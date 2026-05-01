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

local lookup = {'Mage-Frost','Mage-Arcane','Hunter-BeastMastery','DemonHunter-Vengeance','DemonHunter-Devourer','DemonHunter-Havoc','Unknown-Unknown','Druid-Balance','Druid-Feral','Hunter-Marksmanship','Rogue-Subtlety','Monk-Windwalker','Shaman-Enhancement','Paladin-Retribution','Monk-Mistweaver','Warlock-Destruction','Warlock-Demonology','Shaman-Restoration','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Druid-Restoration','DeathKnight-Unholy','Priest-Holy','Priest-Discipline','Warlock-Affliction','DeathKnight-Blood','Warrior-Fury','Paladin-Holy','Priest-Shadow','Druid-Guardian','Warrior-Protection','Shaman-Elemental','Paladin-Protection','Monk-Brewmaster','Hunter-Survival','DeathKnight-Frost','Rogue-Assassination','Rogue-Outlaw','Mage-Fire',}
local provider = {region='US',realm='Drenden',name='US',type='weekly',zone=46,date='2026-05-01',data={Aa='Aaronius:BAAALgAECgYJDgAAAA==.',
Ab='Abbycat:BAAALgADCgQJBAAAAA==.Abundance:BAABLgAECn8eAAMBAAcJBRuMPQB1AQABAAcJBRuMPQB1AQACAAQJ2BeHCwAeAQAAAA==.',
Ad='Addictive:BAAALgADCggJCAAAAA==.Adoe:BAABLgAECn8YAAIDAAcJ4hyYHABbAgADAAcJ4hyYHABbAgAAAA==.Adora:BAAALgAECgUJDQAAAA==.Adër:BAAALgAECgQJBAAAAA==.',
Ae='Aeðn:BAAALgAECgMJBgAAAA==.',
Ag='Agaliarept:BAABLgAECn8VAAMEAAgJxAp1CgD1AAAFAAcJiwbSiwALAQAEAAcJBQt1CgD1AAAAAA==.Agathena:BAAALgADCgEJAQAAAA==.Agathos:BAAALgAECgQJBQAAAA==.',
Ai='Aidan:BAAALgADCgEJAQAAAA==.Aidenator:BAABLgAECn8eAAMGAAcJCxNiIwCiAQAGAAcJCxNiIwCiAQAFAAEJyQO7nAAiAAAAAA==.',
Al='Alger:BAAALgAECgMJAwAAAA==.Aloria:BAAALgAECgEJAgAAAA==.Alrook:BAAALgAECggJDgAAAA==.',
Am='Amoral:BAAALgAECgIJAgAAAA==.',
An='Angelneko:BAAALgAECgYJDgAAAA==.',
Ap='Apylonn:BAAALgADCgEJAQAAAA==.',
Ar='Arakhet:BAAALgADCgYJCQABLgADCgcJBwAHAAAAAA==.Arcaynemoon:BAABLgAECn8XAAIIAAYJWAMyVgDLAAAIAAYJWAMyVgDLAAAAAA==.Arinthian:BAAALgAECgMJAwAAAA==.',
As='Asterior:BAACLgAFFH8MAAIJAAQJdRqqAQBfAQAJAAQJdRqqAQBfAQAuAAQKfx0AAgkACAmlH4sEANICAAkACAmlH4sEANICAAAA.',
Au='Aug:BAAALgAECgEJAQAAAA==.Auley:BAAALgADCgQJBAAAAA==.Auroraa:BAABLgAECn8WAAIIAAYJaAPiKwCvAAAIAAYJaAPiKwCvAAAAAA==.Auyniko:BAAALgADCgQJAwABLgAECgIJAgAHAAAAAA==.',
Av='Avalectra:BAAALgADCgIJAgAAAA==.',
Az='Azmodeaz:BAABLgAECn8ZAAICAAcJuBHTBwCAAQACAAcJuBHTBwCAAQAAAA==.',
Ba='Bajapanti:BAABLgAECn8fAAIKAAcJ/BMjPgBiAQAKAAcJ/BMjPgBiAQAAAA==.Ballyhøø:BAAALgAECggJEAAAAA==.Baxstab:BAABLgAECn8jAAILAAgJdRSdCADkAQALAAgJdRSdCADkAQAAAA==.',
Be='Beahon:BAAALgAECgQJCQAAAA==.Betruger:BAAALgAECgEJAQAAAA==.',
Bg='Bgeefiddy:BAAALgAECgIJAgAAAA==.',
Bi='Bigmuff:BAAALgADCgEJAQAAAA==.Bigsocket:BAAALgAECgYJDAAAAA==.Binglepong:BAAALgAECgMJAwAAAA==.Bingobongo:BAAALgAECgQJBAAAAA==.Bio:BAAALgADCgMJAwAAAA==.',
Bl='Blackpatch:BAABLgAECn8cAAIMAAcJlxrKHAD1AQAMAAcJlxrKHAD1AQAAAA==.Blaqdraco:BAAALgAECgYJCwAAAA==.Blazingballs:BAAALgAECgMJAwAAAA==.Blink:BAEALgAECgQJBgAAAA==.Blitzaga:BAAALgAECgYJCwAAAA==.Bloomsbeam:BAABLgAECn8cAAIFAAgJgBXAHgB6AQAFAAgJgBXAHgB6AQAAAA==.',
Bo='Booneboy:BAAALgAECgYJCgAAAA==.Boptyboopity:BAAALgAECgQJBAAAAA==.Botemedel:BAAALgAECgYJEgABLgAFFAMJBQANAMIIAA==.',
Br='Brennor:BAABLgAECn8kAAIOAAgJtw2vLQCLAQAOAAgJtw2vLQCLAQAAAA==.Brewslunt:BAACLgAFFH8MAAIPAAQJFBbJBwBAAQAPAAQJFBbJBwBAAQAuAAQKfyAAAg8ACAl+IJsNAHoCAA8ACAl+IJsNAHoCAAAA.Briarwyn:BAAALgADCgYJBgAAAA==.Brother:BAAALgAECgQJBAAAAA==.Brujanna:BAAALgAECgEJAQAAAA==.',
Bu='Buttcoin:BAAALgADCgcJCgAAAA==.',
Ca='Caeden:BAAALgAECgUJCQAAAA==.Cairyan:BAAALgAECgcJEAAAAA==.Caiya:BAAALgADCgcJBwABLgAECgcJHwALAIskAA==.Capn:BAAALgADCgcJCAAAAA==.Carvil:BAABLgAECn8kAAMQAAgJMhFnBACVAQAQAAgJMhFnBACVAQARAAMJfwdMdwCXAAAAAA==.Castalia:BAAALgAECgQJBAAAAA==.Cathel:BAAALgADCgEJAQAAAA==.',
Ce='Celenara:BAACLgAFFH8GAAIBAAMJehU8NQD8AAABAAMJehU8NQD8AAAuAAQKfyIAAgEACAm4ISgcAAYDAAEACAm4ISgcAAYDAAAA.Celithe:BAAALgAECgQJCwAAAA==.Cendrian:BAAALgAECgQJBAAAAA==.Cendriel:BAAALgAECgQJBwAAAA==.',
Ch='Charmcaster:BAABLgAECn8kAAIBAAgJ0hzQEgBEAgABAAgJ0hzQEgBEAgAAAA==.Chiafix:BAAALgAECgYJDgABLgAECgcJGAASAH0gAA==.Chipp:BAAALgAFFAEJAgAAAA==.Chleo:BAAALgAECgIJAwAAAA==.Choco:BAACLgAFFH8WAAITAAUJCh+7AwDAAQATAAUJCh+7AwDAAQAuAAQKfyMAAhMACAklIOUFAOgCABMACAklIOUFAOgCAAAA.Chocolat:BAAALgAECgYJDgABLgAFFAUJFgATAAofAA==.Chudster:BAABLgAECn8eAAMUAAgJHBjqAgDNAQAUAAgJHBjqAgDNAQAVAAQJYAcBLwCoAAAAAA==.',
Ci='Cindesh:BAAALgADCgMJAwAAAA==.',
Co='Coggler:BAAALgAECgUJCAAAAA==.Conqueror:BAAALgAECgQJBAABLgAECggJIQAWAO8ZAA==.',
Cr='Crawdaddy:BAAALgAECgYJCgAAAA==.Crawgirl:BAAALgADCgcJCwAAAA==.Crualti:BAAALgAECgQJBwAAAA==.',
Cu='Cupper:BAAALgADCgIJAwABLgAECgYJCgAHAAAAAA==.Curmudge:BAABLgAECn8rAAIWAAgJ9hMmFgDSAQAWAAgJ9hMmFgDSAQAAAA==.',
Cy='Cybele:BAAALgAECgYJCgAAAA==.',
Da='Dakunaito:BAABLgAECn8aAAIXAAcJFCVSDgBQAgAXAAcJFCVSDgBQAgAAAA==.Darachane:BAAALgAECgQJBgAAAA==.',
De='Deafgnome:BAAALgADCggJDAAAAA==.Deathsaber:BAAALgADCgUJBQAAAA==.Deathstars:BAAALgADCgEJAQAAAA==.Deathßite:BAAALgADCgQJBAAAAA==.Deboss:BAAALgAECgQJBAAAAA==.Delianna:BAAALgADCgMJBQAAAA==.Delritha:BAAALgAECgUJEAAAAA==.Deltia:BAAALgAECgYJBgAAAA==.Demonagent:BAAALgAECgYJCgAAAA==.Dermortimer:BAAALgAECgYJCwAAAA==.Desvoker:BAACLgAFFH8NAAMVAAUJ7Bn7CgBVAQAVAAUJ7Bn7CgBVAQAUAAEJ2BYPCQBYAAAuAAQKfyYAAxQACAn4HdMJAEICABQABwkXHdMJAEICABUACAmXFsYbAOoBAAAA.Devessa:BAAALgADCgEJAQAAAA==.Devious:BAAALgAECgYJDgAAAA==.',
Di='Dimebagg:BAAALgADCgMJBQAAAA==.Diorholocene:BAAALgAECgYJEQAAAA==.',
Do='Docspades:BAABLgAECn8UAAMYAAcJMhsnFgBdAQAYAAcJMhsnFgBdAQAZAAMJDgnrRACRAAAAAA==.Dornoch:BAAALgAECgMJAwAAAA==.Dotzilla:BAAALgAECgMJAwAAAA==.',
Dr='Drakeigneel:BAAALgADCgYJCAAAAA==.Dramine:BAAALgAECgIJAwAAAA==.Dremire:BAABLgAECn8YAAIOAAYJUQ47pQA2AQAOAAYJUQ47pQA2AQAAAA==.Drhkillinger:BAAALgADCgkJEQABLgAECgYJCgAHAAAAAA==.Drspades:BAAALgADCgIJAgAAAA==.',
Dx='Dx:BAAALgAFFAEJAQAAAA==.',
['Dé']='Démetal:BAABLgAECn8lAAIXAAgJPyCmCwBtAgAXAAgJPyCmCwBtAgAAAA==.Démi:BAAALgAECgYJDQAAAA==.',
El='Elessaria:BAAALgAECgYJCgAAAA==.Elfatheàrt:BAAALgAECgQJBQAAAA==.Elira:BAAALgAECgEJAQAAAA==.',
Em='Emofurry:BAAALgADCgIJAwAAAA==.',
Er='Eristira:BAAALgADCgcJDAABLgAECgUJDQAHAAAAAA==.',
Es='Esika:BAAALgAFFAEJAgAAAA==.Estherras:BAABLgAECn8eAAIDAAcJ+BZTKgAMAgADAAcJ+BZTKgAMAgAAAA==.',
Et='Ethari:BAAALgADCgUJBQAAAA==.Etternity:BAAALgAECgEJAQAAAA==.',
Ey='Eyvira:BAAALgAECgUJBQAAAA==.',
Fe='Feardotrun:BAAALgAECgYJCwAAAA==.Felicious:BAAALgAECgQJBQAAAA==.',
Fi='Fiach:BAAALgADCgUJBQAAAA==.Finahlia:BAAALgAECgYJEAAAAA==.Finally:BAAALgAECgQJBQAAAA==.Firemage:BAABLgAECn8fAAIRAAgJeSFKDQBEAgARAAgJeSFKDQBEAgAAAA==.Fizzanelf:BAAALgAECgQJBQAAAA==.',
Fo='Forn:BAAALgAECgEJAQAAAA==.',
Fr='Freyá:BAABLgAECn8fAAIOAAgJPxb/UADuAQAOAAgJPxb/UADuAQAAAA==.Friendo:BAABLgAECn8eAAMJAAYJhBM8FABuAQAJAAYJhBM8FABuAQAIAAQJcwYMZQCNAAAAAA==.Frierenn:BAAALgADCgQJBAAAAA==.Frostyflakes:BAAALgAECgYJBgAAAA==.Frylock:BAAALgAECgkJAwAAAA==.',
Fu='Furnost:BAAALgAECgYJEgAAAA==.Futnuraz:BAAALgAECgQJBQAAAA==.',
Fy='Fyriat:BAABLgAECn8eAAIBAAcJYAghuwBrAQABAAcJYAghuwBrAQAAAA==.',
Ge='Getafix:BAAALgADCgYJBgABLgAECgcJGAASAH0gAA==.Gevaudan:BAAALgADCgYJBgAAAA==.',
Gi='Girthquakes:BAAALgAECgQJCQAAAA==.Gizlark:BAAALgADCgUJBQAAAA==.',
Gl='Glenji:BAABLgAECn8bAAIMAAYJVhPjFgAyAQAMAAYJVhPjFgAyAQAAAA==.Glenjin:BAAALgADCgEJAQAAAA==.',
Go='Goodgirl:BAAALgADCgEJAQAAAA==.Gorgmash:BAAALgAECgEJAQAAAA==.',
Gr='Grenswood:BAAALgAECgcJEQAAAA==.Griffindor:BAABLgAECn8YAAIOAAYJaRkLdACTAQAOAAYJaRkLdACTAQAAAA==.Grimfelborn:BAACLgAFFH8GAAIRAAMJMwzsMwDYAAARAAMJMwzsMwDYAAAuAAQKfygAAxEACAm+GrgxAEUCABEACAm+GrgxAEUCABoAAgkUCh4aAKcAAAAA.Grimlinnan:BAAALgAECgMJAwAAAA==.Grondosh:BAAALgAECgQJCgAAAA==.',
Gu='Gummyscales:BAAALgADCgIJAgAAAA==.',
['Gì']='Gìorgìa:BAAALgADCgcJBwAAAA==.',
Ha='Hanicus:BAAALgADCgQJBwAAAA==.Hanoverfiste:BAAALgAECgYJCgAAAA==.Hapsburg:BAABLgAECn8ZAAIPAAcJTBKTEQCTAQAPAAcJTBKTEQCTAQAAAA==.Havince:BAABLgAECn8kAAIbAAgJlx81AwAkAgAbAAgJlx81AwAkAgAAAA==.',
Hi='Higgs:BAAALgAECgMJAwAAAA==.',
Ho='Holyball:BAABLgAECn8fAAIOAAcJyBykXADNAQAOAAcJyBykXADNAQAAAA==.',
Hu='Hughjahsol:BAAALgADCgYJCQAAAA==.Hustlîn:BAAALgADCgEJAQAAAA==.Huulkster:BAAALgADCgEJAQAAAA==.',
['Hê']='Hêra:BAAALgADCgYJBgAAAA==.',
Il='Illidai:BAAALgAECgQJCQAAAA==.Ilyndra:BAAALgAECgYJDgAAAA==.',
In='Infernella:BAAALgAECgMJAwAAAA==.',
Ir='Iristail:BAAALgAECgQJBQAAAA==.Ironskin:BAAALgADCgIJAgAAAA==.',
Is='Iselilja:BAABLgAECn8eAAIcAAcJCBPeGABpAQAcAAcJCBPeGABpAQAAAA==.',
It='Ithea:BAAALgAECgcJEwAAAA==.',
Ja='Jaeson:BAABLgAECn8WAAIRAAgJKxD0IgCmAQARAAgJKxD0IgCmAQAAAA==.Jaiya:BAAALgADCggJCAAAAA==.Jason:BAAALgAECgMJAwAAAA==.Javoren:BAAALgAECgcJCwABLgAFFAUJEwAdABwUAA==.',
Je='Jeef:BAAALgADCgEJAQABLgAECggJCAAHAAAAAA==.Jeefrenzy:BAAALgAECggJCAAAAA==.Jeffha:BAAALgAECgYJEQAAAA==.',
Ji='Jimothy:BAAALgAECgQJBwAAAA==.',
Jo='Joap:BAAALgAECgQJBwAAAA==.Joejr:BAABLgAECn8WAAMZAAYJgxSYFgA7AQAZAAYJgxSYFgA7AQAeAAQJ+BOLPwD6AAAAAA==.Jonald:BAAALgADCgUJBQAAAA==.',
Jt='Jtizlfrizl:BAAALgAECgYJCgAAAA==.',
Jw='Jwise:BAAALgADCgcJCgAAAA==.',
Ka='Kajowsmage:BAAALgADCgcJBwAAAA==.Kalierix:BAAALgAECgQJBAAAAA==.Kaloesh:BAAALgAECgcJEwAAAA==.Kanabat:BAAALgAECgQJBQAAAA==.Karawyn:BAABLgAECn8XAAIDAAgJCg45PQC5AQADAAgJCg45PQC5AQABLgADCgUJBQAHAAAAAA==.Katrishy:BAACLgAFFH8GAAIeAAMJlxBZDQDwAAAeAAMJlxBZDQDwAAAuAAQKfyUAAx4ACAlQHYIWADMCAB4ACAlQHYIWADMCABgAAQlwBTyIACcAAAAA.Kazeral:BAAALgADCgQJBwAAAA==.',
Ke='Keedrid:BAAALgAECgcJCwAAAA==.Keindis:BAAALgADCgYJBgABLgAECgQJBgAHAAAAAA==.Kelemenohpea:BAABLgAECn8VAAIFAAYJXwiQSADMAAAFAAYJXwiQSADMAAAAAA==.',
Kn='Knoll:BAAALgAECgQJBQAAAA==.',
Ko='Kode:BAAALgAECgQJCgAAAA==.',
Kr='Kreeona:BAABLgAECn8YAAISAAcJfSCeGQBKAgASAAcJfSCeGQBKAgAAAA==.Kruàlty:BAAALgAECgQJCgAAAA==.',
Ku='Kungpow:BAAALgADCgIJAgAAAA==.',
Le='Legreebash:BAAALgADCgIJAgABLgAECgEJAQAHAAAAAA==.Legreecast:BAAALgAECgEJAQAAAA==.',
Li='Liasong:BAAALgADCgUJBQAAAA==.Litespeed:BAAALgADCgEJAQAAAA==.Litheliice:BAABLgAECn8jAAIYAAgJNBCMEACfAQAYAAgJNBCMEACfAQAAAA==.',
Lo='Lodur:BAABLgAECn8eAAISAAcJLR3OIAAaAgASAAcJLR3OIAAaAgAAAA==.Lofurious:BAAALgADCgIJAgAAAA==.Lonen:BAEBLgAECn8dAAIfAAYJDBdAEABzAQAfAAYJDBdAEABzAQAAAA==.Losat:BAABLgAECn8fAAIgAAcJQgthJwAEAQAgAAcJQgthJwAEAQAAAA==.',
Lu='Lugrat:BAAALgADCgEJAQAAAA==.Luguna:BAAALgAECgYJDwAAAA==.Lunári:BAAALgAECgEJAQAAAA==.Luraina:BAAALgADCgEJAQABLgAECgUJBQAHAAAAAA==.Luthian:BAAALgADCgMJAwAAAA==.',
Ly='Lycinder:BAAALgAECgEJAQAAAA==.',
['Lî']='Lîîght:BAAALgADCgEJAQAAAA==.',
Ma='Mackavelian:BAAALgAECgEJAQABLgAECgYJCgAHAAAAAA==.Mackkie:BAAALgAECgYJCgAAAA==.Madonkadonk:BAABLgAECn8kAAIUAAgJSg0YBACUAQAUAAgJSg0YBACUAQAAAA==.Maedai:BAABLgAECn8jAAIPAAgJSxjjBwA7AgAPAAgJSxjjBwA7AgAAAA==.Maeli:BAAALgADCgkJDQAAAA==.Magladroth:BAAALgAECgEJAQAAAA==.Magnaball:BAABLgAECn8qAAMdAAgJrR07DAATAgAdAAgJrR07DAATAgAOAAEJOxD2SgEvAAAAAA==.Magús:BAAALgADCgEJAgAAAA==.Maldive:BAABLgAECn8eAAIRAAcJwBNHOgBFAQARAAcJwBNHOgBFAQAAAA==.Maligasia:BAAALgAECgMJAwAAAA==.Mallicia:BAABLgAECn8hAAIYAAgJLiSYAwAgAwAYAAgJLiSYAwAgAwAAAA==.Mallika:BAAALgAECgcJEwABLgAECggJIQAYAC4kAA==.Mallwizard:BAABLgAECn8hAAIRAAgJYhaROAApAgARAAgJYhaROAApAgAAAA==.Mangopewpew:BAAALgAECgQJCAAAAA==.Martris:BAAALgADCgQJBAAAAA==.Massoflice:BAABLgAECn8bAAIXAAgJ9RXnagC2AQAXAAgJ9RXnagC2AQAAAA==.Maxblaide:BAAALgAECgUJBQAAAA==.Maxilla:BAAALgADCgcJBwABLgAECggJKgAdAK0dAA==.',
Me='Meridians:BAAALgAECgYJEwAAAA==.',
Mh='Mhataharii:BAAALgADCgIJAgAAAA==.',
Mi='Mindhorn:BAABLgAECn8kAAMhAAgJFyH7AgCsAgAhAAgJFyH7AgCsAgASAAQJAhWnTgBlAAAAAA==.Misstangy:BAAALgAECgQJBQAAAA==.',
Mo='Moct:BAABLgAECn8fAAIiAAcJwBioEAC8AQAiAAcJwBioEAC8AQAAAA==.Moomooduck:BAAALgAECgEJAQAAAA==.',
Mu='Mudskipper:BAAALgAECggJEwAAAA==.Muradox:BAAALgADCgQJBAABLgAECggJFAAVALINAA==.Mustardhunt:BAAALgADCgQJBQAAAA==.',
My='Myriad:BAABLgAECn8eAAIgAAcJrx4eDABJAgAgAAcJrx4eDABJAgAAAA==.',
Na='Nakze:BAABLgAECn8eAAILAAcJ+wrZLwCGAQALAAcJ+wrZLwCGAQAAAA==.Namanari:BAAALgADCgkJCQAAAA==.Nastyfigs:BAAALgAECgYJEwAAAA==.Nazca:BAAALgADCgcJCgAAAA==.',
Ne='Necrochade:BAAALgAECgEJAQAAAA==.',
Nh='Nhilas:BAAALgAECgEJAwAAAA==.',
Ni='Nishal:BAAALgADCgkJEgAAAA==.',
Ny='Nyxaries:BAAALgAECgUJCAAAAA==.',
Ob='Oblivioso:BAAALgADCgYJBgAAAA==.',
Ol='Olåf:BAAALgADCgkJCQAAAA==.',
Pa='Pablo:BAAALgAECgQJBAAAAA==.Paladus:BAAALgAECgMJAwAAAA==.Panzerblitz:BAAALgAECgYJDgAAAA==.Papers:BAAALgADCgEJAQAAAA==.Pargath:BAABLgAECn8YAAIQAAcJNQoKIABSAQAQAAcJNQoKIABSAQAAAA==.Pasìthea:BAAALgADCgcJCQAAAA==.',
Pe='Pengu:BAAALgAECgQJBgAAAA==.',
Pi='Pillow:BAABLgAECn8UAAIDAAYJNCAnKgANAgADAAYJNCAnKgANAgAAAA==.Pillowdin:BAAALgAECgIJAwAAAA==.Pilson:BAAALgAECgYJDQAAAA==.Pinkytails:BAAALgADCgcJBwAAAA==.Piseyi:BAAALgAECgMJAwAAAA==.',
Po='Poonwagoon:BAAALgADCgYJCAAAAA==.',
Pr='Predacon:BAAALgAECgYJDQAAAA==.Pretzelz:BAAALgADCgYJCgAAAA==.Priesthealer:BAAALgADCgYJBgAAAA==.',
Pu='Puffer:BAABLgAECn8fAAIBAAcJnw/cSABUAQABAAcJnw/cSABUAQAAAA==.',
Ra='Raito:BAAALgAECgcJDwAAAA==.Rakshasa:BAABLgAECn8eAAMRAAgJcSImBwCbAgARAAgJcSImBwCbAgAaAAEJAACvIQBrAAAAAA==.Ranilynn:BAAALgADCgYJBgABLgAECgUJDQAHAAAAAA==.Rasetsungo:BAAALgAECgcJDQAAAA==.Raura:BAAALgAECgMJAwAAAA==.',
Re='Recalcitrent:BAAALgADCgYJCAAAAA==.Redblueblurr:BAAALgAECgUJBQAAAA==.Remi:BAAALgAECggJCAAAAA==.Reveillark:BAAALgAECgQJCQAAAA==.',
Ro='Rolan:BAABLgAECn8YAAIXAAgJvSNoHwDFAgAXAAgJvSNoHwDFAgAAAA==.Rosalian:BAABLgAECn8eAAIWAAcJkxzjEQD9AQAWAAcJkxzjEQD9AQAAAA==.Rotiko:BAABLgAECn8YAAISAAcJKgwbJABIAQASAAcJKgwbJABIAQAAAA==.Roweene:BAAALgAECgYJDQAAAA==.',
Sa='Saintseven:BAAALgAECgUJEQAAAA==.Salamander:BAAALgADCgYJBgAAAA==.Savior:BAAALgADCggJGQAAAA==.',
Se='Seiko:BAAALgADCgEJAQAAAA==.Selaphiel:BAAALgAECgMJAwAAAA==.Selvey:BAAALgADCgUJBwAAAA==.Sensei:BAABLgAECn8eAAMMAAcJTx5eFwAqAgAMAAYJJCJeFwAqAgAjAAEJJAs2hQA8AAAAAA==.Serenatee:BAABLgAECn8iAAIeAAgJwgxMEACKAQAeAAgJwgxMEACKAQAAAA==.',
Sh='Shadowkrak:BAAALgADCgMJAwAAAA==.Shamill:BAAALgADCgMJAwAAAA==.Shammyball:BAAALgADCgcJBwAAAA==.Shamwow:BAAALgADCggJDgAAAA==.Shobe:BAAALgAECgQJCQAAAA==.Shouhuzhee:BAABLgAECn8VAAIFAAgJchKWFwCrAQAFAAgJchKWFwCrAQAAAA==.Shåde:BAAALgADCgYJDQAAAA==.Shócker:BAAALgADCgMJAwAAAA==.',
Si='Sike:BAAALgADCgYJBgAAAA==.Simbà:BAAALgAECgYJDgAAAA==.',
Sl='Sleep:BAAALgADCgYJBgAAAA==.Sluicewrld:BAABLgAECn8XAAMFAAcJGSHFIQCGAgAFAAcJGSHFIQCGAgAGAAEJ9hZRawA7AAABLgAECggJCAAHAAAAAA==.',
Sn='Snorlacks:BAAALgAECgQJBAAAAA==.Snortedgfuel:BAAALgAECgYJDQAAAA==.',
So='Sokroar:BAAALgAECgQJBAAAAA==.Sonknight:BAAALgAECgQJCwAAAA==.',
Sp='Sparkticus:BAABLgAECn8cAAIhAAgJYh0iBQBmAgAhAAgJYh0iBQBmAgAAAA==.Spiky:BAAALgADCggJDQAAAA==.Spitefulcrow:BAABLgAECn8dAAIkAAYJMA3gFQAWAQAkAAYJMA3gFQAWAQAAAA==.Sporak:BAAALgADCgIJAgAAAA==.',
St='Stardstr:BAAALgAECgIJBAAAAA==.Sto:BAAALgAECgcJDAAAAA==.Stubz:BAAALgAECgYJBwAAAA==.',
Su='Supad:BAAALgADCgYJBwAAAA==.Superball:BAAALgAECgQJCgABLgAECggJKgAdAK0dAA==.Superjpriest:BAAALgAECgMJAwAAAA==.Suria:BAABLgAECn8fAAIWAAcJVh4DLwDwAQAWAAcJVh4DLwDwAQAAAA==.',
Sw='Swiskimohunr:BAAALgADCgMJAwAAAA==.Swàt:BAAALgADCgUJBQAAAA==.',
Sy='Syker:BAAALgAECgUJBQAAAA==.Syloc:BAAALgAECgEJAQAAAA==.',
Ta='Tahrovin:BAAALgADCggJEwAAAA==.Talaera:BAAALgAECgUJBQAAAA==.Tannastia:BAAALgAECgQJBwAAAA==.Tatem:BAAALgADCgcJEwAAAA==.Taurunter:BAAALgAECgMJAwAAAA==.Tavistreea:BAAALgAECgYJDQAAAA==.Taystee:BAAALgADCgYJBgAAAA==.Taytorchips:BAABLgAECn8iAAMdAAcJPgTxZwDbAAAdAAYJLATxZwDbAAAOAAYJWAV0+ACiAAAAAA==.',
Th='Thelm:BAAALgADCgMJAwAAAA==.Thevoid:BAAALgADCgMJAwAAAA==.Thiccsmoke:BAAALgADCgIJAgAAAA==.Thoneous:BAAALgAECgYJBgAAAA==.Thornten:BAAALgAECgYJEAAAAA==.Thundercups:BAABLgAECn8kAAINAAgJnBuAAgBFAgANAAgJnBuAAgBFAgAAAA==.',
Ti='Tigerstarr:BAAALgAFFAEJAQAAAA==.Timboslicé:BAAALgAECgcJCwAAAA==.Tinyshieva:BAAALgAECgYJEwAAAA==.Tizuki:BAAALgAECgIJAgAAAA==.',
To='Tokey:BAAALgAECgUJDQAAAA==.Toriael:BAAALgAECgcJBwAAAA==.',
Tr='Trashlock:BAAALgADCgYJBgAAAA==.Treasure:BAAALgAECgYJEAAAAA==.Treborlock:BAABLgAECn8YAAIQAAYJghjeBwAzAQAQAAYJghjeBwAzAQAAAA==.Treenn:BAAALgAECgMJAwAAAA==.Triplock:BAAALgADCgMJBQAAAA==.Trolcain:BAAALgAECgcJEwAAAA==.Trolmed:BAAALgAECgYJDAABLgAECgcJEwAHAAAAAA==.',
Ty='Tyrix:BAAALgAECgYJCgAAAA==.Tyránt:BAABLgAECn8gAAMDAAgJtCD+LQD6AQADAAgJtCD+LQD6AQAKAAEJAADOmwAQAAAAAA==.',
Ul='Ulfal:BAABLgAECn8XAAIjAAYJ2BkQJADmAAAjAAYJ2BkQJADmAAAAAA==.',
Va='Vagglord:BAABLgAECn8WAAIBAAUJoyX6MwCVAQABAAUJoyX6MwCVAQAAAA==.Valadir:BAAALgAECgQJCAAAAA==.Valerossi:BAABLgAECn8dAAIkAAYJXR8JDQD6AQAkAAYJXR8JDQD6AQAAAA==.Valha:BAABLgAECn8fAAIGAAgJxBC6CQCmAQAGAAgJxBC6CQCmAQAAAA==.Vanorick:BAAALgAECgEJAgAAAA==.Vardisk:BAAALgADCgYJBgAAAA==.Varleyna:BAAALgAECgMJAwABLgAECggJIQAYAC4kAA==.Varteras:BAABLgAECn8kAAMRAAgJ8xW4JgCUAQARAAcJGBO4JgCUAQAaAAUJjBMyDgBPAQAAAA==.',
Ve='Veleiri:BAAALgAECgYJDgAAAA==.Velenal:BAAALgAECgEJAwAAAA==.Vellron:BAABLgAECn8VAAIDAAcJrwkdQgAOAQADAAcJrwkdQgAOAQAAAA==.',
Vu='Vurkaal:BAAALgADCgYJBgAAAA==.',
['Và']='Vàsh:BAAALgAECgIJAgAAAA==.',
Wa='Wafflelegend:BAAALgAECgYJEgAAAA==.Wardkbriggle:BAABLgAFFH8GAAIbAAIJ4RcxDwB3AAAbAAIJ4RcxDwB3AAAAAA==.Warlover:BAAALgADCgYJCgAAAA==.Wartiger:BAACLgAFFH8UAAIjAAUJjBubCABSAQAjAAUJjBubCABSAQAuAAQKfxYAAiMACAmBICEVAGMCACMACAmBICEVAGMCAAAA.',
Wo='Wolfdude:BAABLgAECn8XAAMbAAYJeQWANwCGAAAbAAQJGQaANwCGAAAlAAUJ9QH+EgBiAAAAAA==.',
Wy='Wydge:BAABLgAECn8UAAIBAAYJcwyOYgAWAQABAAYJcwyOYgAWAQAAAA==.Wymonath:BAAALgAECgMJAwAAAA==.',
Xa='Xanddoria:BAABLgAECn8fAAQLAAcJiySvBABAAgAmAAYJUSQTBAB1AgALAAcJBiKvBABAAgAnAAYJvR0AAAAAAAAAAA==.Xannydevito:BAAALgAECgYJEwAAAA==.',
Xe='Xellioth:BAAALgAECgYJEQAAAA==.Xenti:BAAALgADCgcJBwABLgAECgcJHwALAIskAA==.',
Xh='Xhared:BAABLgAECn8ZAAIbAAcJqR8ZBAAIAgAbAAcJqR8ZBAAIAgAAAA==.',
Ya='Yahtzee:BAAALgADCgUJAwAAAA==.Yaosi:BAAALgAECgEJAQAAAA==.Yatorishino:BAAALgAECgYJDwAAAA==.',
Ze='Zephy:BAAALgAECgMJAwAAAA==.',
Zo='Zom:BAAALgADCgkJGgAAAA==.',
['Ël']='Ëlle:BAAALgADCgEJAQAAAA==.',
['Öz']='Öz:BAABLgAECn8wAAMoAAkJmR8lAAD5AgAoAAkJmR8lAAD5AgABAAQJsheX+QAHAQAAAA==.',
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

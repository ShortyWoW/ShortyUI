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

local lookup = {'Priest-Holy','Mage-Frost','Mage-Arcane','Hunter-BeastMastery','DemonHunter-Vengeance','DemonHunter-Devourer','DemonHunter-Havoc','Druid-Balance','Unknown-Unknown','Druid-Feral','Hunter-Marksmanship','Rogue-Subtlety','Monk-Windwalker','Warlock-Demonology','Paladin-Retribution','Paladin-Protection','Shaman-Enhancement','Monk-Mistweaver','Warlock-Destruction','Monk-Brewmaster','Shaman-Restoration','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Druid-Restoration','DeathKnight-Unholy','Priest-Discipline','DeathKnight-Frost','Warlock-Affliction','DeathKnight-Blood','Warrior-Arms','Warrior-Fury','Paladin-Holy','Priest-Shadow','Druid-Guardian','Warrior-Protection','Shaman-Elemental','Hunter-Survival','Rogue-Assassination','Rogue-Outlaw','Mage-Fire',}
local provider = {region='US',realm='Drenden',name='US',type='weekly',zone=46,date='2026-05-08',data={Aa='Aaronius:BAABLgAECn8UAAIBAAYJ0wSWLgDYAAABAAYJ0wSWLgDYAAAAAA==.',
Ab='Abbycat:BAAALgADCgQJBAAAAA==.Abundance:BAABLgAECn8mAAMCAAgJQxuMGwBEAgACAAgJQxuMGwBEAgADAAQJ2BeICwAeAQAAAA==.',
Ad='Addictive:BAAALgADCggJCAAAAA==.Adoe:BAABLgAECn8iAAIEAAgJuCC9CQCaAgAEAAgJuCC9CQCaAgAAAA==.Adora:BAAALgAECgUJDQAAAA==.Adril:BAAALgAECgMJAwAAAA==.Adër:BAAALgAECgQJBAAAAA==.',
Ae='Aeðn:BAAALgAECgYJDAAAAA==.',
Ag='Agaliarept:BAABLgAECn8WAAMFAAgJFAuLDgDYAAAGAAcJ6QbYiwALAQAFAAcJBQuLDgDYAAAAAA==.Agathena:BAAALgADCgEJAQAAAA==.Agathos:BAAALgAECgQJCQAAAA==.',
Ai='Aidan:BAAALgADCgEJAQAAAA==.Aidenator:BAABLgAECn8oAAMHAAgJexMhDQCvAQAHAAgJexMhDQCvAQAGAAEJxgMZzQAiAAAAAA==.',
Ak='Akumajoe:BAAALgADCgYJBgAAAA==.',
Al='Alger:BAAALgAECgMJAwAAAA==.Aloria:BAAALgAECgEJBAAAAA==.Alrook:BAAALgAECggJDwAAAA==.',
Am='Amoral:BAAALgAECgIJAgAAAA==.',
An='Angelneko:BAABLgAECn8UAAIIAAYJ2AqlKwDqAAAIAAYJ2AqlKwDqAAAAAA==.',
Ap='Apylonn:BAAALgADCgEJAQAAAA==.',
Ar='Arakhet:BAAALgADCgYJCQABLgADCgcJBwAJAAAAAA==.Arcaynemoon:BAABLgAECn8XAAIIAAYJWAM1VgDLAAAIAAYJWAM1VgDLAAAAAA==.Arinthian:BAAALgAECgMJAwAAAA==.',
As='Asterior:BAACLgAFFH8OAAIKAAUJcBpiAQBxAQAKAAUJcBpiAQBxAQAuAAQKfx0AAgoACAmlH4wEANICAAoACAmlH4wEANICAAAA.',
Au='Aug:BAAALgAECgIJAgABLgAECggJDQAJAAAAAA==.Auley:BAAALgADCgQJBAAAAA==.Auroraa:BAABLgAECn8XAAIIAAYJtgOPNwCtAAAIAAYJtgOPNwCtAAAAAA==.Auyniko:BAAALgADCgQJAwABLgAECgIJAgAJAAAAAA==.',
Av='Avalectra:BAAALgAECgMJAwAAAA==.',
Az='Azmodeaz:BAABLgAECn8aAAIDAAcJuBHTBwCAAQADAAcJuBHTBwCAAQAAAA==.',
Ba='Bajapanti:BAABLgAECn8oAAILAAgJlBjPAwARAgALAAgJlBjPAwARAgAAAA==.Ballyhøø:BAAALgAECggJEwAAAA==.Banchory:BAAALgADCgIJAgAAAA==.Baxstab:BAABLgAECn8qAAIMAAkJ/BrWAwCYAgAMAAkJ/BrWAwCYAgAAAA==.',
Be='Beahon:BAAALgAECgQJCQAAAA==.Betruger:BAAALgAECgEJAQAAAA==.',
Bg='Bgeefiddy:BAAALgAECgIJAgAAAA==.',
Bi='Bigmuff:BAAALgADCgEJAQAAAA==.Bignheavy:BAAALgAECgQJBgAAAA==.Bigsocket:BAAALgAECgYJDAAAAA==.Binglepong:BAAALgAECgMJAwAAAA==.Bingobongo:BAAALgAECgQJBAAAAA==.Bio:BAAALgADCgMJAwAAAA==.',
Bl='Blackpatch:BAABLgAECn8lAAINAAgJdiENBACuAgANAAgJdiENBACuAgAAAA==.Blaqdraco:BAAALgAECgYJCwAAAA==.Blaqsun:BAAALgAECgMJAwAAAA==.Blazen:BAAALgAECgMJAwAAAA==.Blazingballs:BAAALgAECgMJAwAAAA==.Blink:BAEALgAECgQJBgAAAA==.Blitzaga:BAAALgAECgYJDAAAAA==.Blooming:BAAALgAECgYJBgABLgAECgcJFAAOAAYYAA==.Bloomsbeam:BAABLgAECn8cAAIGAAgJgBVfMAB1AQAGAAgJgBVfMAB1AQAAAA==.',
Bo='Booneboy:BAAALgAECgYJEAAAAA==.Boptyboopity:BAAALgAECgQJBQAAAA==.Botemedel:BAABLgAECn8WAAMPAAcJowvXeAD6AAAPAAcJiwrXeAD6AAAQAAYJowl3JQDdAAABLgAFFAMJCAARAGkNAA==.',
Br='Brennor:BAABLgAECn8qAAIPAAkJZA0mLgDEAQAPAAkJZA0mLgDEAQAAAA==.Brewslunt:BAACLgAFFH8OAAISAAUJRBjUCgBuAQASAAUJRBjUCgBuAQAuAAQKfyMAAxIACAl+IJwNAHoCABIACAl+IJwNAHoCAA0AAwm+CyM4AKAAAAAA.Briarwyn:BAAALgADCgYJBgAAAA==.Brother:BAAALgAECgQJBAAAAA==.Brujanna:BAAALgAECgEJAQAAAA==.',
Bu='Buttcoin:BAAALgADCgcJCgAAAA==.',
Ca='Caeden:BAAALgAECgYJCwAAAA==.Cairyan:BAABLgAECn8UAAIFAAgJXhlLDQCDAQAFAAgJXhlLDQCDAQAAAA==.Caiya:BAAALgADCgcJBwABLgAECggJJgAMAA8kAA==.Capn:BAAALgADCgcJCAAAAA==.Carvil:BAABLgAECn8qAAMTAAkJNxNUAwD0AQATAAkJNxNUAwD0AQAOAAMJhwc2mACQAAAAAA==.Castalia:BAAALgAECgQJBAAAAA==.Cathel:BAAALgADCgEJAQAAAA==.',
Ce='Celenara:BAACLgAFFH8IAAICAAMJexW8SgDzAAACAAMJexW8SgDzAAAuAAQKfyUAAgIACAnFISgcAAYDAAIACAnFISgcAAYDAAAA.Celithe:BAAALgAECgUJDwAAAA==.Cendrian:BAAALgAECgYJCgAAAA==.Cendriel:BAAALgAECgQJBwAAAA==.',
Ch='Charmcaster:BAABLgAECn8kAAICAAgJ0hy2HQA4AgACAAgJ0hy2HQA4AgAAAA==.Chiafix:BAABLgAECn8UAAIUAAcJowm8JgANAQAUAAcJowm8JgANAQABLgAECggJIAAVAC0hAA==.Chipp:BAAALgAFFAEJAgAAAA==.Chleo:BAAALgAECgIJAwAAAA==.Choco:BAACLgAFFH8cAAIWAAYJih9fAgAtAgAWAAYJih9fAgAtAgAuAAQKfyMAAhYACAklIOQFAOgCABYACAklIOQFAOgCAAAA.Chocolat:BAAALgAECgYJDgABLgAFFAYJHAAWAIofAA==.Chudster:BAABLgAECn8eAAMXAAgJHBhTBACyAQAXAAgJHBhTBACyAQAYAAQJYAdmPQCnAAAAAA==.',
Ci='Cindesh:BAAALgADCgMJAwAAAA==.',
Co='Coggler:BAAALgAECgUJDQAAAA==.Conqueror:BAAALgAECgYJCgABLgAECggJKQAZAD4bAA==.',
Cr='Crawdaddy:BAAALgAECgYJEAAAAA==.Crawgirl:BAAALgAECgEJAQAAAA==.Crualti:BAAALgAECgQJCAAAAA==.',
Cu='Cupper:BAAALgADCgIJAwABLgAECgYJEAAJAAAAAA==.Curmudge:BAABLgAECn8yAAIZAAkJNhN8FgARAgAZAAkJNhN8FgARAgAAAA==.',
Cy='Cyaani:BAAALgADCgMJAwABLgADCgYJBgAJAAAAAA==.Cybele:BAAALgAECgYJEAAAAA==.',
Da='Dakunaito:BAABLgAECn8aAAIaAAcJFCWzFwA+AgAaAAcJFCWzFwA+AgAAAA==.Darachane:BAAALgAECgQJCgAAAA==.',
De='Deafgnome:BAAALgADCggJDAAAAA==.Deathsaber:BAAALgADCgUJCAAAAA==.Deathstars:BAAALgADCgEJAQAAAA==.Deathßite:BAAALgADCgQJBAAAAA==.Deboss:BAAALgAECgQJBAAAAA==.Delianna:BAAALgADCgMJBQAAAA==.Delritha:BAAALgAECgUJEAAAAA==.Deltia:BAAALgAECgYJDAAAAA==.Demonagent:BAAALgAECgYJCgAAAA==.Dermortimer:BAAALgAECgYJCwAAAA==.Desvoker:BAACLgAFFH8QAAMYAAUJiRoZDwBYAQAYAAUJiRoZDwBYAQAXAAEJ2BYSCQBYAAAuAAQKfygAAxcACQkuHtYJAEICABcACQkCHNYJAEICABgACAmXFsIbAOoBAAAA.Devessa:BAAALgADCgEJAQAAAA==.Devious:BAABLgAECn8UAAIOAAcJBhg/KwC4AQAOAAcJBhg/KwC4AQAAAA==.',
Di='Dimebagg:BAAALgAECgEJAQAAAA==.Diorholocene:BAAALgAECgYJEQAAAA==.',
Do='Docspades:BAABLgAECn8aAAMBAAcJNBxTEgDOAQABAAcJNBxTEgDOAQAbAAMJDgntRACRAAAAAA==.Dornoch:BAAALgAECgQJBwAAAA==.Dotzilla:BAAALgAECgQJBwAAAA==.',
Dr='Drakeigneel:BAAALgADCgYJCAAAAA==.Dramine:BAAALgAECgMJBgAAAA==.Dremire:BAABLgAECn8iAAIPAAgJagwRRwBwAQAPAAgJagwRRwBwAQAAAA==.Drhkillinger:BAAALgADCgkJEQABLgAECgYJCgAJAAAAAA==.Drspades:BAAALgADCgIJAgAAAA==.',
Dx='Dx:BAAALgAFFAIJBAAAAA==.',
['Dé']='Démetal:BAACLgAFFH8FAAIaAAMJZQ41UADvAAAaAAMJZQ41UADvAAAuAAQKfyYAAhoACAk/ID0UAFkCABoACAk/ID0UAFkCAAAA.Démi:BAAALgAECgYJDQAAAA==.',
Ed='Edrem:BAAALgADCgEJAQAAAA==.',
El='Elessaria:BAAALgAECgYJEAAAAA==.Elfatheàrt:BAAALgAECgQJCQAAAA==.Elira:BAAALgAECgEJAQAAAA==.',
Em='Emofurry:BAAALgADCgIJAwAAAA==.',
Er='Eristira:BAAALgADCgcJDAABLgAECgUJDQAJAAAAAA==.',
Es='Esika:BAAALgAFFAEJAgAAAA==.Estherras:BAABLgAECn8mAAIEAAgJsBVeHADzAQAEAAgJsBVeHADzAQAAAA==.',
Et='Ethari:BAAALgADCgUJBQAAAA==.Etternity:BAAALgAECgEJAQAAAA==.',
Ey='Eyvira:BAAALgAECgUJBQAAAA==.',
Fe='Feardotrun:BAABLgAECn8QAAMOAAYJ8Qn3ZgD/AAAOAAYJzQn3ZgD/AAATAAEJkxAOJwA4AAAAAA==.Felicious:BAAALgAECgQJCQAAAA==.Feralclaw:BAAALgAECgUJBQAAAA==.',
Fi='Fiach:BAAALgADCgUJBQAAAA==.Finahlia:BAABLgAECn8VAAIZAAcJvyEcCwCXAgAZAAcJvyEcCwCXAgAAAA==.Finally:BAAALgAECgQJCQAAAA==.Firemage:BAABLgAECn8gAAIOAAgJeSEREwBKAgAOAAgJeSEREwBKAgAAAA==.Fizzanelf:BAAALgAECgQJCQAAAA==.',
Fo='Forn:BAAALgAECgEJAQAAAA==.',
Fr='Freyá:BAABLgAECn8lAAIPAAkJQhX/UADuAQAPAAkJQhX/UADuAQAAAA==.Friendo:BAABLgAECn8nAAMKAAgJxhKDBwC+AQAKAAgJxhKDBwC+AQAIAAQJcwYXZQCNAAAAAA==.Frierenn:BAAALgADCgQJBAAAAA==.Frostyflakes:BAAALgAECgYJBwAAAA==.Frylock:BAAALgAECgkJAwAAAA==.',
Fu='Furnost:BAABLgAECn8bAAIcAAgJrhTEAwDHAQAcAAgJrhTEAwDHAQAAAA==.Futnuraz:BAAALgAECgQJCQAAAA==.',
Fy='Fyriat:BAABLgAECn8oAAICAAgJZQljVQBsAQACAAgJZQljVQBsAQAAAA==.',
Ge='Getafix:BAAALgAECgEJAQABLgAECggJIAAVAC0hAA==.Gevaudan:BAAALgADCgYJBgAAAA==.',
Gi='Girthquakes:BAAALgAECgQJCQAAAA==.Gizlark:BAAALgADCgUJBQAAAA==.',
Gl='Glenji:BAABLgAECn8bAAINAAYJVhO1HgAuAQANAAYJVhO1HgAuAQAAAA==.Glenjin:BAAALgADCgEJAQAAAA==.',
Go='Goodgirl:BAAALgADCgEJAQAAAA==.Gorgmash:BAAALgAECgEJAQAAAA==.',
Gr='Grenswood:BAABLgAECn8XAAITAAgJiBcjBwB3AQATAAgJiBcjBwB3AQAAAA==.Greybark:BAAALgADCgIJAgAAAA==.Griffindor:BAABLgAECn8hAAIPAAgJrBeEKwDQAQAPAAgJrBeEKwDQAQAAAA==.Grimfelborn:BAACLgAFFH8KAAIOAAQJIg0LMgAGAQAOAAQJIg0LMgAGAQAuAAQKfysAAw4ACAnRGrUxAEUCAA4ACAnRGrUxAEUCAB0AAgkUCh8aAKcAAAAA.Grimlinnan:BAAALgAECgMJAwAAAA==.Grondosh:BAAALgAECgYJEAAAAA==.Gryffan:BAAALgADCgEJAQAAAA==.',
Gu='Gummyscales:BAAALgADCgIJAgAAAA==.',
['Gì']='Gìorgìa:BAAALgADCgcJBwAAAA==.',
Ha='Hanicus:BAAALgADCgYJCwAAAA==.Hanoverfiste:BAAALgAECgYJEAAAAA==.Hapsburg:BAABLgAECn8fAAISAAkJHxAEEQDhAQASAAkJHxAEEQDhAQAAAA==.Havince:BAABLgAECn8qAAIeAAkJxSANAgDhAgAeAAkJxSANAgDhAgAAAA==.',
Hi='Higgs:BAAALgAECgMJAwAAAA==.',
Ho='Holyball:BAABLgAECn8mAAIPAAgJNx+DDgCKAgAPAAgJNx+DDgCKAgAAAA==.',
Hu='Hughjahsol:BAAALgADCgYJCQAAAA==.Hustlîn:BAAALgADCgEJAQAAAA==.Huulkster:BAAALgAECgQJBAAAAA==.',
['Hê']='Hêra:BAAALgADCgYJBgAAAA==.',
Id='Idan:BAAALgADCgEJAQAAAA==.',
Il='Illidai:BAAALgAECgYJDgAAAA==.Ilyndra:BAABLgAECn8UAAIfAAYJ+huNCgCdAQAfAAYJ+huNCgCdAQAAAA==.',
In='Infernella:BAAALgAECgMJAwAAAA==.',
Ir='Iristail:BAAALgAECgQJBQAAAA==.Ironskin:BAAALgADCgIJAgAAAA==.',
Is='Iselilja:BAABLgAECn8oAAIgAAgJpxVMEADzAQAgAAgJpxVMEADzAQAAAA==.',
It='Ithea:BAABLgAECn8ZAAICAAcJ8RkwRACaAQACAAcJ8RkwRACaAQAAAA==.',
Ja='Jaeson:BAABLgAECn8cAAIOAAkJGxHWHAADAgAOAAkJGxHWHAADAgAAAA==.Jaiya:BAAALgADCggJCAAAAA==.Jason:BAAALgAECgMJAwAAAA==.Javoren:BAAALgAECgcJCwABLgAFFAUJEwAhABwUAA==.',
Je='Jeef:BAAALgADCgEJAQABLgAECggJEAAJAAAAAA==.Jeefrenzy:BAAALgAECggJEAAAAA==.Jeffha:BAAALgAECgYJEQAAAA==.',
Ji='Jimothy:BAAALgAECgYJDQAAAA==.',
Jo='Joap:BAAALgAECgQJBwAAAA==.Joejr:BAABLgAECn8eAAQBAAgJAhnyGQB9AQABAAUJDBryGQB9AQAbAAYJ8RTXGwBPAQAiAAQJ+BOIPwD6AAAAAA==.Jonald:BAAALgADCgUJBQAAAA==.',
Jt='Jtizlfrizl:BAAALgAECgYJEAAAAA==.',
Jw='Jwise:BAAALgADCgcJCgAAAA==.',
Ka='Kajowsmage:BAAALgADCgcJBwAAAA==.Kalierix:BAAALgAECgQJBAAAAA==.Kaloesh:BAAALgAECgcJEwAAAA==.Kanabat:BAAALgAECgQJBwAAAA==.Karawyn:BAABLgAECn8eAAIEAAgJyg4fLQCaAQAEAAgJyg4fLQCaAQABLgAECgEJAQAJAAAAAA==.Karelix:BAAALgADCgcJBwAAAA==.Katrishy:BAACLgAFFH8KAAIiAAQJdxJ8CwBIAQAiAAQJdxJ8CwBIAQAuAAQKfygAAyIACAlcHYIWADMCACIACAlcHYIWADMCAAEAAQlwBT+IACcAAAAA.Kayyfrost:BAAALgADCgEJAQAAAA==.Kazeral:BAAALgADCgYJBwAAAA==.',
Ke='Keedrid:BAAALgAECggJDQAAAA==.Keindis:BAAALgADCgYJBgABLgAECgQJCgAJAAAAAA==.Kelaeno:BAAALgADCgEJAQABLgAECggJHQAGAAsHAA==.Kelemenohpea:BAABLgAECn8dAAIGAAgJCwd2UAAIAQAGAAgJCwd2UAAIAQAAAA==.',
Kn='Knoll:BAAALgAECgQJBQAAAA==.',
Ko='Kode:BAAALgAECgUJDgAAAA==.',
Kr='Kreeona:BAABLgAECn8gAAIVAAgJLSHPBgDFAgAVAAgJLSHPBgDFAgAAAA==.Kruàlty:BAAALgAECgQJCwAAAA==.',
Ku='Kungpow:BAAALgADCgYJBgAAAA==.',
Le='Legreebash:BAAALgADCgIJAgABLgAECgEJAQAJAAAAAA==.Legreecast:BAAALgAECgEJAQAAAA==.',
Li='Liasong:BAAALgADCgUJBQAAAA==.Litespeed:BAAALgADCgYJBwAAAA==.Litheliice:BAABLgAECn8pAAQBAAkJsg+oFwCTAQABAAgJNRCoFwCTAQAiAAEJ2wd5SwBFAAAbAAEJrgEAUAAdAAAAAA==.',
Lo='Lodur:BAABLgAECn8nAAIVAAgJjBwEDgBXAgAVAAgJjBwEDgBXAgAAAA==.Lofurious:BAAALgADCgIJAgAAAA==.Lonen:BAEBLgAECn8nAAIjAAgJARSwCQCGAQAjAAgJARSwCQCGAQAAAA==.Losat:BAABLgAECn8oAAIkAAgJBguAEgA9AQAkAAgJBguAEgA9AQAAAA==.',
Lu='Lugrat:BAAALgADCgEJAQAAAA==.Luguna:BAABLgAECn8UAAIPAAcJBxvtKwDOAQAPAAcJBxvtKwDOAQAAAA==.Lunári:BAAALgAECgEJAQAAAA==.Luraina:BAAALgADCgEJAQABLgAECgUJBgAJAAAAAA==.Luthian:BAAALgADCgMJAwAAAA==.',
Ly='Lycinder:BAAALgAECgEJAgAAAA==.',
['Lî']='Lîîght:BAAALgADCgEJAQAAAA==.',
Ma='Mackavelian:BAAALgAECgEJAQABLgAECgYJEAAJAAAAAA==.Mackkie:BAAALgAECgYJEAAAAA==.Madonkadonk:BAABLgAECn8qAAIXAAkJfg7IAwDQAQAXAAkJfg7IAwDQAQAAAA==.Maedai:BAABLgAECn8pAAISAAkJyRaOCABrAgASAAkJyRaOCABrAgAAAA==.Maeli:BAAALgADCgkJDQAAAA==.Magladroth:BAAALgAECgEJAQAAAA==.Magnaball:BAABLgAECn8tAAMhAAkJNhulDgAvAgAhAAkJNhulDgAvAgAPAAIJ1wnuSgEvAAAAAA==.Magús:BAAALgADCgEJAgAAAA==.Maldive:BAABLgAECn8fAAIOAAgJfhHQLgCoAQAOAAgJfhHQLgCoAQAAAA==.Maligasia:BAAALgAECgMJBAAAAA==.Mallicia:BAACLgAFFH8FAAIBAAMJ1yDbCgAbAQABAAMJ1yDbCgAbAQAuAAQKfyMAAgEACAkuJJcDACADAAEACAkuJJcDACADAAAA.Mallika:BAABLgAECn8YAAIVAAgJMhQLGwDZAQAVAAgJMhQLGwDZAQABLgAFFAMJBQABANcgAA==.Mallwizard:BAABLgAECn8nAAIOAAkJyxSNOAApAgAOAAkJyxSNOAApAgAAAA==.Mangopewpew:BAAALgAECgUJDQAAAA==.Martris:BAAALgADCgcJCwAAAA==.Massoflice:BAABLgAECn8bAAIaAAgJ9RXiagC2AQAaAAgJ9RXiagC2AQAAAA==.Maxblaide:BAAALgAECgUJBQAAAA==.Maxilla:BAAALgADCgcJDQABLgAECgkJLQAhADYbAA==.',
Me='Meridians:BAABLgAECn8YAAISAAYJnhXkGwBsAQASAAYJnhXkGwBsAQAAAA==.',
Mh='Mhataharii:BAAALgADCgIJAgAAAA==.',
Mi='Mindhorn:BAACLgAFFH8FAAMlAAMJWR3qHQC5AAAlAAIJOxrqHQC5AAAVAAEJKwl1PwBBAAAuAAQKfyUAAyUACAkXIRwFAKACACUACAkXIRwFAKACABUABAkDFcJnAGMAAAAA.Misstangy:BAAALgAECgQJBQAAAA==.',
Mo='Moct:BAABLgAECn8oAAIQAAgJGhlfBwDhAQAQAAgJGhlfBwDhAQAAAA==.Monis:BAAALgAECgEJAQAAAA==.Moomooduck:BAAALgAECgEJAQAAAA==.',
Mu='Mudskipper:BAABLgAECn8VAAIPAAgJIyClJgDmAQAPAAgJIyClJgDmAQAAAA==.Muradox:BAAALgAECgEJAQABLgAECggJHAAYAMQVAA==.Musashi:BAAALgAECgMJAwAAAA==.Mustardhunt:BAAALgADCgQJBQAAAA==.',
My='Myriad:BAABLgAECn8oAAIkAAgJfx/mAwCAAgAkAAgJfx/mAwCAAgAAAA==.',
Na='Nakze:BAABLgAECn8oAAIMAAgJsAvqEACaAQAMAAgJsAvqEACaAQAAAA==.Namanari:BAAALgADCgkJCQAAAA==.Naris:BAAALgADCgYJBgAAAA==.Nastyfigs:BAABLgAECn8ZAAIEAAYJoBlPNwBvAQAEAAYJoBlPNwBvAQAAAA==.Nazca:BAAALgADCgcJCgAAAA==.',
Ne='Necrochade:BAAALgAECgEJAQAAAA==.',
Nh='Nhilas:BAAALgAECgEJAwAAAA==.',
Ni='Nishal:BAAALgADCgkJEgAAAA==.',
Ny='Nyxaries:BAAALgAECgUJDAAAAA==.',
Ob='Oblivioso:BAAALgADCgYJBgAAAA==.',
Ol='Olåf:BAAALgADCgkJCQAAAA==.',
Pa='Pablo:BAAALgAECgQJBAAAAA==.Paladus:BAAALgAECgYJCQAAAA==.Pannacea:BAAALgAECgYJBgABLgAECggJIAAVAC0hAA==.Panzerblitz:BAABLgAECn8UAAIjAAcJtAjLFgCuAAAjAAcJtAjLFgCuAAAAAA==.Papers:BAAALgADCgEJAQAAAA==.Pargath:BAABLgAECn8YAAITAAcJNQoFIABSAQATAAcJNQoFIABSAQAAAA==.Pasìthea:BAAALgADCgcJCQAAAA==.',
Pe='Pedrote:BAAALgADCgUJBQAAAA==.Pengu:BAAALgAECgQJBgAAAA==.Pestcontrol:BAAALgAECgUJBQAAAA==.',
Pi='Pillow:BAABLgAECn8UAAIEAAYJNCAoKgANAgAEAAYJNCAoKgANAgAAAA==.Pillowdin:BAAALgAECgIJAwAAAA==.Pilson:BAAALgAECgYJDQAAAA==.Pinkytails:BAAALgADCgcJBwAAAA==.Piseyi:BAAALgAECgMJAwAAAA==.',
Po='Poondruid:BAAALgAECgEJAgAAAA==.Poonwagoon:BAAALgADCgYJCAAAAA==.',
Pr='Predacon:BAAALgAECgYJEQAAAA==.Pretzelz:BAAALgADCgYJCgAAAA==.Priesthealer:BAAALgAECgQJBgAAAA==.',
Pu='Puffer:BAABLgAECn8nAAICAAgJSQ82RwCRAQACAAgJSQ82RwCRAQAAAA==.',
Ra='Rabone:BAAALgADCgIJAgAAAA==.Raito:BAAALgAECgcJEwAAAA==.Rakshasa:BAABLgAECn8eAAMOAAgJcSIsDACPAgAOAAgJcSIsDACPAgAdAAEJAACwIQBrAAAAAA==.Ramesay:BAAALgAECgEJAQAAAA==.Ranilynn:BAAALgAECgQJBAABLgAECgUJDQAJAAAAAA==.Rasetsungo:BAAALgAECggJDgAAAA==.Raura:BAAALgAECgQJBwAAAA==.',
Re='Recalcitrent:BAAALgADCgYJCAAAAA==.Redblueblurr:BAAALgAECgYJCwAAAA==.Remi:BAAALgAECggJCAAAAA==.Reveillark:BAAALgAECgQJCQAAAA==.',
Ro='Rolan:BAABLgAECn8YAAIaAAgJvSNmHwDFAgAaAAgJvSNmHwDFAgAAAA==.Rosalian:BAABLgAECn8oAAIZAAgJFxyhDACCAgAZAAgJFxyhDACCAgAAAA==.Rotiko:BAABLgAECn8YAAIVAAcJKgzjMgBCAQAVAAcJKgzjMgBCAQAAAA==.Roweene:BAAALgAECgYJEwAAAA==.',
Sa='Saintseven:BAAALgAECgUJEQAAAA==.Salamander:BAAALgADCgYJBgAAAA==.Savior:BAAALgADCggJGQAAAA==.',
Se='Seiko:BAAALgADCgEJAQAAAA==.Selaphiel:BAAALgAECgMJBAAAAA==.Selvey:BAAALgADCgUJBwAAAA==.Sensei:BAABLgAECn8lAAMNAAcJzR8cCwAIAgANAAcJzR8cCwAIAgAUAAEJJAs5hQA8AAAAAA==.Serenatee:BAABLgAECn8oAAIiAAkJ9A0GDwDcAQAiAAkJ9A0GDwDcAQAAAA==.',
Sh='Shadowkrak:BAAALgADCgMJAwAAAA==.Shamill:BAAALgADCgMJAwAAAA==.Shammyball:BAAALgADCgcJBwAAAA==.Shamwow:BAAALgADCggJDgAAAA==.Shenanegans:BAAALgAECgEJAQAAAA==.Shobe:BAAALgAECgUJDgAAAA==.Shouhuzhee:BAABLgAECn8XAAIGAAkJHhHRHQDWAQAGAAkJHhHRHQDWAQAAAA==.Shåde:BAAALgADCgYJDQAAAA==.Shócker:BAAALgADCgMJBgAAAA==.',
Si='Sike:BAAALgADCgYJBgAAAA==.Silara:BAAALgADCgMJAwAAAA==.Simbà:BAAALgAECgYJDgAAAA==.',
Sl='Sleep:BAAALgADCgYJBgAAAA==.Sluicewrld:BAABLgAECn8XAAMGAAcJGSG/IQCGAgAGAAcJGSG/IQCGAgAHAAEJ9hZQawA7AAABLgAECggJEAAJAAAAAA==.',
Sn='Snorlacks:BAAALgAECgQJBAAAAA==.Snortedgfuel:BAAALgAECgYJDQAAAA==.',
So='Sokroar:BAAALgAECgQJBAAAAA==.Sonknight:BAAALgAECgQJDAAAAA==.',
Sp='Sparkticus:BAABLgAECn8dAAIlAAgJYh03CABZAgAlAAgJYh03CABZAgAAAA==.Spiky:BAAALgADCggJDQAAAA==.Spitefulcrow:BAABLgAECn8hAAImAAgJyAr0FABsAQAmAAgJyAr0FABsAQAAAA==.Sporak:BAAALgADCgIJAgAAAA==.',
St='Stardstr:BAAALgAECgIJBAAAAA==.Sto:BAAALgAECggJDQAAAA==.Stubz:BAAALgAECgYJBwAAAA==.',
Su='Supad:BAAALgADCgYJBwAAAA==.Superball:BAAALgAECgkJEwABLgAECgkJLQAhADYbAA==.Superjpriest:BAAALgAECgMJAwABLgAECgYJCgAJAAAAAA==.Suria:BAABLgAECn8nAAIZAAgJ5x3cCgCbAgAZAAgJ5x3cCgCbAgAAAA==.',
Sw='Swiskimohunr:BAAALgADCgMJAwAAAA==.Swàt:BAAALgADCgUJBQAAAA==.',
Sy='Syker:BAAALgAECgUJBQAAAA==.Syloc:BAAALgAECgEJAQAAAA==.',
Ta='Tahrovin:BAAALgADCggJEwAAAA==.Talaera:BAAALgAECgUJBgAAAA==.Tannastia:BAAALgAECgQJBwAAAA==.Tatem:BAAALgADCgcJEwAAAA==.Taurunter:BAAALgAECgMJAwAAAA==.Tavistreea:BAAALgAECgYJDQAAAA==.Taystee:BAAALgADCgYJBgAAAA==.Taytorchips:BAABLgAECn8sAAMhAAgJgQQqLgAiAQAhAAgJgQQqLgAiAQAPAAcJFwaA+ACiAAAAAA==.',
Th='Thelm:BAAALgADCgMJAwAAAA==.Thetinker:BAAALgADCgUJBQAAAA==.Thevoid:BAAALgADCgMJAwAAAA==.Thiccsmoke:BAAALgADCgIJAgAAAA==.Thoneous:BAAALgAECgYJBgAAAA==.Thornten:BAAALgAECgYJEAAAAA==.Thundercups:BAABLgAECn8qAAIRAAkJ1h8JAQDpAgARAAkJ1h8JAQDpAgAAAA==.',
Ti='Tigerstarr:BAABLgAECn8UAAMaAAkJYg0jWwAwAQAaAAkJYg0jWwAwAQAcAAEJUQYnGQAqAAAAAA==.Timboslicé:BAAALgAECgcJCwAAAA==.Tinyshieva:BAABLgAECn8VAAMBAAYJ4wvwSAAVAQABAAYJ4wvwSAAVAQAiAAIJ2AOySgBHAAAAAA==.Tizuki:BAAALgAECgIJAgAAAA==.',
To='Tokey:BAAALgAECgUJDQAAAA==.Toriael:BAAALgAECgcJBwAAAA==.',
Tr='Trashlock:BAAALgADCgYJBgAAAA==.Treasure:BAAALgAECgYJEAAAAA==.Treborlock:BAABLgAECn8gAAITAAgJ0hdDAwD4AQATAAgJ0hdDAwD4AQAAAA==.Treenn:BAAALgAECgMJAwAAAA==.Triplock:BAAALgADCgMJBQAAAA==.Trolcain:BAABLgAECn8cAAIaAAgJKiJkCwCvAgAaAAgJKiJkCwCvAgAAAA==.Trolmed:BAAALgAECgYJDAABLgAECggJHAAaACoiAA==.',
Ty='Tyrix:BAAALgAECgYJEAAAAA==.Tyránt:BAACLgAFFH8GAAIEAAMJjhAXKQD1AAAEAAMJjhAXKQD1AAAuAAQKfyIAAwQACAkbIv8tAPoBAAQACAkbIv8tAPoBAAsAAQkAANmbABAAAAAA.',
Ul='Ulfal:BAABLgAECn8XAAIUAAYJ2BkdMADbAAAUAAYJ2BkdMADbAAAAAA==.',
Va='Vagglord:BAABLgAECn8WAAICAAUJoyXqYQAWAgACAAUJoyXqYQAWAgAAAA==.Valadir:BAAALgAECgQJCAAAAA==.Valerossi:BAABLgAECn8mAAImAAgJCByOBgBHAgAmAAgJCByOBgBHAgAAAA==.Valha:BAABLgAECn8lAAIHAAkJJhKFCQD0AQAHAAkJJhKFCQD0AQAAAA==.Vanorick:BAAALgAECgEJAgAAAA==.Vardisk:BAAALgADCgYJBgAAAA==.Varleyna:BAAALgAECgMJAwABLgAFFAMJBQABANcgAA==.Varteras:BAABLgAECn8mAAMOAAkJFxWtJQDTAQAOAAgJmBKtJQDTAQAdAAUJjBMyDgBPAQAAAA==.',
Ve='Veleiri:BAABLgAECn8UAAICAAYJsRB/cAAwAQACAAYJsRB/cAAwAQAAAA==.Velenal:BAAALgAECgEJAwAAAA==.Vellron:BAABLgAECn8dAAIEAAgJ/wwtLwCRAQAEAAgJ/wwtLwCRAQAAAA==.',
Vo='Voidgawd:BAAALgADCgMJAwAAAA==.',
Vu='Vurkaal:BAAALgADCgYJBgAAAA==.',
['Và']='Vàsh:BAAALgAECgIJAgAAAA==.',
Wa='Wafflelegend:BAABLgAECn8WAAMHAAYJtSNrCQD2AQAHAAYJCiNrCQD2AQAGAAQJHx8ZMgBtAQAAAA==.Wardkbriggle:BAACLgAFFH8HAAIeAAIJ5yLmGgBlAAAeAAIJ5yLmGgBlAAAuAAQKfxkAAh4ACQkqIYEDAJoCAB4ACQkqIYEDAJoCAAAA.Warlover:BAAALgADCgYJCgAAAA==.Wartiger:BAACLgAFFH8UAAIUAAUJjBuTCABKAQAUAAUJjBuTCABKAQAuAAQKfxcAAhQACAmBICIVAGMCABQACAmBICIVAGMCAAAA.',
Wi='Wifi:BAAALgAECgEJAgAAAA==.',
Wo='Wolfdude:BAABLgAECn8XAAMeAAYJeQWBNwCGAAAeAAQJGQaBNwCGAAAcAAUJ9QH+EgBiAAAAAA==.',
Wu='Wudo:BAAALgAECgEJAQAAAA==.',
Wy='Wydge:BAABLgAECn8aAAICAAYJFBIHZgBFAQACAAYJFBIHZgBFAQAAAA==.Wymonath:BAAALgAFFAEJAQAAAA==.',
Xa='Xanddoria:BAABLgAECn8mAAQMAAgJDySSBACAAgAMAAgJ5SGSBACAAgAnAAcJViITBAB1AgAoAAYJtx3UAwC0AQAAAA==.Xannydevito:BAAALgAECgYJEwAAAA==.',
Xe='Xellioth:BAAALgAECgYJEQAAAA==.Xenti:BAAALgADCgcJBwABLgAECggJJgAMAA8kAA==.',
Xh='Xhared:BAABLgAECn8dAAIeAAcJ/iApBwAfAgAeAAcJ/iApBwAfAgAAAA==.',
Ya='Yahtzee:BAAALgADCgUJAwAAAA==.Yamavalkyrie:BAAALgADCgcJBwAAAA==.Yaosi:BAAALgAECgEJAQAAAA==.Yatorishino:BAABLgAECn8XAAIGAAgJ8QIVcAC6AAAGAAgJ8QIVcAC6AAAAAA==.',
Ze='Zephy:BAAALgAECgMJAwAAAA==.',
Zo='Zom:BAAALgADCgkJGgAAAA==.',
['Ël']='Ëlle:BAAALgADCgEJAQAAAA==.',
['Öz']='Öz:BAACLgAFFH8HAAIpAAQJuRhdAABmAQApAAQJuRhdAABmAQAuAAQKfzQAAykACQlVID0AAPkCACkACQlVID0AAPkCAAIABAmyF575AAcBAAAA.',
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

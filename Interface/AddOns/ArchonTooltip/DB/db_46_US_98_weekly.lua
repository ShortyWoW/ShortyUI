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

local lookup = {'Druid-Balance','Unknown-Unknown','Mage-Frost','Mage-Arcane','Paladin-Holy','Paladin-Retribution','Paladin-Protection','Hunter-Survival','Monk-Brewmaster','Monk-Windwalker','Rogue-Subtlety','Shaman-Elemental','Warlock-Demonology','Druid-Restoration','Shaman-Enhancement','Shaman-Restoration','DeathKnight-Unholy','Monk-Mistweaver','Warrior-Fury','Warrior-Protection','Evoker-Preservation','Warlock-Destruction','DemonHunter-Vengeance','Warlock-Affliction','Rogue-Assassination','Evoker-Augmentation','Priest-Shadow','Hunter-BeastMastery','Druid-Feral','DemonHunter-Devourer','DemonHunter-Havoc','Warrior-Arms','DeathKnight-Blood','DeathKnight-Frost','Hunter-Marksmanship','Priest-Holy','Evoker-Devastation','Druid-Guardian','Priest-Discipline',}
local provider = {region='US',realm='Frostmane',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Aberdus:BAABLgAECn8YAAIBAAcJDxUYCAB0AQABAAcJDxUYCAB0AQAAAA==.',
Ac='Accalon:BAAALgAECgYJDwABLgAECgUJDAACAAAAAA==.',
Ad='Adina:BAAALgAECgYJBgAAAA==.Advacus:BAACLgAFFH8HAAMDAAMJtwx1MADxAAADAAMJVgh1MADxAAAEAAEJbxN/AQBVAAAuAAQKfx4AAwQACAmLHgACAJACAAQACAmWGgACAJACAAMACAlEF05QAEYCAAAA.',
Ai='Aicila:BAAALgADCgEJAQAAAA==.Airi:BAAALgADCgYJCAAAAA==.',
Ak='Akrama:BAABLgAECn8aAAIFAAcJdBxKCQCvAQAFAAcJdBxKCQCvAQAAAA==.',
Al='Alara:BAAALgADCgkJEwAAAA==.Alatáriel:BAAALgAECgEJAQAAAA==.Alectrona:BAAALgAECgEJAgAAAA==.Aletriss:BAAALgADCgkJGgAAAA==.Alexsham:BAAALgAECgEJAQAAAA==.Algaraz:BAAALgAECgYJDgAAAA==.',
Am='Ama:BAAALgADCgYJCAAAAA==.Amnorpse:BAAALgAECgUJDQAAAA==.',
An='Anabana:BAAALgAECgQJCQAAAA==.Angler:BAAALgAECgcJDgAAAA==.Anruu:BAAALgAECgUJBQAAAA==.',
Ap='Appropriate:BAAALgADCgMJAwAAAA==.',
Ar='Araleth:BAAALgADCggJCwAAAA==.Arkthurus:BAAALgAECgYJCQAAAA==.Artumis:BAAALgADCgEJAQAAAA==.Arvitherejet:BAAALgAECgEJAQAAAA==.',
As='Aschern:BAAALgAECgYJDAAAAA==.Ashijin:BAACLgAFFH8HAAIGAAMJ8BMWDwCrAAAGAAMJ8BMWDwCrAAAuAAQKfyMAAgYACAl4HxUmAI4CAAYACAl4HxUmAI4CAAAA.Ashilyn:BAAALgAECgEJAQAAAA==.Ashoo:BAAALgADCgEJAQAAAA==.',
At='Ataxxius:BAAALgADCgMJAwAAAA==.Atheristina:BAAALgADCgYJBgABLgAECgUJEAACAAAAAA==.Atroce:BAAALgAECgEJAQAAAA==.Atticu:BAAALgAECgMJAwAAAA==.',
Au='Aura:BAABLgAECn8fAAIFAAkJJBSpHwAcAgAFAAkJJBSpHwAcAgAAAA==.Auxilium:BAABLgAECn8UAAIGAAcJxBjVSAAIAgAGAAcJxBjVSAAIAgAAAA==.',
Aw='Awnen:BAAALgAECgMJBAAAAA==.',
Az='Aza:BAAALgADCgIJAgAAAA==.',
Ba='Backtrakk:BAAALgADCgMJAwAAAA==.Bahndis:BAAALgADCgcJDAAAAA==.Balethar:BAAALgAECgQJBAABLgAECggJIAAHAD4jAA==.Balluh:BAABLgAECn8bAAIIAAcJaxVLDQD1AQAIAAcJaxVLDQD1AQAAAA==.',
Be='Beartest:BAAALgAECgMJBAABLgAECggJFgAJAOYaAA==.Beezen:BAACLgAFFH8OAAIKAAUJFxlmAQBSAQAKAAUJFxlmAQBSAQAuAAQKfyQAAgoACAm/IUcFADADAAoACAm/IUcFADADAAAA.Belara:BAAALgADCgUJBgAAAA==.Bellevo:BAAALgAECgQJBAAAAA==.Bellmage:BAABLgAECn8bAAMDAAgJiB4MMwCmAgADAAgJiB4MMwCmAgAEAAEJxAlqHwAxAAAAAA==.Belttoash:BAABLgAECn8eAAIGAAcJhRS6YADCAQAGAAcJhRS6YADCAQAAAA==.Beneficiary:BAAALgAECgEJAgAAAA==.Bercey:BAAALgAECgIJAgAAAA==.Beybladetest:BAABLgAECn8WAAIJAAgJ5hoBFgBaAgAJAAgJ5hoBFgBaAgAAAA==.',
Bi='Bigmang:BAAALgADCgYJBgAAAA==.Bigmayex:BAAALgADCgkJDQABLgAECggJFwALAPsbAA==.Bigscott:BAAALgADCgQJBAABLgAFFAMJCQAMAG4MAA==.Binky:BAAALgADCgIJAgAAAA==.',
Bl='Blackbride:BAAALgADCgkJEAAAAA==.Blackfyre:BAAALgAECgIJBAAAAA==.Blackmage:BAAALgAECgYJDgAAAA==.Blizzlock:BAABLgAECn8WAAINAAYJzBDGgQBXAQANAAYJzBDGgQBXAQAAAA==.Blood:BAAALgAECgEJAgAAAA==.Bloodfeast:BAAALgADCgYJBgAAAA==.Blooms:BAAALgADCgIJAgAAAA==.Blurednuhtz:BAAALgADCgYJCQAAAA==.',
Bo='Bobcatross:BAAALgADCgYJBgAAAA==.Bohvicce:BAAALgADCgEJAQAAAA==.Bokudo:BAAALgADCgMJAwAAAA==.Bonezs:BAABLgAECn8gAAIOAAgJHyP/AQCxAgAOAAgJHyP/AQCxAgAAAA==.Bootylika:BAAALgAECggJEgAAAA==.Borislav:BAAALgADCgEJAQAAAA==.Bossvega:BAAALgADCgIJAgAAAA==.Boutdatbass:BAAALgADCgkJGgAAAA==.',
Br='Braxxar:BAAALgAECgQJBAAAAA==.Briellia:BAAALgAECgEJAgAAAA==.Bruggerlock:BAEALgADCgMJAwAAAA==.Bryagh:BAAALgAECgYJCwAAAA==.',
Bu='Bubbam:BAAALgADCgYJCAAAAA==.Bufferbug:BAAALgADCgkJFAAAAA==.Bugbear:BAAALgAECgEJAQAAAA==.Bulge:BAAALgADCgUJBQABLgAECgUJCwACAAAAAA==.Bullycow:BAABLgAECn8XAAIPAAYJJgX6BwDoAAAPAAYJJgX6BwDoAAAAAA==.Bushybrowsy:BAAALgAECgcJEQAAAA==.Buttercupz:BAAALgAECgcJEgAAAA==.',
['Bá']='Bámboo:BAAALgAECgEJAQAAAA==.',
['Bî']='Bîgdaddy:BAABLgAECn8aAAMQAAgJ4hUmBgD3AQAQAAgJ4hUmBgD3AQAMAAQJmgNXagCaAAAAAA==.',
Ca='Cacho:BAAALgAECgEJAgAAAA==.Calevan:BAAALgAECgkJDwAAAA==.Candoran:BAAALgADCgMJAwAAAA==.Caracarn:BAAALgAECgUJBQAAAA==.Carpulations:BAABLgAECn8XAAINAAYJEBiYhABRAQANAAYJEBiYhABRAQAAAA==.',
Cc='Ccyll:BAAALgADCgkJEgAAAA==.',
Ce='Cerofewol:BAAALgADCgMJAwABLgAECgUJBwACAAAAAA==.Cerridwen:BAAALgAECgYJBgAAAA==.',
Ch='Chantini:BAAALgADCgkJDwAAAA==.Chartreuze:BAAALgAECgEJAQAAAA==.Chazmonk:BAAALgAECgEJAQAAAA==.Chia:BAACLgAFFH8KAAIRAAQJIgxaBwBOAQARAAQJIgxaBwBOAQAuAAQKfxsAAhEABwlfHaBQAAACABEABwlfHaBQAAACAAAA.Chikn:BAABLgAECn8XAAISAAgJ8xRcGAD8AQASAAgJ8xRcGAD8AQAAAA==.Chirichiri:BAAALgADCgEJAQAAAA==.Chizu:BAAALgADCgUJBQABLgAFFAMJBgATAL8UAA==.Chomboslice:BAABLgAECn8ZAAIFAAgJ6h2yBAAeAgAFAAgJ6h2yBAAeAgAAAA==.',
Cl='Clary:BAAALgADCgEJAQABLgAECgYJEwACAAAAAA==.Classy:BAAALgAECgEJAQAAAA==.',
Cm='Cmil:BAACLgAFFH8JAAMFAAQJtguXDAAUAQAFAAQJtguXDAAUAQAGAAEJkgH8GwA2AAAuAAQKfx8AAwUACAnwC8Y4AJcBAAUACAnwC8Y4AJcBAAYAAQnODaJCATMAAAAA.',
Co='Coffeecrem:BAAALgAECgYJDAAAAA==.Coffie:BAAALgADCgUJBQABLgAECgYJDAACAAAAAA==.Coldnoodles:BAAALgADCgMJAgABLgAECggJHQAKACwfAA==.Combat:BAACLgAFFH8KAAITAAQJuRNbCwBKAQATAAQJuRNbCwBKAQAuAAQKfx4AAhMACAktHlQVAKMCABMACAktHlQVAKMCAAAA.Cornish:BAECLgAFFH8FAAISAAUJ1B+3AAAAAgASAAUJ1B+3AAAAAgAuAAQKfxkAAhIACQnFIbsAAO8CABIACQnFIbsAAO8CAAAA.Cornishpaste:BAEALgAECgQJBAABLgAFFAUJBQASANQfAA==.Cosmo:BAAALgADCgcJCQABLgAECgYJDgACAAAAAA==.',
Cr='Crackjaw:BAAALgAECgMJBQAAAA==.Crockodk:BAAALgAECgEJAQAAAA==.',
Cu='Curserodlock:BAAALgADCgMJAwAAAA==.',
Cy='Cyanide:BAAALgAECgUJBQAAAA==.',
Da='Dabbinshamin:BAAALgADCgkJGQAAAA==.Dadanbing:BAAALgAECgYJBgAAAA==.Dads:BAACLgAFFH8VAAMMAAYJuRWuBACWAQAMAAUJmheuBACWAQAQAAMJhwqcCgCcAAAuAAQKfxsAAwwACQkWJSAQAKgCAAwABwm6JCAQAKgCABAACQloF8ciAA4CAAAA.Daggertest:BAAALgADCgQJBAABLgAECggJFgAJAOYaAA==.Dakeyras:BAABLgAECn8WAAMUAAcJsQ80HgBUAQAUAAcJsQ80HgBUAQATAAIJcgHKrAAwAAAAAA==.Darcevoker:BAACLgAFFH8KAAIVAAUJ9wdhBAAiAQAVAAUJ9wdhBAAiAQAuAAQKfyQAAhUACAmrGN8NAFkCABUACAmrGN8NAFkCAAAA.Darcmonk:BAAALgADCgcJCwABLgAFFAUJCgAVAPcHAA==.Darcpaladin:BAAALgAECgQJBAABLgAFFAUJCgAVAPcHAA==.Darcshaman:BAAALgAECgIJAgABLgAFFAUJCgAVAPcHAA==.Darkrune:BAAALgAECgQJBwAAAA==.Darkschneide:BAAALgAECgQJBAAAAA==.Darthboo:BAAALgADCggJDAAAAA==.Darthtemplar:BAAALgAECgQJBAAAAA==.',
Db='Dbmagic:BAAALgAECgUJBwAAAA==.',
De='Dealsun:BAABLgAECn8bAAMNAAgJdBOhRAD+AQANAAgJdBOhRAD+AQAWAAUJ2QdKOADTAAAAAA==.Decynth:BAAALgAECgcJCQAAAA==.Defne:BAAALgAECgEJAQAAAA==.Demodorn:BAECLgAFFH8LAAIXAAQJ0AT5AADaAAAXAAQJ0AT5AADaAAAuAAQKfycAAhcACAmfFFAIAPgBABcACAmfFFAIAPgBAAAA.Demondudez:BAAALgAECgUJCgAAAA==.Demonikat:BAAALgADCgEJAQAAAA==.Demyst:BAACLgAFFH8FAAMMAAMJgAd/EQDgAAAMAAMJgAd/EQDgAAAQAAEJ3QZNJQBBAAAuAAQKfxsAAwwACAlvHikSAJICAAwACAlvHikSAJICABAAAQnlBnGaADkAAAAA.Deria:BAAALgAECgEJAQAAAA==.Devilsparda:BAAALgAECgMJAwAAAA==.Deweey:BAAALgAECgUJCQAAAA==.Dezeraz:BAECLgAFFH8MAAIVAAQJbBwIBwB+AQAVAAQJbBwIBwB+AQAuAAQKfyMAAhUACAkDJv8BAFsDABUACAkDJv8BAFsDAAEuAAUUBQkFABIA1B8A.',
Dh='Dhecaye:BAAALgADCgkJDwABLgAFFAIJAgACAAAAAA==.',
Di='Dieuscum:BAAALgAECgUJBQAAAA==.Diksneeze:BAAALgADCgUJCAAAAA==.Disengage:BAAALgAECgkJAwABLgAFFAQJCgATALkTAA==.Dislogic:BAABLgAECn8kAAMNAAkJZiJoAAAlAwANAAgJZiJoAAAlAwAWAAQJTSCkGwBwAQAAAA==.',
Do='Dobbie:BAAALgADCgUJBQAAAA==.Donkey:BAAALgAECgYJCQAAAA==.Doraleous:BAAALgAECgYJCgAAAA==.Dotzmybitzup:BAACLgAFFH8KAAMNAAQJIRkXDAASAQANAAQJIRkXDAASAQAWAAEJNA2KBQBUAAAuAAQKfyoABA0ABwmdIZIjAIYCAA0ABglUJZIjAIYCABgAAglqEzEdAIgAABYAAQlXDmJjAEgAAAAA.Dougalleone:BAACLgAFFH8GAAILAAMJPBa5DAAaAQALAAMJPBa5DAAaAQAuAAQKfx8AAwsACAmVIoMHABgDAAsACAmVIoMHABgDABkAAQmtEfQdAD0AAAAA.',
Dr='Draci:BAAALgADCgEJAQAAAA==.Drakar:BAAALgAECgkJDQAAAA==.Dreadknott:BAABLgAECn8gAAIRAAgJyhonLgCAAgARAAgJyhonLgCAAgAAAA==.Dreadxknight:BAAALgADCgMJAwAAAA==.Drekim:BAABLgAECn8UAAIaAAUJryALLgBRAQAaAAUJryALLgBRAQAAAA==.Dreko:BAAALgADCgIJAgAAAA==.Drezzakmage:BAABLgAECn8aAAIDAAgJ+hVtYAAaAgADAAgJ+hVtYAAaAgAAAA==.Drezzakzdh:BAAALgADCgYJBgABLgAECggJGgADAPoVAA==.Drooblet:BAAALgAECgkJBgAAAA==.Druidiac:BAAALgADCgYJEwABLgAECgcJGgAbAMUXAA==.',
Ed='Edgelf:BAAALgADCgMJAwAAAA==.',
El='Elaidare:BAAALgAECgEJAQABLgAECgYJCgACAAAAAA==.Elaidine:BAAALgAECgYJCgAAAA==.Elisabetta:BAAALgADCgMJAwAAAA==.Elizalex:BAAALgAECgEJAQAAAA==.',
Em='Emagdne:BAAALgADCgMJAgAAAA==.Empath:BAAALgADCgQJBQAAAA==.',
En='Enfernum:BAAALgADCgEJAQAAAA==.Enolad:BAAALgADCgcJBwABLgAECgYJBgACAAAAAA==.',
Er='Eradius:BAAALgADCgIJAgAAAA==.Errai:BAABLgAECn8bAAINAAgJ1CBJAgCHAgANAAgJ1CBJAgCHAgAAAA==.',
Eu='Eureka:BAAALgAECggJDgAAAA==.',
Ev='Evilnapkin:BAAALgAECgQJDwAAAA==.Evion:BAABLgAECn8VAAIcAAcJVhuCLwDzAQAcAAcJVhuCLwDzAQAAAA==.',
Ey='Eyez:BAAALgADCgIJAgAAAA==.',
Fa='Faelthorn:BAAALgADCgQJBAAAAA==.Farseer:BAAALgADCgMJAwAAAA==.',
Fe='Feardoctor:BAAALgAECgQJCAAAAA==.Feelthepower:BAAALgAECgYJDwAAAA==.',
Fl='Flavorfrenzy:BAAALgADCgUJBQAAAA==.',
Fo='Fourimborniy:BAAALgAECgcJCwAAAA==.',
Fr='Friendulum:BAAALgAECgcJBwAAAA==.',
Fu='Fuzzsicle:BAAALgAECgYJCQAAAA==.Fuzzydìcê:BAAALgAECgUJCAAAAA==.',
['Fá']='Fáelen:BAABLgAECn8fAAIdAAgJMx6pBgCLAgAdAAgJMx6pBgCLAgAAAA==.',
Ga='Galang:BAAALgAECgEJAQAAAA==.Gangactivity:BAAALgAECgMJAwABLgAECggJHgAKALwgAA==.Garrt:BAAALgAECgEJAQAAAA==.Gartalvanise:BAAALgAECgEJAQAAAA==.',
Ge='Gep:BAAALgAECgcJDgAAAA==.',
Gl='Glaalinix:BAAALgADCgcJEgAAAA==.Globbie:BAAALgADCgMJAwAAAA==.',
Go='Goku:BAAALgAECgQJBAAAAA==.Goobman:BAAALgADCgQJBQABLgAECggJIwAOAP4hAA==.Goodman:BAABLgAECn8aAAIGAAcJyBykCQDxAQAGAAcJyBykCQDxAQAAAA==.Goomei:BAABLgAECn8hAAIKAAgJdx9SCgDTAgAKAAgJdx9SCgDTAgABLgAFFAUJDgAeAGIeAA==.Goomi:BAACLgAFFH8OAAIeAAUJYh4LCACkAQAeAAUJYh4LCACkAQAuAAQKfyMAAh4ACQk+Iw4DAJ4DAB4ACQk+Iw4DAJ4DAAAA.Gordius:BAAALgADCgEJAQAAAA==.Gorok:BAAALgAECgMJAwAAAA==.Goybeam:BAAALgADCgcJCQAAAA==.',
Gr='Gravykin:BAAALgAECgYJCwAAAA==.Grayfoxrun:BAAALgADCgUJBQAAAA==.Greatbooty:BAABLgAECn8VAAIDAAYJBxQMJQA8AQADAAYJBxQMJQA8AQAAAA==.Grecko:BAAALgADCgUJBQAAAA==.Gremmi:BAAALgAECgEJAwAAAA==.Greygavel:BAAALgAECgEJAQAAAA==.Grosgland:BAAALgADCgEJAQAAAA==.Groundbeéf:BAACLgAFFH8OAAIPAAUJciBPAACCAQAPAAUJciBPAACCAQAuAAQKfyQAAg8ACAkJJvwAAH4DAA8ACAkJJvwAAH4DAAAA.Groundzero:BAAALgADCgUJBQAAAA==.Groztrazztok:BAAALgAECgYJEwAAAA==.Grungulus:BAAALgAECgcJCQAAAA==.',
Gu='Guineapig:BAEBLgAECn8UAAIGAAcJLyTrMABfAgAGAAcJLyTrMABfAgAAAA==.Gundral:BAAALgADCgEJAQAAAA==.Gunnysack:BAAALgADCgcJDQAAAA==.Guzmo:BAAALgAECgEJAQABLgAECgUJBgACAAAAAA==.',
Gy='Gypsyrose:BAAALgAECgkJEgAAAA==.Gyx:BAAALgAECgQJCAAAAA==.',
Ha='Haiku:BAAALgAECgEJAQAAAA==.Handanir:BAABLgAECn8XAAIOAAgJxBp6BgAIAgAOAAgJxBp6BgAIAgAAAA==.Harie:BAAALgAECgUJDQAAAA==.Hasbula:BAAALgAECgQJBAAAAA==.Hatebound:BAAALgAECgEJAQAAAA==.',
He='Heihei:BAAALgADCgYJDAAAAA==.Heiny:BAAALgAECgYJCAABLgAECggJKQAFAD4kAA==.Heinyheinyho:BAABLgAECn8pAAIFAAgJPiSrAAAAAwAFAAgJPiSrAAAAAwAAAA==.',
Hi='Hielle:BAAALgADCgkJCQAAAA==.Highguard:BAAALgADCgcJBwAAAA==.Himothy:BAAALgAECgEJAgAAAA==.',
Ho='Hoid:BAAALgAECgEJAQAAAA==.Holy:BAAALgADCgYJBgAAAA==.Holysword:BAEALgADCgYJBgABLgAECgQJBQACAAAAAA==.Hoofmetoo:BAABLgAECn8UAAIRAAYJ5BQrGwA+AQARAAYJ5BQrGwA+AQAAAA==.Howboudah:BAAALgADCggJCAAAAA==.',
Hu='Hulkgirl:BAAALgADCgEJAQAAAA==.Hulzar:BAAALgAECgYJEQAAAA==.',
['Hô']='Hôlyblight:BAAALgADCgEJAQABLgAECggJKQAMAHQhAA==.',
Ic='Iceflare:BAABLgAECn8ZAAMDAAgJihbrVAA6AgADAAgJihbrVAA6AgAEAAQJ7gLnEwCHAAAAAA==.',
Id='Idotyouto:BAABLgAECn8cAAIDAAcJMR3eUgA/AgADAAcJMR3eUgA/AgAAAA==.',
Ig='Igris:BAAALgADCgkJFQAAAA==.',
Ih='Ihavewater:BAAALgADCgkJCQAAAA==.',
Il='Ilbryen:BAAALgAECgUJBQABLgAFFAMJBgATAL8UAA==.Illidori:BAAALgAECgYJDQAAAA==.Illidrag:BAAALgAECgcJDAAAAA==.Ilovemoo:BAAALgAECgMJAwAAAA==.',
Im='Imblind:BAAALgADCgEJAQABLgAECggJFwAKAPEWAA==.Imladris:BAAALgAECgYJDgAAAA==.Immòrtlzed:BAACLgAFFH8MAAIVAAQJECHwAgBcAQAVAAQJECHwAgBcAQAuAAQKfyAAAhUACAliIG8JAJ8CABUACAliIG8JAJ8CAAAA.Immørtlzed:BAAALgADCgUJBQABLgAFFAQJDAAVABAhAA==.',
In='Invective:BAAALgADCgkJIAAAAA==.',
Is='Isharn:BAAALgADCgMJAwAAAA==.',
Iz='Izzyumi:BAABLgAECn8XAAIcAAcJUgxRFQBRAQAcAAcJUgxRFQBRAQAAAA==.',
Ja='Jabo:BAAALgADCgMJAwABLgAECgUJDAACAAAAAA==.Jadelin:BAAALgAECgIJAgABLgAECggJJwAfALsXAA==.Jaxek:BAABLgAECn8cAAIdAAgJvSG9AABZAgAdAAgJvSG9AABZAgAAAA==.Jaxs:BAACLgAFFH8GAAIQAAMJ1Bz+CwAaAQAQAAMJ1Bz+CwAaAQAuAAQKfyAAAhAACAlAG5wVAGgCABAACAlAG5wVAGgCAAAA.Jaylen:BAAALgADCgQJBAAAAA==.',
Je='Jeffurry:BAAALgADCgIJAgAAAA==.Jeminia:BAAALgAECgUJBwAAAA==.Jenifur:BAABLgAECn8VAAIOAAYJqgtDGAD8AAAOAAYJqgtDGAD8AAAAAA==.Jennae:BAAALgADCgEJAQAAAA==.',
Jh='Jhope:BAABLgAFFH8FAAIJAAIJhQf3DACEAAAJAAIJhQf3DACEAAAAAA==.',
Ji='Jinkusu:BAAALgADCgMJAwABLgAECgYJEAACAAAAAA==.',
Jm='Jml:BAACLgAFFH8IAAIeAAQJWCE0CQCWAQAeAAQJWCE0CQCWAQAuAAQKfxkAAh4ACQnRIf4EAHYDAB4ACQnRIf4EAHYDAAAA.',
Jo='Jopha:BAACLgAFFH8NAAITAAQJHyA4AQB7AQATAAQJHyA4AQB7AQAuAAQKfyMAAxMACAlHJQUGAEcDABMACAkmJQUGAEcDACAABwkQH/IEAJQCAAAA.Jophr:BAAALgAECgEJAQABLgAFFAQJDQATAB8gAA==.',
Jp='Jpbruiser:BAABLgAECn8fAAIGAAgJWCCdAwBwAgAGAAgJWCCdAwBwAgAAAA==.',
Ju='Judged:BAAALgAECgUJBwAAAA==.Juggalette:BAAALgADCgIJAgAAAA==.Jumpndeath:BAACLgAFFH8FAAIhAAMJOxAnCwDJAAAhAAMJOxAnCwDJAAAuAAQKfxgAAyEACAlGHzsUAMwBACEABQnZHzsUAMwBABEABglYHJB+AIYBAAAA.Jumpnpunch:BAABLgAECn8YAAQJAAcJRxz+GQA0AgAJAAcJQBz+GQA0AgASAAYJEA44OAANAQAKAAEJqwtndQBAAAABLgAFFAMJBQAhADsQAA==.Justgetme:BAABLgAECn8gAAMHAAgJPiNAAADUAgAHAAgJPiNAAADUAgAGAAIJAA6XGwFjAAAAAA==.',
Jw='Jwad:BAAALgAECgYJDQAAAA==.',
Ka='Kaariel:BAAALgADCgcJCgAAAA==.Kabo:BAAALgADCgUJBQABLgAECggJHQARAPchAA==.Kagger:BAABLgAECn8rAAIGAAkJ3yDmBAB9AwAGAAkJ3yDmBAB9AwAAAA==.Kaiser:BAAALgADCgcJDAAAAA==.Kaitu:BAAALgAECgYJCgAAAA==.Kake:BAAALgAECgQJBAABLgABCgIJAgACAAAAAA==.Kalloh:BAABLgAECn8XAAINAAYJGxPIGwA5AQANAAYJGxPIGwA5AQAAAA==.Kalorth:BAAALgADCgcJBwAAAA==.Kardoroth:BAACLgAFFH8GAAIRAAIJhib2EQDaAAARAAIJhib2EQDaAAAuAAQKfykAAhEACAlQJqYAAAoDABEACAlQJqYAAAoDAAAA.Karibo:BAAALgADCgcJDAAAAA==.Karîba:BAACLgAFFH8MAAQRAAQJUhhnFwBHAQARAAQJdhNnFwBHAQAhAAIJPxO2DgB+AAAiAAEJaAtlBABPAAAuAAQKfyMAAxEACAn8HkkfAMYCABEACAn8HkkfAMYCACEAAQkrCS5NABwAAAAA.Kassi:BAAALgADCgEJAQAAAA==.Kayfree:BAAALgAECgUJCQAAAA==.Kaõtik:BAAALgAECgkJCgAAAA==.',
Ke='Keerrilee:BAAALgAECgcJEgAAAA==.Kefka:BAAALgAECgQJBQAAAA==.Keirine:BAAALgAECgEJAwAAAA==.Kelfrost:BAAALgAECgIJAgAAAA==.Kelknight:BAAALgAECgQJEAAAAA==.Kelsaz:BAACLgAFFH8LAAMIAAQJLxg3AQBlAQAIAAQJ1hE3AQBlAQAcAAMJchV0CwAGAQAuAAQKfx8ABBwACAkqIzUSAKYCABwABwlIIzUSAKYCACMABglBGMtGADgBAAgABAnvFlYLANoAAAAA.Kelsi:BAAALgAECgYJDgAAAA==.Kenný:BAAALgADCgMJBAAAAA==.Kerrìgàn:BAACLgAFFH8KAAIXAAQJSgszAgC9AAAXAAQJSgszAgC9AAAuAAQKfyUAAhcACAlkIGkCANYCABcACAlkIGkCANYCAAAA.Kestral:BAABLgAECn8jAAIVAAgJDBQiFAADAgAVAAgJDBQiFAADAgAAAA==.Keynis:BAAALgADCgEJAQAAAA==.',
Kh='Khalisi:BAAALgADCgYJBQAAAA==.Khejan:BAAALgADCgMJAwAAAA==.Khrask:BAAALgADCgIJAgABLgAFFAMJBgATAL8UAA==.',
Ki='Kiell:BAAALgAECgYJBwAAAA==.Kinuyo:BAAALgAECgQJBAAAAA==.Kiwipie:BAAALgAECgQJBAAAAA==.',
Kn='Knottyjack:BAAALgADCgMJAwAAAA==.Knoxic:BAAALgAECgcJDQAAAA==.',
Ko='Kookiie:BAACLgAFFH8OAAMfAAUJyx/DAQCBAQAfAAUJyx/DAQCBAQAeAAIJWQ1pKwCYAAAuAAQKfyQAAx8ACAnGILsJAMYCAB8ABwmAJbsJAMYCAB4ACAkuHLUkAHYCAAAA.Kookiiez:BAAALgAECgQJBAAAAA==.Koom:BAAALgADCgYJBQAAAA==.Kosian:BAAALgAECgYJDQABLgAECgcJBgACAAAAAA==.Kosigan:BAAALgAECgIJAgABLgAECggJKAAaANEiAA==.',
Kp='Kpop:BAAALgADCgEJAQAAAA==.',
Kr='Kromdor:BAABLgAECn8YAAIWAAgJSxoKBgBxAgAWAAgJSxoKBgBxAgAAAA==.Krosis:BAAALgAECggJDwAAAA==.',
Kt='Kthríss:BAAALgADCgMJAwAAAA==.',
Ku='Kungscott:BAAALgAECgEJAQABLgAFFAMJCQAMAG4MAA==.Kuromi:BAAALgAECgQJBAAAAA==.',
Ky='Kynei:BAABLgAECn8VAAIeAAgJtx5yAwBqAgAeAAgJtx5yAwBqAgAAAA==.',
La='Lacasis:BAAALgADCgUJBQABLgAECgYJCgACAAAAAA==.Larra:BAACLgAFFH8GAAIkAAMJmgv8CADYAAAkAAMJmgv8CADYAAAuAAQKfxsAAyQACAlrHScPAG8CACQACAlrHScPAG8CABsABgnvGyktAHUBAAAA.',
Le='Leman:BAAALgADCgkJFAAAAA==.Lemoncrisp:BAAALgAECgEJAQAAAA==.Leprocylarry:BAAALgADCgcJBwAAAA==.Letos:BAAALgAECgcJEgAAAA==.Levitas:BAABLgAECn8VAAIUAAcJWBKtBAB9AQAUAAcJWBKtBAB9AQAAAA==.Lewieballz:BAAALgADCgMJAwABLgAECgcJGQARAMEfAA==.',
Li='Liljit:BAAALgAECgcJCwAAAA==.Lithel:BAAALgAECgEJAQAAAA==.',
Lo='Loaded:BAAALgADCgEJAQAAAA==.Lockxeno:BAAALgAECgUJCQAAAA==.Logics:BAABLgAECn8jAAIbAAgJyyHnAAClAgAbAAgJyyHnAAClAgAAAA==.Lon:BAABLgAECn8YAAIKAAgJxRJeLAB9AQAKAAgJxRJeLAB9AQAAAA==.Lostea:BAAALgADCgUJBQABLgAECggJGQAaAJEXAA==.Lostmylimbs:BAABLgAECn8cAAIhAAgJfRO4EwDTAQAhAAgJfRO4EwDTAQABLgAFFAQJCgAXAEoLAA==.Lostmyvigor:BAAALgAECgMJBQAAAA==.Lostvoker:BAABLgAECn8ZAAMaAAgJkRe0FQAtAgAaAAgJkRe0FQAtAgAlAAUJehDjIgATAQAAAA==.Loueballz:BAABLgAECn8ZAAIRAAcJwR/HPgA8AgARAAcJwR/HPgA8AgAAAA==.Lowvice:BAAALgADCgEJAQAAAA==.',
Lu='Lucarad:BAABLgAECn8bAAIKAAgJ6hLBGwD+AQAKAAgJ6hLBGwD+AQAAAA==.Lucerfer:BAAALgADCgUJBwAAAA==.Lucivia:BAABLgAECn8cAAIYAAgJzxadAAD4AQAYAAgJzxadAAD4AQAAAA==.Lumafist:BAABLgAECn8eAAIKAAgJvCChCADvAgAKAAgJvCChCADvAgAAAA==.',
['Lè']='Lènneth:BAABLgAECn8aAAIkAAgJlBojAgBbAgAkAAgJlBojAgBbAgAAAA==.',
['Lí']='Líghtning:BAAALgAECgUJBgAAAA==.',
['Lø']='Løstdruid:BAAALgADCgEJAQABLgAECgUJCQACAAAAAA==.Løstpala:BAAALgAECgUJCQAAAA==.',
Ma='Mahiru:BAAALgADCgMJAwAAAA==.Makkaflocka:BAAALgAECgQJBAABLgAECgcJGAAeALEfAA==.Malleus:BAAALgADCgUJBQAAAA==.Malytheris:BAAALgAECgcJEQAAAA==.Marqis:BAAALgAECgEJAQAAAA==.Mattshanu:BAACLgAFFH8FAAIMAAIJJyC+EgDEAAAMAAIJJyC+EgDEAAAuAAQKfxgAAgwACAk7HLsUAHgCAAwACAk7HLsUAHgCAAAA.Mayalaran:BAAALgADCgcJDwAAAA==.Mazgruug:BAAALgAECgcJCQAAAA==.Mazkova:BAAALgAECgEJAQAAAA==.Mazur:BAABLgAECn8ZAAIGAAgJ6B9kCQD0AQAGAAgJ6B9kCQD0AQAAAA==.',
Mc='Mcmonkton:BAAALgAECgcJDAAAAA==.',
Me='Meirah:BAAALgADCgYJBAAAAA==.Mekkaweepz:BAAALgADCgUJBQAAAA==.Melaan:BAAALgAECgUJEAAAAA==.Melinadra:BAAALgAECgEJAQAAAA==.Meowmixx:BAAALgADCgYJBgAAAA==.Meowssa:BAEBLgAECn8lAAImAAgJWSU7AADdAgAmAAgJWSU7AADdAgAAAA==.',
Mi='Midori:BAAALgAECgEJAQAAAA==.Mindleseye:BAAALgADCgQJBgAAAA==.Mindlesscon:BAABLgAECn8UAAMPAAYJ0x7WDAD1AQAPAAYJph3WDAD1AQAMAAUJGRyJPABaAQAAAA==.Minislayer:BAAALgAECgYJEAAAAA==.Minyprayers:BAACLgAFFH8KAAIbAAQJhBdrBgBgAQAbAAQJhBdrBgBgAQAuAAQKfxsAAhsACAk0IEMKAN4CABsACAk0IEMKAN4CAAAA.Minywon:BAAALgADCgcJCgABLgAFFAQJCgAbAIQXAA==.Misosalty:BAABLgAECn8dAAMKAAgJLB/dAQA8AgAKAAgJLB/dAQA8AgAJAAQJOw62ZQCrAAAAAA==.Misowet:BAAALgADCgYJCQABLgAECggJHQAKACwfAA==.',
Ml='Mlorpglorp:BAABLgAECn8cAAIDAAcJQyB0PQCCAgADAAcJQyB0PQCCAgAAAA==.',
Mo='Mobaye:BAAALgAECgEJAQAAAA==.Mohjito:BAABLgAECn8dAAMKAAgJnxmmHAD2AQAKAAgJixmmHAD2AQAJAAUJABEMEQDjAAAAAA==.Mojojojoz:BAAALgADCgUJBQAAAA==.Monkisbad:BAABLgAECn8cAAIJAAcJUCRkDADJAgAJAAcJUCRkDADJAgAAAA==.Moonfire:BAAALgADCgcJDgAAAA==.Moose:BAAALgADCgYJBgAAAA==.Mooshanu:BAAALgADCgcJDAABLgAFFAIJBQAMACcgAA==.Morguth:BAACLgAFFH8GAAMcAAMJBw5YFACyAAAcAAIJ4hRYFACyAAAjAAIJUQCSIwBdAAAuAAQKfxcAAxwACAkEHigUAJUCABwACAkEHigUAJUCACMABAkeBLdoAJsAAAAA.Moriko:BAAALgAECgYJEgAAAA==.',
Mu='Murky:BAAALgAECgcJDAAAAA==.Musicmichael:BAAALgAECgYJBgAAAA==.',
['Mî']='Mîyagî:BAAALgAECgcJCQAAAA==.',
['Mö']='Mööbs:BAABLgAECn8WAAMVAAcJBQeaJwA3AQAVAAcJBQeaJwA3AQAaAAQJngYOSwCnAAAAAA==.',
Na='Namad:BAAALgAECgYJDwAAAA==.Nancybrew:BAABLgAECn8cAAMKAAgJXB/2AQA1AgAKAAgJXB/2AQA1AgASAAIJdRKLWABtAAAAAA==.Nathric:BAAALgADCgUJBQAAAA==.Navajo:BAAALgAECgYJDgAAAA==.',
Ne='Neature:BAAALgADCgMJAwAAAA==.Neoma:BAAALgAECgQJCAAAAA==.Nesqwik:BAAALgADCggJDgAAAA==.Nevan:BAABLgAECn8WAAIFAAcJeCRWEQCIAgAFAAcJeCRWEQCIAgAAAA==.Neverender:BAAALgAECgEJAgAAAA==.Newlock:BAAALgAECgQJBAAAAA==.Nexi:BAAALgAECgMJAwAAAA==.',
Ni='Niang:BAAALgADCgQJBAAAAA==.Nippyvixen:BAAALgADCgcJBwAAAA==.Nishu:BAAALgADCgMJAwAAAA==.',
No='Noochallange:BAABLgAECn8WAAIZAAcJ7R4uAQDfAQAZAAcJ7R4uAQDfAQAAAA==.Norex:BAABLgAECn8bAAMRAAgJXw7bWgDhAQARAAgJ3A3bWgDhAQAhAAYJnwi3LADZAAAAAA==.Norm:BAAALgAECgIJAwAAAA==.Notekk:BAAALgAECgEJAwAAAA==.',
Nu='Nuggie:BAABLgAECn8aAAMNAAcJLh0XCgDSAQANAAYJLh0XCgDSAQAWAAEJAAC5YgBJAAAAAA==.Nurf:BAAALgADCgMJAwAAAA==.Nurgal:BAAALgAECgYJCAAAAA==.Nutlips:BAAALgADCgUJCwAAAA==.',
Ny='Nylariaa:BAAALgAECgQJCgAAAA==.Nymia:BAABLgAECn8bAAIOAAcJQh6WJAAoAgAOAAcJQh6WJAAoAgAAAA==.',
['Næ']='Næon:BAABLgAECn8WAAISAAcJ+xZ+HQDLAQASAAcJ+xZ+HQDLAQAAAA==.',
Ob='Oblake:BAABLgAECn8YAAILAAcJkBQjIQDwAQALAAcJkBQjIQDwAQAAAA==.',
Oc='Octosloth:BAAALgADCgEJAQAAAA==.',
Oh='Ohhashbrowns:BAAALgADCgcJBwAAAA==.',
Ok='Oku:BAAALgADCgcJBgAAAA==.',
Ol='Oldmagic:BAAALgAECgYJBwAAAA==.Olizza:BAAALgAECgIJAgABLgAECgYJCwACAAAAAA==.',
Om='Omgimabeast:BAAALgAECgYJCAAAAA==.',
On='Onieva:BAAALgAECgcJDAAAAA==.',
Oo='Ooglaboogla:BAABLgAECn8ZAAMMAAgJwRfkBQCzAQAMAAgJwRfkBQCzAQAQAAIJhxySggCJAAAAAA==.',
Or='Oriah:BAAALgADCgYJBgAAAA==.Orions:BAAALgADCgQJBAAAAA==.',
Os='Osserc:BAAALgADCgYJBgAAAA==.',
Ox='Oxyrotten:BAABLgAECn8UAAIRAAYJ2wvXJgD4AAARAAYJ2wvXJgD4AAAAAA==.',
Pa='Pablo:BAABLgAECn8tAAMIAAkJxSBWAADJAgAIAAkJxSBWAADJAgAjAAEJZRGvhgA1AAAAAA==.Pancho:BAAALgAECgcJEgAAAA==.Pandra:BAAALgADCgEJAQAAAA==.Panttyraider:BAAALgAECgUJBQAAAA==.Panzeria:BAABLgAECn8bAAIbAAcJPSU2CQDwAgAbAAcJPSU2CQDwAgAAAA==.Pathryis:BAAALgAECgYJBgAAAA==.Pawsome:BAAALgADCgIJAgAAAA==.',
Pl='Plank:BAAALgAECgUJBwAAAA==.',
Pm='Pmon:BAAALgADCgEJAQAAAA==.',
Po='Pongo:BAAALgAECgUJCQAAAA==.Ponkofox:BAAALgAECggJDwAAAA==.',
Pr='Prah:BAAALgAECgIJAwAAAA==.Prepared:BAAALgAECgIJAgAAAA==.Prisefather:BAAALgAECgYJCgAAAA==.Prizefighter:BAAALgAECgYJBgAAAA==.Proditus:BAAALgAECgMJAwAAAA==.',
Pu='Puzzlewalrus:BAAALgADCgQJBAAAAA==.',
Py='Pyreiella:BAAALgADCgUJBQAAAA==.Pyroamor:BAAALgAECgEJAQAAAA==.Pyropete:BAAALgADCgIJAwAAAA==.',
['Pä']='Pälii:BAABLgAECn8UAAMFAAcJwwTuEQAhAQAFAAcJwwTuEQAhAQAGAAQJhA4Z4QDLAAAAAA==.',
Qc='Qcomberoo:BAAALgADCgMJAwAAAA==.',
Ra='Ragublaster:BAAALgAECgEJAQAAAA==.Ralickan:BAAALgADCgcJBQAAAA==.Ramaan:BAAALgAECggJCAAAAA==.Ramble:BAAALgAECgcJDQAAAA==.Ravette:BAABLgAECn8fAAMfAAgJDyIaAgAHAgAfAAgJDyIaAgAHAgAXAAMJlhNVHgCVAAAAAA==.Ravissante:BAAALgAECgYJEAAAAA==.Rawranator:BAAALgAECgUJCwAAAA==.',
Re='Reesecupthis:BAABLgAECn8UAAIHAAcJpiBeBQCiAgAHAAcJpiBeBQCiAgABLgAFFAQJCwAHAI4bAA==.Remagix:BAAALgAECgEJAQAAAA==.Revek:BAAALgADCgEJAQAAAA==.Reveurus:BAAALgADCgcJBwABLgAECgcJFgAFAHgkAA==.Rezzaleya:BAAALgADCgQJBAAAAA==.',
Rh='Rhaena:BAAALgAECgYJDQABLgAECgcJDAACAAAAAA==.',
Ri='Riceroll:BAABLgAECn8bAAMNAAcJJCDTCgDIAQANAAYJ4B7TCgDIAQAWAAQJIB0xJAA4AQAAAA==.Ricochet:BAAALgAECgYJEgAAAA==.Riseordie:BAAALgADCgYJCAAAAA==.',
Ro='Ronnycoleman:BAAALgAECgMJAwAAAA==.Roofonfire:BAAALgAECggJDgAAAA==.Rowyn:BAAALgADCgEJAQAAAA==.',
Ru='Runeka:BAABLgAECn8eAAInAAgJ5iRsBwDLAgAnAAgJ5iRsBwDLAgAAAA==.Rusalkha:BAAALgADCgEJAQAAAA==.Ruteefear:BAAALgAECgUJCQAAAA==.',
Ry='Rybes:BAAALgAECgUJDAAAAA==.Rychesus:BAAALgADCgYJBgABLgAECgUJCQACAAAAAA==.',
Sa='Safehaven:BAAALgADCggJEAAAAA==.Saintcloud:BAAALgADCgkJEAAAAA==.Sairuwki:BAAALgADCggJFwAAAA==.Samwìse:BAACLgAFFH8IAAIkAAMJbA88BADOAAAkAAMJbA88BADOAAAuAAQKfykAAyQACAnBG3QOAHYCACQACAnBG3QOAHYCABsABQkgDUIQAPMAAAAA.Sareir:BAAALgADCgMJAwAAAA==.Sato:BAAALgAECgEJAQAAAA==.Savagex:BAAALgADCgYJBgAAAA==.Saveena:BAAALgAECgUJCAAAAA==.',
Sc='Scarlla:BAAALgAECgcJDAAAAA==.Scorber:BAAALgAECgIJAgAAAA==.',
Se='Searingbear:BAAALgADCgQJBAABLgAECggJGgAKAEYXAA==.Senggolbacok:BAAALgAFFAIJAgAAAA==.Senseitheta:BAAALgAECgEJAgABLgAECgUJCQACAAAAAA==.Sepherios:BAAALgADCgYJBgAAAA==.Serengenuity:BAAALgAECgIJAgAAAA==.Serenidin:BAAALgADCgcJBwAAAA==.Serenio:BAAALgAECgEJAwAAAA==.Sereniswift:BAAALgAECgQJBAAAAA==.Serephita:BAABLgAECn8dAAIDAAgJgAfbrwB9AQADAAgJgAfbrwB9AQAAAA==.',
Sg='Sgtsnipe:BAAALgAECgQJBQAAAA==.',
Sh='Shakys:BAAALgAECgUJDAAAAA==.Shalaylea:BAAALgAECgQJBgAAAA==.Shamwich:BAAALgAECgMJAgAAAA==.Shanondorf:BAAALgAECgUJCwAAAA==.Shark:BAAALgAECgQJBQABLgAFFAQJCgARACIMAA==.Shaymist:BAAALgAECgMJAwAAAA==.Sheeplord:BAAALgADCgQJBgAAAA==.Sheepstealer:BAABLgAECn8bAAMaAAgJdg/6CABYAQAaAAgJdg/6CABYAQAlAAQJLgI8NAByAAAAAA==.Shiggyll:BAAALgADCgIJAgAAAA==.Shildo:BAABLgAECn8aAAMbAAcJxReOBgCaAQAbAAcJxReOBgCaAQAnAAEJQQuuVAA4AAAAAA==.Shirokuma:BAAALgAECgMJAwAAAA==.Shiryunuri:BAAALgADCgUJCAAAAA==.Shizzo:BAAALgAECgEJAQAAAA==.Shockrock:BAAALgAECgQJBQAAAA==.Shybuzz:BAAALgADCgcJCwAAAA==.Shøstákovich:BAAALgADCgEJAQAAAA==.',
Si='Sifen:BAAALgAECgQJBAABLgAFFAMJCQAMAG4MAA==.Silecra:BAAALgADCgcJBwABLgAECggJHgAnAOYkAA==.Sinscale:BAAALgAECgQJBAABLgAFFAUJDgAGAKMdAA==.Sinswrath:BAACLgAFFH8OAAIGAAUJox0YCAByAQAGAAUJox0YCAByAQAuAAQKfyQAAgYACAkWJH4JAEUDAAYACAkWJH4JAEUDAAAA.',
Sk='Skarre:BAABLgAECn8jAAIeAAcJ4BwwMAA6AgAeAAcJ4BwwMAA6AgAAAA==.Skcusnor:BAAALgAECgcJEQAAAA==.Skelevyrn:BAAALgADCgEJAQAAAA==.Skimnms:BAAALgADCgUJBgAAAA==.Skrimbly:BAAALgAECgEJAQAAAA==.',
Sl='Slaye:BAAALgAECggJEgAAAA==.',
Sm='Smiteheal:BAAALgADCgMJAwAAAA==.Smores:BAACLgAFFH8GAAIOAAMJ3CIUCgA3AQAOAAMJ3CIUCgA3AQAuAAQKfxsAAg4ACAmJJakEAEQDAA4ACAmJJakEAEQDAAEuAAUUBQkSAA4ARyUA.Smrts:BAAALgAECggJCwAAAA==.',
Sn='Snaccident:BAABLgAECn8nAAMaAAkJtBHyIAC4AQAaAAkJtBHyIAC4AQAlAAEJwQBlRgAZAAAAAA==.Snaccidentsh:BAAALgADCgMJAgABLgAECgkJJwAaALQRAA==.Snaccidentww:BAAALgAECgYJBgABLgAECgkJJwAaALQRAA==.Sneakyteeth:BAAALgAECgcJEgAAAA==.Snotzz:BAAALgAECgUJBgAAAA==.',
So='Sojukai:BAAALgAECgEJAQAAAA==.Sok:BAAALgAECgUJDgAAAA==.Solonör:BAAALgADCgcJCAAAAA==.Songi:BAABLgAECn8fAAIRAAgJECJyKACZAgARAAgJECJyKACZAgAAAA==.Soulwhisper:BAACLgAFFH8OAAIRAAUJ0xOXBgBXAQARAAUJ0xOXBgBXAQAuAAQKfyQAAhEACAlWI0sVAPwCABEACAlWI0sVAPwCAAAA.',
Sp='Spicynoodi:BAABLgAECn8bAAMlAAcJfAfOHQA/AQAlAAcJfAfOHQA/AQAaAAIJ7AT+HABTAAAAAA==.Spyrodruid:BAAALgAECgQJBAAAAA==.Spyromonk:BAAALgAECgIJAgABLgAECgQJBAACAAAAAA==.',
Sq='Sqoots:BAABLgAECn8ZAAIDAAgJBCFyIQDuAgADAAgJBCFyIQDuAgAAAA==.',
St='Stankyfist:BAAALgAECgUJCAAAAA==.Starfeish:BAAALgAECgYJBwAAAA==.Stepzlol:BAAALgADCgIJAwAAAA==.Stopresistin:BAAALgAECgUJCQAAAA==.Stormsinger:BAABLgAECn8cAAMMAAgJiBWYCAB1AQAMAAcJOBeYCAB1AQAQAAcJfg+ETgBJAQAAAA==.',
Su='Succubis:BAAALgADCgIJAgAAAA==.Sugarblast:BAACLgAFFH8JAAIMAAQJGBd9CQBIAQAMAAQJGBd9CQBIAQAuAAQKfyEAAgwACAnrIwILAOcCAAwACAnrIwILAOcCAAAA.Sukker:BAAALgAECgEJAQAAAA==.Sukkler:BAAALgADCgYJBgAAAA==.Sumtingwong:BAAALgADCgYJBgAAAA==.Suou:BAACLgAFFH8GAAMTAAMJvxSuDwAMAQATAAMJ1BKuDwAMAQAgAAEJegmQCwBUAAAuAAQKfxsAAxMACAmaH9IhAEYCABMABwl8H9IhAEYCACAAAQlRIAA1AFwAAAAA.Superchicken:BAAALgAECgIJAgAAAA==.Surfbird:BAAALgAECgYJBgAAAA==.',
Sv='Svekkê:BAAALgAECgcJBwAAAA==.',
Sw='Swagmeoutbro:BAAALgADCgIJAgAAAA==.',
Sy='Sylint:BAAALgAECgYJCQAAAA==.Sylvara:BAAALgAECgUJBwAAAA==.Sylverlock:BAAALgADCgkJCQAAAA==.',
Ta='Tacosdk:BAAALgAECgUJBQAAAA==.Tacoss:BAAALgAECgIJAgAAAA==.Tandragosa:BAAALgAECgMJBAABLgAECggJHAAMAIgVAA==.Tankadiin:BAAALgAECgQJBAAAAA==.Tannica:BAAALgADCgYJBgAAAA==.Tanthyr:BAAALgADCgQJBAAAAA==.Tayswiftagos:BAAALgAECgcJCQAAAA==.',
Te='Teddy:BAAALgADCgMJAwAAAA==.Teddyy:BAAALgAECgYJBgAAAA==.Texazmade:BAAALgAECgUJBgAAAA==.',
Th='Thagomizer:BAAALgADCgIJAgAAAA==.Thedevilssin:BAAALgAECgYJBgAAAA==.Thefool:BAAALgADCgYJBgAAAA==.Theocles:BAAALgADCgYJDgAAAA==.Theodas:BAAALgAECgYJCAAAAA==.Therru:BAAALgADCggJGAABLgAECgYJEgACAAAAAA==.Thorimm:BAAALgADCgQJBAAAAA==.Throbbert:BAAALgADCgcJBwABLgAECgUJCwACAAAAAA==.Thunderwater:BAAALgAECgMJBAAAAA==.',
Ti='Tiktok:BAAALgAECgUJEQABLgAECgcJCQACAAAAAA==.Tippss:BAABLgAECn8pAAIkAAgJuyX5AQBUAwAkAAgJuyX5AQBUAwAAAA==.',
To='Tokenbeef:BAABLgAECn8WAAMQAAYJFBNNSgBZAQAQAAYJFBNNSgBZAQAMAAMJRAQDdgBqAAAAAA==.Tokenshaman:BAAALgAECgYJDwAAAA==.Torlon:BAAALgADCgEJAQAAAA==.Toxicshamy:BAABLgAECn8YAAQPAAcJahZVAwCbAQAMAAcJ0BMhKQDLAQAPAAUJ6RhVAwCbAQAQAAEJrRgVKQBJAAAAAA==.',
Tr='Trafficcones:BAAALgAECgEJAQAAAA==.Traugdor:BAAALgADCgUJBQAAAA==.Traylay:BAACLgAFFH8GAAIGAAMJCRWSEwAKAQAGAAMJCRWSEwAKAQAuAAQKfxsAAgYACAmQJJwMACkDAAYACAmQJJwMACkDAAAA.Traylei:BAAALgADCgcJBwABLgAFFAMJBgAGAAkVAA==.Trio:BAAALgADCgUJBQAAAA==.Trixaintime:BAABLgAECn8WAAIGAAYJUQlnqwArAQAGAAYJUQlnqwArAQAAAA==.',
Ts='Tsm:BAAALgADCgYJBgAAAA==.',
Tt='Ttocs:BAACLgAFFH8JAAIMAAMJbgzOEADpAAAMAAMJbgzOEADpAAAuAAQKfxgAAgwACAlMI8sGACYDAAwACAlMI8sGACYDAAAA.',
Tu='Tujori:BAACLgAFFH8FAAInAAQJCwvtDgDgAAAnAAQJCwvtDgDgAAAuAAQKfx0AAyQACAmfEpYuAIkBACQACAlJC5YuAIkBACcABglEErQlAGcBAAAA.Turuce:BAAALgADCgUJBQAAAA==.',
Tv='Tv:BAAALgADCgcJBwABLgAECgMJAwACAAAAAA==.',
Tw='Twherk:BAAALgAECgcJDQABLgAFFAUJCgAnAD0QAA==.Twinmoonfury:BAABLgAECn8jAAMBAAcJZRDMCQBRAQABAAcJZRDMCQBRAQAOAAYJPBO5WgBCAQAAAA==.',
Ty='Tylann:BAAALgADCgIJAgAAAA==.Tynestra:BAAALgAECgkJBwAAAA==.',
['Tí']='Tíger:BAAALgADCgQJAwAAAA==.',
['Tü']='Tüyria:BAAALgADCgMJAwAAAA==.',
Ug='Uglydorf:BAABLgAECn8YAAIcAAcJZhxPNQDZAQAcAAcJZhxPNQDZAQAAAA==.',
Ul='Ulraka:BAAALgADCgEJAQAAAA==.Ultraviolenc:BAAALgAECgEJAQAAAA==.',
Un='Unholydiver:BAAALgADCgEJAQAAAA==.',
Va='Vaeros:BAAALgAECgYJDQAAAA==.Valantis:BAEALgAECgQJBQAAAA==.Valcantor:BAAALgADCgYJBgAAAA==.Vanyss:BAAALgADCgYJBgAAAA==.',
Ve='Vekz:BAABLgAECn8bAAIFAAgJAB/iAwA7AgAFAAgJAB/iAwA7AgAAAA==.Velazq:BAAALgADCgEJAgAAAA==.Velicia:BAAALgAECgcJEQAAAA==.Velithice:BAAALgAECgIJAgAAAA==.Venture:BAAALgADCgYJBgAAAA==.',
Vo='Voidnjoyr:BAAALgAECgEJAQAAAA==.',
Wa='Walsun:BAAALgADCgcJBwABLgAECggJHAAMAIgVAA==.Warhéad:BAAALgAECgUJDAAAAA==.Wartonxp:BAABLgAECn8lAAIbAAgJnB1AAwAGAgAbAAgJnB1AAwAGAgAAAA==.Waterbôy:BAABLgAECn8pAAQMAAgJdCEiAwAVAgAMAAgJdCEiAwAVAgAQAAUJYgmTZwDwAAAPAAIJLQUEKABcAAAAAA==.Waynee:BAAALgAECgIJAwAAAA==.',
We='Weepylight:BAAALgAECgMJAwAAAA==.Weissbrew:BAAALgADCgUJBQAAAA==.',
Wh='Wheezy:BAAALgAFFAIJAgAAAA==.Whoasked:BAABLgAECn8oAAMaAAgJ0SLKAAC+AgAaAAgJ0SLKAAC+AgAlAAYJSRchHABPAQAAAA==.',
Wi='Wiggle:BAABLgAECn8cAAIEAAkJ6RoQAgCLAgAEAAkJ6RoQAgCLAgAAAA==.Wildslayer:BAAALgADCgUJBQAAAA==.',
Wt='Wtfheal:BAACLgAFFH8KAAInAAUJPRD6CQA/AQAnAAUJPRD6CQA/AQAuAAQKfxkAAicACAljIbEFAPMCACcACAljIbEFAPMCAAAA.',
Xa='Xanistra:BAABLgAECn8bAAMNAAgJWSJJDQAQAwANAAgJWSJJDQAQAwAWAAQJvxxVLQAIAQAAAA==.Xaylor:BAAALgADCgcJCgAAAA==.',
Ya='Yalaforth:BAABLgAECn8ZAAIGAAcJlBKlHgA3AQAGAAcJlBKlHgA3AQAAAA==.Yamashaman:BAABLgAECn8WAAIQAAkJ+BHlHwAgAgAQAAkJ+BHlHwAgAgAAAA==.Yardgnome:BAAALgAECgEJAQAAAA==.',
Ye='Yebefd:BAAALgADCgUJBQAAAA==.',
Yu='Yungbluudd:BAAALgADCgIJAgAAAA==.',
Za='Zaleth:BAAALgAECgQJBAAAAA==.Zamasu:BAABLgAECn8YAAIeAAcJsR/oBAA9AgAeAAcJsR/oBAA9AgAAAA==.Zapmybitzup:BAAALgAFFAIJAwAAAA==.Zaroneus:BAAALgADCgUJBQAAAA==.Zaszadin:BAECLgAFFH8HAAIGAAMJmR7hBwARAQAGAAMJmR7hBwARAQAuAAQKfyQAAgYACAmMIuoZAM0CAAYACAmMIuoZAM0CAAAA.Zaszhadoom:BAEALgAECgEJAQABLgAFFAMJBwAGAJkeAA==.Zaxxon:BAABLgAECn8bAAMaAAgJKxpoAgAmAgAaAAgJKxpoAgAmAgAlAAEJDQ2+PgA0AAAAAA==.',
Ze='Zekt:BAAALgADCgQJBAAAAA==.Zelo:BAAALgAECgYJCQAAAA==.Zensi:BAAALgAECgEJAQAAAA==.Zerax:BAABLgAECn8fAAIVAAcJNxvfAgDVAQAVAAcJNxvfAgDVAQAAAA==.',
Zi='Zigfury:BAAALgAECgYJCgAAAA==.Zillagoth:BAAALgAECgMJAgAAAA==.Zira:BAABLgAECn8XAAISAAYJcxCGDAAcAQASAAYJcxCGDAAcAQAAAA==.',
Zo='Zombiebrainz:BAAALgAECgUJCQAAAA==.Zombiebubble:BAAALgAECgYJCAAAAA==.Zoìdberg:BAACLgAFFH8HAAIQAAIJuhORFwCdAAAQAAIJuhORFwCdAAAuAAQKfysAAhAACAkDIrAHAPoCABAACAkDIrAHAPoCAAAA.',
Zs='Zselk:BAAALgADCgYJCAAAAA==.',
Zu='Zubzer:BAAALgAECgYJDwAAAA==.',
Zz='Zzor:BAACLgAFFH8LAAIDAAQJExeWCQBTAQADAAQJExeWCQBTAQAuAAQKfyIAAgMACAnAJQkPAE8DAAMACAnAJQkPAE8DAAAA.Zzorfel:BAAALgAECgEJAQABLgAFFAQJCwADABMXAA==.',
['Ði']='Ðii:BAAALgAECgMJAwAAAA==.',
['ßl']='ßlue:BAAALgAECgYJEgABLgAECgcJHAAJAFscAA==.',
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

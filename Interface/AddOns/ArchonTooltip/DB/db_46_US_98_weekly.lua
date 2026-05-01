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

local lookup = {'Druid-Balance','Warrior-Arms','Warrior-Fury','Unknown-Unknown','Mage-Frost','Mage-Arcane','Paladin-Holy','Monk-Mistweaver','Paladin-Retribution','Paladin-Protection','Hunter-Survival','Monk-Brewmaster','Monk-Windwalker','Shaman-Elemental','Warlock-Demonology','Druid-Restoration','Shaman-Enhancement','Warlock-Affliction','Warlock-Destruction','Priest-Shadow','Shaman-Restoration','DeathKnight-Unholy','Warrior-Protection','Evoker-Preservation','DemonHunter-Vengeance','Rogue-Subtlety','Rogue-Assassination','Evoker-Augmentation','Hunter-BeastMastery','Druid-Feral','DemonHunter-Devourer','DeathKnight-Blood','DeathKnight-Frost','Hunter-Marksmanship','DemonHunter-Havoc','Priest-Holy','Priest-Discipline','Evoker-Devastation','Druid-Guardian',}
local provider = {region='US',realm='Frostmane',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Aberdus:BAABLgAECn8YAAIBAAcJDxUIEwBwAQABAAcJDxUIEwBwAQAAAA==.',
Ac='Accalon:BAABLgAECn8WAAMCAAcJSxhkBwCbAQACAAcJSxhkBwCbAQADAAEJ+wdNqQA1AAABLgAECgYJEgAEAAAAAA==.',
Ad='Adina:BAAALgAECgYJBgAAAA==.Advacus:BAACLgAFFH8KAAMFAAQJOxDWIgBJAQAFAAQJOxDWIgBJAQAGAAEJbxN/AQBVAAAuAAQKfyIAAwYACAmLHv8BAJACAAYACAmWGv8BAJACAAUACAkLGkxQAEYCAAAA.',
Ai='Aicila:BAAALgADCgEJAQAAAA==.Aimer:BAAALgAECgEJAQAAAA==.Airi:BAAALgADCgYJCAAAAA==.',
Ak='Akrama:BAABLgAECn8iAAIHAAgJ8xukCwAdAgAHAAgJ8xukCwAdAgAAAA==.',
Al='Alara:BAAALgADCgkJEwAAAA==.Alatáriel:BAAALgAECgEJAQAAAA==.Alectrona:BAAALgAECgIJBAAAAA==.Aletriss:BAAALgAECgIJAgAAAA==.Alexsham:BAAALgAECgEJAQAAAA==.Algaraz:BAAALgAECgYJDgAAAA==.',
Am='Ama:BAAALgADCgYJDAAAAA==.Amnorpse:BAAALgAECgYJEwAAAA==.',
An='Anabana:BAAALgAECgQJCwAAAA==.Angler:BAABLgAECn8UAAIIAAgJKxenCAApAgAIAAgJKxenCAApAgAAAA==.Anruu:BAAALgAECgUJBQAAAA==.',
Ap='Appollis:BAAALgADCgQJBAAAAA==.Appropriate:BAAALgADCgMJAwAAAA==.',
Ar='Araleth:BAAALgADCggJEAAAAA==.Arkthurus:BAAALgAECgYJCgAAAA==.Artumis:BAAALgADCgEJAQAAAA==.Arvitherejet:BAAALgAECgQJBAAAAA==.',
As='Aschern:BAAALgAECgYJDAAAAA==.Ashijin:BAACLgAFFH8LAAIJAAQJ0hVAEABFAQAJAAQJ0hVAEABFAQAuAAQKfyMAAgkACAl4HxAmAI4CAAkACAl5HxAmAI4CAAAA.Ashilyn:BAAALgAECgEJAQAAAA==.Ashoo:BAAALgADCgEJAQAAAA==.Astei:BAAALgADCgEJAQAAAA==.',
At='Ataxxius:BAAALgADCgMJAwAAAA==.Atheristina:BAAALgAECgQJBAABLgAECgUJEgAEAAAAAA==.Atroce:BAAALgAECgEJAgAAAA==.Atticu:BAAALgAECgMJAwAAAA==.',
Au='Aura:BAABLgAECn8kAAIHAAkJUhenHwAcAgAHAAkJUhenHwAcAgAAAA==.Auxilium:BAABLgAECn8UAAIJAAcJxBjNSAAIAgAJAAcJxBjNSAAIAgAAAA==.',
Aw='Awnen:BAAALgAECgMJBwAAAA==.',
Az='Aza:BAAALgADCgIJAgAAAA==.',
Ba='Backtrakk:BAAALgADCgMJAwAAAA==.Bahndis:BAAALgADCgcJDAAAAA==.Balebrew:BAAALgADCgQJBAABLgAECggJKAAKAJMkAA==.Balethar:BAAALgAECgYJDgABLgAECggJKAAKAJMkAA==.Ballador:BAAALgAECgQJBAAAAA==.Balluh:BAABLgAECn8fAAILAAgJoxZ0CwCpAQALAAgJoxZ0CwCpAQAAAA==.',
Be='Beartest:BAAALgAECgMJBAABLgAECggJFgAMAOYaAA==.Beezen:BAACLgAFFH8SAAINAAUJFxl0AwBoAQANAAUJFxl0AwBoAQAuAAQKfyUAAg0ACAm/IUcFADADAA0ACAm/IUcFADADAAAA.Belara:BAAALgADCgUJBgAAAA==.Bellevo:BAAALgAECgQJBAABLgAECggJIwAFABggAA==.Bellmage:BAABLgAECn8jAAMFAAgJGCBGDgBsAgAFAAgJGCBGDgBsAgAGAAEJxAlpHwAxAAAAAA==.Belttoash:BAABLgAECn8eAAIJAAcJhRSzYADCAQAJAAcJhRSzYADCAQAAAA==.Beneficiary:BAAALgAECgQJBQAAAA==.Bercey:BAAALgAECgYJCQAAAA==.Beybladetest:BAABLgAECn8WAAIMAAgJ5hoDFgBaAgAMAAgJ5hoDFgBaAgAAAA==.',
Bi='Bigmang:BAAALgADCgYJBgAAAA==.Bigmayex:BAAALgADCgkJDQAAAA==.Bigscott:BAAALgAECgMJAwABLgAFFAMJCQAOAG4MAA==.Binky:BAAALgADCgIJAgAAAA==.',
Bl='Blackbride:BAAALgAECgEJAQAAAA==.Blackfyre:BAAALgAECgIJBAAAAA==.Blackmage:BAAALgAECgYJDgAAAA==.Blizzlock:BAABLgAECn8cAAIPAAYJfxFZQgAqAQAPAAYJfxFZQgAqAQAAAA==.Blood:BAAALgAECgIJAwAAAA==.Bloodfeast:BAAALgADCgYJBgAAAA==.Blooms:BAAALgADCgIJAgAAAA==.Blurednuhtz:BAAALgADCgYJCQAAAA==.',
Bo='Bobcatross:BAAALgADCgYJBgAAAA==.Bohvicce:BAAALgADCgEJAQAAAA==.Bokudo:BAAALgADCgMJAwAAAA==.Bonezs:BAABLgAECn8oAAIQAAgJjyPCBQDAAgAQAAgJjyPCBQDAAgAAAA==.Boogiepop:BAAALgAECgcJDQAAAA==.Bootylika:BAABLgAECn8YAAIDAAgJ1BOjLgD3AQADAAgJ1BOjLgD3AQAAAA==.Borislav:BAAALgADCgEJAQAAAA==.Bossvega:BAAALgADCgYJCAAAAA==.Boutdatbass:BAAALgAECgIJAgAAAA==.',
Br='Braxxar:BAAALgAECgUJCQAAAA==.Brendelf:BAAALgADCgEJAQAAAA==.Brett:BAAALgAECgEJAgAAAA==.Briellia:BAAALgAECgEJAwAAAA==.Bruggerlock:BAEALgADCgMJAwAAAA==.Bryagh:BAAALgAECgYJEQAAAA==.',
Bu='Bubbam:BAAALgADCgYJCAAAAA==.Bufferbug:BAAALgADCgkJFAAAAA==.Bugbear:BAAALgAECgEJAQAAAA==.Bulge:BAAALgADCgUJBQABLgAFFAEJAQAEAAAAAA==.Bullycow:BAABLgAECn8XAAIRAAYJJgUcDwDeAAARAAYJJgUcDwDeAAAAAA==.Bushybrowsy:BAABLgAECn8ZAAMSAAgJjwrUCQCjAQASAAgJjwrUCQCjAQATAAMJRwJzXQBWAAAAAA==.Buttercupz:BAABLgAECn8WAAIUAAgJoQudMgBRAQAUAAgJoQudMgBRAQAAAA==.',
['Bá']='Bámboo:BAAALgAECgEJAQAAAA==.',
['Bî']='Bîgdaddy:BAABLgAECn8gAAMVAAgJdxc+DQAZAgAVAAgJdxc+DQAZAgAOAAQJmgNjagCaAAAAAA==.',
Ca='Cacho:BAAALgAECgEJAgAAAA==.Calevan:BAAALgAECgkJDwAAAA==.Candoran:BAAALgADCgMJAwAAAA==.Caracarn:BAAALgAECgYJBwAAAA==.Carpulations:BAABLgAECn8XAAIPAAYJEBikhABRAQAPAAYJEBikhABRAQAAAA==.',
Cc='Ccyll:BAAALgADCgkJEgAAAA==.',
Ce='Cerofewol:BAAALgADCgMJAwABLgAECgUJBwAEAAAAAA==.Cerridwen:BAAALgAECgYJDAAAAA==.',
Ch='Chantini:BAAALgAECgUJBQAAAA==.Chartreuze:BAAALgAECgIJAgAAAA==.Chazmonk:BAAALgAECgEJAQABLgAFFAMJAwAEAAAAAA==.Chazzie:BAAALgAFFAMJAwAAAA==.Cheonsul:BAAALgADCgMJAwAAAA==.Chia:BAACLgAFFH8OAAIWAAQJUxLMHQBCAQAWAAQJUxLMHQBCAQAuAAQKfxsAAhYABwlfHZpQAAACABYABwlfHZpQAAACAAAA.Chikn:BAABLgAECn8XAAIIAAgJ8xRVGAD7AQAIAAgJ8xRVGAD7AQAAAA==.Chirichiri:BAAALgADCgIJAwAAAA==.Chizu:BAAALgADCgUJBQABLgAFFAQJCgADAEMVAA==.Chomboslice:BAABLgAECn8aAAIHAAgJ6h1eEgB/AgAHAAgJ6h1eEgB/AgAAAA==.',
Cl='Clary:BAAALgADCgEJAQABLgAECgcJGgAMAEoYAA==.Classy:BAAALgAECgEJAQAAAA==.',
Cm='Cmil:BAACLgAFFH8NAAMHAAQJcxOqCwA4AQAHAAQJcxOqCwA4AQAJAAEJkgElTAAvAAAuAAQKfx8AAwcACAnwC8Y4AJcBAAcACAnwC8Y4AJcBAAkAAQnODcpCATMAAAAA.',
Co='Coffeebrew:BAAALgAECgUJBQABLgAECgYJDAAEAAAAAA==.Coffeecrem:BAAALgAECgYJDAAAAA==.Coffie:BAAALgADCgUJBQABLgAECgYJDAAEAAAAAA==.Coldnoodles:BAAALgADCgMJAgABLgAECggJJQANAPcfAA==.Combat:BAACLgAFFH8PAAIDAAUJuROnCQBIAQADAAUJuROnCQBIAQAuAAQKfx4AAgMACAktHk4VAKMCAAMACAktHk4VAKMCAAAA.Cornish:BAECLgAFFH8KAAIIAAUJ7CL/AQASAgAIAAUJ7CL/AQASAgAuAAQKfyEAAwgACQnhIycBAEwDAAgACQnhIycBAEwDAA0ABAlRGv8fAOcAAAAA.Cornishpaste:BAEALgAECgQJBAABLgAFFAUJCgAIAOwiAA==.Cosmo:BAAALgADCgcJCQABLgAECgYJEAAEAAAAAA==.',
Cr='Crackjaw:BAAALgAECgMJBQAAAA==.',
Cu='Curserodlock:BAAALgAECgYJBgAAAA==.',
Cy='Cyanide:BAAALgAECgYJBwAAAA==.',
Da='Dabbinshamin:BAAALgAECgcJBwAAAA==.Dadanbing:BAAALgAECgYJBgAAAA==.Daddyomg:BAAALgAECgYJCAABLgAFFAYJGwAOAFobAA==.Dads:BAACLgAFFH8bAAMOAAYJWhu1BACWAQAOAAUJMh21BACWAQAVAAQJNAgmGADMAAAuAAQKfxsAAw4ACQkWJSEQAKgCAA4ABwm6JCEQAKgCABUACQloF78iAA4CAAAA.Daggertest:BAAALgADCgQJBAABLgAECggJFgAMAOYaAA==.Dakeyras:BAABLgAECn8bAAMXAAgJDRTHEQAJAQAXAAgJDRTHEQAJAQADAAMJHwR6VAA4AAAAAA==.Darcevoker:BAACLgAFFH8LAAIYAAUJ9wdQDAAiAQAYAAUJ9wdQDAAiAQAuAAQKfyQAAhgACAmrGOYNAFkCABgACAmrGOYNAFkCAAAA.Darcmonk:BAAALgAFFAIJAwABLgAFFAUJCwAYAPcHAA==.Darcpaladin:BAAALgAECgQJBQABLgAFFAUJCwAYAPcHAA==.Darcshaman:BAAALgAECgIJAgABLgAFFAUJCwAYAPcHAA==.Darkrune:BAAALgAECgYJEwAAAA==.Darkschneide:BAAALgAECgQJBQAAAA==.Darthboo:BAAALgADCggJDAAAAA==.Darthtemplar:BAAALgAECgQJBAAAAA==.',
Db='Dbmagic:BAAALgAECgUJBwAAAA==.',
De='Dealsun:BAABLgAECn8bAAMPAAgJdBOcRAD+AQAPAAgJdBOcRAD+AQATAAUJ2QdLOADTAAAAAA==.Decynth:BAAALgAECgcJCQAAAA==.Defne:BAAALgAECgEJAQAAAA==.Demodorn:BAECLgAFFH8OAAIZAAUJ0ASHAgDXAAAZAAUJ0ASHAgDXAAAuAAQKfycAAhkACAmfFE8IAPgBABkACAmfFE8IAPgBAAAA.Demondudez:BAAALgAECgUJCwAAAA==.Demonikat:BAAALgADCgEJAQAAAA==.Demyst:BAACLgAFFH8JAAMOAAQJ5A78CwAvAQAOAAQJ5A78CwAvAQAVAAEJ3QZPJQBBAAAuAAQKfx8AAw4ACAngHygSAJICAA4ACAngHygSAJICABUAAgmkDRheADsAAAAA.Deria:BAAALgAECgEJAQAAAA==.Devilsparda:BAAALgAECgMJAwAAAA==.Deweey:BAAALgAECgUJCQAAAA==.Dezeraz:BAECLgAFFH8MAAIYAAQJbBwRBwB+AQAYAAQJbBwRBwB+AQAuAAQKfyMAAhgACAkDJv4BAFsDABgACAkDJv4BAFsDAAEuAAUUBQkKAAgA7CIA.',
Dh='Dhecaye:BAAALgADCgkJDwAAAA==.',
Di='Dieuscum:BAAALgAECgUJBQAAAA==.Diksneeze:BAAALgADCgUJCAAAAA==.Disengage:BAAALgAECgkJAwABLgAFFAUJDwADALkTAA==.Dislogic:BAABLgAECn8kAAMPAAkJZiLsAQAeAwAPAAgJZiLsAQAeAwATAAQJTSCiGwBwAQAAAA==.',
Dl='Dlorpglorp:BAAALgAECgIJAgABLgAECgcJHQAFAEMgAA==.',
Do='Dobbie:BAAALgADCgUJBQAAAA==.Donkey:BAAALgAECgYJCQAAAA==.Donmega:BAAALgADCgMJAwAAAA==.Doraleous:BAAALgAECgcJEAAAAA==.Dotzmybitzup:BAACLgAFFH8LAAMPAAQJ5Rt/IwASAQAPAAQJ5Rt/IwASAQATAAEJNA28DgBTAAAuAAQKfywABA8ABwmdIZMjAIYCAA8ABglUJZMjAIYCABIAAglqEy8dAIgAABMAAQlXDmhjAEgAAAAA.Dougalleone:BAACLgAFFH8KAAIaAAQJvR88BAB4AQAaAAQJvR88BAB4AQAuAAQKfyMAAxoACAmVIoMHABgDABoACAmVIoMHABgDABsAAQmtEfgdAD0AAAAA.',
Dr='Draci:BAAALgADCgEJAQAAAA==.Dreadknott:BAACLgAFFH8FAAIWAAIJyBXwUwCiAAAWAAIJyBXwUwCiAAAuAAQKfygAAhYACAngHiENAFwCABYACAngHiENAFwCAAAA.Dreadxknight:BAAALgADCgMJAwAAAA==.Drekim:BAABLgAECn8UAAIcAAUJryAWLgBRAQAcAAUJryAWLgBRAQAAAA==.Dreko:BAAALgADCgMJAwAAAA==.Drezzakmage:BAABLgAECn8cAAIFAAgJKxdiYAAaAgAFAAgJKxdiYAAaAgAAAA==.Drezzakzdh:BAAALgADCgYJBgABLgAECggJHAAFACsXAA==.Druidiac:BAAALgADCgYJEwABLgAECggJIgAUACwZAA==.',
Ed='Edgelf:BAAALgADCgMJAwAAAA==.',
El='Elaidare:BAAALgAECgEJAQABLgAECgcJDgAEAAAAAA==.Elaidine:BAAALgAECgcJDgAAAA==.Elisabetta:BAAALgADCgMJAwAAAA==.Elizalex:BAAALgAECgIJAgAAAA==.',
Em='Emagdne:BAAALgADCgMJAgAAAA==.Empath:BAAALgADCgQJBQAAAA==.',
En='Enferno:BAAALgAECgIJAwAAAA==.Enfernum:BAAALgADCgEJAQAAAA==.Enolad:BAAALgADCgcJBwAAAA==.',
Er='Eradius:BAAALgADCgIJAgAAAA==.Errai:BAABLgAECn8kAAIPAAkJAx/IAwDlAgAPAAkJAx/IAwDlAgAAAA==.',
Eu='Eureka:BAABLgAECn8UAAIBAAkJlBWRCAAIAgABAAkJlBWRCAAIAgAAAA==.',
Ev='Evilnapkin:BAAALgAECgQJEAAAAA==.Evion:BAABLgAECn8XAAIdAAgJxhuALwDzAQAdAAgJxhuALwDzAQAAAA==.',
Ey='Eyez:BAAALgADCgIJAgAAAA==.',
Fa='Faelthorn:BAAALgADCgQJBAAAAA==.Farseer:BAAALgADCgMJAwAAAA==.',
Fe='Feardoctor:BAAALgAECgQJCAAAAA==.Feelthepower:BAAALgAECgYJEAAAAA==.',
Fl='Flavorfrenzy:BAAALgADCgUJBQAAAA==.',
Fo='Fourimborniy:BAAALgAECgcJCwAAAA==.',
Fr='Frenzi:BAAALgADCgEJAQAAAA==.Friendulum:BAAALgAECgcJBwAAAA==.',
Fu='Fuzzsicle:BAAALgAECgYJCQAAAA==.Fuzzydìcê:BAAALgAECgUJCAAAAA==.',
['Fá']='Fáelen:BAABLgAECn8fAAIeAAgJMx6pBgCLAgAeAAgJMx6pBgCLAgAAAA==.',
Ga='Galang:BAAALgAECgMJBAAAAA==.Gangactivity:BAAALgAECgQJBgABLgAECgkJJgANAH4hAA==.Garm:BAAALgAECgEJAQAAAA==.Garrt:BAAALgAECgQJBAAAAA==.Gartalvanise:BAAALgAECgQJBgAAAA==.Gavinrad:BAAALgAECgUJBgAAAA==.',
Ge='Gep:BAAALgAECgcJDgAAAA==.',
Gl='Glaalinix:BAAALgADCgkJFQAAAA==.Glaciiel:BAAALgAECgMJAwAAAA==.Globbie:BAAALgADCgMJAwAAAA==.',
Go='Goku:BAAALgAECgQJBQAAAA==.Goobman:BAAALgADCgQJBQABLgAECggJJQAQAP4hAA==.Goodman:BAABLgAECn8iAAIJAAgJ3x2ZCwBtAgAJAAgJ3x2ZCwBtAgAAAA==.Goomei:BAACLgAFFH8GAAINAAMJfRQ1CgD5AAANAAMJfRQ1CgD5AAAuAAQKfygAAg0ACAlQIbwEAFsCAA0ACAlQIbwEAFsCAAEuAAUUBgkPAB8A7BgA.Goomi:BAACLgAFFH8PAAIfAAYJ7BigBQCWAQAfAAYJ7BigBQCWAQAuAAQKfyEAAh8ACQk+IxEDAJ4DAB8ACQk+IxEDAJ4DAAAA.Gordius:BAAALgADCgEJAQAAAA==.Gorok:BAAALgAECgMJBgAAAA==.Goybeam:BAAALgADCgcJCQAAAA==.',
Gr='Gravykin:BAAALgAECggJDwAAAA==.Grayfoxrun:BAAALgADCgUJBQAAAA==.Greatbooty:BAABLgAECn8WAAIFAAcJVREvSgBQAQAFAAcJVREvSgBQAQAAAA==.Grecko:BAAALgADCgUJBQAAAA==.Gremmi:BAAALgAECgEJAwAAAA==.Greygavel:BAAALgAECgYJCwAAAA==.Grosgland:BAAALgADCgEJAQAAAA==.Groundbeéf:BAACLgAFFH8TAAIRAAUJOCGHAAA9AQARAAUJOCGHAAA9AQAuAAQKfyUAAhEACAkJJvsAAH4DABEACAkJJvsAAH4DAAAA.Groundzero:BAAALgADCgUJBQAAAA==.Groztrazztok:BAAALgAECgYJEwAAAA==.Grungulus:BAAALgAECgcJDAAAAA==.',
Gu='Guineapig:BAEBLgAECn8UAAIJAAcJLyTeMABfAgAJAAcJLyTeMABfAgAAAA==.Gundral:BAAALgADCgEJAQAAAA==.Gunnysack:BAAALgADCgcJDQAAAA==.Guzmo:BAAALgAECgEJAQABLgAECgUJBgAEAAAAAA==.',
Gy='Gyx:BAAALgAECgQJCAAAAA==.',
Ha='Haiku:BAAALgAECgEJAQAAAA==.Handanir:BAABLgAECn8fAAIQAAgJBSKHAwD/AgAQAAgJBSKHAwD/AgAAAA==.Harie:BAAALgAECgYJEwAAAA==.Hasbula:BAAALgAECgQJBAAAAA==.Hatebound:BAAALgAECgIJAgAAAA==.',
He='Heihei:BAAALgADCgYJDAAAAA==.Heiny:BAAALgAFFAMJAwAAAA==.Heinyheinyho:BAABLgAECn8pAAIHAAgJPiRyAgD0AgAHAAgJPiRyAgD0AgABLgAFFAMJAwAEAAAAAA==.',
Hi='Hielle:BAAALgADCgkJCQAAAA==.Highguard:BAAALgADCgcJBwAAAA==.Himothy:BAAALgAECgEJAwAAAA==.',
Ho='Hoid:BAAALgAECgEJAQAAAA==.Holy:BAAALgADCgYJBgAAAA==.Holysword:BAEALgADCgYJBgABLgAECgQJBQAEAAAAAA==.Hoofmetoo:BAABLgAECn8aAAIWAAYJ7ReDLgCAAQAWAAYJ7ReDLgCAAQAAAA==.Howboudah:BAAALgADCggJCAAAAA==.',
Hu='Hulkgirl:BAAALgADCgEJAQAAAA==.Hulzar:BAAALgAECgYJEQAAAA==.',
['Hô']='Hôlyblight:BAAALgADCgEJAQABLgAFFAIJBQAOABwNAA==.',
Ic='Iceflare:BAABLgAECn8ZAAMFAAgJihbhVAA6AgAFAAgJihbhVAA6AgAGAAQJ7gLnEwCHAAAAAA==.',
Id='Idotyouto:BAABLgAECn8kAAIFAAgJmxvoKQC9AQAFAAgJmxvoKQC9AQAAAA==.',
Ig='Igris:BAAALgAECgIJAgAAAA==.',
Ih='Ihavewater:BAAALgADCgkJCQAAAA==.',
Il='Ilbryen:BAAALgAECgUJBQABLgAFFAQJCgADAEMVAA==.Illidori:BAAALgAECgYJEwAAAA==.Illidrag:BAAALgAECgkJEgAAAA==.Ilovemoo:BAAALgAECgMJAwAAAA==.',
Im='Imblind:BAAALgADCgEJAQABLgAFFAQJBgANADoLAA==.Imladris:BAAALgAECgYJDgAAAA==.Immòrtlzed:BAACLgAFFH8QAAIYAAUJ0R4bBAC1AQAYAAUJ0R4bBAC1AQAuAAQKfyAAAhgACAliIHMJAJ8CABgACAliIHMJAJ8CAAAA.',
In='Invective:BAAALgADCgkJIAAAAA==.',
Is='Isharn:BAAALgADCgMJAwAAAA==.',
Iz='Izzyumi:BAABLgAECn8XAAIdAAcJUgzxMwBBAQAdAAcJUgzxMwBBAQAAAA==.',
Ja='Jabo:BAAALgADCgMJAwABLgAECgUJDAAEAAAAAA==.Jadelin:BAAALgAECgIJAgAAAA==.Jaxek:BAABLgAECn8lAAIeAAkJgiGVAAD2AgAeAAkJgiGVAAD2AgAAAA==.Jaxs:BAACLgAFFH8LAAIVAAUJqhqkAwC4AQAVAAUJqhqkAwC4AQAuAAQKfyAAAhUACAlAG5wVAGgCABUACAlAG5wVAGgCAAAA.Jaylen:BAAALgAECgQJBwAAAA==.Jaymo:BAAALgAECgUJBQAAAA==.',
Je='Jebke:BAAALgAECgEJAQABLgAECgYJBwAEAAAAAA==.Jeffurry:BAAALgADCgIJAgAAAA==.Jeminia:BAAALgAECgUJCAAAAA==.Jenifur:BAABLgAECn8VAAIQAAYJqgtNOQDvAAAQAAYJqgtNOQDvAAAAAA==.Jennae:BAAALgADCgEJAQAAAA==.',
Jh='Jhope:BAABLgAFFH8IAAIMAAMJkQ0eGQDSAAAMAAMJkQ0eGQDSAAAAAA==.',
Ji='Jinkusu:BAAALgADCgMJAwABLgADCgQJBAAEAAAAAA==.',
Jm='Jml:BAACLgAFFH8NAAIfAAUJzyJOCgBkAQAfAAUJzyJOCgBkAQAuAAQKfxsAAh8ACQnRIQMFAHYDAB8ACQnRIQMFAHYDAAAA.',
Jo='Jopha:BAACLgAFFH8SAAIDAAUJHyBCBAB1AQADAAUJHyBCBAB1AQAuAAQKfyUAAwMACAlKJQUGAEcDAAMACAkpJQUGAEcDAAIABwkQH/MEAJQCAAAA.Jophr:BAAALgAECgEJAQABLgAFFAUJEgADAB8gAA==.',
Jp='Jpbruiser:BAABLgAECn8nAAIJAAgJXyLKBQC9AgAJAAgJXyLKBQC9AgAAAA==.',
Ju='Judged:BAAALgAECgUJDQAAAA==.Juggalette:BAAALgADCgIJAgAAAA==.Jumpndeath:BAACLgAFFH8JAAIgAAQJ/hfjBgAsAQAgAAQJ/hfjBgAsAQAuAAQKfx4AAyAACAmoHzkUAMwBACAABQmFIDkUAMwBABYABglYHI1+AIYBAAAA.Jumpnpunch:BAABLgAECn8gAAQMAAgJ/BoCGgA0AgAMAAcJQBwCGgA0AgANAAgJew55DwCDAQAIAAYJEA4HOAALAQABLgAFFAQJCQAgAP4XAA==.Justgetme:BAABLgAECn8oAAMKAAgJkySXAADqAgAKAAgJkySXAADqAgAJAAIJAA6iGwFjAAAAAA==.',
Jw='Jwad:BAAALgAECgYJEgAAAA==.',
Ka='Kaan:BAAALgAECgEJAQAAAA==.Kaariel:BAAALgADCgcJCgAAAA==.Kabo:BAAALgADCgUJBwABLgAFFAQJBwAWAM4bAA==.Kagger:BAACLgAFFH8FAAIJAAIJSxJpLwCnAAAJAAIJSxJpLwCnAAAuAAQKfzIAAgkACQmfIu0EAH0DAAkACQmfIu0EAH0DAAAA.Kaiser:BAAALgADCgcJDAAAAA==.Kaitu:BAAALgAECgYJCwAAAA==.Kake:BAAALgAECgQJBAABLgAECgYJBgAEAAAAAA==.Kalloh:BAABLgAECn8YAAIPAAYJGxPbQgApAQAPAAYJGxPbQgApAQAAAA==.Kalorth:BAAALgADCgcJBwAAAA==.Kardoroth:BAACLgAFFH8HAAIWAAIJhiZHLQDmAAAWAAIJhiZHLQDmAAAuAAQKfzEAAhYACAmOJpkCABQDABYACAmOJpkCABQDAAAA.Karibo:BAAALgADCgcJDAAAAA==.Karîba:BAACLgAFFH8QAAQWAAUJUhxvFwBHAQAWAAQJHBpvFwBHAQAgAAMJPxO5DgB+AAAhAAEJaAsRBwBPAAAuAAQKfyMAAxYACAn8Hk0fAMUCABYACAn8Hk0fAMUCACAAAQkrCTBNABwAAAAA.Kassi:BAAALgADCgEJAQAAAA==.Kayfree:BAAALgAECgUJCQAAAA==.Kaõtik:BAAALgAECgkJCgAAAA==.',
Ke='Keerrilee:BAABLgAECn8WAAINAAgJ9hwgFABNAQANAAgJ9hwgFABNAQAAAA==.Kefka:BAAALgAECgQJBQAAAA==.Keirine:BAAALgAECgEJAwAAAA==.Kelfrost:BAAALgAECgIJAgAAAA==.Kelknight:BAAALgAECgQJEAAAAA==.Kelsaz:BAACLgAFFH8QAAMLAAUJLxgvBABgAQALAAUJ8BUvBABgAQAdAAMJchV7CwAGAQAuAAQKfx8ABB0ACAkqIzUSAKYCAB0ABwlIIzUSAKYCACIABglBGMdGADgBAAsABAnvFksbANYAAAAA.Kelsi:BAAALgAECgYJEAAAAA==.Kenný:BAAALgADCgMJBAAAAA==.Kerrìgàn:BAACLgAFFH8PAAIZAAUJqxGSAQAZAQAZAAUJqxGSAQAZAQAuAAQKfyUAAhkACAlkIGkCANYCABkACAlkIGkCANYCAAAA.Kestral:BAACLgAFFH8FAAMYAAMJ0wgWEAC9AAAYAAMJ0wgWEAC9AAAcAAIJLwGdJgBqAAAuAAQKfyMAAhgACAkMFCAUAAMCABgACAkMFCAUAAMCAAAA.Keynis:BAAALgADCgEJAQAAAA==.',
Kh='Khalisi:BAAALgADCgcJDAAAAA==.Khejan:BAAALgADCgMJAwAAAA==.Khrask:BAAALgADCgIJAgABLgAFFAQJCgADAEMVAA==.',
Ki='Kiell:BAAALgAECgYJBwAAAA==.Kinuyo:BAAALgAECgQJBAAAAA==.Kiwipie:BAAALgAECgQJBAAAAA==.',
Kn='Knottyjack:BAAALgADCgMJAwAAAA==.',
Ko='Kookiie:BAACLgAFFH8TAAMjAAUJnCIqAQCUAQAjAAUJnCIqAQCUAQAfAAIJWQ1vKwCYAAAuAAQKfyUAAyMACAkTIcAJAMYCACMABwnbJcAJAMYCAB8ACAkuHL4kAHYCAAAA.Kookiiez:BAAALgAECgQJBAAAAA==.Koom:BAAALgADCgYJBQAAAA==.Kosian:BAAALgAECgYJEQABLgAECgcJBwAEAAAAAA==.Kosigan:BAAALgAECgIJAgABLgAECgkJMQAcADElAA==.',
Kp='Kpop:BAAALgADCgEJAQAAAA==.',
Kr='Krepuscular:BAAALgAECgEJAQAAAA==.Kromdor:BAABLgAECn8YAAITAAgJSxoLBgBxAgATAAgJSxoLBgBxAgAAAA==.Krosis:BAAALgAECggJEQAAAA==.',
Kt='Kthríss:BAAALgADCgMJAwAAAA==.',
Ku='Kungscott:BAAALgAECgEJAwABLgAFFAMJCQAOAG4MAA==.Kuromi:BAAALgAECgQJBAAAAA==.',
Ky='Kynei:BAABLgAECn8WAAIfAAgJsR6bCABQAgAfAAgJsR6bCABQAgAAAA==.',
La='Lacasis:BAAALgADCgUJBQABLgAECgYJCwAEAAAAAA==.Larra:BAACLgAFFH8KAAMkAAQJ0Q76CADYAAAlAAQJFQz3DQAuAQAkAAMJmgv6CADYAAAuAAQKfx8ABCQACAlrHS0PAG8CACQACAlrHS0PAG8CABQABgnvGy8tAHUBACUABAlMEcEcAPgAAAAA.',
Le='Leman:BAAALgADCgkJFAAAAA==.Lemoncrisp:BAAALgAECgEJAQAAAA==.Leprocylarry:BAAALgADCgcJBwAAAA==.Letos:BAAALgAECgcJEgAAAA==.Levitas:BAABLgAECn8eAAIXAAgJ2BJZCACxAQAXAAgJ2BJZCACxAQAAAA==.Lewieballz:BAAALgADCgMJAwABLgAECggJHgAEAAAAAA==.',
Li='Liljit:BAAALgAECgcJDgAAAA==.Lithel:BAAALgAECgEJAQAAAA==.',
Lo='Loaded:BAAALgAECgEJAQAAAA==.Lockxeno:BAAALgAECgUJCwAAAA==.Logics:BAABLgAECn8pAAIUAAkJ+SDiAAAVAwAUAAkJ+SDiAAAVAwAAAA==.Lon:BAABLgAECn8YAAINAAgJxRJiLAB9AQANAAgJxRJiLAB9AQAAAA==.Lostea:BAAALgADCgUJBQABLgAECggJGQAcAJEXAA==.Lostmylimbs:BAABLgAECn8jAAIgAAgJhRe3EwDTAQAgAAgJhRe3EwDTAQABLgAFFAUJDwAZAKsRAA==.Lostmyvigor:BAAALgAECgMJBgAAAA==.Lostvoker:BAABLgAECn8ZAAMcAAgJkRe4FQAtAgAcAAgJkRe4FQAtAgAmAAUJehDrIgATAQAAAA==.Loueballz:BAAALgAECggJHgAAAQ==.Lowvice:BAAALgADCgEJAQAAAA==.',
Lu='Lucarad:BAABLgAECn8jAAINAAgJGBPDGwD+AQANAAgJGBPDGwD+AQAAAA==.Lucerfer:BAAALgADCgUJBwAAAA==.Lucivia:BAABLgAECn8hAAISAAgJdRibBAAwAgASAAgJdRibBAAwAgAAAA==.Lumafist:BAABLgAECn8mAAINAAkJfiHrAQDUAgANAAkJfiHrAQDUAgAAAA==.',
['Lè']='Lènneth:BAABLgAECn8hAAIkAAgJpB33BAB7AgAkAAgJpB33BAB7AgAAAA==.',
['Lí']='Líghtning:BAAALgAECggJDgAAAA==.',
['Lø']='Løstdruid:BAAALgADCgEJAQABLgAECgUJCQAEAAAAAA==.Løstpala:BAAALgAECgUJCQAAAA==.',
Ma='Mahiru:BAAALgADCgMJAwAAAA==.Makkaflocka:BAAALgAECgQJBAABLgAECgcJGAAfACggAA==.Malleus:BAAALgADCgUJBQAAAA==.Malytheris:BAABLgAECn8VAAMKAAcJoQ3tDQAhAQAKAAcJoQ3tDQAhAQAJAAEJzwX42wAsAAAAAA==.Marqis:BAAALgAECgEJAQAAAA==.Mattshanu:BAACLgAFFH8JAAIOAAQJgBVnCQBCAQAOAAQJgBVnCQBCAQAuAAQKfxwAAg4ACAmmHboUAHgCAA4ACAmmHboUAHgCAAAA.Mayalaran:BAAALgADCgcJDwAAAA==.Mazgruug:BAAALgAECgcJCgAAAA==.Mazkova:BAAALgAECgYJBgAAAA==.Mazur:BAABLgAECn8hAAIJAAgJcCFnBwCjAgAJAAgJcCFnBwCjAgAAAA==.',
Mc='Mcmonkton:BAAALgAECgcJDAAAAA==.',
Me='Meirah:BAAALgADCgYJBAAAAA==.Mekkaweepz:BAAALgADCgUJBQAAAA==.Melaan:BAAALgAECgUJEgAAAA==.Melinadra:BAAALgAECgEJAQAAAA==.Meowmixx:BAAALgADCgYJBgAAAA==.Meowssa:BAEBLgAECn8lAAInAAgJWSWGAADTAgAnAAgJWSWGAADTAgAAAA==.',
Mi='Midori:BAAALgAECgEJAQAAAA==.Mindleseye:BAAALgADCgQJBgAAAA==.Mindlesscon:BAABLgAECn8WAAMRAAYJ0x7YDAD1AQARAAYJph3YDAD1AQAOAAUJWx6MPABaAQAAAA==.Minislayer:BAAALgAECgcJEQAAAA==.Minyprayers:BAACLgAFFH8PAAIUAAUJORhyBgBgAQAUAAUJORhyBgBgAQAuAAQKfx4AAhQACQm5IEUKAN4CABQACQm5IEUKAN4CAAAA.Minywon:BAAALgADCgcJCgABLgAFFAUJDwAUADkYAA==.Misosalty:BAABLgAECn8lAAMNAAgJ9x8pBQBMAgANAAgJ9x8pBQBMAgAMAAUJ2BdiIgDxAAAAAA==.Misowet:BAAALgADCgYJCQABLgAECggJJQANAPcfAA==.',
Ml='Mlorpglorp:BAABLgAECn8dAAIFAAcJQyB8PQCCAgAFAAcJQyB8PQCCAgAAAA==.',
Mo='Mobaye:BAAALgAECgEJAQAAAA==.Mohjito:BAABLgAECn8lAAMNAAgJ3hsZBwAXAgANAAgJ3hsZBwAXAgAMAAUJABFJJADkAAAAAA==.Mojojojoz:BAAALgADCgUJBQAAAA==.Monkisbad:BAABLgAECn8kAAIMAAgJmyP3BgApAgAMAAgJmyP3BgApAgAAAA==.Monkma:BAAALgAECgIJAgAAAA==.Moonfire:BAAALgADCgcJDgAAAA==.Moose:BAAALgADCgYJBgAAAA==.Mooshanu:BAAALgADCgcJDAABLgAFFAQJCQAOAIAVAA==.Morguth:BAACLgAFFH8IAAMdAAMJBw5fFACyAAAdAAIJ4hRfFACyAAAiAAIJUQCVIwBdAAAuAAQKfxsABB0ACAkEHigUAJUCAB0ACAkEHigUAJUCACIABAkeBLFoAJsAAAsAAglcD7suAD4AAAAA.Moriaug:BAAALgAECgUJBQAAAA==.Moriko:BAAALgAECgYJEgAAAA==.',
Mu='Muggy:BAAALgAECgEJAQAAAA==.Murky:BAABLgAECn8YAAIaAAcJsxZxDwB3AQAaAAcJsxZxDwB3AQAAAA==.Musicmichael:BAAALgAECgYJBwAAAA==.',
['Mî']='Mîyagî:BAAALgAECgcJCQAAAA==.',
['Mö']='Mööbs:BAABLgAECn8aAAMYAAgJJgeYJwA3AQAYAAgJJgeYJwA3AQAcAAQJngYUSwCnAAAAAA==.',
Na='Namad:BAAALgAECgYJDwAAAA==.Nancybrew:BAABLgAECn8hAAMNAAgJXB8YBQBOAgANAAgJXB8YBQBOAgAIAAIJdRJxWABtAAAAAA==.Nathric:BAAALgADCgUJBQAAAA==.Navajo:BAAALgAECgcJEwAAAA==.',
Ne='Neature:BAAALgADCgMJAwAAAA==.Neoma:BAAALgAECgQJDAAAAA==.Nesqwik:BAAALgAECgEJAgAAAA==.Nevan:BAABLgAECn8dAAMHAAgJuSO8CABMAgAHAAgJuSO8CABMAgAJAAEJOROZuwBCAAAAAA==.Neverender:BAAALgAECgEJAgABLgAECgYJDgAEAAAAAA==.Newlock:BAAALgAECgQJBAAAAA==.Nexi:BAAALgAECgMJAwAAAA==.',
Ni='Niang:BAAALgADCgQJBAAAAA==.Nidalee:BAAALgAECgUJBQAAAA==.Nippyvixen:BAAALgADCgcJBwAAAA==.Nishu:BAAALgADCgMJAwAAAA==.',
No='Noochallange:BAABLgAECn8eAAIbAAgJVx5eAQBQAgAbAAgJVx5eAQBQAgAAAA==.Norex:BAABLgAECn8fAAMWAAgJ/BHWWgDhAQAWAAgJeRHWWgDhAQAgAAYJnwi2LADZAAAAAA==.Norm:BAAALgAECgMJBAAAAA==.Notekk:BAAALgAECgQJBwAAAA==.',
Nu='Nuggie:BAABLgAECn8bAAMPAAgJZRpmFAACAgAPAAcJZRpmFAACAgATAAEJAAC/YgBJAAAAAA==.Nurf:BAAALgADCgMJAwAAAA==.Nurgal:BAAALgAECgYJCAAAAA==.Nutlips:BAAALgADCgUJCwAAAA==.',
Ny='Nylariaa:BAAALgAECgQJCgAAAA==.Nymia:BAABLgAECn8gAAIQAAgJBR6bJAAoAgAQAAgJBR6bJAAoAgAAAA==.',
['Næ']='Næon:BAABLgAECn8bAAIIAAgJZxd1HQDKAQAIAAgJZxd1HQDKAQAAAA==.',
Ob='Oblake:BAABLgAECn8YAAIaAAcJkBQhIQDwAQAaAAcJkBQhIQDwAQAAAA==.',
Oc='Octosloth:BAAALgADCgEJAQAAAA==.',
Oh='Ohhashbrowns:BAAALgADCgcJBwAAAA==.',
Ok='Oku:BAAALgADCgcJBgAAAA==.',
Ol='Oldmagic:BAAALgAECgYJCwAAAA==.Olizza:BAAALgAECgIJAgABLgAECgYJDwAEAAAAAA==.',
Om='Omgimabeast:BAAALgAECgYJCAAAAA==.',
On='Onieva:BAAALgAECggJDQAAAA==.',
Oo='Ooglaboogla:BAABLgAECn8hAAMOAAgJihnrCQD8AQAOAAgJihnrCQD8AQAVAAIJhxyXggCJAAAAAA==.',
Or='Oriah:BAAALgADCgYJBgAAAA==.Orions:BAAALgADCgQJBAAAAA==.',
Os='Osserc:BAAALgADCgYJBgAAAA==.',
Ox='Oxyrotten:BAABLgAECn8YAAIWAAYJ/ws6UAAQAQAWAAYJ/ws6UAAQAQAAAA==.',
Pa='Pablo:BAABLgAECn81AAMLAAkJXCGfAAASAwALAAkJXCGfAAASAwAiAAEJZRG5hgA1AAAAAA==.Pancho:BAABLgAECn8ZAAINAAgJkhgXBwAXAgANAAgJkhgXBwAXAgAAAA==.Pandra:BAAALgADCgEJAQAAAA==.Panttyraider:BAAALgAFFAIJAgAAAA==.Panzeria:BAABLgAECn8dAAIUAAcJPSU7CQDwAgAUAAcJPSU7CQDwAgAAAA==.Papito:BAAALgAECgUJBwAAAA==.Pathryis:BAAALgAECgYJBgAAAA==.Pawsome:BAAALgADCgIJAgAAAA==.',
Pl='Plank:BAAALgAECgUJBwAAAA==.',
Pm='Pmon:BAAALgADCgEJAQAAAA==.',
Po='Pongo:BAAALgAECgUJCQAAAA==.Ponkofox:BAABLgAECn8ZAAIRAAgJaREJDgDcAQARAAgJaREJDgDcAQAAAA==.',
Pr='Prah:BAAALgAECgMJBAAAAA==.Prepared:BAAALgAECgIJAgAAAA==.Prise:BAAALgAECgEJAQAAAA==.Prisefather:BAAALgAECgYJCgAAAA==.Prizefighter:BAAALgAECgYJBwAAAA==.Proditus:BAAALgAECgMJAwAAAA==.',
Ps='Pseudoholy:BAAALgADCgEJAQAAAA==.',
Pu='Putridvigor:BAAALgAFFAIJAgAAAA==.Puzzlewalrus:BAAALgADCgQJBAAAAA==.',
Py='Pyreiella:BAAALgADCgUJBQAAAA==.Pyroamor:BAAALgAECgEJAQAAAA==.Pyropete:BAAALgAECgcJDwAAAA==.',
['Pä']='Pälii:BAABLgAECn8cAAMHAAgJbgUbHgBXAQAHAAgJbgUbHgBXAQAJAAQJhA4X4QDLAAAAAA==.',
Qc='Qcomberoo:BAAALgADCgMJAwAAAA==.',
Ra='Ragublaster:BAAALgAECgEJAQABLgAFFAQJCwAPAOUbAA==.Ralickan:BAAALgADCgcJBQAAAA==.Ramaan:BAAALgAECgkJEQAAAA==.Ramble:BAAALgAECgcJDQAAAA==.Ravette:BAABLgAECn8nAAMjAAgJaSPDAQC4AgAjAAgJaSPDAQC4AgAZAAMJlhNWHgCVAAAAAA==.Ravissante:BAABLgAECn8XAAIfAAcJ7QWsQQDhAAAfAAcJ7QWsQQDhAAAAAA==.Rawranator:BAAALgAECgUJDAAAAA==.',
Re='Reesecupthis:BAABLgAECn8bAAIKAAcJDiJfBQCiAgAKAAcJDiJfBQCiAgABLgAFFAUJEQAKALEbAA==.Remagix:BAAALgAECgEJAQAAAA==.Revek:BAAALgADCgEJAQAAAA==.Reveurus:BAAALgADCgcJBwABLgAECggJHQAHALkjAA==.Rezzaleya:BAAALgADCgQJBAAAAA==.',
Rh='Rhaena:BAAALgAECgYJDQABLgAECggJDQAEAAAAAA==.Rhonis:BAAALgAECgMJAwAAAA==.',
Ri='Riceroll:BAABLgAECn8bAAMPAAcJJCAkHQDFAQAPAAYJ4B4kHQDFAQATAAQJIB0yJAA4AQAAAA==.Ricochet:BAABLgAECn8dAAIHAAYJqxP0HgBQAQAHAAYJqxP0HgBQAQAAAA==.Riseordie:BAAALgADCgYJCAAAAA==.',
Ro='Ronnycoleman:BAAALgAECgMJAwAAAA==.Roofonfire:BAABLgAECn8VAAMRAAgJNgcYCwAvAQARAAgJcAYYCwAvAQAOAAMJvwYzdwBmAAAAAA==.Roreck:BAAALgAECgkJBAAAAA==.Rowyn:BAAALgADCgEJAQAAAA==.',
Ru='Runeka:BAABLgAECn8gAAIlAAgJVCVwBwDLAgAlAAgJVCVwBwDLAgAAAA==.Rusalkha:BAAALgADCgEJAQAAAA==.Ruteefear:BAAALgAECgUJDAAAAA==.',
Ry='Rybes:BAAALgAECgUJDAAAAA==.Rychesus:BAAALgADCgYJBgABLgAECgUJCQAEAAAAAA==.',
Sa='Safehaven:BAAALgADCggJEAAAAA==.Saintcloud:BAAALgADCgkJEAAAAA==.Sairuwki:BAAALgADCgkJGQAAAA==.Samwìse:BAACLgAFFH8LAAIkAAMJgRJoCwDWAAAkAAMJgRJoCwDWAAAuAAQKfyMAAyQACAnBG3cOAHYCACQACAnBG3cOAHYCABQAAwm0CLNXAF8AAAAA.Sareir:BAAALgADCgMJAwAAAA==.Sato:BAAALgAECgEJAQAAAA==.Savagex:BAAALgADCgYJBgAAAA==.Saveena:BAAALgAECgYJDgAAAA==.',
Sc='Scarlla:BAAALgAECggJEAAAAA==.Scorber:BAAALgAECgIJAgAAAA==.',
Se='Searingbear:BAAALgADCgQJBAABLgAECggJGgANAEYXAA==.Senggolbacok:BAAALgAFFAIJAgAAAA==.Senpaii:BAAALgAECgEJAQAAAA==.Senseitheta:BAAALgAECgEJAgABLgAECgUJCwAEAAAAAA==.Sepherios:BAAALgADCgYJBgAAAA==.Serengenuity:BAAALgAECgIJAgAAAA==.Serenidin:BAAALgAECgEJAQAAAA==.Serenio:BAAALgAECgEJAwAAAA==.Sereniswift:BAAALgAECgQJBQAAAA==.Serephita:BAABLgAECn8mAAIFAAkJpgepPQB1AQAFAAkJpgepPQB1AQAAAA==.',
Sg='Sgtsnipe:BAAALgAECgQJBQAAAA==.',
Sh='Shakys:BAAALgAECgYJEgAAAA==.Shalaylea:BAAALgAECgQJBgAAAA==.Shamwich:BAAALgAECgUJCQAAAA==.Shanondorf:BAAALgAFFAEJAQAAAA==.Shark:BAAALgAECgYJDQABLgAFFAQJDgAWAFMSAA==.Shaymist:BAAALgAECgMJAwAAAA==.Sheeplord:BAAALgADCgQJBgAAAA==.Sheepstealer:BAABLgAECn8jAAMcAAgJ1hLwDgCeAQAcAAgJ1hLwDgCeAQAmAAQJLgJDNAByAAAAAA==.Shiggyll:BAAALgADCgIJAgAAAA==.Shildo:BAABLgAECn8iAAMUAAgJLBmqBwAMAgAUAAgJLBmqBwAMAgAlAAEJQQupVAA4AAAAAA==.Shirokuma:BAAALgAECgMJAwAAAA==.Shiryunuri:BAAALgADCgUJCAAAAA==.Shizzo:BAAALgAECgYJCwAAAA==.Shockrock:BAAALgAECgQJBQAAAA==.Shybuzz:BAAALgAECgEJAQAAAA==.Shøstákovich:BAAALgADCgEJAQAAAA==.',
Si='Sifen:BAAALgAECgQJCAABLgAFFAMJCQAOAG4MAA==.Silecra:BAAALgADCgcJBwABLgAECggJIAAlAFQlAA==.Sinscale:BAAALgAECgQJBAABLgAFFAUJEwAJAAwfAA==.Sinswrath:BAACLgAFFH8TAAIJAAUJDB/0CABtAQAJAAUJDB/0CABtAQAuAAQKfyUAAgkACAkWJIMJAEUDAAkACAkWJIMJAEUDAAAA.',
Sk='Skarre:BAABLgAECn8hAAIfAAcJ2xwwMAA6AgAfAAcJ2xwwMAA6AgAAAA==.Skcusnor:BAAALgAECgcJEQAAAA==.Skelevyrn:BAAALgADCgEJAQAAAA==.Skimnms:BAAALgADCgUJBgAAAA==.Skrimbly:BAAALgAECgEJAQAAAA==.',
Sl='Slaye:BAAALgAECggJEgAAAA==.',
Sm='Smiteheal:BAAALgADCgMJAwAAAA==.Smores:BAACLgAFFH8KAAIQAAQJUSM7CQBsAQAQAAQJUSM7CQBsAQAuAAQKfx4AAhAACAmJJagEAEQDABAACAmJJagEAEQDAAEuAAUUBgkYABAADyIA.Smrts:BAAALgAECggJCwAAAA==.',
Sn='Snaccident:BAACLgAFFH8GAAMcAAMJIAhWIgCVAAAcAAMJIAhWIgCVAAAmAAEJNwOqBgBGAAAuAAQKfycAAxwACQm0EfwgALgBABwACQm0EfwgALgBACYAAQnBAG1GABkAAAAA.Snaccidentsh:BAAALgADCgMJAgABLgAFFAMJBgAcACAIAA==.Snaccidentww:BAAALgAECgYJDAABLgAFFAMJBgAcACAIAA==.Sneakyteeth:BAABLgAECn8aAAIaAAgJOg2ADQCTAQAaAAgJOg2ADQCTAQAAAA==.Snotzz:BAAALgAECgUJBgAAAA==.',
So='Sojukai:BAAALgAECgEJAQAAAA==.Sok:BAAALgAECgUJDgAAAA==.Solonör:BAAALgADCgcJCAAAAA==.Songi:BAABLgAECn8fAAIWAAgJECJ4KACZAgAWAAgJECJ4KACZAgAAAA==.Soulwhisper:BAACLgAFFH8TAAIWAAUJohqyFQBaAQAWAAUJohqyFQBaAQAuAAQKfyUAAhYACAlWI1EVAPwCABYACAlWI1EVAPwCAAAA.',
Sp='Spaghetifire:BAABLgAFFH8GAAIcAAQJFQxnEgAbAQAcAAQJFQxnEgAbAQABLgAFFAQJCwAPAOUbAA==.Sphyr:BAAALgAECggJCQAAAA==.Spicynoodi:BAABLgAECn8cAAMmAAgJgAfVHQA/AQAmAAcJfAfVHQA/AQAcAAMJ0QURNgB/AAAAAA==.Spyrodruid:BAAALgAFFAEJAQABLgAFFAMJBgAWAOkKAA==.Spyromonk:BAAALgAECgIJAgABLgAFFAMJBgAWAOkKAA==.',
Sq='Sqoots:BAABLgAECn8hAAIFAAgJDiJ2DQB1AgAFAAgJDiJ2DQB1AgAAAA==.',
St='Stankyfist:BAAALgAECgUJCAAAAA==.Starfeish:BAAALgAECgcJDwAAAA==.Stepzlol:BAAALgADCgIJAwAAAA==.Stopresistin:BAAALgAECgUJCQAAAA==.Stormsinger:BAABLgAECn8hAAMOAAgJiBX7EgCEAQAOAAcJOBf7EgCEAQAVAAgJDBGDTgBJAQAAAA==.',
Su='Succubis:BAAALgADCgIJAgAAAA==.Sugarblast:BAACLgAFFH8NAAMOAAUJIRxZCABLAQAOAAQJIRxZCABLAQARAAEJAABzBwAAAAAuAAQKfyEAAg4ACAnrIwcLAOcCAA4ACAnrIwcLAOcCAAAA.Sukker:BAAALgAECgMJAwAAAA==.Sukkler:BAAALgADCgYJCAAAAA==.Sumtingwong:BAAALgADCgYJBgAAAA==.Suou:BAACLgAFFH8KAAMDAAQJQxWvDwAMAQADAAQJ0xOvDwAMAQACAAEJegmUCwBUAAAuAAQKfx8AAwMACAkeINMhAEYCAAMABwndH9MhAEYCAAIAAQmiIS4jAGIAAAAA.Supadoc:BAAALgAECggJCgAAAA==.Superchicken:BAAALgAECgIJAgAAAA==.Surfbird:BAAALgAECgYJBgAAAA==.',
Sv='Svekkê:BAAALgAECgcJBwAAAA==.',
Sw='Swagmeoutbro:BAAALgADCgIJAgAAAA==.',
Sy='Sylint:BAAALgAECgYJCQAAAA==.Sylliseas:BAAALgADCgYJBgAAAA==.Sylvara:BAAALgAECgUJBwAAAA==.Sylverlock:BAAALgAECgIJAgAAAA==.',
Ta='Tacosdk:BAAALgAECgUJCAAAAA==.Tacoss:BAAALgAECgIJAgAAAA==.Tandragosa:BAAALgAECgMJBAABLgAECggJIQAOAIgVAA==.Tankadiin:BAAALgAECgQJBAAAAA==.Tannica:BAAALgADCgYJBgAAAA==.Tanthyr:BAAALgADCggJCwAAAA==.Tayswiftagos:BAAALgAECgcJDwAAAA==.',
Te='Teddy:BAAALgADCgMJAwAAAA==.Teddyy:BAAALgAECgYJBgAAAA==.Texazmade:BAAALgAECgUJBgAAAA==.',
Th='Thagomizer:BAAALgADCgIJAgAAAA==.Thedevilssin:BAAALgAECgYJCgAAAA==.Thefool:BAAALgADCgYJBgAAAA==.Theocles:BAAALgADCgYJDgAAAA==.Theodas:BAAALgAFFAEJAQAAAA==.Therru:BAAALgADCggJGAABLgAECgYJEgAEAAAAAA==.Thien:BAAALgADCgkJCQAAAA==.Thorimm:BAAALgAECgEJAQAAAA==.Throbbert:BAAALgADCgcJBwABLgAFFAEJAQAEAAAAAA==.Thunderwater:BAAALgAECgQJBQAAAA==.',
Ti='Tiktok:BAAALgAECgUJEQABLgAECgcJDwAEAAAAAA==.Tippss:BAACLgAFFH8FAAIkAAIJMSNbCQDRAAAkAAIJMSNbCQDRAAAuAAQKfzIAAyQACQmxJfgBAFQDACQACQmxJfgBAFQDACUACAmpFjUGAEoCAAAA.Tipsygypsy:BAABLgAECn8YAAIFAAcJ4QatVwAvAQAFAAcJ4QatVwAvAQAAAA==.',
To='Tokenbeef:BAABLgAECn8fAAMVAAcJJhnCEQDjAQAVAAcJJhnCEQDjAQAOAAMJRAQUdgBqAAAAAA==.Tokenshaman:BAABLgAECn8VAAIRAAYJfAziDAAKAQARAAYJfAziDAAKAQAAAA==.Torlon:BAAALgADCgEJAQAAAA==.Toxicshamy:BAACLgAFFH8FAAMOAAIJPQm5GQCIAAAOAAIJKQS5GQCIAAARAAIJ8ghABgBSAAAuAAQKfyAABBEACQk5F0ACAFMCABEACAmdGUACAFMCAA4ABwnQEyUpAMsBABUAAQmtGEBZAEgAAAAA.',
Tr='Trafficcones:BAAALgAECgMJAwAAAA==.Traugdor:BAAALgADCgkJDgAAAA==.Traylay:BAACLgAFFH8JAAIJAAQJsxSUEwAKAQAJAAQJsxSUEwAKAQAuAAQKfx8AAgkACAnbJJ8MACkDAAkACAnbJJ8MACkDAAAA.Traylei:BAAALgADCgcJBwABLgAFFAQJCQAJALMUAA==.Trio:BAAALgADCgUJBQAAAA==.Trixaintime:BAABLgAECn8WAAIJAAYJUQlwqwArAQAJAAYJUQlwqwArAQAAAA==.',
Ts='Tsm:BAAALgADCgYJBgAAAA==.',
Tt='Ttocs:BAACLgAFFH8JAAIOAAMJbgzPEADpAAAOAAMJbgzPEADpAAAuAAQKfyoAAg4ACQnUIvcBAN0CAA4ACQnUIvcBAN0CAAAA.',
Tu='Tujori:BAACLgAFFH8IAAIlAAQJCBDtDgDgAAAlAAQJCBDtDgDgAAAuAAQKfx4AAyQACAmfEpQuAIkBACQACAlJC5QuAIkBACUABwm/ErMlAGcBAAAA.Turuce:BAAALgADCgYJBgAAAA==.',
Tv='Tv:BAAALgADCgcJBwABLgAECgMJAwAEAAAAAA==.',
Tw='Twherk:BAAALgAECgcJDgABLgAFFAUJDAAlAD0QAA==.Twinmoonfury:BAABLgAECn8rAAMBAAgJxxfyCAABAgABAAgJxxfyCAABAgAQAAYJPBO5WgBCAQAAAA==.Twobit:BAAALgAECgYJBgAAAA==.',
Ty='Tylann:BAAALgADCgIJAgAAAA==.Tynestra:BAAALgAECgkJDwAAAA==.',
['Tí']='Tíger:BAAALgADCgQJAwAAAA==.',
['Tü']='Tüyria:BAAALgADCgMJAwAAAA==.',
Ug='Uglydorf:BAABLgAECn8cAAIdAAgJsBxKNQDZAQAdAAgJsBxKNQDZAQAAAA==.',
Ul='Ulraka:BAAALgADCgEJAQAAAA==.Ultraviolenc:BAAALgAECgEJAQAAAA==.',
Un='Unholydiver:BAAALgADCgEJAQAAAA==.',
Va='Vaeros:BAAALgAECgYJEgAAAA==.Valantis:BAEALgAECgQJBQAAAA==.Valcantor:BAAALgADCgYJBgAAAA==.Vanyss:BAAALgADCgYJBgAAAA==.',
Ve='Vekz:BAABLgAECn8kAAIHAAkJTx7eBQCIAgAHAAkJTx7eBQCIAgAAAA==.Velazq:BAAALgADCgEJAgAAAA==.Velicia:BAABLgAECn8ZAAICAAgJHBXQBADpAQACAAgJHBXQBADpAQAAAA==.Velithice:BAAALgAECgYJBwAAAA==.Venture:BAAALgAECgEJAQAAAA==.',
Vo='Voidnjoyr:BAAALgAECgEJAQAAAA==.',
Wa='Walsun:BAAALgADCgcJDQABLgAECggJIQAOAIgVAA==.Warhéad:BAAALgAECgUJDAAAAA==.Wartonxp:BAABLgAECn8sAAIUAAgJfR7RBQA2AgAUAAgJfR7RBQA2AgAAAA==.Waterbôy:BAACLgAFFH8FAAIOAAIJHA2wFwCYAAAOAAIJHA2wFwCYAAAuAAQKfzIABA4ACQmyIAQCANoCAA4ACQmyIAQCANoCABUABQliCZZnAPAAABEAAgktBQMoAFwAAAAA.Waynee:BAAALgAECgMJBAAAAA==.',
We='Weepylight:BAAALgAECgMJAwAAAA==.Weissbrew:BAAALgADCgUJBQAAAA==.',
Wh='Wheezy:BAAALgAFFAIJAgAAAA==.Whoasked:BAABLgAECn8xAAMcAAkJMSViAABpAwAcAAkJMSViAABpAwAmAAYJSRcpHABPAQAAAA==.',
Wi='Wiggle:BAABLgAECn8hAAIGAAkJqhwOAgCLAgAGAAkJqhwOAgCLAgAAAA==.Wildslayer:BAAALgADCgUJBQAAAA==.',
Wo='Wolf:BAAALgAECgEJAQAAAA==.',
Wt='Wtfheal:BAACLgAFFH8MAAIlAAUJPRD6CQA/AQAlAAUJPRD6CQA/AQAuAAQKfxoAAiUACAljIbQFAPMCACUACAljIbQFAPMCAAAA.',
Xa='Xanistra:BAACLgAFFH8HAAIPAAQJZxdAIAACAQAPAAQJZxdAIAACAQAuAAQKfx8AAw8ACAlZIk4NABADAA8ACAlZIk4NABADABMABAm/HFUtAAgBAAAA.Xaylor:BAAALgADCgcJCgAAAA==.',
Xz='Xzlemina:BAAALgAECgYJBgAAAA==.',
Ya='Yalaforth:BAABLgAECn8gAAIJAAcJfBPWNABvAQAJAAcJfBPWNABvAQAAAA==.Yamashaman:BAABLgAECn8jAAMVAAkJuRhBCwA2AgAVAAkJuRhBCwA2AgAOAAEJwwcCVgAsAAAAAA==.Yardgnome:BAAALgAECgIJAwAAAA==.',
Ye='Yebefd:BAAALgADCgUJBQAAAA==.',
Yu='Yungbluudd:BAAALgAECgEJAQAAAA==.',
Za='Zaleth:BAAALgAECgQJBAAAAA==.Zamasu:BAABLgAECn8YAAIfAAcJKCAdCgA5AgAfAAcJKCAdCgA5AgAAAA==.Zapmybitzup:BAAALgAFFAMJBAABLgAFFAQJCwAPAOUbAA==.Zaroneus:BAAALgADCgUJBQAAAA==.Zaszadin:BAECLgAFFH8MAAIJAAUJrxnACwBcAQAJAAUJrxnACwBcAQAuAAQKfyYAAgkACAntIusZAM0CAAkACAntIusZAM0CAAAA.Zaxxon:BAABLgAECn8kAAMcAAkJbhptAwCXAgAcAAkJbhptAwCXAgAmAAEJDQ3FPgA0AAAAAA==.',
Ze='Zekt:BAAALgADCgQJBAAAAA==.Zelo:BAAALgAECgYJCgAAAA==.Zensi:BAAALgAECgEJAQAAAA==.Zerax:BAABLgAECn8nAAIYAAgJHhrdBAAZAgAYAAgJHhrdBAAZAgAAAA==.',
Zi='Zigfury:BAAALgAECgYJDwAAAA==.Zillagoth:BAAALgAECgMJAgAAAA==.Zira:BAABLgAECn8eAAIIAAcJRxDQFQBgAQAIAAcJRxDQFQBgAQAAAA==.',
Zo='Zombiebrainz:BAAALgAECgUJCQAAAA==.Zombiebubble:BAAALgAECgYJCAAAAA==.Zoìdberg:BAACLgAFFH8LAAIVAAIJaxWTFwCdAAAVAAIJaxWTFwCdAAAuAAQKfy0AAhUACAkDIrIHAPoCABUACAkDIrIHAPoCAAAA.',
Zs='Zselk:BAAALgADCgYJCAAAAA==.',
Zu='Zubzer:BAABLgAECn8YAAIWAAgJthjCFAAUAgAWAAgJthjCFAAUAgAAAA==.',
Zz='Zzor:BAACLgAFFH8QAAIFAAUJoR7dDQCIAQAFAAUJoR7dDQCIAQAuAAQKfyMAAgUACAnAJRAPAE8DAAUACAnAJRAPAE8DAAAA.Zzorfel:BAAALgAECgEJAgABLgAFFAUJEAAFAKEeAA==.Zzorshock:BAAALgAECgYJBgABLgAFFAUJEAAFAKEeAA==.',
['Ði']='Ðii:BAAALgAECgMJAwAAAA==.',
['ßl']='ßlue:BAAALgAECgYJEgABLgAECggJLQAMAA0eAA==.',
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

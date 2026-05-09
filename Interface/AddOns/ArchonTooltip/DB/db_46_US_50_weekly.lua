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

local lookup = {'Hunter-Survival','Hunter-Marksmanship','Paladin-Protection','Paladin-Retribution','Hunter-BeastMastery','Warlock-Destruction','DemonHunter-Devourer','Mage-Frost','Evoker-Preservation','Priest-Holy','Shaman-Restoration','DeathKnight-Unholy','Druid-Guardian','Druid-Restoration','Monk-Mistweaver','Druid-Feral','Unknown-Unknown','Priest-Shadow','Monk-Brewmaster','Monk-Windwalker','Mage-Arcane','Evoker-Devastation','Warlock-Demonology','Warrior-Protection','DemonHunter-Havoc','Evoker-Augmentation','Warlock-Affliction','DeathKnight-Frost','Paladin-Holy','Druid-Balance','Rogue-Subtlety','Shaman-Elemental','Shaman-Enhancement','Warrior-Arms','Warrior-Fury','DeathKnight-Blood','Priest-Discipline','Rogue-Assassination',}
local provider = {region='US',realm='CenarionCircle',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abelene:BAAALgAECgQJBAAAAA==.Abrâham:BAAALgADCgUJBQAAAA==.',
Ac='Achelis:BAABLgAECn8uAAMBAAgJ8iVOAQAKAwABAAgJ8iVOAQAKAwACAAEJAABFggA/AAAAAA==.',
Ad='Adianitefall:BAAALgADCggJCAAAAA==.Adorian:BAAALgAECgUJCgAAAA==.Adros:BAABLgAECn8fAAMDAAgJqBEIFQB+AQADAAcJ7RMIFQB+AQAEAAEJDwQyIQEcAAAAAA==.Adrrel:BAAALgADCgIJAgABLgAFFAYJFAACACURAA==.Adrrelle:BAACLgAFFH8UAAMCAAYJJRHBCQAlAQACAAYJeg3BCQAlAQAFAAMJbAoNJABYAAAuAAQKfyMABAIACQncHXATAJoCAAIACAmXH3ATAJoCAAEABAnZFzIgAPwAAAUAAgmpEW+4AFIAAAAA.',
Ae='Aelon:BAABLgAECn8cAAIEAAgJxQeUrwAkAQAEAAgJxQeUrwAkAQAAAA==.',
Ai='Ailaith:BAABLgAECn8rAAIFAAgJYSCTCwCDAgAFAAgJYSCTCwCDAgAAAA==.',
Ak='Akariliselle:BAABLgAECn8UAAIGAAcJMBp6BADDAQAGAAcJMBp6BADDAQAAAA==.Aknologia:BAAALgAECgUJBQAAAA==.',
Al='Al:BAAALgADCggJCAAAAA==.Alan:BAAALgAECgQJBwAAAA==.Alarielle:BAAALgADCggJCAAAAA==.Aldora:BAAALgADCgkJDAAAAA==.Alirik:BAAALgADCgQJBQAAAA==.Alleriah:BAAALgAECgcJCAABLgAECggJIwAHALUfAA==.Alydrostage:BAABLgAECn8VAAIIAAYJ+ASGlgDmAAAIAAYJ+ASGlgDmAAAAAA==.Alystriaz:BAABLgAECn8ZAAIJAAgJUxhbBQBFAgAJAAgJUxhbBQBFAgAAAA==.Alzheimerz:BAAALgAECgUJBQAAAA==.',
Am='Amaelalin:BAABLgAECn8nAAIKAAgJfRCQFgCeAQAKAAgJfRCQFgCeAQAAAA==.Ameliya:BAAALgAECgIJAgAAAA==.Ameng:BAAALgAECgQJBgAAAA==.',
An='Andaya:BAABLgAECn8eAAILAAkJ4hhjHwC4AQALAAkJ4hhjHwC4AQAAAA==.Andemeli:BAAALgADCgkJCQAAAA==.Andevyn:BAAALgAECgQJBAABLgAECggJIwAHALUfAA==.Aninja:BAEALgADCgQJBAABLgAFFAQJCQAMADEaAA==.Anivia:BAABLgAECn8WAAIIAAgJrREkeQDfAQAIAAgJrREkeQDfAQAAAA==.Ankoubailith:BAAALgAECgMJAwAAAA==.',
Ap='Apollon:BAAALgADCgIJAgAAAA==.',
Ar='Arandis:BAAALgAECgYJEAAAAA==.Arch:BAAALgAECgQJBQAAAA==.Arcianna:BAABLgAECn8kAAMNAAgJfxxlBAAyAgANAAgJfxxlBAAyAgAOAAEJQREalAAyAAAAAA==.Arctica:BAAALgAECgQJCgAAAA==.Arctiq:BAAALgADCgUJCgAAAA==.Arctîc:BAABLgAECn8bAAIIAAcJoBDZUgByAQAIAAcJoBDZUgByAQAAAA==.Arjurn:BAABLgAECn8uAAIIAAgJ8h4nFAB4AgAIAAgJ8h4nFAB4AgAAAA==.Armpitbutter:BAABLgAECn8uAAIPAAgJ2CRJAgA2AwAPAAgJ2CRJAgA2AwAAAA==.Artymiss:BAAALgAECgYJBwAAAA==.',
As='Ashireita:BAAALgAECgYJEAAAAA==.Astraleth:BAAALgAECgYJDAAAAA==.',
At='Atama:BAAALgADCggJCgAAAA==.',
Au='Authority:BAAALgADCggJCAAAAA==.Autry:BAABLgAECn8eAAMQAAcJ4w9DCwBmAQAQAAcJ4w9DCwBmAQAOAAYJDwyzRAAAAQAAAA==.',
Av='Avelina:BAAALgADCgcJDgAAAA==.Avocat:BAABLgAECn8UAAIFAAYJeRO1RAA/AQAFAAYJeRO1RAA/AQAAAA==.',
Az='Azeria:BAAALgAECgUJCQABLgAFFAYJGQANAIQeAA==.Azshura:BAAALgADCgYJBgAAAA==.Azzinôth:BAAALgADCgcJBwABLgAECgEJAgARAAAAAA==.',
Ba='Baekr:BAAALgAECgYJEAAAAA==.Baldr:BAABLgAECn8iAAIEAAgJVQ7XQACDAQAEAAgJVQ7XQACDAQAAAA==.Balgar:BAABLgAECn8YAAMFAAgJAyNdBwC7AgAFAAgJAyNdBwC7AgACAAUJyxmtPgBhAQAAAA==.Balghas:BAABLgAECn8kAAIEAAgJ1hz9KQDXAQAEAAgJ1hz9KQDXAQAAAA==.Bamzhurt:BAAALgAECgUJBQABLgAFFAMJCAASAJgPAA==.Baumstrum:BAAALgAECgQJBgAAAA==.',
Be='Beezlbubba:BAAALgAECgQJBAAAAA==.Beldam:BAAALgADCgYJBgAAAA==.Belispeak:BAAALgADCgYJBgAAAA==.Bellaboom:BAAALgADCgYJBgAAAA==.Belvkara:BAAALgADCgkJCQAAAA==.Benedictoe:BAAALgADCgYJBgAAAA==.',
Bh='Bhozok:BAABLgAECn8qAAIQAAgJkxAtCACtAQAQAAgJkxAtCACtAQAAAA==.',
Bi='Bint:BAAALgADCgYJBgAAAA==.',
Bl='Bloodpromise:BAAALgADCgMJAwAAAA==.Bloodrayvn:BAABLgAECn8ZAAIFAAcJDRnlKACuAQAFAAcJDRnlKACuAQAAAA==.',
Bo='Boomchick:BAAALgAECgMJAwABLgAECgYJCgARAAAAAA==.Boomparapara:BAABLgAECn8WAAIIAAYJNh0/QACnAQAIAAYJNh0/QACnAQAAAA==.Borrkbuster:BAAALgADCgcJDgAAAA==.Bosta:BAAALgADCgQJBAAAAA==.Botkin:BAAALgADCgEJAQAAAA==.',
Br='Bradley:BAAALgAECgYJDgABLgAECgYJFAAKAHAiAA==.Brandywyne:BAAALgADCgEJAQAAAA==.Brenri:BAAALgAECggJEAAAAA==.Brew:BAABLgAECn8XAAMTAAYJah8CEADLAQATAAYJah8CEADLAQAUAAEJ0Q0CfQAzAAAAAA==.Brkat:BAAALgADCgYJBgAAAA==.Brughe:BAABLgAECn8eAAIFAAcJfgvaSgAtAQAFAAcJfgvaSgAtAQAAAA==.',
Bu='Bubbleoseven:BAAALgADCgYJBgAAAA==.Buttacutta:BAAALgADCgkJCQAAAA==.',
['Bä']='Bäné:BAAALgADCgIJAgAAAA==.',
Ca='Cairn:BAAALgADCgUJBQAAAA==.Caneste:BAACLgAFFH8PAAISAAYJnBnhAgDDAQASAAYJnBnhAgDDAQAuAAQKfx0AAhIACQm6HfQLAMMCABIACQm6HfQLAMMCAAAA.Capela:BAAALgADCgEJAQAAAA==.Capparelli:BAAALgADCgEJAQAAAA==.Cashoe:BAAALgADCgMJAwAAAA==.Catscan:BAABLgAECn8aAAIOAAgJRx6QCgCgAgAOAAgJRx6QCgCgAgABLgADCgYJBgARAAAAAA==.Catty:BAABLgAECn8hAAIQAAgJYBbzBQDuAQAQAAgJYBbzBQDuAQAAAA==.',
Ce='Celestyl:BAABLgAECn8eAAIVAAYJ4Qj9BQACAQAVAAYJ4Qj9BQACAQAAAA==.',
Ch='Charazard:BAAALgAECgUJCgABLgAECgYJGQAWAOYaAA==.Charming:BAAALgADCgMJAwAAAA==.Cheapbeer:BAAALgAECgYJDAAAAA==.Cheesehead:BAAALgADCggJEgAAAA==.Cherry:BAAALgAECgQJBAAAAA==.Chiforged:BAAALgAECgYJDAAAAA==.Chillybovine:BAAALgAECgYJDwAAAA==.Chromstrasza:BAABLgAECn8ZAAIWAAcJExgwBAC4AQAWAAcJExgwBAC4AQAAAA==.Chudderly:BAAALgADCgEJAgAAAA==.Chudders:BAAALgADCgIJAgAAAA==.',
Cl='Clarence:BAAALgADCgIJAgABLgAFFAcJFwAXALYaAA==.',
Co='Conjarr:BAABLgAECn8iAAIKAAgJjhrjJQC8AQAKAAgJjhrjJQC8AQAAAA==.Cortisol:BAAALgADCgIJAgAAAA==.Corven:BAAALgAECgUJDAAAAA==.Cougarsixsix:BAAALgAECgUJCgAAAA==.',
Cr='Crashnburn:BAAALgADCgcJDQAAAA==.Crazyoldbear:BAABLgAECn8ZAAIYAAgJ3SMTAgDRAgAYAAgJ3SMTAgDRAgAAAA==.Creideam:BAAALgADCgkJBwAAAA==.Crimos:BAABLgAECn8tAAIMAAkJnRZlFwBAAgAMAAkJnRZlFwBAAgAAAA==.Crystalliney:BAAALgADCgYJBgABLgAECggJJgATAJcmAA==.',
Cy='Cynnai:BAAALgADCgYJBgAAAA==.Cyrena:BAAALgADCgEJAQAAAA==.',
Da='Daerthor:BAABLgAECn8bAAIDAAgJ0xXtCAC6AQADAAgJ0xXtCAC6AQAAAA==.Dalind:BAAALgAECgUJCgAAAA==.Dalshiro:BAAALgAECgUJCAAAAA==.Damaclies:BAABLgAECn8jAAMXAAkJGxKkKgC6AQAXAAcJzBGkKgC6AQAGAAUJHBOcMgDtAAAAAA==.Damedolla:BAABLgAECn8fAAMHAAgJYAzwQQAzAQAHAAgJwQrwQQAzAQAZAAUJnw7BQAD3AAAAAA==.Dammerung:BAAALgAECgYJBwAAAA==.Darksyn:BAAALgAECgYJEAAAAA==.Darthbane:BAAALgAECgYJBgAAAA==.Darude:BAAALgADCgcJEAAAAA==.',
De='Deadstout:BAAALgAECgQJBAAAAA==.Deepspace:BAABLgAECn8XAAIZAAgJESZVAQANAwAZAAgJESZVAQANAwAAAA==.Deezus:BAAALgADCgMJAwAAAA==.Dejagauth:BAAALgADCgkJCQAAAA==.Dekkan:BAAALgAECgYJEAAAAA==.Demòn:BAAALgAECgEJAQAAAA==.Denounce:BAABLgAECn8YAAIaAAcJqBdwHQBTAQAaAAcJqBdwHQBTAQAAAA==.',
Di='Dia:BAAALgADCgkJGwAAAA==.Diabetes:BAABLgAFFH8MAAIPAAUJFxgkCQCNAQAPAAUJFxgkCQCNAQAAAA==.Diastolic:BAAALgADCgUJBQAAAA==.Diend:BAABLgAECn8sAAILAAgJPR+lBwCzAgALAAgJPR+lBwCzAgAAAA==.Dill:BAAALgADCgcJCgABLgAECggJLgABAPIlAA==.Dillathis:BAAALgADCgEJAQAAAA==.Dissonanita:BAAALgAECgEJAQAAAA==.',
Dj='Djthelock:BAABLgAECn8WAAMXAAcJwxIiXgAVAQAXAAUJcQ4iXgAVAQAGAAMJGBxXFQClAAAAAA==.',
Do='Dormoon:BAAALgAECgYJEgAAAA==.',
Dr='Drac:BAAALgADCgYJCgAAAA==.Dragath:BAAALgAECgQJCwAAAA==.Drakur:BAAALgAECgYJCQAAAA==.Drbrad:BAABLgAECn8UAAMKAAYJcCLlCgA4AgAKAAYJcCLlCgA4AgASAAMJDhBRQQBuAAAAAA==.Dreadfangs:BAAALgADCgQJBQAAAA==.Druen:BAABLgAECn8kAAIQAAgJohjfBAAUAgAQAAgJohjfBAAUAgAAAA==.Drunkenpo:BAABLgAECn8sAAITAAgJFyD0BQB9AgATAAgJFyD0BQB9AgAAAA==.Drïzl:BAEALgADCgQJBAABLgAFFAQJCQAMADEaAA==.',
Du='Duckchow:BAAALgADCgYJBgAAAA==.Dugga:BAAALgADCgQJBAAAAA==.Duskmyre:BAABLgAECn8WAAIHAAgJCQk5UQAGAQAHAAgJCQk5UQAGAQAAAA==.',
Dw='Dwarfoo:BAAALgAECgUJCgAAAA==.Dweñde:BAABLgAECn8WAAIXAAcJ4gUWZgACAQAXAAcJ4gUWZgACAQAAAA==.',
['Dë']='Dëthmetal:BAABLgAECn8UAAIMAAUJngzgmACvAAAMAAUJngzgmACvAAAAAA==.',
Ed='Eddrick:BAABLgAECn8UAAIEAAcJ/hQ7SwBkAQAEAAcJ/hQ7SwBkAQAAAA==.Edoran:BAAALgADCggJCAAAAA==.Edrani:BAAALgAECgIJAwAAAA==.',
Ei='Eilethen:BAABLgAECn8ZAAIbAAgJYRkvAgASAgAbAAgJYRkvAgASAgAAAA==.',
El='Elaína:BAAALgADCgMJAwABLgAFFAMJBgAbAM4OAA==.Elissabethh:BAAALgAECgUJCgAAAA==.Elminstar:BAAALgADCgIJAgAAAA==.',
Em='Employee:BAAALgAECgUJDQAAAA==.',
En='Engo:BAABLgAECn8tAAIKAAkJdCOwAACMAwAKAAkJdCOwAACMAwAAAA==.',
Er='Eradrá:BAACLgAFFH8GAAMbAAMJzg7PAwCUAAAXAAMJ7gocRwDLAAAbAAIJEQrPAwCUAAAuAAQKfz0AAxsACQm4G+gAAA4DABsACQmPG+gAAA4DABcACAkmFEAmANABAAAA.Erastrasza:BAAALgADCgYJCQAAAA==.Eroza:BAAALgAECgUJBgAAAA==.Ersey:BAAALgAECgQJBAABLgAECggJKAAOAKoYAA==.Ersèlla:BAABLgAECn8oAAIOAAgJqhi5GQD2AQAOAAgJqhi5GQD2AQAAAA==.Erysira:BAAALgADCgkJCQAAAA==.',
Et='Ethan:BAAALgAECgEJAQAAAA==.',
Eu='Eureka:BAAALgAECgYJCwABLgAECgYJDAARAAAAAA==.',
Ev='Evandra:BAABLgAECn8bAAILAAgJdRrPDgBMAgALAAgJdRrPDgBMAgAAAA==.Evanorah:BAAALgAECgYJEgAAAA==.',
Ex='Exïle:BAEALgAECgYJBgABLgAFFAQJCQAMADEaAA==.',
Fa='Faelithia:BAABLgAECn8VAAIKAAYJKw6MJAAlAQAKAAYJKw6MJAAlAQAAAA==.Fatalbrew:BAAALgAECgMJAwAAAA==.',
Fe='Feldush:BAAALgADCgYJBgABLgAECgYJGQAWAOYaAA==.Felforit:BAAALgADCgQJBAAAAA==.Felis:BAAALgAECgYJCgAAAA==.Felkardio:BAAALgAECgIJAgAAAA==.Ferheim:BAAALgADCgkJGQAAAA==.',
Fi='Fiddyone:BAABLgAECn8eAAMMAAgJYB/QFgBFAgAMAAgJbx3QFgBFAgAcAAUJAiL/BACNAQAAAA==.Figment:BAAALgADCgYJBgAAAA==.Fireburt:BAAALgADCgUJBQAAAA==.Fireslay:BAABLgAECn8YAAIdAAcJpBwGHgAmAgAdAAcJpBwGHgAmAgAAAA==.',
Fl='Flarefly:BAAALgAECgEJAQAAAA==.Flaya:BAAALgAECgMJAwAAAA==.',
Fo='Fodurzin:BAAALgADCgMJAwABLgADCgcJBwARAAAAAA==.Fonta:BAAALgADCgQJBAAAAA==.Fortuna:BAAALgADCgYJBgABLgAECgYJCgARAAAAAA==.Foxingtobi:BAAALgADCgIJAgAAAA==.',
Fr='Frojio:BAABLgAECn8oAAIcAAgJvh2WAQBdAgAcAAgJvh2WAQBdAgAAAA==.Frosten:BAAALgADCgkJJwAAAA==.',
Fu='Furenio:BAABLgAECn8kAAINAAkJEBZnBgDjAQANAAkJEBZnBgDjAQAAAA==.',
Fy='Fyyre:BAAALgAECgMJBAAAAA==.',
Ga='Gabaghoul:BAACLgAFFH8FAAIEAAIJyhxaOgDAAAAEAAIJyhxaOgDAAAAuAAQKfyoAAgQACAkmIWQNAJUCAAQACAkmIWQNAJUCAAAA.Gaff:BAAALgAECgYJDgAAAA==.Galvan:BAAALgAECgEJBAAAAA==.Gasheth:BAAALgAECgMJAwAAAA==.',
Gi='Giggleblast:BAAALgADCggJCgAAAA==.',
Gl='Glizzydealer:BAAALgAECgEJAQAAAA==.',
Gr='Grauth:BAAALgADCgEJAQAAAA==.Graycen:BAAALgAECgMJBAAAAA==.Grido:BAAALgADCgkJDgAAAA==.Grimbrindral:BAABLgAECn8hAAMEAAcJ5hZFZAC5AQAEAAcJdBVFZAC5AQADAAUJghrGFwBZAQAAAA==.Grimston:BAAALgADCgMJAwABLgAECgcJIQAEAOYWAA==.',
Gu='Gulishdaniel:BAAALgAECgcJBwABLgAFFAYJDwASAJwZAA==.',
Ha='Hadin:BAABLgAECn8qAAMIAAgJZSC2EACUAgAIAAgJJiC2EACUAgAVAAMJqhyrDwDHAAAAAA==.Halalnt:BAAALgAECgIJAgABLgAECggJFgAaAJobAA==.Hanua:BAAALgADCgcJBwAAAA==.Haozhao:BAABLgAECn8lAAMNAAgJZxbLCACaAQANAAgJZxbLCACaAQAQAAEJVBN7IwBFAAAAAA==.Hazenpryde:BAAALgAECgYJEQAAAA==.',
He='Hearsay:BAAALgAECgYJEAAAAA==.Hephaistian:BAAALgADCgcJFgAAAA==.Hespera:BAABLgAECn8eAAMOAAkJyCDpGABwAgAOAAgJoSHpGABwAgAeAAMJ+xB1MgDGAAAAAA==.',
Hi='Hirari:BAAALgAECgcJEwAAAA==.',
Ho='Hodoor:BAAALgADCgUJBQAAAA==.Howlears:BAABLgAECn8VAAISAAYJIgT9MQDJAAASAAYJIgT9MQDJAAAAAA==.',
Hu='Hulud:BAABLgAECn8XAAMXAAgJSRfNLwCkAQAXAAgJSRfNLwCkAQAGAAEJAACjNQAAAAAAAA==.Husbando:BAAALgADCggJCgAAAA==.Husey:BAAALgAECgMJBgAAAA==.',
Hy='Hydrangea:BAAALgAECgcJCwAAAA==.Hydrá:BAAALgAECggJDwAAAA==.Hylan:BAAALgADCgUJBQAAAA==.Hysgar:BAAALgADCgkJDwABLgAECgYJBgARAAAAAA==.',
Ic='Iceamaris:BAAALgAECgYJDwAAAA==.Icetiger:BAAALgADCgIJAgAAAA==.',
Ie='Iechu:BAAALgAECgcJCQAAAA==.',
In='Innanna:BAAALgADCggJCgABLgAECgEJAwARAAAAAA==.',
Is='Isoth:BAAALgAECgEJAQAAAA==.',
Iv='Ivern:BAABLgAFFH8IAAIOAAYJxghWCwCJAQAOAAYJxghWCwCJAQABLgAFFAYJGAAJAJ0XAA==.',
Ja='Jaod:BAAALgADCgkJDgAAAA==.',
Jd='Jdghoul:BAAALgAECggJDAAAAA==.',
Ji='Jindrac:BAAALgAECgIJAgAAAA==.',
Jo='Jolton:BAAALgADCgYJBwABLgAECgkJIAAHAIshAA==.',
['Jà']='Jàcaranda:BAAALgAECgEJAQAAAA==.',
Ka='Kahnrah:BAAALgADCgkJDAAAAA==.Kalarae:BAAALgAECgcJBwAAAA==.Kaltharion:BAAALgAECgQJBQAAAA==.Kaluren:BAAALgAECgcJCwAAAA==.Kana:BAAALgAECgIJAgAAAA==.Kanade:BAABLgAECn8qAAQXAAgJphirHgD5AQAXAAcJphirHgD5AQAGAAMJYwUETACJAAAbAAIJuQbKIgBnAAAAAA==.Kantong:BAABLgAECn8gAAIUAAgJdBnlCgALAgAUAAgJdBnlCgALAgAAAA==.Kapp:BAAALgAECgQJBAAAAA==.Karabar:BAABLgAECn8uAAMDAAgJsiC4AwBeAgAEAAcJ1CMGEwBiAgADAAgJSh64AwBeAgAAAA==.Kasarra:BAAALgAECgYJEQAAAA==.Kazagol:BAABLgAECn8uAAIHAAgJ8h9UDQBhAgAHAAgJ8h9UDQBhAgAAAA==.',
Kh='Khamaracy:BAAALgAECgUJCgAAAA==.Khronni:BAAALgAECgMJAwAAAA==.Khrooze:BAAALgAECgQJDAAAAA==.',
Ki='Kidos:BAAALgAECgQJBgAAAA==.Kiljana:BAAALgAECgEJAQAAAA==.Kimahrí:BAAALgAECgUJCgAAAA==.Kittei:BAABLgAECn8uAAINAAgJmhD6DAA9AQANAAgJmhD6DAA9AQAAAA==.',
Ko='Kojote:BAAALgADCgMJAQAAAA==.Kovalenko:BAAALgAECgEJAQAAAA==.',
Ku='Kurick:BAAALgAECgYJBgAAAA==.Kurzul:BAAALgADCgEJAgAAAA==.Kusinluvin:BAAALgADCgEJAQAAAA==.',
Ky='Kyngizzard:BAABLgAECn8XAAIIAAgJbxgzKQD9AQAIAAgJbxgzKQD9AQABLgAECggJFgAaAJobAA==.',
La='Lactase:BAAALgADCgMJAwAAAA==.Latte:BAAALgADCgIJAgAAAA==.',
Le='Leeli:BAAALgADCgcJBwAAAA==.Lenity:BAABLgAECn8eAAIfAAYJbBQHFgBaAQAfAAYJbBQHFgBaAQAAAA==.Letty:BAAALgAECgQJBQAAAA==.',
Li='Liabelle:BAAALgADCgIJAgAAAA==.Lilithene:BAAALgAECgUJBQABLgAECgYJEAARAAAAAA==.Lionbark:BAAALgADCgEJAQAAAA==.Lithpally:BAAALgADCgEJAQAAAA==.',
Lo='Lokinah:BAAALgAECgYJEAAAAA==.Loonytusk:BAAALgADCgQJBAAAAA==.',
Lu='Lucifermadis:BAAALgAECgQJBgAAAA==.Lucoryphus:BAAALgAECgYJEgAAAA==.Lukeduke:BAABLgAFFH8GAAIYAAQJ0Bn9BwAsAQAYAAQJ0Bn9BwAsAQABLgAFFAYJGQANAIQeAA==.Luketheduke:BAACLgAFFH8ZAAMNAAYJhB74AADLAQANAAUJhB74AADLAQAQAAEJAAAIBwA3AAAuAAQKfycAAw0ACQkqJR8BAFcDAA0ACQkqJR8BAFcDABAABAmxFXocAAkBAAAA.Lumilia:BAAALgADCgUJBQAAAA==.Lunä:BAABLgAECn8ZAAILAAgJ1BVqIgAQAgALAAgJ1BVqIgAQAgAAAA==.',
Ly='Lydia:BAABLgAECn8iAAIIAAgJ2RnLIgAcAgAIAAgJ2RnLIgAcAgAAAA==.',
['Lô']='Lôckrocks:BAAALgAECgcJDAAAAA==.',
['Lý']='Lýsendra:BAAALgADCggJCQAAAA==.',
Ma='Magictomb:BAABLgAECn8pAAQgAAgJlhVFGACOAQAgAAgJlhVFGACOAQALAAYJ6A3cQgD3AAAhAAMJsAcoFwCSAAABLgAFFAIJAgARAAAAAA==.Malcontent:BAAALgAECgQJBQABLgAECgYJCgARAAAAAA==.Maldazane:BAAALgADCgYJCwAAAA==.Malfeasance:BAAALgADCgkJDQABLgAECgYJCgARAAAAAA==.Malidan:BAAALgADCgMJAwAAAA==.Malifel:BAAALgAECgYJCgAAAA==.Maliss:BAABLgAECn8qAAQBAAgJiRjsCwDlAQABAAgJjhfsCwDlAQACAAQJtghGYwCzAAAFAAEJoxFRtAA9AAAAAA==.Mallord:BAAALgAECgYJBwABLgAECgYJCgARAAAAAA==.Mandarin:BAABLgAECn8ZAAIOAAcJ9xecHwDIAQAOAAcJ9xecHwDIAQAAAA==.Manmythlegnd:BAAALgADCgYJBgAAAA==.Mannik:BAAALgAFFAEJAQAAAA==.Marashades:BAAALgADCgQJBAABLgAECggJGQAYAN0jAA==.',
Mc='Mcbadden:BAAALgAECgYJBwAAAA==.',
Me='Meditatetoe:BAAALgADCgIJAgAAAA==.Melissà:BAAALgADCgMJAwAAAA==.Menesta:BAAALgADCgcJBwAAAA==.Mercia:BAABLgAECn8iAAIDAAgJPBayCgCWAQADAAgJPBayCgCWAQAAAA==.Merekoma:BAAALgAECgUJDAAAAA==.',
Mi='Milarra:BAAALgAECgMJBQAAAA==.Milhouse:BAAALgAECgQJBQAAAA==.Minalan:BAAALgADCgYJCgABLgAECgQJDAARAAAAAA==.Mingonashoba:BAAALgAECgYJCwAAAA==.Miragosa:BAABLgAECn8gAAMJAAgJwwQ7KgAgAQAJAAgJwwQ7KgAgAQAWAAEJ8AH0GgAaAAAAAA==.Misschris:BAABLgAECn8ZAAIPAAgJhgi8IwApAQAPAAgJhgi8IwApAQAAAA==.Mizu:BAAALgADCgcJDgAAAA==.',
Mo='Moadeed:BAAALgAECgYJBwAAAA==.Mooluv:BAAALgADCgcJCgAAAA==.Moonstrike:BAAALgAECgEJAQAAAA==.Mordrius:BAAALgADCgYJBgAAAA==.Mortesque:BAAALgAECgcJEgAAAA==.',
Mu='Muttblitzed:BAAALgAECgQJBAAAAA==.Muttskî:BAAALgAECgMJAwAAAA==.',
My='Mybutt:BAAALgAECgMJBgAAAA==.Myrothos:BAAALgADCgEJAQAAAA==.Myrrh:BAAALgAECgYJEQAAAA==.',
['Mí']='Místermage:BAAALgAECgQJCAAAAA==.',
Na='Nasturtium:BAAALgADCgYJDgAAAA==.Naturestone:BAAALgAFFAIJAgAAAA==.Nausican:BAABLgAECn8eAAIcAAcJYRaxBACcAQAcAAcJYRaxBACcAQAAAA==.Nazuhda:BAAALgADCgEJAQAAAA==.',
Ne='Necrosector:BAABLgAECn8gAAIEAAgJLRccJQDuAQAEAAgJLRccJQDuAQAAAA==.Necrotherys:BAABLgAECn8aAAIHAAcJ+BtXHADfAQAHAAcJ+BtXHADfAQAAAA==.Nelandra:BAAALgAECgUJCgAAAA==.',
Ni='Nicklaus:BAAALgAECgYJEQAAAA==.Nilrem:BAAALgADCgIJAgAAAA==.Ninelives:BAAALgAECgYJDgAAAA==.Ninjadk:BAECLgAFFH8JAAIMAAQJMRoBIABgAQAMAAQJMRoBIABgAQAuAAQKfycAAwwACAn6IwYLALICAAwACAn6IwYLALICABwAAQmqGykTAFEAAAAA.',
No='Nocapongfrfr:BAAALgAECgMJAwABLgAFFAMJCQAaAEcIAA==.Nomahuata:BAABLgAECn8vAAIgAAgJtxOlFwCUAQAgAAgJtxOlFwCUAQAAAA==.Nordre:BAAALgAECgMJAwAAAA==.',
Nu='Nufrus:BAAALgADCgYJBgAAAA==.',
Ny='Nyxi:BAAALgAECgQJBgAAAA==.Nyxlee:BAAALgADCgkJDwAAAA==.',
['Né']='Néo:BAAALgAECgMJAwAAAA==.',
Og='Ogdruid:BAAALgADCgcJDgAAAA==.',
Ol='Olympian:BAAALgADCgcJBwAAAA==.',
Om='Omanyte:BAAALgADCgcJBwAAAA==.',
On='Onefiftyone:BAABLgAECn8UAAMhAAUJKiN7DQDnAQAhAAUJKiN7DQDnAQALAAIJnSRHTADOAAABLgAECggJHgAMAGAfAA==.',
Or='Orruk:BAAALgADCgMJAwAAAA==.Orwyn:BAAALgADCgcJDQAAAA==.',
Ov='Overdose:BAAALgADCgMJAwAAAA==.',
Pa='Padmé:BAAALgAECgEJAQAAAA==.Palanas:BAAALgAECggJEAAAAA==.Palochka:BAAALgAECgQJBAAAAA==.Paradots:BAABLgAECn8WAAIJAAYJtRo9CgCwAQAJAAYJtRo9CgCwAQABLgADCgYJBgARAAAAAA==.Paranitis:BAAALgAECggJDAAAAA==.Paranorm:BAAALgADCgEJAQAAAA==.Paraparaboom:BAAALgAECgUJBQABLgAECgYJFgAIADYdAA==.',
Pe='Petronella:BAABLgAECn8rAAMiAAgJWQxPDwBRAQAiAAgJWQxPDwBRAQAjAAQJ+wNZgwCxAAAAAA==.Pezmage:BAAALgAECgEJAQAAAA==.',
Ph='Phatboi:BAAALgADCgIJAwAAAA==.',
Pi='Pixystix:BAAALgAECgUJDAAAAA==.',
Po='Poisonspain:BAAALgADCgkJEwAAAA==.Potscold:BAACLgAFFH8MAAIIAAYJWBiCDAC5AQAIAAYJWBiCDAC5AQAuAAQKfzsAAggACAnaJagHAPUCAAgACAnaJagHAPUCAAAA.Poxi:BAAALgAECgIJAgABLgAECggJGAAIADwdAA==.',
Pr='Prion:BAAALgAECgUJEwAAAA==.',
Pu='Pull:BAABLgAECn8aAAINAAgJ1BpgBgDkAQANAAgJ1BpgBgDkAQAAAA==.',
Ra='Radioshack:BAAALgADCggJCAAAAA==.Radkemonko:BAAALgAECgcJDwAAAA==.Raega:BAAALgADCgYJBgAAAA==.Ragerlock:BAAALgADCgEJAQAAAA==.Raivel:BAAALgAECgUJBwAAAA==.Raldaron:BAAALgADCgEJAQAAAA==.Raneyth:BAAALgAECgQJBAAAAA==.Ravagèr:BAAALgAECgEJAgAAAA==.',
Rd='Rdbwarrior:BAAALgADCgUJBQAAAA==.',
Re='Redemus:BAAALgADCgEJAQAAAA==.Redwinetoast:BAABLgAECn8ZAAIXAAgJfgNDbwDsAAAXAAgJfgNDbwDsAAAAAA==.Reliala:BAAALgADCgkJDgAAAA==.Reno:BAAALgADCgkJEAAAAA==.Reshyk:BAAALgAECggJEQAAAA==.Resles:BAAALgAECgEJAQAAAA==.Respectwomen:BAAALgADCgEJAQABLgAECgQJBAARAAAAAA==.',
Rh='Rhobes:BAAALgADCgkJHQAAAA==.Rhondta:BAABLgAECn8bAAIXAAgJ0Q7NMwCVAQAXAAgJ0Q7NMwCVAQAAAA==.',
Ri='Rickormortis:BAAALgAECgYJCAABLgAECggJGQAPAIYIAA==.Rictus:BAABLgAECn8nAAIIAAkJuCFFBQAfAwAIAAkJuCFFBQAfAwAAAA==.Ringmasterr:BAAALgADCgUJBQAAAA==.Riordaa:BAAALgADCgYJDAAAAA==.Risingdragon:BAABLgAECn8YAAIUAAYJChJkIAAiAQAUAAYJChJkIAAiAQAAAA==.',
Ro='Roades:BAAALgADCgcJDAAAAA==.Roboskritch:BAAALgADCgUJBQAAAA==.Ronaj:BAAALgADCgMJBAAAAA==.Royveer:BAAALgADCgYJCQAAAA==.',
Ru='Rumor:BAAALgAECgQJBQABLgAECgYJEAARAAAAAA==.Rurry:BAACLgAFFH8YAAIJAAYJnRe6BACuAQAJAAYJnRe6BACuAQAuAAQKfykABAkACQlkIrECAEADAAkACQlkIrECAEADABYABQm6GRYWAI8BABoAAwlTF+xGAL8AAAAA.',
Ry='Ryumi:BAABLgAECn8gAAIHAAkJiyFhCQCQAgAHAAkJiyFhCQCQAgAAAA==.Ryur:BAAALgAECgQJCwAAAA==.',
Sa='Sabastion:BAAALgAECgYJBgABLgAECgYJCgARAAAAAA==.Sacrickficed:BAAALgAECgQJBAABLgAECggJGQAPAIYIAA==.Sahwe:BAAALgAECgQJBAAAAA==.Salocar:BAAALgAECgcJEwAAAA==.Sanafela:BAAALgADCgkJKAAAAA==.Saphisha:BAAALgAECgYJDAAAAA==.Sasora:BAAALgAECgUJCgAAAA==.Saucemagic:BAAALgAECgcJDQAAAA==.Savonah:BAAALgADCgkJKAAAAA==.',
Sc='Scaledaddy:BAAALgAECgcJEQAAAA==.Scalespawn:BAAALgADCgYJBgABLgAFFAYJFAAMAFcZAA==.Scaryl:BAAALgADCgkJGAAAAA==.Scourgespawn:BAACLgAFFH8UAAMMAAYJVxmVCgC0AQAMAAUJVxmVCgC0AQAkAAIJpwicIAA1AAAuAAQKfyQAAwwACQleIC0kAK0CAAwACQleIC0kAK0CACQABAmHEjMjAKwAAAAA.',
Se='Selenë:BAAALgAECgMJAwAAAA==.Sengoku:BAAALgADCggJCgAAAA==.Serbiscuit:BAAALgAECgUJCgAAAA==.Sereneya:BAAALgADCgcJBwAAAA==.Serenval:BAAALgADCgkJCQAAAA==.',
Sh='Shadowshart:BAAALgAECgEJAQAAAA==.Shait:BAAALgADCgYJBgAAAA==.Shalis:BAABLgAECn8YAAIFAAgJJRhVHQDsAQAFAAgJJRhVHQDsAQAAAA==.Sharivee:BAAALgAECggJDwAAAA==.Sharko:BAABLgAECn8ZAAQDAAgJ0haRDwDMAQADAAcJzBWRDwDMAQAEAAIJnhJftgCIAAAdAAIJwgOLiwBPAAAAAA==.Shibui:BAABLgAECn8sAAMZAAgJCBVpDAC6AQAZAAgJyRRpDAC6AQAHAAcJpAYkowDNAAAAAA==.Shiggles:BAAALgAECgYJDAABLgAECgkJKQAEAKohAA==.Shinhaein:BAABLgAECn8UAAIIAAYJzhTPZABIAQAIAAYJzhTPZABIAQABLgAFFAQJCgAMAKEXAA==.Shockazilla:BAABLgAECn8rAAMdAAgJ7B9GBADxAgAdAAgJ7B9GBADxAgAEAAMJVw+v/wCWAAAAAA==.Shreddarfort:BAAALgADCgkJFQAAAA==.Shönuff:BAAALgAECgEJAQAAAA==.',
Si='Sigh:BAAALgAECgUJDAAAAA==.Silverhorn:BAAALgAECgUJDQAAAA==.',
Sk='Skoduh:BAABLgAECn8WAAIFAAYJDBsILgCWAQAFAAYJDBsILgCWAQAAAA==.Skyelene:BAABLgAECn8bAAMgAAcJKg+3QwA6AQAgAAYJCg+3QwA6AQALAAcJsQaCQQD9AAAAAA==.',
Sl='Slaanesh:BAAALgAECgYJEgAAAA==.Sluggo:BAAALgAFFAEJAQAAAA==.Sluggoboyce:BAACLgAFFH8GAAICAAQJhgRwEwAHAQACAAQJhgRwEwAHAQAuAAQKfyIAAwIACAkLGRocAEcCAAIACAnYGBocAEcCAAUABAmEDS+aAJ8AAAAA.',
Sm='Smeagosses:BAAALgADCgcJDAAAAA==.Smokeü:BAAALgAECgcJBwAAAA==.',
So='Solace:BAAALgAECgUJBgAAAA==.Solinaara:BAAALgADCgEJAQAAAA==.Soraka:BAABLgAFFH8FAAIlAAMJCAR7GwDAAAAlAAMJCAR7GwDAAAAAAA==.',
Sp='Spiralist:BAABLgAECn8aAAQeAAgJJhpBHQBLAQAeAAYJcRhBHQBLAQAOAAcJvRWMQgAJAQAQAAIJkAwlHwBjAAAAAA==.Spiralmist:BAAALgADCgMJAwAAAA==.',
St='Starge:BAAALgAECgUJBQAAAA==.Steelforged:BAAALgADCgcJBwABLgAECgYJDAARAAAAAA==.Stonedalways:BAAALgAECgUJBwAAAA==.',
Su='Sunfuri:BAABLgAECn8sAAIjAAgJfghCIQBiAQAjAAgJfghCIQBiAQAAAA==.Sunjan:BAAALgADCgkJGAAAAA==.Sus:BAACLgAFFH8XAAIZAAYJtRuMAADbAQAZAAYJtRuMAADbAQAuAAQKfyIAAhkACQmXI5YDAEcDABkACQmXI5YDAEcDAAAA.Susanoo:BAAALgAECgYJEgAAAA==.',
Sy='Sylvíadne:BAAALgAECgYJBgAAAA==.',
Sz='Szul:BAAALgADCgcJDAAAAA==.',
Ta='Tactics:BAAALgADCgcJDAAAAA==.Tahitimango:BAAALgAECgUJEwAAAA==.Takeko:BAAALgADCgcJDgABLgAECgQJCQARAAAAAA==.Talanas:BAAALgADCgcJBwAAAA==.Taleria:BAAALgADCgYJDAAAAA==.Taranad:BAAALgAECgYJCwAAAA==.Tarathor:BAAALgAECgUJCgAAAA==.Tasha:BAAALgAECgEJAgABLgAECgUJEwARAAAAAA==.Tauroctony:BAABLgAECn8aAAINAAgJHSGhBACiAgANAAgJHSGhBACiAgAAAA==.',
Te='Tea:BAAALgAECgUJBQABLgAECggJJwAKAH0QAA==.Teknofarious:BAAALgAECgEJAgAAAA==.Tenom:BAAALgAECgUJCgAAAA==.',
Th='Thalar:BAAALgAECgIJAgAAAA==.Thaumas:BAAALgADCgEJAQAAAA==.Thelsyn:BAAALgAECgIJAgABLgAECggJKgABAIkYAA==.Thesafe:BAAALgAECgIJAgAAAA==.Thialaa:BAAALgAECgEJAgABLgAECggJKwAFAGEgAA==.Thialia:BAAALgAECgYJCwABLgAECggJKwAFAGEgAA==.Thorey:BAAALgAECgEJAQAAAA==.Thornbreaker:BAAALgADCgEJAQAAAA==.Thorthunda:BAAALgAECgQJBgAAAA==.',
Ti='Tinkabella:BAABLgAECn8uAAIlAAgJ9iPRAQBNAwAlAAgJ9iPRAQBNAwAAAA==.Tizl:BAEALgAECgUJBQABLgAFFAQJCQAMADEaAA==.',
To='Tobiblindpaw:BAAALgAECgQJBAAAAA==.Toenailjuice:BAAALgADCgUJBQABLgAECggJLgAPANgkAA==.Torrey:BAABLgAECn8YAAIdAAgJHiVtAwA8AwAdAAgJHiVtAwA8AwAAAA==.',
Tr='Trema:BAAALgAECgEJAQAAAA==.Trix:BAABLgAECn8uAAILAAgJBw3kLABjAQALAAgJBw3kLABjAQAAAA==.',
Tu='Tulsi:BAABLgAECn8lAAImAAgJZCLsAADBAgAmAAgJZCLsAADBAgAAAA==.Tuskoo:BAAALgAECgcJEQAAAA==.',
Ty='Tyrathion:BAAALgAECgMJAwAAAA==.Tyronos:BAABLgAECn8VAAIEAAYJ2RWPcgAHAQAEAAYJ2RWPcgAHAQAAAA==.',
Uk='Uknôwnforce:BAAALgAECgMJBAAAAA==.',
Un='Unbeetable:BAAALgADCgUJBQAAAA==.',
Va='Valanoth:BAABLgAECn8jAAIHAAgJtR8YCQCTAgAHAAgJtR8YCQCTAgAAAA==.Valdr:BAABLgAECn8bAAMaAAgJbhFVFAClAQAaAAgJbhFVFAClAQAWAAQJowzOKQDQAAAAAA==.Valoryck:BAAALgAECgQJDQABLgAECggJIwAHALUfAA==.Vas:BAAALgADCgYJEgAAAA==.',
Ve='Velielina:BAAALgAECgEJAQAAAA==.Vellandrias:BAAALgADCgYJBgAAAA==.Verinda:BAAALgADCgcJDwAAAA==.Vessara:BAAALgADCgUJBQABLgAECgYJDAARAAAAAA==.Vevicenth:BAAALgAECgcJBwAAAA==.',
Vo='Voranth:BAAALgADCgMJAwAAAA==.',
Wa='Warpsbulge:BAACLgAFFH8WAAIIAAUJcx5hCgDMAQAIAAUJcx5hCgDMAQAuAAQKfxsAAwgACQlNIbkhAOwCAAgACQlNIbkhAOwCABUAAgl2FLMTAIoAAAAA.',
Wh='Whakan:BAAALgADCgkJKAABLgAECgYJEgARAAAAAA==.',
Wo='Wolfos:BAAALgAECgcJDgABLgAECggJKAAPAIMlAA==.',
Wt='Wtfox:BAEALgAECgYJDQABLgAECggJHgAgAJUWAA==.',
Wu='Wulfgange:BAAALgADCgEJAQAAAA==.',
Wy='Wysteri:BAAALgAECgEJAwAAAA==.',
Xa='Xadrai:BAAALgADCgIJAgAAAA==.Xakeko:BAAALgAECgQJCQAAAA==.Xalatos:BAAALgADCgEJAQAAAA==.Xalfein:BAAALgADCggJEgAAAA==.',
Xi='Xinu:BAAALgADCgYJBgABLgAECggJLAAFANgbAA==.',
Ya='Yanakana:BAAALgAECgQJBAAAAA==.',
Yd='Ydalise:BAAALgAECgEJAQAAAA==.Ydrassil:BAAALgAECgYJDAAAAA==.',
Yi='Yitsuni:BAAALgAECgcJDQAAAA==.',
Za='Zalaeda:BAAALgAECgEJAQAAAA==.Zalena:BAAALgAECgQJBwAAAA==.Zatriani:BAAALgAECgYJCgAAAA==.',
Ze='Zenus:BAABLgAECn8hAAMFAAgJQxPCIgDNAQAFAAgJQxPCIgDNAQACAAMJqwc9IgBKAAAAAA==.Zerina:BAAALgADCgUJBQAAAA==.Zesty:BAAALgADCgMJAwAAAA==.Zeusal:BAAALgAECgYJCwAAAA==.Zeusinator:BAABLgAECn8XAAIFAAcJ5RWgLgCUAQAFAAcJ5RWgLgCUAQAAAA==.',
Zi='Zinu:BAABLgAECn8sAAIFAAgJ2BvaEwAxAgAFAAgJ2BvaEwAxAgAAAA==.Zivalisse:BAAALgAECgQJBAAAAA==.',
Zu='Zulfionn:BAABLgAECn8VAAIFAAcJEwitUQAZAQAFAAcJEwitUQAZAQAAAA==.',
['Áy']='Áyrá:BAABLgAECn8bAAIdAAgJCxtdDgAzAgAdAAgJCxtdDgAzAgAAAA==.',
['Åp']='Åpollyon:BAAALgAECgIJAgAAAA==.',
['Øu']='Øuroboros:BAABLgAECn8ZAAQWAAYJ5hp1FAChAQAWAAYJ5hp1FAChAQAaAAMJ4heJRQDHAAAJAAIJwQxFIwBUAAAAAA==.',
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

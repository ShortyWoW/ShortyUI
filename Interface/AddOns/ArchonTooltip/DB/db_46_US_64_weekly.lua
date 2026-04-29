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

local lookup = {'Warlock-Demonology','Warlock-Destruction','Unknown-Unknown','Druid-Feral','Shaman-Restoration','Priest-Holy','Priest-Shadow','Mage-Frost','Monk-Windwalker','Warrior-Fury','Evoker-Devastation','DemonHunter-Havoc','Warrior-Protection','Monk-Brewmaster','DemonHunter-Vengeance','Paladin-Retribution','Priest-Discipline','DeathKnight-Unholy','DemonHunter-Devourer','Shaman-Enhancement','Evoker-Preservation','Rogue-Outlaw','Monk-Mistweaver','Evoker-Augmentation','Hunter-BeastMastery','Hunter-Marksmanship','Hunter-Survival','Druid-Restoration','Druid-Balance','Shaman-Elemental','DeathKnight-Blood','Mage-Arcane','Paladin-Holy','Druid-Guardian','Warlock-Affliction','Rogue-Subtlety','DeathKnight-Frost',}
local provider = {region='US',realm='Deathwing',name='US',type='weekly',zone=46,date='2026-04-24',data={Aa='Aamix:BAACLgAFFH8JAAIBAAQJvQwdCQAzAQABAAQJvQwdCQAzAQAuAAQKfygAAwEACAlOH/wZALkCAAEACAlOH/wZALkCAAIAAQkAAKt+ABsAAAAA.Aarom:BAAALgAECgcJDAAAAA==.',
Ab='Abdltzach:BAAALgADCgYJBgABLgAECgYJEwADAAAAAA==.Abhark:BAAALgAECgYJCQAAAA==.',
Ac='Acemonk:BAAALgAECggJCQAAAA==.Achifee:BAAALgADCgkJHQAAAA==.',
Ad='Adragen:BAAALgAECgUJBQAAAA==.',
Ae='Aelyn:BAAALgADCgUJBQAAAA==.Aeni:BAAALgAECgQJBAAAAA==.',
Ai='Aingerfal:BAAALgAECgYJDwAAAA==.',
Ak='Akasori:BAABLgAECn8fAAIEAAgJ+hvwBgCBAgAEAAgJ+hvwBgCBAgAAAA==.Akira:BAAALgAECgYJDwAAAA==.Akorang:BAAALgADCgYJBgAAAA==.Akosori:BAAALgADCgMJAwABLgAECggJHwAEAPobAA==.',
Al='Alixx:BAAALgADCgQJBAAAAA==.Alkein:BAAALgAECgMJAwAAAA==.Allnaturale:BAAALgAECgEJAQAAAA==.Alîsonshammy:BAABLgAECn8cAAIFAAgJuSFvCADvAgAFAAgJuSFvCADvAgAAAA==.',
Am='Ambersulfr:BAAALgAECgYJDgAAAA==.Ammarianar:BAAALgAECgMJAwABLgAECgYJDAADAAAAAA==.Amrazz:BAABLgAECn8iAAMGAAkJFRjVAQBsAgAGAAkJFRjVAQBsAgAHAAIJ3wbsVgBjAAAAAA==.Amzey:BAEBLgAECn8hAAIIAAgJziCuBgBCAgAIAAgJziCuBgBCAgAAAA==.',
An='Anahata:BAAALgADCggJDAAAAA==.Anari:BAABLgAECn8WAAIJAAYJcgl3PwAcAQAJAAYJcgl3PwAcAQAAAA==.Andromeda:BAABLgAECn8hAAIKAAgJJBVBBgDCAQAKAAgJJBVBBgDCAQAAAA==.Anridel:BAAALgADCgIJAgAAAA==.Anyiaa:BAAALgADCgUJBQAAAA==.',
Ar='Arakis:BAAALgADCgcJEgABLgAECggJJwALANcfAA==.Arcacia:BAAALgADCgQJBAAAAA==.Aridillo:BAAALgAECgUJBwAAAA==.Arkanum:BAAALgAECgMJAwAAAA==.Artemai:BAAALgAECgYJCQAAAA==.',
As='Ashaka:BAAALgAECgMJBQAAAA==.Ashylarry:BAAALgADCgYJDQAAAA==.Askthedm:BAAALgAECgQJBAAAAA==.Astralus:BAABLgAECn8WAAIIAAgJ9hafXgAfAgAIAAgJ9hafXgAfAgAAAA==.Astramis:BAAALgAECgYJDwAAAA==.',
Av='Avioradoramo:BAAALgADCgEJAQAAAA==.',
Az='Azariah:BAAALgADCgQJBwAAAA==.',
Ba='Babybuu:BAAALgAECgYJDgAAAA==.Backlash:BAAALgAECgMJBQAAAA==.Balzhac:BAAALgAECgQJBQAAAA==.Bam:BAAALgADCgcJBwABLgAFFAUJDAAMAPwcAA==.Bambamcdn:BAAALgADCgEJAQAAAA==.',
Be='Beleaf:BAAALgAECgQJBAAAAA==.Bellmonte:BAAALgADCgUJBQABLgAECggJJwALANcfAA==.Berdron:BAABLgAECn8nAAIBAAgJtQWfIgASAQABAAgJtQWfIgASAQAAAA==.Bessy:BAAALgAECgYJBwAAAA==.Bexton:BAABLgAECn8XAAINAAcJCRcyFADJAQANAAcJCRcyFADJAQABLgAECggJEQADAAAAAA==.',
Bi='Bicchoi:BAABLgAECn8XAAIJAAcJ2h1sEgBiAgAJAAcJ2h1sEgBiAgAAAA==.Bigripper:BAAALgADCgcJBwAAAA==.',
Bl='Blackdot:BAABLgAECn8WAAMGAAgJRRMLBwCdAQAGAAgJRRMLBwCdAQAHAAQJiwJpUgB/AAAAAA==.Blazin:BAAALgAECgYJEwAAAA==.Bleddyn:BAAALgAECgYJBwAAAA==.Bledsmasher:BAAALgAECgYJDgAAAA==.Blinkss:BAAALgAECgEJAQAAAA==.Blouses:BAACLgAFFH8GAAIKAAMJexhQDwARAQAKAAMJexhQDwARAQAuAAQKfxwAAgoACQmrH/UEAFkDAAoACQmrH/UEAFkDAAAA.',
Bo='Bobowild:BAAALgAECgYJDQAAAA==.Bonbons:BAAALgAECgUJCgAAAA==.Boned:BAAALgAECgYJEQAAAA==.Bonemair:BAAALgAFFAIJBAABLgAFFAUJEAAOANkSAA==.Bonezey:BAAALgADCggJCAAAAA==.Bovityre:BAAALgAECgQJBQAAAA==.Bowjangles:BAAALgADCgEJAQAAAA==.Bowser:BAAALgAECgcJCQAAAA==.',
Bu='Bubbs:BAAALgADCgcJBwAAAA==.Buffnbeers:BAAALgADCgkJEQABLgAECggJHAAPAGQZAA==.Buffydemon:BAAALgADCgIJAgABLgAECgYJFgAQAMYaAA==.Buffypaladin:BAABLgAECn8WAAIQAAYJxhqpXADNAQAQAAYJxhqpXADNAQAAAA==.Buffyrogue:BAAALgAECgYJDAAAAA==.Buffyshaman:BAAALgADCgEJAQABLgAECgYJFgAQAMYaAA==.Bup:BAABLgAECn8ZAAMRAAYJfSO5DgBQAgARAAYJdCK5DgBQAgAGAAMJCBgEWADVAAAAAA==.Bups:BAAALgAECgEJAQAAAA==.Burning:BAAALgADCgYJCQAAAA==.Buttjuggles:BAAALgADCgcJCwAAAA==.',
Bw='Bwonurjor:BAAALgADCgUJBQAAAA==.',
Ca='Caldec:BAACLgAFFH8RAAISAAYJEiM3AQCqAQASAAYJEiM3AQCqAQAuAAQKfyIAAhIACQmcJnkAAO4DABIACQmcJnkAAO4DAAAA.Caldh:BAABLgAECn8VAAITAAYJQyGmMAA4AgATAAYJQyGmMAA4AgABLgAFFAYJEQASABIjAA==.Cardian:BAAALgADCgYJBgAAAA==.Casstiel:BAAALgAECgUJCAAAAA==.Catdog:BAAALgADCgYJDAABLgAECggJGwAUAPwbAA==.',
Ch='Chainizard:BAACLgAFFH8LAAIVAAQJMB5LAwBQAQAVAAQJMB5LAwBQAQAuAAQKfx4AAhUACAnGIG8GANwCABUACAnGIG8GANwCAAAA.Chainsmash:BAAALgAECgUJBQABLgAFFAQJCwAVADAeAA==.Chamonix:BAAALgAECgcJEQAAAA==.Cheeno:BAACLgAFFH8FAAITAAMJ8RvYGAAIAQATAAMJ8RvYGAAIAQAuAAQKfycAAhMACAl8JJUNABMDABMACAl8JJUNABMDAAAA.Chillyblinks:BAACLgAFFH8FAAIIAAMJuAhCFADxAAAIAAMJuAhCFADxAAAuAAQKfxoAAggACAmEHu4kAN8CAAgACAmEHu4kAN8CAAAA.Chillywings:BAAALgAECgIJAgABLgAFFAMJBQAIALgIAA==.Chojii:BAAALgADCgcJCAAAAA==.Choryrth:BAAALgAECgMJAwAAAA==.Chubbymuffin:BAAALgAECggJCAAAAA==.',
Ci='Circuitry:BAAALgAECgMJAwAAAA==.',
Co='Congruent:BAAALgAFFAEJAgABLgAFFAIJAgADAAAAAA==.Cootin:BAAALgADCgEJAgAAAA==.Coriolanus:BAAALgADCgUJBAAAAA==.Corvus:BAAALgADCggJDAAAAA==.',
Cr='Crane:BAABLgAECn8YAAIOAAgJOhjXHgALAgAOAAgJOhjXHgALAgAAAA==.Crelam:BAACLgAFFH8UAAIUAAYJOwZ3AABsAQAUAAYJOwZ3AABsAQAuAAQKfyMAAhQACQnEGoIEANICABQACQnEGoIEANICAAAA.Critz:BAAALgAECgQJBwAAAA==.Cronatherus:BAAALgAECgMJAwAAAA==.Cruentis:BAABLgAECn8bAAIWAAgJ2RjNAADUAQAWAAgJ2RjNAADUAQAAAA==.Crymsonroze:BAAALgAECgMJAwAAAA==.Crysus:BAAALgAECgYJEwAAAA==.',
Cu='Curruptor:BAAALgADCgIJAgAAAA==.',
Da='Dachiang:BAAALgAECgEJAQAAAA==.Damarisalynn:BAAALgADCgMJAwAAAA==.Dangus:BAABLgAECn8YAAQJAAgJyhXCBACxAQAJAAgJyhXCBACxAQAOAAIJLQhbeQBeAAAXAAEJlwcKbQApAAAAAA==.Danifarian:BAABLgAECn8eAAMLAAgJ9BcIDQAKAgALAAgJ/xQIDQAKAgAYAAYJexPxKAB2AQABLgAFFAgJHAADAAAAAA==.Dankeydemon:BAAALgADCgMJAwAAAA==.Danthrox:BAAALgADCgEJAQAAAA==.Darthneepis:BAAALgAECgcJDgAAAA==.Darthplot:BAAALgADCgMJAwAAAA==.Darwin:BAAALgAECgYJDgAAAA==.Dasmoodhayn:BAAALgAECgQJBAAAAA==.Dawnglaive:BAAALgAECgMJAwAAAA==.Dayo:BAABLgAECn8XAAIQAAYJOiWsKACCAgAQAAYJOiWsKACCAgAAAA==.',
De='Dethkløk:BAAALgAECgUJBgAAAA==.',
Di='Dibstrum:BAAALgAECgQJBAAAAA==.Dimaa:BAAALgAECgkJBwAAAA==.Dixqt:BAAALgAECgQJDAAAAA==.',
Dj='Djinn:BAAALgAECgIJAgAAAA==.',
Do='Dogbear:BAAALgADCgIJAgAAAA==.Dogfight:BAACLgAFFH8KAAISAAMJIRRmDgADAQASAAMJIRRmDgADAQAuAAQKfxoAAhIACAkAIy4ZAOUCABIACAkAIy4ZAOUCAAAA.Doilookfatou:BAAALgAECgYJCgAAAA==.Doopy:BAAALgADCgMJAwAAAA==.',
Dr='Draedawn:BAAALgADCgQJBAAAAA==.Dragonhide:BAABLgAECn8XAAIQAAgJXQiDgwBzAQAQAAgJXQiDgwBzAQAAAA==.Drailzx:BAAALgAECgYJBgAAAA==.Drakelle:BAAALgADCgIJAgAAAA==.Draxus:BAAALgAECgQJBwAAAA==.Drbigsbie:BAAALgAECgYJCgAAAA==.Dresel:BAACLgAFFH8RAAMZAAYJTiIoAAD4AQAZAAUJ6SQoAAD4AQAaAAMJ9A4mBwBjAAAuAAQKfyEABBkACQnLJj4AAOgDABkACQnLJj4AAOgDABoABwmrGA4yAKUBABsAAgn9BfIpAGEAAAAA.Drewpeebahlz:BAAALgADCgYJDAABLgAECgcJIQAZAOAgAA==.Drezell:BAAALgADCgcJBwABLgAFFAYJEQAZAE4iAA==.Druidickhal:BAACLgAFFH8LAAMcAAMJIhomBwD7AAAcAAMJIhomBwD7AAAdAAMJDQxFDwDsAAAuAAQKfxkAAxwACAlUHGEqAAgCABwACAlUHGEqAAgCAB0ABQlfIvguAI4BAAAA.Druindabs:BAAALgADCgUJBQAAAA==.Drybussy:BAAALgAECgMJAwAAAA==.',
Du='Dunarith:BAAALgADCgMJAwAAAA==.Dunkel:BAAALgADCgUJBQAAAA==.',
Dw='Dwarvenlight:BAAALgAECgEJAQAAAA==.',
Dy='Dyami:BAABLgAECn8aAAMZAAgJOxrJCQDMAQAZAAcJQBvJCQDMAQAaAAQJUhmfRQA+AQAAAA==.Dynas:BAABLgAECn8YAAMRAAcJdxApJgBkAQARAAYJ/REpJgBkAQAGAAYJ4grFTgD9AAAAAA==.',
Ea='Earthcake:BAACLgAFFH8FAAIFAAMJUw+BBwDcAAAFAAMJUw+BBwDcAAAuAAQKfygAAx4ACAkMH6cBAGgCAB4ACAkMH6cBAGgCAAUAAQmLBdqnACcAAAAA.',
Ed='Eddiechi:BAAALgADCgYJBgABLgAFFAYJEAASAGQXAA==.Eddiedecay:BAAALgAECgUJBQABLgAFFAYJEAASAGQXAA==.Eddielich:BAACLgAFFH8QAAMSAAYJZBdJAgDyAQASAAYJZBdJAgDyAQAfAAEJAACXDQAAAAAuAAQKfyMAAxIACQk1I6AHAGMDABIACQm+IqAHAGMDAB8AAwk4GGksANsAAAAA.Eddiewar:BAAALgAECgYJDwABLgAFFAYJEAASAGQXAA==.',
Eg='Eggfumonk:BAAALgAECgMJAwAAAA==.',
El='Elfpen:BAAALgADCgkJCwAAAA==.',
En='Ents:BAAALgAECgYJDQAAAA==.',
Er='Erragal:BAAALgADCgcJAgAAAA==.Eryunes:BAAALgAECgEJAQAAAA==.',
Et='Et:BAAALgAFFAMJAwABLgAFFAUJAgADAAAAAA==.',
Eu='Euthariel:BAAALgAECgYJDAAAAA==.Euthindor:BAAALgADCgQJBAAAAA==.',
Ev='Evilwench:BAABLgAECn8bAAIHAAcJSRHMDQAYAQAHAAcJSRHMDQAYAQAAAA==.',
Fa='Faexi:BAAALgADCgMJAgAAAA==.Falek:BAAALgADCgUJBQAAAA==.Favii:BAAALgADCggJEgAAAA==.',
Fe='Feefiefoéfum:BAAALgADCgkJGQAAAA==.Felstórm:BAAALgADCgcJBwAAAA==.Felurián:BAAALgAECgYJCQAAAA==.Fexli:BAAALgADCggJBAAAAA==.',
Fi='Fiber:BAAALgADCgUJBgAAAA==.Fireteeth:BAAALgAECgEJAgAAAA==.Fizc:BAAALgADCgEJAQAAAA==.',
Fl='Flojo:BAAALgAFFAEJAQAAAA==.',
Fo='Folklore:BAAALgAECgcJEwAAAA==.Forbidi:BAAALgAECgMJBgAAAA==.',
Fr='Freaky:BAAALgAECgUJBgAAAA==.Frostytute:BAAALgAECgUJCgAAAA==.Frozown:BAAALgAECgYJCgAAAA==.Fruits:BAAALgAECgYJDwAAAA==.',
Fu='Fumanchu:BAAALgADCgMJAwAAAA==.Funfanfare:BAABLgAECn8UAAIgAAYJfhrABQDLAQAgAAYJfhrABQDLAQAAAA==.',
Fy='Fyvern:BAAALgADCgUJBQAAAA==.',
['Fò']='Fòrlorn:BAAALgADCgcJCAAAAA==.',
['Fö']='Fölktergeist:BAAALgAECgIJAgAAAA==.',
Ga='Gaea:BAAALgADCgEJAQAAAA==.Galaeline:BAAALgADCgkJDQAAAA==.Galram:BAABLgAECn8WAAIbAAYJCRbfDwDFAQAbAAYJCRbfDwDFAQABLgAFFAYJFAAUADsGAA==.Gargingoyles:BAABLgAECn8iAAISAAcJsiTyGADmAgASAAcJsiTyGADmAgAAAA==.Garlicbred:BAAALgAECgIJAgABLgAECggJHAAFALkhAA==.Gartholo:BAAALgAECgYJBgAAAA==.Garunah:BAAALgAECgQJBQAAAA==.',
Gi='Gimpwithmilk:BAABLgAECn8VAAIcAAcJiAfDbgAJAQAcAAcJiAfDbgAJAQAAAA==.Giselee:BAAALgADCgEJAQAAAA==.Gisellina:BAABLgAECn8ZAAIZAAcJkhoMKAAYAgAZAAcJkhoMKAAYAgAAAA==.Gizzbos:BAAALgADCgUJBQAAAA==.',
Gl='Gladiatorz:BAAALgAECgcJEgABLgAECggJFwAQAF0IAA==.Glimmair:BAAALgAECgYJBgABLgAFFAUJEAAOANkSAA==.Glimmer:BAAALgAECgYJEQAAAA==.Glo:BAAALgADCggJBAAAAA==.',
Go='Gokuz:BAAALgAECgYJCAAAAA==.Goo:BAAALgAECgQJBAAAAA==.Gorbstrasz:BAAALgADCgEJAQAAAA==.',
Gr='Gregorz:BAAALgADCggJBAAAAA==.Greyanna:BAAALgAECgMJAwAAAA==.Grilka:BAAALgAECgEJAQABLgAECgEJAQADAAAAAA==.Grimmnír:BAAALgAECgMJAwABLgAFFAYJFAAVAB4ZAA==.Grimrath:BAAALgAECgYJDwAAAA==.Gromthrall:BAAALgAECgIJAgAAAA==.Grumpydik:BAAALgADCgkJCQAAAA==.Grumpzilla:BAAALgAECgYJEQAAAA==.',
Gu='Gumdrops:BAAALgAECgUJCgAAAA==.Gurglem:BAAALgADCgEJAQAAAA==.Gurthrot:BAABLgAECn8aAAISAAgJMRh9RgAhAgASAAgJMRh9RgAhAgAAAA==.',
Gw='Gworp:BAAALgADCgEJAQAAAA==.Gwynhwyfar:BAAALgAECgYJDwAAAA==.',
['Gü']='Güanentá:BAAALgAECgMJAwAAAA==.',
Hb='Hbhealthen:BAACLgAFFH8UAAIVAAYJHhkQAQDPAQAVAAYJHhkQAQDPAQAuAAQKfzIAAhUACQmCI38BAG8DABUACQmCI38BAG8DAAAA.Hbheathend:BAAALgAECgQJCAABLgAFFAYJFAAVAB4ZAA==.',
He='Heavie:BAAALgADCgYJCAAAAA==.Hellhore:BAAALgADCgYJDAAAAA==.',
Hi='Highego:BAAALgAECgEJAQAAAA==.Hitmen:BAAALgAECgcJAQAAAA==.Hitta:BAAALgAECgMJBAABLgAECgQJBwADAAAAAA==.',
Ho='Hobodruid:BAAALgAECgEJAQAAAA==.Holdenc:BAAALgAECgYJBgABLgAECgYJCAADAAAAAA==.Holyrandy:BAABLgAECn8fAAIQAAgJsxGIEQCXAQAQAAgJsxGIEQCXAQAAAA==.Hotzalot:BAAALgAECgYJBgAAAA==.Houla:BAAALgAECgQJBAAAAA==.Howard:BAAALgAECgYJDAAAAA==.',
Hu='Huatli:BAAALgADCgYJBgAAAA==.Hurcolo:BAAALgAECgEJAgAAAA==.Huulotta:BAAALgADCgIJAgAAAA==.',
Ia='Ianth:BAAALgAECgUJBgAAAA==.',
Ib='Ibearprofen:BAAALgAECgUJDgAAAA==.Iblees:BAAALgAECgcJDgAAAA==.',
Ic='Ichthyosis:BAAALgAECgYJDAAAAA==.Icë:BAAALgAECgYJBwAAAA==.',
Id='Idtrapdat:BAAALgAECgEJAQABLgAECgIJCAADAAAAAA==.',
Il='Illidarya:BAAALgADCgIJAgAAAA==.Illyana:BAABLgAECn8UAAIfAAcJLSEeDgArAgAfAAcJLSEeDgArAgAAAA==.Ilovetofish:BAAALgAECgEJAQAAAA==.Ilse:BAAALgAECgcJEwAAAA==.',
Im='Imagined:BAABLgAECn8VAAIIAAYJvhrpcwDrAQAIAAYJvhrpcwDrAQABLgAECggJHgAVAH0aAA==.',
In='Indihunter:BAAALgAECgEJAQAAAA==.Infidelity:BAAALgADCgUJBQABLgAECgYJDAADAAAAAA==.',
Is='Iskhan:BAAALgADCgkJCQABLgAECgQJBAADAAAAAA==.',
It='Itsmxke:BAABLgAECn8VAAIQAAYJXiHcDADIAQAQAAYJXiHcDADIAQAAAA==.',
Iv='Ivank:BAAALgAECgYJEwAAAA==.Ivannalot:BAAALgADCgkJGwAAAA==.',
Ja='Jabunken:BAACLgAFFH8GAAIhAAMJ3hWVDgDsAAAhAAMJ3hWVDgDsAAAuAAQKfx0AAyEACQmGIfcDADEDACEACQmGIfcDADEDABAABAn+ESvqALsAAAAA.Jackiechaan:BAAALgADCgkJFAAAAA==.Jage:BAAALgAECgcJEQAAAA==.Jakkul:BAAALgAECgYJBwAAAA==.Jarsham:BAAALgAECgUJCwAAAA==.Jaràdan:BAAALgAECgIJAgABLgAFFAEJAQADAAAAAA==.',
Je='Jeff:BAAALgAECgkJEgAAAA==.',
Ji='Jiannaa:BAABLgAECn8kAAIGAAgJvh97AgBIAgAGAAgJvh97AgBIAgAAAA==.Jitzul:BAAALgADCgEJAQAAAA==.',
Jl='Jl:BAAALgAECgEJAQABLgAFFAUJAgADAAAAAA==.',
Jo='Johnnyderp:BAAALgAECgIJAgAAAA==.Jook:BAAALgAECgcJCwAAAA==.Joran:BAAALgADCgkJFwAAAA==.',
Ju='Justmage:BAAALgADCgEJAQABLgAECgMJAwADAAAAAA==.Justmonk:BAAALgAECgMJAwAAAA==.',
Jw='Jwrs:BAAALgADCgYJBgAAAA==.',
Jy='Jyaki:BAAALgAECgEJAQAAAA==.',
Ka='Kaelana:BAABLgAECn8YAAIGAAgJ1hs+CgCqAgAGAAgJ1hs+CgCqAgAAAA==.Kahlua:BAABLgAECn8fAAIZAAgJcRblCgC7AQAZAAgJcRblCgC7AQAAAA==.Kailan:BAAALgAECgYJDgABLgAECggJIAAHAEcaAA==.Kailani:BAABLgAECn8XAAMcAAgJSAjQbgAJAQAcAAcJYAXQbgAJAQAdAAUJBge5VQDNAAAAAA==.Kaiserroll:BAAALgAECgEJAQAAAA==.Kaldro:BAAALgADCgkJFAAAAA==.Kaly:BAABLgAECn8ZAAIOAAgJegdnCgBIAQAOAAgJegdnCgBIAQAAAA==.Karador:BAAALgAECgEJAQAAAA==.Kathry:BAAALgADCgkJGwAAAA==.',
Kc='Kcid:BAAALgAECgYJBwAAAA==.',
Ke='Kedibaba:BAAALgAECgYJCwAAAA==.Keeiron:BAAALgADCgYJBgABLgAECgMJAwADAAAAAA==.Keepdreaming:BAABLgAECn8ZAAIcAAgJ9xBCDgBxAQAcAAgJ9xBCDgBxAQAAAA==.Kellane:BAAALgAECgMJAwAAAA==.Keybricker:BAAALgAECgIJAgABLgAECggJHAAPAGQZAA==.Keymebrah:BAABLgAECn8gAAIIAAgJXxzpLgC2AgAIAAgJXxzpLgC2AgAAAA==.',
Kh='Khaera:BAAALgADCgQJBAAAAA==.Khansi:BAAALgADCgUJBQAAAA==.',
Ki='Killeh:BAAALgADCggJCwAAAA==.',
Kl='Kleiya:BAABLgAECn8eAAMVAAgJfRp8AQBGAgAVAAgJfRp8AQBGAgALAAEJ+hgRCABUAAAAAA==.',
Ko='Korda:BAAALgADCgMJAwAAAA==.Korinä:BAAALgAECgYJEAAAAA==.Korveen:BAABLgAECn8hAAIHAAgJHAxsBwCEAQAHAAgJHAxsBwCEAQAAAA==.Kosh:BAAALgADCggJBAAAAA==.Koyra:BAACLgAFFH8QAAMLAAYJ5yAdAAAmAgALAAUJYiQdAAAmAgAYAAEJ/BKeDwBjAAAuAAQKfygAAwsACQm8JSEAAOwDAAsACQm8JSEAAOwDABgABQnOHFshALQBAAAA.',
Kr='Krimzin:BAAALgADCgEJAQABLgAFFAIJBQAQAFAWAA==.Krump:BAABLgAECn8VAAINAAgJpRApFwCfAQANAAgJpRApFwCfAQAAAA==.Krëyâdrón:BAAALgAECgIJAgAAAA==.',
Ku='Kubwa:BAAALgAECgMJAwAAAA==.Kungfugimp:BAAALgADCgYJBgAAAA==.Kurral:BAACLgAFFH8JAAIdAAUJsQXADAAWAQAdAAUJsQXADAAWAQAuAAQKfyMAAh0ACQkkG7sMAMwCAB0ACQkkG7sMAMwCAAAA.Kurralagos:BAABLgAECn8WAAMLAAYJcgrBIAAnAQALAAYJcgrBIAAnAQAVAAMJVAKJPwBuAAABLgAFFAUJCQAdALEFAA==.Kurstina:BAAALgAECgEJAQAAAA==.Kurtîmus:BAAALgAECgQJBwAAAA==.Kuznetsov:BAAALgADCgYJBgABLgAECgkJJwAdABcbAA==.Kuzushi:BAAALgADCgkJDAAAAA==.',
Ky='Kyramus:BAAALgAECgYJDwAAAA==.',
La='Laconia:BAABLgAECn8nAAMLAAgJ1x91AwDmAgALAAgJ1x91AwDmAgAYAAEJDA7AYwAvAAAAAA==.Larox:BAAALgADCgYJCQAAAA==.Lattsatnar:BAAALgAECgYJDAAAAA==.',
Le='Lennel:BAAALgAECgQJBAAAAA==.Leøn:BAAALgAECgYJCwAAAA==.',
Li='Lightbrite:BAAALgADCgcJCAAAAA==.Lightstorm:BAAALgAECgMJBgAAAA==.Lilarri:BAAALgAECgEJAQABLgAECgcJCQADAAAAAA==.Lilsnick:BAAALgADCgkJFwABLgAECgYJCAADAAAAAA==.Lilyillidari:BAAALgAECgYJEQAAAA==.Lizardlemons:BAAALgAECgYJEAAAAA==.',
Ll='Llanthyl:BAAALgAECgYJCQAAAA==.',
Lo='Locosmexy:BAAALgAECgQJBAABLgAECgYJBgADAAAAAA==.Lou:BAAALgAECgEJAgAAAA==.Lovia:BAAALgADCgUJBQAAAA==.Lowdps:BAAALgAFFAEJAgABLgAFFAQJCQAaACsRAA==.',
Lu='Luithica:BAAALgADCgUJBQAAAA==.Lunafalia:BAABLgAECn8dAAIIAAgJxRPGFgCNAQAIAAgJxRPGFgCNAQAAAA==.Lurosa:BAACLgAFFH8LAAIcAAQJghrrBAA0AQAcAAQJghrrBAA0AQAuAAQKfxoABBwACAlCJDAIAAoDABwACAlCJDAIAAoDAB0AAglNEwZoAIEAACIAAQmzIQEoAF4AAAAA.Luxeria:BAABLgAECn8WAAIQAAYJDR/xTAD8AQAQAAYJDR/xTAD8AQAAAA==.',
Lz='Lz:BAAALgAFFAUJAgAAAA==.',
['Lí']='Lízard:BAAALgAECgQJBAAAAA==.',
['Lî']='Lîlydan:BAAALgAECgMJAwAAAA==.',
Ma='Macready:BAACLgAFFH8FAAINAAIJNBUgCwCVAAANAAIJNBUgCwCVAAAuAAQKfx0AAg0ACAnSHyYGANECAA0ACAnSHyYGANECAAAA.Madmimm:BAAALgADCgMJAwAAAA==.Maerith:BAAALgAECgYJEAAAAA==.Magenin:BAAALgADCgYJAwAAAA==.Mahmage:BAACLgAFFH8FAAIIAAMJJh8+FwC+AAAIAAMJJh8+FwC+AAAuAAQKfyQAAggACQmgI1ILAGkDAAgACQmgI1ILAGkDAAAA.Mairbear:BAAALgAECgYJBgABLgAFFAUJEAAOANkSAA==.Mairiachi:BAACLgAFFH8QAAIOAAUJ2RJcAQCRAQAOAAUJ2RJcAQCRAQAuAAQKfyMAAg4ACQlnI84DAFIDAA4ACQlnI84DAFIDAAAA.Maloa:BAAALgAECgQJAgAAAA==.Marllowe:BAAALgADCgcJBwABLgAECggJLAAZANofAA==.Marload:BAABLgAECn8sAAIZAAgJ2h8RDADhAgAZAAgJ2h8RDADhAgAAAA==.Mathy:BAABLgAECn8VAAMFAAgJbxpjIgARAgAFAAcJpBljIgARAgAUAAgJmxaCAgDJAQAAAA==.Mazaker:BAAALgADCgEJAQAAAA==.',
Me='Mearis:BAAALgAECgIJAgABLgAECggJHgAVAH0aAA==.Melath:BAAALgADCgkJEAAAAA==.Memesarecool:BAAALgADCgQJCQAAAA==.Meñtat:BAAALgAECgYJDgAAAA==.',
Mi='Michael:BAAALgAECgQJBAAAAA==.Midletons:BAAALgAECgYJCAAAAA==.Midran:BAABLgAECn8VAAIbAAgJJRaoCQBEAgAbAAgJJRaoCQBEAgAAAA==.Minbari:BAAALgADCgQJCgABLgADCggJBAADAAAAAA==.Minerva:BAAALgADCgMJAwAAAA==.Minttea:BAAALgAECgYJBgABLgAFFAIJBQAcAFIbAA==.Misfirë:BAAALgAECgYJCgAAAA==.',
Mo='Mojó:BAAALgAECgYJEAAAAA==.Momenta:BAAALgADCgEJAQAAAA==.Moobubble:BAAALgADCgEJAQAAAA==.Moogul:BAAALgADCgUJBQAAAA==.Moonanoke:BAAALgADCgYJBgAAAA==.Moorawr:BAAALgADCgYJBgAAAA==.Moovoker:BAABLgAECn8XAAMYAAcJ4R+XAwDuAQAYAAYJnhyXAwDuAQALAAMJFSGEIgAWAQAAAA==.Mordran:BAAALgADCgMJAwAAAA==.Morseques:BAABLgAECn8dAAISAAgJ0B/wBgATAgASAAgJ0B/wBgATAgAAAA==.Mozi:BAAALgAECgUJEwAAAA==.',
Mu='Muffins:BAAALgAECgUJCAAAAA==.Muggy:BAACLgAFFH8IAAMSAAQJvRowHgAnAQASAAMJvRowHgAnAQAfAAEJAADvEgBbAAAuAAQKfzcAAxIACAmTJYEBAMECABIACAmTJYEBAMECAB8ABAmXGN8jACIBAAAA.Murphy:BAAALgADCgUJBQAAAA==.Mushrodazz:BAAALgAECgQJBwAAAA==.',
Mx='Mxke:BAAALgADCgQJBAABLgAECgYJFQAQAF4hAA==.',
My='Mysts:BAAALgAECgYJEgABLgAFFAYJFAAVANcmAA==.',
Na='Narama:BAACLgAFFH8JAAMBAAUJtQUECgAoAQABAAQJtQUECgAoAQAjAAEJAABWBwBIAAAuAAQKfyIAAgEACQnZGE0fAJwCAAEACQnZGE0fAJwCAAAA.Naturaljuice:BAAALgADCgcJBwABLgAECgUJBwADAAAAAA==.',
Ne='Neverlucky:BAAALgAECgEJAQAAAA==.',
Ni='Ninæ:BAAALgAECgYJBwABLgAFFAQJCwAcALsTAA==.Nitewïng:BAAALgADCgUJBgAAAA==.',
No='Nootao:BAABLgAECn8aAAIJAAcJmCSCEAB4AgAJAAcJmCSCEAB4AgAAAA==.Nootvoker:BAAALgAECgUJCAABLgAECgcJGgAJAJgkAA==.Noraline:BAAALgAECgEJAgAAAA==.Normac:BAAALgADCgYJCwAAAA==.',
Ny='Nyoz:BAAALgAECgMJAwAAAA==.Nyxxadra:BAABLgAECn8XAAIBAAcJcQ6TFABrAQABAAcJcQ6TFABrAQAAAA==.',
Ol='Oliaa:BAAALgADCgUJBQAAAA==.',
Om='Omegadeed:BAABLgAECn8dAAIBAAgJQgzqXgCsAQABAAgJQgzqXgCsAQAAAA==.',
On='Onne:BAAALgADCggJCgAAAA==.',
Or='Oraculus:BAACLgAFFH8RAAIcAAYJ/w5xAgCIAQAcAAYJ/w5xAgCIAQAuAAQKfyMAAhwACQkaFdUgAD0CABwACQkaFdUgAD0CAAAA.Orchunter:BAAALgADCgcJEgAAAA==.Orcinus:BAAALgAECgUJCwAAAA==.Orcward:BAAALgADCgcJDgABLgAECgcJIQAZAOAgAA==.Ordinem:BAABLgAECn8eAAIIAAgJaR2qCQAPAgAIAAgJaR2qCQAPAgAAAA==.Originality:BAAALgAECgMJBgAAAA==.Orlandodoom:BAAALgADCgMJAwAAAA==.Orvar:BAABLgAECn8hAAQZAAcJ4CAKBgAQAgAZAAcJ4CAKBgAQAgAaAAUJDhhOQwBJAQAbAAEJ4wH5MgAkAAAAAA==.',
Pa='Pakaru:BAABLgAECn8ZAAIQAAgJXx5wNwBFAgAQAAgJXx5wNwBFAgAAAA==.Palpapeen:BAAALgAECgEJAQAAAA==.Pam:BAACLgAFFH8MAAMMAAUJ/BwBAgB4AQAMAAUJ/BwBAgB4AQATAAIJwQoqLACVAAAuAAQKfysAAwwACAlXJkACAHEDAAwACAlXJkACAHEDABMABgm/HGRFAN4BAAAA.Panpanpan:BAAALgAECgYJDQAAAA==.',
Pe='Penry:BAAALgAECgEJAQAAAA==.Peorä:BAAALgAECgYJEAAAAA==.Peremo:BAABLgAECn8lAAISAAkJDyGhBwBjAwASAAkJDyGhBwBjAwAAAA==.Perfectdark:BAACLgAFFH8TAAITAAYJphn4AADLAQATAAYJphn4AADLAQAuAAQKfyAAAhMACQkCIo0EAH4DABMACQkCIo0EAH4DAAAA.Perse:BAAALgAECgYJCwAAAA==.',
Ph='Phutz:BAAALgADCgEJAQAAAA==.',
Pi='Pickles:BAAALgAFFAIJAwAAAA==.Pieper:BAAALgADCggJBAAAAA==.Pipa:BAABLgAECn8hAAIFAAgJQSG+AQCZAgAFAAgJQSG+AQCZAgAAAA==.',
Pl='Plagueis:BAAALgADCgYJCwABLgAECggJJwALANcfAA==.Plaguexrat:BAAALgADCgkJFwAAAA==.Plooptwo:BAAALgAECgYJDgAAAA==.',
Po='Poacher:BAAALgAECgQJBQAAAA==.Poogli:BAAALgAECgYJDAAAAA==.Pooky:BAAALgAECgMJBAAAAA==.Poppapally:BAAALgAECgEJAQAAAA==.Porque:BAABLgAECn8hAAMIAAgJ6hu7NwCWAgAIAAgJ6hu7NwCWAgAgAAIJyAtnFgBnAAAAAA==.Powar:BAAALgADCgQJBAAAAA==.',
Pr='Protolennel:BAAALgADCgkJHQABLgAECgQJBAADAAAAAA==.Provence:BAAALgAECgMJBAAAAA==.',
Py='Pyreynna:BAAALgAECgYJDgAAAA==.',
Qs='Qsteve:BAAALgADCgYJAwAAAA==.',
Qu='Queso:BAAALgADCgYJBgABLgAFFAMJBQATAPEbAA==.Quinmora:BAAALgADCgcJDgAAAA==.',
Ra='Ragarn:BAAALgADCgMJAwAAAA==.Ralnorin:BAAALgAECgQJCQAAAA==.Rarren:BAAALgADCgcJEAAAAA==.Raschild:BAAALgAECgUJCgAAAA==.',
Re='Realfrojd:BAABLgAECn8YAAIfAAgJ2w0jCAARAQAfAAgJ2w0jCAARAQAAAA==.Reallybigdk:BAAALgADCgIJAgAAAA==.Regginunchuk:BAAALgAECgYJEgAAAA==.Rejownation:BAAALgAECgcJEAAAAA==.Releronastus:BAAALgAECgQJBQAAAA==.Relief:BAABLgAECn8XAAMcAAgJ3SPKBwAQAwAcAAgJ3SPKBwAQAwAdAAcJghlrCABsAQAAAA==.Rextallion:BAABLgAECn8YAAIQAAgJlxo2CwDeAQAQAAgJlxo2CwDeAQAAAA==.Reyson:BAABLgAECn8hAAMIAAgJkhalEQC1AQAIAAgJMhalEQC1AQAgAAEJASA2GwA/AAAAAA==.',
Rh='Rhinoe:BAAALgAECgEJAQAAAA==.Rholden:BAAALgADCgMJAwAAAA==.Rhun:BAAALgADCgQJBAAAAA==.Rhunon:BAAALgAECgkJEgAAAA==.',
Ri='Ridor:BAAALgAECgIJAgAAAA==.Rinslaughter:BAABLgAECn8dAAISAAgJSQ6MHQAvAQASAAgJSQ6MHQAvAQAAAA==.Rinthia:BAABLgAECn8gAAIHAAgJRxpDBQC+AQAHAAgJRxpDBQC+AQAAAA==.Ripyeet:BAACLgAFFH8HAAIQAAMJthkQFAAHAQAQAAMJthkQFAAHAQAuAAQKfyQAAhAACQmgI8EIAEwDABAACQmgI8EIAEwDAAAA.',
Ro='Robinhood:BAAALgAECgcJBwABLgAFFAMJBgAKAHsYAA==.Rolden:BAAALgAECgQJDQAAAA==.Ron:BAAALgADCgUJBQAAAA==.',
Ru='Ruffaf:BAAALgADCgEJAQAAAA==.Rukaji:BAAALgAECgcJDwAAAA==.',
Ry='Ryuuter:BAAALgAECgUJBQAAAA==.',
['Rå']='Rå:BAAALgADCgUJBQAAAA==.Rågè:BAAALgAECgYJDAAAAA==.',
Sa='Saebelle:BAAALgADCggJEwAAAA==.Saetheline:BAABLgAECn8ZAAIKAAgJ/wx0CgB4AQAKAAgJ/wx0CgB4AQAAAA==.Sandybeans:BAAALgADCgYJCQAAAA==.Sanko:BAAALgADCgEJAQAAAA==.Sarkang:BAAALgADCgkJHAAAAA==.',
Sc='Schkate:BAAALgAECgYJDAAAAA==.Schutze:BAACLgAFFH8LAAIbAAQJDhY6AQBkAQAbAAQJDhY6AQBkAQAuAAQKfxkAAxsACAnxI0MDAPcCABsACAnxI0MDAPcCABoABAmyDlFiALcAAAAA.Scorn:BAAALgADCgMJAwAAAA==.Scrammbles:BAAALgAECgUJBgAAAA==.Scråmmbles:BAAALgAECgEJAQAAAA==.',
Sd='Sdadfeg:BAABLgAECn8dAAIUAAgJuSFWAwD9AgAUAAgJuSFWAwD9AgAAAA==.',
Se='Selenagomez:BAABLgAFFH8FAAIJAAMJlA1nBQCrAAAJAAMJlA1nBQCrAAAAAA==.Selia:BAAALgAECgYJDwAAAA==.Senlorin:BAAALgAECgMJAwAAAA==.Sephroth:BAAALgAECgUJBwAAAA==.',
Sh='Shabobado:BAAALgAECgYJEQAAAA==.Shadowleaf:BAAALgADCgkJEgAAAA==.Shatoya:BAAALgADCggJFQAAAA==.Shawoman:BAAALgAECgEJAQAAAA==.Shayluh:BAAALgADCgMJAwAAAA==.Shedoo:BAAALgAECgYJCQAAAA==.Shhum:BAAALgAECgMJAwAAAA==.Shinokage:BAAALgAECgIJAgAAAA==.Shinrei:BAAALgAECgYJBwAAAA==.Shumazing:BAAALgADCgYJBgABLgAECgYJBgADAAAAAA==.Shuten:BAAALgAECgEJAQAAAA==.Shxdow:BAAALgAECgQJBAAAAA==.Shìlô:BAAALgAECgQJBgAAAA==.',
Si='Sibble:BAAALgADCgkJCQAAAA==.Silbanuz:BAAALgAECgcJCgAAAA==.Simplejakk:BAAALgADCgYJCwAAAA==.Sinterklaas:BAABLgAECn8fAAMFAAgJQhHvCAC2AQAFAAgJQhHvCAC2AQAeAAYJ+gbKUwD2AAAAAA==.Siqma:BAAALgAECgUJBgAAAA==.',
Sj='Sj:BAAALgAECgEJAQAAAA==.',
Sl='Slapfurr:BAAALgAECgEJAgAAAA==.Slark:BAABLgAECn8hAAMXAAgJRxgVBgC0AQAXAAgJRxgVBgC0AQAJAAEJGwKDJgAcAAAAAA==.Slawth:BAAALgADCgcJAgAAAA==.Slayermonde:BAAALgADCggJBAAAAA==.Slimjerry:BAAALgAECgEJAQAAAA==.',
Sm='Smexydemon:BAAALgAECgMJAwABLgAECgYJBgADAAAAAA==.Smexydubs:BAAALgAECgYJBgAAAA==.Smexyexpress:BAAALgAECgUJBQABLgAECgYJBgADAAAAAA==.Smexytimes:BAAALgAECgEJAQABLgAECgYJBgADAAAAAA==.Smeyplus:BAACLgAFFH8TAAIQAAYJ9hl5AADJAQAQAAYJ9hl5AADJAQAuAAQKfyMAAhAACQk1JAIHAGADABAACQk1JAIHAGADAAAA.Smokincrayon:BAAALgAECgcJAwAAAA==.',
Sn='Snickeris:BAAALgAECgYJCAAAAA==.Snofawl:BAABLgAECn8nAAIYAAgJsxUdFgAnAgAYAAgJsxUdFgAnAgAAAA==.Snoranir:BAABLgAECn8WAAUiAAYJhxa4EwAzAQAiAAUJ2BS4EwAzAQAcAAYJIRx0EwAvAQAEAAIJahuoJgCaAAAdAAIJAwp/dQBNAAAAAA==.',
So='Sovereign:BAABLgAFFH8MAAMLAAUJpBcxAQC0AQALAAUJYBUxAQC0AQAYAAMJcxQpBwAPAQAAAA==.',
Sp='Spanfrontals:BAABLgAECn8cAAMPAAgJZBnfCgC1AQATAAcJ9xgXRADjAQAPAAYJtBrfCgC1AQAAAA==.Spiko:BAAALgAECgUJBQABLgAECgYJCAADAAAAAA==.Spillthetea:BAAALgADCgUJCAAAAA==.Spite:BAABLgAECn8cAAIBAAgJLBSBRAD+AQABAAgJLBSBRAD+AQAAAA==.',
Sq='Squidd:BAAALgAECgMJAwAAAA==.',
St='Stars:BAAALgAECgIJCAAAAA==.Steakshot:BAAALgADCgIJAgAAAA==.Steelcow:BAAALgADCgEJAQAAAA==.Stevengotwow:BAAALgAECgYJBgAAAA==.Stryjix:BAAALgADCgQJBAAAAA==.Stuhmp:BAAALgADCgEJAQAAAA==.',
Su='Sunhorn:BAAALgADCgIJAgAAAA==.Sunset:BAAALgAECgQJBAAAAA==.Sureno:BAAALgAECgYJCwAAAA==.Suslord:BAAALgADCgcJCgAAAA==.',
Sx='Sxybznitch:BAAALgAECgYJCgAAAA==.Sxyhealz:BAABLgAECn8dAAIGAAgJSBWHIADeAQAGAAgJSBWHIADeAQAAAA==.',
Sy='Syntherien:BAAALgADCgEJAQAAAA==.',
Sz='Szandöra:BAABLgAECn8gAAIHAAkJQgMZFgCfAAAHAAkJQgMZFgCfAAAAAA==.',
['Sü']='Süture:BAABLgAECn8eAAIkAAkJkgNcSQDeAAAkAAkJkgNcSQDeAAAAAA==.',
Ta='Taco:BAAALgAECgUJBQAAAA==.Taggaz:BAAALgAECgYJCAAAAA==.Tandrelia:BAAALgAECgEJAQAAAA==.Tanndari:BAAALgADCgcJFQAAAA==.Tarragon:BAAALgAECgEJAwAAAA==.Tartare:BAAALgAECgYJDwAAAA==.Tashiice:BAAALgADCgYJBgABLgAECgcJGQAZAJIaAA==.',
Te='Teriheals:BAAALgADCgkJCQAAAA==.Terishon:BAAALgAECgQJBAAAAA==.',
Th='Thaurex:BAAALgADCgkJEQAAAA==.Theophania:BAAALgADCgkJDwAAAA==.Thogo:BAABLgAECn8XAAIKAAgJkR5CEgC+AgAKAAgJkR5CEgC+AgAAAA==.',
Ti='Tiger:BAAALgAECgEJAQAAAA==.Tinykitsune:BAAALgADCgMJAwAAAA==.Tipnontotems:BAAALgADCgcJDQAAAA==.',
To='Toadeater:BAAALgADCgMJAwAAAA==.Tokiya:BAAALgAECgMJAwAAAA==.Tomerd:BAAALgAECgEJAQABLgAECggJIQAhAIchAA==.Tomerto:BAABLgAECn8hAAMhAAgJhyE9AwBUAgAhAAgJhyE9AwBUAgAQAAEJbAhaUwEqAAAAAA==.Toobeastly:BAAALgAECgUJBwAAAA==.Tooner:BAAALgAECgYJDwAAAA==.Torques:BAAALgADCgYJDAAAAA==.Toymonkey:BAAALgAECgMJBQAAAA==.',
Tr='Trielas:BAAALgADCgMJAwAAAA==.Tryingmybest:BAAALgAECgQJBAABLgAECggJHAAPAGQZAA==.',
Tu='Tuxedomaask:BAAALgAECgIJAgABLgAECgQJBQADAAAAAA==.',
Tw='Twentyone:BAABLgAECn8pAAIiAAgJXibKAAByAwAiAAgJXibKAAByAwAAAA==.Twiggz:BAAALgAECgUJBQABLgAECggJIQAIAOobAA==.Twozero:BAAALgAECgQJBAAAAA==.',
Ty='Tyiesticus:BAAALgAECgYJBwAAAA==.Tyralen:BAABLgAECn8YAAIZAAgJaRj5GwBfAgAZAAgJaRj5GwBfAgABLgAECggJGQAiACsRAA==.Tyrandras:BAABLgAECn8ZAAIiAAgJKxG4AwBdAQAiAAgJKxG4AwBdAQAAAA==.Tyrec:BAAALgAECgEJAQABLgAECgQJBQADAAAAAA==.Tyrïon:BAAALgAECgYJCwAAAA==.',
['Tö']='Töxxy:BAAALgAECgIJAgAAAA==.',
Ul='Uldrag:BAAALgAECgYJCwAAAA==.',
Va='Vaero:BAABLgAECn8hAAITAAcJPSJIBgAXAgATAAcJPSJIBgAXAgAAAA==.Vandenar:BAAALgAECgYJEwAAAA==.Vandutchy:BAAALgADCgMJAQAAAA==.Varju:BAAALgAECgYJDgAAAA==.Vauromoth:BAAALgADCgEJAQAAAA==.',
Vd='Vdarkadin:BAAALgADCgEJAQABLgAECgEJAQADAAAAAA==.Vdarkdevour:BAAALgAECgEJAQABLgAECgEJAQADAAAAAA==.Vdarksmonk:BAAALgAECgEJAQAAAA==.',
Ve='Vee:BAAALgADCgcJBwAAAA==.Velyssa:BAAALgADCgcJBwABLgAECgYJDwADAAAAAA==.Venandi:BAAALgADCgMJAwAAAA==.Venni:BAAALgAECgEJAQAAAA==.Venoshock:BAAALgADCgEJAQAAAA==.',
Vi='Vibez:BAAALgAECgEJAQAAAA==.Vibin:BAABLgAECn8UAAIVAAYJ+xr6FwDVAQAVAAYJ+xr6FwDVAQAAAA==.Vineeshewah:BAAALgAECgYJDwAAAA==.Vision:BAAALgAECgEJAgAAAA==.Vivi:BAAALgADCgcJDAAAAA==.Vizu:BAAALgADCgcJBwAAAA==.',
Vo='Voruna:BAAALgADCgcJBwAAAA==.',
Wa='Wantedd:BAAALgAECgYJCAAAAA==.',
Wh='Whalend:BAAALgAECgYJDQAAAA==.',
Wi='Wilbo:BAABLgAFFH8FAAIeAAIJfA1wFwCZAAAeAAIJfA1wFwCZAAABLgAFFAMJCgASACEUAA==.Wilbodragons:BAAALgADCgMJAwAAAA==.Wily:BAAALgAECgYJEgAAAA==.Wisperwing:BAAALgAECgQJCQAAAA==.',
Wo='Wolfdrudu:BAAALgAECgQJBAAAAA==.Worldfire:BAAALgAECgYJEgAAAA==.Wormadina:BAAALgADCgkJHwAAAA==.Wormszer:BAAALgAECgQJBQAAAA==.Woth:BAAALgAECgUJBwAAAA==.',
Wr='Wrecka:BAABLgAECn8fAAMBAAcJuCMoBwD/AQABAAcJuCMoBwD/AQAjAAEJAABMNwAlAAAAAA==.',
Ww='Ww:BAAALgAECgcJCAABLgAFFAUJAgADAAAAAA==.',
Wy='Wylds:BAAALgAECgMJAwABLgAFFAYJFAAVANcmAA==.Wyldvyrus:BAAALgADCgUJBQAAAA==.Wynds:BAACLgAFFH8UAAIVAAYJ1yYMAACbAgAVAAYJ1yYMAACbAgAuAAQKfyMAAhUACQk1JYgAALUDABUACQk1JYgAALUDAAAA.Wyrsa:BAAALgAECgYJEAAAAA==.Wyrsathuzad:BAAALgADCgUJBQAAAA==.',
Xa='Xaro:BAAALgADCgMJAwAAAA==.',
Xe='Xelock:BAAALgAECgcJBwAAAA==.',
Xi='Xi:BAABLgAECn8ZAAIVAAgJDApeBACBAQAVAAgJDApeBACBAQAAAA==.Xiaozhi:BAEALgAECgYJDwAAAA==.',
Xz='Xzariana:BAAALgAECgYJDgAAAA==.',
Ya='Yakor:BAAALgAECgMJBQAAAA==.Yakub:BAABLgAFFH8JAAMaAAQJKxH2BACsAAAaAAMJ0Bb2BACsAAAZAAIJwAVFEQBvAAAAAA==.',
Ye='Yennefer:BAAALgADCgcJBwAAAA==.Yeobsuirad:BAAALgAECgEJBQAAAA==.',
Yo='Yodda:BAAALgAECgYJCAAAAA==.',
['Yë']='Yëëter:BAAALgAECgIJAgAAAA==.',
Za='Zach:BAAALgAECgYJEwAAAA==.Zaeix:BAAALgADCgcJBwAAAA==.Zaionis:BAAALgAECgUJCAAAAA==.Zalius:BAAALgAECgUJDQAAAA==.Zanori:BAABLgAECn8eAAMlAAgJPBPcAQCAAQASAAgJdBLQXgDWAQAlAAcJdQ7cAQCAAQAAAA==.Zansijo:BAAALgAECgIJAgABLgAECggJHgAlADwTAA==.Zarienia:BAAALgAECgUJBQAAAA==.',
Ze='Zedmann:BAAALgADCgcJEwABLgAECgYJBwADAAAAAA==.Zellyne:BAACLgAFFH8LAAIcAAQJuxPzBAAzAQAcAAQJuxPzBAAzAQAuAAQKfx0AAhwACAnBI24FADYDABwACAnBI24FADYDAAAA.Zenstiller:BAAALgADCgEJAQAAAA==.Zentho:BAAALgADCgYJBwAAAA==.',
Zo='Zom:BAAALgADCgkJCQAAAA==.Zorriya:BAAALgAECgYJDAAAAA==.Zovhia:BAAALgAECgYJDQAAAA==.',
Zy='Zygo:BAAALgADCgQJBAAAAA==.',
['Çò']='Çòñvíçtíòñ:BAAALgAECgYJCQAAAA==.',
['Ìf']='Ìfrìt:BAAALgAECgcJDAAAAA==.',
['Ýu']='Ýuno:BAAALgAECggJEgAAAA==.',
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

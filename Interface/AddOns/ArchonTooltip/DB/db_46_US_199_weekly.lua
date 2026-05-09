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

local lookup = {'Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Druid-Restoration','Shaman-Restoration','DemonHunter-Vengeance','Unknown-Unknown','Paladin-Protection','Paladin-Retribution','Paladin-Holy','Mage-Frost','Warrior-Arms','Warrior-Fury','Evoker-Preservation','Warrior-Protection','Priest-Holy','DemonHunter-Devourer','DeathKnight-Blood','Mage-Fire','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Monk-Brewmaster','Monk-Mistweaver','Monk-Windwalker','Druid-Guardian','DeathKnight-Frost','DeathKnight-Unholy','Priest-Shadow','Shaman-Elemental','Evoker-Augmentation','Evoker-Devastation','Druid-Balance','DemonHunter-Havoc','Druid-Feral','Shaman-Enhancement','Priest-Discipline','Rogue-Subtlety','Rogue-Outlaw','Rogue-Assassination',}
local provider = {region='US',realm='Skywall',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abigt:BAAALgAECgYJEQAAAA==.',
Ad='Adalaidê:BAAALgAECgUJBgAAAA==.',
Ae='Aelusion:BAABLgAECn8ZAAQBAAgJXR46GgC3AgABAAgJlh06GgC3AgACAAMJWiESLAAOAQADAAEJQCQhJwBVAAAAAA==.Aeluu:BAAALgAECgcJBwABLgAECggJHwAEALgRAA==.Aerynne:BAAALgAECgMJDQAAAA==.',
Ai='Ailis:BAAALgAECgQJBAAAAA==.Airie:BAABLgAECn8mAAIFAAgJ+gvrLABiAQAFAAgJ+gvrLABiAQAAAA==.Aita:BAACLgAFFH8GAAIGAAMJgQZFBQCOAAAGAAMJgQZFBQCOAAAuAAQKfxwAAgYACAk4Ge4GAB0CAAYACAk4Ge4GAB0CAAAA.',
Ak='Akuso:BAAALgADCgYJCAAAAA==.',
Al='Alassa:BAAALgADCgQJBAAAAA==.Alayro:BAAALgAECgcJBQAAAA==.Alejandrø:BAAALgADCgUJBgAAAA==.Alisaa:BAAALgADCgMJAwAAAA==.Allegria:BAAALgAECgEJAQAAAA==.Alondra:BAABLgAECn8bAAICAAgJYB9BAQCBAgACAAgJYB9BAQCBAgAAAA==.Alulà:BAAALgAECgYJEwAAAA==.Aluucard:BAAALgADCgUJBQAAAA==.Aluuni:BAAALgAECgUJCQAAAA==.',
Am='Amo:BAAALgAECgIJAgABLgAECgUJCgAHAAAAAA==.',
An='Anaeli:BAABLgAECn8yAAIFAAgJyRxCDQBgAgAFAAgJyRxCDQBgAgAAAA==.Anariel:BAAALgADCgUJBQABLgADCgcJDQAHAAAAAA==.Androth:BAABLgAECn8aAAMIAAcJORhiCwCIAQAIAAYJjhtiCwCIAQAJAAEJjAcIHQEkAAAAAA==.Angita:BAAALgAECgQJBwAAAA==.Antipæn:BAACLgAFFH8LAAMJAAMJnRezKQAHAQAJAAMJnRezKQAHAQAKAAEJKiWfGQBpAAAuAAQKfzQAAwkACQn3JR0BAGkDAAkACQn3JR0BAGkDAAoABgmKH/YpAOIBAAAA.',
Ap='Apologia:BAABLgAECn8pAAIJAAgJTCNCCgC2AgAJAAgJTCNCCgC2AgAAAA==.',
Ar='Arcainus:BAAALgADCgIJAgAAAA==.Arceé:BAAALgAECgIJBAAAAA==.Archaic:BAABLgAECn8lAAILAAgJBhK8OwC1AQALAAgJBhK8OwC1AQAAAA==.Ardicelia:BAAALgAECgEJAQAAAA==.Ares:BAACLgAFFH8RAAMMAAUJOiDoAwBzAQAMAAUJOiDoAwBzAQANAAIJCB7vFgCuAAAuAAQKfx4AAwwACAlOJOQBABoDAAwACAnJIuQBABoDAA0ABwlHIjUZAIICAAAA.Ariellä:BAAALgADCgEJAQAAAA==.Arilynx:BAABLgAECn8iAAIOAAkJ4AdJDQByAQAOAAkJ4AdJDQByAQAAAA==.Arlynn:BAAALgADCgcJBwAAAA==.Armorgorden:BAABLgAECn8rAAIPAAkJBCPjAAAqAwAPAAkJBCPjAAAqAwAAAA==.Aroviaa:BAABLgAECn8uAAIQAAgJIx+dBADHAgAQAAgJIx+dBADHAgAAAA==.Arpmek:BAABLgAECn8aAAIRAAgJmxMfJwCgAQARAAgJmxMfJwCgAQAAAA==.Artemîs:BAAALgAECgMJAwAAAA==.Arydynn:BAAALgADCgIJAgAAAA==.',
As='Ashal:BAAALgAECgYJDAAAAA==.Astrotoad:BAAALgAECgEJAQAAAA==.Astrìd:BAAALgADCgIJAgAAAA==.',
Au='Auntmary:BAAALgADCgYJCAAAAA==.Auramaximus:BAAALgAECgQJBQAAAA==.Aurtt:BAABLgAECn8vAAISAAgJqxc3DQCfAQASAAgJqxc3DQCfAQAAAA==.',
Av='Avanel:BAAALgADCgkJGgAAAA==.Avidae:BAAALgADCgcJCAAAAA==.',
Az='Azkadelia:BAAALgAECgEJAQAAAA==.',
Ba='Bageera:BAAALgAECgYJEAAAAA==.Bahahaknight:BAABLgAECn8mAAISAAgJxRubCQDlAQASAAgJxRubCQDlAQAAAA==.Barcy:BAAALgAECgEJAwAAAA==.Barnette:BAABLgAECn82AAITAAkJ+BIzAQAWAgATAAkJ+BIzAQAWAgAAAA==.Barvi:BAAALgADCgEJAQABLgADCgUJBQAHAAAAAA==.Bashdown:BAAALgADCgEJAQAAAA==.Basic:BAAALgADCgEJAQAAAA==.',
Be='Bearyy:BAAALgADCgQJBAAAAA==.Belthos:BAABLgAECn8lAAIJAAgJ4xnHLADKAQAJAAgJ4xnHLADKAQAAAA==.Berristan:BAABLgAECn8cAAMKAAkJ1BeiDAC1AgAKAAkJ1BeiDAC1AgAJAAMJgAWALAFIAAAAAA==.Bestwingman:BAAALgAECgEJAQAAAA==.',
Bg='Bgdaddyjupes:BAAALgADCgQJBAAAAA==.',
Bi='Bigsam:BAAALgAECgEJAQAAAA==.Bittytigs:BAAALgADCgUJBQAAAA==.',
Bl='Blossom:BAACLgAFFH8HAAIOAAQJXQ5rDwAgAQAOAAQJXQ5rDwAgAQAuAAQKfxUAAg4ACAmdEYoYAM4BAA4ACAmdEYoYAM4BAAAA.Bluewitchpa:BAAALgADCgkJIQAAAA==.',
Bo='Boomboomkill:BAAALgADCgEJAQAAAA==.Boudiicca:BAABLgAECn8ZAAIQAAQJmRI9LQDjAAAQAAQJmRI9LQDjAAAAAA==.Boxmasterr:BAABLgAECn8iAAMBAAgJqAuGPgBvAQABAAgJDwuGPgBvAQADAAcJrgeqCgDiAAAAAA==.',
Br='Brasmir:BAAALgAECgUJDAAAAA==.Bremerton:BAAALgAECgYJEQAAAA==.Brianzero:BAAALgADCgEJAQAAAA==.',
Bu='Bubblegìrl:BAAALgADCgcJCAAAAA==.Bubblement:BAAALgAFFAUJDQAAAQ==.Bushalabong:BAAALgAECgMJBAAAAA==.Butherrface:BAAALgADCgQJBAAAAA==.',
Bw='Bwonsmashdi:BAAALgADCgUJBgAAAA==.',
['Bù']='Bùb:BAAALgADCgEJAQAAAA==.',
Ca='Cafo:BAAALgADCgYJDAAAAA==.Capy:BAACLgAFFH8HAAMUAAQJBhucBABzAQAUAAQJBhucBABzAQAVAAEJuw3eTwBMAAAuAAQKfzAABBQACQl8Ib0EAHQCABQACAm0Hr0EAHQCABUABwkIIIcjADACABYABgmIF0syAKUBAAAA.Cardran:BAAALgADCgEJAQABLgAECgcJGgAIADkYAA==.Carkusw:BAAALgAECgMJBwAAAA==.Cassyn:BAABLgAECn8YAAIKAAgJ3yHWBwDwAgAKAAgJ3yHWBwDwAgAAAA==.Catamay:BAABLgAECn8aAAIRAAgJphs8FgAKAgARAAgJphs8FgAKAgABLgADCgkJGgAHAAAAAA==.Catprincess:BAABLgAECn8fAAIEAAgJuBF7OwC3AQAEAAgJuBF7OwC3AQAAAA==.Caylara:BAAALgAECgYJCAAAAA==.Cayssaber:BAAALgADCgEJAQAAAA==.',
Ce='Celrythis:BAAALgAECgUJBwAAAA==.',
Ch='Chai:BAAALgAECgYJBgAAAA==.Chewglass:BAAALgADCggJCAAAAA==.Chiji:BAABLgAECn8aAAIXAAcJWxNGGQBrAQAXAAcJWxNGGQBrAQAAAA==.',
Ci='Cindrethal:BAAALgADCggJCAAAAA==.',
Cl='Clayler:BAAALgADCgQJBAAAAA==.Cleõ:BAAALgADCggJCwAAAA==.Clipperz:BAAALgAECgEJAQAAAA==.',
Co='Coocoohead:BAAALgAECgMJBQAAAA==.Coralorchid:BAABLgAECn8YAAMIAAYJiRMTFAAGAQAIAAYJ9xETFAAGAQAJAAUJmw9NoQCvAAAAAA==.Corrupt:BAAALgAECgEJAQAAAA==.',
Cp='Cptdarkk:BAAALgAECgYJEAAAAA==.',
Cr='Crytal:BAAALgADCgEJAgAAAA==.',
Cu='Cuddlebucket:BAAALgADCgQJBQAAAA==.Curissan:BAAALgAECgYJDgAAAA==.',
Cy='Cyg:BAAALgADCgEJAQAAAA==.',
['Cè']='Cères:BAABLgAECn8UAAIEAAgJAiFcCQCzAgAEAAgJAiFcCQCzAgAAAA==.',
['Cø']='Cøndemn:BAAALgAECgMJAwAAAA==.',
Da='Daemyn:BAAALgADCgcJBwAAAA==.Daladalian:BAAALgAECgMJAwAAAA==.Dalir:BAAALgAECgYJDQAAAA==.Dalruend:BAAALgADCgYJCwABLgAFFAYJFwAYAN0PAA==.Dalspin:BAACLgAFFH8XAAIYAAYJ3Q97CACcAQAYAAYJ3Q97CACcAQAuAAQKfx8ABBgACQm4GtsHANkCABgACQm4GtsHANkCABkABwm8Ek4qAIoBABcAAwkEAjNUAFQAAAAA.Dalthepal:BAABLgAECn8UAAIKAAcJXx+oHgAiAgAKAAcJXx+oHgAiAgABLgAFFAYJFwAYAN0PAA==.Darka:BAAALgADCgYJFgAAAA==.Davidline:BAACLgAFFH8KAAIJAAMJVxuDJwAOAQAJAAMJVxuDJwAOAQAuAAQKfzgAAgkACQnGJKMBAFUDAAkACQnGJKMBAFUDAAAA.Dawnfist:BAAALgAECgQJBAAAAA==.',
De='Deathsaberss:BAABLgAECn8kAAIMAAgJWxXmCAC+AQAMAAgJWxXmCAC+AQAAAA==.Deathstealer:BAAALgAECgIJAwAAAA==.Deathszen:BAAALgAECgcJDgAAAA==.Debauch:BAAALgAECgcJEQAAAA==.Demonkayk:BAAALgADCgkJDgAAAA==.Derke:BAAALgAECgQJBwAAAA==.',
Di='Didudietho:BAAALgADCggJCAABLgAECgcJKAAJAF8UAA==.Diladrin:BAACLgAFFH8KAAIaAAMJig4eBwCuAAAaAAMJig4eBwCuAAAuAAQKfzcAAhoACQlVF5wEACgCABoACQlVF5wEACgCAAAA.Diode:BAACLgAFFH8UAAQbAAUJJRmKAgA1AQAcAAQJ1hTzMAA+AQAbAAQJBBOKAgA1AQASAAEJAADxKQAAAAAuAAQKfy0AAxsACAmHId0BAEkCABwACAncIC8YAOoCABsACAl1HN0BAEkCAAAA.',
Do='Doileag:BAAALgAECgYJDgAAAA==.Domer:BAAALgAECgYJCAAAAA==.Doomsong:BAAALgADCgYJCgAAAA==.Dora:BAAALgAECgMJAwAAAA==.Dottmatrix:BAAALgAECgYJDgAAAA==.',
Dr='Drachnia:BAAALgAECgQJBAAAAA==.Dragønbreath:BAACLgAFFH8FAAILAAQJVgU8QQAJAQALAAQJVgU8QQAJAQAuAAQKfx0AAxMACQlxGhcCAEoCABMACAnMFxcCAEoCAAsACAk3FZZiAEwBAAAA.Dreadwing:BAABLgAECn8WAAIcAAMJGgTtrwB/AAAcAAMJGgTtrwB/AAAAAA==.',
Du='Duf:BAACLgAFFH8VAAIXAAUJexImEwAlAQAXAAUJexImEwAlAQAuAAQKfy0AAhcACAksH7YKABgCABcACAksH7YKABgCAAAA.Dunso:BAAALgADCgYJAQAAAA==.Dustbunny:BAABLgAECn8oAAIQAAgJPB5iCABpAgAQAAgJPB5iCABpAgAAAA==.',
Dw='Dwagon:BAAALgAECggJCAAAAA==.',
['Dæ']='Dæmôn:BAAALgAECgUJBQAAAA==.',
['Dì']='Dìzzy:BAAALgAECgIJAgAAAA==.',
['Dó']='Dóómkin:BAAALgADCgEJAQAAAA==.',
['Dû']='Dûn:BAABLgAECn8iAAMXAAgJdxsgCwAQAgAXAAgJdxsgCwAQAgAZAAIJpBhJSwBYAAAAAA==.Dûna:BAABLgAECn8YAAIdAAgJoh0qDAADAgAdAAgJoh0qDAADAgABLgAECggJIgAXAHcbAA==.',
Ei='Eira:BAAALgADCggJDQAAAA==.',
El='Elaatia:BAABLgAECn8vAAIJAAgJqiOZCwCmAgAJAAgJqiOZCwCmAgAAAA==.Elduar:BAAALgADCgEJAQAAAA==.Elidria:BAAALgADCgYJBgAAAA==.Elimental:BAAALgAECgYJCwAAAA==.Ellaring:BAAALgAECgYJCAAAAA==.Elle:BAAALgADCgcJBwAAAA==.Elleanna:BAAALgADCgcJBwAAAA==.Elrric:BAABLgAECn8UAAIcAAcJ4w1TSQBfAQAcAAcJ4w1TSQBfAQAAAA==.',
En='Endora:BAAALgADCggJDQAAAA==.Enezath:BAAALgADCgYJBgAAAA==.',
Er='Erakron:BAABLgAECn8aAAMFAAcJXyHiFQAEAgAFAAYJhCDiFQAEAgAeAAUJ1gqjRACWAAAAAA==.Eriko:BAAALgADCgkJEAAAAA==.Eroviaa:BAAALgAECgQJBAABLgAECggJLgAQACMfAA==.Erovvia:BAAALgAECgEJAQABLgAECggJLgAQACMfAA==.',
Et='Etali:BAAALgAECgIJAgABLgAECgYJEwAHAAAAAA==.',
Ez='Ezothen:BAABLgAECn8cAAMfAAgJsANFLgDuAAAfAAgJXANFLgDuAAAgAAQJawRfLwCdAAAAAA==.',
Fa='Faedoria:BAAALgAECgYJEAAAAA==.Faeryln:BAABLgAECn8hAAIQAAgJQQwYHQBhAQAQAAgJQQwYHQBhAQAAAA==.Faewrynn:BAAALgADCgMJAwAAAA==.Falkorr:BAAALgADCgEJAQABLgAECgYJGQAhAM8cAA==.Falorie:BAAALgADCgYJCwAAAA==.Fatesmage:BAAALgADCgUJCAAAAA==.Fatherfade:BAAALgAECgQJBAAAAA==.Fatherkarras:BAAALgADCgIJAgAAAA==.Faustion:BAABLgAECn8VAAIOAAYJ4iFhBQBEAgAOAAYJ4iFhBQBEAgAAAA==.Faustus:BAAALgADCgQJCgABLgAECgYJFQAOAOIhAA==.',
Fe='Feature:BAAALgAECgkJBwAAAA==.Felstormer:BAAALgADCggJEAABLgADCgkJDQAHAAAAAA==.',
Fi='Filthy:BAAALgADCggJDgAAAA==.Finessed:BAAALgADCgEJAQAAAA==.Firebrande:BAAALgAECgQJBwAAAA==.Fireføx:BAAALgADCgEJAQAAAA==.Fisticuffs:BAAALgADCgkJFQAAAA==.Fizzllebang:BAABLgAECn8hAAICAAgJdBCLCABRAQACAAgJdBCLCABRAQAAAA==.',
Fl='Flamewhisker:BAAALgAECgQJBwAAAQ==.Flogginrenee:BAAALgAECgYJEwAAAA==.Floggsdaddy:BAAALgAECgYJEwAAAA==.Floke:BAAALgAECgMJBAAAAA==.Flokie:BAAALgADCgYJEQAAAA==.',
Fr='Fraublucher:BAABLgAECn8aAAIQAAgJrg/iFgCbAQAQAAgJrg/iFgCbAQAAAA==.Fredrik:BAAALgAFFAEJAgABLgAECgYJJQALAAwWAA==.Frewyn:BAAALgAECgQJBgAAAA==.Frostimoth:BAAALgAECgcJEwAAAA==.Frozty:BAAALgAECgYJCQAAAA==.',
Ga='Galandel:BAAALgADCgkJHQAAAA==.Galial:BAACLgAFFH8NAAIGAAQJIyGwAACDAQAGAAQJIyGwAACDAQAuAAQKfyIAAgYACQlaHzsBACIDAAYACQlaHzsBACIDAAAA.Gantar:BAAALgAFFAEJAQAAAA==.Garlicbread:BAAALgADCgYJBgABLgAFFAQJDQAGACMhAA==.Gaznol:BAABLgAECn8TAAIVAAcJ8x9JGAAOAgAVAAcJ8x9JGAAOAgAAAA==.',
Ge='Gelasera:BAAALgAECgQJBwAAAA==.',
Gh='Ghibli:BAAALgAECgcJEAAAAA==.',
Gl='Glaivethras:BAABLgAECn8hAAIGAAgJhSI6AgBjAgAGAAgJhSI6AgBjAgAAAA==.Glyphix:BAAALgAECggJEAAAAA==.',
Gn='Gnarly:BAAALgAECgEJAQABLgAECgEJAQAHAAAAAA==.',
Go='Goochtrap:BAAALgADCgEJAQAAAA==.Gorgon:BAAALgAECgMJBAAAAA==.',
Gr='Grasman:BAAALgADCgYJBwAAAA==.Gremlynn:BAABLgAECn8aAAQUAAgJxgwWEACpAQAUAAgJYAsWEACpAQAVAAQJeQ4sgQDkAAAWAAQJXwUeaACeAAAAAA==.Gridluck:BAAALgAECgMJBAAAAA==.Groot:BAAALgAECgUJCAABLgAECggJHgAJAO4VAA==.',
Gu='Gundunn:BAAALgADCgEJAQAAAA==.',
Ha='Hackdk:BAAALgADCgYJCwAAAA==.Haedlesshour:BAAALgADCgcJBwAAAA==.Hahona:BAAALgADCgEJAQABLgAECgQJBgAHAAAAAA==.Hamfist:BAAALgADCgYJBwAAAA==.Hanhealz:BAEBLgAECn8dAAIdAAgJshD+FACaAQAdAAgJshD+FACaAQABLgAECgYJBwAHAAAAAA==.Hannebal:BAABLgAECn8ZAAIKAAgJ/RAQGQDDAQAKAAgJ/RAQGQDDAQAAAA==.Havenfire:BAAALgADCgUJBQABLgADCgcJBgAHAAAAAA==.',
He='Hearsebait:BAAALgADCgIJAgAAAA==.Hemlock:BAAALgADCgYJCgAAAA==.Hexia:BAAALgADCggJEgAAAA==.Heydaw:BAAALgAECggJDgABLgAECgkJIAAcAHEgAA==.',
Hi='Highmountain:BAAALgADCgkJCgAAAA==.',
Ho='Hobloc:BAAALgADCgcJCwAAAA==.Hobs:BAAALgADCgYJBgAAAA==.Holybeatdown:BAAALgADCgMJAwAAAA==.Holyßloodelf:BAAALgAECgQJBAABLgAECggJDwAHAAAAAA==.Honeysbadger:BAAALgAECgMJAwAAAA==.Hornet:BAABLgAECn8VAAMRAAgJZBDULwB3AQARAAgJ7g/ULwB3AQAiAAQJFwz0SADPAAAAAA==.Hotcupofjoe:BAAALgADCgYJBgAAAA==.Hotsauce:BAAALgAECgYJBgABLgAFFAYJFwALAJ4dAA==.',
Hu='Huasca:BAAALgAECgMJBQAAAA==.Humungous:BAAALgAECgcJDQAAAA==.Hunnybunz:BAAALgAECgYJDAAAAA==.',
['Hà']='Hàney:BAEALgAECgYJBwAAAA==.',
['Hâ']='Hârkness:BAAALgAECgMJEgAAAA==.',
['Hé']='Hélio:BAAALgADCgUJBQAAAA==.',
Ic='Icastfirebal:BAAALgAECgEJAQAAAA==.Icypants:BAAALgADCgcJBwAAAA==.',
If='Iffany:BAAALgAECggJDAAAAA==.',
Ig='Igotahitin:BAAALgADCgMJBgAAAA==.',
Ih='Ihitstuff:BAAALgADCgUJBAAAAA==.',
Ik='Iker:BAABLgAECn8ZAAIXAAgJsxA+FgCHAQAXAAgJsxA+FgCHAQAAAA==.',
Il='Illida:BAAALgAECgMJAwAAAA==.',
Im='Imamalelol:BAAALgAECgQJBgAAAA==.',
In='Indira:BAAALgADCgcJDQAAAA==.Insistonfist:BAAALgADCgEJAQAAAA==.Intol:BAAALgAFFAQJBQABLgAFFAQJBwAOAF0OAQ==.Inumimi:BAABLgAECn8XAAIjAAYJugRlGACsAAAjAAYJugRlGACsAAAAAA==.Invincidemon:BAAALgAECgQJBAAAAA==.',
Ir='Irkenfox:BAECLgAFFH8RAAIPAAUJfSDbAwCAAQAPAAUJfSDbAwCAAQAuAAQKfyUAAg8ACAmhI5wDABsDAA8ACAmhI5wDABsDAAAA.',
It='Ithran:BAABLgAECn8ZAAILAAgJ+gpeUQB2AQALAAgJ+gpeUQB2AQAAAA==.',
Iw='Iwilltank:BAAALgADCgYJDQAAAA==.',
Ix='Ixitt:BAABLgAECn8iAAITAAgJ8h1QAQALAgATAAgJ8h1QAQALAgAAAA==.',
Ja='Jallaz:BAAALgADCgQJBAAAAA==.James:BAABLgAECn8lAAILAAYJDBaBUwBxAQALAAYJDBaBUwBxAQAAAA==.Janderick:BAABLgAECn8XAAINAAYJjx/sFgCwAQANAAYJjx/sFgCwAQAAAA==.Janthara:BAAALgAECgQJBAAAAA==.',
Je='Jellacee:BAABLgAECn8ZAAMiAAQJKxK7LQB1AAAiAAQJKxK7LQB1AAARAAIJHgMfsgA6AAAAAA==.Jesterjoe:BAAALgAECgIJBAAAAA==.',
Jh='Jhonson:BAAALgADCgYJBgAAAA==.',
Ji='Jimboberjim:BAACLgAFFH8UAAICAAUJ7SMrAQCFAQACAAUJ7SMrAQCFAQAuAAQKfy0AAgIACAk2JfQAAC8DAAIACAk2JfQAAC8DAAAA.Jimi:BAAALgADCgUJBQAAAA==.',
Jj='Jjoosshhiiee:BAAALgADCgMJBAABLgAFFAEJAQAHAAAAAA==.',
Jo='Jojokiller:BAAALgADCgEJAQAAAA==.Jolio:BAABLgAECn8UAAQCAAcJfhZbEwC5AAACAAQJZhRbEwC5AAABAAMJlBN+iAC0AAADAAEJXCBzKgBKAAAAAA==.Joltraxi:BAAALgAECgMJBAAAAA==.Jorlidan:BAAALgAECgYJCgAAAA==.Joshe:BAAALgAECgYJEwABLgAFFAEJAQAHAAAAAA==.Jovae:BAAALgADCgIJAgAAAA==.',
Ju='Juggernauht:BAAALgAECgUJCQAAAA==.Juicethevoid:BAABLgAECn8kAAIRAAgJWgeQSQAcAQARAAgJWgeQSQAcAQAAAA==.Juniornite:BAABLgAECn8rAAILAAgJASKCDAC8AgALAAgJASKCDAC8AgAAAA==.Justicus:BAAALgAECgUJDgABLgAECgcJIAAjAOsfAA==.Justthetouch:BAAALgAECggJCQAAAA==.',
Ka='Kaeldrin:BAAALgADCgkJFAAAAA==.Kaelsanguine:BAAALgAECgEJAQAAAA==.Kagemaro:BAAALgAECgYJEwAAAA==.Kaiser:BAAALgAECgQJCQAAAA==.Kaisér:BAAALgADCgYJBgAAAA==.Kalimathath:BAAALgAECgQJBwAAAA==.Kalzod:BAACLgAFFH8KAAIBAAMJixjeOgDpAAABAAMJixjeOgDpAAAuAAQKfzIAAwEACQmGJRUBAGkDAAEACQmGJRUBAGkDAAMAAQkAABwkAGEAAAAA.Kariana:BAAALgAECgYJDgAAAA==.Katett:BAAALgAECgcJDgAAAA==.Kativeria:BAAALgAECgQJBwAAAA==.Kattara:BAAALgAECgQJBAAAAA==.Kattitude:BAAALgADCgcJDwABLgAECgYJDgAHAAAAAA==.Kaysabr:BAAALgADCgkJDAAAAA==.Kayssaber:BAAALgAECgYJEAAAAA==.Kazarale:BAAALgADCgQJBAAAAA==.Kazkade:BAAALgAECgMJAwAAAA==.',
Ke='Keanuu:BAAALgADCgMJAwAAAA==.Kerfufle:BAAALgAECgEJAQAAAA==.Keyn:BAAALgADCgEJAQAAAA==.Keynstolor:BAABLgAECn8ZAAIVAAcJuxu6OwBeAQAVAAcJuxu6OwBeAQAAAA==.',
Kh='Khionè:BAAALgAECgEJAQAAAA==.Khálifá:BAAALgAECgMJBAAAAA==.',
Ki='Kicker:BAAALgAECgYJCQAAAA==.Killmora:BAAALgADCgkJIQAAAA==.Kippars:BAAALgAECgYJEwAAAA==.Kiritsugo:BAAALgADCgUJDQAAAA==.Kissame:BAAALgADCgcJDgAAAA==.',
Ko='Kodazoff:BAABLgAECn8YAAMfAAgJAA9oGAB+AQAfAAgJAA9oGAB+AQAOAAEJyASZSgAtAAAAAA==.Korevash:BAABLgAECn8WAAIkAAYJtRvjCQB6AQAkAAYJtRvjCQB6AQABLgAFFAMJCgAlAFcTAA==.Korupta:BAABLgAECn8nAAMRAAYJ6REgTgAOAQARAAYJ6REgTgAOAQAiAAUJ3A32PQAFAQABLgAECgkJIQANAOcQAA==.Korzilius:BAAALgAECgcJCAAAAA==.',
Kr='Kraiceru:BAABLgAECn8XAAIQAAcJ2x8fCABuAgAQAAcJ2x8fCABuAgAAAA==.Krissylu:BAAALgAECgYJDQAAAA==.Krothix:BAABLgAECn8fAAIeAAgJpQp9IABLAQAeAAgJpQp9IABLAQAAAA==.Kruvix:BAAALgAECgYJCgAAAA==.Kryjag:BAAALgADCggJCAAAAA==.Kryshym:BAAALgADCgkJIQABLgAECgYJCAAHAAAAAA==.',
Ku='Kuatea:BAAALgADCgUJBQAAAA==.Kurorø:BAAALgAECgUJCgAAAA==.',
['Kü']='Kürömë:BAAALgADCgMJAwAAAA==.',
La='Ladara:BAABLgAECn8pAAIDAAkJ8BDRAgDrAQADAAkJ8BDRAgDrAQAAAA==.Laima:BAAALgADCgUJDQAAAA==.Landor:BAAALgADCgEJAQAAAA==.Lanea:BAAALgAECgEJAQAAAA==.',
Le='Leheo:BAAALgAECgQJBgAAAA==.Lehua:BAAALgADCggJDAAAAA==.Leilanii:BAAALgADCgkJFQAAAA==.Lemook:BAAALgAECgQJBAAAAA==.Leonìdas:BAAALgAECgQJBgAAAA==.',
Lh='Lhei:BAAALgAECgEJAgAAAA==.',
Li='Lightstormer:BAAALgADCgkJDQAAAA==.Lilarielle:BAABLgAECn8gAAIjAAgJ8wSZEwDmAAAjAAgJ8wSZEwDmAAAAAA==.Lildash:BAAALgADCgIJAgABLgAECgcJGgAIADkYAA==.Lilface:BAAALgAECgYJCgAAAA==.Liliela:BAAALgAECgQJBAABLgAECgcJGgAIADkYAA==.Lilyannah:BAAALgAECgcJAQAAAA==.Liobrew:BAAALgADCgEJAQABLgAECgEJAQAHAAAAAA==.Liø:BAAALgAECgEJAQAAAA==.',
Lo='Lokir:BAAALgAECgIJAwAAAA==.Lotheovian:BAEALgAECgIJAgABLgAECgYJEQAHAAAAAA==.Lowchin:BAAALgAECgUJBAAAAA==.',
Lu='Lumia:BAABLgAECn8dAAMdAAkJix4rEwBcAgAdAAcJlB8rEwBcAgAQAAYJFBjPSgANAQAAAA==.Lutherion:BAAALgAECgUJBwAAAA==.',
['Lí']='Líttlefoot:BAAALgADCgEJAQAAAA==.',
Ma='Mackdaddy:BAAALgAECgEJAQAAAA==.Mackshiesty:BAAALgAECgUJCQAAAA==.Macoun:BAABLgAECn8ZAAMVAAgJpyOxBQDYAgAVAAgJpyOxBQDYAgAWAAYJEhvrQABVAQAAAA==.Maeledictus:BAAALgAECgMJAwAAAA==.Maga:BAAALgADCgkJHgAAAA==.Magicshowers:BAABLgAECn8qAAILAAgJpSUsCQDhAgALAAgJpSUsCQDhAgAAAA==.Maikiee:BAAALgADCggJCAAAAA==.Manseed:BAAALgAECgYJCgAAAA==.Marksmen:BAAALgADCgEJAQABLgAECgQJBgAHAAAAAA==.Martei:BAACLgAFFH8RAAIjAAUJkRJ8AgBfAQAjAAUJkRJ8AgBfAQAuAAQKfy0AAiMACAmUI0ICAC8DACMACAmUI0ICAC8DAAAA.Maríneth:BAAALgAECgQJBgAAAA==.Mathías:BAABLgAECn8hAAIVAAgJVRi8IgDNAQAVAAgJVRi8IgDNAQAAAA==.',
Me='Meadowfrey:BAAALgAECgEJAQAAAA==.Meowbae:BAABLgAECn8kAAMjAAgJXxE7CACsAQAjAAgJXxE7CACsAQAhAAEJNAGwZQAYAAAAAA==.Mercesdes:BAAALgAECgQJBAAAAA==.Mercina:BAAALgAECgEJAgAAAA==.Mercuros:BAAALgAECggJCAAAAA==.Merknlock:BAAALgAECgEJAQAAAA==.',
Mi='Midnyte:BAABLgAECn8sAAMZAAgJdxq+CQAfAgAZAAgJdxq+CQAfAgAYAAQJ6A2/VQB4AAAAAA==.Milkybun:BAAALgADCgkJGQAAAA==.Mini:BAAALgADCgUJBQAAAA==.Minizee:BAAALgADCgYJBAAAAA==.Mirabella:BAAALgAECgQJBgABLgAECgkJJwAYAAAiAA==.Mirokushan:BAAALgAECgMJDAABLgAECgQJDwAHAAAAAA==.Mistfit:BAAALgAECgIJAgAAAA==.Misticlady:BAAALgADCgEJAQAAAA==.Mistrariel:BAAALgAECgYJCwAAAA==.',
Mo='Mojo:BAAALgADCgIJAgAAAA==.Mojomarv:BAABLgAECn8eAAIeAAcJXRmAGwByAQAeAAcJXRmAGwByAQAAAA==.Mordemour:BAAALgAECgIJAwAAAA==.',
Mu='Mungo:BAAALgAECgYJEwAAAA==.',
My='My:BAAALgAECgYJAwAAAA==.Mynkie:BAACLgAFFH8IAAIYAAMJvgmVGQCyAAAYAAMJvgmVGQCyAAAuAAQKfyQAAhgACQnFHMIDAPMCABgACQnFHMIDAPMCAAAA.',
['Mä']='Mägi:BAAALgADCgEJAQAAAA==.',
['Mæ']='Mæstra:BAAALgADCgEJAQAAAA==.',
['Më']='Mëlony:BAAALgADCgIJAgAAAA==.',
Na='Nachtmar:BAAALgAECgQJBQAAAA==.Nadaliss:BAAALgADCgkJCwAAAA==.Nahela:BAACLgAFFH8UAAIRAAUJfxT3HAA2AQARAAUJfxT3HAA2AQAuAAQKfyoAAhEACAlCHNQSACcCABEACAlCHNQSACcCAAAA.',
Ne='Nevermøre:BAAALgAECgIJAgAAAA==.',
Ni='Nimravidae:BAABLgAECn8lAAIKAAgJCxd0DgAyAgAKAAgJCxd0DgAyAgAAAA==.Ninelives:BAABLgAECn8YAAIhAAgJTAIqXQCtAAAhAAgJTAIqXQCtAAAAAA==.Nitecrawler:BAAALgAECgYJEAAAAA==.Nixus:BAAALgAECgMJAwAAAA==.',
No='Nospitfisty:BAAALgAECgYJEgAAAA==.Noxium:BAAALgAECgYJDQAAAA==.Noxolon:BAABLgAECn8jAAINAAgJOBWhEQDkAQANAAgJOBWhEQDkAQAAAA==.',
Nr='Nreaf:BAABLgAECn8uAAMJAAgJyRy6JACUAgAJAAgJyRy6JACUAgAIAAQJxhYaJQDgAAAAAA==.',
Nu='Nufy:BAAALgAECgYJDwAAAA==.',
Ny='Nyctei:BAAALgAECgQJBgAAAA==.Nysca:BAAALgADCgcJBwAAAA==.',
Ob='Obijuan:BAAALgAECgMJAwAAAA==.',
Oc='Octavia:BAAALgADCgYJCAAAAA==.',
Od='Oddotter:BAAALgADCgYJBgAAAA==.',
Oi='Oili:BAAALgAECgUJCwAAAA==.',
Or='Ornstein:BAAALgAECgYJDAAAAA==.',
Ot='Ottuk:BAACLgAFFH8NAAIcAAQJgRImNAA2AQAcAAQJgRImNAA2AQAuAAQKfyEAAxwACQnVIa0IAFgDABwACQnVIa0IAFgDABIAAwlnHXgnAAMBAAAA.',
Pa='Paksenarrion:BAABLgAECn8mAAIIAAgJ4w82DwBFAQAIAAgJ4w82DwBFAQAAAA==.Pancham:BAAALgADCgUJBQAAAA==.Pandemoniúm:BAAALgAECgMJAwAAAA==.Pandemonîum:BAAALgAECggJEAAAAA==.Pandemönium:BAAALgAECgIJAQAAAA==.Pandemöniüm:BAAALgAECgYJDAAAAA==.Pandèmonium:BAAALgAECgYJBgAAAA==.Patchington:BAAALgAECgQJBgAAAA==.',
Pe='Peatmoss:BAAALgADCgQJBAAAAA==.Pendrgn:BAAALgAECgEJAQAAAA==.Peryite:BAAALgADCgMJAwAAAA==.Pezp:BAAALgAECgQJBAABLgAFFAEJAQAHAAAAAA==.Pezvoker:BAAALgAFFAEJAQAAAA==.',
Pi='Pienarri:BAAALgAECgEJAgAAAA==.Pixelme:BAAALgAECgMJBQAAAA==.',
Pl='Pleggster:BAABLgAECn8YAAMFAAcJrA9MLABmAQAFAAcJrA9MLABmAQAeAAEJiAFVcgAfAAAAAA==.',
Po='Pochula:BAABLgAECn8gAAIEAAYJshcqJQCgAQAEAAYJshcqJQCgAQAAAA==.Powerlock:BAAALgAECgQJBQAAAA==.',
Pr='Primo:BAABLgAECn8cAAIKAAgJnxDdNwCbAQAKAAgJnxDdNwCbAQAAAA==.Protricity:BAABLgAECn8vAAMdAAkJzx4vAgD7AgAdAAkJzx4vAgD7AgAQAAEJ2AJXhAAtAAAAAA==.',
Pu='Pumpernickel:BAAALgADCgUJBQABLgAFFAQJDQAGACMhAA==.',
Py='Pyrellyn:BAAALgADCggJCQAAAA==.',
['Pä']='Pändamönium:BAAALgAECggJDgAAAA==.',
['Pæ']='Pæn:BAACLgAFFH8FAAIcAAIJZyMuXADGAAAcAAIJZyMuXADGAAAuAAQKfxwAAxwABgngJNMcABsCABwABgngJNMcABsCABIABgmXH4gLALwBAAEuAAUUAwkLAAkAnRcA.',
Qt='Qtpi:BAAALgADCgcJCAAAAA==.',
Qu='Quan:BAAALgAECgQJBwABLgAECgYJCwAHAAAAAA==.Quantar:BAAALgAECgYJCwAAAA==.',
Qw='Qwe:BAAALgAECgQJCwAAAA==.',
Ra='Racingdead:BAAALgADCgEJAQAAAA==.Rakshine:BAAALgAECggJCQAAAA==.Rancooll:BAAALgADCgkJIQAAAA==.Rasniir:BAABLgAECn8oAAIEAAgJYBwHDACKAgAEAAgJYBwHDACKAgAAAA==.Ravenlash:BAAALgAECgEJBAAAAA==.',
Re='Regna:BAACLgAFFH8UAAINAAUJoiZbAQDIAQANAAUJoiZbAQDIAQAuAAQKfy0AAg0ACAmGJhkDAH8DAA0ACAmGJhkDAH8DAAAA.Regner:BAAALgAECgEJAQAAAA==.Reign:BAAALgADCgYJBwAAAA==.Relkon:BAAALgAECgYJDgAAAA==.Remaked:BAACLgAFFH8eAAIXAAYJmR2RAwC+AQAXAAYJmR2RAwC+AQAuAAQKfzwAAhcACQmrI1cBACQDABcACQmrI1cBACQDAAAA.Remilia:BAABLgAECn8XAAIdAAYJJRgfGgBrAQAdAAYJJRgfGgBrAQAAAA==.Requinix:BAABLgAECn8xAAIVAAgJPxlPGAAOAgAVAAgJPxlPGAAOAgAAAA==.Retro:BAAALgAECgEJAQAAAA==.Revelatiøn:BAAALgADCgIJAgAAAA==.Revunanto:BAAALgAECgcJBgAAAA==.Revwrinkle:BAAALgADCgQJBQAAAA==.Rexthedragon:BAAALgADCgEJAQAAAA==.',
Ri='Riasu:BAAALgADCgYJCwAAAA==.Rickyybobbie:BAAALgAECgUJCwAAAA==.Ricochet:BAABLgAECn8aAAIUAAgJZREUDQDUAQAUAAgJZREUDQDUAQAAAA==.Riptidez:BAAALgADCgcJBgAAAA==.Ririko:BAABLgAECn8mAAIQAAgJ+AwaHABpAQAQAAgJ+AwaHABpAQAAAA==.Ritzo:BAABLgAECn8cAAINAAgJEw/zGACfAQANAAgJEw/zGACfAQAAAA==.Rizzla:BAAALgAECgIJAgABLgAECgYJGQAhAM8cAA==.',
Ro='Rockllobster:BAAALgAECgYJBAABLgAECgYJCAAHAAAAAA==.Rocksanne:BAAALgADCgYJCQAAAA==.Roguebâit:BAABLgAECn8sAAQDAAgJqR0dAgAWAgADAAYJFR4dAgAWAgABAAYJMBeyNACRAQACAAMJJw3ORACiAAAAAA==.',
Ru='Rubywolf:BAAALgAECgMJAwABLgAECggJGwAhALAWAA==.Rukkis:BAABLgAECn8VAAMmAAYJHByvEQCQAQAmAAYJHByvEQCQAQAnAAEJjQmGEwAyAAAAAA==.Rumi:BAACLgAFFH8KAAIGAAMJaBk0AwDZAAAGAAMJaBk0AwDZAAAuAAQKfzcAAgYACQlPH5EBAJsCAAYACQlPH5EBAJsCAAAA.',
Ry='Ryeekan:BAABLgAECn8VAAIVAAcJkRGPMwB/AQAVAAcJkRGPMwB/AQAAAA==.',
Sa='Saaconse:BAAALgADCgcJBwAAAA==.Saata:BAAALgAECgEJAQAAAA==.Sabrosura:BAABLgAECn8eAAIJAAgJ7hXNOgCWAQAJAAgJ7hXNOgCWAQAAAA==.Saelena:BAAALgADCgEJAQAAAA==.Sancha:BAAALgADCgQJBAAAAA==.Sanosagara:BAABLgAECn8jAAIYAAgJ9hWsDwDzAQAYAAgJ9hWsDwDzAQAAAA==.Saps:BAAALgADCgIJAgAAAA==.Saraya:BAAALgAECgIJAwAAAA==.Sarithon:BAAALgADCgMJAwAAAA==.Saru:BAAALgADCgkJDQAAAA==.Saruta:BAACLgAFFH8HAAMNAAMJywblJQCNAAANAAIJdgjlJQCNAAAMAAEJdQMnHABAAAAuAAQKfx4AAw0ACAk7GfArAAUCAA0ABwk+G/ArAAUCAAwABQmqDwkWAE4BAAAA.Sath:BAAALgADCgQJBAAAAA==.Sathari:BAABLgAECn8gAAIRAAgJJhOpLgB8AQARAAgJJhOpLgB8AQAAAA==.Satsuki:BAAALgAECgYJDAABLgAFFAMJCgARAGgbAA==.',
Sc='Schaden:BAAALgAECgEJAQABLgAECggJFAAEAAIhAA==.',
Se='Sekk:BAABLgAECn8xAAIJAAgJIB+tEAB1AgAJAAgJIB+tEAB1AgAAAA==.Selexi:BAAALgADCgYJEAAAAA==.Sereya:BAAALgADCgQJBAABLgADCgcJBgAHAAAAAA==.Sesshanmaru:BAAALgADCgEJAQAAAA==.',
Sg='Sgáil:BAAALgADCgkJCwAAAA==.',
Sh='Shaddai:BAAALgADCgcJFwAAAA==.Shadeofdark:BAABLgAECn8rAAIiAAcJCh4+CAAQAgAiAAcJCh4+CAAQAgAAAA==.Shadoshiftt:BAABLgAECn8aAAMhAAcJAwnUMgDFAAAhAAYJKQfUMgDFAAAEAAcJNgLrlwCeAAAAAA==.Shadowstar:BAAALgADCggJBwAAAA==.Shamwowee:BAAALgADCgkJIQAAAA==.Shamzee:BAACLgAFFH8FAAMFAAIJRg5fMgB8AAAFAAIJRg5fMgB8AAAeAAEJrQJYLwA/AAAuAAQKfx4AAgUACAkoGd4SACACAAUACAkoGd4SACACAAAA.Shandalf:BAAALgAECgQJDwAAAA==.Shintok:BAAALgADCgUJBQAAAA==.Shuddarun:BAACLgAFFH8VAAIVAAUJiyKVBACYAQAVAAUJiyKVBACYAQAuAAQKfyoAAhUACAmXJcQDAFQDABUACAmXJcQDAFQDAAAA.',
Si='Sidera:BAAALgADCgQJAgABLgADCgcJDQAHAAAAAA==.Sify:BAAALgADCgYJBgAAAA==.Simn:BAABLgAECn8UAAIVAAcJohjiKQCpAQAVAAcJohjiKQCpAQAAAA==.Sindraesong:BAAALgAECggJEgAAAA==.Sinfulpirate:BAAALgADCgQJBAAAAA==.Siyeigon:BAAALgAECgIJAgAAAA==.',
Sk='Skrai:BAAALgAECgYJCgABLgAECggJFgAPABgdAA==.',
Sl='Slayvylora:BAACLgAFFH8SAAIJAAUJ9xHNDQA8AQAJAAUJ9xHNDQA8AQAuAAQKfy8AAwkACAmjI+cKAK4CAAkACAmjI+cKAK4CAAoABQmWB2puAMEAAAAA.Sleep:BAAALgAECgQJBAABLgAFFAIJBQAoAG8LAA==.Slughorn:BAAALgADCgMJAwAAAA==.',
Sm='Smallholy:BAAALgAECgIJBAAAAA==.Smellgripson:BAAALgAECgIJAgAAAA==.',
Sn='Sneakymoth:BAAALgAECgUJDQABLgAECgcJEwAHAAAAAA==.Sniff:BAABLgAECn8hAAILAAgJphsQIAArAgALAAgJphsQIAArAgAAAA==.Snookums:BAABLgAECn8qAAIRAAcJjxnWHwDJAQARAAcJjxnWHwDJAQAAAA==.',
So='Soulomon:BAAALgAECggJEAAAAA==.Soulsarisen:BAAALgAECgYJDwAAAA==.',
Sp='Spanki:BAAALgADCgkJEAAAAA==.Spellteaser:BAABLgAECn8UAAILAAYJOhkXuQBvAQALAAYJOhkXuQBvAQAAAA==.Spicymaker:BAABLgAECn8bAAIMAAcJCSDAAgCNAgAMAAcJCSDAAgCNAgAAAA==.Spiritual:BAAALgADCgIJAgAAAA==.',
St='Starar:BAAALgAECgMJCQAAAA==.Steelheart:BAAALgAECgEJBQAAAA==.Steviathan:BAAALgADCgQJBAAAAA==.Stolensøul:BAAALgADCgcJDAAAAA==.Strifewood:BAABLgAECn8UAAISAAcJGxseDwCAAQASAAcJGxseDwCAAQAAAA==.Stumper:BAABLgAECn8ZAAIhAAYJzxyRFwB/AQAhAAYJzxyRFwB/AQAAAA==.',
Su='Sugondese:BAAALgAECgQJBgAAAA==.Summêr:BAAALgAECgYJCwAAAA==.Suri:BAAALgAECgUJCgAAAA==.Sux:BAABLgAECn8YAAIaAAcJJA5WEgDjAAAaAAcJJA5WEgDjAAAAAA==.',
Sy='Sybrina:BAAALgAECgYJDwAAAA==.Sylvia:BAAALgADCgcJBgAAAA==.Synevra:BAAALgADCggJFgAAAA==.Syngeance:BAABLgAECn8bAAIVAAYJYwY5ZADkAAAVAAYJYwY5ZADkAAAAAA==.Synèsterwolf:BAAALgAECgIJAwABLgAECggJGwAhALAWAA==.',
['Sí']='Síf:BAAALgAECgYJCAAAAA==.',
Ta='Tabernacle:BAAALgAECgUJBQAAAA==.Tamamò:BAABLgAECn8VAAIYAAcJ1BGKKABvAQAYAAcJ1BGKKABvAQAAAA==.Tarrok:BAAALgADCgMJBwAAAA==.',
Te='Tealleth:BAAALgADCgMJAwAAAA==.Telana:BAAALgADCgkJGwAAAA==.Tepache:BAAALgADCgEJAQAAAA==.Tequitos:BAABLgAECn8UAAMJAAcJIRDucAALAQAJAAYJnwvucAALAQAKAAYJWQoTXwAAAQAAAA==.Teranin:BAABLgAECn8UAAIhAAcJPAjFKAD8AAAhAAcJPAjFKAD8AAAAAA==.',
Tf='Tfortyone:BAAALgAECgQJBwAAAA==.',
Th='Tharbad:BAAALgADCgEJBQAAAA==.Thchosen:BAAALgAECgIJAgAAAA==.Thorae:BAAALgADCgEJAQAAAA==.Thorias:BAACLgAFFH8IAAILAAMJgBoPPwARAQALAAMJgBoPPwARAQAuAAQKfzcAAgsACQk1JDEDAE0DAAsACQk1JDEDAE0DAAAA.',
Ti='Tiren:BAAALgAECgYJDQAAAA==.',
To='Torag:BAAALgAECgQJBAAAAA==.Torment:BAABLgAECn8xAAISAAgJXxuIBwAVAgASAAgJXxuIBwAVAgAAAA==.',
Tr='Trepania:BAACLgAFFH8PAAIQAAUJ4geWCAA7AQAQAAUJ4geWCAA7AQAuAAQKfywAAhAACAkMGs8WACUCABAACAkMGs8WACUCAAAA.Tristén:BAAALgAECgIJAgAAAA==.Trogdoor:BAAALgAECgEJAQAAAA==.Trollycarp:BAABLgAECn8VAAMJAAgJrgR8eAD7AAAJAAgJbQN8eAD7AAAIAAEJrQvGNQAiAAAAAA==.Truvie:BAAALgADCgkJCwAAAA==.',
Tu='Tumbler:BAAALgAECgcJEwAAAA==.Tumbles:BAAALgAECgUJBwAAAA==.Tumni:BAABLgAECn8bAAMFAAYJdAxZQAACAQAFAAYJdAxZQAACAQAeAAEJzgHklQAeAAAAAA==.',
Tw='Twinkletoes:BAAALgADCgIJAgAAAA==.Twylah:BAAALgADCgIJAgAAAA==.',
['Tá']='Táelah:BAABLgAECn8VAAIUAAgJ+RAwDgDEAQAUAAgJ+RAwDgDEAQAAAA==.',
Ul='Ulnuk:BAACLgAFFH8IAAIFAAMJzRIwIgDPAAAFAAMJzRIwIgDPAAAuAAQKfyMAAgUACAmhIIsKAIUCAAUACAmhIIsKAIUCAAAA.Ulster:BAAALgAECgEJAQAAAA==.',
Un='Unidus:BAAALgAECgYJBwAAAA==.',
Up='Uphellyaa:BAAALgADCgUJBQABLgAECgQJBAAHAAAAAA==.',
Va='Vadka:BAAALgAECgQJBgAAAA==.Vaexxi:BAAALgAECgUJBgAAAA==.Vaha:BAAALgAECgQJBgAAAA==.Vairian:BAABLgAECn8WAAIiAAYJjw6EGQATAQAiAAYJjw6EGQATAQAAAA==.Valsavis:BAABLgAECn8vAAIGAAgJZxyzAwAKAgAGAAgJZxyzAwAKAgAAAA==.Vampirä:BAABLgAECn8ZAAIEAAYJUwQ+iQDCAAAEAAYJUwQ+iQDCAAAAAA==.Varactor:BAAALgAECgMJAwAAAA==.Vasarah:BAAALgAECgEJAQAAAA==.Vashidan:BAABLgAECn8YAAIZAAgJ7iAxCAD3AgAZAAgJ7iAxCAD3AgAAAA==.',
Ve='Velenar:BAAALgADCgIJAgAAAA==.Velisandre:BAAALgADCgcJIgAAAA==.Vellagosa:BAAALgAECgQJBwAAAA==.Verulan:BAAALgAECgYJDAAAAA==.Vexeh:BAAALgAECgMJBAAAAA==.Vexomous:BAAALgAECgUJDwAAAA==.',
Vi='Vierilan:BAAALgADCgcJBwAAAA==.Vikss:BAABLgAECn8YAAMVAAgJsQuhQgBFAQAVAAgJsQuhQgBFAQAUAAYJXQQqHQAFAQAAAA==.Viledk:BAAALgAECgUJBgAAAA==.Viserian:BAAALgAECgMJAwAAAA==.Vivien:BAAALgADCgYJBgABLgADCgcJBgAHAAAAAA==.',
Vl='Vll:BAABLgAECn8gAAIjAAcJ6x9sCABYAgAjAAcJ6x9sCABYAgAAAA==.',
Vo='Voidmayne:BAABLgAECn8tAAIJAAgJSA4+QACFAQAJAAgJSA4+QACFAQAAAA==.Vongogh:BAAALgADCgEJAQAAAA==.Vonhelsing:BAAALgAECgUJBAAAAA==.Vorcan:BAAALgADCgMJBgAAAA==.Vorenius:BAAALgADCgEJAQAAAA==.',
Vr='Vrel:BAAALgADCggJBwAAAA==.',
Vy='Vyv:BAABLgAECn8UAAIeAAcJswVMLwD3AAAeAAcJswVMLwD3AAAAAA==.Vyvboo:BAAALgADCgcJBwAAAA==.Vyvish:BAAALgADCgUJBQAAAA==.',
['Vö']='Vöid:BAABLgAECn8ZAAIRAAYJEhwoMQByAQARAAYJEhwoMQByAQAAAA==.',
Wa='Warlogic:BAAALgAECgQJBAAAAA==.Wayadra:BAABLgAECn8XAAQfAAkJjyETAgAZAwAfAAkJjyETAgAZAwAgAAcJSQTdJgDrAAAOAAEJlgq/SQAvAAAAAA==.',
We='Weiand:BAAALgAECgYJEgAAAA==.Welil:BAAALgAECgUJCwAAAA==.',
Wh='Whachah:BAAALgAECgQJCAAAAA==.Whatami:BAABLgAECn8fAAQBAAgJPBToRQD5AQABAAgJPBToRQD5AQACAAIJ7w93VwBoAAADAAEJAAANMQA8AAAAAA==.Wholemilk:BAABLgAECn8WAAIRAAcJlBwFHADhAQARAAcJlBwFHADhAQAAAA==.',
Wi='Wilhellena:BAABLgAECn8tAAIQAAgJ0h9iBADPAgAQAAgJ0h9iBADPAgAAAA==.Wilhellfu:BAAALgAECgIJAgAAAA==.Winariel:BAAALgAECgIJAgABLgAECgYJCwAHAAAAAA==.Wisteria:BAAALgAECgEJAQABLgABCgEJAQAHAAAAAA==.',
Wr='Wrëckagë:BAAALgAECgcJEwAAAA==.',
Wu='Wumbo:BAAALgAECgYJBwAAAA==.',
Xa='Xaiea:BAAALgADCgcJBwAAAA==.Xalatath:BAAALgAECgEJAQAAAA==.Xaldred:BAABLgAECn8fAAIBAAgJlxDNLgCoAQABAAgJlxDNLgCoAQABLgAECgkJIQANAOcQAA==.Xandir:BAABLgAECn8dAAIIAAUJARU9GgDDAAAIAAUJARU9GgDDAAAAAA==.Xarhunt:BAAALgAECgMJAwAAAA==.Xaric:BAABLgAECn8hAAIEAAgJdxncIwCpAQAEAAgJdxncIwCpAQAAAA==.',
Xe='Xella:BAAALgAECgQJBAAAAA==.',
Xy='Xyp:BAAALgAECgEJAQABLgAECgYJDAAHAAAAAA==.',
Yi='Yiago:BAAALgAECgQJBgAAAA==.',
Yo='Youknow:BAAALgAECgEJAQAAAA==.',
Yu='Yumiisaki:BAAALgAECgQJBAAAAA==.',
Za='Zahel:BAAALgADCgYJEgAAAA==.Zangbus:BAAALgADCgcJFAAAAA==.Zany:BAAALgADCgIJAgAAAA==.Zaranorinn:BAABLgAECn8WAAIJAAYJowhpfQDxAAAJAAYJowhpfQDxAAAAAA==.Zaxhdk:BAEALgAECgYJEQAAAA==.',
Ze='Zedex:BAAALgADCgcJCAABLgADCggJDQAHAAAAAA==.Zedru:BAAALgADCggJDQAAAA==.Zenstormer:BAAALgADCgQJBAABLgADCgkJDQAHAAAAAA==.Zephril:BAAALgADCgEJAQAAAA==.Zerfällt:BAAALgADCgYJCwAAAA==.Zerrus:BAAALgAECgYJEAAAAA==.',
Zh='Zhoryn:BAAALgAECgYJDQAAAA==.',
Zi='Zilvra:BAABLgAECn8aAAIFAAgJwBj+FQADAgAFAAgJwBj+FQADAgAAAA==.Zinrar:BAABLgAECn8aAAIcAAcJGRhMOACYAQAcAAcJGRhMOACYAQAAAA==.Zipagain:BAAALgADCgQJBAAAAA==.Ziparoo:BAABLgAECn8lAAILAAcJ0QXteAAfAQALAAcJ0QXteAAfAQAAAA==.Zittizle:BAAALgAECgEJAQAAAA==.',
Zr='Zraven:BAABLgAECn8aAAIUAAcJphVDEwCBAQAUAAcJphVDEwCBAQAAAA==.',
Zu='Zushi:BAAALgADCgEJAQAAAA==.',
['Äl']='Älphawolf:BAABLgAECn8bAAMhAAgJsBbIEgCwAQAhAAgJsBbIEgCwAQAEAAIJdgiWhQBIAAAAAA==.',
['Ðê']='Ðêmønicßløøð:BAAALgAECggJDwAAAA==.',
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

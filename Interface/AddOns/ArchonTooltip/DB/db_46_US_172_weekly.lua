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

local lookup = {'Warrior-Protection','Shaman-Elemental','Druid-Restoration','Paladin-Holy','Mage-Arcane','Monk-Brewmaster','Paladin-Retribution','Evoker-Preservation','Priest-Shadow','Unknown-Unknown','Hunter-BeastMastery','DeathKnight-Unholy','Rogue-Assassination','Rogue-Subtlety','Mage-Frost','Druid-Balance','Warrior-Fury','Shaman-Enhancement','Paladin-Protection','Priest-Holy','DemonHunter-Havoc','DemonHunter-Devourer','DemonHunter-Vengeance','Monk-Windwalker','Monk-Mistweaver','Warlock-Demonology','Warlock-Destruction','DeathKnight-Blood','Evoker-Augmentation','Evoker-Devastation','Hunter-Marksmanship','Shaman-Restoration','Hunter-Survival','Priest-Discipline','Warrior-Arms',}
local provider = {region='US',realm='Perenolde',name='US',type='weekly',zone=46,date='2026-04-24',data={Ad='Adrador:BAAALgAECgYJEAAAAA==.Adrenaline:BAABLgAECn8qAAIBAAgJKSRTAADbAgABAAgJKSRTAADbAgAAAA==.',
Ae='Aelik:BAAALgAECgcJDwAAAA==.',
Ah='Ahkimbo:BAAALgADCgUJBQAAAA==.',
Al='Alayssa:BAAALgAECgYJEgAAAA==.Alda:BAAALgADCgMJAwAAAA==.Allarius:BAAALgAECgEJAQAAAA==.Allioops:BAAALgADCgUJBQAAAA==.Alnima:BAEBLgAECn8VAAICAAgJLgiyOQBoAQACAAgJLgiyOQBoAQAAAA==.',
Am='Amilee:BAAALgAECgMJAwAAAA==.Amishhunter:BAAALgADCgEJAQAAAA==.Amoondai:BAAALgAECgYJDgAAAA==.Amoondrin:BAABLgAECn8fAAIDAAkJjATRaQAWAQADAAkJjATRaQAWAQAAAA==.Amplifier:BAAALgADCgUJBQAAAA==.',
An='Antichurch:BAAALgADCgEJAQAAAA==.Antregon:BAAALgADCgQJBwAAAA==.',
Ar='Araviin:BAAALgAECgYJBgAAAA==.Arazen:BAAALgADCgcJDQAAAA==.Arkride:BAAALgAECgEJAQAAAA==.Arnadaz:BAAALgADCgEJAQABLgAFFAIJBgAEALYgAA==.Arthia:BAAALgAECgQJCgAAAA==.Arvidpally:BAAALgADCgkJFQAAAA==.',
As='Ashmehameha:BAAALgADCgQJAgAAAA==.Asoosimov:BAAALgADCgEJAQAAAA==.',
At='Atredes:BAAALgADCggJCgAAAA==.Attima:BAABLgAECn8bAAIFAAgJIQjCBwCCAQAFAAgJIQjCBwCCAQAAAA==.',
Au='Aurøra:BAAALgADCgMJAwAAAA==.Auspex:BAAALgAECgYJDwAAAA==.',
Av='Avaryn:BAABLgAECn8pAAIDAAgJQCB9AwBnAgADAAgJQCB9AwBnAgAAAA==.',
Ba='Babavoss:BAAALgAECgkJAQAAAA==.Badarack:BAAALgAECgMJBgABLgAECggJIwAGAHchAA==.Badarackie:BAABLgAECn8jAAIGAAgJdyGeCQDvAgAGAAgJdyGeCQDvAgAAAA==.Badash:BAAALgAECgYJDwAAAA==.Bahamuth:BAABLgAECn8dAAIHAAgJABm2QQAgAgAHAAgJABm2QQAgAgAAAA==.Barbattos:BAABLgAECn8pAAIIAAgJxCN0AADvAgAIAAgJxCN0AADvAgAAAA==.Barragon:BAAALgADCgcJBwAAAA==.',
Be='Bethollbrew:BAAALgAECgQJBwAAAA==.Bexley:BAAALgAECgYJBwAAAA==.',
Bi='Biggerbunny:BAABLgAECn8cAAIJAAgJbw8+BgCiAQAJAAgJbw8+BgCiAQAAAA==.',
Bl='Blackjax:BAAALgADCgEJAQAAAA==.Blargle:BAAALgAECgUJCQAAAA==.Bleubahlz:BAAALgADCgcJBwABLgAECgMJAwAKAAAAAA==.Bloodrake:BAABLgAECn8gAAILAAkJ4RqrDQDRAgALAAkJ4RqrDQDRAgAAAA==.Bloodreyne:BAAALgADCgEJAgAAAA==.',
Bo='Boahan:BAAALgAECgIJAgAAAA==.Boggart:BAAALgAECgEJAQAAAA==.Bohein:BAAALgADCgEJAQAAAA==.Bownafiedba:BAAALgADCgUJBQAAAA==.',
Br='Braneour:BAABLgAECn8dAAMEAAgJVAiWFAD6AAAEAAcJsgWWFAD6AAAHAAMJjAuRRQByAAAAAA==.Browel:BAAALgAECgYJEQAAAA==.Bruen:BAAALgAECgYJBgAAAA==.',
Bu='Bubbloseven:BAAALgADCgkJEwAAAA==.Budank:BAAALgADCgMJAwAAAA==.Bumm:BAAALgAECgYJCAAAAA==.Bustybubbles:BAAALgADCgYJBgAAAA==.',
Bz='Bzspy:BAAALgAFFAEJAQAAAA==.',
Ca='Caalin:BAAALgAECgEJAgAAAA==.Cabooselul:BAAALgADCgYJBgAAAA==.Calibre:BAAALgAECgYJEwAAAA==.Calyptus:BAAALgAECgYJDAAAAA==.Caprious:BAABLgAECn8pAAIMAAgJ8SIQAgClAgAMAAgJ8SIQAgClAgAAAA==.Capylaura:BAAALgAECgUJCgAAAA==.Caratine:BAAALgAECgQJBwAAAA==.Cassandrar:BAABLgAECn8hAAMNAAkJiyIIAQA5AwANAAgJVSMIAQA5AwAOAAYJlRm2EAC9AAAAAA==.Cat:BAAALgADCgUJBQAAAA==.Cattlelac:BAAALgADCgUJCAAAAA==.Caymus:BAAALgAECgQJBAAAAA==.',
Ce='Celìa:BAAALgAECgYJDAAAAA==.Cess:BAAALgAECgEJAgAAAA==.',
Ch='Chema:BAAALgAECgEJAQABLgAFFAIJBgAEALYgAA==.Chestylarue:BAAALgADCgkJHgAAAA==.Chfgaribaldi:BAAALgADCggJDgAAAA==.Chills:BAAALgAECgcJEQAAAA==.Chosen:BAABLgAECn8VAAIHAAYJRBdyYgC+AQAHAAYJRBdyYgC+AQABLgAECgkJJQAPAHkcAA==.Christy:BAAALgADCgMJAwAAAA==.Chugg:BAAALgAECgYJDgAAAA==.',
Co='Coffeedemon:BAAALgADCgEJAQAAAA==.Coldslappins:BAAALgAECgIJAwAAAA==.Convoke:BAABLgAECn8ZAAIQAAcJDSApFgBeAgAQAAcJDSApFgBeAgAAAA==.',
Cu='Curtastrophe:BAABLgAECn8gAAIPAAkJwRkYOACUAgAPAAkJwRkYOACUAgAAAA==.Curticus:BAAALgADCgMJAwAAAA==.Curtnought:BAAALgADCgIJAgAAAA==.',
['Cé']='Cérnùnnøs:BAAALgAECgEJAQAAAA==.',
Da='Daelanos:BAABLgAECn8UAAIRAAYJhBYVPwCoAQARAAYJhBYVPwCoAQAAAA==.Dalinar:BAAALgADCgcJCgAAAA==.Darska:BAAALgADCgYJBgABLgADCgkJHgAKAAAAAA==.',
De='Deadtauren:BAAALgADCgQJBQAAAA==.Deathdemon:BAAALgADCgcJBwAAAA==.Deathisreal:BAAALgADCgMJAwABLgAECgEJAQAKAAAAAA==.Decimated:BAABLgAECn8WAAIMAAgJgB52BABMAgAMAAgJgB52BABMAgABLgAECgkJJQAPAHkcAA==.Demon:BAAALgAECgEJAgAAAA==.Dempkiston:BAAALgADCgcJCAAAAA==.Denable:BAAALgAECgEJAwAAAA==.Destro:BAAALgAECgYJEAABLgAECggJGgASAAcTAA==.Dethadin:BAAALgADCgcJBwAAAA==.',
Di='Dirteemike:BAAALgADCgMJAwAAAA==.Discoflurry:BAAALgAECgUJBgABLgAFFAIJBgABACofAA==.Dizzyfist:BAAALgAECgUJBwAAAA==.',
Do='Dogaz:BAAALgADCgIJAgAAAA==.Donori:BAAALgAECgQJCwAAAA==.Dorcath:BAAALgADCggJCAABLgAECgYJFAARAIQWAA==.',
Dr='Dragan:BAAALgADCgIJAgAAAA==.Dragonias:BAAALgAECgQJCAAAAA==.Dresel:BAABLgAECn8WAAMTAAcJyhDOHQAbAQAHAAYJrQ7glgBPAQATAAUJqBPOHQAbAQABLgAFFAYJEQALAE4iAA==.Drinny:BAABLgAECn8WAAIUAAgJoAPMQAA2AQAUAAgJoAPMQAA2AQAAAA==.Drqueenisin:BAAALgADCggJEwAAAA==.Druido:BAAALgADCgMJAwAAAA==.',
Du='Duerek:BAAALgADCgUJDAAAAA==.',
['Dè']='Dèaths:BAAALgAECgYJEAAAAA==.',
Ea='Earthangel:BAAALgAECgEJAwAAAA==.',
Ei='Eine:BAABLgAECn8dAAILAAgJcA+OLwDzAQALAAgJcA+OLwDzAQAAAA==.Eitherwind:BAAALgAECgUJBwABLgAECgUJBwAKAAAAAA==.',
El='Eldergreen:BAABLgAECn8aAAIDAAYJ9AtFGQDwAAADAAYJ9AtFGQDwAAAAAA==.Eldest:BAAALgADCgUJBQAAAA==.Elfwine:BAAALgAECgEJAgAAAA==.Elindria:BAABLgAECn8ZAAQVAAcJuSVODACcAgAVAAcJuSVODACcAgAWAAQJUhqyewA0AQAXAAIJKyC0HwCIAAAAAA==.Elminstir:BAAALgAECgYJCgAAAA==.Elynisa:BAAALgAECgEJAQAAAA==.Elysian:BAABLgAECn8VAAMYAAgJrxsdFgA4AgAYAAcJWRsdFgA4AgAZAAgJGxWzIQCnAQAAAA==.',
Em='Emogo:BAAALgADCgUJCQAAAA==.',
En='Enforcer:BAAALgADCgQJBgAAAA==.Enlightened:BAAALgAECgQJBQAAAA==.',
Er='Erendora:BAAALgAECgUJEgAAAA==.Eridar:BAAALgAECgYJBgAAAA==.Erizhal:BAAALgAECgQJBwAAAA==.Erodora:BAAALgADCgEJAQAAAA==.',
Ev='Eva:BAAALgADCgEJAgAAAA==.Eviae:BAAALgAECgEJAwAAAA==.Evillure:BAAALgAECgIJAgAAAA==.',
Fa='Falan:BAAALgAECgYJCQAAAA==.Fatherjoe:BAAALgADCgYJBgAAAA==.Fayze:BAEALgAECgYJBgABLgAECgYJCgAKAAAAAA==.',
Fe='Felbreaker:BAAALgAECgUJBQAAAA==.Feår:BAABLgAECn8VAAMaAAcJTg2hMQC/AAAaAAYJIwqhMQC/AAAbAAMJ3Q8GSwCMAAAAAA==.',
Fi='Finley:BAAALgADCgYJBgAAAA==.Fircane:BAAALgADCgQJBAAAAA==.',
Fl='Flane:BAAALgAECgQJBgABLgAFFAUJDgABALEhAA==.Flem:BAAALgAECgMJBAAAAA==.Flexdruid:BAAALgADCgUJCwAAAA==.',
Fo='Foog:BAAALgADCgkJDQAAAA==.',
Fr='Fragil:BAAALgAECgYJEwAAAA==.Frostmane:BAABLgAECn8cAAMcAAgJgRm+DQAxAgAcAAcJ/hy+DQAxAgAMAAYJIwbyPQB0AAAAAA==.Frostynug:BAAALgADCgYJBgAAAA==.',
Fu='Furbyn:BAAALgADCgIJAgAAAA==.',
Ga='Galena:BAAALgAECgQJBwAAAA==.Gallamier:BAAALgADCgEJAQAAAA==.Gamerinator:BAAALgADCgcJCwAAAA==.',
Ge='Geshtal:BAAALgAECgQJBgAAAA==.',
Gi='Girion:BAAALgAECgEJAwAAAA==.Girliepop:BAAALgAECgEJAQAAAA==.',
Gl='Glaiven:BAEBLgAECn8oAAIWAAgJdCHaAwBaAgAWAAgJdCHaAwBaAgAAAA==.Glyr:BAAALgADCgUJBQAAAA==.',
Go='Gorgrin:BAAALgAECgMJAwAAAA==.',
Gr='Greenback:BAAALgADCgYJCwAAAA==.Greentotes:BAABLgAECn8oAAMdAAgJcCGRAQBlAgAdAAgJcCGRAQBlAgAeAAQJdgYpLgCoAAAAAA==.',
Gu='Gunter:BAAALgAECgMJAwABLgAECgkJJQAPAHkcAA==.Gura:BAAALgADCgEJAQAAAA==.Gurnee:BAAALgADCgcJDQABLgAECgYJDQAKAAAAAA==.Guthix:BAAALgAECgUJBgAAAA==.',
['Gê']='Gêm:BAAALgAECgYJEgAAAA==.',
['Gï']='Gïmlï:BAAALgADCgMJAwAAAA==.',
Ha='Haildydra:BAAALgAECgEJAQABLgAECgcJCAAKAAAAAA==.Halnan:BAAALgADCgEJAQABLgAECgYJEwAKAAAAAA==.Harkanum:BAABLgAECn8gAAMIAAkJzwhrIQBwAQAIAAkJzwhrIQBwAQAdAAQJrxPgPgDuAAAAAA==.Hatebreéd:BAAALgAECgEJAQAAAA==.',
He='Hector:BAAALgAFFAEJAQAAAA==.Helloagain:BAACLgAFFH8GAAIPAAMJKRP2LgD6AAAPAAMJKRP2LgD6AAAuAAQKfxcAAg8ABgm8ISldACMCAA8ABgm8ISldACMCAAAA.Herryknutsak:BAAALgAECgEJAQAAAA==.Hestonater:BAAALgADCggJCgAAAA==.',
Hi='Hidethetotem:BAAALgAECgQJCAAAAA==.Hightops:BAAALgAECggJDAAAAA==.Hikari:BAABLgAECn8cAAIHAAgJyB3nLABwAgAHAAgJyB3nLABwAgAAAA==.',
Ho='Holeliness:BAAALgAECggJEwAAAA==.Holybackshot:BAAALgAECgMJBQAAAA==.Holydisco:BAAALgADCgcJCQAAAA==.Holyhide:BAAALgADCgUJBQAAAA==.Holyspike:BAAALgAECgQJBwAAAA==.Holytard:BAAALgADCgYJBgAAAA==.Holytaren:BAAALgADCggJDQAAAA==.Holytickles:BAABLgAECn8YAAIJAAgJ9RtOAwAEAgAJAAgJ9RtOAwAEAgABLgAFFAQJBwAaAHcUAA==.Holytotem:BAAALgADCggJCAAAAA==.Homerr:BAAALgAECgQJBwAAAA==.Honiahaka:BAABLgAECn8dAAILAAgJ8gsSPwCzAQALAAgJ8gsSPwCzAQAAAA==.Hottcakes:BAAALgADCgIJAgABLgAFFAQJBwAaAHcUAA==.',
Hu='Huckster:BAAALgAECgYJDwAAAA==.Humanoidholy:BAABLgAECn8fAAMHAAgJXSQ3CQBIAwAHAAgJXSQ3CQBIAwATAAEJbgXTTQAYAAABLgAECggJGgAWAO4gAA==.Humanoidhunt:BAAALgAECgIJAgABLgAECggJGgAWAO4gAA==.Humanoidvoid:BAABLgAECn8aAAQWAAcJ7iB2MAA5AgAWAAcJ6SB2MAA5AgAVAAMJOBk9TgC0AAAXAAEJTAX5LQAoAAAAAA==.',
Hy='Hydrasoul:BAAALgAECgcJBwABLgAECgcJCAAKAAAAAA==.',
Ic='Icicle:BAAALgADCgIJAgAAAA==.',
Id='Idunasil:BAAALgADCgIJAgAAAA==.',
Ih='Ihatemustard:BAAALgAECgYJDQAAAA==.',
Il='Illethan:BAAALgADCgYJBgAAAA==.',
In='Inoru:BAAALgADCgIJAgAAAA==.Insanity:BAAALgAECgQJBQAAAA==.',
Ir='Irmaline:BAAALgAECgQJBwAAAA==.',
It='Ithurtshuh:BAAALgAECgEJAQAAAA==.Itsmaam:BAAALgAECgMJBAAAAA==.Itzcannibal:BAABLgAECn8eAAMLAAgJGhl+CQDQAQALAAgJGhl+CQDQAQAfAAIJ1QraeQBaAAAAAA==.',
Ja='Jabbawockie:BAAALgAECgkJAgAAAA==.Jakoby:BAAALgADCggJHQABLgAECgYJEwAKAAAAAA==.Jandrisel:BAAALgAECgEJAQAAAA==.Jayzich:BAAALgADCgQJBwAAAA==.',
Je='Jeffee:BAAALgAECgIJBAAAAA==.Jequalsjosh:BAABLgAECn8iAAINAAgJQR2mAgDDAgANAAgJQR2mAgDDAgAAAA==.Jerk:BAAALgAECgQJBAAAAA==.Jerp:BAAALgADCggJFgAAAA==.Jesper:BAABLgAECn8gAAIgAAkJRBjTFwBXAgAgAAkJRBjTFwBXAgAAAA==.Jetz:BAAALgAECgEJAQAAAA==.Jezelle:BAABLgAECn8fAAIaAAgJChoJNgA0AgAaAAgJChoJNgA0AgAAAA==.',
Ji='Jilara:BAAALgAECgUJDQAAAA==.Jimmyjim:BAAALgAECgMJBgAAAA==.Jingying:BAAALgADCgMJAwAAAA==.',
Jo='Johnny:BAAALgADCgQJBAAAAA==.',
Jp='Jpepps:BAABLgAECn8ZAAMaAAcJCBCPbQCFAQAaAAcJxg+PbQCFAQAbAAMJxwjhRQCeAAAAAA==.',
Jr='Jrose:BAAALgADCgIJAgAAAA==.',
['Jæ']='Jækobÿ:BAAALgADCgcJEgABLgAECgYJEwAKAAAAAA==.',
Ka='Kaiatra:BAAALgAECgQJBwAAAA==.Katare:BAAALgAECgMJAwAAAA==.Kaulder:BAAALgADCgUJBQAAAA==.Kaìju:BAAALgAECgQJDAAAAA==.',
Ke='Kellytgt:BAAALgAECgYJEQAAAA==.Kev:BAAALgADCgUJBQAAAA==.',
Ki='Kilaura:BAAALgAECgUJBQAAAA==.Kilmandaros:BAAALgADCgUJBQAAAA==.Kippi:BAAALgAECgQJBAAAAA==.',
Ko='Korhina:BAABLgAECn8gAAIBAAkJZyURAQCMAwABAAkJZyURAQCMAwAAAA==.Korobas:BAAALgADCgcJGgAAAA==.Koru:BAAALgADCggJCQABLgAECgIJAgAKAAAAAA==.Kosumi:BAAALgADCggJDQAAAA==.',
Kr='Kronic:BAAALgADCgcJDAAAAA==.',
Ku='Kuroyukihime:BAABLgAECn8cAAIPAAgJ6xgJSwBWAgAPAAgJ6xgJSwBWAgAAAA==.Kuwaii:BAAALgAECgYJDAABLgAECggJGQAQAA0gAA==.',
Ky='Kyarina:BAAALgAECgEJAQABLgAECgYJDwAKAAAAAA==.Kylis:BAAALgAECgMJAwAAAA==.Kyna:BAAALgAECgYJDwAAAA==.Kyross:BAAALgADCgEJAQAAAA==.',
La='Lashela:BAAALgAECgUJCQAAAA==.Laughter:BAAALgAECgQJBwAAAA==.Laurana:BAAALgADCgIJAgAAAA==.Lazulie:BAAALgAECgMJAwAAAA==.',
Le='Leansipper:BAAALgAECgMJBAAAAA==.Levoker:BAAALgAECgQJBAAAAA==.Lexapayne:BAAALgADCgEJAQABLgAECgcJHgAaAIAKAA==.',
Li='Lighthammer:BAAALgADCgEJAQAAAA==.Lilandra:BAAALgADCgkJHgABLgADCgkJHgAKAAAAAA==.Lillianaxe:BAAALgADCgkJFAAAAA==.Lilyvain:BAAALgADCgMJAwAAAA==.Lireal:BAABLgAECn8aAAIEAAcJHSDIAgBlAgAEAAcJHSDIAgBlAgAAAA==.Listerine:BAAALgADCgQJBAABLgAECgUJCwAKAAAAAA==.Livnod:BAAALgADCgkJFQAAAA==.',
Lo='Lorine:BAABLgAECn8eAAITAAkJUBVoDQDwAQATAAkJUBVoDQDwAQAAAA==.Lowkie:BAAALgADCgIJAgAAAA==.',
Lu='Luckside:BAAALgADCgkJCQABLgAECgcJFQAaAE4NAA==.',
['Ló']='Lókki:BAAALgAECgUJCAAAAA==.',
Ma='Madwe:BAAALgAECgYJEgAAAA==.Magis:BAAALgADCgkJEQAAAA==.Manimetal:BAAALgAECgEJAQAAAA==.',
Me='Meeralax:BAAALgAECgUJBwAAAA==.Melizza:BAAALgADCgMJAwAAAA==.Merckel:BAABLgAECn8WAAIWAAYJKhzsEwBeAQAWAAYJKhzsEwBeAQAAAA==.',
Mi='Michello:BAAALgAECgQJBwAAAA==.Mickcowmoose:BAAALgADCgIJAgAAAA==.Millia:BAAALgAECgUJCQABLgAFFAEJAQAKAAAAAA==.Mint:BAABLgAECn8XAAIEAAYJHCb+EQCDAgAEAAYJHCb+EQCDAgAAAA==.Misstress:BAAALgAECgYJEQAAAA==.Mizen:BAAALgADCgUJBQAAAA==.',
Mo='Mogdor:BAAALgADCgUJBQAAAA==.Moonhunt:BAAALgADCgkJGQAAAA==.Moonly:BAABLgAECn8WAAIhAAYJFQ4BCAAzAQAhAAYJFQ4BCAAzAQAAAA==.Morrag:BAAALgAECgYJDQAAAA==.',
Mu='Murdumurdu:BAAALgAECgQJBgAAAA==.Murkblade:BAAALgADCgYJBgABLgAECgYJEwAKAAAAAA==.Musho:BAAALgADCgUJBQAAAA==.',
My='Myn:BAAALgAECgYJBgAAAA==.Myw:BAAALgAECgcJBwABLgAFFAUJEAAgADwXAA==.',
['Mí']='Mísfìt:BAABLgAECn8cAAMgAAkJnRTmKwDcAQAgAAkJnRTmKwDcAQACAAEJ0wX4jgApAAAAAA==.',
Na='Nakaito:BAAALgAECgQJBwABLgAECgYJEgAKAAAAAA==.Narcoleptic:BAABLgAECn8aAAMIAAgJChv2AACDAgAIAAgJChv2AACDAgAeAAQJrgVJLwCdAAAAAA==.',
Ne='Neocracy:BAAALgADCgYJCwABLgADCggJDQAKAAAAAA==.Nex:BAAALgADCgYJCAAAAA==.',
Ni='Niceshield:BAAALgAECgEJAQAAAA==.Nightmarexx:BAACLgAFFH8IAAIOAAQJgAu2BgD0AAAOAAQJgAu2BgD0AAAuAAQKfz0AAg4ACAluH8sLANkCAA4ACAluH8sLANkCAAAA.Nightsawdy:BAAALgAECgYJCQAAAA==.Nightsnake:BAAALgAECgMJAwAAAA==.Niightstorm:BAAALgAECgEJAgAAAA==.Nikwillig:BAAALgAECgMJAwAAAA==.Nilveron:BAAALgADCgcJCQAAAA==.Nitefire:BAAALgADCgMJAwAAAA==.',
Nj='Njörðr:BAAALgAECgYJDAAAAA==.',
Nt='Ntadadarknes:BAAALgAECgEJAQABLgAECgYJGgADAPQLAA==.',
Op='Opalinnas:BAABLgAECn8UAAMDAAgJ2BUiOgC9AQADAAgJ2BUiOgC9AQAQAAUJdQjkEgDNAAAAAA==.',
Oz='Ozath:BAAALgAECgIJAgAAAA==.',
Pa='Passionfruit:BAAALgAECgQJBAAAAA==.',
Pe='Peachtea:BAAALgAECgQJBgAAAA==.',
Ph='Phatshaman:BAAALgAECgYJDAAAAA==.Phæryll:BAAALgADCgUJBgAAAA==.',
Pi='Pirodeath:BAAALgAECgcJCAAAAA==.',
Po='Poisonclaw:BAAALgAECgIJAwAAAA==.Poprotonix:BAAALgAECgYJDAAAAA==.Pozessedkaos:BAAALgAECgQJBAAAAA==.',
Pr='Praecantrix:BAAALgAECgEJAQAAAA==.Prath:BAAALgADCgEJAQAAAA==.Pray:BAABLgAECn8dAAIiAAgJth6cAgA0AgAiAAgJth6cAgA0AgAAAA==.Priestyballz:BAAALgAECgYJBgAAAA==.Prodarkangel:BAABLgAECn8UAAMbAAcJBwiPKwARAQAbAAcJBwiPKwARAQAaAAIJTQQhSABQAAAAAA==.',
Pu='Pubis:BAAALgAECgEJAgAAAA==.Puckllane:BAABLgAECn8VAAIHAAcJkxtjQQAhAgAHAAcJkxtjQQAhAgAAAA==.Punkbeer:BAAALgAECgEJAQAAAA==.Punkin:BAAALgADCgYJBgAAAA==.',
Py='Pyre:BAABLgAECn8iAAIiAAkJEQxxHQCpAQAiAAkJEQxxHQCpAQABLgADCgUJBQAKAAAAAA==.',
Qu='Quefstank:BAAALgADCgUJCAAAAA==.',
Ra='Rabmaxx:BAAALgAECgYJCQAAAA==.Radren:BAAALgADCgEJAQAAAA==.Rajinazn:BAAALgADCgMJAwAAAA==.Rattchett:BAAALgADCgYJBgAAAA==.Ravenlight:BAAALgAECgYJCAAAAA==.Ravenwynnd:BAABLgAECn8XAAIjAAkJlxlwBACoAgAjAAkJlxlwBACoAgAAAA==.Raynelock:BAABLgAECn8dAAMbAAgJTAukFAClAQAbAAgJaAqkFAClAQAaAAIJtQf+CAFKAAAAAA==.Raynman:BAABLgAECn8dAAIgAAgJAhL/CQCeAQAgAAgJAhL/CQCeAQAAAA==.Razix:BAABLgAECn8bAAQdAAgJJhAaLABfAQAdAAcJGhIaLABfAQAeAAYJwAnqJgDqAAAIAAMJYwciPACJAAAAAA==.',
Re='Realist:BAAALgAECgMJBAAAAA==.Repentance:BAAALgADCgEJAQABLgAECggJGgASAAcTAA==.Revealed:BAAALgADCgEJAQAAAA==.',
Rh='Rhun:BAAALgAECgYJBgAAAA==.Rhyzer:BAAALgAECgEJAwAAAA==.',
Ri='Rileyksufan:BAAALgAECgcJDAAAAA==.Rinas:BAABLgAECn8WAAIVAAYJQB+cFwALAgAVAAYJQB+cFwALAgAAAA==.Rivendell:BAAALgAECgEJAQAAAA==.',
Ru='Rubioxis:BAAALgADCgYJBgAAAA==.',
Sa='Sabazia:BAABLgAECn8fAAIcAAgJwRowAwDGAQAcAAgJwRowAwDGAQAAAA==.Sacrificer:BAAALgAECgMJAwAAAA==.Sairalindë:BAAALgAECgQJCAAAAA==.Salios:BAABLgAFFH8HAAIaAAMJ5SGpFwAzAQAaAAMJ5SGpFwAzAQAAAA==.Sallydisco:BAAALgADCgQJBAABLgAFFAIJBgABACofAA==.Sanctifier:BAAALgAECgQJCAAAAA==.Saraneth:BAAALgAECgEJAQABLgAECgcJGgAEAB0gAA==.',
Sc='Scandrel:BAAALgAECgQJBAABLgAECgkJJQAPAHkcAA==.Scrept:BAAALgAECgUJEQAAAA==.Scynix:BAEBLgAECn8cAAMdAAYJuRiZIQCyAQAdAAYJuRiZIQCyAQAIAAEJsgFPTgAiAAAAAA==.',
Se='Sedaline:BAAALgAECgMJAwAAAA==.Sephie:BAAALgADCgQJAQAAAQ==.Serenilock:BAAALgADCgMJAwAAAA==.Serfdog:BAAALgADCgQJBgAAAA==.Servoker:BAACLgAFFH8MAAIIAAUJUhzcAgBiAQAIAAUJUhzcAgBiAQAuAAQKfyQAAx0ACAnbIB0KANQCAB0ACAnbIB0KANQCAAgABwkkGrUVAPABAAAA.Seräphina:BAAALgAECgYJEQAAAA==.Setani:BAAALgADCgIJAgAAAA==.',
Sh='Shabzkaw:BAAALgADCgIJAgAAAA==.Shaienne:BAAALgAECgEJAQAAAA==.Shambussy:BAAALgADCgEJAQAAAA==.Shamfore:BAAALgADCgEJAQAAAA==.Shamrockshak:BAAALgAECgEJAgAAAA==.Shenuton:BAAALgAECgEJAQAAAA==.Shiftkicker:BAAALgADCgMJAwAAAA==.Shockthêràpy:BAABLgAECn8nAAQgAAgJgBltJwD0AQAgAAgJgBltJwD0AQACAAIJQxspGgCcAAASAAEJTwpDKwA4AAAAAA==.Shoes:BAABLgAECn8gAAMfAAkJdiK5DQDUAgAfAAgJ4x65DQDUAgALAAYJhyEPGgAsAQAAAA==.Shyanni:BAAALgADCgMJAwAAAA==.',
Si='Siaana:BAAALgADCgUJBQABLgAECggJHwAcAMEaAA==.Sibearian:BAAALgAECgYJCgAAAA==.Simi:BAAALgAECgYJEAABLgAECgcJHgAaAIAKAA==.',
Sk='Skrubzz:BAABLgAECn8ZAAMBAAgJIgbnIAA4AQABAAgJIgbnIAA4AQARAAQJzgJthwChAAAAAA==.',
Sl='Sloppynachos:BAABLgAECn8pAAIOAAgJOBfhAwDVAQAOAAgJOBfhAwDVAQAAAA==.Slyman:BAAALgADCgUJBQABLgAECgYJBgAKAAAAAA==.',
Sm='Smokesçreen:BAABLgAECn8lAAIVAAgJDhhcEABhAgAVAAgJDhhcEABhAgAAAA==.',
Sn='Snowhoof:BAAALgADCgUJBQAAAA==.',
So='Sogerä:BAABLgAECn8WAAIIAAcJbwVFBwAPAQAIAAcJbwVFBwAPAQAAAA==.Soonerpride:BAAALgAECgYJEQAAAA==.Source:BAAALgAECgUJCAAAAA==.',
Sp='Spearminttea:BAAALgAECgcJBQAAAA==.Spellumgud:BAAALgAECgQJBgAAAA==.',
Sq='Squiby:BAABLgAECn8hAAMJAAkJ2x2/DwCJAgAJAAgJDh2/DwCJAgAUAAIJmRXrZwCNAAAAAA==.Squizzy:BAAALgAECgEJAQAAAA==.',
St='Stabfore:BAAALgADCgcJDQAAAA==.Standaside:BAAALgADCgMJAwAAAA==.Stinky:BAAALgAECgYJEwAAAA==.Stix:BAAALgAECgcJEQAAAA==.Stoya:BAAALgADCgQJBAABLgAECgcJGgAEAB0gAA==.Stuef:BAABLgAECn8iAAICAAgJXx8TDgDCAgACAAgJXx8TDgDCAgAAAA==.Stuefagos:BAAALgAECgQJBwAAAA==.Stuefester:BAAALgAECgMJAwAAAA==.Stueflare:BAAALgAECggJEAAAAA==.Stueflip:BAAALgADCgIJAgAAAA==.Stunsturds:BAAALgAECgYJDgABLgAECgYJEwAKAAAAAA==.Stäirs:BAABLgAECn8dAAIRAAgJwxZLJgAnAgARAAgJwxZLJgAnAgAAAA==.',
Su='Summerlily:BAAALgADCgYJBgAAAA==.',
Sv='Svaja:BAAALgADCgMJAwABLgAECgQJBwAKAAAAAA==.',
Sy='Sylaria:BAAALgADCgcJCgAAAA==.Syreline:BAAALgADCgEJAQAAAA==.',
['Sî']='Sîn:BAAALgADCgEJAQABLgAECgQJDAAKAAAAAA==.',
['Sï']='Sïn:BAAALgAECgQJDAAAAA==.',
Ta='Taereachye:BAACLgAFFH8GAAIEAAIJtiCBBwDGAAAEAAIJtiCBBwDGAAAuAAQKfxcAAgQABwk5JAkKANMCAAQABwk5JAkKANMCAAAA.Tailon:BAAALgADCgYJBgAAAA==.Talenelat:BAAALgADCgcJCwAAAA==.Tantric:BAAALgAECgIJAgABLgAECgUJCwAKAAAAAA==.Tarathiel:BAAALgADCgQJBAAAAA==.Taurne:BAACLgAFFH8IAAIDAAQJagrjBgACAQADAAQJagrjBgACAQAuAAQKfx4AAgMABwmzGX8wAOkBAAMABwmzGX8wAOkBAAAA.',
Te='Technique:BAAALgADCgUJBQAAAA==.Teknoman:BAABLgAECn8fAAIRAAgJLxrdBADoAQARAAgJLxrdBADoAQAAAA==.Telmarine:BAAALgADCgkJFgAAAA==.Terlemen:BAAALgAECgUJBQAAAA==.Tetsumi:BAAALgADCgYJCQABLgAECgUJBwAKAAAAAA==.',
Th='Thalan:BAAALgADCgEJAQAAAA==.Thalindra:BAAALgAECgEJAwAAAA==.Tharain:BAAALgADCgMJAwAAAA==.Thecurt:BAABLgAECn8dAAIGAAgJZSMWBwAUAwAGAAgJZSMWBwAUAwAAAA==.Thedammed:BAAALgADCgEJAQAAAA==.Thermidor:BAABLgAECn8gAAIhAAkJXBWeCQBFAgAhAAkJXBWeCQBFAgAAAA==.Thorsamie:BAAALgADCgkJHgAAAA==.Thundercunti:BAAALgADCgYJDAAAAA==.',
Ti='Tiamatt:BAAALgADCgIJBAAAAA==.Ticktock:BAAALgAECgIJAgAAAA==.Timaeus:BAAALgADCgYJBgAAAA==.Tinytotems:BAAALgADCgEJAQAAAA==.Titanlock:BAAALgADCgcJCgAAAA==.',
To='Torvia:BAAALgADCgkJDwAAAA==.Totemix:BAAALgADCgYJCwAAAA==.Towelie:BAAALgAECgMJBQAAAA==.',
Tr='Trisinz:BAAALgAECgYJEAAAAA==.Trixa:BAAALgADCgMJAwAAAA==.',
Tu='Tuerto:BAAALgAECgYJCwAAAA==.Turk:BAABLgAECn8eAAMWAAkJ1A/CTQC+AQAWAAkJ1A/CTQC+AQAVAAEJCQ/AcwAxAAAAAA==.Turkish:BAABLgAECn8dAAIMAAgJThd6SAAaAgAMAAgJThd6SAAaAgAAAA==.Turtledisco:BAACLgAFFH8GAAIBAAIJKh9xCQC5AAABAAIJKh9xCQC5AAAuAAQKfx0AAgEACQmPHrUDABgDAAEACQmPHrUDABgDAAAA.',
Ty='Tychaa:BAAALgADCgMJAwAAAA==.Tylat:BAAALgADCgEJAQAAAA==.Tyranax:BAABLgAECn8kAAMiAAgJBxsYAwAYAgAiAAgJgBgYAwAYAgAUAAYJ1R9NHAD6AQAAAA==.Tyyregade:BAAALgADCgkJCgABLgAECgUJBwAKAAAAAA==.',
Uj='Ujimas:BAAALgADCgcJDQAAAA==.',
Ur='Urawizardtui:BAABLgAECn8pAAMPAAgJdRw8DADuAQAPAAgJdRw8DADuAQAFAAUJgwhkDgDdAAAAAA==.',
Us='Us:BAAALgAECggJCAAAAA==.',
Va='Vadose:BAABLgAECn8eAAIaAAcJgAqEHwAkAQAaAAcJgAqEHwAkAQAAAA==.Vales:BAAALgADCgYJBgABLgAECggJGQALAEAJAA==.Valsavis:BAAALgAECgUJBwAAAA==.Valytrois:BAAALgAECgYJDAAAAA==.Varinix:BAAALgADCgMJAwAAAA==.',
Ve='Veggiebaha:BAAALgADCgIJAgAAAA==.Veiksla:BAAALgAECgQJBwAAAA==.Velore:BAAALgADCgcJDAAAAA==.Vengerr:BAAALgAECgIJAgAAAA==.Verace:BAAALgAECgcJAQAAAA==.',
Vi='Vitur:BAABLgAECn8iAAIWAAkJlyDNEgDpAgAWAAkJlyDNEgDpAgAAAA==.',
Vo='Voidhunter:BAAALgAECgQJCAAAAA==.Voidweaver:BAAALgAECgEJAwAAAA==.Volaine:BAAALgAECgEJAwAAAA==.Volt:BAABLgAECn8aAAISAAgJBxPtCwAIAgASAAgJBxPtCwAIAgAAAA==.Volwryn:BAAALgAECgMJAwABLgAECgUJCwAKAAAAAA==.',
Vy='Vynarian:BAAALgAECgEJAwAAAA==.',
['Vâ']='Vâljean:BAAALgADCgMJAwAAAA==.',
['Vô']='Vôx:BAAALgAECgEJAQABLgAECgQJCgAKAAAAAA==.',
Wa='Warbeard:BAABLgAECn8YAAIRAAkJ7wb5UABkAQARAAkJ7wb5UABkAQAAAA==.',
Wi='Wizwizx:BAAALgADCgEJAQAAAA==.',
Wr='Wreckd:BAAALgAECgkJAQAAAA==.',
Wy='Wyth:BAAALgADCgcJDAABLgAECgIJAgAKAAAAAA==.',
Xa='Xanthad:BAAALgADCgEJAQAAAA==.',
Xb='Xb:BAAALgADCgMJAwAAAA==.',
Xo='Xolair:BAAALgAECgQJBgAAAA==.',
Ya='Yaalia:BAAALgAECgEJAgAAAA==.Yaan:BAABLgAECn8WAAICAAYJBAx+EwDhAAACAAYJBAx+EwDhAAAAAA==.',
Yo='Yoshira:BAAALgADCgQJBAAAAA==.',
['Yö']='Yör:BAAALgADCgcJBwAAAA==.',
Za='Zain:BAABLgAECn8gAAMjAAkJ7BN9BwBGAgAjAAkJ7BN9BwBGAgARAAYJGA5SWQBIAQAAAA==.Zandibar:BAAALgAECgEJAwAAAA==.Zaptoasted:BAAALgAECgEJAQAAAA==.Zaroff:BAAALgADCgcJBwAAAA==.',
Ze='Zedadiah:BAAALgADCgEJAQAAAA==.Zelah:BAAALgAECgQJBAAAAA==.Zellezugtail:BAAALgADCgMJAwABLgAECgQJBwAKAAAAAA==.',
Zi='Zinder:BAAALgAECgYJEQAAAA==.',
Zu='Zuggie:BAAALgAECgQJBwAAAA==.Zurtrinik:BAACLgAFFH8OAAIBAAUJsSFYAgCSAQABAAUJsSFYAgCSAQAuAAQKfyQAAgEACAmZJDoCAE0DAAEACAmZJDoCAE0DAAAA.',
Zz='Zzonked:BAABLgAECn8dAAMMAAkJZAd5iABwAQAMAAkJKAZ5iABwAQAcAAIJ/gtDPwBSAAAAAA==.',
['Zê']='Zêp:BAAALgAECgEJAQAAAA==.',
['Zø']='Zøømies:BAABLgAECn8VAAIWAAYJwBVVHQAbAQAWAAYJwBVVHQAbAQAAAA==.',
['Äs']='Äshnärd:BAABLgAECn8fAAIgAAgJjSKMAgBvAgAgAAgJjSKMAgBvAgAAAA==.',
['Ða']='Ðar:BAAALgADCgEJAQAAAA==.',
['Ðo']='Ðoogle:BAAALgAECgQJBwAAAA==.',
['Ðr']='Ðruidess:BAAALgAECgMJAwAAAA==.',
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

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

local lookup = {'Unknown-Unknown','Monk-Windwalker','Shaman-Elemental','Monk-Brewmaster','DemonHunter-Devourer','Warlock-Affliction','Priest-Shadow','Druid-Restoration','Druid-Balance','Evoker-Preservation','Paladin-Retribution','Evoker-Devastation','Evoker-Augmentation','Warrior-Protection','DeathKnight-Blood','Paladin-Holy','Hunter-Survival','Mage-Frost','Druid-Guardian','Rogue-Subtlety','Rogue-Assassination','Warrior-Fury','DeathKnight-Unholy','Hunter-BeastMastery','Priest-Discipline','Monk-Mistweaver','Shaman-Enhancement','DemonHunter-Vengeance','Warlock-Demonology','Warlock-Destruction','DemonHunter-Havoc','Priest-Holy','Rogue-Outlaw','Warrior-Arms','Hunter-Marksmanship','DeathKnight-Frost',}
local provider = {region='US',realm='Eitrigg',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abominable:BAAALgADCgEJAQAAAA==.',
Ag='Agden:BAAALgADCgEJAQAAAA==.',
Al='Alairn:BAAALgAECgUJCwABLgAECgYJCwABAAAAAA==.Alenciann:BAAALgAECgMJBQAAAA==.Alys:BAABLgAECn8bAAICAAgJAgeFIAAhAQACAAgJAgeFIAAhAQAAAA==.',
Am='Amaniatres:BAAALgAECgEJAQAAAA==.Amoonranara:BAAALgADCgEJAQAAAA==.',
An='Anaan:BAAALgAECgQJBAAAAA==.Angrylizard:BAAALgAECgEJAQAAAA==.Anklebiterr:BAAALgAECgUJBgAAAA==.',
Ap='Apothecary:BAAALgADCgcJBwAAAA==.',
Ar='Arandomidiot:BAAALgADCgYJBgAAAA==.Arathan:BAAALgADCgEJAQAAAA==.Ariiana:BAAALgAECgEJAQAAAA==.',
As='Asapshocky:BAACLgAFFH8LAAIDAAQJsxTXDQA7AQADAAQJsxTXDQA7AQAuAAQKfygAAgMACAnpID4GAIMCAAMACAnpID4GAIMCAAAA.Asclepios:BAAALgAECgMJAwAAAA==.Asmoday:BAAALgADCgEJAQAAAA==.Astraroth:BAAALgADCgQJBAAAAA==.',
Av='Avella:BAAALgADCgUJBwAAAA==.',
Ba='Bamwham:BAAALgADCgcJBwAAAA==.Barrii:BAAALgAECgMJAwAAAA==.',
Be='Bearblaster:BAAALgADCgQJBAABLgAECgQJBgABAAAAAA==.Bearlytanks:BAAALgADCgIJAgAAAA==.Bellabelle:BAAALgADCggJFAAAAA==.Ben:BAAALgAECgcJEwAAAA==.Betamaxx:BAAALgAECgQJBAAAAA==.Betterx:BAAALgAECgQJBQAAAA==.Bevian:BAAALgADCgIJAgABLgAECgQJBQABAAAAAA==.',
Bi='Biggiepants:BAAALgAECggJEwAAAA==.Bighead:BAAALgADCgUJCwABLgAECgYJFQAEAEgeAA==.Bintje:BAAALgADCgcJDQAAAA==.Biollante:BAAALgAECgcJCwAAAA==.',
Bl='Blindedlïght:BAAALgAECgQJBQAAAA==.',
Bo='Bolsan:BAAALgAECgMJBQAAAA==.Bonq:BAAALgAECgIJAgABLgAECggJDwAFAK8ZAA==.Bourg:BAAALgAECgYJCAAAAA==.Bowhemian:BAAALgAECgMJAwAAAA==.',
Bu='Buckis:BAAALgAECgQJBgAAAA==.Bufú:BAAALgADCgIJAgAAAA==.',
['Bö']='Böurbon:BAAALgADCgIJAgAAAA==.',
Ca='Cajia:BAAALgAECgYJEgAAAA==.',
Ce='Celds:BAAALgADCgQJBAABLgAECgcJGQAGAPEbAA==.Celiae:BAAALgAECgYJEAAAAA==.Cendanel:BAAALgADCgYJCwAAAA==.',
Ch='Childress:BAAALgAECgMJAwAAAA==.Choggy:BAABLgAECn8bAAIHAAcJPBfjEQC6AQAHAAcJPBfjEQC6AQAAAA==.',
Ci='Cimbline:BAAALgADCgIJAgAAAA==.',
Cl='Clairerick:BAAALgAECgYJEAAAAA==.',
Co='Confessionn:BAAALgADCggJDAAAAA==.Cough:BAAALgAECgIJBAABLgAECgYJFQAEAEgeAA==.',
Cr='Crinklecut:BAAALgAECgYJDwAAAA==.Critos:BAAALgADCgcJBwAAAA==.Crotchout:BAAALgADCgMJAwAAAA==.Crybaby:BAAALgADCgEJAQAAAA==.Crystilpixy:BAAALgADCgMJBAAAAA==.',
['Cé']='Céline:BAAALgAECgEJAQAAAA==.',
Da='Danilov:BAAALgADCgYJBgAAAA==.',
De='Deadlyshift:BAABLgAECn8XAAMIAAkJqyIGAgBwAwAIAAkJqyIGAgBwAwAJAAUJMhoxNgBjAQAAAA==.Deadybear:BAAALgADCgIJAgABLgAECggJPQAKAD0UAA==.Delrok:BAAALgAECgEJAgAAAA==.Dephias:BAAALgADCgMJAwAAAA==.',
Di='Diagnosis:BAABLgAECn8eAAILAAkJgCWeAQBVAwALAAkJgCWeAQBVAwAAAA==.',
Do='Donnabb:BAAALgAECgUJCQAAAA==.Doran:BAAALgAECgUJCQAAAA==.Doriathrin:BAAALgADCgQJBQAAAA==.Doujinshi:BAABLgAECn8OAAIFAAcJ8xveUwCoAQAFAAcJ8xveUwCoAQAAAA==.',
Dr='Draedis:BAAALgAECgMJBgAAAA==.Dragonbladez:BAAALgADCgUJBQAAAA==.Dragoneye:BAAALgAECgMJAwAAAA==.Dragonhawk:BAAALgADCgQJBAABLgAECgMJEgABAAAAAA==.Drakoil:BAABLgAECn8YAAMMAAYJqBJkCAAoAQAMAAYJqRFkCAAoAQANAAUJTAs4QQDgAAAAAA==.Dreademperor:BAACLgAFFH8JAAIOAAQJdRVECgAMAQAOAAQJdRVECgAMAQAuAAQKfyEAAg4ACQnRHe8EAPYCAA4ACQnRHe8EAPYCAAEuAAUUBQkIAA8AuhYA.Dreadnature:BAAALgAECgMJAwAAAA==.Dreadnight:BAABLgAFFH8IAAIPAAUJuhbyCgAjAQAPAAUJuhbyCgAjAQAAAA==.Dreadsteed:BAAALgAECgEJAQABLgAFFAUJCAAPALoWAA==.Dreadweaver:BAAALgADCgUJBQABLgAFFAUJCAAPALoWAA==.Drenrah:BAABLgAECn8mAAIQAAgJUBFoGQC/AQAQAAgJUBFoGQC/AQAAAA==.Drgndeeznutz:BAACLgAFFH8GAAIRAAMJwBalDQAKAQARAAMJwBalDQAKAQAuAAQKfx4AAhEACQn+HE0DAKYCABEACQn+HE0DAKYCAAAA.Drizz:BAAALgAECgIJAgAAAA==.Drunkenrage:BAACLgAFFH8cAAIEAAYJjSDBAQD8AQAEAAYJjSDBAQD8AQAuAAQKfx4AAgQACQkcIvwBAIIDAAQACQkcIvwBAIIDAAAA.',
Du='Dumorius:BAAALgAECgIJAgAAAA==.',
['Dé']='Déx:BAAALgAECgYJCwAAAA==.',
Ed='Edreth:BAAALgAECgEJAQAAAA==.',
El='Elbryan:BAABLgAECn8hAAIHAAgJSwRzJAAfAQAHAAgJSwRzJAAfAQAAAA==.Elementdemon:BAAALgAECgQJBQAAAA==.',
En='Enthalpy:BAABLgAECn8bAAISAAcJbxq+ggDMAQASAAcJbxq+ggDMAQAAAA==.',
Er='Erazath:BAAALgAECgUJCAABLgAECgkJEAABAAAAAA==.',
Es='Esperzoa:BAAALgAECggJDAAAAA==.',
Et='Eternaldread:BAAALgADCgUJBQABLgAFFAUJCAAPALoWAA==.',
Eu='Eucalicdes:BAABLgAECn8sAAITAAkJ2BPgBgDUAQATAAkJ2BPgBgDUAQAAAA==.',
Ez='Ezra:BAAALgADCgYJBgAAAA==.',
Fa='Farshran:BAAALgAECgkJEAAAAA==.Fate:BAAALgAECgQJBQABLgAECgkJHwALADUkAA==.',
Fe='Felicity:BAACLgAFFH8SAAIUAAUJyh2hBgB1AQAUAAUJyh2hBgB1AQAuAAQKfzIAAxQACQmMIpEEAE4DABQACQmMIpEEAE4DABUABQmBDY8MAPMAAAAA.Ferendis:BAABLgAECn8gAAIFAAgJjCK0BgC9AgAFAAgJjCK0BgC9AgAAAA==.Fernard:BAAALgADCgYJBgABLgAECggJDwAFAK8ZAA==.',
Fl='Florita:BAAALgADCgkJFgAAAA==.',
Fo='Fordinn:BAABLgAECn8XAAMOAAYJWhdNHADZAAAOAAUJXxNNHADZAAAWAAQJyBV6SACZAAAAAA==.',
Fr='Fractured:BAAALgADCgEJAQAAAA==.Freelor:BAAALgAECgIJAwAAAA==.Freemi:BAAALgAECgEJAQAAAA==.',
Fu='Fuddytwo:BAAALgAECgYJCgAAAA==.',
Ga='Garzhvog:BAAALgADCgcJCwABLgAECgkJJwAGAFYkAA==.Gasket:BAABLgAECn8gAAIXAAkJbyG9IgC0AgAXAAkJbyG9IgC0AgAAAA==.Gauteng:BAAALgAECgIJAgABLgAECgkJJAALAKQkAA==.',
Gh='Ghorac:BAAALgADCgYJCAAAAA==.Ghoti:BAAALgADCgUJBQAAAA==.Ghoulz:BAAALgADCgcJDAAAAA==.',
Gl='Glazedham:BAAALgADCgMJAwAAAA==.',
Go='Gorbubbli:BAAALgADCgkJGgAAAA==.',
Gr='Graceful:BAAALgAECgQJBQAAAA==.Grit:BAAALgAECgEJAQAAAA==.',
Gu='Guilddrama:BAAALgADCgEJAQAAAA==.',
Ha='Haeler:BAAALgAECgIJAwAAAA==.Haelin:BAAALgADCgEJAQAAAA==.Halgoðfulk:BAAALgAECgEJAQAAAA==.Hamwarrior:BAAALgAECgEJAQAAAA==.Handicap:BAAALgADCgYJBgABLgAECgkJHgALAIAlAA==.Hark:BAABLgAECn8iAAIYAAkJCRfzNwDOAQAYAAkJCRfzNwDOAQAAAA==.Harvin:BAABLgAECn8gAAIKAAgJ0SDBAgC9AgAKAAgJ0SDBAgC9AgAAAA==.',
He='Hekus:BAAALgAECgcJDgAAAA==.Helanua:BAAALgAECgYJCwAAAA==.',
Hi='Hibernate:BAAALgADCgEJAQAAAA==.Hippopotamus:BAAALgAECgIJAgAAAA==.Hit:BAAALgAECgUJCgAAAA==.',
Ho='Holytide:BAAALgAECgcJEwAAAA==.Hope:BAAALgAECgcJEgAAAA==.Horrorfang:BAABLgAECn8gAAIXAAgJpRikIAAGAgAXAAgJpRikIAAGAgAAAA==.',
Hu='Hukjo:BAAALgAECgcJDwAAAA==.',
Ib='Ibaar:BAACLgAFFH8RAAINAAUJ8SOOCQCWAQANAAUJ8SOOCQCWAQAuAAQKfykAAw0ACQmnI0wHAAUDAA0ACAkeI0wHAAUDAAwABgneIAINAAoCAAAA.',
Ic='Icepickle:BAAALgADCgcJAQAAAA==.',
Ii='Iilnut:BAABLgAECn8YAAMHAAgJkSA8CwDPAgAHAAgJkSA8CwDPAgAZAAQJOxWyNwDpAAABLgAECgkJHAAaANkgAA==.',
Il='Illedren:BAABLgAECn8QAAIFAAgJtwcykAAAAQAFAAgJtwcykAAAAQAAAA==.',
In='Innerdemon:BAAALgAECgQJBAAAAA==.Inno:BAABLgAECn8XAAIFAAgJ3iPvEwDhAgAFAAgJ3iPvEwDhAgAAAA==.',
Is='Isabel:BAAALgAECgYJBgAAAA==.',
It='Ithacus:BAABLgAECn8mAAIbAAgJ3hAOCQCPAQAbAAgJ3hAOCQCPAQAAAA==.',
Ja='Jandaar:BAAALgAECgEJAQAAAA==.Jattao:BAAALgADCgEJAQAAAA==.',
Jd='Jdawgprime:BAAALgADCgcJBwAAAA==.',
Je='Jenjas:BAAALgADCgcJBgAAAA==.',
Ji='Jinnlee:BAAALgAECgQJBAAAAA==.Jinoo:BAABLgAECn8fAAIDAAgJ1RyiCwAgAgADAAgJ1RyiCwAgAgAAAA==.Jinufan:BAAALgAECgIJAgABLgAFFAUJEQANAPEjAA==.',
Jo='Joe:BAAALgAECgcJCAAAAA==.Jorek:BAABLgAECn8WAAIWAAkJ6BSuDgAEAgAWAAkJ6BSuDgAEAgAAAA==.',
Ju='Jugulator:BAAALgADCgUJBQAAAA==.',
Ka='Kaihune:BAAALgADCgEJAQAAAA==.Kaiva:BAAALgAECgMJBAAAAA==.Kallistô:BAAALgADCgYJBgAAAA==.Kamigawa:BAAALgAECgYJDgAAAA==.Kavik:BAAALgAECgcJDQAAAA==.Kazbodan:BAAALgADCgkJFQAAAA==.',
Ke='Keemo:BAABLgAECn8iAAMPAAkJnBBIFwAVAQAPAAkJfRBIFwAVAQAXAAMJmA0+/ACDAAAAAA==.Keemosaki:BAAALgAECgcJCQAAAA==.Keemõ:BAABLgAECn8XAAMFAAYJvw3mVwD1AAAFAAYJ0wzmVwD1AAAcAAYJowkTEgClAAAAAA==.Keflá:BAAALgAECgQJCAAAAA==.Keysersöze:BAAALgADCgEJAQAAAA==.',
Kh='Khaas:BAABLgAECn8gAAIXAAgJXwhXSABiAQAXAAgJXwhXSABiAQAAAA==.Khaleeb:BAAALgAECgEJAwAAAA==.',
Ki='Kierios:BAAALgAECggJCAAAAA==.Kildurgan:BAAALgAECgQJCQAAAA==.Killawarlock:BAABLgAECn8ZAAQdAAgJDSCHNACSAQAdAAcJDSCHNACSAQAGAAEJAABRJwBUAAAeAAEJ/hARcAA2AAAAAA==.Kironn:BAAALgADCgYJBgABLgAECgYJFQAEAEgeAA==.',
Kk='Kkain:BAAALgAECgIJBAAAAA==.',
Ko='Korihor:BAAALgAECggJCwAAAA==.',
Kr='Krestus:BAABLgAECn8PAAMFAAYJrxkTfgAvAQAFAAYJrxkTfgAvAQAfAAEJAABxbwA2AAAAAA==.Krispy:BAABLgAECn8UAAMCAAgJ5wo2JgD7AAACAAgJ5wo2JgD7AAAaAAUJvgO0TgCZAAAAAA==.Krith:BAAALgADCgYJCQAAAA==.Krix:BAAALgAECgMJBAAAAA==.',
Ky='Kyndil:BAAALgADCgMJAwAAAA==.',
La='Laxus:BAAALgADCgcJDAABLgAECgkJGAAMAHkMAA==.Lazarius:BAAALgADCgQJBAAAAA==.',
Le='Levophed:BAABLgAECn8uAAIXAAcJiA/bUwBCAQAXAAcJiA/bUwBCAQAAAA==.',
Li='Liangwei:BAAALgAECgMJAwABLgAFFAMJBQAYAPMdAA==.Lightfallen:BAAALgAECgcJDgAAAA==.Liisara:BAABLgAECn8aAAIFAAgJZQjpRwAhAQAFAAgJZQjpRwAhAQAAAA==.Lily:BAABLgAECn8gAAITAAgJyBgoBwDJAQATAAgJyBgoBwDJAQAAAA==.Linadra:BAABLgAECn8bAAILAAgJdwmVUABVAQALAAgJdwmVUABVAQAAAA==.Littleyeti:BAAALgAECgMJAwAAAA==.Liyara:BAABLgAECn8kAAILAAkJpCRGEQAGAwALAAkJpCRGEQAGAwAAAA==.',
Ll='Llorsa:BAABLgAECn8gAAIgAAgJuQ+iGgB2AQAgAAgJuQ+iGgB2AQAAAA==.',
Lo='Lohhan:BAAALgADCgUJCQAAAA==.Lolamontez:BAAALgADCgcJBwAAAA==.Lorachka:BAAALgADCgIJAgAAAA==.Lorthys:BAAALgADCgEJAQAAAA==.',
Lu='Luxian:BAABLgAECn8eAAILAAcJlw2baQAaAQALAAcJlw2baQAaAQAAAA==.',
Ma='Mahiru:BAAALgADCgEJAQAAAA==.Mahralla:BAAALgADCgIJAgAAAA==.Maikagond:BAAALgAECgMJAwABLgAECgYJFgAQAMUNAA==.Makaria:BAAALgAECgYJDAAAAA==.Malbisa:BAAALgAECgMJAwAAAA==.Malphoz:BAAALgADCggJCAAAAA==.Mandragora:BAAALgAECgQJBwAAAA==.Marli:BAAALgADCgEJAQAAAA==.Mattieatzdot:BAAALgAECgQJBQAAAA==.',
Mc='Mcgrowlin:BAAALgAECgQJCwAAAA==.',
Me='Meko:BAAALgAECgUJBwAAAA==.',
Mi='Mickey:BAACLgAFFH8IAAICAAQJIwtZCwAdAQACAAQJIwtZCwAdAQAuAAQKfyAAAgIACQn0IBcJAOYCAAIACQn0IBcJAOYCAAAA.Migraine:BAAALgAECgYJCgAAAA==.Mikiik:BAABLgAECn8eAAIdAAcJcwguVgAqAQAdAAcJcwguVgAqAQAAAA==.Mildoo:BAABLgAECn8kAAIGAAgJBg8aCQC1AQAGAAgJBg8aCQC1AQAAAA==.Milkymoo:BAAALgAECgUJDAABLgAFFAcJIAAgACEUAA==.Millina:BAAALgADCgIJAgABLgAECggJGwACAAIHAA==.Minip:BAAALgAECgYJCwAAAA==.Mixednuts:BAABLgAECn8cAAMaAAkJ2SDLAQBXAwAaAAkJ2SDLAQBXAwACAAYJ8x+hHwDaAQAAAA==.',
Mo='Mochii:BAAALgADCgYJBgAAAA==.Moneyshock:BAAALgAECgQJBAAAAA==.Monq:BAABLgAECn8VAAMCAAcJFRc8GABjAQACAAcJFRc8GABjAQAEAAEJyAkojQAqAAAAAA==.Moonamber:BAAALgADCgQJBgAAAA==.Morithus:BAAALgADCgkJDgAAAA==.Morphinzerr:BAAALgAECgEJAQAAAA==.',
My='Mythion:BAAALgAECgYJEAAAAA==.Mythoridan:BAAALgAECgEJAQAAAA==.',
Na='Naeres:BAABLgAECn8fAAIXAAgJjxeqLwC6AQAXAAgJjxeqLwC6AQAAAA==.Nafari:BAAALgADCgkJEQAAAA==.Naofummi:BAAALgAECgcJBwAAAA==.Naomii:BAABLgAECn8gAAMgAAgJjRW7JADDAQAgAAgJjRW7JADDAQAHAAUJggivMADQAAAAAA==.Naturefury:BAAALgADCgEJAQAAAA==.',
Ne='Neeston:BAABLgAECn8hAAMIAAgJBiN8BgDqAgAIAAgJBiN8BgDqAgAJAAEJZRLUgAAwAAAAAA==.Neodin:BAAALgAECgUJDgAAAA==.Nephadin:BAAALgADCgUJAwAAAA==.Nerfed:BAAALgAECgUJBwAAAA==.Neviaa:BAABLgAECn8YAAIXAAgJDQoBZAAcAQAXAAgJDQoBZAAcAQAAAA==.',
Ni='Nickypoo:BAAALgAECgMJAwAAAA==.Nightmenace:BAAALgAECgcJCwAAAA==.Ninari:BAAALgADCgUJBQAAAA==.Niq:BAAALgAECgQJBAAAAA==.',
No='Nocshadue:BAAALgADCgUJBQAAAA==.Nordga:BAAALgADCgcJBwAAAA==.Nothealster:BAAALgAECgcJEgAAAA==.',
Ob='Obsidiian:BAABLgAECn8UAAIhAAgJjxH0AwCuAQAhAAgJjxH0AwCuAQAAAA==.Obsidion:BAAALgAECgQJCAABLgAECgYJFwAOAFoXAA==.',
Od='Odie:BAAALgAECgYJCAAAAA==.',
On='Onlyfangs:BAABLgAECn89AAMKAAgJPRTjBwDwAQAKAAgJPRTjBwDwAQANAAUJdQKGTgBcAAAAAA==.',
Os='Oscrapermort:BAAALgADCgMJAwAAAA==.',
Pa='Padivyn:BAAALgAECggJDQAAAA==.Padnamprik:BAAALgAECgQJBAAAAA==.',
Pe='Peanads:BAAALgADCgUJBAAAAA==.Pebblez:BAAALgADCgcJDgAAAA==.Perry:BAAALgAECggJEAAAAA==.',
Po='Po:BAAALgAECgkJCAAAAA==.Pozufuma:BAABLgAECn8gAAIWAAgJrxvOCgA7AgAWAAgJrxvOCgA7AgAAAA==.',
Pr='Priestcraft:BAAALgADCgIJAgABLgAECggJCwABAAAAAA==.',
Ps='Psychomantis:BAABLgAECn8mAAMHAAgJFxUEEQDEAQAHAAgJFxUEEQDEAQAgAAEJQgQChQAsAAAAAA==.',
Pu='Punchypunch:BAAALgADCgkJFAAAAA==.',
Ra='Raek:BAAALgAECgQJBQABLgAECgcJGQAGAPEbAA==.Ravenbyrd:BAAALgADCgMJAwAAAA==.Rawberriez:BAAALgAECgQJBgAAAA==.',
Re='Reani:BAAALgADCgQJBAAAAA==.Reapin:BAAALgADCgUJBQAAAA==.Redpool:BAABLgAECn8dAAIYAAcJWBCKQACtAQAYAAcJWBCKQACtAQAAAA==.Remithedrood:BAAALgADCgIJAgAAAA==.Reqium:BAAALgADCgYJCAAAAA==.Resto:BAAALgAECgQJBgAAAA==.Rethandra:BAAALgAECgYJCAAAAA==.',
Ri='Rion:BAABLgAECn8XAAISAAkJbhFmLADwAQASAAkJbhFmLADwAQAAAA==.Ristvakbaen:BAABLgAECn8nAAQGAAkJViT7AAB/AgAdAAkJaB21DACJAgAGAAcJAiX7AAB/AgAeAAYJeiQmAwD9AQAAAA==.',
Ro='Robynlee:BAABLgAECn8dAAIgAAgJoRB9IwDKAQAgAAgJoRB9IwDKAQAAAA==.Rogùe:BAAALgAECgIJAwAAAA==.',
Ru='Rugratt:BAAALgADCgQJBAABLgADCgcJDgABAAAAAA==.',
Sa='Saeler:BAAALgAECgMJAwAAAA==.Samoth:BAAALgADCgEJAQAAAA==.Sanctuary:BAAALgAECgQJBAAAAA==.Santeclair:BAAALgAECgEJAQAAAA==.',
Sc='Sceryna:BAABLgAECn8kAAILAAkJThdhHAAdAgALAAkJThdhHAAdAgAAAA==.Schiftly:BAAALgAFFAIJAgAAAA==.Schwiggity:BAAALgADCgcJBwABLgAECgQJBwABAAAAAA==.Scrmndemn:BAABLgAECn8XAAILAAcJiAQteAD8AAALAAcJiAQteAD8AAAAAA==.',
Se='Sepviva:BAABLgAECn8VAAIXAAcJNRZacACoAQAXAAcJNRZacACoAQAAAA==.Serpent:BAACLgAFFH8IAAIOAAUJaRI9BQBdAQAOAAUJaRI9BQBdAQAuAAQKfxkAAg4ACQlYHS4EAHYCAA4ACQlYHS4EAHYCAAAA.',
Sh='Shadowheal:BAAALgADCgUJBgAAAA==.Shamadeus:BAAALgADCgUJBQABLgAECgkJJwAGAFYkAA==.Sharaseth:BAAALgAECgYJCAAAAA==.Shikita:BAABLgAECn8gAAMIAAgJ0B7YEABMAgAIAAgJ0B7YEABMAgAJAAEJHAZXigAlAAAAAA==.Shimadin:BAACLgAFFH8RAAILAAQJCRZrGABJAQALAAQJCRZrGABJAQAuAAQKfyAAAgsACAkyHx8vAGYCAAsACAkyHx8vAGYCAAAA.Shimpbizkit:BAAALgAECgUJCwABLgAFFAQJEQALAAkWAA==.Shimsong:BAAALgAECgIJAwABLgAFFAQJEQALAAkWAA==.Shmerek:BAABLgAECn8XAAIOAAkJLyD2AQDYAgAOAAkJLyD2AQDYAgAAAA==.',
Si='Sidarien:BAAALgADCgQJBAAAAA==.Silverlumen:BAAALgAECgUJBQAAAA==.Silverstream:BAABLgAECn8oAAIIAAgJMRMZQgCZAQAIAAgJMRMZQgCZAQAAAA==.',
Sk='Skyblue:BAAALgADCgEJAQAAAA==.',
Sl='Slea:BAAALgADCgIJAgAAAA==.Slease:BAAALgADCgYJBgAAAA==.',
Sm='Smootish:BAAALgADCgUJBQAAAA==.',
So='Solbin:BAAALgAECgUJCAAAAA==.Solitudé:BAABLgAECn8bAAMdAAgJBSQsFABAAgAdAAYJGyIsFABAAgAGAAUJpSWHBgBNAQAAAA==.Soteirian:BAAALgAECgUJDwABLgAECgYJFgAQAMUNAA==.',
Sp='Spam:BAAALgAECgIJAgAAAA==.Spekey:BAAALgADCggJEAAAAA==.Spider:BAAALgAECgYJDQAAAA==.Spineymagus:BAAALgADCgIJAgAAAA==.',
Sq='Squall:BAAALgAECgYJEgAAAA==.',
St='Stalariais:BAAALgAECgQJBAABLgAECgkJGQAQAHoIAA==.Stardrand:BAAALgADCgUJBgAAAA==.Steelreserve:BAAALgAECgYJDQAAAA==.Straw:BAAALgAECgMJBAABLgAECgkJJgALAGAjAA==.',
Su='Sugarkitty:BAAALgADCgYJCgAAAA==.Supereclipse:BAABLgAECn8gAAIYAAgJWhM0JgC7AQAYAAgJWhM0JgC7AQAAAA==.',
Sw='Swolareclips:BAAALgADCgYJBgAAAA==.',
Sy='Sydvicious:BAABLgAECn8hAAIfAAgJIyVBAgDZAgAfAAgJIyVBAgDZAgAAAA==.Syriene:BAAALgAECgYJEgAAAA==.',
Ta='Tankhealz:BAAALgAECgMJBQAAAA==.',
Tb='Tbsp:BAAALgAECgEJAQAAAA==.',
Te='Tecks:BAABLgAECn8XAAIgAAkJwwUsJAAoAQAgAAkJwwUsJAAoAQAAAA==.Teddy:BAAALgAECgUJCQAAAA==.',
Th='Theatrix:BAAALgAECgQJBAAAAA==.Thecuckler:BAAALgAECgQJCAAAAA==.Thefreeman:BAAALgAECgEJAQAAAA==.Themajor:BAABLgAECn8eAAMiAAkJvhJeBgD/AQAiAAkJpRJeBgD/AQAWAAcJ/AhqTAB0AQAAAA==.Then:BAAALgADCgEJAQAAAA==.Thiarad:BAAALgADCgEJAQAAAA==.Thrain:BAAALgADCgcJDAAAAA==.Threat:BAABLgAECn8fAAILAAkJNSQFAgBJAwALAAkJNSQFAgBJAwAAAA==.Thsarus:BAABLgAECn8hAAMFAAcJ1yAzEwAjAgAFAAcJ1yAzEwAjAgAcAAQJHBHQGwCxAAAAAA==.',
Ti='Tiamaat:BAABLgAECn8XAAIIAAkJmQRwTgDaAAAIAAkJmQRwTgDaAAAAAA==.Tireyne:BAAALgADCgEJAgAAAA==.Titus:BAAALgAECgEJBQAAAA==.',
Tr='Treadlightly:BAAALgADCgUJBwAAAA==.Treefróg:BAAALgAECgUJBQAAAA==.Trentus:BAAALgADCgIJAgAAAA==.Trev:BAAALgAECgUJBgABLgAECgYJHAAeAFAhAA==.Trotem:BAAALgAECgUJBQAAAA==.',
Ts='Tsp:BAACLgAFFH8SAAIaAAUJMhjsCACSAQAaAAUJMhjsCACSAQAuAAQKfyQAAxoACQlkFjAUACgCABoACQlkFjAUACgCAAQABAnuA0RsAJEAAAAA.',
Ty='Tyletos:BAABLgAECn8aAAISAAgJYxTxMgDVAQASAAgJYxTxMgDVAQAAAA==.',
Ug='Ugolok:BAAALgAECgUJCAAAAA==.',
Ur='Uriél:BAABLgAECn8aAAIFAAgJjSOjHwCTAgAFAAgJjSOjHwCTAgAAAA==.',
Ve='Veiler:BAABLgAECn8rAAMYAAkJdg3tIQDRAQAYAAkJdg3tIQDRAQAjAAEJ3wHylgAhAAAAAA==.Velca:BAAALgAECgIJAgAAAA==.Veruca:BAAALgAECgMJAwAAAA==.Veviseron:BAABLgAECn8mAAISAAgJpgOzdwAhAQASAAgJpgOzdwAhAQAAAA==.',
Vh='Vhye:BAAALgAECgYJDAAAAA==.',
Vi='Vinstalation:BAABLgAECn8iAAIkAAcJVh2xAwDMAQAkAAcJVh2xAwDMAQAAAA==.Vissa:BAAALgADCgYJBgAAAA==.',
Vo='Vonbismarck:BAABLgAECn8hAAIYAAgJ8xQlKwCjAQAYAAgJ8xQlKwCjAQAAAA==.',
Vr='Vritraz:BAAALgAECgYJCgAAAA==.Vrock:BAAALgAECgEJAQABLgAECgcJGwASAG8aAA==.',
Wa='Warnam:BAAALgADCgcJBwAAAA==.Warsonge:BAAALgADCgMJAwAAAA==.',
We='Wendypini:BAABLgAECn8dAAIYAAkJTw5ZRQCbAQAYAAkJTw5ZRQCbAQAAAA==.Wetnwild:BAAALgADCgQJBAAAAA==.',
Wh='Whitehand:BAAALgAECgIJAgAAAA==.',
Wo='Wooshwoosh:BAAALgAECgMJBAAAAA==.',
Wu='Wudeeps:BAAALgAECgcJEgAAAA==.Wuhanwarrior:BAAALgAECgUJDwAAAA==.',
Ya='Yako:BAAALgAECgEJAQAAAA==.',
Ye='Yennefer:BAAALgAECgMJAwAAAA==.',
Za='Zangolf:BAAALgADCgUJBAAAAA==.Zaye:BAAALgAECgYJBgAAAA==.',
Ze='Zearas:BAABLgAECn8UAAIXAAgJJREykwBZAQAXAAgJJREykwBZAQAAAA==.Zendonn:BAAALgAECgUJDQAAAA==.',
Zi='Zicatriz:BAAALgADCgcJDgAAAA==.',
Zo='Zodiaac:BAABLgAECn8XAAIPAAkJcBlrBwAYAgAPAAkJcBlrBwAYAgAAAA==.',
Zy='Zy:BAAALgADCgUJBQAAAA==.',
['Ëc']='Ëchõ:BAABLgAECn8gAAMIAAkJ+RXPNwDIAQAIAAkJ+RXPNwDIAQAJAAIJvwRfdwBHAAAAAA==.',
['Ðï']='Ðï:BAAALgADCgQJBAAAAA==.',
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

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

local lookup = {'Unknown-Unknown','Monk-Windwalker','Shaman-Elemental','Warlock-Affliction','Priest-Shadow','Druid-Restoration','Druid-Balance','Evoker-Preservation','Paladin-Retribution','DemonHunter-Devourer','Warrior-Protection','Paladin-Holy','Hunter-Survival','Monk-Brewmaster','Mage-Frost','Druid-Guardian','Rogue-Subtlety','Warrior-Fury','Warlock-Destruction','DeathKnight-Unholy','Hunter-BeastMastery','Evoker-Augmentation','Evoker-Devastation','Shaman-Enhancement','DeathKnight-Blood','Warlock-Demonology','DemonHunter-Havoc','Priest-Holy','Monk-Mistweaver','Warrior-Arms','DemonHunter-Vengeance','Hunter-Marksmanship','DeathKnight-Frost',}
local provider = {region='US',realm='Eitrigg',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abominable:BAAALgADCgEJAQAAAA==.',
Ag='Agden:BAAALgADCgEJAQAAAA==.',
Al='Alairn:BAAALgAECgUJCgABLgAECgYJBwABAAAAAA==.Alenciann:BAAALgAECgMJBQAAAA==.Alys:BAABLgAECn8VAAICAAYJxQYlJQDGAAACAAYJxQYlJQDGAAAAAA==.',
Am='Amaniatres:BAAALgAECgEJAQAAAA==.Amoonranara:BAAALgADCgEJAQAAAA==.',
An='Anaan:BAAALgAECgQJBAAAAA==.Angrylizard:BAAALgAECgEJAQAAAA==.Anklebiterr:BAAALgAECgUJBgAAAA==.',
Ap='Apothecary:BAAALgADCgcJBwAAAA==.',
Ar='Arandomidiot:BAAALgADCgYJBgAAAA==.Ariiana:BAAALgADCgEJAQAAAA==.',
As='Asapshocky:BAACLgAFFH8GAAIDAAMJ6RIxEQD1AAADAAMJ6RIxEQD1AAAuAAQKfyEAAgMACAkYGT0LAOcBAAMACAkYGT0LAOcBAAAA.Asclepios:BAAALgAECgMJAwAAAA==.Astraroth:BAAALgADCgQJBAAAAA==.',
Av='Avella:BAAALgADCgUJBwAAAA==.',
Ba='Bamwham:BAAALgADCgcJBwAAAA==.Barrii:BAAALgADCgcJCgAAAA==.',
Be='Bearblaster:BAAALgADCgQJBAABLgAECgQJBgABAAAAAA==.Bearlytanks:BAAALgADCgIJAgAAAA==.Bellabelle:BAAALgADCggJFAAAAA==.Ben:BAAALgAECgcJEwAAAA==.Betterx:BAAALgAECgQJBQAAAA==.Bevian:BAAALgADCgIJAgABLgAECgIJAwABAAAAAA==.',
Bi='Biggiepants:BAAALgAECgUJCwAAAA==.Bighead:BAAALgADCgUJCwABLgAECgYJEgABAAAAAA==.Bintje:BAAALgADCgcJDQAAAA==.Biollante:BAAALgAECgcJCwAAAA==.',
Bl='Blindedlïght:BAAALgAECgQJBQAAAA==.',
Bo='Bolsan:BAAALgAECgMJBQAAAA==.Bourg:BAAALgAECgYJCAAAAA==.Bowhemian:BAAALgADCgkJDQAAAA==.',
Bu='Buckis:BAAALgAECgIJAgAAAA==.Bufú:BAAALgADCgIJAgAAAA==.',
Ca='Cajia:BAAALgAECgYJDAAAAA==.',
Ce='Celds:BAAALgADCgQJBAABLgAECgcJGQAEAPEbAA==.Celiae:BAAALgAECgYJEAAAAA==.Cendanel:BAAALgADCgYJCwAAAA==.',
Ch='Childress:BAAALgAECgMJAwAAAA==.Choggy:BAABLgAECn8VAAIFAAcJbhQFDwCYAQAFAAcJbhQFDwCYAQAAAA==.',
Ci='Cimbline:BAAALgADCgIJAgAAAA==.',
Cl='Clairerick:BAAALgAECgYJEAAAAA==.',
Co='Confessionn:BAAALgADCggJDAAAAA==.Cough:BAAALgAECgIJAwABLgAECgYJEgABAAAAAA==.',
Cr='Crinklecut:BAAALgAECgUJCgAAAA==.Critos:BAAALgADCgcJBwAAAA==.Crotchout:BAAALgADCgMJAwAAAA==.Crybaby:BAAALgADCgEJAQAAAA==.Crystilpixy:BAAALgADCgMJBAAAAA==.',
['Cé']='Céline:BAAALgAECgEJAQAAAA==.',
Da='Danilov:BAAALgADCgYJBgAAAA==.',
De='Deadlyshift:BAABLgAECn8XAAMGAAkJqyIPAQB4AwAGAAkJqyIPAQB4AwAHAAUJMhouNgBjAQAAAA==.Deadybear:BAAALgADCgIJAgABLgAECggJNgAIAD0UAA==.Delrok:BAAALgAECgEJAgAAAA==.Dephias:BAAALgADCgMJAwAAAA==.',
Di='Diagnosis:BAABLgAECn8cAAIJAAkJmiG7AQAsAwAJAAkJmiG7AQAsAwAAAA==.',
Do='Donnabb:BAAALgAECgUJBQAAAA==.Doran:BAAALgAECgUJBgAAAA==.Doriathrin:BAAALgADCgIJAgAAAA==.Doujinshi:BAABLgAECn8OAAIKAAcJ8xvbUwCoAQAKAAcJ8xvbUwCoAQAAAA==.',
Dr='Draedis:BAAALgAECgMJBQAAAA==.Dragonbladez:BAAALgADCgUJBQAAAA==.Dragoneye:BAAALgADCgkJDQAAAA==.Dragonhawk:BAAALgADCgQJBAABLgAECgMJEgABAAAAAA==.Drakoil:BAAALgAECgYJEgAAAA==.Dreademperor:BAACLgAFFH8JAAILAAQJdRUnBgAmAQALAAQJdRUnBgAmAQAuAAQKfyEAAgsACQnRHe8EAPYCAAsACQnRHe8EAPYCAAAA.Dreadnature:BAAALgAECgMJAwAAAA==.Dreadnight:BAAALgAFFAMJAwABLgAFFAQJCQALAHUVAA==.Dreadsteed:BAAALgAECgEJAQABLgAFFAQJCQALAHUVAA==.Drenrah:BAABLgAECn8kAAIMAAgJURHGEADcAQAMAAgJURHGEADcAQAAAA==.Drgndeeznutz:BAABLgAECn8cAAINAAkJ6BqfAwBcAgANAAkJ6BqfAwBcAgAAAA==.Drizz:BAAALgAECgIJAgAAAA==.Drunkenrage:BAACLgAFFH8WAAIOAAYJbSDhAAADAgAOAAYJbSDhAAADAgAuAAQKfx4AAg4ACQkcIv0BAIIDAA4ACQkcIv0BAIIDAAAA.',
Du='Dumorius:BAAALgAECgIJAgAAAA==.',
['Dé']='Déx:BAAALgAECgYJCwAAAA==.',
Ed='Edreth:BAAALgADCgYJBgAAAA==.',
El='Elbryan:BAABLgAECn8dAAIFAAgJpAPhHAAVAQAFAAgJpAPhHAAVAQAAAA==.Elementdemon:BAAALgAECgQJBQAAAA==.',
En='Enthalpy:BAABLgAECn8YAAIPAAYJZhvEggDMAQAPAAYJZhvEggDMAQAAAA==.',
Er='Erazath:BAAALgAECgUJCAABLgAECgcJDgABAAAAAA==.',
Es='Esperzoa:BAAALgAECgYJBgAAAA==.',
Et='Eternaldread:BAAALgADCgUJBQABLgAFFAQJCQALAHUVAA==.',
Eu='Eucalicdes:BAABLgAECn8jAAIQAAgJERS8BwBsAQAQAAgJERS8BwBsAQAAAA==.',
Fa='Farshran:BAAALgAECgcJDgAAAA==.Fate:BAAALgAECgQJBQABLgAECgkJHwAJADUkAA==.',
Fe='Felicity:BAACLgAFFH8NAAIRAAQJjRYJBwBeAQARAAQJjRYJBwBeAQAuAAQKfy0AAhEACQmMIpEEAE4DABEACQmMIpEEAE4DAAAA.Ferendis:BAABLgAECn8bAAIKAAYJZyKODwD2AQAKAAYJZyKODwD2AQAAAA==.Fernard:BAAALgADCgYJBgABLgAECggJDwAKAK8ZAA==.',
Fl='Florita:BAAALgADCgkJFQAAAA==.',
Fo='Fordinn:BAABLgAECn8VAAMLAAYJtRRsFQDfAAALAAUJWRNsFQDfAAASAAMJ/RJSSgBMAAAAAA==.',
Fr='Fractured:BAAALgADCgEJAQAAAA==.Freelor:BAAALgAECgIJAwAAAA==.Freemi:BAAALgAECgEJAQAAAA==.',
Fu='Fuddytwo:BAAALgAECgUJCgAAAA==.',
Ga='Garzhvog:BAAALgADCgcJCwABLgAECggJHwATAPwiAA==.Gasket:BAABLgAECn8fAAIUAAgJpSLCIgC0AgAUAAgJpSLCIgC0AgAAAA==.',
Gh='Ghorac:BAAALgADCgIJAgAAAA==.Ghoti:BAAALgADCgUJBQAAAA==.Ghoulz:BAAALgADCgcJDAAAAA==.',
Gl='Glazedham:BAAALgADCgMJAwAAAA==.',
Go='Gorbubbli:BAAALgADCgkJFgAAAA==.',
Gr='Graceful:BAAALgAECgQJBQAAAA==.Grit:BAAALgAECgEJAQAAAA==.',
Ha='Haeler:BAAALgAECgIJAwAAAA==.Haelin:BAAALgADCgEJAQAAAA==.Halgoðfulk:BAAALgAECgEJAQAAAA==.Hamwarrior:BAAALgAECgEJAQAAAA==.Handicap:BAAALgADCgYJBgABLgAECgkJHAAJAJohAA==.Hark:BAABLgAECn8fAAIVAAgJmxTxNwDOAQAVAAgJmxTxNwDOAQAAAA==.Harvin:BAABLgAECn8bAAIIAAYJtCHyBAAVAgAIAAYJtCHyBAAVAgAAAA==.',
He='Hekus:BAAALgAECgcJDgAAAA==.Helanua:BAAALgAECgYJCwAAAA==.',
Hi='Hibernate:BAAALgADCgEJAQAAAA==.Hippopotamus:BAAALgADCgQJBQAAAA==.Hit:BAAALgAECgUJCgAAAA==.',
Ho='Holytide:BAAALgAECgYJEgAAAA==.Hope:BAAALgAECgYJCwAAAA==.Horrorfang:BAABLgAECn8aAAIUAAYJLBZFNgBgAQAUAAYJLBZFNgBgAQAAAA==.',
Hu='Hukjo:BAAALgAECgcJDAAAAA==.',
Ib='Ibaar:BAACLgAFFH8MAAIWAAQJ8COBBQCfAQAWAAQJ8COBBQCfAQAuAAQKfykAAxYACQmnI24FAFUCABYACAkeI24FAFUCABcABgneIAENAAoCAAAA.',
Ic='Icepickle:BAAALgADCgcJAQAAAA==.',
Ii='Iilnut:BAAALgAECggJEgABLgAECggJFQACAJoZAA==.',
Il='Illedren:BAABLgAECn8QAAIKAAgJtwcskAAAAQAKAAgJtwcskAAAAQAAAA==.',
In='Innerdemon:BAAALgAECgQJBAAAAA==.Inno:BAABLgAECn8XAAIKAAgJ3iPyEwDhAgAKAAgJ3iPyEwDhAgAAAA==.',
Is='Isabel:BAAALgAECgYJBgAAAA==.',
It='Ithacus:BAABLgAECn8kAAIYAAgJ3xAyBgCpAQAYAAgJ3xAyBgCpAQAAAA==.',
Ja='Jandaar:BAAALgAECgEJAQAAAA==.Jattao:BAAALgADCgEJAQAAAA==.',
Jd='Jdawgprime:BAAALgADCgcJBwAAAA==.',
Je='Jenjas:BAAALgADCgcJBgAAAA==.',
Ji='Jinnlee:BAAALgADCgIJAgAAAA==.Jinoo:BAABLgAECn8aAAIDAAYJZBzwEwB5AQADAAYJZBzwEwB5AQAAAA==.',
Jo='Joe:BAAALgAECgcJBgAAAA==.Jorek:BAABLgAECn8WAAISAAkJ6BS5CAAfAgASAAkJ6BS5CAAfAgAAAA==.',
Ka='Kaihune:BAAALgADCgEJAQAAAA==.Kaiva:BAAALgADCgEJAQAAAA==.Kallistô:BAAALgADCgYJBgAAAA==.Kamigawa:BAAALgAECgYJDAAAAA==.Kavik:BAAALgAECgcJBwAAAA==.Kazbodan:BAAALgADCgkJFQAAAA==.',
Ke='Keemo:BAABLgAECn8eAAMZAAgJTBL6HQBZAQAZAAgJKBL6HQBZAQAUAAMJmA00/ACDAAAAAA==.Keemosaki:BAAALgAECgIJAwAAAA==.Keemõ:BAAALgAECgYJCwAAAA==.Keflá:BAAALgAECgQJCAAAAA==.Keysersöze:BAAALgADCgEJAQAAAA==.',
Kh='Khaas:BAABLgAECn8bAAIUAAYJMQnZUwAGAQAUAAYJMQnZUwAGAQAAAA==.Khaleeb:BAAALgAECgEJAwAAAA==.',
Ki='Kierios:BAAALgAECgQJBAAAAA==.Kildurgan:BAAALgAECgQJCQAAAA==.Killawarlock:BAABLgAECn8ZAAQaAAgJDSCiJQCZAQAaAAcJDSCiJQCZAQAEAAEJAABSJwBUAAATAAEJ/hARcAA2AAAAAA==.Kironn:BAAALgADCgYJBgABLgAECgYJEgABAAAAAA==.',
Kk='Kkain:BAAALgAECgIJBAAAAA==.',
Ko='Korihor:BAAALgAECgUJBQAAAA==.',
Kr='Krestus:BAABLgAECn8PAAMKAAYJrxkRfgAvAQAKAAYJrxkRfgAvAQAbAAEJAABxbwA2AAAAAA==.Krispy:BAAALgAECgYJEAAAAA==.Krith:BAAALgADCgYJCQAAAA==.Krix:BAAALgAECgMJBAAAAA==.',
Ky='Kyndil:BAAALgADCgMJAwAAAA==.',
La='Laxus:BAAALgADCgcJDAABLgAECggJEwABAAAAAA==.Lazarius:BAAALgADCgQJBAAAAA==.',
Le='Levophed:BAABLgAECn8uAAIUAAcJhQ+KPABJAQAUAAcJhQ+KPABJAQAAAA==.',
Li='Lightfallen:BAAALgAECgcJDgAAAA==.Liisara:BAABLgAECn8SAAIKAAYJNglHSADNAAAKAAYJNglHSADNAAAAAA==.Lily:BAABLgAECn8bAAIQAAYJSBwRCQBGAQAQAAYJSBwRCQBGAQAAAA==.Linadra:BAAALgAECgYJEwAAAA==.Littleyeti:BAAALgAECgMJAwAAAA==.Liyara:BAABLgAECn8hAAIJAAgJXSVIEQAGAwAJAAgJXSVIEQAGAwAAAA==.',
Ll='Llorsa:BAABLgAECn8bAAIcAAYJ8hFsHAAiAQAcAAYJ8hFsHAAiAQAAAA==.',
Lo='Lohhan:BAAALgADCgUJCQAAAA==.Lolamontez:BAAALgADCgcJBwAAAA==.Lorthys:BAAALgADCgEJAQAAAA==.',
Lu='Luxian:BAABLgAECn8UAAIJAAYJFwjDXAD8AAAJAAYJFwjDXAD8AAAAAA==.',
Ma='Mahiru:BAAALgADCgEJAQAAAA==.Mahralla:BAAALgADCgIJAgAAAA==.Maikagond:BAAALgADCgMJAwABLgAECgUJCgABAAAAAA==.Makaria:BAAALgAECgUJBwAAAA==.Malbisa:BAAALgADCgcJDQAAAA==.Malphoz:BAAALgADCggJCAAAAA==.Mandragora:BAAALgAECgIJAwAAAA==.Mattieatzdot:BAAALgAECgQJBQAAAA==.',
Mc='Mcgrowlin:BAAALgAECgQJCgAAAA==.',
Me='Meko:BAAALgAECgUJBgAAAA==.',
Mi='Mickey:BAABLgAECn8fAAICAAgJbCAXCQDmAgACAAgJbCAXCQDmAgAAAA==.Migraine:BAAALgAECgYJCgAAAA==.Mikiik:BAABLgAECn8bAAIaAAYJnwisTwABAQAaAAYJnwisTwABAQAAAA==.Mildoo:BAABLgAECn8iAAIEAAgJBg95AgC0AQAEAAgJBg95AgC0AQAAAA==.Milkymoo:BAAALgAECgUJCQAAAA==.Millina:BAAALgADCgIJAgABLgAECgYJFQACAMUGAA==.Minipal:BAAALgAECgYJBwAAAA==.Mixednuts:BAABLgAECn8VAAMCAAgJmhmjHwDaAQACAAYJ8x+jHwDaAQAdAAYJ2xABJgDRAAAAAA==.',
Mo='Mochii:BAAALgADCgYJBgAAAA==.Monq:BAABLgAECn8VAAMCAAcJFReDEQBpAQACAAcJFReDEQBpAQAOAAEJyAkljQAqAAAAAA==.Moonamber:BAAALgADCgQJBgAAAA==.Morithus:BAAALgADCgkJDgAAAA==.Morphinzerr:BAAALgAECgEJAQAAAA==.',
My='Mythion:BAAALgAECgUJCgAAAA==.Mythoridan:BAAALgAECgEJAQAAAA==.',
Na='Naeres:BAABLgAECn8fAAIUAAgJjxdsHwDLAQAUAAgJjxdsHwDLAQAAAA==.Nafari:BAAALgADCgkJEQAAAA==.Naomii:BAABLgAECn8cAAMcAAgJjRW5JADDAQAcAAgJjRW5JADDAQAFAAQJtgjUKgCqAAAAAA==.Naturefury:BAAALgADCgEJAQAAAA==.',
Ne='Neeston:BAABLgAECn8gAAMGAAgJBiPTAwD1AgAGAAgJBiPTAwD1AgAHAAEJZRLOgAAwAAAAAA==.Neodin:BAAALgAECgUJDgAAAA==.Nephadin:BAAALgADCgUJAwAAAA==.Nerfed:BAAALgAECgMJBAAAAA==.Neviaa:BAAALgAECgYJEwAAAA==.',
Ni='Nickypoo:BAAALgADCgMJAwAAAA==.Nightmenace:BAAALgAECgcJCwAAAA==.Ninari:BAAALgADCgUJBQAAAA==.Niq:BAAALgAECgQJBAAAAA==.',
No='Nocshadue:BAAALgADCgUJBQAAAA==.Nordga:BAAALgADCgcJBwAAAA==.Nothealster:BAAALgAECgcJEgAAAA==.',
Ob='Obsidiian:BAAALgAECgcJDgAAAA==.Obsidion:BAAALgAECgQJBQABLgAECgYJFQALALUUAA==.',
Od='Odie:BAAALgAECgYJCAAAAA==.',
On='Onlyfangs:BAABLgAECn82AAMIAAgJPRR9BQABAgAIAAgJPRR9BQABAgAWAAEJ6gG/aAAkAAAAAA==.',
Os='Oscrapermort:BAAALgADCgMJAwAAAA==.',
Pa='Padivyn:BAAALgAECgUJBQAAAA==.',
Pe='Peanads:BAAALgADCgUJBAAAAA==.Pebblez:BAAALgADCgcJDgAAAA==.Perry:BAAALgAECgcJDgAAAA==.',
Po='Po:BAAALgAECgkJCAAAAA==.Pozufuma:BAABLgAECn8bAAISAAYJGxk7FQCKAQASAAYJGxk7FQCKAQAAAA==.',
Pr='Priestcraft:BAAALgADCgIJAgABLgAECggJCgABAAAAAA==.',
Ps='Psychomantis:BAABLgAECn8kAAMFAAgJFxU5CwDLAQAFAAgJFxU5CwDLAQAcAAEJQgT/hAAsAAAAAA==.',
Pu='Punchypunch:BAAALgADCgkJFAAAAA==.',
Ra='Raek:BAAALgAECgQJBQABLgAECgcJGQAEAPEbAA==.Ravenbyrd:BAAALgADCgMJAwAAAA==.Rawberriez:BAAALgAECgQJBgAAAA==.',
Re='Reani:BAAALgADCgQJBAAAAA==.Reapin:BAAALgADCgUJBQAAAA==.Redpool:BAABLgAECn8dAAIVAAcJWBCwKgBqAQAVAAcJWBCwKgBqAQAAAA==.Remithedrood:BAAALgADCgIJAgAAAA==.Reqium:BAAALgADCgYJCAAAAA==.Resto:BAAALgAECgQJBgAAAA==.Rethandra:BAAALgAECgQJBQAAAA==.',
Ri='Rion:BAABLgAECn8XAAIPAAkJbhEeHgD3AQAPAAkJbhEeHgD3AQAAAA==.Ristvakbaen:BAABLgAECn8fAAMTAAgJ/CITAgACAgAaAAgJLx1zDgA3AgATAAYJXCQTAgACAgAAAA==.',
Ro='Robynlee:BAABLgAECn8cAAIcAAgJoRB6IwDKAQAcAAgJoRB6IwDKAQAAAA==.Rogùe:BAAALgAECgEJAgAAAA==.',
Ru='Rugratt:BAAALgADCgQJBAABLgADCgcJDgABAAAAAA==.',
Sa='Saeler:BAAALgAECgMJAwAAAA==.Samoth:BAAALgADCgEJAQAAAA==.Sanctuary:BAAALgAECgQJBAAAAA==.Santeclair:BAAALgAECgEJAQAAAA==.',
Sc='Sceryna:BAABLgAECn8hAAIJAAgJbBfdHQDWAQAJAAgJbBfdHQDWAQAAAA==.Schiftly:BAAALgAECgYJBwAAAA==.Schwiggity:BAAALgADCgcJBwABLgAECgIJAwABAAAAAA==.Scrmndemn:BAABLgAECn8WAAIJAAcJ8gOAaQDdAAAJAAcJ8gOAaQDdAAAAAA==.',
Se='Sepviva:BAABLgAECn8VAAIUAAcJNRZccACoAQAUAAcJNRZccACoAQAAAA==.Serpent:BAABLgAECn8UAAILAAkJBhz2AgBqAgALAAkJBhz2AgBqAgAAAA==.',
Sh='Shadowheal:BAAALgADCgUJBgAAAA==.Shamadeus:BAAALgADCgUJBQABLgAECggJHwATAPwiAA==.Sharaseth:BAAALgAECgYJCAAAAA==.Shikita:BAABLgAECn8bAAMGAAYJPyDPJQAhAgAGAAYJPyDPJQAhAgAHAAEJHAZSigAlAAAAAA==.Shimadin:BAACLgAFFH8NAAIJAAQJFBT4EQA9AQAJAAQJFBT4EQA9AQAuAAQKfx0AAgkACAkOHyIvAGYCAAkACAkOHyIvAGYCAAAA.Shimpbizkit:BAAALgAECgUJCgABLgAFFAQJDQAJABQUAA==.Shimsong:BAAALgADCgYJDAABLgAFFAQJDQAJABQUAA==.Shmerek:BAABLgAECn8XAAILAAkJLyABAQDlAgALAAkJLyABAQDlAgAAAA==.',
Si='Sidarien:BAAALgADCgQJBAAAAA==.Silverlumen:BAAALgADCgkJCgAAAA==.Silverstream:BAABLgAECn8nAAIGAAgJMRMaQgCZAQAGAAgJMRMaQgCZAQAAAA==.',
Sk='Skyblue:BAAALgADCgEJAQAAAA==.',
Sl='Slease:BAAALgADCgYJBgAAAA==.',
Sm='Smootish:BAAALgADCgUJBQAAAA==.',
Sn='Snoman:BAAALgADCgYJBgAAAA==.',
So='Solbin:BAAALgAECgQJBQAAAA==.Solitudé:BAABLgAECn8XAAMaAAYJ4iIOGADnAQAaAAUJPiIOGADnAQAEAAIJRyV2FgDOAAAAAA==.Soteirian:BAAALgAECgUJCgAAAA==.',
Sp='Spekey:BAAALgADCgMJBgAAAA==.Spider:BAAALgAECgUJDQAAAA==.Spineymagus:BAAALgADCgIJAgAAAA==.',
Sq='Squall:BAAALgAECgUJDAAAAA==.',
St='Stalariais:BAAALgAECgQJBAABLgAECggJGAAMADsJAA==.Stardrand:BAAALgADCgUJBgAAAA==.Steelreserve:BAAALgAECgYJDQAAAA==.Straw:BAAALgAECgEJAQABLgAECggJHgAJAI4iAA==.',
Su='Sugarkitty:BAAALgADCgYJCgAAAA==.Supereclipse:BAABLgAECn8bAAIVAAYJSRDoNQA6AQAVAAYJSRDoNQA6AQAAAA==.',
Sw='Swolareclips:BAAALgADCgYJBgAAAA==.',
Sy='Sydvicious:BAABLgAECn8hAAIbAAgJIyU3AQDjAgAbAAgJIyU3AQDjAgAAAA==.Syriene:BAAALgAECgYJDQAAAA==.',
Ta='Tankhealz:BAAALgAECgIJAgAAAA==.',
Tb='Tbsp:BAAALgAECgEJAQAAAA==.',
Te='Tecks:BAABLgAECn8XAAIcAAkJwwVLGgA1AQAcAAkJwwVLGgA1AQAAAA==.Teddy:BAAALgAECgUJCQAAAA==.',
Th='Theatrix:BAAALgAECgMJAwAAAA==.Thecuckler:BAAALgAECgQJCAAAAA==.Thefreeman:BAAALgAECgEJAQAAAA==.Themajor:BAABLgAECn8cAAMeAAgJsxI2BgC8AQAeAAgJlhI2BgC8AQASAAcJ/AhpTAB0AQAAAA==.Then:BAAALgADCgEJAQAAAA==.Thiarad:BAAALgADCgEJAQAAAA==.Thrain:BAAALgADCgcJDAAAAA==.Threat:BAABLgAECn8fAAIJAAkJNSQFAQBSAwAJAAkJNSQFAQBSAwAAAA==.Thsarus:BAABLgAECn8bAAMKAAcJGB+CFADGAQAKAAcJGB+CFADGAQAfAAQJHBHPGwCxAAAAAA==.',
Ti='Tiamaat:BAABLgAECn8XAAIGAAkJmQQXPADiAAAGAAkJmQQXPADiAAAAAA==.Tireyne:BAAALgADCgEJAgAAAA==.Titus:BAAALgAECgEJAwAAAA==.',
Tr='Treadlightly:BAAALgADCgUJBwAAAA==.Treefróg:BAAALgAECgUJBQAAAA==.Trentus:BAAALgADCgIJAgAAAA==.Trev:BAAALgAECgUJBgABLgAECgYJHAATAFAhAA==.',
Ts='Tsp:BAACLgAFFH8NAAIdAAQJ9QijDgDwAAAdAAQJ9QijDgDwAAAuAAQKfyQAAx0ACQlkFjAUACgCAB0ACQlkFjAUACgCAA4ABAnuA0BsAJEAAAAA.',
Ty='Tyletos:BAAALgAECgYJEwAAAA==.',
Ug='Ugolok:BAAALgAECgUJBgAAAA==.',
Ur='Uriél:BAABLgAECn8ZAAIKAAgJjCOkHwCTAgAKAAgJjCOkHwCTAgAAAA==.',
Ve='Veiler:BAABLgAECn8iAAMVAAgJug1cIwCPAQAVAAgJug1cIwCPAQAgAAEJ3wHnlgAhAAAAAA==.Velca:BAAALgAECgIJAgAAAA==.Veruca:BAAALgAECgMJAwAAAA==.Veviseron:BAABLgAECn8kAAIPAAgJpAOAXAAkAQAPAAgJpAOAXAAkAQAAAA==.',
Vh='Vhye:BAAALgAECgYJCQAAAA==.',
Vi='Vinstalation:BAABLgAECn8bAAIhAAYJNR6OBAAUAgAhAAYJNR6OBAAUAgAAAA==.Vissa:BAAALgADCgYJBgAAAA==.',
Vo='Vonbismarck:BAABLgAECn8fAAIVAAgJLRSZHQCuAQAVAAgJLRSZHQCuAQAAAA==.',
Vr='Vritraz:BAAALgAECgQJBAAAAA==.Vrock:BAAALgAECgEJAQABLgAECgYJGAAPAGYbAA==.',
Wa='Warnam:BAAALgADCgcJBwAAAA==.Warsonge:BAAALgADCgMJAwAAAA==.',
We='Wendypini:BAABLgAECn8aAAIVAAgJdA5YRQCbAQAVAAgJdA5YRQCbAQAAAA==.Wetnwild:BAAALgADCgQJBAAAAA==.',
Wh='Whitehand:BAAALgAECgIJAgAAAA==.',
Wo='Wooshwoosh:BAAALgAECgMJBAAAAA==.',
Wu='Wudeeps:BAAALgAECgcJEgAAAA==.Wuhanwarrior:BAAALgAECgUJDgAAAA==.',
Ya='Yako:BAAALgAECgEJAQAAAA==.',
Ye='Yennefer:BAAALgADCgIJAgAAAA==.',
Za='Zangolf:BAAALgADCgUJBAAAAA==.',
Ze='Zearas:BAABLgAECn8UAAIUAAgJJREvkwBZAQAUAAgJJREvkwBZAQAAAA==.Zendonn:BAAALgAECgMJCgAAAA==.',
Zi='Zicatriz:BAAALgADCgcJDgAAAA==.',
Zo='Zodiaac:BAABLgAECn8XAAIZAAkJcBnDBADwAQAZAAkJcBnDBADwAQAAAA==.',
Zy='Zy:BAAALgADCgUJBQAAAA==.',
['Ëc']='Ëchõ:BAABLgAECn8fAAMGAAkJ1xXQNwDIAQAGAAkJ1xXQNwDIAQAHAAIJvwRZdwBHAAAAAA==.',
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

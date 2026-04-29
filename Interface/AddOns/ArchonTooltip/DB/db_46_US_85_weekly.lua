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

local lookup = {'Monk-Windwalker','Shaman-Elemental','Unknown-Unknown','Warlock-Affliction','Druid-Restoration','Druid-Balance','Evoker-Preservation','DemonHunter-Devourer','Warrior-Protection','Paladin-Holy','Hunter-Survival','Monk-Brewmaster','Priest-Shadow','Mage-Frost','Druid-Guardian','Paladin-Retribution','Rogue-Subtlety','Warrior-Fury','Warlock-Destruction','DeathKnight-Unholy','Hunter-BeastMastery','Evoker-Augmentation','Evoker-Devastation','Shaman-Enhancement','DeathKnight-Blood','Warlock-Demonology','DemonHunter-Havoc','Priest-Holy','DemonHunter-Vengeance','Monk-Mistweaver','Hunter-Marksmanship','DeathKnight-Frost',}
local provider = {region='US',realm='Eitrigg',name='US',type='weekly',zone=46,date='2026-04-24',data={Ag='Agden:BAAALgADCgEJAQAAAA==.',
Al='Alairn:BAAALgAECgUJCgAAAA==.Alenciann:BAAALgAECgMJBQAAAA==.Alys:BAABLgAECn8VAAIBAAYJxQZXEADNAAABAAYJxQZXEADNAAAAAA==.',
Am='Amaniatres:BAAALgADCgQJBQAAAA==.Amoonranara:BAAALgADCgEJAQAAAA==.',
An='Anaan:BAAALgAECgQJBAAAAA==.Angrylizard:BAAALgAECgEJAQAAAA==.Anklebiterr:BAAALgAECgUJBgAAAA==.',
Ap='Apothecary:BAAALgADCgcJBwAAAA==.',
As='Asapshocky:BAABLgAECn8hAAICAAgJGBk+BADoAQACAAgJGBk+BADoAQAAAA==.Astraroth:BAAALgADCgQJBAAAAA==.',
Av='Avella:BAAALgADCgUJBwAAAA==.',
Ba='Barrii:BAAALgADCgcJCgAAAA==.',
Be='Bearblaster:BAAALgADCgQJBAAAAA==.Bearlytanks:BAAALgADCgIJAgAAAA==.Bellabelle:BAAALgADCggJDQAAAA==.Ben:BAAALgAECgcJEwAAAA==.Betterx:BAAALgAECgQJBQAAAA==.Bevian:BAAALgADCgIJAgABLgAECgEJAQADAAAAAA==.',
Bi='Biggiepants:BAAALgAECgUJCwAAAA==.Bighead:BAAALgADCgUJCwABLgAFFAEJAQADAAAAAA==.Bintje:BAAALgADCgcJBwAAAA==.Biollante:BAAALgAECgcJCwAAAA==.',
Bl='Blindedlïght:BAAALgAECgQJBQAAAA==.',
Bo='Bolsan:BAAALgAECgMJBQAAAA==.Bowhemian:BAAALgADCgkJDQAAAA==.',
Bu='Buckis:BAAALgADCgkJEgAAAA==.Bufú:BAAALgADCgIJAgAAAA==.',
Ca='Cajia:BAAALgAECgUJBgAAAA==.',
Ce='Celds:BAAALgADCgQJBAABLgAECgYJFwAEANMeAA==.Celiae:BAAALgAECgYJEAAAAA==.Cendanel:BAAALgADCgYJCwAAAA==.',
Ch='Childress:BAAALgAECgMJAwAAAA==.Choggy:BAAALgAECgYJDAAAAA==.',
Ci='Cimbline:BAAALgADCgIJAgAAAA==.',
Cl='Clairerick:BAAALgAECgYJEAAAAA==.',
Co='Confessionn:BAAALgADCgYJCQAAAA==.Cough:BAAALgAECgIJAwABLgAFFAEJAQADAAAAAA==.',
Cr='Crinklecut:BAAALgAECgQJBwAAAA==.Critos:BAAALgADCgcJBwAAAA==.Crotchout:BAAALgADCgMJAwAAAA==.Crybaby:BAAALgADCgEJAQAAAA==.Crystilpixy:BAAALgADCgMJBAAAAA==.',
['Cé']='Céline:BAAALgAECgEJAQAAAA==.',
De='Deadlyshift:BAABLgAECn8VAAMFAAgJASOVAAAqAwAFAAgJASOVAAAqAwAGAAUJMhowNgBjAQAAAA==.Deadybear:BAAALgADCgIJAgABLgAECgcJKwAHAIoWAA==.Delrok:BAAALgAECgEJAQAAAA==.Dephias:BAAALgADCgMJAwAAAA==.',
Di='Diagnosis:BAAALgAECggJEwAAAA==.',
Do='Donnabb:BAAALgAECgUJBQAAAA==.Doran:BAAALgAECgUJBQAAAA==.Doriathrin:BAAALgADCgEJAQAAAA==.Doujinshi:BAABLgAECn8VAAIIAAgJEBliCwC+AQAIAAgJEBliCwC+AQAAAA==.',
Dr='Draedis:BAAALgAECgMJBQAAAA==.Dragonbladez:BAAALgADCgUJBQAAAA==.Dragoneye:BAAALgADCgkJDQAAAA==.Dragonhawk:BAAALgADCgQJBAABLgAECgMJDwADAAAAAA==.Drakoil:BAAALgAECgYJDAAAAA==.Dreademperor:BAACLgAFFH8IAAIJAAMJlRqCAwDoAAAJAAMJlRqCAwDoAAAuAAQKfyEAAgkACQn3HewEAPYCAAkACQn3HewEAPYCAAAA.Dreadnature:BAAALgAECgMJAwAAAA==.Dreadsteed:BAAALgAECgEJAQABLgAFFAMJCAAJAJUaAA==.Drenrah:BAABLgAECn8dAAIKAAgJ7QykCAC7AQAKAAgJ7QykCAC7AQAAAA==.Drgndeeznutz:BAABLgAECn8WAAILAAkJSxlEBADXAgALAAkJSxlEBADXAgAAAA==.Drizz:BAAALgAECgIJAgAAAA==.Drunkenrage:BAACLgAFFH8QAAIMAAUJCh5sAgDKAQAMAAUJCh5sAgDKAQAuAAQKfx4AAgwACQkcIvsBAIIDAAwACQkcIvsBAIIDAAAA.',
Du='Dumorius:BAAALgAECgIJAgAAAA==.',
['Dé']='Déx:BAAALgAECgYJCwAAAA==.',
Ed='Edreth:BAAALgADCgYJBgAAAA==.',
El='Elbryan:BAABLgAECn8VAAINAAcJEAP9EADnAAANAAcJEAP9EADnAAAAAA==.Elementdemon:BAAALgAECgQJBQAAAA==.',
En='Enthalpy:BAABLgAECn8YAAIOAAYJZhvUggDMAQAOAAYJZhvUggDMAQAAAA==.',
Er='Erazath:BAAALgAECgUJCAABLgAECgcJDgADAAAAAA==.',
Es='Esperzoa:BAAALgAECgUJBQAAAA==.',
Et='Eternaldread:BAAALgADCgUJBQABLgAFFAMJCAAJAJUaAA==.',
Eu='Eucalicdes:BAABLgAECn8bAAIPAAgJfhGYEABsAQAPAAgJfhGYEABsAQAAAA==.',
Fa='Farshran:BAAALgAECgcJDgAAAA==.Fate:BAAALgADCgcJDQABLgAECggJHQAQAAclAA==.',
Fe='Felicity:BAACLgAFFH8JAAIRAAMJQBvrBAAaAQARAAMJQBvrBAAaAQAuAAQKfygAAhEACQnbH5AEAE8DABEACQnbH5AEAE8DAAAA.Ferendis:BAABLgAECn8VAAIIAAYJ8hnhFgBHAQAIAAYJ8hnhFgBHAQAAAA==.Fernard:BAAALgADCgYJBgABLgAECggJFQAIAPcaAA==.',
Fl='Florita:BAAALgADCgkJDwAAAA==.',
Fo='Fordinn:BAABLgAECn8VAAMJAAYJtRQeCgDfAAAJAAUJWRMeCgDfAAASAAMJ/RICJQBQAAAAAA==.',
Fr='Fractured:BAAALgADCgEJAQAAAA==.Freelor:BAAALgAECgEJAQAAAA==.Freemi:BAAALgAECgEJAQAAAA==.',
Fu='Fuddytwo:BAAALgAECgQJBQAAAA==.',
Ga='Garzhvog:BAAALgADCgcJCwABLgAECgcJFwATAOgjAA==.Gasket:BAABLgAECn8bAAIUAAgJQiG/IgC0AgAUAAgJQiG/IgC0AgAAAA==.',
Gh='Ghoti:BAAALgADCgUJBQAAAA==.Ghoulz:BAAALgADCgcJDAAAAA==.',
Gl='Glazedham:BAAALgADCgMJAwAAAA==.',
Go='Gorbubbli:BAAALgADCgkJEAAAAA==.',
Gr='Graceful:BAAALgAECgQJBQAAAA==.Grit:BAAALgADCgYJBgAAAA==.',
Ha='Haeler:BAAALgAECgIJAwAAAA==.Haelin:BAAALgADCgEJAQAAAA==.Halgoðfulk:BAAALgAECgEJAQAAAA==.Hamwarrior:BAAALgAECgEJAQAAAA==.Handicap:BAAALgADCgYJBgABLgAECggJEwADAAAAAA==.Hark:BAABLgAECn8bAAIVAAgJxhP2NwDOAQAVAAgJxhP2NwDOAQAAAA==.Harvin:BAABLgAECn8VAAIHAAYJtCHzAQAUAgAHAAYJtCHzAQAUAgAAAA==.',
He='Hekus:BAAALgAECgcJDgAAAA==.Helanua:BAAALgAECgYJCwAAAA==.',
Hi='Hibernate:BAAALgADCgEJAQAAAA==.Hippopotamus:BAAALgADCgQJBQAAAA==.Hit:BAAALgAECgUJCgAAAA==.',
Ho='Holytide:BAAALgAECgYJDAAAAA==.Hope:BAAALgAECgYJBwAAAA==.Horrorfang:BAABLgAECn8UAAIUAAYJCRJuGgBCAQAUAAYJCRJuGgBCAQAAAA==.',
Hu='Hukjo:BAAALgAECgQJBQAAAA==.',
Ib='Ibaar:BAACLgAFFH8IAAIWAAMJqCLPBQAuAQAWAAMJqCLPBQAuAQAuAAQKfyYAAxYACQkHI9YBAE4CABYACAl+ItYBAE4CABcABgneIAINAAoCAAAA.',
Ii='Iilnut:BAAALgAECggJEQABLgAECgYJDgADAAAAAA==.',
Il='Illedren:BAABLgAECn8VAAIIAAgJjgakIAAHAQAIAAgJjgakIAAHAQAAAA==.',
In='Innerdemon:BAAALgAECgQJBAAAAA==.Inno:BAABLgAECn8dAAIIAAgJsCNlAQDIAgAIAAgJsCNlAQDIAgAAAA==.',
Is='Isabel:BAAALgAECgYJBgAAAA==.',
It='Ithacus:BAABLgAECn8dAAIYAAgJxg5fAwCZAQAYAAgJxg5fAwCZAQAAAA==.',
Ja='Jandaar:BAAALgAECgEJAQAAAA==.Jattao:BAAALgADCgEJAQAAAA==.',
Jd='Jdawgprime:BAAALgADCgcJBwAAAA==.',
Je='Jenjas:BAAALgADCgcJBgAAAA==.',
Ji='Jinnlee:BAAALgADCgEJAQAAAA==.Jinoo:BAABLgAECn8VAAICAAYJohscCgBaAQACAAYJohscCgBaAQAAAA==.',
Jo='Joe:BAAALgAECgUJBQAAAA==.Jorek:BAABLgAECn8UAAISAAgJDBctBQDeAQASAAgJDBctBQDeAQAAAA==.',
Ka='Kaihune:BAAALgADCgEJAQAAAA==.Kaiva:BAAALgADCgEJAQAAAA==.Kallistô:BAAALgADCgYJBgAAAA==.Kamigawa:BAAALgAECgQJBgAAAA==.Kazbodan:BAAALgADCgkJFQAAAA==.',
Ke='Keemo:BAABLgAECn8aAAMZAAgJARL6HQBZAQAZAAgJ3RH6HQBZAQAUAAMJmA0c/ACDAAAAAA==.Keemosaki:BAAALgAECgEJAQAAAA==.Keemõ:BAAALgAECgYJBgAAAA==.Keflá:BAAALgAECgMJBAAAAA==.Keysersöze:BAAALgADCgEJAQAAAA==.',
Kh='Khaas:BAABLgAECn8VAAIUAAYJPQjaJQD+AAAUAAYJPQjaJQD+AAAAAA==.Khaleeb:BAAALgAECgEJAQAAAA==.',
Ki='Kierios:BAAALgADCgYJBgAAAA==.Kildurgan:BAAALgAECgQJBQAAAA==.Killawarlock:BAABLgAECn8VAAQaAAgJPx1BUADXAQAaAAcJPx1BUADXAQAEAAEJAABRJwBUAAATAAEJ/hALcAA2AAAAAA==.Kironn:BAAALgADCgYJBgABLgAFFAEJAQADAAAAAA==.',
Kk='Kkain:BAAALgADCgYJCAAAAA==.',
Ko='Korihor:BAAALgAECgQJBAAAAA==.',
Kr='Krestus:BAABLgAECn8VAAMIAAgJ9xqgBABEAgAIAAgJ9xqgBABEAgAbAAEJAABxbwA2AAAAAA==.Krispy:BAAALgAECgYJEAAAAA==.Krith:BAAALgADCgYJCQAAAA==.Krix:BAAALgAECgMJBAAAAA==.',
Ky='Kyndil:BAAALgADCgMJAwAAAA==.',
La='Laxus:BAAALgADCgcJDAABLgAECggJEwADAAAAAA==.Lazarius:BAAALgADCgQJBAAAAA==.',
Le='Levophed:BAABLgAECn8hAAIUAAcJLw7CGgBAAQAUAAcJLw7CGgBAAQAAAA==.',
Li='Lightfallen:BAAALgAECgYJDAAAAA==.Liisara:BAAALgAECgYJEAAAAA==.Lily:BAABLgAECn8VAAIPAAYJAhsLDwCMAQAPAAYJAhsLDwCMAQAAAA==.Linadra:BAAALgAECgYJEwAAAA==.Littleyeti:BAAALgAECgMJAwAAAA==.Liyara:BAABLgAECn8dAAIQAAgJ6SRCEQAGAwAQAAgJ6SRCEQAGAwAAAA==.',
Ll='Llorsa:BAABLgAECn8VAAIcAAYJfBGHDAApAQAcAAYJfBGHDAApAQAAAA==.',
Lo='Lohhan:BAAALgADCgUJCQAAAA==.Lorthys:BAAALgADCgEJAQAAAA==.',
Lu='Luxian:BAAALgAECgYJDgAAAA==.',
Ma='Mahralla:BAAALgADCgIJAgAAAA==.Maikagond:BAAALgADCgMJAwABLgAECgQJBAADAAAAAA==.Makaria:BAAALgAECgEJAQAAAA==.Malbisa:BAAALgADCgcJDQAAAA==.Malphoz:BAAALgADCggJCAAAAA==.Mandragora:BAAALgAECgEJAQAAAA==.Mattieatzdot:BAAALgAECgQJBQAAAA==.',
Mc='Mcgrowlin:BAAALgAECgQJCgAAAA==.',
Me='Meko:BAAALgAECgQJBQAAAA==.',
Mi='Mickey:BAABLgAECn8cAAIBAAgJYiAXCQDnAgABAAgJYiAXCQDnAgAAAA==.Migraine:BAAALgAECgYJCgAAAA==.Mikiik:BAABLgAECn8VAAIaAAYJhQacKQDnAAAaAAYJhQacKQDnAAAAAA==.Mildoo:BAABLgAECn8bAAIEAAcJXQ+eAQB8AQAEAAcJXQ+eAQB8AQAAAA==.Milkymoo:BAAALgAECgMJBQABLgAFFAUJEwAcAN4VAA==.Millina:BAAALgADCgIJAgABLgAECgYJFQABAMUGAA==.Minipal:BAAALgAECgUJBgABLgAECgUJCgADAAAAAA==.Mixednuts:BAAALgAECgYJDgAAAA==.',
Mo='Mochii:BAAALgADCgYJBgAAAA==.Monq:BAAALgAECgYJEgAAAA==.Moonamber:BAAALgADCgQJBgAAAA==.Morithus:BAAALgADCgkJDgAAAA==.Morphinzerr:BAAALgAECgEJAQAAAA==.',
My='Mythion:BAAALgAECgQJBQAAAA==.Mythoridan:BAAALgAECgEJAQAAAA==.',
Na='Naeres:BAABLgAECn8XAAIUAAcJLBasGwA6AQAUAAcJLBasGwA6AQAAAA==.Nafari:BAAALgADCgkJEQAAAA==.Naomii:BAABLgAECn8bAAMcAAYJNhi4JADDAQAcAAYJNhi4JADDAQANAAUJugj4EQDZAAAAAA==.Naturefury:BAAALgADCgEJAQAAAA==.',
Ne='Neeston:BAABLgAECn8gAAMFAAgJBiPhAAAKAwAFAAgJBiPhAAAKAwAGAAEJZRLDgAAwAAAAAA==.Neodin:BAAALgAECgUJCQAAAA==.Nephadin:BAAALgADCgUJAwAAAA==.Nerfed:BAAALgAECgMJAwAAAA==.Neviaa:BAAALgAECgYJEwAAAA==.',
Ni='Nickypoo:BAAALgADCgMJAwAAAA==.Nightmenace:BAAALgAECgcJBwAAAA==.Ninari:BAAALgADCgUJBQAAAA==.Niq:BAAALgAECgQJBAAAAA==.',
No='Nocshadue:BAAALgADCgUJBQAAAA==.Nordga:BAAALgADCgcJBwAAAA==.Nothealster:BAAALgAECgcJDAAAAA==.',
Ob='Obsidiian:BAAALgAECgUJBwAAAA==.Obsidion:BAAALgAECgEJAQABLgAECgYJFQAJALUUAA==.',
Od='Odie:BAAALgAECgYJBwAAAA==.',
On='Onlyfangs:BAABLgAECn8rAAMHAAcJihY6BACHAQAHAAYJfhY6BACHAQAWAAEJ6gG1aAAkAAAAAA==.',
Os='Oscrapermort:BAAALgADCgMJAwAAAA==.',
Pa='Padivyn:BAAALgAECgQJBAAAAA==.',
Pe='Peanads:BAAALgADCgUJBAAAAA==.Pebblez:BAAALgADCgcJDgAAAA==.Perry:BAAALgAECgYJBwAAAA==.',
Po='Po:BAAALgAECgkJCAAAAA==.Pozufuma:BAABLgAECn8VAAISAAYJ4heACwBnAQASAAYJ4heACwBnAQAAAA==.',
Pr='Priestcraft:BAAALgADCgIJAgABLgADCgcJDAADAAAAAA==.',
Ps='Psychomantis:BAABLgAECn8dAAMNAAgJFxVEBQC+AQANAAgJFxVEBQC+AQAcAAEJQgT0hAAsAAAAAA==.',
Pu='Punchypunch:BAAALgADCgkJDwAAAA==.',
Ra='Raek:BAAALgAECgQJBQABLgAECgYJFwAEANMeAA==.Ravenbyrd:BAAALgADCgMJAwAAAA==.Rawberriez:BAAALgAECgQJBgAAAA==.',
Re='Reani:BAAALgADCgQJBAAAAA==.Reapin:BAAALgADCgUJBQAAAA==.Redpool:BAABLgAECn8XAAIVAAcJWBAGEQB2AQAVAAcJWBAGEQB2AQAAAA==.Remithedrood:BAAALgADCgIJAgAAAA==.Reqium:BAAALgADCgYJCAAAAA==.Resto:BAAALgAECgQJBgAAAA==.Rethandra:BAAALgAECgEJAQAAAA==.',
Ri='Rion:BAABLgAECn8VAAIOAAgJoRE4EgCwAQAOAAgJoRE4EgCwAQAAAA==.Ristvakbaen:BAABLgAECn8XAAMTAAcJ6COnAAAOAgATAAYJXCSnAAAOAgAaAAIJhiC90QC2AAAAAA==.',
Ro='Robynlee:BAABLgAECn8cAAIcAAgJoRAECACEAQAcAAgJoRAECACEAQAAAA==.Rogùe:BAAALgAECgEJAQAAAA==.',
Ru='Rugratt:BAAALgADCgQJBAABLgADCgcJDgADAAAAAA==.',
Sa='Saeler:BAAALgAECgMJAwAAAA==.Samoth:BAAALgADCgEJAQAAAA==.Santeclair:BAAALgAECgEJAQAAAA==.',
Sc='Sceryna:BAABLgAECn8dAAIQAAgJyBZgDADOAQAQAAgJyBZgDADOAQAAAA==.Schiftly:BAAALgAECgYJBwAAAA==.Scrmndemn:BAABLgAECn8UAAIQAAYJWgRuMADaAAAQAAYJWgRuMADaAAAAAA==.',
Se='Sepviva:BAAALgAECgYJEwAAAA==.Serpent:BAAALgAECgUJCQABLgAFFAQJDQAZAMYWAA==.',
Sh='Shadowheal:BAAALgADCgUJBgAAAA==.Shamadeus:BAAALgADCgUJBQABLgAECgcJFwATAOgjAA==.Sharaseth:BAAALgAECgIJAgAAAA==.Shikita:BAABLgAECn8VAAMFAAYJPyDKJQAhAgAFAAYJPyDKJQAhAgAGAAEJHAZDigAlAAAAAA==.Shimadin:BAACLgAFFH8IAAIQAAMJPBhZEgASAQAQAAMJPBhZEgASAQAuAAQKfx0AAhAACAkOHyovAGYCABAACAkOHyovAGYCAAAA.Shimpbizkit:BAAALgAECgQJBwABLgAFFAMJCAAQADwYAA==.Shimsong:BAAALgADCgYJDAABLgAFFAMJCAAQADwYAA==.Shmerek:BAABLgAECn8VAAIJAAgJXCGpAACWAgAJAAgJXCGpAACWAgAAAA==.',
Si='Silverstream:BAABLgAECn8mAAIFAAgJMRMYQgCZAQAFAAgJMRMYQgCZAQAAAA==.',
Sk='Skyblue:BAAALgADCgEJAQAAAA==.',
Sm='Smootish:BAAALgADCgUJBQAAAA==.',
Sn='Snoman:BAAALgADCgYJBgAAAA==.',
So='Solbin:BAAALgAECgQJBAAAAA==.Solitudé:BAABLgAECn8VAAMaAAYJYCLRCADkAQAaAAUJvCHRCADkAQAEAAIJRyV0FgDOAAAAAA==.Soteirian:BAAALgAECgQJBAAAAA==.',
Sp='Spekey:BAAALgADCgMJBgAAAA==.Spider:BAAALgAECgQJCAAAAA==.Spineymagus:BAAALgADCgIJAgAAAA==.',
Sq='Squall:BAAALgAECgQJBwAAAA==.',
St='Stalariais:BAAALgAECgQJBAABLgAECggJFwAKAOoIAA==.Stardrand:BAAALgADCgUJBgAAAA==.Steelreserve:BAAALgAECgYJDQAAAA==.Straw:BAAALgADCgkJEAABLgAECgcJFgAQAD4jAA==.',
Su='Sugarkitty:BAAALgADCgYJCgAAAA==.Supereclipse:BAABLgAECn8VAAIVAAYJLBANGgAsAQAVAAYJLBANGgAsAQAAAA==.',
Sw='Swolareclips:BAAALgADCgYJBgAAAA==.',
Sy='Sydvicious:BAABLgAECn8aAAIbAAgJaSRTAADbAgAbAAgJaSRTAADbAgAAAA==.Syriene:BAAALgAECgYJCAAAAA==.',
Ta='Tankhealz:BAAALgAECgIJAgAAAA==.',
Tb='Tbsp:BAAALgADCgYJCQAAAA==.',
Te='Tecks:BAABLgAECn8VAAIcAAgJKAazDQAUAQAcAAgJKAazDQAUAQAAAA==.Teddy:BAAALgAECgUJBQAAAA==.',
Th='Theatrix:BAAALgAECgMJAwAAAA==.Thecuckler:BAAALgAECgMJBAAAAA==.Thefreeman:BAAALgAECgEJAQAAAA==.Themajor:BAAALgAECgcJEwAAAA==.Then:BAAALgADCgEJAQAAAA==.Thiarad:BAAALgADCgEJAQAAAA==.Thrain:BAAALgADCgcJDAAAAA==.Threat:BAABLgAECn8dAAIQAAgJByXBAAD5AgAQAAgJByXBAAD5AgAAAA==.Thsarus:BAABLgAECn8UAAMIAAYJASGxMAA4AgAIAAYJASGxMAA4AgAdAAQJHBHPGwCxAAAAAA==.',
Ti='Tiamaat:BAABLgAECn8VAAIFAAgJswSLHgDCAAAFAAgJswSLHgDCAAAAAA==.Tireyne:BAAALgADCgEJAgAAAA==.Titus:BAAALgAECgEJAgAAAA==.',
Tr='Treadlightly:BAAALgADCgUJBwAAAA==.Treefróg:BAAALgAECgUJBQAAAA==.Trentus:BAAALgADCgIJAgAAAA==.Trev:BAAALgAECgUJBgABLgAECgYJGQATAFAhAA==.',
Ts='Tsp:BAACLgAFFH8JAAIeAAMJnQfMDQDDAAAeAAMJnQfMDQDDAAAuAAQKfyIAAx4ACQlkFhMUACoCAB4ACQlkFhMUACoCAAwABAnuA0xsAJEAAAAA.',
Ty='Tyletos:BAAALgAECgYJEgAAAA==.',
Ug='Ugolok:BAAALgADCgcJDAAAAA==.',
Ur='Uriél:BAABLgAECn8aAAIIAAgJ7h+iHwCTAgAIAAgJ7h+iHwCTAgAAAA==.',
Ve='Veiler:BAABLgAECn8aAAMVAAgJAw3tDQCWAQAVAAgJAw3tDQCWAQAfAAEJ3wHilgAhAAAAAA==.Velca:BAAALgAECgEJAQAAAA==.Veruca:BAAALgAECgMJAwAAAA==.Veviseron:BAABLgAECn8dAAIOAAgJiwN8LgAQAQAOAAgJiwN8LgAQAQAAAA==.',
Vh='Vhye:BAAALgAECgYJBwAAAA==.',
Vi='Vinstalation:BAABLgAECn8WAAIgAAYJNR6MBAAUAgAgAAYJNR6MBAAUAgAAAA==.Vissa:BAAALgADCgYJBgAAAA==.',
Vo='Vonbismarck:BAABLgAECn8YAAIVAAcJPRfFEQBvAQAVAAcJPRfFEQBvAQAAAA==.',
Vr='Vrock:BAAALgAECgEJAQABLgAECgYJGAAOAGYbAA==.',
Wa='Warnam:BAAALgADCgcJBwAAAA==.Warsonge:BAAALgADCgMJAwAAAA==.',
We='Wendypini:BAABLgAECn8WAAIVAAgJlQ1hRQCbAQAVAAgJlQ1hRQCbAQAAAA==.Wetnwild:BAAALgADCgQJBAAAAA==.',
Wh='Whitehand:BAAALgAECgIJAgAAAA==.',
Wo='Wooshwoosh:BAAALgAECgIJAgAAAA==.',
Wu='Wudeeps:BAAALgAECgcJEgAAAA==.Wuhanwarrior:BAAALgAECgUJCQAAAA==.',
Ya='Yako:BAAALgAECgEJAQAAAA==.',
Ye='Yennefer:BAAALgADCgIJAgAAAA==.',
Za='Zangolf:BAAALgADCgUJBAAAAA==.',
Ze='Zearas:BAAALgAECgcJEAAAAA==.Zendonn:BAAALgAECgMJBQAAAA==.',
Zi='Zicatriz:BAAALgADCgcJDgAAAA==.',
Zo='Zodiaac:BAABLgAECn8VAAIZAAgJiBrHAgDbAQAZAAgJiBrHAgDbAQAAAA==.',
Zy='Zy:BAAALgADCgUJBQAAAA==.',
['Ëc']='Ëchõ:BAABLgAECn8aAAMFAAgJPhHJNwDIAQAFAAgJPhHJNwDIAQAGAAIJvwRRdwBHAAAAAA==.',
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

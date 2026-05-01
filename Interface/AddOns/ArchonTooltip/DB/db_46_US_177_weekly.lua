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

local lookup = {'Shaman-Restoration','Mage-Frost','Warrior-Fury','Evoker-Augmentation','Paladin-Retribution','Paladin-Holy','Unknown-Unknown','DeathKnight-Unholy','Druid-Feral','Druid-Balance','Paladin-Protection','Priest-Shadow','Druid-Restoration','Rogue-Subtlety','Warrior-Protection','Priest-Holy','Hunter-Marksmanship','Hunter-BeastMastery','DeathKnight-Blood','Warlock-Destruction','Warlock-Demonology','Shaman-Elemental','Monk-Windwalker','Monk-Brewmaster','Hunter-Survival','Rogue-Assassination','Warrior-Arms','DemonHunter-Devourer','Rogue-Outlaw','Warlock-Affliction','Evoker-Preservation','Evoker-Devastation','Shaman-Enhancement','DemonHunter-Havoc','Priest-Discipline',}
local provider = {region='US',realm='Ravencrest',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abelas:BAAALgADCgYJFwAAAA==.Abracadaxis:BAAALgADCggJCAAAAA==.',
Ad='Adallyn:BAAALgADCgYJCgAAAA==.Adzen:BAAALgADCgcJBwAAAA==.Adêrna:BAABLgAECn8bAAIBAAcJBxymHgAnAgABAAcJBxymHgAnAgAAAA==.',
Af='Affliction:BAAALgADCgUJBQAAAA==.',
Ag='Agba:BAAALgAFFAEJAQAAAA==.',
Ah='Ahktari:BAAALgADCgcJBwAAAA==.',
Al='Alaidan:BAAALgAECgYJBwAAAA==.Alanus:BAABLgAECn8eAAICAAgJpw/mLQCsAQACAAgJpw/mLQCsAQAAAA==.Alarion:BAAALgAECgMJAwAAAA==.Alavia:BAABLgAECn8gAAIDAAgJrxMWDwDGAQADAAgJrxMWDwDGAQAAAA==.Alinäs:BAABLgAECn8WAAICAAgJwQ9xMQCeAQACAAgJwQ9xMQCeAQAAAA==.Aliën:BAAALgADCgEJAQAAAA==.Alliumoo:BAAALgAECgYJEQAAAA==.Altana:BAAALgAECggJCAABLgAECgcJGgAEAH0eAA==.Alydrus:BAAALgAECgQJBgAAAA==.Alíen:BAAALgADCgQJBAAAAA==.',
An='Anberlinean:BAABLgAECn8WAAIFAAYJ5gfpXwD1AAAFAAYJ5gfpXwD1AAAAAA==.Angryelf:BAAALgAECgEJAQAAAA==.Ankles:BAAALgADCgcJBwABLgAFFAMJBgAGAMQTAA==.Annahe:BAAALgAECggJDAAAAA==.Annale:BAAALgAECgEJAQABLgAECggJDAAHAAAAAA==.Annatara:BAAALgAECgEJAQAAAA==.Anzala:BAAALgADCgIJAgAAAA==.',
Ao='Aoba:BAAALgAECgUJCQAAAA==.',
Ar='Arataeus:BAAALgAECgQJBwAAAA==.Armsmaster:BAABLgAECn8lAAIIAAgJLh/+XADbAQAIAAgJLh/+XADbAQAAAA==.',
As='Asalynn:BAAALgADCgEJAQAAAA==.',
Av='Avalina:BAAALgAECgEJAQAAAA==.Avengharambe:BAAALgADCgcJBwAAAA==.Averan:BAAALgAECgUJEAAAAA==.Averybug:BAAALgADCgEJAQAAAA==.',
Ba='Backbeamz:BAAALgAECgYJCQAAAA==.Backspace:BAAALgADCgYJBgAAAA==.Badgër:BAAALgADCgEJAQAAAA==.Baey:BAAALgADCgMJAwABLgAECgcJGQACANodAA==.Balduun:BAAALgADCgYJDgAAAA==.Barelycastin:BAAALgADCgMJAwAAAA==.Bashdadargon:BAAALgAECgEJAQAAAA==.',
Be='Bearnaked:BAAALgADCgIJAgAAAA==.Belgarathh:BAAALgAECgQJBAAAAA==.Bellíon:BAAALgAECgMJBgAAAA==.',
Bi='Bixee:BAAALgAECgUJCQAAAA==.',
Bl='Blacat:BAABLgAECn8gAAMJAAgJvBmcAgA+AgAJAAgJvBmcAgA+AgAKAAIJUAMyeABEAAAAAA==.Bleen:BAAALgAECgUJDAAAAA==.Blitzcomets:BAAALgADCgUJBwAAAA==.Bloodbenders:BAAALgADCgEJAQAAAA==.',
Bo='Bogeyman:BAABLgAECn8eAAILAAcJKSAyBAANAgALAAcJKSAyBAANAgAAAA==.Boondoks:BAAALgAECgQJDAABLgAECggJJQABAE4eAA==.Borda:BAAALgADCgcJDQAAAA==.Bowrider:BAAALgAECgYJBwAAAA==.',
Br='Brondeadeye:BAAALgAECgUJBgAAAA==.Brunore:BAAALgAECgYJDAAAAA==.',
Bu='Bubbajüdd:BAAALgADCgEJAQAAAA==.',
Ca='Caledur:BAAALgAECgEJAQAAAA==.Careblair:BAAALgADCgEJAQAAAA==.',
Ch='Chakrah:BAABLgAECn8YAAIMAAcJ/gkeIgDqAAAMAAcJ/gkeIgDqAAAAAA==.Challan:BAAALgAFFAIJAwAAAA==.Chloe:BAABLgAECn8XAAINAAkJ8wEDewAtAAANAAkJ8wEDewAtAAAAAA==.Chrno:BAAALgAECgYJEgAAAA==.Chunkymonkey:BAAALgADCgYJBgABLgAFFAIJAgAHAAAAAA==.',
Cl='Clutcha:BAABLgAECn8ZAAIOAAYJaBs4DgCIAQAOAAYJaBs4DgCIAQAAAA==.Clutchcross:BAAALgAECgQJBgABLgAECgYJGQAOAGgbAA==.Clutchplate:BAABLgAECn8aAAIPAAcJChPcDABTAQAPAAcJChPcDABTAQAAAA==.Clûtch:BAABLgAECn8dAAIIAAgJcSDtNgBbAgAIAAgJcSDtNgBbAgAAAA==.',
Co='Codenameblue:BAAALgADCgEJAQAAAA==.Coog:BAAALgADCgEJAQAAAA==.Corynthe:BAABLgAECn8cAAIQAAcJQh5YGQARAgAQAAcJQh5YGQARAgAAAA==.',
Cr='Crickie:BAAALgAECgEJAQAAAA==.Crovaxis:BAABLgAECn8eAAMRAAgJLiIBAgBEAgARAAcJviIBAgBEAgASAAEJyx6ifABYAAAAAA==.',
Cu='Cursecackler:BAAALgADCgYJBgAAAA==.',
Cy='Cynda:BAAALgADCgMJAwAAAA==.Cyndestine:BAAALgADCgYJBgAAAA==.Cyzarius:BAAALgAECgEJAQAAAA==.',
Da='Daedrìc:BAAALgAECgMJAwAAAA==.Damekka:BAAALgAECgQJBQAAAA==.Danazer:BAAALgAECgUJBQAAAA==.Darktalyn:BAABLgAECn8eAAMQAAgJnBP0CgD2AQAQAAgJnBP0CgD2AQAMAAYJxQ4vMwBOAQAAAA==.',
De='Deathbinger:BAAALgADCgEJAQAAAA==.Deathgriped:BAABLgAECn8ZAAITAAYJSxUxDQA9AQATAAYJSxUxDQA9AQAAAA==.Deathhawkzz:BAABLgAECn8WAAMUAAcJ+hXmCwAEAgAUAAcJ+hXmCwAEAgAVAAEJJARcKwEnAAAAAA==.Deathphoenix:BAAALgADCgcJBwAAAA==.Deathslock:BAAALgADCgQJBAAAAA==.Deekura:BAAALgAECgYJDgAAAA==.Deladorana:BAAALgADCgUJBQAAAA==.Dellma:BAAALgADCgYJBgAAAA==.Delusion:BAAALgAECgEJAgAAAA==.Demonpapi:BAAALgAECgEJAgAAAA==.Demoryx:BAEALgADCgkJCQABLgAECggJHwAWAHocAA==.Denjack:BAAALgAECgEJAQAAAA==.Dewayne:BAAALgAECgUJBQAAAA==.',
Dh='Dhadzen:BAAALgAECgIJCAAAAA==.',
Di='Dionan:BAABLgAECn8eAAIFAAgJLBK7KgCXAQAFAAgJLBK7KgCXAQAAAA==.Dirtysouth:BAAALgAECgEJAQABLgAFFAMJBQASAKcbAA==.',
Do='Docs:BAABLgAECn8aAAIGAAgJFhPzDgDvAQAGAAgJFhPzDgDvAQAAAA==.Doks:BAABLgAECn8lAAIBAAgJTh6xEwB3AgABAAgJTh6xEwB3AgAAAA==.Dontpanic:BAAALgAECgQJBAABLgAFFAMJBgAGAMQTAA==.Doomsnake:BAAALgADCgMJAwABLgADCgEJAQAHAAAAAA==.Dove:BAAALgADCgYJBgAAAA==.',
Dr='Dragomalfoy:BAAALgADCgQJBAAAAA==.Dragõn:BAAALgAECgEJAgAAAA==.Drexeos:BAAALgADCgcJBwAAAA==.Drinker:BAAALgADCgUJBQAAAA==.',
Ea='Ealara:BAAALgAECgYJEAAAAA==.',
Ed='Edran:BAAALgADCgcJFQAAAA==.',
Ei='Eifel:BAAALgAECgQJBAABLgAECgYJDQAHAAAAAA==.Eimin:BAAALgADCgYJCgAAAA==.',
El='Eldarion:BAAALgAECgMJAgAAAA==.Elfmonk:BAAALgAECgEJAQAAAA==.Ellipses:BAAALgADCgYJBgABLgAECgcJDgAHAAAAAA==.',
Em='Emeraldz:BAABLgAECn8WAAIXAAYJgBvBFgAzAQAXAAYJgBvBFgAzAQAAAA==.',
En='Eneru:BAAALgADCgYJCAABLgAECggJHwAGAJ0XAA==.',
Er='Erebrethil:BAAALgAECgYJDwAAAA==.',
Es='Espe:BAABLgAECn8YAAIYAAgJOBVUDADEAQAYAAgJOBVUDADEAQAAAA==.',
Eu='Eucalyptia:BAAALgADCgQJBAAAAA==.',
Ev='Evenin:BAAALgADCgIJAgAAAA==.',
Fa='Faenor:BAAALgAECgMJAwAAAA==.Faynor:BAABLgAECn8dAAIYAAcJVRQGGQA3AQAYAAcJVRQGGQA3AQAAAA==.',
Fe='Feloni:BAAALgAECgMJAwAAAA==.',
Fi='Finalone:BAAALgADCgEJAQAAAA==.Firêfly:BAAALgAECgIJAwAAAA==.',
Fk='Fknsteve:BAAALgADCgYJBgAAAA==.',
Fl='Flaptix:BAAALgAECgMJAwAAAA==.Flipingflerp:BAAALgAECgcJDwAAAA==.Flloran:BAAALgAECgEJAgAAAA==.Floragoth:BAAALgAECgEJAQAAAA==.Flowers:BAAALgADCgkJCQAAAA==.Fluffboi:BAABLgAECn8WAAIXAAYJEwnQHwDoAAAXAAYJEwnQHwDoAAAAAA==.',
Fo='Foxyblue:BAAALgAECgYJDgAAAA==.',
Fr='Fraggle:BAACLgAFFH8GAAMGAAMJxBM2EAD8AAAGAAMJxBM2EAD8AAAFAAEJtgE5SwA8AAAuAAQKfyAAAwYACAl+IBoLAMcCAAYACAl+IBoLAMcCAAUAAQlaExi7AEIAAAAA.Freefolk:BAAALgADCgcJBwAAAA==.Freefromfate:BAAALgAECgEJAQAAAA==.Frogchi:BAAALgAECgEJAQAAAA==.Frostbité:BAABLgAECn8bAAILAAgJYBQuEQC1AQALAAgJYBQuEQC1AQAAAA==.Fruit:BAAALgAECgIJAgAAAA==.',
Fu='Fumikiko:BAAALgADCgIJAgABLgAECgcJGgAEAH0eAA==.Furrykarg:BAAALgAECgEJAQAAAA==.',
['Fú']='Fúzzy:BAAALgADCgEJAgAAAA==.',
Ga='Gakkle:BAAALgAECgYJCQAAAA==.Galadralvia:BAAALgAECgYJEAAAAA==.Gali:BAAALgAECgUJDAAAAA==.',
Ge='Gearsofbob:BAAALgAFFAIJBAAAAA==.Gekkle:BAAALgADCgUJBQAAAA==.Getphisted:BAAALgADCgMJAwAAAA==.',
Gh='Ghoulei:BAABLgAECn8dAAIIAAcJzR+EFQANAgAIAAcJzR+EFQANAgAAAA==.',
Gl='Glaistiguain:BAAALgAECgYJCwABLgAECggJJQAIAC4fAA==.Glifin:BAAALgAECgEJAQAAAA==.Gloomstalkin:BAABLgAECn8gAAIZAAcJYBhpDACYAQAZAAcJYBhpDACYAQAAAA==.',
Gn='Gnøsis:BAAALgADCggJEQAAAA==.',
Go='Goldìelocks:BAAALgADCgEJAQAAAA==.Gom:BAAALgAECgIJAgAAAA==.Gomdrog:BAAALgADCgUJBQAAAA==.',
Gr='Gr:BAABLgAECn8cAAIaAAcJpgoWBgBVAQAaAAcJpgoWBgBVAQAAAA==.Grannecs:BAAALgADCgEJAQAAAA==.Grizzledpaw:BAAALgAECgMJAwAAAA==.Gryffs:BAABLgAECn8mAAMPAAgJgRu3BAAeAgAPAAgJgRu3BAAeAgAbAAEJ0wrvLAA2AAAAAA==.',
Gu='Gutts:BAABLgAECn8YAAQPAAgJch93AgCAAgAPAAgJch93AgCAAgAbAAUJUA9cJADKAAADAAQJ0Q7ffQDFAAAAAA==.',
Ha='Haiirøkami:BAABLgAECn8aAAIFAAYJIgiYuQASAQAFAAYJIgiYuQASAQAAAA==.Halomea:BAAALgADCgQJBAAAAA==.Hanukira:BAAALgADCgUJBQAAAA==.Happi:BAAALgAECgYJCQABLgAFFAYJEQAcALMWAA==.Harald:BAAALgAECgUJCgAAAA==.Harkle:BAAALgADCgcJDQAAAA==.Haruun:BAAALgAECgEJAQAAAA==.',
He='Hesmydaddy:BAABLgAECn8bAAIQAAcJagXvRwAZAQAQAAcJagXvRwAZAQAAAA==.',
Ho='Hongling:BAAALgADCgYJBgABLgAECgcJGgAEAH0eAA==.Honêy:BAEALgADCgUJBQABLgAECggJHwAWAHocAA==.Hotdogstand:BAACLgAFFH8MAAIOAAQJZyP1AQCiAQAOAAQJZyP1AQCiAQAuAAQKfycABA4ACAnvJesFADIDAA4ACAnvJesFADIDABoABAmEIYELAHMBAB0AAQkvIiQLAGIAAAAA.',
Hu='Huzzaah:BAAALgAECgIJAgABLgAFFAMJBgAGAMQTAA==.',
Hy='Hyperius:BAAALgADCgIJAgAAAA==.',
['Hö']='Höneÿdew:BAABLgAECn8ZAAISAAgJ7Bg1LAADAgASAAgJ7Bg1LAADAgAAAA==.',
Ic='Icemann:BAAALgAECgEJAgAAAA==.',
Il='Ilidrayssel:BAABLgAECn8aAAIRAAcJbQO2DgDeAAARAAcJbQO2DgDeAAAAAA==.Illida:BAAALgAECgMJBgAAAA==.Illidad:BAAALgAECgMJAwAAAA==.Ilyssara:BAAALgADCgYJBgABLgAECgcJDgAHAAAAAA==.',
Im='Imhappy:BAAALgAECgEJAgABLgAFFAYJEQAcALMWAA==.Imherdaddy:BAAALgADCgYJCAABLgAECgcJIAAZAGAYAA==.',
In='Innervape:BAAALgADCgMJAwAAAA==.',
Ja='Jacorict:BAAALgAECgYJDwAAAA==.Jagga:BAAALgADCgMJAwAAAA==.Jarrack:BAABLgAECn8WAAICAAcJvBbjMACgAQACAAcJvBbjMACgAQAAAA==.',
Je='Jellyhawk:BAAALgAECgEJAQAAAA==.Jessicae:BAAALgAECgYJDAAAAA==.',
Jo='Josephedd:BAABLgAECn8eAAIKAAgJLRCmKwClAQAKAAgJLRCmKwClAQAAAA==.',
Ju='Jukk:BAAALgAECgYJDQAAAA==.Junazeena:BAABLgAECn8XAAIWAAcJkQMDLQDNAAAWAAcJkQMDLQDNAAAAAA==.',
Ka='Kaji:BAAALgAECgQJDgAAAA==.Kalistus:BAAALgADCgYJBwAAAA==.Kargfu:BAAALgAECgEJAQABLgAECgEJAQAHAAAAAA==.Karolat:BAAALgAECgIJAQAAAA==.Kayfabe:BAABLgAECn8YAAICAAcJEARj+gAGAQACAAcJEARj+gAGAQAAAA==.',
Ke='Keishilda:BAAALgAECgMJBAAAAA==.Keladria:BAAALgAECgMJAwAAAA==.Kelvyren:BAAALgADCgEJAQAAAA==.Kenel:BAABLgAECn8YAAINAAcJmxFgKABGAQANAAcJmxFgKABGAQAAAA==.Kerea:BAABLgAECn8dAAINAAcJHweIQQDKAAANAAcJHweIQQDKAAAAAA==.',
Ki='Kicken:BAABLgAECn8UAAMVAAYJxhaXPwAzAQAVAAUJVhWXPwAzAQAUAAMJCBYkPwC4AAAAAA==.Kitschy:BAAALgADCgEJAQAAAA==.Kittyperry:BAAALgAECgMJAwAAAA==.',
Kn='Knome:BAABLgAECn8ZAAICAAcJ2h07IADsAQACAAcJ2h07IADsAQAAAA==.',
Ko='Koana:BAAALgAECgQJBwAAAA==.Korthelan:BAABLgAECn8dAAIcAAcJyRCxNAAQAQAcAAcJyRCxNAAQAQAAAA==.Kothara:BAABLgAECn8XAAISAAYJtBIwQgCnAQASAAYJtBIwQgCnAQAAAA==.Kotongar:BAAALgADCgMJAwAAAA==.',
Kr='Kreeoo:BAAALgAECgIJAgAAAA==.Krimzin:BAACLgAFFH8FAAISAAMJpxtLGgD9AAASAAMJpxtLGgD9AAAuAAQKfx0AAxIACAneIZYhADwCABIACAneIZYhADwCABkAAgkYEC4qAEsAAAAA.Krystine:BAAALgAECgIJAgAAAA==.',
Ks='Kserasera:BAAALgAECgYJDQAAAA==.',
Ku='Kuball:BAAALgAECgUJBwABLgAECggJGAAPAHIfAA==.Kukuruku:BAAALgAECgIJAwAAAA==.',
['Kî']='Kîllara:BAABLgAECn8kAAIBAAgJ2xXfEADtAQABAAgJ2xXfEADtAQAAAA==.',
La='Labialicious:BAAALgAECgEJAgAAAA==.Lanfeår:BAABLgAECn8VAAIIAAYJDAhZVgAAAQAIAAYJDAhZVgAAAQAAAA==.Lanskies:BAAALgAECgcJCQAAAA==.',
Le='Leafymeds:BAAALgAECgUJCgABLgAECgYJHAABAOcYAA==.Lebronjames:BAAALgADCgYJBgAAAA==.Leiluna:BAAALgADCgkJEQAAAA==.',
Li='Libertinne:BAABLgAECn8XAAIDAAgJJhf3GgBYAQADAAgJJhf3GgBYAQAAAA==.Librarte:BAABLgAECn8aAAIFAAgJwgqzRQA5AQAFAAgJwgqzRQA5AQAAAA==.Ligmanuts:BAAALgAECgIJBAAAAA==.Lillytrae:BAAALgADCgEJAQAAAA==.Listie:BAAALgADCgQJBAAAAA==.Litty:BAABLgAECn8ZAAICAAcJbyRrDwBhAgACAAcJbyRrDwBhAgAAAA==.Lizrdkng:BAAALgADCgMJBgAAAA==.',
Lo='Locktärd:BAACLgAFFH8MAAQeAAQJnRskAACKAQAeAAQJnRskAACKAQAVAAIJShYEMwCtAAAUAAIJogZ3DgCXAAAuAAQKfygABB4ACAmIH6oCAJACAB4ACAk9H6oCAJACABUABwkYGRNCAAYCABQAAgkLHHxGAJwAAAAA.Lohken:BAAALgAECgMJCQAAAA==.Lox:BAABLgAECn8dAAIUAAcJJREbBgBdAQAUAAcJJREbBgBdAQAAAA==.',
Lu='Lucieb:BAAALgAECgEJAQAAAA==.',
Ly='Lydirn:BAABLgAECn8bAAQFAAgJyRtiHQDZAQAFAAcJqRxiHQDZAQAGAAMJZxXeMADFAAALAAEJihYJJQBBAAAAAA==.Lyofel:BAAALgAECgYJDwAAAA==.Lyonel:BAAALgADCggJCAAAAA==.',
['Lí']='Lítterbox:BAAALgAECgEJAQAAAA==.',
Ma='Magedzen:BAAALgADCgEJAwAAAA==.Magicguy:BAAALgAECgYJEAAAAA==.Mahariel:BAAALgAECgYJCwAAAA==.Mahdy:BAABLgAECn8nAAIFAAgJDRpOEwAgAgAFAAgJDRpOEwAgAgAAAA==.Maivel:BAAALgAECgEJAQAAAA==.Mandret:BAAALgAECgMJBAAAAA==.Manicppanic:BAAALgAECgYJDAABLgAFFAMJBgAGAMQTAA==.Manrypurp:BAAALgAECgUJDQAAAA==.Marcie:BAABLgAECn8dAAIKAAcJ+AqWGwAeAQAKAAcJ+AqWGwAeAQAAAA==.',
Mc='Mchammer:BAAALgADCgUJBgAAAA==.',
Me='Meatyloaf:BAAALgAECgUJCgAAAA==.Melkedrik:BAAALgAECgUJCgAAAA==.Melleren:BAAALgAECgEJAQAAAA==.Messande:BAAALgAECgEJAgAAAA==.',
Mi='Minõs:BAAALgADCgkJEAAAAA==.Mirai:BAAALgADCgUJBQAAAA==.Mirei:BAABLgAECn8UAAIQAAYJGgd6IgDsAAAQAAYJGgd6IgDsAAAAAA==.Mistdancer:BAAALgADCgYJBgABLgAECgUJCgAHAAAAAA==.Mitsurugi:BAAALgADCgQJAwABLgAECgUJCgAHAAAAAA==.Miyagí:BAAALgAECgcJDgABLgAECggJGAATAKEdAA==.',
Mo='Mojam:BAAALgAECgEJAgAAAA==.Moonless:BAAALgADCgMJAwAAAA==.Moovidlin:BAAALgAECgYJCAABLgAECgYJDQAHAAAAAA==.Mordian:BAAALgAECgYJBgAAAA==.Morinnas:BAAALgADCgkJDAAAAA==.Moschpit:BAAALgADCgEJAQAAAA==.',
Mu='Munkeez:BAAALgADCgMJAwAAAA==.Murdermoo:BAAALgADCgMJAwAAAA==.Murkessa:BAAALgAECgIJAgAAAA==.Mushhead:BAAALgAECgUJCAAAAA==.',
My='Myishaa:BAAALgADCgIJAgAAAA==.Mykeal:BAAALgADCgMJBQAAAA==.',
['Mì']='Mìstra:BAAALgADCgUJBQAAAA==.',
Na='Nargo:BAAALgADCgYJCgAAAA==.',
Ne='Necrostalker:BAAALgADCgkJCQABLgADCgEJAQAHAAAAAA==.Negative:BAAALgAECgEJAQAAAA==.Nerwende:BAAALgAECgEJAQAAAA==.Nethershade:BAABLgAECn8UAAIaAAYJzhPODgApAQAaAAYJzhPODgApAQAAAA==.Netherstörm:BAAALgADCgkJGwAAAA==.Netzach:BAAALgAECgkJDAAAAA==.',
Ni='Niclea:BAAALgAECgQJBAAAAA==.Nightelm:BAABLgAECn8aAAQEAAcJfR7zGwDpAQAEAAcJdR7zGwDpAQAfAAQJwwsRNADMAAAgAAMJ+h3PKgDHAAAAAA==.Niënor:BAAALgADCgYJBgABLgAECgYJDwAHAAAAAA==.',
No='Noslien:BAAALgAECgQJBAAAAA==.Nostradamuz:BAAALgAECgEJAQAAAA==.Novasong:BAAALgAECgEJAwAAAA==.',
Ny='Nyxstonia:BAABLgAECn8lAAIPAAgJhRoCBwDVAQAPAAgJhRoCBwDVAQAAAA==.',
Ob='Oballi:BAAALgAECgEJAgAAAA==.',
Ol='Olierra:BAAALgAECgUJCgAAAA==.',
On='Onlyvoids:BAAALgAECgMJAwAAAA==.',
Or='Ornac:BAAALgADCgYJBgAAAA==.',
Ot='Otkspring:BAAALgAFFAMJAwAAAA==.Otto:BAABLgAECn8bAAIFAAcJjxAcNAByAQAFAAcJjxAcNAByAQAAAA==.',
Ox='Oxadin:BAAALgAECgEJAQAAAA==.Oxideous:BAAALgADCgMJAwAAAA==.',
Pa='Paleale:BAAALgAECgYJCgAAAA==.Pallyshore:BAAALgADCgMJAwAAAA==.Pampoovy:BAEALgADCgMJAwABLgAECgUJCQAHAAAAAA==.Pantoponrose:BAAALgADCgkJDQAAAA==.Pastorbash:BAAALgADCggJCQAAAA==.',
Pb='Pb:BAAALgAECgMJAwAAAA==.',
Pe='Persephoneia:BAABLgAECn8ZAAIMAAgJVA0YEACMAQAMAAgJVA0YEACMAQAAAA==.',
Ph='Phukimded:BAAALgADCgkJCQABLgAECgcJDgAHAAAAAA==.',
Pi='Piperclip:BAAALgADCgEJAQAAAA==.',
Pk='Pkashmuk:BAAALgADCgcJBwAAAA==.',
Pr='Prophettool:BAAALgAECgcJEwAAAA==.Pruned:BAAALgADCgcJBwABLgAFFAQJDAAeAJ0bAA==.',
Qu='Quanchii:BAAALgADCgMJAwAAAA==.',
Ra='Raemie:BAAALgAECgIJAwAAAA==.Ragequit:BAAALgAECgcJDgAAAA==.Raikoho:BAAALgAECgEJAQAAAA==.Rakulm:BAAALgADCgUJCgAAAA==.Ravenrest:BAEBLgAECn8gAAIMAAgJnRnOBwAKAgAMAAgJnRnOBwAKAgAAAA==.',
Re='Reaverhiem:BAAALgAECgQJCgAAAA==.Reiko:BAAALgADCgkJGAABLgAECgYJFAAQABoHAA==.Remuz:BAAALgAECgMJAwAAAA==.Rennwick:BAAALgAECgQJBgAAAA==.',
Ri='Rilz:BAABLgAECn8eAAIIAAgJkR1iDgBPAgAIAAgJkR1iDgBPAgAAAA==.',
Ro='Rochambeu:BAAALgADCgEJAQAAAA==.Rodgerwabbet:BAAALgAECgQJBAAAAA==.Roiddrood:BAAALgAECgIJAgABLgAECggJIAAVAN8RAA==.Roidlock:BAABLgAECn8gAAIVAAgJ3xFhJQCaAQAVAAgJ3xFhJQCaAQAAAA==.Roidtank:BAAALgAECgUJDAABLgAECggJIAAVAN8RAA==.Rosaline:BAAALgAECgQJBAAAAA==.Rottn:BAAALgAECgYJBgABLgAECgcJDgAHAAAAAA==.',
Ru='Runerion:BAAALgAECgEJAgAAAA==.',
['Rà']='Ràìn:BAABLgAECn8WAAICAAgJAQnoQwBjAQACAAgJAQnoQwBjAQAAAA==.',
Sa='Safmen:BAABLgAECn8WAAQPAAYJsgeALgDPAAAPAAYJ5AWALgDPAAAbAAMJMgX/IgBjAAADAAEJCArrogA9AAAAAA==.Sanikoa:BAAALgADCgEJAQAAAA==.Saraid:BAABLgAECn8eAAMNAAgJNRsKCQB6AgANAAgJNRsKCQB6AgAKAAMJ7Q4FYQCdAAAAAA==.Saravase:BAAALgAECgMJBwAAAA==.Sardel:BAAALgADCgcJBwAAAA==.Sargeros:BAAALgAECgQJBQAAAA==.Sazem:BAAALgADCgIJAgAAAA==.',
Se='Sedaldra:BAAALgADCgYJCwAAAA==.',
Sh='Shadownights:BAABLgAECn8dAAIMAAcJvw40GwAkAQAMAAcJvw40GwAkAQAAAA==.Shamoneyy:BAAALgADCgUJBQAAAA==.Shiki:BAAALgADCgkJCQABLgAECgYJFAAQABoHAA==.Shimnar:BAAALgAECgcJBwABLgAECggJFwADACYXAA==.Shinifur:BAAALgADCgUJBgAAAA==.Shinoto:BAAALgAECgQJBgAAAA==.Shockazam:BAAALgAECgcJEgAAAA==.Shrewby:BAAALgAECgEJAQAAAA==.Shyandra:BAAALgADCgYJBgAAAA==.',
Si='Sieghart:BAAALgAECgEJAQAAAA==.Six:BAAALgAECgUJCwAAAA==.',
Sl='Sloptop:BAAALgAECgEJAgAAAA==.',
Sn='Snickersbar:BAAALgADCgUJCAAAAA==.Snowynn:BAAALgAECgEJAQAAAA==.Snöw:BAABLgAECn8UAAICAAYJ2w7bbAAAAQACAAYJ2w7bbAAAAQAAAA==.Snöwy:BAAALgAECgQJBAAAAA==.',
So='Southpaw:BAAALgAECgMJAwAAAA==.',
Sp='Spooki:BAAALgAECgEJAQAAAA==.Spyro:BAABLgAECn8fAAQEAAkJ4Ax8GgD2AQAEAAkJ4Ax8GgD2AQAfAAgJvgtAIwBfAQAgAAIJpgnONgBgAAAAAA==.',
Sr='Sron:BAABLgAECn8eAAISAAgJER3sDgAhAgASAAgJER3sDgAhAgAAAA==.',
St='Stariah:BAABLgAECn8VAAICAAcJDwoftQB1AQACAAcJDwoftQB1AQAAAA==.Stawn:BAAALgADCgEJAQAAAA==.',
Su='Sumwhiteguy:BAAALgADCgkJCQAAAA==.',
Sw='Swooze:BAABLgAECn8nAAICAAgJpB0IGAAdAgACAAgJpB0IGAAdAgAAAA==.',
Sy='Sylrythriana:BAAALgAECgIJAgAAAA==.Syndicate:BAAALgADCggJCgAAAA==.Syrenis:BAAALgADCgkJDwABLgAECgcJGgAEAH0eAA==.',
['Sù']='Sùnnydk:BAAALgADCgcJBwAAAA==.',
Ta='Talwaz:BAAALgADCgkJDgAAAA==.Tankinbur:BAAALgAECgMJAwAAAA==.Tarlyn:BAABLgAECn8kAAQGAAgJsRQiGQCEAQAGAAgJsRQiGQCEAQAFAAUJNRIFqQAwAQALAAEJAADTPwA+AAAAAA==.Tatslight:BAABLgAECn8UAAILAAYJWhjKFgBoAQALAAYJWhjKFgBoAQABLgAECgYJFAALAFoYAA==.Tatsrage:BAAALgADCgYJBgABLgAECgYJFAALAFoYAA==.Tazaral:BAAALgADCgEJAQABLgAECgQJBwAHAAAAAA==.',
Te='Teysá:BAAALgADCgEJAQAAAA==.',
Th='Thor:BAAALgAECgYJCAAAAA==.Thyandris:BAAALgADCgYJCwAAAA==.Thánátós:BAAALgADCgkJEQAAAA==.',
Ti='Timmthemage:BAAALgAECgUJBwABLgAECgcJBwAHAAAAAQ==.Timthepally:BAAALgAECgcJBwAAAQ==.Tinytex:BAAALgAECgUJEQAAAA==.',
To='Toberson:BAAALgAECgEJAQAAAA==.Toxicbanana:BAAALgAECgYJCwAAAA==.',
Tr='Tradarynn:BAAALgAECgUJCQAAAA==.Tralls:BAEBLgAECn8fAAMWAAgJehxvBgBEAgAWAAgJehxvBgBEAgAhAAEJ8AovLAA1AAABLgAECggJHwAWAHocAA==.Trayvein:BAAALgADCgUJBQAAAA==.Trekk:BAAALgAECgcJBQAAAA==.Tress:BAAALgAECgQJBQAAAA==.',
Ts='Tsindre:BAAALgAECgEJAQAAAA==.',
Tu='Tulkar:BAAALgAECgEJAQAAAA==.Turambar:BAAALgADCgEJAQAAAA==.',
Un='Unholymochi:BAABLgAECn8aAAIIAAYJxh+VXQDaAQAIAAYJxh+VXQDaAQAAAA==.',
Va='Valhalia:BAAALgAECgYJCwAAAA==.Varaelitha:BAAALgAECgMJAwAAAA==.Vashan:BAAALgAECgQJBQAAAA==.Vashni:BAAALgAECgkJDAAAAA==.',
Ve='Velinariae:BAAALgADCgYJEAAAAA==.Vengful:BAAALgAECgYJEgAAAA==.',
Vi='Vivy:BAABLgAECn8fAAQVAAkJMhTcLwBNAgAVAAkJyBPcLwBNAgAUAAQJaxSdMwDpAAAeAAIJBhXMJgBWAAAAAA==.',
Vo='Vorumbrae:BAAALgAECgMJAwAAAA==.',
Vu='Vultus:BAAALgAECgIJAgAAAA==.',
['Vä']='Väntage:BAAALgADCgEJAQAAAA==.',
Wa='Wagyubeef:BAABLgAECn8YAAIDAAgJERcdCwD6AQADAAgJERcdCwD6AQAAAA==.Wali:BAABLgAECn8XAAMVAAgJCBPWHQDCAQAVAAgJCBPWHQDCAQAUAAEJAABydgAuAAAAAA==.',
We='Wenson:BAAALgAECgEJAQAAAA==.',
Wh='Whatupbruh:BAACLgAFFH8HAAMZAAMJXxQSBAC0AAAZAAIJcRYSBAC0AAASAAEJOhBGOABVAAAuAAQKfyMAAxkABwm4IQQHAIgCABkABwm4IQQHAIgCABEAAQndBl+SACgAAAAA.',
Wi='Wildfire:BAAALgADCgUJBQAAAA==.',
Wy='Wyleriya:BAABLgAECn8YAAIVAAcJngZdUgD6AAAVAAcJngZdUgD6AAAAAA==.',
Xa='Xanthas:BAAALgADCgQJBAAAAA==.',
Xc='Xcella:BAAALgAECgMJBgAAAA==.',
Xe='Xephon:BAAALgADCgcJBwAAAA==.',
Ye='Yelizaveta:BAAALgADCgMJAwAAAA==.',
Yl='Ylfcwen:BAAALgAECgEJAQAAAA==.',
Yo='Yodey:BAAALgAECggJEAAAAA==.Yoovee:BAAALgADCgEJAQAAAA==.',
Yu='Yuaetrende:BAABLgAECn8dAAIiAAgJCB+CDgB7AgAiAAgJCB+CDgB7AgAAAA==.Yumii:BAABLgAECn8YAAMQAAgJTCX3AABGAwAQAAgJGiX3AABGAwAjAAYJ/yH0DgBNAgAAAA==.',
Za='Zack:BAAALgAECgYJCAAAAA==.Zaerie:BAAALgADCgcJBwAAAA==.Zagul:BAAALgAECgUJCAAAAA==.Zalarah:BAAALgAECgMJAwAAAA==.Zalarilia:BAAALgAECgEJAQAAAA==.Zanoo:BAAALgADCgYJBwAAAA==.Zaphod:BAAALgADCgQJBQAAAA==.Zardan:BAAALgAECggJEQAAAA==.',
Zi='Ziegler:BAAALgADCgYJBgAAAA==.',
Zo='Zorrita:BAAALgAECgEJAQAAAA==.',
Zu='Zugglite:BAABLgAECn8dAAIGAAcJNSEzFwBYAgAGAAcJNSEzFwBYAgAAAA==.Zulthar:BAABLgAECn8VAAICAAgJ+wmNTQBHAQACAAgJ+wmNTQBHAQAAAA==.',
['Äs']='Äshborn:BAABLgAECn8UAAIIAAcJvww0PABLAQAIAAcJvww0PABLAQAAAA==.Ästra:BAAALgADCggJCAAAAA==.',
['Æl']='Ælx:BAACLgAFFH8FAAICAAMJywWcOwDjAAACAAMJywWcOwDjAAAuAAQKfx4AAgIACQn4E3ESAEgCAAIACQn4E3ESAEgCAAAA.Ælxx:BAAALgAECgMJBAABLgAFFAMJBQACAMsFAA==.',
['Ðe']='Ðeathless:BAAALgADCgUJBQAAAA==.',
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

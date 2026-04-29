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

local lookup = {'Shaman-Restoration','Mage-Frost','Warrior-Fury','Paladin-Holy','Unknown-Unknown','DeathKnight-Unholy','Druid-Feral','Druid-Balance','Paladin-Protection','Priest-Shadow','Rogue-Subtlety','Priest-Holy','Hunter-Marksmanship','Warlock-Destruction','Warlock-Demonology','Shaman-Elemental','Paladin-Retribution','Monk-Brewmaster','Evoker-Augmentation','Hunter-Survival','Rogue-Assassination','Warrior-Protection','Warrior-Arms','DemonHunter-Devourer','Hunter-BeastMastery','Druid-Restoration','Warlock-Affliction','Evoker-Preservation','Evoker-Devastation','Shaman-Enhancement','DemonHunter-Havoc','Priest-Discipline',}
local provider = {region='US',realm='Ravencrest',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Abelas:BAAALgADCgUJFQAAAA==.Abracadaxis:BAAALgADCggJCAAAAA==.',
Ad='Adallyn:BAAALgADCgUJCQAAAA==.Adzen:BAAALgADCgEJAQAAAA==.Adêrna:BAABLgAECn8UAAIBAAcJBxyrHgAoAgABAAcJBxyrHgAoAgAAAA==.',
Af='Affliction:BAAALgADCgUJBQAAAA==.',
Ag='Agba:BAAALgAECgcJDQAAAA==.',
Ah='Ahktari:BAAALgADCgcJBwAAAA==.',
Al='Alaidan:BAAALgAECgQJBAAAAA==.Alanus:BAABLgAECn8VAAICAAYJTg/sIQBLAQACAAYJTg/sIQBLAQAAAA==.Alarion:BAAALgADCgkJEQAAAA==.Alavia:BAABLgAECn8YAAIDAAcJ0xPZMADqAQADAAcJ0xPZMADqAQAAAA==.Alinäs:BAAALgAECgYJDQAAAA==.Aliën:BAAALgADCgEJAQAAAA==.Alliumoo:BAAALgAECgYJCwAAAA==.Alydrus:BAAALgAECgIJAgAAAA==.Alíen:BAAALgADCgQJBAAAAA==.',
An='Anberlinean:BAAALgAECgYJEAAAAA==.Angryelf:BAAALgAECgEJAQAAAA==.Ankles:BAAALgADCgcJBwABLgAECggJFwAEAH4gAA==.Annahe:BAAALgAECgYJCgAAAA==.Annale:BAAALgAECgEJAQABLgAECgYJCgAFAAAAAA==.Annatara:BAAALgADCgcJCQAAAA==.Anzala:BAAALgADCgIJAgAAAA==.',
Ao='Aoba:BAAALgAECgEJAQAAAA==.',
Ar='Arataeus:BAAALgAECgQJBAAAAA==.Armsmaster:BAABLgAECn8gAAIGAAgJmhsAXQDbAQAGAAgJmhsAXQDbAQAAAA==.',
As='Asalynn:BAAALgADCgEJAQAAAA==.',
Av='Avalina:BAAALgAECgEJAQAAAA==.Avengharambe:BAAALgADCgcJBwAAAA==.Averan:BAAALgAECgUJCgAAAA==.Averybug:BAAALgADCgEJAQAAAA==.',
Ba='Backbeamz:BAAALgAECgYJBgAAAA==.Backspace:BAAALgADCgYJBgAAAA==.Badgër:BAAALgADCgEJAQAAAA==.Baey:BAAALgADCgMJAwABLgAECgcJEgACAA4cAA==.Balduun:BAAALgADCgYJDgAAAA==.',
Be='Bearnaked:BAAALgADCgIJAgAAAA==.Bellíon:BAAALgAECgMJBgAAAA==.',
Bi='Bixee:BAAALgAECgUJBQAAAA==.',
Bl='Blacat:BAABLgAECn8bAAMHAAgJTRn3AAA1AgAHAAgJTRn3AAA1AgAIAAIJUAMoeABEAAAAAA==.Bleen:BAAALgAECgQJBgAAAA==.Blitzcomets:BAAALgADCgUJBwAAAA==.Bloodbenders:BAAALgADCgEJAQAAAA==.',
Bo='Bogeyman:BAABLgAECn8XAAIJAAcJMR5LCABVAgAJAAcJMR5LCABVAgAAAA==.Boondoks:BAAALgAECgQJCAABLgAECggJHAABAPkcAA==.Borda:BAAALgADCgMJBgAAAA==.Bowrider:BAAALgAECgQJBAAAAA==.',
Br='Brondeadeye:BAAALgAECgUJBgAAAA==.Brunore:BAAALgAECgYJBgAAAA==.',
Bu='Bubbajüdd:BAAALgADCgEJAQAAAA==.',
Ch='Chakrah:BAABLgAECn8YAAIKAAcJ/gkTEQDmAAAKAAcJ/gkTEQDmAAAAAA==.Challan:BAAALgAFFAEJAQAAAA==.Chrno:BAAALgAECgYJBwAAAA==.Chunkymonkey:BAAALgADCgYJBgABLgAECgYJEAAFAAAAAA==.',
Cl='Clutcha:BAABLgAECn8YAAILAAYJaBvUBQCVAQALAAYJaBvUBQCVAQAAAA==.Clutchcross:BAAALgAECgQJBgABLgAECgYJGAALAGgbAA==.Clutchplate:BAAALgAECgcJEwAAAA==.Clûtch:BAABLgAECn8aAAIGAAgJfB/pNgBbAgAGAAgJfB/pNgBbAgAAAA==.',
Co='Codenameblue:BAAALgADCgEJAQAAAA==.Coog:BAAALgADCgEJAQAAAA==.Corynthe:BAABLgAECn8VAAIMAAYJEB9RGQARAgAMAAYJEB9RGQARAgAAAA==.',
Cr='Crickie:BAAALgADCggJCAAAAA==.Crovaxis:BAABLgAECn8VAAINAAYJ0iCIAgCoAQANAAYJ0iCIAgCoAQAAAA==.',
Cu='Cursecackler:BAAALgADCgYJBgAAAA==.',
Cy='Cynda:BAAALgADCgMJAwAAAA==.Cyndestine:BAAALgADCgYJBgAAAA==.Cyzarius:BAAALgAECgEJAQAAAA==.',
Da='Damekka:BAAALgAECgQJBAAAAA==.Danazer:BAAALgADCgMJBQAAAA==.Darktalyn:BAABLgAECn8VAAMKAAYJxQ4mMwBOAQAKAAYJxQ4mMwBOAQAMAAYJCQZ/EADmAAAAAA==.',
De='Deathbinger:BAAALgADCgEJAQAAAA==.Deathgriped:BAAALgAECgYJEwAAAA==.Deathhawkzz:BAABLgAECn8WAAMOAAcJ+hXgCwAEAgAOAAcJ+hXgCwAEAgAPAAEJJAREKwEnAAAAAA==.Deathphoenix:BAAALgADCgcJBwAAAA==.Deathslock:BAAALgADCgQJBAAAAA==.Deekura:BAAALgAECgYJDgAAAA==.Deladorana:BAAALgADCgUJBQAAAA==.Dellma:BAAALgADCgYJBgAAAA==.Delusion:BAAALgAECgEJAQAAAA==.Demonpapi:BAAALgAECgEJAgAAAA==.Demoryx:BAEALgADCgkJCQABLgAECgYJFgAQAJUYAA==.Denjack:BAAALgADCgcJEQAAAA==.',
Dh='Dhadzen:BAAALgAECgIJBgAAAA==.',
Di='Dionan:BAABLgAECn8VAAIRAAYJAhK6KwDxAAARAAYJAhK6KwDxAAAAAA==.',
Do='Docs:BAABLgAECn8UAAIEAAcJTxLiDgBPAQAEAAcJTxLiDgBPAQAAAA==.Doks:BAABLgAECn8cAAIBAAgJ+Ry1EwB3AgABAAgJ+Ry1EwB3AgAAAA==.Dontpanic:BAAALgAECgMJAwABLgAECggJFwAEAH4gAA==.Doomsnake:BAAALgADCgMJAwABLgADCgEJAQAFAAAAAA==.Dove:BAAALgADCgYJBgAAAA==.',
Dr='Dragomalfoy:BAAALgADCgQJBAAAAA==.Dragõn:BAAALgAECgEJAQAAAA==.Drinker:BAAALgADCgUJBQAAAA==.',
Ea='Ealara:BAAALgAECgYJEAAAAA==.',
Ed='Edran:BAAALgADCgcJFQAAAA==.',
Ei='Eifel:BAAALgAECgQJBAABLgAECggJFAARAEsgAA==.Eimin:BAAALgADCgYJCgAAAA==.',
El='Eldarion:BAAALgAECgMJAgAAAA==.Ellipses:BAAALgADCgYJBgABLgAECgYJDQAFAAAAAA==.',
Em='Emeraldz:BAAALgAECgYJDQAAAA==.',
En='Eneru:BAAALgADCgYJCAABLgAECggJHwAEAJ0XAA==.',
Er='Erebrethil:BAAALgAECgYJCQAAAA==.',
Es='Espe:BAAALgAECgYJDwAAAA==.',
Eu='Eucalyptia:BAAALgADCgQJBAAAAA==.',
Ev='Evenin:BAAALgADCgIJAgAAAA==.',
Fa='Faenor:BAAALgADCgkJEQAAAA==.Faynor:BAABLgAECn8WAAISAAYJFhbwMwCAAQASAAYJFhbwMwCAAQAAAA==.',
Fi='Firêfly:BAAALgAECgEJAQAAAA==.',
Fk='Fknsteve:BAAALgADCgYJBgAAAA==.',
Fl='Flipingflerp:BAAALgAECgUJBgAAAA==.Flloran:BAAALgAECgEJAQAAAA==.Floragoth:BAAALgAECgEJAQAAAA==.Flowers:BAAALgADCgkJCQAAAA==.Fluffboi:BAAALgAECgYJDwAAAA==.',
Fo='Foxyblue:BAAALgAECgYJDgAAAA==.',
Fr='Fraggle:BAABLgAECn8XAAIEAAgJfiAfCwDGAgAEAAgJfiAfCwDGAgAAAA==.Freefolk:BAAALgADCgcJBwAAAA==.Freefromfate:BAAALgAECgEJAQAAAA==.Frogchi:BAAALgADCgcJBwAAAA==.Frostbité:BAAALgAECggJEwAAAA==.Fruit:BAAALgADCgkJGAAAAA==.',
Fu='Fumikiko:BAAALgADCgIJAgABLgAECgcJGgATAH0eAA==.Furrykarg:BAAALgAECgEJAQAAAA==.',
['Fú']='Fúzzy:BAAALgADCgEJAgAAAA==.',
Ga='Gakkle:BAAALgAECgQJBAAAAA==.Galadralvia:BAAALgAECgUJDwAAAA==.Gali:BAAALgAECgUJDAAAAA==.',
Ge='Gearsofbob:BAAALgAFFAIJAgAAAA==.Getphisted:BAAALgADCgMJAwAAAA==.',
Gh='Ghoulei:BAABLgAECn8WAAIGAAYJQiGEPwA6AgAGAAYJQiGEPwA6AgAAAA==.',
Gl='Glaistiguain:BAAALgAECgYJCwABLgAECggJIAAGAJobAA==.Glifin:BAAALgADCgcJEgAAAA==.Gloomstalkin:BAABLgAECn8ZAAIUAAcJDxfBDAD/AQAUAAcJDxfBDAD/AQAAAA==.',
Gn='Gnøsis:BAAALgADCggJEQAAAA==.',
Go='Goldìelocks:BAAALgADCgEJAQAAAA==.Gom:BAAALgAECgIJAgAAAA==.Gomdrog:BAAALgADCgUJBQAAAA==.',
Gr='Gr:BAABLgAECn8VAAIVAAYJXwc5BAAUAQAVAAYJXwc5BAAUAQAAAA==.Grannecs:BAAALgADCgEJAQAAAA==.Grizzledpaw:BAAALgADCggJEAAAAA==.Gryffs:BAABLgAECn8fAAIWAAgJqhj5AgDSAQAWAAgJqhj5AgDSAQAAAA==.',
Gu='Gutts:BAABLgAECn8VAAQWAAYJWR8mAwDGAQAWAAYJWR8mAwDGAQAXAAQJEg1XJADKAAADAAQJ0Q7YfQDFAAAAAA==.',
Ha='Haiirøkami:BAABLgAECn8WAAIRAAYJVgePuQASAQARAAYJVgePuQASAQAAAA==.Halomea:BAAALgADCgQJBAAAAA==.Hanukira:BAAALgADCgUJBQAAAA==.Happi:BAAALgAECgYJCQABLgAFFAYJDQAYAFsVAA==.Harald:BAAALgAECgQJBQAAAA==.Harkle:BAAALgADCgcJDQAAAA==.Haruun:BAAALgAECgEJAQAAAA==.',
He='Hesmydaddy:BAABLgAECn8XAAIMAAcJagXpRwAZAQAMAAcJagXpRwAZAQAAAA==.',
Ho='Hongling:BAAALgADCgYJBgABLgAECgcJGgATAH0eAA==.Honêy:BAEALgADCgUJBQABLgAECgYJFgAQAJUYAA==.Hotdogstand:BAACLgAFFH8IAAILAAQJJCAQAQCLAQALAAQJJCAQAQCLAQAuAAQKfyUAAwsACAnvJeoFADIDAAsACAnvJeoFADIDABUABAmEIYELAHMBAAAA.',
Hu='Huzzaah:BAAALgAECgIJAgABLgAECggJFwAEAH4gAA==.',
Hy='Hyperius:BAAALgADCgIJAgAAAA==.',
['Hö']='Höneÿdew:BAABLgAECn8ZAAIZAAgJ7Bg2LAADAgAZAAgJ7Bg2LAADAgAAAA==.',
Ic='Icemann:BAAALgAECgEJAgAAAA==.',
Il='Ilidrayssel:BAAALgAECgcJEwAAAA==.Illida:BAAALgAECgMJBQAAAA==.',
Im='Imhappy:BAAALgADCgEJAQAAAA==.Imherdaddy:BAAALgADCgYJCAABLgAECgcJGQAUAA8XAA==.',
In='Innervape:BAAALgADCgEJAQAAAA==.',
Ja='Jacorict:BAAALgAECgYJDgAAAA==.Jagga:BAAALgADCgMJAwAAAA==.Jarrack:BAAALgAECgYJDwAAAA==.',
Je='Jellyhawk:BAAALgAECgEJAQAAAA==.Jessicae:BAAALgAECgYJDAAAAA==.',
Jo='Josephedd:BAABLgAECn8XAAIIAAgJ/Q2oKwClAQAIAAgJ/Q2oKwClAQAAAA==.',
Ju='Jukk:BAAALgAECgYJBwABLgAECgYJCAAFAAAAAA==.Junazeena:BAAALgAECgYJCgAAAA==.',
Ka='Kaji:BAAALgAECgQJBAAAAA==.Kalistus:BAAALgADCgYJBwAAAA==.Kargfu:BAAALgADCgEJAQABLgAECgEJAQAFAAAAAA==.Karolat:BAAALgAECgIJAQAAAA==.Kayfabe:BAABLgAECn8VAAICAAYJpANS+gAGAQACAAYJpANS+gAGAQAAAA==.',
Ke='Keishilda:BAAALgADCgcJBwAAAA==.Keladria:BAAALgADCgkJEQAAAA==.Kelvyren:BAAALgADCgEJAQAAAA==.Kenel:BAAALgAECgcJEQAAAA==.Kerea:BAABLgAECn8WAAIaAAYJ9Qd3IACxAAAaAAYJ9Qd3IACxAAAAAA==.',
Ki='Kicken:BAAALgAECgYJDgAAAA==.Kitschy:BAAALgADCgEJAQAAAA==.Kittyperry:BAAALgAECgIJAgAAAA==.',
Kn='Knome:BAABLgAECn8SAAICAAcJDhwKVgA2AgACAAcJDhwKVgA2AgAAAA==.',
Ko='Koana:BAAALgAECgQJBgAAAA==.Korthelan:BAABLgAECn8XAAIYAAcJXw+UYwB2AQAYAAcJXw+UYwB2AQAAAA==.Kothara:BAABLgAECn8XAAIZAAYJtBI4QgCnAQAZAAYJtBI4QgCnAQAAAA==.Kotongar:BAAALgADCgMJAwAAAA==.',
Kr='Kreeoo:BAAALgAECgEJAQAAAA==.Krimzin:BAABLgAECn8bAAMZAAgJXiGVIQA8AgAZAAgJXiGVIQA8AgAUAAEJJgclMQAvAAABLgAFFAIJBQARAFAWAA==.Krystine:BAAALgADCgkJGQAAAA==.',
Ks='Kserasera:BAAALgAECgYJDQAAAA==.',
Ku='Kuball:BAAALgAECgEJAQABLgAECgYJFQAWAFkfAA==.Kukuruku:BAAALgAECgEJAQAAAA==.',
['Kî']='Kîllara:BAABLgAECn8dAAIBAAgJtBRkBwDaAQABAAgJtBRkBwDaAQAAAA==.',
La='Labialicious:BAAALgAECgEJAQAAAA==.Lanfeår:BAAALgAECgYJEAAAAA==.Lanskies:BAAALgAECgYJBgAAAA==.',
Le='Leafymeds:BAAALgAECgUJCgABLgAECgYJDAAFAAAAAA==.Lebronjames:BAAALgADCgQJBAAAAA==.Leiluna:BAAALgADCgkJEQAAAA==.',
Li='Libertinne:BAABLgAECn8VAAIDAAYJrho4PAC0AQADAAYJrho4PAC0AQAAAA==.Librarte:BAAALgAECgcJEgAAAA==.Ligmanuts:BAAALgAECgIJBAAAAA==.Lillytrae:BAAALgADCgEJAQAAAA==.Listie:BAAALgADCgQJBAAAAA==.Litty:BAAALgAECgcJEgAAAA==.Lizrdkng:BAAALgADCgMJBgAAAA==.',
Lo='Locktärd:BAACLgAFFH8IAAQbAAMJ9xayAgBkAAAPAAIJShb0MgCtAAAOAAIJogZ4DgCXAAAbAAIJ5xuyAgBkAAAuAAQKfyYABBsACAmIH6oCAJACABsACAk9H6oCAJACAA8ABwlYGBdCAAYCAA4AAgkLHHpGAJwAAAAA.Lohken:BAAALgAECgMJCQAAAA==.Lox:BAABLgAECn8WAAIOAAYJ8hB7BAAPAQAOAAYJ8hB7BAAPAQAAAA==.',
Lu='Lucieb:BAAALgAECgEJAQAAAA==.',
Ly='Lydirn:BAAALgAECgYJEgAAAA==.Lyofel:BAAALgAECgYJDwAAAA==.Lyonel:BAAALgADCggJCAAAAA==.',
['Lí']='Lítterbox:BAAALgAECgEJAQAAAA==.',
Ma='Magedzen:BAAALgADCgEJAgAAAA==.Magicguy:BAAALgAECgYJCQAAAA==.Mahariel:BAAALgAECgUJBQAAAA==.Mahdy:BAABLgAECn8eAAIRAAcJtBfKRQASAgARAAcJtBfKRQASAgAAAA==.Maivel:BAAALgAECgEJAQAAAA==.Mandret:BAAALgAECgEJAQAAAA==.Manicppanic:BAAALgAECgYJBgABLgAECggJFwAEAH4gAA==.Manrypurp:BAAALgAECgUJDQAAAA==.Marcie:BAABLgAECn8WAAIIAAYJiQupDwD6AAAIAAYJiQupDwD6AAAAAA==.',
Mc='Mchammer:BAAALgADCgUJBgAAAA==.',
Me='Meatyloaf:BAAALgAECgQJBQAAAA==.Melkedrik:BAAALgAECgQJBQAAAA==.Melleren:BAAALgADCgYJAwAAAA==.Messande:BAAALgAECgEJAQAAAA==.',
Mi='Minõs:BAAALgADCgkJEAAAAA==.Mirai:BAAALgADCgUJBQAAAA==.Mirei:BAAALgAECgYJDgAAAA==.Mistdancer:BAAALgADCgYJBgABLgAECgUJCgAFAAAAAA==.Miyagí:BAAALgAECgcJDQAAAA==.',
Mo='Mojam:BAAALgAECgEJAQAAAA==.Moonless:BAAALgADCgMJAwAAAA==.Moovidlin:BAAALgAECgYJCAAAAA==.Morinnas:BAAALgADCgkJDAAAAA==.Moschpit:BAAALgADCgEJAQAAAA==.',
Mu='Munkeez:BAAALgADCgMJAwAAAA==.Murdermoo:BAAALgADCgMJAwAAAA==.Mushhead:BAAALgAECgUJCAAAAA==.',
My='Myishaa:BAAALgADCgIJAgAAAA==.Mykeal:BAAALgADCgIJAgAAAA==.Myndigo:BAAALgADCgQJBAAAAA==.',
Na='Nargo:BAAALgADCgYJCQAAAA==.',
Ne='Necrostalker:BAAALgADCgkJCQABLgADCgEJAQAFAAAAAA==.Negative:BAAALgAECgEJAQAAAA==.Nerwende:BAAALgAECgEJAQAAAA==.Nethershade:BAAALgAECgYJDgAAAA==.Netherstörm:BAAALgADCgkJEgAAAA==.Netzach:BAAALgAECgkJCAAAAA==.',
Ni='Niclea:BAAALgADCgYJBgAAAA==.Nightangels:BAAALgAECgEJAQAAAA==.Nightelm:BAABLgAECn8aAAQTAAcJfR7qGwDpAQATAAcJdR7qGwDpAQAcAAQJwwsYNADMAAAdAAMJ+h3KKgDHAAAAAA==.Niënor:BAAALgADCgYJBgABLgAECgYJCQAFAAAAAA==.',
No='Noslien:BAAALgAECgQJBAAAAA==.Nostradamuz:BAAALgAECgEJAQAAAA==.Novasong:BAAALgAECgEJAwAAAA==.',
Ny='Nyxstonia:BAABLgAECn8hAAIWAAgJKBouAwDFAQAWAAgJKBouAwDFAQAAAA==.',
Ob='Oballi:BAAALgAECgEJAQAAAA==.',
Ol='Olierra:BAAALgAECgQJBQAAAA==.',
On='Onlyvoids:BAAALgAECgMJAwAAAA==.',
Ot='Otkspring:BAAALgAECgYJEwAAAA==.Otto:BAABLgAECn8UAAIRAAYJMg0KIwAeAQARAAYJMg0KIwAeAQAAAA==.',
Ox='Oxadin:BAAALgAECgEJAQAAAA==.Oxideous:BAAALgADCgMJAwAAAA==.',
Pa='Paleale:BAAALgAECgYJCgAAAA==.Pallyshore:BAAALgADCgMJAwAAAA==.Pampoovy:BAEALgADCgMJAwABLgAECgQJBQAFAAAAAA==.Pantoponrose:BAAALgADCgkJDQAAAA==.Pastorbash:BAAALgADCggJCQAAAA==.',
Pb='Pb:BAAALgAECgMJAwAAAA==.',
Pe='Persephoneia:BAABLgAECn8VAAIKAAYJqQ3kDAAlAQAKAAYJqQ3kDAAlAQAAAA==.',
Pi='Piperclip:BAAALgADCgEJAQAAAA==.',
Pk='Pkashmuk:BAAALgADCgcJBwAAAA==.',
Pr='Prophettool:BAAALgAECgcJEwAAAA==.Pruned:BAAALgADCgcJBwABLgAFFAMJCAAbAPcWAA==.',
Qu='Quanchii:BAAALgADCgMJAwAAAA==.',
Ra='Raemie:BAAALgAECgIJAgAAAA==.Ragequit:BAAALgAECgYJDQAAAA==.Rakulm:BAAALgADCgUJCgAAAA==.Ravenrest:BAABLgAECn8YAAIKAAYJ6BwdHwDfAQAKAAYJ6BwdHwDfAQAAAA==.',
Re='Reaverhiem:BAAALgAECgQJBgAAAA==.Reiko:BAAALgADCgkJDwABLgAECgYJDgAFAAAAAA==.Remuz:BAAALgADCgkJDAAAAA==.Rennwick:BAAALgAECgQJBgAAAA==.',
Ri='Rilz:BAABLgAECn8VAAIGAAYJJBuXEwB1AQAGAAYJJBuXEwB1AQAAAA==.',
Ro='Rochambeu:BAAALgADCgEJAQAAAA==.Rodgerwabbet:BAAALgADCgEJAQAAAA==.Roiddrood:BAAALgAECgIJAgABLgAECggJHwAPAN8RAA==.Roidlock:BAABLgAECn8fAAIPAAgJ3xGlDQCnAQAPAAgJ3xGlDQCnAQAAAA==.Roidtank:BAAALgAECgUJBgABLgAECggJHwAPAN8RAA==.Rosaline:BAAALgADCggJFgAAAA==.Rottn:BAAALgADCgcJCAABLgAECgYJDQAFAAAAAA==.',
Ru='Runerion:BAAALgAECgEJAgAAAA==.',
Ry='Ry:BAAALgADCgkJEAAAAA==.',
['Rà']='Ràìn:BAAALgAECggJDwAAAA==.',
Sa='Safmen:BAAALgAECgYJDgAAAA==.Saraid:BAABLgAECn8VAAMaAAYJAw9bFwAFAQAaAAYJAw9bFwAFAQAIAAMJ7Q4BYQCdAAAAAA==.Saravase:BAAALgAECgMJBgAAAA==.Sardel:BAAALgADCgcJBwAAAA==.Sargeros:BAAALgAECgQJBAAAAA==.Sazem:BAAALgADCgIJAgAAAA==.',
Se='Sedaldra:BAAALgADCgYJCQAAAA==.',
Sh='Shadownights:BAABLgAECn8WAAIKAAcJ8Az0KwB9AQAKAAcJ8Az0KwB9AQAAAA==.Shamoneyy:BAAALgADCgUJBQAAAA==.Shiki:BAAALgADCgkJCQABLgAECgYJDgAFAAAAAA==.Shinifur:BAAALgADCgUJBgAAAA==.Shinoto:BAAALgAECgMJBQAAAA==.Shockazam:BAAALgAECgcJEgAAAA==.Shrewby:BAAALgAECgEJAQAAAA==.Shyandra:BAAALgADCgYJBgAAAA==.',
Si='Sieghart:BAAALgAECgEJAQAAAA==.Six:BAAALgAECgUJCwAAAA==.',
Sl='Sloptop:BAAALgAECgEJAgAAAA==.',
Sn='Snickersbar:BAAALgADCgUJCAAAAA==.Snowynn:BAAALgADCggJGQAAAA==.Snöw:BAAALgAECgYJDQAAAA==.Snöwy:BAAALgADCgcJCAAAAA==.',
Sp='Spooki:BAAALgAECgEJAQAAAA==.Spyro:BAABLgAECn8dAAQTAAkJ4Ax0GgD3AQATAAkJ4Ax0GgD3AQAcAAgJHQtDIwBfAQAdAAIJpgnENgBgAAAAAA==.',
Sr='Sron:BAABLgAECn8VAAIZAAYJHB+aKgALAgAZAAYJHB+aKgALAgAAAA==.',
St='Stariah:BAABLgAECn8UAAICAAcJDwogtQB1AQACAAcJDwogtQB1AQAAAA==.',
Su='Sumwhiteguy:BAAALgADCgkJCQAAAA==.',
Sw='Swooze:BAABLgAECn8gAAICAAgJrRwYLwC2AgACAAgJrRwYLwC2AgAAAA==.',
Sy='Syndicate:BAAALgADCggJCgAAAA==.Syrenis:BAAALgADCgkJDwABLgAECgcJGgATAH0eAA==.',
['Sù']='Sùnnydk:BAAALgADCgcJBwAAAA==.',
Ta='Tankinbur:BAAALgADCggJEAAAAA==.Tarlyn:BAABLgAECn8gAAQEAAgJOROTMgC0AQAEAAgJOROTMgC0AQARAAUJNRL8qAAwAQAJAAEJAADTPwA+AAAAAA==.Tatslight:BAAALgAECgYJEQAAAA==.Tatsrage:BAAALgADCgYJBgAAAA==.Tazaral:BAAALgADCgEJAQABLgAECgQJBgAFAAAAAA==.',
Te='Teysá:BAAALgADCgEJAQAAAA==.',
Th='Thor:BAAALgAECgYJCAAAAA==.Thyandris:BAAALgADCgYJCwAAAA==.Thánátós:BAAALgADCgkJEQAAAA==.',
Ti='Timmthemage:BAAALgAECgUJBwAAAQ==.Tinytex:BAAALgAECgUJCAAAAA==.',
To='Toberson:BAAALgADCgkJFAAAAA==.Toxicbanana:BAAALgAECgQJBQAAAA==.',
Tr='Tradarynn:BAAALgAECgQJCAAAAA==.Tralls:BAEBLgAECn8WAAMQAAYJlRiRDQAnAQAQAAYJlRiRDQAnAQAeAAEJ8AoxLAA1AAABLgAECgYJFgAQAJUYAA==.Trayvein:BAAALgADCgUJBQAAAA==.Tress:BAAALgAECgEJAgAAAA==.',
Ts='Tsindre:BAAALgADCgkJCQAAAA==.',
Tu='Tulkar:BAAALgAECgEJAQAAAA==.Turambar:BAAALgADCgEJAQAAAA==.',
Un='Unholymochi:BAABLgAECn8YAAIGAAYJFR+YXQDaAQAGAAYJFR+YXQDaAQAAAA==.',
Va='Valhalia:BAAALgAECgYJCwAAAA==.Varaelitha:BAAALgAECgMJAwAAAA==.Vashan:BAAALgAECgQJBAAAAA==.Vashni:BAAALgAECgkJDAAAAA==.',
Ve='Velinariae:BAAALgADCgUJCgAAAA==.Vengful:BAAALgAECgYJDAAAAA==.',
Vi='Vivy:BAABLgAECn8fAAQPAAkJMhQuDAC3AQAPAAkJyBMuDAC3AQAOAAQJaxScMwDpAAAbAAIJBhXKJgBWAAAAAA==.',
Vo='Vorumbrae:BAAALgADCgEJAQAAAA==.',
Vu='Vultus:BAAALgAECgIJAgAAAA==.',
['Vä']='Väntage:BAAALgADCgEJAQAAAA==.',
Wa='Wagyubeef:BAAALgAECgYJDwAAAA==.Wali:BAAALgAECgYJDgAAAA==.',
Wh='Whatupbruh:BAABLgAECn8hAAMUAAcJuCHuAgDfAQAUAAcJuCHuAgDfAQANAAEJ3QZZkgAoAAAAAA==.',
Wi='Wildfire:BAAALgADCgUJBQAAAA==.',
Wy='Wyleriya:BAAALgAECgcJEQAAAA==.',
Xa='Xanthas:BAAALgADCgQJBAAAAA==.',
Xc='Xcella:BAAALgAECgMJAwAAAA==.',
Xe='Xephon:BAAALgADCgcJBwAAAA==.',
Ye='Yelizaveta:BAAALgADCgMJAwAAAA==.',
Yl='Ylfcwen:BAAALgAECgEJAQAAAA==.',
Yo='Yodey:BAAALgAECgUJCQAAAA==.',
Yu='Yuaetrende:BAABLgAECn8bAAIfAAgJkRyCDgB7AgAfAAgJkRyCDgB7AgAAAA==.Yumii:BAABLgAECn8VAAMMAAYJiyWlAQB6AgAMAAYJSCWlAQB6AgAgAAYJ/yH0DgBNAgAAAA==.',
Za='Zack:BAAALgADCgYJCAAAAA==.Zagul:BAAALgAECgUJCAAAAA==.Zalarah:BAAALgAECgMJAwAAAA==.Zalarilia:BAAALgAECgEJAQAAAA==.Zanoo:BAAALgADCgYJBwAAAA==.Zaphod:BAAALgADCgMJAwAAAA==.Zardan:BAAALgAECggJCQAAAA==.',
Zi='Ziegler:BAAALgADCgYJBgAAAA==.',
Zo='Zorrita:BAAALgAECgEJAQAAAA==.',
Zu='Zugglite:BAABLgAECn8WAAIEAAYJHyMzFwBYAgAEAAYJHyMzFwBYAgAAAA==.Zulthar:BAAALgAECgcJDgAAAA==.',
['Äs']='Äshborn:BAAALgAECgYJDQAAAA==.Ästra:BAAALgADCggJCAAAAA==.',
['Æl']='Ælx:BAABLgAECn8WAAICAAkJWhCaCAAdAgACAAkJWhCaCAAdAgAAAA==.',
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

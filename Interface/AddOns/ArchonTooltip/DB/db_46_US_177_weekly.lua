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

local lookup = {'Shaman-Restoration','Mage-Frost','Warrior-Fury','Druid-Balance','Evoker-Augmentation','Paladin-Retribution','Paladin-Holy','Monk-Windwalker','DeathKnight-Unholy','Unknown-Unknown','Druid-Feral','Paladin-Protection','Priest-Shadow','DemonHunter-Devourer','Druid-Restoration','Rogue-Subtlety','Warrior-Protection','Warrior-Arms','Priest-Holy','Hunter-Marksmanship','Hunter-BeastMastery','DeathKnight-Blood','Warlock-Destruction','Warlock-Demonology','DeathKnight-Frost','Shaman-Elemental','Monk-Brewmaster','Hunter-Survival','Rogue-Assassination','Rogue-Outlaw','Monk-Mistweaver','Warlock-Affliction','Evoker-Preservation','Evoker-Devastation','Druid-Guardian','Shaman-Enhancement','DemonHunter-Havoc','DemonHunter-Vengeance','Priest-Discipline',}
local provider = {region='US',realm='Ravencrest',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abelas:BAAALgADCgYJFwAAAA==.Abracadaxis:BAAALgADCggJCAAAAA==.',
Ad='Adallyn:BAAALgADCgYJCgAAAA==.Adzen:BAAALgADCgcJBwAAAA==.Adêrna:BAABLgAECn8fAAIBAAgJghxXFgAAAgABAAgJghxXFgAAAgAAAA==.',
Af='Affliction:BAAALgADCgUJBQAAAA==.',
Ag='Agba:BAAALgAFFAIJAgAAAA==.',
Ah='Ahktari:BAAALgADCgcJBwAAAA==.',
Al='Alaidan:BAAALgAECgYJCgAAAA==.Alanus:BAABLgAECn8lAAICAAgJWxHcOgC4AQACAAgJWxHcOgC4AQAAAA==.Alarion:BAAALgAECgMJBgAAAA==.Alavia:BAABLgAECn8oAAIDAAgJ4xMxFQDAAQADAAgJ4xMxFQDAAQAAAA==.Alinäs:BAABLgAECn8dAAICAAgJ+w80QQCjAQACAAgJ+w80QQCjAQAAAA==.Aliën:BAAALgADCgEJAQAAAA==.Alliumoo:BAABLgAECn8XAAIEAAYJwQnOLwDUAAAEAAYJwQnOLwDUAAAAAA==.Altana:BAAALgAECggJEwABLgAECggJHgAFAL0eAA==.Alydrus:BAAALgAECgYJDAAAAA==.Alíen:BAAALgADCgQJBAAAAA==.',
An='Anberlinean:BAABLgAECn8WAAIGAAYJ5gfpfwDsAAAGAAYJ5gfpfwDsAAAAAA==.Angryelf:BAAALgAECgEJAQAAAA==.Ankles:BAAALgADCgcJBwABLgAFFAQJCgAHAOcOAA==.Annahe:BAABLgAECn8UAAIIAAgJUxvcCgALAgAIAAgJUxvcCgALAgAAAA==.Annale:BAAALgAECgQJBQABLgAECggJFAAIAFMbAA==.Annatara:BAAALgAECgEJAQAAAA==.Anzala:BAAALgADCgIJAgAAAA==.',
Ao='Aoba:BAAALgAECgYJCgAAAA==.',
Ar='Arataeus:BAAALgAECgQJCgAAAA==.Areliss:BAAALgAECgQJBAAAAA==.Armsmaster:BAABLgAECn8lAAIJAAgJLx/0XADbAQAJAAgJLx/0XADbAQAAAA==.Artemistha:BAAALgADCgYJBgAAAA==.',
As='Asalynn:BAAALgADCgEJAQAAAA==.',
Av='Avalina:BAAALgAECgEJAQAAAA==.Avengharambe:BAAALgADCgcJBwAAAA==.Averan:BAAALgAECgYJEQAAAA==.Averybug:BAAALgAECgEJAQAAAA==.',
Ba='Backbeamz:BAAALgAECgYJCQAAAA==.Backspace:BAAALgADCgYJBgAAAA==.Badgër:BAAALgADCgEJAQAAAA==.Baey:BAAALgADCgMJAwABLgAECggJIQACAPoeAA==.Balduun:BAAALgADCgYJDgAAAA==.Barelycastin:BAAALgADCgMJAwAAAA==.Bashdadargon:BAAALgAECgEJAQABLgAECgQJBAAKAAAAAA==.Bashoomba:BAAALgAECgQJBAAAAA==.',
Be='Bearnaked:BAAALgADCgIJAgAAAA==.Belgarathh:BAAALgAFFAIJAgAAAA==.Bellíon:BAAALgAECgMJBgAAAA==.',
Bi='Bird:BAAALgADCgEJAQAAAA==.Bixee:BAAALgAECgUJCQAAAA==.',
Bl='Blacat:BAABLgAECn8hAAMLAAgJ1xnrAwA5AgALAAgJ1xnrAwA5AgAEAAIJUAM4eABEAAAAAA==.Bleen:BAAALgAECgUJDAAAAA==.Blitzcomets:BAAALgADCgcJCwAAAA==.Bloodbenders:BAAALgADCgEJAQAAAA==.Blueday:BAAALgAECgEJAQAAAA==.',
Bo='Bogeyman:BAABLgAECn8mAAIMAAgJJCA9AwBxAgAMAAgJJCA9AwBxAgAAAA==.Boondoks:BAABLgAECn8ZAAIHAAcJTR2VDQA8AgAHAAcJTR2VDQA8AgABLgAECggJKQABALkeAA==.Borda:BAAALgADCgcJEgAAAA==.Bowrider:BAAALgAECgYJBwAAAA==.',
Br='Brondeadeye:BAAALgAECgUJBwAAAA==.Brunore:BAAALgAECgYJDAAAAA==.',
Bu='Bubbajüdd:BAAALgADCgEJAQAAAA==.',
Ca='Caledur:BAAALgAECgUJBgAAAA==.Caratdeullie:BAAALgADCgEJAQAAAA==.Careblair:BAAALgADCgEJAQAAAA==.',
Ch='Chakrah:BAABLgAECn8YAAINAAcJ/gnmLQDhAAANAAcJ/gnmLQDhAAAAAA==.Challan:BAABLgAFFH8FAAIOAAIJowJ7UgByAAAOAAIJowJ7UgByAAAAAA==.Chloe:BAABLgAECn8XAAIPAAkJ9AEgmAAtAAAPAAkJ9AEgmAAtAAAAAA==.Chrno:BAAALgAECgcJEwAAAA==.Chunkymonkey:BAAALgADCgYJBgABLgAFFAIJBAAKAAAAAA==.',
Cl='Clutcha:BAABLgAECn8aAAIQAAYJDRxPEwB7AQAQAAYJDRxPEwB7AQAAAA==.Clutchcross:BAAALgAECgQJBgABLgAECgYJGgAQAA0cAA==.Clutchplate:BAABLgAECn8bAAMRAAcJFBNzEQBLAQARAAcJFBNzEQBLAQASAAEJWgZrQwAoAAAAAA==.Clûtch:BAACLgAFFH8HAAIJAAMJyRqbRQADAQAJAAMJyRqbRQADAQAuAAQKfx4AAgkACAlxIOk2AFsCAAkACAlxIOk2AFsCAAAA.',
Co='Codenameblue:BAAALgADCgEJAQAAAA==.Coldphoenix:BAAALgADCgkJCQAAAA==.Coog:BAAALgADCgEJAQAAAA==.Corynthe:BAABLgAECn8kAAITAAgJPB1iCwAwAgATAAgJPB1iCwAwAgAAAA==.',
Cr='Crickie:BAAALgAECgQJBQAAAA==.Crovaxis:BAABLgAECn8lAAMUAAgJXSKGAgBUAgAUAAcJ8SKGAgBUAgAVAAEJ4B4CnwBVAAAAAA==.',
Cu='Cursecackler:BAAALgADCgYJBgAAAA==.',
Cy='Cynda:BAAALgADCgMJAwAAAA==.Cyndestine:BAAALgADCgYJBgAAAA==.Cyzarius:BAAALgAECgEJAQAAAA==.',
Da='Daddychill:BAAALgAECggJCAAAAA==.Daedrìc:BAAALgAECgMJAwAAAA==.Damekka:BAAALgAECgQJBQAAAA==.Danazer:BAAALgAECgUJBQAAAA==.Danoe:BAAALgADCggJCAAAAA==.Darktalyn:BAABLgAECn8pAAMTAAgJmhNmEADmAQATAAgJmhNmEADmAQANAAYJxQ4vMwBOAQAAAA==.',
De='Deathbinger:BAAALgADCgEJAQAAAA==.Deathgriped:BAABLgAECn8fAAIWAAYJohaGEgBLAQAWAAYJohaGEgBLAQAAAA==.Deathhawkzz:BAABLgAECn8WAAMXAAcJ+hXmCwAEAgAXAAcJ+hXmCwAEAgAYAAEJJARoKwEnAAAAAA==.Deathphoenix:BAAALgADCgcJBwAAAA==.Deathslock:BAAALgADCgQJBAAAAA==.Deekura:BAABLgAECn8UAAMJAAYJKgamegDsAAAJAAYJKgamegDsAAAZAAIJlQEHFQA9AAAAAA==.Deladorana:BAAALgADCgUJBQAAAA==.Dellma:BAAALgADCgYJDAAAAA==.Delusion:BAAALgAECgQJBgAAAA==.Demonpapi:BAAALgAECgEJAgAAAA==.Demoryx:BAEALgAECgQJBAABLgAECggJHwAaAIEcAA==.Denjack:BAAALgAECgQJBQAAAA==.Dewayne:BAAALgAECgUJBQAAAA==.',
Dh='Dhadzen:BAAALgAECgQJCwAAAA==.',
Di='Dionan:BAABLgAECn8lAAIGAAgJMhJ6OwCUAQAGAAgJMhJ6OwCUAQAAAA==.Dirtysouth:BAAALgAECgEJAQABLgAFFAQJCQAVAD8bAA==.',
Do='Docs:BAABLgAECn8jAAIHAAgJSBY0DwAnAgAHAAgJSBY0DwAnAgAAAA==.Doks:BAABLgAECn8pAAIBAAgJuR6tEwB3AgABAAgJuR6tEwB3AgAAAA==.Dontpanic:BAAALgAECgUJDgABLgAFFAQJCgAHAOcOAA==.Doomsnake:BAAALgADCgMJAwABLgADCgEJAQAKAAAAAA==.Dove:BAAALgADCgYJBgAAAA==.',
Dr='Dragomalfoy:BAAALgADCgQJBAAAAA==.Dragõn:BAAALgAECgQJBgAAAA==.Drexeos:BAAALgADCgcJBwAAAA==.Drinker:BAAALgADCgUJBQAAAA==.',
Ea='Ealara:BAABLgAECn8bAAIVAAcJ4Al7RABAAQAVAAcJ4Al7RABAAQAAAA==.',
Ed='Edran:BAAALgADCgcJFQAAAA==.',
Ei='Eifel:BAAALgAECgQJBAABLgAECgkJGwAGABceAA==.Eimin:BAAALgADCgYJCgAAAA==.',
El='Eldarion:BAAALgAECgMJAgAAAA==.Elfmonk:BAAALgAECgEJAQAAAA==.Ellipses:BAAALgADCgYJBgABLgAECggJDAAKAAAAAA==.',
Em='Emeraldz:BAABLgAECn8dAAIIAAcJpBnCEAC0AQAIAAcJpBnCEAC0AQAAAA==.',
En='Eneru:BAAALgADCgYJCAABLgAECggJHwAHAJ0XAA==.',
Er='Erebrethil:BAAALgAECgYJDwAAAA==.',
Es='Espe:BAABLgAECn8YAAIbAAgJPhVfEQC6AQAbAAgJPhVfEQC6AQAAAA==.',
Eu='Eucalyptia:BAAALgADCgQJBAAAAA==.',
Ev='Evenin:BAAALgADCgIJAgAAAA==.',
Ex='Exoncantotem:BAAALgADCgQJBAAAAA==.',
Fa='Faenor:BAAALgAECgMJBgAAAA==.Faynor:BAABLgAECn8lAAIbAAgJrheoDgDdAQAbAAgJrheoDgDdAQAAAA==.',
Fe='Feloni:BAAALgAECgMJAwAAAA==.',
Fi='Finalone:BAAALgADCgEJAQAAAA==.Firêfly:BAAALgAECgIJAwAAAA==.',
Fk='Fknsteve:BAAALgADCgYJBgAAAA==.',
Fl='Flaptix:BAAALgAECgMJAwAAAA==.Flipingflerp:BAAALgAECgcJEQAAAA==.Flloran:BAAALgAECgQJBgAAAA==.Floragoth:BAAALgAECgEJAQAAAA==.Flowers:BAAALgADCgkJCQAAAA==.Fluffboi:BAABLgAECn8XAAIIAAcJKQjMJgD3AAAIAAcJKQjMJgD3AAAAAA==.',
Fo='Foxyblue:BAAALgAECgYJDgAAAA==.',
Fr='Fraggle:BAACLgAFFH8KAAMHAAQJ5w4RFAARAQAHAAQJ5w4RFAARAQAGAAIJgAKXUACEAAAuAAQKfyIAAwcACAl+IBsLAMcCAAcACAl+IBsLAMcCAAYAAQkwIWXPAGIAAAAA.Freefolk:BAAALgADCgcJBwAAAA==.Freefromfate:BAAALgAECgEJAQAAAA==.Frogchi:BAAALgAECgQJBQAAAA==.Frostbité:BAABLgAECn8cAAIMAAkJ4ROoCwCDAQAMAAkJ4ROoCwCDAQAAAA==.Fruit:BAAALgAECgQJBgAAAA==.',
Fu='Fuknak:BAAALgAECgIJAwAAAA==.Fumikiko:BAAALgADCgIJAgABLgAECggJHgAFAL0eAA==.Furrykarg:BAAALgAECgEJAQABLgAECgQJBQAKAAAAAA==.',
['Fú']='Fúzzy:BAAALgADCgEJAgAAAA==.',
Ga='Gakkle:BAAALgAECgYJCQAAAA==.Galadralvia:BAAALgAECgcJEQAAAA==.Gali:BAAALgAECgUJDAAAAA==.',
Ge='Gearsofbob:BAAALgAFFAIJBAAAAA==.Gekkle:BAAALgADCgUJBQAAAA==.',
Gh='Ghorn:BAAALgAECgEJAQAAAA==.Ghoulei:BAABLgAECn8lAAIJAAgJdR+EFQBPAgAJAAgJdR+EFQBPAgAAAA==.',
Gl='Glaistiguain:BAAALgAECgYJCwABLgAECggJJQAJAC8fAA==.Glenheals:BAAALgADCgkJCQAAAA==.Glifin:BAAALgAECgQJBQAAAA==.Gloomstalkin:BAABLgAECn8oAAIcAAgJYBbyCwDlAQAcAAgJYBbyCwDlAQAAAA==.',
Gn='Gnøsis:BAAALgADCggJEQAAAA==.',
Go='Goldìelocks:BAAALgAECgQJBAAAAA==.Gom:BAAALgAECgIJAgAAAA==.Gomdrog:BAAALgADCgUJBQAAAA==.',
Gr='Gr:BAABLgAECn8jAAIdAAcJPQsKCABaAQAdAAcJPQsKCABaAQAAAA==.Grannecs:BAAALgADCgEJAQAAAA==.Grizzledpaw:BAAALgAECgMJBgAAAA==.Gryffs:BAABLgAECn8sAAMRAAgJeB1oBQBMAgARAAgJeB1oBQBMAgASAAEJ1AoXPgAyAAAAAA==.',
Gu='Gutts:BAABLgAECn8iAAQRAAgJrSK0AgCyAgARAAgJrSK0AgCyAgASAAYJsxKPFwD7AAADAAQJ0Q7nfQDFAAAAAA==.',
Ha='Haiirøkami:BAABLgAECn8fAAIGAAYJIgiClADFAAAGAAYJIgiClADFAAAAAA==.Halomea:BAAALgADCgQJBAAAAA==.Hanukira:BAAALgADCgUJBQAAAA==.Happi:BAAALgAECgYJCQABLgAFFAYJEgAOAAcXAA==.Harald:BAAALgAECgUJCgAAAA==.Harkle:BAAALgADCgcJDQAAAA==.Haruun:BAAALgAECgEJAQAAAA==.',
He='Hesmydaddy:BAABLgAECn8jAAITAAgJsgefIwAsAQATAAgJsgefIwAsAQAAAA==.',
Ho='Hongling:BAAALgADCgYJBgABLgAECggJHgAFAL0eAA==.Honêy:BAEALgADCgUJBQABLgAECggJHwAaAIEcAA==.Hotdogstand:BAACLgAFFH8OAAIQAAUJzCPYBACKAQAQAAUJzCPYBACKAQAuAAQKfykABBAACQlwJesFADIDABAACQlwJesFADIDAB0ABAmEIYELAHMBAB4AAQkrIlIPAGAAAAAA.',
Hu='Huzzaah:BAAALgAECgcJCQABLgAFFAQJCgAHAOcOAA==.',
Hy='Hyperius:BAAALgADCgIJAgAAAA==.',
['Hö']='Höneÿdew:BAABLgAECn8ZAAIVAAgJ8Bg1LAADAgAVAAgJ8Bg1LAADAgAAAA==.',
Ic='Icemann:BAAALgAECgEJAgAAAA==.',
Il='Ilidrayssel:BAABLgAECn8aAAIUAAcJbQNmEgDOAAAUAAcJbQNmEgDOAAAAAA==.Illida:BAAALgAECgMJCAAAAA==.Illidad:BAAALgAECgQJBAAAAA==.Ilyssara:BAAALgADCgYJBgABLgAECggJDAAKAAAAAA==.',
Im='Imhappy:BAAALgAECgIJAwABLgAFFAYJEgAOAAcXAA==.Imherdaddy:BAAALgADCgYJCAABLgAECggJKAAcAGAWAA==.',
In='Innervape:BAAALgADCgMJAwAAAA==.',
Ja='Jacorict:BAAALgAECgYJDwAAAA==.Jagga:BAAALgADCgMJAwAAAA==.Jarrack:BAABLgAECn8eAAICAAgJ2xZ5LADwAQACAAgJ2xZ5LADwAQAAAA==.',
Je='Jellyhawk:BAAALgAECgEJAQAAAA==.Jessicae:BAAALgAECgYJDAAAAA==.',
Jo='Josephedd:BAABLgAECn8oAAIEAAgJbRP+EwCjAQAEAAgJbRP+EwCjAQAAAA==.',
Ju='Jukk:BAAALgAECgYJDQABLgAECggJEAAKAAAAAA==.Junazeena:BAABLgAECn8XAAIaAAcJkQM4OgDEAAAaAAcJkQM4OgDEAAAAAA==.',
Ka='Kaji:BAABLgAECn8XAAIfAAYJGQ4WJQAfAQAfAAYJGQ4WJQAfAQAAAA==.Kalistus:BAAALgADCgYJBwAAAA==.Kargfu:BAAALgAECgQJBQAAAA==.Karolat:BAAALgAECgIJAQAAAA==.Kayfabe:BAABLgAECn8ZAAICAAgJ4gNn+gAGAQACAAgJ4gNn+gAGAQAAAA==.Kazz:BAAALgAECgQJBAAAAA==.',
Ke='Keishilda:BAAALgAECgQJCQAAAA==.Keladria:BAAALgAECgMJBgAAAA==.Kelirra:BAAALgADCgQJBAAAAA==.Kelvyren:BAAALgADCgEJAQAAAA==.Kenel:BAABLgAECn8gAAIPAAgJGxfoFgAOAgAPAAgJGxfoFgAOAgAAAA==.Kerea:BAABLgAECn8lAAIPAAgJMweORwD1AAAPAAgJMweORwD1AAAAAA==.',
Ki='Kicken:BAABLgAECn8aAAMYAAYJVxqwNQCOAQAYAAUJ1BmwNQCOAQAXAAMJBRYlPwC4AAAAAA==.Kitschy:BAAALgADCgEJAQAAAA==.Kittyperry:BAAALgAECgMJAwAAAA==.',
Kn='Knome:BAABLgAECn8hAAICAAgJ+h6QFwBfAgACAAgJ+h6QFwBfAgAAAA==.',
Ko='Koana:BAAALgAECgQJBwAAAA==.Kororin:BAAALgAECgMJAwAAAA==.Korthelan:BAABLgAECn8lAAIOAAgJZRC0NQBfAQAOAAgJZRC0NQBfAQAAAA==.Kothara:BAABLgAECn8dAAIVAAYJkBMuQgCnAQAVAAYJkBMuQgCnAQAAAA==.Kotongar:BAAALgADCgMJAwAAAA==.',
Kr='Kreeoo:BAAALgAECgIJAgAAAA==.Krimzin:BAACLgAFFH8JAAIVAAQJPxubDwBbAQAVAAQJPxubDwBbAQAuAAQKfx0AAxUACAnfIZQhADwCABUACAnfIZQhADwCABwAAgkaEPg3AEkAAAAA.Krystine:BAAALgAECgQJBgAAAA==.',
Ks='Kserasera:BAAALgAECgcJDwAAAA==.',
Ku='Kuball:BAAALgAECgYJCAABLgAECggJIgARAK0iAA==.Kukuruku:BAAALgAECgIJAwAAAA==.',
['Kî']='Kîllara:BAABLgAECn8mAAIBAAgJ4RVUGgDfAQABAAgJ4RVUGgDfAQAAAA==.',
La='Labialicious:BAAALgAECgEJAgAAAA==.Lanfeår:BAABLgAECn8VAAIJAAYJCwjHcwD6AAAJAAYJCwjHcwD6AAAAAA==.Lanskies:BAAALgAECggJDQAAAA==.',
Le='Leafymeds:BAAALgAECgUJCgABLgAECgkJJwABAAcTAA==.Lebronjames:BAAALgAECgQJBAAAAA==.Leiluna:BAAALgADCgkJEQAAAA==.Letheos:BAAALgAECgYJBgAAAA==.',
Li='Libertinne:BAABLgAECn8bAAIDAAgJMxeyFADGAQADAAgJMxeyFADGAQAAAA==.Librarte:BAABLgAECn8fAAIGAAgJKwzwUQBRAQAGAAgJKwzwUQBRAQAAAA==.Ligmanuts:BAAALgAECgIJBAAAAA==.Lillytrae:BAAALgADCgEJAQAAAA==.Lilmeds:BAAALgAECgEJAQABLgAECgkJJwABAAcTAA==.Listie:BAAALgADCgQJBAABLgAECgQJBAAKAAAAAA==.Litty:BAABLgAECn8aAAICAAcJcCRIGABaAgACAAcJcCRIGABaAgAAAA==.Lizrdkng:BAAALgADCgMJBgAAAA==.',
Lo='Locktärd:BAACLgAFFH8MAAQgAAQJiBuzAABYAQAgAAQJiBuzAABYAQAYAAIJShYPMwCtAAAXAAIJogZ8DgCXAAAuAAQKfygABCAACAmIH6oCAJACACAACAk+H6oCAJACABgABwkYGQ5CAAYCABcAAgkLHH5GAJwAAAAA.Lohken:BAAALgAECgMJCQAAAA==.Lox:BAABLgAECn8lAAIXAAgJBxTXBAC3AQAXAAgJBxTXBAC3AQAAAA==.',
Lu='Lucieb:BAAALgAECgEJAQAAAA==.',
Ly='Lydirn:BAABLgAECn8bAAQGAAgJ0httLADLAQAGAAcJrhxtLADLAQAHAAMJaRXDPgC7AAAMAAEJrRaNLgBAAAAAAA==.Lyofel:BAAALgAECgYJDwAAAA==.Lyonel:BAAALgADCggJCAAAAA==.',
['Lí']='Lítterbox:BAAALgAECgEJAQAAAA==.',
Ma='Magedzen:BAAALgAECgEJAQAAAA==.Magicguy:BAAALgAECgYJEwAAAA==.Mahariel:BAAALgAECggJDQAAAA==.Mahdy:BAABLgAECn8vAAIGAAgJxxuUGAA2AgAGAAgJxxuUGAA2AgAAAA==.Maivel:BAAALgAECgEJAQAAAA==.Mandret:BAAALgAECgMJBAAAAA==.Manicppanic:BAABLgAECn8UAAIQAAgJRhKMDgC6AQAQAAgJRhKMDgC6AQABLgAFFAQJCgAHAOcOAA==.Manrypurp:BAAALgAECgUJDQAAAA==.Marcie:BAABLgAECn8hAAIEAAgJIwsUHQBMAQAEAAgJIwsUHQBMAQAAAA==.',
Mc='Mchammer:BAAALgADCgUJBgAAAA==.',
Me='Meatyloaf:BAAALgAECgYJDAAAAA==.Melkedrik:BAAALgAECgYJDAAAAA==.Melleren:BAAALgAECgEJAQAAAA==.Messande:BAAALgAECgUJBgAAAA==.',
Mi='Minõs:BAAALgADCgkJEAAAAA==.Mirai:BAAALgADCgUJBQAAAA==.Mirei:BAABLgAECn8aAAITAAYJbwfkKwDuAAATAAYJbwfkKwDuAAAAAA==.Mistdancer:BAAALgADCgYJBgABLgAECggJEQAKAAAAAA==.Mitsurugi:BAAALgADCgQJAwABLgAECggJEQAKAAAAAA==.Miyagí:BAAALgAECgcJDgABLgAECggJGAAWAKUdAA==.',
Mo='Mojam:BAAALgAECgQJBgAAAA==.Monk:BAAALgAECgEJAQAAAA==.Moonless:BAAALgAECgEJAgAAAA==.Moovidlin:BAAALgAECggJEAAAAA==.Mordian:BAAALgAECgYJBgAAAA==.Morinnas:BAAALgADCgkJDAAAAA==.Moschpit:BAAALgADCgEJAQAAAA==.',
Mu='Munkeez:BAAALgADCgMJAwAAAA==.Murdermoo:BAAALgADCgMJAwAAAA==.Murkessa:BAAALgAECgQJBQAAAA==.Mushhead:BAAALgAECgUJCAAAAA==.',
My='Myishaa:BAAALgADCgIJAgAAAA==.Mykeal:BAAALgADCgMJBQAAAA==.Mystryl:BAAALgADCgYJBgAAAA==.',
['Mì']='Mìstra:BAAALgADCgUJBwAAAA==.',
Na='Nargo:BAAALgADCgYJCgAAAA==.Nataliia:BAAALgAECgQJBAAAAA==.',
Ne='Necrostalker:BAAALgADCgkJCQABLgADCgEJAQAKAAAAAA==.Negative:BAAALgAECgQJBQAAAA==.Nerwende:BAAALgAECgEJAQAAAA==.Nethershade:BAABLgAECn8aAAIdAAYJ2hYeBwBzAQAdAAYJ2hYeBwBzAQAAAA==.Netherstörm:BAAALgADCgkJJAAAAA==.Netzach:BAAALgAECgkJDQAAAA==.',
Ni='Niclea:BAAALgAECgQJBAAAAA==.Nightelm:BAABLgAECn8eAAQFAAgJvR7uGwDpAQAFAAgJth7uGwDpAQAhAAUJcAwRNADNAAAiAAMJ+h3MKgDHAAAAAA==.Niënor:BAAALgADCgYJBgABLgAECgYJDwAKAAAAAA==.',
Nj='Njorvir:BAAALgAECgEJAQAAAA==.',
No='Noslien:BAAALgAECgUJBwAAAA==.Nostradamuz:BAAALgAECgEJAQAAAA==.Novasong:BAAALgAECgEJAwAAAA==.',
Ny='Nyxstonia:BAACLgAFFH8GAAIRAAIJvhrgEQCfAAARAAIJvhrgEQCfAAAuAAQKfywAAhEACQm3GnoFAEoCABEACQm3GnoFAEoCAAAA.',
Ob='Oballi:BAAALgAECgUJBgAAAA==.',
Od='Oddsaint:BAAALgAECgEJAgAAAA==.',
Ol='Olierra:BAAALgAECgYJDAAAAA==.',
On='Onlyvoids:BAAALgAECgMJAwAAAA==.',
Or='Ornac:BAAALgADCgYJBgAAAA==.',
Ot='Otkspring:BAABLgAECn8UAAIDAAcJJhOcGwCLAQADAAcJJhOcGwCLAQAAAA==.Otto:BAABLgAECn8jAAIGAAgJyBI6MgC0AQAGAAgJyBI6MgC0AQAAAA==.',
Ox='Oxadin:BAAALgAECgEJAQAAAA==.Oxideous:BAAALgADCgMJAwAAAA==.',
Pa='Paleale:BAAALgAECgYJEAAAAA==.Pallyshore:BAAALgADCgMJAwAAAA==.Pampoovy:BAEALgADCgMJAwABLgAECgUJCQAKAAAAAA==.Pantoponrose:BAAALgAECgMJAwAAAA==.Pastorbash:BAAALgADCggJCQAAAA==.',
Pb='Pb:BAAALgAECgMJAwAAAA==.',
Pe='Persephoneia:BAABLgAECn8eAAINAAgJZg5CFgCOAQANAAgJZg5CFgCOAQAAAA==.',
Ph='Phukimded:BAAALgAECggJDAAAAA==.',
Pk='Pkashmuk:BAAALgADCgcJBwAAAA==.',
Pr='Prophettool:BAABLgAECn8WAAMGAAgJEQnPqgAsAQAGAAgJEQnPqgAsAQAHAAQJigT/fACGAAAAAA==.Pruned:BAAALgADCgcJBwABLgAFFAQJDAAgAIgbAA==.',
Qu='Quanchii:BAAALgADCgMJAwAAAA==.',
Ra='Raemie:BAAALgAECgQJBwAAAA==.Ragequit:BAAALgAECggJDwABLgAECggJDAAKAAAAAA==.Raikoho:BAAALgAECgEJAQABLgAECgEJAQAKAAAAAA==.Rakulm:BAAALgADCgUJCgAAAA==.Ravenrest:BAEBLgAECn8nAAINAAgJ/ByBCABAAgANAAgJ/ByBCABAAgAAAA==.',
Re='Reaverhiem:BAAALgAECgQJDgAAAA==.Reiko:BAAALgADCgkJIQABLgAECgYJGgATAG8HAA==.Remuz:BAAALgAECgMJBgAAAA==.Rennwick:BAAALgAECgQJBgAAAA==.',
Rh='Rhe:BAAALgAECgEJAQABLgAECgUJBQAKAAAAAA==.',
Ri='Rilz:BAABLgAECn8lAAIJAAgJlR1FFwBBAgAJAAgJlR1FFwBBAgAAAA==.',
Ro='Rochambeu:BAAALgADCgEJAQAAAA==.Rodgerwabbet:BAAALgAECgQJBAAAAA==.Roiddemon:BAAALgADCgQJBAABLgAECggJKgAYABcUAA==.Roiddrood:BAAALgAECgIJAgABLgAECggJKgAYABcUAA==.Roidlock:BAABLgAECn8qAAIYAAgJFxRDJQDVAQAYAAgJFxRDJQDVAQAAAA==.Roidtank:BAAALgAECgUJDAABLgAECggJKgAYABcUAA==.Rosaline:BAAALgAECgQJCAAAAA==.Rottn:BAAALgAECgYJBgABLgAECggJDAAKAAAAAA==.',
Ru='Runerion:BAAALgAECgEJAgAAAA==.',
Ry='Ry:BAAALgAECgUJBQAAAA==.',
['Rà']='Ràìn:BAABLgAECn8WAAICAAgJAgkdWgBgAQACAAgJAgkdWgBgAQAAAA==.',
Sa='Safmen:BAABLgAECn8bAAQRAAYJwQeyHgDHAAARAAYJjAeyHgDHAAASAAMJMgXYMABdAAADAAEJCArsogA9AAAAAA==.Sanikoa:BAAALgADCgEJAQAAAA==.Saraid:BAABLgAECn8oAAQPAAgJNxtEDgBtAgAPAAgJNxtEDgBtAgAEAAMJZxAPYQCdAAAjAAEJOAYdMQAVAAAAAA==.Saravase:BAAALgAECgQJDAAAAA==.Sardel:BAAALgADCgcJBwAAAA==.Sargeros:BAAALgAECgQJBQAAAA==.Sazem:BAAALgADCgIJAgAAAA==.',
Se='Sedaldra:BAAALgADCgYJCwAAAA==.',
Sh='Shadownights:BAABLgAECn8hAAINAAcJ2g8YIQA2AQANAAcJ2g8YIQA2AQAAAA==.Shamoneyy:BAAALgADCgUJBQAAAA==.Shiki:BAAALgADCgkJCQABLgAECgYJGgATAG8HAA==.Shimnar:BAAALgAECgcJDgABLgAECggJGwADADMXAA==.Shinifur:BAAALgADCgUJBgAAAA==.Shinoto:BAAALgAECgQJBgAAAA==.Shockazam:BAAALgAECgcJEgAAAA==.Shrewby:BAAALgAECgEJAQAAAA==.Shyandra:BAAALgADCgYJBgAAAA==.',
Si='Sieghart:BAAALgAECgEJAQAAAA==.Six:BAAALgAECgUJCwAAAA==.',
Sk='Skylines:BAAALgAECgQJBAAAAA==.',
Sl='Sloptop:BAAALgAECgEJAgAAAA==.',
Sn='Snickersbar:BAAALgADCgUJCAAAAA==.Snowynn:BAAALgAECgQJBQAAAA==.Snöw:BAABLgAECn8ZAAICAAcJlg7raQA9AQACAAcJlg7raQA9AQAAAA==.Snöwy:BAAALgAECgQJBAAAAA==.',
So='Southpaw:BAAALgAECgMJAwAAAA==.',
Sp='Spooki:BAAALgAECgEJAQAAAA==.Spyro:BAABLgAECn8fAAQFAAkJ4gx2GgD2AQAFAAkJ4gx2GgD2AQAhAAgJwwtDIwBfAQAiAAIJpgnNNgBgAAAAAA==.',
Sr='Sron:BAABLgAECn8lAAIVAAgJzh0JFQAnAgAVAAgJzh0JFQAnAgAAAA==.',
St='Stariah:BAABLgAECn8aAAICAAgJVQogtQB1AQACAAgJVQogtQB1AQAAAA==.Stawn:BAAALgADCgEJAQAAAA==.',
Su='Sumwhiteguy:BAAALgADCgkJCQAAAA==.',
Sw='Swooze:BAABLgAECn8tAAICAAkJmRspEgCHAgACAAkJmRspEgCHAgAAAA==.',
Sy='Sylrythriana:BAAALgAECgIJAgAAAA==.Syndicate:BAAALgAECgYJBgAAAA==.Syrenis:BAAALgADCgkJDwABLgAECggJHgAFAL0eAA==.',
['Sù']='Sùnnydk:BAAALgADCgcJBwAAAA==.',
Ta='Talwaz:BAAALgADCgkJDgAAAA==.Tankinbur:BAAALgAECgMJBgAAAA==.Tarlyn:BAABLgAECn8vAAQHAAgJrxcDEgAIAgAHAAgJrxcDEgAIAgAGAAYJkxMOWQA/AQAMAAEJAADPPwA+AAAAAA==.Tatslight:BAABLgAECn8cAAIMAAYJmxr8DABqAQAMAAYJmxr8DABqAQABLgAECgYJHAAMAJsaAA==.Tatsrage:BAAALgADCgYJBgABLgAECgYJHAAMAJsaAA==.Tazaral:BAAALgADCgEJAQABLgAECgQJBwAKAAAAAA==.',
Te='Teysá:BAAALgADCgEJAQAAAA==.',
Th='Thor:BAAALgAECgYJCAAAAA==.Thyandris:BAAALgADCgYJCwAAAA==.Thánátós:BAAALgAECgMJAwAAAA==.',
Ti='Timmthemage:BAAALgAECgUJBwABLgAECgcJBwAKAAAAAQ==.Timthepally:BAAALgAECgcJBwAAAQ==.Tinytex:BAAALgAECgYJEwAAAA==.Tisiphoneia:BAAALgAECgQJBgAAAA==.',
To='Toberson:BAAALgAECgEJAQAAAA==.Toxicbanana:BAAALgAECgYJCwAAAA==.',
Tr='Tradarynn:BAAALgAECgcJEAAAAA==.Tralls:BAEBLgAECn8fAAMaAAgJgRz/CQA5AgAaAAgJgRz/CQA5AgAkAAEJ8AozLAA1AAABLgAECggJHwAaAIEcAA==.Trayvein:BAAALgADCgUJBQAAAA==.Trekk:BAAALgAECgcJBQAAAA==.Tress:BAAALgAECgQJCAAAAA==.',
Ts='Tsindre:BAAALgAECgEJAgAAAA==.',
Tu='Tulkar:BAAALgAECgEJAQAAAA==.Turambar:BAAALgADCgEJAQAAAA==.',
Un='Unholymochi:BAABLgAECn8cAAIJAAcJ0x6IXQDaAQAJAAcJ0x6IXQDaAQAAAA==.',
Va='Valhalia:BAAALgAECgcJEgAAAA==.Vanyllapea:BAAALgAECgMJAwAAAA==.Varaelitha:BAAALgAECgMJAwAAAA==.Vashan:BAAALgAECgQJBQAAAA==.Vashni:BAAALgAECgkJDAAAAA==.',
Ve='Velinariae:BAAALgADCgYJEAAAAA==.Vengful:BAABLgAECn8WAAMlAAYJcBxcHQDVAQAlAAYJcBxcHQDVAQAmAAIJoBe8FACDAAAAAA==.',
Vi='Vira:BAAALgAECgIJAgAAAA==.Vivy:BAABLgAECn8fAAQYAAkJNhTbLwBNAgAYAAkJzRPbLwBNAgAXAAQJaxSZMwDpAAAgAAIJBhXKJgBWAAAAAA==.',
Vo='Vorumbrae:BAAALgAECgMJBQAAAA==.',
Vu='Vultus:BAAALgAECgIJAgAAAA==.',
['Vä']='Väntage:BAAALgADCgEJAQAAAA==.',
Wa='Wagyubeef:BAABLgAECn8fAAIDAAgJ3hfFDwD5AQADAAgJ3hfFDwD5AQAAAA==.Wali:BAABLgAECn8eAAMYAAgJMBMjKwC4AQAYAAgJMBMjKwC4AQAXAAEJAABydgAuAAAAAA==.Warlodzen:BAAALgADCgcJBwAAAA==.',
We='Wenson:BAAALgAECgEJAQAAAA==.',
Wh='Whatupbruh:BAACLgAFFH8LAAMVAAQJBBGrKAD3AAAVAAMJRxCrKAD3AAAcAAMJ6hARBAC0AAAuAAQKfyQABBwABwkcIgQHAIgCABwABwm5IQQHAIgCABUAAQkJG+KiAE4AABQAAQndBm6SACgAAAAA.',
Wi='Wildfire:BAAALgADCgUJBQAAAA==.',
Wy='Wyleriya:BAABLgAECn8gAAIYAAgJHQfHSwBGAQAYAAgJHQfHSwBGAQAAAA==.',
Xa='Xanthas:BAAALgADCgQJBAAAAA==.',
Xc='Xcella:BAAALgAECgQJBwAAAA==.',
Xe='Xephon:BAAALgADCgcJBwAAAA==.',
Ye='Yelizaveta:BAAALgAECgEJAQAAAA==.',
Yl='Ylfcwen:BAAALgAECgEJAQAAAA==.',
Yo='Yodey:BAABLgAECn8WAAIJAAkJER0fEwBiAgAJAAkJER0fEwBiAgAAAA==.Yoovee:BAAALgADCgEJAQAAAA==.',
Yu='Yuaetrende:BAACLgAFFH8FAAIlAAIJsRWDDQCoAAAlAAIJsRWDDQCoAAAuAAQKfyUAAiUACAmrIqECAMgCACUACAmrIqECAMgCAAAA.Yumii:BAABLgAECn8fAAMTAAgJfyV9AQBPAwATAAgJTSV9AQBPAwAnAAYJ/yHyDgBNAgAAAA==.',
Za='Zack:BAAALgAECgYJDQAAAA==.Zaerie:BAAALgADCgcJBwAAAA==.Zagul:BAAALgAECgUJCAAAAA==.Zalarah:BAAALgAECgQJBwAAAA==.Zalarilia:BAAALgAECgEJAQAAAA==.Zanoo:BAAALgADCgYJBwAAAA==.Zaphod:BAAALgAECgMJAwAAAA==.Zardan:BAABLgAECn8WAAIYAAgJdQcAXAAbAQAYAAgJdQcAXAAbAQAAAA==.',
Zi='Ziegler:BAAALgADCgYJBgAAAA==.',
Zo='Zorrita:BAAALgAECgEJAQAAAA==.',
Zu='Zugglite:BAABLgAECn8lAAMHAAgJMCEyFwBYAgAHAAgJMCEyFwBYAgAMAAQJ2xpYEAA1AQAAAA==.Zulthar:BAABLgAECn8aAAICAAgJ8QpuYQBPAQACAAgJ8QpuYQBPAQAAAA==.',
['Äs']='Äshborn:BAABLgAECn8cAAIJAAgJVQ46OgCRAQAJAAgJVQ46OgCRAQAAAA==.Ästra:BAAALgADCggJCAAAAA==.',
['Æl']='Ælxx:BAEALgAECgYJBwABLgAFFAMJBgACALkHAA==.',
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

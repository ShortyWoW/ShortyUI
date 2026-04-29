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

local lookup = {'Druid-Balance','Druid-Restoration','Evoker-Augmentation','Unknown-Unknown','Shaman-Restoration','Warlock-Demonology','Warlock-Destruction','Warrior-Arms','DeathKnight-Blood','Monk-Brewmaster','Druid-Guardian','Priest-Shadow','Warrior-Fury','Monk-Mistweaver','Monk-Windwalker','Paladin-Retribution','Evoker-Preservation','Evoker-Devastation','Hunter-BeastMastery','DemonHunter-Devourer','DemonHunter-Havoc','DeathKnight-Unholy','Priest-Holy','Priest-Discipline','Shaman-Elemental','Druid-Feral','Hunter-Marksmanship','Rogue-Assassination','Shaman-Enhancement','Paladin-Holy','Rogue-Subtlety','DemonHunter-Vengeance','Mage-Frost','Warrior-Protection','Mage-Arcane',}
local provider = {region='US',realm='Bladefist',name='US',type='weekly',zone=46,date='2026-04-24',data={Ad='Adrianmonk:BAAALgAECgYJEgAAAA==.',
Ae='Aezu:BAACLgAFFH8OAAMBAAQJixWHEgCvAAABAAMJ8BSHEgCvAAACAAIJBxHLIgBQAAAuAAQKfykAAwEACQmXI5EQAJsCAAEACAmGJJEQAJsCAAIABwlIHkwjAC8CAAAA.',
Ai='Ailuria:BAAALgAECgYJEgAAAA==.Airam:BAAALgADCgkJCQAAAA==.Aitharen:BAAALgADCgUJBAAAAA==.',
Al='Alaura:BAAALgADCgQJBAAAAA==.Albaz:BAABLgAECn8UAAIDAAgJzA1HIwCjAQADAAgJzA1HIwCjAQAAAA==.Alepacino:BAAALgAECgEJAgABLgAECgEJAgAEAAAAAA==.Alikith:BAAALgAECgYJEgAAAA==.Alun:BAAALgADCgYJBgAAAA==.Alynia:BAAALgAECgEJAQAAAA==.',
Am='Ambrìel:BAAALgAECgYJEgAAAA==.Amyloid:BAAALgADCgEJAQAAAA==.Amèlia:BAACLgAFFH8FAAMBAAIJwgG8FwB5AAABAAIJwgG8FwB5AAACAAIJEAO2DgBuAAAuAAQKfx8AAgIACAnSGZgHAOwBAAIACAnSGZgHAOwBAAAA.',
An='Angando:BAAALgAECgYJCwAAAA==.Anjelik:BAAALgADCgYJBgAAAA==.Anneliesë:BAAALgADCgUJDwAAAA==.',
Ao='Aozora:BAAALgAECgYJCgAAAA==.',
Ar='Aric:BAAALgADCgQJBAAAAA==.Arrows:BAAALgADCgcJBwAAAA==.Artemidoros:BAAALgAECgYJEwAAAA==.',
As='Ashkaari:BAABLgAFFH8FAAIFAAIJmBEqGQCXAAAFAAIJmBEqGQCXAAAAAA==.Asuná:BAAALgAECgcJEAAAAA==.',
Au='Aurelyus:BAAALgAECgMJAwAAAA==.Aurevior:BAAALgAECgYJBwAAAA==.',
Az='Azariyah:BAAALgADCgQJBAAAAA==.Azooma:BAAALgADCgkJEAAAAA==.Azshaure:BAAALgAECgQJBwAAAA==.Azu:BAAALgAECgEJAQABLgAFFAQJDgABAIsVAA==.',
Ba='Backerrz:BAACLgAFFH8LAAIGAAQJUwkgHgALAQAGAAQJUwkgHgALAQAuAAQKfykAAwYACQnqGzkXAMkCAAYACQnqGzkXAMkCAAcAAwlAGS85ANAAAAAA.',
Be='Bearwidit:BAAALgAECgMJBAAAAA==.Beefbrownie:BAAALgAECgUJDwAAAA==.Berz:BAAALgAECgUJBQAAAA==.Berzerked:BAABLgAECn8eAAIIAAgJ+yGrAQAnAwAIAAgJ+yGrAQAnAwAAAA==.',
Bi='Bigbubhaa:BAAALgAECgEJAQAAAA==.Bigfluffbutt:BAAALgAECgUJCQAAAA==.Bigsave:BAAALgAECgYJCwAAAA==.Bing:BAAALgAECgUJCAAAAA==.Bitterdawn:BAAALgADCgkJCwAAAA==.',
Bl='Blooddruids:BAAALgAECgEJAQAAAA==.Bloodymàry:BAAALgADCgUJBQAAAA==.Bloodynutz:BAACLgAFFH8HAAIJAAMJeA3rCwC5AAAJAAMJeA3rCwC5AAAuAAQKfygAAgkACAnNH68HAK4CAAkACAnNH68HAK4CAAAA.Bluethelock:BAAALgAECgUJCAAAAA==.',
Bo='Boogity:BAAALgADCgUJCAAAAA==.',
Br='Branel:BAAALgADCgMJAwAAAA==.Brejevol:BAAALgAECgYJDgAAAA==.Brewslee:BAAALgAECgMJAwAAAA==.Brodyty:BAAALgAECgYJCAAAAA==.Brosiedon:BAAALgAECgMJAwAAAA==.',
Bu='Buckett:BAAALgADCgYJDAAAAA==.Buffalotrace:BAAALgAECgMJCAAAAA==.Bus:BAACLgAFFH8TAAIKAAYJQiVLAACAAgAKAAYJQiVLAACAAgAuAAQKfxcAAgoACQlfJnoAANkDAAoACQlfJnoAANkDAAEuAAUUBwkIAAsAQR8A.Bushrod:BAAALgADCgEJAQAAAA==.',
Ce='Celtykun:BAAALgAECgQJBAAAAA==.',
Ch='Chelseyb:BAAALgADCgcJBwAAAA==.Chiron:BAAALgADCgEJAQABLgAECgYJBwAEAAAAAA==.Chirón:BAAALgADCgYJBgAAAA==.Chiyukii:BAAALgAECgEJAQAAAA==.',
Ci='Cirillo:BAAALgAECgcJEQAAAA==.',
Co='Colorss:BAAALgADCgEJAQAAAA==.Connie:BAAALgAECgYJDgAAAA==.Cowmein:BAAALgAECgQJBgAAAA==.',
Cr='Cream:BAAALgAECgUJBAAAAA==.Credence:BAAALgADCgIJAgAAAA==.Crystalmommy:BAAALgADCgEJAQAAAA==.',
Cu='Culillo:BAAALgAECgYJBgAAAA==.Cusn:BAAALgADCgEJAQAAAA==.',
Cy='Cynfulsqt:BAAALgADCgUJCAABLgAFFAQJDQAMAGEWAA==.',
Da='Dapur:BAAALgADCgkJEgAAAA==.Dayne:BAAALgAECgUJBQABLgAECgYJDgAEAAAAAA==.',
Dc='Dced:BAAALgADCgUJCgABLgAECgQJBAAEAAAAAA==.',
De='Demontot:BAAALgADCgkJCgAAAA==.',
Di='Dillexis:BAACLgAFFH8FAAINAAIJYBVeCAC+AAANAAIJYBVeCAC+AAAuAAQKfx8AAg0ACAlHG/wDAAICAA0ACAlHG/wDAAICAAAA.Dipindots:BAAALgADCgEJAQAAAA==.',
Do='Donald:BAABLgAECn8cAAMBAAcJIRINCwA9AQABAAcJIRINCwA9AQACAAMJiwc0pwB5AAAAAA==.Doublea:BAAALgAECgYJCwAAAA==.',
Dr='Dragonchest:BAAALgADCgQJBAAAAA==.Dragonswolf:BAABLgAECn8UAAINAAgJog1hMwDdAQANAAgJog1hMwDdAQAAAA==.Drakeconis:BAAALgADCgUJBQAAAA==.Draksil:BAAALgADCgYJBwAAAA==.Draygon:BAAALgADCgEJAQABLgAFFAQJDgAOACwlAA==.Dregon:BAACLgAFFH8OAAIOAAQJLCWSAwC4AQAOAAQJLCWSAwC4AQAuAAQKfygAAw4ACQkyJl4CAGgDAA4ACQkyJl4CAGgDAA8AAgnlIZhaAKUAAAAA.Dreinara:BAAALgAECgMJAwAAAA==.Dresserdemon:BAAALgADCgcJBwAAAA==.Druthenew:BAAALgADCgUJDwAAAA==.',
Du='Dummysezwhut:BAAALgAECgQJBAAAAA==.',
Ei='Eilyn:BAABLgAECn8VAAIQAAYJCA99lQBSAQAQAAYJCA99lQBSAQAAAA==.',
El='Ellida:BAABLgAECn8aAAIMAAcJMxGHIwC7AQAMAAcJMxGHIwC7AQAAAA==.',
Em='Emastoned:BAAALgADCgcJDQAAAA==.',
Er='Erdran:BAAALgADCgEJAQAAAA==.',
Es='Esterna:BAAALgAECgEJAQAAAA==.',
Et='Ettal:BAAALgAECgYJDgAAAA==.',
Fa='Fangmage:BAAALgAECgYJBwAAAA==.Fazlain:BAAALgAECgYJCgAAAA==.',
Fe='Felestis:BAAALgAECgQJBAAAAA==.Felnir:BAAALgADCggJCwABLgAECgYJBwAEAAAAAA==.',
Fl='Fluffydragon:BAABLgAECn8iAAMRAAgJaho0AQBjAgARAAgJaho0AQBjAgASAAUJ5wdaKADdAAAAAA==.',
Fr='Friartuck:BAAALgAECgEJAQABLgAECggJHAATABsfAA==.Fruit:BAAALgAECgIJAgAAAA==.',
Fu='Furrydeath:BAAALgADCgYJBgAAAA==.Furryem:BAAALgAECgUJDwAAAA==.',
Fy='Fyntos:BAAALgADCgEJAgAAAA==.',
Ga='Galaena:BAAALgAECgcJAwAAAA==.Ganden:BAABLgAECn8WAAIBAAYJvBONDAAlAQABAAYJvBONDAAlAQAAAA==.Garblebeast:BAAALgADCgUJBQAAAA==.Gatelina:BAABLgAECn8YAAIQAAgJGxR6SwAAAgAQAAgJGxR6SwAAAgAAAA==.Gatelinka:BAAALgAECgMJAwABLgAECggJIgARAGoaAA==.Gateto:BAABLgAECn8WAAIFAAgJniDpCQDaAgAFAAgJniDpCQDaAgABLgAECggJIgARAGoaAA==.',
Ge='Genfindel:BAAALgADCgYJBgAAAA==.',
Gi='Gidden:BAAALgAECgUJBQAAAA==.Gidgei:BAAALgAECgQJBQAAAA==.',
Go='Gotyamind:BAAALgAECgIJAgAAAA==.Gouken:BAAALgAECgEJAQAAAA==.',
Gr='Grampybobat:BAAALgAECgQJBgAAAA==.Grampycatbob:BAAALgADCgYJBgAAAA==.',
Gw='Gwenneth:BAAALgAECgMJAwAAAA==.',
['Gú']='Gúr:BAAALgADCgkJEgAAAA==.',
Ha='Halfordin:BAAALgADCgUJBQAAAA==.Hamiepally:BAAALgADCgYJBwAAAA==.Harok:BAAALgADCgUJBQAAAA==.Hartley:BAAALgADCgUJCAAAAA==.',
He='Helkalach:BAAALgAECgEJAQAAAA==.Hellravage:BAABLgAECn8UAAIHAAYJIROkAwAwAQAHAAYJIROkAwAwAQAAAA==.',
Ho='Holeshot:BAAALgADCgYJBgAAAA==.',
Hr='Hruoth:BAAALgADCgIJAgAAAA==.',
Hu='Hunt:BAAALgAECgYJEQAAAA==.Huntinbub:BAAALgAECgYJEgAAAA==.',
['Hó']='Hólyñuts:BAAALgAECgEJAQAAAA==.',
Ic='Icatanktard:BAAALgADCgMJAwAAAA==.',
Im='Implord:BAAALgAECgcJAwAAAA==.',
Is='Ishun:BAAALgAECgMJAwAAAA==.',
Iv='Ivon:BAAALgADCgkJIQABLgAFFAIJBQANAGAVAA==.',
Iw='Iwaxmygoat:BAAALgADCgMJAwABLgAECgQJBAAEAAAAAA==.',
Iz='Izanagì:BAACLgAFFH8IAAIUAAQJsA4BHwDfAAAUAAQJsA4BHwDfAAAuAAQKfyQAAxQACQlPHtkRAPACABQACQlPHtkRAPACABUAAglECPphAFoAAAAA.Izlaar:BAAALgADCgkJDQAAAA==.Izzytt:BAAALgAECgQJBAAAAA==.',
Ja='Jacenskie:BAABLgAECn8aAAINAAgJ7xAsMwDeAQANAAgJ7xAsMwDeAQAAAA==.Jacob:BAAALgAECgQJBwAAAA==.Jadedbabe:BAAALgADCgkJCgAAAA==.Jaderoks:BAAALgAECgUJEgAAAA==.Janthis:BAAALgADCgUJBgAAAA==.',
Je='Jermaxus:BAAALgADCgEJAQAAAA==.',
Ji='Jimmyjams:BAAALgADCgEJAQABLgAECgQJBAAEAAAAAA==.',
Jn='Jneut:BAAALgADCgEJAQAAAA==.',
Jo='Joyvimon:BAAALgAECgMJAwAAAA==.',
Ju='Jugernaut:BAAALgADCgYJDQAAAA==.',
Ka='Kamala:BAAALgAECgEJAQAAAA==.Kaniicus:BAAALgADCgMJBQAAAA==.Karavin:BAABLgAECn8XAAIWAAgJwgngLQDRAAAWAAgJwgngLQDRAAAAAA==.Kayyta:BAAALgADCgYJBgAAAA==.',
Ke='Keirybear:BAAALgADCgcJCgABLgAECgYJEgAEAAAAAA==.',
Kh='Khal:BAACLgAFFH8PAAMDAAYJ5RVJAQCxAQADAAYJ5RVJAQCxAQASAAIJEgehBgClAAAuAAQKfxUAAxIACQkBILYOAO8BAAMABwmCGu8XABMCABIABgnGI7YOAO8BAAAA.',
Ki='Kickstarter:BAAALgAECgQJBAAAAA==.Kikuarse:BAAALgAECgUJBQAAAA==.Kiy:BAAALgADCgcJCwAAAA==.',
Kn='Knìghtmare:BAAALgADCgcJEwAAAA==.',
Ko='Kobal:BAAALgAECgQJBAAAAA==.',
Kr='Krakenlock:BAAALgAECgUJDAAAAA==.Kronas:BAAALgAECgMJAwAAAA==.',
Ku='Kurosaki:BAABLgAECn8aAAIUAAcJKx7bBgAJAgAUAAcJKx7bBgAJAgAAAA==.',
La='Lazyheal:BAACLgAFFH8FAAIXAAIJLBSqDACZAAAXAAIJLBSqDACZAAAuAAQKfx0ABBcABwkxHuUBAGYCABcABwkxHuUBAGYCABgABAlUBq4/ALEAAAwAAgkgBiBYAF0AAAAA.Lazytank:BAAALgAECgMJBQABLgAFFAIJBQAXACwUAA==.',
Le='Legacy:BAAALgADCgEJAgAAAA==.Leigor:BAACLgAFFH8OAAIXAAQJWBOlBAA8AQAXAAQJWBOlBAA8AQAuAAQKfykAAhcACQnbIKYDAB8DABcACQnbIKYDAB8DAAAA.Leomoon:BAAALgAECgIJAgAAAA==.Levite:BAAALgAECgQJBAAAAA==.',
Li='Lilara:BAAALgAECgYJCgAAAA==.Lionknite:BAABLgAECn8YAAIWAAgJGxV1UgD6AQAWAAgJGxV1UgD6AQAAAA==.Liontabu:BAAALgAECgIJAgAAAA==.',
Lo='Looting:BAAALgAECgUJCwAAAA==.',
Lu='Lustdeez:BAAALgADCgYJCQAAAA==.',
['Lã']='Lãdyrift:BAABLgAECn8bAAICAAgJGAsDXQA7AQACAAgJGAsDXQA7AQAAAA==.',
Ma='Mageko:BAAALgAECgEJBAAAAA==.Magetot:BAAALgADCgEJAQABLgADCgkJCgAEAAAAAA==.Makarion:BAAALgAECgYJCgAAAA==.Malvina:BAAALgAECgEJAQAAAA==.Maoli:BAAALgAECgQJCAAAAA==.Marohen:BAAALgADCgYJBgAAAA==.Mauka:BAAALgAECgYJDwAAAA==.Mauzer:BAAALgADCgUJBQABLgAECgYJEQAEAAAAAA==.',
Mc='Mcksquizy:BAABLgAECn8dAAIWAAgJlxwRMAB3AgAWAAgJlxwRMAB3AgAAAA==.',
Me='Mes:BAABLgAECn8cAAIZAAgJ6ht4FQBwAgAZAAgJ6ht4FQBwAgAAAA==.',
Mi='Mimmi:BAAALgAECgQJCQABLgAECgYJEQAEAAAAAA==.Mishri:BAABLgAECn8hAAIUAAgJPyS7AQCxAgAUAAgJPyS7AQCxAgAAAA==.',
Mo='Moonsorrow:BAAALgADCgMJAwAAAA==.Moparcast:BAAALgADCgEJAQABLgADCgUJBQAEAAAAAA==.Moriphael:BAAALgADCgcJCQAAAA==.Moritura:BAAALgAECgYJEQAAAA==.',
My='Mykana:BAAALgAECgYJDQAAAA==.',
Na='Nakabeam:BAABLgAECn8dAAIUAAgJOg8QXQCKAQAUAAgJOg8QXQCKAQAAAA==.Nakatwin:BAAALgAECgkJEgABLgAECgkJHQAUADoPAA==.Naklek:BAABLgAECn8dAAMaAAgJBB6TBgCOAgAaAAgJBB6TBgCOAgALAAEJYgtbNAAkAAAAAA==.Navic:BAAALgAECgEJAQAAAA==.',
Ne='Newtt:BAAALgADCgUJBgABLgADCgcJCQAEAAAAAA==.',
Ni='Nicked:BAECLgAFFH8FAAITAAMJaA+EDQDwAAATAAMJaA+EDQDwAAAuAAQKfyMAAxMACQmMH54OAMYCABMACQmMH54OAMYCABsABAl0BkVpAJkAAAAA.Niraleth:BAAALgADCgcJEQAAAA==.Nistik:BAAALgAECgYJEwAAAA==.',
No='Nozomí:BAAALgAECgEJAQAAAA==.',
Ob='Obergefel:BAAALgADCgEJAQAAAA==.',
Op='Ophiuchus:BAAALgAECgYJBwAAAA==.',
Oz='Ozymandias:BAAALgADCgEJAQAAAA==.',
Pa='Paldente:BAAALgAECgYJBwAAAA==.Pamelina:BAAALgADCgUJDwAAAA==.Panzerfäust:BAAALgAECgQJBwAAAA==.Pawrina:BAAALgAECgkJEQAAAA==.',
Pe='Pernicious:BAAALgAECgQJBAAAAA==.Peskadote:BAAALgADCgMJAwAAAA==.Pestis:BAAALgADCgkJDwAAAA==.',
Ph='Phaoe:BAAALgADCgUJBQAAAA==.Phillis:BAAALgAECgYJDwAAAA==.',
Pi='Pilfering:BAAALgADCgQJBAAAAA==.',
Pl='Plumpt:BAAALgAECgYJEAAAAA==.',
Pr='Prey:BAAALgADCgYJBgAAAA==.',
Pu='Pulchritude:BAAALgAECgYJBgAAAA==.Purex:BAABLgAECn8bAAIcAAgJnAUyCgCSAQAcAAgJnAUyCgCSAQAAAA==.',
Py='Pylonshots:BAAALgAECgEJAQAAAA==.',
Ra='Raivah:BAAALgADCgMJAwAAAA==.Randomyzed:BAAALgAECgYJDAAAAA==.Rathus:BAABLgAECn8XAAIGAAcJvBq/LwBOAgAGAAcJvBq/LwBOAgAAAA==.Rawdata:BAABLgAECn8XAAMdAAgJARNKEACyAQAdAAcJ3Q9KEACyAQAFAAcJyw1VQgB4AQAAAA==.',
Re='Reaperdeath:BAAALgAECgEJAQAAAA==.Rebecca:BAABLgAECn8aAAITAAcJzxmsPQC4AQATAAcJzxmsPQC4AQAAAA==.Rebeka:BAABLgAECn8UAAIeAAYJ+h4bBQASAgAeAAYJ+h4bBQASAgABLgAECgcJGgATAM8ZAA==.Regantze:BAAALgAECgUJCAAAAA==.Reliun:BAAALgAECgYJDgAAAA==.Ressie:BAAALgAECgQJCQAAAA==.Reverendlion:BAAALgAECgEJAQAAAA==.',
Ro='Rogosh:BAAALgAECgEJAQAAAA==.',
Ru='Ruemor:BAAALgADCgYJFgAAAA==.',
Ry='Ryblade:BAAALgAECgcJDQABLgAECggJJQAQAM0VAA==.',
Sa='Saiko:BAAALgAECgIJAgAAAA==.Saladcake:BAAALgAECgQJBAAAAA==.Salleane:BAABLgAECn8XAAIQAAcJ2hU1XgDJAQAQAAcJ2hU1XgDJAQAAAA==.Sampal:BAAALgAECgYJEgAAAA==.Sampriest:BAAALgAECgQJBAABLgAECgYJEgAEAAAAAA==.Samwield:BAABLgAECn8oAAMfAAkJ4RzYBwATAwAfAAkJ4RzYBwATAwAcAAMJJhdLEwDNAAAAAA==.Sanchoe:BAAALgAECgQJBAAAAA==.Sanzo:BAAALgADCgEJAQAAAA==.',
Se='Seireitei:BAAALgAECgYJDQAAAA==.Selaheal:BAAALgAECgYJEgAAAA==.Seraath:BAACLgAFFH8OAAIgAAQJMhlvAQD/AAAgAAQJMhlvAQD/AAAuAAQKfyYAAyAACQn7IZAAAGQDACAACQn7IZAAAGQDABQAAQkAAHLSAE4AAAAA.Serath:BAAALgAECgYJBwAAAA==.',
Sh='Shadwkllr:BAAALgAECgQJBQAAAA==.Shamloo:BAAALgADCgEJAQAAAA==.Shimwow:BAAALgAECgMJAwAAAA==.Shnood:BAAALgAECgYJCQAAAA==.Shortie:BAAALgADCggJCAAAAA==.',
Sk='Ski:BAAALgAECgIJAgAAAA==.Skies:BAAALgAECgEJAgAAAA==.',
Sn='Snowhite:BAAALgAECgIJAgAAAA==.',
So='Soshi:BAAALgAECgQJBAAAAA==.',
Sp='Speckle:BAAALgADCgkJEQAAAA==.Spooqe:BAAALgADCgcJBwAAAA==.',
St='Stabbie:BAAALgADCgcJBwAAAA==.Stahn:BAAALgAECgUJBQAAAA==.Stdoubleds:BAAALgAECgQJBAAAAA==.Stervana:BAABLgAECn8mAAIDAAkJWiDhAwBaAwADAAkJWiDhAwBaAwAAAA==.Stickytoes:BAAALgADCgYJBgAAAA==.Stormyknight:BAABLgAECn8gAAMRAAgJVA4AGgC8AQARAAgJVA4AGgC8AQASAAYJ5QvoBADUAAAAAA==.',
Su='Sunwrath:BAAALgAECgcJCAAAAA==.Suspectedd:BAABLgAFFH8FAAIhAAMJdwhaLwD5AAAhAAMJdwhaLwD5AAABLgAFFAQJDgAiAE0iAA==.Suswar:BAACLgAFFH8OAAIiAAQJTSJ1BAA2AQAiAAQJTSJ1BAA2AQAuAAQKfykAAiIACQlMJJkAALgDACIACQlMJJkAALgDAAAA.Suvulaan:BAABLgAECn8UAAMRAAYJxwXgBwD8AAARAAYJxwXgBwD8AAADAAEJ5ACOawAbAAAAAA==.',
Sw='Swifix:BAAALgADCgYJCQAAAA==.',
Ta='Tacostand:BAACLgAFFH8MAAIUAAQJERa2EABJAQAUAAQJERa2EABJAQAuAAQKfyMAAhQACQlNIOYHAEwDABQACQlNIOYHAEwDAAAA.Tamarlane:BAAALgADCgIJAgAAAA==.Tatoo:BAABLgAECn8cAAITAAgJGx/cBAAuAgATAAgJGx/cBAAuAgAAAA==.',
Te='Teeice:BAAALgAECgcJEwAAAA==.Teo:BAAALgAECgYJCwAAAA==.Terian:BAAALgAECgkJBAAAAA==.',
Th='Thaodan:BAABLgAECn8YAAIZAAgJSRK4DAAyAQAZAAgJSRK4DAAyAQAAAA==.Thekan:BAAALgAECggJDQAAAA==.Theriot:BAABLgAECn8XAAMQAAcJAB5CNgBKAgAQAAcJAB5CNgBKAgAeAAEJMwgmoAAoAAAAAA==.Thianá:BAAALgAECgMJAwAAAA==.Thüclides:BAAALgAECgcJAgAAAA==.',
Ti='Tikidragoona:BAAALgAECgIJAgAAAA==.Tinkerspell:BAAALgAECgYJCwAAAA==.Tinkiebella:BAAALgADCgMJAwABLgAECgYJCwAEAAAAAA==.Tiredinras:BAAALgADCgIJAgAAAA==.',
To='Toosus:BAABLgAFFH8IAAIJAAMJ9xjYCQDmAAAJAAMJ9xjYCQDmAAABLgAFFAQJDgAiAE0iAA==.Toppers:BAAALgAECgMJAwAAAA==.Topps:BAABLgAECn8ZAAIdAAgJJhRsCgAqAgAdAAgJJhRsCgAqAgAAAA==.Toric:BAAALgADCgYJBgAAAA==.Toridian:BAAALgAECgIJAwAAAA==.Torinus:BAAALgADCgMJAwAAAA==.Totec:BAAALgAECgUJCgAAAA==.',
Tr='Trolldung:BAAALgADCgYJBgAAAA==.',
Tt='Tturtle:BAABLgAECn8lAAIQAAkJeBXoMABfAgAQAAkJeBXoMABfAgAAAA==.',
Tu='Tuss:BAAALgADCgEJAgAAAA==.',
Ty='Tyariel:BAAALgADCgYJBgAAAA==.Tystraz:BAAALgADCgkJDAAAAA==.',
Ud='Udúnnaur:BAAALgADCgcJBwAAAA==.',
Um='Umisle:BAAALgADCgQJBAAAAA==.',
Un='Undermage:BAAALgADCgQJBAAAAA==.',
Va='Valmora:BAAALgADCgMJAwAAAA==.Valstad:BAAALgADCgIJAgAAAA==.',
Ve='Vector:BAAALgAECgYJBgAAAA==.Velata:BAAALgAECgUJEQAAAA==.Verdugo:BAAALgADCgEJAQAAAA==.Verite:BAAALgAECgYJEQAAAA==.',
Vi='Vicar:BAAALgADCgcJBwAAAA==.Vice:BAAALgADCgEJAQAAAA==.Violencê:BAAALgAECgYJEgAAAA==.',
Vo='Vodka:BAAALgADCgUJEAAAAA==.Voelva:BAAALgADCgEJAQAAAA==.Voidedge:BAABLgAECn8dAAMGAAcJQA0IdgBxAQAGAAcJQA0IdgBxAQAHAAQJwAWpRgCbAAAAAA==.Voidgazer:BAAALgAECgYJBwAAAA==.Voidsyn:BAAALgAECgMJAwAAAA==.',
We='Wes:BAABLgAECn8ZAAIcAAcJFhQSAgCVAQAcAAcJFhQSAgCVAQAAAA==.',
Wi='Wildlettuce:BAAALgADCgEJAQAAAA==.Willybcastin:BAAALgAFFAEJAQABLgAFFAYJEwAWAP4lAA==.Willybwankin:BAACLgAFFH8TAAIWAAYJ/iWWAABrAgAWAAYJ/iWWAABrAgAuAAQKfyMAAhYACQkwJskAAOEDABYACQkwJskAAOEDAAAA.',
Wo='Wolfiekins:BAAALgADCgUJBQAAAA==.Wowgazm:BAAALgAECgYJEQAAAA==.',
Wy='Wyvern:BAAALgAECgUJDQAAAA==.',
Za='Zacarly:BAAALgAECgMJAwAAAA==.Zalmage:BAABLgAECn8cAAMhAAgJHRItEQC5AQAhAAgJHRItEQC5AQAjAAIJ5wlpFwBeAAAAAA==.Zantack:BAAALgAECgUJBQAAAA==.',
Ze='Zemos:BAAALgADCgMJAwAAAA==.Zeseroth:BAACLgAFFH8KAAIQAAQJjCBdBwB7AQAQAAQJjCBdBwB7AQAuAAQKfyQAAhAACQmnIycDAKMDABAACQmnIycDAKMDAAAA.Zeserotho:BAAALgAECgQJBgAAAA==.',
Zy='Zyn:BAACLgAFFH8GAAIXAAMJcSFNAgAtAQAXAAMJcSFNAgAtAQAuAAQKfyAAAxcACAlnIhIGAO4CABcACAlnIhIGAO4CAAwAAwn4DWZQAI0AAAAA.',
['Äs']='Äshra:BAAALgADCgMJAwAAAA==.',
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

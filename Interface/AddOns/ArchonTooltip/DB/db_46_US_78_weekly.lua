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

local lookup = {'Priest-Discipline','Priest-Holy','Monk-Windwalker','Monk-Brewmaster','Druid-Restoration','DeathKnight-Unholy','DemonHunter-Havoc','DemonHunter-Vengeance','Mage-Frost','Unknown-Unknown','Hunter-Marksmanship','Warlock-Destruction','Warlock-Demonology','Druid-Balance','Shaman-Restoration','Paladin-Retribution','Rogue-Subtlety','Rogue-Assassination','Hunter-BeastMastery','Warrior-Protection','Priest-Shadow','DemonHunter-Devourer','Paladin-Protection','Shaman-Elemental','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Monk-Mistweaver','Shaman-Enhancement','Paladin-Holy','Warlock-Affliction','DeathKnight-Blood','Mage-Fire','Druid-Guardian','Warrior-Fury','Warrior-Arms','Druid-Feral','Rogue-Outlaw','DeathKnight-Frost',}
local provider = {region='US',realm='Dreadmaul',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abbathdoom:BAAALgAECggJDQAAAA==.',
Ae='Aedaris:BAABLgAECn9LAAMBAAgJfh0TFgCMAQABAAYJzBgTFgCMAQACAAMJmiE6LgDbAAAAAA==.Ael:BAAALgAECgEJAQAAAA==.Aethalides:BAAALgAECgYJDwAAAA==.',
Al='Alandrias:BAAALgAECgkJAQAAAA==.Altaria:BAABLgAFFH8LAAMDAAQJ/RcdCABFAQADAAQJ4xUdCABFAQAEAAQJRhfUEwDaAAAAAA==.Alvv:BAAALgADCgMJBQAAAA==.Alvz:BAAALgADCgMJAwAAAA==.',
An='Anouke:BAAALgADCgIJAgAAAA==.Anserion:BAAALgADCgMJAwAAAA==.Anvious:BAAALgAECgcJDAAAAA==.',
Aq='Aquilea:BAAALgAECgcJEQAAAA==.',
Ar='Arcfuldodger:BAAALgADCgcJCgAAAA==.Artais:BAABLgAECn8gAAIFAAgJ1Rx7FgCCAgAFAAgJ1Rx7FgCCAgAAAA==.Artzlayer:BAABLgAECn8nAAIGAAkJcCLkCADPAgAGAAkJcCLkCADPAgAAAA==.Aríes:BAABLgAECn9LAAMHAAgJnBzzBQBNAgAHAAgJnBzzBQBNAgAIAAEJGAkFIAAsAAAAAA==.',
As='Ashbourne:BAAALgADCgcJCwAAAA==.',
Aw='Aw:BAAALgAECgYJEQABLgAFFAUJDwAJAOcOAA==.Awry:BAABLgAECn8gAAIGAAgJtByJGgArAgAGAAgJtByJGgArAgAAAA==.Awuuga:BAAALgAECgEJAQABLgAECgYJEgAKAAAAAA==.Aww:BAACLgAFFH8PAAIJAAUJ5w4LMgBEAQAJAAUJ5w4LMgBEAQAuAAQKfxwAAgkACAkkF/9+ANMBAAkACAkkF/9+ANMBAAAA.',
Az='Azamalaza:BAABLgAECn8fAAILAAcJYCHmBADjAQALAAcJYCHmBADjAQAAAA==.Azmo:BAACLgAFFH8FAAMMAAMJkxLHEQBcAAANAAMJBgwEOQCiAAAMAAEJaxzHEQBcAAAuAAQKfyUAAwwACAkwIcECANYCAAwACAmJHcECANYCAA0ABQk+HLNgAKcBAAAA.Azulon:BAAALgADCgUJBQABLgAECgcJGQABAPcbAA==.Azyrt:BAAALgAECgQJBAABLgAECggJIAAFANUcAA==.',
Ba='Barad:BAAALgAECgEJAgAAAA==.Batrick:BAAALgADCgcJBwAAAA==.Baulric:BAAALgAECgEJAQAAAA==.Bawls:BAAALgAECgYJBgAAAA==.',
Be='Beefrod:BAAALgADCgEJAQAAAA==.Beenis:BAAALgADCgUJBQABLgAECgcJEAAKAAAAAA==.Belerick:BAABLgAFFH8JAAIOAAMJnQqaDwDoAAAOAAMJnQqaDwDoAAAAAA==.Belphine:BAAALgAECgYJCAAAAA==.',
Bi='Bicksmage:BAABLgAFFH8FAAIJAAIJSREkYgCkAAAJAAIJSREkYgCkAAAAAA==.Bigdaddylock:BAACLgAFFH8PAAINAAUJ8hlhGwBGAQANAAUJ8hlhGwBGAQAuAAQKfyUAAwwACQnfJEwIAD4CAAwABgm1IkwIAD4CAA0ACAkqIxgaABQCAAAA.Biluman:BAAALgAECgQJBAAAAA==.Biodeath:BAAALgADCgUJBQAAAA==.Biopally:BAAALgADCgYJDQAAAA==.Biorogue:BAAALgADCgYJDAAAAA==.Bishope:BAABLgAECn8ZAAIBAAcJ9xtuCABXAgABAAcJ9xtuCABXAgAAAA==.',
Bl='Bllizard:BAAALgAECgEJAQAAAA==.Bloodache:BAAALgADCgcJCAABLgAECgQJCwAKAAAAAA==.Bluecar:BAAALgAECgYJCAAAAA==.',
Bo='Bohica:BAAALgAECgIJBQAAAA==.Bombdiggity:BAABLgAECn8cAAIBAAYJjh8dCwAhAgABAAYJjh8dCwAhAgAAAA==.Bonnierot:BAAALgAECgUJCgAAAA==.Boypally:BAAALgAECgIJAgAAAA==.',
Br='Brecciana:BAAALgADCgUJBQAAAA==.Brewjitsu:BAABLgAECn9AAAIEAAgJnhiwDAD4AQAEAAgJnhiwDAD4AQAAAA==.Brick:BAABLgAECn8fAAIEAAcJch56EQC5AQAEAAcJch56EQC5AQABLgAFFAUJEwANAPIfAA==.Brongakill:BAAALgADCgYJBgAAAA==.',
Bu='Bumble:BAAALgADCgYJBgABLgAFFAYJGQACAP0dAA==.Bundalock:BAAALgADCgYJEQAAAA==.',
Ca='Cakebringer:BAAALgAECgcJEgAAAA==.Caroshi:BAABLgAECn8bAAIJAAgJowoOWgBgAQAJAAgJowoOWgBgAQAAAA==.',
Ce='Cell:BAAALgAECgUJCAABLgAECgcJCwAKAAAAAA==.Ceridwen:BAAALgADCgEJAQAAAA==.',
Ch='Charlotte:BAAALgAECgMJBwAAAA==.Cheto:BAAALgAECgcJBwABLgAFFAUJCwAPAKEbAA==.',
Ci='Cig:BAABLgAECn8YAAIQAAgJ/hCfOACdAQAQAAgJ/hCfOACdAQAAAA==.',
Cl='Clankychan:BAACLgAFFH8HAAIEAAMJhgm7LwCCAAAEAAMJhgm7LwCCAAAuAAQKfxcAAgQABwnVEsAmAA0BAAQABwnVEsAmAA0BAAAA.Cloneofmagic:BAAALgADCgcJBwAAAA==.',
Co='Combustanut:BAAALgAECgIJBAAAAA==.Comillmouth:BAABLgAECn8ZAAIBAAgJahEmEgC5AQABAAgJahEmEgC5AQAAAA==.Comillthroat:BAAALgAECgkJEAAAAA==.Cos:BAABLgAECn8sAAMRAAkJQQ6ACQAJAgARAAkJQQ6ACQAJAgASAAMJOAXDFgCKAAAAAA==.',
Cr='Cryptum:BAAALgAECggJBAAAAA==.Cryten:BAAALgAECgIJAgAAAA==.',
['Cä']='Cäin:BAAALgAECgQJCAAAAA==.',
Da='Dabufart:BAAALgADCgEJAQAAAA==.Daerus:BAAALgAECgYJBQAAAA==.Damge:BAAALgAECgUJCgAAAA==.Danky:BAAALgAECgMJAwAAAA==.Danteh:BAAALgAFFAEJAQAAAA==.Darahug:BAAALgADCgYJDAAAAA==.Daraina:BAAALgADCgEJAQABLgADCgEJAQAKAAAAAA==.Darrkton:BAAALgADCgEJAQAAAA==.Dathil:BAAALgAECgYJCQAAAA==.Davmonhunter:BAAALgADCgQJBAAAAA==.',
De='Deadiemurphy:BAAALgADCgYJCQAAAA==.Deathshunter:BAABLgAECn8eAAMTAAgJLyO1CwCCAgATAAcJ9CS1CwCCAgALAAYJ+hkYOgB5AQABLgAFFAUJCgAGAP0XAA==.Deaththorn:BAAALgADCgEJAQAAAA==.Debsi:BAABLgAECn8ZAAIUAAgJPw7fDgB1AQAUAAgJPw7fDgB1AQAAAA==.Deeper:BAAALgAECgYJEAAAAA==.Deepest:BAAALgAFFAIJAgAAAA==.Deloraine:BAACLgAFFH8aAAIVAAYJ5iCuAQDyAQAVAAYJ5iCuAQDyAQAuAAQKfx4AAhUABwnHIrwNAO4BABUABwnHIrwNAO4BAAAA.Demonicfaith:BAABLgAECn82AAMHAAcJbxqBFwAMAgAHAAYJTx6BFwAMAgAWAAcJwAvfZQDRAAAAAA==.Denman:BAABLgAECn8YAAMQAAcJhRk8SgBnAQAQAAcJhRk8SgBnAQAXAAEJmAAjUAAKAAAAAA==.',
Di='Dirtyfux:BAACLgAFFH8FAAIBAAIJjxdXHQCnAAABAAIJjxdXHQCnAAAuAAQKfxUAAwEABglrHIEVAJIBAAEABglrHIEVAJIBAAIAAQkZDwKDAC4AAAAA.Dirtysham:BAACLgAFFH8FAAIPAAIJbR1KKQCsAAAPAAIJbR1KKQCsAAAuAAQKfyoAAw8ACQmyH/4MALUCAA8ACAlxIf4MALUCABgAAwnqBe1JAH0AAAAA.Discipline:BAAALgADCgcJBwAAAA==.Disckin:BAAALgADCgUJBgAAAA==.Divinechill:BAAALgADCgQJBAAAAA==.',
Dn='Dnb:BAAALgADCgEJAQABLgAFFAUJDwAJAOcOAA==.Dnk:BAAALgADCgMJAwAAAA==.',
Do='Dom:BAAALgADCgcJCQAAAA==.Donki:BAAALgAECgcJCgAAAA==.Doomvedas:BAAALgAECgYJCgAAAA==.',
Dr='Dracaena:BAABLgAECn8jAAQZAAkJrBm6AgATAgAZAAgJshe6AgATAgAaAAgJkBT4GwDoAQAbAAUJQwiuMQDiAAAAAA==.Draco:BAAALgAECgMJAwAAAA==.Drekavach:BAAALgADCgcJEwAAAA==.Droidbick:BAAALgAECgYJBwAAAA==.',
['Dâ']='Dâftmonk:BAAALgAECgEJAgABLgAECggJCQAKAAAAAA==.',
Ee='Eevo:BAAALgAECgMJAwABLgAECggJFAAcAJEIAA==.',
El='Elaha:BAAALgAECgcJCQAAAA==.Elexann:BAAALgAECgkJAQAAAA==.Elibaba:BAAALgAECggJDQAAAA==.Elideady:BAAALgAECggJBAABLgAECggJDQAKAAAAAA==.Elindyl:BAAALgADCgEJAQAAAA==.Elleth:BAAALgADCgIJAgAAAA==.Elvishcheese:BAAALgAECgMJBgAAAA==.',
Em='Emojis:BAAALgAECgQJBAAAAA==.',
En='Endlessdh:BAACLgAFFH8HAAIHAAMJ7SEJBwDIAAAHAAMJ7SEJBwDIAAAuAAQKfxgAAgcABwkbJJQJAMgCAAcABwkbJJQJAMgCAAAA.',
Er='Eraserhead:BAAALgAECgYJEwABLgAFFAUJDgAdAPofAA==.Erissaria:BAAALgADCgEJAQAAAA==.',
Ev='Evening:BAAALgAECgMJBAAAAA==.Everbuddha:BAAALgAECgQJBgAAAA==.',
Ew='Ewa:BAAALgAECgMJBAAAAA==.Eww:BAAALgAECgcJEwAAAA==.',
Ez='Ezelia:BAABLgAECn8aAAMQAAkJfRYDGAA7AgAQAAkJfRYDGAA7AgAeAAEJRglUlQA1AAABLgAFFAcJKQACAMgYAA==.',
Fa='Faelune:BAAALgAECgcJEQAAAA==.Faldir:BAAALgADCgYJBAABLgAECggJHgAWABghAA==.',
Fe='Ferndru:BAAALgAECgYJDAAAAA==.',
Fi='Fish:BAAALgAECgEJAgABLgAECggJGAAaADQhAA==.Fisticuffs:BAACLgAFFH8NAAIcAAUJ9AyDDQBFAQAcAAUJ9AyDDQBFAQAuAAQKfxsAAhwABwngFf0kAIsBABwABwngFf0kAIsBAAAA.',
Fl='Flameshock:BAAALgAFFAEJAQAAAA==.Flowki:BAAALgADCgYJBQAAAA==.',
Fo='Forcespark:BAAALgAECgEJAQAAAA==.',
Fr='Frostradamus:BAAALgADCgkJCgAAAA==.',
Fu='Fullmoonride:BAAALgAECgEJAQAAAA==.Fumbll:BAAALgAECgkJCQAAAA==.Funkymajik:BAAALgAECgcJEQAAAA==.Furiosa:BAAALgADCgkJDgAAAA==.',
Ga='Gallywox:BAAALgADCgMJAwAAAA==.Ganin:BAABLgAECn8bAAIeAAYJSxVRJgBXAQAeAAYJSxVRJgBXAQAAAA==.Gankinyou:BAAALgADCgEJAQAAAA==.Garielyn:BAAALgADCgEJAQAAAA==.Garugala:BAABLgAECn8jAAIQAAkJXBdYGgArAgAQAAkJXBdYGgArAgAAAA==.',
Gd='Gdaycøb:BAAALgADCgYJBwAAAA==.',
Ge='Gengár:BAAALgAECgMJBgABLgAECgcJCgAKAAAAAA==.',
Gh='Ghalorin:BAAALgAECgMJCgAAAA==.Ghiroza:BAABLgAECn9MAAQMAAgJuh7eCAAzAgANAAgJrR6MEgBOAgAMAAgJjBbeCAAzAgAfAAIJcBdpHQCGAAAAAA==.',
Gi='Gigaevoker:BAABLgAECn8kAAIbAAgJahZZBgAgAgAbAAgJahZZBgAgAgAAAA==.Gigapaladin:BAAALgADCgQJBAAAAA==.Gingarthas:BAABLgAECn8iAAIGAAkJOR1GEwBhAgAGAAkJOR1GEwBhAgAAAA==.',
Gl='Glowingtoe:BAAALgAECgMJBQAAAA==.',
Go='Gogmazios:BAAALgADCgcJBwAAAA==.',
Gr='Gravytate:BAABLgAECn9KAAIYAAgJbA9dIABMAQAYAAgJbA9dIABMAQAAAA==.Griinn:BAAALgAECgcJEQAAAA==.Grimescene:BAAALgAECgIJAgAAAA==.',
Gu='Guldannyboy:BAABLgAECn8mAAMMAAkJhQmcCwAaAQAMAAgJkwmcCwAaAQANAAkJPAYAAAAAAAAAAA==.Gumbö:BAAALgAECgYJBgABLgAECggJIAAFANUcAA==.',
Ha='Hammer:BAAALgAECgIJAgABLgAECggJCQAKAAAAAA==.Hantore:BAAALgADCgMJAwAAAA==.Harry:BAABLgAECn8nAAMdAAkJYyTlAQA/AwAdAAkJYyTlAQA/AwAPAAcJxBrkIAAaAgAAAA==.',
He='Heartdh:BAABLgAECn8VAAMWAAgJkRKbJwCdAQAWAAgJkRKbJwCdAQAHAAIJrxODWwByAAAAAA==.Heisenbergg:BAAALgADCgIJAgAAAA==.Hellza:BAAALgAECgMJAwAAAA==.Hen:BAAALgAECgUJBQABLgAECgYJFQAgAA4VAA==.Herpyprotect:BAAALgAFFAIJAgAAAA==.Herrion:BAACLgAFFH8TAAINAAUJ8h/SEAB3AQANAAUJ8h/SEAB3AQAuAAQKfy4AAw0ACQn9IvccAKgCAA0ACAn9IvccAKgCAAwABAmcJNEUAKQBAAAA.',
Hh='Hh:BAAALgAECgEJAQAAAA==.',
Ho='Hotspur:BAABLgAECn84AAIFAAgJaxDQOADDAQAFAAgJaxDQOADDAQAAAA==.',
Hu='Hukani:BAAALgAECgEJAQABLgAECggJFgACALEIAA==.Huskar:BAAALgAECgcJCwAAAA==.',
Hy='Hypoxi:BAAALgADCgYJCQAAAA==.',
Ig='Ignis:BAABLgAECn8TAAIhAAgJbhwHAQA1AgAhAAgJbhwHAQA1AgAAAA==.Ignitor:BAAALgADCgEJAQAAAA==.',
Ik='Ikari:BAABLgAECn9LAAIMAAgJ+Rs7AgAzAgAMAAgJ+Rs7AgAzAgAAAA==.',
Il='Illadoss:BAAALgADCgIJAgAAAA==.',
Im='Imntprepared:BAAALgAECggJCQAAAA==.',
In='Incarnate:BAAALgAECgEJAQAAAA==.Incubis:BAAALgADCgIJAgAAAA==.Infectîon:BAAALgADCgYJBgAAAA==.Inferlock:BAAALgADCgMJAwAAAA==.Infernyoz:BAAALgADCggJCQAAAA==.',
Ir='Irithel:BAAALgAECgcJBQAAAA==.',
It='Itchygrowth:BAAALgAFFAEJAQAAAA==.',
Iv='Ivygambina:BAAALgADCgYJBgAAAA==.Ivysore:BAAALgAECgUJBwAAAA==.',
Ja='Jasha:BAAALgADCgcJCwAAAA==.Jayy:BAABLgAECn8bAAIGAAkJBRCBTAAOAgAGAAkJBRCBTAAOAgAAAA==.',
Je='Jennatalia:BAAALgAECgcJCgAAAA==.',
Jo='Joelsdruid:BAABLgAFFH8HAAIiAAQJ+xPmAwARAQAiAAQJ+xPmAwARAQAAAA==.Joelvoker:BAAALgAFFAIJAgABLgAFFAQJBwAiAPsTAA==.Joexotic:BAAALgAECgIJBQAAAA==.Jongwang:BAAALgAECgQJBwAAAA==.',
Ju='Jubjub:BAAALgAECgEJAgAAAA==.',
Ka='Kaaru:BAABLgAECn8fAAMBAAcJjBZjDwDcAQABAAcJKxVjDwDcAQACAAUJExKCSAAXAQAAAA==.Kaihavocz:BAAALgAECgEJAQAAAA==.Kairon:BAABLgAECn8vAAIQAAkJwBahGAA2AgAQAAkJwBahGAA2AgAAAA==.Kalysae:BAAALgADCgEJAQAAAA==.Katarinabluu:BAAALgAECgYJBgAAAA==.Kazakhthundr:BAAALgADCgYJBgAAAA==.',
Ke='Keeanuleaves:BAAALgADCgYJBwAAAA==.Keeanuweaves:BAAALgADCgEJAQAAAA==.Keeze:BAABLgAFFH8GAAIJAAMJvwEaVQDHAAAJAAMJvwEaVQDHAAAAAA==.',
Ki='Kickstarter:BAAALgAECgYJEgAAAA==.Kiel:BAAALgAECgEJAQAAAA==.Killania:BAAALgADCgMJAwAAAA==.Kiwichaos:BAACLgAFFH8JAAIHAAQJeAmbCwDUAAAHAAQJeAmbCwDUAAAuAAQKfyQAAgcACAkcHs4FAFMCAAcACAkcHs4FAFMCAAAA.',
Kl='Klckyourass:BAAALgADCgUJBQAAAA==.',
Kn='Knox:BAAALgAECgIJAgAAAA==.',
Ko='Korner:BAAALgAECgIJAgAAAA==.',
Kr='Krazzul:BAAALgADCgYJBgAAAA==.Krellis:BAABLgAECn8WAAMDAAgJAhC7EwCUAQADAAgJAhC7EwCUAQAcAAYJtRA8MQAzAQAAAA==.Kritikall:BAAALgADCgUJBQAAAA==.',
Ku='Kurö:BAAALgAECgEJAQAAAA==.',
Kv='Kvôthe:BAAALgAECgcJDwAAAA==.',
Ky='Kynnareth:BAAALgAECgIJBQABLgAFFAYJDgABAHgLAA==.Kynralol:BAABLgAECn8hAAIJAAgJih4iHABBAgAJAAgJih4iHABBAgAAAA==.',
['Ká']='Káiser:BAAALgAECggJEQAAAA==.',
La='Laenosh:BAAALgAECgQJCwAAAA==.Laomoo:BAAALgAECgcJDgAAAA==.',
Le='Learning:BAABLgAECn8XAAIYAAcJDB9GGwA4AgAYAAcJDB9GGwA4AgAAAA==.Legham:BAAALgADCgkJDgAAAA==.Legolazz:BAABLgAECn8qAAMTAAkJBR1PCACtAgATAAkJBR1PCACtAgALAAMJCBSbGQB+AAAAAA==.Lemins:BAAALgAECgMJAwAAAA==.Lemondruid:BAAALgAECgIJAgAAAA==.Lemonmelon:BAAALgAECgYJEwAAAA==.Lenatheplug:BAACLgAFFH8SAAMRAAUJ3BwKAwDMAQARAAUJ3BwKAwDMAQASAAEJQRHHBQBgAAAuAAQKfyIAAxEACAmUJD8KAO4CABEACAnbIz8KAO4CABIABwk/ItwDAIACAAAA.Lerust:BAAALgADCgcJBwAAAA==.',
Li='Liadrine:BAABLgAECn8mAAIQAAgJxheDNgCkAQAQAAgJxheDNgCkAQAAAA==.Linus:BAAALgAECgYJBgABLgAFFAUJEwANAPIfAA==.Littleriver:BAAALgAECgcJEQAAAA==.',
Ll='Llewser:BAAALgAECgUJDQAAAA==.',
Lo='Loathe:BAAALgAECgEJAQAAAA==.Loistiah:BAAALgAECgQJCgAAAA==.Lothaof:BAABLgAECn8kAAIQAAkJgw0uSQBqAQAQAAkJgw0uSQBqAQAAAA==.Louisvuitton:BAAALgAECgUJCwAAAA==.',
Lp='Lpayn:BAAALgADCgEJAQAAAA==.',
Lu='Lugroth:BAAALgAECgEJAgABLgAFFAUJEwANAPIfAA==.Lunana:BAAALgAECgcJEgAAAA==.',
Ly='Lychiee:BAAALgAECgcJEQAAAA==.',
Ma='Magesorry:BAAALgADCgUJBQAAAA==.Maize:BAABLgAECn8eAAMBAAgJLBuTCABTAgABAAgJLBuTCABTAgACAAMJhgvMZwCOAAAAAA==.Makima:BAABLgAFFH8FAAIOAAUJlQ5UFQADAQAOAAUJlQ5UFQADAQAAAA==.Malikai:BAAALgADCgcJDAAAAA==.Marcyon:BAAALgAECgYJEwAAAA==.',
Mc='Mchèalz:BAABLgAECn8VAAQBAAgJPwgBHQBEAQABAAgJPwgBHQBEAQACAAQJxAE+aQCIAAAVAAIJOwFuZgAsAAAAAA==.',
Me='Melonlemonza:BAAALgADCgQJBAAAAA==.Mentok:BAAALgAECgYJCwAAAA==.Merchei:BAAALgAECgUJBgAAAA==.Meruen:BAABLgAECn8XAAIWAAgJYxfdGgDoAQAWAAgJYxfdGgDoAQAAAA==.',
Mi='Mistie:BAAALgAECgEJAQAAAA==.Mitymorphin:BAAALgADCgEJAQAAAA==.',
Mo='Mobility:BAAALgADCgYJBgAAAA==.Moistpole:BAAALgADCgQJBAAAAA==.Momock:BAAALgAECgQJBAAAAA==.Mongk:BAABLgAECn8UAAIcAAgJkQiaNQAZAQAcAAgJkQiaNQAZAQAAAA==.Monscustodes:BAABLgAECn8aAAIJAAcJeQ6QWwBdAQAJAAcJeQ6QWwBdAQAAAA==.Mookin:BAAALgAECgcJCAAAAA==.Moospoon:BAABLgAECn8UAAIQAAgJRAkFUQBTAQAQAAgJRAkFUQBTAQAAAA==.Moounka:BAABLgAECn8oAAIEAAcJ4AsGJAAdAQAEAAcJ4AsGJAAdAQAAAA==.Morphio:BAABLgAECn82AAMTAAkJOCD7AgARAwATAAkJOCD7AgARAwALAAUJCxOOTAAfAQAAAA==.Mostakrakish:BAAALgADCgEJAQAAAA==.',
Mu='Muddles:BAABLgAECn88AAIEAAgJCxb7DwDLAQAEAAgJCxb7DwDLAQAAAA==.Murius:BAABLgAECn8rAAIGAAgJWhZTLwC8AQAGAAgJWhZTLwC8AQAAAA==.',
My='Mysterio:BAAALgAECgYJCQAAAA==.',
Na='Naendria:BAAALgAECgMJBAAAAA==.Naga:BAAALgAECgIJAgAAAA==.Nahaza:BAAALgAECgEJAgAAAA==.',
Ne='Nelena:BAAALgADCgEJAQAAAA==.',
Ni='Nickdoom:BAAALgAECgUJDwAAAA==.Nigella:BAABLgAECn8WAAMCAAgJsQhwIgA1AQACAAgJsQhwIgA1AQABAAEJ7AFTTwAhAAAAAA==.Nikola:BAABLgAECn8mAAQFAAgJAxdoNwDKAQAFAAgJAxdoNwDKAQAiAAUJNxbgFQAUAQAOAAQJfg92VADUAAAAAA==.Nimro:BAACLgAFFH8TAAIUAAQJJxd8BAA1AQAUAAQJJxd8BAA1AQAuAAQKfygAAhQACQmPH50DABsDABQACQmPH50DABsDAAAA.Niub:BAABLgAECn8aAAIjAAcJFAp0MAAKAQAjAAcJFAp0MAAKAQAAAA==.',
No='Nofate:BAAALgADCgEJAQAAAA==.Noirebringer:BAAALgAFFAEJAQAAAA==.',
Nt='Ntrldrake:BAAALgADCgEJAgABLgAECgcJGgAJAHkOAA==.',
Nu='Nuferax:BAAALgAECgcJEQAAAA==.Nulledhacz:BAAALgADCgEJAQAAAA==.Numbrethree:BAACLgAFFH8RAAIcAAMJvRArGwCkAAAcAAMJvRArGwCkAAAuAAQKfzMAAhwACAlTF3YWAA8CABwACAlTF3YWAA8CAAAA.',
Ob='Obbi:BAAALgAFFAIJBAABLgAFFAMJBQAkACQaAA==.',
Oh='Ohaither:BAAALgAECgQJBAAAAA==.',
Oi='Oirth:BAAALgADCgIJAgAAAA==.',
Ok='Okiji:BAAALgAECgMJAwAAAA==.',
Or='Orinocco:BAAALgAECgEJAQAAAA==.Orobas:BAAALgAECgEJAQAAAA==.',
Pa='Pakaww:BAAALgAECgIJAwAAAA==.Palimathrus:BAAALgAECgUJCAAAAA==.Palliative:BAABLgAECn8oAAMeAAcJnyLnCACDAgAeAAcJnyLnCACDAgAQAAEJbAGjIQEaAAAAAA==.Pallidnim:BAAALgAFFAEJAwAAAA==.',
Pe='Pea:BAAALgAECgcJEAAAAA==.Perish:BAAALgAECgIJAwABLgAECggJPAAEAAsWAA==.',
Ph='Phatmonk:BAACLgAFFH8KAAIDAAQJgiSfAQC3AQADAAQJgiSfAQC3AQAuAAQKfyAAAgMACQmsJKwAAF4DAAMACQmsJKwAAF4DAAAA.',
Pi='Piewpiew:BAAALgADCgcJCgAAAA==.Pix:BAACLgAFFH8TAAMVAAYJfhnVAgDHAQAVAAUJYh3VAgDHAQABAAUJwgwBDQB7AQAuAAQKfy0AAhUACQlSIj4EAFIDABUACQlSIj4EAFIDAAAA.',
Pl='Pleasuremax:BAAALgAECgcJEQAAAA==.Plex:BAABLgAECn8zAAIlAAgJSxcXBQALAgAlAAgJSxcXBQALAgAAAA==.',
Po='Poogie:BAAALgADCgYJBgABLgAECgMJBQAKAAAAAA==.Popshot:BAABLgAECn8eAAILAAYJ5xIcRQBBAQALAAYJ5xIcRQBBAQAAAA==.Portalhouse:BAAALgAECgEJAQAAAA==.',
Pr='Praxis:BAACLgAFFH8GAAIUAAIJLgcyFgBnAAAUAAIJLgcyFgBnAAAuAAQKfxcAAhQACAlZCXMdAFoBABQACAlZCXMdAFoBAAAA.Preast:BAAALgADCgMJAwABLgAECggJFAAcAJEIAA==.Procist:BAAALgAECgcJCAABLgAECgkJKQAPALkhAA==.',
Py='Pyrusdk:BAABLgAECn8XAAIGAAgJRA4XOwCOAQAGAAgJRA4XOwCOAQAAAA==.Pyrusdruid:BAAALgAECgkJCQAAAA==.',
Qo='Qop:BAAALgAECggJBgAAAA==.',
Qu='Quesarah:BAAALgADCgEJAQABLgAECgQJBAAKAAAAAA==.',
Qw='Qweffor:BAAALgAECgUJBQABLgAECggJFgAGAB8YAA==.',
Ra='Rainbowkelly:BAAALgAECgQJBAAAAA==.Raìn:BAAALgAFFAIJAgAAAA==.',
Re='Reapy:BAAALgAFFAIJAwAAAA==.Recruitqt:BAAALgAECgUJEgAAAA==.Reiayanami:BAABLgAECn8fAAIJAAgJdQ97QQCjAQAJAAgJdQ97QQCjAQAAAA==.',
Ri='Ripandtear:BAABLgAECn8VAAMFAAgJNhaQJQCeAQAFAAgJNhaQJQCeAQAlAAEJFQZ4NgAsAAAAAA==.',
Ro='Roguewan:BAAALgAFFAEJAQAAAA==.Roninn:BAABLgAECn8aAAIFAAgJrh28CQCtAgAFAAgJrh28CQCtAgAAAA==.Ronlock:BAABLgAECn8VAAMNAAYJ6xDynQAdAQANAAUJ6xDynQAdAQAMAAEJAAD4aQA+AAABLgAECgcJNgAHAG8aAA==.',
Rs='Rsi:BAAALgAECgQJBAAAAA==.',
Ry='Rynaea:BAAALgAECgEJAQAAAA==.',
['Rï']='Rïmuru:BAAALgADCgcJCwAAAA==.',
['Rô']='Rôlayne:BAAALgAECgYJBgAAAA==.',
Sa='Salvare:BAABLgAECn8lAAMSAAkJeRhvAwCVAgASAAkJbxhvAwCVAgAmAAIJWBDKDQB7AAAAAA==.Sappy:BAAALgADCgMJBAAAAA==.Sauron:BAAALgADCgEJAQABLgAECgcJIQAjAMkfAA==.',
Sb='Sbf:BAABLgAFFH8UAAIaAAcJYw9wBQDhAQAaAAcJYw9wBQDhAQABLgAFFAcJMQAJANAbAA==.',
Sc='Scalamander:BAAALgAECgcJAgAAAA==.Sciohunter:BAAALgAFFAIJAwAAAA==.Scioscioz:BAABLgAECn8aAAMFAAcJxRPfOwC1AQAFAAcJxRPfOwC1AQAOAAIJZBD6awBwAAAAAA==.Scwisgar:BAAALgAECggJDAAAAA==.',
Se='Sedge:BAAALgAFFAIJAwAAAA==.Sephire:BAABLgAECn8cAAIQAAcJZwRDhADkAAAQAAcJZwRDhADkAAAAAA==.Sermazule:BAAALgADCgcJEQAAAA==.Sewerface:BAABLgAECn8VAAMgAAYJDhV3FwASAQAgAAYJDhV3FwASAQAGAAMJLASWAQF2AAAAAA==.',
Sh='Shadonir:BAAALgAECgQJBAAAAA==.Shadowind:BAACLgAFFH8IAAITAAMJSxv1HgAbAQATAAMJSxv1HgAbAQAuAAQKfysAAwsACAlmHe4FAMABAAsACAkxGe4FAMABABMABAk9G+tGADgBAAAA.Shaft:BAAALgAECgEJAQAAAA==.Shallotte:BAABLgAECn8YAAMfAAgJcRDnCwB7AQAfAAcJABLnCwB7AQANAAcJmwjVUgAzAQAAAA==.Shammalxs:BAABLgAFFH8GAAIYAAUJRwRaDgA5AQAYAAUJRwRaDgA5AQAAAA==.Shamoc:BAABLgAECn8pAAMPAAkJuSEjBAACAwAPAAkJuSEjBAACAwAYAAYJoREMSQAjAQAAAA==.Shampooing:BAABLgAECn8bAAIYAAgJfRFCGwB0AQAYAAgJfRFCGwB0AQAAAA==.Sharpknife:BAABLgAFFH8GAAITAAMJaA82KgDxAAATAAMJaA82KgDxAAAAAA==.Shaz:BAAALgADCgQJBAAAAA==.Shivd:BAAALgADCgYJBgAAAA==.Shorpus:BAABLgAECn8ZAAQYAAgJqyDCFgCcAQAdAAYJNx8gCgAwAgAYAAYJBxzCFgCcAQAPAAcJCwj0XQATAQAAAA==.',
Si='Sicckbrew:BAABLgAECn8hAAIDAAkJRyH5CQDYAgADAAkJRyH5CQDYAgAAAA==.Sinniestro:BAAALgAECgEJAgAAAA==.',
Sk='Skizzyy:BAAALgAECgMJAwABLgAECgcJEAAKAAAAAA==.',
Sl='Slayedurmrs:BAAALgAECgQJBQAAAA==.Slowpoke:BAABLgAFFH8OAAIOAAQJYxbDCABXAQAOAAQJYxbDCABXAQABLgAFFAUJBQAOAJUOAA==.',
Sm='Smacedh:BAABLgAECn8UAAIWAAgJhBOSYgB6AQAWAAgJhBOSYgB6AQAAAA==.',
Sn='Sneakyfella:BAAALgAECggJCgAAAA==.',
So='Solidus:BAABLgAFFH8GAAIQAAQJmhTUFgBOAQAQAAQJmhTUFgBOAQAAAA==.',
Sp='Spaklehooves:BAAALgADCgYJBgAAAA==.Spiral:BAAALgAECgQJBwAAAA==.Spoonfed:BAAALgAECgQJCwAAAA==.',
Sq='Squiish:BAACLgAFFH8RAAMOAAYJ9RkQCgBIAQAOAAUJsBgQCgBIAQAFAAQJhwUpHQDtAAAuAAQKfxoAAg4ABwmoJesLANkCAA4ABwmoJesLANkCAAAA.',
Ss='Ss:BAAALgAECgEJAgAAAA==.',
St='Stavrophore:BAAALgAECgEJAgAAAA==.Stickydruid:BAAALgAECgIJBQABLgAECggJQgAVADsiAA==.Stickyholes:BAAALgAECgIJAgABLgAECggJQgAVADsiAA==.Stickymonk:BAAALgAECgEJAgABLgAECggJQgAVADsiAA==.Stickypriest:BAABLgAECn9CAAMVAAgJOyIeBACsAgAVAAgJOyIeBACsAgACAAEJExiNeQBCAAAAAA==.Stipe:BAAALgADCgUJCAAAAA==.Stove:BAAALgADCgcJCwAAAA==.Strawhats:BAACLgAFFH8xAAIJAAcJ0BsgAwBMAgAJAAcJ0BsgAwBMAgAuAAQKfzwAAgkACQkyJWkCANgDAAkACQkyJWkCANgDAAAA.Streamliner:BAABLgAECn8xAAMRAAkJVRrvCgDxAQARAAkJVRrvCgDxAQAmAAMJ1gdJCwCNAAAAAA==.Stuunks:BAAALgAECgYJCwAAAA==.',
Su='Sustangelia:BAABLgAECn8ZAAIGAAkJbhhxUAAAAgAGAAkJbhhxUAAAAgAAAA==.',
Sw='Swordkiller:BAAALgAECgcJBgAAAA==.',
Sx='Sxy:BAAALgAECgMJAgAAAA==.',
Sy='Sy:BAAALgAECgcJDwAAAA==.Synthesis:BAABLgAECn8hAAIFAAgJoyVPAgBjAwAFAAgJoyVPAgBjAwAAAA==.',
Ta='Tae:BAAALgADCgUJBQAAAA==.Taichee:BAAALgADCgUJBQAAAA==.Talas:BAAALgADCgIJAgAAAA==.Talletalanot:BAABLgAECn8uAAIbAAkJGiCSAgDJAgAbAAkJGiCSAgDJAgAAAA==.Tandryan:BAAALgAECgQJBwAAAA==.Tanukiji:BAABLgAECn8lAAICAAgJQxxWCABqAgACAAgJQxxWCABqAgAAAA==.',
Td='Tdh:BAAALgADCgMJAwAAAA==.Tdk:BAABLgAECn8WAAMGAAgJqRRxYgAfAQAGAAcJzRVxYgAfAQAgAAEJ0Q2/NABDAAAAAA==.',
Te='Tee:BAAALgADCgUJBQAAAA==.Tesarion:BAABLgAECn8WAAIGAAgJHxiaIwD2AQAGAAgJHxiaIwD2AQAAAA==.Testalatesta:BAABLgAECn8mAAMeAAgJ1B/2AwD5AgAeAAgJ1B/2AwD5AgAQAAEJmwiXBAE1AAAAAA==.',
Th='Tharien:BAAALgADCgIJAgAAAA==.Thovir:BAAALgADCgEJAQAAAA==.',
Ti='Tiberian:BAAALgADCgIJAgAAAA==.Tinyvolt:BAAALgAECgYJBwAAAA==.',
Tm='Tmonk:BAAALgAECggJDAAAAA==.',
To='Toinahun:BAAALgAECgQJBAAAAA==.Totemea:BAAALgADCggJDQAAAA==.Totems:BAABLgAFFH8LAAIPAAUJoRvQBwCaAQAPAAUJoRvQBwCaAQAAAA==.Totemîxx:BAABLgAECn8jAAMYAAcJ+BaIGACMAQAYAAcJ+BaIGACMAQAPAAQJYQ2wfgCYAAAAAA==.Touchhy:BAAALgAECgEJAQAAAA==.',
Tr='Trainz:BAAALgADCgcJBwAAAA==.Trass:BAABLgAECn82AAMNAAgJ5CCmDgB0AgANAAgJ5CCmDgB0AgAMAAMJKREYRAClAAAAAA==.Trays:BAAALgADCgEJAQAAAA==.Trisse:BAABLgAECn8UAAIWAAYJ2w16UQAFAQAWAAYJ2w16UQAFAQAAAA==.',
Tu='Tuzz:BAABLgAECn8nAAInAAkJ6yBiAQDuAgAnAAkJ6yBiAQDuAgAAAA==.',
Ty='Tyden:BAAALgAECgYJEAAAAA==.',
Va='Vael:BAAALgAECgYJCgAAAA==.Valerie:BAAALgAECgQJBAAAAA==.Valkyrra:BAAALgAECgQJBAAAAA==.Varaestia:BAAALgAECgQJBAAAAA==.Varg:BAAALgADCgEJAQABLgADCgEJAQAKAAAAAA==.Vargmk:BAAALgADCgEJAQAAAA==.Vargps:BAAALgADCgEJAQAAAA==.',
Ve='Verdict:BAACLgAFFH8JAAIQAAQJxhvuDAB2AQAQAAQJxhvuDAB2AQAuAAQKfxgAAhAACAloHlkgAKoCABAACAloHlkgAKoCAAAA.Vermeil:BAAALgAECgMJAwAAAA==.Vermillion:BAACLgAFFH8QAAIQAAQJ7hUpFwBNAQAQAAQJ7hUpFwBNAQAuAAQKfxsAAhAACQnTH7YiAPsBABAACQnTH7YiAPsBAAAA.',
Vi='Viegas:BAACLgAFFH8FAAITAAIJnRKcPQCfAAATAAIJnRKcPQCfAAAuAAQKfxsAAhMABwkhHK4gAEECABMABwkhHK4gAEECAAAA.Vincent:BAABLgAECn8hAAIJAAYJsB6SfgDUAQAJAAYJsB6SfgDUAQAAAA==.Vinijr:BAAALgAECgEJAgAAAA==.Vivamax:BAAALgAECgEJAQAAAA==.',
Vo='Volthic:BAAALgAECgQJBAAAAA==.Voltormu:BAAALgAECgMJBgAAAA==.Vore:BAABLgAECn8VAAIWAAgJYxSrJgCiAQAWAAgJYxSrJgCiAQAAAA==.',
Vr='Vrag:BAABLgAECn8eAAIGAAcJNAlMWAA2AQAGAAcJNAlMWAA2AQAAAA==.',
['Vè']='Vè:BAAALgAECgYJDAAAAA==.',
Wa='Warslaw:BAACLgAFFH8JAAIgAAQJyhgLCwAiAQAgAAQJyhgLCwAiAQAuAAQKfx0AAiAACQn9IV8FAOsCACAACQn9IV8FAOsCAAAA.Warth:BAAALgADCgEJAQAAAA==.Waterwater:BAAALgAECgYJCgAAAA==.Waterwaterz:BAACLgAFFH8JAAIJAAMJ2hupKgAKAQAJAAMJ2hupKgAKAQAuAAQKfzIAAgkACAnVHN80AJ8CAAkACAnVHN80AJ8CAAAA.Waylay:BAAALgADCgEJAQAAAA==.',
Wc='Wchin:BAAALgAECgcJEwAAAA==.Wchinz:BAABLgAECn8UAAIVAAkJayCLDgCaAgAVAAkJayCLDgCaAgAAAA==.',
We='Wedlock:BAAALgADCgIJAgAAAA==.Welcumshot:BAAALgAFFAIJAgAAAA==.',
Wi='Windsabre:BAAALgADCgIJAgAAAA==.Wingz:BAAALgADCgIJAgAAAA==.',
Wo='Woregeonnick:BAABLgAECn8eAAINAAcJUxGBTgA+AQANAAcJUxGBTgA+AQAAAA==.Woshiren:BAAALgAECgUJBQAAAA==.',
Wy='Wyvern:BAAALgAECgQJCQAAAA==.',
['Wä']='Wärrior:BAAALgADCgMJAwAAAA==.',
Xa='Xanadu:BAAALgADCgIJAgAAAA==.',
Xe='Xerxexy:BAAALgAECgQJCwAAAA==.',
Xi='Xiaodingdang:BAAALgAECgQJBAAAAA==.Xiera:BAAALgAECgcJEQAAAA==.',
Ya='Yaminosaishi:BAAALgAECgYJBwAAAA==.Yaoyôrozu:BAAALgADCgkJFAAAAA==.Yasuô:BAAALgADCgMJAwAAAA==.Yatelega:BAAALgADCgIJAgABLgAECgcJHgANAFMRAA==.Yazdorzarn:BAAALgAECgYJCwAAAA==.',
Za='Zaaniz:BAABLgAECn8bAAQQAAkJcx1uHwCvAgAQAAgJzh5uHwCvAgAXAAIJ5A2XJwBgAAAeAAEJ3AOMYAAzAAAAAA==.',
Ze='Zenestra:BAAALgAECggJAQAAAA==.Zenshui:BAAALgAECgYJCQAAAA==.Zephyruss:BAAALgADCgEJAQAAAA==.Zervis:BAAALgAECgIJAgAAAA==.Zeyra:BAAALgAECgYJDAAAAA==.',
Zi='Zinako:BAAALgADCgcJCwAAAA==.',
Zo='Zocalo:BAAALgAECgUJBQAAAA==.',
['Èa']='Èasymode:BAAALgADCgEJAQAAAA==.',
['Ód']='Ódyssey:BAAALgAECgcJBwAAAA==.',
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

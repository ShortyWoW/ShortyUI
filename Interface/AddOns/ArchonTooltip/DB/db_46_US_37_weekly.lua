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

local lookup = {'Druid-Balance','Druid-Restoration','Monk-Mistweaver','Evoker-Augmentation','Unknown-Unknown','Paladin-Protection','Mage-Frost','Warrior-Protection','Hunter-Survival','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Restoration','Warlock-Demonology','Warlock-Destruction','Warrior-Arms','DeathKnight-Blood','Monk-Windwalker','Monk-Brewmaster','Druid-Guardian','Priest-Shadow','Warrior-Fury','Paladin-Retribution','Priest-Holy','Evoker-Preservation','Evoker-Devastation','Shaman-Elemental','DemonHunter-Devourer','DemonHunter-Havoc','DeathKnight-Unholy','Priest-Discipline','Rogue-Assassination','Druid-Feral','DemonHunter-Vengeance','Paladin-Holy','Shaman-Enhancement','Rogue-Subtlety','Rogue-Outlaw','Mage-Arcane',}
local provider = {region='US',realm='Bladefist',name='US',type='weekly',zone=46,date='2026-05-08',data={Ad='Adhoria:BAAALgAECgEJAQAAAA==.Adrianmonk:BAAALgAECgYJEgAAAA==.',
Ae='Aezu:BAACLgAFFH8YAAMBAAUJtxvoCQBcAQABAAQJtxvoCQBcAQACAAMJ1BfgHADvAAAuAAQKfykAAwEACQmEI48QAJsCAAEACAmGJI8QAJsCAAIABwlIHk4jAC8CAAAA.',
Ai='Ailuria:BAABLgAECn8eAAIDAAYJByXGBwB6AgADAAYJByXGBwB6AgAAAA==.Airam:BAAALgADCgkJCQAAAA==.Aitharen:BAAALgADCgUJBAAAAA==.',
Al='Alaura:BAAALgADCgQJBAAAAA==.Albaz:BAABLgAECn8UAAIEAAgJzA1JIwCjAQAEAAgJzA1JIwCjAQAAAA==.Alepacino:BAAALgAECgEJAgABLgAECgEJAgAFAAAAAA==.Alikith:BAABLgAECn8eAAIGAAYJHxL8GABMAQAGAAYJHxL8GABMAQAAAA==.Alun:BAAALgADCgYJBgAAAA==.Alynia:BAAALgAECgEJAQAAAA==.',
Am='Ambrìel:BAABLgAECn8jAAIHAAgJzwprTgB/AQAHAAgJzwprTgB/AQAAAA==.Amyloid:BAAALgADCgEJAQAAAA==.Amèlia:BAACLgAFFH8LAAMCAAMJ0QjZKACtAAACAAMJ0QjZKACtAAABAAIJwwLIFwB5AAAuAAQKfyEAAwIACQn0F/IXAAUCAAIACQn0F/IXAAUCAAEAAQlKHU9LAFUAAAAA.',
An='Angando:BAABLgAECn8bAAIIAAgJZBHtDQCEAQAIAAgJZBHtDQCEAQAAAA==.Anjelik:BAAALgADCgYJBgAAAA==.Anneliesë:BAAALgADCgUJFAAAAA==.',
Ao='Aozora:BAAALgAECgYJEwAAAA==.',
Ar='Aric:BAAALgADCgQJBAAAAA==.Arrows:BAAALgADCgcJBwAAAA==.Artemidoros:BAABLgAECn8hAAQJAAcJzB/iCAAYAgAKAAYJGiEWIQA/AgAJAAcJNx7iCAAYAgALAAEJngr5igAwAAAAAA==.',
As='Ashkaari:BAACLgAFFH8MAAIMAAMJog+JJgC6AAAMAAMJog+JJgC6AAAuAAQKfxUAAgwACQl2FmInAPQBAAwACQl2FmInAPQBAAAA.Asuná:BAAALgAECggJEgAAAA==.',
Au='Aurelyus:BAAALgAECgMJBAAAAA==.Aurevior:BAAALgAECgYJDgAAAA==.Ausuna:BAAALgAECgQJBAAAAA==.',
Az='Azariyah:BAAALgADCgQJBAAAAA==.Azooma:BAAALgADCgkJEAAAAA==.Azshaderr:BAAALgAECgYJCwAAAA==.Azshaure:BAAALgAECgQJBwAAAA==.Azu:BAAALgAECgEJAQABLgAFFAUJGAABALcbAA==.',
Ba='Backerrz:BAACLgAFFH8WAAINAAUJ6A/LLAAVAQANAAUJ6A/LLAAVAQAuAAQKfykAAw0ACQnqGzkXAMkCAA0ACQnqGzkXAMkCAA4AAwlAGSw5ANAAAAAA.',
Be='Bearwidit:BAAALgAECgYJCAAAAA==.Beefbrownie:BAAALgAECggJEwAAAA==.Bellezora:BAAALgAECgMJAwABLgAECggJGAACAB4TAA==.Berz:BAAALgAECgUJBwAAAA==.Berzerked:BAABLgAECn8mAAIPAAgJaiOsAQAnAwAPAAgJaiOsAQAnAwAAAA==.Bestboygrip:BAAALgAECgUJBQAAAA==.',
Bi='Bigbubhaa:BAAALgAECgEJAQAAAA==.Bigfluffbutt:BAAALgAECgYJEgAAAA==.Bigsave:BAABLgAECn8aAAICAAgJ4w8hOwAoAQACAAgJ4w8hOwAoAQAAAA==.Bing:BAAALgAECgUJCAAAAA==.Bitterdawn:BAAALgADCgkJCwAAAA==.',
Bl='Blooddruids:BAAALgAECgEJAQAAAA==.Bloodymàry:BAAALgADCgUJBQAAAA==.Bloodynutz:BAACLgAFFH8OAAIQAAMJ+BE9EwDEAAAQAAMJ+BE9EwDEAAAuAAQKfzEAAhAACQnLH60HAK4CABAACQnLH60HAK4CAAAA.Bluethelock:BAAALgAECgUJCAAAAA==.',
Bo='Boogity:BAAALgADCgUJCAAAAA==.',
Br='Branel:BAAALgADCgMJAwAAAA==.Brejevol:BAABLgAECn8ZAAMDAAgJhxE6IwAsAQADAAcJDQ86IwAsAQARAAEJYAh6YgAwAAAAAA==.Brewslee:BAAALgAECgMJAwAAAA==.Brodyty:BAAALgAECgYJCAAAAA==.Brosiedon:BAAALgAECgUJCAAAAA==.',
Bu='Buckett:BAAALgAECgMJAwAAAA==.Buckfuttz:BAAALgAECgIJAgAAAA==.Buffalotrace:BAAALgAECgMJCAAAAA==.Bus:BAACLgAFFH8bAAISAAYJhCVMAACAAgASAAYJhCVMAACAAgAuAAQKfxcAAhIACQlfJnkAANkDABIACQlfJnkAANkDAAEuAAUUCAkOABMAfx8A.Bushrod:BAAALgADCgEJAQAAAA==.',
Ce='Celtykun:BAAALgAECgYJDgAAAA==.',
Ch='Chainmalejr:BAAALgAECgEJAQABLgAFFAMJDAAHAPgZAA==.Chelseyb:BAAALgADCgcJBwAAAA==.Chirón:BAAALgADCgkJDgAAAA==.Chiyukii:BAAALgAECgEJAQAAAA==.',
Ci='Cirillo:BAAALgAECgcJEQABLgAECgkJKAAGAL0cAA==.',
Co='Colorss:BAAALgADCgEJAQAAAA==.Connie:BAABLgAECn8bAAIKAAcJ9xs4KgCoAQAKAAcJ9xs4KgCoAQAAAA==.Cowmein:BAAALgAECgUJEAAAAA==.',
Cr='Cream:BAAALgAECgUJBAAAAA==.Credence:BAAALgADCgIJAgAAAA==.Crystalmommy:BAAALgADCgEJAQAAAA==.',
Cu='Culillo:BAAALgAECgYJEwAAAA==.Cusn:BAAALgADCgEJAQAAAA==.',
Cy='Cynfulsqt:BAAALgADCgUJCAABLgAFFAQJFQAUAAofAA==.',
Da='Dapur:BAAALgADCgkJEgAAAA==.Dayne:BAAALgAECgYJEQABLgAECgcJEAAFAAAAAA==.',
Dc='Dced:BAAALgADCgUJCgABLgAFFAMJDAAHAPgZAA==.',
De='Demontot:BAAALgADCgkJCgAAAA==.',
Dh='Dheginsea:BAAALgAECgYJBgAAAA==.',
Di='Dillexis:BAACLgAFFH8MAAIVAAMJdB0BFAASAQAVAAMJdB0BFAASAQAuAAQKfyEAAhUACQm7GSwIAGgCABUACQm7GSwIAGgCAAAA.Dipindots:BAAALgADCgEJAQAAAA==.Divinemark:BAAALgAECgQJBAAAAA==.',
Do='Donald:BAABLgAECn8uAAMBAAgJyxLNEwClAQABAAgJyxLNEwClAQACAAMJiwc8pwB5AAAAAA==.Doublea:BAAALgAECgYJDQAAAA==.',
Dr='Dragonchest:BAAALgADCgcJCwAAAA==.Dragonswolf:BAABLgAECn8fAAIVAAgJwg1fMwDdAQAVAAgJwg1fMwDdAQAAAA==.Drakeconis:BAAALgADCgUJBQAAAA==.Draksil:BAAALgAECgEJAQAAAA==.Draygon:BAAALgADCgEJAQABLgAFFAUJGAADAJklAA==.Dregon:BAACLgAFFH8YAAIDAAUJmSVbAwAYAgADAAUJmSVbAwAYAgAuAAQKfygAAwMACQlBJl8CAGYDAAMACQlBJl8CAGYDABEAAgnlIZ5aAKUAAAAA.Dreinara:BAAALgAECgMJCAAAAA==.Dresserdemon:BAAALgADCgcJBwAAAA==.Druthenew:BAAALgADCgUJDwAAAA==.',
Du='Dummysezwhut:BAAALgAECgYJDgAAAA==.',
Ea='Earthborn:BAAALgAECgcJAQAAAA==.',
Ei='Eilyn:BAABLgAECn8jAAIWAAcJfhBJRwBwAQAWAAcJfhBJRwBwAQAAAA==.',
El='Elesis:BAAALgADCgIJAgAAAA==.Ellida:BAABLgAECn8aAAIUAAcJMxGOIwC7AQAUAAcJMxGOIwC7AQAAAA==.',
Em='Emastoned:BAAALgAECgYJBwAAAA==.',
Er='Erdran:BAAALgADCgEJAQAAAA==.',
Es='Esterna:BAAALgAECgEJAQAAAA==.',
Et='Ettal:BAABLgAECn8fAAMOAAgJlh99AQBsAgAOAAgJWB59AQBsAgANAAcJyxvSJwDHAQAAAA==.',
Fa='Fangmage:BAAALgAECgYJBwAAAA==.Fazlain:BAABLgAECn8WAAIKAAcJ+hkdJgC8AQAKAAcJ+hkdJgC8AQAAAA==.',
Fe='Felestis:BAAALgAECgYJCAAAAA==.Felnir:BAAALgAECgEJAQABLgAECgcJDwAFAAAAAA==.',
Fi='Fighter:BAAALgADCgEJAQABLgAFFAMJCwAXAA0OAA==.',
Fl='Fluffydragon:BAABLgAECn8lAAMYAAgJ6B0MAwCrAgAYAAgJ6B0MAwCrAgAZAAUJ5wdbKADdAAAAAA==.',
Fr='Friartuck:BAAALgAECgYJBwABLgAECgkJJwAKAHIhAA==.Frosteez:BAAALgAECgEJAQABLgAECgQJDgAFAAAAAA==.Fruit:BAAALgAECgIJAgAAAA==.',
Fu='Furrydeath:BAAALgAECgEJAQAAAA==.Furryem:BAABLgAECn8WAAICAAgJDiWIAgBaAwACAAgJDiWIAgBaAwAAAA==.',
Fy='Fyntos:BAAALgADCgEJAgAAAA==.',
Ga='Galaena:BAAALgAECgcJBwAAAA==.Ganden:BAABLgAECn8kAAIBAAgJ+BgnDAAIAgABAAgJ+BgnDAAIAgAAAA==.Garblebeast:BAAALgADCgUJBQAAAA==.Gatelina:BAABLgAECn8lAAIWAAgJlBdySwAAAgAWAAgJlBdySwAAAgAAAA==.Gatelinka:BAAALgAECgYJCQABLgAECggJJQAYAOgdAA==.Gateto:BAABLgAECn8cAAMMAAgJ1iDnCQDaAgAMAAgJ1iDnCQDaAgAaAAEJ0AfPZQAxAAABLgAECggJJQAYAOgdAA==.',
Ge='Genfindel:BAAALgADCgYJBgAAAA==.Getinthevan:BAAALgADCgcJBwAAAA==.',
Gi='Gidden:BAAALgAECgYJDAAAAA==.Gidgei:BAAALgAECgQJBQAAAA==.',
Go='Gotyamind:BAAALgAECgIJAgAAAA==.Gouken:BAAALgAECgkJBQAAAA==.',
Gr='Grampybobat:BAAALgAECgQJBgAAAA==.Grampycatbob:BAAALgADCgYJBgAAAA==.Grindcore:BAAALgADCgcJDQAAAA==.',
Gw='Gwenneth:BAAALgAECgMJAwAAAA==.',
['Gú']='Gúr:BAAALgADCgkJGwAAAA==.',
Ha='Halfordin:BAAALgADCgYJBgAAAA==.Hamiepally:BAAALgADCgYJBwAAAA==.Harok:BAAALgADCgUJBQAAAA==.Hartley:BAAALgADCgUJCAAAAA==.',
He='Helkalach:BAAALgAECgEJAQAAAA==.Hellravage:BAABLgAECn8dAAIOAAgJ+xIfBQCvAQAOAAgJ+xIfBQCvAQAAAA==.Helsreach:BAAALgADCgMJAgAAAA==.',
Ho='Holeshot:BAAALgADCgYJBgAAAA==.',
Hr='Hruoth:BAAALgADCgIJAgAAAA==.',
Hu='Hunt:BAABLgAECn8XAAMKAAYJWhaQPQBXAQAKAAYJuRWQPQBXAQALAAQJsw3TXQDKAAAAAA==.Huntinbub:BAABLgAECn8lAAMKAAgJ2w8qKwCjAQAKAAgJ2w8qKwCjAQALAAEJzQAsmgAZAAAAAA==.',
['Hó']='Hólyñuts:BAAALgAECgEJAQAAAA==.',
Ic='Icatanktard:BAAALgADCgMJAwAAAA==.',
Im='Implord:BAAALgAECgcJAwAAAA==.',
Ir='Irim:BAAALgAECgEJAQAAAA==.',
Is='Ishun:BAAALgAECgMJAwAAAA==.',
Iv='Ivon:BAAALgAECgEJAQABLgAFFAMJDAAVAHQdAA==.',
Iw='Iwaxmygoat:BAAALgADCgMJAwABLgAECgQJBAAFAAAAAA==.',
Iz='Izanagì:BAACLgAFFH8MAAIbAAUJ6xWoGwA7AQAbAAUJ6xWoGwA7AQAuAAQKfyEAAxsACAmJId4RAPACABsACAmJId4RAPACABwAAglECPphAFoAAAAA.Izlaar:BAAALgADCgkJEwAAAA==.Izzytt:BAAALgAECgUJBQAAAA==.',
Ja='Jacenskie:BAABLgAECn8hAAIVAAgJxRErMwDeAQAVAAgJxRErMwDeAQAAAA==.Jacob:BAAALgAECgQJCQAAAA==.Jadedbabe:BAAALgAECgEJAQAAAA==.Jaderoks:BAAALgAECgUJEgAAAA==.Janthis:BAAALgADCgUJBgAAAA==.',
Je='Jermaxus:BAAALgADCgEJAQAAAA==.Jexter:BAAALgADCgIJAgAAAA==.',
Ji='Jimmyjams:BAAALgADCgEJAQABLgAFFAMJDAAHAPgZAA==.',
Jn='Jneut:BAAALgADCgEJAQAAAA==.',
Jo='Joppa:BAAALgAECgIJAgABLgAFFAcJFQAUAAAZAA==.Joyvimon:BAAALgAECgYJDgAAAA==.',
Ju='Jugernaut:BAAALgADCgYJDQAAAA==.',
Ka='Kamala:BAAALgAECgEJAQAAAA==.Kaniicus:BAAALgADCgMJBQAAAA==.Karavin:BAABLgAECn8aAAIdAAgJdAvBRQBqAQAdAAgJdAvBRQBqAQAAAA==.Kayyta:BAAALgADCgYJBgAAAA==.',
Ke='Keirybear:BAAALgADCgcJCgABLgAECgYJEgAFAAAAAA==.',
Kh='Khal:BAACLgAFFH8VAAMEAAYJzhtqBwC3AQAEAAYJzhtqBwC3AQAZAAIJEgejBgClAAAuAAQKfxUAAxkACQkBILsOAO8BAAQABwmCGu8XABMCABkABgnGI7sOAO8BAAAA.Khornedaemon:BAAALgADCgEJAQAAAA==.',
Ki='Kickstarter:BAAALgAFFAEJAQAAAA==.Kikuarse:BAAALgAECgUJBQAAAA==.Kiy:BAAALgAECggJCAAAAA==.',
Kn='Knìghtmare:BAAALgADCgcJEwAAAA==.',
Ko='Kobal:BAAALgAECgQJBAAAAA==.',
Kr='Krakenlock:BAAALgAECgUJDAAAAA==.Kronas:BAAALgAECgUJCQAAAA==.',
Ku='Kurosaki:BAABLgAECn8ZAAIbAAkJghuFKwCKAQAbAAkJghuFKwCKAQAAAA==.',
La='Lazyheal:BAACLgAFFH8LAAQXAAMJDQ6nDACZAAAXAAIJVhSnDACZAAAeAAEJeQFqKQBCAAAUAAIJfAB5IgBAAAAuAAQKfx8ABBcACQmFG4kEAMoCABcACQmFG4kEAMoCAB4ABAlUBrA/ALEAABQAAgkgBihYAF0AAAAA.Lazytank:BAAALgAECgMJBQABLgAFFAMJCwAXAA0OAA==.',
Le='Leetsteve:BAAALgADCgYJCwAAAA==.Legacy:BAAALgADCgEJAgAAAA==.Leigor:BAACLgAFFH8YAAIXAAUJEhxvBACLAQAXAAUJEhxvBACLAQAuAAQKfyoAAhcACQnbIKYDAB8DABcACQnbIKYDAB8DAAAA.Leomoon:BAAALgAECgMJBAAAAA==.Leshy:BAAALgAECgYJBgAAAA==.Levite:BAAALgAECgUJDgAAAA==.',
Li='Lilara:BAAALgAECgYJEwAAAA==.Lionknite:BAABLgAECn8nAAIdAAkJsxqTEgBnAgAdAAkJsxqTEgBnAgAAAA==.Liontabu:BAAALgAECgQJBgAAAA==.Liteshocklet:BAAALgAECgEJAgABLgAFFAMJCwAXAA0OAA==.Littledung:BAAALgADCgYJCgAAAA==.',
Lo='Looting:BAABLgAECn8XAAIfAAcJQxELBwB2AQAfAAcJQxELBwB2AQAAAA==.',
Lu='Lustdeez:BAAALgADCgYJCQAAAA==.',
['Lã']='Lãdyrift:BAABLgAECn8gAAMCAAgJdgsCXQA7AQACAAgJdgsCXQA7AQAgAAEJKAKrLQAfAAAAAA==.',
Ma='Mageko:BAAALgAECgEJBgAAAA==.Magetot:BAAALgADCgEJAQABLgADCgkJCgAFAAAAAA==.Makarion:BAABLgAECn8WAAIKAAgJxAu1NQB2AQAKAAgJxAu1NQB2AQAAAA==.Malvina:BAAALgAFFAEJAQAAAA==.Maoli:BAAALgAECgQJDQAAAA==.Marohen:BAAALgADCgYJBgAAAA==.Mauka:BAABLgAECn8YAAMBAAgJ8g/VOABUAQABAAYJwRPVOABUAQACAAYJ3gusRgD4AAAAAA==.Mauzer:BAAALgAECgEJAQABLgAECgcJHgAcAKsXAA==.',
Mc='Mcfallen:BAAALgAECgIJAgAAAA==.Mcksquizy:BAABLgAECn8lAAIdAAgJeB0PMAB3AgAdAAgJeB0PMAB3AgAAAA==.Mcscrotie:BAAALgAECggJEAAAAA==.',
Me='Mes:BAABLgAECn8jAAIaAAkJfxvfCABNAgAaAAkJfxvfCABNAgAAAA==.',
Mi='Mimmi:BAAALgAECgUJDwABLgAECgcJHgAcAKsXAA==.Mishri:BAABLgAECn8eAAIbAAkJTyMqEAD9AgAbAAkJTyMqEAD9AgAAAA==.',
Mo='Moonsorrow:BAAALgADCgMJAwAAAA==.Moparcast:BAAALgADCgEJAQABLgADCgUJBQAFAAAAAA==.Moriphael:BAAALgADCgcJCQAAAA==.Moritura:BAABLgAECn8eAAMcAAcJqxdiDwCMAQAcAAcJ4RZiDwCMAQAhAAIJHhq9GwBGAAAAAA==.',
My='Mykana:BAABLgAECn8XAAMWAAYJPwgQigDZAAAWAAYJPwgQigDZAAAGAAQJ0wIpNgBrAAAAAA==.Myodieboy:BAAALgADCgEJAQAAAA==.',
Na='Nakabeam:BAABLgAECn8kAAIbAAkJAxTZTgAMAQAbAAkJAxTZTgAMAQAAAA==.Nakatwin:BAABLgAECn8YAAIbAAcJKxXhWACXAQAbAAcJKxXhWACXAQABLgAECgkJJAAbAAMUAA==.Naklek:BAABLgAECn8hAAMgAAgJBB6SBgCOAgAgAAgJBB6SBgCOAgATAAEJYgthNAAkAAAAAA==.Navic:BAAALgAECgEJAQAAAA==.',
Ne='Newtt:BAAALgADCgUJBgABLgADCgcJCQAFAAAAAA==.',
Ni='Nicked:BAECLgAFFH8MAAIKAAUJVBivEwBNAQAKAAUJVBivEwBNAQAuAAQKfyMAAwoACQmEH5wOAMYCAAoACQmEH5wOAMYCAAsABAl0Bk5pAJkAAAAA.Nika:BAAALgAECgEJAQAAAA==.Niraleth:BAAALgAECgMJAwAAAA==.Nistik:BAABLgAECn8aAAMXAAcJsgY7JwAPAQAXAAcJsgY7JwAPAQAUAAEJ0wHaawAaAAAAAA==.',
No='Nozomí:BAAALgAECgUJBQAAAA==.',
Ob='Obergefel:BAAALgADCgEJAQAAAA==.',
Op='Ophiuchus:BAAALgAECgcJDwAAAA==.',
Or='Orcdung:BAAALgADCgEJAQAAAA==.',
Oz='Ozymandias:BAAALgADCgEJAQAAAA==.',
Pa='Paldente:BAAALgAECgcJEgAAAA==.Pamelina:BAAALgADCgUJFAAAAA==.Pandaexpress:BAAALgADCgkJCQABLgAFFAMJDAAVAHQdAA==.Panzerfäust:BAAALgAECgQJDgAAAA==.Pawrina:BAAALgAECgkJEQAAAA==.',
Pe='Pernicious:BAAALgAECgQJBAAAAA==.Peskadote:BAAALgADCgMJAwAAAA==.Pestis:BAAALgADCgkJDwAAAA==.Pewpewbambam:BAAALgAECgUJBQAAAA==.',
Ph='Phaoe:BAAALgADCgUJBQAAAA==.Phillis:BAABLgAECn8cAAMWAAcJfhLhUABUAQAWAAcJfhLhUABUAQAiAAQJzgjcQQCqAAAAAA==.',
Pi='Pilfering:BAAALgADCgQJBAAAAA==.',
Pl='Plumpt:BAAALgAECgcJEwAAAA==.',
Pr='Prey:BAAALgADCgYJBgAAAA==.',
Pu='Pulchritude:BAAALgAECgcJDgAAAA==.Punchem:BAAALgADCgcJBwAAAA==.Purex:BAABLgAECn8dAAIfAAkJKQYwCgCSAQAfAAkJKQYwCgCSAQAAAA==.',
Py='Pylonshots:BAAALgAECgEJAQAAAA==.',
Ra='Raivah:BAAALgADCgMJAwAAAA==.Randomyzed:BAABLgAECn8UAAIGAAgJ3hrZBQAQAgAGAAgJ3hrZBQAQAgAAAA==.Rathus:BAABLgAECn8cAAINAAcJZR2/LwBOAgANAAcJZR2/LwBOAgAAAA==.Rawdata:BAACLgAFFH8GAAIMAAMJRQQBKgCoAAAMAAMJRQQBKgCoAAAuAAQKfyYAAyMACAlVFKMJAIABACMACAlVFKMJAIABAAwACAkvD1FCAHgBAAAA.Razenka:BAAALgAECgIJAgAAAA==.',
Re='Reaperdeath:BAAALgAECgEJAQAAAA==.Rebecca:BAABLgAECn8gAAIKAAgJpxdZOQBnAQAKAAgJpxdZOQBnAQAAAA==.Rebeka:BAABLgAECn8cAAIiAAgJ1x0cBgDAAgAiAAgJ1x0cBgDAAgABLgAECggJIAAKAKcXAA==.Regantze:BAAALgAECgUJCAAAAA==.Reliun:BAAALgAECgcJEAAAAA==.Reniel:BAAALgADCgYJBgABLgAECgYJHgAGAB8SAA==.Ressie:BAAALgAECgQJCQAAAA==.Reverendlion:BAAALgAECggJDgAAAA==.',
Ro='Rogosh:BAAALgAECgEJAQAAAA==.',
Ru='Ruemor:BAAALgADCgYJFgAAAA==.',
Ry='Ryblade:BAAALgAFFAEJAQABLgAFFAMJCQAWANcHAA==.',
Sa='Saiko:BAAALgAECgMJAwABLgAFFAMJDAANADMJAA==.Saladcake:BAAALgAECgYJCgAAAA==.Salleane:BAABLgAECn8YAAIWAAgJtBU1XgDJAQAWAAgJtBU1XgDJAQAAAA==.Sampal:BAABLgAECn8lAAIGAAgJfBsFBgAJAgAGAAgJfBsFBgAJAgAAAA==.Sampriest:BAAALgAECgYJDgABLgAECggJJQAGAHwbAA==.Samwield:BAACLgAFFH8LAAIkAAQJVhotCQBgAQAkAAQJVhotCQBgAQAuAAQKfzYABCQACQk5IdgHABMDACQACQk5IdgHABMDAB8AAwlCGEoTAM0AACUAAQnVCpYTADIAAAAA.Sanchoe:BAAALgAECgcJDAAAAA==.Sanzo:BAAALgADCgEJAQAAAA==.',
Se='Seireitei:BAABLgAECn8gAAIMAAgJmBjDEQArAgAMAAgJmBjDEQArAgAAAA==.Selaheal:BAABLgAECn8lAAIUAAgJ8hb5DgDdAQAUAAgJ8hb5DgDdAQAAAA==.Seraath:BAACLgAFFH8YAAIhAAUJMhm2AQAnAQAhAAUJMhm2AQAnAQAuAAQKfyYAAyEACQn7IZAAAGQDACEACQn7IZAAAGQDABsAAQkAAIXSAE4AAAAA.Serath:BAAALgAECgYJBwAAAA==.',
Sh='Shadowskull:BAAALgADCgcJDAAAAA==.Shadwkllr:BAAALgAECgQJDQAAAA==.Shamloo:BAAALgADCgEJAQAAAA==.Shimwow:BAAALgAECgMJAwAAAA==.Shnood:BAAALgAECgYJDQAAAA==.Shortie:BAAALgADCggJDwAAAA==.',
Sk='Ski:BAAALgAECgIJAgAAAA==.Skies:BAAALgAECgEJAgABLgAECgcJCAAFAAAAAA==.',
Sn='Snowhite:BAAALgAECgIJAgAAAA==.',
So='Soshi:BAAALgAECgQJBAAAAA==.',
Sp='Speckle:BAAALgADCgkJEQAAAA==.Spooqe:BAAALgADCgcJCwAAAA==.',
St='Stabbie:BAAALgADCgcJBwAAAA==.Stahn:BAAALgAECgUJBQAAAA==.Stdoubleds:BAAALgAECgQJBAAAAA==.Stervana:BAACLgAFFH8IAAIEAAQJjBq5EABNAQAEAAQJjBq5EABNAQAuAAQKfysAAgQACQliIOEDAFoDAAQACQliIOEDAFoDAAAA.Sterzephyr:BAAALgAECgYJBgABLgAFFAQJCAAEAIwaAA==.Stickytoes:BAAALgADCgYJBgAAAA==.Stormyknight:BAABLgAECn8pAAMYAAgJNw+GDwBHAQAYAAgJNw+GDwBHAQAZAAYJ5QsmDQC+AAAAAA==.',
Su='Sunwrath:BAAALgAECgcJCAAAAA==.Susmonk:BAAALgAECgQJBQAAAA==.Suspectedd:BAABLgAFFH8HAAIHAAMJyQxbLwD5AAAHAAMJyQxbLwD5AAABLgAFFAUJFwAIAOEjAA==.Suswar:BAACLgAFFH8XAAIIAAUJ4SNRAwCSAQAIAAUJ4SNRAwCSAQAuAAQKfykAAggACQlMJJoAALgDAAgACQlMJJoAALgDAAAA.Suvulaan:BAABLgAECn8pAAMYAAgJaAfSEQAgAQAYAAcJ3gfSEQAgAQAEAAIJggF8ZAAhAAAAAA==.',
Sw='Swifix:BAAALgAECgEJAQAAAA==.',
Ta='Tacostand:BAACLgAFFH8UAAIbAAUJERa5EABJAQAbAAUJERa5EABJAQAuAAQKfysAAhsACQlNIOUHAEwDABsACQlNIOUHAEwDAAAA.Tamarlane:BAAALgADCgIJAgAAAA==.Tatoo:BAABLgAECn8nAAIKAAkJciGGBADrAgAKAAkJciGGBADrAgAAAA==.',
Te='Teeice:BAABLgAECn8bAAIfAAkJIgyeBADGAQAfAAkJIgyeBADGAQAAAA==.Teo:BAABLgAECn8YAAIUAAgJfA3AFgCJAQAUAAgJfA3AFgCJAQAAAA==.Terian:BAAALgAECgkJBQAAAA==.',
Th='Thaodan:BAABLgAECn8aAAIaAAkJ/xBcGQCEAQAaAAkJ/xBcGQCEAQAAAA==.Thekan:BAABLgAECn8XAAIcAAgJIBQ7DAC+AQAcAAgJIBQ7DAC+AQAAAA==.Theriot:BAABLgAECn8jAAMWAAkJmht4GAA3AgAWAAkJmht4GAA3AgAiAAEJMwhFoAAoAAAAAA==.Thianá:BAAALgAECgQJCgAAAA==.Thüclides:BAAALgAECgcJAgAAAA==.',
Ti='Tikidragoona:BAAALgAECgIJAgAAAA==.Tinkerspell:BAABLgAECn8YAAICAAgJHhO7JACjAQACAAgJHhO7JACjAQAAAA==.Tinkiebella:BAAALgADCgMJAwABLgAECggJGAACAB4TAA==.Tiredinras:BAAALgADCgIJAgAAAA==.',
To='Tobivoker:BAAALgAECgEJAQAAAA==.Toosus:BAABLgAFFH8PAAIQAAQJkSH4DgD1AAAQAAQJkSH4DgD1AAABLgAFFAUJFwAIAOEjAA==.Toppers:BAAALgAECgMJAwAAAA==.Topps:BAACLgAFFH8HAAIjAAQJYQfVAwArAQAjAAQJYQfVAwArAQAuAAQKfxoAAiMACAkmFGwKACoCACMACAkmFGwKACoCAAAA.Toric:BAAALgADCgYJBgAAAA==.Toridian:BAAALgAECgIJAwAAAA==.Torinus:BAAALgADCgMJAwAAAA==.Totec:BAAALgAECgUJCgAAAA==.',
Tr='Trolldung:BAAALgADCgkJDQAAAA==.Truffaut:BAAALgADCgUJBgAAAA==.',
Tt='Tturtle:BAACLgAFFH8KAAIWAAQJpQfKIwAdAQAWAAQJpQfKIwAdAQAuAAQKfyUAAhYACQl4Fd4wAF8CABYACQl4Fd4wAF8CAAAA.',
Tu='Tuss:BAAALgADCgEJAgAAAA==.',
Tw='Twoblock:BAAALgADCgEJAgAAAA==.',
Ty='Tyariel:BAAALgADCgYJBgAAAA==.Tystraz:BAAALgAECgYJCAAAAA==.',
Ud='Udúnnaur:BAAALgADCggJDgAAAA==.',
Um='Umisle:BAAALgADCgQJBAAAAA==.',
Un='Undermage:BAAALgADCgQJBAAAAA==.Unholysam:BAAALgAECgYJBgABLgAFFAQJCwAkAFYaAA==.',
Va='Valmora:BAAALgADCgMJAwAAAA==.Valstad:BAAALgADCgIJAgAAAA==.',
Ve='Vector:BAAALgAECgYJCAAAAA==.Velata:BAABLgAECn8YAAIHAAUJBQo/ngDWAAAHAAUJBQo/ngDWAAAAAA==.Verdugo:BAAALgAECgMJBQAAAA==.Verite:BAAALgAECgcJEwAAAA==.',
Vi='Vicar:BAAALgADCggJDgAAAA==.Vice:BAAALgADCgEJAQAAAA==.Violencê:BAABLgAECn8WAAIVAAgJxRjpEADsAQAVAAgJxRjpEADsAQAAAA==.',
Vo='Vodka:BAAALgADCgcJFQAAAA==.Voelva:BAAALgADCgQJBAAAAA==.Voidedge:BAABLgAECn8hAAMOAAcJyQ8HFQCoAAANAAcJQA0OdgBxAQAOAAUJDBEHFQCoAAAAAA==.Voidgazer:BAAALgAECgYJDAAAAA==.Voidsyn:BAAALgAECgMJAwAAAA==.Voltage:BAAALgAECgEJAQAAAA==.',
We='Wes:BAABLgAECn8gAAIfAAkJwRU5AgBJAgAfAAkJwRU5AgBJAgAAAA==.',
Wi='Wildlettuce:BAAALgADCgEJAQAAAA==.Willybcastin:BAAALgAFFAEJAQABLgAFFAcJGQAdANMiAA==.Willybwankin:BAACLgAFFH8ZAAIdAAcJ0yKbAABrAgAdAAcJ0yKbAABrAgAuAAQKfyYAAh0ACQkwJsoAAOEDAB0ACQkwJsoAAOEDAAAA.',
Wo='Wolfiekins:BAAALgADCgUJBQAAAA==.Wowgazm:BAAALgAECgcJEwAAAA==.',
Wy='Wyvern:BAAALgAECgcJDwAAAA==.',
Xa='Xanthion:BAAALgADCgEJAQAAAA==.Xarinn:BAAALgADCgEJAQAAAA==.',
Yo='Yodapopz:BAAALgADCgYJBgAAAA==.',
Za='Zacarly:BAAALgAECgQJCgAAAA==.Zalmage:BAABLgAECn8uAAMHAAkJXhplEACXAgAHAAkJXhplEACXAgAmAAIJ5wlpFwBeAAAAAA==.Zantack:BAAALgAECgUJBQAAAA==.',
Ze='Zemos:BAAALgADCgMJAwAAAA==.Zeseroth:BAACLgAFFH8UAAIWAAUJjCBmBwB7AQAWAAUJjCBmBwB7AQAuAAQKfyQAAhYACQmbIysDAKMDABYACQmbIysDAKMDAAAA.Zeserotho:BAAALgAECgQJBgAAAA==.',
Zy='Zyn:BAACLgAFFH8MAAIXAAQJ0iRcAwCmAQAXAAQJ0iRcAwCmAQAuAAQKfyUAAxcACQndIBIGAO4CABcACQndIBIGAO4CABQABAllE4JCAGkAAAAA.',
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

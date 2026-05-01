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

local lookup = {'Druid-Restoration','Druid-Balance','Monk-Mistweaver','Evoker-Augmentation','Unknown-Unknown','Paladin-Protection','Mage-Frost','Hunter-BeastMastery','Hunter-Survival','Hunter-Marksmanship','Shaman-Restoration','Warlock-Demonology','Warlock-Destruction','Warrior-Arms','DeathKnight-Blood','Monk-Brewmaster','Druid-Guardian','Priest-Shadow','Warrior-Fury','Monk-Windwalker','Paladin-Retribution','Priest-Holy','Evoker-Preservation','Evoker-Devastation','Shaman-Elemental','DemonHunter-Devourer','DemonHunter-Havoc','DeathKnight-Unholy','Priest-Discipline','DemonHunter-Vengeance','Druid-Feral','Rogue-Assassination','Shaman-Enhancement','Paladin-Holy','Rogue-Subtlety','Rogue-Outlaw','Warrior-Protection','Mage-Arcane',}
local provider = {region='US',realm='Bladefist',name='US',type='weekly',zone=46,date='2026-05-01',data={Ad='Adrianmonk:BAAALgAECgYJEgAAAA==.',
Ae='Aezu:BAACLgAFFH8TAAMBAAUJThJjFQDtAAABAAMJ3RRjFQDtAAACAAMJvhy1FAC9AAAuAAQKfykAAwIACQmTI5EQAJsCAAIACAmGJJEQAJsCAAEABwlIHlAjAC8CAAAA.',
Ai='Ailuria:BAABLgAECn8XAAIDAAYJ4iRpBQB6AgADAAYJ4iRpBQB6AgAAAA==.Airam:BAAALgADCgkJCQAAAA==.Aitharen:BAAALgADCgUJBAAAAA==.',
Al='Alaura:BAAALgADCgQJBAAAAA==.Albaz:BAABLgAECn8UAAIEAAgJzA1MIwCjAQAEAAgJzA1MIwCjAQAAAA==.Alepacino:BAAALgAECgEJAgABLgAECgEJAgAFAAAAAA==.Alikith:BAABLgAECn8XAAIGAAYJHxL7GABMAQAGAAYJHxL7GABMAQAAAA==.Alun:BAAALgADCgYJBgAAAA==.Alynia:BAAALgAECgEJAQAAAA==.',
Am='Ambrìel:BAABLgAECn8cAAIHAAcJBwsfTgBGAQAHAAcJBwsfTgBGAQAAAA==.Amyloid:BAAALgADCgEJAQAAAA==.Amèlia:BAACLgAFFH8IAAMBAAMJzghIHQC1AAABAAMJzghIHQC1AAACAAIJwwLDFwB5AAAuAAQKfyEAAwEACQn0Fw4QABICAAEACQn0Fw4QABICAAIAAQlKHcI7AFcAAAAA.',
An='Angando:BAAALgAECgcJEAAAAA==.Anjelik:BAAALgADCgYJBgAAAA==.Anneliesë:BAAALgADCgUJDwAAAA==.',
Ao='Aozora:BAAALgAECgYJDAAAAA==.',
Ar='Aric:BAAALgADCgQJBAAAAA==.Arrows:BAAALgADCgcJBwAAAA==.Artemidoros:BAABLgAECn8ZAAQIAAYJGyEYIQA/AgAIAAYJGSEYIQA/AgAJAAYJixoRDACdAQAKAAEJmgrOigAwAAAAAA==.',
As='Ashkaari:BAACLgAFFH8JAAILAAMJow/nGQDCAAALAAMJow/nGQDCAAAuAAQKfxUAAgsACQl2FmMnAPQBAAsACQl2FmMnAPQBAAAA.Asuná:BAAALgAECggJEgAAAA==.',
Au='Aurelyus:BAAALgAECgMJAwAAAA==.Aurevior:BAAALgAECgYJDgAAAA==.',
Az='Azariyah:BAAALgADCgQJBAAAAA==.Azooma:BAAALgADCgkJEAAAAA==.Azshaderr:BAAALgAECgYJBgAAAA==.Azshaure:BAAALgAECgQJBwAAAA==.Azu:BAAALgAECgEJAQABLgAFFAUJEwABAE4SAA==.',
Ba='Backerrz:BAACLgAFFH8RAAIMAAUJuAq/IQAaAQAMAAUJuAq/IQAaAQAuAAQKfykAAwwACQnqGzkXAMkCAAwACQnqGzkXAMkCAA0AAwlAGS85ANAAAAAA.',
Be='Bearwidit:BAAALgAECgYJCAAAAA==.Beefbrownie:BAAALgAECgcJEQAAAA==.Bellezora:BAAALgADCgQJBAABLgAECgcJEAAFAAAAAA==.Berz:BAAALgAECgUJBgAAAA==.Berzerked:BAABLgAECn8kAAIOAAgJxSKsAQAnAwAOAAgJxSKsAQAnAwAAAA==.Bestboygrip:BAAALgADCgUJBQAAAA==.',
Bi='Bigbubhaa:BAAALgAECgEJAQAAAA==.Bigfluffbutt:BAAALgAECgUJDAAAAA==.Bigsave:BAAALgAECgcJEgAAAA==.Bing:BAAALgAECgUJCAAAAA==.Bitterdawn:BAAALgADCgkJCwAAAA==.',
Bl='Blooddruids:BAAALgAECgEJAQAAAA==.Bloodymàry:BAAALgADCgUJBQAAAA==.Bloodynutz:BAACLgAFFH8LAAIPAAMJ4RGADQDKAAAPAAMJ4RGADQDKAAAuAAQKfzAAAg8ACQnLHzsDACMCAA8ACQnLHzsDACMCAAAA.Bluethelock:BAAALgAECgUJCAAAAA==.',
Bo='Boogity:BAAALgADCgUJCAAAAA==.',
Br='Branel:BAAALgADCgMJAwAAAA==.Brejevol:BAABLgAECn8YAAIDAAcJDQ8fGgAzAQADAAcJDQ8fGgAzAQAAAA==.Brewslee:BAAALgAECgMJAwAAAA==.Brodyty:BAAALgAECgYJCAAAAA==.Brosiedon:BAAALgAECgMJBgAAAA==.',
Bu='Buckett:BAAALgADCgYJDAAAAA==.Buffalotrace:BAAALgAECgMJCAAAAA==.Bus:BAACLgAFFH8XAAIQAAYJQiVMAACAAgAQAAYJQiVMAACAAgAuAAQKfxcAAhAACQlfJnkAANkDABAACQlfJnkAANkDAAEuAAUUBwkNABEAfiEA.Bushrod:BAAALgADCgEJAQAAAA==.',
Ce='Celtykun:BAAALgAECgQJCAAAAA==.',
Ch='Chainmalejr:BAAALgADCgkJCQABLgAECgQJBAAFAAAAAA==.Chelseyb:BAAALgADCgcJBwAAAA==.Chirón:BAAALgADCgkJDgAAAA==.Chiyukii:BAAALgAECgEJAQAAAA==.',
Ci='Cirillo:BAAALgAECgcJEQABLgAECgkJJAAGAL0cAA==.',
Co='Colorss:BAAALgADCgEJAQAAAA==.Connie:BAABLgAECn8VAAIIAAcJ9xuSIACeAQAIAAcJ9xuSIACeAQAAAA==.Cowmein:BAAALgAECgUJCAAAAA==.',
Cr='Cream:BAAALgAECgUJBAAAAA==.Credence:BAAALgADCgIJAgAAAA==.Crystalmommy:BAAALgADCgEJAQAAAA==.',
Cu='Culillo:BAAALgAECgYJCwAAAA==.Cusn:BAAALgADCgEJAQAAAA==.',
Cy='Cynfulsqt:BAAALgADCgUJCAABLgAFFAQJEQASAJwaAA==.',
Da='Dapur:BAAALgADCgkJEgAAAA==.Dayne:BAAALgAECgYJCwABLgAECgYJDgAFAAAAAA==.',
Dc='Dced:BAAALgADCgUJCgABLgAECgQJBAAFAAAAAA==.',
De='Demontot:BAAALgADCgkJCgAAAA==.',
Dh='Dheginsea:BAAALgAECgYJBgAAAA==.',
Di='Dillexis:BAACLgAFFH8JAAITAAMJnBuBDAAqAQATAAMJnBuBDAAqAQAuAAQKfyEAAhMACQm7GQcEAIkCABMACQm7GQcEAIkCAAAA.Dipindots:BAAALgADCgEJAQAAAA==.',
Do='Donald:BAABLgAECn8lAAMCAAgJzRITDgCtAQACAAgJzRITDgCtAQABAAMJiwc/pwB5AAAAAA==.Doublea:BAAALgAECgYJDAAAAA==.',
Dr='Dragonchest:BAAALgADCgcJCwAAAA==.Dragonswolf:BAABLgAECn8ZAAITAAgJog1gMwDdAQATAAgJog1gMwDdAQAAAA==.Drakeconis:BAAALgADCgUJBQAAAA==.Draksil:BAAALgADCgYJCgAAAA==.Draygon:BAAALgADCgEJAQABLgAFFAUJEwADAAslAA==.Dregon:BAACLgAFFH8TAAIDAAUJCyUNAgAQAgADAAUJCyUNAgAQAgAuAAQKfygAAwMACQlBJmACAGYDAAMACQlBJmACAGYDABQAAgnlIZxaAKUAAAAA.Dreinara:BAAALgAECgMJBQAAAA==.Dresserdemon:BAAALgADCgcJBwAAAA==.Druthenew:BAAALgADCgUJDwAAAA==.',
Du='Dummysezwhut:BAAALgAECgQJCAAAAA==.',
Ea='Earthborn:BAAALgAECgcJAQAAAA==.',
Ei='Eilyn:BAABLgAECn8dAAIVAAcJbw5rPABVAQAVAAcJbw5rPABVAQAAAA==.',
El='Elesis:BAAALgADCgIJAgAAAA==.Ellida:BAABLgAECn8aAAISAAcJMxGPIwC7AQASAAcJMxGPIwC7AQAAAA==.',
Em='Emastoned:BAAALgAECgUJBQAAAA==.',
Er='Erdran:BAAALgADCgEJAQAAAA==.',
Es='Esterna:BAAALgAECgEJAQAAAA==.',
Et='Ettal:BAABLgAECn8XAAMNAAcJWiDTBQBlAQAMAAcJwRtFGwDRAQANAAUJOR7TBQBlAQAAAA==.',
Fa='Fangmage:BAAALgAECgYJBwAAAA==.Fazlain:BAAALgAECgYJEAAAAA==.',
Fe='Felestis:BAAALgAECgUJBQAAAA==.Felnir:BAAALgAECgEJAQABLgAECgcJDAAFAAAAAA==.',
Fi='Fighter:BAAALgADCgEJAQABLgAFFAMJCAAWACkUAA==.',
Fl='Fluffydragon:BAABLgAECn8jAAMXAAgJahq4AwBRAgAXAAgJahq4AwBRAgAYAAUJ5wdgKADdAAAAAA==.',
Fr='Friartuck:BAAALgAECgYJBwABLgAECggJHgAIANkfAA==.Frosteez:BAAALgADCgEJAQABLgAECgQJCAAFAAAAAA==.Fruit:BAAALgAECgIJAgAAAA==.',
Fu='Furrydeath:BAAALgAECgEJAQAAAA==.Furryem:BAAALgAECgcJEQAAAA==.',
Fy='Fyntos:BAAALgADCgEJAgAAAA==.',
Ga='Galaena:BAAALgAECgcJBwAAAA==.Ganden:BAABLgAECn8dAAICAAcJmBYnDwCeAQACAAcJmBYnDwCeAQAAAA==.Garblebeast:BAAALgADCgUJBQAAAA==.Gatelina:BAABLgAECn8fAAIVAAgJWxRxSwAAAgAVAAgJWxRxSwAAAgAAAA==.Gatelinka:BAAALgAECgMJAwABLgAECggJIwAXAGoaAA==.Gateto:BAABLgAECn8cAAMLAAgJ1iDoCQDaAgALAAgJ1iDoCQDaAgAZAAEJ0AemUQAyAAABLgAECggJIwAXAGoaAA==.',
Ge='Genfindel:BAAALgADCgYJBgAAAA==.Getinthevan:BAAALgADCgcJBwAAAA==.',
Gi='Gidden:BAAALgAECgYJDAAAAA==.Gidgei:BAAALgAECgQJBQAAAA==.',
Go='Gotyamind:BAAALgAECgIJAgAAAA==.Gouken:BAAALgAECgkJAQAAAA==.',
Gr='Grampybobat:BAAALgAECgQJBgAAAA==.Grampycatbob:BAAALgADCgYJBgAAAA==.Grindcore:BAAALgADCgYJBgAAAA==.',
Gw='Gwenneth:BAAALgAECgMJAwAAAA==.',
['Gú']='Gúr:BAAALgADCgkJGwAAAA==.',
Ha='Halfordin:BAAALgADCgYJBgAAAA==.Hamiepally:BAAALgADCgYJBwAAAA==.Harok:BAAALgADCgUJBQAAAA==.Hartley:BAAALgADCgUJCAAAAA==.',
He='Helkalach:BAAALgAECgEJAQAAAA==.Hellravage:BAABLgAECn8cAAINAAgJ5RJsAwC6AQANAAgJ5RJsAwC6AQAAAA==.',
Ho='Holeshot:BAAALgADCgYJBgAAAA==.',
Hr='Hruoth:BAAALgADCgIJAgAAAA==.',
Hu='Hunt:BAAALgAECgYJEgAAAA==.Huntinbub:BAABLgAECn8cAAMIAAcJmA+4LABfAQAIAAcJmA+4LABfAQAKAAEJzQAfmgAZAAAAAA==.',
['Hó']='Hólyñuts:BAAALgAECgEJAQAAAA==.',
Ic='Icatanktard:BAAALgADCgMJAwAAAA==.',
Im='Implord:BAAALgAECgcJAwAAAA==.',
Is='Ishun:BAAALgAECgMJAwAAAA==.',
Iv='Ivon:BAAALgADCgkJIQABLgAFFAMJCQATAJwbAA==.',
Iw='Iwaxmygoat:BAAALgADCgMJAwABLgAECgQJBAAFAAAAAA==.',
Iz='Izanagì:BAACLgAFFH8HAAIaAAUJ0w0KHwDfAAAaAAUJ0w0KHwDfAAAuAAQKfyEAAxoACAmJIeIRAPACABoACAmJIeIRAPACABsAAglECPdhAFoAAAAA.Izlaar:BAAALgADCgkJEwAAAA==.Izzytt:BAAALgAECgUJBQAAAA==.',
Ja='Jacenskie:BAABLgAECn8gAAITAAgJARE6GABuAQATAAgJARE6GABuAQAAAA==.Jacob:BAAALgAECgQJCQAAAA==.Jadedbabe:BAAALgADCgkJCgAAAA==.Jaderoks:BAAALgAECgUJEgAAAA==.Janthis:BAAALgADCgUJBgAAAA==.',
Je='Jermaxus:BAAALgADCgEJAQAAAA==.Jexter:BAAALgADCgIJAgAAAA==.',
Ji='Jimmyjams:BAAALgADCgEJAQABLgAECgQJBAAFAAAAAA==.',
Jn='Jneut:BAAALgADCgEJAQAAAA==.',
Jo='Joppa:BAAALgAECgIJAgABLgAECgcJDAAFAAAAAA==.Joyvimon:BAAALgAECgUJCAAAAA==.',
Ju='Jugernaut:BAAALgADCgYJDQAAAA==.',
Ka='Kamala:BAAALgAECgEJAQAAAA==.Kaniicus:BAAALgADCgMJBQAAAA==.Karavin:BAABLgAECn8aAAIcAAgJdAtqOgBRAQAcAAgJdAtqOgBRAQAAAA==.Kayyta:BAAALgADCgYJBgAAAA==.',
Ke='Keirybear:BAAALgADCgcJCgABLgAECgYJEgAFAAAAAA==.',
Kh='Khal:BAACLgAFFH8VAAMEAAYJzhvxAwDCAQAEAAYJzhvxAwDCAQAYAAIJEgegBgClAAAuAAQKfxUAAxgACQkBILkOAO8BAAQABwmCGvQXABMCABgABgnGI7kOAO8BAAAA.',
Ki='Kickstarter:BAAALgAECgcJCAAAAA==.Kikuarse:BAAALgAECgUJBQAAAA==.Kiy:BAAALgADCgcJCwAAAA==.',
Kn='Knìghtmare:BAAALgADCgcJEwAAAA==.',
Ko='Kobal:BAAALgAECgQJBAAAAA==.',
Kr='Krakenlock:BAAALgAECgUJDAAAAA==.Kronas:BAAALgAECgUJCAAAAA==.',
Ku='Kurosaki:BAABLgAECn8WAAIaAAkJghu1PAABAgAaAAkJghu1PAABAgAAAA==.',
La='Lazyheal:BAACLgAFFH8IAAMWAAMJKRSmDACZAAAWAAIJVxSmDACZAAASAAIJegDWGgBBAAAuAAQKfx8ABBYACQmFG08CAOgCABYACQmFG08CAOgCAB0ABAlUBq4/ALEAABIAAgkgBihYAF0AAAAA.Lazytank:BAAALgAECgMJBQABLgAFFAMJCAAWACkUAA==.',
Le='Leetsteve:BAAALgADCgYJCgAAAA==.Legacy:BAAALgADCgEJAgAAAA==.Leigor:BAACLgAFFH8TAAIWAAUJ0xWeAwB1AQAWAAUJ0xWeAwB1AQAuAAQKfykAAhYACQnbIKcDAB8DABYACQnbIKcDAB8DAAAA.Leomoon:BAAALgAECgIJAwAAAA==.Levite:BAAALgAECgQJCQAAAA==.',
Li='Lilara:BAAALgAECgYJDAAAAA==.Lionknite:BAABLgAECn8kAAIcAAkJpRqtDABiAgAcAAkJpRqtDABiAgAAAA==.Liontabu:BAAALgAECgIJAgAAAA==.Liteshocklet:BAAALgAECgEJAQABLgAFFAMJCAAWACkUAA==.Littledung:BAAALgADCgQJBAAAAA==.',
Lo='Looting:BAAALgAECgUJEAAAAA==.',
Lu='Lustdeez:BAAALgADCgYJCQAAAA==.',
['Lã']='Lãdyrift:BAABLgAECn8dAAIBAAgJdQsDXQA7AQABAAgJdQsDXQA7AQAAAA==.',
Ma='Mageko:BAAALgAECgEJBQAAAA==.Magetot:BAAALgADCgEJAQABLgADCgkJCgAFAAAAAA==.Makarion:BAAALgAECgYJDgAAAA==.Malvina:BAAALgAECgMJAwAAAA==.Maoli:BAAALgAECgQJDAAAAA==.Marohen:BAAALgADCgYJBgAAAA==.Mauka:BAABLgAECn8VAAMCAAYJwRPPOABUAQACAAYJwRPPOABUAQABAAQJfQ8wUQCMAAAAAA==.Mauzer:BAAALgAECgEJAQABLgAECgYJFwAbANEXAA==.',
Mc='Mcfallen:BAAALgADCgcJBwAAAA==.Mcksquizy:BAABLgAECn8kAAIcAAgJdx2iHwDKAQAcAAgJdx2iHwDKAQAAAA==.Mcscrotie:BAAALgAECggJCAAAAA==.',
Me='Mes:BAABLgAECn8gAAIZAAgJ3BxkCQAGAgAZAAgJ3BxkCQAGAgAAAA==.',
Mi='Mimmi:BAAALgAECgUJDQABLgAECgYJFwAbANEXAA==.Mishri:BAABLgAECn8eAAIaAAkJTyMuEAD8AgAaAAkJTyMuEAD8AgAAAA==.',
Mo='Moonsorrow:BAAALgADCgMJAwAAAA==.Moparcast:BAAALgADCgEJAQABLgADCgUJBQAFAAAAAA==.Moriphael:BAAALgADCgcJCQAAAA==.Moritura:BAABLgAECn8XAAMbAAYJ0RcKEAA8AQAbAAYJIhUKEAA8AQAeAAEJWBuPJwBKAAAAAA==.',
My='Mykana:BAAALgAECgYJEwAAAA==.',
Na='Nakabeam:BAABLgAECn8hAAIaAAkJmxIPXQCKAQAaAAkJmxIPXQCKAQAAAA==.Nakatwin:BAABLgAECn8XAAIaAAcJWxTbWACXAQAaAAcJWxTbWACXAQABLgAECgkJIQAaAJsSAA==.Naklek:BAABLgAECn8hAAMfAAgJBB6TBgCOAgAfAAgJBB6TBgCOAgARAAEJYgteNAAkAAAAAA==.Navic:BAAALgAECgEJAQAAAA==.',
Ne='Newtt:BAAALgADCgUJBgABLgADCgcJCQAFAAAAAA==.',
Ni='Nicked:BAECLgAFFH8HAAIIAAMJaA+JDQDwAAAIAAMJaA+JDQDwAAAuAAQKfyMAAwgACQmEH54OAMYCAAgACQmEH54OAMYCAAoABAl0Bj9pAJkAAAAA.Niraleth:BAAALgADCggJGAAAAA==.Nistik:BAABLgAECn8aAAMWAAcJsgZCHgAQAQAWAAcJsgZCHgAQAQASAAEJ0wHYawAaAAAAAA==.',
No='Nozomí:BAAALgAECgUJBQAAAA==.',
Ob='Obergefel:BAAALgADCgEJAQAAAA==.',
Op='Ophiuchus:BAAALgAECgcJDAAAAA==.',
Or='Orcdung:BAAALgADCgEJAQAAAA==.',
Oz='Ozymandias:BAAALgADCgEJAQAAAA==.',
Pa='Paldente:BAAALgAECgcJDAAAAA==.Pamelina:BAAALgADCgUJDwAAAA==.Pandaexpress:BAAALgADCgkJCQABLgAFFAMJCQATAJwbAA==.Panzerfäust:BAAALgAECgQJCAAAAA==.Pawrina:BAAALgAECgkJEQAAAA==.',
Pe='Pernicious:BAAALgAECgQJBAAAAA==.Peskadote:BAAALgADCgMJAwAAAA==.Pestis:BAAALgADCgkJDwAAAA==.',
Ph='Phaoe:BAAALgADCgUJBQAAAA==.Phillis:BAABLgAECn8WAAIVAAcJfRKVOQBfAQAVAAcJfRKVOQBfAQAAAA==.',
Pi='Pilfering:BAAALgADCgQJBAAAAA==.',
Pl='Plumpt:BAAALgAECgcJEwAAAA==.',
Pr='Prey:BAAALgADCgYJBgAAAA==.',
Pu='Pulchritude:BAAALgAECgcJDQAAAA==.Punchem:BAAALgADCgcJBwAAAA==.Purex:BAABLgAECn8bAAIgAAgJnAUwCgCSAQAgAAgJnAUwCgCSAQAAAA==.',
Py='Pylonshots:BAAALgAECgEJAQAAAA==.',
Ra='Raivah:BAAALgADCgMJAwAAAA==.Randomyzed:BAAALgAECgcJEwAAAA==.Rathus:BAABLgAECn8ZAAIMAAcJcBy/LwBOAgAMAAcJcBy/LwBOAgAAAA==.Rawdata:BAABLgAECn8dAAMhAAgJDBdMEACyAQAhAAcJlRRMEACyAQALAAcJyw1VQgB4AQAAAA==.Razenka:BAAALgAECgEJAQAAAA==.',
Re='Reaperdeath:BAAALgAECgEJAQAAAA==.Rebecca:BAABLgAECn8gAAIIAAgJpxfbJwB4AQAIAAgJpxfbJwB4AQAAAA==.Rebeka:BAABLgAECn8cAAIiAAgJ1x0gAwDaAgAiAAgJ1x0gAwDaAgABLgAECggJIAAIAKcXAA==.Regantze:BAAALgAECgUJCAAAAA==.Reliun:BAAALgAECgYJDgAAAA==.Ressie:BAAALgAECgQJCQAAAA==.Reverendlion:BAAALgAECgYJBwAAAA==.',
Ro='Rogosh:BAAALgAECgEJAQAAAA==.',
Ru='Ruemor:BAAALgADCgYJFgAAAA==.',
Ry='Ryblade:BAAALgAECgcJDQAAAA==.',
Sa='Saiko:BAAALgAECgIJAgAAAA==.Saladcake:BAAALgAECgQJBAAAAA==.Salleane:BAABLgAECn8YAAIVAAgJtBUwXgDJAQAVAAgJtBUwXgDJAQAAAA==.Sampal:BAABLgAECn8cAAIGAAcJOhwsBwCrAQAGAAcJOhwsBwCrAQAAAA==.Sampriest:BAAALgAECgQJCAABLgAECgcJHAAGADocAA==.Samwield:BAACLgAFFH8HAAIjAAMJShqTDgABAQAjAAMJShqTDgABAQAuAAQKfy0ABCMACQnmHNgHABMDACMACQnmHNgHABMDACAAAwkmF0oTAM0AACQAAQnVCn4OADIAAAAA.Sanchoe:BAAALgAECgYJCgAAAA==.Sanzo:BAAALgADCgEJAQAAAA==.',
Se='Seireitei:BAABLgAECn8XAAILAAcJBRtCDQAZAgALAAcJBRtCDQAZAgAAAA==.Selaheal:BAABLgAECn8cAAISAAcJgBbuDgCZAQASAAcJgBbuDgCZAQAAAA==.Seraath:BAACLgAFFH8TAAIeAAUJMhloAQAiAQAeAAUJMhloAQAiAQAuAAQKfyYAAx4ACQn7IZAAAGQDAB4ACQn7IZAAAGQDABoAAQkAAHzSAE4AAAAA.Serath:BAAALgAECgYJBwAAAA==.',
Sh='Shadowskull:BAAALgADCgUJBQAAAA==.Shadwkllr:BAAALgAECgQJCQAAAA==.Shamloo:BAAALgADCgEJAQAAAA==.Shimwow:BAAALgAECgMJAwAAAA==.Shnood:BAAALgAECgYJCgAAAA==.Shortie:BAAALgADCggJDwAAAA==.',
Sk='Ski:BAAALgAECgIJAgAAAA==.Skies:BAAALgAECgEJAgABLgAECgcJCAAFAAAAAA==.',
Sn='Snowhite:BAAALgAECgIJAgAAAA==.',
So='Soshi:BAAALgAECgQJBAAAAA==.',
Sp='Speckle:BAAALgADCgkJEQAAAA==.Spooqe:BAAALgADCgcJCwAAAA==.',
St='Stabbie:BAAALgADCgcJBwAAAA==.Stahn:BAAALgAECgUJBQAAAA==.Stdoubleds:BAAALgAECgQJBAAAAA==.Stervana:BAACLgAFFH8HAAIEAAQJjBptCgBaAQAEAAQJjBptCgBaAQAuAAQKfyoAAgQACQliIOEDAFoDAAQACQliIOEDAFoDAAAA.Sterzephyr:BAAALgAECgIJAgABLgAFFAQJBwAEAIwaAA==.Stickytoes:BAAALgADCgYJBgAAAA==.Stormyknight:BAABLgAECn8nAAMXAAgJNw+XCwBTAQAXAAgJNw+XCwBTAQAYAAYJ5QtJCgDMAAAAAA==.',
Su='Sunwrath:BAAALgAECgcJCAAAAA==.Susmonk:BAAALgAECgQJBQAAAA==.Suspectedd:BAABLgAFFH8FAAIHAAMJdwhYLwD5AAAHAAMJdwhYLwD5AAABLgAFFAUJEwAlAOIjAA==.Suswar:BAACLgAFFH8TAAIlAAUJ4iP6AQCcAQAlAAUJ4iP6AQCcAQAuAAQKfykAAiUACQlMJJkAALgDACUACQlMJJkAALgDAAAA.Suvulaan:BAABLgAECn8ZAAMXAAYJrgesEADyAAAXAAYJrgesEADyAAAEAAEJ5ACaawAbAAAAAA==.',
Sw='Swifix:BAAALgAECgEJAQAAAA==.',
Ta='Tacostand:BAACLgAFFH8PAAIaAAUJERa1EABJAQAaAAUJERa1EABJAQAuAAQKfycAAhoACQlNIOoHAEwDABoACQlNIOoHAEwDAAAA.Tamarlane:BAAALgADCgIJAgAAAA==.Tatoo:BAABLgAECn8eAAIIAAgJ2R9LEAC4AgAIAAgJ2R9LEAC4AgAAAA==.',
Te='Teeice:BAABLgAECn8aAAIgAAkJrgteBACTAQAgAAkJrgteBACTAQAAAA==.Teo:BAAALgAECgcJEAAAAA==.Terian:BAAALgAECgkJBQAAAA==.',
Th='Thaodan:BAABLgAECn8aAAIZAAkJ/xANEgCOAQAZAAkJ/xANEgCOAQAAAA==.Thekan:BAABLgAECn8VAAIbAAgJnRHoCAC5AQAbAAgJnRHoCAC5AQAAAA==.Theriot:BAABLgAECn8aAAMVAAkJHhs5NgBKAgAVAAkJHhs5NgBKAgAiAAEJMwg7oAAoAAAAAA==.Thianá:BAAALgAECgQJBwAAAA==.Thüclides:BAAALgAECgcJAgAAAA==.',
Ti='Tikidragoona:BAAALgAECgIJAgAAAA==.Tinkerspell:BAAALgAECgcJEAAAAA==.Tinkiebella:BAAALgADCgMJAwABLgAECgcJEAAFAAAAAA==.Tiredinras:BAAALgADCgIJAgAAAA==.',
To='Tobivoker:BAAALgAECgEJAQAAAA==.Toosus:BAABLgAFFH8KAAIPAAMJ5RrZCQDmAAAPAAMJ5RrZCQDmAAABLgAFFAUJEwAlAOIjAA==.Toppers:BAAALgAECgMJAwAAAA==.Topps:BAABLgAECn8ZAAIhAAgJJhRsCgAqAgAhAAgJJhRsCgAqAgAAAA==.Toric:BAAALgADCgYJBgAAAA==.Toridian:BAAALgAECgIJAwAAAA==.Torinus:BAAALgADCgMJAwAAAA==.Totec:BAAALgAECgUJCgAAAA==.',
Tr='Trolldung:BAAALgADCgkJDAAAAA==.',
Tt='Tturtle:BAACLgAFFH8GAAIVAAQJ1AZWNQCaAAAVAAQJ1AZWNQCaAAAuAAQKfyUAAhUACQl4FeAwAF8CABUACQl4FeAwAF8CAAAA.',
Tu='Tuss:BAAALgADCgEJAgAAAA==.',
Tw='Twoblock:BAAALgADCgEJAgAAAA==.',
Ty='Tyariel:BAAALgADCgYJBgAAAA==.Tystraz:BAAALgAECgQJBAAAAA==.',
Ud='Udúnnaur:BAAALgADCggJDgAAAA==.',
Um='Umisle:BAAALgADCgQJBAAAAA==.',
Un='Undermage:BAAALgADCgQJBAAAAA==.',
Va='Valmora:BAAALgADCgMJAwAAAA==.Valstad:BAAALgADCgIJAgAAAA==.',
Ve='Vector:BAAALgAECgYJCAAAAA==.Velata:BAABLgAECn8YAAIHAAUJBQqhfQDZAAAHAAUJBQqhfQDZAAAAAA==.Verdugo:BAAALgAECgIJAgAAAA==.Verite:BAAALgAECgYJEQAAAA==.',
Vi='Vicar:BAAALgADCggJDgAAAA==.Vice:BAAALgADCgEJAQAAAA==.Violencê:BAAALgAECgYJEgAAAA==.',
Vo='Vodka:BAAALgADCgcJFQAAAA==.Voelva:BAAALgADCgQJBAAAAA==.Voidedge:BAABLgAECn8hAAMNAAcJxw/GEACqAAAMAAcJQA0RdgBxAQANAAUJDBHGEACqAAAAAA==.Voidgazer:BAAALgAECgYJCwAAAA==.Voidsyn:BAAALgAECgMJAwAAAA==.',
We='Wes:BAABLgAECn8dAAIgAAgJ9BTCAgDmAQAgAAgJ9BTCAgDmAQAAAA==.',
Wi='Wildlettuce:BAAALgADCgEJAQAAAA==.Willybcastin:BAAALgAFFAEJAQABLgAFFAcJFwAcANMiAA==.Willybwankin:BAACLgAFFH8XAAIcAAcJ0yKXAABrAgAcAAcJ0yKXAABrAgAuAAQKfyUAAhwACQkwJsoAAOEDABwACQkwJsoAAOEDAAAA.',
Wo='Wolfiekins:BAAALgADCgUJBQAAAA==.Wowgazm:BAAALgAECgYJEQAAAA==.',
Wy='Wyvern:BAAALgAECgUJDQAAAA==.',
Xa='Xarinn:BAAALgADCgEJAQAAAA==.',
Yo='Yodapopz:BAAALgADCgYJBgAAAA==.',
Za='Zacarly:BAAALgAECgQJBwAAAA==.Zalmage:BAABLgAECn8lAAMHAAkJaRYjEgBLAgAHAAkJaRYjEgBLAgAmAAIJ5wlpFwBeAAAAAA==.Zantack:BAAALgAECgUJBQAAAA==.',
Ze='Zemos:BAAALgADCgMJAwAAAA==.Zeseroth:BAACLgAFFH8PAAIVAAUJjCBmBwB7AQAVAAUJjCBmBwB7AQAuAAQKfyQAAhUACQmbIywDAKMDABUACQmbIywDAKMDAAAA.Zeserotho:BAAALgAECgQJBgAAAA==.',
Zy='Zyn:BAACLgAFFH8KAAIWAAQJiCQaAgCtAQAWAAQJiCQaAgCtAQAuAAQKfyIAAxYACAmWIhMGAO4CABYACAmWIhMGAO4CABIAAwn4DW1QAI0AAAAA.',
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

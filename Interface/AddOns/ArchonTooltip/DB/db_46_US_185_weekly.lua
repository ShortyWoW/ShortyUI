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

local lookup = {'Paladin-Holy','Paladin-Retribution','Warlock-Destruction','Unknown-Unknown','Evoker-Preservation','Evoker-Augmentation','Hunter-Survival','Monk-Brewmaster','DeathKnight-Unholy','Warlock-Demonology','Warrior-Arms','Warrior-Fury','Evoker-Devastation','Rogue-Outlaw','Druid-Guardian','Shaman-Elemental','Mage-Frost','Monk-Windwalker','DemonHunter-Devourer','Shaman-Restoration','Mage-Arcane','Mage-Fire','DeathKnight-Frost','Druid-Feral','Druid-Restoration','Priest-Holy','Rogue-Assassination','DemonHunter-Vengeance','Priest-Discipline','Rogue-Subtlety','DeathKnight-Blood','Druid-Balance','Hunter-BeastMastery',}
local provider = {region='US',realm='Scilla',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abeblinkin:BAAALgAECgQJBAAAAA==.Aborlight:BAAALgADCgkJDAAAAA==.',
Ad='Adit:BAAALgAECgYJBwAAAA==.',
Ae='Aedrius:BAABLgAECn8ZAAMBAAcJLhjHNQClAQABAAYJrRnHNQClAQACAAQJlxECwQAFAQAAAA==.',
Ag='Agnekie:BAAALgAECgEJAQAAAA==.',
Ai='Aiwass:BAABLgAECn8nAAIDAAgJOQ30BwBhAQADAAgJOQ30BwBhAQAAAA==.Aiyo:BAAALgAECgEJAgABLgAECgYJCAAEAAAAAA==.',
Al='Alexander:BAAALgAECgMJAwAAAA==.',
Am='Amathricus:BAABLgAECn8fAAICAAgJKQuMTABgAQACAAgJKQuMTABgAQAAAA==.Amerika:BAAALgADCgIJAgAAAA==.',
Ar='Arawak:BAAALgADCgEJAQAAAA==.',
As='Ashuk:BAAALgAECgIJAQAAAA==.',
At='Athena:BAAALgAECgMJAwAAAA==.',
Au='Augtism:BAECLgAFFH8FAAMFAAQJ1Q8XDQBBAQAFAAQJ1Q8XDQBBAQAGAAEJ3xPtNwBNAAAuAAQKfxcAAwYABwmfHmULABQCAAYABwmfHmULABQCAAUAAgm2EcIdAIIAAAEuAAUUBAkFAAUA1Q8A.Auitou:BAAALgAECgcJCAAAAA==.Auralei:BAAALgAECgUJCgAAAA==.',
Az='Azelia:BAAALgAECgUJCgABLgAECgYJGAABAI0ZAA==.Azzy:BAABLgAECn8YAAIBAAYJjRmFIgBzAQABAAYJjRmFIgBzAQAAAA==.',
Ba='Bacta:BAAALgADCgUJBQAAAA==.',
Be='Beasti:BAAALgAECgIJAgAAAA==.Beelzebul:BAAALgAECgIJBAABLgAECgUJCAAEAAAAAA==.',
Bi='Bigb:BAABLgAECn8gAAIHAAcJKSbhBADEAgAHAAcJKSbhBADEAgAAAA==.Bigpaladin:BAAALgADCgEJAQAAAA==.',
Bl='Black:BAAALgAECgUJCQAAAA==.',
Bo='Bombaclat:BAAALgADCgEJAQAAAA==.Boor:BAAALgAECgcJCAAAAA==.',
Br='Brilline:BAAALgADCgcJCwAAAA==.Brochese:BAAALgAECgEJAQABLgAECgYJCwAEAAAAAA==.Broka:BAAALgAECgMJAwAAAA==.',
Bu='Bubblewrap:BAAALgAECgQJCAABLgAFFAQJDQAIAJcPAA==.',
Ca='Cadaverous:BAAALgAECgIJAgAAAA==.Canadianguy:BAAALgADCgIJAgABLgAECgQJBAAEAAAAAA==.',
Ch='Chonk:BAAALgADCgkJCwAAAA==.Chunguskhan:BAAALgADCgcJCgAAAA==.',
Cl='Classcarry:BAAALgADCgYJBgABLgAFFAYJFwAJAFghAA==.Claybigsby:BAACLgAFFH8NAAIKAAQJKhcUIwAuAQAKAAQJKhcUIwAuAQAuAAQKfxwAAwMACAm5HRADAMoCAAMACAm5HRADAMoCAAoABQmWGqVxAHwBAAAA.Clif:BAACLgAFFH8HAAMLAAQJhAtlCQAQAQALAAQJhAtlCQAQAQAMAAEJhgNAJQBJAAAuAAQKfxkAAwwACAmqHNwWAJYCAAwACAmqHNwWAJYCAAsAAQl+HV8yAFYAAAAA.',
Co='Cosmiccosmo:BAAALgAECgQJBgAAAA==.',
Cu='Cucurbita:BAAALgADCgYJBgAAAA==.',
Da='Dargon:BAABLgAECn8XAAMGAAgJ3yNmBgAaAwAGAAgJ3yNmBgAaAwANAAYJ7hzLGwBSAQABLgAFFAEJAgAEAAAAAA==.',
De='Deadlyorc:BAAALgADCgMJAwAAAA==.Deaf:BAAALgAFFAEJAQABLgAFFAMJBQAOAMIhAA==.Delphine:BAAALgADCgYJBgAAAA==.Demonblade:BAAALgADCgEJAQAAAA==.Demoniosushi:BAAALgAECgMJBwABLgAECgYJDgAEAAAAAA==.Demonmane:BAAALgADCgMJAwAAAA==.Derpy:BAAALgAECgYJEQAAAA==.',
Di='Dippindotz:BAAALgAECgEJAgABLgAFFAYJFwAJAFghAA==.',
Dj='Djheals:BAAALgAECgQJBQAAAA==.',
Do='Doobiemage:BAAALgADCgcJCgAAAA==.Dorenis:BAAALgADCgUJBQAAAA==.',
Dr='Drachese:BAAALgAECgEJAQABLgAECgYJCwAEAAAAAA==.Droopox:BAABLgAECn8YAAIPAAgJdAmSEgDgAAAPAAgJdAmSEgDgAAAAAA==.Druchese:BAAALgAECgYJCwAAAA==.',
Ea='Eagleeye:BAAALgAECgUJDwAAAA==.',
Em='Emsley:BAABLgAECn83AAIQAAkJUxMlDgD8AQAQAAkJUxMlDgD8AQAAAA==.',
Er='Erised:BAAALgADCgYJCQAAAA==.',
Ex='Exo:BAACLgAFFH8NAAIRAAQJzhp3IQBlAQARAAQJzhp3IQBlAQAuAAQKfx4AAhEACAkzITIgAPMCABEACAkzITIgAPMCAAAA.',
Fe='Felrid:BAAALgAECgYJBgABLgAFFAEJAgAEAAAAAA==.',
Fl='Floudruid:BAAALgADCgMJAwAAAA==.',
Fo='Focalors:BAAALgAECgUJCAAAAA==.Foobear:BAACLgAFFH8NAAIPAAQJwxLyAwAPAQAPAAQJwxLyAwAPAQAuAAQKfyIAAg8ACAm5HpsEAKQCAA8ACAm5HpsEAKQCAAAA.Fozzy:BAABLgAECn8WAAIGAAYJHQlrMwDVAAAGAAYJHQlrMwDVAAAAAA==.Fozél:BAAALgAECgEJAQAAAA==.',
Fr='Franchescold:BAABLgAECn8dAAIJAAgJ6hmaKADbAQAJAAgJ6hmaKADbAQAAAA==.Franfran:BAABLgAECn8cAAIRAAgJ4w6wRwCQAQARAAgJ4w6wRwCQAQAAAA==.Freasey:BAAALgAECgUJDwAAAA==.Frostbeard:BAAALgADCgQJBwAAAA==.',
Fu='Furiousfoo:BAAALgAECgUJDwABLgAFFAQJDQAPAMMSAA==.Furlock:BAAALgAECgUJDwAAAA==.',
Ga='Gabriel:BAAALgAECgcJBwAAAA==.Galicia:BAAALgAECgYJBgAAAA==.Gantaris:BAAALgAECgMJAwAAAA==.',
Ge='Gengiskaan:BAAALgADCgcJCgAAAA==.',
Gi='Gir:BAAALgAECgYJBwAAAA==.Gixian:BAAALgAECgYJEAAAAA==.',
Go='Gochese:BAAALgAECgYJCgABLgAECgYJCwAEAAAAAA==.',
Gr='Gramid:BAAALgAFFAEJAgAAAA==.Greenseer:BAABLgAECn8eAAIKAAYJ2RKEYQANAQAKAAYJ2RKEYQANAQAAAA==.Grognag:BAAALgAECgYJDgAAAA==.',
Gt='Gtoffmydh:BAAALgADCgIJAgAAAA==.',
Gw='Gwaralmighty:BAABLgAECn8xAAIMAAkJJSDmAgDpAgAMAAkJJSDmAgDpAgAAAA==.',
Ha='Haagen:BAAALgADCgEJAgAAAA==.Haagoon:BAAALgAECgEJAQAAAA==.Halfwolf:BAAALgADCgQJBAAAAA==.Hatch:BAACLgAFFH8FAAIOAAMJwiHEAgAiAQAOAAMJwiHEAgAiAQAuAAQKfx0AAg4ABwmCJRwBAPMCAA4ABwmCJRwBAPMCAAAA.',
Hh='Hholdem:BAAALgADCgcJBwABLgAECgcJGwASAOIPAA==.',
Hi='Hightones:BAACLgAFFH8JAAITAAQJDAh4KQAMAQATAAQJDAh4KQAMAQAuAAQKfyAAAhMACAk2IEYWANECABMACAk2IEYWANECAAAA.',
Ho='Holdêm:BAABLgAECn8bAAISAAcJ4g9TGgBRAQASAAcJ4g9TGgBRAQAAAA==.Holeytoast:BAAALgAECgQJBAABLgAFFAQJDQAQAK4eAA==.Hollee:BAAALgADCgQJBAABLgAFFAQJDQAUAGkRAA==.Horsdoeuvres:BAAALgAECgcJDgAAAA==.',
Hu='Humberto:BAAALgAECgEJAQAAAA==.Hung:BAAALgAECgEJAgAAAA==.',
Ic='Icylady:BAAALgAECgEJAQAAAA==.',
If='Ifrita:BAABLgAECn8vAAQRAAgJFBTqNwDDAQARAAgJvRLqNwDDAQAVAAYJIxOoBwCGAQAWAAEJtQl6CwAxAAAAAA==.Ifrite:BAABLgAECn8bAAMJAAgJCQ28fgCGAQAJAAcJtAy8fgCGAQAXAAYJCwkDDwCwAAAAAA==.',
Ik='Ikur:BAAALgAECgYJDgABLgAECggJLAABAAIcAA==.',
It='Itita:BAAALgADCgIJAgAAAA==.',
Ja='Jackoneill:BAACLgAFFH8HAAICAAMJFAK1OgC+AAACAAMJFAK1OgC+AAAuAAQKfyEAAgIACAl/EORFAHQBAAIACAl/EORFAHQBAAAA.',
Je='Jezlana:BAAALgAECgcJCwAAAA==.',
Ji='Jillidan:BAAALgAECgIJAgAAAA==.',
Jo='Johnnynapalm:BAAALgAECgIJBAABLgAECgQJBAAEAAAAAA==.Jonnycraig:BAAALgAECgEJAgAAAA==.Jormi:BAABLgAECn8mAAILAAgJQiCbAgCVAgALAAgJQiCbAgCVAgAAAA==.',
Ka='Kabaayi:BAAALgADCgEJAQAAAA==.Kaihu:BAAALgADCgUJCAAAAA==.Kalthael:BAAALgADCgkJGAAAAA==.Kasura:BAABLgAECn8mAAMYAAkJTBsOBAAzAgAYAAgJAh0OBAAzAgAZAAUJjRC2gwDQAAAAAA==.Katakuri:BAAALgAECgEJAQAAAA==.',
Kh='Kharahealer:BAABLgAECn8UAAIaAAcJIhc4HABoAQAaAAcJIhc4HABoAQAAAA==.',
Kl='Kllausy:BAAALgAECgIJAwAAAA==.',
Ko='Kochese:BAAALgAECgEJAQABLgAECgYJCwAEAAAAAA==.',
Kr='Krayt:BAAALgAECgEJAQAAAA==.',
Kw='Kwrr:BAAALgADCgYJBgABLgAFFAcJFAAKAFUfAA==.',
La='Lambo:BAABLgAECn8XAAIQAAcJ2h/HCgAtAgAQAAcJ2h/HCgAtAgAAAA==.',
Le='Leafhoof:BAAALgAECgEJAQAAAA==.Lenona:BAAALgAECgIJAgAAAA==.Lexidia:BAAALgADCgUJBQAAAA==.Leynnar:BAAALgAECgUJDQAAAA==.',
Li='Licha:BAAALgAECgcJBQAAAA==.',
Lo='Lockme:BAAALgAFFAMJAwAAAA==.Loveyuling:BAAALgAECgEJAgABLgAECgQJBwAEAAAAAA==.',
Lu='Lunk:BAAALgAECgEJAgAAAA==.',
['Ló']='Lóvecandy:BAAALgAECgQJBwAAAA==.',
Ma='Maruzensky:BAACLgAFFH8cAAIRAAcJvx1tBAAlAgARAAcJvx1tBAAlAgAuAAQKfyoAAxEACQleI6kPAEoDABEACQleI6kPAEoDABYABAmtD6IHAP8AAAAA.Mary:BAACLgAFFH8LAAIbAAQJZyIpAQCUAQAbAAQJZyIpAQCUAQAuAAQKfxcAAhsACAnqH7MCAMECABsACAnqH7MCAMECAAAA.',
Me='Mechfury:BAAALgADCgEJAQAAAA==.Mero:BAABLgAECn8fAAMcAAgJDRpbCQDZAQAcAAYJjh9bCQDZAQATAAcJ5BL4ZgBtAQAAAA==.Metal:BAABLgAECn8XAAIdAAYJCxfUFACZAQAdAAYJCxfUFACZAQAAAA==.Meyrey:BAAALgADCgYJCwAAAA==.',
Mi='Miorine:BAAALgAECgEJAQABLgAECgUJCAAEAAAAAA==.Mistbehavin:BAACLgAFFH8NAAIIAAQJlw97FAAfAQAIAAQJlw97FAAfAQAuAAQKfyIAAggACAm5FvYcABsCAAgACAm5FvYcABsCAAAA.',
Mo='Mog:BAABLgAECn8iAAIBAAcJMyX+DwAfAgABAAcJMyX+DwAfAgAAAA==.Moochese:BAAALgAECgEJAQABLgAECgYJCwAEAAAAAA==.Moostache:BAAALgAECgMJBAAAAA==.',
My='Mytz:BAAALgADCgEJAQAAAA==.',
Ne='Nemisai:BAAALgAECgUJCwAAAA==.',
No='Nobody:BAAALgADCgcJBwAAAA==.',
Oc='Ochra:BAAALgAECgEJAwAAAA==.',
Og='Ogparadox:BAAALgAECgQJDAAAAA==.',
Or='Orionbtch:BAABLgAECn8VAAIeAAcJMQfMGAA9AQAeAAcJMQfMGAA9AQAAAA==.',
Ov='Overheat:BAABLgAECn8XAAIRAAgJtxgdKQD+AQARAAgJtxgdKQD+AQAAAA==.',
Po='Poppy:BAAALgAECgUJDAAAAA==.Portinglol:BAAALgAECgEJAQABLgAFFAYJFwAJAFghAA==.',
Ps='Psycilocibin:BAAALgADCgEJAQAAAA==.',
Qw='Qwiix:BAAALgADCgMJAwAAAA==.Qwixx:BAAALgADCgEJAQAAAA==.',
Ra='Rafikki:BAAALgAECgYJCwAAAA==.Ragerok:BAAALgAECgUJBQAAAA==.Ratidari:BAABLgAECn8gAAITAAgJIxQ3JwCfAQATAAgJIxQ3JwCfAQAAAA==.Ravenstorm:BAAALgAECgMJBAAAAA==.',
Re='Remmîngton:BAABLgAECn8mAAMBAAgJEh+OBwCeAgABAAgJEh+OBwCeAgACAAEJdwdVQgEzAAAAAA==.Reverie:BAAALgADCgMJAwAAAA==.',
Rh='Rhynehardt:BAAALgAECgQJBAAAAA==.',
Ri='Riptidedro:BAABLgAECn8jAAIUAAgJoR6fEwB4AgAUAAgJoR6fEwB4AgAAAA==.',
Ru='Rukaz:BAAALgADCgYJBgAAAA==.Runslikedeer:BAAALgAECgYJDQAAAA==.Rustyarrow:BAAALgAECgEJAQAAAA==.',
Ry='Ryukk:BAABLgAECn8rAAIJAAkJBhYCIQAEAgAJAAkJBhYCIQAEAgAAAA==.',
Sa='Sanoth:BAAALgADCgEJAgAAAA==.Sarana:BAAALgADCgMJAwAAAA==.Sarkhael:BAAALgAECgUJCAAAAA==.',
Se='Sean:BAACLgAFFH8NAAIRAAQJOhtmIwBhAQARAAQJOhtmIwBhAQAuAAQKfyIAAhEACAmGI0YXAB4DABEACAmGI0YXAB4DAAAA.Secksecute:BAAALgAECgIJBQAAAA==.Seinsleer:BAAALgAECgQJBAAAAA==.Serah:BAAALgAFFAQJBAAAAA==.Seris:BAAALgAECgYJBgABLgAFFAEJAgAEAAAAAA==.',
Sh='Shel:BAABLgAECn8hAAITAAgJEAr5RAApAQATAAgJEAr5RAApAQAAAA==.Shimakaze:BAACLgAFFH8VAAMJAAUJiCMjFQB+AQAJAAQJiCMjFQB+AQAfAAEJAACkKgAAAAAuAAQKfyIAAgkABwljJNErAIkCAAkABwljJNErAIkCAAAA.Shizaam:BAACLgAFFH8NAAIQAAQJrh6XCABqAQAQAAQJrh6XCABqAQAuAAQKfyIAAxAACAkHJYgFAD4DABAACAkHJYgFAD4DABQAAQkrCW6dADQAAAAA.Shlommy:BAAALgAECggJEQAAAA==.',
Si='Siinns:BAABLgAECn8eAAMSAAkJjh13CAA5AgASAAkJjh13CAA5AgAIAAIJzhM7egBbAAAAAA==.Simp:BAAALgAECgIJAgAAAA==.Sinfxl:BAAALgAECgYJCgAAAA==.Sippinsizurp:BAAALgAECggJDwAAAA==.',
Sk='Skadooget:BAAALgADCgYJBgAAAA==.Skullmages:BAACLgAFFH8QAAICAAQJABj9CABnAQACAAQJABj9CABnAQAuAAQKfxkAAgIABwk3I6EgAKkCAAIABwk3I6EgAKkCAAAA.',
Sl='Slayur:BAABLgAECn8XAAIMAAYJXA6TNgDsAAAMAAYJXA6TNgDsAAAAAA==.Slinkeril:BAAALgAECgYJDwAAAA==.Sloppydro:BAAALgAECgEJAwAAAA==.',
Sm='Smackthat:BAAALgAECgQJBgABLgAECgYJDgAEAAAAAA==.Smokey:BAAALgAECgUJCQABLgAECgYJDgAEAAAAAA==.Smokinpurrp:BAAALgAECgQJBAAAAA==.Smoky:BAAALgAECgYJDgAAAA==.',
So='Soju:BAAALgAECgEJBQAAAA==.Sotari:BAAALgADCggJCQAAAA==.',
Sp='Sploosh:BAAALgADCgEJAQAAAA==.',
St='Stabberz:BAABLgAECn86AAMbAAkJvCB9AAAOAwAbAAkJvCB9AAAOAwAeAAQJOBKgSwDNAAAAAA==.Stõrmy:BAAALgAECgIJAgAAAA==.',
Su='Sushiroll:BAAALgAFFAEJAQABLgAFFAYJFwAJAFghAA==.',
Sw='Sweetsourrex:BAAALgAECgYJCAAAAA==.',
Sy='Synkro:BAAALgAECgYJBgABLgAECgYJCgAEAAAAAA==.',
Ta='Tatisjr:BAAALgAECgIJAgAAAA==.',
Te='Tempprance:BAAALgADCgcJDQAAAA==.',
Th='Thewordalive:BAAALgADCgIJAgAAAA==.Tholdraz:BAAALgAECgEJAQAAAA==.Thooran:BAAALgAECgIJBgAAAA==.Thrass:BAABLgAECn8dAAIRAAgJKRF0OwC2AQARAAgJKRF0OwC2AQAAAA==.Throngler:BAAALgAECgYJEQAAAA==.',
To='Tohru:BAAALgAECgIJAgABLgAECgUJCAAEAAAAAA==.Toobrunner:BAACLgAFFH8TAAITAAYJziDDBADyAQATAAYJziDDBADyAQAuAAQKfx4AAhMACAlSImEbAK4CABMACAlSImEbAK4CAAAA.Tool:BAACLgAFFH8NAAITAAUJ+iA+CwB9AQATAAUJ+iA+CwB9AQAuAAQKfxoAAhMACQmfIQQMACEDABMACQmfIQQMACEDAAEuAAUUCAkZABEAHBsA.',
Up='Upside:BAAALgAECgEJAgAAAA==.',
Uz='Uzi:BAAALgAECgcJDgAAAA==.',
Va='Varvera:BAAALgADCgMJAwAAAA==.',
Ve='Velannis:BAABLgAECn8lAAMOAAkJlyFbAAANAwAOAAkJlyFbAAANAwAbAAQJ8hwtEgDiAAAAAA==.',
Vi='Virikas:BAABLgAECn8cAAMUAAcJYx3tEQAqAgAUAAcJYx3tEQAqAgAQAAQJKAzXQgCeAAAAAA==.',
Vo='Voidhunter:BAABLgAECn8TAAITAAgJThW+WwCOAQATAAgJThW+WwCOAQAAAA==.Voodooki:BAABLgAECn8mAAIgAAgJlg8/FQCVAQAgAAgJlg8/FQCVAQAAAA==.',
Vu='Vuo:BAABLgAECn8lAAIhAAgJKxOKJQC+AQAhAAgJKxOKJQC+AQAAAA==.',
Wa='Wayside:BAAALgAECgEJBgAAAA==.',
We='Weedonice:BAAALgAECgcJBQAAAA==.',
Wh='Wheelytank:BAAALgAECggJDgAAAA==.White:BAAALgAECgQJBwABLgABCgIJAgAEAAAAAA==.',
Wi='Wilburoni:BAAALgADCgIJAgAAAA==.Wiping:BAAALgAECgIJAQABLgAECgcJIgABADMlAA==.',
Xf='Xfreshh:BAAALgAECgYJDQAAAA==.',
Ya='Yamalock:BAAALgAFFAQJBAAAAA==.Yamamist:BAAALgAECgYJCgABLgAFFAMJBgARAK4WAA==.Yamå:BAACLgAFFH8GAAIRAAMJrhblQgAFAQARAAMJrhblQgAFAQAuAAQKfxkAAhEABglrIkZfAB0CABEABglrIkZfAB0CAAAA.',
Ye='Yeaffa:BAAALgADCgYJBgAAAA==.',
Yi='Yingzhi:BAAALgADCgIJAgAAAA==.',
Za='Zavalu:BAABLgAECn8iAAIUAAgJ9h2lCACiAgAUAAgJ9h2lCACiAgAAAA==.',
Ze='Zerosh:BAABLgAECn8YAAIbAAgJwwqiBgCBAQAbAAgJwwqiBgCBAQAAAA==.',
Zi='Zinaida:BAAALgADCggJCAAAAA==.',
Zo='Zortok:BAABLgAECn8eAAIQAAgJ+RLXFwCSAQAQAAgJ+RLXFwCSAQAAAA==.',
['Âc']='Âce:BAAALgAECgEJAwAAAA==.',
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

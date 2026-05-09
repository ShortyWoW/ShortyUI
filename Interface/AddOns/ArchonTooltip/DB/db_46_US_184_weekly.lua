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

local lookup = {'Evoker-Preservation','Evoker-Augmentation','Druid-Feral','DeathKnight-Blood','DemonHunter-Havoc','Unknown-Unknown','DemonHunter-Devourer','Druid-Guardian','Mage-Frost','Monk-Brewmaster','Warrior-Fury','Rogue-Subtlety','Hunter-BeastMastery','Hunter-Survival','DeathKnight-Unholy','Druid-Restoration','Shaman-Enhancement','Paladin-Holy','Paladin-Protection','Priest-Discipline','Priest-Shadow','Warrior-Protection','Rogue-Assassination','Rogue-Outlaw','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Druid-Balance','Shaman-Restoration','Paladin-Retribution','Monk-Windwalker','DeathKnight-Frost','Priest-Holy','Evoker-Devastation','Monk-Mistweaver','Hunter-Marksmanship','Shaman-Elemental','DemonHunter-Vengeance','Warrior-Arms',}
local provider = {region='US',realm='ScarletCrusade',name='US',type='weekly',zone=46,date='2026-05-08',data={Ac='Acefu:BAAALgAECgYJDAAAAA==.Acorneo:BAAALgAECgQJBAABLgAFFAQJDAABALMNAA==.Acornita:BAACLgAFFH8MAAMBAAQJsw18FADEAAABAAMJ5w98FADEAAACAAIJXwIbMwByAAAuAAQKfyoAAwEACQnlD0ERACgCAAEACQnlD0ERACgCAAIABwlIEmchADcBAAAA.',
Ae='Aelana:BAAALgADCgkJCQAAAA==.',
Ai='Ailanthus:BAABLgAECn8YAAIDAAcJpg53DwAgAQADAAcJpg53DwAgAQAAAA==.',
Ak='Akinira:BAEBLgAECn80AAIEAAkJOx5WBAB2AgAEAAkJOx5WBAB2AgAAAA==.',
Al='Aleinadris:BAAALgADCgQJBAAAAA==.Alikchi:BAAALgADCgEJAgAAAA==.Alloisaber:BAAALgAECgYJCAAAAA==.Alternis:BAAALgAECgMJAwAAAA==.',
An='Andrelsia:BAAALgAECgEJAQAAAA==.Andrilla:BAAALgAECgMJAwAAAA==.Ankeseth:BAAALgADCgkJEwAAAA==.',
Ap='Apôllyon:BAACLgAFFH8KAAIFAAMJoCIoBgA/AQAFAAMJoCIoBgA/AQAuAAQKfycAAgUACQngJPAAAL4DAAUACQngJPAAAL4DAAAA.',
Ar='Aracelis:BAAALgAECgcJBwAAAA==.Aradius:BAAALgAECgEJAQABLgAECgIJBgAGAAAAAA==.Archertower:BAAALgADCgUJBQAAAA==.Artemiswynd:BAAALgADCgYJBgAAAA==.Arén:BAABLgAECn8ZAAMHAAgJaR6aFgAHAgAHAAcJYx2aFgAHAgAFAAcJhx+XGwDkAQAAAA==.',
As='Ashenshugär:BAAALgAECgQJBQAAAA==.',
Av='Avadda:BAABLgAECn8YAAIIAAcJthE5EgBPAQAIAAcJthE5EgBPAQABLgAECggJCAAGAAAAAA==.',
Az='Azmar:BAABLgAECn8XAAIJAAcJOh9xKQD8AQAJAAcJOh9xKQD8AQAAAA==.',
Ba='Badffinger:BAAALgADCgYJBgAAAA==.Balain:BAAALgAECgEJAQABLgAECgYJFgAKAEoPAA==.',
Be='Bearmont:BAAALgAECgYJCgAAAA==.Bearzerk:BAABLgAECn8eAAILAAcJ2xE0IABqAQALAAcJ2xE0IABqAQAAAA==.Beastmonk:BAAALgADCgEJAQAAAA==.Benathar:BAABLgAECn8YAAIJAAcJKAwKXgBXAQAJAAcJKAwKXgBXAQAAAA==.',
Bi='Bifrost:BAAALgAECgUJBQAAAA==.Bionico:BAAALgAECgUJCgAAAA==.Birgir:BAAALgAECgEJAQAAAA==.',
Bl='Blackmagék:BAAALgADCgcJBwAAAA==.Bloodrager:BAAALgADCgIJAgAAAA==.Bloodthorn:BAABLgAECn8aAAIMAAgJJgZ4FgBVAQAMAAgJJgZ4FgBVAQAAAA==.Blortimor:BAAALgADCgcJBwAAAA==.',
Bo='Bombad:BAAALgAECgYJCAAAAA==.Boomnescient:BAAALgAECgYJDgAAAA==.Bozscaggs:BAABLgAECn8lAAMNAAgJbxD0KACuAQANAAgJbxD0KACuAQAOAAUJAwP3JQDIAAAAAA==.',
Br='Bramis:BAAALgADCgkJHAAAAA==.Brantu:BAAALgADCgQJCAABLgADCgkJDwAGAAAAAA==.Braultus:BAABLgAECn8jAAIEAAgJyxlpCgDTAQAEAAgJyxlpCgDTAQAAAA==.Breyastrasza:BAAALgADCgMJAwAAAA==.',
Bu='Burstangel:BAAALgAECgUJBgAAAA==.',
By='Byrddh:BAAALgADCgQJBAAAAA==.',
Ca='Cadenza:BAAALgAECgMJAwAAAA==.Caliopedk:BAACLgAFFH8HAAMEAAIJrRjNGwBdAAAPAAIJrRjdOACqAAAEAAIJqALNGwBdAAAuAAQKfxsAAw8ACAlIIV4hALsCAA8ACAlIIV4hALsCAAQABQlJDjAqAO0AAAAA.Capra:BAAALgADCgkJHwAAAA==.Carillanklip:BAAALgADCgUJBQAAAA==.',
Cd='Cdmickey:BAAALgADCgUJBQAAAA==.',
Ce='Celestè:BAAALgAECggJEQAAAA==.Celéste:BAAALgAECgQJBAAAAA==.Cerdwin:BAAALgAECggJDAABLgAECggJLQAQALQXAA==.',
Ch='Charferad:BAAALgAECgMJAwAAAA==.Cheaptrick:BAAALgADCgcJCwAAAA==.Chibeard:BAABLgAECn8eAAIKAAgJRiLXAwC4AgAKAAgJRiLXAwC4AgAAAA==.Chonglin:BAAALgADCgIJAgAAAA==.',
Cl='Clearcast:BAAALgADCgkJCQAAAA==.Clubsdh:BAAALgAECgEJAQAAAA==.',
Co='Coolbro:BAAALgADCgIJAgAAAA==.Corialis:BAAALgAECgcJDwAAAA==.Counsel:BAAALgAECgUJBQAAAA==.',
Cr='Crom:BAABLgAECn8hAAIRAAgJvAyWCQCBAQARAAgJvAyWCQCBAQAAAA==.Crosis:BAAALgADCgYJBgAAAA==.Cruelladvoid:BAAALgAECgEJAQAAAA==.Cruush:BAAALgAECgYJBQAAAA==.',
Cu='Culerro:BAAALgAECgYJAwABLgAECgYJBQAGAAAAAA==.Cursive:BAAALgADCgUJDQAAAA==.',
Cy='Cygnes:BAABLgAECn8WAAIPAAgJqhtHHgATAgAPAAgJqhtHHgATAgAAAA==.',
Da='Daddywarrior:BAAALgADCgUJBgAAAA==.Daeva:BAAALgADCgEJAQAAAA==.Dantey:BAAALgADCgYJBgAAAA==.Daus:BAAALgAFFAEJAQAAAA==.Dazanna:BAABLgAECn8dAAMSAAgJ/xIqGQDBAQASAAgJ/xIqGQDBAQATAAUJTAv4HgCdAAAAAA==.Dazre:BAAALgAECgUJBgAAAA==.',
De='Deeminor:BAAALgADCgkJEwAAAA==.Desktop:BAABLgAECn8jAAMUAAgJxRhTCQBDAgAUAAgJxRhTCQBDAgAVAAQJ5QrsLwDVAAAAAA==.',
Di='Diod:BAABLgAECn8jAAIWAAgJ0RX1DQCDAQAWAAgJ0RX1DQCDAQAAAA==.Divineßovine:BAAALgADCgcJBwAAAA==.',
Dr='Dracovoid:BAAALgADCgUJBQAAAA==.Draehton:BAAALgAECgQJBAAAAA==.Dragyns:BAACLgAFFH8KAAIXAAQJvBQyAgBmAQAXAAQJvBQyAgBmAQAuAAQKfycABBcACQlEG4ACAMoCABcACQkTGYACAMoCAAwABQmQGjgsAJwBABgAAwmrFFEJANwAAAAA.Dragynseye:BAAALgADCgIJAgABLgAFFAQJCgAXALwUAA==.Drayper:BAAALgAECgYJCwAAAA==.Druugal:BAACLgAFFH8HAAIMAAMJwBY0EwAAAQAMAAMJwBY0EwAAAQAuAAQKfy0AAwwACAlVIvMEAHQCAAwACAlVIvMEAHQCABcAAQl6C+cfADMAAAAA.',
Du='Dubs:BAABLgAECn8XAAQZAAgJRxpQNgCLAQAZAAUJGRtQNgCLAQAaAAIJthazFwCMAAAbAAIJwxteFABNAAAAAA==.Dunbarke:BAAALgAECgUJDQAAAA==.',
Ef='Efishient:BAABLgAECn8eAAIQAAYJWCRVEQBGAgAQAAYJWCRVEQBGAgABLgAFFAYJGQAQAH8TAA==.',
El='Elisoria:BAAALgADCgMJAwAAAA==.Elliwynd:BAABLgAECn8aAAIQAAgJrgzXMQBWAQAQAAgJrgzXMQBWAQAAAA==.',
Eo='Eoshot:BAAALgAECgUJCAAAAA==.',
Er='Erinnys:BAABLgAECn8VAAMFAAgJXwdOFgA1AQAFAAgJRQdOFgA1AQAHAAYJsgWElgDvAAAAAA==.Ermoril:BAAALgAECgQJBQAAAA==.Ernesta:BAAALgADCgcJCAAAAA==.',
Eu='Eufemia:BAAALgAECgEJAQAAAA==.',
['Eø']='Eøs:BAAALgAECgEJAQAAAA==.',
Fa='Famine:BAAALgAECgcJDAAAAA==.',
Fe='Felern:BAAALgAECgUJBwABLgAECgcJFwAJADofAA==.Feyrun:BAAALgADCgkJEwAAAA==.Feyrè:BAAALgADCgQJBQAAAA==.',
Fi='Finalomega:BAAALgAECgYJCwAAAA==.',
Fl='Flaminfalcon:BAAALgAFFAIJAwAAAA==.Flody:BAAALgAECgYJDAAAAA==.',
Fo='Foxflame:BAABLgAECn8tAAMQAAgJtBdWFgASAgAQAAgJtBdWFgASAgAcAAMJSAr3PACRAAAAAA==.',
Fr='Franzen:BAAALgAECgEJAQAAAA==.Freakbob:BAAALgADCgYJCQAAAA==.Froglocky:BAABLgAECn8fAAMbAAgJ0hZGAwDRAQAbAAgJ0hZGAwDRAQAZAAMJcwRZ9ABwAAAAAA==.Fronsac:BAAALgADCgQJBAAAAA==.',
Fu='Fulanita:BAAALgAECgUJEwAAAA==.',
Ga='Gallager:BAAALgADCgMJAwAAAA==.Garzok:BAABLgAECn8YAAMbAAcJmgoBBwA9AQAbAAcJmgoBBwA9AQAZAAMJzQHjCAFLAAAAAA==.',
Ge='Genkithered:BAABLgAECn8fAAIdAAgJfBiCEwAaAgAdAAgJfBiCEwAaAgAAAA==.',
Gi='Gilaras:BAAALgADCgIJAgAAAA==.Gilernil:BAAALgAECgQJCAAAAA==.',
Gl='Gladtohelp:BAAALgAECgIJAgAAAA==.',
Gn='Gnoquarter:BAAALgADCgIJAgAAAA==.',
Gr='Gravemarks:BAABLgAECn8YAAMYAAgJqBOnAwDAAQAYAAgJqBOnAwDAAQAXAAQJzAncEQDoAAAAAA==.Grimhorn:BAAALgAECgUJDwAAAA==.Grimlie:BAAALgADCgkJDwAAAA==.Grimmrock:BAAALgAECgMJAwAAAA==.Grumblen:BAAALgADCgMJAwAAAA==.',
Gu='Guaritrice:BAAALgAECgUJBwAAAA==.Gubb:BAAALgAECgMJAwAAAA==.',
Gw='Gwenylane:BAABLgAECn8bAAIeAAgJ0wa9VwBCAQAeAAgJ0wa9VwBCAQAAAA==.Gwindor:BAAALgAECgEJAQAAAA==.Gwyndelyn:BAABLgAECn8fAAIfAAgJ9wl4GgBPAQAfAAgJ9wl4GgBPAQAAAA==.',
Ha='Hatterus:BAABLgAECn8rAAIeAAcJ/ArJYAAsAQAeAAcJ/ArJYAAsAQAAAA==.',
He='Herculeze:BAAALgAECgQJBAAAAA==.Hessian:BAAALgADCgEJAQAAAA==.Hetd:BAAALgAECgEJAQAAAA==.',
Hi='Hillbroken:BAABLgAECn8uAAIgAAgJ4yAKAQChAgAgAAgJ4yAKAQChAgAAAA==.',
Ho='Holycross:BAAALgAECgIJAgAAAA==.Holysmokers:BAAALgAECgQJBAABLgAFFAQJCgAXALwUAA==.Holysnow:BAAALgADCgMJAwABLgAECgYJDQAGAAAAAA==.Holysoul:BAAALgAECgEJAQAAAA==.',
Hu='Huntertidus:BAAALgAECggJCgABLgAECgkJIAAeACAVAA==.',
['Hà']='Hànks:BAAALgAECggJDQAAAA==.',
Im='Imo:BAABLgAECn8aAAMaAAUJ+RQhGQB5AAAZAAUJoQzPqQAFAQAaAAQJ/hYhGQB5AAAAAA==.',
In='Intrepidz:BAAALgADCgcJCwABLgAFFAIJAwAGAAAAAA==.Inèvitable:BAABLgAECn8nAAIPAAgJnR40EwBiAgAPAAgJnR40EwBiAgAAAA==.',
Is='Istara:BAAALgADCggJCAAAAA==.',
Ja='Javeech:BAABLgAECn8ZAAMNAAgJdxZfLQCZAQANAAcJhhhfLQCZAQAOAAEJGwqvPwA3AAAAAA==.',
Je='Jebib:BAAALgAECgYJBgABLgAFFAgJJAAQACAdAA==.Jeod:BAAALgAECgEJAQAAAA==.',
Jo='Jolty:BAACLgAFFH8LAAIPAAQJJR5JHQBnAQAPAAQJJR5JHQBnAQAuAAQKfykAAw8ACQlWIqwMADUDAA8ACQlWIqwMADUDAAQABAmgFoYZAP0AAAAA.',
Ka='Kaiou:BAAALgADCgMJBgAAAA==.Kantor:BAABLgAECn8uAAIhAAgJwRYWEgDQAQAhAAgJwRYWEgDQAQAAAA==.Karnstein:BAABLgAECn8WAAQBAAcJDQnqMwDOAAABAAUJgwTqMwDOAAACAAQJ3AZ3QACYAAAiAAEJlA0hGAA0AAAAAA==.Kasenko:BAAALgAECgIJAgABLgAECgUJCQAGAAAAAA==.Kasryna:BAAALgAECgUJCQAAAA==.Kathinja:BAABLgAECn8VAAINAAgJvAdWPQBYAQANAAgJvAdWPQBYAQAAAA==.',
Ke='Kelumbria:BAAALgAECgcJDAAAAA==.Keta:BAAALgADCgYJBgAAAA==.Ketameanie:BAABLgAECn8bAAIHAAcJyxqEJwCeAQAHAAcJyxqEJwCeAQAAAA==.',
Ki='Kieran:BAAALgAECgQJCgAAAA==.Kitsunè:BAAALgAECgEJAQAAAA==.',
Km='Kmazing:BAABLgAECn8VAAMfAAgJ2wv0FwBmAQAfAAgJ2wv0FwBmAQAjAAIJRATxTwBGAAAAAA==.',
Kn='Knifèparty:BAAALgAECgMJAwAAAA==.',
Ko='Konoha:BAABLgAECn8dAAMUAAgJ0iBPBADUAgAUAAgJMh9PBADUAgAhAAMJfiPjQwApAQAAAA==.',
Ku='Kultag:BAAALgAECggJDQAAAA==.',
Ky='Kyaw:BAABLgAECn8UAAQMAAYJbRx6KAC2AQAMAAYJbRx6KAC2AQAXAAIJxRJZFgCTAAAYAAEJPRTTEQA/AAAAAA==.Kynzo:BAABLgAECn8oAAIDAAgJIBnhBAAUAgADAAgJIBnhBAAUAgAAAA==.',
La='Laykeezenith:BAACLgAFFH8TAAQkAAYJJh0jBwCrAQAkAAYJmxojBwCrAQANAAMJ7SLmNACxAAAOAAEJvQd3HABQAAAuAAQKfxsABCQACQmIIVUVAIcCACQACAnqIlUVAIcCAA0ABAnQHqNvAMQAAA4AAgl3EgcoAHUAAAAA.Lazuli:BAABLgAECn8mAAIlAAgJqxOOFgCdAQAlAAgJqxOOFgCdAQAAAA==.',
Le='Lehann:BAABLgAECn8iAAINAAgJeRAkKgCoAQANAAgJeRAkKgCoAQAAAA==.',
Li='Lichtech:BAAALgAECgYJDQABLgAFFAUJEwACAEoeAA==.',
Lu='Luciselda:BAAALgADCgUJBgAAAA==.Lunariah:BAAALgADCgkJEwAAAA==.Luvtarhugar:BAAALgADCgMJAwAAAA==.',
Ma='Magdalene:BAEALgAECgQJBQABLgAFFAQJCQAbAB4MAA==.Marenus:BAABLgAECn8sAAINAAgJhxKcKACvAQANAAgJhxKcKACvAQAAAA==.Masume:BAAALgAECgYJBgAAAA==.Maély:BAAALgAECgEJAgAAAA==.',
Me='Mechadead:BAAALgADCgIJAgAAAA==.Meowmix:BAAALgADCgcJCgAAAA==.',
Mi='Miantha:BAAALgAECgQJBQAAAA==.Michi:BAABLgAECn8sAAIQAAkJgyKpAQCFAwAQAAkJgyKpAQCFAwAAAA==.Midnights:BAAALgAECggJCgAAAA==.Mightymopo:BAAALgADCgMJAwAAAA==.Mikuki:BAABLgAECn8aAAINAAkJTSGjDQDRAgANAAkJTSGjDQDRAgAAAA==.Milkinghands:BAABLgAECn8cAAMjAAkJvg+sJQCFAQAjAAkJvg+sJQCFAQAfAAEJlAJSawAnAAAAAA==.Mizmonk:BAACLgAFFH8RAAIKAAUJWRYZDwA+AQAKAAUJWRYZDwA+AQAuAAQKfyIAAgoACQnxHqQJAO4CAAoACQnxHqQJAO4CAAAA.',
Mj='Mjölnir:BAAALgAECgEJAQAAAA==.',
Mo='Montfort:BAAALgADCggJDwAAAA==.Moovover:BAAALgAECggJCgAAAA==.',
Ms='Msmaho:BAAALgAECgMJAwAAAA==.',
Mu='Murionor:BAAALgADCgEJAQAAAA==.Mushuu:BAAALgADCgcJBwAAAA==.',
My='Mykian:BAABLgAECn8YAAIiAAcJXgc4CQASAQAiAAcJXgc4CQASAQAAAA==.Myrwynn:BAAALgAECgEJAQABLgAECggJJwAVAL8XAA==.Mythundon:BAAALgADCgUJBQAAAA==.',
Na='Nahion:BAAALgAECgEJAQAAAA==.Nashira:BAABLgAECn8aAAINAAgJ1BHGKQCqAQANAAgJ1BHGKQCqAQAAAA==.Nature:BAAALgAECgUJCwAAAA==.',
Ne='Necrana:BAAALgADCgEJAQAAAA==.Necrobyarg:BAAALgAECgYJDQAAAA==.Nemasus:BAABLgAECn8fAAIQAAgJZRuBDQB2AgAQAAgJZRuBDQB2AgAAAA==.Nembie:BAAALgADCgMJAwAAAA==.',
Ni='Ninjahh:BAACLgAFFH8GAAIMAAUJUAaiEAAdAQAMAAUJUAaiEAAdAQAuAAQKfxsAAgwACAkkEUgNAM0BAAwACAkkEUgNAM0BAAAA.Nioshei:BAABLgAECn8gAAIdAAgJxBHYJQCMAQAdAAgJxBHYJQCMAQAAAA==.Nisara:BAABLgAECn8gAAMjAAgJXiB/CgCpAgAjAAgJXiB/CgCpAgAfAAcJRhbFIgDAAQAAAA==.',
No='Nochmuerta:BAAALgAECggJEAAAAA==.Nogrid:BAABLgAECn8uAAITAAgJpxbtBwDSAQATAAgJpxbtBwDSAQAAAA==.Nossaria:BAAALgADCgEJAQAAAA==.Notmyface:BAAALgAECgcJDAABLgAFFAMJBQAeAP4ZAA==.',
Nu='Nuthar:BAABLgAECn8gAAIeAAcJvCQaDwCEAgAeAAcJvCQaDwCEAgAAAA==.',
Ny='Nyxandra:BAAALgAECgMJAwAAAA==.',
['Nò']='Nòhva:BAAALgAECgQJBAAAAA==.',
Ol='Oldeis:BAAALgAECgEJAQAAAA==.',
Om='Ominousowl:BAAALgAFFAEJAQABLgAFFAIJAwAGAAAAAA==.',
Or='Oregizm:BAAALgAECggJDAAAAA==.',
Pa='Pamburu:BAABLgAECn8jAAQNAAgJ8w20NwBuAQANAAgJpw20NwBuAQAkAAYJvgXdEgDIAAAOAAIJrQUNKgBgAAAAAA==.Papagrape:BAABLgAECn8iAAQBAAgJ2SD3AQD1AgABAAgJ2SD3AQD1AgACAAEJUgx1YgAyAAAiAAEJmgVjQgArAAAAAA==.Parzivàl:BAABLgAECn8kAAISAAgJ4haZEwB1AgASAAgJ4haZEwB1AgAAAA==.Paxa:BAABLgAECn8cAAIhAAYJDR8/EADoAQAhAAYJDR8/EADoAQAAAA==.',
Pe='Peacebox:BAAALgADCggJDAABLgAECggJFQAfANsLAA==.Persayis:BAAALgAECgMJAwAAAA==.',
Ph='Phoebel:BAAALgADCgkJEgAAAA==.Phoenixbodhi:BAAALgAECgQJBAAAAA==.',
Pi='Pickledeggs:BAAALgADCgEJAQABLgAECgQJBwAGAAAAAA==.',
Po='Podnov:BAACLgAFFH8NAAMkAAQJdxzIBgBXAQAkAAQJGhzIBgBXAQANAAIJpB3qNgCsAAAuAAQKfyAAAiQACQk6G8MNANYCACQACQk6G8MNANYCAAAA.',
Pr='Preyon:BAAALgAECgUJCgABLgAECgYJFgAKAEoPAA==.',
Py='Pyne:BAAALgADCgEJAQAAAA==.Pyrista:BAAALgAECgkJBQAAAA==.',
Qo='Qotho:BAABLgAECn8tAAINAAgJHxwBFAAwAgANAAgJHxwBFAAwAgAAAA==.',
Ra='Raistliin:BAAALgAECgYJDgAAAA==.Raithis:BAACLgAFFH8RAAINAAUJBxfaEgBQAQANAAUJBxfaEgBQAQAuAAQKfzEAAg0ACQl4Ib8EAEEDAA0ACQl4Ib8EAEEDAAAA.Ramhadin:BAEALgAECgMJBAABLgAECgYJEQAGAAAAAA==.',
Re='Rednaxel:BAABLgAECn8gAAIMAAgJhyI6AwCpAgAMAAgJhyI6AwCpAgAAAA==.Redvelvet:BAABLgAECn8iAAMjAAgJkxdaDAAjAgAjAAgJkxdaDAAjAgAfAAQJggbwWwCgAAAAAA==.Rekoner:BAABLgAECn8dAAIPAAgJGg/sNAClAQAPAAgJGg/sNAClAQAAAA==.Resi:BAAALgAECgEJAQAAAA==.Retarganator:BAABLgAECn8eAAMHAAcJ7BxOGgDrAQAHAAcJFRxOGgDrAQAmAAQJjBjREgAlAQAAAA==.',
Ri='Rixaa:BAAALgADCgMJAwABLgAECgUJDQAGAAAAAA==.',
Ro='Rocks:BAAALgAECgYJCAAAAA==.Romam:BAAALgAECgEJAQAAAA==.',
Ru='Rubyknight:BAAALgAECgEJAQAAAA==.',
Ry='Rykria:BAAALgADCgkJFAAAAA==.',
Sa='Samsonknight:BAAALgADCgYJBgAAAA==.Sanguinarian:BAABLgAECn8XAAIeAAgJIA3qVgBEAQAeAAgJIA3qVgBEAQAAAA==.Savash:BAAALgAECggJCQAAAA==.',
Sc='Scrubtotem:BAAALgAECgMJAwAAAA==.',
Se='Secksiecutie:BAABLgAECn8dAAMgAAgJoRTfAwDCAQAgAAgJoRTfAwDCAQAEAAUJdQt7JQCcAAAAAA==.Selanda:BAAALgADCgcJEQAAAA==.Serinar:BAAALgAECgQJBwAAAA==.',
Sh='Shoshin:BAABLgAECn8WAAMKAAYJSg+mOQCxAAAKAAYJSg+mOQCxAAAfAAMJrAtYXQCbAAAAAA==.Shïvana:BAAALgAECgMJCQAAAA==.',
Si='Silversaiyan:BAABLgAECn8xAAMLAAcJPyMgCQBWAgALAAcJPyMgCQBWAgAnAAEJXRiAOgBGAAAAAA==.',
Sl='Slade:BAABLgAECn8sAAMMAAgJYyKeAgDFAgAMAAgJYyKeAgDFAgAXAAMJ+xpoDAD1AAAAAA==.Slap:BAAALgAECgEJAQAAAA==.Sliyce:BAAALgAECgIJBgAAAA==.',
Sm='Smóke:BAABLgAECn8uAAIHAAgJ7BOIMQBwAQAHAAgJ7BOIMQBwAQAAAA==.',
Sn='Snowfawn:BAAALgAECgYJDQAAAA==.',
So='Sofedan:BAABLgAECn8uAAIkAAgJpA4qCACBAQAkAAgJpA4qCACBAQAAAA==.Sorgath:BAAALgAECgIJAgAAAA==.Soriel:BAAALgAECggJCAAAAA==.Sorokwa:BAAALgAECgcJDgAAAA==.',
Sq='Squids:BAAALgADCgQJBAAAAA==.',
St='Strongstork:BAAALgAECgEJAQABLgAECgQJCQAGAAAAAA==.',
Su='Sunsword:BAAALgAECgYJEQAAAA==.Suriden:BAAALgAECgUJBgAAAA==.',
Sw='Swagidan:BAABLgAECn8iAAIFAAgJkxgtCgDmAQAFAAgJkxgtCgDmAQAAAA==.Sweatermonk:BAAALgADCgIJAgABLgAECgYJBgAGAAAAAA==.Sweaterpally:BAAALgAECgYJBgAAAA==.Swiftera:BAABLgAECn8iAAISAAkJZhUoGQDBAQASAAkJZhUoGQDBAQAAAA==.Swiftlier:BAABLgAECn8hAAIKAAgJtxn6EQCzAQAKAAgJtxn6EQCzAQAAAA==.Swipegirl:BAAALgAECgYJCQAAAA==.',
Sy='Sylphrène:BAABLgAECn8gAAIFAAgJmQarFwAlAQAFAAgJmQarFwAlAQAAAA==.',
Ta='Taladan:BAAALgAECgEJAQAAAA==.Tandrana:BAAALgAECgMJAwAAAA==.Tankmepapi:BAAALgAECgMJAwAAAA==.Tanwen:BAAALgAECgYJDAAAAA==.Targypunch:BAAALgADCgcJBwABLgAECgcJHgAHAOwcAA==.Tatsunoshinn:BAAALgADCgEJAQAAAA==.',
Te='Techniqe:BAACLgAFFH8TAAICAAUJSh49DgBfAQACAAUJSh49DgBfAQAuAAQKfy0AAwIACAlXIhoHAAoDAAIACAlXIhoHAAoDACIABgkgIegSALMBAAAA.Techtides:BAAALgADCgUJBQABLgAFFAUJEwACAEoeAA==.Temperance:BAAALgADCgEJAQAAAA==.Temptations:BAAALgAECgEJAQAAAA==.Terminus:BAAALgAECgEJAQAAAA==.Terrylin:BAAALgAECgQJBQAAAA==.',
Th='Thaliá:BAAALgADCgkJFQAAAA==.Themachinist:BAAALgADCgYJBgAAAA==.Thomag:BAAALgADCgIJAgAAAA==.',
Ti='Ticebane:BAACLgAFFH8KAAMEAAQJLAgIEQDgAAAEAAQJLAgIEQDgAAAPAAIJfwHZhwB1AAAuAAQKfyMAAgQACQk0Ga0LAFgCAAQACQk0Ga0LAFgCAAAA.Tiduspullo:BAABLgAECn8gAAMeAAkJIBWQRAAWAgAeAAkJIBWQRAAWAgATAAEJRw6kRgAnAAAAAA==.Tiduswar:BAABLgAECn8cAAIWAAcJ2BoJDgCCAQAWAAcJ2BoJDgCCAQABLgAECgkJIAAeACAVAA==.Tinafay:BAAALgAECgcJDAAAAA==.Titanbeard:BAAALgAECgEJAQAAAA==.Titor:BAABLgAECn8WAAMBAAYJbRekEQAjAQABAAUJCBakEQAjAQAiAAUJeQ5KCwDjAAAAAA==.Tituspullo:BAAALgAECgUJBgABLgAECgkJIAAeACAVAA==.',
To='Tolduan:BAAALgAECgUJDQAAAA==.Totemik:BAAALgAECgMJBAAAAA==.Toughturkey:BAAALgAECgQJCQAAAA==.',
Tr='Tremorhoof:BAAALgADCgIJAwAAAA==.Tresera:BAAALgADCgEJAQAAAA==.Tricarnetry:BAABLgAECn8UAAIeAAcJPQY4fwDtAAAeAAcJPQY4fwDtAAAAAA==.Trufleshufle:BAAALgAECggJEQAAAA==.',
Uh='Uhtread:BAAALgADCgYJBQAAAA==.',
Un='Unholyfury:BAAALgADCgYJBgAAAA==.',
Va='Vapor:BAAALgAECgQJBQAAAA==.Vaquinha:BAAALgADCgUJBQAAAA==.Varyel:BAAALgAECgIJAgAAAA==.',
Ve='Velianne:BAAALgADCgUJBQAAAA==.Vellinada:BAAALgADCgMJAwABLgAFFAMJEAAhAP4kAA==.Verakis:BAABLgAECn8gAAIWAAgJuxH7DQCDAQAWAAgJuxH7DQCDAQAAAA==.Verndarí:BAAALgAECgcJCwABLgAECggJIQAKALcZAA==.Vervain:BAAALgAECgUJBQAAAA==.',
Vo='Vortheus:BAAALgAECgQJCgAAAA==.Votollis:BAAALgAECgQJBQAAAA==.',
Wa='Warlanen:BAAALgAECgEJAQAAAA==.Warning:BAAALgADCgUJBQAAAA==.Warpiggies:BAAALgADCgkJCAAAAA==.',
Wi='Widdy:BAAALgAECgYJDgAAAA==.Willbur:BAABLgAECn8uAAIJAAgJ7xaQMQDaAQAJAAgJ7xaQMQDaAQAAAA==.Wittledwagon:BAAALgADCgkJCQAAAA==.',
Wu='Wurthwhile:BAAALgAECgYJCAAAAA==.',
Wy='Wylaniris:BAAALgADCgQJBAAAAA==.Wyndywalker:BAABLgAECn8cAAIcAAgJOgZwIgAlAQAcAAgJOgZwIgAlAQAAAA==.',
Xa='Xaveil:BAAALgADCgEJAQAAAA==.',
Xe='Xenosian:BAAALgAECgkJCQAAAA==.',
Xi='Xinnuo:BAAALgAECgIJAQAAAA==.',
Xy='Xydias:BAAALgAECggJCwAAAA==.Xyra:BAAALgADCgcJBwAAAA==.',
Yo='Yoku:BAAALgAECggJEwAAAA==.',
Za='Zalgarian:BAAALgAECgMJAwAAAA==.Zamønk:BAABLgAECn8YAAMKAAcJFg8VOABqAQAKAAcJFg8VOABqAQAfAAIJYAxxbgBXAAAAAA==.Zaphoidvtwo:BAAALgADCgcJBwAAAA==.Zason:BAAALgADCgMJAwAAAA==.Zatari:BAAALgADCgMJAwAAAA==.',
Ze='Zelectie:BAABLgAECn8XAAIIAAgJbhcxCgD3AQAIAAgJbhcxCgD3AQABLgAFFAYJFAAKAH0aAA==.Zelzaikin:BAAALgAECgQJBgAAAA==.Zevon:BAAALgADCgkJCQAAAA==.',
Zi='Zinazarinara:BAAALgADCgcJEQAAAA==.Zirril:BAAALgADCgcJDwAAAA==.',
Zo='Zombiechick:BAAALgAECgMJBAAAAA==.',
['ßr']='ßrigitte:BAAALgADCgkJEQAAAA==.',
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

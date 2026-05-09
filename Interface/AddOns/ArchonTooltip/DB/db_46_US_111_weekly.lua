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

local lookup = {'Monk-Mistweaver','Warrior-Arms','Warrior-Fury','Warrior-Protection','Mage-Frost','Warlock-Demonology','Hunter-BeastMastery','Unknown-Unknown','Paladin-Retribution','Hunter-Survival','Druid-Restoration','DemonHunter-Devourer','Evoker-Preservation','Evoker-Devastation','Paladin-Holy','DeathKnight-Unholy','Warlock-Affliction','Monk-Windwalker','Monk-Brewmaster','DeathKnight-Blood','DemonHunter-Havoc','Priest-Shadow','Priest-Holy','Rogue-Subtlety','Priest-Discipline','Shaman-Elemental','Shaman-Enhancement','Rogue-Assassination','Druid-Guardian','Druid-Feral','Druid-Balance','Evoker-Augmentation',}
local provider = {region='US',realm='Gorgonnash',name='US',type='weekly',zone=46,date='2026-05-08',data={Aa='Aakira:BAAALgAECgcJDAAAAA==.Aangie:BAABLgAECn8YAAIBAAcJnQaFMwDEAAABAAcJnQaFMwDEAAAAAA==.Aanjie:BAABLgAECn8aAAIBAAYJQglQLQDoAAABAAYJQglQLQDoAAAAAA==.',
Ab='Abban:BAAALgAECgMJAwAAAA==.Abrastal:BAAALgAECgQJCAAAAA==.',
Ad='Adrestia:BAAALgADCgcJBwAAAA==.',
Ak='Akbar:BAAALgAECgUJBQAAAA==.',
Al='Alline:BAAALgAECgYJCwAAAA==.Alswaron:BAAALgAECgQJDAAAAA==.',
Am='Amador:BAACLgAFFH8GAAQCAAMJrQxGFAB7AAACAAIJ8wpGFAB7AAADAAEJ1A8SIQBTAAAEAAEJIBCaDwBHAAAuAAQKfycABAIACAkOIcQDAF0CAAIABwkOIcQDAF0CAAMABAndGuBpAA4BAAQAAgmdEIo6AHcAAAAA.Amorlan:BAAALgAECgEJAQAAAA==.Amyra:BAAALgAECgEJAQAAAA==.',
An='Annox:BAAALgAECgQJBwAAAA==.',
Ap='Apsallar:BAAALgAECgcJDgAAAA==.',
Ar='Arcanism:BAABLgAECn8cAAIFAAcJrhP7agA7AQAFAAcJrhP7agA7AQAAAA==.Arlas:BAAALgAECgIJAwAAAA==.Arthone:BAAALgADCgUJBQAAAA==.',
As='Asstalor:BAABLgAECn8XAAIGAAgJXQ84MQCfAQAGAAgJXQ84MQCfAQAAAA==.',
Au='Auggy:BAAALgADCgEJAQAAAA==.Auryon:BAABLgAECn8jAAIHAAgJAiH+DgBfAgAHAAgJAiH+DgBfAgAAAA==.',
Av='Avelna:BAAALgADCgYJBgABLgADCgcJDQAIAAAAAA==.',
Az='Azmodea:BAAALgADCgEJAgAAAA==.',
Ba='Baccstab:BAAALgAECgYJDAAAAA==.Bagains:BAAALgADCgcJDwAAAA==.Baraka:BAAALgAECgYJCgAAAA==.',
Bi='Bigb:BAAALgAECggJDwABLgAFFAgJHQAFAH0jAA==.Bigolcrittie:BAAALgADCgIJAgAAAA==.',
Bl='Bluè:BAAALgAECgYJCwAAAA==.',
Bo='Bobdaunicorn:BAAALgAECgEJAQAAAA==.Boltz:BAAALgAECgMJAwAAAA==.Bombalaharis:BAAALgAECgcJDQAAAA==.',
Br='Brekke:BAABLgAECn8oAAIJAAkJdBazJADwAQAJAAkJdBazJADwAQAAAA==.Brokenbow:BAABLgAECn8XAAMKAAkJpxNtEQCsAQAKAAkJVw5tEQCsAQAHAAQJCRjCfQDuAAAAAA==.',
Bu='Bullshaft:BAAALgAECgEJAQAAAA==.Buntz:BAABLgAECn8YAAIJAAgJciL/CQC5AgAJAAgJciL/CQC5AgABLgAECggJHAADACoYAA==.Bushmethsin:BAACLgAFFH8SAAILAAUJHCOYBAD8AQALAAUJHCOYBAD8AQAuAAQKfxQAAgsACAlUIgweAE4CAAsACAlUIgweAE4CAAAA.Buttery:BAAALgAECgUJDwAAAA==.',
Ca='Cabb:BAAALgADCgkJGAAAAA==.',
Ce='Ceedubble:BAAALgAECggJDAAAAA==.Celestine:BAAALgADCgYJBgABLgAECggJIAAMAG4NAA==.',
Ch='Charmanderz:BAABLgAECn8jAAMNAAgJfw1bDgBeAQANAAgJfw1bDgBeAQAOAAEJIhWaOwA/AAAAAA==.Cherchlglsia:BAAALgADCgQJCAAAAA==.Chewsdee:BAAALgAECgQJBAAAAA==.Christlovesu:BAAALgAECgIJAgAAAA==.Chuckrules:BAAALgADCgcJDgAAAA==.',
Cl='Clackshi:BAAALgAECgYJCgAAAA==.',
Cr='Critable:BAABLgAECn8mAAMPAAkJ+xAuFQDmAQAPAAkJ+xAuFQDmAQAJAAgJNggYggB2AQAAAA==.',
Cu='Curst:BAAALgAECggJEwAAAA==.',
Da='Dagares:BAAALgADCggJDQAAAA==.Dahnte:BAAALgAECgEJAQAAAA==.',
De='Dechala:BAABLgAECn8gAAIMAAgJbg0EOQBSAQAMAAgJbg0EOQBSAQAAAA==.Deezknights:BAACLgAFFH8PAAIQAAUJ4iEUGgBwAQAQAAUJ4iEUGgBwAQAuAAQKfx8AAhAACQkGJUwJAFIDABAACQkGJUwJAFIDAAAA.Deezpuffs:BAAALgAFFAMJAwABLgAFFAUJDwAQAOIhAA==.Deezrage:BAAALgADCgYJBgAAAA==.Derailed:BAAALgADCgEJAgAAAA==.Dergon:BAABLgAECn8dAAIGAAgJuhd+IwDeAQAGAAgJuhd+IwDeAQAAAA==.Destiria:BAABLgAECn8kAAMGAAgJsxlYGQAZAgAGAAgJsxlYGQAZAgARAAMJeQd4JwBUAAAAAA==.Devistatorxx:BAAALgAECgUJBQAAAA==.',
Do='Doggyystyle:BAAALgAECgEJAQAAAA==.Donaldpump:BAAALgAECgYJBwAAAA==.Doomedturtle:BAAALgADCgYJCQAAAA==.Doublekill:BAAALgAECgUJCQAAAA==.',
Du='Duergan:BAABLgAECn8iAAQSAAgJMQ8wGgBSAQASAAgJMQ8wGgBSAQATAAYJbgWjMwDLAAABAAEJRQMCcgAhAAAAAA==.',
Fa='Faelyn:BAAALgADCgEJBAAAAA==.Fansy:BAAALgAECgEJAQAAAA==.',
Fi='Fillycheese:BAAALgAECgEJAQAAAA==.',
Fl='Fleurelle:BAAALgAECgIJAgAAAA==.',
Fr='Frollo:BAAALgAECgEJAQAAAA==.Frosstitute:BAAALgAECgMJAwAAAA==.',
Fu='Furfiend:BAABLgAECn8XAAIQAAYJiRydVABAAQAQAAYJiRydVABAAQAAAA==.',
Gi='Giantdog:BAAALgAECgUJBQAAAA==.Gilraen:BAABLgAECn8mAAMCAAgJdQ7nEAA9AQADAAgJdQ5lTQBxAQACAAgJYgjnEAA9AQAAAA==.',
Go='Gorgrand:BAAALgAECgcJBwAAAA==.Gothbiotch:BAAALgAECgMJAwAAAA==.',
Gr='Greggnog:BAAALgAECgcJDAAAAA==.Greggy:BAAALgAECgUJCQABLgAECgcJDAAIAAAAAA==.Grenache:BAAALgAECgMJBAAAAA==.',
Ha='Halfworld:BAAALgADCgYJBgAAAA==.Happydaze:BAABLgAECn8fAAMUAAgJ6hnTCgDKAQAUAAgJkRnTCgDKAQAQAAIJ2Rd77gChAAAAAA==.Haxthedruid:BAAALgAECgEJAQAAAA==.Haxthemonk:BAAALgAECgEJAQAAAA==.',
He='Hemotoxin:BAAALgAECgMJAwAAAA==.Hendel:BAAALgAECgQJBgAAAA==.Herkaferk:BAAALgAECgYJEwAAAA==.',
Ho='Hojx:BAAALgAECgEJAQAAAA==.',
Hr='Hrolf:BAAALgAECgMJBgABLgAECggJIgASADEPAA==.',
Il='Illiannà:BAAALgAECgYJCQABLgAECggJIwANAH8NAA==.Illidont:BAAALgAECgYJCgAAAA==.Illijr:BAABLgAECn8VAAIVAAcJkA/XFABEAQAVAAcJkA/XFABEAQAAAA==.',
It='Ithil:BAAALgADCgkJDwAAAA==.',
Ja='Jaemison:BAAALgADCgQJAwAAAA==.',
Ji='Jicks:BAAALgAECgYJEgAAAA==.',
Jk='Jkass:BAAALgAECgYJEwAAAA==.',
Ju='Judgementdày:BAAALgAECgQJCgAAAA==.',
['Jà']='Jàk:BAAALgADCgUJBQAAAA==.',
Ka='Kamaeria:BAABLgAECn8eAAIWAAgJvQg3IAA7AQAWAAgJvQg3IAA7AQABLgAECggJKQAHAOEPAA==.Kaíros:BAAALgADCgMJAwAAAA==.',
Kh='Khaotica:BAAALgADCgkJCQAAAA==.',
Ki='Kiandara:BAACLgAFFH8RAAMDAAUJwBP+DAA3AQADAAUJ1g7+DAA3AQACAAMJZQ8kDQDZAAAuAAQKfyEAAwMACQnvG+UMAO8CAAMACQnDG+UMAO8CAAQABQkcG9odAFcBAAAA.Kikkoman:BAAALgAFFAEJAQAAAA==.Kilmas:BAAALgAECgIJAgAAAA==.Kirant:BAAALgADCggJDQAAAA==.Kirara:BAAALgADCgYJBgAAAA==.',
Ko='Kooz:BAAALgADCgUJBQAAAA==.Kooze:BAAALgADCgUJCAAAAA==.Koozo:BAAALgADCgMJAwAAAA==.',
Kt='Kt:BAABLgAECn8aAAIFAAcJNRMuTgB/AQAFAAcJNRMuTgB/AQAAAA==.',
Ky='Kynrath:BAAALgAECgIJAgAAAA==.',
La='Laurie:BAAALgADCgMJBgAAAA==.Lava:BAAALgADCgUJBQABLgAECggJDwAIAAAAAA==.Lavablast:BAAALgADCgYJCwAAAA==.',
Le='Lelanie:BAAALgADCggJDgAAAA==.',
Li='Lichnfamous:BAAALgAECgcJEAAAAA==.Lightfrost:BAAALgADCgIJAgAAAA==.Lightning:BAAALgAECgUJCAAAAA==.Likkan:BAAALgAECgEJAQAAAA==.Lilithdawn:BAABLgAECn8gAAIXAAgJWB1DCABrAgAXAAgJWB1DCABrAgAAAA==.',
Lo='Lockwar:BAAALgAECgYJEAAAAA==.Louvre:BAABLgAECn8hAAIYAAkJBBhuBACEAgAYAAkJBBhuBACEAgAAAA==.',
Lu='Lukarian:BAAALgAECgQJBQAAAA==.',
Ma='Makthra:BAAALgAECgQJDQAAAA==.Marek:BAAALgADCgUJCAAAAA==.Marionette:BAAALgADCggJGQAAAA==.Mawseeker:BAAALgADCgEJAQAAAA==.',
Me='Megabettegaa:BAABLgAECn9KAAIQAAkJLRevGgAqAgAQAAkJLRevGgAqAgAAAA==.Mennathil:BAAALgADCgEJAQAAAA==.Meric:BAAALgADCgcJDgAAAA==.',
Mi='Midnight:BAAALgAECgYJCAABLgAECgcJGgAEAPwhAA==.Milo:BAAALgAECgQJCwAAAA==.Miniangel:BAACLgAFFH8HAAIXAAMJNw+bEADNAAAXAAMJNw+bEADNAAAuAAQKfx4AAxcACQl6FYgIAGYCABcACQl6FYgIAGYCABYACAk+EOwoAJMBAAAA.Mixednuts:BAAALgAECgIJAgAAAA==.',
Mo='Molasses:BAACLgAFFH8IAAIFAAMJVwtlSwDyAAAFAAMJVwtlSwDyAAAuAAQKfzAAAgUACQlzGakSAIMCAAUACQlzGakSAIMCAAAA.Moof:BAAALgAECgEJAQAAAA==.',
Na='Najitar:BAAALgAECgEJAQAAAA==.Nazaibrew:BAAALgADCgYJBgABLgAECgkJKQAZAAweAA==.',
Ne='Necromalus:BAAALgADCgEJAwAAAA==.Neerx:BAAALgADCgUJBQAAAA==.',
Nu='Nubkselk:BAABLgAECn8lAAIMAAgJqx5ODABsAgAMAAgJqx5ODABsAgAAAA==.Nurishment:BAACLgAFFH8ZAAILAAYJPhSTBwC/AQALAAYJPhSTBwC/AQAuAAQKfyIAAgsACQn2HWsSAKICAAsACQn2HWsSAKICAAAA.',
Ny='Nyrr:BAAALgADCgEJAgAAAA==.',
Og='Ogmurka:BAAALgAECgEJAQAAAA==.',
On='Oni:BAAALgADCgUJBQAAAA==.Onitachi:BAABLgAECn8pAAMaAAgJ/w8mJAA0AQAaAAgJ/w8mJAA0AQAbAAQJawl1FgCfAAAAAA==.',
Op='Optistriker:BAABLgAECn8oAAILAAgJUhUFGwDrAQALAAgJUhUFGwDrAQAAAA==.',
Oy='Oythsar:BAAALgADCgQJBAAAAA==.',
Pa='Painfree:BAAALgADCgQJBAAAAA==.Papabear:BAAALgAECgEJAQAAAA==.',
Pi='Pig:BAABLgAECn8cAAIDAAgJKhjYKwAGAgADAAgJKhjYKwAGAgAAAA==.Pinks:BAAALgADCgkJCQAAAA==.',
Po='Poplockndrop:BAAALgAECgUJBgAAAA==.Portion:BAABLgAECn8oAAIFAAcJaBz/WQArAgAFAAcJaBz/WQArAgAAAA==.',
Pr='Pretentious:BAABLgAECn8YAAIJAAgJoh8nJgCOAgAJAAgJoh8nJgCOAgAAAA==.Prettyfun:BAAALgADCgUJBQAAAA==.Prettysavage:BAAALgAECgIJAgAAAA==.Primo:BAAALgADCgYJEQAAAA==.',
Ra='Radicalism:BAAALgAECgQJBQAAAA==.Ranigard:BAAALgAECgUJCAAAAA==.Rantioc:BAAALgAECgIJAgAAAA==.Raugan:BAAALgADCggJCAAAAA==.',
Re='Reparations:BAAALgAECgkJBgAAAA==.Repentofsin:BAAALgAECgQJBAAAAA==.Rexbriefs:BAAALgAECgEJAgAAAA==.',
Ri='Riptong:BAAALgADCgEJAQAAAA==.',
Ro='Rovinj:BAAALgAECgkJBQAAAA==.',
Ru='Rumi:BAABLgAECn8XAAIMAAcJVRJcNQBgAQAMAAcJVRJcNQBgAQAAAA==.',
Ry='Rydle:BAAALgAECgYJBgAAAA==.',
Sa='Sanlesh:BAAALgADCgUJBgAAAA==.Sapodillà:BAAALgAECgcJBwAAAA==.Sarijevo:BAAALgAECgkJBQAAAA==.Saurax:BAAALgADCgMJAwAAAA==.',
Sc='Scatz:BAAALgADCgIJAgAAAA==.Scott:BAAALgAECgcJBwAAAA==.Scylla:BAAALgAECgYJDwAAAA==.',
Se='Sevrin:BAABLgAECn8jAAIYAAgJCyM2AwCqAgAYAAgJCyM2AwCqAgAAAA==.',
Sh='Shadowfuryy:BAAALgAECgUJBQAAAA==.Shalati:BAAALgADCgYJBgAAAA==.Shestrouble:BAAALgAFFAIJAgAAAA==.Shirerat:BAAALgADCgMJBAAAAA==.Shtzson:BAAALgAECgYJBgAAAA==.Shyjinx:BAAALgAECgYJBgAAAA==.Shîft:BAABLgAECn8jAAMYAAgJySBLEwB7AQAYAAYJDiJLEwB7AQAcAAMJgh7YCwABAQAAAA==.',
Si='Siiwwy:BAAALgAECgMJAwAAAA==.',
Sl='Slice:BAAALgAECgUJDAAAAA==.',
So='Solicide:BAABLgAECn8jAAUdAAgJJRvFBgDYAQAdAAgJMRfFBgDYAQAeAAYJpxseDwC9AQALAAEJRBMayAA6AAAfAAEJzwxEfgA0AAAAAA==.Sonarra:BAAALgAECgYJBgAAAA==.',
Sp='Sparkle:BAACLgAFFH8VAAIgAAUJaRQ1FgAvAQAgAAUJaRQ1FgAvAQAuAAQKf0IAAiAACQkMHa8FACsDACAACQkMHa8FACsDAAAA.Splatacular:BAAALgADCgEJAQAAAA==.',
St='Stolenhearth:BAABLgAECn8bAAIDAAYJewtYMQAGAQADAAYJewtYMQAGAQAAAA==.',
Sv='Svets:BAABLgAECn8pAAMZAAkJDB65AwDrAgAZAAkJDB65AwDrAgAXAAEJ3AnFhQArAAAAAA==.',
Sw='Swavey:BAAALgADCgQJBAAAAA==.',
Sy='Syrana:BAAALgADCgEJAQAAAA==.',
Te='Teeanna:BAAALgAECgIJAgABLgAECgIJAwAIAAAAAA==.Temaile:BAAALgADCgEJBAAAAA==.Tenin:BAAALgADCgEJAQAAAA==.',
Th='Thinmint:BAAALgADCgEJAQAAAA==.',
Ti='Tinnman:BAAALgADCgYJBgAAAA==.Tippsie:BAEBLgAECn8VAAIYAAYJ4SNOCQAMAgAYAAYJ4SNOCQAMAgAAAA==.',
To='Toughguytony:BAAALgADCgUJBgAAAA==.',
Tr='Treydk:BAABLgAFFH8FAAIQAAMJ3AlqVADkAAAQAAMJ3AlqVADkAAAAAA==.Trreyy:BAABLgAECn8fAAIJAAgJqh5TKACEAgAJAAgJqh5TKACEAgAAAA==.',
Ts='Tsimfuqis:BAAALgAFFAMJAwAAAA==.',
Tw='Twizzy:BAABLgAECn8pAAIHAAgJ4Q/DKQCqAQAHAAgJ4Q/DKQCqAQAAAA==.',
Ty='Tyranhikar:BAAALgADCgEJAQAAAA==.',
Tz='Tzechan:BAABLgAECn8VAAMPAAgJWxsRLgDLAQAPAAcJmRwRLgDLAQAJAAEJXBEAAAAAAAAAAA==.',
Ug='Uggalee:BAAALgAECgIJAgAAAA==.',
Va='Valtirya:BAAALgAECgQJBgAAAA==.Vayzen:BAABLgAECn8YAAIgAAcJDB4nEwBNAgAgAAcJDB4nEwBNAgAAAA==.',
Vi='Virexus:BAAALgADCgIJAgAAAA==.',
Vo='Voidfree:BAAALgAECgYJEwAAAA==.',
Vy='Vynarc:BAABLgAECn8oAAIJAAgJhxE7PACRAQAJAAgJhxE7PACRAQAAAA==.',
Wa='Warcrimes:BAAALgAECgEJAQAAAA==.Watervendor:BAABLgAECn8jAAIFAAgJXxpiIQAkAgAFAAgJXxpiIQAkAgAAAA==.',
We='Wearegroot:BAAALgAECgEJAQAAAA==.Webedeadiy:BAAALgADCgEJAQAAAA==.',
Wi='Wiggimbottom:BAAALgAECgYJEgAAAA==.Wihtè:BAAALgADCgUJCQAAAA==.Willscarlet:BAAALgADCgMJAwAAAA==.',
Wo='Wolffoxfangs:BAAALgAECgYJDAAAAA==.',
Xe='Xeados:BAAALgAECgIJAgAAAA==.',
Yi='Yin:BAAALgADCgcJDQAAAA==.',
Za='Zaquel:BAAALgAECgUJBQAAAA==.Zarcissa:BAAALgAECgMJBgAAAA==.Zavira:BAAALgADCgcJBwAAAA==.',
Zy='Zyrin:BAAALgAECgYJDwAAAA==.',
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

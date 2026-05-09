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

local lookup = {'Druid-Restoration','Warrior-Arms','Warrior-Fury','Evoker-Augmentation','Priest-Holy','Mage-Frost','Warlock-Demonology','DeathKnight-Frost','Hunter-BeastMastery','Hunter-Survival','Unknown-Unknown','Evoker-Preservation','Warlock-Affliction','Warlock-Destruction','DeathKnight-Blood','Priest-Discipline','Rogue-Assassination','Paladin-Holy','Paladin-Retribution','Monk-Mistweaver','Paladin-Protection','Evoker-Devastation','DemonHunter-Devourer','Shaman-Elemental','DeathKnight-Unholy','DemonHunter-Havoc','Druid-Balance','DemonHunter-Vengeance','Monk-Windwalker','Monk-Brewmaster','Shaman-Restoration','Rogue-Subtlety','Shaman-Enhancement','Druid-Feral','Druid-Guardian','Warrior-Protection','Priest-Shadow','Hunter-Marksmanship',}
local provider = {region='US',realm='Ysera',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Ababear:BAABLgAECn8UAAIBAAgJnR2aDQDOAgABAAgJnR2aDQDOAgAAAA==.Abardi:BAAALgADCgUJBgAAAA==.',
Ad='Adeki:BAAALgADCgEJAQAAAA==.',
Ae='Aedaria:BAAALgADCgMJAwAAAA==.Aegis:BAAALgAECgEJAgAAAA==.Aeira:BAAALgADCgYJCQAAAA==.Aelora:BAAALgADCgMJAwAAAA==.Aerenna:BAAALgADCgUJBQAAAA==.',
Ag='Agakk:BAACLgAFFH8KAAICAAMJWCGxCAAcAQACAAMJWCGxCAAcAQAuAAQKfy8AAgIACQmsI70AACMDAAIACQmsI70AACMDAAAA.Agilities:BAAALgAECgQJBAAAAA==.',
Al='Alarrius:BAABLgAECn8aAAMCAAgJnBJHEwAkAQADAAYJ/RWhJQBGAQACAAYJGRBHEwAkAQAAAA==.Albedö:BAAALgAECgYJBgABLgAFFAQJCQAEAHoIAA==.Alescia:BAEALgADCgcJCAABLgAECggJIQAFAKMYAA==.Alestormia:BAAALgAFFAIJAgAAAA==.Allimental:BAAALgADCgEJAQAAAA==.Allionys:BAABLgAECn8VAAIGAAYJMSSTKQD8AQAGAAYJMSSTKQD8AQAAAA==.Alorelia:BAAALgADCgUJBQAAAA==.Aloris:BAAALgAECgYJEwAAAA==.Alyêska:BAAALgAECgIJAwAAAA==.',
Am='Amanises:BAAALgAECgcJDgAAAA==.Amilara:BAAALgAECgUJCQAAAA==.',
An='Ananaya:BAAALgAECgQJBwABLgAECgcJHAAHAMMRAA==.Andinestiri:BAAALgAECgYJDgAAAA==.Andolastrasz:BAAALgADCgEJAQAAAA==.Andy:BAAALgAECgEJAgAAAA==.Aneethea:BAAALgADCgYJBgAAAA==.Anniklynn:BAAALgADCgIJAgAAAA==.Antaric:BAAALgAECgUJCAAAAA==.Anyalem:BAAALgAECgEJAQAAAA==.',
Ao='Ao:BAAALgAECgYJBgAAAA==.',
Ap='Apotic:BAABLgAECn8ZAAIIAAgJIwgaBwBAAQAIAAgJIwgaBwBAAQAAAA==.Apuntar:BAAALgADCgQJBgAAAA==.',
Aq='Aquamaree:BAAALgAECgYJCwAAAA==.Aquamyth:BAAALgADCgMJAwAAAA==.Aquilla:BAACLgAFFH8KAAMJAAUJcwbpLgDQAAAJAAQJRQfpLgDQAAAKAAMJ6AVRBQCOAAAuAAQKfxoAAwoACAkWGVcMAAgCAAoACAlZFlcMAAgCAAkABgmBG8hhAEIBAAAA.',
Ar='Archenea:BAAALgAECgMJAwAAAA==.Archenore:BAABLgAECn8XAAIDAAcJagcONQD0AAADAAcJagcONQD0AAAAAA==.Ariisa:BAAALgAECgUJBQAAAA==.Arkify:BAAALgADCgYJBgAAAA==.Armadyl:BAAALgAECgEJAQABLgAECgQJBwALAAAAAA==.Around:BAAALgADCgYJBgAAAA==.Arrancar:BAAALgAECgIJAwAAAA==.Arrianda:BAAALgADCgQJBAAAAA==.',
As='Ashw:BAAALgAECgcJEgAAAA==.Asukka:BAAALgAECgcJEQAAAA==.Asëya:BAAALgAECgMJBQAAAA==.',
At='Atomique:BAACLgAFFH8YAAIMAAUJohMNCgB4AQAMAAUJohMNCgB4AQAuAAQKf0EAAgwACAkXH9QGANMCAAwACAkXH9QGANMCAAAA.Attenborough:BAAALgAECgUJBgABLgAECgYJDwALAAAAAA==.',
Au='Auggie:BAAALgADCgEJAQAAAA==.',
Av='Avalíne:BAAALgADCgUJBQAAAA==.Avesa:BAAALgAECgMJBAAAAA==.Avoidant:BAAALgAECggJEwAAAA==.',
Ay='Aydir:BAAALgADCgUJBwAAAA==.Aylithe:BAAALgAECgQJBAAAAA==.',
Az='Azanadra:BAAALgAECgQJBwAAAA==.Azazell:BAAALgAECgQJBQAAAA==.Azenea:BAABLgAECn8fAAQNAAgJBgauDQBZAQANAAgJRwWuDQBZAQAOAAEJ5AhTKQAxAAAHAAIJhwGvIAEwAAAAAA==.',
Ba='Baculum:BAABLgAECn8aAAIPAAgJZBh2DQCaAQAPAAgJZBh2DQCaAQAAAA==.Bacõn:BAAALgAECgQJBAAAAA==.Badmoonrisin:BAAALgAECgMJAwAAAA==.Bainne:BAAALgAECgQJCAAAAA==.Ballzach:BAABLgAECn8ZAAIQAAYJUB1/GgBdAQAQAAYJUB1/GgBdAQABLgAFFAYJHQAPAAEjAA==.Bazookabob:BAAALgAECgYJEgAAAA==.',
Be='Beangles:BAAALgADCggJDAAAAA==.Bearlylegal:BAAALgAECgYJBgABLgAECgkJBgALAAAAAA==.Becky:BAAALgADCgkJCgABLgAECggJEwALAAAAAA==.Beekyy:BAAALgAECggJEwAAAA==.Belenova:BAAALgAECgUJBgAAAA==.Bellapearl:BAAALgAECgMJBAAAAA==.Berkyn:BAAALgADCgMJAwAAAA==.',
Bi='Bittydrood:BAAALgADCgkJDgAAAA==.Bittylexis:BAAALgAECgQJBQAAAA==.',
Bl='Blakheart:BAABLgAECn8pAAIRAAkJdRU6BADTAQARAAkJdRU6BADTAQAAAA==.Bleuopal:BAAALgADCgcJDAAAAA==.Blueaxle:BAABLgAECn8hAAMSAAgJ7hW0FADrAQASAAgJ7hW0FADrAQATAAIJpgHJMQFAAAAAAA==.Blur:BAAALgADCgkJGQAAAA==.Bluzzy:BAAALgAECgEJAQABLgADCgcJEQALAAAAAA==.Blèu:BAABLgAECn8WAAIUAAgJxgnxJgASAQAUAAgJxgnxJgASAQAAAA==.',
Bo='Boomdoom:BAAALgAECgQJBAAAAA==.Bootycat:BAAALgADCgcJBwABLgADCgkJCgALAAAAAA==.Bouffenièce:BAAALgAECgQJBwAAAA==.Boufsy:BAAALgADCgkJEQAAAA==.',
Br='Brakii:BAAALgAECgIJAgAAAA==.Breathe:BAACLgAFFH8FAAIBAAMJRg+DIQDRAAABAAMJRg+DIQDRAAAuAAQKfxUAAgEABwkPHuwVABYCAAEABwkPHuwVABYCAAAA.Brewballs:BAABLgAECn8jAAIUAAcJGgv6JAAgAQAUAAcJGgv6JAAgAQAAAA==.Brynarra:BAAALgADCgUJBQAAAA==.',
Bu='Bubbletea:BAAALgAECgQJCgAAAA==.Bunnicula:BAABLgAECn8eAAMNAAgJmRlyBwDcAQANAAcJAh1yBwDcAQAHAAUJ5QmXZwD+AAAAAA==.',
Bw='Bwanga:BAAALgAECgYJDwAAAA==.',
['Bö']='Böömer:BAAALgAECgQJBwAAAA==.',
Ca='Calmac:BAAALgAFFAMJBAAAAA==.Cameron:BAAALgAECgYJDAAAAA==.Capetonrex:BAAALgAECgEJAQAAAA==.Cavall:BAAALgAECgMJAwAAAA==.Caythus:BAACLgAFFH8IAAMOAAMJiB71EABeAAAHAAIJ8xukUgCpAAAOAAEJsCP1EABeAAAuAAQKfxYAAw4ABwnhJLsLAAYCAA4ABQkPJLsLAAYCAAcABQnmIglRANUBAAAA.',
Ce='Celeana:BAAALgAECgYJDwAAAA==.Celeleron:BAAALgADCgcJBwAAAA==.Celencia:BAAALgAECgUJBQAAAA==.',
Ch='Chadmcguffin:BAABLgAECn8WAAIVAAgJoCNpCABSAgAVAAgJoCNpCABSAgAAAA==.Chakabad:BAAALgAECgMJBwAAAA==.Chalgar:BAAALgAECgMJBAAAAA==.Chaosblossom:BAAALgADCgYJBwAAAA==.Cheezeballs:BAAALgADCgEJAQABLgAFFAEJAQALAAAAAA==.Chenahala:BAAALgAECgQJCAAAAA==.Chibeard:BAAALgAECgkJBgAAAA==.Chåni:BAAALgAECgYJEwAAAA==.',
Ci='Ciege:BAABLgAECn8iAAMEAAkJ4xLyFgCKAQAEAAgJrhDyFgCKAQAWAAYJABKWBwA+AQAAAA==.Cinrah:BAABLgAFFH8JAAIXAAUJCxSIGwA7AQAXAAUJCxSIGwA7AQAAAA==.',
Cl='Cloudwalker:BAAALgADCgkJCwAAAA==.',
Co='Coffeelatte:BAAALgAECgEJAQAAAA==.Complainz:BAAALgADCggJEgAAAA==.Concinnat:BAAALgADCgUJBQAAAA==.Confessorr:BAAALgADCgYJBgAAAA==.Cosantóir:BAAALgAECgUJBgAAAA==.',
Cr='Crispysock:BAAALgAECgYJDQAAAA==.Croda:BAAALgAECgYJCwAAAA==.Crowe:BAAALgAECgIJAwAAAA==.Cröno:BAAALgAECgYJDAAAAA==.',
Cu='Cursez:BAAALgAECgYJEQABLgAFFAUJGwAYAMwiAA==.',
Cy='Cylndra:BAAALgADCgcJBwAAAA==.Cynderr:BAAALgAECgUJCAAAAA==.',
['Cè']='Cèrc:BAAALgAECgIJAwAAAA==.',
Da='Daemian:BAAALgAECgUJCgABLgAECggJFgAVAKAjAA==.Dakarba:BAAALgADCgMJBQAAAA==.Daquilla:BAAALgAECgUJBgAAAA==.Dargonit:BAAALgAECgUJAQAAAA==.Darkisis:BAAALgAECgYJDwAAAA==.Darknara:BAABLgAECn8mAAIZAAkJUx98GQAzAgAZAAkJUx98GQAzAgAAAA==.Darkterror:BAAALgAECgYJCwABLgAECgYJDwALAAAAAA==.Darkzy:BAAALgAECgMJAwAAAA==.Dartol:BAAALgAECgIJAgAAAA==.Dasubertakem:BAAALgAECgIJAgAAAA==.Dawni:BAABLgAECn8YAAIMAAYJPSJNBgAiAgAMAAYJPSJNBgAiAgAAAA==.',
De='Deathies:BAAALgADCgIJAgAAAA==.Deathigh:BAAALgAECgQJBQAAAA==.Deathjeff:BAAALgAECgkJDgAAAA==.Deathsgates:BAABLgAECn8lAAIHAAgJrR9xFAA+AgAHAAgJrR9xFAA+AgABLgAFFAQJCgARAF4hAA==.Decasia:BAAALgAECgYJDQAAAA==.Deheon:BAAALgADCgQJBgAAAA==.Demoswal:BAAALgADCgEJAgAAAA==.Descendent:BAAALgADCgEJAQAAAA==.Destickament:BAAALgADCgMJAwAAAA==.Detala:BAAALgAECgIJAgAAAA==.Detective:BAAALgAECgQJBAAAAA==.Dethkeela:BAABLgAECn8lAAIZAAgJqBnPIAAFAgAZAAgJqBnPIAAFAgABLgAFFAUJCQAJAMMHAA==.Dewy:BAAALgAECgYJEAAAAA==.',
Dh='Dhfig:BAABLgAECn8jAAIXAAgJThPPJgChAQAXAAgJThPPJgChAQAAAA==.',
Di='Dimos:BAAALgAECgUJBQAAAA==.Dinoll:BAAALgAECgYJCQAAAA==.Dirtwhistle:BAAALgAECgEJBAAAAA==.',
Do='Dogo:BAAALgADCgcJCwAAAA==.',
Dr='Draconnt:BAAALgAECgMJAwAAAA==.Dragondh:BAABLgAECn8rAAIaAAgJVhcWCgDoAQAaAAgJVhcWCgDoAQAAAA==.Draksvoid:BAAALgAECgYJDQAAAA==.Dranlu:BAAALgAECgEJAQAAAA==.Dranog:BAABLgAECn8oAAMHAAgJlhZTKgC8AQAHAAgJlhZTKgC8AQAOAAIJVQXSXQBVAAAAAA==.Draxol:BAAALgADCgcJEwAAAA==.Drazsi:BAAALgAECgYJDwAAAA==.Drovaal:BAAALgADCgEJAQAAAA==.Druidbod:BAAALgAECgUJCAABLgAFFAYJGAABAFodAA==.Drutacular:BAAALgADCgEJAgAAAA==.',
Du='Durga:BAAALgAECgYJDgAAAA==.Dusk:BAAALgADCgEJAQABLgAECgEJAQALAAAAAA==.',
Dy='Dyromancer:BAAALgADCgYJEwAAAA==.',
['Dé']='Défect:BAABLgAECn8UAAIZAAYJmBHGmwBJAQAZAAYJmBHGmwBJAQAAAA==.',
['Dô']='Dôminic:BAAALgAECgEJAgAAAA==.',
Eb='Ebpindots:BAABLgAECn8ZAAMNAAgJ2BrpBACGAQANAAcJZxvpBACGAQAHAAYJ2xVFRQBZAQAAAA==.',
Eg='Eggegg:BAAALgAECgMJBgABLgAECggJJQAJADsbAA==.',
El='Eleanne:BAABLgAECn8XAAMbAAgJygsDJAAaAQAbAAcJgwwDJAAaAQABAAUJdwkqZACSAAAAAA==.Elfrida:BAAALgADCgIJBAAAAA==.Ellebasi:BAABLgAECn8vAAIVAAcJ+BJXEQAoAQAVAAcJ+BJXEQAoAQAAAA==.',
Em='Emarosa:BAAALgADCgcJBwABLgAECgcJGQAPAF0YAA==.Emorya:BAAALgAECgcJCwAAAA==.',
En='Enazen:BAAALgAECgYJDAAAAA==.Enchantz:BAAALgADCgYJBgAAAA==.Endzela:BAAALgADCgUJBQAAAA==.Enky:BAAALgADCgcJCAAAAA==.',
Er='Erlas:BAAALgADCgkJLQAAAA==.Errol:BAAALgADCgUJBQAAAA==.Erui:BAAALgAECgQJCAAAAA==.',
Ev='Evilrayne:BAABLgAECn8nAAIGAAgJUxhQLwDjAQAGAAgJUxhQLwDjAQAAAA==.Evoxus:BAAALgAECgUJCAAAAA==.',
Fa='Fatherfingur:BAAALgAECgUJDQAAAA==.Fauxpas:BAABLgAECn8UAAIBAAYJFhXZLgBnAQABAAYJFhXZLgBnAQAAAA==.Fawnzy:BAAALgAECgMJAwAAAA==.',
Fe='Fearoshimâ:BAAALgADCgUJBQAAAA==.Feladrin:BAAALgADCgYJBgAAAA==.Feldommy:BAAALgAECgUJBQAAAA==.Feloak:BAABLgAECn8pAAIcAAkJvw8rBwCBAQAcAAkJvw8rBwCBAQAAAA==.Felonie:BAAALgADCgIJAwAAAA==.Fenyxfall:BAAALgAECgQJBwAAAA==.Feredir:BAAALgAECgYJCwAAAA==.Ferzod:BAAALgADCgEJAQABLgAECggJGQAVAAcMAA==.',
Fi='Fieryfang:BAABLgAECn8lAAIDAAkJcCBSBAC8AgADAAkJcCBSBAC8AgAAAA==.Fireshader:BAAALgADCgEJAQAAAA==.Fistandilius:BAAALgAECgYJDwAAAA==.Fistman:BAABLgAECn8WAAQdAAgJviFlFQBAAgAdAAgJviFlFQBAAgAeAAEJthQ1YAA8AAAUAAIJWARWZgA5AAAAAA==.',
Fl='Flashsomhash:BAAALgAECgEJAQAAAA==.Flyleaf:BAABLgAECn8YAAIEAAgJTRJJFQCaAQAEAAgJTRJJFQCaAQAAAA==.',
Fo='Foshnu:BAABLgAECn8jAAMfAAcJsA57OAAmAQAfAAcJsA57OAAmAQAYAAUJLQfIPQC0AAAAAA==.',
Fr='Fraks:BAAALgADCgMJAwAAAA==.Frostman:BAAALgAECgIJAgABLgAECgYJBwALAAAAAA==.Frozandrov:BAAALgAECgQJEgAAAA==.',
Fu='Fujie:BAABLgAECn8aAAIaAAgJox/yCQDDAgAaAAgJox/yCQDDAgAAAA==.Fujï:BAAALgAECgYJBgAAAA==.Furryfury:BAACLgAFFH8LAAIUAAMJRw4kGAC/AAAUAAMJRw4kGAC/AAAuAAQKfyAAAxQACAkHEJglABsBABQACAkHEJglABsBAB0ABQnbCZBOANgAAAAA.Fuzzyewok:BAABLgAECn8WAAISAAkJRQ5TFQDlAQASAAkJRQ5TFQDlAQAAAA==.',
['Fë']='Fëlisha:BAAALgADCgQJBAAAAA==.',
Ga='Gaazmataaz:BAAALgAECgQJBwAAAA==.Galadir:BAAALgADCgEJAQAAAA==.Garag:BAAALgADCgUJBQAAAA==.Garlstedt:BAAALgAECgUJDQAAAA==.Gawdzirra:BAAALgADCgIJAgAAAA==.',
Ge='Genstein:BAAALgADCgIJAgAAAA==.George:BAABLgAECn8WAAIgAAYJXAVJIAD6AAAgAAYJXAVJIAD6AAAAAA==.Geostigma:BAAALgADCgEJAQABLgAECggJHAAGAF0dAA==.',
Gh='Ghulrokk:BAAALgAECgYJDAAAAA==.',
Gi='Gilidan:BAAALgAECgIJAgAAAA==.Gizmo:BAAALgAECgEJAQAAAA==.',
Gl='Glenndragon:BAAALgAECgYJDQAAAA==.Gluum:BAAALgAECgMJBAAAAA==.',
Go='Goatmeal:BAAALgADCgEJAQAAAA==.Gohibasi:BAAALgAECgYJCwAAAA==.Gormlaif:BAAALgADCgUJBQAAAA==.Gossamerfeet:BAAALgAECgYJDgAAAA==.Gotalian:BAABLgAECn8mAAITAAgJuAndUABUAQATAAgJuAndUABUAQAAAA==.',
Gr='Graceosilver:BAABLgAECn8dAAIhAAcJCQPvEADxAAAhAAcJCQPvEADxAAAAAA==.Grajademoh:BAAALgADCgcJDAAAAA==.Grajashadow:BAAALgAECgYJDAAAAA==.Gregnor:BAABLgAECn8pAAQiAAkJAxlAAgCTAgAiAAkJ8hhAAgCTAgAbAAMJPxHmNwCrAAAjAAEJTgqPKwApAAAAAA==.Gremöry:BAAALgAECgEJAQAAAA==.Grim:BAABLgAECn8jAAIZAAkJoxk/GQA0AgAZAAkJoxk/GQA0AgAAAA==.Grover:BAAALgAECgcJEAAAAA==.Grozztrak:BAAALgADCgQJBAAAAA==.Grumpybun:BAAALgAECgYJBgAAAA==.Grumpybunbun:BAABLgAECn8bAAIFAAgJFxjhJgC2AQAFAAgJFxjhJgC2AQAAAA==.',
Gu='Guldrosi:BAABLgAECn8pAAQNAAkJ5hupAACrAgANAAkJ5BupAACrAgAHAAcJ9RW4OQB/AQAOAAQJPBEQRAClAAAAAA==.',
Gy='Gyat:BAAALgAECgYJEAAAAA==.',
['Gå']='Gårrus:BAABLgAECn8gAAIJAAgJmSFdCwCGAgAJAAgJmSFdCwCGAgAAAA==.',
Ha='Haarl:BAAALgAECgQJBwAAAA==.Hagel:BAAALgAECggJCAAAAA==.Hairypotter:BAAALgADCgMJAwAAAA==.Hallie:BAABLgAECn8dAAIGAAcJAApyZgBEAQAGAAcJAApyZgBEAQAAAA==.Hargoose:BAAALgAECgMJBQAAAA==.Harlu:BAABLgAECn8jAAIYAAcJaQe5LQD/AAAYAAcJaQe5LQD/AAAAAA==.Hartbroke:BAABLgAECn8jAAMTAAcJXBwPJADzAQATAAcJXBwPJADzAQAVAAIJjw8oMgAvAAAAAA==.',
He='Helbourne:BAABLgAECn8VAAIaAAYJVCGPCgDdAQAaAAYJVCGPCgDdAQAAAA==.Hextraspicy:BAAALgADCgQJBAAAAA==.',
Hi='Hideyoshi:BAAALgADCgkJIQAAAA==.Hijjiup:BAAALgAECgEJAQAAAA==.Hildah:BAAALgAECgIJBQAAAA==.',
Ho='Holliestraza:BAABLgAECn8cAAIfAAgJKhPcLABjAQAfAAgJKhPcLABjAQAAAA==.Holyadrian:BAAALgAECgIJAgAAAA==.Holyfugde:BAAALgADCgQJBQAAAA==.Holyman:BAAALgADCgMJAwAAAA==.',
Hw='Hwanwok:BAABLgAECn8YAAMdAAYJYBsVGABlAQAdAAYJeBcVGABlAQAeAAYJRhYEHQBLAQAAAA==.',
Hy='Hyacynth:BAAALgADCgYJBQAAAA==.Hypermage:BAAALgADCgcJBwAAAA==.',
['Hâ']='Hânzö:BAAALgAECgQJCgAAAA==.',
['Hä']='Härbinger:BAAALgAECgUJCQAAAA==.',
Ic='Ic:BAAALgAECgIJAgAAAA==.',
Ig='Ignited:BAAALgADCgYJBwAAAA==.',
Il='Illumine:BAAALgADCgYJBgAAAA==.',
Im='Imadragon:BAABLgAECn8jAAIWAAgJIhNLBACzAQAWAAgJIhNLBACzAQAAAA==.Imdeadguy:BAABLgAECn8eAAIkAAgJnCNuAwCTAgAkAAgJnCNuAwCTAgAAAA==.',
In='Innalowda:BAAALgADCgcJEQABLgAECggJFgAVAKAjAA==.',
Ir='Ironhelmhtr:BAAALgAECgYJDgAAAA==.Irënicus:BAAALgADCgcJCgAAAA==.',
Is='Iseeyounow:BAAALgADCgIJAgAAAA==.Isendra:BAABLgAECn8VAAIGAAcJsgxvXABbAQAGAAcJsgxvXABbAQAAAA==.Istian:BAAALgADCgIJAgAAAA==.',
It='Itachi:BAAALgADCgcJGAAAAA==.',
Ja='Jabtak:BAAALgAECgMJAwAAAA==.Jaded:BAAALgAECgEJAgAAAA==.Janinoo:BAABLgAECn8VAAMlAAcJBQjNIwAkAQAlAAcJBQjNIwAkAQAFAAEJkAV0hwAoAAAAAA==.Jararth:BAAALgAECgEJBAAAAA==.Jazlee:BAABLgAECn8eAAIkAAcJbR45CAD4AQAkAAcJbR45CAD4AQAAAA==.',
Je='Jeggana:BAAALgAECgEJAQAAAA==.',
Ji='Jinathy:BAABLgAECn8dAAITAAgJLhItOwCVAQATAAgJLhItOwCVAQAAAA==.Jinnite:BAAALgADCgEJAQAAAA==.',
Jo='Jolyñ:BAABLgAECn8nAAIFAAkJmBDPDwDuAQAFAAkJmBDPDwDuAQABLgAECggJJwAKAFUPAA==.',
Ju='Jualygosa:BAABLgAECn8qAAIGAAgJsxpxHwAuAgAGAAgJsxpxHwAuAgAAAA==.Judgementall:BAAALgAECgcJEwAAAA==.Juomancito:BAABLgAECn8iAAIBAAgJMSTbAwAtAwABAAgJMSTbAwAtAwAAAA==.Justac:BAAALgAECgQJCAABLgAECgQJEgALAAAAAA==.Justgotbis:BAAALgAECgQJBQAAAA==.',
['Já']='Jáß:BAABLgAFFH8GAAISAAMJcBt1FgD1AAASAAMJcBt1FgD1AAAAAA==.',
['Jä']='Jäb:BAAALgADCgcJBwAAAA==.',
Ka='Kaddrix:BAAALgAECgcJDwAAAA==.Kaldonor:BAABLgAECn8tAAIIAAgJsxahAwDOAQAIAAgJsxahAwDOAQAAAA==.Kalenia:BAABLgAECn8sAAIfAAgJTiNtAwAWAwAfAAgJTiNtAwAWAwAAAA==.Kalvayre:BAABLgAECn8jAAIZAAgJOhTMNgCeAQAZAAgJOhTMNgCeAQAAAA==.Kanzoorb:BAAALgAECgUJBQAAAA==.Karpana:BAEBLgAECn8nAAMVAAcJZhofCADNAQAVAAcJZhofCADNAQATAAUJWQ7hhQDhAAAAAA==.Kashir:BAABLgAECn8dAAQWAAcJwyH4AQBNAgAWAAcJwyH4AQBNAgAEAAQJmBobPgCjAAAMAAEJRAwtSQAxAAAAAA==.Katamoonfang:BAAALgAECgYJBgAAAA==.Katastrophe:BAAALgAECggJEgAAAA==.Katsumi:BAAALgAECgQJBwAAAA==.Kaythewitch:BAAALgAECgUJBQAAAA==.Kazimirah:BAAALgAECgEJAQAAAA==.Kazrael:BAAALgAECgMJBQAAAA==.',
Ke='Keekat:BAAALgADCgkJIgAAAA==.Keloha:BAAALgAECgUJBQAAAA==.Kerprage:BAAALgAECgQJCgAAAA==.Kerpredem:BAAALgADCgcJFwAAAA==.Kerpspells:BAAALgADCgcJEgAAAA==.',
Kh='Khariaa:BAAALgADCgcJBwAAAA==.Khoravi:BAABLgAECn8aAAIEAAkJbRa4CwAQAgAEAAkJbRa4CwAQAgAAAA==.',
Ki='Kikora:BAAALgADCgUJBQAAAA==.Kitaska:BAAALgADCgQJAwABLgAECgcJGwASAFoQAA==.Kittykitty:BAABLgAECn8lAAMfAAkJ+heMHAA1AgAfAAkJ+heMHAA1AgAhAAQJKxMDEQDwAAAAAA==.',
Ko='Kolzane:BAACLgAFFH8RAAIJAAYJjCIbAAANAgAJAAYJjCIbAAANAgAuAAQKfxkAAwkACQl4JHUGACYDAAkACQl4JHUGACYDACYABAnYEC5gAMAAAAAA.Kongfu:BAAALgAECgYJEAAAAA==.Korravah:BAAALgAECgQJBwAAAA==.Koyuki:BAAALgAECgMJBgAAAA==.',
Kr='Kramps:BAAALgAECgQJBgAAAA==.Krandel:BAAALgAECgMJAwAAAA==.Kronan:BAAALgADCgIJAgAAAA==.',
Ku='Kuulas:BAABLgAECn8aAAIJAAgJdxuJGQAGAgAJAAgJdxuJGQAGAgAAAA==.',
Ky='Kyth:BAABLgAECn8qAAIVAAgJ+BGqDQBeAQAVAAgJ+BGqDQBeAQAAAA==.Kythlock:BAAALgADCgkJEwABLgAECggJKgAVAPgRAA==.Kythrax:BAAALgADCgkJCQABLgAECggJKgAVAPgRAA==.Kythtok:BAABLgAECn8aAAIJAAgJEwq4NwBuAQAJAAgJEwq4NwBuAQABLgAECggJKgAVAPgRAA==.',
['Kê']='Kêgstand:BAAALgAECgMJBwAAAA==.',
['Kø']='Køda:BAABLgAECn8mAAMBAAgJ7SOcBQD9AgABAAgJ7SOcBQD9AgAbAAYJ0QzJKgDvAAAAAA==.',
La='Ladyhawk:BAAALgADCgYJCQAAAA==.Lazerbird:BAAALgAECgEJAQAAAA==.',
Le='Leggy:BAAALgAECgIJAgAAAA==.Lela:BAAALgADCgEJAQAAAA==.',
Li='Life:BAAALgADCgYJCgAAAA==.Lifebloomer:BAAALgAECgQJAwABLgAFFAYJHQAPAAEjAA==.Lightnup:BAAALgAECgkJDAAAAA==.Liralyn:BAAALgADCgcJDgAAAA==.Lisanndria:BAAALgADCgUJBQAAAA==.Litharaldra:BAAALgADCgYJBgAAAA==.Littlehell:BAACLgAFFH8HAAIfAAMJrhN+DgD2AAAfAAMJrhN+DgD2AAAuAAQKfxcAAh8ACAkhG74VAGcCAB8ACAkhG74VAGcCAAAA.',
Lo='Lokaroki:BAAALgAECgQJBwAAAA==.Lothbrokk:BAAALgAECgUJBgAAAA==.Lothrik:BAAALgADCgIJAgAAAA==.',
Lu='Lucaafer:BAACLgAFFH8JAAIGAAMJxw2hSAD4AAAGAAMJxw2hSAD4AAAuAAQKfyMAAgYACQn9HSkzAKYCAAYACQn9HSkzAKYCAAAA.Luda:BAAALgAECggJEwAAAA==.',
Ly='Lyssandria:BAABLgAECn8tAAIGAAgJNwosWgBgAQAGAAgJNwosWgBgAQAAAA==.Lyzoldas:BAABLgAECn8eAAITAAcJvRd4OQCaAQATAAcJvRd4OQCaAQAAAA==.',
['Lí']='Lília:BAAALgAECgEJAgAAAA==.',
['Lö']='Löwryder:BAABLgAECn8ZAAIYAAcJrg2BJAAyAQAYAAcJrg2BJAAyAQAAAA==.',
Ma='Maddera:BAAALgAECgUJCAAAAA==.Madmurdock:BAAALgAECgcJEwAAAA==.Madness:BAAALgAECgYJCgAAAA==.Maemura:BAAALgAECgUJCQAAAA==.Magîkarp:BAAALgADCgYJBwAAAA==.Mahll:BAAALgADCgUJBQAAAA==.Maiki:BAAALgAECgEJAgAAAA==.Malach:BAAALgAECgcJBAAAAA==.Malchromatus:BAABLgAECn8aAAMMAAgJhRXHBgARAgAMAAgJhRXHBgARAgAWAAQJKwdtLQCvAAAAAA==.Marcosio:BAAALgAECgIJAwAAAA==.Marsala:BAAALgAECgYJDwAAAA==.',
Mb='Mbop:BAAALgAECgQJBAAAAA==.',
Mc='Mcchud:BAAALgAECgEJAQAAAA==.',
Me='Meandragon:BAAALgADCgcJBwAAAA==.Meatyfajita:BAABLgAECn8bAAISAAgJpCYdAQBtAwASAAgJpCYdAQBtAwAAAA==.Mechabrew:BAABLgAECn8VAAIeAAYJ2w7VKgD2AAAeAAYJ2w7VKgD2AAABLgAECggJGQAcAOAdAA==.Medousa:BAAALgAECgMJAwAAAA==.Megaera:BAAALgAECgYJCwAAAA==.Meiko:BAAALgAECgEJAQABLgAECgcJGQAPAF0YAA==.Meindblast:BAAALgADCgEJAQABLgAECgYJFQAWAJgVAA==.Meladie:BAAALgAECgEJAgAAAA==.Meladrus:BAAALgADCgEJAQAAAA==.Mellene:BAAALgADCgkJFgAAAA==.Memedecay:BAABLgAECn8tAAMZAAgJ9SCoDgCMAgAZAAgJ9SCoDgCMAgAPAAEJnRkfQwA9AAAAAA==.Mememalefic:BAAALgAECgcJDAABLgAECggJLQAZAPUgAA==.Mericck:BAAALgADCgMJAwAAAA==.Merlinthos:BAAALgAECgQJBgABLgAECggJJwARAEsUAA==.Metaljack:BAABLgAECn8pAAIGAAkJDyWXAgBbAwAGAAkJDyWXAgBbAwAAAA==.',
Mi='Miasma:BAAALgAECgYJDgABLgAECgMJDgALAAAAAA==.Mikeyboi:BAAALgADCgEJAQAAAA==.Milanesa:BAABLgAECn8aAAIkAAkJYBMqEgDlAQAkAAkJYBMqEgDlAQAAAA==.Mingyue:BAAALgAECgYJBgABLgAECggJMwAEAIsWAA==.Mishaweha:BAAALgAECggJDAAAAA==.Mithrandir:BAAALgAECgYJEgAAAA==.Mitos:BAABLgAECn8uAAITAAgJJBL8NACpAQATAAgJJBL8NACpAQAAAA==.Miyasabi:BAAALgADCgYJBgAAAA==.Mizzet:BAAALgAECgEJAQAAAA==.',
Mo='Modar:BAABLgAECn8YAAIfAAgJRxzUDgBMAgAfAAgJRxzUDgBMAgAAAA==.Mojopin:BAAALgAECgMJAwAAAA==.Monkas:BAAALgADCgcJCQAAAA==.Moonpaw:BAAALgAECgEJAQAAAA==.Moonrid:BAAALgADCgkJHwAAAA==.Moonshayd:BAAALgAECgcJEgAAAA==.Moreann:BAAALgADCgkJEAAAAA==.Morkepo:BAAALgADCgEJAQAAAA==.Morphëus:BAABLgAECn8WAAIGAAcJ2g4GVABvAQAGAAcJ2g4GVABvAQAAAA==.',
Mu='Muggy:BAAALgADCgIJAgABLgAFFAQJDQAZAAYkAA==.Muha:BAAALgAECgUJBQAAAA==.Murielle:BAAALgADCgUJBQAAAA==.Mushi:BAAALgADCgkJEgAAAA==.Mustardplug:BAAALgADCgEJAQAAAA==.Muzan:BAAALgAECgQJBAAAAA==.Muzzin:BAAALgADCgEJAQAAAA==.',
My='Mystiquebtb:BAAALgAECgcJBQAAAA==.',
['Må']='Måddløck:BAAALgAECgQJBwAAAA==.',
Ne='Needslotion:BAABLgAECn8VAAMWAAYJmBWcBgBbAQAWAAYJJxWcBgBbAQAEAAQJVBJYQADlAAAAAA==.Neiidra:BAAALgAECgYJDgAAAA==.Nepheleah:BAACLgAFFH8HAAITAAQJuwvrIgAhAQATAAQJuwvrIgAhAQAuAAQKfxwAAhMACAmSISgQAA4DABMACAmSISgQAA4DAAAA.Nesmoth:BAABLgAECn8kAAIPAAcJaSQ0BgDVAgAPAAcJaSQ0BgDVAgAAAA==.Ness:BAAALgAECgQJBwAAAA==.',
Ni='Niiborracho:BAABLgAECn8pAAMdAAgJFxBvGABhAQAdAAgJFxBvGABhAQAUAAgJNwzXHQBZAQAAAA==.Niiko:BAAALgAECgQJCwAAAA==.Niisera:BAAALgADCgQJBwAAAA==.',
No='Norntrox:BAABLgAECn8jAAMXAAcJFhsPIQDCAQAXAAcJFhsPIQDCAQAcAAEJAACwKQA9AAAAAA==.Nosåj:BAAALgADCgQJBQAAAA==.Nothannah:BAAALgAECgQJBAAAAA==.',
Ns='Nsshaman:BAAALgADCgMJAwAAAA==.',
Ny='Nylaria:BAAALgADCgUJBQAAAA==.Nyxari:BAAALgAECgYJDwAAAA==.',
Ob='Obscuría:BAAALgADCgYJCgAAAA==.',
Od='Odrik:BAAALgADCgQJCAAAAA==.',
Ol='Oleana:BAAALgAECgQJBAAAAA==.Oleia:BAAALgAECgYJCAAAAA==.',
On='Onatha:BAAALgADCgkJGgAAAA==.Onaw:BAAALgAECgQJDgAAAA==.',
Op='Ops:BAEALgAECgYJEgAAAA==.',
Or='Orctism:BAAALgADCgIJAgAAAA==.',
Ow='Owlsonatotem:BAABLgAECn8hAAIfAAkJvhZwHgC/AQAfAAkJvhZwHgC/AQAAAA==.',
Ox='Oxymage:BAAALgAECgEJAgAAAA==.',
Pa='Pakno:BAAALgAECggJEgAAAA==.Paletia:BAAALgAECgYJBgAAAA==.Pamely:BAABLgAECn8UAAITAAcJBRfmTwBWAQATAAcJBRfmTwBWAQAAAA==.Pankler:BAAALgADCgkJCwAAAA==.',
Pe='Petethelock:BAAALgAECgYJDAAAAA==.Petethemage:BAAALgAECgEJAgAAAA==.',
Ph='Pharmit:BAABLgAECn8iAAQNAAkJ5iQhAABGAwANAAkJQyQhAABGAwAHAAYJ1iLPPQAVAgAOAAIJ1B5rPADDAAAAAA==.Phayte:BAAALgADCgkJEAAAAA==.Photon:BAAALgADCgYJBQAAAA==.Phrock:BAAALgADCgEJAgAAAA==.',
Pl='Pletua:BAABLgAECn8WAAIgAAcJ2B3zFQBfAgAgAAcJ2B3zFQBfAgAAAA==.',
Po='Porazdir:BAAALgAECgUJBgAAAA==.Porcelayna:BAAALgAECgIJAgABLgAECgcJIwAfALAOAA==.',
Pr='Primoris:BAAALgADCgUJBQAAAA==.',
Ps='Psion:BAAALgADCgYJBgAAAA==.',
Pu='Puds:BAAALgADCgMJAwAAAA==.',
['På']='Påimon:BAAALgADCgIJAgAAAA==.',
Qu='Quetzalcoatl:BAAALgAECggJCAAAAA==.Quintin:BAAALgAECgYJBwABLgAFFAQJCAACAH4TAA==.',
Ra='Racavis:BAAALgADCgcJCAAAAA==.Raenisa:BAEALgADCgQJBwABLgAECggJIQAFAKMYAA==.Ragp:BAAALgAECgMJAwAAAA==.Rainydevil:BAAALgADCgcJDgAAAA==.Rainydevils:BAAALgADCgIJAgAAAA==.Rainymdevil:BAAALgADCgUJBQAAAA==.Rainyxdvl:BAAALgAECgEJAQAAAA==.Ramasey:BAAALgAECgYJEAAAAA==.Rasriann:BAAALgAECgQJBAAAAA==.Rawrlordz:BAAALgAECgYJDAAAAA==.',
Re='Reaces:BAAALgADCgEJAQAAAA==.Real:BAABLgAECn8eAAIGAAgJTR3/IgAbAgAGAAgJTR3/IgAbAgABLgAECgQJBQALAAAAAA==.Reda:BAAALgAECgMJBAAAAA==.Reeality:BAAALgAECgQJBQAAAA==.Reelio:BAAALgAECgQJCAAAAA==.Reikio:BAAALgAECgQJBAAAAA==.Rennala:BAAALgAECgcJCAAAAA==.Repeal:BAAALgAECgQJBAAAAA==.Reptar:BAAALgADCgYJBgABLgAFFAYJGwAeAEoWAA==.Retbet:BAAALgAECgYJDwAAAA==.Revoke:BAABLgAECn8iAAITAAgJ9wwhQgB/AQATAAgJ9wwhQgB/AQAAAA==.Reyanne:BAEBLgAECn8hAAIFAAgJoxixCQBOAgAFAAgJoxixCQBOAgAAAA==.',
Ro='Rockfish:BAAALgAECgQJBQAAAA==.Roofio:BAAALgADCgEJAQABLgAECggJFgAVAKAjAA==.',
Ru='Rubiroo:BAAALgADCgEJAQAAAA==.Runebellwolf:BAAALgADCgcJCgAAAA==.Ruroni:BAAALgADCgUJCQAAAA==.',
Ry='Ryniel:BAABLgAECn8bAAIJAAcJUhbgJwCzAQAJAAcJUhbgJwCzAQAAAA==.Rynitty:BAAALgADCgUJBQABLgAECgcJDQALAAAAAA==.Rynthia:BAAALgADCgkJCQAAAA==.',
['Ré']='Réira:BAAALgADCgkJEQABLgAECggJMwAEAIsWAA==.',
['Rï']='Rïptide:BAAALgAECgQJBwAAAA==.',
Sa='Sabrinalee:BAAALgADCgcJBwAAAA==.Sacremierde:BAAALgAECgQJBwAAAA==.Sagah:BAAALgAECgYJEQAAAA==.Saintdeamon:BAABLgAECn8fAAMBAAgJ7xi7QQCaAQABAAcJohe7QQCaAQAbAAcJSBDrHABNAQAAAA==.Sanasta:BAABLgAECn8cAAMHAAcJwxF3PQBzAQAHAAcJdhB3PQBzAQAOAAIJCRkOIwBJAAAAAA==.Sandspur:BAAALgAECgEJAQAAAA==.Sanielin:BAABLgAECn8gAAIeAAcJgyDtDAD1AQAeAAcJgyDtDAD1AQABLgAFFAEJAQALAAAAAA==.Sanielindk:BAAALgAFFAEJAQAAAA==.Saphìr:BAAALgAECgQJCgAAAA==.Sarahnox:BAAALgAECgEJAQAAAA==.Saramoon:BAABLgAECn8dAAMgAAYJyAjSHgAGAQAgAAYJyAjSHgAGAQARAAQJhgLVFQCdAAAAAA==.Sarda:BAEALgAECgYJDQAAAA==.Sargent:BAAALgAECgUJDAAAAA==.Saryaa:BAAALgAECgcJCwAAAA==.Sashchi:BAABLgAECn8VAAIdAAgJZhEbIAAkAQAdAAgJZhEbIAAkAQAAAA==.Satheronys:BAAALgAECgEJAQABLgAECgMJAwALAAAAAA==.',
Sc='Schade:BAAALgAECgQJCQAAAA==.Schrödinger:BAAALgAECgMJAwAAAA==.',
Se='Searen:BAAALgAECgIJAwAAAA==.Sehmet:BAAALgAECgMJBQAAAA==.Seiso:BAABLgAFFH8FAAICAAUJnAmhCQAMAQACAAUJnAmhCQAMAQAAAA==.Seliria:BAABLgAECn8pAAITAAkJ+Qm5OACdAQATAAkJ+Qm5OACdAQAAAA==.Sephaman:BAAALgAECgEJAQAAAA==.Seprogue:BAAALgADCgcJCgAAAA==.',
Sh='Shadyn:BAAALgAECgEJAQAAAA==.Shadówz:BAAALgADCgEJAQAAAA==.Shandrayn:BAAALgADCgMJAwAAAA==.Sheepstealer:BAAALgADCgQJAwAAAA==.Shiftace:BAAALgAECgIJAgAAAA==.Shiryo:BAAALgAECgMJCgAAAA==.Shockwater:BAAALgAECgUJBwAAAA==.Shotfoot:BAAALgAECgMJAwAAAA==.Shwang:BAABLgAECn8XAAIJAAYJTxU2QgBHAQAJAAYJTxU2QgBHAQAAAA==.',
Si='Siclock:BAAALgADCgUJBQAAAA==.Sikkerp:BAAALgADCgMJBAAAAA==.Silentio:BAABLgAECn8nAAIRAAgJSxTaBAC7AQARAAgJSxTaBAC7AQAAAA==.Silihunt:BAAALgADCgMJAwAAAA==.Siliçå:BAAALgADCgYJCQAAAA==.Sinamun:BAABLgAECn8bAAISAAcJWhC7QwBpAQASAAcJWhC7QwBpAQAAAA==.Sinandtonic:BAAALgADCgQJBAAAAA==.Sinofwrath:BAABLgAECn8fAAIXAAgJ5yLtBgC5AgAXAAgJ5yLtBgC5AgAAAA==.Sinsidious:BAABLgAECn8VAAIZAAYJSw2kYwAdAQAZAAYJSw2kYwAdAQAAAA==.Siwin:BAACLgAFFH8YAAIBAAYJWh3DAwATAgABAAYJWh3DAwATAgAuAAQKfx4AAwEACAm3JMsIAAIDAAEACAm3JMsIAAIDABsAAwlAF7g/AIMAAAAA.',
Sk='Skarlett:BAAALgAECgQJBQAAAA==.Skiller:BAAALgADCgYJDAAAAA==.Skinobi:BAAALgAECgQJBQAAAA==.Skysqueezer:BAAALgAECgYJCwAAAA==.',
Sl='Slapchóp:BAABLgAECn8UAAIYAAgJvRq+EADbAQAYAAgJvRq+EADbAQAAAA==.',
Sm='Smoko:BAABLgAECn8ZAAIKAAgJhRz0DQDoAQAKAAgJhRz0DQDoAQAAAA==.',
Sn='Snorlax:BAAALgAECgIJAgABLgAECgYJEgALAAAAAA==.Snowxstorm:BAABLgAECn8oAAIPAAkJOiHcAQDvAgAPAAkJOiHcAQDvAgAAAA==.',
So='Sobieski:BAAALgAECgkJCQAAAA==.Solae:BAAALgADCgkJDwAAAA==.Solrond:BAAALgAECgUJCQAAAA==.Somemageguy:BAAALgAECgEJAQAAAA==.Sosimmage:BAACLgAFFH8FAAIGAAUJGxFnLQBOAQAGAAUJGxFnLQBOAQAuAAQKfxcAAgYACAnaHPwdADYCAAYACAnaHPwdADYCAAEuAAUUBAkOAAYAWRsA.Souldecay:BAABLgAECn8oAAIZAAkJ3g68JQDpAQAZAAkJ3g68JQDpAQAAAA==.Soultender:BAAALgADCgIJAgAAAA==.',
Sp='Spekktrum:BAAALgAECgEJAQAAAA==.',
Sq='Squidacles:BAAALgADCgEJAQAAAA==.Squirrly:BAAALgAECgEJAQAAAA==.',
St='Stainedone:BAAALgAECgYJDwAAAA==.Staqua:BAAALgAECgMJBQAAAA==.Stateomatter:BAAALgAECgcJDgAAAA==.Stevenflowe:BAAALgADCgcJCAAAAA==.Stoneslacher:BAAALgADCgIJBAAAAA==.Streamesance:BAAALgAECgYJCAAAAA==.',
Su='Suanni:BAABLgAECn8zAAQEAAgJixYtDgDsAQAEAAgJixYtDgDsAQAWAAIJVQjWEwBTAAAMAAEJoQD6TwAPAAAAAA==.Summdari:BAABLgAECn8jAAIcAAgJtRtLBADtAQAcAAgJtRtLBADtAQAAAA==.Summrot:BAABLgAECn8VAAMOAAcJTxTPMgDsAAAHAAQJDBIiaQD6AAAOAAUJCBXPMgDsAAAAAA==.Sunfrostt:BAAALgAECgQJCgAAAA==.Supplock:BAAALgAECgYJDwAAAA==.Suromeme:BAAALgAECgQJBAABLgAECgkJKAAjAKceAA==.',
Sw='Swizzler:BAAALgAECgQJBgAAAA==.',
Sy='Sylvalesta:BAAALgAECgMJBQAAAA==.',
Ta='Taedro:BAAALgADCgkJFgAAAA==.Taichung:BAAALgAECgUJAQAAAA==.Talyon:BAAALgAECgYJEAAAAA==.Tayge:BAAALgADCgEJAQAAAA==.',
Td='Tdogx:BAAALgADCgYJCgAAAA==.',
Te='Teafrog:BAAALgADCgcJBwAAAA==.Tekeeladin:BAAALgADCgkJCQAAAA==.Tekeelà:BAAALgAECgYJEwABLgAFFAUJCQAJAMMHAA==.Tenebris:BAABLgAECn8XAAITAAYJjxiagwBzAQATAAYJjxiagwBzAQAAAA==.Terrorbyte:BAAALgADCgYJBgAAAA==.Terrorhungry:BAAALgAECgQJBwAAAA==.',
Th='Thalstrasza:BAABLgAECn8VAAIHAAUJ8BCbZgAAAQAHAAUJ8BCbZgAAAQAAAA==.Thalör:BAABLgAECn8dAAIbAAgJORfAHAAbAgAbAAgJORfAHAAbAgAAAA==.The:BAABLgAECn8dAAIIAAcJbx3LAgACAgAIAAcJbx3LAgACAgAAAA==.Thedevilsown:BAAALgADCgYJDgAAAA==.Thedrizzle:BAABLgAECn8cAAIGAAgJXR0sIgAgAgAGAAgJXR0sIgAgAgAAAA==.Thinkwizzle:BAAALgADCgYJBwAAAA==.Thunderthïgh:BAAALgAECgIJAwAAAA==.Thundrfury:BAAALgAECgQJBwAAAA==.',
Ti='Tibalt:BAAALgAFFAEJAQAAAA==.Tibbles:BAAALgAECgIJAwAAAA==.Tigerlillie:BAAALgADCgIJAgAAAA==.Tipsynips:BAAALgADCgQJBAAAAA==.',
Tk='Tkla:BAAALgADCgIJAgAAAA==.',
Tl='Tlanimass:BAABLgAECn8gAAIkAAcJKxHDEgA6AQAkAAcJKxHDEgA6AQAAAA==.',
To='Tommytubstub:BAAALgAECgQJCAAAAA==.Tomstrasza:BAAALgAECgQJBgAAAA==.Tormen:BAABLgAECn8lAAIlAAgJdhIFEwCuAQAlAAgJdhIFEwCuAQAAAA==.Totemforge:BAABLgAECn8WAAMfAAYJtiUqDABuAgAfAAYJtiUqDABuAgAYAAYJkRqqNgB5AQAAAA==.',
Tr='Trapdaddy:BAAALgADCgYJBgAAAA==.Traq:BAAALgADCgQJBAAAAA==.Treeko:BAAALgAECgYJDAABLgAFFAQJEAAHADkOAA==.Treston:BAAALgAECgMJBQAAAA==.Treyna:BAAALgADCgQJAgAAAA==.',
Ts='Tsyubaki:BAAALgAECggJDwAAAA==.',
Tw='Twistdmister:BAAALgADCgUJBAAAAA==.',
Ty='Tydes:BAAALgAECgUJCQAAAA==.Tylenya:BAAALgADCgUJBQAAAA==.Tyrian:BAAALgAECgIJAQABLgAECgMJDgALAAAAAA==.',
Un='Undeaddude:BAAALgAECgEJAQAAAA==.Unholybrotha:BAABLgAECn8ZAAIPAAcJXRjjDwB0AQAPAAcJXRjjDwB0AQAAAA==.Unslayable:BAAALgAECgYJDAAAAA==.Unwell:BAABLgAECn8aAAQYAAcJzxFxQgA/AQAYAAcJpxBxQgA/AQAfAAQJgBNjRgDoAAAhAAQJahEJHwDgAAAAAA==.',
Ur='Urotherdaddy:BAAALgAECgMJAwABLgAECgYJEQALAAAAAA==.',
Uz='Uzzy:BAAALgAECgQJCAAAAA==.',
Va='Vaevictis:BAAALgAECgQJBwAAAA==.Valandir:BAAALgADCgIJAgAAAA==.Valenith:BAABLgAECn8ZAAIKAAcJqhh/EQCYAQAKAAcJqhh/EQCYAQAAAA==.Valtora:BAAALgAECgUJCgAAAA==.Vartic:BAABLgAECn8UAAIMAAYJ9g8hEAA8AQAMAAYJ9g8hEAA8AQAAAA==.Vassago:BAAALgAECgUJCAAAAA==.',
Ve='Veliry:BAAALgADCgEJAQAAAA==.Vellarieline:BAABLgAECn8fAAIXAAcJlx0cMQA2AgAXAAcJlx0cMQA2AgAAAA==.Velyssara:BAAALgAECgQJCAAAAA==.Ventor:BAABLgAECn8WAAMbAAcJ5iGgGABDAgAbAAcJ5iGgGABDAgAjAAEJAABgNAAAAAABLgAECgcJFAAeADsjAA==.Verbera:BAABLgAECn8bAAIBAAgJByI/BQAGAwABAAgJByI/BQAGAwAAAA==.',
Vi='Viduus:BAAALgAECgQJBgAAAA==.Vimah:BAAALgAECgYJCQAAAA==.Virdeserti:BAABLgAECn8qAAIFAAkJjCA4AQBeAwAFAAkJjCA4AQBeAwAAAA==.Visage:BAAALgADCgkJCQAAAA==.Vixolot:BAAALgAECgIJAgAAAA==.',
Vl='Vlartank:BAAALgAECgkJBgAAAA==.',
Vm='Vmaoh:BAAALgADCggJCwAAAA==.',
Vo='Voidwithin:BAAALgAECggJDgAAAA==.',
Vu='Vulpies:BAAALgADCgYJBgAAAA==.',
Vy='Vyketh:BAAALgAECgIJAgABLgAECgYJBwALAAAAAA==.',
Wa='Wandiferous:BAAALgAECgYJDAAAAA==.',
We='Weezak:BAAALgAECgEJAQAAAA==.',
Wi='Wickedsmaht:BAACLgAFFH8QAAIHAAQJOQ7uKwAXAQAHAAQJOQ7uKwAXAQAuAAQKfyIABA4ACQltFlgWAJcBAA4ABwlYElgWAJcBAAcABwksFdBuAIMBAA0AAQnOGYUtAEMAAAAA.Widowghast:BAAALgADCgQJBAAAAA==.Willowísp:BAABLgAECn8mAAIeAAgJxBBBGQBsAQAeAAgJxBBBGQBsAQAAAA==.Winsfer:BAAALgAECgYJDgAAAA==.',
Wn='Wnchester:BAAALgADCgIJAgAAAA==.',
Wo='Woggers:BAAALgAECgYJCQAAAA==.',
Wr='Wrathion:BAABLgAECn8VAAMWAAcJzBouAwDzAQAWAAcJzBouAwDzAQAEAAIJkAxnWABdAAAAAA==.',
Wu='Wulfenstein:BAAALgADCgUJBQAAAA==.',
Wy='Wyvernman:BAAALgAECgYJBwAAAA==.Wywy:BAAALgADCgYJBgAAAA==.',
['Wí']='Wíppy:BAAALgAECgQJBQAAAA==.',
Xa='Xalthea:BAABLgAECn8iAAQXAAgJvBOIOgBMAQAXAAgJgROIOgBMAQAcAAUJng8bEAC+AAAaAAEJ+BHVbgA2AAAAAA==.Xanda:BAACLgAFFH8KAAMRAAQJXiEsAQCTAQARAAQJXiEsAQCTAQAgAAEJxwHnGwBMAAAuAAQKfyIAAhEACAmQH8oBAPkCABEACAmQH8oBAPkCAAAA.',
Xe='Xenalah:BAAALgAECgIJAgAAAA==.',
Xi='Xikai:BAAALgADCgIJAgABLgAECgYJEgALAAAAAA==.',
Xo='Xobos:BAAALgAECgQJBQAAAA==.',
Xp='Xpddevour:BAABLgAECn8uAAIXAAkJgRNLGgDrAQAXAAkJgRNLGgDrAQAAAA==.',
Xs='Xscapenature:BAAALgAECgcJEQAAAA==.',
Xt='Xtena:BAAALgADCgkJCwAAAA==.Xtendron:BAACLgAFFH8HAAMTAAMJBAntNADjAAATAAMJBAntNADjAAASAAIJrgMAGQB6AAAuAAQKfycAAxMACAn/HsIaAMkCABMACAn/HsIaAMkCABIABgniB9NaABEBAAAA.',
Xu='Xuxo:BAAALgAECgEJAQAAAA==.',
Ya='Yaraxiu:BAAALgAECgcJCwAAAA==.',
Ye='Yegarmiester:BAAALgAECgcJEwAAAA==.',
Yo='Yodidyoufart:BAACLgAFFH8FAAIJAAMJ/xiqIwAHAQAJAAMJ/xiqIwAHAQAuAAQKfy8AAwkACQkDHx8LAIkCAAkACQlRHh8LAIkCACYACAmRFsEmAPMBAAAA.',
Za='Zaco:BAABLgAECn8lAAIDAAcJwxwvDwD/AQADAAcJwxwvDwD/AQAAAA==.Zakonn:BAAALgAECgQJBAAAAA==.Zarikas:BAABLgAECn8UAAIXAAYJ/RXpQQAzAQAXAAYJ/RXpQQAzAQAAAA==.Zatapatate:BAABLgAECn8sAAMXAAgJIBuNGgDqAQAXAAgJHRuNGgDqAQAcAAYJXhIwCwAaAQAAAA==.',
Ze='Zekken:BAAALgADCgUJBwABLgADCgYJCQALAAAAAA==.Zerality:BAABLgAECn8ZAAITAAgJWhqwIQAAAgATAAgJWhqwIQAAAgAAAA==.',
Zh='Zhachy:BAACLgAFFH8LAAMWAAMJ4xoZAwAKAQAWAAMJQxcZAwAKAQAEAAMJNRrJHgD0AAAuAAQKfywABAQACAkkIxUPAIUCAAQABwlEIRUPAIUCABYABgndIywKADwCAAwAAQmHFA4nADwAAAAA.',
Zi='Ziggie:BAABLgAECn8uAAIXAAgJ+SXNAwD8AgAXAAgJ+SXNAwD8AgAAAA==.Zinovia:BAABLgAECn8VAAQdAAgJEyC6EQBqAgAdAAgJxB26EQBqAgAeAAYJoRcVMQCQAQAUAAEJeBkLYwBEAAAAAA==.Ziwei:BAAALgAECgMJBAABLgAECggJMwAEAIsWAA==.',
Zo='Zombieboy:BAAALgAECgcJBgAAAA==.Zookee:BAABLgAECn8pAAIUAAkJRRrzBQCqAgAUAAkJRRrzBQCqAgAAAA==.Zopilote:BAAALgAECgEJAQAAAA==.',
['Ön']='Önlish:BAAALgAECgEJAQABLgAECgcJDAALAAAAAA==.Önlîsh:BAAALgADCgMJAwABLgAECgcJDAALAAAAAA==.',
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

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

local lookup = {'Druid-Restoration','Warrior-Arms','Unknown-Unknown','Hunter-Survival','Hunter-BeastMastery','Evoker-Preservation','Warlock-Affliction','Warlock-Demonology','DeathKnight-Blood','Rogue-Assassination','Paladin-Holy','Paladin-Retribution','Monk-Mistweaver','Warlock-Destruction','Evoker-Augmentation','Evoker-Devastation','Shaman-Elemental','DeathKnight-Unholy','DemonHunter-Devourer','DemonHunter-Havoc','Paladin-Protection','Mage-Frost','DemonHunter-Vengeance','Warrior-Fury','Shaman-Restoration','Monk-Windwalker','Druid-Feral','Druid-Guardian','Warrior-Protection','Priest-Holy','DeathKnight-Frost','Shaman-Enhancement','Hunter-Marksmanship','Druid-Balance','Rogue-Subtlety','Monk-Brewmaster','Priest-Shadow',}
local provider = {region='US',realm='Ysera',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Ababear:BAABLgAECn8UAAIBAAgJnB2eDQDOAgABAAgJnB2eDQDOAgAAAA==.Abardi:BAAALgADCgUJBgAAAA==.',
Ad='Adeki:BAAALgADCgEJAQAAAA==.',
Ae='Aedaria:BAAALgADCgMJAwAAAA==.Aegis:BAAALgAECgEJAQAAAA==.Aeira:BAAALgADCgYJCQAAAA==.Aelora:BAAALgADCgMJAwAAAA==.Aerenna:BAAALgADCgUJBQAAAA==.',
Ag='Agakk:BAABLgAECn8fAAICAAgJQiBSAgAEAwACAAgJQiBSAgAEAwAAAA==.Agilities:BAAALgAECgQJBAAAAA==.',
Al='Alarrius:BAAALgAECgYJEgAAAA==.Alescia:BAEALgADCgYJBgABLgAECgYJEgADAAAAAA==.Allimental:BAAALgADCgEJAQAAAA==.Allionys:BAAALgAECgUJCQAAAA==.Alorelia:BAAALgADCgUJBQAAAA==.Aloris:BAAALgAECgYJDwAAAA==.',
Am='Amanises:BAAALgAECgYJDQAAAA==.Amilara:BAAALgAECgMJBAAAAA==.',
An='Ananaya:BAAALgAECgEJAQABLgAECgYJDgADAAAAAA==.Andinestiri:BAAALgAECgYJDgAAAA==.Andolastrasz:BAAALgADCgEJAQAAAA==.Andy:BAAALgAECgEJAgAAAA==.Aneethea:BAAALgADCgYJBgAAAA==.Antaric:BAAALgAECgMJAwAAAA==.Anyalem:BAAALgAECgEJAQAAAA==.',
Ao='Ao:BAAALgAECgUJBQAAAA==.',
Ap='Apotic:BAAALgAECgcJCgAAAA==.',
Aq='Aquamaree:BAAALgADCgYJBwAAAA==.Aquamyth:BAAALgADCgMJAwAAAA==.Aquilla:BAACLgAFFH8GAAMEAAQJxAJTBQCOAAAEAAIJHgJTBQCOAAAFAAIJEgTnGABHAAAuAAQKfxgAAwQACAmhFlQMAAgCAAQACAnlE1QMAAgCAAUABgmBG81hAEIBAAAA.',
Ar='Archenea:BAAALgAECgMJAwAAAA==.Archenore:BAAALgAECgcJEQAAAA==.Arkify:BAAALgADCgYJBgAAAA==.Armadyl:BAAALgAECgEJAQABLgAECgQJBwADAAAAAA==.Around:BAAALgADCgYJBgAAAA==.',
As='Ashw:BAAALgAECgYJEQAAAA==.Asukka:BAAALgAECgYJCgAAAA==.Asëya:BAAALgAECgMJBQAAAA==.',
At='Atomique:BAACLgAFFH8KAAIGAAMJ2xFXDgDyAAAGAAMJ2xFXDgDyAAAuAAQKfzMAAgYACAkXH9QGANMCAAYACAkXH9QGANMCAAAA.Attenborough:BAAALgAECgUJBgABLgAECgYJDwADAAAAAA==.',
Av='Avesa:BAAALgAECgIJAgAAAA==.Avoidant:BAAALgAECgUJCgAAAA==.',
Ay='Aydir:BAAALgADCgUJBwAAAA==.Aylithe:BAAALgAECgQJBAAAAA==.',
Az='Azanadra:BAAALgAECgQJBwAAAA==.Azazell:BAAALgADCgYJBgAAAA==.Azenea:BAABLgAECn8WAAMHAAgJigStDQBZAQAHAAgJigStDQBZAQAIAAIJhwGMIAEwAAAAAA==.',
Ba='Baculum:BAAALgAECgYJEgAAAA==.Bacõn:BAAALgAECgQJBAAAAA==.Badmoonrisin:BAAALgAECgMJAwAAAA==.Bainne:BAAALgAECgIJBAAAAA==.Ballzach:BAAALgAECgUJEwABLgAFFAUJEQAJAMIhAA==.Bazookabob:BAAALgAECgYJEgAAAA==.',
Be='Beangles:BAAALgADCgYJBgAAAA==.Becky:BAAALgADCgkJCgABLgAECgUJDAADAAAAAA==.Beekyy:BAAALgAECgUJDAAAAA==.Belenova:BAAALgAECgUJBgAAAA==.Bellapearl:BAAALgAECgEJAQAAAA==.Berkyn:BAAALgADCgMJAwAAAA==.',
Bi='Bittydrood:BAAALgADCgYJBgAAAA==.Bittylexis:BAAALgAECgEJAQAAAA==.',
Bl='Blakheart:BAABLgAECn8cAAIKAAgJoBT/BQAgAgAKAAgJoBT/BQAgAgAAAA==.Bleuopal:BAAALgADCgcJDAAAAA==.Blueaxle:BAABLgAECn8YAAMLAAgJDBPuLADRAQALAAgJDBPuLADRAQAMAAIJpgG0MQFAAAAAAA==.Blur:BAAALgADCgkJEgAAAA==.Blèu:BAAALgAECgYJDwAAAA==.',
Bo='Boomdoom:BAAALgAECgQJBAAAAA==.Bootycat:BAAALgADCgcJBwABLgADCgkJCgADAAAAAA==.Bora:BAAALgAECgQJDQAAAA==.Bouffenièce:BAAALgAECgQJBwAAAA==.Boufsy:BAAALgADCgkJEQAAAA==.',
Br='Breathe:BAAALgAECgcJEAAAAA==.Brewballs:BAABLgAECn8VAAINAAYJtgrGDQAGAQANAAYJtgrGDQAGAQAAAA==.Brynarra:BAAALgADCgUJBQAAAA==.',
Bu='Bubbletea:BAAALgAECgIJAgAAAA==.Bunnicula:BAABLgAECn8VAAMHAAcJ6RZ0BwDcAQAHAAYJfRp0BwDcAQAIAAEJCQV2WwAqAAAAAA==.',
Bw='Bwanga:BAAALgAECgYJDwAAAA==.',
['Bö']='Böömer:BAAALgAECgEJAQAAAA==.',
Ca='Calmac:BAAALgAECgYJDQAAAA==.Cameron:BAAALgAECgYJDAAAAA==.Capetonrex:BAAALgAECgEJAQAAAA==.Caythus:BAABLgAECn8WAAMOAAcJ4SS1CwAGAgAOAAUJDyS1CwAGAgAIAAUJ5iILUQDVAQAAAA==.',
Ce='Celeana:BAAALgAECgYJDQAAAA==.Celencia:BAAALgADCgUJCAAAAA==.',
Ch='Chadmcguffin:BAAALgAECgcJEwAAAA==.Chakabad:BAAALgAECgEJAQAAAA==.Chalgar:BAAALgADCgcJFAAAAA==.Chaosblossom:BAAALgADCgYJBwAAAA==.Chenahala:BAAALgAECgEJAQAAAA==.Chibeard:BAAALgAECgkJBgAAAA==.Chåni:BAAALgAECgYJEwAAAA==.',
Ci='Ciege:BAABLgAECn8UAAMPAAgJpBFvCABjAQAPAAcJFxFvCABjAQAQAAQJdhG2KwC/AAAAAA==.Cinrah:BAAALgAFFAMJAwAAAA==.',
Cl='Cloudwalker:BAAALgADCgkJCQAAAA==.',
Co='Coffeelatte:BAAALgAECgEJAQAAAA==.Complainz:BAAALgADCgYJDAAAAA==.Concinnat:BAAALgADCgUJBQAAAA==.Confessorr:BAAALgADCgYJBgAAAA==.Cosantóir:BAAALgAECgQJBQAAAA==.',
Cr='Crispysock:BAAALgAECgYJCQAAAA==.Croda:BAAALgAECgYJCQAAAA==.Crowe:BAAALgAECgEJAQAAAA==.Cröno:BAAALgAECgYJBgAAAA==.',
Cu='Cursez:BAAALgAECgUJBQABLgAFFAQJEAARAFEVAA==.',
Cy='Cylndra:BAAALgADCgMJAwAAAA==.Cynderr:BAAALgAECgMJAwAAAA==.',
['Cè']='Cèrc:BAAALgAECgEJAgAAAA==.',
Da='Daemian:BAAALgADCgIJAgABLgAECgcJEwADAAAAAA==.Dakarba:BAAALgADCgMJBQAAAA==.Daquilla:BAAALgAECgUJBgAAAA==.Dargonit:BAAALgAECgUJAQAAAA==.Darkisis:BAAALgAECgQJBAABLgAECgYJBgADAAAAAA==.Darknara:BAABLgAECn8fAAISAAgJsx4QJQCpAgASAAgJsx4QJQCpAgAAAA==.Darkterror:BAAALgAECgYJBgAAAA==.Darkzy:BAAALgAECgMJAwAAAA==.Dartol:BAAALgADCggJCQAAAA==.Dasubertakem:BAAALgADCgEJAgAAAA==.Dawni:BAAALgAECgYJEQAAAA==.',
De='Deathies:BAAALgADCgIJAgAAAA==.Deathigh:BAAALgADCgUJBgAAAA==.Deathjeff:BAAALgAECgcJCgAAAA==.Deathsgates:BAABLgAECn8XAAIIAAcJFSD4HgCeAgAIAAcJFSD4HgCeAgABLgAECggJIgAKAJAfAA==.Decasia:BAAALgAECgYJCwAAAA==.Deheon:BAAALgADCgQJBgAAAA==.Demoswal:BAAALgADCgEJAgAAAA==.Descendent:BAAALgADCgEJAQAAAA==.Destickament:BAAALgADCgMJAwAAAA==.Detala:BAAALgAECgEJAQAAAA==.Detective:BAAALgADCgkJFwAAAA==.Dethkeela:BAABLgAECn8WAAISAAYJrBfMawCzAQASAAYJrBfMawCzAQABLgAFFAUJCQAFAMMHAA==.Dewy:BAAALgAECgYJDwAAAA==.',
Dh='Dhfig:BAABLgAECn8VAAITAAcJlxOGTwC4AQATAAcJlxOGTwC4AQAAAA==.',
Di='Dimos:BAAALgAECgUJBQAAAA==.Dinoll:BAAALgAECgYJCQAAAA==.Dirtwhistle:BAAALgAECgEJBAAAAA==.',
Do='Dogo:BAAALgADCgcJCwAAAA==.',
Dr='Draconnt:BAAALgAECgMJAwAAAA==.Dragondh:BAABLgAECn8kAAIUAAgJVxe4AgDfAQAUAAgJVxe4AgDfAQAAAA==.Draksvoid:BAAALgAECgUJBgAAAA==.Dranlu:BAAALgADCgcJBwAAAA==.Dranog:BAABLgAECn8YAAMIAAgJcBTqcAB9AQAIAAgJcBTqcAB9AQAOAAIJVQXMXQBVAAAAAA==.Draxol:BAAALgADCgcJDQAAAA==.Drazsi:BAAALgAECgYJBgAAAA==.Drovaal:BAAALgADCgEJAQAAAA==.Druidbod:BAAALgAECgUJCAABLgAFFAUJDQABAFYaAA==.Drutacular:BAAALgADCgEJAgAAAA==.',
Du='Durga:BAAALgAECgIJBAAAAA==.Dusk:BAAALgADCgEJAQABLgAECgEJAQADAAAAAA==.',
Dy='Dyromancer:BAAALgADCgYJEgAAAA==.',
['Dé']='Défect:BAABLgAECn8UAAISAAYJmBHPmwBJAQASAAYJmBHPmwBJAQAAAA==.',
['Dô']='Dôminic:BAAALgAECgEJAgAAAA==.',
Eb='Ebpindots:BAAALgAECgYJEgAAAA==.',
Eg='Eggegg:BAAALgAECgMJBgABLgAECggJIwAFALYaAA==.',
El='Eleanne:BAAALgAECgYJDwAAAA==.Elfrida:BAAALgADCgIJBAAAAA==.Ellebasi:BAABLgAECn8hAAIVAAYJ3BPSFwBYAQAVAAYJ3BPSFwBYAQAAAA==.',
Em='Emarosa:BAAALgADCgcJBwABLgAECgYJEgADAAAAAA==.',
En='Enazen:BAAALgAECgYJCAAAAA==.Enchantz:BAAALgADCgYJBgAAAA==.Endzela:BAAALgADCgUJBQAAAA==.Enky:BAAALgADCgcJCAAAAA==.',
Er='Erlas:BAAALgADCgkJGgAAAA==.Errol:BAAALgADCgUJBQAAAA==.Erui:BAAALgAECgEJAQAAAA==.',
Ev='Evilrayne:BAABLgAECn8dAAIWAAgJSxXBDgDQAQAWAAgJSxXBDgDQAQAAAA==.Evoxus:BAAALgAECgMJAwAAAA==.',
Fa='Fatherfingur:BAAALgAECgQJCQAAAA==.Fauxpas:BAAALgAECgUJCAAAAA==.Fawnzy:BAAALgAECgMJAwAAAA==.',
Fe='Fearoshimâ:BAAALgADCgUJBQAAAA==.Feldommy:BAAALgAECgUJBQAAAA==.Feloak:BAABLgAECn8bAAIXAAgJfw1FAwBOAQAXAAgJfw1FAwBOAQAAAA==.Felonie:BAAALgADCgIJAwAAAA==.Fenyxfall:BAAALgAECgMJAwAAAA==.Feredir:BAAALgAECgMJBQAAAA==.Ferzod:BAAALgADCgEJAQABLgAECgcJEAADAAAAAA==.',
Fi='Fieryfang:BAABLgAECn8cAAIYAAcJ0CDlAwAEAgAYAAcJ0CDlAwAEAgAAAA==.Fireshader:BAAALgADCgEJAQAAAA==.Fistandilius:BAAALgAECgUJCQAAAA==.Fistman:BAAALgAECgcJEgAAAA==.',
Fl='Flashsomhash:BAAALgAECgEJAQAAAA==.Flyleaf:BAAALgAECgYJDwAAAA==.',
Fo='Foshnu:BAABLgAECn8VAAMZAAYJnwz/TwBEAQAZAAYJnwz/TwBEAQARAAUJKAcNFwC+AAAAAA==.',
Fr='Fraks:BAAALgADCgMJAwAAAA==.Frozandrov:BAAALgAECgQJCgAAAA==.',
Fu='Fujie:BAABLgAECn8ZAAIUAAgJox/yCQDDAgAUAAgJox/yCQDDAgAAAA==.Fujï:BAAALgAECgYJBgAAAA==.Furryfury:BAABLgAECn8bAAMNAAgJ8A4pMwAqAQANAAgJ8A4pMwAqAQAaAAUJ2gmRTgDYAAAAAA==.Fuzzyewok:BAAALgAECggJCAAAAA==.',
['Fë']='Fëlisha:BAAALgADCgQJBAAAAA==.',
Ga='Gaazmataaz:BAAALgADCgkJHAAAAA==.Galadir:BAAALgADCgEJAQAAAA==.Garag:BAAALgADCgUJBQAAAA==.Garlstedt:BAAALgAECgQJBAAAAA==.Gawdzirra:BAAALgADCgIJAgAAAA==.',
Ge='Genstein:BAAALgADCgIJAgAAAA==.George:BAAALgAECgYJCgAAAA==.',
Gh='Ghulrokk:BAAALgAECgYJDAAAAA==.',
Gi='Gizmo:BAAALgADCgkJFAAAAA==.',
Gl='Glenndragon:BAAALgAECgUJCgAAAA==.Gluum:BAAALgAECgEJAQAAAA==.',
Go='Gohibasi:BAAALgAECgMJBQAAAA==.Gossamerfeet:BAAALgAECgYJDAAAAA==.Gotalian:BAABLgAECn8XAAIMAAYJvgn6KAD/AAAMAAYJvgn6KAD/AAAAAA==.',
Gr='Graceosilver:BAAALgAECgYJDgAAAA==.Grajademoh:BAAALgADCgcJDAAAAA==.Grajashadow:BAAALgAECgQJBgAAAA==.Gregnor:BAABLgAECn8bAAMbAAgJRhahAgCoAQAbAAcJSBihAgCoAQAcAAEJOArTDgArAAAAAA==.Grim:BAABLgAECn8XAAISAAgJ9xeAOQBRAgASAAgJ9xeAOQBRAgAAAA==.Grover:BAAALgAECgUJCAAAAA==.Grozztrak:BAAALgADCgQJBAAAAA==.Grumpybun:BAAALgADCgYJCwAAAA==.Grumpybunbun:BAAALgAECgcJEgAAAA==.',
Gu='Guldrosi:BAABLgAECn8bAAMIAAgJchQZEACRAQAIAAcJ7RUZEACRAQAOAAQJPBENRAClAAAAAA==.',
Gy='Gyat:BAAALgAECgYJEAAAAA==.',
['Gå']='Gårrus:BAAALgAECgcJEAAAAA==.',
Ha='Haarl:BAAALgADCgkJHgAAAA==.Hairypotter:BAAALgADCgMJAwAAAA==.Hallie:BAAALgAECgYJDgAAAA==.Hargoose:BAAALgAECgEJAQAAAA==.Harlu:BAABLgAECn8VAAIRAAYJFwXHFQDKAAARAAYJFwXHFQDKAAAAAA==.Hartbroke:BAABLgAECn8VAAIMAAYJ7RrJEgCMAQAMAAYJ7RrJEgCMAQAAAA==.',
He='Helbourne:BAAALgAECgUJCQAAAA==.Hextraspicy:BAAALgADCgQJBAAAAA==.',
Hi='Hideyoshi:BAAALgADCgcJGwAAAA==.Hijjiup:BAAALgAECgEJAQAAAA==.Hildah:BAAALgAECgIJBAAAAA==.',
Ho='Holliestraza:BAABLgAECn8YAAIZAAgJxRKxDABxAQAZAAgJxRKxDABxAQAAAA==.Holyadrian:BAAALgADCgEJAQAAAA==.Holyfugde:BAAALgADCgQJBQAAAA==.Holyman:BAAALgADCgMJAwAAAA==.',
Hw='Hwanwok:BAAALgAECgUJDAAAAA==.',
Hy='Hyacynth:BAAALgADCgYJBQAAAA==.Hypermage:BAAALgADCgcJBwAAAA==.',
['Hä']='Härbinger:BAAALgAECgUJCQAAAA==.',
Ic='Ic:BAAALgAECgIJAgAAAA==.',
Ig='Ignited:BAAALgADCgYJBwAAAA==.',
Im='Imadragon:BAABLgAECn8WAAIQAAcJOBJcEwCtAQAQAAcJOBJcEwCtAQAAAA==.Imdeadguy:BAABLgAECn8VAAIdAAcJtSLMCwBQAgAdAAcJtSLMCwBQAgAAAA==.',
In='Innalowda:BAAALgADCgcJEQABLgAECgcJEwADAAAAAA==.',
Ir='Ironhelmhtr:BAAALgAECgMJCAAAAA==.Irënicus:BAAALgADCgcJCgAAAA==.',
Is='Isendra:BAAALgAECgYJDgAAAA==.',
It='Itachi:BAAALgADCgcJGAAAAA==.',
Ja='Jabtak:BAAALgAECgMJAwAAAA==.Jaded:BAAALgADCgUJBQAAAA==.Janinoo:BAAALgAECgYJDgAAAA==.Jararth:BAAALgAECgEJBAAAAA==.Jazlee:BAAALgAECgYJEAAAAA==.',
Je='Jeggana:BAAALgADCgcJGAAAAA==.',
Ji='Jinathy:BAABLgAECn8bAAIMAAgJDRIwDwCtAQAMAAgJDRIwDwCtAQAAAA==.Jinnite:BAAALgADCgEJAQAAAA==.',
Jo='Jolyñ:BAABLgAECn8WAAIeAAcJ5BEQBwCcAQAeAAcJ5BEQBwCcAQABLgAECggJFwAEAMsKAA==.',
Ju='Jualygosa:BAABLgAECn8aAAIWAAcJexWmFQCWAQAWAAcJexWmFQCWAQAAAA==.Judgementall:BAAALgAECgUJBgAAAA==.Juomancito:BAAALgAECgYJDgAAAA==.Justac:BAAALgAECgEJAQABLgAECgQJCgADAAAAAA==.Justgotbis:BAAALgAECgQJBAAAAA==.',
['Já']='Jáß:BAAALgAECggJEgAAAA==.',
['Jä']='Jäb:BAAALgADCgcJBwAAAA==.',
Ka='Kaddrix:BAAALgAECgYJCgAAAA==.Kaldonor:BAABLgAECn8dAAIfAAgJKBLTAQCDAQAfAAgJKBLTAQCDAQAAAA==.Kalenia:BAABLgAECn8cAAIZAAgJWiGEAQCoAgAZAAgJWiGEAQCoAgAAAA==.Kalvayre:BAABLgAECn8WAAISAAYJIBXHfwCDAQASAAYJIBXHfwCDAQAAAA==.Kamuui:BAAALgADCgYJBgABLgADCgcJGwADAAAAAA==.Kanzoorb:BAAALgAECgUJBQAAAA==.Karpana:BAEBLgAECn8YAAMVAAYJhxaSFwBcAQAVAAYJhxaSFwBcAQAMAAUJvg4VKwD0AAAAAA==.Kashir:BAAALgAECgYJDwAAAA==.Katamoonfang:BAAALgADCgkJEQAAAA==.Katastrophe:BAAALgAECgYJCwAAAA==.Katsumi:BAAALgAECgQJBgAAAA==.Kaythewitch:BAAALgAECgUJBQAAAA==.Kazimirah:BAAALgADCgYJDgAAAA==.Kazrael:BAAALgAECgEJAQAAAA==.',
Ke='Keekat:BAAALgADCgkJGQAAAA==.Kegstands:BAAALgAECgIJAgAAAA==.Kerprage:BAAALgAECgQJBgAAAA==.Kerpredem:BAAALgADCgYJDAAAAA==.Kerpspells:BAAALgADCgcJCgAAAA==.',
Kh='Khariaa:BAAALgADCgcJBwAAAA==.Khoravi:BAAALgAECgYJDAAAAA==.',
Ki='Kikora:BAAALgADCgUJBQAAAA==.Kitaska:BAAALgADCgQJAwABLgAECgcJGwALAFsQAA==.Kittykitty:BAABLgAECn8ZAAMZAAgJLRmSHAA1AgAZAAgJLRmSHAA1AgAgAAQJExO9GwAPAQAAAA==.',
Ko='Kolzane:BAACLgAFFH8OAAIFAAUJniIbAAANAgAFAAUJniIbAAANAgAuAAQKfxcAAwUACAknJHYGACYDAAUACAknJHYGACYDACEABAnYECBgAMAAAAAA.Kongfu:BAAALgAECgYJCgAAAA==.Korravah:BAAALgAECgQJBwAAAA==.Koyuki:BAAALgADCgcJDAAAAA==.',
Kr='Kramps:BAAALgAECgMJBAAAAA==.Krandel:BAAALgAECgMJAwAAAA==.Kronan:BAAALgADCgIJAgAAAA==.',
Ku='Kuulas:BAAALgAECgcJEgAAAA==.',
Ky='Kyth:BAABLgAECn8aAAIVAAgJ0A8iFACKAQAVAAgJ0A8iFACKAQAAAA==.Kythlock:BAAALgADCgkJEwABLgAECggJGgAVANAPAA==.Kythtok:BAAALgAECgYJEQABLgAECggJGgAVANAPAA==.',
['Kø']='Køda:BAABLgAECn8YAAMBAAgJhiGtHgBKAgABAAgJhiGtHgBKAgAiAAYJxAz4DgAEAQAAAA==.',
La='Ladyhawk:BAAALgADCgYJBgAAAA==.Lazerbird:BAAALgADCgUJBgAAAA==.',
Le='Leggy:BAAALgAECgIJAgAAAA==.Lela:BAAALgADCgEJAQAAAA==.',
Li='Life:BAAALgADCgUJBQAAAA==.Lifebloomer:BAAALgAECgQJAwABLgAFFAUJEQAJAMIhAA==.Lightnup:BAAALgAECgUJCAAAAA==.Liralyn:BAAALgADCgcJDgAAAA==.Litharaldra:BAAALgADCgYJBgAAAA==.Littlehell:BAAALgAFFAMJAwAAAA==.',
Lo='Lokaroki:BAAALgAECgQJBwAAAA==.Lothbrokk:BAAALgAECgEJAQAAAA==.',
Lu='Lucaafer:BAABLgAECn8gAAIWAAgJcB8nMwCmAgAWAAgJcB8nMwCmAgAAAA==.Luda:BAAALgAECgcJEQAAAA==.',
Ly='Lyssandria:BAABLgAECn8eAAIWAAgJGQcyIABUAQAWAAgJGQcyIABUAQAAAA==.Lyzoldas:BAABLgAECn8XAAIMAAYJ0BljFwBmAQAMAAYJ0BljFwBmAQAAAA==.',
['Lö']='Löwryder:BAAALgAECgYJCgAAAA==.',
Ma='Maddera:BAAALgAECgUJCAAAAA==.Madmurdock:BAAALgAECgYJDwAAAA==.Madness:BAAALgAECgMJAwAAAA==.Maemura:BAAALgAECgMJBQAAAA==.Magîkarp:BAAALgADCgYJBwAAAA==.Maiki:BAAALgADCgQJBQAAAA==.Malach:BAAALgAECgcJAgAAAA==.Malchromatus:BAAALgAECgcJEQAAAA==.Marcosio:BAAALgAECgEJAQAAAA==.Marsala:BAAALgAECgYJDwAAAA==.',
Mb='Mbop:BAAALgAECgQJBAAAAA==.',
Mc='Mcchud:BAAALgAECgEJAQAAAA==.',
Me='Meandragon:BAAALgADCgcJBwAAAA==.Meatyfajita:BAABLgAECn8ZAAILAAgJZSYcAAB8AwALAAgJZSYcAAB8AwAAAA==.Mechabrew:BAAALgAECgUJCgABLgAECgYJEAADAAAAAA==.Medousa:BAAALgAECgMJAwAAAA==.Megaera:BAAALgAECgMJBQAAAA==.Meiko:BAAALgAECgEJAQABLgAECgYJEgADAAAAAA==.Meladie:BAAALgAECgEJAgAAAA==.Meladrus:BAAALgADCgEJAQAAAA==.Mellene:BAAALgADCgkJFgAAAA==.Memedecay:BAABLgAECn8dAAMSAAgJnB6kBABIAgASAAgJnB6kBABIAgAJAAEJnRkeQwA9AAAAAA==.Mememalefic:BAAALgAECgcJCAABLgAECggJHQASAJweAA==.Mericck:BAAALgADCgMJAwAAAA==.Merlinthos:BAAALgADCgMJAwABLgAECggJHQAKAGQSAA==.Metaljack:BAABLgAECn8bAAIWAAgJhCHKAgCnAgAWAAgJhCHKAgCnAgAAAA==.',
Mi='Miasma:BAAALgAECgYJDgABLgAECgMJDgADAAAAAA==.Mikeyboi:BAAALgADCgEJAQAAAA==.Milanesa:BAABLgAECn8ZAAIdAAgJ+hQoEgDlAQAdAAgJ+hQoEgDlAQAAAA==.Mingyue:BAAALgADCgIJBAABLgAECggJJAAPAJ8NAA==.Mishaweha:BAAALgAECgQJBQAAAA==.Mithrandir:BAAALgAECgQJBAAAAA==.Mitos:BAABLgAECn8hAAIMAAgJOBC2EQCWAQAMAAgJOBC2EQCWAQAAAA==.Miyasabi:BAAALgADCgYJBgAAAA==.Mizzet:BAAALgADCgUJBQAAAA==.',
Mo='Modar:BAABLgAECn8UAAIZAAgJ2he8CQCkAQAZAAgJ2he8CQCkAQAAAA==.Monkas:BAAALgADCgcJCQAAAA==.Moonpaw:BAAALgAECgEJAQAAAA==.Moonrid:BAAALgADCgcJGQAAAA==.Moonshayd:BAAALgAECgYJBwAAAA==.Moreann:BAAALgADCgcJDQAAAA==.Morphëus:BAAALgAECgUJCQAAAA==.',
Mu='Muggy:BAAALgADCgIJAgABLgAFFAQJCAASAL0aAA==.Muha:BAAALgAECgEJAQABLgAECgIJAgADAAAAAA==.Mushi:BAAALgADCgkJEgAAAA==.Mustardplug:BAAALgADCgEJAQAAAA==.Muzan:BAAALgAECgQJBAAAAA==.Muzzin:BAAALgADCgEJAQAAAA==.',
['Må']='Måddløck:BAAALgAECgEJAQAAAA==.',
Ne='Needslotion:BAAALgAECgUJCQAAAA==.Neiidra:BAAALgAECgYJDAAAAA==.Nepheleah:BAABLgAECn8cAAIMAAgJkiEnEAAOAwAMAAgJkiEnEAAOAwAAAA==.Nesmoth:BAABLgAECn8VAAIJAAcJ4iM1BgDVAgAJAAcJ4iM1BgDVAgAAAA==.Ness:BAAALgAECgEJAQAAAA==.',
Ni='Niiborracho:BAABLgAECn8ZAAMaAAgJGg/rCQA0AQAaAAgJGg/rCQA0AQANAAEJdg0AagAuAAAAAA==.Niiko:BAAALgAECgEJAQAAAA==.Niisera:BAAALgADCgQJBwAAAA==.',
No='Norntrox:BAABLgAECn8VAAMTAAYJpx2fFwBCAQATAAYJpx2fFwBCAQAXAAEJAACyKQA9AAAAAA==.Nosåj:BAAALgADCgQJBQAAAA==.',
Ns='Nsshaman:BAAALgADCgMJAwAAAA==.',
Ny='Nylaria:BAAALgADCgUJBQAAAA==.Nyxari:BAAALgAECgUJCQAAAA==.',
Ob='Obscuría:BAAALgADCgYJBwAAAA==.',
Od='Odrik:BAAALgADCgQJCAAAAA==.',
Ol='Oleana:BAAALgAECgQJBAAAAA==.Oleia:BAAALgAECgQJBgAAAA==.',
On='Onatha:BAAALgADCgkJGgAAAA==.Onaw:BAAALgAECgQJBwAAAA==.',
Op='Ops:BAAALgAECgQJBAAAAA==.',
Or='Orctism:BAAALgADCgIJAgAAAA==.',
Ow='Owlsonatotem:BAABLgAECn8bAAIZAAgJxBfkCQCgAQAZAAgJxBfkCQCgAQAAAA==.',
Ox='Oxymage:BAAALgADCgUJBQAAAA==.',
Pa='Pakno:BAAALgAECgUJCgAAAA==.Paletia:BAAALgAECgYJBgAAAA==.Pamely:BAAALgAECgcJEgAAAA==.',
Pe='Petethelock:BAAALgADCgEJAQAAAA==.',
Ph='Pharmit:BAABLgAECn8UAAMIAAcJ0yLYPQAVAgAIAAYJ0yLYPQAVAgAOAAIJ1B5pPADDAAAAAA==.Phayte:BAAALgADCgkJEAAAAA==.Photon:BAAALgADCgYJBQAAAA==.Phrock:BAAALgADCgEJAgAAAA==.',
Pl='Pletua:BAABLgAECn8WAAIjAAcJ2B34FQBfAgAjAAcJ2B34FQBfAgAAAA==.',
Po='Porazdir:BAAALgAECgUJBgAAAA==.Porcelayna:BAAALgAECgEJAQABLgAECgYJFQAZAJ8MAA==.',
Pr='Primoris:BAAALgADCgUJBQAAAA==.',
Ps='Psion:BAAALgADCgYJBgAAAA==.',
Pu='Puds:BAAALgADCgMJAwAAAA==.',
['På']='Påimon:BAAALgADCgIJAgAAAA==.',
['Pö']='Pöê:BAAALgAECgIJAgAAAA==.',
Qu='Quintin:BAAALgAECgYJBgAAAA==.',
Ra='Racavis:BAAALgADCgcJCAAAAA==.Raenisa:BAEALgADCgQJBwABLgAECgYJEgADAAAAAA==.Ragp:BAAALgAECgMJAwAAAA==.Rainydevil:BAAALgADCgcJDgAAAA==.Rainydevils:BAAALgADCgIJAgAAAA==.Rainymdevil:BAAALgADCgUJBQAAAA==.Rainyxdvl:BAAALgAECgEJAQAAAA==.Ramasey:BAAALgAECgYJDgAAAA==.Rasriann:BAAALgAECgQJBAAAAA==.Rawrlordz:BAAALgAECgYJDAAAAA==.',
Re='Reaces:BAAALgADCgEJAQAAAA==.Real:BAABLgAECn8VAAIWAAcJ2RzmbQD5AQAWAAcJ2RzmbQD5AQABLgADCgkJCQADAAAAAA==.Reda:BAAALgADCgQJBAAAAA==.Reeality:BAAALgADCgkJCQAAAA==.Reelio:BAAALgAECgQJBwAAAA==.Reikio:BAAALgADCgMJAwAAAA==.Rennala:BAAALgADCgkJFAAAAA==.Repeal:BAAALgAECgQJBAAAAA==.Reptar:BAAALgADCgYJBgABLgAECgUJBQADAAAAAA==.Retbet:BAAALgAECgUJBQAAAA==.Revoke:BAAALgAECgcJEgAAAA==.Reyanne:BAEALgAECgYJEgAAAA==.',
Ro='Rockfish:BAAALgADCgQJBgAAAA==.Roofio:BAAALgADCgEJAQABLgAECgcJEwADAAAAAA==.',
Ru='Rubiroo:BAAALgADCgEJAQAAAA==.Runebellwolf:BAAALgADCgcJCgAAAA==.Ruroni:BAAALgADCgUJBQAAAA==.',
Ry='Ryniel:BAAALgAECgYJDgAAAA==.Rynthia:BAAALgADCgkJCQAAAA==.',
['Ré']='Réira:BAAALgADCgkJEQABLgAECggJJAAPAJ8NAA==.',
['Rï']='Rïptide:BAAALgAECgEJAQAAAA==.',
Sa='Sabrinalee:BAAALgADCgcJBwAAAA==.Sacremierde:BAAALgAECgEJAQAAAA==.Sagah:BAAALgAECgYJEQAAAA==.Saintdeamon:BAABLgAECn8WAAMBAAYJkRe0QQCbAQABAAYJkRe0QQCbAQAiAAUJSQgEEwDLAAAAAA==.Sanasta:BAAALgAECgYJDgAAAA==.Sandspur:BAAALgAECgEJAQAAAA==.Sanielin:BAABLgAECn8ZAAIkAAcJZCAIBQDFAQAkAAcJZCAIBQDFAQAAAA==.Saphìr:BAAALgAECgQJBwAAAA==.Saramoon:BAABLgAECn8VAAMjAAYJDQjdDgDeAAAjAAYJDQjdDgDeAAAKAAQJhgLSFQCdAAAAAA==.Sarda:BAEALgAECgUJBwAAAA==.Sargent:BAAALgAECgUJCAAAAA==.Saryaa:BAAALgAECgUJCwAAAA==.Sashchi:BAAALgAECgcJEwAAAA==.Satheronys:BAAALgAECgEJAQABLgAECgMJAwADAAAAAA==.',
Sc='Schade:BAAALgAECgQJCAAAAA==.Schrödinger:BAAALgAECgMJAwAAAA==.',
Se='Searen:BAAALgADCgMJAwAAAA==.Sehmet:BAAALgAECgEJAQAAAA==.Seiso:BAAALgAFFAMJAwAAAA==.Seliria:BAABLgAECn8bAAIMAAgJDgl5FwBlAQAMAAgJDgl5FwBlAQAAAA==.Sephaman:BAAALgAECgEJAQAAAA==.Seprogue:BAAALgADCgcJCgAAAA==.',
Sh='Shadyn:BAAALgAECgEJAQAAAA==.Shadówz:BAAALgADCgEJAQAAAA==.Sheepstealer:BAAALgADCgQJAwAAAA==.Shiftace:BAAALgADCgEJAwAAAA==.Shiryo:BAAALgAECgMJBwAAAA==.Shockwater:BAAALgAECgEJAgAAAA==.Shotfoot:BAAALgADCgkJHwAAAA==.Shwang:BAAALgAECgYJEQAAAA==.',
Si='Siclock:BAAALgADCgUJBQAAAA==.Sikkerp:BAAALgADCgMJBAAAAA==.Silentio:BAABLgAECn8dAAIKAAgJZBKcAQC1AQAKAAgJZBKcAQC1AQAAAA==.Silihunt:BAAALgADCgMJAwAAAA==.Siliçå:BAAALgADCgYJCQAAAA==.Sinamun:BAABLgAECn8bAAILAAcJWxC8QwBpAQALAAcJWxC8QwBpAQAAAA==.Sinofwrath:BAABLgAECn8WAAITAAgJNB6YBABFAgATAAgJNB6YBABFAgAAAA==.Sinsidious:BAAALgAECgUJCQAAAA==.Siwin:BAACLgAFFH8NAAIBAAUJVhoIBAChAQABAAUJVhoIBAChAQAuAAQKfxwAAwEACAm3JNAIAAIDAAEACAm3JNAIAAIDACIAAQlqHgV5AEEAAAAA.',
Sk='Skarlett:BAAALgAECgQJBQAAAA==.Skiller:BAAALgADCgYJDAAAAA==.Skinobi:BAAALgAECgEJAQAAAA==.Skysqueezer:BAAALgAECgYJCgAAAA==.',
Sl='Slapchóp:BAABLgAECn8UAAIRAAgJrhooBADsAQARAAgJrhooBADsAQAAAA==.',
Sm='Smoko:BAABLgAECn8UAAIEAAcJkRzxDQDoAQAEAAcJkRzxDQDoAQAAAA==.',
Sn='Snorlax:BAAALgAECgIJAgABLgAECgYJEgADAAAAAA==.Snowxstorm:BAABLgAECn8aAAIJAAcJliHEAQAfAgAJAAcJliHEAQAfAgAAAA==.',
So='Sobieski:BAAALgAECgkJCQAAAA==.Solae:BAAALgADCgkJDwAAAA==.Solrond:BAAALgAECgQJCAAAAA==.Somemageguy:BAAALgAECgEJAQAAAA==.Souldecay:BAABLgAECn8aAAISAAgJBAvxEACNAQASAAgJBAvxEACNAQAAAA==.Soultender:BAAALgADCgIJAgAAAA==.',
Sp='Spekktrum:BAAALgAECgEJAQAAAA==.',
Sq='Squidacles:BAAALgADCgEJAQAAAA==.Squirrly:BAAALgAECgEJAQAAAA==.',
St='Stainedone:BAAALgAECgUJCQAAAA==.Staqua:BAAALgAECgEJAQAAAA==.Stateomatter:BAAALgAECgYJDgAAAA==.Stevenflowe:BAAALgADCgcJCAAAAA==.Stoneslacher:BAAALgADCgIJBAAAAA==.Streamesance:BAAALgAECgYJBgAAAA==.',
Su='Suanni:BAABLgAECn8kAAQPAAgJnw1zEADoAAAPAAgJnw1zEADoAAAQAAIJSAhvBwBlAAAGAAEJoQDuTwAPAAAAAA==.Summdari:BAABLgAECn8XAAIXAAgJIRbjBgAfAgAXAAgJIRbjBgAfAgAAAA==.Summrot:BAAALgAECgYJDgAAAA==.Sunfrostt:BAAALgAECgQJBAAAAA==.Supplock:BAAALgAECgYJDwAAAA==.Suromeme:BAAALgAECgQJBAABLgAECgcJFwAcANIfAA==.',
Sw='Swizzler:BAAALgAECgQJBgAAAA==.',
Sy='Sylvalesta:BAAALgAECgEJAQAAAA==.',
Ta='Taedro:BAAALgADCgcJEgAAAA==.Taichung:BAAALgAECgUJAQAAAA==.Talyon:BAAALgAECgUJBQAAAA==.Tayge:BAAALgADCgEJAQAAAA==.',
Te='Tekeelà:BAAALgAECgQJCgABLgAFFAUJCQAFAMMHAA==.Tenebris:BAABLgAECn8XAAIMAAYJjRhvJgAMAQAMAAYJjRhvJgAMAQAAAA==.Terrorbyte:BAAALgADCgYJBgAAAA==.Terrorhungry:BAAALgAECgEJAQAAAA==.',
Th='Thalstrasza:BAAALgAECgQJDQAAAA==.Thalör:BAABLgAECn8XAAIiAAgJMha7HAAbAgAiAAgJMha7HAAbAgAAAA==.The:BAAALgAECgYJDgAAAA==.Thedevilsown:BAAALgADCgYJDgAAAA==.Thedrizzle:BAABLgAECn8VAAIWAAcJOB4WDgDYAQAWAAcJOB4WDgDYAQAAAA==.Thinkwizzle:BAAALgADCgYJBwAAAA==.Thunderthïgh:BAAALgAECgEJAQAAAA==.Thundrfury:BAAALgADCgkJGwAAAA==.',
Ti='Tibalt:BAAALgAFFAEJAQAAAA==.Tibbles:BAAALgAECgEJAQAAAA==.Tipsynips:BAAALgADCgQJBAAAAA==.',
Tk='Tkla:BAAALgADCgIJAgAAAA==.',
Tl='Tlanimass:BAABLgAECn8UAAIdAAYJoA6gCAABAQAdAAYJoA6gCAABAQAAAA==.',
To='Tommytubstub:BAAALgAECgEJAQAAAA==.Tomstrasza:BAAALgAECgIJAgAAAA==.Tormen:BAABLgAECn8dAAIlAAgJyw+JBgCbAQAlAAgJyw+JBgCbAQAAAA==.Totemforge:BAAALgAECgUJCgAAAA==.',
Tr='Trapdaddy:BAAALgADCgYJBgAAAA==.Traq:BAAALgADCgQJBAAAAA==.Treeko:BAAALgAECgYJCAABLgAFFAQJCQAIAK0IAA==.Treston:BAAALgAECgEJAQAAAA==.Treyna:BAAALgADCgQJAgAAAA==.',
Ts='Tsyubaki:BAAALgAECgcJCwAAAA==.',
Tw='Twistdmister:BAAALgADCgUJBAAAAA==.',
Ty='Tydes:BAAALgAECgUJCQAAAA==.',
Un='Unholybrotha:BAAALgAECgYJEgAAAA==.Unslayable:BAAALgADCgkJFQAAAA==.Unwell:BAABLgAECn8WAAMRAAcJzxGuEgDqAAARAAcJpxCuEgDqAAAgAAQJahEJHwDgAAAAAA==.',
Ur='Urotherdaddy:BAAALgAECgMJAwABLgAECgYJEQADAAAAAA==.',
Uz='Uzzy:BAAALgAECgEJAQAAAA==.',
Va='Vaevictis:BAAALgAECgQJBwAAAA==.Valandir:BAAALgADCgIJAgAAAA==.Valenith:BAAALgAECgYJEgAAAA==.Valtora:BAAALgAECgQJCQAAAA==.Vartic:BAAALgAECgYJDgAAAA==.Vassago:BAAALgAECgUJCAAAAA==.',
Ve='Veliry:BAAALgADCgEJAQAAAA==.Vellarieline:BAABLgAECn8YAAITAAcJ9hwfMQA2AgATAAcJ9hwfMQA2AgAAAA==.Velyssara:BAAALgAECgEJAQAAAA==.Ventor:BAABLgAECn8VAAIiAAcJ5iGfGABDAgAiAAcJ5iGfGABDAgABLgAFFAIJAwADAAAAAA==.Verbera:BAAALgAECgYJEQAAAA==.',
Vi='Viduus:BAAALgAECgEJAQAAAA==.Virdeserti:BAABLgAECn8WAAIeAAgJ9hiFDgB1AgAeAAgJ9hiFDgB1AgAAAA==.Visage:BAAALgADCgkJCQAAAA==.Vixolot:BAAALgAECgIJAgAAAA==.',
Vm='Vmaoh:BAAALgADCgQJBAAAAA==.',
Vo='Voidwithin:BAAALgAECgUJBgAAAA==.',
Vu='Vulpies:BAAALgADCgYJBgAAAA==.',
Wa='Wandiferous:BAAALgAECgYJCwAAAA==.',
Wi='Wickedsmaht:BAACLgAFFH8JAAIIAAQJrQjQCQAqAQAIAAQJrQjQCQAqAQAuAAQKfyAABA4ACAkYF1sWAJcBAA4ABwlYElsWAJcBAAgABgm9FcpuAIMBAAcAAQnOGYUtAEMAAAAA.Widowghast:BAAALgADCgQJBAAAAA==.Willowísp:BAABLgAECn8XAAIkAAYJjxErQABEAQAkAAYJjxErQABEAQAAAA==.Winsfer:BAAALgAECgYJDAAAAA==.',
Wn='Wnchester:BAAALgADCgEJAQAAAA==.',
Wo='Woggers:BAAALgAECgYJBgAAAA==.',
Wr='Wrathion:BAAALgAECgYJDgAAAA==.',
Wu='Wulfenstein:BAAALgADCgUJBQAAAA==.',
Wy='Wyvernman:BAAALgAECgEJAQAAAA==.Wywy:BAAALgADCgYJBgAAAA==.',
['Wí']='Wíppy:BAAALgADCgEJAQAAAA==.',
Xa='Xalthea:BAABLgAECn8VAAMTAAcJEBXpEAB+AQATAAcJyhTpEAB+AQAUAAEJ+BHVbgA2AAAAAA==.Xanda:BAABLgAECn8iAAIKAAgJkB/LAQD5AgAKAAgJkB/LAQD5AgAAAA==.',
Xe='Xenalah:BAAALgAECgIJAgAAAA==.',
Xi='Xikai:BAAALgADCgIJAgABLgAECgYJDAADAAAAAA==.',
Xo='Xobos:BAAALgAECgEJAQAAAA==.',
Xp='Xpddevour:BAABLgAECn8fAAITAAgJ+RQEEACGAQATAAgJ+RQEEACGAQAAAA==.',
Xs='Xscapenature:BAAALgAECgQJCgAAAA==.',
Xt='Xtena:BAAALgADCgkJCwAAAA==.Xtendron:BAABLgAECn8bAAMMAAgJqx7GGgDJAgAMAAgJqx7GGgDJAgALAAYJ4gfVWgARAQAAAA==.',
Xu='Xuxo:BAAALgADCgMJCAAAAA==.',
Ya='Yaraxiu:BAAALgAECgIJBAAAAA==.',
Ye='Yegarmiester:BAAALgAECgcJCwAAAA==.',
Yo='Yodidyoufart:BAABLgAECn8qAAMFAAgJQR8QCADoAQAhAAcJtBkeJwDtAQAFAAgJdR4QCADoAQAAAA==.',
Za='Zaco:BAAALgAECgYJEwAAAA==.Zakonn:BAAALgADCgEJAQAAAA==.Zarikas:BAAALgAECgYJCQAAAA==.Zatapatate:BAABLgAECn8cAAMXAAcJjRizAwA0AQATAAcJihjQTQC+AQAXAAYJSBKzAwA0AQAAAA==.',
Ze='Zekken:BAAALgADCgUJBwABLgADCgYJCQADAAAAAA==.Zerality:BAAALgAECgUJCgABLgAECgYJBgADAAAAAA==.',
Zh='Zhachy:BAABLgAECn8oAAQPAAgJ9iIYDwCFAgAPAAcJMiEYDwCFAgAQAAYJtyMpCgA8AgAGAAEJeBSiDwA/AAAAAA==.',
Zi='Ziggie:BAABLgAECn8ZAAITAAgJACTZBwBNAwATAAgJACTZBwBNAwAAAA==.Zinovia:BAAALgAECgcJEwAAAA==.Ziwei:BAAALgAECgMJBAABLgAECggJJAAPAJ8NAA==.',
Zo='Zombieboy:BAAALgAECgUJBQAAAA==.Zookee:BAABLgAECn8bAAINAAgJuxHxBgCaAQANAAgJuxHxBgCaAQAAAA==.',
['Ön']='Önlish:BAAALgADCgYJBgABLgAECgcJCQADAAAAAA==.Önlîsh:BAAALgADCgMJAwABLgAECgcJCQADAAAAAA==.',
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

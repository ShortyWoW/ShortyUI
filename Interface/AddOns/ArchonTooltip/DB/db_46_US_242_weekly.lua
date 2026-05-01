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

local lookup = {'Druid-Restoration','Warrior-Arms','Warrior-Fury','Priest-Holy','Warlock-Demonology','Hunter-BeastMastery','Hunter-Survival','Unknown-Unknown','Evoker-Preservation','Warlock-Affliction','Priest-Discipline','DeathKnight-Blood','Rogue-Assassination','Paladin-Holy','Paladin-Retribution','Monk-Mistweaver','Warlock-Destruction','Paladin-Protection','Evoker-Augmentation','Evoker-Devastation','DemonHunter-Devourer','Shaman-Elemental','DeathKnight-Unholy','DemonHunter-Havoc','Mage-Frost','DemonHunter-Vengeance','Monk-Windwalker','Shaman-Restoration','Shaman-Enhancement','Druid-Feral','Druid-Guardian','Warrior-Protection','DeathKnight-Frost','Hunter-Marksmanship','Druid-Balance','Monk-Brewmaster','Rogue-Subtlety','Priest-Shadow',}
local provider = {region='US',realm='Ysera',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Ababear:BAABLgAECn8UAAIBAAgJnB2dDQDOAgABAAgJnB2dDQDOAgAAAA==.Abardi:BAAALgADCgUJBgAAAA==.',
Ad='Adeki:BAAALgADCgEJAQAAAA==.',
Ae='Aedaria:BAAALgADCgMJAwAAAA==.Aegis:BAAALgAECgEJAgAAAA==.Aeira:BAAALgADCgYJCQAAAA==.Aelora:BAAALgADCgMJAwAAAA==.Aerenna:BAAALgADCgUJBQAAAA==.',
Ag='Agakk:BAACLgAFFH8HAAICAAMJSx3rBQAdAQACAAMJSx3rBQAdAQAuAAQKfygAAgIACAnWIlMCAAQDAAIACAnWIlMCAAQDAAAA.Agilities:BAAALgAECgQJBAAAAA==.',
Al='Alarrius:BAABLgAECn8aAAMCAAgJmhLcDAA1AQADAAYJ+hV5GwBUAQACAAYJFhDcDAA1AQAAAA==.Albedö:BAAALgADCgkJCQAAAA==.Alescia:BAEALgADCgcJBgABLgAECgYJFQAEAPwaAA==.Alestormia:BAAALgAECgUJBgAAAA==.Allimental:BAAALgADCgEJAQAAAA==.Allionys:BAAALgAECgYJDwAAAA==.Alorelia:BAAALgADCgUJBQAAAA==.Aloris:BAAALgAECgYJEQAAAA==.',
Am='Amanises:BAAALgAECgYJDQAAAA==.Amilara:BAAALgAECgMJBAAAAA==.',
An='Ananaya:BAAALgAECgIJAwABLgAECgYJFgAFADETAA==.Andinestiri:BAAALgAECgYJDgAAAA==.Andolastrasz:BAAALgADCgEJAQAAAA==.Andy:BAAALgAECgEJAgAAAA==.Aneethea:BAAALgADCgYJBgAAAA==.Antaric:BAAALgAECgMJAwAAAA==.Anyalem:BAAALgAECgEJAQAAAA==.',
Ao='Ao:BAAALgAECgYJBgAAAA==.',
Ap='Apotic:BAAALgAECgcJEQAAAA==.Apuntar:BAAALgADCgQJBgAAAA==.',
Aq='Aquamaree:BAAALgAECgYJCAAAAA==.Aquamyth:BAAALgADCgMJAwAAAA==.Aquilla:BAACLgAFFH8IAAMGAAUJ4AXmHgDcAAAGAAQJPQfmHgDcAAAHAAIJHgJRBQCOAAAuAAQKfxkAAwcACAmhFlcMAAgCAAcACAnlE1cMAAgCAAYABgmBG8ZhAEIBAAAA.',
Ar='Archenea:BAAALgAECgMJAwAAAA==.Archenore:BAABLgAECn8XAAIDAAcJaQdHVQBWAQADAAcJaQdHVQBWAQAAAA==.Arkify:BAAALgADCgYJBgAAAA==.Armadyl:BAAALgAECgEJAQABLgAECgQJBwAIAAAAAA==.Around:BAAALgADCgYJBgAAAA==.',
As='Ashw:BAAALgAECgcJEgAAAA==.Asukka:BAAALgAECgYJCgAAAA==.Asëya:BAAALgAECgMJBQAAAA==.',
At='Atomique:BAACLgAFFH8SAAIJAAQJOhdQCgAvAQAJAAQJOhdQCgAvAQAuAAQKf0EAAgkACAkXH9UGANMCAAkACAkXH9UGANMCAAAA.Attenborough:BAAALgAECgUJBgABLgAECgYJDwAIAAAAAA==.',
Au='Auggie:BAAALgADCgEJAQAAAA==.',
Av='Avesa:BAAALgAECgMJBAAAAA==.Avoidant:BAAALgAECgcJEgAAAA==.',
Ay='Aydir:BAAALgADCgUJBwAAAA==.Aylithe:BAAALgAECgQJBAAAAA==.',
Az='Azanadra:BAAALgAECgQJBwAAAA==.Azazell:BAAALgAECgIJAgAAAA==.Azenea:BAABLgAECn8eAAMKAAgJRQWuDQBZAQAKAAgJRQWuDQBZAQAFAAIJhwGfIAEwAAAAAA==.',
Ba='Baculum:BAAALgAECgYJEgAAAA==.Bacõn:BAAALgAECgQJBAAAAA==.Badmoonrisin:BAAALgAECgMJAwAAAA==.Bainne:BAAALgAECgQJCAAAAA==.Ballzach:BAABLgAECn8VAAILAAYJABvxFgA3AQALAAYJABvxFgA3AQABLgAFFAYJFwAMAAgjAA==.Bazookabob:BAAALgAECgYJEgAAAA==.',
Be='Beangles:BAAALgADCgYJCQAAAA==.Becky:BAAALgADCgkJCgABLgAECgcJEAAIAAAAAA==.Beekyy:BAAALgAECgcJEAAAAA==.Belenova:BAAALgAECgUJBgAAAA==.Bellapearl:BAAALgAECgIJAwAAAA==.Berkyn:BAAALgADCgMJAwAAAA==.',
Bi='Bittydrood:BAAALgADCgcJBwAAAA==.Bittylexis:BAAALgAECgEJAQAAAA==.',
Bl='Blakheart:BAABLgAECn8mAAINAAkJWRT+BQAgAgANAAkJWRT+BQAgAgAAAA==.Bleuopal:BAAALgADCgcJDAAAAA==.Blueaxle:BAABLgAECn8gAAMOAAgJ+hPYEADbAQAOAAgJ+hPYEADbAQAPAAIJpgHOMQFAAAAAAA==.Blur:BAAALgADCgkJEgAAAA==.Bluzzy:BAAALgAECgEJAQABLgADCgcJEAAIAAAAAA==.Blèu:BAAALgAECggJEgAAAA==.',
Bo='Boomdoom:BAAALgAECgQJBAAAAA==.Bootycat:BAAALgADCgcJBwABLgADCgkJCgAIAAAAAA==.Bouffenièce:BAAALgAECgQJBwAAAA==.Boufsy:BAAALgADCgkJEQAAAA==.',
Br='Brakii:BAAALgAECgIJAgAAAA==.Breathe:BAAALgAFFAIJAwAAAA==.Brewballs:BAABLgAECn8cAAIQAAcJWAo+HAAfAQAQAAcJWAo+HAAfAQAAAA==.Brynarra:BAAALgADCgUJBQAAAA==.',
Bu='Bubbletea:BAAALgAECgQJBgAAAA==.Bunnicula:BAABLgAECn8cAAMKAAgJeRhyBwDcAQAKAAcJthtyBwDcAQAFAAUJ2glXTgAFAQAAAA==.',
Bw='Bwanga:BAAALgAECgYJDwAAAA==.',
['Bö']='Böömer:BAAALgAECgIJAwAAAA==.',
Ca='Calmac:BAAALgAFFAIJAgAAAA==.Cameron:BAAALgAECgYJDAAAAA==.Capetonrex:BAAALgAECgEJAQAAAA==.Caythus:BAACLgAFFH8IAAMFAAMJhx41PQCwAAAFAAIJ8xs1PQCwAAARAAEJsCPyEABeAAAuAAQKfxYAAxEABwnhJLoLAAYCABEABQkPJLoLAAYCAAUABQnmIg5RANUBAAAA.',
Ce='Celeana:BAAALgAECgYJDwAAAA==.Celeleron:BAAALgADCgcJBwAAAA==.Celencia:BAAALgAECgUJBQAAAA==.',
Ch='Chadmcguffin:BAABLgAECn8VAAISAAgJoCNrCABSAgASAAgJoCNrCABSAgAAAA==.Chakabad:BAAALgAECgMJBAAAAA==.Chalgar:BAAALgAECgEJAQAAAA==.Chaosblossom:BAAALgADCgYJBwAAAA==.Cheezeballs:BAAALgADCgEJAQABLgAFFAEJAQAIAAAAAA==.Chenahala:BAAALgAECgMJBAAAAA==.Chibeard:BAAALgAECgkJBgAAAA==.Chåni:BAAALgAECgYJEwAAAA==.',
Ci='Ciege:BAABLgAECn8cAAMTAAgJ+hGIEQB/AQATAAgJDQ+IEQB/AQAUAAUJcBJoCAD7AAAAAA==.Cinrah:BAABLgAFFH8FAAIVAAUJjg8JEAA7AQAVAAUJjg8JEAA7AQAAAA==.',
Cl='Cloudwalker:BAAALgADCgkJCwAAAA==.',
Co='Coffeelatte:BAAALgAECgEJAQAAAA==.Complainz:BAAALgADCgYJDwAAAA==.Concinnat:BAAALgADCgUJBQAAAA==.Confessorr:BAAALgADCgYJBgAAAA==.Cosantóir:BAAALgAECgUJBgAAAA==.',
Cr='Crispysock:BAAALgAECgYJCwAAAA==.Croda:BAAALgAECgYJCgAAAA==.Crowe:BAAALgAECgIJAwAAAA==.Cröno:BAAALgAECgYJBgAAAA==.',
Cu='Cursez:BAAALgAECgYJCwABLgAFFAUJFgAWABwgAA==.',
Cy='Cylndra:BAAALgADCgcJBwAAAA==.Cynderr:BAAALgAECgMJAwAAAA==.',
['Cè']='Cèrc:BAAALgAECgIJAwAAAA==.',
Da='Daemian:BAAALgAECgUJBQABLgAECggJFQASAKAjAA==.Dakarba:BAAALgADCgMJBQAAAA==.Daquilla:BAAALgAECgUJBgAAAA==.Dargonit:BAAALgAECgUJAQAAAA==.Darkisis:BAAALgAECgYJCgABLgAECgYJCgAIAAAAAA==.Darknara:BAABLgAECn8mAAIXAAkJUh8wDwBGAgAXAAkJUh8wDwBGAgAAAA==.Darkterror:BAAALgAECgYJCgAAAA==.Darkzy:BAAALgAECgMJAwAAAA==.Dartol:BAAALgAECgIJAgAAAA==.Dasubertakem:BAAALgADCgkJCwAAAA==.Dawni:BAABLgAECn8XAAIJAAYJPCKLBAAqAgAJAAYJPCKLBAAqAgAAAA==.',
De='Deathies:BAAALgADCgIJAgAAAA==.Deathigh:BAAALgADCgUJBgAAAA==.Deathjeff:BAAALgAECggJCwAAAA==.Deathsgates:BAABLgAECn8eAAIFAAcJuiL4HgCdAgAFAAcJuiL4HgCdAgABLgAFFAMJBwANAMMZAA==.Decasia:BAAALgAECgYJDAAAAA==.Deheon:BAAALgADCgQJBgAAAA==.Demoswal:BAAALgADCgEJAgAAAA==.Descendent:BAAALgADCgEJAQAAAA==.Destickament:BAAALgADCgMJAwAAAA==.Detala:BAAALgAECgIJAgAAAA==.Detective:BAAALgADCgkJFwAAAA==.Dethkeela:BAABLgAECn8eAAIXAAcJuBoSHwDNAQAXAAcJuBoSHwDNAQABLgAFFAUJCQAGAMMHAA==.Dewy:BAAALgAECgYJEAAAAA==.',
Dh='Dhfig:BAABLgAECn8eAAIVAAgJzhKxHgB6AQAVAAgJzhKxHgB6AQAAAA==.',
Di='Dimos:BAAALgAECgUJBQAAAA==.Dinoll:BAAALgAECgYJCQAAAA==.Dirtwhistle:BAAALgAECgEJBAAAAA==.',
Do='Dogo:BAAALgADCgcJCwAAAA==.',
Dr='Draconnt:BAAALgAECgMJAwAAAA==.Dragondh:BAABLgAECn8qAAIYAAgJVxd6BgD6AQAYAAgJVxd6BgD6AQAAAA==.Draksvoid:BAAALgAECgUJCwAAAA==.Dranlu:BAAALgAECgEJAQAAAA==.Dranog:BAABLgAECn8gAAMFAAgJKRZRHQDEAQAFAAgJKRZRHQDEAQARAAIJVQXUXQBVAAAAAA==.Draxol:BAAALgADCgcJDQAAAA==.Drazsi:BAAALgAECgYJCgAAAA==.Drovaal:BAAALgADCgEJAQAAAA==.Druidbod:BAAALgAECgUJCAABLgAFFAUJEgABADcdAA==.Drutacular:BAAALgADCgEJAgAAAA==.',
Du='Durga:BAAALgAECgIJBwAAAA==.Dusk:BAAALgADCgEJAQABLgAECgEJAQAIAAAAAA==.',
Dy='Dyromancer:BAAALgADCgYJEwAAAA==.',
['Dé']='Défect:BAABLgAECn8UAAIXAAYJmBHEmwBJAQAXAAYJmBHEmwBJAQAAAA==.',
['Dô']='Dôminic:BAAALgAECgEJAgAAAA==.',
Eb='Ebpindots:BAAALgAECgYJEgAAAA==.',
Eg='Eggegg:BAAALgAECgMJBgABLgAECggJJQAGADwbAA==.',
El='Eleanne:BAAALgAECgYJDwAAAA==.Elfrida:BAAALgADCgIJBAAAAA==.Ellebasi:BAABLgAECn8oAAISAAcJ9BLRFwBYAQASAAcJ9BLRFwBYAQAAAA==.',
Em='Emarosa:BAAALgADCgcJBwABLgAECgcJGQAMAE8YAA==.Emorya:BAAALgAECgcJCwAAAA==.',
En='Enazen:BAAALgAECgYJCgAAAA==.Enchantz:BAAALgADCgYJBgAAAA==.Endzela:BAAALgADCgUJBQAAAA==.Enky:BAAALgADCgcJCAAAAA==.',
Er='Erlas:BAAALgADCgkJJAAAAA==.Errol:BAAALgADCgUJBQAAAA==.Erui:BAAALgAECgMJBAAAAA==.',
Ev='Evilrayne:BAABLgAECn8fAAIZAAgJHRYjKADEAQAZAAgJHRYjKADEAQAAAA==.Evoxus:BAAALgAECgMJAwAAAA==.',
Fa='Fatherfingur:BAAALgAECgQJCQAAAA==.Fauxpas:BAAALgAECgYJDgAAAA==.Fawnzy:BAAALgAECgMJAwAAAA==.',
Fe='Fearoshimâ:BAAALgADCgUJBQAAAA==.Feldommy:BAAALgAECgUJBQAAAA==.Feloak:BAABLgAECn8jAAIaAAgJGBCQBgBfAQAaAAgJGBCQBgBfAQAAAA==.Felonie:BAAALgADCgIJAwAAAA==.Fenyxfall:BAAALgAECgMJAwAAAA==.Feredir:BAAALgAECgMJBQAAAA==.Ferzod:BAAALgADCgEJAQABLgAECgcJEwAIAAAAAA==.',
Fi='Fieryfang:BAABLgAECn8kAAIDAAgJrSCEBAB6AgADAAgJrSCEBAB6AgAAAA==.Fireshader:BAAALgADCgEJAQAAAA==.Fistandilius:BAAALgAECgYJDwAAAA==.Fistman:BAABLgAECn8UAAMbAAgJZiFpFQBAAgAbAAgJZiFpFQBAAgAQAAIJWARUZgA5AAAAAA==.',
Fl='Flashsomhash:BAAALgAECgEJAQAAAA==.Flyleaf:BAABLgAECn8YAAITAAgJTRJGDwCaAQATAAgJTRJGDwCaAQAAAA==.',
Fo='Foshnu:BAABLgAECn8cAAMcAAcJ+A3PKwAXAQAcAAcJ+A3PKwAXAQAWAAUJKAdNMAC7AAAAAA==.',
Fr='Fraks:BAAALgADCgMJAwAAAA==.Frozandrov:BAAALgAECgQJDgAAAA==.',
Fu='Fujie:BAABLgAECn8aAAIYAAgJox/0CQDDAgAYAAgJox/0CQDDAgAAAA==.Fujï:BAAALgAECgYJBgAAAA==.Furryfury:BAACLgAFFH8GAAIQAAMJuAjdEgC2AAAQAAMJuAjdEgC2AAAuAAQKfx8AAxAACAkCEFwcAB4BABAACAkCEFwcAB4BABsABQnaCY5OANgAAAAA.Fuzzyewok:BAAALgAECggJEAAAAA==.',
['Fë']='Fëlisha:BAAALgADCgQJBAAAAA==.',
Ga='Gaazmataaz:BAAALgAECgMJAwAAAA==.Galadir:BAAALgADCgEJAQAAAA==.Garag:BAAALgADCgUJBQAAAA==.Garlstedt:BAAALgAECgUJCAAAAA==.Gawdzirra:BAAALgADCgIJAgAAAA==.',
Ge='Genstein:BAAALgADCgIJAgAAAA==.George:BAAALgAECgYJEAAAAA==.',
Gh='Ghulrokk:BAAALgAECgYJDAAAAA==.',
Gi='Gilidan:BAAALgAECgIJAgAAAA==.Gizmo:BAAALgAECgEJAQAAAA==.',
Gl='Glenndragon:BAAALgAECgYJDAAAAA==.Gluum:BAAALgAECgMJBAAAAA==.',
Go='Gohibasi:BAAALgAECgMJBQAAAA==.Gossamerfeet:BAAALgAECgYJDQAAAA==.Gotalian:BAABLgAECn8eAAIPAAcJiAmXRgA2AQAPAAcJiAmXRgA2AQAAAA==.',
Gr='Graceosilver:BAABLgAECn8WAAIdAAYJvwEEEgClAAAdAAYJvwEEEgClAAAAAA==.Grajademoh:BAAALgADCgcJDAAAAA==.Grajashadow:BAAALgAECgYJDAAAAA==.Gregnor:BAABLgAECn8jAAMeAAgJnRqHAgBEAgAeAAgJGhqHAgBEAgAfAAEJOAokIAAqAAAAAA==.Grim:BAABLgAECn8dAAIXAAgJJRyHOQBRAgAXAAgJJRyHOQBRAgAAAA==.Grover:BAAALgAECgcJEAAAAA==.Grozztrak:BAAALgADCgQJBAAAAA==.Grumpybun:BAAALgADCgYJCwAAAA==.Grumpybunbun:BAABLgAECn8UAAIEAAgJWBXfJgC2AQAEAAgJWBXfJgC2AQAAAA==.',
Gu='Guldrosi:BAABLgAECn8jAAQKAAgJzBnrAAAwAgAKAAgJkBjrAAAwAgAFAAcJ7RXtKACKAQARAAQJPBEORAClAAAAAA==.',
Gy='Gyat:BAAALgAECgYJEAAAAA==.',
['Gå']='Gårrus:BAABLgAECn8YAAIGAAgJfCEMBgCWAgAGAAgJfCEMBgCWAgAAAA==.',
Ha='Haarl:BAAALgAECgMJAwAAAA==.Hairypotter:BAAALgADCgMJAwAAAA==.Hallie:BAABLgAECn8WAAIZAAYJjwoeZQAQAQAZAAYJjwoeZQAQAQAAAA==.Hargoose:BAAALgAECgEJAgAAAA==.Harlu:BAABLgAECn8cAAIWAAcJhwa+JAD8AAAWAAcJhwa+JAD8AAAAAA==.Hartbroke:BAABLgAECn8cAAIPAAcJxhlvIADHAQAPAAcJxhlvIADHAQAAAA==.',
He='Helbourne:BAAALgAECgYJDwAAAA==.Hextraspicy:BAAALgADCgQJBAAAAA==.',
Hi='Hideyoshi:BAAALgADCgcJHgAAAA==.Hijjiup:BAAALgAECgEJAQAAAA==.Hildah:BAAALgAECgIJBQAAAA==.',
Ho='Holliestraza:BAABLgAECn8cAAIcAAgJKBPZPwCBAQAcAAgJKBPZPwCBAQAAAA==.Holyadrian:BAAALgAECgIJAgAAAA==.Holyfugde:BAAALgADCgQJBQAAAA==.Holyman:BAAALgADCgMJAwAAAA==.',
Hw='Hwanwok:BAAALgAECgYJEgAAAA==.',
Hy='Hyacynth:BAAALgADCgYJBQAAAA==.Hypermage:BAAALgADCgcJBwAAAA==.',
['Hä']='Härbinger:BAAALgAECgUJCQAAAA==.',
Ic='Ic:BAAALgAECgIJAgAAAA==.',
Ig='Ignited:BAAALgADCgYJBwAAAA==.',
Im='Imadragon:BAABLgAECn8fAAIUAAgJ2hFgAwC1AQAUAAgJ2hFgAwC1AQAAAA==.Imdeadguy:BAABLgAECn8cAAIgAAgJdSPzAQCeAgAgAAgJdSPzAQCeAgAAAA==.',
In='Innalowda:BAAALgADCgcJEQABLgAECggJFQASAKAjAA==.',
Ir='Ironhelmhtr:BAAALgAECgMJCAAAAA==.Irënicus:BAAALgADCgcJCgAAAA==.',
Is='Isendra:BAAALgAECgYJDgAAAA==.Istian:BAAALgADCgIJAgAAAA==.',
It='Itachi:BAAALgADCgcJGAAAAA==.',
Ja='Jabtak:BAAALgAECgMJAwAAAA==.Jaded:BAAALgAECgEJAQAAAA==.Janinoo:BAAALgAECgYJDgAAAA==.Jararth:BAAALgAECgEJBAAAAA==.Jazlee:BAABLgAECn8XAAIgAAcJ3B0WBwDTAQAgAAcJ3B0WBwDTAQAAAA==.',
Je='Jeggana:BAAALgAECgEJAQAAAA==.',
Ji='Jinathy:BAABLgAECn8dAAIPAAgJJBIqKACiAQAPAAgJJBIqKACiAQAAAA==.Jinnite:BAAALgADCgEJAQAAAA==.',
Jo='Jolyñ:BAABLgAECn8eAAIEAAgJVBEQDgDBAQAEAAgJVBEQDgDBAQABLgAECggJGwAHANYLAA==.',
Ju='Jualygosa:BAABLgAECn8iAAIZAAgJsBftHwDtAQAZAAgJsBftHwDtAQAAAA==.Judgementall:BAAALgAECgcJDgAAAA==.Juomancito:BAABLgAECn8aAAIBAAcJfSVSBADmAgABAAcJfSVSBADmAgAAAA==.Justac:BAAALgAECgMJBAABLgAECgQJDgAIAAAAAA==.Justgotbis:BAAALgAECgQJBAAAAA==.',
['Já']='Jáß:BAAALgAFFAMJAwAAAA==.',
['Jä']='Jäb:BAAALgADCgcJBwAAAA==.',
Ka='Kaddrix:BAAALgAECgcJDwAAAA==.Kaldonor:BAABLgAECn8lAAIhAAgJChQqAwCmAQAhAAgJChQqAwCmAQAAAA==.Kalenia:BAABLgAECn8kAAIcAAgJVyJzBQCdAgAcAAgJVyJzBQCdAgAAAA==.Kalvayre:BAABLgAECn8hAAIXAAgJORQPJQCsAQAXAAgJORQPJQCsAQAAAA==.Kanzoorb:BAAALgAECgUJBQAAAA==.Karpana:BAEBLgAECn8gAAMSAAYJvxsgCACRAQASAAYJvxsgCACRAQAPAAUJTg74ZADoAAAAAA==.Kashir:BAABLgAECn8WAAQUAAYJdSAjCwAoAgAUAAYJdSAjCwAoAgATAAMJ/RiRTgCUAAAJAAEJRAwqSQAxAAAAAA==.Katamoonfang:BAAALgADCgkJEQAAAA==.Katastrophe:BAAALgAECgYJCwAAAA==.Katsumi:BAAALgAECgQJBgAAAA==.Kaythewitch:BAAALgAECgUJBQAAAA==.Kazimirah:BAAALgADCgYJDwAAAA==.Kazrael:BAAALgAECgEJAgAAAA==.',
Ke='Keekat:BAAALgADCgkJGQAAAA==.Kegstands:BAAALgAECgMJBQABLgAECgUJBQAIAAAAAA==.Keloha:BAAALgAECgUJBQAAAA==.Kerprage:BAAALgAECgQJCgAAAA==.Kerpredem:BAAALgADCgcJEgAAAA==.Kerpspells:BAAALgADCgcJEAAAAA==.',
Kh='Khariaa:BAAALgADCgcJBwAAAA==.Khoravi:BAABLgAECn8UAAITAAgJ3BbUDAC7AQATAAgJ3BbUDAC7AQAAAA==.',
Ki='Kikora:BAAALgADCgUJBQAAAA==.Kitaska:BAAALgADCgQJAwABLgAECgcJGwAOAFsQAA==.Kittykitty:BAABLgAECn8fAAMcAAgJLRmMHAA1AgAcAAgJLRmMHAA1AgAdAAQJExO4GwAPAQAAAA==.',
Ko='Kolzane:BAACLgAFFH8QAAIGAAYJjiIbAAANAgAGAAYJjiIbAAANAgAuAAQKfxcAAwYACAknJHcGACYDAAYACAknJHcGACYDACIABAnYEBhgAMAAAAAA.Kongfu:BAAALgAECgYJEAAAAA==.Korravah:BAAALgAECgQJBwAAAA==.Koyuki:BAAALgAECgMJAwAAAA==.',
Kr='Kramps:BAAALgAECgQJBgAAAA==.Krandel:BAAALgAECgMJAwAAAA==.Kronan:BAAALgADCgIJAgAAAA==.',
Ku='Kuulas:BAABLgAECn8aAAIGAAgJdBseDwAfAgAGAAgJdBseDwAfAgAAAA==.',
Ky='Kyth:BAABLgAECn8iAAISAAgJ9RETCgBkAQASAAgJ9RETCgBkAQAAAA==.Kythlock:BAAALgADCgkJEwABLgAECggJIgASAPURAA==.Kythtok:BAAALgAECgYJEwABLgAECggJIgASAPURAA==.',
['Kø']='Køda:BAABLgAECn8eAAMBAAgJVCKtHgBKAgABAAgJVCKtHgBKAgAjAAYJxAyuIAD4AAAAAA==.',
La='Ladyhawk:BAAALgADCgYJCQAAAA==.Lazerbird:BAAALgADCgUJBgAAAA==.',
Le='Leggy:BAAALgAECgIJAgAAAA==.Lela:BAAALgADCgEJAQAAAA==.',
Li='Life:BAAALgADCgYJCQAAAA==.Lifebloomer:BAAALgAECgQJAwABLgAFFAYJFwAMAAgjAA==.Lightnup:BAAALgAECgkJDAAAAA==.Liralyn:BAAALgADCgcJDgAAAA==.Litharaldra:BAAALgADCgYJBgAAAA==.Littlehell:BAACLgAFFH8FAAIcAAMJrxN6DgD2AAAcAAMJrxN6DgD2AAAuAAQKfxcAAhwACAkfG8AVAGcCABwACAkfG8AVAGcCAAAA.',
Lo='Lokaroki:BAAALgAECgQJBwAAAA==.Lothbrokk:BAAALgAECgUJBgAAAA==.Lothrik:BAAALgADCgIJAgAAAA==.',
Lu='Lucaafer:BAABLgAECn8hAAIZAAgJziArMwCmAgAZAAgJziArMwCmAgAAAA==.Luda:BAAALgAECgcJEQAAAA==.',
Ly='Lyssandria:BAABLgAECn8lAAIZAAgJiAn4RgBZAQAZAAgJiAn4RgBZAQAAAA==.Lyzoldas:BAABLgAECn8XAAIPAAYJ0BnoOABhAQAPAAYJ0BnoOABhAQAAAA==.',
['Lí']='Lília:BAAALgAECgEJAgAAAA==.',
['Lö']='Löwryder:BAAALgAECgYJEgAAAA==.',
Ma='Maddera:BAAALgAECgUJCAAAAA==.Madmurdock:BAAALgAECgcJEwAAAA==.Madness:BAAALgAECgUJCAAAAA==.Maemura:BAAALgAECgMJBQAAAA==.Magîkarp:BAAALgADCgYJBwAAAA==.Mahll:BAAALgADCgUJBQAAAA==.Maiki:BAAALgAECgEJAQAAAA==.Malach:BAAALgAECgcJAwAAAA==.Malchromatus:BAABLgAECn8YAAMJAAgJjRT4BAAUAgAJAAgJjRT4BAAUAgAUAAQJKwdxLQCvAAAAAA==.Marcosio:BAAALgAECgEJAQAAAA==.Marsala:BAAALgAECgYJDwAAAA==.',
Mb='Mbop:BAAALgAECgQJBAAAAA==.',
Mc='Mcchud:BAAALgAECgEJAQAAAA==.',
Me='Meandragon:BAAALgADCgcJBwAAAA==.Meatyfajita:BAABLgAECn8bAAIOAAgJoyZwAAB8AwAOAAgJoyZwAAB8AwAAAA==.Mechabrew:BAABLgAECn8VAAIkAAYJ2Q7LIAD9AAAkAAYJ2Q7LIAD9AAAAAA==.Medousa:BAAALgAECgMJAwAAAA==.Megaera:BAAALgAECgMJBQAAAA==.Meiko:BAAALgAECgEJAQABLgAECgcJGQAMAE8YAA==.Meladie:BAAALgAECgEJAgAAAA==.Meladrus:BAAALgADCgEJAQAAAA==.Mellene:BAAALgADCgkJFgAAAA==.Memedecay:BAABLgAECn8hAAMXAAgJZSCHFgAGAgAXAAgJZSCHFgAGAgAMAAEJnRkdQwA9AAAAAA==.Mememalefic:BAAALgAECgcJCAABLgAECggJIQAXAGUgAA==.Mericck:BAAALgADCgMJAwAAAA==.Merlinthos:BAAALgADCgUJBQABLgAECggJIQANABIUAA==.Metaljack:BAABLgAECn8jAAIZAAgJ8iQWBQDqAgAZAAgJ8iQWBQDqAgAAAA==.',
Mi='Miasma:BAAALgAECgYJDgABLgAECgMJDgAIAAAAAA==.Mikeyboi:BAAALgADCgEJAQAAAA==.Milanesa:BAABLgAECn8ZAAIgAAgJ+hQqEgDlAQAgAAgJ+hQqEgDlAQAAAA==.Mingyue:BAAALgADCgIJBAABLgAECggJKwATAIIWAA==.Mishaweha:BAAALgAECgYJBQAAAA==.Mithrandir:BAAALgAECgYJCgAAAA==.Mitos:BAABLgAECn8kAAIPAAgJ5RDkLACOAQAPAAgJ5RDkLACOAQAAAA==.Miyasabi:BAAALgADCgYJBgAAAA==.Mizzet:BAAALgAECgEJAQAAAA==.',
Mo='Modar:BAABLgAECn8YAAIcAAgJPxwcCQBYAgAcAAgJPxwcCQBYAgAAAA==.Monkas:BAAALgADCgcJCQAAAA==.Moonpaw:BAAALgAECgEJAQAAAA==.Moonrid:BAAALgADCgcJHAAAAA==.Moonshayd:BAAALgAECgYJDgAAAA==.Moreann:BAAALgADCgcJDQAAAA==.Morkepo:BAAALgADCgEJAQAAAA==.Morphëus:BAAALgAECgYJDwAAAA==.',
Mu='Muggy:BAAALgADCgIJAgABLgAFFAQJDAAXAA0kAA==.Muha:BAAALgAECgUJBQAAAA==.Mushi:BAAALgADCgkJEgAAAA==.Mustardplug:BAAALgADCgEJAQAAAA==.Muzan:BAAALgAECgQJBAAAAA==.Muzzin:BAAALgADCgEJAQAAAA==.',
['Må']='Måddløck:BAAALgAECgIJAwAAAA==.',
Ne='Needslotion:BAAALgAECgYJDwAAAA==.Neiidra:BAAALgAECgYJDQAAAA==.Nepheleah:BAACLgAFFH8FAAIPAAMJpwlfJQDXAAAPAAMJpwlfJQDXAAAuAAQKfxwAAg8ACAmSISwQAA4DAA8ACAmSISwQAA4DAAAA.Nesmoth:BAABLgAECn8dAAIMAAcJ4iMzBgDVAgAMAAcJ4iMzBgDVAgAAAA==.Ness:BAAALgAECgIJAwAAAA==.',
Ni='Niiborracho:BAABLgAECn8hAAMbAAgJGg+fJACxAQAbAAgJGg+fJACxAQAQAAgJhwg/GwAoAQAAAA==.Niiko:BAAALgAECgIJBAAAAA==.Niisera:BAAALgADCgQJBwAAAA==.',
No='Norntrox:BAABLgAECn8cAAMVAAcJGxuYFQC8AQAVAAcJGxuYFQC8AQAaAAEJAAC0KQA9AAAAAA==.Nosåj:BAAALgADCgQJBQAAAA==.Nothannah:BAAALgADCgEJAQAAAA==.',
Ns='Nsshaman:BAAALgADCgMJAwAAAA==.',
Ny='Nylaria:BAAALgADCgUJBQAAAA==.Nyxari:BAAALgAECgYJDwAAAA==.',
Ob='Obscuría:BAAALgADCgYJCgAAAA==.',
Od='Odrik:BAAALgADCgQJCAAAAA==.',
Ol='Oleana:BAAALgAECgQJBAAAAA==.Oleia:BAAALgAECgUJBwAAAA==.',
On='Onatha:BAAALgADCgkJGgAAAA==.Onaw:BAAALgAECgQJCgAAAA==.',
Op='Ops:BAAALgAECgQJBAAAAA==.',
Or='Orctism:BAAALgADCgIJAgAAAA==.',
Ow='Owlsonatotem:BAABLgAECn8bAAIcAAgJxBeaGgCOAQAcAAgJxBeaGgCOAQAAAA==.',
Ox='Oxymage:BAAALgAECgEJAgAAAA==.',
Pa='Pakno:BAAALgAECggJEAAAAA==.Paletia:BAAALgAECgYJBgAAAA==.Pamely:BAABLgAECn8UAAIPAAcJABd9OABiAQAPAAcJABd9OABiAQAAAA==.Pankler:BAAALgADCgkJCwAAAA==.',
Pe='Petethelock:BAAALgAECgIJAgAAAA==.',
Ph='Pharmit:BAABLgAECn8cAAQKAAgJGiQ3AADXAgAKAAgJ4yI3AADXAgAFAAYJ0yLUPQAVAgARAAIJ1B5sPADDAAAAAA==.Phayte:BAAALgADCgkJEAAAAA==.Photon:BAAALgADCgYJBQAAAA==.Phrock:BAAALgADCgEJAgAAAA==.',
Pl='Pletua:BAABLgAECn8WAAIlAAcJ2B32FQBfAgAlAAcJ2B32FQBfAgAAAA==.',
Po='Porazdir:BAAALgAECgUJBgAAAA==.Porcelayna:BAAALgAECgEJAQABLgAECgcJHAAcAPgNAA==.',
Pr='Primoris:BAAALgADCgUJBQAAAA==.',
Ps='Psion:BAAALgADCgYJBgAAAA==.',
Pu='Puds:BAAALgADCgMJAwAAAA==.',
['På']='Påimon:BAAALgADCgIJAgAAAA==.',
['Pö']='Pöê:BAAALgAECgQJBQAAAA==.',
Qu='Quintin:BAAALgAECgYJBwAAAA==.',
Ra='Racavis:BAAALgADCgcJCAAAAA==.Raenisa:BAEALgADCgQJBwABLgAECgYJFQAEAPwaAA==.Ragp:BAAALgAECgMJAwAAAA==.Rainydevil:BAAALgADCgcJDgAAAA==.Rainydevils:BAAALgADCgIJAgAAAA==.Rainymdevil:BAAALgADCgUJBQAAAA==.Rainyxdvl:BAAALgAECgEJAQAAAA==.Ramasey:BAAALgAECgYJEAAAAA==.Rasriann:BAAALgAECgQJBAAAAA==.Rawrlordz:BAAALgAECgYJDAAAAA==.',
Re='Reaces:BAAALgADCgEJAQAAAA==.Real:BAABLgAECn8cAAIZAAgJSx2vFgAnAgAZAAgJSx2vFgAnAgABLgAECgQJBAAIAAAAAA==.Reda:BAAALgADCgcJBwAAAA==.Reeality:BAAALgAECgQJBAAAAA==.Reelio:BAAALgAECgQJCAAAAA==.Reikio:BAAALgAECgMJAwAAAA==.Rennala:BAAALgAECgcJBwAAAA==.Repeal:BAAALgAECgQJBAAAAA==.Reptar:BAAALgADCgYJBgABLgAECgUJBQAIAAAAAA==.Retbet:BAAALgAECgYJCwAAAA==.Revoke:BAABLgAECn8aAAIPAAgJlgyGLgCHAQAPAAgJlgyGLgCHAQAAAA==.Reyanne:BAEBLgAECn8VAAIEAAYJ/Bp1EgCHAQAEAAYJ/Bp1EgCHAQAAAA==.',
Ro='Rockfish:BAAALgAECgEJAQAAAA==.Roofio:BAAALgADCgEJAQABLgAECggJFQASAKAjAA==.',
Ru='Rubiroo:BAAALgADCgEJAQAAAA==.Runebellwolf:BAAALgADCgcJCgAAAA==.Ruroni:BAAALgADCgUJBQAAAA==.',
Ry='Ryniel:BAABLgAECn8UAAIGAAYJyBZsKgBrAQAGAAYJyBZsKgBrAQAAAA==.Rynitty:BAAALgADCgUJBQABLgAECgcJDQAIAAAAAA==.Rynthia:BAAALgADCgkJCQAAAA==.',
['Ré']='Réira:BAAALgADCgkJEQABLgAECggJKwATAIIWAA==.',
['Rï']='Rïptide:BAAALgAECgIJAwAAAA==.',
Sa='Sabrinalee:BAAALgADCgcJBwAAAA==.Sacremierde:BAAALgAECgIJAwAAAA==.Sagah:BAAALgAECgYJEQAAAA==.Saintdeamon:BAABLgAECn8dAAMBAAcJoxe+QQCaAQABAAcJoxe+QQCaAQAjAAYJXA+oHAAWAQAAAA==.Sanasta:BAABLgAECn8WAAMFAAYJMROoOgBDAQAFAAYJmxGoOgBDAQARAAIJEBmUHABLAAAAAA==.Sandspur:BAAALgAECgEJAQAAAA==.Sanielin:BAABLgAECn8aAAIkAAcJZCD4CwDJAQAkAAcJZCD4CwDJAQAAAA==.Saphìr:BAAALgAECgQJCQAAAA==.Saramoon:BAABLgAECn8bAAMlAAYJxgijGAAOAQAlAAYJxgijGAAOAQANAAQJhgLSFQCdAAAAAA==.Sarda:BAEALgAECgUJCgAAAA==.Sargent:BAAALgAECgUJCQAAAA==.Saryaa:BAAALgAECgYJCwAAAA==.Sashchi:BAABLgAECn8VAAIbAAgJYBF3FwAtAQAbAAgJYBF3FwAtAQAAAA==.Satheronys:BAAALgAECgEJAQABLgAECgMJAwAIAAAAAA==.',
Sc='Schade:BAAALgAECgQJCQAAAA==.Schrödinger:BAAALgAECgMJAwAAAA==.',
Se='Searen:BAAALgADCgMJAwAAAA==.Sehmet:BAAALgAECgEJAgAAAA==.Seiso:BAABLgAFFH8FAAICAAUJjgmNBQApAQACAAUJjgmNBQApAQAAAA==.Seliria:BAABLgAECn8jAAIPAAgJ2wkwNwBnAQAPAAgJ2wkwNwBnAQAAAA==.Sephaman:BAAALgAECgEJAQAAAA==.Seprogue:BAAALgADCgcJCgAAAA==.',
Sh='Shadyn:BAAALgAECgEJAQAAAA==.Shadówz:BAAALgADCgEJAQAAAA==.Sheepstealer:BAAALgADCgQJAwAAAA==.Shiftace:BAAALgADCgkJDAAAAA==.Shiryo:BAAALgAECgMJCQAAAA==.Shockwater:BAAALgAECgUJBwAAAA==.Shotfoot:BAAALgAECgMJAwAAAA==.Shwang:BAAALgAECgYJEQAAAA==.',
Si='Siclock:BAAALgADCgUJBQAAAA==.Sikkerp:BAAALgADCgMJBAAAAA==.Silentio:BAABLgAECn8hAAINAAgJEhS8BACGAQANAAgJEhS8BACGAQAAAA==.Silihunt:BAAALgADCgMJAwAAAA==.Siliçå:BAAALgADCgYJCQAAAA==.Sinamun:BAABLgAECn8bAAIOAAcJWxC5QwBpAQAOAAcJWxC5QwBpAQAAAA==.Sinandtonic:BAAALgADCgQJBAAAAA==.Sinofwrath:BAABLgAECn8YAAIVAAgJqSJtAwDAAgAVAAgJqSJtAwDAAgAAAA==.Sinsidious:BAAALgAECgYJDwAAAA==.Siwin:BAACLgAFFH8SAAIBAAUJNx09BQCyAQABAAUJNx09BQCyAQAuAAQKfx0AAwEACAm3JM8IAAIDAAEACAm3JM8IAAIDACMAAgnuFQ55AEEAAAAA.',
Sk='Skarlett:BAAALgAECgQJBQAAAA==.Skiller:BAAALgADCgYJDAAAAA==.Skinobi:BAAALgAECgQJBQAAAA==.Skysqueezer:BAAALgAECgYJCgAAAA==.',
Sl='Slapchóp:BAABLgAECn8UAAIWAAgJrhoTCwDpAQAWAAgJrhoTCwDpAQAAAA==.',
Sm='Smoko:BAABLgAECn8XAAIHAAcJkRz0DQDoAQAHAAcJkRz0DQDoAQAAAA==.',
Sn='Snorlax:BAAALgAECgIJAgABLgAECgYJEgAIAAAAAA==.Snowxstorm:BAABLgAECn8iAAIMAAgJbCE+AgBPAgAMAAgJbCE+AgBPAgAAAA==.',
So='Sobieski:BAAALgAECgkJCQAAAA==.Solae:BAAALgADCgkJDwAAAA==.Solrond:BAAALgAECgQJCAAAAA==.Somemageguy:BAAALgAECgEJAQAAAA==.Sosimmage:BAAALgAECggJEwABLgAFFAQJCgAZAFobAA==.Souldecay:BAABLgAECn8iAAIXAAgJkA5BKACcAQAXAAgJkA5BKACcAQAAAA==.Soultender:BAAALgADCgIJAgAAAA==.',
Sp='Spekktrum:BAAALgAECgEJAQAAAA==.',
Sq='Squidacles:BAAALgADCgEJAQAAAA==.Squirrly:BAAALgAECgEJAQAAAA==.',
St='Stainedone:BAAALgAECgUJCQAAAA==.Staqua:BAAALgAECgEJAgAAAA==.Stateomatter:BAAALgAECgYJDgAAAA==.Stevenflowe:BAAALgADCgcJCAAAAA==.Stoneslacher:BAAALgADCgIJBAAAAA==.Streamesance:BAAALgAECgYJCAAAAA==.',
Su='Suanni:BAABLgAECn8rAAQTAAgJghbrCQDtAQATAAgJghbrCQDtAQAUAAIJSAhoDwBcAAAJAAEJoQD0TwAPAAAAAA==.Summdari:BAABLgAECn8fAAIaAAgJKhjgBgAfAgAaAAgJKhjgBgAfAgAAAA==.Summrot:BAAALgAECgYJDgAAAA==.Sunfrostt:BAAALgAECgQJBgAAAA==.Supplock:BAAALgAECgYJDwAAAA==.Suromeme:BAAALgAECgQJBAABLgAECggJHwAfAJoeAA==.',
Sw='Swizzler:BAAALgAECgQJBgAAAA==.',
Sy='Sylvalesta:BAAALgAECgEJAgAAAA==.',
Ta='Taedro:BAAALgADCgcJEwAAAA==.Taichung:BAAALgAECgUJAQAAAA==.Talyon:BAAALgAECgYJCgAAAA==.Tayge:BAAALgADCgEJAQAAAA==.',
Te='Teafrog:BAAALgADCgcJBwAAAA==.Tekeelà:BAAALgAECgQJDQABLgAFFAUJCQAGAMMHAA==.Tenebris:BAABLgAECn8XAAIPAAYJjRiZgwBzAQAPAAYJjRiZgwBzAQAAAA==.Terrorbyte:BAAALgADCgYJBgAAAA==.Terrorhungry:BAAALgAECgIJAwAAAA==.',
Th='Thalstrasza:BAAALgAECgQJEAAAAA==.Thalör:BAABLgAECn8bAAIjAAgJMha7HAAbAgAjAAgJMha7HAAbAgAAAA==.The:BAABLgAECn8WAAIhAAYJbhrBAwCFAQAhAAYJbhrBAwCFAQAAAA==.Thedevilsown:BAAALgADCgYJDgAAAA==.Thedrizzle:BAABLgAECn8bAAIZAAgJWx0mFgArAgAZAAgJWx0mFgArAgAAAA==.Thinkwizzle:BAAALgADCgYJBwAAAA==.Thunderthïgh:BAAALgAECgIJAwAAAA==.Thundrfury:BAAALgAECgMJAwAAAA==.',
Ti='Tibalt:BAAALgAFFAEJAQAAAA==.Tibbles:BAAALgAECgEJAgAAAA==.Tipsynips:BAAALgADCgQJBAAAAA==.',
Tk='Tkla:BAAALgADCgIJAgAAAA==.',
Tl='Tlanimass:BAABLgAECn8bAAIgAAcJfhA7DgA7AQAgAAcJfhA7DgA7AQAAAA==.',
To='Tommytubstub:BAAALgAECgQJBQAAAA==.Tomstrasza:BAAALgAECgQJBgAAAA==.Tormen:BAABLgAECn8ZAAImAAgJDw+JMgBSAQAmAAgJDw+JMgBSAQAAAA==.Totemforge:BAAALgAECgYJEAAAAA==.',
Tr='Trapdaddy:BAAALgADCgYJBgAAAA==.Traq:BAAALgADCgQJBAAAAA==.Treeko:BAAALgAECgYJDAABLgAFFAQJDAAFAC8JAA==.Treston:BAAALgAECgEJAgAAAA==.Treyna:BAAALgADCgQJAgAAAA==.',
Ts='Tsyubaki:BAAALgAECggJDQAAAA==.',
Tw='Twistdmister:BAAALgADCgUJBAAAAA==.',
Ty='Tydes:BAAALgAECgUJCQAAAA==.',
Un='Unholybrotha:BAABLgAECn8ZAAIMAAcJTxiqCQB7AQAMAAcJTxiqCQB7AQAAAA==.Unslayable:BAAALgADCgkJFQAAAA==.Unwell:BAABLgAECn8aAAQcAAcJyxoUMwDvAAAcAAQJfRMUMwDvAAAWAAcJpxCUKADlAAAdAAQJahEGHwDgAAAAAA==.',
Ur='Urotherdaddy:BAAALgAECgMJAwABLgAECgYJEQAIAAAAAA==.',
Uz='Uzzy:BAAALgAECgMJBAAAAA==.',
Va='Vaevictis:BAAALgAECgQJBwAAAA==.Valandir:BAAALgADCgIJAgAAAA==.Valenith:BAABLgAECn8ZAAIHAAcJqRjCCwCjAQAHAAcJqRjCCwCjAQAAAA==.Valtora:BAAALgAECgQJCQAAAA==.Vartic:BAABLgAECn8UAAIJAAYJ8Q81DABGAQAJAAYJ8Q81DABGAQAAAA==.Vassago:BAAALgAECgUJCAAAAA==.',
Ve='Veliry:BAAALgADCgEJAQAAAA==.Vellarieline:BAABLgAECn8eAAIVAAcJKh06HwB4AQAVAAcJKh06HwB4AQAAAA==.Velyssara:BAAALgAECgMJBAAAAA==.Ventor:BAABLgAECn8VAAIjAAcJ5iGeGABDAgAjAAcJ5iGeGABDAgABLgAECgkJHwAiANwbAA==.Verbera:BAABLgAECn8bAAIBAAgJBSIRAwAPAwABAAgJBSIRAwAPAwAAAA==.',
Vi='Viduus:BAAALgAECgIJAwAAAA==.Virdeserti:BAABLgAECn8hAAIEAAkJ7xyNAQAWAwAEAAkJ7xyNAQAWAwAAAA==.Visage:BAAALgADCgkJCQAAAA==.Vixolot:BAAALgAECgIJAgAAAA==.',
Vl='Vlartank:BAAALgAECgkJBgAAAA==.',
Vm='Vmaoh:BAAALgADCggJCwAAAA==.',
Vo='Voidwithin:BAAALgAECgYJCgAAAA==.',
Vu='Vulpies:BAAALgADCgYJBgAAAA==.',
Vy='Vyketh:BAAALgAECgEJAQABLgAECgYJBgAIAAAAAA==.',
Wa='Wandiferous:BAAALgAECgYJDAAAAA==.',
We='Weezak:BAAALgADCgUJBQAAAA==.',
Wi='Wickedsmaht:BAACLgAFFH8MAAIFAAQJLwlpIAAgAQAFAAQJLwlpIAAgAQAuAAQKfyIABBEACQlnFloWAJcBABEABwlYEloWAJcBAAUABwkkFbRDACYBAAoAAQnOGYctAEMAAAAA.Widowghast:BAAALgADCgQJBAAAAA==.Willowísp:BAABLgAECn8eAAIkAAcJHRDyFwBAAQAkAAcJHRDyFwBAAQAAAA==.Winsfer:BAAALgAECgYJDQAAAA==.',
Wn='Wnchester:BAAALgADCgIJAgAAAA==.',
Wo='Woggers:BAAALgAECgYJBwAAAA==.',
Wr='Wrathion:BAAALgAFFAEJAQAAAA==.',
Wu='Wulfenstein:BAAALgADCgUJBQAAAA==.',
Wy='Wyvernman:BAAALgAECgYJBgAAAA==.Wywy:BAAALgADCgYJBgAAAA==.',
['Wí']='Wíppy:BAAALgAECgQJBAAAAA==.',
Xa='Xalthea:BAABLgAECn8bAAQVAAgJgBO/VQCiAQAVAAgJRBO/VQCiAQAaAAUJmw9uDADNAAAYAAEJ+BHUbgA2AAAAAA==.Xanda:BAACLgAFFH8HAAMNAAMJwxliAgAcAQANAAMJwxliAgAcAQAlAAEJxwHjGwBMAAAuAAQKfyIAAg0ACAmQH8oBAPkCAA0ACAmQH8oBAPkCAAAA.',
Xe='Xenalah:BAAALgAECgIJAgAAAA==.',
Xi='Xikai:BAAALgADCgIJAgABLgAECgYJEQAIAAAAAA==.',
Xo='Xobos:BAAALgAECgEJAQAAAA==.',
Xp='Xpddevour:BAABLgAECn8lAAIVAAgJ/BMHGgCaAQAVAAgJ/BMHGgCaAQAAAA==.',
Xs='Xscapenature:BAAALgAECgcJEQAAAA==.',
Xt='Xtena:BAAALgADCgkJCwAAAA==.Xtendron:BAACLgAFFH8HAAMPAAMJ/whmIwDmAAAPAAMJ/whmIwDmAAAOAAIJrgP8GAB6AAAuAAQKfyQAAw8ACAnqHsYaAMkCAA8ACAnqHsYaAMkCAA4ABgniB9BaABEBAAAA.',
Xu='Xuxo:BAAALgADCgMJCAAAAA==.',
Ya='Yaraxiu:BAAALgAECgIJBAAAAA==.',
Ye='Yegarmiester:BAAALgAECgcJEwAAAA==.',
Yo='Yodidyoufart:BAABLgAECn8rAAMGAAgJQR8TFQDpAQAiAAcJtBkgJwDtAQAGAAgJdR4TFQDpAQAAAA==.',
Za='Zaco:BAABLgAECn8aAAIDAAcJwhaCEQCtAQADAAcJwhaCEQCtAQAAAA==.Zakonn:BAAALgADCgEJAQAAAA==.Zarikas:BAABLgAECn8UAAIVAAYJWBXZKwA1AQAVAAYJWBXZKwA1AQAAAA==.Zatapatate:BAABLgAECn8kAAMVAAgJ2Bl2FgC0AQAVAAgJ1Rl2FgC0AQAaAAYJSBIOCAAxAQAAAA==.',
Ze='Zekken:BAAALgADCgUJBwABLgADCgYJCQAIAAAAAA==.Zerality:BAAALgAECgcJEQAAAA==.',
Zh='Zhachy:BAACLgAFFH8FAAITAAMJMhoSFgD3AAATAAMJMhoSFgD3AAAuAAQKfygABBMACAn2IhsPAIUCABMABwkyIRsPAIUCABQABgm3IyoKADwCAAkAAQl4FAUgADwAAAAA.',
Zi='Ziggie:BAABLgAECn8mAAIVAAgJ9SXtAQAAAwAVAAgJ9SXtAQAAAwAAAA==.Zinovia:BAABLgAECn8VAAQbAAgJASC/EQBqAgAbAAgJsh2/EQBqAgAkAAYJoRcYMQCQAQAQAAEJeBkKYwBEAAAAAA==.Ziwei:BAAALgAECgMJBAABLgAECggJKwATAIIWAA==.',
Zo='Zombieboy:BAAALgAECgYJBQAAAA==.Zookee:BAABLgAECn8jAAIQAAgJdBoeBgBmAgAQAAgJdBoeBgBmAgAAAA==.',
['Ön']='Önlish:BAAALgAECgEJAQABLgAECgcJDAAIAAAAAA==.Önlîsh:BAAALgADCgMJAwABLgAECgcJDAAIAAAAAA==.',
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

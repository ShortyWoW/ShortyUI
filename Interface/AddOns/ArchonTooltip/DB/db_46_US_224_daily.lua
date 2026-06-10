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

local lookup = {'Paladin-Retribution','Warrior-Fury','Monk-Brewmaster','DeathKnight-Blood','Unknown-Unknown','DemonHunter-Havoc','DemonHunter-Vengeance','DeathKnight-Unholy','Druid-Guardian','Druid-Balance','Warlock-Demonology','Druid-Feral','Mage-Frost','Monk-Mistweaver','Mage-Fire','Mage-Arcane','Evoker-Devastation','Evoker-Preservation','Evoker-Augmentation','Priest-Discipline','Priest-Holy','Monk-Windwalker','Shaman-Enhancement','DemonHunter-Devourer','Priest-Shadow',}
local provider = {region='US',realm='Tortheldrin',name='US',type='daily',zone=46,date='2026-06-09',data={Ac='Acquinus:BAAALgAECgEJAQAAAA==.',
Ad='Adonis:BAAALgAECggJEwAAAA==.',
Ag='Agatha:BAAALgAECgYJDAAAAA==.',
Al='Altreyuzz:BAAALgADCgUJBQAAAA==.',
An='Anastarya:BAAALgAECgIJAgAAAA==.Anmor:BAAALgAECgUJBQABLgAFFAQJDAABAOYVAA==.Antiserum:BAAALgAECgMJAwAAAA==.',
Ap='Apocalypse:BAABLgAECn8XAAICAAkJYwayXwAxAQloDAAAAgAeAGkMAAADABgAawwAAAMAJwBqDAAAAwALAGwMAAADAAwAbQwAAAMAAgDqDAAAAgARAG4MAAACAAAAbwwAAAIAAgACAAkJYwayXwAxAQloDAAAAgAeAGkMAAADABgAawwAAAMAJwBqDAAAAwALAGwMAAADAAwAbQwAAAMAAgDqDAAAAgARAG4MAAACAAAAbwwAAAIAAgAAAA==.',
Ar='Arockoner:BAAALgADCgEJAQAAAA==.',
As='Astrozerg:BAAALgAECggJCAABLgAFFAYJKQADAOImAA==.',
Az='Azeroth:BAAALgADCgYJBgAAAA==.Azin:BAABLgAFFH8NAAIEAAQJSxedFwAaAQRoDAAABABPAGkMAAAEAEEAawwAAAIAIADqDAAAAwA9AAQABAlLF50XABoBBGgMAAAEAE8AaQwAAAQAQQBrDAAAAgAgAOoMAAADAD0AAAA=.',
Ba='Baen:BAAALgAECgYJCgAAAA==.',
Be='Bearju:BAAALgAECgIJBAAAAA==.Bet:BAAALgADCgMJAwABLgAECgUJCgAFAAAAAA==.',
Br='Braxticus:BAAALgADCgYJDQAAAA==.Bruceyuu:BAAALgAECgYJDQAAAA==.',
Bu='Bubble:BAAALgAECgcJEgAAAA==.',
Ca='Cassidin:BAACLgAFFH8MAAIBAAQJ5hUXRQAYAQRoDAAABQBRAGkMAAAEAFwAawwAAAEABADqDAAAAgAuAAEABAnmFRdFABgBBGgMAAAFAFEAaQwAAAQAXABrDAAAAQAEAOoMAAACAC4ALgAECn8ZAAIBAAkJgh2oLwBkAgABAAkJgh2oLwBkAgAAAA==.Cataclysm:BAAALgAECgkJAgAAAA==.',
Ch='Chammick:BAAALgADCgIJAgAAAA==.Chooch:BAABLgAECn8cAAMGAAYJjBzvHgDHAQZoDAAABQBQAGkMAAAFAE0AawwAAAUAOwBqDAAABAAzAGwMAAAEAEoA6gwAAAUASAAGAAYJjBzvHgDHAQZoDAAABQBQAGkMAAAFAE0AawwAAAUAOwBqDAAABAAzAGwMAAAEAEoA6gwAAAQASAAHAAEJjA8QNAAsAAHqDAAAAQAnAAAA.',
Ci='Cidril:BAABLgAECn8aAAIBAAgJ1BOnagCSAQhoDAAABQBQAGkMAAAFAEEAawwAAAUAMgBqDAAAAwA4AGwMAAABACAAbQwAAAEARQDqDAAABQA1AG4MAAABAAQAAQAICdQTp2oAkgEIaAwAAAUAUABpDAAABQBBAGsMAAAFADIAagwAAAMAOABsDAAAAQAgAG0MAAABAEUA6gwAAAUANQBuDAAAAQAEAAAA.',
Cr='Creating:BAABLgAECn8fAAIBAAgJ1R25OABAAghoDAAABQBBAGkMAAAFAFQAawwAAAUAVQBqDAAAAwBTAGwMAAAEAE8AbQwAAAIAQwDqDAAABQBXAG4MAAACAEAAAQAICdUduTgAQAIIaAwAAAUAQQBpDAAABQBUAGsMAAAFAFUAagwAAAMAUwBsDAAABABPAG0MAAACAEMA6gwAAAUAVwBuDAAAAgBAAAEuAAUUAwkIAAgAvQUA.Creep:BAAALgAECgEJAQABLgAECgIJAgAFAAAAAA==.Crk:BAAALgAECgQJBQABLgAFFAMJCAAIAL0FAA==.Crkgetd:BAAALgAECgEJAQABLgAFFAMJCAAIAL0FAA==.Cryptik:BAAALgADCgEJAQAAAA==.Cryptoprocta:BAAALgADCgUJCAAAAA==.',
Cu='Cuckcurll:BAAALgAFFAIJAQABLgAFFAUJCwAJACgkAA==.',
De='Deathslip:BAAALgAECgMJBQABLgAECgUJCQAFAAAAAA==.Devilneroo:BAABLgAECn8bAAIGAAgJlRv/EgD0AQhoDAAABgBSAGkMAAAGAEgAawwAAAYAUQBqDAAAAgBIAGwMAAABAE4AbQwAAAEASgDqDAAABAA/AG4MAAABACgABgAICZUb/xIA9AEIaAwAAAYAUgBpDAAABgBIAGsMAAAGAFEAagwAAAIASABsDAAAAQBOAG0MAAABAEoA6gwAAAQAPwBuDAAAAQAoAAAA.',
Do='Doobiesnibs:BAAALgAECgYJDAAAAA==.Doomzilla:BAAALgAECgcJBgAAAA==.Doth:BAABLgAECn8WAAIIAAYJESI2UQD+AQZoDAAABwBgAGkMAAAGAFsAawwAAAMAWABsDAAAAQBOAG0MAAABAEkA6gwAAAQAXAAIAAYJESI2UQD+AQZoDAAABwBgAGkMAAAGAFsAawwAAAMAWABsDAAAAQBOAG0MAAABAEkA6gwAAAQAXAAAAA==.Dovregubben:BAAALgAECgUJCgAAAA==.',
Dr='Drakknar:BAAALgAECgcJBwAAAA==.Drogyn:BAAALgAECgEJAgAAAA==.',
Dv='Dvlock:BAAALgAECgUJCQAAAA==.',
['Dò']='Dòóm:BAAALgAECgYJCgAAAA==.',
['Dó']='Dóóm:BAAALgAECgEJAQAAAA==.',
Ek='Ekrizdis:BAAALgADCgEJAgAAAA==.',
Em='Emryss:BAABLgAECn8VAAIKAAgJ0BeWGgDuAQhoDAAAAwAwAGkMAAADACkAawwAAAMAOABqDAAAAwAyAGwMAAAEAEAAbQwAAAEATwDqDAAAAgAxAG4MAAACAFcACgAICdAXlhoA7gEIaAwAAAMAMABpDAAAAwApAGsMAAADADgAagwAAAMAMgBsDAAABABAAG0MAAABAE8A6gwAAAIAMQBuDAAAAgBXAAAA.',
Ex='Exile:BAAALgAECgUJBgAAAA==.',
Fi='Finalgrace:BAAALgADCgYJBgAAAA==.Finnix:BAAALgADCgEJAQAAAA==.',
Fu='Furfoxsake:BAAALgADCgIJAgAAAA==.',
Gi='Gigilong:BAACLgAFFH8GAAILAAMJdhu7GwAXAQNoDAAAAwBWAGkMAAABAEoA6gwAAAIAMQALAAMJdhu7GwAXAQNoDAAAAwBWAGkMAAABAEoA6gwAAAIAMQAuAAQKfx0AAgsABwmcI5EWAM0CAAsABwmcI5EWAM0CAAAA.Gihon:BAAALgAECgUJBQAAAA==.',
Go='Gorrdain:BAAALgADCgEJAQAAAA==.Gorrgath:BAAALgAECgYJCgAAAA==.',
Gr='Grandeur:BAAALgADCgkJEAAAAA==.Greencrayon:BAAALgAECgMJBAAAAA==.Gristlezerg:BAAALgAECgUJBwABLgAFFAYJKQADAOImAA==.',
Hi='Hippopotamus:BAAALgAECgYJDQAAAA==.',
Ho='Holyhealz:BAAALgAECgMJAwAAAA==.',
Id='Idiotdk:BAABLgAFFH8FAAIIAAIJsQ+9ygCPAAJoDAAAAQAIAOoMAAAEAEgACAACCbEPvcoAjwACaAwAAAEACADqDAAABABIAAEuAAUUAwkIAAwAfRcA.',
Il='Illyria:BAAALgADCgUJAQAAAA==.',
Ir='Ironheart:BAABLgAECn8fAAIBAAgJhxTqXACxAQhoDAAAAwBOAGkMAAAGADEAawwAAAYAQwBqDAAAAwBDAGwMAAADADAAbQwAAAIALgDqDAAABwBKAG4MAAABAAQAAQAICYcU6lwAsQEIaAwAAAMATgBpDAAABgAxAGsMAAAGAEMAagwAAAMAQwBsDAAAAwAwAG0MAAACAC4A6gwAAAcASgBuDAAAAQAEAAAA.',
Ja='Jackmerious:BAABLgAECn8eAAINAAgJdBLtcACUAQhoDAAABgA3AGkMAAAFADYAawwAAAQAJQBqDAAAAwA/AGwMAAADADIAbQwAAAEAIwDqDAAABwAyAG4MAAABAC0ADQAICXQS7XAAlAEIaAwAAAYANwBpDAAABQA2AGsMAAAEACUAagwAAAMAPwBsDAAAAwAyAG0MAAABACMA6gwAAAcAMgBuDAAAAQAtAAAA.Jadefire:BAAALgAECgIJAQAAAA==.Jasnah:BAABLgAECn8wAAICAAkJNxYSGwASAgloDAAABwArAGkMAAAHADMAawwAAAYAQQBqDAAABgBPAGwMAAAFAFAAbQwAAAMAOQDqDAAABgA9AG4MAAAGADQAbwwAAAIAKwACAAkJNxYSGwASAgloDAAABwArAGkMAAAHADMAawwAAAYAQQBqDAAABgBPAGwMAAAFAFAAbQwAAAMAOQDqDAAABgA9AG4MAAAGADQAbwwAAAIAKwAAAA==.',
Je='Jefry:BAAALgADCgYJBgAAAA==.Jermomu:BAAALgAECgQJBQAAAA==.',
Ji='Jinai:BAABLgAECn8UAAIOAAYJbROMPQBnAQZoDAAABAA3AGkMAAAEAE4AawwAAAQAOwBqDAAAAgAZAGwMAAABAAkA6gwAAAUARgAOAAYJbROMPQBnAQZoDAAABAA3AGkMAAAEAE4AawwAAAQAOwBqDAAAAgAZAGwMAAABAAkA6gwAAAUARgABLgAECggJGwAGAJUbAA==.',
Jo='Johnnysalami:BAAALgADCgQJBAAAAA==.',
Ju='Julita:BAAALgAECgQJBQAAAA==.',
Ka='Kaggar:BAAALgAFFAEJAQAAAA==.Karadesh:BAABLgAFFH8HAAIPAAMJYBmQAgDmAANoDAAABABUAGkMAAABADwA6gwAAAIAMQAPAAMJYBmQAgDmAANoDAAABABUAGkMAAABADwA6gwAAAIAMQAAAA==.',
Ke='Keytosuccess:BAAALgAECgUJCQAAAA==.',
Ki='Killwhat:BAACLgAFFH8UAAMNAAQJYh4BQgBgAQRoDAAACABMAGkMAAAFAEIAawwAAAIATQDqDAAABQBaAA0ABAliHgFCAGABBGgMAAAHAEwAaQwAAAUAQgBrDAAAAgBNAOoMAAAFAFoAEAABCQgD3wYAOAABaAwAAAEABwAuAAQKfzkAAg0ACQmiI6sKACEDAA0ACQmiI6sKACEDAAAA.',
Kl='Klint:BAABLgAFFH8IAAIIAAMJvQVHrAC7AANoDAAAAwAQAGkMAAACAAgA6gwAAAMAEgAIAAMJvQVHrAC7AANoDAAAAwAQAGkMAAACAAgA6gwAAAMAEgAAAA==.',
Ko='Korthyn:BAABLgAECn8eAAQRAAkJgR2WBQD8AQloDAAABQBXAGkMAAACAD8AawwAAAMATQBqDAAAAwBaAGwMAAAFAE0AbQwAAAIAOADqDAAABgBbAG4MAAACAD8AbwwAAAIAVgARAAkJgR2WBQD8AQloDAAABQBXAGkMAAACAD8AawwAAAMATQBqDAAAAwBaAGwMAAAEAE0AbQwAAAEAOADqDAAAAwBbAG4MAAACAD8AbwwAAAEAVgASAAQJpBLmHwDuAARsDAAAAQA+AG0MAAABAB8A6gwAAAIAMwBvDAAAAQAsABMAAQmGE3yMADYAAeoMAAABADEAAAA=.',
Ku='Kurnoth:BAAALgAECgEJAQABLgAECgIJAgAFAAAAAA==.',
Lo='Lothus:BAAALgADCgMJAwAAAA==.',
Ma='Magely:BAAALgADCggJCAAAAA==.',
Me='Merkules:BAAALgAECgYJDAAAAA==.',
Mo='Moxie:BAACLgAFFH8aAAIUAAgJiRQ0CwBPAghoDAAABgBXAGkMAAAFAEwAawwAAAMAJgBqDAAAAgArAGwMAAABAAUAbQwAAAEAKgDqDAAABwBRAG4MAAABACwAFAAICYkUNAsATwIIaAwAAAYAVwBpDAAABQBMAGsMAAADACYAagwAAAIAKwBsDAAAAQAFAG0MAAABACoA6gwAAAcAUQBuDAAAAQAsAC4ABAp/JwACFAAJCcIjvwIASQMAFAAJCcIjvwIASQMAAAA=.',
Ms='Msdranderson:BAABLgAECn8tAAIVAAcJigrrOQAHAQdoDAAACQAQAGkMAAAIAA0AawwAAAcAIwBqDAAABgAjAGwMAAAGADIAbQwAAAIABADqDAAABwAgABUABwmKCus5AAcBB2gMAAAJABAAaQwAAAgADQBrDAAABwAjAGoMAAAGACMAbAwAAAYAMgBtDAAAAgAEAOoMAAAHACAAAAA=.',
Ne='Nero:BAAALgAECgUJCwABLgAECggJGwAGAJUbAA==.',
Ni='Nipps:BAAALgADCgQJCgAAAA==.',
Od='Odóyle:BAAALgAFFAEJAQAAAA==.',
On='Onatoe:BAAALgAECgMJAwAAAA==.',
Oo='Oo:BAAALgAECgUJBQAAAA==.',
Op='Op:BAAALgADCgcJAgAAAA==.',
Or='Orius:BAAALgAECgMJBAAAAA==.',
Pa='Parsimony:BAAALgADCgUJBQAAAA==.',
Pe='Peaches:BAAALgAECgUJBQAAAA==.Pestilent:BAAALgAECgIJAgAAAA==.',
Po='Poj:BAAALgAECgMJBgAAAA==.Pojins:BAAALgAECgIJAgAAAA==.',
Pr='Pratt:BAAALgADCgcJBwAAAA==.',
Pu='Purple:BAABLgAECn8tAAIBAAkJVB06IQB7AgloDAAABgBEAGkMAAAGAFoAawwAAAYATABqDAAABgAuAGwMAAAGAFQAbQwAAAIAKADqDAAABgBMAG4MAAAFAEcAbwwAAAIAWwABAAkJVB06IQB7AgloDAAABgBEAGkMAAAGAFoAawwAAAYATABqDAAABgAuAGwMAAAGAFQAbQwAAAIAKADqDAAABgBMAG4MAAAFAEcAbwwAAAIAWwAAAA==.',
Ra='Raviel:BAAALgADCgQJBAAAAA==.',
Re='Regret:BAABLgAECn8XAAIKAAcJsCJREQBIAgdoDAAABABYAGkMAAAFAFoAawwAAAQAWgBqDAAAAwBfAGwMAAADAFcAbQwAAAEAWADqDAAAAwBXAAoABwmwIlERAEgCB2gMAAAEAFgAaQwAAAUAWgBrDAAABABaAGoMAAADAF8AbAwAAAMAVwBtDAAAAQBYAOoMAAADAFcAAS4ABRQICRwACgCfGQA=.',
Ro='Rogué:BAAALgADCgQJBAAAAA==.',
Ru='Rueal:BAAALgADCgEJAQAAAA==.Rukar:BAAALgAECgQJCgAAAA==.',
Sa='Sabra:BAAALgAECgQJBgABLgAECgUJCgAFAAAAAA==.Saia:BAAALgAECgUJEAAAAA==.Samanosuke:BAAALgAECgEJAQAAAA==.Sawaruna:BAAALgADCgYJBgAAAA==.',
Se='Seleren:BAAALgADCgEJAQAAAA==.Serapphina:BAAALgAECgIJAgAAAA==.',
Si='Silverfangz:BAAALgADCgEJAQAAAA==.Sinless:BAAALgAECgQJBgAAAA==.',
Sn='Snipedbaby:BAAALgAECgMJAgAAAA==.',
Su='Superfist:BAACLgAFFH8YAAQWAAcJwRdiBABPAQdoDAAABgBaAGkMAAAFADsAawwAAAQAOwBqDAAAAgBEAGwMAAABAEoAbQwAAAEAAwDqDAAABQBOABYABQkPHGIEAE8BBWgMAAAGAFoAaQwAAAUAOwBrDAAABAA7AGoMAAACAEQA6gwAAAUATgAOAAEJ7RA9VABIAAFsDAAAAQArAAMAAQlZAa1cAC8AAW0MAAABAAMALgAECn8mAAMWAAgJyCJDBgAcAwAWAAgJyCJDBgAcAwAOAAcJlB6nFQBhAgAAAA==.',
['Så']='Såbra:BAAALgADCgEJAQAAAA==.',
Ta='Tavitusk:BAAALgAECgcJDQABLgAECgkJFgABAFEbAA==.Tayonhands:BAAALgAECgYJEAABLgAECgkJMAACADcWAA==.',
Te='Tehgimp:BAABLgAECn86AAIXAAkJLg1JEACkAQloDAAACAApAGkMAAAHACMAawwAAAcAHwBqDAAABwAaAGwMAAAHACcAbQwAAAUAEwDqDAAABwAjAG4MAAAGAC4AbwwAAAQAEwAXAAkJLg1JEACkAQloDAAACAApAGkMAAAHACMAawwAAAcAHwBqDAAABwAaAGwMAAAHACcAbQwAAAUAEwDqDAAABwAjAG4MAAAGAC4AbwwAAAQAEwAAAA==.',
Ti='Tinder:BAAALgAECgEJAQAAAA==.',
To='Tom:BAAALgAECgMJAwAAAA==.',
Tr='Trakanon:BAABLgAECn8uAAQRAAgJchw5BgDlAQhoDAAABgBTAGkMAAAIAE0AawwAAAgATgBqDAAABgBaAGwMAAAGAFAAbQwAAAIALgDqDAAACABMAG4MAAACAEMAEQAICXIcOQYA5QEIaAwAAAQAUwBpDAAABQBNAGsMAAAFAE4AagwAAAUAWgBsDAAABQBQAG0MAAABAC4A6gwAAAUATABuDAAAAQBDABMABQlCE0w8AP0ABWgMAAABAEgAaQwAAAEARABrDAAAAgAzAGoMAAABADEAbAwAAAEABAASAAYJEgqMHwDyAAZoDAAAAQALAGkMAAACAB0AawwAAAEAGwBtDAAAAQAfAOoMAAADAB8AbgwAAAEAFwAAAA==.Treezus:BAAALgAECgEJAQAAAA==.Trouthunter:BAAALgAECggJDwAAAA==.',
Ts='Tsuyoikuma:BAAALgADCgkJGQAAAA==.',
Ug='Ugornargol:BAAALgADCgEJAQABLgAECgcJBwAFAAAAAA==.',
Uu='Uu:BAABLgAECn8ZAAIKAAkJYhz0DgBoAgloDAAABABZAGkMAAAEAFUAawwAAAQAUQBqDAAAAwBQAGwMAAADAFIAbQwAAAEAQgDqDAAABABfAG4MAAABACYAbwwAAAEAKQAKAAkJYhz0DgBoAgloDAAABABZAGkMAAAEAFUAawwAAAQAUQBqDAAAAwBQAGwMAAADAFIAbQwAAAEAQgDqDAAABABfAG4MAAABACYAbwwAAAEAKQAAAA==.',
Uw='Uwu:BAAALgADCgcJDgAAAA==.',
Va='Valicore:BAABLgAECn8aAAIYAAgJNxOYQgDqAQhoDAAABQBNAGkMAAAEACwAawwAAAQALwBqDAAABABHAGwMAAAEADMAbQwAAAEAGgDqDAAAAwA+AG4MAAABACEAGAAICTcTmEIA6gEIaAwAAAUATQBpDAAABAAsAGsMAAAEAC8AagwAAAQARwBsDAAABAAzAG0MAAABABoA6gwAAAMAPgBuDAAAAQAhAAAA.Vansftw:BAAALgAECggJDwAAAA==.Varithak:BAAALgADCgYJBgAAAA==.',
Ve='Vent:BAAALgAECgQJBQAAAA==.Vestrevus:BAAALgAECgUJEQAAAA==.',
Vg='Vginny:BAAALgADCgUJBQAAAA==.',
Vi='Violetta:BAABLgAECn8dAAIOAAYJ2SB7GwAvAgZoDAAABABIAGkMAAAEAFcAawwAAAQAWABqDAAABgBMAGwMAAAFAFUA6gwAAAYAXgAOAAYJ2SB7GwAvAgZoDAAABABIAGkMAAAEAFcAawwAAAQAWABqDAAABgBMAGwMAAAFAFUA6gwAAAYAXgABLgAECgIJAgAFAAAAAA==.Viroz:BAAALgADCgYJBgAAAA==.',
Vo='Vonix:BAAALgADCgMJAwAAAA==.Vorcthal:BAACLgAFFH8FAAIUAAMJsRoDKgDrAANoDAAAAwBCAGkMAAABAEgA6gwAAAEAQQAUAAMJsRoDKgDrAANoDAAAAwBCAGkMAAABAEgA6gwAAAEAQQAuAAQKfygAAxQACQmMHSUHAAQDABQACQmMHSUHAAQDABkACAlEDTYxAFIBAAAA.Voren:BAAALgADCgQJBAAAAA==.Vorenormu:BAABLgAECn8dAAQTAAgJixNWKwCJAQhoDAAABQAwAGkMAAAFADcAawwAAAUANABqDAAAAwBFAGwMAAADACsAbQwAAAEAMADqDAAABQA0AG4MAAACADAAEwAICdwSVisAiQEIaAwAAAMAIwBpDAAABAA3AGsMAAAEADQAagwAAAMARQBsDAAAAwArAG0MAAABADAA6gwAAAQANABuDAAAAgAwABIAAwlWA6c+AHUAA2gMAAABAA0AawwAAAEACQDqDAAAAQACABEAAgniEJI0AHAAAmgMAAABADAAaQwAAAEAJgABLgAFFAMJBQAUALEaAA==.',
Vy='Vyre:BAAALgAECgEJAQABLgAECggJHgANAHQSAA==.',
Wa='Waste:BAAALgAECgIJAgAAAA==.',
Wi='Wingzero:BAAALgAECgIJAgAAAA==.',
Xe='Xero:BAAALgADCgUJBQAAAA==.',
Xo='Xoloteku:BAAALgADCgIJAgAAAA==.',
Xx='Xxz:BAAALgAECgcJBgAAAA==.',
Ya='Yaoi:BAAALgAECgYJCAABLgAECgIJAgAFAAAAAA==.',
Za='Zaelor:BAAALgAECgcJBgABLgAECgkJGgAYADcTAA==.Zandros:BAAALgAECgcJBwAAAA==.',
Ze='Zen:BAAALgADCgQJBAABLgAECggJCQAFAAAAAA==.Zergdh:BAAALgADCgcJBwABLgAFFAYJKQADAOImAA==.Zergkin:BAAALgAECggJCAABLgAFFAYJKQADAOImAA==.',
Zu='Zuggernautt:BAAALgAECgcJDAAAAA==.Zuryea:BAAALgAECgUJCgAAAA==.',
['Zü']='Zülly:BAAALgADCgcJCQAAAA==.',
},}
provider.parse = parse

local rawData = provider.data
provider.data = {}
provider.getChunk = getChunkLookup(rawData, 2)

provider.splitId = 0
provider.splitCount = 1
provider.splitType = 'none'

setmetatable(provider.data, {
	__index = function(table, key)
		provider.getChunk(key)
	end,
})

if _G["ArchonTooltip"] and ArchonTooltip.AddProviderV2 then
	ArchonTooltip.AddProviderV2(lookup, provider)
end

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

local lookup = {'Unknown-Unknown','Paladin-Retribution','Paladin-Holy','DeathKnight-Blood','Rogue-Subtlety','Druid-Guardian','Druid-Feral','DeathKnight-Unholy','Shaman-Elemental','DemonHunter-Devourer','Priest-Discipline','Warlock-Destruction','Shaman-Restoration','Hunter-BeastMastery','Shaman-Enhancement','Evoker-Preservation','Evoker-Augmentation','Priest-Holy','Monk-Mistweaver','Monk-Windwalker','Mage-Frost','DemonHunter-Vengeance','DemonHunter-Havoc','Monk-Brewmaster','Warrior-Protection','Druid-Balance','Druid-Restoration','Priest-Shadow','Warrior-Fury','Evoker-Devastation','Hunter-Marksmanship','Warlock-Demonology','Warrior-Arms',}
local provider = {region='US',realm='Ursin',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abelle:BAAALgAECgEJAQAAAA==.Abigail:BAAALgAECgEJAQAAAA==.',
Ad='Adrialortial:BAAALgAECgEJAQAAAA==.',
Al='Aliesterra:BAAALgADCgUJBwAAAA==.',
Am='Amaryllys:BAAALgAECgMJBAAAAA==.',
An='Animalstyle:BAAALgADCgcJBwABLgAECgEJAQABAAAAAA==.Anonymoose:BAAALgAECgYJDQAAAA==.Antrus:BAAALgAECggJDQAAAA==.',
Ar='Arator:BAAALgAECgEJAQAAAA==.Arykiel:BAABLgAECn8ZAAICAAcJfBgjOQCbAQACAAcJfBgjOQCbAQAAAA==.',
As='Asthar:BAAALgADCgMJBQAAAA==.',
At='Atalian:BAAALgAECgUJBgABLgAFFAQJCwADAAQgAA==.',
Au='Auhsoj:BAAALgADCgEJAQABLgAFFAUJDQAEAAUZAA==.',
Aw='Awenno:BAAALgADCgkJCQAAAA==.',
Ba='Baffled:BAAALgADCggJCAAAAA==.Ballisticboo:BAABLgAECn8ZAAIFAAgJfBCVDgC6AQAFAAgJfBCVDgC6AQAAAA==.Bazbirttwo:BAAALgAECgMJBQAAAA==.',
Be='Bearbearbear:BAABLgAECn8gAAMGAAcJtxTmCgBpAQAGAAcJtxTmCgBpAQAHAAUJeQ5WHQD/AAABLgAECgkJGwAIAB0MAA==.Bearocalypse:BAAALgADCgIJAgAAAA==.',
Bo='Boongnizzle:BAAALgADCgUJBQAAAA==.Borenthol:BAAALgAECgMJAwAAAA==.',
Br='Branaka:BAABLgAECn8VAAIJAAcJ+BcVHgBdAQAJAAcJ+BcVHgBdAQAAAA==.Braniti:BAAALgADCgQJBAAAAA==.Breadbull:BAAALgAECgQJBAAAAA==.Breadsoup:BAAALgAECgYJDQABLgAFFAIJAwABAAAAAA==.Briarmaul:BAAALgADCgEJAQAAAA==.Brickedkey:BAAALgAECgYJCwABLgAECggJJAAKAPkeAA==.',
Bu='Bubbies:BAABLgAECn8ZAAILAAcJgxZ/EwCoAQALAAcJgxZ/EwCoAQAAAA==.Budew:BAAALgAECgUJBQAAAA==.Bulyamy:BAAALgAECgMJBgAAAA==.Butcherßrown:BAAALgAECgMJAwAAAA==.',
Ch='Chadilac:BAAALgAECgkJEgAAAA==.Chiste:BAABLgAECn8bAAIMAAcJ7AzJDAAFAQAMAAcJ7AzJDAAFAQAAAA==.',
Co='Cobrah:BAAALgADCggJDQABLgAECgUJBQABAAAAAA==.Coredellion:BAAALgADCgUJCAAAAA==.Corypheus:BAAALgADCggJEAAAAA==.',
Cr='Crispysan:BAAALgAECgYJBgAAAA==.Crispyushi:BAAALgAECgYJDgAAAA==.',
Cu='Curareeh:BAAALgAECgYJBgAAAA==.',
Da='Dahlia:BAABLgAECn8mAAINAAgJ3RI7HwC5AQANAAgJ3RI7HwC5AQABLgAFFAYJGQAOAJMYAA==.Dannica:BAAALgAECgUJAgAAAA==.Dantedragon:BAAALgAECgIJAgAAAA==.Dantezs:BAAALgADCgIJAQAAAA==.Darthen:BAAALgAECgUJCwAAAA==.Dazzle:BAAALgAECgEJAQAAAA==.',
De='Deathmantis:BAAALgAECgYJDQABLgAFFAUJDQAEAAUZAA==.Demo:BAAALgAECgYJBgAAAA==.Demondemon:BAAALgAECgQJBgAAAA==.',
Di='Dirty:BAAALgAECgYJEgAAAA==.',
Dk='Dkillin:BAABLgAECn8VAAICAAcJ5gldYQArAQACAAcJ5gldYQArAQAAAA==.',
Do='Dobledas:BAAALgAECggJCAAAAA==.Dominisera:BAAALgAECgcJCwABLgAFFAMJBQAPADUVAA==.Dovenah:BAAALgADCgIJBAAAAA==.',
Dr='Dreadheirark:BAAALgADCgQJBAAAAA==.Drseussphd:BAAALgADCgMJAwAAAA==.',
Du='Durangho:BAAALgAECgcJDQAAAA==.',
Eh='Ehlesdi:BAAALgAECgMJAwAAAA==.',
El='Elayne:BAABLgAECn8sAAMQAAgJUiRLAQAwAwAQAAgJUiRLAQAwAwARAAQJKhHXPwDpAAAAAA==.Elizalynn:BAABLgAECn8gAAISAAgJIxBiGQCDAQASAAgJIxBiGQCDAQAAAA==.',
Ev='Eveycakes:BAAALgAECgYJDgABLgAFFAQJCwADAAQgAA==.',
Fe='Fengshui:BAAALgAECggJCAAAAA==.Ferritin:BAABLgAECn8eAAIEAAgJDiXcAQBjAwAEAAgJDiXcAQBjAwAAAA==.Fester:BAAALgAECgEJAQAAAA==.',
Fi='Fish:BAAALgAECgQJBgAAAA==.Fishguts:BAACLgAFFH8GAAITAAMJXBCTFwDEAAATAAMJXBCTFwDEAAAuAAQKfzYAAxMACQlEG+sOAGgCABMACQlEG+sOAGgCABQACAnFGx0KABkCAAAA.',
Fo='Focaccia:BAABLgAECn8VAAIVAAgJnhveGgBJAgAVAAgJnhveGgBJAgAAAA==.Foxthisup:BAAALgAECgIJAgAAAA==.',
Fr='Frey:BAAALgADCgYJDQABLgAECgYJDAABAAAAAA==.',
Fu='Furrywarrior:BAAALgADCgYJBgAAAA==.',
['Fí']='Físh:BAAALgAECgMJAwAAAA==.',
Ge='Geneviève:BAAALgAFFAIJBAABLgAFFAYJGQAOAJMYAA==.',
Gl='Glittershtr:BAAALgADCgcJBwABLgAECggJJAAKAPkeAA==.',
Go='Gothjuice:BAAALgADCgcJDQAAAA==.',
Gr='Granuaile:BAAALgADCgYJBwAAAA==.Grultock:BAAALgAECgQJCgAAAA==.',
Gu='Guruleio:BAAALgADCgcJBwAAAA==.',
Gw='Gwenquaya:BAABLgAECn8gAAINAAgJTRsyDABtAgANAAgJTRsyDABtAgAAAA==.',
['Gô']='Gôngfû:BAAALgAECgEJAQAAAA==.',
He='Healohunter:BAAALgAECgMJBAAAAA==.',
Hi='Higgs:BAAALgAECgEJAQAAAA==.',
Ho='Hockeydruid:BAAALgAECgEJAgABLgAECgkJIgAOAMMVAA==.Hockeyhunter:BAABLgAECn8iAAIOAAkJwxWUGgD+AQAOAAkJwxWUGgD+AQAAAA==.Hockeylockz:BAAALgAECgUJDAABLgAECgkJIgAOAMMVAA==.Holydps:BAAALgADCgIJAgAAAA==.Hooker:BAAALgAECgQJBAAAAA==.Horcrux:BAAALgADCgMJAwAAAA==.Howdoimdps:BAAALgAECgIJBgABLgAECgkJIgAVANAPAA==.',
Hu='Hunthunthunt:BAAALgAECgcJEwABLgAECgkJGwAIAB0MAA==.',
['Hè']='Hèxen:BAAALgADCgcJBgAAAA==.',
Ic='Icetomeetu:BAAALgAECgMJBQAAAA==.Ichaival:BAAALgAECgYJDAAAAA==.',
Ig='Igneel:BAAALgADCgcJDgAAAA==.',
Je='Jedem:BAAALgADCgUJCAAAAA==.',
Ji='Jillidan:BAAALgAECgMJAwAAAA==.',
Ka='Kalathaes:BAAALgADCgYJBgABLgAECggJEAABAAAAAA==.Kanawaza:BAAALgADCgMJAwAAAA==.Kazimir:BAAALgAECgYJBgAAAA==.Kazu:BAAALgAECgMJBwAAAA==.Kazum:BAAALgAECgEJAQAAAA==.',
Ke='Keralan:BAACLgAFFH8FAAIWAAIJBSSEBgBoAAAWAAIJBSSEBgBoAAAuAAQKfyAAAxYACAkjJoIAAGwDABYACAkjJoIAAGwDABcAAQmhFU04AEUAAAEuAAUUBQkVABgA3CEA.',
Ki='Kiljaiden:BAAALgADCgUJCgAAAA==.',
Kl='Klhank:BAAALgAECgEJAQAAAA==.',
Ko='Korotyr:BAAALgAECgUJCwAAAA==.',
Kr='Kromwel:BAABLgAECn8eAAIZAAgJ4COqAgCzAgAZAAgJ4COqAgCzAgAAAA==.',
Kw='Kwehlewd:BAABLgAECn8YAAIaAAcJlA3fIwAbAQAaAAcJlA3fIwAbAQAAAA==.',
La='Lachampion:BAAALgADCggJCQABLgAECgUJBQABAAAAAA==.Laizee:BAABLgAECn8eAAINAAgJ2gMYQQD/AAANAAgJ2gMYQQD/AAAAAA==.Latrice:BAABLgAECn8lAAICAAkJ6h27DgCIAgACAAkJ6h27DgCIAgAAAA==.',
Lo='Loki:BAAALgAECgUJDwAAAA==.',
Lu='Ludo:BAAALgADCgUJBQAAAA==.Luxferre:BAABLgAECn8cAAIKAAYJSRMVSgAaAQAKAAYJSRMVSgAaAQAAAA==.',
Ma='Mattadk:BAAALgADCgUJBQAAAA==.Mattylite:BAABLgAECn8VAAITAAgJwBH7HwBGAQATAAgJwBH7HwBGAQAAAA==.Mawikiea:BAAALgAECgEJAgABLgAECgkJLwASAL8gAA==.',
Me='Melander:BAABLgAECn8eAAIZAAkJpBugBgDEAgAZAAkJpBugBgDEAgAAAA==.',
Mh='Mhoram:BAAALgAECgEJAQAAAA==.',
Mi='Mike:BAAALgAECgYJCQAAAA==.Milksterr:BAAALgAECgUJBQABLgAFFAMJBQAPADUVAA==.',
Mo='Moggchamp:BAAALgAECgUJDQAAAA==.Mommywommy:BAAALgAECgEJAQAAAA==.Mongy:BAAALgAECgIJAgAAAA==.Mordeaf:BAAALgADCgYJBgAAAA==.',
Mv='Mvp:BAACLgAFFH8JAAIIAAIJeSAaXgC/AAAIAAIJeSAaXgC/AAAuAAQKfyQAAggACAl5JBAJAM0CAAgACAl5JBAJAM0CAAAA.',
Na='Nami:BAAALgAECgUJBwAAAA==.Natalie:BAAALgAECgYJBgAAAA==.',
Ne='Nerzhuul:BAACLgAFFH8FAAIPAAMJNRXiBAD+AAAPAAMJNRXiBAD+AAAuAAQKfykAAg8ACQnwHZ4FAKkCAA8ACQnwHZ4FAKkCAAAA.',
No='Noarn:BAAALgADCgEJAQAAAA==.Noopola:BAAALgADCgYJBgAAAA==.Noove:BAABLgAECn8jAAIDAAgJAxxtCgBqAgADAAgJAxxtCgBqAgAAAA==.',
Ny='Nyxiana:BAAALgAECgMJAwAAAA==.',
Ol='Olow:BAABLgAECn8dAAIVAAYJFxViegAcAQAVAAYJFxViegAcAQAAAA==.',
Om='Omalkkalktok:BAAALgADCgMJAwAAAA==.',
On='Onyxz:BAABLgAECn8aAAMbAAgJBBtsGQD5AQAbAAYJuB1sGQD5AQAaAAcJ0Q5jMACFAQAAAA==.',
Op='Opsef:BAAALgADCgYJCwAAAA==.',
Pa='Painpriest:BAAALgADCgYJBgAAAA==.Pandastryker:BAAALgAECgYJDQABLgAFFAUJDQAEAAUZAA==.Pandlian:BAAALgADCgUJBQABLgAFFAQJCwADAAQgAA==.',
Ph='Phigg:BAAALgAECgIJBwAAAA==.Phreog:BAAALgAFFAIJAwAAAA==.',
Po='Pondscum:BAAALgAECgUJBQAAAA==.',
Pr='Primalshock:BAAALgADCgUJBwAAAA==.Promethus:BAAALgAECgUJCAAAAA==.',
Pw='Pwotector:BAAALgAECgYJEwAAAA==.',
['Qù']='Qùèenbish:BAAALgADCgQJAgAAAA==.',
Ra='Raedaldra:BAABLgAECn8VAAQSAAcJnx4wCQBZAgASAAcJnx4wCQBZAgALAAEJNRY/QwA+AAAcAAEJow2mXgA7AAAAAA==.Raggnarr:BAACLgAFFH8LAAIdAAQJdBsNCgBSAQAdAAQJdBsNCgBSAQAuAAQKfykAAh0ACAm6IA0NAO4CAB0ACAm6IA0NAO4CAAAA.Raina:BAAALgAECgYJBgAAAA==.Rainesagé:BAAALgAFFAMJBAAAAA==.Rania:BAABLgAECn8VAAIYAAgJ1CBtDQC8AgAYAAgJ1CBtDQC8AgAAAA==.Rayla:BAAALgADCgUJBQAAAQ==.',
Re='Reaza:BAAALgAECgUJBQAAAA==.Rekkthraka:BAAALgAECgQJBQAAAA==.Renatnom:BAAALgADCggJFwAAAA==.',
Ri='Riqitan:BAAALgAECgUJBQAAAA==.',
Ro='Roardemon:BAAALgAECgYJCAAAAA==.Ronji:BAAALgAECgEJAQAAAA==.',
Ry='Rythevia:BAABLgAECn80AAMRAAkJHxVACwAXAgARAAgJvhNACwAXAgAeAAgJyBHtEgCzAQAAAA==.',
Sa='Sanctified:BAAALgAECgYJCwAAAA==.Saphíra:BAEALgAECgQJCAABLgAECgkJKQAEAGokAA==.Satanick:BAAALgADCgEJAQABLgAFFAMJBQAPADUVAA==.',
Se='Seraph:BAABLgAECn8eAAISAAgJExE2JgC6AQASAAgJExE2JgC6AQAAAA==.Serasta:BAAALgAECgYJDgAAAA==.',
Sh='Shoc:BAAALgADCgIJAgAAAA==.',
Sj='Sjoralina:BAAALgAECgEJAQAAAA==.',
Sl='Slamcheeks:BAAALgAECgEJAQAAAA==.Slanghammer:BAAALgAECgUJBQAAAA==.',
Sn='Snikit:BAAALgADCgcJBwABLgAECgkJHgAZAKQbAA==.',
So='Sojourner:BAAALgAECgYJEwAAAA==.',
Sp='Spoonzilla:BAABLgAECn8VAAIaAAYJ9QeNNQC3AAAaAAYJ9QeNNQC3AAAAAA==.',
St='Stabjesse:BAAALgADCgUJBQAAAA==.Stormm:BAABLgAECn8kAAIKAAgJ+R71FgAEAgAKAAgJ+R71FgAEAgAAAA==.',
Su='Supersham:BAAALgAECgEJAQAAAA==.Superspam:BAABLgAECn8eAAMbAAgJVx7iLAD7AQAbAAgJVx7iLAD7AQAaAAcJWBKzGwBXAQAAAA==.Supersuplex:BAAALgAECgYJBgAAAA==.',
Ta='Targot:BAAALgAECgcJDAAAAA==.',
Te='Teinaras:BAABLgAECn8mAAIfAAgJJR63AgBHAgAfAAgJJR63AgBHAgAAAA==.',
Th='Thegrease:BAAALgAECgUJBQAAAA==.Thistledewit:BAABLgAECn8cAAIbAAYJ8RCQOwAmAQAbAAYJ8RCQOwAmAQAAAA==.Thrasherzs:BAAALgAECgEJAgAAAA==.Thy:BAAALgADCgEJAQAAAA==.',
Ti='Tinyvoid:BAABLgAECn8eAAIKAAgJeBiIHwDLAQAKAAgJeBiIHwDLAQAAAA==.',
To='Togdumburz:BAACLgAFFH8GAAIgAAMJRRRyQADaAAAgAAMJRRRyQADaAAAuAAQKfyUAAyAACQkhGocMAIsCACAACQkhGocMAIsCAAwAAQkAAEBnAEIAAAAA.Tolouse:BAAALgADCgcJCQAAAA==.',
Ty='Typhon:BAAALgAECgEJAQAAAA==.',
Un='Undeåd:BAAALgAECgMJBAAAAA==.',
Va='Vaelhyra:BAACLgAFFH8VAAIYAAUJ3CGJAQAHAgAYAAUJ3CGJAQAHAgAuAAQKfxkABBgACAmKIeQJAOsCABgACAl1IeQJAOsCABQAAgnJFCFcAKAAABMAAgmdD1haAGUAAAAA.Valox:BAAALgADCgEJAgAAAA==.Vampiregirls:BAAALgAECgYJBgAAAA==.Vaydos:BAAALgADCgEJAQABLgAECgcJEwABAAAAAA==.',
Ve='Velirine:BAAALgADCgYJBgAAAA==.Venlya:BAABLgAECn8UAAMZAAcJHySaBABpAgAZAAcJHySaBABpAgAhAAEJ2x4/NQBbAAABLgAFFAUJFQAYANwhAA==.',
Vi='Vietsham:BAABLgAECn8fAAINAAgJehD8LgBWAQANAAgJehD8LgBWAQAAAA==.Viralmessiah:BAAALgADCgEJAQAAAA==.',
Vo='Vorpalite:BAAALgADCggJDAAAAA==.',
Vu='Vulstryker:BAACLgAFFH8NAAIEAAUJBRm8DQABAQAEAAUJBRm8DQABAQAuAAQKfxgAAgQACAnKGZQNADQCAAQACAnKGZQNADQCAAAA.',
Wa='Wacky:BAAALgADCgMJAwAAAA==.Warlussy:BAAALgADCgEJAQAAAA==.Wawa:BAAALgADCgEJAQAAAA==.',
Wo='Woahlock:BAAALgADCgYJBgAAAA==.',
Wu='Wurrzagudura:BAAALgADCggJDAAAAA==.',
Xr='Xrookie:BAAALgADCgUJCwABLgADCgcJDgABAAAAAA==.',
['Xä']='Xänthe:BAABLgAECn8vAAMSAAkJvyBIAgAkAwASAAkJvyBIAgAkAwALAAIJiA8sNwB2AAAAAA==.',
Ye='Yetlian:BAACLgAFFH8LAAIDAAQJBCAODQBYAQADAAQJBCAODQBYAQAuAAQKfxYAAwMACAmiG4cXAFUCAAMACAmiG4cXAFUCAAIAAQkAAZgiARYAAAAA.',
Ze='Zerath:BAAALgADCgUJBQAAAA==.',
Zi='Zigi:BAACLgAFFH8ZAAIhAAYJnyWpAAAfAgAhAAYJnyWpAAAfAgAuAAQKfyAAAiEACAmrIWUCAAADACEACAmrIWUCAAADAAAA.',
Zo='Zobo:BAAALgAECgYJBgAAAA==.',
Zu='Zultarra:BAAALgAECgEJAQAAAA==.',
Zy='Zyrahh:BAAALgADCgYJBgAAAA==.',
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

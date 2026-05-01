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

local lookup = {'Paladin-Holy','DeathKnight-Blood','Rogue-Subtlety','Druid-Guardian','Druid-Feral','DeathKnight-Unholy','Shaman-Elemental','Unknown-Unknown','DemonHunter-Devourer','Priest-Discipline','Warlock-Destruction','Shaman-Restoration','Hunter-BeastMastery','Paladin-Retribution','Shaman-Enhancement','Evoker-Preservation','Evoker-Augmentation','Priest-Holy','Monk-Mistweaver','Monk-Windwalker','DemonHunter-Vengeance','DemonHunter-Havoc','Monk-Brewmaster','Warrior-Protection','Druid-Balance','Mage-Frost','Druid-Restoration','Warrior-Fury','Evoker-Devastation','Hunter-Marksmanship','Warlock-Demonology','Warrior-Arms',}
local provider = {region='US',realm='Ursin',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abelle:BAAALgADCgkJGwAAAA==.Abigail:BAAALgAECgEJAQAAAA==.',
Ad='Adrialortial:BAAALgADCgcJCAAAAA==.',
Al='Aliesterra:BAAALgADCgUJBwAAAA==.',
Am='Amaryllys:BAAALgAECgMJAwAAAA==.',
An='Animalstyle:BAAALgADCgcJBwAAAA==.Anonymoose:BAAALgAECgQJCgAAAA==.Antrus:BAAALgAECggJDAAAAA==.',
Ar='Arator:BAAALgAECgEJAQAAAA==.Arykiel:BAAALgAECgYJEgAAAA==.',
As='Asthar:BAAALgADCgMJBAAAAA==.',
At='Atalian:BAAALgAECgQJBAABLgAFFAQJCgABAIMfAA==.',
Au='Auhsoj:BAAALgADCgEJAQABLgAFFAUJDAACAAYZAA==.',
Aw='Awenno:BAAALgADCgkJCQAAAA==.',
Ba='Baffled:BAAALgADCgYJBwAAAA==.Ballisticboo:BAABLgAECn8ZAAIDAAgJfBDaCQDMAQADAAgJfBDaCQDMAQAAAA==.Bazbirttwo:BAAALgAECgMJBQAAAA==.',
Be='Bearbearbear:BAABLgAECn8ZAAMEAAYJmxX0CQAvAQAEAAYJaBX0CQAvAQAFAAUJeQ5XHQD/AAABLgAECgkJFwAGAKEJAA==.Bearocalypse:BAAALgADCgIJAgAAAA==.',
Bo='Boongnizzle:BAAALgADCgUJBQAAAA==.Borenthol:BAAALgAECgMJAwAAAA==.',
Br='Branaka:BAABLgAECn8VAAIHAAcJ9Re2FQBoAQAHAAcJ9Re2FQBoAQAAAA==.Braniti:BAAALgADCgQJBAAAAA==.Breadsoup:BAAALgAECgYJDQABLgAFFAIJAgAIAAAAAA==.Brickedkey:BAAALgAECgYJCwABLgAECggJIwAJAPkeAA==.',
Bu='Bubbies:BAABLgAECn8VAAIKAAYJ6hJ7IgCAAQAKAAYJ6hJ7IgCAAQAAAA==.Budew:BAAALgAECgUJBQAAAA==.Bulyamy:BAAALgAECgMJBgAAAA==.Butcherßrown:BAAALgAECgMJAwAAAA==.',
Ch='Chadilac:BAAALgAECgYJCwAAAA==.Chiste:BAABLgAECn8XAAILAAUJAgskMwDrAAALAAUJAgskMwDrAAAAAA==.',
Co='Cobrah:BAAALgADCggJDQAAAA==.Coredellion:BAAALgADCgUJCAAAAA==.Corypheus:BAAALgADCggJEAAAAA==.',
Cr='Crispysan:BAAALgAECgYJBgAAAA==.Crispyushi:BAAALgAECgYJDgAAAA==.',
Cu='Curareeh:BAAALgAECgYJBgAAAA==.',
Da='Dahlia:BAABLgAECn8mAAIMAAgJ1RKMFADHAQAMAAgJ1RKMFADHAQABLgAFFAUJFwANADoWAA==.Dannica:BAAALgAECgIJAgAAAA==.Dantedragon:BAAALgAECgEJAQAAAA==.Dantezs:BAAALgADCgIJAQAAAA==.Darthen:BAAALgAECgMJBgAAAA==.',
De='Deathmantis:BAAALgAECgYJDQABLgAFFAUJDAACAAYZAA==.Demondemon:BAAALgAECgQJBgAAAA==.',
Di='Dirty:BAAALgAECgYJEgAAAA==.',
Dk='Dkillin:BAABLgAECn8UAAIOAAYJrAppWgACAQAOAAYJrAppWgACAQAAAA==.',
Do='Dobledas:BAAALgAECggJCAAAAA==.Dominisera:BAAALgAECgUJBQABLgAECggJJQAPAG8dAA==.Dovenah:BAAALgADCgIJBAAAAA==.',
Dr='Dreadheirark:BAAALgADCgQJBAAAAA==.Drseussphd:BAAALgADCgMJAwAAAA==.',
Du='Durangho:BAAALgAECgcJDQAAAA==.',
Eh='Ehlesdi:BAAALgAECgMJAwAAAA==.',
El='Elayne:BAABLgAECn8kAAMQAAgJgCEpAQAHAwAQAAgJgCEpAQAHAwARAAQJKhHUPwDpAAAAAA==.Elizalynn:BAABLgAECn8XAAISAAYJjxDpPQBCAQASAAYJjxDpPQBCAQAAAA==.',
Ev='Eveycakes:BAAALgAECgYJDgABLgAFFAQJCgABAIMfAA==.',
Fe='Fengshui:BAAALgAECggJCAAAAA==.Ferritin:BAABLgAECn8eAAICAAgJDiXbAQBjAwACAAgJDiXbAQBjAwAAAA==.Fester:BAAALgAECgEJAQAAAA==.',
Fi='Fish:BAAALgAECgQJBQAAAA==.Fishguts:BAABLgAECn80AAMTAAkJRRvqDgBoAgATAAkJRRvqDgBoAgAUAAcJYB2ACQDhAQAAAA==.',
Fo='Focaccia:BAAALgAECggJDQAAAA==.Foxthisup:BAAALgAECgIJAgAAAA==.',
Fr='Frey:BAAALgADCgYJDQABLgAECgQJBAAIAAAAAA==.',
Fu='Furrywarrior:BAAALgADCgYJBgAAAA==.',
['Fí']='Físh:BAAALgAECgMJAwAAAA==.',
Ge='Geneviève:BAAALgAFFAIJAwABLgAFFAUJFwANADoWAA==.',
Gl='Glittershtr:BAAALgADCgcJBwABLgAECggJIwAJAPkeAA==.',
Go='Gothjuice:BAAALgADCgcJDQAAAA==.',
Gr='Granuaile:BAAALgADCgYJBwAAAA==.Grultock:BAAALgAECgQJBgAAAA==.',
Gu='Guruleio:BAAALgADCgcJBwAAAA==.',
Gw='Gwenquaya:BAABLgAECn8XAAIMAAYJgx3KFADEAQAMAAYJgx3KFADEAQAAAA==.',
['Gô']='Gôngfû:BAAALgAECgEJAQAAAA==.',
He='Healohunter:BAAALgAECgMJAwAAAA==.',
Hi='Higgs:BAAALgAECgEJAQAAAA==.',
Ho='Hockeydruid:BAAALgADCgYJDwABLgAECggJGQANAGcWAA==.Hockeyhunter:BAABLgAECn8ZAAINAAgJZxYeHgBRAgANAAgJZxYeHgBRAgAAAA==.Hockeylockz:BAAALgAECgUJDAABLgAECggJGQANAGcWAA==.Holydps:BAAALgADCgIJAgAAAA==.Horcrux:BAAALgADCgMJAwAAAA==.Howdoimdps:BAAALgAECgIJBQAAAA==.',
Hu='Hunthunthunt:BAAALgAECgYJEQABLgAECgkJFwAGAKEJAA==.',
Ic='Icetomeetu:BAAALgAECgMJBQAAAA==.Ichaival:BAAALgAECgQJBAAAAA==.',
Ig='Igneel:BAAALgADCgcJDgAAAA==.',
Je='Jedem:BAAALgADCgUJCAAAAA==.',
Ka='Kalathaes:BAAALgADCgYJBgABLgAECggJEAAIAAAAAA==.Kanawaza:BAAALgADCgMJAwAAAA==.Kazimir:BAAALgAECgYJBgAAAA==.Kazu:BAAALgAECgMJBgAAAA==.Kazum:BAAALgAECgEJAQAAAA==.',
Ke='Keralan:BAABLgAECn8gAAMVAAgJIyaCAABsAwAVAAgJIyaCAABsAwAWAAEJmhXoKwBGAAABLgAFFAQJFAAXAGglAA==.',
Ki='Kiljaiden:BAAALgADCgUJCgAAAA==.',
Kl='Klhank:BAAALgAECgEJAQAAAA==.',
Ko='Korotyr:BAAALgAECgUJCwAAAA==.',
Kr='Kromwel:BAABLgAECn8bAAIYAAcJMSRYAwBXAgAYAAcJMSRYAwBXAgAAAA==.',
Kw='Kwehlewd:BAABLgAECn8YAAIZAAcJlA20GgAmAQAZAAcJlA20GgAmAQAAAA==.',
La='Lachampion:BAAALgADCggJCQABLgADCggJDQAIAAAAAA==.Laizee:BAABLgAECn8bAAIMAAcJJgQbNADpAAAMAAcJJgQbNADpAAAAAA==.Latrice:BAABLgAECn8iAAIOAAgJ5BzHEgAkAgAOAAgJ5BzHEgAkAgAAAA==.',
Lo='Loki:BAAALgAECgQJCgAAAA==.',
Lu='Ludo:BAAALgADCgUJBQAAAA==.Luxferre:BAABLgAECn8ZAAIJAAYJshKnMgAYAQAJAAYJshKnMgAYAQAAAA==.',
Ma='Mattadk:BAAALgADCgUJBQAAAA==.Mattylite:BAABLgAECn8VAAITAAgJxhGTFwBMAQATAAgJxhGTFwBMAQAAAA==.Mawikiea:BAAALgADCggJCAABLgAECgkJJgASAI0gAA==.',
Me='Melander:BAABLgAECn8VAAIYAAgJvx2gBgDEAgAYAAgJvx2gBgDEAgAAAA==.',
Mh='Mhoram:BAAALgADCgcJDgAAAA==.',
Mi='Mike:BAAALgAECgYJCQAAAA==.Milksterr:BAAALgADCgUJBQABLgAECggJJQAPAG8dAA==.',
Mo='Moggchamp:BAAALgAECgUJDQAAAA==.Mommywommy:BAAALgAECgEJAQAAAA==.Mongy:BAAALgADCggJIQAAAA==.Mordeaf:BAAALgADCgYJBgAAAA==.',
Mv='Mvp:BAACLgAFFH8GAAIGAAIJ9BtlOACqAAAGAAIJ9BtlOACqAAAuAAQKfxwAAgYACAnwIYYPAEMCAAYACAnwIYYPAEMCAAAA.',
Na='Nami:BAAALgAECgUJBwAAAA==.Natalie:BAAALgAECgYJBgAAAA==.',
Ne='Nerzhuul:BAABLgAECn8lAAIPAAgJbx2eBQCpAgAPAAgJbx2eBQCpAgAAAA==.',
No='Noarn:BAAALgADCgEJAQAAAA==.Noopola:BAAALgADCgYJBgAAAA==.Noove:BAABLgAECn8gAAIBAAgJ4Bv5BQCFAgABAAgJ4Bv5BQCFAgAAAA==.',
Ny='Nyxiana:BAAALgAECgMJAwAAAA==.',
Ol='Olow:BAABLgAECn8ZAAIaAAYJVhMYZwAMAQAaAAYJVhMYZwAMAQAAAA==.',
Om='Omalkkalktok:BAAALgADCgMJAwAAAA==.',
On='Onyxz:BAABLgAECn8YAAMbAAgJAht/EQACAgAbAAYJuR1/EQACAgAZAAcJ0g5eMACFAQAAAA==.',
Op='Opsef:BAAALgADCgYJCwAAAA==.',
Pa='Painpriest:BAAALgADCgYJBgAAAA==.Pandastryker:BAAALgAECgYJDAABLgAFFAUJDAACAAYZAA==.Pandlian:BAAALgADCgUJBQABLgAFFAQJCgABAIMfAA==.',
Ph='Phigg:BAAALgAECgIJBwAAAA==.Phreog:BAAALgAFFAIJAgAAAA==.',
Po='Pondscum:BAAALgAECgUJBQAAAA==.',
Pr='Primalshock:BAAALgADCgUJBwAAAA==.Promethus:BAAALgAECgUJCAAAAA==.',
Pw='Pwotector:BAAALgAECgYJEwAAAA==.',
['Qù']='Qùèenbish:BAAALgADCgQJAgAAAA==.',
Ra='Raedaldra:BAAALgAECgcJEgAAAA==.Raggnarr:BAACLgAFFH8HAAIcAAQJhxZoCABRAQAcAAQJhxZoCABRAQAuAAQKfyQAAhwACAlVHxINAO4CABwACAlVHxINAO4CAAAA.Rainesagé:BAAALgAFFAEJAQAAAA==.Rania:BAABLgAECn8VAAIXAAgJ0yBxDQC8AgAXAAgJ0yBxDQC8AgAAAA==.Rayla:BAAALgADCgUJBQAAAQ==.',
Re='Reaza:BAAALgAECgUJBQAAAA==.Rekkthraka:BAAALgAECgQJBQAAAA==.Renatnom:BAAALgADCggJFwAAAA==.',
Ri='Riqitan:BAAALgADCgcJEgABLgADCggJDQAIAAAAAA==.',
Ro='Roardemon:BAAALgAECgIJAgAAAA==.Ronji:BAAALgAECgEJAQAAAA==.',
Ry='Rythevia:BAABLgAECn8rAAMRAAkJYBMMDQC4AQARAAcJwxEMDQC4AQAdAAgJyBHtEgCzAQAAAA==.',
Sa='Sanctified:BAAALgAECgYJCwAAAA==.Saphíra:BAEALgAECgQJBAABLgAECgkJJwACAOghAA==.Satanick:BAAALgADCgEJAQABLgAECggJJQAPAG8dAA==.',
Se='Seraph:BAABLgAECn8eAAISAAgJEhEzJgC6AQASAAgJEhEzJgC6AQAAAA==.Serasta:BAAALgAECgYJDgAAAA==.',
Sh='Shoc:BAAALgADCgIJAgAAAA==.',
Sj='Sjoralina:BAAALgAECgEJAQAAAA==.',
Sl='Slamcheeks:BAAALgAECgEJAQAAAA==.Slanghammer:BAAALgAECgUJBQAAAA==.',
Sn='Snikit:BAAALgADCgcJBwABLgAECggJFQAYAL8dAA==.',
So='Sojourner:BAAALgAECgUJDQAAAA==.',
Sp='Spoonzilla:BAABLgAECn8UAAIZAAYJ7gdqKQC+AAAZAAYJ7gdqKQC+AAAAAA==.',
Sq='Squee:BAAALgAECgcJEgAAAA==.',
St='Stabjesse:BAAALgADCgUJBQAAAA==.Stormm:BAABLgAECn8jAAIJAAgJ+R7eDQAJAgAJAAgJ+R7eDQAJAgAAAA==.',
Su='Superspam:BAABLgAECn8ZAAMbAAgJVB7mLAD7AQAbAAgJVB7mLAD7AQAZAAUJfhP3IgDoAAAAAA==.Supersuplex:BAAALgAECgYJBgAAAA==.',
Ta='Targot:BAAALgAECgcJDAAAAA==.',
Te='Teinaras:BAABLgAECn8mAAIeAAgJFB6PAQBmAgAeAAgJFB6PAQBmAgAAAA==.',
Th='Thegrease:BAAALgAECgUJBQAAAA==.Thistledewit:BAABLgAECn8WAAIbAAYJ8RBULAAvAQAbAAYJ8RBULAAvAQAAAA==.',
Ti='Tinyvoid:BAABLgAECn8bAAIJAAcJKRlMGgCXAQAJAAcJKRlMGgCXAQAAAA==.',
To='Togdumburz:BAACLgAFFH8FAAIfAAMJQBQ3LADxAAAfAAMJQBQ3LADxAAAuAAQKfxwAAx8ACAkAFxZNAOEBAB8ABwkAFxZNAOEBAAsAAQkAAEBnAEIAAAAA.Tolouse:BAAALgADCgcJCQAAAA==.',
Ty='Typhon:BAAALgAECgEJAQAAAA==.',
Un='Undeåd:BAAALgAECgMJBAAAAA==.',
Va='Vaelhyra:BAACLgAFFH8UAAIXAAQJaCUnAgC8AQAXAAQJaCUnAgC8AQAuAAQKfxkABBcACAmKIeUJAOsCABcACAl1IeUJAOsCABQAAgnIFB1cAKAAABMAAgmhD1daAGUAAAAA.Valox:BAAALgADCgEJAgAAAA==.Vampiregirls:BAAALgAECgYJBgAAAA==.Vaydos:BAAALgADCgEJAQABLgAECgcJEQAIAAAAAA==.',
Ve='Velirine:BAAALgADCgYJBgAAAA==.Venlya:BAABLgAECn8UAAMYAAcJFSTGAgByAgAYAAcJFSTGAgByAgAgAAEJ1R46NQBbAAABLgAFFAQJFAAXAGglAA==.',
Vi='Vietsham:BAABLgAECn8XAAIMAAcJfQ4PTQBPAQAMAAcJfQ4PTQBPAQAAAA==.Viralmessiah:BAAALgADCgEJAQAAAA==.',
Vo='Vorpalite:BAAALgADCggJDAAAAA==.',
Vu='Vulstryker:BAACLgAFFH8MAAICAAUJBhnoCAAMAQACAAUJBhnoCAAMAQAuAAQKfxYAAgIACAmwGZQNADQCAAIACAmwGZQNADQCAAAA.',
Wa='Wacky:BAAALgADCgMJAwAAAA==.Warlussy:BAAALgADCgEJAQAAAA==.Wawa:BAAALgADCgEJAQAAAA==.',
Wu='Wurrzagudura:BAAALgADCggJDAAAAA==.',
Xr='Xrookie:BAAALgADCgUJCwABLgADCgcJDgAIAAAAAA==.',
['Xä']='Xänthe:BAABLgAECn8mAAISAAkJjSAxAQAwAwASAAkJjSAxAQAwAwAAAA==.',
Ye='Yetlian:BAACLgAFFH8KAAIBAAQJgx+fCABjAQABAAQJgx+fCABjAQAuAAQKfxUAAwEACAmiG4kXAFUCAAEACAmiG4kXAFUCAA4AAQmtAGrmABcAAAAA.',
Zi='Zigi:BAACLgAFFH8TAAIgAAYJNiFrAAAIAgAgAAYJNiFrAAAIAgAuAAQKfyAAAiAACAmrIWcCAAADACAACAmrIWcCAAADAAAA.',
Zo='Zobo:BAAALgAECgYJBgAAAA==.',
Zu='Zultarra:BAAALgADCgkJGwAAAA==.',
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

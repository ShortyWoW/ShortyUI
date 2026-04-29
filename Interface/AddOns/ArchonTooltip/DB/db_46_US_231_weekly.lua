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

local lookup = {'Paladin-Holy','Rogue-Subtlety','Unknown-Unknown','DemonHunter-Devourer','Shaman-Restoration','Hunter-BeastMastery','DeathKnight-Blood','Shaman-Enhancement','Evoker-Preservation','Evoker-Augmentation','Monk-Mistweaver','Monk-Windwalker','DemonHunter-Vengeance','DemonHunter-Havoc','Monk-Brewmaster','Warrior-Protection','Druid-Balance','Paladin-Retribution','DeathKnight-Unholy','Warlock-Demonology','Warrior-Fury','Evoker-Devastation','Priest-Holy','Hunter-Marksmanship','Warlock-Destruction','Warrior-Arms',}
local provider = {region='US',realm='Ursin',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Abelle:BAAALgADCgkJEgAAAA==.Abigail:BAAALgAECgEJAQAAAA==.',
Ad='Adrialortial:BAAALgADCgcJBwAAAA==.',
Al='Aliesterra:BAAALgADCgUJBwAAAA==.',
Am='Amaryllys:BAAALgAECgMJAwAAAA==.',
An='Animalstyle:BAAALgADCgcJBwAAAA==.Anonymoose:BAAALgAECgQJCgAAAA==.Antrus:BAAALgAECggJCwAAAA==.',
Ar='Arator:BAAALgAECgEJAQAAAA==.Arykiel:BAAALgAECgUJDAAAAA==.',
As='Asthar:BAAALgADCgMJBAAAAA==.',
At='Atalian:BAAALgAECgQJBAABLgAFFAQJCQABAIMfAA==.',
Aw='Awenno:BAAALgADCgkJCQAAAA==.',
Ba='Ballisticboo:BAABLgAECn8XAAICAAgJOQ/qAwDTAQACAAgJOQ/qAwDTAQAAAA==.Bazbirttwo:BAAALgAECgMJBQAAAA==.',
Be='Bearbearbear:BAAALgAECgUJDAABLgAECggJEQADAAAAAA==.Bearocalypse:BAAALgADCgIJAgAAAA==.',
Bo='Boongnizzle:BAAALgADCgUJBQAAAA==.Borenthol:BAAALgAECgMJAwAAAA==.',
Br='Branaka:BAAALgAECgYJEgAAAA==.Braniti:BAAALgADCgQJBAAAAA==.Breadsoup:BAAALgAECgYJDQAAAA==.Brickedkey:BAAALgAECgYJCwABLgAECggJGwAEAPkeAA==.',
Bu='Bubbies:BAAALgAECgYJDwAAAA==.Budew:BAAALgAECgUJBQAAAA==.Bulyamy:BAAALgAECgMJBgAAAA==.Butcherßrown:BAAALgAECgMJAwAAAA==.',
Ch='Chadilac:BAAALgAECgYJCwAAAA==.Chiste:BAAALgAECgUJEQAAAA==.',
Co='Cobrah:BAAALgADCgYJBgABLgADCgcJEgADAAAAAA==.Coredellion:BAAALgADCgMJAwAAAA==.Corypheus:BAAALgADCggJEAAAAA==.',
Cr='Crispysan:BAAALgAECgYJBgAAAA==.Crispyushi:BAAALgAECgYJDgAAAA==.',
Cu='Curareeh:BAAALgAECgYJBgAAAA==.',
Da='Dahlia:BAABLgAECn8eAAIFAAgJ1RKBCAC/AQAFAAgJ1RKBCAC/AQABLgAFFAUJEgAGAHEVAA==.Dannica:BAAALgAECgIJAgAAAA==.Dantedragon:BAAALgADCgUJCwAAAA==.Dantezs:BAAALgADCgIJAQAAAA==.Darthen:BAAALgAECgMJBgAAAA==.',
De='Deathmantis:BAAALgAECgYJDQABLgAFFAQJCgAHAAYZAA==.Demondemon:BAAALgAECgIJAgAAAA==.',
Di='Dirty:BAAALgAECgYJEgAAAA==.',
Dk='Dkillin:BAAALgAECgYJDgAAAA==.',
Do='Dominisera:BAAALgAECgUJBQABLgAECggJIQAIAJEcAA==.Dovenah:BAAALgADCgIJBAAAAA==.',
Dr='Dreadheirark:BAAALgADCgQJBAAAAA==.Drseussphd:BAAALgADCgMJAwAAAA==.',
Du='Durangho:BAAALgAECgcJDQAAAA==.',
Eh='Ehlesdi:BAAALgAECgMJAwAAAA==.',
El='Elayne:BAABLgAECn8cAAMJAAYJdSXvAACFAgAJAAYJdSXvAACFAgAKAAQJKhHSPwDpAAAAAA==.Elizalynn:BAAALgAECgYJEgAAAA==.',
Ev='Eveycakes:BAAALgAECgYJDgABLgAFFAQJCQABAIMfAA==.',
Fe='Fengshui:BAAALgAECggJCAAAAA==.Ferritin:BAABLgAECn8eAAIHAAgJDiXaAQBjAwAHAAgJDiXaAQBjAwAAAA==.Fester:BAAALgADCgkJDwAAAA==.',
Fi='Fish:BAAALgAECgQJBQAAAA==.Fishguts:BAABLgAECn8sAAMLAAgJ2BvnDgBpAgALAAgJ2BvnDgBpAgAMAAYJCiCgGgAKAgAAAA==.',
Fo='Focaccia:BAAALgAECgYJBgAAAA==.Foxthisup:BAAALgAECgIJAgAAAA==.',
Fr='Frey:BAAALgADCgYJBgAAAA==.',
Fu='Furrywarrior:BAAALgADCgYJBgAAAA==.',
['Fí']='Físh:BAAALgAECgMJAwAAAA==.',
Ge='Geneviève:BAAALgAFFAEJAQABLgAFFAUJEgAGAHEVAA==.',
Gl='Glittershtr:BAAALgADCgcJBwABLgAECggJGwAEAPkeAA==.',
Go='Gothjuice:BAAALgADCgcJDQAAAA==.',
Gr='Granuaile:BAAALgADCgYJBwAAAA==.Grultock:BAAALgAECgMJAwAAAA==.',
Gu='Guruleio:BAAALgADCgcJBwAAAA==.',
Gw='Gwenquaya:BAAALgAECgYJEgAAAA==.',
['Gô']='Gôngfû:BAAALgAECgEJAQAAAA==.',
He='Healohunter:BAAALgAECgMJAwAAAA==.',
Hi='Higgs:BAAALgAECgEJAQAAAA==.',
Ho='Hockeydruid:BAAALgADCgYJDwABLgAECggJFQAGAGcWAA==.Hockeyhunter:BAABLgAECn8VAAIGAAgJZxYiHgBRAgAGAAgJZxYiHgBRAgAAAA==.Hockeylockz:BAAALgAECgMJBAABLgAECggJFQAGAGcWAA==.Holydps:BAAALgADCgIJAgAAAA==.Horcrux:BAAALgADCgMJAwAAAA==.Howdoimdps:BAAALgAECgIJAgAAAA==.',
Hu='Hunthunthunt:BAAALgAECgYJCQABLgAECggJEQADAAAAAA==.',
Ic='Icetomeetu:BAAALgAECgMJAwAAAA==.',
Ig='Igneel:BAAALgADCgcJDgAAAA==.',
Je='Jedem:BAAALgADCgMJAwAAAA==.',
Ka='Kalathaes:BAAALgADCgYJBgABLgAECggJEAADAAAAAA==.Kanawaza:BAAALgADCgMJAwAAAA==.Kazimir:BAAALgAECgYJBgAAAA==.Kazu:BAAALgAECgMJAwAAAA==.',
Ke='Keralan:BAABLgAECn8YAAMNAAgJeSWCAABsAwANAAgJeSWCAABsAwAOAAEJmhUzFABFAAABLgAFFAQJEAAPAHQkAA==.',
Ki='Kiljaiden:BAAALgADCgUJCgAAAA==.',
Kl='Klhank:BAAALgAECgEJAQAAAA==.',
Ko='Korotyr:BAAALgAECgUJCgAAAA==.',
Kr='Kromwel:BAABLgAECn8YAAIQAAYJSiRkDABGAgAQAAYJSiRkDABGAgAAAA==.',
Kw='Kwehlewd:BAABLgAECn8VAAIRAAYJfQ/hPQA7AQARAAYJfQ/hPQA7AQAAAA==.',
La='Laizee:BAABLgAECn8YAAIFAAYJgwSDHACwAAAFAAYJgwSDHACwAAAAAA==.Latrice:BAABLgAECn8gAAISAAgJzBwBCAAKAgASAAgJzBwBCAAKAgAAAA==.',
Lo='Loki:BAAALgAECgMJBgAAAA==.',
Lu='Ludo:BAAALgADCgUJBQAAAA==.Luxferre:BAAALgAECgYJCwAAAA==.',
Ma='Mattadk:BAAALgADCgUJBQAAAA==.Mattylite:BAABLgAECn8VAAILAAgJxhGCCQBYAQALAAgJxhGCCQBYAQAAAA==.Mawikiea:BAAALgADCggJCAAAAA==.',
Me='Melander:BAABLgAECn8VAAIQAAgJvx2eBgDEAgAQAAgJvx2eBgDEAgAAAA==.',
Mh='Mhoram:BAAALgADCgcJDgAAAA==.',
Mi='Mike:BAAALgAECgYJCQAAAA==.Milksterr:BAAALgADCgUJBQABLgAECggJIQAIAJEcAA==.',
Mo='Moggchamp:BAAALgAECgUJDQAAAA==.Mommywommy:BAAALgAECgEJAQAAAA==.Mongy:BAAALgADCgYJEwAAAA==.Mordeaf:BAAALgADCgYJBgAAAA==.',
Mv='Mvp:BAABLgAECn8VAAITAAcJHCMoLgCAAgATAAcJHCMoLgCAAgABLgAFFAIJBQAUAIkYAA==.',
Na='Nami:BAAALgAECgUJBwAAAA==.Natalie:BAAALgAECgYJBgAAAA==.',
Ne='Nerzhuul:BAABLgAECn8hAAIIAAgJkRycBQCpAgAIAAgJkRycBQCpAgAAAA==.',
No='Noarn:BAAALgADCgEJAQAAAA==.Noove:BAABLgAECn8bAAIBAAgJPxoFBAA2AgABAAgJPxoFBAA2AgAAAA==.',
Ny='Nyxiana:BAAALgAECgMJAwAAAA==.',
Ol='Olow:BAAALgAECgYJEQAAAA==.',
Om='Omalkkalktok:BAAALgADCgMJAwAAAA==.',
On='Onyxz:BAAALgAECggJCwAAAA==.',
Op='Opsef:BAAALgADCgYJCwAAAA==.',
Pa='Painpriest:BAAALgADCgYJBgAAAA==.Pandastryker:BAAALgAECgUJBgABLgAFFAQJCgAHAAYZAA==.Pandlian:BAAALgADCgUJBQABLgAFFAQJCQABAIMfAA==.',
Ph='Phigg:BAAALgAECgIJBgAAAA==.Phreog:BAAALgAECgQJBAABLgAECgYJDQADAAAAAA==.',
Po='Pondscum:BAAALgAECgUJBQAAAA==.',
Pr='Primalshock:BAAALgADCgUJBwAAAA==.Promethus:BAAALgAECgQJBQAAAA==.',
Pw='Pwotector:BAAALgAECgYJEwAAAA==.',
['Qù']='Qùèenbish:BAAALgADCgQJAgAAAA==.',
Ra='Raedaldra:BAAALgAECgYJDAAAAA==.Raggnarr:BAABLgAECn8aAAIVAAgJQR8SDQDuAgAVAAgJQR8SDQDuAgAAAA==.Rainesagé:BAAALgAECgcJCAAAAA==.Rania:BAAALgAECggJEwAAAA==.Rayla:BAAALgADCgUJBQAAAQ==.',
Re='Reaza:BAAALgAECgUJBQAAAA==.Rekkthraka:BAAALgAECgMJAwAAAA==.Renatnom:BAAALgADCggJEgAAAA==.',
Ri='Riqitan:BAAALgADCgcJEgAAAA==.',
Ro='Roardemon:BAAALgADCgMJAwAAAA==.Ronji:BAAALgAECgEJAQAAAA==.',
Ry='Rythevia:BAABLgAECn8iAAMKAAkJlQ9CBgCWAQAWAAcJKRPqEgCzAQAKAAcJBA1CBgCWAQAAAA==.',
Sa='Sanctified:BAAALgAECgUJCQAAAA==.',
Se='Seraph:BAABLgAECn8eAAIXAAgJEhEzJgC6AQAXAAgJEhEzJgC6AQAAAA==.Serasta:BAAALgAECgYJCwAAAA==.',
Sj='Sjoralina:BAAALgAECgEJAQAAAA==.',
Sl='Slamcheeks:BAAALgAECgEJAQAAAA==.Slanghammer:BAAALgAECgUJBQAAAA==.',
Sn='Snikit:BAAALgADCgcJBwABLgAECggJFQAQAL8dAA==.',
So='Sojourner:BAAALgAECgQJBgAAAA==.',
Sp='Spoonzilla:BAAALgAECgYJCwAAAA==.',
Sq='Squee:BAAALgAECgcJDwAAAA==.',
St='Stabjesse:BAAALgADCgUJBQAAAA==.Stormm:BAABLgAECn8bAAIEAAgJ+R6eGgC0AgAEAAgJ+R6eGgC0AgAAAA==.',
Su='Superspam:BAAALgAECgcJEQAAAA==.Supersuplex:BAAALgAECgUJBQAAAA==.',
Ta='Targot:BAAALgAECgcJDAAAAA==.',
Te='Teinaras:BAABLgAECn8eAAIYAAgJnhsEAQAlAgAYAAgJnhsEAQAlAgAAAA==.',
Th='Thegrease:BAAALgAECgUJBQAAAA==.Thistledewit:BAAALgAECgYJEAAAAA==.',
Ti='Tinyvoid:BAABLgAECn8YAAIEAAYJuxvOTADBAQAEAAYJuxvOTADBAQAAAA==.',
To='Togdumburz:BAABLgAECn8cAAMUAAgJABcWTQDhAQAUAAcJABcWTQDhAQAZAAEJAAA5ZwBCAAAAAA==.Tolouse:BAAALgADCgcJCQAAAA==.',
Ty='Typhon:BAAALgAECgEJAQAAAA==.',
Un='Undeåd:BAAALgAECgMJBAAAAA==.',
Va='Vaelhyra:BAACLgAFFH8QAAIPAAQJdCTvAACnAQAPAAQJdCTvAACnAQAuAAQKfxkABA8ACAmKIeQJAOsCAA8ACAl1IeQJAOsCAAwAAgnIFBtcAKAAAAsAAgmhDyhaAGcAAAAA.Valox:BAAALgADCgEJAgAAAA==.Vampiregirls:BAAALgAECgYJBgAAAA==.Vaydos:BAAALgADCgEJAQABLgAECgYJDgADAAAAAA==.',
Ve='Velirine:BAAALgADCgYJBgAAAA==.Venlya:BAABLgAECn8UAAMQAAcJFSTuAABzAgAQAAcJFSTuAABzAgAaAAEJ1R4zNQBbAAABLgAFFAQJEAAPAHQkAA==.',
Vi='Vietsham:BAABLgAECn8UAAIFAAYJaQ8UTQBPAQAFAAYJaQ8UTQBPAQAAAA==.Viralmessiah:BAAALgADCgEJAQAAAA==.',
Vo='Vorpalite:BAAALgADCggJDAAAAA==.',
Vu='Vulstryker:BAACLgAFFH8KAAIHAAQJBhkzAwAcAQAHAAQJBhkzAwAcAQAuAAQKfxYAAgcACAmwGZMNADQCAAcACAmwGZMNADQCAAAA.',
Wa='Wacky:BAAALgADCgMJAwAAAA==.Warlussy:BAAALgADCgEJAQAAAA==.Wawa:BAAALgADCgEJAQAAAA==.',
Wu='Wurrzagudura:BAAALgADCggJDAAAAA==.',
Xr='Xrookie:BAAALgADCgUJCwABLgADCgcJDgADAAAAAA==.',
['Xä']='Xänthe:BAABLgAECn8dAAIXAAkJxByXAAD2AgAXAAkJxByXAAD2AgAAAA==.',
Ye='Yetlian:BAABLgAFFH8JAAIBAAQJgx+dAgBxAQABAAQJgx+dAgBxAQAAAA==.',
Zi='Zigi:BAACLgAFFH8NAAIaAAUJuh91AACRAQAaAAUJuh91AACRAQAuAAQKfyAAAhoACAmrIWQCAAADABoACAmrIWQCAAADAAAA.',
Zo='Zobo:BAAALgAECgYJBgAAAA==.',
Zu='Zultarra:BAAALgADCgkJEgAAAA==.',
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

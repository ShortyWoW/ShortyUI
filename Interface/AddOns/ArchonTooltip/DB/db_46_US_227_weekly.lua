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

local lookup = {'Warlock-Demonology','Unknown-Unknown','DeathKnight-Unholy','DemonHunter-Devourer','Warrior-Protection','Rogue-Assassination','Paladin-Protection','Paladin-Retribution','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Enhancement','Shaman-Restoration','Paladin-Holy','DeathKnight-Blood','Warrior-Fury','Warrior-Arms','DemonHunter-Vengeance','DemonHunter-Havoc','Priest-Holy','Mage-Frost','Evoker-Devastation','Druid-Restoration','DeathKnight-Frost','Druid-Balance','Evoker-Augmentation','Evoker-Preservation','Mage-Arcane','Mage-Fire','Priest-Discipline','Shaman-Elemental','Rogue-Subtlety','Druid-Guardian','Monk-Brewmaster','Monk-Windwalker',}
local provider = {region='US',realm='TwistingNether',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abharn:BAAALgAECgQJBQAAAA==.',
Ak='Akeera:BAABLgAECn8UAAIBAAcJTQ5dRgAdAQABAAcJTQ5dRgAdAQAAAA==.Akkiya:BAAALgAECgYJDwABLgAFFAMJBAACAAAAAA==.',
Am='Amalyn:BAAALgAECgYJCAAAAA==.Amarantha:BAAALgAECgYJEQAAAA==.',
An='Anaesthetize:BAAALgADCgYJCwAAAA==.Aness:BAAALgAECgYJCgAAAA==.Animaker:BAABLgAECn8nAAIDAAgJChZZGwDkAQADAAgJChZZGwDkAQAAAA==.Anngus:BAAALgADCgIJAgAAAA==.Anvilkrash:BAAALgADCgcJCwAAAA==.',
Ar='Ariese:BAAALgADCgcJCAAAAA==.',
As='Ashido:BAAALgAECgMJAwAAAA==.Astreos:BAAALgAECgQJBAABLgAFFAYJFgAEACkgAA==.Astrikin:BAAALgAECgYJDwABLgAFFAYJFgAEACkgAA==.',
Au='Auraiel:BAAALgADCgcJFAAAAA==.Aurorastar:BAAALgAECgEJAQAAAA==.',
Ba='Baultier:BAAALgADCgkJDgAAAA==.',
Be='Bel:BAABLgAECn8nAAIFAAgJdCGzAQCwAgAFAAgJdCGzAQCwAgAAAA==.Beraxes:BAAALgAECgUJCQAAAA==.',
Bl='Blasser:BAABLgAECn8WAAIGAAYJcyHQBQAoAgAGAAYJcyHQBQAoAgAAAA==.Blizizdumz:BAABLgAECn8hAAMHAAYJfCFoBwCkAQAHAAYJFiFoBwCkAQAIAAQJzB/tSwAnAQAAAA==.',
Bm='Bmcgilicuddy:BAAALgADCgEJAQAAAA==.',
Br='Bralindra:BAAALgAECgEJAgAAAA==.Brewdhism:BAAALgAECgMJAwAAAA==.',
Bu='Bulsy:BAABLgAECn8ZAAMJAAgJ0hYCJgCBAQAJAAgJ0hYCJgCBAQAKAAQJkATTaACbAAAAAA==.',
Ca='Calamidade:BAABLgAECn8nAAMLAAgJEwRlCwApAQALAAgJEwRlCwApAQAMAAMJdwEjXwA4AAAAAA==.Calashlar:BAAALgAECgIJBAAAAA==.Camri:BAAALgADCgMJAwAAAA==.Capwnd:BAAALgAECgMJAwAAAA==.',
Ce='Cerryan:BAABLgAECn8YAAINAAYJyQrBJAAhAQANAAYJyQrBJAAhAQAAAA==.',
Ch='Charivium:BAAALgADCgQJBAAAAA==.Chaòs:BAAALgADCgMJAwAAAA==.Chinup:BAABLgAECn8pAAIOAAgJcSEPBQDoAQAOAAgJcSEPBQDoAQAAAA==.',
Cl='Clother:BAACLgAFFH8QAAMPAAUJxxlGBACxAQAPAAUJ6RhGBACxAQAQAAQJnhr3AQBkAQAuAAQKfxoAAw8ACAkEIf8KAAQDAA8ACAkEIf8KAAQDABAABgnmIGAHAEkCAAAA.',
Co='Cokenopepsi:BAAALgAECgcJEgAAAA==.',
Cr='Crackle:BAAALgADCgcJDAAAAA==.Crazyhorse:BAAALgAECgYJCwAAAA==.Cristos:BAAALgADCgYJBgAAAA==.',
Cu='Curses:BAAALgAECggJEAAAAA==.',
['Cø']='Cøløssus:BAAALgAECgEJAQAAAA==.',
Da='Daddypie:BAABLgAECn8jAAMRAAcJYSRTAQBwAgARAAcJQCRTAQBwAgASAAEJcB0oKQBVAAABLgAECggJJwATAMYeAA==.Darkdesire:BAAALgADCgUJBQAAAA==.',
Di='Disney:BAABLgAECn8WAAIGAAcJsBLOCgCDAQAGAAcJsBLOCgCDAQAAAA==.',
Dj='Djaztech:BAABLgAECn8VAAMPAAgJeR7rGQB8AgAPAAgJeR7rGQB8AgAQAAEJXRTdPAA+AAAAAA==.',
Do='Donkie:BAABLgAECn8YAAIJAAYJECCMJwAbAgAJAAYJECCMJwAbAgAAAA==.',
Dr='Dragndeznuts:BAAALgAECgYJBgABLgAECggJEAACAAAAAA==.Dreamzz:BAAALgADCgMJAwAAAA==.Drixadin:BAAALgAECgQJBwAAAA==.Drshockêr:BAABLgAECn8jAAMLAAgJJwghCQBYAQALAAgJJwghCQBYAQAMAAUJ3AsFNQDkAAAAAA==.',
Ds='Dsakony:BAAALgAECggJDgAAAA==.',
Du='Duthir:BAACLgAFFH8FAAIDAAMJ3wyuNwDvAAADAAMJ3wyuNwDvAAAuAAQKfyUAAgMACAnRGso/ADkCAAMACAnRGso/ADkCAAAA.',
Ea='East:BAAALgAECgYJEwAAAA==.',
Ed='Edd:BAAALgAECgEJAQAAAA==.',
Eg='Egrok:BAAALgAECgYJEAAAAA==.',
Em='Emaeel:BAAALgAECgYJCgAAAA==.',
En='Envyqt:BAAALgADCgEJAQAAAA==.',
Es='Esso:BAAALgAFFAMJBAAAAA==.',
Fa='Faelenor:BAAALgAECgYJCAAAAA==.Faelure:BAABLgAECn8XAAIIAAcJiAm0XwD1AAAIAAcJiAm0XwD1AAAAAA==.',
Fi='Fiddleoux:BAAALgAECgYJEAAAAA==.Fiending:BAAALgAECgEJAQAAAA==.Finnarius:BAAALgADCgYJBgAAAA==.Firenze:BAAALgAECgYJDQAAAA==.',
Fo='Foros:BAABLgAECn8ZAAINAAYJryUqEACSAgANAAYJryUqEACSAgAAAA==.',
Fr='Frozone:BAABLgAECn8YAAIUAAUJqBjjdADtAAAUAAUJqBjjdADtAAAAAA==.Fryiertuck:BAAALgAECgYJCgAAAA==.',
Ga='Gabil:BAABLgAECn8WAAIVAAYJjwoRCAAEAQAVAAYJjwoRCAAEAQAAAA==.Gaunshots:BAAALgAECgQJBwABLgAECggJEAACAAAAAA==.',
Ge='Gendorosan:BAABLgAECn8WAAIWAAYJoCTnDAA7AgAWAAYJoCTnDAA7AgAAAA==.',
Gn='Gnork:BAAALgAECgYJEAAAAA==.',
Go='Goldwolf:BAAALgADCgYJBgAAAA==.Gotarrnianan:BAAALgAECgEJAQAAAA==.',
Gr='Grandmasterx:BAAALgAECgIJAwAAAA==.Gravewurm:BAAALgAECgEJAQAAAA==.Grayfoxx:BAABLgAECn8WAAIDAAYJoxgsNABoAQADAAYJoxgsNABoAQAAAA==.Grayhard:BAAALgAECgYJBwAAAA==.Greenhornn:BAAALgADCgQJBAAAAA==.Grìmmgor:BAACLgAFFH8MAAIXAAMJaCOqAAA2AQAXAAMJaCOqAAA2AQAuAAQKfysAAhcACQmDIksAAIgDABcACQmDIksAAIgDAAAA.',
['Gô']='Gôôdbye:BAAALgAECgYJCgAAAA==.',
['Gö']='Gööse:BAAALgAECgEJAQAAAA==.',
Ha='Hado:BAAALgAECgQJBAAAAA==.Halbrand:BAABLgAECn8aAAIDAAgJphnDHQDVAQADAAgJphnDHQDVAQAAAA==.Hamburgmeat:BAAALgADCgYJBQAAAA==.',
He='Healovathyme:BAABLgAECn8ZAAIWAAgJcSLPCgBbAgAWAAgJcSLPCgBbAgAAAA==.Hellstomper:BAAALgAECgIJAwAAAA==.Heygrlhey:BAABLgAECn8kAAMJAAgJLB+0CABuAgAJAAgJLB+0CABuAgAKAAQJRweWYAC+AAAAAA==.',
Ho='Holdstillbro:BAAALgADCgEJAQABLgAECggJKQAOAHEhAA==.',
Hu='Hukkaluzul:BAAALgAECgEJAQAAAA==.Humaladin:BAAALgAECgEJAQAAAA==.Hungryghost:BAAALgAECgkJCwAAAA==.Hunna:BAAALgAECgYJDQAAAA==.Hurtzdonit:BAAALgADCgIJAgAAAA==.',
Hv='Hvtn:BAAALgAECgYJCgAAAA==.',
Ic='Icyfractals:BAAALgADCgQJBQAAAA==.',
In='Inebriated:BAAALgAECgYJEQAAAA==.',
Io='Iondia:BAAALgAECgQJBgAAAA==.',
Is='Iselune:BAAALgAECgIJAgAAAA==.',
Iz='Izanami:BAAALgAECgEJAQAAAA==.',
Ja='Jambi:BAAALgAECgMJBgAAAA==.Jandrina:BAAALgADCgYJCgAAAA==.Jardran:BAAALgAECgEJAgAAAA==.',
Jo='Joanchokkea:BAAALgADCgcJDgAAAA==.Joankorel:BAAALgADCgkJCQAAAA==.Jolty:BAAALgAECgEJAQABLgAFFAIJBwADAH8iAA==.',
Ka='Kael:BAAALgAECgEJAQAAAA==.Kahira:BAEALgADCgQJBAAAAA==.Kalidra:BAAALgAECgMJAwAAAA==.Kaname:BAAALgADCgYJCQABLgAECgUJEAACAAAAAA==.',
Ki='Kirlo:BAAALgADCgcJDQAAAA==.Kittytiddies:BAAALgADCgUJBQAAAA==.',
Ko='Kobethama:BAAALgAECgEJAwAAAA==.Kohnan:BAAALgAECgYJEQAAAA==.Kotoko:BAAALgAECgcJCwAAAA==.',
Ks='Ksauce:BAAALgAECgUJCAAAAA==.',
Ky='Kynan:BAAALgAFFAIJAgABLgAECgMJAwACAAAAAA==.Kynon:BAAALgAECgYJEwABLgAECgMJAwACAAAAAA==.Kyran:BAAALgAECgMJAwAAAA==.',
La='Laerai:BAAALgADCgcJDAAAAA==.Lament:BAAALgAECgYJBgAAAA==.Lamurun:BAAALgADCgEJAgAAAA==.Lancelöt:BAABLgAECn82AAIIAAgJnCUtAwD1AgAIAAgJnCUtAwD1AgAAAA==.Lathina:BAAALgAECgMJAwAAAA==.Lavendere:BAAALgAECgYJBwABLgAFFAMJBQADAN8MAA==.',
Le='Lectra:BAAALgADCgEJAQAAAA==.Leechang:BAAALgADCgMJAwAAAA==.',
Li='Liiam:BAAALgADCgYJBgAAAA==.Linafox:BAAALgAECgYJCwAAAA==.Linnëa:BAAALgAECggJEQAAAA==.Linta:BAAALgADCgcJCQAAAA==.',
Ll='Llonia:BAAALgADCgMJAwAAAA==.',
Lo='Lockraum:BAAALgAECgIJAgAAAA==.Lokix:BAABLgAECn8ZAAIDAAYJAyHEHADbAQADAAYJAyHEHADbAQAAAA==.',
Lu='Luexis:BAAALgADCgkJFgAAAA==.Luobo:BAAALgADCgQJBQAAAA==.Lustie:BAAALgADCgMJAwAAAA==.',
Ly='Lysistratta:BAABLgAECn8WAAIOAAYJKQnkFwC+AAAOAAYJKQnkFwC+AAAAAA==.',
Ma='Magikishi:BAABLgAECn8cAAIUAAgJWx8xOwCKAgAUAAgJWx8xOwCKAgAAAA==.Magimal:BAAALgAECgYJBgABLgAECgYJCgACAAAAAA==.Mahka:BAABLgAECn8rAAMWAAkJPRi2IwAsAgAWAAkJPRi2IwAsAgAYAAMJHiNKGQAzAQABLgADCgEJAQACAAAAAA==.Maldrakesus:BAAALgADCgEJAQABLgAECgYJCgACAAAAAA==.Malifecent:BAAALgAECgMJAwAAAA==.Manthalus:BAAALgAECgIJAgAAAA==.Marquista:BAAALgADCgkJLAAAAA==.',
Mc='Mchammer:BAAALgADCgMJAwAAAA==.',
Me='Meatball:BAAALgAECgMJAwAAAA==.Meganstoon:BAAALgAECgEJAQAAAA==.Meladaris:BAAALgADCggJCAAAAA==.Mey:BAABLgAECn8qAAITAAgJiRntEQBSAgATAAgJiRntEQBSAgAAAA==.',
Mi='Misfortune:BAAALgADCgUJBQAAAA==.Missperfect:BAAALgAECgYJDwAAAA==.Mitenalla:BAAALgAFFAMJBAAAAA==.',
Mu='Muatahawa:BAAALgADCggJEQAAAA==.Muglackh:BAAALgAECgcJEwAAAA==.',
My='Myoue:BAAALgAECgMJBAAAAA==.Mysticraven:BAAALgAECgcJAQAAAA==.',
Na='Nagendra:BAABLgAECn8XAAIZAAkJESDoBwD7AgAZAAkJESDoBwD7AgAAAA==.Natharion:BAAALgADCgUJCgAAAA==.',
Ne='Neoptolemos:BAAALgAECgEJAgAAAA==.Nezpak:BAAALgADCgcJEAAAAA==.',
Ni='Nicnevin:BAAALgAECgYJDAAAAA==.Nitrochrist:BAABLgAECn8nAAIBAAgJbRbqHADGAQABAAgJbRbqHADGAQAAAA==.Nixxy:BAAALgADCgcJDgABLgAFFAQJCwAaAKEUAA==.',
No='Nokansee:BAAALgADCgQJBAAAAA==.Nokimi:BAAALgAECgQJBAAAAA==.Noobru:BAAALgAECgYJDwAAAA==.Nordathair:BAAALgAECgYJDAAAAA==.Nori:BAACLgAFFH8aAAIUAAYJ+CZNAQBAAgAUAAYJ+CZNAQBAAgAuAAQKfyMAAxQACQmeJpoAAPwDABQACQmeJpoAAPwDABsAAwkSILgPAMcAAAAA.',
Ob='Oblivion:BAAALgADCgQJBAAAAA==.',
On='Onebuttonman:BAAALgAECgEJAQAAAA==.Onlyfoxes:BAAALgAECgIJAgAAAA==.',
Or='Original:BAAALgAECgIJAgAAAA==.Originals:BAAALgAECgMJAwAAAA==.',
Ot='Otome:BAAALgAECgEJAQAAAA==.',
Pa='Painfulpoo:BAAALgAECgIJAgAAAA==.Parsemae:BAABLgAECn8jAAMUAAgJth1oLwC0AgAUAAgJth1oLwC0AgAcAAEJHQ+vEAAxAAAAAA==.Pastries:BAACLgAFFH8WAAIEAAYJKSBIAgAyAgAEAAYJKSBIAgAyAgAuAAQKfzAAAgQACQmrIrkCAKUDAAQACQmrIrkCAKUDAAAA.',
Pb='Pbd:BAAALgAECgIJAgAAAA==.',
Pi='Pitlin:BAABLgAECn8fAAIdAAgJ8iHHAQASAwAdAAgJ8iHHAQASAwAAAA==.',
Pm='Pmsavenger:BAAALgADCgkJEgAAAA==.',
Po='Polynya:BAAALgAECgQJBQAAAA==.Pooshot:BAAALgAECgYJCwAAAA==.',
Pr='Priestalisha:BAACLgAFFH8RAAITAAUJICNSAQDVAQATAAUJICNSAQDVAQAuAAQKfyYAAhMACQmiJPEAAIMDABMACQmiJPEAAIMDAAAA.Prognie:BAAALgADCgcJCAAAAA==.',
Ra='Raelana:BAABLgAECn8YAAIIAAYJVQi6WgABAQAIAAYJVQi6WgABAQAAAA==.Ragetatertot:BAAALgAECgYJCgAAAA==.Ragingpoo:BAABLgAECn8UAAIDAAkJfxODGAD3AQADAAkJfxODGAD3AQAAAA==.Rakenroll:BAAALgADCggJCAAAAA==.Rawsteak:BAAALgAECgYJEQAAAA==.Razdaz:BAABLgAECn8UAAMdAAcJgB39FQD0AQAdAAYJxhv9FQD0AQATAAcJOhbZEwB1AQAAAA==.',
Re='Redcrow:BAAALgAECgYJBgAAAA==.Reheal:BAAALgAECgUJCwAAAA==.Reshocker:BAABLgAECn8kAAIeAAgJsBvFGgA9AgAeAAgJsBvFGgA9AgAAAA==.Restosexualz:BAAALgAECgIJAgAAAA==.',
Ri='Rixxy:BAACLgAFFH8LAAIaAAQJoRS/CABdAQAaAAQJoRS/CABdAQAuAAQKfycAAxoACAmVIkcCAFEDABoACAmVIkcCAFEDABkABwmqC8A+AO8AAAAA.',
Ro='Roastbeefdr:BAABLgAECn8mAAIOAAgJjyPnAQBgAgAOAAgJjyPnAQBgAgAAAA==.Roderigo:BAABLgAECn8WAAIWAAYJ0xIWJgBVAQAWAAYJ0xIWJgBVAQAAAA==.Root:BAAALgAECgYJEQAAAA==.',
Ru='Runian:BAAALgAECgQJBAAAAA==.',
Sa='Sadlypink:BAABLgAECn8VAAIUAAcJJxRLhwDDAQAUAAcJJxRLhwDDAQAAAA==.Saisaith:BAAALgADCgMJAwABLgAFFAMJBQADAN8MAA==.Sanarian:BAAALgADCgMJAwAAAA==.Sand:BAABLgAECn8dAAIDAAcJ8RQ1aAC9AQADAAcJ8RQ1aAC9AQAAAA==.Sandy:BAAALgAECgcJAwAAAA==.Savadar:BAAALgAECgYJBgAAAA==.Saymourcox:BAAALgAECgUJBwAAAA==.',
Se='Seadra:BAAALgADCggJDQABLgAECgYJFAAHAMoZAA==.Sealyboi:BAAALgADCgQJBAAAAA==.Serpeng:BAAALgAECgYJDAAAAA==.Setareh:BAABLgAECn8UAAIUAAYJxweycAD3AAAUAAYJxweycAD3AAAAAA==.Settra:BAAALgADCgcJDAAAAA==.',
Sh='Shakuru:BAABLgAECn8hAAIUAAgJpA7yMACgAQAUAAgJpA7yMACgAQAAAA==.Shanta:BAAALgADCgMJAwAAAA==.Shkar:BAABLgAECn8zAAIPAAkJyxYuBgBRAgAPAAkJyxYuBgBRAgAAAA==.Shokan:BAAALgADCgQJBwAAAA==.',
Si='Silanah:BAAALgADCgEJAQAAAA==.Silandrya:BAAALgADCggJCwAAAA==.Sildin:BAAALgAECgQJBAAAAA==.Silverclaws:BAAALgADCgUJBQAAAA==.',
Sj='Sjaridin:BAEALgAECgQJCAAAAA==.',
Sk='Skittle:BAAALgAECgQJCgAAAA==.Skullhunter:BAAALgAFFAMJAwAAAA==.',
Sl='Slenderama:BAAALgADCgMJAwAAAA==.',
Sm='Smawbrawl:BAAALgADCgkJDwAAAA==.Smoothroller:BAAALgAECgEJAQAAAA==.',
So='Sogen:BAAALgADCgMJAwAAAA==.',
St='Staysalty:BAAALgADCgEJAQAAAA==.Stickyricky:BAAALgADCgUJBQAAAA==.Strongmandan:BAAALgAECgEJAQAAAA==.Stubs:BAAALgADCgYJDAAAAA==.',
Su='Sule:BAEBLgAECn8qAAIUAAkJYA8lJgDOAQAUAAkJYA8lJgDOAQAAAA==.',
Sw='Sweetpea:BAAALgAFFAEJAQABLgAFFAMJBQAHAAkBAA==.',
['Sä']='Sämuel:BAAALgADCgEJAQAAAA==.',
Ta='Tanks:BAAALgADCgEJAgAAAA==.',
Th='Thelorax:BAAALgAECggJDwAAAA==.Theyeti:BAAALgADCgEJAQABLgADCgcJDQACAAAAAA==.Thhee:BAABLgAECn8VAAIfAAYJPBSbEwBBAQAfAAYJPBSbEwBBAQAAAA==.Thumbelyna:BAABLgAECn8WAAMWAAYJqx7wEwDnAQAWAAYJqx7wEwDnAQAgAAEJMQrvNQAeAAAAAA==.',
Ts='Tsuro:BAAALgAECgUJBgAAAA==.',
Tu='Tukktukk:BAAALgAECgEJAQAAAA==.',
Ty='Tyrini:BAAALgADCgIJAgAAAA==.',
Um='Umie:BAAALgAECgEJAQAAAA==.',
Un='Unholylife:BAAALgAECgYJEAAAAA==.',
Up='Up:BAABLgAECn8VAAIRAAcJUx/oBABjAgARAAcJUx/oBABjAgAAAA==.',
Va='Valasi:BAAALgAECgEJAgAAAA==.',
Ve='Velocet:BAABLgAECn8pAAMfAAgJfBp5FQBkAgAfAAgJfBp5FQBkAgAGAAMJiAi5FgCLAAAAAA==.Vetlance:BAAALgAECgQJBQAAAA==.',
Vo='Voroak:BAAALgADCgYJBgAAAA==.',
Wa='Waghdaddy:BAABLgAECn8kAAIIAAkJFCLGAgAAAwAIAAkJFCLGAgAAAwAAAA==.',
Wh='Whatøncewas:BAAALgAFFAEJAQAAAA==.Whitfield:BAAALgADCgUJBQAAAA==.Whordie:BAAALgAECgEJAQAAAA==.',
Wi='Wildlily:BAAALgADCgkJCQABLgAECgYJEAACAAAAAA==.Wistful:BAAALgAECgQJBwAAAA==.',
Wo='Wobiwabi:BAAALgADCgIJAgAAAA==.',
Wr='Wratheon:BAABLgAECn8nAAMhAAkJtRXPDAC+AQAhAAkJtRXPDAC+AQAiAAEJAADojQAWAAAAAA==.',
Wu='Wuji:BAABLgAECn8YAAIdAAYJQA1UFgA+AQAdAAYJQA1UFgA+AQAAAA==.',
['Wê']='Wêrewôlf:BAAALgADCgUJBQAAAA==.',
Xa='Xablau:BAAALgADCgkJCwAAAA==.',
Ye='Yeli:BAAALgADCgcJDAAAAA==.',
Ze='Zenaf:BAAALgAECgUJBwAAAA==.Zeryph:BAAALgADCgYJCwABLgAECgMJAwACAAAAAA==.',
Zi='Zimbabway:BAAALgAECgYJBgAAAA==.',
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

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

local lookup = {'Unknown-Unknown','DeathKnight-Unholy','DemonHunter-Devourer','Warrior-Protection','Rogue-Assassination','Paladin-Protection','Paladin-Retribution','Hunter-BeastMastery','Hunter-Marksmanship','Shaman-Enhancement','Shaman-Restoration','DeathKnight-Blood','Warrior-Fury','Warrior-Arms','DemonHunter-Vengeance','Priest-Holy','DeathKnight-Frost','Druid-Balance','Mage-Frost','Druid-Restoration','Evoker-Augmentation','Warlock-Demonology','Evoker-Preservation','Mage-Arcane','Mage-Fire','Priest-Discipline','Shaman-Elemental','Druid-Guardian','Rogue-Subtlety','Monk-Brewmaster','Monk-Windwalker',}
local provider = {region='US',realm='TwistingNether',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Abharn:BAAALgAECgMJAwAAAA==.',
Ak='Akeera:BAAALgAECgYJDgAAAA==.Akkiya:BAAALgAECgYJDwABLgAFFAEJAQABAAAAAA==.',
Am='Amalyn:BAAALgAECgYJCAAAAA==.Amarantha:BAAALgAECgYJCwAAAA==.',
An='Anaesthetize:BAAALgADCgYJCwAAAA==.Aness:BAAALgAECgQJBAAAAA==.Animaker:BAABLgAECn8fAAICAAgJyhNIUgD7AQACAAgJyhNIUgD7AQAAAA==.Anvilkrash:BAAALgADCgcJCwAAAA==.',
Ar='Ariese:BAAALgADCgEJAQAAAA==.',
As='Ashido:BAAALgAECgMJAwAAAA==.Astrikin:BAAALgAECgYJDwABLgAFFAYJFwADAKAfAA==.',
Au='Auraiel:BAAALgADCgcJFAAAAA==.Aurorastar:BAAALgAECgEJAQAAAA==.',
Ba='Baultier:BAAALgADCgkJDgAAAA==.',
Be='Bel:BAABLgAECn8gAAIEAAgJmyC5AACOAgAEAAgJmyC5AACOAgAAAA==.Beraxes:BAAALgAECgUJCAAAAA==.',
Bl='Blasser:BAABLgAECn8WAAIFAAYJcyHSBQAoAgAFAAYJcyHSBQAoAgAAAA==.Blizizdumz:BAABLgAECn8XAAMGAAQJmSFmFwBeAQAHAAQJGB82iwBkAQAGAAQJ0SBmFwBeAQAAAA==.',
Br='Bralindra:BAAALgAECgEJAgAAAA==.Brewdhism:BAAALgAECgMJAwAAAA==.',
Bu='Bulsy:BAABLgAECn8XAAMIAAgJRhWgEQBwAQAIAAgJRhWgEQBwAQAJAAQJkATZaACbAAAAAA==.',
Ca='Calamidade:BAABLgAECn8fAAMKAAgJ5wM0FQBpAQAKAAgJ5wM0FQBpAQALAAEJ5gChqgAhAAAAAA==.Calashlar:BAAALgAECgIJAwAAAA==.Camri:BAAALgADCgMJAwAAAA==.Capwnd:BAAALgAECgMJAgAAAA==.',
Ce='Cerryan:BAAALgAECgYJEgAAAA==.',
Ch='Chaòs:BAAALgADCgMJAwAAAA==.Chinup:BAABLgAECn8hAAIMAAgJ6x8ECACnAgAMAAgJ6x8ECACnAgAAAA==.',
Cl='Clother:BAACLgAFFH8OAAMNAAUJThlBBACxAQANAAUJbxhBBACxAQAOAAQJnhr0AQBkAQAuAAQKfxkAAw0ACAkEIQELAAQDAA0ACAkEIQELAAQDAA4ABgnmIF0HAEkCAAAA.',
Co='Cokenopepsi:BAAALgAECgYJEQAAAA==.',
Cr='Crackle:BAAALgADCgcJDAAAAA==.Crazyhorse:BAAALgAECgYJCwAAAA==.Cristos:BAAALgADCgYJBgAAAA==.',
Cu='Curses:BAAALgAECgYJDgAAAA==.',
['Cø']='Cøløssus:BAAALgAECgEJAQAAAA==.',
Da='Daddypie:BAABLgAECn8bAAIPAAcJmCE3AwCpAgAPAAcJmCE3AwCpAgABLgAECggJIAAQAPgbAA==.Darkdesire:BAAALgADCgUJBQAAAA==.',
Di='Disney:BAABLgAECn8VAAIFAAcJsRDOCgCDAQAFAAcJsRDOCgCDAQAAAA==.',
Dj='Djaztech:BAABLgAECn8VAAMNAAgJeR7vGQB8AgANAAgJeR7vGQB8AgAOAAEJXRTaPAA+AAAAAA==.',
Do='Donkie:BAAALgAECgYJEgAAAA==.',
Dr='Dreamzz:BAAALgADCgMJAwAAAA==.Drixadin:BAAALgAECgQJBwAAAA==.Drshockêr:BAABLgAECn8bAAMKAAgJ0QdPBQBLAQAKAAgJ0QdPBQBLAQALAAUJ3AvnFgDxAAAAAA==.',
Ds='Dsakony:BAAALgAECgcJCgAAAA==.',
Du='Duthir:BAABLgAECn8gAAICAAgJ0RrFPwA5AgACAAgJ0RrFPwA5AgAAAA==.',
Ea='East:BAAALgAECgYJDQAAAA==.',
Ed='Edd:BAAALgAECgEJAQAAAA==.',
Eg='Egrok:BAAALgAECgQJCgAAAA==.',
Em='Emaeel:BAAALgAECgYJCgAAAA==.',
En='Envyqt:BAAALgADCgEJAQAAAA==.',
Es='Esso:BAAALgAFFAEJAQAAAA==.',
Fa='Faelenor:BAAALgAECgYJCAAAAA==.Faelure:BAABLgAECn8XAAIHAAcJiAk3KQD+AAAHAAcJiAk3KQD+AAAAAA==.',
Fi='Fiddleoux:BAAALgAECgYJDQAAAA==.Fiending:BAAALgAECgEJAQAAAA==.Finnarius:BAAALgADCgYJBgAAAA==.Firenze:BAAALgAECgYJDQAAAA==.',
Fo='Foros:BAAALgAECgYJEwAAAA==.',
Fr='Frozone:BAAALgAECgUJDwAAAA==.Fryiertuck:BAAALgAECgYJCgAAAA==.',
Ga='Gabil:BAAALgAECgYJEAAAAA==.Gaunshots:BAAALgAECgQJBwABLgAECgYJDgABAAAAAA==.',
Ge='Gendorosan:BAAALgAECgYJEAAAAA==.',
Gn='Gnork:BAAALgAECgYJCgAAAA==.',
Go='Goldwolf:BAAALgADCgYJBgAAAA==.',
Gr='Grandmasterx:BAAALgAECgIJAwAAAA==.Grayfoxx:BAAALgAECgYJEAAAAA==.Grayhard:BAAALgAECgYJBwAAAA==.Greenhornn:BAAALgADCgQJBAAAAA==.Grìmmgor:BAACLgAFFH8JAAIRAAMJ1CGqAAA2AQARAAMJ1CGqAAA2AQAuAAQKfysAAhEACQmDIksAAIgDABEACQmDIksAAIgDAAAA.',
['Gô']='Gôôdbye:BAAALgAECgYJCgAAAA==.',
Ha='Hado:BAAALgAECgMJAgAAAA==.Halbrand:BAABLgAECn8WAAICAAcJmxZJFABwAQACAAcJmxZJFABwAQABLgAECggJHwASANggAA==.Hamburgmeat:BAAALgADCgYJBQAAAA==.',
He='Healovathyme:BAAALgAECgcJEgAAAA==.Hellstomper:BAAALgADCgkJFAAAAA==.Heygrlhey:BAABLgAECn8cAAMIAAgJnRwHBABFAgAIAAgJnRwHBABFAgAJAAQJRweeYAC+AAAAAA==.',
Ho='Holdstillbro:BAAALgADCgEJAQABLgAECggJIQAMAOsfAA==.',
Hu='Hukkaluzul:BAAALgAECgEJAQAAAA==.Humaladin:BAAALgAECgEJAQAAAA==.Hungryghost:BAAALgAECgkJCwAAAA==.Hunna:BAAALgAECgUJBgAAAA==.Hurtzdonit:BAAALgADCgIJAgAAAA==.',
Hv='Hvtn:BAAALgAECgUJBwAAAA==.',
Ic='Icyfractals:BAAALgADCgQJBQAAAA==.',
In='Inebriated:BAAALgAECgYJEQAAAA==.',
Io='Iondia:BAAALgAECgQJBgAAAA==.',
Is='Iselune:BAAALgAECgIJAgAAAA==.',
Iz='Izanami:BAAALgAECgEJAQAAAA==.',
Ja='Jambi:BAAALgAECgMJBgAAAA==.Jandrina:BAAALgADCgYJCgAAAA==.Jardran:BAAALgAECgEJAgAAAA==.',
Jo='Joanchokkea:BAAALgADCgcJDgAAAA==.Joankorel:BAAALgADCgkJCQAAAA==.Jolty:BAAALgADCgkJEQABLgAFFAIJBQACAI4eAA==.',
Ka='Kael:BAAALgAECgEJAQAAAA==.Kahira:BAEALgADCgQJBAAAAA==.Kalidra:BAAALgAECgMJAwAAAA==.Kaname:BAAALgADCgYJCQABLgAECgUJEAABAAAAAA==.',
Ki='Kirlo:BAAALgADCgcJDQAAAA==.Kittehkat:BAAALgAECgQJBgAAAA==.Kittytiddies:BAAALgADCgUJBQAAAA==.',
Ko='Kobethama:BAAALgAECgEJAgAAAA==.Kohnan:BAAALgAECgYJCwAAAA==.Kotoko:BAAALgAECgYJCgAAAA==.',
Ks='Ksauce:BAAALgAECgMJAwAAAA==.',
Ky='Kynan:BAAALgAFFAIJAgAAAA==.Kynon:BAAALgAECgYJEwABLgAFFAIJAgABAAAAAA==.',
La='Laerai:BAAALgADCgcJDAAAAA==.Lancelöt:BAABLgAECn8vAAIHAAgJkCQuAQDWAgAHAAgJkCQuAQDWAgAAAA==.Lathina:BAAALgAECgMJAwAAAA==.Lavendere:BAAALgAECgYJBgABLgAECggJIAACANEaAA==.',
Le='Lectra:BAAALgADCgEJAQAAAA==.Leechang:BAAALgADCgMJAwAAAA==.',
Li='Liiam:BAAALgADCgYJBgAAAA==.Linafox:BAAALgAECgMJBAAAAA==.Linnëa:BAAALgAECggJEAAAAA==.Linta:BAAALgADCgcJCQAAAA==.',
Ll='Llonia:BAAALgADCgMJAwAAAA==.',
Lo='Lockraum:BAAALgAECgEJAQAAAA==.Lokix:BAAALgAECgYJEwAAAA==.',
Lu='Luexis:BAAALgADCgkJFgAAAA==.Luobo:BAAALgADCgQJBQAAAA==.Lustie:BAAALgADCgMJAwAAAA==.',
Ly='Lysistratta:BAAALgAECgYJEAAAAA==.',
Ma='Magikishi:BAABLgAECn8bAAITAAgJWx8sOwCKAgATAAgJWx8sOwCKAgAAAA==.Mahka:BAABLgAECn8iAAMUAAgJ6xm0IwAsAgAUAAgJ6xm0IwAsAgASAAMJFBozUADnAAABLgADCgEJAQABAAAAAA==.Maldrakesus:BAAALgADCgEJAQABLgAECgYJCgABAAAAAA==.Malifecent:BAAALgAECgMJAwAAAA==.Manthalus:BAAALgAECgIJAgAAAA==.Marquista:BAAALgADCgkJIwAAAA==.',
Mc='Mchammer:BAAALgADCgMJAwAAAA==.',
Me='Meatball:BAAALgAECgMJAwAAAA==.Meladaris:BAAALgADCgYJBgAAAA==.Mey:BAABLgAECn8jAAIQAAgJiRnnEQBSAgAQAAgJiRnnEQBSAgAAAA==.',
Mi='Misfortune:BAAALgADCgUJBQAAAA==.Missperfect:BAAALgAECgYJCgAAAA==.Mitenalla:BAAALgAFFAEJAQAAAA==.',
Mo='Morninbreath:BAAALgADCgYJCwAAAA==.',
Mu='Muatahawa:BAAALgADCggJEQAAAA==.Muglackh:BAAALgAECgcJEwAAAA==.',
My='Myoue:BAAALgAECgMJBAAAAA==.',
Na='Nagendra:BAABLgAECn8XAAIVAAkJESDkBwD7AgAVAAkJESDkBwD7AgAAAA==.Natharion:BAAALgADCgUJCgAAAA==.',
Ne='Neoptolemos:BAAALgADCgMJAwAAAA==.Nezpak:BAAALgADCgcJEAAAAA==.',
Ni='Nicnevin:BAAALgAECgQJBQAAAA==.Nitrochrist:BAABLgAECn8fAAIWAAgJpxRtRgD4AQAWAAgJpxRtRgD4AQAAAA==.Nixxy:BAAALgADCgcJDgABLgAFFAQJBwAXABASAA==.',
No='Nokansee:BAAALgADCgQJBAAAAA==.Noobru:BAAALgAECgYJDwAAAA==.Nordathair:BAAALgAECgYJBwAAAA==.Nori:BAACLgAFFH8UAAITAAYJrSZyAAAUAgATAAYJrSZyAAAUAgAuAAQKfyMAAxMACQmeJpgAAPwDABMACQmeJpgAAPwDABgAAwkSILUPAMcAAAAA.',
Ob='Oblivion:BAAALgADCgQJBAAAAA==.',
On='Onebuttonman:BAAALgAECgEJAQAAAA==.Onlyfoxes:BAAALgAECgIJAgAAAA==.',
Ot='Otome:BAAALgADCgYJBgAAAA==.',
Pa='Painfulpoo:BAAALgAECgIJAgAAAA==.Parsemae:BAABLgAECn8eAAMTAAgJth1lLwC0AgATAAgJth1lLwC0AgAZAAEJHQ+tEAAxAAAAAA==.Pastries:BAACLgAFFH8XAAIDAAYJoB/8AADLAQADAAYJoB/8AADLAQAuAAQKfzEAAgMACQmrIrYCAKUDAAMACQmrIrYCAKUDAAAA.',
Pi='Pitlin:BAABLgAECn8bAAIaAAcJMCL7AAC+AgAaAAcJMCL7AAC+AgAAAA==.',
Pm='Pmsavenger:BAAALgADCgkJEgAAAA==.',
Po='Polynya:BAAALgAECgQJBQAAAA==.Pooshot:BAAALgAECgYJCwAAAA==.',
Pr='Priestalisha:BAACLgAFFH8MAAIQAAQJiSOyAQClAQAQAAQJiSOyAQClAQAuAAQKfx4AAhAACAk3JvEAAIMDABAACAk3JvEAAIMDAAAA.Prognie:BAAALgADCgcJCAAAAA==.',
Ra='Raelana:BAAALgAECgYJEgAAAA==.Ragetatertot:BAAALgAECgQJBAAAAA==.Ragingpoo:BAAALgAECggJEQAAAA==.Rakenroll:BAAALgADCggJCAAAAA==.Rawsteak:BAAALgAECgYJCwAAAA==.Razdaz:BAAALgAECgYJDgAAAA==.',
Re='Redcrow:BAAALgADCgcJBwAAAA==.Reheal:BAAALgAECgUJBQAAAA==.Reshocker:BAABLgAECn8gAAIbAAgJ+xnEGgA8AgAbAAgJ+xnEGgA8AgAAAA==.Restosexualz:BAAALgADCgYJBgAAAA==.',
Ri='Rixxy:BAACLgAFFH8HAAIXAAQJEBK2CABdAQAXAAQJEBK2CABdAQAuAAQKfycAAxcACAmVIkkCAFEDABcACAmVIkkCAFEDABUABwmqC7w+AO8AAAAA.',
Ro='Roastbeefdr:BAABLgAECn8eAAIMAAgJjiG6AACYAgAMAAgJjiG6AACYAgAAAA==.Roderigo:BAAALgAECgYJCwAAAA==.Root:BAAALgAECgQJDwAAAA==.',
Ru='Runian:BAAALgADCgcJFQAAAA==.',
Sa='Sadlypink:BAABLgAECn8VAAITAAcJJxRahwDDAQATAAcJJxRahwDDAQAAAA==.Saisaith:BAAALgADCgMJAwABLgAECggJIAACANEaAA==.Sanarian:BAAALgADCgMJAwAAAA==.Sand:BAABLgAECn8ZAAICAAcJExM6aAC9AQACAAcJExM6aAC9AQAAAA==.Sandy:BAAALgAECgcJAgAAAA==.Saymourcox:BAAALgAECgUJBgAAAA==.',
Se='Seadra:BAAALgADCggJDQABLgAECgYJDgABAAAAAA==.Sealyboi:BAAALgADCgQJBAAAAA==.Serpeng:BAAALgAECgYJBgAAAA==.Setareh:BAAALgAECgYJDgAAAA==.Settra:BAAALgADCgcJDAAAAA==.',
Sh='Shakuru:BAABLgAECn8ZAAITAAgJZQu+FACcAQATAAgJZQu+FACcAQAAAA==.Shanta:BAAALgADCgMJAwAAAA==.Shkar:BAABLgAECn8qAAINAAkJPxUjAgBJAgANAAkJPxUjAgBJAgAAAA==.Shokan:BAAALgADCgQJBwAAAA==.',
Si='Silanah:BAAALgADCgEJAQAAAA==.Silandrya:BAAALgADCgcJBgAAAA==.',
Sj='Sjaridin:BAEALgAECgQJBAABLgAFFAQJDAAcACkBAA==.',
Sk='Skullhunter:BAAALgAFFAEJAQAAAA==.',
Sm='Smawbrawl:BAAALgADCgkJDwAAAA==.Smoothroller:BAAALgAECgEJAQAAAA==.',
So='Sogen:BAAALgADCgMJAwAAAA==.',
St='Staysalty:BAAALgADCgEJAQAAAA==.Stickyricky:BAAALgADCgUJBQAAAA==.Strongmandan:BAAALgAECgEJAQAAAA==.Stubs:BAAALgADCgYJDAAAAA==.',
Su='Sule:BAEBLgAECn8hAAITAAgJDRCAGwBvAQATAAgJDRCAGwBvAQAAAA==.',
Sw='Sweetpea:BAAALgAFFAEJAQABLgAFFAIJAwABAAAAAA==.',
['Sä']='Sämuel:BAAALgADCgEJAQAAAA==.',
Ta='Tanks:BAAALgADCgEJAgAAAA==.',
Th='Thelorax:BAAALgAECgYJCgAAAA==.Thhee:BAAALgAECgUJDwAAAA==.Thumbelyna:BAAALgAECgYJEAAAAA==.',
Ts='Tsuro:BAAALgAECgQJBAAAAA==.',
Tu='Tukktukk:BAAALgAECgEJAQAAAA==.',
Ty='Tyrini:BAAALgADCgIJAgAAAA==.',
Um='Umie:BAAALgAECgEJAQAAAA==.',
Un='Unholylife:BAAALgAECgQJCgAAAA==.',
Up='Up:BAABLgAECn8VAAIPAAcJUx/qBABjAgAPAAcJUx/qBABjAgAAAA==.',
Va='Valasi:BAAALgAECgEJAQAAAA==.',
Ve='Velocet:BAABLgAECn8fAAMdAAgJfBp8FQBkAgAdAAgJfBp8FQBkAgAFAAMJiAi5FgCLAAAAAA==.Vetlance:BAAALgAECgQJBQAAAA==.',
Vo='Voroak:BAAALgADCgYJBgAAAA==.',
Wa='Waghdaddy:BAABLgAECn8bAAIHAAgJaR8ABQBMAgAHAAgJaR8ABQBMAgAAAA==.',
Wh='Whatøncewas:BAAALgAFFAEJAQAAAA==.Whitfield:BAAALgADCgUJBQAAAA==.Whordie:BAAALgAECgEJAQAAAA==.',
Wi='Wildlily:BAAALgADCgkJCQABLgAECgYJEAABAAAAAA==.Wistful:BAAALgAECgQJBwAAAA==.',
Wo='Wobiwabi:BAAALgADCgIJAgAAAA==.',
Wr='Wratheon:BAABLgAECn8kAAMeAAkJtRU2JQDZAQAeAAkJtRU2JQDZAQAfAAEJAADfjQAWAAAAAA==.',
Wu='Wuji:BAAALgAECgYJEgAAAA==.',
['Wê']='Wêrewôlf:BAAALgADCgUJBQAAAA==.',
Xa='Xablau:BAAALgADCgkJCwAAAA==.',
Ye='Yeli:BAAALgADCgcJDAAAAA==.',
Ze='Zenaf:BAAALgAECgUJBwAAAA==.Zeryph:BAAALgADCgYJCwABLgAECgcJHAAEAEoeAA==.',
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

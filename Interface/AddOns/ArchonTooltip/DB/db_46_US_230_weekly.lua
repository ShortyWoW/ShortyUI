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

local lookup = {'Warlock-Demonology','Unknown-Unknown','Shaman-Restoration','Shaman-Elemental','Paladin-Holy','Evoker-Augmentation','Evoker-Preservation','Druid-Guardian','DemonHunter-Havoc','Druid-Restoration','Warrior-Protection','Warrior-Arms','Paladin-Retribution','Paladin-Protection','Monk-Brewmaster','Shaman-Enhancement','Warlock-Destruction','Priest-Shadow','Priest-Holy','Mage-Frost','DeathKnight-Unholy','Monk-Windwalker','DeathKnight-Blood','Warrior-Fury','Monk-Mistweaver','DemonHunter-Devourer','Warlock-Affliction','DemonHunter-Vengeance','Hunter-BeastMastery','Hunter-Marksmanship','Druid-Balance','Druid-Feral','Rogue-Subtlety','Rogue-Assassination','Evoker-Devastation',}
local provider = {region='US',realm='Undermine',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Abaddon:BAAALgAECgUJCQAAAA==.',
Ac='Acidtears:BAAALgADCgcJDQAAAA==.Ackris:BAABLgAECn8lAAIBAAkJ/BwFCgAuAwABAAkJ/BwFCgAuAwAAAA==.',
Al='Aleathris:BAEALgADCgcJBwABLgAECgQJBAACAAAAAA==.Alka:BAAALgADCgEJAQAAAA==.Alor:BAAALgAECgEJAgABLgAECgcJFgADAAEQAA==.Alpyne:BAAALgAECgcJEgAAAA==.',
Am='Amaimon:BAAALgAECgcJCwABLgAFFAUJDQAEADYQAA==.Amnoon:BAABLgAECn8VAAIFAAYJexB9EAA2AQAFAAYJexB9EAA2AQAAAA==.Amri:BAABLgAECn8bAAMGAAgJcRaaFQAuAgAGAAgJcRaaFQAuAgAHAAMJDAXHPACEAAABLgAECggJHgAIANodAA==.',
Aq='Aquas:BAAALgAECgEJAQAAAA==.',
Ar='Ardrhys:BAAALgADCgkJDQAAAA==.Arthurcarrot:BAAALgAECgQJBwAAAA==.Artikin:BAAALgAECgEJAQABLgAFFAMJBgAJAHIQAA==.',
As='Assasinateu:BAAALgADCgMJAwAAAA==.Asûná:BAAALgAECgIJAgAAAA==.',
At='Atreus:BAABLgAECn8ZAAIJAAYJYiABGAAHAgAJAAYJYiABGAAHAgAAAA==.Atzalan:BAABLgAECn8UAAIKAAYJpgnxcwD7AAAKAAYJpgnxcwD7AAAAAA==.',
Av='Avondwella:BAABLgAECn8dAAMLAAgJRQ9yGACRAQALAAgJRQ9yGACRAQAMAAEJ+wm7RAAvAAAAAA==.',
Az='Azrikam:BAAALgAECgEJAgAAAA==.',
Ba='Baldyguy:BAAALgADCgcJCgAAAA==.Balm:BAABLgAECn8bAAIKAAYJPhvsNADUAQAKAAYJPhvsNADUAQAAAA==.Balton:BAAALgADCgQJBAAAAA==.Bashalot:BAAALgAECgUJBgAAAA==.',
Be='Bearooter:BAAALgADCgUJCAABLgAFFAQJDQAHAGUkAA==.Bermin:BAAALgADCgUJAwAAAA==.',
Bi='Biblepimp:BAAALgAECgQJBAAAAA==.',
Bl='Blackmarker:BAAALgAECgYJCgAAAA==.',
Bm='Bmo:BAABLgAECn8VAAINAAcJZSB6SAAJAgANAAcJZSB6SAAJAgAAAA==.',
Bo='Bodyguardwyn:BAAALgADCgQJBQAAAA==.Bogle:BAABLgAECn8hAAIOAAgJmSNjAAC3AgAOAAgJmSNjAAC3AgAAAA==.Bonedmuch:BAAALgADCgUJCgABLgAECgYJFQAPAEgUAA==.Bow:BAAALgAECgIJAwAAAA==.',
Br='Brasi:BAAALgAECgIJAgAAAA==.Bratton:BAAALgAECgQJBgAAAA==.Bremitin:BAAALgADCggJCAABLgAECgYJGAAOALkQAA==.Bremitus:BAAALgADCgkJCQABLgAECgYJGAAOALkQAA==.Brewmongster:BAAALgAECgQJBQAAAA==.Brimscythe:BAAALgAECgYJEgAAAA==.Brud:BAAALgAECgIJAgAAAA==.Brunstan:BAAALgAFFAIJAwAAAA==.',
Bu='Bubbastump:BAAALgAECgQJBAAAAA==.',
By='Byakugan:BAACLgAFFH8NAAIEAAUJNhBaBQCIAQAEAAUJNhBaBQCIAQAuAAQKfxsABAQACQk6H5QPAK8CAAQACQk6H5QPAK8CABAAAQm+F7wpAEEAAAMAAQkHAfyoACUAAAAA.',
['Bø']='Bønitalèè:BAAALgAECgYJDgAAAA==.',
Ca='Calvisichaos:BAABLgAECn8VAAIRAAYJ1BQrBAAbAQARAAYJ1BQrBAAbAQAAAA==.Cantero:BAAALgADCgUJBQAAAA==.Canthen:BAAALgAECgUJBgAAAA==.Capillidan:BAAALgAECgEJAQAAAA==.Carcarnisa:BAAALgAECgQJBgAAAA==.',
Ce='Cenobia:BAAALgADCgUJCQAAAA==.',
Ch='Chaire:BAAALgADCgcJBgAAAA==.Chariena:BAAALgAECgQJDgAAAA==.Chrysophylax:BAAALgAECgEJAQAAAA==.',
Co='Conky:BAAALgAECgMJBgAAAA==.Corndog:BAAALgADCgEJAQAAAA==.Cornix:BAAALgADCgEJAQAAAA==.Cosmicspark:BAAALgAECgEJAQAAAA==.',
Cr='Crentist:BAAALgAECgEJAQAAAA==.Cropala:BAABLgAECn8WAAINAAcJyxJzZAC4AQANAAcJyxJzZAC4AQAAAA==.',
Da='Daca:BAAALgADCgMJAwAAAA==.Dave:BAAALgADCgQJBAAAAA==.Davros:BAAALgAECgMJBAAAAA==.',
De='Deleto:BAAALgAECgIJBAAAAA==.Delta:BAAALgAECgYJEQAAAA==.Demony:BAAALgAECgEJAQAAAA==.Denard:BAAALgAECgUJBgAAAA==.',
Di='Diabolist:BAAALgAECggJDgAAAA==.Digichowder:BAAALgAECgYJCwAAAA==.Dirtygiri:BAAALgADCgEJAgAAAA==.',
Do='Doktaga:BAAALgAECgEJAQAAAA==.',
Dr='Draex:BAAALgADCgEJAQAAAA==.Dragonzord:BAAALgADCgEJAQAAAA==.Drbubbles:BAAALgADCgYJCAABLgAECgQJCQACAAAAAA==.Drredd:BAAALgAECgQJBAAAAA==.',
Eg='Eggfield:BAAALgADCgIJAwAAAA==.',
El='Eladora:BAAALgADCgEJAQAAAA==.Eldarr:BAABLgAECn8WAAIRAAYJliDqAADiAQARAAYJliDqAADiAQAAAA==.Eldhe:BAAALgADCgkJFQAAAA==.Eleos:BAAALgADCgMJBgAAAA==.Elistrae:BAAALgAECgYJEAAAAA==.',
Em='Emorri:BAAALgAECgYJBgAAAA==.',
En='Enazen:BAAALgAECgYJDAAAAA==.Endlol:BAABLgAECn8eAAMSAAgJKiL/AQBNAgASAAcJqiH/AQBNAgATAAEJWB+xGQBeAAABLgAFFAEJAQACAAAAAA==.',
Er='Eredaria:BAAALgADCgkJCQAAAA==.Ereshkigal:BAAALgADCgYJCwAAAA==.Ergo:BAACLgAFFH8JAAIUAAUJ1A03DwCeAQAUAAUJ1A03DwCeAQAuAAQKfx4AAhQACQnyHxojAOYCABQACQnyHxojAOYCAAAA.Eronel:BAAALgAECgYJDwAAAA==.',
Ex='Excido:BAAALgAECgEJAQAAAA==.',
Fa='Fadedharanir:BAAALgADCgMJBgAAAA==.Fadedmystic:BAAALgADCgkJEAAAAA==.Fadednight:BAABLgAECn8aAAIVAAYJBxytZQDDAQAVAAYJBxytZQDDAQAAAA==.Faeyir:BAABLgAECn8aAAIUAAgJ5BpGUABGAgAUAAgJ5BpGUABGAgAAAA==.Fallingmoon:BAAALgAECgYJDAAAAA==.Fatherlode:BAABLgAECn8hAAIUAAgJkiGBAwCQAgAUAAgJkiGBAwCQAgAAAA==.',
Fe='Femcelibate:BAAALgADCgcJCAAAAA==.Fentenjoyer:BAAALgAECgQJBAAAAA==.Fernfondler:BAAALgAFFAEJAQAAAA==.',
Fo='Forcebolt:BAAALgADCgMJAwAAAA==.',
Fr='Fredgoffin:BAAALgAECgIJAgAAAA==.Freecookies:BAAALgAECgYJCQAAAA==.Frostybrews:BAAALgAECgEJAQABLgAECgMJAwACAAAAAA==.Frostydh:BAAALgAECgMJAwAAAA==.Frostytotems:BAAALgADCgEJAQAAAA==.Fróstblight:BAAALgAECgcJBgAAAA==.',
Fu='Furryiosa:BAAALgADCgYJBgAAAA==.',
Ga='Gauntodimm:BAAALgADCgUJBQAAAA==.',
Gi='Gilberticus:BAAALgAECgEJAQABLgAECggJHQAWAFAYAA==.Gishmou:BAABLgAECn8YAAIDAAcJrBknCQCyAQADAAcJrBknCQCyAQAAAA==.',
Go='Goldblade:BAAALgAECgcJEQAAAA==.',
Gr='Greyoll:BAAALgAECgUJBQAAAA==.Grindlewald:BAAALgAECgIJAgAAAA==.',
Gu='Gutted:BAACLgAFFH8OAAIXAAUJESbZAAAmAgAXAAUJESbZAAAmAgAuAAQKfxsAAhcACQnbJbkBAGcDABcACQnbJbkBAGcDAAAA.',
['Gä']='Gärin:BAAALgADCggJFAAAAA==.',
Hi='Highly:BAAALgADCgcJCwAAAA==.',
Ho='Hollowheart:BAAALgAECgYJDAAAAA==.Holycourtney:BAAALgADCgkJEQAAAA==.Hoved:BAAALgADCgEJAQAAAA==.',
Hy='Hylanna:BAAALgAECgUJBgAAAA==.Hyorinmaru:BAAALgAECgIJAgAAAA==.',
['Hó']='Hónor:BAAALgADCgMJAwABLgAECgYJGAAOALkQAA==.',
Ic='Ici:BAABLgAECn8WAAINAAYJawZELQDpAAANAAYJawZELQDpAAAAAA==.',
If='Iffybacon:BAAALgAECgIJAgABLgAECgQJCwACAAAAAA==.',
Im='Imlerith:BAAALgADCgQJBAAAAA==.',
In='Intensifies:BAAALgAECgYJDAAAAA==.',
Ip='Ippo:BAAALgADCgEJAQAAAA==.',
Is='Iskothar:BAAALgAECgYJBgAAAA==.',
Iv='Ivarboneless:BAAALgAECgEJAQAAAA==.',
Ja='Jackz:BAAALgADCgQJBAAAAA==.Jakethemage:BAAALgADCgUJCAAAAA==.',
Je='Jefftrep:BAAALgAECgIJAgAAAA==.Jerihatrix:BAAALgAECgEJAQAAAA==.',
Ji='Jimmylahey:BAAALgAECgMJAwAAAA==.',
Jo='Jonah:BAAALgADCgEJAQAAAA==.',
Ka='Kaina:BAAALgADCgYJCQAAAA==.Kakidruid:BAAALgAECgIJAwAAAA==.',
Ke='Ketesh:BAABLgAECn8eAAIIAAgJ2h3SBACaAgAIAAgJ2h3SBACaAgAAAA==.',
Ki='Kilorean:BAAALgAECgYJBgAAAA==.',
Kn='Knastey:BAAALgAECgYJDQAAAA==.Knasty:BAAALgADCgEJAQAAAA==.',
Ko='Kodera:BAAALgAECgIJAwAAAA==.',
Kr='Krej:BAAALgAECgYJBwABLgAFFAMJBgAJAHIQAA==.Krisskringle:BAAALgAECgMJBgAAAA==.',
Ku='Kuromori:BAAALgADCgYJBgAAAA==.',
La='Langarde:BAAALgAECgYJDAAAAA==.Laoghaire:BAAALgAECgQJBgAAAA==.',
Le='Leonz:BAACLgAFFH8LAAIYAAUJZhm/AwC4AQAYAAUJZhm/AwC4AQAuAAQKfyEAAhgACQnnH+sJABADABgACQnnH+sJABADAAAA.Leonzs:BAAALgAECgUJCAAAAA==.Letharanos:BAEBLgAECn8cAAIVAAgJ5Ri+CgDTAQAVAAgJ5Ri+CgDTAQAAAA==.',
Li='Liraffemynn:BAABLgAECn8iAAIZAAgJbyMjAQC7AgAZAAgJbyMjAQC7AgAAAA==.Liralynn:BAAALgADCgUJBQAAAA==.',
Lk='Lkynyx:BAAALgADCgYJAQAAAA==.',
Lo='Lostinlight:BAAALgAECgYJBgAAAA==.',
Lu='Luckylucy:BAAALgAECgIJBAAAAA==.',
Ma='Madarauchiha:BAAALgAECgYJDQAAAA==.Maldran:BAABLgAECn8VAAIDAAYJ/B00BgD2AQADAAYJ/B00BgD2AQAAAA==.Maling:BAAALgAECgEJAQAAAA==.Manderpants:BAAALgAECgQJBwAAAA==.Marien:BAAALgAECgYJDAAAAA==.Marty:BAAALgAECgIJAwAAAA==.Maxus:BAAALgADCgUJBQAAAA==.',
Mb='Mbbin:BAAALgAECggJDgAAAA==.',
Me='Mehuman:BAAALgAECgEJAQAAAA==.Mehumanhuntr:BAAALgADCggJCwAAAA==.Mehumanlock:BAAALgAECgYJEwAAAA==.Merran:BAAALgADCgEJAQAAAA==.Metal:BAAALgADCgQJBAAAAA==.Meworgendk:BAAALgADCgkJCQAAAA==.',
Mh='Mhoo:BAAALgADCgcJBwAAAA==.',
Mi='Miriym:BAAALgADCgEJAQAAAA==.Miräj:BAAALgADCgMJAwAAAA==.Mistyblue:BAAALgADCgEJAQAAAA==.Miya:BAAALgADCgcJDQAAAA==.',
Mo='Mordaci:BAAALgADCgQJBQABLgAECgYJCAACAAAAAA==.Mortstan:BAAALgADCgYJBgAAAA==.',
['Mé']='Mélusine:BAAALgADCgEJAQAAAA==.',
Na='Nailia:BAAALgAECgUJCQAAAA==.Nailz:BAABLgAECn8YAAIaAAcJtxVITQDAAQAaAAcJtxVITQDAAQAAAA==.Nasaug:BAAALgADCgYJBgABLgAECgYJGAAOALkQAA==.',
Ne='Ned:BAAALgADCgkJFAAAAA==.Neuse:BAAALgAECgUJDAAAAA==.',
Ni='Nightlion:BAAALgAECgEJAQAAAA==.Nillius:BAAALgADCgIJAgAAAA==.Nisu:BAAALgAECgEJAQAAAA==.',
No='Noahdh:BAAALgAECgMJAwABLgAFFAUJDQABAM8YAA==.Noahpriest:BAAALgAECgMJAwABLgAFFAUJDQABAM8YAA==.Noahvoker:BAAALgAECgcJBwABLgAFFAUJDQABAM8YAA==.Noahwarlock:BAACLgAFFH8NAAMBAAUJzxhIDwBkAQABAAQJWB1IDwBkAQARAAEJNgsjBQBXAAAuAAQKfxwABBEACQl+I0EaAHsBABEABAl0IkEaAHsBAAEABgmuIqEdAC8BABsAAgnmI4AWAM0AAAAA.Nonsensical:BAAALgADCgUJBQAAAA==.Nook:BAAALgADCgUJBgAAAA==.',
Ny='Nym:BAAALgAECggJEAAAAA==.',
['Nâ']='Nârenth:BAAALgADCgMJAwAAAA==.',
Oa='Oaths:BAAALgAECgYJCAAAAA==.',
Oh='Ohmylantä:BAABLgAECn8UAAIUAAcJzwte1gBCAQAUAAcJzwte1gBCAQAAAA==.Ohmylantå:BAAALgADCgUJCAAAAA==.',
On='Onumae:BAAALgAECggJEQAAAA==.',
Op='Oprime:BAAALgADCgMJAwAAAA==.',
Or='Orbeck:BAAALgADCgQJBAABLgAFFAUJDgAPAEMeAA==.Oriax:BAAALgADCgMJAwAAAA==.Ormond:BAAALgADCgYJDgAAAA==.Orochinchin:BAAALgAECgMJAwABLgAFFAUJDgAXABEmAA==.',
Os='Oscarmike:BAAALgADCgcJDQAAAA==.',
Oz='Ozlon:BAAALgAECgYJCwAAAA==.',
['Oâ']='Oâth:BAABLgAECn8WAAIcAAYJsQ1oBQDiAAAcAAYJsQ1oBQDiAAAAAA==.',
Pa='Pallywacker:BAAALgAECgYJEAAAAA==.Pankins:BAAALgAECgMJAwAAAA==.',
Pe='Percymorris:BAAALgADCgYJBwAAAA==.',
Pi='Pigishdog:BAABLgAECn8fAAIBAAgJShTcCgDHAQABAAgJShTcCgDHAQAAAA==.Pikon:BAAALgADCgkJDQAAAA==.',
Po='Pokeabear:BAAALgAECgYJEAABLgAECgcJCgACAAAAAA==.Pokethemonk:BAAALgAECgEJBAAAAA==.Poshingtang:BAABLgAECn8fAAQEAAgJvg+1NgB4AQAEAAcJTw+1NgB4AQADAAgJCgU7EQAyAQAQAAMJSwP9JQB3AAAAAA==.',
Pu='Punchies:BAAALgADCggJDQAAAA==.',
Qu='Quatrain:BAABLgAECn8WAAIDAAcJARCKQgB3AQADAAcJARCKQgB3AQAAAA==.',
Ra='Ragerunner:BAAALgADCgkJEwAAAA==.Rakarg:BAAALgAECgUJEQAAAA==.Ravenus:BAAALgADCgcJFgAAAA==.',
Re='Refund:BAAALgAECgEJAQAAAA==.Regalbacon:BAAALgAECgMJAwAAAA==.Reygina:BAAALgAECgYJDgAAAA==.',
Ri='Rickÿ:BAAALgADCgYJCAAAAA==.Riprock:BAAALgADCgkJCgAAAA==.Rixas:BAAALgADCgQJBAABLgAECgkJJQABAPwcAA==.',
Rn='Rn:BAEBLgAECn8bAAMMAAkJJSI/AQBGAwAMAAkJuyE/AQBGAwAYAAcJLyMeKQAXAgABLgAFFAYJDQAMAC0gAA==.',
Ro='Roguehiro:BAABLgAECn8YAAIOAAcJkR42BwBuAgAOAAcJkR42BwBuAgAAAA==.Rooter:BAACLgAFFH8NAAIHAAQJZSRVAQC4AQAHAAQJZSRVAQC4AQAuAAQKfyUAAgcACAm2I4QAANwCAAcACAm2I4QAANwCAAAA.',
Ru='Ruikhai:BAAALgADCgMJBQABLgADCgkJBwACAAAAAA==.Ruto:BAAALgADCgYJCgAAAA==.',
Sa='Saelis:BAAALgAFFAIJBAAAAA==.Samshara:BAAALgADCgcJDAABLgAECgYJEwACAAAAAA==.Saracenio:BAAALgADCgEJAQAAAA==.',
Sc='Schnem:BAAALgAECgUJBgAAAA==.',
Se='Securìty:BAAALgAECgQJBQAAAA==.Selyane:BAAALgADCgkJCQAAAA==.Senia:BAAALgADCgIJAgAAAA==.Seong:BAACLgAFFH8OAAIPAAUJQx6BAwCoAQAPAAUJQx6BAwCoAQAuAAQKfxsAAg8ACQlYIgMFADkDAA8ACQlYIgMFADkDAAAA.Seongdh:BAAALgAECgUJBQAAAA==.Seongwar:BAAALgAECgMJAwAAAA==.Seraphinà:BAAALgAECgEJAQABLgAECgYJDAACAAAAAA==.',
Sh='Shadowdooms:BAAALgAECgcJEgAAAA==.Shadowfur:BAAALgADCgkJCQABLgAECgYJEwACAAAAAA==.Shii:BAAALgADCgUJBQAAAA==.Shimera:BAABLgAECn8VAAIdAAYJrRQcFwBDAQAdAAYJrRQcFwBDAQAAAA==.Shish:BAAALgAECgMJAwAAAA==.Shockawar:BAACLgAFFH8NAAIYAAUJeRwtAwDEAQAYAAUJeRwtAwDEAQAuAAQKfxQAAhgACQlFHnAYAIgCABgACQlFHnAYAIgCAAAA.Shooter:BAAALgADCgIJAgAAAA==.Shootrmcgavn:BAACLgAFFH8GAAMdAAMJKSDABQAhAQAeAAMJIiCoEAAqAQAdAAMJdRvABQAhAQAuAAQKfxcAAx0ACAk7IdUVAIkCAB0ABwnxIdUVAIkCAB4ABwlKIWIaAFMCAAAA.Shu:BAAALgAFFAIJAgAAAA==.Shuletaa:BAAALgAECgIJBAAAAA==.Shïsh:BAAALgADCgcJBwABLgAECgMJAwACAAAAAA==.',
Si='Sinestra:BAAALgAECgEJAQAAAA==.',
Sk='Skofung:BAAALgADCgEJAQAAAA==.',
Sl='Slaughterhse:BAAALgAECgUJCgAAAA==.Slootar:BAABLgAECn8UAAQKAAcJ5xuDJAAoAgAKAAcJ5xuDJAAoAgAfAAIJuxBLbABuAAAgAAIJMAb6MgA1AAAAAA==.Slugs:BAAALgADCgUJBQAAAA==.',
Sn='Snqwflake:BAABLgAECn8VAAIZAAgJ7hb4FQAWAgAZAAgJ7hb4FQAWAgAAAA==.',
So='Solareth:BAAALgADCgQJBAAAAA==.Somebeotch:BAAALgADCgYJBgAAAA==.Somerled:BAAALgAECgYJEwAAAA==.',
Sp='Spyroid:BAAALgAECgUJAQAAAA==.',
St='Static:BAAALgADCgcJBwABLgAECgYJCAACAAAAAA==.',
Su='Sunstrike:BAAALgADCgEJBAAAAA==.',
Sy='Sylvanna:BAAALgADCgQJBAAAAA==.',
Ta='Takka:BAAALgAECgQJCAAAAA==.Talden:BAABLgAECn8eAAMNAAgJnhfrCQDuAQANAAgJnhfrCQDuAQAOAAEJ+wW2RAAsAAAAAA==.Talkamar:BAABLgAECn8VAAIWAAYJTQ+vNQBJAQAWAAYJTQ+vNQBJAQAAAA==.Taylorswift:BAABLgAECn8VAAIUAAYJuhaOIABSAQAUAAYJuhaOIABSAQAAAA==.Tazzaar:BAAALgAECgMJAwAAAA==.',
Th='Thekourge:BAABLgAECn8VAAIOAAYJ6gieJgDUAAAOAAYJ6gieJgDUAAAAAA==.Thenard:BAAALgAECgUJCAAAAA==.Thukunaenhan:BAAALgADCgcJCgABLgAECggJHgAUABUdAA==.Thukunamage:BAABLgAECn8eAAIUAAgJFR3MCgAAAgAUAAgJFR3MCgAAAgAAAA==.',
Ti='Tibarius:BAAALgADCgkJEgAAAA==.Tinaraeda:BAAALgAECgIJAgAAAA==.',
To='Tomislav:BAAALgAECgYJDAAAAA==.Touritos:BAAALgAECgUJDQAAAA==.',
Tr='Troyka:BAAALgAECgEJAQAAAA==.Truefitt:BAAALgAECgQJCAAAAA==.',
Tu='Tuskal:BAAALgAECgEJAQAAAA==.',
Tw='Twogora:BAAALgAECgQJBQAAAA==.',
Ty='Tydes:BAABLgAECn8ZAAMhAAgJ6RbMEwB4AgAhAAgJ6RbMEwB4AgAiAAEJqQs9HQBBAAAAAA==.Tyler:BAACLgAFFH8HAAIaAAQJfhXNDwBPAQAaAAQJfhXNDwBPAQAuAAQKfx4AAhoACAkOHTUcAKkCABoACAkOHTUcAKkCAAAA.Tystin:BAAALgADCgEJAQABLgADCgkJBwACAAAAAA==.',
Ud='Uddermilk:BAAALgADCgkJEgAAAA==.',
Va='Valina:BAAALgADCgIJAgAAAA==.Valissar:BAAALgADCgcJCgAAAA==.Valr:BAABLgAECn8YAAIOAAYJuRDjHwAJAQAOAAYJuRDjHwAJAQAAAA==.Vandreu:BAAALgADCgUJBQAAAA==.',
Ve='Verpally:BAAALgADCgMJAwAAAA==.',
Vi='Viparia:BAAALgAECgkJAgAAAA==.',
Vo='Voloaura:BAAALgADCgMJAwAAAA==.',
Vs='Vse:BAABLgAECn8kAAIUAAcJPxd+GgB2AQAUAAcJPxd+GgB2AQAAAA==.Vsesosorry:BAAALgAECgYJCgABLgAECgcJJAAUAD8XAA==.Vsè:BAAALgADCgUJBQABLgAECgcJJAAUAD8XAA==.',
['Ví']='Ví:BAAALgAECgYJBgAAAA==.',
Wa='Wammo:BAAALgAECgQJBAAAAA==.Waq:BAAALgADCgMJAwAAAA==.Wardozer:BAAALgAECgUJCQAAAA==.Warlockedin:BAAALgAECgYJCQAAAA==.',
We='Weierstrass:BAAALgAECgQJBAABLgAFFAUJDgAXABEmAA==.',
Wo='Worgenkrantz:BAAALgAECgYJDAAAAA==.',
Wr='Wrenlyn:BAACLgAFFH8GAAIJAAMJchASAgD7AAAJAAMJchASAgD7AAAuAAQKfx8AAwkACAlsHnoEAJIBAAkACAnuGnoEAJIBABwAAQnfIJckAF4AAAAA.',
Xo='Xolòtl:BAABLgAECn8ZAAILAAcJARcUFADLAQALAAcJARcUFADLAQABLgAFFAMJBgAJAHIQAA==.',
Yg='Yggdrasali:BAAALgAECgQJBgABLgAFFAEJAQACAAAAAA==.',
Yi='Yin:BAAALgAECgUJBQAAAA==.',
Ys='Yserra:BAAALgAECgYJCwAAAA==.',
Za='Zakuso:BAAALgAECgQJBwAAAA==.Zalyia:BAABLgAECn8XAAISAAYJZAl2DwD/AAASAAYJZAl2DwD/AAAAAA==.',
Ze='Zephinar:BAABLgAECn8YAAIUAAcJxhhxaQADAgAUAAcJxhhxaQADAgAAAA==.Zexpert:BAABLgAECn8YAAQjAAcJRhidDQAAAgAjAAcJCBidDQAAAgAGAAYJlxYlKAB8AQAHAAQJfgwENADNAAAAAA==.',
Zu='Zulblade:BAABLgAECn8UAAIaAAgJORqHMAA5AgAaAAgJORqHMAA5AgAAAA==.Zulpally:BAABLgAECn8YAAQNAAUJxxM1MADbAAANAAQJzBU1MADbAAAFAAMJyRCAcgCxAAAOAAQJ3AisMQCIAAAAAA==.',
['Zô']='Zôrt:BAAALgAECgQJBAAAAA==.',
['Âr']='Ârtemis:BAAALgADCgkJFAAAAA==.',
['Öâ']='Öâth:BAAALgAECgIJAgAAAA==.',
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

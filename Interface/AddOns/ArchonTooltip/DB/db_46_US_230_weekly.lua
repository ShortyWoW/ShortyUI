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

local lookup = {'Warlock-Demonology','Unknown-Unknown','Shaman-Restoration','Shaman-Elemental','Paladin-Holy','Evoker-Augmentation','Evoker-Preservation','DemonHunter-Havoc','Druid-Restoration','Warrior-Protection','Warrior-Arms','Paladin-Retribution','Paladin-Protection','Monk-Brewmaster','DemonHunter-Devourer','Hunter-Marksmanship','Shaman-Enhancement','Warlock-Destruction','Priest-Shadow','Priest-Holy','Mage-Frost','DeathKnight-Unholy','Hunter-BeastMastery','Monk-Windwalker','DeathKnight-Blood','Druid-Guardian','Warrior-Fury','Monk-Mistweaver','Warlock-Affliction','DemonHunter-Vengeance','Hunter-Survival','DeathKnight-Frost','Druid-Balance','Druid-Feral','Rogue-Subtlety','Rogue-Assassination','Evoker-Devastation',}
local provider = {region='US',realm='Undermine',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abaddon:BAAALgAECgYJDwAAAA==.',
Ac='Acidtears:BAAALgADCgcJDQAAAA==.Ackris:BAABLgAECn8nAAIBAAkJ/BwHCgAuAwABAAkJ/BwHCgAuAwAAAA==.Acris:BAAALgAECgYJCAABLgAECgkJJwABAPwcAA==.',
Al='Aleathris:BAEALgADCgcJBwABLgAECgQJBAACAAAAAA==.Alka:BAAALgADCgEJAQAAAA==.Alor:BAAALgAECgEJAgABLgAECgcJHAADAHEQAA==.Alpyne:BAAALgAECgcJEgAAAA==.',
Am='Amaimon:BAAALgAECggJEwABLgAFFAUJEgAEAEMSAA==.Amnoon:BAABLgAECn8XAAIFAAcJeQ9eHABoAQAFAAcJeQ9eHABoAQAAAA==.Amri:BAACLgAFFH8IAAIGAAMJegt5GQDeAAAGAAMJegt5GQDeAAAuAAQKfxsAAwYACAlxFpwVAC0CAAYACAlxFpwVAC0CAAcAAwkMBcE8AIQAAAAA.',
An='Andarnáurram:BAAALgADCgEJAQAAAA==.',
Aq='Aquas:BAAALgAECgMJBAAAAA==.',
Ar='Ardrhys:BAAALgADCgkJDQAAAA==.Arthurcarrot:BAAALgAECgQJBwAAAA==.Artikin:BAAALgAECgEJAQABLgAFFAQJCgAIAJEUAA==.',
As='Assasinateu:BAAALgADCgMJAwAAAA==.Asûná:BAAALgAECgMJBQAAAA==.',
At='Atreus:BAABLgAECn8cAAIIAAgJTRkFGAAHAgAIAAgJTRkFGAAHAgAAAA==.Atzalan:BAABLgAECn8UAAIJAAYJpgnqcwD7AAAJAAYJpgnqcwD7AAAAAA==.',
Au='Automagic:BAAALgADCgEJAQAAAA==.',
Av='Avondwella:BAABLgAECn8jAAMKAAgJzhB6GACRAQAKAAgJzhB6GACRAQALAAEJ+wnARAAvAAAAAA==.',
Az='Azrikam:BAAALgAECgYJCAAAAA==.',
Ba='Baldyguy:BAAALgADCgcJCgAAAA==.Balm:BAABLgAECn8jAAIJAAcJWRlQHwCGAQAJAAcJWRlQHwCGAQAAAA==.Balton:BAAALgAECgIJAgAAAA==.Bashalot:BAAALgAECgUJBgAAAA==.',
Be='Bearooter:BAAALgADCgUJCAABLgAFFAUJDwAHAKwkAA==.Bermin:BAAALgADCgUJAwAAAA==.',
Bi='Biblepimp:BAAALgAECgQJBAAAAA==.Bigwilly:BAAALgADCgEJAQAAAA==.',
Bl='Blackmarker:BAAALgAECgcJCwAAAA==.',
Bm='Bmo:BAABLgAECn8VAAIMAAcJZSBvSAAJAgAMAAcJZSBvSAAJAgAAAA==.',
Bo='Bodyguardwyn:BAAALgAECgEJAQAAAA==.Bogle:BAABLgAECn8pAAMNAAkJ4CEBAQDGAgANAAgJpSMBAQDGAgAMAAEJghWArABWAAAAAA==.Bonedmuch:BAAALgADCgUJCgABLgAECgcJFwAOABwSAA==.Bow:BAAALgAECgIJAwAAAA==.',
Br='Brasi:BAAALgAECgIJAgAAAA==.Bratton:BAAALgAECgYJDAAAAA==.Bremitin:BAAALgADCggJCAABLgAECgcJIAANAN8OAA==.Bremitus:BAAALgADCgkJCQABLgAECgcJIAANAN8OAA==.Brewcrew:BAAALgAECgkJBwAAAA==.Brewmongster:BAAALgAECgQJBQAAAA==.Brimscythe:BAABLgAECn8XAAIPAAcJQR6uNwAXAgAPAAcJQR6uNwAXAgAAAA==.Brud:BAAALgAECgMJBQAAAA==.Brunstan:BAABLgAFFH8GAAIQAAMJqRaxCAD3AAAQAAMJqRaxCAD3AAAAAA==.',
Bu='Bubbastump:BAAALgAECgQJBAAAAA==.',
By='Byakugan:BAACLgAFFH8SAAIEAAUJQxJfBQCIAQAEAAUJQxJfBQCIAQAuAAQKfxsABAQACQk6H5QPAK8CAAQACQk6H5QPAK8CABEAAQm+F7opAEEAAAMAAQkHAQOpACUAAAAA.',
['Bø']='Bønitalèè:BAAALgAECgYJEwAAAA==.',
Ca='Calvisichaos:BAABLgAECn8XAAISAAcJlhIrBwBCAQASAAcJlhIrBwBCAQAAAA==.Cantero:BAAALgADCgUJBQAAAA==.Canthen:BAAALgAECgYJBwAAAA==.Carcarnisa:BAAALgAECgQJBgAAAA==.',
Ce='Cenobia:BAAALgADCgUJCQAAAA==.',
Ch='Chaire:BAAALgADCgcJBgAAAA==.Chrysophylax:BAAALgAECgEJAQAAAA==.',
Co='Conky:BAAALgAECgMJBgAAAA==.Corndog:BAAALgADCgEJAQAAAA==.Cornix:BAAALgADCgEJAQAAAA==.Cosmicspark:BAAALgAECgEJAQAAAA==.',
Cr='Crentist:BAAALgAECgEJAQAAAA==.Cropala:BAABLgAECn8WAAIMAAcJyxJwZAC4AQAMAAcJyxJwZAC4AQAAAA==.',
Da='Daca:BAAALgADCgMJAwAAAA==.Dave:BAAALgADCgQJBAAAAA==.Davros:BAAALgAECgMJBAAAAA==.',
De='Deleto:BAAALgAECgQJBwAAAA==.Delta:BAABLgAECn8PAAIPAAgJUwakXgCMAAAPAAgJUwakXgCMAAAAAA==.Demony:BAAALgAECgEJAQAAAA==.Denard:BAAALgAECgUJBgAAAA==.',
Di='Diabolist:BAAALgAECggJEAAAAA==.Digichowder:BAAALgAECgcJEQAAAA==.Dirtygiri:BAAALgADCgEJAgAAAA==.',
Do='Doktaga:BAAALgAECgUJCAAAAA==.',
Dr='Draex:BAAALgADCgEJAQAAAA==.Dragonzord:BAAALgADCgEJAQAAAA==.Drbubbles:BAAALgADCgYJCAABLgAECgQJCQACAAAAAA==.Drredd:BAAALgAECgQJBAAAAA==.',
Eg='Eggfield:BAAALgAECgUJBgAAAA==.',
El='Eladora:BAAALgADCgEJAQAAAA==.Eldarr:BAABLgAECn8eAAISAAcJvCEsAQBRAgASAAcJvCEsAQBRAgAAAA==.Eldhe:BAAALgADCgkJFwAAAA==.Eleos:BAAALgADCgMJBgAAAA==.Elistrae:BAAALgAECgcJEgAAAA==.',
Em='Emorri:BAAALgAECgYJBgAAAA==.',
En='Enazen:BAAALgAECgcJDgAAAA==.Endlol:BAABLgAECn8lAAMTAAgJKCI6BQBHAgATAAcJqCE6BQBHAgAUAAEJWB9PNQBcAAABLgAFFAIJAwACAAAAAA==.',
Er='Eredaria:BAAALgAECgEJAQAAAA==.Ereshkigal:BAAALgADCgYJCwAAAA==.Ergo:BAACLgAFFH8NAAIVAAUJKBRFDwCeAQAVAAUJKBRFDwCeAQAuAAQKfyIAAhUACQkXIBcjAOYCABUACQkXIBcjAOYCAAAA.Eronel:BAABLgAECn8WAAIWAAcJpRc9JQCrAQAWAAcJpRc9JQCrAQAAAA==.',
Es='Esv:BAAALgAECgMJAwABLgAFFAMJBQAVADMIAA==.',
Ex='Excido:BAAALgAECgEJAQAAAA==.Exodiagold:BAAALgAECgEJAQAAAA==.',
Fa='Fadedharanir:BAAALgAECgEJAQAAAA==.Fadedmystic:BAAALgADCgkJEAAAAA==.Fadednight:BAABLgAECn8iAAIWAAcJFx6fFwD+AQAWAAcJFx6fFwD+AQAAAA==.Faeyir:BAABLgAECn8fAAIVAAkJohtDUABGAgAVAAkJohtDUABGAgAAAA==.Fallingmoon:BAABLgAECn8UAAMXAAgJXBy7DwAZAgAXAAgJXBy7DwAZAgAQAAEJKRC3igAwAAAAAA==.Fatherlode:BAACLgAFFH8HAAIVAAMJwRjWLwALAQAVAAMJwRjWLwALAQAuAAQKfykAAhUACQmPISYEAP4CABUACQmPISYEAP4CAAAA.',
Fe='Feltpen:BAAALgADCgEJAQAAAA==.Femcelibate:BAAALgADCgcJCAAAAA==.Fentenjoyer:BAAALgAECgUJBgAAAA==.Fernfondler:BAAALgAFFAIJAwAAAA==.',
Fo='Fontane:BAAALgADCgEJAQAAAA==.Forcebolt:BAAALgADCgMJAwAAAA==.',
Fr='Fredgoffin:BAAALgAECgIJAgAAAA==.Freecookies:BAAALgAECgYJCQAAAA==.Frostybop:BAAALgAECgEJAQABLgAECgMJAwACAAAAAA==.Frostybrews:BAAALgAECgEJAQABLgAECgMJAwACAAAAAA==.Frostydh:BAAALgAECgMJAwAAAA==.Frostytotems:BAAALgAECgEJAgAAAA==.Fróstblight:BAAALgAECgcJBwAAAA==.',
Fu='Furryiosa:BAAALgADCgYJBgAAAA==.',
Ga='Gauntodimm:BAAALgAECgUJBQAAAA==.',
Gi='Gilberticus:BAAALgAECgQJBQABLgAECggJJQAYADcbAA==.Gishmou:BAABLgAECn8aAAIDAAgJsBp9DQAWAgADAAgJsBp9DQAWAgAAAA==.',
Go='Goldblade:BAABLgAECn8YAAIMAAcJxhdBIgC9AQAMAAcJxhdBIgC9AQAAAA==.',
Gr='Greyoll:BAAALgAECgYJCAAAAA==.Grindlewald:BAAALgAECgIJAgAAAA==.',
Gu='Gutted:BAACLgAFFH8TAAIZAAUJESbZAAAmAgAZAAUJESbZAAAmAgAuAAQKfxsAAhkACQnWJbwBAGcDABkACQnWJbwBAGcDAAAA.',
['Gä']='Gärin:BAAALgADCggJFAAAAA==.',
Ha='Hanna:BAAALgAECggJCAABLgAFFAUJEwAZABEmAA==.',
He='Hellmaw:BAAALgADCgcJBwAAAA==.',
Hi='Highly:BAAALgADCgcJCwAAAA==.',
Ho='Hollowheart:BAABLgAECn8UAAIDAAgJ+BXQFQC6AQADAAgJ+BXQFQC6AQAAAA==.Holycourtney:BAAALgADCgkJEQAAAA==.Hoved:BAAALgADCgEJAQAAAA==.',
Hy='Hylanna:BAAALgAECgUJBgAAAA==.Hyorinmaru:BAAALgAECgIJAgAAAA==.',
['Hó']='Hónor:BAAALgADCgMJAwABLgAECgcJIAANAN8OAA==.',
Ic='Ici:BAABLgAECn8dAAIMAAcJXgaFWQAEAQAMAAcJXgaFWQAEAQAAAA==.',
If='Iffybacon:BAAALgAECgIJAgABLgAECgQJCwACAAAAAA==.',
Im='Imlerith:BAAALgADCgQJBAAAAA==.',
In='Intensifies:BAAALgAECgYJDAAAAA==.',
Ip='Ippo:BAAALgADCgEJAQAAAA==.',
Is='Iskothar:BAAALgAECgYJDAAAAA==.',
Iv='Ivarboneless:BAAALgAECgQJBQAAAA==.',
Ja='Jackz:BAAALgADCgQJBAAAAA==.Jakethemage:BAAALgADCgUJCAAAAA==.',
Je='Jefftrep:BAAALgAECgIJAgAAAA==.Jerihatrix:BAAALgAECgEJAQAAAA==.',
Ji='Jimmylahey:BAAALgAECgMJAwAAAA==.',
Jo='Jonah:BAAALgADCgEJAQAAAA==.',
Ka='Kaina:BAAALgADCgYJCQAAAA==.Kakidruid:BAAALgAECgIJAwAAAA==.',
Ke='Ketesh:BAABLgAECn8mAAIaAAgJWR8iAgBTAgAaAAgJWR8iAgBTAgABLgAFFAMJCAAGAHoLAA==.',
Ki='Kilorean:BAAALgAECgcJCAAAAA==.',
Kn='Knastey:BAAALgAECgYJDQAAAA==.Knasty:BAAALgADCgEJAQAAAA==.',
Ko='Kodera:BAAALgAECgMJBgAAAA==.',
Kr='Krej:BAAALgAECggJDgABLgAFFAQJCgAIAJEUAA==.Krisskringle:BAAALgAECgMJBgAAAA==.',
Ku='Kuromori:BAAALgADCgYJBgAAAA==.',
['Kê']='Kênpachi:BAAALgAECgYJCAAAAA==.',
La='Langarde:BAAALgAECgcJDgAAAA==.Laoghaire:BAAALgAECgUJCwAAAA==.',
Le='Leonz:BAACLgAFFH8PAAIbAAUJ1BnCAwC4AQAbAAUJ1BnCAwC4AQAuAAQKfyEAAhsACQmrH+wJABADABsACQmrH+wJABADAAAA.Leonzs:BAAALgAECggJEAAAAA==.Letharanos:BAEBLgAECn8jAAIWAAgJcxuQFgAFAgAWAAgJcxuQFgAFAgAAAA==.',
Li='Liraffemynn:BAABLgAECn8mAAIcAAgJ6yNyAQAyAwAcAAgJ6yNyAQAyAwAAAA==.Liralynn:BAAALgADCgUJBQAAAA==.',
Lk='Lkynyx:BAAALgADCgYJAQAAAA==.',
Lo='Lostinlight:BAAALgAECgYJBgAAAA==.',
Lu='Luckylucy:BAAALgAECgMJBQAAAA==.',
Ma='Madarauchiha:BAAALgAECgYJDwAAAA==.Magus:BAAALgADCggJCAABLgAECgMJBAACAAAAAA==.Maldran:BAABLgAECn8XAAIDAAcJhh0cCwA5AgADAAcJhh0cCwA5AgAAAA==.Maling:BAAALgAECgEJAQAAAA==.Manderpants:BAAALgAECgUJDAAAAA==.Marien:BAAALgAECgcJDgAAAA==.Marty:BAAALgAECgIJAwAAAA==.Maxus:BAAALgADCgUJBQAAAA==.',
Mb='Mbbin:BAABLgAECn8gAAIVAAkJ6B94BwDAAgAVAAkJ6B94BwDAAgAAAA==.',
Me='Mehuman:BAAALgAECgMJBAAAAA==.Mehumanhuntr:BAAALgADCggJCwAAAA==.Mehumanlock:BAABLgAECn8aAAISAAcJlxBKBgBYAQASAAcJlxBKBgBYAQAAAA==.Merran:BAAALgADCgEJAQAAAA==.Metal:BAAALgADCgQJBAAAAA==.Meworgendk:BAAALgAECgEJAQAAAA==.',
Mh='Mhoo:BAAALgADCgcJBwAAAA==.',
Mi='Miriym:BAAALgADCgEJAQAAAA==.Miräj:BAAALgADCgMJAwAAAA==.Mistyblue:BAAALgADCgEJAQAAAA==.Miya:BAAALgADCgcJDQAAAA==.',
Mo='Mordaci:BAAALgADCgQJBQABLgAECgcJCQACAAAAAA==.Mortstan:BAAALgAECgUJBQAAAA==.',
['Mé']='Mélusine:BAAALgADCgEJAQAAAA==.',
Na='Nailia:BAAALgAECgUJCQAAAA==.Nailz:BAABLgAECn8aAAIPAAgJxRZOIgBlAQAPAAgJxRZOIgBlAQAAAA==.Narie:BAAALgADCgEJAQAAAA==.Nasaug:BAAALgADCgYJBgABLgAECgcJIAANAN8OAA==.',
Ne='Ned:BAAALgAECgEJAQAAAA==.Neuse:BAAALgAECgYJDQAAAA==.',
Ni='Nightlion:BAAALgAECgQJBQAAAA==.Nillius:BAAALgADCgIJAgAAAA==.Nisu:BAAALgAECgEJAQAAAA==.',
No='Noahdh:BAAALgAECgMJAwABLgAFFAUJEQABAOcZAA==.Noahpriest:BAAALgAECgMJAwABLgAFFAUJEQABAOcZAA==.Noahvoker:BAAALgAECggJDwABLgAFFAUJEQABAOcZAA==.Noahwarlock:BAACLgAFFH8RAAMBAAUJ5xlODwBkAQABAAQJzB5ODwBkAQASAAEJNgsGDgBWAAAuAAQKfxwABBIACQllIz8aAHsBAAEABgmOImViAKMBABIABAl0Ij8aAHsBAB0AAgnmI4EWAM0AAAAA.Nonsensical:BAAALgADCgUJBQAAAA==.Nook:BAAALgADCgUJBgAAAA==.',
Ny='Nym:BAAALgAECgkJEQAAAA==.',
['Nâ']='Nârenth:BAAALgADCgMJAwAAAA==.',
Oa='Oaths:BAAALgAECgcJCQAAAA==.',
Oh='Ohmylantä:BAABLgAECn8VAAIVAAcJ5Atj1gBCAQAVAAcJ5Atj1gBCAQAAAA==.Ohmylantå:BAAALgADCgUJCAAAAA==.',
On='Onumae:BAAALgAECggJEwAAAA==.',
Op='Oprime:BAAALgADCgMJAwAAAA==.',
Or='Orbeck:BAAALgADCgQJBAABLgAFFAUJEwAOAJggAA==.Oriax:BAAALgADCgMJAwAAAA==.Ormond:BAAALgADCgYJDgAAAA==.Orochinchin:BAAALgAECgMJAwABLgAFFAUJEwAZABEmAA==.',
Os='Oscarmike:BAAALgADCgcJDQAAAA==.',
Oz='Ozlon:BAAALgAECgYJDQAAAA==.',
['Oâ']='Oâth:BAABLgAECn8aAAIeAAgJOgtpCAAnAQAeAAgJOgtpCAAnAQAAAA==.',
Pa='Pachane:BAAALgAECgMJAwAAAA==.Pallywacker:BAABLgAECn8UAAINAAYJEAk6GACjAAANAAYJEAk6GACjAAAAAA==.Pankins:BAAALgAECgMJAwAAAA==.Panzerkan:BAAALgAECgEJAQAAAA==.',
Pe='Percymorris:BAAALgADCgYJBwAAAA==.',
Pi='Pigishdog:BAABLgAECn8rAAIBAAgJBhhfFAACAgABAAgJBhhfFAACAgAAAA==.Pikon:BAAALgADCgkJDQAAAA==.',
Po='Pokeabear:BAAALgAECgYJEAABLgAECgcJDQACAAAAAA==.Pokethemonk:BAAALgAECgEJBQAAAA==.Poshingtang:BAABLgAECn8mAAQDAAgJzg2wGQCVAQADAAgJzg2wGQCVAQAEAAgJHRG6NgB4AQARAAMJSwP7JQB3AAAAAA==.',
Pu='Pulsar:BAAALgADCgcJBwAAAA==.Punchies:BAAALgADCggJDQAAAA==.',
Qu='Quatrain:BAABLgAECn8cAAIDAAcJcRCKQgB3AQADAAcJcRCKQgB3AQAAAA==.',
Ra='Rabidbutt:BAAALgAECgMJBQABLgAFFAUJDwAHAKwkAA==.Ragerunner:BAAALgADCgkJEwAAAA==.Rakarg:BAABLgAECn8VAAIWAAUJ9BUzVQADAQAWAAUJ9BUzVQADAQAAAA==.Ravenus:BAAALgADCgcJGAAAAA==.',
Re='Refund:BAAALgAECgEJAQAAAA==.Regalbacon:BAAALgAECgMJAwAAAA==.Reygina:BAAALgAECgYJDgAAAA==.',
Ri='Rickÿ:BAAALgAECgEJAQAAAA==.Rixas:BAAALgADCgQJBAABLgAECgkJJwABAPwcAA==.',
Rn='Rn:BAEBLgAECn8bAAMLAAkJJSJBAQBGAwALAAkJuyFBAQBGAwAbAAcJLyMiKQAXAgABLgAFFAYJEwALANUhAA==.',
Ro='Roguehiro:BAABLgAECn8YAAINAAcJkR43BwBuAgANAAcJkR43BwBuAgAAAA==.Rooter:BAACLgAFFH8PAAIHAAUJrCR4AQAcAgAHAAUJrCR4AQAcAgAuAAQKfyUAAgcACAm2I8MEAAMDAAcACAm2I8MEAAMDAAAA.Rosalynñ:BAAALgAECgUJEAAAAA==.',
Ru='Ruikhai:BAAALgADCgMJBQABLgADCgkJBwACAAAAAA==.Ruto:BAAALgADCgYJCwAAAA==.',
Sa='Saelis:BAABLgAFFH8IAAIJAAMJLxdWFwDbAAAJAAMJLxdWFwDbAAAAAA==.Samshara:BAAALgADCgcJDAABLgAECggJGgAfABUZAA==.Saracenio:BAAALgADCgEJAQAAAA==.',
Sc='Schnem:BAAALgAECgYJBwAAAA==.',
Se='Securìty:BAAALgAECgQJBQAAAA==.Selyane:BAAALgADCgkJCQAAAA==.Senia:BAAALgAECgcJBwAAAA==.Seong:BAACLgAFFH8TAAIOAAUJmCCDAwCoAQAOAAUJmCCDAwCoAQAuAAQKfxsAAg4ACQlYIgcFADkDAA4ACQlYIgcFADkDAAAA.Seongdh:BAAALgAECggJDQAAAA==.Seongwar:BAAALgAECgMJAwAAAA==.Seraphinà:BAAALgAECgEJAQABLgAECggJFAAJADYFAA==.',
Sh='Shadowdooms:BAABLgAECn8UAAMWAAgJFRkdYQDQAQAWAAgJFRkdYQDQAQAgAAEJSxfxFABFAAAAAA==.Shadowfur:BAAALgADCgkJCQABLgAECgIJAgACAAAAAA==.Shamynna:BAAALgADCgkJCQAAAA==.Shii:BAAALgADCgUJBQAAAA==.Shimera:BAABLgAECn8XAAIXAAcJfRNbKwBmAQAXAAcJfRNbKwBmAQAAAA==.Shish:BAAALgAECgMJAwAAAA==.Shockawar:BAACLgAFFH8RAAIbAAUJeRwvAwDEAQAbAAUJeRwvAwDEAQAuAAQKfxQAAhsACQkqHmoYAIgCABsACQkqHmoYAIgCAAAA.Shooter:BAAALgADCgIJAgAAAA==.Shootrmcgavn:BAACLgAFFH8KAAQfAAQJNiGwAgB3AQAfAAQJnh2wAgB3AQAQAAMJIiC1EAAqAQAXAAMJdRsiFQAVAQAuAAQKfxgAAxcACAk7IdUVAIkCABcABwnxIdUVAIkCABAABwlKIWMaAFMCAAAA.Shu:BAAALgAFFAIJAgAAAA==.Shuletaa:BAAALgAECgIJBAAAAA==.Shïsh:BAAALgADCgcJBwABLgAECgMJAwACAAAAAA==.',
Si='Sinestra:BAAALgAECgEJAQAAAA==.',
Sl='Slaughterhse:BAAALgAECgYJEAAAAA==.Slootar:BAABLgAECn8UAAQJAAcJ5xuHJAAoAgAJAAcJ5xuHJAAoAgAhAAIJuxBObABuAAAiAAIJMAbgHQA4AAAAAA==.Slugs:BAAALgAECgIJAgAAAA==.',
Sn='Snqwflake:BAABLgAECn8VAAIcAAgJ7hb3FQAUAgAcAAgJ7hb3FQAUAgAAAA==.',
So='Solareth:BAAALgADCgQJBQAAAA==.Somebeotch:BAAALgADCgYJBgAAAA==.Somerled:BAABLgAECn8aAAIfAAgJFRmGCgC5AQAfAAgJFRmGCgC5AQAAAA==.',
Sp='Spyroid:BAAALgAECgUJAQAAAA==.',
St='Static:BAAALgADCgcJBwABLgAECgYJCgACAAAAAA==.',
Su='Sugerlumps:BAAALgAECgcJAQAAAA==.Sunstrike:BAAALgADCgEJBAAAAA==.',
Sy='Sylvanna:BAAALgADCgQJBAAAAA==.',
Ta='Takka:BAAALgAECgQJDAAAAA==.Talden:BAABLgAECn8nAAMMAAgJzxjdGQDvAQAMAAgJzxjdGQDvAQANAAEJ+wW6RAAsAAAAAA==.Talkamar:BAABLgAECn8cAAIYAAcJzQ8NEwBYAQAYAAcJzQ8NEwBYAQAAAA==.Taylorswift:BAABLgAECn8XAAIVAAcJrxZkOgCAAQAVAAcJrxZkOgCAAQAAAA==.Tazzaar:BAAALgAECgMJAwAAAA==.',
Th='Thekourge:BAABLgAECn8XAAINAAcJyAi0EwDQAAANAAcJyAi0EwDQAAAAAA==.Thenard:BAAALgAECgYJDAAAAA==.Thukunaenhan:BAAALgADCgcJCgABLgAECggJJQAVAO8gAA==.Thukunamage:BAABLgAECn8lAAIVAAgJ7yBqDACBAgAVAAgJ7yBqDACBAgAAAA==.',
Ti='Tibarius:BAAALgADCgkJEgAAAA==.Tinaraeda:BAAALgAECgIJAgAAAA==.',
To='Tomislav:BAAALgAECgcJEwAAAA==.Touritos:BAAALgAECgUJEgAAAA==.',
Tr='Troyka:BAAALgAECgEJAQAAAA==.Truefitt:BAAALgAECgUJDQAAAA==.',
Tu='Tulikettwo:BAAALgADCgcJBwAAAA==.Tuskal:BAAALgAECgEJAgAAAA==.',
Tw='Twogora:BAAALgAECgUJBgAAAA==.',
Ty='Tydes:BAABLgAECn8bAAMjAAgJ6RbNEwB4AgAjAAgJ6RbNEwB4AgAkAAEJqQs+HQBBAAAAAA==.Tyler:BAACLgAFFH8HAAIPAAQJfhXODwBPAQAPAAQJfhXODwBPAQAuAAQKfxsAAg8ACAkOHTccAKkCAA8ACAkOHTccAKkCAAAA.Tystin:BAAALgADCgQJBAABLgADCgkJBwACAAAAAA==.',
Ud='Uddermilk:BAAALgADCgkJEgAAAA==.',
Va='Valina:BAAALgADCgIJAgAAAA==.Valissar:BAAALgADCgcJEAAAAA==.Valr:BAABLgAECn8gAAINAAcJ3w4YEgDkAAANAAcJ3w4YEgDkAAAAAA==.Vandreu:BAAALgADCgUJBQAAAA==.',
Ve='Verpally:BAAALgADCgMJAwAAAA==.',
Vi='Viparia:BAAALgAECgkJAgAAAA==.',
Vo='Voloaura:BAAALgADCgMJAwAAAA==.',
Vs='Vse:BAACLgAFFH8FAAIVAAMJMwj3OQDsAAAVAAMJMwj3OQDsAAAuAAQKfyQAAhUABwk/F4dEAGEBABUABwk/F4dEAGEBAAAA.Vsesosorry:BAAALgAECgYJCgABLgAFFAMJBQAVADMIAA==.Vsè:BAAALgADCgUJBQABLgAFFAMJBQAVADMIAA==.',
['Ví']='Ví:BAAALgAECgYJBgAAAA==.',
Wa='Wammo:BAAALgAECgYJCgAAAA==.Waq:BAAALgADCgMJAwAAAA==.Wardozer:BAAALgAECgUJCQAAAA==.Warlockedin:BAAALgAECgYJCQAAAA==.',
We='Weierstrass:BAAALgAECgQJBQABLgAFFAUJEwAZABEmAA==.',
Wo='Worgenkrantz:BAABLgAECn8UAAMJAAgJNgVJkgCrAAAJAAcJeAJJkgCrAAAhAAUJDQS/LACqAAAAAA==.',
Wr='Wrathlor:BAAALgADCgcJBQAAAA==.Wrenlyn:BAACLgAFFH8KAAIIAAQJkRRGAwBeAQAIAAQJkRRGAwBeAQAuAAQKfycAAwgACAn8IKMFABACAAgACAl9HaMFABACAB4AAQnfIIoUAFMAAAAA.',
Xo='Xolòtl:BAABLgAECn8aAAIKAAgJBhYYFADLAQAKAAgJBhYYFADLAQABLgAFFAQJCgAIAJEUAA==.',
Yg='Yggdrasali:BAAALgAECgQJBgAAAA==.',
Yi='Yin:BAAALgAECgYJBgAAAA==.',
Ys='Yserra:BAAALgAECgcJDAAAAA==.',
Za='Zakuso:BAAALgAECgQJCAAAAA==.Zalyia:BAABLgAECn8fAAITAAcJ2AniFwA/AQATAAcJ2AniFwA/AQAAAA==.',
Ze='Zephinar:BAABLgAECn8YAAIVAAcJxhhraQADAgAVAAcJxhhraQADAgAAAA==.Zexpert:BAABLgAECn8aAAQlAAgJMBecDQAAAgAlAAcJCBicDQAAAgAGAAcJmhUoKAB8AQAHAAQJfgwANADNAAAAAA==.',
Zu='Zulblade:BAABLgAECn8SAAIPAAgJORqHMAA5AgAPAAgJORqHMAA5AgAAAA==.Zulpally:BAABLgAECn8ZAAQMAAUJ3RN+bADWAAAMAAQJzBV+bADWAAAFAAMJyRCHcgCxAAANAAQJ9witMQCIAAAAAA==.',
['Zô']='Zôrt:BAAALgAECgQJBAAAAA==.',
['Âr']='Ârtemis:BAAALgAECgEJAQAAAA==.',
['Öh']='Öhmylanta:BAAALgADCgMJAwAAAA==.',
['Öâ']='Öâth:BAAALgAECgIJAgAAAA==.',
['ßa']='ßaroness:BAAALgADCgUJBQAAAA==.',
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

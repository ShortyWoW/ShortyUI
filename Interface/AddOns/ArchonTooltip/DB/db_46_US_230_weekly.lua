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

local lookup = {'DeathKnight-Frost','DeathKnight-Unholy','Warlock-Demonology','Unknown-Unknown','Shaman-Restoration','DemonHunter-Devourer','DemonHunter-Havoc','Shaman-Elemental','Paladin-Holy','Evoker-Augmentation','Evoker-Preservation','Druid-Restoration','Warrior-Protection','Warrior-Arms','Paladin-Retribution','Paladin-Protection','Monk-Brewmaster','Hunter-Marksmanship','Shaman-Enhancement','Mage-Frost','Warlock-Destruction','Warrior-Fury','Hunter-Survival','Priest-Shadow','Priest-Holy','Hunter-BeastMastery','Monk-Windwalker','DeathKnight-Blood','Druid-Guardian','Monk-Mistweaver','Warlock-Affliction','DemonHunter-Vengeance','Druid-Balance','Druid-Feral','Rogue-Subtlety','Rogue-Assassination','Evoker-Devastation',}
local provider = {region='US',realm='Undermine',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abaddon:BAABLgAECn8UAAMBAAYJ2R7mBgBHAQABAAQJAx/mBgBHAQACAAUJox3xVQA8AQAAAA==.',
Ac='Acidtears:BAAALgADCgcJDQAAAA==.Ackris:BAABLgAECn8oAAIDAAkJ/BwHCgAuAwADAAkJ/BwHCgAuAwAAAA==.Ackrisa:BAAALgAECgIJAgAAAA==.Acris:BAAALgAECgYJCwABLgAECgkJKAADAPwcAA==.',
Al='Aleathris:BAEALgADCgcJBwABLgAECgQJBAAEAAAAAA==.Alka:BAAALgADCgEJAQAAAA==.Alor:BAAALgAECgEJAgABLgAECgcJHwAFAHIQAA==.Alpyne:BAAALgAECgcJEgAAAA==.',
Am='Amaimon:BAABLgAECn8aAAMGAAgJDRWFJgCjAQAGAAgJDRWFJgCjAQAHAAEJawxXPwA2AAABLgAFFAYJFwAIADITAA==.Amnoon:BAABLgAECn8fAAIJAAgJWBjJCwBWAgAJAAgJWBjJCwBWAgAAAA==.Amri:BAACLgAFFH8NAAIKAAQJCw4TFwAqAQAKAAQJCw4TFwAqAQAuAAQKfxsAAwoACAlxFpgVAC0CAAoACAlxFpgVAC0CAAsAAwkMBcY8AIQAAAAA.',
An='Andarnáurram:BAAALgAECgIJAgAAAA==.',
Aq='Aquas:BAAALgAECgMJBQAAAA==.',
Ar='Ardrhys:BAAALgAECgMJAwAAAA==.Arthurcarrot:BAAALgAECgQJBwAAAA==.Artikin:BAAALgAECgEJAQABLgAFFAQJDgAHAOUVAA==.',
As='Assasinateu:BAAALgADCgMJAwAAAA==.Asûná:BAAALgAECgQJCAAAAA==.',
At='Atreus:BAABLgAECn8iAAIHAAkJ8xpABQBmAgAHAAkJ8xpABQBmAgAAAA==.Atzalan:BAABLgAECn8UAAIMAAYJpwnlcwD7AAAMAAYJpwnlcwD7AAAAAA==.',
Au='Automagic:BAAALgAECgEJAQAAAA==.',
Av='Avondwella:BAABLgAECn8jAAMNAAgJ0RB4GACRAQANAAgJ0RB4GACRAQAOAAEJ+wnARAAvAAAAAA==.',
Az='Azrikam:BAAALgAECgYJCAAAAA==.',
Ba='Baldyguy:BAAALgADCgcJCgAAAA==.Balm:BAABLgAECn8nAAIMAAgJKhnVIQC3AQAMAAgJKhnVIQC3AQAAAA==.Balton:BAAALgAECgIJAwAAAA==.Barbsimpsonn:BAAALgAECgEJAQAAAA==.Bashalot:BAAALgAECgUJBgAAAA==.',
Be='Bearooter:BAAALgADCgUJCAABLgAFFAUJEAALALEkAA==.Bermin:BAAALgADCgUJAwAAAA==.',
Bi='Biblepimp:BAAALgAFFAEJAQAAAA==.Bigwilliam:BAAALgADCgEJAQAAAA==.',
Bl='Blackmarker:BAAALgAECgcJEgAAAA==.',
Bm='Bmo:BAABLgAECn8VAAIPAAcJZSBvSAAJAgAPAAcJZSBvSAAJAgAAAA==.',
Bo='Bodyguardwyn:BAAALgAECgEJAQAAAA==.Bogle:BAACLgAFFH8FAAMPAAIJOQznTwCJAAAPAAIJUAXnTwCJAAAQAAIJOQwMCAA2AAAuAAQKfywAAxAACQnYI4AAACwDABAACQnYI4AAACwDAA8AAQmPFfzaAFQAAAAA.Bonedmuch:BAAALgADCgUJCgABLgAECggJHwARAGUSAA==.Bow:BAAALgAECgIJAwAAAA==.',
Br='Brasi:BAAALgAECgIJAgAAAA==.Bratton:BAAALgAECgYJEAAAAA==.Bremitin:BAAALgADCggJCAABLgAECggJKQAQAFYQAA==.Bremitus:BAAALgADCgkJCQABLgAECggJKQAQAFYQAA==.Brewcrew:BAAALgAECgkJBwAAAA==.Brewmongster:BAAALgAECgQJBQAAAA==.Brimscythe:BAABLgAECn8YAAIGAAcJhx+oNwAXAgAGAAcJhx+oNwAXAgAAAA==.Brud:BAAALgAECgMJBwAAAA==.Brunstan:BAABLgAFFH8KAAISAAQJvh4lBQB8AQASAAQJvh4lBQB8AQAAAA==.',
Bu='Bubbastump:BAAALgAECgQJBAAAAA==.',
By='Byakugan:BAACLgAFFH8XAAMIAAYJMhNiBQCIAQAIAAUJaxNiBQCIAQAFAAEJaA/TOgBSAAAuAAQKfxsABAgACQktH5cPAK8CAAgACQktH5cPAK8CABMAAQm+F74pAEEAAAUAAQkHAf6oACUAAAAA.',
['Bø']='Bønitalèè:BAABLgAECn8aAAIUAAcJNQXkgAAQAQAUAAcJNQXkgAAQAQAAAA==.',
Ca='Cain:BAAALgADCgMJAwAAAA==.Calvisi:BAAALgAECgEJAQAAAA==.Calvisichaos:BAABLgAECn8eAAIVAAgJUBGIBgCFAQAVAAgJUBGIBgCFAQAAAA==.Cantero:BAAALgADCgUJBQAAAA==.Canthen:BAAALgAECgYJBwAAAA==.Carcarnisa:BAAALgAECgQJBgAAAA==.Carm:BAAALgAECgMJAwAAAA==.',
Ce='Cenobia:BAAALgADCgUJCQAAAA==.',
Ch='Chaire:BAAALgADCgcJBgAAAA==.Chrysophylax:BAAALgAECgYJBgAAAA==.',
Co='Conky:BAAALgAECgMJBgAAAA==.Corndog:BAAALgADCgEJAQAAAA==.Cornix:BAAALgADCgEJAQAAAA==.Cosmicspark:BAAALgAECgIJBAAAAA==.',
Cr='Crentist:BAAALgAECgEJAQAAAA==.Cropala:BAABLgAECn8WAAIPAAcJyxJxZAC4AQAPAAcJyxJxZAC4AQAAAA==.',
Da='Daca:BAAALgADCgMJAwAAAA==.Darkwingduck:BAAALgADCgEJAQAAAA==.Dave:BAAALgADCgQJBAAAAA==.Davros:BAAALgAECgMJBwAAAA==.',
De='Deleto:BAAALgAECgQJBwAAAA==.Dellandre:BAAALgAECgQJBAABLgAECggJHwAQACYIAA==.Delta:BAABLgAECn8RAAIGAAgJHAfLgQCSAAAGAAgJHAfLgQCSAAAAAA==.Delti:BAAALgADCgYJBgABLgAECggJGgAGAMUWAA==.Demondozer:BAAALgAECgMJAwABLgAECgUJCQAEAAAAAA==.Demony:BAAALgAECgEJAQAAAA==.Denard:BAAALgAECgUJBgAAAA==.',
Di='Diabolist:BAABLgAECn8UAAIDAAkJNQcJOQCCAQADAAkJNQcJOQCCAQAAAA==.Digichowder:BAABLgAECn8WAAMOAAcJARc+CgCiAQAOAAYJARc+CgCiAQAWAAMJnQ9kTgB8AAAAAA==.Dirtygiri:BAAALgADCgEJAgAAAA==.',
Do='Doktaga:BAAALgAECgYJCQAAAA==.',
Dr='Draex:BAAALgADCgEJAQAAAA==.Dragonzord:BAAALgADCgEJAQAAAA==.Drbubbles:BAAALgADCgYJCAABLgAECgQJCQAEAAAAAA==.Drredd:BAAALgAECgQJBAAAAA==.',
Eg='Eggfield:BAAALgAECgUJBgAAAA==.',
El='Eladora:BAAALgADCgEJAQAAAA==.Eldarr:BAABLgAECn8lAAMVAAgJcCDIAQBSAgAVAAcJPyLIAQBSAgADAAQJIBTsYAAOAQAAAA==.Eldhe:BAAALgADCgkJFwAAAA==.Eleos:BAAALgADCgMJBgAAAA==.Elistrae:BAABLgAECn8WAAMSAAgJjRUrMwCgAQASAAcJABcrMwCgAQAXAAQJVw4rHgAQAQAAAA==.',
Em='Emorri:BAAALgAECgYJBgAAAA==.',
En='Enazen:BAAALgAECgcJDwAAAA==.Endlol:BAABLgAECn8lAAMYAAgJIiK7CAA8AgAYAAcJoSG7CAA8AgAZAAEJWB+xQgBaAAABLgAFFAIJAwAEAAAAAA==.',
Er='Eredaria:BAAALgAECgUJCQAAAA==.Ereshkigal:BAAALgADCgYJCwAAAA==.Ergo:BAACLgAFFH8SAAIUAAYJjBRIDwCeAQAUAAYJjBRIDwCeAQAuAAQKfyIAAhQACQk+IBcjAOYCABQACQk+IBcjAOYCAAAA.Eronel:BAABLgAECn8dAAICAAcJDhrLNgCeAQACAAcJDhrLNgCeAQAAAA==.',
Es='Esv:BAAALgAECgQJBwABLgAFFAMJCAAUAPAJAA==.',
Ex='Excido:BAAALgAECgEJAQAAAA==.Exodiagold:BAAALgAECgEJAQAAAA==.',
Fa='Fadedharanir:BAAALgAECgEJAQAAAA==.Fadedheart:BAAALgAECgMJAwABLgAECggJKgACACEfAA==.Fadedmystic:BAAALgADCgkJEAAAAA==.Fadednight:BAABLgAECn8qAAICAAgJIR/EDwCBAgACAAgJIR/EDwCBAgAAAA==.Faeyir:BAABLgAECn8gAAIUAAkJphs6UABGAgAUAAkJphs6UABGAgAAAA==.Fallingmoon:BAABLgAECn8bAAMaAAgJBx94EgA9AgAaAAgJBx94EgA9AgASAAEJKRDgigAwAAAAAA==.Fangrage:BAAALgAECgYJBAAAAA==.Fatherlode:BAACLgAFFH8KAAIUAAMJwBjUQwADAQAUAAMJwBjUQwADAQAuAAQKfysAAhQACQmUIRwHAP0CABQACQmUIRwHAP0CAAAA.',
Fe='Feltpen:BAAALgAECgUJBQAAAA==.Femcelibate:BAAALgADCgcJCAAAAA==.Fentenjoyer:BAAALgAECgUJCQAAAA==.Fernfondler:BAAALgAFFAIJAwAAAA==.',
Fl='Flashylights:BAAALgADCgYJBgAAAA==.',
Fo='Fontane:BAAALgADCgYJBwAAAA==.Forcebolt:BAAALgADCgMJAwAAAA==.',
Fr='Fredgoffin:BAAALgAECgIJAgAAAA==.Freecookies:BAAALgAECgYJCQAAAA==.Frostybop:BAAALgAECgEJAgABLgAECgMJAwAEAAAAAA==.Frostybrews:BAAALgAECgEJAQABLgAECgMJAwAEAAAAAA==.Frostydh:BAAALgAECgMJAwAAAA==.Frostytotems:BAAALgAECgEJAgAAAA==.Fróstblight:BAAALgAECgcJBwAAAA==.',
Fu='Furryiosa:BAAALgADCgYJBgAAAA==.',
Ga='Gauntodimm:BAAALgAECgUJBgAAAA==.',
Gi='Gilberticus:BAAALgAECgQJBgABLgAECgkJLQAbAG8bAA==.Gishmou:BAABLgAECn8aAAIFAAgJuBpBFQAKAgAFAAgJuBpBFQAKAgAAAA==.',
Go='Goldblade:BAABLgAECn8YAAIPAAcJxxcsMwCwAQAPAAcJxxcsMwCwAQAAAA==.',
Gr='Greyoll:BAAALgAECgYJCAAAAA==.Grindlewald:BAAALgAECgIJAgAAAA==.',
Gu='Gutted:BAACLgAFFH8ZAAIcAAYJHiXaAAAmAgAcAAYJHiXaAAAmAgAuAAQKfxsAAhwACQmsJb0BAGcDABwACQmsJb0BAGcDAAAA.',
['Gä']='Gärin:BAAALgADCggJFAAAAA==.',
Ha='Hanna:BAAALgAECggJDQABLgAFFAYJGQAcAB4lAA==.',
He='Hellmaw:BAAALgADCgcJBwAAAA==.',
Hi='Highly:BAAALgADCgcJCwAAAA==.',
Ho='Hollowheart:BAABLgAECn8bAAIFAAgJyxd6HgC+AQAFAAgJyxd6HgC+AQAAAA==.Holycourtney:BAAALgADCgkJEQAAAA==.Hoved:BAAALgADCgEJAQAAAA==.',
Hy='Hylanna:BAAALgAECgUJBgAAAA==.Hyorinmaru:BAAALgAECgIJAgAAAA==.',
['Hó']='Hónor:BAAALgADCgMJAwABLgAECggJKQAQAFYQAA==.',
Ic='Ici:BAABLgAECn8jAAIPAAcJhgerawAWAQAPAAcJhgerawAWAQAAAA==.',
If='Iffybacon:BAAALgAECgIJAgABLgAECgQJCwAEAAAAAA==.',
Im='Imlerith:BAAALgADCgQJBAAAAA==.',
In='Intensifies:BAAALgAECgYJDAAAAA==.',
Ip='Ippo:BAAALgADCgEJAQAAAA==.',
Is='Iskothar:BAAALgAECgcJEwAAAA==.',
Iv='Ivarboneless:BAAALgAECgQJCgAAAA==.',
Ja='Jackz:BAAALgAECgIJAgAAAA==.Jakethemage:BAAALgADCgUJCAAAAA==.',
Je='Jefftrep:BAAALgAECgIJAgAAAA==.Jerihatrix:BAAALgAECgEJAQAAAA==.',
Ji='Jimmylahey:BAAALgAECgMJAwAAAA==.',
Jo='Jonah:BAAALgADCgEJAQAAAA==.',
Ka='Kaina:BAAALgADCgYJCQAAAA==.Kakidruid:BAAALgAECgIJAwAAAA==.Kalfu:BAAALgAECggJCAAAAA==.',
Ke='Ketesh:BAABLgAECn8qAAIdAAgJXh+UAwBVAgAdAAgJXh+UAwBVAgABLgAFFAQJDQAKAAsOAA==.',
Ki='Kilorean:BAAALgAECgcJCAAAAA==.Kirae:BAAALgADCgcJBwABLgAECgcJEwAEAAAAAA==.',
Kn='Knastey:BAAALgAECgYJDgAAAA==.Knasty:BAAALgADCgEJAQAAAA==.',
Ko='Kodera:BAAALgAECgQJCgAAAA==.',
Kr='Krej:BAAALgAECgkJEwABLgAFFAQJDgAHAOUVAA==.Krisskringle:BAAALgAECgMJBgAAAA==.',
Ku='Kuromori:BAAALgADCgYJBgAAAA==.',
['Kê']='Kênpachi:BAAALgAECgYJCAAAAA==.',
La='Langarde:BAAALgAECgcJDwAAAA==.Laoghaire:BAAALgAECgYJEQAAAA==.',
Le='Leonz:BAACLgAFFH8UAAIWAAYJKh/zAADgAQAWAAYJKh/zAADgAQAuAAQKfyQAAhYACQlKIOYJABADABYACQlKIOYJABADAAAA.Leonzs:BAAALgAECggJEAAAAA==.Letharanos:BAEBLgAECn8kAAICAAgJdBtfJADyAQACAAgJdBtfJADyAQAAAA==.',
Li='Liraffemynn:BAABLgAECn8tAAIeAAkJ/CIxAQCGAwAeAAkJ/CIxAQCGAwAAAA==.Liralynn:BAAALgADCgUJBQAAAA==.',
Lk='Lkynyx:BAAALgADCgYJAQAAAA==.',
Lo='Lostinlight:BAAALgAECgYJBgAAAA==.',
Lu='Luckylucy:BAAALgAECgQJCQAAAA==.',
Ma='Madarauchiha:BAAALgAECgYJEgAAAA==.Magus:BAAALgADCggJCAABLgAECgMJBwAEAAAAAA==.Maldran:BAABLgAECn8XAAIFAAcJjh3dEQArAgAFAAcJjh3dEQArAgAAAA==.Maling:BAAALgAECgEJAQAAAA==.Manderpants:BAAALgAECgYJEQAAAA==.Marien:BAAALgAECgcJDwAAAA==.Marty:BAAALgAECgIJAwAAAA==.Maxus:BAAALgADCgUJBQAAAA==.',
Mb='Mbbin:BAABLgAECn8hAAIUAAkJ6x9BDQC0AgAUAAkJ6h9BDQC0AgAAAA==.',
Me='Mehuman:BAAALgAECgMJCQAAAA==.Mehumanhuntr:BAAALgADCggJCwAAAA==.Mehumanlock:BAABLgAECn8cAAIVAAgJWxBkBgCKAQAVAAgJWxBkBgCKAQAAAA==.Merran:BAAALgADCgEJAQAAAA==.Metal:BAAALgADCgQJBAAAAA==.Meworgendk:BAAALgAECgMJBAAAAA==.',
Mh='Mhoo:BAAALgADCgcJBwAAAA==.',
Mi='Miriym:BAAALgADCgEJAQAAAA==.Miräj:BAAALgADCgMJAwAAAA==.Mistyblue:BAAALgADCgEJAQAAAA==.Miya:BAAALgADCgcJDQAAAA==.',
Mo='Mordaci:BAAALgADCgQJBQABLgAECggJDAAEAAAAAA==.Mortstan:BAAALgAECgYJCwAAAA==.',
['Mé']='Mélusine:BAAALgADCgEJAQAAAA==.',
Na='Nailia:BAAALgAECgUJCQAAAA==.Nailz:BAABLgAECn8aAAIGAAgJxRboNABiAQAGAAgJxRboNABiAQAAAA==.Narie:BAAALgADCgYJBgAAAA==.Nasaug:BAAALgAECgEJAQABLgAECggJKQAQAFYQAA==.',
Ne='Ned:BAAALgAECgEJAQAAAA==.Neuse:BAAALgAECgYJDQAAAA==.',
Ni='Nightlion:BAAALgAECgQJCgAAAA==.Nillius:BAAALgADCgIJAgAAAA==.Nisu:BAAALgAECgEJAQAAAA==.',
No='Noahdh:BAAALgAECgMJAwABLgAFFAYJFgADACAcAA==.Noahpriest:BAAALgAECgMJAwABLgAFFAYJFgADACAcAA==.Noahvoker:BAAALgAECggJEQABLgAFFAYJFgADACAcAA==.Noahwarlock:BAACLgAFFH8WAAQDAAYJIBwDFABmAQADAAUJuR8DFABmAQAVAAIJsxTpBwCqAAAfAAEJkSNtBQBhAAAuAAQKfx0ABBUACQmEIz8aAHsBAAMABgm2ImViAKMBABUABAl0Ij8aAHsBAB8AAgnmI4IWAM0AAAAA.Nonsensical:BAAALgADCgUJBQAAAA==.Nook:BAAALgADCgUJBgAAAA==.Noxander:BAAALgAECgEJAQAAAA==.',
Ny='Nym:BAAALgAECgkJEQAAAA==.',
['Nâ']='Nârenth:BAAALgADCgMJAwAAAA==.',
Oa='Oaths:BAAALgAECgcJCQAAAA==.',
Oh='Ohmylantä:BAABLgAECn8XAAIUAAgJSgtr1gBCAQAUAAgJSgtr1gBCAQAAAA==.Ohmylantå:BAAALgADCgUJCAAAAA==.',
On='Ondeane:BAAALgADCgEJAQAAAA==.Onumae:BAABLgAECn8WAAIPAAkJcRpJEAB5AgAPAAkJcRpJEAB5AgAAAA==.',
Op='Oprime:BAAALgADCgMJAwAAAA==.',
Or='Orbeck:BAAALgADCgQJBAABLgAFFAYJGQARAI8fAA==.Oriax:BAAALgADCgMJAwAAAA==.Ormond:BAAALgADCgYJDgAAAA==.Orochinchin:BAAALgAECgMJAwABLgAFFAYJGQAcAB4lAA==.',
Os='Oscarmike:BAAALgADCgcJDQAAAA==.',
Oz='Ozlon:BAAALgAECgYJDQAAAA==.',
['Oâ']='Oâth:BAABLgAECn8cAAIgAAgJOwvgCwAJAQAgAAgJOwvgCwAJAQAAAA==.',
Pa='Pachane:BAAALgAECgMJBAAAAA==.Paldozer:BAAALgAECgIJAgABLgAECgUJCQAEAAAAAA==.Pallywacker:BAABLgAECn8dAAIQAAgJvgwrEAA4AQAQAAgJvgwrEAA4AQAAAA==.Pankins:BAAALgAECgMJAwAAAA==.Panzerkan:BAAALgAECgEJAQAAAA==.',
Pe='Percymorris:BAAALgADCgYJBwAAAA==.',
Pi='Pigishdog:BAABLgAECn80AAIDAAgJthnNGAAcAgADAAgJthnNGAAcAgAAAA==.Pikon:BAAALgADCgkJDQAAAA==.',
Po='Pokeabear:BAAALgAECgYJEAABLgAECgcJEAAEAAAAAA==.Pokethemonk:BAAALgAECgEJBgAAAA==.Poshingtang:BAABLgAECn8pAAQFAAkJqgwVIQCqAQAFAAkJqgwVIQCqAQAIAAgJHhG4NgB4AQATAAMJSwP9JQB3AAAAAA==.',
Pu='Pulsar:BAAALgADCgcJCAAAAA==.Punchies:BAAALgADCggJDQAAAA==.',
Qu='Quatrain:BAABLgAECn8fAAIFAAcJchCGQgB3AQAFAAcJchCGQgB3AQAAAA==.',
Ra='Rabidbutt:BAAALgAFFAEJAQABLgAFFAUJEAALALEkAA==.Ragerunner:BAAALgADCgkJEwAAAA==.Rakarg:BAABLgAECn8XAAICAAUJDBgCZwAVAQACAAUJDBgCZwAVAQAAAA==.Ravenus:BAAALgAECgEJAQAAAA==.',
Re='Refund:BAAALgAECgEJAQAAAA==.Regalbacon:BAAALgAECgMJAwAAAA==.Reygina:BAABLgAECn8UAAIJAAYJiQEWRACfAAAJAAYJiQEWRACfAAAAAA==.',
Ri='Rickÿ:BAAALgAECgEJAQAAAA==.Riprock:BAAALgAECgIJAQAAAA==.Rixas:BAAALgADCgQJBAABLgAECgkJKAADAPwcAA==.',
Rn='Rn:BAABLgAECn8bAAMOAAkJJSJBAQBGAwAOAAkJuyFBAQBGAwAWAAcJLyMfKQAXAgABLgAFFAcJGgAOABsjAA==.',
Ro='Roguehiro:BAABLgAECn8YAAIQAAcJkR41BwBuAgAQAAcJkR41BwBuAgAAAA==.Rooter:BAACLgAFFH8QAAILAAUJsSTaAgAZAgALAAUJsSTaAgAZAgAuAAQKfy0AAwsACAm3I6gCAMMCAAsACAm3I6gCAMMCAAoABwkmGdYQAMsBAAAA.Rosalynñ:BAABLgAECn8WAAIVAAYJvQaQEQDKAAAVAAYJvQaQEQDKAAAAAA==.',
Ru='Ruikhai:BAAALgADCgMJBQABLgADCgkJBwAEAAAAAA==.Ruto:BAAALgAECgEJAQAAAA==.',
Sa='Saelis:BAACLgAFFH8MAAIMAAQJGhUMFgAeAQAMAAQJGhUMFgAeAQAuAAQKfxUAAgwACQnAHloQAFICAAwACQnAHloQAFICAAAA.Samshara:BAAALgADCgcJDAABLgAECggJIgAXALYZAA==.Saptapper:BAAALgAECgIJAgAAAA==.Saracenio:BAAALgADCgEJAQAAAA==.',
Sc='Schnem:BAAALgAECgYJBwAAAA==.',
Se='Securìty:BAAALgAECgQJBQAAAA==.Selyane:BAAALgADCgkJCQAAAA==.Senia:BAAALgAECgcJDQAAAA==.Seong:BAACLgAFFH8ZAAIRAAYJjx9zAgDXAQARAAYJjx9zAgDXAQAuAAQKfxwAAhEACQmAIgYFADkDABEACQmAIgYFADkDAAAA.Seongdh:BAAALgAECggJDQAAAA==.Seongwar:BAAALgAECgMJAwAAAA==.Seraphinà:BAAALgAECgIJAwABLgAECggJGwAhAIsKAA==.',
Sh='Shadowdooms:BAABLgAECn8UAAMCAAgJFBkXYQDQAQACAAgJFBkXYQDQAQABAAEJSxfzFABFAAAAAA==.Shadowfur:BAAALgADCgkJCQABLgAECggJIwAJAAQdAA==.Shamynna:BAAALgAECgIJAgAAAA==.Shii:BAAALgADCgUJBQAAAA==.Shimera:BAABLgAECn8fAAIaAAgJDRLhKwCgAQAaAAgJDRLhKwCgAQAAAA==.Shish:BAAALgAECgMJAwAAAA==.Shockawar:BAACLgAFFH8VAAIWAAUJeRwwAwDEAQAWAAUJeRwwAwDEAQAuAAQKfxQAAhYACQmrHmUYAIgCABYACQmrHmUYAIgCAAAA.Shooter:BAAALgADCgIJAgAAAA==.Shootrmcgavn:BAACLgAFFH8OAAQXAAQJOiHzBABvAQAXAAQJ2h3zBABvAQASAAMJIiC6EAAqAQAaAAMJfRv7IgAJAQAuAAQKfxgAAxoACAk7IdMVAIkCABoABwnxIdMVAIkCABIABwlKIcEaAFMCAAAA.Shu:BAAALgAFFAIJAgAAAA==.Shuletaa:BAAALgAECgIJBAAAAA==.Shïsh:BAAALgADCgcJBwABLgAECgMJAwAEAAAAAA==.',
Si='Sinestra:BAAALgAECgEJAQAAAA==.',
Sl='Slaughterhse:BAAALgAECgYJEQAAAA==.Slootar:BAABLgAECn8UAAQMAAcJ5xuGJAAoAgAMAAcJ5xuGJAAoAgAhAAIJuxBXbABuAAAiAAIJMAalJgA3AAAAAA==.Slugs:BAAALgAECgIJAwAAAA==.',
Sn='Snqwflake:BAABLgAECn8VAAIeAAgJ7xb3FQAUAgAeAAgJ7xb3FQAUAgAAAA==.',
So='Solareth:BAAALgADCgQJBQAAAA==.Somebeotch:BAAALgADCgYJBgAAAA==.Somerled:BAABLgAECn8iAAIXAAgJthnXBwAsAgAXAAgJthnXBwAsAgAAAA==.',
Sp='Spyroid:BAAALgAECgUJAQAAAA==.',
St='Static:BAAALgADCgcJBwABLgAECgYJCgAEAAAAAA==.',
Su='Sugerlumps:BAAALgAECgcJAgAAAA==.Sunstrike:BAAALgADCgEJBAAAAA==.',
Sy='Sylvanna:BAAALgADCgQJBAAAAA==.',
Ta='Takka:BAAALgAECgYJEgAAAA==.Talden:BAABLgAECn8rAAMPAAgJ2RhAJgDoAQAPAAgJ2RhAJgDoAQAQAAEJ/AW4RAAsAAAAAA==.Talkamar:BAABLgAECn8gAAIbAAgJlxBEEwCZAQAbAAgJlxBEEwCZAQAAAA==.Taylorswift:BAABLgAECn8fAAIUAAgJzRZ5LgDnAQAUAAgJzRZ5LgDnAQAAAA==.Tazzaar:BAAALgAECgMJAwAAAA==.',
Th='Thaelios:BAAALgADCgEJAQAAAA==.Thekourge:BAABLgAECn8fAAIQAAgJJggnFQD4AAAQAAgJJggnFQD4AAAAAA==.Thenard:BAABLgAECn8VAAIaAAgJTRFoKQCrAQAaAAgJTRFoKQCrAQAAAA==.Thukunaenhan:BAAALgADCgcJCgABLgAFFAMJBgAUAPoPAA==.Thukunamage:BAACLgAFFH8GAAIUAAMJ+g8ASAD5AAAUAAMJ+g8ASAD5AAAuAAQKfycAAhQACQk/IH0KANECABQACQk/IH0KANECAAAA.',
Ti='Tibarius:BAAALgADCgkJEgAAAA==.Tinaraeda:BAAALgAECgMJAwAAAA==.',
To='Tomislav:BAAALgAECgcJEwAAAA==.Touritos:BAABLgAECn8VAAIIAAcJQRF/HgBZAQAIAAcJQRF/HgBZAQAAAA==.',
Tr='Troyka:BAAALgAECgEJAQAAAA==.Truefitt:BAAALgAECgYJEwAAAA==.',
Tu='Tulikettwo:BAAALgADCgcJBwAAAA==.Tuskal:BAAALgAECgEJAgAAAA==.',
Tw='Twogora:BAAALgAECgUJBgAAAA==.',
Ty='Tydes:BAABLgAECn8bAAMjAAgJ6RbKEwB4AgAjAAgJ6RbKEwB4AgAkAAEJtgs+HQBBAAAAAA==.Tyler:BAACLgAFFH8HAAIGAAQJfhXSDwBPAQAGAAQJfhXSDwBPAQAuAAQKfxsAAgYACAkOHTUcAKkCAAYACAkOHTUcAKkCAAAA.Tystin:BAAALgADCgQJBQABLgADCgkJBwAEAAAAAA==.',
Ud='Uddermilk:BAAALgAECgQJBAAAAA==.',
Va='Valina:BAAALgADCgIJAgAAAA==.Valissar:BAAALgAECgEJAQAAAA==.Valr:BAABLgAECn8pAAIQAAgJVhBPDwBDAQAQAAgJVhBPDwBDAQAAAA==.Vandreu:BAAALgADCgUJBQAAAA==.',
Ve='Verpally:BAAALgADCgMJAwAAAA==.',
Vi='Viparia:BAAALgAECgkJAgAAAA==.Virulent:BAAALgAECgMJAwAAAA==.',
Vo='Voloaura:BAAALgADCgMJAwAAAA==.',
Vs='Vse:BAACLgAFFH8IAAIUAAMJ8AkVTgDqAAAUAAMJ8AkVTgDqAAAuAAQKfyUAAhQACAkHFdhHAJABABQACAkHFdhHAJABAAAA.Vsesosorry:BAAALgAFFAIJBAABLgAFFAMJCAAUAPAJAA==.Vsè:BAAALgADCgUJBQABLgAFFAMJCAAUAPAJAA==.',
Vy='Vyke:BAAALgAECgYJBgABLgAFFAYJGQARAI8fAA==.',
['Ví']='Ví:BAAALgAECgYJBgAAAA==.',
Wa='Wammo:BAAALgAECgYJCgAAAA==.Waq:BAAALgADCgMJAwAAAA==.Wardozer:BAAALgAECgUJCQAAAA==.Warlockedin:BAAALgAECgYJCgAAAA==.',
We='Weierstrass:BAAALgAECgUJCgABLgAFFAYJGQAcAB4lAA==.',
Wo='Worgenkrantz:BAABLgAECn8bAAMhAAgJiwp1HABQAQAhAAgJiwp1HABQAQAMAAcJeAJKkgCrAAAAAA==.',
Wr='Wrathlor:BAAALgADCgcJBQAAAA==.Wrenlyn:BAACLgAFFH8OAAIHAAQJ5RXhBABRAQAHAAQJ5RXhBABRAQAuAAQKfygAAwcACAleI74GADYCAAcACAnfH74GADYCACAAAQnfIBoaAFEAAAAA.',
Xo='Xolòtl:BAABLgAECn8eAAINAAgJhRYWFADLAQANAAgJhRYWFADLAQABLgAFFAQJDgAHAOUVAA==.',
Yg='Yggdrasali:BAAALgAECgQJBgABLgAFFAIJBQAUAJIaAA==.',
Yi='Yin:BAAALgAECgYJBgAAAA==.',
Ys='Yserra:BAAALgAECgcJDAAAAA==.',
Za='Zakuso:BAAALgAECgQJCQAAAA==.Zalyia:BAABLgAECn8nAAIYAAgJDwtJGQByAQAYAAgJDwtJGQByAQAAAA==.',
Ze='Zephinar:BAABLgAECn8ZAAIUAAgJcBVlaQADAgAUAAgJcBVlaQADAgAAAA==.Zexpert:BAABLgAECn8aAAQlAAgJNBeeDQAAAgAlAAcJChieDQAAAgAKAAcJnhUnKAB8AQALAAQJfgwANADNAAAAAA==.',
Zq='Zquestion:BAAALgAECgEJAgABLgAECggJGgAlADQXAA==.',
Zu='Zulblade:BAABLgAECn8SAAIGAAgJORqAMAA5AgAGAAgJORqAMAA5AgAAAA==.Zulpally:BAABLgAECn8aAAQPAAUJQBZoZQAjAQAPAAQJxhhoZQAjAQAJAAMJyRCMcgCxAAAQAAQJ+QiqMQCIAAAAAA==.',
['Zô']='Zôrt:BAAALgAECgQJBAAAAA==.',
['Âr']='Ârtemis:BAAALgAECgEJAQAAAA==.',
['Öh']='Öhmylanta:BAAALgADCgMJAwAAAA==.',
['Öâ']='Öâth:BAAALgAECgIJAgAAAA==.',
['ßa']='ßaroness:BAAALgADCgUJCQAAAA==.',
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

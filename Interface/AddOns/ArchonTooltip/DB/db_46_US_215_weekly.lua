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

local lookup = {'Rogue-Subtlety','Evoker-Augmentation','Paladin-Holy','Warlock-Demonology','Hunter-Survival','Hunter-BeastMastery','Monk-Mistweaver','DeathKnight-Unholy','DeathKnight-Frost','Druid-Restoration','Druid-Feral','Shaman-Restoration','Warrior-Arms','Warrior-Fury','Evoker-Devastation','Evoker-Preservation','Shaman-Elemental','Priest-Holy','Druid-Guardian','Monk-Windwalker','DeathKnight-Blood','Hunter-Marksmanship','Unknown-Unknown','Priest-Shadow','Paladin-Protection','Paladin-Retribution','Shaman-Enhancement','Druid-Balance','Warlock-Destruction','DemonHunter-Havoc','Monk-Brewmaster','Rogue-Outlaw','Rogue-Assassination','Warrior-Protection','Warlock-Affliction',}
local provider = {region='US',realm='TheScryers',name='US',type='weekly',zone=46,date='2026-05-08',data={Ae='Aelin:BAAALgAECgYJBwAAAA==.',
Ai='Airo:BAABLgAECn8wAAIBAAkJQxeFBgBIAgABAAkJQxeFBgBIAgAAAA==.',
Ak='Akaris:BAABLgAECn8WAAICAAYJXwX8NgDEAAACAAYJXwX8NgDEAAAAAA==.',
Al='Alainea:BAAALgAECggJDAAAAA==.Alispia:BAAALgADCgMJAwAAAA==.',
Am='Amaterasu:BAABLgAFFH8JAAIDAAMJViB+EwAXAQADAAMJViB+EwAXAQABLgAFFAMJCQADAFYgAA==.Ambre:BAAALgAECgYJCwAAAA==.Amerdro:BAAALgAECgQJCQAAAA==.Amoreesa:BAAALgAECgQJBAAAAA==.',
An='Andross:BAAALgADCgcJEgABLgAECgYJFQAEAH8IAA==.Angrytestie:BAAALgAECgUJBQAAAA==.Anomaly:BAABLgAECn8sAAMFAAgJJSImBACHAgAFAAgJJSImBACHAgAGAAIJdg43uQBQAAAAAA==.Anthousai:BAAALgADCgQJBAAAAA==.',
Ar='Ara:BAABLgAFFH8LAAIHAAYJARp7AwC7AQAHAAYJARp7AwC7AQAAAA==.',
As='Asylum:BAAALgADCgcJDQAAAA==.',
Au='Aura:BAAALgAECgMJAwAAAA==.',
Ax='Axl:BAABLgAECn8WAAMIAAYJ7galewDqAAAIAAYJ7galewDqAAAJAAEJ8QFzGgAhAAAAAA==.',
Ay='Aylíth:BAAALgAFFAEJAQABLgAFFAMJCQADAFYgAA==.',
Ba='Bacon:BAAALgADCgkJCQAAAA==.Bahdeeps:BAAALgAECgEJAQAAAA==.Bahheals:BAABLgAECn8UAAMKAAcJzgRLWQC1AAAKAAcJzgRLWQC1AAALAAUJhQGrHAB3AAAAAA==.Banjoo:BAABLgAECn8ZAAIKAAgJMRsNGgDzAQAKAAgJMRsNGgDzAQAAAA==.Baruk:BAABLgAECn8cAAIMAAgJ8BNuJgCJAQAMAAgJ8BNuJgCJAQAAAA==.',
Be='Beauzericka:BAAALgADCgEJAQAAAA==.Beeswax:BAAALgADCgkJCQAAAA==.',
Bi='Bigçhungi:BAABLgAECn8YAAMNAAgJAx+7BQATAgANAAcJ0h27BQATAgAOAAcJlRcBGACmAQABLgAFFAUJFAAIAOIhAA==.',
Bl='Blitzen:BAABLgAECn8lAAMPAAkJ3BqDAQBzAgAPAAkJ3BqDAQBzAgAQAAEJswRKSwArAAAAAA==.',
Bo='Borealiss:BAAALgAECgYJBwABLgAECgkJJQAPANwaAA==.',
Br='Brewjigsaw:BAAALgADCgcJCgAAAA==.',
Bu='Buffsubordie:BAAALgAFFAEJAQAAAA==.',
Bw='Bwonsamdi:BAABLgAECn9EAAIRAAgJhCAPDwC2AgARAAgJhCAPDwC2AgAAAA==.',
['Bâ']='Bârks:BAABLgAECn8aAAISAAYJKCBrDQAPAgASAAYJKCBrDQAPAgAAAA==.',
Ca='Camazotz:BAAALgADCgUJBQAAAA==.Cardkun:BAAALgADCgIJAgAAAA==.Carp:BAABLgAECn8aAAITAAYJKgrKFwCjAAATAAYJKgrKFwCjAAAAAA==.',
Ch='Chargerkun:BAAALgAECgMJCwAAAA==.Chayda:BAAALgADCgEJAQAAAA==.Choleena:BAABLgAECn8aAAIMAAYJvxh3IgChAQAMAAYJvxh3IgChAQAAAA==.',
Ci='Cindress:BAAALgADCgEJAQAAAA==.',
Co='Combat:BAAALgAECgYJDAAAAA==.Coojotwo:BAAALgAECgQJBwAAAA==.',
Cr='Crewd:BAAALgADCgEJAQAAAA==.Crimzonfire:BAAALgAECgEJAQAAAA==.',
Da='Dangerfloof:BAAALgADCgQJCAAAAA==.Dangerwithin:BAACLgAFFH8jAAMUAAgJpCMVAACuAgAUAAcJhSQVAACuAgAHAAEJrh0hIwBbAAAuAAQKfyYAAhQACQnKJjMAAPsDABQACQnKJjMAAPsDAAEuAAUUAwkJAAMAViAA.Danklazercat:BAAALgADCgcJDgABLgAFFAUJFAAIAOIhAA==.Darius:BAABLgAFFH8FAAIVAAMJ6gwPFAC5AAAVAAMJ6gwPFAC5AAAAAA==.Dastraz:BAAALgAECgYJDgAAAA==.',
De='Decay:BAAALgADCgEJAQAAAA==.Deebz:BAABLgAECn8ZAAMWAAYJARziCQBZAQAGAAYJ/hnbNAB5AQAWAAYJQxjiCQBZAQAAAA==.Devkra:BAAALgADCgYJBgAAAA==.',
Dm='Dmgabsorb:BAAALgADCgIJAgAAAA==.',
Do='Doge:BAAALgADCgkJCQAAAA==.',
Dr='Dragoneux:BAAALgAFFAIJAwAAAQ==.',
Du='Dudemachine:BAAALgADCgUJBQABLgADCgkJEwAXAAAAAA==.',
['Dè']='Dèèbz:BAAALgADCgQJBAAAAA==.',
['Dö']='Dörf:BAAALgADCgMJAwAAAA==.',
Ed='Eddison:BAAALgADCgkJCQAAAA==.',
En='Enchanted:BAABLgAECn8WAAMVAAcJCRg/FwAVAQAVAAYJ6hQ/FwAVAQAIAAYJrRUiowCbAAAAAA==.Enid:BAACLgAFFH8mAAIVAAcJPCYKAAAFAwAVAAcJPCYKAAAFAwAuAAQKfxkAAhUACAmpJloBAH4DABUACAmpJloBAH4DAAAA.',
Es='Eskanor:BAAALgADCgQJBgAAAA==.',
Et='Eternalwrath:BAAALgAECgYJDAAAAA==.',
Eu='Eublar:BAAALgAECgEJAQAAAA==.',
Fa='Falzemphx:BAAALgAECgMJBgAAAA==.Farbringer:BAAALgAECgUJBgABLgAECgYJDgAXAAAAAA==.Fayanna:BAAALgADCgEJAQAAAA==.',
Fe='Felicitee:BAAALgAECgMJAwAAAA==.',
Fo='Foxxylady:BAABLgAECn8YAAIGAAYJWhwIQgBHAQAGAAYJWhwIQgBHAQAAAA==.',
Fu='Furbees:BAAALgAECgUJEAAAAA==.',
Ge='Geenon:BAAALgAECgMJBgAAAA==.Gephen:BAAALgADCgUJBQAAAA==.',
Gr='Grakdeez:BAAALgAECgUJBwABLgAECgkJEAAXAAAAAA==.Grakfist:BAAALgAECgkJEAAAAA==.Graubard:BAAALgAECgEJAQAAAA==.Gravec:BAAALgADCgEJAQAAAA==.Grimswhisper:BAAALgAECgYJDQAAAA==.Gritchen:BAABLgAECn8YAAMSAAYJYR1SEADnAQASAAYJYR1SEADnAQAYAAMJNAJ+UwAzAAAAAA==.Growler:BAAALgAECgYJEAAAAA==.Grynsel:BAABLgAECn8aAAIGAAYJOxDTRgA5AQAGAAYJOxDTRgA5AQAAAA==.',
Ha='Harlynne:BAAALgADCgkJCQAAAA==.',
Ho='Holios:BAAALgADCgYJBgABLgAECgcJFwAYAAUKAA==.',
Hu='Huntwix:BAAALgADCgYJBgAAAA==.',
Id='Idontknow:BAABLgAECn8XAAIYAAcJBQoxIwAoAQAYAAcJBQoxIwAoAQAAAA==.',
Ii='Iilia:BAAALgAECgQJBAAAAA==.',
In='Inwe:BAAALgAECgUJEQAAAA==.',
Je='Jeemana:BAAALgADCgYJBgAAAA==.',
Jo='Johnnydodge:BAABLgAECn8WAAIOAAcJOglMKQAxAQAOAAcJOglMKQAxAQAAAA==.Joyride:BAABLgAECn8aAAMZAAYJdxvZCwB/AQAZAAYJdxvZCwB/AQAaAAEJ5A4cRAEyAAAAAA==.',
Ju='Jujuwing:BAAALgAECgQJBAAAAA==.',
['Jù']='Jùde:BAAALgAECgQJBQAAAA==.',
Ka='Kaidastraza:BAAALgADCgcJCgAAAA==.Kaliel:BAAALgADCgMJAwAAAA==.Kalthas:BAAALgAECgEJAQAAAA==.Kanrethad:BAAALgAECgkJEwAAAA==.',
Ke='Kerrygan:BAAALgAECgYJEQAAAA==.',
Kh='Khaed:BAABLgAECn8ZAAIbAAkJHhHoEQCYAQAbAAkJHhHoEQCYAQAAAA==.',
Ki='Kicat:BAAALgADCgYJCgAAAA==.Kilmister:BAAALgADCgkJFwABLgAECgEJAQAXAAAAAA==.Kinara:BAAALgAECgIJAgAAAA==.',
Ko='Korthank:BAABLgAECn8WAAMbAAgJeh8oCgAvAgAbAAgJeh8oCgAvAgAMAAEJXRCJpAArAAAAAA==.Koruka:BAAALgADCgEJAQAAAA==.Kozatri:BAAALgADCgcJEwAAAA==.',
Kr='Krentead:BAAALgADCgYJBgAAAA==.',
Kw='Kwissy:BAABLgAECn8UAAIGAAYJyQQeYwDnAAAGAAYJyQQeYwDnAAAAAA==.',
La='Labellanotte:BAABLgAECn8ZAAMKAAYJ8AVJXQCoAAAKAAYJ8AVJXQCoAAALAAQJqQbwGwCCAAAAAA==.Laturalus:BAAALgADCgUJBQAAAA==.Layssa:BAABLgAECn8WAAMcAAcJ1BX9GgBeAQAcAAcJ1BX9GgBeAQAKAAUJ3ghKgwDRAAAAAA==.',
Li='Liliania:BAABLgAECn8XAAMdAAgJUgfXCwAXAQAdAAgJUgfXCwAXAQAEAAIJkgENMwEaAAAAAA==.Limper:BAAALgADCgMJAwAAAA==.Lizuket:BAAALgADCgYJBgAAAA==.',
Lo='Loveles:BAAALgADCgUJBQAAAA==.',
Lu='Lucry:BAAALgADCgkJDgAAAA==.Lucyford:BAABLgAECn8YAAMaAAYJjxhIUwBNAQAaAAYJjxhIUwBNAQADAAYJUBltLAAtAQAAAA==.Lunafloof:BAAALgAECgYJDAAAAA==.Lunaiya:BAAALgAECgUJDQAAAA==.Lunarfang:BAAALgAECgEJAQAAAA==.Lunarosa:BAAALgADCgkJCQABLgAECgEJAQAXAAAAAA==.',
Ly='Lyraali:BAABLgAECn8WAAIGAAYJ8hfINwBuAQAGAAYJ8hfINwBuAQAAAA==.',
Ma='Magemode:BAAALgAECgYJEwAAAA==.Mara:BAAALgADCgYJDwAAAA==.Mavramaria:BAAALgADCgYJCgAAAA==.',
Me='Melzemphx:BAAALgAECgYJEQAAAA==.',
Mi='Mikeberetta:BAAALgADCgMJAwAAAA==.Miniz:BAAALgADCgcJBwAAAA==.Misirlou:BAAALgADCgMJAwABLgAECgkJJQAPANwaAA==.Mizchivf:BAAALgADCgQJBgAAAA==.',
Mo='Mogal:BAAALgADCgEJAQAAAA==.Moktezuma:BAAALgAECgQJBAAAAA==.Moosifer:BAAALgADCgYJBgAAAA==.Morodos:BAAALgADCgkJFAAAAA==.',
Mu='Murtaugh:BAAALgADCgUJBQAAAA==.Mutekii:BAAALgADCgYJCwAAAA==.',
Na='Natrel:BAAALgAECgYJEgAAAA==.Natsuko:BAAALgADCgkJCQAAAA==.',
Ne='Neema:BAAALgAECgEJAwAAAA==.Nemmael:BAAALgADCgcJDwAAAA==.',
No='Noctogero:BAAALgADCgcJBwAAAA==.Nosibm:BAAALgADCgkJCQAAAA==.',
Ny='Nyxes:BAAALgADCgMJAwAAAA==.',
['Nê']='Nêo:BAAALgADCgcJBwAAAA==.',
Oc='Octane:BAAALgAECgEJAQAAAA==.Octozm:BAAALgAFFAIJBAAAAA==.',
Or='Oreofrosting:BAAALgADCgkJEwAAAA==.',
Pa='Palmstrike:BAAALgADCgEJAQAAAA==.Pañdø:BAAALgADCgMJAwAAAA==.',
Pe='Penderrin:BAAALgADCgYJBgAAAA==.',
Pi='Pidia:BAAALgADCgUJCAAAAA==.',
Po='Popes:BAACLgAFFH8JAAMGAAQJeA4HHgAgAQAGAAQJGAgHHgAgAQAWAAIJ5hH2HACiAAAuAAQKfxgAAxYACQldG28fACoCABYACAkZHW8fACoCAAYAAgnGE1GCAJIAAAAA.Popper:BAAALgADCgIJAgAAAA==.',
Pr='Preservation:BAAALgAFFAMJAwAAAA==.Prey:BAAALgADCgMJAwAAAA==.Pruina:BAAALgADCgEJAQAAAA==.',
Pu='Pub:BAAALgAECgYJDQAAAA==.',
Py='Pyrø:BAAALgAECgEJAQAAAA==.',
Ra='Radhika:BAAALgAECgIJAwAAAA==.Raelos:BAAALgAECgcJEQAAAA==.Ragebait:BAABLgAECn8aAAIaAAYJNRniRAB3AQAaAAYJNRniRAB3AQAAAA==.Raiha:BAAALgADCgMJAwAAAA==.Ranikina:BAAALgAECgUJDQAAAA==.Raynor:BAAALgADCgIJAgAAAA==.',
Re='Regasus:BAAALgAECgYJCQAAAA==.Revolt:BAABLgAECn8nAAIYAAgJrhsECwATAgAYAAgJrhsECwATAgAAAA==.Reïna:BAAALgAECgUJDwAAAA==.',
Rh='Rheía:BAAALgADCgYJBgABLgAFFAMJCQADAFYgAA==.',
Ro='Roükai:BAAALgAECgQJBQAAAA==.',
Sa='Sahariel:BAABLgAECn8mAAMSAAgJJx+zDAAaAgASAAgJJx+zDAAaAgAYAAcJwRNqGAB6AQAAAA==.',
Sc='Schwartpheil:BAAALgAECgYJEAAAAA==.Schwartzbann:BAAALgADCgcJCgABLgAECgYJEAAXAAAAAA==.Scilla:BAAALgADCgEJAQABLgAECgEJAQAXAAAAAA==.',
Sh='Shadowballz:BAAALgAECggJEQAAAA==.Shadowwing:BAAALgAECgMJBwAAAA==.Shamnorris:BAAALgADCgQJBAAAAA==.Shardemma:BAAALgADCgkJEAAAAA==.Shelfy:BAAALgAECgQJDwAAAA==.Shreddedbeef:BAAALgADCgcJBwAAAA==.Shytningbolt:BAAALgADCgMJAgAAAA==.Shælyn:BAAALgAECgMJBgAAAA==.',
Sk='Skitzo:BAAALgADCgkJFgAAAA==.',
Sp='Spinetaker:BAABLgAECn8mAAIUAAgJGSJpAwDHAgAUAAgJGSJpAwDHAgABLgAFFAUJFAAIAOIhAA==.Spyder:BAAALgADCgQJBAAAAA==.',
St='Stolensouls:BAAALgAECgUJEgAAAA==.Strawkun:BAAALgAECgIJAwAAAA==.',
Su='Sunaris:BAAALgADCgUJBQAAAA==.Suneater:BAAALgAECgQJBAAAAA==.',
['Sç']='Sçruffy:BAACLgAFFH8UAAMIAAUJ4iHcGgBtAQAIAAQJ4iHcGgBtAQAVAAEJAABxEwBXAAAuAAQKfzsAAggACQl7JgwFAIMDAAgACQl7JgwFAIMDAAAA.',
Ta='Tahtiania:BAAALgADCgYJCwAAAA==.Talas:BAAALgADCgEJAQAAAA==.Taliesin:BAAALgADCgUJBQAAAA==.',
Te='Teldryn:BAACLgAFFH8MAAIOAAQJ9BG/EQAmAQAOAAQJ9BG/EQAmAQAuAAQKfyIAAw4ACAlbJFIHADMDAA4ACAlbJFIHADMDAA0AAQneGNQ5AEkAAAAA.Telios:BAAALgAECgQJBQAAAA==.',
Th='Thaer:BAAALgADCgYJCgAAAA==.Thorendire:BAABLgAECn8kAAIeAAgJ4g55EAB8AQAeAAgJ4g55EAB8AQAAAA==.',
Ti='Tirnz:BAABLgAECn8fAAIJAAgJ+An+BwAnAQAJAAgJ+An+BwAnAQAAAA==.',
To='Tohotstotrot:BAAALgADCgQJBAAAAA==.Torlana:BAAALgADCgQJBAAAAA==.',
Tr='Trafaros:BAAALgADCgMJAwAAAA==.Trilldh:BAAALgAECgcJBQAAAA==.Trixielou:BAAALgAECggJEAAAAA==.',
Tt='Ttattoo:BAEBLgAECn8YAAMfAAYJ5QdNMADaAAAfAAYJ5QdNMADaAAAUAAEJqALQbwAbAAAAAA==.Ttattooz:BAEALgADCgMJAwABLgAECgYJGAAfAOUHAA==.',
Ty='Tyramonde:BAAALgAECgYJBgAAAA==.',
Ub='Ubonrebu:BAAALgAFFAEJAQAAAA==.',
Va='Vaelestrix:BAACLgAFFH8TAAQBAAYJIBsYBQCWAQABAAUJEyAYBQCWAQAgAAMJDBzzAgAXAQAhAAEJUQcpBgBdAAAuAAQKfzoAAwEACQnmJW4AAOUDAAEACQnmJW4AAOUDACEAAQk/JYMYAGwAAAAA.Valholla:BAAALgADCgMJAwAAAA==.Vashtanerada:BAAALgADCgYJCgAAAA==.',
Ve='Veilish:BAAALgADCgYJCQAAAA==.',
Vo='Voiddøøde:BAAALgADCgcJBwAAAA==.Voidsocket:BAAALgAECgcJAQAAAA==.Voidtoes:BAAALgADCgQJBAAAAA==.',
Vu='Vulpvs:BAAALgADCgcJCwAAAA==.',
Vv='Vvlpvs:BAAALgADCgQJBAAAAA==.',
Wa='Warherald:BAABLgAECn8UAAIiAAYJRA9AGAD+AAAiAAYJRA9AGAD+AAAAAA==.Wasntme:BAAALgADCgYJBgABLgAECgcJFwAYAAUKAA==.',
We='Wednesday:BAACLgAFFH8WAAIVAAcJwxHqAgCZAQAVAAcJwxHqAgCZAQAuAAQKfx0AAhUACAmVImIFAOsCABUACAmVImIFAOsCAAAA.',
Wh='Whoops:BAAALgADCgcJBwAAAA==.',
Xa='Xalaria:BAAALgAECgYJDAAAAA==.',
Xi='Xirek:BAABLgAECn8aAAIiAAYJ4Q9vFwAGAQAiAAYJ4Q9vFwAGAQAAAA==.',
Yr='Yreasak:BAABLgAECn8VAAMEAAYJfwjpcADoAAAEAAYJmAbpcADoAAAjAAMJFwj8GgCeAAAAAA==.Yrisan:BAAALgADCgUJBQABLgAECgYJFQAEAH8IAA==.',
Ys='Yseulde:BAAALgADCgkJDwABLgAECgYJFQAEAH8IAA==.',
Zo='Zonako:BAAALgAECgcJEgAAAA==.Zoogranby:BAAALgADCgYJBgAAAA==.',
Zu='Zurâ:BAAALgAECgYJEQAAAA==.',
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

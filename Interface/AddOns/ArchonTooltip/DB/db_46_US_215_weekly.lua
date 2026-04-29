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

local lookup = {'Rogue-Subtlety','Monk-Windwalker','Unknown-Unknown','Hunter-Survival','Hunter-BeastMastery','Monk-Mistweaver','Shaman-Restoration','DeathKnight-Unholy','Evoker-Devastation','Evoker-Preservation','Shaman-Elemental','DeathKnight-Blood','Shaman-Enhancement','Hunter-Marksmanship','Priest-Shadow','Priest-Holy','Warrior-Fury','Warrior-Arms','DemonHunter-Havoc','DeathKnight-Frost','Rogue-Assassination',}
local provider = {region='US',realm='TheScryers',name='US',type='weekly',zone=46,date='2026-04-24',data={Ae='Aelin:BAAALgAECgQJBAAAAA==.',
Ai='Airo:BAABLgAECn8fAAIBAAgJIBX4AwDRAQABAAgJIBX4AwDRAQAAAA==.',
Ak='Akaris:BAAALgAECgUJCgAAAA==.',
Al='Alainea:BAAALgAECgEJAQAAAA==.Alispia:BAAALgADCgMJAwAAAA==.',
Am='Amaterasu:BAAALgAFFAMJAwABLgAFFAYJGQACADgiAA==.Ambre:BAAALgAECgUJBQAAAA==.Amerdro:BAAALgAECgQJCQAAAA==.Amoreesa:BAAALgAECgQJBAAAAA==.',
An='Andross:BAAALgADCgcJEQABLgAECgYJCQADAAAAAA==.Angrytestie:BAAALgAECgEJAQAAAA==.Anomaly:BAABLgAECn8fAAMEAAcJCyItBgCgAgAEAAcJCyItBgCgAgAFAAIJdg4luQBQAAAAAA==.Anthousai:BAAALgADCgQJBAAAAA==.',
Ar='Ara:BAABLgAFFH8JAAIGAAUJexp5AwC7AQAGAAUJexp5AwC7AQAAAA==.',
As='Asylum:BAAALgADCgcJDQAAAA==.',
Au='Aura:BAAALgAECgMJAwAAAA==.',
Ax='Axl:BAAALgAECgUJCgAAAA==.',
Ay='Aylíth:BAAALgAECgYJBgABLgAFFAYJGQACADgiAA==.',
Ba='Bacon:BAAALgADCgkJCQAAAA==.Bahheals:BAAALgAECgYJDAAAAA==.Banjoo:BAAALgAECgYJDgAAAA==.Baruk:BAABLgAECn8VAAIHAAgJERPcMADDAQAHAAgJERPcMADDAQAAAA==.',
Be='Beauzericka:BAAALgADCgEJAQAAAA==.Beeswax:BAAALgADCgkJCQAAAA==.',
Bi='Bigçhungi:BAAALgAECgcJEQABLgAFFAUJDgAIAOIZAA==.',
Bl='Blitzen:BAABLgAECn8YAAMJAAgJdBnACQBDAgAJAAgJdBnACQBDAgAKAAEJswRCSwArAAAAAA==.',
Bo='Borealiss:BAAALgAECgQJBAABLgAECggJGAAJAHQZAA==.',
Br='Brewjigsaw:BAAALgADCgcJCgAAAA==.',
Bu='Buffsubordie:BAAALgAFFAEJAQAAAA==.',
Bw='Bwonsamdi:BAABLgAECn9EAAILAAgJhCAKDwC2AgALAAgJhCAKDwC2AgAAAA==.',
['Bâ']='Bârks:BAAALgAECgQJCgAAAA==.',
Ca='Camazotz:BAAALgADCgUJBQAAAA==.Cardkun:BAAALgADCgIJAgAAAA==.Carp:BAAALgAECgUJDgAAAA==.',
Ch='Chargerkun:BAAALgAECgMJBgAAAA==.Chayda:BAAALgADCgEJAQAAAA==.Choleena:BAAALgAECgQJCgAAAA==.',
Ci='Cindress:BAAALgADCgEJAQAAAA==.',
Co='Combat:BAAALgAECgQJBwAAAA==.Coojotwo:BAAALgADCgkJEwAAAA==.',
Cr='Crewd:BAAALgADCgEJAQAAAA==.Crimzonstorm:BAAALgAECgEJAQAAAA==.',
Da='Dangerfloof:BAAALgADCgMJBAAAAA==.Dangerwithin:BAACLgAFFH8ZAAMCAAYJOCIcAADIAQACAAUJdCYcAADIAQAGAAEJ/BAACwBSAAAuAAQKfyYAAgIACQnHJjMAAPsDAAIACQnHJjMAAPsDAAAA.Danklazercat:BAAALgADCgcJDgABLgAFFAUJDgAIAOIZAA==.Darius:BAAALgAECgYJBgAAAA==.Dastraz:BAAALgAECgYJDQAAAA==.',
De='Deebz:BAAALgAECgQJCgAAAA==.',
Dm='Dmgabsorb:BAAALgADCgIJAgAAAA==.',
Do='Doge:BAAALgADCgkJCQAAAA==.',
Dr='Dragoneux:BAAALgAECgkJFAAAAQ==.',
Du='Dudemachine:BAAALgADCgUJBQABLgADCgkJEwADAAAAAA==.',
['Dö']='Dörf:BAAALgADCgMJAwAAAA==.',
Ed='Eddison:BAAALgADCgkJCQAAAA==.',
El='Elementhor:BAAALgADCgcJBwAAAA==.',
En='Enchanted:BAAALgAECgYJDwAAAA==.Enid:BAACLgAFFH8bAAIMAAcJESYJAAAGAwAMAAcJESYJAAAGAwAuAAQKfxkAAgwACAmpJlUBAH4DAAwACAmpJlUBAH4DAAAA.',
Es='Eskanor:BAAALgADCgQJBgAAAA==.',
Eu='Eublar:BAAALgAECgEJAQAAAA==.',
Fa='Falzemphx:BAAALgAECgMJAwAAAA==.Farbringer:BAAALgAECgQJBQABLgAECgYJDQADAAAAAA==.Fayanna:BAAALgADCgEJAQAAAA==.',
Fe='Felicitee:BAAALgAECgMJAwAAAA==.',
Fo='Foxxylady:BAAALgAECgUJDwAAAA==.',
Fu='Furbees:BAAALgAECgQJCAAAAA==.',
Ge='Geenon:BAAALgAECgMJAwAAAA==.Gephen:BAAALgADCgUJBQAAAA==.',
Gr='Grakdeez:BAAALgADCgEJAQAAAA==.Grakfist:BAAALgAECgcJDgAAAA==.Gravec:BAAALgADCgEJAQAAAA==.Grimswhisper:BAAALgAECgYJDQAAAA==.Gritchen:BAAALgAECgQJCAAAAA==.Growler:BAAALgAECgQJBAAAAA==.Grynsel:BAAALgAECgQJCgAAAA==.',
Ha='Harlynne:BAAALgADCgkJCQAAAA==.',
Ho='Holios:BAAALgADCgYJBgABLgAECgUJCgADAAAAAA==.',
Hu='Huntwix:BAAALgADCgYJBgAAAA==.',
Id='Idontknow:BAAALgAECgUJCgAAAA==.',
In='Inwe:BAAALgAECgQJBwAAAA==.',
Je='Jeemana:BAAALgADCgYJBgAAAA==.',
Jo='Johnnydodge:BAAALgAECgUJCQAAAA==.Joyride:BAAALgAECgQJCgAAAA==.',
Ju='Jujuwing:BAAALgADCgkJEwAAAA==.',
['Jù']='Jùde:BAAALgAECgEJAQAAAA==.',
Ka='Kaidastraza:BAAALgADCgcJCgAAAA==.Kaliel:BAAALgADCgMJAwAAAA==.Kalthas:BAAALgAECgEJAQAAAA==.Kanrethad:BAAALgAECggJCAAAAA==.',
Ke='Kerrygan:BAAALgAECgUJCQAAAA==.',
Kh='Khaed:BAABLgAECn8UAAINAAgJsRDnEQCYAQANAAgJsRDnEQCYAQAAAA==.',
Ki='Kicat:BAAALgADCgYJBgAAAA==.Kilmister:BAAALgADCgkJFgAAAA==.Kinara:BAAALgAECgIJAgAAAA==.',
Ko='Korthank:BAAALgAECggJEgAAAA==.Koruka:BAAALgADCgEJAQAAAA==.Kozatri:BAAALgADCgcJDAAAAA==.',
Kr='Krentead:BAAALgADCgYJBgAAAA==.',
Kw='Kwissy:BAAALgAECgYJCAAAAA==.',
La='Labellanotte:BAAALgAECgQJCQAAAA==.Laturalus:BAAALgADCgUJBQAAAA==.Layssa:BAAALgAECgcJDQAAAA==.',
Li='Liliania:BAAALgAECgYJDwAAAA==.Limper:BAAALgADCgMJAwAAAA==.Lizuket:BAAALgADCgYJBgAAAA==.',
Lo='Loveles:BAAALgADCgUJBQAAAA==.',
Lu='Lucry:BAAALgADCgkJDgAAAA==.Lucyford:BAAALgAECgUJCQAAAA==.Lunaiya:BAAALgAECgQJCQAAAA==.Lunarfang:BAAALgAECgEJAQAAAA==.Lunarosa:BAAALgADCgkJCQABLgAECgEJAQADAAAAAA==.',
Ly='Lyraali:BAAALgAECgQJCgAAAA==.',
Ma='Magemode:BAAALgAECgYJDAAAAA==.Mara:BAAALgADCgYJDwAAAA==.Mavramaria:BAAALgADCgYJCgAAAA==.',
Me='Melzemphx:BAAALgAECgUJBwAAAA==.',
Mi='Miniz:BAAALgADCgcJBwAAAA==.Misirlou:BAAALgADCgMJAwABLgAECggJGAAJAHQZAA==.Mizchivf:BAAALgADCgQJBgAAAA==.',
Mo='Mogal:BAAALgADCgEJAQAAAA==.Moktezuma:BAAALgAECgQJBAAAAA==.Morodos:BAAALgADCgkJFAAAAA==.',
Mu='Mutekii:BAAALgADCgUJBgAAAA==.',
Na='Natrel:BAAALgAECgYJCAAAAA==.',
Ne='Neema:BAAALgAECgEJAQAAAA==.Nemmael:BAAALgADCgcJDwAAAA==.',
No='Noctogero:BAAALgADCgcJBwAAAA==.',
Ny='Nyxes:BAAALgADCgMJAwAAAA==.',
Oc='Octane:BAAALgAECgEJAQAAAA==.Octozm:BAAALgAFFAIJBAAAAA==.',
Or='Oreofrosting:BAAALgADCgkJEwAAAA==.',
Pa='Palmstrike:BAAALgADCgEJAQAAAA==.Pañdø:BAAALgADCgMJAwAAAA==.',
Pi='Pidia:BAAALgADCgUJCAAAAA==.',
Po='Popes:BAACLgAFFH8FAAMFAAMJBhIdCQD1AAAFAAMJgQkdCQD1AAAOAAIJ5hHgHACiAAAuAAQKfxgAAw4ACQlGG7sfACQCAA4ACAkZHbsfACQCAAUAAglhExYuAJ8AAAAA.Popper:BAAALgADCgIJAgAAAA==.',
Pr='Prey:BAAALgADCgMJAwAAAA==.Pruina:BAAALgADCgEJAQAAAA==.',
Pu='Pub:BAAALgAECgYJDQAAAA==.',
Ra='Radhika:BAAALgAECgIJAwAAAA==.Raelos:BAAALgAECgYJDgAAAA==.Ragebait:BAAALgAECgQJCgAAAA==.Raiha:BAAALgADCgMJAwAAAA==.Ranikina:BAAALgAECgQJCAAAAA==.Raynor:BAAALgADCgIJAgAAAA==.',
Re='Revolt:BAABLgAECn8gAAIPAAgJsBi2FQA8AgAPAAgJsBi2FQA8AgAAAA==.Reïna:BAAALgAECgMJBQAAAA==.',
Rh='Rheía:BAAALgADCgYJBgABLgAFFAYJGQACADgiAA==.',
Ro='Roükai:BAAALgAECgQJBQAAAA==.',
Sa='Sahariel:BAABLgAECn8bAAIQAAgJZB7yAgAtAgAQAAgJZB7yAgAtAgAAAA==.',
Sc='Schwartpheil:BAAALgAECgYJEAAAAA==.Schwartzbann:BAAALgADCgcJCgABLgAECgYJEAADAAAAAA==.Scilla:BAAALgADCgEJAQABLgADCgkJFgADAAAAAA==.',
Sh='Shadowballz:BAAALgAECgUJCwAAAA==.Shadowwing:BAAALgAECgMJBwAAAA==.Shamnorris:BAAALgADCgQJBAAAAA==.Shardemma:BAAALgADCgYJCAAAAA==.Shelfy:BAAALgAECgQJCwAAAA==.Shreddedbeef:BAAALgADCgcJBwAAAA==.Shytningbolt:BAAALgADCgMJAgAAAA==.Shælyn:BAAALgAECgMJBgAAAA==.',
Sk='Skitzo:BAAALgADCgkJFgAAAA==.',
Sp='Spinetaker:BAABLgAECn8YAAICAAgJ+BywAgAGAgACAAgJ+BywAgAGAgABLgAFFAUJDgAIAOIZAA==.',
St='Stolensouls:BAAALgAECgQJCAAAAA==.Strawkun:BAAALgAECgIJAwAAAA==.',
['Sç']='Sçruffy:BAACLgAFFH8OAAMIAAUJ4hmmBQBgAQAIAAQJ4hmmBQBgAQAMAAEJAABnEwBXAAAuAAQKfzMAAggACQndJQsFAIMDAAgACQndJQsFAIMDAAAA.',
Ta='Tahtiania:BAAALgADCgYJBwAAAA==.Talas:BAAALgADCgEJAQAAAA==.Taliesin:BAAALgADCgUJBQAAAA==.',
Te='Teldryn:BAABLgAECn8eAAMRAAgJyCNYBwAzAwARAAgJyCNYBwAzAwASAAEJ3hjSOQBJAAAAAA==.Telios:BAAALgAECgQJBQAAAA==.',
Th='Thorendire:BAABLgAECn8UAAITAAYJrQoTCgD4AAATAAYJrQoTCgD4AAAAAA==.',
Ti='Tirnz:BAABLgAECn8UAAIUAAcJoweZCABdAQAUAAcJoweZCABdAQAAAA==.',
To='Tohotstotrot:BAAALgADCgQJBAAAAA==.Torlana:BAAALgADCgQJBAAAAA==.',
Tr='Trafaros:BAAALgADCgMJAwAAAA==.Trilldh:BAAALgAECgcJBQAAAA==.Trixielou:BAAALgAECgUJCgAAAA==.',
Tt='Ttattoo:BAEALgAECgUJDQAAAA==.Ttattooz:BAEALgADCgMJAwABLgAECgUJDQADAAAAAA==.',
Ub='Ubonrebu:BAAALgAFFAEJAQAAAA==.',
Va='Vaelestrix:BAACLgAFFH8MAAMBAAUJ7RoSBQCWAQABAAQJ1B8SBQCWAQAVAAEJUQcnBgBdAAAuAAQKfzEAAwEACQn8JG0AAOUDAAEACQn8JG0AAOUDABUAAQk/JX8YAGwAAAAA.Valholla:BAAALgADCgMJAwAAAA==.Vashtanerada:BAAALgADCgMJBAAAAA==.',
Ve='Veilish:BAAALgADCgYJCQAAAA==.',
Vo='Voiddøøde:BAAALgADCgcJBwAAAA==.Voidtoes:BAAALgADCgQJBAAAAA==.',
Vu='Vulpvs:BAAALgADCgcJCwAAAA==.',
Vv='Vvlpvs:BAAALgADCgQJBAAAAA==.',
Wa='Warherald:BAAALgAECgQJCAAAAA==.',
We='Wednesday:BAACLgAFFH8RAAIMAAYJYRPoAgCZAQAMAAYJYRPoAgCZAQAuAAQKfx0AAgwACAmVIl8FAOsCAAwACAmVIl8FAOsCAAAA.',
Xa='Xalaria:BAAALgAECgMJCAAAAA==.',
Xi='Xirek:BAAALgAECgQJCgAAAA==.',
Yr='Yreasak:BAAALgAECgYJCQAAAA==.Yrisan:BAAALgADCgEJAQABLgAECgYJCQADAAAAAA==.',
Ys='Yseulde:BAAALgADCgkJCQABLgAECgYJCQADAAAAAA==.',
Zo='Zonako:BAAALgAECgcJEgAAAA==.Zoogranby:BAAALgADCgYJBgAAAA==.',
Zu='Zurâ:BAAALgAECgUJCQAAAA==.',
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

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

local lookup = {'Priest-Discipline','Priest-Holy','Unknown-Unknown','Paladin-Retribution','Hunter-Marksmanship','Hunter-BeastMastery','Mage-Frost','DemonHunter-Devourer','Warlock-Demonology','Monk-Brewmaster','Warrior-Protection','Hunter-Survival','Druid-Restoration','Shaman-Elemental','Shaman-Restoration','DeathKnight-Unholy','DeathKnight-Frost','Druid-Balance','Rogue-Subtlety','Rogue-Assassination','Evoker-Preservation','Evoker-Devastation','Warrior-Fury','Paladin-Protection','Paladin-Holy','Evoker-Augmentation','Monk-Mistweaver','Warrior-Arms','Shaman-Enhancement','Mage-Arcane','Priest-Shadow','Rogue-Outlaw','Monk-Windwalker',}
local provider = {region='US',realm='Ysondre',name='US',type='weekly',zone=46,date='2026-05-08',data={Al='Alex:BAAALgADCgMJAwAAAA==.',
An='Angalius:BAAALgAECgYJCgAAAA==.',
Ap='Apathy:BAAALgAECgEJAQAAAA==.',
Ar='Aralid:BAAALgAECgUJCgAAAA==.Ariadné:BAABLgAECn8WAAMBAAgJDh0YCgA0AgABAAgJDh0YCgA0AgACAAIJTAntcwBYAAAAAA==.Artasha:BAAALgADCgIJAwAAAA==.',
Ba='Badassmf:BAAALgADCgIJAgAAAA==.',
Be='Bearlover:BAAALgAECgcJDwAAAA==.Beau:BAAALgAECgQJBAAAAA==.Belal:BAAALgADCgIJAgAAAA==.',
Bi='Birdflù:BAAALgADCgUJBQAAAA==.Biscuits:BAAALgADCgYJBgAAAA==.Bitron:BAAALgAECgkJBAAAAA==.',
Bo='Bomi:BAAALgAECgIJAwAAAA==.Boogiesera:BAAALgADCgQJBAABLgAECgcJEgADAAAAAA==.Bootles:BAAALgAECgcJEgAAAA==.Bowl:BAAALgADCgkJCQAAAA==.',
Br='Brewslee:BAAALgAECgkJAQAAAA==.',
Bu='Bulltastich:BAAALgADCgUJBgABLgADCgcJBwADAAAAAA==.Bullwings:BAAALgAECgEJAQAAAA==.Buttholemu:BAAALgADCgYJBgAAAA==.',
Ca='Calanthe:BAAALgAECgYJBwAAAA==.',
Ch='Charrend:BAABLgAECn8eAAIEAAgJJQW6agAYAQAEAAgJJQW6agAYAQAAAA==.',
Cl='Clutchmedic:BAABLgAFFH8IAAMFAAUJEQwrEAAwAQAFAAQJfw0rEAAwAQAGAAEJxwczJgBVAAAAAA==.',
Co='Completed:BAAALgADCgUJBQAAAA==.',
Cp='Cptloveme:BAABLgAECn8eAAIHAAYJaRoKXwBUAQAHAAYJaRoKXwBUAQAAAA==.',
Cr='Crazon:BAAALgADCgcJIAAAAA==.Cropduster:BAACLgAFFH8FAAIIAAMJzwayOwDCAAAIAAMJzwayOwDCAAAuAAQKfxwAAggACAneGbo1ACACAAgACAneGbo1ACACAAAA.Crushed:BAAALgADCgMJAwABLgAECggJIgAJAPYcAA==.',
Ct='Cthulhu:BAACLgAFFH8SAAIJAAQJdBdJIwAtAQAJAAQJdBdJIwAtAQAuAAQKfy8AAgkACAnPHrIdAKQCAAkACAnPHrIdAKQCAAAA.',
Cu='Cursedpriest:BAAALgADCgUJBQAAAA==.',
Da='Dad:BAAALgAECgEJAgAAAA==.Darner:BAAALgAECgQJBAAAAA==.',
De='Delnarei:BAAALgADCgEJAQAAAA==.Demise:BAAALgADCgYJCgABLgAECggJHwAHALkdAA==.Destiniemonk:BAAALgAECgYJCgAAAA==.Deviant:BAAALgADCgIJAgAAAA==.',
Do='Dolo:BAAALgADCgIJAgAAAA==.Doloni:BAAALgAECgUJDAAAAA==.Doomd:BAEALgAECgcJEQAAAA==.Doomdtrooper:BAEALgAECgcJDgABLgAECgcJEQADAAAAAA==.Dotti:BAAALgADCgkJCQABLgAECgYJFQAGADAJAA==.Dotts:BAABLgAECn8dAAIJAAcJ8hI0PQB0AQAJAAcJ8hI0PQB0AQAAAA==.',
Dr='Drewied:BAAALgADCgEJAQAAAA==.Drfinger:BAAALgAECgEJAQABLgAECggJIAAKAFMlAA==.Droodorei:BAAALgADCggJJAAAAA==.',
Du='Durianz:BAAALgAECgYJCwAAAA==.',
Dw='Dwnloadedchi:BAAALgAECggJCgAAAA==.Dwnloadedski:BAAALgAECgcJEgAAAA==.',
Eg='Eggenan:BAAALgAECgEJAQAAAA==.',
Ei='Eiskält:BAAALgAECgUJDgAAAA==.',
El='Ellay:BAAALgAECgYJEAAAAA==.',
Em='Emofumu:BAAALgADCgYJBgABLgAECgkJFAALAPQjAA==.',
En='Endrin:BAAALgAECgUJCwAAAA==.',
Ew='Eww:BAEBLgAECn8tAAIMAAkJrBSzBQBbAgAMAAkJrBSzBQBbAgAAAA==.',
Ez='Ezzak:BAAALgADCgQJBAAAAA==.',
Fe='Felfirefoxxo:BAAALgAECgMJAwAAAA==.Felldeeds:BAABLgAECn8bAAINAAcJhCVuCwCSAgANAAcJhCVuCwCSAgAAAA==.Fellshock:BAAALgAECgQJBAABLgAECgcJGwANAIQlAA==.Felthazzar:BAAALgAECgYJBgAAAA==.Fent:BAACLgAFFH8NAAMOAAQJEw6QEQAlAQAOAAQJEw6QEQAlAQAPAAEJRAtHPQBHAAAuAAQKfywAAw8ACQlAF/MgABkCAA8ACQlAF/MgABkCAA4ABwlrIOEMAA4CAAAA.',
Fi='Fingerblastn:BAAALgADCgcJBwABLgAECggJIAAKAFMlAA==.Fingerr:BAABLgAECn8gAAIKAAgJUyU2AgDyAgAKAAgJUyU2AgDyAgAAAA==.Finneagan:BAAALgADCgEJAQAAAA==.',
Fl='Flinkorandus:BAAALgAECgEJAQABLgAECgUJCgADAAAAAA==.Flokki:BAAALgAECgcJDwAAAA==.',
Fo='Foxxowo:BAAALgAECgQJBwAAAA==.',
Fr='Froztbane:BAEALgAECgcJDwABLgAECgkJNgAIAK0gAA==.Froztbanshee:BAEBLgAECn82AAIIAAkJrSCoCACaAgAIAAkJrSCoCACaAgAAAA==.',
Gh='Ghats:BAAALgAECgEJAQAAAA==.Ghuss:BAAALgAECgUJBQAAAA==.',
Gl='Glass:BAAALgAECgUJCwAAAA==.',
Go='Gogo:BAAALgAECgUJCwABLgAECgYJBgADAAAAAA==.',
Gr='Grimzyn:BAACLgAFFH8JAAIQAAQJvxRFJABXAQAQAAQJvxRFJABXAQAuAAQKfxwAAhAACAljHLo2AFwCABAACAljHLo2AFwCAAAA.Grudge:BAABLgAECn8mAAMRAAgJmxC+BQDVAQARAAgJpQ6+BQDVAQAQAAgJkg5gOwCNAQAAAA==.',
Ha='Haircules:BAAALgAECgQJBgAAAA==.Harrowhark:BAABLgAECn8fAAIQAAgJhRyzIAAGAgAQAAgJhRyzIAAGAgAAAA==.',
He='Herambae:BAAALgADCgYJBgAAAA==.Herculesátan:BAAALgADCgYJCAAAAA==.',
Ho='Hornstache:BAAALgADCgEJAQAAAA==.',
Hy='Hyacinth:BAABLgAECn8dAAISAAkJWRGDDAACAgASAAkJWRGDDAACAgAAAA==.Hyria:BAAALgADCgkJDwABLgAECgcJEgADAAAAAA==.Hyun:BAAALgADCgYJBgAAAA==.',
Ia='Iamfinn:BAAALgAECgEJAQAAAA==.Iamomegafox:BAABLgAECn8qAAMTAAgJpRjnCgDyAQATAAgJkBbnCgDyAQAUAAYJ8RfkCwBoAQAAAA==.',
Ig='Ignax:BAACLgAFFH8JAAMVAAQJYwhpEwDWAAAVAAQJYwhpEwDWAAAWAAEJWgUNCwBNAAAuAAQKfyEAAxUACAkSFUsUAAECABUACAkSFUsUAAECABYABglWCFYlAPoAAAAA.',
Im='Imomeganisha:BAAALgAECgQJBwABLgAECggJKgATAKUYAA==.Imsparticus:BAABLgAECn8VAAMXAAYJxgiVMgAAAQAXAAYJxgiVMgAAAQALAAQJcAHOOwBtAAAAAA==.',
Io='Ionias:BAABLgAECn8UAAMYAAgJ2xz3FwBXAQAYAAYJERn3FwBXAQAZAAgJpALoLgAdAQAAAA==.',
Ja='Jackblack:BAAALgAECgIJBAABLgAFFAMJBQAIAM8GAA==.Jaquelius:BAAALgAECgUJDgAAAA==.',
Jo='Joeworgen:BAAALgAECgEJAQAAAA==.Johadan:BAABLgAECn8WAAIEAAYJPgZbhQDiAAAEAAYJPgZbhQDiAAAAAA==.',
Ka='Kaelx:BAAALgAECgEJBAAAAA==.Kafizz:BAABLgAECn8fAAIJAAkJWxUnJgDQAQAJAAkJWxUnJgDQAQAAAA==.Kagnara:BAAALgADCgUJBQAAAA==.',
Ke='Keely:BAAALgAECgIJAgAAAA==.Keolmont:BAAALgADCgEJAQAAAA==.',
Ki='Kinla:BAAALgAECgQJBAAAAA==.Kirakitsune:BAAALgADCgcJBwAAAA==.Kireag:BAAALgADCgIJAgAAAA==.',
Ko='Kooppa:BAAALgADCgQJBAAAAA==.',
Ku='Kuromigirl:BAAALgAECgUJCgAAAA==.',
La='Labchimpette:BAAALgAECgYJDgAAAA==.Lagerthä:BAAALgAECgUJBgABLgAECggJEwADAAAAAA==.',
Li='Link:BAAALgADCgcJBwAAAA==.Lione:BAAALgAECgcJEwAAAA==.Lith:BAACLgAFFH8HAAIVAAMJgRTgDQD9AAAVAAMJgRTgDQD9AAAuAAQKfycAAxUACAmuGWkFAEMCABUACAmuGWkFAEMCABoACAlgELYdANcBAAAA.Litterbocks:BAAALgAECgMJBAAAAA==.Littlepriest:BAAALgADCgEJAQAAAA==.',
Ly='Lyzandra:BAAALgADCgYJCgAAAA==.',
['Lì']='Lìllyanna:BAABLgAECn8fAAIYAAgJdxLACwCAAQAYAAgJdxLACwCAAQAAAA==.',
Ma='Mailbox:BAAALgAECgEJAQABLgAFFAcJGAAZAOYYAA==.Malock:BAAALgADCgkJCQAAAA==.Mango:BAAALgAECgEJAQAAAA==.Matcha:BAABLgAECn8UAAIbAAkJ5BkIBgCnAgAbAAkJ5BkIBgCnAgAAAA==.Mauler:BAAALgAECgQJCAAAAA==.',
Me='Melinoë:BAAALgADCgUJBQAAAA==.Meowhunter:BAAALgAECgUJCQAAAA==.',
Mi='Miaraa:BAAALgAECgcJDwAAAA==.Minervå:BAAALgADCgMJAwAAAA==.',
Mo='Mogdor:BAABLgAECn8XAAMaAAgJrRirCwAQAgAaAAgJrRirCwAQAgAWAAMJZBRiLAC4AAAAAA==.Moonpeach:BAABLgAECn8WAAINAAYJhhG4MwBMAQANAAYJhhG4MwBMAQAAAA==.Motex:BAABLgAECn8eAAITAAgJ8QJ/MwBvAQATAAgJ8QJ/MwBvAQAAAA==.',
Na='Naturebug:BAAALgAECgYJCgAAAA==.',
Ne='Ned:BAECLgAFFH8MAAIXAAQJ7B7FCABbAQAXAAQJ7B7FCABbAQAuAAQKfz4AAxcACAmkJVgDAHkDABcACAmkJVgDAHkDABwABAllJIUPAKMBAAAA.Netre:BAAALgAECgYJEQAAAA==.',
Ni='Ninax:BAAALgAECgYJBgAAAA==.',
Ny='Nylian:BAAALgAECgMJBAAAAA==.',
Ob='Obamasmama:BAAALgAECgYJCwAAAA==.',
Ol='Oldmantom:BAAALgADCgYJBgAAAA==.',
Or='Ormgorg:BAABLgAECn8TAAIdAAcJHR16BgDWAQAdAAcJHR16BgDWAQAAAA==.Orpheus:BAABLgAECn8sAAMPAAkJASHVAQBVAwAPAAkJASHVAQBVAwAOAAMJNQoeRgCQAAAAAA==.',
Oz='Oza:BAAALgAECgMJBgAAAA==.',
Pa='Pandamoniium:BAAALgAECgcJDQABLgAECggJJgAHAHsgAA==.Pandamonk:BAACLgAFFH8NAAIKAAQJuSW2AwC8AQAKAAQJuSW2AwC8AQAuAAQKfysAAgoACQlwJBIBADUDAAoACQlwJBIBADUDAAAA.',
Pe='Percy:BAEBLgAECn8VAAIeAAcJzg35AwBhAQAeAAcJzg35AwBhAQAAAA==.',
Pi='Pickleswag:BAAALgADCgMJAwAAAA==.',
Pr='Preservation:BAAALgAECgMJAwAAAA==.',
Ra='Raastamon:BAAALgADCgEJAQAAAA==.Raekitty:BAABLgAECn8XAAINAAgJgR6SFACRAgANAAgJgR6SFACRAgAAAA==.Rama:BAAALgAECgEJAQABLgAECgYJGQAHAPQcAA==.',
Re='Redrover:BAAALgADCggJDgAAAA==.Reia:BAAALgADCgcJBwAAAA==.',
Rh='Rhara:BAAALgADCgYJEgAAAA==.Rhoem:BAABLgAECn8gAAIRAAgJzB+wBQDXAQARAAgJzB+wBQDXAQAAAA==.',
Ri='Rin:BAEALgADCgMJAwABLgAECggJHQAbANEeAA==.',
Ro='Roger:BAAALgAECgYJEwAAAA==.',
Ru='Rumor:BAACLgAFFH8ZAAMUAAYJByNgAAD7AQAUAAYJByNgAAD7AQATAAQJsRlxBwBtAQAuAAQKfzQAAxMACAnJJpQKAOkCABMACAnTJJQKAOkCABQACAmJJj4FAKsBAAAA.Run:BAAALgAECgEJAQAAAA==.',
Se='Secretgrace:BAAALgADCgQJBAABLgAECgcJEwAdAB0dAA==.Senortickle:BAAALgAECgcJEgAAAA==.',
Sh='Shadowmoone:BAABLgAECn8VAAIGAAYJMAliWAAGAQAGAAYJMAliWAAGAQAAAA==.Shaki:BAAALgAECgQJBwAAAA==.Shalendris:BAAALgAECgEJAQAAAA==.Shalestrasz:BAABLgAECn8XAAQWAAgJNQgtIQAjAQAWAAgJFwUtIQAjAQAaAAMJFQpYQwCLAAAVAAIJVQFJRQBGAAAAAA==.Shibal:BAAALgADCggJCAAAAA==.Shochu:BAAALgAECgcJDwAAAA==.',
So='Soju:BAAALgAECgUJBQAAAA==.Somnera:BAAALgAECgEJAQABLgAECgcJEwAdAB0dAA==.Soyboymalfoy:BAAALgAECggJEAAAAA==.',
Sp='Sp:BAACLgAFFH8IAAICAAIJ4Q/LDQCPAAACAAIJ4Q/LDQCPAAAuAAQKfyoAAwIACAmvI8YEAMICAAIACAmvI8YEAMICAB8AAQl5ClVSADQAAAAA.',
St='Sterility:BAAALgAECgUJEAAAAA==.',
Sw='Switchfoot:BAABLgAECn8oAAMgAAgJeB5IAQB5AgAgAAgJdR5IAQB5AgAUAAEJJRPYGwBJAAAAAA==.',
['Sï']='Sïeghart:BAAALgADCgUJBQAAAA==.',
Te='Tenzin:BAAALgADCgQJBAABLgAFFAQJEgAJAHQXAA==.Tex:BAAALgADCgcJDgAAAA==.',
Ti='Timerunner:BAAALgADCgYJBgAAAA==.',
To='Totingtotems:BAAALgADCgcJDQAAAA==.Touchofdeath:BAABLgAECn8WAAIhAAcJ3As5LQDTAAAhAAcJ3As5LQDTAAAAAA==.',
Ug='Ughnga:BAAALgAECgMJAwABLgAECgcJHQAJAPISAA==.',
Va='Vandli:BAAALgAECgMJBAAAAA==.',
Ve='Velzard:BAAALgAECgYJEgAAAA==.Verti:BAAALgAECgYJCwAAAA==.Veylan:BAAALgAECgEJAQAAAA==.',
Vi='Visona:BAAALgADCgMJAwAAAA==.',
Vo='Voíshara:BAAALgADCgUJCwAAAA==.',
['Vö']='Vöre:BAAALgAECgYJBwAAAA==.',
Wa='Wanagi:BAAALgADCgEJAQAAAA==.',
Wh='Whitessin:BAAALgADCgcJBwAAAA==.',
Wi='Wither:BAACLgAFFH8FAAIQAAQJMhFvFQBOAQAQAAQJMhFvFQBOAQAuAAQKfxcAAhAACAldIps1AGACABAACAldIps1AGACAAEuAAUUBgkZABQAByMA.',
Wy='Wyspur:BAAALgADCgYJCgAAAA==.',
Yo='Yofoxxo:BAACLgAFFH8SAAIZAAYJsRvWAwCoAQAZAAYJsRvWAwCoAQAuAAQKfykABBkACAldJDsEACoDABkACAldJDsEACoDAAQABQkNDp+0ABsBABgAAgmLCLc9AEcAAAAA.',
Yu='Yulon:BAAALgAECgQJBwABLgAFFAIJCAACAOEPAA==.',
Za='Zaraerivia:BAAALgAECgYJDgAAAA==.Zarlon:BAAALgAECgIJBAABLgAECgYJGQAHAPQcAA==.',
Ze='Zengriff:BAABLgAECn8cAAIKAAgJ3CFMBACqAgAKAAgJ3CFMBACqAgAAAA==.Zerena:BAAALgAECgYJBgAAAA==.',
Zh='Zhule:BAABLgAECn8cAAIGAAgJ2B+xDAB4AgAGAAgJ2B+xDAB4AgAAAA==.',
Zy='Zyklonbarbie:BAAALgAECgcJBAAAAA==.',
['Ær']='Æres:BAAALgADCgEJAQAAAA==.',
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

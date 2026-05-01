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

local lookup = {'Priest-Discipline','Priest-Holy','Unknown-Unknown','Paladin-Retribution','Hunter-Marksmanship','Hunter-BeastMastery','Mage-Frost','DemonHunter-Devourer','Warlock-Demonology','Monk-Brewmaster','Warrior-Protection','Hunter-Survival','Druid-Restoration','Shaman-Elemental','Shaman-Restoration','DeathKnight-Unholy','DeathKnight-Frost','Druid-Balance','Rogue-Subtlety','Rogue-Assassination','Evoker-Preservation','Evoker-Devastation','Warrior-Fury','Evoker-Augmentation','Paladin-Protection','Warrior-Arms','Rogue-Outlaw','Monk-Windwalker','Paladin-Holy',}
local provider = {region='US',realm='Ysondre',name='US',type='weekly',zone=46,date='2026-05-01',data={Al='Alex:BAAALgADCgMJAwAAAA==.',
An='Angalius:BAAALgAECgQJBAAAAA==.',
Ap='Apathy:BAAALgAECgEJAQAAAA==.',
Ar='Aralid:BAAALgAECgUJCAAAAA==.Ariadné:BAABLgAECn8WAAMBAAgJCR2ZBgA/AgABAAgJCR2ZBgA/AgACAAIJTAnncwBYAAAAAA==.Artasha:BAAALgADCgIJAwAAAA==.',
Be='Bearlover:BAAALgAECgcJDwAAAA==.Beau:BAAALgAECgQJBAAAAA==.Belal:BAAALgADCgIJAgAAAA==.',
Bi='Birdflù:BAAALgADCgUJBQAAAA==.Biscuits:BAAALgADCgYJBgAAAA==.Bitron:BAAALgADCgkJDQAAAA==.',
Bo='Bomi:BAAALgAECgEJAQAAAA==.Boogiesera:BAAALgADCgQJBAABLgAECgcJEgADAAAAAA==.Bootles:BAAALgAECgcJEgAAAA==.',
Bu='Bulltastich:BAAALgADCgUJBgABLgADCgcJBwADAAAAAA==.Bullwings:BAAALgADCgkJCwAAAA==.Buttholemu:BAAALgADCgYJBgAAAA==.',
Ca='Calanthe:BAAALgAECgEJAQAAAA==.',
Ch='Charrend:BAABLgAECn8YAAIEAAYJ6QVqaADgAAAEAAYJ6QVqaADgAAAAAA==.',
Cl='Clutchmedic:BAABLgAFFH8IAAMFAAUJEQwmEAAwAQAFAAQJfw0mEAAwAQAGAAEJxwcrJgBVAAAAAA==.',
Co='Completed:BAAALgADCgUJBQAAAA==.',
Cp='Cptloveme:BAABLgAECn8eAAIHAAYJaRoFRwBZAQAHAAYJaRoFRwBZAQAAAA==.',
Cr='Crazon:BAAALgADCgcJGgAAAA==.Cropduster:BAABLgAECn8bAAIIAAgJLxnANQAgAgAIAAgJLxnANQAgAgAAAA==.Crushed:BAAALgADCgMJAwABLgAECgUJDAADAAAAAA==.',
Ct='Cthulhu:BAACLgAFFH8NAAIJAAQJcxfTEwBNAQAJAAQJcxfTEwBNAQAuAAQKfy8AAgkACAnPHrMdAKQCAAkACAnPHrMdAKQCAAAA.',
Cu='Cursedpriest:BAAALgADCgUJBQAAAA==.',
Da='Dad:BAAALgAECgEJAgAAAA==.',
De='Delnarei:BAAALgADCgEJAQAAAA==.Demise:BAAALgADCgYJCgABLgAECggJHwAHALkdAA==.Destiniemonk:BAAALgAECgYJCgAAAA==.',
Do='Dolo:BAAALgADCgIJAgAAAA==.Doloni:BAAALgAECgUJDAAAAA==.Doomd:BAEALgAECgcJEQAAAA==.Doomdtrooper:BAEALgAECgcJDgABLgAECgcJEQADAAAAAA==.Dotti:BAAALgADCgkJCQABLgAECgYJDwADAAAAAA==.Dotts:BAABLgAECn8dAAIJAAcJ5hKXKwB+AQAJAAcJ5hKXKwB+AQAAAA==.',
Dr='Drewied:BAAALgADCgEJAQAAAA==.Drfinger:BAAALgADCgQJBAABLgAECggJGwAKADolAA==.Droodorei:BAAALgADCggJHgAAAA==.',
Du='Durianz:BAAALgAECgYJCwAAAA==.',
Dw='Dwnloadedchi:BAAALgAECgcJCQAAAA==.Dwnloadedski:BAAALgAECgcJEgAAAA==.',
Eg='Eggenan:BAAALgADCgIJAgAAAA==.',
Ei='Eiskält:BAAALgAECgUJCQAAAA==.',
El='Ellay:BAAALgAECgUJCgAAAA==.',
Em='Emofumu:BAAALgADCgYJBgABLgAECgkJFAALAPEjAA==.',
En='Endrin:BAAALgAECgUJCwAAAA==.',
Ew='Eww:BAEBLgAECn8dAAIMAAgJnBE3CQDPAQAMAAgJnBE3CQDPAQAAAA==.',
Ez='Ezzak:BAAALgADCgQJBAAAAA==.',
Fe='Felldeeds:BAABLgAECn8XAAINAAcJKSXZCAB+AgANAAcJKSXZCAB+AgAAAA==.Fellshock:BAAALgADCgUJBQABLgAECgcJFwANACklAA==.Felthazzar:BAAALgAECgYJBgAAAA==.Fent:BAACLgAFFH8IAAIOAAMJOg2fEgDoAAAOAAMJOg2fEgDoAAAuAAQKfywAAw4ACQmHHGIIABoCAA4ABwlpIGIIABoCAA8ACQk+F/MgABkCAAAA.',
Fi='Fingerblastn:BAAALgADCgcJBwABLgAECggJGwAKADolAA==.Fingerr:BAABLgAECn8bAAIKAAgJOiU/AQD4AgAKAAgJOiU/AQD4AgAAAA==.Finneagan:BAAALgADCgEJAQAAAA==.',
Fl='Flokki:BAAALgAECgUJBQAAAA==.',
Fo='Foxxowo:BAAALgAECgQJBwAAAA==.',
Fr='Froztbane:BAEALgAECgcJDwABLgAECgkJLgAIAGsgAA==.Froztbanshee:BAEBLgAECn8uAAIIAAkJayCrDAAbAwAIAAkJayCrDAAbAwAAAA==.',
Gh='Ghats:BAAALgAECgEJAQAAAA==.',
Gl='Glass:BAAALgAECgUJCwAAAA==.',
Go='Gogo:BAAALgAECgUJCAABLgAECgYJBgADAAAAAA==.',
Gr='Grimzyn:BAACLgAFFH8FAAIQAAMJHRLzPgDPAAAQAAMJHRLzPgDPAAAuAAQKfxwAAhAACAljHL02AFwCABAACAljHL02AFwCAAAA.Grudge:BAABLgAECn8eAAMRAAgJbg++BQDVAQARAAgJpA6+BQDVAQAQAAgJPQr/NgBeAQAAAA==.',
Ha='Haircules:BAAALgAECgQJBAAAAA==.Harrowhark:BAABLgAECn8ZAAIQAAgJChvuIgC3AQAQAAgJChvuIgC3AQAAAA==.',
He='Herambae:BAAALgADCgYJBgAAAA==.Herculesátan:BAAALgADCgYJCAAAAA==.',
Hy='Hyacinth:BAABLgAECn8WAAISAAgJKgwdEwBwAQASAAgJKgwdEwBwAQAAAA==.Hyria:BAAALgADCgkJDwABLgAECgcJEgADAAAAAA==.Hyun:BAAALgADCgYJBgAAAA==.',
Ia='Iamfinn:BAAALgAECgEJAQAAAA==.Iamomegafox:BAABLgAECn8iAAMTAAgJJBfxBwDxAQATAAgJAxXxBwDxAQAUAAYJ8RfkCwBoAQAAAA==.',
Ig='Ignax:BAACLgAFFH8HAAMVAAMJ7QRUEwCCAAAVAAMJ7QRUEwCCAAAWAAEJWgUKCwBNAAAuAAQKfyEAAxUACAkDFUkUAAECABUACAkDFUkUAAECABYABglWCFwlAPoAAAAA.',
Im='Imomeganisha:BAAALgAECgQJBwABLgAECggJIgATACQXAA==.Imsparticus:BAABLgAECn8VAAMXAAYJxwhdJgAMAQAXAAYJxwhdJgAMAQALAAQJcAHSOwBtAAAAAA==.',
Io='Ionias:BAAALgAECggJDgAAAA==.',
Ja='Jackblack:BAAALgAECgIJBAABLgAECggJGwAIAC8ZAA==.Jaquelius:BAAALgAECgUJDgAAAA==.',
Jo='Johadan:BAAALgAECgYJEAAAAA==.',
Ka='Kaelx:BAAALgAECgEJAwAAAA==.Kafizz:BAABLgAECn8eAAIJAAgJKRe7JQCYAQAJAAgJKRe7JQCYAQAAAA==.Kagnara:BAAALgADCgUJBQAAAA==.',
Ke='Keolmont:BAAALgADCgEJAQAAAA==.',
Ki='Kinla:BAAALgAECgQJBAAAAA==.Kireag:BAAALgADCgIJAgAAAA==.',
Ko='Kooppa:BAAALgADCgQJBAAAAA==.',
Ku='Kuromigirl:BAAALgAECgUJCAAAAA==.',
La='Labchimpette:BAAALgAECgYJDgAAAA==.Lagerthä:BAAALgADCgYJBgABLgAECgcJEgADAAAAAA==.',
Li='Link:BAAALgADCgcJBwAAAA==.Lione:BAAALgAECgcJEwAAAA==.Lith:BAACLgAFFH8HAAIVAAMJgRTeDQD9AAAVAAMJgRTeDQD9AAAuAAQKfycAAxUACAmPGb4DAE8CABUACAmPGb4DAE8CABgACAlgELsdANcBAAAA.Litterbocks:BAAALgAECgMJBAAAAA==.Littlepriest:BAAALgADCgEJAQAAAA==.',
Ly='Lyzandra:BAAALgADCgYJCgAAAA==.',
['Lì']='Lìllyanna:BAABLgAECn8dAAIZAAgJPBB/CQBxAQAZAAgJPBB/CQBxAQAAAA==.',
Ma='Mailbox:BAAALgAECgEJAQABLgAECggJHgAVADIeAA==.Malock:BAAALgADCgkJCQAAAA==.Mango:BAAALgADCgcJBAAAAA==.Matcha:BAAALgAECggJDQAAAA==.Mauler:BAAALgAECgQJCAAAAA==.',
Me='Melinoë:BAAALgADCgUJBQAAAA==.Meowhunter:BAAALgAECgUJCQAAAA==.',
Mi='Miaraa:BAAALgAECgcJDwAAAA==.Minervå:BAAALgADCgMJAwAAAA==.',
Mo='Mogdor:BAAALgAECgcJEAAAAA==.Moonpeach:BAAALgAECgUJEAAAAA==.Motex:BAABLgAECn8eAAITAAgJ8QKVGwDxAAATAAgJ8QKVGwDxAAAAAA==.',
Na='Naturebug:BAAALgAECgYJCgAAAA==.',
Ne='Ned:BAECLgAFFH8HAAIXAAMJ0CD2DQAnAQAXAAMJ0CD2DQAnAQAuAAQKfzkAAxcACAmiJVoDAHkDABcACAmiJVoDAHkDABoABAllJIkPAKMBAAAA.Netre:BAAALgAECgUJBgAAAA==.',
Ni='Ninax:BAAALgAECgYJBgAAAA==.',
Ny='Nylian:BAAALgAECgMJBAAAAA==.',
Ob='Obamasmama:BAAALgAECgYJBgAAAA==.',
Ol='Oldmantom:BAAALgADCgYJBgAAAA==.',
Or='Ormgorg:BAAALgAECgcJDwAAAA==.Orpheus:BAABLgAECn8jAAMPAAgJ6x9PBwB3AgAPAAgJ6x9PBwB3AgAOAAMJNArSNgCXAAAAAA==.',
Oz='Oza:BAAALgAECgMJBgAAAA==.',
Pa='Pandamoniium:BAAALgAECgcJCwAAAA==.Pandamonk:BAACLgAFFH8IAAIKAAMJciZLCABWAQAKAAMJciZLCABWAQAuAAQKfysAAgoACQlxJIgAAD8DAAoACQlxJIgAAD8DAAAA.',
Pe='Percy:BAEALgAECgYJDgAAAA==.',
Pr='Preservation:BAAALgAECgMJAwAAAA==.',
Ra='Raastamon:BAAALgADCgEJAQAAAA==.Raekitty:BAABLgAECn8XAAINAAgJgR6VFACRAgANAAgJgR6VFACRAgAAAA==.',
Re='Redrover:BAAALgADCggJDgAAAA==.Reia:BAAALgADCgcJBwAAAA==.',
Rh='Rhara:BAAALgADCgYJDgAAAA==.Rhoem:BAABLgAECn8eAAIRAAgJqR+wBQDYAQARAAgJqR+wBQDYAQAAAA==.',
Ro='Roger:BAAALgAECgUJDQAAAA==.',
Ru='Rumor:BAACLgAFFH8UAAMUAAYJNSI3AAD2AQAUAAYJNSI3AAD2AQATAAQJsRlwBwBtAQAuAAQKfzEAAxMACAnJJpUKAOkCABMACAnTJJUKAOkCABQACAmJJoIKANsAAAAA.',
Se='Secretgrace:BAAALgADCgQJBAABLgAECgcJDwADAAAAAA==.Senortickle:BAAALgAECgYJCwAAAA==.',
Sh='Shadowmoone:BAAALgAECgYJDwAAAA==.Shaki:BAAALgAECgQJBAAAAA==.Shalendris:BAAALgAECgEJAQAAAA==.Shalestrasz:BAABLgAECn8XAAQWAAgJNAg0IQAjAQAWAAgJFgU0IQAjAQAYAAMJFApJNACKAAAVAAIJVQFIRQBGAAAAAA==.Shibal:BAAALgADCggJCAAAAA==.Shochu:BAAALgAECgcJDwAAAA==.',
So='Soju:BAAALgAECgUJBQAAAA==.Somnera:BAAALgAECgEJAQABLgAECgcJDwADAAAAAA==.Soyboymalfoy:BAAALgAECgcJDgAAAA==.',
Sp='Sp:BAACLgAFFH8GAAICAAIJOg/IDQCPAAACAAIJOg/IDQCPAAAuAAQKfyQAAgIACAnbIQUOAHsCAAIACAnbIQUOAHsCAAAA.',
St='Sterility:BAAALgAECgQJCwAAAA==.',
Sw='Switchfoot:BAABLgAECn8cAAMbAAgJKBzuAgA4AgAbAAgJJxzuAgA4AgAUAAEJJxPWGwBJAAAAAA==.',
['Sï']='Sïeghart:BAAALgADCgUJBQAAAA==.',
Te='Tenzin:BAAALgADCgQJBAABLgAFFAQJDQAJAHMXAA==.Tex:BAAALgADCgcJDgAAAA==.',
Ti='Timerunner:BAAALgADCgYJBgAAAA==.',
To='Totingtotems:BAAALgADCgcJDQAAAA==.Touchofdeath:BAABLgAECn8WAAIcAAcJ3AtTIgDXAAAcAAcJ3AtTIgDXAAAAAA==.',
Ug='Ughnga:BAAALgAECgMJAwABLgAECgcJHQAJAOYSAA==.',
Va='Vandli:BAAALgAECgMJBAAAAA==.',
Ve='Velzard:BAAALgAECgUJDAAAAA==.Verti:BAAALgAECgYJCwAAAA==.',
Vi='Visona:BAAALgADCgMJAwAAAA==.',
Vo='Voíshara:BAAALgADCgUJCwAAAA==.',
['Vö']='Vöre:BAAALgAECgUJBgAAAA==.',
Wi='Wither:BAACLgAFFH8FAAIQAAQJKxFpFQBOAQAQAAQJKxFpFQBOAQAuAAQKfxcAAhAACAldIp41AGACABAACAldIp41AGACAAEuAAUUBgkUABQANSIA.',
Wy='Wyspur:BAAALgADCgYJCgAAAA==.',
Yo='Yofoxxo:BAACLgAFFH8RAAIdAAYJehvTAwCoAQAdAAYJehvTAwCoAQAuAAQKfyQABB0ACAnfIzsEACoDAB0ACAnfIzsEACoDAAQABQkNDpm0ABsBABkAAgmLCLk9AEcAAAAA.',
Yu='Yulon:BAAALgAECgQJBgABLgAFFAIJBgACADoPAA==.',
Za='Zaraerivia:BAAALgAECgUJCQAAAA==.Zarlon:BAAALgAECgIJAwABLgAECgYJGQAHAPQcAA==.',
Ze='Zengriff:BAABLgAECn8UAAIKAAgJ9B96BABtAgAKAAgJ9B96BABtAgAAAA==.Zerena:BAAALgAECgYJBgAAAA==.',
Zh='Zhule:BAABLgAECn8UAAIGAAgJSx21CgBTAgAGAAgJSx21CgBTAgAAAA==.',
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

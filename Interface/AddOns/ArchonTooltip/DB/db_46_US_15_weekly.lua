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

local lookup = {'Warlock-Destruction','Warlock-Demonology','Mage-Frost','Paladin-Retribution','DemonHunter-Vengeance','Unknown-Unknown','Paladin-Holy','Shaman-Restoration','Hunter-Marksmanship','Hunter-Survival','Monk-Mistweaver','Monk-Windwalker','Hunter-BeastMastery','DeathKnight-Unholy','Warrior-Fury','Evoker-Devastation','Priest-Holy','DemonHunter-Devourer','Rogue-Subtlety','Warrior-Arms','Druid-Restoration','DeathKnight-Blood','DeathKnight-Frost','Monk-Brewmaster','Paladin-Protection','Priest-Discipline','Shaman-Elemental','Evoker-Augmentation','Evoker-Preservation','Warrior-Protection','Rogue-Outlaw','Druid-Feral','Warlock-Affliction','Druid-Guardian','Shaman-Enhancement','DemonHunter-Havoc','Priest-Shadow',}
local provider = {region='US',realm='Anvilmar',name='US',type='weekly',zone=46,date='2026-05-08',data={Aa='Aaril:BAAALgAECgMJBAAAAQ==.',
Ad='Adel:BAAALgADCgUJDAAAAA==.',
Ae='Aelitha:BAABLgAECn8ZAAMBAAYJ/QV0OQDOAAACAAYJsAS+ewDQAAABAAYJtgR0OQDOAAAAAA==.',
Ak='Akaishi:BAAALgADCgIJAgAAAA==.Akali:BAAALgAFFAEJAQAAAA==.Akina:BAAALgADCgMJAQABLgAECggJGQADAFEMAA==.',
Al='Alathiana:BAAALgADCgUJCAAAAA==.Alcweaver:BAAALgAECgYJDgAAAA==.Alecto:BAAALgAECgMJAwAAAA==.Alindia:BAAALgAECgQJCgABLgAECggJGQADAFEMAA==.Alirrayia:BAAALgAECgQJBAAAAA==.Alirrayiia:BAACLgAFFH8FAAIEAAMJMwFBPwCtAAAEAAMJMwFBPwCtAAAuAAQKfyAAAgQACQlUDyxNAPsBAAQACQlUDyxNAPsBAAAA.Alkri:BAAALgADCgMJAwAAAA==.Allari:BAAALgAECgYJEwAAAA==.Allikazam:BAAALgADCgYJCQAAAA==.Allystar:BAAALgAECgMJBAAAAA==.Altheia:BAAALgAECgQJBAAAAA==.Alvidor:BAABLgAECn8jAAIDAAgJEgNWgQAPAQADAAgJEgNWgQAPAQAAAA==.',
Am='Ameria:BAAALgADCgUJBQAAAA==.',
An='Anastos:BAAALgAECgUJBQAAAA==.Andydufresne:BAAALgAECgQJBgABLgAECggJMAAFAKYlAA==.Angryqueer:BAAALgADCgEJAQAAAA==.',
Ao='Aowl:BAAALgAECgcJCwAAAA==.',
Ap='Apocketheory:BAAALgADCgIJAgAAAA==.Apolloerosb:BAAALgADCggJDgABLgAECgYJEAAGAAAAAA==.Apollossham:BAAALgAECgYJEAAAAA==.',
Ar='Arkanaun:BAABLgAECn8aAAMEAAYJRBdtcwCUAQAEAAYJRBdtcwCUAQAHAAUJvhQ9LQAoAQAAAA==.',
As='Ashes:BAAALgAECgcJAQAAAA==.Ashrán:BAAALgAECgYJCQAAAA==.Ashyluna:BAAALgAECgQJBAAAAA==.Astianna:BAAALgADCgMJAwAAAA==.',
Au='Aule:BAAALgAECgEJAQAAAA==.Aurinia:BAAALgADCgQJAgAAAA==.Auroradinlee:BAAALgAECgkJBgAAAA==.Aurore:BAAALgADCgQJBgAAAA==.',
Av='Avradea:BAAALgADCgEJAQABLgAECggJGQADAFEMAA==.',
Az='Azareth:BAAALgADCggJCAAAAA==.',
Ba='Baconatorr:BAAALgAECgMJAwAAAA==.Bagelbags:BAAALgADCgEJAQAAAA==.Bahler:BAAALgADCgUJBQABLgAECgMJAwAGAAAAAA==.Baji:BAABLgAECn8pAAIIAAgJcSPZAwALAwAIAAgJcSPZAwALAwAAAA==.Baklan:BAAALgAECgMJAwAAAA==.Barefaall:BAACLgAFFH8HAAIJAAQJzhCSEACsAAAJAAQJzhCSEACsAAAuAAQKfzEAAgkACQnAHzoDAC0CAAkACQnAHzoDAC0CAAAA.Barefall:BAAALgAFFAEJAQABLgAFFAQJBwAJAM4QAA==.Barefalls:BAABLgAECn8jAAMKAAgJlhxtBgBKAgAKAAgJlhxtBgBKAgAJAAEJjAGclgAiAAABLgAFFAQJBwAJAM4QAA==.Barelywolf:BAABLgAECn8WAAMLAAYJkRrHFAC0AQALAAYJkRrHFAC0AQAMAAIJzgjESQBbAAABLgAFFAIJAwAGAAAAAA==.Bashira:BAABLgAECn8XAAINAAgJFAosNQB4AQANAAgJFAosNQB4AQAAAA==.Bast:BAABLgAECn8aAAIOAAcJvBJbRABvAQAOAAcJvBJbRABvAQAAAA==.',
Be='Bearophe:BAAALgAECgEJAgAAAA==.Beerfist:BAAALgAECgEJAQAAAA==.Bellock:BAAALgAECgMJAwAAAA==.Benisbagina:BAAALgADCggJCQAAAA==.Bergonator:BAABLgAECn8gAAIPAAYJchDYKwAkAQAPAAYJchDYKwAkAQAAAA==.Berrodiah:BAAALgAECgUJBwABLgAECggJFgAQALUYAA==.Bettyswalls:BAAALgAECgMJAwAAAA==.Beyarago:BAAALgAECgUJCQAAAA==.',
Bh='Bheiroth:BAABLgAECn8oAAIRAAgJ1CLqAwDiAgARAAgJ1CLqAwDiAgAAAA==.',
Bi='Birds:BAAALgAECgIJAgAAAA==.',
Bl='Bladeygaga:BAABLgAECn8hAAISAAgJpBujEgAoAgASAAgJpBujEgAoAgAAAA==.Blasé:BAAALgAECgcJAQAAAA==.Blazingblood:BAAALgADCgUJAQAAAA==.Bloodknight:BAAALgADCgYJCQAAAA==.Bluett:BAAALgADCgkJGQAAAA==.Bláckøut:BAAALgADCgYJDAAAAA==.',
Bo='Bodhi:BAABLgAECn8WAAITAAcJNhAKJwDAAQATAAcJNhAKJwDAAQAAAA==.Bogertus:BAACLgAFFH8IAAIPAAMJIST0DwAxAQAPAAMJIST0DwAxAQAuAAQKfy8AAw8ACAknJqcBABcDAA8ACAknJqcBABcDABQAAgn1HHApAKUAAAAA.Boomertunes:BAABLgAECn8WAAMCAAYJuxfHPgBuAQACAAYJuxfHPgBuAQABAAIJGwEjNQAAAAAAAA==.',
Br='Brein:BAABLgAECn8jAAIVAAgJbCVXAgBhAwAVAAgJbCVXAgBhAwAAAA==.Brewmaster:BAAALgAECgIJAwAAAA==.Brewwmaster:BAABLgAECn8gAAQWAAgJ4Rh/DACsAQAWAAgJ0RR/DACsAQAOAAYJtBfOfACKAQAXAAEJ+he2FgA2AAAAAA==.Brickred:BAAALgADCggJDgAAAA==.Brynodd:BAAALgADCgkJGwAAAA==.',
Bu='Bubblybetty:BAAALgAECgEJAQAAAA==.Bucketeer:BAABLgAECn8fAAIDAAgJVxwMGgBOAgADAAgJVxwMGgBOAgAAAA==.Buffs:BAAALgADCgEJAQAAAA==.Bursona:BAAALgAECgEJAQAAAA==.Butterfree:BAAALgAECgUJDAAAAA==.',
Ca='Cards:BAAALgAECgYJCQAAAA==.Carkrash:BAAALgADCgkJFwAAAA==.Casterkang:BAAALgAECgUJCQAAAA==.Catshunter:BAAALgAECgUJCQAAAA==.',
Ce='Celaa:BAABLgAECn8ZAAIDAAgJUQyERgCTAQADAAgJUQyERgCTAQAAAA==.',
Ch='Chanka:BAAALgAECgQJBAAAAA==.Chantillary:BAAALgADCgkJGwAAAA==.Chargerkang:BAAALgADCgYJBgAAAA==.Chchanges:BAAALgAECgEJAQAAAA==.Cheesy:BAAALgAECgcJEwAAAA==.Chicken:BAAALgAECgYJDQAAAA==.Chonk:BAAALgADCgEJAQAAAA==.Chopzullee:BAAALgAECgYJDgAAAA==.',
Ci='Cirya:BAAALgAECgUJCAAAAA==.',
Cl='Cleric:BAAALgADCgUJBQAAAA==.Clortho:BAAALgADCggJGAAAAA==.',
Co='Colljack:BAACLgAFFH8RAAIHAAUJ7x4WCQCLAQAHAAUJ7x4WCQCLAQAuAAQKfxoAAwcACQl3Ip4JANgCAAcACAktIp4JANgCAAQABQlOEtO5ABIBAAAA.',
Cr='Crocbait:BAAALgAECgcJEAAAAA==.Cryptoe:BAABLgAECn8WAAIDAAcJxA1sWwBdAQADAAcJxA1sWwBdAQAAAA==.',
Cu='Cudlsac:BAAALgAECgQJBQAAAA==.',
Da='Daedelus:BAAALgAECgcJEAAAAA==.Daglon:BAAALgAECggJDAAAAA==.Dagz:BAAALgAECgQJBAAAAA==.Dakina:BAAALgADCgYJBgAAAA==.Daraedra:BAAALgADCgYJEgAAAA==.Darkenvoid:BAAALgADCgkJDQAAAA==.',
De='Deathslight:BAAALgAECgQJBwAAAA==.Deeznutticus:BAACLgAFFH8TAAIPAAUJ6Rb6DABAAQAPAAUJ6Rb6DABAAQAuAAQKfx8AAw8ABwnCIkYYAIkCAA8ABwnCIkYYAIkCABQAAQkSFho8AEEAAAAA.Defnotisis:BAABLgAECn8UAAMMAAgJJBBrKQDnAAAMAAgJmQtrKQDnAAAYAAYJ+g9bQwCJAAABLgAFFAEJAQAGAAAAAA==.Demonspud:BAABLgAECn8WAAISAAcJuA58SQAcAQASAAcJuA58SQAcAQAAAA==.Dersan:BAAALgAECgYJDAAAAA==.Destriant:BAABLgAECn8qAAIZAAgJqxklCQBCAgAZAAgJqxklCQBCAgAAAA==.Devilschant:BAAALgAECgYJCgAAAA==.Devilshadow:BAAALgAECgUJBwABLgAECgYJCgAGAAAAAA==.Dewburt:BAAALgADCgUJBQAAAA==.Deylia:BAAALgADCgYJBgABLgAFFAQJCgAaADgSAA==.',
Di='Dilithia:BAAALgAECgMJBAAAAA==.Dillion:BAAALgAECgYJCAAAAA==.Dinonuggies:BAAALgADCgcJBwAAAA==.Dionin:BAAALgADCgYJCQAAAA==.Dira:BAAALgAECgYJEAABLgAFFAQJDQAbAAEcAA==.Dirkbanne:BAAALgADCgYJBgAAAA==.',
Do='Dodoubleg:BAAALgAECgYJEAAAAA==.Dominique:BAAALgADCgYJBgAAAA==.Donzilch:BAEALgAECgQJBAAAAA==.Dooburt:BAAALgADCgYJBgAAAA==.',
Dr='Dracaric:BAABLgAECn8eAAIcAAcJzRhGEADRAQAcAAcJzRhGEADRAQAAAA==.Dragondznut:BAAALgAECgQJBQAAAA==.Drfrostie:BAAALgAECgcJCQAAAA==.Drgunner:BAAALgAECgcJDwAAAA==.Driatin:BAAALgAECgIJBAABLgAECgUJDAAGAAAAAA==.Drkladykikyo:BAAALgAECgYJDgAAAA==.Druroo:BAAALgAECgEJAQABLgAECggJHQAaADkfAA==.Druterr:BAAALgAECgIJAgAAAA==.',
Du='Dumb:BAACLgAFFH8PAAIdAAUJLAyOBgCJAQAdAAUJLAyOBgCJAQAuAAQKfyMAAh0ACAnoG2oLAH4CAB0ACAnoG2oLAH4CAAAA.Durø:BAABLgAECn8WAAISAAgJriLZDAAZAwASAAgJriLZDAAZAwAAAA==.',
Dy='Dyanisian:BAAALgADCgYJCAAAAA==.',
['Dè']='Dègenerate:BAABLgAECn8pAAIeAAgJ9SBTAwCXAgAeAAgJ9SBTAwCXAgAAAA==.',
Ed='Edagerran:BAAALgADCgkJCQAAAA==.',
Ei='Eilae:BAAALgAECgQJCgAAAA==.Eirhakan:BAAALgAECgQJCAAAAA==.',
El='Elrethyl:BAABLgAECn8VAAIEAAYJdhsaPwCIAQAEAAYJdhsaPwCIAQAAAA==.Elvanus:BAAALgADCgYJBgAAAA==.Elêktra:BAABLgAECn8lAAIbAAgJFg+cHABpAQAbAAgJFg+cHABpAQAAAA==.',
Ep='Epicnym:BAAALgADCgcJBwAAAA==.Epicsmoke:BAABLgAECn8sAAIPAAgJOCFIBQCjAgAPAAgJOCFIBQCjAgAAAA==.Epidemius:BAAALgAECgkJCgAAAA==.',
Er='Erevan:BAABLgAECn8eAAMTAAgJbw4uDwCxAQATAAgJbw4uDwCxAQAfAAEJpwD+DwAcAAAAAA==.Eroica:BAAALgADCgYJBwAAAA==.',
Es='Esdeath:BAABLgAECn8kAAMOAAgJZBFzTQBTAQAOAAcJ1BNzTQBTAQAWAAYJWgZUIgCyAAAAAA==.',
Et='Etharia:BAAALgADCgUJAwAAAA==.',
Ev='Evilsmeghead:BAAALgADCgEJAQAAAA==.',
Ex='Extenze:BAABLgAECn8iAAISAAgJ/hvbEAA6AgASAAgJ/hvbEAA6AgAAAA==.',
Ez='Ezykiah:BAAALgADCgcJEgAAAA==.',
Fa='Falconponch:BAAALgADCgEJAQAAAA==.',
Fe='Felgibson:BAAALgAECgQJBQAAAA==.Felkang:BAAALgADCgkJCQAAAA==.Ferryman:BAAALgAECgQJBQAAAA==.',
Fl='Flingor:BAAALgAECgYJEAAAAA==.Flokha:BAAALgADCgEJAQAAAA==.',
Fo='Forphium:BAACLgAFFH8VAAITAAUJPxKjBACkAQATAAUJPxKjBACkAQAuAAQKfxwAAhMACQlTH3oNAMQCABMACQlTH3oNAMQCAAAA.',
Fr='Fredolf:BAAALgADCgkJDgAAAA==.Freydís:BAAALgAECgUJCwAAAA==.Friarkuck:BAAALgADCggJCAAAAA==.Friedbones:BAAALgADCgkJGQAAAA==.Frostlilliy:BAAALgADCgYJBgAAAA==.',
Ga='Gahlina:BAAALgAECgMJCAAAAA==.Galdorian:BAAALgADCgMJAwABLgAECggJFwANABQKAA==.Galynda:BAAALgADCgQJBQAAAA==.',
Ge='Genjimain:BAABLgAECn8iAAMVAAgJGhqQHgBKAgAVAAgJGhqQHgBKAgAgAAMJ9wydGQCeAAAAAA==.Genjí:BAAALgAECgEJAwAAAA==.Geris:BAAALgAECgQJBQAAAA==.Gertruide:BAAALgADCgUJBQAAAA==.',
Gh='Ghendala:BAAALgADCggJEwAAAA==.',
Gi='Gillesmon:BAAALgAECgYJCAABLgAECggJDAAGAAAAAA==.Gincainn:BAAALgAECgEJAgAAAA==.Gird:BAABLgAECn8kAAIHAAcJvAv0JgBTAQAHAAcJvAv0JgBTAQAAAA==.',
Gl='Glaiveyjones:BAAALgAECgEJAQAAAA==.',
Gn='Gnymesis:BAAALgADCgcJBwAAAA==.',
Go='Goatmonger:BAAALgAECgYJBgAAAA==.Goinpostal:BAAALgAECgIJAgAAAA==.Goldblade:BAAALgAECgkJCwAAAA==.Goodvsevil:BAAALgAECgQJBAAAAA==.Gordek:BAABLgAECn8UAAMEAAcJNhoKNwCiAQAEAAcJNhoKNwCiAQAHAAIJfxBSTABxAAAAAA==.Gothitelle:BAAALgAECgEJAQAAAA==.Goöse:BAACLgAFFH8XAAIOAAUJ7iHaAwDEAQAOAAUJ7iHaAwDEAQAuAAQKfyAAAg4ACAmDJuwGAGsDAA4ACAmDJuwGAGsDAAAA.',
Gr='Grantaron:BAABLgAECn8qAAIEAAgJmB89GADXAgAEAAgJmB89GADXAgAAAA==.Gravarii:BAAALgADCgcJEwAAAA==.Grimskul:BAABLgAECn8aAAMOAAgJTRWuMgCuAQAOAAgJBROuMgCuAQAXAAYJDxSUBwCBAQAAAA==.Grntitan:BAAALgAECgQJBAAAAA==.Gruid:BAAALgADCgcJDwAAAA==.',
Gu='Guinessbrew:BAAALgAECgEJAQAAAA==.',
Gw='Gwoohoori:BAAALgAECgQJAwAAAA==.',
Gy='Gyra:BAAALgAECgYJDwAAAA==.',
Ha='Halukari:BAAALgAECgYJDwABLgAFFAQJCgAaADgSAA==.Harfnan:BAAALgAECgIJAgAAAA==.Harrin:BAABLgAECn8VAAIDAAcJkA4quABwAQADAAcJkA4quABwAQAAAA==.',
He='Healingwater:BAAALgAECgIJAwAAAA==.Herracles:BAAALgADCgYJCQAAAA==.Hezrel:BAAALgAECgYJCgAAAA==.',
Hi='Hierodule:BAAALgAECgEJAQAAAA==.Hiimriven:BAAALgAECgIJAgABLgAECgYJFgATAFkhAA==.Hinal:BAAALgAECggJEQAAAA==.',
Ho='Hojo:BAAALgADCgUJCAAAAA==.Holyenabler:BAAALgAFFAIJAgAAAA==.Hootiehoo:BAAALgADCgMJAwAAAA==.',
Hu='Huflunggoo:BAAALgADCgkJDQAAAA==.Huflungpoop:BAABLgAECn8sAAIMAAgJMxmbCgAPAgAMAAgJMxmbCgAPAgAAAA==.Hunterborn:BAAALgAFFAIJAgAAAA==.',
['Hè']='Hèalz:BAAALgADCgcJCQABLgAECggJGwAPADoZAA==.',
Ic='Ickixia:BAAALgADCgQJBAAAAA==.',
Il='Ilkaressa:BAAALgADCgQJBAAAAA==.Illyríá:BAEALgAFFAIJAgABLgAECggJHgABAJcYAA==.Ilun:BAAALgAECgEJAQAAAA==.',
Im='Imcruel:BAACLgAFFH8QAAIDAAUJCx6kFwBrAQADAAUJCx6kFwBrAQAuAAQKfx8AAgMACAl7Jc4eADECAAMACAl7Jc4eADECAAAA.',
In='Ink:BAACLgAFFH8FAAIDAAMJlw+2SwDxAAADAAMJlw+2SwDxAAAuAAQKfyMAAgMABwmxIKAlAA4CAAMABwmxIKAlAA4CAAAA.',
Is='Istaria:BAAALgADCgkJGQAAAA==.Isujr:BAABLgAECn8ZAAIOAAcJ8hL/cACmAQAOAAcJ8hL/cACmAQAAAA==.',
Ja='Jacaerys:BAAALgADCgYJBgAAAA==.Jackiegan:BAABLgAECn8YAAMYAAgJTBzaCgAVAgAYAAcJRB/aCgAVAgALAAEJIweiYwAfAAAAAA==.Jackson:BAAALgADCgkJGwAAAA==.Jagerdemon:BAAALgAECgcJBwAAAA==.',
Je='Jerce:BAAALgADCgUJBQAAAA==.',
Jh='Jhala:BAAALgADCgcJCAAAAA==.',
Jo='Joshcalc:BAAALgAECgEJAQAAAA==.Joskel:BAABLgAECn8hAAMCAAYJTQ8oVQAsAQACAAYJTQ8oVQAsAQAhAAYJMQToFgDIAAAAAA==.',
Ju='Juacqer:BAAALgADCgkJFQAAAA==.',
Ka='Kaant:BAABLgAECn8jAAMbAAgJthoqEwC/AQAbAAcJ2hkqEwC/AQAIAAYJwBNeNwAsAQAAAA==.Kaeni:BAAALgADCgMJAwAAAA==.Kaidevyn:BAABLgAECn8cAAMXAAcJlxD5BwByAQAXAAcJlxD5BwByAQAOAAQJWgqGmgCsAAAAAA==.Kaiste:BAAALgADCgEJAQAAAA==.Kaleine:BAAALgAECgIJAgAAAA==.Kardren:BAAALgAECgUJBgAAAA==.',
Ke='Keiko:BAAALgAECgcJDAAAAA==.Keiran:BAABLgAECn8oAAMNAAgJ8iAPCwCKAgAJAAgJpRzFEgCgAgANAAgJ1iAPCwCKAgAAAA==.Kelazurin:BAAALgADCgEJAQAAAA==.Kellistair:BAAALgADCgYJBgAAAA==.Keläo:BAAALgADCgUJCQAAAA==.Keyadish:BAAALgADCgYJBwAAAA==.Keys:BAABLgAECn8lAAITAAgJEx7/BwAoAgATAAgJEx7/BwAoAgAAAA==.',
Kh='Khalnerys:BAABLgAECn8dAAMcAAgJTwZEJQAgAQAcAAgJTwZEJQAgAQAQAAQJZwXsDwCFAAAAAA==.Khoulock:BAACLgAFFH8OAAICAAUJIBe4JwAiAQACAAUJIBe4JwAiAQAuAAQKfy8ABAIACQlcIJILAJUCAAIACQlNIJILAJUCACEABQliIp4EAJIBAAEAAwl9ENU+ALkAAAAA.',
Ki='Kimmi:BAAALgAECggJCAAAAA==.Kimmispally:BAAALgAECgIJAwAAAA==.Kiro:BAAALgADCgQJBQAAAA==.',
Kn='Knowimsayin:BAAALgAECgEJAQAAAA==.',
Ko='Kotateal:BAAALgAECgYJCwAAAA==.',
Kr='Krux:BAAALgAECgEJAQAAAA==.',
Kt='Kthxbye:BAAALgAECgUJBwABLgAECgcJBwAGAAAAAA==.',
Ku='Kumcookies:BAAALgADCgEJAQAAAA==.Kungfuprissy:BAAALgAECgMJBAAAAA==.Kuraishin:BAACLgAFFH8KAAIgAAIJLBPvBgCwAAAgAAIJLBPvBgCwAAAuAAQKf0wAAyAABwmrH1wEACgCACAABwmrH1wEACgCACIAAwmdHBUaAN4AAAAA.Kuroakuma:BAAALgAECgYJEAAAAA==.Kuvara:BAAALgADCgkJCgAAAA==.',
Kv='Kvnpro:BAAALgADCgEJAQAAAA==.',
Kw='Kwandashadow:BAAALgAECgUJDQAAAA==.',
Ky='Kylemonk:BAAALgADCgEJAQAAAA==.',
['Ké']='Kéres:BAAALgADCgkJEAAAAA==.',
La='Lagspike:BAABLgAECn8dAAIDAAgJphVgUwBxAQADAAgJphVgUwBxAQAAAA==.Latheal:BAAALgADCggJEwAAAA==.Lavi:BAABLgAECn8dAAIEAAgJDA6PQACEAQAEAAgJDA6PQACEAQAAAA==.',
Lb='Lbk:BAAALgADCgIJAgAAAA==.',
Le='Lejeune:BAAALgADCgcJFgAAAA==.Lengex:BAAALgAECgYJCQAAAA==.Lero:BAABLgAECn8iAAIYAAkJryGUAQAUAwAYAAkJryGUAQAUAwAAAA==.Lerwindion:BAABLgAECn8dAAIaAAgJOR+RCQCiAgAaAAgJOR+RCQCiAgAAAA==.Lescaryn:BAAALgADCgIJAgAAAA==.Lexoh:BAAALgAECgYJEgAAAA==.',
Li='Lilani:BAAALgADCgQJBAAAAA==.Lindir:BAACLgAFFH8IAAIKAAMJlBvBDAASAQAKAAMJlBvBDAASAQAuAAQKfycAAgoACAk5JKQBAD4DAAoACAk5JKQBAD4DAAAA.Lionelle:BAAALgAECgYJDgAAAA==.Liquor:BAACLgAFFH8JAAISAAQJ4BMvHQA2AQASAAQJ4BMvHQA2AQAuAAQKfzQAAxIACQl9IZsDAAMDABIACQl9IZsDAAMDAAUAAwnPFOMhAHQAAAAA.Liquorish:BAAALgADCgEJAQABLgAFFAQJCQASAOATAA==.Lirathiel:BAAALgAECgMJCAAAAA==.Litasfk:BAAALgAECgIJAgAAAA==.Liuni:BAABLgAECn8eAAIYAAcJzxXKGwBVAQAYAAcJzxXKGwBVAQAAAA==.Liyin:BAAALgAECgQJCQABLgAECggJGQADAFEMAA==.',
Lo='Lobopeste:BAABLgAECn8jAAIWAAgJdQaqGgDxAAAWAAgJdQaqGgDxAAAAAA==.Locknutz:BAAALgADCgMJAwAAAA==.Loracy:BAAALgADCgcJBwAAAA==.Lorelynn:BAABLgAECn8eAAICAAcJdQ0kRwBTAQACAAcJdQ0kRwBTAQAAAA==.',
Lu='Luci:BAAALgAECggJEgABLgAFFAEJAQAGAAAAAA==.Lucìan:BAABLgAECn8eAAIVAAgJ5h8PCQC5AgAVAAgJ5h8PCQC5AgAAAA==.Ludociel:BAAALgADCgkJEQAAAA==.Lunaclair:BAACLgAFFH8KAAIOAAIJiQ9kegCZAAAOAAIJiQ9kegCZAAAuAAQKf0AAAw4ACAmkHPIfAAkCAA4ACAmkHPIfAAkCABYAAglRBv1CAD4AAAEuAAUUAgkKACAALBMA.Lunadrus:BAABLgAECn8dAAIDAAcJPwo7dQAnAQADAAcJPwo7dQAnAQAAAA==.Lunarielle:BAACLgAFFH8HAAINAAMJ3Qu2KwDqAAANAAMJ3Qu2KwDqAAAuAAQKfxsAAg0ACAnWG8YVAIkCAA0ACAnWG8YVAIkCAAAA.',
Ly='Lyriaa:BAAALgADCgYJCwAAAA==.',
Ma='Macfly:BAABLgAECn8kAAINAAgJDxnjHQDpAQANAAgJDxnjHQDpAQAAAA==.Madmeatballs:BAAALgADCgIJAgABLgAECggJHwADAFccAA==.Magicmissile:BAACLgAFFH8GAAIDAAIJpAuAZAChAAADAAIJpAuAZAChAAAuAAQKfyEAAgMACAnTHFgcAEACAAMACAnTHFgcAEACAAAA.Makgora:BAAALgAECgMJBAABLgAECgYJFgATAFkhAA==.Makhvan:BAAALgAECgQJBwAAAA==.Maksoon:BAAALgAECgUJDAAAAA==.Maladjusted:BAAALgAECgMJBAAAAA==.Maléfique:BAAALgADCgkJEAAAAA==.Mancath:BAAALgAECggJCAAAAA==.Maplè:BAAALgAECgIJAwABLgAECggJHgAIAKMTAA==.Mar:BAAALgADCgMJAwAAAA==.Marlei:BAAALgADCgQJBAABLgAECggJGQADAFEMAA==.Marqose:BAAALgADCgYJCQAAAA==.Matan:BAAALgADCgUJBQAAAA==.',
Me='Melfie:BAAALgAECgcJEgAAAA==.Meliadoul:BAAALgAECgYJDwAAAA==.Mellyndra:BAABLgAECn8jAAIHAAgJBB0PDABSAgAHAAgJBB0PDABSAgAAAA==.Mercüry:BAAALgAECgEJAwAAAA==.Mezhren:BAAALgAECgYJBwAAAA==.',
Mh='Mhoramsgirl:BAAALgADCggJCwAAAA==.',
Mi='Midoriya:BAABLgAECn8hAAMMAAgJIhIvHQA6AQAMAAcJLBMvHQA6AQALAAUJkBF2OwCYAAAAAA==.Mistjack:BAABLgAFFH8IAAILAAQJRRDJEQANAQALAAQJRRDJEQANAQAAAA==.',
Mo='Momdad:BAACLgAFFH8JAAIKAAQJPxZwBgBgAQAKAAQJPxZwBgBgAQAuAAQKfy8AAgoACQmCIG8BAAEDAAoACQmCIG8BAAEDAAAA.Mongaux:BAAALgADCgQJBQAAAA==.Monkey:BAAALgAECgMJBwAAAA==.Morrígán:BAAALgADCgUJBQAAAA==.Moxi:BAAALgADCggJDQAAAA==.',
Mu='Muamman:BAAALgAECgMJAwAAAA==.Murda:BAAALgADCgYJCgAAAA==.Murphysflaw:BAAALgADCgUJCAAAAA==.Mutegen:BAAALgAFFAEJAQAAAA==.',
Mx='Mxhealeryduf:BAAALgAECgIJAgAAAA==.',
My='Mystallian:BAAALgAECgEJAQAAAA==.Mythicplus:BAAALgAECgcJCwAAAA==.',
['Mé']='Mémnoc:BAAALgAECgMJAwAAAA==.',
Na='Nadarien:BAAALgAECgYJDQAAAA==.Nadyia:BAAALgADCgEJAQAAAA==.Nailah:BAAALgADCgcJCwAAAA==.Nannergoat:BAAALgADCgMJAwAAAA==.Nastymikey:BAABLgAECn8XAAIjAAgJ4Rp2BwBzAgAjAAgJ4Rp2BwBzAgAAAA==.Nazdormu:BAABLgAECn8WAAIdAAYJmgINGgCvAAAdAAYJmgINGgCvAAAAAA==.',
Ne='Nefarious:BAAALgAECgcJCAAAAA==.Neisen:BAABLgAECn8ZAAMHAAgJig/gOgCOAQAHAAcJuw3gOgCOAQAEAAUJBwKY+gCeAAAAAA==.Neptune:BAAALgADCgYJBgAAAA==.',
No='Norna:BAAALgADCgUJCgAAAA==.Noz:BAAALgADCgkJCQAAAA==.',
Nu='Nufonewhodis:BAABLgAECn8WAAITAAYJWSFxHQATAgATAAYJWSFxHQATAgAAAA==.',
Ny='Nykolas:BAAALgADCgkJDAAAAA==.Nymofthedead:BAAALgAECgcJEwAAAA==.',
Oa='Oakgrove:BAAALgADCgQJBAAAAA==.',
Om='Ombraless:BAAALgADCgMJAwABLgAECgQJCAAGAAAAAA==.',
On='Oneforall:BAAALgAECgkJBgAAAA==.',
Op='Ophrizhani:BAAALgAECgMJAwAAAA==.',
Or='Orangegrove:BAAALgAECgEJAQAAAA==.Orpheal:BAAALgAECgUJBQAAAA==.Orphen:BAAALgADCgcJDQAAAA==.',
Pa='Paddleball:BAAALgADCgQJBAAAAA==.Paladouin:BAAALgAECgYJEwAAAA==.Pandammy:BAAALgAECgkJAgAAAA==.Pantro:BAAALgAECgYJDQAAAA==.Papalion:BAAALgAECgQJCgAAAA==.Paragas:BAAALgADCgkJEAAAAA==.Pawbs:BAAALgAECgQJCwAAAA==.',
Pe='Peanuts:BAAALgADCgcJBwAAAA==.Peoplehugger:BAAALgADCgMJAwAAAA==.',
Pi='Pickleburger:BAAALgAECgEJAQAAAA==.Pinklilydrd:BAAALgADCgkJGwAAAA==.',
Pl='Plaindonut:BAAALgAECgcJBwAAAA==.',
Pr='Priestdrago:BAAALgADCgUJBQAAAA==.Prissidebow:BAAALgADCgkJHAAAAA==.',
Ra='Rahzule:BAAALgADCgYJBwAAAA==.Ralynne:BAABLgAECn8mAAIbAAgJCQ9JHgBbAQAbAAgJCQ9JHgBbAQAAAA==.Ravenbrook:BAACLgAFFH8NAAIPAAQJjSV0AQDEAQAPAAQJjSV0AQDEAQAuAAQKfxsAAw8ACAmwJH8EAGIDAA8ACAmwJH8EAGIDABQAAQkwIAMxAFwAAAAA.Rawrr:BAABLgAECn8WAAIkAAYJlAkBHQDxAAAkAAYJlAkBHQDxAAAAAA==.Raxie:BAACLgAFFH8KAAMaAAQJOBJ7EQA7AQAaAAQJOBJ7EQA7AQAlAAEJBQ3MFABRAAAuAAQKfyoABBoACAlnG7gHAGkCABoACAlnG7gHAGkCACUABwmzEPAYAHUBABEAAQkBBOyHACgAAAAA.Razeth:BAABLgAECn8VAAIKAAYJ8BaQFQBmAQAKAAYJ8BaQFQBmAQAAAA==.',
Re='Reanne:BAAALgAECgYJEAAAAA==.Res:BAAALgAECgYJCwAAAA==.Rescorla:BAAALgAECggJCgAAAA==.Rethali:BAAALgADCgQJAgAAAA==.Rezr:BAAALgAECggJDQAAAA==.',
Rh='Rhixa:BAAALgADCgUJBQAAAA==.Rhymunky:BAAALgAECgMJAwAAAA==.',
Ri='Rifthor:BAAALgAECgYJCwAAAA==.Rillx:BAAALgADCgQJBgAAAA==.Ripmxi:BAABLgAECn8mAAIDAAgJzxBZRQCXAQADAAgJzxBZRQCXAQAAAA==.',
Ro='Robinski:BAAALgADCgEJAQAAAA==.Robotiss:BAAALgADCgIJAgAAAA==.Rocco:BAAALgADCgYJBwAAAA==.Rodevon:BAAALgADCggJCAAAAA==.Roknasaurus:BAAALgADCgUJCAAAAA==.Romani:BAAALgADCgYJBgAAAA==.Romeo:BAAALgADCgMJAwAAAA==.Ronaldreagnt:BAAALgAECgcJDAAAAA==.',
Ru='Runelight:BAAALgAFFAIJAgAAAA==.Rupertgiless:BAACLgAFFH8KAAICAAQJ1A4CKwAaAQACAAQJ1A4CKwAaAQAuAAQKfyAAAgIACQkzGnkiAIsCAAIACQkzGnkiAIsCAAAA.',
Sa='Sabeckya:BAAALgAECgMJBgAAAA==.Sacksmasher:BAAALgADCgcJDwAAAA==.Sampleshrimp:BAAALgADCgEJAgAAAA==.Saphyla:BAAALgADCgcJCwAAAA==.Sarcastyx:BAAALgAECgYJBwAAAA==.Sarrod:BAAALgADCgUJBQAAAA==.Saxines:BAAALgAECgQJBgAAAA==.',
Sc='Scaliefox:BAAALgAECgIJAgABLgAECggJIwAHAAQdAA==.Scarl:BAAALgADCgUJBQAAAA==.Schwarznacht:BAAALgADCgUJBQAAAA==.Schwarzwölf:BAAALgADCgYJCwAAAA==.Scoots:BAAALgADCgQJBAAAAA==.Scrubs:BAAALgAECgUJCAAAAA==.Scrubsevoker:BAAALgADCgcJDwAAAA==.Scumbum:BAAALgADCgIJAgAAAA==.Scyllo:BAAALgAECgQJBAAAAA==.',
Se='Seekndestroy:BAAALgAECgQJBQAAAA==.Selige:BAAALgAECgQJBAAAAA==.',
Sg='Sgtcuunt:BAAALgADCgQJBAAAAA==.',
Sh='Shaenicor:BAAALgADCgIJAgAAAA==.Shelbo:BAAALgADCgcJEAAAAA==.Shortshammy:BAAALgAECgEJAQABLgAFFAMJCwADACQJAA==.Shror:BAAALgADCgEJAQABLgAECgUJBQAGAAAAAA==.',
Si='Sicarune:BAAALgAECgEJAQAAAA==.Siiegrand:BAABLgAECn8UAAIZAAYJphLWHwAJAQAZAAYJphLWHwAJAQAAAA==.Silentswag:BAAALgAECgQJBAAAAA==.Sindrane:BAAALgADCgIJAwABLgAECggJKQAOADUWAA==.Sitzho:BAAALgADCgUJCAAAAA==.',
Sk='Skeleton:BAAALgAECgIJAgAAAA==.Skybringer:BAABLgAECn8jAAIEAAYJFAwqbQATAQAEAAYJFAwqbQATAQAAAA==.Skyee:BAABLgAECn8oAAMMAAkJAh0GDAC6AgAMAAkJAh0GDAC6AgALAAMJGBQUOACrAAAAAA==.Skylos:BAAALgAECgEJAgAAAA==.',
So='Soapscum:BAAALgADCgQJBAAAAA==.Soarphium:BAAALgAECgIJAgABLgAFFAUJFQATAD8SAA==.Solararc:BAAALgADCgEJAgAAAA==.Soleana:BAAALgAECgYJBQAAAA==.Sonicast:BAAALgAECgYJCQAAAA==.Sooie:BAAALgAECgYJEgAAAA==.Soramian:BAAALgADCgcJEgAAAA==.Soulcacher:BAABLgAECn8pAAMOAAgJNRYjMgCxAQAOAAgJGRYjMgCxAQAWAAMJTBbZHwDEAAAAAA==.Soxxy:BAAALgAECgEJAQABLgAFFAEJAQAGAAAAAA==.',
Sp='Spellgunner:BAABLgAECn8VAAIDAAgJOxuAKQD8AQADAAgJOxuAKQD8AQAAAA==.',
St='Stormwulf:BAAALgADCgUJBQABLgADCgkJFAAGAAAAAA==.Strombjorn:BAABLgAECn8eAAIIAAgJoxPaWAAlAQAIAAgJoxPaWAAlAQAAAA==.',
['Sø']='Sølaria:BAAALgAECgEJAQAAAA==.',
Ta='Tasireth:BAAALgADCgcJBwAAAA==.',
Te='Tessi:BAAALgAFFAEJAQAAAA==.',
Th='Thalrian:BAAALgAECgQJBQABLgAECggJLQAPAJ4jAA==.Thefailnym:BAAALgAECggJCAAAAA==.Theylive:BAAALgAECgYJDAAAAA==.Thondrin:BAAALgAECgYJCQAAAA==.Thordanil:BAAALgAECgEJAQAAAA==.Thrashedass:BAAALgADCgEJAQAAAA==.',
Ti='Tigerlilliy:BAAALgADCgYJEAAAAA==.Tim:BAAALgADCgYJCwAAAA==.Timerek:BAAALgADCgIJAgAAAA==.',
To='Toawulf:BAAALgAECgMJAwABLgADCgkJFAAGAAAAAA==.Toya:BAABLgAECn8bAAITAAcJShsXGgAxAgATAAcJShsXGgAxAgAAAA==.',
Tr='Trenazen:BAAALgADCgEJAQAAAA==.Trevain:BAAALgADCgkJGwAAAA==.Trimasdrood:BAAALgADCgMJAwAAAA==.Trivia:BAAALgADCgYJFwAAAA==.Trundle:BAAALgAECgEJAgAAAA==.Truthordare:BAABLgAECn8aAAIBAAYJPgmNEgDBAAABAAYJPgmNEgDBAAAAAA==.',
Tu='Turtei:BAAALgAECgEJAQABLgAFFAUJGAAMAJklAA==.Turtl:BAACLgAFFH8YAAIMAAUJmSVWAQDFAQAMAAUJmSVWAQDFAQAuAAQKfyMAAgwACQlnJjcAAPgDAAwACQlnJjcAAPgDAAAA.',
Tw='Twohoof:BAAALgADCgEJAQAAAA==.',
Tx='Txìewtkuä:BAAALgADCgkJCQAAAA==.',
Ty='Tyryn:BAAALgADCgMJBAAAAA==.',
Ug='Uglydragon:BAAALgAECgcJDAAAAA==.Uglypally:BAAALgADCgkJCQAAAA==.Uglypetguy:BAAALgAECgIJAgAAAA==.Uglyrogue:BAAALgAECgQJAgAAAA==.Uglyshaman:BAAALgAECgEJAgAAAA==.',
Ul='Ulgrym:BAAALgADCggJFAAAAA==.Ultimatia:BAAALgADCgMJBwAAAA==.',
Un='Unbalancéd:BAAALgAECgMJBAAAAA==.',
Va='Vahra:BAAALgADCgkJGQAAAA==.Valanther:BAAALgAECgMJAwAAAA==.Valantis:BAAALgADCgEJAQAAAA==.Valgaskav:BAABLgAECn8aAAIEAAgJvCBsGAA4AgAEAAgJvCBsGAA4AgAAAA==.Valimond:BAAALgAECgEJAQABLgADCgkJFAAGAAAAAA==.Valric:BAAALgADCgYJBwAAAA==.Vanarrath:BAAALgADCgYJBwAAAA==.Vandryelle:BAAALgADCgIJAgAAAA==.Varge:BAAALgADCgMJAwAAAA==.Varrathos:BAAALgADCgkJEgAAAA==.Vayl:BAAALgAECgMJAwAAAA==.',
Ve='Velisa:BAAALgADCgYJBgAAAA==.Ventrue:BAAALgADCgMJAwAAAA==.Verdesoul:BAAALgAECgQJBQAAAA==.Vesyra:BAAALgAECgQJBQAAAA==.',
Vi='Viralyn:BAAALgADCgMJAwABLgAECgcJHgAYAM8VAA==.',
Vo='Voidluck:BAABLgAECn8SAAISAAgJZRBgdABIAQASAAgJZRBgdABIAQAAAA==.Voker:BAAALgAECgIJBQABLgAECgQJCwAGAAAAAA==.Voladis:BAAALgAECgYJBwAAAA==.Voladro:BAAALgAECgQJBAAAAA==.Volos:BAABLgAECn8cAAIEAAgJixFONgClAQAEAAgJixFONgClAQAAAA==.Vordaman:BAABLgAECn8kAAIOAAgJFRUaOACZAQAOAAgJFRUaOACZAQAAAA==.',
Vy='Vynír:BAACLgAFFH8VAAICAAUJex9aFABlAQACAAUJex9aFABlAQAuAAQKfyMAAwEACAnnIowNAOwBAAIABwn0Il5HAPQBAAEABQkHI4wNAOwBAAAA.',
Wa='Waghoba:BAECLgAFFH8VAAIgAAUJNxjvAQByAQAgAAUJNxjvAQByAQAuAAQKfyAAAiAACAkkISYGAJwCACAACAkkISYGAJwCAAAA.Waito:BAAALgAECgQJBwAAAA==.Wandä:BAABLgAECn8cAAQYAAgJ/BknCwAQAgAYAAgJGhknCwAQAgAMAAgJxxDeEQCoAQALAAEJtQ5dWAAuAAAAAA==.Wardriccan:BAAALgAECgUJCwAAAA==.Warfle:BAAALgADCgYJBgAAAA==.Warrionomous:BAAALgAFFAEJAQABLgAFFAIJBgADAKQLAA==.Washu:BAABLgAECn8lAAMkAAgJjx23BgA2AgAkAAgJjx23BgA2AgAFAAMJTAtYIQB5AAAAAA==.',
Wh='Whimlock:BAAALgADCgQJBAABLgAFFAIJBQADAMQYAA==.Whims:BAAALgAECgYJCAABLgAFFAIJBQADAMQYAA==.Whimzie:BAAALgAECgEJAQABLgAFFAIJBQADAMQYAA==.Whorphium:BAAALgAECggJEgABLgAFFAUJFQATAD8SAA==.',
Wi='Willow:BAAALgAECgYJCwAAAA==.Winterous:BAAALgAECgEJAQAAAA==.',
Wo='Wonderbread:BAABLgAECn8lAAIEAAgJLxJjXQDLAQAEAAgJLxJjXQDLAQAAAA==.',
Wr='Wrager:BAAALgAECgUJBgAAAA==.Wrathofzaun:BAAALgAECgYJDwAAAA==.',
Wy='Wylest:BAAALgADCgcJBwAAAA==.Wynch:BAAALgAECgkJCAAAAA==.',
['Wâ']='Wârwôlf:BAABLgAECn8cAAMNAAgJYyJDBwC9AgANAAgJYyJDBwC9AgAJAAQJ+BWoVQDzAAAAAA==.',
Xe='Xenan:BAABLgAECn8gAAIEAAgJzAwzRgBzAQAEAAgJzAwzRgBzAQAAAA==.',
Xt='Xtrolldinary:BAAALgAECgQJCgAAAA==.',
Xv='Xvp:BAAALgAECgQJCgAAAA==.',
Xy='Xylophy:BAABLgAECn8gAAIFAAcJyBOGCABZAQAFAAcJyBOGCABZAQAAAA==.',
Ye='Yeastmode:BAACLgAFFH8KAAINAAQJEAguHgAfAQANAAQJEAguHgAfAQAuAAQKfx8AAg0ACAloGssaAGYCAA0ACAloGssaAGYCAAAA.',
Yo='Yonah:BAAALgAECgYJDAAAAA==.',
Yu='Yurc:BAABLgAECn8XAAIeAAYJxRmBDwBrAQAeAAYJxRmBDwBrAQAAAA==.',
Za='Zademan:BAAALgAECgUJBwAAAA==.Zappyu:BAAALgAECgkJBQABLgAECgkJCAAGAAAAAA==.',
Ze='Zeebra:BAAALgAECgMJBAAAAA==.Zeg:BAAALgAECgMJAwAAAA==.Zega:BAAALgAECgEJAQAAAA==.Zegafur:BAABLgAECn8qAAIVAAgJ/BsUFgAUAgAVAAgJ/BsUFgAUAgAAAA==.Zeruk:BAABLgAECn8XAAMMAAcJjwJrYACOAAAMAAYJlAJrYACOAAALAAcJmwEOQACBAAAAAA==.',
Zi='Zillionbúcks:BAACLgAFFH8YAAIEAAYJ+hLPBgCjAQAEAAYJ+hLPBgCjAQAuAAQKfxoAAgQACQnrHc8tAGwCAAQACQnrHc8tAGwCAAAA.',
Zy='Zylcat:BAAALgAECgUJCAAAAA==.',
['Zê']='Zêddicus:BAABLgAECn8oAAMBAAgJ0x5mAQB2AgABAAgJ0x5mAQB2AgACAAUJHwgA1ACyAAAAAA==.',
['Áq']='Áquafina:BAABLgAECn8rAAIDAAkJmQtzMQDbAQADAAkJmQtzMQDbAQAAAA==.',
['Îv']='Îvan:BAAALgADCggJCAAAAA==.',
['Ðö']='Ðö:BAABLgAECn8bAAIPAAgJOhmSDgAGAgAPAAgJOhmSDgAGAgAAAA==.',
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

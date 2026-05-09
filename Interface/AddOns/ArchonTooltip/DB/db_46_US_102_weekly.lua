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

local lookup = {'Hunter-BeastMastery','Paladin-Retribution','Unknown-Unknown','Shaman-Restoration','Shaman-Elemental','Shaman-Enhancement','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Warrior-Fury','Hunter-Survival','Warrior-Protection','Warrior-Arms','Druid-Restoration','Evoker-Preservation','DeathKnight-Unholy','Mage-Frost','Priest-Holy','DemonHunter-Devourer','Monk-Windwalker','Druid-Balance','Priest-Discipline','Mage-Fire','DeathKnight-Blood','Monk-Mistweaver','Paladin-Protection','Hunter-Marksmanship','DeathKnight-Frost','Druid-Feral','Paladin-Holy','Priest-Shadow',}
local provider = {region='US',realm='Gallywix',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abortheira:BAAALgADCgUJBQAAAA==.',
Ac='Acelord:BAAALgAECgcJDwAAAA==.',
Ad='Adaar:BAAALgAECgEJAQAAAA==.Adakat:BAAALgADCgEJAQAAAA==.Adanthedark:BAAALgADCgIJAgAAAA==.Adariom:BAAALgADCgUJCAAAAA==.Adrian:BAAALgADCgEJAQAAAA==.Adriannos:BAAALgADCgEJAQAAAA==.',
Ae='Aethir:BAAALgADCgYJBwAAAA==.',
Ag='Agonyy:BAAALgAECgUJDAAAAA==.',
Ah='Aharadack:BAAALgADCgUJCwAAAA==.',
Ak='Akawaka:BAAALgAECgEJAQAAAA==.Akiji:BAAALgADCgEJAQAAAA==.Akimurad:BAAALgAECgYJBgAAAA==.',
Al='Alakazam:BAAALgADCgcJBwAAAA==.Alanie:BAAALgADCggJCAAAAA==.Ald:BAAALgAECgEJAQAAAA==.Aldebaraum:BAAALgAECgEJAgAAAA==.Alexextreme:BAAALgAECgcJEQAAAA==.Alikth:BAAALgADCgYJBgAAAA==.Alista:BAAALgAECgMJAgAAAA==.Allandyr:BAABLgAECn8jAAIBAAcJxxRXLwCRAQABAAcJxxRXLwCRAQAAAA==.Alvarao:BAAALgAECgQJBAAAAA==.',
Am='Amandadark:BAAALgAECgEJAQAAAA==.Amano:BAAALgADCgYJDAAAAA==.',
An='Anaxthacia:BAAALgADCgMJAwAAAA==.Andinth:BAAALgADCgQJBAAAAA==.Andrepvp:BAAALgADCggJDwAAAA==.Andrit:BAAALgADCgEJAQAAAA==.Angelloz:BAABLgAECn8iAAICAAgJtA8CPgCMAQACAAgJtA8CPgCMAQAAAA==.Annaoh:BAABLgAECn8cAAICAAgJUh3dFQBLAgACAAgJUh3dFQBLAgAAAA==.Annia:BAAALgADCgYJBwAAAA==.Anãodengoso:BAABLgAECn8jAAICAAgJQSZdFQDpAgACAAgJQSZdFQDpAgAAAA==.',
Ap='Apökalÿpsïs:BAAALgAECgYJEgAAAA==.',
Ar='Arator:BAAALgAECgYJBgAAAA==.Ardry:BAAALgADCgYJBgAAAA==.Argaloth:BAAALgAECgYJBwAAAA==.',
As='Ashthon:BAABLgAECn8ZAAIBAAcJyxlFNgDVAQABAAcJyxlFNgDVAQAAAA==.Asmitta:BAAALgADCgQJBAAAAA==.',
At='Atomictank:BAAALgAECgUJCQAAAA==.Atonos:BAAALgAECgEJAwAAAA==.',
Au='Augustosg:BAAALgAECgEJAgABLgAECgQJCAADAAAAAA==.Auquenai:BAAALgADCgUJBQAAAA==.Aurielis:BAAALgAECgEJAQAAAA==.',
Av='Averagemage:BAAALgAECgEJAQAAAA==.',
Ay='Ayda:BAAALgAECgQJBAAAAA==.',
Az='Azadium:BAAALgAECgEJAwAAAA==.Azul:BAAALgAECgMJBAAAAA==.',
Ba='Badayaga:BAAALgADCgIJAgAAAA==.Bakunogrind:BAAALgAECgUJBQABLgAFFAQJBwAEAEMeAA==.Balthar:BAABLgAECn8gAAQFAAcJOhKyIwA3AQAFAAcJoxGyIwA3AQAGAAQJChFsHQD1AAAEAAQJBg8sXwB/AAAAAA==.Barcaldas:BAAALgAECgUJBgAAAA==.Barrocø:BAAALgAECgQJBQABLgAECgcJDwADAAAAAA==.Basara:BAAALgAECgYJCAAAAA==.Batefraco:BAAALgADCgIJAgAAAA==.',
Bb='Bbiel:BAABLgAECn8dAAMHAAUJbBRIDQD+AAAHAAUJbBRIDQD+AAAIAAEJ3wG17wAhAAAAAA==.',
Be='Beherit:BAAALgADCgMJBAAAAA==.Beliall:BAAALgADCgEJAQAAAA==.Belowlight:BAAALgADCgYJCwAAAA==.Belttazar:BAAALgADCgkJDwAAAA==.Berzan:BAAALgAECgMJBgAAAA==.Beyoond:BAACLgAFFH8JAAMIAAMJGxNUUACxAAAIAAIJcRpUUACxAAAJAAEJbwTLCgBBAAAuAAQKfzEABAgACQlXGwcPAHACAAgACAl2GgcPAHACAAcABAm3D+cxAPEAAAkAAgnAH3wMAL8AAAAA.',
Bi='Bielinski:BAAALgAECgQJBAAAAA==.',
Bl='Blackdut:BAAALgAECgIJAgAAAA==.Blackrøse:BAAALgADCgYJBgAAAA==.Blackteriaa:BAAALgAECgUJDwAAAA==.Blankis:BAAALgADCgYJCQAAAA==.Blizther:BAAALgADCgIJAgAAAA==.Bloodh:BAAALgAECgEJAwAAAA==.Bls:BAAALgADCgMJAwAAAA==.',
Bo='Boijf:BAAALgADCgEJAQAAAA==.Boladomal:BAAALgAECgMJAwAAAA==.Bones:BAAALgAECgEJAQAAAA==.Boromy:BAAALgAECgEJAgAAAA==.Boruck:BAAALgAECgIJAwAAAA==.',
Br='Braandom:BAAALgAECgcJCgAAAA==.Bradan:BAABLgAECn8eAAIKAAgJUhWaKgAOAgAKAAgJUhWaKgAOAgAAAA==.Brandomm:BAAALgAECgUJCQAAAA==.Branmir:BAAALgAECgMJBQAAAA==.Bridda:BAAALgAECgYJDAAAAA==.Bruzapaladin:BAAALgADCgUJBQAAAA==.',
Bt='Btrcaotics:BAAALgAECgIJBQAAAA==.',
['Bí']='Bíbs:BAAALgAECggJEQAAAA==.',
Ca='Cabanagé:BAAALgAECgUJBwAAAA==.Cabodecobre:BAAALgAECgUJCwAAAA==.Cainmarko:BAAALgAECgYJEAAAAA==.Caiowisk:BAAALgAECgYJDAAAAA==.Calir:BAAALgADCgYJFgAAAA==.Calçadora:BAABLgAECn8sAAILAAkJUx8dAgDaAgALAAkJUx8dAgDaAgAAAA==.Cardrok:BAAALgADCgEJAQAAAA==.Caridosa:BAAALgADCgUJBQAAAA==.Carnius:BAABLgAECn8+AAQMAAgJlB06CAD4AQAMAAgJbhw6CAD4AQAKAAIJuiDfVQBgAAANAAEJDxy0MwBSAAAAAA==.Casuall:BAAALgAECgcJBwAAAA==.Cataclysm:BAAALgAECgMJBAAAAA==.Catalango:BAAALgAECgMJBgAAAA==.Catapó:BAAALgAECgQJCQAAAA==.Catapózão:BAABLgAECn8fAAIOAAgJzxo+LAD+AQAOAAgJzxo+LAD+AQAAAA==.Catü:BAAALgAECgEJAQAAAA==.Cavernus:BAAALgADCgMJAwAAAA==.Caves:BAAALgADCgIJAgAAAA==.Caveston:BAAALgADCgUJCgAAAA==.',
Cb='Cbestabr:BAAALgADCgYJBgAAAA==.',
Ch='Chamadmordor:BAAALgAECgMJBQAAAA==.Charats:BAAALgADCgYJDQAAAA==.Charterine:BAAALgADCgYJBgAAAA==.Chaya:BAAALgADCgUJBQAAAA==.Chicknorris:BAAALgADCgUJBQAAAA==.Chifrudaxl:BAAALgAECgMJAwAAAA==.Chrisjks:BAAALgADCgYJCgAAAA==.',
Ci='Cindyn:BAAALgAECgEJAQAAAA==.',
Cl='Clared:BAAALgADCgEJAQAAAA==.Clebeya:BAAALgADCgQJBAAAAA==.Climps:BAAALgAECgYJCAAAAA==.',
Co='Cobyx:BAAALgADCgcJDAAAAA==.Cocaferoz:BAAALgADCgEJAQAAAA==.Coffeeaddict:BAAALgADCgMJAwAAAA==.Colugo:BAAALgADCgIJAgAAAA==.Coriisco:BAAALgADCgIJAgAAAA==.Corollaxei:BAABLgAECn8iAAIPAAgJSBhYDwBEAgAPAAgJSBhYDwBEAgAAAA==.Cosculluela:BAAALgADCgUJBwAAAA==.',
Cr='Creuzapriest:BAAALgAECgEJAQAAAA==.Cruzade:BAAALgAECgUJCgABLgAFFAEJAQADAAAAAA==.Cröwllëy:BAABLgAECn8ZAAIQAAcJxRYEOQCVAQAQAAcJxRYEOQCVAQAAAA==.',
Cu='Cubatao:BAAALgAECgUJDgAAAA==.Cucaracha:BAAALgAECgUJCQAAAA==.',
Da='Dahhak:BAAALgAECgEJAwAAAA==.Dakhgagul:BAAALgADCgUJBQAAAA==.Dakshayani:BAAALgADCgcJBwAAAA==.Danielbrz:BAAALgAECgMJAwAAAA==.Danygatuxa:BAAALgAECgQJBQAAAA==.Dardano:BAAALgADCgcJCgAAAA==.Daree:BAAALgAECgEJAQAAAA==.Darkinmt:BAAALgADCgcJCAAAAA==.Darknesstk:BAAALgAECgQJCAAAAA==.Darksiderptc:BAAALgADCgcJDwAAAA==.',
De='Deadvi:BAAALgAECgcJDwAAAA==.Deadziin:BAAALgAECgYJCAAAAA==.Demetrix:BAAALgADCgkJCgAAAA==.Dennyam:BAAALgAECgYJCQAAAA==.Derothey:BAABLgAECn8dAAIRAAcJUhQFRQCYAQARAAcJUhQFRQCYAQAAAA==.Deulorem:BAABLgAECn8gAAISAAkJaBdQBwB/AgASAAkJaBdQBwB/AgAAAA==.Devilblade:BAABLgAECn8RAAITAAgJSQmcjwACAQATAAgJSQmcjwACAQAAAA==.',
Di='Diabolynn:BAAALgADCggJCgAAAA==.',
Dk='Dkatraia:BAAALgAECgMJAwAAAA==.',
Dn='Dnghidan:BAACLgAFFH8KAAICAAQJWBcbFABXAQACAAQJWBcbFABXAQAuAAQKfxcAAgIACAmoH1NUAOUBAAIACAmoH1NUAOUBAAAA.Dngtobi:BAAALgAECgUJAQABLgAFFAQJCgACAFgXAA==.',
Do='Dollynhø:BAABLgAECn8dAAIUAAgJ+Rl1CQAkAgAUAAgJ+Rl1CQAkAgAAAA==.Donyed:BAAALgAECgQJBAAAAA==.Dottado:BAAALgADCgcJCgAAAA==.',
Dr='Drackah:BAAALgADCgcJBwAAAA==.Draconían:BAAALgAECgEJBQAAAA==.Dracón:BAAALgADCgkJDwAAAA==.Draigo:BAAALgAECgIJAgAAAA==.Dreykar:BAABLgAECn8eAAITAAgJORKHJwCeAQATAAgJORKHJwCeAQAAAA==.Drogorn:BAAALgAECgQJBwAAAA==.Druidaezeki:BAAALgADCgYJCwAAAA==.Druidjm:BAAALgADCgMJAwAAAA==.Druvannar:BAAALgADCgEJAQAAAA==.',
Du='Dultrasenegl:BAABLgAECn8WAAIBAAYJAA3wZQA2AQABAAYJAA3wZQA2AQAAAA==.Dunois:BAAALgAECgIJBgAAAA==.',
['Dä']='Dähäkä:BAAALgAECgYJCQAAAA==.',
Ed='Edven:BAACLgAFFH8JAAIPAAMJcwJOFgCiAAAPAAMJcwJOFgCiAAAuAAQKfx0AAg8ABgkxDMIlAEgBAA8ABgkxDMIlAEgBAAAA.',
El='Eldros:BAAALgAECgYJCAAAAA==.Elementais:BAAALgAECgQJBwAAAA==.Elgado:BAAALgAECgEJAwAAAA==.Elgatadexota:BAAALgADCgIJAgAAAA==.Eliksir:BAAALgAECgUJBQAAAA==.Ellanor:BAABLgAECn8ZAAIRAAgJ+RixJAATAgARAAgJ+RixJAATAgAAAA==.Eltão:BAAALgADCgEJAQAAAA==.Elunah:BAAALgADCgQJBAAAAA==.Elwindor:BAAALgADCgkJDAAAAA==.Elyind:BAAALgADCgYJBgAAAA==.',
Em='Emmymm:BAAALgADCgIJAgAAAA==.',
En='Endeavour:BAAALgADCgEJAQAAAA==.Enegadiel:BAAALgAECgcJEAAAAA==.Enoia:BAAALgADCgUJBQAAAA==.',
Eq='Equidnah:BAAALgADCgIJAgAAAA==.',
Er='Erickya:BAAALgAECgIJBAAAAA==.Ervadocè:BAABLgAECn8ZAAIVAAYJwhiYGgBiAQAVAAYJwhiYGgBiAQAAAA==.Ervelino:BAAALgAECgMJBAAAAA==.',
Es='Estrogosbald:BAAALgAECgcJDgAAAA==.',
Ev='Evely:BAAALgAECgYJEwAAAA==.',
Ex='Exarch:BAACLgAFFH8FAAILAAIJHA0WFgClAAALAAIJHA0WFgClAAAuAAQKfxkAAgsABwm0Ew8RAJ0BAAsABwm0Ew8RAJ0BAAAA.',
Fa='Faengar:BAAALgAECgUJCAAAAA==.Falconess:BAAALgADCgEJAQAAAA==.',
Fe='Felipebritoo:BAAALgAECgMJBgABLgAECgUJBgADAAAAAA==.Fenrirsp:BAAALgAECgUJCgAAAA==.Ferdruiid:BAAALgADCgkJEAAAAA==.Feropudo:BAAALgADCgkJDgAAAA==.Ferrarig:BAAALgAECgEJAwAAAA==.',
Fi='Figy:BAAALgAECgQJBAAAAA==.',
Fl='Flemma:BAABLgAECn8YAAIPAAgJIQfgEQAfAQAPAAgJIQfgEQAfAQAAAA==.Flexer:BAAALgAECgEJAQAAAA==.Flores:BAAALgADCgMJBQAAAA==.Floridastyle:BAABLgAECn8UAAIWAAUJDhHSJwDqAAAWAAUJDhHSJwDqAAAAAA==.',
Fo='Foguerosa:BAACLgAFFH8JAAMRAAMJpBzsPgARAQARAAMJpBzsPgARAQAXAAEJggDDAgA7AAAuAAQKfxYAAhEACAlgIaEgACcCABEACAlgIaEgACcCAAAA.Folghunthir:BAAALgADCgQJBAAAAA==.',
Fr='Frankkquini:BAAALgADCgYJEgAAAA==.Friodokrl:BAABLgAECn8kAAMYAAgJXhidCQDkAQAYAAgJXhidCQDkAQAQAAEJnQGbOQEfAAAAAA==.Fritzgerhart:BAAALgAECgEJAQAAAA==.Frostmhaw:BAAALgADCgUJBQAAAA==.Frostreaper:BAAALgAECgQJBgAAAA==.',
Fu='Fubukiofhell:BAAALgAECgYJDQAAAA==.Fuginzao:BAAALgAECgEJAQAAAA==.Furtacor:BAAALgADCgcJBwAAAA==.',
['Fí']='Fí:BAAALgADCggJDgABLgAECgkJFwABAPATAA==.',
Ga='Gabana:BAAALgADCgQJBAAAAA==.Gabdobbuh:BAAALgAECgUJCAAAAA==.Gabn:BAAALgAECgIJAwAAAA==.Gafgar:BAAALgADCgUJCQAAAA==.Gaila:BAAALgAECgIJAwAAAA==.Galduin:BAABLgAECn8iAAIKAAgJmBFNFQC/AQAKAAgJmBFNFQC/AQAAAA==.Gallymonk:BAAALgAECgcJBwAAAA==.',
Ge='Gedexx:BAAALgAECgMJAgAAAA==.Geduntruppa:BAAALgAECgYJBgAAAA==.Gentioiroh:BAAALgAECgMJAwAAAA==.',
Gh='Ghorderp:BAAALgADCgcJDAAAAA==.Ghosstt:BAAALgAECgEJAgAAAA==.Ghoulrozon:BAAALgADCgYJBgAAAA==.',
Gi='Giovannapala:BAAALgAECgcJDgAAAA==.Giripoca:BAAALgAECgQJCQAAAA==.',
Gl='Gladsmonge:BAABLgAECn8cAAIZAAcJBx3XEgDMAQAZAAcJBx3XEgDMAQAAAA==.Glorcckk:BAAALgAECgMJAwAAAA==.',
Gn='Gnomagga:BAAALgAECgYJCwABLgAECggJKwAaABgcAA==.Gnomohabe:BAAALgADCgQJBgAAAA==.',
Go='Goddofwarr:BAAALgADCggJEQAAAA==.Gonb:BAAALgADCgUJBQAAAA==.Goueki:BAABLgAECn8bAAMBAAgJFhRkJADEAQABAAgJFhRkJADEAQAbAAIJSwEqgwA8AAAAAA==.',
Gr='Greenzle:BAAALgAECgIJAgAAAA==.Grillnborst:BAAALgADCgEJAgAAAA==.Grilonp:BAAALgADCgQJBgAAAA==.Grogtixa:BAAALgAECgcJBwABLgAECgkJKgAFAFcWAA==.Gromoff:BAABLgAFFH8FAAIIAAIJth/0UQCrAAAIAAIJth/0UQCrAAAAAA==.Grunmonk:BAAALgADCgEJAQAAAA==.Grømmar:BAAALgADCgMJAwAAAA==.',
Gu='Gudangara:BAAALgADCgYJBgAAAA==.Gumy:BAAALgAECgEJAgAAAA==.Guztaverdead:BAAALgADCgQJBAAAAA==.',
['Gü']='Güistrong:BAAALgADCgIJAwAAAA==.',
Ha='Haakaí:BAAALgAECgUJCQAAAA==.Hackterin:BAAALgADCgYJBgAAAA==.Hadorah:BAAALgAECgUJBgAAAA==.Haerys:BAAALgADCgYJBgAAAA==.Handhemirr:BAAALgAECgMJBAAAAA==.Harany:BAAALgAECgYJDAAAAA==.Harrypotinho:BAABLgAECn8gAAIIAAcJ1RdAKgC8AQAIAAcJ1RdAKgC8AQAAAA==.Haunexd:BAAALgADCgMJAwAAAA==.Havenna:BAAALgAECgUJCAAAAA==.',
He='Headøhunter:BAAALgAECgEJAgAAAA==.Healgate:BAAALgAECgEJAQAAAA==.Heeythaly:BAAALgADCgEJAQAAAA==.Hellenah:BAAALgADCggJCAAAAA==.Herika:BAAALgADCgMJAwAAAA==.',
Ho='Hoem:BAAALgAECgMJAwAAAA==.Holand:BAAALgAECgYJDgAAAA==.Holydread:BAAALgAECgIJAgAAAA==.',
Hu='Hulig:BAABLgAECn8dAAICAAgJoByFFgBHAgACAAgJoByFFgBHAgAAAA==.',
['Hø']='Høkulani:BAAALgAECgQJCAAAAA==.',
Ib='Ibuprofens:BAAALgAECgEJAQAAAA==.',
Ik='Ikiam:BAAALgAECgQJBQAAAA==.Ikslawok:BAAALgADCgYJEAAAAA==.',
Il='Ileria:BAAALgAECgYJBwAAAA==.Illarion:BAAALgADCgQJBAAAAA==.Illidanos:BAAALgAECgYJDwAAAA==.Illidansan:BAAALgADCgIJAgABLgAECgEJAQADAAAAAA==.Illidris:BAAALgAECgUJBQAAAA==.Illumiinated:BAAALgAECgYJEQAAAA==.',
In='Incarus:BAAALgAECgUJBwAAAA==.Indis:BAAALgADCgQJBgAAAA==.Interst:BAAALgAECgEJAQAAAA==.',
Ir='Irion:BAAALgADCgkJJgAAAA==.',
Is='Iscalio:BAAALgAECgUJCAAAAA==.',
Ja='Jackdawnsong:BAAALgAECgEJAgAAAA==.Jaene:BAAALgADCgMJAwAAAA==.Jahuun:BAAALgAECgYJDAAAAA==.Jamantoso:BAAALgAECgEJAQAAAA==.',
Je='Jeess:BAAALgADCgMJAwAAAA==.Jefflich:BAABLgAECn8aAAMQAAgJRgp5bAAJAQAQAAgJ8Qh5bAAJAQAcAAEJhxLkFQA2AAAAAA==.',
Jg='Jg:BAAALgAECgUJBwABLgAECgYJDgADAAAAAA==.',
Ji='Jinknu:BAAALgAECgIJBAAAAA==.',
Jo='Jottapeg:BAAALgADCgcJAwAAAA==.',
Ju='Jubard:BAAALgADCgkJDAAAAA==.Juliamarques:BAAALgAECgMJBAAAAA==.',
['Jü']='Jüllÿe:BAAALgADCgEJAQAAAA==.',
Ka='Kaaellthas:BAAALgAECgIJBAAAAA==.Kacolux:BAAALgADCgEJAQAAAA==.Kaisaargente:BAAALgAECgEJAQAAAA==.Kakarotho:BAAALgAECgMJCQAAAA==.Kaldonios:BAAALgADCgcJEgAAAA==.Kamasutram:BAAALgADCgYJCwAAAA==.Kanadriel:BAAALgAECgcJCQAAAA==.Kanarinho:BAABLgAECn8lAAIOAAkJIh+fAwA1AwAOAAkJIh+fAwA1AwAAAA==.Karmussie:BAAALgADCgEJAQAAAA==.Kazandra:BAAALgADCgYJBgAAAA==.',
Ke='Kendars:BAABLgAECn8VAAQVAAYJ0hKWSAAKAQAVAAUJJhKWSAAKAQAOAAUJFQ+ydgDzAAAdAAEJgBWwIwBEAAAAAA==.Ket:BAAALgADCgMJAwAAAA==.',
Kh='Khanmir:BAAALgAECgMJBgAAAA==.Khild:BAAALgAECgYJDQAAAA==.Khonar:BAAALgADCgEJAQAAAA==.',
Ki='Killerdek:BAAALgAECgEJAQAAAA==.Killshoty:BAAALgAECgEJAgAAAA==.',
Kl='Kluzlocak:BAABLgAECn8gAAIWAAYJEwp5IAAoAQAWAAYJEwp5IAAoAQAAAA==.',
Ko='Komah:BAAALgAECgEJAQAAAA==.Korav:BAAALgAECgMJCQAAAA==.Korium:BAAALgADCgUJBQABLgAECggJJAAMAAkiAA==.Koruno:BAAALgADCgYJBgAAAA==.',
Kr='Krosn:BAAALgAECgEJAQAAAA==.Krozhul:BAAALgAECgQJBgAAAA==.',
Ku='Kurnous:BAAALgAECgEJAQAAAA==.Kutirenzo:BAAALgADCgUJBwAAAA==.',
La='Lafiel:BAAALgAECgcJCwAAAA==.Lamelo:BAAALgADCgYJBgAAAA==.Lanmo:BAAALgAECgcJAgAAAA==.Largatixazul:BAAALgADCgUJBgAAAA==.Laurea:BAAALgAECgYJBgABLgAECgkJFgAeAJAdAA==.',
Le='Leebron:BAAALgAECgEJAgAAAA==.Lefthalas:BAAALgAECgUJCgAAAA==.Leitchero:BAAALgAECgEJAQAAAA==.Lemaz:BAAALgAECgEJAQAAAA==.Leonelmessi:BAAALgAFFAQJAQAAAA==.Lesco:BAAALgADCgMJAwAAAA==.',
Li='Lianele:BAAALgAECgIJAgAAAA==.Liaras:BAABLgAECn8oAAMSAAgJBhdSDwD0AQASAAgJBhdSDwD0AQAfAAIJzABAaQAmAAAAAA==.Lichtbaum:BAAALgAECgcJEAAAAA==.Lightsertrop:BAAALgADCgIJAgAAAA==.Liifecomm:BAACLgAFFH8GAAISAAMJ3hhpDQD7AAASAAMJ3hhpDQD7AAAuAAQKfy4AAhIACAmAH1gNAIICABIACAmAH1gNAIICAAAA.Liike:BAAALgADCgMJAwAAAA==.Linestra:BAAALgADCgUJBQAAAA==.Liniak:BAAALgAECgUJCAAAAA==.Lisong:BAAALgADCgUJBQAAAA==.Littlepurple:BAACLgAFFH8JAAITAAMJzxJ0GwD2AAATAAMJzxJ0GwD2AAAuAAQKfyQAAhMACQl0HJkYAMICABMACQl0HJkYAMICAAAA.',
Lo='Longhai:BAAALgADCgUJCAAAAA==.Lookatmylock:BAABLgAECn8dAAMHAAYJYhtEBgCOAQAHAAYJYhtEBgCOAQAIAAIJRQmcBQFRAAAAAA==.Lordpain:BAAALgAECgQJCAAAAA==.Lortherti:BAAALgADCgUJBgAAAA==.Lorwin:BAAALgAECgcJEAAAAA==.Lotusbr:BAAALgADCgEJAQAAAA==.Louisenacioo:BAAALgAECgYJDQAAAA==.Loátrak:BAAALgADCgMJAwAAAA==.',
Lu='Luccablack:BAAALgAECgMJAwAAAA==.Lucyx:BAAALgAECgEJAQAAAA==.Luidar:BAAALgAECgQJBAAAAA==.Lukaslions:BAAALgAECgcJDgAAAA==.Lunarie:BAAALgAECgYJEwABLgAECgcJBwADAAAAAA==.Luphoe:BAABLgAECn8dAAMOAAcJrhzFJwAWAgAOAAcJrhzFJwAWAgAVAAQJkw6TOQCjAAAAAA==.Luxanä:BAAALgADCggJDQAAAA==.',
['Lé']='Léio:BAAALgADCgcJCAAAAA==.Léora:BAAALgADCgIJAgAAAA==.',
['Lø']='Lørdsith:BAAALgAECgYJCAABLgAECgcJBAADAAAAAA==.',
['Lÿ']='Lÿcäns:BAAALgADCgMJAwAAAA==.',
Ma='Madagalux:BAAALgAECgQJDwAAAA==.Madjack:BAAALgAECgMJAwAAAA==.Madushi:BAAALgAECgIJAgAAAA==.Magatiun:BAAALgADCgMJBAAAAA==.Magogunt:BAABLgAECn8VAAIRAAgJUgthcwAqAQARAAgJUgthcwAqAQAAAA==.Maguul:BAAALgAECgUJDAAAAA==.Magzifeh:BAABLgAECn8TAAIBAAcJvCA0EwA3AgABAAcJvCA0EwA3AgAAAA==.Mahadevi:BAAALgADCgIJAgAAAA==.Malandrvs:BAAALgAFFAEJAgAAAA==.Maljamim:BAAALgADCgIJAgAAAA==.Mamuthwar:BAABLgAECn8ZAAMKAAcJnRgaNgDQAQAKAAcJnRgaNgDQAQANAAEJMQ7WQQA1AAAAAA==.Mandingavudu:BAAALgAECgEJAgABLgAECgQJBwADAAAAAA==.Manei:BAAALgAECgMJAwAAAA==.Mangalarga:BAAALgADCgEJAQAAAA==.Manmoden:BAAALgADCgUJBQABLgAECgQJBwADAAAAAA==.Manopaladino:BAAALgADCgYJBgAAAA==.Manowlo:BAAALgAECgMJAwAAAA==.Manzagon:BAAALgAECgQJBwABLgAECgQJBwADAAAAAA==.Marmelo:BAAALgADCgQJBAAAAA==.Marretasanta:BAABLgAECn8eAAICAAcJTRIWSgBnAQACAAcJTRIWSgBnAQAAAA==.Marù:BAAALgAECgQJBQAAAA==.Marúh:BAACLgAFFH8NAAIEAAQJ2xrfDwBEAQAEAAQJ2xrfDwBEAQAuAAQKfyYAAgQACAnzIsQFABYDAAQACAnzIsQFABYDAAAA.Matroná:BAAALgADCggJBwAAAA==.Maxmorf:BAAALgADCgUJBQAAAA==.Mayarabr:BAAALgADCgcJEgAAAA==.Mazeratos:BAAALgAECgMJAwAAAA==.',
Mc='Mcorelhao:BAAALgADCgEJAQAAAA==.',
Me='Megrezz:BAAALgAECgEJAQAAAA==.Mehiel:BAAALgAECgEJAQAAAA==.Mekihlvshtak:BAAALgAECgEJAQAAAA==.Meliøðas:BAAALgADCgEJAQAAAA==.Mendingu:BAAALgAECgcJDwAAAA==.Merumim:BAAALgAECgYJCgAAAA==.Metalgirl:BAAALgADCgYJCwAAAA==.',
Mi='Midrão:BAAALgAECgIJAgAAAA==.Milczarek:BAAALgAECgEJAQAAAA==.Mindlocker:BAABLgAECn8UAAIIAAYJiwWrdQDdAAAIAAYJiwWrdQDdAAAAAA==.Minorus:BAAALgAECgcJEgAAAA==.Mistifs:BAAALgAECggJEQAAAA==.',
Mo='Modogz:BAAALgADCgYJBgAAAA==.Momongadk:BAAALgADCgcJBwAAAA==.Monkeydking:BAAALgADCgUJBQAAAA==.Morania:BAAALgAECgYJCQAAAA==.Mordekais:BAAALgAECgIJAgAAAA==.Morganne:BAAALgAECgEJAQAAAA==.Moriyama:BAABLgAECn8dAAIOAAcJIhtTIQC7AQAOAAcJIhtTIQC7AQAAAA==.Morphisz:BAAALgAECgQJBwAAAA==.Morphiszs:BAAALgAECgMJBAABLgAECgQJBwADAAAAAA==.Morphizs:BAAALgAECgEJAgABLgAECgQJBwADAAAAAA==.Mortesan:BAAALgADCgEJAQABLgAECgEJAQADAAAAAA==.',
Mp='Mpastor:BAAALgADCgUJBQAAAA==.',
Mu='Muca:BAAALgADCgEJAQAAAA==.Muho:BAAALgADCgEJAQAAAA==.Mukonha:BAABLgAECn8iAAIIAAcJeA7FRgBUAQAIAAcJeA7FRgBUAQAAAA==.',
['Mã']='Mãoleves:BAAALgADCgEJAQAAAA==.',
['Må']='Måximus:BAAALgAECgIJAgAAAA==.',
Na='Naeryndam:BAAALgADCgEJAQAAAA==.Narutowow:BAAALgADCgMJAwAAAA==.Natcmd:BAAALgADCggJDAAAAA==.Nayanna:BAAALgADCgcJDQAAAA==.',
Ne='Negblack:BAAALgAECgYJCwAAAA==.Neggi:BAAALgAECgUJBwAAAA==.Nemesysy:BAAALgAECgMJAwAAAA==.Nerphien:BAAALgADCgUJBQAAAA==.Nesktpally:BAAALgAECgcJCAAAAA==.Netbrood:BAAALgADCgUJBgABLgAECgUJBwADAAAAAA==.Netbrother:BAAALgAECgUJBwAAAA==.Nethdorai:BAAALgADCgQJBAAAAA==.Netherbane:BAABLgAECn8VAAMNAAcJYBRjDQBrAQANAAcJYBRjDQBrAQAKAAEJAAAMdgAAAAAAAA==.Nezuko:BAAALgADCgcJEQABLgAECgcJIAAIANUXAA==.',
Ni='Nightmære:BAAALgAECgQJBgAAAA==.Nikelok:BAAALgAECgMJAwAAAA==.Ninfador:BAABLgAECn8eAAIWAAYJgxe2FwB5AQAWAAYJgxe2FwB5AQAAAA==.Ninpus:BAAALgAECgMJAwAAAA==.',
No='Noobmasteer:BAAALgADCgIJAgAAAA==.Nooneknow:BAABLgAECn8jAAIQAAgJxCBIEwBhAgAQAAgJxCBIEwBhAgAAAA==.Nosrede:BAAALgAECgEJAQAAAA==.Notz:BAAALgADCgMJBAAAAA==.',
Nu='Nuccixama:BAAALgAECgEJAQAAAA==.',
Ny='Nyde:BAAALgADCgEJAQAAAA==.',
['Nø']='Nøar:BAAALgADCgIJAgAAAA==.',
Oa='Oakshlar:BAAALgAECgQJCgAAAA==.',
Oc='Ocelaris:BAAALgAECgEJAgAAAA==.',
Oh='Ohluh:BAAALgAECgcJBwAAAA==.',
Or='Oryana:BAAALgADCgcJIAAAAA==.Oríon:BAAALgADCgIJAgAAAA==.',
Ot='Otton:BAABLgAECn8XAAICAAYJOwc3hADkAAACAAYJOwc3hADkAAAAAA==.',
Ov='Overnigth:BAAALgADCgIJAgAAAA==.Overwalker:BAAALgADCgIJAgAAAA==.Ovosemdente:BAAALgADCgEJAQAAAA==.',
Ow='Owllskull:BAAALgAECgUJBgAAAA==.',
Oz='Ozovo:BAAALgAECgIJAgAAAA==.',
Pa='Pacoka:BAAALgADCgQJBQAAAA==.Padrafferty:BAAALgADCgcJBwAAAA==.Paidesanto:BAAALgAECgYJEAAAAA==.Paidesantox:BAAALgAECgYJCAABLgAECggJIgAKAJgRAA==.Paladinokun:BAAALgAECgEJAQAAAA==.Palanis:BAAALgAECgcJBwAAAA==.Palazarta:BAAALgAECgcJEAAAAA==.Pandavoli:BAAALgAECgUJCQAAAA==.Panky:BAAALgADCgEJAQAAAA==.Panquecudo:BAAALgADCgIJAgAAAA==.',
Pd='Pdois:BAAALgADCgMJAwAAAA==.',
Pe='Pesscador:BAAALgAECgMJAwAAAA==.Petrolesk:BAAALgAECgYJBgAAAA==.',
Pi='Piriguetee:BAAALgADCgEJAQAAAA==.Pirro:BAAALgAECgEJAQAAAA==.Pisadinha:BAAALgADCgcJBwAAAA==.',
Pk='Pkzimn:BAAALgADCgUJBQAAAA==.',
Pl='Playsson:BAAALgAECgYJEgAAAA==.Plottwist:BAAALgADCgcJDwABLgAECggJIgAQADUWAA==.',
Po='Pogonus:BAAALgADCgIJAgAAAA==.Pontocego:BAAALgAECgQJBAAAAA==.Powerworth:BAAALgADCgQJBAAAAA==.',
Pr='Pravios:BAAALgAECgIJBAAAAA==.Priestkill:BAAALgADCgMJAgAAAA==.',
Pt='Pterodactilo:BAAALgAECgYJAQAAAA==.',
Pu='Puherito:BAAALgAECgQJBwAAAA==.Purgas:BAAALgAECgQJDAAAAA==.',
Qu='Quinthalam:BAAALgADCgMJAwAAAA==.',
Ra='Rafazinho:BAAALgADCgQJBAAAAA==.Ramyna:BAAALgAECgMJBQAAAA==.Ramyra:BAAALgADCgcJDQAAAA==.Raphaeldh:BAAALgAECgEJAgAAAA==.Raphahunterr:BAAALgADCgEJAQAAAA==.Raposa:BAAALgADCgEJAQAAAA==.Raposinha:BAAALgADCgMJAwAAAA==.Rarkway:BAAALgAECgYJCQAAAA==.Rayanne:BAAALgADCgYJBgAAAA==.',
Re='Reckfull:BAAALgAECgYJBgAAAA==.Regininha:BAAALgAECgEJAQAAAA==.Reloumifrend:BAAALgAECgcJCgAAAA==.Rendros:BAAALgADCgUJBQAAAA==.',
Rh='Rhaegaar:BAAALgAECgcJDQAAAA==.Rhodinius:BAAALgAECgMJCAAAAA==.',
Ri='Rivotreel:BAAALgADCgQJBAAAAA==.',
Ro='Robeerth:BAAALgAFFAEJAQAAAA==.Rochera:BAAALgAECgEJAQAAAA==.Rokhanar:BAAALgAECgUJBgAAAA==.',
Ru='Ruhtarr:BAAALgADCgEJAQAAAA==.',
Ry='Ryukato:BAAALgAECgQJBQAAAA==.',
Sa='Saek:BAAALgAECgcJEgAAAA==.Sanderclone:BAAALgAECgEJAQAAAA==.Sanguenafaca:BAAALgADCgYJBgAAAA==.Santiss:BAAALgAECgYJEQAAAA==.Santorini:BAAALgAECgcJCwAAAA==.Saphirot:BAAALgADCgUJBQAAAA==.Saphis:BAAALgADCgEJAQAAAA==.Sardado:BAAALgAECgEJAQAAAA==.Sardron:BAAALgADCgMJAwAAAA==.',
Sc='Scanorr:BAAALgAECgEJAQAAAA==.Scheffers:BAAALgAECgUJBAAAAA==.',
Se='Selah:BAAALgADCgMJBQAAAA==.Selver:BAAALgAECgYJBwABLgAFFAcJFQAfAAAZAA==.Selüne:BAAALgAECgcJDQAAAA==.Sephora:BAAALgAECgYJBgABLgAECggJKAASAAYXAA==.',
Sh='Shadowlock:BAAALgADCgIJAQABLgAECgYJDAADAAAAAA==.Shadowmornac:BAAALgAECgEJAQAAAA==.Shamanica:BAAALgAECgEJAgAAAA==.Shamateus:BAAALgADCggJEwAAAA==.Shasuna:BAAALgADCgIJAgAAAA==.Shaunnun:BAAALgADCgEJAQAAAA==.Shenloong:BAAALgADCgMJAwAAAA==.Shinnók:BAAALgAECgIJAgAAAA==.Shiíro:BAAALgAECgMJBQABLgAFFAMJCAACAHkRAA==.Shynato:BAAALgADCgEJAQAAAA==.Shynock:BAAALgADCgEJAQAAAA==.Shãka:BAAALgADCgMJAwAAAA==.',
Si='Siladriel:BAAALgADCgMJAwAAAA==.Sirgonzo:BAAALgAECgYJDAAAAA==.',
Sk='Skullexus:BAAALgAECgMJBAAAAA==.Skunkbr:BAAALgADCgEJAQAAAA==.',
Sl='Sleepychety:BAAALgAECgUJBgAAAA==.Slowsmoke:BAAALgADCgEJAQAAAA==.',
Sn='Snatzz:BAAALgADCgMJAgAAAA==.',
So='Soggoth:BAAALgADCgkJCQAAAA==.Solk:BAAALgADCgQJBAAAAA==.Sontarfury:BAAALgAECgEJAQAAAA==.Sorim:BAABLgAECn8XAAIOAAYJYB/XGQD1AQAOAAYJYB/XGQD1AQAAAA==.Soryan:BAABLgAECn8dAAIOAAcJ4RSpJACkAQAOAAcJ4RSpJACkAQAAAA==.Soulassassin:BAAALgADCgIJAwAAAA==.Soulhell:BAABLgAECn8VAAIWAAYJzxO7GgBbAQAWAAYJzxO7GgBbAQAAAA==.',
Sp='Spartanlofs:BAAALgADCgcJEQAAAA==.Spawndeath:BAAALgADCgEJAQAAAA==.',
Ss='Ssushii:BAAALgAECgEJAQAAAA==.',
St='Stigmata:BAAALgADCgcJCAAAAA==.Stixmixdk:BAAALgAFFAQJAgAAAA==.Straz:BAAALgADCgQJBAAAAA==.Strongman:BAAALgAECgYJBgAAAA==.Stx:BAAALgAECgEJAQAAAA==.',
Su='Subsdk:BAACLgAFFH8IAAIQAAQJDg99MwA3AQAQAAQJDg99MwA3AQAuAAQKfyAAAhAACAk/HPofAAkCABAACAk/HPofAAkCAAAA.Sunwalkers:BAAALgAECgUJBgAAAA==.',
Sy='Systeni:BAAALgADCgkJDQAAAA==.',
['Sø']='Søøssø:BAAALgAECgEJAQAAAA==.',
Ta='Taha:BAAALgAECgYJDAAAAA==.Taillys:BAAALgADCgMJBAAAAA==.Tainy:BAAALgAECgEJAQAAAA==.Takenaka:BAAALgADCgMJAwAAAA==.Tarez:BAAALgAECgEJAQAAAA==.Tarfonir:BAAALgAECgYJCAAAAA==.Tavalira:BAAALgADCgYJBgAAAA==.',
Te='Tealen:BAAALgAECgEJAQAAAA==.Ted:BAAALgAECgcJDAAAAA==.Teiseken:BAAALgAECgcJBwAAAA==.Tenébria:BAAALgAECgcJBwAAAA==.Teratsemknk:BAAALgAECgMJAwAAAA==.',
Th='Tharnforge:BAAALgAECgEJAQAAAA==.Thejokker:BAAALgAFFAIJAgAAAA==.Themooster:BAAALgAFFAEJAQAAAA==.Thepickles:BAAALgADCgkJEwAAAA==.Thepunk:BAAALgAECgQJCAAAAA==.Thintor:BAAALgADCgEJAQAAAA==.Thormento:BAABLgAECn8VAAIEAAcJkBF/LABlAQAEAAcJkBF/LABlAQAAAA==.',
Ti='Tigerblood:BAAALgADCgUJBQAAAA==.Tipooreeii:BAAALgADCgEJAQAAAA==.Titanicos:BAAALgADCgQJBAAAAA==.',
Tj='Tjhunter:BAABLgAECn8fAAIBAAgJnQqyPgBTAQABAAgJnQqyPgBTAQAAAA==.',
To='Tobbiy:BAAALgAFFAEJAgAAAA==.Toddyb:BAAALgAECgEJAQAAAA==.',
Tr='Tranh:BAAALgADCgkJFQAAAA==.Traxer:BAAALgADCgQJBAAAAA==.Tripäsecä:BAAALgAECgMJBQAAAA==.Troladora:BAAALgAECgYJDwAAAA==.',
Ts='Tsreis:BAAALgADCgEJAQAAAA==.',
Ty='Tyrandrisa:BAAALgADCgIJAQAAAA==.',
['Tá']='Tátu:BAAALgADCgMJAwAAAA==.',
Um='Ummetrodefio:BAAALgADCgEJAQAAAA==.',
Ut='Uthred:BAABLgAECn8hAAQQAAgJIwfDaAARAQAQAAgJcwPDaAARAQAcAAYJoARuDADrAAAYAAMJrgkFKwB0AAAAAA==.',
Va='Vaelryn:BAAALgAECgUJBgAAAA==.Valdemmon:BAAALgADCgcJBwAAAA==.Valororo:BAAALgAECgMJBQAAAA==.Vandlesh:BAAALgAECgYJDwAAAA==.Varka:BAAALgADCgYJGQAAAA==.',
Ve='Velkharun:BAAALgAECgQJCwABLgAFFAEJAQADAAAAAA==.Venatrin:BAAALgADCgkJCQAAAA==.Vexxv:BAAALgAFFAIJAwAAAA==.Vexxz:BAAALgAECgYJBwAAAA==.',
Vi='Viquue:BAAALgADCgYJBgAAAA==.Vivisoft:BAAALgADCgMJAwAAAA==.',
Vo='Voidrb:BAAALgADCgcJBwABLgAECgcJDwADAAAAAA==.Vovogamer:BAAALgADCgEJAQAAAA==.',
['Vò']='Vòxs:BAACLgAFFH8FAAINAAMJVBBvDADjAAANAAMJVBBvDADjAAAuAAQKf0EAAw0ACAk8JA0DAH4CAA0ABwnDJA0DAH4CAAoABglHHoAuAPcBAAAA.',
Wa='Walkery:BAAALgADCgIJAgAAAA==.Wattari:BAABLgAECn8VAAIMAAYJFwMhNQCdAAAMAAYJFwMhNQCdAAAAAA==.',
Wh='Whiteep:BAAALgADCgYJCAAAAA==.Whiteseraph:BAAALgADCgEJAQAAAA==.Whynchester:BAAALgADCgEJAQAAAA==.',
Wi='Windsailor:BAAALgADCggJDgAAAA==.Wiserys:BAABLgAECn8cAAMIAAYJ/B0tKQDBAQAIAAYJ/B0tKQDBAQAJAAMJOQyiGwCXAAAAAA==.',
Wm='Wmarcão:BAAALgAECgUJCAAAAA==.',
Wo='Wolfiez:BAAALgAECgUJDAAAAA==.Wolfnwar:BAAALgAECgQJBgAAAA==.Wopz:BAAALgADCgUJBQAAAA==.Worq:BAAALgADCgMJAwAAAA==.',
Wq='Wqz:BAABLgAECn8UAAIBAAcJWhmQNgDUAQABAAcJWhmQNgDUAQAAAA==.',
Wu='Wunamuno:BAAALgADCgkJCQAAAA==.',
Xa='Xallatath:BAAALgADCgUJBQAAAA==.Xamela:BAAALgADCgMJAwAAAA==.Xamãna:BAAALgAECgQJCQAAAA==.',
Xe='Xevron:BAAALgAECgQJBAAAAA==.Xexnetw:BAAALgAECgEJAQAAAA==.Xexnew:BAABLgAECn8WAAIYAAgJfRsgBwAgAgAYAAgJfRsgBwAgAgAAAA==.',
Xi='Xidevill:BAAALgAECgIJAgAAAA==.Xinthorak:BAAALgADCgEJAgAAAA==.Xinzhou:BAAALgADCgQJCAAAAA==.Xiseth:BAAALgAECgEJAQAAAA==.Xixíca:BAAALgADCgQJBQAAAA==.',
Xm='Xmari:BAAALgAECgEJAQAAAA==.',
Xu='Xulaman:BAAALgAECgcJDgAAAA==.Xungodz:BAAALgADCgQJBAAAAA==.Xunxu:BAABLgAECn8ZAAMCAAYJcxOKaQAaAQACAAYJcxOKaQAaAQAeAAEJJgM0ngArAAAAAA==.',
Xy='Xynrath:BAAALgADCgMJAwAAAA==.',
['Xÿ']='Xÿon:BAAALgAECgEJAQAAAA==.',
Ya='Yannadcg:BAABLgAECn8jAAISAAgJgwVKJgAXAQASAAgJgwVKJgAXAQAAAA==.',
Yo='Youdie:BAABLgAECn8YAAIfAAgJeRLsKgCEAQAfAAgJeRLsKgCEAQAAAA==.',
Yu='Yulthuan:BAAALgADCgMJAwAAAA==.',
Yv='Yvernus:BAAALgAECgQJBgAAAA==.',
Za='Zaaraki:BAABLgAECn8iAAMQAAgJNRYIQgB3AQAQAAgJ2xUIQgB3AQAYAAcJ/xKWFgAcAQAAAA==.Zarolho:BAABLgAECn8VAAIFAAYJRg6vOQDGAAAFAAYJRg6vOQDGAAAAAA==.',
Ze='Zenitsua:BAAALgAECgYJCAAAAA==.Zephiir:BAAALgAECgYJDwAAAA==.Zeryen:BAAALgAECgEJAQAAAA==.',
Zh='Zhunka:BAAALgADCgEJAQAAAA==.',
Zo='Zornak:BAAALgADCgUJBQAAAA==.',
Zz='Zzx:BAAALgADCgcJBwAAAA==.',
['Zé']='Zécasete:BAAALgADCgUJBwAAAA==.',
['Ál']='Álucard:BAAALgAECgcJDAAAAA==.',
['Ån']='Åntares:BAAALgADCgMJAwAAAA==.',
['Éy']='Éyga:BAAALgAECgEJAwAAAA==.',
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

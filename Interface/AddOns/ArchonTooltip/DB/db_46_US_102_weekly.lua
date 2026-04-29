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

local lookup = {'Hunter-BeastMastery','Paladin-Retribution','Shaman-Restoration','Unknown-Unknown','Warlock-Destruction','Warlock-Demonology','Warrior-Fury','Hunter-Survival','Warrior-Protection','Druid-Restoration','Evoker-Preservation','Mage-Frost','Mage-Fire','DeathKnight-Blood','DeathKnight-Unholy','Monk-Mistweaver','Paladin-Protection','Druid-Balance','Druid-Feral','Priest-Discipline','Priest-Holy','Priest-Shadow','DemonHunter-Devourer','Warrior-Arms','DeathKnight-Frost','Rogue-Outlaw',}
local provider = {region='US',realm='Gallywix',name='US',type='weekly',zone=46,date='2026-04-24',data={Ac='Acelord:BAAALgAECgYJDAAAAA==.',
Ad='Adaar:BAAALgAECgEJAQAAAA==.Adakat:BAAALgADCgEJAQAAAA==.Adanthedark:BAAALgADCgIJAgAAAA==.Adariom:BAAALgADCgUJCAAAAA==.Adrian:BAAALgADCgEJAQAAAA==.Adriannos:BAAALgADCgEJAQAAAA==.',
Ae='Aethir:BAAALgADCgYJBwAAAA==.',
Ag='Agonyy:BAAALgAECgQJBwAAAA==.',
Ah='Aharadack:BAAALgADCgUJCAAAAA==.',
Ak='Akimurad:BAAALgAECgYJBgAAAA==.',
Al='Alanie:BAAALgADCggJCAAAAA==.Ald:BAAALgADCgEJAgAAAA==.Alexextreme:BAAALgAECgUJCAAAAA==.Alikth:BAAALgADCgYJBgAAAA==.Alista:BAAALgAECgMJAgAAAA==.Allandyr:BAABLgAECn8aAAIBAAcJTRK/DgCOAQABAAcJTRK/DgCOAQAAAA==.Alvarao:BAAALgAECgQJBAAAAA==.',
Am='Amano:BAAALgADCgYJBwAAAA==.',
An='Anaxthacia:BAAALgADCgMJAwAAAA==.Andinth:BAAALgADCgQJBAAAAA==.Andrepvp:BAAALgADCggJDwAAAA==.Angelloz:BAABLgAECn8VAAICAAYJLxILHwA0AQACAAYJLxILHwA0AQAAAA==.Annaoh:BAAALgAECgUJDgAAAA==.Annia:BAAALgADCgYJBgAAAA==.Anãodengoso:BAABLgAECn8jAAICAAgJQSYaBgAyAgACAAgJQSYaBgAyAgAAAA==.',
Ap='Apökalÿpsïs:BAAALgAECgEJAQAAAA==.',
Ar='Arator:BAAALgAECgYJBgAAAA==.Ardry:BAAALgADCgYJBgAAAA==.',
As='Ashthon:BAABLgAECn8WAAIBAAcJQRdJNgDVAQABAAcJQRdJNgDVAQAAAA==.',
At='Atomictank:BAAALgADCgcJDAAAAA==.Atonos:BAAALgAECgEJAwAAAA==.',
Au='Auquenai:BAAALgADCgUJBQAAAA==.',
Av='Averagemage:BAAALgAECgEJAQAAAA==.',
Ay='Ayda:BAAALgAECgMJAwAAAA==.',
Ba='Badayaga:BAAALgADCgIJAgAAAA==.Bakunogrind:BAAALgAECgUJBQABLgAECgkJLgADANIhAA==.Balthar:BAAALgAECgYJEQAAAA==.Barcaldas:BAAALgAECgUJBgAAAA==.Barrocø:BAAALgAECgQJBQABLgAECgcJDwAEAAAAAA==.Basara:BAAALgAECgUJBgAAAA==.Batefraco:BAAALgADCgIJAgAAAA==.',
Bb='Bbiel:BAABLgAECn8YAAIFAAUJgxLGBgDMAAAFAAUJgxLGBgDMAAAAAA==.',
Be='Belowlight:BAAALgADCgYJCwAAAA==.Belttazar:BAAALgADCgkJDwAAAA==.Berzan:BAAALgAECgMJAwAAAA==.Beyoond:BAABLgAECn8eAAMGAAgJWxnpRwDzAQAGAAcJahfpRwDzAQAFAAQJtw/pMQDxAAAAAA==.',
Bi='Bielinski:BAAALgAECgMJAwAAAA==.',
Bl='Blackrøse:BAAALgADCgYJBgAAAA==.Blackteriaa:BAAALgAECgUJCQAAAA==.Blankis:BAAALgADCgMJAwAAAA==.Bloodh:BAAALgAECgEJAQAAAA==.Bls:BAAALgADCgMJAwAAAA==.',
Bo='Boijf:BAAALgADCgEJAQAAAA==.Boladomal:BAAALgADCgEJAQAAAA==.Bones:BAAALgAECgEJAQAAAA==.Boruck:BAAALgAECgIJAgAAAA==.',
Br='Braandom:BAAALgAECgQJBAAAAA==.Bradan:BAABLgAECn8ZAAIHAAgJDxSbKgAOAgAHAAgJDxSbKgAOAgAAAA==.Brandomm:BAAALgAECgQJBgAAAA==.Branmir:BAAALgAECgMJAwAAAA==.Bridda:BAAALgADCgUJBgAAAA==.Bruzapaladin:BAAALgADCgUJBQAAAA==.',
Ca='Cabanagé:BAAALgAECgEJAQAAAA==.Cabodecobre:BAAALgAECgUJCwAAAA==.Cainmarko:BAAALgAECgYJEAAAAA==.Caiowisk:BAAALgADCgkJFQAAAA==.Calir:BAAALgADCgYJCwAAAA==.Calçadora:BAABLgAECn8fAAIIAAgJ6SDwAABtAgAIAAgJ6SDwAABtAgAAAA==.Cardrok:BAAALgADCgEJAQAAAA==.Caridosa:BAAALgADCgUJBQAAAA==.Carnius:BAABLgAECn8rAAIJAAgJdxj9DgAZAgAJAAgJdxj9DgAZAgAAAA==.Casuall:BAAALgADCgYJBgAAAA==.Cataclysm:BAAALgAECgMJBAAAAA==.Catalango:BAAALgAECgMJBgAAAA==.Catapó:BAAALgAECgQJBgAAAA==.Catapózão:BAABLgAECn8YAAIKAAgJuhZBLAD+AQAKAAgJuhZBLAD+AQAAAA==.Catü:BAAALgAECgEJAQAAAA==.Cavernus:BAAALgADCgMJAwAAAA==.Caves:BAAALgADCgIJAgAAAA==.Caveston:BAAALgADCgUJCgAAAA==.',
Cb='Cbestabr:BAAALgADCgYJBgAAAA==.',
Ch='Charats:BAAALgADCgYJDQAAAA==.Chaya:BAAALgADCgUJBQAAAA==.Chicknorris:BAAALgADCgUJBQAAAA==.Chifrudaxl:BAAALgAECgMJAwAAAA==.Chrisjks:BAAALgADCgYJCgAAAA==.',
Ci='Cindyn:BAAALgAECgEJAQAAAA==.',
Cl='Clared:BAAALgADCgEJAQAAAA==.Clebeya:BAAALgADCgQJBAAAAA==.Climps:BAAALgAECgMJAgAAAA==.',
Co='Cobyx:BAAALgADCgcJDAAAAA==.Cocaferoz:BAAALgADCgEJAQAAAA==.Colugo:BAAALgADCgIJAgAAAA==.Coriisco:BAAALgADCgIJAgAAAA==.Corollaxei:BAABLgAECn8bAAILAAgJRRZTDwBEAgALAAgJRRZTDwBEAgAAAA==.Cosculluela:BAAALgADCgUJBwAAAA==.',
Cr='Creuzapriest:BAAALgAECgEJAQAAAA==.Cruzade:BAAALgAECgUJCQAAAA==.Cröwllëy:BAAALgAECgUJEAAAAA==.',
Cu='Cubatao:BAAALgAECgUJCwAAAA==.Cucaracha:BAAALgAECgUJCAAAAA==.',
Da='Dahhak:BAAALgAECgEJAQAAAA==.Dakhgagul:BAAALgADCgUJBQAAAA==.Danygatuxa:BAAALgADCgcJEwAAAA==.Dardano:BAAALgADCgcJCgAAAA==.Daree:BAAALgADCgQJBAAAAA==.Darkinmt:BAAALgADCgcJCAAAAA==.Darknesstk:BAAALgAECgEJAgAAAA==.Darksiderptc:BAAALgADCgcJDwAAAA==.',
De='Deadvi:BAAALgAECgcJDwAAAA==.Deadziin:BAAALgADCgMJAwAAAA==.Demetrix:BAAALgADCggJCQAAAA==.Dennyam:BAAALgADCgIJAgAAAA==.Derothey:BAAALgAECgUJEwAAAA==.Deulorem:BAAALgAECgYJDwAAAA==.Devilblade:BAAALgAECgcJEAAAAA==.',
Dk='Dkatraia:BAAALgAECgMJAwAAAA==.',
Dn='Dnghidan:BAACLgAFFH8FAAICAAIJkBTpHwCuAAACAAIJkBTpHwCuAAAuAAQKfxgAAgIACAnYH2YiAKACAAIACAnYH2YiAKACAAAA.Dngtobi:BAAALgADCgkJCQABLgAFFAIJBQACAJAUAA==.',
Do='Dollynhø:BAAALgAECgcJDQAAAA==.Donyed:BAAALgAECgEJAQAAAA==.Dottado:BAAALgADCgcJCgAAAA==.',
Dr='Drackah:BAAALgADCgcJBwAAAA==.Draconían:BAAALgAECgEJAwAAAA==.Dracón:BAAALgADCggJDAAAAA==.Draigo:BAAALgADCgkJCgAAAA==.Dreykar:BAAALgAECgcJDQAAAA==.Drogorn:BAAALgAECgEJAgAAAA==.Druidaezeki:BAAALgADCgYJCwAAAA==.Druidjm:BAAALgADCgMJAwAAAA==.',
Du='Dultrasenegl:BAABLgAECn8WAAIBAAYJAA30ZQA2AQABAAYJAA30ZQA2AQAAAA==.Dunois:BAAALgAECgIJBAAAAA==.',
['Dä']='Dähäkä:BAAALgAECgUJBAAAAA==.',
Ed='Edven:BAABLgAECn8YAAILAAYJGwzIJQBIAQALAAYJGwzIJQBIAQAAAA==.',
El='Eldros:BAAALgADCgkJDwAAAA==.Elgado:BAAALgAECgEJAgAAAA==.Ellanor:BAAALgAECgYJCwAAAA==.Eltão:BAAALgADCgEJAQAAAA==.Elunah:BAAALgADCgQJBAAAAA==.Elyind:BAAALgADCgYJBgAAAA==.',
Em='Emmymm:BAAALgADCgIJAgAAAA==.',
En='Endeavour:BAAALgADCgEJAQAAAA==.Enegadiel:BAAALgAECgMJBgAAAA==.',
Eq='Equidnah:BAAALgADCgIJAgAAAA==.',
Er='Erickya:BAAALgAECgEJAQAAAA==.Ervadocè:BAAALgAECgYJDgAAAA==.Ervelino:BAAALgAECgMJBAAAAA==.',
Es='Estrogosbald:BAAALgADCgYJBgAAAA==.',
Ev='Evely:BAAALgAECgUJCwAAAA==.',
Ex='Exarch:BAAALgAECgYJEQABLgAECggJEwAEAAAAAA==.',
Fa='Faengar:BAAALgAECgUJCAAAAA==.Falconess:BAAALgADCgEJAQAAAA==.',
Fe='Felipebritoo:BAAALgAECgEJAgAAAA==.Ferdruiid:BAAALgADCggJCQAAAA==.Feropudo:BAAALgADCgkJDgAAAA==.Ferrarig:BAAALgAECgEJAQAAAA==.',
Fi='Figy:BAAALgAECgIJAgAAAA==.',
Fl='Flemma:BAABLgAECn8WAAILAAcJWgfuBgAdAQALAAcJWgfuBgAdAQAAAA==.Flores:BAAALgADCgMJBQAAAA==.',
Fo='Foguerosa:BAACLgAFFH8GAAMMAAMJRxCGLwD4AAAMAAMJRxCGLwD4AAANAAEJggDaAAA9AAAuAAQKfxUAAgwABwnRIOgNANoBAAwABwnRIOgNANoBAAAA.Folghunthir:BAAALgADCgQJBAAAAA==.',
Fr='Frankkquini:BAAALgADCgYJEgAAAA==.Friodokrl:BAABLgAECn8cAAMOAAgJchCoGACSAQAOAAgJchCoGACSAQAPAAEJnQGEOQEfAAAAAA==.Fritzgerhart:BAAALgAECgEJAQAAAA==.Frostmhaw:BAAALgADCgUJBQAAAA==.Frostreaper:BAAALgAECgQJBgAAAA==.',
Fu='Fubukiofhell:BAAALgAECgYJCwAAAA==.',
['Fí']='Fí:BAAALgADCggJDgAAAA==.',
Ga='Gabana:BAAALgADCgQJBAAAAA==.Gabdobbuh:BAAALgAECgEJAQAAAA==.Gabn:BAAALgAECgIJAwAAAA==.Gafgar:BAAALgADCgUJCQAAAA==.Gaila:BAAALgADCgYJCAAAAA==.Galduin:BAABLgAECn8bAAIHAAgJ5Q64TwBoAQAHAAgJ5Q64TwBoAQAAAA==.',
Ge='Geduntruppa:BAAALgAECgYJBgAAAA==.Gentioiroh:BAAALgAECgMJAwAAAA==.',
Gh='Ghorderp:BAAALgADCgYJCwAAAA==.Ghoulrozon:BAAALgADCgYJBgAAAA==.',
Gi='Giovannapala:BAAALgAECgUJBQAAAA==.Giripoca:BAAALgAECgQJCQAAAA==.',
Gl='Gladsmonge:BAABLgAECn8bAAIQAAcJlx1oFgARAgAQAAcJlx1oFgARAgAAAA==.Glorcckk:BAAALgADCgEJAQAAAA==.',
Gn='Gnomagga:BAAALgAECgYJCAABLgAECggJHwARABgcAA==.Gnomohabe:BAAALgADCgQJBgAAAA==.',
Go='Goddofwarr:BAAALgADCggJCwAAAA==.Gonb:BAAALgADCgUJBQAAAA==.Goueki:BAAALgAECgcJEAAAAA==.',
Gr='Greenzle:BAAALgADCgMJAwAAAA==.Grillnborst:BAAALgADCgEJAgAAAA==.Grilonp:BAAALgADCgMJAwAAAA==.Gromoff:BAAALgAFFAIJAwAAAA==.Grunmonk:BAAALgADCgEJAQAAAA==.Grømmar:BAAALgADCgMJAwAAAA==.',
Gu='Gudangara:BAAALgADCgYJBgAAAA==.Guztaverdead:BAAALgADCgQJBAAAAA==.',
['Gü']='Güistrong:BAAALgADCgIJAwAAAA==.',
Ha='Haakaí:BAAALgAECgUJCQAAAA==.Hackterin:BAAALgADCgYJBgAAAA==.Hadorah:BAAALgAECgEJAQAAAA==.Haerys:BAAALgADCgYJBgAAAA==.Handhemirr:BAAALgAECgMJBAAAAA==.Harany:BAAALgAECgQJCAAAAA==.Harrypotinho:BAAALgAECgYJEwAAAA==.Haunexd:BAAALgADCgMJAwAAAA==.Havenna:BAAALgAECgUJCAAAAA==.',
He='Headøhunter:BAAALgAECgEJAQAAAA==.Healgate:BAAALgAECgEJAQAAAA==.Hellenah:BAAALgADCggJCAAAAA==.Herika:BAAALgADCgMJAwAAAA==.',
Ho='Hoem:BAAALgAECgMJAwAAAA==.Holand:BAAALgAECgUJBQAAAA==.Holydread:BAAALgAECgIJAgAAAA==.',
Hu='Hulig:BAAALgAECgYJDgAAAA==.',
['Hø']='Høkulani:BAAALgADCgIJAwAAAA==.',
Ik='Ikiam:BAAALgAECgEJAQAAAA==.Ikslawok:BAAALgADCgYJBgAAAA==.',
Il='Ileria:BAAALgAECgYJBwAAAA==.Illarion:BAAALgADCgQJBAAAAA==.Illidanos:BAAALgAECgMJAwAAAA==.Illidris:BAAALgAECgUJBQAAAA==.Illumiinated:BAAALgAECgYJDQAAAA==.',
In='Incarus:BAAALgAECgUJBwAAAA==.Indis:BAAALgADCgQJBgAAAA==.Interst:BAAALgAECgEJAQAAAA==.',
Ir='Irion:BAAALgADCgkJGAAAAA==.',
Is='Iscalio:BAAALgAECgUJCAAAAA==.',
Ja='Jackdawnsong:BAAALgAECgEJAQAAAA==.Jahuun:BAAALgAECgUJBgAAAA==.Jamantoso:BAAALgADCgIJAgAAAA==.',
Je='Jeess:BAAALgADCgMJAwAAAA==.Jefflich:BAAALgAECggJEQAAAA==.',
Jg='Jg:BAAALgAECgUJBwABLgAECgYJDQAEAAAAAA==.',
Jo='Jottapeg:BAAALgADCgcJAwAAAA==.',
Ju='Jubard:BAAALgADCgYJBgAAAA==.Juliamarques:BAAALgAECgMJBAAAAA==.',
['Jü']='Jüllÿe:BAAALgADCgEJAQAAAA==.',
Ka='Kaaellthas:BAAALgAECgIJBAAAAA==.Kacolux:BAAALgADCgEJAQAAAA==.Kaisaargente:BAAALgAECgEJAQAAAA==.Kakarotho:BAAALgAECgMJAwAAAA==.Kaldonios:BAAALgADCgcJEgAAAA==.Kamasutram:BAAALgADCgUJBQAAAA==.Kanadriel:BAAALgAECgEJAQAAAA==.Kanarinho:BAABLgAECn8bAAIKAAYJlBWCUgBcAQAKAAYJlBWCUgBcAQAAAA==.Kazandra:BAAALgADCgYJBgAAAA==.',
Ke='Kendars:BAABLgAECn8VAAQSAAYJ0hKLSAAKAQASAAUJJhKLSAAKAQAKAAUJFQ+6dgDzAAATAAEJgBXuDABGAAAAAA==.Ket:BAAALgADCgMJAwAAAA==.',
Kh='Khanmir:BAAALgAECgMJBgAAAA==.Khild:BAAALgAECgYJDQAAAA==.',
Ki='Killerdek:BAAALgADCgMJAwAAAA==.Killshoty:BAAALgAECgEJAQAAAA==.',
Kl='Kluzlocak:BAABLgAECn8VAAIUAAYJIQehMQAUAQAUAAYJIQehMQAUAQAAAA==.',
Ko='Korav:BAAALgAECgMJAwAAAA==.Koruno:BAAALgADCgYJBgAAAA==.',
Kr='Krozhul:BAAALgAECgQJBgAAAA==.',
Ku='Kurnous:BAAALgAECgEJAQAAAA==.Kutirenzo:BAAALgADCgUJBwAAAA==.',
La='Lafiel:BAAALgAECgcJCwAAAA==.Lamelo:BAAALgADCgYJBgAAAA==.Lanmo:BAAALgADCgUJCAAAAA==.Largatixazul:BAAALgADCgUJBgAAAA==.Laurea:BAAALgADCgYJCwABLgAECgQJCQAEAAAAAA==.',
Le='Leebron:BAAALgADCgUJBgAAAA==.Lefthalas:BAAALgAECgUJCgAAAA==.Leitchero:BAAALgADCgYJBgAAAA==.Lemaz:BAAALgAECgEJAQAAAA==.Lesco:BAAALgADCgMJAwAAAA==.',
Li='Lianele:BAAALgADCgkJDAAAAA==.Liaras:BAABLgAECn8XAAMVAAYJwBDsPgA+AQAVAAYJwBDsPgA+AQAWAAIJzAAzaQAmAAAAAA==.Licelaa:BAAALgADCgcJBwAAAA==.Lichtbaum:BAAALgAECgcJCwAAAA==.Lightsertrop:BAAALgADCgEJAQAAAA==.Liifecomm:BAABLgAECn8oAAIVAAgJxh1bDQCCAgAVAAgJxh1bDQCCAgAAAA==.Liike:BAAALgADCgMJAwAAAA==.Linestra:BAAALgADCgUJBQAAAA==.Liniak:BAAALgAECgUJBgAAAA==.Lisong:BAAALgADCgUJBQAAAA==.Littlepurple:BAACLgAFFH8JAAIXAAMJzxJsGwD2AAAXAAMJzxJsGwD2AAAuAAQKfyUAAhcACQl0HJsYAMICABcACQl0HJsYAMICAAAA.',
Lo='Longhai:BAAALgADCgUJCAAAAA==.Lookatmylock:BAABLgAECn8WAAMFAAYJfhYZGACKAQAFAAYJfhYZGACKAQAGAAIJQQmIBQFRAAAAAA==.Lordpain:BAAALgAECgMJBgAAAA==.Lortherti:BAAALgADCgUJBgAAAA==.Lorwin:BAAALgAECgYJCQAAAA==.Louisenacioo:BAAALgAECgMJAwAAAA==.Loátrak:BAAALgADCgMJAwAAAA==.',
Lu='Lucyx:BAAALgAECgEJAQAAAA==.Luidar:BAAALgAECgQJBAAAAA==.Lukaslions:BAAALgAECgQJBgAAAA==.Lunarie:BAAALgAECgYJBwAAAA==.Luphoe:BAABLgAECn8WAAIKAAcJqxzHJwAWAgAKAAcJqxzHJwAWAgAAAA==.',
['Lé']='Léio:BAAALgADCgcJCAAAAA==.Léora:BAAALgADCgIJAgAAAA==.',
['Lø']='Lørdsith:BAAALgAECgYJCAABLgAECgcJBAAEAAAAAA==.',
['Lÿ']='Lÿcäns:BAAALgADCgMJAwAAAA==.',
Ma='Madagalux:BAAALgADCgYJCgAAAA==.Madjack:BAAALgAECgMJAwAAAA==.Madushi:BAAALgADCgMJAwAAAA==.Magatiun:BAAALgADCgMJBAAAAA==.Magogunt:BAAALgAECgYJDwAAAA==.Maguul:BAAALgAECgQJBwAAAA==.Magzifeh:BAEALgAFFAEJAgAAAA==.Malandrvs:BAAALgAECgUJBgAAAA==.Maljamim:BAAALgADCgIJAgAAAA==.Mamuthwar:BAABLgAECn8ZAAMHAAcJnRgZNgDQAQAHAAcJnRgZNgDQAQAYAAEJMQ7RQQA1AAAAAA==.Mandingavudu:BAAALgAECgEJAQABLgAECgMJAwAEAAAAAA==.Manei:BAAALgAECgMJAwAAAA==.Manopaladino:BAAALgADCgYJBgAAAA==.Manowlo:BAAALgAECgMJAwAAAA==.Marmelo:BAAALgADCgQJBAAAAA==.Marretasanta:BAABLgAECn8XAAICAAYJ9BBWmABNAQACAAYJ9BBWmABNAQAAAA==.Marù:BAAALgAECgMJAwAAAA==.Marúh:BAACLgAFFH8HAAIDAAMJFBBoBwDeAAADAAMJFBBoBwDeAAAuAAQKfx8AAgMACAm/IsQFABYDAAMACAm/IsQFABYDAAAA.Maxmorf:BAAALgADCgQJBAAAAA==.Mayarabr:BAAALgADCgUJBwAAAA==.Mazeratos:BAAALgAECgMJAwAAAA==.',
Mc='Mcorelhao:BAAALgADCgEJAQAAAA==.',
Me='Megrezz:BAAALgAECgEJAQAAAA==.Mehiel:BAAALgAECgEJAQAAAA==.Mekihlvshtak:BAAALgADCgYJBgAAAA==.Mendingu:BAAALgAECgcJDwAAAA==.Merumim:BAAALgAECgQJAwAAAA==.Metalgirl:BAAALgADCgYJCwAAAA==.',
Mi='Midrão:BAAALgADCgEJAQAAAA==.Mindlocker:BAAALgAECgQJCgAAAA==.Minorus:BAAALgAECgcJDAAAAA==.',
Mo='Modogz:BAAALgADCgYJBgAAAA==.Momongadk:BAAALgADCgcJBwAAAA==.Monkeydking:BAAALgADCgUJBQAAAA==.Mordekais:BAAALgADCggJGAAAAA==.Morganne:BAAALgAECgEJAQAAAA==.Moriyama:BAAALgAECgYJEAAAAA==.Morphisz:BAAALgAECgIJAgABLgAECgMJAwAEAAAAAA==.Morphiszs:BAAALgAECgMJAwAAAA==.Morphizs:BAAALgADCgMJAwABLgAECgMJAwAEAAAAAA==.Mortesan:BAAALgADCgEJAQABLgADCggJCAAEAAAAAA==.',
Mp='Mpastor:BAAALgADCgUJBQAAAA==.',
Mu='Muca:BAAALgADCgEJAQAAAA==.Muho:BAAALgADCgEJAQAAAA==.Mukonha:BAAALgAECgUJBgAAAA==.',
['Mã']='Mãoleves:BAAALgADCgEJAQAAAA==.',
['Mï']='Mïnthara:BAAALgAECgcJDQAAAA==.',
Na='Naeryndam:BAAALgADCgEJAQAAAA==.Nayanna:BAAALgADCgcJBwAAAA==.',
Ne='Negblack:BAAALgAECgIJAgAAAA==.Neggi:BAAALgAECgUJBwAAAA==.Nemesysy:BAAALgAECgMJAwAAAA==.Nerphien:BAAALgADCgUJBQAAAA==.Nesktpally:BAAALgAECgcJCAAAAA==.Netbrood:BAAALgADCgUJBgABLgAECgUJBwAEAAAAAA==.Netbrother:BAAALgAECgUJBwAAAA==.Nethdorai:BAAALgADCgQJBAAAAA==.Netherbane:BAAALgAECgYJCwAAAA==.Nezuko:BAAALgADCgcJEQABLgAECgYJEwAEAAAAAA==.',
Ni='Nightmære:BAAALgAECgMJAwAAAA==.Nikelok:BAAALgAECgMJAwAAAA==.Ninfador:BAABLgAECn8ZAAIUAAYJhBWkJgBgAQAUAAYJhBWkJgBgAQAAAA==.Ninpus:BAAALgAECgIJAgAAAA==.',
No='Noobmasteer:BAAALgADCgIJAgAAAA==.Nooneknow:BAABLgAECn8YAAIPAAYJrh7NFQBiAQAPAAYJrh7NFQBiAQAAAA==.Nosrede:BAAALgAECgEJAQAAAA==.Notz:BAAALgADCgMJBAAAAA==.',
Ny='Nyde:BAAALgADCgEJAQAAAA==.',
Oa='Oakshlar:BAAALgAECgQJCgAAAA==.',
Oc='Ocelaris:BAAALgADCgMJBAAAAA==.',
Or='Oryana:BAAALgADCgcJIAAAAA==.Oríon:BAAALgADCgIJAgAAAA==.',
Ot='Otton:BAAALgAECgYJCwAAAA==.',
Ov='Overnigth:BAAALgADCgIJAgAAAA==.Overwalker:BAAALgADCgIJAgAAAA==.Ovosemdente:BAAALgADCgEJAQAAAA==.',
Ow='Owllskull:BAAALgADCgcJEQABLgAECgEJAgAEAAAAAA==.',
Pa='Pacoka:BAAALgADCgQJBQAAAA==.Paidesanto:BAAALgAECgYJEAAAAA==.Paladinokun:BAAALgADCggJCAAAAA==.Palanis:BAAALgAECgcJBwAAAA==.Palazarta:BAAALgAECgMJAgAAAA==.Panquecudo:BAAALgADCgIJAgAAAA==.',
Pd='Pdois:BAAALgADCgMJAwAAAA==.',
Pe='Pesscador:BAAALgAECgMJAwAAAA==.',
Pi='Piriguetee:BAAALgADCgEJAQAAAA==.Pirro:BAAALgADCgYJDQAAAA==.',
Pk='Pkzimn:BAAALgADCgUJBQAAAA==.',
Pl='Playsson:BAAALgAECgYJDAAAAA==.Plottwist:BAAALgADCgcJDwABLgAECggJFQAPAGcTAA==.',
Po='Pogonus:BAAALgADCgIJAgAAAA==.',
Pr='Pravios:BAAALgAECgEJAgAAAA==.Priestkill:BAAALgADCgMJAgAAAA==.',
Pt='Pterodactilo:BAAALgAECgYJAQAAAA==.',
Pu='Puherito:BAAALgAECgQJBAAAAA==.Purgas:BAAALgAECgMJCQAAAA==.',
Qu='Quinthalam:BAAALgADCgMJAwAAAA==.',
Ra='Rafazinho:BAAALgADCgQJBAAAAA==.Ramyna:BAAALgAECgMJAwAAAA==.Raphaeldh:BAAALgAECgEJAgAAAA==.Raphahunterr:BAAALgADCgEJAQAAAA==.Raposa:BAAALgADCgEJAQAAAA==.Raposinha:BAAALgADCgMJAwAAAA==.Rarkway:BAAALgADCgkJCQAAAA==.Rayanne:BAAALgADCgUJBQAAAA==.',
Re='Reckfull:BAAALgAECgYJBgAAAA==.Regininha:BAAALgAECgEJAQAAAA==.Reloumifrend:BAAALgAECgEJAQAAAA==.Rendros:BAAALgADCgUJBQAAAA==.',
Rh='Rhaegaar:BAAALgAECgQJCgAAAA==.Rhodinius:BAAALgAECgMJCAAAAA==.',
Ro='Rochera:BAAALgAECgEJAQAAAA==.',
Ru='Ruhtarr:BAAALgADCgEJAQAAAA==.',
Sa='Saek:BAAALgAECgYJDAAAAA==.Sanderclone:BAAALgADCgQJBAAAAA==.Santiss:BAAALgAECgQJCQAAAA==.Santorini:BAAALgADCgEJAQAAAA==.Saphis:BAAALgADCgEJAQAAAA==.Sardado:BAAALgAECgEJAQAAAA==.Sardron:BAAALgADCgMJAwAAAA==.',
Sc='Scanorr:BAAALgAECgEJAQAAAA==.Scheffers:BAAALgAECgEJAQAAAA==.',
Se='Selah:BAAALgADCgMJBQAAAA==.Sephora:BAAALgADCgcJDAABLgAECgYJFwAVAMAQAA==.',
Sh='Shadowlock:BAAALgADCgIJAQABLgAECgYJDAAEAAAAAA==.Shadowmornac:BAAALgADCgEJAQAAAA==.Shamanica:BAAALgAECgEJAQAAAA==.Shamateus:BAAALgADCggJDAAAAA==.Shasuna:BAAALgADCgIJAgAAAA==.Shaunnun:BAAALgADCgEJAQAAAA==.Shinnók:BAAALgADCgUJBgAAAA==.Shiíro:BAAALgAECgEJAgABLgAECggJFQACAOUXAA==.Shynato:BAAALgADCgEJAQAAAA==.Shynock:BAAALgADCgEJAQAAAA==.Shãka:BAAALgADCgMJAwAAAA==.',
Si='Siladriel:BAAALgADCgMJAwAAAA==.Sirgonzo:BAAALgAECgMJBgAAAA==.',
Sk='Skullexus:BAAALgAECgMJBAAAAA==.Skunkbr:BAAALgADCgEJAQAAAA==.',
Sl='Sleepychety:BAAALgAECgUJBgAAAA==.Slowsmoke:BAAALgADCgEJAQAAAA==.',
Sn='Snatzz:BAAALgADCgMJAgAAAA==.',
So='Soggoth:BAAALgADCgkJCQAAAA==.Solk:BAAALgADCgQJBAAAAA==.Sontarfury:BAAALgAECgEJAQAAAA==.Sorim:BAAALgAECgYJCwAAAA==.Soryan:BAAALgAECgYJEgAAAA==.Soulassassin:BAAALgADCgIJAwAAAA==.Soulhell:BAAALgAECgYJDwAAAA==.',
Sp='Spartanlofs:BAAALgADCgcJEQAAAA==.Spawndeath:BAAALgADCgEJAQAAAA==.',
Ss='Ssushii:BAAALgAECgEJAQAAAA==.',
St='Stigmata:BAAALgADCgcJCAAAAA==.Stixmixdk:BAAALgAFFAQJAgAAAA==.Straz:BAAALgADCgQJBAAAAA==.Strongman:BAAALgAECgYJBgAAAA==.Stx:BAAALgADCgUJBQAAAA==.',
Su='Subsdk:BAABLgAECn8VAAIPAAgJkBMFDQC3AQAPAAgJkBMFDQC3AQAAAA==.Sunwalkers:BAAALgAECgUJBgAAAA==.',
Sy='Systeni:BAAALgADCgkJDQAAAA==.',
['Sø']='Søøssø:BAAALgADCgQJBAAAAA==.',
Ta='Taha:BAAALgAECgQJAgAAAA==.Taillys:BAAALgADCgMJBAAAAA==.Tainy:BAAALgADCgMJAwAAAA==.Takenaka:BAAALgADCgMJAwAAAA==.Tarez:BAAALgADCgkJCgAAAA==.Tarfonir:BAAALgAECgIJAwAAAA==.Tavalira:BAAALgADCgYJBgAAAA==.',
Te='Tealen:BAAALgADCgYJBgAAAA==.Ted:BAAALgAECgcJDAAAAA==.Teiseken:BAAALgAECgcJBwAAAA==.Teratsemknk:BAAALgAECgMJAwAAAA==.',
Th='Tharnforge:BAAALgAECgEJAQAAAA==.Thejokker:BAAALgAFFAIJAgAAAA==.Themooster:BAAALgAECgIJAgAAAA==.Thepickles:BAAALgADCgkJEAAAAA==.Thepunk:BAAALgAECgMJBAAAAA==.Thintor:BAAALgADCgEJAQAAAA==.Thormento:BAAALgAECgYJEAAAAA==.',
Ti='Tigerblood:BAAALgADCgUJBQAAAA==.Tipooreeii:BAAALgADCgEJAQAAAA==.Titanicos:BAAALgADCgMJAwAAAA==.',
Tj='Tjhunter:BAABLgAECn8VAAIBAAgJkAjXFgBFAQABAAgJkAjXFgBFAQAAAA==.',
To='Tobbiy:BAAALgAECgMJAwAAAA==.',
Tr='Tranh:BAAALgADCgkJFQAAAA==.Traxer:BAAALgADCgQJBAAAAA==.Tripäsecä:BAAALgAECgIJAwAAAA==.Troladora:BAAALgAECgYJCgAAAA==.',
Ty='Tyrandrisa:BAAALgADCgIJAQAAAA==.',
Um='Ummetrodefio:BAAALgADCgEJAQAAAA==.',
Ut='Uthred:BAABLgAECn8UAAMZAAYJoARtDADrAAAZAAYJoARtDADrAAAPAAIJfwG0IgExAAAAAA==.',
Va='Vaelryn:BAAALgAECgUJBgAAAA==.Valdemmon:BAAALgADCgcJBwAAAA==.Valororo:BAAALgAECgMJAwAAAA==.Vandlesh:BAAALgAECgIJAwAAAA==.Varka:BAAALgADCgYJGQAAAA==.',
Ve='Velkharun:BAAALgAECgQJCAABLgAECgUJCQAEAAAAAA==.Venatrin:BAAALgADCgkJCQAAAA==.Vexxv:BAAALgAFFAEJAQAAAA==.Vexxz:BAAALgAECgYJBwAAAA==.',
Vi='Viquue:BAAALgADCgYJBgAAAA==.Vivisoft:BAAALgADCgMJAwAAAA==.',
Vo='Voidrb:BAAALgADCgcJBwABLgAECgcJDwAEAAAAAA==.Vovogamer:BAAALgADCgEJAQAAAA==.',
['Vò']='Vòxs:BAABLgAECn8rAAMYAAgJsyG4AwDEAgAYAAcJziG4AwDEAgAHAAYJyR2HLgD3AQAAAA==.',
Wa='Walkery:BAAALgADCgIJAgAAAA==.Wattari:BAABLgAECn8VAAIJAAYJFwMfNQCdAAAJAAYJFwMfNQCdAAAAAA==.',
Wh='Whiteep:BAAALgADCgYJCAAAAA==.Whiteseraph:BAAALgADCgEJAQAAAA==.Whynchester:BAAALgADCgEJAQAAAA==.',
Wi='Windsailor:BAAALgADCgIJAgAAAA==.Wiserys:BAAALgAECgYJEAAAAA==.',
Wm='Wmarcão:BAAALgAECgUJCAAAAA==.',
Wo='Wolfiez:BAAALgAECgUJDAAAAA==.Wopz:BAAALgADCgUJBQAAAA==.',
Wq='Wqz:BAAALgAECgcJDQAAAA==.',
Wu='Wunamuno:BAAALgADCgkJCQAAAA==.',
Xa='Xallatath:BAAALgADCgUJBQAAAA==.Xamãna:BAAALgAECgMJBQAAAA==.',
Xe='Xevron:BAAALgAECgQJBAAAAA==.Xexnew:BAAALgAECgYJEgAAAA==.',
Xi='Xinthorak:BAAALgADCgEJAgAAAA==.Xinzhou:BAAALgADCgQJCAAAAA==.Xiseth:BAAALgAECgEJAQAAAA==.Xixíca:BAAALgADCgQJBAAAAA==.',
Xm='Xmari:BAAALgADCgMJBgAAAA==.',
Xu='Xulaman:BAAALgAECgYJDAAAAA==.Xungodz:BAAALgADCgQJBAAAAA==.Xunxu:BAAALgAECgYJEQAAAA==.',
Xy='Xynrath:BAAALgADCgMJAwAAAA==.',
Xz='Xzxzg:BAAALgAFFAIJAgABLgAFFAUJEQAaAC8gAA==.',
['Xÿ']='Xÿon:BAAALgAECgEJAQAAAA==.',
Ya='Yannadcg:BAABLgAECn8UAAIVAAgJPgSEQQAyAQAVAAgJPgSEQQAyAQAAAA==.',
Yo='Youdie:BAABLgAECn8VAAIWAAYJnBXnKgCEAQAWAAYJnBXnKgCEAQAAAA==.',
Yu='Yulthuan:BAAALgADCgMJAwAAAA==.',
Yv='Yvernus:BAAALgAECgQJBAAAAA==.',
Za='Zaaraki:BAABLgAECn8VAAMPAAgJZxPRVQDwAQAPAAgJIRLRVQDwAQAOAAYJ6w+BKwDjAAAAAA==.Zarolho:BAAALgAECgUJEAAAAA==.',
Ze='Zenitsua:BAAALgAECgEJAQAAAA==.Zephiir:BAAALgAECgQJCQAAAA==.',
Zo='Zornak:BAAALgADCgUJBQAAAA==.',
Zz='Zzx:BAAALgADCgcJBwAAAA==.',
['Zé']='Zécasete:BAAALgADCgUJBwAAAA==.',
['Ál']='Álucard:BAAALgADCgcJDQAAAA==.',
['Ån']='Åntares:BAAALgADCgMJAwAAAA==.',
['Éy']='Éyga:BAAALgAECgEJAgAAAA==.',
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

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

local lookup = {'Hunter-BeastMastery','Paladin-Retribution','Shaman-Restoration','Shaman-Elemental','Shaman-Enhancement','Unknown-Unknown','Warlock-Destruction','Warlock-Demonology','Warrior-Fury','Hunter-Survival','Warrior-Protection','Druid-Restoration','Evoker-Preservation','DeathKnight-Unholy','Priest-Holy','DemonHunter-Devourer','Mage-Frost','Druid-Balance','Mage-Fire','DeathKnight-Blood','Monk-Mistweaver','Hunter-Marksmanship','Druid-Feral','Priest-Discipline','Priest-Shadow','Warrior-Arms','DeathKnight-Frost','Warlock-Affliction','Rogue-Outlaw',}
local provider = {region='US',realm='Gallywix',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abortheira:BAAALgADCgUJBQAAAA==.',
Ac='Acelord:BAAALgAECgYJDgAAAA==.',
Ad='Adaar:BAAALgAECgEJAQAAAA==.Adakat:BAAALgADCgEJAQAAAA==.Adanthedark:BAAALgADCgIJAgAAAA==.Adariom:BAAALgADCgUJCAAAAA==.Adrian:BAAALgADCgEJAQAAAA==.Adriannos:BAAALgADCgEJAQAAAA==.',
Ae='Aethir:BAAALgADCgYJBwAAAA==.',
Ag='Agonyy:BAAALgAECgQJBwAAAA==.',
Ah='Aharadack:BAAALgADCgUJCwAAAA==.',
Ak='Akawaka:BAAALgAECgEJAQAAAA==.Akiji:BAAALgADCgEJAQAAAA==.Akimurad:BAAALgAECgYJBgAAAA==.',
Al='Alanie:BAAALgADCggJCAAAAA==.Ald:BAAALgADCgEJAgAAAA==.Aldebaraum:BAAALgAECgEJAQAAAA==.Alexextreme:BAAALgAECgcJCwAAAA==.Alikth:BAAALgADCgYJBgAAAA==.Alista:BAAALgAECgMJAgAAAA==.Allandyr:BAABLgAECn8hAAIBAAcJRxTFLwBSAQABAAcJRxTFLwBSAQAAAA==.Alvarao:BAAALgAECgQJBAAAAA==.',
Am='Amandadark:BAAALgAECgEJAQAAAA==.Amano:BAAALgADCgYJDAAAAA==.',
An='Anaxthacia:BAAALgADCgMJAwAAAA==.Andinth:BAAALgADCgQJBAAAAA==.Andrepvp:BAAALgADCggJDwAAAA==.Angelloz:BAABLgAECn8cAAICAAcJEhDPPgBNAQACAAcJEhDPPgBNAQAAAA==.Annaoh:BAABLgAECn8VAAICAAcJiR2vGgDqAQACAAcJiR2vGgDqAQAAAA==.Annia:BAAALgADCgYJBwAAAA==.Anãodengoso:BAABLgAECn8jAAICAAgJQSZgFQDpAgACAAgJQSZgFQDpAgAAAA==.',
Ap='Apökalÿpsïs:BAAALgAECgUJCwAAAA==.',
Ar='Arator:BAAALgAECgYJBgAAAA==.Ardry:BAAALgADCgYJBgAAAA==.',
As='Ashthon:BAABLgAECn8YAAIBAAcJQRdCNgDVAQABAAcJQRdCNgDVAQAAAA==.Asmitta:BAAALgADCgQJBAAAAA==.',
At='Atomictank:BAAALgAECgUJCAAAAA==.Atonos:BAAALgAECgEJAwAAAA==.',
Au='Auquenai:BAAALgADCgUJBQAAAA==.Aurielis:BAAALgAECgEJAQAAAA==.',
Av='Averagemage:BAAALgAECgEJAQAAAA==.',
Ay='Ayda:BAAALgAECgQJBAAAAA==.',
Az='Azadium:BAAALgAECgEJAQAAAA==.Azul:BAAALgAECgMJAwAAAA==.',
Ba='Badayaga:BAAALgADCgIJAgAAAA==.Bakunogrind:BAAALgAECgUJBQABLgAFFAQJBwADAEMeAA==.Balthar:BAABLgAECn8YAAQEAAcJvg9vHgAkAQAEAAcJJw9vHgAkAQAFAAQJxRBrHQD1AAADAAMJOwjChQB9AAAAAA==.Barcaldas:BAAALgAECgUJBgAAAA==.Barrocø:BAAALgAECgQJBQABLgAECgcJDwAGAAAAAA==.Basara:BAAALgAECgYJCAAAAA==.Batefraco:BAAALgADCgIJAgAAAA==.',
Bb='Bbiel:BAABLgAECn8ZAAIHAAUJxxNFCgAAAQAHAAUJxxNFCgAAAQAAAA==.',
Be='Beherit:BAAALgADCgIJAgAAAA==.Beliall:BAAALgADCgEJAQAAAA==.Belowlight:BAAALgADCgYJCwAAAA==.Belttazar:BAAALgADCgkJDwAAAA==.Berzan:BAAALgAECgMJBgAAAA==.Beyoond:BAABLgAECn8mAAMIAAkJaBhNHgC/AQAIAAgJ8xdNHgC/AQAHAAQJtw/oMQDxAAAAAA==.',
Bi='Bielinski:BAAALgAECgQJBAAAAA==.',
Bl='Blackrøse:BAAALgADCgYJBgAAAA==.Blackteriaa:BAAALgAECgUJDgAAAA==.Blankis:BAAALgADCgYJCQAAAA==.Blizther:BAAALgADCgEJAQAAAA==.Bloodh:BAAALgAECgEJAgAAAA==.Bls:BAAALgADCgMJAwAAAA==.',
Bo='Boijf:BAAALgADCgEJAQAAAA==.Boladomal:BAAALgAECgMJAwAAAA==.Bones:BAAALgAECgEJAQAAAA==.Boromy:BAAALgAECgEJAQAAAA==.Boruck:BAAALgAECgIJAwAAAA==.',
Br='Braandom:BAAALgAECgUJBQAAAA==.Bradan:BAABLgAECn8dAAIJAAgJUhWeKgAOAgAJAAgJUhWeKgAOAgAAAA==.Brandomm:BAAALgAECgQJBwAAAA==.Branmir:BAAALgAECgMJBQAAAA==.Bridda:BAAALgAECgQJBQAAAA==.Bruzapaladin:BAAALgADCgUJBQAAAA==.',
['Bí']='Bíbs:BAAALgAECgYJCQAAAA==.',
Ca='Cabanagé:BAAALgAECgUJBQAAAA==.Cabodecobre:BAAALgAECgUJCwAAAA==.Cainmarko:BAAALgAECgYJEAAAAA==.Caiowisk:BAAALgAECgYJBwAAAA==.Calir:BAAALgADCgYJFgAAAA==.Calçadora:BAABLgAECn8jAAIKAAgJViHoAgB1AgAKAAgJViHoAgB1AgAAAA==.Cardrok:BAAALgADCgEJAQAAAA==.Caridosa:BAAALgADCgUJBQAAAA==.Carnius:BAABLgAECn80AAILAAgJYRumBwDEAQALAAgJYRumBwDEAQAAAA==.Casuall:BAAALgADCgYJBgAAAA==.Cataclysm:BAAALgAECgMJBAAAAA==.Catalango:BAAALgAECgMJBgAAAA==.Catapó:BAAALgAECgQJBgAAAA==.Catapózão:BAABLgAECn8bAAIMAAgJzBpCLAD+AQAMAAgJzBpCLAD+AQAAAA==.Catü:BAAALgAECgEJAQAAAA==.Cavernus:BAAALgADCgMJAwAAAA==.Caves:BAAALgADCgIJAgAAAA==.Caveston:BAAALgADCgUJCgAAAA==.',
Cb='Cbestabr:BAAALgADCgYJBgAAAA==.',
Ch='Charats:BAAALgADCgYJDQAAAA==.Charterine:BAAALgADCgYJBgAAAA==.Chaya:BAAALgADCgUJBQAAAA==.Chicknorris:BAAALgADCgUJBQAAAA==.Chifrudaxl:BAAALgAECgMJAwAAAA==.Chrisjks:BAAALgADCgYJCgAAAA==.',
Ci='Cindyn:BAAALgAECgEJAQAAAA==.',
Cl='Clared:BAAALgADCgEJAQAAAA==.Clebeya:BAAALgADCgQJBAAAAA==.Climps:BAAALgAECgUJBgAAAA==.',
Co='Cobyx:BAAALgADCgcJDAAAAA==.Cocaferoz:BAAALgADCgEJAQAAAA==.Coffeeaddict:BAAALgADCgMJAwAAAA==.Colugo:BAAALgADCgIJAgAAAA==.Coriisco:BAAALgADCgIJAgAAAA==.Corollaxei:BAABLgAECn8iAAINAAgJSBjLBgDVAQANAAgJSBjLBgDVAQAAAA==.Cosculluela:BAAALgADCgUJBwAAAA==.',
Cr='Creuzapriest:BAAALgAECgEJAQAAAA==.Cruzade:BAAALgAECgUJCgAAAA==.Cröwllëy:BAABLgAECn8XAAIOAAYJPhR/QwAzAQAOAAYJPhR/QwAzAQAAAA==.',
Cu='Cubatao:BAAALgAECgUJDgAAAA==.Cucaracha:BAAALgAECgUJCQAAAA==.',
Da='Dahhak:BAAALgAECgEJAgAAAA==.Dakhgagul:BAAALgADCgUJBQAAAA==.Dakshayani:BAAALgADCgMJAwAAAA==.Danielbrz:BAAALgAECgIJAgAAAA==.Danygatuxa:BAAALgADCgcJEwAAAA==.Dardano:BAAALgADCgcJCgAAAA==.Daree:BAAALgAECgEJAQAAAA==.Darkinmt:BAAALgADCgcJCAAAAA==.Darknesstk:BAAALgAECgQJCAAAAA==.Darksiderptc:BAAALgADCgcJDwAAAA==.',
De='Deadvi:BAAALgAECgcJDwAAAA==.Deadziin:BAAALgAECgMJAwAAAA==.Demetrix:BAAALgADCgkJCgAAAA==.Dennyam:BAAALgAECgUJBgAAAA==.Derothey:BAAALgAECgUJEwAAAA==.Deulorem:BAABLgAECn8XAAIPAAgJ4BFuDgC8AQAPAAgJ4BFuDgC8AQAAAA==.Devilblade:BAABLgAECn8RAAIQAAgJSQn0XgCLAAAQAAgJSQn0XgCLAAAAAA==.',
Dk='Dkatraia:BAAALgAECgMJAwAAAA==.',
Dn='Dnghidan:BAACLgAFFH8GAAICAAMJDxwJGQAVAQACAAMJDxwJGQAVAQAuAAQKfxYAAgIACAmoH1NUAOUBAAIACAmoH1NUAOUBAAAA.Dngtobi:BAAALgAECgEJAQABLgAFFAMJBgACAA8cAA==.',
Do='Dollynhø:BAAALgAECgcJDQAAAA==.Donyed:BAAALgAECgEJAQAAAA==.Dottado:BAAALgADCgcJCgAAAA==.',
Dr='Drackah:BAAALgADCgcJBwAAAA==.Draconían:BAAALgAECgEJBAAAAA==.Dracón:BAAALgADCgkJDwAAAA==.Draigo:BAAALgAECgEJAQAAAA==.Dreykar:BAABLgAECn8VAAIQAAgJsw7cHwB0AQAQAAgJsw7cHwB0AQAAAA==.Drogorn:BAAALgAECgQJBwAAAA==.Druidaezeki:BAAALgADCgYJCwAAAA==.Druidjm:BAAALgADCgMJAwAAAA==.',
Du='Dultrasenegl:BAABLgAECn8WAAIBAAYJAA3vZQA2AQABAAYJAA3vZQA2AQAAAA==.Dunois:BAAALgAECgIJBQAAAA==.',
['Dä']='Dähäkä:BAAALgAECgYJBgAAAA==.',
Ed='Edven:BAACLgAFFH8GAAINAAIJZQH+FABsAAANAAIJZQH+FABsAAAuAAQKfx0AAg0ABgkxDMQlAEgBAA0ABgkxDMQlAEgBAAAA.',
El='Eldros:BAAALgAECgIJAgAAAA==.Elgado:BAAALgAECgEJAwAAAA==.Ellanor:BAABLgAECn8UAAIRAAcJSRTTQQBpAQARAAcJSRTTQQBpAQAAAA==.Eltão:BAAALgADCgEJAQAAAA==.Elunah:BAAALgADCgQJBAAAAA==.Elwindor:BAAALgADCgYJBAAAAA==.Elyind:BAAALgADCgYJBgAAAA==.',
Em='Emmymm:BAAALgADCgIJAgAAAA==.',
En='Endeavour:BAAALgADCgEJAQAAAA==.Enegadiel:BAAALgAECgUJDAAAAA==.Enoia:BAAALgADCgUJBQAAAA==.',
Eq='Equidnah:BAAALgADCgIJAgAAAA==.',
Er='Erickya:BAAALgAECgEJAgAAAA==.Ervadocè:BAABLgAECn8VAAISAAYJQxQ+GQAzAQASAAYJQxQ+GQAzAQAAAA==.Ervelino:BAAALgAECgMJBAAAAA==.',
Es='Estrogosbald:BAAALgADCgYJCAAAAA==.',
Ev='Evely:BAAALgAECgYJDQAAAA==.',
Ex='Exarch:BAABLgAECn8WAAIKAAcJXxO/DwDHAQAKAAcJXxO/DwDHAQAAAA==.',
Fa='Faengar:BAAALgAECgUJCAAAAA==.Falconess:BAAALgADCgEJAQAAAA==.',
Fe='Felipebritoo:BAAALgAECgIJBAAAAA==.Ferdruiid:BAAALgADCgkJEAAAAA==.Feropudo:BAAALgADCgkJDgAAAA==.Ferrarig:BAAALgAECgEJAQAAAA==.',
Fi='Figy:BAAALgAECgQJBAAAAA==.',
Fl='Flemma:BAABLgAECn8XAAINAAgJIQdfDQAsAQANAAgJIQdfDQAsAQAAAA==.Flexer:BAAALgAECgEJAQAAAA==.Flores:BAAALgADCgMJBQAAAA==.Floridastyle:BAAALgAECgQJCwAAAA==.',
Fo='Foguerosa:BAACLgAFFH8JAAMRAAMJpBx0KwAdAQARAAMJpBx0KwAdAQATAAEJggDsAQA7AAAuAAQKfxYAAhEACAlgIRIVADMCABEACAlgIRIVADMCAAAA.Folghunthir:BAAALgADCgQJBAAAAA==.',
Fr='Frankkquini:BAAALgADCgYJEgAAAA==.Friodokrl:BAABLgAECn8kAAMUAAgJXhgpBwCuAQAUAAgJXhgpBwCuAQAOAAEJnQGVOQEfAAAAAA==.Fritzgerhart:BAAALgAECgEJAQAAAA==.Frostmhaw:BAAALgADCgUJBQAAAA==.Frostreaper:BAAALgAECgQJBgAAAA==.',
Fu='Fubukiofhell:BAAALgAECgYJCwAAAA==.Furtacor:BAAALgADCgcJBwAAAA==.',
['Fí']='Fí:BAAALgADCggJDgAAAA==.',
Ga='Gabana:BAAALgADCgQJBAAAAA==.Gabdobbuh:BAAALgAECgIJBAAAAA==.Gabn:BAAALgAECgIJAwAAAA==.Gafgar:BAAALgADCgUJCQAAAA==.Gaila:BAAALgADCgYJCAAAAA==.Galduin:BAABLgAECn8eAAIJAAgJ5Q4CIwAgAQAJAAgJ5Q4CIwAgAQAAAA==.',
Ge='Geduntruppa:BAAALgAECgYJBgAAAA==.Gentioiroh:BAAALgAECgMJAwAAAA==.',
Gh='Ghorderp:BAAALgADCgcJDAAAAA==.Ghosstt:BAAALgAECgEJAgAAAA==.Ghoulrozon:BAAALgADCgYJBgAAAA==.',
Gi='Giovannapala:BAAALgAECgcJCQAAAA==.Giripoca:BAAALgAECgQJCQAAAA==.',
Gl='Gladsmonge:BAABLgAECn8XAAIVAAcJeRzMFgALAgAVAAcJeRzMFgALAgAAAA==.Glorcckk:BAAALgADCgUJBQAAAA==.',
Gn='Gnomagga:BAAALgAECgYJCQAAAA==.Gnomohabe:BAAALgADCgQJBgAAAA==.',
Go='Goddofwarr:BAAALgADCggJEQAAAA==.Gonb:BAAALgADCgUJBQAAAA==.Goueki:BAABLgAECn8ZAAMBAAcJXxUhIQCbAQABAAcJXxUhIQCbAQAWAAIJSwGoggA8AAAAAA==.',
Gr='Greenzle:BAAALgAECgIJAgAAAA==.Grillnborst:BAAALgADCgEJAgAAAA==.Grilonp:BAAALgADCgQJBgAAAA==.Gromoff:BAAALgAFFAIJBAAAAA==.Grunmonk:BAAALgADCgEJAQAAAA==.Grømmar:BAAALgADCgMJAwAAAA==.',
Gu='Gudangara:BAAALgADCgYJBgAAAA==.Guztaverdead:BAAALgADCgQJBAAAAA==.',
['Gü']='Güistrong:BAAALgADCgIJAwAAAA==.',
Ha='Haakaí:BAAALgAECgUJCQAAAA==.Hackterin:BAAALgADCgYJBgAAAA==.Hadorah:BAAALgAECgUJBgAAAA==.Haerys:BAAALgADCgYJBgAAAA==.Handhemirr:BAAALgAECgMJBAAAAA==.Harany:BAAALgAECgUJCgAAAA==.Harrypotinho:BAAALgAECgYJEwAAAA==.Haunexd:BAAALgADCgMJAwAAAA==.Havenna:BAAALgAECgUJCAAAAA==.',
He='Headøhunter:BAAALgAECgEJAgAAAA==.Healgate:BAAALgAECgEJAQAAAA==.Hellenah:BAAALgADCggJCAAAAA==.Herika:BAAALgADCgMJAwAAAA==.',
Ho='Hoem:BAAALgAECgMJAwAAAA==.Holand:BAAALgAECgYJDgAAAA==.Holydread:BAAALgAECgIJAgAAAA==.',
Hu='Hulig:BAABLgAECn8VAAICAAcJPB4fGAD7AQACAAcJPB4fGAD7AQAAAA==.',
['Hø']='Høkulani:BAAALgAECgIJAgAAAA==.',
Ib='Ibuprofens:BAAALgAECgEJAQAAAA==.',
Ik='Ikiam:BAAALgAECgQJBAAAAA==.Ikslawok:BAAALgADCgYJCwAAAA==.',
Il='Ileria:BAAALgAECgYJBwAAAA==.Illarion:BAAALgADCgQJBAAAAA==.Illidanos:BAAALgAECgMJAwAAAA==.Illidansan:BAAALgADCgIJAgABLgADCggJCAAGAAAAAA==.Illidris:BAAALgAECgUJBQAAAA==.Illumiinated:BAAALgAECgYJEQAAAA==.',
In='Incarus:BAAALgAECgUJBwAAAA==.Indis:BAAALgADCgQJBgAAAA==.Interst:BAAALgAECgEJAQAAAA==.',
Ir='Irion:BAAALgADCgkJIgAAAA==.',
Is='Iscalio:BAAALgAECgUJCAAAAA==.',
Ja='Jackdawnsong:BAAALgAECgEJAQAAAA==.Jahuun:BAAALgAECgUJBgAAAA==.Jamantoso:BAAALgADCgIJAgAAAA==.',
Je='Jeess:BAAALgADCgMJAwAAAA==.Jefflich:BAABLgAECn8WAAIOAAgJ7weJiQBuAQAOAAgJ7weJiQBuAQAAAA==.',
Jg='Jg:BAAALgAECgUJBwAAAA==.',
Ji='Jinknu:BAAALgADCgEJAQAAAA==.',
Jo='Jottapeg:BAAALgADCgcJAwAAAA==.',
Ju='Jubard:BAAALgADCgkJDAAAAA==.Juliamarques:BAAALgAECgMJBAAAAA==.',
['Jü']='Jüllÿe:BAAALgADCgEJAQAAAA==.',
Ka='Kaaellthas:BAAALgAECgIJBAAAAA==.Kacolux:BAAALgADCgEJAQAAAA==.Kaisaargente:BAAALgAECgEJAQAAAA==.Kakarotho:BAAALgAECgMJBQAAAA==.Kaldonios:BAAALgADCgcJEgAAAA==.Kamasutram:BAAALgADCgYJCwAAAA==.Kanadriel:BAAALgAECgEJAgAAAA==.Kanarinho:BAABLgAECn8cAAIMAAYJlBWFUgBcAQAMAAYJlBWFUgBcAQAAAA==.Kazandra:BAAALgADCgYJBgAAAA==.',
Ke='Kendars:BAABLgAECn8VAAQSAAYJ0hKPSAAKAQASAAUJJhKPSAAKAQAMAAUJFQ+5dgDzAAAXAAEJgBWFGwBEAAAAAA==.Ket:BAAALgADCgMJAwAAAA==.',
Kh='Khanmir:BAAALgAECgMJBgAAAA==.Khild:BAAALgAECgYJDQAAAA==.',
Ki='Killerdek:BAAALgAECgEJAQAAAA==.Killshoty:BAAALgAECgEJAQAAAA==.',
Kl='Kluzlocak:BAABLgAECn8dAAIYAAYJhgilMQAUAQAYAAYJhgilMQAUAQAAAA==.',
Ko='Korav:BAAALgAECgMJBgAAAA==.Korium:BAAALgADCgUJBQABLgAECgMJAwAGAAAAAA==.Koruno:BAAALgADCgYJBgAAAA==.',
Kr='Krozhul:BAAALgAECgQJBgAAAA==.',
Ku='Kurnous:BAAALgAECgEJAQAAAA==.Kutirenzo:BAAALgADCgUJBwAAAA==.',
La='Lafiel:BAAALgAECgcJCwAAAA==.Lamelo:BAAALgADCgYJBgAAAA==.Lanmo:BAAALgAECgcJAgAAAA==.Largatixazul:BAAALgADCgUJBgAAAA==.Laurea:BAAALgAECgYJBgAAAA==.',
Le='Leebron:BAAALgADCgUJCgAAAA==.Lefthalas:BAAALgAECgUJCgAAAA==.Leitchero:BAAALgADCggJCAAAAA==.Lemaz:BAAALgAECgEJAQAAAA==.Leonelmessi:BAAALgAFFAQJAQAAAA==.Lesco:BAAALgADCgMJAwAAAA==.',
Li='Lianele:BAAALgAECgIJAgAAAA==.Liaras:BAABLgAECn8eAAMPAAYJwRKCGwArAQAPAAYJwRKCGwArAQAZAAIJzABAaQAmAAAAAA==.Licelaa:BAAALgADCgcJBwAAAA==.Lichtbaum:BAAALgAECgcJEAAAAA==.Lightsertrop:BAAALgADCgIJAgAAAA==.Liifecomm:BAABLgAECn8tAAIPAAgJgB9cDQCCAgAPAAgJgB9cDQCCAgAAAA==.Liike:BAAALgADCgMJAwAAAA==.Linestra:BAAALgADCgUJBQAAAA==.Liniak:BAAALgAECgUJBgAAAA==.Lisong:BAAALgADCgUJBQAAAA==.Littlepurple:BAACLgAFFH8JAAIQAAMJzxJvGwD2AAAQAAMJzxJvGwD2AAAuAAQKfyQAAhAACQl0HJ0YAMECABAACQl0HJ0YAMECAAAA.',
Lo='Longhai:BAAALgADCgUJCAAAAA==.Lookatmylock:BAABLgAECn8YAAMHAAYJKho/CAArAQAHAAYJKho/CAArAQAIAAIJQQmUBQFRAAAAAA==.Lordpain:BAAALgAECgMJBwAAAA==.Lortherti:BAAALgADCgUJBgAAAA==.Lorwin:BAAALgAECgcJDwAAAA==.Lotusbr:BAAALgADCgEJAQAAAA==.Louisenacioo:BAAALgAECgUJCAAAAA==.Loátrak:BAAALgADCgMJAwAAAA==.',
Lu='Luccablack:BAAALgAECgIJAgAAAA==.Lucyx:BAAALgAECgEJAQAAAA==.Luidar:BAAALgAECgQJBAAAAA==.Lukaslions:BAAALgAECgcJDQAAAA==.Lunarie:BAAALgAECgYJDQAAAA==.Luphoe:BAABLgAECn8XAAIMAAcJqxzKJwAWAgAMAAcJqxzKJwAWAgAAAA==.Luxanä:BAAALgADCgcJBwAAAA==.',
['Lé']='Léio:BAAALgADCgcJCAAAAA==.Léora:BAAALgADCgIJAgAAAA==.',
['Lø']='Lørdsith:BAAALgAECgYJCAAAAA==.',
['Lÿ']='Lÿcäns:BAAALgADCgMJAwAAAA==.',
Ma='Madagalux:BAAALgAECgQJBAAAAA==.Madjack:BAAALgAECgMJAwAAAA==.Madushi:BAAALgAECgIJAgAAAA==.Magatiun:BAAALgADCgMJBAAAAA==.Magogunt:BAAALgAECgYJDwAAAA==.Maguul:BAAALgAECgQJCQAAAA==.Magzifeh:BAEALgAFFAEJAgAAAA==.Malandrvs:BAAALgAFFAEJAQAAAA==.Maljamim:BAAALgADCgIJAgAAAA==.Mamuthwar:BAABLgAECn8ZAAMJAAcJnRgbNgDQAQAJAAcJnRgbNgDQAQAaAAEJMQ7VQQA1AAAAAA==.Mandingavudu:BAAALgAECgEJAgABLgAECgMJBAAGAAAAAA==.Manei:BAAALgAECgMJAwAAAA==.Mangalarga:BAAALgADCgEJAQAAAA==.Manopaladino:BAAALgADCgYJBgAAAA==.Manowlo:BAAALgAECgMJAwAAAA==.Manzagon:BAAALgAECgMJAwABLgAECgMJBAAGAAAAAA==.Marmelo:BAAALgADCgQJBAAAAA==.Marretasanta:BAABLgAECn8cAAICAAYJHhPdRgA1AQACAAYJHhPdRgA1AQAAAA==.Marù:BAAALgAECgQJBQAAAA==.Marúh:BAACLgAFFH8JAAIDAAMJrBixFADnAAADAAMJrBixFADnAAAuAAQKfyQAAgMACAnzIsMFABYDAAMACAnzIsMFABYDAAAA.Matroná:BAAALgADCgIJAQAAAA==.Maxmorf:BAAALgADCgQJBAAAAA==.Mayarabr:BAAALgADCgcJDAAAAA==.Mazeratos:BAAALgAECgMJAwAAAA==.',
Mc='Mcorelhao:BAAALgADCgEJAQAAAA==.',
Me='Megrezz:BAAALgAECgEJAQAAAA==.Mehiel:BAAALgAECgEJAQAAAA==.Mekihlvshtak:BAAALgADCgcJBwAAAA==.Mendingu:BAAALgAECgcJDwAAAA==.Merumim:BAAALgAECgQJAwAAAA==.Metalgirl:BAAALgADCgYJCwAAAA==.',
Mi='Midrão:BAAALgADCgEJAQAAAA==.Mindlocker:BAAALgAECgYJDQAAAA==.Minorus:BAAALgAECgcJEgAAAA==.Mistifs:BAAALgAECgYJCQAAAA==.',
Mo='Modogz:BAAALgADCgYJBgAAAA==.Momongadk:BAAALgADCgcJBwAAAA==.Monkeydking:BAAALgADCgUJBQAAAA==.Morania:BAAALgADCgcJCAAAAA==.Mordekais:BAAALgAECgIJAgAAAA==.Morganne:BAAALgAECgEJAQAAAA==.Moriyama:BAABLgAECn8WAAIMAAYJ3RxAJABhAQAMAAYJ3RxAJABhAQAAAA==.Morphisz:BAAALgAECgMJBAABLgAECgMJBAAGAAAAAA==.Morphiszs:BAAALgAECgMJBAAAAA==.Morphizs:BAAALgAECgEJAQABLgAECgMJBAAGAAAAAA==.Mortesan:BAAALgADCgEJAQABLgADCggJCAAGAAAAAA==.',
Mp='Mpastor:BAAALgADCgUJBQAAAA==.',
Mu='Muca:BAAALgADCgEJAQAAAA==.Muho:BAAALgADCgEJAQAAAA==.Mukonha:BAABLgAECn8VAAIIAAcJHge3RgAcAQAIAAcJHge3RgAcAQAAAA==.',
['Mã']='Mãoleves:BAAALgADCgEJAQAAAA==.',
['Må']='Måximus:BAAALgAECgIJAgAAAA==.',
['Mï']='Mïnthara:BAAALgAECgcJDQAAAA==.',
Na='Naeryndam:BAAALgADCgEJAQAAAA==.Narutowow:BAAALgADCgMJAwAAAA==.Natcmd:BAAALgADCgUJBQAAAA==.Nayanna:BAAALgADCgcJDQAAAA==.',
Ne='Negblack:BAAALgAECgMJAwAAAA==.Neggi:BAAALgAECgUJBwAAAA==.Nemesysy:BAAALgAECgMJAwAAAA==.Nerphien:BAAALgADCgUJBQAAAA==.Nesktpally:BAAALgAECgcJCAAAAA==.Netbrood:BAAALgADCgUJBgABLgAECgUJBwAGAAAAAA==.Netbrother:BAAALgAECgUJBwAAAA==.Nethdorai:BAAALgADCgQJBAAAAA==.Netherbane:BAAALgAECgcJEgAAAA==.Nezuko:BAAALgADCgcJEQABLgAECgYJEwAGAAAAAA==.',
Ni='Nightmære:BAAALgAECgQJBgAAAA==.Nikelok:BAAALgAECgMJAwAAAA==.Ninfador:BAABLgAECn8eAAIYAAYJgxeFEACGAQAYAAYJgxeFEACGAQAAAA==.Ninpus:BAAALgAECgMJAwAAAA==.',
No='Noobmasteer:BAAALgADCgIJAgAAAA==.Nooneknow:BAABLgAECn8hAAIOAAgJwyB0CgB8AgAOAAgJwyB0CgB8AgAAAA==.Nosrede:BAAALgAECgEJAQAAAA==.Notz:BAAALgADCgMJBAAAAA==.',
Ny='Nyde:BAAALgADCgEJAQAAAA==.',
Oa='Oakshlar:BAAALgAECgQJCgAAAA==.',
Oc='Ocelaris:BAAALgAECgEJAQAAAA==.',
Or='Oryana:BAAALgADCgcJIAAAAA==.Oríon:BAAALgADCgIJAgAAAA==.',
Ot='Otton:BAAALgAECgYJEQAAAA==.',
Ov='Overnigth:BAAALgADCgIJAgAAAA==.Overwalker:BAAALgADCgIJAgAAAA==.Ovosemdente:BAAALgADCgEJAQAAAA==.',
Ow='Owllskull:BAAALgAECgEJAQABLgAECgIJBAAGAAAAAA==.',
Pa='Pacoka:BAAALgADCgQJBQAAAA==.Paidesanto:BAAALgAECgYJEAAAAA==.Paidesantox:BAAALgADCgcJBwABLgAECggJHgAJAOUOAA==.Paladinokun:BAAALgADCggJCAAAAA==.Palanis:BAAALgAECgcJBwAAAA==.Palazarta:BAAALgAECgcJCQAAAA==.Panquecudo:BAAALgADCgIJAgAAAA==.',
Pd='Pdois:BAAALgADCgMJAwAAAA==.',
Pe='Pesscador:BAAALgAECgMJAwAAAA==.',
Pi='Piriguetee:BAAALgADCgEJAQAAAA==.Pirro:BAAALgAECgEJAQAAAA==.Pisadinha:BAAALgADCgcJBwAAAA==.',
Pk='Pkzimn:BAAALgADCgUJBQAAAA==.',
Pl='Playsson:BAAALgAECgYJDgAAAA==.Plottwist:BAAALgADCgcJDwABLgAECggJFQAOAGcTAA==.',
Po='Pogonus:BAAALgADCgIJAgAAAA==.Pontocego:BAAALgAECgQJBAAAAA==.',
Pr='Pravios:BAAALgAECgIJBAAAAA==.Priestkill:BAAALgADCgMJAgAAAA==.',
Pt='Pterodactilo:BAAALgAECgYJAQAAAA==.',
Pu='Puherito:BAAALgAECgQJBwAAAA==.Purgas:BAAALgAECgQJCgAAAA==.',
Qu='Quinthalam:BAAALgADCgMJAwAAAA==.',
Ra='Rafazinho:BAAALgADCgQJBAAAAA==.Ramyna:BAAALgAECgMJAwAAAA==.Ramyra:BAAALgADCgcJCwAAAA==.Raphaeldh:BAAALgAECgEJAgAAAA==.Raphahunterr:BAAALgADCgEJAQAAAA==.Raposa:BAAALgADCgEJAQAAAA==.Raposinha:BAAALgADCgMJAwAAAA==.Rarkway:BAAALgAECgQJBAAAAA==.Rayanne:BAAALgADCgYJBgAAAA==.',
Re='Reckfull:BAAALgAECgYJBgAAAA==.Regininha:BAAALgAECgEJAQAAAA==.Reloumifrend:BAAALgAECgcJCgAAAA==.Rendros:BAAALgADCgUJBQAAAA==.',
Rh='Rhaegaar:BAAALgAECgQJCgAAAA==.Rhodinius:BAAALgAECgMJCAAAAA==.',
Ri='Rivotreel:BAAALgADCgQJBAAAAA==.',
Ro='Rochera:BAAALgAECgEJAQAAAA==.',
Ru='Ruhtarr:BAAALgADCgEJAQAAAA==.',
Ry='Ryukato:BAAALgAECgQJBQAAAA==.',
Sa='Saek:BAAALgAECgcJEgAAAA==.Sanderclone:BAAALgAECgEJAQAAAA==.Santiss:BAAALgAECgQJCQAAAA==.Santorini:BAAALgADCgEJAQAAAA==.Saphis:BAAALgADCgEJAQAAAA==.Sardado:BAAALgAECgEJAQAAAA==.Sardron:BAAALgADCgMJAwAAAA==.',
Sc='Scanorr:BAAALgAECgEJAQAAAA==.Scheffers:BAAALgAECgEJAQAAAA==.',
Se='Selah:BAAALgADCgMJBQAAAA==.Selver:BAAALgAECgEJAQABLgAECgcJDAAGAAAAAA==.Sephora:BAAALgADCgcJFQABLgAECgYJHgAPAMESAA==.',
Sh='Shadowlock:BAAALgADCgIJAQABLgAECgYJDAAGAAAAAA==.Shadowmornac:BAAALgADCgEJAQAAAA==.Shamanica:BAAALgAECgEJAgAAAA==.Shamateus:BAAALgADCggJDAAAAA==.Shasuna:BAAALgADCgIJAgAAAA==.Shaunnun:BAAALgADCgEJAQAAAA==.Shinnók:BAAALgAECgIJAgAAAA==.Shiíro:BAAALgAECgIJAwABLgAECgYJDQAGAAAAAA==.Shynato:BAAALgADCgEJAQAAAA==.Shynock:BAAALgADCgEJAQAAAA==.Shãka:BAAALgADCgMJAwAAAA==.',
Si='Siladriel:BAAALgADCgMJAwAAAA==.Sirgonzo:BAAALgAECgYJDAAAAA==.',
Sk='Skullexus:BAAALgAECgMJBAAAAA==.Skunkbr:BAAALgADCgEJAQAAAA==.',
Sl='Sleepychety:BAAALgAECgUJBgAAAA==.Slowsmoke:BAAALgADCgEJAQAAAA==.',
Sn='Snatzz:BAAALgADCgMJAgAAAA==.',
So='Soggoth:BAAALgADCgkJCQAAAA==.Solk:BAAALgADCgQJBAAAAA==.Sontarfury:BAAALgAECgEJAQAAAA==.Sorim:BAAALgAECgYJEQAAAA==.Soryan:BAAALgAECgYJEgAAAA==.Soulassassin:BAAALgADCgIJAwAAAA==.Soulhell:BAAALgAECgYJEwAAAA==.',
Sp='Spartanlofs:BAAALgADCgcJEQAAAA==.Spawndeath:BAAALgADCgEJAQAAAA==.',
Ss='Ssushii:BAAALgAECgEJAQAAAA==.',
St='Stigmata:BAAALgADCgcJCAAAAA==.Stixmixdk:BAAALgAFFAQJAgAAAA==.Straz:BAAALgADCgQJBAAAAA==.Strongman:BAAALgAECgYJBgAAAA==.Stx:BAAALgAECgEJAQAAAA==.',
Su='Subsdk:BAABLgAECn8dAAIOAAgJ4hqsGAD2AQAOAAgJ4hqsGAD2AQAAAA==.Sunwalkers:BAAALgAECgUJBgAAAA==.',
Sy='Systeni:BAAALgADCgkJDQAAAA==.',
['Sø']='Søøssø:BAAALgADCgUJBQAAAA==.',
Ta='Taha:BAAALgAECgQJBgAAAA==.Taillys:BAAALgADCgMJBAAAAA==.Tainy:BAAALgADCgMJAwAAAA==.Takenaka:BAAALgADCgMJAwAAAA==.Tarez:BAAALgADCgkJCwAAAA==.Tarfonir:BAAALgAECgMJBAAAAA==.Tavalira:BAAALgADCgYJBgAAAA==.',
Te='Tealen:BAAALgADCgYJBgAAAA==.Ted:BAAALgAECgcJDAAAAA==.Teiseken:BAAALgAECgcJBwAAAA==.Teratsemknk:BAAALgAECgMJAwAAAA==.',
Th='Tharnforge:BAAALgAECgEJAQAAAA==.Thejokker:BAAALgAFFAIJAgAAAA==.Themooster:BAAALgAECgUJBwAAAA==.Thepickles:BAAALgADCgkJEAAAAA==.Thepunk:BAAALgAECgQJBQAAAA==.Thintor:BAAALgADCgEJAQAAAA==.Thormento:BAAALgAECgcJEgAAAA==.',
Ti='Tigerblood:BAAALgADCgUJBQAAAA==.Tipooreeii:BAAALgADCgEJAQAAAA==.Titanicos:BAAALgADCgMJAwAAAA==.',
Tj='Tjhunter:BAABLgAECn8bAAIBAAgJ3QijMgBGAQABAAgJ3QijMgBGAQAAAA==.',
To='Tobbiy:BAAALgAECgUJCQAAAA==.',
Tr='Tranh:BAAALgADCgkJFQAAAA==.Traxer:BAAALgADCgQJBAAAAA==.Tripäsecä:BAAALgAECgMJBQAAAA==.Troladora:BAAALgAECgYJCwAAAA==.',
Ts='Tsreis:BAAALgADCgEJAQAAAA==.',
Ty='Tyrandrisa:BAAALgADCgIJAQAAAA==.',
Um='Ummetrodefio:BAAALgADCgEJAQAAAA==.',
Ut='Uthred:BAABLgAECn8cAAMOAAgJ5gNuXADwAAAOAAgJ5wJuXADwAAAbAAYJoARuDADrAAAAAA==.',
Va='Vaelryn:BAAALgAECgUJBgAAAA==.Valdemmon:BAAALgADCgcJBwAAAA==.Valororo:BAAALgAECgMJAwAAAA==.Vandlesh:BAAALgAECgYJCwAAAA==.Varka:BAAALgADCgYJGQAAAA==.',
Ve='Velkharun:BAAALgAECgQJCwABLgAECgUJCgAGAAAAAA==.Venatrin:BAAALgADCgkJCQAAAA==.Vexxv:BAAALgAFFAIJAwAAAA==.Vexxz:BAAALgAECgYJBwAAAA==.',
Vi='Viquue:BAAALgADCgYJBgAAAA==.Vivisoft:BAAALgADCgMJAwAAAA==.',
Vo='Voidrb:BAAALgADCgcJBwABLgAECgcJDwAGAAAAAA==.Vovogamer:BAAALgADCgEJAQAAAA==.',
['Vò']='Vòxs:BAABLgAECn8wAAMaAAgJsyG4AwDEAgAaAAcJziG4AwDEAgAJAAYJyR2GLgD3AQAAAA==.',
Wa='Walkery:BAAALgADCgIJAgAAAA==.Wattari:BAABLgAECn8VAAILAAYJFwMkNQCdAAALAAYJFwMkNQCdAAAAAA==.',
Wh='Whiteep:BAAALgADCgYJCAAAAA==.Whiteseraph:BAAALgADCgEJAQAAAA==.Whynchester:BAAALgADCgEJAQAAAA==.',
Wi='Windsailor:BAAALgADCgcJCAAAAA==.Wiserys:BAABLgAECn8WAAMIAAYJOx2uHwC3AQAIAAYJOx2uHwC3AQAcAAMJNwygGwCXAAAAAA==.',
Wm='Wmarcão:BAAALgAECgUJCAAAAA==.',
Wo='Wolfiez:BAAALgAECgUJDAAAAA==.Wolfnwar:BAAALgAECgIJAgAAAA==.Wopz:BAAALgADCgUJBQAAAA==.',
Wq='Wqz:BAAALgAECgcJEQAAAA==.',
Wu='Wunamuno:BAAALgADCgkJCQAAAA==.',
Xa='Xallatath:BAAALgADCgUJBQAAAA==.Xamela:BAAALgADCgMJAwAAAA==.Xamãna:BAAALgAECgQJCQAAAA==.',
Xe='Xevron:BAAALgAECgQJBAAAAA==.Xexnetw:BAAALgADCgYJBgAAAA==.Xexnew:BAABLgAECn8VAAIUAAgJxhp/BQDaAQAUAAgJxhp/BQDaAQAAAA==.',
Xi='Xidevill:BAAALgAECgEJAQAAAA==.Xinthorak:BAAALgADCgEJAgAAAA==.Xinzhou:BAAALgADCgQJCAAAAA==.Xiseth:BAAALgAECgEJAQAAAA==.Xixíca:BAAALgADCgQJBQAAAA==.',
Xm='Xmari:BAAALgAECgEJAQAAAA==.',
Xu='Xulaman:BAAALgAECgcJDgAAAA==.Xungodz:BAAALgADCgQJBAAAAA==.Xunxu:BAAALgAECgYJEwAAAA==.',
Xy='Xynrath:BAAALgADCgMJAwAAAA==.',
Xz='Xzxzg:BAABLgAFFH8GAAIXAAUJqBctAQB4AQAXAAUJqBctAQB4AQABLgAFFAYJFAAdAJchAA==.',
['Xÿ']='Xÿon:BAAALgAECgEJAQAAAA==.',
Ya='Yannadcg:BAABLgAECn8bAAIPAAgJzQSJQQAyAQAPAAgJzQSJQQAyAQAAAA==.',
Yo='Youdie:BAABLgAECn8YAAIZAAgJeRLsKgCEAQAZAAgJeRLsKgCEAQAAAA==.',
Yu='Yulthuan:BAAALgADCgMJAwAAAA==.',
Yv='Yvernus:BAAALgAECgQJBQAAAA==.',
Za='Zaaraki:BAABLgAECn8VAAMOAAgJZxPLVQDwAQAOAAgJIRLLVQDwAQAUAAYJ6w+AKwDjAAAAAA==.Zarolho:BAABLgAECn8VAAIEAAYJRg6kLADOAAAEAAYJRg6kLADOAAAAAA==.',
Ze='Zenitsua:BAAALgAECgQJBQAAAA==.Zephiir:BAAALgAECgQJCQAAAA==.',
Zh='Zhunka:BAAALgADCgEJAQAAAA==.',
Zo='Zornak:BAAALgADCgUJBQAAAA==.',
Zz='Zzx:BAAALgADCgcJBwAAAA==.',
['Zé']='Zécasete:BAAALgADCgUJBwAAAA==.',
['Ál']='Álucard:BAAALgADCgcJDgAAAA==.',
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

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

local lookup = {'Unknown-Unknown','Paladin-Retribution','DemonHunter-Vengeance','Shaman-Restoration','Hunter-Marksmanship','Hunter-Survival','Warrior-Fury','Evoker-Devastation','Priest-Holy','DemonHunter-Devourer','Rogue-Subtlety','Warrior-Arms','DeathKnight-Blood','DeathKnight-Unholy','DeathKnight-Frost','Paladin-Holy','Paladin-Protection','Priest-Discipline','Shaman-Elemental','Evoker-Preservation','Warrior-Protection','Druid-Restoration','Monk-Windwalker','Mage-Frost','Warlock-Demonology','Warlock-Affliction','Hunter-BeastMastery','Warlock-Destruction','Druid-Feral','Druid-Guardian','Monk-Brewmaster','Monk-Mistweaver','Shaman-Enhancement','Priest-Shadow','DemonHunter-Havoc',}
local provider = {region='US',realm='Anvilmar',name='US',type='weekly',zone=46,date='2026-04-24',data={Aa='Aaril:BAAALgADCgkJHAAAAQ==.',
Ae='Aelitha:BAAALgAECgYJEwAAAA==.',
Ak='Akaishi:BAAALgADCgEJAQAAAA==.Akali:BAAALgAFFAEJAQAAAA==.',
Al='Alathiana:BAAALgADCgUJCAAAAA==.Alcweaver:BAAALgAECgYJBgAAAA==.Alecto:BAAALgAECgMJAwAAAA==.Alindia:BAAALgAECgQJCgABLgAECggJDgABAAAAAA==.Alirrayia:BAAALgAECgQJBAAAAA==.Alirrayiia:BAABLgAECn8fAAICAAkJ2w0yTQD7AQACAAkJ2w0yTQD7AQAAAA==.Alkri:BAAALgADCgMJAwAAAA==.Allari:BAAALgAECgYJEwAAAA==.Allystar:BAAALgADCgkJFwAAAA==.Altheia:BAAALgAECgQJBAAAAA==.Alvidor:BAAALgAECgYJEwAAAA==.',
Am='Ameria:BAAALgADCgUJBQAAAA==.',
An='Anastos:BAAALgAECgQJBAAAAA==.Andydufresne:BAAALgAECgEJAQABLgAECggJIgADAFclAA==.Angryqueer:BAAALgADCgEJAQAAAA==.',
Ao='Aowl:BAAALgAECgcJCwAAAA==.',
Ap='Apocketheory:BAAALgADCgIJAgAAAA==.Apolloerosb:BAAALgADCggJDgABLgAECgUJCAABAAAAAA==.Apollossham:BAAALgAECgUJCAAAAA==.',
Ar='Arkanaun:BAAALgAECgYJEwAAAA==.',
As='Ashes:BAAALgAECgcJAQAAAA==.Ashrán:BAAALgAECgEJAgAAAA==.Ashyluna:BAAALgAECgQJBAAAAA==.Astianna:BAAALgADCgMJAwAAAA==.',
Au='Aurinia:BAAALgADCgQJAgAAAA==.Aurore:BAAALgADCgQJBgAAAA==.',
Av='Avradea:BAAALgADCgEJAQABLgAECggJDgABAAAAAA==.',
Az='Azareth:BAAALgADCggJCAAAAA==.',
Ba='Baconatorr:BAAALgAECgMJAwAAAA==.Bagelbags:BAAALgADCgEJAQAAAA==.Bahler:BAAALgADCgUJBQABLgAECgMJAwABAAAAAA==.Baji:BAABLgAECn8eAAIEAAgJbCOBAAAVAwAEAAgJbCOBAAAVAwAAAA==.Baklan:BAAALgAECgMJAwAAAA==.Barefaall:BAABLgAECn8kAAIFAAkJfBuLCwDtAgAFAAkJfBuLCwDtAgAAAA==.Barefalls:BAABLgAECn8YAAMGAAYJ9xOABQB8AQAGAAYJ9xOABQB8AQAFAAEJjAGKlgAiAAABLgAECgkJJAAFAHwbAA==.Barelywolf:BAAALgAECgUJDQABLgAFFAEJAQABAAAAAA==.Bashira:BAAALgAECgYJDgAAAA==.Bast:BAAALgAECgYJEgAAAA==.',
Be='Bearophe:BAAALgAECgEJAgAAAA==.Beerfist:BAAALgAECgEJAQAAAA==.Bellock:BAAALgADCggJCAAAAA==.Benisbagina:BAAALgADCggJCQAAAA==.Bergonator:BAABLgAECn8VAAIHAAYJRRCxTwBpAQAHAAYJRRCxTwBpAQAAAA==.Berrodiah:BAAALgAECgIJAgABLgAECggJFgAIALUYAA==.Bettyswalls:BAAALgAECgMJAwAAAA==.Beyarago:BAAALgAECgUJCQAAAA==.',
Bh='Bheiroth:BAABLgAECn8XAAIJAAYJxSR/AgBIAgAJAAYJxSR/AgBIAgAAAA==.',
Bl='Bladeygaga:BAABLgAECn8eAAIKAAgJYRYOCwDDAQAKAAgJYRYOCwDDAQAAAA==.Blazingblood:BAAALgADCgUJAQAAAA==.Bloodknight:BAAALgADCgYJCQAAAA==.Bluett:BAAALgADCggJEAAAAA==.Bláckøut:BAAALgADCgYJDAAAAA==.',
Bo='Bodhi:BAABLgAECn8WAAILAAcJNhAKJwDAAQALAAcJNhAKJwDAAQAAAA==.Bogertus:BAABLgAECn8gAAMHAAcJuiWPCgAJAwAHAAcJuiWPCgAJAwAMAAIJ9RxuKQClAAAAAA==.Boomertunes:BAAALgAECgUJDQAAAA==.',
Br='Brein:BAAALgAECgYJEwAAAA==.Brewmaster:BAAALgADCgEJAQAAAA==.Brewwmaster:BAABLgAECn8YAAQNAAcJTRk5BgBEAQAOAAYJtBfSfACKAQANAAcJihQ5BgBEAQAPAAEJ+hexFgA2AAAAAA==.Brickred:BAAALgADCggJDgAAAA==.Brynodd:BAAALgADCggJEgAAAA==.',
Bu='Bubblybetty:BAAALgADCgUJCAAAAA==.Bucketeer:BAAALgAECgUJEAAAAA==.Buffs:BAAALgADCgEJAQAAAA==.Bursona:BAAALgAECgEJAQAAAA==.Butterfree:BAAALgAECgQJCQAAAA==.',
Ca='Cards:BAAALgAECgYJBwAAAA==.Carkrash:BAAALgADCgkJFwAAAA==.Casterkang:BAAALgAECgQJBgAAAA==.Catshunter:BAAALgAECgUJCQAAAA==.',
Ce='Celaa:BAAALgAECggJDgAAAA==.',
Ch='Chanka:BAAALgAECgQJBAAAAA==.Chantillary:BAAALgADCggJEgAAAA==.Chargerkang:BAAALgADCgYJBgAAAA==.Chchanges:BAAALgAECgEJAQAAAA==.Cheesy:BAAALgAECgYJCwAAAA==.Chicken:BAAALgAECgUJBwAAAA==.Chonk:BAAALgADCgEJAQAAAA==.Chopzullee:BAAALgAECgUJCQAAAA==.',
Ci='Cirya:BAAALgAECgUJBQAAAA==.',
Cl='Cleric:BAAALgADCgUJBQAAAA==.Clortho:BAAALgADCgcJEAAAAA==.',
Co='Colljack:BAACLgAFFH8OAAIQAAQJgx8kAwBZAQAQAAQJgx8kAwBZAQAuAAQKfxoAAxAACQl3IqEJANcCABAACAktIqEJANcCAAIABQlOEsS5ABIBAAAA.',
Cr='Crocbait:BAAALgAECgUJDAAAAA==.Cryptoe:BAAALgAECgYJEAAAAA==.',
Cu='Cudlsac:BAAALgAECgQJBQAAAA==.',
Da='Daedelus:BAAALgAECgcJCAAAAA==.Daglon:BAAALgAECgYJCAAAAA==.Dagz:BAAALgAECgQJBAAAAA==.Dakina:BAAALgADCgYJBgAAAA==.Daraedra:BAAALgADCgYJDAAAAA==.Darkenvoid:BAAALgADCgkJCQAAAA==.',
De='Deathslight:BAAALgAECgQJBwAAAA==.Deeznutticus:BAACLgAFFH8PAAIHAAUJWRFrAgBcAQAHAAUJWRFrAgBcAQAuAAQKfx4AAwcABwnCIk0YAIkCAAcABwnCIk0YAIkCAAwAAQkSFhY8AEEAAAAA.Defnotisis:BAAALgAECggJEgABLgAFFAEJAQABAAAAAA==.Demonspud:BAABLgAECn8UAAIKAAcJlg4/HgAWAQAKAAcJlg4/HgAWAQAAAA==.Dersan:BAAALgAECgYJDAAAAA==.Destriant:BAABLgAECn8dAAIRAAgJiBclCQBCAgARAAgJiBclCQBCAgAAAA==.Devilschant:BAAALgAECgYJCgAAAA==.Devilshadow:BAAALgAECgUJBwABLgAECgYJCgABAAAAAA==.Deylia:BAAALgADCgYJBgABLgAECggJIAASAGIZAA==.',
Di='Dilithia:BAAALgADCgkJFQAAAA==.Dillion:BAAALgAECgYJCAAAAA==.Dinonuggies:BAAALgADCgcJBwAAAA==.Dionin:BAAALgADCgYJCQAAAA==.Dira:BAAALgAECgUJBwABLgAFFAMJBQATAMoeAA==.Dirkbanne:BAAALgADCgYJBgAAAA==.',
Do='Dodoubleg:BAAALgAECgYJEAAAAA==.Dominique:BAAALgADCgYJBgAAAA==.Donzilch:BAEALgAECgQJBAAAAA==.',
Dr='Dracaric:BAAALgAECgYJEAAAAA==.Drfrostie:BAAALgAECgcJBwAAAA==.Drgunner:BAAALgAECgcJDwAAAA==.Driatin:BAAALgAECgIJBAABLgAECgQJCQABAAAAAA==.Drkladykikyo:BAAALgAECgYJDgAAAA==.Druroo:BAAALgAECgEJAQABLgAECggJFQASAF8dAA==.Druterr:BAAALgAECgIJAgAAAA==.',
Du='Dumb:BAACLgAFFH8NAAIUAAUJLAyDBgCJAQAUAAUJLAyDBgCJAQAuAAQKfyMAAhQACAnoG2YLAH8CABQACAnoG2YLAH8CAAAA.Durø:BAABLgAECn8eAAIKAAgJFCOcAwBkAgAKAAgJFCOcAwBkAgAAAA==.',
Dy='Dyanisian:BAAALgADCgYJCAAAAA==.',
['Dè']='Dègenerate:BAABLgAECn8dAAIVAAgJ2RyiAQAuAgAVAAgJ2RyiAQAuAgAAAA==.',
Ed='Edagerran:BAAALgADCgkJCQAAAA==.',
Ei='Eilae:BAAALgAECgEJAQAAAA==.Eirhakan:BAAALgAECgQJBAAAAA==.',
El='Elrethyl:BAAALgAECgYJDgAAAA==.Elvanus:BAAALgADCgYJBgAAAA==.Elêktra:BAABLgAECn8XAAITAAYJ6hDBDgAZAQATAAYJ6hDBDgAZAQAAAA==.',
Ep='Epicsmoke:BAABLgAECn8bAAIHAAcJsB21AwAKAgAHAAcJsB21AwAKAgAAAA==.Epidemius:BAAALgAECgcJBwAAAA==.',
Er='Erevan:BAAALgAECgYJDgAAAA==.Eroica:BAAALgADCgYJBwAAAA==.',
Es='Esdeath:BAABLgAECn8XAAIOAAYJkhZAFgBfAQAOAAYJkhZAFgBfAQAAAA==.',
Et='Etharia:BAAALgADCgUJAwAAAA==.',
Ev='Evilsmeghead:BAAALgADCgEJAQAAAA==.',
Ex='Extenze:BAABLgAECn8XAAIKAAYJCBn/EAB9AQAKAAYJCBn/EAB9AQAAAA==.',
Ez='Ezykiah:BAAALgADCgcJBwAAAA==.',
Fa='Falconponch:BAAALgADCgEJAQAAAA==.',
Fe='Felgibson:BAAALgAECgMJAwAAAA==.Felkang:BAAALgADCgkJCQAAAA==.Ferryman:BAAALgAECgEJAQAAAA==.',
Fl='Flingor:BAAALgAECgYJEAAAAA==.Flokha:BAAALgADCgEJAQAAAA==.',
Fo='Forphium:BAACLgAFFH8NAAILAAUJeAufBACkAQALAAUJeAufBACkAQAuAAQKfxsAAgsACQldH3wNAMQCAAsACQldH3wNAMQCAAAA.',
Fr='Fredolf:BAAALgADCggJCAAAAA==.Freydís:BAAALgAECgUJCwAAAA==.Friarkuck:BAAALgADCggJCAAAAA==.Friedbones:BAAALgADCgcJEQAAAA==.',
Ga='Gahlina:BAAALgAECgEJAQAAAA==.Galdorian:BAAALgADCgMJAwABLgAECgYJDgABAAAAAA==.Galynda:BAAALgADCgQJBQAAAA==.',
Ge='Genjimain:BAABLgAECn8aAAIWAAcJXRyQHgBKAgAWAAcJXRyQHgBKAgAAAA==.Genjí:BAAALgAECgEJAQAAAA==.Geris:BAAALgAECgQJBQAAAA==.Gertruide:BAAALgADCgUJBQAAAA==.',
Gh='Ghendala:BAAALgADCggJDQAAAA==.',
Gi='Gincainn:BAAALgAECgEJAgAAAA==.Gird:BAABLgAECn8XAAIQAAYJLQ0CEAA9AQAQAAYJLQ0CEAA9AQAAAA==.',
Gl='Glaiveyjones:BAAALgADCgYJBgAAAA==.',
Go='Goatmonger:BAAALgAECgYJBgAAAA==.Goinpostal:BAAALgAECgIJAgAAAA==.Goldblade:BAAALgAECgkJBAAAAA==.Gordek:BAAALgAECgYJDAAAAA==.Gothitelle:BAAALgADCggJDAAAAA==.Goöse:BAACLgAFFH8OAAIOAAUJkyDXAwDEAQAOAAUJkyDXAwDEAQAuAAQKfyAAAg4ACAmDJuwGAGsDAA4ACAmDJuwGAGsDAAAA.',
Gr='Grantaron:BAABLgAECn8dAAICAAgJOx0/GADXAgACAAgJOx0/GADXAgAAAA==.Gravarii:BAAALgADCgcJEwAAAA==.Grimskul:BAAALgAECggJEgAAAA==.Grntitan:BAAALgADCgkJEQAAAA==.Gruid:BAAALgADCgcJCgAAAA==.',
Gu='Guinessbrew:BAAALgADCgEJAQAAAA==.',
Gw='Gwoohoori:BAAALgAECgQJAwAAAA==.',
Gy='Gyra:BAAALgAECgYJDwAAAA==.',
Ha='Halukari:BAAALgAECgYJCgABLgAECggJIAASAGIZAA==.Harfnan:BAAALgAECgIJAgAAAA==.Harrin:BAAALgAECgYJDwAAAA==.',
He='Healingwater:BAAALgADCgEJAQAAAA==.Hezrel:BAAALgAECgUJCAAAAA==.',
Hi='Hierodule:BAAALgAECgEJAQAAAA==.Hiimriven:BAAALgAECgIJAgABLgAECgYJFgALAFkhAA==.Hinal:BAAALgAECgQJBwAAAA==.',
Ho='Hojo:BAAALgADCgUJCAAAAA==.Holyenabler:BAAALgAECgUJBwAAAA==.Hootiehoo:BAAALgADCgMJAwAAAA==.',
Hu='Huflunggoo:BAAALgADCgkJDQAAAA==.Huflungpoop:BAABLgAECn8bAAIXAAYJeBjDCQA2AQAXAAYJeBjDCQA2AQAAAA==.Hunterborn:BAAALgAECgUJCwAAAA==.',
['Hè']='Hèalz:BAAALgADCgcJCQABLgAECgYJDAABAAAAAA==.',
Ic='Ickixia:BAAALgADCgQJBAAAAA==.',
Il='Ilkaressa:BAAALgADCgQJBAAAAA==.Illyríá:BAAALgAFFAIJAgABLgAECgcJEwABAAAAAA==.',
Im='Imcruel:BAACLgAFFH8MAAIYAAUJfRyXFwBrAQAYAAUJfRyXFwBrAQAuAAQKfxkAAhgABwnaJeUtALoCABgABwnaJeUtALoCAAAA.',
In='Ink:BAABLgAECn8gAAIYAAcJvCBuBwAzAgAYAAcJvCBuBwAzAgAAAA==.',
Is='Istaria:BAAALgADCggJEgAAAA==.Isujr:BAABLgAECn8YAAIOAAcJ8hIKcQCmAQAOAAcJ8hIKcQCmAQAAAA==.',
Ja='Jackiegan:BAAALgAECgYJCgAAAA==.Jackson:BAAALgADCggJEgAAAA==.Jagerdemon:BAAALgAECgcJBwAAAA==.',
Je='Jerce:BAAALgADCgUJBQAAAA==.',
Jh='Jhala:BAAALgADCgcJCAAAAA==.',
Jo='Joshcalc:BAAALgAECgEJAQAAAA==.Joskel:BAABLgAECn8VAAMZAAYJFAjnIgAQAQAZAAYJFAjnIgAQAQAaAAUJEgPnFgDIAAAAAA==.',
Ju='Juacqer:BAAALgADCgcJEQAAAA==.',
Ka='Kaant:BAAALgAECgYJEwAAAA==.Kaeni:BAAALgADCgMJAwAAAA==.Kaidevyn:BAAALgAECgcJEgAAAA==.Kaleine:BAAALgADCgkJEQAAAA==.Kardren:BAAALgADCgYJBQAAAA==.',
Ke='Keiko:BAAALgAECgYJCAAAAA==.Keiran:BAABLgAECn8dAAMbAAgJzh66BAAxAgAFAAgJphyOEgCfAgAbAAcJNx+6BAAxAgAAAA==.Kelazurin:BAAALgADCgEJAQAAAA==.Kellistair:BAAALgADCgYJBgAAAA==.Keläo:BAAALgADCgUJCQAAAA==.Keyadish:BAAALgADCgYJBgAAAA==.Keys:BAABLgAECn8cAAILAAgJ4hm5EACcAgALAAgJ4hm5EACcAgAAAA==.',
Kh='Khalnerys:BAAALgAECgYJEAAAAA==.Khoulock:BAACLgAFFH8JAAIZAAQJHxfVBwBEAQAZAAQJHxfVBwBEAQAuAAQKfykAAxkACQlNIOEBAJwCABkACQlNIOEBAJwCABwAAwl9ENM+ALkAAAAA.',
Ki='Kimmispally:BAAALgAECgIJAgAAAA==.Kiro:BAAALgADCgQJBQAAAA==.',
Ko='Kotateal:BAAALgAECgYJCwAAAA==.',
Kr='Kruelshot:BAAALgAECgcJCQABLgAFFAUJDAAYAH0cAA==.Krux:BAAALgAECgEJAQAAAA==.',
Ku='Kumcookies:BAAALgADCgEJAQAAAA==.Kuraishin:BAABLgAECn89AAMdAAcJvB6eBwBuAgAdAAcJvB6eBwBuAgAeAAMJnRwXGgDdAAAAAA==.Kuroakuma:BAAALgAECgYJDwAAAA==.Kuvara:BAAALgADCgkJCgAAAA==.',
Kw='Kwandashadow:BAAALgAECgQJBwAAAA==.',
['Ké']='Kéres:BAAALgADCgkJEAAAAA==.',
La='Lagspike:BAABLgAECn8cAAIYAAgJvBWxGACBAQAYAAgJvBWxGACBAQAAAA==.Latheal:BAAALgADCgcJDAAAAA==.Lavi:BAAALgAECgYJEAAAAA==.',
Lb='Lbk:BAAALgADCgIJAgAAAA==.',
Le='Lejeune:BAAALgADCgYJEwAAAA==.Lengex:BAAALgAECgUJBwAAAA==.Lero:BAABLgAECn8gAAIfAAgJViOGAQBtAgAfAAgJViOGAQBtAgAAAA==.Lerwindion:BAABLgAECn8VAAISAAgJXx2PCQCiAgASAAgJXx2PCQCiAgAAAA==.Lexoh:BAAALgAECgYJEgAAAA==.',
Li='Lindir:BAABLgAECn8kAAIGAAgJ3SNYAADIAgAGAAgJ3SNYAADIAgAAAA==.Lionelle:BAAALgAECgYJCAAAAA==.Liquor:BAABLgAECn8kAAMKAAkJMR3OAQCsAgAKAAkJMR3OAQCsAgADAAIJ/BDnIQB0AAAAAA==.Lirathiel:BAAALgAECgEJAQAAAA==.Litasfk:BAAALgAECgIJAgAAAA==.Liuni:BAABLgAECn8XAAIfAAYJKBmrCwA1AQAfAAYJKBmrCwA1AQAAAA==.Liyin:BAAALgAECgEJAQABLgAECggJDgABAAAAAA==.',
Lo='Lobopeste:BAAALgAECgYJEwAAAA==.Locknutz:BAAALgADCgMJAwAAAA==.Lorelynn:BAAALgAECgYJEAAAAA==.',
Lu='Luci:BAAALgAECgMJAwABLgAFFAEJAQABAAAAAA==.Lucìan:BAAALgAECgYJEQAAAA==.Ludociel:BAAALgADCgkJEQAAAA==.Lunaclair:BAABLgAECn8wAAMOAAgJcRUhGABSAQAOAAgJcRUhGABSAQANAAIJUQb9QgA+AAABLgAECgcJPQAdALweAA==.Lunadrus:BAAALgAECgcJDwAAAA==.Lunarielle:BAABLgAECn8aAAIbAAcJKx3GFQCJAgAbAAcJKx3GFQCJAgAAAA==.',
Ly='Lyriaa:BAAALgADCgUJBgAAAA==.',
Ma='Macfly:BAABLgAECn8YAAIbAAYJrhhUEgBpAQAbAAYJrhhUEgBpAQAAAA==.Madmeatballs:BAAALgADCgIJAgAAAA==.Magicmissile:BAABLgAECn8XAAIYAAgJvxrtYgAUAgAYAAgJvxrtYgAUAgAAAA==.Makgora:BAAALgAECgMJBAABLgAECgYJFgALAFkhAA==.Maksoon:BAAALgAECgUJCwAAAA==.Maladjusted:BAAALgAECgMJBAAAAA==.Maléfique:BAAALgADCggJDAAAAA==.Mancath:BAAALgADCgcJBwAAAA==.Mar:BAAALgADCgMJAwAAAA==.Marlei:BAAALgADCgQJBAABLgAECggJDgABAAAAAA==.Marqose:BAAALgADCgYJBgAAAA==.Matan:BAAALgADCgUJBQAAAA==.',
Me='Melfie:BAAALgAECgYJBgAAAA==.Meliadoul:BAAALgAECgUJCgAAAA==.Mellyndra:BAAALgAECgYJEwAAAA==.Mercüry:BAAALgAECgEJAQAAAA==.Mezhren:BAAALgADCggJFgAAAA==.',
Mh='Mhoramsgirl:BAAALgADCgYJBgAAAA==.',
Mi='Midoriya:BAABLgAECn8dAAMXAAgJ+hAlKACZAQAXAAcJ0hElKACZAQAgAAQJVA7cVAB+AAAAAA==.Mistjack:BAAALgAECggJDQAAAA==.',
Mo='Momdad:BAABLgAECn8dAAIGAAkJIRpAAQBNAgAGAAkJIRpAAQBNAgAAAA==.Mongaux:BAAALgADCgQJBQAAAA==.Monkey:BAAALgAECgEJAwAAAA==.Morrígán:BAAALgADCgUJBQAAAA==.Moxi:BAAALgADCggJDQAAAA==.',
Mu='Muamman:BAAALgAECgMJAwAAAA==.Murda:BAAALgADCgYJCgAAAA==.Murphysflaw:BAAALgADCgUJCAAAAA==.Mutegen:BAAALgAECgMJBAAAAA==.',
Mx='Mxhealeryduf:BAAALgAECgIJAgAAAA==.',
My='Mystallian:BAAALgADCgUJCgAAAA==.Mythicplus:BAAALgAECgcJCgAAAA==.',
['Mé']='Mémnoc:BAAALgAECgMJAwAAAA==.',
Na='Nadarien:BAAALgAECgYJDQAAAA==.Nadyia:BAAALgADCgEJAQAAAA==.Nailah:BAAALgADCgcJCwAAAA==.Nannergoat:BAAALgADCgMJAwAAAA==.Nastymikey:BAABLgAECn8UAAIhAAgJQRp2BwBzAgAhAAgJQRp2BwBzAgAAAA==.Nazdormu:BAAALgAECgUJCgAAAA==.',
Ne='Nefarious:BAAALgAECgYJBgAAAA==.Neisen:BAABLgAECn8YAAMQAAgJig/gOgCOAQAQAAcJuw3gOgCOAQACAAUJBwKL+gCeAAAAAA==.Neptune:BAAALgADCgYJBgAAAA==.',
No='Norna:BAAALgADCgUJCgAAAA==.',
Nu='Nufonewhodis:BAABLgAECn8WAAILAAYJWSFzHQATAgALAAYJWSFzHQATAgAAAA==.',
Ny='Nykolas:BAAALgADCggJCgAAAA==.Nymofthedead:BAAALgAECgYJBgAAAA==.',
Oa='Oakgrove:BAAALgADCgQJBAAAAA==.',
Om='Ombraless:BAAALgADCgMJAwABLgAECgQJBAABAAAAAA==.',
Op='Ophrizhani:BAAALgAECgMJAwAAAA==.',
Or='Orangegrove:BAAALgAECgEJAQAAAA==.Orpheal:BAAALgAECgUJBQAAAA==.Orphen:BAAALgADCgYJBgAAAA==.',
Pa='Paddleball:BAAALgADCgQJBAAAAA==.Paladouin:BAAALgAECgYJEwAAAA==.Pandammy:BAAALgAECgkJAgAAAA==.Pantro:BAAALgADCgQJBAAAAA==.Papalion:BAAALgAECgEJAQAAAA==.Paragas:BAAALgADCgkJEAAAAA==.Pawbs:BAAALgAECgMJBwAAAA==.',
Pe='Peanuts:BAAALgADCgcJBwAAAA==.Peoplehugger:BAAALgADCgMJAwAAAA==.',
Pi='Pickleburger:BAAALgADCgMJAwAAAA==.Pinklilydrd:BAAALgADCggJEgAAAA==.',
Pr='Priestdrago:BAAALgADCgUJBQAAAA==.Prissidebow:BAAALgADCggJEgAAAA==.',
Ra='Ralynne:BAABLgAECn8aAAITAAgJKw6fQQBCAQATAAgJKw6fQQBCAQAAAA==.Ravenbrook:BAABLgAECn8ZAAIHAAgJsCSABABiAwAHAAgJsCSABABiAwAAAA==.Rawrr:BAAALgAECgUJCgAAAA==.Raxie:BAABLgAECn8gAAQSAAgJYhkkAgBNAgASAAgJYhkkAgBNAgAiAAMJphQNSwCtAAAJAAEJAQTchwAoAAAAAA==.Razeth:BAAALgAECgYJDgAAAA==.',
Re='Reanne:BAAALgAECgYJEAAAAA==.Res:BAAALgAECgYJCwAAAA==.Rescorla:BAAALgAECgYJBgAAAA==.Rethali:BAAALgADCgQJAgAAAA==.Rezr:BAAALgAECgYJCwAAAA==.',
Rh='Rhixa:BAAALgADCgUJBQAAAA==.',
Ri='Rifthor:BAAALgAECgUJCQAAAA==.Rillx:BAAALgADCgMJBQAAAA==.Ripmxi:BAABLgAECn8bAAIYAAYJEBNRLAAaAQAYAAYJEBNRLAAaAQAAAA==.',
Ro='Robinski:BAAALgADCgEJAQAAAA==.Robotiss:BAAALgADCgIJAgAAAA==.Rodevon:BAAALgADCggJCAAAAA==.Roknasaurus:BAAALgADCgUJCAAAAA==.Romani:BAAALgADCgYJBgAAAA==.Romeo:BAAALgADCgMJAwAAAA==.Ronaldreagnt:BAAALgAECgEJAQAAAA==.',
Ru='Runelight:BAAALgAECgMJAwAAAA==.Rupertgiless:BAACLgAFFH8GAAIZAAQJCQnECAA5AQAZAAQJCQnECAA5AQAuAAQKfyAAAhkACQk9GnoiAIsCABkACQk9GnoiAIsCAAAA.',
Sa='Sabeckya:BAAALgAECgEJAQAAAA==.Sacksmasher:BAAALgADCgcJDwAAAA==.Sampleshrimp:BAAALgADCgEJAgAAAA==.Saphyla:BAAALgADCgcJCwAAAA==.Sarcastyx:BAAALgAECgQJBQAAAA==.Saxines:BAAALgAECgIJAgAAAA==.',
Sc='Scaliefox:BAAALgAECgIJAgABLgAECgYJEwABAAAAAA==.Schwarznacht:BAAALgADCgUJBQAAAA==.Schwarzwölf:BAAALgADCgYJCwAAAA==.Scoots:BAAALgADCgQJBAAAAA==.Scrubs:BAAALgAECgUJCAAAAA==.Scrubsevoker:BAAALgADCgEJAgAAAA==.Scumbum:BAAALgADCgIJAgAAAA==.Scyllo:BAAALgAECgQJBAAAAA==.',
Se='Seekndestroy:BAAALgAECgEJAQAAAA==.Selige:BAAALgAECgQJBAAAAA==.',
Sg='Sgtcuunt:BAAALgADCgQJBAAAAA==.',
Sh='Shaenicor:BAAALgADCgIJAgAAAA==.Shelbo:BAAALgADCgMJAwAAAA==.Shortshammy:BAAALgAECgEJAQABLgAFFAIJBQAYAAEBAA==.Shror:BAAALgADCgEJAQABLgAECgUJBQABAAAAAA==.',
Si='Sicarune:BAAALgAECgEJAQAAAA==.Siiegrand:BAAALgAECgYJDQAAAA==.Silentswag:BAAALgADCgUJBQAAAA==.Sitzho:BAAALgADCgUJCAAAAA==.',
Sk='Skeleton:BAAALgAECgIJAgAAAA==.Skybringer:BAABLgAECn8VAAICAAYJpAjFtAAbAQACAAYJpAjFtAAbAQAAAA==.Skyee:BAABLgAECn8dAAIXAAgJhh0GDAC6AgAXAAgJhh0GDAC6AgAAAA==.Skylos:BAAALgAECgEJAQAAAA==.',
So='Soapscum:BAAALgADCgQJBAAAAA==.Soarphium:BAAALgAECgIJAgABLgAFFAUJDQALAHgLAA==.Soleana:BAAALgAECgYJBQAAAA==.Sonicast:BAAALgADCgIJAgAAAA==.Sooie:BAAALgAECgUJDQAAAA==.Soramian:BAAALgADCgcJEgAAAA==.Soulcacher:BAABLgAECn8dAAIOAAgJ8xSiSwAQAgAOAAgJ8xSiSwAQAgAAAA==.Soxxy:BAAALgAECgEJAQABLgAFFAEJAQABAAAAAA==.',
Sp='Spellgunner:BAAALgAECgcJDwAAAA==.',
St='Stormwulf:BAAALgADCgUJBQABLgADCggJDwABAAAAAA==.Strombjorn:BAABLgAECn8YAAIEAAgJQxE6CgCaAQAEAAgJQxE6CgCaAQAAAA==.',
['Sø']='Sølaria:BAAALgAECgEJAQAAAA==.',
Ta='Tasireth:BAAALgADCgcJBwAAAA==.',
Te='Tessi:BAAALgADCgEJAwAAAA==.',
Th='Thalrian:BAAALgAECgIJAgABLgAECggJIQAHADQhAA==.Thefailnym:BAAALgADCgcJBwAAAA==.Theylive:BAAALgAECgQJBgAAAA==.Thondrin:BAAALgAECgMJBAAAAA==.',
Ti='Tigerlilliy:BAAALgADCgYJEAAAAA==.Timerek:BAAALgADCgIJAgAAAA==.',
To='Toawulf:BAAALgADCgMJBgABLgADCggJDwABAAAAAA==.Toya:BAABLgAECn8bAAILAAcJShtSBwBtAQALAAcJShtSBwBtAQAAAA==.',
Tr='Trenazen:BAAALgADCgEJAQAAAA==.Trevain:BAAALgADCggJEgAAAA==.Trimasdrood:BAAALgADCgMJAwAAAA==.Trivia:BAAALgADCgYJDAAAAA==.Truthordare:BAAALgAECgYJEQAAAA==.',
Tu='Turtl:BAACLgAFFH8OAAIXAAQJRyUsAAC2AQAXAAQJRyUsAAC2AQAuAAQKfyMAAhcACQlnJjcAAPgDABcACQlnJjcAAPgDAAAA.',
Tw='Twohoof:BAAALgADCgEJAQAAAA==.',
Tx='Txìewtkuä:BAAALgADCgkJCQAAAA==.',
Ty='Tyryn:BAAALgADCgMJBAAAAA==.',
Ug='Uglydragon:BAAALgAECgcJDAAAAA==.Uglypally:BAAALgADCgkJCQAAAA==.Uglypetguy:BAAALgAECgIJAgAAAA==.Uglyrogue:BAAALgAECgQJAgAAAA==.Uglyshaman:BAAALgAECgEJAgAAAA==.',
Ul='Ulgrym:BAAALgADCgcJDAAAAA==.Ultimatia:BAAALgADCgMJBwAAAA==.',
Un='Unbalancéd:BAAALgADCgkJHAAAAA==.',
Va='Vahra:BAAALgADCggJEAAAAA==.Valanther:BAAALgAECgMJAwAAAA==.Valantis:BAAALgADCgEJAQAAAA==.Valgaskav:BAABLgAECn8SAAICAAYJHiHzPwAmAgACAAYJHiHzPwAmAgAAAA==.Valimond:BAAALgADCgkJEQABLgADCggJDwABAAAAAA==.Valric:BAAALgADCgUJBQAAAA==.Vanarrath:BAAALgADCgYJBwAAAA==.Vandryelle:BAAALgADCgIJAgAAAA==.Varge:BAAALgADCgMJAwAAAA==.Varrathos:BAAALgADCgkJCQAAAA==.Vayl:BAAALgAECgMJAwAAAA==.',
Ve='Velisa:BAAALgADCgYJBgAAAA==.Verdesoul:BAAALgADCgcJFwAAAA==.Vesyra:BAAALgAECgQJBQAAAA==.',
Vi='Viralyn:BAAALgADCgMJAwABLgAECgYJFwAfACgZAA==.',
Vo='Voidluck:BAABLgAECn8YAAIKAAgJIRFfEQB5AQAKAAgJIRFfEQB5AQAAAA==.Voker:BAAALgADCgEJAQABLgAECgMJBwABAAAAAA==.Voladis:BAAALgAECgIJAgAAAA==.Voladro:BAAALgAECgQJBAAAAA==.Volos:BAAALgAECgYJDwAAAA==.Vordaman:BAABLgAECn8dAAIOAAgJIxPOHQAtAQAOAAgJIxPOHQAtAQAAAA==.',
Vy='Vynír:BAACLgAFFH8NAAIZAAQJlBo+BQBiAQAZAAQJlBo+BQBiAQAuAAQKfyMAAxwACAnnIooNAOwBABwABQkHI4oNAOwBABkABwn0ImERAIUBAAAA.',
Wa='Waghoba:BAECLgAFFH8IAAIdAAMJWxJBAQAOAQAdAAMJWxJBAQAOAQAuAAQKfx8AAh0ABwkMIiUGAJwCAB0ABwkMIiUGAJwCAAAA.Waito:BAAALgAECgQJBAAAAA==.Wandä:BAAALgAECggJEQAAAA==.Wardriccan:BAAALgAECgUJCgAAAA==.Warrionomous:BAAALgAECgYJCQABLgAECggJFwAYAL8aAA==.Washu:BAABLgAECn8UAAMjAAcJqRpsBACUAQAjAAcJqRpsBACUAQADAAMJTAtcIQB5AAAAAA==.',
Wh='Whimlock:BAAALgADCgQJBAAAAA==.Whimzie:BAAALgADCgEJAQAAAA==.Whorphium:BAAALgAECgQJBAABLgAFFAUJDQALAHgLAA==.',
Wi='Willow:BAAALgAECgYJCgAAAA==.Wims:BAAALgAECgIJAgAAAA==.Wimz:BAAALgAFFAEJAQAAAA==.Winterous:BAAALgAECgEJAQAAAA==.',
Wo='Wonderbread:BAABLgAECn8eAAICAAgJThENGQBaAQACAAgJThENGQBaAQAAAA==.',
Wr='Wrager:BAAALgAECgUJBgAAAA==.Wrathofzaun:BAAALgAECgYJDwAAAA==.',
Wy='Wylest:BAAALgADCgcJBwAAAA==.Wynch:BAAALgAECgkJCAAAAA==.',
['Wâ']='Wârwôlf:BAAALgAECgYJEwAAAA==.',
Xe='Xenan:BAAALgAECgYJEAAAAA==.',
Xi='Xiu:BAAALgADCgEJAQAAAA==.',
Xt='Xtrolldinary:BAAALgAECgMJBgAAAA==.',
Xv='Xvp:BAAALgAECgQJBAAAAA==.',
Xy='Xylophy:BAABLgAECn8VAAIDAAcJyQ9kAwBHAQADAAcJyQ9kAwBHAQAAAA==.',
Ye='Yeastmode:BAABLgAECn8bAAIbAAgJTBrPGgBmAgAbAAgJTBrPGgBmAgAAAA==.',
Yo='Yonah:BAAALgAECgYJDAAAAA==.',
Yu='Yurc:BAAALgAECgUJDgAAAA==.',
Za='Zademan:BAAALgAECgUJBwAAAA==.Zappyu:BAAALgAECgkJBQABLgAECgkJCAABAAAAAA==.',
Ze='Zeebra:BAAALgADCggJCwAAAA==.Zeg:BAAALgADCgkJCQAAAA==.Zegafur:BAABLgAECn8ZAAIWAAYJ2R7TKwABAgAWAAYJ2R7TKwABAgAAAA==.Zeruk:BAAALgAECgcJEQAAAA==.',
Zi='Zillionbúcks:BAACLgAFFH8OAAICAAUJkBLgBQCRAQACAAUJkBLgBQCRAQAuAAQKfxoAAgIACQnvHdctAGwCAAIACQnvHdctAGwCAAAA.',
Zy='Zylcat:BAAALgAECgQJBgAAAA==.',
['Zê']='Zêddicus:BAABLgAECn8bAAMcAAYJDxZtBAARAQAcAAYJDxZtBAARAQAZAAQJjQjm0wCyAAAAAA==.',
['Áq']='Áquafina:BAABLgAECn8aAAIYAAgJSAY6IQBOAQAYAAgJSAY6IQBOAQAAAA==.',
['Îv']='Îvan:BAAALgADCggJCAAAAA==.',
['Ðö']='Ðö:BAAALgAECgYJDAAAAA==.',
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

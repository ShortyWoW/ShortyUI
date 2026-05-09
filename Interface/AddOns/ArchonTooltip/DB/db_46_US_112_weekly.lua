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

local lookup = {'Unknown-Unknown','Warrior-Fury','Druid-Balance','Druid-Restoration','Warlock-Destruction','DeathKnight-Unholy','Warrior-Protection','Shaman-Restoration','Monk-Brewmaster','DeathKnight-Frost','Hunter-BeastMastery','Warlock-Demonology','Mage-Frost','Priest-Holy','Warlock-Affliction','Rogue-Subtlety','Paladin-Protection','Paladin-Retribution','Shaman-Elemental','Shaman-Enhancement','Hunter-Marksmanship','Hunter-Survival','Monk-Windwalker','DeathKnight-Blood','Druid-Feral','Paladin-Holy','DemonHunter-Devourer','Priest-Discipline','Evoker-Devastation','DemonHunter-Vengeance','Mage-Arcane','DemonHunter-Havoc','Priest-Shadow','Druid-Guardian','Rogue-Assassination','Warrior-Arms','Monk-Mistweaver',}
local provider = {region='US',realm='Greymane',name='US',type='weekly',zone=46,date='2026-05-08',data={Aa='Aagonyy:BAAALgADCgMJAwAAAA==.',
Ae='Aernoth:BAAALgAECgUJDQAAAA==.',
Ak='Akaidia:BAAALgAECgYJBgABLgAECgYJBgABAAAAAA==.',
Al='Alderan:BAABLgAECn8XAAICAAcJCgvEJwA5AQACAAcJCgvEJwA5AQAAAA==.Aleinas:BAABLgAECn8iAAMDAAYJDhXFIwAcAQADAAYJDhXFIwAcAQAEAAQJQQhHZACSAAAAAA==.Alektophobia:BAAALgAECgcJCQAAAA==.Alendra:BAAALgAECgEJAQAAAA==.Alluisice:BAAALgAECgYJBgAAAA==.Allysaun:BAAALgADCgMJAwAAAA==.Alpharoach:BAAALgADCgYJBgAAAA==.',
Am='Amorina:BAAALgAECggJEAAAAA==.',
An='Anda:BAAALgADCgYJBgAAAA==.Andarnn:BAAALgAECgEJAQAAAA==.Andracca:BAAALgAECgUJCgAAAA==.Andromeda:BAAALgAECgMJAwAAAA==.Aner:BAAALgAECgEJBQAAAA==.Angrygnome:BAABLgAECn8cAAIFAAgJ3x8yAQCEAgAFAAgJ3x8yAQCEAgAAAA==.Angélique:BAAALgAECgYJDQABLgAFFAMJBwAGABojAA==.Antcension:BAAALgADCgUJBQAAAA==.Antemental:BAAALgAECgYJEAAAAA==.Anthigos:BAAALgAECgMJAwAAAA==.',
Ar='Arax:BAABLgAECn8YAAIHAAYJBSKTCQDaAQAHAAYJBSKTCQDaAQAAAA==.Arcamoon:BAAALgAECgIJAgABLgAECgUJBQABAAAAAA==.Arcashi:BAAALgADCgcJCgABLgAECgUJBQABAAAAAA==.Arianlion:BAAALgAECgEJAgAAAA==.Armistice:BAAALgAECgEJAgAAAA==.Arowenn:BAAALgADCgMJAwAAAA==.Arrokoth:BAAALgAECgEJAQAAAA==.Artana:BAAALgAECgIJAgAAAA==.',
As='Astolvik:BAAALgAECgQJAwAAAA==.',
At='Attachedplag:BAAALgAECgUJCAAAAA==.Atulwa:BAABLgAECn8YAAIIAAcJ3hlYKAB9AQAIAAcJ3hlYKAB9AQAAAA==.',
Au='Aurinox:BAAALgAECgEJAQAAAA==.Autodrive:BAAALgAECgUJCAAAAA==.',
Av='Avralea:BAABLgAECn8xAAIJAAgJFBt6CwAKAgAJAAgJFBt6CwAKAgAAAA==.',
Az='Azenthal:BAAALgAECgEJAQAAAA==.',
Ba='Bananahammik:BAAALgAECgYJDgAAAA==.Banzen:BAAALgAECgEJAgAAAA==.Basz:BAABLgAECn8UAAIGAAYJBBiUSABhAQAGAAYJBBiUSABhAQAAAA==.',
Be='Beginagain:BAAALgADCgMJAwAAAA==.Belgran:BAABLgAECn8WAAIKAAkJUxrRAwA9AgAKAAkJUxrRAwA9AgAAAA==.Berunma:BAABLgAECn8UAAILAAcJ2hBDWABfAQALAAcJ2hBDWABfAQAAAA==.',
Bh='Bhain:BAABLgAECn8gAAMMAAcJ0x1vMgCaAQAMAAcJ0x1vMgCaAQAFAAEJaA16dAAwAAABLgAFFAIJAwABAAAAAA==.',
Bi='Bileshots:BAAALgAECgcJCQAAAA==.Biowolf:BAACLgAFFH8JAAINAAMJCQjuTgDnAAANAAMJCQjuTgDnAAAuAAQKfyQAAg0ACAkrFZs2AMcBAA0ACAkrFZs2AMcBAAAA.Birdhunter:BAAALgAECgcJEAAAAA==.Bishopixixix:BAAALgAECgYJCwAAAA==.Bits:BAAALgAECgYJEwAAAA==.',
Bj='Bjoren:BAABLgAECn8kAAIOAAgJJyRFAgAkAwAOAAgJJyRFAgAkAwAAAA==.',
Bl='Blackdread:BAAALgADCgYJBgAAAA==.Bloodcaptain:BAABLgAECn8aAAMFAAgJIBfEAwDgAQAFAAgJJxbEAwDgAQAPAAYJshf5CAC3AQAAAA==.',
Bo='Bohma:BAAALgADCgEJAQAAAA==.Bootiebang:BAABLgAECn8VAAIQAAYJCANMJADXAAAQAAYJCANMJADXAAAAAA==.Bootycaall:BAAALgADCgkJEgAAAA==.Boroth:BAAALgADCgcJBwAAAA==.',
Br='Breetech:BAAALgAECgIJAgAAAA==.Brett:BAAALgAECgEJAQAAAA==.Breé:BAAALgADCgMJAwAAAA==.Brianx:BAAALgADCgIJAgAAAA==.Brklyn:BAAALgAFFAEJAQAAAA==.Brokki:BAAALgADCgEJAQAAAA==.',
Bu='Buckaroo:BAAALgAECgEJAQAAAA==.Buckwhild:BAAALgAECgcJDwAAAA==.Burrhus:BAAALgADCgQJAgAAAA==.',
Ca='Cagomei:BAAALgADCggJDgAAAA==.Caladbolg:BAABLgAECn8nAAMRAAcJRCIGBABRAgARAAcJRCIGBABRAgASAAEJkAPwVwEnAAAAAA==.Camrillem:BAAALgAFFAEJAQAAAA==.Cannacola:BAABLgAECn8fAAMTAAYJHB+4FgCcAQAUAAYJ1BznDQDeAQATAAYJ5xu4FgCcAQAAAA==.Carebearr:BAAALgADCgQJBAAAAA==.',
Ce='Cearius:BAAALgAECgYJCgABLgAFFAMJDQAMAGQlAA==.Cesàrè:BAAALgAECgYJDAAAAA==.',
Ch='Chahra:BAAALgAECgUJBwAAAA==.Chammie:BAAALgAECgYJBgAAAA==.Chamuki:BAAALgAECgUJCwABLgAFFAMJCAAEAJkeAA==.Cheesecake:BAACLgAFFH8HAAIGAAMJGiMNNgAwAQAGAAMJGiMNNgAwAQAuAAQKfx0AAgYACQleJcUCAK4DAAYACQleJcUCAK4DAAAA.Cheesuspiece:BAAALgADCgIJAgAAAA==.Chrispbacon:BAAALgAECgEJAgAAAA==.Chuubak:BAAALgAECgkJAwAAAA==.',
Cl='Clangedin:BAAALgAECgQJCwAAAA==.',
Co='Cobalt:BAAALgADCgUJBQABLgAECggJGQAMAKsZAA==.Coreydruid:BAAALgAECgMJBwAAAA==.Coreysham:BAAALgAECgQJBQAAAA==.Corily:BAAALgADCgUJEQAAAA==.Corsten:BAAALgAECgUJCgAAAA==.Cosmictonic:BAAALgADCgYJBgAAAA==.',
Cr='Crabpack:BAAALgADCgIJAgAAAA==.Crayoneater:BAAALgADCgIJAgAAAA==.Crippleswagg:BAAALgAECgYJAQAAAA==.Croisades:BAAALgAECgQJCgAAAA==.Crosis:BAAALgADCgYJEAAAAA==.Crowmatic:BAABLgAECn8XAAIGAAgJVx7+FABTAgAGAAgJVx7+FABTAgAAAA==.Crusadan:BAAALgADCgYJBgAAAA==.Cryo:BAAALgAECgEJAQAAAA==.',
Cu='Cute:BAABLgAFFH8FAAICAAIJzRuRHgC5AAACAAIJzRuRHgC5AAAAAA==.',
['Cà']='Càhos:BAAALgADCgUJBQAAAA==.',
Da='Dakon:BAABLgAECn83AAMRAAkJThqfAwBhAgARAAkJThqfAwBhAgASAAIJcBi3DAF9AAAAAA==.Dalune:BAAALgAECgYJEQAAAA==.Daneaus:BAABLgAECn8bAAIEAAcJsiLNCQCsAgAEAAcJsiLNCQCsAgAAAA==.Daniellson:BAABLgAECn8YAAQVAAgJKBHjLwC1AQAVAAgJKBHjLwC1AQAWAAEJPhAiOwBCAAALAAEJAABY3AAXAAABLgAFFAQJDgAXAHsjAA==.Daredevil:BAAALgADCgkJCAABLgAECggJEQABAAAAAA==.Darkchronos:BAAALgADCgcJEAAAAA==.Darkscorp:BAAALgADCgkJDgAAAA==.Darkwolf:BAABLgAECn8gAAMGAAgJVQlBSwBZAQAGAAgJ1ghBSwBZAQAYAAgJkwU8GwDsAAAAAA==.Darnuus:BAAALgAECgQJCwABLgAECgYJBgABAAAAAA==.',
Db='Dblaster:BAAALgAECgUJCwAAAA==.',
De='Deathbydruid:BAAALgAECgkJDgAAAA==.Deathnelf:BAAALgAECgYJEQAAAA==.Deazraelle:BAAALgAECgYJDgAAAA==.Decimator:BAAALgADCgcJFgAAAA==.Declan:BAAALgADCgUJBQAAAA==.Dedric:BAABLgAECn8bAAMDAAgJLATDKgDvAAADAAgJLATDKgDvAAAZAAEJBAHeOwAKAAAAAA==.Dellin:BAABLgAECn8bAAIDAAcJhBfbGgBfAQADAAcJhBfbGgBfAQAAAA==.Demeco:BAEALgAECgcJDgABLgAFFAgJFgAaAI8cAA==.Demonch:BAAALgAECgUJCAAAAA==.Depeche:BAABLgAECn8VAAIbAAYJiA9gVwD2AAAbAAYJiA9gVwD2AAAAAA==.Deralle:BAAALgAECgYJBgAAAA==.',
Di='Diminuendo:BAAALgAECgUJCAAAAA==.',
Do='Donalda:BAAALgAECgEJAQAAAA==.Dorillion:BAAALgAECgUJCQAAAA==.Dorozh:BAAALgAECggJEAAAAA==.',
Dr='Draconx:BAAALgADCgYJBgAAAA==.Draghr:BAAALgADCgkJDQAAAA==.Dragskar:BAAALgADCgUJBQAAAA==.Drala:BAABLgAECn8WAAMcAAcJTw+wFQCPAQAcAAcJTw+wFQCPAQAOAAEJ2w72ggAuAAAAAA==.Dreadmage:BAAALgADCgUJBQABLgADCgUJCQABAAAAAA==.Dreadpally:BAAALgADCgEJAQABLgADCgUJCQABAAAAAA==.Dreco:BAAALgADCgcJBwAAAA==.Driver:BAEALgAECgUJBQABLgAFFAQJCQAMAMQMAA==.Dryconias:BAABLgAECn8lAAISAAkJeRqUEgBmAgASAAkJeRqUEgBmAgAAAA==.Drèadpriest:BAAALgAECgUJEAAAAA==.Drôgô:BAABLgAECn8VAAILAAYJnhM4TgB+AQALAAYJnhM4TgB+AQAAAA==.',
Du='Dunkelzhan:BAABLgAECn8vAAINAAgJ4RlJIwAZAgANAAgJ4RlJIwAZAgAAAA==.Duntack:BAAALgADCgEJAQAAAA==.',
Dy='Dyana:BAAALgAECggJEAAAAA==.',
Dz='Dz:BAABLgAECn8sAAIaAAkJkiQ6AQBlAwAaAAkJkiQ6AQBlAwAAAA==.',
['Dø']='Dømimømmÿ:BAAALgAECgQJBAAAAA==.',
Ed='Edgyname:BAAALgAECgUJDAAAAA==.Edgyvoid:BAAALgADCgYJDAAAAA==.Edlund:BAABLgAECn8aAAIdAAcJFwoSCAAwAQAdAAcJFwoSCAAwAQAAAA==.',
Ef='Effyinzpjake:BAAALgAECgYJDgAAAA==.',
Ei='Eianistic:BAAALgADCgEJAQAAAA==.',
El='Ellinor:BAAALgADCgYJFQAAAA==.Elvy:BAABLgAECn8eAAIDAAgJeRWeJQDQAQADAAgJeRWeJQDQAQAAAA==.',
En='Enngin:BAAALgAECggJDwAAAA==.',
Er='Erebus:BAAALgAECgYJCgAAAA==.Erythra:BAAALgADCgMJAwAAAA==.',
Ev='Evildefiant:BAAALgAECgEJAQAAAA==.',
Ex='Exsalsior:BAAALgADCgYJBgAAAA==.',
Fa='Fabulousness:BAABLgAECn8UAAIOAAcJeR4NCQBcAgAOAAcJeR4NCQBcAgAAAA==.',
Fi='Fifefrost:BAAALgADCgMJAwAAAA==.Fishingsucks:BAAALgAECgEJAQAAAA==.',
Fl='Flexi:BAAALgADCgEJAQAAAA==.Flitred:BAAALgAECggJDwAAAA==.Flock:BAAALgAECgEJAQAAAA==.',
Fo='Foxx:BAAALgAECgUJCAAAAA==.',
Fr='Framboise:BAABLgAECn8ZAAICAAYJUAcRYAAwAQACAAYJUAcRYAAwAQAAAA==.Frostybolt:BAAALgAECgEJAgAAAA==.',
Fu='Furryriver:BAAALgAECgUJCAAAAA==.',
Ga='Galadhras:BAAALgADCgYJCwAAAA==.Galdryn:BAAALgADCgIJAQAAAA==.Galianna:BAAALgAECgcJDgAAAA==.Garkevon:BAAALgADCgMJAwAAAA==.',
Ge='Gemeni:BAAALgAECgEJAQAAAA==.Gevul:BAABLgAECn8oAAMMAAgJ6xP3KwC0AQAMAAgJ6xP3KwC0AQAFAAQJswhuRgCcAAAAAA==.',
Gh='Ghostess:BAAALgADCgkJAQAAAA==.Ghrank:BAAALgAECgYJCAAAAA==.',
Gi='Gilliruni:BAAALgADCgUJBQAAAA==.',
Gl='Glimley:BAAALgADCgMJAwAAAA==.',
Gn='Gnorst:BAAALgADCgkJCgAAAA==.',
Go='Goreolio:BAAALgADCgkJDwABLgAECgYJEQABAAAAAA==.',
Gr='Grandmatank:BAAALgADCgkJCQAAAA==.Grasshopaa:BAAALgADCgYJCQAAAA==.Grassy:BAAALgADCgkJCQAAAA==.Gremz:BAABLgAECn8iAAIeAAgJ2gqpCgAkAQAeAAgJ2gqpCgAkAQAAAA==.Grozny:BAAALgADCgYJBgAAAA==.Grày:BAABLgAECn8hAAIGAAgJvxmMGwAkAgAGAAgJvxmMGwAkAgAAAA==.',
Gu='Gumboslice:BAABLgAECn8XAAIEAAcJwBrgFAAgAgAEAAcJwBrgFAAgAgAAAA==.Gusgus:BAAALgAECgUJBQAAAA==.',
['Gä']='Gändälf:BAABLgAECn8WAAIfAAcJUhcSAwCXAQAfAAcJUhcSAwCXAQAAAA==.',
Ha='Habanero:BAABLgAECn8ZAAMIAAcJWA0hOAAoAQAIAAcJWA0hOAAoAQATAAMJ7BvHMADwAAAAAA==.Hachedev:BAAALgAECgMJCAAAAA==.Hadtopandadk:BAAALgAECgEJAQAAAA==.Hallia:BAABLgAECn8rAAIEAAkJVROQGgDvAQAEAAkJVROQGgDvAQAAAA==.Hark:BAAALgADCgYJEQAAAA==.Hawgwild:BAAALgAECgQJDAAAAA==.',
He='Headdinks:BAAALgADCgcJDAAAAA==.Healvisprsly:BAAALgAECgcJEAAAAA==.Heisenberg:BAAALgADCgMJAwABLgAECgEJAwABAAAAAA==.Helena:BAABLgAECn8uAAMSAAkJ1R5PCQDBAgASAAkJ1R5PCQDBAgARAAgJ0xqVBwBkAgAAAA==.Heliarc:BAAALgADCgYJFQAAAA==.',
Hi='Highfive:BAAALgAECgUJCQAAAA==.',
Ho='Holybeech:BAAALgAECgQJBAAAAA==.Honestly:BAAALgAECgQJBAAAAA==.Honkytonkman:BAAALgADCgQJBAAAAA==.Hover:BAAALgAECgYJEQAAAA==.',
Ih='Ihmoen:BAAALgADCgYJBgAAAA==.',
Il='Illuminate:BAAALgADCgQJBAAAAA==.Illustria:BAAALgADCgYJDwAAAA==.Illustriâ:BAAALgADCgYJBgABLgADCgYJDwABAAAAAA==.',
In='Insidious:BAABLgAECn8cAAIYAAgJRhpjCAAAAgAYAAgJRhpjCAAAAgAAAA==.Invoke:BAAALgADCgEJAQAAAA==.',
Ir='Irs:BAAALgADCgIJAgAAAA==.',
It='Itchyfeet:BAAALgADCgUJBQABLgAECggJIAANAHgkAA==.Itchymage:BAABLgAECn8gAAINAAgJeCQvHQABAwANAAgJeCQvHQABAwAAAA==.',
Ja='Jacckiemoon:BAAALgAECgMJAwAAAA==.Jadehunterr:BAAALgAECgMJBAAAAA==.Jaesn:BAAALgADCgYJBgAAAA==.',
Je='Jenae:BAAALgAECgEJAQAAAA==.Jenövha:BAAALgADCgkJFwAAAA==.Jezebelle:BAAALgADCgkJGgAAAA==.',
Ji='Jigs:BAABLgAECn8gAAILAAYJ7xBGRgA6AQALAAYJ7xBGRgA6AQAAAA==.Jiräiya:BAAALgADCgYJBgAAAA==.',
Jo='Johastrasz:BAAALgADCggJCAAAAA==.',
Ju='Junsing:BAAALgADCgEJAQABLgAECgYJBgABAAAAAA==.',
['Jå']='Jåfar:BAAALgADCgEJAgAAAA==.',
Ka='Kaladriel:BAAALgADCgEJAQAAAA==.Kaldrick:BAAALgADCgkJCgAAAA==.Kamstareater:BAABLgAECn8VAAIbAAcJsRN1OgBMAQAbAAcJsRN1OgBMAQAAAA==.Kanakas:BAAALgAECgcJEQAAAA==.Kanaloa:BAABLgAECn8bAAINAAcJfgdCcwAqAQANAAcJfgdCcwAqAQAAAA==.Kayler:BAAALgAECgYJBgAAAA==.',
Ke='Kegerator:BAAALgAECgEJAQAAAA==.Keirin:BAAALgAECggJEAAAAA==.Keldica:BAAALgAECgIJAgAAAA==.Kelysa:BAAALgADCgkJDQAAAA==.Kenshan:BAAALgADCgcJCgAAAA==.Kevinbox:BAAALgAECgYJDQAAAA==.Kevinslayer:BAAALgAECgUJDAAAAA==.Keynaridan:BAABLgAECn8UAAIbAAcJAxN2NABkAQAbAAcJAxN2NABkAQAAAA==.Keyss:BAAALgADCgIJAgAAAA==.',
Kg='Kglizard:BAAALgAECgUJCAAAAA==.',
Kh='Khalinor:BAABLgAECn8VAAIaAAcJsA9xIQB8AQAaAAcJsA9xIQB8AQAAAA==.Khardun:BAAALgAECgEJAQAAAA==.Khotuhn:BAAALgADCgkJFAAAAA==.',
Ki='Kickazdin:BAAALgAFFAEJAQAAAA==.Kiryie:BAAALgAECgUJBwAAAA==.Kisäme:BAAALgADCgkJCQAAAA==.',
Kl='Klad:BAAALgADCgYJBgAAAA==.Kluma:BAAALgAECgEJAQAAAA==.',
Kn='Knok:BAAALgAECggJCAAAAA==.',
Ko='Kobu:BAAALgADCgUJBgAAAA==.Konran:BAAALgADCgEJAQAAAA==.',
Kr='Kraigen:BAABLgAECn8bAAIgAAcJUxoyDAC+AQAgAAcJUxoyDAC+AQAAAA==.Krinack:BAABLgAECn8YAAIQAAgJkQwyEACjAQAQAAgJkQwyEACjAQAAAA==.Krixiz:BAAALgAECgYJCgAAAA==.',
Ku='Kurindrixx:BAAALgADCgIJAgAAAA==.Kurtakum:BAAALgADCgMJAwAAAA==.',
Kw='Kwarify:BAAALgADCgEJAQAAAA==.',
Ky='Kynasmira:BAAALgADCgYJEAAAAA==.Kyrsh:BAAALgADCgcJEAAAAA==.',
La='Ladrona:BAAALgAECgYJCgAAAA==.Lailyre:BAAALgAECgYJBQABLgAECgYJBgABAAAAAA==.Lassan:BAAALgAECgQJBwAAAA==.Later:BAAALgAECgcJBwAAAA==.Latimir:BAAALgADCgcJCQAAAA==.Laur:BAAALgADCgYJBgAAAA==.Lavendeer:BAABLgAECn8XAAIDAAcJ1Q2MJQAQAQADAAcJ1Q2MJQAQAQAAAA==.Laylana:BAAALgADCgIJAgABLgADCgUJCQABAAAAAA==.Lazyeye:BAAALgADCgUJBAABLgAECgYJBgABAAAAAA==.',
Lb='Lb:BAAALgADCgEJAQABLgAECgUJBQABAAAAAA==.',
Le='Legume:BAAALgADCgcJCAABLgAECgUJDQABAAAAAA==.Legzanot:BAACLgAFFH8IAAITAAMJmwqaGwDSAAATAAMJmwqaGwDSAAAuAAQKfyQAAhMACAkzGCEdACgCABMACAkzGCEdACgCAAAA.Leonceault:BAAALgAECgEJAQAAAA==.',
Li='Lifebringa:BAABLgAECn8WAAMOAAUJ5B/AMwBwAQAOAAUJ5B/AMwBwAQAhAAQJCREMNAC+AAAAAA==.Lightningfox:BAAALgAECgYJDgAAAA==.Lightsfallen:BAAALgAECgEJAQAAAA==.Lileth:BAAALgAECgYJBAAAAA==.Limzzmagus:BAAALgAECgMJBgAAAA==.Lithia:BAAALgAECgUJBwAAAA==.Littlemo:BAAALgAECgUJCAAAAA==.',
Lo='Loggs:BAAALgAFFAEJAQAAAA==.Lohnar:BAAALgAECgUJCAAAAA==.',
Lu='Lucidslock:BAAALgADCgIJAgAAAA==.Lucielbaal:BAABLgAECn8bAAIMAAcJWBnXKwC1AQAMAAcJWBnXKwC1AQAAAA==.Luciferus:BAAALgAECgQJBAABLgAECggJHgAWAHwOAA==.Luckystop:BAAALgAECgQJBAAAAA==.Lunareth:BAAALgADCgUJBQAAAA==.Luraris:BAAALgADCgMJAwAAAA==.',
Ly='Lyrska:BAABLgAECn8WAAIWAAYJdwwBGQBBAQAWAAYJdwwBGQBBAQAAAA==.Lytearrow:BAABLgAECn8WAAILAAcJrQySSQAwAQALAAcJrQySSQAwAQAAAA==.',
['Lé']='Léaf:BAAALgAECgMJAwAAAA==.',
Ma='Mahrylee:BAAALgAECgcJEAAAAA==.Maiya:BAAALgADCgcJCgAAAA==.Majutsu:BAAALgADCgEJAQABLgADCgcJDgABAAAAAA==.Malbrax:BAAALgAECggJDwAAAA==.Maleficents:BAABLgAECn8YAAIDAAYJqwznRQAWAQADAAYJqwznRQAWAQAAAA==.Malurius:BAAALgAECgcJEwAAAA==.Malware:BAAALgAECgYJEQAAAA==.Manana:BAAALgADCgEJAQAAAA==.Manbearpally:BAAALgAECgQJBAAAAA==.Manikfury:BAABLgAECn8bAAMEAAcJXB8OGQD8AQAEAAYJYx4OGQD8AQAZAAcJ4RpFBgDkAQAAAA==.Maniksmage:BAAALgADCgUJDAABLgAECgcJGwAEAFwfAA==.Mannypack:BAAALgAECggJEAAAAA==.Maranelli:BAAALgADCgYJBgAAAA==.Maseles:BAAALgAECgEJAQABLgAECgUJCQABAAAAAA==.Maxiticon:BAAALgADCgUJBQAAAA==.',
Mc='Mcdawg:BAAALgADCgQJBAAAAA==.Mcleary:BAAALgADCgYJDAAAAA==.',
Me='Melinashala:BAABLgAECn8UAAIMAAYJEwMhjwClAAAMAAYJEwMhjwClAAAAAA==.Mending:BAAALgAECgUJBQAAAA==.Meowinator:BAAALgAECgQJBQAAAA==.',
Mi='Miler:BAAALgAECgQJBgAAAA==.Misanth:BAAALgAECgYJDgAAAA==.Mistdruid:BAAALgAECgIJAwABLgAECgIJBgABAAAAAA==.',
Mo='Moemo:BAABLgAECn8XAAIEAAcJqiF2CwCSAgAEAAcJqiF2CwCSAgAAAA==.Mogryn:BAAALgAECgYJBgAAAA==.Moistymists:BAAALgAECgYJCQAAAA==.Mommybree:BAAALgAECgQJBAAAAA==.Monksterz:BAABLgAECn8kAAIJAAgJviDHBACcAgAJAAgJviDHBACcAgAAAA==.Monoxidê:BAAALgAECgEJAQAAAA==.Morsecode:BAAALgAECgcJDwABLgABCgIJAgABAAAAAA==.Morthok:BAABLgAECn8bAAIMAAcJaBJYOACEAQAMAAcJaBJYOACEAQAAAA==.Mortischa:BAAALgADCggJCAAAAA==.Mosh:BAAALgAECgcJEQAAAA==.',
Mu='Muchuchu:BAAALgAECgQJDQABLgAECgEJAQABAAAAAA==.Muldern:BAAALgADCgEJAQAAAA==.Munkee:BAAALgAECgYJEQAAAA==.Murdinbronze:BAAALgADCgUJCAAAAA==.Musyl:BAAALgADCgEJAQABLgAECgYJEQABAAAAAA==.',
['Mã']='Mãf:BAAALgAECgYJEwAAAA==.',
['Mí']='Místwalker:BAAALgAECgIJBgAAAA==.',
Na='Nackthyr:BAACLgAFFH8IAAIdAAMJviQBAgBJAQAdAAMJviQBAgBJAQAuAAQKfzcAAh0ACQn+JRQAAIkDAB0ACQn+JRQAAIkDAAAA.Nafir:BAAALgADCgYJEQAAAA==.Narlin:BAAALgAECgIJAwAAAA==.Nasta:BAAALgAECgIJAgAAAA==.Natureboi:BAAALgADCgQJBAABLgADCgYJDAABAAAAAA==.Nazareths:BAAALgAECgQJCAAAAA==.Nazgor:BAAALgAECgMJAwAAAA==.',
Ne='Neckromancy:BAAALgADCgcJBwAAAA==.Necrosius:BAAALgAECgQJBwAAAA==.Neonarc:BAEALgADCgYJDgAAAA==.Neshi:BAAALgAECgMJBQAAAA==.Neuman:BAAALgADCgEJAQAAAA==.',
Ni='Nibblemah:BAAALgADCgkJCwAAAA==.Nightsbane:BAAALgADCgcJCgAAAA==.Nivdk:BAAALgADCgYJBgABLgAECgYJEQABAAAAAA==.Nivora:BAAALgAECgYJEQAAAA==.',
No='Notsure:BAAALgAECgEJAgAAAA==.',
Ny='Nyxstalia:BAAALgAECgUJDAAAAA==.Nyyx:BAABLgAECn8TAAIbAAcJTQV3aADLAAAbAAcJTQV3aADLAAAAAA==.',
Ol='Olmek:BAACLgAFFH8PAAICAAUJZw/1DAA4AQACAAUJZw/1DAA4AQAuAAQKfxUAAgIABwl2IiMeAF4CAAIABwl2IiMeAF4CAAAA.',
Op='Opalana:BAAALgADCgIJAwAAAA==.Oprahwndfury:BAAALgAECgEJAgAAAA==.',
Or='Orasaya:BAAALgADCgYJBgAAAA==.Orphee:BAAALgADCgcJBwAAAA==.Orzanis:BAAALgADCgcJDgAAAA==.',
Pa='Paige:BAAALgADCgcJDgAAAA==.Palasades:BAAALgADCgUJBQAAAA==.Pallymarc:BAAALgADCgYJBgAAAA==.Pallytune:BAAALgAFFAIJAgAAAA==.Pandalorian:BAAALgAECgYJCgAAAA==.Pandamajack:BAAALgAECgMJAwAAAA==.',
Ph='Philandre:BAAALgAECgIJAgAAAA==.',
Pi='Picoso:BAABLgAECn8XAAINAAcJuwdrbwAyAQANAAcJuwdrbwAyAQAAAA==.Piianca:BAAALgADCgcJBwAAAA==.Piianna:BAAALgAECgYJEgAAAA==.Pirko:BAAALgADCggJCwAAAA==.',
Po='Pocketheal:BAAALgADCgkJCQAAAA==.',
Pu='Punch:BAAALgAECgEJAgAAAA==.Purplerain:BAAALgAECgEJAQAAAA==.Putrigord:BAAALgAECgQJCQAAAA==.',
Qi='Qik:BAAALgADCgcJBwAAAA==.Qikkaw:BAAALgAECgYJEgAAAA==.Qitetsu:BAAALgAECgUJBgAAAA==.',
Qu='Quantos:BAABLgAECn8VAAIiAAYJmxT9EABmAQAiAAYJmxT9EABmAQAAAA==.Ququmatz:BAAALgADCgMJAwAAAA==.',
Ra='Raatha:BAAALgAECgcJDwAAAA==.Raganar:BAAALgAECgYJEQAAAA==.Ranlerodis:BAAALgADCgMJAwAAAA==.Rayjean:BAAALgADCgYJFQAAAA==.',
Re='Redneckboots:BAAALgADCgEJAQAAAA==.Relmax:BAAALgAECggJEAAAAA==.Rendeminae:BAAALgADCgcJBwAAAA==.Renri:BAAALgAECgcJBwAAAA==.Repose:BAAALgAECgIJAwAAAA==.Revick:BAAALgAECgUJCAAAAA==.Revil:BAAALgADCgIJAgAAAA==.',
Rh='Rhaenýs:BAAALgADCgcJDQAAAA==.Rhonwynn:BAAALgAECgYJEQAAAA==.',
Ri='Rikershipdwn:BAAALgAECggJEAAAAA==.Rimish:BAAALgAECgEJAQABLgAECgkJHgAjAHMYAA==.Rimrave:BAABLgAECn8bAAQHAAcJ3h4BDACmAQACAAYJIxsZNQDVAQAHAAYJhh0BDACmAQAkAAUJgg+LGwDZAAAAAA==.Ripavicii:BAAALgAECgEJAQAAAA==.Ritobeans:BAAALgADCgYJFQAAAA==.Rivik:BAAALgADCgkJGgAAAA==.',
Ro='Robbstark:BAAALgAECgYJDAAAAA==.Robertkenway:BAABLgAECn8eAAMWAAgJfA4PDgDGAQAWAAgJfA4PDgDGAQALAAEJAADV1AAwAAAAAA==.Roguebot:BAAALgADCgkJEgAAAA==.Rohdaric:BAABLgAECn8ZAAIWAAYJUxSaGQA6AQAWAAYJUxSaGQA6AQAAAA==.Rokte:BAAALgAECgUJBwAAAA==.Rook:BAAALgAECgcJEgAAAA==.Rosekenway:BAAALgAECgYJDgABLgAECggJHgAWAHwOAA==.',
Rr='Rratt:BAAALgAECgMJAwAAAA==.',
Ru='Rubimoon:BAAALgAECgUJBQAAAA==.Rumí:BAAALgADCgUJCQAAAA==.Running:BAAALgADCgUJBgAAAA==.',
Sa='Saammiee:BAAALgAECgIJAgAAAA==.Sabiha:BAABLgAECn8UAAMLAAYJZg+nZQA2AQALAAYJZg+nZQA2AQAVAAEJwQPllAAlAAAAAA==.Saintotem:BAAALgAECgcJDAAAAA==.Samartyr:BAAALgAECgUJCAAAAA==.Sammiiee:BAAALgADCgQJBAABLgAECgIJAgABAAAAAA==.Sangwynaris:BAAALgADCgYJCQAAAA==.Saphiiraa:BAAALgAECgYJDAAAAA==.Sayahealer:BAAALgADCgcJDgAAAA==.',
Sc='Scorpmage:BAAALgAECgYJEgAAAA==.Scramms:BAAALgADCgcJDQAAAA==.Scrams:BAABLgAECn8VAAIVAAcJpgyZCwA0AQAVAAcJpgyZCwA0AQAAAA==.',
Se='Sedrick:BAABLgAECn8kAAIaAAgJHB+nBQDKAgAaAAgJHB+nBQDKAgAAAA==.Sekendipity:BAAALgADCgEJAQABLgAECgYJBgABAAAAAA==.Sekhmett:BAAALgADCgMJAwAAAA==.Sekndestroy:BAAALgADCgYJCQABLgAECgYJBgABAAAAAA==.Sektacular:BAAALgADCgQJBAABLgAECgYJBgABAAAAAA==.Sekzen:BAAALgAECgYJBgAAAA==.Semiazas:BAABLgAECn8cAAQPAAcJvg8aBgBZAQAPAAcJvg8aBgBZAQAMAAUJ2QmbtwDpAAAFAAEJAADwegAnAAAAAA==.Semiazes:BAAALgADCgYJBgAAAA==.Senessa:BAAALgADCgIJAgAAAA==.Sensy:BAAALgADCgQJBAAAAA==.Seumas:BAAALgADCgMJAwAAAA==.',
Sh='Shadrock:BAAALgADCgYJBgAAAA==.Shayrisa:BAABLgAECn8kAAMIAAgJ4BAeKwBtAQAIAAgJ4BAeKwBtAQATAAYJNBFzJwAgAQAAAA==.Shazool:BAAALgAECgUJBwABLgAECgkJKwAEAFUTAA==.Sheep:BAAALgAECgYJDwAAAA==.Shifterz:BAAALgAECgUJBwAAAA==.Shrubbery:BAAALgAECggJEAAAAA==.Shxdow:BAAALgAECgQJBAAAAA==.',
Si='Sind:BAAALgAECgEJAQABLgAECggJFAAiAIEMAA==.Sindella:BAAALgADCgIJAgABLgAECggJFAAiAIEMAA==.Sinna:BAAALgADCgUJCQAAAA==.Sinthorne:BAABLgAECn8UAAMiAAgJgQw+EgDlAAAiAAYJAhA+EgDlAAAZAAMJ8AVBHgBpAAAAAA==.',
Sk='Skedaddle:BAAALgAECgQJCAABLgAECgYJHwANAPUhAA==.Skithíryx:BAAALgAECgIJAgABLgAECgYJCwABAAAAAA==.',
Sl='Slashbndcoot:BAAALgADCgMJAwAAAA==.Slashgquit:BAACLgAFFH8KAAIYAAMJCB71CwAWAQAYAAMJCB71CwAWAQAuAAQKfywAAhgACAlGJTYCANcCABgACAlGJTYCANcCAAAA.Slumbermist:BAABLgAECn8kAAMXAAgJQREjEwCaAQAXAAgJQREjEwCaAQAlAAYJihKoLQBLAQABLgABCgIJAgABAAAAAA==.',
So='Solaire:BAABLgAECn8XAAMRAAcJdBjqCwB+AQARAAcJdBjqCwB+AQAaAAEJexTVXgA4AAABLgAECggJIgAXAHsfAA==.Soras:BAAALgADCgYJFQAAAA==.',
St='Steph:BAAALgADCgYJDAAAAA==.',
Su='Sunareas:BAAALgADCgIJAgAAAA==.',
Sy='Synthetic:BAAALgAECgYJEAAAAA==.',
Sz='Szasstaam:BAABLgAECn8VAAIfAAcJewciBgD9AAAfAAcJewciBgD9AAAAAA==.',
['Sé']='Séékér:BAAALgADCgcJFQAAAA==.',
Ta='Talanith:BAAALgADCggJEAAAAA==.Taxal:BAAALgADCgYJBwAAAA==.Taxlock:BAABLgAECn8aAAIMAAcJ8AlYUQA2AQAMAAcJ8AlYUQA2AQAAAA==.',
Tb='Tbagjones:BAAALgAECgQJBAAAAA==.',
Te='Tecsaran:BAAALgAECgYJEwAAAA==.Tekis:BAAALgADCgEJAQAAAA==.Terania:BAAALgADCgIJAgAAAA==.',
Th='Thalira:BAAALgAECgcJDwAAAA==.',
Ti='Tiger:BAACLgAFFH8xAAMZAAkJECUBAACwAwAZAAkJECUBAACwAwAEAAMJxhYqFwCoAAAuAAQKfyUAAxkACQnqJgUAABYEABkACQnqJgUAABYEAAQAAQm1C4LEAD8AAAAA.Tinnea:BAAALgAECgUJCQAAAA==.Titanosaurus:BAAALgAECgUJCAAAAA==.Tizzly:BAABLgAECn8nAAINAAgJCQ5hSgCJAQANAAgJCQ5hSgCJAQAAAA==.',
To='Torhilda:BAAALgAECgYJBgAAAA==.Torridwells:BAAALgAECgUJBwAAAA==.',
Tr='Trad:BAAALgADCgYJBgAAAA==.Troag:BAAALgAECgYJCwAAAA==.Troagstar:BAAALgAECgYJEQAAAA==.',
Ts='Tsaesci:BAAALgADCgQJBgAAAA==.Tsynn:BAAALgADCgYJEQAAAA==.',
Ty='Tyraana:BAABLgAECn8pAAMgAAgJLxzBDAC1AQAgAAcJfB/BDAC1AQAbAAgJSBCXLQCBAQAAAA==.Tyrinwar:BAAALgADCgYJDAAAAA==.Tyrmog:BAAALgAECgcJCwAAAA==.Tytus:BAAALgADCgIJAgAAAA==.',
Us='Ushas:BAABLgAECn8dAAIOAAgJ8BerJADDAQAOAAgJ8BerJADDAQAAAA==.',
Va='Vali:BAABLgAECn8bAAIVAAcJLx6VAwAbAgAVAAcJLx6VAwAbAgAAAA==.Valindrea:BAAALgAECgUJCAAAAA==.Vasrael:BAABLgAECn8bAAMaAAcJYRzcDABHAgAaAAcJYRzcDABHAgASAAEJ2xQaPwE1AAAAAA==.Vav:BAABLgAECn8UAAMLAAYJdhcoTQAmAQALAAYJdhcoTQAmAQAWAAIJsgwzOwBCAAAAAA==.',
Ve='Vecnis:BAAALgAECgIJAgAAAA==.Veliette:BAAALgAECgIJAgAAAA==.',
Vi='Vithper:BAAALgAECgcJCwAAAA==.',
Vn='Vnia:BAAALgADCgMJAwAAAA==.',
Vo='Voidmuffinz:BAABLgAECn8aAAIbAAkJ1xcRFQATAgAbAAkJ1xcRFQATAgAAAA==.',
Vy='Vynis:BAAALgAECgcJDQABLgAFFAIJAgABAAAAAA==.Vyrahildard:BAABLgAECn8bAAISAAcJrBlEOwCUAQASAAcJrBlEOwCUAQAAAA==.',
Wa='Wakkiq:BAAALgADCgkJCQAAAA==.Waringoutlaw:BAAALgADCgkJCQAAAA==.Wasteland:BAABLgAECn8dAAIYAAkJzQ1PDwB+AQAYAAkJzQ1PDwB+AQAAAA==.',
We='Weaselhunter:BAAALgAECgIJAgABLgAECgcJEQABAAAAAA==.Weasellock:BAAALgAECgcJEQAAAA==.Weaselmage:BAAALgAECgYJDAABLgAECgcJEQABAAAAAA==.Welor:BAAALgADCgYJDAAAAA==.',
Wh='Whatthef:BAAALgAECgEJAQAAAA==.',
Wi='Wildweasel:BAAALgAECgQJBQABLgAECgcJEQABAAAAAA==.Winterhide:BAABLgAECn8bAAIGAAcJgxMDPACKAQAGAAcJgxMDPACKAQAAAA==.',
Xa='Xallie:BAEBLgAECn8pAAIbAAkJTRZ1EwAhAgAbAAkJTRZ1EwAhAgAAAA==.Xanvyr:BAABLgAECn8gAAISAAgJvRpzHgARAgASAAgJvRpzHgARAgAAAA==.Xaquillis:BAACLgAFFH8HAAMGAAMJuw1YVADlAAAGAAMJuw1YVADlAAAKAAEJqwUaCgBIAAAuAAQKfyIAAwYACAmMGyI8AEcCAAYACAmMGyI8AEcCAAoAAQnZDsQWADEAAAAA.Xarthis:BAAALgAECgEJAQABLgAFFAMJBwAGALsNAA==.',
Xe='Xentrie:BAAALgADCgUJCgAAAA==.Xeyvara:BAABLgAECn8bAAIeAAcJ1CKQAgBNAgAeAAcJ1CKQAgBNAgAAAA==.',
Xg='Xg:BAAALgADCgUJBgABLgAECgYJHwATABwfAA==.',
Ya='Yatsui:BAAALgAECgQJBAAAAA==.',
Yo='Youngthug:BAAALgAECgIJAwAAAA==.',
Yu='Yutaa:BAAALgADCgYJBgAAAA==.',
Za='Zarihanna:BAABLgAECn8pAAINAAgJ9hOrPACyAQANAAgJ9hOrPACyAQAAAA==.Zatannah:BAAALgADCgUJBQAAAA==.',
Ze='Zedryn:BAABLgAECn8WAAIMAAcJrQeCWAAkAQAMAAcJrQeCWAAkAQAAAA==.Zenshi:BAAALgAECgEJAQAAAA==.Zeperios:BAAALgAECgQJBQAAAA==.Zeril:BAAALgAECgcJDgAAAA==.Zestull:BAABLgAECn8bAAIJAAcJGiRRBgB0AgAJAAcJGiRRBgB0AgAAAA==.Zetsudeath:BAAALgADCgYJBgAAAA==.',
Zh='Zhoel:BAAALgADCgEJAQAAAA==.',
Zi='Zindeshal:BAAALgAECgQJBAAAAA==.',
Zo='Zorc:BAACLgAFFH8FAAITAAMJvRCmGgDaAAATAAMJvRCmGgDaAAAuAAQKfyMAAhMACQkaIPkJAPQCABMACQkaIPkJAPQCAAAA.',
Zu='Zunji:BAAALgAECgEJAwAAAA==.',
Zy='Zyate:BAABLgAECn8xAAIMAAkJTBJcHAAGAgAMAAkJTBJcHAAGAgAAAA==.Zyrryn:BAABLgAECn8WAAIdAAcJwgPiCwDXAAAdAAcJwgPiCwDXAAAAAA==.',
['Ër']='Ërëbus:BAAALgADCgQJBAAAAA==.',
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

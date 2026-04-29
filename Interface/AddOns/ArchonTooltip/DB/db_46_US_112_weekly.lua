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

local lookup = {'Druid-Balance','Unknown-Unknown','Warlock-Destruction','DeathKnight-Unholy','Monk-Brewmaster','Warlock-Demonology','Mage-Frost','Priest-Holy','Paladin-Protection','Paladin-Retribution','Druid-Restoration','Hunter-Marksmanship','Hunter-Survival','Hunter-BeastMastery','Monk-Windwalker','Paladin-Holy','Warrior-Fury','DemonHunter-Vengeance','Shaman-Elemental','Evoker-Devastation','Warlock-Affliction','Shaman-Restoration','DeathKnight-Blood','Monk-Mistweaver','Druid-Feral','DemonHunter-Havoc','DemonHunter-Devourer',}
local provider = {region='US',realm='Greymane',name='US',type='weekly',zone=46,date='2026-04-24',data={Aa='Aagonyy:BAAALgADCgMJAwAAAA==.',
Ae='Aernoth:BAAALgAECgUJDAAAAA==.',
Al='Alderan:BAAALgAECgUJCgAAAA==.Aleinas:BAABLgAECn8VAAIBAAYJzRPkNQBlAQABAAYJzRPkNQBlAQAAAA==.Alektophobia:BAAALgAECgUJBQAAAA==.Alendra:BAAALgAECgEJAQAAAA==.Alluisice:BAAALgAECgYJBgAAAA==.Alpharoach:BAAALgADCgYJBgABLgAECgIJAgACAAAAAA==.',
Am='Amorina:BAAALgAECgUJBQAAAA==.',
An='Andarnn:BAAALgAECgEJAQAAAA==.Andracca:BAAALgAECgMJAwAAAA==.Andromeda:BAAALgADCgkJDgAAAA==.Aner:BAAALgAECgEJAwAAAA==.Angrygnome:BAABLgAECn8UAAIDAAYJPx99CgAXAgADAAYJPx99CgAXAgAAAA==.Angélique:BAAALgAECgQJBAABLgAECgkJGQAEAOQkAA==.Antcension:BAAALgADCgUJBQAAAA==.Antemental:BAAALgAECgYJEAAAAA==.Anthigos:BAAALgAECgIJAgAAAA==.',
Ar='Arax:BAAALgAECgUJDQAAAA==.Arcamoon:BAAALgADCgcJCAABLgADCgcJCgACAAAAAA==.Arcashi:BAAALgADCgcJCgAAAA==.Arianlion:BAAALgAECgEJAgAAAA==.Armistice:BAAALgAECgEJAQAAAA==.Arowenn:BAAALgADCgMJAwAAAA==.Arrokoth:BAAALgAECgEJAQAAAA==.Artana:BAAALgAECgIJAgAAAA==.',
At='Attachedplag:BAAALgADCgkJDgAAAA==.Atulwa:BAAALgAECgcJEgAAAA==.',
Au='Aurinox:BAAALgAECgEJAQAAAA==.Autodrive:BAAALgAECgUJCAAAAA==.',
Av='Avralea:BAABLgAECn8cAAIFAAgJtRfWKADBAQAFAAgJtRfWKADBAQAAAA==.',
Az='Azenthal:BAAALgAECgEJAQAAAA==.',
Ba='Bananahammik:BAAALgAECgYJDgAAAA==.Banzen:BAAALgADCgYJBwAAAA==.Basz:BAAALgAECgQJCgAAAA==.',
Be='Belgran:BAAALgAECggJEQAAAA==.Berunma:BAAALgAECgYJCwAAAA==.',
Bh='Bhain:BAABLgAECn8gAAMGAAcJ0x2XDQCoAQAGAAcJ0x2XDQCoAQADAAEJaA11dAAwAAAAAA==.',
Bi='Bileshots:BAAALgAECgUJBQAAAA==.Biowolf:BAABLgAECn8bAAIHAAgJWBN4EAC+AQAHAAgJWBN4EAC+AQAAAA==.Birdhunter:BAAALgAECgcJBwAAAA==.Bishopixixix:BAAALgAECgUJCgAAAA==.Bits:BAAALgAECgQJBwAAAA==.',
Bj='Bjoren:BAABLgAECn8UAAIIAAYJBSWODQCAAgAIAAYJBSWODQCAAgAAAA==.',
Bl='Blackdread:BAAALgADCgYJBgAAAA==.Bloodcaptain:BAAALgAECggJEgAAAA==.',
Bo='Bohma:BAAALgADCgEJAQAAAA==.Bootiebang:BAAALgAECgUJCgAAAA==.Bootycaall:BAAALgADCgkJCQAAAA==.Boroth:BAAALgADCgcJBwAAAA==.',
Br='Breetech:BAAALgAECgIJAgAAAA==.Brett:BAAALgAECgEJAQAAAA==.Breé:BAAALgADCgMJAwAAAA==.Brianx:BAAALgADCgIJAgAAAA==.Brklyn:BAAALgAFFAEJAQAAAA==.Brokki:BAAALgADCgEJAQAAAA==.',
Bu='Buckaroo:BAAALgAECgEJAQAAAA==.Buckwhild:BAAALgAECgYJCAAAAA==.Burrhus:BAAALgADCgQJAgAAAA==.',
Ca='Cagomei:BAAALgADCggJDgAAAA==.Caladbolg:BAABLgAECn8YAAMJAAcJfBOmEQCtAQAJAAcJfBOmEQCtAQAKAAEJkAPWVwEnAAAAAA==.Camrillem:BAAALgAECgQJCQAAAA==.Cannacola:BAAALgAECgYJDgAAAA==.',
Ce='Cearius:BAAALgAECgYJCgABLgAFFAMJBwAGAEgkAA==.',
Ch='Chahra:BAAALgADCgkJEwAAAA==.Chammie:BAAALgADCgUJCAAAAA==.Chamuki:BAAALgAECgMJAwABLgAECgkJJwALAAQhAA==.Cheesecake:BAABLgAECn8ZAAIEAAkJ5CTHAgCuAwAEAAkJ5CTHAgCuAwAAAA==.Cheesuspiece:BAAALgADCgIJAgAAAA==.Chrispbacon:BAAALgADCgMJBQAAAA==.Chuubak:BAAALgAECgEJAQAAAA==.',
Cl='Clangedin:BAAALgAECgMJBAAAAA==.',
Co='Cobalt:BAAALgADCgUJBQABLgAECgYJCgACAAAAAA==.Coreydruid:BAAALgAECgMJBQAAAA==.Coreysham:BAAALgAECgIJAgAAAA==.Corily:BAAALgADCgQJDQAAAA==.Corsten:BAAALgAECgUJBgAAAA==.Cosmictonic:BAAALgADCgYJBgAAAA==.',
Cr='Crabpack:BAAALgADCgIJAgAAAA==.Croisades:BAAALgAECgMJBgAAAA==.Crosis:BAAALgADCgYJEAAAAA==.Crowmatic:BAAALgAECgcJDQAAAA==.Crusadan:BAAALgADCgYJBgAAAA==.Cryo:BAAALgAECgEJAQAAAA==.',
Cu='Cute:BAAALgAECgYJCgAAAA==.',
['Cà']='Càhos:BAAALgADCgUJBQAAAA==.',
Da='Dakon:BAABLgAECn8lAAMJAAgJDxtNAgDXAQAJAAgJbxpNAgDXAQAKAAIJcBinDAF9AAAAAA==.Dalune:BAAALgAECgMJBwAAAA==.Daneaus:BAAALgAECgYJEgAAAA==.Daniellson:BAABLgAECn8WAAQMAAgJKBGFLwC1AQAMAAgJKBGFLwC1AQANAAEJiA49EwBGAAAOAAEJAABM3AAXAAABLgAFFAMJBgAPAAIbAA==.Daredevil:BAAALgADCgkJCAABLgAECgcJDQACAAAAAA==.Darkchronos:BAAALgADCgcJEAAAAA==.Darkwolf:BAAALgAECggJEAAAAA==.Darnuus:BAAALgAECgMJBwAAAA==.',
Db='Dblaster:BAAALgAECgUJCgAAAA==.',
De='Deathbydruid:BAAALgAECgYJBgAAAA==.Deathnelf:BAAALgAECgUJCgAAAA==.Deazraelle:BAAALgAECgYJDgAAAA==.Declan:BAAALgADCgUJBQAAAA==.Dedric:BAAALgAECgYJDAAAAA==.Dellin:BAAALgAECgYJEgAAAA==.Demeco:BAEALgAECgcJDgABLgAFFAcJEAAQAPMaAA==.Demonch:BAAALgAECgUJCAAAAA==.Depeche:BAAALgAECgQJBAAAAA==.',
Di='Diminuendo:BAAALgAECgQJBwAAAA==.',
Do='Donalda:BAAALgADCgQJBAAAAA==.Dorillion:BAAALgAECgIJAgAAAA==.Dorozh:BAAALgAECgUJBQAAAA==.',
Dr='Draconx:BAAALgADCgYJBgAAAA==.Draghr:BAAALgADCgkJDQAAAA==.Dragskar:BAAALgADCgUJBQAAAA==.Drala:BAAALgAECgUJCgAAAA==.Dreadmage:BAAALgADCgUJBQABLgADCgUJCQACAAAAAA==.Dreadpally:BAAALgADCgEJAQABLgADCgUJCQACAAAAAA==.Dreco:BAAALgADCgcJBwAAAA==.Dryconias:BAAALgAECgcJEgAAAA==.Drèadpriest:BAAALgAECgQJCgAAAA==.Drôgô:BAABLgAECn8VAAIOAAYJnhO1GQAvAQAOAAYJnhO1GQAvAQAAAA==.',
Du='Dunkelzhan:BAABLgAECn8gAAIHAAYJZRq1GwBuAQAHAAYJZRq1GwBuAQAAAA==.Duntack:BAAALgADCgEJAQAAAA==.',
Dy='Dyana:BAAALgAECgUJBQAAAA==.',
Dz='Dz:BAABLgAECn8bAAIQAAgJkiP0AgBGAwAQAAgJkiP0AgBGAwAAAA==.',
['Dø']='Dømimømmÿ:BAAALgAECgQJBAAAAA==.',
Ed='Edgyname:BAAALgAECgQJCgAAAA==.Edgyvoid:BAAALgADCgYJDAAAAA==.Edlund:BAAALgAECgYJEQAAAA==.',
Ef='Effyinzpjake:BAAALgAECgYJDgAAAA==.',
Ei='Eianistic:BAAALgADCgEJAQAAAA==.',
El='Ellinor:BAAALgADCgUJCQAAAA==.Elvy:BAAALgAECgcJEwAAAA==.',
En='Enngin:BAAALgAECgYJCgAAAA==.',
Er='Erebus:BAAALgAECgYJCQAAAA==.',
Ev='Evildefiant:BAAALgAECgEJAQAAAA==.',
Ex='Exsalsior:BAAALgADCgYJBgAAAA==.',
Fa='Fabulousness:BAAALgAECgYJBwAAAA==.',
Fl='Flexi:BAAALgADCgEJAQAAAA==.Flitred:BAAALgAECgYJDAAAAA==.',
Fo='Foxx:BAAALgAECgEJAQAAAA==.',
Fr='Framboise:BAABLgAECn8ZAAIRAAYJUAcIYAAwAQARAAYJUAcIYAAwAQAAAA==.Frostybolt:BAAALgAECgEJAgAAAA==.',
Fu='Furryriver:BAAALgAECgQJBwAAAA==.',
Ga='Galadhras:BAAALgADCgUJBQAAAA==.Galdryn:BAAALgADCgIJAQAAAA==.Galianna:BAAALgAECgQJBAAAAA==.Garkevon:BAAALgADCgMJAwAAAA==.',
Ge='Gemeni:BAAALgADCgYJCQAAAA==.Gevul:BAABLgAECn8eAAMGAAYJeBZmjwA6AQAGAAYJeBZmjwA6AQADAAMJAAlpRgCcAAAAAA==.',
Gh='Ghostess:BAAALgADCgkJAQAAAA==.Ghrank:BAAALgAECgEJAQAAAA==.',
Gi='Gilliruni:BAAALgADCgUJBQAAAA==.',
Gl='Glimley:BAAALgADCgMJAwAAAA==.',
Gn='Gnorst:BAAALgADCgkJCgAAAA==.',
Go='Goreolio:BAAALgADCgkJDwABLgAECgYJDQACAAAAAA==.',
Gr='Grasshopaa:BAAALgADCgYJCQAAAA==.Grassy:BAAALgADCgkJCQAAAA==.Gremz:BAABLgAECn8ZAAISAAcJMAkGBQDyAAASAAcJMAkGBQDyAAAAAA==.Grozny:BAAALgADCgYJBgAAAA==.Grày:BAAALgAECgYJEgAAAA==.',
Gu='Gumboslice:BAAALgAECgQJCQAAAA==.',
['Gä']='Gändälf:BAAALgAECgUJCgAAAA==.',
Ha='Habanero:BAAALgAECgYJEgAAAA==.Hachedev:BAAALgAECgMJCAAAAA==.Hadtopandadk:BAAALgAECgEJAQAAAA==.Hallia:BAABLgAECn8fAAILAAgJKBJfOADFAQALAAgJKBJfOADFAQAAAA==.Hark:BAAALgADCgUJBQAAAA==.Hawgwild:BAAALgAECgQJCQAAAA==.',
He='Headdinks:BAAALgADCgcJDAAAAA==.Healvisprsly:BAAALgAECgQJBgAAAA==.Heisenberg:BAAALgADCgMJAwABLgAECgEJAwACAAAAAA==.Helena:BAABLgAECn8jAAMJAAgJYByWBwBkAgAJAAgJ0xqWBwBkAgAKAAcJ7Bk6VwDdAQAAAA==.Heliarc:BAAALgADCgUJCQAAAA==.',
Hi='Highfive:BAAALgAECgUJCAAAAA==.',
Ho='Holybeech:BAAALgAECgQJBAAAAA==.Honestly:BAAALgADCgcJDQAAAA==.Honkytonkman:BAAALgADCgQJBAAAAA==.Hover:BAAALgAECgUJBQAAAA==.',
Il='Illuminate:BAAALgADCgQJBAAAAA==.Illustria:BAAALgADCgUJCQAAAA==.',
In='Insidious:BAAALgAECgYJDQAAAA==.',
Ir='Irs:BAAALgADCgIJAgAAAA==.',
It='Itchyfeet:BAAALgADCgUJBQABLgAECggJIAAHAHgkAA==.Itchymage:BAABLgAECn8gAAIHAAgJeCQvHQABAwAHAAgJeCQvHQABAwAAAA==.',
Ja='Jacckiemoon:BAAALgADCggJDwAAAA==.Jadehunterr:BAAALgAECgMJBAAAAA==.Jaesn:BAAALgADCgYJBgAAAA==.',
Je='Jenövha:BAAALgADCgkJFwAAAA==.Jezebelle:BAAALgADCgYJDwAAAA==.',
Ji='Jigs:BAABLgAECn8UAAIOAAYJLwoaHQAXAQAOAAYJLwoaHQAXAQAAAA==.Jiräiya:BAAALgADCgYJBgAAAA==.',
Jo='Johastrasz:BAAALgADCggJCAAAAA==.',
['Jå']='Jåfar:BAAALgADCgEJAgAAAA==.',
Ka='Kaladriel:BAAALgADCgEJAQAAAA==.Kaldrick:BAAALgADCgkJCQAAAA==.Kamstareater:BAAALgAECgYJEgAAAA==.Kanakas:BAAALgAECgYJCgAAAA==.Kanaloa:BAAALgAECgYJDgAAAA==.',
Ke='Kegerator:BAAALgADCgcJDwAAAA==.Keirin:BAAALgAECgUJBQAAAA==.Keldica:BAAALgAECgEJAQAAAA==.Kelysa:BAAALgADCggJCwAAAA==.Kevinbox:BAAALgAECgYJCAAAAA==.Kevinslayer:BAAALgAECgUJCwAAAA==.Keynaridan:BAAALgAECgYJCQAAAA==.Keyss:BAAALgADCgIJAgAAAA==.',
Kg='Kglizard:BAAALgAECgUJBgAAAA==.',
Kh='Khalinor:BAAALgAECgQJCAAAAA==.Khardun:BAAALgADCgcJCQAAAA==.',
Ki='Kickazdin:BAAALgAECgQJCAAAAA==.Kiryie:BAAALgADCgcJDQAAAA==.',
Kl='Kluma:BAAALgAECgEJAQAAAA==.',
Ko='Kobu:BAAALgADCgUJBgAAAA==.Konran:BAAALgADCgEJAQAAAA==.',
Kr='Kraigen:BAAALgAECgYJDgAAAA==.Krinack:BAAALgAECgYJEQAAAA==.Krixiz:BAAALgAECgYJCgAAAA==.',
Ku='Kurindrixx:BAAALgADCgIJAgAAAA==.Kurtakum:BAAALgADCgMJAwAAAA==.',
Kw='Kwarify:BAAALgADCgEJAQAAAA==.',
Ky='Kynasmira:BAAALgADCgQJBAAAAA==.Kyrsh:BAAALgADCgcJEAAAAA==.',
La='Ladrona:BAAALgAECgEJAQAAAA==.Lassan:BAAALgAECgQJBwAAAA==.Later:BAAALgAECgUJBQAAAA==.Latimir:BAAALgADCgMJAwAAAA==.Laur:BAAALgADCgYJBgAAAA==.Lavendeer:BAAALgAECgYJEAAAAA==.Laylana:BAAALgADCgIJAgABLgADCgUJCQACAAAAAA==.Lazyeye:BAAALgADCgUJBAABLgAECgUJBQACAAAAAA==.',
Lb='Lb:BAAALgADCgEJAQAAAA==.',
Le='Legume:BAAALgADCgcJCAABLgAECgUJDAACAAAAAA==.Legzanot:BAABLgAECn8eAAITAAgJIRciHQAoAgATAAgJIRciHQAoAgAAAA==.Leonceault:BAAALgAECgEJAQAAAA==.',
Li='Lifebringa:BAAALgAECgQJCwAAAA==.Lightningfox:BAAALgAECgIJAwAAAA==.Lileth:BAAALgAECgEJAQAAAA==.Limzzmagus:BAAALgAECgMJBgAAAA==.Lithia:BAAALgADCgkJEwAAAA==.Littlemo:BAAALgAECgQJBwAAAA==.',
Lo='Loggs:BAAALgAFFAEJAQAAAA==.Lohnar:BAAALgAECgQJBwAAAA==.',
Lu='Lucielbaal:BAAALgAECgYJEgAAAA==.Luciferus:BAAALgAECgQJBAABLgAECgYJEQACAAAAAA==.Lunareth:BAAALgADCgUJBQAAAA==.',
Ly='Lyrska:BAAALgAECgUJCgAAAA==.Lytearrow:BAAALgAECgYJCwAAAA==.',
['Lé']='Léaf:BAAALgAECgMJAwAAAA==.',
Ma='Mahrylee:BAAALgAECgQJCQAAAA==.Majutsu:BAAALgADCgEJAQABLgADCgcJDgACAAAAAA==.Malbrax:BAAALgAECgQJBAAAAA==.Maleficents:BAABLgAECn8WAAIBAAYJBAzbRQAWAQABAAYJBAzbRQAWAQAAAA==.Malurius:BAAALgAECgYJDAAAAA==.Malware:BAAALgAECgYJDwAAAA==.Manana:BAAALgADCgEJAQAAAA==.Manikfury:BAAALgAECgYJDgAAAA==.Maniksmage:BAAALgADCgUJDAABLgAECgYJDgACAAAAAA==.Mannypack:BAAALgAECgUJBQAAAA==.Maseles:BAAALgAECgEJAQAAAA==.',
Mc='Mcdawg:BAAALgADCgQJBAAAAA==.Mcleary:BAAALgADCgYJDAAAAA==.',
Me='Melinashala:BAAALgAECgYJDgAAAA==.Mending:BAAALgAECgQJBAAAAA==.',
Mi='Miler:BAAALgAECgMJBAAAAA==.Misanth:BAAALgAECgYJDgAAAA==.Mistdruid:BAAALgAECgIJAgABLgAECgIJAwACAAAAAA==.',
Mo='Moemo:BAAALgAECgUJCgAAAA==.Mogryn:BAAALgAECgMJAwAAAA==.Mommybree:BAAALgAECgMJAwAAAA==.Monksterz:BAABLgAECn8UAAIFAAYJvR/JBQCuAQAFAAYJvR/JBQCuAQAAAA==.Monoxidê:BAAALgAECgEJAQAAAA==.Morsecode:BAAALgADCgUJBAABLgABCgIJAgACAAAAAA==.Morthok:BAAALgAECgYJDgAAAA==.Mosh:BAAALgAECgMJBQAAAA==.',
Mu='Muchuchu:BAAALgAECgQJCwABLgAECgEJAQACAAAAAA==.Munkee:BAAALgAECgYJDQAAAA==.Murdinbronze:BAAALgADCgUJCAAAAA==.Musyl:BAAALgADCgEJAQABLgAECgYJDQACAAAAAA==.',
['Mã']='Mãf:BAAALgAECgQJCAAAAA==.',
['Mí']='Místwalker:BAAALgAECgIJAwAAAA==.',
Na='Nackthyr:BAABLgAECn8nAAIUAAgJpSazAAB8AwAUAAgJpSazAAB8AwAAAA==.Nafir:BAAALgADCgUJBQAAAA==.Narlin:BAAALgAECgEJAgAAAA==.Nasta:BAAALgAECgIJAgAAAA==.Natureboi:BAAALgADCgQJBAABLgADCgYJDAACAAAAAA==.Nazareths:BAAALgAECgQJCAAAAA==.Nazgor:BAAALgADCgkJCwAAAA==.',
Ne='Necrosius:BAAALgAECgQJBwAAAA==.Neonarc:BAEALgADCgUJCAAAAA==.Neshi:BAAALgAECgMJBQAAAA==.Neuman:BAAALgADCgEJAQAAAA==.',
Ni='Nivdk:BAAALgADCgYJBgABLgAECgYJEQACAAAAAA==.Nivora:BAAALgAECgYJEQAAAA==.',
Ny='Nyxstalia:BAAALgAECgUJDAAAAA==.Nyyx:BAAALgAECgYJDgAAAA==.',
Ol='Olmek:BAACLgAFFH8MAAIRAAQJZQo7BQANAQARAAQJZQo7BQANAQAuAAQKfxUAAhEABwl2IiUeAF4CABEABwl2IiUeAF4CAAAA.',
Op='Opalana:BAAALgADCgIJAwAAAA==.Oprahwndfury:BAAALgADCgYJCwABLgAECgEJBgACAAAAAA==.',
Or='Orasaya:BAAALgADCgYJBgAAAA==.Orphee:BAAALgADCgcJBwAAAA==.Orzanis:BAAALgADCgcJDgAAAA==.',
Pa='Paige:BAAALgADCgcJDgAAAA==.Palasades:BAAALgADCgUJBQAAAA==.Pallymarc:BAAALgADCgEJAQAAAA==.Pallytune:BAAALgAECgcJDAAAAA==.Pandalorian:BAAALgAECgQJBAAAAA==.Pandamajack:BAAALgAECgEJAQAAAA==.',
Ph='Philandre:BAAALgADCgYJBgAAAA==.',
Pi='Picoso:BAAALgAECgYJCgAAAA==.Piianna:BAAALgAECgYJCQAAAA==.Pirko:BAAALgADCgMJAwAAAA==.',
Po='Pocketheal:BAAALgADCgkJCQAAAA==.',
Pu='Punch:BAAALgAECgEJAQAAAA==.Purplerain:BAAALgADCgMJBwAAAA==.Putrigord:BAAALgAECgMJBQAAAA==.',
Qi='Qik:BAAALgADCgYJBgAAAA==.Qikkaw:BAAALgAECgMJBwAAAA==.Qitetsu:BAAALgAECgUJBQAAAA==.',
Qu='Quantos:BAAALgAECgYJCQAAAA==.Ququmatz:BAAALgADCgMJAwAAAA==.',
Ra='Raatha:BAAALgAECgYJDAAAAA==.Raganar:BAAALgAECgMJBwAAAA==.Ranlerodis:BAAALgADCgMJAwAAAA==.Rayjean:BAAALgADCgUJCQAAAA==.',
Re='Redneckboots:BAAALgADCgEJAQAAAA==.Relmax:BAAALgAECgUJBQAAAA==.Rendeminae:BAAALgADCgcJBwAAAA==.Renri:BAAALgADCgYJBgAAAA==.Repose:BAAALgAECgIJAwAAAA==.Revick:BAAALgAECgUJCAAAAA==.Revil:BAAALgADCgIJAgAAAA==.',
Rh='Rhaenýs:BAAALgADCgcJDQAAAA==.Rhonwynn:BAAALgAECgMJBwAAAA==.',
Ri='Rikershipdwn:BAAALgAECgUJBQAAAA==.Rimish:BAAALgADCgcJEwABLgAECggJEwACAAAAAA==.Rimrave:BAAALgAECgYJEgAAAA==.Ripavicii:BAAALgAECgEJAQAAAA==.Ritobeans:BAAALgADCgUJCQAAAA==.Rivik:BAAALgADCgkJGgAAAA==.',
Ro='Robbstark:BAAALgAECgYJCwAAAA==.Robertkenway:BAAALgAECgYJEQAAAA==.Roguebot:BAAALgADCgkJEAAAAA==.Rohdaric:BAAALgAECgYJEQAAAA==.Rokte:BAAALgADCgkJEwAAAA==.Rook:BAAALgAECgYJDAAAAA==.Rosekenway:BAAALgAECgUJBQAAAA==.',
Rr='Rratt:BAAALgADCgcJGgAAAA==.',
Ru='Rubimoon:BAAALgADCgMJBgABLgADCgcJCgACAAAAAA==.Rumí:BAAALgADCgUJCQAAAA==.Running:BAAALgADCgUJBgAAAA==.',
Sa='Saammiee:BAAALgAECgIJAgAAAA==.Sabiha:BAAALgAECgYJDgAAAA==.Saintotem:BAAALgAECgYJBgAAAA==.Samartyr:BAAALgAECgQJBwAAAA==.Sammiiee:BAAALgADCgQJBAABLgAECgIJAgACAAAAAA==.Sangwynaris:BAAALgADCgYJCQAAAA==.Saphiiraa:BAAALgADCgMJAwAAAA==.Sayahealer:BAAALgADCgcJDgAAAA==.',
Sc='Scorpmage:BAAALgAECgMJBwAAAA==.Scramms:BAAALgADCgcJDQAAAA==.Scrams:BAAALgAECgUJCAAAAA==.',
Se='Sedrick:BAABLgAECn8VAAIQAAYJGyK8BAAcAgAQAAYJGyK8BAAcAgAAAA==.Sekendipity:BAAALgADCgEJAQABLgAECgUJBQACAAAAAA==.Sekndestroy:BAAALgADCgYJCQABLgAECgUJBQACAAAAAA==.Sektacular:BAAALgADCgQJBAABLgAECgUJBQACAAAAAA==.Sekzen:BAAALgAECgUJBQAAAA==.Semiazas:BAABLgAECn8VAAQVAAYJYQxBAwAFAQAVAAYJFQxBAwAFAQAGAAUJ2QmLtwDpAAADAAEJAADpegAnAAAAAA==.Semiazes:BAAALgADCgYJBgAAAA==.Seumas:BAAALgADCgMJAwAAAA==.',
Sh='Shadrock:BAAALgADCgYJBgAAAA==.Shayrisa:BAABLgAECn8VAAIWAAYJBhSAEQAuAQAWAAYJBhSAEQAuAQAAAA==.Shazool:BAAALgADCgkJEwABLgAECggJHwALACgSAA==.Sheep:BAAALgAECgYJCQAAAA==.Shifterz:BAAALgAECgQJBgAAAA==.Shrubbery:BAAALgAECgUJBQAAAA==.Shxdow:BAAALgAECgQJBAAAAA==.',
Si='Sind:BAAALgADCgcJEQABLgAECgMJBwACAAAAAA==.Sindella:BAAALgADCgEJAQABLgAECgMJBwACAAAAAA==.Sinna:BAAALgADCgUJCQAAAA==.Sinthorne:BAAALgAECgMJBwAAAA==.',
Sk='Skedaddle:BAAALgAECgMJBAABLgAECgYJEwACAAAAAA==.',
Sl='Slashbndcoot:BAAALgADCgMJAwAAAA==.Slashgquit:BAABLgAECn8jAAIXAAgJFiX4AAB1AgAXAAgJFiX4AAB1AgAAAA==.Slumbermist:BAABLgAECn8VAAIYAAYJhBLvDAAVAQAYAAYJhBLvDAAVAQABLgABCgIJAgACAAAAAA==.',
So='Solaire:BAAALgAECgYJDwABLgAECggJHAAPABIfAA==.Soras:BAAALgADCgUJCQAAAA==.',
Su='Sunareas:BAAALgADCgIJAgAAAA==.',
Sy='Synthetic:BAAALgAECgQJBQAAAA==.',
Sz='Szasstaam:BAAALgAECgUJDQAAAA==.',
['Sé']='Séékér:BAAALgADCgcJFQAAAA==.',
Ta='Talanith:BAAALgADCggJEAAAAA==.Tarriff:BAAALgAECgYJDgAAAA==.Taxal:BAAALgADCgYJBgAAAA==.Taxlock:BAAALgAECgYJEwAAAA==.',
Tb='Tbagjones:BAAALgADCgkJDQAAAA==.',
Te='Tecsaran:BAAALgAECgYJEAAAAA==.Tekis:BAAALgADCgEJAQAAAA==.Terania:BAAALgADCgIJAgAAAA==.',
Th='Thalira:BAAALgAECgUJBQAAAA==.',
Ti='Tiger:BAACLgAFFH8hAAMZAAkJECcBAACwAwAZAAgJECcBAACwAwALAAIJGSEeFwCoAAAuAAQKfyUAAxkACQnqJgUAABYEABkACQnqJgUAABYEAAsAAQm1C3rEAD8AAAAA.Tinnea:BAAALgAECgQJBAAAAA==.Titanosaurus:BAAALgAECgQJBwAAAA==.Tizzly:BAABLgAECn8XAAIHAAgJoQzlFgCMAQAHAAgJoQzlFgCMAQAAAA==.',
To='Torhilda:BAAALgAECgYJBgAAAA==.Torridwells:BAAALgADCgkJEwAAAA==.',
Tr='Trad:BAAALgADCgYJBgAAAA==.Troag:BAAALgAECgQJBQAAAA==.Troagstar:BAAALgAECgQJCQAAAA==.',
Ts='Tsaesci:BAAALgADCgQJBgAAAA==.Tsynn:BAAALgADCgUJBQAAAA==.',
Ty='Tyraana:BAABLgAECn8ZAAMaAAYJOSDRFgATAgAaAAYJOSDRFgATAgAbAAEJngPF8QAgAAAAAA==.Tyrinwar:BAAALgADCgYJDAAAAA==.Tyrmog:BAAALgAECgIJAgAAAA==.Tytus:BAAALgADCgIJAgAAAA==.',
Us='Ushas:BAAALgAECgcJEwAAAA==.',
Va='Vali:BAAALgAECgYJDgAAAA==.Valindrea:BAAALgAECgQJBwAAAA==.Vasrael:BAAALgAECgYJDgAAAA==.Vav:BAAALgAECgYJDgAAAA==.',
Ve='Vecnis:BAAALgAECgIJAgAAAA==.',
Vi='Vithper:BAAALgAECgUJBQAAAA==.',
Vn='Vnia:BAAALgADCgMJAwAAAA==.',
Vo='Voidmuffinz:BAABLgAECn8ZAAIbAAgJqxbEDwCIAQAbAAgJqxbEDwCIAQAAAA==.',
Vy='Vynis:BAAALgAECgcJDAABLgAECgcJDAACAAAAAA==.Vyrahildard:BAAALgAECgYJEgAAAA==.',
Wa='Waringoutlaw:BAAALgADCgkJCQAAAA==.Wasteland:BAAALgAECggJCwAAAA==.',
We='Weaselhunter:BAAALgAECgEJAQABLgAECgUJCwACAAAAAA==.Weasellock:BAAALgAECgUJCwAAAA==.Weaselmage:BAAALgAECgQJBgABLgAECgUJCwACAAAAAA==.Welor:BAAALgADCgMJAwAAAA==.',
Wh='Whatthef:BAAALgADCgkJEAAAAA==.',
Wi='Wildweasel:BAAALgAECgEJAQABLgAECgUJCwACAAAAAA==.Winterhide:BAAALgAECgYJDgAAAA==.',
Xa='Xallie:BAEBLgAECn8XAAIbAAgJgQ8JVACnAQAbAAgJgQ8JVACnAQAAAA==.Xanvyr:BAAALgAECgYJEgAAAA==.Xaquillis:BAABLgAECn8fAAIEAAgJjBsfPABHAgAEAAgJjBsfPABHAgAAAA==.Xarthis:BAAALgADCgYJCwABLgAECggJHwAEAIwbAA==.',
Xe='Xentrie:BAAALgADCgUJCgAAAA==.Xeyvara:BAAALgAECgYJEgAAAA==.',
Xg='Xg:BAAALgADCgUJBgABLgAECgYJDgACAAAAAA==.',
Ya='Yatsui:BAAALgAECgQJBAAAAA==.',
Yo='Youngthug:BAAALgAECgIJAwAAAA==.',
Yu='Yutaa:BAAALgADCgYJBgAAAA==.',
Za='Zarihanna:BAABLgAECn8ZAAIHAAcJcBEdHgBgAQAHAAcJcBEdHgBgAQAAAA==.Zatannah:BAAALgADCgUJBQAAAA==.',
Ze='Zedryn:BAAALgAECgYJDQAAAA==.Zeperios:BAAALgAECgQJBAAAAA==.Zeril:BAAALgAECgYJCQAAAA==.Zestull:BAAALgAECgYJDgAAAA==.',
Zh='Zhoel:BAAALgADCgEJAQAAAA==.',
Zi='Zindeshal:BAAALgAECgEJAQAAAA==.',
Zo='Zonnish:BAAALgAECgIJAgAAAA==.Zorc:BAABLgAECn8ZAAITAAgJSyH0CQD0AgATAAgJSyH0CQD0AgAAAA==.',
Zy='Zyate:BAABLgAECn8hAAIGAAgJNxGGGgBBAQAGAAgJNxGGGgBBAQAAAA==.Zyrryn:BAAALgAECgYJDgAAAA==.',
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

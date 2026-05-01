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

local lookup = {'Unknown-Unknown','Druid-Balance','Druid-Restoration','Warlock-Destruction','DeathKnight-Unholy','Shaman-Restoration','Monk-Brewmaster','Warlock-Demonology','Mage-Frost','Priest-Holy','Warlock-Affliction','Paladin-Protection','Paladin-Retribution','Hunter-Marksmanship','Hunter-Survival','Hunter-BeastMastery','Monk-Windwalker','DeathKnight-Blood','Paladin-Holy','Evoker-Devastation','Warrior-Fury','DemonHunter-Vengeance','Shaman-Elemental','DemonHunter-Devourer','DemonHunter-Havoc','Druid-Feral','Rogue-Assassination','Warrior-Protection','Warrior-Arms','Monk-Mistweaver',}
local provider = {region='US',realm='Greymane',name='US',type='weekly',zone=46,date='2026-05-01',data={Aa='Aagonyy:BAAALgADCgMJAwAAAA==.',
Ae='Aernoth:BAAALgAECgUJDAAAAA==.',
Ak='Akaidia:BAAALgAECgYJBgABLgAECgYJBgABAAAAAA==.',
Al='Alderan:BAAALgAECgYJEAAAAA==.Aleinas:BAABLgAECn8bAAMCAAYJzRPiNQBlAQACAAYJzRPiNQBlAQADAAQJPwjvTgCVAAAAAA==.Alektophobia:BAAALgAECgUJBQAAAA==.Alendra:BAAALgAECgEJAQAAAA==.Alluisice:BAAALgAECgYJBgAAAA==.Allysaun:BAAALgADCgMJAwAAAA==.Alpharoach:BAAALgADCgYJBgAAAA==.',
Am='Amorina:BAAALgAECgYJCwAAAA==.',
An='Andarnn:BAAALgAECgEJAQAAAA==.Andracca:BAAALgAECgQJBgAAAA==.Andromeda:BAAALgAECgMJAwAAAA==.Aner:BAAALgAECgEJAwAAAA==.Angrygnome:BAABLgAECn8cAAIEAAgJ3x+6AACLAgAEAAgJ3x+6AACLAgAAAA==.Angélique:BAAALgAECgYJCgABLgAFFAMJBQAFAMwfAA==.Antcension:BAAALgADCgUJBQAAAA==.Antemental:BAAALgAECgYJEAAAAA==.Anthigos:BAAALgAECgMJAwAAAA==.',
Ar='Arax:BAAALgAECgYJEwAAAA==.Arcamoon:BAAALgADCgcJCAABLgADCgcJCgABAAAAAA==.Arcashi:BAAALgADCgcJCgAAAA==.Arianlion:BAAALgAECgEJAgAAAA==.Armistice:BAAALgAECgEJAgAAAA==.Arowenn:BAAALgADCgMJAwAAAA==.Arrokoth:BAAALgAECgEJAQAAAA==.Artana:BAAALgAECgIJAgAAAA==.',
At='Attachedplag:BAAALgAECgUJBQAAAA==.Atulwa:BAABLgAECn8WAAIGAAcJ9xchNgCrAQAGAAcJ9xchNgCrAQAAAA==.',
Au='Aurinox:BAAALgAECgEJAQAAAA==.Autodrive:BAAALgAECgUJCAAAAA==.',
Av='Avralea:BAABLgAECn8qAAIHAAgJ6RrgCgDcAQAHAAgJ6RrgCgDcAQAAAA==.',
Az='Azenthal:BAAALgAECgEJAQAAAA==.',
Ba='Bananahammik:BAAALgAECgYJDgAAAA==.Banzen:BAAALgAECgEJAQAAAA==.Basz:BAAALgAECgUJDgAAAA==.',
Be='Beginagain:BAAALgADCgEJAQAAAA==.Belgran:BAAALgAECggJEwAAAA==.Berunma:BAAALgAECgcJEgAAAA==.',
Bh='Bhain:BAABLgAECn8gAAMIAAcJ0x17IwCjAQAIAAcJ0x17IwCjAQAEAAEJaA16dAAwAAABLgAFFAEJAQABAAAAAA==.',
Bi='Bileshots:BAAALgAECgUJBQAAAA==.Biowolf:BAABLgAECn8jAAIJAAgJKxVLJgDNAQAJAAgJKxVLJgDNAQAAAA==.Birdhunter:BAAALgAECgcJDQAAAA==.Bishopixixix:BAAALgAECgYJCwAAAA==.Bits:BAAALgAECgYJDQAAAA==.',
Bj='Bjoren:BAABLgAECn8aAAIKAAYJBSWPDQCAAgAKAAYJBSWPDQCAAgAAAA==.',
Bl='Blackdread:BAAALgADCgYJBgAAAA==.Bloodcaptain:BAABLgAECn8ZAAMEAAgJHxeDAgDqAQAEAAgJJhaDAgDqAQALAAYJshf5CAC3AQAAAA==.',
Bo='Bohma:BAAALgADCgEJAQAAAA==.Bootiebang:BAAALgAECgYJEAAAAA==.Bootycaall:BAAALgADCgkJCQAAAA==.Boroth:BAAALgADCgcJBwAAAA==.',
Br='Breetech:BAAALgAECgIJAgAAAA==.Brett:BAAALgAECgEJAQAAAA==.Breé:BAAALgADCgMJAwAAAA==.Brianx:BAAALgADCgIJAgAAAA==.Brklyn:BAAALgAFFAEJAQAAAA==.Brokki:BAAALgADCgEJAQAAAA==.',
Bu='Buckaroo:BAAALgAECgEJAQAAAA==.Buckwhild:BAAALgAECgYJCQAAAA==.Burrhus:BAAALgADCgQJAgAAAA==.',
Ca='Cagomei:BAAALgADCggJDgAAAA==.Caladbolg:BAABLgAECn8cAAMMAAcJFxWoEQCtAQAMAAcJFxWoEQCtAQANAAEJkAP4VwEnAAAAAA==.Camrillem:BAAALgAECgQJCQAAAA==.Cannacola:BAAALgAECgYJEwAAAA==.Carebearr:BAAALgADCgQJBAAAAA==.',
Ce='Cearius:BAAALgAECgYJCgABLgAFFAMJCgAIAGYlAA==.Cesàrè:BAAALgAECgYJBgAAAA==.',
Ch='Chahra:BAAALgAECgMJAwAAAA==.Chammie:BAAALgAECgYJBgAAAA==.Chamuki:BAAALgAECgUJCwABLgAFFAMJBwADAJoeAA==.Cheesecake:BAACLgAFFH8FAAIFAAMJzB9BMAABAQAFAAMJzB9BMAABAQAuAAQKfxwAAgUACQleJcUCAK4DAAUACQleJcUCAK4DAAAA.Cheesuspiece:BAAALgADCgIJAgAAAA==.Chrispbacon:BAAALgAECgEJAQAAAA==.Chuubak:BAAALgAECgkJAQAAAA==.',
Cl='Clangedin:BAAALgAECgMJBwAAAA==.',
Co='Cobalt:BAAALgADCgUJBQABLgAECgcJEQABAAAAAA==.Coreydruid:BAAALgAECgMJBwAAAA==.Coreysham:BAAALgAECgMJAwAAAA==.Corily:BAAALgADCgUJEQAAAA==.Corsten:BAAALgAECgUJCgAAAA==.Cosmictonic:BAAALgADCgYJBgAAAA==.',
Cr='Crabpack:BAAALgADCgIJAgAAAA==.Croisades:BAAALgAECgQJCgAAAA==.Crosis:BAAALgADCgYJEAAAAA==.Crowmatic:BAABLgAECn8VAAIFAAgJUR67CwBtAgAFAAgJUR67CwBtAgAAAA==.Crusadan:BAAALgADCgYJBgAAAA==.Cryo:BAAALgAECgEJAQAAAA==.',
Cu='Cute:BAAALgAFFAIJAgAAAA==.',
['Cà']='Càhos:BAAALgADCgUJBQAAAA==.',
Da='Dakon:BAABLgAECn8uAAMMAAkJShpcAgBmAgAMAAkJShpcAgBmAgANAAIJcBiwDAF9AAAAAA==.Dalune:BAAALgAECgQJCwAAAA==.Daneaus:BAABLgAECn8YAAIDAAYJXiNNCwBTAgADAAYJXiNNCwBTAgAAAA==.Daniellson:BAABLgAECn8YAAQOAAgJKBGJLwC1AQAOAAgJKBGJLwC1AQAPAAEJPRC7LABEAAAQAAEJAABY3AAXAAABLgAFFAQJCgARAEciAA==.Daredevil:BAAALgADCgkJCAABLgAECggJEQABAAAAAA==.Darkchronos:BAAALgADCgcJEAAAAA==.Darkscorp:BAAALgADCgkJCQAAAA==.Darkwolf:BAABLgAECn8XAAMFAAgJFAnaOABWAQAFAAgJlQjaOABWAQASAAYJyARgGgCoAAAAAA==.Darnuus:BAAALgAECgQJCwAAAA==.',
Db='Dblaster:BAAALgAECgUJCgAAAA==.',
De='Deathbydruid:BAAALgAECgYJBgAAAA==.Deathnelf:BAAALgAECgYJCwAAAA==.Deazraelle:BAAALgAECgYJDgAAAA==.Decimator:BAAALgADCgcJEAAAAA==.Declan:BAAALgADCgUJBQAAAA==.Dedric:BAAALgAECgcJEwAAAA==.Dellin:BAABLgAECn8YAAICAAYJWxm3KwCkAQACAAYJWxm3KwCkAQAAAA==.Demeco:BAEALgAECgcJDgAAAA==.Demonch:BAAALgAECgUJCAAAAA==.Depeche:BAAALgAECgUJCQAAAA==.',
Di='Diminuendo:BAAALgAECgQJBwAAAA==.',
Do='Donalda:BAAALgADCgQJBAAAAA==.Dorillion:BAAALgAECgQJBAAAAA==.Dorozh:BAAALgAECgYJCwAAAA==.',
Dr='Draconx:BAAALgADCgYJBgAAAA==.Draghr:BAAALgADCgkJDQAAAA==.Dragskar:BAAALgADCgUJBQAAAA==.Drala:BAAALgAECgYJEAAAAA==.Dreadmage:BAAALgADCgUJBQABLgADCgUJCQABAAAAAA==.Dreadpally:BAAALgADCgEJAQABLgADCgUJCQABAAAAAA==.Dreco:BAAALgADCgcJBwAAAA==.Driver:BAEALgAECgUJBQABLgAFFAMJBwAIAKULAA==.Dryconias:BAABLgAECn8bAAINAAkJSxfAMQB7AQANAAkJSxfAMQB7AQAAAA==.Drèadpriest:BAAALgAECgUJCwAAAA==.Drôgô:BAABLgAECn8VAAIQAAYJnhM2TgB+AQAQAAYJnhM2TgB+AQAAAA==.',
Du='Dunkelzhan:BAABLgAECn8nAAIJAAcJJxqrJwDHAQAJAAcJJxqrJwDHAQAAAA==.Duntack:BAAALgADCgEJAQAAAA==.',
Dy='Dyana:BAAALgAECgYJCwAAAA==.',
Dz='Dz:BAABLgAECn8jAAITAAgJ3yTyAgBGAwATAAgJ3yTyAgBGAwAAAA==.',
['Dø']='Dømimømmÿ:BAAALgAECgQJBAAAAA==.',
Ed='Edgyname:BAAALgAECgQJCgAAAA==.Edgyvoid:BAAALgADCgYJDAAAAA==.Edlund:BAABLgAECn8XAAIUAAYJQgg8CAAAAQAUAAYJQgg8CAAAAQAAAA==.',
Ef='Effyinzpjake:BAAALgAECgYJDgAAAA==.',
Ei='Eianistic:BAAALgADCgEJAQAAAA==.',
El='Ellinor:BAAALgADCgYJDwAAAA==.Elvy:BAABLgAECn8YAAICAAcJ5xWYJQDQAQACAAcJ5xWYJQDQAQAAAA==.',
En='Enngin:BAAALgAECggJDwAAAA==.',
Er='Erebus:BAAALgAECgYJCQAAAA==.',
Ev='Evildefiant:BAAALgAECgEJAQAAAA==.',
Ex='Exsalsior:BAAALgADCgYJBgAAAA==.',
Fa='Fabulousness:BAAALgAECgYJDQAAAA==.',
Fi='Fishingsucks:BAAALgAECgEJAQAAAA==.',
Fl='Flexi:BAAALgADCgEJAQAAAA==.Flitred:BAAALgAECggJDwAAAA==.Flock:BAAALgADCgcJBwAAAA==.',
Fo='Foxx:BAAALgAECgIJAwAAAA==.',
Fr='Framboise:BAABLgAECn8ZAAIVAAYJUAcRYAAwAQAVAAYJUAcRYAAwAQAAAA==.Frostybolt:BAAALgAECgEJAgAAAA==.',
Fu='Furryriver:BAAALgAECgQJBwAAAA==.',
Ga='Galadhras:BAAALgADCgUJBQAAAA==.Galdryn:BAAALgADCgIJAQAAAA==.Galianna:BAAALgAECgYJCgAAAA==.Garkevon:BAAALgADCgMJAwAAAA==.',
Ge='Gemeni:BAAALgADCgYJCQAAAA==.Gevul:BAABLgAECn8jAAMIAAgJFxMwKgCFAQAIAAcJ7BQwKgCFAQAEAAQJswhsRgCcAAAAAA==.',
Gh='Ghostess:BAAALgADCgkJAQAAAA==.Ghrank:BAAALgAECgIJAgAAAA==.',
Gi='Gilliruni:BAAALgADCgUJBQAAAA==.',
Gl='Glimley:BAAALgADCgMJAwAAAA==.',
Gn='Gnorst:BAAALgADCgkJCgAAAA==.',
Go='Goreolio:BAAALgADCgkJDwABLgAECgYJEQABAAAAAA==.',
Gr='Grandmatank:BAAALgADCgkJCQAAAA==.Grasshopaa:BAAALgADCgYJCQAAAA==.Grassy:BAAALgADCgkJCQAAAA==.Gremz:BAABLgAECn8eAAIWAAcJvwluCgD1AAAWAAcJvwluCgD1AAAAAA==.Grozny:BAAALgADCgYJBgAAAA==.Grày:BAABLgAECn8ZAAIFAAcJ1BZNKgCTAQAFAAcJ1BZNKgCTAQAAAA==.',
Gu='Gumboslice:BAAALgAECgUJDQAAAA==.',
['Gä']='Gändälf:BAAALgAECgYJEAAAAA==.',
Ha='Habanero:BAABLgAECn8YAAMXAAYJHSDeJQD2AAAXAAMJ7BveJQD2AAAGAAYJYA0bMwDvAAAAAA==.Hachedev:BAAALgAECgMJCAAAAA==.Hadtopandadk:BAAALgAECgEJAQAAAA==.Hallia:BAABLgAECn8iAAIDAAkJURLxGwCgAQADAAkJURLxGwCgAQAAAA==.Hark:BAAALgADCgYJCwAAAA==.Hawgwild:BAAALgAECgQJCgAAAA==.',
He='Headdinks:BAAALgADCgcJDAAAAA==.Healvisprsly:BAAALgAECgQJBwAAAA==.Heisenberg:BAAALgADCgMJAwABLgAECgEJAwABAAAAAA==.Helena:BAABLgAECn8rAAMNAAgJRB/NCgB3AgANAAgJRB/NCgB3AgAMAAgJ0xqWBwBkAgAAAA==.Heliarc:BAAALgADCgYJDwAAAA==.',
Hi='Highfive:BAAALgAECgUJCAAAAA==.',
Ho='Holybeech:BAAALgAECgQJBAAAAA==.Honestly:BAAALgADCggJEwAAAA==.Honkytonkman:BAAALgADCgQJBAAAAA==.Hover:BAAALgAECgYJCwAAAA==.',
Ih='Ihmoen:BAAALgADCgYJBgAAAA==.',
Il='Illuminate:BAAALgADCgQJBAAAAA==.Illustria:BAAALgADCgUJCQABLgADCgYJBgABAAAAAA==.Illustriâ:BAAALgADCgYJBgAAAA==.',
In='Insidious:BAABLgAECn8UAAISAAcJRBmMCwBXAQASAAcJRBmMCwBXAQAAAA==.',
Ir='Irs:BAAALgADCgIJAgAAAA==.',
It='Itchyfeet:BAAALgADCgUJBQABLgAECggJIAAJAHgkAA==.Itchymage:BAABLgAECn8gAAIJAAgJeCQvHQABAwAJAAgJeCQvHQABAwAAAA==.',
Ja='Jacckiemoon:BAAALgAECgMJAwAAAA==.Jadehunterr:BAAALgAECgMJBAAAAA==.Jaesn:BAAALgADCgYJBgAAAA==.',
Je='Jenae:BAAALgAECgEJAQAAAA==.Jenövha:BAAALgADCgkJFwAAAA==.Jezebelle:BAAALgADCgkJGAAAAA==.',
Ji='Jigs:BAABLgAECn8aAAIQAAYJJwxDPAAiAQAQAAYJJwxDPAAiAQAAAA==.Jiräiya:BAAALgADCgYJBgAAAA==.',
Jo='Johastrasz:BAAALgADCggJCAAAAA==.',
['Jå']='Jåfar:BAAALgADCgEJAgAAAA==.',
Ka='Kaladriel:BAAALgADCgEJAQAAAA==.Kaldrick:BAAALgADCgkJCQAAAA==.Kamstareater:BAABLgAECn8SAAIYAAYJZhRoMQAdAQAYAAYJZhRoMQAdAQAAAA==.Kanakas:BAAALgAECgYJDAAAAA==.Kanaloa:BAABLgAECn8UAAIJAAYJ7QRveQDjAAAJAAYJ7QRveQDjAAAAAA==.Kayler:BAAALgAECgYJBgAAAA==.',
Ke='Kegerator:BAAALgADCgcJDwAAAA==.Keirin:BAAALgAECgYJCwAAAA==.Keldica:BAAALgAECgIJAgAAAA==.Kelysa:BAAALgADCgkJDQAAAA==.Kenshan:BAAALgADCgQJBAAAAA==.Kevinbox:BAAALgAECgYJCgAAAA==.Kevinslayer:BAAALgAECgUJCwAAAA==.Keynaridan:BAAALgAECgYJEgAAAA==.Keyss:BAAALgADCgIJAgAAAA==.',
Kg='Kglizard:BAAALgAECgUJBwAAAA==.',
Kh='Khalinor:BAAALgAECgYJDgAAAA==.Khardun:BAAALgADCgcJDQAAAA==.Khotuhn:BAAALgADCgkJCwAAAA==.',
Ki='Kickazdin:BAAALgAFFAEJAQAAAA==.Kiryie:BAAALgAECgMJAwAAAA==.Kisäme:BAAALgADCgkJCQAAAA==.',
Kl='Kluma:BAAALgAECgEJAQAAAA==.',
Ko='Kobu:BAAALgADCgUJBgAAAA==.Konran:BAAALgADCgEJAQAAAA==.',
Kr='Kraigen:BAABLgAECn8UAAIZAAYJzRs1CwCJAQAZAAYJzRs1CwCJAQAAAA==.Krinack:BAAALgAECgYJEQAAAA==.Krixiz:BAAALgAECgYJCgAAAA==.',
Ku='Kurindrixx:BAAALgADCgIJAgAAAA==.Kurtakum:BAAALgADCgMJAwAAAA==.',
Kw='Kwarify:BAAALgADCgEJAQAAAA==.',
Ky='Kynasmira:BAAALgADCgYJCgAAAA==.Kyrsh:BAAALgADCgcJEAAAAA==.',
La='Ladrona:BAAALgAECgYJBwAAAA==.Lailyre:BAAALgAECgYJBQABLgAECgYJBgABAAAAAA==.Lassan:BAAALgAECgQJBwAAAA==.Later:BAAALgAECgUJBQAAAA==.Latimir:BAAALgADCgMJAwAAAA==.Laur:BAAALgADCgYJBgAAAA==.Lavendeer:BAABLgAECn8XAAICAAcJ1Q1FHAAZAQACAAcJ1Q1FHAAZAQAAAA==.Laylana:BAAALgADCgIJAgABLgADCgUJCQABAAAAAA==.Lazyeye:BAAALgADCgUJBAABLgAECgYJBgABAAAAAA==.',
Lb='Lb:BAAALgADCgEJAQAAAA==.',
Le='Legume:BAAALgADCgcJCAABLgAECgUJDAABAAAAAA==.Legzanot:BAACLgAFFH8GAAIXAAMJRQeDFQDHAAAXAAMJRQeDFQDHAAAuAAQKfyEAAhcACAkzGCMdACgCABcACAkzGCMdACgCAAAA.Leonceault:BAAALgAECgEJAQAAAA==.',
Li='Lifebringa:BAAALgAECgUJEAAAAA==.Lightningfox:BAAALgAECgQJBwAAAA==.Lightsfallen:BAAALgADCgkJEAAAAA==.Lileth:BAAALgAECgUJAQAAAA==.Limzzmagus:BAAALgAECgMJBgAAAA==.Lithia:BAAALgAECgMJAwAAAA==.Littlemo:BAAALgAECgQJBwAAAA==.',
Lo='Loggs:BAAALgAFFAEJAQAAAA==.Lohnar:BAAALgAECgQJBwAAAA==.',
Lu='Lucidslock:BAAALgADCgIJAgAAAA==.Lucielbaal:BAABLgAECn8YAAIIAAYJOho3MQBmAQAIAAYJOho3MQBmAQAAAA==.Luciferus:BAAALgAECgQJBAABLgAECggJGQAPAEQNAA==.Luckystop:BAAALgAECgMJAwAAAA==.Lunareth:BAAALgADCgUJBQAAAA==.',
Ly='Lyrska:BAAALgAECgYJEAAAAA==.Lytearrow:BAAALgAECgYJEwAAAA==.',
['Lé']='Léaf:BAAALgAECgMJAwAAAA==.',
Ma='Mahrylee:BAAALgAECgQJCQAAAA==.Maiya:BAAALgADCgQJBAAAAA==.Majutsu:BAAALgADCgEJAQABLgADCgcJDgABAAAAAA==.Malbrax:BAAALgAECgYJCgAAAA==.Maleficents:BAABLgAECn8XAAICAAYJBAzgRQAWAQACAAYJBAzgRQAWAQAAAA==.Malurius:BAAALgAECgYJDAAAAA==.Malware:BAAALgAECgYJDwAAAA==.Manana:BAAALgADCgEJAQAAAA==.Manbearpally:BAAALgAECgQJBAAAAA==.Manikfury:BAABLgAECn8UAAMDAAYJWx4DEQAHAgADAAYJWx4DEQAHAgAaAAUJBBEVDwDnAAAAAA==.Maniksmage:BAAALgADCgUJDAABLgAECgYJFAADAFseAA==.Mannypack:BAAALgAECgYJCwAAAA==.Maseles:BAAALgAECgEJAQAAAA==.',
Mc='Mcdawg:BAAALgADCgQJBAAAAA==.Mcleary:BAAALgADCgYJDAAAAA==.',
Me='Melinashala:BAABLgAECn8UAAIIAAYJEwMkcQCoAAAIAAYJEwMkcQCoAAAAAA==.Mending:BAAALgAECgUJBQAAAA==.Meowinator:BAAALgAECgMJAwAAAA==.',
Mi='Miler:BAAALgAECgQJBQAAAA==.Misanth:BAAALgAECgYJDgAAAA==.Mistdruid:BAAALgAECgIJAwABLgAECgIJBgABAAAAAA==.',
Mo='Moemo:BAAALgAECgYJEAAAAA==.Mogryn:BAAALgAECgMJAwAAAA==.Moistymists:BAAALgAECgYJBgAAAA==.Mommybree:BAAALgAECgMJAwAAAA==.Monksterz:BAABLgAECn8aAAIHAAYJ+yDPCgDdAQAHAAYJ+yDPCgDdAQAAAA==.Monoxidê:BAAALgAECgEJAQAAAA==.Morsecode:BAAALgAECgEJAQABLgABCgIJAgABAAAAAA==.Morthok:BAABLgAECn8UAAIIAAYJ2RG7QAAvAQAIAAYJ2RG7QAAvAQAAAA==.Mosh:BAAALgAECgYJCwAAAA==.',
Mu='Muchuchu:BAAALgAECgQJDAABLgAECgEJAQABAAAAAA==.Munkee:BAAALgAECgYJEQAAAA==.Murdinbronze:BAAALgADCgUJCAAAAA==.Musyl:BAAALgADCgEJAQABLgAECgYJEQABAAAAAA==.',
['Mã']='Mãf:BAAALgAECgYJDQAAAA==.',
['Mí']='Místwalker:BAAALgAECgIJBgAAAA==.',
Na='Nackthyr:BAACLgAFFH8FAAIUAAIJzCMPBQDSAAAUAAIJzCMPBQDSAAAuAAQKfy8AAhQACQn2JQwAAIwDABQACQn2JQwAAIwDAAAA.Nafir:BAAALgADCgYJCwAAAA==.Narlin:BAAALgAECgEJAgAAAA==.Nasta:BAAALgAECgIJAgAAAA==.Natureboi:BAAALgADCgQJBAABLgADCgYJDAABAAAAAA==.Nazareths:BAAALgAECgQJCAAAAA==.Nazgor:BAAALgAECgMJAwAAAA==.',
Ne='Necrosius:BAAALgAECgQJBwAAAA==.Neonarc:BAEALgADCgYJDgAAAA==.Neshi:BAAALgAECgMJBQAAAA==.Neuman:BAAALgADCgEJAQAAAA==.',
Ni='Nightsbane:BAAALgADCgQJBAAAAA==.Nivdk:BAAALgADCgYJBgABLgAECgYJEQABAAAAAA==.Nivora:BAAALgAECgYJEQAAAA==.',
No='Notsure:BAAALgAECgEJAgAAAA==.',
Ny='Nyxstalia:BAAALgAECgUJDAAAAA==.Nyyx:BAABLgAECn8PAAIYAAYJIATOVwCgAAAYAAYJIATOVwCgAAAAAA==.',
Ol='Olmek:BAACLgAFFH8OAAIVAAUJZw/zDAA4AQAVAAUJZw/zDAA4AQAuAAQKfxUAAhUABwl2IiEeAF4CABUABwl2IiEeAF4CAAAA.',
Op='Opalana:BAAALgADCgIJAwAAAA==.Oprahwndfury:BAAALgADCgYJEQABLgAECgEJBwABAAAAAA==.',
Or='Orasaya:BAAALgADCgYJBgAAAA==.Orphee:BAAALgADCgcJBwAAAA==.Orzanis:BAAALgADCgcJDgAAAA==.',
Pa='Paige:BAAALgADCgcJDgAAAA==.Palasades:BAAALgADCgUJBQAAAA==.Pallymarc:BAAALgADCgEJAQAAAA==.Pallytune:BAAALgAFFAIJAgAAAA==.Pandalorian:BAAALgAECgYJCgAAAA==.Pandamajack:BAAALgAECgEJAQAAAA==.',
Ph='Philandre:BAAALgADCgYJBgAAAA==.',
Pi='Picoso:BAAALgAECgYJEAAAAA==.Piianna:BAAALgAECgYJDwAAAA==.Pirko:BAAALgADCgMJAwAAAA==.',
Po='Pocketheal:BAAALgADCgkJCQAAAA==.',
Pu='Punch:BAAALgAECgEJAgAAAA==.Purplerain:BAAALgADCgMJBwAAAA==.Putrigord:BAAALgAECgQJCQAAAA==.',
Qi='Qik:BAAALgADCgYJBgAAAA==.Qikkaw:BAAALgAECgUJDAAAAA==.Qitetsu:BAAALgAECgUJBgAAAA==.',
Qu='Quantos:BAAALgAECgYJDwAAAA==.Ququmatz:BAAALgADCgMJAwAAAA==.',
Ra='Raatha:BAAALgAECgYJDAAAAA==.Raganar:BAAALgAECgQJCwAAAA==.Ranlerodis:BAAALgADCgMJAwAAAA==.Rayjean:BAAALgADCgYJDwAAAA==.',
Re='Redneckboots:BAAALgADCgEJAQAAAA==.Relmax:BAAALgAECgYJCwAAAA==.Rendeminae:BAAALgADCgcJBwAAAA==.Renri:BAAALgAECgcJBwAAAA==.Repose:BAAALgAECgIJAwAAAA==.Revick:BAAALgAECgUJCAAAAA==.Revil:BAAALgADCgIJAgAAAA==.',
Rh='Rhaenýs:BAAALgADCgcJDQAAAA==.Rhonwynn:BAAALgAECgQJCwAAAA==.',
Ri='Rikershipdwn:BAAALgAECgYJCwAAAA==.Rimish:BAAALgADCgcJEwABLgAECggJGwAbANgXAA==.Rimrave:BAABLgAECn8YAAQcAAYJXB6JCACtAQAVAAYJIxsZNQDVAQAcAAYJhB2JCACtAQAdAAMJswhmJQBXAAAAAA==.Ripavicii:BAAALgAECgEJAQAAAA==.Ritobeans:BAAALgADCgYJDwAAAA==.Rivik:BAAALgADCgkJGgAAAA==.',
Ro='Robbstark:BAAALgAECgYJDAAAAA==.Robertkenway:BAABLgAECn8ZAAMPAAgJRA0lCgC/AQAPAAgJRA0lCgC/AQAQAAEJAADT1AAwAAAAAA==.Roguebot:BAAALgADCgkJEgAAAA==.Rohdaric:BAABLgAECn8XAAIPAAYJfxPOEgA7AQAPAAYJfxPOEgA7AQAAAA==.Rokte:BAAALgAECgMJAwAAAA==.Rook:BAAALgAECgYJEAAAAA==.Rosekenway:BAAALgAECgYJBwAAAA==.',
Rr='Rratt:BAAALgADCgkJHQAAAA==.',
Ru='Rubimoon:BAAALgADCgMJBgABLgADCgcJCgABAAAAAA==.Rumí:BAAALgADCgUJCQAAAA==.Running:BAAALgADCgUJBgAAAA==.',
Sa='Saammiee:BAAALgAECgIJAgAAAA==.Sabiha:BAABLgAECn8UAAMQAAYJZg8GSgDzAAAQAAYJZg8GSgDzAAAOAAEJwQPTlAAlAAAAAA==.Saintotem:BAAALgAECgYJBgAAAA==.Samartyr:BAAALgAECgQJBwAAAA==.Sammiiee:BAAALgADCgQJBAABLgAECgIJAgABAAAAAA==.Sangwynaris:BAAALgADCgYJCQAAAA==.Saphiiraa:BAAALgAECgYJBgAAAA==.Sayahealer:BAAALgADCgcJDgAAAA==.',
Sc='Scorpmage:BAAALgAECgUJDAAAAA==.Scramms:BAAALgADCgcJDQAAAA==.Scrams:BAAALgAECgYJDgAAAA==.',
Se='Sedrick:BAABLgAECn8cAAITAAcJox94BwBmAgATAAcJox94BwBmAgAAAA==.Sekendipity:BAAALgADCgEJAQABLgAECgYJBgABAAAAAA==.Sekndestroy:BAAALgADCgYJCQABLgAECgYJBgABAAAAAA==.Sektacular:BAAALgADCgQJBAABLgAECgYJBgABAAAAAA==.Sekzen:BAAALgAECgYJBgAAAA==.Semiazas:BAABLgAECn8cAAQLAAcJvg9aAwCGAQALAAcJvg9aAwCGAQAIAAUJ2QmdtwDpAAAEAAEJAADuegAnAAAAAA==.Semiazes:BAAALgADCgYJBgAAAA==.Senessa:BAAALgADCgIJAgAAAA==.Sensy:BAAALgADCgQJBAAAAA==.Seumas:BAAALgADCgMJAwAAAA==.',
Sh='Shadrock:BAAALgADCgYJBgAAAA==.Shayrisa:BAABLgAECn8cAAIGAAcJGhKUJQA+AQAGAAcJGhKUJQA+AQAAAA==.Shazool:BAAALgAECgMJAwABLgAECgkJIgADAFESAA==.Sheep:BAAALgAECgYJCQAAAA==.Shifterz:BAAALgAECgQJBgAAAA==.Shrubbery:BAAALgAECgYJCwAAAA==.Shxdow:BAAALgAECgQJBAAAAA==.',
Si='Sind:BAAALgADCgkJGQABLgAECgQJCwABAAAAAA==.Sindella:BAAALgADCgIJAgABLgAECgQJCwABAAAAAA==.Sinna:BAAALgADCgUJCQAAAA==.Sinthorne:BAAALgAECgQJCwAAAA==.',
Sk='Skedaddle:BAAALgAECgQJCAAAAA==.',
Sl='Slashbndcoot:BAAALgADCgMJAwAAAA==.Slashgquit:BAACLgAFFH8HAAISAAMJDx23CAAPAQASAAMJDx23CAAPAQAuAAQKfycAAhIACAkWJZYBAHMCABIACAkWJZYBAHMCAAAA.Slumbermist:BAABLgAECn8cAAMeAAcJHROnLQBLAQAeAAYJnhKnLQBLAQARAAcJdwwiFQBDAQABLgABCgIJAgABAAAAAA==.',
So='Solaire:BAAALgAECgYJEQABLgAECggJIQARAHsfAA==.Soras:BAAALgADCgYJDwAAAA==.',
St='Steph:BAAALgADCgYJBgAAAA==.',
Su='Sunareas:BAAALgADCgIJAgAAAA==.',
Sy='Synthetic:BAAALgAECgUJCgAAAA==.',
Sz='Szasstaam:BAAALgAECgUJEgAAAA==.',
['Sé']='Séékér:BAAALgADCgcJFQAAAA==.',
Ta='Talanith:BAAALgADCggJEAAAAA==.Taxal:BAAALgADCgYJBwAAAA==.Taxlock:BAABLgAECn8aAAIIAAcJ8AlYPQA6AQAIAAcJ8AlYPQA6AQAAAA==.',
Tb='Tbagjones:BAAALgAECgMJAwAAAA==.',
Te='Tecsaran:BAAALgAECgYJEQAAAA==.Tekis:BAAALgADCgEJAQAAAA==.Terania:BAAALgADCgIJAgAAAA==.',
Th='Thalira:BAAALgAECgYJCwAAAA==.',
Ti='Tiger:BAACLgAFFH8pAAMaAAkJECcBAACwAwAaAAgJECcBAACwAwADAAIJGSElFwCoAAAuAAQKfyUAAxoACQnqJgUAABYEABoACQnqJgUAABYEAAMAAQm1C37EAD8AAAAA.Tinnea:BAAALgAECgQJBAAAAA==.Titanosaurus:BAAALgAECgQJBwAAAA==.Tizzly:BAABLgAECn8fAAIJAAgJuw1FOACGAQAJAAgJuw1FOACGAQAAAA==.',
To='Torhilda:BAAALgAECgYJBgAAAA==.Torridwells:BAAALgAECgMJAwAAAA==.',
Tr='Trad:BAAALgADCgYJBgAAAA==.Troag:BAAALgAECgQJBQAAAA==.Troagstar:BAAALgAECgUJCwAAAA==.',
Ts='Tsaesci:BAAALgADCgQJBgAAAA==.Tsynn:BAAALgADCgYJCwAAAA==.',
Ty='Tyraana:BAABLgAECn8hAAMZAAcJex/LCAC8AQAZAAcJex/LCAC8AQAYAAEJngPJ8QAgAAAAAA==.Tyrinwar:BAAALgADCgYJDAAAAA==.Tyrmog:BAAALgAECgIJBAAAAA==.Tytus:BAAALgADCgIJAgAAAA==.',
Us='Ushas:BAABLgAECn8bAAIKAAgJ8BckEQCYAQAKAAgJ8BckEQCYAQAAAA==.',
Va='Vali:BAABLgAECn8UAAIOAAYJexy8BQCbAQAOAAYJexy8BQCbAQAAAA==.Valindrea:BAAALgAECgQJBwAAAA==.Vasrael:BAABLgAECn8UAAMTAAYJdh5qDAARAgATAAYJdh5qDAARAgANAAEJ2xQhPwE1AAAAAA==.Vav:BAABLgAECn8UAAMQAAYJdhesNwAzAQAQAAYJdhesNwAzAQAPAAIJsgzBKwBHAAAAAA==.',
Ve='Vecnis:BAAALgAECgIJAgAAAA==.Veliette:BAAALgAECgIJAgAAAA==.',
Vi='Vithper:BAAALgAECgUJBQAAAA==.',
Vn='Vnia:BAAALgADCgMJAwAAAA==.',
Vo='Voidmuffinz:BAABLgAECn8TAAIYAAgJyhjoUQCvAQAYAAgJyhjoUQCvAQAAAA==.',
Vy='Vynis:BAAALgAECgcJDQABLgAFFAIJAgABAAAAAA==.Vyrahildard:BAABLgAECn8YAAINAAYJFhpzOgBbAQANAAYJFhpzOgBbAQAAAA==.',
Wa='Wakkiq:BAAALgADCgkJCQAAAA==.Waringoutlaw:BAAALgADCgkJCQAAAA==.Wasteland:BAAALgAECggJEwAAAA==.',
We='Weaselhunter:BAAALgAECgIJAgABLgAECgYJDAABAAAAAA==.Weasellock:BAAALgAECgUJDQABLgAECgYJDAABAAAAAA==.Weaselmage:BAAALgAECgYJDAAAAA==.Welor:BAAALgADCgMJBgAAAA==.',
Wh='Whatthef:BAAALgADCgkJGwAAAA==.',
Wi='Wildweasel:BAAALgAECgQJBQABLgAECgYJDAABAAAAAA==.Winterhide:BAABLgAECn8UAAIFAAYJDRNMPgBEAQAFAAYJDRNMPgBEAQAAAA==.',
Xa='Xallie:BAEBLgAECn8cAAIYAAkJ+hBbKABGAQAYAAkJ+hBbKABGAQAAAA==.Xanvyr:BAABLgAECn8ZAAINAAcJZBhiLACQAQANAAcJZBhiLACQAQAAAA==.Xaquillis:BAACLgAFFH8FAAIFAAMJvQ16OADtAAAFAAMJvQ16OADtAAAuAAQKfyAAAgUACAmMGyQ8AEcCAAUACAmMGyQ8AEcCAAAA.Xarthis:BAAALgAECgEJAQABLgAFFAMJBQAFAL0NAA==.',
Xe='Xentrie:BAAALgADCgUJCgAAAA==.Xeyvara:BAABLgAECn8YAAIWAAYJYSPqAgD8AQAWAAYJYSPqAgD8AQAAAA==.',
Xg='Xg:BAAALgADCgUJBgABLgAECgYJEwABAAAAAA==.',
Ya='Yatsui:BAAALgAECgQJBAAAAA==.',
Yo='Youngthug:BAAALgAECgIJAwAAAA==.',
Yu='Yutaa:BAAALgADCgYJBgAAAA==.',
Za='Zarihanna:BAABLgAECn8jAAIJAAgJohKyLgCpAQAJAAgJohKyLgCpAQAAAA==.Zatannah:BAAALgADCgUJBQAAAA==.',
Ze='Zedryn:BAAALgAECgYJEwAAAA==.Zeperios:BAAALgAECgQJBAAAAA==.Zeril:BAAALgAECgcJDgAAAA==.Zestull:BAABLgAECn8UAAIHAAYJcCUzBwAlAgAHAAYJcCUzBwAlAgAAAA==.',
Zh='Zhoel:BAAALgADCgEJAQAAAA==.',
Zi='Zindeshal:BAAALgAECgQJBAAAAA==.',
Zo='Zorc:BAABLgAECn8iAAIXAAkJnR74CQD0AgAXAAkJnR74CQD0AgAAAA==.',
Zu='Zunji:BAAALgAECgEJAgAAAA==.',
Zy='Zyate:BAABLgAECn8oAAIIAAgJNxGNKgCDAQAIAAgJNxGNKgCDAQAAAA==.Zyrryn:BAABLgAECn8UAAIUAAYJmQPfCgC8AAAUAAYJmQPfCgC8AAAAAA==.',
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

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

local lookup = {'Paladin-Protection','Evoker-Preservation','Evoker-Devastation','Evoker-Augmentation','Warrior-Protection','Priest-Holy','Paladin-Retribution','Paladin-Holy','DemonHunter-Devourer','Druid-Guardian','Mage-Frost','Warrior-Fury','Shaman-Elemental','Shaman-Restoration','Shaman-Enhancement','Druid-Restoration','DeathKnight-Unholy','Hunter-BeastMastery','Unknown-Unknown','Monk-Brewmaster','Druid-Balance','Monk-Windwalker','Hunter-Marksmanship','Warlock-Demonology','Warlock-Destruction','DeathKnight-Blood','DemonHunter-Havoc','Priest-Discipline','DeathKnight-Frost','Druid-Feral','Monk-Mistweaver','Warrior-Arms','Priest-Shadow','Hunter-Survival','DemonHunter-Vengeance','Warlock-Affliction','Rogue-Subtlety',}
local provider = {region='US',realm='Uther',name='US',type='weekly',zone=46,date='2026-05-08',data={Ad='Addiction:BAAALgADCgYJAQAAAA==.',
Ah='Ahmet:BAAALgAECgkJEwABLgAECgkJKwABAMcaAA==.',
Ai='Aiax:BAACLgAFFH8FAAICAAMJRAIJFgCoAAACAAMJRAIJFgCoAAAuAAQKfxcABAMACAlODC4gACwBAAQABgmnDbkxADoBAAMABglkCi4gACwBAAIAAglJB0FGAEAAAAAA.',
Al='Aliancia:BAABLgAECn8bAAIFAAYJXxBoFwAGAQAFAAYJXxBoFwAGAQAAAA==.Almur:BAAALgAECgYJBgAAAA==.Alyda:BAAALgADCggJFAAAAA==.',
Am='Amet:BAABLgAECn8rAAIBAAkJxxp6BQCfAgABAAkJxxp6BQCfAgAAAA==.',
An='Anakinn:BAAALgAECgUJBQAAAA==.Annailuj:BAAALgADCgIJAgAAAA==.Annora:BAABLgAECn8pAAIGAAgJjxl0FgApAgAGAAgJjxl0FgApAgAAAA==.Antherina:BAAALgADCgQJBwAAAA==.Antonious:BAAALgADCgMJAwAAAA==.Antonlavay:BAAALgAECgQJBAAAAA==.',
Ap='Aphyra:BAAALgADCgUJBQAAAA==.Apollyøn:BAABLgAECn8eAAMHAAkJ4yBEBQD7AgAHAAkJ4yBEBQD7AgAIAAIJKhWnfgB/AAAAAA==.',
Ar='Arlechino:BAABLgAECn8cAAIJAAgJFxdSQADzAQAJAAgJFxdSQADzAQAAAA==.Arywyn:BAAALgAECgYJDwAAAA==.',
As='Assclapiuss:BAABLgAECn8cAAIHAAgJ9SRtCgC0AgAHAAgJ9SRtCgC0AgAAAA==.Asterchades:BAABLgAECn8nAAIKAAgJ9BpkBgDkAQAKAAgJ9BpkBgDkAQAAAA==.Astlin:BAAALgAECgEJAQAAAA==.Astraeastar:BAAALgADCgUJBQAAAA==.',
At='Athennah:BAAALgAECgcJBwABLgAECggJFAALAOMaAA==.Atrei:BAAALgADCgIJAgAAAA==.Attikus:BAABLgAECn8lAAILAAgJPAMdfwATAQALAAgJPAMdfwATAQAAAA==.Atuan:BAAALgAECgYJDwAAAA==.',
Au='Auralass:BAAALgAECgYJEwAAAA==.Aurene:BAAALgAECgkJHwAAAQ==.Autym:BAAALgADCgkJCQAAAA==.',
Av='Avatard:BAAALgAECgIJAgABLgAECggJIgALALcQAA==.',
Ax='Axem:BAABLgAECn8YAAIMAAgJJBVAIwBWAQAMAAgJJBVAIwBWAQAAAA==.',
Az='Azlanii:BAAALgADCggJCgAAAA==.Azulathan:BAAALgAECgYJEgABLgAECggJLAANAK4PAA==.',
Ba='Bamseyn:BAAALgADCgYJBgAAAA==.Bamsheyn:BAAALgADCgkJCQAAAA==.Baraxor:BAABLgAECn8sAAMNAAgJrg9+HQBiAQANAAgJrg9+HQBiAQAOAAQJDRTybgDTAAAAAA==.Barrelaged:BAAALgADCggJCwAAAA==.',
Be='Beerguy:BAAALgAECgUJBQAAAA==.Behemothe:BAABLgAECn8fAAIPAAgJ3B3VBAAOAgAPAAgJ3B3VBAAOAgAAAA==.Berníesandrs:BAABLgAECn8oAAILAAgJUA3rUgByAQALAAgJUA3rUgByAQAAAA==.Beryllos:BAAALgAECgIJAgAAAA==.Bevela:BAAALgADCgIJAgAAAA==.',
Bi='Biddies:BAAALgAECgYJBwAAAA==.Biggusdiscus:BAAALgAECgMJAwAAAA==.Bigimpin:BAAALgADCgcJBwAAAA==.',
Bj='Bjôrn:BAAALgAECgcJDQAAAA==.',
Bl='Bledana:BAAALgADCggJCgAAAA==.Bleué:BAAALgADCgEJAQABLgAECggJJAAQAGAcAA==.Bloodmourne:BAABLgAECn8iAAIRAAgJWSNLDAClAgARAAgJWSNLDAClAgAAAA==.Bloodytoutii:BAAALgAECgUJBQAAAA==.',
Bo='Borthyr:BAABLgAECn8cAAMEAAkJUBl0CABLAgAEAAkJ/BV0CABLAgADAAYJ0RynDgDwAQAAAA==.Bowowner:BAABLgAECn8fAAISAAgJxR79EQBCAgASAAgJxR79EQBCAgAAAA==.',
Br='Branchmanagr:BAABLgAECn8aAAIKAAkJ/AwgDABPAQAKAAkJ/AwgDABPAQAAAA==.Brewlee:BAAALgAECgkJDgAAAA==.Brokenkrayon:BAAALgAECgIJAwAAAA==.Brokkr:BAAALgADCgQJBwAAAA==.Brugz:BAAALgAFFAEJAQAAAA==.Bryce:BAAALgAECgEJAQAAAA==.',
Bu='Busta:BAABLgAECn8fAAILAAkJZgUyZABJAQALAAkJZgUyZABJAQAAAA==.',
Bw='Bwicked:BAAALgAECgcJEgAAAA==.',
['Bé']='Béck:BAAALgADCgEJAQAAAA==.',
['Bü']='Büg:BAAALgAECgcJDwAAAA==.',
Ca='Caedars:BAAALgADCgEJAQAAAA==.Calzone:BAAALgAECgMJBAAAAA==.Cantpurge:BAAALgADCgIJAgABLgAECgYJEQATAAAAAA==.',
Ch='Chamelean:BAAALgAECgYJDQABLgAECggJFgAJABUUAA==.Chimpnzthat:BAABLgAECn8WAAIUAAYJUhLjJQASAQAUAAYJUhLjJQASAQAAAA==.Chookicookie:BAABLgAECn8sAAMOAAgJvx80FgBkAgAOAAgJvx80FgBkAgANAAQJHxVqOQDHAAAAAA==.Chuckarita:BAABLgAECn8XAAIVAAcJBQnrKQD1AAAVAAcJBQnrKQD1AAAAAA==.',
Ci='Cindyy:BAABLgAECn8ZAAIWAAcJexrEDQDcAQAWAAcJexrEDQDcAQABLgAECgkJGgASAGEaAA==.Civaelia:BAAALgADCgMJAwAAAA==.',
Cl='Clutterbear:BAAALgADCgIJAgAAAA==.',
Co='Cornpuff:BAAALgAECgYJDQAAAA==.Cortiz:BAABLgAECn8nAAISAAgJ6A/YLgCTAQASAAgJ6A/YLgCTAQAAAA==.',
Cr='Crankdog:BAABLgAECn8fAAMSAAkJZiOiAQA/AwASAAkJZiOiAQA/AwAXAAYJ8g9fSgApAQAAAA==.Creedd:BAABLgAECn8vAAIQAAgJGSA7CQC1AgAQAAgJGSA7CQC1AgAAAA==.Crialta:BAAALgADCgcJFAAAAA==.',
Cu='Cupsandcakes:BAAALgAECgYJEgAAAA==.',
Cy='Cynaidia:BAAALgAECgQJBwAAAA==.',
Da='Dacarry:BAAALgAECgIJAgAAAA==.Damessiah:BAABLgAECn8fAAIGAAgJRA4AGQCHAQAGAAgJRA4AGQCHAQAAAA==.Dark:BAABLgAECn8iAAIYAAgJqB+3EgBNAgAYAAgJqB+3EgBNAgAAAA==.Darkphyre:BAAALgAECgYJDwAAAA==.Darthtree:BAAALgADCgEJAQAAAA==.Dawling:BAAALgAECggJCAAAAA==.',
De='Deadmandan:BAABLgAECn8vAAMYAAkJHSXLAQBRAwAYAAkJHSXLAQBRAwAZAAYJISSwBwBMAgAAAA==.Deathomen:BAAALgADCgcJBwAAAA==.Deathtike:BAABLgAECn8oAAIaAAgJHiKMAwCYAgAaAAgJHiKMAwCYAgAAAA==.Decius:BAAALgAECgYJDgAAAA==.Deltairlines:BAAALgAFFAMJAwAAAA==.Demagorgin:BAABLgAECn8oAAIHAAkJSRfVFQBMAgAHAAkJSRfVFQBMAgAAAA==.Demcheekz:BAAALgAECgIJAgAAAA==.Demiurge:BAAALgAECgUJBQAAAA==.Demondred:BAAALgAECgUJCgAAAA==.Demonplug:BAAALgADCgEJAQAAAA==.Demonrae:BAAALgAECgIJAgAAAA==.Deqlyn:BAABLgAECn8fAAIHAAkJpRsgEwBhAgAHAAkJpRsgEwBhAgAAAA==.Desmus:BAABLgAECn8WAAIVAAYJXRP9IQAoAQAVAAYJXRP9IQAoAQAAAA==.Deterno:BAAALgADCgUJBQAAAA==.Devige:BAAALgADCgMJBAABLgAFFAQJCwAYAJAfAA==.Devilmaycry:BAAALgADCgEJAQAAAA==.Deáthreaver:BAAALgAECggJEAAAAA==.',
Di='Diglett:BAAALgADCgYJAQAAAA==.Dimsum:BAAALgAECgUJBgAAAA==.Diqtator:BAAALgADCgcJBwAAAA==.Dismal:BAABLgAECn8WAAIIAAkJBBBwEwD4AQAIAAkJBBBwEwD4AQAAAA==.Ditar:BAAALgAECgEJAQABLgAECgEJBQATAAAAAA==.',
Dk='Dk:BAAALgADCgIJAgABLgAFFAMJCQASABkkAA==.',
Do='Domwarlock:BAAALgAFFAIJAwAAAA==.Doomdooms:BAAALgADCgEJAQAAAA==.Dots:BAAALgADCggJDgAAAA==.',
Dr='Dradin:BAAALgADCgMJAwAAAA==.Dronin:BAABLgAECn8bAAIXAAcJiBU3CAB/AQAXAAcJiBU3CAB/AQAAAA==.Drpatan:BAAALgAECgYJEgAAAA==.Druni:BAAALgAECgYJDwAAAA==.Dryan:BAAALgADCgEJAQAAAA==.',
Ec='Echowalker:BAAALgAECgYJEQAAAA==.',
Ee='Eecho:BAAALgADCgEJAQAAAA==.',
Ei='Eisenthorne:BAAALgADCgEJAgAAAA==.',
El='Eldruida:BAAALgADCgYJDAAAAA==.Elguezo:BAAALgAECgYJCwAAAA==.Elysyn:BAAALgADCgMJAwAAAA==.',
Em='Emaelia:BAAALgAECgQJBAAAAA==.Emokillaz:BAABLgAECn8WAAIbAAcJ2hiuEgBfAQAbAAcJ2hiuEgBfAQAAAA==.',
Ep='Epictaxes:BAAALgADCgEJAQAAAA==.Epimetheuz:BAAALgADCgYJAwAAAA==.Epsilón:BAAALgAECgYJEQAAAA==.',
Et='Eternalpeace:BAAALgAECgEJAQAAAA==.',
Ev='Evelana:BAAALgADCgQJBwAAAA==.',
Ex='Exaduss:BAABLgAECn8VAAMZAAgJUiF4AwDuAQAZAAgJUiF4AwDuAQAYAAQJHB7FQQBkAQAAAA==.',
Fa='Fastrolling:BAAALgADCgQJCgAAAA==.Faxon:BAABLgAECn8WAAISAAgJMhVlJwC1AQASAAgJMhVlJwC1AQAAAA==.Faylan:BAAALgAECgYJDwAAAA==.',
Fe='Feronnia:BAAALgADCgkJFwAAAA==.',
Fi='Fibot:BAABLgAECn8nAAIPAAgJIxubBAAaAgAPAAgJIxubBAAaAgAAAA==.Fingon:BAAALgAECgcJEgAAAA==.',
Fl='Flogor:BAAALgAECgcJBgABLgAECgkJDwATAAAAAA==.Florasol:BAAALgADCgIJAgAAAA==.',
Fo='Foxling:BAEALgAECgEJAQAAAA==.',
Fr='Fraeyah:BAAALgAECgMJAwAAAA==.Frahaad:BAAALgADCgQJBAAAAA==.Freebunz:BAACLgAFFH8GAAILAAMJCQXmUQDaAAALAAMJCQXmUQDaAAAuAAQKfxQAAgsACAmFF2BUADsCAAsACAmFF2BUADsCAAAA.',
Ga='Gahydra:BAAALgADCgkJEwAAAA==.Galvanize:BAACLgAFFH8JAAILAAQJDQv2NQA5AQALAAQJDQv2NQA5AQAuAAQKfzAAAgsACAn7G8UnAAQCAAsACAn7G8UnAAQCAAAA.Gastdhunter:BAAALgAECgEJAQAAAA==.Gastrophos:BAAALgAECgEJAQAAAA==.',
Gh='Ghomertin:BAAALgADCggJCgAAAA==.',
Gi='Gimtar:BAAALgAECgEJBQAAAA==.Ginjockey:BAAALgADCgUJBQABLgAECgYJEQATAAAAAA==.Gipsydanger:BAABLgAECn85AAIcAAkJvxvvBAC7AgAcAAkJvxvvBAC7AgAAAA==.Girllygirl:BAAALgAECgYJDAAAAA==.Givr:BAAALgADCgEJAQAAAA==.',
Gl='Glaurang:BAAALgAECgMJAwAAAA==.Glofor:BAAALgAECgcJCgABLgAECgkJDwATAAAAAA==.',
Gn='Gnarp:BAAALgADCgEJAQABLgAECgcJFgAOAFIYAA==.Gnomeregrets:BAAALgAECgUJBQAAAA==.',
Go='Goldencorpse:BAAALgAECgQJBAAAAA==.Goldenspoon:BAAALgADCgEJAQAAAA==.Gorlokk:BAEALgADCgMJAwABLgADCgkJHwATAAAAAA==.',
Gr='Grakonys:BAABLgAECn8gAAMEAAgJSg5zGAB+AQAEAAgJSg5zGAB+AQADAAcJ4Qc0HQBFAQAAAA==.Granger:BAAALgAECgIJAgAAAA==.Greed:BAABLgAECn8lAAIWAAgJ3xTSEgCeAQAWAAgJ3xTSEgCeAQAAAA==.Greensun:BAAALgADCgEJAQAAAA==.Grendol:BAAALgAECgMJAwAAAA==.Grimmbot:BAAALgAECgIJAgAAAA==.Grimmvelt:BAAALgAECgMJAwAAAA==.Grunnck:BAAALgADCgcJFAAAAA==.',
Gu='Guayusa:BAAALgAECggJEwAAAA==.Gunned:BAAALgADCgEJAQAAAA==.',
Gw='Gwendolin:BAAALgAECgUJBQAAAA==.Gwenfrewi:BAAALgADCgEJAQABLgADCgEJAQATAAAAAA==.',
Ha='Hacheron:BAAALgADCgIJAgABLgAFFAMJBAATAAAAAA==.Hallows:BAAALgAECgMJAwAAAA==.Harnix:BAAALgAECgYJEQAAAA==.Hawtbooty:BAABLgAECn8eAAIGAAgJnBogHQD1AQAGAAgJnBogHQD1AQAAAA==.',
He='Heartsbane:BAAALgAECgEJAQAAAA==.Helixrage:BAAALgAECgcJEwAAAA==.Hellreines:BAABLgAECn8UAAIdAAYJ2CEtAwDqAQAdAAYJ2CEtAwDqAQAAAA==.Herpderplol:BAABLgAECn8ZAAIeAAgJNRBACQCUAQAeAAgJNRBACQCUAQAAAA==.',
Hi='Hildi:BAABLgAECn8WAAMfAAYJcgG+RABqAAAfAAYJcgG+RABqAAAWAAEJyAEdjAAfAAAAAA==.Him:BAABLgAECn8cAAIMAAgJiSQuAwDfAgAMAAgJiSQuAwDfAgAAAA==.',
Ho='Holy:BAABLgAECn8nAAMcAAgJPR8YCABgAgAcAAgJPR8YCABgAgAGAAEJgxziRABSAAAAAA==.Hoots:BAAALgAECgEJAQAAAA==.',
Hu='Hucklebury:BAAALgADCgYJDQAAAA==.Hulkcrush:BAAALgADCgUJEQAAAA==.Humânity:BAAALgADCgYJBgAAAA==.',
['Hø']='Høåx:BAAALgADCggJCAABLgAECgMJAwATAAAAAA==.',
Il='Illbloodarch:BAABLgAECn8dAAIgAAgJ2Ad0EgAsAQAgAAgJ2Ad0EgAsAQAAAA==.Illvicious:BAAALgAECgIJAwAAAA==.',
In='Incredibread:BAAALgAECgQJBwAAAA==.Indub:BAAALgAECgUJBwAAAA==.',
Ir='Ironfistmogu:BAAALgADCgkJCQAAAA==.',
Is='Ishura:BAABLgAECn8VAAIIAAYJVQlKMwACAQAIAAYJVQlKMwACAQAAAA==.',
It='Itslevi:BAAALgAECgYJCQAAAA==.',
Iv='Ivvy:BAAALgAECgYJDAAAAA==.',
Iz='Izanami:BAAALgAECgYJEAAAAA==.',
Ja='Jaewreth:BAAALgAECgIJAgAAAA==.Janntro:BAAALgAECggJEgAAAA==.Jantra:BAAALgAECgEJAQAAAA==.Jantro:BAABLgAECn8UAAIKAAgJsB5qBAAxAgAKAAgJsB5qBAAxAgAAAA==.Janttro:BAAALgAECgIJAgAAAA==.Jaquavious:BAAALgADCgcJBwAAAA==.',
Je='Jeebz:BAABLgAECn8gAAMOAAkJzBJzHwC3AQAOAAkJzBJzHwC3AQANAAMJxQqMbACRAAAAAA==.Jelmarr:BAAALgAECgYJCQAAAA==.Jemmâ:BAAALgAECggJDgAAAA==.Jerauld:BAABLgAECn8VAAIeAAYJnAsTEQAKAQAeAAYJnAsTEQAKAQAAAA==.Jezrra:BAAALgAECggJDwAAAA==.',
Jh='Jhuloot:BAAALgADCgYJCQAAAA==.',
Ji='Jiddles:BAAALgADCgMJAwABLgAECggJEgATAAAAAA==.',
Jo='Johnnyzyns:BAABLgAECn8iAAMRAAgJPBjJJQDpAQARAAgJPBjJJQDpAQAaAAEJthhVNABFAAAAAA==.Jokhasta:BAABLgAECn8ZAAIPAAgJvhbdBwCvAQAPAAgJvhbdBwCvAQAAAA==.Joshc:BAABLgAECn8iAAIKAAgJDQykEAD9AAAKAAgJDQykEAD9AAAAAA==.',
Jp='Jpmeister:BAAALgADCgkJDQAAAA==.',
Ju='Judgejudee:BAAALgADCgYJCAAAAA==.',
['Já']='Ják:BAABLgAECn8aAAQBAAgJzBMKGwA2AQABAAcJJhEKGwA2AQAIAAIJ8wmQiQBWAAAHAAEJpwPrGAEpAAAAAA==.',
Ka='Kaaris:BAAALgAECgcJDwAAAA==.Kaiarie:BAAALgAECgYJEwAAAA==.Kainraziel:BAABLgAECn8WAAIJAAgJFRTHNABiAQAJAAgJFRTHNABiAQAAAA==.Kairos:BAABLgAECn8kAAILAAcJjA2FZgBEAQALAAcJjA2FZgBEAQAAAA==.Kalasta:BAAALgADCgIJAgAAAA==.Kanzak:BAAALgADCgcJCgAAAA==.Karem:BAAALgAECgEJAQAAAA==.Karkea:BAAALgAECgEJAgAAAA==.Kayper:BAAALgAECgcJAgAAAA==.',
Ke='Kebin:BAABLgAECn8hAAIFAAgJrRcqCgDOAQAFAAgJrRcqCgDOAQAAAA==.Kekkoken:BAAALgADCgkJCgAAAA==.Kelfhammer:BAAALgADCgQJBAAAAA==.Kenkenif:BAAALgADCgUJCgAAAA==.',
Kh='Khlorox:BAAALgADCgYJBgAAAA==.Khronin:BAAALgADCgIJAgAAAA==.',
Ki='Killmonger:BAAALgAECgYJCwAAAA==.Kimsambo:BAAALgAECgQJBAAAAA==.',
Kl='Klöwÿ:BAAALgAECgEJAQAAAA==.',
Ko='Korax:BAAALgAECgUJBQAAAA==.Korgia:BAAALgAECgQJBAAAAA==.Kortharion:BAABLgAECn8iAAICAAgJkCHJAQAGAwACAAgJkCHJAQAGAwAAAA==.Korzillian:BAAALgAECgEJAQAAAA==.Kos:BAABLgAECn8bAAIhAAkJ1B3wAgDZAgAhAAkJ1B3wAgDZAgAAAA==.',
Kr='Krixis:BAAALgADCgEJAgAAAA==.',
Ku='Kujiera:BAAALgAECgcJEwAAAA==.Kuntar:BAAALgAECgcJCgAAAA==.Kurgan:BAAALgADCggJCAAAAA==.Kurkoh:BAAALgAECgEJAgABLgAECgIJAgATAAAAAA==.Kurrent:BAAALgAECggJEgAAAA==.',
['Kÿ']='Kÿtten:BAABLgAECn8cAAIBAAkJxgjhEgAVAQABAAkJxgjhEgAVAQAAAA==.',
La='Lad:BAAALgAECgUJCQABLgAECggJGwAJAL0dAA==.Laiyth:BAAALgAECgkJEgAAAA==.Larryfish:BAABLgAECn8WAAIRAAgJGR5+FQBPAgARAAgJGR5+FQBPAgAAAA==.Laslock:BAAALgADCgEJAQAAAA==.Lavahitman:BAAALgAECgEJAQAAAA==.Lavos:BAABLgAECn8fAAIZAAkJ9AxHBgCOAQAZAAkJ9AxHBgCOAQAAAA==.',
Le='Levitikus:BAAALgAECgEJAwAAAA==.Levìtikus:BAAALgAECgEJAQAAAA==.',
Li='Lighteyes:BAAALgADCgEJAQAAAA==.Lildragon:BAAALgAECgYJBgAAAA==.Lisster:BAABLgAECn8iAAMSAAgJthzgEgA5AgASAAgJthzgEgA5AgAXAAEJkAGxmAAeAAAAAA==.Littledoty:BAAALgAECgEJAQAAAA==.Liyra:BAABLgAECn8dAAMIAAkJNhuyIAAWAgAIAAkJNhuyIAAWAgABAAEJBBUJQQA5AAAAAA==.Lizcandor:BAAALgAECgMJCQAAAA==.',
Lo='Loafe:BAABLgAECn8oAAIHAAgJlg33SwBiAQAHAAgJlg33SwBiAQAAAA==.Lokni:BAAALgAECgYJEQAAAA==.Loumin:BAAALgADCgkJCQAAAA==.',
Lu='Ludacritz:BAAALgAECgUJBgAAAA==.Lunaignis:BAAALgADCgYJBgAAAA==.Lunasera:BAAALgADCgcJBwAAAA==.Luthais:BAAALgAECgYJDwAAAA==.Luxury:BAABLgAECn8ZAAIFAAgJdwH9HgDFAAAFAAgJdwH9HgDFAAAAAA==.',
Ma='Mahroq:BAABLgAECn8dAAMGAAcJFhyPEgDLAQAGAAcJFhyPEgDLAQAcAAEJkQIOXgAmAAAAAA==.Mako:BAACLgAFFH8FAAICAAIJ0hJVFwCQAAACAAIJ0hJVFwCQAAAuAAQKfxwAAgIACAn7IAMCAPICAAIACAn7IAMCAPICAAAA.Malarkeclark:BAAALgADCgkJCQAAAA==.Malevian:BAABLgAECn8nAAMDAAgJDwxpBwBCAQADAAgJyghpBwBCAQAEAAcJtgq4NQAjAQAAAA==.Malfuridan:BAAALgADCgYJCAAAAA==.Malocki:BAAALgADCgQJCgAAAA==.Maples:BAABLgAECn8jAAMfAAkJhwiEHABmAQAfAAkJhwiEHABmAQAWAAMJ3gG9cAAVAAAAAA==.Mariasha:BAAALgADCgkJHAAAAA==.Marichika:BAAALgADCgYJBgAAAA==.Mazzikin:BAABLgAECn8ZAAIJAAgJdh3jIACMAgAJAAgJdh3jIACMAgAAAA==.',
Mc='Mcdodgy:BAAALgADCgEJAQAAAA==.',
Me='Megaterium:BAABLgAECn8gAAMGAAYJkhoQFgCjAQAGAAYJkhoQFgCjAQAhAAMJ3wTBUwB2AAAAAA==.Menethil:BAABLgAECn8VAAIIAAYJRyQsDwAoAgAIAAYJRyQsDwAoAgAAAA==.Metheuz:BAAALgADCgIJAgABLgADCgYJAwATAAAAAA==.Mexican:BAABLgAECn8iAAILAAgJvA8BSACPAQALAAgJvA8BSACPAQAAAA==.',
Mi='Midnightlock:BAAALgAECgYJDQAAAA==.Midnyght:BAAALgAECgIJAgAAAA==.Mishgrail:BAABLgAECn8fAAIUAAkJWRvfBQCAAgAUAAkJWRvfBQCAAgAAAA==.Missmisery:BAAALgAECgcJEQAAAA==.Mithdraug:BAAALgAECgYJDwAAAA==.Mitzi:BAACLgAFFH8TAAMRAAYJNBbcEABeAQARAAUJNBbcEABeAQAaAAEJAAA2MQAAAAAuAAQKfyQAAhEACQlwI3MNAJgCABEACQlwI3MNAJgCAAAA.',
Mo='Molsan:BAAALgAECgQJBAAAAA==.Monache:BAABLgAECn8UAAIMAAYJ/QkqLwARAQAMAAYJ/QkqLwARAQAAAA==.Mongalf:BAAALgADCgQJBAAAAA==.Montrois:BAAALgAECgMJAwAAAA==.Moopally:BAAALgAECgQJCAAAAA==.',
['Mô']='Môônmôôn:BAAALgADCgYJBgAAAA==.',
Ne='Neletheus:BAABLgAECn8WAAIYAAcJihAXQABpAQAYAAcJihAXQABpAQAAAA==.Nephbrew:BAAALgADCgEJAQAAAA==.Nephren:BAAALgADCgYJBgAAAA==.Nephwren:BAAALgADCgUJBQAAAA==.',
Ni='Nightparade:BAAALgAECgYJEAAAAA==.Nirvanik:BAAALgADCgcJAgAAAA==.Nishgrail:BAAALgADCgYJBAABLgAECgkJHwAUAFkbAA==.',
Nu='Nukusmaximus:BAAALgAECgYJEQAAAA==.',
Ny='Nyeneave:BAAALgAECgIJAgAAAA==.Nyiah:BAABLgAECn8WAAIQAAgJyhblHgDNAQAQAAgJyhblHgDNAQAAAA==.',
['Nä']='Närgazeth:BAAALgADCgMJAwAAAA==.',
Og='Ogdoadtl:BAAALgADCgkJKAAAAA==.',
Oh='Ohello:BAAALgADCgUJBQAAAA==.',
Ol='Oldbull:BAAALgADCgEJAQAAAA==.',
On='Onex:BAAALgAECgYJCQAAAA==.',
Or='Organicmeat:BAAALgAECggJCQAAAA==.Orgrím:BAAALgADCgMJAwAAAA==.',
Pa='Palii:BAAALgAECgQJBAAAAA==.Partywizard:BAAALgAECgMJAwAAAA==.',
Pe='Persefini:BAAALgAECgYJCgAAAA==.Persephoneia:BAAALgADCgcJDQAAAA==.Petrokull:BAAALgADCgkJOgAAAA==.',
Ph='Pheeguh:BAAALgADCgkJEAAAAA==.Pheylan:BAAALgAECgEJBQAAAA==.Philidox:BAAALgAECgYJBgABLgAECggJGgABAMwTAA==.Phood:BAAALgADCgcJBwAAAA==.',
Pi='Pikxs:BAAALgAECgMJAgAAAA==.Pitchou:BAAALgAECgQJBQAAAA==.',
Pl='Plugugly:BAAALgAECgIJAgAAAA==.',
Po='Poenin:BAAALgADCgYJBgAAAA==.Pokeball:BAAALgAECgYJDAAAAA==.Polinemarois:BAAALgADCggJBwAAAA==.Porkque:BAABLgAECn8fAAISAAkJHQ2vIwDHAQASAAkJHQ2vIwDHAQAAAA==.Potatobear:BAABLgAECn8kAAQiAAkJCSGwAwCWAgAiAAkJYBqwAwCWAgAXAAYJXyPpGQBbAgASAAQJBCM+LACeAQAAAA==.',
Pr='Prifduwies:BAAALgADCgcJAQAAAA==.Professorson:BAAALgAECgIJAgAAAA==.',
Qu='Quicktime:BAABLgAECn8qAAIJAAgJ7R2pDgBSAgAJAAgJ7R2pDgBSAgAAAA==.',
Ra='Ragedh:BAAALgAECgMJAwAAAA==.Ragnarlothbr:BAAALgADCgQJBAAAAA==.Ragnoir:BAAALgAECggJCAAAAA==.Ranillan:BAAALgAECgYJBgAAAA==.Rased:BAAALgADCgEJAQAAAA==.Rashish:BAAALgADCgIJAgAAAA==.Ravies:BAAALgAECgEJAwAAAA==.Rawdøg:BAAALgADCgEJAQAAAA==.Rayaz:BAAALgAECgUJBwABLgAECggJDQATAAAAAA==.',
Re='Reeses:BAEALgADCgkJHwAAAA==.Reinharts:BAAALgAFFAEJAQAAAA==.Religgar:BAABLgAECn8dAAIRAAgJQQ+vMwCqAQARAAgJQQ+vMwCqAQAAAA==.Rethart:BAAALgADCgcJBwAAAA==.',
Rh='Rhilik:BAAALgADCgQJBAAAAA==.',
Ri='Ricter:BAABLgAECn8dAAILAAcJFQ4eVQBtAQALAAcJFQ4eVQBtAQAAAA==.Rictor:BAAALgAECgIJAwAAAA==.',
Ro='Roglof:BAAALgAECgkJDwAAAA==.Rokkoks:BAAALgADCgYJDgAAAA==.Rowlah:BAAALgADCggJCgAAAA==.Roxyfoxy:BAAALgAECgMJBAAAAA==.Rozy:BAABLgAECn8vAAIIAAkJGBsQCACUAgAIAAkJGBsQCACUAgAAAA==.',
Ru='Ruffs:BAABLgAECn8WAAMJAAkJIB10CACeAgAJAAkJIB10CACeAgAjAAEJYhDkHQA3AAAAAA==.Ruiizu:BAABLgAECn8iAAIHAAgJSiMcCgC4AgAHAAgJSiMcCgC4AgAAAA==.Rulnathil:BAAALgADCgMJBgAAAA==.Rushuna:BAABLgAECn8jAAIcAAgJcRoICwAiAgAcAAgJcRoICwAiAgAAAA==.',
Sa='Saberjaw:BAABLgAECn8XAAMiAAYJrBWcGQA6AQAiAAYJkRScGQA6AQASAAIJvwvJoABSAAAAAA==.Sairicck:BAABLgAECn8dAAISAAgJdh1yHgDlAQASAAgJdh1yHgDlAQAAAA==.Samaal:BAAALgADCgUJBQAAAA==.Samial:BAAALgADCgYJDAAAAA==.Sanguinor:BAAALgADCgYJFAAAAA==.Santamorte:BAAALgADCggJCgAAAA==.Sashay:BAAALgADCgYJCwAAAA==.Satoru:BAAALgAECgEJAgAAAA==.Satsuki:BAAALgADCgEJAQAAAA==.',
Sc='Scuba:BAAALgAECgUJCAAAAA==.',
Se='Selesé:BAAALgAECgEJAQABLgAECggJDgATAAAAAA==.Selinora:BAAALgAECgkJDgAAAA==.Serhalatath:BAAALgAECgQJBwAAAA==.',
Sh='Shadowsbane:BAAALgADCgEJAQAAAA==.Shaguar:BAABLgAECn8bAAMHAAgJAx/nGwAgAgAHAAcJlx/nGwAgAgAIAAcJPhB/XAALAQAAAA==.Shamhawk:BAAALgADCgMJBgAAAA==.Shaolinsnake:BAAALgAECgUJCQAAAA==.Shiiva:BAAALgADCgMJAwAAAA==.Shizukahime:BAAALgAECgMJAwAAAA==.Shizzite:BAAALgADCgEJAQAAAA==.',
Si='Sicken:BAAALgADCgIJAgAAAA==.Sigiloc:BAAALgADCgcJBwAAAA==.Silverchair:BAAALgADCgQJBAAAAA==.Singe:BAABLgAECn8iAAILAAgJtxBYaQADAgALAAgJtxBYaQADAgAAAA==.Sinzala:BAABLgAECn8ZAAILAAkJmhx6JwAFAgALAAkJmhx6JwAFAgAAAA==.',
Sk='Skeetsurfin:BAAALgADCgYJBgAAAA==.Skelly:BAAALgADCgYJCwAAAA==.Skyman:BAAALgADCgkJEwAAAA==.',
Sm='Smallblackdk:BAAALgAECgMJAwAAAA==.Smaugdor:BAAALgADCgcJBgAAAA==.',
Sn='Snorp:BAAALgAECgQJBAAAAA==.',
So='Solai:BAAALgAECgEJAQAAAA==.Solsti:BAABLgAECn8fAAIIAAkJcxYHDgA3AgAIAAkJcxYHDgA3AgAAAA==.',
Sp='Spears:BAAALgAECgUJBwAAAA==.Spoondot:BAABLgAECn8VAAMYAAcJbSPuFAA6AgAYAAcJth7uFAA6AgAkAAUJAyDdBwDRAQAAAA==.Spoonknight:BAAALgAECgkJDQAAAA==.',
Sq='Squidge:BAAALgAECgIJAgAAAA==.',
St='Staceyrella:BAAALgADCgMJAwAAAA==.Stainpngolin:BAABLgAECn8WAAIKAAYJWB/4BwCwAQAKAAYJWB/4BwCwAQAAAA==.Stillhorn:BAABLgAECn8VAAMJAAgJsRXzHwDJAQAJAAgJsRXzHwDJAQAbAAIJ/A8GPAA7AAAAAA==.Stinjeras:BAABLgAECn8iAAIYAAgJOyGeDACKAgAYAAgJOyGeDACKAgAAAA==.Stinkyjo:BAABLgAECn8iAAIQAAgJYhnLEABNAgAQAAgJYhnLEABNAgAAAA==.Stokelys:BAAALgADCgMJAwAAAA==.Stormfeather:BAAALgAECgEJAQAAAA==.Strikerv:BAABLgAECn8fAAISAAkJKR3jHABYAgASAAkJKR3jHABYAgAAAA==.',
Su='Sunadoria:BAAALgAECgUJDgAAAA==.Sunrae:BAAALgAECgYJEgAAAA==.Sushi:BAABLgAECn8WAAIUAAgJXw9uGAB0AQAUAAgJXw9uGAB0AQAAAA==.',
Sv='Sven:BAAALgAECgUJCQAAAA==.',
Sy='Sylinsor:BAAALgADCgEJAQAAAA==.Symor:BAAALgAECgIJAgAAAA==.',
['Sö']='Söap:BAAALgAECgUJBQAAAA==.',
Ta='Tahl:BAABLgAECn8jAAIGAAcJXRFgGQCDAQAGAAcJXRFgGQCDAQAAAA==.Tamanovitch:BAAALgAECgEJAQAAAA==.Tamashii:BAAALgAECgEJAQAAAA==.Tangriah:BAAALgADCgEJAQAAAA==.Taproot:BAAALgADCgEJAQABLgAFFAQJCQALAA0LAA==.Taryen:BAAALgAECgEJAQABLgAECgMJAwATAAAAAA==.Tavie:BAABLgAFFH8MAAILAAQJzRU7JwBaAQALAAQJzRU7JwBaAQAAAA==.',
Te='Teddy:BAAALgADCgYJBgAAAA==.Tedo:BAAALgADCgcJDAABLgAFFAMJCAAIAOEYAA==.Teikkas:BAAALgAECgYJCgAAAA==.Telaari:BAAALgAECgEJAQAAAA==.',
Th='Thalenia:BAABLgAECn8nAAMXAAgJVgmRDwD0AAASAAYJFAwqYQBEAQAXAAgJYQaRDwD0AAAAAA==.Thallenia:BAAALgADCgEJAQAAAA==.Thalron:BAAALgADCgEJAQAAAA==.Thekingdom:BAABLgAECn8aAAILAAgJVh1ZRQBnAgALAAgJVh1ZRQBnAgAAAA==.Thriller:BAAALgAECgQJBgABLgAFFAMJCAAIAOEYAA==.Thunderfuzz:BAABLgAECn8nAAMQAAgJxx19HgBLAgAQAAgJxx19HgBLAgAVAAgJKhMuEwCrAQAAAA==.',
Ti='Tikeidari:BAABLgAECn8mAAIjAAgJ2CNCAQC1AgAjAAgJ2CNCAQC1AgABLgAECggJKAAaAB4iAA==.Tiltedtroll:BAABLgAECn8dAAINAAgJIhH6HABmAQANAAgJIhH6HABmAQAAAA==.Timedemon:BAABLgAECn8mAAIJAAkJcRuWDgBTAgAJAAkJcRuWDgBTAgAAAA==.Tinuveuil:BAAALgADCgYJBgAAAA==.',
To='Tonjuras:BAAALgAECggJEQAAAA==.Toona:BAABLgAECn8bAAIJAAgJvR0CHACqAgAJAAgJvR0CHACqAgAAAA==.Torogrande:BAAALgADCgkJKgAAAA==.Touchmyting:BAAALgAECgEJAgAAAA==.Toutii:BAAALgAECgMJAwAAAA==.',
Tr='Trappydh:BAAALgAFFAMJBAAAAA==.Trappydk:BAABLgAECn8WAAIaAAgJhRoKCAAJAgAaAAgJhRoKCAAJAgABLgAFFAMJBAATAAAAAA==.Trintran:BAAALgADCgIJAgAAAA==.',
Tu='Tulshira:BAAALgADCgYJBgAAAA==.',
Tw='Twocents:BAABLgAECn8sAAMYAAgJsST9BgDUAgAYAAgJsST9BgDUAgAkAAEJAADeIQBqAAAAAA==.',
Ty='Tyronne:BAAALgAECgcJBwAAAA==.',
Ul='Ultraball:BAAALgAECggJDgAAAA==.',
Un='Unagi:BAABLgAECn8aAAIiAAYJcAzJGgAvAQAiAAYJcAzJGgAvAQAAAA==.Unkelb:BAAALgADCgYJBgAAAA==.',
Va='Vaenessa:BAABLgAECn8WAAILAAcJSAh0bQA2AQALAAcJSAh0bQA2AQAAAA==.Vaesir:BAAALgADCgcJDQAAAA==.Varleara:BAABLgAECn8gAAMJAAgJziFCEwDmAgAJAAgJziFCEwDmAgAjAAEJKQeGLQAqAAAAAA==.',
Ve='Venenn:BAAALgADCgEJAgAAAA==.Venev:BAAALgAECgUJBQAAAA==.Ventana:BAABLgAECn8dAAIPAAgJThtHBAAqAgAPAAgJThtHBAAqAgAAAA==.Verdilac:BAABLgAECn8kAAIHAAgJCBoKTQD7AQAHAAgJCBoKTQD7AQAAAA==.',
Vi='Vinceglortho:BAAALgAECgIJAgAAAA==.Vindicator:BAAALgAECggJDwAAAA==.Violetnoir:BAAALgAECgQJBAABLgAECgcJGgAYANsIAA==.Visiroth:BAAALgAECggJEQAAAA==.',
Wa='Wagyumoo:BAAALgAECgEJAQABLgAECggJIgALALcQAA==.Wallydk:BAABLgAECn8WAAIRAAgJDhGXMAC3AQARAAgJDhGXMAC3AQAAAA==.Wanji:BAABLgAECn8bAAIRAAgJTAfcSwBXAQARAAgJTAfcSwBXAQAAAA==.',
We='Weave:BAAALgADCgYJBgAAAA==.Westhresh:BAAALgADCgcJBwAAAA==.',
Wi='Widginatrix:BAAALgAECggJCwAAAA==.Willkain:BAAALgAECgMJAwAAAA==.',
Wo='Woons:BAAALgAECgIJBQAAAA==.',
Wr='Wraithbane:BAAALgAECgMJAwAAAA==.',
Xa='Xaya:BAABLgAECn8aAAMYAAcJ2wj/UwAwAQAYAAcJ2wj/UwAwAQAZAAQJ6AJDUQB6AAAAAA==.',
Xi='Xiva:BAABLgAECn8WAAIlAAYJQQwCGwAoAQAlAAYJQQwCGwAoAQAAAA==.',
Xo='Xovace:BAAALgAECgYJDAAAAA==.',
Xt='Xtayse:BAABLgAECn8WAAIDAAgJahygAgAZAgADAAgJahygAgAZAgAAAA==.',
Ya='Yamyam:BAABLgAECn8VAAIVAAkJsg/EKQCyAQAVAAkJsg/EKQCyAQAAAA==.',
Yf='Yfelril:BAAALgADCgQJBAABLgAECgYJEQATAAAAAA==.',
Yo='Yoruechi:BAABLgAECn8pAAIKAAgJKCOqAQC/AgAKAAgJKCOqAQC/AgAAAA==.',
['Yú']='Yúmyúm:BAABLgAECn8ZAAIHAAgJvRV2LQDHAQAHAAgJvRV2LQDHAQAAAA==.',
Za='Zahel:BAABLgAECn8lAAIHAAkJjR09DQCWAgAHAAkJjR09DQCWAgAAAA==.Zahrogue:BAAALgADCgYJBgABLgAECgkJJQAHAI0dAA==.Zalark:BAAALgADCgUJCgABLgAECggJHwAGAEQOAA==.Zangai:BAAALgADCgUJBQAAAA==.',
Ze='Zeneri:BAABLgAECn8fAAMfAAkJEhB1EgDQAQAfAAkJEhB1EgDQAQAWAAQJNQnqRQBlAAAAAA==.',
Zo='Zobi:BAAALgAECgIJAgAAAA==.Zomboo:BAAALgAFFAEJAQAAAA==.',
Zu='Zugzugzug:BAAALgADCgMJBgAAAA==.',
['Zò']='Zònan:BAAALgADCgEJAQABLgAECgkJIAAOAMwSAA==.',
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

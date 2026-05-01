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

local lookup = {'Paladin-Protection','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Warrior-Protection','Priest-Holy','Paladin-Retribution','Paladin-Holy','DemonHunter-Devourer','Druid-Guardian','Mage-Frost','Warrior-Fury','Shaman-Elemental','Shaman-Restoration','Shaman-Enhancement','Druid-Restoration','DeathKnight-Unholy','Hunter-BeastMastery','Unknown-Unknown','Druid-Balance','Monk-Windwalker','Hunter-Marksmanship','Warlock-Demonology','Warlock-Destruction','DeathKnight-Blood','DemonHunter-Vengeance','DemonHunter-Havoc','Priest-Discipline','Druid-Feral','Warrior-Arms','Priest-Shadow','Monk-Mistweaver','Monk-Brewmaster','Hunter-Survival','Warlock-Affliction',}
local provider = {region='US',realm='Uther',name='US',type='weekly',zone=46,date='2026-05-01',data={Ad='Addiction:BAAALgADCgYJAQAAAA==.',
Ah='Ahmet:BAAALgAECggJEgABLgAECgkJJQABALkaAA==.',
Ai='Aiax:BAABLgAECn8XAAQCAAgJTgw1IAAsAQADAAYJpw27MQA6AQACAAYJZAo1IAAsAQAEAAIJQAc/RgBAAAAAAA==.',
Al='Aliancia:BAABLgAECn8VAAIFAAYJLw7RFADlAAAFAAYJLw7RFADlAAAAAA==.Almur:BAAALgADCggJGgAAAA==.Alyda:BAAALgADCggJFAAAAA==.',
Am='Amet:BAABLgAECn8lAAIBAAkJuRp8BQCfAgABAAkJuRp8BQCfAgAAAA==.',
An='Anakinn:BAAALgAECgUJBQAAAA==.Annailuj:BAAALgADCgIJAgAAAA==.Annora:BAABLgAECn8hAAIGAAgJjRl2FgApAgAGAAgJjRl2FgApAgAAAA==.Antherina:BAAALgADCgQJBwAAAA==.Antonious:BAAALgADCgMJAwAAAA==.Antonlavay:BAAALgAECgQJBAAAAA==.',
Ap='Aphyra:BAAALgADCgUJBQAAAA==.Apollyøn:BAABLgAECn8cAAMHAAgJCiKJBgCxAgAHAAgJCiKJBgCxAgAIAAIJKhWffgB/AAAAAA==.',
Ar='Arlechino:BAABLgAECn8cAAIJAAgJFhdWQADzAQAJAAgJFhdWQADzAQAAAA==.Arywyn:BAAALgAECgQJCgAAAA==.',
As='Assclapiuss:BAABLgAECn8cAAIHAAgJ8SSXBQDAAgAHAAgJ8SSXBQDAAgAAAA==.Asterchades:BAABLgAECn8fAAIKAAgJWhmqBQCrAQAKAAgJWhmqBQCrAQAAAA==.Astlin:BAAALgAECgEJAQAAAA==.Astraeastar:BAAALgADCgUJBQAAAA==.',
At='Athennah:BAAALgAECgcJBwAAAA==.Atrei:BAAALgADCgIJAgAAAA==.Attikus:BAABLgAECn8eAAILAAgJsALhgQDQAAALAAgJsALhgQDQAAAAAA==.Atuan:BAAALgAECgQJCQAAAA==.',
Au='Auralass:BAAALgAECgYJDQAAAA==.Aurene:BAAALgAECggJGgAAAQ==.',
Av='Avatard:BAAALgAECgIJAgABLgAECggJIgALAKsQAA==.',
Ax='Axem:BAABLgAECn8UAAIMAAcJUxJMSQB/AQAMAAcJUxJMSQB/AQAAAA==.',
Az='Azlanii:BAAALgADCggJCgAAAA==.Azulathan:BAAALgAECgYJDAABLgAECggJLAANAKUPAA==.',
Ba='Bamseyn:BAAALgADCgYJBgAAAA==.Baraxor:BAABLgAECn8sAAMNAAgJpQ9bFQBrAQANAAgJpQ9bFQBrAQAOAAQJDhT2bgDTAAAAAA==.Barrelaged:BAAALgADCggJCwAAAA==.',
Be='Beerguy:BAAALgADCggJBAAAAA==.Behemothe:BAABLgAECn8fAAIPAAgJ2B3zAgApAgAPAAgJ2B3zAgApAgAAAA==.Berníesandrs:BAABLgAECn8nAAILAAgJSQ2SPQB1AQALAAgJSQ2SPQB1AQAAAA==.Beryllos:BAAALgADCgkJLgAAAA==.Bevela:BAAALgADCgIJAgAAAA==.',
Bi='Biddies:BAAALgAECgYJBwAAAA==.Bigimpin:BAAALgADCgcJBwAAAA==.',
Bj='Bjôrn:BAAALgAECgcJCgAAAA==.',
Bl='Bledana:BAAALgADCggJCgAAAA==.Bleué:BAAALgADCgEJAQABLgAECggJHAAQANAZAA==.Bloodmourne:BAABLgAECn8aAAIRAAgJ8iEoCACbAgARAAgJ8iEoCACbAgAAAA==.Bloodytoutii:BAAALgAECgUJBQAAAA==.',
Bo='Borthyr:BAABLgAECn8ZAAMDAAgJ6Bp1CAAIAgADAAgJFxd1CAAIAgACAAYJ0RylDgDwAQAAAA==.Bowowner:BAABLgAECn8YAAISAAgJUx5xCwBJAgASAAgJUx5xCwBJAgAAAA==.',
Br='Branchmanagr:BAABLgAECn8YAAIKAAgJZA7zCQAvAQAKAAgJZA7zCQAvAQAAAA==.Brewlee:BAAALgAECgkJDAAAAA==.Brokenkrayon:BAAALgAECgIJAwAAAA==.Brokkr:BAAALgADCgQJBwAAAA==.Bryce:BAAALgAECgEJAQAAAA==.',
Bu='Busta:BAABLgAECn8fAAILAAkJYQVaTABLAQALAAkJYQVaTABLAQAAAA==.',
Bw='Bwicked:BAAALgAECgYJDQAAAA==.',
['Bé']='Béck:BAAALgADCgEJAQAAAA==.',
['Bü']='Büg:BAAALgAECgYJDQAAAA==.',
Ca='Caedars:BAAALgADCgEJAQAAAA==.Cantpurge:BAAALgADCgIJAgABLgAECgYJEAATAAAAAA==.',
Ch='Chamelean:BAAALgAECgYJDQABLgAECggJEwAJAAYUAA==.Chimpnzthat:BAAALgAECgYJEAAAAA==.Chookicookie:BAABLgAECn8rAAMOAAgJvh8yFgBkAgAOAAgJvh8yFgBkAgANAAQJFxU5LQDLAAAAAA==.Chuckarita:BAABLgAECn8XAAIUAAcJBglRIAD7AAAUAAcJBglRIAD7AAAAAA==.',
Ci='Cindyy:BAABLgAECn8WAAIVAAcJdxk9CwDBAQAVAAcJdxk9CwDBAQABLgAECggJGAASAI0YAA==.Civaelia:BAAALgADCgMJAwAAAA==.',
Cl='Clutterbear:BAAALgADCgIJAgAAAA==.',
Co='Cornpuff:BAAALgAECgQJCAAAAA==.Cortiz:BAABLgAECn8fAAISAAgJiQ45IQCaAQASAAgJiQ45IQCaAQAAAA==.',
Cr='Crankdog:BAABLgAECn8WAAMSAAgJuB9QBwCCAgASAAgJuB9QBwCCAgAWAAYJ8g87SgApAQAAAA==.Creedd:BAABLgAECn8oAAIQAAgJGCCkBQDEAgAQAAgJGCCkBQDEAgAAAA==.Crialta:BAAALgADCgcJDwAAAA==.',
Cu='Cupsandcakes:BAAALgAECgYJDAAAAA==.',
Cy='Cynaidia:BAAALgAECgQJBwAAAA==.',
Da='Dacarry:BAAALgAECgIJAgAAAA==.Damessiah:BAABLgAECn8ZAAIGAAYJhhDRHQAUAQAGAAYJhhDRHQAUAQAAAA==.Dark:BAABLgAECn8dAAIXAAgJfR9CIACXAgAXAAgJfR9CIACXAgAAAA==.Darkphyre:BAAALgAECgQJCgAAAA==.Darthtree:BAAALgADCgEJAQAAAA==.Dawling:BAAALgADCggJDgAAAA==.',
De='Deadmandan:BAABLgAECn8jAAMXAAkJpyR8AgAKAwAXAAkJpyR8AgAKAwAYAAYJISSvBwBMAgAAAA==.Deathomen:BAAALgADCgcJBwAAAA==.Deathtike:BAABLgAECn8eAAIZAAgJMB4YBQDnAQAZAAgJMB4YBQDnAQABLgAECggJHwAaABYjAA==.Decius:BAAALgAECgQJCQAAAA==.Demagorgin:BAABLgAECn8lAAIHAAgJuxcuFwACAgAHAAgJuxcuFwACAgAAAA==.Demcheekz:BAAALgAECgIJAgAAAA==.Demiurge:BAAALgAECgUJBQAAAA==.Demondred:BAAALgAECgQJCQAAAA==.Demonplug:BAAALgADCgEJAQAAAA==.Demonrae:BAAALgAECgIJAgAAAA==.Deqlyn:BAABLgAECn8aAAIHAAgJhhu5FgAFAgAHAAgJhhu5FgAFAgAAAA==.Desmus:BAAALgAECgYJEAAAAA==.Deterno:BAAALgADCgUJBQAAAA==.Devige:BAAALgADCgMJBAABLgAFFAQJBwAXAI4fAA==.Devilmaycry:BAAALgADCgEJAQAAAA==.Deáthreaver:BAAALgAECggJCgAAAA==.',
Di='Diglett:BAAALgADCgYJAQAAAA==.Dimsum:BAAALgAECgUJBgAAAA==.Diqtator:BAAALgADCgcJBwAAAA==.Dismal:BAABLgAECn8UAAIIAAgJiREJEADjAQAIAAgJiREJEADjAQAAAA==.Ditar:BAAALgAECgEJAQABLgAECgEJBQATAAAAAA==.',
Dk='Dk:BAAALgADCgIJAgABLgAFFAMJBgASAH4aAA==.',
Do='Domwarlock:BAAALgAFFAEJAQAAAA==.Doomdooms:BAAALgADCgEJAQAAAA==.Dots:BAAALgADCggJDgAAAA==.',
Dr='Dradin:BAAALgADCgMJAwAAAA==.Dronin:BAABLgAECn8VAAIWAAYJ2BEKCgAxAQAWAAYJ2BEKCgAxAQAAAA==.Drpatan:BAAALgAECgYJDgAAAA==.Druni:BAAALgAECgQJCgAAAA==.Dryan:BAAALgADCgEJAQAAAA==.',
Ec='Echowalker:BAAALgAECgYJCwAAAA==.',
Ee='Eecho:BAAALgADCgEJAQAAAA==.',
Ei='Eisenthorne:BAAALgADCgEJAgAAAA==.',
El='Eldruida:BAAALgADCgYJDAAAAA==.Elguezo:BAAALgAECgYJCQAAAA==.Elysyn:BAAALgADCgMJAwAAAA==.',
Em='Emaelia:BAAALgAECgQJBAAAAA==.Emokillaz:BAABLgAECn8WAAIbAAcJ1xjbDABuAQAbAAcJ1xjbDABuAQAAAA==.',
Ep='Epictaxes:BAAALgADCgEJAQAAAA==.Epimetheuz:BAAALgADCgYJAwAAAA==.Epsilón:BAAALgAECgYJEAAAAA==.',
Et='Eternalpeace:BAAALgAECgEJAQAAAA==.',
Ev='Evelana:BAAALgADCgQJBwAAAA==.',
Ex='Exaduss:BAAALgAECgcJEwAAAA==.',
Fa='Fastrolling:BAAALgADCgQJCgAAAA==.Faxon:BAAALgAECgcJEwAAAA==.Faylan:BAAALgAECgQJCgAAAA==.',
Fe='Feronnia:BAAALgADCgYJDgAAAA==.',
Fi='Fibot:BAABLgAECn8fAAIPAAgJIBu5AgA0AgAPAAgJIBu5AgA0AgAAAA==.Fingon:BAAALgAECgcJEgAAAA==.',
Fl='Flogor:BAAALgAECgcJBgABLgAECgkJDwATAAAAAA==.Florasol:BAAALgADCgIJAgAAAA==.',
Fo='Foxling:BAEALgAECgEJAQAAAA==.',
Fr='Fraeyah:BAAALgADCgYJCwAAAA==.Frahaad:BAAALgADCgQJBAAAAA==.Freebunz:BAABLgAECn8UAAILAAgJhRdoVAA7AgALAAgJhRdoVAA7AgAAAA==.',
Ga='Gahydra:BAAALgADCgkJEwAAAA==.Galvanize:BAACLgAFFH8HAAILAAMJdQx+NwD1AAALAAMJdQx+NwD1AAAuAAQKfysAAgsACAn7G3MeAPUBAAsACAn7G3MeAPUBAAAA.Gastdhunter:BAAALgAECgEJAQAAAA==.Gastrophos:BAAALgAECgEJAQAAAA==.',
Gh='Ghomertin:BAAALgADCggJCgAAAA==.',
Gi='Gimtar:BAAALgAECgEJBQAAAA==.Ginjockey:BAAALgADCgUJBQABLgAECgYJEAATAAAAAA==.Gipsydanger:BAABLgAECn8xAAIcAAgJ5h1oBQBkAgAcAAgJ5h1oBQBkAgAAAA==.Girllygirl:BAAALgAECgYJBgAAAA==.Givr:BAAALgADCgEJAQAAAA==.',
Gl='Glaurang:BAAALgADCgkJGQAAAA==.Glofor:BAAALgAECgcJBAABLgAECgkJDwATAAAAAA==.',
Gn='Gnarp:BAAALgADCgEJAQABLgAECgcJFgAOAFAYAA==.Gnomeregrets:BAAALgAECgMJAwABLgAECgUJBwATAAAAAA==.',
Go='Goldencorpse:BAAALgAECgIJAgAAAA==.Goldenspoon:BAAALgADCgEJAQAAAA==.Gorlokk:BAEALgADCgMJAwABLgADCgcJGwATAAAAAA==.',
Gr='Grakonys:BAABLgAECn8YAAMDAAgJXAxFEwBqAQADAAgJXAxFEwBqAQACAAcJ3Qc5HQBFAQAAAA==.Granger:BAAALgAECgIJAgAAAA==.Greed:BAABLgAECn8dAAIVAAcJ0xROIgDDAQAVAAcJ0xROIgDDAQAAAA==.Greensun:BAAALgADCgEJAQAAAA==.Grendol:BAAALgAECgMJAwAAAA==.Grimmbot:BAAALgADCgkJFAAAAA==.Grimmvelt:BAAALgADCggJDAAAAA==.Grunnck:BAAALgADCgYJDQAAAA==.',
Gu='Guayusa:BAAALgAECggJEwAAAA==.Gunned:BAAALgADCgEJAQAAAA==.',
Gw='Gwendolin:BAAALgAECgUJBQAAAA==.Gwenfrewi:BAAALgADCgEJAQABLgADCgEJAQATAAAAAA==.',
Ha='Hacheron:BAAALgADCgIJAgABLgAFFAEJAQATAAAAAA==.Hallows:BAAALgADCgIJAgAAAA==.Harnix:BAAALgAECgYJCwAAAA==.Hawtbooty:BAABLgAECn8WAAIGAAYJ6h0gHQD0AQAGAAYJ6h0gHQD0AQAAAA==.',
He='Heartsbane:BAAALgADCgYJDAAAAA==.Helixrage:BAAALgAECgcJEwAAAA==.Hellreines:BAAALgAECgYJDwAAAA==.Herpderplol:BAABLgAECn8XAAIdAAcJIxI8CABuAQAdAAcJIxI8CABuAQAAAA==.',
Hi='Hildi:BAAALgAECgYJEAAAAA==.Him:BAABLgAECn8XAAIMAAgJ2iPCAQDeAgAMAAgJ2iPCAQDeAgAAAA==.',
Ho='Holy:BAABLgAECn8iAAIcAAgJEB2xAwCkAgAcAAgJEB2xAwCkAgAAAA==.Hoots:BAAALgAECgEJAQAAAA==.',
Hu='Hucklebury:BAAALgADCgYJDQAAAA==.Hulkcrush:BAAALgADCgQJDAAAAA==.Humânity:BAAALgADCgYJBgAAAA==.',
['Hø']='Høåx:BAAALgADCgIJAgABLgADCgcJCwATAAAAAA==.',
Il='Illbloodarch:BAABLgAECn8VAAIeAAgJyAUaHQAHAQAeAAgJyAUaHQAHAQAAAA==.Illvicious:BAAALgAECgEJAQAAAA==.',
In='Incredibread:BAAALgAECgQJBAAAAA==.Indub:BAAALgAECgMJAwAAAA==.',
Is='Ishura:BAAALgAECgYJDwAAAA==.',
It='Itslevi:BAAALgAECgUJBgAAAA==.',
Iv='Ivvy:BAAALgAECgQJBwAAAA==.',
Iz='Izanami:BAAALgAECgYJDQAAAA==.',
Ja='Jaewreth:BAAALgAECgIJAgAAAA==.Janntro:BAAALgAECggJDwAAAA==.Jantra:BAAALgAECgEJAQAAAA==.Jantro:BAAALgAECgcJEwAAAA==.Janttro:BAAALgAECgEJAQAAAA==.Jaquavious:BAAALgADCgcJBwAAAA==.',
Je='Jeebz:BAABLgAECn8eAAMOAAgJ+BM9GwCKAQAOAAgJ+BM9GwCKAQANAAMJxQqObACRAAAAAA==.Jelmarr:BAAALgAECgYJBgAAAA==.Jemmâ:BAAALgAECgYJCwAAAA==.Jerauld:BAAALgAECgYJDwAAAA==.Jezrra:BAAALgAECggJDwAAAA==.',
Jh='Jhuloot:BAAALgADCgYJCQAAAA==.',
Ji='Jiddles:BAAALgADCgMJAwABLgAECgcJDwATAAAAAA==.',
Jo='Johnnyzyns:BAABLgAECn8aAAIRAAgJzxf4GgDmAQARAAgJzxf4GgDmAQAAAA==.Jokhasta:BAABLgAECn8ZAAIPAAgJqhY6BQDJAQAPAAgJqhY6BQDJAQAAAA==.Joshc:BAABLgAECn8aAAIKAAgJVAoHDgDXAAAKAAgJVAoHDgDXAAAAAA==.',
Jp='Jpmeister:BAAALgADCgkJDQAAAA==.',
Ju='Judgejudee:BAAALgADCgYJBQAAAA==.',
['Já']='Ják:BAABLgAECn8YAAMBAAgJ+hIKGwA2AQABAAcJJBEKGwA2AQAIAAIJ7QmEiQBWAAAAAA==.',
Ka='Kaaris:BAAALgAECgYJDQAAAA==.Kaiarie:BAAALgAECgYJDQAAAA==.Kainraziel:BAABLgAECn8TAAIJAAgJBhSGKwA3AQAJAAgJBhSGKwA3AQAAAA==.Kairos:BAABLgAECn8dAAILAAcJXQ0bYgAXAQALAAcJXQ0bYgAXAQAAAA==.Kalasta:BAAALgADCgIJAgAAAA==.Kanzak:BAAALgADCgcJCgAAAA==.Karkea:BAAALgAECgEJAgAAAA==.Kayper:BAAALgAECgcJAgAAAA==.',
Ke='Kebin:BAABLgAECn8aAAIFAAgJcBQ7CQCdAQAFAAgJcBQ7CQCdAQAAAA==.Kekkoken:BAAALgADCgkJCgAAAA==.Kelfhammer:BAAALgADCgQJBAAAAA==.Kenkenif:BAAALgADCgUJCAAAAA==.',
Kh='Khlorox:BAAALgADCgYJBgAAAA==.Khronin:BAAALgADCgIJAgAAAA==.',
Ki='Killmonger:BAAALgAECgYJCwAAAA==.',
Kl='Klöwÿ:BAAALgAECgEJAQAAAA==.',
Ko='Korax:BAAALgADCgUJBQAAAA==.Korgia:BAAALgAECgQJBAAAAA==.Kortharion:BAABLgAECn8aAAIEAAgJwB+SAQDbAgAEAAgJwB+SAQDbAgAAAA==.Korzillian:BAAALgAECgEJAQAAAA==.Kos:BAABLgAECn8ZAAIfAAgJrB15AwCDAgAfAAgJrB15AwCDAgAAAA==.',
Kr='Krixis:BAAALgADCgEJAgAAAA==.',
Ku='Kujiera:BAAALgAECgcJEwAAAA==.Kuntar:BAAALgAECgcJCgAAAA==.Kurgan:BAAALgADCggJCAAAAA==.Kurkoh:BAAALgAECgEJAgABLgAECgIJAgATAAAAAA==.Kurrent:BAAALgAECgcJDwAAAA==.',
['Kÿ']='Kÿtten:BAABLgAECn8aAAIBAAgJqwnOEAD1AAABAAgJqwnOEAD1AAAAAA==.',
La='Lad:BAAALgAECgUJCQABLgAECggJGwAJAL0dAA==.Laiyth:BAAALgAECggJDwAAAA==.Larryfish:BAAALgAECgcJEwAAAA==.Laslock:BAAALgADCgEJAQAAAA==.Lavahitman:BAAALgAECgEJAQAAAA==.Lavos:BAABLgAECn8aAAIYAAgJNgyiBgBOAQAYAAgJNgyiBgBOAQAAAA==.',
Le='Levitikus:BAAALgAECgEJAgAAAA==.Levìtikus:BAAALgAECgEJAQAAAA==.',
Li='Lighteyes:BAAALgADCgEJAQAAAA==.Lildragon:BAAALgAECgYJBgAAAA==.Lisster:BAABLgAECn8aAAMSAAgJFhkHDgArAgASAAgJFhkHDgArAgAWAAEJkAGlmAAeAAAAAA==.Littledoty:BAAALgAECgEJAQAAAA==.Liyra:BAABLgAECn8dAAMIAAkJORu1IAAWAgAIAAkJORu1IAAWAgABAAEJBBUNQQA5AAAAAA==.Lizcandor:BAAALgAECgMJCQAAAA==.',
Lo='Loafe:BAABLgAECn8oAAIHAAgJlA1ENQBuAQAHAAgJlA1ENQBuAQAAAA==.Lokni:BAAALgAECgYJEQAAAA==.Loumin:BAAALgADCgkJCQAAAA==.',
Lu='Ludacritz:BAAALgAECgUJBQAAAA==.Lunaignis:BAAALgADCgYJBgAAAA==.Lunasera:BAAALgADCgEJAQAAAA==.Luthais:BAAALgAECgQJCgAAAA==.Luxury:BAAALgAECgcJEwAAAA==.',
Ma='Mahroq:BAABLgAECn8aAAMGAAcJERyTDADbAQAGAAcJERyTDADbAQAcAAEJkQILXgAmAAAAAA==.Mako:BAABLgAECn8aAAIEAAgJ7SBFAQD7AgAEAAgJ7SBFAQD7AgAAAA==.Malarkeclark:BAAALgADCgkJCQAAAA==.Malevian:BAABLgAECn8nAAMCAAgJBgxSBQBcAQACAAgJrwhSBQBcAQADAAcJtwq5NQAjAQAAAA==.Malfuridan:BAAALgADCgYJCAAAAA==.Malocki:BAAALgADCgQJCgAAAA==.Maples:BAABLgAECn8jAAMgAAkJigibFABuAQAgAAkJigibFABuAQAVAAMJ3gE6VwAUAAAAAA==.Mariasha:BAAALgADCggJFwAAAA==.Mazzikin:BAABLgAECn8VAAIJAAgJoxvnIACMAgAJAAgJoxvnIACMAgAAAA==.',
Mc='Mcdodgy:BAAALgADCgEJAQAAAA==.',
Me='Megaterium:BAABLgAECn8cAAMGAAYJ0hUXMQB8AQAGAAYJ0hUXMQB8AQAfAAMJ3wTBUwB2AAAAAA==.Menethil:BAAALgAECgYJDQAAAA==.Metheuz:BAAALgADCgIJAgABLgADCgYJAwATAAAAAA==.Mexican:BAABLgAECn8aAAILAAgJoQ91NQCPAQALAAgJoQ91NQCPAQAAAA==.',
Mi='Midnightlock:BAAALgAECgYJDQAAAA==.Midnyght:BAAALgADCgkJMQAAAA==.Mishgrail:BAABLgAECn8aAAIhAAgJ6RmYBwAdAgAhAAgJ6RmYBwAdAgAAAA==.Missmisery:BAAALgAECgYJDgAAAA==.Mithdraug:BAAALgAECgQJCgAAAA==.Mitzi:BAACLgAFFH8SAAMRAAYJDRXaEABeAQARAAUJDRXaEABeAQAZAAEJAADRJAAAAAAuAAQKfyQAAhEACQlwI8sHAKICABEACQlwI8sHAKICAAAA.',
Mo='Molsan:BAAALgAECgMJAwAAAA==.Monache:BAABLgAECn8UAAIMAAYJAApDIwAfAQAMAAYJAApDIwAfAQAAAA==.Mongalf:BAAALgADCgQJBAAAAA==.Montrois:BAAALgADCgcJCwAAAA==.Moopally:BAAALgAECgQJCAAAAA==.',
['Mô']='Môônmôôn:BAAALgADCgYJBgAAAA==.',
Ne='Neletheus:BAABLgAECn8WAAIXAAcJiRB2LwBuAQAXAAcJiRB2LwBuAQAAAA==.Nephbrew:BAAALgADCgEJAQAAAA==.Nephren:BAAALgADCgYJBgAAAA==.Nephwren:BAAALgADCgUJBQAAAA==.',
Ni='Nightparade:BAAALgAECgQJCwAAAA==.Nirvanik:BAAALgADCgcJAgAAAA==.Nishgrail:BAAALgADCgYJBAABLgAECggJGgAhAOkZAA==.',
Nu='Nukusmaximus:BAAALgAECgYJCwAAAA==.',
Ny='Nyeneave:BAAALgADCggJCAAAAA==.Nyiah:BAAALgAECgcJEwAAAA==.',
['Nä']='Närgazeth:BAAALgADCgMJAwAAAA==.',
Og='Ogdoadtl:BAAALgADCgkJJwAAAA==.',
Oh='Ohello:BAAALgADCgUJBQAAAA==.',
Ol='Oldbull:BAAALgADCgEJAQAAAA==.',
On='Onex:BAAALgAECgMJBAAAAA==.',
Or='Organicmeat:BAAALgAECggJCQAAAA==.Orgrím:BAAALgADCgMJAwAAAA==.',
Pa='Palii:BAAALgAECgQJBAAAAA==.Partywizard:BAAALgAECgMJAwAAAA==.',
Pe='Persefini:BAAALgAECgQJBQAAAA==.Persephoneia:BAAALgADCgcJDQAAAA==.Petrokull:BAAALgADCgkJMQAAAA==.',
Ph='Pheeguh:BAAALgADCgkJEAAAAA==.Pheylan:BAAALgAECgEJBAAAAA==.Philidox:BAAALgAECgYJBgABLgAECggJGAABAPoSAA==.Phood:BAAALgADCgcJBwAAAA==.',
Pi='Pikxs:BAAALgAECgMJAgAAAA==.Pitchou:BAAALgAECgQJBAAAAA==.',
Pl='Plugugly:BAAALgAECgIJAgAAAA==.',
Po='Poenin:BAAALgADCgYJBgAAAA==.Pokeball:BAAALgAECgYJDAAAAA==.Polinemarois:BAAALgADCggJBwAAAA==.Porkque:BAABLgAECn8aAAISAAgJWg1YIwCPAQASAAgJWg1YIwCPAQAAAA==.Potatobear:BAABLgAECn8fAAQiAAgJDSKuAwBbAgAWAAYJXyOGGQBbAgAiAAgJyRuuAwBbAgASAAEJWR9KvABLAAAAAA==.',
Pr='Prifduwies:BAAALgADCgcJAQAAAA==.Professorson:BAAALgAECgIJAgAAAA==.',
Qu='Quicktime:BAABLgAECn8iAAIJAAgJ1R1MCABVAgAJAAgJ1R1MCABVAgAAAA==.',
Ra='Ragedh:BAAALgAECgMJAwAAAA==.Ragnarlothbr:BAAALgADCgQJBAAAAA==.Ragnoir:BAAALgADCgYJBgAAAA==.Ranillan:BAAALgAECgYJBgAAAA==.Rased:BAAALgADCgEJAQAAAA==.Rashish:BAAALgADCgIJAgAAAA==.Ravies:BAAALgAECgEJAgAAAA==.Rawdøg:BAAALgADCgEJAQAAAA==.Rayaz:BAAALgAECgUJBQABLgAECgcJCwATAAAAAA==.',
Re='Reeses:BAEALgADCgcJGwAAAA==.Reinharts:BAAALgAECgUJCwAAAA==.Religgar:BAABLgAECn8XAAIRAAYJkBEoQAA+AQARAAYJkBEoQAA+AQAAAA==.Reploidzero:BAAALgADCgkJCwAAAA==.Rethart:BAAALgADCgcJBwAAAA==.',
Rh='Rhilik:BAAALgADCgQJBAAAAA==.',
Ri='Ricter:BAAALgAECgcJEQAAAA==.Rictor:BAAALgAECgIJAwAAAA==.',
Ro='Roglof:BAAALgAECgkJDwAAAA==.Rokkoks:BAAALgADCgYJDgAAAA==.Rowlah:BAAALgADCggJCgAAAA==.Roxyfoxy:BAAALgAECgMJAwAAAA==.Rozy:BAABLgAECn8oAAIIAAkJ0BpsEgB/AgAIAAkJ0BpsEgB/AgAAAA==.',
Ru='Ruffs:BAABLgAECn8UAAMJAAgJhR2HCABRAgAJAAgJhR2HCABRAgAaAAEJQRA8FwA7AAAAAA==.Ruiizu:BAABLgAECn8aAAIHAAgJpyC5CACRAgAHAAgJpyC5CACRAgAAAA==.Rulnathil:BAAALgADCgMJBgAAAA==.Rushuna:BAABLgAECn8bAAIcAAgJOhkEEAA/AgAcAAgJOhkEEAA/AgAAAA==.',
Sa='Saberjaw:BAABLgAECn8XAAMiAAYJrBUREgBFAQAiAAYJkRQREgBFAQASAAIJvwtEfgBVAAAAAA==.Sairicck:BAABLgAECn8VAAISAAgJ/hzkEwDzAQASAAgJ/hzkEwDzAQAAAA==.Samaal:BAAALgADCgUJBQAAAA==.Samial:BAAALgADCgYJDAAAAA==.Sanguinor:BAAALgADCgYJFAAAAA==.Santamorte:BAAALgADCgYJBwAAAA==.Sashay:BAAALgADCgYJCwAAAA==.Satoru:BAAALgAECgEJAgAAAA==.Satsuki:BAAALgADCgEJAQAAAA==.',
Sc='Scuba:BAAALgAECgUJCAAAAA==.',
Se='Selesé:BAAALgAECgEJAQABLgAECgYJCwATAAAAAA==.Selinora:BAAALgAECggJDQAAAA==.Serhalatath:BAAALgAECgQJBgAAAA==.',
Sh='Shadowsbane:BAAALgADCgEJAQAAAA==.Shaguar:BAABLgAECn8aAAMHAAgJ9xxCGwDnAQAHAAYJbiFCGwDnAQAIAAcJPxB+XAALAQAAAA==.Shamhawk:BAAALgADCgMJBgAAAA==.Shaolinsnake:BAAALgAECgQJBQAAAA==.Shiiva:BAAALgADCgMJAwAAAA==.Shizukahime:BAAALgAECgMJAwAAAA==.',
Si='Sicken:BAAALgADCgIJAgAAAA==.Sigiloc:BAAALgADCgcJBwAAAA==.Silverchair:BAAALgADCgQJBAAAAA==.Singe:BAABLgAECn8iAAILAAgJqxBeaQADAgALAAgJqxBeaQADAgAAAA==.Sinzala:BAABLgAECn8UAAILAAgJ9RtTcADzAQALAAgJ9RtTcADzAQAAAA==.',
Sk='Skeetsurfin:BAAALgADCgYJBgAAAA==.Skelly:BAAALgADCgYJCwAAAA==.Skyman:BAAALgADCgkJEwAAAA==.',
Sm='Smaugdor:BAAALgADCgcJBgAAAA==.',
Sn='Snorp:BAAALgAECgQJBAAAAA==.',
So='Solai:BAAALgAECgEJAQAAAA==.Solsti:BAABLgAECn8aAAIIAAgJzBV3EQDUAQAIAAgJzBV3EQDUAQAAAA==.',
Sp='Spears:BAAALgAECgUJBwAAAA==.Spoondot:BAAALgAECgcJDwAAAA==.Spoonknight:BAAALgAECggJCgAAAA==.',
Sq='Squidge:BAAALgAECgIJAgAAAA==.',
St='Staceyrella:BAAALgADCgMJAwAAAA==.Stainpngolin:BAAALgAECgYJEAAAAA==.Stillhorn:BAAALgAECgcJEwAAAA==.Stinjeras:BAABLgAECn8aAAIXAAgJfR/2CQBtAgAXAAgJfR/2CQBtAgAAAA==.Stinkyjo:BAABLgAECn8aAAIQAAgJpRZwDgAmAgAQAAgJpRZwDgAmAgAAAA==.Stokelys:BAAALgADCgMJAwAAAA==.Stormfeather:BAAALgAECgEJAQAAAA==.Strikerv:BAABLgAECn8cAAISAAgJ6xvmHABYAgASAAgJ6xvmHABYAgAAAA==.',
Su='Sunadoria:BAAALgAECgUJCQAAAA==.Sunrae:BAAALgAECgYJDAAAAA==.Sushi:BAAALgAECgcJEwAAAA==.',
Sv='Sven:BAAALgAECgQJBQAAAA==.',
Sy='Sylinsor:BAAALgADCgEJAQAAAA==.Symor:BAAALgADCgkJMQAAAA==.',
['Sö']='Söap:BAAALgAECgUJBQAAAA==.',
Ta='Tahl:BAABLgAECn8gAAIGAAcJLhG0RwAaAQAGAAcJLhG0RwAaAQAAAA==.Tamanovitch:BAAALgAECgEJAQAAAA==.Tamashii:BAAALgAECgEJAQAAAA==.Taproot:BAAALgADCgEJAQABLgAFFAMJBwALAHUMAA==.Taryen:BAAALgAECgEJAQABLgAECgMJAwATAAAAAA==.Tavie:BAABLgAFFH8IAAILAAMJgBeDLwAMAQALAAMJgBeDLwAMAQAAAA==.',
Te='Teddy:BAAALgADCgYJBgAAAA==.Tedo:BAAALgADCgUJBQABLgAFFAMJBQAIAO4XAA==.Teikkas:BAAALgAECgQJBQAAAA==.Telaari:BAAALgAECgEJAQAAAA==.',
Th='Thalenia:BAABLgAECn8nAAMWAAgJVglODAAJAQASAAYJFAwoYQBEAQAWAAgJYAZODAAJAQAAAA==.Thalron:BAAALgADCgEJAQAAAA==.Thekingdom:BAABLgAECn8YAAILAAgJVh1hRQBnAgALAAgJVh1hRQBnAgAAAA==.Thriller:BAAALgAECgEJAgABLgAFFAMJBQAIAO4XAA==.Thunderfuzz:BAABLgAECn8fAAIQAAgJxh0ZEQAGAgAQAAgJxh0ZEQAGAgAAAA==.',
Ti='Tikeidari:BAABLgAECn8fAAIaAAgJFiPYAACuAgAaAAgJFiPYAACuAgAAAA==.Tiltedtroll:BAABLgAECn8VAAINAAgJUhCDGgA/AQANAAgJUhCDGgA/AQAAAA==.Timedemon:BAABLgAECn8mAAIJAAkJcxvpBwBbAgAJAAkJcxvpBwBbAgAAAA==.Tinuveuil:BAAALgADCgYJBgAAAA==.',
To='Tonjuras:BAAALgAECgcJDgAAAA==.Toona:BAABLgAECn8bAAIJAAgJvR0EHACqAgAJAAgJvR0EHACqAgAAAA==.Torogrande:BAAALgADCgkJIQAAAA==.Touchmyting:BAAALgAECgEJAQAAAA==.',
Tr='Trappydh:BAAALgAFFAEJAQAAAA==.Trappydk:BAABLgAECn8WAAIZAAgJfRppBQDcAQAZAAgJfRppBQDcAQABLgAFFAEJAQATAAAAAA==.Trintran:BAAALgADCgIJAgAAAA==.',
Tu='Tulshira:BAAALgADCgYJBgAAAA==.',
Tw='Twocents:BAABLgAECn8sAAMXAAgJtCQGBADfAgAXAAgJtCQGBADfAgAjAAEJAADdIQBqAAAAAA==.',
Ty='Tyronne:BAAALgAECgcJBwAAAA==.',
Ul='Ultraball:BAAALgAECggJDQAAAA==.',
Un='Unagi:BAABLgAECn8UAAIiAAYJcAwYEwA4AQAiAAYJcAwYEwA4AQAAAA==.Unkelb:BAAALgADCgYJBgAAAA==.',
Va='Vaenessa:BAAALgAECgYJCwAAAA==.Vaesir:BAAALgADCgcJDQAAAA==.Varleara:BAABLgAECn8gAAMJAAgJyCFHEwDmAgAJAAgJyCFHEwDmAgAaAAEJKQeLLQAqAAAAAA==.',
Ve='Venenn:BAAALgADCgEJAgAAAA==.Venev:BAAALgAECgMJAwAAAA==.Ventana:BAABLgAECn8VAAIPAAYJqBgbCABzAQAPAAYJqBgbCABzAQAAAA==.Verdilac:BAABLgAECn8eAAIHAAgJoRkKTQD7AQAHAAgJoRkKTQD7AQAAAA==.',
Vi='Vinceglortho:BAAALgADCgkJEAAAAA==.Vindicator:BAAALgAECggJDwAAAA==.Violetnoir:BAAALgAECgQJBAABLgAECgcJGgAXAM8IAA==.Visiroth:BAAALgAECgcJEAAAAA==.',
Wa='Wagyumoo:BAAALgAECgEJAQABLgAECggJIgALAKsQAA==.Wallydk:BAAALgAECgcJDQAAAA==.Wanji:BAAALgAECggJEwAAAA==.',
We='Weave:BAAALgADCgYJBgAAAA==.Westhresh:BAAALgADCgcJBwAAAA==.',
Wi='Widginatrix:BAAALgAECggJCQAAAA==.Willkain:BAAALgAECgMJAwAAAA==.',
Wo='Woons:BAAALgAECgIJBQAAAA==.',
Wr='Wraithbane:BAAALgAECgMJAwAAAA==.',
Xa='Xaya:BAABLgAECn8aAAMXAAcJzwh6PwA0AQAXAAcJzwh6PwA0AQAYAAQJ6AJEUQB6AAAAAA==.',
Xi='Xiva:BAAALgAECgYJEAAAAA==.',
Xo='Xovace:BAAALgAECgQJBwAAAA==.',
Xt='Xtayse:BAAALgAECgcJEwAAAA==.',
Ya='Yamyam:BAABLgAECn8UAAIUAAgJ8A/AKQCyAQAUAAgJ8A/AKQCyAQAAAA==.',
Yf='Yfelril:BAAALgADCgQJBAABLgAECgYJEAATAAAAAA==.',
Yo='Yoruechi:BAABLgAECn8pAAIKAAgJJCO/AAC+AgAKAAgJJCO/AAC+AgAAAA==.',
['Yú']='Yúmyúm:BAAALgAECggJEQAAAA==.',
Za='Zahel:BAABLgAECn8gAAIHAAgJwh2oEQAtAgAHAAgJwh2oEQAtAgAAAA==.Zahrogue:BAAALgADCgYJBgABLgAECggJIAAHAMIdAA==.Zalark:BAAALgADCgUJCgABLgAECgYJGQAGAIYQAA==.Zangai:BAAALgADCgUJBQAAAA==.',
Ze='Zeneri:BAABLgAECn8aAAMgAAgJIRFXEACjAQAgAAgJIRFXEACjAQAVAAMJiQZhYQCKAAAAAA==.',
Zo='Zobi:BAAALgADCgkJMQAAAA==.Zomboo:BAAALgAFFAEJAQAAAA==.',
Zu='Zugzugzug:BAAALgADCgMJBgAAAA==.',
['Zò']='Zònan:BAAALgADCgEJAQABLgAECggJHgAOAPgTAA==.',
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

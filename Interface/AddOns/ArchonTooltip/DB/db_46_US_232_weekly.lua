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

local lookup = {'Paladin-Protection','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Priest-Holy','DemonHunter-Devourer','Paladin-Retribution','Druid-Guardian','Unknown-Unknown','Mage-Frost','Shaman-Elemental','Shaman-Restoration','Shaman-Enhancement','Druid-Restoration','DemonHunter-Havoc','DemonHunter-Vengeance','Hunter-BeastMastery','Hunter-Marksmanship','Warlock-Demonology','Warlock-Destruction','DeathKnight-Blood','Priest-Discipline','Monk-Windwalker','Paladin-Holy','Monk-Mistweaver','Priest-Shadow','Monk-Brewmaster','DeathKnight-Unholy','Hunter-Survival','Warlock-Affliction','Druid-Feral','Druid-Balance',}
local provider = {region='US',realm='Uther',name='US',type='weekly',zone=46,date='2026-04-24',data={Ad='Addiction:BAAALgADCgYJAQAAAA==.',
Ah='Ahmet:BAAALgAECgQJBAABLgAECggJJAABAJIdAA==.',
Ai='Aiax:BAABLgAECn8VAAQCAAgJwgosIAAsAQADAAYJ2QuyMQA6AQACAAYJZAosIAAsAQAEAAIJWAI/RgBAAAAAAA==.',
Al='Aliancia:BAAALgAECgYJDwAAAA==.Almur:BAAALgADCggJGgAAAA==.Alyda:BAAALgADCggJFAAAAA==.',
Am='Amet:BAABLgAECn8kAAIBAAgJkh18BQCfAgABAAgJkh18BQCfAgAAAA==.',
An='Annailuj:BAAALgADCgIJAgAAAA==.Annora:BAABLgAECn8ZAAIFAAgJ9xdvFgApAgAFAAgJ9xdvFgApAgAAAA==.Antherina:BAAALgADCgQJBwAAAA==.Antonlavay:BAAALgADCgUJBwAAAA==.',
Ap='Apollyøn:BAAALgAECgYJEgAAAA==.',
Ar='Arlechino:BAABLgAECn8fAAIGAAgJUhUoEACFAQAGAAgJUhUoEACFAQAAAA==.Arywyn:BAAALgAECgQJBgAAAA==.',
As='Assclapiuss:BAABLgAECn8VAAIHAAcJVCUpFQDrAgAHAAcJVCUpFQDrAgAAAA==.Asterchades:BAABLgAECn8XAAIIAAcJNhmYCgDtAQAIAAcJNhmYCgDtAQAAAA==.Astlin:BAAALgAECgEJAQAAAA==.Astraeastar:BAAALgADCgUJBQAAAA==.',
At='Athennah:BAAALgAECgUJBQABLgAECgYJCgAJAAAAAA==.Atrei:BAAALgADCgIJAgAAAA==.Attikus:BAABLgAECn8WAAIKAAYJYwLXDgHfAAAKAAYJYwLXDgHfAAAAAA==.Atuan:BAAALgAECgMJBAAAAA==.',
Au='Auralass:BAAALgAECgQJBgAAAA==.Aurene:BAAALgAECgYJFgAAAQ==.',
Av='Avatard:BAAALgAECgIJAgABLgAECggJIgAKAKsQAA==.',
Ax='Axem:BAAALgAECgYJEgAAAA==.',
Az='Azlanii:BAAALgADCggJCgAAAA==.Azulathan:BAAALgAECgYJDAABLgAECggJGwALAAoNAA==.',
Ba='Bamseyn:BAAALgADCgYJBgAAAA==.Baraxor:BAABLgAECn8bAAMLAAgJCg04RAA4AQALAAcJCQ04RAA4AQAMAAMJQRTxbgDTAAAAAA==.Barrelaged:BAAALgADCgcJBwAAAA==.',
Be='Beerguy:BAAALgADCggJBAAAAA==.Behemothe:BAABLgAECn8XAAINAAcJkBx4CQA/AgANAAcJkBx4CQA/AgAAAA==.Berníesandrs:BAABLgAECn8hAAIKAAgJEw0AGQB/AQAKAAgJEw0AGQB/AQAAAA==.Beryllos:BAAALgADCggJIgAAAA==.Bevela:BAAALgADCgIJAgAAAA==.',
Bi='Biddies:BAAALgAECgEJAQAAAA==.Bigimpin:BAAALgADCgcJBwAAAA==.',
Bj='Bjôrn:BAAALgAECgYJBwAAAA==.',
Bl='Bledana:BAAALgADCgQJBAAAAA==.Bleué:BAAALgADCgEJAQABLgAECgYJFAAOAGQUAA==.Bloodmourne:BAAALgAECgcJEQAAAA==.Bloodytoutii:BAAALgAECgIJAQAAAA==.',
Bo='Borthyr:BAABLgAECn8VAAMCAAYJ2hykDgDwAQACAAYJ0RykDgDwAQADAAUJPRbYCwAqAQAAAA==.Bowowner:BAAALgAECgcJDwAAAA==.',
Br='Branchmanagr:BAAALgAECgYJEAAAAA==.Brewlee:BAAALgAECgkJCwAAAA==.Brokenkrayon:BAAALgAECgIJAwAAAA==.Brokkr:BAAALgADCgQJBwAAAA==.Bryce:BAAALgAECgEJAQAAAA==.',
Bu='Busta:BAABLgAECn8dAAIKAAgJmgWzMQACAQAKAAgJmgWzMQACAQAAAA==.',
Bw='Bwicked:BAAALgAECgUJBgAAAA==.',
['Bé']='Béck:BAAALgADCgEJAQAAAA==.',
['Bü']='Büg:BAAALgAECgUJDAAAAA==.',
Ca='Caedars:BAAALgADCgEJAQAAAA==.Calzone:BAAALgAECgIJAQAAAA==.Cantpurge:BAAALgADCgIJAgABLgAECgYJCgAJAAAAAA==.',
Ch='Chamelean:BAAALgAECgYJDQABLgAECgcJEQAJAAAAAA==.Chimpnzthat:BAAALgAECgQJCQAAAA==.Chookicookie:BAABLgAECn8jAAIMAAcJ5x84FgBkAgAMAAcJ5x84FgBkAgAAAA==.Chuckarita:BAAALgAECgYJDAAAAA==.',
Ci='Cindyy:BAAALgAECgYJEgAAAA==.Civaelia:BAAALgADCgMJAwAAAA==.',
Cl='Clutterbear:BAAALgADCgIJAgAAAA==.',
Co='Consume:BAABLgAECn8UAAMPAAYJCCQKFQAnAgAPAAYJCCQKFQAnAgAQAAMJex63FQD8AAAAAA==.Cornpuff:BAAALgAECgQJBAAAAA==.Cortiz:BAABLgAECn8XAAIRAAcJsAwaRQCcAQARAAcJsAwaRQCcAQAAAA==.',
Cr='Crankdog:BAABLgAECn8WAAMRAAgJuB8tAgCMAgARAAgJuB8tAgCMAgASAAYJ8g9DSgApAQAAAA==.Creedd:BAABLgAECn8YAAIOAAcJWCBLBQAqAgAOAAcJWCBLBQAqAgAAAA==.Crialta:BAAALgADCgcJDwAAAA==.',
Cu='Cupsandcakes:BAAALgAECgUJBgAAAA==.',
Cy='Cynaidia:BAAALgAECgQJBwAAAA==.',
Da='Dacarry:BAAALgAECgIJAgAAAA==.Damessiah:BAAALgAECgYJEwAAAA==.Dark:BAABLgAECn8WAAITAAcJziBFIACXAgATAAcJziBFIACXAgAAAA==.Darkphyre:BAAALgAECgQJBgAAAA==.Darthtree:BAAALgADCgEJAQAAAA==.Dawling:BAAALgADCgYJBgAAAA==.',
De='Deadmandan:BAABLgAECn8hAAMTAAgJeiWHAQCwAgATAAgJeiWHAQCwAgAUAAYJISSuBwBMAgAAAA==.Deathomen:BAAALgADCgcJBwAAAA==.Deathtike:BAABLgAECn8WAAIVAAcJCB5NAwDAAQAVAAcJCB5NAwDAAQABLgAECgcJFwAQADohAA==.Decius:BAAALgAECgQJBQAAAA==.Demagorgin:BAABLgAECn8dAAIHAAgJMhQbEgCSAQAHAAgJMhQbEgCSAQAAAA==.Demcheekz:BAAALgAECgIJAgAAAA==.Demiurge:BAAALgAECgUJBQAAAA==.Demondred:BAAALgAECgQJBQAAAA==.Demonhugger:BAAALgAECgEJAQABLgAECgYJFAAKAG4SAA==.Demonplug:BAAALgADCgEJAQAAAA==.Demonrae:BAAALgAECgIJAgAAAA==.Deqlyn:BAABLgAECn8WAAIHAAYJ5RyRFwBkAQAHAAYJ5RyRFwBkAQAAAA==.Desmus:BAAALgAECgQJCQAAAA==.Deterno:BAAALgADCgUJBQAAAA==.Devige:BAAALgADCgMJBAABLgAECggJIgATADYjAA==.Deáthreaver:BAAALgAECgUJBgAAAA==.',
Di='Diglett:BAAALgADCgYJAQAAAA==.Dimsum:BAAALgAECgUJBgAAAA==.Diqtator:BAAALgADCgcJBwAAAA==.Dismal:BAAALgAECgYJDAAAAA==.',
Dk='Dk:BAAALgADCgIJAgAAAA==.',
Do='Domwarlock:BAAALgAECgYJCAAAAA==.Doomdooms:BAAALgADCgEJAQAAAA==.Dots:BAAALgADCggJDgAAAA==.',
Dr='Dradin:BAAALgADCgMJAwAAAA==.Dronin:BAAALgAECgYJDwAAAA==.Drpatan:BAAALgAECgYJDQAAAA==.Druni:BAAALgAECgQJBgAAAA==.Dryan:BAAALgADCgEJAQAAAA==.',
Ec='Echowalker:BAAALgAECgMJBQAAAA==.',
Ee='Eecho:BAAALgADCgEJAQAAAA==.',
El='Eldruida:BAAALgADCgYJDAAAAA==.Elguezo:BAAALgAECgUJBQAAAA==.Elysyn:BAAALgADCgMJAwAAAA==.',
Em='Emaelia:BAAALgAECgQJBAAAAA==.Emokillaz:BAABLgAECn8WAAIPAAcJ1xghBQB4AQAPAAcJ1xghBQB4AQAAAA==.',
Ep='Epictaxes:BAAALgADCgEJAQAAAA==.Epimetheuz:BAAALgADCgYJAwAAAA==.Epsilón:BAAALgAECgYJCgAAAA==.',
Et='Eternalpeace:BAAALgADCgEJAQAAAA==.',
Ex='Exaduss:BAAALgAECgcJDgAAAA==.',
Fa='Fastrolling:BAAALgADCgQJCgAAAA==.Faxon:BAAALgAECgcJDgAAAA==.Faylan:BAAALgAECgQJBgAAAA==.',
Fe='Feronnia:BAAALgADCgYJDgAAAA==.',
Fi='Fibot:BAABLgAECn8XAAINAAcJeRZLDQDqAQANAAcJeRZLDQDqAQAAAA==.Fingon:BAAALgAECgYJEAAAAA==.',
Fl='Flogor:BAAALgAECgcJBgABLgAECgkJCQAJAAAAAA==.Florasol:BAAALgADCgIJAgAAAA==.',
Fo='Foxling:BAEALgAECgEJAQAAAA==.',
Fr='Fraeyah:BAAALgADCgYJCwAAAA==.Frahaad:BAAALgADCgQJBAAAAA==.Freebunz:BAABLgAECn8UAAIKAAgJhRdzVAA7AgAKAAgJhRdzVAA7AgAAAA==.',
Ga='Gahydra:BAAALgADCgkJEwAAAA==.Galvanize:BAABLgAECn8kAAIKAAgJyxs0EwCoAQAKAAgJyxs0EwCoAQAAAA==.Gastrophos:BAAALgAECgEJAQAAAA==.',
Gh='Ghomertin:BAAALgADCggJCgAAAA==.',
Gi='Gimtar:BAAALgAECgEJBAAAAA==.Gipsydanger:BAABLgAECn8pAAIWAAgJZRzVAwDzAQAWAAgJZRzVAwDzAQAAAA==.Givr:BAAALgADCgEJAQAAAA==.',
Gl='Glaurang:BAAALgADCgYJCQAAAA==.Glofor:BAAALgADCgEJAQABLgAECgkJCQAJAAAAAA==.',
Gn='Gnarp:BAAALgADCgEJAQABLgAECgcJEwAJAAAAAA==.Gnomeregrets:BAAALgADCgkJCAABLgAECgQJBgAJAAAAAA==.',
Go='Goldencorpse:BAAALgADCgkJFgAAAA==.Goldenspoon:BAAALgADCgEJAQAAAA==.Gorlokk:BAEALgADCgMJAwABLgADCgcJFAAJAAAAAA==.',
Gr='Grakonys:BAAALgAECgcJEAAAAA==.Granger:BAAALgADCgQJBAABLgAECgEJAQAJAAAAAA==.Greed:BAABLgAECn8XAAIXAAcJoRROIgDDAQAXAAcJoRROIgDDAQAAAA==.Greensun:BAAALgADCgEJAQAAAA==.Grendol:BAAALgAECgMJAwAAAA==.Grimmbot:BAAALgADCgkJEAAAAA==.Grimmvelt:BAAALgADCgYJCgAAAA==.Grunnck:BAAALgADCgYJDQAAAA==.',
Gu='Guayusa:BAAALgAECggJDgAAAA==.Gunned:BAAALgADCgEJAQAAAA==.Gunowner:BAABLgAECn8aAAIRAAgJxiWyAADuAgARAAgJxiWyAADuAgAAAA==.',
Gw='Gwendolin:BAAALgAECgUJBQAAAA==.Gwenfrewi:BAAALgADCgEJAQABLgADCgEJAQAJAAAAAA==.',
Ha='Hacheron:BAAALgADCgIJAgABLgAFFAIJAwAJAAAAAA==.Hallows:BAAALgADCgIJAgAAAA==.Harnix:BAAALgAECgQJBAAAAA==.Hawtbooty:BAAALgAECgYJEAAAAA==.',
He='Heartsbane:BAAALgADCgYJDAAAAA==.Helixrage:BAAALgAECgYJDwAAAA==.Hellreines:BAAALgAECgYJCwAAAA==.Herpderplol:BAAALgAECgYJEAAAAA==.',
Hi='Hildi:BAAALgAECgQJCQAAAA==.Him:BAAALgAECgcJDwAAAA==.',
Ho='Holy:BAABLgAECn8aAAIWAAcJOBttAgA8AgAWAAcJOBttAgA8AgAAAA==.Hoots:BAAALgAECgEJAQAAAA==.',
Hu='Hucklebury:BAAALgADCgYJDQAAAA==.Hulkcrush:BAAALgADCgQJCgAAAA==.Humânity:BAAALgADCgYJBgAAAA==.',
Il='Illbloodarch:BAAALgAECgYJEAAAAA==.Illvicious:BAAALgAECgEJAQAAAA==.',
In='Incredibread:BAAALgAECgIJAQAAAA==.Indub:BAAALgAECgMJAwAAAA==.',
Is='Ishura:BAAALgAECgQJCQAAAA==.',
Iv='Ivvy:BAAALgAECgQJBgAAAA==.',
Iz='Izanami:BAAALgAECgQJBwAAAA==.',
Ja='Jaewreth:BAAALgAECgIJAgAAAA==.Janntro:BAAALgAECgcJDQAAAA==.Jantra:BAAALgADCgkJBwAAAA==.Jantro:BAAALgAECgcJDgAAAA==.Janttro:BAAALgADCgcJBwAAAA==.Jaquavious:BAAALgADCgcJBwAAAA==.',
Je='Jeebz:BAABLgAECn8WAAMMAAcJ/BJ6QwBzAQAMAAYJMBV6QwBzAQALAAMJxQqDbACRAAAAAA==.Jelmarr:BAAALgAECgYJBgAAAA==.Jemmâ:BAAALgAECgUJCQAAAA==.Jerauld:BAAALgAECgQJCQAAAA==.Jezrra:BAAALgAECgYJBgAAAA==.',
Jh='Jhuloot:BAAALgADCgYJCQAAAA==.',
Ji='Jiddles:BAAALgADCgMJAwABLgAECgcJDAAJAAAAAA==.',
Jo='Johnnyzyns:BAAALgAECgcJEQAAAA==.Jokhasta:BAABLgAECn8ZAAINAAgJqhZIAgDXAQANAAgJqhZIAgDXAQAAAA==.Joshc:BAAALgAECgcJEQAAAA==.',
Jp='Jpmeister:BAAALgADCgkJDQAAAA==.',
['Já']='Ják:BAABLgAECn8YAAMBAAgJ+hIIGwA2AQABAAcJJBEIGwA2AQAYAAIJ7Ql/iQBWAAAAAA==.',
Ka='Kaaris:BAAALgAECgUJCAAAAA==.Kaiarie:BAAALgAECgMJBgAAAA==.Kainraziel:BAAALgAECgcJEQAAAA==.Kairos:BAABLgAECn8WAAIKAAcJ8gtzrQCBAQAKAAcJ8gtzrQCBAQAAAA==.Kalasta:BAAALgADCgIJAgAAAA==.Kanzak:BAAALgADCgcJCgAAAA==.Karem:BAAALgAECgEJAQAAAA==.Karkea:BAAALgAECgEJAQAAAA==.Kayper:BAAALgAECgcJAgAAAA==.',
Ke='Kebin:BAAALgAECgcJEQAAAA==.Kelfhammer:BAAALgADCgQJBAAAAA==.',
Kh='Khlorox:BAAALgADCgYJBgAAAA==.Khronin:BAAALgADCgIJAgAAAA==.',
Ki='Killmonger:BAAALgAECgYJCwAAAA==.',
Kl='Klöwÿ:BAAALgAECgEJAQAAAA==.',
Ko='Korax:BAAALgADCgUJBQAAAA==.Korgia:BAAALgAECgQJBAAAAA==.Kortharion:BAAALgAECgcJEQAAAA==.Kos:BAAALgAECgYJEgAAAA==.',
Kr='Krixis:BAAALgADCgEJAgAAAA==.',
Ku='Kujiera:BAAALgAECgYJEAAAAA==.Kuntar:BAAALgAECgcJCgAAAA==.Kurgan:BAAALgADCggJCAAAAA==.Kurkoh:BAAALgAECgEJAQAAAA==.Kurrent:BAAALgAECgcJDAAAAA==.',
['Kÿ']='Kÿtten:BAAALgAECgYJEgAAAA==.',
La='Lad:BAAALgAECgUJCQABLgAECggJIgAGAL0dAA==.Laiyth:BAAALgAECgcJDQAAAA==.Larryfish:BAAALgAECgcJDgAAAA==.Laslock:BAAALgADCgEJAQAAAA==.Lavahitman:BAAALgAECgEJAQAAAA==.Lavos:BAABLgAECn8WAAIUAAYJyQ4RBAAeAQAUAAYJyQ4RBAAeAQAAAA==.',
Li='Lighteyes:BAAALgADCgEJAQAAAA==.Lildragon:BAAALgAECgYJBgAAAA==.Lisster:BAAALgAECgcJEQAAAA==.Littledoty:BAAALgAECgEJAQAAAA==.Liyra:BAABLgAECn8cAAMYAAkJIhq2IAAWAgAYAAkJIhq2IAAWAgABAAEJBBUNQQA5AAAAAA==.Lizcandor:BAAALgAECgMJBwAAAA==.',
Lo='Loafe:BAABLgAECn8jAAIHAAgJlA31GABbAQAHAAgJlA31GABbAQAAAA==.Lokni:BAAALgAECgUJCwAAAA==.Loumin:BAAALgADCgkJCQAAAA==.',
Lu='Ludacritz:BAAALgADCgcJFAAAAA==.Lunaignis:BAAALgADCgYJBgAAAA==.Lunasera:BAAALgADCgEJAQAAAA==.Luthais:BAAALgAECgQJBgAAAA==.Luxury:BAAALgAECgYJDAAAAA==.',
Ma='Mahroq:BAABLgAECn8UAAMFAAcJ4Rc2HgDtAQAFAAcJ4Rc2HgDtAQAWAAEJkQIKXgAmAAAAAA==.Mako:BAABLgAECn8aAAIEAAgJ7SBbAAAJAwAEAAgJ7SBbAAAJAwAAAA==.Malarkeclark:BAAALgADCgkJCQAAAA==.Malevian:BAABLgAECn8iAAMCAAgJcwppAgBrAQACAAgJrwhpAgBrAQADAAcJmwizNQAjAQAAAA==.Malfuridan:BAAALgADCgYJCAAAAA==.Malocki:BAAALgADCgQJCgAAAA==.Maples:BAABLgAECn8fAAIZAAkJfQjOBwCDAQAZAAkJfQjOBwCDAQAAAA==.Mariasha:BAAALgADCgYJDwAAAA==.Mazzikin:BAAALgAECggJDwAAAA==.',
Mc='Mcdodgy:BAAALgADCgEJAQAAAA==.',
Me='Megaterium:BAABLgAECn8WAAMFAAYJ0hUUMQB8AQAFAAYJ0hUUMQB8AQAaAAMJ3wS5UwB2AAAAAA==.Menethil:BAAALgAECgUJDAAAAA==.Metheuz:BAAALgADCgIJAgABLgADCgYJAwAJAAAAAA==.Mexican:BAAALgAECgcJEQAAAA==.',
Mi='Midnightlock:BAAALgAECgYJDQAAAA==.Midnyght:BAAALgADCgkJJQAAAA==.Mishgrail:BAABLgAECn8WAAIbAAYJ4Rw9CAB0AQAbAAYJ4Rw9CAB0AQAAAA==.Missmisery:BAAALgAECgYJCQAAAA==.Mithdraug:BAAALgAECgQJBgAAAA==.Mitzi:BAACLgAFFH8OAAMcAAUJZRfUEABeAQAcAAQJZRfUEABeAQAVAAEJAABDGwAvAAAuAAQKfyEAAhwACQnvIZ0DAGUCABwACQnvIZ0DAGUCAAAA.',
Mo='Monache:BAAALgAECgYJDgAAAA==.Mongalf:BAAALgADCgQJBAAAAA==.Montrois:BAAALgADCgcJCwAAAA==.Moopally:BAAALgAECgQJBAAAAA==.',
['Mô']='Môônmôôn:BAAALgADCgYJBgAAAA==.',
Ne='Neletheus:BAAALgAECgYJDwAAAA==.Nephbrew:BAAALgADCgEJAQAAAA==.Nephren:BAAALgADCgYJBgAAAA==.Nephwren:BAAALgADCgUJBQAAAA==.',
Ni='Nightparade:BAAALgAECgQJBwAAAA==.Nirvanik:BAAALgADCgcJAgAAAA==.Nishgrail:BAAALgADCgYJBAABLgAECgYJFgAbAOEcAA==.',
Nu='Nukusmaximus:BAAALgAECgQJBQAAAA==.',
Ny='Nyeneave:BAAALgADCggJCAAAAA==.Nyiah:BAAALgAECgcJDgAAAA==.',
['Nä']='Närgazeth:BAAALgADCgMJAwAAAA==.',
Og='Ogdoadtl:BAAALgADCgkJIwAAAA==.',
Oh='Ohello:BAAALgADCgUJBQAAAA==.',
Ol='Oldbull:BAAALgADCgEJAQAAAA==.',
On='Onex:BAAALgAECgMJBAAAAA==.',
Or='Organicmeat:BAAALgAECggJCQAAAA==.Orgrím:BAAALgADCgMJAwAAAA==.',
Pa='Partywizard:BAAALgAECgMJAwAAAA==.',
Pe='Persefini:BAAALgAECgEJAQAAAA==.Persephoneia:BAAALgADCgYJBgAAAA==.Petrokull:BAAALgADCgkJJQAAAA==.',
Ph='Pheeguh:BAAALgADCgkJEAAAAA==.Pheylan:BAAALgAECgEJAwAAAA==.Philidox:BAAALgAECgYJBgABLgAECggJGAABAPoSAA==.Phood:BAAALgADCgcJBwAAAA==.',
Pi='Pikxs:BAAALgAECgIJAgAAAA==.Pitchou:BAAALgAECgEJAQAAAA==.',
Pl='Plugugly:BAAALgAECgIJAgAAAA==.',
Po='Poenin:BAAALgADCgYJBgAAAA==.Pokeball:BAAALgAECgYJDAAAAA==.Polinemarois:BAAALgADCggJBwAAAA==.Porkque:BAABLgAECn8WAAIRAAYJ9gw7HAAdAQARAAYJ9gw7HAAdAQAAAA==.Potatobear:BAABLgAECn8bAAQSAAYJXyOHGQBbAgASAAYJXyOHGQBbAgAdAAYJnBevBACYAQARAAEJWR8/vABLAAAAAA==.',
Pr='Prifduwies:BAAALgADCgcJAQAAAA==.Professorson:BAAALgADCgQJBAAAAA==.',
Qu='Quicktime:BAABLgAECn8aAAIGAAgJSxdmEACDAQAGAAgJSxdmEACDAQAAAA==.',
Ra='Ragedh:BAAALgADCgcJBwABLgAECgEJAQAJAAAAAA==.Ragnarlothbr:BAAALgADCgQJBAAAAA==.Ranillan:BAAALgAECgYJBgAAAA==.Rased:BAAALgADCgEJAQAAAA==.Rashish:BAAALgADCgIJAgAAAA==.Ravies:BAAALgAECgEJAQAAAA==.Rawdøg:BAAALgADCgEJAQAAAA==.',
Re='Reeses:BAEALgADCgcJFAAAAA==.Reinharts:BAAALgAECgUJCwAAAA==.Religgar:BAAALgAECgYJEwAAAA==.Reploidzero:BAAALgADCgkJCwAAAA==.Rethart:BAAALgADCgcJBwAAAA==.',
Rh='Rhilik:BAAALgADCgQJBAAAAA==.',
Ri='Ricter:BAAALgAECgYJCwAAAA==.Rictor:BAAALgAECgIJAwAAAA==.',
Ro='Roglof:BAAALgAECgkJCQAAAA==.Rokkoks:BAAALgADCgYJDgAAAA==.Rowlah:BAAALgADCggJCgAAAA==.Roxyfoxy:BAAALgADCgEJAQAAAA==.Rozy:BAABLgAECn8fAAIYAAgJAhtwEgB/AgAYAAgJAhtwEgB/AgAAAA==.',
Ru='Ruffs:BAAALgAECgYJEQAAAA==.Ruiizu:BAAALgAECgcJEQAAAA==.Rulnathil:BAAALgADCgMJBgAAAA==.Rushuna:BAABLgAECn8UAAIWAAcJnxsEEAA/AgAWAAcJnxsEEAA/AgAAAA==.',
Sa='Saberjaw:BAAALgAECgYJEQAAAA==.Sairicck:BAAALgAECgcJDQAAAA==.Samaal:BAAALgADCgUJBQAAAA==.Samial:BAAALgADCgYJDAAAAA==.Sanguinor:BAAALgADCgYJFAAAAA==.Santamorte:BAAALgADCgYJBwAAAA==.Sashay:BAAALgADCgYJCwAAAA==.Satoru:BAAALgAECgEJAgAAAA==.Satsuki:BAAALgADCgEJAQAAAA==.',
Sc='Scuba:BAAALgAECgUJCAAAAA==.',
Se='Selesé:BAAALgAECgEJAQABLgAECgUJCQAJAAAAAA==.Selinora:BAAALgAECggJDQAAAA==.Serhalatath:BAAALgAECgIJAwAAAA==.',
Sh='Shadowsbane:BAAALgADCgEJAQAAAA==.Shaguar:BAAALgAECgcJEQAAAA==.Shamhawk:BAAALgADCgMJBgAAAA==.Shaolinsnake:BAAALgAECgEJAQAAAA==.Shiiva:BAAALgADCgMJAwAAAA==.Shizukahime:BAAALgAECgMJAwAAAA==.',
Si='Sicken:BAAALgADCgIJAgAAAA==.Sigiloc:BAAALgADCgcJBwAAAA==.Silverchair:BAAALgADCgQJBAAAAA==.Singe:BAABLgAECn8iAAIKAAgJqxBHGQB+AQAKAAgJqxBHGQB+AQAAAA==.Sinzala:BAAALgAECggJEgAAAA==.',
Sk='Skeetsurfin:BAAALgADCgYJBgAAAA==.Skelly:BAAALgADCgYJCwAAAA==.Skyman:BAAALgADCgkJEwAAAA==.',
Sm='Smaugdor:BAAALgADCgcJBgAAAA==.',
Sn='Snorp:BAAALgAECgQJBAAAAA==.',
So='Solai:BAAALgAECgEJAQAAAA==.Solsti:BAABLgAECn8WAAIYAAYJFhfTDQBjAQAYAAYJFhfTDQBjAQAAAA==.',
Sp='Spears:BAAALgAECgIJAgAAAA==.Spoondot:BAAALgAECgcJCgAAAA==.Spoonknight:BAAALgAECggJCAAAAA==.',
Sq='Squidge:BAAALgAECgIJAgAAAA==.',
St='Stainpngolin:BAAALgAECgQJCQAAAA==.Stillhorn:BAAALgAECgcJDgAAAA==.Stinjeras:BAAALgAECgcJEQAAAA==.Stinkyjo:BAAALgAECgcJEQAAAA==.Stokelys:BAAALgADCgMJAwAAAA==.Stormfeather:BAAALgAECgEJAQAAAA==.Strikerv:BAABLgAECn8ZAAIRAAgJkhvpHABYAgARAAgJkhvpHABYAgAAAA==.',
Su='Sunadoria:BAAALgAECgUJBQAAAA==.Sunrae:BAAALgAECgQJBgAAAA==.Sushi:BAAALgAECgcJDgAAAA==.',
Sv='Sven:BAAALgAECgQJBQAAAA==.',
Sy='Sylinsor:BAAALgADCgEJAQAAAA==.Symor:BAAALgADCgkJJQAAAA==.',
['Sö']='Söap:BAAALgAECgUJBQAAAA==.',
Ta='Tahl:BAABLgAECn8gAAIFAAcJLhFeBwCUAQAFAAcJLhFeBwCUAQAAAA==.Tamanovitch:BAAALgADCgIJAwAAAA==.Tamashii:BAAALgAECgEJAQAAAA==.Taproot:BAAALgADCgEJAQABLgAECggJJAAKAMsbAA==.Taryen:BAAALgAECgEJAQAAAA==.Tavie:BAABLgAFFH8FAAIKAAIJ7g0oHwCLAAAKAAIJ7g0oHwCLAAAAAA==.',
Te='Teddy:BAAALgADCgYJBgAAAA==.Teikkas:BAAALgAECgEJAQAAAA==.Telaari:BAAALgAECgEJAQAAAA==.',
Th='Thalenia:BAABLgAECn8iAAMSAAgJVglRBgAUAQARAAYJFAwwYQBEAQASAAgJYAZRBgAUAQAAAA==.Thalron:BAAALgADCgEJAQAAAA==.Thekingdom:BAABLgAECn8XAAIKAAgJVh1fRQBnAgAKAAgJVh1fRQBnAgAAAA==.Thriller:BAAALgAECgEJAQABLgAECggJHgAYADUbAA==.Thunderfuzz:BAABLgAECn8XAAIOAAcJJB9+HgBLAgAOAAcJJB9+HgBLAgAAAA==.',
Ti='Tikeidari:BAABLgAECn8XAAIQAAcJOiGVAwCWAgAQAAcJOiGVAwCWAgAAAA==.Tiltedtroll:BAAALgAECgcJDQAAAA==.Timedemon:BAABLgAECn8kAAIGAAgJCxzjCwC4AQAGAAgJCxzjCwC4AQAAAA==.Tinuveuil:BAAALgADCgYJBgAAAA==.',
To='Tonjuras:BAAALgAECgcJDgAAAA==.Toona:BAABLgAECn8iAAIGAAgJvR0BHACqAgAGAAgJvR0BHACqAgAAAA==.Torogrande:BAAALgADCgkJIQAAAA==.',
Tr='Trappydh:BAAALgAECgcJEQABLgAFFAIJAwAJAAAAAA==.Trappydk:BAAALgAFFAIJAwAAAA==.Trintran:BAAALgADCgIJAgAAAA==.',
Tu='Tulshira:BAAALgADCgYJBgAAAA==.',
Tw='Twocents:BAABLgAECn8nAAMTAAgJJSSjAQCrAgATAAgJJSSjAQCrAgAeAAEJAADcIQBqAAAAAA==.',
Ty='Tyronne:BAAALgAECgcJBwAAAA==.',
Ul='Ultraball:BAAALgAECgUJBQAAAA==.',
Un='Unagi:BAAALgAECgQJDAAAAA==.Unkelb:BAAALgADCgYJBgAAAA==.',
Va='Vaenessa:BAAALgAECgMJBwAAAA==.Vaesir:BAAALgADCgYJBgAAAA==.Varleara:BAABLgAECn8jAAMGAAgJyCE7EwDmAgAGAAgJyCE7EwDmAgAQAAEJKQeJLQAqAAAAAA==.',
Ve='Venenn:BAAALgADCgEJAgAAAA==.Venev:BAAALgADCgIJBAAAAA==.Ventana:BAAALgAECgYJDwAAAA==.Verdilac:BAABLgAECn8YAAIHAAcJKhgRTQD7AQAHAAcJKhgRTQD7AQABLgAECggJHgAfAHQdAA==.',
Vi='Vinceglortho:BAAALgADCgQJBAAAAA==.Vindicator:BAAALgAECgYJBgAAAA==.Violetnoir:BAAALgAECgQJBAABLgAECgcJFQATADYGAA==.Visiroth:BAAALgAECgcJCwAAAA==.',
Wa='Wagyumoo:BAAALgAECgEJAQABLgAECggJIgAKAKsQAA==.Wallydk:BAAALgAECgcJDQAAAA==.Wanji:BAAALgAECgYJCwAAAA==.',
We='Weave:BAAALgADCgYJBgAAAA==.Westhresh:BAAALgADCgcJBwAAAA==.',
Wi='Willkain:BAAALgAECgMJAwAAAA==.',
Wo='Woons:BAAALgAECgIJBAAAAA==.',
Wr='Wraithbane:BAAALgAECgMJAwAAAA==.',
Xa='Xaya:BAABLgAECn8VAAMTAAcJNgaVIAAdAQATAAcJNgaVIAAdAQAUAAQJ6AI+UQB6AAAAAA==.',
Xi='Xiva:BAAALgAECgQJCQAAAA==.',
Xo='Xovace:BAAALgAECgMJAwAAAA==.',
Xt='Xtayse:BAAALgAECgcJDgAAAA==.',
Ya='Yamyam:BAABLgAECn8UAAIgAAgJ8A/CKQCyAQAgAAgJ8A/CKQCyAQAAAA==.',
Yf='Yfelril:BAAALgADCgQJBAABLgAECgYJCgAJAAAAAA==.',
Yo='Yoruechi:BAABLgAECn8kAAIIAAgJKiJ2AACiAgAIAAgJKiJ2AACiAgAAAA==.',
['Yú']='Yúmyúm:BAAALgAECgcJCQAAAA==.',
Za='Zahel:BAABLgAECn8bAAIHAAYJxx/oEACdAQAHAAYJxx/oEACdAQAAAA==.Zahrogue:BAAALgADCgYJBgABLgAECgYJGwAHAMcfAA==.Zalark:BAAALgADCgUJCgABLgAECgYJEwAJAAAAAA==.Zangai:BAAALgADCgUJBQAAAA==.',
Ze='Zeneri:BAABLgAECn8WAAMZAAYJ/Q+4CgA/AQAZAAYJ/Q+4CgA/AQAXAAMJiQZhYQCKAAAAAA==.',
Zo='Zobi:BAAALgADCgkJJQAAAA==.Zomboo:BAAALgAECggJDAAAAA==.',
Zu='Zugzugzug:BAAALgADCgMJBgAAAA==.',
['Zò']='Zònan:BAAALgADCgEJAQABLgAECgcJFgAMAPwSAA==.',
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

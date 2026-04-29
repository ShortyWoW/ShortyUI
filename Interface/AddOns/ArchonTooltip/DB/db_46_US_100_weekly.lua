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

local lookup = {'Warlock-Demonology','Hunter-BeastMastery','Paladin-Retribution','Paladin-Protection','Unknown-Unknown','Hunter-Survival','Paladin-Holy','Druid-Guardian','Mage-Frost','DeathKnight-Unholy','DeathKnight-Blood','Evoker-Augmentation','Hunter-Marksmanship','Evoker-Preservation','Warlock-Destruction','Warrior-Fury','Priest-Shadow','Rogue-Subtlety','Priest-Holy','Warlock-Affliction','Evoker-Devastation','Shaman-Enhancement','Warrior-Protection','Druid-Balance','Monk-Windwalker','DemonHunter-Devourer','DeathKnight-Frost','Shaman-Restoration','Shaman-Elemental','Druid-Restoration','Monk-Brewmaster','Mage-Fire','Priest-Discipline','Druid-Feral','Rogue-Assassination','DemonHunter-Vengeance','Warrior-Arms',}
local provider = {region='US',realm='Frostwolf',name='US',type='weekly',zone=46,date='2026-04-24',data={Aa='Aamodar:BAAALgAECgQJBAAAAA==.Aaz:BAAALgAECgEJAQAAAA==.',
Ab='Abadon:BAABLgAECn8hAAIBAAgJKxdWCADsAQABAAgJKxdWCADsAQAAAA==.',
Ac='Acidangel:BAAALgADCgcJBwAAAA==.',
Ad='Adalea:BAAALgAECgMJAwAAAA==.Adino:BAABLgAECn8XAAICAAYJsQwrGwAkAQACAAYJsQwrGwAkAQAAAA==.',
Ae='Aeldius:BAAALgAECgEJAQAAAA==.Aeryn:BAABLgAECn8hAAIDAAgJ5yLsDgAXAwADAAgJ5yLsDgAXAwAAAA==.',
Ag='Aggranak:BAAALgAECgYJCQAAAA==.',
Ah='Ahote:BAAALgAECgcJCwAAAA==.Ahtee:BAABLgAECn8WAAMDAAYJWx7EEACeAQADAAYJWx7EEACeAQAEAAMJpwiwNgBoAAAAAA==.',
Ak='Akroz:BAAALgAECgUJBgAAAA==.',
Al='Alande:BAAALgADCgMJAwAAAA==.Aldamithas:BAAALgADCgEJAQAAAA==.Alenon:BAAALgADCgMJAwABLgAECggJDwAFAAAAAA==.Algodon:BAAALgAECgMJAwABLgAFFAMJCAACAFMUAA==.Allenduin:BAAALgADCgEJAQAAAA==.Alonias:BAAALgAECgMJBQAAAA==.Alseena:BAABLgAECn8UAAIDAAUJ/RhFJwAIAQADAAUJ/RhFJwAIAQAAAA==.Alysiita:BAAALgADCgYJBgAAAA==.',
Am='Amadeux:BAABLgAECn8aAAIGAAcJIyCBBwB6AgAGAAcJIyCBBwB6AgAAAA==.Amicae:BAAALgADCgcJCAAAAA==.',
An='Anceirbe:BAAALgAECgEJAQAAAA==.Andenarras:BAAALgAECgEJAQABLgAECggJEQAFAAAAAA==.Anform:BAAALgAECgIJAgAAAA==.Anthais:BAAALgAECgEJAQAAAA==.Anvar:BAAALgAECggJDwAAAA==.',
Ap='Apocalypto:BAAALgADCgMJAwAAAA==.',
Aq='Aquiline:BAAALgADCgMJAwAAAA==.',
Ar='Arastaya:BAAALgADCgcJCgAAAA==.Arathion:BAABLgAECn8fAAIHAAYJBx9zBwDUAQAHAAYJBx9zBwDUAQAAAA==.Archistrate:BAAALgADCgkJEAAAAA==.Artamir:BAAALgADCgMJAwAAAA==.Arx:BAAALgAECgYJCQAAAA==.',
At='Atrumdeus:BAABLgAECn8hAAIDAAcJHBhJFAB/AQADAAcJHBhJFAB/AQAAAA==.',
Au='Audiamer:BAAALgAECgQJBQAAAA==.',
Av='Avindel:BAAALgAECgQJBAAAAA==.',
Aw='Awarmplace:BAAALgADCgYJBgABLgAECgYJDQAFAAAAAA==.Aweyaeh:BAAALgADCgQJBwAAAA==.Awkykit:BAAALgAECgYJCwAAAA==.',
Ay='Ayayron:BAAALgADCgUJBQAAAA==.',
Az='Azymondias:BAAALgADCgEJAgAAAA==.',
Ba='Babushka:BAABLgAECn8VAAIIAAYJVBC5BgDTAAAIAAYJVBC5BgDTAAAAAA==.Babyface:BAAALgAECgUJDQAAAA==.Banddon:BAAALgADCgcJEAAAAA==.Bangerz:BAABLgAECn8UAAIJAAYJyA/UMwD4AAAJAAYJyA/UMwD4AAAAAA==.Bannann:BAAALgADCgIJAgAAAA==.Banned:BAAALgAECgQJBQABLgAECggJIgABAHsmAA==.Bariôn:BAAALgAECgQJBwAAAA==.',
Be='Beakk:BAAALgAECgUJCgABLgAFFAUJEQAKACEiAA==.Beaksbigdk:BAACLgAFFH8RAAMKAAUJISJiDAByAQAKAAQJISJiDAByAQALAAEJAACZEQBmAAAuAAQKfyEAAwoACAk7JpcRABIDAAoACAnEJJcRABIDAAsABQl+JKwPABECAAAA.Bearach:BAAALgADCgUJBQAAAA==.Beariál:BAAALgAECggJEgAAAA==.Beedo:BAAALgADCgEJAgAAAA==.Beef:BAAALgAECgYJBgABLgAFFAQJCgAMALccAA==.Beeftek:BAAALgADCgEJAQAAAA==.Belfegor:BAAALgAECgMJAwAAAA==.Belldia:BAACLgAFFH8IAAICAAUJzQZMBQBOAQACAAUJzQZMBQBOAQAuAAQKfyEAAwIACAkMIJAPAL8CAAIACAkMIJAPAL8CAA0ABQnTDb9RAAUBAAAA.Beni:BAAALgAECgUJCAAAAA==.Beniima:BAAALgAECgYJDQAAAA==.Bennylickz:BAABLgAECn8iAAIOAAgJgRQPAwDKAQAOAAgJgRQPAwDKAQAAAA==.',
Bi='Bibby:BAAALgAECgQJBAAAAA==.Bibi:BAAALgAECgQJBAAAAA==.',
Bl='Blgelk:BAAALgAECgUJBgAAAA==.Blightedmilk:BAAALgADCgUJBQABLgAECggJJAAPAJEdAA==.Blufox:BAAALgAFFAEJAQAAAA==.Blxrry:BAAALgAECgQJBgABLgAFFAIJBQAJANkhAA==.',
Bm='Bmanzero:BAAALgADCgIJAgAAAA==.',
Bo='Bobfresh:BAAALgAECgEJAQABLgAECgQJBwAFAAAAAA==.',
Br='Brainpower:BAAALgADCgkJHAAAAA==.Broherum:BAAALgADCgEJAwAAAA==.Broseidon:BAAALgADCgEJAQAAAA==.Brucella:BAAALgADCgkJFAAAAA==.Bruizin:BAAALgADCgQJBAAAAA==.',
Bu='Buckbeak:BAAALgAECgYJDAAAAA==.Busting:BAAALgAECgYJCwAAAA==.Buttmucker:BAAALgAECgIJAgAAAA==.Buzzliteyear:BAAALgAECgQJBAAAAA==.',
Bw='Bweomysin:BAAALgAFFAEJAQAAAA==.',
['Bå']='Båemax:BAAALgAECgEJAQAAAA==.',
Ca='Caelestos:BAAALgAECgcJDgAAAA==.Castar:BAAALgADCgIJAgAAAA==.',
Cc='Ccwwds:BAAALgADCgMJAwABLgAECgUJCwAFAAAAAA==.',
Ce='Cewkie:BAABLgAECn8cAAIQAAYJSxR+DABYAQAQAAYJSxR+DABYAQAAAA==.',
Ch='Chausup:BAAALgADCgQJBAABLgAECggJIgADAIskAA==.Chautime:BAABLgAECn8iAAIDAAgJiyS/BwBYAwADAAgJiyS/BwBYAwAAAA==.Cheefillkeef:BAAALgADCgYJDAABLgAECgEJAQAFAAAAAA==.Chialliance:BAAALgAECgYJDQAAAA==.Chizz:BAAALgAECgQJBwABLgAFFAUJDQAIAEwSAA==.Choujisan:BAAALgAECgQJBwABLgAECgkJFQADAL0QAA==.Chrysamere:BAAALgADCgcJDQAAAA==.',
Ci='Citizenwings:BAAALgAECgEJAQAAAA==.',
Cl='Clairebenet:BAABLgAECn8eAAIGAAgJUiEMAQBfAgAGAAgJUiEMAQBfAgAAAA==.Cloft:BAAALgADCgkJGAAAAA==.Clumzylock:BAAALgAECgUJCgABLgAECgYJGAARAJgKAA==.',
Co='Code:BAABLgAECn8aAAISAAgJtSLFBwAUAwASAAgJtSLFBwAUAwAAAA==.Coolynn:BAAALgADCgYJBgAAAA==.Corl:BAABLgAECn8UAAIDAAcJPR3MEQCVAQADAAcJPR3MEQCVAQAAAA==.Corrl:BAAALgAECgYJCQABLgAECgcJFAADAD0dAA==.',
Cr='Crayzie:BAAALgADCgEJAQAAAA==.Crazyidiot:BAAALgADCgUJBQAAAA==.Creams:BAAALgADCgMJAwABLgADCgQJBAAFAAAAAA==.Creatrix:BAAALgADCgcJBwAAAA==.',
Cs='Csythe:BAAALgAECgYJDQAAAA==.',
Cu='Cuma:BAAALgAECgEJAgAAAA==.Cumb:BAAALgAECgQJBwAAAA==.Curatoria:BAAALgAECgQJBAAAAA==.',
Cw='Cwwddsz:BAAALgAECgEJAQABLgAECgUJCwAFAAAAAA==.',
['Cã']='Cãstanova:BAAALgADCgQJBAAAAA==.',
['Cä']='Cäldius:BAAALgAECgUJBwAAAA==.',
Da='Daladin:BAAALgADCgEJAQAAAA==.Damacraze:BAABLgAECn8XAAICAAgJciB0BAA6AgACAAgJciB0BAA6AgAAAA==.Darkbluerose:BAAALgAECgYJCwAAAA==.Darkevilaeon:BAAALgADCggJCAAAAA==.Darkmelon:BAAALgADCgEJAQAAAA==.Dawigrund:BAAALgAECgYJEAAAAA==.Daxine:BAAALgADCgkJDwAAAA==.',
De='Deadboy:BAAALgADCgcJBwAAAA==.Deadroar:BAAALgAECgYJDgAAAA==.Deadwill:BAAALgADCgYJBgAAAA==.Deaminase:BAAALgAECgYJEQAAAA==.Deathknell:BAAALgADCgQJBAAAAA==.Decypher:BAAALgAECgQJBwAAAA==.Deggle:BAAALgADCgIJAgAAAA==.Delphoxx:BAAALgAECgQJBAAAAA==.Demidru:BAAALgAECgQJBAAAAA==.Demonboar:BAAALgAECgYJEAAAAA==.Demunic:BAAALgAECgYJCgABLgAECggJHQAIAMQYAA==.Dennis:BAAALgAECgEJAQAAAA==.Derringer:BAAALgADCgkJCQAAAA==.Destructíon:BAAALgADCgUJBgAAAA==.',
Dh='Dhqt:BAAALgADCgQJBAAAAA==.',
Di='Digsy:BAAALgADCgEJAQAAAA==.Dingbangow:BAAALgAECgQJBwAAAA==.Divination:BAAALgADCgYJBgAAAA==.Divinèhero:BAAALgAECgEJAQAAAA==.',
Do='Donothingwin:BAABLgAECn8iAAMBAAgJeybdAwB+AwABAAgJeybdAwB+AwAPAAMJCiWbJwAlAQAAAA==.Doomgirl:BAAALgADCgkJGAAAAA==.Doublelift:BAAALgAFFAEJAQAAAA==.',
Dr='Drakblak:BAABLgAECn8fAAITAAgJQRa8BADkAQATAAgJQRa8BADkAQAAAA==.Draukarí:BAABLgAECn8eAAQUAAgJniFUAQDlAgAUAAgJhR9UAQDlAgABAAcJYRzmKABtAgAPAAEJiB+rXwBQAAAAAA==.Drayer:BAABLgAECn8VAAIHAAYJ1BLQEgAUAQAHAAYJ1BLQEgAUAQAAAA==.Dripped:BAAALgADCgcJBwAAAA==.Droni:BAAALgAECgYJEwAAAA==.Drunkenmist:BAAALgAECgYJCwAAAA==.Drunkle:BAAALgADCgUJBQAAAA==.Dröbi:BAACLgAFFH8FAAIMAAMJjx7YBgAWAQAMAAMJjx7YBgAWAQAuAAQKfyEAAwwACQlcIAQBAJkCAAwACQlcIAQBAJkCABUABgkIFU0aAGEBAAAA.',
Du='Dundundun:BAAALgAECgcJCAAAAA==.Duroklu:BAAALgAECgUJCAAAAA==.Durortar:BAAALgAECggJEQAAAA==.Durrok:BAAALgAECgEJAQAAAA==.',
Dy='Dynastes:BAAALgADCgQJAQABLgAFFAUJEQAKACEiAA==.Dyne:BAAALgADCgEJAQAAAA==.',
['Dê']='Dêdícatíón:BAAALgAECgYJCAAAAA==.',
['Dö']='Dödsriddare:BAAALgADCgYJBgAAAA==.',
Ea='Eazy:BAACLgAFFH8MAAMCAAQJdhI+BABAAQACAAQJxgg+BABAAQANAAQJKhKADwA2AQAuAAQKfyQAAw0ACAncI7kHAB8DAA0ACAncI7kHAB8DAAIAAgkxFm0vAJIAAAAA.',
Eg='Eggdrop:BAABLgAECn8VAAIQAAYJ9CBZJwAhAgAQAAYJ9CBZJwAhAgAAAA==.',
Eh='Ehgu:BAABLgAECn8hAAIWAAgJwRvwAABIAgAWAAgJwRvwAABIAgAAAA==.',
El='Eleverclear:BAABLgAECn8UAAIHAAcJkROuPgB+AQAHAAcJkROuPgB+AQAAAA==.Elfbloodbane:BAAALgADCggJCAAAAA==.Eliizabeth:BAAALgAECgUJCAAAAA==.',
Em='Emidget:BAAALgAECgEJAQAAAA==.',
Ep='Epicorc:BAAALgADCgEJAQAAAA==.',
Er='Erra:BAAALgAECgQJBQAAAA==.',
Et='Ethersong:BAAALgADCgcJCwAAAA==.',
Ev='Everlight:BAAALgADCgcJBwAAAA==.Evjoker:BAAALgAECgUJCAAAAA==.',
Ex='Exodes:BAAALgAECgYJDQAAAA==.',
Fa='Fairymonk:BAAALgAECgUJCQAAAA==.Fariona:BAAALgADCgEJAQAAAA==.Fartbarf:BAABLgAECn8eAAIBAAgJng93VADKAQABAAgJng93VADKAQAAAA==.Fascharrawm:BAAALgADCgEJAwAAAA==.Faya:BAAALgADCgUJBQABLgAECggJDwAFAAAAAA==.',
Fe='Fennicuss:BAAALgADCgYJCQAAAA==.Ferdalight:BAAALgAECgQJCAAAAA==.Festinu:BAAALgADCgQJBQAAAA==.',
Fi='Fistake:BAAALgAECgUJCwAAAA==.Fistalicious:BAAALgAECgMJAwABLgAFFAUJDwAXAPokAA==.Fitshaced:BAAALgADCgMJAwAAAA==.',
Fl='Flandia:BAAALgAECgEJAQAAAA==.Flintanyl:BAAALgADCgUJCQAAAA==.',
Fo='Forduecezero:BAAALgAECgYJDgAAAA==.',
Fr='Fricher:BAAALgAECgYJEwAAAA==.Fridgecig:BAAALgADCgcJBwAAAA==.Frostbringer:BAAALgADCgcJEwAAAA==.Frostworn:BAAALgADCgYJBgAAAA==.Frostybetch:BAAALgAECgUJBQAAAA==.Frozenwithin:BAAALgAECgMJAwAAAA==.Froznbolt:BAAALgADCgcJBwAAAA==.Froznlight:BAABLgAECn8YAAIDAAcJ+RwPMwBWAgADAAcJ+RwPMwBWAgAAAA==.Fruitsnacks:BAAALgAECgYJBgABLgAFFAYJEgALAC8XAA==.Fränk:BAAALgADCgcJDwAAAA==.Frío:BAAALgAECgQJBQAAAA==.Frõst:BAAALgADCgMJAwAAAA==.',
Fu='Fusio:BAAALgADCgMJAwAAAA==.',
Fy='Fylerian:BAACLgAFFH8TAAIYAAYJQx1eAADTAQAYAAYJQx1eAADTAQAuAAQKfx0AAhgACQkwJHcCAJcDABgACQkwJHcCAJcDAAAA.Fylerianmage:BAABLgAECn8VAAIJAAYJMiD7lwClAQAJAAYJMiD7lwClAQABLgAFFAYJEwAYAEMdAA==.Fylerianprie:BAAALgAECgQJBgABLgAFFAYJEwAYAEMdAA==.Fyrebane:BAAALgADCgYJBgAAAA==.',
Ga='Galaxygas:BAAALgAECgYJDQAAAA==.Ganjja:BAAALgAECgEJAQAAAA==.Gardrath:BAAALgAECgcJDQAAAA==.Gargalon:BAAALgAECgMJAwAAAA==.Gatør:BAAALgAECgYJEgAAAA==.',
Ge='Gether:BAAALgADCgcJDAAAAA==.Getter:BAAALgAECgcJDwAAAA==.',
Gh='Ghettomike:BAAALgAECgUJCQAAAA==.',
Gi='Gilga:BAAALgAECgYJCgAAAA==.Giny:BAAALgAECgYJEwAAAA==.',
Gl='Glandros:BAAALgADCgEJAQAAAA==.',
Go='Gobbledeez:BAAALgAECgcJCQAAAA==.Gojojo:BAABLgAECn8kAAIQAAgJ2xtIEwC0AgAQAAgJ2xtIEwC0AgAAAA==.Gorfrunch:BAAALgAECgUJCQAAAA==.Gorro:BAAALgAECgEJAQAAAA==.Govinniuur:BAABLgAECn8cAAILAAcJyg1uCAAGAQALAAcJyg1uCAAGAQAAAA==.',
Gr='Grandcodex:BAAALgADCgcJBwABLgAECggJHQAKABQQAA==.Granips:BAAALgADCgIJAQAAAA==.Gravelord:BAAALgADCgEJAQAAAA==.Grawnita:BAABLgAECn8iAAIJAAgJ1CLeEwAxAwAJAAgJ1CLeEwAxAwAAAA==.Grizzy:BAAALgAECgQJBQAAAA==.Grohan:BAAALgADCgEJAQAAAA==.Groundscore:BAAALgADCgUJBQABLgADCgUJBQAFAAAAAA==.',
Gu='Gundam:BAAALgAECgcJBwAAAA==.Gunde:BAAALgADCgQJAwAAAA==.',
Gw='Gweilo:BAAALgADCgQJBAAAAA==.Gwendilyn:BAAALgADCgkJEgAAAA==.Gwydionatlan:BAAALgADCgEJAQAAAA==.',
Gy='Gyndrinolara:BAAALgAECgcJEAAAAA==.',
Ha='Hafadude:BAAALgAECgkJBwAAAA==.Hakouh:BAAALgAECgYJBwAAAA==.Harambabe:BAAALgAECgYJBgAAAA==.Hatereading:BAAALgADCgcJCAAAAA==.',
He='Headhuntér:BAAALgAECgQJBQAAAA==.Healdnbloody:BAAALgAECgIJAgAAAA==.Healgoßyeßye:BAAALgAECgEJAgAAAA==.Heckitwebawl:BAAALgADCgEJAQABLgAECggJIgAOAIEUAA==.Hehatesme:BAAALgADCgcJBwAAAA==.Hellface:BAAALgADCgcJDAABLgAFFAEJAQAFAAAAAA==.Hellokrittyz:BAAALgADCgcJBwAAAA==.Hephaestis:BAAALgADCgUJBQAAAA==.',
Hi='Hiimmas:BAAALgAECgkJAgABLgAFFAQJCAAWAKAbAA==.',
Ho='Holywater:BAABLgAECn8oAAIEAAgJ4x+sAAB/AgAEAAgJ4x+sAAB/AgAAAA==.Hoon:BAAALgADCgkJCQAAAA==.Hoonish:BAAALgAECgYJDwAAAA==.',
Hr='Hruaka:BAAALgAECgMJAwAAAA==.',
Ia='Iamstronge:BAAALgADCgMJAwAAAA==.',
Il='Illuminax:BAAALgAECgUJCAAAAA==.Illydan:BAAALgAECgIJAgABLgAECgQJBgAFAAAAAA==.',
Im='Immahotmess:BAAALgAECgEJAQAAAA==.',
In='Inamorta:BAAALgAECgQJBQAAAA==.Ineedbowjob:BAAALgAECgYJCgAAAA==.Intothedark:BAAALgAECgIJAwAAAA==.Inya:BAAALgAECgIJBQAAAA==.Inyomouf:BAAALgADCgEJAQAAAA==.',
Io='Iomadae:BAABLgAECn8ZAAIDAAgJxyCLFwDbAgADAAgJxyCLFwDbAgAAAA==.',
Ir='Ironjaws:BAAALgAECgQJBwAAAA==.',
Is='Isaacnewton:BAAALgAECgQJEgAAAA==.',
It='Ithoril:BAAALgADCgcJCgAAAA==.Itsdone:BAABLgAECn8hAAMBAAgJ+BA2TQDhAQABAAgJPBA2TQDhAQAPAAMJWxHjQACxAAABLgAFFAEJAQAFAAAAAA==.',
Iv='Iveliz:BAAALgAECgYJCwAAAA==.',
Iz='Izheals:BAAALgADCgEJAQABLgAECgcJGAAMAAUQAA==.',
Ja='Jackk:BAABLgAECn8mAAIHAAgJJSFDCADqAgAHAAgJJSFDCADqAgAAAA==.Jackks:BAAALgAECgEJAQABLgAECggJJgAHACUhAA==.Jaeger:BAABLgAECn8VAAIGAAgJjhl0CABiAgAGAAgJjhl0CABiAgAAAA==.Janzan:BAAALgAECgYJEwAAAA==.Jasmonk:BAABLgAECn8XAAIZAAYJCwfcDgDjAAAZAAYJCwfcDgDjAAAAAA==.Jayren:BAAALgAECgIJAgAAAA==.',
Je='Jenniekim:BAABLgAECn8XAAIaAAgJ9AovHwAQAQAaAAgJ9AovHwAQAQAAAA==.',
Ji='Jinkz:BAAALgAECgEJAQAAAA==.',
Jo='Josephsmith:BAAALgAECgcJAwAAAA==.',
Ju='Judgevis:BAAALgAECggJEQAAAA==.Jumbles:BAAALgADCgkJGAAAAA==.Justeene:BAAALgADCgcJBwABLgAECgEJAQAFAAAAAA==.',
Jv='Jvedo:BAAALgADCgYJBQAAAA==.',
['Jø']='Jøshu:BAAALgADCgIJAgAAAA==.',
Ka='Kabalester:BAAALgAECgIJAgAAAA==.Kaello:BAAALgAECgEJAQABLgAECgYJCwAFAAAAAA==.Kaerigyn:BAAALgAECgYJCwAAAA==.Karrona:BAAALgADCgcJEgAAAA==.Katirinu:BAAALgADCgMJAwAAAA==.Kawliga:BAAALgADCgkJDwAAAA==.Kazuu:BAAALgADCgEJBQAAAA==.',
Ke='Keepup:BAAALgAECgYJBgABLgAECggJIgABAHsmAA==.Keg:BAAALgAFFAEJAgABLgAFFAYJEgALAC8XAA==.Keheo:BAAALgADCgMJAwAAAA==.Keimei:BAAALgADCgMJAwABLgAECgYJEAAFAAAAAA==.Keladun:BAAALgAECgUJCQAAAA==.',
Kh='Khaho:BAAALgAECggJEQAAAA==.Khonan:BAAALgAECgYJEwABLgAFFAUJCgAJADsYAA==.',
Ki='Kiamar:BAAALgAECggJDgAAAA==.Kijyo:BAAALgAECgYJDAAAAA==.Kishu:BAAALgADCggJDQAAAA==.Kitz:BAAALgADCgEJAQAAAA==.',
Ko='Koinzell:BAAALgADCgEJAgAAAA==.Kojirin:BAAALgADCgYJBwAAAA==.Kordarg:BAAALgAECgUJBQAAAA==.',
Kr='Krex:BAAALgADCgYJDQAAAA==.Krossedup:BAAALgADCgYJBwAAAA==.Krystal:BAAALgAECgIJBAAAAA==.Kröw:BAAALgAECggJEwAAAA==.',
Ku='Kudrix:BAABLgAECn8UAAIZAAYJkx5PBgCBAQAZAAYJkx5PBgCBAQAAAA==.Kurø:BAABLgAECn8YAAIKAAcJHR3ePwA5AgAKAAcJHR3ePwA5AgAAAA==.',
Kw='Kwanzie:BAAALgADCgEJAQAAAA==.',
Ky='Kyoco:BAAALgADCgEJAQAAAA==.Kyprolis:BAAALgADCgYJBgAAAA==.Kyushi:BAAALgAECgYJEQAAAA==.',
['Kà']='Kàri:BAAALgAECggJEwAAAA==.',
['Kä']='Käva:BAAALgAECgEJAQAAAA==.',
['Kï']='Kïngston:BAEALgAECgYJDwAAAA==.',
La='Lamorakk:BAAALgAECgEJAQAAAA==.Lany:BAABLgAECn8YAAMKAAcJ6BSXaAC8AQAKAAcJDhSXaAC8AQAbAAMJtxFbFQA/AAAAAA==.Latherfanta:BAAALgAECgUJCQAAAA==.Laurijaydn:BAAALgAECgcJAQAAAA==.',
Le='Lelink:BAAALgAECgYJDAAAAA==.Lemywinx:BAAALgAECgEJAQAAAA==.Leoden:BAAALgADCgUJBAAAAA==.Lepra:BAAALgADCgUJBgAAAA==.Leslieknope:BAAALgADCgIJAgAAAA==.',
Li='Lichbabies:BAAALgADCgMJAwAAAA==.Lielys:BAAALgAECgUJEQABLgAECgYJCQAFAAAAAA==.Lightlana:BAABLgAECn8cAAIDAAgJuSHNGADUAgADAAgJuSHNGADUAgAAAA==.Lightwalker:BAAALgAECgUJBQAAAA==.Linfang:BAAALgADCgYJBgAAAA==.Littlestarz:BAABLgAECn8UAAMcAAYJ4R6UBgDuAQAcAAYJ4R6UBgDuAQAdAAMJ5QpAbgCKAAAAAA==.Lizzieag:BAEBLgAECn8kAAIQAAgJLBhyBQDYAQAQAAgJLBhyBQDYAQAAAA==.',
Ll='Lluvia:BAAALgAECgQJBwAAAA==.',
Lo='Loenil:BAAALgAECgYJDAAAAA==.Lohueng:BAAALgAECgEJAQAAAA==.Loodah:BAAALgAECgIJAgAAAA==.Lookee:BAAALgADCgcJEgAAAA==.Loranoth:BAAALgADCgUJDAAAAA==.Loreel:BAAALgAECgUJBQAAAA==.Loudnoise:BAAALgADCgYJBgAAAA==.',
Lu='Lucielle:BAAALgAECgYJCgAAAA==.Luke:BAAALgAECgIJAgAAAA==.Luminali:BAAALgADCggJCgAAAA==.Lunareva:BAABLgAECn8XAAIeAAYJ9CK7BwDoAQAeAAYJ9CK7BwDoAQAAAA==.Lunä:BAAALgAECgYJCgABLgAFFAUJCAACAM0GAA==.',
Ly='Lyxon:BAAALgAECgQJCAAAAA==.',
['Lå']='Låw:BAAALgADCgkJHwAAAA==.',
Ma='Maandos:BAAALgADCgcJBwAAAA==.Mabrian:BAAALgADCgcJBwAAAA==.Mafoôza:BAABLgAECn8bAAIQAAcJtR5dBgC/AQAQAAcJtR5dBgC/AQAAAA==.Magicalama:BAAALgADCgUJBQABLgAECgcJGgAGACMgAA==.Magicnugz:BAAALgADCgEJAQAAAA==.Magnanimity:BAEALgADCgEJAQABLgAECgYJEQAFAAAAAA==.Magpen:BAAALgADCgMJBgAAAA==.Mahboyblu:BAAALgADCggJCwAAAA==.Mahndoo:BAABLgAECn8WAAIJAAgJNBPCYwARAgAJAAgJNBPCYwARAgAAAA==.Makto:BAAALgADCgUJBQAAAA==.Malia:BAAALgADCgUJBQAAAA==.Maliciouso:BAAALgAECgYJEAAAAA==.Malédiction:BAABLgAECn8ZAAIJAAgJ6RXfdwDiAQAJAAgJ6RXfdwDiAQAAAA==.Maymae:BAAALgADCgkJCQAAAA==.',
Me='Medizine:BAAALgADCgIJAgAAAA==.Meepz:BAAALgAECgEJAQAAAA==.Megademac:BAABLgAECn8UAAIaAAUJnxDIiwALAQAaAAUJnxDIiwALAQAAAA==.Meowenstein:BAAALgAECgMJBgAAAA==.',
Mi='Miistral:BAAALgAECgYJEwAAAA==.Miniblinks:BAAALgADCgQJBAAAAA==.Minisid:BAAALgAFFAEJAQAAAA==.Mirshta:BAAALgADCggJDwAAAA==.Missmaam:BAAALgAECgYJEwAAAA==.Mistinmae:BAAALgAECgEJAQABLgAECgYJCwAFAAAAAA==.Mistrjenkins:BAAALgAECgEJAQAAAA==.Mixoz:BAAALgAECgQJBAAAAA==.',
Mo='Moistooltip:BAAALgADCgYJCwABLgAECgYJEQAFAAAAAA==.Mokotrize:BAABLgAECn8WAAIEAAYJCRcdFQB9AQAEAAYJCRcdFQB9AQAAAA==.Monarch:BAAALgADCgEJAQAAAA==.Mookate:BAABLgAECn8cAAIYAAgJkhtpEACdAgAYAAgJkhtpEACdAgAAAA==.Moonblade:BAAALgADCgMJAwAAAA==.Mootylicious:BAAALgAECgEJAQABLgAECgYJEQAFAAAAAA==.Mordred:BAAALgAECgUJBQAAAA==.',
Ms='Msfirefly:BAAALgAECgYJCAAAAA==.',
Mu='Mud:BAAALgADCgMJAwAAAA==.Munchies:BAAALgAECgQJBAAAAA==.Murlooze:BAAALgADCgYJBgAAAA==.Muwunfire:BAAALgADCgcJBwAAAA==.',
My='Myrolan:BAAALgAECgcJCQAAAA==.Myrowrynn:BAAALgAECgYJBgABLgAECgcJCQAFAAAAAA==.Myrozond:BAAALgAECgYJDwABLgAECgcJCQAFAAAAAA==.',
['Má']='Mánú:BAAALgAECgYJDQABLgAECgcJGAADAGcjAA==.',
['Mä']='Mänu:BAABLgAECn8YAAIDAAcJZyNJGQDRAgADAAcJZyNJGQDRAgAAAA==.',
['Mø']='Mønstrøsity:BAAALgAECgEJAQAAAA==.',
Na='Naiyah:BAAALgAFFAEJAQAAAA==.Namelesskin:BAAALgAECgQJBAAAAA==.Nanoko:BAABLgAECn8hAAIZAAgJvCIgAQB4AgAZAAgJvCIgAQB4AgAAAA==.Nayasylpha:BAABLgAECn8fAAIfAAgJxhzxDwCdAgAfAAgJxhzxDwCdAgAAAA==.Nazara:BAAALgADCgYJBgAAAA==.',
Ne='Neekage:BAAALgADCgEJAQAAAA==.Nephertiti:BAAALgADCgYJCgAAAA==.Neuro:BAABLgAECn8iAAIJAAgJbCFFBQBhAgAJAAgJbCFFBQBhAgAAAA==.Newxexhu:BAAALgAECgQJBAAAAA==.',
Ni='Nicolico:BAAALgADCgcJBwAAAA==.Nictamom:BAAALgAECgEJAQAAAA==.Nirri:BAAALgAECgEJAQAAAA==.Nishendra:BAABLgAECn8ZAAIOAAgJ+x78BgDQAgAOAAgJ+x78BgDQAgAAAA==.Nitama:BAAALgADCgYJBwAAAA==.Nitefall:BAAALgAECgYJDgAAAA==.',
No='Noblok:BAAALgAECgMJAwAAAA==.Nocando:BAAALgAFFAEJAQAAAA==.Nofeetpicsyo:BAABLgAECn8YAAIRAAYJmAqBEADvAAARAAYJmAqBEADvAAAAAA==.Nootella:BAABLgAECn8UAAIHAAYJlSIqHgAlAgAHAAYJlSIqHgAlAgAAAA==.Norgoma:BAAALgAECgYJDwAAAA==.Normmarry:BAAALgAECgUJCgAAAA==.Notybynature:BAAALgADCgIJAgAAAA==.',
Nu='Nuriel:BAABLgAECn8XAAIRAAcJLhkJGwAGAgARAAcJLhkJGwAGAgAAAA==.',
Ny='Nylinu:BAAALgADCgQJBAABLgAECggJJAAPAJEdAA==.Nylinuya:BAAALgAECgYJBgABLgAECggJJAAPAJEdAA==.Nyteskye:BAAALgADCgYJDQAAAA==.Nyxoblivion:BAAALgADCgcJCgAAAA==.',
['Nî']='Nîco:BAABLgAECn8eAAIeAAcJxx/0GABwAgAeAAcJxx/0GABwAgAAAA==.',
Ob='Obsydia:BAAALgADCgcJDQAAAA==.',
Oc='Octin:BAABLgAECn8fAAMfAAgJMQ5RCAByAQAfAAgJ3Q1RCAByAQAZAAEJWBW0eAA5AAAAAA==.',
Ok='Okowilly:BAAALgADCgcJCgAAAA==.',
Ol='Oline:BAABLgAECn8ZAAIBAAYJABd0YgCiAQABAAYJABd0YgCiAQAAAA==.',
Om='Ommnom:BAAALgAECgQJBAABLgAECggJIgAOAIEUAA==.',
On='Oneall:BAABLgAECn8ZAAIYAAcJZxPwCwAuAQAYAAcJZxPwCwAuAQAAAA==.Onehit:BAAALgAECgIJBAAAAA==.Onlyspells:BAABLgAECn8WAAMJAAgJYwm1pwCKAQAJAAgJYwm1pwCKAQAgAAEJnAEJEgAgAAAAAA==.',
Oo='Oomcrit:BAAALgAECgUJCQAAAA==.Oonaki:BAABLgAECn8hAAILAAgJoxhpBACMAQALAAgJoxhpBACMAQAAAA==.',
Or='Oreoz:BAAALgADCgUJBQAAAA==.',
Ot='Othin:BAAALgAECgcJDAAAAA==.',
Pa='Painloa:BAAALgAECgYJEAAAAA==.Pam:BAAALgADCgYJCgAAAA==.Panacéa:BAABLgAECn8bAAIhAAgJzw/dHACuAQAhAAgJzw/dHACuAQAAAA==.Pandadance:BAAALgAECgcJEgAAAA==.Pandakill:BAAALgAECgQJBAAAAA==.Pandanimal:BAAALgAECgEJAgAAAA==.Pandar:BAAALgAECgQJBAAAAA==.Pandrael:BAAALgADCgMJAwAAAA==.Paotah:BAAALgAECgEJAQAAAA==.Papaganu:BAAALgADCgYJCQABLgAECgYJCwAFAAAAAA==.Papagenu:BAAALgAECgYJBgABLgAECgYJCwAFAAAAAA==.Papsfear:BAAALgADCgQJBAAAAA==.Paradoxx:BAABLgAECn8gAAIJAAgJDyJYGwAJAwAJAAgJDyJYGwAJAwAAAA==.Pazzie:BAAALgADCgYJCwAAAA==.',
Pe='Petrogris:BAAALgADCgUJBQAAAA==.',
Ph='Phelefica:BAAALgAECgUJBwAAAA==.',
Pm='Pmac:BAAALgADCgYJBwABLgAECgUJFAAaAJ8QAA==.',
Po='Poggie:BAAALgAECgQJBQAAAA==.Pointybrows:BAAALgAECgEJAgAAAA==.Poppé:BAAALgAECgMJAwAAAA==.Porkfu:BAAALgADCgQJBAAAAA==.Potroaster:BAAALgAECgEJAQAAAA==.Powerflower:BAAALgADCgYJBwAAAA==.',
Pr='Professorson:BAAALgADCgEJAQAAAA==.Proteinbar:BAAALgADCgQJBAABLgAECgEJAQAFAAAAAA==.',
Pu='Putresca:BAAALgADCgkJCQAAAA==.',
Py='Pyroheart:BAAALgAECgYJEwAAAA==.',
Qa='Qai:BAABLgAECn8cAAMiAAcJrQ6WFwBEAQAiAAUJYhSWFwBEAQAIAAcJtAVyHgCtAAAAAA==.',
Qu='Quelestraza:BAAALgAECgYJDAAAAA==.',
Ra='Raewyck:BAABLgAECn8iAAICAAgJ3xS8LQD8AQACAAgJ3xS8LQD8AQAAAA==.Ragar:BAAALgAECgEJAQABLgAFFAMJBgAQAG4ZAA==.Raginbull:BAAALgAECgYJEgAAAA==.Ragingmaze:BAAALgAECgYJCwAAAA==.Rainburrow:BAAALgADCgkJFwAAAA==.Raptormortis:BAABLgAECn8WAAMdAAcJKRlRIAANAgAdAAcJKRlRIAANAgAcAAIJbQv4hwB0AAAAAA==.Raskolniköv:BAAALgAECgUJBwAAAA==.Raskolnikøv:BAAALgADCgcJBgABLgAECgUJBwAFAAAAAA==.Rayjin:BAAALgAECgYJBgABLgAECgcJDgAFAAAAAA==.Raylen:BAAALgADCgkJGAAAAA==.',
Re='Reckz:BAAALgADCgQJCAAAAA==.Regarr:BAAALgADCgEJAQABLgADCgYJBgAFAAAAAA==.Rellic:BAAALgADCgEJAQAAAA==.Renku:BAAALgAECgQJDgAAAA==.Retana:BAAALgAECgQJBQAAAA==.',
Rh='Rhinn:BAAALgAECgQJBAAAAA==.Rhythm:BAAALgAECgYJBgAAAA==.',
Ri='Rickypeepee:BAAALgAECgQJBAAAAA==.Ritsuyi:BAAALgADCgYJBgABLgAECgMJAwAFAAAAAA==.',
Ro='Roarbear:BAAALgAECgYJBgAAAA==.Roastedz:BAAALgAECgMJBQAAAA==.Rolánd:BAAALgADCgkJCQAAAA==.Roomi:BAABLgAECn8jAAIWAAgJ0xZpAQATAgAWAAgJ0xZpAQATAgAAAA==.Roowar:BAAALgADCgEJAQAAAA==.Rorthu:BAAALgADCgkJGAAAAA==.Roru:BAAALgAECgQJBwABLgAECgYJFAABAKUSAA==.Rozie:BAAALgAECgQJBAAAAA==.',
Ru='Rukélie:BAAALgADCgkJGAAAAA==.',
Ry='Ry:BAAALgAECgUJDgAAAA==.Ryanna:BAAALgADCgIJAgAAAA==.Rygon:BAAALgADCgMJAwAAAA==.Rymax:BAAALgADCgkJCQAAAA==.Ryy:BAAALgAECgYJBwAAAA==.',
['Ræ']='Rædiêncë:BAAALgAECgQJBwAAAA==.',
['Rò']='Ròó:BAABLgAECn8cAAMSAAgJhB/oCAACAwASAAgJhB/oCAACAwAjAAIJ3h59FAC1AAAAAA==.',
Sa='Saevio:BAAALgAECgYJEwAAAA==.Sallean:BAAALgAECgEJAQAAAA==.Saoikingston:BAEALgAECgYJBQABLgAECgYJDwAFAAAAAA==.Sarayu:BAAALgADCgcJDQAAAA==.Sashimi:BAABLgAECn8cAAMKAAcJlxlPQgAwAgAKAAcJlxlPQgAwAgAbAAQJgRHvBADKAAAAAA==.Sassyjay:BAAALgAECgcJBgAAAA==.Sassyuwu:BAACLgAFFH8FAAIHAAMJ/hX7DQD3AAAHAAMJ/hX7DQD3AAAuAAQKfxcAAgcACAnGJWgEACcDAAcACAnGJWgEACcDAAAA.',
Sc='Scarlet:BAAALgADCgEJAQAAAA==.Schbag:BAAALgAECgMJAwAAAA==.Scotchnsoda:BAACLgAFFH8HAAMTAAMJ3gNmCgC/AAATAAMJjgNmCgC/AAAhAAEJJQPKDAA+AAAuAAQKfx4AAxMACAkZEXMpAKYBABMACAkZEXMpAKYBABEAAQlyAL5rABoAAAAA.Scrives:BAAALgAECgYJDAAAAA==.Scrubiclese:BAAALgADCgQJBAAAAA==.',
Se='Seldaren:BAAALgAECgMJAwAAAA==.Selenegosa:BAABLgAECn8XAAMVAAYJEha2AwAWAQAVAAYJEha2AwAWAQAMAAQJdg0ySQCxAAABLgAECggJGQACABcfAA==.Seran:BAAALgAECgYJEAAAAA==.Serenade:BAABLgAECn8ZAAIYAAgJcwzxLwCHAQAYAAgJcwzxLwCHAQAAAA==.Severyne:BAABLgAECn8hAAIeAAgJyiMYBQA8AwAeAAgJyiMYBQA8AwAAAA==.',
Sh='Shadowchad:BAAALgADCgUJCQAAAA==.Shadowmeld:BAAALgAECgYJBAAAAA==.Shadyhealer:BAAALgAECgEJAQAAAA==.Shaile:BAAALgADCggJCQAAAA==.Shamanu:BAAALgAECgcJDgABLgAECgcJGAADAGcjAA==.Shamsel:BAAALgAECgYJDwAAAA==.Shaunpj:BAAALgAECgMJBAAAAA==.Shermlock:BAAALgAECgIJAgAAAA==.Shiftychiz:BAACLgAFFH8NAAIIAAUJTBI1AgAQAQAIAAUJSxI1AgAQAQAuAAQKfyQAAggACQnXIEICABEDAAgACQnXIEICABEDAAAA.Shiéld:BAAALgAECgcJEAAAAA==.Shobogenzo:BAAALgADCgMJAwAAAA==.Shockcaller:BAAALgAECgQJCgAAAA==.Shorin:BAAALgADCgYJCQAAAA==.Showtooltip:BAAALgAECgYJEQAAAA==.Shulla:BAABLgAECn8bAAIeAAgJryQHBABQAwAeAAgJryQHBABQAwAAAA==.Shweatyballs:BAABLgAECn8XAAIJAAYJWhvCGQB6AQAJAAYJWhvCGQB6AQAAAA==.',
Si='Silran:BAAALgAECgYJEAAAAA==.Simmara:BAAALgAECgcJEgAAAA==.Sinner:BAECLgAFFH8LAAITAAUJphHFBAA6AQATAAUJphHFBAA6AQAuAAQKfxkAAxMACQkHHNQHAM4CABMACQkHHNQHAM4CABEAAwnuAwVZAFcAAAAA.',
Sk='Skaboodle:BAAALgAECgQJBAABLgAFFAUJDwAXAPokAA==.Skruff:BAAALgAECgIJAwAAAA==.',
Sl='Slamuraijack:BAAALgAECgQJAQAAAA==.Slayngin:BAAALgAECgQJCAABLgAECgUJCAAFAAAAAA==.Sleepydeputy:BAAALgAECgUJBwAAAA==.Sleetwoodmac:BAAALgAECgIJAgAAAA==.',
Sm='Smeggsbenny:BAAALgADCgQJBAAAAA==.',
So='Solaris:BAAALgADCgcJCwAAAA==.Solstica:BAAALgAECgIJAgAAAA==.Sora:BAAALgAECgEJAQAAAA==.',
Sp='Sparklemeow:BAAALgADCgEJAQAAAA==.Spiritualone:BAAALgAECgYJEAAAAA==.',
Sq='Squishly:BAAALgAECgQJCAAAAA==.',
St='Stanmarshh:BAAALgADCgEJAQAAAA==.Staydown:BAAALgADCgEJAgAAAA==.Steelrib:BAAALgAECgQJBAAAAA==.Stogienuna:BAAALgADCgYJBgAAAA==.Straam:BAACLgAFFH8IAAIcAAMJMAuGEQDbAAAcAAMJMAuGEQDbAAAuAAQKfygAAhwACQnYHXkCAHMCABwACQnYHXkCAHMCAAAA.Stupidity:BAAALgADCgkJCgAAAA==.Støney:BAABLgAECn8aAAIJAAYJlA3wywBSAQAJAAYJlA3wywBSAQAAAA==.',
Su='Subatronic:BAAALgAECgEJAQABLgAFFAUJDwAXAPokAA==.Subroutine:BAABLgAECn8WAAINAAgJHh/ZDgDIAgANAAgJHh/ZDgDIAgABLgAFFAUJDwAXAPokAA==.Subtractive:BAACLgAFFH8PAAIXAAUJ+iTRAAAeAgAXAAUJ+iTRAAAeAgAuAAQKfxsAAhcACAmmJiQBAIYDABcACAmmJiQBAIYDAAAA.',
Sw='Swodaem:BAAALgADCgQJBAAAAA==.',
Sx='Sx:BAACLgAFFH8FAAIJAAIJ2SHCMwDKAAAJAAIJ2SHCMwDKAAAuAAQKfyIAAgkACQk5I7QFAKcDAAkACQk5I7QFAKcDAAAA.',
Sy='Sylthara:BAAALgAECgYJDQAAAA==.Syrellis:BAAALgAECgEJAQAAAA==.',
['Så']='Såcred:BAAALgADCggJDwAAAA==.',
Ta='Taenggu:BAABLgAECn8UAAIkAAYJChI/BAAWAQAkAAYJChI/BAAWAQAAAA==.Takki:BAAALgAECgIJAgAAAA==.Talethia:BAAALgAECgEJAQAAAA==.Tartarus:BAAALgAECgMJAwAAAA==.Tavin:BAAALgADCgcJBwAAAA==.Tazchem:BAAALgAECgEJAQAAAA==.',
Te='Teinuya:BAABLgAECn8kAAQPAAgJkR0nAgB/AQAUAAUJgBzQCgCPAQAPAAYJEx0nAgB/AQABAAEJ1RnlDQFCAAAAAA==.Teivel:BAAALgADCgYJBgAAAA==.Tekorgx:BAAALgADCgkJJwAAAA==.Tenderfiddle:BAAALgAECgYJDgAAAA==.Tenochitilan:BAAALgAECgEJAQAAAA==.Tenuous:BAAALgAECgMJAwAAAA==.Teregor:BAAALgADCgEJAQAAAA==.',
Th='Thainir:BAAALgAECgIJAgABLgAECggJGwAeAK8kAA==.Thanar:BAAALgADCgEJAQAAAA==.Thisistheway:BAAALgAECgYJEwABLgAFFAIJBQAOAHIUAA==.Thoorz:BAAALgADCgUJBQAAAA==.Thornman:BAAALgADCgcJBwAAAA==.Thorzy:BAAALgAECgYJDAABLgADCgUJBQAFAAAAAA==.Thothh:BAAALgAECgUJBgAAAA==.Thraxacious:BAABLgAECn8gAAIiAAgJuBjGAQDmAQAiAAgJuBjGAQDmAQAAAA==.Thulcandra:BAABLgAECn8UAAIJAAYJxB/jYwARAgAJAAYJxB/jYwARAgAAAA==.Thulsadoomm:BAAALgAECgYJDAAAAA==.Thundermay:BAAALgAECgYJCwAAAA==.',
Ti='Tibremix:BAAALgADCgYJBgAAAA==.Tiduss:BAAALgAECgUJCgAAAA==.Tigó:BAAALgAECgYJDAAAAA==.Tigölebittie:BAAALgAECgcJDwAAAA==.Tinkerrbella:BAABLgAECn8UAAMCAAcJvQ3zUwBsAQACAAcJvQ3zUwBsAQANAAUJFgIEbQCKAAABLgAFFAUJCAACAM0GAA==.Tireliaa:BAAALgAECgEJAQAAAA==.',
To='Toatsie:BAAALgAECgQJCQAAAA==.Toyotathon:BAAALgADCgYJBgAAAA==.',
Tr='Trafalgour:BAAALgADCgMJAwAAAA==.Traxal:BAAALgAECgcJBQAAAA==.Trumpybear:BAAALgAECgYJEAAAAA==.',
Ts='Tsun:BAABLgAECn8UAAIlAAYJ0BRABQA8AQAlAAYJ0BRABQA8AQAAAA==.',
Ty='Tyys:BAAALgADCgMJAwAAAA==.',
['Tø']='Tønka:BAAALgAECgUJBgABLgAECgcJGAADAGcjAA==.',
Ud='Uddertrouble:BAEALgAECgYJEQAAAA==.',
Uf='Ufos:BAAALgADCggJFwAAAA==.',
Ui='Ui:BAAALgADCgUJBQABLgAFFAIJBQAJANkhAA==.',
Un='Uncletat:BAABLgAECn8aAAMTAAYJWiX+AQBhAgATAAYJNiX+AQBhAgAhAAYJmCFUDwBJAgAAAA==.',
Ur='Urmada:BAAALgAECgYJEgAAAA==.Urmami:BAAALgAECgYJDgAAAA==.',
Ut='Uthil:BAAALgADCgQJBAAAAA==.',
Va='Vahnt:BAABLgAECn8eAAIcAAgJRxd8IAAcAgAcAAgJRxd8IAAcAgAAAA==.Valkon:BAAALgADCgYJBgAAAA==.Vallissrya:BAABLgAECn8fAAIDAAkJ1xuEJgCMAgADAAkJ1xuEJgCMAgAAAA==.Vampire:BAAALgAECgIJAgAAAA==.Vampyre:BAACLgAFFH8SAAILAAYJLxeRAQBmAQALAAYJLxeRAQBmAQAuAAQKfxgAAgsACQmaIfgCADMDAAsACQmaIfgCADMDAAAA.Vanadie:BAAALgADCgkJGAAAAA==.Vanta:BAAALgADCgcJDQAAAA==.Vargmal:BAAALgADCgEJAgAAAA==.',
Ve='Velo:BAAALgAECgMJAwAAAA==.Veloboom:BAAALgAECgMJAwAAAA==.Vendettá:BAAALgAECgQJCQAAAA==.Vengeta:BAAALgADCgQJBAAAAA==.Venomflare:BAAALgADCgUJBQAAAA==.',
Vi='Vitaminn:BAABLgAECn8VAAQDAAYJ6BYOGABhAQADAAYJIxYOGABhAQAHAAIJTwZNigBUAAAEAAEJnBf4PgBCAAAAAA==.',
Vl='Vlaen:BAAALgAECgMJAwAAAA==.',
Vo='Voidreaper:BAAALgADCgEJAgAAAA==.Votum:BAAALgAECgMJAwAAAA==.',
Vy='Vyndanin:BAAALgAECggJDQAAAA==.',
Wa='Walterlight:BAAALgADCgIJAgAAAA==.Warlockd:BAAALgADCgUJBQAAAA==.Wazoshao:BAAALgADCgIJAgAAAA==.',
We='Welios:BAAALgAECgMJBgAAAA==.',
Wh='Wheataid:BAAALgADCggJDQAAAA==.',
Wi='Wilhedin:BAACLgAFFH8GAAIQAAMJbhlIDwARAQAQAAMJbhlIDwARAQAuAAQKfykAAyUACAlRJnYAAJ4CABAABwkHJJwNAOkCACUACAm6I3YAAJ4CAAAA.Windente:BAABLgAECn8VAAMCAAcJ4RKuUQBzAQACAAYJoBKuUQBzAQANAAQJ/QjzZgCjAAAAAA==.Wing:BAEALgAFFAIJBAABLgAFFAUJCwATAKYRAA==.Wiseau:BAAALgAECgYJEQAAAA==.',
Wo='Wolfer:BAAALgADCgEJAQAAAA==.Wong:BAAALgAECgEJAwAAAA==.',
Wu='Wulfnbolt:BAAALgADCgIJAgAAAA==.Wumbology:BAAALgAECgcJAQAAAA==.',
Wy='Wyon:BAAALgAECgYJDQAAAQ==.',
Xu='Xuen:BAAALgAECgYJDAAAAA==.',
Yo='Yokog:BAAALgAECgMJBQAAAA==.',
Za='Zaeluna:BAABLgAECn8fAAIIAAgJyx92AwDWAgAIAAgJyx92AwDWAgAAAA==.Zanzer:BAAALgAECgEJAgAAAA==.Zathara:BAAALgAECgYJCQAAAA==.',
Ze='Zeevoid:BAAALgADCgEJAQAAAA==.Zephiron:BAAALgADCgcJDgAAAA==.Zeroshot:BAAALgAECgEJAQAAAA==.Zeshom:BAAALgAECgQJBAAAAA==.',
Zp='Zpazzie:BAAALgADCgkJCgAAAA==.',
Zu='Zuluk:BAAALgADCgUJBQAAAA==.',
Zy='Zynblaster:BAAALgADCgQJBAAAAA==.',
['Zö']='Zörö:BAAALgAECgUJBwAAAA==.',
['Ãr']='Ãrx:BAAALgAECgIJAgAAAA==.',
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

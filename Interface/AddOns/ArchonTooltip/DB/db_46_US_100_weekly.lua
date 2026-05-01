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

local lookup = {'Warlock-Demonology','Hunter-BeastMastery','Paladin-Retribution','Paladin-Protection','Hunter-Survival','Shaman-Elemental','Paladin-Holy','Unknown-Unknown','Druid-Guardian','Mage-Frost','DeathKnight-Unholy','DeathKnight-Blood','Evoker-Augmentation','Hunter-Marksmanship','Evoker-Preservation','Warlock-Destruction','Warrior-Fury','Druid-Balance','Druid-Restoration','Priest-Shadow','Rogue-Subtlety','DemonHunter-Havoc','DemonHunter-Devourer','Priest-Holy','Warlock-Affliction','Evoker-Devastation','Shaman-Enhancement','Warrior-Protection','Shaman-Restoration','Monk-Windwalker','Monk-Mistweaver','Monk-Brewmaster','DeathKnight-Frost','DemonHunter-Vengeance','Mage-Fire','Priest-Discipline','Druid-Feral','Rogue-Assassination','Rogue-Outlaw','Warrior-Arms',}
local provider = {region='US',realm='Frostwolf',name='US',type='weekly',zone=46,date='2026-05-01',data={Aa='Aamodar:BAAALgAECgQJCAAAAA==.Aaz:BAAALgAECgEJAQAAAA==.',
Ab='Abadon:BAABLgAECn8hAAIBAAgJKxfmUgDOAQABAAgJKxfmUgDOAQAAAA==.',
Ac='Acidangel:BAAALgADCgcJBwAAAA==.',
Ad='Adalea:BAAALgAECgMJAwAAAA==.Adino:BAABLgAECn8dAAICAAYJRg0SPAAjAQACAAYJRg0SPAAjAQAAAA==.',
Ae='Aeldius:BAAALgAECgEJAQAAAA==.Aeryn:BAACLgAFFH8GAAIDAAMJgR2XGAAXAQADAAMJgR2XGAAXAQAuAAQKfyIAAgMACAnnIvAOABcDAAMACAnnIvAOABcDAAAA.',
Ag='Aggranak:BAAALgAECgYJCQAAAA==.',
Ah='Ahote:BAAALgAECgkJDQAAAA==.Ahtee:BAABLgAECn8dAAMDAAcJ+hwdGQD0AQADAAcJ+hwdGQD0AQAEAAMJpwiwNgBoAAAAAA==.',
Ak='Akroz:BAAALgAECgUJBgAAAA==.Akuprovik:BAAALgAECgMJBAAAAA==.',
Al='Alande:BAAALgADCgMJAwAAAA==.Aldamithas:BAAALgADCgEJAQAAAA==.Alenon:BAAALgADCgMJAwABLgAECggJFwACAJMaAA==.Algodon:BAAALgAECgUJDAAAAA==.Allenduin:BAAALgADCgEJAQAAAA==.Alonias:BAAALgAECgMJBQAAAA==.Alseena:BAABLgAECn8ZAAIDAAUJ/RjBVQAOAQADAAUJ/RjBVQAOAQAAAA==.Alysiita:BAAALgADCgYJBgAAAA==.',
Am='Amadeux:BAABLgAECn8cAAIFAAgJAiCEBwB6AgAFAAgJAiCEBwB6AgAAAA==.Amicae:BAAALgADCgcJCAAAAA==.Ammandor:BAAALgAECgQJBAAAAA==.Amun:BAAALgADCgYJBgAAAA==.',
An='Anceirbe:BAAALgAECgEJAQAAAA==.Andenarras:BAAALgAECgQJCAABLgAECggJFQAGAIMaAA==.Anform:BAAALgAECgIJAgAAAA==.Anryn:BAAALgADCgQJAQABLgAFFAMJBgADAIEdAA==.Anthais:BAAALgAECgEJAQAAAA==.Anvar:BAABLgAECn8XAAICAAgJkxr6DAA2AgACAAgJkxr6DAA2AgAAAA==.',
Ap='Apocalypto:BAAALgADCgMJAwAAAA==.',
Aq='Aquiline:BAAALgADCgYJCQAAAA==.',
Ar='Arastaya:BAAALgADCgcJCgAAAA==.Arathion:BAABLgAECn8mAAIHAAcJpx0aCwAlAgAHAAcJpx0aCwAlAgAAAA==.Archistrate:BAAALgADCgkJEAAAAA==.Artamir:BAAALgADCgMJAwAAAA==.Arx:BAAALgAECgYJCQAAAA==.',
At='Atrumdeus:BAABLgAECn8pAAIDAAgJbhpiGAD5AQADAAgJbhpiGAD5AQAAAA==.',
Au='Audiamer:BAAALgAECgQJBQAAAA==.',
Av='Avindel:BAAALgAECgQJBAAAAA==.',
Aw='Awarmplace:BAAALgADCgYJBgABLgAECgYJDQAIAAAAAA==.Aweyaeh:BAAALgADCgQJBwAAAA==.Awkykit:BAAALgAECgYJEQAAAA==.',
Ay='Ayayron:BAAALgADCgUJBQAAAA==.',
Az='Azymondias:BAAALgADCgEJAgAAAA==.',
Ba='Babushka:BAABLgAECn8VAAIJAAYJVBAIDgDXAAAJAAYJVBAIDgDXAAAAAA==.Babyface:BAAALgAECgUJDQAAAA==.Banddon:BAAALgADCgcJEAAAAA==.Bangerz:BAABLgAECn8UAAIKAAYJyA8QdwDoAAAKAAYJyA8QdwDoAAAAAA==.Bannann:BAAALgADCgIJAgAAAA==.Banned:BAAALgAECgQJBQABLgAFFAIJBQABAC0hAA==.Bariôn:BAAALgAECgQJBwAAAA==.',
Be='Beakk:BAAALgAECgUJCgABLgAFFAUJFQALAAcjAA==.Beaksbigdk:BAACLgAFFH8VAAMLAAUJByNoDAByAQALAAQJByNoDAByAQAMAAEJAACcEQBmAAAuAAQKfyoAAwsACQkPJpwRABIDAAsACQk9JZwRABIDAAwACAn2I2QFAN0BAAAA.Bearach:BAAALgADCgUJBQAAAA==.Beariál:BAABLgAECn8ZAAMLAAgJCxCUSgAfAQALAAgJyg+USgAfAQAMAAcJ6wTpGQCsAAAAAA==.Beedo:BAAALgAECgEJAQAAAA==.Beef:BAAALgAECgYJBgABLgAFFAUJDgANALccAA==.Beeftek:BAAALgADCgEJAQAAAA==.Belfegor:BAAALgAECgQJCAAAAA==.Belldia:BAACLgAFFH8MAAICAAYJlQZMBQBOAQACAAYJlQZMBQBOAQAuAAQKfysAAwIACQn+HpAPAL8CAAIACQn+HpAPAL8CAA4ABQnVDbhRAAUBAAAA.Beni:BAAALgAECgUJCQAAAA==.Beniima:BAAALgAECgYJDwAAAA==.Bennylickz:BAABLgAECn8lAAMPAAkJDxbBBgDWAQAPAAgJgRTBBgDWAQANAAIJjQlwNwB2AAAAAA==.',
Bi='Bibby:BAAALgAECgQJBwAAAA==.Bibi:BAAALgAECgQJBAAAAA==.Birdbear:BAAALgAECgYJBgAAAA==.',
Bl='Blgelk:BAAALgAECgUJBgAAAA==.Blightedmilk:BAAALgADCgUJBQABLgAECggJJAAQAJEdAA==.Blufox:BAAALgAFFAEJAQAAAA==.Blxrry:BAAALgAECgQJBgABLgAFFAIJBQAKANkhAA==.',
Bm='Bmanzero:BAAALgADCgIJAgAAAA==.',
Bo='Bobfresh:BAAALgAECgEJAQABLgAECgUJCQAIAAAAAA==.',
Br='Brainpower:BAAALgAECgYJBgAAAA==.Broherum:BAAALgADCgEJAwAAAA==.Broseidon:BAAALgADCgEJAQAAAA==.Brucella:BAAALgADCgkJFAAAAA==.Bruizin:BAAALgADCgQJBAAAAA==.',
Bu='Buckbeak:BAAALgAECgYJDAAAAA==.Bulgingtotem:BAAALgADCgYJBgAAAA==.Busting:BAAALgAECgYJCwAAAA==.Buttmucker:BAAALgAECgIJAgAAAA==.Buzzliteyear:BAAALgAECgQJBAAAAA==.',
Bw='Bweomysin:BAAALgAFFAIJAgAAAA==.',
By='Byebye:BAAALgAECgcJBgAAAA==.',
['Bà']='Bàhamut:BAAALgADCgMJAwAAAA==.',
['Bå']='Båemax:BAAALgAECgIJBAAAAA==.',
Ca='Caelestos:BAAALgAECgcJDgAAAA==.Castar:BAAALgADCgIJAgAAAA==.',
Cc='Ccwwds:BAAALgADCgMJAwABLgAECgUJCwAIAAAAAA==.',
Ce='Celypzo:BAAALgADCgkJCQAAAA==.Cewkie:BAABLgAECn8cAAIRAAYJSxRXGwBVAQARAAYJSxRXGwBVAQAAAA==.',
Ch='Chaulock:BAAALgAECgcJBwAAAA==.Chausup:BAAALgADCgQJBAABLgAECggJIgADAIskAA==.Chautime:BAABLgAECn8iAAIDAAgJiyTBBwBYAwADAAgJiyTBBwBYAwAAAA==.Cheefillkeef:BAAALgADCgYJDAABLgAECgEJAgAIAAAAAA==.Chialliance:BAABLgAECn8UAAMSAAcJJBHIEwBnAQASAAcJJBHIEwBnAQATAAEJowGg6gAaAAAAAA==.Chizz:BAAALgAECgQJBwABLgAFFAUJEgAJAEMXAA==.Choujisan:BAAALgAECgQJBwABLgAECgkJGAADAP8RAA==.Chrysamere:BAAALgADCgcJDQAAAA==.Chugrar:BAAALgADCgIJAQAAAA==.',
Ci='Citizenwings:BAAALgAECgEJAQAAAA==.',
Cl='Clairebenet:BAABLgAECn8eAAIFAAgJUiF8AwDuAgAFAAgJUiF8AwDuAgAAAA==.Cloft:BAAALgAECgYJBgAAAA==.Clumzylock:BAAALgAECgYJDwABLgAECggJIAAUAFUIAA==.',
Co='Code:BAABLgAECn8dAAIVAAgJtSLFBwAUAwAVAAgJtSLFBwAUAwAAAA==.Consfearacy:BAAALgAECgcJCAAAAA==.Coolynn:BAAALgADCgYJBgAAAA==.Corl:BAABLgAECn8YAAIDAAcJTh4eFwACAgADAAcJTh4eFwACAgAAAA==.Corrl:BAAALgAECgcJDwABLgAECgcJGAADAE4eAA==.',
Cr='Crayzie:BAAALgADCgEJAQAAAA==.Crazyidiot:BAAALgADCgUJBQAAAA==.Creams:BAAALgADCgMJAwABLgADCgQJBAAIAAAAAA==.Creatrix:BAAALgADCgcJBwAAAA==.',
Cs='Csythe:BAAALgAECgYJDQAAAA==.',
Cu='Cuma:BAAALgAECgEJBAAAAA==.Cumb:BAAALgAECgUJCQAAAA==.Curatoria:BAAALgAECgUJBgAAAA==.',
Cw='Cwwddsz:BAAALgAECgEJAQABLgAECgUJCwAIAAAAAA==.',
['Cã']='Cãstanova:BAAALgADCgQJBAAAAA==.',
['Cä']='Cäldius:BAAALgAECgUJBwAAAA==.',
Da='Daioh:BAAALgADCgEJAQAAAA==.Daladin:BAAALgADCgEJAQAAAA==.Damacraze:BAABLgAECn8ZAAICAAgJciC3EAC0AgACAAgJciC3EAC0AgAAAA==.Darkbluerose:BAAALgAECgYJEQAAAA==.Darkevilaeon:BAAALgADCggJCAAAAA==.Darkmelon:BAAALgADCgEJAQAAAA==.Dawigrund:BAAALgAECgYJEAAAAA==.Daxine:BAAALgAECgYJBgAAAA==.',
De='Deadboy:BAAALgADCggJCAAAAA==.Deadroar:BAAALgAECgYJEAAAAA==.Deadwill:BAAALgADCgYJBgAAAA==.Deaminase:BAABLgAECn8XAAIKAAYJ9hhxQQBqAQAKAAYJ9hhxQQBqAQAAAA==.Deathknell:BAAALgADCgQJBAAAAA==.Decypher:BAAALgAECgcJDQAAAA==.Deggle:BAAALgADCgIJAgAAAA==.Delphoxx:BAAALgAECgQJCAAAAA==.Demidru:BAAALgAECgQJBwAAAA==.Demonboar:BAABLgAECn8RAAMWAAcJnRFKDQBoAQAWAAcJnRFKDQBoAQAXAAYJPwSFmwDhAAAAAA==.Demonrocky:BAAALgADCgkJCwAAAA==.Demunic:BAAALgAECggJEgAAAA==.Dennis:BAAALgAECgEJAgAAAA==.Derringer:BAAALgAECgYJBgAAAA==.Destructíon:BAAALgADCgUJBgAAAA==.',
Dh='Dharin:BAAALgAECgEJAQAAAA==.Dhqt:BAAALgADCgQJBAAAAA==.',
Di='Digsy:BAAALgADCgEJAQAAAA==.Dingbangow:BAAALgAECgUJCwAAAA==.Divination:BAAALgADCgYJBgAAAA==.Divinèhero:BAAALgAECgQJBQAAAA==.',
Do='Donki:BAAALgAECgYJBwAAAA==.Donothingwin:BAACLgAFFH8FAAIBAAIJLSHBNwDGAAABAAIJLSHBNwDGAAAuAAQKfyQAAwEACAl7Jt8DAH4DAAEACAl7Jt8DAH4DABAAAwkKJZ0nACUBAAAA.Doomgirl:BAAALgAECgYJBgAAAA==.Doublelift:BAAALgAFFAEJAQAAAA==.',
Dr='Drakblak:BAABLgAECn8hAAIYAAgJQRasDADZAQAYAAgJQRasDADZAQAAAA==.Draukarí:BAABLgAECn8eAAQZAAgJniFTAQDlAgAZAAgJhR9TAQDlAgABAAcJYRzqKABtAgAQAAEJiB+yXwBPAAAAAA==.Drayer:BAABLgAECn8dAAIHAAgJnxCUFgCcAQAHAAgJnxCUFgCcAQAAAA==.Dripped:BAAALgADCgcJBwAAAA==.Droni:BAABLgAECn8TAAIXAAYJDR0FHQCFAQAXAAYJDR0FHQCFAQAAAA==.Drunkenmist:BAAALgAECgYJEQAAAA==.Drunkle:BAAALgADCgUJBQAAAA==.Dröbi:BAACLgAFFH8JAAINAAQJoh3hBwB3AQANAAQJoh3hBwB3AQAuAAQKfykAAw0ACQlhIrACAL0CAA0ACQlhIrACAL0CABoABgkIFVMaAGEBAAAA.',
Du='Dundundun:BAAALgAECgcJCAAAAA==.Duroklu:BAAALgAECgUJCAAAAA==.Durortar:BAABLgAECn8YAAMCAAgJ9wjLJgB9AQACAAgJ9wjLJgB9AQAOAAEJrwDGmwAQAAAAAA==.Durrok:BAAALgAECgEJAQAAAA==.',
Dy='Dynastes:BAAALgADCgQJAQABLgAFFAUJFQALAAcjAA==.Dyne:BAAALgADCgEJAQAAAA==.',
['Dê']='Dêdícatíón:BAAALgAECgYJDQAAAA==.',
['Dö']='Dödsriddare:BAAALgADCgYJBgAAAA==.',
Ea='Eazy:BAACLgAFFH8MAAMCAAQJdhIHEQA0AQAOAAQJKhKNDwA2AQACAAQJxggHEQA0AQAuAAQKfyQAAw4ACAncI7wHAB8DAA4ACAncI7wHAB8DAAIAAgkxFutmAJEAAAAA.',
Eg='Eggdrop:BAABLgAECn8aAAIRAAcJIh9aJwAhAgARAAcJIh9aJwAhAgAAAA==.',
Eh='Ehgu:BAABLgAECn8qAAIbAAkJGBoaAQCsAgAbAAkJGBoaAQCsAgAAAA==.',
El='Eleverclear:BAABLgAECn8VAAIHAAcJkROrPgB+AQAHAAcJkROrPgB+AQAAAA==.Elfbloodbane:BAAALgADCggJCAAAAA==.Eliizabeth:BAAALgAECgUJCAAAAA==.',
Em='Emidget:BAAALgAECgQJBQAAAA==.',
Ep='Epicorc:BAAALgADCgEJAQAAAA==.',
Er='Erhmer:BAAALgAECggJBgAAAA==.Erra:BAAALgAECgQJBQAAAA==.',
Et='Ethersong:BAAALgADCgcJCwAAAA==.',
Ev='Everlight:BAAALgADCgcJBwAAAA==.Evjoker:BAAALgAECgUJCAAAAA==.',
Ex='Exodes:BAAALgAECgYJEAAAAA==.',
Fa='Fabermor:BAAALgAECgEJAQAAAA==.Fairygon:BAAALgAECgUJBQAAAA==.Fairyhunter:BAAALgAECgEJAQAAAA==.Fairymonk:BAAALgAECgUJCgAAAA==.Fariona:BAAALgADCgEJAQAAAA==.Fartbarf:BAABLgAECn8kAAIBAAgJcRJ3VADKAQABAAgJcRJ3VADKAQAAAA==.Fascharrawm:BAAALgADCgEJAwAAAA==.Faya:BAAALgADCgUJBQABLgAECggJFwACAJMaAA==.',
Fe='Fennicuss:BAAALgAECgEJAQAAAA==.Ferdalight:BAAALgAECgQJCAAAAA==.Festinu:BAAALgADCgQJBQAAAA==.',
Fi='Fistake:BAAALgAECgcJEgAAAA==.Fistalicious:BAAALgAECgMJAwABLgAFFAYJFQAcAN0lAA==.Fitshaced:BAAALgADCgMJAwAAAA==.',
Fl='Flandia:BAAALgAECgIJBAAAAA==.Flintanyl:BAAALgADCgUJCQAAAA==.',
Fo='Forduecezero:BAAALgAECgYJDgAAAA==.',
Fr='Fricher:BAABLgAECn8aAAILAAcJUxBTMgBwAQALAAcJUxBTMgBwAQAAAA==.Fridgecig:BAAALgADCgcJBwAAAA==.Frostbringer:BAAALgADCgcJEwAAAA==.Frostworn:BAAALgADCgYJBgAAAA==.Frostybetch:BAAALgAECgcJCwAAAA==.Frozenwithin:BAAALgAECgMJAwAAAA==.Froznbolt:BAAALgADCgcJBwAAAA==.Froznlight:BAABLgAECn8YAAIDAAcJ+RwIMwBWAgADAAcJ+RwIMwBWAgAAAA==.Fruitsnacks:BAAALgAECgYJBgABLgAFFAYJGAAMAAAaAA==.Fränk:BAAALgADCgcJDwAAAA==.Frío:BAAALgAECgQJBQAAAA==.Frõst:BAAALgADCgMJAwAAAA==.',
Fu='Fusio:BAAALgADCgMJAwAAAA==.',
Fy='Fylerian:BAACLgAFFH8YAAISAAYJuR4fAQDuAQASAAYJuR4fAQDuAQAuAAQKfx0AAhIACQkwJHoCAJcDABIACQkwJHoCAJcDAAAA.Fylerianmage:BAABLgAECn8XAAIKAAYJMiDslwClAQAKAAYJMiDslwClAQABLgAFFAYJGAASALkeAA==.Fylerianprie:BAAALgAECgUJCgABLgAFFAYJGAASALkeAA==.Fyrebane:BAAALgAECgUJBQAAAA==.',
Ga='Galaxygas:BAAALgAECgYJDQAAAA==.Ganjja:BAAALgAECgEJAQAAAA==.Gardrath:BAAALgAECgcJDQAAAA==.Gargalon:BAAALgAECgUJBQAAAA==.Gatør:BAAALgAECgcJEwAAAA==.',
Ge='Gether:BAAALgADCgcJDAAAAA==.Getter:BAABLgAECn8WAAIJAAcJWxwVCQAVAgAJAAcJWxwVCQAVAgAAAA==.',
Gh='Ghettomike:BAAALgAECgcJCwAAAA==.',
Gi='Gilga:BAAALgAECgYJCgAAAA==.Giny:BAABLgAECn8aAAIGAAcJUhPdFQBnAQAGAAcJUhPdFQBnAQAAAA==.',
Gl='Glandros:BAAALgADCgMJAwAAAA==.Glorin:BAAALgAECgYJDAAAAA==.',
Go='Gobbledeez:BAAALgAECgcJCwAAAA==.Gojojo:BAABLgAECn8kAAIRAAgJ2xtGEwC0AgARAAgJ2xtGEwC0AgAAAA==.Gorfrunch:BAAALgAECgUJCQAAAA==.Gorro:BAAALgAECgIJAwAAAA==.Govinniuur:BAABLgAECn8cAAIMAAcJyg1kEQAEAQAMAAcJyg1kEQAEAQAAAA==.',
Gr='Grandcodex:BAAALgADCgcJBwABLgAECggJHQALABQQAA==.Granips:BAAALgADCgIJAQAAAA==.Gravelord:BAAALgADCgEJAQAAAA==.Grawnita:BAABLgAECn8iAAIKAAgJ1CLiEwAxAwAKAAgJ1CLiEwAxAwAAAA==.Grizzy:BAAALgAECgUJBgAAAA==.Grohan:BAAALgADCgEJAQAAAA==.Groundscore:BAAALgADCgUJBQABLgADCgUJBQAIAAAAAA==.',
Gu='Gundam:BAAALgAECggJCQABLgAFFAUJEQAKAMEfAA==.Gunde:BAAALgADCgQJAwAAAA==.',
Gw='Gweilo:BAAALgADCgQJBAAAAA==.Gwendilyn:BAAALgAECgYJBgAAAA==.Gwydionatlan:BAAALgADCgEJAQAAAA==.',
Gy='Gyndrinolara:BAABLgAECn8WAAICAAcJ4w8sLQBdAQACAAcJ4w8sLQBdAQAAAA==.',
Ha='Hafadude:BAAALgAECgkJBwAAAA==.Hakouh:BAAALgAECgYJBwAAAA==.Harambabe:BAAALgAECgYJBgAAAA==.Hatereading:BAAALgADCgcJCAAAAA==.',
He='Headhuntér:BAAALgAECgUJBgAAAA==.Healdnbloody:BAAALgAECgIJAgAAAA==.Healgoßyeßye:BAAALgAECgEJAgAAAA==.Heckitwebawl:BAAALgADCgEJAQABLgAECgkJJQAPAA8WAA==.Hehatesme:BAAALgADCgcJBwAAAA==.Hellface:BAAALgADCgcJDAABLgAFFAEJAQAIAAAAAA==.Hellokrittyz:BAAALgADCgcJBwAAAA==.Hephaestis:BAAALgADCgUJBQAAAA==.',
Hi='Hiimmas:BAAALgAECgkJAgABLgAFFAQJDAAbAEYhAA==.Hikiru:BAAALgAECgkJCAAAAA==.',
Ho='Holysh:BAAALgADCgYJBgAAAA==.Holywater:BAABLgAECn8wAAIEAAgJCSG+AQCPAgAEAAgJCSG+AQCPAgAAAA==.Hoon:BAAALgADCgkJCQAAAA==.Hoonish:BAABLgAECn8WAAMBAAYJ9R5oQQAJAgABAAYJ9R5oQQAJAgAQAAIJtxbmUgB1AAAAAA==.Horick:BAAALgAECgEJAQAAAA==.',
Hr='Hruaka:BAAALgAECgMJAwAAAA==.',
Hy='Hyperiann:BAAALgADCgEJAQAAAA==.',
Ia='Iamstronge:BAAALgADCgMJAwAAAA==.',
Ic='Iceyrot:BAAALgAECgYJBgAAAA==.',
Il='Illuminax:BAAALgAECgUJCAAAAA==.Illydan:BAAALgAECgIJAwABLgAFFAEJAQAIAAAAAA==.',
Im='Immahotmess:BAAALgAECgEJAQAAAA==.',
In='Inamorta:BAAALgAECgcJDAAAAA==.Ineedbowjob:BAAALgAECgYJCgAAAA==.Intothedark:BAAALgAECgIJAwAAAA==.Intotherain:BAAALgADCgIJAwAAAA==.Inya:BAAALgAECgMJBwAAAA==.Inyomouf:BAAALgAECgEJAQAAAA==.',
Io='Iomadae:BAABLgAECn8ZAAIDAAgJxyCQFwDbAgADAAgJxyCQFwDbAgAAAA==.',
Ir='Ironjaws:BAAALgAECgQJCwAAAA==.',
Is='Isaacnewton:BAABLgAECn8fAAIRAAYJhx5JEAC5AQARAAYJhx5JEAC5AQAAAA==.',
It='Ithoril:BAAALgADCgcJCwAAAA==.Itsdone:BAABLgAECn8qAAMBAAgJHhO/KQCGAQABAAgJCBK/KQCGAQAQAAMJRxRrFAB5AAABLgAFFAEJAQAIAAAAAA==.',
Iv='Iveliz:BAAALgAECgcJEgAAAA==.',
Iz='Izheals:BAAALgADCgEJAQABLgAECggJHgANADoPAA==.',
Ja='Jackk:BAACLgAFFH8IAAIHAAQJZBzrDgARAQAHAAQJZBzrDgARAQAuAAQKfykAAgcACAklIUEIAOoCAAcACAklIUEIAOoCAAAA.Jackks:BAAALgAECgEJAQABLgAFFAQJCAAHAGQcAA==.Jaeger:BAABLgAECn8ZAAIFAAgJjhl3CABiAgAFAAgJjhl3CABiAgAAAA==.Janzan:BAABLgAECn8UAAIdAAYJZxPoIgBQAQAdAAYJZxPoIgBQAQAAAA==.Jasmonk:BAABLgAECn8eAAIeAAcJZAh7GAAkAQAeAAcJZAh7GAAkAQAAAA==.Jayren:BAAALgAECgIJAgAAAA==.',
Je='Jenniekim:BAABLgAECn8XAAIXAAcJuA2zSQDJAAAXAAcJuA2zSQDJAAAAAA==.',
Ji='Jinkz:BAAALgAECgEJAQAAAA==.',
Jo='Josephsmith:BAAALgAECgkJAwAAAA==.',
Ju='Judgevis:BAAALgAECggJEQAAAA==.Jumbles:BAAALgAECgYJBgAAAA==.Justeene:BAAALgAECgYJBgABLgAECgQJBQAIAAAAAA==.',
Jv='Jvedo:BAAALgADCgYJBQAAAA==.',
['Jø']='Jøshu:BAAALgAECgEJAQAAAA==.',
Ka='Kabalester:BAAALgAECgIJAgAAAA==.Kaello:BAAALgAECgEJAQABLgAECgYJCwAIAAAAAA==.Kaerigyn:BAAALgAECgYJCwAAAA==.Karrona:BAAALgADCgcJEgAAAA==.Katirinu:BAAALgADCgMJAwAAAA==.Kawliga:BAAALgADCgkJDwAAAA==.Kazuu:BAAALgADCgEJBgAAAA==.',
Ke='Keepup:BAAALgAECgYJCwABLgAFFAIJBQABAC0hAA==.Keg:BAAALgAFFAEJAgABLgAFFAYJGAAMAAAaAA==.Keheo:BAAALgADCgMJAwAAAA==.Keimei:BAAALgADCgMJAwABLgAECgYJFgAdABkbAA==.Keladun:BAAALgAECgUJCwAAAA==.',
Kh='Khaho:BAAALgAECggJEQAAAA==.Khonan:BAABLgAECn8XAAQeAAYJUBeENwBAAQAeAAUJ9BSENwBAAQAfAAYJtQ6HNAAfAQAgAAEJsQPrlgAeAAABLgAFFAUJDAAKADsYAA==.',
Ki='Kiamar:BAAALgAECggJDgAAAA==.Kijyo:BAAALgAECgYJEQAAAA==.Kishu:BAAALgADCggJDQAAAA==.Kitz:BAAALgADCgEJAQAAAA==.',
Kn='Knutebomb:BAAALgADCgEJAQAAAA==.',
Ko='Koinzell:BAAALgADCgEJAgAAAA==.Kojirin:BAAALgADCgYJBwAAAA==.Kordarg:BAAALgAECgUJBQAAAA==.',
Kr='Krex:BAAALgADCgYJDQAAAA==.Krossedup:BAAALgADCgcJDgAAAA==.Kryptonikk:BAAALgAECgIJAwAAAA==.Krystal:BAAALgAECgMJBgAAAA==.Kröw:BAABLgAECn8bAAIbAAgJ7Q5aBgClAQAbAAgJ7Q5aBgClAQAAAA==.',
Ku='Kudrix:BAABLgAECn8bAAIeAAcJWx+QBgAjAgAeAAcJWx+QBgAjAgAAAA==.Kurgaz:BAAALgADCgMJBAAAAA==.Kurø:BAABLgAECn8gAAILAAgJJR69FAAUAgALAAgJJR69FAAUAgAAAA==.',
Kw='Kwanzie:BAAALgAECgMJAwAAAA==.',
Ky='Kyoco:BAAALgADCgEJAQAAAA==.Kyprolis:BAAALgADCgYJBgAAAA==.Kyushi:BAAALgAECgYJEQAAAA==.',
['Kà']='Kàri:BAABLgAECn8VAAITAAgJyxl4CwBRAgATAAgJyxl4CwBRAgAAAA==.',
['Kä']='Käva:BAAALgAECgEJAQAAAA==.',
['Kï']='Kïngston:BAEALgAECgYJDwAAAA==.',
La='Lamorakk:BAAALgAECgEJAQAAAA==.Lany:BAABLgAECn8YAAMLAAcJ6BSSaAC8AQALAAcJDhSSaAC8AQAhAAMJtxFdFQA/AAAAAA==.Latherfanta:BAAALgAECgUJCgAAAA==.Laurijaydn:BAAALgAECgcJBgAAAA==.',
Le='Lelink:BAAALgAECgYJDAAAAA==.Lemywinx:BAAALgAECgEJAQAAAA==.Leoden:BAAALgADCgUJBAAAAA==.Leopard:BAAALgAECgkJBwAAAA==.Lepra:BAAALgADCgUJBgAAAA==.Leslieknope:BAAALgADCgIJAgAAAA==.',
Li='Lichbabies:BAAALgADCgMJAwAAAA==.Lielys:BAAALgAECgUJEQABLgAECgYJCQAIAAAAAA==.Lightlana:BAACLgAFFH8JAAIDAAQJww57EQBAAQADAAQJww57EQBAAQAuAAQKfxwAAgMACAm5IdIYANQCAAMACAm5IdIYANQCAAAA.Lightwalker:BAAALgAECgUJBQAAAA==.Likeaglove:BAAALgAECgYJBgABLgAFFAEJAQAIAAAAAA==.Linfang:BAAALgADCgYJBgAAAA==.Littlestarz:BAABLgAECn8bAAMdAAcJ7x6GCABiAgAdAAcJ7x6GCABiAgAGAAMJ5QpJbgCKAAAAAA==.Lizzieag:BAEBLgAECn8kAAIRAAgJLBgDIgBEAgARAAgJLBgDIgBEAgAAAA==.',
Ll='Lluvia:BAAALgAECgQJBwAAAA==.',
Lo='Loafsies:BAAALgADCgMJAwAAAA==.Loenil:BAAALgAECgcJEwAAAA==.Lohueng:BAAALgAECgEJAQAAAA==.Loodah:BAAALgAECgIJAgAAAA==.Lookee:BAAALgAECgUJBQAAAA==.Loranoth:BAAALgADCgUJDAAAAA==.Loreel:BAAALgAECgUJBQAAAA==.Loudnoise:BAAALgADCgYJBgAAAA==.',
Lu='Lucielle:BAAALgAECgYJCgAAAA==.Luke:BAAALgAECgIJAgAAAA==.Luminali:BAAALgADCggJCgAAAA==.Lunareva:BAABLgAECn8eAAITAAcJ5iKQBgCtAgATAAcJ5iKQBgCtAgAAAA==.Lunä:BAAALgAECgYJCgABLgAFFAYJDAACAJUGAA==.',
Ly='Lyxon:BAAALgAECgQJDAAAAA==.',
['Lå']='Låw:BAAALgAECgIJAgAAAA==.',
Ma='Maandos:BAAALgADCgcJBwAAAA==.Mabrian:BAAALgADCgcJBwAAAA==.Mafoôza:BAABLgAECn8eAAIRAAgJAyHaBAByAgARAAgJAyHaBAByAgAAAA==.Magicalama:BAAALgADCgYJCwABLgAECggJHAAFAAIgAA==.Magicnugz:BAAALgADCgEJAQAAAA==.Magnanimity:BAEALgADCgEJAQABLgAECgYJFQACANQSAA==.Magpen:BAAALgADCgMJBgAAAA==.Mahboyblu:BAAALgAECgMJAwAAAA==.Mahndoo:BAABLgAECn8fAAIKAAgJkBrfFQAtAgAKAAgJkBrfFQAtAgAAAA==.Makto:BAAALgADCgUJCAAAAA==.Malia:BAAALgADCgUJBQAAAA==.Maliciouso:BAABLgAECn8WAAIdAAYJGRuEFgCzAQAdAAYJGRuEFgCzAQAAAA==.Malédiction:BAABLgAECn8ZAAIKAAgJ6RXWdwDiAQAKAAgJ6RXWdwDiAQAAAA==.Mattdemøn:BAAALgADCgEJAQABLgAECggJFwACAFkWAA==.Matua:BAAALgADCgEJAQAAAA==.Maymae:BAAALgAECgMJAwAAAA==.',
Me='Medizine:BAAALgAECgEJAQAAAA==.Meepz:BAAALgAECgEJAQAAAA==.Megabonk:BAAALgAECgQJBQABLgAECggJJAARANsbAA==.Megademac:BAABLgAECn8SAAIXAAUJLg/HiwALAQAXAAUJLg/HiwALAQAAAA==.Meowenstein:BAAALgAECgMJBgAAAA==.',
Mi='Miistral:BAAALgAECgYJEwAAAA==.Miniblinks:BAAALgADCgQJBAAAAA==.Minisid:BAAALgAFFAEJAQAAAA==.Miriia:BAAALgAECgEJAgAAAA==.Mirshta:BAAALgADCggJEQAAAA==.Missmaam:BAABLgAECn8aAAIiAAcJhx/6AwDBAQAiAAcJhx/6AwDBAQABLgAFFAEJAQAIAAAAAA==.Mistinmae:BAAALgAECgEJAgABLgAECgYJEQAIAAAAAA==.Mistrjenkins:BAAALgAECgEJAQAAAA==.Mixoz:BAAALgAECgQJBAAAAA==.',
Mo='Moistooltip:BAAALgADCgYJCwABLgAECgYJEQAIAAAAAA==.Mokotrize:BAABLgAECn8cAAIEAAYJohhfCwBMAQAEAAYJohhfCwBMAQAAAA==.Monarch:BAAALgADCgEJAQAAAA==.Mookate:BAABLgAECn8oAAISAAgJrhtqEACdAgASAAgJrhtqEACdAgAAAA==.Moonblade:BAAALgADCgMJAwAAAA==.Mootylicious:BAAALgAECgEJAQABLgAECggJFwACAFkWAA==.Mordred:BAAALgAECgUJCQAAAA==.',
Ms='Msfirefly:BAAALgAECgYJCQAAAA==.',
Mu='Mud:BAAALgADCgMJAwAAAA==.Munchies:BAAALgAECgQJBAAAAA==.Murlooze:BAAALgADCgYJBgAAAA==.Muwunfire:BAAALgADCgcJBwAAAA==.',
My='Myrolan:BAAALgAECgcJCQABLgAECgcJCwAIAAAAAA==.Myrolee:BAAALgAECgcJCwAAAA==.Myrowrynn:BAAALgAECgYJBgABLgAECgcJCwAIAAAAAA==.Myrozond:BAAALgAECgYJDwABLgAECgcJCwAIAAAAAA==.',
['Má']='Mánú:BAAALgAECgYJDQABLgAECgcJGAADAGcjAA==.',
['Mä']='Mänu:BAABLgAECn8YAAIDAAcJZyNOGQDRAgADAAcJZyNOGQDRAgAAAA==.',
['Mø']='Mønstrøsity:BAAALgAECgEJAQAAAA==.',
Na='Naiyah:BAAALgAFFAEJAQAAAA==.Namelesskin:BAAALgAECgQJBAAAAA==.Nanoko:BAABLgAECn8jAAIeAAgJxCOWAwCEAgAeAAgJxCOWAwCEAgAAAA==.Nayasylpha:BAABLgAECn8mAAIgAAgJxhzzDwCdAgAgAAgJxhzzDwCdAgAAAA==.Nazara:BAAALgADCgYJBgAAAA==.',
Ne='Neekage:BAAALgADCgEJAQAAAA==.Neown:BAAALgAECgEJAgABLgAECggJJgATAMAdAA==.Nephertiti:BAAALgADCgYJCgAAAA==.Neuro:BAABLgAECn8mAAIKAAgJ8SITEABdAgAKAAgJ8SITEABdAgAAAA==.Newxexhu:BAAALgAECgQJBAAAAA==.',
Ni='Nicolico:BAAALgADCgcJBwAAAA==.Nictamom:BAAALgAECgEJAQAAAA==.Nirri:BAAALgAECgYJBwAAAA==.Nishendra:BAABLgAECn8aAAIPAAkJix3/BgDQAgAPAAkJix3/BgDQAgAAAA==.Nitama:BAAALgADCgYJBwAAAA==.Nitefall:BAABLgAECn8VAAMCAAcJkQ7BKwBkAQACAAcJkQ7BKwBkAQAFAAMJKgPfJwBYAAAAAA==.',
No='Noblok:BAAALgAECgMJAwAAAA==.Nocando:BAAALgAFFAEJAQAAAA==.Nofeetpicsyo:BAABLgAECn8gAAIUAAgJVQhDGQA0AQAUAAgJVQhDGQA0AQAAAA==.Nootella:BAABLgAECn8UAAIHAAYJlSIoHgAlAgAHAAYJlSIoHgAlAgAAAA==.Norgoma:BAAALgAECgYJDwAAAA==.Normmarry:BAAALgAECgYJEAAAAA==.Notybynature:BAAALgADCgIJAgAAAA==.',
Nu='Nuriel:BAABLgAECn8XAAIUAAcJLhkNGwAGAgAUAAcJLhkNGwAGAgAAAA==.',
Ny='Nylinu:BAAALgADCgQJBAABLgAECggJJAAQAJEdAA==.Nylinuya:BAAALgAECgYJDAABLgAECggJJAAQAJEdAA==.Nyteskye:BAAALgAECgEJAQAAAA==.Nyxoblivion:BAAALgADCgcJEQAAAA==.',
['Nî']='Nîco:BAABLgAECn8mAAITAAgJwB3zGABwAgATAAgJwB3zGABwAgAAAA==.',
Ob='Obsydia:BAAALgADCgcJDQAAAA==.',
Oc='Octin:BAABLgAECn8fAAMgAAgJMQ5lOABoAQAgAAgJ3Q1lOABoAQAeAAEJWBW+eAA5AAAAAA==.',
Ok='Okowilly:BAAALgADCgcJCgAAAA==.',
Ol='Oline:BAABLgAECn8iAAIBAAgJ/hbkIACwAQABAAgJ/hbkIACwAQAAAA==.',
Om='Ommnom:BAAALgAECgQJBAABLgAECgkJJQAPAA8WAA==.',
On='Oneall:BAABLgAECn8hAAISAAgJqhPoDgCiAQASAAgJqhPoDgCiAQAAAA==.Onehit:BAAALgAECgIJBAAAAA==.Onlyspells:BAABLgAECn8WAAMKAAgJYwmupwCKAQAKAAgJYwmupwCKAQAjAAEJnAEMEgAgAAAAAA==.',
Oo='Oomcrit:BAAALgAECgUJCQAAAA==.Oonaki:BAABLgAECn8jAAIMAAgJoxiOEwDVAQAMAAgJoxiOEwDVAQAAAA==.',
Or='Oreoz:BAAALgADCgUJBQAAAA==.',
Ot='Othin:BAABLgAECn8UAAITAAgJ4xpwCQB0AgATAAgJ4xpwCQB0AgAAAA==.',
Pa='Painloa:BAABLgAECn8XAAMhAAcJrwbYBgAQAQAhAAcJrwbYBgAQAQALAAYJZwFU7wCfAAAAAA==.Pam:BAAALgADCgYJCgAAAA==.Panacéa:BAABLgAECn8cAAIkAAkJ5A7eHACuAQAkAAkJ5A7eHACuAQAAAA==.Pandadance:BAAALgAECgcJEwAAAA==.Pandakill:BAAALgAECgUJBgAAAA==.Pandanimal:BAAALgAECgEJAgAAAA==.Pandar:BAAALgAECgQJBAAAAA==.Pandrael:BAAALgADCgMJAwAAAA==.Paotah:BAAALgAECgEJAQAAAA==.Papaganu:BAAALgADCgYJCQABLgAECgYJCwAIAAAAAA==.Papagenu:BAAALgAECgYJBgABLgAECgYJCwAIAAAAAA==.Papsfear:BAAALgADCgQJBAAAAA==.Paradoxx:BAABLgAECn8pAAIKAAgJcyNCBwDEAgAKAAgJcyNCBwDEAgAAAA==.',
Pe='Petrogris:BAAALgADCgUJBQAAAA==.',
Ph='Phelefica:BAAALgAECgUJBwAAAA==.',
Pm='Pmac:BAAALgAECgQJBQABLgAECgUJEgAXAC4PAA==.',
Po='Poggie:BAAALgAECgQJBQAAAA==.Pointybrows:BAAALgAECgEJAgAAAA==.Poppé:BAAALgAECgMJAwAAAA==.Porkfu:BAAALgADCgQJBAAAAA==.Potroaster:BAAALgAECgEJAQAAAA==.Powerflower:BAAALgADCgYJBwAAAA==.',
Pr='Professorson:BAAALgADCgEJAQAAAA==.Proteinbar:BAAALgADCgQJBAABLgAECgEJAgAIAAAAAA==.',
Pu='Punishment:BAAALgADCgQJBwAAAA==.Putresca:BAAALgADCgkJCQAAAA==.',
Py='Pyroheart:BAABLgAECn8VAAMQAAYJLyDWAwCqAQAQAAYJLyDWAwCqAQABAAIJMwuXBQFRAAAAAA==.',
Qa='Qai:BAABLgAECn8dAAMlAAcJXhCZFwBEAQAlAAUJ6xaZFwBEAQAJAAcJtAVyHgCtAAAAAA==.',
Qu='Quelestraza:BAAALgAECgYJEgAAAA==.',
Ra='Raewyck:BAABLgAECn8iAAICAAgJ3xS5LQD8AQACAAgJ3xS5LQD8AQAAAA==.Ragar:BAAALgAECgUJBQABLgAFFAMJBwARAG4ZAA==.Raginbull:BAABLgAECn8XAAIcAAYJlROkEQAMAQAcAAYJlROkEQAMAQAAAA==.Ragingmaze:BAAALgAECgcJEQAAAA==.Rainburrow:BAAALgAECgQJBAAAAA==.Raptormortis:BAABLgAECn8dAAMGAAcJKRlUIAANAgAGAAcJKRlUIAANAgAdAAYJ4xOoHwBnAQAAAA==.Raskolnikòv:BAAALgADCgQJBAABLgAECgcJDgAIAAAAAA==.Raskolniköv:BAAALgAECgcJDgAAAA==.Raskolnikøv:BAAALgADCgcJBgABLgAECgcJDgAIAAAAAA==.Rawd:BAAALgADCgIJAgAAAA==.Rayjin:BAAALgAECgYJBgABLgAECgcJDgAIAAAAAA==.Raylen:BAAALgAECgYJBgAAAA==.',
Re='Reckz:BAAALgADCgQJCAAAAA==.Regarr:BAAALgADCgEJAQABLgADCgYJBgAIAAAAAA==.Reinitia:BAAALgAECgIJAgAAAA==.Rellic:BAAALgADCgcJBwAAAA==.Remy:BAAALgAECgEJAgAAAA==.Renkagisa:BAAALgADCgcJBwAAAA==.Renku:BAAALgAECgQJEgAAAA==.Retana:BAAALgAECgQJBQAAAA==.',
Rh='Rhinn:BAAALgAECgQJCAAAAA==.Rhythm:BAAALgAECgYJBgAAAA==.',
Ri='Rickypeepee:BAAALgAECgQJBQAAAA==.Ritsuyi:BAAALgADCgYJBgABLgAECgMJAwAIAAAAAA==.',
Ro='Roarbear:BAAALgAECgYJBgAAAA==.Roastedz:BAAALgAECgYJDAAAAA==.Rolánd:BAAALgADCgkJCQAAAA==.Roomi:BAABLgAECn8mAAIbAAkJJxUeAgBdAgAbAAkJJxUeAgBdAgAAAA==.Roowar:BAAALgAECgEJAQABLgAECggJJgAVAKcfAA==.Rorthu:BAAALgAECgYJBgAAAA==.Roru:BAAALgAECgYJDQAAAA==.Rozie:BAAALgAECgQJBAAAAA==.',
Ru='Rukélie:BAAALgAECgYJBgAAAA==.',
Ry='Ry:BAAALgAECgkJDwAAAA==.Ryanna:BAAALgAECgMJAwAAAA==.Rygon:BAAALgADCgMJAwAAAA==.Rymax:BAAALgADCgkJCQAAAA==.Ryy:BAAALgAECgYJBwAAAA==.',
['Ræ']='Rædiêncë:BAAALgAECgYJDQAAAA==.',
['Rò']='Ròó:BAABLgAECn8mAAQVAAgJpx/pCAACAwAVAAgJhx/pCAACAwAmAAMJLB59FAC1AAAnAAIJiiPhCgBnAAAAAA==.',
Sa='Saevio:BAABLgAECn8YAAILAAYJiRdvNABnAQALAAYJiRdvNABnAQAAAA==.Sallean:BAAALgAECgEJAQAAAA==.Sanlorastik:BAAALgAECgEJAQAAAA==.Saoikingston:BAEALgAECgYJBQABLgAECgYJDwAIAAAAAA==.Sarayu:BAAALgADCgcJDQAAAA==.Sashimi:BAABLgAECn8gAAMLAAgJARlSQgAwAgALAAgJARlSQgAwAgAhAAQJgRFHCQDFAAAAAA==.Sassyjay:BAAALgAECgcJBgAAAA==.Sassyuwu:BAACLgAFFH8FAAIHAAMJ/hUGDgD3AAAHAAMJ/hUGDgD3AAAuAAQKfxcAAgcACAnGJWQEACcDAAcACAnGJWQEACcDAAAA.',
Sc='Scarlet:BAAALgADCgEJAQAAAA==.Schbag:BAAALgAECgMJAwAAAA==.Scotchnsoda:BAACLgAFFH8KAAMYAAMJ/gdkCgC/AAAYAAMJ/gdkCgC/AAAkAAEJJQOYIAA+AAAuAAQKfx8AAxgACAl1EnUpAKYBABgACAl1EnUpAKYBABQAAQlyAMtrABoAAAAA.Scrives:BAAALgAECgYJDAAAAA==.Scrubiclese:BAAALgAECgQJBAAAAA==.',
Se='Seldaren:BAAALgAECgQJBwAAAA==.Selenegosa:BAABLgAECn8eAAMaAAcJ9BX4BABpAQAaAAYJCRf4BABpAQANAAUJjQ+cLQCwAAABLgAECggJIQACAKofAA==.Seran:BAAALgAECgYJEAAAAA==.Serenade:BAABLgAECn8hAAISAAgJ2A10FABgAQASAAgJ2A10FABgAQAAAA==.Severyne:BAABLgAECn8oAAITAAgJISUXBQA8AwATAAgJISUXBQA8AwAAAA==.',
Sh='Shadowchad:BAAALgADCgUJCQAAAA==.Shadowmeld:BAAALgAECgYJBwAAAA==.Shadyhealer:BAAALgAECgEJAQAAAA==.Shaile:BAAALgAECgIJAgAAAA==.Shamanu:BAAALgAECgcJEQABLgAECgcJGAADAGcjAA==.Shamsel:BAABLgAECn8VAAIUAAYJeAnyJADUAAAUAAYJeAnyJADUAAAAAA==.Shaunpj:BAAALgAECgMJBAAAAA==.Shermlock:BAAALgAECgIJAgAAAA==.Shiftychiz:BAACLgAFFH8SAAIJAAUJQxd6AgAkAQAJAAUJQxd6AgAkAQAuAAQKfyUAAgkACQnwIEMCABEDAAkACQnwIEMCABEDAAAA.Shinpaku:BAAALgADCgIJAgAAAA==.Shiéld:BAAALgAECgcJEAAAAA==.Shobogenzo:BAAALgADCgMJAwAAAA==.Shockcaller:BAAALgAECgQJCgAAAA==.Shorin:BAAALgADCgYJCQAAAA==.Showtooltip:BAAALgAECgYJEQAAAA==.Shulla:BAABLgAECn8jAAITAAgJsCQGBABQAwATAAgJsCQGBABQAwAAAA==.Shweatyballs:BAABLgAECn8XAAIKAAYJWhssQwBlAQAKAAYJWhssQwBlAQAAAA==.',
Si='Sidetrax:BAAALgADCgQJBAAAAA==.Silran:BAAALgAECgYJEAAAAA==.Silverwings:BAAALgADCgEJAQAAAA==.Simmara:BAABLgAECn8YAAMCAAcJ+g/kRgCWAQACAAcJ+g/kRgCWAQAFAAQJggSFJACmAAAAAA==.Sinner:BAECLgAFFH8PAAIYAAYJ6RD7AgCJAQAYAAYJ6RD7AgCJAQAuAAQKfxoAAxgACQkYHdUHAM4CABgACQkYHdUHAM4CABQAAwnuAw5ZAFcAAAAA.Sinrael:BAAALgADCgkJCQAAAA==.',
Sk='Skaboodle:BAAALgAECgQJBAABLgAFFAYJFQAcAN0lAA==.Skruff:BAAALgAECgIJAwAAAA==.',
Sl='Slamuraijack:BAAALgAECgUJAgAAAA==.Slayngin:BAAALgAECgQJCAABLgAECgUJCAAIAAAAAA==.Sleepydeputy:BAAALgAECgUJBwAAAA==.Sleetwoodmac:BAAALgAECgIJAgAAAA==.',
Sm='Smeggsbenny:BAAALgADCgQJBAABLgADCgYJBgAIAAAAAA==.',
So='Solaris:BAAALgADCgcJCwAAAA==.Solstica:BAAALgAECgIJAgAAAA==.Sora:BAAALgAECgEJAQAAAA==.',
Sp='Sparklemeow:BAAALgADCgEJAQAAAA==.Spiritualone:BAABLgAECn8XAAIEAAcJmBYaCACSAQAEAAcJmBYaCACSAQAAAA==.',
Sq='Squishly:BAAALgAECgQJCAAAAA==.',
St='Stanmarshh:BAAALgADCgEJAQAAAA==.Staydown:BAAALgADCgEJAgAAAA==.Steelrib:BAAALgAECgQJCAAAAA==.Stogienuna:BAAALgADCgYJBgAAAA==.Straam:BAACLgAFFH8IAAIdAAMJMAuMEQDbAAAdAAMJMAuMEQDbAAAuAAQKfzAAAh0ACQnYHRkOAKkCAB0ACQnYHRkOAKkCAAAA.Stupidity:BAAALgAECgYJBgAAAA==.Støney:BAABLgAECn8eAAIKAAcJWgzgeQDiAAAKAAcJWgzgeQDiAAAAAA==.',
Su='Subatronic:BAAALgAECgEJAQABLgAFFAYJFQAcAN0lAA==.Subroutine:BAABLgAECn8WAAIOAAgJHh/ZDgDIAgAOAAgJHh/ZDgDIAgABLgAFFAYJFQAcAN0lAA==.Subtractive:BAACLgAFFH8VAAIcAAYJ3SVgAAAuAgAcAAYJ3SVgAAAuAgAuAAQKfxsAAhwACAmmJiQBAIYDABwACAmmJiQBAIYDAAAA.',
Sw='Swagchamp:BAAALgADCgQJBQABLgAECgEJAgAIAAAAAA==.Swodaem:BAAALgADCgQJBAAAAA==.',
Sx='Sx:BAACLgAFFH8FAAIKAAIJ2SHEMwDKAAAKAAIJ2SHEMwDKAAAuAAQKfyIAAgoACQk5I7oFAKcDAAoACQk5I7oFAKcDAAAA.',
Sy='Sylthara:BAAALgAECgYJEwAAAA==.Syrellis:BAAALgAECgEJAgAAAA==.',
['Så']='Såcred:BAAALgADCggJDwAAAA==.',
Ta='Taenggu:BAABLgAECn8bAAIiAAcJLBZfBQCGAQAiAAcJLBZfBQCGAQAAAA==.Takki:BAAALgAECgIJAgAAAA==.Talethia:BAAALgAECgQJBQAAAA==.Tartarus:BAAALgAECgMJAwAAAA==.Tavin:BAAALgAECgUJBQAAAA==.Tazchem:BAAALgAECgQJBQAAAA==.',
Te='Techboar:BAAALgAECgEJAQAAAA==.Teinuya:BAABLgAECn8kAAQQAAgJkR0CDAACAgAQAAYJEx0CDAACAgAZAAUJgBzRCgCPAQABAAEJ1RnzDQFCAAAAAA==.Teivel:BAAALgADCgYJBgAAAA==.Tekorgx:BAAALgADCgkJJwAAAA==.Tenderfiddle:BAAALgAECgYJEgAAAA==.Tenochitilan:BAAALgAECgQJBQAAAA==.Tenuous:BAAALgAECgUJCgAAAA==.Teregor:BAAALgADCgEJAQAAAA==.',
Th='Thainir:BAAALgAECgIJAgABLgAECggJIwATALAkAA==.Thanar:BAAALgADCgEJAQAAAA==.Thisistheway:BAABLgAECn8aAAIcAAgJShC5CgB9AQAcAAgJShC5CgB9AQABLgAFFAMJCQAPANEZAA==.Thoorz:BAAALgADCgUJBQAAAA==.Thornman:BAAALgADCgcJBwAAAA==.Thorzy:BAAALgAECgYJEgABLgADCgUJBQAIAAAAAA==.Thothh:BAAALgAECgUJCwAAAA==.Thraxacious:BAABLgAECn8gAAIlAAgJuBjADADtAQAlAAgJuBjADADtAQAAAA==.Thulcandra:BAABLgAECn8UAAIKAAYJxB/fYwARAgAKAAYJxB/fYwARAgAAAA==.Thulsadoomm:BAAALgAECgYJDwAAAA==.Thundermay:BAAALgAECgYJEQAAAA==.',
Ti='Tibremix:BAAALgADCgYJBgAAAA==.Tiduss:BAAALgAECgYJDwAAAA==.Tigó:BAAALgAECgcJEwAAAA==.Tigölebittie:BAABLgAECn8XAAMTAAcJ0xPmGgCoAQATAAcJ0xPmGgCoAQASAAEJyxi4dgBIAAAAAA==.Tinkerrbella:BAABLgAECn8WAAQCAAcJvQ3xUwBsAQACAAcJvQ3xUwBsAQAOAAUJFgIAbQCKAAAFAAIJtQGaKQBMAAABLgAFFAYJDAACAJUGAA==.Tireliaa:BAAALgAECgEJAQAAAA==.',
Tj='Tjnewt:BAAALgADCgkJCQAAAA==.',
To='Toatsie:BAAALgAECgcJEgAAAA==.Toyotathon:BAAALgADCgYJBgAAAA==.',
Tr='Trafalgour:BAAALgADCgMJAwAAAA==.Traxal:BAAALgAECgcJBQAAAA==.Trumpybear:BAABLgAECn8WAAIDAAcJ9xlLNABxAQADAAcJ9xlLNABxAQAAAA==.',
Ts='Tsun:BAABLgAECn8aAAMoAAcJRhUcDABBAQAoAAYJLxccDABBAQAcAAEJugvIKgA2AAAAAA==.',
Ty='Tyys:BAAALgADCgMJAwAAAA==.',
['Tø']='Tønka:BAAALgAECgcJCgABLgAECgcJGAADAGcjAA==.',
Ud='Uddertrouble:BAEBLgAECn8VAAICAAYJ1BJUTACEAQACAAYJ1BJUTACEAQAAAA==.',
Uf='Ufos:BAAALgADCggJHgAAAA==.',
Ui='Ui:BAAALgADCgUJBQABLgAFFAIJBQAKANkhAA==.',
Un='Uncletat:BAABLgAECn8hAAQYAAcJqyHvBQBeAgAYAAYJNiXvBQBeAgAkAAYJmCFTDwBJAgAUAAEJEhRmPABAAAAAAA==.',
Ur='Urmada:BAABLgAECn8YAAIKAAYJOAubXgAfAQAKAAYJOAubXgAfAQAAAA==.Urmami:BAAALgAECgYJEwAAAA==.',
Ut='Uthil:BAAALgADCgQJBAAAAA==.',
Va='Vahnt:BAABLgAECn8lAAIdAAgJgRd2IAAcAgAdAAgJgRd2IAAcAgAAAA==.Valkon:BAAALgADCgYJBgAAAA==.Vallissrya:BAABLgAECn8mAAIDAAkJYBxNFwABAgADAAkJYBxNFwABAgAAAA==.Vampire:BAAALgAECgYJCAAAAA==.Vampyre:BAACLgAFFH8YAAIMAAYJABosAwCCAQAMAAYJABosAwCCAQAuAAQKfxgAAgwACQmaIfcCADQDAAwACQmaIfcCADQDAAAA.Vanadie:BAAALgAECgYJBgAAAA==.Vanta:BAAALgADCgcJDQAAAA==.Vargmal:BAAALgADCgEJAgAAAA==.',
Ve='Velo:BAAALgAECgMJAwAAAA==.Veloboom:BAAALgAECgMJAwAAAA==.Vendettá:BAAALgAECgQJCwAAAA==.Vengeta:BAAALgADCgQJBAAAAA==.Venomflare:BAAALgAECgMJAwAAAA==.',
Vi='Vitaminn:BAABLgAECn8WAAQDAAcJlRUlKgCZAQADAAcJ8RQlKgCZAQAHAAIJTwZRigBUAAAEAAEJnBf5PgBCAAAAAA==.Vithiris:BAAALgADCgYJBgAAAA==.',
Vl='Vlaen:BAAALgAECgMJAwAAAA==.',
Vo='Voidreaper:BAAALgADCgEJAwAAAA==.Votum:BAAALgAECgMJAwAAAA==.',
Vy='Vyndanin:BAAALgAECggJDQAAAA==.Vynora:BAAALgAECgkJAwAAAA==.',
Wa='Wafflez:BAAALgAECgcJBwAAAA==.Walterlight:BAAALgAECgEJAQAAAA==.Warlockd:BAAALgADCgUJBQAAAA==.Wazoshao:BAAALgADCgIJAgAAAA==.',
We='Welios:BAAALgAECgMJBgAAAA==.',
Wh='Wheataid:BAAALgADCggJDQAAAA==.',
Wi='Wilhedin:BAACLgAFFH8HAAIRAAMJbhlLDwARAQARAAMJbhlLDwARAQAuAAQKfywAAygACQn+JI4AAA0DACgACQl5I44AAA0DABEABwkHJJ8NAOkCAAAA.Windente:BAABLgAECn8cAAMCAAcJrBepKQBvAQACAAYJYBipKQBvAQAOAAQJ/QjsZgCjAAAAAA==.Wing:BAEBLgAFFH8FAAIDAAIJUiJmJwDGAAADAAIJUiJmJwDGAAABLgAFFAYJDwAYAOkQAA==.Wiseau:BAABLgAECn8XAAMCAAgJWRaEGwC6AQACAAgJWRaEGwC6AQAOAAEJ4wPxkwAmAAAAAA==.',
Wo='Wolfer:BAAALgADCgEJAQAAAA==.Wong:BAAALgAECgEJBAAAAA==.',
Wu='Wulfnbolt:BAAALgADCgIJAgAAAA==.Wumbology:BAAALgAECgcJAQAAAA==.',
Wy='Wyon:BAAALgAECgYJEgAAAQ==.',
Xu='Xuen:BAAALgAECgYJEgAAAA==.',
Yo='Yokog:BAAALgAECgMJBQAAAA==.',
Za='Zaeluna:BAABLgAECn8mAAIJAAgJYyB1AwDWAgAJAAgJYyB1AwDWAgAAAA==.Zanikan:BAAALgAECgkJAQAAAA==.Zanzer:BAAALgAECgIJBAAAAA==.Zathara:BAAALgAECggJDAAAAA==.',
Ze='Zeevoid:BAAALgADCgEJAQAAAA==.Zephiron:BAAALgADCgcJDgAAAA==.Zeroshot:BAAALgAECgEJAwAAAA==.Zeshom:BAAALgAECgQJBAAAAA==.',
Zp='Zpazzie:BAAALgAECgEJAQAAAA==.',
Zu='Zuluk:BAAALgADCgUJBQAAAA==.',
Zy='Zynblaster:BAAALgADCgQJBAAAAA==.',
['Zö']='Zörö:BAAALgAFFAEJAQAAAA==.',
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

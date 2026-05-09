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

local lookup = {'Warlock-Demonology','Hunter-BeastMastery','Paladin-Retribution','Druid-Feral','Paladin-Protection','Hunter-Survival','Shaman-Elemental','Paladin-Holy','Unknown-Unknown','Mage-Fire','Druid-Guardian','Mage-Frost','DeathKnight-Unholy','DeathKnight-Blood','Evoker-Augmentation','Hunter-Marksmanship','Evoker-Preservation','Warlock-Affliction','Warrior-Fury','Druid-Balance','Druid-Restoration','Priest-Shadow','Rogue-Subtlety','Priest-Holy','DemonHunter-Havoc','DemonHunter-Devourer','Warlock-Destruction','Evoker-Devastation','Shaman-Enhancement','Warrior-Protection','Shaman-Restoration','Monk-Windwalker','Monk-Mistweaver','Monk-Brewmaster','DemonHunter-Vengeance','DeathKnight-Frost','Priest-Discipline','Rogue-Assassination','Rogue-Outlaw','Warrior-Arms',}
local provider = {region='US',realm='Frostwolf',name='US',type='weekly',zone=46,date='2026-05-08',data={Aa='Aamodar:BAAALgAECgYJDgAAAA==.Aaz:BAAALgAECgEJAQAAAA==.',
Ab='Abadon:BAABLgAECn8nAAIBAAgJOxdAIADvAQABAAgJOxdAIADvAQAAAA==.',
Ac='Acathisia:BAAALgAECgEJAQAAAA==.Acidangel:BAAALgADCgcJBwAAAA==.',
Ad='Adalea:BAAALgAECgMJAwAAAA==.Adino:BAABLgAECn8mAAICAAgJYA0DLwCSAQACAAgJYA0DLwCSAQAAAA==.',
Ae='Aeldius:BAAALgAECgEJAQAAAA==.Aeryn:BAACLgAFFH8KAAIDAAQJdxYqHgA2AQADAAQJdxYqHgA2AQAuAAQKfyIAAgMACAnnIu0OABcDAAMACAnnIu0OABcDAAAA.',
Ag='Aggranak:BAAALgAECgYJCQAAAA==.',
Ah='Ahote:BAABLgAECn8TAAIEAAUJJSVVBAApAgAEAAUJJSVVBAApAgAAAA==.Ahtee:BAABLgAECn8mAAMDAAgJSh1MEwBfAgADAAgJSh1MEwBfAgAFAAMJpwitNgBoAAAAAA==.',
Ak='Akroz:BAAALgAECgUJBgAAAA==.Akuprovik:BAAALgAECgYJDgAAAA==.',
Al='Alande:BAAALgADCgMJAwAAAA==.Alanthos:BAAALgAECgQJBAAAAA==.Aldamithas:BAAALgADCgEJAQAAAA==.Alenon:BAAALgADCgMJAwABLgAECggJGAACAJQaAA==.Alexiea:BAAALgADCgcJCwAAAA==.Algodon:BAAALgAFFAMJAwAAAA==.Allenduin:BAAALgADCgEJAQAAAA==.Almeads:BAAALgAECgEJAQAAAA==.Alonias:BAAALgAECgUJCQAAAA==.Alseena:BAABLgAECn8aAAIDAAYJgBiTVQBHAQADAAYJgBiTVQBHAQAAAA==.Alysiita:BAAALgAECgEJAQAAAA==.',
Am='Amadeux:BAACLgAFFH8HAAIGAAQJPxIGCABTAQAGAAQJPxIGCABTAQAuAAQKfxwAAgYACAkCIIQHAHoCAAYACAkCIIQHAHoCAAAA.Amarawr:BAAALgADCgYJBgABLgAFFAQJBwAGAD8SAA==.Amicae:BAAALgADCgcJCAAAAA==.Ammandor:BAAALgAECgQJBAAAAA==.Amun:BAAALgAECgEJAQAAAA==.',
An='Anceirbe:BAAALgAECgEJAQAAAA==.Andenarras:BAAALgAECgQJCAABLgAECggJHQAHAIMbAA==.Anform:BAAALgAECgIJAgAAAA==.Anryn:BAAALgAECgYJBgABLgAFFAQJCgADAHcWAA==.Anthais:BAAALgAECgEJAQAAAA==.Anvar:BAABLgAECn8YAAICAAgJlBoGFwAXAgACAAgJlBoGFwAXAgAAAA==.',
Ap='Apocalypto:BAAALgADCgMJAwAAAA==.',
Aq='Aquiline:BAAALgADCgYJCQAAAA==.',
Ar='Arastaya:BAAALgADCgcJCgAAAA==.Arathion:BAABLgAECn8vAAIIAAgJFh3WCgBkAgAIAAgJFh3WCgBkAgAAAA==.Archistrate:BAAALgADCgkJEAAAAA==.Artamir:BAAALgADCgMJAwAAAA==.Arx:BAAALgAECgcJCgAAAA==.',
At='Atrumdeus:BAABLgAECn8uAAIDAAgJSRvgHgAPAgADAAgJSRvgHgAPAgAAAA==.',
Au='Audiamer:BAAALgAECgQJBQAAAA==.',
Av='Avindel:BAAALgAECgQJBAAAAA==.',
Aw='Awarmplace:BAAALgADCgYJBgABLgAECgYJDQAJAAAAAA==.Aweyaeh:BAAALgADCgQJBwAAAA==.Awkykit:BAABLgAECn8XAAIKAAcJpQT5BwDzAAAKAAcJpQT5BwDzAAAAAA==.',
Ay='Ayayron:BAAALgADCgUJBQAAAA==.',
Az='Azymondias:BAAALgADCgEJAgAAAA==.',
Ba='Babushka:BAABLgAECn8VAAILAAYJVBCJEwDTAAALAAYJVBCJEwDTAAAAAA==.Babyface:BAAALgAECgUJDQAAAA==.Banddon:BAAALgADCgcJEAAAAA==.Bangerz:BAABLgAECn8UAAIMAAYJyA+WzQBQAQAMAAYJyA+WzQBQAQAAAA==.Bannann:BAAALgADCgIJAgAAAA==.Banned:BAAALgAECgQJBQABLgAFFAIJBQABAC0hAA==.Bariôn:BAAALgAECgQJBwAAAA==.Barney:BAAALgADCgYJBwAAAA==.',
Be='Beakk:BAAALgAECgUJCgABLgAFFAYJGQANANYeAA==.Beaksbigdk:BAACLgAFFH8ZAAMNAAYJ1h79BwDLAQANAAUJ1h79BwDLAQAOAAEJAACiEQBmAAAuAAQKfzIAAw4ACQkPJj8CANYCAA0ACQk9JZcRABIDAA4ACAmMJD8CANYCAAAA.Bearach:BAAALgADCgUJBQAAAA==.Beariál:BAABLgAECn8ZAAMNAAgJCxBdZQAYAQANAAgJyg9dZQAYAQAOAAcJ6wT0HgDKAAAAAA==.Beedo:BAAALgAECgEJAgAAAA==.Beef:BAAALgAECgYJBgABLgAFFAUJDgAPALccAA==.Beeftek:BAAALgADCgEJAQAAAA==.Belfegor:BAAALgAECgQJDAAAAA==.Belldia:BAACLgAFFH8OAAICAAYJ/wpMBQBOAQACAAYJ/wpMBQBOAQAuAAQKfzMAAwIACQkZIHsJAJ4CAAIACQkZIHsJAJ4CABAABQnVDZ1QAAsBAAAA.Beni:BAAALgAECgUJDAAAAA==.Beniima:BAAALgAECgYJEwAAAA==.Benimarú:BAAALgAECgQJBAAAAA==.Bennylickz:BAABLgAECn8wAAMRAAkJMxc5CADmAQARAAgJyRU5CADmAQAPAAYJ9RTiEwCpAQAAAA==.',
Bi='Bibby:BAAALgAECgYJDAAAAA==.Bibi:BAAALgAECgQJBAAAAA==.Birdbear:BAAALgAECgYJDgAAAA==.',
Bl='Blgelk:BAAALgAECgUJBgAAAA==.Blightedmilk:BAAALgADCgUJBQABLgAFFAMJBQASAK8QAA==.Blufox:BAABLgAECn8QAAIDAAYJFiQpHwANAgADAAYJFiQpHwANAgAAAA==.Blxrry:BAAALgAECgQJBgABLgAFFAIJBQAMANkhAA==.',
Bm='Bmanzero:BAAALgADCgIJAgAAAA==.',
Bo='Bobfresh:BAAALgAECgIJAgABLgAECgYJEQAJAAAAAA==.',
Br='Brainpower:BAAALgAECgYJBgAAAA==.Broherum:BAAALgADCgEJAwAAAA==.Broseidon:BAAALgADCgEJAQAAAA==.Brucella:BAAALgADCgkJFAAAAA==.Bruizin:BAAALgADCgQJBAAAAA==.Brunia:BAAALgADCgIJAgAAAA==.',
Bu='Bubonicmyro:BAAALgAECgMJAwABLgAECggJEQAJAAAAAA==.Buckbeak:BAAALgAECgYJDAAAAA==.Bulgingtotem:BAAALgADCgYJBgAAAA==.Busting:BAAALgAECgYJDQAAAA==.Buttmucker:BAAALgAECgIJAgAAAA==.Buzzliteyear:BAAALgAECgQJBAAAAA==.',
Bw='Bweomysin:BAAALgAFFAIJAgAAAA==.',
By='Byebye:BAAALgAECgcJBgAAAA==.',
['Bà']='Bàhamut:BAAALgADCgMJAwAAAA==.',
['Bå']='Båemax:BAAALgAECgIJBQAAAA==.',
Ca='Caelestos:BAAALgAECggJEgAAAA==.Castar:BAAALgADCgIJAgAAAA==.',
Cc='Ccwwds:BAAALgADCgYJCQABLgAFFAEJAQAJAAAAAA==.',
Ce='Celypzo:BAAALgADCgkJCQAAAA==.Cewkie:BAABLgAECn8cAAITAAYJSxQTJgBDAQATAAYJSxQTJgBDAQAAAA==.',
Ch='Chaulock:BAAALgAECgcJBwAAAA==.Chausup:BAAALgADCgQJBAABLgAECggJIgADAIskAA==.Chautime:BAABLgAECn8iAAIDAAgJiyTABwBYAwADAAgJiyTABwBYAwAAAA==.Cheefillkeef:BAAALgADCgYJDAABLgAECgMJBAAJAAAAAA==.Chemdizz:BAAALgAECgQJBAAAAA==.Chialliance:BAABLgAECn8UAAMUAAcJJBHdGgBfAQAUAAcJJBHdGgBfAQAVAAEJowGn6gAaAAAAAA==.Chizz:BAAALgAECgQJBwABLgAFFAUJFgALAEQXAA==.Choujisan:BAAALgAECgQJCQABLgAECgkJIQADAD4YAA==.Chrysamere:BAAALgADCgcJDQAAAA==.Chugrar:BAAALgADCggJCAAAAA==.',
Ci='Citizenwings:BAAALgAECgEJAQAAAA==.',
Cl='Clairebenet:BAABLgAECn8eAAIGAAgJUiF8AwDuAgAGAAgJUiF8AwDuAgAAAA==.Cloft:BAAALgAECgYJBgAAAA==.Clumzylock:BAAALgAECgcJEAABLgAECggJKAAWAJsKAA==.',
Co='Code:BAABLgAECn8fAAIXAAkJvSLFBwAUAwAXAAkJvSLFBwAUAwAAAA==.Consfearacy:BAAALgAECggJCgAAAA==.Coolynn:BAAALgADCgYJBgAAAA==.Corl:BAABLgAECn8ZAAIDAAcJTh7kIgD6AQADAAcJTh7kIgD6AQAAAA==.Corrl:BAABLgAECn8TAAIMAAcJLRgMRwCSAQAMAAcJLRgMRwCSAQABLgAECgcJGQADAE4eAA==.',
Cr='Crayzie:BAAALgADCgEJAQAAAA==.Crazyidiot:BAAALgADCgUJBQAAAA==.Creams:BAAALgADCgMJAwABLgADCgQJBAAJAAAAAA==.Creatrix:BAAALgADCgcJBwAAAA==.',
Cs='Csythe:BAAALgAECgYJDQAAAA==.',
Cu='Cuma:BAAALgAECgEJBAAAAA==.Cumb:BAAALgAECgYJEQAAAA==.Curatoria:BAAALgAECgUJBgAAAA==.',
Cw='Cwwddsz:BAAALgAECgEJAQABLgAFFAEJAQAJAAAAAA==.',
['Cã']='Cãstanova:BAAALgADCgQJBAAAAA==.',
['Cä']='Cäldius:BAAALgAECgUJBwAAAA==.',
Da='Daioh:BAAALgADCgEJAQAAAA==.Daladin:BAAALgADCgEJAQAAAA==.Damacraze:BAABLgAECn8ZAAICAAgJciC1EAC0AgACAAgJciC1EAC0AgAAAA==.Darkbluerose:BAABLgAECn8XAAMQAAYJrQfFFgCdAAAGAAUJLgXJIQDJAAAQAAYJVAbFFgCdAAAAAA==.Darkevilaeon:BAAALgADCggJCAAAAA==.Darkmelon:BAAALgADCgEJAQAAAA==.Dawigrund:BAAALgAECgYJEQAAAA==.Daxine:BAAALgAECgYJBgAAAA==.',
De='Deadboy:BAAALgADCggJCgAAAA==.Deadroar:BAAALgAECgcJEQAAAA==.Deadwill:BAAALgADCgYJBgAAAA==.Deaminase:BAABLgAECn8dAAIMAAYJ+htURACaAQAMAAYJ+htURACaAQAAAA==.Deathknell:BAAALgADCgQJBAAAAA==.Decypher:BAABLgAECn8UAAIYAAcJ6RvBDAAaAgAYAAcJ6RvBDAAaAgAAAA==.Deggle:BAAALgADCgIJAgAAAA==.Delphoxx:BAAALgAECgUJDQAAAA==.Demidru:BAAALgAECgYJDgAAAA==.Demonboar:BAABLgAECn8aAAMZAAgJNxNNDQCsAQAZAAgJNxNNDQCsAQAaAAYJPwSLmwDhAAAAAA==.Demonrocky:BAAALgADCgkJCwAAAA==.Demunic:BAAALgAECggJEgABLgAFFAMJCAALAO4OAA==.Dennis:BAAALgAECgEJAwAAAA==.Derringer:BAAALgAECgYJBgAAAA==.Destructíon:BAAALgADCgUJBgAAAA==.',
Dh='Dharin:BAAALgAECgEJAQAAAA==.Dhqt:BAAALgADCgQJBAAAAA==.',
Di='Digsy:BAAALgADCgEJAQAAAA==.Dihnnis:BAAALgAECgEJAQAAAA==.Dingbangow:BAAALgAECgUJCwAAAA==.Divination:BAAALgADCgYJBgAAAA==.Divinèhero:BAAALgAECgQJCQAAAA==.',
Do='Doneza:BAAALgAECgMJAwAAAA==.Donki:BAAALgAECgYJCAAAAA==.Donothingwin:BAACLgAFFH8FAAIBAAIJLSE1SgDDAAABAAIJLSE1SgDDAAAuAAQKfyUAAwEACQl/Jt8DAH4DAAEACQl/Jt8DAH4DABsAAwkKJZcnACUBAAAA.Doomgirl:BAAALgAECgYJBgAAAA==.Doublelift:BAAALgAFFAEJAQAAAA==.',
Dr='Dragondeznut:BAAALgAECgIJAgAAAA==.Drakblak:BAABLgAECn8jAAIYAAkJSBRJDwD0AQAYAAkJSBRJDwD0AQAAAA==.Draukarí:BAABLgAECn8gAAQSAAkJ9B1TAQDlAgASAAkJvB1TAQDlAgABAAcJYRzpKABtAgAbAAEJiB+wXwBQAAAAAA==.Drayer:BAABLgAECn8jAAIIAAgJnhAvIACFAQAIAAgJnhAvIACFAQAAAA==.Dripped:BAAALgADCgcJBwAAAA==.Droni:BAABLgAECn8WAAIaAAgJfRdgHADfAQAaAAgJfRdgHADfAQAAAA==.Drunkenmist:BAAALgAECgYJEQAAAA==.Drunkle:BAAALgADCgUJBQAAAA==.Dröbi:BAACLgAFFH8NAAIPAAQJpB3BDABtAQAPAAQJpB3BDABtAQAuAAQKfykAAw8ACQlhIjwEALsCAA8ACQlhIjwEALsCABwABgkIFU8aAGEBAAAA.',
Du='Dundundun:BAAALgAECgcJCAAAAA==.Duroklu:BAAALgAECgUJCAAAAA==.Durortar:BAABLgAECn8ZAAMCAAgJ/QimOABqAQACAAgJ/QimOABqAQAQAAEJrwDRmwAQAAAAAA==.Durrok:BAAALgAECgEJAQAAAA==.',
Dy='Dynastes:BAAALgADCgQJAQABLgAFFAYJGQANANYeAA==.Dyne:BAAALgADCgEJAQAAAA==.',
['Dê']='Dêdícatíón:BAAALgAECgYJDQAAAA==.',
['Dö']='Dödsriddare:BAAALgADCgYJBgAAAA==.',
Ea='Eazy:BAACLgAFFH8RAAMQAAUJXBVPCAA7AQAQAAUJNBVPCAA7AQACAAQJyggLHQAlAQAuAAQKfykAAxAACQlaI8cHACADABAACQlaI8cHACADAAIAAglGFpmGAIUAAAAA.',
Eg='Eggdrop:BAABLgAECn8iAAITAAgJsB9jCABkAgATAAgJsB9jCABkAgAAAA==.Egufro:BAAALgAECgYJBgABLgAFFAMJBQAdAIwNAA==.',
Eh='Ehgu:BAACLgAFFH8FAAIdAAMJjA0aBQD1AAAdAAMJjA0aBQD1AAAuAAQKfyoAAh0ACQkYGkICAI0CAB0ACQkYGkICAI0CAAAA.',
El='Eleverclear:BAABLgAECn8YAAMIAAcJWhSqPgB+AQAIAAcJWhSqPgB+AQADAAIJWw+6vwB1AAAAAA==.Elfbloodbane:BAAALgADCggJCAAAAA==.Eliizabeth:BAAALgAECgUJDAAAAA==.',
Em='Emidget:BAAALgAECgQJCQAAAA==.',
Ep='Epicorc:BAAALgADCgEJAQAAAA==.',
Er='Erhmer:BAAALgAECggJBgAAAA==.Erra:BAAALgAECgQJBQAAAA==.',
Et='Ethersong:BAAALgADCgcJCwAAAA==.',
Ev='Everlight:BAAALgADCgcJBwAAAA==.Evjoker:BAAALgAECgUJCAAAAA==.',
Ex='Exodes:BAAALgAECgYJEwAAAA==.',
Fa='Fabermor:BAAALgAECgEJAQAAAA==.Fairygon:BAAALgAECgUJBQAAAA==.Fairyhunter:BAAALgAECgEJAQAAAA==.Fairymonk:BAAALgAECgUJCgAAAA==.Fariona:BAAALgADCggJCQAAAA==.Fartbarf:BAABLgAECn8kAAIBAAgJcRJvVADKAQABAAgJcRJvVADKAQAAAA==.Fascharrawm:BAAALgADCgEJAwAAAA==.Fatshark:BAAALgAECgEJAQABLgAECgcJEQAJAAAAAA==.Faya:BAAALgADCgUJBQABLgAECggJGAACAJQaAA==.',
Fe='Fennicuss:BAAALgAECgEJAQAAAA==.Ferdalight:BAAALgAECgQJCAAAAA==.Festinu:BAAALgADCgQJBQAAAA==.',
Fi='Fistake:BAAALgAECgcJEgAAAA==.Fistalicious:BAAALgAECgMJAwABLgAFFAYJFgAeAN0lAA==.Fitshaced:BAAALgADCgMJAwAAAA==.',
Fl='Flandia:BAAALgAECgQJCAAAAA==.Flintanyl:BAAALgADCgUJCQAAAA==.',
Fo='Forduecezero:BAAALgAECgYJDgAAAA==.',
Fr='Fricher:BAABLgAECn8iAAINAAgJ1hFWMAC4AQANAAgJ1hFWMAC4AQAAAA==.Fridgecig:BAAALgADCgcJBwAAAA==.Frostbringer:BAAALgAECgMJAwAAAA==.Frostworn:BAAALgADCgYJBgAAAA==.Frostybetch:BAAALgAECgcJDAAAAA==.Frozenwithin:BAAALgAECgMJAwAAAA==.Froznbolt:BAAALgADCgcJBwAAAA==.Froznlight:BAABLgAECn8YAAIDAAcJ+RwGMwBWAgADAAcJ+RwGMwBWAgAAAA==.Fruitsnacks:BAAALgAECgYJBgABLgAFFAcJGQAOAEUXAA==.Fränk:BAAALgADCgcJDwAAAA==.Frío:BAAALgAECgQJBQAAAA==.Frõst:BAAALgADCgMJAwAAAA==.',
Fu='Fusio:BAAALgADCgMJAwAAAA==.',
Fy='Fylerian:BAACLgAFFH8aAAIUAAcJ/h3PAABNAgAUAAcJ/h3PAABNAgAuAAQKfx0AAhQACQkwJHgCAJcDABQACQkwJHgCAJcDAAAA.Fylerianmage:BAABLgAECn8YAAIMAAYJMiDtlwClAQAMAAYJMiDtlwClAQABLgAFFAcJGgAUAP4dAA==.Fylerianprie:BAAALgAFFAEJAQABLgAFFAcJGgAUAP4dAA==.Fyrebane:BAAALgAECgYJBgAAAA==.',
Ga='Galaxygas:BAAALgAECgYJDQAAAA==.Ganjja:BAAALgAECgEJAQAAAA==.Gardrath:BAAALgAFFAIJAgAAAA==.Gargalon:BAAALgAFFAEJAQAAAA==.Gatør:BAAALgAECgcJEwAAAA==.',
Ge='Gether:BAAALgADCgcJDAAAAA==.Getter:BAABLgAECn8XAAILAAgJ+Bq0BwC3AQALAAgJ+Bq0BwC3AQAAAA==.',
Gh='Ghettomike:BAAALgAECgcJCwAAAA==.',
Gi='Gilga:BAAALgAECgYJCgAAAA==.Gillixos:BAAALgAECgEJAQAAAA==.Giny:BAABLgAECn8hAAIHAAgJxBMmFQCrAQAHAAgJxBMmFQCrAQAAAA==.',
Gl='Glandros:BAAALgADCgUJBwAAAA==.Glorin:BAAALgAECgYJDAAAAA==.',
Go='Gobbledeez:BAAALgAECgcJCwAAAA==.Gojojo:BAABLgAECn8kAAITAAgJ2xs/EwC0AgATAAgJ2xs/EwC0AgAAAA==.Gorfrunch:BAAALgAECgUJCQAAAA==.Gorro:BAAALgAECgIJBgAAAA==.Govinniuur:BAABLgAECn8eAAIOAAcJ+Q7dFwAOAQAOAAcJ+Q7dFwAOAQAAAA==.',
Gr='Grandcodex:BAAALgADCgcJBwABLgAECggJJQANALIUAA==.Granips:BAAALgADCgIJAQAAAA==.Gravelord:BAAALgADCgEJAQAAAA==.Grawnita:BAABLgAECn8iAAIMAAgJ1CLiEwAxAwAMAAgJ1CLiEwAxAwAAAA==.Grizzy:BAAALgAECgYJCQAAAA==.Grohan:BAAALgADCgEJAQAAAA==.Groundscore:BAAALgADCgUJBQABLgAECgMJAwAJAAAAAA==.Gryf:BAAALgADCgQJBAAAAA==.',
Gu='Gundam:BAAALgAECggJDgABLgAFFAYJEwAMAHoZAA==.Gunde:BAAALgADCgQJAwAAAA==.',
Gw='Gweilo:BAAALgADCgQJBAAAAA==.Gwendilyn:BAAALgAECgYJBgAAAA==.Gwydionatlan:BAAALgADCgEJAQAAAA==.',
Gy='Gyndrinolara:BAABLgAECn8ZAAICAAgJZQ+XLgCUAQACAAgJZQ+XLgCUAQAAAA==.',
Ha='Hafadude:BAAALgAECgkJBwAAAA==.Hakouh:BAAALgAECgYJBwAAAA==.Harambabe:BAAALgAECgYJBgAAAA==.Hatereading:BAAALgADCgcJCAAAAA==.',
He='Headhuntér:BAAALgAECgYJCwAAAA==.Healdnbloody:BAAALgAECgIJAgAAAA==.Healgoßyeßye:BAAALgAECgEJAgAAAA==.Heckitwebawl:BAAALgADCgEJAQABLgAECgkJMAARADMXAA==.Hehatesme:BAAALgADCgcJBwAAAA==.Hellface:BAAALgADCgcJDAABLgAFFAEJAQAJAAAAAA==.Hellokrittyz:BAAALgADCgcJBwAAAA==.Hephaestis:BAAALgADCgUJBQAAAA==.',
Hi='Hiimmas:BAAALgAECgkJAgABLgAFFAUJDgAdAAYjAA==.Hikiru:BAAALgAECgkJCAAAAA==.',
Ho='Holydwarfen:BAAALgAECgEJAQAAAA==.Holysh:BAAALgADCgYJBgAAAA==.Holywater:BAABLgAECn84AAIFAAgJDCGXAgCMAgAFAAgJDCGXAgCMAgAAAA==.Hoon:BAAALgADCgkJCQAAAA==.Hoonish:BAABLgAECn8WAAMBAAYJ9R5jQQAJAgABAAYJ9R5jQQAJAgAbAAIJtxbmUgB1AAAAAA==.Horick:BAAALgAECgEJAQAAAA==.',
Hr='Hruaka:BAAALgAECgMJAwAAAA==.',
Hy='Hyperiann:BAAALgADCgEJAQAAAA==.',
Ia='Iamstronge:BAAALgADCgMJAwAAAA==.',
Ic='Iceyrot:BAAALgAECgYJBgAAAA==.',
Il='Illuminax:BAAALgAECgUJCAAAAA==.Illydan:BAAALgAECgIJAwABLgAFFAEJAQAJAAAAAA==.',
Im='Immahotmess:BAAALgAECgEJAQAAAA==.',
In='Inamorta:BAAALgAECgcJEwAAAA==.Ineedbowjob:BAAALgAECgYJEAAAAA==.Intothedark:BAAALgAECgMJBAAAAA==.Intotherain:BAAALgADCgIJAwAAAA==.Inya:BAAALgAECgMJBwAAAA==.Inyomouf:BAAALgAECgEJAQAAAA==.',
Io='Iomadae:BAABLgAECn8ZAAIDAAgJxyCNFwDbAgADAAgJxyCNFwDbAgAAAA==.',
Ir='Ironjaws:BAAALgAECgQJCwAAAA==.',
Is='Isaacnewton:BAABLgAECn8fAAITAAYJhx4ZGACmAQATAAYJhx4ZGACmAQAAAA==.',
It='Ithoril:BAAALgADCgcJCwAAAA==.Itsdone:BAABLgAECn8tAAMBAAgJHxM8OQCBAQABAAgJCRI8OQCBAQAbAAMJSxRvGQB1AAABLgAFFAEJAQAJAAAAAA==.',
Iv='Iveliz:BAABLgAECn8ZAAIWAAgJxhOGEADJAQAWAAgJxhOGEADJAQAAAA==.',
Iz='Izheals:BAAALgADCgEJAQABLgAECgIJAgAJAAAAAA==.',
Ja='Jackk:BAACLgAFFH8JAAIIAAQJZRwXFgD6AAAIAAQJZRwXFgD6AAAuAAQKfykAAggACAklIUEIAOoCAAgACAklIUEIAOoCAAAA.Jackks:BAAALgAECgEJAQABLgAFFAQJCQAIAGUcAA==.Jaeger:BAABLgAECn8cAAIGAAgJfhr7CwAQAgAGAAgJfhr7CwAQAgAAAA==.Jamalsdad:BAAALgAECgIJAgAAAA==.Janzan:BAABLgAECn8VAAIfAAYJZxNfMgBEAQAfAAYJZxNfMgBEAQAAAA==.Jasmonk:BAABLgAECn8lAAIgAAcJHwt7HgAwAQAgAAcJHwt7HgAwAQAAAA==.Jayren:BAAALgAECgIJAgAAAA==.',
Je='Jenniekim:BAABLgAECn8ZAAIaAAcJMhCIRwAiAQAaAAcJMhCIRwAiAQAAAA==.',
Ji='Jinkz:BAAALgAECgYJCAAAAA==.',
Jo='Josephsmith:BAAALgAECgkJAwAAAA==.',
Ju='Judgevis:BAABLgAECn8WAAIIAAgJrg8kJQBgAQAIAAgJrg8kJQBgAQAAAA==.Jumbles:BAAALgAECgYJBgAAAA==.Justeene:BAAALgAECgYJBgABLgAECgQJBQAJAAAAAA==.',
Jv='Jvedo:BAAALgADCgYJBQAAAA==.',
['Jø']='Jøshu:BAAALgAECgUJBwAAAA==.',
Ka='Kabalester:BAAALgAECgIJAgAAAA==.Kaello:BAAALgAECgEJAQABLgAECgYJCwAJAAAAAA==.Kaerigyn:BAAALgAECgYJCwAAAA==.Karrona:BAAALgADCgcJEgAAAA==.Katirinu:BAAALgADCgMJAwAAAA==.Kawliga:BAAALgADCgkJDwAAAA==.Kazuu:BAAALgADCgEJBgAAAA==.',
Ke='Keepup:BAAALgAECgcJDAABLgAFFAIJBQABAC0hAA==.Keg:BAAALgAFFAEJAgABLgAFFAcJGQAOAEUXAA==.Keheo:BAAALgADCgMJAwAAAA==.Keimei:BAAALgADCgMJAwABLgAECggJHwAfALQbAA==.Keladun:BAAALgAECgUJDAAAAA==.',
Kh='Khaho:BAABLgAECn8WAAIMAAgJcxKuTwB7AQAMAAgJcxKuTwB7AQAAAA==.Khonan:BAABLgAECn8XAAQgAAYJUBd/NwBAAQAgAAUJ9BR/NwBAAQAhAAYJtQ6GNAAfAQAiAAEJsQPwlgAeAAABLgAFFAUJDQAMAFwYAA==.',
Ki='Kiamar:BAAALgAECgkJDwAAAA==.Kijyo:BAABLgAECn8UAAIjAAgJYBToCABPAQAjAAgJYBToCABPAQAAAA==.Kishu:BAAALgADCggJDQAAAA==.Kitz:BAAALgADCgEJAQAAAA==.',
Kn='Knutebomb:BAAALgADCgEJAQAAAA==.',
Ko='Koinzell:BAAALgADCgEJAgAAAA==.Kojirin:BAAALgADCgYJBwAAAA==.Kordarg:BAAALgAECgUJBQAAAA==.Korlax:BAAALgAECgEJAQAAAA==.',
Kr='Krex:BAAALgADCgYJDQAAAA==.Krossedup:BAAALgADCgcJDgAAAA==.Kryptonikk:BAAALgAECgYJCQAAAA==.Krystal:BAAALgAECgMJBgAAAA==.Kröw:BAABLgAECn8eAAIdAAkJZA4rBgDhAQAdAAkJZA4rBgDhAQAAAA==.',
Ku='Kudrix:BAABLgAECn8fAAIgAAgJ3h9RBQCJAgAgAAgJ3h9RBQCJAgAAAA==.Kurgaz:BAAALgAECgYJBgAAAA==.Kurø:BAABLgAECn8oAAINAAgJiyBJEQBzAgANAAgJiyBJEQBzAgAAAA==.',
Kw='Kwanzie:BAAALgAECgMJAwAAAA==.',
Ky='Kyoco:BAAALgADCgEJAQAAAA==.Kyprolis:BAAALgADCgYJBgAAAA==.Kyushi:BAAALgAECgYJEQAAAA==.',
['Kà']='Kàri:BAABLgAECn8YAAIVAAkJ9hjECwCOAgAVAAkJ9hjECwCOAgAAAA==.',
['Kä']='Käva:BAAALgAECgEJAQAAAA==.',
['Kï']='Kïngston:BAEALgAECgYJDwAAAA==.',
La='Lamorakk:BAAALgAECgEJAQAAAA==.Lany:BAABLgAECn8YAAMNAAcJ6BSNaAC8AQANAAcJDhSNaAC8AQAkAAMJtxFdFQA/AAAAAA==.Latherfanta:BAAALgAECgYJDAAAAA==.Laurijaydn:BAAALgAECgcJBwAAAA==.',
Le='Lelink:BAAALgAECgYJDQAAAA==.Lemywinx:BAAALgAECgEJAQAAAA==.Leoden:BAAALgADCgUJBAAAAA==.Leopard:BAAALgAECgkJBwAAAA==.Lepra:BAAALgADCgUJBgAAAA==.Leslieknope:BAAALgADCgIJAgAAAA==.',
Li='Lichbabies:BAAALgADCgMJAwAAAA==.Lielys:BAAALgAECgUJEQABLgAECgYJCQAJAAAAAA==.Lightlana:BAACLgAFFH8KAAIDAAQJ/BFzGQBGAQADAAQJ/BFzGQBGAQAuAAQKfxwAAgMACAm5Ic0YANQCAAMACAm5Ic0YANQCAAAA.Lightwalker:BAAALgAECgUJBQAAAA==.Likeaglove:BAAALgAECgYJDAABLgAFFAEJAQAJAAAAAA==.Linfang:BAAALgADCgYJBgAAAA==.Littlestarz:BAABLgAECn8iAAMfAAgJpB+sBgDHAgAfAAgJpB+sBgDHAgAHAAMJ5QpEbgCKAAAAAA==.Lizzieag:BAECLgAFFH8FAAITAAMJOQlmHADSAAATAAMJOQlmHADSAAAuAAQKfykAAhMACAksGMkTAM4BABMACAksGMkTAM4BAAAA.',
Ll='Lluvia:BAAALgAECgQJBwAAAA==.',
Lo='Loafsies:BAAALgADCgMJAwAAAA==.Loakai:BAAALgAECgEJAQAAAA==.Lockndotz:BAAALgAECgYJBgABLgAECgQJBQAJAAAAAA==.Loenil:BAABLgAECn8ZAAIDAAgJiAybTQBdAQADAAgJiAybTQBdAQAAAA==.Lohueng:BAAALgAECgQJBQAAAA==.Loodah:BAAALgAECgIJAgAAAA==.Lookee:BAAALgAECgYJCwAAAA==.Loranoth:BAAALgADCggJDwAAAA==.Loreel:BAAALgAECgUJBQAAAA==.Loudnoise:BAAALgADCgYJBgAAAA==.',
Lu='Lucielle:BAAALgAECgYJCwAAAA==.Luke:BAAALgAECgIJAgAAAA==.Luminali:BAAALgADCggJCgAAAA==.Lunareva:BAABLgAECn8nAAIVAAgJJSJcBQADAwAVAAgJJSJcBQADAwAAAA==.Lunä:BAAALgAECgYJCgABLgAFFAYJDgACAP8KAA==.Lustarhymes:BAAALgAECgUJBQAAAA==.',
Ly='Lyxon:BAAALgAECgYJEgAAAA==.',
['Lå']='Låw:BAAALgAECgIJBAAAAA==.',
Ma='Maandos:BAAALgADCgcJBwAAAA==.Mabrian:BAAALgADCgcJBwAAAA==.Mafoôza:BAABLgAECn8mAAITAAgJwiLiBACtAgATAAgJwiLiBACtAgAAAA==.Magicalama:BAAALgADCgYJCwABLgAFFAQJBwAGAD8SAA==.Magicnugz:BAAALgADCgEJAQAAAA==.Magnanimity:BAEALgADCgIJAgABLgAECgYJGQACAGUXAA==.Magpen:BAAALgADCgMJBgAAAA==.Mahboyblu:BAAALgAECgMJAwAAAA==.Mahndoo:BAABLgAECn8gAAIMAAgJkRr7IAAmAgAMAAgJkRr7IAAmAgAAAA==.Makto:BAAALgADCgUJCAAAAA==.Malia:BAAALgAECgEJAQAAAA==.Maliciouso:BAABLgAECn8fAAIfAAgJtBuBCgCFAgAfAAgJtBuBCgCFAgAAAA==.Malédiction:BAABLgAECn8ZAAIMAAgJ6RXUdwDiAQAMAAgJ6RXUdwDiAQAAAA==.Mattdemøn:BAAALgAECgMJAwABLgAECggJGQACANIXAA==.Matua:BAAALgAECgEJAQAAAA==.Maymae:BAAALgAECgQJBwAAAA==.',
Me='Medizine:BAAALgAECgEJAgAAAA==.Meepz:BAAALgAECgEJAQAAAA==.Megabonk:BAAALgAECgQJBQABLgAECggJJAATANsbAA==.Megademac:BAABLgAECn8SAAIaAAUJLg/MiwALAQAaAAUJLg/MiwALAQAAAA==.Meowenstein:BAAALgAECgMJBgAAAA==.',
Mi='Miistral:BAABLgAECn8aAAIDAAcJsxeYQwB7AQADAAcJsxeYQwB7AQAAAA==.Miniblinks:BAAALgADCgQJAwAAAA==.Minisid:BAAALgAFFAIJAwAAAA==.Miriia:BAAALgAECgEJAgAAAA==.Mirshta:BAAALgADCggJEQAAAA==.Missmaam:BAABLgAECn8hAAIjAAcJqiCeAwAPAgAjAAcJqiCeAwAPAgABLgAFFAEJAQAJAAAAAA==.Mistinmae:BAAALgAECgEJAgABLgAECgYJFwAfACUTAA==.Mistrjenkins:BAAALgAECgQJBgAAAA==.Mixoz:BAAALgAECgQJBAAAAA==.',
Mo='Moistooltip:BAAALgADCgYJCwABLgAECgYJEQAJAAAAAA==.Mokotrize:BAABLgAECn8lAAIFAAgJ8hieBgD2AQAFAAgJ8hieBgD2AQAAAA==.Momtok:BAAALgAECgUJBwAAAA==.Monarch:BAAALgADCgEJAQAAAA==.Mookate:BAABLgAECn8pAAIUAAgJYRxnEACdAgAUAAgJYRxnEACdAgAAAA==.Moonblade:BAAALgADCgMJAwAAAA==.Mootylicious:BAAALgAECgEJAQABLgAECggJGQACANIXAA==.Mordred:BAAALgAECgUJDQAAAA==.',
Ms='Msfirefly:BAAALgAECgYJCQAAAA==.',
Mu='Mud:BAAALgADCgMJAwAAAA==.Munchies:BAAALgAECgQJBAAAAA==.Murlooze:BAAALgADCgYJBgAAAA==.Muwunfire:BAAALgADCgcJBwAAAA==.',
My='Myrolan:BAAALgAECgcJCQABLgAECggJEQAJAAAAAA==.Myrolee:BAAALgAECggJEQAAAA==.Myrowrynn:BAAALgAECgYJBgABLgAECggJEQAJAAAAAA==.Myrozond:BAAALgAECgYJDwABLgAECggJEQAJAAAAAA==.',
['Má']='Mánú:BAAALgAECgYJDQABLgAECgcJGAADAGcjAA==.',
['Mä']='Mänu:BAABLgAECn8YAAIDAAcJZyNKGQDRAgADAAcJZyNKGQDRAgAAAA==.',
['Mø']='Mønstrøsity:BAAALgAECgEJAQAAAA==.',
Na='Naiyah:BAAALgAFFAEJAQAAAA==.Namelesskin:BAAALgAECgQJBAAAAA==.Nanoko:BAABLgAECn8rAAIgAAkJfyPSAQAKAwAgAAkJfyPSAQAKAwAAAA==.Nayasylpha:BAABLgAECn8mAAIiAAgJxhzxDwCdAgAiAAgJxhzxDwCdAgAAAA==.Nazara:BAAALgADCgYJBgAAAA==.',
Ne='Neekage:BAAALgADCgEJAQAAAA==.Neown:BAAALgAECgYJDgABLgAECggJJgAVAMAdAA==.Nephertiti:BAAALgADCgYJCgAAAA==.Neuro:BAABLgAECn8sAAIMAAkJMSHECwDDAgAMAAkJMSHECwDDAgAAAA==.Newxexhu:BAAALgAECgQJBAAAAA==.',
Ni='Nicolico:BAAALgADCgcJBwAAAA==.Nictamom:BAAALgAECgUJDQAAAA==.Nirri:BAAALgAECgcJCAAAAA==.Nishendra:BAABLgAECn8aAAIRAAkJix39BgDQAgARAAkJix39BgDQAgAAAA==.Nitama:BAAALgADCgYJBwAAAA==.Nitefall:BAABLgAECn8dAAMCAAgJuQ3ILwCOAQACAAgJuQ3ILwCOAQAGAAYJ+wblIAD2AAAAAA==.Nitezilla:BAAALgAECgQJBAAAAA==.',
No='Noblok:BAAALgAECgQJBQAAAA==.Nocando:BAAALgAFFAEJAQAAAA==.Nofeetpicsyo:BAABLgAECn8oAAIWAAgJmwoNHQBTAQAWAAgJmwoNHQBTAQAAAA==.Nootella:BAABLgAECn8UAAIIAAYJlSInHgAlAgAIAAYJlSInHgAlAgABLgAECgkJGwAlAIwXAA==.Norgoma:BAAALgAECgYJDwAAAA==.Normmarry:BAABLgAECn8WAAMDAAYJmyJlSQAGAgADAAUJTyNlSQAGAgAFAAEJzR+NKABbAAAAAA==.Notybynature:BAAALgADCgIJAgAAAA==.',
Nu='Nuriel:BAABLgAECn8cAAIWAAgJ7xkJGwAGAgAWAAgJ7xkJGwAGAgAAAA==.',
Ny='Nylinu:BAAALgADCgQJBAABLgAFFAMJBQASAK8QAA==.Nylinuya:BAAALgAECgYJDAABLgAFFAMJBQASAK8QAA==.Nyteskye:BAAALgAECgEJAgAAAA==.Nyxoblivion:BAAALgADCgcJEQAAAA==.',
['Nî']='Nîco:BAABLgAECn8mAAIVAAgJwB3wGABwAgAVAAgJwB3wGABwAgAAAA==.',
Ob='Obsydia:BAAALgADCgcJDQAAAA==.',
Oc='Octin:BAABLgAECn8fAAMiAAgJMQ5cGgBiAQAiAAgJ3Q1cGgBiAQAgAAEJWBXBeAA5AAAAAA==.',
Ok='Okowilly:BAAALgADCgcJCgAAAA==.',
Ol='Oline:BAABLgAECn8qAAIBAAgJIhi5HAAEAgABAAgJIhi5HAAEAgAAAA==.',
Om='Ommnom:BAAALgAECgQJBAABLgAECgkJMAARADMXAA==.',
On='Oneall:BAABLgAECn8nAAIUAAgJlhSqEQC8AQAUAAgJlhSqEQC8AQAAAA==.Onehit:BAAALgAECgIJBAAAAA==.Onlyspells:BAABLgAECn8WAAMMAAgJYwmvpwCKAQAMAAgJYwmvpwCKAQAKAAEJnAELEgAgAAAAAA==.',
Oo='Oomcrit:BAAALgAECgUJCQAAAA==.Oonaki:BAABLgAECn8lAAIOAAkJHxhjCQDpAQAOAAkJHxhjCQDpAQAAAA==.',
Or='Oreoz:BAAALgADCgUJBQAAAA==.',
Ot='Othin:BAABLgAECn8ZAAIVAAgJKRtVDgBrAgAVAAgJKRtVDgBrAgAAAA==.Ottoshock:BAAALgAECgEJAQAAAA==.',
Pa='Painloa:BAABLgAECn8ZAAMkAAcJrgbHCQD9AAAkAAcJrgbHCQD9AAANAAYJZwFc7wCfAAAAAA==.Pam:BAAALgADCgYJCgAAAA==.Panacéa:BAABLgAECn8cAAIlAAkJ5A7dHACuAQAlAAkJ5A7dHACuAQAAAA==.Pandadance:BAAALgAECgcJEwAAAA==.Pandakill:BAAALgAECgUJBgAAAA==.Pandanimal:BAAALgAECgEJAgAAAA==.Pandar:BAAALgAECgQJBAAAAA==.Pandaxi:BAAALgAECgEJAQABLgAECgcJFwADAPcZAA==.Pandrael:BAAALgADCgMJAwAAAA==.Paotah:BAAALgAECgEJAQAAAA==.Papaganu:BAAALgADCgYJCQABLgAECgYJDQAJAAAAAA==.Papagenu:BAAALgAECgYJCAABLgAECgYJDQAJAAAAAA==.Papsfear:BAAALgADCgQJBAAAAA==.Paradoxx:BAABLgAECn8sAAIMAAkJLiNABQAfAwAMAAkJLiNABQAfAwAAAA==.',
Pe='Petrogris:BAAALgADCgUJBQAAAA==.',
Ph='Phelefica:BAAALgAECgUJBwAAAA==.',
Pm='Pmac:BAAALgAECgUJDAABLgAECgUJEgAaAC4PAA==.',
Po='Poggie:BAAALgAECgQJBQAAAA==.Pointybrows:BAAALgAECgEJAgAAAA==.Poppé:BAAALgAECgMJAwAAAA==.Porkfu:BAAALgADCgQJBAAAAA==.Potroaster:BAAALgAECgEJAQAAAA==.Powerflower:BAAALgADCgYJBwAAAA==.',
Pr='Primerecall:BAAALgAECgEJAQAAAA==.Professorson:BAAALgADCgEJAQAAAA==.Proteinbar:BAAALgADCgQJBAABLgAECgMJBAAJAAAAAA==.',
Pu='Punishment:BAAALgADCgYJCwAAAA==.Putresca:BAAALgADCgkJCQAAAA==.',
Py='Pyroheart:BAABLgAECn8eAAMbAAgJWx6TAQBiAgAbAAgJWx6TAQBiAgABAAIJHwzosABhAAAAAA==.',
Qa='Qai:BAABLgAECn8iAAMEAAgJkw+ZFwBEAQAEAAUJ7BaZFwBEAQALAAgJNgcwFwCqAAAAAA==.',
Qu='Quelestraza:BAABLgAECn8YAAIRAAYJjhJNDwBLAQARAAYJjhJNDwBLAQAAAA==.',
Ra='Raewyck:BAABLgAECn8oAAICAAgJ3xS6LQD8AQACAAgJ3xS6LQD8AQAAAA==.Ragar:BAAALgAECgUJBQABLgAFFAMJBwATAG4ZAA==.Raginbull:BAABLgAECn8dAAIeAAcJTxZ3DQCLAQAeAAcJTxZ3DQCLAQAAAA==.Raginganja:BAAALgADCgMJAwAAAA==.Ragingmaze:BAAALgAECggJEgAAAA==.Rainburrow:BAAALgAECgQJBAAAAA==.Raptormortis:BAABLgAECn8lAAMHAAgJ9BuDCQBCAgAHAAgJ9BuDCQBCAgAfAAYJ4xN6LQBfAQAAAA==.Raskolnikòv:BAAALgADCgQJBAABLgAECgcJDgAJAAAAAA==.Raskolniköv:BAAALgAECgcJDgAAAA==.Raskolnikøv:BAAALgADCgcJBgABLgAECgcJDgAJAAAAAA==.Rawd:BAAALgADCgIJAgAAAA==.Rayjin:BAAALgAECgYJBgABLgAECgcJDgAJAAAAAA==.Raylen:BAAALgAECgYJBgAAAA==.',
Re='Reckz:BAAALgADCgQJCAAAAA==.Redrockk:BAAALgAECgEJAQAAAA==.Regarr:BAAALgADCgEJAQABLgADCgYJBgAJAAAAAA==.Reinitia:BAAALgAECgIJAgAAAA==.Rellic:BAAALgAECgEJAQAAAA==.Remy:BAAALgAECgcJCQAAAA==.Renkagisa:BAAALgADCgcJBwAAAA==.Renku:BAAALgAECgQJEgAAAA==.Retana:BAAALgAECgQJBQAAAA==.',
Rh='Rhinn:BAAALgAECgYJDgAAAA==.Rhythm:BAAALgAECgYJBgAAAA==.',
Ri='Rickypeepee:BAAALgAECgQJBgAAAA==.Ritsuyi:BAAALgADCgYJBgABLgAECgMJAwAJAAAAAA==.Ritualbeef:BAAALgADCgMJAwABLgAECgcJAwAJAAAAAA==.Riven:BAAALgAECggJDgAAAA==.',
Ro='Roarbear:BAAALgAECgcJDAAAAA==.Roastedz:BAAALgAECgYJEQAAAA==.Rolánd:BAAALgADCgkJCQAAAA==.Roomi:BAABLgAECn8xAAIdAAkJxxu6AQCvAgAdAAkJxxu6AQCvAgAAAA==.Roowar:BAAALgAECgMJBQABLgAECggJJgAXAKcfAA==.Rorié:BAAALgADCggJDAAAAA==.Rorthu:BAAALgAECgYJBgAAAA==.Roru:BAAALgAECgYJEwABLgAECggJHAABAFQSAA==.Rozie:BAAALgAECgQJBAAAAA==.',
Ru='Rukélie:BAAALgAECgYJBgAAAA==.Ruxman:BAAALgAECgEJAQAAAA==.',
Ry='Ry:BAAALgAECgkJDwAAAA==.Ryanna:BAAALgAECgMJAwAAAA==.Rygon:BAAALgADCgMJAwAAAA==.Rymax:BAAALgADCgkJCQAAAA==.Ryy:BAAALgAECgYJBwAAAA==.',
['Ræ']='Rædiêncë:BAAALgAECgYJDQAAAA==.',
['Rò']='Ròó:BAABLgAECn8mAAQXAAgJpx/oCAACAwAXAAgJhx/oCAACAwAmAAMJLB5+FAC1AAAnAAIJiiP+DgBlAAAAAA==.',
Sa='Saevio:BAABLgAECn8cAAINAAgJ4he6HgAQAgANAAgJ4he6HgAQAgAAAA==.Sallean:BAAALgAECgEJAQAAAA==.Sanlorastik:BAAALgAECgEJAQAAAA==.Saoikingston:BAEALgAECgYJBQABLgAECgYJDwAJAAAAAA==.Sarayu:BAAALgADCgcJDQAAAA==.Sashimi:BAABLgAECn8hAAMNAAgJwRlQQgAwAgANAAgJwRlQQgAwAgAkAAQJgREyDQCyAAAAAA==.Saso:BAAALgAECgEJAQAAAA==.Sassyjay:BAAALgAECgcJBgAAAA==.Sassyuwu:BAACLgAFFH8FAAIIAAMJ/hUIDgD3AAAIAAMJ/hUIDgD3AAAuAAQKfxcAAggACAnGJWMEACcDAAgACAnGJWMEACcDAAAA.',
Sc='Scarlet:BAAALgADCgEJAQAAAA==.Schbag:BAAALgAECgMJBAAAAA==.Scotchnsoda:BAACLgAFFH8OAAMYAAQJPgnVDAACAQAYAAQJPgnVDAACAQAlAAEJJgNrKgA7AAAuAAQKfx8AAxgACAl1EngpAKYBABgACAl1EngpAKYBABYAAQlyAM1rABoAAAAA.Scrives:BAAALgAECgYJDAAAAA==.Scrubiclese:BAAALgAECgQJBAAAAA==.',
Se='Seldaren:BAAALgAECgUJCwAAAA==.Selenegosa:BAABLgAECn8fAAMcAAgJkxXABgBVAQAcAAYJCRfABgBVAQAPAAYJLBC2LgDrAAAAAA==.Seran:BAABLgAECn8UAAICAAgJuh5NLQCZAQACAAgJuh5NLQCZAQAAAA==.Serenade:BAABLgAECn8pAAIUAAgJxxFrFACeAQAUAAgJxxFrFACeAQAAAA==.Severyne:BAABLgAECn8oAAIVAAgJISUVBQA8AwAVAAgJISUVBQA8AwAAAA==.',
Sh='Shadowchad:BAAALgADCgUJCQAAAA==.Shadowmeld:BAAALgAECgYJDQAAAA==.Shadowpump:BAAALgAECgIJAgAAAA==.Shadyhealer:BAAALgAECgEJAQAAAA==.Shaile:BAAALgAECgIJAgAAAA==.Shamanu:BAAALgAECgcJEQABLgAECgcJGAADAGcjAA==.Shamsel:BAABLgAECn8bAAIWAAYJhgtTJgASAQAWAAYJhgtTJgASAQAAAA==.Shaunpj:BAAALgAECgMJBAAAAA==.Shermlock:BAAALgAECgIJAgAAAA==.Shiftychiz:BAACLgAFFH8WAAILAAUJRBegAwAaAQALAAUJRBegAwAaAQAuAAQKfyUAAgsACQnwIEICABEDAAsACQnwIEICABEDAAAA.Shinpaku:BAAALgADCgIJAgAAAA==.Shiéld:BAAALgAECgcJEAAAAA==.Shobogenzo:BAAALgADCgMJAwAAAA==.Shockcaller:BAAALgAECgQJDAAAAA==.Shorin:BAAALgADCgYJCwAAAA==.Showtooltip:BAAALgAECgYJEQAAAA==.Shulla:BAABLgAECn8sAAIVAAgJSCUFBABQAwAVAAgJSCUFBABQAwAAAA==.Shweatyballs:BAABLgAECn8XAAIMAAYJWhswWgBgAQAMAAYJWhswWgBgAQAAAA==.',
Si='Sidetrax:BAAALgADCgQJBAAAAA==.Silran:BAABLgAECn8WAAIDAAcJ+AzwewD0AAADAAcJ+AzwewD0AAAAAA==.Silverwings:BAAALgADCgEJAQAAAA==.Simmara:BAABLgAECn8YAAMCAAcJ+g/lRgCWAQACAAcJ+g/lRgCWAQAGAAQJggSEJACmAAAAAA==.Sinner:BAECLgAFFH8TAAIYAAYJ+B2NAAA4AgAYAAYJ+B2NAAA4AgAuAAQKfxoAAxgACQkYHdMHAM4CABgACQkYHdMHAM4CABYAAwnuAw1ZAFcAAAAA.',
Sk='Skaboodle:BAAALgAECgQJBAABLgAFFAYJFgAeAN0lAA==.Skruff:BAAALgAECgIJAwAAAA==.',
Sl='Slamuraijack:BAAALgAECgUJAgAAAA==.Slayngin:BAAALgAECgQJCAABLgAECgUJCAAJAAAAAA==.Sleepydeputy:BAAALgAECgUJBwAAAA==.Sleetwoodmac:BAAALgAECgYJCAAAAA==.',
Sm='Smeggsbenny:BAAALgADCgQJBAABLgADCgYJBgAJAAAAAA==.',
So='Solaris:BAAALgADCgcJCwAAAA==.Solstica:BAAALgAECgIJAgAAAA==.Sora:BAAALgAECgEJAQAAAA==.',
Sp='Sparklemeow:BAAALgADCgEJAQAAAA==.Spiritualone:BAABLgAECn8bAAIFAAgJhxQRCQC3AQAFAAgJhxQRCQC3AQAAAA==.',
Sq='Squishly:BAAALgAECgQJCAAAAA==.',
St='Stanmarshh:BAAALgADCgEJAQAAAA==.Staydown:BAAALgADCgEJAgAAAA==.Steelrib:BAAALgAECgYJDgAAAA==.Stogienuna:BAAALgADCgYJBgAAAA==.Stonystark:BAAALgAECgEJAQAAAA==.Straam:BAACLgAFFH8PAAIfAAQJ3hNXFQAcAQAfAAQJ3hNXFQAcAQAuAAQKfzEAAh8ACQnYHRYOAKkCAB8ACQnYHRYOAKkCAAAA.Stupidity:BAAALgAECgYJBgAAAA==.Støney:BAABLgAECn8nAAIMAAcJtA9IVgBqAQAMAAcJtA9IVgBqAQAAAA==.',
Su='Subatronic:BAAALgAECgEJAQABLgAFFAYJFgAeAN0lAA==.Subroutine:BAABLgAECn8WAAIQAAgJHh/uDgDKAgAQAAgJHh/uDgDKAgABLgAFFAYJFgAeAN0lAA==.Subtractive:BAACLgAFFH8WAAIeAAYJ3SXiAAAgAgAeAAYJ3SXiAAAgAgAuAAQKfxsAAh4ACAmmJiQBAIYDAB4ACAmmJiQBAIYDAAAA.Superiorha:BAAALgAECgYJBgAAAA==.',
Sw='Swagchamp:BAAALgADCgQJBQABLgAECgMJBAAJAAAAAA==.Swodaem:BAAALgADCgQJBAAAAA==.',
Sx='Sx:BAACLgAFFH8FAAIMAAIJ2SHHMwDKAAAMAAIJ2SHHMwDKAAAuAAQKfyIAAgwACQk5I7oFAKcDAAwACQk5I7oFAKcDAAAA.',
Sy='Sylthara:BAABLgAECn8ZAAIfAAYJsRQiLQBhAQAfAAYJsRQiLQBhAQAAAA==.Syrellis:BAAALgAECgEJAgAAAA==.',
['Så']='Såcred:BAAALgADCggJDwAAAA==.',
Ta='Taenggu:BAABLgAECn8kAAIjAAgJwhbEBADXAQAjAAgJwhbEBADXAQAAAA==.Tahle:BAAALgAECgIJAgAAAA==.Takki:BAAALgAECgIJAgAAAA==.Talethia:BAAALgAECgQJCQAAAA==.Tartarus:BAAALgAECgMJAwAAAA==.Tavin:BAAALgAECgUJBQAAAA==.Tazchem:BAAALgAECgQJBQAAAA==.',
Te='Techboar:BAAALgAECgEJAQAAAA==.Teinuya:BAACLgAFFH8FAAMSAAMJrxDlAQD5AAASAAMJUxDlAQD5AAABAAIJMAusaACBAAAuAAQKfykABBsACAmRHQUMAAICABsABgkTHQUMAAICABIABgmAHNAKAI8BAAEABAkCFzhdABgBAAAA.Teivel:BAAALgADCgYJBgAAAA==.Tekorgx:BAAALgADCgkJJwAAAA==.Tenderfiddle:BAABLgAECn8UAAIBAAYJ7RZiPwBsAQABAAYJ7RZiPwBsAQAAAA==.Tenochitilan:BAAALgAECggJDQAAAA==.Tenuous:BAAALgAECgUJCgAAAA==.Teregor:BAAALgADCgEJAQAAAA==.',
Th='Thainir:BAAALgAECgIJAgABLgAECggJLAAVAEglAA==.Thanar:BAAALgADCgEJAQAAAA==.Thisistheway:BAABLgAECn8mAAIeAAkJhhmfBABoAgAeAAkJhhmfBABoAgABLgAFFAMJCwARANEZAA==.Thoorz:BAAALgAECgMJAwAAAA==.Thornman:BAAALgADCgcJBwAAAA==.Thorzy:BAAALgAECgYJEgABLgAECgMJAwAJAAAAAA==.Thothh:BAAALgAECgUJEQAAAA==.Thraxacious:BAACLgAFFH8FAAIEAAMJDwteBQD3AAAEAAMJDwteBQD3AAAuAAQKfyAAAgQACAm4GGkGAN8BAAQACAm4GGkGAN8BAAAA.Thulcandra:BAABLgAECn8UAAIMAAYJxB/WYwARAgAMAAYJxB/WYwARAgAAAA==.Thulsadoomm:BAABLgAECn8VAAIOAAYJphySEQDyAQAOAAYJphySEQDyAQAAAA==.Thundermay:BAABLgAECn8XAAIfAAYJJRM+NAA7AQAfAAYJJRM+NAA7AQAAAA==.',
Ti='Tibremix:BAAALgADCgYJBgAAAA==.Tiduss:BAABLgAECn8UAAIeAAYJBQlbIgCrAAAeAAYJBQlbIgCrAAAAAA==.Tigó:BAABLgAECn8bAAIDAAgJWBxvFwA/AgADAAgJWBxvFwA/AgAAAA==.Tigölebittie:BAABLgAECn8bAAMVAAgJvxIcIQC9AQAVAAgJvxIcIQC9AQAUAAEJyxi+dgBIAAAAAA==.Tinkerrbella:BAABLgAECn8WAAQCAAcJvQ3wUwBsAQACAAcJvQ3wUwBsAQAQAAUJFgISbQCKAAAGAAIJtQH/NgBLAAABLgAFFAYJDgACAP8KAA==.Tireliaa:BAAALgAECgUJCAAAAA==.Tizzymami:BAAALgADCgQJBAAAAA==.',
Tj='Tjnewt:BAAALgADCgkJCQAAAA==.',
To='Toatsie:BAAALgAECgcJEwAAAA==.Toyotathon:BAAALgADCgYJBgAAAA==.',
Tr='Trafalgour:BAAALgADCgMJAwAAAA==.Traxal:BAAALgAECgcJBQAAAA==.Trumpybear:BAABLgAECn8XAAIDAAcJ9xn2UQDrAQADAAcJ9xn2UQDrAQAAAA==.',
Ts='Tsun:BAABLgAECn8jAAMoAAgJSBnPBQAQAgAoAAgJSBnPBQAQAgAeAAEJugvJNQA1AAAAAA==.',
Ty='Tyys:BAAALgADCgMJAwAAAA==.',
['Tø']='Tønka:BAAALgAECgcJCgABLgAECgcJGAADAGcjAA==.',
Ud='Uddertrouble:BAEBLgAECn8ZAAICAAYJZRdTTACEAQACAAYJZRdTTACEAQAAAA==.',
Uf='Ufos:BAAALgADCggJHgAAAA==.',
Ui='Ui:BAAALgADCgUJBQABLgAFFAIJBQAMANkhAA==.',
Ul='Ulfgrim:BAAALgADCgEJAQAAAA==.',
Un='Uncletat:BAABLgAECn8qAAQYAAgJuiQoAgApAwAYAAgJnyQoAgApAwAlAAYJmCFRDwBJAgAWAAEJHRSiTQA/AAAAAA==.',
Ur='Urmada:BAABLgAECn8gAAIMAAgJhArLTQCAAQAMAAgJhArLTQCAAQAAAA==.Urmami:BAABLgAECn8cAAIBAAgJcxIvKgC8AQABAAgJcxIvKgC8AQAAAA==.',
Ut='Uthil:BAAALgADCgQJBAAAAA==.',
Uz='Uzui:BAAALgAECgYJBwAAAA==.',
Va='Vahnt:BAABLgAECn8lAAIfAAgJgRd2IAAcAgAfAAgJgRd2IAAcAgAAAA==.Valkon:BAAALgADCgYJBgAAAA==.Vallissrya:BAABLgAECn8rAAIDAAkJLh57EQBuAgADAAkJLh57EQBuAgAAAA==.Vampire:BAAALgAECggJDAAAAA==.Vampyre:BAACLgAFFH8ZAAIOAAcJRRcUAwC2AQAOAAcJRRcUAwC2AQAuAAQKfxgAAg4ACQmaIfgCADQDAA4ACQmaIfgCADQDAAAA.Vanadie:BAAALgAECgYJBgAAAA==.Vanta:BAAALgADCgcJDQAAAA==.Vargmal:BAAALgADCgEJAgAAAA==.',
Ve='Velo:BAAALgAECgMJAwAAAA==.Veloboom:BAAALgAECgMJAwAAAA==.Vendettá:BAAALgAECgQJDgAAAA==.Vengeta:BAAALgADCgQJBAAAAA==.Venomflare:BAAALgAECgQJBAAAAA==.',
Vi='Vishontey:BAAALgADCggJCAAAAA==.Vitaminn:BAABLgAECn8dAAQDAAgJehqWGAA2AgADAAgJehqWGAA2AgAIAAIJTwZeigBUAAAFAAEJnBf4PgBCAAAAAA==.Vithiris:BAAALgADCgYJBgAAAA==.',
Vk='Vk:BAAALgAECgcJBwAAAA==.',
Vl='Vlaen:BAAALgAECgMJAwAAAA==.',
Vo='Voidreaper:BAAALgADCgEJAwAAAA==.Votum:BAAALgAECgMJAwAAAA==.',
Vy='Vyndanin:BAAALgAECgkJDgAAAA==.Vynora:BAAALgAECgkJBwAAAA==.',
Wa='Wafflez:BAAALgAECgcJBwAAAA==.Walterlight:BAAALgAECgEJAQAAAA==.Warlockd:BAAALgADCgUJBQAAAA==.Wazoshao:BAAALgADCgIJAgAAAA==.',
We='Welios:BAAALgAECgMJBgAAAA==.',
Wh='Wheataid:BAAALgADCggJDQAAAA==.',
Wi='Wilhedin:BAACLgAFFH8HAAITAAMJbhlMDwARAQATAAMJbhlMDwARAQAuAAQKfzQAAygACQkgJR4BAAADACgACQmbIx4BAAADABMABwmwJZoNAOkCAAAA.Windente:BAABLgAECn8dAAMCAAgJMxZeLQCZAQACAAcJihZeLQCZAQAQAAQJ/Qj9ZgCjAAAAAA==.Wing:BAEBLgAFFH8FAAIDAAIJUiKgOQDFAAADAAIJUiKgOQDFAAABLgAFFAYJEwAYAPgdAA==.Wiseau:BAABLgAECn8ZAAMCAAgJ0hdiHQDsAQACAAgJ0hdiHQDsAQAQAAEJ4wMAlAAmAAAAAA==.',
Wo='Wolfer:BAAALgADCgEJAQAAAA==.Wong:BAAALgAECgEJBAAAAA==.',
Wu='Wulfnbolt:BAAALgADCgIJAgAAAA==.Wumbology:BAAALgAECgcJAQAAAA==.',
Wy='Wyon:BAAALgAECggJFgAAAQ==.',
Xu='Xuen:BAAALgAECgYJEgAAAA==.',
Yo='Yokog:BAAALgAECgMJBQAAAA==.',
Za='Zaeluna:BAABLgAECn8mAAILAAgJYyB1AwDWAgALAAgJYyB1AwDWAgAAAA==.Zanikan:BAAALgAECgkJAQAAAA==.Zanzer:BAAALgAECgIJBAAAAA==.Zathara:BAAALgAECgkJEAAAAA==.',
Ze='Zeevoid:BAAALgADCgEJAQAAAA==.Zephiron:BAAALgADCgcJDgAAAA==.Zeroshot:BAAALgAECgEJBAAAAA==.Zeshom:BAAALgAECgQJBAAAAA==.',
Zp='Zpazzie:BAAALgAECgIJAwAAAA==.',
Zu='Zuluk:BAAALgADCgUJBQAAAA==.',
Zy='Zynblaster:BAAALgAECgEJAQAAAA==.',
['Zö']='Zörö:BAAALgAFFAIJBAAAAA==.',
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

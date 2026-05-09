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

local lookup = {'Unknown-Unknown','Shaman-Restoration','Mage-Frost','Paladin-Holy','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Paladin-Protection','Warlock-Demonology','Paladin-Retribution','Monk-Brewmaster','Shaman-Elemental','DeathKnight-Unholy','DeathKnight-Frost','Druid-Feral','Hunter-Survival','Rogue-Assassination','Monk-Windwalker','Warlock-Affliction','Warlock-Destruction','DemonHunter-Havoc','Priest-Holy','Priest-Shadow','Priest-Discipline','DeathKnight-Blood','Hunter-BeastMastery','Druid-Guardian','DemonHunter-Devourer','Warrior-Arms','Warrior-Fury','Hunter-Marksmanship','Rogue-Subtlety','Rogue-Outlaw','Druid-Restoration','Warrior-Protection',}
local provider = {region='US',realm='Coilfang',name='US',type='weekly',zone=46,date='2026-05-08',data={Ae='Aendean:BAAALgAECgEJAQAAAA==.',
Am='Amethyne:BAAALgADCgMJAwAAAA==.',
An='Anabell:BAAALgADCgcJDwABLgAECgEJAgABAAAAAA==.',
Ar='Arckane:BAAALgAECgEJAQAAAA==.Arcueid:BAABLgAECn8jAAICAAgJ4h8fFwBdAgACAAgJ4h8fFwBdAgAAAA==.',
As='Asmadeus:BAAALgAECgEJAQAAAA==.',
Ay='Ayda:BAABLgAECn8zAAIDAAkJDyPbBAAoAwADAAkJDyPbBAAoAwAAAA==.',
Ba='Bartholdson:BAAALgAECgYJDAAAAA==.',
Be='Bearlydidit:BAAALgADCgQJBAAAAA==.Beloc:BAAALgAECggJAgAAAA==.Berzerkirz:BAAALgADCgYJBgAAAA==.',
Bl='Blacksnow:BAAALgADCgEJAQAAAA==.Blcksnowcrow:BAABLgAECn8dAAIEAAkJ7xmdCQB3AgAEAAkJ7xmdCQB3AgAAAA==.',
Bo='Bonfire:BAABLgAECn8kAAQFAAgJASORBgBzAgAFAAgJASORBgBzAgAGAAUJ2yDCDQCyAAAHAAIJSgKDRABLAAABLgAFFAEJAQABAAAAAA==.Boochili:BAABLgAECn8vAAIIAAkJiiYOAACKAwAIAAkJiiYOAACKAwAAAA==.',
Br='Braveling:BAABLgAECn8YAAIJAAgJNgzBOACDAQAJAAgJNgzBOACDAQAAAA==.',
Bu='Bubblës:BAAALgAECgQJBgABLgAECggJHwADAAgiAA==.',
Ca='Carezarsh:BAAALgADCgMJAQAAAA==.',
Ch='Charlie:BAACLgAFFH8SAAMKAAQJxyPFCACRAQAKAAQJxyPFCACRAQAIAAEJQCNaCQBnAAAuAAQKfzAAAwoACQm5JegEAAEDAAoACQm5JegEAAEDAAgAAwlgGD8oAF0AAAAA.Chicken:BAAALgADCgMJAwABLgAECggJGwALAFcOAA==.',
Cr='Cruel:BAAALgADCgEJAQAAAA==.',
['Cä']='Cätîáñdrïà:BAABLgAECn9LAAMCAAkJzR1cCACmAgACAAkJzR1cCACmAgAMAAUJaA5vNQDZAAAAAA==.',
Da='Daniedk:BAABLgAECn8jAAINAAgJBRNCOQCUAQANAAgJBRNCOQCUAQAAAA==.Daphanim:BAAALgADCgYJCgAAAA==.Darctotem:BAAALgAECgUJCwAAAA==.',
De='Deathtouch:BAACLgAFFH8HAAMNAAMJRRw9TgDzAAANAAMJRRw9TgDzAAAOAAIJQBCXBgCfAAAuAAQKfxsAAw0ACAlEI2YQAHsCAA0ACAnFImYQAHsCAA4AAQkOHfsSAFMAAAAA.Devona:BAABLgAECn8dAAMEAAgJ5hsOFgDeAQAEAAcJthwOFgDeAQAKAAcJmAx1UgBPAQAAAA==.',
Di='Didit:BAAALgADCgcJBwAAAA==.Dingledangle:BAABLgAECn8VAAIPAAcJAhIEDABYAQAPAAcJAhIEDABYAQAAAA==.',
Dj='Djindor:BAAALgADCgUJBQAAAA==.',
Dr='Draconix:BAAALgAECgQJBAABLgAECgUJBQABAAAAAA==.Dragonzordd:BAAALgADCgQJBQABLgAECgYJFAAQAAwiAA==.Dragoonnick:BAABLgAECn8xAAIRAAgJHR0VBAB0AgARAAgJHR0VBAB0AgAAAA==.',
Es='Esh:BAAALgAECgYJCAAAAA==.',
Eu='Euphal:BAABLgAECn8mAAIJAAgJ2xLBLwCkAQAJAAgJ2xLBLwCkAQAAAA==.',
Ey='Eyekicku:BAABLgAECn8cAAISAAgJciAcBQCPAgASAAgJciAcBQCPAgAAAA==.',
Fe='Feldana:BAAALgAECgQJBAAAAA==.Fenicon:BAAALgAECgQJBQAAAA==.',
Fi='Fitz:BAAALgAECgQJBAAAAA==.Fitzwell:BAAALgADCgYJCQAAAA==.',
Fu='Fuyu:BAAALgAECgQJBAAAAA==.',
Gh='Ghost:BAAALgAECgMJBQAAAA==.',
Gr='Graycieden:BAAALgAECgYJBwAAAA==.',
Gu='Guldangit:BAACLgAFFH8dAAMJAAcJGhzQAQAZAgAJAAcJGhzQAQAZAgATAAEJAAA+AwBgAAAuAAQKfykAAwkACQnCI2oIAD4DAAkACQkBI2oIAD4DABQABAmOIi0aAHsBAAAA.',
Ha='Hanora:BAAALgAECgEJAQAAAA==.',
He='Hellspawn:BAABLgAECn8zAAIVAAkJxg4BDADBAQAVAAkJxg4BDADBAQAAAA==.',
Ho='Hojai:BAAALgADCgMJAwAAAA==.Holybeef:BAAALgAECgcJDQAAAA==.Holygrim:BAACLgAFFH8aAAIWAAcJ5yMgAACnAgAWAAcJ5yMgAACnAgAuAAQKfx0AAxYACAljJuABAFcDABYACAljJuABAFcDABcAAQk+CeZSADQAAAAA.Holyloa:BAAALgAECgMJAwAAAA==.Holypablo:BAABLgAECn8zAAQYAAkJER87AgAxAwAYAAkJER87AgAxAwAXAAQJaRS5LwDVAAAWAAQJrQuPXQC8AAAAAA==.Howii:BAABLgAECn81AAIZAAkJvSSIAABQAwAZAAkJvSSIAABQAwAAAA==.',
Im='Imperator:BAAALgAECgQJBAAAAA==.',
In='Inchworm:BAAALgAECgYJBgAAAA==.',
Is='Isabellaah:BAABLgAECn8bAAIaAAcJ9xI9NQB4AQAaAAcJ9xI9NQB4AQAAAA==.',
Je='Jellyfïsh:BAAALgAECgUJCgAAAA==.Jeraziah:BAAALgAECgUJDwABLgAECggJIwACAOIfAA==.',
Jo='Johnnyjr:BAAALgAECgkJEgAAAA==.',
Ke='Kelliz:BAAALgADCgcJCAAAAA==.',
Kh='Khaladin:BAAALgAECgYJEgAAAA==.',
La='Laggers:BAABLgAECn8jAAIbAAgJdhaMCgBxAQAbAAgJdhaMCgBxAQAAAA==.',
Li='Litbit:BAAALgAECgYJEAAAAA==.Litbitonme:BAAALgAECgMJAwAAAA==.Litt:BAAALgADCgkJCwAAAA==.Lizardwizard:BAAALgAECgEJAQAAAA==.',
Lo='Lockmantwo:BAAALgAECgcJAwAAAA==.Lostmoo:BAAALgAECgEJAQAAAA==.Lostunholy:BAABLgAECn8XAAINAAcJhCBaIgD8AQANAAcJhCBaIgD8AQAAAA==.Lovebug:BAAALgADCgcJBwAAAA==.',
Lu='Lunaardris:BAAALgAECgQJBQAAAA==.',
Ly='Lynxe:BAAALgAECgUJBQAAAA==.',
Ma='Maggikal:BAABLgAECn8XAAIDAAYJtAx7fwASAQADAAYJtAx7fwASAQAAAA==.',
Me='Megahottie:BAAALgADCgYJBgAAAA==.',
Mi='Mirant:BAAALgAECgUJDAAAAA==.',
Mo='Moretisha:BAAALgADCgYJBgAAAA==.',
Na='Nakwoo:BAAALgADCgMJAwAAAA==.',
On='One:BAAALgAECgEJAQAAAA==.',
Op='Opallea:BAABLgAECn8YAAMVAAgJoxueEQBRAgAVAAgJoxueEQBRAgAcAAQJ+wS6kQBrAAAAAA==.',
Pa='Pallyplay:BAAALgAECgEJAQAAAA==.',
Pb='Pballs:BAAALgADCgEJAQABLgAECgkJMwAYABEfAA==.',
Pe='Periodic:BAACLgAFFH8HAAICAAQJtyC1CwBuAQACAAQJtyC1CwBuAQAuAAQKfy4AAgIACQnlI/QAAJkDAAIACQnlI/QAAJkDAAAA.',
Pl='Platen:BAABLgAECn8cAAIaAAgJlA5HNAB8AQAaAAgJlA5HNAB8AQAAAA==.',
Po='Potter:BAABLgAECn8zAAIDAAkJwxzCEgCDAgADAAkJwxzCEgCDAgAAAA==.',
Ra='Raffa:BAABLgAECn8cAAISAAcJhhdIIgDDAQASAAcJhhdIIgDDAQAAAA==.Rakandei:BAAALgADCgMJAwAAAA==.Raptor:BAAALgAECgIJAgABLgAFFAEJAQABAAAAAA==.Rapunzel:BAAALgAECgkJAwAAAA==.Rataiga:BAAALgAECgYJEgAAAA==.',
Rh='Rheynah:BAABLgAECn8ZAAMdAAgJjQOFIAC4AAAdAAgJSAOFIAC4AAAeAAYJCQPiRgChAAAAAA==.',
Ri='Rimuna:BAAALgADCgUJBQAAAA==.Rinni:BAACLgAFFH8TAAIPAAYJBB9XAADQAQAPAAYJBB9XAADQAQAuAAQKfyYAAg8ACQkRJdwBAEUDAA8ACQkRJdwBAEUDAAAA.',
Ro='Rovintis:BAABLgAECn8mAAIdAAgJFBgPBgAHAgAdAAgJFBgPBgAHAgAAAA==.',
Ry='Rynne:BAAALgAECgcJEgAAAA==.',
Sa='Sansundertal:BAABLgAECn8wAAIHAAkJryJ+AgBJAwAHAAkJryJ+AgBJAwAAAA==.',
Se='Selissaroth:BAAALgAECgEJAQAAAA==.Sentinal:BAABLgAECn8cAAIZAAgJVRQyDgCPAQAZAAgJVRQyDgCPAQAAAA==.Sentinäl:BAAALgADCgIJAgAAAA==.Sephiro:BAAALgAECgQJBgAAAA==.',
Sh='Shamu:BAABLgAECn8VAAICAAgJfQ2tOwCTAQACAAgJfQ2tOwCTAQAAAA==.Shawner:BAAALgADCgMJAwAAAA==.Shy:BAAALgAECgIJAgAAAA==.',
Si='Silvertiger:BAABLgAECn8yAAMQAAkJ0xy/AgC7AgAQAAkJ0xy/AgC7AgAfAAcJgg+VPABsAQAAAA==.',
Sl='Slabbydabby:BAAALgAECgEJAQAAAA==.Sleeperbater:BAAALgADCgIJAgAAAA==.Sleeperdk:BAAALgAECgYJCwAAAA==.',
Sn='Snackyfraps:BAAALgADCgUJCAABLgAECgkJMwAYABEfAA==.Sneaki:BAABLgAECn8xAAQgAAkJaSLUAwCYAgAgAAkJuCDUAwCYAgAhAAgJ+xx0AQBmAgARAAEJwRwOFgBTAAAAAA==.Sniperanger:BAAALgADCgMJAwAAAA==.Snstr:BAABLgAECn8aAAQWAAYJbRfgLACTAQAWAAYJbRfgLACTAQAXAAQJ5gMbTQChAAAYAAIJkQhWTQBdAAAAAA==.',
So='Sorynia:BAAALgAECgUJDgAAAA==.Soul:BAAALgAECgEJAQAAAA==.Soulkid:BAAALgAECgQJBQAAAA==.',
St='Starta:BAACLgAFFH8IAAIcAAMJRhZMLwD0AAAcAAMJRhZMLwD0AAAuAAQKfxUAAhwACAmNIbMSACgCABwACAmNIbMSACgCAAAA.Startawar:BAABLgAECn8kAAIKAAgJxyPJCgCvAgAKAAgJxyPJCgCvAgAAAA==.',
Su='Sukii:BAAALgAECgUJBgAAAA==.Sulfuricvein:BAAALgAECgMJBQAAAA==.',
['Sø']='Sømebody:BAAALgAECgMJAwAAAA==.',
Ti='Tiana:BAAALgAECgkJBAAAAA==.',
To='Totemdaddy:BAAALgAECgEJAQAAAA==.Totemicdidit:BAAALgADCgMJAwAAAA==.Totemstorm:BAAALgAECgcJBwAAAA==.',
Tr='Traumatic:BAABLgAECn8UAAIeAAcJjRj2LwDvAQAeAAcJjRj2LwDvAQAAAA==.',
Tu='Tunny:BAAALgAECgYJCAAAAA==.Turnleft:BAABLgAECn8kAAIiAAgJcCU1AgBmAwAiAAgJcCU1AgBmAwAAAA==.',
Va='Vauntmonk:BAAALgADCgMJAwABLgAFFAQJCgAjAN4fAA==.',
Ve='Vercyv:BAAALgADCgkJEQAAAA==.Vevio:BAAALgAECgQJBAAAAA==.',
Vi='Video:BAAALgAECgEJAQAAAA==.Violet:BAABLgAECn8nAAINAAkJWx29CwCrAgANAAkJWx29CwCrAgAAAA==.Vishlock:BAABLgAECn8tAAMTAAkJ+RYQAgAaAgATAAkJ+RYQAgAaAgAJAAcJcA4DlAAwAQAAAA==.',
Vo='Voddie:BAABLgAECn8ZAAIMAAcJNwl1MQDsAAAMAAcJNwl1MQDsAAAAAA==.',
Wa='Waban:BAAALgAECgcJEwAAAA==.Walmarthas:BAAALgAECgYJBgABLgAECggJGAAFAEgVAA==.Wapta:BAAALgAFFAEJAQAAAA==.',
Wi='Wizwiztheliz:BAAALgAECgYJDwAAAA==.',
Wo='Wolf:BAABLgAECn8bAAILAAgJVw6RFwB7AQALAAgJVw6RFwB7AQAAAA==.Woof:BAAALgAECgIJAgAAAA==.',
Xy='Xynelle:BAAALgADCgcJCwAAAA==.',
Ya='Yahtzee:BAAALgAECgQJBwAAAA==.',
Yo='Youdidwhat:BAAALgADCgkJCQAAAA==.',
Za='Zaia:BAAALgAECgYJCwAAAA==.',
Ze='Zenithmage:BAAALgAECgcJDQAAAA==.',
['Ár']='Ártémes:BAAALgADCggJAgAAAA==.',
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

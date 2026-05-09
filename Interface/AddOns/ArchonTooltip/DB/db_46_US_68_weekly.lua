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

local lookup = {'Hunter-Survival','Warrior-Fury','Monk-Windwalker','Monk-Brewmaster','DemonHunter-Havoc','Priest-Discipline','Priest-Holy','Priest-Shadow','DeathKnight-Unholy','Hunter-BeastMastery','Paladin-Holy','Rogue-Subtlety','DeathKnight-Blood','Shaman-Elemental','Shaman-Enhancement','Hunter-Marksmanship','Paladin-Retribution','Druid-Balance','Shaman-Restoration','Mage-Frost','Paladin-Protection','Warlock-Demonology','Unknown-Unknown','Warrior-Protection','Warrior-Arms',}
local provider = {region='US',realm='Dethecus',name='US',type='weekly',zone=46,date='2026-05-08',data={Aa='Aashley:BAAALgAECgcJBwAAAA==.',
Al='Alistis:BAAALgADCgEJAQAAAA==.',
Am='Amutio:BAAALgAECgMJCwAAAA==.',
Ar='Arasis:BAABLgAECn8lAAIBAAgJYyUrAQBaAwABAAgJYyUrAQBaAwAAAA==.Arìel:BAAALgADCgYJBgAAAA==.',
As='Ashhlleyy:BAAALgAECgcJAQAAAA==.',
Ba='Balancing:BAAALgAECgIJAgAAAA==.Bamag:BAABLgAECn8eAAICAAgJgiLyBgA5AwACAAgJgiLyBgA5AwAAAA==.',
Bi='Bigmak:BAAALgAECgEJAQAAAA==.',
Br='Braellyn:BAAALgAECgUJCQAAAA==.',
Bu='Burnyou:BAAALgADCgYJCwAAAA==.',
Ce='Cenobité:BAABLgAECn8rAAMDAAgJqCSlAgDmAgADAAgJqCSlAgDmAgAEAAIJPxvocAB/AAAAAA==.Ceridemon:BAABLgAECn8ZAAIFAAgJaxBEEAB/AQAFAAgJaxBEEAB/AQAAAA==.',
Ch='Chingee:BAABLgAECn88AAMGAAkJLRmeCQChAgAGAAkJrBeeCQChAgAHAAgJiw49JgC6AQAAAA==.',
Co='Consarios:BAAALgAECgUJCAAAAA==.',
Cr='Croakadin:BAAALgADCgcJEAAAAA==.Crushers:BAAALgADCggJCAAAAA==.',
Cy='Cyraanden:BAACLgAFFH8IAAIDAAMJ7gxrEQDeAAADAAMJ7gxrEQDeAAAuAAQKfysAAwMACAmTGR8LAAgCAAMACAmTGR8LAAgCAAQAAgmrCJt6AFoAAAAA.Cyvus:BAABLgAECn8XAAMHAAgJRgNVQwArAQAHAAgJRgNVQwArAQAIAAYJPgmeOAAqAQAAAA==.',
Da='Dab:BAABLgAECn8sAAIJAAgJ9iNhCQDJAgAJAAgJ9iNhCQDJAgAAAA==.Daedara:BAAALgADCgUJBQAAAA==.Daggz:BAABLgAECn8hAAIKAAgJtR81EABTAgAKAAgJtR81EABTAgAAAA==.Dansgrundle:BAAALgAECgMJAwABLgAECgkJHgALABUaAA==.Darkhorse:BAABLgAECn8YAAIMAAcJVxmRGgAtAgAMAAcJVxmRGgAtAgAAAA==.Darkmer:BAABLgAECn8YAAIJAAYJ6gQXggDcAAAJAAYJ6gQXggDcAAAAAA==.',
De='Deathsnight:BAAALgAECgUJBwAAAA==.Derpy:BAAALgADCgYJCQAAAA==.Deynestta:BAAALgAECgIJBAAAAA==.',
Di='Dixiereaper:BAABLgAECn8VAAINAAkJahBnGgB+AQANAAkJahBnGgB+AQAAAA==.',
Dr='Droopin:BAAALgADCgYJBwAAAA==.',
Ds='Ds:BAAALgAECgYJCgAAAA==.Dsntdrptotem:BAABLgAECn8cAAMOAAkJjhDdLAADAQAPAAcJ2BF5DQAvAQAOAAYJbgvdLAADAQAAAA==.',
Dt='Dtothep:BAAALgAECgEJAQAAAA==.',
El='Elfangar:BAAALgADCgcJBwAAAA==.',
Ep='Epicamerican:BAAALgAECgEJAQAAAA==.',
Ff='Ffecanti:BAAALgAECgEJAwAAAA==.',
Fl='Floury:BAAALgAECgMJAwAAAA==.',
Ga='Gailen:BAAALgADCgkJDgAAAA==.',
Gi='Gideonn:BAAALgADCgMJAwAAAA==.',
Go='Gorber:BAAALgAFFAMJAwABLgAFFAcJGgAKAI4aAA==.Gorberfn:BAAALgAECgMJAwABLgAFFAcJGgAKAI4aAA==.',
Gr='Grimorn:BAACLgAFFH8aAAIJAAcJrCDxAABGAgAJAAcJrCDxAABGAgAuAAQKfykAAgkACQm/IcEDAJkDAAkACQm/IcEDAJkDAAAA.Grogvald:BAAALgAECgYJDgAAAA==.',
['Gø']='Gøober:BAACLgAFFH8aAAMKAAcJjhraAQDIAQAQAAYJ4RuWAwAPAgAKAAYJ+BnaAQDIAQAuAAQKfy8ABBAACQlpIYEDAG0DABAACQkUIYEDAG0DAAEABwmOITgGAE4CAAoAAQmHHVSgAFMAAAAA.',
Ha='Hadrick:BAAALgADCgYJBgAAAA==.',
He='Herax:BAABLgAECn8fAAIOAAgJ4hp8CgAyAgAOAAgJ4hp8CgAyAgAAAA==.',
Hi='Hidrógeno:BAACLgAFFH8FAAIRAAMJLgxCMgDuAAARAAMJLgxCMgDuAAAuAAQKfxcAAhEACAkkHsoxAFsCABEACAkkHsoxAFsCAAAA.',
Ho='Hoofartted:BAABLgAECn8pAAIPAAgJhR0DBQC9AgAPAAgJhR0DBQC9AgAAAA==.Horchata:BAAALgAECgMJCAAAAA==.Horndawg:BAAALgADCgkJHAAAAA==.',
Il='Illidara:BAAALgAECgMJAwAAAA==.',
Is='Istarìa:BAAALgADCgkJEAAAAA==.',
Jo='Jollyrancher:BAAALgADCgYJBgAAAA==.',
Ju='Judgejobrown:BAAALgAECgcJEwAAAA==.',
Kh='Khajiit:BAABLgAECn8WAAISAAcJ4R3fEQC5AQASAAcJ4R3fEQC5AQAAAA==.',
Ki='Kijana:BAABLgAFFH8EAAIKAAQJIR7iDQBiAQAKAAQJIR7iDQBiAQAAAA==.Kindraa:BAAALgADCgQJBAAAAA==.',
La='Lardpile:BAAALgADCgYJBgAAAA==.Lazaria:BAAALgAECgcJDQAAAA==.',
Le='Leveltwo:BAABLgAECn8lAAIBAAgJLhi4BwAvAgABAAgJLhi4BwAvAgAAAA==.',
Li='Litguine:BAAALgAECgQJBgAAAA==.Littlestar:BAABLgAECn8bAAIGAAYJHBTtFwB2AQAGAAYJHBTtFwB2AQAAAA==.',
Lo='Lockdnloadd:BAAALgADCgUJCAAAAA==.',
Lu='Lucyfurr:BAAALgADCgEJAQABLgAECggJJwATACUiAA==.Lunea:BAAALgAECgYJCgAAAA==.',
Ly='Lyraa:BAAALgADCgQJDQAAAA==.',
Ma='Marvel:BAAALgADCgkJEwAAAA==.Mattystaff:BAAALgADCgUJBQAAAA==.',
Me='Melanreu:BAAALgAECgEJAQAAAA==.',
My='Myrddraal:BAAALgADCgMJAwAAAA==.Mythicc:BAAALgAECgYJBwAAAA==.',
Na='Naenae:BAAALgAECgEJAQAAAA==.Nastybob:BAABLgAECn8gAAIJAAkJiBwJDgCTAgAJAAkJiBwJDgCTAgAAAA==.',
Ni='Nicobulus:BAAALgAECgcJEQAAAA==.Nightspell:BAAALgADCgIJAgAAAA==.',
No='Nor:BAAALgAECgYJEAAAAA==.',
['Nä']='Näota:BAAALgADCgEJAQAAAA==.',
Pa='Papanoellego:BAACLgAFFH8aAAIUAAcJLRo5AwBHAgAUAAcJLRo5AwBHAgAuAAQKfyIAAhQACQmsIzsDAMsDABQACQmsIzsDAMsDAAAA.',
Ph='Phcicoknight:BAAALgADCgYJBgAAAA==.Pheal:BAABLgAECn8fAAIJAAgJsBNoKgDSAQAJAAgJsBNoKgDSAQAAAA==.Phiend:BAAALgAECgQJCQAAAA==.Phlak:BAAALgAECgIJAgAAAA==.',
Pl='Pluvl:BAAALgAECgcJEwAAAA==.',
Qu='Quimby:BAAALgADCgcJDQAAAA==.',
Ra='Raign:BAAALgADCgMJAwAAAA==.',
Re='Reyla:BAAALgADCgIJAgABLgAFFAUJFwAMANUiAA==.',
Rh='Rhyze:BAAALgAECgYJCAAAAA==.',
Ri='Rivent:BAAALgAECgQJBgAAAA==.Rivia:BAABLgAECn8UAAIRAAgJuhfzQQAfAgARAAgJuhfzQQAfAgAAAA==.',
Ro='Royalmace:BAAALgAECgQJBAAAAA==.',
Sa='Safaridan:BAABLgAECn8eAAQLAAkJFRpVGQBIAgALAAkJFRpVGQBIAgAVAAUJVwxFHQCpAAARAAIJaQeVAAE3AAAAAA==.Sapphirre:BAAALgADCgcJDgAAAA==.Savsham:BAAALgADCgEJAQAAAA==.',
Sc='Scamp:BAAALgADCgQJBAAAAA==.Scrump:BAAALgAECgQJBQAAAA==.',
Sh='Shtick:BAAALgADCggJDQAAAA==.',
Si='Sienen:BAAALgAECgQJBAAAAA==.',
Sj='Sjk:BAABLgAECn8WAAIFAAgJXSCjBgD8AgAFAAgJXSCjBgD8AgAAAA==.',
Sl='Slabia:BAABLgAECn8VAAIRAAcJsCC3MQBcAgARAAcJsCC3MQBcAgAAAA==.Slashly:BAAALgAECgEJAwAAAA==.Sloan:BAAALgAECgUJCwAAAA==.',
Sp='Spektrum:BAAALgADCgEJAQAAAA==.',
St='Stacey:BAAALgAECgQJBAABLgAFFAgJJgAIAOMdAA==.Stepmom:BAAALgAFFAIJAgAAAA==.Stepsis:BAAALgAFFAIJBAAAAA==.Stiick:BAAALgADCgUJBQAAAA==.',
Sv='Svinehundt:BAABLgAECn8bAAIWAAcJVRbzMACgAQAWAAcJVRbzMACgAQAAAA==.',
Ta='Tabtok:BAAALgADCgcJDgAAAA==.Tanalin:BAAALgADCgMJAwABLgAECgcJGwAWAFUWAA==.Tanglebones:BAAALgAECgQJCAAAAA==.Tasty:BAAALgAECgEJAQABLgAFFAMJCQATALgcAA==.Taukra:BAAALgADCgYJBgAAAA==.',
To='Tore:BAAALgAECgYJDAAAAA==.',
Tr='Trazie:BAAALgAECgYJCQAAAA==.Trenn:BAAALgADCgkJCQABLgAECggJEgAXAAAAAA==.',
Un='Unsocial:BAAALgADCgQJBAAAAA==.',
Ve='Vecna:BAAALgAECgEJAQABLgAECgYJEAAXAAAAAA==.Vermi:BAAALgAECgIJAgAAAA==.',
Wa='Warcloud:BAAALgAECgcJEgAAAA==.Wartortle:BAABLgAECn8pAAMYAAYJMxuEFADEAQAYAAYJMxuEFADEAQAZAAEJoglEPgAyAAAAAA==.',
Wh='Whack:BAAALgAECgYJBgAAAA==.',
Ws='Wsedfgghj:BAAALgAECgYJCgAAAA==.',
Wu='Wu:BAAALgAECgIJAgAAAA==.Wulfgaz:BAAALgAECgYJCAAAAA==.',
Wy='Wyldhart:BAAALgAECgEJAQAAAA==.Wylf:BAAALgADCgcJBwAAAA==.',
Xt='Xtheleon:BAAALgADCgUJBQAAAA==.',
Ze='Zenn:BAAALgAECggJEgAAAA==.Zeroomega:BAAALgADCgMJAwAAAA==.Zerø:BAAALgADCgYJBgAAAA==.',
Zi='Zinthous:BAAALgAECgEJAQAAAA==.',
['Äl']='Ältäir:BAABLgAECn8fAAITAAgJhxgvGADwAQATAAgJhxgvGADwAQAAAA==.',
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

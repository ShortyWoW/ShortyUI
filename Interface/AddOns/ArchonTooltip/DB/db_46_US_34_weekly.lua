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

local lookup = {'Unknown-Unknown','Hunter-BeastMastery','Rogue-Assassination','Warrior-Fury','DeathKnight-Blood','Mage-Frost','Paladin-Retribution','Monk-Windwalker','Monk-Brewmaster','Warlock-Demonology','DemonHunter-Havoc','Rogue-Outlaw','Warlock-Destruction','DeathKnight-Unholy','Druid-Guardian','Druid-Feral','Monk-Mistweaver','DemonHunter-Devourer','DemonHunter-Vengeance','Druid-Restoration','Evoker-Preservation','Paladin-Holy','Rogue-Subtlety','Priest-Shadow','Priest-Holy','Priest-Discipline','Evoker-Augmentation','Paladin-Protection',}
local provider = {region='US',realm='BlackwaterRaiders',name='US',type='weekly',zone=46,date='2026-04-24',data={Ad='Adamonious:BAAALgADCgMJAwABLgAECggJEQABAAAAAA==.Adaware:BAAALgAECgMJAwAAAA==.Addieeboy:BAAALgADCgEJAQAAAA==.',
Ai='Aisha:BAAALgADCgEJAQAAAA==.',
Al='Alba:BAAALgAECgYJDgABLgAECggJGwACAP0cAA==.Aletta:BAAALgADCgQJCwAAAA==.Allast:BAAALgADCgYJDQAAAA==.',
An='Andezard:BAAALgAECgYJEwAAAA==.',
Aq='Aquâ:BAAALgADCgYJBgABLgAECgYJDwABAAAAAA==.',
Ar='Arianes:BAAALgAECgYJDQAAAA==.Arturias:BAAALgAECgYJEAAAAA==.',
At='Athenaowl:BAAALgAECgEJAQAAAA==.',
Au='Autofocus:BAAALgAECgYJEAAAAA==.',
Aw='Aweyna:BAAALgAECgYJCQAAAA==.Awisha:BAAALgADCgUJBQAAAA==.',
Ay='Ayanoriko:BAABLgAECn8mAAIDAAgJ0B1uAABeAgADAAgJ0B1uAABeAgAAAA==.',
Ba='Babaganoosh:BAAALgADCgcJBwAAAA==.Barracuda:BAAALgAECgYJBgAAAA==.',
Be='Benmonk:BAAALgADCgkJCQAAAA==.',
Bi='Bifur:BAAALgADCgkJDwAAAA==.Bigstones:BAABLgAECn8fAAIEAAgJGQyxCACVAQAEAAgJGQyxCACVAQAAAA==.',
Bl='Bluehydra:BAAALgADCgcJBwAAAA==.',
Bo='Bobbydigital:BAABLgAECn8XAAIFAAYJxBKtIgAsAQAFAAYJxBKtIgAsAQAAAA==.Bohd:BAAALgADCgIJAgAAAA==.Boneski:BAAALgAECgQJCwAAAA==.Booger:BAAALgAECgQJBAAAAA==.',
Br='Bracynn:BAAALgAECgQJBwAAAA==.Brudiclad:BAAALgAECgYJEwAAAA==.',
Bu='Butterfinger:BAAALgADCgQJBwAAAA==.',
Ca='Caimark:BAABLgAECn8UAAIGAAgJjAI43AA6AQAGAAgJjAI43AA6AQAAAA==.Calahan:BAABLgAECn8dAAIHAAgJqBr1CgDhAQAHAAgJqBr1CgDhAQAAAA==.',
Ch='Chakuneeai:BAAALgADCgYJBgAAAA==.Chikostix:BAAALgAECgQJCAAAAA==.Christae:BAAALgAECgcJEAAAAA==.',
Cl='Clydè:BAABLgAECn8uAAMIAAgJYxeVBAC3AQAIAAgJYxeVBAC3AQAJAAcJpg0SNwBvAQAAAA==.Cláncey:BAAALgAECgYJCQAAAA==.',
Co='Coachhazzard:BAAALgAECgQJCAAAAA==.Cocytus:BAAALgADCgIJAgABLgAECggJHgAKAG4YAA==.Combatant:BAAALgADCgYJDAAAAA==.Compromised:BAABLgAECn8WAAILAAYJlBtvGwDmAQALAAYJlBtvGwDmAQAAAA==.Corelack:BAAALgAECggJDgAAAA==.',
Cr='Crwth:BAAALgADCgIJAgAAAA==.',
Cu='Curendae:BAAALgAECgYJDwAAAA==.',
Da='Dabaldzombie:BAACLgAFFH8IAAIGAAQJWhO+CQBSAQAGAAQJWhO+CQBSAQAuAAQKfxcAAgYACAmpGEZMAFICAAYACAmpGEZMAFICAAAA.Danamy:BAAALgADCggJDQAAAA==.Daxzazi:BAAALgAECgMJCQAAAA==.',
De='Deadmanwlkin:BAAALgADCgIJAgAAAA==.Defias:BAAALgADCggJCAAAAA==.Despair:BAAALgADCggJCAABLgAECggJGwACAP0cAA==.',
Di='Dice:BAABLgAECn8bAAIMAAcJax6iAgBSAgAMAAcJax6iAgBSAgAAAA==.Disturbd:BAAALgAFFAIJAgABLgAFFAIJAwABAAAAAA==.Disturbian:BAAALgAFFAIJAwAAAA==.Dixierecht:BAAALgAECgcJEwAAAA==.',
Do='Dodrop:BAAALgADCgYJBwAAAA==.',
Dr='Drvargas:BAAALgADCgcJAQAAAA==.',
['Då']='Dårth:BAAALgAECgEJAQAAAA==.',
El='Elenestern:BAAALgAECgQJBQAAAA==.Elmo:BAAALgAECgYJDwAAAA==.',
Em='Emryssa:BAAALgAECgMJBgAAAA==.',
Er='Erosis:BAABLgAECn8dAAIGAAgJsB/4LgC2AgAGAAgJsB/4LgC2AgAAAA==.',
Ez='Ezaratren:BAAALgAECgUJCQABLgAECggJDgABAAAAAA==.',
Fe='Fear:BAACLgAFFH8FAAIKAAMJOBu1HQANAQAKAAMJOBu1HQANAQAuAAQKfyMAAwoACAlPIOErAF8CAAoACAlPIOErAF8CAA0ABQkbFlMbAHIBAAAA.Felcatalyist:BAABLgAECn8UAAIOAAcJARYZYwDKAQAOAAcJARYZYwDKAQAAAA==.Felisaty:BAAALgAECgEJAQAAAA==.Fellisaty:BAAALgAECgYJDgAAAA==.',
Fi='Fistofwayne:BAAALgAECgYJCgABLgAECggJHQAOAMsiAA==.',
Ga='Gakopozy:BAAALgAECgEJAgAAAA==.Gambrinos:BAAALgADCgMJAwAAAA==.Gander:BAAALgADCgEJAQABLgAECgEJAQABAAAAAA==.Gandermon:BAAALgAECgEJAQAAAA==.',
Ge='Geg:BAABLgAFFH8FAAIOAAMJuhH/JgD7AAAOAAMJuhH/JgD7AAAAAA==.',
Gu='Guldán:BAAALgAECgYJBgAAAA==.',
Gw='Gwydre:BAABLgAFFH8FAAIFAAMJ1hOCBQDAAAAFAAMJ1hOCBQDAAAAAAA==.',
Ha='Havrin:BAABLgAECn8zAAMPAAkJAhWTDQCsAQAPAAkJAhWTDQCsAQAQAAEJQhLTMQA7AAAAAA==.',
He='Headshots:BAABLgAECn8bAAICAAgJ/RxeFACUAgACAAgJ/RxeFACUAgAAAA==.Hexatar:BAAALgAECgQJBAAAAA==.',
Ho='Holmie:BAAALgADCgkJCgAAAA==.Hoofsoflove:BAAALgADCgQJBAAAAA==.Hoogaplop:BAACLgAFFH8JAAIOAAQJOhyaAwB4AQAOAAQJOhyaAwB4AQAuAAQKfykAAw4ACAmeI/sTAAMDAA4ACAmvIfsTAAMDAAUABwmOHbUEAH4BAAAA.',
Hu='Huamulan:BAABLgAECn8ZAAIHAAYJAwQxOwCpAAAHAAYJAwQxOwCpAAAAAA==.',
Ib='Ibc:BAAALgADCgcJDQABLgAECgYJFgAGAEEVAA==.Ibchilling:BAABLgAECn8WAAIGAAYJQRURIABVAQAGAAYJQRURIABVAQAAAA==.Ibcorrupted:BAAALgAECgUJCQABLgAECgYJFgAGAEEVAA==.',
Ic='Icarrus:BAABLgAECn8cAAIRAAgJqxbGFQAYAgARAAgJqxbGFQAYAgABLgAECgYJEQABAAAAAA==.Icarus:BAAALgADCgEJAQABLgAECgYJEQABAAAAAA==.',
Ig='Ignis:BAAALgAECgYJEQAAAA==.',
In='Inesh:BAAALgADCgEJAQAAAA==.',
Ir='Irrizia:BAAALgADCgkJCgAAAA==.',
Is='Iseldra:BAAALgADCggJCwAAAA==.',
['Iç']='Içyhot:BAAALgAECgEJBAABLgAECgcJEwABAAAAAA==.',
Ja='Jackbfistn:BAAALgAECgUJCQAAAA==.Jaskim:BAAALgAECgEJAQAAAA==.',
Je='Jeses:BAAALgADCgYJCQABLgAECgYJFQAHAJcRAA==.',
Jo='Jolty:BAAALgADCggJCAABLgAFFAIJBQAOAI4eAA==.Jooni:BAAALgADCggJDwAAAA==.Jordomon:BAAALgAECgMJBAAAAA==.',
['Jú']='Júliët:BAAALgAECgIJAgAAAA==.',
Ka='Kahtonah:BAAALgADCgMJAwAAAA==.Kaltaan:BAAALgAECgYJEgAAAA==.Karasan:BAAALgAECgYJDgAAAA==.Karenas:BAAALgAECgcJEwAAAA==.Karr:BAAALgAECgQJBAAAAA==.Kataraara:BAACLgAFFH8HAAIJAAQJRSAmAQCaAQAJAAQJRSAmAQCaAQAuAAQKfxcAAgkACAntJN4EADwDAAkACAntJN4EADwDAAAA.Katbeans:BAAALgAECgYJEgAAAA==.Kathrynne:BAAALgAECgUJCQAAAA==.',
Ke='Kelicemoon:BAAALgAECgYJDgABLgAECgcJFAAOALsIAA==.',
Kh='Khaliope:BAABLgAECn8yAAISAAkJMgokYACAAQASAAkJMgokYACAAQAAAA==.',
Ko='Korzari:BAAALgADCgEJAQAAAA==.Koven:BAAALgADCgMJAwAAAA==.',
Ky='Kyndlearya:BAAALgADCgEJAQAAAA==.',
La='Lahrnaon:BAAALgAECgcJDQAAAA==.Laxeron:BAAALgAECgYJEAAAAA==.',
Le='Leotherassy:BAAALgADCgUJDAAAAA==.Leychron:BAAALgAECgEJAQAAAA==.',
Li='Lightsworn:BAAALgAECgEJAQAAAA==.Lilin:BAAALgADCgYJBgAAAA==.',
Lo='Lotiel:BAAALgAECgIJAwABLgAFFAEJAQABAAAAAA==.',
Lu='Lucrecia:BAABLgAECn8UAAMSAAYJBB0hUgCuAQASAAUJWCEhUgCuAQATAAEJswufLAAuAAAAAA==.',
Ly='Lymara:BAAALgADCgcJCAAAAA==.Lynthirae:BAAALgADCgcJDAAAAA==.',
['Lø']='Lørðzêdd:BAAALgAECgQJDQAAAA==.',
Ma='Manyace:BAAALgAECgQJBgAAAA==.',
Mc='Mcbodhran:BAAALgAECgYJDgAAAA==.Mcfeast:BAAALgAECgYJEAAAAA==.',
Me='Medra:BAAALgAECgcJEAAAAA==.Merogoth:BAAALgADCgUJBwAAAA==.Mestrois:BAAALgAECgYJDQAAAA==.',
Mo='Morar:BAAALgAECgEJAQAAAA==.',
Ms='Msprettÿp:BAAALgADCgIJAgAAAA==.',
Mu='Murimlinn:BAAALgADCgMJAwAAAA==.Mustafa:BAAALgAECgQJBAAAAA==.',
Ni='Nightcat:BAAALgAECgEJAQAAAA==.Nitebäne:BAAALgADCggJCAAAAA==.Nitesbåne:BAAALgADCgcJBwAAAA==.Nitestorm:BAAALgAECgIJAgAAAA==.Nixie:BAABLgAECn8VAAIUAAYJdAcpHQDNAAAUAAYJdAcpHQDNAAAAAA==.',
No='Nobonesjones:BAACLgAFFH8HAAILAAQJSAR+AQAaAQALAAQJSAR+AQAaAQAuAAQKfxcAAgsACAkUEi4eAM4BAAsACAkUEi4eAM4BAAAA.',
Og='Oguricap:BAAALgADCgcJBwAAAA==.Ogwarshock:BAABLgAECn8dAAMKAAgJYSKjBQAcAgAKAAYJzyCjBQAcAgANAAQJ6yE+GgB7AQAAAA==.',
Ol='Oliiver:BAAALgAECgYJEAAAAA==.',
Om='Omnivore:BAAALgADCgcJCAAAAA==.Omën:BAAALgAECgQJBAABLgAECgQJCAABAAAAAA==.',
On='Oniichan:BAAALgAECgQJBQAAAA==.',
Or='Orbeez:BAAALgAECgYJEQAAAA==.',
Pa='Panaceus:BAABLgAECn8fAAIVAAgJ3BwLAQB1AgAVAAgJ3BwLAQB1AgAAAA==.Paragon:BAAALgADCgkJCQABLgAFFAMJCQAOACQZAA==.Patron:BAAALgADCgEJAQAAAA==.',
Pe='Perennial:BAAALgAECgEJAQAAAA==.Perpetrator:BAAALgADCgcJDwAAAA==.',
Ph='Phreeq:BAEALgAECgUJCQAAAA==.Phrequency:BAEALgAECgQJCQABLgAECgUJCQABAAAAAA==.',
Pi='Piety:BAAALgADCgIJAgAAAA==.Pig:BAAALgAECgEJAQABLgAFFAQJCQAOADocAA==.',
Pl='Plumsham:BAAALgADCgQJBAAAAA==.',
Po='Poisonóus:BAABLgAECn8mAAIFAAgJ6xjlDQAvAgAFAAgJ6xjlDQAvAgAAAA==.',
Pr='Profang:BAAALgADCgUJAwAAAA==.',
Py='Pyrelic:BAABLgAFFH8FAAIIAAQJNgq3CADqAAAIAAQJNgq3CADqAAAAAA==.Pyroela:BAAALgAECgUJCgABLgAFFAMJBQAFANYTAA==.',
['Pö']='Pöncho:BAAALgADCgMJAwAAAA==.',
Qa='Qayllera:BAAALgADCgkJCQAAAA==.',
Qe='Qelcie:BAAALgADCgYJBgAAAA==.',
Qu='Quizet:BAAALgADCgEJAgAAAA==.',
Ra='Raf:BAAALgAECgYJBwAAAA==.Rakeem:BAAALgAECgYJDgAAAA==.Ravenhawk:BAAALgADCgQJCAAAAA==.',
Re='Redtoxin:BAAALgADCgEJAQAAAA==.Reilley:BAABLgAECn8dAAIOAAgJbyHRFwDsAgAOAAgJbyHRFwDsAgAAAA==.Remorsa:BAAALgAECgQJCgAAAA==.Renni:BAABLgAECn8YAAIKAAYJRxewagCNAQAKAAYJRxewagCNAQAAAA==.Reshath:BAAALgADCgEJAQAAAA==.Reznor:BAABLgAECn8YAAIWAAgJEBbBJwDtAQAWAAgJEBbBJwDtAQAAAA==.',
Ro='Rosealia:BAAALgAECgMJBAAAAA==.',
Ru='Runeight:BAAALgADCgIJAQAAAA==.',
Ry='Ryder:BAAALgAECgIJBAAAAA==.',
['Ró']='Rómëo:BAABLgAECn8iAAIXAAcJZBKIBQCeAQAXAAcJZBKIBQCeAQAAAA==.',
Sa='Sabbatical:BAAALgADCgEJAQAAAA==.Saintzan:BAAALgAECgUJBgAAAA==.Salivan:BAAALgAECgUJCQAAAA==.San:BAAALgAECgYJDwAAAA==.Sanketsu:BAAALgADCgYJBgABLgAECgcJEAABAAAAAA==.Sathariel:BAAALgADCgIJAgAAAA==.',
Sc='Scalyboyos:BAAALgAECgYJEwAAAA==.Schmoop:BAABLgAECn8cAAQYAAcJKSJ9DwCMAgAYAAcJKSJ9DwCMAgAZAAMJXBtMUwDpAAAaAAEJ8RBiVgA0AAABLgAFFAQJCQAOADocAA==.',
Se='Seldaria:BAAALgAECgYJDwAAAA==.Senza:BAAALgAECgQJBwAAAA==.Senzyri:BAAALgAECgYJDgAAAA==.Serote:BAAALgADCgcJBwAAAA==.Setmabone:BAAALgADCgkJCQABLgAECgUJCQABAAAAAA==.Sevilo:BAAALgADCgkJCwABLgAECgIJAgABAAAAAA==.',
Sh='Shamagoth:BAAALgADCgEJAQAAAA==.Shoes:BAAALgAECgEJAQAAAA==.',
Si='Simic:BAAALgAECgYJDwAAAA==.',
Sn='Snowthistle:BAAALgAECgYJCgAAAA==.',
So='Soulnãris:BAAALgAECgEJAgAAAA==.',
Sp='Spin:BAAALgADCgEJAQAAAA==.Spudpal:BAAALgADCgEJAQAAAA==.',
Sq='Squirley:BAAALgAECgQJCAAAAA==.',
St='Starge:BAAALgAECgEJAQAAAA==.Stargefall:BAAALgAECgMJAwAAAA==.Stonymahoney:BAABLgAECn8cAAIHAAcJzxunPgAqAgAHAAcJzxunPgAqAgAAAA==.',
Su='Sudokoo:BAAALgADCgMJAwAAAA==.Suraisu:BAABLgAECn8YAAIEAAcJuh1WAwAYAgAEAAcJuh1WAwAYAgAAAA==.Suê:BAAALgADCgEJAQABLgADCgQJBAABAAAAAA==.',
Sv='Sveela:BAABLgAECn8bAAIPAAgJdh/CAwDKAgAPAAgJdh/CAwDKAgAAAA==.Sveelaa:BAAALgAECgYJDQABLgAECggJGwAPAHYfAA==.Sveella:BAAALgADCgEJAQABLgAECggJGwAPAHYfAA==.',
Sw='Swampjimmy:BAAALgAECgIJAgAAAA==.',
Sy='Synap:BAAALgADCgEJAQAAAA==.',
Ta='Tabchan:BAAALgAECgEJAQAAAA==.Tacocat:BAABLgAECn8dAAIZAAgJZBrMAQBuAgAZAAgJZBrMAQBuAgAAAA==.Talras:BAAALgADCgkJDAAAAA==.',
Te='Temlock:BAABLgAECn8fAAIKAAcJthsqMQBIAgAKAAcJthsqMQBIAgAAAA==.Tempest:BAAALgADCgUJAgABLgAFFAMJCQAOACQZAA==.Temtank:BAABLgAECn8UAAIFAAcJzxf+BgAvAQAFAAcJzxf+BgAvAQABLgAECgcJHwAKALYbAA==.',
Tr='Trak:BAABLgAECn8UAAIbAAgJZgzbMwAtAQAbAAgJZgzbMwAtAQAAAA==.Trukarak:BAAALgAECgcJEAAAAA==.',
Tu='Tuvaquitamuu:BAAALgADCgEJAQAAAA==.',
Va='Vaeegoldiir:BAAALgAECgEJAQAAAA==.Valenti:BAAALgAECgQJCQAAAA==.Valor:BAABLgAECn8XAAIHAAcJdR7VPQAtAgAHAAcJdR7VPQAtAgAAAA==.Vanity:BAAALgADCgMJAwAAAA==.',
Ve='Veliann:BAAALgAECgEJAQAAAA==.Vellatrix:BAAALgAECgQJBgAAAA==.',
Vi='Vipershot:BAAALgADCggJDgAAAA==.',
We='Weewoo:BAAALgADCgQJBAAAAA==.',
Wi='Wildama:BAAALgAECgYJDAAAAA==.',
Wr='Wrenwillow:BAAALgAECgIJAgAAAA==.',
Wu='Wumbo:BAAALgADCgEJAQAAAA==.',
Xa='Xarríøn:BAAALgADCgMJAwABLgAECggJCAABAAAAAA==.',
Xi='Xiao:BAAALgAECgYJEAAAAA==.',
Xy='Xylaini:BAAALgAECgQJBAABLgAECgUJEAABAAAAAA==.',
Ya='Yahargul:BAAALgAECgUJBwAAAA==.',
Yo='Yogafarts:BAAALgAECgYJCAAAAA==.',
Ze='Zeik:BAABLgAECn8WAAIcAAYJahZXBgArAQAcAAYJahZXBgArAQAAAA==.Zephyrgosa:BAAALgADCgUJBQAAAA==.',
Zu='Zucco:BAAALgAECgkJBAAAAA==.Zuufungo:BAAALgAECgUJBQAAAA==.',
['Zí']='Zíx:BAAALgAECgYJDgAAAA==.',
['Àl']='Àlcàrà:BAAALgAECgYJCgAAAA==.',
['Ål']='Åldaren:BAAALgADCgQJBAAAAA==.',
['Ÿa']='Ÿamar:BAAALgADCgIJAgAAAA==.',
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

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

local lookup = {'Hunter-Survival','Mage-Fire','Evoker-Augmentation','DeathKnight-Unholy','Priest-Shadow','Mage-Frost','Warrior-Fury','Monk-Mistweaver','Shaman-Elemental','Paladin-Retribution','Mage-Arcane','Warrior-Arms','Unknown-Unknown','Evoker-Devastation','Hunter-BeastMastery','Hunter-Marksmanship','DemonHunter-Devourer','Shaman-Restoration','Monk-Brewmaster','DeathKnight-Blood','DeathKnight-Frost','Warrior-Protection','Priest-Discipline','Priest-Holy','Warlock-Affliction','Druid-Guardian','Warlock-Demonology','Rogue-Subtlety','Evoker-Preservation','Monk-Windwalker','DemonHunter-Vengeance','Paladin-Holy','Warlock-Destruction','Druid-Restoration','Druid-Feral','DemonHunter-Havoc',}
local provider = {region='US',realm='Azgalor',name='US',type='weekly',zone=46,date='2026-04-24',data={Aa='Aarahunt:BAABLgAECn8hAAIBAAgJrgWyFAB8AQABAAgJrgWyFAB8AQAAAA==.',
Ab='Abente:BAAALgADCgYJBwAAAA==.',
Ac='Acarin:BAAALgAECgQJBgAAAA==.',
Ad='Adawna:BAAALgAECgYJCAAAAA==.Addio:BAAALgADCgcJDAAAAA==.Adgalor:BAAALgADCgkJCQAAAA==.Adrenaline:BAAALgADCgMJAQAAAA==.Adsaw:BAABLgAECn8ZAAICAAcJsRp9AADcAQACAAcJsRp9AADcAQAAAA==.Adula:BAAALgAECgUJBgABLgAFFAMJBwADAGcVAA==.',
Ae='Aelunara:BAABLgAECn8WAAIEAAYJDRqGZQDEAQAEAAYJDRqGZQDEAQAAAA==.Aer:BAAALgADCgcJDgAAAA==.Aerostalim:BAAALgAECgUJBwAAAA==.',
Af='Aftershocks:BAAALgAECgYJEwAAAA==.',
Ah='Ahnanji:BAAALgADCgEJAQAAAA==.Ahoydorei:BAAALgAECgEJAQAAAA==.',
Ai='Aijha:BAAALgADCgMJAwAAAA==.Ailric:BAABLgAECn8XAAIFAAYJpRWGCgBIAQAFAAYJpRWGCgBIAQAAAA==.',
Ak='Akivra:BAAALgAECgYJBgAAAA==.',
Al='Alanon:BAAALgADCgEJAQAAAA==.Alanorae:BAAALgADCgMJAwAAAA==.Alarakian:BAAALgAECgIJAgAAAA==.Alassae:BAAALgADCgcJCQAAAA==.Alcapown:BAAALgAECgQJDwAAAA==.Aldrea:BAAALgAECgQJBgAAAA==.Aleco:BAAALgADCgcJDAAAAA==.Alexdaelfs:BAAALgAECgEJAQAAAA==.Aliakin:BAABLgAECn8ZAAIGAAgJPB6tCAAdAgAGAAgJPB6tCAAdAgAAAA==.Alinda:BAAALgADCgYJCAABLgAECggJGAAHAGEUAA==.Alleviel:BAAALgAECgkJDwAAAA==.Aloros:BAAALgAECgEJAQABLgAECggJGAAGAO4QAA==.Alphirion:BAAALgAECgMJBAAAAA==.Alyssachik:BAABLgAECn8UAAIIAAYJrw/pNAAfAQAIAAYJrw/pNAAfAQAAAA==.',
Am='Amaeradin:BAAALgADCgIJAgAAAA==.Amarxd:BAABLgAECn8bAAIJAAcJ5SG+GgA9AgAJAAcJ5SG+GgA9AgAAAA==.Amashira:BAAALgAECgQJBAAAAA==.Ambosi:BAAALgAECgYJBwAAAA==.',
An='Anamae:BAAALgADCgIJAgAAAA==.Anarchtear:BAAALgAECgUJCQAAAA==.Andesipa:BAAALgAECgYJEgAAAA==.Anduin:BAAALgAECgEJAQAAAA==.Anetha:BAAALgAECgYJCgAAAA==.Angerclaw:BAAALgAECgYJDwAAAA==.Angrybirdee:BAAALgAECgMJAwAAAA==.Ankaramessi:BAAALgAECgYJCQAAAA==.Annaalista:BAAALgAECgYJCgAAAA==.',
Ap='Apollosolo:BAAALgADCgIJAgAAAA==.Apoth:BAAALgAECgcJAgAAAA==.',
Ar='Aradrad:BAAALgADCgUJBwAAAA==.Arakisa:BAAALgAECgQJBwAAAA==.Aranhferizzi:BAAALgADCgYJDgAAAA==.Arazara:BAAALgADCgIJAgAAAA==.Arcaenus:BAAALgAECgQJBgABLgAECggJFwAKAEEiAA==.Archspally:BAAALgADCgEJAgAAAA==.Arivian:BAAALgAECgMJAwAAAA==.Arkileous:BAABLgAECn8VAAMGAAYJfhy7dwDiAQAGAAYJfhy7dwDiAQALAAEJqg+XHQA3AAAAAA==.Artemmis:BAAALgAFFAMJAwAAAA==.',
As='Assapopolous:BAAALgAECgYJCgAAAA==.',
At='Atalmon:BAABLgAECn8YAAIKAAcJGyDvCAD7AQAKAAcJGyDvCAD7AQAAAA==.Atticos:BAAALgAECgMJBAAAAA==.',
Av='Avastin:BAAALgAECgQJBAAAAA==.',
Aw='Awni:BAABLgAECn8eAAIMAAgJZB6OAQD6AQAMAAgJZB6OAQD6AQAAAA==.',
Az='Azarinth:BAAALgAECgQJBAABLgAECgUJBgANAAAAAA==.',
Ba='Babadookk:BAAALgAECgcJEwAAAA==.Bahbahr:BAABLgAECn8ZAAIGAAgJoR60JQDcAgAGAAgJoR60JQDcAgAAAA==.Bahrim:BAAALgAECgQJCAAAAA==.Balarian:BAAALgADCgkJEQAAAA==.Balefirebob:BAABLgAECn8ZAAMDAAcJNRIsCABoAQADAAcJ2hEsCABoAQAOAAIJ/w+9NQBnAAAAAA==.Bangbangji:BAAALgADCgMJAwABLgAECgEJAgANAAAAAA==.Bangis:BAAALgADCgcJBwABLgAECggJGwAIAPkXAA==.Baphome:BAAALgAECgMJAwAAAA==.Barkntank:BAAALgADCgMJAwAAAA==.Barreloferal:BAAALgAECgMJBAAAAA==.Bartholomeow:BAAALgADCgMJAwAAAA==.Batohar:BAAALgADCgEJAQAAAA==.Battlebeats:BAAALgADCgIJAgAAAA==.Battlebelle:BAAALgAECgYJCAAAAA==.Baxx:BAAALgADCgkJCQAAAA==.Bazzoo:BAAALgAECgYJDQAAAA==.',
Be='Beachbabe:BAAALgAECgMJBgAAAA==.Bendable:BAAALgADCgEJAQAAAA==.Berrd:BAAALgAECgMJAwAAAA==.Bethezar:BAAALgAECgMJBQAAAA==.',
Bh='Bhangbhang:BAABLgAECn8bAAIIAAgJ+RfaFQAWAgAIAAgJ+RfaFQAWAgAAAA==.',
Bi='Bigboitaur:BAAALgADCgEJAQAAAA==.Biggerbits:BAAALgAECgEJAQAAAA==.Bigkrayze:BAAALgAECgYJDAAAAA==.Bimboblyad:BAABLgAECn98AAMPAAkJAidIAAAuAwAQAAgJ+Sa0AQClAwAPAAgJ0CZIAAAuAwAAAA==.Birdupp:BAAALgADCgEJAgAAAA==.Bizzarro:BAAALgAECgYJCgAAAA==.Bizzkitt:BAAALgADCgcJBwAAAA==.',
Bl='Blackwîdow:BAABLgAECn8cAAIRAAgJ1B7rBAA8AgARAAgJ1B7rBAA8AgAAAA==.Blaigne:BAAALgADCgcJCwAAAA==.Blizimcguire:BAAALgADCgcJCQAAAA==.Bloodycat:BAAALgAECgMJAwAAAA==.Bloodymenses:BAAALgADCgkJEwAAAA==.Bluerose:BAAALgAECgUJBQAAAA==.Blurry:BAAALgAECgEJAQAAAA==.',
Bo='Bonngo:BAAALgAECgEJAgAAAA==.Boofgodrekk:BAAALgAECgIJAgAAAA==.Boofkokaina:BAAALgAECgEJAQAAAA==.Boofydoo:BAAALgADCgIJAgAAAA==.',
Br='Brannen:BAAALgAECgUJBwAAAA==.Brayicela:BAAALgADCgQJBAABLgAECgQJBQANAAAAAA==.Brazzii:BAAALgADCgYJBgAAAA==.Bricksanchez:BAAALgAECgMJAwAAAA==.Brindo:BAAALgADCgUJBwAAAA==.Bringbags:BAAALgADCgMJAwAAAA==.Britneyfears:BAAALgAECgEJAQAAAA==.Bro:BAAALgADCgkJDQAAAA==.Brokentuskz:BAAALgADCggJAQABLgAECggJHAAKAKQSAA==.Broten:BAAALgADCgMJAwAAAA==.Brëwskï:BAAALgADCgEJAQAAAA==.',
Bu='Buffbutton:BAAALgAECgYJCwAAAA==.Bulistus:BAAALgADCgIJAgAAAA==.Bulszeye:BAAALgAECgYJCwAAAA==.Burningwave:BAAALgAECgYJDwAAAA==.Buzzie:BAAALgADCgYJCAAAAA==.',
Bw='Bwonsamdiboy:BAAALgADCgIJAgAAAA==.',
Bx='Bxndo:BAAALgADCgQJAwAAAA==.',
Ca='Caerisma:BAAALgAECggJGwAAAQ==.Calebsdemon:BAAALgADCgUJBQAAAA==.Caltha:BAAALgADCgcJBwAAAA==.Caravaggio:BAAALgADCgUJBQAAAA==.Casterbation:BAAALgADCgYJBgAAAA==.Catiany:BAAALgADCgYJBgAAAA==.',
Ce='Celithil:BAAALgADCgYJCAAAAA==.Ceroll:BAAALgAFFAEJAQAAAA==.Cerolumas:BAAALgADCgUJBQABLgADCgYJBwANAAAAAA==.',
Ch='Chadwik:BAAALgADCgYJBgAAAA==.Chainevoker:BAAALgAECgYJCgAAAA==.Charbzenberg:BAAALgADCgIJAgAAAA==.Charisma:BAAALgADCgYJBgABLgAECggJGwANAAAAAQ==.Cheeseburgrr:BAAALgAECgYJCQAAAA==.Chiang:BAAALgADCgkJHAAAAA==.Chilijayleen:BAAALgAECgQJBAAAAA==.Chinari:BAAALgADCgYJBgAAAA==.Chinkinarobe:BAAALgAECgMJAwAAAA==.Chonhunter:BAAALgAECgYJCQAAAA==.Chungae:BAAALgADCgMJAwAAAA==.Chunkychucky:BAAALgADCgIJAgAAAA==.',
Cj='Cjay:BAAALgADCgQJAwAAAA==.',
Cl='Clegen:BAAALgADCgUJAwAAAA==.Cloax:BAACLgAFFH8HAAIFAAMJNAP/BgCzAAAFAAMJNAP/BgCzAAAuAAQKfyUAAgUACAmIGoISAGQCAAUACAmIGoISAGQCAAAA.Clýde:BAAALgAECgUJCAAAAA==.',
Co='Cobask:BAAALgAECgMJAgAAAA==.Cobyashi:BAAALgADCgcJBwAAAA==.Colinar:BAAALgAECgUJBQAAAA==.Compassion:BAAALgADCgYJCgAAAA==.Conquer:BAAALgADCgYJBgAAAA==.Conquermonk:BAAALgADCgQJBAAAAA==.Coobin:BAAALgADCgIJAgAAAA==.Coors:BAAALgADCgQJBAAAAA==.Cotas:BAAALgAECgYJCwAAAA==.Couraegus:BAABLgAECn8XAAIKAAgJQSJlEAAMAwAKAAgJQSJlEAAMAwAAAA==.Covenants:BAAALgADCgQJBAAAAA==.',
Cr='Crabemoji:BAAALgAECgQJBQABLgAFFAQJBwASALYbAA==.Crapo:BAAALgAECgYJCgAAAA==.Crewbin:BAAALgAECgMJBAAAAA==.Croobin:BAAALgADCgcJBwAAAA==.Crud:BAAALgADCgMJAwAAAA==.Cryhavok:BAAALgAECgEJAgAAAA==.Crymzin:BAAALgADCgIJAgAAAA==.',
Cu='Cubefuonyou:BAAALgAECgYJCQAAAA==.Cubesoaker:BAAALgAECgQJCQAAAA==.Cutesbrews:BAABLgAECn8bAAITAAcJ1hQ5LQClAQATAAcJ1hQ5LQClAQAAAA==.',
Cy='Cyther:BAAALgAECgEJAQAAAA==.',
['Cê']='Cêll:BAAALgADCgEJAgAAAA==.',
Da='Daghar:BAAALgAECgYJEwAAAA==.Dalé:BAAALgAECgYJBgAAAA==.Damecias:BAAALgAECgYJDQAAAA==.Dana:BAAALgADCgIJAQAAAA==.Danielsonn:BAAALgAECgQJBAAAAA==.Danyphantom:BAAALgADCgMJBAAAAA==.Darbpal:BAABLgAECn8aAAIKAAcJURIiWgDUAQAKAAcJURIiWgDUAQAAAA==.Darealrambo:BAAALgADCgYJCwAAAA==.Darfk:BAAALgADCgUJCAAAAA==.Darkbender:BAAALgAECgYJCwAAAA==.Darkmanta:BAAALgAECgMJAwAAAA==.Darkzephyr:BAAALgADCgYJCQAAAA==.Darkÿ:BAAALgAECgQJCAAAAA==.Darnitt:BAAALgADCgQJBAABLgADCggJEAANAAAAAA==.Darthvaliate:BAAALgAECgYJCwAAAA==.Datboyj:BAAALgAECgkJDAAAAA==.Davosi:BAABLgAECn8XAAIHAAgJkhwqAgBJAgAHAAgJkhwqAgBJAgAAAA==.Dayrb:BAAALgADCgIJAgAAAA==.',
De='Deadtalini:BAABLgAECn8tAAQUAAkJ+RljCwBdAgAUAAgJJR1jCwBdAgAEAAkJKwwiFwBZAQAVAAEJdA4sCQA5AAAAAA==.Deah:BAABLgAECn8XAAIPAAcJoiFiBwD0AQAPAAcJoiFiBwD0AQAAAA==.Dearling:BAAALgADCgUJBQAAAA==.Deckerdramon:BAABLgAECn8cAAIWAAcJcBcgBQBoAQAWAAcJcBcgBQBoAQAAAA==.Deepeemcgee:BAAALgADCgcJEQAAAA==.Delanoris:BAAALgADCgYJBgAAAA==.Dellera:BAAALgADCgcJGAAAAA==.Demonhizzy:BAAALgAECggJCwAAAA==.Demontoid:BAAALgADCgcJDQAAAA==.Demonzo:BAAALgADCgUJBQAAAA==.Dennevien:BAAALgADCgcJBgAAAA==.Desaran:BAAALgAECgEJAQAAAA==.Destinda:BAAALgAECgYJCgAAAA==.Devoider:BAAALgAECgYJBgAAAA==.Devour:BAAALgADCgcJDAAAAA==.Devoured:BAAALgAECgMJAgAAAA==.Devours:BAACLgAFFH8OAAISAAQJ3xoJBwBVAQASAAQJ3xoJBwBVAQAuAAQKfyAAAhIACQk0I1QCAF8DABIACQk0I1QCAF8DAAAA.Devoury:BAACLgAFFH8GAAMXAAMJ3g9rBgDvAAAXAAMJ3g9rBgDvAAAYAAEJrgzfFQA+AAAuAAQKfxkAAxgABwmnI7wJALECABgABwmMI7wJALECABcABwkHGiERADACAAEuAAUUBAkOABIA3xoA.',
Di='Dihfacer:BAAALgAECgIJAgAAAA==.Dippndots:BAAALgADCgEJAQAAAA==.Diâblö:BAACLgAFFH8MAAIIAAQJfSV0AQC8AQAIAAQJfSV0AQC8AQAuAAQKfzAAAggACAkyJtkBAHkDAAgACAkyJtkBAHkDAAAA.',
Do='Dobro:BAAALgAECgUJBwAAAA==.Doth:BAAALgADCgIJAgAAAA==.Downkid:BAAALgAECgMJAwAAAA==.',
Dr='Dragapult:BAACLgAFFH8HAAIDAAMJZxWmCQDoAAADAAMJZxWmCQDoAAAuAAQKfyQAAwMACAn8GqMEAMQBAAMACAn8GqMEAMQBAA4AAwkJD+swAI8AAAAA.Dragusysmash:BAAALgADCgYJBgAAAA==.Dralvira:BAABLgAECn8hAAIWAAgJmyWzAQBoAwAWAAgJmyWzAQBoAwAAAA==.Drath:BAAALgADCggJFwAAAA==.Draxithar:BAAALgAECgUJBQAAAA==.Drazzin:BAAALgADCgIJAgABLgAECgcJHQAZAAIdAA==.Dryduss:BAAALgADCgYJBgAAAA==.Drzj:BAAALgAECggJEwAAAA==.',
Ds='Dsappman:BAAALgAECgIJAgAAAA==.',
Du='Dualshock:BAAALgAECgEJAQAAAA==.Duggo:BAAALgAECgIJAwAAAA==.Durvier:BAAALgADCgUJBQAAAA==.Durzaq:BAAALgADCgEJAQAAAA==.',
Dy='Dyrteshadow:BAAALgADCgYJCAAAAA==.',
['Dà']='Dàth:BAAALgAECgUJCQAAAA==.',
Eb='Ebore:BAAALgADCgMJAwAAAA==.',
Ec='Ecoshock:BAAALgADCgMJAwABLgAECgMJCAANAAAAAA==.',
Ei='Eirrin:BAABLgAECn8gAAIYAAgJJyBnCADFAgAYAAgJJyBnCADFAgAAAA==.',
El='Elaineh:BAAALgAECgUJBgAAAA==.Elementalist:BAAALgAECgQJBAAAAA==.Elendira:BAAALgAECgYJCAAAAA==.Elkane:BAAALgAECgYJCgAAAA==.Elleredreaux:BAAALgAECgYJEQAAAA==.Elofin:BAAALgAECgMJAwAAAA==.',
En='Endomorphism:BAABLgAECn8WAAIaAAcJTyK1BACfAgAaAAcJTyK1BACfAgABLgAFFAUJEgAaAK8XAA==.',
Eq='Equidus:BAAALgADCgEJAQAAAA==.',
Er='Eranthis:BAAALgAECgUJBQAAAA==.Errour:BAAALgADCgYJCwAAAA==.',
Et='Etherhand:BAAALgAECgEJAQAAAA==.',
Ev='Eveldumboone:BAACLgAFFH8NAAIUAAQJyRzPAgApAQAUAAQJyRzPAgApAQAuAAQKfyUAAxQACAlxJGADACUDABQACAlxJGADACUDABUAAQmOGboUAEgAAAAA.',
Ez='Ezmelora:BAABLgAECn8dAAIbAAgJwxRjQQAJAgAbAAgJwxRjQQAJAgAAAA==.',
Fa='Faelight:BAAALgAECgEJAQAAAA==.Faenixandria:BAAALgAECgMJBwAAAA==.Fairykiller:BAAALgADCgEJAQAAAA==.Falkrus:BAAALgADCgEJAQAAAA==.Fallenresto:BAAALgADCgcJBwAAAA==.Fancydemon:BAAALgADCgIJAgAAAA==.Fancypets:BAAALgADCgUJBQAAAA==.Fantasie:BAAALgAECgEJAgABLgAECggJIAAYAJMVAA==.Fartz:BAAALgADCgYJBgAAAA==.Fauxpawz:BAAALgAECgYJDQAAAA==.Fayia:BAABLgAECn8YAAMPAAcJFBZ9QQCqAQAPAAcJFBZ9QQCqAQAQAAQJHQSFbACMAAAAAA==.',
Fe='Fearshaman:BAABLgAECn8mAAISAAgJbQhaQwB0AQASAAgJbQhaQwB0AQAAAA==.Felbrew:BAAALgAECggJDAAAAA==.Felhoof:BAABLgAECn8VAAIcAAcJGhxrHQATAgAcAAcJGhxrHQATAgAAAA==.Fellrend:BAAALgAECgIJAgAAAA==.Felrogue:BAAALgADCgQJBAAAAA==.',
Fi='Fibbs:BAAALgAECggJEQAAAA==.Firaman:BAAALgAECgYJBwAAAA==.Firewraith:BAAALgAECgMJAwAAAA==.Fistmachin:BAABLgAECn8aAAITAAgJ1A69CQBVAQATAAgJ1A69CQBVAQAAAA==.Fizzibix:BAAALgADCgIJAgABLgAECgYJEAANAAAAAA==.',
Fl='Flexxed:BAACLgAFFH8IAAIVAAQJWBZJAQAZAQAVAAQJWBZJAQAZAQAuAAQKfxcAAxUABwmNIg0DAGwCABUABwmNIg0DAGwCAAQAAQmqDJQsASkAAAAA.Flip:BAAALgADCgUJBwAAAA==.Florelai:BAAALgAECgMJAwAAAA==.Florin:BAAALgADCgEJAQAAAA==.Flyinmachin:BAAALgAECgEJAQAAAA==.',
Fo='Foreheadkiss:BAAALgAECgcJBwAAAA==.',
Fr='Frakkinfrik:BAAALgADCgIJAgAAAA==.Franciss:BAAALgAECgQJBQAAAA==.Freezie:BAAALgAECgcJDgAAAA==.Freyae:BAAALgADCggJEgAAAA==.Frikkinfrak:BAAALgADCgIJAgAAAA==.Friskie:BAAALgAECgcJCwABLgAECggJIAAYAJMVAA==.Frona:BAAALgADCgYJEgAAAA==.',
Ft='Ftknox:BAAALgAECgEJAQAAAA==.',
Fu='Fuhq:BAAALgAECgEJAQAAAA==.Furrever:BAAALgAECgUJCwAAAA==.Fuzada:BAABLgAECn8XAAIGAAcJ5CH7OACRAgAGAAcJ5CH7OACRAgAAAA==.',
Fw='Fwuppy:BAAALgAECgEJAQAAAA==.',
Ga='Gament:BAAALgADCgYJBgAAAA==.Gandamar:BAAALgAECgYJCAAAAA==.Gankzz:BAAALgAECgcJDQAAAA==.Ganondork:BAAALgADCgMJAwAAAA==.Ganondrow:BAAALgAECggJEAAAAA==.Gantar:BAAALgADCgcJBwAAAA==.',
Gb='Gboyzz:BAAALgADCgkJCQAAAA==.',
Ge='Gemelo:BAAALgAECgMJAwAAAA==.',
Gg='Ggivverr:BAAALgAECgQJBgAAAA==.',
Gh='Ghstsplntr:BAABLgAECn8eAAIKAAYJnBrgYADCAQAKAAYJnBrgYADCAQAAAA==.',
Gi='Gibayy:BAAALgAFFAIJAgAAAA==.Gibsonex:BAAALgAECgUJDQAAAA==.Gilliamm:BAAALgAECggJEQAAAA==.Giselda:BAAALgAECgYJEAAAAA==.',
Gl='Gloomstick:BAAALgAECgYJBwAAAA==.',
Go='Gobbs:BAABLgAECn8ZAAMPAAcJVR48PgC2AQAPAAcJVR48PgC2AQAQAAIJFw9iDAB7AAAAAA==.Goblocker:BAAALgADCgYJBgAAAA==.Golath:BAAALgAECgQJBAAAAA==.Goldoraq:BAAALgAECgEJAQAAAA==.Goldscales:BAAALgADCgMJAwAAAA==.Gonjoodman:BAAALgADCgcJBwAAAA==.Gonthielhunt:BAAALgAECgIJAgAAAA==.Gonzobeanz:BAAALgADCgYJCwAAAA==.Gonzolo:BAAALgADCgUJBgAAAA==.Goocheater:BAAALgADCgYJCQAAAA==.Gorcazzo:BAAALgAECgYJDwAAAA==.Gorekroxx:BAAALgADCgQJAwAAAA==.Gorgonzormu:BAABLgAECn8YAAMOAAgJayEnBADNAgAOAAcJlSEnBADNAgADAAYJWSF8GQABAgAAAA==.Gothbutta:BAAALgAECgMJAwAAAA==.',
Gr='Grandpoobah:BAAALgADCggJCAABLgAECgkJIgAdAAAcAA==.Gregorian:BAAALgAECgYJCQAAAA==.Gremliin:BAAALgAECgYJDAAAAA==.Gremlinstorm:BAAALgADCgYJCQABLgAECgYJDAANAAAAAA==.Grendalu:BAAALgADCgEJAgAAAA==.Griffy:BAAALgADCgMJBQAAAA==.',
Gu='Gumpiz:BAAALgAECgMJAwAAAA==.',
Ha='Haardslinger:BAAALgADCgcJBwABLgAECgMJAwANAAAAAA==.Hamdon:BAAALgADCgQJBAAAAA==.Hanabi:BAAALgADCgcJCAAAAA==.Haniesh:BAABLgAECn8cAAIKAAgJpBJcEgCQAQAKAAgJpBJcEgCQAQAAAA==.Harlin:BAAALgADCgQJBAABLgAECgQJBQANAAAAAA==.Hatengar:BAAALgAECgYJEgAAAA==.Hazben:BAAALgADCgQJBAAAAA==.',
He='Healmeharder:BAAALgAECgEJAQAAAA==.Helburk:BAAALgADCgYJCQAAAA==.Hellagood:BAAALgAECgQJBwAAAA==.Hethar:BAAALgADCgQJBAABLgAECgUJBwANAAAAAA==.',
Hi='Hightide:BAAALgAECgYJDQAAAA==.Hipocratic:BAAALgAECgYJDgAAAA==.Hippodot:BAAALgAECggJEAAAAA==.',
Ho='Hodorr:BAABLgAECn8XAAMTAAgJZBI6CQBeAQATAAgJZBI6CQBeAQAeAAIJ/gbIdABCAAAAAA==.Hodr:BAAALgAECgYJCAABLgAECggJFwATAGQSAA==.Hoghoof:BAAALgADCggJEwAAAA==.Hoja:BAAALgAFFAEJAQAAAA==.Holdor:BAAALgADCgIJAgAAAA==.Holrhyn:BAABLgAECn8VAAIYAAcJFxkcJgC6AQAYAAcJFxkcJgC6AQAAAA==.Holybloodboi:BAAALgAECgcJCAAAAA==.Holylife:BAAALgADCgEJAQAAAA==.Hozencolo:BAAALgADCgMJBAAAAA==.',
Hu='Huckleberry:BAAALgAECgcJEwAAAA==.Hugegigachad:BAAALgADCgQJBAAAAA==.Hugsnkisses:BAAALgAECgEJAQAAAA==.Hukjek:BAAALgAECgMJBgAAAA==.Hungcowboy:BAAALgADCgIJAgAAAA==.',
Hy='Hydrogenbomb:BAABLgAECn8aAAMBAAYJDSCzCgArAgABAAYJkx+zCgArAgAQAAQJVBZVUQAHAQAAAA==.Hymnbral:BAAALgADCgMJBQABLgAECggJGAAGAO4QAA==.',
Ic='Icebergx:BAAALgAECgQJBgAAAA==.',
Im='Imcooleddown:BAABLgAECn8YAAIGAAcJmBvGDADmAQAGAAcJmBvGDADmAQAAAA==.Imfkinold:BAAALgAECgMJBAAAAA==.Imptricity:BAAALgADCgMJAwAAAA==.Imrickjamesb:BAAALgADCgIJAgAAAA==.',
In='Indee:BAAALgADCgYJBQABLgAECgYJBgANAAAAAA==.Indi:BAAALgADCgQJBAAAAA==.Indyd:BAAALgAECgEJAQAAAA==.Indyy:BAAALgADCgMJAwABLgAECgYJBgANAAAAAA==.',
Iz='Izunna:BAAALgAECgMJAwABLgAECggJIwAfAEsiAA==.',
Ja='Jackbeef:BAABLgAECn8ZAAIHAAgJkxv9BADkAQAHAAgJkxv9BADkAQAAAA==.Jadedhooves:BAAALgAECgYJDwAAAA==.Japorms:BAAALgADCgEJAgAAAA==.',
Je='Jedai:BAABLgAECn8pAAIgAAgJNCaNAQBsAwAgAAgJNCaNAQBsAwAAAA==.Jerrund:BAAALgAECgIJAgAAAA==.Jerryfour:BAAALgADCgEJAQAAAA==.Jerrythree:BAAALgADCgMJAgAAAA==.Jerrytwo:BAAALgAECgYJEAAAAA==.',
Jm='Jman:BAAALgAECgYJDAAAAA==.',
Jo='Johnboy:BAAALgADCgYJAQAAAA==.Jorgancrath:BAAALgAECgMJAwAAAA==.Jovallius:BAAALgADCgkJCQAAAA==.',
Ju='Judadiah:BAAALgAECgIJAgAAAA==.Juggernutz:BAAALgAECgEJAgABLgAECggJGAAHAGEUAA==.Juggernutzy:BAAALgADCgcJBwABLgAECggJGAAHAGEUAA==.Jujujalal:BAAALgADCgkJCQAAAA==.Justbeginner:BAAALgADCgcJCwAAAA==.Justlycolda:BAAALgAECgUJBQAAAA==.',
['Jà']='Jàde:BAAALgADCgkJHQAAAA==.',
Ka='Kagalith:BAAALgADCgIJAgAAAA==.Kagorin:BAABLgAECn8bAAIOAAgJiw9dAQC/AQAOAAgJiw9dAQC/AQAAAA==.Kaidios:BAABLgAECn8dAAQVAAgJfRtZBgC2AQAEAAgJ5he9WgDiAQAVAAcJrhZZBgC2AQAUAAEJOQZ3RwAqAAAAAA==.Kalano:BAABLgAECn8XAAMGAAcJngmNLAAZAQAGAAcJcweNLAAZAQALAAMJEgudEwCLAAAAAA==.Kalona:BAAALgADCgIJAgAAAA==.Kalrock:BAABLgAECn8XAAMbAAcJpR09DQCrAQAbAAYJpR09DQCrAQAhAAEJAACuXQBVAAAAAA==.Kalulu:BAAALgADCgEJAQAAAA==.Karkit:BAAALgADCgcJEwAAAA==.Katchow:BAAALgAECgcJDQAAAA==.Katkot:BAABLgAECn8VAAIKAAYJ8RGomgBJAQAKAAYJ8RGomgBJAQAAAA==.Kayro:BAAALgADCgcJEgAAAA==.Kayyggoo:BAAALgAECgkJEAAAAA==.Kazlan:BAAALgADCgYJCwAAAA==.',
Ke='Kercimage:BAAALgADCgIJAgAAAA==.Kevinn:BAAALgADCgUJBAAAAA==.',
Kh='Khalana:BAAALgADCgUJCAAAAA==.Khalio:BAAALgADCgYJCwAAAA==.Khamul:BAAALgAECgYJDAAAAA==.',
Ki='Kielovar:BAAALgADCgYJBgAAAA==.Kimchilada:BAAALgAECgMJAwAAAA==.Kithkanan:BAAALgADCgUJBQAAAA==.',
Kk='Kkodabear:BAAALgAECgQJBAAAAA==.',
Kn='Kneeonater:BAAALgADCgcJEAAAAA==.',
Ko='Kobiter:BAAALgAECgUJCAABLgAECggJJgAWALgbAA==.Kobito:BAABLgAECn8mAAMWAAgJuBuzCQB9AgAWAAgJuBuzCQB9AgAHAAYJyBmYOwC3AQAAAA==.Kointahti:BAAALgAECgYJCgABLgAECgEJCgANAAAAAA==.Konara:BAAALgADCgcJBgAAAA==.Koopatroopa:BAABLgAECn8UAAMeAAYJ3xD1CwARAQAeAAYJ3xD1CwARAQATAAUJ6AkOWgDcAAAAAA==.Koup:BAABLgAECn8gAAMPAAgJbyZ3AAAIAwAPAAgJbyZ3AAAIAwAQAAEJAAAejgAtAAAAAA==.Koupe:BAAALgAECgQJCgABLgAECggJIAAPAG8mAA==.Koups:BAAALgADCgQJBAABLgAECggJIAAPAG8mAA==.',
Kr='Krayzebeef:BAAALgADCgkJDQAAAA==.Krazyemist:BAAALgADCgQJBAAAAA==.Kreyash:BAAALgAECgIJAgAAAA==.Kriss:BAAALgAECgQJCQAAAA==.Kruncha:BAAALgAECgIJAgAAAA==.Krungus:BAAALgAECgIJAgAAAA==.Kryxis:BAABLgAECn8YAAIRAAcJ4RqSUAC0AQARAAcJ4RqSUAC0AQAAAA==.',
Ku='Kupe:BAAALgAECgYJCwABLgAECggJIAAPAG8mAA==.Kuroguro:BAAALgAECgYJCgAAAA==.Kuruption:BAAALgAECgIJAgAAAA==.',
Kw='Kwikkx:BAAALgADCgcJDQAAAA==.',
Ky='Kyewanda:BAABLgAECn8ZAAIiAAYJiR5mKgAIAgAiAAYJiR5mKgAIAgAAAA==.Kyewson:BAAALgADCgMJAwABLgAECgYJGQAiAIkeAA==.Kyrobytez:BAAALgAECgUJCgAAAA==.Kythyra:BAAALgADCgUJBgAAAA==.',
La='Laanu:BAAALgAECgYJCwABLgAECggJJQAcAFEdAA==.Lagginwaggin:BAAALgAECgUJBgAAAA==.Lakes:BAAALgADCgQJBAAAAA==.Lanuna:BAAALgAECgcJAwAAAA==.Laowan:BAAALgAECgMJAwAAAA==.Lasagnatoo:BAAALgAECgMJBQABLgAECgkJLQAUAPkZAA==.Lastlight:BAAALgAECgIJAgAAAA==.Lathara:BAAALgADCgkJDQAAAA==.Lavs:BAABLgAECn8cAAIjAAgJYh0QBQDBAgAjAAgJYh0QBQDBAgAAAA==.',
Le='Leahabah:BAAALgADCgYJBgAAAA==.Legendweaver:BAAALgADCgUJBQABLgAECgYJEQANAAAAAA==.Lein:BAAALgAECgUJDAAAAA==.Lenix:BAAALgADCgYJDgAAAA==.',
Li='Lionalone:BAAALgADCgIJAgAAAA==.Livallan:BAAALgAECggJDwAAAA==.',
Lm='Lman:BAAALgAECgMJBQAAAA==.',
Lo='Loamathor:BAAALgADCgkJHgAAAA==.Lobaxv:BAAALgAECgQJCgAAAA==.Lolenter:BAAALgADCgcJBwAAAA==.Loli:BAAALgADCgQJAgAAAA==.Lonealpha:BAAALgAECgMJAwAAAA==.Lonesource:BAAALgAECgUJCwAAAA==.Lorilyn:BAABLgAECn8bAAIYAAgJfxagBADoAQAYAAgJfxagBADoAQAAAA==.Lorthag:BAAALgAECgQJCgAAAA==.Lovebuz:BAAALgAECgQJBAAAAA==.Loveles:BAAALgADCgIJAgAAAA==.Loverone:BAAALgADCgEJAQAAAA==.',
Lr='Lringecord:BAAALgAECgcJCgAAAA==.',
Lu='Lu:BAAALgADCgEJAQAAAA==.Luckless:BAAALgAECgcJDgAAAA==.Luckyroux:BAAALgADCgYJCAAAAA==.Lumiboba:BAAALgAFFAEJAQAAAA==.Lumilychee:BAAALgAFFAEJAQAAAA==.Lunachick:BAAALgAECgUJCQAAAA==.Lunarus:BAABLgAECn8VAAIZAAYJmA5kAgBAAQAZAAYJmA5kAgBAAQAAAA==.Lurline:BAAALgAFFAEJAgAAAA==.Luvergirl:BAAALgADCgMJAgAAAA==.Luxiu:BAAALgADCgIJAgAAAA==.',
Lv='Lvladin:BAAALgAECgYJBwAAAA==.',
Ly='Lyllies:BAAALgAECgEJAQAAAA==.Lythriaa:BAAALgADCgYJBgAAAA==.',
['Lì']='Lìfe:BAABLgAECn8eAAIHAAkJjhX6GgB0AgAHAAkJjhX6GgB0AgAAAA==.',
Ma='Macloving:BAABLgAECn8VAAIJAAgJkQt8MwCLAQAJAAgJkQt8MwCLAQAAAA==.Madapipa:BAAALgADCgUJBQAAAA==.Maddiablo:BAAALgADCgUJCAAAAA==.Magicpipe:BAAALgAECgUJEQAAAA==.Magrumok:BAAALgAECgYJBwAAAA==.Magthars:BAAALgADCgkJEwAAAA==.Mahnàmahnà:BAAALgADCgYJCQAAAA==.Maká:BAAALgAECgYJCQAAAA==.Malígn:BAAALgAECgcJBAAAAA==.Manbearpig:BAAALgAECgcJBwAAAA==.Mandysmores:BAAALgAECgUJCwABLgAFFAQJDQAGACoPAA==.Marshmalow:BAAALgAECgQJBAAAAA==.',
Mc='Mclovhin:BAAALgAECgIJAgAAAA==.Mcpal:BAAALgAECgMJAwABLgAECgMJBgANAAAAAA==.Mcquade:BAAALgADCgcJBwAAAA==.Mctigly:BAAALgAECgYJBgAAAA==.',
Me='Meals:BAAALgAECgYJCAAAAA==.Meatchunks:BAAALgAECgUJCAAAAA==.Meetras:BAACLgAFFH8HAAIcAAIJqiEHEADWAAAcAAIJqiEHEADWAAAuAAQKfyMAAhwACQmFIKMAALACABwACQmFIKMAALACAAAA.Megagosa:BAAALgAECgUJBgAAAA==.Meganob:BAAALgADCgYJBgAAAA==.Melkiel:BAAALgADCggJCAABLgAECggJIQAWAJslAA==.Mementomorie:BAAALgAECgMJAwAAAA==.Mennopaws:BAAALgADCgcJAQAAAA==.Mesa:BAABLgAECn9hAAIdAAkJ7yYIAAD0AwAdAAkJ7yYIAAD0AwAAAA==.',
Mi='Miclovin:BAAALgAECgYJBgAAAA==.Microplastic:BAABLgAECn8fAAMHAAgJ6hw5BAD8AQAHAAgJ6hw5BAD8AQAMAAIJ4w/XOQBIAAAAAA==.Miniblué:BAAALgAECgMJBgAAAA==.Minimalskill:BAAALgAECgEJAQAAAA==.Minthammer:BAAALgAECgEJAgAAAA==.Mirrin:BAAALgADCgEJAQABLgAECgEJAQANAAAAAA==.Mirumahn:BAAALgADCgkJFwAAAA==.Mistie:BAAALgADCgMJAwAAAA==.',
Mk='Mkultravictm:BAAALgAECgYJDAAAAA==.',
Mo='Moadeab:BAAALgADCgcJDAAAAA==.Mogando:BAAALgADCgUJBQABLgAECgcJHQAZAAIdAA==.Mogrogarg:BAAALgAECgYJDwAAAA==.Mogromage:BAAALgADCgkJCQAAAA==.Mojojojò:BAAALgAECgEJAgAAAA==.Monica:BAAALgAECgMJAwAAAA==.Monkydpuzzle:BAAALgAECgMJAwAAAA==.Moogicmike:BAAALgADCgUJBQAAAA==.Moonwulf:BAAALgADCgcJCgAAAA==.Moonyin:BAAALgAECgUJCQAAAA==.Moosedrool:BAAALgADCgYJBgABLgADCgcJDAANAAAAAA==.Mooster:BAAALgADCgcJBwAAAA==.Moralefist:BAAALgAECgYJBgAAAA==.Mordin:BAAALgADCgUJBwAAAA==.Morenthia:BAAALgAECgYJCgAAAA==.Morgaliice:BAAALgAECgcJDgAAAA==.Morganasz:BAAALgADCgUJBQABLgAECggJJQARAGUbAA==.Mornafah:BAABLgAECn8jAAIfAAgJSyLgAQD1AgAfAAgJSyLgAQD1AgAAAA==.Mornna:BAAALgADCgcJFQABLgAECggJIwAfAEsiAA==.Morrickk:BAAALgADCgUJBQAAAA==.Morriffic:BAAALgADCgYJCAABLgAECgcJGwAiAPMhAA==.Mortarion:BAAALgADCgEJAQAAAA==.Mortigen:BAAALgAECgEJAQAAAA==.Mousethyr:BAAALgAECgcJCwAAAA==.',
Mu='Munric:BAABLgAECn8eAAIKAAgJvBimOQA9AgAKAAgJvBimOQA9AgAAAA==.Murlow:BAAALgADCgQJBQAAAA==.Muteddruid:BAAALgAECgMJAwAAAA==.Mutedfury:BAAALgADCgUJBQAAAA==.Mutelock:BAAALgAECgEJAQAAAA==.',
My='Myboycleetus:BAAALgAECgUJBwABLgADCgYJCQANAAAAAA==.Mykerz:BAAALgAECggJDgAAAA==.Mynon:BAAALgADCgMJAwAAAA==.Mysaeris:BAAALgADCgcJBwAAAA==.Mystie:BAAALgADCgcJBwAAAA==.Myw:BAACLgAFFH8QAAISAAUJPBfYAQCJAQASAAUJPBfYAQCJAQAuAAQKfyQAAhIACAkXJUYDAEYDABIACAkXJUYDAEYDAAAA.',
['Mí']='Míles:BAAALgAECgUJCAAAAA==.',
['Mó']='Mórningstar:BAAALgAECgYJBgAAAA==.',
Na='Nachomama:BAAALgAECgQJBgAAAA==.Nachothings:BAACLgAFFH8MAAIRAAUJ8w/SEwAzAQARAAUJ8w/SEwAzAQAuAAQKfx4AAxEACAkeIGQbAK4CABEACAkeIGQbAK4CACQAAgmBFhBbAHUAAAAA.Nakedindee:BAAALgAECgYJBgAAAA==.Nakedindy:BAAALgADCgcJAwABLgAECgYJBgANAAAAAA==.Nakedlizard:BAAALgAECgQJBAAAAA==.Nashonkle:BAAALgADCgEJAQAAAA==.Navarth:BAAALgADCgYJCwAAAA==.',
Nb='Nbayoungboy:BAAALgADCgUJBQAAAA==.',
Ne='Nearlydeath:BAAALgAECgYJCwAAAA==.Nedria:BAAALgADCgcJDAAAAA==.Nedwar:BAAALgAECgUJCQAAAA==.Nenghis:BAAALgAECgYJDwAAAA==.Neur:BAAALgADCgMJAwABLgAECgQJBAANAAAAAA==.Nevän:BAAALgADCgcJBwAAAA==.Nezha:BAAALgAECgcJBwABLgAECgcJGQAbAGUkAA==.',
Ni='Nickelos:BAAALgADCgcJCQAAAA==.Nicksmonk:BAAALgADCgMJAwAAAA==.Nightmist:BAAALgADCggJEAAAAA==.Nihility:BAABLgAECn8ZAAIbAAcJZSRXEQDwAgAbAAcJZSRXEQDwAgAAAA==.Nirgand:BAAALgAECgEJAQABLgAECgcJHQAZAAIdAA==.Nixxie:BAAALgAECgIJAgAAAA==.',
No='Nochoice:BAAALgADCgEJAQAAAA==.Noodlebark:BAAALgAECgEJAQAAAA==.Noodlestang:BAAALgAECgYJDAAAAA==.Nool:BAAALgAECgUJCAAAAA==.Nophel:BAAALgADCggJGQAAAA==.Noraelin:BAAALgADCgYJBwAAAA==.Nordily:BAAALgADCgMJAwAAAA==.Norgand:BAABLgAECn8dAAMZAAcJAh1PAwBqAgAZAAcJAh1PAwBqAgAhAAEJAACxawA8AAAAAA==.Nornar:BAABLgAECn8UAAIBAAYJiRe9FwBPAQABAAYJiRe9FwBPAQAAAA==.Norsehammer:BAAALgADCgcJBwAAAA==.Nosleep:BAACLgAFFH8GAAIWAAMJmgSLBAC8AAAWAAMJmgSLBAC8AAAuAAQKfxoAAhYABwkHDXQgAD0BABYABwkHDXQgAD0BAAAA.Nosleepo:BAAALgADCgkJIgAAAA==.',
Ny='Nydeath:BAAALgAECgIJBAAAAA==.Nyduss:BAAALgAECgcJCgAAAA==.Nyxpal:BAAALgADCgEJAQAAAA==.',
['Nù']='Nùtter:BAABLgAECn8YAAIHAAgJYRQUMwDfAQAHAAgJYRQUMwDfAQAAAA==.',
Oa='Oath:BAAALgADCggJCAAAAA==.',
Ob='Obrlord:BAAALgAECgUJBwAAAA==.Obvy:BAABLgAECn8UAAIcAAgJsxTaGgAqAgAcAAgJsxTaGgAqAgAAAA==.',
Of='Offeiriad:BAAALgAECgIJAgAAAA==.',
Om='Omaboa:BAABLgAECn8ZAAIJAAcJPSICAgBOAgAJAAcJPSICAgBOAgAAAA==.',
On='Onrai:BAAALgADCgEJAQAAAA==.Onî:BAAALgADCgEJAQAAAA==.',
Oo='Oof:BAABLgAECn8XAAMFAAgJJxIVBgClAQAFAAgJJxIVBgClAQAYAAEJbwoygwAuAAAAAA==.',
Op='Ophinal:BAAALgADCgcJDAAAAA==.Optimize:BAABLgAECn8YAAIGAAYJJh5XdgDlAQAGAAYJJh5XdgDlAQAAAA==.',
Or='Orastal:BAAALgAECgMJAwABLgAECgYJDAANAAAAAA==.Ordinia:BAAALgAECgMJBQAAAA==.',
Os='Ossian:BAAALgADCgUJBwAAAA==.',
Pa='Pandadander:BAAALgADCgYJCQAAAA==.Pandalo:BAAALgADCgYJBgAAAA==.Panxpan:BAAALgAECgYJBQAAAA==.Papipa:BAABLgAECn8lAAQXAAcJCifiAwAmAwAXAAcJCifiAwAmAwAYAAYJfCQFEQBbAgAFAAEJPiYqWABcAAAAAA==.',
Pe='Pebbles:BAAALgAECgEJAQABLgAECgYJEwANAAAAAA==.Pelarn:BAAALgADCgYJCwAAAA==.Pengwei:BAEALgAFFAIJAwABLgAFFAMJBgAPAC4jAA==.Penumbrix:BAAALgADCgcJDAAAAA==.Pepperbreath:BAABLgAECn8YAAIdAAgJRgx8GgC3AQAdAAgJRgx8GgC3AQAAAA==.Perfectstorm:BAAALgAECgYJCQAAAA==.Persefo:BAAALgADCggJCAAAAA==.Petmeimtame:BAAALgAECgQJAwAAAA==.',
Ph='Phadenstar:BAAALgAECgMJAwAAAA==.',
Pi='Pickleburnz:BAAALgADCgQJBAAAAA==.Pinkpwnage:BAAALgAECgEJAQAAAA==.',
Pm='Pmmeurdog:BAAALgADCgYJBgAAAA==.',
Po='Pocketsmonk:BAAALgAECgQJDAAAAA==.Podnuh:BAAALgAECgEJAQAAAA==.Pokemcjoke:BAAALgAECgIJAgAAAA==.Ponchoe:BAAALgADCgcJDgAAAA==.Poobahdrag:BAABLgAECn8iAAMdAAkJABxMCgCRAgAdAAkJABxMCgCRAgAOAAQJ9hLoKgDGAAAAAA==.Pools:BAAALgADCgYJCQAAAA==.Popnosmoke:BAAALgAECgYJEwAAAA==.Porzok:BAABLgAECn8cAAIBAAcJWh3QAwC5AQABAAcJWh3QAwC5AQAAAA==.Poxxel:BAAALgADCgMJAwABLgAECggJIQAKAKUiAA==.',
Pu='Puhd:BAAALgAECgEJAQAAAA==.Punchimon:BAAALgADCgYJBgAAAA==.Putraa:BAAALgADCgYJBgAAAA==.Putridstrike:BAAALgAECgIJAgAAAA==.',
Py='Pyrra:BAAALgADCgcJBwAAAA==.',
['Pü']='Pürple:BAAALgAECgYJDQAAAA==.',
Qt='Qtiy:BAABLgAECn8cAAIbAAgJYSM1AgCLAgAbAAgJYSM1AgCLAgAAAA==.Qty:BAAALgADCgIJAQABLgAECggJHAAbAGEjAA==.',
Qu='Queeg:BAAALgADCgEJAgAAAA==.Quickben:BAAALgAECgQJBAAAAA==.Quintalen:BAAALgAECgQJBwAAAA==.',
Ra='Raawwrr:BAAALgADCgcJBgAAAA==.Racken:BAAALgAECgcJEAAAAA==.Raedona:BAAALgADCgQJBAAAAA==.Ragon:BAAALgADCgEJAQAAAA==.Raharn:BAAALgAECgUJCQAAAA==.Raincheckplz:BAAALgADCgIJAgAAAA==.Ranzor:BAABLgAECn8XAAIWAAgJYBV5EAABAgAWAAgJYBV5EAABAgAAAA==.Rauden:BAAALgADCgMJBAAAAA==.Raveyn:BAAALgAECgYJEAAAAA==.',
Re='Rebecca:BAABLgAECn8VAAIcAAgJMSDeAACMAgAcAAgJMSDeAACMAgAAAA==.Redmaine:BAAALgADCgEJAQAAAA==.Reef:BAABLgAECn8bAAIRAAgJ3CMLEAD+AgARAAgJ3CMLEAD+AgAAAA==.Rekieuwu:BAAALgAECgcJEQAAAA==.Releaf:BAAALgAECgIJAgAAAA==.Remarista:BAAALgADCgMJAwAAAA==.Remixed:BAAALgADCgMJAwABLgAECgYJBQANAAAAAA==.Repentance:BAAALgAECgQJAwAAAA==.Retnuh:BAABLgAECn8aAAIPAAgJtRqcBAA1AgAPAAgJtRqcBAA1AgAAAA==.',
Rh='Rheiner:BAAALgADCgkJDgAAAA==.Rhynpi:BAAALgADCgIJAgAAAA==.Rhynsen:BAAALgADCgYJBgAAAA==.',
Ri='Ribez:BAAALgADCggJEAAAAA==.Ricoxx:BAAALgAECgEJAgAAAA==.Riftseeker:BAAALgAECgYJCwAAAA==.Rikori:BAAALgAECgUJCgAAAA==.Rimmjab:BAAALgAECgEJAQAAAA==.Rinzz:BAAALgADCgcJDQABLgAECgMJCAANAAAAAA==.Ristin:BAAALgADCgEJAQAAAA==.',
Ro='Roderika:BAAALgADCgUJBQABLgAFFAMJBwADAGcVAA==.Rogald:BAAALgAECgMJBQAAAA==.Roids:BAAALgADCgYJEAAAAA==.Rolockrad:BAAALgAECgMJAwAAAA==.Rord:BAABLgAECn8hAAMKAAgJpSKpCwAwAwAKAAgJpSKpCwAwAwAgAAgJQCAMDwCdAgAAAA==.Rorloc:BAAALgADCgIJAgAAAA==.Rosalei:BAAALgADCgMJAwAAAA==.Rownin:BAAALgADCgEJAgAAAA==.Royaljalopen:BAAALgAECgEJAQAAAA==.',
Ru='Ruinaria:BAAALgADCgMJAwAAAA==.Rumblepak:BAAALgADCgcJDwAAAA==.Rumblez:BAAALgADCgEJAQAAAA==.Runicstrike:BAABLgAECn8dAAMEAAkJuyS6BACHAwAEAAkJuyS6BACHAwAUAAMJnR/nLQDQAAAAAA==.',
Rz='Rzarazor:BAABLgAECn8VAAIGAAYJ2QqX1wBBAQAGAAYJ2QqX1wBBAQAAAA==.',
Sa='Sadeye:BAAALgAECgYJCAAAAA==.Salvation:BAAALgADCgYJBgAAAA==.Samborn:BAAALgADCgEJAQAAAA==.Sanctustrike:BAAALgAECgMJAwAAAA==.Sandero:BAAALgAECggJDgAAAA==.Saraphina:BAAALgAECgYJEQAAAA==.Sathrell:BAAALgADCgUJBQAAAA==.Savageborn:BAAALgADCgIJAgAAAA==.Savagetime:BAABLgAECn8VAAIGAAcJQBQOlwCmAQAGAAcJQBQOlwCmAQAAAA==.',
Sc='Scarletwitçh:BAAALgADCgIJAgABLgAECggJHAARANQeAA==.Schnooks:BAAALgAECgEJAgABLgAECgQJBAANAAAAAA==.Scyythe:BAAALgADCgEJAQAAAA==.',
Se='Sedor:BAAALgADCgEJAQAAAA==.Sellandre:BAAALgAECgIJBQAAAA==.Selvalamhi:BAAALgADCgcJDQABLgAECgcJHQAZAAIdAA==.Semi:BAABLgAECn8aAAIPAAcJKRKkFABWAQAPAAcJKRKkFABWAQAAAA==.Sensenah:BAAALgADCgUJEgAAAA==.Serenitie:BAAALgADCgcJDAAAAA==.Serpompom:BAAALgAECgUJBgAAAA==.',
Sh='Shadowbugger:BAAALgADCgcJBwAAAA==.Shadowknigh:BAAALgAECgMJAwAAAA==.Shalirah:BAAALgAECgEJAgABLgAECgYJEAANAAAAAA==.Sharaudra:BAAALgADCgMJAwABLgAECggJIQAKAKUiAA==.Shengal:BAABLgAECn8bAAMIAAYJgQR2EwCtAAAIAAYJgQR2EwCtAAAeAAEJQQFojgASAAAAAA==.Sherfight:BAABLgAECn8gAAMYAAgJkxVDHwDmAQAYAAgJkxVDHwDmAQAFAAYJLRnlDQAWAQAAAA==.Shiftyzegg:BAAALgAECgEJAQAAAA==.Shipp:BAAALgAECgMJBAAAAA==.Shmakk:BAAALgADCgYJCQAAAA==.Shmebulon:BAAALgADCgEJAQAAAA==.Shopkeep:BAAALgADCgEJAQAAAA==.Shund:BAAALgADCgQJBQABLgAECgQJBAANAAAAAA==.Shunkd:BAAALgAECgQJBAAAAA==.Shyjinx:BAAALgADCgEJAQAAAA==.Shyvala:BAAALgAECgcJEQAAAA==.',
Si='Sig:BAAALgADCgEJAQAAAA==.Silithaine:BAAALgAECgEJAQAAAA==.Silvarogue:BAAALgAECgYJCQAAAA==.',
Sk='Skinwalk:BAAALgADCgUJBQAAAA==.Skrillen:BAAALgADCgcJBwAAAA==.',
Sl='Slackerftw:BAAALgAECgMJBwAAAA==.Slamhog:BAAALgAECgcJEgAAAA==.Slayaa:BAAALgADCgEJAQAAAA==.Sleazo:BAAALgADCgUJBQAAAA==.Sleepdemon:BAAALgADCgEJAQAAAA==.Sleew:BAABLgAECn8bAAMhAAgJMRcMEQDFAQAhAAcJKRUMEQDFAQAbAAUJpRpCbgCEAQAAAA==.Slippydippy:BAAALgAECgMJAwAAAA==.Slobbin:BAAALgADCgUJBQAAAA==.Sloppydrag:BAAALgAECgQJBQAAAA==.',
Sm='Smacku:BAAALgADCggJDgAAAA==.Smaugly:BAAALgAECgcJEwAAAA==.Smaugumz:BAAALgAECgQJBAAAAA==.Smorz:BAAALgADCgMJAwAAAA==.',
Sn='Snackalot:BAAALgADCgcJCAAAAA==.Snocaps:BAAALgAECgEJAQAAAA==.Snowblade:BAAALgAECgYJCwAAAA==.',
So='Soggypringle:BAAALgADCgIJAgAAAA==.Soleilroi:BAAALgAECgQJCQAAAA==.Soletaken:BAAALgADCgMJCAAAAA==.Solson:BAAALgADCgUJBQAAAA==.',
Sp='Specsdraco:BAABLgAECn8XAAIQAAgJYyK1DADgAgAQAAgJYyK1DADgAgAAAA==.Spewpuke:BAABLgAECn8xAAIWAAgJixw5AgADAgAWAAgJixw5AgADAgAAAA==.Spinlock:BAAALgAECgEJAQAAAA==.',
St='Staci:BAABLgAECn8YAAIHAAgJTxM0BwCvAQAHAAgJTxM0BwCvAQAAAA==.Starfree:BAABLgAECn8VAAMXAAgJxgi5KgBEAQAXAAcJQAm5KgBEAQAFAAIJLgf7WQBRAAAAAA==.Steelhoof:BAAALgAECgEJAQAAAA==.Steelsham:BAABLgAECn8aAAMJAAgJjwefDAAzAQAJAAgJjwefDAAzAQASAAYJuwshWgAgAQAAAA==.Stgermain:BAABLgAECn8gAAMXAAkJlRk3CQCoAgAXAAkJRhg3CQCoAgAYAAYJbhZaMgB2AQAAAA==.Stinkybinks:BAAALgADCgYJBgAAAA==.Stonedmaster:BAAALgAECgMJBgAAAA==.Strickdic:BAAALgADCgcJCQAAAA==.Strikeanywer:BAAALgADCgUJBQAAAA==.Stuard:BAAALgAECgQJCAAAAA==.Stuardh:BAAALgADCgcJDAAAAA==.',
Su='Superstoned:BAAALgADCgcJEAAAAA==.Surudruid:BAAALgADCgMJBQAAAA==.',
Sw='Swampy:BAAALgADCgUJBQAAAA==.Swolbõi:BAAALgAECgQJBgAAAA==.',
Sy='Sykes:BAAALgAFFAMJAwAAAA==.Sylrana:BAABLgAECn8XAAIiAAgJUBUIQgCZAQAiAAgJUBUIQgCZAQAAAA==.Sylvaelrodas:BAAALgADCggJCAAAAA==.Sylvarion:BAAALgADCgUJBQAAAA==.Sylvie:BAAALgADCgcJDAABLgAECgQJBAANAAAAAA==.Sylzyrus:BAABLgAECn8iAAIdAAgJthpTAQBWAgAdAAgJthpTAQBWAgAAAA==.',
Ta='Tabuta:BAAALgAECgQJCAAAAA==.Taktikil:BAAALgADCgkJFgAAAA==.Taktikyl:BAAALgADCgcJDQABLgADCgkJFgANAAAAAA==.Talizar:BAAALgADCgEJAgAAAA==.Talor:BAAALgADCgYJCAAAAA==.Talrad:BAAALgAECgYJDAAAAA==.Tarrot:BAAALgADCgIJAgAAAA==.Tauralyon:BAABLgAECn8bAAIgAAgJ5x3TAwA9AgAgAAgJ5x3TAwA9AgAAAA==.Tazerxface:BAAALgAECgQJBQAAAA==.Tazomfg:BAAALgADCgEJAgAAAA==.',
Te='Teenyhands:BAAALgAECgQJCQAAAA==.Telarae:BAABLgAECn8WAAIKAAgJ9hPVVADjAQAKAAgJ9hPVVADjAQAAAA==.Teldrasa:BAACLgAFFH8GAAIiAAIJQxLhGQCVAAAiAAIJQxLhGQCVAAAuAAQKfyQAAyIACAntGpwIANYBACIACAntGpwIANYBACMABgk7E7QYADgBAAAA.Tellera:BAAALgAECgQJBQAAAA==.Tempér:BAAALgADCgUJCgABLgAECgcJBAANAAAAAA==.Tereshi:BAAALgAECgEJAQABLgAECgYJCAANAAAAAA==.Teugelsi:BAAALgADCgEJAQAAAA==.Teukard:BAAALgADCgIJAwAAAA==.',
Th='Thebigmon:BAABLgAECn8aAAIJAAcJ5RcHCwBLAQAJAAcJ5RcHCwBLAQAAAA==.Thedabara:BAAALgAECgMJAwAAAA==.Thegriddler:BAAALgAECgEJAQAAAA==.Thesolartaco:BAAALgADCgYJCAAAAA==.Thewhite:BAAALgAECggJEwAAAA==.Thiccjinbei:BAAALgAECgMJBgAAAA==.Thingamabob:BAAALgAECgMJBgAAAA==.Thordriel:BAAALgAECgYJDgAAAA==.Threna:BAAALgADCgcJBwAAAA==.Thrisper:BAABLgAECn8VAAIiAAYJ0wUgHgDGAAAiAAYJ0wUgHgDGAAAAAA==.Thrudheals:BAAALgAECgQJBwAAAA==.',
Ti='Tickeld:BAAALgAECgIJAgAAAA==.Tintaglia:BAAALgADCgEJAQAAAA==.Tinytina:BAAALgAFFAIJAgAAAA==.',
To='Tocino:BAAALgADCgMJAwAAAA==.Tofrenm:BAAALgAECgUJCQAAAA==.Togashi:BAAALgADCgcJBwAAAA==.Tombomb:BAAALgAECggJDQAAAA==.Tomspoojer:BAAALgAECgEJAQAAAA==.Topnacho:BAAALgAECgYJEAABLgAFFAUJDAARAPMPAA==.Torgrim:BAAALgAECgIJAgAAAA==.',
Tr='Traitor:BAAALgADCgcJCQAAAA==.Traumatik:BAAALgAECgYJEgAAAA==.Treespirit:BAAALgAECgEJAQAAAA==.Trekin:BAAALgAECgIJAgAAAA==.Trigospread:BAAALgADCgUJBQABLgAECgIJAgANAAAAAA==.Trisperth:BAAALgADCgQJBgAAAA==.Trocity:BAAALgAECgIJAwAAAA==.Trollyjoebo:BAAALgADCgEJAQAAAA==.Trudeathh:BAABLgAECn8UAAMUAAYJYiNYEAAFAgAUAAYJYiNYEAAFAgAVAAQJ9grjDgCzAAAAAA==.',
Tu='Turbosins:BAAALgAECgIJAgAAAA==.',
Tw='Twestside:BAAALgAECgIJAgAAAA==.',
Ty='Tylenolbaby:BAAALgADCgcJDQABLgAECgYJEwANAAAAAA==.Typhoone:BAAALgAECggJDQAAAA==.Tyranbae:BAAALgAECgYJBgABLgAECgkJIgAdAAAcAA==.Tyrur:BAAALgAECgYJCwAAAA==.Tytherion:BAAALgADCgYJCwAAAA==.',
['Tö']='Tönesies:BAAALgAECgIJAgAAAA==.',
Ug='Ugbukk:BAAALgADCgcJBwAAAA==.Uglyashell:BAAALgADCgkJFwAAAA==.',
Um='Umbriel:BAAALgAECgEJAQAAAA==.Umbrielagosa:BAACLgAFFH8KAAIdAAQJcRtmAgB/AQAdAAQJcRtmAgB/AQAuAAQKfx0AAh0ACAnQHfUHALwCAB0ACAnQHfUHALwCAAAA.',
Un='Unclefingiez:BAAALgADCgEJAQAAAA==.',
Ur='Urotherdaddy:BAAALgAECgYJEQAAAA==.',
Va='Vaelith:BAABLgAECn8VAAIGAAgJ2xlKRgBlAgAGAAgJ2xlKRgBlAgAAAA==.Valerikka:BAAALgAECgEJAQAAAA==.Valkaire:BAAALgAECgEJAQAAAA==.Valnyx:BAAALgADCgEJAQAAAA==.Valsorin:BAAALgAECgUJCwAAAA==.Valtaea:BAABLgAECn8aAAIGAAgJYBYUWgArAgAGAAgJYBYUWgArAgAAAA==.Valwhoard:BAAALgADCgcJCAAAAA==.Vanille:BAAALgADCgEJAQAAAA==.Varyndra:BAAALgAECgEJAQAAAA==.',
Ve='Velour:BAAALgAECgYJDQABLgAECgUJCQANAAAAAA==.Velzhara:BAAALgADCgMJAwAAAA==.',
Vi='Vigilus:BAAALgAECgMJBAAAAA==.Vividdevour:BAAALgADCgMJAwAAAA==.Vixol:BAAALgAECgYJDgAAAA==.',
Vo='Voidheals:BAAALgAECgMJBgAAAA==.Voids:BAAALgADCgEJAgAAAA==.Volairne:BAAALgAECgMJBwAAAA==.Voodoowhodo:BAAALgAECgQJBQAAAA==.',
Wa='Waarsêer:BAAALgAECgYJCQAAAA==.Wackah:BAABLgAECn8iAAMhAAkJfx2/AgDXAgAhAAkJfx2/AgDXAgAbAAIJJQq4PwBtAAAAAA==.Wafflxs:BAABLgAECn8WAAIIAAgJmyTZAwA3AwAIAAgJmyTZAwA3AwAAAA==.Wanpisu:BAAALgAECgcJEgAAAA==.Wardaddy:BAAALgAECgEJAQAAAA==.Wardorable:BAAALgADCgMJAwAAAA==.Warmage:BAAALgADCgIJAgAAAA==.Wartirus:BAEBLgAECn8aAAIbAAgJbhl2CQDZAQAbAAgJbhl2CQDZAQAAAA==.',
We='Weezing:BAAALgAECgEJAgAAAA==.Wellfookthat:BAAALgAECgUJCwAAAA==.Wellfookyew:BAAALgADCgMJAwAAAA==.Weolf:BAAALgAECgYJEQAAAA==.',
Wh='Wheelchair:BAAALgAECgQJDAABLgAECgYJCAANAAAAAA==.Whyfeedzwhy:BAAALgAECgEJAQAAAA==.Whyvala:BAAALgAECgcJEQAAAA==.',
Wi='Wiisp:BAAALgADCgcJCwAAAA==.Wilmadikfit:BAAALgAECgMJAwAAAA==.Wintersidemo:BAABLgAECn8ZAAIbAAgJPBVAOwAfAgAbAAgJPBVAOwAfAgAAAA==.',
Wo='Wolnney:BAAALgAECgYJEgAAAA==.',
Wr='Wraithian:BAAALgAECgUJBQAAAA==.',
Wy='Wylar:BAABLgAECn8XAAIEAAcJoRRJbwCqAQAEAAcJoRRJbwCqAQAAAA==.',
Xa='Xalatoes:BAABLgAFFH8HAAISAAQJthsHBgBoAQASAAQJthsHBgBoAQAAAA==.',
Xe='Xeb:BAAALgADCgEJAQAAAA==.Xenar:BAAALgADCgIJAwAAAA==.Xerathor:BAAALgAECgYJDgAAAA==.',
Xi='Xim:BAAALgAECgIJAgAAAA==.',
Xy='Xyne:BAAALgAECgEJAQAAAA==.',
Xz='Xziled:BAAALgAECgEJAgAAAA==.',
Ya='Yakihunt:BAAALgADCgIJAgAAAA==.',
Yo='Yogonine:BAACLgAFFH8GAAIIAAMJZhcvCwDzAAAIAAMJZhcvCwDzAAAuAAQKfyQAAggACQk6IEcDAEgDAAgACQk6IEcDAEgDAAAA.Yoshie:BAAALgAECgMJCAAAAA==.',
Yu='Yunna:BAAALgADCgcJDAAAAA==.',
Yx='Yxma:BAAALgAECgYJEgAAAA==.',
Za='Zanetta:BAAALgADCgYJGgAAAA==.Zanydruid:BAAALgAECgUJCAAAAA==.Zanza:BAAALgAECgYJDAAAAA==.Zariana:BAAALgADCgEJAQAAAA==.',
Ze='Zekku:BAAALgAECgIJBAAAAA==.Zephadawn:BAAALgAECgEJAQAAAA==.',
Zh='Zhamazu:BAAALgADCgUJCgAAAA==.Zhy:BAAALgAECgYJCgAAAA==.Zhygar:BAAALgAECgUJCQAAAA==.',
Zi='Zinniah:BAAALgAECgQJBAAAAA==.Zipthud:BAAALgAECgMJCAAAAA==.',
Zo='Zodin:BAAALgADCgQJBAABLgAECgUJCgANAAAAAA==.Zombiez:BAAALgAECgMJAwAAAA==.',
Zu='Zujoth:BAAALgADCgcJFQAAAA==.',
['Âb']='Âbaddön:BAAALgADCgUJBgAAAA==.',
['Çh']='Çhefhunter:BAAALgADCgcJBwAAAA==.Çhloe:BAAALgADCgIJAgAAAA==.',
['Ðr']='Ðrstrange:BAAALgAECgIJAgABLgAECggJHAARANQeAA==.',
['Øb']='Øbitø:BAAALgADCgUJBQAAAA==.',
['ßo']='ßoomßoom:BAAALgADCgUJBQAAAA==.',
['ßø']='ßøß:BAAALgADCgEJAQAAAA==.',
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

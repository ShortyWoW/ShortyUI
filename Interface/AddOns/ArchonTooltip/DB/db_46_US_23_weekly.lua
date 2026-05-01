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

local lookup = {'Hunter-Survival','Mage-Fire','Evoker-Augmentation','DeathKnight-Unholy','Priest-Shadow','Mage-Frost','Warrior-Fury','Monk-Mistweaver','Shaman-Elemental','Unknown-Unknown','Paladin-Retribution','Mage-Arcane','Warrior-Arms','DemonHunter-Devourer','Evoker-Devastation','Hunter-BeastMastery','Hunter-Marksmanship','Warlock-Demonology','Warlock-Destruction','DemonHunter-Vengeance','Shaman-Restoration','Monk-Brewmaster','Warrior-Protection','DeathKnight-Blood','DeathKnight-Frost','Priest-Discipline','Priest-Holy','Warlock-Affliction','Druid-Guardian','Rogue-Subtlety','Evoker-Preservation','Shaman-Enhancement','Monk-Windwalker','Paladin-Holy','Druid-Restoration','Druid-Feral','Paladin-Protection','DemonHunter-Havoc',}
local provider = {region='US',realm='Azgalor',name='US',type='weekly',zone=46,date='2026-05-01',data={Aa='Aarahunt:BAABLgAECn8oAAIBAAgJHwfgDwBiAQABAAgJHwfgDwBiAQAAAA==.',
Ab='Abente:BAAALgAECgEJAQAAAA==.',
Ac='Acarin:BAAALgAECgUJCwAAAA==.',
Ad='Adawna:BAAALgAECgYJCQAAAA==.Addio:BAAALgADCgcJDAAAAA==.Adgalor:BAAALgADCgkJCQAAAA==.Adrenaline:BAAALgADCgMJAQAAAA==.Adsaw:BAABLgAECn8cAAICAAgJyBnMAAAkAgACAAgJyBnMAAAkAgAAAA==.Adula:BAAALgAECgUJCgABLgAFFAQJCAADALwTAA==.',
Ae='Aelunara:BAABLgAECn8bAAIEAAYJoBwILgCDAQAEAAYJoBwILgCDAQAAAA==.Aer:BAAALgADCgcJDgAAAA==.Aerostalim:BAAALgAECgUJBwAAAA==.',
Af='Aftershocks:BAAALgAECgYJEwAAAA==.',
Ah='Ahnanji:BAAALgADCgEJAQAAAA==.Ahoydorei:BAAALgAECgEJAQAAAA==.',
Ai='Aijha:BAAALgADCgMJAwAAAA==.Ailric:BAABLgAECn8dAAIFAAYJgxiiEQB7AQAFAAYJgxiiEQB7AQAAAA==.',
Ak='Akivra:BAAALgAECgYJBgAAAA==.',
Al='Alanon:BAAALgADCgEJAQAAAA==.Alanorae:BAAALgADCgkJDAAAAA==.Alarakian:BAAALgAECgIJAgAAAA==.Alassae:BAAALgADCgcJCQAAAA==.Alcapown:BAAALgAECgQJDwAAAA==.Aldrea:BAAALgAECgQJBgAAAA==.Aleco:BAAALgADCgcJDAAAAA==.Alexdaelfs:BAAALgAECgEJAQAAAA==.Aliakin:BAABLgAECn8bAAIGAAgJDh9yFgApAgAGAAgJDh9yFgApAgAAAA==.Alinda:BAAALgADCgYJCAABLgAECggJGgAHAHkWAA==.Alleviel:BAAALgAECgkJDwAAAA==.Aloros:BAAALgAFFAIJAgAAAA==.Alphirion:BAAALgAECgYJDAAAAA==.Alyssachik:BAABLgAECn8UAAIIAAYJrw/vNAAdAQAIAAYJrw/vNAAdAQAAAA==.',
Am='Amaeradin:BAAALgAECgUJBQAAAA==.Amarxd:BAACLgAFFH8GAAIJAAIJtRwdFwCuAAAJAAIJtRwdFwCuAAAuAAQKfxsAAgkABwnlIb8aAD0CAAkABwnlIb8aAD0CAAAA.Amashira:BAAALgAECgQJBAAAAA==.Ambosi:BAAALgAECgYJDAAAAA==.',
An='Anamae:BAAALgADCgIJAgAAAA==.Anarchtear:BAAALgAECgYJDgAAAA==.Andesipa:BAAALgAECgYJEgAAAA==.Anduin:BAAALgAECgEJAQAAAA==.Anetha:BAAALgAECgYJCgAAAA==.Angerclaw:BAAALgAECgYJEQAAAA==.Angrybirdee:BAAALgAECgMJAwAAAA==.Ankaramessi:BAAALgAECgYJCQAAAA==.Annaalista:BAAALgAECgYJDwAAAA==.Annulled:BAAALgADCgMJAwABLgAECgUJBwAKAAAAAA==.',
Ap='Apollosolo:BAAALgADCgIJAgAAAA==.Apoth:BAAALgAECgcJAgAAAA==.',
Ar='Aradrad:BAAALgADCgUJBwAAAA==.Arakisa:BAAALgAECgQJCAAAAA==.Aranhferizzi:BAAALgADCgYJEgAAAA==.Arazara:BAAALgADCgIJAgAAAA==.Arcaenus:BAAALgAECgQJBgABLgAECggJFwALAEEiAA==.Archspally:BAAALgADCgEJAgAAAA==.Arivian:BAAALgAECgYJBAAAAA==.Arkileous:BAABLgAECn8eAAMGAAcJgBsoQQBrAQAGAAcJgBsoQQBrAQAMAAEJqg+WHQA3AAAAAA==.Arkmage:BAAALgADCgcJBwAAAA==.Artemmis:BAACLgAFFH8FAAIBAAMJ/wMjEQCEAAABAAMJ/wMjEQCEAAAuAAQKfxoAAgEABwnnG6oLABcCAAEABwnnG6oLABcCAAAA.',
As='Assapopolous:BAAALgAECgYJCgAAAA==.',
At='Atalmon:BAABLgAECn8cAAILAAgJwx+GDgBNAgALAAgJwx+GDgBNAgAAAA==.Atticos:BAAALgAECgYJCgAAAA==.',
Av='Avastin:BAAALgAECgUJBQAAAA==.',
Aw='Awni:BAABLgAECn8fAAINAAgJZB7uBQB0AgANAAgJZB7uBQB0AgAAAA==.',
Az='Azarinth:BAAALgAECgQJBAAAAA==.Azenastra:BAAALgAECgEJAQAAAA==.',
Ba='Babadookk:BAABLgAECn8VAAIOAAgJRB0oQQDvAQAOAAgJRB0oQQDvAQAAAA==.Bahbahr:BAACLgAFFH8GAAIGAAIJYBI6SgCqAAAGAAIJYBI6SgCqAAAuAAQKfyAAAgYACAl9InYUADcCAAYACAl9InYUADcCAAAA.Bahrim:BAAALgAECgQJCAAAAA==.Balarian:BAAALgADCgkJEQAAAA==.Balefirebob:BAABLgAECn8cAAMDAAgJphGODwCWAQADAAgJWBGODwCWAQAPAAIJ/w/FNQBnAAAAAA==.Bangbangji:BAAALgADCgMJAwAAAA==.Bangis:BAAALgADCgcJBwABLgAECggJIgAIAL4aAA==.Baphome:BAAALgAECgMJAwAAAA==.Barkntank:BAAALgAECgEJAQAAAA==.Barreloferal:BAAALgAECgMJBAAAAA==.Bartholomeow:BAAALgAECgIJAgAAAA==.Batohar:BAAALgADCgEJAQAAAA==.Battlebeats:BAAALgADCgIJAgAAAA==.Battlebelle:BAAALgAECgYJCQAAAA==.Baxx:BAAALgADCgkJCwAAAA==.Bazzoo:BAAALgAECgYJDwAAAA==.',
Be='Beachbabe:BAAALgAFFAEJAgAAAA==.Bendable:BAAALgADCgEJAQAAAA==.Berrd:BAAALgAECgMJAwAAAA==.Bethezar:BAAALgAECgUJBwAAAA==.',
Bh='Bhangbhang:BAABLgAECn8iAAIIAAgJvho7CAAzAgAIAAgJvho7CAAzAgAAAA==.',
Bi='Bigboitaur:BAAALgADCgEJAQAAAA==.Biggerbits:BAAALgAECgEJAQAAAA==.Bigkrayze:BAAALgAECgYJDgAAAA==.Bigpapapump:BAAALgAECgYJBQAAAA==.Bimboblyad:BAABLgAECn+lAAQQAAkJAycIAQA2AwARAAgJ+SaxAQClAwAQAAgJ/CYIAQA2AwABAAgJxCWpAAAMAwAAAA==.Birdupp:BAAALgADCgEJAgAAAA==.Bizzarro:BAAALgAECgYJEAAAAA==.Bizzkitt:BAAALgADCgkJEAAAAA==.',
Bl='Blackwîdow:BAABLgAECn8eAAIOAAgJ7iF9BACjAgAOAAgJ7iF9BACjAgAAAA==.Blaigne:BAAALgADCgcJCwAAAA==.Blizimcguire:BAAALgAECgQJBQAAAA==.Bloodycat:BAAALgAECgMJAwAAAA==.Bloodymenses:BAAALgADCgkJEwAAAA==.Bluerose:BAAALgAECgYJCgAAAA==.Blurry:BAAALgAECgEJAQAAAA==.',
Bo='Bonngo:BAAALgAECgEJAgAAAA==.Boofgodrekk:BAAALgAECgMJBAAAAA==.Boofkokaina:BAAALgAECgEJAQAAAA==.Boofydoo:BAAALgADCgIJAgAAAA==.',
Br='Brannen:BAAALgAECgUJBwAAAA==.Brayicela:BAAALgADCgQJBAABLgAECgUJCgAKAAAAAA==.Brazzii:BAAALgADCgYJBgAAAA==.Bricksanchez:BAAALgAECgMJAwAAAA==.Brindo:BAAALgADCgUJBwAAAA==.Bringbags:BAAALgADCgMJAwAAAA==.Britneyfears:BAAALgAECgYJCwAAAA==.Bro:BAAALgAECgIJAgAAAA==.Brokentuskz:BAAALgAECgUJBQABLgAECggJJAALACwVAA==.Broten:BAAALgADCgMJAwAAAA==.Brëwskï:BAAALgADCgEJAQAAAA==.',
Bu='Buffbutton:BAAALgAECgYJDQAAAA==.Bulistus:BAAALgADCgIJAgAAAA==.Bulszeye:BAAALgAECgYJCwAAAA==.Bumme:BAAALgAECgYJBgAAAA==.Burningwave:BAABLgAECn8YAAMSAAcJOxzVJQCYAQASAAcJOxzVJQCYAQATAAEJ+QukcQA0AAAAAA==.Buzzie:BAAALgADCgYJCAAAAA==.',
Bw='Bwonsamdiboy:BAAALgADCgIJAgAAAA==.',
Bx='Bxndo:BAAALgAECgEJAgAAAA==.',
Ca='Caerisma:BAAALgAECggJHwAAAQ==.Calebsdemon:BAAALgADCgIJAgAAAA==.Caltha:BAAALgADCgcJBwAAAA==.Caravaggio:BAAALgADCgUJBQAAAA==.Casterbation:BAAALgADCgYJBgAAAA==.Catiany:BAAALgADCgYJBgAAAA==.',
Ce='Celithil:BAAALgADCgcJCQAAAA==.Ceroll:BAABLgAECn8QAAMOAAgJzBoKFADJAQAOAAgJzBoKFADJAQAUAAEJORV/FgBBAAAAAA==.Cerolumas:BAAALgADCgUJBQABLgAECgEJAQAKAAAAAA==.',
Ch='Chadwik:BAAALgADCgYJBgAAAA==.Chainevoker:BAAALgAECgYJCgAAAA==.Changoqt:BAAALgAECggJDQAAAA==.Charbzenberg:BAAALgADCgIJAgAAAA==.Charisma:BAAALgADCgYJBgABLgAECggJHwAKAAAAAQ==.Cheeseburgrr:BAAALgAECgYJCQAAAA==.Chiang:BAAALgAECgUJBQAAAA==.Chikfila:BAAALgADCgUJBQAAAA==.Chilijayleen:BAAALgAECgYJEAAAAA==.Chinari:BAAALgADCgYJBgAAAA==.Chinkinarobe:BAAALgAECgMJAwAAAA==.Chonhunter:BAAALgAECgcJCgAAAA==.Chungae:BAAALgADCgMJAwAAAA==.Chunkychucky:BAAALgADCgIJAgAAAA==.Chångomike:BAAALgADCgkJCQAAAA==.',
Cj='Cjay:BAAALgADCgQJAwAAAA==.',
Cl='Clegen:BAAALgADCgUJBQAAAA==.Cloax:BAACLgAFFH8HAAIFAAMJNAMGEAC5AAAFAAMJNAMGEAC5AAAuAAQKfyYAAgUACAlGG4MSAGQCAAUACAlGG4MSAGQCAAAA.Clýde:BAAALgAECgUJCAAAAA==.',
Co='Cobask:BAAALgAECgMJAgAAAA==.Cobyashi:BAAALgADCgcJBwAAAA==.Colinar:BAAALgAECgYJCwAAAA==.Compassion:BAAALgADCgYJCgAAAA==.Conquer:BAAALgADCgYJBgAAAA==.Conquermonk:BAAALgADCgQJBAAAAA==.Coobin:BAAALgADCgIJAgAAAA==.Coors:BAAALgADCgQJBAAAAA==.Cotas:BAAALgAECgYJCwAAAA==.Couraegus:BAABLgAECn8XAAILAAgJQSJpEAAMAwALAAgJQSJpEAAMAwAAAA==.Covenants:BAAALgADCgQJBAAAAA==.',
Cr='Crabemoji:BAAALgAECgQJBQABLgAFFAUJDAAVAEMeAA==.Crapo:BAAALgAECgYJEAAAAA==.Crewbin:BAAALgAECgMJBAAAAA==.Croobin:BAAALgADCgcJBwAAAA==.Crud:BAAALgADCgMJAwAAAA==.Cryhavok:BAAALgAECgcJCQAAAA==.Crymzin:BAAALgADCgIJAgAAAA==.',
Cu='Cubefuonyou:BAAALgAFFAEJAQAAAA==.Cubesoaker:BAAALgAECgQJCQAAAA==.Cutesbrews:BAABLgAECn8dAAIWAAcJ6hTfFgBJAQAWAAcJ6hTfFgBJAQAAAA==.',
Cy='Cyther:BAAALgAECgEJAQAAAA==.',
['Cê']='Cêll:BAAALgADCgEJAgAAAA==.',
Da='Daghar:BAABLgAECn8aAAQNAAcJSxoVCACKAQANAAcJ9xIVCACKAQAXAAYJ9xtkDgA5AQAHAAMJGwbsiwCPAAAAAA==.Dalé:BAAALgAECgYJBgAAAA==.Damecias:BAAALgAECgcJEgAAAA==.Dana:BAAALgADCgIJAQAAAA==.Danielsonn:BAAALgAECgQJBAAAAA==.Danyphantom:BAAALgADCgMJBAAAAA==.Darbpal:BAABLgAECn8hAAILAAgJwRTyNABvAQALAAgJwRTyNABvAQAAAA==.Darealrambo:BAAALgADCgYJCwAAAA==.Darfk:BAAALgADCgUJCAAAAA==.Darkbender:BAAALgAECgYJCwAAAA==.Darkmanta:BAAALgAECgMJAwAAAA==.Darkzephyr:BAAALgAECgQJBAAAAA==.Darkÿ:BAAALgAECgUJDgAAAA==.Darnitt:BAAALgADCgQJBAABLgAFFAEJAQAKAAAAAA==.Darthvaliate:BAAALgAECgYJCwAAAA==.Datboyj:BAAALgAECgkJDAAAAA==.Davosi:BAABLgAECn8aAAIHAAkJgB2DAgC6AgAHAAkJgB2DAgC6AgAAAA==.Dayrb:BAAALgADCgIJAgAAAA==.',
De='Deadtalini:BAABLgAECn8zAAQYAAkJtBpjCwBdAgAYAAgJ/B1jCwBdAgAEAAkJKwyRRQAuAQAZAAEJdA5uEAA5AAAAAA==.Deah:BAABLgAECn8XAAIQAAcJoiGSFADtAQAQAAcJoiGSFADtAQAAAA==.Dearling:BAAALgADCgYJBwAAAA==.Deckerdramon:BAABLgAECn8kAAIXAAgJXhlGBgDsAQAXAAgJXhlGBgDsAQAAAA==.Deepeemcgee:BAAALgADCgcJEQAAAA==.Delanoris:BAAALgADCgYJBgAAAA==.Dellera:BAAALgADCgcJGAAAAA==.Delulú:BAAALgAECgEJAQAAAA==.Demonhizzy:BAAALgAECgkJDQAAAA==.Demontoid:BAAALgADCgcJDQAAAA==.Demonzo:BAAALgADCgUJBQAAAA==.Dennevien:BAAALgADCgcJBgAAAA==.Desaran:BAAALgAECgEJAgAAAA==.Destinda:BAAALgAECgYJCgAAAA==.Devoider:BAAALgAECgYJBgAAAA==.Devour:BAAALgADCgcJDAAAAA==.Devoured:BAAALgAECgMJAgAAAA==.Devours:BAACLgAFFH8UAAIVAAUJgRmwBACgAQAVAAUJgRmwBACgAQAuAAQKfyAAAhUACQk0I1MCAF8DABUACQk0I1MCAF8DAAAA.Devoury:BAACLgAFFH8JAAMaAAMJfRfPEAD9AAAaAAMJfRfPEAD9AAAbAAEJrgzgFQA+AAAuAAQKfxkAAxsABwmnI7wJALECABsABwmMI7wJALECABoABwkHGiMRADACAAEuAAUUBQkUABUAgRkA.',
Di='Dihfacer:BAAALgAECgIJAgAAAA==.Dippndots:BAAALgADCgEJAQAAAA==.Divinessa:BAAALgADCgcJBwAAAA==.Diâblö:BAACLgAFFH8RAAIIAAUJQSWdAQAlAgAIAAUJQSWdAQAlAgAuAAQKfzIAAggACAkyJtwBAHcDAAgACAkyJtwBAHcDAAAA.',
Do='Dobro:BAAALgAECgcJDgAAAA==.Doth:BAAALgADCgIJAgAAAA==.Downkid:BAAALgAECgMJAwAAAA==.',
Dr='Dractharion:BAAALgAECgQJBAAAAA==.Dragapult:BAACLgAFFH8IAAIDAAQJvBM+FgCwAAADAAQJvBM+FgCwAAAuAAQKfygAAwMACAm5HfcQAGoCAAMACAm5HfcQAGoCAA8AAwkJD/EwAI8AAAAA.Dragusysmash:BAAALgADCgYJBgAAAA==.Dralvira:BAABLgAECn8mAAIXAAgJuiWyAQBoAwAXAAgJuiWyAQBoAwAAAA==.Drath:BAAALgAECgMJBQAAAA==.Draxithar:BAAALgAECgYJDwAAAA==.Drazzin:BAAALgADCgIJAgABLgAECggJHwAcAP0aAA==.Drgragas:BAAALgADCgMJAwAAAA==.Dryduss:BAAALgADCgYJBgAAAA==.Drzj:BAAALgAECggJEwAAAA==.',
Ds='Dsappman:BAAALgAECgIJAgAAAA==.',
Du='Dualshock:BAAALgAECgEJAQAAAA==.Duggo:BAAALgAECgYJCwAAAA==.Durvier:BAAALgADCgcJDAAAAA==.Durzaq:BAAALgAECgQJBAAAAA==.',
Dy='Dyrteshadow:BAAALgADCgYJCAAAAA==.',
['Dà']='Dàth:BAAALgAECgUJCQAAAA==.',
Eb='Ebore:BAAALgADCgMJAwAAAA==.',
Ec='Ecoshock:BAAALgADCgMJAwABLgAECgMJCAAKAAAAAA==.',
Eh='Eh:BAAALgAECggJCAAAAA==.',
Ei='Eirrin:BAABLgAECn8gAAIbAAgJJyBnCADFAgAbAAgJJyBnCADFAgAAAA==.',
El='Elaineh:BAAALgAECgUJBgAAAA==.Elementalist:BAAALgAECgQJBAAAAA==.Elendira:BAAALgAECgcJDwAAAA==.Elkane:BAAALgAECgYJCwAAAA==.Elleredreaux:BAABLgAECn8XAAIGAAYJZQ55XQAiAQAGAAYJZQ55XQAiAQAAAA==.Elofin:BAAALgAECgMJAwAAAA==.',
En='Endomorphism:BAACLgAFFH8JAAIdAAMJ3BmqAwDqAAAdAAMJ3BmqAwDqAAAuAAQKfx4AAh0ACAl1IxsBAJ0CAB0ACAl1IxsBAJ0CAAEuAAUUBgkYAB0AjRkA.',
Eq='Equidus:BAAALgADCgEJAQAAAA==.',
Er='Eranthis:BAAALgAECgcJDQAAAA==.Errour:BAAALgADCgYJCwAAAA==.',
Et='Etherhand:BAAALgAECgEJAQAAAA==.',
Ev='Eveldumboone:BAACLgAFFH8SAAIYAAUJNh6DBABdAQAYAAUJNh6DBABdAQAuAAQKfyUAAxgACAlxJGIDACUDABgACAlxJGIDACUDABkAAQmOGb0UAEgAAAAA.',
Ez='Ezmelora:BAABLgAECn8dAAISAAgJwxRgQQAJAgASAAgJwxRgQQAJAgAAAA==.',
Fa='Faelight:BAAALgAECgEJAQAAAA==.Faenixandria:BAAALgAECgMJBwAAAA==.Fairykiller:BAAALgADCgEJAQAAAA==.Falkrus:BAAALgADCgEJAQAAAA==.Fallenresto:BAAALgADCgcJBwAAAA==.Fancydemon:BAAALgADCgIJAgAAAA==.Fancypets:BAAALgADCgUJBQAAAA==.Fantasie:BAAALgAECgYJBwABLgAECggJIwAbALgVAA==.Fartz:BAAALgADCgYJBgAAAA==.Fauxpawz:BAAALgAECgYJEAAAAA==.Fayia:BAACLgAFFH8FAAIQAAIJ9gXXGwCHAAAQAAIJ9gXXGwCHAAAuAAQKfxoAAxAABwkUFnNBAKoBABAABwkUFnNBAKoBABEABAkdBIFsAIwAAAAA.',
Fe='Fearshaman:BAABLgAECn8oAAIVAAgJbQhZQwB0AQAVAAgJbQhZQwB0AQAAAA==.Felbrew:BAAALgAFFAEJAQAAAA==.Felhoof:BAABLgAECn8VAAIeAAcJGhxpHQATAgAeAAcJGhxpHQATAgAAAA==.Fellrend:BAAALgAECgIJAgAAAA==.Felrogue:BAAALgADCgQJBAAAAA==.',
Fi='Fibbs:BAAALgAECggJEQAAAA==.Firaman:BAAALgAECgYJCQAAAA==.Firewraith:BAAALgAECgQJBQAAAA==.Fistmachin:BAABLgAECn8eAAIWAAgJVxC4EACLAQAWAAgJVxC4EACLAQAAAA==.Fizzibix:BAAALgADCgIJAwABLgAECgcJFQAEAKYRAA==.',
Fl='Flexxed:BAACLgAFFH8KAAIZAAQJWBYvAQBVAQAZAAQJWBYvAQBVAQAuAAQKfxcAAxkABwmNIg8DAGwCABkABwmNIg8DAGwCAAQAAQmqDKksASkAAAAA.Flibble:BAAALgADCgEJAQAAAA==.Flip:BAAALgADCgUJBwAAAA==.Florelai:BAAALgAECgQJBAAAAA==.Florin:BAAALgADCgEJAQAAAA==.Flyinmachin:BAAALgAECgEJAQAAAA==.',
Fo='Foreheadkiss:BAAALgAECgcJBwAAAA==.',
Fr='Frakkinfrik:BAAALgADCgIJAgAAAA==.Franciss:BAAALgAECgQJBQAAAA==.Freezie:BAAALgAECgcJDgAAAA==.Freyae:BAAALgADCggJEgAAAA==.Frikkinfrak:BAAALgADCgIJAgAAAA==.Friskie:BAAALgAECgcJCwABLgAECggJIwAbALgVAA==.Frona:BAAALgADCgYJEgAAAA==.',
Ft='Ftknox:BAAALgAECgMJAwAAAA==.',
Fu='Fufubabe:BAAALgADCgUJBQAAAA==.Fuhq:BAAALgAECgEJAQAAAA==.Fuqin:BAAALgADCgcJBwAAAA==.Furrever:BAAALgAECgYJEQAAAA==.Fuzada:BAABLgAECn8XAAIGAAcJ5CEAOQCRAgAGAAcJ5CEAOQCRAgAAAA==.',
Fw='Fwuppy:BAAALgAECgEJAQAAAA==.',
Ga='Gament:BAAALgAECgIJAgAAAA==.Ganangus:BAAALgADCgEJAQAAAA==.Gandamar:BAAALgAECgYJDgAAAA==.Gankzz:BAABLgAECn8WAAISAAgJNQsNOgBFAQASAAgJNQsNOgBFAQAAAA==.Ganondork:BAAALgADCgMJAwAAAA==.Ganondrow:BAAALgAECggJEQAAAA==.Gantar:BAAALgADCgcJBwAAAA==.',
Gb='Gboyzz:BAAALgADCgkJCQAAAA==.',
Ge='Gemelo:BAAALgAECgMJBgAAAA==.Gettuff:BAAALgAECgQJBAAAAA==.',
Gg='Ggivverr:BAAALgAECgQJBwAAAA==.',
Gh='Ghstsplntr:BAABLgAECn8mAAILAAcJSxvRJACxAQALAAcJSxvRJACxAQAAAA==.',
Gi='Gibayy:BAAALgAFFAIJAgAAAA==.Gibsonex:BAAALgAECgYJEwAAAA==.Gilliamm:BAABLgAECn8UAAIeAAgJgxOiIAD0AQAeAAgJgxOiIAD0AQAAAA==.Giselda:BAABLgAECn8VAAIEAAcJphG3NABmAQAEAAcJphG3NABmAQAAAA==.Gizzmah:BAAALgADCgUJBQAAAA==.',
Gl='Gloomstick:BAAALgAECgYJCgAAAA==.Glowza:BAAALgAFFAIJAgAAAA==.',
Go='Gobbs:BAABLgAECn8eAAMQAAgJiBtHKwBmAQAQAAgJiBtHKwBmAQARAAMJqA+aEQC2AAAAAA==.Goblocker:BAAALgADCgYJBgAAAA==.Golath:BAAALgAECgYJEAAAAA==.Goldoraq:BAAALgAECgEJAQAAAA==.Goldscales:BAAALgADCgMJAwAAAA==.Gonjoodman:BAAALgADCgcJBwAAAA==.Gonthielhunt:BAAALgAECgIJAgAAAA==.Gonzobeanz:BAAALgADCgYJCwAAAA==.Gonzolo:BAAALgADCgUJBgAAAA==.Goocheater:BAAALgADCgYJCQAAAA==.Gorcazzo:BAAALgAECgYJDwAAAA==.Gorekroxx:BAAALgADCgQJAwAAAA==.Gorgonzormu:BAABLgAECn8eAAMPAAgJayEnBADNAgAPAAcJlSEnBADNAgADAAYJFCNiDgCmAQAAAA==.Gothbutta:BAAALgAECgQJBwAAAA==.',
Gr='Grandpoobah:BAAALgADCggJCAABLgAFFAMJBgAfAFoZAA==.Greela:BAAALgAECgEJAQAAAA==.Gregorian:BAAALgAECgYJDgAAAA==.Gremliin:BAAALgAECgYJDAAAAA==.Gremlinstorm:BAAALgADCgYJCQABLgAECgYJDAAKAAAAAA==.Grendalu:BAAALgADCgEJAgAAAA==.Griffy:BAAALgADCgMJBQAAAA==.',
Gu='Gumpiz:BAAALgAECgQJBAAAAA==.',
Ha='Haardslinger:BAAALgADCgcJBwABLgAECgMJAwAKAAAAAA==.Hamdon:BAAALgADCgQJBAAAAA==.Hanabi:BAAALgAECgEJAQAAAA==.Haniesh:BAABLgAECn8kAAILAAgJLBXiIQDAAQALAAgJLBXiIQDAAQAAAA==.Harlin:BAAALgADCgQJBAABLgAECgQJBQAKAAAAAA==.Hatengar:BAABLgAECn8UAAIgAAcJCAdiDQD/AAAgAAcJCAdiDQD/AAAAAA==.Hazben:BAAALgADCgQJBAAAAA==.',
He='Healingeyes:BAAALgADCgYJBgAAAA==.Healmeharder:BAAALgAECgEJAQAAAA==.Helburk:BAAALgADCgYJCQAAAA==.Hellagood:BAAALgAECgQJCwAAAA==.Hethar:BAAALgADCgQJBAABLgAECgUJBwAKAAAAAA==.',
Hi='Hightide:BAAALgAECgYJEQAAAA==.Hipocratic:BAAALgAECgYJDgAAAA==.Hippodot:BAABLgAECn8VAAISAAgJyBGYHgC9AQASAAgJyBGYHgC9AQAAAA==.',
Ho='Hodorr:BAABLgAECn8YAAMWAAgJZBKuEQCAAQAWAAgJZBKuEQCAAQAhAAIJ/gbTdABCAAAAAA==.Hodr:BAAALgAECgYJCwABLgAECggJGAAWAGQSAA==.Hoghoof:BAAALgADCggJEwAAAA==.Hoja:BAAALgAFFAEJAQAAAA==.Holdor:BAAALgAECgEJAQAAAA==.Holrhyn:BAABLgAECn8XAAIbAAgJchcgJgC6AQAbAAgJchcgJgC6AQAAAA==.Holybloodboi:BAAALgAECgcJCAABLgAECggJKAAVAAUlAA==.Holylife:BAAALgADCgMJAwAAAA==.Hozencolo:BAAALgADCgMJBAAAAA==.',
Hu='Huckleberry:BAABLgAECn8XAAIhAAgJkAp2PAAqAQAhAAgJkAp2PAAqAQAAAA==.Hugegigachad:BAAALgADCgQJBAAAAA==.Hugsnkisses:BAAALgAECgEJAgAAAA==.Hukjek:BAAALgAECgQJBwAAAA==.Hungcowboy:BAAALgADCgIJAgAAAA==.',
Hy='Hydrogenbomb:BAABLgAECn8hAAMBAAgJJhvqCQDDAQABAAgJzxrqCQDDAQARAAQJVBZQUQAHAQAAAA==.Hymnbral:BAAALgADCgMJBQABLgAFFAIJAgAKAAAAAA==.',
Ic='Icebergx:BAAALgAECgQJBgAAAA==.',
Ig='Igriis:BAAALgADCgYJBgAAAA==.',
Im='Imcooleddown:BAABLgAECn8aAAIGAAgJ3BvOFgAmAgAGAAgJ3BvOFgAmAgAAAA==.Imfkinold:BAAALgAECgMJBAAAAA==.Imptricity:BAAALgADCgMJAwAAAA==.Imrickjamesb:BAAALgADCgIJAgAAAA==.',
In='Indee:BAAALgADCgYJBQABLgAECgYJBgAKAAAAAA==.Indi:BAAALgADCgQJBAAAAA==.Indyd:BAAALgAECgEJAQAAAA==.Indyy:BAAALgADCgMJAwABLgAECgYJBgAKAAAAAA==.',
Iz='Izunna:BAAALgAECgQJBAABLgAECgkJJAAUAG0hAA==.',
Ja='Jackbeef:BAABLgAECn8ZAAIHAAgJkxsYDQDfAQAHAAgJkxsYDQDfAQAAAA==.Jadedhooves:BAABLgAECn8UAAILAAcJ5A7UVgALAQALAAcJ5A7UVgALAQAAAA==.Japorms:BAAALgADCgEJAgAAAA==.Jarryoak:BAAALgAECgEJAQAAAA==.',
Je='Jedai:BAABLgAECn8uAAIiAAgJTyaMAQBsAwAiAAgJTyaMAQBsAwAAAA==.Jerrund:BAAALgAECgIJAgAAAA==.Jerryfour:BAAALgADCgEJAQAAAA==.Jerrythree:BAAALgADCgMJAgAAAA==.Jerrytwo:BAAALgAECgYJEAAAAA==.',
Ji='Jimjones:BAAALgAECgQJBQAAAA==.',
Jm='Jman:BAAALgAECgYJDAAAAA==.',
Jo='Johnboy:BAAALgADCgYJAQAAAA==.Jorgancrath:BAAALgAECgMJAwAAAA==.Jovallius:BAAALgADCgkJCQAAAA==.',
Ju='Judadiah:BAAALgAECgMJBQAAAA==.Juggernutz:BAAALgAECgEJAgABLgAECggJGgAHAHkWAA==.Juggernutzy:BAAALgADCgcJBwABLgAECggJGgAHAHkWAA==.Jujujalal:BAAALgAECgMJBgAAAA==.Justbeginner:BAAALgADCgcJCwAAAA==.Justlycolda:BAAALgAECgUJBQAAAA==.',
['Jà']='Jàde:BAAALgADCgkJJQAAAA==.',
['Jù']='Jùgger:BAAALgADCgIJAgAAAA==.',
Ka='Kagalith:BAAALgADCgIJAgAAAA==.Kagorin:BAABLgAECn8fAAIPAAgJvBAtAwC/AQAPAAgJvBAtAwC/AQAAAA==.Kaidios:BAABLgAECn8iAAQZAAgJsBxtBABmAQAEAAgJ5he5WgDiAQAZAAgJXRptBABmAQAYAAEJOQZ0RwAqAAAAAA==.Kalano:BAABLgAECn8fAAMGAAgJGRA/KwC3AQAGAAgJGRA/KwC3AQAMAAMJEgueEwCLAAAAAA==.Kalona:BAAALgADCgYJCAAAAA==.Kalrock:BAABLgAECn8aAAMSAAgJTRzUFQD2AQASAAcJTRzUFQD2AQATAAEJAAC2XQBVAAAAAA==.Kalulu:BAAALgADCgEJAQAAAA==.Karkit:BAAALgAECgEJAQAAAA==.Katchow:BAAALgAECgcJEwAAAA==.Katkot:BAABLgAECn8VAAILAAYJ8RGtmgBJAQALAAYJ8RGtmgBJAQAAAA==.Kayro:BAAALgADCgcJEgAAAA==.Kayyggoo:BAAALgAECgkJEQAAAA==.Kazlan:BAAALgADCgYJCwAAAA==.',
Ke='Kercimage:BAAALgADCgIJAgAAAA==.Kevinn:BAAALgADCgUJBAAAAA==.',
Kh='Khalana:BAAALgADCgUJCAAAAA==.Khalio:BAAALgADCgYJCwAAAA==.Khamul:BAABLgAECn8UAAIVAAYJQA98LAATAQAVAAYJQA98LAATAQAAAA==.',
Ki='Kielovar:BAAALgADCgYJBgAAAA==.Kimchilada:BAAALgAECgQJBwAAAA==.Kithkanan:BAAALgADCgUJBQAAAA==.',
Kk='Kkodabear:BAAALgAECgUJCQAAAA==.',
Kn='Kneeonater:BAAALgADCggJEwAAAA==.',
Ko='Kobiter:BAAALgAECgUJCgABLgAFFAIJBQAXAC4TAA==.Kobito:BAACLgAFFH8FAAIXAAIJLhPzDQCTAAAXAAIJLhPzDQCTAAAuAAQKfygAAxcACAmOHbMJAH0CABcACAmOHbMJAH0CAAcABgnIGZ87ALcBAAAA.Kointahti:BAAALgAECgYJCgABLgAECgEJCgAKAAAAAA==.Konara:BAAALgADCgcJBgAAAA==.Koopatroopa:BAABLgAECn8WAAMhAAYJaxGtGwAIAQAhAAYJ3xCtGwAIAQAWAAYJ1wgKWgDcAAAAAA==.Koup:BAABLgAECn8mAAMQAAgJdybuAQADAwAQAAgJdybuAQADAwARAAEJAAAljgAtAAAAAA==.Koupe:BAAALgAECgcJEgABLgAECggJJgAQAHcmAA==.Koups:BAAALgADCgQJBAABLgAECggJJgAQAHcmAA==.',
Kr='Krayzebeef:BAAALgAECgIJAgAAAA==.Krazyemist:BAAALgADCgQJBAAAAA==.Kreyash:BAAALgAECgIJBQAAAA==.Kriss:BAAALgAECgQJDQAAAA==.Kruncha:BAAALgAECgIJAgAAAA==.Krungus:BAAALgAECgIJAgAAAA==.Kryxis:BAABLgAECn8eAAIOAAcJuhtkHgB8AQAOAAcJuhtkHgB8AQAAAA==.',
Ku='Kupe:BAAALgAECgYJDQABLgAECggJJgAQAHcmAA==.Kuroguro:BAAALgAECgYJEAAAAA==.Kuruption:BAAALgAECgIJAgAAAA==.',
Kw='Kwikkx:BAAALgADCgcJDQAAAA==.',
Ky='Kyewanda:BAABLgAECn8gAAIjAAcJCx+XDwAYAgAjAAcJCx+XDwAYAgAAAA==.Kyewson:BAAALgADCgMJAwABLgAECgcJIAAjAAsfAA==.Kyrobytez:BAAALgAECgUJCwAAAA==.Kythyra:BAAALgADCgUJCgAAAA==.',
La='Laanu:BAAALgAECgYJCwAAAA==.Lagginwaggin:BAAALgAECgUJBwAAAA==.Lakes:BAAALgADCgQJBAAAAA==.Lanuna:BAAALgAECgcJAwAAAA==.Laowan:BAAALgAECgMJAwAAAA==.Lasagnatoo:BAAALgAECgMJBQABLgAECgkJMwAYALQaAA==.Lastlight:BAAALgAECgIJAgAAAA==.Lathara:BAAALgAECgIJAgAAAA==.Lavs:BAABLgAECn8jAAIkAAgJXh+IAQCHAgAkAAgJXh+IAQCHAgAAAA==.',
Le='Leahabah:BAAALgAECgEJAQAAAA==.Legendweaver:BAAALgAECgEJAQABLgAECgYJGAAGAHUNAA==.Lein:BAAALgAECgUJDwAAAA==.Lenix:BAAALgADCgYJDgAAAA==.',
Li='Limper:BAAALgAECgkJBgAAAA==.Lineman:BAAALgADCgUJBQAAAA==.Lionalone:BAAALgAECgEJAgAAAA==.Livallan:BAABLgAECn8WAAMlAAgJSgeKEAD4AAAlAAgJ4QaKEAD4AAALAAEJ5Qf2TAEuAAAAAA==.',
Lm='Lman:BAAALgAECgMJBQAAAA==.',
Lo='Loamathor:BAAALgADCgkJJAAAAA==.Lobaxv:BAABLgAECn8UAAIiAAUJZxg/IQA9AQAiAAUJZxg/IQA9AQAAAA==.Lolenter:BAAALgADCgcJBwAAAA==.Loli:BAAALgADCgQJAgAAAA==.Lonealpha:BAAALgAECgMJAwAAAA==.Lonesource:BAAALgAECgUJCwAAAA==.Lorilyn:BAABLgAECn8jAAIbAAgJHhlwCAAjAgAbAAgJHhlwCAAjAgAAAA==.Lorthag:BAAALgAECgQJDgAAAA==.Lovebuz:BAAALgAECgQJBAAAAA==.Loveles:BAAALgADCgIJAgAAAA==.Loverone:BAAALgADCgEJAQAAAA==.',
Lr='Lringecord:BAAALgAECgcJCgAAAA==.',
Lu='Lu:BAAALgADCgEJAQAAAA==.Luckless:BAAALgAECgcJEAAAAA==.Luckyroux:BAAALgADCgYJCQAAAA==.Lumiboba:BAAALgAFFAEJAQAAAA==.Lumilychee:BAABLgAECn8aAAIIAAkJexqPDQB7AgAIAAkJexqPDQB7AgAAAA==.Lumylock:BAAALgAECgUJCgAAAA==.Lunachick:BAAALgAECgUJCQAAAA==.Lunarus:BAABLgAECn8bAAIcAAYJJxAPDQBkAQAcAAYJJxAPDQBkAQAAAA==.Lurline:BAABLgAECn8aAAIGAAgJMCBJCwCNAgAGAAgJMCBJCwCNAgAAAA==.Lurrus:BAAALgADCgcJBwAAAA==.Luvergirl:BAAALgADCgMJAgAAAA==.Luvsmage:BAAALgAECgEJAQAAAA==.Luxiu:BAAALgADCgIJAgAAAA==.',
Lv='Lvladin:BAAALgAECgYJBwAAAA==.',
Ly='Lyllies:BAAALgAECgEJAQAAAA==.Lythriaa:BAAALgADCgYJBgAAAA==.',
['Lì']='Lìfe:BAABLgAECn8oAAIHAAkJMBjFBQBbAgAHAAkJMBjFBQBbAgAAAA==.',
Ma='Macloving:BAABLgAECn8WAAIJAAkJowp+MwCLAQAJAAkJowp+MwCLAQAAAA==.Madapipa:BAAALgADCgUJBQAAAA==.Maddiablo:BAAALgADCgUJCAAAAA==.Magicpipe:BAAALgAECgUJCQAAAA==.Magrumok:BAAALgAECgYJBwAAAA==.Magthars:BAAALgAECgMJAwAAAA==.Mahnàmahnà:BAAALgADCgYJCQAAAA==.Maká:BAAALgAECgYJDwAAAA==.Malorian:BAAALgAECgkJBgAAAA==.Malígn:BAAALgAECgcJEAAAAA==.Manbearpig:BAAALgAECgcJBwAAAA==.Mandysmores:BAAALgAECgUJCwABLgAFFAUJEgAGAN4QAA==.Marduchava:BAAALgAECgEJAQAAAA==.Marshmalow:BAAALgAECgUJCAAAAA==.',
Mc='Mclovhin:BAAALgAECgMJAwAAAA==.Mcpal:BAAALgAECgMJAwABLgAECgMJCAAKAAAAAA==.Mcquade:BAAALgADCgcJBwABLgADCgkJEQAKAAAAAA==.Mctigly:BAAALgAECgcJBwAAAA==.',
Me='Meals:BAAALgAECgcJEQAAAA==.Meatchunks:BAAALgAECgYJCgAAAA==.Meetras:BAACLgAFFH8HAAIeAAIJqiEEEADWAAAeAAIJqiEEEADWAAAuAAQKfyMAAh4ACQmFIFQCAKACAB4ACQmFIFQCAKACAAAA.Megadefi:BAAALgAECgUJBgAAAA==.Megagosa:BAAALgAECgUJCgAAAA==.Meganob:BAAALgADCgYJBgAAAA==.Melkiel:BAAALgADCggJCAABLgAECggJJgAXALolAA==.Mementomorie:BAAALgAECgMJAwAAAA==.Mennopaws:BAAALgADCgcJAQAAAA==.Mesa:BAABLgAECn+nAAIfAAkJ9yYDAAAZBAAfAAkJ9yYDAAAZBAAAAA==.',
Mi='Miclovin:BAAALgAECggJDgAAAA==.Microplastic:BAABLgAECn8lAAMHAAgJcx61BAB1AgAHAAgJcx61BAB1AgANAAIJ4w/XOQBIAAAAAA==.Millerltez:BAAALgAECggJAgAAAA==.Miniblué:BAAALgAECgMJBgAAAA==.Minimalskill:BAAALgAECgEJAgAAAA==.Minthammer:BAAALgAECgEJAgAAAA==.Mirrin:BAAALgAECgEJAQABLgAECgEJAgAKAAAAAA==.Mirumahn:BAAALgADCgkJIAAAAA==.Misocursed:BAAALgADCgMJAwAAAA==.Mistie:BAAALgADCgMJAwAAAA==.',
Mk='Mkultravictm:BAAALgAECgYJDAAAAA==.',
Mo='Moadeab:BAAALgADCggJDwAAAA==.Mogando:BAAALgADCgUJCQABLgAECggJHwAcAP0aAA==.Mogrodeath:BAAALgAECgEJAgAAAA==.Mogrodem:BAAALgAECgEJAgAAAA==.Mogrodruid:BAAALgAECgEJAgABLgAECgcJEgAKAAAAAA==.Mogrogarg:BAAALgAECgcJEgAAAA==.Mogrohunt:BAAALgAECgEJAgAAAA==.Mogromage:BAAALgAECgEJAgAAAA==.Mogropal:BAAALgAECgEJAgAAAA==.Mojojojò:BAAALgAECgIJAwAAAA==.Monica:BAAALgAECgMJAwAAAA==.Monkydpuzzle:BAAALgAECgQJBAAAAA==.Moogicmike:BAAALgADCgUJBQAAAA==.Moonflower:BAAALgADCggJDgAAAA==.Moonwulf:BAAALgADCggJEgAAAA==.Moonyin:BAAALgAECgUJCQAAAA==.Moosedrool:BAAALgADCgYJBgABLgADCgcJDAAKAAAAAA==.Mooster:BAAALgADCgcJBwAAAA==.Moralefist:BAAALgAECgYJBgAAAA==.Mordin:BAAALgAECgEJAQAAAA==.Morenthia:BAAALgAECgYJEAAAAA==.Morgaliice:BAABLgAECn8VAAImAAgJng55DwBEAQAmAAgJng55DwBEAQAAAA==.Morganasz:BAAALgADCgUJBQABLgAECgkJJgAOAGQZAA==.Mornafah:BAABLgAECn8kAAIUAAkJbSHRAACxAgAUAAkJbSHRAACxAgAAAA==.Mornna:BAAALgAECgMJAwABLgAECgkJJAAUAG0hAA==.Morrickk:BAAALgADCgUJBQAAAA==.Morriffic:BAAALgADCgYJDgAAAA==.Mortarion:BAAALgADCgEJAQAAAA==.Mortigen:BAAALgAECgMJAwAAAA==.Mousethyr:BAAALgAECggJEgAAAA==.',
Mu='Munric:BAABLgAECn8iAAILAAgJZxmeOQA9AgALAAgJZxmeOQA9AgAAAA==.Murlow:BAAALgADCgQJBQAAAA==.Muteddruid:BAAALgAECgMJAwAAAA==.Mutedfury:BAAALgADCgcJBwAAAA==.Mutelock:BAAALgAECgEJAQAAAA==.',
My='Myboycleetus:BAAALgAECgUJCwABLgADCgYJCQAKAAAAAA==.Mykerz:BAABLgAECn8UAAIVAAgJSxYzDgAMAgAVAAgJSxYzDgAMAgAAAA==.Mynon:BAAALgADCgMJAwAAAA==.Mysaeris:BAAALgADCgcJBwAAAA==.Mystie:BAAALgADCgcJCAAAAA==.Myw:BAACLgAFFH8VAAIVAAUJPBdcBwBxAQAVAAUJPBdcBwBxAQAuAAQKfyoAAhUACAkXJUQDAEYDABUACAkXJUQDAEYDAAAA.',
['Mí']='Míles:BAAALgAECgYJDgAAAA==.',
['Mó']='Mórningstar:BAAALgAECgYJBgAAAA==.',
Na='Nachomama:BAAALgAECgQJBgAAAA==.Nachothings:BAACLgAFFH8OAAIOAAUJ9hXdEgAtAQAOAAUJ9hXdEgAtAQAuAAQKfx0AAw4ACAk/H2UbAK4CAA4ACAk/H2UbAK4CACYAAgmBFg5bAHUAAAAA.Nakedindee:BAAALgAECgYJBgAAAA==.Nakedindy:BAAALgADCgcJAwABLgAECgYJBgAKAAAAAA==.Nakedlizard:BAAALgAECgQJBAAAAA==.Nashonkle:BAAALgADCgEJAQAAAA==.Navarth:BAAALgADCgYJCwAAAA==.',
Nb='Nbayoungboy:BAAALgADCgUJBQAAAA==.',
Ne='Nearlydeath:BAAALgAFFAEJAQAAAA==.Nedria:BAAALgADCgcJDAAAAA==.Nedwar:BAAALgAECgYJDgAAAA==.Nenghis:BAAALgAECgYJDwAAAA==.Neur:BAAALgADCgMJAwABLgAECgYJEAAKAAAAAA==.Nevän:BAAALgADCgcJBwAAAA==.Nezha:BAAALgAFFAIJAgAAAA==.',
Ni='Nickelos:BAAALgADCgcJCQAAAA==.Nicksmonk:BAAALgADCgMJAwAAAA==.Nightmist:BAAALgADCggJEAAAAA==.Nihility:BAABLgAECn8fAAISAAcJpSRZEQDwAgASAAcJpSRZEQDwAgABLgAFFAIJAgAKAAAAAA==.Nirgand:BAAALgAECgQJBQABLgAECggJHwAcAP0aAA==.Nixxie:BAAALgAECgIJAgAAAA==.',
No='Nochoice:BAAALgADCgEJAQAAAA==.Noodlebark:BAAALgAECgEJAQAAAA==.Noodlestang:BAAALgAECgYJDQAAAA==.Nool:BAAALgAECgUJCwAAAA==.Nophel:BAAALgADCggJGQAAAA==.Noraelin:BAAALgADCgYJBwAAAA==.Norgand:BAABLgAECn8fAAMcAAgJ/RpQAwBqAgAcAAgJ/RpQAwBqAgATAAEJAAC4awA8AAAAAA==.Nornar:BAABLgAECn8VAAIBAAYJiRfAFwBPAQABAAYJiRfAFwBPAQAAAA==.Norsehammer:BAAALgADCgcJBwAAAA==.Nosleep:BAACLgAFFH8JAAIXAAMJLAcxDwCAAAAXAAMJLAcxDwCAAAAuAAQKfxoAAhcABwkHDXYgAD0BABcABwkHDXYgAD0BAAAA.Nosleepe:BAAALgADCgEJAQAAAA==.Nosleepo:BAAALgAECgcJBwAAAA==.',
Nu='Nubetoob:BAAALgADCgQJBAAAAA==.',
Ny='Nydeath:BAAALgAECgIJBAAAAA==.Nyduss:BAAALgAECgcJCgAAAA==.Nyxpal:BAAALgADCgEJAQAAAA==.',
['Nù']='Nùtter:BAABLgAECn8aAAIHAAgJeRYUMwDfAQAHAAgJeRYUMwDfAQAAAA==.',
Oa='Oath:BAAALgADCggJCAAAAA==.',
Ob='Obrlord:BAAALgAECgYJDgAAAA==.Obvy:BAABLgAECn8WAAIeAAgJnBnzDACaAQAeAAgJnBnzDACaAQAAAA==.',
Of='Offeiriad:BAAALgAECgIJAgAAAA==.',
Om='Omaboa:BAABLgAECn8aAAIJAAgJpCFQAwCgAgAJAAgJpCFQAwCgAgAAAA==.',
On='Onrai:BAAALgADCgEJAQAAAA==.Onî:BAAALgADCgEJAQAAAA==.',
Oo='Oof:BAABLgAECn8YAAMFAAkJghBlDQCuAQAFAAgJJxJlDQCuAQAbAAIJ6gauPwAwAAAAAA==.',
Op='Ophinal:BAAALgADCgcJDAAAAA==.Optimize:BAABLgAECn8ZAAIGAAcJsx2IPwBvAQAGAAcJsx2IPwBvAQAAAA==.',
Or='Orastal:BAAALgAECgQJBwABLgAECgcJDgAKAAAAAA==.Ordinia:BAAALgAECgYJCwAAAA==.Oroki:BAAALgAECgcJBgAAAA==.',
Os='Ossian:BAAALgADCgUJBwAAAA==.',
Pa='Pandadander:BAAALgADCgYJCQAAAA==.Pandalo:BAAALgADCgYJCgAAAA==.Papipa:BAABLgAECn8lAAQaAAcJCifkAwAmAwAaAAcJCifkAwAmAwAbAAYJfCQKEQBbAgAFAAEJPiYyWABcAAAAAA==.',
Pe='Pebbles:BAAALgAECgMJAwAAAA==.Pelarn:BAAALgADCgYJCwAAAA==.Pengwei:BAEBLgAECn8ZAAIhAAkJth6iBQApAwAhAAkJth6iBQApAwAAAA==.Penumbrix:BAAALgAECgEJAQAAAA==.Pepperbreath:BAABLgAECn8bAAIfAAgJeQ1/GgC3AQAfAAgJeQ1/GgC3AQAAAA==.Perfectstorm:BAAALgAECgYJCgAAAA==.Persefo:BAAALgAECgMJAwAAAA==.Petmeimtame:BAAALgAECgQJAwAAAA==.',
Ph='Phadenstar:BAAALgAECgQJBwAAAA==.',
Pi='Pickleburnz:BAAALgADCgQJBAAAAA==.Pinefresh:BAAALgAECgQJBQAAAA==.Pinkpwnage:BAAALgAECgQJBQAAAA==.Pinpoint:BAAALgADCgEJAQABLgAECggJGgAHAHkWAA==.Pivosos:BAAALgAECggJBwAAAA==.',
Pm='Pmmeurdog:BAAALgADCgYJBgAAAA==.',
Po='Pocketsmonk:BAAALgAECgUJEQAAAA==.Podnuh:BAAALgAECgEJAQAAAA==.Pokemcjoke:BAAALgAECgIJAgAAAA==.Ponchoe:BAAALgADCgcJDgAAAA==.Poobahdrag:BAACLgAFFH8GAAIfAAMJWhlODQD2AAAfAAMJWhlODQD2AAAuAAQKfyIAAx8ACQkAHFQKAJECAB8ACQkAHFQKAJECAA8ABAn2Eu0qAMYAAAAA.Pools:BAAALgAECgIJAgAAAA==.Popnosmoke:BAABLgAECn8VAAIHAAYJvg4aIwAgAQAHAAYJvg4aIwAgAQAAAA==.Popster:BAAALgADCgMJAwAAAA==.Porzok:BAABLgAECn8kAAIBAAgJfx/WAgB3AgABAAgJfx/WAgB3AgAAAA==.Poxxel:BAAALgADCgMJAwABLgAECggJLAALAOsiAA==.',
Pr='Prosperine:BAAALgADCgYJBgAAAA==.',
Pu='Puhd:BAAALgAECgEJAQAAAA==.Punchimon:BAAALgADCgYJBgAAAA==.Putraa:BAAALgADCgYJBgAAAA==.Putridstrike:BAAALgAECgcJCgAAAA==.',
Py='Pyrra:BAAALgADCgcJCQAAAA==.',
['Pü']='Pürple:BAAALgAECgYJDQAAAA==.',
Qt='Qtiy:BAABLgAECn8kAAISAAgJwCOGBQC7AgASAAgJwCOGBQC7AgAAAA==.Qty:BAAALgADCgIJAQABLgAECggJJAASAMAjAA==.',
Qu='Queeg:BAAALgADCgEJAgAAAA==.Quickben:BAAALgAECgQJBAAAAA==.Quintalen:BAAALgAECgQJCAAAAA==.',
Ra='Raawwrr:BAAALgADCgcJBwAAAA==.Racken:BAABLgAECn8YAAQYAAgJ7h1WBgDFAQAYAAgJ7h1WBgDFAQAZAAQJGgpxDQDWAAAEAAIJBwKLFQFKAAAAAA==.Raedona:BAAALgADCgQJBAAAAA==.Ragon:BAAALgADCgEJAQAAAA==.Raharn:BAAALgAECgUJCQAAAA==.Raincheckplz:BAAALgADCgIJAgAAAA==.Ranzor:BAABLgAECn8XAAIXAAgJYBV3EAABAgAXAAgJYBV3EAABAgAAAA==.Rauden:BAAALgADCgMJBAAAAA==.Raveyn:BAABLgAECn8ZAAMFAAcJcB1KEgBzAQAFAAYJjBtKEgBzAQAbAAUJvRe6JADYAAAAAA==.',
Re='Reacted:BAAALgADCgQJBAABLgAECggJHwAKAAAAAQ==.Rebecca:BAABLgAECn8ZAAIeAAgJYCIBAgCxAgAeAAgJYCIBAgCxAgAAAA==.Redmaine:BAAALgADCgEJAQAAAA==.Reef:BAABLgAECn8aAAIOAAgJ3CMREAD+AgAOAAgJ3CMREAD+AgAAAA==.Rekieuwu:BAAALgAECgcJEQAAAA==.Releaf:BAAALgAECgIJAgAAAA==.Remarista:BAAALgADCgYJCAAAAA==.Remixed:BAAALgADCgMJAwABLgAECgYJDQAKAAAAAA==.Repentance:BAAALgAECgQJAwAAAA==.Retnuh:BAABLgAECn8eAAMQAAgJHhtcDgAoAgAQAAgJHhtcDgAoAgABAAIJYxHmIgCFAAAAAA==.',
Rh='Rheiner:BAAALgAECgEJAQAAAA==.Rhynpi:BAAALgADCgIJAgAAAA==.Rhynsen:BAAALgADCgYJBgAAAA==.',
Ri='Ribez:BAAALgAFFAEJAQAAAA==.Ricoxx:BAAALgAECgEJBQAAAA==.Riftseeker:BAAALgAECgYJEQAAAA==.Rikori:BAAALgAECgUJCgAAAA==.Rimmjab:BAAALgAECgEJAQAAAA==.Rinzz:BAAALgADCgcJDQABLgAECgMJCAAKAAAAAA==.Rinzzler:BAAALgADCgEJAQAAAA==.Ristin:BAAALgADCgEJAQAAAA==.',
Ro='Roderika:BAAALgADCgUJBQABLgAFFAQJCAADALwTAA==.Rogald:BAAALgAECgMJBQAAAA==.Roids:BAAALgADCgYJEAAAAA==.Rolockrad:BAAALgAECgUJCAAAAA==.Roradonria:BAAALgAECgEJAQAAAA==.Rord:BAABLgAECn8sAAMLAAgJ6yKtCwAwAwALAAgJ6yKtCwAwAwAiAAgJQCAKDwCdAgAAAA==.Rorloc:BAAALgADCgIJAgAAAA==.Rosalei:BAAALgADCgMJAwAAAA==.Rownin:BAAALgADCgEJAgAAAA==.Royaljalopen:BAAALgAECgIJAQAAAA==.',
Ru='Ruinaria:BAAALgADCgMJAwAAAA==.Rumblepak:BAAALgADCgcJDwAAAA==.Rumblez:BAAALgADCgEJAQAAAA==.Runicstrike:BAABLgAECn8wAAMEAAkJ+yUiAwAFAwAEAAkJ+yUiAwAFAwAYAAMJnR8UFwDFAAAAAA==.',
Rz='Rzarazor:BAABLgAECn8ZAAIGAAYJOwu7gQDQAAAGAAYJOwu7gQDQAAAAAA==.',
Sa='Sadeye:BAAALgAECgYJCAAAAA==.Saeword:BAAALgADCgYJBgAAAA==.Salvation:BAAALgADCgYJBgAAAA==.Samborn:BAAALgADCgEJAQAAAA==.Sanctustrike:BAAALgAECgYJCgAAAA==.Sandero:BAABLgAECn8UAAILAAgJjwphOABjAQALAAgJjwphOABjAQAAAA==.Saraphina:BAABLgAECn8YAAMGAAYJdQ1NcAD4AAAGAAYJigxNcAD4AAAMAAMJBhFyEQCsAAAAAA==.Sathrell:BAAALgADCgUJBQAAAA==.Savageborn:BAAALgADCgIJAgAAAA==.Savagetime:BAABLgAECn8hAAIGAAcJ3hoVIgDiAQAGAAcJ3hoVIgDiAQAAAA==.',
Sc='Scarletwitçh:BAAALgADCgIJAgABLgAECggJHgAOAO4hAA==.Schnooks:BAAALgAECgEJAgABLgAECgcJCwAKAAAAAA==.Scyythe:BAAALgADCgEJAQAAAA==.',
Se='Sedor:BAAALgADCgEJAQAAAA==.Sellandre:BAAALgAECgIJBQAAAA==.Selvalamhi:BAAALgADCgcJDQABLgAECggJHwAcAP0aAA==.Semi:BAABLgAECn8hAAIQAAgJbRC7HQCtAQAQAAgJbRC7HQCtAQAAAA==.Sensenah:BAAALgADCgUJEgAAAA==.Serenitie:BAAALgADCgcJDAAAAA==.Serpompom:BAAALgAECgUJBgAAAA==.',
Sh='Shadowbugger:BAAALgADCgcJBwAAAA==.Shadowknigh:BAAALgAECgMJAwAAAA==.Shalirah:BAAALgAECgYJBwABLgAECgcJFQAEAKYRAA==.Sharaudra:BAAALgADCgMJAwABLgAECggJLAALAOsiAA==.Shengal:BAABLgAECn8kAAMIAAgJOAhTHQAWAQAIAAgJOAhTHQAWAQAhAAEJQQFxjgASAAAAAA==.Sherfight:BAABLgAECn8jAAMbAAgJuBVEHwDmAQAbAAgJuBVEHwDmAQAFAAYJLRnzFABZAQAAAA==.Shiftyzegg:BAAALgAECgEJAQAAAA==.Shipp:BAAALgAECgMJBAAAAA==.Shmakk:BAAALgADCgYJCQAAAA==.Shmebulon:BAAALgADCgEJAQAAAA==.Shopkeep:BAAALgADCgEJAQAAAA==.Shund:BAAALgADCgQJBQABLgAECgQJBAAKAAAAAA==.Shunkd:BAAALgAECgQJBAAAAA==.Shyjinx:BAAALgADCgEJAQAAAA==.Shyvala:BAAALgAECgcJEgAAAA==.',
Si='Sig:BAAALgADCgEJAQAAAA==.Silithaine:BAAALgAECgIJAgAAAA==.Silvarogue:BAAALgAECgYJCQAAAA==.',
Sk='Skinwalk:BAAALgAECgQJBAAAAA==.Skrillen:BAAALgADCgcJBwAAAA==.',
Sl='Slackerftw:BAAALgAECgQJCAAAAA==.Slamhog:BAABLgAECn8cAAIEAAcJEhrzHwDIAQAEAAcJEhrzHwDIAQAAAA==.Sleazo:BAAALgADCgUJBQAAAA==.Sleew:BAABLgAECn8jAAMSAAgJmBksEwALAgASAAcJHBksEwALAgATAAcJKRUKEQDFAQAAAA==.Slippydippy:BAAALgAECgMJAwAAAA==.Slobbin:BAAALgADCgUJBQAAAA==.Sloppydrag:BAAALgAECgQJBQAAAA==.',
Sm='Smacku:BAAALgADCggJDgAAAA==.Smaugly:BAAALgAECgcJEwAAAA==.Smaugumz:BAAALgAECgcJCwAAAA==.Smokebae:BAAALgADCgEJAQAAAA==.Smorz:BAAALgADCgMJAwAAAA==.',
Sn='Snackalot:BAAALgADCgcJCAAAAA==.Snocaps:BAAALgAECgEJAQAAAA==.Snowblade:BAAALgAECgYJCwAAAA==.',
So='Soggypringle:BAAALgADCgIJAgAAAA==.Solan:BAAALgAECgEJAQABLgAECgEJAQAKAAAAAA==.Soleilroi:BAAALgAECgQJCQAAAA==.Soletaken:BAAALgAECgEJAQAAAA==.Solson:BAAALgADCgUJBQAAAA==.',
Sp='Specsdraco:BAABLgAECn8fAAIRAAgJBCPmAQBMAgARAAgJBCPmAQBMAgAAAA==.Spewpuke:BAABLgAECn8zAAIXAAgJDB37BAAUAgAXAAgJDB37BAAUAgAAAA==.Spinlock:BAAALgAECgEJAQAAAA==.',
St='Staci:BAABLgAECn8gAAIHAAgJ+RYFDADtAQAHAAgJ+RYFDADtAQAAAA==.Starfree:BAABLgAECn8VAAMaAAgJxgi4KgBEAQAaAAcJQAm4KgBEAQAFAAIJLgcEWgBRAAAAAA==.Steelhoof:BAAALgAECgMJBAAAAA==.Steelsham:BAABLgAECn8aAAMJAAgJjwcKHQAuAQAJAAgJjwcKHQAuAQAVAAYJuwsnWgAgAQAAAA==.Stgermain:BAABLgAECn8oAAQaAAkJJh3WAwCfAgAaAAkJJh3WAwCfAgAbAAYJbhZeMgB2AQAFAAEJAACySgAAAAAAAA==.Stinkybinks:BAAALgADCgYJBgAAAA==.Stonedmaster:BAAALgAECgUJCwAAAA==.Strickdic:BAAALgADCgcJCQAAAA==.Strikeanywer:BAAALgAECgEJAQAAAA==.Stuard:BAAALgAECgQJDAAAAA==.Stuardh:BAAALgAECgEJAQAAAA==.',
Su='Superstoned:BAAALgADCgcJEAAAAA==.Surudruid:BAAALgAECgMJAwAAAA==.',
Sw='Swampy:BAAALgADCgUJBQAAAA==.Swolbõi:BAAALgAECgYJDAAAAA==.',
Sy='Sykes:BAABLgAFFH8FAAIhAAMJ1hQSDwCsAAAhAAMJ1hQSDwCsAAAAAA==.Sylrana:BAACLgAFFH8GAAIjAAMJTQ0zGwDDAAAjAAMJTQ0zGwDDAAAuAAQKfxcAAiMACAlQFQxCAJkBACMACAlQFQxCAJkBAAAA.Sylvaelrodas:BAAALgADCggJCAAAAA==.Sylvarion:BAAALgADCgUJBQAAAA==.Sylvie:BAAALgADCgcJDAABLgAECgQJBAAKAAAAAA==.Sylzyrus:BAABLgAECn8iAAIfAAgJthoBBABCAgAfAAgJthoBBABCAgAAAA==.',
Ta='Tabuta:BAAALgAECgcJDwAAAA==.Taktikil:BAAALgADCgkJFgAAAA==.Taktikyl:BAAALgADCgcJDQABLgADCgkJFgAKAAAAAA==.Talizar:BAAALgADCgIJAwAAAA==.Talor:BAAALgADCgYJCAAAAA==.Talrad:BAAALgAECgYJDAAAAA==.Tarrot:BAAALgADCgIJAgAAAA==.Tauralyon:BAABLgAECn8fAAIiAAgJiB9eCABTAgAiAAgJiB9eCABTAgAAAA==.Tazerxface:BAAALgAECgQJBQAAAA==.Tazomfg:BAAALgADCgEJAgAAAA==.',
Te='Tealgos:BAAALgADCgEJAQAAAA==.Teenyhands:BAAALgAECgUJCwAAAA==.Telarae:BAABLgAECn8cAAILAAgJRBrMVADjAQALAAgJRBrMVADjAQAAAA==.Teldrasa:BAACLgAFFH8GAAIjAAIJQxLnGQCVAAAjAAIJQxLnGQCVAAAuAAQKfyQAAyMACAntGiAmACACACMACAntGiAmACACACQABgk7E7gYADgBAAAA.Tellera:BAAALgAECgQJBQAAAA==.Tempér:BAAALgADCgUJCgABLgAECgcJEAAKAAAAAA==.Tereshi:BAAALgAECgEJAQABLgAECgYJCAAKAAAAAA==.Teugelsi:BAAALgADCgEJAQAAAA==.Teukard:BAAALgADCgIJAwAAAA==.',
Th='Thebigmon:BAABLgAECn8gAAIJAAcJIRvVDADPAQAJAAcJIRvVDADPAQAAAA==.Thedabara:BAAALgAECgMJAwAAAA==.Thegriddler:BAAALgAECgEJAQAAAA==.Thermocline:BAAALgAECgUJBQABLgAECgcJGgANAEsaAA==.Thesolartaco:BAAALgADCgYJCAAAAA==.Thewhite:BAABLgAECn8XAAIjAAgJ0Q9WNAAHAQAjAAgJ0Q9WNAAHAQAAAA==.Thiccjinbei:BAAALgAECgMJBgAAAA==.Thingamabob:BAAALgAECgMJBgAAAA==.Thordriel:BAAALgAECgYJDgAAAA==.Threna:BAAALgADCgcJBwAAAA==.Thrisper:BAABLgAECn8ZAAIjAAcJiwbqOwDjAAAjAAcJiwbqOwDjAAAAAA==.Thrudheals:BAAALgAECgQJCAAAAA==.',
Ti='Tickeld:BAAALgAECgMJBQAAAA==.Tintaglia:BAAALgADCgEJAQAAAA==.Tinytina:BAABLgAFFH8FAAIhAAMJWwi8DADWAAAhAAMJWwi8DADWAAAAAA==.',
To='Tocino:BAAALgADCgMJAwAAAA==.Tofrenm:BAAALgAECgYJCwAAAA==.Togashi:BAAALgADCgcJBwAAAA==.Tombomb:BAABLgAECn8VAAIWAAgJtw1rEQCDAQAWAAgJtw1rEQCDAQAAAA==.Tomspoojer:BAAALgAECgEJAQAAAA==.Topnacho:BAAALgAECgYJEAABLgAFFAUJDgAOAPYVAA==.Torgrim:BAAALgAECgIJAgAAAA==.',
Tr='Traitor:BAAALgADCgcJCQAAAA==.Traumatik:BAABLgAECn8dAAIEAAgJERoNFQASAgAEAAgJERoNFQASAgAAAA==.Treebird:BAAALgADCgkJCQAAAA==.Treespirit:BAAALgAECgEJAQAAAA==.Trekin:BAAALgAECgIJAgAAAA==.Trigospread:BAAALgADCgUJBQABLgAECgIJAgAKAAAAAA==.Trikkon:BAAALgADCgcJBwABLgAECgIJAgAKAAAAAA==.Tripallie:BAAALgADCgYJCgAAAA==.Trisperth:BAAALgADCgQJBgAAAA==.Trocity:BAAALgAECgIJBQAAAA==.Trollyjoebo:BAAALgADCgEJAQAAAA==.Trudeathh:BAACLgAFFH8GAAIYAAMJTBEPDgDBAAAYAAMJTBEPDgDBAAAuAAQKfxQAAxgABgliI1gQAAUCABgABgliI1gQAAUCABkABAn2CuQOALMAAAAA.',
Tu='Turbosins:BAAALgAECgIJAgAAAA==.',
Tw='Twestside:BAAALgAECgMJAgAAAA==.',
Ty='Tylenolbaby:BAAALgADCgcJDQABLgAECgIJAgAKAAAAAA==.Typhoone:BAAALgAFFAEJAQAAAA==.Tyranbae:BAAALgAECgYJCgABLgAFFAMJBgAfAFoZAA==.Tyrur:BAAALgAECgYJDAAAAA==.Tytherion:BAAALgAECgEJAQAAAA==.',
['Tö']='Tönesies:BAAALgAECgMJAwAAAA==.',
Ug='Ugbukk:BAAALgADCgcJBwAAAA==.Uglyashell:BAAALgADCgkJFwAAAA==.',
Um='Umbriel:BAAALgAECgEJAQAAAA==.Umbrielagosa:BAACLgAFFH8OAAIfAAQJgBujBwBkAQAfAAQJgBujBwBkAQAuAAQKfx4AAh8ACAkrHvcHALwCAB8ACAkrHvcHALwCAAAA.',
Un='Unclefingiez:BAAALgADCgEJAQAAAA==.',
Ur='Urknee:BAAALgADCgUJBQAAAA==.Urotherdaddy:BAAALgAECgYJEQAAAA==.',
Va='Vaelith:BAACLgAFFH8FAAIGAAMJZxODMgADAQAGAAMJZxODMgADAQAuAAQKfyEAAgYACAn3HoQOAGoCAAYACAn3HoQOAGoCAAAA.Valaxia:BAAALgADCgEJAQAAAA==.Valerikka:BAAALgAECgEJAQAAAA==.Valkaire:BAAALgAECgEJAQAAAA==.Valnyx:BAAALgADCgEJAQAAAA==.Valsorin:BAAALgAECgUJDgAAAA==.Valtaea:BAACLgAFFH8GAAIGAAMJhwTrPQDQAAAGAAMJhwTrPQDQAAAuAAQKfxwAAgYACAkIFwpaACsCAAYACAkIFwpaACsCAAAA.Valwhoard:BAAALgADCgcJCAAAAA==.Vampiroth:BAAALgADCgYJBgAAAA==.Vanille:BAAALgADCgEJAQAAAA==.Varyndra:BAAALgAECgEJAQAAAA==.',
Ve='Veks:BAAALgADCggJCAAAAA==.Velour:BAAALgAECgcJEwABLgAECgUJCQAKAAAAAA==.Velzhara:BAAALgADCgMJAwAAAA==.',
Vi='Vigilus:BAAALgAECgQJCAAAAA==.Vividdevour:BAAALgADCgMJAwAAAA==.Vixol:BAABLgAECn8UAAIGAAcJHR7nLACwAQAGAAcJHR7nLACwAQAAAA==.',
Vo='Voidheals:BAAALgAECgMJCAAAAA==.Voids:BAAALgADCgEJAgAAAA==.Volairne:BAAALgAECgMJBwAAAA==.',
Wa='Waarsêer:BAAALgAECgYJCQAAAA==.Wackah:BAABLgAECn8iAAMTAAkJfx29AgDXAgATAAkJfx29AgDXAgASAAIJJQpVigBoAAAAAA==.Wafflxs:BAACLgAFFH8GAAIIAAMJwB91DAAUAQAIAAMJwB91DAAUAQAuAAQKfxsAAwgACAnhJNkDADUDAAgACAnhJNkDADUDACEAAQloAxFUACUAAAAA.Waldo:BAAALgAECgQJBAAAAA==.Wanpisu:BAABLgAECn8UAAILAAgJixD/aQCrAQALAAgJixD/aQCrAQAAAA==.Wardaddy:BAAALgAECgQJBAAAAA==.Wardorable:BAAALgADCgMJAwAAAA==.Warmage:BAAALgADCgIJAgAAAA==.Wartirus:BAEBLgAECn8cAAISAAgJQRzOEAAgAgASAAgJQRzOEAAgAgAAAA==.',
We='Weepingtiger:BAAALgAECgcJAQAAAA==.Weezing:BAAALgAECgEJAgAAAA==.Wellfookthat:BAAALgAECgUJDwAAAA==.Wellfookyew:BAAALgADCgYJBgAAAA==.Weolf:BAAALgAECgYJEQAAAA==.',
Wh='Wheelchair:BAAALgAECgQJDAABLgAFFAIJAgAKAAAAAA==.Whyfeedzwhy:BAAALgAECgEJAQAAAA==.Whyvala:BAABLgAECn8UAAIGAAYJCgJekgCrAAAGAAYJCgJekgCrAAAAAA==.',
Wi='Wiisp:BAAALgADCgcJCwAAAA==.Wilmadikfit:BAAALgAECgMJAwAAAA==.Wintersidemo:BAABLgAECn8dAAISAAgJ4hcDHwC7AQASAAgJ4hcDHwC7AQAAAA==.',
Wo='Wolnney:BAABLgAECn8WAAILAAYJQCPkJQCsAQALAAYJQCPkJQCsAQAAAA==.',
Wr='Wraithian:BAAALgAECgUJBQAAAA==.',
Wy='Wylar:BAABLgAECn8XAAIEAAcJoRRGbwCqAQAEAAcJoRRGbwCqAQAAAA==.',
Xa='Xalatoes:BAABLgAFFH8MAAIVAAUJQx66AwC2AQAVAAUJQx66AwC2AQAAAA==.',
Xe='Xeb:BAAALgADCgEJAQAAAA==.Xenar:BAAALgADCgIJAwAAAA==.Xerathor:BAAALgAFFAIJAgAAAA==.',
Xi='Xiaoyu:BAAALgAECgYJBgAAAA==.Xim:BAAALgAECgIJAgAAAA==.',
Xr='Xraiz:BAAALgADCgIJAgAAAA==.',
Xy='Xyne:BAAALgAECgEJAgAAAA==.',
Xz='Xziled:BAAALgAECgMJBQAAAA==.',
Ya='Yakihunt:BAAALgADCgIJAgAAAA==.',
Yo='Yogonine:BAACLgAFFH8JAAIIAAQJDxjaCQA/AQAIAAQJDxjaCQA/AQAuAAQKfykAAwgACQn2IUkDAEYDAAgACQn2IUkDAEYDACEAAQn4BKlQACsAAAAA.Yoshie:BAAALgAECgMJCAAAAA==.',
Yu='Yunna:BAAALgADCgcJDAAAAA==.',
Yx='Yxma:BAABLgAECn8aAAIgAAYJ4gnACwAhAQAgAAYJ4gnACwAhAQAAAA==.',
Za='Zanetta:BAAALgADCgYJGgAAAA==.Zanydruid:BAAALgAECgUJCAAAAA==.Zanza:BAAALgAECgcJEwAAAA==.Zariana:BAAALgADCgEJAQAAAA==.',
Ze='Zekku:BAAALgAECgQJBgAAAA==.Zeldõris:BAAALgAECgQJBgAAAA==.Zephadawn:BAAALgAECgEJAQAAAA==.',
Zh='Zhamazu:BAAALgAECgIJAgAAAA==.Zhy:BAAALgAECgYJCgAAAA==.Zhygar:BAAALgAECgUJCQAAAA==.',
Zi='Zinniah:BAAALgAECgQJBAAAAA==.Zipthud:BAAALgAECgMJCAAAAA==.',
Zo='Zodin:BAAALgADCgYJBwABLgAECgUJCgAKAAAAAA==.Zombiez:BAAALgAECgQJCAAAAA==.',
Zu='Zujoth:BAAALgADCgcJFQAAAA==.',
['Âb']='Âbaddön:BAAALgADCgUJBgAAAA==.',
['Çh']='Çhefhunter:BAAALgAECgQJAwAAAA==.Çhloe:BAAALgADCgIJAgAAAA==.',
['Çl']='Çlaire:BAAALgAECgEJAQAAAA==.',
['Ðr']='Ðrstrange:BAAALgAECgIJAgABLgAECggJHgAOAO4hAA==.',
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

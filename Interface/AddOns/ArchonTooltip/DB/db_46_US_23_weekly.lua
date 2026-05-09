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

local lookup = {'Hunter-Survival','Mage-Fire','Evoker-Augmentation','DeathKnight-Unholy','Priest-Shadow','Mage-Frost','Warrior-Fury','Monk-Mistweaver','Shaman-Elemental','Warrior-Protection','Warrior-Arms','Paladin-Retribution','Unknown-Unknown','Mage-Arcane','DemonHunter-Devourer','Evoker-Devastation','Druid-Restoration','Druid-Balance','Hunter-BeastMastery','Hunter-Marksmanship','Warlock-Demonology','Warlock-Destruction','DemonHunter-Vengeance','Shaman-Restoration','DeathKnight-Frost','Monk-Brewmaster','DeathKnight-Blood','Priest-Holy','Priest-Discipline','Warlock-Affliction','Druid-Guardian','Monk-Windwalker','Rogue-Subtlety','Paladin-Protection','Evoker-Preservation','Shaman-Enhancement','Paladin-Holy','Druid-Feral','DemonHunter-Havoc',}
local provider = {region='US',realm='Azgalor',name='US',type='weekly',zone=46,date='2026-05-08',data={Aa='Aarahunt:BAABLgAECn8tAAIBAAgJJQecFgBaAQABAAgJJQecFgBaAQAAAA==.',
Ab='Abente:BAAALgAECgEJAQAAAA==.',
Ac='Acarin:BAAALgAECgUJCwAAAA==.',
Ad='Adawna:BAAALgAECgYJCQAAAA==.Addio:BAAALgADCgcJDAAAAA==.Adgalor:BAAALgADCgkJCQAAAA==.Adrenaline:BAAALgADCgMJAQAAAA==.Adsaw:BAABLgAECn8fAAICAAkJehjZAABbAgACAAkJehjZAABbAgAAAA==.Adula:BAAALgAECgYJDQABLgAFFAQJDAADAMMTAA==.',
Ae='Aelunara:BAABLgAECn8bAAIEAAYJoBzFQgB1AQAEAAYJoBzFQgB1AQAAAA==.Aer:BAAALgADCgcJDgAAAA==.Aerostalim:BAAALgAECgUJBwAAAA==.',
Af='Aftershocks:BAAALgAECgYJEwAAAA==.',
Ag='Agh:BAAALgAECgIJAgAAAA==.',
Ah='Ahnanji:BAAALgADCgEJAQAAAA==.Ahoydorei:BAAALgAECgEJAQAAAA==.',
Ai='Aijha:BAAALgADCgMJAwAAAA==.Ailric:BAABLgAECn8gAAIFAAgJ8BetDAD8AQAFAAgJ8BetDAD8AQAAAA==.',
Ak='Akivra:BAAALgAECgYJBgAAAA==.',
Al='Alanon:BAAALgADCgEJAQAAAA==.Alanorae:BAAALgADCgkJDAAAAA==.Alarakian:BAAALgAECgUJBQAAAA==.Alassae:BAAALgADCgcJCQAAAA==.Alcapown:BAAALgAECgQJDwAAAA==.Aldrea:BAAALgAECgQJBgAAAA==.Aleco:BAAALgADCgcJDAAAAA==.Alexdaelfs:BAAALgAECgEJAQAAAA==.Aliakin:BAABLgAECn8dAAIGAAgJDx9iIgAeAgAGAAgJDx9iIgAeAgAAAA==.Alinda:BAAALgADCgcJCgABLgAECggJGwAHAHkWAA==.Alleviel:BAAALgAECgkJDwAAAA==.Aloros:BAAALgAFFAIJAgAAAA==.Alphirion:BAAALgAECgYJDAAAAA==.Alyssachik:BAABLgAECn8UAAIIAAYJrw/xNAAdAQAIAAYJrw/xNAAdAQAAAA==.',
Am='Amaeradin:BAAALgAECgUJBQAAAA==.Amarxd:BAACLgAFFH8GAAIJAAIJtRxdHwCnAAAJAAIJtRxdHwCnAAAuAAQKfxsAAgkABwnlIb4aAD0CAAkABwnlIb4aAD0CAAAA.Amashira:BAAALgAECgQJBAAAAA==.Ambosi:BAAALgAECgYJDAAAAA==.',
An='Anamae:BAAALgADCgIJAgAAAA==.Anarchtear:BAAALgAECgYJEQAAAA==.Anartik:BAAALgADCgIJAgAAAA==.Andesipa:BAAALgAFFAEJAgAAAA==.Anduin:BAAALgAECgEJAQAAAA==.Anetha:BAAALgAECgYJCgAAAA==.Angerclaw:BAABLgAECn8bAAQKAAcJ6hy7DwBnAQAKAAYJ6Bm7DwBnAQAHAAcJPBhRIwBVAQALAAMJKRG5LQBpAAAAAA==.Angrybirdee:BAAALgAECgMJAwAAAA==.Ankaramessi:BAAALgAECgYJCQAAAA==.Annaalista:BAABLgAECn8WAAIMAAcJYgtKXQA1AQAMAAcJYgtKXQA1AQAAAA==.Annulled:BAAALgADCgMJAwABLgAECgUJBwANAAAAAA==.',
Ap='Apollosolo:BAAALgADCgIJAgAAAA==.Apoth:BAAALgAECgcJAgAAAA==.',
Ar='Aradrad:BAAALgADCgUJBwAAAA==.Arakisa:BAAALgAECgQJCAAAAA==.Aranhferizzi:BAAALgADCgYJEgAAAA==.Arazara:BAAALgADCgIJAgAAAA==.Arcaenus:BAAALgAECgQJBgABLgAECggJFwAMAEEiAA==.Arcanofrosty:BAAALgAECgYJBgAAAA==.Archspally:BAAALgADCgEJAgAAAA==.Arivian:BAAALgAECgYJBQAAAA==.Arkileous:BAABLgAECn8mAAMGAAgJfhkDLgDpAQAGAAgJfhkDLgDpAQAOAAEJqg+XHQA3AAAAAA==.Arkmage:BAAALgADCgcJBwAAAA==.Arraegon:BAAALgADCgIJAgAAAA==.Artemmis:BAACLgAFFH8FAAIBAAMJ/wMpEgDLAAABAAMJ/wMpEgDLAAAuAAQKfx4AAgEABwnnG6kLABcCAAEABwnnG6kLABcCAAAA.',
As='Asdolfo:BAAALgAECgEJAQAAAA==.Assapopolous:BAAALgAECgYJCgAAAA==.',
At='Atalmon:BAABLgAECn8jAAIMAAgJFyHKDQCRAgAMAAgJFyHKDQCRAgAAAA==.Atticos:BAAALgAECgYJCgAAAA==.Attistike:BAAALgADCgYJBgAAAA==.',
Av='Avastin:BAAALgAECgUJBwAAAA==.',
Aw='Awni:BAABLgAECn8jAAILAAkJhh4XBABOAgALAAkJhh4XBABOAgAAAA==.',
Az='Azarinth:BAAALgAECgQJBAABLgAFFAMJBQALADMEAA==.Azenastra:BAAALgAECgEJAQAAAA==.',
Ba='Babadookk:BAABLgAECn8VAAIPAAgJRB0fQQDvAQAPAAgJRB0fQQDvAQAAAA==.Bahbahr:BAACLgAFFH8JAAIGAAMJnxxHPAAdAQAGAAMJnxxHPAAdAQAuAAQKfyQAAgYACAl9IrQlANwCAAYACAl9IrQlANwCAAAA.Bahrim:BAAALgAECgQJCAAAAA==.Balarian:BAAALgADCgkJEQAAAA==.Balefirebob:BAABLgAECn8fAAMDAAkJxhDgDwDWAQADAAkJghDgDwDWAQAQAAIJ/w/ENQBnAAAAAA==.Bangbangji:BAAALgADCgMJAwABLgAECgYJCAANAAAAAA==.Bangis:BAAALgADCgcJBwABLgAECgkJJQAIAPoZAA==.Baphome:BAAALgAECgMJAwAAAA==.Barkntank:BAAALgAECgEJAQAAAA==.Barreloferal:BAAALgAECgMJBAAAAA==.Bartholomeow:BAAALgAECgIJAgAAAA==.Batohar:BAAALgAECgEJAQAAAA==.Battlebeats:BAAALgADCgIJAgAAAA==.Baxx:BAAALgADCgkJCwAAAA==.Bazzoo:BAABLgAECn8VAAMRAAYJjhiAQAARAQARAAYJjhiAQAARAQASAAYJvQ3xJwABAQAAAA==.',
Be='Beachbabe:BAAALgAFFAEJAwAAAA==.Bendable:BAAALgADCgEJAQAAAA==.Berrd:BAAALgAECgMJAwAAAA==.Bethezar:BAAALgAECgYJCgAAAA==.',
Bh='Bhangbhang:BAABLgAECn8lAAIIAAkJ+hlLCABxAgAIAAkJ+hlLCABxAgAAAA==.',
Bi='Bigboitaur:BAAALgADCgEJAQAAAA==.Biggerbits:BAAALgAECgEJAQAAAA==.Bigkrayze:BAABLgAECn8VAAIEAAYJZRjJXQAqAQAEAAYJZRjJXQAqAQAAAA==.Bigpapapump:BAAALgAECgYJBQAAAA==.Bimboblyad:BAABLgAECn+2AAQTAAkJBSfqAQA1AwAUAAgJ+SauAQCnAwATAAgJASfqAQA1AwABAAgJyiVxAQABAwAAAA==.Birdupp:BAAALgADCgEJAgAAAA==.Bizzarro:BAAALgAECgYJEQAAAA==.Bizzkitt:BAAALgADCgkJEAAAAA==.',
Bl='Blackwîdow:BAABLgAECn8mAAIPAAgJTiPEBgC9AgAPAAgJTiPEBgC9AgAAAA==.Blaigne:BAAALgADCgcJCwAAAA==.Blizimcguire:BAAALgAECgQJBQAAAA==.Bloodycat:BAAALgAECgMJAwAAAA==.Bloodymenses:BAAALgADCgkJEwAAAA==.Bluerose:BAAALgAECgYJDgAAAA==.Blurry:BAAALgAECgEJAQAAAA==.',
Bo='Bonngo:BAAALgAECgEJAgAAAA==.Boofgodrekk:BAAALgAECgMJBAAAAA==.Boofkokaina:BAAALgAECgEJAQAAAA==.Boofydoo:BAAALgADCgIJAgAAAA==.Borku:BAAALgAECgYJBgABLgAECggJGQAHAJMbAA==.',
Br='Brannen:BAAALgAECgUJBwAAAA==.Brayicela:BAAALgADCgQJBAABLgAECgUJCgANAAAAAA==.Brazzii:BAAALgADCgYJBgAAAA==.Bricksanchez:BAAALgAECgMJAwAAAA==.Brindo:BAAALgADCgUJBwAAAA==.Bringbags:BAAALgADCgMJAwAAAA==.Bristleback:BAAALgAECgEJAQAAAA==.Britneyfears:BAAALgAECgcJDAAAAA==.Bro:BAAALgAECgMJAwAAAA==.Brokentuskz:BAAALgAECgYJDgABLgAECgkJKAAMAG4VAA==.Broten:BAAALgADCgMJAwAAAA==.Brëwskï:BAAALgADCgcJCAAAAA==.',
Bu='Buffbutton:BAAALgAECgYJEwAAAA==.Bulistus:BAAALgADCgIJAgAAAA==.Bulszeye:BAAALgAECgYJCwAAAA==.Bumme:BAAALgAECgYJDAAAAA==.Burningwave:BAABLgAECn8gAAMVAAgJEhzoEABdAgAVAAgJEhzoEABdAgAWAAEJ+QukcQA0AAAAAA==.Buzzie:BAAALgADCgYJCgAAAA==.',
Bw='Bwonsamdiboy:BAAALgADCgIJAgAAAA==.',
Bx='Bxndo:BAAALgAECgEJAgAAAA==.',
Ca='Caerisma:BAAALgAECggJIQAAAQ==.Calebsdemon:BAAALgAECgEJAQAAAA==.Caltha:BAAALgADCgcJBwAAAA==.Caravaggio:BAAALgADCgUJBQAAAA==.Carterann:BAAALgADCgMJAwAAAA==.Casterbation:BAAALgADCgYJBgAAAA==.Cat:BAAALgADCgUJBQAAAA==.Catiany:BAAALgADCgYJBgAAAA==.',
Ce='Celithil:BAAALgAECgEJAQAAAA==.Ceroll:BAACLgAFFH8GAAIPAAQJBA18JQAbAQAPAAQJBA18JQAbAQAuAAQKfxEAAw8ACAnJGoogAMUBAA8ACAnJGoogAMUBABcAAQk5FdIcAD4AAAAA.Cerolumas:BAAALgADCgUJBQABLgAECgEJAQANAAAAAA==.',
Ch='Chadwik:BAAALgADCgYJBgAAAA==.Chainevoker:BAAALgAECgYJCgAAAA==.Changoqt:BAAALgAECggJDQAAAA==.Charbelcher:BAAALgAECgEJAQAAAA==.Charbzenberg:BAAALgADCgIJAgAAAA==.Charisma:BAAALgADCgYJBgABLgAECggJIQANAAAAAQ==.Cheeseburgrr:BAAALgAECgYJDwAAAA==.Chiang:BAAALgAECgUJBQAAAA==.Chikfila:BAAALgADCgYJCgAAAA==.Chilijayleen:BAABLgAECn8cAAIWAAYJhRaqCABPAQAWAAYJhRaqCABPAQAAAA==.Chinari:BAAALgADCgYJBgAAAA==.Chinkinarobe:BAAALgAECgMJAwAAAA==.Chonhunter:BAAALgAECgcJCgAAAA==.Chungae:BAAALgADCgMJAwAAAA==.Chunkychucky:BAAALgADCgIJAgAAAA==.Chångomike:BAAALgADCgkJEgABLgAECggJDQANAAAAAA==.',
Cj='Cjay:BAAALgADCgQJAwAAAA==.',
Cl='Clegen:BAAALgADCgUJBQAAAA==.Cloax:BAACLgAFFH8IAAIFAAMJTAMwFgC2AAAFAAMJTAMwFgC2AAAuAAQKfyYAAgUACAlGG4ESAGQCAAUACAlGG4ESAGQCAAAA.Clýde:BAAALgAECgUJCAAAAA==.',
Co='Cobask:BAAALgAECgMJAgAAAA==.Cobyashi:BAAALgADCgcJBwAAAA==.Colinar:BAAALgAECgYJEQAAAA==.Compassion:BAAALgADCgYJCgAAAA==.Conquer:BAAALgADCgYJBgAAAA==.Conquermonk:BAAALgADCgQJBAAAAA==.Coobin:BAAALgADCgIJAgAAAA==.Coors:BAAALgADCgQJBAAAAA==.Cotas:BAAALgAECgYJCwAAAA==.Couraegus:BAABLgAECn8XAAIMAAgJQSJmEAAMAwAMAAgJQSJmEAAMAwAAAA==.Covenants:BAAALgADCgQJBAAAAA==.',
Cr='Crabemoji:BAAALgAECgQJBQABLgAFFAUJEQAYAGAeAA==.Crapo:BAABLgAECn8XAAIZAAcJLRWKBQDgAQAZAAcJLRWKBQDgAQAAAA==.Crazyxspeedy:BAAALgADCgEJAQAAAA==.Crewbin:BAAALgAECgMJBAAAAA==.Croobin:BAAALgADCgcJBwAAAA==.Crud:BAAALgADCgMJAwAAAA==.Cryhavok:BAAALgAECgcJDAAAAA==.Crymzin:BAAALgADCgIJAgAAAA==.',
Cu='Cubefuonyou:BAAALgAFFAEJAQAAAA==.Cubesoaker:BAAALgAECgQJCQAAAA==.Cutesbrews:BAABLgAECn8eAAIaAAcJ5RQhHwA8AQAaAAcJ5RQhHwA8AQAAAA==.',
Cy='Cyther:BAAALgAECgEJAQAAAA==.',
['Cê']='Cêll:BAAALgADCgEJAgAAAA==.',
Da='Daghar:BAABLgAECn8bAAQLAAgJ8RgYDACAAQALAAcJ9xIYDACAAQAKAAcJHBp+DwBrAQAHAAMJGwbwiwCPAAAAAA==.Dalé:BAAALgAECgYJBgAAAA==.Damecias:BAAALgAECgcJEgAAAA==.Dana:BAAALgADCgIJAQAAAA==.Danielsonn:BAAALgAECgQJBAAAAA==.Danyphantom:BAAALgADCgMJBAAAAA==.Darbpal:BAACLgAFFH8HAAIMAAMJQAPUNwDRAAAMAAMJQAPUNwDRAAAuAAQKfycAAgwACAkMFTk0AKwBAAwACAkMFTk0AKwBAAAA.Darealrambo:BAAALgADCgYJCwAAAA==.Darfk:BAAALgADCgUJCAAAAA==.Darkbender:BAAALgAECgYJCwAAAA==.Darkmanta:BAAALgAECgMJAwAAAA==.Darkzephyr:BAAALgAECgYJBgAAAA==.Darkÿ:BAAALgAECgUJDgAAAA==.Darnitt:BAAALgADCgQJBAABLgAFFAEJAQANAAAAAA==.Darthvaliate:BAAALgAECgYJCwAAAA==.Datboyj:BAAALgAECgkJDAAAAA==.Davosi:BAABLgAECn8aAAIHAAkJfx3kBQCVAgAHAAkJfx3kBQCVAgAAAA==.Dayrb:BAAALgADCgIJAgAAAA==.',
De='Deadtalini:BAABLgAECn8zAAQbAAkJtBpgCwBdAgAbAAgJ/B1gCwBdAgAEAAkJKwzlXgAnAQAZAAEJdA52FgAzAAAAAA==.Deah:BAABLgAECn8aAAITAAcJ3CGaHwDeAQATAAcJ3CGaHwDeAQAAAA==.Dearling:BAAALgAECgMJAwAAAA==.Deckerdramon:BAABLgAECn8tAAIKAAkJDR1mAwCUAgAKAAkJDR1mAwCUAgAAAA==.Deepeemcgee:BAAALgADCgcJEQAAAA==.Delanoris:BAAALgADCgYJBgAAAA==.Dellera:BAAALgADCgcJGAAAAA==.Delulú:BAAALgAECgEJAQAAAA==.Demonhizzy:BAAALgAFFAEJAQAAAA==.Demontoid:BAAALgADCgcJDQAAAA==.Demonzo:BAAALgADCgYJCwAAAA==.Dennevien:BAAALgADCgcJBgAAAA==.Desaran:BAAALgAECgUJBwAAAA==.Destinda:BAAALgAECgYJCgAAAA==.Devoider:BAAALgAECgYJBgAAAA==.Devour:BAAALgADCgcJDAAAAA==.Devoured:BAAALgAECgMJAgAAAA==.Devours:BAACLgAFFH8ZAAIYAAUJmBkuCQCJAQAYAAUJmBkuCQCJAQAuAAQKfyAAAhgACQk0I1QCAF8DABgACQk0I1QCAF8DAAAA.Devoury:BAACLgAFFH8NAAMcAAQJYR2SBgBbAQAcAAQJYR2SBgBbAQAdAAMJXhdJFwDuAAAuAAQKfxoAAxwACAmJIbgJALECABwACAlxIbgJALECAB0ABwkHGiARADACAAEuAAUUBQkZABgAmBkA.',
Di='Dihfacer:BAAALgAECgIJAgAAAA==.Dippndots:BAAALgADCgEJAQAAAA==.Divinessa:BAAALgADCgcJBwAAAA==.Diâblö:BAACLgAFFH8WAAIIAAUJASa4AgAxAgAIAAUJASa4AgAxAgAuAAQKfzIAAggACAkyJtoBAHcDAAgACAkyJtoBAHcDAAAA.',
Dk='Dkinallday:BAAALgADCggJCwAAAA==.',
Do='Dobro:BAAALgAECggJEAAAAA==.Dosin:BAAALgAECgEJAQAAAA==.Doth:BAAALgADCgIJAgAAAA==.Downkid:BAAALgAECgMJAwAAAA==.',
Dr='Dractharion:BAAALgAECgQJBAAAAA==.Dragapult:BAACLgAFFH8MAAIDAAQJwxN2FwAoAQADAAQJwxN2FwAoAQAuAAQKfysAAwMACQmdHr4EAKoCAAMACQmdHr4EAKoCABAAAwkJD+0wAI8AAAAA.Dragusysmash:BAAALgADCgYJBgAAAA==.Dralvira:BAABLgAECn8mAAIKAAgJuiWyAQBoAwAKAAgJuiWyAQBoAwAAAA==.Drath:BAAALgAECgUJCAAAAA==.Draxithar:BAAALgAFFAEJAQAAAA==.Drazzin:BAAALgADCgIJAgABLgAFFAMJBwAeAD0JAA==.Drgragas:BAAALgAECgYJBgAAAA==.Drunkfaiyd:BAAALgAECgEJAQAAAA==.Dryduss:BAAALgADCgYJBgAAAA==.Drzj:BAAALgAECggJEwAAAA==.',
Ds='Dsappman:BAAALgAECgIJAgAAAA==.',
Du='Dualshock:BAAALgAECgEJAQAAAA==.Duggo:BAAALgAECgYJCwAAAA==.Durvier:BAAALgADCgcJDAAAAA==.Durzaq:BAAALgAECgQJBAAAAA==.',
Dy='Dyrteshadow:BAAALgADCgYJCAAAAA==.',
['Dà']='Dàth:BAAALgAECgUJCQAAAA==.',
Eb='Ebore:BAAALgADCgMJAwAAAA==.',
Ec='Ecoshock:BAAALgADCgMJAwABLgAECgMJCAANAAAAAA==.',
Eh='Eh:BAAALgAECggJCAAAAA==.',
Ei='Eirrin:BAABLgAECn8mAAIcAAgJgiBlCADFAgAcAAgJgiBlCADFAgAAAA==.',
El='Elaineh:BAAALgAECgUJBgAAAA==.Elementalist:BAAALgAECgQJBAAAAA==.Elendira:BAABLgAECn8XAAQcAAcJ8RVqEQDZAQAcAAcJ8RVqEQDZAQAdAAYJ4QVEJAAIAQAFAAEJEgTQZwApAAAAAA==.Elestrike:BAAALgAECgYJCAAAAA==.Elkane:BAAALgAECgYJCwAAAA==.Elleredreaux:BAABLgAECn8eAAIGAAcJ0xVtPwCpAQAGAAcJ0xVtPwCpAQAAAA==.Elofin:BAAALgAECgQJBwAAAA==.',
En='Endomorphism:BAACLgAFFH8NAAIfAAQJ3xgDAwA0AQAfAAQJ3xgDAwA0AQAuAAQKfy8AAh8ACQm8JFsAAFQDAB8ACQm8JFsAAFQDAAEuAAUUBgkZAB8AmRoA.',
Eq='Equidus:BAAALgADCgEJAQAAAA==.',
Er='Eranthis:BAAALgAECgcJDwAAAA==.Errour:BAAALgADCgYJCwAAAA==.',
Et='Etherhand:BAAALgAECgEJAQAAAA==.',
Ev='Eveldumboone:BAACLgAFFH8YAAIbAAYJAh73AgC6AQAbAAYJAh73AgC6AQAuAAQKfyUAAxsACAlxJGMDACUDABsACAlxJGMDACUDABkAAQmOGb0UAEgAAAAA.Evialistia:BAAALgAECgIJAgAAAA==.',
Ez='Ezmelora:BAABLgAECn8dAAIVAAgJwxRbQQAJAgAVAAgJwxRbQQAJAgAAAA==.',
Fa='Faelight:BAAALgAECgEJAQAAAA==.Faenixandria:BAAALgAECgMJBwAAAA==.Fairykiller:BAAALgADCgEJAQAAAA==.Falkrus:BAAALgADCgEJAQAAAA==.Fallenresto:BAAALgADCgcJBwAAAA==.Fancydemon:BAAALgADCgIJAgAAAA==.Fancypets:BAAALgADCgUJBQAAAA==.Fantasie:BAAALgAECgYJCQABLgAECgkJJwAcADAVAA==.Fartz:BAAALgADCgYJBgAAAA==.Fauxpawz:BAAALgAECgcJEQAAAA==.Fayia:BAACLgAFFH8FAAITAAIJ9gXaGwCHAAATAAIJ9gXaGwCHAAAuAAQKfyIAAxMACAlZF4goAK8BABMACAlZF4goAK8BABQABAkdBJBsAIwAAAAA.',
Fe='Fearshaman:BAABLgAECn8oAAIYAAgJbQhVQwB0AQAYAAgJbQhVQwB0AQAAAA==.Felbrew:BAABLgAECn8VAAMgAAgJIR56DgCVAgAgAAgJIR56DgCVAgAaAAcJ7QynewBWAAAAAA==.Felhoof:BAABLgAECn8VAAIhAAcJGhxoHQATAgAhAAcJGhxoHQATAgAAAA==.Fellrend:BAAALgAECgIJAgAAAA==.Felrogue:BAAALgADCgQJBAAAAA==.Felsunder:BAAALgAECgEJAQAAAA==.Femhumanmage:BAAALgAECgYJBgAAAA==.',
Fi='Fibbs:BAABLgAECn8UAAIGAAgJXwzihgDEAQAGAAgJXwzihgDEAQAAAA==.Firaman:BAAALgAECgYJDwAAAA==.Firewraith:BAAALgAECgQJBQAAAA==.Fistmachin:BAABLgAECn8gAAIaAAgJWBBBGAB1AQAaAAgJWBBBGAB1AQAAAA==.Fizzibix:BAAALgADCgIJAwABLgAECgcJFgAEALgSAA==.',
Fl='Flexxed:BAACLgAFFH8MAAIZAAUJexm4AQBTAQAZAAUJexm4AQBTAQAuAAQKfxcAAxkABwmNIg8DAGwCABkABwmNIg8DAGwCAAQAAQmqDLcsASkAAAAA.Flibble:BAAALgADCgEJAQAAAA==.Flip:BAAALgADCgUJBwAAAA==.Florelai:BAAALgAECgQJBQAAAA==.Florin:BAAALgADCgEJAQAAAA==.Flyinmachin:BAAALgAECgEJAgAAAA==.',
Fo='Foreheadkiss:BAAALgAECgcJBwAAAA==.',
Fr='Frakkinfrik:BAAALgADCgIJAgAAAA==.Franciss:BAAALgAECgQJBQAAAA==.Freezie:BAAALgAECgcJDgAAAA==.Freyae:BAAALgADCggJEgAAAA==.Frikkinfrak:BAAALgADCgIJAgAAAA==.Friskie:BAAALgAECgcJCwABLgAECgkJJwAcADAVAA==.Frona:BAAALgADCgYJEgAAAA==.',
Ft='Ftknox:BAAALgAECgQJBQAAAA==.',
Fu='Fufubabe:BAAALgADCgUJBQAAAA==.Fuhq:BAAALgAECgEJAQAAAA==.Fuqin:BAAALgAECgQJBwAAAA==.Furrever:BAAALgAECgYJEQAAAA==.Fuzada:BAABLgAECn8XAAIGAAcJ5CH6OACRAgAGAAcJ5CH6OACRAgAAAA==.',
Fw='Fwuppy:BAAALgAECgEJAQAAAA==.',
Ga='Gament:BAAALgAECgIJAgAAAA==.Ganangus:BAAALgADCgEJAQAAAA==.Gandamar:BAABLgAECn8WAAIVAAcJ3wY1WQAiAQAVAAcJ3wY1WQAiAQAAAA==.Gankzz:BAABLgAECn8ZAAIVAAgJCQydSwBGAQAVAAgJCQydSwBGAQAAAA==.Ganondork:BAAALgADCgMJAwAAAA==.Ganondrow:BAABLgAECn8ZAAIFAAkJpBlxCgAdAgAFAAkJpBlxCgAdAgAAAA==.Gantar:BAAALgADCgcJBwAAAA==.',
Gb='Gboyzz:BAAALgADCgkJCQAAAA==.',
Ge='Gemelo:BAAALgAECgQJCQAAAA==.Genghiscon:BAAALgADCgcJBwAAAA==.Geromul:BAAALgADCgUJBgAAAA==.Gettuff:BAAALgAECgQJBAAAAA==.',
Gg='Ggivverr:BAAALgAECgQJBwAAAA==.',
Gh='Ghstsplntr:BAABLgAECn8pAAIMAAgJJBvQIAAFAgAMAAgJJBvQIAAFAgAAAA==.',
Gi='Gibayy:BAAALgAFFAIJAgAAAA==.Gibsonex:BAABLgAECn8VAAIVAAcJ5RKrNgCKAQAVAAcJ5RKrNgCKAQAAAA==.Gilliamm:BAABLgAECn8VAAIhAAgJtROgIAD0AQAhAAgJtROgIAD0AQAAAA==.Giselda:BAABLgAECn8WAAIEAAcJuBJwQgB1AQAEAAcJuBJwQgB1AQAAAA==.Gizzmah:BAAALgADCgUJBQAAAA==.',
Gl='Gloomstick:BAAALgAECgcJCwAAAA==.Glowza:BAAALgAFFAMJAwAAAA==.',
Go='Gobbs:BAABLgAECn8eAAMTAAgJiBs1PgC2AQATAAgJiBs1PgC2AQAUAAMJqA+hFQCoAAAAAA==.Goblocker:BAAALgADCgYJBgAAAA==.Golath:BAABLgAECn8cAAMMAAYJfBa/UABUAQAMAAYJfBa/UABUAQAiAAYJMAkxGwC6AAAAAA==.Goldnut:BAAALgAECgIJAgAAAA==.Goldoraq:BAAALgAECgEJAQAAAA==.Goldscales:BAAALgADCgMJAwAAAA==.Gonjoodman:BAAALgADCgcJBwAAAA==.Gonthielhunt:BAAALgAECgQJBgAAAA==.Gonzobeanz:BAAALgADCgYJCwAAAA==.Gonzolo:BAAALgADCgUJBgAAAA==.Goocheater:BAAALgADCgYJCQAAAA==.Gorcazzo:BAAALgAECgYJEgAAAA==.Gorekroxx:BAAALgADCgQJAwAAAA==.Gorgonzormu:BAABLgAECn8fAAMQAAgJvSQpBADNAgAQAAcJlSEpBADNAgADAAcJciOfCwARAgAAAA==.Gothbutta:BAAALgAECgQJBwAAAA==.',
Gr='Grandpoobah:BAAALgADCggJCAABLgAFFAQJCwAjACQcAA==.Greela:BAAALgAECgEJAQAAAA==.Gregorian:BAAALgAECgYJEAAAAA==.Gremliin:BAABLgAECn8UAAIcAAgJMBI5GgB6AQAcAAgJMBI5GgB6AQAAAA==.Gremlinstorm:BAAALgADCgYJCQABLgAECggJFAAcADASAA==.Grendalu:BAAALgADCgEJAgAAAA==.Griffy:BAAALgAECgEJAQAAAA==.',
Gu='Gumpiz:BAAALgAECgQJBQAAAA==.',
Ha='Haardslinger:BAAALgADCgcJBwABLgAECgMJAwANAAAAAA==.Hamdon:BAAALgADCgQJBAAAAA==.Hanabi:BAAALgAECgEJAgAAAA==.Haniesh:BAABLgAECn8oAAIMAAkJbhVuHAAdAgAMAAkJbhVuHAAdAgAAAA==.Harlin:BAAALgADCgQJBAABLgAECgQJBQANAAAAAA==.Hatengar:BAABLgAECn8UAAIkAAcJCAdCEQDrAAAkAAcJCAdCEQDrAAAAAA==.Hazben:BAAALgADCgQJBAAAAA==.',
He='Healingeyes:BAAALgADCgYJDAAAAA==.Healmeharder:BAAALgAECgEJAQAAAA==.Helburk:BAAALgADCgYJCQAAAA==.Hellagood:BAAALgAECgYJEQAAAA==.Hethar:BAAALgAECgEJAQABLgAECgUJBwANAAAAAA==.',
Hi='Hightide:BAABLgAECn8XAAIVAAcJ0BZjQABoAQAVAAcJ0BZjQABoAQAAAA==.Himmël:BAAALgAECgkJBQAAAA==.Hipocratic:BAAALgAECgcJEAAAAA==.Hippodot:BAABLgAECn8XAAIVAAkJzxEJHgD8AQAVAAkJzxEJHgD8AQAAAA==.',
Ho='Hodordk:BAAALgAECgEJAQABLgAFFAIJAgANAAAAAA==.Hodorr:BAABLgAECn8gAAMaAAgJkhLAGABwAQAaAAgJaxLAGABwAQAgAAUJ6BDdKADrAAABLgAFFAIJAgANAAAAAA==.Hodr:BAAALgAFFAIJAgAAAA==.Hoghoof:BAAALgADCggJEwAAAA==.Hoja:BAAALgAFFAEJAQAAAA==.Holdor:BAAALgAECgUJBQAAAA==.Holrhyn:BAABLgAECn8bAAIcAAgJ9BgwDwD2AQAcAAgJ9BgwDwD2AQAAAA==.Holybloodboi:BAAALgAECgcJDQABLgAECgkJLAAYAFQiAA==.Holylife:BAAALgADCgMJAwAAAA==.Hozencolo:BAAALgADCgMJBAAAAA==.',
Hu='Huckleberry:BAABLgAECn8ZAAIgAAgJkApzPAAqAQAgAAgJkApzPAAqAQAAAA==.Hugegigachad:BAAALgADCgQJBAAAAA==.Hugsnkisses:BAAALgAECgEJAgAAAA==.Hukjek:BAAALgAECgQJBwAAAA==.Hungcowboy:BAAALgADCgIJAgAAAA==.',
Hy='Hydrogenbomb:BAABLgAECn8kAAMBAAgJfh13CQAOAgABAAgJJx13CQAOAgAUAAQJVBZxUQAHAQAAAA==.Hymnbral:BAAALgADCgMJBQABLgAFFAIJAgANAAAAAA==.',
Ic='Icebergx:BAAALgAECgQJBgAAAA==.',
Ig='Igriis:BAAALgADCgcJDAAAAA==.',
Im='Imcooleddown:BAABLgAECn8jAAIGAAgJPB2SGQBRAgAGAAgJPB2SGQBRAgAAAA==.Imfkinold:BAAALgAECgMJBAAAAA==.Imptricity:BAAALgADCgMJAwAAAA==.Imrickjamesb:BAAALgADCgIJAgAAAA==.',
In='Indee:BAAALgADCgYJBQABLgAECgYJBgANAAAAAA==.Indi:BAAALgADCgQJBAAAAA==.Indyd:BAAALgAECgEJAQAAAA==.Indyy:BAAALgADCgMJAwABLgAECgYJBgANAAAAAA==.',
Iz='Izunna:BAAALgAECgQJBAABLgAECgkJJQAXAGwhAA==.',
Ja='Jackbeef:BAABLgAECn8ZAAIHAAgJkxsoFADLAQAHAAgJkxsoFADLAQAAAA==.Jadedhooves:BAABLgAECn8UAAIMAAcJ5A6njABiAQAMAAcJ5A6njABiAQAAAA==.Jaigerbomb:BAAALgAECgYJBgAAAA==.Japorms:BAAALgADCgEJAgAAAA==.Jarryoak:BAAALgAECgEJAQAAAA==.Jawren:BAAALgADCgEJAQAAAA==.',
Je='Jecynth:BAAALgADCgEJAQAAAA==.Jedai:BAACLgAFFH8IAAIlAAQJoxt9CwBsAQAlAAQJoxt9CwBsAQAuAAQKfzEAAiUACQlgJuwAAHkDACUACQlgJuwAAHkDAAAA.Jerrun:BAAALgAECgMJAwAAAA==.Jerrund:BAAALgAECgIJAgAAAA==.Jerryfour:BAAALgADCgEJAQAAAA==.Jerrythree:BAAALgADCgMJAgAAAA==.Jerrytwo:BAAALgAECgYJEgAAAA==.Jetfuel:BAAALgAECgQJBAAAAA==.',
Ji='Jimjones:BAAALgAECgQJBQAAAA==.',
Jm='Jman:BAAALgAECgYJDAAAAA==.',
Jo='Johnboy:BAAALgADCgYJAgAAAA==.Jorgancrath:BAAALgAECgMJAwAAAA==.Jovallius:BAAALgADCgkJCQAAAA==.',
Ju='Judadiah:BAAALgAECgQJCQAAAA==.Juggernutz:BAAALgAECgEJAgABLgAECggJGwAHAHkWAA==.Juggernutzy:BAAALgADCgcJBwABLgAECggJGwAHAHkWAA==.Jujujalal:BAAALgAECgcJEAAAAA==.Justbeginner:BAAALgADCgcJCwAAAA==.Justlycolda:BAAALgAECgUJBQAAAA==.',
['Jà']='Jàde:BAAALgAECgQJBAAAAA==.Jàxx:BAAALgADCgkJCQABLgAECgcJEAANAAAAAA==.',
['Jù']='Jùgger:BAAALgAECgUJBQABLgAECggJGwAHAHkWAA==.',
Ka='Kagalith:BAAALgADCgIJAgAAAA==.Kagorin:BAABLgAECn8hAAIQAAgJyhDXBACgAQAQAAgJyhDXBACgAQAAAA==.Kaidios:BAACLgAFFH8GAAMZAAMJqA+DBADpAAAZAAMJqA+DBADpAAAEAAEJjgeJmwBFAAAuAAQKfyIABBkACAmwHFoGALYBAAQACAnmF61aAOIBABkACAldGloGALYBABsAAQk5BnZHACoAAAAA.Kalano:BAABLgAECn8hAAMGAAgJaBCMOwC1AQAGAAgJaBCMOwC1AQAOAAMJEgucEwCLAAAAAA==.Kalona:BAAALgADCgkJEwAAAA==.Kalrock:BAABLgAECn8bAAMVAAkJUhz7EwBBAgAVAAgJUhz7EwBBAgAWAAEJAACzXQBVAAAAAA==.Kalulu:BAAALgADCgEJAQAAAA==.Karkit:BAAALgAECgIJAgAAAA==.Karnae:BAAALgAECgQJBAAAAA==.Katchow:BAAALgAECgcJEwAAAA==.Katkot:BAACLgAFFH8FAAIMAAMJ6QPQKQCPAAAMAAMJ6QPQKQCPAAAuAAQKfxkAAgwABgllFShrABcBAAwABgllFShrABcBAAAA.Kayro:BAAALgADCgcJEgAAAA==.Kayyggoo:BAAALgAECgkJEQAAAA==.Kazlan:BAAALgADCgYJCwAAAA==.',
Ke='Kercimage:BAAALgADCgIJAgAAAA==.Kevinn:BAAALgADCgUJBAAAAA==.',
Kh='Khalana:BAAALgADCgUJCAAAAA==.Khalio:BAAALgADCgYJCwAAAA==.Khamul:BAABLgAECn8ZAAIYAAYJ8BXAKQB1AQAYAAYJ8BXAKQB1AQAAAA==.Kharigwyn:BAAALgADCgMJAgAAAA==.',
Ki='Kielovar:BAAALgADCgYJDAAAAA==.Kimchilada:BAAALgAECgQJBwAAAA==.Kithkanan:BAAALgADCgUJBQAAAA==.Kizzazz:BAAALgAECgMJAwAAAA==.',
Kk='Kkodabear:BAAALgAECgcJCwAAAA==.',
Kn='Kneeonater:BAAALgADCgkJFgAAAA==.',
Ko='Kobiter:BAAALgAECgUJDgABLgAFFAIJBQAKAC4TAA==.Kobito:BAACLgAFFH8FAAIKAAIJLhNBEwCIAAAKAAIJLhNBEwCIAAAuAAQKfygAAwoACAmKHbMJAH0CAAoACAmKHbMJAH0CAAcABgnIGZ07ALcBAAAA.Kointahti:BAAALgAECgYJCgABLgAECgEJCgANAAAAAA==.Konara:BAAALgADCgcJBgAAAA==.Koopatroopa:BAABLgAECn8cAAMgAAYJKhLXJAAEAQAgAAYJ4xDXJAAEAQAaAAYJaQtdMQDVAAAAAA==.Koup:BAABLgAECn8vAAMTAAgJgiZQAwAJAwATAAgJgiZQAwAJAwAUAAEJAAA+jgAtAAAAAA==.Koupe:BAABLgAECn8YAAMRAAcJ1RrEJACjAQARAAYJIhrEJACjAQASAAIJmBoSSgBZAAABLgAECggJLwATAIImAA==.Koups:BAAALgADCgQJBAABLgAECggJLwATAIImAA==.',
Kr='Krayzebeef:BAAALgAECgIJAgAAAA==.Krazyemist:BAAALgADCgQJBAAAAA==.Kreyash:BAAALgAECgQJCAAAAA==.Kriss:BAAALgAECgUJEgAAAA==.Kruncha:BAAALgAECgIJAgAAAA==.Krungus:BAAALgAECgIJAgAAAA==.Krystel:BAAALgADCgEJAQAAAA==.Kryxis:BAABLgAECn8eAAIPAAcJuhsCMAB3AQAPAAcJuhsCMAB3AQAAAA==.',
Ku='Kuminuras:BAAALgADCgUJBQAAAA==.Kupe:BAAALgAECgYJDQABLgAECggJLwATAIImAA==.Kuroguro:BAAALgAECgYJEAAAAA==.Kuruption:BAAALgAECgIJAgAAAA==.',
Kw='Kwikkx:BAAALgADCgcJDQAAAA==.',
Ky='Kyewanda:BAABLgAECn8mAAIRAAgJhR7ZDAB/AgARAAgJhR7ZDAB/AgAAAA==.Kyewson:BAAALgADCgMJAwABLgAECggJJgARAIUeAA==.Kyrobytez:BAAALgAECgYJDwAAAA==.Kythyra:BAAALgAECgEJAQAAAA==.',
La='Laanu:BAAALgAECgcJEgABLgAECgkJNgAhAAMgAA==.Lagginwaggin:BAAALgAECgUJBwAAAA==.Lakes:BAAALgADCgQJBAAAAA==.Lanuna:BAAALgAECgcJBAAAAA==.Laowan:BAAALgAECgMJAwAAAA==.Lasagnatoo:BAAALgAECgMJBQABLgAECgkJMwAbALQaAA==.Lastlight:BAAALgAECgIJAgAAAA==.Lathara:BAAALgAECgYJCAAAAA==.Lavs:BAABLgAECn8mAAImAAkJ/R04AQDhAgAmAAkJ/R04AQDhAgAAAA==.',
Ld='Ldybramble:BAAALgADCgIJAgABLgADCggJDgANAAAAAA==.',
Le='Leahabah:BAAALgAECgEJAQAAAA==.Legendweaver:BAAALgAECgEJAQABLgAECgcJHwAGAHsMAA==.Lein:BAAALgAFFAEJAQAAAA==.Lenix:BAAALgADCgYJDgAAAA==.',
Li='Limper:BAAALgAECgkJCAAAAA==.Lineman:BAAALgADCgUJBQAAAA==.Lionalone:BAAALgAECgYJCQAAAA==.Livallan:BAABLgAECn8eAAMiAAgJ1Al9EwAOAQAiAAgJawl9EwAOAQAMAAEJ5QfuTAEuAAAAAA==.',
Lm='Lman:BAAALgAECgMJBQAAAA==.',
Lo='Loamathor:BAAALgADCgkJKgAAAA==.Lobaxv:BAABLgAECn8WAAIlAAUJZxgzJgBYAQAlAAUJZxgzJgBYAQAAAA==.Lokidoki:BAAALgAECgMJAwAAAA==.Lolenter:BAAALgADCgcJBwAAAA==.Loli:BAAALgADCgQJAgAAAA==.Lonealpha:BAAALgAECgMJAwAAAA==.Lonesource:BAAALgAECgUJCwAAAA==.Lorilyn:BAABLgAECn8sAAIcAAkJ9xgHCQBcAgAcAAkJ9xgHCQBcAgAAAA==.Lorthag:BAAALgAECgQJEgAAAA==.Lovebuz:BAAALgAECgQJBwAAAA==.Loveles:BAAALgADCgYJCAAAAA==.Loverone:BAAALgADCgEJAQAAAA==.Loññie:BAAALgADCgEJAQAAAA==.',
Lr='Lringecord:BAAALgAECgcJCgAAAA==.',
Lu='Lu:BAAALgADCgEJAQAAAA==.Luckless:BAAALgAECggJEwAAAA==.Luckyroux:BAAALgADCgYJCQAAAA==.Lumiboba:BAAALgAFFAEJAQAAAA==.Lumilychee:BAACLgAFFH8FAAIIAAQJCRC6EAAYAQAIAAQJCRC6EAAYAQAuAAQKfyQAAggACQlyHWYFALoCAAgACQlyHWYFALoCAAAA.Lumylock:BAAALgAECgUJCgAAAA==.Lunachick:BAAALgAECgUJCQAAAA==.Lunarus:BAABLgAECn8hAAIeAAYJDhMPDQBkAQAeAAYJDhMPDQBkAQAAAA==.Lurline:BAABLgAECn8gAAIGAAgJMSAZEwCAAgAGAAgJMSAZEwCAAgAAAA==.Lurrus:BAAALgADCggJCgAAAA==.Luvergirl:BAAALgADCgMJAgAAAA==.Luvsmage:BAAALgAECgQJBgAAAA==.Luxiu:BAAALgADCgIJAgAAAA==.',
Lv='Lvladin:BAAALgAECgYJBwAAAA==.',
Ly='Lyllies:BAAALgAECgEJAQAAAA==.Lythriaa:BAAALgADCgYJBgAAAA==.',
['Lì']='Lìfe:BAABLgAECn8oAAIHAAkJLxjSCgA7AgAHAAkJLxjSCgA7AgAAAA==.',
Ma='Macloving:BAABLgAECn8XAAIJAAkJEQt9MwCLAQAJAAkJEQt9MwCLAQAAAA==.Madapipa:BAAALgADCgUJBQAAAA==.Maddiablo:BAAALgADCgUJCAAAAA==.Magicpipe:BAAALgAECgUJDAAAAA==.Magrumok:BAAALgAECgYJBwAAAA==.Magthars:BAAALgAECgMJAwAAAA==.Mahnàmahnà:BAAALgADCgYJCQAAAA==.Maká:BAABLgAECn8UAAISAAYJUAkJMgDIAAASAAYJUAkJMgDIAAAAAA==.Malorian:BAAALgAECgkJBgAAAA==.Malígn:BAAALgAECgcJEAAAAA==.Manbearpig:BAAALgAECgcJBwAAAA==.Mandysmores:BAAALgAECgUJCwABLgAFFAUJFwAGABETAA==.Marduchava:BAAALgAECgEJAQAAAA==.Marshmalow:BAAALgAECgUJCAAAAA==.',
Mc='Mclovhin:BAAALgAECgMJAwAAAA==.Mcpal:BAAALgAECgMJAwABLgAECgYJDgANAAAAAA==.Mcquade:BAAALgADCgcJBwABLgADCgkJEQANAAAAAA==.Mctigly:BAAALgAECgcJBwAAAA==.',
Me='Meals:BAABLgAECn8ZAAIHAAgJyQhYIQBiAQAHAAgJyQhYIQBiAQAAAA==.Meatchunks:BAAALgAECgcJDQAAAA==.Meetras:BAACLgAFFH8HAAIhAAIJqiEHEADWAAAhAAIJqiEHEADWAAAuAAQKfyMAAiEACQmFIL4EAEsDACEACQmFIL4EAEsDAAAA.Megadefi:BAAALgAECgUJBgAAAA==.Megagosa:BAAALgAECgUJCgAAAA==.Meganob:BAAALgADCgYJBgAAAA==.Melkiel:BAAALgADCggJCAABLgAECggJJgAKALolAA==.Mementomorie:BAAALgAECgMJAwAAAA==.Mennopaws:BAAALgADCgcJAQAAAA==.Merüem:BAAALgAECgQJBAAAAA==.Mesa:BAABLgAECn/UAAIjAAkJ9iYHAAAOBAAjAAkJ9iYHAAAOBAAAAA==.',
Mi='Miclovin:BAABLgAECn8WAAIhAAgJphH+DADSAQAhAAgJphH+DADSAQAAAA==.Microplastic:BAABLgAECn8tAAMHAAgJ5CHyBACrAgAHAAgJ5CHyBACrAgALAAIJ9A/aOQBIAAAAAA==.Midsized:BAAALgAECgMJBAAAAA==.Millerltez:BAAALgAECgkJAgAAAA==.Miniblué:BAAALgAECgMJBgAAAA==.Minimalskill:BAAALgAECgEJAgAAAA==.Minthammer:BAAALgAECgEJAgAAAA==.Mirrin:BAAALgAECgEJAQABLgAECgUJBwANAAAAAA==.Mirumahn:BAAALgAECgQJBAAAAA==.Misocursed:BAAALgAECgQJBQAAAA==.Mistie:BAAALgADCgMJBAAAAA==.',
Mk='Mkultravictm:BAAALgAECgYJDAAAAA==.',
Mo='Moadeab:BAAALgADCgkJEgAAAA==.Mogando:BAAALgADCgUJCQABLgAFFAMJBwAeAD0JAA==.Mogrodeath:BAAALgAECgEJAgAAAA==.Mogrodem:BAAALgAECgEJAgAAAA==.Mogrodruid:BAAALgAECgEJAgABLgAECgcJEgANAAAAAA==.Mogrogarg:BAAALgAECgcJEgAAAA==.Mogrohunt:BAAALgAECgEJAgAAAA==.Mogromage:BAAALgAECgEJAgAAAA==.Mogropal:BAAALgAECgEJAgAAAA==.Mojojojò:BAAALgAECgIJBAAAAA==.Monica:BAAALgAECgMJAwAAAA==.Monkily:BAAALgAECgMJAwAAAA==.Monkydpuzzle:BAAALgAECgQJBAAAAA==.Moogicmike:BAAALgADCgUJBQAAAA==.Moonflower:BAAALgADCggJDgAAAA==.Moonwulf:BAAALgADCggJEgAAAA==.Moonyin:BAAALgAECgYJCgAAAA==.Moosedrool:BAAALgADCgYJBgABLgADCgcJDAANAAAAAA==.Mooster:BAAALgADCgcJBwAAAA==.Moralefist:BAAALgAECgYJBgAAAA==.Mordin:BAAALgAECgEJAQAAAA==.Morenthia:BAAALgAECgYJEQAAAA==.Morgaliice:BAABLgAECn8VAAInAAgJng4yFgA2AQAnAAgJng4yFgA2AQAAAA==.Morganasz:BAAALgADCgUJBQABLgAECgkJJgAPAGQZAA==.Mornafah:BAABLgAECn8lAAIXAAkJbCHfAQD1AgAXAAkJbCHfAQD1AgAAAA==.Mornna:BAAALgAECgMJAwABLgAECgkJJQAXAGwhAA==.Morrickk:BAAALgADCgUJBQAAAA==.Morriffic:BAAALgADCgYJDgABLgAECggJIQARAIwgAA==.Mortarion:BAAALgADCgEJAQAAAA==.Mortigen:BAAALgAECgMJAwAAAA==.Mousethyr:BAAALgAFFAEJAQAAAA==.',
Mu='Munric:BAABLgAECn8jAAIMAAgJpxmbOQA9AgAMAAgJpxmbOQA9AgAAAA==.Murasame:BAAALgAECgEJAQABLgAECggJGwAHAMYVAA==.Murlow:BAAALgADCgQJBQAAAA==.Musun:BAAALgADCgcJBwAAAA==.Muteddruid:BAAALgAECgMJAwAAAA==.Mutedfury:BAAALgAECgYJBgAAAA==.Mutelock:BAAALgAECgEJAQAAAA==.',
My='Myaxe:BAAALgAECgYJBgAAAA==.Myboycleetus:BAAALgAECgYJEAABLgADCgYJCQANAAAAAA==.Mykerz:BAABLgAECn8UAAIYAAgJTBYeFgACAgAYAAgJTBYeFgACAgAAAA==.Mynon:BAAALgADCgMJAwAAAA==.Mysaeris:BAAALgADCgcJBwAAAA==.Mystie:BAAALgAECgUJBQAAAA==.Myw:BAACLgAFFH8bAAIYAAYJnBiWBQC8AQAYAAYJnBiWBQC8AQAuAAQKfy0AAhgACQljI0UDAEYDABgACQljI0UDAEYDAAAA.',
['Mí']='Míles:BAAALgAECgYJDgAAAA==.',
['Mó']='Mórningstar:BAAALgAECgYJCAAAAA==.',
Na='Nachomama:BAAALgAECgQJBgAAAA==.Nachothings:BAACLgAFFH8TAAIPAAUJqRu5FwBLAQAPAAUJqRu5FwBLAQAuAAQKfx0AAw8ACAk/H2MbAK4CAA8ACAk/H2MbAK4CACcAAgmBFhJbAHUAAAAA.Nakedindee:BAAALgAECgYJBgAAAA==.Nakedindy:BAAALgADCgcJAwABLgAECgYJBgANAAAAAA==.Nakedlizard:BAAALgAECgQJBAAAAA==.Nashonkle:BAAALgADCgEJAQAAAA==.Naughtiie:BAAALgAECgMJAwABLgAECgkJJwAcADAVAA==.Navarth:BAAALgADCgYJDAAAAA==.',
Nb='Nbayoungboy:BAAALgADCgUJBQAAAA==.',
Ne='Nearlydeath:BAABLgAECn8ZAAMEAAcJbBy9KgDRAQAEAAcJ0hi9KgDRAQAbAAMJpxYLKQCDAAAAAA==.Nedria:BAAALgADCgcJDAAAAA==.Nedwar:BAAALgAECgYJEgAAAA==.Nenghis:BAAALgAECgYJDwAAAA==.Neur:BAAALgADCgMJAwABLgAECgYJHAAMAHwWAA==.Nevän:BAAALgADCgcJBwAAAA==.Nezha:BAAALgAFFAIJAgABLgAFFAMJBQAVALMjAA==.',
Ni='Nickelos:BAAALgADCgcJCQAAAA==.Nicksmonk:BAAALgADCgMJAwAAAA==.Nightmist:BAAALgAECgQJBAAAAA==.Nigius:BAAALgADCgMJAwAAAA==.Nihility:BAACLgAFFH8FAAIVAAMJsyPDIQAxAQAVAAMJsyPDIQAxAQAuAAQKfx8AAhUABwmlJFcRAPACABUABwmlJFcRAPACAAAA.Nirgand:BAAALgAECgYJCwABLgAFFAMJBwAeAD0JAA==.Nixxie:BAAALgAECgIJAgAAAA==.',
No='Nochoice:BAAALgADCgEJAQAAAA==.Noodlebark:BAAALgAECgEJAQAAAA==.Noodlestang:BAAALgAECgcJEgAAAA==.Nool:BAAALgAECgUJCwAAAA==.Nophel:BAAALgADCggJGQAAAA==.Noraelin:BAAALgADCgYJBwAAAA==.Norgand:BAACLgAFFH8HAAIeAAMJPQlOAgDZAAAeAAMJPQlOAgDZAAAuAAQKfyEAAx4ACAnzHFADAGoCAB4ACAnzHFADAGoCABYAAQkAALlrADwAAAAA.Nornar:BAABLgAECn8VAAIBAAYJiRe+FwBPAQABAAYJiRe+FwBPAQAAAA==.Norsehammer:BAAALgADCgcJBwAAAA==.Nosleep:BAACLgAFFH8NAAIKAAQJZgY8DQDhAAAKAAQJZgY8DQDhAAAuAAQKfxsAAgoACAm4DnYgADwBAAoACAm4DnYgADwBAAAA.Nosleepe:BAAALgADCgEJAQAAAA==.Nosleepo:BAAALgAECgcJDgAAAA==.',
Nu='Nubetoob:BAAALgADCgcJBwAAAA==.Nuiria:BAAALgAECgYJBgAAAA==.',
Ny='Nydeath:BAAALgAECgIJBAAAAA==.Nyduss:BAAALgAECgcJCgAAAA==.Nyxpal:BAAALgADCgEJAQAAAQ==.',
['Nù']='Nùtter:BAABLgAECn8bAAIHAAgJeRYTMwDfAQAHAAgJeRYTMwDfAQAAAA==.',
Oa='Oath:BAAALgADCggJCAAAAA==.',
Ob='Obrlord:BAABLgAECn8UAAIWAAYJuwwvDgDvAAAWAAYJuwwvDgDvAAAAAA==.Obvy:BAABLgAECn8eAAIhAAgJxBvUCgDzAQAhAAgJxBvUCgDzAQAAAA==.',
Of='Offeiriad:BAAALgAECgIJAgAAAA==.',
Om='Omaboa:BAABLgAECn8aAAIJAAgJpCGmBQCTAgAJAAgJpCGmBQCTAgAAAA==.',
On='Onrai:BAAALgADCgEJAQAAAA==.Onî:BAAALgADCgEJAQAAAA==.',
Oo='Oof:BAABLgAECn8hAAMFAAkJsBIBDAAFAgAFAAkJsBIBDAAFAgAcAAIJ6gZAgwAuAAAAAA==.',
Op='Ophinal:BAAALgADCgcJDAAAAA==.Optimize:BAABLgAECn8ZAAIGAAcJsx1KdgDlAQAGAAcJsx1KdgDlAQAAAA==.',
Or='Orangepeel:BAAALgAECgkJCQAAAA==.Orastal:BAAALgAECgQJCwABLgAECgcJDwANAAAAAA==.Ordinia:BAAALgAECgYJCwAAAA==.Oroki:BAAALgAECgcJBwAAAA==.',
Os='Ossian:BAAALgADCgUJBwAAAA==.',
Pa='Pandadander:BAAALgADCgYJCQAAAA==.Pandalo:BAAALgADCgYJCgAAAA==.Papipa:BAABLgAECn8lAAQdAAcJCieJCAC0AgAdAAcJCieJCAC0AgAcAAYJfCQKEQBbAgAFAAEJPiYyWABcAAAAAA==.',
Pe='Pebbles:BAAALgAECgMJAwABLgAECgcJIAABAOcNAA==.Pelarn:BAAALgADCgYJCwAAAA==.Pelviscrushy:BAAALgADCgEJAQAAAA==.Pengwei:BAECLgAFFH8JAAIgAAMJFhocDAAVAQAgAAMJFhocDAAVAQAuAAQKfykAAiAACQkAIbQCAOMCACAACQkAIbQCAOMCAAAA.Penumbrix:BAAALgAECgEJAQAAAA==.Pepperbreath:BAABLgAECn8bAAIjAAgJeQ2AGgC3AQAjAAgJeQ2AGgC3AQAAAA==.Perfectstorm:BAAALgAECgYJDwAAAA==.Persefo:BAAALgAECgYJDgAAAA==.Petmeimtame:BAAALgAECgQJAwAAAA==.',
Ph='Phadenstar:BAAALgAECgYJCgAAAA==.',
Pi='Pickleburnz:BAAALgADCgQJBAAAAA==.Pinefresh:BAAALgAECgQJBQAAAA==.Pinkpwnage:BAAALgAFFAEJAQAAAA==.Pinpoint:BAAALgADCgEJAQABLgAECggJGwAHAHkWAA==.',
Pm='Pmmeurdog:BAAALgADCgYJBgAAAA==.',
Po='Pocketsmonk:BAABLgAECn8VAAQIAAcJbxPCIAA/AQAIAAcJbxPCIAA/AQAaAAMJxxPoYAC+AAAgAAMJghVTSgBaAAAAAA==.Podnuh:BAAALgAECgEJAQAAAA==.Pokemcjoke:BAAALgAECgIJAgAAAA==.Ponchoe:BAAALgADCgcJDgAAAA==.Poobahdrag:BAACLgAFFH8LAAIjAAQJJBz9CQB5AQAjAAQJJBz9CQB5AQAuAAQKfyQAAyMACQkPHFMKAJECACMACQkPHFMKAJECABAABAn2EuoqAMYAAAAA.Pools:BAAALgAECgIJAgAAAA==.Popnosmoke:BAABLgAECn8WAAIHAAYJOhCPLQAZAQAHAAYJOhCPLQAZAQAAAA==.Popster:BAAALgADCggJCQAAAA==.Porzok:BAABLgAECn8tAAIBAAkJ3x/hAQDmAgABAAkJ3x/hAQDmAgAAAA==.Poxxel:BAAALgADCgMJAwABLgAECggJLAAMAOsiAA==.',
Pr='Prell:BAAALgAECgQJBwAAAA==.Privet:BAAALgAECgUJBQABLgAECggJEAANAAAAAA==.Prosperine:BAAALgAECgIJAgAAAA==.Prozakaoa:BAAALgADCgIJAgAAAA==.',
Pu='Puhd:BAAALgAECgEJAQAAAA==.Punchimon:BAAALgADCgYJBgAAAA==.Putraa:BAAALgADCgYJBgAAAA==.Putridstrike:BAAALgAECgcJEAAAAA==.',
Py='Pyromagus:BAAALgAECgEJAgAAAA==.Pyrra:BAAALgADCgcJDgAAAA==.',
['Pü']='Pürple:BAAALgAECgYJEgAAAA==.',
Qt='Qtiy:BAABLgAECn8mAAIVAAkJ+yMmAwAiAwAVAAkJ+yMmAwAiAwAAAA==.Qty:BAAALgADCgIJAQABLgAECgkJJgAVAPsjAA==.Qtylol:BAAALgAECgcJBwABLgAECgkJJgAVAPsjAA==.',
Qu='Queeg:BAAALgADCgEJAgAAAA==.Quickben:BAAALgAECgQJBAAAAA==.Quintalen:BAAALgAECgYJDQAAAA==.',
Ra='Raaken:BAAALgADCggJCAAAAA==.Raawwrr:BAAALgADCgcJBwAAAA==.Racken:BAABLgAECn8bAAQbAAgJYx/0BABiAgAbAAgJYx/0BABiAgAZAAQJGgpwDQDWAAAEAAIJBwKTFQFKAAAAAA==.Raedona:BAAALgADCgQJBAAAAA==.Ragon:BAAALgADCgEJAQAAAA==.Raharn:BAAALgAECgUJCgAAAA==.Raincheckplz:BAAALgADCgIJAgAAAA==.Ranzor:BAABLgAECn8XAAIKAAgJYBV3EAABAgAKAAgJYBV3EAABAgAAAA==.Rauden:BAAALgADCgMJBAAAAA==.Raveyn:BAABLgAECn8hAAMcAAgJSB5QBQCwAgAcAAgJSB5QBQCwAgAFAAYJjBsvGgBqAQAAAA==.',
Re='Reacted:BAAALgADCgQJBAABLgAECggJIQANAAAAAQ==.Rebecca:BAABLgAECn8bAAIhAAgJCSOEAwCiAgAhAAgJCSOEAwCiAgAAAA==.Redmaine:BAAALgADCgEJAQAAAA==.Reef:BAABLgAECn8aAAIPAAgJ3CMPEAD+AgAPAAgJ3CMPEAD+AgAAAA==.Rekieuwu:BAAALgAECgcJEQAAAA==.Releaf:BAAALgAECgMJAwAAAA==.Remarista:BAAALgADCgYJCAAAAA==.Remixed:BAAALgADCgMJAwABLgAECggJDQANAAAAAA==.Repentance:BAAALgAECgQJAwAAAA==.Retnuh:BAABLgAECn8gAAMTAAgJOx0rFQAmAgATAAgJOx0rFQAmAgABAAIJYRHHLgCDAAAAAA==.Revivified:BAAALgAECgQJBAAAAA==.',
Rh='Rheiner:BAAALgAECgEJAQAAAA==.Rhynpi:BAAALgADCgIJAgAAAA==.Rhynsen:BAAALgADCgYJBgAAAA==.',
Ri='Ribez:BAAALgAFFAEJAQAAAA==.Ricoxx:BAAALgAECgEJBQAAAA==.Rieki:BAAALgAECggJCAAAAA==.Riftseeker:BAAALgAECgYJEQAAAA==.Rikori:BAAALgAECgYJCwAAAA==.Rimmjab:BAAALgAECgEJAQAAAA==.Rinzz:BAAALgADCgcJDQABLgAECgMJCAANAAAAAA==.Rinzzler:BAAALgADCgEJAQAAAA==.Ristin:BAAALgADCgEJAQAAAA==.',
Ro='Roderika:BAAALgADCgUJBQABLgAFFAQJDAADAMMTAA==.Rogald:BAAALgAECgMJBQAAAA==.Roids:BAAALgADCgYJEAAAAA==.Rolockrad:BAAALgAECgYJCgAAAA==.Roradonria:BAAALgAECgEJAgAAAA==.Rord:BAABLgAECn8sAAMMAAgJ6yKrCwAwAwAMAAgJ6yKrCwAwAwAlAAgJQCAKDwCdAgAAAA==.Rorloc:BAAALgADCgIJAgAAAA==.Rosalei:BAAALgADCgMJAwAAAA==.Rownin:BAAALgADCgEJAgAAAA==.Royaljalopen:BAAALgAECgIJAQAAAA==.Royjacked:BAAALgAECgIJAgAAAA==.',
Ru='Ruinaria:BAAALgADCgMJAwAAAA==.Rumblepak:BAAALgADCgcJDwAAAA==.Rumblez:BAAALgADCgEJAQAAAA==.Runicstrike:BAABLgAECn84AAMEAAkJHia+BACHAwAEAAkJHia+BACHAwAbAAMJnR9UIADBAAAAAA==.Ruthlesreign:BAAALgAECgMJAwAAAA==.',
Rz='Rzarazor:BAABLgAECn8hAAIGAAgJXwkhYABSAQAGAAgJXwkhYABSAQAAAA==.',
Sa='Sadeye:BAAALgAECgYJCAAAAA==.Saeword:BAAALgADCgYJCgAAAA==.Saladdressin:BAAALgADCgcJBwABLgAECgUJBwANAAAAAA==.Salvation:BAAALgADCgYJBgAAAA==.Samborn:BAAALgADCgEJAQAAAA==.Sanctustrike:BAAALgAECgYJCwAAAA==.Sandero:BAABLgAECn8ZAAIMAAgJmQpvTwBYAQAMAAgJmQpvTwBYAQAAAA==.Saraphina:BAABLgAECn8fAAMGAAcJewwmdQAnAQAGAAcJvwsmdQAnAQAOAAMJBhFwEQCsAAAAAA==.Sathrell:BAAALgADCgUJBQAAAA==.Savageborn:BAAALgADCgIJAgAAAA==.Savagetime:BAABLgAECn8hAAIGAAcJ3hpIMgDXAQAGAAcJ3hpIMgDXAQAAAA==.',
Sc='Scarletwitçh:BAAALgADCgIJAgABLgAECggJJgAPAE4jAA==.Schnooks:BAAALgAECgEJAgABLgAECgcJDgANAAAAAA==.Scyythe:BAAALgADCgEJAQAAAA==.',
Se='Sedor:BAAALgADCgEJAQAAAA==.Sellandre:BAAALgAECgIJBQAAAA==.Selvalamhi:BAAALgADCgcJDgABLgAFFAMJBwAeAD0JAA==.Semi:BAABLgAECn8oAAITAAgJdxJuIwDJAQATAAgJdxJuIwDJAQAAAA==.Sensenah:BAAALgADCgUJEgAAAA==.Serenitie:BAAALgADCgcJDAAAAA==.Serpompom:BAAALgAECgYJCgAAAA==.',
Sh='Shadowbugger:BAAALgADCgcJBwAAAA==.Shadowknigh:BAAALgAECgMJAwAAAA==.Shalirah:BAAALgAECgYJCwABLgAECgcJFgAEALgSAA==.Sharaudra:BAAALgADCgMJAwABLgAECggJLAAMAOsiAA==.Shardy:BAAALgADCgUJBQABLgAECgUJBwANAAAAAA==.Shengal:BAABLgAECn8rAAMIAAgJ1A5tGgB5AQAIAAgJ1A5tGgB5AQAgAAEJQQF3jgASAAAAAA==.Sherfight:BAABLgAECn8nAAMcAAkJMBVGHwDmAQAcAAkJMBVGHwDmAQAFAAYJMxm5HABWAQAAAA==.Shiftyzegg:BAAALgAECgEJAQAAAA==.Shipp:BAAALgAECgMJBAAAAA==.Shmakk:BAAALgADCgYJCQAAAA==.Shmebulon:BAAALgADCgEJAQAAAA==.Shopkeep:BAAALgADCgEJAQAAAA==.Shund:BAAALgADCgQJBQABLgAECgQJBAANAAAAAA==.Shunkd:BAAALgAECgQJBAAAAA==.Shyjinx:BAAALgADCgEJAQAAAA==.Shyvala:BAAALgAECgcJEgAAAA==.',
Si='Sig:BAAALgADCgEJAQAAAA==.Silithaine:BAAALgAECgUJBgAAAA==.Silvarogue:BAAALgAECgYJCQAAAA==.',
Sk='Skargrub:BAAALgAECgEJAQAAAA==.Skinwalk:BAAALgAECgQJBAAAAA==.',
Sl='Slackerftw:BAAALgAECgQJCQAAAA==.Slamhog:BAABLgAECn8mAAIEAAgJixxqGAA5AgAEAAgJixxqGAA5AgAAAA==.Slayaa:BAAALgAECgIJAwAAAA==.Sleazo:BAAALgADCgUJBQAAAA==.Sleew:BAABLgAECn8sAAMVAAkJ1xymCgCgAgAVAAgJ1xymCgCgAgAWAAcJKRULEQDFAQAAAA==.Slippydippy:BAAALgAECgMJAwAAAA==.Slobbin:BAAALgADCgUJBQAAAA==.Sloppydrag:BAAALgAECgQJBQAAAA==.',
Sm='Smacku:BAAALgADCggJDgAAAA==.Smaugly:BAAALgAECgcJEwAAAA==.Smaugumz:BAAALgAECgcJDgAAAA==.Smokebae:BAAALgADCgEJAQAAAA==.Smorz:BAAALgADCgMJAwAAAA==.',
Sn='Snackalot:BAAALgADCgcJCAAAAA==.Snocaps:BAAALgAECgEJAQAAAA==.Snowblade:BAAALgAECgYJCwAAAA==.',
So='Soggypringle:BAAALgADCgIJAgAAAA==.Solan:BAAALgAECgEJAQABLgAECgEJAQANAAAAAA==.Soleilroi:BAAALgAECgQJCQAAAA==.Soletaken:BAAALgAECgEJAwAAAA==.Solson:BAAALgADCgUJBQAAAA==.',
Sp='Specsdraco:BAABLgAECn8iAAIUAAkJKCG/AQCMAgAUAAkJKCG/AQCMAgAAAA==.Spewpuke:BAACLgAFFH8GAAMHAAQJnA4cFQAHAQAHAAQJSAUcFQAHAQAKAAIJdxeTEgCSAAAuAAQKfzQAAwoACAkMHbIHAAUCAAoACAkMHbIHAAUCAAsAAQmwEH08ADUAAAAA.Spinlock:BAAALgAECgEJAQAAAA==.',
St='Staci:BAABLgAECn8nAAIHAAgJXBhgEADyAQAHAAgJXBhgEADyAQAAAA==.Starfree:BAACLgAFFH8GAAIcAAIJnQxkGAB+AAAcAAIJnQxkGAB+AAAuAAQKfxsABBwACAnmDiQiADgBAB0ABwlACbYqAEQBABwABglaESQiADgBAAUAAgkuBwNaAFEAAAAA.Steelhoof:BAAALgAECgUJCQAAAA==.Steelsham:BAABLgAECn8aAAMJAAgJjwdkJwAhAQAJAAgJjwdkJwAhAQAYAAYJuwsiWgAgAQAAAA==.Stgermain:BAACLgAFFH8GAAIdAAMJzRYeFgAAAQAdAAMJzRYeFgAAAQAuAAQKfysABB0ACQknHfwFAJsCAB0ACQknHfwFAJsCABwABgluFmYyAHYBAAUAAQkAAIFfAAAAAAAA.Stinkybinks:BAAALgADCgYJBgAAAA==.Stonedmaster:BAAALgAECgUJCwAAAA==.Strickdic:BAAALgADCgcJCQAAAA==.Striikes:BAAALgADCgQJBQABLgAECgQJAwANAAAAAA==.Strikeanywer:BAAALgAECgEJAQAAAA==.Stuard:BAAALgAECgQJDQAAAA==.Stuardh:BAAALgAECgIJAQAAAA==.',
Su='Superstoned:BAAALgADCgcJEAAAAA==.Surudruid:BAAALgAECgQJAwAAAA==.',
Sw='Swampy:BAAALgADCgYJBgAAAA==.Swolbõi:BAAALgAECgYJEgAAAA==.',
Sy='Sykes:BAABLgAFFH8JAAIgAAQJCBgWBgBeAQAgAAQJCBgWBgBeAQAAAA==.Sylrana:BAACLgAFFH8IAAMRAAMJTA0qJgC7AAARAAMJTA0qJgC7AAAfAAEJ1QLNDwAiAAAuAAQKfxoAAhEACAnOGAlCAJkBABEACAnOGAlCAJkBAAAA.Sylvaelrodas:BAAALgADCggJCAAAAA==.Sylvarion:BAAALgADCgUJBQAAAA==.Sylvie:BAAALgADCgcJDAABLgAECgQJBQANAAAAAA==.Sylzyrus:BAABLgAECn8iAAIjAAgJthroBQAwAgAjAAgJthroBQAwAgAAAA==.Syrelanas:BAAALgADCgcJBwAAAA==.',
Ta='Tabitha:BAAALgADCgEJAQAAAA==.Tabuta:BAABLgAECn8XAAIJAAgJYw1+IABLAQAJAAgJYw1+IABLAQAAAA==.Taktikil:BAAALgADCgkJFgAAAA==.Taktikyl:BAAALgADCgcJDQABLgADCgkJFgANAAAAAA==.Talizar:BAAALgADCgIJAwAAAA==.Talonfire:BAAALgADCgUJBQAAAA==.Talor:BAAALgADCgYJCAAAAA==.Talrad:BAAALgAECgcJDgAAAA==.Tarrot:BAAALgADCgIJAgAAAA==.Tauralyon:BAABLgAECn8hAAIlAAgJqx8VDgA3AgAlAAgJqx8VDgA3AgAAAA==.Tazerxface:BAAALgAECgUJBgAAAA==.Tazomfg:BAAALgADCgEJAgAAAA==.',
Te='Tealgos:BAAALgAECgcJBwAAAA==.Teenyhands:BAAALgAECgYJDQAAAA==.Telarae:BAABLgAECn8cAAIMAAgJMxrNVADjAQAMAAgJMxrNVADjAQAAAA==.Teldrasa:BAACLgAFFH8GAAIRAAIJQxLsGQCVAAARAAIJQxLsGQCVAAAuAAQKfyQAAxEACAntGh0mACACABEACAntGh0mACACACYABgk7E7cYADgBAAAA.Tellera:BAAALgAECgQJBQAAAA==.Tempér:BAAALgADCgUJCgABLgAECgcJEAANAAAAAA==.Tereshi:BAAALgAECgEJAQABLgAECgYJCAANAAAAAA==.Teugelsi:BAAALgADCgEJAQAAAA==.Teukard:BAAALgADCgIJAwAAAA==.',
Th='Thebeefchief:BAAALgAECggJCAABLgAFFAYJGAAbAAIeAA==.Thebigmon:BAABLgAECn8mAAIJAAcJHRx5DwDrAQAJAAcJHRx5DwDrAQAAAA==.Thedabara:BAAALgAECgMJAwAAAA==.Thegriddler:BAAALgAECgEJAQAAAA==.Thermocline:BAAALgAECgUJBQABLgAECggJGwALAPEYAA==.Thesolartaco:BAAALgADCgYJCAAAAA==.Thewhite:BAABLgAECn8ZAAIRAAgJsRJnKgCBAQARAAgJsRJnKgCBAQAAAA==.Thiccjinbei:BAAALgAECgMJBgAAAA==.Thingamabob:BAAALgAECgMJBgAAAA==.Thoradyn:BAAALgAECgIJAgAAAA==.Thordriel:BAAALgAECgYJDgAAAA==.Threna:BAAALgADCgcJBwAAAA==.Thrisper:BAABLgAECn8gAAIRAAgJFQcmPwAXAQARAAgJFQcmPwAXAQAAAA==.Thrudheals:BAAALgAECgQJCAAAAA==.',
Ti='Tickeld:BAAALgAECgQJCQAAAA==.Tintaglia:BAAALgADCgEJAQAAAA==.Tinytina:BAABLgAFFH8JAAIgAAQJYQ1QCgArAQAgAAQJYQ1QCgArAQAAAA==.',
To='Tocino:BAAALgADCgMJAwAAAA==.Tofrenm:BAAALgAECggJDgAAAA==.Togashi:BAAALgADCgcJBwAAAA==.Tombomb:BAABLgAECn8YAAIaAAgJPRGeEwCiAQAaAAgJPRGeEwCiAQAAAA==.Tomspoojer:BAAALgAECgEJAQAAAA==.Topnacho:BAAALgAECgYJEAABLgAFFAUJEwAPAKkbAA==.Torgrim:BAAALgAECgIJAgAAAA==.',
Tr='Traitor:BAAALgADCgcJCQAAAA==.Traumatik:BAABLgAECn8kAAIEAAkJ6BduFABXAgAEAAkJ6BduFABXAgAAAA==.Treebird:BAAALgADCgkJCQAAAA==.Treespirit:BAAALgAECggJCQAAAA==.Trekin:BAAALgAECgIJAgAAAA==.Trigospread:BAAALgADCgUJBQABLgAECgQJBQANAAAAAA==.Trikkon:BAAALgADCgcJBwABLgAECgIJAgANAAAAAA==.Tripallie:BAAALgADCgYJCgAAAA==.Trisperth:BAAALgADCgQJBgAAAA==.Trocity:BAAALgAECgIJBQAAAA==.Trollyjoebo:BAAALgADCgEJAQAAAA==.Trudeathh:BAACLgAFFH8GAAIbAAMJTBH1EwC6AAAbAAMJTBH1EwC6AAAuAAQKfxQAAxsABgliI1YQAAUCABsABgliI1YQAAUCABkABAn2CuUOALMAAAAA.',
Tu='Turbosins:BAAALgAECgIJAgAAAA==.',
Tw='Twestside:BAAALgAECgMJAgAAAA==.',
Ty='Tylenolbaby:BAAALgADCgcJDQABLgAECgcJGgAKAPwhAA==.Typhoone:BAAALgAFFAEJAQAAAA==.Tyranbae:BAAALgAECgYJCgABLgAFFAQJCwAjACQcAA==.Tyrur:BAAALgAECgYJDQAAAA==.Tytherion:BAAALgAECgEJAQAAAA==.',
['Tö']='Tönesies:BAAALgAECgMJAwAAAA==.',
Ug='Ugbukk:BAAALgADCgcJBwAAAA==.Uglyashell:BAAALgADCgkJFwAAAA==.',
Um='Umbriel:BAAALgAECgEJAQAAAA==.Umbrielagosa:BAACLgAFFH8PAAIjAAQJghtgCwBfAQAjAAQJghtgCwBfAQAuAAQKfx4AAiMACAkrHvUHALwCACMACAkrHvUHALwCAAAA.',
Un='Unclefingiez:BAAALgADCgEJAQAAAA==.Unknownhealz:BAAALgADCgcJBgAAAA==.',
Ur='Urknee:BAAALgADCgYJCgABLgAECgkJGQAkAIAQAA==.Urotherdaddy:BAAALgAECgYJEQAAAA==.',
Va='Vaelith:BAACLgAFFH8JAAIGAAQJBxCuMQBFAQAGAAQJBxCuMQBFAQAuAAQKfyEAAgYACAn3Hr4XAF0CAAYACAn3Hr4XAF0CAAAA.Vaethys:BAAALgADCgUJCAAAAA==.Valaxia:BAAALgADCgEJAgAAAA==.Valerikka:BAAALgAECgEJAQAAAA==.Valkaire:BAAALgAECgEJAQAAAA==.Valnyx:BAAALgADCgEJAQAAAA==.Valsorin:BAAALgAECgUJDwAAAA==.Valtaea:BAACLgAFFH8IAAIGAAMJiATYUwDOAAAGAAMJiATYUwDOAAAuAAQKfx0AAgYACAkIFwJaACsCAAYACAkIFwJaACsCAAAA.Valwhoard:BAAALgADCgcJCAAAAA==.Vampiroth:BAAALgAECgMJAwAAAA==.Vampiz:BAAALgADCgMJAwAAAA==.Vanille:BAAALgADCgEJAQAAAA==.Varyndra:BAAALgAECgEJAQAAAA==.',
Ve='Veks:BAAALgAECgEJAgAAAA==.Velour:BAABLgAECn8UAAMdAAgJ5hcHHgCkAQAdAAcJzxcHHgCkAQAFAAEJ1wsMUQA2AAABLgAECgUJCgANAAAAAA==.Velzhara:BAAALgADCgMJAwAAAA==.',
Vi='Vigilus:BAAALgAECgQJCAAAAA==.Vividdevour:BAAALgADCgMJAwAAAA==.Vixol:BAABLgAECn8YAAIGAAgJ4h09KgD5AQAGAAgJ4h09KgD5AQAAAA==.',
Vo='Voidheals:BAAALgAECgYJDgAAAA==.Voids:BAAALgADCgEJAgAAAA==.Volairne:BAAALgAECgMJCAAAAA==.',
Wa='Waarsêer:BAAALgAECggJCwAAAA==.Wackah:BAACLgAFFH8GAAMVAAQJkgnhMQAHAQAVAAQJKQjhMQAHAQAWAAIJBwyhDQCgAAAuAAQKfyQAAxYACQl/Hb0CANcCABYACQl/Hb0CANcCABUAAgnAEe+bAIYAAAAA.Wafflxs:BAACLgAFFH8KAAIIAAQJrBuxCgBwAQAIAAQJrBuxCgBwAQAuAAQKfx0AAwgACAnhJNgDADYDAAgACAnhJNgDADYDACAAAQnbH1BJAF0AAAAA.Waldo:BAAALgAECgQJBAAAAA==.Wanpisu:BAABLgAECn8UAAIMAAgJixADagCrAQAMAAgJixADagCrAQAAAA==.Wardaddy:BAAALgAECgUJDgAAAA==.Wardorable:BAAALgADCgMJAwAAAA==.Warmage:BAAALgADCgIJAgAAAA==.Wartirus:BAABLgAECn8eAAIVAAkJaxyoDwBqAgAVAAkJaxyoDwBqAgAAAA==.',
We='Weepingtiger:BAAALgAECgcJAQAAAA==.Weezing:BAAALgAECgEJAgAAAA==.Wellfookthat:BAAALgAECgUJEwAAAA==.Weolf:BAAALgAECgYJEQAAAA==.',
Wh='Wheelchair:BAAALgAECgQJDAABLgAFFAMJAwANAAAAAA==.Whyfeedzwhy:BAAALgAECgEJAQAAAA==.Whyvala:BAABLgAECn8UAAIGAAYJCgL2tACpAAAGAAYJCgL2tACpAAABLgADCgEJAQANAAAAAA==.Whyvara:BAAALgADCgEJAQAAAA==.',
Wi='Wiisp:BAAALgADCgcJCwAAAA==.Wilmadikfit:BAAALgAECgMJAwAAAA==.Winterfresh:BAAALgAECgMJAwAAAA==.Wintersidemo:BAABLgAECn8hAAIVAAkJdRapFQA1AgAVAAkJdRapFQA1AgAAAA==.',
Wo='Wolnney:BAABLgAECn8cAAIMAAYJQCMcJgDpAQAMAAYJQCMcJgDpAQAAAA==.',
Wr='Wraithian:BAAALgAECgUJBQAAAA==.',
Wy='Wylar:BAABLgAECn8XAAIEAAcJoRREbwCqAQAEAAcJoRREbwCqAQAAAA==.',
Xa='Xalatoes:BAABLgAFFH8RAAIYAAUJYB5rBwCgAQAYAAUJYB5rBwCgAQAAAA==.',
Xe='Xeb:BAAALgADCgEJAQAAAA==.Xenar:BAAALgADCgIJAwAAAA==.Xerathor:BAABLgAECn8YAAMEAAgJTB2xFABVAgAEAAgJTB2xFABVAgAZAAEJkwy5FwAxAAAAAA==.',
Xi='Xiaoyu:BAAALgAECgYJCgAAAA==.Xim:BAAALgAECgIJAgAAAA==.',
Xr='Xraiz:BAAALgADCgIJAgAAAA==.',
Xy='Xyne:BAAALgAECgEJAgAAAA==.',
Xz='Xziled:BAAALgAECgMJBQAAAA==.',
Ya='Yakihunt:BAAALgADCgIJAgAAAA==.',
Yo='Yogonine:BAACLgAFFH8NAAIIAAQJdRjjDgAxAQAIAAQJdRjjDgAxAQAuAAQKfywAAwgACQntI0gDAEYDAAgACQntI0gDAEYDACAAAQn4BMxpACkAAAAA.Yoshie:BAAALgAECgMJCAAAAA==.',
Yu='Yunna:BAAALgADCgcJDAAAAA==.',
Yx='Yxma:BAABLgAECn8aAAIkAAYJ4gmLDwAKAQAkAAYJ4gmLDwAKAQAAAA==.',
Za='Zanetta:BAAALgAECgEJAQAAAA==.Zanydruid:BAAALgAECgUJDQAAAA==.Zanza:BAABLgAECn8VAAILAAgJLxc8CADNAQALAAgJLxc8CADNAQAAAA==.Zariana:BAAALgADCgEJAQAAAA==.',
Ze='Zedekaya:BAAALgADCgUJBQAAAA==.Zekku:BAAALgAECgQJBgAAAA==.Zeldõris:BAAALgAECgUJBwAAAA==.Zephadawn:BAAALgAECgEJAQAAAA==.',
Zh='Zhamazu:BAAALgAECgIJAgAAAA==.Zhy:BAAALgAECgYJCgAAAA==.Zhygar:BAAALgAECgUJCQAAAA==.',
Zi='Zinniah:BAAALgAECgQJBQAAAA==.Zipthud:BAAALgAECgMJCAAAAA==.',
Zo='Zodin:BAAALgADCgYJBwABLgAECgYJCwANAAAAAA==.Zombiez:BAAALgAFFAQJBAAAAA==.',
Zu='Zujoth:BAAALgADCgcJFQAAAA==.',
['Âb']='Âbaddön:BAAALgADCgUJBgAAAA==.',
['Çh']='Çhefhunter:BAAALgAECgQJAwAAAA==.Çhloe:BAAALgADCgIJAgAAAA==.',
['Çl']='Çlaire:BAAALgAECgEJAQAAAA==.',
['Ðr']='Ðrstrange:BAAALgAECgIJAgABLgAECggJJgAPAE4jAA==.',
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

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

local lookup = {'DemonHunter-Havoc','DemonHunter-Vengeance','Unknown-Unknown','Paladin-Retribution','Shaman-Restoration','Shaman-Elemental','Rogue-Outlaw','Warrior-Fury','Warrior-Arms','DemonHunter-Devourer','Warlock-Demonology','Mage-Frost','Druid-Feral','Monk-Windwalker','Hunter-Marksmanship','Priest-Holy','Monk-Brewmaster','Warlock-Destruction','Evoker-Augmentation','Monk-Mistweaver','Priest-Shadow','DeathKnight-Unholy','Druid-Guardian','Mage-Arcane','Warlock-Affliction','Evoker-Preservation','Hunter-BeastMastery','Rogue-Subtlety','Warrior-Protection','Evoker-Devastation','DeathKnight-Blood','Paladin-Protection','Shaman-Enhancement','Druid-Balance','Paladin-Holy','Rogue-Assassination','Hunter-Survival','Druid-Restoration','Priest-Discipline','Mage-Fire',}
local provider = {region='US',realm='AzjolNerub',name='US',type='weekly',zone=46,date='2026-04-24',data={Ad='Adapt:BAAALgAECgMJCQAAAA==.Addy:BAABLgAECn8WAAMBAAcJoxVRBgBUAQABAAYJUBhRBgBUAQACAAEJQgh/CwAxAAAAAA==.',
Ae='Aeonis:BAAALgAECgEJAQAAAA==.Aestian:BAAALgAECgYJEwAAAA==.',
Ag='Agamesh:BAAALgADCgUJCQAAAA==.',
Ai='Ailysely:BAAALgADCgEJAQABLgAECgEJAQADAAAAAA==.Airees:BAABLgAECn8bAAIEAAcJlh3qQQAfAgAEAAcJlh3qQQAfAgAAAA==.Aispere:BAAALgADCggJHAAAAA==.',
Al='Alastria:BAAALgADCgcJBwAAAA==.Alektra:BAAALgADCgUJBwAAAA==.Alerzhulan:BAAALgADCgcJCwAAAA==.Allanquatre:BAAALgADCgEJAQAAAA==.Alledria:BAAALgAECgcJEgAAAA==.Allenaena:BAAALgAECgMJBgAAAA==.Alorely:BAAALgAECgYJEQAAAA==.Altonas:BAAALgAECgMJAwAAAA==.',
Am='Amanara:BAAALgAECgEJAQAAAA==.Amillah:BAAALgAECgEJAQAAAA==.',
An='Anciientpaw:BAABLgAECn8eAAMFAAgJAh5sHQAvAgAFAAgJAh5sHQAvAgAGAAUJaBX/EAD/AAAAAA==.Andramalyus:BAAALgAECgYJEgAAAA==.Angbar:BAAALgAECgYJEgAAAA==.Anguirus:BAABLgAECn8XAAIGAAgJCwRcUAAFAQAGAAgJCwRcUAAFAQAAAA==.Animà:BAAALgAECgMJAwAAAA==.Ankhnstein:BAAALgAECgQJBAAAAA==.Antoine:BAAALgAECgIJAgAAAA==.',
Ap='Appynoxusrog:BAABLgAECn8cAAIHAAYJuhgsBQCcAQAHAAYJuhgsBQCcAQAAAA==.',
Aq='Aqulenas:BAAALgAECggJCgAAAA==.',
Ar='Arakhan:BAAALgAECgQJBAAAAA==.Arcadian:BAABLgAECn8aAAMIAAgJhBGfMQDmAQAIAAgJhBGfMQDmAQAJAAEJzAfLRAAvAAAAAA==.Arcadiann:BAAALgADCgMJAwAAAA==.Arcadin:BAAALgAECgEJAgAAAA==.Arextheelder:BAAALgADCgIJAgAAAA==.Aridas:BAABLgAECn8iAAMKAAgJ5RfpDgCSAQAKAAgJ5RfpDgCSAQABAAIJRQv/XwBiAAAAAA==.Arikdeath:BAAALgADCgYJBAAAAA==.Armorscales:BAACLgAFFH8GAAILAAIJ6RGlNwCkAAALAAIJ6RGlNwCkAAAuAAQKfyQAAgsACAkLIlUQAPcCAAsACAkLIlUQAPcCAAAA.Arntraz:BAAALgADCggJFQAAAA==.Arçadia:BAAALgAECgMJAwAAAA==.',
As='Ashegen:BAAALgAECgQJBAAAAA==.Ashtori:BAAALgADCgEJAgAAAA==.Astrine:BAACLgAFFH8GAAIMAAIJxxhcOwC0AAAMAAIJxxhcOwC0AAAuAAQKfyMAAgwACAktIgEiAOsCAAwACAktIgEiAOsCAAAA.',
Au='Auberon:BAABLgAECn8YAAINAAgJwRh5BgCSAgANAAgJwRh5BgCSAgAAAA==.Aufta:BAABLgAECn8WAAIOAAYJeAYfEADQAAAOAAYJeAYfEADQAAAAAA==.',
Az='Azdh:BAAALgAECgQJBgAAAA==.Azi:BAACLgAFFH8LAAIPAAQJoA8AEQAlAQAPAAQJoA8AEQAlAQAuAAQKfyEAAg8ACAnSH8wUAIkCAA8ACAnSH8wUAIkCAAAA.Azshanorel:BAAALgADCgcJBwAAAA==.Azunea:BAAALgAECgEJAQAAAA==.',
Ba='Backpedal:BAAALgAECgQJBAAAAA==.Badankhadonk:BAACLgAFFH8GAAIFAAIJ5CN7CADLAAAFAAIJ5CN7CADLAAAuAAQKfyQAAgUACAnaJVECAF8DAAUACAnaJVECAF8DAAAA.Balen:BAAALgAECgYJEwAAAA==.Bandrösh:BAAALgADCgMJAwAAAA==.',
Be='Belholy:BAAALgAECgQJCAAAAA==.Beliice:BAAALgADCgYJBgABLgAECgQJCAADAAAAAA==.Bellanei:BAAALgAECgEJAQAAAA==.Ben:BAAALgAECgEJAQAAAA==.Benafflockk:BAAALgADCggJCAAAAA==.Benefitdruid:BAAALgAECgEJAQAAAA==.Benilok:BAABLgAECn8iAAILAAgJUyMdDAAZAwALAAgJUyMdDAAZAwAAAA==.Bethgibbons:BAAALgADCgQJCQAAAA==.',
Bi='Bibimbap:BAAALgAECgEJAQAAAA==.Bigsuccubus:BAAALgAECgMJBQAAAA==.Biohazard:BAAALgADCgUJBQAAAA==.Bizël:BAAALgADCgMJAwAAAA==.',
Bl='Blackblood:BAAALgAECgYJEAAAAA==.Blackclouds:BAAALgADCgkJCQAAAA==.Blackspiral:BAAALgADCgEJAQAAAA==.Bladestriker:BAAALgADCgkJCQAAAA==.Blindside:BAAALgAECgIJAgAAAA==.Bloodache:BAAALgAECgcJEAAAAA==.Bloodkissed:BAAALgADCgUJBgABLgAECgcJGgAQAFkfAA==.Bluebuberry:BAAALgAECgQJBgAAAA==.Bluesaphire:BAAALgAECgIJAgABLgAECgYJDwADAAAAAA==.Blux:BAAALgAECgIJBAAAAA==.',
Bo='Boil:BAAALgAECgYJBgAAAA==.Bonemarrow:BAAALgAECgQJDQAAAA==.Bournx:BAAALgADCgcJBwAAAA==.Boysenbar:BAAALgADCgIJAgAAAA==.',
Br='Bradrenna:BAABLgAECn8sAAMCAAkJsBUJBgA5AgACAAkJsBUJBgA5AgAKAAEJpQGt9AAbAAAAAA==.Braké:BAAALgAECgYJEAAAAA==.Brenzull:BAAALgADCgYJCwAAAA==.Brewskies:BAABLgAECn8YAAIRAAcJbCE8EACZAgARAAcJbCE8EACZAgAAAA==.Brewsli:BAAALgADCgIJAgABLgAECgYJCgADAAAAAA==.Brightstar:BAAALgAECgcJEwAAAA==.Brokenaltar:BAABLgAECn8VAAMBAAYJNRhZOQAdAQAKAAYJgRFVcwBLAQABAAUJCRpZOQAdAQAAAA==.Brownington:BAAALgAECgYJCgAAAA==.Bruhilda:BAAALgAECgUJCAAAAA==.Brymstone:BAAALgAECgQJBwAAAA==.Brynthebuff:BAAALgADCgMJBQAAAA==.Brìonik:BAACLgAFFH8NAAMLAAUJvRhIBgBXAQALAAUJkBVIBgBXAQASAAIJuxBjDACpAAAuAAQKfyIAAxIACAnwIYcNAOwBABIABgksIYcNAOwBAAsABAnuIzxoAJMBAAAA.',
Bu='Bufferfish:BAABLgAECn8cAAITAAgJ5gnPCwAqAQATAAgJ5gnPCwAqAQAAAA==.',
Ca='Calinnea:BAAALgAECgMJAwABLgAECgQJBwADAAAAAA==.Cantheartitz:BAAALgAECgUJDAAAAA==.Catastrophe:BAAALgAECgQJCAAAAA==.',
Ce='Celthol:BAAALgAECgMJBgAAAA==.',
Ch='Chelraani:BAAALgAECgYJEQAAAA==.Chiichard:BAAALgADCgYJCgAAAA==.Chipnuts:BAABLgAECn8YAAIOAAgJTiXAAgBtAwAOAAgJTiXAAgBtAwAAAA==.Chonchoo:BAAALgADCgEJAQAAAA==.Chosethebear:BAAALgADCgkJEAAAAA==.',
Cl='Clarabellax:BAAALgAECgMJAwAAAA==.Clarkkentt:BAAALgADCgcJBwAAAA==.Claymore:BAACLgAFFH8GAAIIAAMJuhAbBwDnAAAIAAMJuhAbBwDnAAAuAAQKfxUAAggACAkMGc4cAGcCAAgACAkMGc4cAGcCAAAA.Clazzicola:BAACLgAFFH8GAAMUAAMJKwWMBwC4AAAUAAMJKwWMBwC4AAAOAAIJXgiyDQCWAAAuAAQKfxwABA4ACAnHGFkeAOUBAA4ABwlYHFkeAOUBABQABwnlE5EmAIABABEAAQlhA7uVAB8AAAAA.',
Co='Conjredcukee:BAAALgAECgUJBQAAAA==.Coo:BAAALgAECgQJBAABLgAECgUJBwADAAAAAA==.Coogsayer:BAABLgAECn8UAAIVAAcJxh2VEQBxAgAVAAcJxh2VEQBxAgAAAA==.',
Cp='Cptncrush:BAAALgAECgYJEAAAAA==.',
Cr='Croquetica:BAAALgADCgMJBAAAAA==.Crossed:BAAALgADCgcJCwAAAA==.Crowshadow:BAAALgAECgIJAgAAAA==.',
Cy='Cyther:BAACLgAFFH8QAAIIAAUJAB4QAQCAAQAIAAUJAB4QAQCAAQAuAAQKfyEAAggACAlcJLEHAC4DAAgACAlcJLEHAC4DAAAA.',
['Cÿ']='Cÿthera:BAABLgAECn8YAAIKAAgJUB/AHAClAgAKAAgJUB/AHAClAgAAAA==.',
Da='Dakk:BAABLgAECn8oAAIWAAgJXyIqAwB1AgAWAAgJXyIqAwB1AgAAAA==.Daraghor:BAABLgAECn8YAAIXAAgJeSIMAgAbAwAXAAgJeSIMAgAbAwAAAA==.Darkenstormy:BAAALgAECgUJCgAAAA==.Darlyndra:BAAALgADCgUJBQAAAA==.Darsae:BAAALgAECgQJDAAAAA==.',
De='Deadlight:BAABLgAECn8fAAIWAAkJew8DCQDuAQAWAAkJew8DCQDuAQAAAA==.Deathkillhun:BAAALgAECgQJBwAAAA==.Deathshooter:BAAALgAECgcJAQAAAA==.Deavant:BAAALgADCgMJAwAAAA==.Deermon:BAAALgAECgYJCwAAAA==.Deforest:BAAALgADCgcJEQAAAA==.Deity:BAAALgAECgYJDwAAAA==.Demogon:BAAALgAECgQJBwAAAA==.Demondeano:BAABLgAECn8VAAIKAAgJJBFFFABbAQAKAAgJJBFFFABbAQAAAA==.Demonx:BAAALgAECgYJEgAAAA==.Desolation:BAABLgAECn8fAAIYAAgJNSQLAADLAgAYAAgJNSQLAADLAgAAAA==.Despia:BAAALgAECgYJEwAAAA==.Devastacia:BAAALgADCgUJBQAAAA==.Deviarc:BAAALgAECgQJBAAAAA==.',
Dh='Dharkon:BAAALgAECgIJAgAAAA==.',
Di='Dicot:BAAALgAECgYJEgAAAA==.',
Dj='Djpallyd:BAAALgAECggJCwAAAA==.',
Do='Domilthri:BAABLgAECn8gAAMZAAgJawpDEAAqAQALAAgJawoTHQAyAQAZAAYJ8gVDEAAqAQAAAA==.Dotdaddy:BAAALgAECgQJBwAAAA==.',
Dr='Dracoly:BAAALgAECggJEAAAAA==.Draconu:BAACLgAFFH8HAAITAAMJaQvmEgDoAAATAAMJaQvmEgDoAAAuAAQKfxoAAxMACQkVG8gKAMkCABMACQkVG8gKAMkCABoAAQmaAWtOACIAAAAA.Dragoncurry:BAAALgAECgQJCgAAAA==.Dragonmite:BAAALgAECgEJAQAAAA==.Drakka:BAAALgADCgkJDgAAAA==.Draktyr:BAABLgAECn8gAAIIAAgJeCB+CQAWAwAIAAgJeCB+CQAWAwAAAA==.Dropeadita:BAAALgAECgQJBAAAAA==.Droptop:BAAALgADCgcJCAAAAA==.',
Du='Dumbsht:BAABLgAECn8XAAMPAAgJ0BZhMQCpAQAPAAcJ0BVhMQCpAQAbAAYJUBHlXQBOAQAAAA==.',
Ea='Easystreet:BAAALgAECgIJAwAAAA==.',
Ef='Effluv:BAAALgADCgcJDgAAAA==.',
El='Elandir:BAAALgADCgQJAQAAAA==.Elanora:BAAALgAECgMJAwAAAA==.Elbrookel:BAAALgAECgIJAgAAAA==.Eliza:BAAALgADCgkJCQAAAA==.Ellismom:BAABLgAECn8fAAIWAAgJEBdHDADAAQAWAAgJEBdHDADAAQAAAA==.Elvea:BAAALgAECgUJCgABLgAECgkJIgAcAAYaAA==.',
Em='Emeralddemon:BAAALgADCgEJAgABLgADCgUJCAADAAAAAA==.Emeraldshade:BAAALgADCgUJCAAAAA==.',
En='Enamorada:BAAALgADCgYJCgABLgAECgYJDwADAAAAAA==.',
Er='Ereithelda:BAACLgAFFH8QAAIUAAUJDRN1AgCAAQAUAAUJDRN1AgCAAQAuAAQKfyEAAhQACAm5IhEHAOsCABQACAm5IhEHAOsCAAAA.Ericka:BAAALgADCgQJBAAAAA==.Erreya:BAAALgADCgEJAQAAAA==.',
Es='Esma:BAAALgADCgkJCQAAAA==.',
Ev='Evox:BAAALgAECgUJCgAAAA==.',
Ey='Eyris:BAAALgADCgMJAwAAAA==.Eyrndor:BAAALgADCgIJAwAAAA==.',
Fa='Faacee:BAAALgAECgIJAgAAAA==.Fann:BAAALgAECgUJDgAAAA==.Faytl:BAAALgADCggJCAAAAA==.',
Fe='Felbubu:BAABLgAECn8cAAQCAAgJ6iAhBACAAgACAAcJBiIhBACAAgABAAUJOyAeIgCrAQAKAAEJ6hqx3QA0AAAAAA==.Femboy:BAAALgADCgEJAQAAAA==.Fewz:BAACLgAFFH8FAAIMAAIJ7RZzPgCwAAAMAAIJ7RZzPgCwAAAuAAQKfxoAAgwACAlDICkwALICAAwACAlDICkwALICAAAA.',
Fi='Fireybuns:BAAALgAECgEJAgAAAA==.',
Fl='Flaccid:BAAALgAECggJEAAAAA==.Flakiron:BAACLgAFFH8HAAIdAAIJmA/2CwCKAAAdAAIJmA/2CwCKAAAuAAQKfyQAAh0ACAkeGpYLAFUCAB0ACAkeGpYLAFUCAAAA.Flakov:BAAALgAECgIJAgABLgAFFAIJBwAdAJgPAA==.Flaktop:BAAALgAECgIJAgABLgAFFAIJBwAdAJgPAA==.Fler:BAAALgADCgQJBAAAAA==.',
Fo='Forbacon:BAAALgAECgYJCgAAAA==.Force:BAAALgAECgYJDwAAAA==.Fouris:BAAALgAECgYJDAAAAA==.',
Fr='Fremosth:BAAALgADCgIJAgAAAA==.Fretman:BAAALgADCgcJCQAAAA==.Fridgie:BAACLgAFFH8PAAIbAAUJXBU0BABdAQAbAAUJXBU0BABdAQAuAAQKfyEAAhsACAlnI3EPAMACABsACAlnI3EPAMACAAAA.Frozenflyer:BAAALgAECgUJEAAAAA==.Frozenturtle:BAAALgAECgQJBwAAAA==.',
Ft='Ftwiamtank:BAAALgADCgkJDAAAAA==.',
Fu='Fuoco:BAAALgAECgkJCgAAAA==.',
Ga='Garcutt:BAACLgAFFH8PAAIMAAUJJw06CgBNAQAMAAUJJw06CgBNAQAuAAQKfyEAAgwACAkjIOs2AJgCAAwACAkjIOs2AJgCAAAA.Gaurdinn:BAABLgAECn8eAAMeAAgJBg8YAwA7AQAeAAYJbhAYAwA7AQATAAcJVg2YMwAvAQAAAA==.',
Ge='Gebuss:BAAALgADCgQJBAAAAA==.Generickmonk:BAACLgAFFH8GAAIOAAQJ8wxZCADxAAAOAAQJ8wxZCADxAAAuAAQKfyAAAg4ACAkfIvsIAOgCAA4ACAkfIvsIAOgCAAAA.Gensis:BAAALgADCgYJBgAAAA==.Geomatic:BAAALgAECgEJAQAAAA==.Gethsemåne:BAAALgADCgMJAwAAAA==.',
Gi='Giovannucci:BAAALgAECgEJAQAAAA==.Gitan:BAAALgADCgQJBAAAAA==.',
Gl='Gladstone:BAAALgAECgYJCQAAAA==.',
Go='Gomlvirgin:BAAALgADCgYJBgABLgAECggJIAALAHQUAA==.',
Gr='Gracehimeûwû:BAAALgAECgYJBwAAAA==.Grampsie:BAAALgAECgUJBwAAAA==.Grayeyes:BAAALgADCggJCAAAAA==.Greenngoblin:BAAALgADCgEJAQAAAA==.Grimmlie:BAAALgADCgUJBQAAAA==.Grinzler:BAAALgADCgIJAgAAAA==.Grumpybear:BAAALgADCggJDwAAAA==.Grumpykat:BAAALgAECggJEgAAAA==.Grumpypros:BAAALgADCgUJBQAAAA==.',
Gu='Guino:BAAALgAECgMJAwAAAA==.Guinodruid:BAAALgADCgUJCAAAAA==.',
Gw='Gwenelly:BAAALgAECgEJAQAAAA==.',
Ha='Hamncheeks:BAAALgAECgEJAQAAAA==.Haptism:BAAALgADCgcJBwAAAA==.Hardeesdelux:BAAALgADCgYJBgABLgAECgMJAwADAAAAAA==.Hardnarples:BAAALgADCgEJAQAAAA==.Hayzerade:BAAALgAECgMJAwAAAA==.Hazis:BAABLgAECn8iAAIfAAgJbh4dCACkAgAfAAgJbh4dCACkAgAAAA==.',
Hi='Hippiecritz:BAAALgADCgYJBwAAAA==.Hitokiri:BAAALgADCgMJAwAAAA==.',
Ho='Holy:BAACLgAFFH8HAAIgAAIJ0AJVBgBYAAAgAAIJ0AJVBgBYAAAuAAQKfyEAAiAACAn1EvAQALcBACAACAn1EvAQALcBAAAA.Holydad:BAABLgAECn8ZAAIgAAgJOhr5CQAxAgAgAAgJOhr5CQAxAgAAAA==.Holydust:BAAALgAECgcJEQAAAA==.Holymoki:BAAALgADCgYJCgAAAA==.Holyroundie:BAABLgAECn8iAAIQAAgJ6gxzLgCKAQAQAAgJ6gxzLgCKAQAAAA==.Holyshock:BAACLgAFFH8PAAIEAAUJZBonAwBmAQAEAAUJZBonAwBmAQAuAAQKfyEAAgQACAnPI9UOABcDAAQACAnPI9UOABcDAAAA.Honeybutter:BAABLgAECn8nAAMJAAgJXCP9AQAVAwAJAAgJXCP9AQAVAwAIAAcJix7PIwA4AgAAAA==.Hordebreaker:BAAALgAECgUJDgAAAA==.Hotflash:BAAALgADCgUJBwAAAA==.',
Hu='Huukend:BAABLgAECn8fAAIbAAgJaxuYFACSAgAbAAgJaxuYFACSAgAAAA==.',
Ic='Icebabyman:BAABLgAECn8UAAIMAAgJWRvfOACSAgAMAAgJWRvfOACSAgAAAA==.',
In='Inanitas:BAAALgADCgcJBwAAAA==.Ineffectual:BAABLgAECn8XAAIFAAgJCBAaMgC9AQAFAAgJCBAaMgC9AQAAAA==.',
Ir='Irukox:BAAALgAECgQJBQAAAA==.',
It='Itty:BAAALgADCgcJBwAAAA==.',
Ja='Jagger:BAAALgADCgcJCQAAAA==.Jalene:BAAALgAECgEJAQAAAA==.Janewayy:BAABLgAECn8YAAIKAAgJrwzjWgCQAQAKAAgJrwzjWgCQAQAAAA==.',
Je='Jeks:BAAALgADCgcJBwABLgAFFAUJEAAFAJEdAA==.Jemma:BAAALgAECgcJEgAAAA==.Jettadari:BAACLgAFFH8QAAIKAAUJaBr/AwBnAQAKAAUJaBr/AwBnAQAuAAQKfyEAAgoACAmDIekWAM0CAAoACAmDIekWAM0CAAAA.Jettadin:BAABLgAECn8YAAIEAAgJ9SGjDwARAwAEAAgJ9SGjDwARAwABLgAFFAUJEAAKAGgaAA==.Jettathyr:BAAALgAECgcJCgABLgAFFAUJEAAKAGgaAA==.',
Ju='Jubba:BAAALgAECgYJDQAAAA==.Junk:BAAALgAECgYJBwABLgAECgcJGAARAGwhAA==.',
['Jë']='Jëks:BAACLgAFFH8QAAIFAAUJkR0TAQCzAQAFAAUJkR0TAQCzAQAuAAQKfyEAAwUACAlUJXEDAEEDAAUACAlUJXEDAEEDACEAAgksDpwKAIIAAAAA.',
Ka='Kahea:BAAALgAECgQJBAAAAA==.Kaitou:BAABLgAECn8eAAINAAgJARxLBwB4AgANAAgJARxLBwB4AgAAAA==.Kalamiti:BAAALgAECgQJCAAAAA==.Kallar:BAABLgAECn8aAAIQAAcJWR9cAgBNAgAQAAcJWR9cAgBNAgAAAA==.Karesh:BAAALgAECgQJBAAAAA==.Kayeera:BAAALgAECgQJDgAAAA==.Kayha:BAAALgADCgEJAQAAAA==.Kaztiel:BAAALgAECgIJAgAAAA==.',
Ke='Keadon:BAAALgAECgYJCgAAAA==.Keeper:BAAALgADCgMJAwABLgAECgYJDwADAAAAAA==.Keh:BAAALgADCgkJCQAAAA==.Kennethv:BAAALgAECgMJBAAAAA==.Kenze:BAAALgADCgQJBAAAAA==.Kev:BAAALgAECgcJAgAAAA==.',
Kh='Khel:BAAALgADCgcJBwAAAA==.Khiell:BAABLgAECn8UAAIIAAgJvRZfHwBWAgAIAAgJvRZfHwBWAgAAAA==.',
Ki='Kilyse:BAAALgADCgYJBgAAAA==.Kinigit:BAAALgAECgQJBwABLgAFFAIJBwAiANsUAA==.Kirïtö:BAAALgAECgUJCwAAAA==.Kitarah:BAAALgAECgIJAgAAAA==.Kitarazen:BAAALgAECgYJBgAAAA==.',
Ko='Kokushimosu:BAAALgAECgQJBAAAAA==.Koo:BAAALgAECgUJBwAAAA==.',
Ks='Ksper:BAAALgAECgYJCQAAAA==.',
Ku='Kukalak:BAAALgAECgYJDwAAAA==.Kuranaa:BAAALgADCggJDwABLgADCggJHAADAAAAAA==.Kurulak:BAABLgAECn8bAAIKAAgJ+ww7FwBFAQAKAAgJ+ww7FwBFAQAAAA==.',
Ky='Kymru:BAAALgADCgcJDQAAAA==.',
['Ké']='Kénnéth:BAAALgAECgUJCwAAAA==.',
La='Lacerveza:BAAALgAECgIJAgAAAA==.Lahyanhou:BAABLgAECn8VAAIPAAcJjANgUQAHAQAPAAcJjANgUQAHAQAAAA==.Lalalalala:BAAALgAECgcJCgAAAA==.Lalin:BAAALgAECgEJAQAAAA==.Larkwyn:BAAALgAECgMJAwAAAA==.Laylah:BAAALgADCgYJBAAAAA==.',
Le='Lebrand:BAAALgAECgEJAQAAAA==.Leriope:BAABLgAECn8fAAILAAgJKQ65FQBiAQALAAgJKQ65FQBiAQAAAA==.',
Li='Lightbeer:BAAALgAECgYJBwAAAA==.Lihplock:BAAALgAECgQJBAABLgAECggJJwAIADgjAA==.Lildragonboi:BAAALgADCgUJBQAAAA==.Lilem:BAAALgADCgcJEgAAAA==.Listenlinda:BAAALgADCgYJBgAAAA==.Littlemerald:BAAALgADCgMJAwAAAA==.',
Lj='Lj:BAABLgAECn8YAAIjAAgJ4R1qAgB1AgAjAAgJ4R1qAgB1AgAAAA==.',
Lo='Localsingles:BAAALgADCgcJBwAAAA==.Lorath:BAAALgADCgEJAQAAAA==.Lovecrafft:BAAALgAECgEJAQAAAA==.',
Lu='Lu:BAAALgAECgIJAgABLgAFFAMJBgAUACsFAA==.Lucinà:BAABLgAECn8ZAAMjAAgJeh6YDAC1AgAjAAgJeh6YDAC1AgAEAAQJPSMPgAB6AQAAAA==.Luxure:BAAALgAECgEJAQAAAA==.',
Ly='Lyndall:BAAALgAECgMJAwAAAA==.',
Ma='Maegan:BAAALgADCgkJHwAAAA==.Mager:BAAALgAECgEJAQAAAA==.Mahll:BAAALgADCgcJBwAAAA==.Maidrim:BAACLgAFFH8IAAIkAAQJvBpPAQB/AQAkAAQJvBpPAQB/AQAuAAQKfxcAAiQACAn3IvICALECACQACAn3IvICALECAAAA.Mamajumbo:BAAALgAECgUJCAAAAA==.Marage:BAAALgADCgEJAQAAAA==.Marellias:BAAALgAECgEJAQABLgAECggJHgAEAIgjAA==.Marikel:BAAALgADCgcJEAAAAA==.Markwel:BAAALgAECgIJAgAAAA==.Marrack:BAAALgAECgYJDQAAAA==.',
Me='Melador:BAAALgADCgIJAgAAAA==.Meletha:BAAALgAECgYJCQAAAA==.Melpuis:BAAALgAECgEJAgAAAA==.Metahorfasis:BAAALgAECgMJAwAAAA==.',
Mi='Michaelken:BAAALgAECgYJDwAAAA==.Mierín:BAAALgADCgYJBgAAAA==.Migrains:BAABLgAECn8fAAIgAAgJPiLBAgAAAwAgAAgJPiLBAgAAAwAAAA==.Mineo:BAAALgAECgEJAQAAAA==.Mirâjâne:BAAALgAECgEJAQAAAA==.Miskaabin:BAAALgAECgUJCAAAAA==.Miststress:BAAALgADCgcJBwAAAA==.',
Mo='Mobal:BAABLgAECn8WAAIFAAcJhxqHHgAoAgAFAAcJhxqHHgAoAgAAAA==.Mojogreens:BAAALgAECgYJDAAAAA==.Montydh:BAAALgAECgEJAQAAAA==.Moonpetals:BAAALgADCgcJBwAAAA==.Moonrush:BAAALgAECgMJCAAAAA==.Mortiis:BAAALgAECgYJDwAAAA==.Motako:BAABLgAECn8gAAIFAAcJQiCiFQBoAgAFAAcJQiCiFQBoAgAAAA==.',
Mp='Mpd:BAAALgAECgQJBwAAAA==.',
My='Mybizël:BAABLgAECn8dAAIbAAcJOBvpIABAAgAbAAcJOBvpIABAAgAAAA==.Myrlifax:BAAALgADCgEJAQABLgADCgkJDgADAAAAAA==.Mystique:BAAALgAECgEJAQAAAA==.Mythdaraghma:BAAALgADCgYJBwAAAA==.',
['Má']='Máximo:BAAALgAECgYJDgAAAA==.',
['Mí']='Míerin:BAAALgAECgQJBAAAAA==.Míerín:BAACLgAFFH8FAAIlAAIJWBiKBAC8AAAlAAIJWBiKBAC8AAAuAAQKfxwAAyUACAkfIL0EAMcCACUACAkfIL0EAMcCABsABAm+G0lgAEcBAAAA.',
Na='Naama:BAAALgADCgMJAwAAAA==.Nadaar:BAAALgAECgUJBgAAAA==.Naelih:BAAALgAECgYJEQAAAA==.Natholomas:BAAALgADCgQJBAAAAA==.Nazeer:BAAALgADCgcJBwABLgAECggJIgAmAHEUAA==.Nazgrim:BAABLgAECn8iAAImAAgJcRRbLwDvAQAmAAgJcRRbLwDvAQAAAA==.',
Ne='Necronu:BAAALgAFFAEJAQABLgAFFAMJBwATAGkLAA==.',
Ni='Nikkolos:BAAALgAECgQJCwAAAA==.Ninjastax:BAAALgADCgEJAgAAAA==.Nissie:BAAALgAECgEJAQAAAA==.',
No='Nogusta:BAACLgAFFH8KAAIIAAUJFRTAAgBSAQAIAAUJFRTAAgBSAQAuAAQKfyEAAggACAkCInMLAP8CAAgACAkCInMLAP8CAAAA.Norberta:BAAALgAECgcJDgAAAA==.Nossanir:BAAALgAECgIJAgAAAA==.Nossellia:BAAALgAECgMJAwAAAA==.',
Nu='Nurana:BAAALgADCgEJAQAAAA==.',
Ny='Nycecritz:BAAALgAECgEJAQAAAA==.',
Od='Odor:BAAALgAECgQJBgAAAA==.',
Ol='Oldie:BAAALgAECgIJAgAAAA==.Olielno:BAAALgADCgMJAwAAAA==.',
On='Onlyshams:BAABLgAECn8YAAIFAAgJPxc5GQBNAgAFAAgJPxc5GQBNAgAAAA==.Onlytides:BAEBLgAECn8YAAMFAAgJKSLjBwD2AgAFAAgJKSLjBwD2AgAGAAcJVBh5HwAUAgABLgAFFAUJDwAmAD0iAA==.Onubis:BAABLgAECn8aAAMbAAgJlx8SDADhAgAbAAgJiR8SDADhAgAPAAYJxh1tNACXAQABLgAFFAMJBwATAGkLAA==.Onulock:BAAALgAECgYJCgABLgAFFAMJBwATAGkLAA==.',
Op='Opgarbage:BAAALgAECgQJCAAAAA==.',
Ou='Oukei:BAAALgAECgcJEAABLgAFFAQJCwADAAAAAQ==.Oumura:BAAALgAECgYJDgAAAA==.',
Ov='Overlordainz:BAAALgAECgQJBgAAAA==.',
Pa='Paarthürnax:BAAALgAECgYJDAAAAA==.Pallyoop:BAAALgAECgcJEwAAAA==.Pandaa:BAAALgAECgEJAQAAAA==.Papapaw:BAAALgAECgQJBgAAAA==.Patherion:BAAALgADCgEJAQABLgAECgQJBwADAAAAAA==.Patholans:BAAALgAECgQJBwAAAA==.Paxman:BAAALgADCgcJCwAAAA==.',
Pe='Peanits:BAAALgAECgQJCQAAAA==.Peanutsuckr:BAACLgAFFH8QAAIfAAUJJCP6AACSAQAfAAUJJCP6AACSAQAuAAQKfyEAAh8ACAnTJEAEAAoDAB8ACAnTJEAEAAoDAAAA.Pearserve:BAAALgADCgUJBQABLgAECgYJDwADAAAAAA==.',
Ph='Phantöm:BAAALgADCgQJBAAAAA==.Phosphate:BAABLgAECn8UAAIKAAYJNxKjbgBYAQAKAAYJNxKjbgBYAQAAAA==.',
Pi='Pingg:BAAALgAECgQJBAAAAA==.Pinkeye:BAAALgADCgEJAQAAAA==.Pippafan:BAAALgAECgEJAQAAAA==.',
Pl='Planknstein:BAAALgADCgMJAwAAAA==.Playdohh:BAAALgAECgcJCAAAAA==.Plutonia:BAAALgAECgIJBAAAAA==.',
Po='Pockett:BAAALgAECgUJCgAAAA==.Powrwordgoat:BAABLgAECn8fAAInAAgJuxFDIQCJAQAnAAgJuxFDIQCJAQAAAA==.',
Pr='Prestoh:BAABLgAECn8VAAIGAAcJxA/WDQAjAQAGAAcJxA/WDQAjAQAAAA==.Prismclaw:BAABLgAECn8YAAIMAAgJAAZJIgBJAQAMAAgJAAZJIgBJAQAAAA==.Processing:BAAALgAECgYJBgAAAA==.',
Ps='Pseudoruski:BAAALgADCgMJAwAAAA==.',
Pu='Purplehaze:BAAALgADCggJEQAAAA==.',
Pv='Pvlolz:BAABLgAECn8YAAIQAAgJxAo7MACAAQAQAAgJxAo7MACAAQAAAA==.',
Qa='Qaharn:BAAALgADCgUJBQAAAA==.',
Qp='Qplus:BAAALgAECgYJDwAAAA==.',
Qu='Quaenie:BAAALgAECgYJDgAAAA==.Quintin:BAAALgAECgMJBAAAAA==.',
Ra='Raged:BAAALgAECgUJCgAAAA==.Ragetotem:BAABLgAECn8aAAIGAAYJTRwaKADSAQAGAAYJTRwaKADSAQAAAA==.Ragewarg:BAAALgAECgQJBAAAAA==.Ragnashock:BAAALgAECgQJBgAAAA==.Ralvarr:BAAALgAECgYJCwAAAA==.Raptorjésus:BAAALgADCgcJCwAAAA==.Rathaes:BAAALgADCgMJAwAAAA==.Ravenstryke:BAAALgAECgEJAQAAAA==.Raylea:BAAALgADCgcJBwAAAA==.Rayleigh:BAAALgAECgQJBAABLgAECgUJCwADAAAAAA==.Razzgix:BAAALgAECgUJBgAAAA==.',
Re='Redchord:BAAALgADCgUJDAAAAA==.Regidør:BAABLgAECn8YAAMjAAgJ/CBgCADoAgAjAAgJ/CBgCADoAgAEAAYJxx0fYQDBAQAAAA==.Relik:BAAALgAECgYJEAAAAA==.Resith:BAAALgAECgYJBwAAAA==.',
Rh='Rhaelia:BAAALgAECgcJEwAAAA==.Rhaspus:BAAALgADCgQJBAAAAA==.',
Ri='Rilliccine:BAAALgADCgkJCQAAAA==.Rillinetti:BAAALgAECgYJDQAAAA==.Rillini:BAAALgADCgcJBwAAAA==.',
Ro='Rondon:BAAALgAECgYJDwAAAA==.Rookdh:BAABLgAECn8fAAMKAAgJuxYZVQCkAQAKAAgJuxYZVQCkAQABAAYJ8xfiLABjAQAAAA==.Rorcia:BAAALgADCgUJBwAAAA==.Rosey:BAAALgAECgYJCwAAAA==.Roxania:BAAALgADCgYJBgAAAA==.Royale:BAAALgADCgUJBQAAAA==.',
Ru='Rudyeightbal:BAAALgAECgcJEwAAAA==.Ruedons:BAAALgAECgIJAgAAAA==.Rugsalon:BAABLgAECn8eAAIMAAgJox3sNACfAgAMAAgJox3sNACfAgAAAA==.Rustedbarrel:BAABLgAECn8ZAAIRAAgJuBN0IQD2AQARAAgJuBN0IQD2AQAAAA==.',
Ry='Ryptar:BAAALgADCgkJFQAAAA==.',
['Ré']='Réxxar:BAABLgAECn8cAAIXAAcJPRTaDQClAQAXAAcJPRTaDQClAQAAAA==.',
Sa='Saelyres:BAAALgAECgQJCAAAAA==.Saikye:BAAALgADCgcJBwAAAA==.Sairu:BAAALgADCgEJAQAAAA==.Samistraza:BAAALgADCgEJAQAAAA==.Sammy:BAAALgAECgYJEAAAAA==.Santaclaaws:BAACLgAFFH8FAAIKAAIJ/xlqFQCVAAAKAAIJ/xlqFQCVAAAuAAQKfyUABAoACAkwIi4SAO0CAAoACAkwIi4SAO0CAAIAAwlEFr4FANUAAAEAAgk1GYhbAHIAAAAA.Santapal:BAABLgAECn8bAAIjAAYJdhsFLQDRAQAjAAYJdhsFLQDRAQABLgAFFAIJBQAKAP8ZAA==.Santatumblr:BAAALgAECgUJBQABLgAFFAIJBQAKAP8ZAA==.Santhin:BAAALgADCgcJCgAAAA==.Sareit:BAAALgAECgMJBgAAAA==.Sassee:BAAALgADCgEJAQAAAA==.Sayvil:BAAALgAECgIJAgABLgAECgcJGgAQAFkfAQ==.',
Sc='Scripture:BAAALgADCgYJBgAAAA==.',
Se='Seawolph:BAABLgAECn8VAAIFAAcJXhanDQBkAQAFAAcJXhanDQBkAQAAAA==.Selenia:BAAALgADCggJDwAAAA==.Sensational:BAABLgAECn8aAAMUAAcJWhx6EwAxAgAUAAcJWhx6EwAxAgAOAAUJZQi+DwDWAAAAAA==.Sergio:BAAALgAECgcJCgAAAA==.',
Sh='Shamiska:BAAALgADCgkJHgAAAA==.Shammerdown:BAAALgAECgIJAwAAAA==.Shampooh:BAAALgADCgkJCQABLgAECgYJEQADAAAAAA==.Shaokhan:BAABLgAECn8aAAIFAAcJyh/0AgBcAgAFAAcJyh/0AgBcAgAAAA==.Sheilla:BAAALgADCgUJBQAAAA==.Shian:BAAALgAECgYJEwAAAA==.Shieldee:BAABLgAECn8eAAIEAAgJoBSxDQC+AQAEAAgJoBSxDQC+AQAAAA==.Shlectrinell:BAABLgAECn8fAAMcAAgJbQYlCABZAQAkAAgJBAUICwB+AQAcAAgJEwQlCABZAQAAAA==.Shockeei:BAACLgAFFH8NAAIMAAUJGyPQDgCiAQAMAAUJGyPQDgCiAQAuAAQKfyEAAwwACAnkJKcUACwDAAwACAnkJKcUACwDACgAAwlSGHgJALkAAAAA.Shocktroop:BAAALgADCgYJCQAAAA==.Shurp:BAAALgAECgMJAwAAAA==.',
Si='Siakora:BAAALgAECgcJEgABLgAFFAUJDgAiAK0aAA==.Sicksty:BAAALgADCgcJBwAAAA==.Sighhy:BAAALgAECgIJBQAAAA==.Sijth:BAABLgAECn8sAAIEAAcJuh79CAD6AQAEAAcJuh79CAD6AQAAAA==.Silentchaos:BAAALgADCgMJBQAAAA==.Silverwar:BAAALgAECgcJEwAAAA==.Simmi:BAECLgAFFH8PAAImAAUJPSLpAADlAQAmAAUJPSLpAADlAQAuAAQKfyEAAiYACAlqJXcGACQDACYACAlqJXcGACQDAAAA.Sinnis:BAAALgAECgEJAQAAAA==.Sixtea:BAAALgAECgcJEwAAAA==.',
Sk='Skepti:BAABLgAECn8UAAIbAAcJABNgDwCHAQAbAAcJABNgDwCHAQAAAA==.Skysong:BAAALgAECgMJAwAAAA==.',
Sl='Slimfoo:BAAALgAECgcJDQAAAA==.Slunkyspit:BAAALgADCgUJCAAAAA==.Slybearclaw:BAAALgADCgUJBQAAAA==.',
Sm='Smeeta:BAABLgAECn8nAAIWAAgJ4R22DAC7AQAWAAgJ4R22DAC7AQAAAA==.Smoak:BAAALgADCgUJBQAAAA==.Smolderlight:BAABLgAECn8fAAIjAAgJQRAMCwCPAQAjAAgJQRAMCwCPAQAAAA==.Smoochiebutt:BAAALgAECgQJBAAAAA==.',
So='Solaace:BAAALgAECgEJAQAAAA==.Solo:BAAALgAECgYJCQAAAA==.Soloris:BAAALgADCgcJCAAAAA==.Soram:BAAALgAECgYJCgAAAA==.Soulstryker:BAAALgAECgEJAQAAAA==.',
Sp='Spacepants:BAAALgAECgEJAQAAAA==.',
St='Staraelle:BAAALgAECgEJAgAAAA==.Steelerayne:BAAALgAECgUJCgAAAA==.Stinkypanky:BAAALgADCgEJAQAAAA==.Strangerdk:BAAALgAECgYJEAAAAA==.Streetdog:BAAALgADCgUJBQAAAA==.',
Su='Superfatbaby:BAAALgAECgYJCgAAAA==.',
Sw='Swishersweet:BAABLgAECn8UAAIXAAgJigPfHgCpAAAXAAgJigPfHgCpAAAAAA==.Swordfish:BAAALgAECgYJEgAAAA==.',
Sy='Sybros:BAAALgADCgEJAQAAAA==.Sydonie:BAAALgAECgEJAQAAAA==.Symbah:BAAALgADCgYJBgAAAA==.Synvalid:BAABLgAECn8XAAIKAAgJvgc4IwD3AAAKAAgJvgc4IwD3AAAAAA==.',
Ta='Tabmage:BAABLgAECn8cAAIMAAgJwRk3DgDWAQAMAAgJwRk3DgDWAQAAAA==.Talanth:BAAALgAECgYJCQAAAA==.Tandisong:BAAALgADCgYJBgAAAA==.Tanknstein:BAAALgADCgYJBgAAAA==.Tanton:BAAALgAECgMJAwAAAA==.Tanzil:BAAALgAECgYJDgAAAA==.Tardigrade:BAAALgAECgIJAgAAAA==.Tayon:BAAALgAECgUJCgAAAA==.Tayvin:BAAALgADCgQJAwAAAA==.Tazanath:BAAALgADCgEJAQAAAA==.',
Te='Tempest:BAAALgADCgcJBwAAAA==.Tengen:BAAALgAECgQJCQAAAA==.Termana:BAACLgAFFH8QAAIdAAUJjx/kAgByAQAdAAUJjx/kAgByAQAuAAQKfyEAAh0ACAljJIICAEMDAB0ACAljJIICAEMDAAAA.',
Th='Tharja:BAABLgAECn8YAAIMAAgJJRvmNACfAgAMAAgJJRvmNACfAgAAAA==.Thornp:BAAALgAECgEJAgAAAA==.Thoronk:BAAALgAECgcJBgAAAA==.Thsaric:BAAALgADCgkJFAAAAA==.Thug:BAABLgAECn8WAAMIAAcJ0R/MJQArAgAIAAcJ0R/MJQArAgAdAAIJHxvONgCRAAAAAA==.',
Ti='Tiferet:BAABLgAECn8WAAQQAAcJDB4DAgBgAgAQAAcJDB4DAgBgAgAnAAMJfRLjPgC3AAAVAAEJngRrZwAqAAAAAA==.Tinysunshine:BAAALgAECgMJBAAAAA==.Tismyhammer:BAAALgADCgQJBAAAAA==.',
To='Toasted:BAAALgADCgQJAQAAAA==.Tolenkar:BAAALgAECgYJEAAAAA==.Tomato:BAACLgAFFH8LAAMSAAUJlA3DBwDxAAASAAMJXw3DBwDxAAALAAMJMgylOACiAAAuAAQKfyEAAxIACAkLH6oFAHoCABIACAkIHKoFAHoCAAsABAmwGFYpAOkAAAAA.Tomhanks:BAAALgADCggJCgABLgADCgkJDgADAAAAAA==.Tormentaa:BAAALgAECgYJBwAAAA==.Torvalar:BAABLgAECn8gAAIEAAgJHRDbGABbAQAEAAgJHRDbGABbAQAAAA==.',
Tr='Treemendous:BAAALgADCgYJCQAAAA==.Truthslayer:BAAALgAECgcJDAAAAA==.Trûth:BAAALgAECggJEwAAAA==.',
Tu='Turdyl:BAABLgAECn8dAAIEAAgJSg+CcwCUAQAEAAgJSg+CcwCUAQAAAA==.',
Tw='Twindad:BAAALgADCgkJEQAAAA==.Twindadlock:BAAALgADCgEJAQAAAA==.',
Ty='Tyraz:BAAALgAECgcJEwAAAA==.Tystrolf:BAAALgAECgcJDwAAAA==.',
Tz='Tzar:BAAALgADCgIJAgAAAA==.',
['Tô']='Tôx:BAAALgAECgUJDgAAAA==.',
Ud='Udyrr:BAAALgADCgIJAgAAAA==.',
Ul='Ulfius:BAAALgADCgMJAwAAAA==.Ullume:BAAALgAECgMJAwAAAA==.',
Um='Umbranwings:BAAALgAECgQJBAAAAA==.',
Un='Undeadarnix:BAAALgAECgMJAwAAAA==.Unheardjp:BAAALgAECgMJCAAAAA==.Unholy:BAAALgADCgMJAwAAAA==.',
Va='Vacuum:BAAALgAECgYJDgAAAA==.Vadican:BAAALgADCgQJBAAAAA==.Vaerix:BAABLgAECn8bAAITAAgJmQxoCABkAQATAAgJmQxoCABkAQAAAA==.Valhals:BAABLgAECn8UAAIRAAUJuQT8FgCeAAARAAUJuQT8FgCeAAAAAA==.Valydrin:BAABLgAECn8fAAIQAAgJQhzTAQBtAgAQAAgJQhzTAQBtAgAAAA==.Vanhelsinky:BAAALgADCgIJAgAAAA==.Varyn:BAAALgADCgIJAgAAAA==.',
Ve='Velandia:BAAALgAECgEJAQAAAA==.Ventis:BAAALgAECgQJBwAAAA==.',
Vo='Voidifphat:BAAALgAECggJDAAAAA==.Voidtorrent:BAAALgAECgQJBwAAAA==.Voidvanquish:BAAALgAECgUJBQAAAA==.Vorkhan:BAAALgADCgUJBwAAAA==.',
Vu='Vuldrak:BAAALgAECgcJEAAAAA==.',
Vy='Vysis:BAACLgAFFH8GAAQQAAMJVBEEDgCOAAAQAAIJ1AwEDgCOAAAVAAIJ2gLqCwBKAAAnAAEJYACKHAA2AAAuAAQKfysABBAACAnEGIISAEwCABAACAnEGIISAEwCABUABgl5F/AlAKgBACcAAQn3I0gTAGkAAAAA.',
['Vä']='Vännic:BAAALgADCgEJAwAAAA==.Vännìc:BAAALgADCgEJAQAAAA==.',
['Ví']='Ví:BAAALgAECgMJBQAAAA==.',
Wh='Whatfoxsay:BAAALgADCgEJAQAAAA==.When:BAAALgADCgQJBAAAAA==.Whicker:BAAALgAECgUJBgAAAA==.Whipsnchains:BAAALgADCgYJCQAAAA==.',
Wi='Wickèr:BAABLgAECn8gAAIRAAgJAxpHBADfAQARAAgJAxpHBADfAQAAAA==.Wieldblade:BAABLgAECn8ZAAIEAAgJ8xsgKACEAgAEAAgJ8xsgKACEAgAAAA==.Winslett:BAAALgADCgQJBAAAAA==.',
Wo='Wolfemoon:BAAALgAECgMJBQAAAA==.',
Wr='Wrexd:BAABLgAECn8kAAILAAgJbRftCgDHAQALAAgJbRftCgDHAQAAAA==.',
Wu='Wunderbar:BAAALgAECgYJEwAAAA==.',
Wy='Wyldfire:BAACLgAFFH8HAAIiAAIJ2xSYCACjAAAiAAIJ2xSYCACjAAAuAAQKfyQAAyIACAmhI/QLANgCACIACAmhI/QLANgCACYAAglkF4SeAI4AAAAA.Wyndclaw:BAAALgAECgMJAwAAAA==.',
Xa='Xanith:BAAALgAECgYJDwAAAA==.',
Xe='Xebubble:BAAALgADCgEJAQABLgAECgEJAQADAAAAAA==.Xemonk:BAAALgAECgEJAQAAAA==.',
Yi='Yilnara:BAAALgAECgYJDgAAAA==.',
Ys='Ysa:BAABLgAECn8TAAMOAAYJliWXEAB3AgAOAAYJliWXEAB3AgAUAAEJkw2SbQApAAAAAA==.',
Za='Zajindor:BAAALgADCgEJAQAAAA==.Zarathul:BAAALgADCgIJAgAAAA==.',
Ze='Zekkun:BAAALgAECgEJAQAAAA==.',
Zi='Zirael:BAAALgADCgYJCgAAAA==.',
Zo='Zoganian:BAEALgADCgkJEAABLgAECgYJDQADAAAAAA==.Zogula:BAEALgAECgYJDQAAAA==.',
Zu='Zu:BAAALgAECgMJAwAAAA==.',
['År']='Årtemis:BAABLgAECn8VAAIlAAgJQRiCCQBIAgAlAAgJQRiCCQBIAgAAAA==.',
['Æb']='Æbony:BAAALgADCgMJAwAAAA==.',
['Ïr']='Ïrini:BAAALgAECgIJAgABLgAECgQJBwADAAAAAA==.',
['Ða']='Ðante:BAAALgAECgEJAQAAAA==.',
['Ðe']='Ðelusion:BAAALgAECgMJAwAAAA==.',
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

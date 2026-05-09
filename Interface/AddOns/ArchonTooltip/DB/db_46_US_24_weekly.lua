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

local lookup = {'DemonHunter-Havoc','DemonHunter-Vengeance','Paladin-Protection','Unknown-Unknown','Paladin-Retribution','Priest-Shadow','Priest-Discipline','Shaman-Restoration','Shaman-Elemental','Warlock-Demonology','Evoker-Preservation','Shaman-Enhancement','Druid-Guardian','Rogue-Outlaw','Warrior-Fury','Warrior-Arms','DemonHunter-Devourer','Mage-Frost','Druid-Feral','Monk-Windwalker','Hunter-Marksmanship','Priest-Holy','Monk-Brewmaster','DeathKnight-Unholy','Warlock-Destruction','Evoker-Augmentation','Monk-Mistweaver','Mage-Arcane','Druid-Restoration','Warlock-Affliction','Hunter-BeastMastery','Evoker-Devastation','Rogue-Subtlety','Warrior-Protection','DeathKnight-Frost','DeathKnight-Blood','Druid-Balance','Paladin-Holy','Rogue-Assassination','Hunter-Survival','Mage-Fire',}
local provider = {region='US',realm='AzjolNerub',name='US',type='weekly',zone=46,date='2026-05-08',data={Ad='Adapt:BAAALgAECgMJCQAAAA==.Addy:BAABLgAECn8fAAMBAAgJWBewDAC2AQABAAgJWBewDAC2AQACAAEJQggMIQAnAAAAAA==.',
Ae='Aeonis:BAAALgAECgIJAwAAAA==.Aestian:BAABLgAECn8hAAIDAAgJzhiuCADAAQADAAgJzhiuCADAAQAAAA==.',
Ag='Agamesh:BAAALgADCgUJCQAAAA==.',
Ah='Ahoma:BAAALgADCgkJBgAAAA==.',
Ai='Ailysely:BAAALgADCgEJAQABLgAECgIJAwAEAAAAAA==.Airees:BAABLgAECn8iAAIFAAcJNh7lQQAfAgAFAAcJNh7lQQAfAgAAAA==.Aispere:BAAALgAECgMJAwAAAA==.',
Al='Alastria:BAAALgADCgcJBwAAAA==.Alektra:BAAALgADCgUJBwAAAA==.Alerzhulan:BAAALgAECggJCwAAAA==.Allanquatre:BAAALgADCgEJAQABLgADCggJCQAEAAAAAA==.Alledria:BAABLgAECn8ZAAIFAAcJchQwQgB/AQAFAAcJchQwQgB/AQAAAA==.Allenaena:BAAALgAECgMJBgAAAA==.Alorely:BAABLgAECn8TAAMGAAcJ4Ag9KAAFAQAGAAcJ4Ag9KAAFAQAHAAUJqwojNQD7AAAAAA==.Altonas:BAAALgAECgMJAwAAAA==.',
Am='Amanara:BAAALgAECgIJAwAAAA==.Amillah:BAAALgAECgMJBAAAAA==.',
An='Anciientpaw:BAABLgAECn8iAAMIAAkJGyBmHQAvAgAIAAkJGyBmHQAvAgAJAAUJaBVRLwD3AAAAAA==.Andramalyus:BAABLgAECn8bAAIKAAcJmgzMUwAwAQAKAAcJmgzMUwAwAQAAAA==.Andrasomnium:BAAALgADCgYJCwAAAA==.Angbar:BAABLgAECn8jAAILAAgJsBQMCADrAQALAAgJsBQMCADrAQAAAA==.Anguirus:BAABLgAECn8fAAMJAAgJMARoUAAFAQAJAAgJMARoUAAFAQAMAAQJ4ADhHwA0AAAAAA==.Animà:BAAALgAECgYJDwAAAA==.Ankhnstein:BAAALgAECgQJBAAAAA==.Antoine:BAAALgAECgIJAgAAAA==.',
Ap='Apolloni:BAAALgAECgIJAgABLgAECggJHQANAC8GAA==.Appynoxusrog:BAABLgAECn8cAAIOAAYJuhgsBQCcAQAOAAYJuhgsBQCcAQAAAA==.',
Aq='Aqulenas:BAAALgAECggJDAAAAA==.',
Ar='Arakhan:BAAALgAECgQJBAAAAA==.Arasaka:BAAALgAECgQJCAAAAA==.Arcadian:BAABLgAECn8iAAMPAAgJ5BSgMQDmAQAPAAgJ5BSgMQDmAQAQAAEJzAfQRAAvAAAAAA==.Arcadiann:BAAALgAECgQJBwAAAA==.Arcadin:BAAALgAECgEJAgAAAA==.Arextheelder:BAAALgAECgEJAQAAAA==.Aridas:BAABLgAECn8dAAMRAAgJ5RdmMwAsAgARAAgJ5RdmMwAsAgABAAIJRQsEYABiAAAAAA==.Arikdeath:BAAALgAECgYJDQAAAA==.Armorscales:BAACLgAFFH8LAAIKAAQJ9xEjPgDgAAAKAAQJ9xEjPgDgAAAuAAQKfysAAgoACAmVIlgQAPcCAAoACAmVIlgQAPcCAAAA.Arntraz:BAAALgADCgkJIQAAAA==.Arçadia:BAAALgAECgMJAwAAAA==.',
As='Ashegen:BAAALgAECgQJBAAAAA==.Ashnikko:BAAALgAECgEJAQAAAA==.Ashtori:BAAALgADCgEJAgAAAA==.Astrine:BAACLgAFFH8NAAISAAQJmBnHRAAAAQASAAQJmBnHRAAAAQAuAAQKfykAAhIACAklIgIiAOsCABIACAklIgIiAOsCAAAA.',
Au='Auberon:BAABLgAECn8jAAITAAgJcBt5BgCSAgATAAgJcBt5BgCSAgAAAA==.Aufta:BAABLgAECn8iAAIUAAgJzQVLIgAVAQAUAAgJzQVLIgAVAQAAAA==.',
Az='Azdh:BAAALgAECgQJBgAAAA==.Azi:BAACLgAFFH8UAAIVAAUJoBu1BwBFAQAVAAUJoBu1BwBFAQAuAAQKfyMAAhUACQm4HnIUAJACABUACQm4HnIUAJACAAAA.Azshanorel:BAAALgADCgcJBwAAAA==.Azunea:BAAALgAECgIJBwAAAA==.Azurite:BAAALgADCgYJCQAAAA==.',
Ba='Backpedal:BAAALgAECgYJDwAAAA==.Badankhadonk:BAACLgAFFH8OAAIIAAQJuCMJCACXAQAIAAQJuCMJCACXAQAuAAQKfysAAggACAnaJVICAF8DAAgACAnaJVICAF8DAAAA.Balen:BAABLgAECn8hAAIDAAcJjhXGCwCAAQADAAcJjhXGCwCAAQAAAA==.Bandrösh:BAAALgADCgMJAwAAAA==.Barradune:BAAALgADCgYJDAAAAA==.',
Be='Belholy:BAABLgAECn8UAAIWAAYJDCJLCgBDAgAWAAYJDCJLCgBDAgAAAA==.Beliice:BAAALgADCgkJGAABLgAECgYJFAAWAAwiAA==.Bellanei:BAAALgAECgEJAgAAAA==.Ben:BAAALgAECgEJAQAAAA==.Benafflockk:BAAALgADCggJCAAAAA==.Benefitdruid:BAAALgAECgEJAQAAAA==.Benilok:BAACLgAFFH8KAAIKAAQJ9x3OFABjAQAKAAQJ9x3OFABjAQAuAAQKfykAAgoACAlEJSEMABkDAAoACAlEJSEMABkDAAAA.Bethgibbons:BAAALgADCgkJGgAAAA==.',
Bi='Bibimbap:BAAALgAECgEJAQAAAA==.Bigsuccubus:BAAALgAECgYJDwAAAA==.Biohazard:BAAALgADCgUJBQAAAA==.Bizël:BAAALgAECgQJBAAAAA==.',
Bl='Blackblood:BAABLgAECn8XAAIBAAgJUQ6mEAB6AQABAAgJUQ6mEAB6AQAAAA==.Blackclouds:BAAALgADCgkJCQAAAA==.Blackspiral:BAAALgADCgEJAQAAAA==.Bladestriker:BAAALgAECgEJAQAAAA==.Blindside:BAAALgAECgMJAwAAAA==.Bloodache:BAABLgAECn8VAAIRAAcJNyFbKQBcAgARAAcJNyFbKQBcAgAAAA==.Bloodkissed:BAAALgADCgUJBgABLgAECggJJwAWAKofAA==.Bluebuberry:BAAALgAECgQJBgAAAA==.Bluesaphire:BAAALgAECgIJAgABLgAECgYJDwAEAAAAAA==.Blux:BAAALgAECgIJBAAAAA==.',
Bo='Boil:BAABLgAECn8UAAIOAAcJ+AQgCQDtAAAOAAcJ+AQgCQDtAAAAAA==.Bonemarrow:BAAALgAECgQJEQAAAA==.Bournx:BAAALgADCgcJBwAAAA==.Boysenbar:BAAALgADCgYJCAAAAA==.',
Br='Bradrenna:BAABLgAECn82AAQCAAkJyBcHBgA5AgACAAkJyBcHBgA5AgABAAEJsRHHOwA8AAARAAEJpQG79AAbAAAAAA==.Braké:BAABLgAECn8XAAIDAAgJ6BqlBAA2AgADAAgJ6BqlBAA2AgAAAA==.Breakthrough:BAAALgAECgYJDAAAAA==.Brenzull:BAAALgADCgYJCwAAAA==.Brewskies:BAABLgAECn8mAAIXAAcJACV8BQCJAgAXAAcJACV8BQCJAgAAAA==.Brewsli:BAAALgADCgIJAgABLgAECgcJFwAYAAsMAA==.Brightstar:BAAALgAECgcJEwAAAA==.Brokenaltar:BAABLgAECn8VAAMBAAYJNRhZOQAdAQARAAYJgRFYcwBLAQABAAUJCRpZOQAdAQAAAA==.Brownington:BAABLgAECn8YAAINAAcJVSRAAwBlAgANAAcJVSRAAwBlAgAAAA==.Bruhilda:BAAALgAECgYJDgAAAA==.Brymstone:BAAALgAECgQJBwAAAA==.Brynthebuff:BAAALgAECgEJAQAAAA==.Brìonik:BAACLgAFFH8VAAMKAAUJLx1iGwBGAQAKAAUJmxliGwBGAQAZAAMJNBhnDACpAAAuAAQKfyQAAxkACQmuIYoNAOwBABkABgksIYoNAOwBAAoABQkeI1Q6AH0BAAAA.',
Bu='Bufferfish:BAABLgAECn8pAAIaAAgJLAuoHgBKAQAaAAgJLAuoHgBKAQAAAA==.',
Ca='Calinnea:BAAALgAECgcJCAAAAA==.Cantheartitz:BAAALgAECgUJEQAAAA==.Catastrophe:BAAALgAECgYJEwAAAA==.',
Ce='Celthol:BAAALgAECgUJCwAAAA==.',
Ch='Chelraani:BAABLgAECn8fAAIFAAcJKCApGQAyAgAFAAcJKCApGQAyAgAAAA==.Chiichard:BAAALgADCgYJCgAAAA==.Chipnuts:BAABLgAECn8aAAIUAAgJTiXAAgBtAwAUAAgJTiXAAgBtAwAAAA==.Chonchoo:BAAALgADCgEJAQAAAA==.Chosethebear:BAAALgADCgkJEAAAAA==.',
Cl='Clarabellax:BAAALgAECgQJBQAAAA==.Clarkkentt:BAAALgADCgcJDQAAAA==.Claymore:BAACLgAFFH8KAAIPAAQJ8xS1DwAyAQAPAAQJ8xS1DwAyAQAuAAQKfxUAAg8ACAkMGcgcAGcCAA8ACAkMGcgcAGcCAAAA.Clazzicola:BAACLgAFFH8MAAMbAAQJFA7kEQAMAQAbAAQJFA7kEQAMAQAUAAMJJgu6DQCWAAAuAAQKfx8ABBQACQmbFloeAOUBABQABwlYHFoeAOUBABsACAnmEYQmAH8BABcAAQlhA8mVAB8AAAAA.Cloudbeast:BAAALgAECgEJAQABLgAECgQJDQAEAAAAAA==.Clue:BAAALgADCgYJBgAAAA==.',
Co='Conjredcukee:BAAALgAECgYJEQAAAA==.Coo:BAAALgAECgQJBAABLgAECgUJBwAEAAAAAA==.Coogsayer:BAABLgAECn8UAAIGAAcJxh2UEQBxAgAGAAcJxh2UEQBxAgAAAA==.',
Cp='Cptncrush:BAABLgAECn8XAAMIAAgJPhfbFAANAgAIAAgJPhfbFAANAgAJAAMJnhf+bwCDAAAAAA==.',
Cr='Croquetica:BAAALgADCgMJBAAAAA==.Crossed:BAAALgADCgcJCwAAAA==.Crowshadow:BAAALgAECgUJCwAAAA==.',
Cy='Cyther:BAACLgAFFH8ZAAIPAAUJCiIRAwCcAQAPAAUJCiIRAwCcAQAuAAQKfyMAAg8ACQmMIq0HAC4DAA8ACQmMIq0HAC4DAAAA.',
['Cÿ']='Cÿthera:BAABLgAECn8aAAIRAAgJUB+/HAClAgARAAgJUB+/HAClAgAAAA==.',
Da='Dakk:BAABLgAECn84AAIYAAkJZiD6CADOAgAYAAkJZiD6CADOAgAAAA==.Daraghor:BAABLgAECn8aAAINAAgJjCMMAgAbAwANAAgJjCMMAgAbAwAAAA==.Darkenstormy:BAAALgAECgYJDAAAAA==.Darlyndra:BAAALgADCgUJBQAAAA==.Darsae:BAAALgAECgQJDAAAAA==.Darthiono:BAAALgAECgEJAQAAAA==.',
De='Deadlight:BAABLgAECn8vAAIYAAkJfRGmIAAGAgAYAAkJfRGmIAAGAgAAAA==.Deathkillhun:BAAALgAECgQJBwAAAA==.Deathpooch:BAAALgADCgkJDwAAAA==.Deathshooter:BAAALgAECgcJAQAAAA==.Deavant:BAAALgADCgMJAwAAAA==.Deermon:BAAALgAECgYJCwAAAA==.Deet:BAAALgAECgUJBQAAAA==.Deforest:BAAALgADCgcJFgAAAA==.Deity:BAABLgAECn8bAAIPAAYJVh+NJAAyAgAPAAYJVh+NJAAyAgAAAA==.Demogon:BAAALgAECgQJBwAAAA==.Demondeano:BAABLgAECn8bAAIRAAkJBxOsIQC+AQARAAkJBxOsIQC+AQAAAA==.Demonlxl:BAAALgAECgEJAQAAAA==.Demonx:BAABLgAECn8hAAIYAAkJFRfRFgBFAgAYAAkJFRfRFgBFAgAAAA==.Desolation:BAABLgAECn8vAAIcAAgJzyRcAABRAwAcAAgJzyRcAABRAwAAAA==.Despia:BAABLgAECn8aAAIWAAcJkCRfBADQAgAWAAcJkCRfBADQAgAAAA==.Devastacia:BAAALgADCgUJBQAAAA==.Deviarc:BAAALgAECgQJBAAAAA==.',
Dh='Dharkon:BAAALgAECgIJBAAAAA==.',
Di='Dicot:BAABLgAECn8gAAIdAAcJ+g8zMwBPAQAdAAcJ+g8zMwBPAQAAAA==.',
Dj='Djpallyd:BAAALgAECgkJEAAAAA==.',
Do='Doinks:BAAALgAECgIJAgAAAA==.Domilthri:BAABLgAECn8sAAMeAAgJwQpEEAAqAQAKAAgJwQprVAAuAQAeAAYJ8gVEEAAqAQAAAA==.Dotdaddy:BAAALgAECgQJBwABLgAECgcJCAAEAAAAAA==.',
Dr='Dracoly:BAAALgAECggJEgAAAA==.Draconu:BAACLgAFFH8RAAIaAAQJpxWfEgBCAQAaAAQJpxWfEgBCAQAuAAQKfxsAAxoACQkjG8gKAMkCABoACQkjG8gKAMkCAAsAAQmaAXZOACIAAAAA.Draenyth:BAAALgAECgEJAQAAAA==.Dragoncurry:BAAALgAECgQJEgAAAA==.Dragonmite:BAAALgAECgEJAQAAAA==.Drakka:BAAALgADCgkJDgABLgAECgQJCAAEAAAAAA==.Draktyr:BAACLgAFFH8GAAIPAAMJtRZPGgDjAAAPAAMJtRZPGgDjAAAuAAQKfyQAAg8ACQn1HnkJABYDAA8ACQn1HnkJABYDAAAA.Dropeadita:BAAALgAECgQJBAAAAA==.Droptop:BAAALgADCgcJCAAAAA==.',
Du='Dumbsht:BAABLgAECn8ZAAMVAAgJ5Ra6MQCpAQAVAAcJ6RW6MQCpAQAfAAYJUBHiXQBOAQAAAA==.',
Ea='Easystreet:BAAALgAECgIJAwAAAA==.',
Ef='Effluv:BAAALgADCgcJDgAAAA==.',
El='Elandir:BAAALgADCgQJAQAAAA==.Elanora:BAAALgAECgYJCQAAAA==.Elbrookel:BAAALgAECgIJAgAAAA==.Eleshnorn:BAAALgAECgMJBwAAAA==.Eliza:BAAALgADCgkJCQAAAA==.Ellismom:BAABLgAECn8nAAIYAAgJ3RrbIQD/AQAYAAgJ3RrbIQD/AQAAAA==.Elvea:BAABLgAECn8WAAMaAAcJ7RjrEADKAQAaAAcJ7RjrEADKAQAgAAEJ9QoQQgArAAABLgAFFAMJCAAhANYXAA==.',
Em='Emeralddemon:BAAALgAECgIJAgAAAA==.Emeraldshade:BAAALgADCgcJDwABLgAECgIJAgAEAAAAAA==.Emeråld:BAAALgAECgMJAwAAAA==.',
En='Enamorada:BAAALgAECgIJAgABLgAECgYJDwAEAAAAAA==.',
Er='Ereithelda:BAACLgAFFH8VAAIbAAUJFhZiCgB3AQAbAAUJFhZiCgB3AQAuAAQKfyEAAhsACAnDIhUHAOkCABsACAnDIhUHAOkCAAAA.Ericka:BAAALgADCgQJBQAAAA==.Erreya:BAAALgADCgEJAQAAAA==.',
Es='Esma:BAAALgADCgkJCQAAAA==.',
Ev='Evox:BAAALgAECgYJDQAAAA==.',
Ey='Eyris:BAAALgADCgMJAwAAAA==.Eyrndor:BAAALgADCgIJAwAAAA==.',
Fa='Faacee:BAAALgAECgIJAgAAAA==.Fann:BAABLgAECn8VAAIdAAcJyAQKVQDEAAAdAAcJyAQKVQDEAAAAAA==.Faytl:BAAALgAECgEJAQAAAA==.',
Fe='Felbubu:BAABLgAECn8iAAQCAAkJlSIeBACAAgACAAkJKSIeBACAAgABAAYJOyAjIgCrAQARAAMJNRxQWADzAAAAAA==.Femboy:BAAALgAECgUJDAAAAA==.Fewz:BAACLgAFFH8JAAISAAQJihKASwDyAAASAAQJihKASwDyAAAuAAQKfx0AAhIACAnTICowALICABIACAnTICowALICAAAA.',
Fi='Fireybuns:BAAALgAECgEJAwAAAA==.',
Fl='Flaccid:BAABLgAECn8gAAIfAAgJbBhGGgABAgAfAAgJbBhGGgABAgAAAA==.Flakiron:BAACLgAFFH8QAAIiAAQJrhN1CAAmAQAiAAQJrhN1CAAmAQAuAAQKfysAAiIACAmGHJQLAFUCACIACAmGHJQLAFUCAAAA.Flakov:BAAALgAECgIJAgABLgAFFAQJEAAiAK4TAA==.Flaktop:BAAALgAECgIJAgABLgAFFAQJEAAiAK4TAA==.Fler:BAAALgAECgQJBgAAAA==.',
Fo='Forbacon:BAABLgAECn8XAAMYAAcJCwxTawAMAQAYAAYJgAlTawAMAQAjAAcJmQrZCgDkAAAAAA==.Force:BAABLgAECn8WAAQjAAgJewgUDgDHAAAjAAUJPwwUDgDHAAAYAAUJEATAmACvAAAkAAEJ4QBLQQAVAAAAAA==.Fornost:BAAALgADCgkJCQAAAA==.Fourdragon:BAAALgADCgQJBAABLgAECggJFwAJACMXAA==.Fouris:BAABLgAECn8XAAIJAAgJIxcwEQDWAQAJAAgJIxcwEQDWAQAAAA==.',
Fr='Fremosth:BAAALgADCgMJAwAAAA==.Fretman:BAAALgADCgcJCQAAAA==.Fridgie:BAACLgAFFH8TAAIfAAUJIhY0BABdAQAfAAUJIhY0BABdAQAuAAQKfyMAAh8ACQm7Im4PAMACAB8ACQm7Im4PAMACAAAA.Frostreaper:BAAALgAECgIJAgAAAA==.Frozenflyer:BAAALgAECgUJEAAAAA==.Frozenturtle:BAAALgAECggJEQAAAA==.',
Ft='Ftwiamtank:BAAALgAECgYJBgAAAA==.',
Fu='Fuoco:BAAALgAECgkJCgAAAA==.',
Ga='Gabriél:BAAALgAECgYJBwAAAA==.Garcutt:BAACLgAFFH8YAAISAAUJUhUGKABYAQASAAUJUhUGKABYAQAuAAQKfyUAAhIACQmKHek2AJgCABIACQmKHek2AJgCAAAA.Gaurdinn:BAABLgAECn8mAAQgAAgJ7w8MCQAXAQAgAAYJfxAMCQAXAQAaAAcJkw5wKAAOAQALAAIJagLPJwA3AAAAAA==.',
Ge='Gebuss:BAAALgADCgQJBAAAAA==.Generickmonk:BAACLgAFFH8LAAIUAAQJ5xddDAASAQAUAAQJ5xddDAASAQAuAAQKfyoAAhQACQlCIvoIAOgCABQACQlCIvoIAOgCAAAA.Gensis:BAAALgADCgYJBgAAAA==.Geomatic:BAAALgAECgEJAQAAAA==.Gethsemåne:BAAALgADCgMJBQAAAA==.',
Gi='Giovannucci:BAAALgAECgEJAgAAAA==.Gitan:BAAALgADCgQJBQAAAA==.',
Gl='Gladstone:BAAALgAECgYJCQAAAA==.',
Go='Gomlvirgin:BAAALgADCgYJBgABLgAECggJIgAKAHQUAA==.',
Gr='Gracehimeûwû:BAAALgAFFAIJBAAAAA==.Grampsie:BAAALgAECgUJBwAAAA==.Grayeyes:BAAALgAECgMJAwAAAA==.Greenngoblin:BAAALgADCgEJAQAAAA==.Grimmlie:BAAALgADCgUJBQAAAA==.Grinzler:BAAALgADCgIJAgAAAA==.Grumpybear:BAAALgADCggJDwAAAA==.Grumpykat:BAAALgAECggJEgAAAA==.Grumpypros:BAAALgADCgUJBQAAAA==.',
Gt='Gtatedk:BAAALgAECgcJBwAAAA==.',
Gu='Guino:BAAALgAECgMJAwAAAA==.Guinodruid:BAAALgADCgcJDgAAAA==.',
Gw='Gwenelly:BAAALgAECgEJAQAAAA==.',
Ha='Hamncheeks:BAAALgAECgEJAQAAAA==.Haptism:BAAALgADCgcJBwAAAA==.Hardeesdelux:BAAALgADCgYJBgABLgAECgQJDQAEAAAAAA==.Hardnarples:BAAALgADCgEJAQAAAA==.Hayzerade:BAAALgAECgMJAwAAAA==.Hazis:BAABLgAECn8rAAIkAAkJEyFMBAB4AgAkAAkJEyFMBAB4AgAAAA==.',
Hi='Hippiecritz:BAAALgADCgYJBwAAAA==.Hitokiri:BAAALgADCgMJAwAAAA==.',
Ho='Holy:BAACLgAFFH8QAAIDAAQJuAdUBQDDAAADAAQJuAdUBQDDAAAuAAQKfygAAgMACAkqF/IQALcBAAMACAkqF/IQALcBAAAA.Holydad:BAABLgAECn8fAAIDAAgJbxv5CQAxAgADAAgJbxv5CQAxAgAAAA==.Holydust:BAAALgAECgcJEQAAAA==.Holymoki:BAAALgADCgYJCgAAAA==.Holymoliie:BAAALgADCgEJAQAAAA==.Holyroundie:BAABLgAECn80AAIWAAkJ+AwfGgB7AQAWAAkJ+AwfGgB7AQAAAA==.Holyshock:BAACLgAFFH8ZAAIFAAUJzB5FCwB/AQAFAAUJzB5FCwB/AQAuAAQKfyMAAgUACQm/I9cOABcDAAUACQm/I9cOABcDAAAA.Holystax:BAAALgAECgEJAQAAAA==.Honeybutter:BAACLgAFFH8HAAMQAAMJ+x36AgAnAQAQAAMJ+x36AgAnAQAPAAEJCAkOIgBRAAAuAAQKfzIAAxAACQnhJT4AAHIDABAACQnhJT4AAHIDAA8ABwmLHtAjADgCAAAA.Hordebreaker:BAAALgAECgYJDwAAAA==.Hotflash:BAAALgAECgEJAQAAAA==.',
Hu='Huukend:BAABLgAECn8oAAIfAAgJFh8VDgBpAgAfAAgJFh8VDgBpAgAAAA==.',
Ic='Icebabyman:BAABLgAECn8fAAISAAgJER4FIwAbAgASAAgJER4FIwAbAgAAAA==.',
In='Inanitas:BAAALgADCgcJBwAAAA==.Ineffectual:BAABLgAECn8fAAIIAAgJuxMbMgC9AQAIAAgJuxMbMgC9AQAAAA==.',
Ir='Irukox:BAAALgAECgQJBwAAAA==.',
It='Itty:BAAALgADCgcJBwAAAA==.',
Ja='Jagger:BAAALgADCgcJCQAAAA==.Jalene:BAAALgAECgUJCAAAAA==.Janewayy:BAABLgAECn8lAAIRAAgJYg0tQgAyAQARAAgJYg0tQgAyAQAAAA==.',
Je='Jeks:BAAALgADCgcJBwABLgAFFAUJGAAIAAseAA==.Jemma:BAABLgAECn8bAAIZAAgJTA8uCABaAQAZAAgJTA8uCABaAQAAAA==.Jettadari:BAACLgAFFH8PAAIRAAUJoRcREABNAQARAAUJoRcREABNAQAuAAQKfyAAAxEACQn5HugWAM0CABEACQn5HugWAM0CAAIAAQkmDi4fADAAAAAA.Jettadin:BAABLgAECn8aAAIFAAgJ9SGjDwARAwAFAAgJ9SGjDwARAwABLgAFFAUJDwARAKEXAA==.Jettathyr:BAAALgAECgcJDQABLgAFFAUJDwARAKEXAA==.',
Ju='Jubba:BAAALgAECggJEwAAAA==.Juderius:BAAALgADCgIJAgABLgAECgMJAwAEAAAAAA==.Junk:BAAALgAECgYJCQABLgAECgcJJgAXAAAlAA==.',
['Jë']='Jëks:BAACLgAFFH8YAAIIAAUJCx7TBwCZAQAIAAUJCx7TBwCZAQAuAAQKfyMAAwgACQlgJXEDAEEDAAgACQlgJXEDAEEDAAwAAgksDrcYAHQAAAAA.',
Ka='Kahea:BAAALgAECgQJBAAAAA==.Kaing:BAABLgAECn8cAAMUAAcJqiR5DADxAQAUAAcJqiR5DADxAQAbAAEJkw2TbAApAAAAAA==.Kaitou:BAABLgAECn8vAAMTAAkJZx+4AQC5AgATAAkJZx+4AQC5AgAlAAEJrQ5BVgA2AAAAAA==.Kalamiti:BAAALgAECgYJDgAAAA==.Kallar:BAABLgAECn8nAAIWAAgJqh/6BAC7AgAWAAgJqh/6BAC7AgAAAA==.Karesh:BAAALgAECgQJBAAAAA==.Kayeera:BAAALgAECgYJEwAAAA==.Kayha:BAAALgADCgYJBwAAAA==.Kaylrandi:BAAALgADCgQJBwAAAA==.Kaztiel:BAAALgAECgIJAgAAAA==.',
Ke='Keadon:BAAALgAECgYJDgAAAA==.Keeper:BAAALgADCgMJAwABLgAECgYJGwAPAFYfAA==.Keh:BAAALgADCgkJCQAAAA==.Kennethv:BAAALgAECgQJBQAAAA==.Kenze:BAAALgAECgEJAQAAAA==.Kethra:BAAALgADCgcJDAAAAA==.Kev:BAAALgAECgcJAgAAAA==.',
Kh='Khel:BAAALgADCgcJBwAAAA==.Khibanee:BAAALgADCgQJBAAAAA==.Khiell:BAACLgAFFH8HAAIPAAQJFgzYEwAUAQAPAAQJFgzYEwAUAQAuAAQKfxgAAg8ACQk8F1wfAFYCAA8ACQk8F1wfAFYCAAAA.',
Ki='Kilyse:BAAALgADCgYJBgAAAA==.Kinigit:BAAALgAECgQJBwABLgAFFAQJEAAlALETAA==.Kirïtö:BAAALgAECgUJCwAAAA==.Kitarah:BAEALgAECgIJAgABLgAECgcJCAAEAAAAAA==.Kitarazen:BAEALgAECgcJCAAAAA==.Kizli:BAAALgADCgUJBQABLgAECggJIgAWAFIjAA==.',
Ko='Kokushimosu:BAAALgAECgQJCwAAAA==.Koo:BAAALgAECgUJBwAAAA==.',
Kr='Krátos:BAAALgAECggJDwABLgAECggJHQARAOUXAA==.',
Ks='Ksper:BAAALgAECgcJEAAAAA==.',
Ku='Kukalak:BAABLgAECn8YAAIiAAgJ5xuxCgDCAQAiAAgJ5xuxCgDCAQAAAA==.Kuranaa:BAAALgADCggJEwABLgAECgMJAwAEAAAAAA==.Kurulak:BAABLgAECn8cAAIRAAgJRg5NPABGAQARAAgJRg5NPABGAQAAAA==.',
Ky='Kymru:BAAALgADCgcJDQAAAA==.',
['Ké']='Kénnéth:BAAALgAECgYJDQAAAA==.',
La='Lacerveza:BAAALgAECgIJBQAAAA==.Lahyanhou:BAABLgAECn8kAAIVAAgJ4AUGDQAcAQAVAAgJ4AUGDQAcAQAAAA==.Lalalalala:BAAALgAECgcJCgAAAA==.Lalin:BAAALgAECgEJAwAAAA==.Larkwyn:BAAALgAECgQJBAABLgAECgcJHgAKAAAXAA==.Laylah:BAAALgADCgYJBAAAAA==.',
Le='Lebrand:BAAALgAECgEJAQAAAA==.Leriope:BAABLgAECn8vAAIKAAgJsw4lOgB+AQAKAAgJsw4lOgB+AQAAAA==.',
Li='Lichfiend:BAAALgADCgEJAQAAAA==.Lightbeer:BAAALgAECgYJBwAAAA==.Lihplock:BAAALgAECgQJCAABLgAFFAMJCgAPAAEkAA==.Lildragonboi:BAAALgADCgUJBQAAAA==.Lilem:BAAALgADCgcJEgAAAA==.Listenlinda:BAAALgAECgEJAQAAAA==.Littlemerald:BAAALgAECgQJBwAAAA==.',
Lj='Lj:BAABLgAECn8nAAImAAgJnB4VCQCAAgAmAAgJnB4VCQCAAgAAAA==.',
Lo='Localsingles:BAAALgADCgcJBwAAAA==.Lorath:BAAALgADCgEJAQAAAA==.Lovecrafft:BAAALgAECgEJAQAAAA==.',
Lu='Lu:BAAALgAFFAIJAwABLgAFFAQJDAAbABQOAA==.Lucinà:BAABLgAECn8qAAQmAAgJeh6TDAC1AgAmAAgJeh6TDAC1AgAFAAgJsCGxDACcAgADAAUJiR3ADgBMAQAAAA==.Lusande:BAAALgAECgQJBQAAAA==.Luxure:BAAALgAECgYJBgAAAA==.',
Ly='Lyndall:BAAALgAECgQJBgAAAA==.',
Ma='Madammìm:BAAALgADCgEJAQAAAA==.Maegan:BAAALgAECgIJAgAAAA==.Mager:BAAALgAECgIJAwAAAA==.Magerhunter:BAAALgADCgYJBwAAAA==.Magolock:BAAALgAECgQJCAAAAA==.Mahll:BAAALgADCgcJCQAAAA==.Maidrim:BAACLgAFFH8RAAInAAUJ1B1PAQCLAQAnAAUJ1B1PAQCLAQAuAAQKfxkAAicACQmtIfECALICACcACQmtIfECALICAAAA.Makavelli:BAAALgADCgEJAQAAAA==.Mamajumbo:BAAALgAECgYJDQAAAA==.Marage:BAAALgADCgEJAQAAAA==.Marellias:BAAALgAECgMJAwABLgAECggJIwAFACokAA==.Marikel:BAAALgAECgMJAwAAAA==.Markwel:BAAALgAECgIJAgAAAA==.Marrack:BAAALgAECgYJDQAAAA==.',
Me='Melador:BAAALgADCgIJAgAAAA==.Meletha:BAAALgAECgYJCQAAAA==.Melpuis:BAAALgAECgEJAgAAAA==.Metahorfasis:BAAALgAECgMJAwAAAA==.',
Mi='Michaelken:BAABLgAECn8WAAImAAgJgxVnFQDlAQAmAAgJgxVnFQDlAQAAAA==.Mierín:BAAALgADCgYJBgAAAA==.Migrains:BAABLgAECn8vAAIDAAgJGiMPAgClAgADAAgJGiMPAgClAgAAAA==.Mineo:BAAALgAECgYJBwAAAA==.Mirâjâne:BAAALgAECgEJAQAAAA==.Miskaabin:BAABLgAECn8WAAIFAAcJ/wunUwBMAQAFAAcJ/wunUwBMAQAAAA==.Miststress:BAAALgAECgcJCAAAAA==.',
Mo='Mobal:BAABLgAECn8fAAMIAAgJMhqCHgAoAgAIAAgJMhqCHgAoAgAJAAIJqAXlaQAsAAAAAA==.Mojogreens:BAAALgAECgYJDAAAAA==.Montydh:BAAALgAECgEJAQAAAA==.Moonblades:BAAALgADCgUJBQAAAA==.Moonpetals:BAAALgAECgEJAQAAAA==.Moonrush:BAAALgAECgMJCAAAAA==.Mortiis:BAAALgAECgYJEwAAAA==.Motako:BAABLgAECn8gAAIIAAcJQiCfFQBoAgAIAAcJQiCfFQBoAgAAAA==.',
Mp='Mpd:BAAALgAECgYJCwAAAA==.',
My='Mybizël:BAABLgAECn8iAAIfAAcJVBzoIABAAgAfAAcJVBzoIABAAgAAAA==.Myrlifax:BAAALgADCgEJAQABLgAECgQJCAAEAAAAAA==.Mystique:BAAALgAECgYJBwAAAA==.Mythdaraghma:BAAALgAECgQJBwAAAA==.',
['Má']='Máximo:BAAALgAECgYJEAAAAA==.',
['Mí']='Míerin:BAAALgAECgQJBAAAAA==.Míerín:BAACLgAFFH8MAAIoAAQJ7RjEBQBnAQAoAAQJ7RjEBQBnAQAuAAQKfyMAAygACAnUI74EAMcCACgACAnUI74EAMcCAB8ABAm+G0FgAEcBAAAA.',
Na='Naama:BAAALgADCgcJCgAAAA==.Nadaar:BAAALgAECgYJDQAAAA==.Naelih:BAABLgAECn8fAAIVAAgJlwetCwAyAQAVAAgJlwetCwAyAQAAAA==.Naharuk:BAAALgADCgMJAwAAAA==.Natholomas:BAAALgADCgQJBAAAAA==.Natlès:BAAALgAECgUJBgABLgAECgcJCAAEAAAAAA==.Nazeer:BAAALgADCgcJBwABLgAECgkJLgAdABoWAA==.Nazgrim:BAABLgAECn8uAAIdAAgJGhZYLwDvAQAdAAgJGhZYLwDvAQAAAA==.',
Ne='Necronu:BAAALgAFFAIJBAABLgAFFAQJEQAaAKcVAA==.',
Ni='Nikkolos:BAAALgAECgcJDwAAAA==.Ninjastax:BAAALgAECgEJAQAAAA==.Nissie:BAAALgAECgEJAQAAAA==.',
No='Nogusta:BAACLgAFFH8SAAIPAAUJwhteCABeAQAPAAUJwhteCABeAQAuAAQKfyMAAg8ACQmCHm4LAP8CAA8ACQmCHm4LAP8CAAAA.Norberta:BAAALgAECgcJEwAAAA==.Nossanir:BAAALgAECgIJAgAAAA==.Nossellia:BAAALgAECgQJBwAAAA==.',
Nu='Nurana:BAAALgADCgEJAQAAAA==.',
Ny='Nycecritz:BAAALgAECgEJAQAAAA==.',
Od='Odor:BAAALgAECgQJBgAAAA==.',
Ol='Oldie:BAAALgAECgIJAgAAAA==.Olielno:BAAALgADCgMJAwAAAA==.',
On='Onlyshams:BAABLgAECn8hAAIIAAgJshgxGQBNAgAIAAgJshgxGQBNAgAAAA==.Onlytides:BAEBLgAECn8aAAMIAAgJryPlBwD2AgAIAAgJryPlBwD2AgAJAAcJVBh8HwAUAgABLgAFFAUJFwAdAIMjAA==.Onubis:BAACLgAFFH8KAAMfAAMJaCIoDQD3AAAfAAMJex0oDQD3AAAoAAIJ5yAuEgDLAAAuAAQKfxwABB8ACAmXHw8MAOECAB8ACAmJHw8MAOECABUABgnGHco0AJcBACgAAQmkI/ExAGkAAAEuAAUUBAkRABoApxUA.Onulock:BAAALgAECgYJCgABLgAFFAQJEQAaAKcVAA==.Onux:BAABLgAFFH8FAAIRAAIJTw1nSwCLAAARAAIJTw1nSwCLAAABLgAFFAQJEQAaAKcVAA==.',
Op='Opgarbage:BAAALgAECgQJCAAAAA==.',
Ou='Oukei:BAAALgAECgcJEgABLgAFFAUJEQAEAAAAAQ==.Oumura:BAAALgAECgYJDgAAAA==.',
Ov='Overlordainz:BAAALgAECgUJDQAAAA==.',
Pa='Paarthürnax:BAAALgAECgYJDAAAAA==.Padamee:BAAALgAECgMJBgAAAA==.Pallyoop:BAABLgAECn8WAAImAAcJMw/mNAD4AAAmAAcJMw/mNAD4AAAAAA==.Pandaa:BAAALgAECgEJAQAAAA==.Papapaw:BAAALgAECgQJBgAAAA==.Patherion:BAAALgADCgEJAQABLgAECgYJCQAEAAAAAA==.Patholans:BAAALgAECgYJCQAAAA==.Pathology:BAAALgAECgMJAwABLgAECgYJCQAEAAAAAA==.Paxman:BAAALgAECgEJAQAAAA==.',
Pe='Peanits:BAAALgAECgQJCQABLgAECgkJIgACAJUiAA==.Peanutsuckr:BAACLgAFFH8ZAAIkAAUJ9iRTAwCvAQAkAAUJ9iRTAwCvAQAuAAQKfyMAAiQACQmoJEIEAAoDACQACQmoJEIEAAoDAAAA.Pearserve:BAAALgADCgYJBgABLgAECgcJEQAEAAAAAA==.',
Ph='Phantöm:BAAALgADCgQJBAAAAA==.Phosphate:BAABLgAECn8QAAIRAAYJNxKvbgBYAQARAAYJNxKvbgBYAQAAAA==.',
Pi='Piccolo:BAAALgADCgYJCQAAAA==.Pingg:BAAALgAECgQJBQAAAA==.Pinkeye:BAAALgAECgMJAwAAAA==.Pippafan:BAAALgAECgEJAQAAAA==.',
Pl='Planknstein:BAAALgADCgMJAwAAAA==.Playdohh:BAAALgAECgcJCQAAAA==.Plutonia:BAAALgAECgMJBwAAAA==.',
Po='Pockett:BAABLgAECn8VAAMJAAYJsQ21KwAJAQAMAAUJBQnoGwAMAQAJAAYJmw21KwAJAQAAAA==.Powrwordgoat:BAABLgAECn8oAAIHAAgJZxLHFACaAQAHAAgJZxLHFACaAQAAAA==.',
Pr='Prestoh:BAABLgAECn8cAAIJAAcJpxOfHQBhAQAJAAcJpxOfHQBhAQAAAA==.Prismclaw:BAABLgAECn8nAAISAAgJKQpJTgB/AQASAAgJKQpJTgB/AQAAAA==.Processing:BAAALgAECgYJBgAAAA==.',
Ps='Pseudoruski:BAAALgADCgMJAwAAAA==.',
Pu='Purplehaze:BAAALgADCggJEQAAAA==.',
Pv='Pvlolz:BAABLgAECn8YAAIWAAgJxApBMACAAQAWAAgJxApBMACAAQAAAA==.',
Qa='Qaharn:BAAALgAECgQJBwAAAA==.',
Qp='Qplus:BAABLgAECn8WAAIfAAgJ1QfmOgBhAQAfAAgJ1QfmOgBhAQAAAA==.',
Qu='Quaenie:BAABLgAECn8VAAIWAAgJ/hOXEgDLAQAWAAgJ/hOXEgDLAQAAAA==.Quintin:BAAALgAECgYJCwAAAA==.',
Ra='Raged:BAAALgAECgUJCgAAAA==.Ragetotem:BAABLgAECn8dAAIJAAYJmRwdKADSAQAJAAYJmRwdKADSAQAAAA==.Ragewarg:BAAALgAECgQJBAAAAA==.Ragnashock:BAAALgAECgQJBgAAAA==.Ralvarr:BAABLgAECn8UAAIbAAcJTBmgGwDbAQAbAAcJTBmgGwDbAQAAAA==.Raptorjésus:BAAALgADCgcJCwAAAA==.Rathaes:BAAALgADCgMJAwAAAA==.Ravenstryke:BAAALgAECgEJAQAAAA==.Raylea:BAAALgADCgcJBwAAAA==.Rayleigh:BAAALgAECgUJBwABLgAECgUJCwAEAAAAAA==.Razzgix:BAAALgAECgUJBgAAAA==.',
Re='Redchord:BAAALgADCgUJDAAAAA==.Regidør:BAABLgAECn8ZAAMmAAgJ/CBeCADoAgAmAAgJ/CBeCADoAgAFAAYJxx0YYQDBAQAAAA==.Relik:BAABLgAECn8XAAIiAAgJNQviEgA5AQAiAAgJNQviEgA5AQAAAA==.Resith:BAAALgAECgYJCAAAAA==.',
Rh='Rhaelia:BAABLgAECn8ZAAIFAAcJFQnYYwAmAQAFAAcJFQnYYwAmAQAAAA==.Rhaspus:BAAALgADCgQJBAAAAA==.',
Ri='Rilliccine:BAAALgADCgkJCQAAAA==.Rillinetti:BAABLgAECn8aAAIKAAgJHxKxKwC2AQAKAAgJHxKxKwC2AQAAAA==.Rillini:BAAALgADCgcJBwAAAA==.Rilliti:BAAALgAECgEJAQAAAA==.',
Ro='Rondon:BAABLgAECn8dAAIfAAcJcCXMCgCNAgAfAAcJcCXMCgCNAgAAAA==.Rookdh:BAACLgAFFH8HAAMBAAQJUQSaCAAOAQABAAQJUQSaCAAOAQARAAIJ2gFZVQBdAAAuAAQKfyMAAxEACQmWFR9VAKQBABEACAnDFh9VAKQBAAEABwkuFuIsAGMBAAAA.Rorcia:BAAALgADCgcJEwAAAA==.Rosey:BAABLgAECn8ZAAIFAAcJjA4kUwBNAQAFAAcJjA4kUwBNAQAAAA==.Roxania:BAAALgADCgYJBgAAAA==.Royale:BAAALgADCgUJBQAAAA==.',
Ru='Rudyeightbal:BAABLgAECn8aAAMKAAgJBwznVwAlAQAKAAYJhQ3nVwAlAQAZAAIJFQMRNgAAAAAAAA==.Ruedons:BAAALgAECgIJAgAAAA==.Rugsalon:BAACLgAFFH8IAAISAAMJCwn/TgDnAAASAAMJCwn/TgDnAAAuAAQKfyUAAhIACAmyHe40AJ8CABIACAmyHe40AJ8CAAAA.Rustedbarrel:BAACLgAFFH8FAAIXAAIJBQZLMwByAAAXAAIJBQZLMwByAAAuAAQKfxoAAhcACAm+E3MhAPYBABcACAm+E3MhAPYBAAAA.',
Ry='Ryptar:BAAALgADCgkJFgAAAA==.',
['Ré']='Réxxar:BAABLgAECn8cAAINAAcJPRTbDQClAQANAAcJPRTbDQClAQAAAA==.',
Sa='Saelyres:BAAALgAECggJEgAAAA==.Sagesse:BAAALgADCgYJBgAAAA==.Saikye:BAAALgAECgEJAQAAAA==.Sairu:BAAALgADCgEJAQAAAA==.Saisera:BAAALgADCgMJAwAAAA==.Samistraza:BAAALgADCgEJAQAAAA==.Sammy:BAABLgAECn8XAAIFAAgJoQdMZAAlAQAFAAgJoQdMZAAlAQAAAA==.Santaclaaws:BAACLgAFFH8KAAIRAAQJnxmSGQBDAQARAAQJnxmSGQBDAQAuAAQKfywABBEACAmjIjISAO0CABEACAmjIjISAO0CAAIAAwlPFuYPAMIAAAEAAgk1GYtbAHIAAAAA.Santapal:BAABLgAECn8iAAMmAAgJqhmPGgC1AQAmAAcJLxqPGgC1AQAFAAIJeAXP1ABbAAABLgAFFAQJCgARAJ8ZAA==.Santatumblr:BAAALgAECgYJDQABLgAFFAQJCgARAJ8ZAA==.Santhin:BAAALgADCgcJCgAAAA==.Saphira:BAAALgAECgQJBAAAAA==.Sareit:BAAALgAECgcJEAAAAA==.Sassee:BAAALgAECgQJCAAAAA==.Sayvil:BAAALgAECgUJCwABLgAECggJJwAWAKofAQ==.',
Sc='Scripture:BAAALgADCgYJBgAAAA==.',
Se='Seawolph:BAABLgAECn8eAAIIAAgJbhTEJwCAAQAIAAgJbhTEJwCAAQAAAA==.Selenia:BAAALgAECgMJAwAAAA==.Semmers:BAAALgADCgYJBgAAAA==.Sensational:BAABLgAECn8aAAMbAAcJWhx6EwAvAgAbAAcJWhx6EwAvAgAUAAUJXggQLwDKAAAAAA==.Sergio:BAAALgAECgcJCgAAAA==.',
Sh='Shamiska:BAAALgAECgIJAgAAAA==.Shammerdown:BAAALgAECgIJAwAAAA==.Shampooh:BAAALgADCgkJCQABLgAECgYJEwAEAAAAAA==.Shamtastyk:BAAALgAECgQJBAAAAA==.Shaokhan:BAABLgAECn8gAAIIAAkJgyHCAQBXAwAIAAkJgyHCAQBXAwAAAA==.Sheilla:BAAALgADCgUJBQAAAA==.Shian:BAABLgAECn8hAAINAAcJzxYcCQCTAQANAAcJzxYcCQCTAQAAAA==.Shieldee:BAABLgAECn8sAAIFAAgJbRuvGQAvAgAFAAgJbRuvGQAvAgAAAA==.Shlectrinell:BAABLgAECn8oAAMhAAgJHQuGEQCRAQAhAAgJjwqGEQCRAQAnAAgJBAUICwB+AQAAAA==.Shockeei:BAACLgAFFH8WAAISAAUJMiXTEQCfAQASAAUJMiXTEQCfAQAuAAQKfyMABBIACQlbJK4UACwDABIACQlbJK4UACwDACkAAwlSGHcJALkAABwAAQnWIK8KAGEAAAAA.Shocktroop:BAAALgADCgYJCgAAAA==.Shortdon:BAAALgADCgcJBwAAAA==.Shurp:BAAALgAECgMJAwAAAA==.',
Si='Siakora:BAABLgAECn8UAAIhAAcJUBsHGwAoAgAhAAcJUBsHGwAoAgABLgAFFAUJGAAlAN0bAA==.Sicksty:BAAALgADCgcJBwAAAA==.Sighh:BAAALgADCgMJAwAAAA==.Sighhy:BAAALgAECgMJCAAAAA==.Sijth:BAABLgAECn9DAAIFAAgJ0R/jEAB0AgAFAAgJ0R/jEAB0AgAAAA==.Silentchaos:BAAALgADCgMJBQAAAA==.Siler:BAAALgADCgYJBgAAAA==.Silverwar:BAABLgAECn8aAAIPAAcJBxrVEwDOAQAPAAcJBxrVEwDOAQAAAA==.Simmi:BAECLgAFFH8XAAIdAAUJgyMtBQDuAQAdAAUJgyMtBQDuAQAuAAQKfyMAAh0ACQmQJXMGACQDAB0ACQmQJXMGACQDAAAA.Sinnis:BAAALgAECgEJAQAAAA==.Sixtea:BAABLgAECn8cAAIJAAgJmxTgHQBfAQAJAAgJmxTgHQBfAQAAAA==.',
Sk='Skepti:BAABLgAECn8dAAIfAAgJ+hBYOABrAQAfAAgJ+hBYOABrAQAAAA==.Skysong:BAAALgAECgMJAwAAAA==.',
Sl='Slimfoo:BAAALgAECgcJDQAAAA==.Slunkyspit:BAAALgADCgUJCAAAAA==.Slybearclaw:BAAALgADCgUJBQAAAA==.',
Sm='Smeeta:BAABLgAECn9CAAQYAAkJwR/IBwDgAgAYAAkJwR/IBwDgAgAjAAMJ2B/ECAAUAQAkAAUJUBFgHQDXAAAAAA==.Smoak:BAAALgADCgUJBQAAAA==.Smolderlight:BAABLgAECn8sAAImAAkJ+xNAEAAcAgAmAAkJ+xNAEAAcAgAAAA==.Smoochiebutt:BAAALgAECgUJCQAAAA==.',
So='Solaace:BAAALgAECgEJAQABLgAECgIJAgAEAAAAAA==.Solo:BAAALgAECgYJCQAAAA==.Soloris:BAAALgADCgcJCAAAAA==.Sonja:BAAALgAECgcJBwAAAA==.Soram:BAAALgAECgYJCgAAAA==.Soulstryker:BAAALgAECgEJAQAAAA==.Soùl:BAAALgADCgQJBAAAAA==.',
Sp='Spacepants:BAAALgAECgEJAQAAAA==.',
St='Staraelle:BAAALgAECgEJAgAAAA==.Stazz:BAAALgAECgYJBgAAAA==.Steelerayne:BAAALgAECgYJDAAAAA==.Stormii:BAAALgAECgIJAgAAAA==.Strangerdk:BAABLgAECn8fAAIYAAgJGwf+TwBMAQAYAAgJGwf+TwBMAQAAAA==.Streetdog:BAAALgADCgYJBgAAAA==.',
Su='Superfatbaby:BAAALgAECgcJEQAAAA==.',
Sw='Swikk:BAAALgADCgYJCAAAAA==.Swishersweet:BAABLgAECn8dAAINAAgJLwbgHgCpAAANAAgJLwbgHgCpAAAAAA==.Swordfish:BAABLgAECn8XAAIgAAYJdB6DBACqAQAgAAYJdB6DBACqAQAAAA==.',
Sy='Syannae:BAAALgADCgQJBAAAAA==.Sybros:BAAALgADCgEJAQAAAA==.Sydonie:BAAALgAECgEJAwAAAA==.Symbah:BAAALgADCgYJBgAAAA==.Synvalid:BAABLgAECn8ZAAIRAAkJswcZSAAgAQARAAkJswcZSAAgAQAAAA==.Syzrin:BAAALgADCgEJAQABLgAECggJIgAKAHQUAA==.',
Ta='Tabmage:BAABLgAECn8sAAISAAgJyRrYHgAxAgASAAgJyRrYHgAxAgAAAA==.Tadokof:BAAALgADCgQJBAAAAA==.Talanth:BAAALgAECggJDQAAAA==.Tandisong:BAAALgAECgEJAQAAAA==.Tanknhammerm:BAAALgADCgYJBgAAAA==.Tanknstein:BAAALgADCgYJBgAAAA==.Tanton:BAAALgAECgMJAwAAAA==.Tanzil:BAAALgAECgYJDgAAAA==.Tardigrade:BAAALgAECggJDwAAAA==.Tareyna:BAAALgAECggJCAAAAA==.Tayon:BAAALgAECgYJDQAAAA==.Tayvin:BAAALgADCgcJDQAAAA==.Tazanath:BAAALgADCgEJAQAAAA==.',
Te='Tempest:BAAALgADCgcJBwAAAA==.Tengen:BAAALgAECgUJDAAAAA==.Termana:BAACLgAFFH8aAAIiAAUJdyMnAwCWAQAiAAUJdyMnAwCWAQAuAAQKfyIAAiIACQmSI4QCAEMDACIACQmSI4QCAEMDAAAA.',
Th='Tharja:BAABLgAECn8aAAISAAgJLB3pNACfAgASAAgJLB3pNACfAgAAAA==.Thornp:BAAALgAECgEJAgAAAA==.Thoronk:BAAALgAECgcJBgAAAA==.Thsaric:BAAALgAECgEJAQAAAA==.Thug:BAABLgAECn8WAAMPAAcJ0R/QJQArAgAPAAcJ0R/QJQArAgAiAAIJHxvONgCRAAAAAA==.',
Ti='Tiferet:BAABLgAECn8gAAQWAAgJ/R9HBADTAgAWAAgJ/R9HBADTAgAHAAMJfRLnPgC3AAAGAAIJwgWMVwAsAAAAAA==.Tigiw:BAAALgADCgcJDAAAAA==.Tinysunshine:BAAALgAECgYJCgAAAA==.Tinyt:BAAALgAECgEJAQAAAA==.Tismyhammer:BAAALgADCgQJBAAAAA==.',
To='Toasted:BAAALgADCgQJAQAAAA==.Tolenkar:BAABLgAECn8XAAIfAAgJoxoMFwAXAgAfAAgJoxoMFwAXAgAAAA==.Tomato:BAACLgAFFH8SAAMZAAUJ1A7SBwDxAAAZAAMJXw3SBwDxAAAKAAQJZxAnQgDXAAAuAAQKfyMAAxkACQlpHaYFAHoCABkACAkIHKYFAHoCAAoABQlZFzpXACcBAAAA.Tomhanks:BAAALgAECgQJCAAAAA==.Tormentaa:BAAALgAECgYJBwAAAA==.Torvalar:BAABLgAECn8xAAIFAAgJdxOYMQC2AQAFAAgJdxOYMQC2AQAAAA==.',
Tr='Treemendous:BAAALgADCgYJCQAAAA==.Truthslayer:BAABLgAECn8VAAMPAAkJ7AW6MgAAAQAPAAkJ7AW6MgAAAQAQAAEJbAr8QgAzAAAAAA==.Trûth:BAABLgAECn8WAAIGAAgJvBBIIwC9AQAGAAgJvBBIIwC9AQAAAA==.',
Tu='Turdyl:BAABLgAECn8kAAIFAAkJTg+GcwCUAQAFAAkJTg+GcwCUAQAAAA==.',
Tw='Twindad:BAAALgADCgkJEQAAAA==.Twindadlock:BAAALgADCgEJAQAAAA==.',
Ty='Tyraz:BAAALgAECgcJEwAAAA==.Tystrolf:BAAALgAECgcJEQAAAA==.',
Tz='Tzar:BAAALgADCgIJAgAAAA==.',
['Tô']='Tôx:BAABLgAECn8VAAMJAAcJVR3rIQBCAQAJAAcJVR3rIQBCAQAIAAEJyhWpoAAwAAAAAA==.',
Ub='Ubrew:BAAALgAECgkJBQAAAA==.',
Ud='Udyrr:BAAALgADCgIJAgAAAA==.',
Ul='Ulfius:BAAALgADCgMJAwAAAA==.Ullume:BAAALgAECgMJAwAAAA==.',
Um='Umbranwings:BAAALgAECgUJBQAAAA==.',
Un='Unheardjp:BAAALgAECgMJCwAAAA==.Unholy:BAAALgADCgMJAwAAAA==.Unholyarnix:BAAALgAECgQJCwAAAA==.',
Ur='Ursus:BAAALgADCgYJBgAAAA==.',
Va='Vacuum:BAAALgAECgYJEQAAAA==.Vadican:BAAALgADCgQJBAAAAA==.Vaerix:BAABLgAECn8kAAIaAAkJ0A0uFQCcAQAaAAkJ0A0uFQCcAQAAAA==.Valhals:BAABLgAECn8YAAIXAAUJNAUyQQCSAAAXAAUJNAUyQQCSAAAAAA==.Valydrin:BAABLgAECn8vAAIWAAgJEh9IBgCWAgAWAAgJEh9IBgCWAgAAAA==.Vanhelsinky:BAAALgADCgIJAgAAAA==.Vanquished:BAAALgAECgIJBAAAAA==.Varyn:BAAALgADCgIJAgAAAA==.',
Ve='Velandia:BAAALgAECgcJCAAAAA==.Ventis:BAAALgAECgQJBwAAAA==.',
Vi='Vicara:BAAALgADCgYJBgAAAA==.',
Vo='Voidifphat:BAAALgAECggJDAAAAA==.Voidtorrent:BAAALgAECgQJCAAAAA==.Voidvanquish:BAAALgAECgYJBgAAAA==.Vorkhan:BAAALgADCgUJCAAAAA==.',
Vu='Vuldrak:BAAALgAECgcJEgAAAA==.',
Vy='Vysis:BAACLgAFFH8LAAQGAAMJ6AfMEwDkAAAGAAMJ6AfMEwDkAAAHAAMJVQkXGgDRAAAWAAIJ1AwFDgCOAAAuAAQKfzwABBYACQnnGYYSAEwCABYACAnEGIYSAEwCAAYABwliGmMOAOUBAAcABwnDFSIPAOABAAAA.',
['Vä']='Vännic:BAAALgADCgEJAwAAAA==.Vännìc:BAAALgADCgEJAQAAAA==.',
['Ví']='Ví:BAAALgAECgYJDwAAAA==.',
Wh='Whatfoxsay:BAAALgADCgEJAQAAAA==.Whats:BAAALgADCgcJBwABLgAECgYJDwAEAAAAAA==.When:BAAALgADCgQJBAAAAA==.Whicker:BAAALgAECgUJBgAAAA==.Whipsnchains:BAAALgAECgMJAwAAAA==.Whipsntricks:BAAALgAECgEJAQAAAA==.',
Wi='Wickèr:BAABLgAECn8uAAIXAAgJah3VCAA7AgAXAAgJah3VCAA7AgAAAA==.Wieldblade:BAABLgAECn8mAAIFAAgJSB4aKACEAgAFAAgJSB4aKACEAgAAAA==.Wilsondk:BAAALgAECgEJAQAAAA==.Winslett:BAAALgADCgQJBAAAAA==.',
Wo='Wolfemoon:BAABLgAECn8UAAIfAAgJwwrNNgByAQAfAAgJwwrNNgByAQAAAA==.Worganlefey:BAAALgAECgEJAQABLgAECggJLwAKALMOAA==.',
Wr='Wrexd:BAABLgAECn8qAAIKAAgJBBu8GgAQAgAKAAgJBBu8GgAQAgAAAA==.',
Wu='Wunderbar:BAABLgAECn8hAAMJAAcJWB0XDgD9AQAJAAcJWB0XDgD9AQAIAAEJRxrdlwBAAAAAAA==.',
Wy='Wyldfire:BAACLgAFFH8QAAIlAAQJsRMNDwA7AQAlAAQJsRMNDwA7AQAuAAQKfysAAyUACAl8JPQLANgCACUACAl8JPQLANgCAB0AAglkF4meAI4AAAAA.Wyndclaw:BAAALgAECgQJBAAAAA==.',
Xa='Xanith:BAABLgAECn8aAAIPAAcJBhLOHQB7AQAPAAcJBhLOHQB7AQAAAA==.',
Xe='Xebubble:BAAALgADCgEJAQABLgAECgEJAQAEAAAAAA==.Xemonk:BAAALgAECgEJAQAAAA==.',
Xi='Xia:BAAALgADCgYJBgAAAA==.',
Xr='Xroi:BAAALgAECgIJAgAAAA==.',
Ya='Yaganor:BAAALgADCgUJBgAAAA==.',
Ye='Yeto:BAAALgADCgYJBwAAAA==.',
Yi='Yia:BAAALgAECgQJCAABLgAECgQJCAAEAAAAAA==.Yilnara:BAABLgAECn8QAAIRAAcJOAYNYQDdAAARAAcJOAYNYQDdAAAAAA==.',
Za='Zajindor:BAAALgADCgEJAQAAAA==.Zarathul:BAAALgADCgIJAgAAAA==.',
Ze='Zekkun:BAAALgAECgEJAQAAAA==.',
Zh='Zheria:BAAALgAECgQJBAAAAA==.',
Zi='Zirael:BAAALgADCgYJCgAAAA==.',
Zo='Zoganian:BAEALgAECgEJAQABLgAECggJHAAWAO0jAA==.Zogula:BAEBLgAECn8cAAMWAAgJ7SNnBQCvAgAWAAgJsyNnBQCvAgAHAAEJaiP8OQBmAAAAAA==.',
Zu='Zu:BAAALgAECgQJDQAAAA==.',
['År']='Årtemis:BAABLgAECn8eAAIoAAgJMBqECQBIAgAoAAgJMBqECQBIAgAAAA==.',
['Æb']='Æbony:BAAALgADCgMJAwAAAA==.',
['Ïr']='Ïrini:BAAALgAECgIJAwABLgAECgcJCAAEAAAAAA==.',
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

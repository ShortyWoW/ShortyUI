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

local lookup = {'DemonHunter-Havoc','DemonHunter-Vengeance','Paladin-Protection','Unknown-Unknown','Paladin-Retribution','Priest-Discipline','Priest-Shadow','Shaman-Restoration','Shaman-Elemental','Warlock-Demonology','Evoker-Preservation','Shaman-Enhancement','Druid-Guardian','Rogue-Outlaw','Warrior-Fury','Warrior-Arms','DemonHunter-Devourer','Mage-Frost','Druid-Feral','Monk-Windwalker','Hunter-Marksmanship','Priest-Holy','Monk-Brewmaster','Warlock-Destruction','Evoker-Augmentation','Monk-Mistweaver','DeathKnight-Unholy','Mage-Arcane','Druid-Restoration','Warlock-Affliction','Hunter-BeastMastery','Warrior-Protection','DeathKnight-Frost','DeathKnight-Blood','Evoker-Devastation','Druid-Balance','Paladin-Holy','Rogue-Assassination','Hunter-Survival','Rogue-Subtlety','Mage-Fire',}
local provider = {region='US',realm='AzjolNerub',name='US',type='weekly',zone=46,date='2026-05-01',data={Ad='Adapt:BAAALgAECgMJCQAAAA==.Addy:BAABLgAECn8dAAMBAAgJIBf4DABtAQABAAgJIBf4DABtAQACAAEJQgh8GQAtAAAAAA==.',
Ae='Aeonis:BAAALgAECgEJAQAAAA==.Aestian:BAABLgAECn8aAAIDAAcJ5BpBCACOAQADAAcJ5BpBCACOAQAAAA==.',
Ag='Agamesh:BAAALgADCgUJCQAAAA==.',
Ah='Ahoma:BAAALgADCgkJBgAAAA==.',
Ai='Ailysely:BAAALgADCgEJAQABLgAECgEJAQAEAAAAAA==.Airees:BAABLgAECn8hAAIFAAcJNh7iKgCWAQAFAAcJNh7iKgCWAQAAAA==.Aispere:BAAALgAECgMJAwAAAA==.',
Al='Alastria:BAAALgADCgcJBwAAAA==.Alektra:BAAALgADCgUJBwAAAA==.Alerzhulan:BAAALgAECgcJBwAAAA==.Allanquatre:BAAALgADCgEJAQABLgADCggJCAAEAAAAAA==.Alledria:BAABLgAECn8ZAAIFAAcJdxSbLgCHAQAFAAcJdxSbLgCHAQAAAA==.Allenaena:BAAALgAECgMJBgAAAA==.Alorely:BAABLgAECn8RAAMGAAUJqwolNQD7AAAGAAUJqwolNQD7AAAHAAUJpwnUKAC5AAAAAA==.Altonas:BAAALgAECgMJAwAAAA==.',
Am='Amanara:BAAALgAECgIJAgAAAA==.Amillah:BAAALgAECgMJAwAAAA==.',
An='Anciientpaw:BAABLgAECn8fAAMIAAgJoh5mHQAvAgAIAAgJoh5mHQAvAgAJAAUJaBWAJAD+AAAAAA==.Andramalyus:BAABLgAECn8UAAIKAAcJhAuaYwDKAAAKAAcJhAuaYwDKAAAAAA==.Andrasomnium:BAAALgADCgUJBQAAAA==.Angbar:BAABLgAECn8bAAILAAcJ2xRGCQCLAQALAAcJ2xRGCQCLAQAAAA==.Anguirus:BAABLgAECn8eAAMJAAgJJARiUAAFAQAJAAgJJARiUAAFAQAMAAQJ3QDdGAA6AAAAAA==.Animà:BAAALgAECgYJBgAAAA==.Ankhnstein:BAAALgAECgQJBAAAAA==.Antoine:BAAALgAECgIJAgAAAA==.',
Ap='Apolloni:BAAALgAECgIJAgABLgAECggJGQANAKoDAA==.Appynoxusrog:BAABLgAECn8cAAIOAAYJuhgsBQCcAQAOAAYJuhgsBQCcAQAAAA==.',
Aq='Aqulenas:BAAALgAECggJDAAAAA==.',
Ar='Arakhan:BAAALgAECgQJBAAAAA==.Arasaka:BAAALgAECgQJBAAAAA==.Arcadian:BAABLgAECn8fAAMPAAgJJBSgMQDmAQAPAAgJJBSgMQDmAQAQAAEJzAfQRAAvAAAAAA==.Arcadiann:BAAALgAECgQJBAAAAA==.Arcadin:BAAALgAECgEJAgAAAA==.Arextheelder:BAAALgADCgIJAgAAAA==.Aridas:BAABLgAECn8dAAMRAAgJ5RdsMwAsAgARAAgJ5RdsMwAsAgABAAIJRQv/XwBiAAAAAA==.Arikdeath:BAAALgAECgYJCQAAAA==.Armorscales:BAACLgAFFH8JAAIKAAMJPxGTQgCiAAAKAAMJPxGTQgCiAAAuAAQKfygAAgoACAmVIloQAPcCAAoACAmVIloQAPcCAAAA.Arntraz:BAAALgADCggJGwAAAA==.Arçadia:BAAALgAECgMJAwAAAA==.',
As='Ashegen:BAAALgAECgQJBAAAAA==.Ashnikko:BAAALgAECgEJAQAAAA==.Ashtori:BAAALgADCgEJAgAAAA==.Astrine:BAACLgAFFH8JAAISAAMJ4x6+QgC4AAASAAMJ4x6+QgC4AAAuAAQKfyYAAhIACAkWIgIiAOsCABIACAkWIgIiAOsCAAAA.',
Au='Auberon:BAABLgAECn8dAAITAAgJchl6BgCSAgATAAgJchl6BgCSAgAAAA==.Aufta:BAABLgAECn8ZAAIUAAgJmQXRGQAXAQAUAAgJmQXRGQAXAQAAAA==.',
Az='Azdh:BAAALgAECgQJBgAAAA==.Azi:BAACLgAFFH8QAAIVAAUJkBcBBQBMAQAVAAUJkBcBBQBMAQAuAAQKfyMAAhUACQm4Hs8UAIkCABUACQm4Hs8UAIkCAAAA.Azshanorel:BAAALgADCgcJBwAAAA==.Azunea:BAAALgAECgIJBwAAAA==.Azurite:BAAALgADCgQJAwAAAA==.',
Ba='Backpedal:BAAALgAECgQJBQAAAA==.Badankhadonk:BAACLgAFFH8JAAIIAAMJQCCADwAVAQAIAAMJQCCADwAVAQAuAAQKfygAAggACAnaJVECAF8DAAgACAnaJVECAF8DAAAA.Balen:BAABLgAECn8aAAIDAAcJNhMECwBSAQADAAcJNhMECwBSAQAAAA==.Bandrösh:BAAALgADCgMJAwAAAA==.Barradune:BAAALgADCgYJCgAAAA==.',
Be='Belholy:BAAALgAECgYJDgAAAA==.Beliice:BAAALgADCgkJDwABLgAECgYJDgAEAAAAAA==.Bellanei:BAAALgAECgEJAQAAAA==.Ben:BAAALgAECgEJAQAAAA==.Benafflockk:BAAALgADCggJCAAAAA==.Benefitdruid:BAAALgAECgEJAQAAAA==.Benilok:BAACLgAFFH8GAAIKAAMJHBkMMQCwAAAKAAMJHBkMMQCwAAAuAAQKfyYAAgoACAklJSMMABkDAAoACAklJSMMABkDAAAA.Bethgibbons:BAAALgADCgkJEAAAAA==.',
Bi='Bibimbap:BAAALgAECgEJAQAAAA==.Bigsuccubus:BAAALgAECgQJCAAAAA==.Biohazard:BAAALgADCgUJBQAAAA==.Bizël:BAAALgADCgMJAwAAAA==.',
Bl='Blackblood:BAABLgAECn8VAAIBAAYJjhCkEQAnAQABAAYJjhCkEQAnAQAAAA==.Blackclouds:BAAALgADCgkJCQAAAA==.Blackspiral:BAAALgADCgEJAQAAAA==.Bladestriker:BAAALgAECgEJAQAAAA==.Blindside:BAAALgAECgMJAwAAAA==.Bloodache:BAABLgAECn8VAAIRAAcJNyFiKQBcAgARAAcJNyFiKQBcAgAAAA==.Bloodkissed:BAAALgADCgUJBgABLgAECgcJHwAWAH4fAA==.Bluebuberry:BAAALgAECgQJBgAAAA==.Bluesaphire:BAAALgAECgIJAgABLgAECgYJDwAEAAAAAA==.Blux:BAAALgAECgIJBAAAAA==.',
Bo='Boil:BAAALgAECgcJDQAAAA==.Bonemarrow:BAAALgAECgQJDQAAAA==.Bournx:BAAALgADCgcJBwAAAA==.Boysenbar:BAAALgADCgYJCAAAAA==.',
Br='Bradrenna:BAABLgAECn8tAAMCAAkJMxYHBgA5AgACAAkJMxYHBgA5AgARAAEJpQGx9AAbAAAAAA==.Braké:BAABLgAECn8VAAIDAAYJ4xuxBwCeAQADAAYJ4xuxBwCeAQAAAA==.Breakthrough:BAAALgAECgQJBAAAAA==.Brenzull:BAAALgADCgYJCwAAAA==.Brewskies:BAABLgAECn8fAAIXAAcJlSNOBAByAgAXAAcJlSNOBAByAgAAAA==.Brewsli:BAAALgADCgIJAgABLgAECgYJEAAEAAAAAA==.Brightstar:BAAALgAECgcJEwAAAA==.Brokenaltar:BAABLgAECn8VAAMBAAYJNRhYOQAdAQARAAYJgRFVcwBLAQABAAUJCRpYOQAdAQAAAA==.Brownington:BAAALgAECgcJEQAAAA==.Bruhilda:BAAALgAECgUJDQAAAA==.Brymstone:BAAALgAECgQJBwAAAA==.Brynthebuff:BAAALgAECgEJAQAAAA==.Brìonik:BAACLgAFFH8QAAMKAAUJeRzhFgBDAQAKAAUJmhXhFgBDAQAYAAMJIBhkDACpAAAuAAQKfyQAAxgACQmuIYkNAOwBABgABgksIYkNAOwBAAoABQkeI3MqAIQBAAAA.',
Bu='Bufferfish:BAABLgAECn8kAAIZAAgJEwvsFgBGAQAZAAgJEwvsFgBGAQAAAA==.',
Ca='Calinnea:BAAALgAECgYJBwAAAA==.Cantheartitz:BAAALgAECgUJDwAAAA==.Catastrophe:BAAALgAECgUJDQAAAA==.',
Ce='Celthol:BAAALgAECgMJBgAAAA==.',
Ch='Chelraani:BAABLgAECn8YAAIFAAcJkx4ZFAAZAgAFAAcJkx4ZFAAZAgAAAA==.Chiichard:BAAALgADCgYJCgAAAA==.Chipnuts:BAABLgAECn8aAAIUAAgJTiXBAgBtAwAUAAgJTiXBAgBtAwAAAA==.Chonchoo:BAAALgADCgEJAQAAAA==.Chosethebear:BAAALgADCgkJEAAAAA==.',
Cl='Clarabellax:BAAALgAECgQJBQAAAA==.Clarkkentt:BAAALgADCgcJDQAAAA==.Claymore:BAACLgAFFH8GAAIPAAMJuhALFADhAAAPAAMJuhALFADhAAAuAAQKfxUAAg8ACAkMGcocAGcCAA8ACAkMGcocAGcCAAAA.Clazzicola:BAACLgAFFH8KAAMaAAQJIAmmDQABAQAaAAQJIAmmDQABAQAUAAIJXgi3DQCWAAAuAAQKfx8ABBQACQmcFlweAOUBABQABwlYHFweAOUBABoACAnlEYQmAH8BABcAAQlhA8SVAB8AAAAA.Cloudbeast:BAAALgADCgQJBAABLgAECgQJCgAEAAAAAA==.Clue:BAAALgADCgYJBgAAAA==.',
Co='Conjredcukee:BAAALgAECgYJCwAAAA==.Coo:BAAALgAECgQJBAABLgAECgUJBwAEAAAAAA==.Coogsayer:BAABLgAECn8UAAIHAAcJxh2WEQBxAgAHAAcJxh2WEQBxAgAAAA==.',
Cp='Cptncrush:BAABLgAECn8VAAMIAAYJ6RpMFgC1AQAIAAYJ6RpMFgC1AQAJAAMJrRcDcACDAAAAAA==.',
Cr='Croquetica:BAAALgADCgMJBAAAAA==.Crossed:BAAALgADCgcJCwAAAA==.Crowshadow:BAAALgAECgUJCgAAAA==.',
Cy='Cyther:BAACLgAFFH8UAAIPAAUJAB58AwB9AQAPAAUJAB58AwB9AQAuAAQKfyMAAg8ACQmMIrAHAC4DAA8ACQmMIrAHAC4DAAAA.',
['Cÿ']='Cÿthera:BAABLgAECn8aAAIRAAgJUB/DHAClAgARAAgJUB/DHAClAgAAAA==.',
Da='Dakk:BAABLgAECn8vAAIbAAgJWiNcCACYAgAbAAgJWiNcCACYAgAAAA==.Daraghor:BAABLgAECn8aAAINAAgJjCMNAgAbAwANAAgJjCMNAgAbAwAAAA==.Darkenstormy:BAAALgAECgYJCwAAAA==.Darlyndra:BAAALgADCgUJBQAAAA==.Darsae:BAAALgAECgQJDAAAAA==.Darthiono:BAAALgAECgEJAQAAAA==.',
De='Deadlight:BAABLgAECn8nAAIbAAkJrBCuGQDuAQAbAAkJrBCuGQDuAQAAAA==.Deathkillhun:BAAALgAECgQJBwAAAA==.Deathpooch:BAAALgADCgkJDwAAAA==.Deathshooter:BAAALgAECgcJAQAAAA==.Deavant:BAAALgADCgMJAwAAAA==.Deermon:BAAALgAECgYJCwAAAA==.Deforest:BAAALgADCgcJFgAAAA==.Deity:BAABLgAECn8VAAIPAAYJVh+NJAAyAgAPAAYJVh+NJAAyAgAAAA==.Demogon:BAAALgAECgQJBwAAAA==.Demondeano:BAABLgAECn8ZAAIRAAgJsxN4HgB8AQARAAgJsxN4HgB8AQAAAA==.Demonlxl:BAAALgADCgIJAgAAAA==.Demonx:BAABLgAECn8ZAAIbAAkJJhEOGAD7AQAbAAkJJhEOGAD7AQAAAA==.Desolation:BAABLgAECn8nAAIcAAgJYiRcAABRAwAcAAgJYiRcAABRAwAAAA==.Despia:BAABLgAECn8aAAIWAAcJkiR+AgDcAgAWAAcJkiR+AgDcAgAAAA==.Devastacia:BAAALgADCgUJBQAAAA==.Deviarc:BAAALgAECgQJBAAAAA==.',
Dh='Dharkon:BAAALgAECgIJBAAAAA==.',
Di='Dicot:BAABLgAECn8ZAAIdAAcJ+Q3pKgA3AQAdAAcJ+Q3pKgA3AQAAAA==.',
Dj='Djpallyd:BAAALgAECgkJEAAAAA==.',
Do='Doinks:BAAALgAECgIJAgAAAA==.Domilthri:BAABLgAECn8mAAMeAAgJwApDEAAqAQAKAAgJwAqQQgAqAQAeAAYJ8gVDEAAqAQAAAA==.Dotdaddy:BAAALgAECgQJBwABLgAECgYJBwAEAAAAAA==.',
Dr='Dracoly:BAAALgAECggJEgAAAA==.Draconu:BAACLgAFFH8MAAIZAAQJXRLeDQBAAQAZAAQJXRLeDQBAAQAuAAQKfxsAAxkACQkjG8wKAMkCABkACQkjG8wKAMkCAAsAAQmaAXBOACIAAAAA.Draenyth:BAAALgAECgEJAQAAAA==.Dragoncurry:BAAALgAECgQJEAAAAA==.Dragonmite:BAAALgAECgEJAQAAAA==.Drakka:BAAALgADCgkJDgABLgAECgQJBAAEAAAAAA==.Draktyr:BAACLgAFFH8GAAIPAAMJshaoEQD6AAAPAAMJshaoEQD6AAAuAAQKfyQAAg8ACQn1Hn4JABYDAA8ACQn1Hn4JABYDAAAA.Dropeadita:BAAALgAECgQJBAAAAA==.Droptop:BAAALgADCgcJCAAAAA==.',
Du='Dumbsht:BAABLgAECn8ZAAMVAAgJ5RZkMQCpAQAVAAcJ6RVkMQCpAQAfAAYJUBHhXQBOAQAAAA==.',
Ea='Easystreet:BAAALgAECgIJAwAAAA==.',
Ef='Effluv:BAAALgADCgcJDgAAAA==.',
El='Elandir:BAAALgADCgQJAQAAAA==.Elanora:BAAALgAECgMJAwAAAA==.Elbrookel:BAAALgAECgIJAgAAAA==.Eleshnorn:BAAALgAECgIJBQAAAA==.Eliza:BAAALgADCgkJCQAAAA==.Ellismom:BAABLgAECn8nAAIbAAgJ3Rq6FAAUAgAbAAgJ3Rq6FAAUAgAAAA==.Elvea:BAAALgAECgYJEAAAAA==.',
Em='Emeralddemon:BAAALgAECgEJAQAAAA==.Emeraldshade:BAAALgADCgcJDgABLgAECgEJAQAEAAAAAA==.Emeråld:BAAALgAECgMJAwAAAA==.',
En='Enamorada:BAAALgAECgIJAgABLgAECgYJDwAEAAAAAA==.',
Er='Ereithelda:BAACLgAFFH8QAAIaAAUJWxNxBwBxAQAaAAUJWxNxBwBxAQAuAAQKfyEAAhoACAnDIhYHAOkCABoACAnDIhYHAOkCAAAA.Ericka:BAAALgADCgQJBAAAAA==.Erreya:BAAALgADCgEJAQAAAA==.',
Es='Esma:BAAALgADCgkJCQAAAA==.',
Ev='Evox:BAAALgAECgYJDAAAAA==.',
Ey='Eyris:BAAALgADCgMJAwAAAA==.Eyrndor:BAAALgADCgIJAwAAAA==.',
Fa='Faacee:BAAALgAECgIJAgAAAA==.Fann:BAAALgAECgUJEwAAAA==.Faytl:BAAALgAECgEJAQAAAA==.',
Fe='Felbubu:BAABLgAECn8eAAQCAAgJaCIgBACAAgACAAgJ7CEgBACAAgABAAYJOyAfIgCrAQARAAEJ6hq63QA0AAAAAA==.Femboy:BAAALgAECgUJCQAAAA==.Fewz:BAACLgAFFH8GAAISAAMJ8BJxPgCwAAASAAMJ8BJxPgCwAAAuAAQKfxoAAhIACAlDIC0wALICABIACAlDIC0wALICAAAA.',
Fi='Fireybuns:BAAALgAECgEJAwAAAA==.',
Fl='Flaccid:BAABLgAECn8YAAIfAAgJfQ/SHQCsAQAfAAgJfQ/SHQCsAQAAAA==.Flakiron:BAACLgAFFH8LAAIgAAMJgBEYCgDcAAAgAAMJgBEYCgDcAAAuAAQKfygAAiAACAnBGpULAFUCACAACAnBGpULAFUCAAAA.Flakov:BAAALgAECgIJAgABLgAFFAMJCwAgAIARAA==.Flaktop:BAAALgAECgIJAgABLgAFFAMJCwAgAIARAA==.Fler:BAAALgADCgQJBAAAAA==.',
Fo='Forbacon:BAAALgAECgYJEAAAAA==.Force:BAABLgAECn8UAAQhAAYJjQgUDgDHAAAhAAQJwwsUDgDHAAAbAAQJfATshgCIAAAiAAEJ4QDoMQAWAAAAAA==.Fouris:BAAALgAECgYJEgAAAA==.',
Fr='Fremosth:BAAALgADCgIJAgAAAA==.Fretman:BAAALgADCgcJCQAAAA==.Fridgie:BAACLgAFFH8TAAIfAAUJIhY0BABdAQAfAAUJIhY0BABdAQAuAAQKfyMAAh8ACQm7InAPAMACAB8ACQm7InAPAMACAAAA.Frozenflyer:BAAALgAECgUJEAAAAA==.Frozenturtle:BAAALgAECgcJDgAAAA==.',
Ft='Ftwiamtank:BAAALgAECgUJBQAAAA==.',
Fu='Fuoco:BAAALgAECgkJCgAAAA==.',
Ga='Garcutt:BAACLgAFFH8TAAISAAUJpQ58IwBGAQASAAUJpQ58IwBGAQAuAAQKfyUAAhIACQmQHe82AJgCABIACQmQHe82AJgCAAAA.Gaurdinn:BAABLgAECn8eAAMjAAgJBg/VBgApAQAZAAcJJQ2dMwAvAQAjAAYJbhDVBgApAQAAAA==.',
Ge='Gebuss:BAAALgADCgQJBAAAAA==.Generickmonk:BAACLgAFFH8IAAIUAAQJKw9YCADxAAAUAAQJKw9YCADxAAAuAAQKfyUAAhQACAkfIvsIAOgCABQACAkfIvsIAOgCAAAA.Gensis:BAAALgADCgYJBgAAAA==.Geomatic:BAAALgAECgEJAQAAAA==.Gethsemåne:BAAALgADCgMJAwAAAA==.',
Gi='Gitan:BAAALgADCgQJBQAAAA==.',
Gl='Gladstone:BAAALgAECgYJCQAAAA==.',
Go='Gomlvirgin:BAAALgADCgYJBgAAAA==.',
Gr='Gracehimeûwû:BAAALgAFFAIJAgAAAA==.Grampsie:BAAALgAECgUJBwAAAA==.Grayeyes:BAAALgADCgkJCQAAAA==.Greenngoblin:BAAALgADCgEJAQAAAA==.Grimmlie:BAAALgADCgUJBQAAAA==.Grinzler:BAAALgADCgIJAgAAAA==.Grumpybear:BAAALgADCggJDwAAAA==.Grumpykat:BAAALgAECggJEgAAAA==.Grumpypros:BAAALgADCgUJBQAAAA==.',
Gt='Gtatedk:BAAALgAECgcJBgAAAA==.',
Gu='Guino:BAAALgAECgMJAwAAAA==.Guinodruid:BAAALgADCgcJDgAAAA==.',
Gw='Gwenelly:BAAALgAECgEJAQAAAA==.',
Ha='Hamncheeks:BAAALgAECgEJAQAAAA==.Haptism:BAAALgADCgcJBwAAAA==.Hardeesdelux:BAAALgADCgYJBgABLgAECgQJCgAEAAAAAA==.Hardnarples:BAAALgADCgEJAQAAAA==.Hayzerade:BAAALgAECgMJAwAAAA==.Hazis:BAABLgAECn8pAAIiAAkJpyATAwAqAgAiAAkJpyATAwAqAgAAAA==.',
Hi='Hippiecritz:BAAALgADCgYJBwAAAA==.Hitokiri:BAAALgADCgMJAwAAAA==.',
Ho='Holy:BAACLgAFFH8LAAIDAAMJ5gSWBQCEAAADAAMJ5gSWBQCEAAAuAAQKfyUAAgMACAnxE/IQALcBAAMACAnxE/IQALcBAAAA.Holydad:BAABLgAECn8ZAAIDAAgJOhr6CQAxAgADAAgJOhr6CQAxAgAAAA==.Holydust:BAAALgAECgcJEQAAAA==.Holymoki:BAAALgADCgYJCgAAAA==.Holymoliie:BAAALgADCgEJAQAAAA==.Holyroundie:BAABLgAECn8rAAIWAAkJUAxlFABvAQAWAAkJUAxlFABvAQAAAA==.Holyshock:BAACLgAFFH8UAAIFAAUJlBxjBwB7AQAFAAUJlBxjBwB7AQAuAAQKfyMAAgUACQm/I9oOABcDAAUACQm/I9oOABcDAAAA.Honeybutter:BAACLgAFFH8HAAMQAAMJ+x36AgAnAQAQAAMJ+x36AgAnAQAPAAEJCAkLIgBRAAAuAAQKfykAAxAACQnPIlgAADcDABAACQnPIlgAADcDAA8ABwmLHtEjADgCAAAA.Hordebreaker:BAAALgAECgUJDgAAAA==.Hotflash:BAAALgAECgEJAQAAAA==.',
Hu='Huukend:BAABLgAECn8fAAIfAAgJaxuZFACSAgAfAAgJaxuZFACSAgAAAA==.',
Ic='Icebabyman:BAABLgAECn8ZAAISAAgJCR3hOACSAgASAAgJCR3hOACSAgAAAA==.',
In='Inanitas:BAAALgADCgcJBwAAAA==.Ineffectual:BAABLgAECn8fAAIIAAgJuxMAHgBzAQAIAAgJuxMAHgBzAQAAAA==.',
Ir='Irukox:BAAALgAECgQJBQAAAA==.',
It='Itty:BAAALgADCgcJBwAAAA==.',
Ja='Jagger:BAAALgADCgcJCQAAAA==.Jalene:BAAALgAECgUJCAAAAA==.Janewayy:BAABLgAECn8fAAIRAAgJrwzjWgCQAQARAAgJrwzjWgCQAQAAAA==.',
Je='Jeks:BAAALgADCgcJBwABLgAFFAUJFQAIABQeAA==.Jemma:BAABLgAECn8ZAAIYAAgJAg6qCAAiAQAYAAgJAg6qCAAiAQAAAA==.Jettadari:BAACLgAFFH8OAAIRAAUJoRcNEABNAQARAAUJoRcNEABNAQAuAAQKfyAAAxEACQn5HuwWAM0CABEACQn5HuwWAM0CAAIAAQkmDl8YADQAAAAA.Jettadin:BAABLgAECn8aAAIFAAgJ9SGmDwARAwAFAAgJ9SGmDwARAwABLgAFFAUJDgARAKEXAA==.Jettathyr:BAAALgAECgcJDQABLgAFFAUJDgARAKEXAA==.',
Ju='Jubba:BAAALgAECgYJEQAAAA==.Junk:BAAALgAECgYJCAABLgAECgcJHwAXAJUjAA==.',
['Jë']='Jëks:BAACLgAFFH8VAAIIAAUJFB7dAwCxAQAIAAUJFB7dAwCxAQAuAAQKfyMAAwgACQlgJXADAEEDAAgACQlgJXADAEEDAAwAAgksDp8TAH4AAAAA.',
Ka='Kahea:BAAALgAECgQJBAAAAA==.Kaing:BAABLgAECn8XAAMUAAcJRCObEAB3AgAUAAcJRCObEAB3AgAaAAEJkw2PbAApAAAAAA==.Kaitou:BAABLgAECn8mAAMTAAgJARxLBwB4AgATAAgJARxLBwB4AgAkAAEJrA7SRAA4AAAAAA==.Kalamiti:BAAALgAECgQJCAAAAA==.Kallar:BAABLgAECn8fAAIWAAcJfh9qBgBSAgAWAAcJfh9qBgBSAgAAAA==.Karesh:BAAALgAECgQJBAAAAA==.Kayeera:BAAALgAECgUJEgAAAA==.Kayha:BAAALgADCgEJAQAAAA==.Kaylrandi:BAAALgADCgQJBwAAAA==.Kaztiel:BAAALgAECgIJAgAAAA==.',
Ke='Keadon:BAAALgAECgYJCwAAAA==.Keeper:BAAALgADCgMJAwABLgAECgYJFQAPAFYfAA==.Keh:BAAALgADCgkJCQAAAA==.Kennethv:BAAALgAECgMJBAAAAA==.Kenze:BAAALgAECgEJAQAAAA==.Kethra:BAAALgADCgYJBgAAAA==.Kev:BAAALgAECgcJAgAAAA==.',
Kh='Khel:BAAALgADCgcJBwAAAA==.Khiell:BAACLgAFFH8HAAIPAAQJKQw/DAAtAQAPAAQJKQw/DAAtAQAuAAQKfxUAAg8ACAm9Fl4fAFYCAA8ACAm9Fl4fAFYCAAAA.',
Ki='Kilyse:BAAALgADCgYJBgAAAA==.Kinigit:BAAALgAECgQJBwABLgAFFAMJCwAkADIWAA==.Kirïtö:BAAALgAECgUJCwAAAA==.Kitarah:BAEALgAECgIJAgABLgAECgYJBgAEAAAAAA==.Kitarazen:BAEALgAECgYJBgAAAA==.',
Ko='Kokushimosu:BAAALgAECgQJBAAAAA==.Koo:BAAALgAECgUJBwAAAA==.',
Kr='Krátos:BAAALgAECgcJBwABLgAECggJHQARAOUXAA==.',
Ks='Ksper:BAAALgAECgYJDAAAAA==.',
Ku='Kukalak:BAABLgAECn8WAAIgAAgJ/RZmCgCEAQAgAAgJ/RZmCgCEAQAAAA==.Kuranaa:BAAALgADCggJEwABLgAECgMJAwAEAAAAAA==.Kurulak:BAABLgAECn8VAAIRAAgJ+ww3WgCTAQARAAgJ+ww3WgCTAQAAAA==.',
Ky='Kymru:BAAALgADCgcJDQAAAA==.',
['Ké']='Kénnéth:BAAALgAECgYJDQAAAA==.',
La='Lacerveza:BAAALgAECgIJBAAAAA==.Lahyanhou:BAABLgAECn8dAAIVAAgJygUFCgAyAQAVAAgJygUFCgAyAQAAAA==.Lalalalala:BAAALgAECgcJCgAAAA==.Lalin:BAAALgAECgEJAgAAAA==.Larkwyn:BAAALgAECgMJAwABLgAECgcJGgAKAAsPAA==.Laylah:BAAALgADCgYJBAAAAA==.',
Le='Lebrand:BAAALgAECgEJAQAAAA==.Leriope:BAABLgAECn8nAAIKAAgJKQ6aLwBtAQAKAAgJKQ6aLwBtAQAAAA==.',
Li='Lichfiend:BAAALgADCgEJAQAAAA==.Lightbeer:BAAALgAECgYJBwAAAA==.Lihplock:BAAALgAECgQJCAAAAA==.Lildragonboi:BAAALgADCgUJBQAAAA==.Lilem:BAAALgADCgcJEgAAAA==.Listenlinda:BAAALgADCgcJCwAAAA==.Littlemerald:BAAALgAECgMJBAAAAA==.',
Lj='Lj:BAABLgAECn8gAAIlAAgJ4R3gBgBzAgAlAAgJ4R3gBgBzAgAAAA==.',
Lo='Localsingles:BAAALgADCgcJBwAAAA==.Lorath:BAAALgADCgEJAQAAAA==.Lovecrafft:BAAALgAECgEJAQAAAA==.',
Lu='Lu:BAAALgAFFAEJAQABLgAFFAQJCgAaACAJAA==.Lucinà:BAABLgAECn8iAAQlAAgJeh6TDAC1AgAlAAgJeh6TDAC1AgADAAUJiR3vCgBTAQAFAAcJ7SGBTwAeAQAAAA==.Luxure:BAAALgAECgYJBgAAAA==.',
Ly='Lyndall:BAAALgAECgQJBgAAAA==.',
Ma='Madammìm:BAAALgADCgEJAQAAAA==.Maegan:BAAALgAECgIJAgAAAA==.Mager:BAAALgAECgEJAQAAAA==.Magerhunter:BAAALgADCgYJBwAAAA==.Magolock:BAAALgAECgQJBAABLgAECgQJBAAEAAAAAA==.Mahll:BAAALgADCgcJBwAAAA==.Maidrim:BAACLgAFFH8MAAImAAQJvBpPAQB/AQAmAAQJvBpPAQB/AQAuAAQKfxkAAiYACQmtIfECALICACYACQmtIfECALICAAAA.Makavelli:BAAALgADCgEJAQAAAA==.Mamajumbo:BAAALgAECgYJCgAAAA==.Marage:BAAALgADCgEJAQAAAA==.Marellias:BAAALgAECgIJAgABLgAECggJIwAFACokAA==.Marikel:BAAALgAECgMJAwAAAA==.Markwel:BAAALgAECgIJAgAAAA==.Marrack:BAAALgAECgYJDQAAAA==.',
Me='Melador:BAAALgADCgIJAgAAAA==.Meletha:BAAALgAECgYJCQAAAA==.Melpuis:BAAALgAECgEJAgAAAA==.Metahorfasis:BAAALgAECgMJAwAAAA==.',
Mi='Michaelken:BAABLgAECn8UAAIlAAYJvRWRHABmAQAlAAYJvRWRHABmAQAAAA==.Mierín:BAAALgADCgYJBgAAAA==.Migrains:BAABLgAECn8nAAIDAAgJhSLCAgAAAwADAAgJhSLCAgAAAwAAAA==.Mineo:BAAALgAECgYJBwAAAA==.Mirâjâne:BAAALgAECgEJAQAAAA==.Miskaabin:BAAALgAECgcJDwAAAA==.Miststress:BAAALgAECgIJAgAAAA==.',
Mo='Mobal:BAABLgAECn8XAAIIAAcJhxqCHgAoAgAIAAcJhxqCHgAoAgAAAA==.Mojogreens:BAAALgAECgYJDAAAAA==.Montydh:BAAALgAECgEJAQAAAA==.Moonblades:BAAALgADCgUJBQAAAA==.Moonpetals:BAAALgADCgcJBwAAAA==.Moonrush:BAAALgAECgMJCAAAAA==.Mortiis:BAAALgAECgYJEwAAAA==.Motako:BAABLgAECn8gAAIIAAcJQiChFQBoAgAIAAcJQiChFQBoAgAAAA==.',
Mp='Mpd:BAAALgAECgYJCgAAAA==.',
My='Mybizël:BAABLgAECn8hAAIfAAcJSRzpIABAAgAfAAcJSRzpIABAAgAAAA==.Myrlifax:BAAALgADCgEJAQABLgAECgQJBAAEAAAAAA==.Mystique:BAAALgAECgUJBgAAAA==.Mythdaraghma:BAAALgAECgMJAwAAAA==.',
['Má']='Máximo:BAAALgAECgYJDgAAAA==.',
['Mí']='Míerin:BAAALgAECgQJBAAAAA==.Míerín:BAACLgAFFH8IAAInAAMJfRfTBwAbAQAnAAMJfRfTBwAbAQAuAAQKfyAAAycACAkrI78EAMcCACcACAkrI78EAMcCAB8ABAm+Gz9gAEcBAAAA.',
Na='Naama:BAAALgADCgMJAwAAAA==.Nadaar:BAAALgAECgUJDAAAAA==.Naelih:BAABLgAECn8XAAIVAAYJ6gSMEADEAAAVAAYJ6gSMEADEAAAAAA==.Naharuk:BAAALgADCgMJAwAAAA==.Natholomas:BAAALgADCgQJBAAAAA==.Nazeer:BAAALgADCgcJBwABLgAECgkJLQAdABwWAA==.Nazgrim:BAABLgAECn8tAAIdAAgJHBZzGgCsAQAdAAgJHBZzGgCsAQAAAA==.',
Ne='Necronu:BAAALgAFFAIJAgABLgAFFAQJDAAZAF0SAA==.',
Ni='Nikkolos:BAAALgAECgUJCwAAAA==.Ninjastax:BAAALgADCgEJAgAAAA==.Nissie:BAAALgAECgEJAQAAAA==.',
No='Nogusta:BAACLgAFFH8NAAIPAAUJFRTBCQBHAQAPAAUJFRTBCQBHAQAuAAQKfyMAAg8ACQmCHnILAP8CAA8ACQmCHnILAP8CAAAA.Norberta:BAAALgAECgcJEwAAAA==.Nossanir:BAAALgAECgIJAgAAAA==.Nossellia:BAAALgAECgQJBwAAAA==.',
Nu='Nurana:BAAALgADCgEJAQAAAA==.',
Ny='Nycecritz:BAAALgAECgEJAQAAAA==.',
Od='Odor:BAAALgAECgQJBgAAAA==.',
Ol='Oldie:BAAALgAECgIJAgAAAA==.Olielno:BAAALgADCgMJAwAAAA==.',
On='Onlyshams:BAABLgAECn8bAAIIAAgJAhgxGQBNAgAIAAgJAhgxGQBNAgAAAA==.Onlytides:BAEBLgAECn8aAAMIAAgJryPlBwD2AgAIAAgJryPlBwD2AgAJAAcJVBh+HwAUAgABLgAFFAUJFAAdAJQjAA==.Onubis:BAACLgAFFH8HAAMfAAMJaCIoDQD3AAAfAAMJfB0oDQD3AAAnAAEJVyVpEQBvAAAuAAQKfxsABB8ACAmXHxEMAOECAB8ACAmJHxEMAOECABUABgnGHW80AJcBACcAAQmpIaUmAGIAAAEuAAUUBAkMABkAXRIA.Onulock:BAAALgAECgYJCgABLgAFFAQJDAAZAF0SAA==.Onux:BAAALgAFFAIJAwABLgAFFAQJDAAZAF0SAA==.',
Op='Opgarbage:BAAALgAECgQJCAAAAA==.',
Ou='Oukei:BAAALgAECgcJEgABLgAFFAUJEAAEAAAAAQ==.Oumura:BAAALgAECgYJDgAAAA==.',
Ov='Overlordainz:BAAALgAECgUJCgAAAA==.',
Pa='Paarthürnax:BAAALgAECgYJDAAAAA==.Padamee:BAAALgAECgMJAwAAAA==.Pallyoop:BAABLgAECn8WAAIlAAcJMw9eKAAIAQAlAAcJMw9eKAAIAQAAAA==.Pandaa:BAAALgAECgEJAQAAAA==.Papapaw:BAAALgAECgQJBgAAAA==.Patholans:BAAALgAECgUJCAAAAA==.Pathology:BAAALgADCgcJBwABLgAECgUJCAAEAAAAAA==.Paxman:BAAALgAECgEJAQAAAA==.',
Pe='Peanits:BAAALgAECgQJCQABLgAECggJHgACAGgiAA==.Peanutsuckr:BAACLgAFFH8UAAIiAAUJhCOxAgCRAQAiAAUJhCOxAgCRAQAuAAQKfyMAAiIACQmoJEEEAAoDACIACQmoJEEEAAoDAAAA.Pearserve:BAAALgADCgYJBgABLgAECgYJDwAEAAAAAA==.',
Ph='Phantöm:BAAALgADCgQJBAAAAA==.Phosphate:BAABLgAECn8QAAIRAAYJNxKsbgBYAQARAAYJNxKsbgBYAQAAAA==.',
Pi='Pingg:BAAALgAECgQJBQAAAA==.Pinkeye:BAAALgADCgEJAQAAAA==.Pippafan:BAAALgAECgEJAQAAAA==.',
Pl='Planknstein:BAAALgADCgMJAwAAAA==.Playdohh:BAAALgAECgcJCQAAAA==.Plutonia:BAAALgAECgMJBgAAAA==.',
Po='Pockett:BAAALgAECgUJDwAAAA==.Powrwordgoat:BAABLgAECn8fAAIGAAgJuxFBIQCJAQAGAAgJuxFBIQCJAQAAAA==.',
Pr='Prestoh:BAABLgAECn8aAAIJAAcJRBN/FwBXAQAJAAcJRBN/FwBXAQAAAA==.Prismclaw:BAABLgAECn8gAAISAAgJzwfbQgBmAQASAAgJzwfbQgBmAQAAAA==.Processing:BAAALgAECgYJBgAAAA==.',
Ps='Pseudoruski:BAAALgADCgMJAwAAAA==.',
Pu='Purplehaze:BAAALgADCggJEQAAAA==.',
Pv='Pvlolz:BAABLgAECn8YAAIWAAgJxAo8MACAAQAWAAgJxAo8MACAAQAAAA==.',
Qa='Qaharn:BAAALgAECgQJBAAAAA==.',
Qp='Qplus:BAABLgAECn8UAAIfAAYJZgjoQQAPAQAfAAYJZgjoQQAPAQAAAA==.',
Qu='Quaenie:BAAALgAECgYJEwAAAA==.Quintin:BAAALgAECgYJBwAAAA==.',
Ra='Raged:BAAALgAECgUJCgAAAA==.Ragetotem:BAABLgAECn8dAAIJAAYJmRwbKADSAQAJAAYJmRwbKADSAQAAAA==.Ragewarg:BAAALgAECgQJBAAAAA==.Ragnashock:BAAALgAECgQJBgAAAA==.Ralvarr:BAAALgAECgcJDAAAAA==.Raptorjésus:BAAALgADCgcJCwAAAA==.Rathaes:BAAALgADCgMJAwAAAA==.Ravenstryke:BAAALgAECgEJAQAAAA==.Raylea:BAAALgADCgcJBwAAAA==.Rayleigh:BAAALgAECgUJBgABLgAECgUJCwAEAAAAAA==.Razzgix:BAAALgAECgUJBgAAAA==.',
Re='Redchord:BAAALgADCgUJDAAAAA==.Regidør:BAABLgAECn8ZAAMlAAgJ/CBdCADoAgAlAAgJ/CBdCADoAgAFAAYJxx0ZYQDBAQAAAA==.Relik:BAABLgAECn8VAAIgAAYJVQ0KFADtAAAgAAYJVQ0KFADtAAAAAA==.Resith:BAAALgAECgYJCAAAAA==.',
Rh='Rhaelia:BAABLgAECn8ZAAIFAAcJFQn4SAAvAQAFAAcJFQn4SAAvAQAAAA==.Rhaspus:BAAALgADCgQJBAAAAA==.',
Ri='Rilliccine:BAAALgADCgkJCQAAAA==.Rillinetti:BAABLgAECn8SAAIKAAcJzQ9uMABpAQAKAAcJzQ9uMABpAQAAAA==.Rillini:BAAALgADCgcJBwAAAA==.Rilliti:BAAALgAECgEJAQAAAA==.',
Ro='Rondon:BAABLgAECn8WAAIfAAcJriSDBwB/AgAfAAcJriSDBwB/AgAAAA==.Rookdh:BAACLgAFFH8DAAIBAAMJXQMHCADUAAABAAMJXQMHCADUAAAuAAQKfyMAAxEACQmWFQU5AP8AAAEABwkuFt4sAGMBABEACAnDFgU5AP8AAAAA.Rorcia:BAAALgADCgYJDQAAAA==.Rosey:BAAALgAECgcJEgAAAA==.Roxania:BAAALgADCgYJBgAAAA==.Royale:BAAALgADCgUJBQAAAA==.',
Ru='Rudyeightbal:BAABLgAECn8aAAMKAAgJCAxgQgAqAQAKAAYJhQ1gQgAqAQAYAAIJGQN9LAAAAAAAAA==.Ruedons:BAAALgAECgIJAgAAAA==.Rugsalon:BAACLgAFFH8FAAISAAIJ2AdZUQCeAAASAAIJ2AdZUQCeAAAuAAQKfyIAAhIACAmyHfE0AJ8CABIACAmyHfE0AJ8CAAAA.Rustedbarrel:BAABLgAECn8ZAAIXAAgJuBNyIQD2AQAXAAgJuBNyIQD2AQAAAA==.',
Ry='Ryptar:BAAALgADCgkJFgAAAA==.',
['Ré']='Réxxar:BAABLgAECn8cAAINAAcJPRTaDQClAQANAAcJPRTaDQClAQAAAA==.',
Sa='Saelyres:BAAALgAECgcJDwAAAA==.Sagesse:BAAALgADCgYJBgAAAA==.Saikye:BAAALgAECgEJAQAAAA==.Sairu:BAAALgADCgEJAQAAAA==.Samistraza:BAAALgADCgEJAQAAAA==.Sammy:BAABLgAECn8VAAIFAAYJYAmEXAD9AAAFAAYJYAmEXAD9AAAAAA==.Santaclaaws:BAACLgAFFH8GAAIRAAMJcxnDKQCwAAARAAMJcxnDKQCwAAAuAAQKfykABBEACAlFIjYSAO0CABEACAlFIjYSAO0CAAIAAwlEFogMAMsAAAEAAgk1GYZbAHIAAAAA.Santapal:BAABLgAECn8eAAIlAAcJLxrtEQDOAQAlAAcJLxrtEQDOAQABLgAFFAMJBgARAHMZAA==.Santatumblr:BAAALgAECgUJCgABLgAFFAMJBgARAHMZAA==.Santhin:BAAALgADCgcJCgAAAA==.Sareit:BAAALgAECgYJDwAAAA==.Sassee:BAAALgAECgQJBAAAAA==.Sayvil:BAAALgAECgIJAgABLgAECgcJHwAWAH4fAQ==.',
Sc='Scripture:BAAALgADCgYJBgAAAA==.',
Se='Seawolph:BAABLgAECn8cAAIIAAgJaBQNGwCLAQAIAAgJaBQNGwCLAQAAAA==.Selenia:BAAALgAECgMJAwAAAA==.Sensational:BAABLgAECn8aAAMaAAcJWhx5EwAvAgAaAAcJWhx5EwAvAgAUAAUJXgiqIwDPAAAAAA==.Sergio:BAAALgAECgcJCgAAAA==.',
Sh='Shamiska:BAAALgAECgIJAgAAAA==.Shammerdown:BAAALgAECgIJAwAAAA==.Shampooh:BAAALgADCgkJCQABLgAECgIJAgAEAAAAAA==.Shaokhan:BAABLgAECn8eAAIIAAgJZSAQAwDmAgAIAAgJZSAQAwDmAgAAAA==.Sheilla:BAAALgADCgUJBQAAAA==.Shian:BAABLgAECn8aAAINAAcJfxT0BwBmAQANAAcJfxT0BwBmAQAAAA==.Shieldee:BAABLgAECn8mAAIFAAgJShqZEQAuAgAFAAgJShqZEQAuAgAAAA==.Shlectrinell:BAABLgAECn8nAAMoAAgJHQuCDAChAQAoAAgJjwqCDAChAQAmAAgJBAUICwB+AQAAAA==.Shockeei:BAACLgAFFH8SAAISAAUJMyUCCQCvAQASAAUJMyUCCQCvAQAuAAQKfyMABBIACQlbJK0UACwDABIACQlbJK0UACwDACkAAwlSGHgJALkAABwAAQnWIMcIAGMAAAAA.Shocktroop:BAAALgADCgYJCgAAAA==.Shortdon:BAAALgADCgcJBwAAAA==.Shurp:BAAALgAECgMJAwAAAA==.',
Si='Siakora:BAABLgAECn8UAAIoAAcJUBsHGwAoAgAoAAcJUBsHGwAoAgABLgAFFAUJEwAkAK0aAA==.Sicksty:BAAALgADCgcJBwAAAA==.Sighhy:BAAALgAECgIJBgAAAA==.Sijth:BAABLgAECn87AAIFAAgJIh+dDABhAgAFAAgJIh+dDABhAgAAAA==.Silentchaos:BAAALgADCgMJBQAAAA==.Siler:BAAALgADCgYJBgAAAA==.Silverwar:BAABLgAECn8YAAIPAAcJ0xQgGABvAQAPAAcJ0xQgGABvAQAAAA==.Simmi:BAECLgAFFH8UAAIdAAUJlCPOAgD3AQAdAAUJlCPOAgD3AQAuAAQKfyMAAh0ACQmQJXYGACQDAB0ACQmQJXYGACQDAAAA.Sinnis:BAAALgAECgEJAQAAAA==.Sixtea:BAABLgAECn8aAAIJAAgJmRNDHgAlAQAJAAgJmRNDHgAlAQAAAA==.',
Sk='Skepti:BAABLgAECn8bAAIfAAgJ/BBxJwB6AQAfAAgJ/BBxJwB6AQAAAA==.Skysong:BAAALgAECgMJAwAAAA==.',
Sl='Slimfoo:BAAALgAECgcJDQAAAA==.Slunkyspit:BAAALgADCgUJCAAAAA==.Slybearclaw:BAAALgADCgUJBQAAAA==.',
Sm='Smeeta:BAABLgAECn8zAAIbAAgJ1SBDCQCLAgAbAAgJ1SBDCQCLAgAAAA==.Smoak:BAAALgADCgUJBQAAAA==.Smolderlight:BAABLgAECn8kAAIlAAkJ9xF/DgD1AQAlAAkJ9xF/DgD1AQAAAA==.Smoochiebutt:BAAALgAECgQJBAAAAA==.',
So='Solaace:BAAALgAECgEJAQABLgAECgIJAgAEAAAAAA==.Solo:BAAALgAECgYJCQAAAA==.Soloris:BAAALgADCgcJCAAAAA==.Sonja:BAAALgAECgcJBwAAAA==.Soram:BAAALgAECgYJCgAAAA==.Soulstryker:BAAALgAECgEJAQAAAA==.Soùl:BAAALgADCgQJBAAAAA==.',
Sp='Spacepants:BAAALgAECgEJAQAAAA==.',
St='Staraelle:BAAALgAECgEJAgAAAA==.Steelerayne:BAAALgAECgYJCwAAAA==.Strangerdk:BAABLgAECn8XAAIbAAcJbweaRgArAQAbAAcJbweaRgArAQAAAA==.Streetdog:BAAALgADCgYJBgAAAA==.',
Su='Superfatbaby:BAAALgAECgcJEQAAAA==.',
Sw='Swikk:BAAALgADCgYJCAAAAA==.Swishersweet:BAABLgAECn8ZAAINAAgJqgPgHgCpAAANAAgJqgPgHgCpAAAAAA==.Swordfish:BAABLgAECn8WAAIjAAYJdB7WBABvAQAjAAYJdB7WBABvAQAAAA==.',
Sy='Sybros:BAAALgADCgEJAQAAAA==.Sydonie:BAAALgAECgEJAgAAAA==.Symbah:BAAALgADCgYJBgAAAA==.Synvalid:BAABLgAECn8ZAAIRAAkJswf8LwAjAQARAAkJswf8LwAjAQAAAA==.Syzrin:BAAALgADCgEJAQABLgADCgYJBgAEAAAAAA==.',
Ta='Tabmage:BAABLgAECn8kAAISAAgJyRrWFwAeAgASAAgJyRrWFwAeAgAAAA==.Tadokof:BAAALgADCgIJAgAAAA==.Talanth:BAAALgAECgYJCwAAAA==.Tandisong:BAAALgADCgYJBgAAAA==.Tanknhammerm:BAAALgADCgYJBgAAAA==.Tanknstein:BAAALgADCgYJBgAAAA==.Tanton:BAAALgAECgMJAwAAAA==.Tanzil:BAAALgAECgYJDgAAAA==.Tardigrade:BAAALgAECgIJAgAAAA==.Tayon:BAAALgAECgYJDAAAAA==.Tayvin:BAAALgADCgQJBwAAAA==.Tazanath:BAAALgADCgEJAQAAAA==.',
Te='Tempest:BAAALgADCgcJBwAAAA==.Tengen:BAAALgAECgUJDAAAAA==.Termana:BAACLgAFFH8VAAIgAAUJjx/kAgByAQAgAAUJjx/kAgByAQAuAAQKfyIAAiAACQmSI4MCAEMDACAACQmSI4MCAEMDAAAA.',
Th='Tharja:BAABLgAECn8aAAISAAgJLB3sNACfAgASAAgJLB3sNACfAgAAAA==.Thornp:BAAALgAECgEJAgAAAA==.Thoronk:BAAALgAECgcJBgAAAA==.Thsaric:BAAALgADCgkJFAAAAA==.Thug:BAABLgAECn8WAAMPAAcJ0R/QJQArAgAPAAcJ0R/QJQArAgAgAAIJHxvQNgCRAAAAAA==.',
Ti='Tiferet:BAABLgAECn8dAAQWAAgJ2h7YAwCgAgAWAAgJ2h7YAwCgAgAGAAMJfRLkPgC3AAAHAAIJtAV4ZwAqAAAAAA==.Tigiw:BAAALgADCgYJBgAAAA==.Tinysunshine:BAAALgAECgUJCQAAAA==.Tismyhammer:BAAALgADCgQJBAAAAA==.',
To='Toasted:BAAALgADCgQJAQAAAA==.Tolenkar:BAABLgAECn8VAAIfAAYJORw8HwClAQAfAAYJORw8HwClAQAAAA==.Tomato:BAACLgAFFH8QAAMYAAUJ0w7PBwDxAAAYAAMJXw3PBwDxAAAKAAQJug4cLwDoAAAuAAQKfyMAAxgACQlpHacFAHoCABgACAkIHKcFAHoCAAoABQlZF3hAADABAAAA.Tomhanks:BAAALgAECgQJBAAAAA==.Tormentaa:BAAALgAECgYJBwAAAA==.Torvalar:BAABLgAECn8oAAIFAAgJjRCWMwB0AQAFAAgJjRCWMwB0AQAAAA==.',
Tr='Treemendous:BAAALgADCgYJCQAAAA==.Truthslayer:BAABLgAECn8VAAMPAAkJ9QXNJgAKAQAPAAkJ9QXNJgAKAQAQAAEJbAr9QgAzAAAAAA==.Trûth:BAABLgAECn8WAAIHAAgJvBBKIwC9AQAHAAgJvBBKIwC9AQAAAA==.',
Tu='Turdyl:BAABLgAECn8fAAIFAAkJkw6CcwCUAQAFAAkJkw6CcwCUAQAAAA==.',
Tw='Twindad:BAAALgADCgkJEQAAAA==.Twindadlock:BAAALgADCgEJAQAAAA==.',
Ty='Tyraz:BAAALgAECgcJEwAAAA==.Tystrolf:BAAALgAECgcJDwAAAA==.',
Tz='Tzar:BAAALgADCgIJAgAAAA==.',
['Tô']='Tôx:BAABLgAECn8UAAMJAAcJVR2fGABNAQAJAAcJVR2fGABNAQAIAAEJyhWxoAAwAAAAAA==.',
Ub='Ubrew:BAAALgAECgkJBQAAAA==.',
Ud='Udyrr:BAAALgADCgIJAgAAAA==.',
Ul='Ulfius:BAAALgADCgMJAwAAAA==.Ullume:BAAALgAECgMJAwAAAA==.',
Um='Umbranwings:BAAALgAECgQJBAAAAA==.',
Un='Undeadarnix:BAAALgAECgQJCwAAAA==.Unheardjp:BAAALgAECgMJCQAAAA==.Unholy:BAAALgADCgMJAwAAAA==.',
Ur='Ursus:BAAALgADCgYJBgAAAA==.',
Va='Vacuum:BAAALgAECgYJEAAAAA==.Vadican:BAAALgADCgQJBAAAAA==.Vaerix:BAABLgAECn8jAAIZAAgJrQ4AFABiAQAZAAgJrQ4AFABiAQAAAA==.Valhals:BAABLgAECn8VAAIXAAUJuQQBMgCaAAAXAAUJuQQBMgCaAAAAAA==.Valydrin:BAABLgAECn8nAAIWAAgJYB08BQByAgAWAAgJYB08BQByAgAAAA==.Vanhelsinky:BAAALgADCgIJAgAAAA==.Vanquished:BAAALgAECgIJAwAAAA==.Varyn:BAAALgADCgIJAgAAAA==.',
Ve='Velandia:BAAALgAECgcJCAAAAA==.Ventis:BAAALgAECgQJBwAAAA==.',
Vi='Vicara:BAAALgADCgYJBgAAAA==.',
Vo='Voidifphat:BAAALgAECggJDAAAAA==.Voidtorrent:BAAALgAECgQJCAAAAA==.Voidvanquish:BAAALgAECgUJBQAAAA==.Vorkhan:BAAALgADCgUJBwAAAA==.',
Vu='Vuldrak:BAAALgAECgcJEgAAAA==.',
Vy='Vysis:BAACLgAFFH8LAAQHAAMJ6AfvDQDoAAAHAAMJ6AfvDQDoAAAGAAMJVQn3EgDeAAAWAAIJ1AwCDgCOAAAuAAQKfzYABBYACQmrGYgSAEwCABYACAnEGIgSAEwCAAYABwlEFacKAOMBAAcABwk+GVoKANsBAAAA.',
['Vä']='Vännic:BAAALgADCgEJAwAAAA==.Vännìc:BAAALgADCgEJAQAAAA==.',
['Ví']='Ví:BAAALgAECgQJCAAAAA==.',
Wh='Whatfoxsay:BAAALgADCgEJAQAAAA==.Whats:BAAALgADCgcJBwABLgAECgQJBQAEAAAAAA==.When:BAAALgADCgQJBAAAAA==.Whicker:BAAALgAECgUJBgAAAA==.Whipsnchains:BAAALgAECgMJAwAAAA==.Whipsntricks:BAAALgADCgYJBgAAAA==.',
Wi='Wickèr:BAABLgAECn8oAAIXAAgJKh2XBgAyAgAXAAgJKh2XBgAyAgAAAA==.Wieldblade:BAABLgAECn8iAAIFAAgJ3x0dKACEAgAFAAgJ3x0dKACEAgAAAA==.Winslett:BAAALgADCgQJBAAAAA==.',
Wo='Wolfemoon:BAAALgAECgQJCwAAAA==.',
Wr='Wrexd:BAABLgAECn8qAAIKAAgJBBuVEQAYAgAKAAgJBBuVEQAYAgAAAA==.',
Wu='Wunderbar:BAABLgAECn8aAAMJAAcJ7xzdCgDsAQAJAAcJ7xzdCgDsAQAIAAEJRxrklwBAAAAAAA==.',
Wy='Wyldfire:BAACLgAFFH8LAAIkAAMJMhbeDwD+AAAkAAMJMhbeDwD+AAAuAAQKfygAAyQACAklJPULANgCACQACAklJPULANgCAB0AAglkF4yeAI4AAAAA.Wyndclaw:BAAALgAECgMJAwAAAA==.',
Xa='Xanith:BAABLgAECn8VAAIPAAcJhQ9/GABsAQAPAAcJhQ9/GABsAQAAAA==.',
Xe='Xebubble:BAAALgADCgEJAQABLgAECgEJAQAEAAAAAA==.Xemonk:BAAALgAECgEJAQAAAA==.',
Xi='Xia:BAAALgADCgYJBgAAAA==.',
Ya='Yaganor:BAAALgADCgUJBgAAAA==.',
Ye='Yeto:BAAALgADCgYJBwAAAA==.',
Yi='Yia:BAAALgAECgQJBAAAAA==.Yilnara:BAAALgAECgcJDwAAAA==.',
Za='Zajindor:BAAALgADCgEJAQAAAA==.Zarathul:BAAALgADCgIJAgAAAA==.',
Ze='Zekkun:BAAALgAECgEJAQAAAA==.',
Zi='Zirael:BAAALgADCgYJCgAAAA==.',
Zo='Zoganian:BAEALgAECgEJAQABLgAECgcJFAAWAD0jAA==.Zogula:BAEBLgAECn8UAAMWAAcJPSP4BgBEAgAWAAcJ/CL4BgBEAgAGAAEJaCOyLABnAAAAAA==.',
Zu='Zu:BAAALgAECgQJCgAAAA==.',
['År']='Årtemis:BAABLgAECn8eAAInAAgJQBouCADiAQAnAAgJQBouCADiAQAAAA==.',
['Æb']='Æbony:BAAALgADCgMJAwAAAA==.',
['Ïr']='Ïrini:BAAALgAECgIJAwABLgAECgYJBwAEAAAAAA==.',
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

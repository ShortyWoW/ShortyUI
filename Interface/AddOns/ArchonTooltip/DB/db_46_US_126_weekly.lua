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

local lookup = {'Unknown-Unknown','Evoker-Preservation','Evoker-Augmentation','Warrior-Arms','Monk-Windwalker','Paladin-Retribution','Paladin-Protection','Hunter-BeastMastery','Priest-Holy','Priest-Shadow','Paladin-Holy','Druid-Restoration','Shaman-Restoration','Druid-Balance','Mage-Frost','Warlock-Demonology','Hunter-Survival','Monk-Mistweaver','Warrior-Fury','Evoker-Devastation','Shaman-Elemental','DeathKnight-Unholy','Warlock-Destruction','Warlock-Affliction','Monk-Brewmaster','Druid-Guardian','DeathKnight-Blood','DemonHunter-Devourer','DemonHunter-Havoc','Warrior-Protection','DemonHunter-Vengeance','Shaman-Enhancement','Hunter-Marksmanship','Rogue-Subtlety','Druid-Feral','Rogue-Assassination','Mage-Fire','Mage-Arcane','Priest-Discipline',}
local provider = {region='US',realm="Kael'thas",name='US',type='weekly',zone=46,date='2026-05-08',data={Ad='Adorraa:BAAALgAECgQJBAABLgAECgYJDAABAAAAAA==.Adoryn:BAAALgADCgMJAwAAAA==.Adowyrm:BAACLgAFFH8VAAMCAAYJiBn9BgCwAQACAAUJJhz9BgCwAQADAAEJewZeNgBSAAAuAAQKfyEAAwIACQm1IUYCAFEDAAIACQm1IUYCAFEDAAMABgnLHfMcAN8BAAAA.Adriaat:BAAALgADCgMJAwAAAA==.Adrielle:BAAALgADCgMJAwAAAA==.',
Ae='Aeife:BAEALgADCgEJAQABLgAECggJFgAEACoZAA==.',
Af='Afflockted:BAAALgADCgQJBAAAAA==.',
Ag='Agicat:BAAALgAECgUJDAABLgAECggJHgAFAFogAA==.',
Ai='Airali:BAABLgAECn8XAAMGAAkJ/hNtZAC4AQAGAAkJ/hNtZAC4AQAHAAMJiQjONwBiAAAAAA==.Airedale:BAABLgAECn8YAAIIAAYJ2Q3uSwAqAQAIAAYJ2Q3uSwAqAQAAAA==.',
Ak='Akairo:BAABLgAECn8tAAMJAAkJACSCAgBBAwAJAAkJACSCAgBBAwAKAAgJzw5mFgCMAQAAAA==.Akelia:BAAALgAECgEJAgAAAA==.Akonic:BAAALgADCgkJDgAAAA==.',
Al='Alasteria:BAAALgAECgkJAgAAAA==.Alcoaplus:BAAALgADCgkJFgABLgAECgkJJAADAMcfAA==.Alexanderxl:BAAALgAECgYJDgABLgAECggJAwABAAAAAA==.Aleybobwa:BAABLgAECn8fAAMLAAkJjRI9FADwAQALAAkJjRI9FADwAQAGAAEJYwiHUgErAAAAAA==.Alody:BAAALgADCgMJAwAAAA==.',
Am='Amethen:BAAALgADCgMJAwAAAA==.Amochi:BAAALgAECgkJDwAAAA==.Amulius:BAABLgAECn8wAAIGAAkJAiVFAQBiAwAGAAkJAiVFAQBiAwAAAA==.',
An='Anderdingus:BAAALgADCgUJBQAAAA==.Andormath:BAAALgAECgEJAgAAAA==.Andramedae:BAABLgAECn8aAAIMAAgJJBNCHQDZAQAMAAgJJBNCHQDZAQAAAA==.Angerissues:BAAALgADCgkJCQAAAA==.Angyavocado:BAAALgADCgkJCQAAAA==.Anoki:BAABLgAECn8hAAINAAkJSxg8CgCJAgANAAkJSxg8CgCJAgAAAA==.',
Ao='Aolus:BAACLgAFFH8PAAIOAAQJzxbuDABHAQAOAAQJzxbuDABHAQAuAAQKfxsAAg4ACQkVHCsTAHwCAA4ACQkVHCsTAHwCAAAA.',
Ap='Aphratite:BAAALgADCgMJAwAAAA==.Apoliis:BAAALgAECgEJAQAAAA==.',
Ar='Arbol:BAAALgADCgYJCAABLgAECgIJAwABAAAAAA==.Arcaina:BAABLgAECn8VAAIPAAcJhwkbZQBHAQAPAAcJhwkbZQBHAQAAAA==.Ares:BAAALgADCgcJBwABLgAECggJHwAQAOQUAA==.Arez:BAABLgAECn8fAAIQAAgJ5BQNJADbAQAQAAgJ5BQNJADbAQAAAA==.Arilass:BAAALgADCgIJBAAAAA==.Artèmís:BAABLgAECn8hAAIRAAgJ5yTBAQDuAgARAAgJ5yTBAQDuAgABLgAECggJLQASAAwfAA==.',
As='Ashborn:BAAALgADCgEJAQAAAA==.Ashtongue:BAAALgADCgMJAwAAAA==.Asladur:BAAALgADCgcJCgAAAA==.',
At='Athenä:BAAALgAECgIJAgAAAA==.',
Az='Azaekho:BAABLgAECn8kAAINAAkJcxQaHwC6AQANAAkJcxQaHwC6AQAAAA==.',
Ba='Baalzak:BAAALgADCgQJBQAAAA==.Backfliphoe:BAAALgAECgcJBwAAAA==.Badoosh:BAABLgAECn8iAAITAAgJCB2ZGACHAgATAAgJCB2ZGACHAgAAAA==.Badragon:BAAALgAECgcJBwAAAA==.Bajablaster:BAABLgAECn8cAAQUAAgJYB9EAQCKAgAUAAgJYB9EAQCKAgADAAMJ5BD0TACdAAACAAEJMAuqKQAtAAAAAA==.Baliw:BAAALgADCgUJBAAAAA==.Balto:BAAALgADCgMJAwAAAA==.',
Bb='Bbl:BAECLgAFFH8MAAIVAAQJig/sEQAjAQAVAAQJig/sEQAjAQAuAAQKfyEAAhUACAlBH1UKAPACABUACAlBH1UKAPACAAAA.',
Bc='Bchung:BAACLgAFFH8PAAIPAAQJ2xFsMABIAQAPAAQJ2xFsMABIAQAuAAQKfyIAAg8ACQnDGZE7AIkCAA8ACQnDGZE7AIkCAAAA.',
Be='Beertits:BAAALgAECgEJAQAAAA==.Belip:BAAALgAFFAEJAgAAAA==.',
Bh='Bhain:BAAALgADCgcJDQABLgAFFAIJAwABAAAAAA==.',
Bi='Bieorne:BAABLgAECn8oAAIWAAgJNCCKDwCDAgAWAAgJNCCKDwCDAgAAAA==.',
Bl='Blastbane:BAABLgAFFH8GAAIQAAMJRg2qQwDTAAAQAAMJRg2qQwDTAAAAAA==.Bloodwrath:BAAALgADCgQJBAAAAA==.',
Bn='Bnanaketchup:BAAALgADCgQJBAAAAA==.',
Bo='Boo:BAABLgAECn8YAAMQAAkJ7xz+DwD6AgAQAAkJ7xz+DwD6AgAXAAEJAACCMQAAAAABLgAFFAMJBwALAGsbAA==.Boondocks:BAABLgAECn8cAAMYAAgJ/xZXCAAZAQAQAAUJXxFoUAA5AQAYAAQJMSBXCAAZAQAAAA==.',
Br='Braca:BAAALgADCgEJAgAAAA==.Braelek:BAAALgADCgEJAQAAAA==.Brewslei:BAAALgADCgYJBgAAAA==.Brewtime:BAABLgAECn8WAAIZAAgJBhC2FwB6AQAZAAgJBhC2FwB6AQABLgAECggJIgAaAJcaAA==.Brielle:BAABLgAECn8kAAIIAAgJ/BYlIgDQAQAIAAgJ/BYlIgDQAQAAAA==.Brokenbranch:BAAALgAECgUJCAAAAA==.Brudene:BAABLgAECn8UAAITAAcJFRE2LQAbAQATAAcJFRE2LQAbAQAAAA==.Brynhildr:BAAALgADCgYJBgAAAA==.',
Bu='Buddylock:BAABLgAECn8iAAIQAAkJmgkiPwBtAQAQAAkJmgkiPwBtAQAAAA==.Bulltaura:BAAALgADCgkJCQAAAA==.Bullymaguire:BAACLgAFFH8OAAIFAAYJQBmXBABzAQAFAAYJQBmXBABzAQAuAAQKfx0AAgUACAk5Iz8FADEDAAUACAk5Iz8FADEDAAAA.Burakkuburu:BAABLgAECn8tAAMSAAgJDB/hBADNAgASAAgJDB/hBADNAgAFAAYJ4RXZJwCbAQAAAA==.',
Ca='Caboozles:BAABLgAECn8qAAIIAAgJbBb7HwDcAQAIAAgJbBb7HwDcAQAAAA==.Caliopia:BAABLgAECn8iAAIVAAkJvBNnEADfAQAVAAkJvBNnEADfAQAAAA==.Captnhuntcat:BAAALgAECgcJCwAAAA==.Carcosa:BAAALgAECgEJAQAAAA==.Cardone:BAAALgAECgEJAQAAAA==.',
Ce='Ceromaar:BAABLgAECn8hAAITAAkJ5xD8DwD2AQATAAkJ5xD8DwD2AQAAAA==.Ceti:BAAALgAECgcJDAAAAA==.',
Ch='Chaoticdh:BAAALgADCgYJBgAAAA==.Checkurback:BAABLgAECn8UAAMbAAgJJB6aEAABAgAbAAgJJB6aEAABAgAWAAEJfRBJ3gA9AAAAAA==.Chemistree:BAABLgAECn8dAAIMAAcJiRPoJQCcAQAMAAcJiRPoJQCcAQAAAA==.Chillout:BAABLgAECn8cAAIPAAcJPA65WwBdAQAPAAcJPA65WwBdAQAAAA==.Chillums:BAABLgAECn8dAAIQAAcJ4iObEwBFAgAQAAcJ4iObEwBFAgAAAA==.Chipcle:BAAALgADCgcJCwAAAA==.Chocoflan:BAAALgADCgIJAgAAAA==.Chöpper:BAAALgADCgEJAgAAAA==.',
Cl='Clumsy:BAAALgADCgUJBQABLgADCgQJBAABAAAAAA==.',
Co='Cokarott:BAAALgAECgUJBgAAAA==.Cops:BAABLgAECn8aAAILAAgJ2A2DGgC2AQALAAgJ2A2DGgC2AQAAAA==.Coral:BAAALgADCgkJGQAAAA==.',
Cr='Criticål:BAAALgADCgIJAgAAAA==.Crusherk:BAAALgAECgcJBQAAAA==.',
Da='Dabercoo:BAAALgADCgQJBAAAAA==.Daeleiel:BAAALgAECgEJAQAAAA==.Darkenergy:BAABLgAECn8bAAMcAAgJfyPUCQCLAgAcAAgJ1x/UCQCLAgAdAAYJxSQYEwA+AgAAAA==.Darà:BAAALgADCgcJDgABLgAECgcJEwABAAAAAA==.Dashyll:BAAALgADCgkJFQAAAA==.Davyfknjones:BAAALgAECgcJDQAAAA==.Daynia:BAAALgADCgEJAQAAAA==.',
De='Deadlegslul:BAAALgAECgYJEAAAAA==.Deadlegsmd:BAAALgADCgcJCwAAAA==.Deadrat:BAAALgAECgMJAwAAAA==.Deadzepplin:BAAALgAECgUJBwAAAA==.Deathmono:BAAALgAECgYJCQAAAA==.Deathshark:BAABLgAECn8kAAIbAAgJPh28CgBsAgAbAAgJPh28CgBsAgAAAA==.Dellphine:BAAALgAECgEJAQAAAA==.Demacus:BAAALgAECgcJDAABLgAECgcJJAANAI0PAA==.Demeter:BAABLgAECn8iAAIHAAkJtxChCwCDAQAHAAkJtxChCwCDAQAAAA==.Demonhunters:BAAALgADCgcJDAAAAA==.Demontb:BAAALgAECgkJAQAAAA==.Denarien:BAAALgAECgkJDAAAAA==.Derpygos:BAAALgADCgcJBwABLgAECggJIgAaAJcaAA==.Devouress:BAABLgAECn8PAAIcAAgJFRREJQCqAQAcAAgJFRREJQCqAQABLgAECggJGAAFAEcgAA==.',
Di='Diddlesz:BAAALgAECggJAwAAAA==.Dillkiller:BAABLgAECn8XAAIeAAcJGQn9IQAuAQAeAAcJGQn9IQAuAQAAAA==.Dirgen:BAAALgAECgcJEwAAAA==.Disspair:BAAALgADCgEJAQAAAA==.',
Do='Dobbyscumsok:BAAALgAECgYJEQAAAA==.Dookiee:BAAALgAECgYJEQAAAA==.Dorksparrow:BAAALgAECgQJBwABLgAECgkJHwAZANMOAA==.Double:BAAALgADCgEJAQAAAA==.Doug:BAAALgADCgcJDQAAAA==.Doxom:BAAALgADCgEJAQAAAA==.',
Dr='Dracalled:BAABLgAECn8aAAIDAAgJYhrMCQAvAgADAAgJYhrMCQAvAgAAAA==.Draggnar:BAAALgAECgUJCAAAAA==.Dragönlöl:BAAALgAECgYJCAAAAA==.Dramme:BAAALgAECgIJAgAAAA==.Drat:BAAALgAECgcJBwAAAA==.Druidvishnu:BAAALgAECgYJCQABLgAFFAQJCQAVAC8aAA==.',
Du='Dumplingsxo:BAABLgAECn8jAAMOAAkJnBg7GQA9AgAOAAgJsBk7GQA9AgAMAAcJ4Bg9KQCIAQAAAA==.Dusktodawn:BAAALgAECgUJDgAAAA==.',
Dy='Dyharmis:BAABLgAECn8iAAIfAAkJmSRdAAAlAwAfAAkJmSRdAAAlAwAAAA==.',
Eb='Ebojager:BAABLgAECn8nAAIcAAgJFhbNHwDJAQAcAAgJFhbNHwDJAQAAAA==.',
Eh='Ehko:BAAALgAECgUJBQABLgAECggJLQASAAwfAA==.',
Ei='Eibon:BAACLgAFFH8SAAIWAAUJcxg1DQCjAQAWAAUJcxg1DQCjAQAuAAQKfx4AAhYACQnNIaUUAAADABYACQnNIaUUAAADAAAA.',
El='Elliiria:BAAALgADCggJDgAAAA==.Eloïse:BAAALgADCgYJCQAAAA==.Elthion:BAAALgADCgkJEwAAAA==.Elvispriesty:BAAALgAECgUJEQAAAA==.Elwarrioro:BAAALgAECgYJDQAAAA==.',
Em='Emmune:BAABLgAECn8cAAIgAAgJQg7nCACTAQAgAAgJQg7nCACTAQAAAA==.',
En='Enobia:BAABLgAECn8UAAMXAAYJ2hFhCwAfAQAXAAYJ2hFhCwAfAQAQAAUJFga3xADQAAAAAA==.Entrapment:BAAALgADCgYJBgABLgADCgQJBAABAAAAAA==.Envie:BAAALgAECgQJBQAAAA==.',
Er='Eriaeda:BAAALgAECgUJCgAAAA==.',
Es='Esen:BAAALgAECgEJAQABLgAECggJHwAQAOQUAA==.Eskath:BAABLgAECn8XAAIQAAgJmRtOFQA3AgAQAAgJmRtOFQA3AgABLgAECggJIgAaAJcaAA==.Essential:BAABLgAECn8YAAIGAAgJVxD+RAB2AQAGAAgJVxD+RAB2AQAAAA==.',
Et='Eternalpain:BAAALgADCgEJAQAAAA==.',
Ev='Evdoggy:BAABLgAECn8XAAIFAAYJcRN+HgAwAQAFAAYJcRN+HgAwAQAAAA==.Evilkills:BAAALgAECgMJAwAAAA==.',
Ex='Exterminate:BAAALgAECgQJBAAAAA==.',
Fe='Feekknight:BAAALgADCgQJBAAAAA==.Fellon:BAAALgADCgEJAQAAAA==.Femmur:BAAALgADCgUJBwAAAA==.Fenrin:BAAALgAECgMJAgAAAA==.Fenrîr:BAAALgADCgYJBgABLgAECgYJGAAZAB0OAA==.Ferrara:BAACLgAFFH8WAAQhAAYJySDrCwBdAQAhAAYJAR3rCwBdAQARAAEJ9iXPGAByAAAIAAEJtx+0HwBiAAAuAAQKfyAABCEACQnRIyQGADoDACEACQmLIyQGADoDAAgAAQn1I66wAGIAABEAAQk6HvsrAEYAAAAA.',
Fi='Fibermaxing:BAAALgAECgYJEgAAAA==.Finesse:BAAALgADCggJFQAAAA==.Firebåll:BAAALgAECgUJBwAAAA==.Fishbait:BAAALgADCgIJAgABLgAECgkJIgAOAFUgAA==.Fisted:BAAALgAFFAEJAQABLgAFFAMJBwALAGsbAA==.Fisterjob:BAAALgAECgEJAQAAAA==.',
Fl='Flandri:BAABLgAFFH8LAAIJAAUJWBCLBQBwAQAJAAUJWBCLBQBwAQAAAA==.Flandrie:BAAALgADCgMJAwAAAA==.Flexicute:BAAALgADCgcJDAAAAA==.',
Fo='Foxlock:BAAALgADCgYJBgAAAA==.',
Fr='Friedá:BAAALgAECgIJAwABLgAECgYJEgABAAAAAA==.Frostednip:BAABLgAECn8XAAIWAAkJsyBeNABlAgAWAAkJsyBeNABlAgAAAA==.',
Ga='Gabaghoul:BAAALgAECgQJBAAAAA==.Gabiru:BAACLgAFFH8HAAQDAAMJ9gTjJQDIAAADAAMJ9gTjJQDIAAACAAMJvQe+FAC/AAAUAAEJlwEkDABCAAAuAAQKfxUAAwIACQlTE2ESABkCAAIACQlTE2ESABkCAAMAAQm0CY9hADUAAAAA.Gadreeste:BAAALgADCgUJBQAAAA==.Galnarn:BAACLgAFFH8YAAIZAAYJcSLNAQD4AQAZAAYJcSLNAQD4AQAuAAQKfyEAAhkACQlkHfcNALQCABkACQlkHfcNALQCAAAA.Gambagood:BAAALgAECgYJCgAAAA==.Garious:BAAALgAECgcJBwABLgAFFAQJCgAWAIsgAA==.Garjingo:BAAALgAECgEJAQABLgAECggJHAAUAGAfAA==.Garlicbae:BAAALgAECgQJBAAAAA==.Garwulf:BAAALgAECgYJDAAAAA==.',
Ge='Gefaustet:BAABLgAECn8cAAIeAAgJthj8CADnAQAeAAgJthj8CADnAQAAAA==.Gelroos:BAAALgADCgEJAQAAAA==.Geryll:BAAALgADCgIJAgAAAA==.',
Gl='Glimpse:BAAALgADCgEJAQAAAA==.Glognar:BAAALgADCgQJBAAAAA==.Glorp:BAAALgAECgEJAQAAAA==.',
Go='Goatcheesè:BAAALgAECgIJAgAAAA==.Goatess:BAAALgADCgYJCQAAAA==.Goopa:BAAALgAECgYJCgAAAA==.Goopert:BAAALgADCgYJDAAAAA==.Goopy:BAAALgAECgcJEAAAAA==.Gorbachev:BAAALgADCgYJEQAAAA==.Gorehowl:BAAALgAECgEJAgAAAA==.Goro:BAAALgADCgQJBAAAAA==.',
Gr='Graybrew:BAAALgAECgYJCwAAAA==.Grayes:BAABLgAECn8XAAIaAAYJ7wVoHAB1AAAaAAYJ7wVoHAB1AAAAAA==.Grayson:BAAALgADCgUJBQAAAA==.Grorkster:BAAALgADCgUJBQAAAQ==.Grute:BAAALgAECgUJBQAAAA==.',
Gu='Gumption:BAAALgAECgEJAQAAAA==.',
Ha='Hallowshade:BAABLgAECn8XAAIiAAcJEhlSEQCUAQAiAAcJEhlSEQCUAQAAAA==.Hardran:BAAALgAECgYJEgAAAA==.Harington:BAAALgAECgkJAgAAAA==.Harmôny:BAAALgADCggJFAAAAA==.Hatreddyes:BAAALgADCgUJBQAAAA==.Hatredyes:BAAALgAECgcJCAAAAA==.',
He='Heatedsoul:BAAALgAECgEJAQAAAA==.Helare:BAAALgAECgYJCAAAAA==.Henrymorgan:BAAALgAECgkJBgAAAA==.Hexenbane:BAABLgAECn8WAAIjAAYJVQp3EQAFAQAjAAYJVQp3EQAFAQAAAA==.',
Hi='Hinatsuru:BAAALgAECgEJAQAAAA==.',
Ho='Holyzap:BAAALgAECgEJAQABLgAECgkJHgAPAHgcAA==.Hoyt:BAAALgADCgcJCwAAAA==.',
Hu='Hugme:BAAALgAECgkJAgAAAA==.Hukhan:BAAALgAECgEJAQAAAA==.Hunthard:BAAALgAECgEJAQAAAA==.Huulrokk:BAAALgADCgIJAgABLgAECgIJBQABAAAAAA==.',
Hy='Hyasin:BAAALgADCgUJDQAAAA==.Hyperreal:BAAALgAECgEJAQAAAA==.',
Ic='Ichom:BAAALgADCgMJAwABLgAECgkJDwABAAAAAA==.',
Id='Idalia:BAAALgADCgQJBAABLgADCgYJDwABAAAAAA==.',
If='Iforgotnaaru:BAAALgAECgcJCgAAAA==.',
Ik='Ikrys:BAAALgAECgYJBgAAAA==.',
Il='Illiae:BAABLgAECn8dAAIVAAcJSR8NDAAZAgAVAAcJSR8NDAAZAgAAAA==.',
Im='Impactr:BAAALgADCgMJAwAAAA==.Implanttorq:BAAALgAECgEJAQAAAA==.Imtheteapot:BAABLgAECn8qAAITAAgJHRA+FgC2AQATAAgJHRA+FgC2AQAAAA==.',
In='Innex:BAABLgAECn8eAAIWAAgJAR79IwD0AQAWAAgJAR79IwD0AQAAAA==.Innexrogue:BAAALgAECgEJAgABLgAECggJHgAWAAEeAA==.Innexvoker:BAAALgAECgUJCgABLgAECggJHgAWAAEeAA==.Inpesca:BAAALgADCgUJBQABLgAECgkJJAADAMcfAA==.Insanityx:BAAALgAECggJCAAAAA==.',
Io='Ionic:BAAALgAECgQJBQAAAA==.',
Ir='Iridescent:BAAALgAECgIJAgAAAA==.Ironpalm:BAAALgAECgcJBwAAAA==.',
Is='Issidora:BAAALgAECgYJDgAAAA==.',
It='Ithronel:BAAALgADCgUJBQAAAA==.Itzmuffin:BAABLgAECn8hAAINAAgJ7xHmNgCnAQANAAgJ7xHmNgCnAQAAAA==.Itzpie:BAABLgAECn8sAAIPAAgJkxYAMgDYAQAPAAgJkxYAMgDYAQAAAA==.',
Ja='Jadandotz:BAAALgADCggJAgAAAA==.Jagtat:BAAALgAECgYJDwAAAA==.Jakeakuma:BAABLgAECn8UAAIQAAkJBAwcXwCsAQAQAAkJBAwcXwCsAQAAAA==.Jascob:BAABLgAECn8WAAIkAAUJdgZMDwC+AAAkAAUJdgZMDwC+AAAAAA==.',
Je='Jessa:BAAALgADCgMJAwAAAA==.',
Jh='Jhivago:BAAALgADCgEJAQAAAA==.',
Jo='Johnivxx:BAAALgADCggJCwAAAA==.Johnnybravo:BAAALgAECgIJBAAAAA==.',
Ju='Judokeg:BAABLgAECn8jAAIZAAkJcBznBACYAgAZAAkJcBznBACYAgAAAA==.Juglass:BAAALgADCgEJAQAAAA==.Jujutsu:BAABLgAECn8eAAIFAAgJWiBYCAD0AgAFAAgJWiBYCAD0AgAAAA==.Junfan:BAAALgAECgcJAwAAAA==.',
['Jà']='Jàckblack:BAAALgADCgEJAQAAAA==.',
Ka='Kaashaa:BAABLgAECn8tAAIIAAkJOyETAwAPAwAIAAkJOyETAwAPAwAAAA==.Kaelsgf:BAAALgADCgIJAgAAAA==.Kahllan:BAAALgAECgcJEwAAAA==.Kahnigitt:BAAALgAECgYJCgAAAA==.Kataltoholic:BAABLgAECn8UAAIPAAYJOAHFyQB4AAAPAAYJOAHFyQB4AAAAAA==.Katrath:BAAALgADCgMJBgAAAA==.Kayser:BAAALgAECgIJAgAAAA==.Kaýhas:BAABLgAECn8OAAIcAAYJCxp3UAC1AQAcAAYJCxp3UAC1AQAAAA==.',
Ke='Kelinïsha:BAABLgAECn8jAAIPAAgJJArhWQBhAQAPAAgJJArhWQBhAQAAAA==.Kelynna:BAABLgAECn8bAAIJAAYJ7B4SIADhAQAJAAYJ7B4SIADhAQAAAA==.Kevinarnold:BAAALgADCgEJAQAAAA==.Kevinbacon:BAAALgAECgEJAwAAAA==.',
Kh='Khelldyr:BAAALgAECggJCAAAAA==.Khellrond:BAAALgAECgkJCgAAAA==.Khuntress:BAAALgADCgUJBQAAAA==.',
Ki='Kiiras:BAABLgAECn8nAAIPAAgJLwyISgCIAQAPAAgJLwyISgCIAQAAAA==.Kimbodh:BAACLgAFFH8KAAIcAAQJth+/DgB/AQAcAAQJth+/DgB/AQAuAAQKfx8AAhwACAlaI7INAF0CABwACAlaI7INAF0CAAEuAAEKAwkBAAEAAAAA.Kinvictusk:BAAALgAECgEJAQAAAA==.Kirathein:BAABLgAECn8eAAIcAAgJiQ+nMgBrAQAcAAgJiQ+nMgBrAQAAAA==.',
Kl='Klefthoof:BAABLgAECn8kAAINAAcJjQ8eMABQAQANAAcJjQ8eMABQAQAAAA==.',
Ko='Kodey:BAABLgAECn8UAAIXAAcJCRFACABZAQAXAAcJCRFACABZAQABLgAECggJGAAXACkSAA==.Kordy:BAAALgAECgkJAQAAAA==.',
Kr='Kraniah:BAAALgAECgIJBQAAAA==.Krimboz:BAABLgAECn8bAAIQAAYJahbPSQBLAQAQAAYJahbPSQBLAQAAAA==.Krimbrouge:BAAALgADCgEJAQAAAA==.Krimdk:BAAALgADCgcJBwAAAA==.Krystallight:BAABLgAECn8cAAIRAAcJmRQpEACoAQARAAcJmRQpEACoAQAAAA==.Krìsta:BAABLgAECn8ZAAMYAAcJ6wpXDQBgAQAYAAYJWAxXDQBgAQAQAAcJJgQ6cwDjAAAAAA==.',
Ku='Kuanshuwo:BAABLgAECn8VAAMKAAgJ8AmOGgBoAQAKAAgJ8AmOGgBoAQAJAAYJfQZHTgD/AAAAAA==.Kullomaa:BAAALgAECgcJBQAAAA==.',
La='Lanwulf:BAAALgADCggJDQAAAA==.Lastgasp:BAAALgADCgcJBwAAAA==.Lauriela:BAAALgAECgQJCwAAAA==.',
Le='Lechuzón:BAAALgADCgMJAwAAAA==.Ledrõllan:BAABLgAECn8YAAIKAAkJbx26FwAmAgAKAAkJbx26FwAmAgAAAA==.Legaloas:BAABLgAECn8gAAMIAAgJLxr/HQDoAQAIAAgJrxn/HQDoAQAhAAUJVRBWDQAWAQAAAA==.Leinhart:BAAALgAECgUJCQAAAA==.Lenah:BAAALgAECgUJCAAAAA==.Leonarde:BAACLgAFFH8PAAMIAAQJKBnpDwBaAQAIAAQJIBnpDwBaAQAhAAMJ2Q/DFQDuAAAuAAQKfyEABCEACQlCFrkgACACACEACAkSF7kgACACAAgABAlNFlZEAEABABEAAQlWAKozAA0AAAAA.Levitt:BAAALgAECgYJEgAAAA==.',
Li='Lilsia:BAAALgADCgEJAQAAAA==.Lilwok:BAABLgAECn8kAAIFAAgJvxMrEwCaAQAFAAgJvxMrEwCaAQAAAA==.Lintelworth:BAAALgADCgYJFAAAAA==.Liradia:BAAALgAECgIJAwAAAA==.Liver:BAAALgAECgEJAQAAAA==.',
Ll='Llevanya:BAABLgAECn8kAAIGAAgJMgeOWgA7AQAGAAgJMgeOWgA7AQAAAA==.Llinaigh:BAAALgAECgcJEwAAAA==.',
Lo='Loanna:BAAALgADCgYJDwAAAA==.Lobao:BAAALgAECgEJAQABLgAECggJGwATANodAA==.Lomu:BAABLgAECn8iAAQaAAgJlxrrBQD0AQAaAAgJlxrrBQD0AQAMAAEJ7Q5IzwAvAAAOAAEJigSyYQAkAAAAAA==.Loredalso:BAAALgADCggJFgAAAA==.Lorenitha:BAAALgAECgEJAQAAAA==.',
Lu='Lunastraz:BAAALgADCgkJDwAAAA==.',
Ma='Magerproblem:BAAALgAFFAEJAQABLgAFFAMJBwALAGsbAA==.Magicdreams:BAABLgAECn8nAAIOAAgJvQcbIAA2AQAOAAgJvQcbIAA2AQAAAA==.Malificent:BAAALgADCgQJCAAAAA==.Malmorte:BAABLgAECn8VAAIWAAYJWRT9ogA6AQAWAAYJWRT9ogA6AQAAAA==.Malorane:BAABLgAECn8uAAIbAAkJFhviBQBEAgAbAAkJFhviBQBEAgAAAA==.Mana:BAAALgADCgUJBQAAAA==.Marcasite:BAAALgAECgEJAQAAAA==.Marihuano:BAAALgADCgYJCAABLgADCgcJCwABAAAAAA==.Marisi:BAAALgADCggJCAABLgADCgkJCQABAAAAAA==.Masumune:BAAALgAECgQJBAAAAA==.Matamosca:BAABLgAECn8gAAIiAAkJwx3EAwCaAgAiAAkJwx3EAwCaAgAAAA==.Materiaga:BAABLgAECn8iAAQDAAgJEBFZFAClAQADAAgJvxBZFAClAQACAAYJFQtZKQAoAQAUAAMJjw8tDgCoAAAAAA==.Mature:BAAALgADCgIJAgAAAA==.Maz:BAABLgAECn8fAAIGAAgJViHiDgCGAgAGAAgJViHiDgCGAgAAAA==.',
Mc='Mcflury:BAABLgAECn8oAAMgAAkJGxU2BgCWAgAgAAkJGxU2BgCWAgAVAAgJyg80IABNAQAAAA==.',
Me='Meerchi:BAABLgAECn8lAAMPAAgJLBUcMADgAQAPAAgJLBUcMADgAQAlAAQJWAPACgCVAAAAAA==.Meetyomaker:BAAALgAECgUJCAAAAA==.Meowkai:BAAALgAECgYJBgABLgAECggJLQASAAwfAA==.Mesthos:BAAALgAECgcJDAABLgAECggJGQAfAHIlAA==.Mestyphe:BAAALgAECgMJAwAAAA==.Metalmoth:BAAALgADCgEJAQAAAA==.Metformin:BAABLgAECn8lAAIDAAgJlBKGGgD2AQADAAgJlBKGGgD2AQAAAA==.',
Mi='Mickieta:BAABLgAECn8cAAIGAAgJYB/kEwBbAgAGAAgJYB/kEwBbAgAAAA==.Microsurge:BAABLgAECn8cAAIPAAgJIh3XJQDbAgAPAAgJIh3XJQDbAgAAAA==.Mikalau:BAAALgAECgYJEgAAAA==.Mikaluu:BAAALgAECgYJBwAAAA==.Miqkail:BAAALgAECggJCgABLgAECggJGQAfAHIlAA==.Missteek:BAAALgAECgEJAgABLgAECggJHAAUAGAfAA==.Mistrunner:BAAALgAECgMJAwAAAA==.Mistspell:BAACLgAFFH8PAAIKAAQJpQ9HDQA2AQAKAAQJpQ9HDQA2AQAuAAQKfx8AAwoACQkVG+AOAJUCAAoACQkVG+AOAJUCAAkAAwklBnpqAIIAAAAA.',
Mo='Mochia:BAAALgAECgYJEwABLgAECgkJDwABAAAAAA==.Mognel:BAABLgAECn8uAAIQAAgJ2h4TFQA5AgAQAAgJ2h4TFQA5AgAAAA==.Mogrungar:BAABLgAECn8bAAINAAgJYwoALgBcAQANAAgJYwoALgBcAQAAAA==.Moisten:BAABLgAECn8VAAIVAAkJURxnBQCYAgAVAAkJURxnBQCYAgAAAA==.Monklee:BAAALgAECgEJAQAAAA==.Moomootus:BAABLgAECn8UAAMGAAgJvhEEOACfAQAGAAgJvhEEOACfAQALAAEJrhz6VwBLAAAAAA==.Moxod:BAAALgAECgEJAQAAAA==.Mozzie:BAAALgAECgcJEQAAAA==.',
My='Mysterica:BAAALgADCgYJBgAAAA==.Mysticize:BAABLgAECn8YAAIFAAgJRyBmDQClAgAFAAgJRyBmDQClAgAAAA==.Mystynight:BAAALgAECgYJBwAAAA==.',
['Má']='Mác:BAAALgAECgEJAQAAAA==.',
Na='Naajin:BAABLgAECn8VAAIVAAYJ4g7gLAADAQAVAAYJ4g7gLAADAQAAAA==.Nagini:BAABLgAECn8eAAIQAAgJwgcNUAA6AQAQAAgJwgcNUAA6AQAAAA==.',
Ne='Neiko:BAAALgADCgUJBQAAAA==.Newt:BAAALgADCgUJBQAAAA==.',
Ni='Nicegauges:BAEBLgAECn8rAAMKAAgJYg5sMABgAQAKAAgJYg5sMABgAQAJAAYJ+xObHgBUAQAAAA==.Nietzcha:BAAALgADCgYJDgAAAA==.Nightidan:BAAALgAECgEJAQAAAA==.Nightpetal:BAAALgAECgYJDgAAAA==.Nightstandd:BAAALgADCgcJBwAAAA==.Nigogg:BAAALgADCgIJAgAAAA==.Nioh:BAABLgAECn8bAAIcAAgJAxgNGgDtAQAcAAgJAxgNGgDtAQAAAA==.',
No='Noodles:BAABLgAECn8jAAIcAAgJfwjhVAD8AAAcAAgJfwjhVAD8AAAAAA==.Nordrydsh:BAAALgADCgkJCQABLgAFFAUJDwASAHQWAA==.',
Nu='Nuggs:BAAALgAECggJDwAAAA==.Nuhpie:BAACLgAFFH8PAAMTAAYJPg/oGQDlAAATAAMJ2A7oGQDlAAAEAAMJ1Q98EAClAAAuAAQKfxYAAxMABwmSF/NLAHYBABMABQlgF/NLAHYBAAQAAwkBFNkiANYAAAAA.',
['Nè']='Nèkrosis:BAABLgAECn8cAAIWAAkJlxsUGgAuAgAWAAkJlxsUGgAuAgAAAA==.',
Oj='Ojibwe:BAAALgAECgIJAwAAAA==.',
Ol='Olimdar:BAACLgAFFH8XAAINAAYJ0CP1AABIAgANAAYJ0CP1AABIAgAuAAQKfyEAAw0ACQlsJUsAAM8DAA0ACQlsJUsAAM8DABUAAQmSHaKCAD4AAAAA.',
Om='Omnidraconus:BAAALgAECgkJBwAAAA==.',
Oo='Oopsdidipull:BAAALgADCgYJBwAAAA==.',
Or='Oricelle:BAABLgAECn8fAAIcAAkJdhF8JwCeAQAcAAkJdhF8JwCeAQAAAA==.Oryon:BAEBLgAECn8iAAIYAAgJZBKlAwC9AQAYAAgJZBKlAwC9AQAAAA==.',
Ov='Ovarb:BAABLgAECn8hAAIbAAkJkRjKBQBIAgAbAAkJkRjKBQBIAgAAAA==.',
Ox='Oxiclean:BAAALgAECgEJAQAAAA==.',
Pa='Pachum:BAAALgAECgUJDQAAAA==.Palasexo:BAAALgADCgcJCwAAAA==.Palldude:BAAALgADCgIJAgAAAA==.Paluu:BAAALgAECgEJAQAAAA==.Paragon:BAAALgAECgEJAQAAAA==.Pavo:BAAALgADCgQJBAAAAA==.',
Pe='Pesti:BAACLgAFFH8MAAIiAAMJXhGUDgAGAQAiAAMJXhGUDgAGAQAuAAQKfy4AAiIACAlJHpUGAEcCACIACAlJHpUGAEcCAAAA.Petevoker:BAEALgAECgcJEQAAAA==.',
Ph='Phenoman:BAABLgAECn8vAAINAAgJBCTrAwAJAwANAAgJBCTrAwAJAwAAAA==.',
Pi='Pissedwolf:BAAALgAECgEJAgAAAA==.',
Pl='Plágué:BAAALgAECgYJBwAAAA==.',
Po='Polong:BAABLgAECn8UAAIZAAcJ4g0rJgAQAQAZAAcJ4g0rJgAQAQAAAA==.Ponypants:BAAALgAECgYJEAAAAA==.',
Pr='Preparedman:BAAALgAECgYJBgAAAA==.Preppyplum:BAABLgAECn8rAAMPAAkJnh1uDgCpAgAPAAkJzRxuDgCpAgAmAAUJrRIjDAAQAQAAAA==.Proctologist:BAABLgAECn8aAAIZAAgJlRegDgDeAQAZAAgJlRegDgDeAQAAAA==.Proserpìne:BAABLgAECn8dAAIcAAgJiAgHRQApAQAcAAgJiAgHRQApAQAAAA==.',
Ps='Psychojester:BAABLgAECn8wAAIgAAkJ7h5DAQDUAgAgAAkJ7h5DAQDUAgAAAA==.Psylir:BAAALgAECgQJDAAAAA==.Psythrot:BAAALgADCgUJCgAAAA==.',
Pu='Putt:BAAALgAECgUJEQAAAA==.',
Py='Pydge:BAAALgAECgEJAQAAAA==.',
Qu='Quod:BAAALgAECgQJBAAAAA==.Quoril:BAABLgAECn8oAAMPAAgJoRxUGgBMAgAPAAgJoRxUGgBMAgAmAAEJlyB5GQBMAAABLgAFFAQJDQAIALsUAA==.',
Ra='Raijyu:BAABLgAECn8gAAMKAAkJfxN6IwC8AQAKAAcJ1xR6IwC8AQAJAAUJZxwbFwCZAQAAAA==.Rainfallen:BAAALgADCgQJBAABLgAECggJJwAOAOEVAA==.Rainstormin:BAABLgAECn8nAAIOAAgJ4RWiDgDkAQAOAAgJ4RWiDgDkAQAAAA==.Rakarra:BAABLgAECn8VAAMMAAcJogqUPwAVAQAMAAcJogqUPwAVAQAOAAYJDgcFTQD2AAAAAA==.Rawrstance:BAABLgAECn8gAAMWAAgJ4xoMMAC5AQAWAAcJoRwMMAC5AQAbAAgJ0w1PEgBOAQABLgADCgQJBAABAAAAAA==.Razgrize:BAAALgAECgcJEQAAAA==.',
Re='Redraggon:BAAALgAECgYJBgAAAA==.Reecalled:BAAALgADCgUJBQABLgAECggJGgADAGIaAA==.Reeshan:BAABLgAECn8fAAMGAAkJ1iN/AgA7AwAGAAkJ1iN/AgA7AwALAAIJaxS8TABvAAAAAA==.Reilin:BAAALgAECgQJBQAAAA==.Remsham:BAABLgAECn8WAAIgAAYJlA9JDgAhAQAgAAYJlA9JDgAhAQAAAA==.Renwyck:BAABLgAECn8ZAAIfAAgJciXYAQD2AgAfAAgJciXYAQD2AgAAAA==.Revengemoon:BAACLgAFFH8PAAIGAAQJJBL6GgBBAQAGAAQJJBL6GgBBAQAuAAQKfyIAAgYACQnEGbwpAH4CAAYACQnEGbwpAH4CAAAA.Revitalized:BAAALgADCgQJBAAAAA==.',
Ri='Riakhar:BAAALgAECgEJAgAAAA==.Riddlebox:BAAALgAECgcJCwABLgAECgkJAgABAAAAAA==.Ringberg:BAACLgAFFH8HAAILAAMJaxsJFgD7AAALAAMJaxsJFgD7AAAuAAQKfxYAAwsABwmmHZ8RAAwCAAsABwmmHZ8RAAwCAAYAAwmmFNGVAMMAAAAA.',
Ro='Robane:BAAALgAECgUJDgAAAA==.Robertdowney:BAAALgADCgUJBQAAAA==.Ronburgundy:BAAALgAECgMJBQAAAA==.Rouen:BAABLgAECn8iAAMgAAgJBSIvAwBbAgAgAAgJBSIvAwBbAgANAAYJmx/bEwAWAgAAAA==.',
Ru='Ruckus:BAEALgAECgMJBQAAAA==.Ruder:BAAALgAECgIJAwAAAA==.Rutabaga:BAAALgAECgUJCAAAAA==.',
Rw='Rword:BAAALgADCgUJBgAAAA==.',
Ry='Rykken:BAAALgADCgEJAQAAAA==.Ryotash:BAAALgADCgIJBAAAAA==.Rythas:BAABLgAECn8bAAIKAAkJxBtiEQBzAgAKAAkJxBtiEQBzAgAAAA==.',
Sa='Saintanic:BAAALgADCgQJBAAAAA==.Sandkat:BAABLgAECn8oAAITAAgJWyA1BgCOAgATAAgJWyA1BgCOAgAAAA==.Sanstian:BAAALgAECgUJDQAAAA==.Santamou:BAAALgADCgIJAgAAAA==.Saraelin:BAAALgAFFAEJAgAAAA==.Saray:BAAALgAECgcJDQAAAA==.Saronis:BAAALgADCgQJBAAAAA==.Saurelli:BAAALgADCggJDQABLgAFFAQJBQAkACMMAA==.Sazlok:BAAALgADCgIJAgAAAA==.',
Sc='Scera:BAAALgADCgUJBQAAAA==.Scribbler:BAAALgAECgEJAQAAAA==.',
Se='Sedak:BAAALgAECgYJCwAAAA==.Serahstia:BAABLgAECn8YAAIPAAYJ8BgcVABvAQAPAAYJ8BgcVABvAQAAAA==.Serbustin:BAAALgAECgEJAgAAAA==.',
Sh='Shadowluna:BAAALgADCgkJGQAAAA==.Shaiy:BAAALgAECgMJBQAAAA==.Shiftymage:BAAALgAECgIJAwAAAA==.Shiftymonky:BAAALgAECgEJAQABLgAECgIJAwABAAAAAA==.Shiifthappen:BAAALgAECgEJAQAAAA==.Shinta:BAAALgAECgUJBQAAAA==.Shirtles:BAAALgAECgYJDwAAAA==.Shockblocked:BAAALgAECgEJAQAAAA==.Shèp:BAABLgAECn8ZAAILAAgJFhGaFwDQAQALAAgJFhGaFwDQAQAAAA==.',
Si='Siani:BAAALgADCgYJBgAAAA==.Sidecake:BAABLgAFFH8IAAIVAAUJ/hmMAwCzAQAVAAUJ/hmMAwCzAQABLgAFFAYJCwARAOkTAA==.Siffrin:BAAALgAECgIJAgAAAA==.Silviria:BAAALgADCgEJAQAAAA==.Singars:BAABLgAECn8eAAMQAAcJiRQCNwCJAQAQAAYJehICNwCJAQAYAAQJZhTZGgCfAAABLgAECggJJQADAJQSAA==.Sinkingship:BAAALgADCgcJDwAAAA==.Sipra:BAAALgAECgYJCAAAAA==.Sisterkind:BAAALgADCgIJAgAAAA==.Siypra:BAAALgAECggJDQAAAA==.',
Sk='Skorpix:BAAALgADCgMJAwAAAA==.Skrrt:BAAALgADCgEJAQAAAA==.',
Sl='Sloothe:BAAALgADCgUJBQAAAA==.Sloothi:BAAALgAECgEJAQAAAA==.',
Sn='Snokplaster:BAAALgADCgUJBQAAAA==.',
So='Sotopriest:BAAALgAECgYJBwAAAA==.Sotosan:BAAALgAECggJCAAAAA==.Sotoshaman:BAAALgAECgIJAgAAAA==.Soulhammer:BAAALgAECgcJDAAAAA==.',
Sp='Sprodage:BAABLgAECn8dAAILAAgJ1xIyFwDUAQALAAgJ1xIyFwDUAQAAAA==.',
St='Staggrsaurus:BAAALgAECgIJAwABLgAECgMJBAABAAAAAA==.Stanil:BAAALgAECgYJEwAAAA==.Stayfrosty:BAAALgAECgcJDAAAAA==.Stellare:BAABLgAECn8pAAIdAAgJHRSvCwDHAQAdAAgJHRSvCwDHAQAAAA==.Stevathor:BAAALgAECgEJAQAAAA==.Striest:BAAALgAECgMJAwAAAA==.Styló:BAAALgAECgUJBgAAAA==.',
Su='Suetonius:BAAALgAECgYJCQAAAA==.Sunwalker:BAAALgAECgEJAQAAAA==.Surasaurus:BAABLgAECn8iAAIPAAkJ9hfmGwBDAgAPAAkJ9hfmGwBDAgAAAA==.Suraschi:BAAALgADCgYJBQABLgAECgkJIgAPAPYXAA==.',
Sv='Svelda:BAAALgAECgUJCQAAAA==.',
Sw='Swisscake:BAABLgAECn8iAAIOAAkJVSASAwDgAgAOAAkJVSASAwDgAgAAAA==.',
Sy='Sylain:BAAALgAECgYJEQABLgAECggJDwABAAAAAA==.',
Ta='Tannatax:BAABLgAECn8eAAINAAgJCgW9OQAgAQANAAgJCgW9OQAgAQAAAA==.Taterdotz:BAAALgADCgcJBwAAAA==.',
Te='Teamspidey:BAAALgADCgYJBgABLgAECgMJBAABAAAAAA==.Tekvet:BAAALgAECgkJCQAAAA==.',
Th='Theaemz:BAAALgADCgEJAQAAAA==.Theholygoat:BAAALgADCgEJAQAAAA==.Thewhitness:BAABLgAECn8jAAMPAAkJmRWAIgAeAgAPAAkJmRWAIgAeAgAlAAEJGgGjDAAMAAAAAA==.Thewretch:BAABLgAECn8iAAIQAAgJrSBEDgB4AgAQAAgJrSBEDgB4AgAAAA==.Thumpthump:BAABLgAECn8bAAQhAAgJtxmgIgARAgAhAAYJwx6gIgARAgARAAcJyAzvEgCFAQAIAAEJpw6nwAA1AAAAAA==.Thunderclapn:BAAALgAECgMJCAAAAA==.Thunderkiss:BAEALgAECgMJAwABLgAECgMJBQABAAAAAA==.Thundorf:BAAALgADCgUJCQAAAA==.',
Ti='Tiga:BAAALgAECgMJBAAAAA==.Tindario:BAAALgADCgYJBgAAAA==.Titiera:BAAALgAECgYJDQAAAA==.',
To='Toastnbutta:BAABLgAECn8bAAIMAAcJbBrpLAD7AQAMAAcJbBrpLAD7AQAAAA==.Tolten:BAABLgAECn8eAAIGAAgJ3RmUMQBcAgAGAAgJ3RmUMQBcAgAAAA==.Toothguy:BAAALgAECgQJBgAAAA==.Torvasha:BAAALgADCgEJAQAAAA==.Toscus:BAAALgAECgEJAQAAAA==.',
Tr='Tranquility:BAAALgADCgYJBgAAAA==.Trapfail:BAAALgAECgEJAQAAAA==.Traumatism:BAAALgAECgIJAwAAAA==.Trevor:BAABLgAECn8oAAIkAAgJnhNdBADOAQAkAAgJnhNdBADOAQAAAA==.Trinnitie:BAAALgAECgEJAQAAAA==.',
Ts='Tshark:BAABLgAECn8UAAMaAAcJXxz6CACWAQAaAAYJNBz6CACWAQAjAAUJhhsQDABXAQABLgAECggJJAAbAD4dAA==.',
Tu='Tutatotao:BAAALgADCgMJAwAAAA==.',
Tw='Twotom:BAAALgADCgUJBQAAAA==.',
Ty='Tylaesh:BAAALgAECgYJCQAAAA==.',
Un='Unclepeepers:BAACLgAFFH8PAAISAAQJ4xz2CwBbAQASAAQJ4xz2CwBbAQAuAAQKfyIAAxIACQkDGpkVABgCABIACQkDGpkVABgCAAUAAgmXHzVKAFoAAAAA.Underpowered:BAAALgAECgYJDAAAAA==.Ungodlypain:BAAALgAECgcJEAAAAA==.',
Ur='Urtag:BAABLgAFFH8GAAIhAAUJ4wtsBgBfAQAhAAUJ4wtsBgBfAQAAAA==.',
Va='Vadge:BAAALgADCgcJBwABLgADCgQJBAABAAAAAA==.Valastane:BAAALgADCgUJCAAAAA==.Valhen:BAABLgAECn8xAAMnAAgJfRgKCABhAgAnAAgJfRgKCABhAgAKAAIJogVOZAAwAAAAAA==.Valryn:BAAALgAECgIJAgABLgAECggJMQAnAH0YAA==.Valtar:BAABLgAECn8fAAINAAkJqRrvDQBYAgANAAkJqRrvDQBYAgAAAA==.Vardax:BAAALgADCgcJCQAAAA==.Vaxi:BAABLgAECn8eAAIbAAgJ7R1JDwAXAgAbAAgJ7R1JDwAXAgAAAA==.',
Ve='Veraalyn:BAABLgAECn8dAAMVAAgJHhGRIQBEAQAVAAgJHhGRIQBEAQANAAMJxwicfgCZAAAAAA==.',
Vi='Vicsen:BAABLgAECn8XAAIQAAgJJwVsWwAcAQAQAAgJJwVsWwAcAQAAAA==.Vikaya:BAAALgADCgUJBQAAAA==.Vilevixon:BAABLgAECn8cAAMKAAgJiRihCwAKAgAKAAgJiRihCwAKAgAnAAEJDwRfTgAlAAAAAA==.Vineweaver:BAAALgADCgEJAQAAAA==.Vinvoldo:BAAALgADCgcJCwAAAA==.Vistara:BAAALgAECgIJAgAAAA==.',
Vl='Vladof:BAAALgADCggJCQAAAA==.',
Vo='Voidasuras:BAAALgAECgEJAQAAAA==.',
Wa='Wakabombo:BAAALgAECgcJEAAAAA==.Walla:BAAALgAECgIJAgABLgAECgMJBAABAAAAAA==.Wanlok:BAAALgAECgQJBAAAAA==.Wantoo:BAAALgAECgYJBgAAAA==.Warlokip:BAAALgAECgkJCgAAAA==.Warotar:BAAALgAECgIJAgAAAA==.Warriorlobo:BAABLgAECn8bAAQTAAgJ2h1ECABmAgATAAgJ2h1ECABmAgAEAAYJ7RCXEgArAQAeAAEJ6A6MOAArAAAAAA==.Warvision:BAAALgAFFAEJAQAAAA==.Watchthis:BAAALgAECgMJBAAAAA==.',
Wi='Wildfang:BAABLgAECn8cAAIIAAcJuQy/RgCWAQAIAAcJuQy/RgCWAQAAAA==.Wildside:BAAALgAECgcJCgAAAA==.',
Wu='Wulffgar:BAAALgADCgcJCQAAAA==.',
Xa='Xandronys:BAAALgAECgQJBAAAAA==.Xanne:BAAALgADCgYJBgAAAA==.',
Xe='Xebec:BAAALgAECgEJAQAAAA==.Xenie:BAAALgAECgUJCgAAAA==.',
Xi='Xioran:BAAALgADCgMJAwAAAA==.',
Xy='Xyra:BAAALgADCgcJCAAAAA==.',
Ye='Yeet:BAABLgAECn8UAAIiAAgJExj0IgDhAQAiAAgJExj0IgDhAQAAAA==.',
Yt='Ytterli:BAAALgADCgkJCgAAAA==.',
Za='Zaethas:BAAALgAECgEJBAAAAA==.Zagdakka:BAAALgAECgYJDwAAAA==.Zalandra:BAAALgADCggJEQAAAA==.Zalckar:BAABLgAECn8UAAILAAgJNxIVRQBjAQALAAgJNxIVRQBjAQAAAA==.Zavar:BAAALgAECgUJBwAAAA==.',
Ze='Zeeva:BAAALgAECgYJEAAAAA==.Zendead:BAABLgAECn8cAAIFAAgJhyMbBQCPAgAFAAgJhyMbBQCPAgAAAA==.Zeppeli:BAAALgAECgMJAwAAAA==.',
Zi='Zionspartan:BAABLgAECn8eAAIIAAgJUgzEMwB+AQAIAAgJUgzEMwB+AQAAAA==.',
Zo='Zoology:BAAALgAECgYJDQAAAA==.',
Zu='Zugzugshaman:BAABLgAECn8iAAQNAAkJhRapDgBOAgANAAkJhRapDgBOAgAVAAQJrwN/bgCJAAAgAAEJYQDCIgAdAAAAAA==.',
['Ço']='Çoldædheart:BAAALgADCgkJEgAAAA==.',
['Êï']='Êïñstëïn:BAAALgAECgEJAQAAAA==.',
['Ðø']='Ðøøm:BAAALgADCgEJAQAAAA==.',
['Ñe']='Ñeh:BAABLgAECn8YAAIZAAYJHQ4PKgD6AAAZAAYJHQ4PKgD6AAAAAA==.',
['Ñå']='Ñårçîssîstîç:BAAALgAECgYJBgAAAA==.',
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

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

local lookup = {'Unknown-Unknown','Evoker-Preservation','Evoker-Augmentation','Warrior-Arms','Monk-Windwalker','Paladin-Retribution','Paladin-Protection','Priest-Holy','Priest-Shadow','Paladin-Holy','Shaman-Restoration','Druid-Balance','Warlock-Demonology','Hunter-Survival','Monk-Mistweaver','Warrior-Fury','Evoker-Devastation','Shaman-Elemental','Mage-Frost','DeathKnight-Unholy','Druid-Guardian','Hunter-BeastMastery','Druid-Restoration','DemonHunter-Havoc','DemonHunter-Devourer','DeathKnight-Blood','Warrior-Protection','Monk-Brewmaster','DemonHunter-Vengeance','Shaman-Enhancement','Hunter-Marksmanship','Rogue-Subtlety','Warlock-Destruction','Warlock-Affliction','Mage-Fire','Mage-Arcane','Rogue-Assassination','Priest-Discipline',}
local provider = {region='US',realm="Kael'thas",name='US',type='weekly',zone=46,date='2026-05-01',data={Ad='Adorraa:BAAALgAECgQJBAABLgAECgYJDAABAAAAAA==.Adoryn:BAAALgADCgMJAwAAAA==.Adowyrm:BAACLgAFFH8UAAMCAAYJfRkQBAC2AQACAAUJGRwQBAC2AQADAAEJgAbxKABUAAAuAAQKfyEAAwIACQm1IUgCAFEDAAIACQm1IUgCAFEDAAMABgnLHfccAN8BAAAA.Adriaat:BAAALgADCgMJAwAAAA==.',
Ae='Aeife:BAEALgADCgEJAQABLgAECggJFgAEAB8ZAA==.',
Af='Afflockted:BAAALgADCgQJBAAAAA==.',
Ag='Agicat:BAAALgAECgUJDAABLgAECggJHgAFAFogAA==.',
Ai='Airali:BAABLgAECn8XAAMGAAkJ/BNrZAC4AQAGAAkJ/BNrZAC4AQAHAAMJiQjRNwBiAAAAAA==.Airedale:BAAALgAECgUJDwAAAA==.',
Ak='Akairo:BAABLgAECn8pAAMIAAkJ/yODAgBBAwAIAAkJ/yODAgBBAwAJAAYJSQ4fMgBVAQAAAA==.Akelia:BAAALgAECgEJAgAAAA==.Akonic:BAAALgADCgkJDgAAAA==.',
Al='Alasteria:BAAALgAECgkJAgAAAA==.Alcoaplus:BAAALgADCgkJFgABLgAECggJIgADAFkhAA==.Alexanderxl:BAAALgAECgYJDgABLgAECggJAwABAAAAAA==.Aleybobwa:BAABLgAECn8YAAMKAAkJBRBiKwDaAQAKAAkJBRBiKwDaAQAGAAEJYwiPUgErAAAAAA==.Alody:BAAALgADCgMJAwAAAA==.',
Am='Amethen:BAAALgADCgMJAwAAAA==.Amochi:BAAALgAECggJCwAAAA==.Amulius:BAABLgAECn8nAAIGAAgJLyT+AwDgAgAGAAgJLyT+AwDgAgAAAA==.',
An='Anderdingus:BAAALgADCgUJBQAAAA==.Andormath:BAAALgADCggJDwAAAA==.Andramedae:BAAALgAECgcJEQAAAA==.Angyavocado:BAAALgADCgkJCQAAAA==.Anoki:BAABLgAECn8dAAILAAgJOxgkCgBHAgALAAgJOxgkCgBHAgAAAA==.',
Ao='Aolus:BAACLgAFFH8LAAIMAAMJZRQgDgD+AAAMAAMJZRQgDgD+AAAuAAQKfxgAAgwACQkMHCwTAHsCAAwACQkMHCwTAHsCAAAA.',
Ap='Aphratite:BAAALgADCgMJAwAAAA==.Apoliis:BAAALgADCgEJAQAAAA==.',
Ar='Arbol:BAAALgADCgYJCAABLgAECgIJAwABAAAAAA==.Arcaina:BAAALgAECgYJDgAAAA==.Arez:BAABLgAECn8YAAINAAcJ1hMOJQCcAQANAAcJ1hMOJQCcAQAAAA==.Arilass:BAAALgADCgIJAgAAAA==.Artèmís:BAABLgAECn8fAAIOAAgJoiJBAQDRAgAOAAgJoiJBAQDRAgABLgAECggJJQAPAAwaAA==.',
As='Ashborn:BAAALgADCgEJAQAAAA==.Asladur:BAAALgADCgcJCgAAAA==.',
At='Athenä:BAAALgAECgIJAgAAAA==.',
Az='Azaekho:BAABLgAECn8kAAILAAkJcxR1FQC+AQALAAkJcxR1FQC+AQAAAA==.',
Ba='Baalzak:BAAALgADCgQJBQAAAA==.Backfliphoe:BAAALgAECgcJBwAAAA==.Badoosh:BAABLgAECn8dAAIQAAgJCB2bGACHAgAQAAgJCB2bGACHAgAAAA==.Badragon:BAAALgAECgcJBwAAAA==.Bajablaster:BAABLgAECn8VAAQRAAYJvx+1AgDbAQARAAYJvx+1AgDbAQADAAMJ5BDxTACdAAACAAEJIgvqIQAwAAAAAA==.Baliw:BAAALgADCgUJBAAAAA==.Balto:BAAALgADCgMJAwAAAA==.',
Bb='Bbl:BAACLgAFFH8IAAISAAMJkxBNEwDiAAASAAMJkxBNEwDiAAAuAAQKfyAAAhIACAlBH1QKAPACABIACAlBH1QKAPACAAAA.',
Bc='Bchung:BAACLgAFFH8LAAITAAMJBxU6KwAIAQATAAMJBxU6KwAIAQAuAAQKfx8AAhMACQm5GZc7AIkCABMACQm5GZc7AIkCAAAA.',
Be='Beertits:BAAALgAECgEJAQAAAA==.Belip:BAAALgAFFAEJAQAAAA==.',
Bh='Bhain:BAAALgADCgcJDQABLgAFFAEJAQABAAAAAA==.',
Bi='Bieorne:BAABLgAECn8gAAIUAAgJMh8yCwByAgAUAAgJMh8yCwByAgAAAA==.',
Bl='Blastbane:BAAALgAECgkJEgAAAA==.Bloodwrath:BAAALgADCgQJBAAAAA==.',
Bn='Bnanaketchup:BAAALgADCgQJBAAAAA==.',
Bo='Boo:BAABLgAECn8VAAINAAkJgBwAEAD6AgANAAkJgBwAEAD6AgAAAA==.Boondocks:BAAALgAECgcJEgAAAA==.',
Br='Braca:BAAALgADCgEJAgAAAA==.Braelek:BAAALgADCgEJAQAAAA==.Brewslei:BAAALgADCgYJBgAAAA==.Brewtime:BAAALgAECgYJDwABLgAECggJGgAVAD0aAA==.Brielle:BAABLgAECn8jAAIWAAcJXBgIHAC3AQAWAAcJXBgIHAC3AQAAAA==.Brokenbranch:BAAALgAECgMJAwAAAA==.Brudene:BAABLgAECn8UAAIQAAcJFBGRIQAqAQAQAAcJFBGRIQAqAQAAAA==.Brynhildr:BAAALgADCgYJBgAAAA==.',
Bu='Buddylock:BAABLgAECn8gAAINAAgJagrtNwBNAQANAAgJagrtNwBNAQAAAA==.Bullymaguire:BAACLgAFFH8JAAIFAAUJbRaRBwD9AAAFAAUJbRaRBwD9AAAuAAQKfx0AAgUACAk5I0EFADEDAAUACAk5I0EFADEDAAAA.Burakkuburu:BAABLgAECn8lAAMPAAgJDBqRBgBYAgAPAAgJDBqRBgBYAgAFAAYJ4RXdJwCbAQAAAA==.',
Ca='Caboozles:BAABLgAECn8iAAIWAAgJ0BTjGADMAQAWAAgJ0BTjGADMAQAAAA==.Caliopia:BAABLgAECn8eAAISAAgJqxQiEQCZAQASAAgJqxQiEQCZAQAAAA==.Captnhuntcat:BAAALgAECgUJBgAAAA==.Carcosa:BAAALgAECgEJAQAAAA==.Cardone:BAAALgAECgEJAQAAAA==.',
Ce='Ceromaar:BAABLgAECn8hAAIQAAkJ5hB6CQASAgAQAAkJ5hB6CQASAgAAAA==.Ceti:BAAALgAECgcJDAAAAA==.',
Ch='Chaoticdh:BAAALgADCgYJBgAAAA==.Checkurback:BAAALgAECggJEwAAAA==.Chemistree:BAABLgAECn8YAAIXAAcJ8BA+IgBvAQAXAAcJ8BA+IgBvAQAAAA==.Chillout:BAABLgAECn8WAAITAAcJNQ7IRABgAQATAAcJNQ7IRABgAQAAAA==.Chillums:BAABLgAECn8cAAINAAcJ4iOwDQA/AgANAAcJ4iOwDQA/AgAAAA==.Chipcle:BAAALgADCgcJCwAAAA==.Chocoflan:BAAALgADCgIJAgAAAA==.Chöpper:BAAALgADCgEJAgAAAA==.',
Cl='Clumsy:BAAALgADCgUJBQABLgADCgQJBAABAAAAAA==.',
Co='Cokarott:BAAALgAECgUJBgAAAA==.Cops:BAABLgAECn8XAAIKAAgJKg1THgBWAQAKAAgJKg1THgBWAQAAAA==.Coral:BAAALgADCgkJGQAAAA==.',
Cr='Criticål:BAAALgADCgIJAgAAAA==.Crusherk:BAAALgAECgcJBQAAAA==.',
Da='Dabercoo:BAAALgADCgQJBAAAAA==.Daeleiel:BAAALgADCgQJBAAAAA==.Darkenergy:BAABLgAECn8SAAMYAAcJqiIYEwA+AgAYAAYJxSQYEwA+AgAZAAYJ+hjsGgCTAQAAAA==.Darthtotem:BAAALgAECgYJEQABLgAECgcJCQABAAAAAA==.Darà:BAAALgADCgcJBwABLgAECgYJDAABAAAAAA==.Dashyll:BAAALgADCgkJFQAAAA==.Davyfknjones:BAAALgAECgUJBgAAAA==.',
De='Deadlegslul:BAAALgAECgYJCwAAAA==.Deadlegsmd:BAAALgADCgcJCwAAAA==.Deadrat:BAAALgAECgMJAwAAAA==.Deadzepplin:BAAALgAECgEJAgAAAA==.Deathmono:BAAALgAECgYJCQAAAA==.Deathshark:BAABLgAECn8gAAIaAAgJEBu9CgBsAgAaAAgJEBu9CgBsAgAAAA==.Dellphine:BAAALgAECgEJAQAAAA==.Demacus:BAAALgAECgcJCwAAAA==.Demeter:BAABLgAECn8eAAIHAAgJghAjDAA/AQAHAAgJghAjDAA/AQAAAA==.Demonhunters:BAAALgADCgcJDAAAAA==.Demontb:BAAALgAECgkJAQAAAA==.Denarien:BAAALgAECgkJDAAAAA==.Derpygos:BAAALgADCgcJBwABLgAECggJGgAVAD0aAA==.Devouress:BAAALgAECggJDgABLgAECggJGAAFAEUgAA==.',
Di='Diddlesz:BAAALgAECggJAwAAAA==.Dillkiller:BAABLgAECn8XAAIbAAcJGQn8IQAuAQAbAAcJGQn8IQAuAQAAAA==.Dirgen:BAAALgAECgYJDAAAAA==.Disspair:BAAALgADCgEJAQAAAA==.',
Do='Dobbyscumsok:BAAALgAECgYJEQAAAA==.Dookiee:BAAALgAECgYJEQAAAA==.Dorksparrow:BAAALgAECgQJBwABLgAECgkJHgAcAMoOAA==.Doug:BAAALgADCgcJDQAAAA==.Doxom:BAAALgADCgEJAQAAAA==.',
Dr='Dracalled:BAAALgAECgcJEgAAAA==.Draggnar:BAAALgAECgMJAwAAAA==.Dragönlöl:BAAALgAECgYJCAAAAA==.Dramme:BAAALgAECgIJAgAAAA==.Drat:BAAALgAECgcJBwAAAA==.Druidvishnu:BAAALgAECgYJCQABLgAFFAQJBQASAGoUAA==.',
Du='Dumplingsxo:BAABLgAECn8fAAMMAAkJnBg5GQA9AgAMAAgJsBk5GQA9AgAXAAcJaxWaPQCtAQAAAA==.Dusktodawn:BAAALgAECgUJDgAAAA==.',
Dy='Dyharmis:BAABLgAECn8eAAIdAAgJ6SPOAACzAgAdAAgJ6SPOAACzAgAAAA==.',
Eb='Ebojager:BAABLgAECn8fAAIZAAgJRRSvFQC7AQAZAAgJRRSvFQC7AQAAAA==.',
Ei='Eibon:BAACLgAFFH8RAAIUAAUJfRhkBQC1AQAUAAUJfRhkBQC1AQAuAAQKfx4AAhQACQnNIakUAAADABQACQnNIakUAAADAAAA.',
El='Elliiria:BAAALgADCggJDgAAAA==.Eloïse:BAAALgADCgYJCQAAAA==.Elthion:BAAALgADCgYJCgAAAA==.Elvispriesty:BAAALgAECgUJDQAAAA==.Elwarrioro:BAAALgAECgYJDQAAAA==.',
Em='Emmune:BAABLgAECn8cAAIeAAgJRQ4OBgCuAQAeAAgJRQ4OBgCuAQAAAA==.',
En='Enobia:BAAALgAECgYJCwAAAA==.Entrapment:BAAALgADCgYJBgABLgADCgQJBAABAAAAAA==.Envie:BAAALgAECgQJBQAAAA==.',
Er='Eriaeda:BAAALgAECgQJCAAAAA==.',
Es='Eskath:BAAALgAECgcJEAABLgAECggJGgAVAD0aAA==.Essential:BAABLgAECn8UAAIGAAgJvQtnkABbAQAGAAgJvQtnkABbAQAAAA==.',
Et='Eternalpain:BAAALgADCgEJAQAAAA==.',
Ev='Evdoggy:BAABLgAECn8WAAIFAAYJhRK9FwArAQAFAAYJhRK9FwArAQAAAA==.Evilkills:BAAALgAECgMJAwAAAA==.',
Ex='Exterminate:BAAALgAECgIJAgAAAA==.',
Fe='Feekknight:BAAALgADCgQJBAAAAA==.Fellon:BAAALgADCgEJAQAAAA==.Femmur:BAAALgADCgUJBwAAAA==.Fenrin:BAAALgAECgMJAgAAAA==.Fenrîr:BAAALgADCgYJBgABLgAECgYJFwAcABwOAA==.Ferrara:BAACLgAFFH8VAAQfAAYJiyDmCwBdAQAfAAYJAh3mCwBdAQAWAAEJzh+vHwBiAAAOAAEJYQBnFgA1AAAuAAQKfyAABB8ACQnRIxcGADkDAB8ACQmLIxcGADkDABYAAQn1I6+wAGIAAA4AAQk6HvwrAEYAAAAA.',
Fi='Finesse:BAAALgADCggJFQAAAA==.Firebåll:BAAALgAECgMJBQAAAA==.Fishbait:BAAALgADCgIJAgABLgAECggJHgAMAMcfAA==.Fisterjob:BAAALgAECgEJAQAAAA==.',
Fl='Flandri:BAABLgAFFH8KAAIIAAUJaA8YAwCGAQAIAAUJaA8YAwCGAQAAAA==.Flandrie:BAAALgADCgMJAwAAAA==.Flexicute:BAAALgADCgcJDAAAAA==.',
Fo='Foxlock:BAAALgADCgYJBgAAAA==.',
Fr='Friedá:BAAALgAECgEJAQABLgAECgYJCwABAAAAAA==.Frostednip:BAABLgAECn8XAAIUAAkJsiBhNABlAgAUAAkJsiBhNABlAgAAAA==.',
Ga='Gabiru:BAABLgAFFH8HAAQDAAMJ8QQ7GwDMAAADAAMJ8QQ7GwDMAAACAAMJvAf+DwC/AAARAAEJlwEhDABCAAAAAA==.Gadreeste:BAAALgADCgUJBQAAAA==.Galnarn:BAACLgAFFH8XAAIcAAYJfyHzAAD+AQAcAAYJfyHzAAD+AQAuAAQKfyEAAhwACQliHfsNALQCABwACQliHfsNALQCAAAA.Gambagood:BAAALgAECgYJCgAAAA==.Garious:BAAALgAECgcJBwABLgAFFAQJCQAUAI0gAA==.Garlicbae:BAAALgAECgEJAQAAAA==.Garwulf:BAAALgAECgYJDAAAAA==.',
Ge='Gefaustet:BAAALgAECgcJEgAAAA==.Gelroos:BAAALgADCgEJAQAAAA==.Geryll:BAAALgADCgIJAgAAAA==.',
Gl='Glimpse:BAAALgADCgEJAQAAAA==.Glognar:BAAALgADCgQJBAAAAA==.Glorp:BAAALgAECgEJAQAAAA==.',
Go='Goatcheesè:BAAALgAECgIJAgAAAA==.Goatess:BAAALgADCgYJCQAAAA==.Goopa:BAAALgAECgYJCgAAAA==.Goopert:BAAALgADCgYJDAAAAA==.Goopy:BAAALgAECgcJDwAAAA==.Gorbachev:BAAALgADCgYJEQAAAA==.Gorehowl:BAAALgAECgEJAgAAAA==.Goro:BAAALgADCgQJBAAAAA==.',
Gr='Graybrew:BAAALgAECgIJAgAAAA==.Grayes:BAABLgAECn8XAAIVAAYJ8AUSFQB0AAAVAAYJ8AUSFQB0AAAAAA==.Grayson:BAAALgADCgUJBQAAAA==.Grorkster:BAAALgADCgUJBQAAAQ==.Grute:BAAALgAECgUJBQAAAA==.',
Gu='Gumption:BAAALgAECgEJAQAAAA==.',
Ha='Hallowshade:BAABLgAECn8XAAIgAAcJERksDACmAQAgAAcJERksDACmAQAAAA==.Hardran:BAAALgAECgQJCAAAAA==.Harington:BAAALgAECgkJAgAAAA==.Harmôny:BAAALgADCggJFAAAAA==.Hatreddyes:BAAALgADCgUJBQAAAA==.Hatredyes:BAAALgAECgUJBgAAAA==.',
He='Helare:BAAALgAECgUJBwAAAA==.Henrymorgan:BAAALgAECgkJBgAAAA==.Hexenbane:BAAALgAECgYJEAAAAA==.',
Hi='Hinatsuru:BAAALgAECgEJAQAAAA==.',
Ho='Holyzap:BAAALgADCgIJAgABLgAECgMJBQABAAAAAA==.Hoyt:BAAALgADCgcJCwAAAA==.',
Hu='Hugme:BAAALgAECgkJAgAAAA==.Hukhan:BAAALgAECgEJAQAAAA==.Hunthard:BAAALgAECgEJAQAAAA==.Huunno:BAAALgAECgIJAwABLgAECgMJBAABAAAAAA==.',
Hy='Hyasin:BAAALgADCgUJDQAAAA==.',
Ic='Ichom:BAAALgADCgMJAwABLgAECgYJEwABAAAAAA==.',
Id='Idalia:BAAALgADCgQJBAABLgADCgYJDwABAAAAAA==.',
If='Iforgotnaaru:BAAALgAECgcJCgAAAA==.',
Il='Illiae:BAABLgAECn8WAAISAAcJrRwxDADYAQASAAcJrRwxDADYAQAAAA==.',
Im='Impactr:BAAALgADCgMJAwAAAA==.Implanttorq:BAAALgAECgEJAQAAAA==.Imtheteapot:BAABLgAECn8jAAIQAAgJrQ3zEACyAQAQAAgJrQ3zEACyAQAAAA==.',
In='Innex:BAABLgAECn8cAAIUAAgJ/x1FGAD5AQAUAAgJ/x1FGAD5AQAAAA==.Innexrogue:BAAALgAECgEJAgABLgAECggJHAAUAP8dAA==.Innexvoker:BAAALgAECgUJBQABLgAECggJHAAUAP8dAA==.Inpesca:BAAALgADCgUJBQABLgAECggJIgADAFkhAA==.Insanityx:BAAALgAECggJCAAAAA==.',
Io='Ionic:BAAALgAECgIJAgAAAA==.',
Ir='Iridescent:BAAALgAECgIJAgAAAA==.Ironpalm:BAAALgAECgcJBwAAAA==.',
Is='Issidora:BAAALgAECgUJCQAAAA==.',
It='Ithronel:BAAALgADCgUJBQAAAA==.Itzmuffin:BAABLgAECn8hAAILAAgJ8BHnNgCnAQALAAgJ8BHnNgCnAQAAAA==.Itzpie:BAABLgAECn8lAAITAAgJZBbkIwDZAQATAAgJZBbkIwDZAQAAAA==.',
Ja='Jagtat:BAAALgAECgYJCgAAAA==.Jakeakuma:BAABLgAECn8UAAINAAkJBAwaXwCsAQANAAkJBAwaXwCsAQAAAA==.Jascob:BAAALgAECgUJEQAAAA==.',
Je='Jessa:BAAALgADCgMJAwAAAA==.',
Jh='Jhivago:BAAALgADCgEJAQAAAA==.',
Jo='Johnivxx:BAAALgADCgcJBAAAAA==.Johnnybravo:BAAALgAECgIJBAAAAA==.',
Ju='Judokeg:BAABLgAECn8gAAIcAAgJTxy0BQBJAgAcAAgJTxy0BQBJAgAAAA==.Juglass:BAAALgADCgEJAQAAAA==.Jujutsu:BAABLgAECn8eAAIFAAgJWiBZCAD0AgAFAAgJWiBZCAD0AgAAAA==.Junfan:BAAALgAECgcJAwAAAA==.',
Ka='Kaashaa:BAABLgAECn8kAAIWAAgJyBoXEAAWAgAWAAgJyBoXEAAWAgAAAA==.Kaelsgf:BAAALgADCgIJAgAAAA==.Kahllan:BAAALgAECgYJDAAAAA==.Kahnigitt:BAAALgAECgIJAwAAAA==.Kataltoholic:BAAALgAECgYJDgAAAA==.Katrath:BAAALgADCgIJAgAAAA==.Kayser:BAAALgAECgIJAgAAAA==.Kaýhas:BAABLgAECn8OAAIZAAYJCxp2UAC0AQAZAAYJCxp2UAC0AQAAAA==.',
Ke='Kelinïsha:BAABLgAECn8hAAITAAgJZgk6SQBTAQATAAgJZgk6SQBTAQAAAA==.Kelynna:BAABLgAECn8VAAIIAAYJtRwTIADhAQAIAAYJtRwTIADhAQAAAA==.Kevinarnold:BAAALgADCgEJAQAAAA==.Kevinbacon:BAAALgAECgEJAgAAAA==.',
Kh='Khelldyr:BAAALgAECggJCAAAAA==.Khellrond:BAAALgAECggJCQAAAA==.Khuntress:BAAALgADCgUJBQAAAA==.',
Ki='Kiiras:BAABLgAECn8fAAITAAgJEgo3QwBlAQATAAgJEgo3QwBlAQAAAA==.Kimbodh:BAACLgAFFH8JAAIZAAQJth8dBwCDAQAZAAQJth8dBwCDAQAuAAQKfx8AAhkACAk2I4kHAGICABkACAk2I4kHAGICAAEuAAEKAwkBAAEAAAAA.Kinvictusk:BAAALgAECgEJAQAAAA==.Kirathein:BAABLgAECn8aAAIZAAgJfw6xIABuAQAZAAgJfw6xIABuAQABLgADCgUJBQABAAAAAA==.',
Kl='Klefthoof:BAABLgAECn8YAAILAAYJxQ8TKAAuAQALAAYJxQ8TKAAuAQABLgAECgcJCwABAAAAAA==.',
Ko='Kodey:BAAALgAECgcJDwABLgAECggJFwAhACgSAA==.Kordy:BAAALgAECgkJAQAAAA==.',
Kr='Kraniah:BAAALgAECgIJBQAAAA==.Krimboz:BAABLgAECn8VAAINAAYJThSfRgAcAQANAAYJThSfRgAcAQAAAA==.Krimdk:BAAALgADCgcJBwAAAA==.Krystallight:BAABLgAECn8aAAIOAAcJLhK4DACTAQAOAAcJLhK4DACTAQAAAA==.Krìsta:BAABLgAECn8WAAMiAAYJWAxXDQBgAQAiAAYJWAxXDQBgAQANAAYJ4AOuaAC9AAAAAA==.',
Ku='Kuanshuwo:BAABLgAECn8VAAMJAAgJ6QlFEgB0AQAJAAgJ6QlFEgB0AQAIAAYJfQZATgD/AAAAAA==.Kullomaa:BAAALgAECgcJBQAAAA==.',
La='Lanwulf:BAAALgADCggJDQAAAA==.Lastgasp:BAAALgADCgcJBwAAAA==.Lauriela:BAAALgAECgQJCwAAAA==.',
Le='Lechuzón:BAAALgADCgMJAwAAAA==.Ledrõllan:BAABLgAECn8YAAIJAAkJbB28FwAmAgAJAAkJbB28FwAmAgAAAA==.Legaloas:BAABLgAECn8YAAMfAAcJUxhOCgAsAQAWAAYJNxmCQACtAQAfAAUJVhBOCgAsAQAAAA==.Leinhart:BAAALgAECgUJCQAAAA==.Lenah:BAAALgAECgMJAwAAAA==.Leonarde:BAACLgAFFH8LAAMWAAMJlBZYGAAFAQAWAAMJlxRYGAAFAQAfAAMJ2Q++FQDuAAAuAAQKfx4ABB8ACQkBFiAhABoCAB8ACAkSFyAhABoCABYAAQmLDup/AFIAAA4AAQlWAKozAA0AAAAA.Levitt:BAAALgAECgQJCgAAAA==.',
Li='Lilsia:BAAALgADCgEJAQAAAA==.Lilwok:BAABLgAECn8jAAIFAAcJpBWpEAB0AQAFAAcJpBWpEAB0AQAAAA==.Lintelworth:BAAALgADCgYJFAAAAA==.Liradia:BAAALgAECgIJAwAAAA==.Liver:BAAALgAECgEJAQAAAA==.',
Ll='Llevanya:BAABLgAECn8dAAIGAAgJLgdJQQBGAQAGAAgJLgdJQQBGAQAAAA==.Llinaigh:BAAALgAECgYJDQAAAA==.',
Lo='Loanna:BAAALgADCgYJDwAAAA==.Lobao:BAAALgAECgEJAQABLgAECgcJEQABAAAAAA==.Lomu:BAABLgAECn8aAAQVAAgJPRorBwB8AQAVAAgJPRorBwB8AQAXAAEJ7Q5CzwAvAAAMAAEJlATgTQAkAAAAAA==.Loredalso:BAAALgADCggJFgAAAA==.Lorenitha:BAAALgAECgEJAQAAAA==.',
Lu='Lunastraz:BAAALgADCgkJDwAAAA==.',
Ma='Magerproblem:BAAALgAFFAEJAQABLgAECgkJFQANAIAcAA==.Magicdreams:BAABLgAECn8gAAIMAAgJtQaPHAAXAQAMAAgJtQaPHAAXAQAAAA==.Malificent:BAAALgADCgMJBQAAAA==.Malmorte:BAABLgAECn8UAAIUAAYJ5xMAowA6AQAUAAYJ5xMAowA6AQAAAA==.Malorane:BAABLgAECn8nAAIaAAkJFxthAwAdAgAaAAkJFxthAwAdAgAAAA==.Mana:BAAALgADCgUJBQAAAA==.Marcasite:BAAALgADCgIJAQAAAA==.Marihuano:BAAALgADCgYJCAABLgADCgcJCwABAAAAAA==.Marisi:BAAALgADCggJCAAAAA==.Mastir:BAAALgAECgUJCAAAAA==.Masumune:BAAALgAECgQJBAAAAA==.Matamosca:BAABLgAECn8gAAIgAAkJwx3mAQC1AgAgAAkJwx3mAQC1AgAAAA==.Materiaga:BAABLgAECn8iAAQDAAgJChFnDgClAQADAAgJtRBnDgClAQACAAYJFQtaKQAoAQARAAMJjg/iCgC8AAAAAA==.Mature:BAAALgADCgIJAgAAAA==.Maz:BAABLgAECn8eAAIGAAgJUyF4CACUAgAGAAgJUyF4CACUAgAAAA==.',
Mc='Mcflury:BAABLgAECn8oAAMeAAkJGxU2BgCWAgAeAAkJGxU2BgCWAgASAAgJtg9CFwBaAQAAAA==.',
Me='Meerchi:BAABLgAECn8eAAMTAAgJrBH7JwDFAQATAAgJrBH7JwDFAQAjAAQJWAPACgCVAAAAAA==.Meetyomaker:BAAALgAECgUJCAAAAA==.Meowkai:BAAALgAECgYJBgABLgAECggJJQAPAAwaAA==.Mesthos:BAAALgAECgcJDAABLgAECggJGAAdAF8lAA==.Mestyphe:BAAALgAECgMJAwAAAA==.Metalmoth:BAAALgADCgEJAQAAAA==.Metformin:BAABLgAECn8lAAIDAAgJlBKMGgD2AQADAAgJlBKMGgD2AQAAAA==.',
Mi='Mickieta:BAAALgAECgcJEgAAAA==.Microsurge:BAABLgAECn8cAAITAAgJIB3WJQDbAgATAAgJIB3WJQDbAgAAAA==.Mikalau:BAAALgAECgYJDQAAAA==.Mikaluu:BAAALgAECgQJBAAAAA==.Miqkail:BAAALgAECgYJCAABLgAECggJGAAdAF8lAA==.Missteek:BAAALgAECgEJAQABLgAECgYJFQARAL8fAA==.Mistrunner:BAAALgADCgUJBgAAAA==.Mistspell:BAACLgAFFH8LAAIJAAMJghIJCwAEAQAJAAMJghIJCwAEAQAuAAQKfx8AAwkACQkXG98OAJUCAAkACQkXG98OAJUCAAgAAwklBm9qAIIAAAAA.',
Mo='Mochia:BAAALgAECgYJEwAAAA==.Mognel:BAABLgAECn8mAAINAAgJcBwJEQAeAgANAAgJcBwJEQAeAgAAAA==.Mogrungar:BAAALgAECgcJEwAAAA==.Moisten:BAAALgAECggJEgAAAA==.Monklee:BAAALgAECgEJAQAAAA==.Moomootus:BAAALgAECgYJEQAAAA==.Moxod:BAAALgAECgEJAQAAAA==.Mozzie:BAAALgAECgcJEQAAAA==.',
My='Mysterica:BAAALgADCgYJBgAAAA==.Mysticize:BAABLgAECn8YAAIFAAgJRSBmDQClAgAFAAgJRSBmDQClAgAAAA==.Mystynight:BAAALgAECgYJBwAAAA==.',
['Má']='Mác:BAAALgAECgEJAQAAAA==.',
Na='Naajin:BAAALgAECgYJDwAAAA==.Nagini:BAABLgAECn8ZAAINAAgJwgcjOwBCAQANAAgJwgcjOwBCAQAAAA==.',
Ne='Neiko:BAAALgADCgUJBQAAAA==.Newt:BAAALgADCgUJBQAAAA==.',
Ni='Nicegauges:BAEBLgAECn8fAAMJAAcJmQ9tMABgAQAJAAcJmQ9tMABgAQAIAAUJfRDyUQDvAAABLgAECggJGwATAC0NAA==.Nietzcha:BAAALgADCgYJDgAAAA==.Nightidan:BAAALgAECgEJAQAAAA==.Nightpetal:BAAALgAECgUJCAAAAA==.Nightstandd:BAAALgADCgcJBwAAAA==.Nigogg:BAAALgADCgIJAgAAAA==.Nioh:BAAALgAECggJEwAAAA==.',
No='Noodles:BAABLgAECn8bAAIZAAYJowkzjAAKAQAZAAYJowkzjAAKAQAAAA==.Nordrydsh:BAAALgADCgkJCQABLgAFFAQJCgAPAJ4WAA==.',
Nu='Nuggs:BAAALgAECggJDwAAAA==.Nuhpie:BAACLgAFFH8OAAMQAAYJAg+7EgDyAAAQAAMJYQ67EgDyAAAEAAMJ9A+bCgCsAAAuAAQKfxYAAxAABwmOF/NLAHYBABAABQlZF/NLAHYBAAQAAwkCFNkiANYAAAAA.',
['Nè']='Nèkrosis:BAABLgAECn8aAAIUAAgJvBxTGQDwAQAUAAgJvBxTGQDwAQAAAA==.',
Oj='Ojibwe:BAAALgAECgIJAgAAAA==.',
Ol='Olimdar:BAACLgAFFH8WAAILAAYJ2CNOAABUAgALAAYJ2CNOAABUAgAuAAQKfyEAAwsACQlsJUsAAM8DAAsACQlsJUsAAM8DABIAAQmSHaWCAD4AAAAA.',
Om='Omnidraconus:BAAALgAECgkJBAAAAA==.',
Oo='Oopsdidipull:BAAALgADCgYJBwAAAA==.',
Or='Oricelle:BAABLgAECn8bAAIZAAgJAhGsIgBjAQAZAAgJAhGsIgBjAQAAAA==.Oryon:BAEBLgAECn8aAAIiAAgJkQycAwB7AQAiAAgJkQycAwB7AQAAAA==.',
Ov='Ovarb:BAABLgAECn8fAAIaAAgJyBk9BgDHAQAaAAgJyBk9BgDHAQAAAA==.',
Ox='Oxiclean:BAAALgAECgEJAQAAAA==.',
Pa='Pachum:BAAALgAECgUJDQAAAA==.Palasexo:BAAALgADCgcJCwAAAA==.Paluu:BAAALgAECgEJAQAAAA==.Paragon:BAAALgAECgEJAQAAAA==.Pavo:BAAALgADCgQJBAAAAA==.',
Pe='Pesti:BAACLgAFFH8JAAIgAAMJYw6RDgAGAQAgAAMJYw6RDgAGAQAuAAQKfysAAiAABwkAIn8FACkCACAABwkAIn8FACkCAAAA.Petevoker:BAEALgAECgcJEQAAAA==.',
Ph='Phenoman:BAABLgAECn8nAAILAAgJUSInCgDXAgALAAgJUSInCgDXAgAAAA==.',
Pl='Plágué:BAAALgAECgYJBwAAAA==.',
Po='Polong:BAAALgAECgYJEgAAAA==.Ponypants:BAAALgAECgYJEAAAAA==.',
Pr='Preparedman:BAAALgAECgYJBgAAAA==.Preppyplum:BAABLgAECn8iAAMTAAgJZx3DEgBFAgATAAgJcxzDEgBFAgAkAAUJrRIkDAAQAQAAAA==.Proctologist:BAABLgAECn8YAAIcAAgJlBfMCQDvAQAcAAgJlBfMCQDvAQAAAA==.Proserpìne:BAABLgAECn8VAAIZAAYJLQm+QwDaAAAZAAYJLQm+QwDaAAAAAA==.',
Ps='Psychojester:BAABLgAECn8nAAIeAAgJwR18AgBFAgAeAAgJwR18AgBFAgAAAA==.Psylir:BAAALgAECgQJDAAAAA==.Psythrot:BAAALgADCgUJCgAAAA==.',
Pu='Putt:BAAALgAECgUJDQAAAA==.',
Py='Pydge:BAAALgADCgEJAgAAAA==.',
Qu='Quod:BAAALgAECgQJBAAAAA==.Quoril:BAABLgAECn8gAAMTAAgJ0BsJFQAzAgATAAgJ0BsJFQAzAgAkAAEJlyB5GQBMAAABLgAFFAQJDAAWAFYPAA==.',
Ra='Raijyu:BAABLgAECn8cAAMJAAgJvRR7IwC8AQAJAAYJdBd7IwC8AQAIAAQJohvrGABCAQAAAA==.Rainfallen:BAAALgADCgQJBAABLgAECggJHwAMAL4QAA==.Rainstormin:BAABLgAECn8fAAIMAAgJvhDqEQB9AQAMAAgJvhDqEQB9AQAAAA==.Rakarra:BAAALgAECgYJDgAAAA==.Rawrstance:BAABLgAECn8YAAIUAAcJnxymHwDJAQAUAAcJnxymHwDJAQABLgADCgQJBAABAAAAAA==.Razgrize:BAAALgAECgYJDAAAAA==.',
Re='Reecalled:BAAALgADCgUJBQABLgAECgcJEgABAAAAAA==.Reeshan:BAABLgAECn8cAAMGAAgJ2SSXAwDpAgAGAAgJ2SSXAwDpAgAKAAIJZRRjPAB6AAAAAA==.Reilin:BAAALgAECgQJBQAAAA==.Remsham:BAAALgAECgYJEAAAAA==.Renwyck:BAABLgAECn8YAAIdAAgJXyXYAQD2AgAdAAgJXyXYAQD2AgAAAA==.Revengemoon:BAACLgAFFH8LAAIGAAMJtA9VFwDzAAAGAAMJtA9VFwDzAAAuAAQKfx8AAgYACQnDGb0pAH4CAAYACQnDGb0pAH4CAAAA.Revitalized:BAAALgADCgQJBAAAAA==.',
Ri='Riakhar:BAAALgAECgEJAgAAAA==.Riddlebox:BAAALgAECgcJCwABLgAECgkJAgABAAAAAA==.Ringberg:BAABLgAECn8UAAMKAAcJ6xzcEADaAQAKAAcJ6xzcEADaAQAGAAMJohQxcQDMAAABLgAECgkJFQANAIAcAA==.',
Ro='Robane:BAAALgAECgUJDQAAAA==.Robertdowney:BAAALgADCgUJBQAAAA==.Ronburgundy:BAAALgAECgMJBAAAAA==.Rouen:BAABLgAECn8gAAMeAAgJ7iAgAgBdAgAeAAgJ7iAgAgBdAgALAAYJmx+QDAAhAgAAAA==.',
Ru='Ruckus:BAEALgAECgIJAwAAAA==.Ruder:BAAALgAECgEJAQAAAA==.Ruhe:BAAALgAECgEJAQAAAA==.Rutabaga:BAAALgAECgUJCAAAAA==.',
Rw='Rword:BAAALgADCgUJBgAAAA==.',
Ry='Rykken:BAAALgADCgEJAQAAAA==.Ryotash:BAAALgADCgIJBAAAAA==.Rythas:BAABLgAECn8bAAIJAAkJvRtkEQBzAgAJAAkJvRtkEQBzAgAAAA==.',
Sa='Saintanic:BAAALgADCgQJBAAAAA==.Sandkat:BAABLgAECn8gAAIQAAgJOxsxBgBRAgAQAAgJOxsxBgBRAgAAAA==.Sanstian:BAAALgAECgQJCAAAAA==.Santamou:BAAALgADCgIJAgAAAA==.Saraelin:BAAALgAFFAEJAQAAAA==.Saray:BAAALgAECgcJDQAAAA==.Saronis:BAAALgADCgQJBAAAAA==.Saurelli:BAAALgADCggJDQABLgAFFAQJBQAlACMMAA==.Sazlok:BAAALgADCgIJAgAAAA==.',
Sc='Scera:BAAALgADCgUJBQAAAA==.Scribbler:BAAALgAECgEJAQAAAA==.',
Se='Sedak:BAAALgAECgUJBwAAAA==.Serahstia:BAABLgAECn8XAAITAAYJ8Rh/PQB1AQATAAYJ8Rh/PQB1AQAAAA==.Serbustin:BAAALgAECgEJAgAAAA==.',
Sh='Shadowluna:BAAALgADCgkJGQAAAA==.Shaiy:BAAALgAECgMJBQAAAA==.Shiftymage:BAAALgAECgIJAwAAAA==.Shiftymonky:BAAALgAECgEJAQABLgAECgIJAwABAAAAAA==.Shiifthappen:BAAALgAECgEJAQAAAA==.Shinta:BAAALgADCggJEgAAAA==.Shirtles:BAAALgAECgYJCQAAAA==.Shockblocked:BAAALgAECgEJAQAAAA==.Shèp:BAABLgAECn8WAAIKAAgJUg8oEwC/AQAKAAgJUg8oEwC/AQAAAA==.',
Si='Siani:BAAALgADCgYJBgAAAA==.Sidecake:BAABLgAFFH8IAAISAAUJ/hmKAwCzAQASAAUJ/hmKAwCzAQAAAA==.Siffrin:BAAALgAECgIJAgAAAA==.Silviria:BAAALgADCgEJAQAAAA==.Singars:BAABLgAECn8XAAMNAAcJgQ9KPgA3AQANAAUJIhBKPgA3AQAiAAMJBAnYGgCfAAABLgAECggJJQADAJQSAA==.Sinkingship:BAAALgADCgcJDwAAAA==.Sipra:BAAALgAECgYJCAAAAA==.Sisterkind:BAAALgADCgIJAgAAAA==.Siypra:BAAALgAECgcJCgAAAA==.',
Sk='Skorpix:BAAALgADCgMJAwAAAA==.Skrrt:BAAALgADCgEJAQAAAA==.',
Sl='Sloothi:BAAALgAECgEJAQAAAA==.',
Sn='Snokplaster:BAAALgADCgUJBQAAAA==.',
So='Sotopriest:BAAALgAECgYJBwAAAA==.Sotosan:BAAALgAECggJCAAAAA==.Sotoshaman:BAAALgAECgIJAgAAAA==.Soulhammer:BAAALgAECgcJDAAAAA==.',
Sp='Sprodage:BAABLgAECn8VAAIKAAYJohX0HABiAQAKAAYJohX0HABiAQAAAA==.',
St='Stanil:BAAALgAECgYJDAAAAA==.Stayfrosty:BAAALgAECgUJCQAAAA==.Stellare:BAABLgAECn8hAAIYAAgJgg/RCwB/AQAYAAgJgg/RCwB/AQAAAA==.Stevathor:BAAALgAECgEJAQAAAA==.Styló:BAAALgAECgIJAgAAAA==.',
Su='Suetonius:BAAALgAECgIJBAAAAA==.Surasaurus:BAABLgAECn8eAAITAAgJQBi1HwDuAQATAAgJQBi1HwDuAQAAAA==.Suraschi:BAAALgADCgYJBQABLgAECggJHgATAEAYAA==.',
Sv='Svelda:BAAALgAECgQJBQAAAA==.',
Sw='Swisscake:BAABLgAECn8eAAIMAAgJxx+LBABvAgAMAAgJxx+LBABvAgAAAA==.',
Sy='Sylain:BAAALgAECgYJEQAAAA==.',
Ta='Tannatax:BAABLgAECn8WAAILAAgJoQSvKwAYAQALAAgJoQSvKwAYAQAAAA==.Taterdotz:BAAALgADCgcJBwAAAA==.',
Te='Teamspidey:BAAALgADCgYJBgABLgAECgMJBAABAAAAAA==.Tekvet:BAAALgAECgkJCQAAAA==.',
Th='Theaemz:BAAALgADCgEJAQAAAA==.Theholygoat:BAAALgADCgEJAQAAAA==.Thewhitness:BAABLgAECn8hAAMTAAgJqBc6IwDcAQATAAgJqBc6IwDcAQAjAAEJGgHnCQAMAAAAAA==.Thewretch:BAABLgAECn8gAAINAAgJqx6KCwBaAgANAAgJqx6KCwBaAgAAAA==.Thumpthump:BAAALgAFFAEJAQAAAA==.Thunderclapn:BAAALgAECgMJCAAAAA==.Thunderkiss:BAEALgADCgkJEAABLgAECgIJAwABAAAAAA==.Thundorf:BAAALgADCgUJCQAAAA==.',
Ti='Tiga:BAAALgAECgMJBAAAAA==.Tindario:BAAALgADCgYJBgAAAA==.Titiera:BAAALgAECgQJBwAAAA==.',
To='Toastnbutta:BAABLgAECn8bAAIXAAcJaxrtLAD7AQAXAAcJaxrtLAD7AQAAAA==.Tolten:BAABLgAECn8eAAIGAAgJ3RmYMQBcAgAGAAgJ3RmYMQBcAgAAAA==.Toothguy:BAAALgAECgQJBgAAAA==.Torvasha:BAAALgADCgEJAQAAAA==.Toscus:BAAALgAECgEJAQAAAA==.',
Tr='Tranquility:BAAALgADCgYJBgAAAA==.Trapfail:BAAALgAECgEJAQAAAA==.Traumatism:BAAALgAECgIJAwAAAA==.Trevor:BAABLgAECn8gAAIlAAgJKRGAAwC1AQAlAAgJKRGAAwC1AQAAAA==.Trinnitie:BAAALgAECgEJAQAAAA==.',
Ts='Tshark:BAAALgAECgQJCwABLgAECggJIAAaABAbAA==.',
Tu='Tutatotao:BAAALgADCgMJAwAAAA==.',
Tw='Twotom:BAAALgADCgUJBQAAAA==.',
Un='Unclepeepers:BAACLgAFFH8LAAIPAAMJrxnLDgDuAAAPAAMJrxnLDgDuAAAuAAQKfx8AAw8ACQlrGZkVABgCAA8ACQlrGZkVABgCAAUAAQnMIEVsAF8AAAAA.Underpowered:BAAALgAECgYJDAAAAA==.Ungodlypain:BAAALgAECgcJEAAAAA==.',
Ur='Urtag:BAABLgAFFH8GAAIfAAUJ5gtlAwB0AQAfAAUJ5gtlAwB0AQAAAA==.',
Va='Valastane:BAAALgADCgUJCAAAAA==.Valhen:BAABLgAECn8qAAMmAAgJWxXCBwAgAgAmAAgJWxXCBwAgAgAJAAIJpgVOZAAwAAAAAA==.Valryn:BAAALgAECgIJAgABLgAECggJKgAmAFsVAA==.Valtar:BAABLgAECn8fAAILAAkJpxo8CABnAgALAAkJpxo8CABnAgAAAA==.Vardax:BAAALgADCgcJCQAAAA==.Vaxi:BAABLgAECn8bAAIaAAgJYRxLDwAXAgAaAAgJYRxLDwAXAgAAAA==.',
Ve='Veraalyn:BAABLgAECn8dAAMSAAgJExGAGABOAQASAAgJExGAGABOAQALAAMJxwikfgCZAAAAAA==.',
Vi='Vicsen:BAAALgAECgcJDwAAAA==.Vikaya:BAAALgADCgUJBQAAAA==.Vilevixon:BAAALgAECgcJEgAAAA==.Vineweaver:BAAALgADCgEJAQAAAA==.Vinvoldo:BAAALgADCgcJCwAAAA==.Vistara:BAAALgAECgIJAgAAAA==.',
Vl='Vladof:BAAALgADCggJCQAAAA==.',
Wa='Wakabombo:BAAALgAECgcJEAAAAA==.Walla:BAAALgAECgIJAgABLgAECgMJBAABAAAAAA==.Wanlok:BAAALgAECgQJBAAAAA==.Wantoo:BAAALgAECgYJBQAAAA==.Warlokip:BAAALgAECggJCAAAAA==.Warriorlobo:BAAALgAECgcJEQAAAA==.Warvision:BAAALgAECgYJCwAAAA==.Watchthis:BAAALgAECgMJBAAAAA==.',
Wi='Wildfang:BAABLgAECn8bAAIWAAcJuQy+RgCWAQAWAAcJuQy+RgCWAQAAAA==.Wildside:BAAALgAECgcJBgAAAA==.',
Wu='Wulffgar:BAAALgADCgcJCQAAAA==.',
Xa='Xandronys:BAAALgADCgcJEAAAAA==.Xanne:BAAALgADCgYJBgAAAA==.',
Xe='Xebec:BAAALgAECgEJAQAAAA==.Xenie:BAAALgAECgQJCAAAAA==.',
Xi='Xioran:BAAALgADCgMJAwAAAA==.',
Xy='Xyra:BAAALgADCgcJCAAAAA==.',
Ye='Yeet:BAAALgAECggJEgAAAA==.',
Yt='Ytterli:BAAALgADCgkJCgAAAA==.',
Za='Zaethas:BAAALgAECgEJAwAAAA==.Zagdakka:BAAALgAECgYJDwAAAA==.Zalandra:BAAALgADCggJEQAAAA==.Zalckar:BAAALgAECggJEwAAAA==.Zavar:BAAALgAECgUJBwAAAA==.',
Ze='Zeeva:BAAALgAECgYJCwAAAA==.Zendead:BAABLgAECn8aAAIFAAgJeyFOBABpAgAFAAgJeyFOBABpAgAAAA==.',
Zi='Zionspartan:BAABLgAECn8WAAIWAAcJKw3pLABeAQAWAAcJKw3pLABeAQAAAA==.',
Zo='Zoology:BAAALgAECgYJDQAAAA==.',
Zu='Zugzugshaman:BAABLgAECn8gAAQLAAgJpBZ3DQAWAgALAAgJpBZ3DQAWAgASAAQJrwOEbgCJAAAeAAEJYQDoGwAdAAAAAA==.',
['Ço']='Çoldædheart:BAAALgADCgkJEgAAAA==.',
['Ðø']='Ðøøm:BAAALgADCgEJAQAAAA==.',
['Ñe']='Ñeh:BAABLgAECn8XAAIcAAYJHA6+HwAEAQAcAAYJHA6+HwAEAQAAAA==.',
['Ñå']='Ñårçîssîstîç:BAAALgADCgQJCAAAAA==.',
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

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

local lookup = {'Evoker-Preservation','Evoker-Augmentation','Unknown-Unknown','Monk-Windwalker','Paladin-Retribution','Paladin-Protection','Priest-Holy','Priest-Shadow','Paladin-Holy','Shaman-Restoration','Druid-Balance','Hunter-Survival','Monk-Mistweaver','Warrior-Fury','Shaman-Elemental','Mage-Frost','Warlock-Demonology','DeathKnight-Unholy','Hunter-BeastMastery','DeathKnight-Blood','Warrior-Protection','Monk-Brewmaster','Druid-Restoration','DemonHunter-Vengeance','DemonHunter-Devourer','Shaman-Enhancement','Hunter-Marksmanship','Rogue-Subtlety','Druid-Guardian','Evoker-Devastation','Mage-Fire','Warrior-Arms','Warlock-Affliction','Mage-Arcane','Rogue-Assassination','DemonHunter-Havoc','Priest-Discipline',}
local provider = {region='US',realm="Kael'thas",name='US',type='weekly',zone=46,date='2026-04-24',data={Ad='Adorraa:BAAALgAECgQJBAAAAA==.Adowyrm:BAACLgAFFH8QAAIBAAUJ5xsUAQDPAQABAAUJ5xsUAQDPAQAuAAQKfyEAAwEACQm1IUgCAFEDAAEACQm1IUgCAFEDAAIABgnLHe4cAN8BAAAA.Adriaat:BAAALgADCgMJAwAAAA==.',
Ae='Aeife:BAEALgADCgEJAQABLgAECgcJEgADAAAAAA==.',
Af='Afflockted:BAAALgADCgQJBAAAAA==.',
Ag='Agicat:BAAALgAECgUJCwABLgAECggJHgAEAFogAA==.',
Ai='Airali:BAABLgAECn8UAAMFAAgJlxVvZAC4AQAFAAgJlxVvZAC4AQAGAAMJiQjRNwBiAAAAAA==.Airedale:BAAALgAECgQJCwAAAA==.',
Ak='Akairo:BAABLgAECn8oAAMHAAgJ3iWCAgBBAwAHAAgJ3iWCAgBBAwAIAAYJSQ4VMgBVAQAAAA==.Akelia:BAAALgAECgEJAgAAAA==.Akonic:BAAALgADCgkJDAAAAA==.',
Al='Alasteria:BAAALgAECgkJAgAAAA==.Alcoaplus:BAAALgADCgkJDwABLgAECggJGgACAHccAA==.Alexanderxl:BAAALgAECgYJCgAAAA==.Aleybobwa:BAABLgAECn8XAAMJAAgJeBFhKwDaAQAJAAgJeBFhKwDaAQAFAAEJYwhoUgErAAAAAA==.Alody:BAAALgADCgMJAwAAAA==.',
Am='Amethen:BAAALgADCgMJAwAAAA==.Amochi:BAAALgAECgcJBwAAAA==.Amulius:BAABLgAECn8dAAIFAAgJdyG6DwARAwAFAAgJdyG6DwARAwAAAA==.',
An='Andormath:BAAALgADCggJDAAAAA==.Andramedae:BAAALgAECgYJCgAAAA==.Angyavocado:BAAALgADCgkJCQAAAA==.Anoki:BAABLgAECn8ZAAIKAAcJlBoPBAA3AgAKAAcJlBoPBAA3AgAAAA==.',
Ao='Aolus:BAACLgAFFH8IAAILAAMJZRRRBgDvAAALAAMJZRRRBgDvAAAuAAQKfxgAAgsACQkMHC4TAHsCAAsACQkMHC4TAHsCAAAA.',
Ap='Aphratite:BAAALgADCgMJAwAAAA==.',
Ar='Arbol:BAAALgADCgYJCAABLgAECgEJAgADAAAAAA==.Arcaina:BAAALgAECgYJCAAAAA==.Arez:BAAALgAECgYJEQAAAA==.Artèmís:BAABLgAECn8XAAIMAAcJTxucFgBgAQAMAAcJTxucFgBgAQABLgAECggJHQANAK0ZAA==.',
As='Ashborn:BAAALgADCgEJAQAAAA==.Asladur:BAAALgADCgcJCgAAAA==.',
At='Athenä:BAAALgAECgIJAgAAAA==.',
Az='Azaekho:BAABLgAECn8hAAIKAAkJHRA1DAB5AQAKAAkJHRA1DAB5AQAAAA==.',
Ba='Badoosh:BAABLgAECn8dAAIOAAgJCB2gGACHAgAOAAgJCB2gGACHAgAAAA==.Bajablaster:BAAALgAECgYJDwAAAA==.Baliw:BAAALgADCgUJBAAAAA==.Balto:BAAALgADCgMJAwAAAA==.',
Bb='Bbl:BAABLgAECn8fAAIPAAgJQR9RCgDwAgAPAAgJQR9RCgDwAgAAAA==.',
Bc='Bchung:BAACLgAFFH8IAAIQAAMJ6hLVEgD+AAAQAAMJ6hLVEgD+AAAuAAQKfx8AAhAACQm5GZA7AIkCABAACQm5GZA7AIkCAAAA.',
Be='Beertits:BAAALgAECgEJAQAAAA==.Belip:BAAALgAECgYJCgAAAA==.',
Bh='Bhain:BAAALgADCgcJDQABLgAECgcJIAARANMdAA==.',
Bi='Bieorne:BAABLgAECn8YAAISAAYJoxrdEQCFAQASAAYJoxrdEQCFAQAAAA==.',
Bl='Blastbane:BAAALgAECgkJEgAAAA==.Bloodwrath:BAAALgADCgQJBAAAAA==.',
Bn='Bnanaketchup:BAAALgADCgQJBAAAAA==.',
Bo='Boo:BAABLgAECn8VAAIRAAkJgBz+DwD6AgARAAkJgBz+DwD6AgABLgAFFAEJAQADAAAAAA==.Boondocks:BAAALgAECgYJDAAAAA==.',
Br='Braca:BAAALgADCgEJAQAAAA==.Braelek:BAAALgADCgEJAQAAAA==.Brewslei:BAAALgADCgYJBgAAAA==.Brewtime:BAAALgAECgYJCgAAAA==.Brielle:BAABLgAECn8bAAITAAcJrRWmLwDzAQATAAcJrRWmLwDzAQAAAA==.Brokenbranch:BAAALgADCgcJEgAAAA==.Brudene:BAAALgAECgcJDgAAAA==.Brynhildr:BAAALgADCgYJBgAAAA==.',
Bu='Buddylock:BAABLgAECn8XAAIRAAcJ5An1eABqAQARAAcJ5An1eABqAQAAAA==.Bullymaguire:BAACLgAFFH8FAAIEAAMJDxWRBwD9AAAEAAMJDxWRBwD9AAAuAAQKfx0AAgQACAk5I0EFADEDAAQACAk5I0EFADEDAAAA.Burakkuburu:BAABLgAECn8dAAMNAAgJrRkeAwAmAgANAAgJrRkeAwAmAgAEAAYJ4RXYJwCbAQAAAA==.',
Ca='Caboozles:BAABLgAECn8bAAITAAgJvBPCCgC9AQATAAgJvBPCCgC9AQAAAA==.Caliopia:BAABLgAECn8aAAIPAAcJzxSRCgBSAQAPAAcJzxSRCgBSAQAAAA==.Captnhuntcat:BAAALgAECgIJAgAAAA==.Carcosa:BAAALgAECgEJAQAAAA==.Cardone:BAAALgAECgEJAQAAAA==.',
Ce='Ceromaar:BAABLgAECn8YAAIOAAgJNxGABgC8AQAOAAgJNxGABgC8AQAAAA==.Ceti:BAAALgAECgcJDAAAAA==.',
Ch='Chaoticdh:BAAALgADCgYJBgAAAA==.Checkurback:BAAALgAECggJEwAAAA==.Chemistree:BAAALgAECgYJEQAAAA==.Chillout:BAAALgAECgYJEAAAAA==.Chillums:BAABLgAECn8bAAIRAAcJ4iPHBgAGAgARAAcJ4iPHBgAGAgAAAA==.Chipcle:BAAALgADCgcJCwAAAA==.Chocoflan:BAAALgADCgIJAgAAAA==.Chöpper:BAAALgADCgEJAgAAAA==.',
Cl='Clumsy:BAAALgADCgUJBQABLgADCgQJBAADAAAAAA==.',
Co='Cokarott:BAAALgAECgUJBgAAAA==.Cops:BAAALgAECggJEQAAAA==.Coral:BAAALgADCgkJGQAAAA==.',
Cr='Criticål:BAAALgADCgIJAgAAAA==.Crusherk:BAAALgAECgcJBQAAAA==.',
Da='Dabercoo:BAAALgADCgQJBAAAAA==.Daeleiel:BAAALgADCgMJAwAAAA==.Darkenergy:BAAALgAECgYJDgAAAA==.Darthtotem:BAAALgAECgYJEQABLgAECgcJAQADAAAAAA==.Dashyll:BAAALgADCggJDwAAAA==.Davyfknjones:BAAALgAECgUJBgAAAA==.',
De='Deadlegslul:BAAALgAECgMJBQAAAA==.Deadlegsmd:BAAALgADCgcJCwAAAA==.Deadrat:BAAALgAECgMJAwAAAA==.Deadzepplin:BAAALgAECgEJAQAAAA==.Deathmono:BAAALgAECgYJCQAAAA==.Deathshark:BAABLgAECn8cAAIUAAgJchq+CgBsAgAUAAgJchq+CgBsAgAAAA==.Dellphine:BAAALgAECgEJAQAAAA==.Demacus:BAAALgAECgcJBwAAAA==.Demeter:BAABLgAECn8aAAIGAAcJLhJEFgBuAQAGAAcJLhJEFgBuAQAAAA==.Demonhunters:BAAALgADCgcJDAAAAA==.Demontb:BAAALgAECgkJAQAAAA==.Denarien:BAAALgAECgEJAwAAAA==.Derpygos:BAAALgADCgcJBwAAAA==.Devouress:BAAALgAECgYJBgABLgAECggJGAAEAEUgAA==.',
Di='Dillkiller:BAABLgAECn8WAAIVAAcJGQn7IQAuAQAVAAcJGQn7IQAuAQAAAA==.Dirgen:BAAALgAECgYJBgAAAA==.Disspair:BAAALgADCgEJAQAAAA==.',
Do='Dobbyscumsok:BAAALgAECgYJEQAAAA==.Dookiee:BAAALgAECgYJEQAAAA==.Dorksparrow:BAAALgAECgQJBwABLgAECggJGwAWAMMPAA==.Doug:BAAALgADCgcJDQAAAA==.Doxom:BAAALgADCgEJAQAAAA==.',
Dr='Dracalled:BAAALgAECgcJEgAAAA==.Draggnar:BAAALgADCgcJDAAAAA==.Dragönlöl:BAAALgAECgYJCAAAAA==.Dramme:BAAALgAECgIJAgAAAA==.Druidvishnu:BAAALgAECgYJCQAAAA==.',
Du='Dumplingsxo:BAABLgAECn8fAAMLAAkJnBg7GQA9AgALAAgJsBk7GQA9AgAXAAcJaxWTPQCtAQAAAA==.Dusktodawn:BAAALgAECgUJDgAAAA==.',
Dy='Dyharmis:BAABLgAECn8aAAIYAAcJGCSjAABLAgAYAAcJGCSjAABLAgAAAA==.',
Eb='Ebojager:BAABLgAECn8XAAIZAAYJ/RBtGgAuAQAZAAYJ/RBtGgAuAQAAAA==.',
Ei='Eibon:BAACLgAFFH8MAAISAAQJXxZfFQBOAQASAAQJXxZfFQBOAQAuAAQKfx4AAhIACQnNIaIUAAADABIACQnNIaIUAAADAAAA.',
El='Elliiria:BAAALgADCgcJBwAAAA==.Eloïse:BAAALgADCgYJCQAAAA==.Elthion:BAAALgADCgMJBAAAAA==.Elvispriesty:BAAALgAECgQJCgAAAA==.Elwarrioro:BAAALgAECgYJCAAAAA==.',
Em='Emmune:BAABLgAECn8UAAIaAAYJKhGDBQBDAQAaAAYJKhGDBQBDAQAAAA==.',
En='Enobia:BAAALgAECgUJBQAAAA==.Entrapment:BAAALgADCgYJBgABLgADCgQJBAADAAAAAA==.Envie:BAAALgAECgQJBQAAAA==.',
Er='Eriaeda:BAAALgAECgQJBAAAAA==.',
Es='Eskath:BAAALgAECgUJCQAAAA==.Essential:BAAALgAECgcJEAAAAA==.',
Et='Eternalpain:BAAALgADCgEJAQAAAA==.',
Ev='Evdoggy:BAAALgAECgYJDgAAAA==.Evilkills:BAAALgAECgMJAwAAAA==.',
Ex='Exterminate:BAAALgAECgIJAgAAAA==.',
Fe='Feekknight:BAAALgADCgQJBAAAAA==.Fellon:BAAALgADCgEJAQAAAA==.Femmur:BAAALgADCgMJAwAAAA==.Fenrin:BAAALgAECgMJAgAAAA==.Fenrîr:BAAALgADCgYJBgABLgAECgYJEQADAAAAAA==.Ferrara:BAACLgAFFH8PAAMbAAUJeyHaCwBdAQAbAAUJDx3aCwBdAQATAAEJzh+pHwBiAAAuAAQKfyAABBsACQnRIxQGADkDABsACQmLIxQGADkDABMAAQn1I56wAGIAAAwAAQk6HvcrAEYAAAAA.',
Fi='Finesse:BAAALgADCggJFQAAAA==.Firebåll:BAAALgAECgIJAgAAAA==.Fishbait:BAAALgADCgIJAgABLgAECgcJGgALAFkgAA==.Fisterjob:BAAALgADCgYJBwAAAA==.',
Fl='Flandri:BAAALgAFFAQJBAAAAA==.Flandrie:BAAALgADCgMJAwAAAA==.Flexicute:BAAALgADCgcJDAAAAA==.',
Fo='Foxlock:BAAALgADCgYJBgAAAA==.',
Fr='Frostednip:BAABLgAECn8UAAISAAgJgyFdNABlAgASAAgJgyFdNABlAgAAAA==.',
Ga='Gabiru:BAAALgAFFAMJBAAAAA==.Gadreeste:BAAALgADCgUJBQAAAA==.Galnarn:BAACLgAFFH8QAAIWAAUJMB0ZAgBwAQAWAAUJMB0ZAgBwAQAuAAQKfyEAAhYACQliHfwNALQCABYACQliHfwNALQCAAAA.Gambagood:BAAALgAECgYJCgAAAA==.Garious:BAAALgADCgcJBwABLgAFFAIJBQASACEdAA==.Garlicbae:BAAALgADCgkJFwAAAA==.Garwulf:BAAALgAECgQJBwAAAA==.',
Ge='Gefaustet:BAAALgAECgYJDAAAAA==.Gelroos:BAAALgADCgEJAQAAAA==.',
Gl='Glimpse:BAAALgADCgEJAQAAAA==.Glognar:BAAALgADCgQJBAAAAA==.',
Go='Goatcheesè:BAAALgAECgEJAQAAAA==.Goatess:BAAALgADCgYJCQAAAA==.Goopa:BAAALgAECgYJCgAAAA==.Goopert:BAAALgADCgYJDAAAAA==.Goopy:BAAALgAECgYJCQAAAA==.Gorbachev:BAAALgADCgYJEAAAAA==.Gorehowl:BAAALgAECgEJAQAAAA==.Goro:BAAALgADCgQJBAAAAA==.',
Gr='Graybrew:BAAALgADCgcJDAAAAA==.Grayes:BAAALgAECgYJEQAAAA==.Grayson:BAAALgADCgUJBQAAAA==.Grorkster:BAAALgADCgUJBQAAAQ==.Grute:BAAALgADCgcJDQAAAA==.',
Ha='Hallowshade:BAABLgAECn8XAAIcAAcJERntBACxAQAcAAcJERntBACxAQAAAA==.Hardran:BAAALgAECgQJBAAAAA==.Harington:BAAALgAECgkJAgAAAA==.Harmôny:BAAALgADCggJDQAAAA==.Hatreddyes:BAAALgADCgUJBQAAAA==.Hatredyes:BAAALgAECgUJBgAAAA==.',
He='Helare:BAAALgAECgIJAgAAAA==.Henrymorgan:BAAALgAECgkJAQAAAA==.Hexenbane:BAAALgAECgYJCgAAAA==.',
Hi='Hinatsuru:BAAALgAECgEJAQAAAA==.',
Ho='Holyzap:BAAALgADCgIJAgABLgAECggJHQAQACQfAA==.Hoyt:BAAALgADCgcJCgAAAA==.',
Hu='Hugme:BAAALgAECgkJAgAAAA==.Hukhan:BAAALgAECgEJAQAAAA==.Hunthard:BAAALgAECgEJAQAAAA==.Huunno:BAAALgAECgIJAgABLgAECgMJBAADAAAAAA==.',
Hy='Hyasin:BAAALgADCgUJDQAAAA==.',
Ic='Ichom:BAAALgADCgMJAwABLgAECgYJEwADAAAAAA==.',
Id='Idalia:BAAALgADCgQJBAABLgADCgYJDwADAAAAAA==.',
If='Iforgotnaaru:BAAALgAECgQJBAAAAA==.',
Il='Illiae:BAAALgAECgYJDwAAAA==.',
Im='Impactr:BAAALgADCgMJAwAAAA==.Imtheteapot:BAABLgAECn8jAAIOAAgJrQ3WBgC2AQAOAAgJrQ3WBgC2AQAAAA==.',
In='Innex:BAABLgAECn8ZAAISAAgJUBvXLgB9AgASAAgJUBvXLgB9AgAAAA==.Innexrogue:BAAALgAECgEJAgABLgAECggJGQASAFAbAA==.Innexvoker:BAAALgAECgUJBQABLgAECggJGQASAFAbAA==.Inpesca:BAAALgADCgUJBQABLgAECggJGgACAHccAA==.Insanityx:BAAALgAECggJCAAAAA==.',
Io='Ionic:BAAALgAECgEJAQAAAA==.',
Ir='Iridescent:BAAALgAECgIJAgAAAA==.Ironpalm:BAAALgAECgQJBAAAAA==.',
Is='Issidora:BAAALgAECgUJBQAAAA==.',
It='Ithronel:BAAALgADCgUJBQAAAA==.Itzmuffin:BAABLgAECn8ZAAIKAAcJUhPjNgCnAQAKAAcJUhPjNgCnAQAAAA==.Itzpie:BAABLgAECn8dAAIQAAcJDhRsjQC4AQAQAAcJDhRsjQC4AQAAAA==.',
Ja='Jagtat:BAAALgAECgYJCgAAAA==.Jakeakuma:BAAALgAECggJEgAAAA==.Jascob:BAAALgAECgUJEAAAAA==.',
Je='Jessa:BAAALgADCgMJAwAAAA==.',
Jh='Jhivago:BAAALgADCgEJAQAAAA==.',
Jo='Johnivxx:BAAALgADCgcJAwAAAA==.Johnnybravo:BAAALgAECgIJBAAAAA==.',
Ju='Judokeg:BAAALgAECgYJEwAAAA==.Juglass:BAAALgADCgEJAQAAAA==.Jujutsu:BAABLgAECn8eAAIEAAgJWiBZCAD0AgAEAAgJWiBZCAD0AgAAAA==.Junfan:BAAALgAECgcJAwAAAA==.',
Ka='Kaashaa:BAABLgAECn8aAAITAAcJnhuCMQDqAQATAAcJnhuCMQDqAQAAAA==.Kaelsgf:BAAALgADCgIJAgAAAA==.Kahllan:BAAALgAECgYJBgAAAA==.Kahnigitt:BAAALgAECgIJAgAAAA==.Kataltoholic:BAAALgAECgUJCAAAAA==.Katrath:BAAALgADCgIJAgAAAA==.Kayser:BAAALgAECgIJAgAAAA==.Kaýhas:BAABLgAECn8VAAIZAAcJdxgADgCeAQAZAAcJdxgADgCeAQAAAA==.',
Ke='Kelinïsha:BAABLgAECn8ZAAIQAAcJCQpIMAAIAQAQAAcJCQpIMAAIAQAAAA==.Kelynna:BAAALgAECgYJDwAAAA==.Kevinarnold:BAAALgADCgEJAQAAAA==.Kevinbacon:BAAALgAECgEJAQAAAA==.',
Ki='Kiiras:BAABLgAECn8fAAIQAAgJFApqGgB2AQAQAAgJFApqGgB2AQAAAA==.Kimbodh:BAABLgAECn8bAAIZAAgJGyJ9EAD6AgAZAAgJGyJ9EAD6AgABLgABCgMJAQADAAAAAA==.Kinvictusk:BAAALgAECgEJAQAAAA==.Kirathein:BAAALgAECgcJEwABLgABCgMJAwADAAAAAA==.',
Kl='Klefthoof:BAAALgAECgYJEwABLgAECgcJBwADAAAAAA==.',
Ko='Kodey:BAAALgAECgQJCAABLgAFFAEJAQADAAAAAA==.Kordy:BAAALgAECgkJAQAAAA==.',
Kr='Kraniah:BAAALgAECgIJBQAAAA==.Krimboz:BAAALgAECgYJDwAAAA==.Krimdk:BAAALgADCgcJBwAAAA==.Krystallight:BAAALgAECgYJEwAAAA==.Krìsta:BAAALgAECgYJEAAAAA==.',
Ku='Kuanshuwo:BAAALgAECgYJDQAAAA==.Kullomaa:BAAALgAECgcJBQAAAA==.',
La='Lanwulf:BAAALgADCggJDQAAAA==.Lastgasp:BAAALgADCgcJBwAAAA==.Lauriela:BAAALgAECgQJCwAAAA==.',
Le='Lechuzón:BAAALgADCgMJAwAAAA==.Ledrõllan:BAABLgAECn8VAAIIAAgJyx65FwAmAgAIAAgJyx65FwAmAgAAAA==.Legaloas:BAAALgAECgYJEQAAAA==.Leinhart:BAAALgAECgUJCQAAAA==.Lenah:BAAALgADCgcJEwAAAA==.Leonarde:BAACLgAFFH8IAAMTAAMJERSsCAD9AAATAAMJ1gusCAD9AAAbAAMJ2Q+sFQDuAAAuAAQKfx4ABBsACQkBFh8hABoCABsACAkSFx8hABoCABMAAQmLDs86AFMAAAwAAQlWAKUzAA0AAAAA.Levitt:BAAALgAECgQJBQAAAA==.',
Li='Lilsia:BAAALgADCgEJAQAAAA==.Lilwok:BAABLgAECn8bAAIEAAcJPxK4CgAmAQAEAAcJPxK4CgAmAQAAAA==.Lintelworth:BAAALgADCgYJFAAAAA==.Liradia:BAAALgAECgIJAwAAAA==.Liver:BAAALgADCgkJFQAAAA==.',
Ll='Llevanya:BAABLgAECn8UAAIFAAYJiQZwtwAWAQAFAAYJiQZwtwAWAQAAAA==.Llinaigh:BAAALgAECgYJDAAAAA==.',
Lo='Loanna:BAAALgADCgYJDwAAAA==.Lomu:BAABLgAECn8VAAQdAAgJPRopCwDfAQAdAAgJPRopCwDfAQAXAAEJ7Q5AzwAvAAALAAEJlAQkJQAoAAAAAA==.Loredalso:BAAALgADCggJEAAAAA==.Lorenitha:BAAALgAECgEJAQABLgAFFAMJBQAFAAoYAA==.',
Lu='Lunastraz:BAAALgADCgkJDwAAAA==.',
Ma='Magerproblem:BAAALgAECgYJDwABLgAFFAEJAQADAAAAAA==.Magicdreams:BAABLgAECn8YAAILAAYJlwd0EADuAAALAAYJlwd0EADuAAAAAA==.Malificent:BAAALgADCgMJBQAAAA==.Malmorte:BAAALgAECgYJEwAAAA==.Malorane:BAABLgAECn8eAAIUAAgJqxtCAwDDAQAUAAgJqxtCAwDDAQAAAA==.Mana:BAAALgADCgUJBQAAAA==.Marcasite:BAAALgADCgIJAQAAAA==.Marihuano:BAAALgADCgYJCAABLgADCgcJCwADAAAAAA==.Marisi:BAAALgADCggJCAAAAA==.Mastir:BAAALgADCgMJAwAAAA==.Masumune:BAAALgAECgMJAwAAAA==.Matamosca:BAABLgAECn8eAAIcAAgJrB02AQBlAgAcAAgJrB02AQBlAgAAAA==.Materiaga:BAABLgAECn8eAAQCAAgJthCRBQCoAQACAAgJthCRBQCoAQABAAYJFQtcKQAoAQAeAAEJsAnFPgA0AAAAAA==.Mature:BAAALgADCgIJAgAAAA==.Maz:BAABLgAECn8aAAIFAAcJFSETBgAzAgAFAAcJFSETBgAzAgAAAA==.',
Mc='Mcflury:BAABLgAECn8mAAMaAAkJGxU1BgCWAgAaAAkJGxU1BgCWAgAPAAcJhA9tDQApAQAAAA==.',
Me='Meerchi:BAABLgAECn8WAAMQAAgJNgnTugBsAQAQAAgJFgnTugBsAQAfAAQJWAO/CgCVAAAAAA==.Meetyomaker:BAAALgAECgUJCAAAAA==.Meowkai:BAAALgAECgYJBgABLgAECggJHQANAK0ZAA==.Mesthos:BAAALgAECgcJCwABLgAECggJFwAYAC4lAA==.Mestyphe:BAAALgAECgMJAwAAAA==.Metalmoth:BAAALgADCgEJAQAAAA==.Metformin:BAABLgAECn8eAAICAAgJNRKEGgD2AQACAAgJNRKEGgD2AQAAAA==.',
Mi='Mickieta:BAAALgAECgYJDAAAAA==.Microsurge:BAABLgAECn8cAAIQAAgJIB3YJQDbAgAQAAgJIB3YJQDbAgAAAA==.Mikalau:BAAALgAECgQJBwAAAA==.Mikaluu:BAAALgADCgkJCwAAAA==.Missteek:BAAALgADCgUJBQABLgAECgYJDwADAAAAAA==.Mistrunner:BAAALgADCgUJBgAAAA==.Mistspell:BAACLgAFFH8IAAIIAAMJghJyBQDtAAAIAAMJghJyBQDtAAAuAAQKfx8AAwgACQkXG94OAJUCAAgACQkXG94OAJUCAAcAAwklBnBqAIIAAAAA.',
Mo='Mochia:BAAALgAECgYJEwAAAA==.Mognel:BAABLgAECn8eAAIRAAgJjhn5DQCjAQARAAgJjhn5DQCjAQAAAA==.Mogrungar:BAAALgAECgcJDQAAAA==.Moisten:BAAALgAECgcJEQAAAA==.Moomootus:BAAALgAECgYJBgAAAA==.Moxod:BAAALgAECgEJAQAAAA==.Mozzie:BAAALgAECgcJEQAAAA==.',
My='Mysterica:BAAALgADCgYJBgAAAA==.Mysticize:BAABLgAECn8YAAIEAAgJRSBjDQClAgAEAAgJRSBjDQClAgAAAA==.Mystynight:BAAALgAECgYJBwAAAA==.',
['Má']='Mác:BAAALgAECgEJAQAAAA==.',
Na='Naajin:BAAALgAECgYJDwAAAA==.Nagini:BAAALgAECgYJEQAAAA==.',
Ne='Neiko:BAAALgADCgUJBQAAAA==.Newt:BAAALgADCgUJBQAAAA==.',
Ni='Nicegauges:BAEBLgAECn8cAAMIAAcJmQ9jMABgAQAIAAcJmQ9jMABgAQAHAAQJhhLrUQDwAAAAAA==.Nietzcha:BAAALgADCgYJDQAAAA==.Nightpetal:BAAALgAECgMJAwAAAA==.Nightstandd:BAAALgADCgcJBwAAAA==.Nigogg:BAAALgADCgIJAgAAAA==.Nioh:BAAALgAECggJEwAAAA==.',
No='Noodles:BAABLgAECn8WAAIZAAYJowkyjAAKAQAZAAYJowkyjAAKAQAAAA==.Nordrydsh:BAAALgADCgkJCQABLgAFFAMJBgANABAXAA==.',
Nu='Nuggs:BAAALgAECggJCQAAAA==.Nuhpie:BAACLgAFFH8HAAMOAAUJwQjpBgDvAAAOAAMJ5gbpBgDvAAAgAAIJUw7UBQBZAAAuAAQKfxQAAw4ABwm/Fu1LAHYBAA4ABQlZF+1LAHYBACAAAwllEtMiANYAAAAA.',
['Nè']='Nèkrosis:BAAALgAECgYJEwAAAA==.',
Ol='Olimdar:BAACLgAFFH8PAAIKAAUJZiLzAQCEAQAKAAUJZiLzAQCEAQAuAAQKfyEAAwoACQlsJUkAAM8DAAoACQlsJUkAAM8DAA8AAQmSHY2CAD4AAAAA.',
Om='Omnidraconus:BAAALgAECgMJAwAAAA==.',
Oo='Oopsdidipull:BAAALgADCgYJBwAAAA==.',
Or='Oricelle:BAABLgAECn8aAAIZAAcJ2hLgGAA5AQAZAAcJ2hLgGAA5AQAAAA==.Oryon:BAEBLgAECn8YAAIhAAYJGQ7jDQBVAQAhAAYJGQ7jDQBVAQAAAA==.',
Ov='Ovarb:BAABLgAECn8WAAIUAAcJEhiVBACFAQAUAAcJEhiVBACFAQAAAA==.',
Ox='Oxiclean:BAAALgAECgEJAQAAAA==.',
Pa='Pachum:BAAALgAECgQJCwAAAA==.Palasexo:BAAALgADCgcJCwAAAA==.Paluu:BAAALgAECgEJAQAAAA==.Paragon:BAAALgAECgEJAQAAAA==.Pavo:BAAALgADCgQJBAAAAA==.',
Pe='Pesti:BAACLgAFFH8FAAIcAAMJAA6SDgAGAQAcAAMJAA6SDgAGAQAuAAQKfyMAAhwABwngHpQUAG4CABwABwngHpQUAG4CAAAA.Petevoker:BAEALgAECgcJEQAAAA==.',
Ph='Phenoman:BAABLgAECn8fAAIKAAgJUSIoCgDXAgAKAAgJUSIoCgDXAgAAAA==.',
Pl='Plágué:BAAALgAECgYJBwAAAA==.',
Po='Polong:BAAALgAECgYJDAAAAA==.Ponypants:BAAALgAECgYJEAAAAA==.',
Pr='Preparedman:BAAALgAECgYJBgAAAA==.Preppyplum:BAABLgAECn8YAAMQAAgJqBc/FwCKAQAQAAgJtBY/FwCKAQAiAAUJrRIhDAAQAQAAAA==.Proctologist:BAAALgAECgYJDwAAAA==.Proserpìne:BAAALgAECgYJDwAAAA==.',
Ps='Psychojester:BAABLgAECn8dAAIaAAgJ7hvGBgCGAgAaAAgJ7hvGBgCGAgAAAA==.Psylir:BAAALgAECgQJDAAAAA==.Psythrot:BAAALgADCgUJCgAAAA==.',
Pu='Putt:BAAALgAECgUJCAAAAA==.',
Py='Pydge:BAAALgADCgEJAgAAAA==.',
Qu='Quod:BAAALgAECgQJBAAAAA==.Quoril:BAABLgAECn8YAAMQAAYJPhpZGACDAQAQAAYJPhpZGACDAQAiAAEJlyB5GQBMAAABLgAFFAMJBwATANsKAA==.',
Ra='Raijyu:BAABLgAECn8ZAAMIAAcJgRdzIwC8AQAIAAYJdBdzIwC8AQAHAAEJaRpdGwBPAAAAAA==.Rainfallen:BAAALgADCgQJBAABLgAECgcJFwALABYQAA==.Rainstormin:BAABLgAECn8XAAILAAcJFhBFDAApAQALAAcJFhBFDAApAQAAAA==.Rakarra:BAAALgAECgYJCAAAAA==.Rawrstance:BAAALgAECgYJEQABLgADCgQJBAADAAAAAA==.Razgrize:BAAALgAECgQJBwAAAA==.',
Re='Reecalled:BAAALgADCgUJBQABLgAECgcJEgADAAAAAA==.Reeshan:BAAALgAECggJEAAAAA==.Reilin:BAAALgAECgQJBAAAAA==.Remsham:BAAALgAECgYJCgAAAA==.Renwyck:BAABLgAECn8XAAIYAAgJLiXYAQD2AgAYAAgJLiXYAQD2AgAAAA==.Revengemoon:BAACLgAFFH8IAAIFAAMJlQ5TFwDzAAAFAAMJlQ5TFwDzAAAuAAQKfx8AAgUACQnDGcIpAH4CAAUACQnDGcIpAH4CAAAA.Revitalized:BAAALgADCgQJBAAAAA==.',
Ri='Riakhar:BAAALgAECgEJAQAAAA==.Riddlebox:BAAALgAECgcJCwABLgAECgkJAgADAAAAAA==.Ringberg:BAAALgAFFAEJAQAAAA==.',
Ro='Robane:BAAALgAECgQJBwAAAA==.Robertdowney:BAAALgADCgUJBQAAAA==.Ronburgundy:BAAALgAECgIJAgAAAA==.Rouen:BAABLgAECn8YAAIaAAYJaCOoBwBtAgAaAAYJaCOoBwBtAgAAAA==.',
Ru='Ruckus:BAEALgAECgIJAgAAAA==.Ruder:BAAALgAECgEJAQAAAA==.Ruhe:BAAALgADCgYJDAAAAA==.Rutabaga:BAAALgAECgUJCAAAAA==.',
Rw='Rword:BAAALgADCgEJAQAAAA==.',
Ry='Rykken:BAAALgADCgEJAQAAAA==.Ryotash:BAAALgADCgIJBAAAAA==.Rythas:BAABLgAECn8hAAIIAAkJPx+OAADgAgAIAAkJPx+OAADgAgAAAA==.',
Sa='Saintanic:BAAALgADCgQJBAAAAA==.Sandkat:BAABLgAECn8YAAIOAAYJoRrGNQDRAQAOAAYJoRrGNQDRAQAAAA==.Sanstian:BAAALgAECgQJCAAAAA==.Santamou:BAAALgADCgIJAgAAAA==.Saraelin:BAAALgAECgEJAQAAAA==.Saray:BAAALgAECgcJCwAAAA==.Saronis:BAAALgADCgQJBAAAAA==.Saurelli:BAAALgADCggJDQABLgAFFAQJBQAjACMMAA==.Sazlok:BAAALgADCgIJAgAAAA==.',
Sc='Scera:BAAALgADCgUJBQAAAA==.Scribbler:BAAALgAECgEJAQAAAA==.',
Se='Sedak:BAAALgAECgQJBAAAAA==.Serahstia:BAAALgAECgYJEQAAAA==.Serbustin:BAAALgAECgEJAgAAAA==.',
Sh='Shadowluna:BAAALgADCgkJGQAAAA==.Shaiy:BAAALgAECgMJBQAAAA==.Shiftymonky:BAAALgADCgYJBgAAAA==.Shinta:BAAALgADCggJDwAAAA==.Shirtles:BAAALgAECgMJAwAAAA==.Shockblocked:BAAALgAECgEJAQAAAA==.Shèp:BAAALgAECgUJDAABLgAECgcJCwADAAAAAA==.',
Si='Siani:BAAALgADCgYJBgAAAA==.Sidecake:BAABLgAFFH8IAAIPAAUJ/hmDAwCzAQAPAAUJ/hmDAwCzAQAAAA==.Siffrin:BAAALgAECgIJAgAAAA==.Silviria:BAAALgADCgEJAQAAAA==.Singars:BAAALgAECgcJEQABLgAECggJHgACADUSAA==.Sinkingship:BAAALgADCgcJDwAAAA==.Sipra:BAAALgAECgYJCAAAAA==.Sisterkind:BAAALgADCgIJAgAAAA==.Siypra:BAAALgAECgQJBAAAAA==.',
Sk='Skorpix:BAAALgADCgMJAwAAAA==.Skrrt:BAAALgADCgEJAQAAAA==.',
Sl='Sloothi:BAAALgADCgYJDgAAAA==.',
Sn='Snokplaster:BAAALgADCgUJBQAAAA==.',
So='Sotopriest:BAAALgAECgYJBwAAAA==.Sotosan:BAAALgAECgcJBwAAAA==.Sotoshaman:BAAALgAECgIJAgAAAA==.Soulhammer:BAAALgAECgcJDAAAAA==.',
Sp='Sprodage:BAAALgAECgYJDwAAAA==.',
St='Stanil:BAAALgAECgUJBwAAAA==.Stayfrosty:BAAALgAECgEJAQAAAA==.Stellare:BAABLgAECn8aAAIkAAgJgg/QBACFAQAkAAgJgg/QBACFAQAAAA==.Stevathor:BAAALgAECgEJAQAAAA==.Styló:BAAALgAECgIJAgAAAA==.',
Su='Suetonius:BAAALgAECgEJAQAAAA==.Sunwalker:BAAALgAECgEJAQAAAA==.Surasaurus:BAABLgAECn8aAAIQAAcJpRiEFgCPAQAQAAcJpRiEFgCPAQAAAA==.Suraschi:BAAALgADCgYJBQABLgAECgcJGgAQAKUYAA==.',
Sv='Svelda:BAAALgAECgEJAQAAAA==.',
Sw='Swisscake:BAABLgAECn8aAAILAAcJWSAoAwAHAgALAAcJWSAoAwAHAgAAAA==.',
Sy='Sylain:BAAALgAECgYJEQABLgAECggJCAADAAAAAA==.',
Ta='Tannatax:BAABLgAECn8UAAIKAAYJkwUsFwDuAAAKAAYJkwUsFwDuAAAAAA==.Taterdotz:BAAALgADCgcJBwAAAA==.',
Te='Teamspidey:BAAALgADCgYJBgABLgAECgMJBAADAAAAAA==.Tekvet:BAAALgAECgkJCQAAAA==.',
Th='Theaemz:BAAALgADCgEJAQAAAA==.Theholygoat:BAAALgADCgEJAQAAAA==.Thewhitness:BAABLgAECn8YAAIQAAcJ7xb5FQCTAQAQAAcJ7xb5FQCTAQAAAA==.Thewretch:BAABLgAECn8YAAIRAAYJ5SBPDAC1AQARAAYJ5SBPDAC1AQAAAA==.Thumpthump:BAAALgAECggJEwAAAA==.Thunderclapn:BAAALgAECgMJBwAAAA==.Thunderkiss:BAEALgADCgcJBwABLgAECgIJAgADAAAAAA==.Thundorf:BAAALgADCgUJCQAAAA==.',
Ti='Tiga:BAAALgAECgMJBAAAAA==.Tindario:BAAALgADCgYJBgAAAA==.Titiera:BAAALgAECgQJBgAAAA==.',
To='Toastnbutta:BAAALgAECgcJEAAAAA==.Tolten:BAABLgAECn8eAAIFAAgJ3RmgMQBcAgAFAAgJ3RmgMQBcAgAAAA==.Toothguy:BAAALgAECgQJBgAAAA==.Torvasha:BAAALgADCgEJAQAAAA==.Toscus:BAAALgAECgEJAQAAAA==.',
Tr='Tranquility:BAAALgADCgYJBgAAAA==.Trapfail:BAAALgAECgEJAQAAAA==.Traumatism:BAAALgAECgIJAwAAAA==.Trevor:BAABLgAECn8YAAIjAAYJERJLAwBDAQAjAAYJERJLAwBDAQAAAA==.Trinnitie:BAAALgAECgEJAQAAAA==.',
Ts='Tshark:BAAALgAECgQJCAABLgAECggJHAAUAHIaAA==.',
Tu='Tutatotao:BAAALgADCgMJAwAAAA==.',
Tw='Twotom:BAAALgADCgUJBQAAAA==.',
Un='Unclepeepers:BAACLgAFFH8IAAINAAMJYBGABgDWAAANAAMJYBGABgDWAAAuAAQKfx8AAw0ACQlrGY8VABkCAA0ACQlrGY8VABkCAAQAAQnMID1sAF8AAAAA.Underpowered:BAAALgAECgYJDAAAAA==.Ungodlypain:BAAALgAECgcJEAAAAA==.',
Ur='Urtag:BAAALgAFFAQJBAAAAA==.',
Va='Valastane:BAAALgADCgUJCAAAAA==.Valhen:BAABLgAECn8VAAMlAAgJ4g1THACzAQAlAAgJ4g1THACzAQAIAAEJhQdFZAAwAAAAAA==.Valryn:BAAALgAECgIJAgABLgAECggJFQAlAOINAA==.Valtar:BAABLgAECn8WAAIKAAgJ0hq9GQBJAgAKAAgJ0hq9GQBJAgAAAA==.Vardax:BAAALgADCgcJAwAAAA==.Vaxi:BAABLgAECn8ZAAIUAAgJShxMDwAXAgAUAAgJShxMDwAXAgAAAA==.',
Ve='Veraalyn:BAABLgAECn8dAAMPAAgJExG+CgBPAQAPAAgJExG+CgBPAQAKAAMJxwihfgCZAAAAAA==.',
Vi='Vicsen:BAAALgAECgcJDwAAAA==.Vikaya:BAAALgADCgUJBQAAAA==.Vilevixon:BAAALgAECgYJDAAAAA==.Vineweaver:BAAALgADCgEJAQAAAA==.Vinvoldo:BAAALgADCgcJCwAAAA==.Vistara:BAAALgAECgEJAQAAAA==.',
Vl='Vladof:BAAALgADCggJCQAAAA==.',
Wa='Wakabombo:BAAALgAECgcJEAAAAA==.Walelson:BAAALgADCgcJBAAAAA==.Walla:BAAALgAECgIJAgABLgAECgMJBAADAAAAAA==.Wantoo:BAAALgAECgIJAQAAAA==.Warriorlobo:BAAALgAECgYJCgAAAA==.Warvision:BAAALgAECgQJBgAAAA==.Watchthis:BAAALgAECgMJBAAAAA==.',
Wi='Wildfang:BAAALgAECgcJEAAAAA==.Wildside:BAAALgAECgcJAwAAAA==.',
Wu='Wulffgar:BAAALgADCgcJCQAAAA==.',
Xa='Xandronys:BAAALgADCgYJCQAAAA==.Xanne:BAAALgADCgYJBgAAAA==.',
Xe='Xebec:BAAALgAECgEJAQAAAA==.Xenie:BAAALgAECgQJCAAAAA==.',
Xi='Xioran:BAAALgADCgMJAwAAAA==.',
Xy='Xyra:BAAALgADCgEJAQAAAA==.',
Ye='Yeet:BAAALgAECggJEgAAAA==.',
Yt='Ytterli:BAAALgADCgkJCgAAAA==.',
Za='Zaethas:BAAALgAECgEJAQAAAA==.Zagdakka:BAAALgAECgYJDwAAAA==.Zalandra:BAAALgADCggJCgAAAA==.Zalckar:BAAALgAECggJEwAAAA==.Zavar:BAAALgAECgUJBwAAAA==.',
Ze='Zeeva:BAAALgAECgMJBQAAAA==.Zendead:BAAALgAECggJEwAAAA==.',
Zi='Zionspartan:BAAALgAECgYJDwAAAA==.',
Zo='Zoology:BAAALgAECgYJDQAAAA==.',
Zu='Zugzugshaman:BAABLgAECn8XAAQKAAcJDhWzCgCRAQAKAAcJDhWzCgCRAQAPAAQJrwN7bgCJAAAaAAEJYQBNDwAcAAAAAA==.',
['Ço']='Çoldædheart:BAAALgADCgkJDgAAAA==.',
['Ðø']='Ðøøm:BAAALgADCgEJAQAAAA==.',
['Ñe']='Ñeh:BAAALgAECgYJEQAAAA==.',
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

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

local lookup = {'Monk-Windwalker','Mage-Frost','Unknown-Unknown','Druid-Restoration','Warrior-Fury','Shaman-Elemental','Shaman-Restoration','Priest-Shadow','Paladin-Retribution','Monk-Brewmaster','Hunter-BeastMastery','DeathKnight-Unholy','DeathKnight-Blood','Warlock-Demonology','Warlock-Destruction','Shaman-Enhancement','Warrior-Arms','DemonHunter-Devourer','Priest-Discipline','Priest-Holy','Evoker-Devastation','Evoker-Augmentation','Druid-Guardian','Warlock-Affliction','Mage-Fire','Mage-Arcane','Druid-Balance','Rogue-Subtlety','Hunter-Marksmanship','Hunter-Survival','Rogue-Outlaw','Druid-Feral','Paladin-Holy','Evoker-Preservation','Warrior-Protection','DemonHunter-Havoc',}
local provider = {region='US',realm='GrizzlyHills',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Abramz:BAAALgADCgMJAwAAAA==.',
Ad='Adely:BAAALgAECgEJAQAAAA==.Adelymon:BAAALgAECgQJCAAAAA==.Adelymonk:BAAALgADCgIJAgAAAA==.Adrahil:BAAALgADCgIJAgAAAA==.',
Ae='Aeonra:BAAALgADCgEJAQAAAA==.',
Ag='Agronak:BAAALgAECgQJBgAAAA==.',
Al='Aldan:BAAALgADCgMJAwAAAA==.Aldazen:BAABLgAECn8lAAIBAAgJhCIDAQCFAgABAAgJhCIDAQCFAgAAAA==.Alenara:BAAALgAECgIJAwABLgAECggJFQACALsFAA==.Aletheìa:BAAALgAECgEJAQAAAA==.Alyssandra:BAAALgAECgUJCAAAAA==.',
Am='Amarella:BAAALgAECgYJDAAAAA==.Amarrite:BAAALgADCgkJGwAAAA==.Ammalane:BAAALgADCgkJDQABLgADCgkJGwADAAAAAA==.Amunzo:BAAALgAECgEJAQABLgAECgUJBgADAAAAAA==.',
An='Angyrolaj:BAAALgAECgQJCgAAAA==.',
Aq='Aquadora:BAAALgADCgMJAwAAAA==.',
Ar='Arangarr:BAABLgAECn8fAAIEAAgJ3xsYBgATAgAEAAgJ3xsYBgATAgAAAA==.Arcin:BAAALgADCgEJAQAAAA==.Areyana:BAAALgAECgIJAwAAAA==.Areyoudead:BAAALgAECgQJBAAAAA==.Arkand:BAAALgADCgUJBAAAAA==.Arkandra:BAAALgAECgEJAQAAAA==.Arkara:BAAALgADCgEJAQAAAA==.Arrietty:BAAALgAECgUJCAAAAA==.Arthues:BAAALgADCgcJBwAAAA==.Arthâs:BAAALgADCgUJBQAAAA==.Arumathe:BAAALgAECggJDgAAAA==.',
As='Asura:BAABLgAECn8aAAIFAAgJ5yHiCAAeAwAFAAgJ5yHiCAAeAwAAAA==.',
Au='Aurelian:BAAALgAECgEJAgAAAA==.',
Az='Az:BAAALgAECgYJCwAAAA==.Azeriall:BAABLgAECn8gAAMGAAgJ6ggODAA6AQAGAAgJ6ggODAA6AQAHAAQJSgFdhgB7AAAAAA==.Azráèl:BAAALgADCgMJAwAAAA==.',
Ba='Babyboom:BAAALgADCgIJAgAAAA==.Baconhammr:BAAALgAECgQJBQAAAA==.Badazmf:BAAALgADCgcJDAABLgAECggJFgAIACofAA==.Baddream:BAAALgAECgMJAwAAAA==.Balenciagosa:BAAALgADCgUJBQABLgAECggJFQACALsFAA==.Banshiï:BAAALgAECgYJDgAAAA==.Bax:BAAALgADCgIJAgAAAA==.Baxar:BAAALgAECgIJAgAAAA==.',
Bb='Bbd:BAAALgAECggJBgABLgAECgYJDQADAAAAAA==.',
Be='Beeftard:BAAALgAECgcJEwAAAA==.Bellavix:BAAALgADCgMJBAAAAA==.Benafflic:BAAALgADCgYJBwABLgADCgYJEwADAAAAAA==.Berserrk:BAAALgADCgYJBgAAAA==.Bershale:BAAALgAECgEJAQAAAA==.',
Bi='Bifficus:BAAALgAECgIJAwAAAA==.Big:BAAALgADCgEJAQAAAA==.',
Bl='Blackscorn:BAAALgADCgEJAQAAAA==.Blackthôrne:BAAALgADCgQJBAAAAA==.Blucki:BAAALgAECgYJEgAAAA==.',
Bo='Bobfu:BAAALgADCgYJCAAAAA==.',
Br='Brieze:BAAALgADCgIJAgAAAA==.Brige:BAAALgAECgYJBgAAAA==.Brightstar:BAAALgADCgEJAQAAAA==.Brimaz:BAAALgADCgEJAQAAAA==.',
Bu='Buhhead:BAAALgADCgUJBgAAAA==.Bunana:BAAALgADCgEJAQAAAA==.Bunbear:BAAALgAECgIJAgAAAA==.Bunette:BAAALgADCgEJAQAAAA==.',
Bw='Bwamsamdi:BAAALgADCgYJBgAAAA==.',
By='Byzantium:BAAALgAECgQJCAAAAA==.',
['Bô']='Bônebeard:BAAALgAECgEJAQAAAA==.',
Ca='Cabledryer:BAAALgAECgQJEAAAAA==.Caelidpackx:BAAALgADCgYJBwAAAA==.Caluu:BAAALgADCgEJAQAAAA==.Carnry:BAAALgADCgQJBAAAAA==.Catboy:BAABLgAECn8WAAICAAcJMxUspgCMAQACAAcJMxUspgCMAQAAAA==.Catnips:BAABLgAECn8ZAAIJAAgJzhf5CgDgAQAJAAgJzhf5CgDgAQAAAA==.',
Ch='Chanaranach:BAAALgAECgYJCgAAAA==.Cheelo:BAAALgAECgYJCgAAAA==.Chknnugget:BAAALgAECgIJBAAAAA==.Chowpally:BAAALgAECgUJDQABLgAECgYJBwADAAAAAA==.Chromatic:BAAALgAECgUJDAAAAA==.',
Ci='Cindrethresh:BAAALgAECgEJAQAAAA==.',
Co='Coffeeblak:BAAALgAECggJEgAAAA==.Coldstorm:BAAALgAECgYJCgAAAA==.Compensating:BAAALgADCgYJBgAAAA==.Connor:BAAALgADCgcJBwAAAA==.Connsumption:BAAALgAECgYJCgAAAA==.Corrine:BAAALgADCgQJBwAAAA==.',
Cr='Crazybatt:BAAALgAECgMJAwAAAA==.Crypt:BAAALgAECgYJCwAAAA==.',
Cu='Cuckchairpov:BAABLgAECn8jAAMBAAgJgx1jCgDSAgABAAgJeB1jCgDSAgAKAAgJhAlcCABxAQAAAA==.',
Cy='Cynderleena:BAAALgAECgQJBAAAAA==.Cynyia:BAABLgAECn8gAAILAAgJWBJFCgDFAQALAAgJWBJFCgDFAQAAAA==.',
Cz='Czk:BAAALgADCgEJAgABLgAECggJEgADAAAAAA==.',
Da='Daddyelessar:BAAALgAECgIJAwAAAA==.Dafattyup:BAAALgAECgYJEgAAAA==.Dagon:BAAALgAECgMJAwAAAA==.Dakotarain:BAAALgADCgIJAgAAAA==.Dalerontwo:BAAALgADCgEJAQAAAA==.Dayrun:BAAALgAECgUJCgAAAA==.',
De='Deathturtle:BAABLgAECn8WAAIMAAYJohL1jgBiAQAMAAYJohL1jgBiAQAAAA==.Deavaos:BAAALgADCgkJCwAAAA==.Dedmartigan:BAAALgADCgUJBQAAAA==.Deeanndra:BAAALgAECgcJBQAAAA==.Deevz:BAAALgADCgcJBwAAAA==.Demiz:BAABLgAECn8WAAIHAAYJFROhQgB2AQAHAAYJFROhQgB2AQAAAA==.Deredris:BAAALgAECgQJBAABLgAECgYJCgADAAAAAA==.Dertka:BAAALgAECgQJBgAAAA==.',
Di='Discodruid:BAAALgAECgMJCgAAAA==.Dishsoap:BAAALgADCgYJBgABLgAFFAMJBQAFAF0OAA==.Dixie:BAAALgAECgEJAQAAAA==.',
Do='Dommy:BAAALgAECgEJAQABLgAECgcJGwAKAMsmAA==.Donham:BAACLgAFFH8KAAMMAAUJXBjkEwBSAQAMAAQJXBjkEwBSAQANAAEJAAAyEwBZAAAuAAQKfx0AAgwACAnLHzQeAMsCAAwACAnLHzQeAMsCAAAA.Dorkimedes:BAAALgAECgQJCQAAAA==.Dottie:BAABLgAECn8gAAMOAAgJIhAmDgCiAQAOAAgJqg4mDgCiAQAPAAcJJQ83FwCQAQAAAA==.',
Dr='Draelesh:BAAALgAECgUJDgAAAA==.Draenk:BAAALgADCgUJBQAAAA==.Dragún:BAAALgAECgYJCwAAAA==.Drakari:BAAALgADCgYJBgAAAA==.Drewit:BAAALgAECgYJEAAAAA==.',
Du='Ducan:BAAALgADCgQJBwAAAA==.Duskmane:BAAALgAECgIJAgAAAA==.',
Dw='Dwadler:BAAALgAECgMJBgAAAA==.',
Dy='Dyrkonian:BAAALgADCgkJDwAAAA==.',
Ei='Eireann:BAAALgADCgcJCQAAAA==.',
El='Elerrak:BAAALgAECgEJAQABLgAFFAUJCQAQAF0ZAA==.Elindalia:BAAALgAECgMJAwAAAA==.',
Em='Emberash:BAAALgADCgYJBgAAAA==.Embre:BAAALgAECgUJCgAAAA==.Emorri:BAAALgAECgYJBgAAAA==.Empyrea:BAAALgAECgQJBQAAAA==.',
Er='Eraina:BAAALgADCgIJAgAAAA==.Ericles:BAABLgAECn8YAAMRAAYJvR+nAgCqAQARAAYJvR+nAgCqAQAFAAIJlAVQlwBkAAAAAA==.Erys:BAAALgAECgIJAwAAAA==.Erébus:BAABLgAECn8gAAISAAgJmxoSCQDiAQASAAgJmxoSCQDiAQAAAA==.',
Ev='Ev:BAAALgAECgQJBAAAAA==.Evlpotato:BAABLgAECn8WAAQIAAgJKh81IwC9AQAIAAUJlSA1IwC9AQATAAQJhxTtEACZAAAUAAEJlAc+fwAzAAAAAA==.Evojak:BAAALgAECgMJAwAAAA==.',
Fa='Faevelia:BAAALgADCgMJAwAAAA==.Fairaday:BAABLgAECn8VAAILAAYJEghmagApAQALAAYJEghmagApAQAAAA==.Fanshen:BAAALgADCgkJGQAAAA==.Faxqueenmage:BAAALgAECgYJCgAAAA==.',
Fe='Felador:BAAALgADCgUJCAAAAA==.Feldo:BAAALgAECgMJAwAAAA==.Felmès:BAAALgADCgYJBgABLgAECggJFQACALsFAA==.Fennec:BAAALgAECgUJDAAAAA==.Feralarak:BAAALgAECgQJBAABLgAFFAUJCQAQAF0ZAA==.',
Fi='Firebrandd:BAACLgAFFH8LAAMVAAQJdx0eAgBtAQAVAAQJdx0eAgBtAQAWAAEJ5A75IABOAAAuAAQKfycAAxUACAkLI18CAA8DABUACAmpIV8CAA8DABYABwneHdAPAHsCAAAA.Fizehbubbleh:BAEALgADCgEJAQABLgAECggJGwAGANsaAA==.Fizehtotems:BAEBLgAECn8bAAIGAAgJ2xrvBADRAQAGAAgJ2xrvBADRAQAAAA==.',
Fl='Fleshoracle:BAAALgAECgMJAwAAAA==.Fluctuates:BAAALgAECgQJCAAAAA==.',
Fo='Foron:BAAALgAECgIJAgAAAA==.',
Fr='Frankkastle:BAAALgAECgYJDQAAAA==.Frazelia:BAAALgADCggJCQABLgAECgYJEAADAAAAAA==.Fribble:BAAALgAECgUJBQABLgAECgUJDgADAAAAAA==.Froggierlynx:BAAALgAECgcJEgAAAA==.Froznfate:BAAALgAECgYJDwAAAA==.Fryes:BAAALgAECgcJBAAAAA==.',
Fu='Fuzziebutt:BAAALgADCgEJAQAAAA==.',
Fy='Fyrelady:BAAALgADCgQJBgABLgADCgcJEgADAAAAAA==.Fyrestone:BAAALgADCgcJEgAAAA==.',
['Fæ']='Fæder:BAAALgADCgYJBgAAAA==.',
Ga='Gabarnak:BAAALgADCgIJAgABLgAECgMJBgADAAAAAA==.Galencharred:BAAALgAECgQJBwAAAA==.Garagon:BAAALgAECgUJDgAAAA==.Gauss:BAAALgAECgUJDgAAAA==.Gaîîa:BAABLgAECn8cAAILAAgJBBpOCADkAQALAAgJBBpOCADkAQAAAA==.',
Ge='Gerva:BAAALgAECgUJCwAAAA==.',
Gh='Ghlain:BAAALgAECgMJAwAAAA==.Ghorfindor:BAAALgAECgQJCgAAAA==.Ghostlybrew:BAACLgAFFH8PAAIKAAUJAx3kBACHAQAKAAUJAx3kBACHAQAuAAQKfxYAAgoACAmoH94TAHECAAoACAmoH94TAHECAAAA.',
Gi='Gigastorm:BAAALgADCgIJAQAAAA==.Gilas:BAAALgAECgQJBwAAAA==.',
Gl='Glaivemstake:BAAALgADCgcJBwAAAA==.',
Gn='Gnik:BAAALgAECgYJCgAAAA==.',
Gr='Graahak:BAAALgADCgMJAwAAAA==.Graydenton:BAAALgAECgkJCQABLgAECgYJBgADAAAAAA==.Gruuven:BAAALgADCgUJBwAAAA==.',
Gu='Gutmtmon:BAAALgAECgMJBgAAAA==.',
Gw='Gwenivive:BAAALgAECgYJCgAAAA==.',
['Gí']='Gízmo:BAAALgADCgUJBQAAAA==.',
Ha='Haenus:BAAALgAECggJEgAAAA==.Harrynear:BAAALgADCgMJAwABLgAECgQJCgADAAAAAA==.Haunt:BAAALgADCgcJDgAAAA==.Havark:BAAALgAECgMJAwAAAA==.',
He='Healbilly:BAAALgADCgEJAQAAAA==.Hellzknîght:BAAALgAECgUJCQAAAA==.',
Ho='Holek:BAAALgAECgUJBQAAAA==.Holgy:BAACLgAFFH8RAAIXAAUJlh92AAB3AQAXAAUJlh92AAB3AQAuAAQKfyAAAhcACQmUIkwBAEkDABcACQmUIkwBAEkDAAAA.Holybeard:BAABLgAECn8aAAIJAAcJ2xaYTQD6AQAJAAcJ2xaYTQD6AQAAAA==.Hooks:BAAALgADCggJEgAAAA==.',
Hu='Hunterturtle:BAAALgADCgUJBQAAAA==.',
Ic='Icia:BAAALgAECgEJAQAAAA==.',
Id='Idontmiss:BAAALgAECgIJBQAAAA==.',
Il='Ilickboody:BAAALgADCgQJBAAAAA==.Illustra:BAAALgAECgQJBAABLgAECggJFQACALsFAA==.',
Im='Imcaldo:BAAALgADCgYJBgAAAA==.Imcaldoo:BAAALgADCgUJCgAAAA==.',
In='Interrupt:BAAALgAECgUJDQAAAA==.',
Ir='Irox:BAAALgADCgMJAwAAAA==.',
Is='Isaic:BAAALgADCgEJAQAAAA==.Iseila:BAAALgAECggJDwAAAA==.Isevio:BAAALgAECgMJBgAAAA==.',
It='Ithorus:BAAALgAECgQJBgAAAA==.',
Ja='Jaadb:BAAALgADCgMJBAAAAA==.Jaadd:BAAALgAECgIJAgAAAA==.Jaadi:BAAALgAECgIJAwAAAA==.Jaata:BAAALgADCgcJEAAAAA==.Jamien:BAAALgAECgYJEwAAAA==.Jasnos:BAAALgAECgUJCAAAAA==.',
Jd='Jdk:BAAALgAECgUJBwAAAA==.',
Je='Jelf:BAAALgADCgcJBwAAAA==.Jenzing:BAABLgAECn8VAAMOAAgJqh0JKwBjAgAOAAcJqh0JKwBjAgAYAAEJAACrIwBjAAAAAA==.Jessemyn:BAAALgADCgMJAQAAAA==.',
Jh='Jholy:BAAALgADCggJCAAAAA==.',
Jo='Jobokenhones:BAAALgAECgYJDwAAAA==.Johadgan:BAAALgADCgEJAQAAAA==.',
Jp='Jproudmore:BAAALgADCgUJBQAAAA==.',
Js='Jsberg:BAAALgAECgUJDgAAAA==.',
Ka='Kaathe:BAABLgAECn8hAAMCAAYJGx70hADHAQACAAYJGx70hADHAQAZAAEJjhqYDwA4AAAAAA==.Kadance:BAAALgAECgIJAwAAAA==.Kaidiis:BAAALgAECgYJDgAAAA==.Kaido:BAAALgADCgQJBAAAAA==.Kalder:BAAALgADCgcJBwAAAA==.Karbonn:BAAALgAECgIJAwAAAA==.Kay:BAAALgAECgcJBwAAAA==.Kazeraz:BAAALgADCgEJAQAAAA==.',
Ke='Kegbreaker:BAABLgAECn8VAAIUAAYJVAglDwD+AAAUAAYJVAglDwD+AAAAAA==.',
Kh='Khanas:BAAALgAECgIJAwAAAA==.Kheru:BAAALgADCgcJCAAAAA==.Khoan:BAAALgAECgYJCgAAAA==.',
Ki='Kimbustible:BAABLgAECn8jAAICAAgJlRypNACgAgACAAgJlRypNACgAgAAAA==.Kimchi:BAAALgAECgcJDAABLgAECggJIwACAJUcAA==.',
Kn='Knockknocko:BAAALgAECgQJBgAAAA==.',
Ko='Kobir:BAAALgADCgEJAQAAAA==.Komodostyle:BAAALgAECgYJDQAAAA==.Koobideh:BAAALgADCgEJAQAAAA==.',
Kr='Kriddler:BAAALgADCgQJBAAAAA==.Krisarugala:BAAALgAECgYJDAAAAA==.',
Ku='Kujoluvsmilf:BAAALgAECgUJBQAAAA==.Kunuku:BAAALgADCgUJBQAAAA==.Kurash:BAAALgADCgcJBwAAAA==.Kurion:BAAALgAECgkJAQAAAA==.Kurogami:BAAALgADCgUJBQAAAA==.',
Ky='Kylesxmom:BAABLgAECn8gAAMMAAgJJRuBDgCmAQAMAAcJnBuBDgCmAQANAAcJiRWrIQA1AQAAAA==.Kymal:BAABLgAECn8gAAISAAgJGRMnFABcAQASAAgJGRMnFABcAQAAAA==.Kymbria:BAAALgADCgUJCAAAAA==.Kymora:BAAALgADCgcJBwAAAA==.Kyndrissa:BAAALgADCgUJBQAAAA==.',
['Kë']='Këy:BAABLgAECn8fAAIMAAgJoxqJLACGAgAMAAgJoxqJLACGAgAAAA==.',
La='Latrice:BAACLgAFFH8PAAICAAUJbhgAGQBmAQACAAUJbhgAGQBmAQAuAAQKfyAAAwIACQkAI9gJAHYDAAIACQkAI9gJAHYDABoAAQltGNwYAFEAAAAA.Lavynder:BAABLgAECn8UAAISAAcJGhcOWgCTAQASAAcJGhcOWgCTAQAAAA==.Laërtes:BAAALgAECgMJAwAAAA==.',
Le='Leiamirage:BAAALgAECgUJBQAAAA==.Leviscus:BAAALgADCgkJGgAAAA==.',
Li='Lifetap:BAAALgADCgMJAwAAAA==.Lightbàne:BAAALgAECgQJBAAAAA==.Lightningrod:BAAALgAECgYJBgAAAA==.Lildruidz:BAAALgAECgQJBAAAAA==.Lithedra:BAAALgADCgcJDwAAAA==.',
Lu='Lucavi:BAAALgAECgMJAwAAAA==.Lucyvar:BAAALgADCgEJAQAAAA==.Luke:BAAALgADCgUJBwAAAA==.Luma:BAAALgAECgIJAgAAAA==.Luther:BAABLgAECn8XAAIKAAkJNw9cJQDYAQAKAAkJNw9cJQDYAQAAAA==.',
Ly='Lyla:BAAALgADCgQJBgAAAA==.',
Ma='Malríus:BAAALgAECgQJEQAAAA==.Manales:BAAALgAECgcJBgAAAA==.Marhukai:BAAALgAECgYJDgAAAA==.Marotal:BAAALgAECgUJCwAAAA==.Martysparty:BAAALgAECgYJEwAAAA==.Mavaena:BAAALgAECgEJAQAAAA==.Mavrane:BAAALgADCgEJAgAAAA==.',
Me='Meashakegs:BAAALgAECgQJBAAAAA==.Mechaboomer:BAAALgAECgUJDQAAAA==.Megafire:BAAALgADCgMJAwAAAA==.Melcanthet:BAAALgADCggJCAAAAA==.Mellowrock:BAAALgAECgUJBgAAAA==.',
Mi='Mickhaggis:BAAALgADCgIJAgAAAA==.Micktarogar:BAAALgAECgcJEwAAAA==.Mickwutang:BAAALgADCgMJAwAAAA==.Miklaga:BAAALgAECgEJAQAAAA==.Milince:BAAALgADCgMJAgAAAA==.Minikloon:BAAALgAECgUJCAAAAA==.Minphoria:BAAALgADCgQJBgAAAA==.Missylock:BAAALgADCgYJBgAAAA==.Mistilinn:BAAALgAECgYJEQAAAA==.Miyri:BAAALgADCgYJBgABLgAECgIJAgADAAAAAA==.',
Mo='Mollyporph:BAAALgADCgYJCAAAAA==.Monoco:BAAALgAECgQJBwAAAA==.Moopandax:BAACLgAFFH8GAAIbAAMJsxE2DgD8AAAbAAMJsxE2DgD8AAAuAAQKfxwAAhsACQnAHUoFAEoDABsACQnAHUoFAEoDAAEuAAUUBAkGABsAvRMA.Mortrum:BAAALgADCgQJBAAAAA==.Moxestime:BAAALgAECgEJAgAAAA==.Moxsdeaths:BAAALgADCgcJBwAAAA==.',
Mu='Mushaboom:BAAALgAECgIJAwAAAA==.Muzzler:BAABLgAECn8cAAICAAgJTB3hNQCcAgACAAgJTB3hNQCcAgAAAA==.',
My='Myeyes:BAAALgADCgEJAQAAAA==.Mylinkah:BAAALgADCgQJBAAAAA==.Mynamefizz:BAEALgADCgMJAwABLgAECggJGwAGANsaAA==.Myotonic:BAAALgADCgQJBAAAAA==.Mythlok:BAAALgAECgMJAwAAAA==.Mythreiel:BAAALgAECgEJAQAAAA==.Mythykal:BAAALgAECgIJAgAAAA==.',
Na='Nadis:BAEALgAECgIJAwAAAA==.Narcessa:BAAALgADCgQJBAAAAA==.Nawk:BAAALgADCgcJBwAAAA==.',
Ne='Nennerb:BAAALgADCgQJBAAAAA==.',
Ni='Nicola:BAAALgAECgQJBQAAAA==.Nightxwish:BAAALgAECgUJCAAAAA==.Niranye:BAAALgADCgEJAQAAAA==.',
No='Noisemarine:BAAALgAECgIJAwAAAA==.Nokk:BAAALgADCgEJAQAAAA==.Nokkco:BAAALgAECgEJAQAAAA==.Northspirit:BAAALgAECgMJBQAAAA==.',
Nu='Nuit:BAAALgADCgUJBQABLgAECgYJCwADAAAAAA==.',
Ny='Nyarlothep:BAAALgADCgcJFQAAAA==.',
Oa='Oakenshièld:BAAALgADCgQJBgAAAA==.',
Od='Odindh:BAAALgAECgIJBAAAAA==.Odins:BAAALgADCgEJAQABLgAECgIJBAADAAAAAA==.',
Oh='Ohwhelp:BAAALgAECgMJBAABLgAFFAUJDAAbAEMlAA==.Ohyikers:BAACLgAFFH8MAAIbAAUJQyWHAADAAQAbAAUJQyWHAADAAQAuAAQKfyEAAhsACAl3ISwGADYDABsACAl3ISwGADYDAAAA.',
Ok='Oken:BAAALgADCgUJBQAAAA==.',
Om='Om:BAAALgADCgMJAwAAAA==.',
Pa='Pallek:BAAALgADCgIJAgABLgAECgUJBQADAAAAAA==.Palli:BAAALgAECgUJDgAAAA==.Paogao:BAAALgAECgEJAQAAAA==.Parry:BAAALgADCgQJBAAAAA==.Pasghetti:BAAALgADCgMJAwAAAA==.Pasta:BAABLgAECn8ZAAIcAAcJTxvkBwBfAQAcAAcJTxvkBwBfAQAAAA==.',
Pe='Pewpewbite:BAAALgAECgIJAwAAAA==.',
Ph='Phantomarrow:BAACLgAFFH8IAAMdAAUJeQuGAwDvAAAdAAUJHguGAwDvAAALAAEJzQEKGQBFAAAuAAQKfxUABAsABgk8IAhOAH8BAAsABgkbHghOAH8BAB0ABQmzGXBCAE0BAB4AAQkAACQWAAAAAAAA.Phatcow:BAABLgAECn8gAAMHAAgJthmEFwBaAgAHAAgJthmEFwBaAgAQAAcJiRBgAwCZAQAAAA==.Phoseidon:BAAALgADCgYJCAAAAA==.Phude:BAABLgAECn8hAAIJAAgJBhnTOABAAgAJAAgJBhnTOABAAgAAAA==.',
Pi='Pinch:BAAALgAECgMJAwAAAA==.',
Po='Poohynok:BAABLgAECn8cAAICAAgJ5SMIAgDIAgACAAgJ5SMIAgDIAgAAAA==.',
Pu='Pukefeast:BAAALgAECgQJBgAAAA==.',
Py='Pyramys:BAACLgAFFH8JAAIcAAMJiByDBAAjAQAcAAMJiByDBAAjAQAuAAQKfyEAAhwACAm3IAARAJoCABwACAm3IAARAJoCAAAA.',
['Pè']='Pèrce:BAAALgAECgIJAwAAAA==.',
Qu='Quepaoka:BAAALgADCgIJAgAAAA==.',
Ra='Raklem:BAAALgADCgUJBQABLgAECgYJCgADAAAAAA==.Ramble:BAAALgADCgMJAwABLgAECgQJBgADAAAAAA==.Ramstein:BAAALgADCgcJBwAAAA==.Raphînîty:BAAALgADCgMJBQAAAA==.Rashari:BAAALgADCgYJCAAAAA==.Razgrizz:BAAALgADCgkJGAAAAA==.',
Re='Retro:BAAALgAECgIJAwAAAA==.Revelatus:BAAALgAECgQJBgAAAA==.Reythanas:BAAALgAECgQJBwAAAA==.Rezzin:BAAALgAECgEJAQAAAA==.',
Ri='Rileyann:BAAALgAECgYJEgAAAA==.',
Ro='Roozer:BAAALgADCgkJHQAAAA==.',
['Rå']='Råphå:BAAALgAECgMJBAAAAA==.',
Sa='Saelyria:BAAALgAECgIJAgAAAA==.Saga:BAAALgADCgUJBQAAAA==.Sagethepally:BAAALgAECgcJAgAAAA==.Saintfail:BAAALgAECgYJBwAAAA==.Salero:BAAALgADCgIJAQAAAA==.Sandiera:BAABLgAECn8VAAMCAAgJuwVEqgCGAQACAAgJuwVEqgCGAQAaAAMJPAOnFwBcAAAAAA==.Saxtön:BAAALgADCggJEwAAAA==.',
Sc='Scoreboard:BAACLgAFFH8IAAIfAAQJER5oAACIAQAfAAQJER5oAACIAQAuAAQKfyEAAx8ACQkgJg0AAOsDAB8ACQkgJg0AAOsDABwAAQnwFJRaAE8AAAAA.Scorn:BAAALgAECgQJBwAAAA==.Scottx:BAAALgAECgQJBQAAAA==.',
Se='Sebas:BAAALgADCgcJCAAAAA==.Sedric:BAAALgAECgYJBQAAAA==.Selkz:BAAALgAECgcJDAAAAA==.Selsonblue:BAAALgADCgYJEwAAAA==.Sesskaa:BAAALgAECgQJBgAAAA==.',
Sh='Shadowcursed:BAAALgADCgcJCgAAAA==.Shadowstorm:BAAALgADCgQJBAAAAA==.Shadøws:BAAALgAECgEJAQAAAA==.Shathos:BAAALgADCgEJAQAAAA==.Sheebá:BAAALgADCgYJCwAAAA==.Shishkbob:BAAALgADCgkJCQAAAA==.Shivax:BAAALgAECgQJCQAAAA==.Shünúkh:BAAALgADCgYJBgAAAA==.',
Si='Signal:BAAALgAECgEJAQAAAA==.Sinogad:BAAALgAECggJCAAAAA==.Sinol:BAAALgAECgYJDwABLgAECggJCAADAAAAAA==.Sioux:BAAALgADCgEJAQAAAA==.',
Sk='Skaro:BAAALgAECgIJAwAAAA==.Skyborn:BAAALgAECgIJAwAAAA==.',
Sl='Slay:BAABLgAECn8eAAMbAAcJFh9fBADdAQAbAAcJ5x5fBADdAQAgAAYJZBuLEwB4AQAAAA==.',
Sm='Smokedademon:BAAALgAECgIJAgAAAA==.Smokiebear:BAAALgAECgIJAgAAAA==.Smunkie:BAABLgAECn8bAAIKAAcJyybnAACoAgAKAAcJyybnAACoAgAAAA==.',
Sn='Snickeers:BAAALgAECgEJAQAAAA==.',
So='Somogyi:BAAALgADCgIJAgAAAA==.',
Sp='Spopovich:BAAALgADCgIJAgABLgADCgcJEAADAAAAAA==.',
St='Stinko:BAAALgADCgEJAgAAAA==.Stitchlock:BAAALgAECgIJAgAAAA==.Stitchofevil:BAABLgAECn8WAAQYAAcJuBoEBgACAgAYAAYJUB8EBgACAgAOAAQJmQlKOwCEAAAPAAIJtQ8UYQBMAAAAAA==.Stonedshaman:BAAALgADCgYJBgABLgAECgIJAgADAAAAAA==.Stormhands:BAAALgAECgYJCwAAAA==.Stormhugger:BAAALgAECgUJBwAAAA==.Stoutnholy:BAAALgAECgIJAgAAAA==.Stratichnut:BAAALgAECgUJDgAAAA==.Stromar:BAAALgADCgcJDAAAAA==.Stwampadin:BAAALgAECgcJDgAAAA==.Stwevoker:BAAALgAECgMJAwABLgAECgcJDgADAAAAAA==.Stwonkfu:BAAALgAECgYJBgABLgAECgcJDgADAAAAAA==.',
Su='Sumire:BAAALgADCggJDgABLgAECgYJCgADAAAAAA==.',
Sv='Sveny:BAAALgADCgUJBQAAAA==.',
Sw='Swampert:BAACLgAFFH8FAAIFAAMJXQ5LBgD+AAAFAAMJXQ5LBgD+AAAuAAQKfxsAAgUACQmQGtUMAPACAAUACQmQGtUMAPACAAAA.Swamperting:BAAALgAECgQJBAABLgAFFAMJBQAFAF0OAA==.Swaye:BAABLgAECn8aAAIIAAcJvRFpCwA7AQAIAAcJvRFpCwA7AQAAAA==.Sweetfox:BAAALgADCgMJAwAAAA==.Switched:BAAALgADCgcJBwABLgAECgcJGwAKAMsmAA==.Swizzle:BAAALgADCgUJBgAAAA==.',
Sy='Syllvanas:BAAALgAECgMJAQAAAA==.Sythia:BAAALgAECgEJAQABLgAECgUJCAADAAAAAA==.',
Ta='Taltost:BAAALgAECgQJCAAAAA==.Tantrik:BAAALgADCgEJAQAAAA==.Tartin:BAAALgAECgMJAwAAAA==.Tarv:BAAALgADCgMJAQAAAA==.Tashamirage:BAAALgAECgMJBAAAAA==.Tauriel:BAAALgADCgIJAgAAAA==.',
Te='Teex:BAAALgADCgYJBwAAAA==.Teksuo:BAABLgAECn8hAAIBAAgJjxyLAgAOAgABAAgJjxyLAgAOAgAAAA==.Telamontay:BAAALgADCgcJEgAAAA==.Telferas:BAAALgAECgYJDwABLgAFFAQJCwAVAHcdAA==.Tenithon:BAABLgAECn8dAAIhAAgJSiKCBQAUAwAhAAgJSiKCBQAUAwAAAA==.Tenshenzen:BAAALgADCgYJCAAAAA==.',
Th='Therandis:BAAALgADCgUJBQAAAA==.Thetombo:BAAALgAECgEJAQAAAA==.Thierry:BAAALgADCgUJBQAAAA==.Thierrye:BAAALgAECgYJEAAAAA==.Tholaren:BAAALgAECgUJDQAAAA==.Threed:BAAALgAECgUJBgAAAA==.Threewar:BAAALgAECgIJAgABLgAECgUJBgADAAAAAA==.Thrissa:BAAALgAECgIJAwAAAA==.',
To='Torrque:BAAALgADCgkJCQAAAA==.Totemlicker:BAAALgAECgEJAQAAAA==.',
Tr='Trangon:BAAALgAECgYJDwAAAA==.Traveler:BAAALgADCgEJAQAAAA==.Trillion:BAAALgADCgMJAwAAAA==.',
Tu='Tunzoffun:BAAALgAECgIJAwAAAA==.',
Un='Underbyte:BAAALgADCggJCgAAAA==.Unknownname:BAAALgADCgMJAwAAAA==.',
Ur='Urholiness:BAAALgADCgcJDQAAAA==.',
Va='Vaeleia:BAAALgAECgQJBAAAAA==.Vahnkar:BAAALgADCgQJBwAAAA==.Valentinu:BAAALgADCgcJDwAAAA==.Vaneshk:BAAALgADCgEJAQAAAA==.Varithal:BAABLgAECn8gAAIiAAgJ2B0SAQByAgAiAAgJ2B0SAQByAgABLgABCgYJCQADAAAAAA==.Varri:BAAALgAECgMJBQAAAA==.Vastectomy:BAAALgAECgYJBgAAAA==.',
Ve='Velwing:BAAALgAECgUJBgAAAA==.Venawyn:BAAALgAECgQJCAAAAA==.Verakhaa:BAAALgAECgQJBAAAAA==.',
Vi='Vindfaramaðr:BAAALgAECgYJDwAAAA==.Vixin:BAAALgAECgIJAgAAAA==.',
Vo='Voidsaack:BAAALgADCgcJDQAAAA==.Volfguar:BAAALgAECgQJAQAAAA==.Vortan:BAAALgAECgIJAwAAAA==.',
Vr='Vreya:BAAALgADCgUJBQABLgADCgkJGAADAAAAAA==.',
Vy='Vynthus:BAAALgADCgkJEAAAAA==.',
['Vä']='Värys:BAAALgAECgEJAQAAAA==.',
Wa='Warhundin:BAEALgAECgUJBQABLgAECggJEwADAAAAAA==.Warwan:BAAALgADCgIJAgAAAA==.Wazzdot:BAAALgADCgUJBQAAAA==.Wazzhunnah:BAAALgAECgYJEQAAAA==.',
We='Werg:BAAALgAECgcJBwABLgAECgkJBwADAAAAAA==.',
Wh='Whatmyname:BAAALgAECgUJDgAAAA==.Whispp:BAAALgAECgYJBQAAAA==.',
Wo='Wonsok:BAAALgAECgYJBwAAAA==.',
Wy='Wyvoker:BAAALgAECgYJDwAAAA==.',
['Wì']='Wìllow:BAAALgADCgIJAgAAAA==.',
['Wÿ']='Wÿm:BAAALgADCgkJCgABLgAECgYJDwADAAAAAA==.',
Xe='Xenorion:BAAALgAECgMJAwAAAA==.Xephora:BAAALgAECgEJAgAAAA==.',
Xu='Xuny:BAAALgAECgEJAQAAAA==.',
Yo='Yordi:BAAALgAECgUJBQAAAA==.',
Yu='Yuzuriha:BAABLgAECn8gAAILAAgJ2iKzAgB0AgALAAgJ2iKzAgB0AgAAAA==.',
Za='Zamaze:BAABLgAECn8cAAIjAAgJ3R4wAQBSAgAjAAgJ3R4wAQBSAgAAAA==.Zannah:BAAALgADCgcJEAAAAA==.',
Ze='Zeekielle:BAEALgAECggJEwAAAA==.Zenius:BAAALgAECgMJAwAAAA==.Zerithrielle:BAABLgAECn8XAAIkAAcJpBShBgBMAQAkAAcJpBShBgBMAQAAAA==.',
Zi='Zippii:BAAALgAECgEJAQAAAA==.Zipy:BAAALgAECgUJDgAAAA==.',
Zo='Zof:BAAALgAECgYJBwAAAA==.',
Zu='Zugtag:BAABLgAECn8VAAIMAAYJJBxyEQCIAQAMAAYJJBxyEQCIAQAAAA==.',
Zy='Zyllo:BAAALgADCgkJHgAAAA==.',
['Zá']='Závier:BAAALgAECgUJBQAAAA==.',
['Äe']='Äemond:BAAALgADCgMJAwAAAA==.',
['Ål']='Ålïce:BAABLgAECn8iAAIJAAcJaxZrFAB+AQAJAAcJaxZrFAB+AQAAAA==.',
['Ëd']='Ëdward:BAAALgADCgcJCgABLgAECgMJAwADAAAAAA==.',
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

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

local lookup = {'Unknown-Unknown','Warrior-Fury','Paladin-Holy','Rogue-Subtlety','Rogue-Assassination','Paladin-Protection','Paladin-Retribution','Druid-Guardian','Mage-Frost','Druid-Restoration','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','DeathKnight-Unholy','Priest-Discipline','Shaman-Restoration','Hunter-BeastMastery','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','Druid-Balance','Warrior-Arms','Monk-Windwalker','Monk-Mistweaver','DemonHunter-Devourer','DemonHunter-Havoc','Hunter-Marksmanship','Priest-Holy','DeathKnight-Blood',}
local provider = {region='US',realm='KhazModan',name='US',type='weekly',zone=46,date='2026-04-24',data={Ad='Ader:BAAALgADCgkJDQAAAA==.',
Ae='Aeryhnn:BAAALgADCgMJAwABLgADCgkJHwABAAAAAA==.',
Al='Alaanda:BAAALgADCgkJCQAAAA==.Alandrysong:BAAALgAECgUJEAAAAA==.Alexandre:BAAALgAECgUJDQAAAA==.Aliandes:BAAALgADCgIJAgAAAA==.Allasia:BAAALgAECgYJDwAAAA==.Aloysius:BAAALgADCgEJAQAAAA==.Alton:BAAALgAECgUJDQAAAA==.',
Am='Amoonsia:BAAALgADCgIJAgAAAA==.',
An='Anamanahebo:BAAALgAECgEJAQAAAA==.',
Ap='Aphroditee:BAAALgAECgIJAwAAAA==.Apollyonn:BAAALgAECgEJAgAAAA==.Apostriss:BAAALgAECgEJAQAAAA==.',
Aq='Aquafresh:BAAALgAECggJEAAAAA==.',
Ar='Arisel:BAAALgAECgQJCgABLgAECgcJDwABAAAAAA==.Aristia:BAAALgAECgMJAwABLgAECgYJEgABAAAAAA==.Arweni:BAABLgAECn8cAAICAAgJXhGULwDxAQACAAgJXhGULwDxAQAAAA==.',
As='Ashand:BAAALgAECgIJAgAAAA==.Ashhxc:BAAALgAECgIJAgAAAA==.',
At='Atheizt:BAABLgAECn8dAAIDAAcJWSVHCADqAgADAAcJWSVHCADqAgAAAA==.',
Az='Azog:BAAALgAECgIJAgAAAA==.',
Ba='Banedon:BAAALgADCggJCAABLgAECggJHQADAAQXAA==.Baridyn:BAAALgADCgMJBgAAAA==.',
Be='Bearbacked:BAAALgADCggJCgABLgAECgEJAQABAAAAAA==.Beefer:BAAALgADCgYJBgAAAA==.Belagrip:BAAALgAECgMJBAAAAA==.Belashar:BAAALgADCgkJHgABLgAECgMJBAABAAAAAA==.Beytuha:BAAALgAECgQJCwAAAA==.',
Bi='Bigworm:BAAALgADCgYJBgAAAA==.Bingling:BAEALgAECgYJBgAAAA==.',
Bl='Blacken:BAAALgAECgQJBwAAAA==.Blackknife:BAABLgAECn8XAAMEAAYJPhtvJADVAQAEAAYJPhtvJADVAQAFAAEJowYiCwA1AAAAAA==.Blakylightz:BAABLgAECn8fAAMGAAgJxxoECQBGAgAGAAgJxxoECQBGAgAHAAYJcwlougARAQABLgAFFAUJEQAIANUZAA==.Blinker:BAAALgAECgYJEQAAAA==.Bloodynuts:BAAALgAECgEJAQABLgAECggJJAAJANEgAA==.Blurberry:BAAALgAECgYJDAAAAA==.',
Bo='Bobbidobby:BAAALgAECgQJBwABLgAFFAIJBwAKALcFAA==.Bobbidyboo:BAACLgAFFH8HAAIKAAIJtwV/DgBxAAAKAAIJtwV/DgBxAAAuAAQKfyQAAgoACAlcFaU2AM0BAAoACAlcFaU2AM0BAAAA.Bolton:BAAALgADCgYJCgAAAA==.Bonesclone:BAAALgAECgEJAQAAAA==.Boram:BAAALgAECgEJAQAAAA==.Bostonbean:BAAALgAECgYJCwAAAA==.',
Br='Brechnar:BAAALgADCgQJCQAAAA==.Brewshido:BAAALgAECgIJAgAAAA==.Brovar:BAACLgAFFH8FAAIHAAIJeRHIDwCnAAAHAAIJeRHIDwCnAAAuAAQKfyMAAwcACAlQHnQaAMoCAAcACAlQHnQaAMoCAAMABQlgCt1zAKwAAAAA.Brü:BAAALgADCgUJBQAAAA==.',
Bu='Bubbaa:BAABLgAECn8bAAQLAAcJ8QsnDQAXAQALAAcJ8QsnDQAXAQAMAAQJ5QeaOwCOAAANAAEJwwNwQwAoAAAAAA==.Bubblez:BAAALgAECgQJCAAAAA==.Buddydaelf:BAAALgAECgUJEAAAAA==.Bungle:BAAALgADCgEJAQAAAA==.',
By='Byebyetwinks:BAAALgAECgEJAQAAAA==.',
Ca='Caencis:BAAALgADCggJEwAAAA==.Candyman:BAAALgADCgYJDgAAAA==.',
Ce='Celestina:BAAALgADCgkJFgAAAA==.',
Ch='Chameleon:BAAALgADCgIJAgAAAA==.Chillfang:BAABLgAECn8fAAIOAAgJ+R2eNgBcAgAOAAgJ+R2eNgBcAgAAAA==.Chune:BAAALgAECgQJDgAAAA==.Chêster:BAAALgADCgcJEgAAAA==.',
Ci='Circle:BAAALgADCgEJAQAAAA==.',
Cl='Claireity:BAAALgADCgMJAwAAAA==.',
Co='Connor:BAABLgAECn8VAAIPAAcJTBGgBwB0AQAPAAcJTBGgBwB0AQAAAA==.Cooleddown:BAAALgADCgUJBQAAAA==.Corpsebríde:BAAALgAECgYJCQAAAA==.',
Cr='Crosshair:BAAALgADCgEJAgAAAA==.',
Cy='Cygne:BAAALgADCgUJBQABLgADCgYJBgABAAAAAA==.',
['Cê']='Cêlaçane:BAAALgAECgYJCQAAAA==.',
Da='Dacianwolf:BAAALgADCggJDAAAAA==.Daemoni:BAAALgADCgIJAgAAAA==.Daravinius:BAAALgAECgcJDwAAAA==.Dare:BAAALgAECggJDgAAAA==.Darksoulz:BAAALgAECgYJBgAAAA==.Darkvoider:BAAALgADCgYJBgAAAA==.Darrir:BAAALgADCgcJDQABLgAECgUJCgABAAAAAA==.Daveah:BAAALgAECgQJCgAAAA==.Dazarros:BAAALgAECgIJAgAAAA==.',
De='Deadwait:BAAALgADCgUJBQAAAA==.Deathberry:BAAALgAECggJDwAAAA==.Deeg:BAAALgADCgMJBQAAAA==.Dellystia:BAAALgAECgQJBwAAAA==.Delphron:BAAALgADCgkJDAAAAA==.Demoncharge:BAAALgADCgcJBwABLgAECgQJBQABAAAAAA==.Demonclaw:BAAALgADCgMJAwABLgAECgQJBQABAAAAAA==.Demondrake:BAAALgAECgQJBQAAAA==.Demonflayer:BAAALgADCgkJEwABLgAECgQJBQABAAAAAA==.Demonicow:BAAALgAECgEJAQAAAA==.Denaeaa:BAAALgAECgUJBwABLgAFFAIJBQAQAF8MAA==.Devilzkry:BAAALgAECgMJAwAAAA==.Devlina:BAAALgADCgYJBgAAAA==.Dewtdewt:BAAALgADCgEJAQABLgAECgcJFgARAF8dAA==.',
Dh='Dhodge:BAAALgADCgEJAQAAAA==.',
Di='Dinerra:BAAALgADCgcJCAAAAA==.Divinestorm:BAABLgAECn8dAAIDAAgJBBfXBAAYAgADAAgJBBfXBAAYAgAAAA==.',
Dn='Dnyal:BAAALgADCgcJBwAAAA==.',
Do='Doffyy:BAAALgAECgEJAQAAAA==.Dotexe:BAAALgAECgUJDQAAAA==.Dotsy:BAACLgAFFH8GAAMSAAIJahIMBABeAAASAAEJoBYMBABeAAATAAEJNA4RSgBRAAAuAAQKfyQABBIACAmRHa8PANMBABIABgk/Ga8PANMBABMABgkHILxVAMYBABQABQmIGbMOAEUBAAAA.',
Dr='Dragonpower:BAAALgAECgMJBAAAAA==.Drakiir:BAAALgAECgQJCQABLgAECgUJCgABAAAAAA==.Dralkish:BAABLgAECn8kAAIHAAgJahHPXgDHAQAHAAgJahHPXgDHAQAAAA==.Dramore:BAAALgAECgEJAQAAAA==.Drathi:BAAALgADCgcJBwABLgAECgcJEwABAAAAAA==.Dravas:BAAALgAECgQJCgAAAA==.Dressymage:BAAALgAECgUJBwAAAA==.Droxx:BAAALgAECgQJBwAAAA==.Drucilla:BAAALgADCgUJBQAAAA==.Drzark:BAAALgADCgkJFgAAAA==.',
Dw='Dwdog:BAABLgAECn8UAAIUAAYJpA+IAQCBAQAUAAYJpA+IAQCBAQAAAA==.',
['Dà']='Dàthguy:BAABLgAECn8lAAIOAAgJgiRtDQAvAwAOAAgJgiRtDQAvAwAAAA==.',
['Dè']='Dèstruct:BAAALgAECgEJAQAAAA==.',
Ea='Earthgirl:BAAALgAECgQJBAAAAA==.',
Ed='Edaras:BAAALgAECgQJCQAAAA==.',
El='Elennie:BAAALgAECgEJAQAAAA==.Elephantom:BAAALgADCgEJAQAAAA==.Elerion:BAAALgAECgUJCAAAAA==.Elm:BAAALgADCgUJBQAAAA==.Elsianna:BAAALgADCgQJBQAAAA==.',
Em='Emelie:BAAALgAECgEJAQAAAA==.Emmi:BAAALgAECgYJCwAAAA==.',
En='Endeavor:BAAALgADCgUJAwAAAA==.Enyo:BAAALgAECgYJCgAAAA==.',
Er='Erad:BAABLgAECn8YAAIHAAcJ/B7pLwBjAgAHAAcJ/B7pLwBjAgAAAA==.',
Eu='Eurydice:BAAALgAECgYJCAAAAA==.',
Ev='Eviaela:BAAALgADCgcJEQAAAA==.Evilwarden:BAAALgADCgEJAQAAAA==.',
Ex='Exadius:BAAALgADCgIJAgAAAA==.',
Fa='Faith:BAAALgADCgYJBgAAAA==.Falcor:BAABLgAECn8YAAMLAAgJLSH6BwD5AgALAAgJPiD6BwD5AgANAAYJXSFvEQDIAQAAAA==.',
Fe='Fearafawcett:BAAALgADCgMJBAAAAA==.Fearmyhunter:BAAALgAECgYJAwAAAA==.Fervid:BAAALgADCgMJAwAAAA==.Feylen:BAAALgAECgcJEAAAAA==.',
Fi='Fido:BAAALgAECgQJCgAAAA==.Fifthelement:BAAALgAECgUJDQAAAA==.',
Fj='Fjalgeirr:BAAALgAECgUJDQAAAA==.',
Fl='Flockling:BAAALgADCgYJBgAAAA==.',
Fo='Foxymomma:BAAALgAECgYJCwAAAA==.',
Fr='Frey:BAACLgAFFH8HAAIOAAIJUx/eFAC0AAAOAAIJUx/eFAC0AAAuAAQKfyQAAg4ACAn0Iw0XAPECAA4ACAn0Iw0XAPECAAAA.Friarfig:BAAALgADCgMJAwAAAA==.Frothy:BAABLgAECn8YAAMUAAgJjCJZAQDjAgAUAAcJ7SRZAQDjAgATAAMJ6hvOpAAOAQABLgAECggJGQAVAEggAA==.Frßlizzard:BAAALgAECgEJAQAAAA==.',
Fu='Fulgar:BAAALgAECgQJBQAAAA==.Funkdrat:BAAALgAECgYJEAAAAA==.',
Fw='Fwenwir:BAAALgAECgYJEwAAAA==.',
Ga='Galatea:BAAALgADCgYJBgAAAA==.Gandriela:BAAALgADCgEJAQAAAA==.Gankak:BAAALgAECgUJDQAAAA==.',
Ge='Geiste:BAAALgAECgYJCwAAAA==.Geronimoose:BAAALgADCgcJDAABLgAECgUJDQABAAAAAA==.',
Gh='Ghue:BAAALgAECgYJCAAAAA==.',
Gi='Gilalade:BAAALgAECgYJCwAAAA==.',
Gl='Glideslope:BAAALgAECgYJEAAAAA==.Glorbius:BAAALgAECgEJAQAAAA==.',
Gn='Gnowaytodie:BAABLgAECn8eAAIOAAgJhAaTFABuAQAOAAgJhAaTFABuAQAAAA==.',
Go='Gobann:BAAALgADCgcJBwABLgAECgUJDQABAAAAAA==.Gooby:BAAALgAECgQJBAABLgAFFAQJCgADAKUZAA==.Gotwood:BAAALgADCgYJBgAAAA==.',
Gr='Granny:BAAALgAECgYJCQAAAA==.Grimes:BAAALgAECgEJAQAAAA==.Grodin:BAAALgADCgcJBwAAAA==.Grofiest:BAAALgAECgUJDQAAAA==.',
Gu='Guggychan:BAABLgAECn8dAAIWAAgJyiWpAAB/AwAWAAgJyiWpAAB/AwAAAA==.',
['Gô']='Gôö:BAAALgAECgQJBgAAAA==.',
Ha='Hadoken:BAABLgAECn8VAAIXAAgJxApoCgAsAQAXAAgJxApoCgAsAQAAAA==.Haldor:BAABLgAECn8jAAIHAAgJcwwTFACBAQAHAAgJcwwTFACBAQAAAA==.Haohmaru:BAAALgAECgYJCwAAAA==.',
He='Hecæte:BAAALgADCgYJBgAAAA==.Hercdru:BAAALgADCgMJAwAAAA==.Hercgrim:BAAALgAECgIJAgAAAA==.Hercsham:BAAALgADCgQJBAAAAA==.Heunei:BAAALgAECgUJDwAAAA==.',
Ho='Hoffenstauff:BAAALgADCgMJAwAAAA==.Hollowmagi:BAAALgAECgIJAgAAAA==.Holychoc:BAAALgADCgEJAQAAAA==.',
Hu='Huneyhunter:BAAALgAECgQJCwAAAA==.',
Id='Idkhao:BAAALgADCgMJAwAAAA==.',
Il='Illimommy:BAAALgADCggJEgAAAA==.',
Im='Imsocold:BAAALgAECgIJAgAAAA==.',
In='Intern:BAAALgAECgQJCwAAAA==.',
Ir='Irishmonk:BAAALgAECgkJCwAAAA==.',
Is='Isapharra:BAAALgADCgYJBgAAAA==.',
Ja='Jaeksoolie:BAAALgAECgQJBQAAAA==.Jakychanda:BAAALgAECgQJBgAAAA==.Jakyro:BAAALgAECgYJCwAAAA==.Javeech:BAAALgADCgcJDAAAAA==.',
Je='Jeezus:BAAALgADCgYJBgABLgAFFAIJAgABAAAAAA==.',
Jo='Jokinphoenix:BAAALgAECgEJAQABLgAECgYJCwABAAAAAA==.',
Ju='Juudaz:BAAALgAFFAIJAgAAAA==.',
Ka='Kakahna:BAAALgAECgYJCwAAAA==.Kallan:BAAALgAECgMJAwAAAA==.Kamela:BAAALgAECgQJBgAAAA==.Kamilia:BAAALgAECgEJAQAAAA==.Kappy:BAAALgADCgMJAwAAAA==.',
Ke='Kegpoker:BAAALgAECgYJCQAAAA==.Kelgoroth:BAAALgADCgEJAwAAAA==.',
Ki='Kindacold:BAAALgAECgcJCgAAAA==.Kindahot:BAAALgAECgkJBAAAAA==.Kiyara:BAABLgAECn8cAAIRAAgJdAuMEQBxAQARAAgJdAuMEQBxAQAAAA==.Kizaki:BAAALgADCgkJDgABLgAECgUJCQABAAAAAA==.',
Kn='Knowoone:BAABLgAECn8fAAIKAAgJRBSgCQDAAQAKAAgJRBSgCQDAAQAAAA==.',
Ko='Komonaut:BAAALgADCgkJEAAAAA==.Koscihardt:BAAALgAECgcJDwAAAA==.',
Kr='Krelliz:BAABLgAECn8YAAIQAAcJSRBWEAA9AQAQAAcJSRBWEAA9AQAAAA==.Kroctdi:BAAALgADCgYJBgAAAA==.Krolly:BAAALgAECgQJCwAAAA==.Krystar:BAAALgADCgEJAgAAAA==.',
Ku='Kulfig:BAAALgAECgMJAwAAAA==.Kumen:BAAALgAECgYJDwAAAA==.Kungfuwho:BAABLgAECn8eAAMXAAgJQRVuBwBkAQAXAAgJQRVuBwBkAQAYAAEJswN8IwAlAAAAAA==.Kutyou:BAAALgADCgMJAwAAAA==.',
['Kû']='Kûnei:BAAALgAECgMJAwAAAA==.',
La='Laysee:BAAALgADCgkJEwAAAA==.Lazegos:BAAALgADCgUJBQAAAA==.',
Le='Lehiga:BAAALgADCgMJAwAAAA==.Lenaea:BAACLgAFFH8FAAIQAAIJXwxODACFAAAQAAIJXwxODACFAAAuAAQKfx4AAhAACAktGCMjAAwCABAACAktGCMjAAwCAAAA.',
Li='Liesta:BAAALgADCgUJBQAAAA==.Lightrawne:BAABLgAECn8eAAIDAAgJrA5fMgC1AQADAAgJrA5fMgC1AQAAAA==.Liiege:BAAALgAECgUJCgAAAA==.Likeàßoss:BAAALgADCgcJBwAAAA==.Liltotem:BAAALgADCgUJBQAAAA==.Limp:BAAALgAECgEJAQAAAA==.Littleleg:BAAALgADCgMJAwAAAA==.Littlestjeff:BAAALgAECgUJBgAAAA==.',
Lo='Lobø:BAAALgAECgUJDQAAAA==.',
Lu='Luccyy:BAAALgADCgcJCgAAAA==.Lunatyc:BAABLgAECn8VAAIOAAcJJQeSHAA1AQAOAAcJJQeSHAA1AQAAAA==.Lunette:BAAALgADCgcJEwAAAA==.Luçius:BAAALgADCgUJBQAAAA==.',
Ly='Lylacy:BAAALgADCgIJAgAAAA==.',
Ma='Mackenzielyn:BAAALgADCgYJCwAAAA==.Madscience:BAAALgAECgIJAgAAAA==.Magerbrkdown:BAAALgADCgYJBgAAAA==.Magnoliá:BAAALgADCgcJBwAAAA==.Malach:BAAALgAECgYJCwAAAA==.Mammal:BAAALgAECgUJCgAAAA==.Manatee:BAAALgAECgEJAQAAAA==.Marlasinger:BAAALgADCgcJCwAAAA==.Marpesia:BAAALgAECgEJAQAAAA==.Marqfourthre:BAAALgAECgEJAQAAAA==.Maygwyn:BAAALgADCgkJCwAAAA==.',
Me='Medivha:BAAALgAECgEJAQAAAA==.Meechíe:BAAALgADCgcJBwAAAA==.Megaera:BAACLgAFFH8HAAIZAAIJLR6fEgCsAAAZAAIJLR6fEgCsAAAuAAQKfyAAAxkACAm+IvMOAAcDABkACAm+IvMOAAcDABoAAQkeGBVsADoAAAAA.Melar:BAAALgAECgYJDQAAAA==.Mellador:BAAALgADCgYJBgAAAA==.Mentoku:BAAALgADCgcJDgAAAA==.',
Mi='Mihawk:BAAALgADCgUJBQAAAA==.Minjae:BAAALgADCgkJIgABLgAECggJHQATANYSAA==.Mistytouch:BAAALgADCgMJAwAAAA==.',
Mo='Moondemon:BAAALgADCgEJAQAAAA==.Moongrave:BAAALgADCgQJBAAAAA==.Morrìgan:BAAALgAECgUJBwAAAA==.Movack:BAAALgAECgYJDwAAAA==.Moxxnixx:BAAALgAECgEJAQAAAA==.',
Mu='Murderface:BAAALgAECgYJCwAAAA==.Murloch:BAAALgADCgEJAQAAAA==.',
My='Myalison:BAAALgAECgUJDAAAAA==.Mythunran:BAABLgAECn8YAAIbAAcJsA3PBgAHAQAbAAcJsA3PBgAHAQAAAA==.',
Na='Nalandra:BAAALgADCgcJBwABLgAECgQJCQABAAAAAA==.Natash:BAAALgADCgMJBAAAAA==.Nax:BAAALgAECgMJAwAAAA==.',
Ne='Necrofusion:BAAALgADCgEJAQAAAA==.Nerfhammer:BAACLgAFFH8GAAIHAAIJNBhRHwCwAAAHAAIJNBhRHwCwAAAuAAQKfyEAAgcACAlBIgkcAMICAAcACAlBIgkcAMICAAAA.Nessalove:BAACLgAFFH8HAAIcAAIJOROtDQCQAAAcAAIJOROtDQCQAAAuAAQKfyIAAhwACAkZHTsMAI8CABwACAkZHTsMAI8CAAAA.',
Ni='Nicolbowlass:BAAALgAECgYJEgAAAA==.Nipao:BAAALgADCgYJBgABLgAECgYJCAABAAAAAA==.',
No='Nopntsdnce:BAAALgADCgIJAgAAAA==.Noriel:BAAALgAECgYJCAAAAA==.',
Nu='Numbnutts:BAAALgADCgYJBgAAAA==.Nutela:BAAALgADCgYJCQAAAA==.',
Nz='Nz:BAAALgADCgcJEwAAAA==.',
Od='Oddeccentric:BAAALgADCgIJAgAAAA==.',
Oh='Ohtani:BAAALgAECgMJAwAAAA==.',
Ol='Olectria:BAAALgADCgEJAQAAAA==.',
Oo='Ooblitoon:BAABLgAECn8WAAINAAYJWgxxBADtAAANAAYJWgxxBADtAAAAAA==.',
Or='Orfantal:BAABLgAECn8VAAIRAAcJrBEVEwBiAQARAAcJrBEVEwBiAQAAAA==.',
Ov='Oven:BAAALgADCgYJCAABLgAECggJJQAOAIIkAA==.Overcast:BAAALgAECgEJAQAAAA==.Overshoot:BAAALgAECgQJBwAAAA==.',
Pa='Panterion:BAAALgAECgUJDAAAAA==.Parvarti:BAAALgAECgUJDQAAAA==.Pathogenic:BAAALgADCgMJBQABLgAECgQJBwABAAAAAA==.Pawmommy:BAAALgADCgMJAwAAAA==.',
Pe='Peachringz:BAAALgADCgcJCAAAAA==.Persimmoñ:BAAALgAECgQJCgAAAA==.Petthemonk:BAAALgADCgcJBAAAAA==.',
Ph='Phaelissia:BAAALgAECgMJAwAAAA==.',
Po='Poolnoodle:BAAALgADCgYJBgAAAA==.',
Pr='Presidìum:BAAALgAECgQJBwAAAA==.Prost:BAAALgAECgUJCAAAAA==.Prowlethius:BAAALgADCgMJAwAAAA==.',
Pu='Purdy:BAAALgADCgQJBAAAAA==.',
Py='Pyroblast:BAABLgAECn8kAAIJAAgJ0SAXIQDvAgAJAAgJ0SAXIQDvAgAAAA==.',
['Pè']='Pèstilence:BAAALgADCgYJCQAAAA==.',
Ra='Ravage:BAAALgADCgIJAgAAAA==.',
Re='Reladin:BAAALgAECgYJCwAAAA==.Relanna:BAAALgAECgMJBgAAAA==.Rend:BAAALgADCgcJBwAAAA==.Rendaelyne:BAAALgADCgMJAwAAAA==.Rendstein:BAAALgAECgUJDAAAAA==.Renzr:BAABLgAECn8iAAMdAAgJMx1nBACMAQAOAAgJCRqHXQDaAQAdAAUJVSNnBACMAQAAAA==.',
Rh='Rhowdie:BAAALgAECgEJAQAAAA==.',
Ri='Ridiknight:BAAALgAECgQJBAAAAA==.',
Ro='Roley:BAAALgAECgYJEAAAAA==.Rowin:BAAALgAECgUJCAAAAA==.',
Ru='Rustedroots:BAAALgAECgQJBwAAAA==.',
Ry='Ryanbolt:BAAALgADCgEJAQAAAA==.',
Sa='Saltdisney:BAAALgADCgYJBgAAAA==.Sarisnika:BAAALgADCgcJBwAAAA==.Saristrix:BAAALgAECgYJDwAAAA==.Sarnara:BAAALgAECgUJDQAAAA==.Savagekegs:BAAALgAECgYJEAAAAA==.Savagex:BAAALgAECgEJAQAAAA==.',
Sc='Scâr:BAAALgADCgkJCQAAAA==.',
Se='Secord:BAAALgAECgUJDQAAAA==.Sekhmet:BAAALgADCgEJAQAAAA==.Sekmet:BAAALgADCgkJFQAAAA==.Selacia:BAAALgADCgcJBwAAAA==.Selania:BAAALgADCgkJDwAAAA==.Sereniity:BAAALgAECgUJCAABLgAECgUJCgABAAAAAA==.',
Sh='Shamalicous:BAAALgAECgIJAgAAAA==.Shamjam:BAAALgAECgQJBwAAAA==.Shanthe:BAAALgAECgYJEQAAAA==.Sharku:BAAALgAECgYJDgAAAA==.Shãdo:BAAALgAECgIJAgAAAA==.Shädë:BAAALgAECgUJCAAAAA==.',
Si='Sidewind:BAAALgAECgIJAgABLgAECggJGAALAC0hAA==.Siinep:BAAALgAECgcJEAAAAA==.',
Sk='Skibblé:BAAALgADCgYJBgAAAA==.Skwisgaar:BAAALgAECgQJBgAAAA==.',
Sl='Slickcity:BAAALgADCgEJAQAAAA==.Slimthick:BAAALgAECgQJBAAAAA==.',
Sm='Smalldad:BAAALgAECgMJAwAAAA==.Smeed:BAABLgAECn8UAAIZAAgJrSF8EgDrAgAZAAgJrSF8EgDrAgAAAA==.',
Sn='Sneakyboi:BAABLgAECn8cAAIFAAgJYRaJAQC7AQAFAAgJYRaJAQC7AQAAAA==.',
So='Sorden:BAAALgAECgQJBQAAAA==.Soülcatcher:BAAALgADCgkJKAAAAA==.',
Sp='Spiced:BAABLgAECn8ZAAIVAAgJSCCyDQDAAgAVAAgJSCCyDQDAAgAAAA==.Spliff:BAAALgAECgEJAQAAAA==.',
Sq='Squirt:BAABLgAECn8YAAIMAAgJBw41GgC6AQAMAAgJBw41GgC6AQAAAA==.',
St='Stabsmcshank:BAABLgAECn8dAAIEAAcJQxYVHQAWAgAEAAcJQxYVHQAWAgAAAA==.Starbux:BAAALgAECgQJDAAAAA==.Steakx:BAAALgAECgQJBgAAAA==.',
Su='Suriel:BAAALgADCgkJHwABLgAECgEJAQABAAAAAA==.',
Sv='Svenya:BAAALgAECgUJCQAAAA==.',
Sy='Sygne:BAAALgADCgYJBgAAAA==.Sylvánas:BAAALgADCgEJAQAAAA==.',
Sz='Szell:BAAALgAECgQJCgAAAA==.',
['Së']='Sëkhmët:BAAALgAECgQJBgABLgAECgQJCAABAAAAAA==.',
Ta='Taggy:BAAALgAECgcJDwAAAA==.Tankachi:BAAALgADCgIJAgAAAA==.Tayebeh:BAAALgADCgcJDAAAAA==.',
Te='Terran:BAAALgADCgIJAgAAAA==.Texhd:BAAALgAECgYJBgABLgAFFAUJDQANAI8iAA==.',
Th='Thalassian:BAAALgAECgEJAQAAAA==.Thalrik:BAAALgADCgcJBwAAAA==.',
Ti='Tingwa:BAAALgADCgQJBAAAAA==.',
To='Toiletnuker:BAAALgAECgEJAQABLgAECggJHQADAAQXAA==.Tokyojoe:BAABLgAECn8UAAIZAAcJEhHmFQBPAQAZAAcJEhHmFQBPAQAAAA==.Torocious:BAAALgAECgEJAQAAAA==.Torrick:BAAALgAECgcJEwAAAA==.Totemtot:BAAALgAECgYJCwAAAA==.Toupee:BAAALgADCgYJCgAAAA==.',
Tr='Tradrivia:BAAALgADCgcJEAAAAA==.Tronly:BAAALgADCgUJBQAAAA==.',
Tu='Tuxlopuz:BAAALgADCgQJBQAAAA==.',
Ty='Tyllivan:BAAALgADCgcJCAAAAA==.',
['Tø']='Tøaster:BAAALgAECgEJAwAAAA==.',
Ul='Ulf:BAAALgAECgUJBwAAAA==.',
Va='Valquirie:BAAALgAECgcJEgAAAA==.Varlamor:BAAALgAECgQJBAAAAA==.Vathraen:BAAALgADCgUJCgAAAA==.',
Ve='Velanistra:BAAALgAECgYJEgAAAA==.Velnia:BAAALgADCgkJDQAAAA==.Velyrinn:BAAALgADCgcJCAAAAA==.Vervane:BAAALgAECgUJDQAAAA==.Very:BAAALgADCgEJAgAAAA==.',
Vg='Vgerr:BAAALgAECgQJCAAAAA==.',
Vi='Viashino:BAAALgADCgQJBAAAAA==.Vidarus:BAAALgAECgQJBwABLgAFFAIJBgAHADQYAA==.Viridian:BAAALgAECgMJBAABLgAFFAIJBwAZAC0eAA==.Vivraa:BAAALgADCgYJBgAAAA==.',
Vo='Vohu:BAAALgAECgUJDQAAAA==.Vozzle:BAAALgAECggJEgAAAA==.',
Vy='Vynesh:BAAALgAECgYJCgAAAA==.Vynos:BAAALgAECgUJCAAAAA==.',
Wa='Wanahkalugie:BAAALgADCgEJAQAAAA==.Wasobi:BAAALgADCgEJAQAAAA==.Waterlily:BAAALgAECgQJCAAAAA==.',
We='Welker:BAAALgADCgQJCAAAAA==.Welkerdk:BAABLgAECn8WAAIOAAYJtyDiEwBzAQAOAAYJtyDiEwBzAQAAAA==.Wendonai:BAAALgADCgQJBgABLgAFFAIJBwAZAC0eAA==.',
Wi='Wildfist:BAAALgADCgYJCQAAAA==.Wildsnakee:BAAALgADCgIJAgAAAA==.',
Wo='Wolfman:BAAALgAECgQJCQAAAA==.',
Xa='Xalidan:BAAALgAECgUJBgAAAA==.',
Xt='Xten:BAAALgADCgkJHwAAAA==.',
Ye='Yeat:BAAALgAECgQJBQAAAA==.',
Yo='Yoshinox:BAAALgAECgMJBAAAAA==.',
Za='Zalazam:BAAALgAECgYJDwAAAA==.Zalth:BAAALgAECgQJBwAAAA==.',
Ze='Zelliph:BAAALgADCgEJAgAAAA==.Zenagdrina:BAAALgAECgEJAQAAAA==.Zerosouls:BAAALgAECgYJBwAAAA==.Zerowolf:BAAALgAECgYJCwAAAA==.',
Zh='Zhaann:BAAALgADCgkJHwAAAA==.',
Zo='Zokor:BAAALgADCgYJBgAAAA==.Zorach:BAAALgAECgEJAQAAAA==.',
['Zá']='Zárá:BAAALgAECgYJCwAAAA==.',
['Ûn']='Ûncle:BAAALgADCgcJCwAAAA==.',
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

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

local lookup = {'Unknown-Unknown','Paladin-Holy','Hunter-BeastMastery','Druid-Restoration','Paladin-Protection','Shaman-Restoration','Druid-Feral','Druid-Guardian','Rogue-Assassination','Shaman-Elemental','Warrior-Fury','Rogue-Subtlety','Paladin-Retribution','Mage-Frost','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','DeathKnight-Unholy','Priest-Discipline','Warlock-Demonology','Warrior-Arms','Warlock-Affliction','Warlock-Destruction','DeathKnight-Blood','Priest-Holy','Hunter-Marksmanship','Hunter-Survival','Monk-Windwalker','Monk-Brewmaster','DeathKnight-Frost','Druid-Balance','Monk-Mistweaver','DemonHunter-Devourer','DemonHunter-Havoc','Warrior-Protection','Priest-Shadow','Shaman-Enhancement',}
local provider = {region='US',realm='KhazModan',name='US',type='weekly',zone=46,date='2026-05-08',data={Ad='Ader:BAAALgADCgkJDQAAAA==.',
Ae='Aeryhnn:BAAALgADCgcJEAABLgAECgIJAgABAAAAAA==.',
Al='Alaanda:BAAALgADCgkJCQAAAA==.Alandrysong:BAABLgAECn8WAAICAAUJkBI2OADkAAACAAUJkBI2OADkAAAAAA==.Alexandre:BAABLgAECn8UAAIDAAcJsxH4PwBOAQADAAcJsxH4PwBOAQAAAA==.Aliandes:BAAALgADCgIJAgAAAA==.Allasia:BAABLgAECn8WAAIEAAYJzg4iRAACAQAEAAYJzg4iRAACAQAAAA==.Aloysius:BAAALgADCgEJAQAAAA==.Alton:BAABLgAECn8cAAMCAAcJehm4FQDhAQACAAcJehm4FQDhAQAFAAMJ2gNYKQBXAAAAAA==.',
Am='Amoonsia:BAAALgADCgIJAgAAAA==.',
An='Anamanahebo:BAAALgAECgIJBAAAAA==.',
Ap='Aphroditee:BAAALgAECgIJAwAAAA==.Apollyonn:BAAALgAECgEJAgAAAA==.Apostriss:BAAALgAECgEJAQAAAA==.',
Aq='Aquafresh:BAABLgAECn8hAAIGAAkJqBvwCACdAgAGAAkJqBvwCACdAgAAAA==.',
Ar='Arisel:BAABLgAECn8WAAMHAAYJ9hKCDgAvAQAHAAYJ2BCCDgAvAQAIAAMJiBQGHwCnAAABLgAECggJHQAJAHgMAA==.Aristia:BAAALgAECgMJAwABLgAECggJHQAKAGgPAA==.Arweni:BAABLgAECn8oAAILAAgJsBV6GwCMAQALAAgJsBV6GwCMAQAAAA==.',
As='Ashand:BAAALgAECgIJAgAAAA==.Ashcheeks:BAAALgAECgEJAQAAAA==.Ashhxc:BAAALgAECgIJAgAAAA==.',
At='Atheizt:BAABLgAECn8gAAICAAgJECRECADqAgACAAgJECRECADqAgAAAA==.',
Av='Avlynn:BAAALgADCgMJAwABLgAFFAMJCgAGACoOAA==.Avoidme:BAAALgADCgkJCQABLgAECggJKwACAGwdAA==.',
Az='Azog:BAAALgAECgIJAgAAAA==.',
Ba='Banedon:BAAALgADCggJCAABLgAECggJKwACAGwdAA==.Baridyn:BAAALgADCgMJBgAAAA==.Bariir:BAAALgAECgMJAwABLgAECgYJEQABAAAAAA==.',
Be='Bearbacked:BAAALgADCggJCgABLgAECgEJAQABAAAAAA==.Bearlytankin:BAAALgADCgkJCQAAAA==.Beefer:BAAALgADCgYJBgAAAA==.Belagrip:BAAALgAECgMJBAAAAA==.Belashar:BAAALgAECgIJAgABLgAECgMJBAABAAAAAA==.Beytuha:BAAALgAECgYJDwAAAA==.',
Bi='Bigtim:BAAALgAECgMJAwAAAA==.Bigworm:BAAALgADCgYJBgAAAA==.Bingling:BAEALgAECgYJBgAAAA==.',
Bl='Blacken:BAAALgAECgYJEwAAAA==.Blackknife:BAABLgAECn8mAAMMAAgJsBzuBQBYAgAMAAgJsBzuBQBYAgAJAAEJGAkuGwA0AAAAAA==.Blakylightz:BAABLgAECn8fAAMFAAgJxxoCCQBGAgAFAAgJxxoCCQBGAgANAAYJcwl5ugARAQABLgAFFAYJGwAIAFcYAA==.Blinker:BAABLgAECn8WAAIOAAYJJA+j0QBKAQAOAAYJJA+j0QBKAQAAAA==.Bloodynuts:BAAALgAECgEJAQABLgAFFAQJDAAOADAWAA==.Blueberriess:BAAALgAECgEJAQAAAA==.Blurberry:BAAALgAECggJDwAAAA==.',
Bo='Bobbidobby:BAAALgAECgYJEQABLgAFFAQJDwAEAK0GAA==.Bobbidyboo:BAACLgAFFH8PAAIEAAQJrQbcHQDoAAAEAAQJrQbcHQDoAAAuAAQKfysAAgQACAkmF6c2AM0BAAQACAkmF6c2AM0BAAAA.Bodhin:BAAALgADCgEJAQAAAA==.Bolton:BAAALgADCgYJCgAAAA==.Bonesclone:BAAALgAECgUJBwAAAA==.Boram:BAAALgAECgEJAQAAAA==.Bostonbean:BAAALgAECgYJDAAAAA==.',
Br='Brechnar:BAAALgADCgQJCQAAAA==.Brewshido:BAAALgAECgYJBwAAAA==.Brovar:BAACLgAFFH8NAAINAAQJBBt1DwBqAQANAAQJBBt1DwBqAQAuAAQKfyoAAw0ACAm1I3IaAMoCAA0ACAm1I3IaAMoCAAIABQlgCuhzAKwAAAAA.Brü:BAAALgADCgUJBQAAAA==.',
Bu='Bubbaa:BAABLgAECn8cAAQPAAgJSAsFIABAAQAPAAgJSAsFIABAAQAQAAQJ8QeZOwCOAAARAAEJwwN3QwAoAAAAAA==.Bubblez:BAAALgAECgQJCAAAAA==.Buddydaelf:BAABLgAECn8YAAIDAAYJwRkCPABdAQADAAYJwRkCPABdAQAAAA==.Bungle:BAAALgADCgEJAQAAAA==.',
Bw='Bwonshlongdi:BAAALgADCgcJBwAAAA==.',
By='Byebyetwinks:BAAALgAECgEJAQAAAA==.',
Ca='Caencis:BAAALgADCggJEwAAAA==.Candyman:BAAALgADCgYJDgAAAA==.Caprisan:BAAALgAECgQJBAABLgAECggJEQABAAAAAA==.',
Ce='Celestina:BAAALgADCgkJFgAAAA==.',
Ch='Chameleon:BAAALgADCgIJAgAAAA==.Channese:BAAALgAECgEJAQAAAA==.Charfig:BAAALgADCgYJBgAAAA==.Chillfang:BAACLgAFFH8GAAISAAIJfQ3CegCYAAASAAIJfQ3CegCYAAAuAAQKfyMAAhIACAnPIZ82AFwCABIACAnPIZ82AFwCAAAA.Chune:BAAALgAECgQJEgAAAA==.Chêster:BAAALgADCgcJEgAAAA==.',
Ci='Circle:BAAALgADCgEJAQAAAA==.',
Cl='Claireity:BAAALgADCgMJAwAAAA==.',
Co='Connor:BAABLgAECn8gAAITAAgJ3RFgEADOAQATAAgJ3RFgEADOAQAAAA==.Cooleddown:BAAALgADCgUJBQAAAA==.Corpsebríde:BAAALgAECgYJDwAAAA==.',
Cr='Crosshair:BAAALgAECgQJCAAAAA==.',
Cu='Cuneglas:BAAALgADCgMJAwAAAA==.',
Cy='Cygne:BAAALgADCgUJBQABLgADCgYJBgABAAAAAA==.',
['Cê']='Cêlaçane:BAAALgAECgYJCQAAAA==.',
Da='Dacianwolf:BAAALgAECgQJAgAAAA==.Daemoni:BAAALgAECgYJCAAAAA==.Dalliance:BAAALgADCggJCAAAAA==.Daravinius:BAAALgAECgcJDwAAAA==.Dare:BAAALgAECggJDgAAAA==.Darksoulz:BAAALgAECgYJBgAAAA==.Darkvoider:BAAALgADCgYJBgAAAA==.Darrir:BAAALgADCgcJDQABLgAECgYJEQABAAAAAA==.Daveah:BAABLgAECn8WAAIGAAYJbhqaHgC9AQAGAAYJbhqaHgC9AQAAAA==.Dazarros:BAAALgAECgUJCgAAAA==.',
De='Deadwait:BAAALgADCgUJBQAAAA==.Deathberry:BAABLgAECn8bAAIUAAgJ9Q2hYgCiAQAUAAgJ9Q2hYgCiAQAAAA==.Deeg:BAAALgADCgMJBQAAAA==.Dellystia:BAAALgAECgQJBwAAAA==.Delphron:BAAALgAECgIJAgAAAA==.Demoncharge:BAAALgADCgcJBwABLgAECgUJCQABAAAAAA==.Demonclaw:BAAALgADCgMJAwABLgAECgUJCQABAAAAAA==.Demondrake:BAAALgAECgUJBgABLgAECgUJCQABAAAAAA==.Demonflayer:BAAALgAECgUJCQAAAA==.Demonicow:BAAALgAECgcJCgAAAA==.Denaeaa:BAAALgAECgYJEwABLgAFFAMJCgAGACoOAA==.Devilzkry:BAAALgAECgcJCwAAAA==.Devlina:BAAALgADCgYJBgAAAA==.Dewtdewt:BAAALgADCgEJAQABLgAECgcJFgADAGIdAA==.',
Dh='Dhodge:BAAALgAECgYJDQABLgAFFAMJBQAVAJMcAA==.',
Di='Dinerra:BAAALgAECgEJAQAAAA==.Divinestorm:BAABLgAECn8rAAICAAgJbB0RBwCoAgACAAgJbB0RBwCoAgAAAA==.',
Dn='Dnyal:BAAALgAECgkJBQAAAA==.',
Do='Doffyy:BAAALgAECgEJAQAAAA==.Dokash:BAAALgAECgMJBQABLgAECgUJDQABAAAAAA==.Dotexe:BAABLgAECn8WAAIJAAUJvB8oCQA8AQAJAAUJvB8oCQA8AQAAAA==.Dotsy:BAACLgAFFH8OAAQWAAQJNxgNAQA6AQAWAAQJERENAQA6AQAUAAMJFQ3KRQDOAAAXAAEJFCBuDgBdAAAuAAQKfysABBcACAl6Iq4PANMBABcABglDHK4PANMBABQABgkJILlVAMYBABYABglPIiwFAHwBAAAA.',
Dr='Drackarys:BAAALgADCgcJDQAAAA==.Dragonpower:BAAALgAECgQJCAAAAA==.Dragooner:BAAALgAECgEJAQAAAA==.Drakiir:BAAALgAECgQJCQABLgAECgYJEQABAAAAAA==.Dralkish:BAABLgAECn80AAINAAkJmRIdMgC0AQANAAkJmRIdMgC0AQAAAA==.Dramore:BAAALgAECgYJCwAAAA==.Drathi:BAAALgADCgcJBwABLgAECgcJGgANAN4fAA==.Dravas:BAAALgAECgUJDwAAAA==.Dressymage:BAAALgAECgUJBwAAAA==.Droxx:BAAALgAECgUJCgAAAA==.Drucilla:BAAALgADCgUJBQAAAA==.Drunkash:BAAALgAECgEJAQAAAA==.Drzark:BAAALgAECgIJAgAAAA==.',
Dw='Dwdog:BAABLgAECn8gAAIWAAcJyRmGAwDDAQAWAAcJyRmGAwDDAQAAAA==.',
['Dà']='Dàthguy:BAABLgAECn8qAAISAAkJOyRtDQAuAwASAAkJOyRtDQAuAwAAAA==.',
['Dè']='Dèstruct:BAAALgAECgEJAQAAAA==.',
Ea='Earthgirl:BAAALgAECgQJBAAAAA==.',
Ed='Edaras:BAAALgAECgYJDwAAAA==.',
El='Elennie:BAAALgAECgEJAgAAAA==.Elephantom:BAAALgADCgEJAQAAAA==.Elerion:BAABLgAECn8XAAITAAgJdhWkDQD3AQATAAgJdhWkDQD3AQAAAA==.Elm:BAAALgADCgUJBQAAAA==.Elsianna:BAAALgAECgIJAgAAAA==.',
Em='Emelie:BAAALgAECgIJAgAAAA==.Emmi:BAABLgAECn8XAAISAAYJihgjTABXAQASAAYJihgjTABXAQAAAA==.',
En='Endeavor:BAAALgADCgUJAwAAAA==.Enyo:BAAALgAECgYJCgAAAA==.',
Er='Erad:BAABLgAECn8YAAINAAcJ/B7gLwBjAgANAAcJ/B7gLwBjAgAAAA==.',
Eu='Eurydice:BAAALgAECgYJCAAAAA==.',
Ev='Eviaela:BAAALgADCgcJEQAAAA==.Evilwarden:BAAALgADCgEJAQAAAA==.',
Ex='Exadius:BAAALgADCgIJAgAAAA==.',
Fa='Faith:BAAALgADCgYJBgAAAA==.Falcor:BAABLgAECn8cAAMPAAgJYiL7BwD5AgAPAAgJDCL7BwD5AgARAAYJXSFyEQDIAQAAAA==.Faloran:BAAALgAECgEJAQAAAA==.',
Fe='Fearafawcett:BAAALgADCgMJBAAAAA==.Fearmyhunter:BAAALgAECgkJAwAAAA==.Fekk:BAAALgADCgIJAgAAAA==.Fervid:BAAALgADCgMJAwAAAA==.Feylen:BAAALgAECgcJEAAAAA==.',
Fi='Fido:BAABLgAECn8WAAIYAAYJchyNDQCYAQAYAAYJchyNDQCYAQAAAA==.Fifthelement:BAABLgAECn8UAAIGAAcJuRrIGADrAQAGAAcJuRrIGADrAQAAAA==.',
Fj='Fjalgeirr:BAAALgAECgYJEQAAAA==.',
Fl='Flockling:BAAALgADCgYJBgAAAA==.',
Fo='Foxymomma:BAABLgAECn8UAAIZAAYJuSCwDAAbAgAZAAYJuSCwDAAbAgAAAA==.',
Fr='Frey:BAACLgAFFH8OAAISAAQJUSAAFQB/AQASAAQJUSAAFQB/AQAuAAQKfysAAhIACAlhJhAXAPECABIACAlhJhAXAPECAAAA.Friarfig:BAAALgADCgMJAwAAAA==.Frothy:BAABLgAECn8aAAMWAAgJjSJZAQDjAgAWAAcJ7iRZAQDjAgAUAAUJaRzopAAOAQAAAA==.Frßlizzard:BAAALgAECgEJAQAAAA==.',
Fu='Fulgar:BAAALgAECgQJBQAAAA==.Funkdrat:BAAALgAECgYJEAAAAA==.',
Fw='Fwenwir:BAABLgAECn8XAAMaAAYJFSCMLADKAQAaAAYJfx+MLADKAQAbAAIJ3Bo1KQCuAAAAAA==.',
Ga='Galatea:BAAALgADCgkJGAAAAA==.Gandriela:BAAALgADCgEJAQAAAA==.Gankak:BAABLgAECn8UAAILAAcJIwlWKQAxAQALAAcJIwlWKQAxAQAAAA==.',
Ge='Geiste:BAAALgAECgYJEQAAAA==.Geronimoose:BAAALgADCggJFAABLgAECgcJHAACAHoZAA==.',
Gh='Ghue:BAAALgAECgcJCQAAAA==.',
Gi='Gilalade:BAABLgAECn8WAAIDAAYJbhTmSAAzAQADAAYJbhTmSAAzAQAAAA==.',
Gl='Glideslope:BAAALgAECgYJEAAAAA==.Glorbius:BAAALgAECgEJAQAAAA==.',
Gn='Gnowaytodie:BAABLgAECn8iAAISAAgJZgfyTgBPAQASAAgJZgfyTgBPAQAAAA==.',
Go='Gobann:BAAALgADCggJEAABLgAECgcJFAAaAG0ZAA==.Gooby:BAAALgAECgQJBAABLgAFFAUJDwACAIMWAA==.Gotwood:BAAALgADCgYJBgAAAA==.',
Gr='Granny:BAAALgAECgYJCQAAAA==.Greencheese:BAAALgADCgMJAwAAAA==.Grimes:BAAALgAECgEJAQAAAA==.Grodin:BAAALgADCggJDwAAAA==.Grofiest:BAAALgAECgcJEwAAAA==.',
Gu='Guggychan:BAACLgAFFH8FAAIVAAMJkxxdCgABAQAVAAMJkxxdCgABAQAuAAQKfygAAhUACQnIJawAAH8DABUACQnIJawAAH8DAAAA.',
['Gô']='Gôö:BAAALgAECgQJDAAAAA==.',
Ha='Hadoken:BAABLgAECn8cAAIcAAkJTw+1EgCfAQAcAAkJTw+1EgCfAQAAAA==.Haelwyn:BAAALgAECgEJAQAAAA==.Haldor:BAABLgAECn8jAAINAAgJewwNSQBqAQANAAgJewwNSQBqAQAAAA==.Haohmaru:BAABLgAECn8XAAIdAAYJEhyFGQBpAQAdAAYJEhyFGQBpAQAAAA==.',
He='Hecæte:BAAALgADCgYJBgAAAA==.Hercdru:BAAALgADCgMJAwAAAA==.Hercgrim:BAAALgAECgMJBQAAAA==.Hercsham:BAAALgAECgQJBAAAAA==.Heunei:BAABLgAECn8UAAIUAAUJ+RQ1awD1AAAUAAUJ+RQ1awD1AAAAAA==.',
Ho='Hoffenstauff:BAAALgADCgMJAwAAAA==.Hollowmagi:BAAALgAECgIJAgAAAA==.Holychoc:BAAALgADCgEJAQAAAA==.',
Hu='Huneyhunter:BAAALgAECgQJDQAAAA==.',
Id='Idkhao:BAAALgADCgMJAwAAAA==.',
Il='Illimommy:BAAALgAECgQJBAAAAA==.',
Im='Imsocold:BAAALgAFFAEJAQAAAA==.',
In='Intern:BAAALgAECgYJEwAAAA==.',
Ir='Irishmonk:BAAALgAECgkJCwAAAA==.',
Is='Isapharra:BAAALgADCgkJFwAAAA==.',
Ja='Jaeksoolie:BAAALgAECgQJBQAAAA==.Jakychanda:BAAALgAECgQJBgAAAA==.Jakyro:BAAALgAECgYJEQAAAA==.Javeech:BAAALgAECgEJAgAAAA==.',
Je='Jeezus:BAAALgADCgYJBgABLgAFFAMJCAASAAkcAA==.',
Jo='Jokinphoenix:BAAALgAECgEJAgABLgAECgYJCwABAAAAAA==.',
Ju='Juudaz:BAACLgAFFH8IAAISAAMJCRxzPgAWAQASAAMJCRxzPgAWAQAuAAQKfyAABBIACQl2GnUYADkCABIACAmJG3UYADkCABgABQkpIO0gADwBAB4AAQllAScaABIAAAAA.',
Ka='Kaalorixa:BAAALgADCgEJAQAAAA==.Kakahna:BAABLgAECn8XAAMCAAYJrSCWEAAXAgACAAYJrSCWEAAXAgANAAQJCxGkfQDxAAAAAA==.Kallan:BAAALgAECgUJCAAAAA==.Kamela:BAAALgAECgQJBgAAAA==.Kamilia:BAAALgAECgEJAQAAAA==.Kapkywa:BAAALgAECgcJCQABLgAECggJIAACABAkAA==.Kappy:BAAALgADCgMJAwAAAA==.Karazen:BAAALgADCgIJAQAAAA==.',
Ke='Kegpoker:BAAALgAECgcJDwAAAA==.Kelgoroth:BAAALgAECgEJAQABLgAECgQJBwABAAAAAA==.',
Ki='Kindacold:BAAALgAECgcJDwAAAA==.Kindahot:BAAALgAECgkJDgAAAA==.Kiyara:BAABLgAECn8sAAIDAAgJWxGEKACvAQADAAgJWxGEKACvAQAAAA==.Kizaki:BAAALgADCgkJDgABLgAECgcJFQACAPkTAA==.',
Kn='Knowoone:BAABLgAECn8nAAIEAAgJIhXvIgCwAQAEAAgJIhXvIgCwAQAAAA==.',
Ko='Komonaut:BAAALgAECgEJAQAAAA==.Koscihardt:BAAALgAECgcJDwAAAA==.',
Kr='Krelliz:BAABLgAECn8cAAIGAAcJTBANNQA3AQAGAAcJTBANNQA3AQAAAA==.Kroctdi:BAAALgADCgYJBgAAAA==.Krolly:BAABLgAECn8WAAIOAAYJVwrmfgATAQAOAAYJVwrmfgATAQAAAA==.Krystar:BAAALgAECgQJCAAAAA==.',
Ku='Kulfig:BAAALgAECgcJDAAAAA==.Kumen:BAABLgAECn8VAAIfAAgJjx02BwBjAgAfAAgJjx02BwBjAgAAAA==.Kungfuwho:BAACLgAFFH8GAAIcAAIJIA0KGACYAAAcAAIJIA0KGACYAAAuAAQKfy0AAxwACAkpGb4MAOwBABwACAkpGb4MAOwBACAABAlGDA03ALAAAAAA.Kutyou:BAAALgADCgMJAwAAAA==.',
['Kû']='Kûnei:BAAALgAECgMJAwAAAA==.',
La='Laysee:BAAALgADCgkJGgAAAA==.Lazegos:BAAALgADCgUJBQAAAA==.',
Le='Lehiga:BAAALgADCgMJAwAAAA==.Lenaea:BAACLgAFFH8KAAIGAAMJKg5gJgC6AAAGAAMJKg5gJgC6AAAuAAQKfyQAAgYACAkEG4IZAOYBAAYACAkEG4IZAOYBAAAA.',
Li='Liesta:BAAALgADCgUJBQAAAA==.Lightrawne:BAABLgAECn8kAAICAAgJixFfMgC1AQACAAgJixFfMgC1AQAAAA==.Liiege:BAAALgAECgUJDwABLgAECgYJEQABAAAAAA==.Likeàßoss:BAAALgADCgcJBwAAAA==.Liltotem:BAAALgADCgUJBQAAAA==.Limp:BAAALgAECgEJAQAAAA==.Litesuprmcst:BAAALgADCgcJDAAAAA==.Littleleg:BAAALgADCgMJAwAAAA==.Littlestjeff:BAAALgAECgUJBwAAAA==.',
Lo='Lobø:BAAALgAECgcJEwAAAA==.',
Lu='Luccyy:BAAALgADCgcJCgAAAA==.Lunatyc:BAABLgAECn8aAAISAAcJcQhhYQAiAQASAAcJcQhhYQAiAQAAAA==.Lunette:BAAALgAECgQJBAAAAA==.Luth:BAAALgAECgQJBwAAAA==.Luçius:BAAALgADCgUJBQAAAA==.',
Ly='Lylacy:BAAALgADCgYJCAAAAA==.',
Ma='Mackenzielyn:BAAALgADCgYJCwAAAA==.Madscience:BAAALgAECgYJDwAAAA==.Magerbrkdown:BAAALgADCgYJBgAAAA==.Magnoliá:BAAALgADCgcJCAAAAA==.Malach:BAAALgAECgYJEAAAAA==.Mammal:BAAALgAECgUJDAAAAA==.Manatee:BAAALgAECgIJBQAAAA==.Mannan:BAAALgADCgEJAQAAAA==.Marlasinger:BAAALgADCgcJCwAAAA==.Marpesia:BAAALgAECgUJCAAAAA==.Marqfourthre:BAAALgAECgEJAQAAAA==.Maygwyn:BAAALgAECgQJCAAAAA==.',
Me='Mediva:BAAALgADCgIJAgAAAA==.Medivha:BAAALgAECgEJAQAAAA==.Meechíe:BAAALgAECgUJBAAAAA==.Megaera:BAACLgAFFH8GAAIhAAMJwhvHIwCxAAAhAAMJwhvHIwCxAAAuAAQKfxwAAyEACAmjIvMOAAcDACEACAmjIvMOAAcDACIAAQkeGBNsADoAAAAA.Melar:BAABLgAECn8ZAAMLAAcJgAdZOQDfAAALAAYJ7ghZOQDfAAAjAAEJWAC7UQARAAAAAA==.Mellador:BAAALgADCgYJBgAAAA==.Mentoku:BAAALgADCgcJDgAAAA==.',
Mi='Mihawk:BAAALgAECgMJAwAAAA==.Minjae:BAAALgAECgIJAgABLgAECggJJQAUAPQUAA==.Minseo:BAAALgAECgEJAQAAAA==.Miserain:BAAALgADCgIJAgAAAA==.Mistytouch:BAAALgADCgMJAwAAAA==.',
Mo='Moondemon:BAAALgADCgEJAQAAAA==.Moongrave:BAAALgADCgQJBAAAAA==.Morrìgan:BAAALgAECgYJEgAAAA==.Movack:BAABLgAECn8WAAINAAcJJQ7lUABUAQANAAcJJQ7lUABUAQAAAA==.Moxxnixx:BAAALgAECgEJAQAAAA==.',
Mu='Muncha:BAAALgAECgEJAQAAAA==.Murderface:BAABLgAECn8WAAMfAAYJ5BWmIgAjAQAfAAYJ5BWmIgAjAQAEAAQJVheLbAAOAQAAAA==.Murloch:BAAALgADCgEJAQAAAA==.',
My='Myalison:BAAALgAECgYJEAAAAA==.Mythunran:BAABLgAECn8nAAIaAAcJAxJcCQBkAQAaAAcJAxJcCQBkAQAAAA==.',
Na='Nalandra:BAAALgADCgcJBwABLgAECgYJDwABAAAAAA==.Natash:BAAALgAECgEJAgAAAA==.Nax:BAAALgAECgMJAwAAAA==.',
Ne='Necrofusion:BAAALgADCgEJAQAAAA==.Nemains:BAAALgAECgEJAQAAAA==.Nerfhammer:BAACLgAFFH8MAAINAAQJuRXuGABHAQANAAQJuRXuGABHAQAuAAQKfygAAg0ACAl6IwYcAMICAA0ACAl6IwYcAMICAAAA.Nessalove:BAACLgAFFH8QAAIZAAQJoREzCwAXAQAZAAQJoREzCwAXAQAuAAQKfykAAhkACAm2HjoMAI8CABkACAm2HjoMAI8CAAAA.',
Ni='Nicolbowlass:BAABLgAECn8ZAAQQAAYJJxFMEwAJAQAQAAYJJxFMEwAJAQAPAAQJ/g95OgC1AAARAAEJxANCQgArAAAAAA==.Nipao:BAAALgAECgMJBgABLgAECgYJDgABAAAAAA==.',
No='Noodle:BAAALgADCgMJAwAAAA==.Nopntsdnce:BAAALgADCgIJAgAAAA==.Nori:BAAALgAECgEJAQABLgAFFAYJIAAOAPgmAA==.Noriel:BAAALgAECgYJDwAAAA==.',
Nu='Numbnutts:BAAALgADCgYJBgAAAA==.Nutela:BAAALgADCgYJCQAAAA==.',
Nz='Nz:BAAALgAECgIJAgAAAA==.',
['Nû']='Nûx:BAAALgADCggJCAAAAA==.',
Od='Oddeccentric:BAAALgADCgIJAgAAAA==.',
Oh='Ohtani:BAAALgAECgcJDAAAAA==.',
Ol='Olectria:BAAALgADCgEJAQAAAA==.',
Oo='Ooblitoon:BAABLgAECn8lAAIRAAgJ/w5jBQCJAQARAAgJ/w5jBQCJAQAAAA==.',
Or='Orfantal:BAABLgAECn8eAAIDAAgJJhM1NQB4AQADAAgJJhM1NQB4AQAAAA==.',
Ov='Oven:BAAALgADCgYJCAABLgAECgkJKgASADskAA==.Overcast:BAAALgAECgIJAwAAAA==.Overshoot:BAAALgAECgQJCAAAAA==.',
Ox='Oxen:BAAALgADCgEJAQAAAA==.',
Pa='Panterion:BAAALgAECgcJEwAAAA==.Parvarti:BAABLgAECn8UAAIXAAcJ6QU5DwDgAAAXAAcJ6QU5DwDgAAAAAA==.Pathogenic:BAAALgAECgEJAQABLgAECgYJCQABAAAAAA==.Pawmommy:BAAALgADCgMJAwAAAA==.',
Pe='Peachringz:BAAALgADCgcJCAAAAA==.Persimmoñ:BAABLgAECn8VAAINAAYJHgcNhwDeAAANAAYJHgcNhwDeAAAAAA==.Petthemonk:BAAALgADCgcJBAAAAA==.',
Ph='Phaelissia:BAAALgAECgYJDwAAAA==.Philljr:BAAALgADCgMJAwAAAA==.',
Pi='Pigzox:BAAALgAECgQJBAAAAA==.',
Pl='Plaugus:BAAALgADCgIJAgAAAA==.',
Po='Poolnoodle:BAAALgADCgYJBgAAAA==.',
Pr='Presidìum:BAAALgAECgcJDgAAAA==.Prost:BAAALgAECgcJDgAAAA==.Prowlethius:BAAALgADCgMJAwAAAA==.',
Pu='Purdy:BAAALgAECgkJAgAAAA==.',
Py='Pyroblast:BAACLgAFFH8MAAIOAAQJMBanNAA9AQAOAAQJMBanNAA9AQAuAAQKfysAAg4ACAkZIRkhAO8CAA4ACAkZIRkhAO8CAAAA.',
['Pè']='Pèstilence:BAAALgADCgYJCQAAAA==.',
Ra='Ravage:BAAALgADCgIJAgAAAA==.',
Re='Relaceara:BAAALgAECgcJDgAAAA==.Reladin:BAABLgAECn8XAAIFAAYJUQp6GwC4AAAFAAYJUQp6GwC4AAAAAA==.Relanna:BAAALgAECgYJEwAAAA==.Rend:BAAALgADCgcJBwAAAA==.Rendaelyne:BAAALgADCgcJDAAAAA==.Rendstein:BAAALgAECgcJEwAAAA==.Renzr:BAABLgAECn82AAMSAAgJ4iAHEQB1AgASAAgJpB8HEQB1AgAYAAYJmCEaCgDaAQAAAA==.Reqquuiiem:BAAALgADCgUJCAAAAA==.',
Rh='Rhowdie:BAAALgAECgEJAQAAAA==.',
Ri='Ridiknight:BAAALgAECgQJBAAAAA==.',
Ro='Roley:BAABLgAECn8UAAIEAAkJMQ9CKQCIAQAEAAkJMQ9CKQCIAQAAAA==.Rowin:BAAALgAECgcJCwAAAA==.',
Ru='Rustedroots:BAAALgAECgYJEwAAAA==.',
Ry='Ryanbolt:BAAALgADCgEJAQAAAA==.',
Sa='Sailley:BAAALgADCgEJAQAAAA==.Saltdisney:BAAALgADCgYJBgAAAA==.Sarisnika:BAAALgADCgcJBwAAAA==.Saristrix:BAAALgAECggJEQAAAA==.Sarnara:BAABLgAECn8VAAIFAAcJ9hhdCwCJAQAFAAcJ9hhdCwCJAQAAAA==.Savagekegs:BAAALgAECgYJEgAAAA==.Savagex:BAAALgAECgEJAQAAAA==.',
Sc='Scâr:BAAALgADCgkJCQAAAA==.',
Se='Secord:BAAALgAECgYJEwAAAA==.Sekhmet:BAAALgADCgEJAQAAAA==.Sekmet:BAAALgADCgkJGQAAAA==.Selacia:BAAALgADCgcJBwAAAA==.Selania:BAAALgADCgkJDwABLgAECgcJGgANABQKAA==.Sereniity:BAAALgAECgYJEQAAAA==.',
Sh='Shamalicous:BAAALgAECgUJCwAAAA==.Shamjam:BAABLgAECn8UAAIGAAYJgBEdMwBAAQAGAAYJgBEdMwBAAQAAAA==.Shanthe:BAAALgAECgYJEQAAAA==.Sharku:BAABLgAECn8cAAIOAAgJnR34HwArAgAOAAgJnR34HwArAgAAAA==.Shãdo:BAAALgAECgIJAgAAAA==.Shädë:BAAALgAECgUJCAAAAA==.',
Si='Sidewind:BAAALgAECgIJAgABLgAECggJHAAPAGIiAA==.Siinep:BAAALgAECgcJEAAAAA==.',
Sk='Skibblé:BAAALgADCgkJDwAAAA==.Skwisgaar:BAAALgAECgQJBgAAAA==.',
Sl='Slickcity:BAAALgADCgEJAQAAAA==.Slimthick:BAAALgAECgYJDAAAAA==.',
Sm='Smalldad:BAAALgAECgMJAwAAAA==.Smeed:BAABLgAECn8UAAIhAAgJrSGAEgDrAgAhAAgJrSGAEgDrAgAAAA==.',
Sn='Sneakyboi:BAABLgAECn8rAAIJAAkJ/BmGAQCDAgAJAAkJ/BmGAQCDAgAAAA==.',
So='Soléne:BAAALgAECgQJBQABLgAECgkJIgAUAGYgAA==.Sorden:BAAALgAECgQJBgAAAA==.',
Sp='Spiced:BAABLgAECn8ZAAIfAAgJSCCwDQDAAgAfAAgJSCCwDQDAAgABLgAECggJGgAWAI0iAA==.Spliff:BAAALgAECgEJAQAAAA==.',
Sq='Squirt:BAABLgAECn8aAAIQAAgJvQ83GgC6AQAQAAgJvQ83GgC6AQAAAA==.',
St='Stabsmcshank:BAACLgAFFH8HAAIMAAMJbgylFQDrAAAMAAMJbgylFQDrAAAuAAQKfyEAAgwACAlfGBMdABYCAAwACAlfGBMdABYCAAAA.Starbux:BAABLgAECn8YAAQTAAcJVxD9IAAjAQATAAUJxBD9IAAjAQAZAAUJEA85WgDLAAAkAAIJyweAUAA3AAAAAA==.Steakx:BAAALgAECgQJBgAAAA==.Stikman:BAAALgAECgEJAQAAAA==.',
Su='Suriel:BAAALgAECgIJAgAAAA==.Suumcuique:BAAALgADCgMJAwABLgAECgYJFgAfAOQVAA==.',
Sv='Svenya:BAAALgAECgYJDAAAAA==.',
Sy='Sygne:BAAALgADCgYJBgAAAA==.Sylvánas:BAAALgADCgEJAgAAAA==.',
Sz='Szell:BAABLgAECn8WAAIDAAYJdArEUgAVAQADAAYJdArEUgAVAQAAAA==.',
['Së']='Sëkhmët:BAAALgAECgQJBwABLgAECgYJCwABAAAAAA==.',
['Sï']='Sïenna:BAAALgAECgMJAwAAAA==.',
Ta='Taggy:BAABLgAECn8dAAIJAAgJeAzEBgB9AQAJAAgJeAzEBgB9AQAAAA==.Tankachi:BAAALgADCgIJAgAAAA==.Tassandie:BAAALgADCggJCQABLgAECgcJEwABAAAAAA==.Tayebeh:BAAALgADCgcJDAAAAA==.',
Te='Terran:BAAALgAECgUJBQAAAA==.Texhd:BAAALgAECgYJBgABLgAFFAYJEwARAE4eAA==.',
Th='Thalassian:BAAALgAECgEJAQAAAA==.Thalrik:BAAALgADCgcJBwAAAA==.Theçølletør:BAAALgAECgEJAQAAAA==.',
Ti='Tingwa:BAAALgADCgQJBAAAAA==.',
To='Toiletnuker:BAAALgAECgYJCwABLgAECggJKwACAGwdAA==.Tokyojoe:BAABLgAECn8bAAIhAAgJKhRMJACvAQAhAAgJKhRMJACvAQAAAA==.Torocious:BAAALgAECgYJDQAAAA==.Torrick:BAABLgAECn8aAAQNAAcJ3h84GwAlAgANAAcJ3h84GwAlAgACAAYJBRcQNwCfAQAFAAEJwxRhQwAwAAAAAA==.Torrickgreed:BAAALgADCgYJBgABLgAECgcJGgANAN4fAA==.Totemtot:BAABLgAECn8XAAIlAAYJwAToEwDFAAAlAAYJwAToEwDFAAAAAA==.Toupee:BAAALgAECgEJAQAAAA==.',
Tr='Tradrivia:BAAALgADCggJGAAAAA==.Tronly:BAAALgADCgUJBQAAAA==.',
Tu='Tuxlopuz:BAAALgADCgQJBQAAAA==.',
Ty='Tyllivan:BAAALgADCgcJCAAAAA==.',
['Tø']='Tøaster:BAAALgAECgUJCgAAAA==.',
Uf='Uffizzle:BAAALgAECgUJBwAAAA==.',
Ul='Ulf:BAAALgAECgYJCgAAAA==.Ullindor:BAAALgADCgEJAQAAAA==.',
Va='Valquirie:BAABLgAECn8kAAIYAAcJ9RiMDACrAQAYAAcJ9RiMDACrAQAAAA==.Valyrius:BAAALgADCggJCQAAAA==.Varlamor:BAAALgAECgUJCQAAAA==.Vathraen:BAAALgADCgcJDwAAAA==.',
Ve='Velanistra:BAABLgAECn8aAAINAAcJFApEYwAnAQANAAcJFApEYwAnAQAAAA==.Velnia:BAAALgAECgcJBwAAAA==.Velyrinn:BAAALgAECgEJAQAAAA==.Vervane:BAAALgAECgYJEQAAAA==.Very:BAAALgAECgQJCAAAAA==.',
Vg='Vgerr:BAAALgAECgYJCwAAAA==.',
Vi='Viashino:BAAALgADCgQJBAAAAA==.Vidarus:BAAALgAECgYJEQABLgAFFAQJDAANALkVAA==.Viridian:BAAALgAECgMJBQABLgAFFAMJBgAhAMIbAA==.Vivraa:BAAALgADCgYJBgAAAA==.',
Vo='Vohu:BAABLgAECn8UAAMaAAcJbRk9DQAYAQAaAAYJlBc9DQAYAQADAAMJ/xsaXAD8AAAAAA==.Vozzle:BAAALgAECggJEgAAAA==.',
Vy='Vynesh:BAAALgAECgcJDQAAAA==.Vynos:BAAALgAECgYJEwAAAA==.Vysant:BAAALgADCgIJAgABLgAECgYJEwABAAAAAA==.',
['Vä']='Väl:BAAALgAECgQJBgAAAA==.',
Wa='Wanahkalugie:BAAALgADCgEJAQAAAA==.Wasobi:BAAALgADCgEJAQAAAA==.Waterlily:BAAALgAECgYJCwAAAA==.',
We='Welker:BAAALgADCgQJCAABLgAECggJJQASADMdAA==.Welkerdk:BAABLgAECn8lAAISAAgJMx1tHgASAgASAAgJMx1tHgASAgAAAA==.Wendonai:BAAALgADCgQJBgABLgAFFAMJBgAhAMIbAA==.',
Wi='Wildfist:BAAALgADCgYJCQAAAA==.Wildsnakee:BAAALgADCgIJAgAAAA==.Windeyaho:BAAALgAECgQJBAAAAA==.',
Wo='Wolfman:BAAALgAECgYJDAAAAA==.Woökie:BAAALgADCgYJBgAAAA==.',
Xa='Xalidan:BAAALgAECgUJCgAAAA==.',
Xt='Xten:BAAALgAECgIJAgAAAA==.',
Ya='Yath:BAAALgAECgMJAwAAAA==.',
Ye='Yeat:BAAALgAECgQJCQAAAA==.',
Yo='Yoshinox:BAAALgAECgMJBAAAAA==.',
Za='Zalazam:BAABLgAECn8cAAIKAAcJ+xuHDwDqAQAKAAcJ+xuHDwDqAQAAAA==.Zalth:BAABLgAECn8UAAIOAAgJbgyhSACNAQAOAAgJbgyhSACNAQAAAA==.',
Ze='Zelliph:BAAALgAECgQJCAAAAA==.Zenagdrina:BAAALgAECgIJBQAAAA==.Zenobiå:BAAALgAECgYJBgAAAA==.Zerosouls:BAAALgAECgYJBwAAAA==.Zerowolf:BAAALgAECgYJCwAAAA==.',
Zh='Zhaann:BAAALgAECgIJAgAAAA==.',
Zo='Zokor:BAAALgADCgkJGAAAAA==.Zorach:BAAALgAECgYJBgAAAA==.',
['Zá']='Zárá:BAABLgAECn8UAAIOAAYJAQ6ydAAoAQAOAAYJAQ6ydAAoAQAAAA==.',
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

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

local lookup = {'Unknown-Unknown','Shaman-Restoration','Rogue-Assassination','Warrior-Fury','Paladin-Holy','Rogue-Subtlety','Paladin-Protection','Paladin-Retribution','Mage-Frost','Druid-Restoration','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','Hunter-BeastMastery','DeathKnight-Unholy','Priest-Discipline','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Warrior-Arms','Monk-Windwalker','DeathKnight-Blood','Druid-Balance','Monk-Mistweaver','DemonHunter-Devourer','DemonHunter-Havoc','Warrior-Protection','Hunter-Marksmanship','Priest-Holy','Shaman-Elemental',}
local provider = {region='US',realm='KhazModan',name='US',type='weekly',zone=46,date='2026-05-01',data={Ad='Ader:BAAALgADCgkJDQAAAA==.',
Ae='Aeryhnn:BAAALgADCgYJCQABLgAECgIJAgABAAAAAA==.',
Al='Alaanda:BAAALgADCgkJCQAAAA==.Alandrysong:BAAALgAECgUJEAAAAA==.Alexandre:BAAALgAECgYJEAAAAA==.Aliandes:BAAALgADCgIJAgAAAA==.Allasia:BAAALgAECgYJEQAAAA==.Aloysius:BAAALgADCgEJAQAAAA==.Alton:BAAALgAECgYJEAAAAA==.',
Am='Amoonsia:BAAALgADCgIJAgAAAA==.',
An='Anamanahebo:BAAALgAECgIJAwAAAA==.',
Ap='Aphroditee:BAAALgAECgIJAwAAAA==.Apollyonn:BAAALgAECgEJAgAAAA==.Apostriss:BAAALgAECgEJAQAAAA==.',
Aq='Aquafresh:BAABLgAECn8YAAICAAgJ1B3pBwBtAgACAAgJ1B3pBwBtAgAAAA==.',
Ar='Arisel:BAAALgAECgYJEAABLgAECggJFgADABQMAA==.Aristia:BAAALgAECgMJAwAAAA==.Arweni:BAABLgAECn8jAAIEAAgJDRQyFgCCAQAEAAgJDRQyFgCCAQAAAA==.',
As='Ashand:BAAALgAECgIJAgAAAA==.Ashhxc:BAAALgAECgIJAgAAAA==.',
At='Atheizt:BAABLgAECn8fAAIFAAgJDSRECADqAgAFAAgJDSRECADqAgAAAA==.',
Av='Avoidme:BAAALgADCgkJCQABLgAECggJJAAFAMkXAA==.',
Az='Azog:BAAALgAECgIJAgAAAA==.',
Ba='Banedon:BAAALgADCggJCAABLgAECggJJAAFAMkXAA==.Baridyn:BAAALgADCgMJBgAAAA==.',
Be='Bearbacked:BAAALgADCggJCgABLgAECgEJAQABAAAAAA==.Beefer:BAAALgADCgYJBgAAAA==.Belagrip:BAAALgAECgMJBAAAAA==.Belashar:BAAALgAECgIJAgABLgAECgMJBAABAAAAAA==.Beytuha:BAAALgAECgUJDQAAAA==.',
Bi='Bigworm:BAAALgADCgYJBgAAAA==.Bingling:BAEALgAECgYJBgAAAA==.',
Bl='Blacken:BAAALgAECgYJDQAAAA==.Blackknife:BAABLgAECn8eAAMGAAcJkxdEEgBRAQAGAAcJkxdEEgBRAQADAAEJEQmTFQA0AAAAAA==.Blakylightz:BAABLgAECn8fAAMHAAgJxxoECQBGAgAHAAgJxxoECQBGAgAIAAYJcwlxugARAQABLgAFFAEJAQABAAAAAA==.Blinker:BAABLgAECn8WAAIJAAYJJA+Z0QBKAQAJAAYJJA+Z0QBKAQAAAA==.Bloodynuts:BAAALgAECgEJAQABLgAFFAMJCAAJAN4cAA==.Blurberry:BAAALgAECggJDwAAAA==.',
Bo='Bobbidobby:BAAALgAECgYJDQABLgAFFAMJCwAKAEYIAA==.Bobbidyboo:BAACLgAFFH8LAAIKAAMJRggxHAC8AAAKAAMJRggxHAC8AAAuAAQKfygAAgoACAkmF6g2AM0BAAoACAkmF6g2AM0BAAAA.Bodhin:BAAALgADCgEJAQAAAA==.Bolton:BAAALgADCgYJCgAAAA==.Bonesclone:BAAALgAECgUJBgAAAA==.Boram:BAAALgAECgEJAQAAAA==.Bostonbean:BAAALgAECgYJDAAAAA==.',
Br='Brechnar:BAAALgADCgQJCQAAAA==.Brewshido:BAAALgAECgUJBgAAAA==.Brovar:BAACLgAFFH8JAAIIAAMJMRU0GgAOAQAIAAMJMRU0GgAOAQAuAAQKfycAAwgACAm3InYaAMoCAAgACAm3InYaAMoCAAUABQlgCuJzAKwAAAAA.Brü:BAAALgADCgUJBQAAAA==.',
Bu='Bubbaa:BAABLgAECn8bAAQLAAcJ8QunHgALAQALAAcJ8QunHgALAQAMAAQJ5QeUOwCOAAANAAEJwwN4QwAoAAAAAA==.Bubblez:BAAALgAECgQJCAAAAA==.Buddydaelf:BAABLgAECn8UAAIOAAYJOBd1VQBoAQAOAAYJOBd1VQBoAQAAAA==.Bungle:BAAALgADCgEJAQAAAA==.',
By='Byebyetwinks:BAAALgAECgEJAQAAAA==.',
Ca='Caencis:BAAALgADCggJEwAAAA==.Candyman:BAAALgADCgYJDgAAAA==.',
Ce='Celestina:BAAALgADCgkJFgAAAA==.',
Ch='Chameleon:BAAALgADCgIJAgAAAA==.Channese:BAAALgAECgEJAQAAAA==.Chillfang:BAACLgAFFH8GAAIPAAIJfQ11WQCcAAAPAAIJfQ11WQCcAAAuAAQKfyMAAg8ACAnPIaI2AFwCAA8ACAnPIaI2AFwCAAAA.Chune:BAAALgAECgQJDgAAAA==.Chêster:BAAALgADCgcJEgAAAA==.',
Ci='Circle:BAAALgADCgEJAQAAAA==.',
Cl='Claireity:BAAALgADCgMJAwAAAA==.',
Co='Connor:BAABLgAECn8dAAIQAAgJ3BEYCwDbAQAQAAgJ3BEYCwDbAQAAAA==.Cooleddown:BAAALgADCgUJBQAAAA==.Corpsebríde:BAAALgAECgYJDwAAAA==.',
Cr='Crosshair:BAAALgAECgQJBAAAAA==.',
Cu='Cuneglas:BAAALgADCgMJAwAAAA==.',
Cy='Cygne:BAAALgADCgUJBQABLgADCgYJBgABAAAAAA==.',
['Cê']='Cêlaçane:BAAALgAECgYJCQAAAA==.',
Da='Dacianwolf:BAAALgAECgMJAgAAAA==.Daemoni:BAAALgAECgIJAgAAAA==.Dalliance:BAAALgADCggJCAAAAA==.Daravinius:BAAALgAECgcJDwAAAA==.Dare:BAAALgAECggJDgAAAA==.Darksoulz:BAAALgAECgYJBgAAAA==.Darkvoider:BAAALgADCgYJBgAAAA==.Darrir:BAAALgADCgcJDQABLgAECgYJEAABAAAAAA==.Daveah:BAAALgAECgYJEAAAAA==.Dazarros:BAAALgAECgMJBQAAAA==.',
De='Deadwait:BAAALgADCgUJBQAAAA==.Deathberry:BAABLgAECn8VAAIRAAgJDA2hYgCiAQARAAgJDA2hYgCiAQAAAA==.Deeg:BAAALgADCgMJBQAAAA==.Dellystia:BAAALgAECgQJBwAAAA==.Delphron:BAAALgADCgkJEwAAAA==.Demoncharge:BAAALgADCgcJBwABLgAECgUJBwABAAAAAA==.Demonclaw:BAAALgADCgMJAwABLgAECgUJBwABAAAAAA==.Demondrake:BAAALgAECgQJBQABLgAECgUJBwABAAAAAA==.Demonflayer:BAAALgAECgUJBwAAAA==.Demonicow:BAAALgAECgYJBwAAAA==.Denaeaa:BAAALgAECgYJDQABLgAFFAMJBwACAFQMAA==.Devilzkry:BAAALgAECgYJCAAAAA==.Devlina:BAAALgADCgYJBgAAAA==.Dewtdewt:BAAALgADCgEJAQAAAA==.',
Dh='Dhodge:BAAALgAECgYJBwAAAA==.',
Di='Dinerra:BAAALgAECgEJAQAAAA==.Divinestorm:BAABLgAECn8kAAIFAAgJyReiCgAtAgAFAAgJyReiCgAtAgAAAA==.',
Dn='Dnyal:BAAALgAECgkJBQAAAA==.',
Do='Doffyy:BAAALgAECgEJAQAAAA==.Dotexe:BAAALgAECgUJEgAAAA==.Dotsy:BAACLgAFFH8JAAMSAAMJyBIPCgBhAAARAAIJIAyqSwCTAAASAAEJFyAPCgBhAAAuAAQKfygABBIACAlpIa0PANMBABIABglCHK0PANMBABEABgkHIMFVAMYBABMABgmmG7QOAEUBAAAA.',
Dr='Drackarys:BAAALgADCgYJBgAAAA==.Dragonpower:BAAALgAECgQJCAAAAA==.Dragooner:BAAALgADCgEJAQAAAA==.Drakiir:BAAALgAECgQJCQABLgAECgYJEAABAAAAAA==.Dralkish:BAABLgAECn8rAAIIAAgJ1RLJXgDHAQAIAAgJ1RLJXgDHAQAAAA==.Dramore:BAAALgAECgQJBQAAAA==.Drathi:BAAALgADCgcJBwABLgAECgcJGAAIABcdAA==.Dravas:BAAALgAECgQJCwAAAA==.Dressymage:BAAALgAECgUJBwAAAA==.Droxx:BAAALgAECgQJCAAAAA==.Drucilla:BAAALgADCgUJBQAAAA==.Drzark:BAAALgAECgIJAgAAAA==.',
Dw='Dwdog:BAABLgAECn8aAAITAAcJYhZLAgC/AQATAAcJYhZLAgC/AQAAAA==.',
['Dà']='Dàthguy:BAABLgAECn8nAAIPAAgJgiRwDQAuAwAPAAgJgiRwDQAuAwAAAA==.',
['Dè']='Dèstruct:BAAALgAECgEJAQAAAA==.',
Ea='Earthgirl:BAAALgAECgQJBAAAAA==.',
Ed='Edaras:BAAALgAECgYJDwAAAA==.',
El='Elennie:BAAALgAECgEJAgAAAA==.Elephantom:BAAALgADCgEJAQAAAA==.Elerion:BAAALgAECgcJDwAAAA==.Elm:BAAALgADCgUJBQAAAA==.Elsianna:BAAALgAECgIJAgAAAA==.',
Em='Emelie:BAAALgAECgEJAQAAAA==.Emmi:BAAALgAECgYJEQAAAA==.',
En='Endeavor:BAAALgADCgUJAwAAAA==.Enyo:BAAALgAECgYJCgAAAA==.',
Er='Erad:BAABLgAECn8YAAIIAAcJ/B7kLwBjAgAIAAcJ/B7kLwBjAgAAAA==.',
Eu='Eurydice:BAAALgAECgYJCAAAAA==.',
Ev='Eviaela:BAAALgADCgcJEQAAAA==.Evilwarden:BAAALgADCgEJAQAAAA==.',
Ex='Exadius:BAAALgADCgIJAgAAAA==.',
Fa='Faith:BAAALgADCgYJBgAAAA==.Falcor:BAABLgAECn8cAAMLAAgJYSL+BwD5AgALAAgJCyL+BwD5AgANAAYJXSFxEQDIAQAAAA==.',
Fe='Fearafawcett:BAAALgADCgMJBAAAAA==.Fearmyhunter:BAAALgAECgYJAwAAAA==.Fervid:BAAALgADCgMJAwAAAA==.Feylen:BAAALgAECgcJEAAAAA==.',
Fi='Fido:BAAALgAECgYJEAAAAA==.Fifthelement:BAAALgAECgYJEAAAAA==.',
Fj='Fjalgeirr:BAAALgAECgYJEAAAAA==.',
Fl='Flockling:BAAALgADCgYJBgAAAA==.',
Fo='Foxymomma:BAAALgAECgYJEQAAAA==.',
Fr='Frey:BAACLgAFFH8KAAIPAAMJ4B75LAALAQAPAAMJ4B75LAALAQAuAAQKfygAAg8ACAlcJhEXAPECAA8ACAlcJhEXAPECAAAA.Friarfig:BAAALgADCgMJAwAAAA==.Frothy:BAABLgAECn8aAAMTAAgJjCJZAQDjAgATAAcJ7SRZAQDjAgARAAUJZhzhpAAOAQAAAA==.Frßlizzard:BAAALgAECgEJAQAAAA==.',
Fu='Fulgar:BAAALgAECgQJBQAAAA==.Funkdrat:BAAALgAECgYJEAAAAA==.',
Fw='Fwenwir:BAAALgAECgYJEwAAAA==.',
Ga='Galatea:BAAALgADCgkJDwAAAA==.Gandriela:BAAALgADCgEJAQAAAA==.Gankak:BAAALgAECgYJEAAAAA==.',
Ge='Geiste:BAAALgAECgYJEQAAAA==.Geronimoose:BAAALgADCggJFAABLgAECgYJEAABAAAAAA==.',
Gh='Ghue:BAAALgAECgcJCQAAAA==.',
Gi='Gilalade:BAAALgAECgYJEQAAAA==.',
Gl='Glideslope:BAAALgAECgYJEAAAAA==.Glorbius:BAAALgAECgEJAQAAAA==.',
Gn='Gnowaytodie:BAABLgAECn8gAAIPAAgJKQeTOQBUAQAPAAgJKQeTOQBUAQAAAA==.',
Go='Gobann:BAAALgADCggJDwABLgAECgYJEAABAAAAAA==.Gooby:BAAALgAECgQJBAAAAA==.Gotwood:BAAALgADCgYJBgAAAA==.',
Gr='Granny:BAAALgAECgYJCQAAAA==.Grimes:BAAALgAECgEJAQAAAA==.Grodin:BAAALgADCggJDwAAAA==.Grofiest:BAAALgAECgYJEAAAAA==.',
Gu='Guggychan:BAACLgAFFH8FAAIUAAMJmRwHBgAZAQAUAAMJmRwHBgAZAQAuAAQKfyQAAhQACAkpJqwAAH8DABQACAkpJqwAAH8DAAAA.',
['Gô']='Gôö:BAAALgAECgQJCQAAAA==.',
Ha='Hadoken:BAABLgAECn8cAAIVAAkJUg9mEQBrAQAVAAkJUg9mEQBrAQAAAA==.Haldor:BAABLgAECn8jAAIIAAgJcww4MwB1AQAIAAgJcww4MwB1AQAAAA==.Haohmaru:BAAALgAECgYJEQAAAA==.',
He='Hecæte:BAAALgADCgYJBgAAAA==.Hercdru:BAAALgADCgMJAwAAAA==.Hercgrim:BAAALgAECgIJAgAAAA==.Hercsham:BAAALgAECgQJBAAAAA==.Heunei:BAABLgAECn8UAAIRAAUJ+RQOUgD6AAARAAUJ+RQOUgD6AAAAAA==.',
Ho='Hoffenstauff:BAAALgADCgMJAwAAAA==.Hollowmagi:BAAALgAECgIJAgAAAA==.Holychoc:BAAALgADCgEJAQAAAA==.',
Hu='Huneyhunter:BAAALgAECgQJCwAAAA==.',
Id='Idkhao:BAAALgADCgMJAwAAAA==.',
Il='Illimommy:BAAALgAECgQJBAAAAA==.',
Im='Imsocold:BAAALgAECgIJAwAAAA==.',
In='Intern:BAAALgAECgQJDgAAAA==.',
Ir='Irishmonk:BAAALgAECgkJCwAAAA==.',
Is='Isapharra:BAAALgADCgkJDwAAAA==.',
Ja='Jaeksoolie:BAAALgAECgQJBQAAAA==.Jakychanda:BAAALgAECgQJBgAAAA==.Jakyro:BAAALgAECgYJEQAAAA==.Javeech:BAAALgADCgcJDQAAAA==.',
Je='Jeezus:BAAALgADCgYJBgABLgAFFAMJBQAPABsPAA==.',
Jo='Jokinphoenix:BAAALgAECgEJAgABLgAECgYJCwABAAAAAA==.',
Ju='Juudaz:BAACLgAFFH8FAAIPAAMJGw+AOQDpAAAPAAMJGw+AOQDpAAAuAAQKfxUAAw8ABwnPHpVfANQBAA8ABwnyGpVfANQBABYABQkdIO4gADwBAAAA.',
Ka='Kaalorixa:BAAALgADCgEJAQAAAA==.Kakahna:BAAALgAECgYJEQAAAA==.Kallan:BAAALgAECgMJAwAAAA==.Kamela:BAAALgAECgQJBgAAAA==.Kamilia:BAAALgAECgEJAQAAAA==.Kappy:BAAALgADCgMJAwAAAA==.Karazen:BAAALgADCgIJAQAAAA==.',
Ke='Kegpoker:BAAALgAECgcJDwAAAA==.Kelgoroth:BAAALgAECgEJAQABLgAECgMJAwABAAAAAA==.',
Ki='Kindacold:BAAALgAECgcJDwAAAA==.Kindahot:BAAALgAECgkJCwAAAA==.Kiyara:BAABLgAECn8kAAIOAAgJiAszJgCAAQAOAAgJiAszJgCAAQAAAA==.Kizaki:BAAALgADCgkJDgABLgAECgYJDwABAAAAAA==.',
Kn='Knowoone:BAABLgAECn8iAAIKAAgJRBQCGgCwAQAKAAgJRBQCGgCwAQAAAA==.',
Ko='Komonaut:BAAALgAECgEJAQAAAA==.Koscihardt:BAAALgAECgcJDwAAAA==.',
Kr='Krelliz:BAABLgAECn8YAAICAAcJSRB8KAAsAQACAAcJSRB8KAAsAQAAAA==.Kroctdi:BAAALgADCgYJBgAAAA==.Krolly:BAAALgAECgUJEAAAAA==.Krystar:BAAALgAECgQJBAAAAA==.',
Ku='Kulfig:BAAALgAECgYJCQAAAA==.Kumen:BAABLgAECn8TAAIXAAYJeRxEDgCrAQAXAAYJeRxEDgCrAQAAAA==.Kungfuwho:BAABLgAECn8iAAMVAAgJzhX/EABwAQAVAAgJzhX/EABwAQAYAAEJswOYTgAgAAAAAA==.Kutyou:BAAALgADCgMJAwAAAA==.',
['Kû']='Kûnei:BAAALgAECgMJAwAAAA==.',
La='Laysee:BAAALgADCgkJGgAAAA==.Lazegos:BAAALgADCgUJBQAAAA==.',
Le='Lehiga:BAAALgADCgMJAwAAAA==.Lenaea:BAACLgAFFH8HAAICAAMJVAw+GwCNAAACAAMJVAw+GwCNAAAuAAQKfyIAAgIACAkDGx4jAAwCAAIACAkDGx4jAAwCAAAA.',
Li='Liesta:BAAALgADCgUJBQAAAA==.Lightrawne:BAABLgAECn8fAAIFAAgJrA5dMgC1AQAFAAgJrA5dMgC1AQAAAA==.Liiege:BAAALgAECgUJDgABLgAECgYJEAABAAAAAA==.Likeàßoss:BAAALgADCgcJBwAAAA==.Liltotem:BAAALgADCgUJBQAAAA==.Limp:BAAALgAECgEJAQAAAA==.Litesuprmcst:BAAALgADCgYJBgAAAA==.Littleleg:BAAALgADCgMJAwAAAA==.Littlestjeff:BAAALgAECgUJBgAAAA==.',
Lo='Lobø:BAAALgAECgYJDwAAAA==.',
Lu='Luccyy:BAAALgADCgcJCgAAAA==.Lunatyc:BAABLgAECn8YAAIPAAcJJQfPTAAZAQAPAAcJJQfPTAAZAQAAAA==.Lunette:BAAALgAECgQJBAAAAA==.Luth:BAAALgAECgMJAwAAAA==.Luçius:BAAALgADCgUJBQAAAA==.',
Ly='Lylacy:BAAALgADCgYJCAAAAA==.',
Ma='Mackenzielyn:BAAALgADCgYJCwAAAA==.Madscience:BAAALgAECgYJCQAAAA==.Magerbrkdown:BAAALgADCgYJBgAAAA==.Magnoliá:BAAALgADCgcJCAAAAA==.Malach:BAAALgAECgYJEAAAAA==.Mammal:BAAALgAECgUJCwAAAA==.Manatee:BAAALgAECgIJBAAAAA==.Mannan:BAAALgADCgEJAQAAAA==.Marlasinger:BAAALgADCgcJCwAAAA==.Marpesia:BAAALgAECgQJBQAAAA==.Marqfourthre:BAAALgAECgEJAQAAAA==.Maygwyn:BAAALgAECgQJBAAAAA==.',
Me='Medivha:BAAALgAECgEJAQAAAA==.Meechíe:BAAALgAECgEJAQAAAA==.Megaera:BAACLgAFFH8GAAIZAAMJLBvDIwCxAAAZAAMJLBvDIwCxAAAuAAQKfxwAAxkACAmjIvgOAAcDABkACAmjIvgOAAcDABoAAQkeGBNsADoAAAAA.Melar:BAABLgAECn8UAAMEAAYJeQfoNQCyAAAEAAUJQgnoNQCyAAAbAAEJWAC6UQARAAAAAA==.Mellador:BAAALgADCgYJBgAAAA==.Mentoku:BAAALgADCgcJDgAAAA==.',
Mi='Mihawk:BAAALgAECgMJAwAAAA==.Minjae:BAAALgAECgIJAgABLgAECggJJAARACQTAA==.Mistytouch:BAAALgADCgMJAwAAAA==.',
Mo='Moondemon:BAAALgADCgEJAQAAAA==.Moongrave:BAAALgADCgQJBAAAAA==.Morrìgan:BAAALgAECgYJDQAAAA==.Movack:BAABLgAECn8WAAIIAAcJIg7QOQBeAQAIAAcJIg7QOQBeAQAAAA==.Moxxnixx:BAAALgAECgEJAQAAAA==.',
Mu='Murderface:BAAALgAECgYJEAAAAA==.Murloch:BAAALgADCgEJAQAAAA==.',
My='Myalison:BAAALgAECgYJDgAAAA==.Mythunran:BAABLgAECn8hAAIcAAcJqQ/vCABIAQAcAAcJqQ/vCABIAQAAAA==.',
Na='Nalandra:BAAALgADCgcJBwABLgAECgYJDwABAAAAAA==.Natash:BAAALgAECgEJAQAAAA==.Nax:BAAALgAECgMJAwAAAA==.',
Ne='Necrofusion:BAAALgADCgEJAQAAAA==.Nemains:BAAALgAECgEJAQAAAA==.Nerfhammer:BAACLgAFFH8IAAIIAAMJwBlcHQABAQAIAAMJwBlcHQABAQAuAAQKfyUAAggACAkGIwocAMICAAgACAkGIwocAMICAAAA.Nessalove:BAACLgAFFH8LAAIdAAMJZRNWCwDXAAAdAAMJZRNWCwDXAAAuAAQKfyYAAh0ACAmJHj0MAI8CAB0ACAmJHj0MAI8CAAAA.',
Ni='Nicolbowlass:BAABLgAECn8XAAQMAAYJGBFHDwALAQAMAAYJGBFHDwALAQALAAQJ6QzvMACdAAANAAEJxANDQgArAAAAAA==.Nipao:BAAALgAECgEJAQABLgAECgYJCgABAAAAAA==.',
No='Noodle:BAAALgADCgMJAwAAAA==.Nopntsdnce:BAAALgADCgIJAgAAAA==.Nori:BAAALgAECgEJAQABLgAFFAYJGgAJAPgmAA==.Noriel:BAAALgAECgYJDgAAAA==.',
Nu='Numbnutts:BAAALgADCgYJBgAAAA==.Nutela:BAAALgADCgYJCQAAAA==.',
Nz='Nz:BAAALgAECgIJAgAAAA==.',
['Nû']='Nûx:BAAALgADCggJCAAAAA==.',
Od='Oddeccentric:BAAALgADCgIJAgAAAA==.',
Oh='Ohtani:BAAALgAECgYJCQAAAA==.',
Ol='Olectria:BAAALgADCgEJAQAAAA==.',
Oo='Ooblitoon:BAABLgAECn8dAAINAAcJCg40BQBgAQANAAcJCg40BQBgAQAAAA==.',
Or='Orfantal:BAABLgAECn8cAAIOAAgJeBH+JgB8AQAOAAgJeBH+JgB8AQAAAA==.',
Ov='Oven:BAAALgADCgYJCAABLgAECggJJwAPAIIkAA==.Overcast:BAAALgAECgEJAgAAAA==.Overshoot:BAAALgAECgQJBwAAAA==.',
Ox='Oxen:BAAALgADCgEJAQAAAA==.',
Pa='Panterion:BAAALgAECgYJDwAAAA==.Parvarti:BAAALgAECgYJEAAAAA==.Pathogenic:BAAALgAECgEJAQABLgAECgUJCAABAAAAAA==.Pawmommy:BAAALgADCgMJAwAAAA==.',
Pe='Peachringz:BAAALgADCgcJCAAAAA==.Persimmoñ:BAAALgAECgYJEAAAAA==.Petthemonk:BAAALgADCgcJBAAAAA==.',
Ph='Phaelissia:BAAALgAECgYJCQAAAA==.',
Pi='Pigzox:BAAALgAECgQJAwAAAA==.',
Po='Poolnoodle:BAAALgADCgYJBgAAAA==.',
Pr='Presidìum:BAAALgAECgQJBwAAAA==.Prost:BAAALgAECgYJCwAAAA==.Prowlethius:BAAALgADCgMJAwAAAA==.',
Pu='Purdy:BAAALgADCgQJBAAAAA==.',
Py='Pyroblast:BAACLgAFFH8IAAIJAAMJ3hwZMQAHAQAJAAMJ3hwZMQAHAQAuAAQKfygAAgkACAnRIBghAO8CAAkACAnRIBghAO8CAAAA.',
['Pè']='Pèstilence:BAAALgADCgYJCQAAAA==.',
Ra='Ravage:BAAALgADCgIJAgAAAA==.',
Re='Relaceara:BAAALgAECgcJBwAAAA==.Reladin:BAAALgAECgYJEQAAAA==.Relanna:BAAALgAECgYJDQAAAA==.Rend:BAAALgADCgcJBwAAAA==.Rendaelyne:BAAALgADCgYJCQAAAA==.Rendstein:BAAALgAECgYJDwAAAA==.Renzr:BAABLgAECn8qAAMWAAgJyR3OBQDSAQAPAAgJjRyFXQDaAQAWAAYJuiDOBQDSAQAAAA==.Reqquuiiem:BAAALgADCgUJBQAAAA==.',
Rh='Rhowdie:BAAALgAECgEJAQAAAA==.',
Ri='Ridiknight:BAAALgAECgQJBAAAAA==.',
Ro='Roley:BAAALgAECggJEwAAAA==.Rowin:BAAALgAECgcJCwAAAA==.',
Ru='Rustedroots:BAAALgAECgYJDQAAAA==.',
Ry='Ryanbolt:BAAALgADCgEJAQAAAA==.',
Sa='Saltdisney:BAAALgADCgYJBgABLgAFFAYJDgAFAKUKAA==.Sarisnika:BAAALgADCgcJBwAAAA==.Saristrix:BAAALgAECgYJDwAAAA==.Sarnara:BAAALgAECgYJEQAAAA==.Savagekegs:BAAALgAECgYJEQAAAA==.Savagex:BAAALgAECgEJAQAAAA==.',
Sc='Scâr:BAAALgADCgkJCQAAAA==.',
Se='Secord:BAAALgAECgYJEAAAAA==.Sekhmet:BAAALgADCgEJAQAAAA==.Sekmet:BAAALgADCgkJFwAAAA==.Selacia:BAAALgADCgcJBwAAAA==.Selania:BAAALgADCgkJDwAAAA==.Sereniity:BAAALgAECgYJEAAAAA==.',
Sh='Shamalicous:BAAALgAECgUJBwAAAA==.Shamjam:BAAALgAECgYJDgAAAA==.Shanthe:BAAALgAECgYJEQAAAA==.Sharku:BAABLgAECn8UAAIJAAcJIh4cNQCRAQAJAAcJIh4cNQCRAQAAAA==.Shãdo:BAAALgAECgIJAgAAAA==.Shädë:BAAALgAECgUJCAAAAA==.',
Si='Sidewind:BAAALgAECgIJAgABLgAECggJHAALAGEiAA==.Siinep:BAAALgAECgcJEAAAAA==.',
Sk='Skibblé:BAAALgADCgYJBgAAAA==.Skwisgaar:BAAALgAECgQJBgAAAA==.',
Sl='Slickcity:BAAALgADCgEJAQAAAA==.Slimthick:BAAALgAECgUJCQAAAA==.',
Sm='Smalldad:BAAALgAECgMJAwAAAA==.Smeed:BAABLgAECn8UAAIZAAgJrSGEEgDrAgAZAAgJrSGEEgDrAgAAAA==.',
Sn='Sneakyboi:BAABLgAECn8kAAIDAAgJVhhqAgD/AQADAAgJVhhqAgD/AQAAAA==.',
So='Soléne:BAAALgAECgQJBAAAAA==.Sorden:BAAALgAECgQJBgAAAA==.Soülcatcher:BAAALgADCgkJKAAAAA==.',
Sp='Spiced:BAABLgAECn8ZAAIXAAgJSCCwDQDAAgAXAAgJSCCwDQDAAgABLgAECggJGgATAIwiAA==.Spliff:BAAALgAECgEJAQAAAA==.',
Sq='Squirt:BAABLgAECn8aAAIMAAgJug82GgC6AQAMAAgJug82GgC6AQAAAA==.',
St='Stabsmcshank:BAABLgAECn8fAAIGAAgJhxYVHQAWAgAGAAgJhxYVHQAWAgAAAA==.Starbux:BAAALgAECgQJDwAAAA==.Steakx:BAAALgAECgQJBgAAAA==.Stikman:BAAALgAECgEJAQAAAA==.',
Su='Suriel:BAAALgAECgIJAgAAAA==.',
Sv='Svenya:BAAALgAECgYJCwAAAA==.',
Sy='Sygne:BAAALgADCgYJBgAAAA==.Sylvánas:BAAALgADCgEJAgAAAA==.',
Sz='Szell:BAAALgAECgYJEAAAAA==.',
['Së']='Sëkhmët:BAAALgAECgQJBwABLgAECgUJCgABAAAAAA==.',
Ta='Taggy:BAABLgAECn8WAAIDAAgJFAwMBQB6AQADAAgJFAwMBQB6AQAAAA==.Tankachi:BAAALgADCgIJAgAAAA==.Tassandie:BAAALgADCggJCAABLgAECgYJDwABAAAAAA==.Tayebeh:BAAALgADCgcJDAAAAA==.',
Te='Terran:BAAALgADCgYJCAAAAA==.Texhd:BAAALgAECgYJBgABLgAFFAEJAQABAAAAAA==.',
Th='Thalassian:BAAALgAECgEJAQAAAA==.Thalrik:BAAALgADCgcJBwAAAA==.',
Ti='Tingwa:BAAALgADCgQJBAAAAA==.',
To='Toiletnuker:BAAALgAECgQJBQABLgAECggJJAAFAMkXAA==.Tokyojoe:BAABLgAECn8SAAIZAAgJQxPvPgDrAAAZAAgJQxPvPgDrAAAAAA==.Torocious:BAAALgAECgYJBwAAAA==.Torrick:BAABLgAECn8YAAQIAAcJFx33IADFAQAIAAcJFx33IADFAQAFAAYJBRcONwCfAQAHAAEJwxRjQwAwAAAAAA==.Torrickgreed:BAAALgADCgYJBgABLgAECgcJGAAIABcdAA==.Totemtot:BAAALgAECgYJEQAAAA==.Toupee:BAAALgADCgkJDQAAAA==.',
Tr='Tradrivia:BAAALgADCggJGAAAAA==.Tronly:BAAALgADCgUJBQAAAA==.',
Tu='Tuxlopuz:BAAALgADCgQJBQAAAA==.',
Ty='Tyllivan:BAAALgADCgcJCAAAAA==.',
['Tø']='Tøaster:BAAALgAECgUJCAAAAA==.',
Ul='Ulf:BAAALgAECgUJBwAAAA==.Ullindor:BAAALgADCgEJAQAAAA==.',
Va='Valquirie:BAABLgAECn8fAAIWAAcJshXGCQB4AQAWAAcJshXGCQB4AQAAAA==.Valyrius:BAAALgADCggJCAAAAA==.Varlamor:BAAALgAECgQJBQAAAA==.Vathraen:BAAALgADCgcJDQAAAA==.',
Ve='Velanistra:BAABLgAECn8XAAIIAAYJhQmyWgABAQAIAAYJhQmyWgABAQAAAA==.Velnia:BAAALgADCgkJDQAAAA==.Velyrinn:BAAALgAECgEJAQAAAA==.Vervane:BAAALgAECgYJEAAAAA==.Very:BAAALgAECgQJBAAAAA==.',
Vg='Vgerr:BAAALgAECgUJCQAAAA==.',
Vi='Viashino:BAAALgADCgQJBAAAAA==.Vidarus:BAAALgAECgYJDQABLgAFFAMJCAAIAMAZAA==.Viridian:BAAALgAECgMJBQABLgAFFAMJBgAZACwbAA==.Vivraa:BAAALgADCgYJBgAAAA==.',
Vo='Vohu:BAAALgAECgYJEAAAAA==.Vozzle:BAAALgAECggJEgAAAA==.',
Vy='Vynesh:BAAALgAECgYJCgAAAA==.Vynos:BAAALgAECgYJDQAAAA==.',
['Vä']='Väl:BAAALgAECgQJBgAAAA==.',
Wa='Wanahkalugie:BAAALgADCgEJAQAAAA==.Wasobi:BAAALgADCgEJAQAAAA==.Waterlily:BAAALgAECgUJCgAAAA==.',
We='Welker:BAAALgADCgQJCAAAAA==.Welkerdk:BAABLgAECn8dAAIPAAcJqhx6IQC/AQAPAAcJqhx6IQC/AQAAAA==.Wendonai:BAAALgADCgQJBgABLgAFFAMJBgAZACwbAA==.',
Wi='Wildfist:BAAALgADCgYJCQAAAA==.Wildsnakee:BAAALgADCgIJAgAAAA==.',
Wo='Wolfman:BAAALgAECgUJCgAAAA==.',
Xa='Xalidan:BAAALgAECgUJBwAAAA==.',
Xt='Xten:BAAALgAECgIJAgAAAA==.',
Ye='Yeat:BAAALgAECgQJBQAAAA==.',
Yo='Yoshinox:BAAALgAECgMJBAAAAA==.',
Za='Zalazam:BAABLgAECn8VAAIeAAYJqBfTGABMAQAeAAYJqBfTGABMAQAAAA==.Zalth:BAAALgAECggJEAAAAA==.',
Ze='Zelliph:BAAALgAECgQJBAAAAA==.Zenagdrina:BAAALgAECgIJAwAAAA==.Zerosouls:BAAALgAECgYJBwAAAA==.Zerowolf:BAAALgAECgYJCwAAAA==.',
Zh='Zhaann:BAAALgAECgIJAgAAAA==.',
Zo='Zokor:BAAALgADCgkJDwAAAA==.Zorach:BAAALgAECgEJAQAAAA==.',
['Zá']='Zárá:BAAALgAECgYJEgAAAA==.',
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

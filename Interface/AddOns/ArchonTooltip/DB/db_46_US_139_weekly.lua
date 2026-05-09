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

local lookup = {'Priest-Holy','Priest-Shadow','Priest-Discipline','Monk-Mistweaver','Druid-Restoration','Rogue-Assassination','Warlock-Destruction','Mage-Frost','Unknown-Unknown','DeathKnight-Unholy','DemonHunter-Havoc','DemonHunter-Devourer','DeathKnight-Blood','Paladin-Holy','Paladin-Retribution','Paladin-Protection','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','Druid-Guardian','Druid-Balance','Shaman-Restoration','Shaman-Elemental','Monk-Brewmaster','Shaman-Enhancement','Rogue-Subtlety','Hunter-BeastMastery','Mage-Arcane','Monk-Windwalker','DeathKnight-Frost','Warlock-Demonology','Druid-Feral','Hunter-Marksmanship','Warrior-Fury','Warrior-Arms','Warrior-Protection','Mage-Fire','Warlock-Affliction','Hunter-Survival','Rogue-Outlaw',}
local provider = {region='US',realm='LaughingSkull',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Ablucia:BAAALgADCgUJCQAAAA==.',
Ac='Achannara:BAAALgADCgcJBwAAAA==.',
Ae='Aennisong:BAAALgAECgMJAwAAAA==.Aeoliana:BAAALgAECggJEgAAAA==.',
Aj='Ajier:BAABLgAECn8tAAIBAAkJKRahFgAnAgABAAkJKRahFgAnAgAAAA==.',
Al='Aleraz:BAACLgAFFH8LAAMBAAMJNCCZCwASAQABAAMJNCCZCwASAQACAAMJIQ6rEgDyAAAuAAQKfywABAEACQnuH98VAC0CAAEABwncIN8VAC0CAAIACQmDGZMMAP0BAAMAAwkmBzY2AH4AAAAA.Allcapwne:BAAALgAECgQJBAAAAA==.Allenduin:BAAALgAECgYJBwAAAA==.Alshau:BAABLgAECn8aAAIEAAcJ0BdaIwCYAQAEAAcJ0BdaIwCYAQAAAA==.Alucart:BAAALgADCgMJAwAAAA==.',
Am='Ambrosia:BAAALgAECgYJDwAAAA==.Amity:BAAALgADCgkJEAABLgAECggJHQAFANceAA==.',
An='Anewrbyss:BAAALgAECgUJDwAAAA==.Angela:BAABLgAECn8jAAIDAAkJgRj8BgB9AgADAAkJgRj8BgB9AgAAAA==.Anna:BAAALgAECgQJBQAAAA==.Annalunà:BAAALgADCgIJAgAAAA==.Annälise:BAAALgADCgEJAQAAAA==.',
Ap='Apeople:BAABLgAECn8oAAIGAAkJViFYAQAiAwAGAAkJViFYAQAiAwAAAA==.Apocalýpsè:BAAALgAECgEJAQAAAA==.Applebottum:BAAALgAECgYJDAAAAA==.Appärition:BAABLgAECn8eAAIHAAgJ3hsAAgBAAgAHAAgJ3hsAAgBAAgAAAA==.',
Ar='Arleance:BAAALgADCgcJFAAAAA==.Arondael:BAABLgAECn8VAAIGAAgJThLGBADAAQAGAAgJThLGBADAAQAAAA==.Arsène:BAAALgADCgcJCwAAAA==.',
As='Aszun:BAAALgADCgUJBQAAAA==.',
Au='Aurialis:BAAALgAECgcJDQAAAA==.',
Av='Avanti:BAABLgAECn8hAAIIAAYJNBmZTwB7AQAIAAYJNBmZTwB7AQAAAA==.Avendeloria:BAAALgAECgUJBwAAAA==.',
Az='Azrahn:BAAALgADCgEJAQAAAA==.',
['Aü']='Aüra:BAAALgAECgEJAQABLgAECgUJCQAJAAAAAA==.',
Ba='Backmoist:BAAALgAECgMJBAAAAA==.Bagmaster:BAACLgAFFH8FAAIBAAIJHiPXEADLAAABAAIJHiPXEADLAAAuAAQKfy8AAgEACQkAJpkCAD0DAAEACQkAJpkCAD0DAAAA.Baktolife:BAAALgAECgkJBAAAAA==.Bam:BAAALgAECgQJBQABLgAFFAIJBgAKAJshAA==.Bartholomoo:BAABLgAECn8vAAIKAAgJOyNiCQDJAgAKAAgJOyNiCQDJAgAAAA==.Bayonetta:BAAALgAECgcJDAAAAA==.',
Be='Beeftornado:BAAALgAECgQJBAAAAA==.Belakor:BAAALgADCgIJAgAAAA==.Ber:BAAALgAECgEJAQAAAA==.',
Bi='Bigbusta:BAAALgADCgMJAwAAAA==.Bildros:BAAALgAECgEJAQAAAA==.Birgite:BAAALgAECgYJDAAAAA==.Bizniz:BAAALgAECgYJDAAAAA==.',
Bl='Blastin:BAAALgADCgcJBwAAAA==.Blazefury:BAAALgAECgQJEQAAAA==.Blazeknight:BAABLgAECn8gAAILAAcJrxmBFgAXAgALAAcJrxmBFgAXAgAAAA==.Blazemaker:BAABLgAECn8VAAIIAAYJPBD4bwAxAQAIAAYJPBD4bwAxAQAAAA==.Blazemaster:BAAALgAECgQJCAAAAA==.Blinduru:BAACLgAFFH8HAAIMAAMJphoeLAABAQAMAAMJphoeLAABAQAuAAQKfykAAgwACQluIvwEAOECAAwACQluIvwEAOECAAAA.Blitz:BAAALgAECgIJAgAAAA==.Blocktor:BAAALgAECgMJAwABLgAECgYJHAAMANkOAA==.Bluberriez:BAAALgAECgYJBgAAAA==.',
Bo='Bobbiepines:BAAALgAECgEJAQAAAA==.Booza:BAAALgAECgIJAgAAAA==.Borkenshwang:BAAALgADCgYJCwAAAA==.Boydik:BAAALgAECgQJBQAAAA==.',
Bp='Bpaìn:BAAALgAECgYJEQAAAA==.',
Br='Brewlïth:BAAALgAECgIJAgABLgAFFAUJCwANAPAfAA==.Brink:BAAALgAECgUJBwAAAA==.Brojac:BAAALgAECgcJDgAAAA==.Brokil:BAAALgADCggJDAAAAA==.Bromaster:BAAALgAECgQJBAAAAA==.Brones:BAAALgAECgcJAQAAAA==.Brossiere:BAABLgAECn8WAAQOAAgJiBoBIACHAQAOAAUJiRkBIACHAQAPAAYJmBHNqAAwAQAQAAUJGhX9FQDuAAAAAA==.Brotemic:BAAALgADCgcJBwAAAA==.Bru:BAABLgAECn8jAAIBAAkJdhzsDACGAgABAAkJdhzsDACGAgAAAA==.Brutalizèr:BAAALgADCgYJBgABLgAECgEJAQAJAAAAAA==.',
Bu='Bullsmcgee:BAABLgAECn8lAAMKAAgJoCP1CADOAgAKAAgJoCP1CADOAgANAAEJAAASQwA9AAAAAA==.Burninghunt:BAAALgADCgYJBgAAAA==.Burningtree:BAAALgAECgYJEQAAAA==.Burny:BAAALgADCgEJAQAAAA==.Burrder:BAAALgADCggJCAAAAA==.Bustdown:BAAALgADCggJDwAAAA==.Buttslapper:BAAALgADCggJCAAAAA==.',
['Bö']='Börck:BAAALgADCgUJBQAAAA==.',
['Bø']='Bøb:BAAALgAECggJCwAAAA==.',
Ca='Camamoonmana:BAABLgAECn8YAAIFAAkJvBMDIgC2AQAFAAkJvBMDIgC2AQAAAA==.Captcorndog:BAABLgAECn8cAAQRAAgJhxGtFAChAQARAAgJhxGtFAChAQASAAUJ8wN0OACnAAATAAEJAACuQAAvAAAAAA==.Catdog:BAABLgAECn8ZAAIUAAYJExfQDwB8AQAUAAYJExfQDwB8AQAAAA==.Catechism:BAABLgAECn8WAAIOAAcJjh1hDQA/AgAOAAcJjh1hDQA/AgAAAA==.',
Ce='Cemeo:BAAALgAECgcJEwAAAA==.Cerberusalfa:BAACLgAFFH8FAAILAAIJXCSECwDYAAALAAIJXCSECwDYAAAuAAQKfywAAgsACQnTJVkDAE4DAAsACQnTJVkDAE4DAAAA.',
Ch='Chaintazer:BAAALgADCgYJBgABLgAECgYJEAAJAAAAAA==.Chewbaca:BAAALgAECgEJAwAAAA==.Chickennuggi:BAABLgAECn8dAAIIAAYJLBwDQQCkAQAIAAYJLBwDQQCkAQAAAA==.Chiphoof:BAAALgAECgYJEQAAAA==.Chocofox:BAAALgAECgYJEAAAAA==.Chokemagic:BAAALgAECgEJAgAAAA==.Chopndot:BAAALgAECgEJBAAAAA==.Chozen:BAAALgADCgcJBwAAAA==.Chrill:BAAALgAECgUJBgAAAA==.',
Cl='Claraabun:BAAALgAECgUJBQABLgAFFAUJEgAOADgSAA==.Clarabuns:BAACLgAFFH8SAAIOAAUJOBKwCgB2AQAOAAUJOBKwCgB2AQAuAAQKfxYAAg4ACQnGF2QlAPsBAA4ACQnGF2QlAPsBAAAA.Clarasbuns:BAAALgADCgQJBAABLgAFFAUJEgAOADgSAA==.Clawdragoon:BAECLgAFFH8JAAMVAAQJxQaNFQAAAQAVAAQJxQaNFQAAAQAFAAMJ/ABFMQCEAAAuAAQKfykAAxUACAnVGWcUAG8CABUACAnVGWcUAG8CAAUABQkwBNmbAJQAAAAA.',
Co='Coati:BAAALgADCgYJBgAAAA==.Colosie:BAAALgAECgYJEwAAAA==.Comegetpsalm:BAABLgAECn8rAAIOAAgJghu7DABJAgAOAAgJghu7DABJAgAAAA==.',
Cr='Creamsock:BAAALgAECgQJCQAAAA==.Creatlach:BAACLgAFFH8OAAIWAAUJOhhdCACTAQAWAAUJOhhdCACTAQAuAAQKfzcAAxYACAlPHTkOAFQCABYACAlPHTkOAFQCABcAAwlXE2hjALUAAAAA.Creech:BAAALgADCgIJAgAAAA==.Creeptoken:BAAALgADCggJDwAAAA==.Crucifilth:BAAALgADCgYJDAAAAA==.Cryopathy:BAAALgAECgYJDgAAAA==.Crypty:BAABLgAECn8dAAMXAAkJggzmFQCjAQAXAAkJggzmFQCjAQAWAAUJrREdXQAWAQAAAA==.',
Cy='Cyaniidee:BAAALgADCgcJBwAAAA==.Cytherea:BAABLgAECn8YAAIPAAYJqQ07cwAGAQAPAAYJqQ07cwAGAQAAAA==.',
Da='Daddybod:BAABLgAECn8dAAIYAAgJhhKvFACXAQAYAAgJhhKvFACXAQAAAA==.Dalinek:BAAALgAECgUJBQAAAA==.Darktaynt:BAAALgAECgMJBQAAAA==.Darthfox:BAAALgAECgMJAwAAAA==.',
De='Deadsean:BAAALgAECgUJDAAAAA==.Deathtracker:BAAALgAECgcJDQAAAA==.Deathwarden:BAAALgAECgYJCwAAAA==.Deathñdk:BAAALgADCgEJAQAAAA==.Debuffed:BAAALgAECgEJAQAAAA==.Delathor:BAAALgAECgcJBwAAAA==.Demise:BAABLgAECn8fAAIIAAgJuR03MQCtAgAIAAgJuR03MQCtAgAAAA==.Demonclem:BAAALgAECggJDAAAAA==.Demonskinner:BAAALgADCgUJBQAAAA==.Denzo:BAAALgAECgMJAwAAAA==.Deoxyrybo:BAABLgAECn8yAAMLAAkJZBYjBgBHAgALAAkJZBYjBgBHAgAMAAYJpwuNiAAUAQAAAA==.Destructor:BAAALgAECgcJEwAAAA==.Devourera:BAAALgAECgYJEQAAAA==.',
Di='Died:BAAALgADCgMJAwAAAA==.Dilldobaggin:BAAALgADCgQJBAAAAA==.Dinopriest:BAAALgAECgcJEQAAAA==.Distia:BAAALgAECgYJBwAAAA==.Divinedragon:BAABLgAECn8cAAMCAAgJZxM5EQDCAQACAAgJZxM5EQDCAQADAAcJ5grkLgAoAQAAAA==.Dixoncider:BAAALgAECgQJBgAAAA==.',
Do='Doboy:BAAALgADCgIJAgAAAA==.Donmanuel:BAAALgADCgEJAQAAAA==.',
Dr='Drackaris:BAAALgADCgYJBgAAAA==.Drainbamage:BAAALgAECgMJAwAAAA==.Drakin:BAABLgAECn8jAAIPAAkJkxgKJQDuAQAPAAkJkxgKJQDuAQAAAA==.Dreya:BAABLgAECn8ZAAIZAAgJrB74AwA0AgAZAAgJrB74AwA0AgAAAA==.Drinkcoolaid:BAAALgAECgcJEgAAAA==.Dritzle:BAABLgAECn8aAAMaAAgJ/xR8EgCFAQAaAAgJ/xR8EgCFAQAGAAQJHgi4EwDEAAAAAA==.Droopapi:BAAALgAECgYJEQAAAA==.',
Du='Dutchman:BAACLgAFFH8SAAIbAAUJmCQtAwCrAQAbAAUJmCQtAwCrAQAuAAQKfxwAAhsACAkNIWgIAAsDABsACAkNIWgIAAsDAAAA.',
Eh='Ehhmuh:BAAALgAECgQJBgAAAA==.Ehlumii:BAABLgAECn8UAAIEAAYJRSRrDgBwAgAEAAYJRSRrDgBwAgAAAA==.',
Ei='Eiffel:BAAALgADCgUJBQAAAA==.',
El='Eldrene:BAABLgAECn8mAAMIAAgJehulHAA+AgAIAAgJehulHAA+AgAcAAEJ7hOVHAA6AAAAAA==.Elethil:BAAALgADCgEJAQAAAA==.Elfstomper:BAAALgADCgcJCAAAAA==.Elitepaladin:BAABLgAECn8nAAIOAAkJGRbeIQAPAgAOAAkJGRbeIQAPAgAAAA==.Ellexi:BAAALgAECgYJDAAAAA==.Elyseia:BAABLgAECn8bAAIbAAcJbQUUcgARAQAbAAcJbQUUcgARAQAAAA==.',
Em='Empkin:BAAALgAECgcJEgAAAA==.',
En='Enof:BAAALgADCgIJAgAAAA==.Enpower:BAAALgADCgYJBgABLgAECggJJgAdAEMcAA==.',
Ep='Epicsause:BAAALgAECgEJAQAAAA==.',
Er='Erelor:BAAALgADCgMJAwAAAA==.',
Es='España:BAEBLgAECn8nAAQNAAkJTho8CgB2AgANAAkJTho8CgB2AgAeAAQJMAsfDADHAAAKAAEJAACZCQEAAAAAAA==.Essdeath:BAAALgADCgkJFwAAAA==.',
Fa='Farael:BAAALgAECgcJBAAAAA==.Farmerbrown:BAAALgAECgIJAwABLgAECggJIQAPAPMhAA==.Fatalmann:BAABLgAECn8WAAMTAAkJzA+QFQCVAQATAAcJqA+QFQCVAQASAAYJNg/gEAAuAQAAAA==.Fatalminn:BAAALgAECgUJCQAAAA==.Fathergob:BAAALgADCgEJAQAAAA==.Fatty:BAAALgADCgYJBgAAAA==.',
Fe='Fenty:BAAALgADCgEJAQAAAA==.Feralhorn:BAAALgAECgEJAQAAAA==.',
Fi='Fingerz:BAAALgADCgIJAgAAAA==.Fintan:BAAALgADCgEJAQAAAA==.',
Fl='Flarestrasz:BAAALgADCgUJCQAAAA==.Flexxar:BAAALgAECgEJAgAAAA==.Flèxion:BAABLgAECn8oAAIKAAgJ/yQACQDOAgAKAAgJ/yQACQDOAgAAAA==.',
Fo='Foskin:BAAALgAECgEJAQABLgAECgYJEAAJAAAAAA==.',
Fr='Frassk:BAABLgAECn8wAAMHAAgJKhV6CwAdAQAHAAYJ+RR6CwAdAQAfAAQJzRB1hwC3AAAAAA==.Freja:BAAALgADCgMJBgAAAA==.Froggystyle:BAAALgAECgUJDQAAAA==.Frostydru:BAABLgAECn8wAAIgAAgJfiGcAgB8AgAgAAgJfiGcAgB8AgAAAA==.Frozat:BAACLgAFFH8SAAISAAYJkBSSBQCdAQASAAYJkBSSBQCdAQAuAAQKfyEAAxIACAkTH4wGANoCABIACAkTH4wGANoCABEAAQmAEZNeAEAAAAAA.Frösting:BAAALgADCgcJDgABLgAECgcJIwAMADIaAA==.',
Fu='Furballieo:BAAALgADCgIJAgAAAA==.',
Ga='Galianem:BAAALgADCgMJAwAAAA==.Gamora:BAAALgAECgYJCQAAAA==.Gandon:BAAALgAECgQJBAAAAA==.Garbarn:BAABLgAECn8UAAIPAAkJ0g9bNwChAQAPAAkJ0g9bNwChAQAAAA==.Garonno:BAAALgADCgIJAgAAAA==.',
Ge='Gelystine:BAAALgADCgUJCgAAAA==.Geminirunes:BAAALgADCgYJBgABLgAECggJJgAdAEMcAA==.Germaine:BAAALgAECgQJBQAAAA==.',
Gh='Ghabi:BAAALgAECgYJBgAAAA==.Ghauri:BAAALgAECgMJAwAAAA==.',
Gi='Gia:BAABLgAECn8iAAIEAAgJBhVJEgDSAQAEAAgJBhVJEgDSAQAAAA==.',
Go='Gobx:BAAALgAECgUJBgAAAA==.Golgroth:BAAALgAECgYJEgAAAA==.Goodtimesm:BAAALgAECgEJAQAAAA==.Goodtymes:BAAALgAECgEJAQAAAA==.Gorearrow:BAABLgAECn8wAAMbAAkJVyLYCwDjAgAbAAkJVyLYCwDjAgAhAAIJVgdfegBZAAAAAA==.Goretaint:BAAALgAECgYJCQAAAA==.Gorgesh:BAAALgADCgQJBAAAAA==.Gothladriel:BAAALgAECgYJCwAAAA==.Gottamoo:BAAALgAECgkJDwAAAA==.',
Gr='Greenstank:BAAALgADCgMJAwABLgAECgUJDQAJAAAAAA==.Grimmtotem:BAAALgADCgQJBAAAAA==.Grrumpybear:BAABLgAECn8vAAIUAAgJOB3uAwBGAgAUAAgJOB3uAwBGAgAAAA==.Grundal:BAAALgADCggJCAAAAA==.',
Gu='Gunafistya:BAAALgAECgIJAgAAAA==.',
['Gú']='Gúildarts:BAAALgADCgEJAQAAAA==.',
Ha='Haannarr:BAAALgAECgIJAgAAAA==.Hairymoodini:BAAALgAECgEJAQAAAA==.Hajin:BAAALgAECgYJCgAAAA==.Hanky:BAAALgAECgQJBAAAAA==.Havòk:BAAALgAECgcJBgAAAA==.Hawthorn:BAAALgAECgMJBQAAAA==.Hazyblades:BAAALgAECgEJAQAAAA==.',
He='Helacookie:BAAALgAECgcJDAAAAA==.Heomors:BAAALgAECgEJAQAAAA==.Hexxan:BAAALgAECgUJDAAAAA==.',
Hi='Hifumi:BAAALgADCgQJBwAAAA==.Hisagu:BAAALgADCgIJAgABLgAECgYJDwAJAAAAAA==.Hiver:BAAALgAECgQJBAAAAA==.',
Ho='Holes:BAAALgADCgYJCAAAAA==.Holier:BAABLgAECn8nAAIPAAgJthLHagCpAQAPAAgJthLHagCpAQAAAA==.Hollows:BAAALgAECgQJBgAAAA==.Holyatrops:BAAALgAECgcJCAABLgAFFAYJFQAfADkaAA==.Hopperstotem:BAAALgAECgIJAgAAAA==.Horuu:BAAALgAECgQJBgAAAA==.Hoyboii:BAAALgADCgYJBgAAAA==.',
Hu='Hulo:BAAALgAECgIJAgAAAA==.Humbled:BAAALgAECgQJBQAAAA==.Hunteress:BAAALgADCgYJBwAAAA==.Huntkoalas:BAAALgAECgMJAwABLgAFFAUJFwAVAKwaAA==.Hurrdurr:BAAALgAECgEJAQAAAA==.',
['Hî']='Hîflax:BAAALgAECgEJAgAAAA==.',
['Hö']='Hölyców:BAAALgADCgQJBAAAAA==.',
Ic='Ichbinstark:BAAALgAECgEJBAAAAA==.',
Id='Idonttcare:BAAALgAECgMJAwAAAA==.',
Ig='Iggnignokt:BAAALgADCgYJBwAAAA==.',
Ih='Ihealnewbs:BAAALgADCgYJDwAAAA==.',
In='Infamus:BAAALgAECgQJCAAAAA==.Invysion:BAABLgAECn8tAAIDAAkJFxGaCwAYAgADAAkJFxGaCwAYAgAAAA==.',
Ir='Irri:BAAALgADCgUJBQAAAA==.',
Ja='Jaidess:BAAALgADCgcJDQAAAA==.',
Je='Jeanjean:BAAALgAECgcJCAAAAA==.Jeannjeann:BAAALgAECggJEgAAAA==.Jediknîght:BAAALgAECgYJBgAAAA==.Jeep:BAACLgAFFH8KAAIbAAQJnhvlDgBeAQAbAAQJnhvlDgBeAQAuAAQKfyMAAhsACAkwJVIEAEoDABsACAkwJVIEAEoDAAAA.Jellybea:BAABLgAECn8jAAIBAAkJbSEwBAASAwABAAkJbSEwBAASAwAAAA==.',
Ji='Jibalynne:BAAALgAECgQJBAAAAA==.Jida:BAAALgAECgEJAQAAAA==.Jiffypop:BAAALgAECgQJBAABLgAECggJIQAiAGEXAA==.Jinwooaura:BAAALgADCgcJBwAAAA==.',
Jo='Johnnycakes:BAAALgADCgMJBQAAAA==.Jonsnowxd:BAAALgADCgYJBgAAAA==.',
Jr='Jrhnbr:BAAALgADCgMJAwAAAA==.',
Ju='Juggnut:BAAALgAECgcJEAAAAA==.Jump:BAAALgAECgQJCgAAAA==.Jurisdiction:BAABLgAECn8UAAIPAAcJ6gembwAOAQAPAAcJ6gembwAOAQAAAA==.',
Jz='Jz:BAAALgADCgQJAwAAAA==.',
['Jì']='Jìnn:BAAALgAECgUJDwAAAA==.',
Ka='Kaan:BAABLgAECn8fAAIFAAcJhiFLEwCbAgAFAAcJhiFLEwCbAgAAAA==.Kadath:BAAALgADCgEJAQAAAA==.Kaeladín:BAAALgAECgUJCAAAAA==.Kagebouzu:BAAALgAECgYJDwAAAA==.Kahlan:BAAALgADCgcJCAABLgAECgYJCgAJAAAAAA==.Kamela:BAAALgAECgYJCAAAAA==.Karael:BAAALgAECgUJEQAAAA==.Karma:BAAALgAECgUJCAAAAA==.Kayliaa:BAAALgAECgkJAQAAAA==.Kazarke:BAAALgADCgcJGAAAAA==.',
Ke='Keho:BAABLgAECn8WAAMYAAcJJglXJwAJAQAYAAcJ8wdXJwAJAQAdAAIJkg6caABqAAAAAA==.Kenalia:BAABLgAECn8gAAIEAAgJARXtEQDWAQAEAAgJARXtEQDWAQAAAA==.Keptalive:BAAALgADCgcJCgAAAA==.Kerzermern:BAAALgAFFAMJAwAAAA==.Kevic:BAAALgAECgcJBwAAAA==.',
Kh='Khamaelion:BAAALgADCgcJDgAAAA==.',
Ki='Kiara:BAABLgAECn8eAAIPAAgJMyDMFABTAgAPAAgJMyDMFABTAgAAAA==.Kiju:BAAALgADCgYJBgAAAA==.Killaban:BAACLgAFFH8FAAIiAAIJEhYDIgCfAAAiAAIJEhYDIgCfAAAuAAQKfy0AAyIACQkfH9gbAG4CACIACQkfH9gbAG4CACMAAwncEFErAJoAAAAA.Killbydeath:BAAALgAECgEJAQAAAA==.Kimberlyhárt:BAABLgAECn8hAAMPAAgJ8yHXEgBkAgAPAAgJ8yHXEgBkAgAOAAEJpwMTaAAqAAAAAA==.Kissmydots:BAABLgAECn8xAAIfAAgJTh3iEwBCAgAfAAgJTh3iEwBCAgAAAA==.Kitja:BAABLgAECn8dAAIBAAcJHR2PCQBRAgABAAcJHR2PCQBRAgAAAA==.Kitla:BAAALgADCgUJBQABLgAECgcJHQABAB0dAA==.',
Kl='Klukai:BAAALgADCgcJCwABLgAECggJHQAFANceAA==.',
Kn='Kneed:BAAALgADCgYJBgAAAA==.',
Ko='Koala:BAAALgAECgQJBQABLgAFFAUJFwAVAKwaAA==.Kohman:BAABLgAECn8aAAIfAAYJ5RTDfABiAQAfAAYJ5RTDfABiAQAAAA==.Konyani:BAAALgADCgUJAQAAAA==.',
Kr='Kraeven:BAAALgADCgEJAQAAAA==.Kregerath:BAAALgADCgIJAgAAAA==.Krftpnk:BAACLgAFFH8OAAILAAQJaiVoAQCiAQALAAQJaiVoAQCiAQAuAAQKfx4AAwsACAmhIjYEADcDAAsACAmhIjYEADcDAAwAAQkAAN3ZAAAAAAAA.Krom:BAABLgAECn8hAAMiAAgJYRcIEQDqAQAiAAgJYRcIEQDqAQAjAAEJPQkwQQAtAAAAAA==.Kronas:BAABLgAECn8UAAIbAAgJsRSpKQCqAQAbAAgJsRSpKQCqAQAAAA==.Kronophyne:BAABLgAECn8xAAIIAAkJ+B3zOgCLAgAIAAkJ+B3zOgCLAgAAAA==.Kronotality:BAABLgAECn81AAINAAgJriP9AgCxAgANAAgJriP9AgCxAgAAAA==.Kronotek:BAAALgAECgYJBgAAAA==.Kronotekken:BAAALgADCgYJBgAAAA==.',
Ku='Kurohitsugî:BAAALgAECgIJBAAAAA==.',
Ky='Kylorai:BAAALgAECgYJDwAAAA==.Kynbrochel:BAAALgAECgEJAQAAAA==.',
La='Laars:BAAALgAECgEJAQAAAA==.Laimaster:BAAALgAECgEJAQAAAA==.Lakiri:BAABLgAECn8hAAIZAAYJXBfjCgBkAQAZAAYJXBfjCgBkAQAAAA==.Landaeda:BAAALgAECgcJDgAAAA==.Lapsu:BAABLgAECn8dAAIdAAkJ/RN5CwACAgAdAAkJ/RN5CwACAgAAAA==.Lascivia:BAABLgAECn8jAAMiAAkJyB5MJgAnAgAiAAkJiBxMJgAnAgAkAAcJZg5iMADBAAAAAA==.Lawhanx:BAAALgADCgEJAQABLgAECggJHwAMANAYAA==.Laylahh:BAAALgADCgMJBAAAAA==.Lazy:BAABLgAECn8WAAMfAAYJyRcgiQBHAQAfAAUJyRcgiQBHAQAHAAIJxQF7YQBLAAAAAA==.',
Le='Leademon:BAABLgAECn8tAAMMAAgJqR+2DgBSAgAMAAgJqR+2DgBSAgALAAIJTRrTWgB2AAAAAA==.Leadmin:BAAALgADCgMJBQABLgAECggJLQAMAKkfAA==.Leadmln:BAAALgADCgcJBwABLgAECggJLQAMAKkfAA==.Leftlane:BAABLgAECn8jAAIWAAgJdCMWAwAiAwAWAAgJdCMWAwAiAwAAAA==.Legato:BAAALgAECgcJCAABLgAFFAYJHAAWADggAA==.Lethalkrits:BAAALgAECgcJAgAAAA==.Leva:BAABLgAECn8dAAIFAAgJ1x67EwAsAgAFAAgJ1x67EwAsAgAAAA==.',
Li='Liberté:BAAALgADCgcJDQAAAA==.Lie:BAABLgAECn8eAAIaAAkJixISEgCKAQAaAAkJixISEgCKAQAAAA==.Lightsdown:BAAALgADCgcJDgAAAA==.Lilbeebs:BAAALgAECgkJEAAAAA==.Lileth:BAAALgAECgkJAgAAAA==.Lilflea:BAAALgAECggJEQAAAA==.Lilzuki:BAAALgAECgYJDgAAAA==.Lilïth:BAACLgAFFH8LAAINAAUJ8B8NCQA8AQANAAUJ8B8NCQA8AQAuAAQKfxsAAg0ABwmDJPIGAMICAA0ABwmDJPIGAMICAAAA.Linguine:BAAALgAECgEJAQABLgAFFAMJCwABADQgAA==.Lisalisa:BAABLgAECn8gAAIWAAYJrxjfKQB0AQAWAAYJrxjfKQB0AQAAAA==.Livan:BAAALgAECgMJAwAAAA==.Livia:BAAALgAECgEJAQAAAA==.',
Lo='Lohzak:BAAALgAECgEJAQAAAA==.Lousier:BAAALgAECgEJAQAAAA==.',
Lu='Lularia:BAAALgADCgIJAgAAAA==.Lumii:BAAALgAECgYJBgABLgAECgYJFAAEAEUkAA==.Lunaa:BAAALgAECgMJAQAAAA==.Lurassa:BAAALgAECgYJDAAAAA==.',
Ly='Lyacon:BAAALgADCgQJBAABLgAECgkJFQAIAEEcAA==.',
['Lä']='Lä:BAEALgAECgcJBwABLgAECgkJDgAJAAAAAA==.',
Ma='Madrie:BAAALgAECgQJBAAAAA==.Maekar:BAAALgAECgUJDgAAAA==.Maelstorm:BAAALgADCgIJAgAAAA==.Mageman:BAAALgADCgYJAgAAAA==.Magicmoo:BAAALgAECgEJAQABLgAECggJIQAPAPMhAA==.Maltis:BAAALgADCgcJCwAAAA==.Mananstuff:BAABLgAECn8xAAIVAAkJAw9FEQDBAQAVAAkJAw9FEQDBAQAAAA==.Manaproblems:BAAALgADCgMJBAAAAA==.Marguerek:BAAALgADCgEJAQAAAA==.Marinara:BAAALgAECgUJCgABLgAECgYJDAAJAAAAAA==.Markamanimal:BAACLgAFFH8OAAIgAAQJiRUnAgBrAQAgAAQJiRUnAgBrAQAuAAQKfx8AAiAACAkrIYYDAPwCACAACAkrIYYDAPwCAAAA.Marnix:BAAALgAECgYJEAAAAA==.',
Me='Medikus:BAABLgAECn8cAAMWAAgJrRvcDQBZAgAWAAgJrRvcDQBZAgAXAAEJcgbFbAApAAAAAA==.Meesoomagi:BAAALgAECgYJBwAAAA==.Menil:BAABLgAECn8XAAMEAAgJwBtSFgAQAgAEAAcJJhpSFgAQAgAdAAQJchbaLADVAAAAAA==.Merryl:BAAALgAECggJDgAAAA==.',
Mi='Midnye:BAAALgADCgYJBgAAAA==.Mike:BAEBLgAECn8tAAMIAAgJYyBEIgAfAgAIAAgJYyBEIgAfAgAlAAEJAADnDABcAAAAAA==.',
Mo='Mockra:BAABLgAECn8uAAMIAAgJlCBzEwB+AgAIAAgJlCBzEwB+AgAcAAIJuBipGgBCAAAAAA==.Monafae:BAAALgADCgUJBQAAAA==.Moohammered:BAAALgADCgQJBgAAAA==.Moolou:BAABLgAECn8gAAIQAAkJoR8hAgChAgAQAAkJoR8hAgChAgAAAA==.Moosé:BAAALgAECgEJAQABLgAECgEJAgAJAAAAAA==.Mootilator:BAAALgADCgYJBgAAAA==.Moraei:BAAALgADCgEJAQAAAA==.Mordew:BAAALgADCgUJBQABLgAECggJJQAKAKAjAA==.Morechie:BAABLgAECn8aAAImAAgJ2Q+yBACOAQAmAAgJ2Q+yBACOAQAAAA==.Mortiferon:BAABLgAECn8jAAIKAAkJ1xl8IQABAgAKAAkJ1xl8IQABAgAAAA==.',
Mu='Muhgunguh:BAAALgADCgYJBgAAAA==.Munnky:BAABLgAECn8YAAIEAAYJih+PEADnAQAEAAYJih+PEADnAQAAAA==.Murmaider:BAAALgADCgIJAgAAAA==.',
My='Mythrandere:BAAALgADCgUJBQAAAA==.',
['Má']='Mánflu:BAABLgAECn8rAAMjAAkJ5B4RAwDiAgAjAAkJ5B4RAwDiAgAiAAcJSRpNNADZAQAAAA==.',
['Mô']='Môrrigãn:BAAALgADCgMJAwAAAA==.',
['Mö']='Mörgänä:BAAALgADCgMJAwAAAA==.',
Na='Naissa:BAAALgAECgEJAwAAAA==.Nakanir:BAAALgAECgYJBgAAAA==.Nalfeign:BAAALgAECgQJBQAAAA==.Napa:BAAALgADCgEJAQABLgAECggJEQAJAAAAAA==.Narn:BAABLgAECn8zAAQRAAgJ5BtRDgDqAQATAAcJrRjSCQBCAgARAAgJgRZRDgDqAQASAAIJLQiAQQBgAAAAAA==.',
Ne='Nealite:BAAALgAECgkJBgAAAA==.Necrotion:BAAALgAECgYJEgAAAA==.Nerrisa:BAABLgAECn8fAAICAAgJdRNwFACfAQACAAgJdRNwFACfAQAAAA==.Nertt:BAAALgADCgYJBgAAAA==.Neublood:BAAALgAECgQJCAAAAA==.',
Ni='Nicodemus:BAAALgAECgUJBQAAAA==.',
No='Noblewarrior:BAACLgAFFH8TAAIiAAUJBx8OBwBpAQAiAAUJBx8OBwBpAQAuAAQKfyUAAiIACAmfJKwEALICACIACAmfJKwEALICAAAA.Noctilus:BAAALgAECgcJCQAAAA==.Nooj:BAACLgAFFH8lAAMGAAgJUCELAAB9AgAGAAgJUCELAAB9AgAaAAYJiRRGAwCoAQAuAAQKfx4AAwYACQl7IToAAMMDAAYACQl7IToAAMMDABoABgmFEos6AEQBAAAA.Notakoala:BAACLgAFFH8XAAIVAAUJrBpRCQBhAQAVAAUJrBpRCQBhAQAuAAQKfyEAAhUACAmuIk8NAMUCABUACAmuIk8NAMUCAAAA.Nothnx:BAAALgAECgEJAwAAAA==.Notoriouspat:BAAALgAECgUJEwAAAA==.Notsamadeath:BAAALgAECgQJBAAAAA==.Novia:BAAALgAECgYJBgAAAA==.Noyber:BAAALgADCgYJBgAAAA==.Noydin:BAAALgAFFAEJAQAAAA==.',
['Nü']='Nüll:BAAALgAECggJDgAAAA==.',
Ob='Obern:BAABLgAECn8UAAInAAkJAhpQCAAjAgAnAAkJAhpQCAAjAgAAAA==.Oblïna:BAABLgAECn8WAAIEAAcJKQZcLQDoAAAEAAcJKQZcLQDoAAAAAA==.',
Od='Odiumaeterna:BAAALgADCgcJBwAAAA==.',
Of='Offensivé:BAAALgAECgMJBwAAAA==.',
On='Onetozerosix:BAABLgAECn8ZAAIKAAkJEhfeLgC+AQAKAAkJEhfeLgC+AQAAAA==.Onsen:BAAALgADCgIJAgAAAA==.',
Oo='Oogak:BAAALgAECgUJBgAAAA==.Oomigig:BAAALgADCgUJBQAAAA==.',
Op='Opalily:BAAALgADCgYJBwAAAA==.Operation:BAAALgAECgQJCAAAAA==.',
Os='Osteer:BAAALgAECgYJBgAAAA==.',
Ot='Otterjim:BAAALgADCgQJBAAAAA==.',
Pa='Pahaa:BAAALgAECgUJBQAAAA==.Pairadeez:BAAALgAECgYJCwAAAA==.Pajamabanana:BAAALgADCgIJAgAAAA==.Pandablaze:BAAALgAECgMJAwAAAA==.Panterarey:BAAALgADCgYJEAAAAA==.Papalego:BAABLgAECn8fAAIbAAgJTQwiMQCJAQAbAAgJTQwiMQCJAQAAAA==.Parakka:BAABLgAECn8iAAIWAAkJ8REJFgADAgAWAAkJ8REJFgADAgAAAA==.Pavle:BAAALgADCgYJBgAAAA==.Pawp:BAAALgAECgYJCQABLgAECgcJHgABAPUTAA==.',
Pe='Pearagon:BAAALgAECgYJBgABLgAECggJEQAJAAAAAA==.Pepsidew:BAAALgADCgcJCwAAAA==.Pepsisprite:BAABLgAECn8iAAIBAAgJsxeiDAAbAgABAAgJsxeiDAAbAgAAAA==.Pesky:BAAALgAECgYJDAAAAA==.',
Pf='Pfchanguz:BAAALgADCgcJDAAAAA==.',
Ph='Phdbeef:BAAALgAFFAIJAgABLgAFFAUJCwANAPAfAA==.Phlemm:BAAALgAECgEJAQAAAA==.Phoivos:BAABLgAECn8VAAIIAAkJQRwFIQDvAgAIAAkJQRwFIQDvAgAAAA==.',
Pi='Picklez:BAABLgAECn8XAAIKAAYJ9CGAJADxAQAKAAYJ9CGAJADxAQAAAA==.Pissflizzle:BAABLgAECn8WAAIfAAYJVAnIdADfAAAfAAYJVAnIdADfAAAAAA==.',
Pl='Plaquenil:BAAALgADCgEJAQAAAA==.',
Po='Poison:BAAALgADCgEJAQAAAA==.Porkroaster:BAABLgAECn8UAAIIAAYJ3givggAMAQAIAAYJ3givggAMAQAAAA==.',
Pr='Praye:BAAALgAECgMJAwAAAA==.Priestop:BAAALgAECgEJAQAAAA==.',
Ps='Psyfarian:BAAALgADCgcJDQAAAA==.Psyop:BAAALgAECgEJAQABLgAECgcJCwAJAAAAAA==.',
Qu='Quillswitch:BAAALgAECgEJAQAAAA==.',
Ra='Radduc:BAABLgAECn8WAAMOAAYJZhMsKQBEAQAOAAYJZhMsKQBEAQAPAAEJlQZBEQEvAAAAAA==.Ragerade:BAAALgAECgQJBQAAAA==.Raidu:BAAALgAECgMJAwAAAA==.Ralpherion:BAAALgADCgIJAgAAAA==.Ranoa:BAAALgAECgQJCgAAAA==.Raphåel:BAAALgAECgYJAwAAAA==.Ravioli:BAAALgAECgQJBgAAAA==.Razialum:BAAALgADCgYJBgAAAA==.Razorsteps:BAAALgAFFAUJBAAAAA==.Razzberry:BAAALgADCgYJDAAAAA==.',
Re='Rebrowth:BAAALgAECgUJDQAAAA==.Redren:BAAALgADCgIJAgAAAA==.Reegrets:BAAALgAECggJDQAAAA==.Reena:BAAALgADCgIJAwAAAA==.Regiplague:BAAALgAECgYJCwAAAA==.Regretty:BAAALgAECgcJCgABLgAECggJDQAJAAAAAA==.Renthar:BAAALgADCgUJBQAAAA==.Renzdingo:BAAALgAECgkJDwAAAA==.Repete:BAAALgAECgUJDgAAAA==.Resyek:BAABLgAECn8xAAIIAAgJmyNOCwDIAgAIAAgJmyNOCwDIAgAAAA==.Reverendgank:BAAALgAECgEJAQAAAA==.',
Rh='Rhaxanna:BAAALgADCgYJBgAAAA==.',
Ri='Rick:BAAALgAECgQJBAAAAA==.Riivan:BAABLgAECn8TAAIfAAcJiwslTABFAQAfAAcJiwslTABFAQAAAA==.Rishi:BAABLgAECn8zAAIPAAgJZRPyOwCSAQAPAAgJZRPyOwCSAQAAAA==.Rivian:BAAALgADCgIJAgAAAA==.',
Ro='Robot:BAABLgAECn8eAAIEAAcJtQ8EJgAYAQAEAAcJtQ8EJgAYAQAAAA==.Rokmog:BAAALgADCgUJBQAAAA==.Rollinburn:BAAALgADCgYJCQAAAA==.Roxanol:BAAALgADCgEJAQABLgAECggJKwAOAIIbAA==.',
Ru='Rumbrave:BAAALgAECgYJCwAAAA==.Rumtumtugger:BAAALgADCgkJCQAAAA==.',
['Rá']='Ráyune:BAAALgADCgcJBwAAAA==.',
Sa='Sackos:BAAALgAECgEJAQAAAA==.Sadpanda:BAAALgADCgUJCAAAAA==.Saffronspark:BAAALgADCgkJGQABLgAECgkJLgAdAMofAA==.Sainsei:BAAALgAECgUJCAAAAA==.Saith:BAAALgAECgEJBQAAAA==.Samasear:BAABLgAECn8UAAIiAAgJ0w8tMgDjAQAiAAgJ0w8tMgDjAQABLgAFFAUJEwAKACMfAA==.Sandwitch:BAABLgAECn8xAAMfAAgJTxaFIADuAQAfAAgJTxaFIADuAQAHAAIJmxBuUwB0AAAAAA==.Sargatana:BAABLgAECn8hAAIYAAkJIBaKCgAaAgAYAAkJIBaKCgAaAgAAAA==.Sars:BAABLgAECn8UAAMEAAYJZiZOBgCfAgAEAAYJZiZOBgCfAgAdAAMJGhN8MgC6AAAAAA==.Sauronxd:BAAALgAECgUJCAAAAA==.',
Sc='Scalion:BAABLgAECn8fAAMMAAgJ0BhEOgBNAQAMAAgJ0BhEOgBNAQALAAQJ+BG7SwDAAAAAAA==.Scarne:BAAALgADCgEJAQAAAA==.Schrodinger:BAAALgAECgcJEgAAAA==.',
Se='Selunee:BAAALgADCgEJAQAAAA==.Sepharad:BAAALgADCggJEgAAAA==.Septicflësh:BAAALgADCgEJAQAAAA==.Severum:BAABLgAECn8mAAIkAAgJlBqtBgAjAgAkAAgJlBqtBgAjAgAAAA==.',
Sh='Shadowtiger:BAABLgAECn8eAAIbAAgJzAZ3PgBUAQAbAAgJzAZ3PgBUAQAAAA==.Shadrad:BAAALgAECgkJEwAAAA==.Shamanor:BAEALgAECgcJCAAAAA==.Shammoo:BAAALgAECgEJAgAAAA==.Shantz:BAABLgAECn8bAAINAAcJ1QwTFwAXAQANAAcJ1QwTFwAXAQAAAA==.Shirtless:BAAALgAECggJEQAAAA==.Shockra:BAABLgAECn8dAAIXAAkJ4xcmDQAKAgAXAAkJ4xcmDQAKAgAAAA==.Shortbuss:BAAALgADCgYJEgAAAA==.',
Si='Sige:BAAALgADCgYJBgAAAA==.Sillygoose:BAAALgADCgkJDwAAAA==.Silx:BAABLgAECn8VAAMDAAcJMBE7IQCJAQADAAcJMBE7IQCJAQACAAEJoBY9XQA/AAAAAA==.Simvastatin:BAAALgADCgQJBAAAAA==.Sinterdeath:BAAALgAECgIJAgAAAA==.',
Sk='Skulltide:BAAALgADCgcJCQAAAA==.',
Sl='Slaggz:BAAALgADCgQJBAAAAA==.Slamvoke:BAAALgAECgEJAQABLgAFFAQJCgAiAI4OAA==.Slowrot:BAAALgADCgEJAQABLgAECggJIQAPAPMhAA==.Slâte:BAAALgAFFAEJAgAAAA==.',
Sm='Smiteasaurus:BAAALgAECgEJAQAAAA==.Smorthian:BAAALgAECgcJDQAAAA==.',
Sn='Snarll:BAAALgADCgEJAQAAAA==.Sniffinsteak:BAAALgAECggJCQAAAA==.',
So='Somaliabiggs:BAAALgAECgYJCgAAAA==.Sorraba:BAAALgAECgQJBAAAAA==.Sorrabo:BAAALgAECgUJBQAAAA==.Soryan:BAAALgAECggJEAAAAA==.Sosalkin:BAAALgAECgcJEQAAAA==.Souls:BAACLgAFFH8NAAIfAAMJbCFLGQAnAQAfAAMJbCFLGQAnAQAuAAQKfxwABB8ABwk8IyYXAMkCAB8ABwk8IyYXAMkCACYAAQkAAPEfAHIAAAcAAQm1Gj9iAEoAAAAA.',
Sp='Spankenstine:BAABLgAECn8XAAMPAAgJkBW0NgCjAQAPAAgJkBW0NgCjAQAOAAUJowh3YwDuAAABLgABCgYJCwAJAAAAAA==.Spannky:BAAALgADCgYJCgABLgAECgYJGAAEAIofAA==.',
Sq='Squishÿ:BAAALgAECgYJDwAAAA==.',
St='Starshriek:BAAALgADCgcJBwAAAA==.Stinkyfree:BAABLgAECn8bAAIYAAYJzBjOLgCcAQAYAAYJzBjOLgCcAQAAAA==.Stinkynatto:BAAALgADCgYJBgABLgAECgYJGwAYAMwYAA==.Stormcharred:BAABLgAECn8eAAIIAAgJ6SCbKADQAgAIAAgJ6SCbKADQAgAAAA==.Stormknight:BAAALgAECgQJBgAAAA==.Straka:BAABLgAECn8ZAAIFAAgJmhMWPgCrAQAFAAgJmhMWPgCrAQAAAA==.',
Su='Suffers:BAAALgAECgEJAQAAAA==.Suneater:BAAALgAECgEJAQAAAA==.Supaheals:BAAALgAECgEJAQAAAA==.Superdruid:BAAALgADCgUJBQABLgAFFAYJEQAPABkeAA==.Supermonks:BAAALgAECgQJBAABLgAFFAYJEQAPABkeAA==.Superpi:BAABLgAECn8UAAIDAAYJ4h5XCwAcAgADAAYJ4h5XCwAcAgABLgAFFAYJEQAPABkeAA==.Superret:BAACLgAFFH8RAAIPAAYJGR72DgBsAQAPAAYJGR72DgBsAQAuAAQKfyEAAg8ACAn+IfUOABYDAA8ACAn+IfUOABYDAAAA.Superskeet:BAABLgAECn8lAAIOAAgJeBdsDwAlAgAOAAgJeBdsDwAlAgAAAA==.',
Sw='Swaggbag:BAAALgADCgEJAQAAAA==.Swiftia:BAABLgAECn8VAAMhAAYJlBZPOwBzAQAhAAYJjhRPOwBzAQAbAAUJAg0KaADZAAAAAA==.Swiftybutt:BAAALgAECggJCgAAAA==.',
Sy='Sylphièl:BAACLgAFFH8HAAMGAAQJ+AGzAwATAQAGAAQJvQGzAwATAQAoAAEJqQJgAgBEAAAuAAQKfyIAAwYACAnyC3oGAIUBACgACAmbCq0EALkBAAYACAnaCXoGAIUBAAAA.Synhunt:BAAALgADCgYJBwAAAA==.Synicc:BAAALgAECgEJAQAAAA==.Syrene:BAAALgAECgMJBgAAAA==.',
Ta='Tandarì:BAACLgAFFH8LAAIPAAQJURsADgBxAQAPAAQJURsADgBxAQAuAAQKfx4AAg8ACQlJHqYPABEDAA8ACQlJHqYPABEDAAAA.Tano:BAAALgAECgUJBwABLgAECggJLgAIAJQgAA==.Tanparo:BAAALgAECgMJAwAAAA==.Tarick:BAAALgAECgEJAQAAAA==.Tasty:BAAALgAECgQJCwAAAA==.Tawnii:BAAALgADCgcJEgAAAA==.Taírn:BAAALgAECgYJDwAAAA==.',
Te='Tehpredator:BAAALgAECgIJAwAAAA==.Teilin:BAACLgAFFH8cAAIWAAYJOCDPAQAeAgAWAAYJOCDPAQAeAgAuAAQKfyIAAhYACQmQI7MEACcDABYACQmQI7MEACcDAAAA.',
Th='Theaterthug:BAAALgADCgcJFQAAAA==.Thehulkster:BAAALgAECgMJAwAAAA==.Thetinman:BAAALgAECgEJAQAAAA==.Thevelo:BAAALgAECgEJAQABLgAECgQJBQAJAAAAAA==.Theßigshot:BAABLgAECn8VAAIFAAYJICO9IgAyAgAFAAYJICO9IgAyAgAAAA==.Thoseheals:BAAALgADCgQJBAAAAA==.Thunderskeet:BAABLgAECn8sAAMMAAgJoiPQBQDPAgAMAAgJoiPQBQDPAgALAAcJWB0MFAAyAgAAAA==.Thundurus:BAACLgAFFH8FAAIXAAIJWxQtIQCbAAAXAAIJWxQtIQCbAAAuAAQKfyQAAhcACAnWFE8dAGMBABcACAnWFE8dAGMBAAAA.',
Ti='Timmayy:BAABLgAECn8kAAIfAAgJCBZzOQAmAgAfAAgJCBZzOQAmAgAAAA==.Tindrill:BAABLgAECn8aAAIjAAkJUSGTAwDKAgAjAAkJUSGTAwDKAgAAAA==.Tireiron:BAAALgADCgYJBgAAAA==.',
To='Tomraedisk:BAAALgAECgYJEAAAAA==.Totemagoat:BAACLgAFFH8QAAMWAAUJoxsmFAAkAQAWAAQJzxgmFAAkAQAXAAMJ6wNjJgCBAAAuAAQKfysAAxYACQkvFdUsANcBABYACAkYE9UsANcBABcACAmjGOQfAFABAAAA.Totemlyfine:BAABLgAECn8jAAMWAAcJ2yI3CgCKAgAWAAcJ2yI3CgCKAgAXAAEJ6hVnXQBAAAAAAA==.Totesmugoats:BAAALgAECggJEgAAAA==.Toxicshock:BAAALgADCgEJAQAAAA==.',
Tr='Traprkeepr:BAAALgADCgcJDQAAAA==.Treechains:BAABLgAECn8WAAMWAAYJ8hflJgCGAQAWAAYJ8hflJgCGAQAXAAEJZQPnkQAlAAAAAA==.Treefist:BAAALgADCgMJAwAAAA==.Treeshield:BAAALgADCgYJBgAAAA==.Trickster:BAAALgAECgEJAQAAAA==.Truth:BAAALgADCgcJDQAAAA==.',
Tu='Turbobis:BAAALgAECgIJAgAAAA==.',
Tw='Twentyfour:BAABLgAECn8UAAIFAAcJhhDiXQA4AQAFAAcJhhDiXQA4AQAAAA==.Twigberry:BAAALgAECgUJCAAAAA==.',
Ty='Typeshxxt:BAAALgADCgEJAQAAAA==.Tytanea:BAAALgAECgIJAgAAAA==.',
['Tø']='Tøqa:BAAALgAFFAEJAQAAAA==.',
Uh='Uhnderstood:BAABLgAECn8mAAIEAAkJjh1lEABUAgAEAAkJjh1lEABUAgAAAA==.',
Un='Undeadmonks:BAABLgAECn8nAAMYAAgJHhHfGABvAQAYAAgJQxDfGABvAQAdAAMJdgq6ZQB2AAAAAA==.',
Va='Vahe:BAAALgAECgEJAQAAAA==.Vale:BAAALgAECgQJBAAAAA==.Valeshot:BAABLgAECn8eAAIbAAkJ7AhpPwCxAQAbAAkJ7AhpPwCxAQAAAA==.Valkillrie:BAAALgADCgcJBwAAAA==.Vall:BAAALgAECgMJBAAAAA==.Valssra:BAABLgAECn8XAAIIAAcJmAqtZABIAQAIAAcJmAqtZABIAQAAAA==.Vampiricvrus:BAAALgAECgQJBgAAAA==.',
Ve='Vedbow:BAACLgAFFH8MAAQnAAQJ2CAVAgCdAQAnAAQJ2CAVAgCdAQAbAAIJgw//PACgAAAhAAEJgA+tJwBNAAAuAAQKfxgABBsACAmkIh8UAJUCABsACAmzIR8UAJUCACEABAnyHxs8AG4BACcAAgnoG84qAKIAAAAA.Vedronas:BAAALgAECgcJEwAAAA==.Venlii:BAAALgADCgEJAQAAAA==.Verdict:BAAALgADCgcJDQAAAA==.Vern:BAABLgAECn8YAAMDAAgJ+RfwDwDUAQADAAgJ+RfwDwDUAQACAAIJgwYiWQBWAAAAAA==.Vernah:BAAALgAECggJDgABLgAECggJGAADAPkXAA==.Verybad:BAABLgAECn9EAAIIAAYJpRwsSwCHAQAIAAYJpRwsSwCHAQAAAA==.',
Vo='Voidify:BAAALgADCgEJAgAAAA==.Voodoodrood:BAAALgADCgIJAgAAAA==.',
['Vè']='Vèronique:BAAALgADCgYJBgAAAA==.',
Wa='Waamchifu:BAABLgAECn8jAAIYAAgJ0x3YBgBmAgAYAAgJ0x3YBgBmAgAAAA==.Wack:BAAALgADCgUJBgAAAA==.Waka:BAAALgADCgcJCwAAAA==.Waltersight:BAAALgAECgcJCwAAAA==.',
We='Wesker:BAAALgADCgYJBgAAAA==.Westavia:BAAALgADCgMJAwABLgAECggJIQAPAPMhAA==.Wewabear:BAAALgADCgQJBAAAAA==.',
Wh='Whateley:BAAALgAECgcJCgAAAA==.Whosthetänk:BAAALgAECgEJAQAAAA==.',
Wi='Wisebrownguy:BAABLgAECn8dAAIPAAYJBh7YMQC1AQAPAAYJBh7YMQC1AQABLgAECgYJEAAJAAAAAA==.',
Wo='Worgana:BAAALgAECgMJAwAAAA==.Wormchild:BAAALgADCgQJBAAAAA==.',
Wu='Wukòng:BAAALgADCgEJAQAAAA==.',
Xi='Xikar:BAAALgAECgQJCAAAAA==.',
Ye='Yeddy:BAAALgADCgcJBwAAAA==.Yel:BAAALgADCgYJCAAAAA==.',
Yo='Yoel:BAAALgADCgEJAQAAAA==.',
Yu='Yudah:BAACLgAFFH8FAAMnAAMJDQ7dDwD2AAAnAAMJDQ7dDwD2AAAbAAEJ2QG7VAA+AAAuAAQKfyMABCcACAkWGCMIACYCACcACAkWGCMIACYCACEABQm/ChhZAOEAABsABwmpCptyALwAAAAA.Yuta:BAAALgADCgcJBgAAAA==.',
Za='Zalrei:BAAALgADCgYJBgAAAA==.Zalupa:BAAALgAECgIJAgAAAA==.Zanghonghua:BAABLgAECn8uAAMdAAkJyh96AgDsAgAdAAkJyh96AgDsAgAEAAEJSRXTZAA+AAAAAA==.Zarinaria:BAABLgAECn8cAAIMAAYJ2Q7lfQAvAQAMAAYJ2Q7lfQAvAQAAAA==.',
Zh='Zhael:BAABLgAECn8bAAIMAAgJFRy4GAD3AQAMAAgJFRy4GAD3AQAAAA==.',
Zo='Zodstrike:BAABLgAECn8VAAMMAAYJ6gPgfQCbAAAMAAYJ6gPgfQCbAAALAAQJnwITWACGAAAAAA==.Zomara:BAAALgAECgIJBgAAAA==.Zooboo:BAAALgAECgcJEwAAAA==.Zophie:BAAALgADCgEJAQAAAA==.',
['Är']='Ärcane:BAAALgAECgkJBgAAAA==.',
['Äú']='Äúra:BAAALgAECgUJCQAAAA==.',
['Åi']='Åir:BAAALgADCgIJAgAAAA==.',
['Ðô']='Ðôôm:BAAALgAECgEJAQAAAA==.',
['Öv']='Överpöwered:BAAALgADCgIJAgAAAA==.',
['Öð']='Öðïn:BAAALgADCgQJBAAAAA==.',
['ßl']='ßlisster:BAAALgADCgYJBgAAAA==.',
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

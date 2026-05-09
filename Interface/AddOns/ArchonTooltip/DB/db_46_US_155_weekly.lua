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

local lookup = {'Rogue-Subtlety','Rogue-Assassination','Druid-Restoration','Druid-Balance','DemonHunter-Devourer','Mage-Frost','Druid-Feral','Monk-Mistweaver','DeathKnight-Unholy','Unknown-Unknown','Paladin-Holy','Paladin-Retribution','Evoker-Augmentation','Evoker-Devastation','Druid-Guardian','Evoker-Preservation','Shaman-Restoration','Mage-Fire','Priest-Shadow','Shaman-Enhancement','Priest-Holy','Paladin-Protection','DemonHunter-Havoc','Priest-Discipline','Warlock-Demonology','Warrior-Fury','Shaman-Elemental','Warrior-Arms','Rogue-Outlaw','Hunter-Survival','DeathKnight-Blood','Monk-Brewmaster','Warrior-Protection','Warlock-Destruction','Hunter-Marksmanship','Hunter-BeastMastery','DemonHunter-Vengeance','Monk-Windwalker','DeathKnight-Frost','Mage-Arcane','Warlock-Affliction',}
local provider = {region='US',realm='Medivh',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abashai:BAABLgAECn8dAAMBAAgJnhr3CAATAgABAAgJnhr3CAATAgACAAEJoAzVIAAuAAAAAA==.Abashot:BAAALgADCgMJAwABLgAECggJHQABAJ4aAA==.',
Ac='Achicken:BAAALgAECgQJBAAAAA==.',
Ad='Adeathknight:BAAALgAECgYJCwAAAA==.Adetalo:BAAALgADCggJCAAAAA==.Adouken:BAAALgAFFAIJAgAAAA==.',
Ae='Aeliafaelyn:BAAALgADCgkJEAAAAA==.Aellyria:BAABLgAECn8mAAMDAAgJaxARJwCVAQADAAgJaxARJwCVAQAEAAEJUAdWWQAwAAAAAA==.Aeloesh:BAABLgAECn8cAAIFAAcJHhKSOABUAQAFAAcJHhKSOABUAQAAAA==.Aestra:BAACLgAFFH8IAAIGAAUJqwvtOQAoAQAGAAUJqwvtOQAoAQAuAAQKfyIAAgYACQkDHCQeAP0CAAYACQkDHCQeAP0CAAAA.',
Ai='Ailari:BAAALgAECgYJCgAAAA==.Aipasso:BAAALgAECgYJCAAAAA==.',
Ak='Akaili:BAAALgAECgMJBgAAAA==.Aklymydia:BAAALgAECgMJBAAAAA==.',
Al='Aledria:BAAALgADCgUJBQAAAA==.Alexiya:BAABLgAECn8kAAIHAAcJdwlZDwAiAQAHAAcJdwlZDwAiAQAAAA==.Alinoven:BAABLgAECn8fAAIGAAgJtRbIUAB4AQAGAAgJtRbIUAB4AQAAAA==.Allacari:BAAALgAECgYJEwAAAA==.Almace:BAAALgAECggJEQAAAA==.Alucardd:BAAALgAECgMJAwAAAA==.',
An='Angmaro:BAAALgAECgUJCwAAAA==.Anniki:BAAALgAECgQJCgABLgAFFAUJEQAIAF0cAA==.Antibear:BAABLgAECn8mAAIJAAgJcxCYLgC/AQAJAAgJcxCYLgC/AQAAAA==.Antonina:BAAALgADCgYJBgAAAA==.',
Ap='Apetoes:BAAALgADCgIJAgABLgAECgIJAgAKAAAAAA==.Aphrodita:BAAALgAECgEJAwAAAA==.Apito:BAAALgAECgIJAgAAAA==.Apitoo:BAAALgADCgUJBQABLgAECgIJAgAKAAAAAA==.Apol:BAABLgAECn8fAAILAAkJIw8lGADLAQALAAkJIw8lGADLAQAAAA==.',
Ar='Arachne:BAABLgAECn8jAAIGAAkJmhWLLQDrAQAGAAkJmhWLLQDrAQAAAA==.Arakar:BAABLgAECn8gAAMLAAkJmRGbLwDEAQALAAgJ1Q+bLwDEAQAMAAkJOwapxAD+AAAAAA==.Arakina:BAAALgADCgMJAwABLgAECgkJIAALAJkRAA==.Aralynne:BAABLgAECn8hAAMMAAgJYxn/IwD0AQAMAAgJYxn/IwD0AQALAAEJzQFtowAhAAAAAA==.Arch:BAABLgAECn8WAAMNAAYJEg0ULAD5AAANAAYJwwwULAD5AAAOAAMJIQhFOQBPAAAAAA==.Archeus:BAAALgAECgUJBgAAAA==.Archyan:BAAALgADCgEJAQAAAA==.Ariielle:BAAALgAECgEJAQAAAA==.Arlïnn:BAAALgAECgYJBgAAAA==.Armorya:BAABLgAECn8nAAIMAAkJexpHKQCAAgAMAAkJexpHKQCAAgAAAA==.Armyofone:BAAALgAECgYJCgAAAA==.Artaius:BAABLgAECn8mAAIPAAgJNCU5AQDkAgAPAAgJNCU5AQDkAgAAAA==.Artree:BAAALgAECgkJBgAAAA==.',
As='Ashaw:BAAALgADCggJGAAAAA==.Ashwyn:BAABLgAECn8jAAIEAAgJ8QKcMwDBAAAEAAgJ8QKcMwDBAAAAAA==.Astarog:BAABLgAECn8YAAMQAAYJahEyEwALAQAQAAYJahEyEwALAQANAAIJBAP0ZAAgAAAAAA==.',
At='Atafloosy:BAEBLgAECn8qAAIRAAgJPCRdAgA+AwARAAgJPCRdAgA+AwAAAA==.Athammer:BAAALgAECgYJBgAAAA==.Athelf:BAABLgAECn8gAAIMAAkJ7BwQGQDTAgAMAAkJ7BwQGQDTAgAAAA==.Athelfstein:BAAALgAECgYJDAAAAA==.',
Au='Aubrie:BAAALgADCgEJAQAAAA==.Aubriell:BAAALgAECgUJDAAAAA==.Augtistic:BAAALgAECgYJCgAAAA==.',
Av='Avelone:BAAALgADCgMJAwAAAA==.Aviren:BAABLgAECn8XAAIFAAgJoRnXLACEAQAFAAgJoRnXLACEAQAAAA==.',
Ax='Axël:BAAALgADCgYJBgAAAA==.',
Ay='Ayeamamonk:BAAALgADCgkJFwAAAA==.Ayrnerdam:BAAALgAECgYJDwAAAA==.',
Az='Azmadius:BAAALgADCgEJAQAAAA==.Azor:BAAALgAECgQJCAABLgAECgYJBgAKAAAAAA==.',
Ba='Baconbits:BAAALgADCgEJAQAAAA==.Bageldinger:BAAALgAECgEJAwABLgAECgIJAgAKAAAAAA==.Bagelss:BAAALgADCgIJAwABLgAECgIJAgAKAAAAAA==.Bagelstealth:BAAALgADCgcJDAABLgAECgIJAgAKAAAAAA==.Bagleflinger:BAAALgAECgEJAQABLgAECgIJAgAKAAAAAA==.Bairry:BAAALgADCgYJAwAAAA==.Baldhood:BAAALgADCgcJDQABLgAECgcJKQASAFEcAA==.Bamberk:BAAALgAECgkJAQAAAA==.Batarang:BAABLgAECn8fAAIBAAcJBRNrEgCGAQABAAcJBRNrEgCGAQAAAA==.',
Be='Bearbarian:BAABLgAECn8ZAAIPAAcJSQrFFQC5AAAPAAcJSQrFFQC5AAAAAA==.Beardalorian:BAAALgAECgQJBAAAAA==.Beastkael:BAAALgAECgcJEgAAAA==.Bellwhip:BAAALgAECgEJAwABLgAECggJJgAFAK4cAA==.Berghain:BAAALgADCgMJBQAAAA==.Berick:BAABLgAECn8gAAITAAYJaCPpCwAGAgATAAYJaCPpCwAGAgAAAA==.Besaaba:BAABLgAECn8lAAIDAAgJPAaHQAARAQADAAgJPAaHQAARAQAAAA==.',
Bi='Bingo:BAAALgAECgQJBAAAAA==.',
Bl='Blaize:BAAALgADCgEJAQAAAA==.Blax:BAAALgAECgQJCAAAAA==.Blitzwing:BAAALgAECgMJAwAAAA==.Bloodeh:BAAALgAECgQJBgAAAA==.Bloodyaggro:BAAALgAECgUJDAAAAA==.Bloodygrip:BAAALgAECgYJCwAAAA==.Blux:BAAALgAECgQJBAAAAA==.',
Bo='Bodin:BAABLgAECn8bAAIMAAgJiQmFWgA7AQAMAAgJiQmFWgA7AQAAAA==.Bolero:BAABLgAECn8ZAAIUAAcJrwuYDAA/AQAUAAcJrwuYDAA/AQAAAA==.Bonnabelle:BAAALgAECgYJCAAAAA==.Boombawks:BAAALgAECggJEgAAAA==.Boompd:BAAALgAECgYJCAABLgAECggJEgAKAAAAAA==.Bootswidafur:BAAALgADCgYJCAAAAA==.Bos:BAABLgAECn8ZAAMTAAgJdhtEGQByAQATAAYJwxdEGQByAQAVAAcJYhQRHABpAQAAAA==.Bowguy:BAAALgADCgcJBwABLgAFFAQJDAAWAN0PAA==.',
Br='Brasmina:BAAALgAECgcJEAAAAA==.Brazilian:BAABLgAECn8mAAMFAAgJrhzzDwBEAgAFAAgJURzzDwBEAgAXAAQJ2RUlQQD1AAAAAA==.Briest:BAABLgAECn8jAAMYAAgJQR9DCgCVAgAYAAgJQR9DCgCVAgAVAAMJJBc3XQC+AAAAAA==.Brightside:BAABLgAECn8TAAIMAAcJkh5TNwBFAgAMAAcJkh5TNwBFAgAAAA==.Brigid:BAAALgAECgQJBgABLgAFFAUJEQAIAF0cAA==.Brotherconns:BAAALgAECgMJAwAAAA==.Brunadin:BAAALgADCgIJAgAAAA==.Bruneigin:BAAALgAECgUJCwAAAA==.Brunny:BAAALgADCgYJCAABLgAECggJIwAYAEEfAA==.',
Bu='Bubblohsvn:BAAALgAECgEJAQAAAA==.Bubonic:BAAALgAECgQJCQAAAA==.Bureiku:BAABLgAECn8fAAIZAAgJChZKIgDlAQAZAAgJChZKIgDlAQAAAA==.',
Bw='Bwomp:BAABLgAECn8bAAIaAAgJxxWPIwA5AgAaAAgJxxWPIwA5AgAAAA==.',
Ca='Caatos:BAAALgADCgcJDQAAAA==.Caelm:BAAALgADCggJDgAAAA==.Caias:BAAALgAECgUJDgAAAA==.Caldrea:BAAALgADCggJEgAAAA==.Calzone:BAAALgAECgQJCAAAAA==.Cambria:BAAALgAECgYJDgABLgAECgcJHAAbAJEYAA==.Cameltotum:BAAALgADCgYJCQAAAA==.Carceret:BAAALgAECgkJBgAAAA==.Cardian:BAAALgAECgYJDwAAAA==.Caridin:BAABLgAECn8aAAMcAAcJ/BkKCgCmAQAcAAcJ/BkKCgCmAQAaAAIJ7Qv0kwBvAAAAAA==.Carmey:BAAALgAECgQJBAAAAA==.Carpus:BAAALgADCgMJAwAAAA==.Carrin:BAACLgAFFH8TAAIMAAQJzRcrEABnAQAMAAQJzRcrEABnAQAuAAQKfyUAAgwACAlEIWMQAAwDAAwACAlEIWMQAAwDAAAA.Catalyia:BAAALgAECgMJAwAAAA==.Catris:BAABLgAECn8RAAITAAYJzgegKgD1AAATAAYJzgegKgD1AAAAAA==.Catset:BAAALgAECgYJCwAAAA==.Caímeda:BAAALgADCgYJBgAAAA==.',
Ce='Cecea:BAAALgAECgEJAQAAAA==.Cedriel:BAAALgADCgUJAgAAAA==.Cenariya:BAAALgADCgYJBgAAAA==.Ceronos:BAAALgADCgQJBAAAAA==.Cerul:BAABLgAECn8gAAINAAgJtBduDAAFAgANAAgJtBduDAAFAgAAAA==.',
Ch='Charlton:BAAALgAECgMJAwABLgAECgkJGQAQAG0PAA==.Chazzy:BAACLgAFFH8IAAINAAMJvQpCIwDbAAANAAMJvQpCIwDbAAAuAAQKfyEAAg0ACAkrFS8ZAHUBAA0ACAkrFS8ZAHUBAAAA.Cheapfloosy:BAAALgADCgMJAwAAAA==.Chesleon:BAAALgAECgEJAgAAAA==.Chila:BAAALgAECgUJCQAAAA==.Chinaski:BAAALgAECgQJBAAAAA==.Chissgoria:BAAALgADCgYJBgAAAA==.',
Ci='Cinamonbagel:BAAALgADCgUJBgABLgADCgcJFAAKAAAAAA==.Cirina:BAAALgAECgYJCgAAAA==.',
Cl='Cli:BAAALgADCgMJAwAAAA==.Cliss:BAAALgAECgEJAQAAAA==.',
Co='Cognitive:BAAALgADCgYJBgABLgAFFAQJDAAWAN0PAA==.Coheed:BAAALgAECgQJBQABLgAECgcJHAAbAJEYAA==.Coiren:BAAALgAECgQJBQAAAA==.Cokegaming:BAAALgADCgIJAgAAAA==.Commy:BAAALgAECgEJAQAAAA==.Concorde:BAABLgAECn8YAAIMAAgJuhb8TAD7AQAMAAgJuhb8TAD7AQAAAA==.Copiousconns:BAAALgAECgYJEwAAAA==.Corasa:BAAALgADCgYJBQAAAA==.Coreyb:BAAALgADCgMJAwAAAA==.Corlock:BAABLgAECn8VAAIZAAcJpgURYgAMAQAZAAcJpgURYgAMAQAAAA==.',
Cp='Cptstabn:BAACLgAFFH8NAAMdAAQJuhvnAQBQAQAdAAQJKxbnAQBQAQABAAIJbB+0EADEAAAuAAQKfysAAx0ACAkvJBYBAIsCAAEACAnVIx4GAC8DAB0ACAl5HxYBAIsCAAAA.',
Cr='Craitos:BAAALgAECgMJBQAAAA==.Creky:BAAALgADCgkJCQAAAA==.Crimsonfury:BAAALgAECgQJBAAAAA==.',
Cu='Cutlash:BAAALgADCgcJCAABLgAECgYJFgAUALwhAA==.Cutslash:BAAALgADCgcJBwABLgAECgYJFgAUALwhAA==.Cutzap:BAABLgAECn8WAAIUAAYJvCFsBgDYAQAUAAYJvCFsBgDYAQAAAA==.',
['Cà']='Càin:BAAALgAECgUJDAAAAA==.',
Da='Daemoda:BAABLgAECn8XAAIFAAYJWSHjIQC9AQAFAAYJWSHjIQC9AQAAAA==.Daemona:BAABLgAECn8dAAIXAAkJQBKqCgDcAQAXAAkJQBKqCgDcAQAAAA==.Daieniceis:BAAALgAECgYJDgAAAA==.Dalaren:BAAALgADCgMJAwAAAA==.Dariele:BAABLgAECn8jAAIeAAYJBQ2EGgAxAQAeAAYJBQ2EGgAxAQAAAA==.Darra:BAABLgAECn8UAAMJAAcJ0xHfTABVAQAJAAcJfQ/fTABVAQAfAAQJoRPwLgDIAAAAAA==.',
De='Decayxdd:BAAALgADCgYJBgABLgAFFAMJCQAgAEsSAA==.Decayy:BAABLgAFFH8FAAIfAAMJjRh1DQCVAAAfAAMJjRh1DQCVAAABLgAFFAMJCQAgAEsSAA==.Deceptakahn:BAABLgAECn8ZAAIPAAcJ/Q3uEQDpAAAPAAcJ/Q3uEQDpAAAAAA==.Dellin:BAAALgADCgIJAQAAAA==.Derailedbeef:BAABLgAECn8hAAQcAAgJaReiCwCJAQAaAAYJLRzTLwDwAQAcAAcJKBSiCwCJAQAhAAcJPBBAEgBBAQAAAA==.Deremes:BAAALgAECgMJBAAAAA==.Destrobutor:BAAALgADCgMJAgAAAA==.Devalsminion:BAAALgADCgUJBQAAAA==.Deyas:BAABLgAECn8mAAITAAkJPhKmGQATAgATAAkJPhKmGQATAgAAAA==.Deydora:BAAALgAECgYJDAAAAA==.Deydoralia:BAABLgAECn80AAILAAkJ8STTAACCAwALAAkJ8STTAACCAwAAAA==.',
Di='Diabeetus:BAAALgAECgMJAwAAAA==.Dineye:BAAALgAECgEJAgAAAA==.Dislowcate:BAACLgAFFH8GAAIJAAMJiBabTgDyAAAJAAMJiBabTgDyAAAuAAQKfycAAgkACQleFmQpANcBAAkACQleFmQpANcBAAAA.Divineknight:BAAALgADCgcJCAAAAA==.Divinesarah:BAAALgAECgMJBAABLgAFFAUJDwAGAB4MAA==.Diô:BAAALgAECggJEQAAAA==.',
Dj='Djs:BAAALgAECgUJBwAAAA==.',
Do='Docdoom:BAAALgAECgMJAwABLgAECggJHwAGAEIYAA==.Doieha:BAAALgAECgQJBAABLgAECgYJIAAQAPIdAA==.Dollos:BAAALgADCgQJBAAAAA==.Doneldus:BAAALgAECgQJBQAAAA==.Donnovan:BAAALgADCgUJBQAAAA==.Dontrelease:BAABLgAECn8oAAMNAAkJQxBQDwDdAQANAAkJQxBQDwDdAQAQAAgJfxCwGQDAAQAAAA==.Doore:BAAALgADCgcJCAAAAA==.Dorfdragon:BAABLgAECn8gAAIOAAcJ2g9wBgBgAQAOAAcJ2g9wBgBgAQAAAA==.Dorfe:BAABLgAECn8kAAICAAgJSBRNBADQAQACAAgJSBRNBADQAQAAAA==.Dorflock:BAAALgAECgMJAwAAAA==.',
Dr='Draconas:BAABLgAECn8iAAMZAAgJpBgBHQACAgAZAAcJpBgBHQACAgAiAAEJAACXZgBDAAAAAA==.Dragonpants:BAACLgAFFH8LAAIOAAQJFh/VAAB6AQAOAAQJFh/VAAB6AQAuAAQKfysAAg4ACAlZIfcAALECAA4ACAlZIfcAALECAAAA.Drakiero:BAAALgAECgYJDwAAAA==.Drakona:BAAALgAECgYJCwAAAA==.Draych:BAABLgAECn8kAAMLAAkJCg6bLADTAQALAAkJCg6bLADTAQAMAAEJ1QV7CwEyAAAAAA==.Dreadnaughts:BAAALgADCgEJAQAAAA==.Drewgarymore:BAABLgAECn8kAAMEAAcJ8RzzDAD8AQAEAAcJ8RzzDAD8AQAPAAMJZQQbLgA+AAAAAA==.',
Du='Durandall:BAACLgAFFH8HAAIMAAMJCxRuJQCgAAAMAAMJCxRuJQCgAAAuAAQKfy0AAgwACQl0HWIaACsCAAwACQl0HWIaACsCAAAA.Durleap:BAAALgAECgUJDAAAAA==.Duskjade:BAAALgADCgIJAQAAAA==.Dustall:BAACLgAFFH8MAAIMAAUJBhEMGgBEAQAMAAUJBhEMGgBEAQAuAAQKfycAAgwACQnHHicMAKECAAwACQnHHicMAKECAAAA.',
Dy='Dylpickl:BAACLgAFFH8QAAIFAAQJjyXKCACxAQAFAAQJjyXKCACxAQAuAAQKfyQAAgUACQnpJJwBAMMDAAUACQnpJJwBAMMDAAAA.Dymàs:BAAALgAECgYJBwAAAA==.',
['Dè']='Dècay:BAACLgAFFH8JAAIgAAMJSxJXHgDpAAAgAAMJSxJXHgDpAAAuAAQKfxcAAiAACAlzG/sKABMCACAACAlzG/sKABMCAAAA.',
Ea='Earthrocker:BAABLgAECn8cAAIPAAgJ8RHBDABDAQAPAAgJ8RHBDABDAQAAAA==.',
Ed='Edified:BAAALgAECgUJDAAAAA==.',
Ei='Einkil:BAABLgAECn8iAAIfAAgJahQeEQBgAQAfAAgJahQeEQBgAQAAAA==.',
Ek='Ekalb:BAAALgADCgUJBQABLgAECggJHwAZAAoWAA==.',
El='Elleryq:BAAALgAECgIJAwAAAA==.Elurah:BAABLgAECn8WAAIVAAcJNRyUDAAcAgAVAAcJNRyUDAAcAgAAAA==.',
Em='Emberflame:BAAALgAECgIJAQAAAA==.Embergrove:BAAALgADCgEJAQAAAA==.Emberlée:BAAALgAECgMJAwABLgAECgkJNAALAPEkAA==.',
En='Entropîc:BAAALgADCgkJDQAAAA==.',
Ep='Epin:BAAALgAECgMJBQABLgAECggJFQARAHUXAA==.',
Er='Erazminash:BAAALgAECgQJCAAAAA==.',
Es='Esdeáth:BAABLgAECn8WAAIGAAcJQAOjkwDrAAAGAAcJQAOjkwDrAAAAAA==.Ess:BAABLgAECn8WAAIWAAYJcBZRDwBDAQAWAAYJcBZRDwBDAQAAAA==.',
Ev='Even:BAAALgAECgMJBQAAAA==.',
Fa='Fae:BAAALgADCgcJCwAAAA==.Faede:BAAALgADCgcJCgAAAA==.Fangorn:BAAALgADCgQJBAAAAA==.Fantarius:BAABLgAECn8bAAMVAAgJSSHMDwBoAgAVAAgJSSHMDwBoAgATAAcJ4wtHHQBRAQAAAA==.Fantazee:BAAALgADCgQJBAAAAA==.Faromore:BAAALgAECgEJBQAAAA==.Farvah:BAAALgAECgIJAgABLgAECgYJGAAQAGoRAA==.Fatdono:BAAALgAECgYJCwAAAA==.',
Fe='Felfurion:BAAALgAECgUJBQAAAA==.Feluhn:BAAALgAECgYJEwAAAA==.Fennriz:BAABLgAECn8fAAIGAAgJQhj3KwDyAQAGAAgJQhj3KwDyAQAAAA==.',
Fi='Fibbs:BAABLgAECn8cAAIPAAcJXxcdCgB7AQAPAAcJXxcdCgB7AQAAAA==.Firocios:BAABLgAECn8YAAILAAYJpxK6LQAkAQALAAYJpxK6LQAkAQAAAA==.Fistavus:BAAALgADCgYJBAAAAA==.Fizzlepie:BAAALgAECgQJBAAAAA==.',
Fl='Flappyboy:BAAALgAECgEJAQAAAA==.Flatiron:BAABLgAECn8UAAIeAAYJdAkMHgARAQAeAAYJdAkMHgARAQAAAA==.Flirts:BAAALgADCgMJAwAAAA==.',
Fo='Foul:BAABLgAECn8vAAMLAAgJOCL1BgD8AgALAAgJOCL1BgD8AgAMAAIJ3g09wgBxAAABLgAFFAUJEQAIAF0cAA==.Foxybeans:BAAALgADCgcJBwAAAA==.',
Fr='Frankyzappa:BAABLgAECn8cAAMjAAgJEx5fBAD4AQAjAAgJyBxfBAD4AQAkAAMJ0BqyYADuAAAAAA==.Frieda:BAAALgADCgMJAwAAAA==.Frink:BAAALgADCgkJEwABLgAECgYJFAAeAHQJAA==.Fromunda:BAAALgAECgYJDAAAAA==.Frosthot:BAAALgAECgIJAgAAAA==.Frostyfella:BAAALgAECgYJBgABLgAFFAQJDAANAGoWAA==.',
Fu='Futality:BAEALgAECgQJBAABLgAECggJKAALAL4cAA==.',
Fy='Fyredemon:BAAALgADCgkJDwAAAA==.',
['Fë']='Fëld:BAAALgADCgUJBQAAAA==.',
Ga='Gardlier:BAAALgAECgQJBwAAAA==.Garumna:BAABLgAECn8fAAIJAAgJzRYNIwD4AQAJAAgJzRYNIwD4AQAAAA==.Garypotter:BAABLgAECn8hAAIFAAcJySFxDwBLAgAFAAcJySFxDwBLAgAAAA==.',
Ge='Gec:BAAALgADCgEJAQAAAA==.',
Gl='Gleave:BAABLgAECn8kAAIkAAgJjyLECQCaAgAkAAgJjyLECQCaAgAAAA==.Glennzig:BAAALgAECgYJCwAAAA==.Glimmerdin:BAAALgAECgMJAwABLgAECggJHgATAO0UAA==.',
Go='Goremock:BAABLgAECn8gAAIaAAcJtR4nDwD/AQAaAAcJtR4nDwD/AQAAAA==.Gorescore:BAAALgADCgMJAwAAAA==.Gorpus:BAAALgADCgYJBgAAAA==.',
Gr='Granhiert:BAAALgAECgUJDQAAAA==.Graven:BAAALgAECgQJBAAAAA==.Gravytrain:BAAALgADCgUJCgAAAA==.Greatred:BAAALgADCgIJAgAAAA==.Greenonion:BAAALgADCgYJBgAAAA==.Gremer:BAAALgADCgYJCAAAAA==.Greyfear:BAAALgADCgEJAQABLgAECggJHwAJAM0WAA==.Greyluxen:BAAALgAECgcJDwAAAA==.Greystoke:BAABLgAECn8VAAIRAAgJdRfqHwAfAgARAAgJdRfqHwAfAgAAAA==.Greytusk:BAAALgADCgIJAgAAAA==.Grindelbald:BAABLgAECn8pAAISAAcJURx1AgAoAgASAAcJURx1AgAoAgAAAA==.Grìp:BAABLgAECn8UAAIkAAcJqxibLwCPAQAkAAcJqxibLwCPAQAAAA==.',
Gt='Gtfofupá:BAAALgAECgkJDAAAAA==.',
Gu='Gushee:BAAALgAFFAMJAwAAAA==.',
Gw='Gwenn:BAABLgAECn8cAAIYAAcJlxc2EQDDAQAYAAcJlxc2EQDDAQAAAA==.',
Ha='Hae:BAAALgADCgMJAwAAAA==.Haldor:BAAALgADCgcJBwABLgAECgkJGQAQAG0PAA==.Haldrath:BAABLgAECn8dAAIXAAkJZRpEFgAZAgAXAAkJZRpEFgAZAgAAAA==.Halse:BAAALgADCgIJAgAAAA==.Hanahiro:BAAALgADCgUJBAAAAA==.Harleyquìnn:BAAALgAECgUJBgAAAA==.Hashishem:BAAALgAECgUJCAABLgAFFAUJEQAIAF0cAA==.Hawkslayer:BAABLgAECn8UAAIMAAYJaQrrdQAAAQAMAAYJaQrrdQAAAQAAAA==.',
He='Hecaate:BAAALgAECgYJCgAAAA==.Hedgelord:BAACLgAFFH8OAAIEAAQJmxn8CwBNAQAEAAQJmxn8CwBNAQAuAAQKfx8AAgQACAnWGJwXAE4CAAQACAnWGJwXAE4CAAAA.Hedy:BAAALgADCgkJEwAAAA==.Hellebore:BAAALgAECgQJBwAAAA==.Hendil:BAABLgAECn8iAAIkAAcJxg1fPwBQAQAkAAcJxg1fPwBQAQAAAA==.',
Ho='Hobe:BAAALgAECgUJBQAAAA==.Hohenhiem:BAAALgAECgIJAgAAAA==.Holeyfield:BAAALgADCgEJAQAAAA==.Hollyparton:BAAALgAECgUJDAAAAA==.Holysith:BAAALgAECgQJBwAAAA==.Hornypunn:BAAALgADCgcJBwABLgAFFAMJBQAZAMEOAA==.Hotzlol:BAABLgAECn8hAAMDAAgJ/R6DDgBpAgADAAgJ/R6DDgBpAgAHAAEJJBqtMABCAAAAAA==.',
Ht='Htari:BAAALgADCgkJEQABLgAECgYJIAAQAPIdAA==.',
Hu='Humoresque:BAABLgAECn8WAAILAAYJeCWuCACIAgALAAYJeCWuCACIAgAAAA==.Hunger:BAAALgAECgEJBAAAAA==.',
Ic='Icyblades:BAABLgAECn8YAAIJAAgJCxjrQQB3AQAJAAgJCxjrQQB3AQAAAA==.Icònòclast:BAAALgAECggJEgAAAA==.',
Ii='Iifa:BAAALgADCgkJGAAAAA==.',
Ik='Ikari:BAAALgADCgMJAwAAAA==.Iknowkungfu:BAABLgAECn8nAAIgAAcJwyHpCQAmAgAgAAcJwyHpCQAmAgAAAA==.',
Il='Illuminate:BAABLgAECn8kAAILAAcJVx22DgAvAgALAAcJVx22DgAvAgAAAA==.',
Im='Imboutablow:BAAALgADCgEJAQAAAA==.Immortalnut:BAAALgAECgMJAwAAAA==.',
In='Inori:BAACLgAFFH8IAAIYAAMJixmvFgD3AAAYAAMJixmvFgD3AAAuAAQKfyEAAxgACAkZHUcKADECABgACAkZHUcKADECABUAAQnTGpN4AEcAAAAA.',
It='Ittyycakes:BAAALgADCgUJBQAAAA==.',
Iv='Ivara:BAAALgADCgMJAwAAAA==.',
Ja='Jackypan:BAAALgAECgIJBAAAAA==.Jadebreeze:BAAALgAECgIJAgAAAA==.Jaktar:BAABLgAECn8ZAAIkAAgJWAx5NQDYAQAkAAgJWAx5NQDYAQAAAA==.Jane:BAAALgAECgMJBgAAAA==.Janet:BAABLgAECn8iAAIhAAkJyA0fEwA2AQAhAAkJyA0fEwA2AQAAAA==.',
Je='Jeroung:BAAALgAECgIJAwABLgAECggJHwAJAM0WAA==.Jezak:BAAALgAECgYJEAABLgAECggJIgAkAGcfAA==.',
Ji='Jiraipo:BAAALgAECgQJBwAAAA==.Jirikidawn:BAAALgADCgMJAwAAAA==.Jirikideath:BAAALgAFFAMJAwAAAA==.Jirikidemon:BAAALgAECgIJAgAAAA==.',
Jo='Joffery:BAAALgAECgUJBQAAAA==.Jojobeän:BAAALgADCgUJBAABLgADCgcJDQAKAAAAAA==.Jone:BAAALgAECgUJDAAAAA==.Joobs:BAAALgAECgcJEwAAAA==.',
Ju='Jurahas:BAAALgAECgUJBQAAAA==.Justforkicks:BAAALgADCgYJBgAAAA==.Justíce:BAAALgAECgQJCwAAAA==.',
Ka='Kahliea:BAABLgAECn8WAAIDAAYJMB4gGQD8AQADAAYJMB4gGQD8AQAAAA==.Kaidance:BAABLgAECn8fAAIlAAkJ1A16BwB3AQAlAAkJ1A16BwB3AQAAAA==.Kaisaze:BAAALgAECgcJEQAAAA==.Kaiser:BAAALgAECgMJAwAAAA==.Kaluno:BAAALgADCggJCQAAAA==.Kapachka:BAAALgAECgUJCQAAAA==.Katmarie:BAAALgADCgkJIAAAAA==.Kayssa:BAAALgAECggJEQAAAA==.Kazothor:BAABLgAECn8WAAIfAAYJSB9QCwDBAQAfAAYJSB9QCwDBAQAAAA==.',
Ke='Keebo:BAAALgADCgMJAwAAAA==.Kellandriiya:BAAALgADCgUJBQAAAA==.Kerelissia:BAAALgAECgEJAgAAAA==.Keria:BAACLgAFFH8XAAMXAAcJ0Ru4AADLAQAXAAUJtR64AADLAQAFAAYJbxDcEQBrAQAuAAQKfzcAAxcACQnrJZAAAN8DABcACQmbJZAAAN8DAAUACQntIZ4CACIDAAAA.',
Kh='Kharfáz:BAAALgAECgMJBQAAAA==.Khasmeen:BAAALgAECgUJBQAAAA==.Khorn:BAAALgADCgcJBwAAAA==.',
Ki='Kifd:BAACLgAFFH8KAAIhAAMJKx4rCgAOAQAhAAMJKx4rCgAOAQAuAAQKfysAAiEACAnRI4ECAEMDACEACAnRI4ECAEMDAAAA.Kinzy:BAAALgAECgMJBQAAAA==.Kiretsu:BAABLgAECn8aAAIGAAkJ9xPYUwA8AgAGAAkJ9xPYUwA8AgAAAA==.Kittingtons:BAAALgAECggJCAAAAA==.',
Ko='Koder:BAABLgAECn8fAAMQAAcJbhIKDQB2AQAQAAcJbhIKDQB2AQAOAAMJ8iORBwA+AQAAAA==.Kodykinns:BAAALgAECgkJDwAAAA==.Kovus:BAAALgAECgUJCwAAAA==.',
Kr='Krelien:BAAALgAECgYJBgAAAA==.Kristaan:BAAALgADCgQJBAAAAA==.',
Ky='Kyliejenner:BAAALgAECgEJAQAAAA==.Kynetik:BAAALgAFFAEJAQABLgAFFAQJDAAWAN0PAA==.',
La='Ladamirea:BAABLgAECn8mAAMlAAkJkyLCAADoAgAlAAkJkyLCAADoAgAFAAEJlAc65wArAAAAAA==.Lamashtu:BAABLgAECn8mAAMTAAcJKxPEIwAkAQATAAYJOxHEIwAkAQAVAAQJtQkFMwC6AAAAAA==.Lanardris:BAAALgADCgYJCAAAAA==.Landoras:BAAALgADCgQJBAAAAA==.Lashar:BAAALgADCgcJCwAAAA==.Lawlipopkid:BAABLgAECn8iAAIMAAgJFA5oQACEAQAMAAgJFA5oQACEAQAAAA==.Layssar:BAAALgAECgYJCwAAAA==.',
Le='Lefrench:BAACLgAFFH8QAAImAAQJYBpCBgBcAQAmAAQJYBpCBgBcAQAuAAQKfxgAAiYACAksH/sHAPoCACYACAksH/sHAPoCAAAA.Legendarea:BAAALgADCgIJAgAAAA==.Legionstorm:BAAALgAECgEJAgAAAA==.Lemmy:BAAALgADCgkJCQAAAA==.Lexzan:BAABLgAECn8UAAIMAAYJJQy0owA5AQAMAAYJJQy0owA5AQAAAA==.',
Li='Lilas:BAAALgAECgUJDAAAAA==.Lilifa:BAABLgAECn8fAAIIAAcJtyP4BQCpAgAIAAcJtyP4BQCpAgAAAA==.Lilillidari:BAAALgAECgYJCAABLgAFFAQJDQAJABAeAA==.Lilmontaro:BAACLgAFFH8NAAMJAAQJEB5sIQATAQAJAAQJEB5sIQATAQAnAAIJdAqXBwCMAAAuAAQKfzsAAwkACQk0JawQABgDAAkACQk0JawQABgDAB8AAgkEDkY6ACsAAAAA.Linali:BAABLgAECn8bAAIRAAcJyBWWJQCOAQARAAcJyBWWJQCOAQAAAA==.Liona:BAAALgADCgIJAgAAAA==.Lisey:BAABLgAECn8cAAMEAAkJsRZGHwAFAgAEAAgJKxhGHwAFAgADAAgJBxd0PAAjAQAAAA==.Lisong:BAAALgAECgIJAgAAAA==.Listari:BAAALgAECgcJDQAAAA==.Littlebuns:BAAALgAECgYJEwAAAA==.',
Lk='Lkar:BAAALgADCgUJBQAAAA==.',
Lo='Lohk:BAAALgADCgYJBgABLgAECgcJHAAhAJoTAA==.Lohkin:BAABLgAECn8cAAIhAAcJmhMVDgCBAQAhAAcJmhMVDgCBAQAAAA==.Loreleí:BAAALgADCgkJDAABLgAECgcJHwAIALcjAA==.Lotherun:BAAALgAECggJDgAAAA==.',
Lu='Lucïna:BAABLgAECn8dAAIXAAcJpxdBEAB/AQAXAAcJpxdBEAB/AQAAAA==.Ludk:BAAALgAECgEJBAAAAA==.Lumiela:BAAALgAECgQJBwAAAA==.Luminah:BAABLgAECn8gAAIZAAgJxxdoIQDpAQAZAAgJxxdoIQDpAQAAAA==.Luni:BAAALgAECgIJAgAAAA==.Lunì:BAAALgADCgYJBgABLgAECgIJAgAKAAAAAA==.Luxanna:BAAALgAECgMJAwAAAA==.',
Ly='Lysithea:BAAALgAFFAEJAQAAAA==.',
['Lì']='Lìlïth:BAAALgADCgYJBgAAAA==.',
Ma='Mageblaster:BAAALgADCgQJBAAAAA==.Maggnut:BAABLgAECn8YAAIaAAgJBxh/HQBiAgAaAAgJBxh/HQBiAgAAAA==.Mairek:BAABLgAECn8lAAMoAAgJlBxUAwA/AgAoAAcJzB1UAwA/AgAGAAgJFxrIIAAnAgAAAA==.Makarios:BAAALgAECgMJCAAAAA==.Maleigoron:BAABLgAECn8eAAIZAAkJ7AmfVAAuAQAZAAkJ7AmfVAAuAQAAAA==.Malestrom:BAAALgADCgUJBQAAAA==.Malkuri:BAABLgAECn8kAAMjAAkJsRlIBAD7AQAjAAkJsRlIBAD7AQAkAAEJVBSWqABFAAAAAA==.Manapoppins:BAAALgADCgUJBQAAAA==.Maranne:BAAALgAECgYJEwAAAA==.Marolt:BAAALgADCgkJCQABLgAECgYJIAAQAPIdAA==.Masonite:BAAALgAECgYJBwAAAA==.Mauser:BAAALgAECgcJDgABLgAFFAUJEQAIAF0cAA==.',
Mc='Mcbasketball:BAAALgAECgYJEwAAAA==.Mcchickenman:BAABLgAECn8bAAIJAAcJqiNVJgCiAgAJAAcJqiNVJgCiAgAAAA==.',
Me='Mechagnome:BAAALgADCgEJAQAAAA==.Mechaljaxon:BAABLgAECn8aAAIiAAkJ7whIBwByAQAiAAkJ7whIBwByAQAAAA==.Melyssa:BAAALgADCgYJBgAAAA==.Memeologist:BAACLgAFFH8UAAImAAQJDSacAQC3AQAmAAQJDSacAQC3AQAuAAQKfyUAAiYACQmlI3UBAJ4DACYACQmlI3UBAJ4DAAAA.Meowdy:BAACLgAFFH8KAAINAAMJlw00JADVAAANAAMJlw00JADVAAAuAAQKfysAAg0ACAmYHiYHAGYCAA0ACAmYHiYHAGYCAAAA.Metapal:BAACLgAFFH8MAAIWAAQJ3Q9zBADcAAAWAAQJ3Q9zBADcAAAuAAQKfyUAAhYACAlXGEQKACsCABYACAlXGEQKACsCAAAA.Metasham:BAAALgAECgcJDQABLgAFFAQJDAAWAN0PAA==.',
Mi='Mienaz:BAAALgADCggJBgAAAA==.Miiaa:BAAALgAECggJEwAAAA==.Milane:BAAALgAECgQJCwAAAA==.Milktank:BAABLgAECn8WAAImAAgJrBZhIQDLAQAmAAgJrBZhIQDLAQAAAA==.Millea:BAAALgAECgYJDAAAAA==.Mindsight:BAAALgADCgcJBAAAAA==.Mirian:BAAALgAECgUJCQAAAA==.Mistystrike:BAAALgAECgcJBwAAAA==.Miztaken:BAAALgAECgYJEQAAAA==.',
Mo='Moirasha:BAABLgAECn8lAAMZAAgJkguxOgB8AQAZAAgJkguxOgB8AQAiAAUJrgTDPADBAAAAAA==.Moistbagel:BAAALgAECgUJBQAAAA==.Mojorisen:BAAALgAECgcJEQAAAA==.Momonitis:BAAALgAECgMJAwAAAA==.Monran:BAAALgAECgcJEgAAAA==.Moonlixer:BAAALgAECgQJCQAAAA==.Moonshinee:BAAALgAECgEJAQAAAA==.Moosand:BAABLgAECn8iAAIkAAgJZx/kEABMAgAkAAgJZx/kEABMAgAAAA==.Morgorath:BAABLgAECn8aAAIBAAcJmAXyHAAWAQABAAcJmAXyHAAWAQAAAA==.Mortivus:BAAALgAECgUJCwAAAA==.',
Mu='Muggs:BAAALgAECgIJAgAAAA==.Mulgaist:BAAALgADCgYJBgAAAA==.Mulvane:BAAALgAECgUJCwAAAA==.Munkii:BAAALgAECgEJAgABLgAECgQJCwAKAAAAAA==.Murphyb:BAAALgAECgMJBAAAAA==.Mustachio:BAABLgAECn8dAAIGAAgJgRg9KAABAgAGAAgJgRg9KAABAgAAAA==.',
Mw='Mwc:BAACLgAFFH8MAAMCAAQJIiU6AQCPAQACAAQJZyQ6AQCPAQABAAEJBSZhFgBxAAAuAAQKfykAAwEACAkGII4KAOkCAAEACAkCII4KAOkCAAIABgnrF2oHAGsBAAAA.',
My='Myrrim:BAABLgAECn8iAAIDAAgJWBZ6JAClAQADAAgJWBZ6JAClAQAAAA==.Mysweetness:BAAALgAECgQJBAAAAA==.',
Mz='Mziao:BAAALgAECggJCgAAAA==.',
['Më']='Mëlly:BAAALgADCgMJAwAAAA==.',
['Mô']='Môruden:BAAALgADCgYJCAAAAA==.',
Na='Naahmi:BAAALgAECgYJDwAAAA==.Naiara:BAAALgAECgYJCwAAAA==.Nalexia:BAAALgAECgQJBgAAAA==.Namma:BAAALgADCgcJCgAAAA==.Narbw:BAAALgAECgMJBAABLgAECgMJBgAKAAAAAA==.Narbzy:BAAALgAECgMJBgAAAA==.Nashia:BAAALgADCgMJAwAAAA==.Naytear:BAAALgAECgEJAgAAAA==.Nazend:BAAALgADCgQJBAABLgAECgYJDwAKAAAAAA==.',
Ne='Neall:BAABLgAECn8mAAIhAAgJWA83DwBwAQAhAAgJWA83DwBwAQAAAA==.Necroflame:BAAALgADCgEJAQAAAA==.Necronym:BAABLgAFFH8GAAMJAAQJsBvYQwAGAQAJAAMJsBvYQwAGAQAfAAEJAADZKAAAAAAAAA==.Nef:BAAALgAECgQJCgAAAA==.Negapriest:BAAALgAECgQJAgAAAA==.Nei:BAAALgAECgEJAgABLgAECgQJCgAKAAAAAA==.Nekoshade:BAAALgADCgQJBAAAAA==.Nekoshâde:BAAALgAECgQJBwAAAA==.Nemrin:BAAALgADCgIJAgAAAA==.Nendetre:BAABLgAECn8gAAMQAAYJ8h3iCgCiAQAQAAYJ8h3iCgCiAQAOAAQJVA1VKQDUAAAAAA==.Nerelia:BAAALgADCgYJCwAAAA==.Nevets:BAAALgAECgcJDQAAAA==.Neô:BAAALgAECgEJAgAAAA==.',
Ni='Nightbird:BAAALgADCgYJBgAAAA==.Nighthazy:BAAALgADCgMJBAAAAA==.Nimvexium:BAAALgAECgcJBgABLgAECgYJFgAaAHgWAA==.Nixs:BAAALgAECgUJBQABLgAFFAUJCAAGAKsLAA==.',
No='Notbald:BAAALgADCgUJBQABLgAECgcJKQASAFEcAA==.Notbyworks:BAABLgAECn8YAAIDAAYJwBinIwCrAQADAAYJwBinIwCrAQAAAA==.Notorious:BAAALgAECgkJJwAAAQ==.',
Ny='Nykyrian:BAABLgAECn8hAAMmAAkJSRimDADuAQAmAAgJdBamDADuAQAIAAMJCgquVQB4AAAAAA==.Nyxeris:BAAALgAECgkJAQAAAA==.',
Ob='Oblast:BAAALgAECgcJBwAAAA==.',
Oc='Ocman:BAAALgADCgMJAwAAAA==.',
Od='Odb:BAAALgAECgYJEgAAAA==.',
Ol='Olathe:BAAALgADCgkJDwAAAA==.Oldmanjey:BAAALgAECgYJEwAAAA==.Olmanjankins:BAAALgAECggJCgAAAA==.',
On='Onara:BAAALgADCgIJAgAAAA==.Onlydks:BAAALgAECgcJCgABLgAECgYJFgAaAHgWAA==.Onlyslams:BAABLgAECn8WAAQaAAYJeBadTABzAQAaAAYJZBSdTABzAQAhAAIJcxpENQCcAAAcAAIJJQp7NABfAAAAAA==.',
Op='Opil:BAAALgAECgMJBAAAAA==.',
Or='Orlandeau:BAAALgADCgIJAgAAAA==.Orter:BAACLgAFFH8LAAIJAAMJ8hiDSwD4AAAJAAMJ8hiDSwD4AAAuAAQKfysAAgkACAlZIxAKAMACAAkACAlZIxAKAMACAAAA.',
Pa='Panakoa:BAAALgADCgMJAwAAAA==.Pandishar:BAAALgAECgYJCgAAAA==.Papsfear:BAABLgAECn8kAAIZAAcJVhrfJADXAQAZAAcJVhrfJADXAQAAAA==.Parce:BAABLgAECn8nAAMLAAgJIyQjCwDGAgALAAcJKCQjCwDGAgAMAAgJ8BsHFQBRAgAAAA==.',
Pe='Peacebringer:BAAALgADCgcJCAAAAA==.Pengyoa:BAABLgAECn8VAAIFAAgJ7hhKOQAPAgAFAAgJ7hhKOQAPAgAAAA==.',
Ph='Phydaux:BAAALgAECgYJEgAAAA==.',
Pi='Pinkponyclub:BAAALgADCggJCAAAAA==.Pinpow:BAAALgADCgcJCQAAAA==.Pizza:BAAALgAECgQJBAAAAA==.Pizzaman:BAABLgAECn8YAAIjAAgJsQurCQBeAQAjAAgJsQurCQBeAQAAAA==.',
Po='Poxi:BAABLgAECn8YAAIGAAgJPB2gYgAUAgAGAAgJPB2gYgAUAgAAAA==.',
Pr='Proxima:BAAALgADCgcJCwAAAA==.',
Ps='Psykopath:BAAALgAECgEJAQAAAA==.',
Pt='Ptoughneigh:BAABLgAECn8YAAIMAAkJ/RpNFgBIAgAMAAkJ/RpNFgBIAgAAAA==.',
Pu='Publicus:BAAALgADCgkJDwABLgAECgYJEQAKAAAAAA==.Puckish:BAACLgAFFH8MAAMYAAQJsgVkFwDtAAAYAAQJ1AFkFwDtAAAVAAEJABEIFQBBAAAuAAQKfygAAxgACAmfCrYhAIYBABgACAmsCbYhAIYBABUACAkWBjU4AFsBAAAA.Punnisher:BAACLgAFFH8FAAIZAAMJwQ7YQwDTAAAZAAMJwQ7YQwDTAAAuAAQKfyMABBkABwn5G1srALcBABkABwn5G1srALcBACkAAQkAAK0sAEUAACIAAQkAAHZtADoAAAAA.',
['Pä']='Päiñ:BAAALgAECgMJBAAAAA==.',
Qu='Quacky:BAAALgAECgUJBQAAAA==.Quackys:BAAALgAECgYJEgAAAA==.Quellog:BAAALgADCgEJAQABLgAECgcJHAAbAJEYAA==.Quickbeam:BAAALgAECgcJEgAAAA==.Quorrad:BAAALgAECgcJBAAAAA==.Quäckys:BAAALgADCgcJDQAAAA==.',
Ra='Radünz:BAAALgAECgEJAQABLgAECggJKAAHACYhAA==.Raelianna:BAABLgAECn8VAAIZAAcJyxRdZQCbAQAZAAcJyxRdZQCbAQABLgAECggJHgAGALMhAA==.Raevin:BAAALgAECgEJAgAAAA==.Raewyna:BAAALgAECgIJAgAAAA==.Ragi:BAAALgADCgMJAwAAAA==.Rahlian:BAAALgAECgUJCQABLgAECgYJDwAKAAAAAA==.Rahlock:BAAALgAECgYJDwAAAA==.Raine:BAABLgAECn8jAAMRAAgJ1R6OFgBhAgARAAgJ1R6OFgBhAgAbAAIJ3Rm+XQA/AAAAAA==.Rainingblood:BAAALgADCgMJAwAAAA==.Rainjar:BAABLgAECn8ZAAIIAAYJKiSXDwBfAgAIAAYJKiSXDwBfAgAAAA==.Ranron:BAAALgADCgYJBgAAAA==.Raphael:BAABLgAECn8rAAMJAAgJMRDDPwB+AQAJAAgJSw3DPwB+AQAfAAIJ2hNFKwByAAAAAA==.Rasik:BAABLgAECn8rAAMaAAgJYSMWCQBXAgAaAAcJhiMWCQBXAgAhAAEJgyIFLABlAAAAAA==.Ravenblood:BAAALgAECgEJAgAAAA==.Rayel:BAABLgAECn8UAAIVAAgJ+RqJDAAdAgAVAAgJ+RqJDAAdAgAAAA==.Raylyn:BAAALgAECgMJBAAAAA==.',
Re='Redoubtf:BAABLgAECn8fAAIMAAkJShNwTwDzAQAMAAkJShNwTwDzAQAAAA==.Refourper:BAAALgADCgcJFAAAAA==.Rendingo:BAABLgAECn8cAAMlAAgJ3BtsBADoAQAlAAgJixtsBADoAQAFAAYJAxi5WQCUAQAAAA==.Rennlei:BAABLgAECn8ZAAIFAAkJliAhDgBYAgAFAAkJliAhDgBYAgAAAA==.',
Rh='Rhaegare:BAABLgAECn8XAAMcAAYJPxwKGAA5AQAcAAQJlxwKGAA5AQAaAAUJJxhlOwDVAAAAAA==.Rheanon:BAAALgAECgQJCAAAAA==.Rhome:BAACLgAFFH8HAAITAAIJ/Q7AGAChAAATAAIJ/Q7AGAChAAAuAAQKfxsAAxMACAmAGp8lAKsBABMACAmAGp8lAKsBABUABQnKE3wmABYBAAAA.',
Ri='Rialu:BAABLgAECn8fAAIVAAkJNBEqDwD2AQAVAAkJNBEqDwD2AQAAAA==.Ribald:BAAALgADCgUJBQAAAA==.Rickgrimes:BAAALgAECgYJDQAAAA==.Rigormortits:BAAALgAECgQJBgABLgAECgcJJAAZAFYaAA==.Rime:BAACLgAFFH8JAAIGAAQJsx5nIQBlAQAGAAQJsx5nIQBlAQAuAAQKfyIAAgYACAl5JbIKAG8DAAYACAl5JbIKAG8DAAAA.Risandra:BAAALgADCgYJBwAAAA==.',
Ro='Roid:BAACLgAFFH8MAAMMAAQJvxuuDwBpAQAMAAQJvxuuDwBpAQALAAIJjhG8IgCKAAAuAAQKfx8AAwwACAnQIn0JAL8CAAwACAnQIn0JAL8CAAsAAwm8B1J7AIwAAAAA.Rotcorpse:BAABLgAECn8gAAIVAAkJcSB9BQD3AgAVAAkJcSB9BQD3AgAAAA==.',
Ru='Rubyred:BAAALgADCgUJBQAAAA==.Ruddam:BAAALgAECgUJDAAAAA==.Runier:BAAALgADCgUJBQABLgAECgIJAgAKAAAAAA==.Runikh:BAAALgAECgUJCAAAAA==.',
Ry='Rylandor:BAAALgADCggJCAAAAA==.',
['Rä']='Rägekäge:BAAALgADCgYJCAAAAA==.Räveñz:BAABLgAECn8hAAIPAAcJnwyXEwDTAAAPAAcJnwyXEwDTAAAAAA==.',
Sa='Saariell:BAABLgAECn8kAAIDAAcJAxJ2KgCAAQADAAcJAxJ2KgCAAQAAAA==.Sabrielle:BAAALgAECgkJAQAAAA==.Sagremor:BAAALgAECgYJBwABLgAECggJJgAPADQlAA==.Saintabes:BAABLgAECn8eAAQTAAgJ7RQ+GwAEAgATAAcJGhg+GwAEAgAYAAYJOBU3IgCCAQAVAAMJbwQEawB/AAAAAA==.Saintlaurent:BAAALgADCgEJAQABLgAECgkJJwAKAAAAAA==.Saintthorlak:BAABLgAECn8WAAIMAAYJIw8PdQACAQAMAAYJIw8PdQACAQAAAA==.Saiorse:BAABLgAECn8lAAIDAAgJkQxnLQBvAQADAAgJkQxnLQBvAQAAAA==.Samelan:BAAALgAECgEJAQAAAA==.Sandara:BAABLgAECn8mAAITAAgJ/iLMAwC4AgATAAgJ/iLMAwC4AgAAAA==.Sanguineliam:BAAALgAECgEJAgAAAA==.Sanrinn:BAAALgADCgkJCQABLgAECgYJDAAKAAAAAA==.Santocarbón:BAAALgAECgUJCwAAAA==.Saphera:BAAALgAECgEJAQAAAA==.Sarahann:BAAALgAECgcJEgAAAA==.Sarahboom:BAACLgAFFH8PAAIGAAUJHgxSIQA9AQAGAAUJHgxSIQA9AQAuAAQKfyEAAgYACAmcGrlAAHYCAAYACAmcGrlAAHYCAAAA.',
Sc='Scaia:BAABLgAECn8VAAIMAAcJARrROgCWAQAMAAcJARrROgCWAQAAAA==.Scapegoat:BAEALgAECggJKwAAAQ==.Scaryspice:BAABLgAECn8kAAIkAAcJPgv9QgBEAQAkAAcJPgv9QgBEAQAAAA==.Scraime:BAAALgAFFAIJAgAAAA==.',
Se='Seethe:BAAALgADCgYJCwAAAA==.Seilah:BAABLgAECn8gAAIDAAcJuCVzBQAAAwADAAcJuCVzBQAAAwAAAA==.Seliah:BAABLgAECn8WAAIMAAYJbCAdQgAeAgAMAAYJbCAdQgAeAgAAAA==.Sennis:BAABLgAECn8aAAMBAAkJIBztEACaAgABAAcJOx7tEACaAgAdAAUJ8xUVBQB3AQAAAA==.Senpai:BAAALgAFFAEJAQAAAA==.Sephora:BAAALgAECgcJEgAAAA==.Seventhshadë:BAAALgADCgEJAQAAAA==.',
Sh='Shadoris:BAABLgAECn8UAAIBAAgJOBD5DgC0AQABAAgJOBD5DgC0AQAAAA==.Shadowglade:BAABLgAECn8hAAIEAAgJDhhlDwDaAQAEAAgJDhhlDwDaAQAAAA==.Shalanoth:BAABLgAECn8kAAINAAcJOwgaKwD/AAANAAcJOwgaKwD/AAAAAA==.Shalltear:BAABLgAECn8TAAIFAAYJAgOIggCQAAAFAAYJAgOIggCQAAAAAA==.Shamashiznit:BAAALgADCgQJAwAAAA==.Shamizzle:BAAALgAECgcJCgAAAA==.Shammydavis:BAABLgAECn8dAAMRAAYJ9iQUEwB9AgARAAYJ9iQUEwB9AgAbAAQJZBiwJwAfAQAAAA==.Shammylove:BAAALgAECgcJDgAAAA==.Shessra:BAAALgAECgQJBAABLgAECgYJBgAKAAAAAA==.Shiftyloki:BAAALgAECgEJAQABLgAECgkJDAAKAAAAAA==.Shockoctopus:BAAALgADCgYJBgAAAA==.Shootinblanx:BAAALgAECgIJAgAAAA==.Shraan:BAAALgAECgYJDwAAAA==.Shrapnel:BAABLgAECn8YAAIkAAYJvhCuUAB3AQAkAAYJvhCuUAB3AQAAAA==.Shàytan:BAABLgAECn8lAAIXAAcJ7xR/EgBiAQAXAAcJ7xR/EgBiAQAAAA==.',
Si='Sinistral:BAAALgAECgEJAQAAAA==.Sinvyx:BAAALgADCgUJBQAAAA==.',
Sk='Skullchopper:BAAALgAECgQJCAABLgAECgcJGgAXABceAA==.Skunch:BAAALgADCgYJCwAAAA==.',
Sl='Slashanon:BAAALgADCgYJBwABLgADCgcJFAAKAAAAAA==.Slise:BAAALgADCggJCAAAAA==.',
Sm='Smithers:BAABLgAECn8rAAQZAAgJvyOKEgBOAgAZAAYJCiKKEgBOAgAiAAMJrCN0CwAdAQApAAIJ5x9AFgDQAAAAAA==.',
Sn='Snappycakes:BAAALgAECgQJBQAAAA==.Sneakybunny:BAABLgAECn8rAAIdAAgJ2gN0CQDlAAAdAAgJ2gN0CQDlAAAAAA==.Snowvocaine:BAAALgAECgcJDwAAAA==.',
So='Soladriel:BAAALgAECgMJAwABLgAECgcJHwAIALcjAA==.Sorabjr:BAAALgAECgUJDwAAAA==.Sorim:BAAALgADCgcJCgAAAA==.Soulbreaker:BAABLgAECn8aAAMXAAcJFx4RCgDoAQAXAAcJFx4RCgDoAQAFAAEJpgK80gAZAAAAAA==.Soulstice:BAAALgAECgMJBQAAAA==.',
Sp='Spandexshoe:BAAALgADCgMJAwAAAA==.Spewn:BAAALgAECgYJCQAAAA==.Spyrofella:BAACLgAFFH8MAAINAAQJahbAEwA8AQANAAQJahbAEwA8AQAuAAQKfxoAAw0ACQmVILkFACkDAA0ACQmVILkFACkDAA4AAQmyF8Y/ADEAAAAA.',
Sq='Squeance:BAAALgAECgYJCwAAAA==.',
Sr='Sroopsalot:BAAALgAECgQJBAAAAA==.',
St='Starblunder:BAAALgAECgYJBgAAAA==.Steppriest:BAAALgADCgEJAQAAAA==.Sticky:BAAALgAECgcJEAAAAA==.Stormaranian:BAAALgAECgMJAwABLgAFFAIJBQAIAPIYAA==.Stormwild:BAAALgAECgMJBQABLgAECgYJDwAKAAAAAA==.Styleaug:BAABLgAECn8UAAINAAcJ4A8VHgBOAQANAAcJ4A8VHgBOAQAAAA==.',
Su='Sundersremix:BAAALgAECgEJAQAAAA==.Sunsparrow:BAAALgAECgQJDQAAAA==.',
Sw='Swamp:BAAALgADCgMJBAAAAA==.Swankdave:BAAALgAECgMJBQAAAA==.Sweetchicka:BAAALgADCgUJBQAAAA==.Swiftysarah:BAAALgADCgMJBAABLgAFFAUJDwAGAB4MAA==.',
Sy='Syvarris:BAACLgAFFH8FAAIeAAMJRRhwDQALAQAeAAMJRRhwDQALAQAuAAQKfxUAAh4ACAlxGscJAEECAB4ACAlxGscJAEECAAAA.',
['Sè']='Sèvènthshade:BAAALgADCgEJAQAAAA==.',
['Sî']='Sîpher:BAAALgAECgEJAQAAAA==.',
['Sú']='Súndavar:BAEALgADCgMJAwABLgAFFAQJEQAJAPIdAA==.',
Ta='Taborax:BAAALgAECgYJDAAAAA==.Taeveren:BAAALgAECgUJCAAAAA==.Taikwondoh:BAAALgAECgYJBgABLgAECgkJJAALAAoOAA==.Tandaiff:BAAALgAECgYJCwAAAA==.Tandea:BAAALgAECgEJAgAAAA==.Taner:BAABLgAECn8VAAIkAAgJhRaiHgDkAQAkAAgJhRaiHgDkAQAAAA==.Tankajahari:BAABLgAECn8XAAIMAAkJOA/0KADcAQAMAAkJOA/0KADcAQAAAA==.Tarayn:BAABLgAECn8jAAMWAAcJuSI4BABKAgAWAAcJuSI4BABKAgAMAAMJHgxppQCnAAAAAA==.Tazenath:BAAALgAECgYJDwAAAA==.',
Te='Teagan:BAAALgADCgQJBAAAAA==.Tealeaf:BAAALgAECgcJBwAAAA==.Teeagan:BAAALgADCgYJBgAAAA==.Teoritta:BAEBLgAECn8jAAMeAAcJMxThEQCTAQAeAAcJMxThEQCTAQAjAAEJ+AN4lAAlAAAAAA==.',
Th='Thalimus:BAAALgAECgQJBwAAAA==.Thedarkbagel:BAAALgAECgIJAgAAAA==.Thefarter:BAAALgAECgYJCwAAAA==.Theldor:BAAALgAECgMJAwAAAA==.Thewhitelion:BAAALgAECgUJDAAAAA==.Thickbacon:BAAALgAECgUJBQAAAA==.Thorin:BAAALgADCgYJCAABLgAECggJIAAZAJUhAA==.Thorzson:BAAALgAECgEJAQAAAA==.Thudd:BAAALgADCgcJFgAAAA==.Thìerry:BAACLgAFFH8KAAIGAAMJHx/6PAAaAQAGAAMJHx/6PAAaAQAuAAQKfyoAAwYACAlJJccMAF4DAAYACAlAJccMAF4DACgABglMIsUFAMoBAAAA.',
Ti='Tigg:BAACLgAFFH8LAAMJAAQJPx9+GgBuAQAJAAQJPx9+GgBuAQAnAAIJ/g6tBgCeAAAuAAQKfyMAAwkACAnJIAAmAKQCAAkACAnJIAAmAKQCACcACAnQDgIIACcBAAAA.Tirrenus:BAAALgAECgQJDAAAAA==.Tiwi:BAAALgADCgYJBgAAAA==.',
To='Tonytonychop:BAAALgAECgQJDAABLgAECgcJKgAEADoSAA==.Tory:BAAALgAECgEJAQAAAA==.Toshidot:BAACLgAFFH8MAAIZAAQJ8RF8KAAgAQAZAAQJ8RF8KAAgAQAuAAQKfycAAhkACAn9Hr0bAK4CABkACAn9Hr0bAK4CAAAA.Toshy:BAAALgAECgQJBAABLgAFFAQJDAAZAPERAA==.Totesmygoats:BAABLgAECn8WAAIRAAYJGg8COAApAQARAAYJGg8COAApAQAAAA==.',
Tr='Translucent:BAABLgAECn8qAAMbAAgJjQrmIQBCAQAbAAgJjQrmIQBCAQARAAYJsgSbZQD4AAAAAA==.Trap:BAAALgAECgEJAgABLgAECgYJCgAKAAAAAA==.Travaman:BAABLgAECn8XAAIbAAcJExRpIgA+AQAbAAcJExRpIgA+AQAAAA==.Trazatra:BAABLgAECn8ZAAMQAAkJbQ/DGQC/AQAQAAkJbQ/DGQC/AQANAAUJrBVNPwDsAAAAAA==.Treelock:BAAALgADCgEJAQAAAA==.Treestars:BAAALgAECgUJBgAAAA==.Truelilimain:BAAALgADCgYJCgAAAA==.',
Tu='Tunalongarms:BAAALgADCgcJDQABLgAECgYJDwAKAAAAAA==.Tuonadari:BAAALgAECgMJBQAAAA==.Tusknus:BAAALgAECggJCQAAAA==.Tusthree:BAEBLgAECn8VAAMJAAcJGB7jKQDVAQAJAAcJ1h3jKQDVAQAfAAEJ0hziMABVAAABLgAECggJKAALAL4cAA==.Tustone:BAEBLgAECn8oAAMLAAgJvhyJEgB+AgALAAgJvhyJEgB+AgAMAAUJIxq1VwBCAQAAAA==.',
Tw='Twelfthplnet:BAAALgAECgIJAgAAAA==.',
['Tù']='Tùst:BAEBLgAECn8bAAMDAAcJ0xbCPgCoAQADAAYJjRfCPgCoAQAEAAcJvg0MIAA3AQABLgAECggJKAALAL4cAA==.',
Ur='Ursôc:BAAALgAECgMJAwABLgAFFAUJDwAGAB4MAA==.Urzukul:BAAALgAECgEJAgAAAA==.',
Us='Usodead:BAAALgAECgYJEAAAAA==.',
Va='Vacia:BAAALgAECgQJBgAAAA==.Vader:BAAALgAECgEJAQABLgAECgcJHAAbAJEYAA==.Valaeh:BAAALgAECgIJAwAAAA==.Valgor:BAAALgADCggJFQAAAA==.Valkurichi:BAAALgADCgYJBgABLgAFFAYJGgAJAHEmAA==.Valkuridk:BAACLgAFFH8aAAMJAAYJcSZYAQAjAgAJAAYJcSZYAQAjAgAnAAEJriQhCABoAAAuAAQKfx8AAgkACQmBJskFAHkDAAkACQmBJskFAHkDAAAA.Vallerian:BAAALgADCgQJBAAAAA==.Vandy:BAABLgAECn8WAAIVAAkJvB52CQC0AgAVAAkJvB52CQC0AgAAAA==.Vanthe:BAAALgADCgcJBwAAAA==.Vaygrant:BAAALgAECgIJAgAAAA==.',
Ve='Vedo:BAABLgAECn8wAAMkAAkJGyaJAAB1AwAkAAkJ3SWJAAB1AwAjAAgJbSEeCAAdAwAAAA==.Vedora:BAAALgADCgMJBQAAAA==.Velensia:BAAALgADCgkJHQAAAA==.Velf:BAAALgAECgEJAgAAAA==.Velind:BAAALgADCgkJDAAAAA==.Velnela:BAAALgADCgEJAQAAAA==.Veradis:BAAALgAECgMJAwAAAA==.Vetro:BAABLgAECn8gAAICAAgJOBO3BQCbAQACAAgJOBO3BQCbAQAAAA==.',
Vi='Vindar:BAAALgAECgQJBgAAAA==.Vinland:BAAALgAECgIJAQAAAA==.Vinsmokesanj:BAAALgAECgQJBQAAAA==.Violet:BAAALgAECgQJCQAAAA==.Viris:BAABLgAECn8eAAMIAAgJ2RK3FAC1AQAIAAgJ2RK3FAC1AQAgAAYJiBARJgARAQAAAA==.Virulent:BAAALgAECgMJBQAAAA==.Visell:BAAALgAECgYJBgAAAA==.Vissarion:BAABLgAECn8cAAIWAAcJhh3GBwDWAQAWAAcJhh3GBwDWAQAAAA==.',
Vl='Vl:BAAALgAECgcJEgAAAA==.Vladak:BAABLgAECn8UAAIpAAgJPQRxEQAWAQApAAgJPQRxEQAWAQAAAA==.',
Vo='Voc:BAAALgAECggJCgAAAA==.Voidschlong:BAAALgAECgkJBwAAAA==.Voluptus:BAAALgAECgYJEwAAAA==.',
Vu='Vulkin:BAABLgAECn8cAAIbAAcJkRiVFQCmAQAbAAcJkRiVFQCmAQAAAA==.Vulric:BAAALgADCgYJBgAAAA==.',
Vv='Vv:BAABLgAECn8gAAIkAAkJwRq/FwB7AgAkAAkJwRq/FwB7AgAAAA==.',
Vy='Vyridion:BAAALgADCgMJAwAAAA==.Vyridionsham:BAAALgAECgUJDAAAAA==.Vyx:BAABLgAECn8XAAIZAAYJbBzSLwCkAQAZAAYJbBzSLwCkAQAAAA==.',
Wa='Warkast:BAAALgAECgUJDgAAAA==.Waymán:BAAALgADCgcJDgAAAA==.',
We='Weebjones:BAAALgAECggJEwAAAA==.Welkin:BAAALgADCgEJAQAAAA==.',
Wi='Windrift:BAABLgAECn8kAAIVAAcJIwYAKAAKAQAVAAcJIwYAKAAKAQAAAA==.',
Wo='Worgenformer:BAAALgADCgYJBQAAAA==.Worgenmytail:BAAALgADCgMJAwAAAA==.',
Wy='Wyldone:BAAALgADCgYJBgAAAA==.',
['Wà']='Wànderlust:BAAALgAECgIJAgAAAA==.',
['Wä']='Wäyman:BAABLgAECn8qAAIUAAgJPBb1BQDpAQAUAAgJPBb1BQDpAQAAAA==.',
['Wî']='Wînë:BAAALgADCgEJAQAAAA==.',
Xa='Xanden:BAAALgADCgYJBwAAAA==.Xaranthia:BAABLgAECn8iAAIXAAkJyhJGGAAFAgAXAAkJyhJGGAAFAgAAAA==.',
Xe='Xembra:BAAALgAECgYJCwAAAA==.',
Xh='Xhyon:BAABLgAECn8gAAIkAAgJ8xi2JADCAQAkAAgJ8xi2JADCAQAAAA==.',
Xi='Xiamira:BAAALgAECgQJDAAAAA==.',
Xm='Xmcdizzle:BAABLgAECn8mAAIGAAgJoRcYJgAMAgAGAAgJoRcYJgAMAgAAAA==.',
Xy='Xylarra:BAABLgAECn8rAAMXAAgJ5yDKAwCZAgAXAAgJ5yDKAwCZAgAFAAEJAADg2gAAAAAAAA==.Xyz:BAAALgAFFAEJAQAAAA==.',
Ya='Yautja:BAABLgAECn8rAAIjAAgJ3BhOBAD6AQAjAAgJ3BhOBAD6AQAAAA==.',
Yo='Yojím:BAAALgAECgUJBQAAAA==.Yoruba:BAAALgAECgMJAwABLgAECgYJGAAQAGoRAA==.',
Yu='Yuenna:BAAALgADCgUJBQABLgAECgYJIAAQAPIdAA==.Yus:BAAALgAECgIJAgAAAA==.',
Za='Zaleyne:BAAALgADCgEJAQAAAA==.Zamali:BAABLgAECn8iAAMfAAcJZBCuFQAmAQAfAAcJZBCuFQAmAQAJAAUJ5whFigDMAAAAAA==.Zantris:BAABLgAECn8cAAIBAAcJUh5CDADcAQABAAcJUh5CDADcAQAAAA==.Zaralystia:BAAALgADCgkJGwAAAA==.Zartella:BAABLgAECn8YAAMkAAYJdBmbPQC4AQAkAAUJHR+bPQC4AQAeAAUJtwxdIQDzAAAAAA==.',
Ze='Zeleste:BAAALgAECgEJAwAAAA==.Zelti:BAAALgAECgYJBgAAAA==.Zendraza:BAAALgAECgYJBwAAAA==.Zenowulf:BAAALgADCggJFQAAAA==.Zephyrion:BAABLgAFFH8IAAIfAAQJPgsbFQCsAAAfAAQJPgsbFQCsAAABLgAECgkJCQAKAAAAAA==.Zepplin:BAABLgAECn8XAAIeAAcJ+BXREgCHAQAeAAcJ+BXREgCHAQAAAA==.Zetro:BAAALgADCgYJBwAAAA==.',
Zi='Zionus:BAAALgADCgEJAQAAAA==.',
Zr='Zreydyn:BAAALgADCgMJBAAAAA==.',
Zu='Zuma:BAABLgAECn8rAAIGAAgJ2BpiLgDnAQAGAAgJ2BpiLgDnAQAAAA==.',
Zy='Zyhunt:BAAALgADCggJCwAAAA==.',
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

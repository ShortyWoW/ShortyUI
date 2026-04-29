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

local lookup = {'Hunter-BeastMastery','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Shaman-Restoration','Mage-Frost','Monk-Mistweaver','Unknown-Unknown','Paladin-Holy','Druid-Restoration','DemonHunter-Vengeance','Monk-Brewmaster','Shaman-Elemental','Paladin-Retribution','DeathKnight-Unholy','DeathKnight-Blood','DemonHunter-Devourer','Paladin-Protection','Druid-Guardian','Mage-Fire','Warrior-Fury','Shaman-Enhancement','Priest-Holy','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Druid-Balance','DemonHunter-Havoc','Mage-Arcane','Priest-Shadow','Monk-Windwalker','DeathKnight-Frost','Rogue-Subtlety','Druid-Feral','Priest-Discipline','Hunter-Marksmanship','Warrior-Protection','Hunter-Survival','Warrior-Arms',}
local provider = {region='US',realm="Cho'gall",name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Abeblinken:BAAALgAECgEJAQAAAA==.',
Ad='Adym:BAABLgAECn8WAAIBAAgJVxr0HABYAgABAAgJVxr0HABYAgAAAA==.',
Ae='Aethos:BAABLgAECn8mAAQCAAcJXRssCQDeAQACAAcJXRssCQDeAQADAAEJ+xcRKwBJAAAEAAEJAABlZABGAAAAAA==.Aeyther:BAAALgAECggJEwAAAA==.',
Ag='Agave:BAABLgAECn8cAAIFAAgJBxLTDABwAQAFAAgJBxLTDABwAQAAAA==.',
Ah='Ahluethedrud:BAAALgADCgUJBQAAAA==.',
Ai='Airbnb:BAAALgADCgQJBAAAAA==.',
Al='Aleynah:BAAALgADCggJFAABLgAECgcJIwAEALkHAA==.Alukarrd:BAAALgAECgIJAgAAAA==.',
Am='Amoraniel:BAABLgAECn8eAAIGAAgJaiFwBQBdAgAGAAgJaiFwBQBdAgAAAA==.Amortin:BAAALgADCgEJAQAAAA==.',
An='Anavar:BAABLgAECn8aAAIHAAkJWhfODgBqAgAHAAkJWhfODgBqAgAAAA==.Ancestral:BAAALgADCgEJAQABLgAECgkJFAAIAAAAAA==.Andrar:BAAALgADCgEJAQAAAA==.Andresra:BAABLgAECn8UAAIGAAcJ3RceZwAJAgAGAAcJ3RceZwAJAgAAAA==.Angelle:BAABLgAECn8cAAIJAAgJ6CAVAQDSAgAJAAgJ6CAVAQDSAgAAAA==.Annakin:BAABLgAECn8cAAIKAAgJyxp2BwDvAQAKAAgJyxp2BwDvAQAAAA==.Annaluna:BAAALgAECgIJAQAAAA==.Anomally:BAAALgADCgMJAwAAAA==.Anzhelika:BAAALgADCgMJAwAAAA==.',
Ar='Arararagi:BAAALgADCgcJCAAAAA==.Arawn:BAAALgADCgYJBgAAAA==.Arctica:BAABLgAECn8cAAILAAgJPB7NAwCPAgALAAgJPB7NAwCPAgAAAA==.Arelà:BAAALgAFFAEJAQAAAA==.Aria:BAAALgAECgYJEgAAAA==.Articdemon:BAAALgADCgkJFAAAAA==.Artics:BAAALgAECgEJAQAAAA==.Arylynn:BAAALgADCgYJBgABLgAECggJGwAMAHUlAA==.',
As='Astradaeus:BAAALgADCgMJAwAAAA==.Astridaya:BAAALgAECgEJAQAAAA==.',
Au='Aunumator:BAAALgADCgcJEAAAAA==.',
Av='Avâtre:BAABLgAECn8YAAINAAgJtQ8LDgAhAQANAAgJtQ8LDgAhAQAAAA==.',
Ba='Baba:BAAALgADCgcJAQAAAA==.Baeblue:BAAALgAECgEJAgABLgAECggJFQAOAEsXAA==.Bajingobomb:BAABLgAECn8cAAMPAAgJKBwJLwB8AgAPAAgJKBwJLwB8AgAQAAEJpREpRgAvAAAAAA==.Ballmelazer:BAAALgAECgEJAQAAAA==.Barasuishou:BAAALgAECgEJAQABLgAECgcJFAADAGkgAA==.Barkruffalo:BAABLgAECn8gAAIKAAgJmxifIwAtAgAKAAgJmxifIwAtAgAAAA==.Battleborne:BAAALgADCgEJAQAAAA==.',
Be='Beckyoncé:BAABLgAECn8dAAIRAAgJ5iEeBABSAgARAAgJ5iEeBABSAgAAAA==.Bedris:BAABLgAECn8XAAMOAAYJhQ/4IQAkAQAOAAYJ/Q34IQAkAQASAAUJUAtbKwCyAAAAAA==.Beerticus:BAAALgAECgYJCgAAAA==.Berim:BAAALgAECgQJBQAAAA==.',
Bi='Bigdingus:BAABLgAECn8WAAITAAgJIyCtBQB8AgATAAgJIyCtBQB8AgAAAA==.Binggles:BAACLgAFFH8TAAMGAAYJMB0TBwDvAQAGAAYJMB0TBwDvAQAUAAEJXQHLAQBDAAAuAAQKfx8AAgYACAl+JXESADkDAAYACAl+JXESADkDAAAA.Bingglestwo:BAAALgAECgMJAwABLgAFFAYJEwAGADAdAA==.',
Bl='Blanketparty:BAAALgAECgYJDAAAAA==.Blinkyshadow:BAAALgADCgMJAwAAAA==.Bloodraven:BAABLgAECn8iAAIKAAkJFBxBBgAOAgAKAAkJFBxBBgAOAgAAAA==.Blëwm:BAAALgADCgcJBwABLgAECgYJDAAIAAAAAA==.',
Bo='Boaj:BAABLgAECn8XAAIVAAgJMhcEKAAdAgAVAAgJMhcEKAAdAgAAAA==.Bobette:BAABLgAECn8UAAIWAAgJDwg3FQBpAQAWAAgJDwg3FQBpAQAAAA==.Bodyspray:BAAALgAECggJEAAAAA==.Boolay:BAABLgAECn8WAAISAAgJ9RtSDAACAgASAAgJ9RtSDAACAgAAAA==.Bootyfire:BAABLgAECn8ZAAIGAAgJ9RGDaAAFAgAGAAgJ9RGDaAAFAgAAAA==.Boozing:BAAALgAECgEJAQAAAA==.Bosmina:BAABLgAECn8iAAIXAAkJSBDjBQC/AQAXAAkJSBDjBQC/AQAAAA==.',
Br='Braeibo:BAAALgAECgYJBwAAAA==.Breelynn:BAAALgADCgcJBwAAAA==.Breida:BAAALgAECgMJAwAAAA==.Brenmonk:BAAALgADCggJCAAAAA==.Brielle:BAAALgADCgEJAQAAAA==.Brolerion:BAAALgADCgQJBAAAAA==.',
Bu='Bubblebaddie:BAAALgAECgQJBgAAAA==.Bugenhagen:BAAALgAECgQJCgABLgAECgYJBgAIAAAAAA==.Buttpaladin:BAAALgADCgcJDQAAAA==.',
['Bë']='Bëldin:BAAALgADCggJCwAAAA==.',
Ca='Canelo:BAAALgADCgUJBQAAAA==.Cantheal:BAAALgADCgYJBgAAAA==.Carademuerta:BAAALgAECgcJEAAAAA==.Cardib:BAAALgAFFAIJAgAAAA==.Cavos:BAABLgAECn8gAAIRAAgJnhmwCQDXAQARAAgJnhmwCQDXAQAAAA==.',
Ce='Cernsarn:BAABLgAECn8cAAIQAAgJZQzZBwAYAQAQAAgJZQzZBwAYAQAAAA==.',
Ch='Chandlef:BAAALgAECgQJBAAAAA==.Chantorc:BAAALgADCgYJCgAAAA==.Chickendad:BAAALgAECgUJBQAAAA==.Chigang:BAAALgADCgMJAwAAAA==.Chiri:BAEBLgAECn8YAAQYAAgJkBP9AgBCAQAYAAYJpBD9AgBCAQAZAAYJdQuENQAkAQAaAAUJdAs4DQBhAAAAAA==.Chvngus:BAABLgAECn8cAAIOAAgJ5x+5AgCNAgAOAAgJ5x+5AgCNAgAAAA==.',
Ci='Cindersam:BAAALgAECgYJCQABLgAECgcJFAAPAK0UAA==.',
Co='Cocheeze:BAAALgADCgYJBgAAAA==.Condor:BAEALgAFFAEJAQAAAA==.Conmammoth:BAAALgAECgQJCQAAAA==.Coohwhip:BAAALgAECgcJDgAAAA==.Cowwithhorns:BAABLgAECn8YAAIVAAgJIhJjKgAPAgAVAAgJIhJjKgAPAgAAAA==.',
Cr='Cristobal:BAAALgAECggJDQAAAA==.Cronùs:BAAALgAECgcJCgAAAA==.Crunkshot:BAAALgAECgcJEwAAAA==.',
Cu='Curtis:BAAALgAECgYJDwAAAA==.',
Cy='Cyalaterz:BAAALgAECgEJAQAAAA==.Cyrail:BAABLgAECn8cAAIJAAgJeCSJBQATAwAJAAgJeCSJBQATAwAAAA==.',
['Cø']='Cøven:BAABLgAECn8oAAMbAAgJZx/KDADLAgAbAAgJZx/KDADLAgAKAAMJ1w5ZnQCQAAAAAA==.',
Da='Dan:BAAALgAECgEJAQAAAA==.Darktoxi:BAABLgAECn8ZAAIHAAcJARzOAgA3AgAHAAcJARzOAgA3AgAAAA==.Darthpooper:BAAALgAECgYJBgABLgAECgkJGAAOAE8cAA==.Dauntus:BAACLgAFFH8FAAIGAAMJqA1XEgABAQAGAAMJqA1XEgABAQAuAAQKfx0AAgYACAlYGwEyAKsCAAYACAlYGwEyAKsCAAAA.Dawnclaw:BAAALgADCgUJBQAAAA==.Daydream:BAAALgAECgEJAQAAAA==.',
De='Deathclock:BAABLgAECn8jAAIPAAkJsx0SDQAyAwAPAAkJsx0SDQAyAwAAAA==.Deep:BAAALgADCgEJAQAAAA==.Degey:BAAALgAECgYJEAAAAA==.Deign:BAABLgAECn8iAAIcAAkJVwjEBgBHAQAcAAkJVwjEBgBHAQAAAA==.Delayne:BAAALgAECgcJCAAAAA==.Demoncrat:BAAALgAFFAEJAQAAAA==.Demonicramen:BAAALgAECgIJAgAAAA==.Demonstroza:BAAALgAECgUJBQABLgAECggJCAAIAAAAAA==.Demontotems:BAAALgAECgMJBgAAAA==.Demotoxi:BAAALgAECgYJDQAAAA==.Deriso:BAAALgAECggJDQAAAA==.Derpthyr:BAAALgADCgMJAwAAAA==.Destrozinth:BAAALgAECggJCAAAAA==.Dethorok:BAAALgAECgYJEQAAAA==.Deåth:BAAALgAECgUJBgAAAA==.',
Dh='Dhamon:BAAALgADCgYJBgAAAA==.',
Di='Dieworc:BAAALgADCgkJFgAAAA==.Digey:BAAALgAECggJDAAAAA==.Digitz:BAABLgAECn8cAAMGAAgJTBYSVwAzAgAGAAgJTBYSVwAzAgAdAAEJAABAHgA1AAAAAA==.Direwolf:BAAALgAECgUJBQAAAA==.Dirtnapp:BAAALgAECgMJBQAAAA==.Divah:BAABLgAECn8jAAIEAAcJuQdEJAA4AQAEAAcJuQdEJAA4AQAAAA==.',
Do='Donald:BAABLgAECn8UAAIBAAgJeAwwDwCJAQABAAgJeAwwDwCJAQAAAA==.Donbolo:BAAALgAECgUJCAAAAA==.Dopeaf:BAAALgAECgcJCQAAAA==.Dotpotato:BAAALgADCgIJAgAAAA==.Dotterparty:BAAALgADCgYJCgAAAA==.Dowkia:BAAALgAECgEJAQAAAA==.Downwarddog:BAAALgADCgYJBwAAAA==.',
Dr='Dragonmaas:BAAALgADCgYJBgAAAA==.Dragonwings:BAEBLgAECn8YAAIGAAcJOxbqfQDVAQAGAAcJOxbqfQDVAQAAAA==.Drakah:BAAALgAECgIJAgAAAA==.Drakbek:BAAALgAECgIJAgAAAA==.Dreaknite:BAAALgADCgQJBgAAAA==.Dreamshift:BAAALgAECgcJDgAAAA==.Dreco:BAABLgAECn8aAAIRAAcJrh6DDQCjAQARAAcJrh6DDQCjAQAAAA==.Drekken:BAAALgAECgMJBQAAAA==.Drelik:BAAALgADCgIJAgAAAA==.Dronebot:BAABLgAECn8bAAMeAAgJahsjAwALAgAeAAgJahsjAwALAgAXAAMJngpcZwCPAAAAAA==.Drucifer:BAAALgAECgYJEQAAAA==.Druelf:BAAALgAECgIJAgAAAA==.Druiwny:BAAALgAECgMJAwAAAA==.Drúcifer:BAAALgADCgkJDAAAAA==.',
Du='Dud:BAABLgAECn8WAAICAAYJCBmCHQAwAQACAAYJCBmCHQAwAQAAAA==.Dugaa:BAAALgAECgQJBAAAAA==.Dumbdwagon:BAABLgAECn8cAAIaAAgJSwn/BABkAQAaAAgJSwn/BABkAQAAAA==.Dumblecrumb:BAAALgADCgQJBAAAAA==.Dustyshotz:BAAALgADCgYJBgAAAA==.',
Dw='Dwall:BAAALgAECgMJAwAAAA==.Dwarriorarf:BAAALgAECgEJAQAAAA==.',
Dz='Dzieux:BAAALgADCgYJBwAAAA==.',
['Dë']='Dëadisbetter:BAAALgADCgEJAQAAAA==.',
['Dö']='Dögehh:BAAALgAECgEJAQAAAA==.',
Ee='Eeseo:BAAALgAECgEJAQAAAA==.',
Eg='Eggblack:BAAALgAECgQJBwAAAA==.',
El='Ellegryn:BAAALgADCgEJAgAAAA==.Elvebring:BAABLgAECn8aAAIcAAcJGxohGQD8AQAcAAcJGxohGQD8AQABLgAFFAMJBQAJAFEaAA==.',
Em='Embody:BAABLgAECn8YAAIbAAgJ4w8aBgClAQAbAAgJ4w8aBgClAQAAAA==.',
En='Endlyss:BAAALgADCgcJBwAAAA==.',
Er='Erikira:BAAALgAECgUJCgAAAA==.Erikk:BAAALgAECgYJCQAAAA==.Eryngium:BAAALgAECgYJBgAAAA==.',
Es='Essentia:BAAALgAECgEJAQAAAA==.',
Et='Ethantherat:BAAALgAECgEJAQAAAA==.',
Eu='Euphoricx:BAABLgAECn8lAAIFAAgJYCX3AgBOAwAFAAgJYCX3AgBOAwAAAA==.',
Ev='Evildeader:BAAALgAECgcJEAAAAA==.Eviltotems:BAAALgAECgQJBAABLgAECgcJEAAIAAAAAA==.',
Ex='Exes:BAAALgADCggJCAABLgAECggJIQANAAIfAA==.Expand:BAABLgAECn8UAAIfAAgJUBnUFQA7AgAfAAgJUBnUFQA7AgAAAA==.',
Ey='Eyeseyesbaby:BAAALgAECgcJEQAAAA==.',
Fa='Faithles:BAABLgAECn8fAAIeAAkJgRzNDwCIAgAeAAkJgRzNDwCIAgAAAA==.Falgur:BAABLgAECn8jAAMNAAkJJB01DwCzAgANAAkJJB01DwCzAgAFAAMJxQmyHwCOAAAAAA==.Fantasma:BAAALgAECgQJBgAAAA==.Fasty:BAABLgAECn8cAAIHAAgJYRP1HgC+AQAHAAgJYRP1HgC+AQAAAA==.Faygochugger:BAAALgAECgMJAwAAAA==.',
Fe='Felmajik:BAAALgADCgMJBQAAAA==.',
Fi='Finley:BAAALgADCgMJAwAAAA==.Fivemagics:BAABLgAECn8VAAMCAAcJlxYGcACAAQACAAYJzRQGcACAAQAEAAIJnhTFTgCBAAAAAA==.',
Fl='Fleaboy:BAAALgAECgUJCQAAAA==.Fleshwound:BAAALgADCgYJBgAAAA==.Flist:BAABLgAECn8cAAIfAAgJ6x9ZAQBmAgAfAAgJ6x9ZAQBmAgAAAA==.',
Fo='Fongsaiyok:BAAALgAECgEJAQAAAA==.Foregord:BAAALgADCgUJBQABLgABCgUJBQAIAAAAAA==.Fortlock:BAAALgAECgQJBQAAAA==.Fotation:BAAALgAECgQJBAAAAA==.',
Fr='Frankyice:BAABLgAECn8WAAIeAAgJtA3VBwB8AQAeAAgJtA3VBwB8AQAAAA==.Freesia:BAAALgAECgYJEAAAAA==.French:BAAALgAECggJCwAAAA==.Froggyfresh:BAAALgADCgYJCAAAAA==.Fruitjuice:BAAALgAECgQJCAAAAA==.',
Fu='Funbobby:BAAALgAECgIJAgAAAA==.',
Fx='Fxce:BAAALgAECgQJBAAAAA==.',
['Fâ']='Fâmine:BAABLgAECn8VAAICAAcJqhHFZACdAQACAAcJqhHFZACdAQAAAA==.',
Ga='Gamer:BAAALgADCgcJDAABLgAECgYJCwAIAAAAAA==.Gamergirl:BAAALgAECgYJCwAAAA==.Ganjj:BAAALgAECgEJAQAAAA==.Gawdric:BAACLgAFFH8KAAIPAAQJQhRkDwD9AAAPAAQJQhRkDwD9AAAuAAQKfx0AAw8ACAlWIZgsAIYCAA8ACAlWIZgsAIYCACAAAQnOC0UYAC4AAAAA.',
Ge='Georgesoros:BAAALgAECggJDwAAAA==.',
Gh='Ghibludgeon:BAAALgADCgIJAgAAAA==.Ghiboom:BAAALgAECgEJAgAAAA==.Ghulz:BAAALgAECgQJBAAAAA==.Ghuntarr:BAAALgADCgcJDAAAAA==.',
Gi='Gibsmedats:BAABLgAECn8cAAIRAAgJkRJ2QgDqAQARAAgJkRJ2QgDqAQAAAA==.Giin:BAAALgAECgEJAwAAAA==.Gildark:BAAALgADCgEJAQAAAA==.',
Gl='Glaiven:BAABLgAECn8UAAIRAAgJBR/CHgCZAgARAAgJBR/CHgCZAgAAAA==.Glasscleaner:BAAALgAECgcJEQABLgAECgkJIAAHAIMlAA==.Glenfiddich:BAABLgAECn8YAAIPAAgJZR6KBABKAgAPAAgJZR6KBABKAgAAAA==.',
Gn='Gnartusk:BAABLgAECn8VAAIQAAYJjyM7AgD+AQAQAAYJjyM7AgD+AQAAAA==.Gnomett:BAAALgADCgEJAQAAAA==.',
Gr='Grasswizard:BAAALgAECgcJDgAAAA==.Greela:BAAALgADCgIJAgAAAA==.Greens:BAAALgAECgYJCAAAAA==.Gremory:BAAALgADCgYJBwAAAA==.Gru:BAAALgAECggJDgAAAA==.Grïma:BAAALgADCgcJBwABLgAECggJKAAbAGcfAA==.',
Gu='Gueritestje:BAABLgAECn8dAAISAAgJNiDVAABnAgASAAgJNiDVAABnAgAAAA==.Guzzlord:BAAALgAECggJEAAAAA==.',
Ha='Hanekawa:BAAALgAECgUJBwABLgAECgcJFAADAGkgAA==.Harddwarf:BAAALgAECgEJAQAAAA==.Haugcraneka:BAAALgADCgYJBgAAAA==.Hawts:BAAALgAECgEJAQAAAA==.',
He='Heleous:BAABLgAECn8VAAMOAAgJSxcUVwDdAQAOAAgJSxcUVwDdAQASAAEJHg43RAAuAAAAAA==.',
Hi='Highly:BAAALgADCgIJAgAAAA==.Hikari:BAABLgAECn8jAAIcAAcJtg/ZIAC2AQAcAAcJtg/ZIAC2AQAAAA==.Himalayanman:BAAALgAECgkJDgAAAA==.Hipdrop:BAAALgADCgEJAQAAAA==.Hitemup:BAAALgAECgEJAgAAAA==.Hitoshura:BAAALgAECggJEQAAAA==.',
Ho='Hobbeswerth:BAABLgAECn8UAAIHAAYJExAmEADdAAAHAAYJExAmEADdAAAAAA==.Holycowbun:BAAALgADCggJCAABLgAECggJHAARAPkgAA==.Holyginger:BAAALgAECgUJBQAAAA==.Holyglizzy:BAAALgAECgQJBQAAAA==.Holysoup:BAAALgAECgEJAQAAAA==.Hornlet:BAAALgAECgEJAQABLgAECgIJBAAIAAAAAA==.Howitzerx:BAAALgAECgQJCQAAAA==.',
Hu='Huggies:BAAALgAECgMJBgAAAA==.Humdinger:BAAALgADCgYJCAAAAA==.',
Hy='Hypérîon:BAAALgAECgQJCAAAAA==.',
Ia='Iagging:BAABLgAECn8gAAIHAAkJgyVdAABGAwAHAAkJgyVdAABGAwAAAA==.',
Ic='Iceflinger:BAAALgAECgYJEgAAAA==.',
Id='Idjit:BAAALgADCgcJBwABLgAECgYJBgAIAAAAAA==.Idlehand:BAAALgAECgQJBgAAAA==.',
Ie='Ieatcats:BAABLgAECn8iAAIhAAkJ5BfcAgD+AQAhAAkJ5BfcAgD+AQAAAA==.',
Im='Imarri:BAAALgADCgYJCAAAAA==.Imjustakid:BAAALgADCgMJAwAAAA==.Immahuntyou:BAAALgAECgEJAgAAAA==.Imobelle:BAABLgAECn8fAAIGAAcJlxPRHABnAQAGAAcJlxPRHABnAQAAAA==.Imprepared:BAAALgAECgMJAwAAAA==.',
In='Indrani:BAAALgAECgYJCgAAAA==.Infidel:BAAALgAECgMJAwABLgAFFAUJDQAGAKAMAA==.',
Ip='Ippiekiyaymf:BAAALgAECgYJDgAAAA==.',
Ir='Irishman:BAAALgADCgYJBwAAAA==.',
Is='Ishooturface:BAAALgAECgcJEQAAAA==.István:BAAALgADCgYJBgAAAA==.',
It='Itazki:BAABLgAECn8WAAIiAAgJOh4ICQBHAgAiAAgJOh4ICQBHAgAAAA==.',
Ja='Jardabeans:BAAALgAECgQJCAAAAA==.Jarjárßlinks:BAAALgAECgMJBAAAAA==.Jawz:BAAALgAECgMJBQAAAA==.',
Je='Jelial:BAAALgAECgUJBQAAAA==.Jenga:BAAALgAECgYJBgAAAA==.Jerriblank:BAAALgADCgcJCAAAAA==.',
Jf='Jf:BAAALgAECgcJCQAAAA==.',
Ji='Ji:BAABLgAECn8fAAIfAAgJzBeFFgA0AgAfAAgJzBeFFgA0AgAAAA==.Jibbage:BAACLgAFFH8NAAIGAAUJoAwwDwCeAQAGAAUJoAwwDwCeAQAuAAQKfywAAgYACQnlIDMKAHIDAAYACQnlIDMKAHIDAAAA.Jinkala:BAAALgADCgYJCAAAAA==.Jitzakkal:BAACLgAFFH8RAAMCAAUJ/CMnCwAbAQACAAQJECMnCwAbAQAEAAEJwCYNAwBnAAAuAAQKfx4AAwQACAnaJSkFAIgCAAIACAmUIyoVANYCAAQABgmTJSkFAIgCAAAA.',
Jo='Johnpaladin:BAABLgAECn8hAAISAAgJgh8mBADJAgASAAgJgh8mBADJAgAAAA==.Joshswims:BAABLgAECn8WAAMPAAgJGg8sIwAOAQAPAAgJUQ4sIwAOAQAgAAQJARCuDQDRAAAAAA==.',
Ju='Jussie:BAAALgAECgEJAQAAAA==.',
Ka='Kadriel:BAAALgADCgEJAQAAAA==.Kambo:BAAALgAECgEJAQAAAA==.Kaptainkushh:BAAALgAECgQJEAAAAA==.Kaptkush:BAAALgAECgQJCQAAAA==.Kardinal:BAABLgAECn8fAAMCAAgJxyE6EgDqAgACAAgJaCE6EgDqAgAEAAMJoR/KLAALAQAAAA==.Karig:BAAALgADCgQJBQAAAA==.Karpathous:BAAALgAECgcJDQAAAA==.Karrag:BAAALgAECgEJAQAAAA==.Karzo:BAAALgADCgIJAgAAAA==.Katena:BAAALgAECgYJDwAAAA==.Kaymir:BAABLgAECn8ZAAQjAAYJMRkmIgCDAQAjAAYJIRUmIgCDAQAXAAMJyhxVVQDhAAAeAAEJ+gmTZAAvAAAAAA==.Kazdruid:BAAALgAECgYJBgAAAA==.Kaznathi:BAABLgAECn8bAAIMAAgJdSVlAADzAgAMAAgJdSVlAADzAgAAAA==.',
Ke='Keladorn:BAAALgAECgYJEAAAAA==.Keloril:BAAALgAECgQJCgAAAA==.',
Kh='Khanyiso:BAABLgAECn8cAAISAAgJPxSzAgDBAQASAAgJPxSzAgDBAQAAAA==.Kharak:BAAALgAECgcJDQABLgABCgUJBAAIAAAAAA==.',
Ki='Kieran:BAABLgAECn8ZAAMeAAgJAQuBCgBIAQAeAAcJgwyBCgBIAQAXAAIJPwE8igAiAAAAAA==.Kikimora:BAABLgAECn8WAAMCAAcJNBoBCgDTAQACAAYJNBoBCgDTAQAEAAIJmxdnSACVAAAAAA==.Killsaurus:BAACLgAFFH8GAAIeAAMJrBA2BQDzAAAeAAMJrBA2BQDzAAAuAAQKfyAAAh4ACAn6H1EBAHwCAB4ACAn6H1EBAHwCAAAA.Kilsaurus:BAAALgAECgMJAwAAAA==.Kismetx:BAAALgAECgMJBAAAAA==.Kittysmasher:BAAALgAECgQJBAAAAA==.Kiue:BAAALgADCgEJAQAAAA==.',
Kn='Knomtseb:BAAALgADCgcJDgAAAA==.',
Ko='Koa:BAAALgAECgEJAQAAAA==.Koey:BAAALgAECgIJAgAAAA==.Kosuke:BAAALgADCgUJBQAAAA==.',
Kr='Kriep:BAAALgAECgEJAQAAAA==.Kristian:BAAALgADCgcJBwAAAA==.Krittykitkat:BAAALgADCgYJBgABLgAECgkJGgAHAFoXAA==.Kroshka:BAAALgADCgEJAQAAAA==.',
Kw='Kwarrior:BAAALgADCgkJCQABLgAECggJFgACAC0UAA==.Kwazlock:BAABLgAECn8WAAMCAAgJLRStGwA6AQACAAcJjhGtGwA6AQAEAAMJ2A5JQgCsAAAAAA==.',
Ky='Kyoju:BAAALgAECgYJCgABLgAFFAEJAQAIAAAAAA==.',
La='Laprimera:BAAALgAECgQJBQAAAA==.Lazyjade:BAAALgAECgYJEAAAAA==.',
Le='Leyskrodan:BAABLgAECn8cAAMeAAgJBQxEBwCHAQAeAAgJBQxEBwCHAQAXAAEJKQMQiQAlAAAAAA==.',
Li='Lichborne:BAAALgAECgUJDAAAAA==.Lift:BAAALgADCggJCAABLgAECgkJFAAIAAAAAA==.Listel:BAAALgADCgUJBQAAAA==.',
Lm='Lmnpeprstepr:BAAALgAECgEJAgAAAA==.',
Lo='Lorynn:BAAALgADCgcJBwAAAA==.',
Lu='Lucyna:BAABLgAECn8iAAQEAAgJ4Bw4EwCxAQAEAAUJBh04EwCxAQACAAcJMhsMYwChAQADAAEJAABSIABxAAAAAA==.Lueshen:BAABLgAECn8bAAIfAAcJDx6rFABHAgAfAAcJDx6rFABHAgAAAA==.Luniea:BAAALgAECgEJAQAAAA==.',
Ly='Lysergicburn:BAAALgADCgMJBAABLgAECgQJBgAIAAAAAA==.Lyshin:BAAALgADCgQJBAAAAA==.',
['Lá']='Lárz:BAAALgAECgIJAwAAAA==.',
['Lü']='Lüktar:BAAALgADCgYJBgAAAA==.',
Ma='Madmarsh:BAAALgAECgQJBwABLgAECgkJEgAIAAAAAA==.Madwe:BAAALgAECgYJDAAAAA==.Maggams:BAAALgADCgEJAQAAAA==.Magnaur:BAAALgADCgcJDgAAAA==.Magturri:BAABLgAECn8cAAMBAAgJUyKwCQD8AgABAAgJUyKwCQD8AgAkAAIJihAzdgBmAAAAAA==.Maineck:BAABLgAECn8eAAINAAgJ+BzYEgCLAgANAAgJ+BzYEgCLAgAAAA==.Maketaori:BAAALgADCgYJDAAAAA==.Mambosauce:BAAALgADCgUJBQAAAA==.Mangosmash:BAAALgAECgMJBQAAAA==.Maraline:BAAALgADCgYJBQAAAA==.Marcusdapimp:BAACLgAFFH8JAAIXAAQJzhWfBwDyAAAXAAQJzhWfBwDyAAAuAAQKfyIAAhcACAlsIcoFAPMCABcACAlsIcoFAPMCAAAA.Marymoocow:BAAALgAECgUJCwAAAA==.Matild:BAAALgAECgYJEwAAAA==.Maxdiabolic:BAAALgADCgQJBAAAAA==.Maxfirepower:BAAALgADCgMJAwAAAA==.Maxfrogpower:BAAALgADCgYJBgAAAA==.Maxsunward:BAAALgAECgEJAQAAAA==.Maérline:BAAALgADCgcJDQABLgAECggJGwAeAGobAA==.',
Me='Meatslug:BAAALgADCgMJAwAAAA==.Meepasaurus:BAABLgAECn8YAAIlAAYJMRtMFADHAQAlAAYJMRtMFADHAQAAAA==.Megaforce:BAAALgAECgQJBAAAAA==.Meliiodas:BAABLgAECn8jAAIcAAcJeAoELABoAQAcAAcJeAoELABoAQAAAA==.Mellky:BAABLgAECn8lAAIHAAgJRiR3BQAMAwAHAAgJRiR3BQAMAwAAAA==.Merkin:BAAALgADCgcJBwAAAA==.Merrinx:BAAALgAFFAMJAwAAAA==.Metanoia:BAAALgAECgQJBwAAAA==.',
Mg='Mgamer:BAAALgAECgYJEQAAAA==.Mgämër:BAAALgADCgEJAQAAAA==.',
Mi='Midgetmanxl:BAAALgAECgEJAQAAAA==.Midnitetrvlr:BAAALgAECgYJCwAAAA==.Miima:BAAALgAECgEJAQAAAA==.Minji:BAAALgADCgEJAQAAAA==.Mirren:BAABLgAECn8VAAIGAAcJQBbzigC8AQAGAAcJQBbzigC8AQAAAA==.Missed:BAAALgADCgUJBQABLgAECggJIQANAAIfAA==.Misthios:BAABLgAECn8XAAIhAAgJ2RSlGgAsAgAhAAgJ2RSlGgAsAgAAAA==.Mistkeg:BAAALgAECgYJDQAAAA==.Miteux:BAAALgAECgYJDgAAAA==.Mixxlepit:BAAALgAECggJEgAAAA==.',
Ml='Mlkchocolate:BAAALgADCgkJDwAAAA==.',
Mm='Mmhunt:BAAALgAECgMJAwAAAA==.',
Mo='Mogli:BAAALgADCgYJBgAAAA==.Molyporph:BAAALgAECgEJAQAAAA==.Momojojo:BAABLgAECn8eAAIEAAgJnBmiBACUAgAEAAgJnBmiBACUAgAAAA==.Monre:BAABLgAECn8WAAIRAAgJLxVUSQDPAQARAAgJLxVUSQDPAQAAAA==.Moobss:BAAALgADCgEJAQAAAA==.Moohlawn:BAAALgAECgQJBAABLgAECgUJCQAIAAAAAA==.Moolock:BAAALgAECgUJBQAAAA==.Moonflame:BAABLgAECn8eAAMXAAgJ0xb7JwCwAQAXAAYJsBb7JwCwAQAeAAgJ7wo0DwADAQAAAA==.Moonmajik:BAAALgADCgEJAQAAAA==.Mooriah:BAABLgAECn8XAAIbAAcJVAM3FgCiAAAbAAcJVAM3FgCiAAAAAA==.Moosty:BAAALgAECgIJAgAAAA==.Morphtek:BAAALgAECgYJCgAAAA==.Morphyne:BAABLgAECn8bAAIOAAgJ3xdAPgAsAgAOAAgJ3xdAPgAsAgAAAA==.Moselii:BAAALgADCgEJAQABLgAECgEJAQAIAAAAAA==.Moserr:BAAALgAECgEJAQAAAA==.Motowa:BAAALgADCggJDwAAAA==.',
Mu='Muffin:BAAALgAECgYJEQAAAA==.',
My='Mycilya:BAAALgAECgcJEAAAAA==.Mynchus:BAAALgAECgEJAQAAAA==.Mysterymonk:BAABLgAECn8cAAIHAAcJ8iNpCADQAgAHAAcJ8iNpCADQAgAAAA==.Mysterypala:BAABLgAECn8XAAIJAAcJRiS8CQDXAgAJAAcJRiS8CQDXAgAAAA==.Mysto:BAABLgAECn8gAAMcAAcJfBbPHADaAQAcAAcJfBbPHADaAQARAAMJHQNMzABdAAAAAA==.Mystodin:BAAALgAECgIJAgAAAA==.',
['Mä']='Mälförmïtÿ:BAABLgAECn8WAAMXAAgJgxppFgApAgAXAAgJgxppFgApAgAeAAUJnBJxNwAyAQAAAA==.',
Na='Nacon:BAAALgAECgQJCgAAAA==.Naneko:BAABLgAECn8WAAIGAAgJNQmdMAAGAQAGAAgJNQmdMAAGAQAAAA==.Nardass:BAAALgADCgEJAQAAAA==.Narrator:BAAALgAECgYJCAAAAA==.Nawwl:BAAALgADCgcJDgAAAA==.',
Ne='Neamheaglach:BAAALgADCgQJBAABLgAFFAEJAQAIAAAAAA==.Neotahr:BAABLgAECn8hAAMkAAgJUh3rEQCmAgAkAAgJUh3rEQCmAgABAAMJzhcfmwCcAAAAAA==.Neroiki:BAAALgADCgUJBQAAAA==.Neurôn:BAEALgAECgQJBAAAAA==.Nezra:BAABLgAECn8WAAIjAAgJVRRyGgDEAQAjAAgJVRRyGgDEAQAAAA==.',
Ni='Nicckkcc:BAAALgADCgYJCAAAAA==.Nightquil:BAAALgADCgIJAgAAAA==.Nim:BAABLgAECn8YAAIlAAcJkQ2vHgBPAQAlAAcJkQ2vHgBPAQAAAA==.Nitehunter:BAABLgAECn8WAAIBAAYJmxAUVgBmAQABAAYJmxAUVgBmAQAAAA==.',
No='Nomad:BAAALgAECgQJBQAAAA==.',
Nu='Nubshock:BAAALgAECgEJAQAAAA==.',
Ny='Nyatsua:BAAALgADCgEJAQAAAA==.',
Oi='Oistos:BAAALgADCgcJCwAAAA==.',
Om='Omid:BAAALgADCgYJCgAAAA==.',
On='Ondarklena:BAAALgADCgEJAQAAAA==.Onlydans:BAABLgAECn8WAAISAAgJoRnTCwAMAgASAAgJoRnTCwAMAgAAAA==.',
Oo='Oomfie:BAAALgADCgkJDAAAAA==.',
Ou='Ouch:BAAALgAECgUJBQAAAA==.',
Oy='Oyakev:BAAALgADCggJCgAAAA==.',
Pa='Pabiloneta:BAAALgAECgQJBQAAAA==.Painzir:BAAALgAECgcJEwAAAA==.Palamyne:BAAALgADCgYJBgAAAA==.Pallyana:BAAALgAECgYJDwAAAA==.Palosdin:BAAALgADCgIJAgAAAA==.Pandangerous:BAAALgADCgQJBQAAAA==.Parch:BAAALgADCgcJBwABLgAECggJHAAfAOsfAA==.Parsleyposh:BAAALgADCgMJAgAAAA==.',
Pe='Peace:BAABLgAECn8hAAIeAAgJ6Br0DwCGAgAeAAgJ6Br0DwCGAgAAAA==.Pepsweat:BAAALgADCgUJBQAAAA==.Perilc:BAAALgADCgQJBAAAAA==.Perimones:BAAALgAECgQJCAAAAA==.',
Ph='Phteve:BAAALgADCgUJBwAAAA==.',
Pi='Pigfeet:BAAALgADCgcJCwAAAA==.Pillows:BAAALgADCgYJCgAAAA==.',
Pl='Plapper:BAAALgADCgMJAwABLgAECgYJCwAIAAAAAA==.',
Po='Ponytale:BAAALgADCgYJBgAAAA==.Popaheal:BAABLgAECn8dAAMXAAUJ5iGoIQDWAQAXAAUJ5iGoIQDWAQAeAAEJHAheYwAyAAAAAA==.Portali:BAAALgADCgkJFAAAAA==.',
Pr='Praystatiøn:BAAALgADCgcJBwAAAA==.Proticus:BAAALgAECgMJAwAAAA==.',
Ps='Psychodad:BAAALgADCgcJCAAAAA==.Psyop:BAAALgADCgQJBQABLgAECgMJBAAIAAAAAA==.',
Pu='Purplepain:BAAALgAFFAEJAQAAAA==.Purplod:BAABLgAECn8WAAIPAAgJ7wtMhAB6AQAPAAgJ7wtMhAB6AQAAAA==.',
Py='Pyatpree:BAAALgAECgUJBwAAAA==.',
['Pä']='Päntera:BAABLgAECn8WAAImAAcJ2RvoCQA+AgAmAAcJ2RvoCQA+AgAAAA==.',
Qi='Qing:BAAALgAECgYJDAAAAA==.',
Qt='Qtrpounder:BAAALgAECggJCgAAAA==.',
Qy='Qybxboogied:BAAALgAECgIJAgAAAA==.',
Ra='Raensong:BAAALgADCgEJAQAAAA==.Rafterman:BAAALgAECgEJAgAAAA==.Rahdric:BAAALgAECgYJCgAAAA==.Raisa:BAABLgAECn8ZAAMCAAgJQx6zEACLAQACAAUJ3ByzEACLAQAEAAQJ1B8tHABtAQAAAA==.Rakarum:BAAALgAECgUJCwAAAA==.Rasar:BAABLgAECn8aAAIGAAgJVyAbIwDmAgAGAAgJVyAbIwDmAgAAAA==.Rayleena:BAAALgAECgEJAQAAAA==.Rayo:BAAALgAECgQJBAAAAA==.',
Re='Reginald:BAAALgADCgcJDgAAAA==.Reigh:BAAALgADCgQJBAAAAA==.Rektington:BAAALgAECggJEwAAAA==.Remmag:BAABLgAECn8iAAIGAAcJKyUtHgD8AgAGAAcJKyUtHgD8AgAAAA==.Rett:BAAALgADCgcJEQABLgAECggJGgAnAIYeAA==.Rexxy:BAAALgAECgYJDgAAAA==.',
Ri='Riott:BAAALgADCggJDwAAAA==.Rippednstiff:BAAALgADCgYJBgAAAA==.',
Ro='Roflmeister:BAAALgAECgYJEQAAAA==.Rognroll:BAAALgADCggJCAAAAA==.Romoko:BAABLgAECn8eAAINAAgJpBbqIAAIAgANAAgJpBbqIAAIAgAAAA==.Rorshk:BAAALgAECgYJCgAAAA==.Royal:BAAALgAECgEJAQAAAA==.Roysham:BAAALgAECgYJEgAAAA==.Roywar:BAAALgAECgEJAgAAAA==.',
Ru='Rubianne:BAABLgAECn8aAAIKAAYJeQrXFwAAAQAKAAYJeQrXFwAAAQAAAA==.Rumrunner:BAAALgAECggJCwAAAA==.',
Ry='Rycicle:BAAALgADCgYJBQABLgAECgEJAQAIAAAAAA==.Rynhardt:BAAALgAECgEJAQAAAA==.Ryolith:BAAALgADCgMJAwAAAA==.',
['Rø']='Rønea:BAAALgADCgkJEgAAAA==.',
['Rý']='Rýfle:BAAALgADCgEJAQABLgAECgEJAQAIAAAAAA==.',
Sa='Sacrus:BAAALgAECgYJDwAAAA==.Santoss:BAAALgADCgYJDgAAAA==.Sarah:BAABLgAECn8iAAMmAAgJkCGLAACmAgAmAAgJSSGLAACmAgAkAAEJuCIRdwBjAAABLgAECggJGwAeAJIdAA==.',
Sc='Scottscrx:BAAALgADCgUJBQAAAA==.Scrotes:BAAALgAECgYJDQAAAA==.',
Se='Seer:BAABLgAECn8WAAIRAAgJ0BaDHQAaAQARAAgJ0BaDHQAaAQAAAA==.Seilah:BAAALgADCgcJCgAAAA==.Selbi:BAABLgAECn8aAAIEAAgJwBQBAQDWAQAEAAgJwBQBAQDWAQAAAA==.Senjougahara:BAACLgAFFH8OAAIgAAQJphpXAAB0AQAgAAQJphpXAAB0AQAuAAQKfyEAAyAABwnAJUcBAPcCACAABwnAJUcBAPcCAA8AAQnCB9YqASsAAAAA.Serav:BAAALgADCgIJAgAAAA==.Seravonas:BAAALgADCgcJBwAAAA==.Seravonta:BAAALgAECgEJAgAAAA==.Serial:BAABLgAECn8cAAINAAgJDSAuAQCSAgANAAgJDSAuAQCSAgAAAA==.Seriyah:BAACLgAFFH8GAAIiAAIJHQyLBACoAAAiAAIJHQyLBACoAAAuAAQKfxcAAiIABwntGKYKABwCACIABwntGKYKABwCAAAA.Serph:BAAALgAECgcJBQAAAA==.',
Sh='Shabane:BAABLgAECn8VAAIMAAYJgBBgDQAaAQAMAAYJgBBgDQAaAQAAAA==.Shaggyspaggy:BAAALgAECgUJBQAAAA==.Shambulañcé:BAAALgAECgYJCgAAAA==.Shanbubu:BAAALgAECgEJBAAAAA==.Shasta:BAAALgADCgYJBgAAAA==.Shekari:BAAALgAECgEJAQAAAA==.Shenanigins:BAAALgADCgUJBQAAAA==.Shiftey:BAAALgADCggJCAABLgAECgcJEwAIAAAAAA==.Shilera:BAAALgADCgYJDwAAAA==.Shiminy:BAAALgAECgcJCwAAAA==.Shinobi:BAABLgAECn8YAAIfAAgJyBdgBAC9AQAfAAgJyBdgBAC9AQAAAA==.Shiol:BAABLgAECn8XAAMCAAgJUR5PJACCAgACAAcJFR5PJACCAgAEAAQJbx69IQBHAQAAAA==.Shirls:BAABLgAECn8WAAMOAAgJ3xpzRwANAgAOAAgJ3xpzRwANAgAJAAUJHhRUWAAaAQAAAA==.Shivak:BAABLgAECn8iAAIZAAkJGRIBBQC5AQAZAAkJGRIBBQC5AQAAAA==.Shivanie:BAAALgAECgYJEQAAAA==.Shock:BAABLgAECn8hAAMNAAgJAh/hDgC4AgANAAgJAh/hDgC4AgAFAAEJ2RBolwBBAAAAAA==.Shocknorris:BAAALgAECgUJBQAAAA==.Shîftycent:BAABLgAECn8ZAAQKAAcJbQktYgArAQAKAAcJbQktYgArAQAbAAYJ1QtMEwDIAAAiAAEJ0wDaOwAKAAAAAA==.',
Si='Siccem:BAAALgAECgYJBwABLgAECgcJIAAbAJgdAA==.Sienfonson:BAAALgADCgMJAwAAAA==.',
Sk='Skaffos:BAAALgADCgUJBQABLgADCgYJBgAIAAAAAA==.Skaffoz:BAAALgADCgEJAQABLgADCgYJBgAIAAAAAA==.Skafz:BAAALgADCgYJBgAAAA==.Skik:BAABLgAECn8cAAIlAAcJyhSzFQCyAQAlAAcJyhSzFQCyAQAAAA==.Skylines:BAAALgAECgYJBgAAAA==.Skylinez:BAACLgAFFH8IAAINAAUJVQc+CADKAAANAAUJVQc+CADKAAAuAAQKfxoAAg0ACQnSHWcWAGcCAA0ACQnSHWcWAGcCAAAA.Skïttles:BAAALgAECgcJEwAAAA==.',
Sl='Sleezball:BAAALgADCgEJAwAAAA==.Sloppyhog:BAAALgAECgkJEgAAAA==.Sloppyslice:BAAALgAECgEJAQABLgAECgMJBAAIAAAAAA==.',
Sm='Smobo:BAAALgAECgEJAQAAAA==.Smolder:BAAALgAECgUJCQABLgAECgkJFAAIAAAAAA==.',
Sn='Snoz:BAAALgADCgEJAQAAAA==.',
So='Sobek:BAAALgAECgYJCAAAAA==.Soeuphoric:BAAALgAECgcJBwAAAA==.Sonicfear:BAAALgAFFAEJAQAAAA==.Sonictide:BAAALgAECgUJBQAAAA==.Souahang:BAAALgAECgEJAgAAAA==.Soviette:BAAALgADCgcJDQAAAA==.',
Sp='Spaghetto:BAABLgAECn8cAAIbAAgJOBYGBgCmAQAbAAgJOBYGBgCmAQAAAA==.Sparx:BAAALgAECgEJAgAAAA==.Spicytacoo:BAAALgAECgUJBQAAAA==.',
St='Stacy:BAAALgADCgMJAwAAAA==.Stankystank:BAABLgAECn80AAMCAAUJWxDqJQD9AAACAAUJWxDqJQD9AAAEAAEJVwTfegAnAAAAAA==.Stepdag:BAABLgAECn8eAAIMAAkJrwo1CQBeAQAMAAkJrwo1CQBeAQAAAA==.Stinkydagger:BAAALgADCgIJAgAAAA==.Stoutshrike:BAAALgAECggJEQAAAA==.Strive:BAABLgAECn8cAAQeAAgJ0ghJNABHAQAeAAYJDgpJNABHAQAjAAcJ4gUsCwAXAQAXAAQJTRVPUwDpAAAAAA==.',
Sw='Sweetfeed:BAAALgADCgcJCgAAAA==.',
Sy='Synder:BAABLgAECn8YAAIZAAcJKAPCEADiAAAZAAcJKAPCEADiAAAAAA==.',
Sz='Szmata:BAAALgAECgYJEAAAAA==.',
['Só']='Sóth:BAAALgADCgEJAQAAAA==.',
Ta='Tabata:BAABLgAECn8cAAIlAAgJ+hNwAwC3AQAlAAgJ+hNwAwC3AQAAAA==.Tahharruk:BAAALgAECgQJCwAAAA==.Tailwind:BAAALgADCgUJBAAAAA==.Talivandril:BAAALgAECgEJAQAAAA==.Talogos:BAAALgAECgIJAgAAAA==.Talvan:BAAALgADCgcJBwAAAA==.Tankowner:BAAALgADCgUJBQAAAA==.Tarkdoxicity:BAAALgADCgcJCgAAAA==.Tarynna:BAABLgAECn8VAAICAAYJBQ93HAA1AQACAAYJBQ93HAA1AQAAAA==.Tawxx:BAAALgAECgUJBQAAAA==.',
Te='Teagen:BAABLgAECn8aAAINAAcJ3Rb1BwCCAQANAAcJ3Rb1BwCCAQAAAA==.Teleprompter:BAAALgAECgYJEgAAAA==.Teleros:BAAALgADCgcJDQAAAA==.Telrissan:BAAALgAECgYJBgAAAA==.Tenyroldemon:BAAALgAECggJEwAAAA==.Tenzingyatso:BAAALgAECgcJAgAAAA==.',
Th='Thald:BAABLgAECn8bAAIMAAgJWSB6EACWAgAMAAgJWSB6EACWAgAAAA==.Thari:BAAALgADCgIJAgAAAA==.Thepooper:BAABLgAECn8YAAIOAAkJTxyfBgAmAgAOAAkJTxyfBgAmAgAAAA==.Thunderball:BAABLgAECn8cAAIGAAgJ4xcdUQBEAgAGAAgJ4xcdUQBEAgAAAA==.',
Ti='Tinyaminals:BAAALgADCgYJBgAAAA==.Tisagosa:BAAALgADCgYJCAABLgAECgkJIgAGAAMlAA==.Tisakna:BAABLgAECn8iAAMGAAkJAyXSAgCnAgAGAAkJ8yTSAgCnAgAdAAEJwiYrFwBhAAAAAA==.Tiskano:BAAALgADCgYJCwABLgAECgkJIgAGAAMlAA==.Tissaia:BAAALgADCgcJDAABLgAECgkJIgAGAAMlAA==.Tiszy:BAAALgADCgYJBgAAAA==.Titanx:BAAALgAECgcJDAAAAA==.',
To='Tomatoes:BAAALgAECgQJDQAAAA==.Toothy:BAAALgAECgQJBgAAAA==.Torahdanyse:BAAALgAECgMJAwAAAA==.',
Tr='Trask:BAABLgAECn8WAAIGAAgJzRudXgAfAgAGAAgJzRudXgAfAgAAAA==.Trogdoor:BAAALgAECgEJAQAAAA==.Troko:BAAALgAECgcJBwABLgAECggJGwAGAHElAA==.Trokom:BAABLgAECn8bAAIGAAgJcSU6DQBbAwAGAAgJcSU6DQBbAwABLgAECggJGwAGAHElAA==.',
Tu='Tuakia:BAAALgADCgEJAQAAAA==.Tuggmytotem:BAAALgAECggJDgAAAA==.',
Tw='Twi:BAAALgAECgcJCgAAAA==.',
Ty='Tygerfist:BAAALgAECgIJBAAAAA==.Tyrannar:BAAALgADCgEJAgAAAA==.Tytanion:BAAALgAECgEJAwAAAA==.Tython:BAAALgADCgcJBwAAAA==.',
Uc='Uch:BAAALgADCgQJBQAAAA==.',
Ul='Ultrarion:BAAALgADCgEJAQAAAA==.',
Un='Undercovrcow:BAAALgAECgEJAgAAAA==.Unity:BAAALgADCgYJBgAAAA==.Unmade:BAABLgAECn8iAAIeAAkJuxpNAwAEAgAeAAkJuxpNAwAEAgAAAA==.',
Ur='Urbanmech:BAAALgAECggJEQAAAA==.',
Va='Vanderbos:BAAALgADCgMJAwAAAA==.Vanderune:BAABLgAECn8hAAIQAAkJhRhmDABKAgAQAAkJhRhmDABKAgAAAA==.Varastanna:BAAALgADCgUJBQAAAA==.',
Ve='Vecky:BAAALgADCgcJBwAAAA==.',
Vi='Victus:BAAALgAECgEJAQAAAA==.Vidrus:BAAALgAECgYJCgAAAA==.Vilkas:BAACLgAFFH8NAAIeAAUJnhcKAgBSAQAeAAUJnhcKAgBSAQAuAAQKfx8AAh4ACAkKISAIAAIDAB4ACAkKISAIAAIDAAAA.Viserion:BAAALgAECgYJDwAAAA==.Visionhorn:BAAALgADCgIJAwAAAA==.',
Vo='Voidlit:BAAALgAECgEJAQAAAA==.Voodoowhodo:BAAALgAECgQJBAAAAA==.',
Vu='Vuradra:BAAALgAECgMJAwAAAA==.Vuudrood:BAAALgADCgYJDQAAAA==.',
Wa='Walruskíng:BAABLgAECn8UAAIeAAcJYhkwGAAhAgAeAAcJYhkwGAAhAgAAAA==.Wardaddy:BAAALgAECgEJAQAAAA==.Warmaku:BAAALgAECgYJEQAAAA==.',
We='Weezybaby:BAAALgAECgYJEQAAAA==.Wenjiesmom:BAAALgAECgEJAQAAAA==.',
Wh='Whitecosmos:BAAALgAECgMJBgAAAA==.Whohe:BAAALgAECgEJAQAAAA==.',
Wi='Wigwog:BAAALgAECgYJCQAAAA==.Windfury:BAACLgAFFH8MAAIWAAQJIyIwAACVAQAWAAQJIyIwAACVAQAuAAQKfyEAAhYACAl8JbABAEwDABYACAl8JbABAEwDAAAA.Winterfella:BAAALgADCgUJCwAAAA==.Wirantimer:BAAALgAECgYJDwAAAA==.Witfuk:BAAALgADCgUJBQAAAA==.',
Wo='Wogasaurus:BAAALgAECgIJAgAAAA==.',
Wu='Wuzo:BAAALgAECgMJAwAAAA==.',
Wy='Wykka:BAAALgAECggJCwAAAA==.Wyverynn:BAABLgAECn8UAAIPAAcJrRRwHgAqAQAPAAcJrRRwHgAqAQAAAA==.',
['Wí']='Wínter:BAAALgADCgMJAwAAAA==.',
Xa='Xany:BAAALgAECgUJBQAAAA==.',
Xc='Xcomunicated:BAAALgADCgUJBQAAAA==.',
Xe='Xenomortis:BAAALgAECgcJDQAAAA==.Xephanie:BAAALgADCgEJAgAAAA==.',
Xi='Xinlucia:BAAALgAECggJDQAAAA==.',
Xo='Xofu:BAAALgAECgEJAwAAAA==.',
Xr='Xrxyz:BAACLgAFFH8GAAIOAAMJ3g3UCQD8AAAOAAMJ3g3UCQD8AAAuAAQKfxwAAg4ACAnkG+IoAIECAA4ACAnkG+IoAIECAAAA.',
Xy='Xylus:BAAALgAECgIJAgAAAA==.',
Ya='Yabe:BAAALgAECgMJAwAAAA==.',
Ye='Yen:BAAALgADCgIJAgAAAA==.Yetibear:BAAALgAECgIJAgAAAA==.Yewna:BAAALgAECgYJBgAAAA==.',
Za='Zachdem:BAAALgADCggJCAAAAA==.Zachdrac:BAAALgADCgQJBAAAAA==.',
Ze='Zebrabutt:BAABLgAECn8UAAIWAAcJ8A70BABWAQAWAAcJ8A70BABWAQAAAA==.Zenstation:BAAALgADCgEJAQAAAA==.Zero:BAAALgAECgcJEgAAAA==.',
Zi='Ziccem:BAABLgAECn8gAAIbAAcJmB0EBQDFAQAbAAcJmB0EBQDFAQAAAA==.Ziggawâ:BAAALgADCgYJCQABLgAECggJHAASAD8UAA==.Zildjìan:BAAALgAECgEJAQAAAA==.Zionsmender:BAAALgADCgEJAQAAAA==.',
Zo='Zolja:BAAALgAECgMJAwAAAA==.Zoney:BAAALgADCgEJAQAAAA==.Zordlon:BAAALgAECgMJBgAAAA==.',
Zu='Zukem:BAAALgAECgUJBQAAAA==.',
Zy='Zynlord:BAAALgADCgEJAQAAAA==.Zyvea:BAAALgAECgMJAwAAAA==.',
['Çr']='Çrossblesser:BAAALgAECgMJCgAAAA==.',
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

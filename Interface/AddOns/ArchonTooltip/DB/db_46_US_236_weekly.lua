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

local lookup = {'Druid-Balance','Unknown-Unknown','Mage-Frost','Mage-Arcane','DeathKnight-Unholy','DeathKnight-Blood','Druid-Guardian','Paladin-Retribution','DemonHunter-Devourer','DemonHunter-Vengeance','Rogue-Assassination','Rogue-Subtlety','Warlock-Demonology','Druid-Restoration','Warrior-Fury','Monk-Brewmaster','Evoker-Preservation','Monk-Windwalker','DeathKnight-Frost','Priest-Discipline','Paladin-Holy','Rogue-Outlaw','Hunter-BeastMastery','Hunter-Marksmanship','Evoker-Augmentation','Evoker-Devastation','Shaman-Restoration','Druid-Feral','Priest-Holy','Warrior-Arms','Warrior-Protection','Warlock-Destruction','DemonHunter-Havoc','Shaman-Elemental','Shaman-Enhancement',}
local provider = {region='US',realm='Warsong',name='US',type='weekly',zone=46,date='2026-05-08',data={Ad='Adònis:BAAALgADCgEJAQAAAA==.',
Ae='Aesudan:BAAALgADCgEJAQAAAA==.',
Ah='Aharan:BAABLgAECn8aAAIBAAYJ4gkjLADnAAABAAYJ4gkjLADnAAAAAA==.',
Ai='Aiona:BAAALgADCgYJDAAAAA==.',
Al='Alandrov:BAAALgADCgEJAQAAAA==.Alexanzalone:BAAALgADCggJCAAAAA==.Allenduin:BAAALgAECgEJAQAAAA==.Alodso:BAAALgADCgEJAQAAAA==.',
An='Angryballz:BAAALgAECgYJBwABLgAECgYJCwACAAAAAA==.Angz:BAAALgAECgUJDQAAAA==.Anielor:BAAALgADCgMJAwAAAA==.Anuksuna:BAAALgAECgUJCQABLgAECgYJEwACAAAAAA==.',
Ar='Arcadia:BAAALgAECgYJDgAAAA==.Arcane:BAABLgAECn8eAAMDAAgJCCRbEABGAwADAAgJCCRbEABGAwAEAAUJQyQXBQDpAQAAAA==.',
As='Asta:BAAALgAECgQJBAAAAA==.',
At='Atulan:BAAALgADCgQJBAAAAA==.',
Au='Austin:BAAALgADCggJEAAAAA==.Automobeer:BAAALgAECgEJAwAAAA==.',
Aw='Awake:BAABLgAECn8WAAMFAAcJYRM+XgAoAQAGAAYJ2hJSHwBKAQAFAAcJvAg+XgAoAQAAAA==.',
Az='Azazzel:BAAALgADCgEJAQAAAA==.',
Ba='Bambietta:BAAALgADCgkJCQAAAA==.Barebelly:BAAALgAECggJEAAAAA==.',
Be='Bearforce:BAABLgAECn8eAAIHAAkJjxnZCAAbAgAHAAkJjxnZCAAbAgAAAA==.',
Bi='Biggbird:BAABLgAECn8WAAIBAAYJNhlbGQBuAQABAAYJNhlbGQBuAQAAAA==.',
Bl='Blutwin:BAABLgAECn8eAAIIAAgJXhBUNgCkAQAIAAgJXhBUNgCkAQAAAA==.Bluud:BAAALgADCgMJAwAAAA==.',
Bo='Bossdierr:BAACLgAFFH8JAAIJAAIJQiXzHwDXAAAJAAIJQiXzHwDXAAAuAAQKfyMAAwkACAk1HkkzACwCAAkABgl/IUkzACwCAAoACAlsEQAJAE0BAAAA.Bossdisan:BAACLgAFFH8HAAIDAAMJ6h40KgAMAQADAAMJ6h40KgAMAQAuAAQKfyEAAgMABgkXI1FXADMCAAMABgkXI1FXADMCAAAA.Bosswudi:BAABLgAFFH8HAAMLAAIJMRMsBgCpAAALAAIJsQ4sBgCpAAAMAAIJygiuFQCgAAAAAA==.',
Br='Brashe:BAAALgAECgUJEgAAAA==.Breakahorde:BAAALgAECgEJAQAAAA==.Breathe:BAAALgAECgQJBAAAAA==.Brickbeard:BAAALgADCgcJBwABLgAECgYJEAACAAAAAA==.Bruv:BAABLgAECn8jAAINAAYJhhUYUAA6AQANAAYJhhUYUAA6AQAAAA==.',
Ca='Calathis:BAAALgAECgEJAQAAAA==.Cazadòr:BAAALgAECgIJAgAAAA==.',
Ch='Chromiepip:BAAALgADCgMJAwAAAA==.',
Co='Corbann:BAAALgAECgYJCgAAAA==.',
Cr='Creamcheese:BAABLgAECn8aAAIOAAcJUB0wHADiAQAOAAcJUB0wHADiAQAAAA==.Creamy:BAABLgAECn8jAAIPAAgJxRicDQATAgAPAAgJxRicDQATAgAAAA==.Crossbreed:BAAALgAECgQJBQAAAA==.',
Cy='Cyr:BAAALgADCgUJBQAAAA==.Cytosine:BAAALgAECgYJCQAAAA==.',
Da='Daddyhaz:BAABLgAECn8sAAIJAAgJGSEpCwB5AgAJAAgJGSEpCwB5AgAAAA==.Daddywhyudie:BAAALgADCgEJAQAAAA==.Daelyte:BAAALgAECgYJDwAAAA==.Daghor:BAABLgAFFH8GAAIMAAIJLBqdGACvAAAMAAIJLBqdGACvAAAAAA==.',
De='Deltron:BAAALgAECgEJAQAAAA==.Desetre:BAAALgADCgIJAgAAAA==.',
Di='Dinks:BAABLgAECn8oAAIDAAgJvRdrMgDXAQADAAgJvRdrMgDXAQAAAA==.Ditzy:BAAALgAECgEJAQAAAA==.',
Do='Docc:BAABLgAECn8XAAIMAAkJGA+lFgBXAgAMAAkJGA+lFgBXAgAAAA==.',
Dr='Draan:BAAALgADCgUJBwAAAA==.Dragorr:BAAALgADCgcJBwAAAA==.Dreadpanda:BAAALgADCgMJAwABLgAFFAQJCAAQALIiAA==.Drekkarn:BAAALgADCgMJBAAAAA==.Drood:BAAALgAECgEJAQAAAA==.',
El='Elzath:BAAALgADCggJEAABLgAECgkJIwARAIkUAA==.',
En='Enix:BAAALgADCgYJBgABLgAFFAIJBQAOALwTAA==.',
Er='Erdrick:BAAALgAECgEJAgAAAA==.',
Es='Espeon:BAAALgAECgYJDQAAAA==.',
Eu='Eudisius:BAAALgADCgEJAQAAAA==.',
Ev='Evara:BAABLgAECn8UAAIDAAYJAwccoADTAAADAAYJAwccoADTAAAAAA==.',
Fa='Fangbot:BAAALgAECgEJAQAAAA==.',
Fe='Felcaas:BAAALgADCgQJBAAAAA==.Felini:BAABLgAECn8bAAIPAAcJvQdsKwAmAQAPAAcJvQdsKwAmAQAAAA==.Feronar:BAABLgAECn8fAAIPAAgJegiRIgBaAQAPAAgJegiRIgBaAQAAAA==.',
Fl='Fleepity:BAAALgAECgYJCQAAAA==.Floopity:BAAALgADCgYJBwAAAA==.Flowermom:BAAALgAECgEJAQAAAA==.',
Fu='Fusíon:BAEBLgAECn8yAAIJAAkJdiI2CQCSAgAJAAkJdiI2CQCSAgAAAA==.',
Gi='Gin:BAACLgAFFH8FAAISAAMJ0Qq5EQDbAAASAAMJ0Qq5EQDbAAAuAAQKfycAAhIACQn2Gi4IAEACABIACQn2Gi4IAEACAAAA.',
Gj='Gjana:BAAALgAECgQJBAABLgAECgQJDgACAAAAAA==.',
Gl='Glamdring:BAAALgADCgMJAwAAAA==.Glunty:BAAALgAECgUJCAAAAA==.',
Go='Goldpaw:BAAALgADCgEJAQAAAA==.Gorlash:BAAALgAECgYJBwAAAA==.',
Gr='Gridinn:BAAALgADCgIJAgAAAA==.Grimgeth:BAACLgAFFH8IAAIFAAMJcBRWSwD4AAAFAAMJcBRWSwD4AAAuAAQKfyYAAwUACAnQHMoxALIBAAUACAnQHMoxALIBABMAAgnlF/gTAEgAAAAA.Grimwrath:BAAALgAECgUJBwABLgAFFAMJCAAFAHAUAA==.',
Gu='Gugaman:BAAALgADCgcJDgAAAA==.Guishin:BAAALgAECgEJAQAAAA==.',
He='Healpls:BAAALgADCgUJBQAAAA==.Heidriel:BAAALgAECgMJAwAAAA==.Herumesu:BAAALgADCgcJCgABLgAFFAMJCgAFAEsgAA==.',
Ho='Holapes:BAAALgAECgUJCAABLgAECgMJBAACAAAAAA==.',
Hu='Huhbruh:BAAALgAECgIJAgABLgAECgYJIwANAIYVAA==.',
Hw='Hwasa:BAABLgAECn8iAAIQAAgJCR4eCABLAgAQAAgJCR4eCABLAgAAAA==.',
Il='Illigari:BAAALgAFFAEJAQAAAA==.',
In='Indy:BAAALgADCgUJCAAAAA==.Insanities:BAABLgAECn8mAAIUAAkJQB/LAgAUAwAUAAkJQB/LAgAUAwAAAA==.Inti:BAABLgAECn8WAAIVAAYJZhvFGQC8AQAVAAYJZhvFGQC8AQABLgAFFAIJBQAOALwTAA==.',
Ja='Jaidie:BAAALgAECgMJAwAAAA==.',
Je='Jeffreyx:BAAALgAECgYJCAAAAA==.',
Jo='Joak:BAAALgADCgUJBQAAAA==.Jota:BAAALgADCgcJCAAAAA==.',
Ka='Kahlán:BAAALgAECgYJEwAAAA==.Karlangas:BAAALgAECgMJBAAAAA==.',
Ki='Kifu:BAAALgADCgEJAQABLgAECgQJDgACAAAAAA==.Kikipants:BAAALgADCgEJAQAAAA==.Kitrix:BAAALgADCgUJBQAAAA==.',
Kr='Krue:BAAALgADCggJDQAAAA==.',
Ku='Kubimage:BAABLgAECn8aAAIDAAkJKhuzMgCoAgADAAkJKhuzMgCoAgAAAA==.',
La='Lane:BAAALgADCgEJAQAAAA==.Layona:BAAALgAECgYJCgAAAA==.',
Le='Lerroy:BAAALgADCgcJCQAAAA==.',
Li='Lildar:BAABLgAECn8eAAIFAAgJjxpBHwANAgAFAAgJjxpBHwANAgAAAA==.Linelli:BAAALgAECgcJCgABLgAFFAUJEQAWALUkAA==.Lirra:BAAALgAFFAIJAgABLgAFFAIJBQAOALwTAA==.',
Lo='Lorthiel:BAAALgADCgIJAgAAAA==.Lothus:BAABLgAECn8VAAMXAAkJDxswGAB4AgAXAAkJDxswGAB4AgAYAAEJdgRfkwAnAAABLgAFFAIJBQAOALwTAA==.',
Ls='Lsblkxd:BAAALgADCgYJBgAAAA==.',
Lu='Lumen:BAAALgADCgcJCAAAAA==.Lumverjvcked:BAAALgAECgYJDAABLgAECgYJIwANAIYVAA==.',
Lx='Lxrbread:BAACLgAFFH8IAAMZAAMJqQuxIgDeAAAZAAMJqQuxIgDeAAARAAEJ5QPSGAA8AAAuAAQKfyoABBkACAlDFD8WAJEBABkACAkdFD8WAJEBABEABQlBBdA3AK0AABoAAgmoCtEWADoAAAAA.',
['Lë']='Lëgitz:BAABLgAECn8dAAIbAAkJuh88AwAdAwAbAAkJuh88AwAdAwAAAA==.',
Ma='Maccazilla:BAAALgAECgYJCwAAAA==.Magdalena:BAACLgAFFH8JAAISAAQJhB+pAwCCAQASAAQJhB+pAwCCAQAuAAQKfyMAAhIACAkbJb8CAG0DABIACAkbJb8CAG0DAAAA.Magedand:BAAALgAECgMJAwAAAA==.Magnesson:BAAALgAFFAEJAgAAAA==.Manakaren:BAAALgADCggJDAAAAA==.Mazuro:BAACLgAFFH8PAAIMAAUJah3EBwBrAQAMAAUJah3EBwBrAQAuAAQKfycAAwwABwlfH3EKAPkBAAwABwlfH3EKAPkBAAsAAQlGGVgdAEAAAAAA.',
Me='Meatkleaver:BAABLgAECn8bAAMTAAkJ0BUhAwBnAgATAAkJ0BUhAwBnAgAFAAEJqAGRNgEiAAAAAA==.Meau:BAABLgAECn8iAAIcAAgJax/JAgBxAgAcAAgJax/JAgBxAgAAAA==.Mechadar:BAAALgAECgMJAwAAAA==.Mechanizedtv:BAACLgAFFH8FAAIHAAIJnBmtBwCgAAAHAAIJnBmtBwCgAAAuAAQKf78ABAcACQmyJg4AAI0DAAcACQmyJg4AAI0DABwABgl4HBAIALABAAEAAQlmAglkAB4AAAEuAAQKAgkCAAIAAAAA.',
Mi='Mitskí:BAAALgAECgQJBAAAAA==.',
Mo='Monkerooz:BAAALgAECgUJCAAAAA==.Moodeng:BAAALgADCgYJBwAAAA==.Morphîne:BAACLgAFFH8FAAIOAAIJvBOGMACGAAAOAAIJvBOGMACGAAAuAAQKfxcAAg4ABwkZHu0oABACAA4ABwkZHu0oABACAAAA.',
Mu='Mugwump:BAAALgADCgYJCAAAAA==.Murdøk:BAABLgAECn8VAAMFAAYJKBfsfADnAAAFAAYJKBfsfADnAAAGAAEJ6Q01RAA4AAAAAA==.',
My='Mythic:BAABLgAECn8eAAISAAgJMBptDADyAQASAAgJMBptDADyAQAAAA==.',
['Mû']='Mûrdok:BAAALgAECgUJDAABLgAECgYJFQAFACgXAA==.',
['Mü']='Mürdok:BAAALgAECgYJCAABLgAECgYJFQAFACgXAA==.',
Ne='Necromortas:BAAALgAECgcJBwAAAA==.Nefarius:BAAALgAECggJEwAAAA==.Neph:BAABLgAECn8aAAMdAAkJQw94HwDlAQAdAAkJQw94HwDlAQAUAAIJbgNbUABNAAAAAA==.',
Ni='Nihilism:BAAALgADCgYJBgAAAA==.Ninsu:BAAALgAECgYJCgAAAA==.Nishale:BAAALgAECgMJBQAAAA==.',
No='Noir:BAAALgADCgQJBAAAAA==.',
Nu='Nutdraggin:BAAALgADCgcJBwAAAA==.',
Ny='Nyki:BAAALgAECgYJBwAAAA==.',
Op='Opius:BAAALgAECgcJDQAAAA==.',
Or='Orcmagic:BAAALgADCgQJBAAAAA==.',
Os='Oshift:BAAALgAECgYJBgAAAA==.',
Pa='Pandinha:BAACLgAFFH8OAAIFAAMJjh4RRwAAAQAFAAMJjh4RRwAAAQAuAAQKfy4AAgUACQn3ICkMADkDAAUACQn3ICkMADkDAAAA.Pattêrn:BAAALgAECgYJBQAAAA==.',
Pd='Pdr:BAAALgADCgcJBwAAAA==.',
Pe='Pedri:BAABLgAFFH8FAAIFAAIJvyKbWQDRAAAFAAIJvyKbWQDRAAAAAA==.Pedrok:BAAALgAECgMJBAAAAA==.',
Ph='Phoenixashes:BAAALgADCgIJAgAAAA==.',
Po='Pokz:BAAALgADCgEJAQAAAA==.',
Pr='Priestiality:BAAALgAECgIJAwAAAA==.Prowl:BAAALgAECgEJAQABLgAFFAUJEgAeAF0ZAA==.Prscilla:BAAALgADCgcJBgAAAA==.',
Qu='Quixote:BAAALgADCgYJBgAAAA==.',
Ra='Radagast:BAAALgADCgcJDQABLgAECggJGQAJAJgQAA==.Radulf:BAAALgAECgQJBAAAAA==.Raph:BAACLgAFFH8KAAIFAAMJSyD6QQALAQAFAAMJSyD6QQALAQAuAAQKfygAAgUABwmJI+IeAA8CAAUABwmJI+IeAA8CAAAA.Raphy:BAAALgAECgcJEAABLgAFFAMJCgAFAEsgAA==.Ravyn:BAAALgADCgUJBQAAAA==.',
Re='Reckon:BAAALgAECgYJDAAAAA==.Redthedeer:BAAALgAECgcJCgAAAA==.Redzone:BAAALgAECgQJBgAAAA==.Refuliya:BAAALgADCgkJBwAAAA==.Remmahcm:BAABLgAECn8VAAIIAAgJUBYwPwApAgAIAAgJUBYwPwApAgAAAA==.Renewing:BAAALgADCgQJBAAAAA==.Renrir:BAAALgADCgcJCAAAAA==.',
Rh='Rhark:BAAALgAECgUJDAAAAA==.',
Ri='Rikku:BAAALgAFFAEJAQAAAA==.',
Ro='Rook:BAABLgAECn8ZAAIIAAgJuCLCCQC7AgAIAAgJuCLCCQC7AgAAAA==.',
Ru='Runnow:BAAALgADCgYJCwAAAA==.',
Sa='Sagas:BAAALgAECgEJAQAAAA==.Salina:BAAALgAECgEJAQABLgAECgMJBQACAAAAAA==.Sammysam:BAAALgADCgUJBwAAAA==.Sathor:BAAALgADCgkJDgAAAA==.',
Sc='Scotch:BAAALgADCgQJBAABLgAFFAMJBQASANEKAA==.',
Sh='Shelton:BAAALgADCgMJAwABLgADCggJDQACAAAAAA==.Shinjey:BAAALgAECgMJBwAAAA==.',
Si='Sil:BAABLgAECn8ZAAIfAAkJCwrzFwCXAQAfAAkJCwrzFwCXAQAAAA==.Silents:BAAALgAECgUJBQAAAA==.Siphon:BAAALgAECgYJCwAAAA==.Siphons:BAAALgAECgMJBAAAAA==.',
Sk='Ska:BAACLgAFFH8UAAINAAYJhxThDACOAQANAAYJhxThDACOAQAuAAQKfxsAAw0ACAm7H1kYAMICAA0ACAm7H1kYAMICACAAAQkAAIlwADUAAAAA.',
Sl='Slyzete:BAAALgAECgQJBwAAAA==.',
So='Softbutt:BAAALgAECggJDwAAAA==.Sophie:BAAALgADCgcJBwAAAA==.Soulseeker:BAABLgAECn8WAAMNAAYJWBOCewDQAAANAAUJyhKCewDQAAAgAAIJfBRjUAB9AAAAAA==.',
St='Stölen:BAAALgAECgEJAQAAAA==.',
Sy='Sylthas:BAAALgADCgMJAwAAAA==.Syrensong:BAAALgAECgQJBAAAAA==.',
Ta='Tankli:BAAALgAECgIJBgAAAA==.Tanriel:BAAALgAECgEJAQAAAA==.Tatl:BAAALgADCgkJCQAAAA==.',
Te='Tertletoes:BAABLgAECn8cAAQhAAkJECXvAAC+AwAhAAkJECXvAAC+AwAKAAEJ2x45JwBMAAAJAAEJ/h3R2gA5AAAAAA==.Terts:BAAALgAECgEJAQABLgAECgkJHAAhABAlAA==.Teto:BAAALgAECgYJDgAAAA==.',
Th='Thebartender:BAAALgAECgcJDAAAAA==.Thella:BAAALgAECgQJBgAAAA==.Thopowisiwi:BAAALgAECggJDgAAAA==.',
To='Tog:BAABLgAECn8bAAIOAAkJciLHAwBVAwAOAAkJciLHAwBVAwAAAA==.Togame:BAAALgAECgUJCAAAAA==.Tognahok:BAAALgADCgYJDgAAAA==.Togy:BAAALgADCgEJAQAAAA==.Tortoisetoes:BAAALgAECgIJAgABLgAECgkJHAAhABAlAA==.',
Tr='Tremboladin:BAABLgAECn8aAAIVAAcJHxozJgD2AQAVAAcJHxozJgD2AQABLgAFFAMJBQAZAFQHAA==.',
Ts='Tsnt:BAAALgAECgEJAQAAAA==.',
Tu='Turbosocks:BAAALgAECgIJBQAAAA==.Turok:BAAALgADCgMJAwAAAA==.Turtles:BAAALgADCgEJAQABLgAECgkJHAAhABAlAA==.Tuskydin:BAAALgADCgcJCQAAAA==.',
Ty='Tydrin:BAAALgAECgIJAwAAAA==.Tylandord:BAAALgADCgEJAQAAAA==.',
['Tý']='Týråél:BAAALgADCgYJCwAAAA==.',
Ur='Urra:BAABLgAECn8lAAIiAAgJTht2EgDHAQAiAAgJTht2EgDHAQAAAA==.',
Va='Valoo:BAAALgAECgQJCgAAAA==.Valunar:BAAALgADCgUJBQAAAA==.',
Ve='Veyron:BAAALgADCgMJAwAAAA==.',
Vi='Vicar:BAAALgADCggJCQAAAA==.',
Vo='Voidstrider:BAAALgAECggJDgAAAA==.',
We='Weezard:BAAALgAECgQJDgAAAA==.',
Wh='Wheein:BAABLgAECn8iAAIUAAgJjyIfBADbAgAUAAgJjyIfBADbAgAAAA==.',
Wi='Wingolingo:BAAALgAECgIJAgAAAA==.',
Ya='Yaamoonn:BAAALgADCgUJBQAAAA==.',
Ye='Yenn:BAABLgAECn8bAAMNAAkJXhtHFgDPAgANAAkJXhtHFgDPAgAgAAIJwAEmWgBgAAAAAA==.',
Za='Zardnax:BAAALgADCgIJAgAAAA==.',
Ze='Zenin:BAAALgADCggJFQAAAA==.Zenu:BAABLgAECn8eAAMiAAgJ7RsUEgCSAgAiAAgJ7RsUEgCSAgAjAAEJ1RVOHQA/AAAAAA==.',
Zu='Zugg:BAAALgADCgEJAQAAAA==.',
['Çh']='Çhakra:BAAALgAECgUJBwAAAA==.',
['Ðð']='Ððn:BAAALgADCgMJAQAAAA==.',
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

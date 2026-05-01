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

local lookup = {'Druid-Balance','Unknown-Unknown','Mage-Frost','Mage-Arcane','Druid-Guardian','Paladin-Retribution','DemonHunter-Devourer','DemonHunter-Vengeance','Warlock-Demonology','Druid-Restoration','Warrior-Fury','Rogue-Subtlety','Monk-Brewmaster','Evoker-Devastation','Monk-Windwalker','DeathKnight-Unholy','DeathKnight-Frost','Priest-Discipline','Paladin-Holy','Rogue-Outlaw','Evoker-Augmentation','Evoker-Preservation','Shaman-Restoration','Rogue-Assassination','Druid-Feral','Priest-Holy','Warrior-Arms','Warrior-Protection','Warlock-Destruction','DemonHunter-Havoc','Shaman-Elemental','Shaman-Enhancement',}
local provider = {region='US',realm='Warsong',name='US',type='weekly',zone=46,date='2026-05-01',data={Ad='Adònis:BAAALgADCgEJAQAAAA==.',
Ae='Aesudan:BAAALgADCgEJAQAAAA==.',
Ah='Aharan:BAABLgAECn8UAAIBAAYJjglcIgDsAAABAAYJjglcIgDsAAAAAA==.',
Ai='Aiona:BAAALgADCgYJDAAAAA==.',
Al='Alandrov:BAAALgADCgEJAQAAAA==.Alexanzalone:BAAALgADCggJCAAAAA==.Allenduin:BAAALgAECgEJAQAAAA==.Alodso:BAAALgADCgEJAQAAAA==.',
An='Angryballz:BAAALgAECgYJBgABLgAECgYJCwACAAAAAA==.Angz:BAAALgAECgUJDQAAAA==.Anielor:BAAALgADCgMJAwAAAA==.Anuksuna:BAAALgAECgMJAwABLgAECgYJEQACAAAAAA==.',
Ar='Arcadia:BAAALgAECgQJCAAAAA==.Arcane:BAABLgAECn8eAAMDAAgJCCRcEABGAwADAAgJCCRcEABGAwAEAAUJQyQYBQDpAQAAAA==.',
As='Asta:BAAALgAECgQJBAAAAA==.',
At='Atulan:BAAALgADCgQJBAAAAA==.',
Au='Austin:BAAALgADCggJEAAAAA==.Automobeer:BAAALgAECgEJAgAAAA==.',
Aw='Awake:BAAALgAECgYJEwAAAA==.',
Az='Azazzel:BAAALgADCgEJAQAAAA==.',
Ba='Bambietta:BAAALgADCgkJCQAAAA==.Barebelly:BAAALgAECggJEAAAAA==.',
Be='Bearforce:BAABLgAECn8bAAIFAAgJYxrYCAAbAgAFAAgJYxrYCAAbAgAAAA==.',
Bi='Biggbird:BAABLgAECn8WAAIBAAYJNhnAEgB0AQABAAYJNhnAEgB0AQAAAA==.',
Bl='Blutwin:BAABLgAECn8XAAIGAAgJ0QxCPwBMAQAGAAgJ0QxCPwBMAQAAAA==.Bluud:BAAALgADCgMJAwAAAA==.',
Bo='Bossdierr:BAACLgAFFH8IAAIHAAIJECUvJwDAAAAHAAIJECUvJwDAAAAuAAQKfxsAAwcACAloHE8zACwCAAcABgkTIU8zACwCAAgACAl5CL0RADUBAAAA.Bossdisan:BAACLgAFFH8FAAIDAAMJsxIwKgAMAQADAAMJsxIwKgAMAQAuAAQKfxkAAgMABgn9IlhXADMCAAMABgn9IlhXADMCAAAA.Bosswudi:BAAALgAFFAIJBAAAAA==.',
Br='Brashe:BAAALgAECgUJDAAAAA==.Breathe:BAAALgAECgQJBAAAAA==.Bruv:BAABLgAECn8dAAIJAAYJhRWxQAAvAQAJAAYJhRWxQAAvAQAAAA==.',
Ca='Calathis:BAAALgADCgYJCwAAAA==.Cazadòr:BAAALgAECgIJAgAAAA==.',
Ch='Chromiepip:BAAALgADCgMJAwAAAA==.',
Co='Corbann:BAAALgAECgYJCgAAAA==.',
Cr='Creamcheese:BAABLgAECn8WAAIKAAcJ+xi+LAD8AQAKAAcJ+xi+LAD8AQAAAA==.Creamy:BAABLgAECn8bAAILAAYJ8Bm2GgBaAQALAAYJ8Bm2GgBaAQAAAA==.Crossbreed:BAAALgAECgIJAgAAAA==.',
Cy='Cyr:BAAALgADCgUJBQAAAA==.Cytosine:BAAALgAECgYJCQAAAA==.',
Da='Daddyhaz:BAABLgAECn8kAAIHAAgJRx7GEwDMAQAHAAgJRx7GEwDMAQAAAA==.Daddywhyudie:BAAALgADCgEJAQAAAA==.Daelyte:BAAALgAECgYJDwAAAA==.Daghor:BAAALgAFFAIJAgAAAA==.',
De='Deltron:BAAALgAECgEJAQAAAA==.Desetre:BAAALgADCgIJAgAAAA==.',
Di='Dinks:BAABLgAECn8dAAIDAAgJGhdpiADBAQADAAgJGhdpiADBAQAAAA==.Ditzy:BAAALgAECgEJAQAAAA==.',
Do='Docc:BAABLgAECn8XAAIMAAkJGA+pFgBXAgAMAAkJGA+pFgBXAgAAAA==.',
Dr='Draan:BAAALgADCgUJBwAAAA==.Dragorr:BAAALgADCgcJBwAAAA==.Dreadpanda:BAAALgADCgMJAwABLgAFFAMJBQANAHwlAA==.Drekkarn:BAAALgADCgMJBAAAAA==.',
El='Elzath:BAAALgADCggJEAABLgAECggJHQAOANwOAA==.',
En='Enix:BAAALgADCgYJBgABLgAECgcJFQAKABgeAA==.',
Er='Erdrick:BAAALgAECgEJAQAAAA==.',
Es='Espeon:BAAALgAECgYJDQAAAA==.',
Eu='Eudisius:BAAALgADCgEJAQAAAA==.',
Ev='Evara:BAABLgAECn8UAAIDAAYJAgfEfwDUAAADAAYJAgfEfwDUAAAAAA==.',
Fa='Fangbot:BAAALgAECgEJAQAAAA==.',
Fe='Felcaas:BAAALgADCgQJBAAAAA==.Felini:BAABLgAECn8bAAILAAcJvgdXIAAzAQALAAcJvgdXIAAzAQAAAA==.Feronar:BAABLgAECn8XAAILAAcJuAf1IAAuAQALAAcJuAf1IAAuAQAAAA==.',
Fl='Fleepity:BAAALgAECgEJAgAAAA==.Floopity:BAAALgADCgYJBwAAAA==.Flowermom:BAAALgAECgEJAQAAAA==.',
Fu='Fusíon:BAEBLgAECn8uAAIHAAgJ1iI3DgANAwAHAAgJ1iI3DgANAwAAAA==.',
['Fú']='Fúsioñ:BAEALgAECgEJAQABLgAECgkJLgAHANYiAA==.',
Gi='Gin:BAABLgAECn8lAAIPAAgJlxzgBwAFAgAPAAgJlxzgBwAFAgAAAA==.',
Gj='Gjana:BAAALgAECgQJBAABLgAECgQJDQACAAAAAA==.',
Gl='Glamdring:BAAALgADCgMJAwAAAA==.Glunty:BAAALgAECgUJCAAAAA==.',
Go='Goldpaw:BAAALgADCgEJAQAAAA==.Gorlash:BAAALgAECgUJBgAAAA==.',
Gr='Gridinn:BAAALgADCgIJAgAAAA==.Grimgeth:BAABLgAECn8fAAMQAAgJ4BfYRQAjAgAQAAgJ4BfYRQAjAgARAAEJAAC1FgA2AAAAAA==.Grimwrath:BAAALgAECgUJBwABLgAECggJHwAQAOAXAA==.',
Gu='Gugaman:BAAALgADCgcJDgAAAA==.Guishin:BAAALgAECgEJAQAAAA==.',
He='Healpls:BAAALgADCgUJBQAAAA==.Heidriel:BAAALgAECgMJAwAAAA==.Herumesu:BAAALgADCgcJCgABLgAFFAMJBwAQAI4dAA==.',
Ho='Holapes:BAAALgAECgQJBQABLgAECgMJBAACAAAAAA==.',
Hu='Huhbruh:BAAALgADCgUJBQABLgAECgYJHQAJAIUVAA==.',
Hw='Hwasa:BAABLgAECn8iAAINAAgJCB5OBQBWAgANAAgJCB5OBQBWAgAAAA==.',
Il='Illigari:BAAALgAFFAEJAQAAAA==.',
In='Indy:BAAALgADCgUJCAAAAA==.Insanities:BAABLgAECn8fAAISAAkJ8RyjBAB+AgASAAkJ8RyjBAB+AgAAAA==.Inti:BAABLgAECn8UAAITAAYJtBivGwBvAQATAAYJtBivGwBvAQABLgAECgcJFQAKABgeAA==.',
Ja='Jaidie:BAAALgADCgkJFQAAAA==.',
Je='Jeffreyx:BAAALgAECgYJCAAAAA==.',
Jo='Joak:BAAALgADCgUJBQAAAA==.Jota:BAAALgADCgcJCAAAAA==.',
Ka='Kahlán:BAAALgAECgYJEQAAAA==.Kaidou:BAAALgADCgQJBAAAAA==.Karlangas:BAAALgAECgMJBAAAAA==.',
Ki='Kifu:BAAALgADCgEJAQABLgAECgQJDQACAAAAAA==.Kikipants:BAAALgADCgEJAQAAAA==.Kitrix:BAAALgADCgUJBQAAAA==.',
Kr='Krue:BAAALgADCggJDQAAAA==.',
Ku='Kubimage:BAABLgAECn8aAAIDAAkJKhu1MgCoAgADAAkJKhu1MgCoAgAAAA==.',
La='Lane:BAAALgADCgEJAQAAAA==.Layona:BAAALgAECgYJCgAAAA==.',
Le='Lerroy:BAAALgADCgcJCQAAAA==.',
Li='Lildar:BAABLgAECn8cAAIQAAcJ5huoHADbAQAQAAcJ5huoHADbAQAAAA==.Linelli:BAAALgAECgYJCQABLgAFFAUJDAAUAMMkAA==.Lirra:BAAALgAECgYJBgABLgAECgcJFQAKABgeAA==.',
Lo='Lorthiel:BAAALgADCgIJAgAAAA==.Lothus:BAAALgAFFAIJAgABLgAECgcJFQAKABgeAA==.',
Ls='Lsblkxd:BAAALgADCgYJBgAAAA==.',
Lx='Lxrbread:BAACLgAFFH8FAAMVAAIJPgKPHQCCAAAVAAIJPgKPHQCCAAAWAAEJ5QPOGAA8AAAuAAQKfyIABBUACAmlEv0VAE8BABUACAmlEv0VAE8BABYABQlBBc03AK0AAA4AAQlIAidFACIAAAAA.',
['Lë']='Lëgitz:BAABLgAECn8cAAIXAAgJviAeAwDjAgAXAAgJviAeAwDjAgAAAA==.',
Ma='Maccazilla:BAAALgAECgYJCwAAAA==.Magdalena:BAACLgAFFH8FAAIPAAMJoBzVCAAMAQAPAAMJoBzVCAAMAQAuAAQKfyIAAg8ACAkbJcACAG0DAA8ACAkbJcACAG0DAAAA.Magedand:BAAALgAECgMJAwAAAA==.Magnesson:BAAALgAFFAEJAgAAAA==.Manakaren:BAAALgADCggJDAAAAA==.Mazuro:BAACLgAFFH8KAAIMAAQJWxrHBQBpAQAMAAQJWxrHBQBpAQAuAAQKfycAAwwABwlgH4EGAA4CAAwABwlgH4EGAA4CABgAAQlGGVgdAEAAAAAA.',
Me='Meatkleaver:BAABLgAECn8bAAMRAAkJ0BUhAwBnAgARAAkJ0BUhAwBnAgAQAAEJqAGHNgEiAAAAAA==.Meau:BAABLgAECn8iAAIZAAgJaR/AAQB1AgAZAAgJaR/AAQB1AgAAAA==.Mechadar:BAAALgAECgMJAwAAAA==.Mechanizedtv:BAABLgAECn+yAAQFAAkJrCYJAAAZAwAFAAkJrCYJAAAZAwAZAAYJbhzTBQCzAQABAAEJaAK1TwAeAAABLgAECgIJAgACAAAAAA==.',
Mo='Monkerooz:BAAALgAECgIJBQAAAA==.Moodeng:BAAALgADCgYJBwAAAA==.Morphîne:BAABLgAECn8VAAIKAAcJGB7zKAAQAgAKAAcJGB7zKAAQAgAAAA==.',
Mu='Mugwump:BAAALgADCgIJAgAAAA==.Murdøk:BAAALgAECgYJDwAAAA==.',
My='Mythic:BAABLgAECn8dAAIPAAgJMBpmCAD5AQAPAAgJMBpmCAD5AQAAAA==.',
['Mû']='Mûrdok:BAAALgAECgQJCgABLgAECgYJDwACAAAAAA==.',
['Mü']='Mürdok:BAAALgAECgYJCAABLgAECgYJDwACAAAAAA==.',
Na='Narkis:BAAALgAECgEJAQAAAA==.',
Ne='Necromortas:BAAALgAECgcJBwAAAA==.Nefarius:BAAALgAECggJEgAAAA==.Neph:BAABLgAECn8aAAMaAAkJQw92HwDlAQAaAAkJQw92HwDlAQASAAIJbgNcUABNAAAAAA==.',
Ni='Nihilism:BAAALgADCgYJBgAAAA==.Ninsu:BAAALgAECgYJCgAAAA==.Nishale:BAAALgAECgMJBQAAAA==.',
No='Noir:BAAALgADCgQJBAAAAA==.',
Nu='Nutdraggin:BAAALgADCgcJBwAAAA==.',
Ny='Nyki:BAAALgAECgYJBwAAAA==.',
Op='Opius:BAAALgAECgYJCQAAAA==.',
Or='Orcmagic:BAAALgADCgQJBAAAAA==.',
Os='Oshift:BAAALgAECgYJBgAAAA==.',
Pa='Pandinha:BAACLgAFFH8KAAIQAAMJQhoYNgDzAAAQAAMJQhoYNgDzAAAuAAQKfy0AAhAACQn3IC0MADkDABAACQn3IC0MADkDAAAA.Pattêrn:BAAALgADCgUJBQAAAA==.',
Pd='Pdr:BAAALgADCgcJBwAAAA==.',
Pe='Pedri:BAAALgAFFAIJAgAAAA==.Pedrok:BAAALgAECgMJBAAAAA==.',
Ph='Phoenixashes:BAAALgADCgIJAgAAAA==.',
Po='Pokz:BAAALgADCgEJAQAAAA==.',
Pr='Priestiality:BAAALgAECgEJAQAAAA==.Prowl:BAAALgAECgEJAQABLgAFFAUJEAAbAK8WAA==.Prscilla:BAAALgADCgcJBgAAAA==.',
Ra='Radagast:BAAALgADCgcJDQABLgAECggJEwAHAOgMAA==.Radulf:BAAALgAECgQJBAAAAA==.Raph:BAACLgAFFH8HAAIQAAMJjh3XKgASAQAQAAMJjh3XKgASAQAuAAQKfygAAhAABwl7IwgTACECABAABwl7IwgTACECAAAA.Raphy:BAAALgAECgcJCgABLgAFFAMJBwAQAI4dAA==.Ravyn:BAAALgADCgUJBQAAAA==.',
Re='Reckon:BAAALgAECgYJDAAAAA==.Redthedeer:BAAALgAECgYJCQAAAA==.Redzone:BAAALgAECgQJBgAAAA==.Refuliya:BAAALgADCgkJBwAAAA==.Remmahcm:BAABLgAECn8VAAIGAAgJUBYwPwApAgAGAAgJUBYwPwApAgAAAA==.Renewing:BAAALgADCgQJBAAAAA==.Renrir:BAAALgADCgcJCAAAAA==.',
Rh='Rhark:BAAALgAECgUJDAAAAA==.',
Ri='Rikku:BAAALgADCgQJBAAAAA==.',
Ro='Rook:BAAALgAFFAIJAwAAAA==.',
Ru='Runnow:BAAALgADCgYJCwAAAA==.',
Sa='Sagas:BAAALgAECgEJAQAAAA==.Salina:BAAALgAECgEJAQABLgAECgMJBQACAAAAAA==.Sammysam:BAAALgADCgUJBwAAAA==.Sathor:BAAALgADCgkJDgAAAA==.',
Sc='Scotch:BAAALgADCgQJBAABLgAECggJJQAPAJccAA==.',
Sh='Shelton:BAAALgADCgMJAwABLgADCggJDQACAAAAAA==.Shinjey:BAAALgAECgMJBwAAAA==.',
Si='Sil:BAABLgAECn8ZAAIcAAkJCwr1FwCXAQAcAAkJCwr1FwCXAQAAAA==.Silents:BAAALgAECgUJBQAAAA==.Siphon:BAAALgAECgYJCwAAAA==.Siphons:BAAALgAECgMJAwAAAA==.',
Sk='Ska:BAACLgAFFH8SAAIJAAUJwRZbFABMAQAJAAUJwRZbFABMAQAuAAQKfxsAAwkACAm7H10YAMICAAkACAm7H10YAMICAB0AAQkAAIlwADUAAAAA.',
Sl='Slyzete:BAAALgAECgMJAwAAAA==.',
So='Softbutt:BAAALgAECggJDwAAAA==.Sophie:BAAALgADCgcJBwAAAA==.Soulseeker:BAAALgAECgYJEwAAAA==.',
St='Stölen:BAAALgAECgEJAQAAAA==.',
Sy='Sylthas:BAAALgADCgMJAwAAAA==.Syrensong:BAAALgAECgQJBAAAAA==.',
Ta='Tankli:BAAALgAECgEJBAAAAA==.Tanriel:BAAALgAECgEJAQAAAA==.Tatl:BAAALgADCgkJCQAAAA==.',
Te='Tertletoes:BAABLgAECn8cAAQeAAkJECXvAAC+AwAeAAkJECXvAAC+AwAIAAEJ2x49JwBMAAAHAAEJ/h3I2gA5AAAAAA==.Terts:BAAALgAECgEJAQABLgAECgkJHAAeABAlAA==.Teto:BAAALgAECgYJDgAAAA==.',
Th='Thebartender:BAAALgAECgcJDAAAAA==.Thella:BAAALgAECgQJBgAAAA==.Thopowisiwi:BAAALgAECggJDQAAAA==.',
To='Tog:BAABLgAECn8bAAIKAAkJciLIAwBVAwAKAAkJciLIAwBVAwAAAA==.Togame:BAAALgAECgQJBgAAAA==.Tognahok:BAAALgADCgYJDgAAAA==.Togy:BAAALgADCgEJAQAAAA==.',
Tr='Tremboladin:BAABLgAECn8aAAITAAcJHxozJgD2AQATAAcJHxozJgD2AQABLgAFFAIJBAACAAAAAA==.',
Tu='Turbosocks:BAAALgAECgIJBAAAAA==.Turok:BAAALgADCgMJAwAAAA==.Turtles:BAAALgADCgEJAQABLgAECgkJHAAeABAlAA==.Tuskydin:BAAALgADCgcJCQAAAA==.',
Ty='Tydrin:BAAALgAECgIJAgAAAA==.Tylandord:BAAALgADCgEJAQAAAA==.',
['Tý']='Týråél:BAAALgADCgYJCwAAAA==.',
Ur='Urra:BAABLgAECn8iAAIfAAgJkhqPEQCUAQAfAAgJkhqPEQCUAQAAAA==.',
Va='Valoo:BAAALgAECgQJCgAAAA==.Valunar:BAAALgADCgUJBQAAAA==.',
Ve='Veyron:BAAALgADCgMJAwAAAA==.',
Vi='Vicar:BAAALgADCgEJAQAAAA==.',
Vo='Voidstrider:BAAALgAECgcJDAAAAA==.',
We='Weezard:BAAALgAECgQJDQAAAA==.',
Wh='Wheein:BAABLgAECn8iAAISAAgJjyJrAgDlAgASAAgJjyJrAgDlAgAAAA==.',
Wi='Wingolingo:BAAALgAECgIJAgAAAA==.',
Ya='Yaamoonn:BAAALgADCgUJBQAAAA==.',
Ye='Yenn:BAABLgAECn8bAAMJAAkJXhtJFgDPAgAJAAkJXhtJFgDPAgAdAAIJwAEpWgBgAAAAAA==.',
Ze='Zenin:BAAALgADCggJFQAAAA==.Zenu:BAABLgAECn8dAAMfAAgJ7BsUEgCSAgAfAAgJ7BsUEgCSAgAgAAEJzRXyFgBKAAAAAA==.',
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

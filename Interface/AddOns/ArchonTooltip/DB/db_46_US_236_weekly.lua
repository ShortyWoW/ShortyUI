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

local lookup = {'Unknown-Unknown','Mage-Frost','Mage-Arcane','Druid-Guardian','Paladin-Retribution','DemonHunter-Devourer','DemonHunter-Vengeance','Warlock-Demonology','Druid-Restoration','Warrior-Fury','Rogue-Subtlety','Evoker-Devastation','Monk-Windwalker','DeathKnight-Unholy','DeathKnight-Frost','Monk-Brewmaster','Priest-Discipline','Rogue-Outlaw','Evoker-Augmentation','Evoker-Preservation','Shaman-Restoration','Rogue-Assassination','Druid-Feral','Druid-Balance','Priest-Holy','Warrior-Arms','Warrior-Protection','Warlock-Destruction','DemonHunter-Havoc','Paladin-Holy','Shaman-Elemental','Shaman-Enhancement',}
local provider = {region='US',realm='Warsong',name='US',type='weekly',zone=46,date='2026-04-24',data={Ad='Adònis:BAAALgADCgEJAQAAAA==.',
Ae='Aesudan:BAAALgADCgEJAQAAAA==.',
Ah='Aharan:BAAALgAECgUJDQAAAA==.',
Ai='Aiona:BAAALgADCgYJDAAAAA==.',
Al='Alandrov:BAAALgADCgEJAQAAAA==.Alexanzalone:BAAALgADCggJCAAAAA==.Allenduin:BAAALgAECgEJAQAAAA==.Alodso:BAAALgADCgEJAQAAAA==.',
An='Angryballz:BAAALgAECgYJBgABLgAECgYJCwABAAAAAA==.Angz:BAAALgAECgUJDQAAAA==.Anielor:BAAALgADCgMJAwAAAA==.Anuksuna:BAAALgAECgMJAwABLgAECgYJEQABAAAAAA==.',
Ar='Arcadia:BAAALgAECgMJBAAAAA==.Arcane:BAABLgAECn8eAAMCAAgJCCRUEABGAwACAAgJCCRUEABGAwADAAUJQyQXBQDpAQAAAA==.',
As='Asta:BAAALgAECgMJAwAAAA==.',
At='Atulan:BAAALgADCgQJBAAAAA==.',
Au='Austin:BAAALgADCggJEAAAAA==.',
Aw='Awake:BAAALgAECgYJCwAAAA==.',
Az='Azazzel:BAAALgADCgEJAQAAAA==.',
Ba='Bambietta:BAAALgADCgkJCQAAAA==.Barebelly:BAAALgAECggJEAAAAA==.',
Be='Bearforce:BAABLgAECn8WAAIEAAgJ+BfVCAAbAgAEAAgJ+BfVCAAbAgAAAA==.',
Bi='Biggbird:BAAALgAECgQJBwAAAA==.',
Bl='Blutwin:BAABLgAECn8UAAIFAAYJRQvNLgDhAAAFAAYJRQvNLgDhAAAAAA==.',
Bo='Bossdierr:BAACLgAFFH8GAAIGAAIJ/SPkHwDXAAAGAAIJ/SPkHwDXAAAuAAQKfxUAAwYACAnwG04zACwCAAYABglrIE4zACwCAAcABwkCCLsRADUBAAAA.Bossdisan:BAACLgAFFH8FAAICAAMJsxIxKgAMAQACAAMJsxIxKgAMAQAuAAQKfxcAAgIABgn9ImRXADMCAAIABgn9ImRXADMCAAAA.Bosswudi:BAAALgAFFAIJAgAAAA==.',
Br='Brashe:BAAALgAECgUJCAAAAA==.Breathe:BAAALgAECgQJBAAAAA==.Bruv:BAABLgAECn8XAAIIAAYJHRUrbwCCAQAIAAYJHRUrbwCCAQAAAA==.',
Ca='Calathis:BAAALgADCgYJCwAAAA==.Cazadòr:BAAALgAECgIJAgAAAA==.',
Ch='Chromiepip:BAAALgADCgMJAwAAAA==.',
Co='Corbann:BAAALgAECgYJCgAAAA==.',
Cr='Creamcheese:BAABLgAECn8UAAIJAAcJ+xi8LAD8AQAJAAcJ+xi8LAD8AQAAAA==.Creamy:BAABLgAECn8bAAIKAAYJ8BkJDABfAQAKAAYJ8BkJDABfAQAAAA==.Crossbreed:BAAALgAECgIJAgAAAA==.',
Cy='Cyr:BAAALgADCgUJBQAAAA==.Cytosine:BAAALgAECgYJCQAAAA==.',
Da='Daddyhaz:BAABLgAECn8eAAIGAAgJVhtSJQByAgAGAAgJVhtSJQByAgAAAA==.Daddywhyudie:BAAALgADCgEJAQAAAA==.Daelyte:BAAALgAECgYJDwAAAA==.Daghor:BAAALgAECgkJAwAAAA==.',
De='Deltron:BAAALgAECgEJAQAAAA==.Desetre:BAAALgADCgIJAgAAAA==.',
Di='Dinks:BAABLgAECn8ZAAICAAgJmRZ4iADBAQACAAgJmRZ4iADBAQAAAA==.Ditzy:BAAALgAECgEJAQAAAA==.',
Do='Docc:BAABLgAECn8XAAILAAkJGA+sFgBXAgALAAkJGA+sFgBXAgAAAA==.',
Dr='Draan:BAAALgADCgUJBwAAAA==.Drekkarn:BAAALgADCgMJBAAAAA==.',
El='Elzath:BAAALgADCggJEAABLgAECggJGAAMANwOAA==.',
En='Enix:BAAALgADCgYJBgABLgAFFAIJAgABAAAAAA==.',
Er='Erdrick:BAAALgADCgIJAgAAAA==.',
Es='Espeon:BAAALgAECgYJDQAAAA==.',
Eu='Eudisius:BAAALgADCgEJAQAAAA==.',
Ev='Evara:BAAALgAECgYJDgAAAA==.',
Fa='Fangbot:BAAALgADCgEJAQAAAA==.',
Fe='Felcaas:BAAALgADCgQJBAAAAA==.Felini:BAABLgAECn8UAAIKAAYJRwWoZwAVAQAKAAYJRwWoZwAVAQAAAA==.Feronar:BAABLgAECn8VAAIKAAYJUAifEgANAQAKAAYJUAifEgANAQAAAA==.',
Fl='Fleepity:BAAALgAECgEJAQAAAA==.Floopity:BAAALgADCgYJBwAAAA==.Flowermom:BAAALgAECgEJAQAAAA==.',
Fu='Fusíon:BAEBLgAECn8sAAIGAAgJnSEyDgANAwAGAAgJnSEyDgANAwAAAA==.',
Gi='Gin:BAABLgAECn8eAAINAAgJGhmKBQCYAQANAAgJGhmKBQCYAQAAAA==.',
Gj='Gjana:BAAALgAECgQJBAABLgAECgQJDQABAAAAAA==.',
Gl='Glamdring:BAAALgADCgMJAwAAAA==.Glunty:BAAALgAECgUJCAAAAA==.',
Go='Goldpaw:BAAALgADCgEJAQAAAA==.Gorlash:BAAALgAECgUJBgAAAA==.',
Gr='Gridinn:BAAALgADCgIJAgAAAA==.Grimgeth:BAABLgAECn8bAAMOAAgJOhbYRQAjAgAOAAgJOhbYRQAjAgAPAAEJAACwFgA2AAAAAA==.Grimwrath:BAAALgAECgUJBQABLgAECggJGwAOADoWAA==.',
Gu='Gugaman:BAAALgADCgcJDgAAAA==.Guishin:BAAALgAECgEJAQAAAA==.',
He='Heidriel:BAAALgAECgMJAwAAAA==.Herumesu:BAAALgADCgcJCgABLgAECgcJIwAOAFUjAA==.',
Hu='Huhbruh:BAAALgADCgUJBQABLgAECgYJFwAIAB0VAA==.',
Hw='Hwasa:BAABLgAECn8aAAIQAAgJ9RsJAwASAgAQAAgJ9RsJAwASAgAAAA==.',
Il='Illigari:BAAALgAECgUJCQAAAA==.',
In='Indy:BAAALgADCgUJCAAAAA==.Insanities:BAABLgAECn8dAAIRAAkJ0RsgBwDSAgARAAkJ0RsgBwDSAgAAAA==.Inti:BAAALgAECgYJEQABLgAFFAIJAgABAAAAAA==.',
Ja='Jaidie:BAAALgADCgkJEgAAAA==.',
Je='Jeffreyx:BAAALgAECgYJBgAAAA==.',
Jo='Joak:BAAALgADCgUJBQAAAA==.Jota:BAAALgADCgcJCAAAAA==.',
Ka='Kahlán:BAAALgAECgYJEQAAAA==.Kaidou:BAAALgADCgQJBAAAAA==.Karlangas:BAAALgAECgMJBAAAAA==.',
Ki='Kifu:BAAALgADCgEJAQABLgAECgQJDQABAAAAAA==.Kikipants:BAAALgADCgEJAQAAAA==.Kitrix:BAAALgADCgUJBQAAAA==.',
Kr='Krue:BAAALgADCggJDQAAAA==.',
Ku='Kubimage:BAABLgAECn8aAAICAAkJKhu2MgCoAgACAAkJKhu2MgCoAgAAAA==.',
La='Lane:BAAALgADCgEJAQAAAA==.Layona:BAAALgAECgYJCgAAAA==.',
Le='Lerroy:BAAALgADCgcJCQAAAA==.',
Li='Lildar:BAABLgAECn8VAAIOAAYJ1hg+HwAlAQAOAAYJ1hg+HwAlAQAAAA==.Linelli:BAAALgAECgYJCAABLgAFFAQJBwASAKohAA==.',
Lo='Lorthiel:BAAALgADCgIJAgAAAA==.Lothus:BAAALgAFFAEJAQABLgAFFAIJAgABAAAAAA==.',
Ls='Lsblkxd:BAAALgADCgYJBgAAAA==.',
Lx='Lxrbread:BAABLgAECn8bAAQTAAgJoBDAHQDXAQATAAgJoBDAHQDXAQAUAAQJbgbPNwCtAAAMAAEJSAIeRQAiAAAAAA==.',
['Lë']='Lëgitz:BAABLgAECn8aAAIVAAgJ9x/qAADZAgAVAAgJ9x/qAADZAgAAAA==.',
Ma='Maccazilla:BAAALgAECgYJCwAAAA==.Magdalena:BAABLgAECn8hAAINAAgJGyW/AgBtAwANAAgJGyW/AgBtAwAAAA==.Magedand:BAAALgAECgMJAwAAAA==.Magnesson:BAAALgAFFAEJAgAAAA==.Manakaren:BAAALgADCggJDAAAAA==.Mazuro:BAACLgAFFH8GAAILAAMJpBosBQAVAQALAAMJpBosBQAVAQAuAAQKfyIAAwsABwlgH24CABMCAAsABwlgH24CABMCABYAAQlGGVYdAEAAAAAA.',
Me='Meatkleaver:BAABLgAECn8bAAMPAAkJ0BUfAwBnAgAPAAkJ0BUfAwBnAgAOAAEJqAF2NgEiAAAAAA==.Meau:BAABLgAECn8aAAIXAAgJtBy4AQDrAQAXAAgJtBy4AQDrAQAAAA==.Mechadar:BAAALgAECgMJAwAAAA==.Mechanizedtv:BAABLgAECn+LAAQEAAkJrSUNAABnAwAEAAkJrSUNAABnAwAXAAYJURv8AgCWAQAYAAEJaALSJQAiAAABLgADCgcJCgABAAAAAA==.',
Mo='Monkerooz:BAAALgAECgIJBAAAAA==.Moodeng:BAAALgADCgYJBwAAAA==.Morphîne:BAAALgAFFAIJAgAAAA==.',
Mu='Mugwump:BAAALgADCgIJAgAAAA==.Murdøk:BAAALgAECgYJDwAAAA==.',
My='Mythic:BAABLgAECn8VAAINAAcJuBrJFgAxAgANAAcJuBrJFgAxAgAAAA==.',
['Mû']='Mûrdok:BAAALgAECgQJCgABLgAECgYJDwABAAAAAA==.',
['Mü']='Mürdok:BAAALgAECgYJCAABLgAECgYJDwABAAAAAA==.',
Na='Narkis:BAAALgADCgcJBwAAAA==.',
Ne='Nefarius:BAAALgAECggJEgAAAA==.Neph:BAABLgAECn8aAAMZAAkJQw92HwDlAQAZAAkJQw92HwDlAQARAAIJbgNeUABNAAAAAA==.',
Ni='Nihilism:BAAALgADCgYJBgAAAA==.Ninsu:BAAALgAECgYJCgAAAA==.Nishale:BAAALgAECgMJBAAAAA==.',
No='Noir:BAAALgADCgQJBAAAAA==.',
Nu='Nutdraggin:BAAALgADCgcJBwAAAA==.',
Ny='Nyki:BAAALgAECgUJBgAAAA==.',
Op='Opius:BAAALgAECgQJBAAAAA==.',
Or='Orcmagic:BAAALgADCgQJBAAAAA==.',
Os='Oshift:BAAALgAECgYJBgAAAA==.',
Pa='Pandinha:BAACLgAFFH8IAAIOAAMJ4RmtMwC6AAAOAAMJ4RmtMwC6AAAuAAQKfy0AAg4ACQn3ICwMADkDAA4ACQn3ICwMADkDAAAA.',
Pd='Pdr:BAAALgADCgcJBwAAAA==.',
Pe='Pedri:BAAALgAECgIJBAAAAA==.Pedrok:BAAALgAECgMJAwAAAA==.',
Ph='Phoenixashes:BAAALgADCgIJAgAAAA==.',
Pr='Priestiality:BAAALgADCgIJAgAAAA==.Prowl:BAAALgAECgEJAQABLgAFFAQJCwAaAOEVAA==.Prscilla:BAAALgADCgcJBgAAAA==.',
Ra='Radagast:BAAALgADCgcJDQABLgAECggJGQAGAPkQAA==.Radulf:BAAALgAECgQJBAAAAA==.Raph:BAABLgAECn8jAAIOAAcJVSPcAwBcAgAOAAcJVSPcAwBcAgAAAA==.Raphy:BAAALgAECgYJBgABLgAECgcJIwAOAFUjAA==.Ravyn:BAAALgADCgUJBQAAAA==.',
Re='Reckon:BAAALgAECgYJCgAAAA==.Redthedeer:BAAALgAECgYJCQAAAA==.Redzone:BAAALgAECgQJBgAAAA==.Refuliya:BAAALgADCgkJBwAAAA==.Remmahcm:BAABLgAECn8VAAIFAAgJUBY0PwApAgAFAAgJUBY0PwApAgAAAA==.Renewing:BAAALgADCgQJBAAAAA==.Renrir:BAAALgADCgcJCAAAAA==.',
Rh='Rhark:BAAALgAECgMJAwAAAA==.',
Ri='Rikku:BAAALgADCgQJBAAAAA==.',
Ro='Rook:BAAALgAECgYJCQABLgAECggJIgAKAEEdAA==.',
Ru='Runnow:BAAALgADCgYJCwAAAA==.',
Sa='Sagas:BAAALgAECgEJAQAAAA==.Salina:BAAALgADCgQJBwABLgAECgMJBAABAAAAAA==.Sammysam:BAAALgADCgUJBwAAAA==.',
Sc='Scotch:BAAALgADCgQJBAABLgAECggJHgANABoZAA==.',
Sh='Shelton:BAAALgADCgMJAwABLgADCggJDQABAAAAAA==.Shinjey:BAAALgAECgMJBwAAAA==.',
Si='Sil:BAABLgAECn8ZAAIbAAkJCwrxFwCXAQAbAAkJCwrxFwCXAQAAAA==.Siphon:BAAALgAECgYJCwAAAA==.Siphons:BAAALgAECgMJAwAAAA==.',
Sk='Ska:BAACLgAFFH8NAAIIAAUJOhXgBQBcAQAIAAUJOhXgBQBcAQAuAAQKfxsAAwgACAm7H1sYAMMCAAgACAm7H1sYAMMCABwAAQkAAINwADUAAAAA.',
Sl='Slyzete:BAAALgAECgMJAwAAAA==.',
So='Softbutt:BAAALgAECgcJCAAAAA==.Sophie:BAAALgADCgcJBwAAAA==.Soulseeker:BAAALgAECgYJEgAAAA==.',
St='Stölen:BAAALgAECgEJAQAAAA==.',
Sy='Sylthas:BAAALgADCgMJAwAAAA==.Syrensong:BAAALgADCggJDQAAAA==.',
Ta='Tankli:BAAALgAECgEJAgAAAA==.Tanriel:BAAALgAECgEJAQAAAA==.Tatl:BAAALgADCgkJCQAAAA==.',
Te='Tertletoes:BAABLgAECn8cAAQdAAkJECXtAAC+AwAdAAkJECXtAAC+AwAHAAEJ2x49JwBMAAAGAAEJ/h222gA5AAAAAA==.Teto:BAAALgAECgYJDgAAAA==.',
Th='Thebartender:BAAALgAECgcJDAAAAA==.Thella:BAAALgAECgQJBgAAAA==.Thopowisiwi:BAAALgAECgMJBAAAAA==.',
To='Tog:BAABLgAECn8bAAIJAAkJciLJAwBVAwAJAAkJciLJAwBVAwAAAA==.Togame:BAAALgAECgQJBQAAAA==.Tognahok:BAAALgADCgYJDgAAAA==.Togy:BAAALgADCgEJAQAAAA==.',
Tr='Tremboladin:BAABLgAECn8aAAIeAAcJHxoxJgD2AQAeAAcJHxoxJgD2AQABLgAFFAIJAgABAAAAAA==.',
Tu='Turbosocks:BAAALgAECgIJBAAAAA==.Turok:BAAALgADCgMJAwAAAA==.Turtles:BAAALgADCgEJAQABLgAECgkJHAAdABAlAA==.Tuskydin:BAAALgADCgcJCQAAAA==.',
Ty='Tylandord:BAAALgADCgEJAQAAAA==.',
['Tý']='Týråél:BAAALgADCgYJCwAAAA==.',
Ur='Urra:BAABLgAECn8hAAIfAAgJ9RgJIAAPAgAfAAgJ9RgJIAAPAgAAAA==.',
Va='Valoo:BAAALgAECgQJCgAAAA==.',
Ve='Veyron:BAAALgADCgMJAwAAAA==.',
Vi='Vicar:BAAALgADCgEJAQAAAA==.',
Vo='Voidstrider:BAAALgAECgcJCgAAAA==.',
We='Weezard:BAAALgAECgQJDQAAAA==.',
Wh='Wheein:BAABLgAECn8aAAIRAAgJRiBpAQCHAgARAAgJRiBpAQCHAgAAAA==.',
Wi='Wingolingo:BAAALgAECgIJAgAAAA==.',
Ya='Yaamoonn:BAAALgADCgUJBQAAAA==.',
Ye='Yenn:BAABLgAECn8bAAMIAAkJXhtKFgDPAgAIAAkJXhtKFgDPAgAcAAIJwAEfWgBgAAAAAA==.',
Ze='Zenin:BAAALgADCggJFQAAAA==.Zenu:BAABLgAECn8dAAMfAAgJ7BsWEgCSAgAfAAgJ7BsWEgCSAgAgAAEJzRV3DABPAAAAAA==.',
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

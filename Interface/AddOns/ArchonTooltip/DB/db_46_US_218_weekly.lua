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

local lookup = {'Unknown-Unknown','DeathKnight-Frost','Monk-Mistweaver','Priest-Holy','Paladin-Holy','Druid-Restoration','Druid-Balance','DemonHunter-Devourer','Warrior-Protection','Paladin-Retribution','Priest-Shadow','Warlock-Demonology','Hunter-Survival','Warlock-Destruction','Shaman-Elemental','Mage-Frost','Shaman-Restoration','DeathKnight-Unholy','DeathKnight-Blood','Priest-Discipline','Warrior-Arms','Warrior-Fury','Evoker-Preservation','Hunter-BeastMastery','Rogue-Assassination','Evoker-Augmentation','DemonHunter-Vengeance','Monk-Brewmaster','Rogue-Outlaw','Monk-Windwalker','Hunter-Marksmanship',}
local provider = {region='US',realm='ThoriumBrotherhood',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Absolver:BAAALgADCgYJCwAAAA==.',
Ad='Addu:BAAALgADCgYJBgAAAA==.',
Ae='Aeralina:BAAALgAECggJDgAAAA==.Aerandir:BAAALgAECgYJDwABLgAFFAEJAQABAAAAAA==.Aerwyn:BAAALgAECgYJBgAAAA==.',
Ah='Ahmyra:BAAALgAECgYJDAAAAA==.',
Al='Alessar:BAAALgAECgYJDAAAAA==.Allysson:BAABLgAECn8cAAICAAcJiw9ZBwA5AQACAAcJiw9ZBwA5AQAAAA==.Alyestra:BAAALgAECgQJBgAAAA==.',
An='Animyst:BAABLgAECn82AAIDAAgJBiPfAwDuAgADAAgJBiPfAwDuAgABLgAECggJKgAEAIciAA==.Anipaltu:BAABLgAECn8WAAIFAAYJzR0OFADyAQAFAAYJzR0OFADyAQABLgAECggJKgAEAIciAA==.Aniron:BAAALgAECgYJDgABLgAECggJKgAEAIciAA==.Anirot:BAABLgAECn8qAAIEAAgJhyInAwD+AgAEAAgJhyInAwD+AgAAAA==.',
Ar='Aranta:BAABLgAECn8UAAMGAAYJRwsWSADyAAAGAAYJRwsWSADyAAAHAAYJ9AkSLADoAAAAAA==.',
As='Astren:BAAALgAECgEJAQAAAA==.Asynsia:BAABLgAECn8eAAIIAAgJhSBrDgBVAgAIAAgJhSBrDgBVAgAAAA==.',
Av='Avamani:BAAALgADCgkJCQAAAA==.',
Ba='Balrogg:BAAALgADCgcJBwAAAA==.Banashain:BAAALgADCgEJAgAAAA==.Bartholomew:BAABLgAECn8eAAIDAAgJTBs1CAByAgADAAgJTBs1CAByAgAAAA==.Bartno:BAAALgAECgIJAQAAAA==.',
Be='Beefed:BAAALgADCgIJAgAAAA==.Bessie:BAAALgADCgIJAgAAAA==.',
Bi='Bienfaiseur:BAABLgAECn8eAAIEAAgJASTcAQA5AwAEAAgJASTcAQA5AwAAAA==.',
Bl='Bladez:BAAALgAECgEJAQAAAA==.',
Bo='Boombawks:BAAALgADCgUJBQABLgADCgYJAgABAAAAAA==.Boryndin:BAABLgAECn8VAAIJAAgJFBeVCgDFAQAJAAgJFBeVCgDFAQAAAA==.',
Br='Brad:BAAALgADCgIJAgAAAA==.Breadburn:BAAALgADCggJCAAAAA==.Breezybb:BAABLgAECn8yAAIKAAkJfRcrOgA6AgAKAAkJfRcrOgA6AgAAAA==.',
Ca='Camhawk:BAAALgADCgkJCQAAAA==.Catastrophe:BAAALgADCgUJBQAAAA==.',
Ce='Cearylin:BAAALgADCgcJEwAAAA==.Cering:BAAALgAECgYJBgAAAA==.',
Ch='Cherypoptart:BAABLgAECn8WAAILAAcJKyIJBwBgAgALAAcJKyIJBwBgAgAAAA==.Chrismeister:BAAALgAECgIJAwAAAA==.',
Co='Codah:BAAALgAECgEJAgAAAA==.Corbenik:BAAALgAECgIJAgABLgAECgcJGAAMAPEHAA==.',
Cr='Creel:BAAALgADCgYJBgAAAA==.Crettephal:BAEALgAECgIJAwAAAA==.',
['Cä']='Cähira:BAAALgADCgUJBQABLgADCgYJCQABAAAAAA==.',
Da='Daellan:BAAALgAECgMJBAAAAA==.Dainaira:BAAALgAECgYJCwAAAA==.Daisia:BAABLgAECn8WAAINAAYJGQe9HwABAQANAAYJGQe9HwABAQAAAA==.Dalarrong:BAAALgAECgIJAgAAAA==.Dasteaire:BAAALgAECgMJBgAAAA==.',
De='Deathdealler:BAAALgADCgUJCgAAAA==.Demonicadhd:BAAALgAECgYJEwAAAA==.Demonsmind:BAABLgAECn8VAAMMAAcJBw+MYgAKAQAMAAYJ9AyMYgAKAQAOAAMJqhEsQQCwAAAAAA==.Derien:BAABLgAECn8eAAIJAAgJ9BbkEAD6AQAJAAgJ9BbkEAD6AQAAAA==.Derienfu:BAAALgAECgYJBgAAAA==.Dezin:BAAALgADCgUJBQAAAA==.',
Di='Dinkeldorf:BAAALgAECgMJBAABLgAECgcJDwABAAAAAA==.',
Dk='Dkerien:BAAALgAECgYJBgAAAA==.',
Do='Donkeyteeth:BAABLgAECn8XAAIPAAgJHA2PIABLAQAPAAgJHA2PIABLAQAAAA==.Downtownbuu:BAAALgADCgcJDAAAAA==.',
Dr='Dracarian:BAAALgADCgMJAwAAAA==.Dracorz:BAAALgAECgUJCgAAAA==.Dru:BAAALgADCgcJBwAAAA==.Drywater:BAABLgAECn8XAAIQAAYJgQlChAAJAQAQAAYJgQlChAAJAQAAAA==.',
Du='Dura:BAABLgAECn8ZAAIRAAYJNBf/JQCLAQARAAYJNBf/JQCLAQAAAA==.',
El='Eldunari:BAAALgAECgQJBAAAAA==.Elfblood:BAABLgAECn8kAAIOAAgJfgq9CQA7AQAOAAgJfgq9CQA7AQAAAA==.Elvion:BAAALgAECgMJBQAAAA==.',
Em='Emollama:BAABLgAECn8vAAMSAAkJmAxdKQDXAQASAAkJmAxdKQDXAQATAAEJJwJlTQAcAAAAAA==.',
En='Engine:BAAALgADCgQJBAAAAA==.',
Er='Erilana:BAAALgAECgEJAQAAAA==.',
Et='Etiimasi:BAAALgADCgYJBwAAAA==.',
['Eï']='Eïr:BAAALgAECgQJCAABLgAFFAIJAgABAAAAAA==.',
Fa='Fabulosa:BAABLgAECn8nAAQUAAgJYgzhLwAhAQAUAAYJ2wnhLwAhAQALAAgJmgjGJgAPAQAEAAUJYAqFNwCbAAAAAA==.Faith:BAAALgAECgYJDwAAAA==.',
Fi='Finiquito:BAAALgADCgMJAwAAAA==.Finite:BAAALgADCgkJEAABLgAECgcJHgAKAIgZAA==.Firebug:BAAALgAECgYJDAAAAA==.',
Fn='Fndruid:BAAALgADCgEJAQAAAA==.Fnmage:BAAALgADCgcJEAAAAA==.',
Fu='Furnok:BAABLgAECn8eAAMPAAgJvAzDIABJAQAPAAgJvAzDIABJAQARAAQJMhDuVQCnAAAAAA==.',
Ga='Galethia:BAAALgADCgkJGAAAAA==.Garli:BAAALgADCgMJAwAAAA==.',
Ge='Gerkin:BAAALgADCgcJDwAAAA==.',
Gg='Ggcthulhu:BAAALgAECgMJBAABLgAECgYJCAABAAAAAA==.',
Gh='Ghutz:BAABLgAECn8xAAMVAAgJFBgNBwDsAQAVAAgJFBgNBwDsAQAWAAcJiAs0SACDAQAAAA==.',
Gl='Glitterhoof:BAAALgAECgYJDwAAAA==.Glorblariirn:BAAALgADCgYJBgAAAA==.',
Go='Goliath:BAAALgAECgUJCwAAAA==.',
Gr='Grimbjorne:BAAALgADCgcJBwAAAA==.Grimmbeardd:BAAALgADCgYJCgAAAA==.',
Gu='Gumbercules:BAABLgAECn8kAAIXAAgJqxAbCgC0AQAXAAgJqxAbCgC0AQAAAA==.',
Ha='Hammie:BAAALgADCgkJCQAAAA==.',
He='Hearthglen:BAABLgAECn8VAAIKAAYJWg/ZaQAaAQAKAAYJWg/ZaQAaAQAAAA==.',
Ho='Hollet:BAAALgAECgQJCgAAAA==.Holyblasto:BAAALgADCgEJAQAAAA==.Holyshukk:BAACLgAFFH8HAAIFAAMJXhi0FgDyAAAFAAMJXhi0FgDyAAAuAAQKfyMAAwUACQmRIqAFABIDAAUACQmRIqAFABIDAAoAAQlCB1IUAS0AAAAA.',
Hu='Huckk:BAAALgADCgUJBQAAAA==.',
Hy='Hylen:BAAALgAECgcJCQAAAA==.',
Ib='Ibrandul:BAABLgAECn8eAAIKAAcJhRHMRwBuAQAKAAcJhRHMRwBuAQAAAA==.',
Ic='Icyveins:BAABLgAECn8UAAIQAAcJ8wGZrgC3AAAQAAcJ8wGZrgC3AAAAAA==.',
Ir='Ironhuntress:BAABLgAECn8WAAIYAAYJtg3xTQAkAQAYAAYJtg3xTQAkAQAAAA==.',
It='Ithro:BAABLgAECn8fAAIZAAgJlReTAwD3AQAZAAgJlReTAwD3AQAAAA==.',
Iy='Iyachtu:BAAALgAECgkJBwAAAA==.',
Ja='Jarlo:BAABLgAECn8kAAIZAAgJyxI5BADTAQAZAAgJyxI5BADTAQAAAA==.',
Je='Jeffeory:BAAALgAECgIJAgABLgAECggJKgAKAFoZAA==.',
Jo='Jobu:BAAALgAECgEJAQAAAA==.Jormungandr:BAABLgAECn8cAAIVAAgJKSGWBAA3AgAVAAgJKSGWBAA3AgAAAA==.',
Ju='Juanhunglow:BAAALgADCgcJIwAAAA==.Judgederien:BAAALgAECgIJAgAAAA==.Jularity:BAAALgADCgYJBgAAAA==.',
Ka='Kaeldric:BAABLgAECn8YAAISAAcJMh7+JADuAQASAAcJMh7+JADuAQAAAA==.Kaladïn:BAAALgAECgEJAQAAAA==.Kalemshai:BAAALgADCgcJCwAAAA==.Kalinea:BAABLgAECn8fAAIYAAcJRBTkWABdAQAYAAcJRBTkWABdAQAAAA==.Kazuha:BAAALgAECgYJDgAAAA==.',
Ke='Kellerun:BAAALgADCgIJAgAAAA==.Ketosis:BAAALgADCggJCgAAAA==.',
Ko='Kope:BAABLgAECn8hAAIXAAgJ3hioBwD1AQAXAAgJ3hioBwD1AQAAAA==.',
Kr='Kreltor:BAABLgAECn8aAAIRAAYJBCITEAA+AgARAAYJBCITEAA+AgAAAA==.Kryptikz:BAAALgAECgYJCwABLgAECgYJEAABAAAAAA==.Krystoferson:BAAALgAECgYJDAAAAA==.',
La='Largar:BAAALgADCgQJBAAAAA==.',
Le='Leerroyy:BAAALgADCgIJAgAAAA==.Leesoftpaw:BAAALgADCgYJAgAAAA==.Leianii:BAAALgADCgUJDAAAAA==.Lextali:BAAALgAECgQJBAAAAA==.',
Lh='Lhondar:BAAALgAECgQJBAAAAA==.',
Li='Liafail:BAABLgAECn8YAAIMAAcJ8QejgwBTAQAMAAcJ8QejgwBTAQAAAA==.Lillat:BAAALgAECgUJCwAAAA==.Liryv:BAAALgADCgYJFAAAAA==.Littlepop:BAAALgADCgEJAQAAAA==.',
Lu='Luena:BAAALgAECgYJDQAAAA==.Lumbre:BAAALgADCgcJCQAAAA==.Luminara:BAAALgADCgkJCwAAAA==.',
Ly='Lyrà:BAAALgAECgQJAwAAAA==.',
['Lì']='Lìesson:BAABLgAECn8cAAIKAAgJ+h7cEgBjAgAKAAgJ+h7cEgBjAgAAAA==.',
Ma='Mackaroni:BAAALgAECgYJDwABLgAECgcJDwABAAAAAA==.Madrel:BAAALgADCgUJBQAAAA==.Magesca:BAABLgAECn8jAAIQAAgJkRQzMwDUAQAQAAgJkRQzMwDUAQAAAA==.Makkagg:BAACLgAFFH8JAAMJAAMJoxM/DgDSAAAJAAMJoxM/DgDSAAAWAAEJAQZaJABLAAAuAAQKfy0AAwkACAmVIFwDAJUCAAkACAmVIFwDAJUCABYACAlWDMM5AL8BAAAA.Malamur:BAAALgADCggJEgAAAA==.Malisea:BAABLgAECn8UAAIQAAYJUQWMmADiAAAQAAYJUQWMmADiAAAAAA==.',
Mi='Milagrosa:BAABLgAECn8bAAIaAAgJEg6vGQBxAQAaAAgJEg6vGQBxAQAAAA==.Mirael:BAACLgAFFH8FAAIYAAMJJB0kHgAgAQAYAAMJJB0kHgAgAQAuAAQKfywAAhgACQnhH8EIAAcDABgACQnhH8EIAAcDAAAA.Mishuntsalot:BAAALgADCgYJCQAAAA==.',
Mo='Molocherx:BAAALgADCgMJAwAAAA==.Mommacoo:BAAALgAECgUJCQAAAA==.',
Mu='Mumsurprise:BAAALgAECgkJAgAAAA==.',
My='Myrmia:BAABLgAECn8WAAIGAAYJQg3qQwADAQAGAAYJQg3qQwADAQAAAA==.Mystryx:BAAALgAECgUJCQAAAA==.',
['Mà']='Màck:BAAALgAECgcJDwAAAA==.',
Na='Nade:BAAALgAECgcJBAAAAA==.Naldor:BAAALgADCgkJCQAAAA==.Nargul:BAABLgAECn8cAAIMAAYJhBNDWwAcAQAMAAYJhBNDWwAcAQAAAA==.Naturboom:BAAALgAECgEJAQAAAA==.',
Ne='Nekossian:BAAALgAECgYJCwABLgAECggJKgAKAFoZAA==.',
Ni='Nickorvis:BAAALgADCgUJBQABLgAECgcJGAAMAPEHAA==.',
No='Nonae:BAEALgADCgYJBgAAAA==.Nota:BAABLgAECn8WAAIKAAYJ+wZQkwDHAAAKAAYJ+wZQkwDHAAAAAA==.',
Oa='Oathmere:BAAALgADCgUJBQAAAA==.',
Og='Ogrusao:BAAALgAECgYJCgAAAA==.',
Pa='Panasaurus:BAABLgAECn8kAAIbAAgJ2xI3BwB/AQAbAAgJ2xI3BwB/AQAAAA==.',
Pe='Pechuuga:BAABLgAECn8WAAIcAAcJvhl/MgCHAQAcAAcJvhl/MgCHAQAAAA==.Pelli:BAABLgAECn8XAAILAAYJlwWrLgDcAAALAAYJlwWrLgDcAAAAAA==.Pendraig:BAAALgADCgUJCAAAAA==.',
Pl='Plaza:BAAALgAECgkJCAAAAA==.',
Qu='Quadrilio:BAAALgADCgUJBQAAAA==.Quamutei:BAAALgADCgUJBgAAAA==.',
Ra='Raylisarri:BAAALgAECgEJAgABLgAECgQJDAABAAAAAA==.Rayst:BAAALgAECgQJEAAAAA==.Razìel:BAAALgADCgMJAgAAAA==.',
Rh='Rhalek:BAAALgAECgUJCQABLgAECggJMQAGALUhAA==.Rheunae:BAAALgAECgQJBAAAAA==.Rhykis:BAABLgAECn8WAAIWAAYJ6x+BEgDaAQAWAAYJ6x+BEgDaAQAAAA==.',
Ri='Rilis:BAAALgADCgEJAQAAAA==.Rillyn:BAABLgAECn8gAAINAAgJaxMhCwDyAQANAAgJaxMhCwDyAQAAAA==.',
Ro='Rojei:BAAALgADCgYJBgAAAA==.Role:BAAALgADCgEJAQABLgAECggJHgAdAGQXAA==.',
Ru='Rubbin:BAAALgAECgEJAQAAAA==.',
Sa='Salindill:BAAALgADCgMJAwAAAA==.Salline:BAAALgAECgQJDgAAAA==.Samanda:BAAALgAECgYJDgAAAA==.Samshir:BAAALgAFFAEJAQAAAA==.',
Sc='Scorned:BAABLgAECn8hAAIIAAcJ4hBaQQA1AQAIAAcJ4hBaQQA1AQAAAA==.',
Se='Sekrain:BAAALgAECgQJBAAAAA==.',
Sh='Shamnasty:BAAALgAECgcJEwAAAA==.Shariaan:BAAALgADCgkJJwAAAA==.Shaylinn:BAAALgADCgcJHwAAAA==.Shukkvoker:BAAALgADCgQJBQABLgAFFAMJBwAFAF4YAA==.',
Si='Siella:BAABLgAECn8ZAAIEAAYJXBZoGQCCAQAEAAYJXBZoGQCCAQAAAA==.Sileves:BAAALgADCgkJDQAAAA==.Sitrom:BAAALgAECgUJCwAAAA==.',
Sn='Snayd:BAABLgAECn8VAAIQAAYJTCFYLQDsAQAQAAYJTCFYLQDsAQAAAA==.',
So='Sonofmums:BAAALgAECgcJBgAAAA==.Soulbaine:BAAALgAECgQJCQAAAA==.',
Sp='Spazeric:BAABLgAECn8YAAMDAAgJ5xddEwDFAQADAAcJNhZdEwDFAQAeAAQJdRPGWQCpAAAAAA==.Spheria:BAABLgAECn8fAAIMAAgJgAMmaQD6AAAMAAgJgAMmaQD6AAAAAA==.',
St='Stalon:BAAALgADCgYJDgAAAA==.Strangeluve:BAAALgAECgcJDAAAAA==.',
Su='Suerte:BAAALgADCggJDQAAAA==.Suzieq:BAAALgADCgMJAwAAAA==.',
Sy='Sysnootles:BAAALgADCgYJBwAAAA==.',
['Sà']='Sàyori:BAAALgAECgUJBwAAAA==.',
Ta='Tabrett:BAAALgAECgIJAgAAAA==.Tankdezoe:BAAALgAECgMJBAABLgAECgQJBQABAAAAAA==.Tarall:BAAALgADCgMJAwAAAA==.Taveres:BAAALgADCgEJAQAAAA==.Tax:BAAALgAECgQJEAAAAA==.',
Te='Tenara:BAAALgADCgkJEgAAAA==.Tequ:BAAALgADCgcJFQAAAA==.',
Ti='Timeshadow:BAAALgAECgQJBAAAAA==.Tinakoffee:BAAALgAECgIJAgAAAA==.Tine:BAABLgAECn8eAAIQAAgJkxjzMADdAQAQAAgJkxjzMADdAQAAAA==.',
To='Tope:BAAALgAECgYJCwAAAA==.Toray:BAAALgAECgcJDgAAAA==.',
Tr='Triplesix:BAAALgAECgcJEgAAAA==.Trittia:BAAALgAECgYJEgAAAA==.',
Tu='Tukk:BAAALgAECgYJCQAAAA==.Turtle:BAAALgAECgEJAwAAAA==.',
Tw='Twigatron:BAAALgAECggJEwABLgAECgcJDAABAAAAAA==.Twigdin:BAAALgADCgMJAwAAAA==.Twigdun:BAAALgAECgMJBQAAAA==.',
Ty='Tynk:BAAALgADCgUJBQABLgADCgcJFAABAAAAAA==.',
Ur='Urza:BAAALgAECgUJBwAAAA==.',
Va='Vaewind:BAAALgADCgEJAQAAAA==.Valethus:BAABLgAECn8sAAMYAAgJLBqVFAArAgAYAAgJLBqVFAArAgAfAAIJVAgafgBNAAAAAA==.Valmaru:BAAALgADCgEJAQAAAA==.',
Ve='Vesp:BAAALgAECgMJAwAAAA==.Vexxa:BAABLgAECn8QAAIIAAgJIxohYgB7AQAIAAgJIxohYgB7AQAAAA==.',
Vy='Vynd:BAAALgADCgQJBQABLgABCgMJBAABAAAAAA==.',
Wa='Walkz:BAAALgAECgYJEAAAAA==.Warrockhealz:BAAALgADCgYJBgAAAA==.',
Wi='Wickedlight:BAABLgAECn8eAAILAAgJGRmRCgAbAgALAAgJGRmRCgAbAgAAAA==.Wiggleston:BAAALgAECgYJCgAAAA==.Willscarlet:BAAALgAECgQJBgAAAA==.',
Wy='Wylethia:BAAALgADCgcJCAAAAA==.',
Xa='Xandris:BAAALgAECgEJAgABLgAFFAEJAQABAAAAAA==.',
Yh='Yhana:BAAALgADCggJEwAAAA==.',
Yo='Yozsh:BAAALgADCgkJGAAAAA==.',
Za='Zarathia:BAAALgAECgUJCQAAAA==.Zaritym:BAABLgAECn8WAAMDAAYJ/hqZEwDBAQADAAYJ/hqZEwDBAQAeAAQJbw+BNwCiAAAAAA==.Zarrilin:BAABLgAECn8kAAIQAAgJhRZ7LwDjAQAQAAgJhRZ7LwDjAQAAAA==.',
Ze='Zebop:BAAALgADCgMJBgAAAA==.Zeeley:BAAALgADCgYJCgAAAA==.Zelsada:BAAALgAECgEJAQAAAA==.',
Zi='Zibetha:BAACLgAFFH8GAAIOAAIJ3QtaCQCbAAAOAAIJ3QtaCQCbAAAuAAQKf0IAAg4ACQkPGk4BAHsCAA4ACQkPGk4BAHsCAAAA.',
Zo='Zoeheals:BAAALgAECgQJBQAAAA==.',
Zu='Zuggtmoy:BAAALgADCgkJCQAAAA==.Zulmahn:BAAALgAECgYJEQAAAA==.',
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

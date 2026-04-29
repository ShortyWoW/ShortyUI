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

local lookup = {'Warrior-Arms','Warrior-Fury','DemonHunter-Devourer','Evoker-Augmentation','Paladin-Retribution','Warlock-Destruction','Warlock-Affliction','Warlock-Demonology','DeathKnight-Frost','Monk-Brewmaster','Priest-Discipline','Paladin-Protection','Rogue-Subtlety','Mage-Frost','Unknown-Unknown','Paladin-Holy','Shaman-Enhancement','Hunter-BeastMastery','Hunter-Marksmanship','Monk-Windwalker','Evoker-Devastation','DeathKnight-Unholy','Evoker-Preservation','Druid-Restoration','Warrior-Protection','Hunter-Survival','DemonHunter-Havoc','Priest-Holy','Priest-Shadow','Druid-Balance','Rogue-Assassination','Shaman-Elemental','Shaman-Restoration','Druid-Guardian','DeathKnight-Blood','DemonHunter-Vengeance','Monk-Mistweaver','Mage-Arcane','Druid-Feral','Mage-Fire',}
local provider = {region='US',realm='BurningBlade',name='US',type='weekly',zone=46,date='2026-04-24',data={Ac='Acerbic:BAAALgAFFAIJAgAAAA==.Acerhelper:BAACLgAFFH8UAAMBAAYJ4x8qAABHAgABAAYJ4x8qAABHAgACAAEJKg1oIABUAAAuAAQKfyEAAwEACQmLIz8AAMQDAAEACQmLIz8AAMQDAAIABgmvEZNZAEcBAAAA.',
Ad='Addh:BAACLgAFFH8FAAIDAAMJ1RHFGgD6AAADAAMJ1RHFGgD6AAAuAAQKfygAAgMACAnfH60CAIYCAAMACAnfH60CAIYCAAAA.Adumb:BAAALgADCgQJBQAAAA==.Adyhunt:BAAALgADCgUJCAABLgAFFAMJBgAEAIANAA==.Adyvictis:BAABLgAFFH8HAAIFAAUJbhMuDABKAQAFAAUJbhMuDABKAQABLgAFFAMJBgAEAIANAA==.',
Ae='Aeirtha:BAAALgADCgMJAwAAAA==.Aelara:BAAALgADCgEJAQAAAA==.Aelorst:BAABLgAECn8WAAIFAAYJsA51lQBSAQAFAAYJsA51lQBSAQAAAA==.Aelwyd:BAACLgAFFH8IAAQGAAQJjwEODwCJAAAGAAIJbQEODwCJAAAHAAEJAADTBgBPAAAIAAEJ1AHGKQA/AAAuAAQKfy0ABAYACQm6FwMVAKMBAAYABgkrGQMVAKMBAAgACAkADexkAJwBAAcAAgn+GUsqAEsAAAAA.Aeoni:BAAALgADCgYJBgABLgAECggJGQAJAP0eAA==.Aery:BAAALgAECgYJBgABLgAFFAMJBQAKAC0gAA==.Aessara:BAABLgAECn8cAAILAAcJLRyhBADRAQALAAcJLRyhBADRAQAAAA==.',
Ag='Aggron:BAAALgAECgcJEQAAAA==.Aggrosaurus:BAAALgAECgMJBAAAAA==.Aggrothar:BAAALgAFFAIJAwABLgAECgcJGgAMALoaAA==.Aggröh:BAABLgAECn8aAAIMAAcJuhrhCwALAgAMAAcJuhrhCwALAgABLgAECgcJGgAMALoaAA==.',
Ai='Ailurun:BAAALgAECgYJCwAAAA==.Aitza:BAAALgADCgUJBQAAAA==.',
Al='Alexassassin:BAABLgAECn8nAAINAAkJWSLMAADQAwANAAkJWSLMAADQAwAAAA==.Algma:BAAALgADCgMJAwAAAA==.Alorel:BAAALgAECgIJAgAAAA==.Aloriannis:BAABLgAECn8dAAIOAAgJ2ht3EAC+AQAOAAgJ2ht3EAC+AQAAAA==.Alorstus:BAAALgADCgEJAQAAAA==.Alphâ:BAAALgAECgUJCQAAAA==.Aluas:BAAALgAECgMJBQAAAA==.Alurai:BAAALgADCgYJBgAAAA==.',
Am='Amarace:BAAALgAECgYJEQABLgAECgUJCQAPAAAAAA==.Amaracepally:BAAALgADCgEJAQABLgAECgUJCQAPAAAAAA==.Amaraceshift:BAAALgAECgUJCQAAAA==.Amazing:BAABLgAECn8dAAMFAAgJux1jDQDBAQAFAAgJux1jDQDBAQAQAAUJ9xfiYQD1AAAAAA==.Amazinghulk:BAAALgADCgUJCwAAAA==.Ammorellin:BAAALgAECgIJAgABLgAFFAIJBgARAKkkAA==.Amow:BAAALgAECgIJAgABLgAECgcJFgAEADsWAA==.Amowdrac:BAABLgAECn8WAAIEAAcJOxZ+HgDQAQAEAAcJOxZ+HgDQAQAAAA==.Amowshamow:BAAALgADCgcJDgABLgAECgcJFgAEADsWAA==.Amunara:BAAALgADCgcJBwAAAA==.',
An='Anachronism:BAAALgAECgIJBAABLgAECgYJCwAPAAAAAA==.Anastasià:BAAALgAECgcJBAAAAA==.Anatall:BAABLgAECn8YAAMSAAYJyCJaKQARAgASAAYJyCJaKQARAgATAAYJuhZrBgASAQAAAA==.Andrin:BAAALgAECgQJBgAAAA==.Angiepic:BAABLgAECn8fAAMIAAgJVBDfVgDDAQAIAAgJVBDfVgDDAQAGAAMJzgwtTACJAAAAAA==.Animosity:BAAALgAECgYJCgAAAA==.Anitá:BAAALgAECgMJBQAAAA==.Antusk:BAAALgADCgEJAQAAAA==.',
Ap='Applebees:BAABLgAECn8YAAIFAAgJzx2+LABwAgAFAAgJzx2+LABwAgAAAA==.Applebeez:BAAALgAECgIJAgABLgAECgMJAwAPAAAAAA==.Applejack:BAAALgADCgkJCQAAAA==.Apêx:BAAALgAECgQJCAAAAA==.',
Ar='Arei:BAACLgAFFH8FAAIKAAMJLSAWDQAcAQAKAAMJLSAWDQAcAQAuAAQKfygAAgoACAkkIhwBAJECAAoACAkkIhwBAJECAAAA.Argosa:BAABLgAECn8bAAIOAAcJahSLGACCAQAOAAcJahSLGACCAQAAAA==.Ari:BAABLgAECn8cAAMUAAgJyiNyBABEAwAUAAgJyiNyBABEAwAKAAEJuBZQhgA5AAAAAA==.Arianagrande:BAAALgAECgYJEAAAAA==.Ariehh:BAAALgADCgcJCwABLgAECggJHAAUAMojAA==.Arioch:BAAALgAECgEJAQAAAA==.Aripud:BAAALgAECgYJEAAAAA==.Arisol:BAAALgAECgEJAQABLgAECggJHAAUAMojAA==.Arkilytê:BAACLgAFFH8bAAIDAAcJzh0ZAABTAgADAAcJzh0ZAABTAgAuAAQKfycAAgMACQncI4UBAMUDAAMACQncI4UBAMUDAAAA.Arok:BAAALgAECgUJCAAAAA==.',
As='Ascend:BAECLgAFFH8bAAIQAAcJXBsVAACAAgAQAAcJXBsVAACAAgAuAAQKfyMAAxAACQnaI5EBAGsDABAACQnaI5EBAGsDAAUAAwn9EPzwAK8AAAAA.Astar:BAAALgAECgYJEQAAAA==.',
At='Atulho:BAAALgAECgEJAQABLgAECgUJCAAPAAAAAA==.',
Au='Auroch:BAABLgAECn8gAAMEAAgJahdZFwAaAgAEAAgJABZZFwAaAgAVAAYJHRcVGAB5AQAAAA==.Auxilary:BAABLgAECn8nAAMWAAgJgx++DgCkAQAWAAgJgx++DgCkAQAJAAIJvBndBQCdAAAAAA==.',
Av='Avadakèdavra:BAAALgAECgcJAgAAAA==.Avalari:BAAALgAECgMJAwAAAA==.Avalon:BAAALgAECgUJDAAAAA==.Avarcis:BAAALgAECggJDQAAAA==.Avathauria:BAAALgADCgEJAQAAAA==.Aveleni:BAAALgAECgIJAwAAAA==.Aveloree:BAAALgAECgQJBwAAAA==.Avigdor:BAAALgAECgYJDwAAAA==.',
Aw='Awful:BAAALgAECggJCAABLgAFFAQJBwAWAAYUAA==.Awn:BAAALgADCgcJBwAAAA==.',
Az='Azelie:BAAALgAECgUJCQAAAA==.Azerrath:BAAALgADCgYJCAAAAA==.Azzhle:BAAALgADCgQJBAABLgADCgUJBQAPAAAAAA==.',
Ba='Baalian:BAAALgADCgIJAgABLgAECgYJEQAPAAAAAA==.Babbaganoosh:BAAALgADCgYJBgAAAA==.Baca:BAAALgADCgMJAwAAAA==.Bacca:BAABLgAECn8XAAIBAAgJ9hU8BABeAQABAAgJ9hU8BABeAQAAAA==.Baccah:BAAALgADCgkJGgAAAA==.Badyeof:BAAALgADCgYJCQAAAA==.Bageesus:BAAALgAECgMJBQAAAA==.Ballidur:BAAALgAECgQJBQAAAA==.Bangree:BAAALgADCgcJBwAAAA==.Banick:BAAALgAECgQJBAAAAA==.Barrey:BAEBLgAECn8aAAIXAAgJuSPQBAACAwAXAAgJuSPQBAACAwABLgAFFAcJHAAYAO8aAA==.Bartszsha:BAAALgAECgYJBgAAAA==.Bartszw:BAABLgAECn8UAAMGAAcJFBVMNgDdAAAIAAUJmhGnpgALAQAGAAQJKRVMNgDdAAAAAA==.Battlehealer:BAAALgADCgYJBgAAAA==.Bawkbawk:BAAALgAECgEJAQAAAA==.',
Be='Bearvrlyhils:BAAALgADCgYJBgAAAA==.Beefbroroni:BAAALgAECgYJCwAAAA==.Beertank:BAACLgAFFH8JAAIKAAQJ0SB2AQCMAQAKAAQJ0SB2AQCMAQAuAAQKfycAAgoACAlLJSUDAGIDAAoACAlLJSUDAGIDAAAA.Bendie:BAAALgAECgIJAwAAAA==.Beret:BAACLgAFFH8FAAIXAAMJzRlADQAMAQAXAAMJzRlADQAMAQAuAAQKfykAAhcACAmqJD4AAD0DABcACAmqJD4AAD0DAAAA.Bewmbat:BAEALgADCggJCgABLgAFFAEJAQAPAAAAAQ==.',
Bg='Bgze:BAAALgADCgUJBQABLgADCgYJBgAPAAAAAA==.',
Bi='Biaraea:BAAALgAECgMJAwAAAA==.Birdinii:BAACLgAFFH8FAAIOAAMJEBayKAARAQAOAAMJEBayKAARAQAuAAQKfygAAg4ACAlkIi0DAJoCAA4ACAlkIi0DAJoCAAAA.',
Bl='Blackrose:BAAALgADCgcJBwAAAA==.Blargwar:BAACLgAFFH8HAAMCAAMJAAZZBwDeAAACAAMJAAZZBwDeAAAZAAEJJwdFEABCAAAuAAQKfyoABAIACAnwF2ckADQCAAIACAkXFmckADQCAAEABgkVFb0XADwBABkABwlOC6cLAMIAAAAA.Blessthat:BAEALgAECgYJEAAAAA==.Blightbutter:BAAALgADCgcJBAAAAA==.',
Bo='Bonkie:BAAALgAECgEJAQABLgAECgUJCQAPAAAAAA==.',
Br='Bravewolf:BAABLgAECn8iAAIaAAgJawuxBACYAQAaAAgJawuxBACYAQAAAA==.Breccadareck:BAAALgAECgUJBgABLgAFFAEJAgAPAAAAAA==.Breckdareck:BAAALgADCgYJBgABLgAFFAEJAgAPAAAAAA==.Breckdarèck:BAAALgAFFAEJAgAAAA==.Breckkdareck:BAAALgAECgYJBwABLgAFFAEJAgAPAAAAAA==.Brecklock:BAAALgAECgEJAQABLgAFFAEJAgAPAAAAAA==.Brewdyne:BAABLgAECn8nAAIKAAkJMBrQAgAeAgAKAAkJMBrQAgAeAgAAAA==.Brianp:BAAALgAECgMJAwABLgAECggJIQAaALcjAA==.Bricktøp:BAAALgAECgYJCgAAAA==.Brisnger:BAAALgAECgcJEAAAAA==.Brodega:BAAALgADCgMJAwAAAA==.Brojojojojo:BAABLgAECn8UAAIUAAgJoBjlAwDNAQAUAAgJoBjlAwDNAQAAAA==.Brokenturnip:BAAALgAECgYJBgAAAA==.Bronzage:BAAALgAECgQJBwABLgAECgcJDwAPAAAAAA==.',
Bu='Bubb:BAAALgADCgcJBwAAAA==.Bubblesbro:BAACLgAFFH8PAAIFAAUJ0SSqAQCEAQAFAAUJ0SSqAQCEAQAuAAQKfzUAAgUACAnoJvUAAOYCAAUACAnoJvUAAOYCAAAA.Bubkiss:BAEALgAFFAEJAQAAAQ==.Buckyboo:BAAALgADCgQJBwAAAA==.Buffalo:BAACLgAFFH8FAAICAAMJjw4HEgD2AAACAAMJjw4HEgD2AAAuAAQKfyUAAgIACAmvHlIUAKsCAAIACAmvHlIUAKsCAAAA.Buffdk:BAABLgAECn8YAAMWAAcJZyAOTQAMAgAWAAYJWiAOTQAMAgAJAAMJUCCTDADoAAAAAA==.Buffs:BAAALgAECgYJDQAAAA==.Buffy:BAAALgAECgMJAwAAAA==.Bulbasaurz:BAAALgAECgYJDwAAAA==.Burstygirl:BAAALgAECgQJBQABLgAECggJIwAQAMoVAA==.',
['Bø']='Bøkari:BAAALgADCgEJAQAAAA==.',
Ca='Cakes:BAABLgAECn8WAAMDAAYJRBUqZQByAQADAAYJRBUqZQByAQAbAAIJrwl1YABgAAAAAA==.Calazone:BAAALgAECgMJAwAAAA==.Caleb:BAAALgADCgEJAQAAAA==.Calicity:BAAALgADCgMJAwAAAA==.Callie:BAACLgAFFH8bAAMLAAcJ5xlXAABDAgALAAcJ5xlXAABDAgAcAAEJQhiYFABCAAAuAAQKfygABAsACQnhImQBAH8DAAsACQmwImQBAH8DABwABwnTHxoRAFoCAB0AAwn/DYVKALAAAAAA.Candylock:BAAALgAECgcJCwAAAA==.Capitis:BAABLgAECn8XAAIGAAYJTR/tCwADAgAGAAYJTR/tCwADAgAAAA==.Carabaw:BAAALgADCgQJBAAAAA==.Catbearcow:BAAALgAECgYJDQAAAA==.Catwink:BAAALgADCgYJBgAAAA==.',
Ce='Celaine:BAAALgAECgIJAgAAAA==.Celine:BAABLgAECn8aAAMYAAgJuhoTBQAwAgAYAAgJuhoTBQAwAgAeAAEJABEMhAAsAAAAAA==.',
Ch='Ch:BAACLgAFFH8UAAMNAAcJRCEhAAD2AQANAAYJ6SIhAAD2AQAfAAEJCBlMAgBnAAAuAAQKfx8AAw0ACAnAJhMCAJMDAA0ACAnAJhMCAJMDAB8AAQlJABIjAAsAAAEuAAUUAwkDAA8AAAAA.Chaddbrochil:BAAALgAECgQJBAAAAA==.Chadillac:BAAALgADCgMJAwAAAA==.Chakra:BAAALgAECgEJAwAAAA==.Chakraiv:BAAALgADCgcJDQAAAA==.Chaosblade:BAAALgAECgIJAgAAAA==.Charlei:BAAALgAECggJEgAAAA==.Charlìe:BAAALgADCgQJBAAAAA==.Chickengawdz:BAAALgAECgUJBQAAAA==.Chizzle:BAABLgAECn8ZAAIOAAgJthT5WwAmAgAOAAgJthT5WwAmAgAAAA==.Chocobomb:BAABLgAECn8jAAMgAAkJdgmcLgCoAQAgAAkJdgmcLgCoAQAhAAQJOgI8fACiAAAAAA==.Chopchop:BAAALgADCgUJBQAAAA==.',
Ci='Cicatrizesp:BAABLgAECn8lAAIRAAgJgBYhCgAwAgARAAgJgBYhCgAwAgAAAA==.Cindyclawfrd:BAAALgAECgMJAwAAAA==.Cive:BAABLgAECn8bAAMTAAcJWggoBgAYAQAaAAYJSge8GgAmAQATAAcJHQYoBgAYAQAAAA==.',
Cl='Clîck:BAAALgADCgMJAgAAAA==.',
Co='Coldhearrted:BAABLgAECn8oAAMWAAgJwiCNMAB2AgAWAAgJiiCNMAB2AgAJAAUJ/x8FAgB0AQAAAA==.Colinrobnson:BAAALgAECgEJAgAAAA==.Connerbedard:BAABLgAECn8UAAIWAAYJvyKYRAAnAgAWAAYJvyKYRAAnAgAAAA==.Corinthian:BAAALgADCgYJDAAAAA==.Corpsemonkey:BAAALgAECgQJCAAAAA==.Cosmere:BAAALgAECgUJBAAAAA==.',
Cr='Crackychan:BAAALgADCgcJBwAAAA==.Craniotomy:BAAALgAECgYJCwAAAA==.Crisey:BAAALgAECgEJAQAAAA==.Crusidius:BAAALgADCgYJBwAAAA==.Cryos:BAABLgAECn8YAAIOAAYJoRGOvwBlAQAOAAYJoRGOvwBlAQAAAA==.Cryt:BAAALgAECgQJBAAAAA==.Crêate:BAAALgAECgMJAwAAAA==.',
Cu='Cultist:BAAALgADCgEJAQAAAA==.',
Da='Dabaja:BAABLgAECn8bAAIXAAgJYR+AAADhAgAXAAgJYR+AAADhAgAAAA==.Dagather:BAAALgAECgcJEgAAAA==.Dahnza:BAABLgAECn8jAAICAAkJTAngPgCpAQACAAkJTAngPgCpAQAAAA==.Dalelador:BAAALgAECgIJAgAAAA==.Dalkick:BAAALgADCgEJAQAAAA==.Damagra:BAAALgAECggJEgAAAA==.Danendena:BAAALgAECgYJEQAAAA==.Darkcorn:BAABLgAECn8mAAICAAkJ7RcyGwByAgACAAkJ7RcyGwByAgAAAA==.Daroot:BAAALgADCgEJAQAAAA==.Dassphinctr:BAAALgAECgYJCgAAAA==.David:BAACLgAFFH8FAAMSAAMJMCTCBQBHAQASAAMJMCTCBQBHAQATAAEJXhyxJABVAAAuAAQKfygAAxIACAlnJowAAP4CABIACAlnJowAAP4CABMACAmkHJgVAIECAAAA.Dazìze:BAABLgAECn8nAAIiAAgJcCOQAACDAgAiAAgJcCOQAACDAgAAAA==.',
De='Deadkyle:BAAALgADCgMJAwABLgAECgUJDQAPAAAAAA==.Deathblossom:BAAALgADCgEJAQABLgAECgMJAwAPAAAAAA==.Deathcalls:BAAALgAECgEJAgAAAA==.Deathlywind:BAABLgAECn8VAAIjAAcJYBGXHwBIAQAjAAcJYBGXHwBIAQAAAA==.Delphias:BAAALgAECgYJEAAAAA==.Demzar:BAABLgAECn8VAAIDAAgJPx/vIACMAgADAAgJPx/vIACMAgAAAA==.Density:BAAALgAECgMJBQAAAA==.Dereksama:BAABLgAECn8ZAAIIAAgJrA8vFQBnAQAIAAgJrA8vFQBnAQAAAA==.Derrue:BAAALgADCgYJBgABLgAECggJGQAJAP0eAA==.Destrorin:BAAALgADCgUJBQAAAA==.Detree:BAAALgAECggJCAAAAA==.Detur:BAAALgADCgQJBAAAAA==.Devis:BAAALgADCgQJBQAAAA==.Devowizard:BAACLgAFFH8UAAIOAAcJDxwDAQC/AgAOAAcJDxwDAQC/AgAuAAQKfyEAAg4ACQlEJcwGAJgDAA4ACQlEJcwGAJgDAAAA.',
Di='Dibib:BAACLgAFFH8bAAQIAAcJdBYWAgAXAgAIAAYJfBYWAgAXAgAGAAQJMROdBgAGAQAHAAEJAACiBQBWAAAuAAQKfx4AAwYACAloI9oDAKwCAAYABwlIJNoDAKwCAAgABAlNIbx3AG0BAAAA.Dingleling:BAABLgAECn8cAAIZAAgJdxY1EAAFAgAZAAgJdxY1EAAFAgAAAA==.Dinkee:BAAALgAECgEJAQABLgAECggJGwAQAAAhAA==.Discoblastin:BAAALgAECgYJBgAAAA==.Discowalker:BAAALgAECggJCAAAAA==.',
Dk='Dkittie:BAAALgAECgMJAwABLgAECggJFQAQAGEbAA==.Dkitty:BAABLgAECn8VAAMQAAgJYRvYFgBaAgAQAAgJYRvYFgBaAgAFAAEJqwtTSAEwAAAAAA==.Dkittykat:BAAALgADCgMJAwABLgAECggJFQAQAGEbAA==.Dklaive:BAAALgADCgkJCQABLgAECggJFQAQAGEbAA==.',
Do='Dogs:BAAALgADCgYJBgAAAA==.Domanatrix:BAAALgAECgIJAgAAAA==.Dominavee:BAAALgAECgQJBgAAAA==.Doraena:BAAALgADCgcJBwAAAA==.Dota:BAAALgAECgYJEwAAAA==.Doughnut:BAAALgAECgEJAQAAAA==.',
Dr='Dracke:BAAALgAECgEJAQAAAA==.Dragonde:BAAALgAECgcJDQAAAA==.Dragondenutz:BAAALgADCgYJGgAAAA==.Drainis:BAAALgAECgcJCwAAAA==.Drashog:BAAALgAECgMJAwAAAA==.Dreamcaulk:BAABLgAECn8cAAIYAAcJGh+rBgADAgAYAAcJGh+rBgADAgAAAA==.Dreamwalkar:BAAALgADCgkJDAAAAA==.Drekzul:BAAALgAECgUJBgAAAA==.Drucifer:BAAALgADCgcJBwAAAA==.Druslash:BAABLgAECn8bAAIYAAgJnw89DQCBAQAYAAgJnw89DQCBAQAAAA==.Drutara:BAABLgAECn8cAAMeAAkJAQ0oKQC2AQAeAAkJAQ0oKQC2AQAYAAMJFgLTtQBZAAAAAA==.',
Du='Duckamar:BAAALgADCgcJDgAAAA==.Ducksicker:BAAALgAECgUJBwAAAA==.Dumpsterbaby:BAACLgAFFH8HAAIWAAQJBhR4FABRAQAWAAQJBhR4FABRAQAuAAQKfyEAAhYACAmQJOccANICABYACAmQJOccANICAAAA.Dumpsterfire:BAAALgAECgUJBQAAAA==.',
Dy='Dynxsty:BAAALgAECgQJBAAAAA==.Dyxi:BAAALgADCgkJDwAAAA==.',
['Dë']='Dëku:BAAALgAECgYJBgAAAA==.',
Ed='Edgbart:BAAALgADCgEJAQAAAA==.Edgelord:BAAALgADCggJDgAAAA==.',
Ee='Eevos:BAAALgAECgUJCQAAAA==.',
Ek='Ekim:BAAALgADCgYJCAAAAA==.',
El='Ellínore:BAAALgAECgYJEAABLgAECgYJEAAPAAAAAA==.Elyaen:BAABLgAECn8YAAIjAAYJfBG2IQA0AQAjAAYJfBG2IQA0AQAAAA==.Elysium:BAABLgAECn8qAAIOAAgJISCzHgD6AgAOAAgJISCzHgD6AgAAAA==.',
Em='Emailed:BAECLgAFFH8PAAMgAAYJ1A8CCgBCAQAgAAUJWQ0CCgBCAQAhAAEJmBH5HwBTAAAuAAQKfyYAAyAACQnNIVYDAG4DACAACQnNIVYDAG4DACEAAQkMAoqcADUAAAAA.Embarked:BAEALgADCgcJBwABLgAFFAYJDwAgANQPAA==.Emi:BAAALgADCgcJDQAAAA==.Emmeline:BAAALgADCgcJDQAAAA==.',
En='Engost:BAAALgADCgMJAwAAAA==.Ensaladatoss:BAACLgAFFH8GAAIcAAIJgx5rCwCsAAAcAAIJgx5rCwCsAAAuAAQKfxQAAxwABwkIH9wVAC4CABwABwnqHtwVAC4CAAsABgnGFpEgAI8BAAAA.',
Eo='Eore:BAABLgAECn8bAAIeAAgJ+hz4AQBGAgAeAAgJ+hz4AQBGAgAAAA==.',
Er='Erdactr:BAABLgAECn8YAAIgAAgJpgigDgAaAQAgAAgJpgigDgAaAQAAAA==.Eredo:BAAALgADCgcJBwAAAA==.Eredraug:BAAALgADCgUJBQABLgAECgMJBQAPAAAAAA==.Eridyn:BAAALgADCgYJDAAAAA==.Erinys:BAAALgAECgYJDgAAAA==.',
Es='Esdeath:BAAALgADCgQJBQAAAA==.Espur:BAAALgADCgIJAgAAAA==.',
Eu='Eupatorus:BAAALgAECgcJEgAAAA==.',
Ew='Ewgank:BAAALgADCgYJBgAAAA==.Ewokhunter:BAABLgAECn8eAAINAAkJ7yLEAACeAgANAAkJ7yLEAACeAgAAAA==.',
['Eâ']='Eâgle:BAABLgAECn8UAAIWAAgJcxj8QwApAgAWAAgJcxj8QwApAgAAAA==.',
Fa='Faeline:BAAALgAECgUJBQAAAA==.Fantial:BAAALgAECgQJBAABLgAECggJGwAMABMHAA==.Fathernylla:BAAALgAECgkJEQABLgAFFAQJCQAOAJ0NAA==.',
Fe='Felpha:BAAALgADCgQJBgAAAA==.Festermight:BAACLgAFFH8SAAMWAAYJghfUAgCCAQAWAAUJghfUAgCCAQAjAAEJAABDFQBFAAAuAAQKfyEAAhYACQmrI30NAC4DABYACQmrI30NAC4DAAAA.',
Fi='Fieka:BAAALgADCgcJDgAAAA==.Figa:BAAALgAECgQJBAAAAA==.Fightsause:BAAALgAECgIJAgAAAA==.Filthyheals:BAAALgADCgIJAgAAAA==.Firenze:BAAALgAECgQJBwAAAA==.Fishycat:BAABLgAECn8WAAMXAAgJYBopDQBjAgAXAAgJYBopDQBjAgAEAAYJZRdbIAC9AQAAAA==.Fistofkrosia:BAAALgADCgUJBQAAAA==.',
Fl='Flosstradamu:BAAALgADCgQJBAABLgAFFAIJBgAcAIMeAA==.',
Fn='Fn:BAAALgAECgIJAgAAAA==.',
Fr='Francroll:BAAALgADCgEJAQAAAA==.Fredrock:BAAALgAECggJEQAAAA==.Freshmeat:BAAALgAECgMJAwAAAA==.Frog:BAAALgAECgIJAgABLgAFFAUJDgADAKkeAA==.Frostysnwman:BAAALgADCgcJCgAAAA==.',
Fu='Furrythighs:BAAALgADCgkJCQAAAA==.',
Ga='Gaibe:BAACLgAFFH8HAAIQAAMJ8hyiBQAEAQAQAAMJ8hyiBQAEAQAuAAQKfxkAAhAABwnDIxoQAJMCABAABwnDIxoQAJMCAAAA.Gamba:BAAALgAECgYJDQAAAA==.Gamin:BAAALgAECgUJCAAAAA==.Gangstafish:BAAALgADCgQJBAAAAA==.Ganicuss:BAAALgAECgkJEAAAAA==.Gann:BAAALgAECgkJBQAAAA==.',
Ge='Geezusdown:BAABLgAECn8YAAMDAAgJjBK5WQCUAQADAAgJjBK5WQCUAQAbAAIJGwerYQBcAAAAAA==.Gemshunter:BAAALgADCgEJAgAAAA==.Georgehunter:BAAALgAFFAEJAgABLgAFFAcJFgAWALIRAA==.Georgeknight:BAACLgAFFH8WAAQWAAcJshEPAQCyAQAWAAUJKRUPAQCyAQAjAAEJAADrFQBCAAAJAAEJYQDHBABAAAAuAAQKfyEAAxYACQmDIooKAEcDABYACQnYIIoKAEcDACMABQkaG2giAC4BAAAA.Gertrùde:BAAALgAECgYJEAAAAA==.Gerunash:BAAALgAECgUJCQABLgAFFAYJEQANAP8TAA==.Gewch:BAABLgAECn8WAAIYAAgJ/CR9AAA8AwAYAAgJ/CR9AAA8AwAAAA==.',
Gi='Gildarts:BAAALgAECgYJEQABLgAECgcJDQAPAAAAAA==.Gildartts:BAAALgAECgQJBAABLgAECgcJDQAPAAAAAA==.Gilddarts:BAAALgAECgcJDQAAAA==.Gildharts:BAAALgAECgQJBAABLgAECgcJDQAPAAAAAA==.',
Gl='Glorpp:BAAALgAECgMJBQAAAA==.Glowlimn:BAAALgAECgYJDwABLgAECggJGgASAJQgAA==.',
Go='Gogeta:BAAALgADCgcJBwAAAA==.Goldenbanana:BAABLgAECn8fAAIMAAgJSh3BBAC0AgAMAAgJSh3BBAC0AgAAAA==.Goodbeary:BAAALgADCgQJBwAAAA==.',
Gr='Gradris:BAACLgAFFH8FAAIFAAMJ1gleGADqAAAFAAMJ1gleGADqAAAuAAQKfygAAgUACAlNHYcGACcCAAUACAlNHYcGACcCAAAA.Greener:BAABLgAECn8iAAMbAAgJCBg1FgAaAgAbAAgJCBg1FgAaAgADAAgJ6QvfZwBrAQAAAA==.Grimghar:BAAALgADCgMJAwAAAA==.Grimrael:BAAALgAECgUJCQABLgAECgcJGAAQAL4iAA==.Grimreifer:BAAALgADCgcJFwABLgAECgcJGAAQAL4iAA==.Grimtar:BAAALgAECgYJCgABLgAECgcJGAAQAL4iAA==.Grimtariel:BAABLgAECn8YAAIQAAcJviIhGABRAgAQAAcJviIhGABRAgAAAA==.Grimzilla:BAAALgAECgYJEwABLgAECgcJGAAQAL4iAA==.Grippin:BAABLgAECn8aAAIWAAgJBx6xBgAYAgAWAAgJBx6xBgAYAgAAAA==.Groden:BAAALgADCgMJAwAAAA==.',
Gu='Guniix:BAAALgAECgYJDgAAAA==.Gunoil:BAABLgAECn8aAAIhAAgJixwdAgCHAgAhAAgJixwdAgCHAgAAAA==.',
Gw='Gwapejuith:BAAALgAECgUJBgABLgAECgYJEAAPAAAAAA==.',
['Gì']='Gìngersnap:BAAALgADCgkJEQAAAA==.',
Ha='Hafnarrot:BAAALgADCgYJBAAAAA==.Halo:BAAALgADCgYJBgAAAA==.Hamrsdeath:BAAALgAECgMJBQAAAA==.Harambae:BAAALgAECgYJCwAAAA==.',
He='Healmepls:BAAALgADCgEJAQAAAA==.Healstrike:BAAALgADCgYJBgAAAA==.Heeheehee:BAAALgADCgcJDQABLgADCgcJDwAPAAAAAA==.Hellahigh:BAAALgAECgMJBgAAAA==.Helsing:BAAALgAECgYJEAAAAA==.Herenya:BAAALgAECgMJBQAAAA==.Hest:BAAALgAECgIJAgABLgAECgMJAwAPAAAAAA==.Hexual:BAAALgAECgQJBgAAAA==.',
Hi='Hiccup:BAAALgAECgMJBAAAAA==.Hightimes:BAAALgAECgYJEAAAAA==.Hiizev:BAAALgAECgQJBQAAAA==.Hilux:BAAALgAECgEJAQAAAA==.Himnick:BAACLgAFFH8XAAQGAAgJJBmGAQDOAQAGAAYJPxWGAQDOAQAIAAQJqx1/AgCMAQAHAAEJAAARAwBhAAAuAAQKfyQABAYACQksJMoDAK8CAAYABwmyJMoDAK8CAAgACAkMIPkbAK0CAAcAAgkxIG0EAMQAAAAA.',
Ho='Holyblitz:BAABLgAECn8fAAIQAAcJrxoNCADGAQAQAAcJrxoNCADGAQAAAA==.Holydevotion:BAAALgAECgYJDAAAAA==.Holymomo:BAAALgADCgQJAwAAAA==.Holyslimes:BAAALgADCgcJEQAAAA==.Homer:BAAALgADCgcJBwAAAA==.Honoree:BAAALgAECgYJCgAAAA==.Honse:BAAALgAECgYJCgAAAA==.Hontarg:BAABLgAECn8aAAIZAAgJ0ArtGwBqAQAZAAgJ0ArtGwBqAQAAAA==.Hoovski:BAABLgAECn8aAAIOAAcJUBiQFQCWAQAOAAcJUBiQFQCWAQAAAA==.Hope:BAECLgAFFH8KAAIXAAUJiAg3BwB5AQAXAAUJiAg3BwB5AQAuAAQKfyAAAhcACAkHHngIALMCABcACAkHHngIALMCAAAA.Hornzie:BAACLgAFFH8FAAIhAAMJayGZBAAoAQAhAAMJayGZBAAoAQAuAAQKfyQAAiEACQkUJnEAAMADACEACQkUJnEAAMADAAAA.Hozen:BAAALgADCgEJAQAAAA==.',
Hu='Hungbeast:BAAALgAECgMJAwAAAA==.Huntersrop:BAAALgADCgIJAgABLgAECggJIwAQAMoVAA==.Huntesslabef:BAAALgAECgYJDAAAAA==.Huntrez:BAAALgADCgYJBgABLgAECgUJCwAPAAAAAA==.',
Hy='Hyllah:BAAALgAECgYJEwAAAA==.',
['Hò']='Hòrnz:BAAALgADCgMJAwAAAA==.',
Ia='Iamanevoker:BAABLgAECn8bAAIEAAgJxRmIAgAdAgAEAAgJxRmIAgAdAgAAAA==.',
Ic='Ickly:BAAALgADCgYJBgAAAA==.',
Ih='Ihuntu:BAAALgAECgQJCgAAAA==.',
Ii='Iillil:BAAALgAECgQJDQAAAA==.',
Il='Illhealuprob:BAAALgAECgQJBAAAAA==.Illuunni:BAAALgAECgcJBwAAAA==.',
Im='Imaarcaneu:BAAALgAECgUJBwAAAA==.Imprint:BAAALgADCgcJCgAAAA==.',
In='Inceptionz:BAAALgADCgMJAwAAAA==.Instantnoods:BAAALgAECgYJCgAAAA==.',
Ir='Ironxed:BAAALgAECgcJEwAAAA==.',
Ix='Ixx:BAAALgADCgcJAwABLgAFFAMJAwAPAAAAAQ==.',
Ja='Jameimpalla:BAAALgAECgYJEgAAAA==.Jaraxxus:BAAALgAECggJDgAAAA==.Jawn:BAAALgADCgEJAQAAAA==.',
Jc='Jclaw:BAAALgAECgQJAgAAAA==.',
Je='Jeddak:BAAALgAECggJDQAAAA==.Jehoshaphat:BAAALgADCggJEAAAAA==.Jennaortega:BAAALgAECgQJBAAAAA==.Jennzen:BAAALgAECgMJBQAAAA==.',
Jh='Jhaan:BAAALgAECgQJBAABLgAFFAIJBgAfAJ0WAA==.Jhopkinz:BAAALgADCgcJCwAAAA==.',
Ji='Jiahyu:BAAALgAECgEJAQAAAA==.',
Jl='Jlimremix:BAABLgAECn8XAAIeAAgJsSAcAQCRAgAeAAgJsSAcAQCRAgAAAA==.',
Jo='Jor:BAAALgADCgMJAgAAAA==.Jouley:BAAALgADCgYJBgAAAA==.',
Ju='Juiciest:BAEALgAECgIJAgABLgAFFAEJAgAPAAAAAA==.Jukeson:BAAALgAECgQJBAAAAA==.',
Jz='Jzimm:BAAALgAECgQJBAAAAA==.',
Ka='Kaelairn:BAAALgADCgEJAgAAAA==.Kaelvyris:BAAALgADCgMJAwAAAA==.Kaeorisera:BAACLgAFFH8QAAIWAAYJAxIDAgD8AQAWAAYJAxIDAgD8AQAuAAQKfyIAAhYACQl7IzkHAGcDABYACQl7IzkHAGcDAAAA.Kandice:BAAALgAECgYJBgAAAA==.Kaptinbadruk:BAAALgADCgEJAQAAAA==.Karina:BAAALgAECgYJDgAAAA==.Karlach:BAABLgAECn8hAAIOAAgJ2A6DFACdAQAOAAgJ2A6DFACdAQAAAA==.Karlachsimp:BAAALgAECgcJAQAAAA==.Karnesia:BAAALgAECgYJEAAAAA==.Karra:BAABLgAECn8ZAAIJAAgJ/R4UAQAGAwAJAAgJ/R4UAQAGAwAAAA==.Kathqt:BAAALgADCgIJAgAAAA==.Katresh:BAAALgAECgMJAwABLgAECgYJDgAPAAAAAA==.Kayliezra:BAAALgAECgEJAQABLgAECgMJBQAPAAAAAA==.Kayne:BAAALgAECgUJBgAAAA==.Kayssa:BAACLgAFFH8JAAIbAAQJDRQIAwBbAQAbAAQJDRQIAwBbAQAuAAQKfx8AAhsACQlgIjcCAHIDABsACQlgIjcCAHIDAAAA.Kazarn:BAAALgADCgEJAQAAAA==.Kazer:BAAALgAECgEJAQABLgAECggJGgALAB8YAA==.',
Ke='Keegan:BAABLgAECn8oAAICAAgJrh6eAQBoAgACAAgJrh6eAQBoAgAAAA==.Keiragosa:BAAALgAECgcJEwAAAA==.Keita:BAAALgAECgQJCgAAAA==.Keitaa:BAAALgAECgYJDQAAAA==.Keitah:BAAALgADCgUJBwAAAA==.Kelina:BAAALgAECgEJAQAAAA==.Kelsara:BAABLgAFFH8GAAIOAAQJHhE9GwBeAQAOAAQJHhE9GwBeAQAAAA==.',
Kh='Khaladyn:BAAALgAECgIJAgAAAA==.',
Ki='Kibble:BAAALgAECgIJAgAAAA==.Kieta:BAAALgAECgQJBAABLgAECgQJCgAPAAAAAA==.Kiko:BAAALgAECgMJBQAAAA==.Killstardo:BAAALgAECgcJDgAAAA==.Kimbap:BAAALgAECgQJDQAAAA==.Kimochii:BAAALgAECgYJCwAAAA==.Kindatipsy:BAAALgAECgQJBwAAAA==.Kinetikx:BAAALgAECgYJDgAAAA==.Kirasti:BAAALgAECgMJBQAAAA==.Kirkadh:BAEALgAECgEJAQABLgAFFAcJHAAYAO8aAA==.Kisspr:BAABLgAECn8bAAIdAAgJqyOZBABLAwAdAAgJqyOZBABLAwAAAA==.Kitkatt:BAAALgAECgcJEgAAAA==.',
Kl='Klet:BAAALgAECgUJCgAAAA==.',
Km='Kmage:BAABLgAECn8dAAIOAAYJMRsvHwBaAQAOAAYJMRsvHwBaAQAAAA==.',
Kn='Knockeyx:BAAALgADCgUJBQAAAA==.',
Ko='Kogthesecond:BAAALgAECgIJAgAAAA==.Kokodrilo:BAAALgAECgkJAgAAAA==.Kolpoll:BAAALgADCgIJAgAAAA==.Koramar:BAAALgAECgYJCwABLgAFFAYJEQANAP8TAA==.',
Kq='Kqs:BAAALgAECgQJBQAAAA==.',
Kr='Kragarsf:BAAALgAECgMJBQAAAA==.Kruziik:BAAALgAECgQJBAAAAA==.Krylancelo:BAAALgAECgIJAgAAAA==.',
Ku='Kunalo:BAAALgADCgcJBwAAAA==.Kupona:BAAALgAECgUJDAAAAA==.',
Ky='Kyoppy:BAABLgAECn8iAAIQAAgJgB6ZDgCiAgAQAAgJgB6ZDgCiAgAAAA==.',
['Kæ']='Kæzen:BAAALgADCgYJBQAAAA==.',
La='Labluegirl:BAAALgAECgQJBAAAAA==.Ladend:BAABLgAECn8eAAMjAAgJyxq3DABEAgAjAAgJvxi3DABEAgAWAAcJ0RpoYQDPAQAAAA==.Lall:BAAALgAECgMJAwAAAA==.Lanar:BAAALgAECgYJCQAAAA==.Lantis:BAAALgADCgYJBgAAAA==.Lateralusei:BAAALgADCgUJCAAAAA==.',
Le='Leftyy:BAAALgAECgIJAgAAAA==.Legndairy:BAABLgAECn8UAAMCAAgJKxl8KgAOAgACAAYJAiB8KgAOAgAZAAIJEAh4PQBhAAAAAA==.Leinekki:BAAALgADCgkJEQAAAA==.Lenala:BAAALgAECgMJAwAAAA==.Lenie:BAABLgAECn8VAAIYAAgJUiJ8DADaAgAYAAgJUiJ8DADaAgABLgAFFAYJFQAYAFEiAA==.Letmetuchu:BAAALgADCgcJEgAAAA==.',
Li='Lickwid:BAAALgAECgQJBAAAAA==.Liege:BAABLgAECn8bAAIDAAcJXB0XBwAEAgADAAcJXB0XBwAEAgAAAA==.Lif:BAAALgADCgUJBQAAAA==.Lightbody:BAAALgADCgYJBwAAAA==.Lightdeity:BAABLgAECn8eAAIQAAgJsBrXFgBaAgAQAAgJsBrXFgBaAgAAAA==.Lime:BAAALgAECgYJEAAAAA==.Limp:BAAALgAECgEJAQAAAA==.Limzahn:BAABLgAECn8dAAIUAAgJxh7TDACtAgAUAAgJxh7TDACtAgAAAA==.Lindormi:BAAALgAECgEJAQAAAA==.Linessa:BAAALgAECgcJDQAAAA==.Lionator:BAABLgAECn8eAAIDAAgJBBkzPwD3AQADAAgJBBkzPwD3AQAAAA==.Liora:BAAALgAECggJCAAAAA==.Lippillow:BAAALgAECgYJEQAAAA==.Littleteapot:BAABLgAECn8bAAIeAAcJoRsGHgAQAgAeAAcJoRsGHgAQAgAAAA==.Littlewig:BAAALgADCgcJCAAAAA==.Livalia:BAABLgAECn8jAAIdAAkJVB7MAQBZAgAdAAkJVB7MAQBZAgAAAA==.Lizagna:BAAALgAECgMJAwAAAA==.',
Lo='Loadstar:BAAALgAECgUJBgAAAA==.Lobster:BAAALgAECgYJCgAAAA==.Locktaur:BAABLgAECn8YAAIGAAcJ7REqEwCyAQAGAAcJ7REqEwCyAQAAAA==.Lokrates:BAABLgAECn8lAAMGAAgJZiK6CQAkAgAGAAYJIiC6CQAkAgAIAAUJpR/jCgDHAQAAAA==.Lorentz:BAAALgAECgYJEQAAAA==.Lorthus:BAAALgADCgQJBQAAAA==.',
Lu='Lucentil:BAAALgAECgEJAQABLgAECgMJBQAPAAAAAA==.Lucie:BAAALgAECgYJDQABLgAECggJCAAPAAAAAA==.Lucienn:BAAALgAECgIJAgAAAA==.Lucigoosey:BAAALgAECggJCwAAAA==.Ludynasty:BAAALgAECgQJBAAAAA==.Lumindra:BAAALgAECgYJBgAAAA==.Luminth:BAAALgAECgQJCwAAAA==.Lune:BAABLgAECn8fAAMcAAgJJyBQCADGAgAcAAgJJyBQCADGAgALAAEJhgmfWwArAAAAAA==.',
Lv='Lv:BAACLgAFFH8FAAIkAAMJQBttAQAAAQAkAAMJQBttAQAAAQAuAAQKfygAAiQACAmFIk4AAKsCACQACAmFIk4AAKsCAAAA.',
Ly='Lyeco:BAAALgADCggJFAAAAA==.Lyka:BAAALgAECgYJEAAAAA==.',
['Lì']='Lìghtning:BAABLgAECn8YAAINAAgJ/BCKBgCAAQANAAgJ/BCKBgCAAQAAAA==.',
Ma='Madamemuscle:BAAALgAECgUJDQABLgAECgcJDwAPAAAAAA==.Madoria:BAAALgAECgQJBwAAAA==.Magala:BAAALgADCgcJBwAAAA==.Magebearpig:BAAALgAECgcJEgAAAA==.Magecraftsp:BAACLgAFFH8YAAIdAAcJkRwPAAAlAgAdAAcJkRwPAAAlAgAuAAQKfygABB0ACQkoIvkBAJoDAB0ACQkoIvkBAJoDABwAAglpBRJzAFsAAAsAAgnCAfNQAEkAAAAA.Magehunts:BAAALgAECgIJAgABLgAFFAcJGAAdAJEcAA==.Magice:BAAALgAECgUJCwAAAA==.Magistus:BAACLgAFFH8XAAIlAAgJNBjpAABdAgAlAAgJNBjpAABdAgAuAAQKfyoAAyUACQlBIEAGAPwCACUACQlBIEAGAPwCAAoAAQkOD72DAD8AAAAA.Makeout:BAAALgAECgYJEgAAAA==.Maladra:BAAALgAECgIJAwAAAA==.Malala:BAAALgADCgUJBQAAAA==.Malbraxx:BAAALgAECgEJAQAAAA==.Malyk:BAAALgAECgYJEwAAAA==.Manamontaná:BAAALgAECgQJBgAAAA==.Marcellus:BAAALgADCgMJAwAAAA==.Mariahcarry:BAABLgAECn8WAAMlAAYJbRsvHgDGAQAlAAYJbRsvHgDGAQAKAAQJzA8yFQCyAAABLgAECgYJGgAYAGAhAA==.Marluxio:BAAALgADCgEJAQAAAA==.Marmalady:BAACLgAFFH8XAAIXAAgJ1hyIAACCAgAXAAgJ1hyIAACCAgAuAAQKfyIAAhcACQmtH3oCAEoDABcACQmtH3oCAEoDAAAA.Masa:BAACLgAFFH8YAAIYAAYJrguzAQCtAQAYAAYJrguzAQCtAQAuAAQKfyYAAhgACQmqHBwLAOgCABgACQmqHBwLAOgCAAAA.Masachi:BAAALgAFFAEJAwABLgAFFAYJGAAYAK4LAA==.Masq:BAAALgAECgUJCQAAAA==.Mateyus:BAAALgADCgYJBgAAAA==.Matrebobe:BAAALgAECgcJDwAAAA==.Matt:BAAALgAECgQJBwAAAA==.Mauled:BAAALgADCgcJBwABLgAFFAcJEQAKAHYMAA==.Maulnificent:BAABLgAFFH8GAAIiAAYJiA5gAACOAQAiAAYJiA5gAACOAQABLgAFFAcJEQAKAHYMAA==.Mauly:BAACLgAFFH8RAAIKAAcJdgy6AQDzAQAKAAcJdgy6AQDzAQAuAAQKfyIAAgoACQmDH+AJAOsCAAoACQmDH+AJAOsCAAAA.Mazzoraku:BAAALgADCgYJBgAAAA==.',
Mc='Mcfly:BAAALgAECgYJDgAAAA==.',
Me='Medspriest:BAAALgAECgMJBQAAAA==.Megamam:BAAALgADCgEJAQAAAA==.Meliria:BAAALgAECgcJCgAAAA==.Melodie:BAAALgADCggJCwAAAA==.Mepewpew:BAAALgAECgEJAQAAAA==.Methklock:BAAALgAECgYJDAAAAA==.Methodiction:BAAALgADCgYJBgAAAA==.',
Mi='Microshanks:BAAALgAECgQJBAABLgAECgYJDAAPAAAAAA==.Midgert:BAABLgAECn8WAAIOAAkJERfrSgBWAgAOAAkJEhfrSgBWAgAAAA==.Midisurf:BAABLgAECn8XAAIgAAgJqRE2CwBIAQAgAAgJqRE2CwBIAQAAAA==.Mikehunter:BAEBLgAECn8YAAMSAAgJnRnuFQCIAgASAAgJnRnuFQCIAgATAAYJDxfLUAAKAQABLgAFFAEJAgAPAAAAAA==.Mikewheeler:BAAALgAECgYJCQAAAA==.Miniipope:BAAALgAECgUJBgAAAA==.Mistfit:BAAALgADCgYJFQAAAA==.Misty:BAAALgAECgYJBwAAAA==.',
Mo='Moadebe:BAACLgAFFH8HAAIRAAMJsw2sAQD8AAARAAMJsw2sAQD8AAAuAAQKfyEAAhEACAm2GeoEAMECABEACAm2GeoEAMECAAAA.Moloki:BAAALgADCgYJBgABLgAECgYJCgAPAAAAAA==.Moomonkey:BAAALgAECggJEwAAAA==.Moomoomeadow:BAAALgAECggJEAAAAA==.Morgianax:BAAALgADCgYJBgAAAA==.Morphunter:BAAALgAECgYJEAAAAA==.Moto:BAABLgAECn8dAAIYAAgJ9CGDCgDvAgAYAAgJ9CGDCgDvAgAAAA==.',
My='Myfursona:BAAALgAECgYJDgAAAA==.Mystrali:BAAALgAECgUJCAAAAA==.Mythwenha:BAAALgAECgMJAwABLgAFFAIJBgAkAHkkAA==.',
['Mà']='Màsákins:BAEALgAECgYJBgABLgAFFAcJGwAQAFwbAA==.',
['Må']='Mårs:BAAALgAECgMJBAAAAA==.',
Na='Naelyni:BAAALgAECgEJAgAAAA==.Nagolith:BAAALgADCgUJCAAAAA==.Nagwan:BAAALgADCgYJBgABLgAECggJGwAWANMTAA==.Nakdbeaver:BAAALgADCgYJCQAAAA==.Nalfuria:BAAALgADCgcJDAAAAA==.Naminè:BAABLgAECn8YAAIOAAgJago8GgB3AQAOAAgJago8GgB3AQAAAA==.Naturallife:BAAALgAECgYJCwAAAA==.Nauvi:BAAALgAECgYJCwAAAA==.Navora:BAAALgAECgYJCgAAAA==.Nawtikal:BAAALgAECgYJDgAAAA==.Nazon:BAAALgAECgUJBQAAAA==.',
Ne='Neccroplease:BAAALgADCgcJDAAAAA==.Necrobutcher:BAAALgADCgEJAQAAAA==.Negrumps:BAAALgADCgUJBQAAAA==.Nekthros:BAAALgAECgYJCQAAAA==.Nelune:BAAALgAECgYJCAAAAA==.Neoheals:BAAALgAECgQJBgAAAA==.Nephair:BAACLgAFFH8JAAMSAAQJ0xrxAQBxAQASAAQJ0xrxAQBxAQAaAAEJSQokBwBQAAAuAAQKfxkABBIACAlPHmgeAE8CABIACAlPHmgeAE8CABoABAnWDw0hANMAABMAAwmxCXFoAJwAAAAA.Nepkin:BAAALgAECgYJEQAAAA==.Nerfed:BAAALgAECgMJAwAAAA==.Netsel:BAAALgADCgUJBgAAAA==.Nezdh:BAACLgAFFH8TAAIDAAcJwxsaAABTAgADAAcJwxsaAABTAgAuAAQKfycAAgMACQnpIvwCAJ8DAAMACQnpIvwCAJ8DAAAA.',
Ng='Ngen:BAAALgADCgYJDQAAAA==.',
Ni='Niafix:BAABLgAECn8ZAAICAAgJYBcrIQBKAgACAAgJYBcrIQBKAgAAAA==.Niathiccs:BAAALgAECgIJAgAAAA==.Nightman:BAAALgADCgMJAwAAAA==.Niku:BAAALgADCgIJAgAAAA==.Nivekmage:BAACLgAFFH8FAAIOAAMJWCJ0FwC8AAAOAAMJWCJ0FwC8AAAuAAQKfyMAAg4ACAmQJG4XAB0DAA4ACAmQJG4XAB0DAAAA.',
No='Noobta:BAAALgAECgYJEAAAAA==.Notbpage:BAAALgADCgcJBwABLgAECggJIQAaALcjAA==.Notbrianpage:BAABLgAECn8hAAIaAAgJtyMEAQBlAwAaAAgJtyMEAQBlAwAAAA==.Novsflowerb:BAAALgADCgcJDAAAAA==.',
Nu='Nujobu:BAABLgAECn8XAAIWAAgJqQqhIAAcAQAWAAgJqQqhIAAcAQAAAA==.',
Ny='Nyllamage:BAACLgAFFH8JAAIOAAQJnQ3VLgD7AAAOAAQJnQ3VLgD7AAAuAAQKfyMAAg4ACAlaIn8oANECAA4ACAlaIn8oANECAAAA.Nyllamagetre:BAAALgAECgYJAQABLgAFFAQJCQAOAJ0NAA==.',
Nz='Nzane:BAAALgAECgEJAQAAAA==.',
Oa='Oakgrom:BAAALgADCgIJAgAAAA==.Oathkrates:BAAALgAECgQJBQAAAA==.',
Ob='Oberron:BAAALgAECgYJEwABLgAECgYJGAASAMgiAA==.',
Ok='Okixs:BAAALgAECgMJBAAAAA==.Okra:BAAALgAECgMJBQAAAA==.',
Om='Omiohmyz:BAAALgADCgUJBQAAAA==.Omnisyst:BAAALgAECgYJDQAAAA==.',
On='Onebadshaman:BAEALgADCgMJAwAAAA==.',
Oo='Oogabgooga:BAAALgAECgUJBgAAAA==.',
Or='Oroboros:BAAALgAECgYJCQAAAA==.Ortessa:BAAALgAECgIJAgAAAA==.Orthobro:BAACLgAFFH8HAAIbAAUJoRrMAADCAQAbAAUJoRrMAADCAQAuAAQKfxQAAhsABwkIJRQKAMECABsABwkIJRQKAMECAAEuAAUUBQkPAAUA0SQA.',
Ot='Otterclaw:BAABLgAECn8bAAIYAAcJQh64BQAdAgAYAAcJQh64BQAdAgAAAA==.',
Ov='Ovisha:BAAALgADCgcJBwABLgAFFAgJFwAOAIccAA==.',
Ow='Owo:BAAALgAECgYJBwAAAA==.',
Oz='Ozbrew:BAAALgADCgcJBwABLgAECgYJCwAPAAAAAA==.Ozcane:BAAALgADCgUJCAABLgAECgYJCwAPAAAAAA==.Ozen:BAAALgADCgcJDAABLgAECgYJCwAPAAAAAA==.Ozidan:BAAALgADCgYJBgABLgAECgYJCwAPAAAAAA==.Ozmentation:BAAALgAECgMJBgABLgAECgYJCwAPAAAAAA==.Ozpal:BAAALgAECgYJCwAAAA==.Oztide:BAAALgADCgcJBwABLgAECgYJCwAPAAAAAA==.Oztington:BAAALgAECgEJAQAAAA==.Oztoration:BAAALgADCgcJDwABLgAECgYJCwAPAAAAAA==.',
Pa='Pabzt:BAAALgAECgYJCgAAAA==.Packogum:BAAALgADCgEJAQAAAA==.Pallymon:BAAALgADCgcJCAAAAA==.Pancakeez:BAAALgADCgYJCAAAAA==.Paperpally:BAAALgAECgMJBgABLgAECgUJCwAPAAAAAA==.',
Pb='Pb:BAAALgAECgMJAwAAAA==.',
Pe='Peccavi:BAAALgAECgQJBQAAAA==.Peithagoras:BAAALgADCgYJDgAAAA==.Penelopi:BAABLgAECn8aAAMSAAgJlCDRAQCcAgASAAgJlCDRAQCcAgATAAEJWwYSiQAyAAAAAA==.Penguinia:BAABLgAECn8YAAMFAAgJwhxYMgBZAgAFAAgJwhxYMgBZAgAQAAMJpRTmbwC7AAAAAA==.Pennythegamr:BAAALgAECgcJCgAAAA==.Pensman:BAABLgAECn8bAAIWAAgJ0xPsEACOAQAWAAgJ0xPsEACOAQAAAA==.Pew:BAAALgAECgEJAQAAAA==.',
Ph='Phishfude:BAAALgADCggJDwAAAA==.Phron:BAAALgADCgkJCQAAAA==.Phukitol:BAAALgAECgYJEQAAAA==.',
Pi='Pigeonkick:BAAALgAECgQJBAAAAA==.Pigeonshot:BAAALgAECgQJBAABLgAECgQJBAAPAAAAAA==.Pitukis:BAAALgADCgcJCAAAAA==.',
Pl='Platemate:BAAALgAECgQJBAABLgAFFAQJBwAWAAYUAA==.Plazmah:BAABLgAECn8WAAMgAAgJkwnePQBTAQAgAAgJkwnePQBTAQAhAAIJyQG1kwBNAAAAAA==.Plexadin:BAAALgAECgYJEgAAAA==.Plokoon:BAAALgAECgYJBwAAAA==.',
Po='Poex:BAABLgAECn8UAAIKAAgJ4R9kAQB4AgAKAAgJ4R9kAQB4AgAAAA==.Ponx:BAABLgAECn8VAAImAAcJuApzCABuAQAmAAcJuApzCABuAQAAAA==.Powerhammer:BAAALgAECgMJAwAAAA==.',
Pr='Prepotentè:BAABLgAECn8dAAIDAAgJeRmuDQChAQADAAgJeRmuDQChAQAAAA==.Prepotenté:BAAALgADCgcJDgAAAA==.Priesta:BAABLgAECn8lAAIcAAgJQhaGBQDKAQAcAAgJQhaGBQDKAQAAAA==.Priestfandan:BAABLgAECn8dAAILAAkJ+hvHBgDZAgALAAkJ+hvHBgDZAgAAAA==.',
Pu='Puddingpop:BAAALgAECgMJBQAAAA==.Pudlamental:BAAALgAECgEJAQAAAA==.Puffandra:BAABLgAECn8VAAIOAAYJFgObOwDUAAAOAAYJFgObOwDUAAAAAA==.Punchmonk:BAAALgAECgEJAQAAAA==.Puppet:BAAALgAECgYJEQAAAA==.',
Qu='Quantrank:BAABLgAECn8aAAIbAAgJHR5cAQA8AgAbAAgJHR5cAQA8AgAAAA==.',
Ra='Raazevon:BAAALgADCgUJCwAAAA==.Raddox:BAAALgAFFAEJAQAAAA==.Raei:BAABLgAECn8tAAIhAAkJnBwjBQAeAwAhAAkJnBwjBQAeAwAAAA==.Ragestrasz:BAABLgAECn8bAAIiAAcJkBqrAgCaAQAiAAcJkBqrAgCaAQAAAA==.Raladin:BAAALgAECggJEwAAAA==.Ramanich:BAAALgADCgcJFQAAAA==.Ramchi:BAACLgAFFH8XAAMTAAgJMR8bAAAjAgATAAgJMR8bAAAjAgASAAEJbhULIgBcAAAuAAQKfysAAxMACQmtJdcDAGUDABMACQmtJdcDAGUDABoAAQkAAPsVAAAAAAAA.Ramhorn:BAAALgAECgcJCAAAAA==.Rarfs:BAAALgAECgYJEAAAAA==.Ratatan:BAAALgADCgcJFQAAAA==.Rawbee:BAAALgAECgYJEAAAAA==.Raythe:BAAALgAECgQJBAAAAA==.Razorjudge:BAAALgAECgIJAgABLgAFFAcJGwAXADsPAA==.Razorscales:BAACLgAFFH8bAAIXAAcJOw+kAAD7AQAXAAcJOw+kAAD7AQAuAAQKfykABBcACQnAIYcBAG8DABcACQnAIYcBAG8DAAQABQksHzIoAHwBABUAAQn5BCcKADAAAAAA.',
Re='Reckon:BAAALgAECgQJBwAAAA==.Redestro:BAABLgAECn8bAAIIAAgJ2ROBEACNAQAIAAgJ2ROBEACNAQAAAA==.Reeleaf:BAAALgAECgQJBQAAAA==.Reinadin:BAAALgADCgEJAQAAAA==.Relgeiz:BAAALgAECgEJAQAAAA==.Remlar:BAABLgAECn8jAAQQAAgJyhVlBwDVAQAQAAgJyhVlBwDVAQAFAAMJwQqwAQGSAAAMAAEJ2BhWPQBJAAAAAA==.Renah:BAAALgADCgEJAQAAAA==.',
Ri='Ride:BAAALgADCgcJDAAAAA==.Rixi:BAAALgAECgkJDQAAAA==.Rizzard:BAAALgAECgcJDQAAAA==.',
Rl='Rlyeh:BAAALgADCgIJAgAAAA==.',
Ro='Roadkillz:BAAALgAECgEJAQAAAA==.Robinsouls:BAAALgAECgUJDgAAAA==.Rodan:BAAALgAECgMJAwAAAA==.Roflmaoeggo:BAAALgAECgYJCQAAAA==.Rougarou:BAAALgAECgUJBQAAAA==.Roweana:BAAALgAECgMJBQAAAA==.',
Ru='Ruby:BAAALgADCgMJAwAAAA==.Rudrik:BAAALgADCgcJBwABLgAECgkJLQAhAJwcAA==.Rumblecat:BAAALgADCgQJBAABLgAECggJGgAhAIscAA==.Ruru:BAABLgAECn8mAAIaAAkJVCIoAAASAwAaAAkJVCIoAAASAwAAAA==.',
Ry='Rycana:BAAALgADCgcJCwAAAA==.Rylankneth:BAAALgAECgcJEQAAAA==.',
['Rã']='Rãz:BAAALgADCgkJDQAAAA==.',
['Rì']='Rìçè:BAAALgAECgcJCwABLgAECggJFQAaAF8jAA==.Rìçé:BAABLgAECn8VAAMaAAgJXyMGAQBhAgAaAAgJXyMGAQBhAgATAAUJABwIRQBAAQAAAA==.',
['Rÿ']='Rÿö:BAAALgADCgcJBwAAAA==.',
Sa='Sabelorn:BAAALgAECggJEwAAAA==.Sabrina:BAAALgAECgEJAwAAAA==.Sacredfear:BAABLgAECn8nAAMIAAkJlyJFFQDWAgAIAAkJlyJFFQDWAgAGAAEJAADyYgBIAAAAAA==.Sacredraider:BAAALgAECgYJEQABLgAECgkJJwAIAJciAA==.Sacredshammy:BAAALgAECgQJBgABLgAECgkJJwAIAJciAA==.Sakula:BAAALgADCgMJAwAAAA==.Saraya:BAAALgAECgUJCQABLgAECgUJCgAPAAAAAA==.Satanicsally:BAAALgADCgMJBAAAAA==.Satine:BAABLgAECn8aAAIcAAgJSCCABgDmAgAcAAgJSCCABgDmAgAAAA==.Saturday:BAAALgAECgUJBQAAAA==.Saucywings:BAECLgAFFH8UAAMVAAcJog9bAQCjAQAEAAcJigyfBAC/AQAVAAUJ7Q5bAQCjAQAuAAQKfx4AAxUACAnpI7QBADEDABUACAnpI7QBADEDAAQAAQnqInNXAGIAAAAA.Sayla:BAAALgAECgUJCAAAAA==.Sazerac:BAAALgAECgQJBAAAAA==.',
Sc='Schoust:BAAALgAECgEJAQAAAA==.Scourgeborn:BAAALgAECgEJAQAAAA==.Screwheals:BAABLgAECn8VAAIdAAgJrR1WCwDOAgAdAAgJrR1WCwDOAgABLgAECggJHAAZAHcWAA==.',
Se='Seamaster:BAAALgAECgYJCgAAAA==.Secretions:BAAALgAECgEJAQABLgAECggJGgAWAAceAA==.Selinthe:BAAALgAECgYJDgAAAA==.Sellene:BAECLgAFFH8cAAIYAAcJ7xp7AABqAgAYAAcJ7xp7AABqAgAuAAQKfyAAAhgACAn2I/4JAPUCABgACAn2I/4JAPUCAAAA.Sellina:BAEALgAECgYJBwABLgAFFAcJHAAYAO8aAA==.Senorbang:BAAALgADCgYJBgAAAA==.Sensei:BAAALgAECgcJEQAAAA==.Sep:BAACLgAFFH8FAAIhAAMJIx2RCwAfAQAhAAMJIx2RCwAfAQAuAAQKfygAAiEACAkjIY0CAG8CACEACAkjIY0CAG8CAAAA.Sequence:BAAALgADCgMJAwAAAA==.',
Sh='Shadowflare:BAAALgAECgcJEgAAAA==.Shammoghe:BAAALgAECgEJAQAAAA==.Shaolinhunk:BAAALgAECgQJBwAAAA==.Sharks:BAAALgAECgEJAQAAAA==.Sharp:BAABLgAECn8ZAAIDAAgJOgUIdgBEAQADAAgJOgUIdgBEAQAAAA==.Shawshanks:BAAALgAECgYJDAAAAA==.Shaylagh:BAAALgADCgQJBwAAAA==.Shelandria:BAACLgAFFH8RAAMNAAYJ/xNCAADNAQANAAUJiBVCAADNAQAfAAEJUAzOBQBgAAAuAAQKfy0AAw0ACQnbIzEIAA0DAA0ACQnbIzEIAA0DAB8ABgm3IdEFACgCAAAA.Shiboopy:BAAALgAECgcJDwAAAA==.Shifterella:BAAALgADCgUJBQAAAA==.Shinryuken:BAAALgADCgMJAwAAAA==.Shintook:BAAALgAECgEJAQAAAA==.Shmeggy:BAAALgAECgYJDAAAAA==.Shmegmer:BAABLgAECn8pAAIcAAkJXx7VBQDyAgAcAAkJXx7VBQDyAgAAAA==.Shoda:BAACLgAFFH8bAAMSAAcJ8yA4AADlAQASAAUJEiU4AADlAQATAAYJLhh6CACTAQAuAAQKfykAAxIACQkzJPgAAK4DABIACQkzJPgAAK4DABMACQlFHQIOANECAAAA.Shreker:BAACLgAFFH8FAAIcAAMJPAz0CADYAAAcAAMJPAz0CADYAAAuAAQKfyMAAhwACAkhHlIMAI4CABwACAkhHlIMAI4CAAAA.',
Si='Sidebo:BAAALgAECgEJAQABLgAECgIJAgAPAAAAAA==.Sirn:BAAALgAECgMJAwAAAA==.Sixing:BAAALgAECgkJBwAAAA==.',
Sj='Sjp:BAAALgAECgkJAwAAAA==.Sjpark:BAAALgAECgcJAQAAAA==.Sjue:BAAALgAECgYJCgAAAA==.',
Sk='Skeeto:BAABLgAECn8eAAInAAgJfQ49AwCJAQAnAAgJfQ49AwCJAQAAAA==.Skiplegs:BAABLgAECn8VAAIFAAcJQBNoZgCzAQAFAAcJQBNoZgCzAQAAAA==.Skiron:BAAALgADCgYJAQAAAA==.Skorpeo:BAAALgAECgYJDQAAAA==.Skywise:BAAALgAECgQJBgAAAA==.',
Sl='Slimesmage:BAAALgADCgMJAwAAAA==.Slimxx:BAABLgAECn8iAAMQAAgJDw6TNQCmAQAQAAgJDw6TNQCmAQAFAAUJJBdgLwDfAAAAAA==.Slurms:BAAALgAECgYJEgAAAA==.Slytherin:BAAALgADCgIJAgAAAA==.',
Sm='Smargenrog:BAACLgAFFH8GAAIRAAIJqST3AQDDAAARAAIJqST3AQDDAAAuAAQKfyEAAhEACAmMI10AALACABEACAmMI10AALACAAAA.Smoketreez:BAAALgADCggJCwAAAA==.',
Sn='Snaven:BAAALgAECgYJDwAAAA==.Sneggs:BAAALgAECgIJAgAAAA==.Snipermonkey:BAAALgAECgUJBQAAAA==.',
So='Soapysub:BAAALgADCgEJAQAAAA==.Soiled:BAABLgAECn8cAAIOAAgJXBkSegDeAQAOAAgJXBkSegDeAQAAAA==.Solidshaft:BAAALgAECgYJEAAAAA==.Sopheia:BAAALgADCgEJAQAAAA==.Soul:BAACLgAFFH8FAAIOAAMJLRlMJQAeAQAOAAMJLRlMJQAeAQAuAAQKfyUAAw4ACAnrIsYYABYDAA4ACAl/IsYYABYDACYABQlvIZ4HAIcBAAAA.Soulthemage:BAAALgAECgMJAwAAAA==.Sovereign:BAAALgADCgYJAwAAAA==.',
Sp='Spek:BAACLgAFFH8KAAIhAAUJDR5hBQB2AQAhAAUJDR5hBQB2AQAuAAQKfx8AAyEACAk9JCcGAA8DACEACAk9JCcGAA8DACAAAQn0DqeRACUAAAAA.Spineripper:BAAALgADCgEJAQAAAA==.Spookmage:BAAALgADCgQJBAAAAA==.',
Sq='Squidward:BAACLgAFFH8OAAIDAAUJqR5QBABhAQADAAUJqR5QBABhAQAuAAQKfywAAgMACQl8JP4BALkDAAMACQl8JP4BALkDAAAA.',
Ss='Ssjdoru:BAAALgADCgMJAwAAAA==.',
St='Stackers:BAAALgAECgEJAQAAAA==.Stankiy:BAABLgAECn8XAAMLAAcJ7hhzBgCUAQALAAcJ7hhzBgCUAQAdAAMJYhN2TAClAAAAAA==.Starion:BAAALgAECgEJAQAAAA==.Steakflaps:BAAALgADCgQJBAAAAA==.Stedk:BAABLgAFFH8HAAIjAAMJiB2DCQDuAAAjAAMJhx2DCQDuAAAAAA==.Stinkfinger:BAAALgAECgcJCgAAAA==.Stinkybreath:BAAALgADCgcJCwAAAA==.Stinkysoul:BAAALgAECgYJCgAAAA==.Stormweave:BAAALgAECgMJBgAAAA==.Stygwyggyr:BAABLgAECn8oAAINAAgJ0hjNAQA2AgANAAgJ0hjNAQA2AgAAAA==.',
Su='Subllmation:BAAALgAECgMJBQAAAA==.Succoso:BAEALgAECgEJAQABLgAFFAEJAgAPAAAAAA==.Suebird:BAAALgAECgYJCwABLgAFFAMJBQAcADwMAA==.Sugar:BAAALgAECgIJAgAAAA==.Sugarzcoat:BAABLgAECn8aAAIhAAYJ+R1mCADCAQAhAAYJ+R1mCADCAQAAAA==.Sulphurous:BAABLgAECn8bAAIQAAgJACFOBwD3AgAQAAgJACFOBwD3AgAAAA==.Sunlight:BAAALgADCgYJBwAAAA==.Sup:BAAALgAECgUJBQABLgAECggJIQAaALcjAA==.Supernovi:BAACLgAFFH8XAAIOAAgJhxx3AAASAgAOAAgJhxx3AAASAgAuAAQKfyIAAw4ACQlVJiYEAL4DAA4ACQlVJiYEAL4DACYAAQlTGrkYAFIAAAAA.',
Sw='Swftshadow:BAAALgADCgcJDgAAAA==.Swifty:BAAALgADCgcJAQAAAA==.Swsandy:BAABLgAECn8YAAMcAAgJ1wNJPgBAAQAcAAgJ1wNJPgBAAQAdAAIJwAQ3WgBQAAAAAA==.',
Sy='Sykomike:BAAALgAECgcJDgAAAA==.Sylarria:BAAALgAECgQJCAAAAA==.Syler:BAACLgAFFH8GAAMfAAIJnRaLAwC/AAAfAAIJfxSLAwC/AAANAAEJNA7uGABYAAAuAAQKfyEAAw0ACAnmGa8EALoBAB8ABwneFg4IANgBAA0ACAkKGa8EALoBAAAA.Sylph:BAAALgAECgQJBgAAAA==.Sylveras:BAAALgAECgUJBQAAAA==.Synthètik:BAAALgAECgYJEAAAAA==.Syreal:BAAALgAECgYJDgAAAA==.',
['Sä']='Säcred:BAAALgAECgMJBAABLgAECgkJJwAIAJciAA==.',
Ta='Taine:BAAALgADCgcJCgABLgAECgcJGgAjAMEPAA==.Takatifu:BAAALgADCgMJAwAAAA==.Takkar:BAAALgADCgUJBQAAAA==.Talfiee:BAABLgAECn8iAAIYAAgJ1woXFQAdAQAYAAgJ1woXFQAdAQAAAA==.Taliwis:BAABLgAECn8XAAINAAgJ4g9zCQBAAQANAAgJ4g9zCQBAAQAAAA==.Tallwínd:BAAALgAECgUJDwAAAA==.Talmahakiea:BAAALgADCgIJAgAAAA==.Talphy:BAAALgADCgkJDQAAAA==.Talren:BAABLgAECn8XAAIiAAcJ0RE0EgBPAQAiAAcJ0RE0EgBPAQAAAA==.Talìa:BAAALgAECgUJCgAAAA==.Tanael:BAAALgADCgkJDwAAAA==.Tantalize:BAAALgAECgEJAgAAAA==.Tarasam:BAAALgADCgIJAwAAAA==.Tartlet:BAAALgADCgIJAgAAAA==.Tasari:BAACLgAFFH8bAAIKAAcJTiQHAAByAgAKAAcJTiQHAAByAgAuAAQKfxwAAgoACQnkJPoAALcDAAoACQnkJPoAALcDAAAA.Taylrswftmnd:BAAALgAECgcJDwAAAA==.Taysir:BAAALgAECgMJAwABLgAECgcJGgAjAMEPAA==.',
Te='Teera:BAAALgAECgYJEAAAAA==.Tekain:BAABLgAECn8ZAAIMAAgJ5R+EAwDiAgAMAAgJ5R+EAwDiAgAAAA==.Tenecteplase:BAAALgADCggJDgAAAA==.Tenkinos:BAABLgAECn8aAAMMAAcJnRIsBgAxAQAFAAcJ0Q04egCGAQAMAAYJPxIsBgAxAQAAAA==.Tesia:BAAALgADCgUJBQAAAA==.',
Th='Thanduil:BAAALgADCgEJAQAAAA==.Thedeadlypug:BAAALgAECgcJEgAAAA==.Thehunt:BAAALgAECgYJBgAAAA==.Thehuntsman:BAAALgADCgIJAgAAAA==.Thiccbolts:BAACLgAFFH8JAAMGAAQJww6sBwDzAAAGAAQJww6sBwDzAAAIAAEJ9gPkTwBIAAAuAAQKfxwABAYACAlbIvkDAKgCAAYABwkBI/kDAKgCAAcAAwmpJNQOAEQBAAgAAwm1D5vbAKIAAAAA.Thise:BAAALgAECgMJAwAAAA==.Thunderstud:BAAALgAECgMJBQAAAA==.Thusios:BAAALgAECgcJDgAAAA==.',
Ti='Tiazz:BAAALgADCgcJBwAAAA==.Tibfib:BAAALgADCgYJDAAAAA==.Tichu:BAAALgAECgEJBAAAAA==.Tiekho:BAABLgAECn8cAAIQAAcJZRbsCgCRAQAQAAcJZRbsCgCRAQAAAA==.Tifelia:BAAALgAECgEJAQAAAA==.Tikí:BAACLgAFFH8TAAQVAAcJFRVUAQClAQAVAAUJAhJUAQClAQAEAAQJmQ+9EQDyAAAXAAEJBwdPFwBHAAAuAAQKfygABBUACQmEH2wBAEADABUACQmEH2wBAEADAAQACAn+GvcRAFsCABcAAgmwB209AH8AAAAA.Tizirk:BAAALgADCgQJBAAAAA==.',
Tk='Tkdtwo:BAAALgAECgYJDQAAAA==.',
To='Tombogo:BAABLgAECn8mAAMYAAgJySS+BwARAwAYAAgJySS+BwARAwAeAAgJbiAoBADkAQAAAA==.Tonyz:BAAALgAECgkJEgAAAA==.Torthie:BAACLgAFFH8bAAIOAAcJHCQiAABYAgAOAAcJHCQiAABYAgAuAAQKfykAAg4ACQmyJi4AAA0EAA4ACQmyJi4AAA0EAAAA.Toxaaris:BAABLgAECn8kAAMTAAkJmhJ8GgBSAgATAAkJKRJ8GgBSAgASAAYJbA7SdgACAQAAAA==.',
Tp='Tpa:BAEALgAFFAEJAgAAAA==.',
Tr='Tragikz:BAAALgADCgIJAQAAAA==.Trak:BAAALgAECgYJAQAAAA==.Trent:BAACLgAFFH8IAAIOAAMJ5hT7EQADAQAOAAMJ5hT7EQADAQAuAAQKfyUAAg4ACQmXI88OAFADAA4ACQmXI88OAFADAAAA.Tricksypixie:BAAALgAECgMJBQAAAA==.Tripp:BAABLgAECn8VAAISAAcJNA2nTgB9AQASAAcJNA2nTgB9AQAAAA==.Tronxx:BAAALgADCgUJBwAAAA==.Troxigar:BAABLgAECn8bAAMhAAcJgR7gBQD+AQAhAAcJgR7gBQD+AQAgAAMJORj+bwCDAAAAAA==.Tryx:BAAALgADCgYJBgAAAA==.Trånsformer:BAAALgAECggJCwAAAA==.',
Tu='Tuffskins:BAABLgAECn8aAAIZAAUJawDpPQBeAAAZAAUJawDpPQBeAAAAAA==.Tuon:BAAALgAECgYJDwAAAA==.Turdinnagh:BAABLgAECn8bAAITAAgJMR0AEwCbAgATAAgJMR0AEwCbAgAAAA==.Tuula:BAAALgADCgcJBAABLgAECgcJFQAjAGARAA==.',
Tw='Twistkun:BAABLgAECn8ZAAIYAAcJFiTxDgDBAgAYAAcJFiTxDgDBAgAAAA==.Twistxx:BAAALgAECgEJAQABLgAECgcJGQAYABYkAA==.',
Ty='Tyrinistin:BAABLgAECn8aAAIjAAcJwQ+6HgBRAQAjAAcJwQ+6HgBRAQAAAA==.',
['Tó']='Tóxic:BAAALgADCgUJBQAAAA==.',
Un='Unbearabill:BAABLgAECn8VAAIYAAYJFSBiBgALAgAYAAYJFSBiBgALAgAAAA==.Unholyme:BAAALgADCgQJBAAAAA==.Unjust:BAAALgAECgUJCQAAAA==.Unkickn:BAAALgADCgkJEgAAAA==.Unusualhorse:BAABLgAECn8YAAIRAAgJ1CXVAACJAwARAAgJ1CXVAACJAwAAAA==.',
Va='Vadavaka:BAAALgAECgEJAQAAAA==.Vaerygos:BAAALgADCgEJAQAAAA==.Valedia:BAAALgAECgYJEAAAAA==.Vallenforge:BAAALgADCgcJCQAAAA==.Vallon:BAABLgAECn8XAAIFAAcJFRI9bgCgAQAFAAcJFRI9bgCgAQAAAA==.Vangough:BAAALgAECgIJAgAAAA==.Vaperr:BAAALgAECgQJBwABLgAECggJHgAQALAaAA==.',
Ve='Vealstirke:BAAALgADCgcJBwAAAA==.Veida:BAAALgAECgIJAgAAAA==.Velvetvixen:BAAALgAECgEJAQAAAA==.Venturre:BAAALgAECgcJCgAAAA==.',
Vh='Vhalli:BAABLgAECn8UAAIDAAgJWxz5GwCrAgADAAgJWxz5GwCrAgAAAA==.',
Vi='Viper:BAACLgAFFH8FAAMfAAMJABAoBACwAAAfAAIJRw8oBACwAAANAAEJcxFXGABaAAAuAAQKfygAAw0ACAkxHW8EAMEBAA0ABgmOHW8EAMEBAB8AAwmMHV8RAPIAAAAA.Vira:BAAALgADCgcJBwABLgAECggJGQAJAP0eAA==.Viridity:BAAALgAECgEJAQAAAA==.',
Vl='Vlad:BAABLgAECn8iAAMCAAkJaxilJAAyAgACAAkJnQ2lJAAyAgAZAAgJahlTEQDyAQAAAA==.Vladfurdik:BAAALgADCgEJAQAAAA==.',
Vn='Vnd:BAAALgAECgQJBwAAAA==.',
Vo='Vosslar:BAABLgAECn8YAAIMAAcJRBviDQDoAQAMAAcJRBviDQDoAQAAAA==.Vosslarr:BAAALgAECgEJAQAAAA==.',
Vv='Vvangahrd:BAAALgADCgcJDAAAAA==.Vvarden:BAAALgADCgYJBgAAAA==.',
Vy='Vypra:BAAALgADCgkJCQABLgAECggJGwAlAHcZAA==.',
['Vî']='Vîper:BAAALgAECgUJCAAAAA==.',
Wa='Waarrlockk:BAACLgAFFH8bAAQIAAcJ6R6vBADUAQAIAAUJ5xmvBADUAQAGAAUJ9h4qAgCjAQAHAAEJAADMAwBdAAAuAAQKfykAAwYACQlqJRkDAMgCAAgABwlbI7UUANkCAAYABwmsIRkDAMgCAAAA.Wackyaamom:BAAALgAECgEJAQAAAA==.Wait:BAAALgAECgEJAQAAAA==.Waitrose:BAAALgAECgYJBgAAAA==.Walrusrider:BAAALgADCgkJEQAAAA==.Wassy:BAABLgAECn8YAAIVAAgJ5ST/AABgAwAVAAgJ5ST/AABgAwAAAA==.Wazzabi:BAAALgAECgEJAQAAAA==.',
We='Wealdstone:BAAALgAECgYJDQABLgAECgcJDgAPAAAAAA==.Weauaimer:BAABLgAECn8XAAMTAAgJ3AlaUwD+AAATAAYJnAZaUwD+AAASAAMJsgwFKwCzAAAAAA==.Wemgobyama:BAACLgAFFH8HAAIaAAQJlhbJAAB6AQAaAAQJlhbJAAB6AQAuAAQKfyoAAhoACQnMH/QBAC4DABoACQnMH/QBAC4DAAAA.Wetsox:BAEALgAECgEJAQABLgAFFAEJAQAPAAAAAQ==.',
Wh='Whispy:BAAALgAECgMJBAAAAA==.',
Wi='Windjogger:BAAALgADCgEJAQAAAA==.Wintersedge:BAAALgADCgQJBAAAAA==.Wizartrees:BAAALgADCgcJDgABLgAECgkJJAAVAOsfAA==.Wizsera:BAABLgAECn8kAAMVAAkJ6x8IBADTAgAVAAkJ6x8IBADTAgAEAAIJTRi4UACIAAAAAA==.',
Wo='Wombly:BAAALgAECgcJEgAAAA==.Womboree:BAABLgAECn8fAAMeAAgJ2x+aAQBkAgAeAAgJ2x+aAQBkAgAiAAMJXhcJHwCnAAAAAA==.',
['Wá']='Wáy:BAAALgAECggJCAAAAA==.',
['Wî']='Wîld:BAAALgAECgYJDAAAAA==.',
Xa='Xanatharius:BAAALgAECgQJBQAAAA==.Xanevo:BAAALgADCgMJAwAAAA==.Xazzy:BAAALgAECgQJCgABLgAFFAQJCQASANMaAA==.',
Xe='Xeonhart:BAACLgAFFH8KAAIIAAMJTREBEAD0AAAIAAMJTREBEAD0AAAuAAQKfyEAAwgACQn6HZUeAKACAAgACAk4G5UeAKACAAYABAnjF2smACwBAAAA.',
Xg='Xgunii:BAAALgAECgEJAQABLgAECgYJDgAPAAAAAA==.',
Xi='Xilana:BAAALgAECgEJAQAAAA==.Xiyuun:BAAALgAECgMJAwAAAA==.',
Xt='Xtaasea:BAAALgAECgEJAQAAAA==.',
Ya='Ya:BAAALgAECgcJCQAAAA==.',
Ye='Yellowheal:BAAALgADCgUJBgAAAA==.Yeofl:BAAALgAECgUJCQAAAA==.',
Yi='Yizmit:BAAALgADCgMJAwAAAA==.',
Yk='Ykime:BAAALgAECgYJEwAAAA==.',
Yu='Yukarna:BAABLgAECn8ZAAMfAAgJxhisBQAtAgAfAAcJUBisBQAtAgANAAIJrBRuVACHAAAAAA==.Yukionná:BAABLgAECn8XAAIOAAYJkRraIABQAQAOAAYJkRraIABQAQAAAA==.',
Za='Zaafkiel:BAAALgAECgYJBwAAAA==.Zanez:BAABLgAECn8bAAIMAAgJEwf3HAAjAQAMAAgJEwf3HAAjAQAAAA==.Zappyyboii:BAABLgAECn8jAAIgAAgJHxVfCQBoAQAgAAgJHxVfCQBoAQAAAA==.Zarafie:BAAALgAECgQJCQABLgAECgYJGwAWAFcjAA==.Zarakizz:BAAALgADCgUJBQAAAA==.Zaralji:BAAALgADCgEJAQAAAA==.Zaraphie:BAAALgADCgcJDQABLgAECgYJGwAWAFcjAA==.Zaraphym:BAABLgAECn8bAAIWAAYJVyPFNgBcAgAWAAYJVyPFNgBcAgAAAA==.Zaries:BAABLgAECn8ZAAISAAgJzBIzNwDSAQASAAgJzBIzNwDSAQAAAA==.',
Ze='Zeiya:BAAALgADCgUJBQAAAA==.Zeno:BAAALgAECgcJDQAAAA==.Zephyrine:BAAALgAECgcJEQAAAA==.Zetsuî:BAAALgAECgIJAgAAAA==.Zeyara:BAAALgADCgMJAwAAAA==.',
Zh='Zhu:BAAALgADCgUJCAABLgAECggJGgALAB8YAA==.Zhuzhu:BAABLgAECn8aAAQLAAgJHxhRIQCJAQALAAYJwBhRIQCJAQAcAAcJ6hTBOABZAQAdAAIJLg/DHwA6AAAAAA==.',
Zi='Zigy:BAABLgAECn8nAAMCAAgJOyIjAwAfAgACAAgJuSEjAwAfAgABAAEJKSPVDgBnAAAAAA==.Zimonk:BAAALgADCgcJCwAAAA==.Zimren:BAAALgADCgcJCAAAAA==.Ziralia:BAAALgAECgUJBQAAAA==.',
Zo='Zoinksscoobs:BAAALgADCgcJDwAAAA==.',
Zu='Zugzugbro:BAAALgAECgEJAQABLgAFFAUJDwAFANEkAA==.Zukko:BAABLgAECn8ZAAIoAAgJBR1FAAAoAgAoAAgJBR1FAAAoAgAAAA==.Zulkaris:BAAALgADCgYJBgAAAA==.Zurpzi:BAAALgAECgYJBwAAAA==.',
Zw='Zweitoogood:BAAALgADCgEJAQAAAA==.',
Zy='Zynxbrew:BAABLgAECn8WAAMlAAYJkhm6JACPAQAlAAYJkhm6JACPAQAUAAEJxwz0fgAxAAABLgAECggJHAAjAJMfAA==.',
['Âd']='Âdyvictis:BAACLgAFFH8GAAIEAAMJgA3AEgDpAAAEAAMJgA3AEgDpAAAuAAQKfxYABAQACAlrG8gWACACAAQABwlMHcgWACACABUABwkRFCwVAJgBABcAAgnbDFRAAGgAAAAA.',
['Åk']='Åkuma:BAAALgADCgYJCgABLgAECgUJCAAPAAAAAA==.',
['Êx']='Êxorcerer:BAAALgAECgYJEAAAAA==.',
['Ìl']='Ìl:BAAALgAFFAMJAwAAAA==.',
['Ín']='Ínfinitum:BAAALgAECgQJBAAAAA==.',
['Ðr']='Ðragor:BAAALgADCgYJBgAAAA==.',
['Øs']='Østro:BAAALgAECgcJEwABLgAFFAQJCQASANMaAA==.',
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

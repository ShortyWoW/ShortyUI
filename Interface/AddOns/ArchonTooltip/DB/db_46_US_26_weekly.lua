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

local lookup = {'Mage-Frost','Druid-Restoration','Shaman-Elemental','Unknown-Unknown','Paladin-Protection','Druid-Balance','DemonHunter-Devourer','Evoker-Augmentation','Priest-Holy','Rogue-Subtlety','DeathKnight-Blood','Hunter-BeastMastery','Warrior-Fury','Monk-Windwalker','Paladin-Retribution','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Monk-Brewmaster','DemonHunter-Havoc','Hunter-Marksmanship','Hunter-Survival','Mage-Arcane','Shaman-Restoration','DeathKnight-Unholy','Priest-Shadow','Warrior-Protection','Priest-Discipline','DemonHunter-Vengeance','Paladin-Holy','Monk-Mistweaver','DeathKnight-Frost','Druid-Feral','Warrior-Arms','Shaman-Enhancement','Rogue-Assassination','Druid-Guardian','Evoker-Devastation','Mage-Fire','Evoker-Preservation',}
local provider = {region='US',realm='Azshara',name='US',type='weekly',zone=46,date='2026-05-01',data={Ac='Acethyr:BAAALgADCgkJCgAAAA==.Activase:BAAALgAECgEJAgAAAA==.Activasee:BAABLgAECn8aAAIBAAcJGhQkNwCKAQABAAcJGhQkNwCKAQAAAA==.',
Ad='Adarnyk:BAAALgAECgQJBAAAAA==.Adgavis:BAAALgADCgcJEQAAAA==.Adiena:BAAALgADCggJCAAAAA==.',
Ae='Aelelelos:BAAALgAECgQJBQAAAA==.Aevenyhm:BAABLgAECn8UAAICAAYJkx1NEgD4AQACAAYJkx1NEgD4AQAAAA==.',
Ah='Ahsoul:BAAALgAECgUJCgAAAA==.',
Ak='Akadein:BAAALgAECgcJEwAAAA==.Akimato:BAAALgAECgUJBwAAAA==.Akzulf:BAAALgADCgEJAQAAAA==.',
Al='Alaeul:BAAALgADCgEJAQAAAA==.Alarael:BAAALgADCgcJDAAAAA==.Alenath:BAAALgAECgEJAQAAAA==.Alicelin:BAABLgAECn8rAAIDAAcJaiL9DgC3AgADAAcJaiL9DgC3AgAAAA==.Alicemist:BAAALgAECgUJBQAAAA==.Alicê:BAAALgADCgIJAgAAAA==.Allhallows:BAAALgAECgUJBgAAAA==.Aloko:BAAALgAECgEJAwABLgAECgQJCwAEAAAAAA==.Alqueria:BAAALgAECgEJBQAAAA==.Altarboizyum:BAAALgAECgQJBAABLgAFFAMJCgAFACQTAA==.',
Am='Amanuit:BAAALgADCgUJBQAAAA==.Amoreing:BAAALgADCgEJAQAAAA==.',
An='Andress:BAAALgAECgMJAwAAAA==.Angrylabubu:BAAALgAECgIJAgAAAA==.Anitadrink:BAABLgAECn8WAAMCAAcJ0AdENgD9AAACAAcJ0AdENgD9AAAGAAEJEgF1kgAMAAAAAA==.Anitapiss:BAAALgAECgIJAgAAAA==.Annarri:BAAALgADCgcJDAAAAA==.Anneweaver:BAABLgAECn8jAAIBAAgJKw/CcQDwAQABAAgJKw/CcQDwAQAAAA==.Annihilus:BAABLgAECn8eAAIHAAgJAR7bFwDGAgAHAAgJAR7bFwDGAgAAAA==.Anthorian:BAAALgADCgMJBgAAAA==.',
Ap='Aperture:BAAALgADCgkJCQABLgAFFAIJBQAIAH4QAA==.Apicots:BAABLgAECn8XAAIJAAgJbySLAgBAAwAJAAgJbySLAgBAAwAAAA==.Apipa:BAAALgADCgYJCAABLgAECgQJBQAEAAAAAA==.Apocalypse:BAAALgAECgYJEQAAAA==.Aprilstorms:BAAALgAECgYJEAAAAA==.',
Ar='Arcaneklout:BAAALgADCgEJAQAAAA==.Archalice:BAAALgAECgUJBgAAAA==.Arctik:BAAALgADCgMJAwAAAA==.Ardelas:BAAALgADCgUJAwAAAA==.Ariella:BAAALgADCgEJAQAAAA==.Aris:BAAALgADCgUJBQAAAA==.Artica:BAAALgAECgIJAgAAAA==.Aryn:BAAALgADCgMJAwAAAA==.',
As='Asherabinx:BAAALgADCgEJAQAAAA==.Asztaroth:BAAALgADCggJDgAAAA==.',
At='Athrepos:BAAALgAECgQJBwAAAA==.Atomoonk:BAAALgAECggJEwAAAA==.Atoy:BAAALgAECgMJAwAAAA==.Atreian:BAAALgAECgEJAQAAAA==.Atrejha:BAAALgAECgYJEQAAAA==.Atursix:BAAALgAECgYJBgABLgAECgYJDQAEAAAAAA==.',
Au='Aurethas:BAAALgADCgcJBgAAAA==.Aurithos:BAABLgAECn8QAAIHAAgJTCDFFgDOAgAHAAgJTCDFFgDOAgAAAA==.Aurousdiamo:BAAALgADCgYJBgAAAA==.Aurä:BAABLgAECn8ZAAIBAAgJWBK/KADCAQABAAgJWBK/KADCAQABLgAECgkJFQAHAFkWAA==.Aussilio:BAAALgADCgYJBgAAAA==.',
Av='Avanddraeda:BAAALgAECgQJCAAAAA==.Avariel:BAAALgADCgUJBQABLgAECgUJBQAEAAAAAA==.',
Aw='Awesome:BAAALgAECgIJBAAAAA==.Awesometail:BAAALgADCgYJBgAAAA==.',
Ax='Axul:BAAALgADCgEJAQAAAA==.',
Az='Azazelundead:BAAALgADCgkJHAAAAA==.Azrina:BAABLgAECn8XAAIKAAYJJRI4EwBGAQAKAAYJJRI4EwBGAQAAAA==.',
Ba='Baam:BAAALgAECgEJAQAAAA==.Badboi:BAAALgAECgQJBgAAAA==.Bahnzuul:BAAALgADCgYJBgAAAA==.Baidden:BAAALgADCgcJDgAAAA==.Baldbandit:BAAALgADCgcJBwAAAA==.Balddh:BAAALgAECgYJCwAAAA==.Ballseye:BAAALgAECgIJAgAAAA==.Balsagnatung:BAAALgAECgkJDwABLgAFFAMJBgALANgKAA==.Bananaheals:BAAALgAECgYJCAAAAA==.Bandidos:BAAALgADCggJFwAAAA==.Bapaful:BAAALgADCgYJBgAAAA==.Barkformommy:BAAALgADCgEJAQAAAA==.',
Be='Behealzabub:BAAALgAECgYJDQAAAA==.Behrman:BAAALgADCgYJBgABLgAECgUJBQAEAAAAAA==.Belfposer:BAAALgAECgYJDwAAAA==.Belpepper:BAAALgAFFAIJAgAAAA==.Belwas:BAAALgADCgMJAwAAAA==.Bendelmonte:BAAALgADCgkJHAAAAA==.Bengi:BAAALgADCgYJBwAAAA==.Bentone:BAAALgAECgIJAgAAAA==.Bergerkìng:BAABLgAECn8XAAIMAAgJdhbBFwDVAQAMAAgJdhbBFwDVAQAAAA==.',
Bi='Bibiimbap:BAAALgAECgYJCQABLgAFFAMJBQANAMMdAA==.Bigbigboi:BAAALgADCgMJAwAAAA==.Bigchungus:BAAALgAECgYJBgAAAA==.Bilipmonk:BAABLgAECn8bAAIOAAcJcx0EDAC2AQAOAAcJcx0EDAC2AQAAAA==.Bindinglight:BAABLgAFFH8FAAICAAMJgQeZHAC6AAACAAMJgQeZHAC6AAABLgAFFAMJCAAPAAILAA==.Birdofhermes:BAAALgAECgcJCAAAAA==.Biñx:BAAALgADCgUJCAAAAA==.',
Bl='Blackamus:BAAALgAECgEJAQAAAA==.Blarr:BAAALgAECgQJBAAAAA==.Blastss:BAAALgADCgUJCgAAAA==.Blindvoid:BAAALgAECgUJCgABLgADCgkJEAAEAAAAAA==.Blipilopian:BAAALgADCgMJAwAAAA==.Blockhead:BAAALgAECgUJCQAAAA==.Blueprint:BAAALgADCgUJBQABLgAECgQJBAAEAAAAAA==.',
Bo='Boenur:BAAALgADCgQJBAAAAA==.Bokumbap:BAACLgAFFH8FAAINAAMJwx2HDQAdAQANAAMJwx2HDQAdAQAuAAQKfyAAAg0ACQkdIjIEAGgDAA0ACQkdIjIEAGgDAAAA.Bonesteel:BAAALgAECgYJEAAAAA==.Boomacita:BAAALgAECgMJBgAAAA==.Boonkay:BAAALgAECgMJAwAAAA==.Boonkie:BAAALgAECgEJAQAAAA==.Boonksdeath:BAAALgADCgcJDgAAAA==.Boonksdragon:BAAALgADCgQJBQAAAA==.Borednow:BAAALgADCgUJBQAAAA==.Boreowlis:BAAALgAECgEJAwAAAA==.Boribap:BAAALgAECgYJDAABLgAFFAMJBQANAMMdAA==.Borozon:BAAALgADCggJCAAAAA==.Botoliilii:BAAALgADCgEJAQAAAA==.Boyfriend:BAAALgAECgEJAQAAAA==.',
Br='Bremspal:BAAALgADCgYJBgAAAA==.Brewtangclan:BAAALgAECgYJEgAAAA==.Briarr:BAAALgAECgYJBwAAAA==.Brisanna:BAAALgADCgkJDgAAAA==.Brucethemage:BAAALgAECgEJBAAAAA==.Bruleecreme:BAAALgAECgYJEAAAAA==.',
Bu='Bubbasquez:BAACLgAFFH8GAAIPAAMJwBRAFQAAAQAPAAMJwBRAFQAAAQAuAAQKfxoAAg8ACAmFG+slAI8CAA8ACAmFG+slAI8CAAAA.Bububear:BAAALgAECgYJEQAAAA==.Bugsjugs:BAAALgAECgYJEwAAAA==.Bugszugs:BAAALgADCgMJAwAAAA==.Buonasera:BAAALgADCgMJAwAAAA==.',
['Bà']='Bàng:BAAALgADCgMJAwAAAA==.Bàwlz:BAAALgAECgYJDwAAAA==.',
['Bè']='Bèérsërk:BAAALgADCgMJBAAAAA==.',
Ca='Caelix:BAAALgADCgYJBgAAAA==.Caledor:BAAALgADCgQJBAAAAA==.Camitriel:BAABLgAECn+GAAQQAAkJcyYiAACTAwAQAAgJaSYiAACTAwARAAYJGCanAwCwAQASAAEJeiZuCwByAAAAAA==.Castence:BAAALgADCgIJAgAAAA==.',
Cb='Cbdpen:BAAALgAECgEJAgAAAA==.',
Ce='Ceaserianoma:BAAALgAECgEJAQAAAA==.Celerunas:BAAALgAECgIJAgABLgAECgYJDwAEAAAAAA==.',
Ch='Chadder:BAAALgADCgcJBwAAAA==.Chaunakoala:BAAALgADCgcJBwAAAA==.Cheesydemon:BAAALgADCgYJBgAAAA==.Chubbss:BAAALgAECgcJAgAAAA==.Chudkahlif:BAAALgAECgEJAQAAAA==.Chunkymonk:BAAALgADCgQJBAAAAA==.',
Cl='Classyshammy:BAAALgADCgYJBgAAAA==.Clenzo:BAAALgADCgcJBwAAAA==.Clopendeath:BAAALgADCgMJAQAAAA==.Cloüdyy:BAAALgADCgIJAgAAAA==.Clyemne:BAAALgADCgcJDQABLgADCgkJCQAEAAAAAA==.Clïve:BAAALgADCgYJFAAAAA==.',
Co='Coachjim:BAABLgAECn8WAAIBAAgJhxisRgBkAgABAAgJhxisRgBkAgAAAA==.Cocinegr:BAABLgAECn8gAAQQAAgJ2BXuPAAZAgAQAAgJ2BXuPAAZAgASAAMJVw1rHACPAAARAAIJcQWBWgBfAAAAAA==.Cocinegrö:BAAALgAECgMJAwABLgAECggJIAAQANgVAA==.Coneja:BAAALgAECgcJEgAAAA==.Corazon:BAAALgAECgIJAwAAAA==.',
Cr='Craabman:BAAALgAECgQJBAAAAA==.Craiso:BAABLgAECn8gAAITAAgJxyEiCAAEAwATAAgJxyEiCAAEAwAAAA==.Crasher:BAAALgAECgMJAwAAAA==.Creamyholes:BAAALgADCgYJBgAAAA==.Crimsondawn:BAAALgADCgUJBQAAAA==.Crisnerion:BAAALgADCgcJCQAAAA==.Cryonix:BAAALgADCgQJBAAAAA==.',
Ct='Cthuvian:BAAALgADCgcJCQAAAA==.',
Cu='Cuddlesama:BAAALgADCgkJDwAAAA==.Cudleyknight:BAAALgAECgUJCAAAAA==.Current:BAABLgAECn8ZAAIUAAcJ2wlmGQDSAAAUAAcJ2wlmGQDSAAAAAA==.',
Cy='Cynesd:BAAALgADCgQJBAAAAA==.Cynesh:BAACLgAFFH8eAAQVAAcJdxxbAwAXAgAVAAYJBxhbAwAXAgAWAAQJeBwKCAAYAQAMAAUJKh1cCQAWAQAuAAQKfzAAAxUACQn3JJ0BAKgDABUACQklIp0BAKgDAAwACQkLIfQEAKwCAAAA.Cyrn:BAAALgADCgYJBwAAAA==.',
['Cô']='Cômbustiôn:BAAALgAECgMJBAAAAA==.',
Da='Daddyweaver:BAABLgAECn8mAAIJAAgJRhLaDQDFAQAJAAgJRhLaDQDFAQAAAA==.Daegor:BAAALgAECgMJAwAAAA==.Dagun:BAAALgADCgIJAgAAAA==.Daisylight:BAAALgADCgMJAwAAAA==.Dakyu:BAAALgAECgEJAQAAAA==.Damitbobbi:BAAALgADCgEJAQAAAA==.Danazath:BAAALgAECgYJDAAAAA==.Danjaianka:BAAALgAECgIJAgAAAA==.Dansbouche:BAAALgAECgMJAwAAAA==.Darkerwarior:BAAALgAECgQJBgAAAA==.Darkkarma:BAABLgAECn8WAAIMAAYJgRWfRACdAQAMAAYJgRWfRACdAQAAAA==.Darkzeus:BAAALgAECgQJBwAAAA==.',
Dd='Ddeezn:BAAALgAECgkJDQAAAA==.',
De='Deadorcalive:BAAALgAECgMJAwAAAA==.Deathran:BAABLgAECn8kAAIQAAgJaht6EAAjAgAQAAgJaht6EAAjAgAAAA==.Declined:BAAALgADCgYJBgAAAA==.Decun:BAEALgAECgIJAgAAAA==.Delfine:BAAALgADCgYJBgAAAA==.Delitia:BAAALgAECggJEwAAAA==.Demonikillz:BAAALgADCgUJBwAAAA==.Despott:BAABLgAECn8dAAMBAAgJxxzrFQAsAgABAAgJxxzrFQAsAgAXAAQJXgnMEAC1AAAAAA==.Dethfox:BAAALgAECgUJDQAAAA==.',
Di='Diampiece:BAAALgAFFAEJAQAAAA==.Diiviiniity:BAAALgADCgcJBwAAAA==.Dinellihun:BAAALgAECgQJBQAAAA==.Dioni:BAACLgAFFH8GAAMYAAMJ1BAtFQDiAAAYAAMJ1BAtFQDiAAADAAMJ/QcfHQCHAAAuAAQKfxYAAgMABwlrFrspAMcBAAMABwlrFrspAMcBAAAA.',
Dk='Dkurther:BAAALgADCgYJBgAAAA==.',
Do='Dominants:BAAALgAECgQJCQAAAA==.Doomsdays:BAAALgAECgQJBAAAAA==.Doomsparkle:BAAALgAECgIJAgAAAA==.Dotterup:BAAALgADCgUJBgAAAA==.Dotty:BAAALgADCgMJAwAAAA==.Doublehelix:BAAALgAECggJEwAAAA==.',
Dr='Dracoboch:BAAALgAECgIJAgAAAA==.Draethyra:BAAALgAECgEJAQAAAA==.Draglox:BAAALgADCgMJAwAAAA==.Dragonmaipen:BAAALgAECgYJDgAAAA==.Dragonnwar:BAAALgADCgEJAQAAAA==.Drakaryss:BAAALgADCgEJAQABLgAECggJGgACAEMhAA==.Drakkarth:BAAALgAECgYJEgAAAA==.Dravenm:BAABLgAECn8UAAIBAAYJAAikbQD+AAABAAYJAAikbQD+AAAAAA==.Dreamyblinks:BAAALgADCgIJAgAAAA==.Dremonhunter:BAAALgAECgEJAQAAAA==.Dreyden:BAAALgADCgMJAwAAAA==.Drift:BAAALgADCgMJAwAAAA==.Drunkendrago:BAAALgAECgQJBAAAAA==.',
Du='Duckboss:BAAALgADCgUJBwAAAA==.Dulfrim:BAAALgADCggJDAAAAA==.Dumbest:BAACLgAFFH8HAAIZAAMJMxL5LQDjAAAZAAMJMxL5LQDjAAAuAAQKfxQAAhkABwl/GWBYAOkBABkABwl/GWBYAOkBAAAA.',
['Dè']='Dèmonic:BAACLgAFFH8IAAIQAAIJpwYHPACaAAAQAAIJpwYHPACaAAAuAAQKfysAAhAACQlOF4UnAHMCABAACQlOF4UnAHMCAAAA.',
['Dô']='Dôminants:BAAALgAECgEJAQAAAA==.',
['Dü']='Dürinn:BAAALgADCgQJDQAAAA==.',
Ea='Eastsideeyes:BAAALgAECgEJAQAAAA==.',
Eb='Ebonn:BAAALgADCgcJBwAAAA==.',
Ec='Echobloom:BAAALgAECgYJEAAAAA==.Echolaylee:BAAALgADCgQJBAABLgAECgYJEAAEAAAAAA==.Ectoplasm:BAAALgAECggJDwAAAA==.',
Ed='Eddiedagreat:BAAALgADCgEJAgAAAA==.Edgedemon:BAAALgADCgkJDAAAAA==.',
Ee='Eeny:BAAALgAECgYJCgAAAA==.',
Eh='Ehud:BAAALgAFFAIJAwAAAA==.',
Ei='Eiemonk:BAACLgAFFH8OAAITAAQJGQnNEQALAQATAAQJGQnNEQALAQAuAAQKfx4AAhMACAl0HekaAC0CABMACAl0HekaAC0CAAAA.',
El='Elaratorment:BAAALgADCgYJDAAAAA==.Elastica:BAAALgADCgEJAQAAAA==.Elbori:BAAALgAECgEJAQAAAA==.Eldaral:BAAALgAECgcJBQAAAA==.Elderathion:BAAALgADCgIJAgAAAA==.Elfmas:BAAALgAECgUJCAAAAA==.Elianie:BAAALgADCgQJBAAAAA==.Ellinarilia:BAAALgADCgQJAgAAAA==.Elrithien:BAAALgAECgQJBAAAAA==.',
Em='Emwhun:BAAALgAECgQJCgABLgAECgYJDwAEAAAAAA==.',
En='Entropy:BAAALgAECgYJEAAAAA==.',
Er='Erenore:BAAALgADCgcJCwAAAA==.Eriele:BAAALgADCgQJBAABLgAECgUJBQAEAAAAAA==.',
Es='Eshaia:BAAALgAECgEJAQAAAA==.',
Et='Etalea:BAAALgAECgkJBwAAAA==.',
Ev='Eviaris:BAAALgADCgEJAQAAAA==.',
Fa='Faehuntress:BAAALgAECgMJAwAAAA==.Faenyx:BAAALgAECgMJBQAAAA==.Faesmite:BAACLgAFFH8GAAIJAAMJABdrCQD9AAAJAAMJABdrCQD9AAAuAAQKfyUAAwkACAlDHk8KAAICAAkACAlDHk8KAAICABoABAnUCIYjAN4AAAAA.Fairra:BAAALgAECgYJBwAAAA==.Faithh:BAAALgADCgQJBAAAAA==.Fanggs:BAAALgADCgQJBgAAAA==.Fanobattle:BAAALgADCgkJDgABLgAECgUJDAAEAAAAAA==.Fanorage:BAAALgAECgUJDAAAAA==.Farvajr:BAAALgADCgcJBwAAAA==.Father:BAAALgADCgEJAgAAAA==.',
Fe='Fedusdeletus:BAAALgAECgUJBwAAAA==.Felic:BAAALgADCgUJBQAAAA==.Felixox:BAABLgAECn8VAAIbAAYJWAncKAD5AAAbAAYJWAncKAD5AAAAAA==.Felixxo:BAAALgADCgUJBQAAAA==.Felokali:BAABLgAECn8uAAIcAAkJrBGQEAA4AgAcAAkJrBGQEAA4AgAAAA==.Felrager:BAAALgADCgYJBgAAAA==.Ferocias:BAAALgADCgMJAwAAAA==.Fetty:BAAALgADCgUJCQAAAA==.',
Fi='Fiametta:BAAALgADCgcJEAAAAA==.Filianore:BAAALgAECgEJAgAAAA==.Filthyhobo:BAAALgADCggJCwAAAA==.Finessier:BAABLgAECn8ZAAQVAAcJHx7KKgDTAQAVAAYJPR3KKgDTAQAWAAQJwBGuIADYAAAMAAEJjCIJrwBmAAAAAA==.Fipples:BAABLgAECn8cAAIHAAgJdRxhEwDPAQAHAAgJdRxhEwDPAQAAAA==.Fistasoup:BAAALgAECgEJAQAAAA==.',
Fl='Flaffergan:BAAALgAECgQJBgAAAA==.Florafae:BAAALgAECgIJAgAAAA==.Flugel:BAAALgADCgQJBAAAAA==.',
Fo='Focinnet:BAAALgAECgYJEAAAAA==.Foilwrapped:BAAALgADCgkJDgAAAA==.Four:BAAALgAFFAIJAgAAAA==.Fourform:BAAALgAECgYJDgAAAA==.',
Fr='Fraydknot:BAAALgAECgQJBAAAAA==.Frieren:BAAALgAECgYJEwAAAA==.Frostedfake:BAAALgADCgEJAQAAAA==.Frostybuns:BAAALgADCgYJBgAAAA==.',
Fu='Fustervin:BAAALgAECgMJBgAAAA==.',
Ga='Gaalit:BAAALgAECgQJCwAAAA==.Galaxybone:BAABLgAECn8gAAIZAAcJWSFpFgAGAgAZAAcJWSFpFgAGAgAAAA==.Galer:BAAALgAECgIJAgAAAA==.Galithiri:BAAALgAECgQJBAAAAA==.Gankorade:BAAALgAECgcJEwAAAA==.Ganthani:BAABLgAECn8gAAIJAAgJpBdACwDwAQAJAAgJpBdACwDwAQAAAA==.Ganthanor:BAAALgADCgQJBgAAAA==.Garzett:BAABLgAECn8nAAIGAAgJ0h7TBABnAgAGAAgJ0h7TBABnAgAAAA==.',
Gb='Gbonk:BAAALgADCgUJBQAAAA==.',
Ge='Geisterjäger:BAABLgAECn8mAAMdAAkJYBMEBADAAQAdAAkJYBMEBADAAQAUAAQJMArpHwCXAAAAAA==.Gethalis:BAAALgADCgUJBgAAAA==.',
Gh='Ghouliana:BAAALgAECggJCQABLgAECggJFgAeABojAA==.',
Gi='Giina:BAABLgAECn8kAAIfAAgJMxpmDQDPAQAfAAgJMxpmDQDPAQAAAA==.Girlypopxoxo:BAAALgADCgQJBAAAAA==.',
Go='Gooddik:BAAALgAECgYJBwAAAA==.Gooseburglar:BAAALgAECgMJBAAAAA==.Goosesnacks:BAAALgAECgcJCAAAAA==.Goots:BAAALgADCgcJBwAAAA==.Gordo:BAAALgAECgcJDgAAAA==.Gore:BAAALgADCgUJBQAAAA==.',
Gr='Grhm:BAABLgAECn8kAAMMAAgJaCNoBAC6AgAMAAgJaCNoBAC6AgAVAAEJXwHWmAAdAAAAAA==.Griffin:BAAALgADCgYJCAAAAA==.Griffinlance:BAAALgAECgYJEgAAAA==.Grim:BAACLgAFFH8TAAIZAAcJNxpuAQAeAgAZAAcJNxpuAQAeAgAuAAQKfyAAAxkACQlII3kHAGUDABkACQlII3kHAGUDACAAAgmRIR8PAK4AAAAA.Grimskull:BAAALgADCgEJAQAAAA==.Grimvalde:BAAALgAECgQJBAAAAA==.Grinberryall:BAAALgAECgIJBAAAAA==.Grinshankz:BAAALgADCgcJDgAAAA==.Gromtor:BAAALgAECgcJEwABLgAFFAUJEQAWAK0kAA==.Groos:BAAALgADCgEJAQAAAA==.',
Gu='Gulthor:BAAALgAECgMJAwAAAA==.',
Gw='Gwory:BAABLgAECn8XAAINAAcJsx6NCAAiAgANAAcJsx6NCAAiAgAAAA==.',
['Gá']='Gárp:BAABLgAECn8YAAINAAcJwRByOQDBAQANAAcJwRByOQDBAQAAAA==.',
['Gø']='Gøsa:BAAALgADCgcJDgAAAA==.',
Ha='Haeretik:BAAALgADCgEJAQAAAA==.Hagpag:BAAALgAECgUJEAAAAA==.Hallowmourne:BAABLgAECn8bAAMeAAgJOR4/CwAiAgAeAAgJOR4/CwAiAgAPAAMJZRdY3wDOAAAAAA==.Hanabii:BAAALgADCgQJBAAAAA==.Haramzadi:BAAALgAECgMJBAAAAA==.Harukà:BAABLgAECn8UAAMYAAYJLwYXPwCxAAAYAAYJLwYXPwCxAAADAAMJ8QZAcgB5AAAAAA==.Haven:BAAALgADCgkJCQAAAA==.Hawbinobs:BAABLgAECn8YAAIZAAgJShINYgDNAQAZAAgJShINYgDNAQAAAA==.',
He='Hecâte:BAAALgADCgUJCQAAAA==.Helfon:BAAALgAECgcJEwAAAA==.Helganelf:BAAALgAECgQJBgAAAA==.Hellenria:BAAALgADCggJFQAAAA==.',
Hi='Hibouu:BAAALgADCgYJCQAAAA==.Highlordtron:BAAALgAECgYJEwAAAA==.Hiira:BAAALgADCgYJBwAAAA==.Hinazuki:BAAALgADCgYJCAAAAA==.Hirro:BAABLgAECn8bAAIOAAkJbAb1FABFAQAOAAkJbAb1FABFAQAAAA==.',
Ho='Holycharlie:BAABLgAECn8bAAIFAAgJ2CEWBgCLAgAFAAgJ2CEWBgCLAgAAAA==.Holydudy:BAAALgAECgQJBAAAAA==.Holyely:BAAALgAECgYJEAAAAA==.Holynutzz:BAAALgAECgEJAQAAAA==.Holytrolli:BAAALgAECgQJBAAAAA==.Holyvez:BAAALgAECgEJAgAAAA==.Holyvoids:BAAALgADCgkJEAAAAA==.Holywhit:BAAALgAECgkJBgAAAA==.Hondodk:BAEBLgAECn8UAAILAAcJLyXsCACSAgALAAcJLyXsCACSAgABLgAFFAUJEgAZAA8jAA==.Honeycake:BAAALgADCgcJBwAAAA==.Hoodlum:BAAALgADCgUJBgAAAA==.Hoodlumxdk:BAAALgADCgcJCAAAAA==.Horegan:BAAALgAECgUJCgAAAA==.Hornflames:BAAALgADCgEJAQAAAA==.Hotguymilker:BAAALgAECggJEAAAAA==.Hotnhard:BAAALgAFFAEJAQAAAA==.Howiedewit:BAAALgADCgQJBwAAAA==.Howlupine:BAAALgAECgQJBgAAAA==.',
Hu='Huneybee:BAAALgADCgQJAQAAAA==.',
Hy='Hysterium:BAAALgAECgIJAgAAAA==.',
Ik='Ikki:BAABLgAECn8TAAIHAAkJ6R/rDwD/AgAHAAkJ6R/rDwD/AgAAAA==.',
Il='Iliraelis:BAAALgAECgEJAQAAAA==.Ilirranna:BAAALgAECgcJEQAAAA==.Ilith:BAABLgAECn8XAAIHAAYJqw8bOAADAQAHAAYJqw8bOAADAQAAAA==.Illegal:BAAALgAECgEJAgAAAA==.',
In='Infi:BAACLgAFFH8RAAQVAAYJrRweBAD7AQAVAAYJrRweBAD7AQAMAAEJmA8nOQBUAAAWAAEJXQAAAAAAAAAuAAQKfyMAAxUACAmMJA4GADkDABUACAm5Iw4GADkDABYAAQmbIC0nAF4AAAAA.Initapoop:BAAALgAECgUJBQAAAA==.',
Io='Ioannis:BAAALgAECgQJCQAAAA==.',
Ip='Ipse:BAAALgADCgcJCAAAAA==.',
Ir='Ironstrike:BAAALgAECgMJAwAAAA==.',
Is='Isos:BAABLgAECn8mAAMcAAgJCSXzAgBEAwAcAAgJCSXzAgBEAwAJAAEJPxAffAA4AAAAAA==.Isus:BAAALgADCggJCwAAAA==.',
Iv='Ivander:BAAALgADCgMJAwAAAA==.',
Iw='Iweorn:BAAALgADCgEJAQAAAA==.',
Iy='Iykyk:BAAALgAECgUJBwABLgAECgYJFgAeAMAXAA==.',
Iz='Izuchi:BAAALgADCgcJEQAAAA==.Izzwizz:BAAALgAECgMJBAAAAA==.',
Ja='Jaded:BAABLgAECn8mAAIOAAgJPyFOCAD1AgAOAAgJPyFOCAD1AgAAAA==.Jakersai:BAAALgADCgEJAQAAAA==.Jaksi:BAAALgAECgcJEAAAAA==.Jangutu:BAAALgAECgYJBgAAAA==.Jarlaxl:BAAALgAECgQJBwAAAA==.Jarthh:BAAALgADCgMJAwAAAA==.Javyr:BAAALgAECgMJAwAAAA==.Jaysdruid:BAAALgADCgUJBgAAAA==.Jayskrt:BAAALgADCgEJAgAAAA==.',
Je='Jearik:BAAALgADCgcJCAAAAA==.Jef:BAAALgADCgUJCAAAAA==.Jery:BAAALgADCgYJCQAAAA==.',
Ji='Jijí:BAAALgADCgUJBQAAAA==.Jimmyegs:BAAALgADCgMJAwAAAA==.Jinurzah:BAAALgADCgcJDAAAAA==.',
Jl='Jlnxy:BAABLgAECn8aAAIPAAcJawQfYAD0AAAPAAcJawQfYAD0AAAAAA==.',
Jo='Jokerld:BAAALgAECgEJAQAAAA==.Josiae:BAAALgADCgMJAwAAAA==.',
Jw='Jward:BAAALgAECgYJCQAAAA==.',
Ka='Kaagu:BAAALgADCgQJBAAAAA==.Kadzilak:BAAALgADCgYJEAAAAA==.Kagemika:BAAALgADCgkJGgABLgAECgYJEQAEAAAAAA==.Kaizumie:BAABLgAECn8WAAIeAAgJGiP5CADgAgAeAAgJGiP5CADgAgAAAA==.Kalmojor:BAAALgAECgQJBQAAAA==.Kamina:BAABLgAECn83AAIDAAkJ+x5KBwAfAwADAAkJ+x5KBwAfAwAAAA==.Karlhungus:BAAALgADCgMJAwAAAA==.Karmaniac:BAAALgAECgIJAgAAAA==.Karonet:BAAALgADCgIJAgAAAA==.Karu:BAAALgADCgcJGAAAAA==.Kawaiikutie:BAAALgAECgEJAQAAAA==.Kayarra:BAAALgAECgcJBwABLgAECggJJQAaAJkWAA==.Kayonna:BAAALgADCgcJCAABLgAECggJJQAaAJkWAA==.Kaypop:BAAALgADCgYJEwAAAA==.',
Ke='Keastral:BAAALgAECgQJBQAAAA==.Keeshawn:BAAALgAECgEJAQAAAA==.Keldanis:BAABLgAECn8aAAQMAAgJHBosHgBRAgAMAAgJHBosHgBRAgAWAAMJ9QkWJQCgAAAVAAMJBAVtcgB0AAAAAA==.Kelestrah:BAAALgAECgYJBgAAAA==.Kenbone:BAAALgADCgUJBQAAAA==.Keony:BAABLgAECn8WAAIeAAYJwBfRIQA4AQAeAAYJwBfRIQA4AQAAAA==.Kerthur:BAAALgAECgYJEAAAAA==.',
Kh='Khaalandrun:BAAALgAECgIJAgAAAA==.Khengis:BAAALgADCgMJAwAAAA==.',
Ki='Kiaarly:BAAALgADCgUJBQABLgAECgYJGQAhAJYfAA==.Kieloesh:BAAALgAECgMJBQABLgAECgYJDwAEAAAAAA==.Killamanjara:BAAALgADCgEJAQAAAA==.Killercj:BAAALgADCgMJAwAAAA==.Kirokote:BAAALgADCgIJAgAAAA==.Kitch:BAAALgADCgcJCgAAAA==.Kittyarly:BAABLgAECn8ZAAIhAAYJlh++BwB7AQAhAAYJlh++BwB7AQAAAA==.Kiwee:BAAALgAECgIJAQAAAA==.',
Kj='Kjetil:BAAALgADCgMJAwAAAA==.',
Kl='Kleptoria:BAAALgADCgUJBgAAAA==.Klockwork:BAAALgADCgEJAQAAAA==.',
Kn='Kneeler:BAAALgADCgcJBgAAAA==.',
Ko='Kodeck:BAAALgADCgEJAQAAAA==.Kodokan:BAAALgAECgEJAQAAAA==.Koffey:BAAALgADCgUJBwAAAA==.Kopigyatt:BAAALgADCggJDAABLgAECgcJDgAEAAAAAA==.Koshima:BAABLgAECn8hAAIDAAkJ6RGvCwDfAQADAAkJ6RGvCwDfAQAAAA==.Kozan:BAAALgAECgYJEAAAAA==.',
Kr='Krialin:BAABLgAECn8hAAIPAAgJTiDFDgBKAgAPAAgJTiDFDgBKAgAAAA==.Krimhit:BAAALgAECgUJDAAAAA==.Kronkley:BAABLgAECn8YAAITAAgJABcUHQAaAgATAAgJABcUHQAaAgAAAA==.',
Ku='Kuddel:BAAALgADCgcJCAAAAA==.Kudranne:BAAALgAECgEJAQABLgAECgQJBAAEAAAAAA==.Kugia:BAABLgAECn8bAAICAAgJihhlKgAIAgACAAgJihhlKgAIAgABLgAFFAMJBgAYANQQAA==.Kunthax:BAAALgADCgQJBAAAAA==.Kuorii:BAAALgADCgMJAwAAAA==.Kuraba:BAAALgADCgIJAgAAAA==.Kushtusk:BAAALgAECgUJBgAAAA==.',
Ky='Kynndell:BAAALgADCgcJFQAAAA==.Kyo:BAAALgAECgQJBgAAAA==.',
['Ká']='Kárurosu:BAAALgAECgEJAQAAAA==.',
['Kø']='Køkushibø:BAAALgADCgYJCgAAAA==.',
La='Lanasrin:BAABLgAECn8UAAIPAAcJtCbFDgAYAwAPAAcJtCbFDgAYAwAAAA==.Lanastaul:BAAALgADCgQJBAABLgAFFAIJBQAIAH4QAA==.Lantheiel:BAAALgAECgEJAQAAAA==.Laralana:BAABLgAECn8aAAIMAAcJGwQZTwDgAAAMAAcJGwQZTwDgAAAAAA==.Lazrin:BAAALgADCgIJAgAAAA==.',
Le='Leadzeplin:BAAALgADCgEJAQAAAA==.Leetheal:BAACLgAFFH8JAAIJAAMJ8hTHBwDuAAAJAAMJ8hTHBwDuAAAuAAQKfx0AAwkACQl6IO0DABgDAAkACQl6IO0DABgDABoAAQkoFgFcAEUAAAAA.Lekromancer:BAAALgAECgEJAQAAAA==.Lelethxx:BAAALgAECgUJBgAAAA==.Leraxx:BAAALgAECgEJAQAAAA==.Lerrax:BAAALgAECgIJAQAAAA==.Lesanna:BAABLgAECn8WAAIUAAgJggksLgBbAQAUAAgJggksLgBbAQAAAA==.Lesslie:BAAALgADCggJCAAAAA==.Leåwer:BAAALgAECgQJBAAAAA==.',
Li='Lilbitzz:BAAALgADCgkJCQAAAA==.Lilheal:BAAALgAECgYJBwAAAA==.Lilhussy:BAAALgAECgYJBgAAAA==.Lionël:BAAALgAECgYJEAAAAA==.Lirielle:BAAALgAECgEJAQAAAA==.Lisax:BAAALgADCgMJAwAAAA==.Literocola:BAAALgADCgQJBAAAAA==.Lizbethe:BAABLgAECn8lAAMaAAgJmRZLBwAUAgAaAAgJmRZLBwAUAgAcAAYJpxwxFwDmAQAAAA==.Lizzii:BAAALgADCgMJAwAAAA==.',
Lo='Loltank:BAAALgADCgcJDgAAAA==.Lomrgreenol:BAAALgADCggJCAAAAA==.Lopi:BAABLgAECn8UAAIQAAcJ6APcoAAWAQAQAAcJ6APcoAAWAQAAAA==.Lorshadow:BAAALgADCgcJDQAAAA==.Lorwater:BAAALgADCgcJCQAAAA==.Lorynden:BAAALgAECgQJBQAAAA==.Loubrock:BAAALgAECgcJBwAAAA==.Lovach:BAAALgAECgYJEgAAAA==.Loveinfinity:BAAALgAECgYJEwAAAA==.Lovenox:BAAALgADCgcJBwAAAA==.Lovington:BAAALgAECgMJBgABLgAFFAIJCAAQAKcGAA==.',
Lu='Lu:BAAALgADCgYJBgAAAA==.Luandria:BAAALgAECggJDwAAAA==.Lugostiglitz:BAAALgAECgEJAQAAAA==.Luminas:BAAALgADCgIJAgAAAA==.Lumí:BAAALgAECgEJAQAAAA==.Lunchboss:BAAALgADCgEJAQAAAA==.Lurelune:BAAALgAECgIJAgABLgAFFAIJBQAIAH4QAA==.Luxaria:BAAALgAECgUJBQAAAA==.Luxx:BAAALgADCgQJBAABLgAECgcJJQASAFEfAA==.',
Ly='Lylek:BAAALgAECgYJBgAAAA==.',
Ma='Mackie:BAAALgADCgUJBQABLgAECgQJBAAEAAAAAA==.Madstreak:BAAALgADCgMJAwAAAA==.Maelbeq:BAABLgAECn8XAAIiAAgJohSQBwBEAgAiAAgJohSQBwBEAgAAAA==.Maevelles:BAAALgADCgUJBwAAAA==.Mag:BAAALgADCgUJBQAAAA==.Magewain:BAAALgADCgUJBQAAAA==.Mageypoo:BAABLgAECn8jAAIBAAgJMCQ5BgDUAgABAAgJMCQ5BgDUAgAAAA==.Magicpickle:BAAALgADCgkJEQABLgAECgUJDgAEAAAAAA==.Maine:BAAALgAECgQJBAAAAA==.Malakarth:BAAALgADCgEJAgAAAA==.Malathar:BAAALgAECgUJCAAAAA==.Mallowe:BAAALgADCgMJAwAAAA==.Malson:BAAALgADCgMJBAAAAA==.Marcelxd:BAAALgAECgcJAwAAAA==.Martinjc:BAAALgAECgYJBgAAAA==.Martinlw:BAAALgADCgUJBQAAAA==.Martinte:BAAALgADCgcJAgAAAA==.Masambula:BAAALgADCgEJAQAAAA==.Mavering:BAAALgADCgEJAQAAAA==.Mayaa:BAAALgADCgMJAwAAAA==.Mayaesp:BAAALgADCgMJAwAAAA==.',
Me='Meene:BAAALgAECgYJDAAAAA==.Meepderp:BAAALgAECgcJDgABLgAFFAQJCQAMADAcAA==.Mehaz:BAAALgADCgYJBgAAAA==.Memeep:BAACLgAFFH8JAAIMAAQJMBw7CAAhAQAMAAQJMBw7CAAhAQAuAAQKfykAAwwACQmDJHkAANEDAAwACQmDJHkAANEDABUAAgnYBZB8AFIAAAAA.Meowely:BAAALgADCgYJCgAAAA==.Merry:BAAALgAECgEJAQAAAA==.Meshshift:BAAALgADCgIJAQAAAA==.',
Mi='Miggs:BAAALgADCgEJAQAAAA==.Milfshotz:BAAALgAECggJDgAAAA==.Mimidésy:BAAALgADCgEJAQAAAA==.Minimiyagi:BAAALgAECgEJAQAAAA==.Missbehavior:BAAALgAECgUJBQAAAA==.Misscariina:BAAALgAECgQJBAAAAA==.Missmouthoff:BAABLgAECn8XAAIJAAYJaxgJFQBoAQAJAAYJaxgJFQBoAQAAAA==.Mistralwind:BAAALgADCgEJAQABLgAECgQJBAAEAAAAAA==.Miztärjake:BAAALgADCggJCQAAAA==.Mizzxgummy:BAAALgAECgcJBwAAAA==.',
Mo='Modush:BAAALgADCgUJBQAAAA==.Moldytoast:BAAALgAECgQJAwAAAA==.Monkstaar:BAAALgADCgEJAQAAAA==.Moogan:BAAALgAECgMJAwAAAA==.Mooneyes:BAAALgADCgcJHAAAAA==.Moonfishing:BAACLgAFFH8FAAIBAAIJUgTjVACWAAABAAIJUgTjVACWAAAuAAQKfyEAAgEACAnoDxNIAFYBAAEACAnoDxNIAFYBAAAA.Moonfly:BAABLgAECn8WAAIGAAgJ0BinCAAHAgAGAAgJ0BinCAAHAgAAAA==.Moonmoonpand:BAAALgADCgEJBAAAAA==.Moorea:BAAALgAECgYJCQAAAA==.Morax:BAAALgAECgEJAQAAAA==.Morbidlord:BAAALgADCgcJBwAAAA==.Moubu:BAAALgAECgEJAgAAAA==.Mouton:BAAALgAECgUJCQAAAA==.Mozumi:BAABLgAECn8WAAIQAAYJxx8WIAC1AQAQAAYJxx8WIAC1AQAAAA==.',
Mu='Munn:BAABLgAECn8aAAMBAAgJnRYWTgBNAgABAAgJnRYWTgBNAgAXAAUJHw8sDAAPAQAAAA==.Murag:BAAALgAECgYJEwAAAA==.Mureum:BAAALgADCgEJAQAAAA==.',
['Mä']='Mächtig:BAAALgADCgEJAQAAAA==.',
Na='Nalä:BAAALgADCgUJBAAAAA==.Nammi:BAAALgADCgUJBQAAAA==.Nardorne:BAAALgADCgcJCQAAAA==.Natsumy:BAABLgAECn8WAAIQAAgJiQkCeQBqAQAQAAgJiQkCeQBqAQAAAA==.',
Ne='Nearhammer:BAAALgAECgQJBAAAAA==.Nearsear:BAAALgADCgcJCQAAAA==.Nefariouz:BAAALgAECgkJCQAAAA==.Nervouz:BAAALgAECggJDwAAAA==.Nezarly:BAAALgADCgkJDQAAAA==.',
Ni='Nicky:BAAALgADCgYJBgAAAA==.Nitrøus:BAAALgAECgEJAQAAAA==.',
No='Nobbs:BAAALgAECgMJAwAAAA==.Noctis:BAAALgADCgUJBQAAAA==.Nohhozwa:BAAALgAECgYJDwAAAA==.Nool:BAAALgADCgcJCgAAAA==.Nosaj:BAAALgAECgYJEAAAAA==.Notacow:BAAALgADCgUJAQAAAA==.Notzombie:BAAALgADCgIJAgAAAA==.Noxx:BAAALgAECgUJCAAAAA==.',
Nu='Nualaperafin:BAACLgAFFH8FAAIjAAIJlQ5eBAClAAAjAAIJlQ5eBAClAAAuAAQKfyQAAiMACQlgHPQCAAwDACMACQlgHPQCAAwDAAAA.',
Ny='Nysellia:BAAALgADCgcJCgAAAA==.Nyvara:BAAALgAECgMJAwAAAA==.',
Oc='Ocularagon:BAAALgADCgEJAgAAAA==.',
Ol='Olayro:BAABLgAECn8cAAIQAAgJ1weHOwBBAQAQAAgJ1weHOwBBAQAAAA==.',
Om='Omez:BAAALgAECgIJAgABLgAECgYJBgAEAAAAAA==.Omut:BAAALgAECgcJCQAAAA==.',
On='Onlymilkers:BAAALgADCgEJAQAAAA==.Onsight:BAAALgAECgQJBAAAAA==.',
Oo='Ookabooka:BAAALgAECgEJAQAAAA==.Oopsiedaisy:BAAALgAECgUJCwAAAA==.',
Or='Orangeburn:BAAALgADCgUJBgAAAA==.Orestes:BAAALgAECgYJDgAAAA==.',
Ow='Owillo:BAAALgAECgEJAQAAAA==.',
Pa='Pacadin:BAAALgAECgQJBAAAAA==.Palaguy:BAAALgADCgEJAQAAAA==.Paleie:BAAALgADCgcJDAABLgAFFAQJDgATABkJAA==.Palokarhu:BAAALgADCgIJAgAAAA==.Panterra:BAAALgADCgIJAgABLgADCgQJBAAEAAAAAA==.Papacy:BAAALgADCggJCAAAAA==.Pathran:BAAALgADCgcJDAAAAA==.',
Pe='Peeonsnow:BAAALgAECgYJBgAAAA==.Pellias:BAAALgADCgQJBAAAAA==.Pendrix:BAAALgAECgEJAQAAAA==.Pennerixi:BAAALgAECgkJBAAAAA==.Percival:BAAALgAECgUJBgAAAA==.Perzeval:BAAALgAECgYJEAAAAA==.Perzevel:BAAALgAECgIJBQAAAA==.',
Ph='Pharmacology:BAABLgAECn8ZAAMcAAcJzyGAAwCsAgAcAAcJDCGAAwCsAgAJAAQJNSS+KgCeAQAAAA==.Phénicie:BAAALgADCgYJBwAAAA==.',
Pi='Pieceofchit:BAAALgADCgUJBQAAAA==.',
Pj='Pjb:BAAALgADCgMJAwAAAA==.',
Pl='Plankton:BAAALgAECgQJCgAAAA==.',
Po='Pocholate:BAAALgADCgIJAgAAAA==.Popa:BAAALgAECgEJAQAAAA==.Potatofat:BAAALgADCgUJCgAAAA==.',
Pr='Prathe:BAABLgAECn8ZAAIeAAgJtx31BQCFAgAeAAgJtx31BQCFAgAAAA==.Prayformee:BAAALgADCgYJDAAAAA==.Priestpriest:BAAALgADCgEJAQAAAA==.',
Ps='Psiloci:BAAALgADCgEJAQABLgAECggJHwAGAC8bAA==.Psilocy:BAABLgAECn8fAAIGAAgJLxs2CAAQAgAGAAgJLxs2CAAQAgAAAA==.Pspspspspsps:BAAALgAECggJDgAAAA==.',
Pu='Puddiintoo:BAAALgAECgYJDQAAAA==.Pulsate:BAAALgAECgcJCgAAAA==.Purplechem:BAAALgAECgMJAwAAAA==.',
Qa='Qaucker:BAABLgAECn8iAAMJAAgJzhn9BQBcAgAJAAgJzhn9BQBcAgAcAAYJowZ+MAAcAQAAAA==.',
Qi='Qiz:BAABLgAECn8ZAAIBAAYJpSCVLgCpAQABAAYJpSCVLgCpAQAAAA==.Qizard:BAAALgADCgMJAwAAAA==.',
Qj='Qjq:BAAALgAECgMJAwAAAA==.',
Qu='Quintarite:BAAALgADCgMJAwAAAA==.Quistas:BAAALgAECgMJBAAAAA==.',
Ra='Radlock:BAAALgAECgIJBAAAAA==.Radwaran:BAAALgADCgYJCAAAAA==.Rahma:BAAALgADCgEJAgAAAA==.Raincal:BAABLgAECn8jAAIGAAgJzhY5IAD8AQAGAAgJzhY5IAD8AQAAAA==.Rainsford:BAAALgADCgEJAQAAAA==.Rakchu:BAAALgAECgQJCAAAAA==.Randios:BAAALgADCgMJAwAAAA==.Ranfalem:BAAALgADCgYJCAAAAA==.Rasto:BAABLgAECn8eAAIYAAgJ+QzSHwBmAQAYAAgJ+QzSHwBmAQAAAA==.Rausrunebane:BAAALgADCgIJAwAAAA==.Ravokh:BAAALgADCgYJCgAAAA==.',
Re='Redhand:BAAALgADCgYJBgAAAA==.Regolas:BAAALgADCgcJDQAAAA==.Relentlezz:BAAALgADCgIJAgAAAA==.Relica:BAABLgAECn8YAAIBAAcJ+Q8LUABBAQABAAcJ+Q8LUABBAQAAAA==.Restalan:BAAALgADCgEJAQAAAA==.Revki:BAAALgAECgEJAQAAAA==.Revolvr:BAABLgAECn8kAAIkAAgJnh6RAQAKAwAkAAgJnh6RAQAKAwAAAA==.Reïgn:BAAALgADCgUJBQAAAA==.',
Ri='Ridire:BAAALgAECgcJEQAAAA==.Riptidus:BAACLgAFFH8NAAIYAAQJhhpHCABiAQAYAAQJhhpHCABiAQAuAAQKfyAAAxgACAmKF8EiAA4CABgACAmKF8EiAA4CAAMABQmvD7slAPcAAAAA.Ripzly:BAAALgAECgUJBQAAAA==.Ritalin:BAAALgADCgcJCwAAAA==.Rizzakk:BAAALgADCgcJBAAAAA==.',
Ro='Rogawr:BAAALgADCgEJAQAAAA==.Roguemas:BAAALgADCggJDQAAAA==.Ropeshooter:BAAALgADCgMJAwAAAA==.Roshi:BAAALgADCgIJAgAAAA==.Roxus:BAAALgAECgQJBwAAAA==.',
Ru='Rubberduck:BAAALgADCgYJBgAAAA==.Rudabaga:BAAALgADCgEJAQAAAA==.Rumî:BAABLgAECn8YAAIHAAgJUR1xBgB0AgAHAAgJUR1xBgB0AgAAAA==.Runaf:BAAALgADCgkJCgAAAA==.Runhauf:BAAALgAECgYJBwAAAA==.Runts:BAAALgAECgQJBAAAAA==.',
Ry='Ryuni:BAAALgAECgEJAQAAAA==.',
Sa='Sabellal:BAAALgADCgQJBAAAAA==.Sacredaura:BAAALgAECgMJBAAAAA==.Saegusa:BAAALgADCgkJDAAAAA==.Safedruid:BAAALgADCgUJCAABLgADCgEJAQAEAAAAAA==.Samhain:BAAALgADCgEJAQAAAA==.Samshamwow:BAAALgADCgMJAwABLgAFFAQJCQAhAF8FAA==.Saneseth:BAAALgAECgYJEQAAAA==.Sangodi:BAAALgAECgEJAQAAAA==.Sangomia:BAABLgAFFH8PAAMZAAUJiSWqBAC/AQAZAAQJiSWqBAC/AQALAAEJAAAAIQAAAAAAAA==.Saniblaze:BAAALgADCgQJBwAAAA==.Sanlanesh:BAAALgAECgEJAQAAAA==.Sarrazine:BAAALgAECgQJBgAAAA==.Sasive:BAAALgAECgUJBwAAAA==.Sassbringer:BAAALgAECgIJAgAAAA==.Sayani:BAAALgAECgQJBAAAAA==.',
Sc='Schmall:BAABLgAECn8WAAIDAAcJCxLPGQBEAQADAAcJCxLPGQBEAQAAAA==.Scpypy:BAAALgAECgEJAQAAAA==.Scärlët:BAABLgAECn8kAAIJAAgJQBtYDwBtAgAJAAgJQBtYDwBtAgAAAA==.',
Se='Secrient:BAACLgAFFH8GAAIZAAMJAxJwOQDpAAAZAAMJAxJwOQDpAAAuAAQKfyQAAhkACAnvH5spAJMCABkACAnvH5spAJMCAAAA.Selume:BAAALgADCgcJCAAAAA==.Selvalin:BAAALgADCgIJAgAAAA==.Sevyn:BAAALgAECgEJAwAAAQ==.Sevynari:BAAALgAECgQJBQABLgAECgEJAwAEAAAAAQ==.',
Sh='Shadowmeres:BAAALgAECgEJAQAAAA==.Shamtaar:BAAALgADCgMJAwAAAA==.Shestalker:BAAALgAECgMJAwAAAA==.Shieldheart:BAAALgADCgkJFAAAAA==.Shielpruuf:BAAALgAECgEJAQAAAA==.Shiift:BAAALgAECgcJEwAAAA==.Sholl:BAABLgAECn8XAAMaAAYJsRziDwCOAQAaAAYJsRziDwCOAQAJAAEJUQ9SQAAvAAAAAA==.Sholls:BAABLgAECn8XAAMlAAgJPRnKCQABAgAlAAgJ6RjKCQABAgAhAAMJLBn5EgCrAAAAAA==.Shurpi:BAAALgADCgEJAQAAAA==.Shweener:BAAALgAECgEJAQAAAA==.',
Si='Siandena:BAAALgADCgQJBgAAAA==.Sieguer:BAAALgADCgEJAQAAAA==.Sigismund:BAAALgAECgEJAQAAAA==.Sillygøøsey:BAAALgADCgIJAgAAAA==.Silvaine:BAAALgAECgYJEAAAAA==.Silverdrack:BAAALgAECgEJAQAAAA==.',
Sk='Skalitzath:BAAALgADCgQJAwAAAA==.Skarlax:BAAALgADCgEJAQABLgAECggJFgAeABojAA==.Skkits:BAAALgAECgMJAwAAAA==.Skrunkle:BAAALgAECgYJCQABLgAECggJIQAZAMQRAA==.Skulshooter:BAAALgADCgQJBAAAAA==.',
Sl='Slarhan:BAAALgADCgEJAQAAAA==.Slickshooter:BAAALgADCgMJBQAAAA==.',
Sm='Smibaco:BAAALgAECgEJAQAAAA==.Smushbush:BAABLgAECn8ZAAIPAAcJtyI2NABRAgAPAAcJtyI2NABRAgAAAA==.Smushinbush:BAAALgADCgEJAQABLgAECgcJGQAPALciAA==.Smushyobush:BAAALgAECgcJCgABLgAECgcJGQAPALciAA==.',
Sn='Snicklefritz:BAAALgAECgQJBQABLgAECgYJDgAEAAAAAA==.Snipez:BAAALgADCgMJAwAAAA==.Snortymcdash:BAAALgAECgYJBgAAAA==.',
So='Solclipeus:BAACLgAFFH8KAAMFAAMJJBPWAwC/AAAFAAMJJBPWAwC/AAAPAAMJvAHoKAC8AAAuAAQKfyYAAwUACAmDIuQCAPkCAAUACAmDIuQCAPkCAA8ACAmEEidVAOIBAAAA.Soldh:BAAALgADCgYJBwABLgAFFAMJCgAFACQTAA==.Soulton:BAAALgAECgUJCQAAAA==.Souperscott:BAAALgAECgIJAgAAAA==.Soupz:BAABLgAECn8cAAIPAAYJJCLSGgDpAQAPAAYJJCLSGgDpAQAAAA==.',
Sp='Spaghett:BAABLgAECn8aAAIDAAgJSRgwDwCwAQADAAgJSRgwDwCwAQAAAA==.Sparkev:BAAALgADCgYJDAAAAA==.Spongebobytp:BAAALgADCgYJBwAAAA==.Springburn:BAAALgADCgUJBQAAAA==.',
Sq='Squiddy:BAAALgAECgEJAQAAAA==.',
Sr='Sririacha:BAACLgAFFH8FAAIIAAIJfhBqGQCcAAAIAAIJfhBqGQCcAAAuAAQKfyEAAwgACAl5GIcSAFYCAAgACAl5GIcSAFYCACYABAkUCtMrAL4AAAAA.',
St='Stabbyabby:BAAALgADCggJCAAAAA==.Stabbypickle:BAAALgAECgUJBQABLgAECgUJDgAEAAAAAA==.Statík:BAAALgADCgMJBgAAAA==.Steelbane:BAAALgADCgEJAQAAAA==.Stewy:BAAALgADCgYJCQAAAA==.Strånge:BAABLgAECn8WAAMBAAYJTyGwhADIAQABAAYJTyGwhADIAQAnAAEJdQU4EQAtAAAAAA==.Stìtch:BAABLgAECn86AAMRAAgJKhmwCAA2AgARAAgJ6RewCAA2AgAQAAcJuhanHgC9AQAAAA==.',
Su='Succubetch:BAAALgAECgYJDwAAAA==.Sukiafaunias:BAAALgAECgUJCQAAAA==.Sumirishade:BAAALgAECgIJAgAAAA==.Suoop:BAAALgAECgMJBgAAAA==.Surgeclaw:BAAALgAECgQJCgAAAA==.Suziedh:BAAALgAECgEJAQAAAA==.Suziesham:BAAALgAECgEJAQAAAA==.',
Sw='Switchbladez:BAAALgAECgEJAgAAAA==.',
Sy='Sylendris:BAAALgADCgYJBgAAAA==.',
['Sì']='Sìx:BAAALgAECgYJDQAAAA==.',
['Sï']='Sïxx:BAAALgADCgcJCgABLgAECgYJDQAEAAAAAA==.',
['Sø']='Søÿsåûçê:BAAALgAECgEJAQABLgAECgcJJAATAA8eAA==.',
Ta='Taeril:BAAALgAECgIJAgAAAA==.Taezanx:BAAALgADCgcJBwAAAA==.Tahm:BAABLgAECn8aAAIfAAgJFx4zBwBKAgAfAAgJFx4zBwBKAgAAAA==.Tambel:BAAALgADCgQJBAAAAA==.Tanburn:BAAALgAECgQJDgAAAA==.Tanduinex:BAAALgADCgcJFgAAAA==.Tanrobby:BAAALgADCgUJCQAAAA==.Tanthe:BAAALgADCgYJDAAAAA==.Tapae:BAAALgADCgYJBgAAAA==.Taterrot:BAAALgADCgMJAwAAAA==.Tatsumy:BAAALgAECgUJCwAAAA==.',
Tc='Tcdathirsty:BAAALgAECgMJAwAAAA==.Tcmon:BAABLgAECn8VAAQMAAYJvxIOWgBZAQAMAAUJwRYOWgBZAQAWAAIJAwJ5KwBMAAAVAAMJkgHpfgBKAAAAAA==.',
Te='Teaghan:BAAALgAECgYJEQAAAA==.Teaglizzy:BAACLgAFFH8IAAIPAAMJAgtqIgDsAAAPAAMJAgtqIgDsAAAuAAQKfy0AAg8ACQmQGqsaAMkCAA8ACQmQGqsaAMkCAAAA.Teancm:BAAALgADCgUJBQAAAA==.Tedward:BAAALgADCgQJBAAAAA==.Teehole:BAABLgAECn8VAAIPAAgJpgwndgCOAQAPAAgJpgwndgCOAQAAAA==.Tempert:BAAALgADCgYJBgAAAA==.Termytree:BAAALgADCgcJBwAAAA==.Terorblade:BAAALgAECgIJAgAAAA==.',
Th='Thaetrois:BAAALgADCgMJBAAAAA==.Thanussy:BAABLgAECn8XAAMIAAgJCg1zFABdAQAIAAgJCg1zFABdAQAoAAgJDAW3JgA/AQAAAA==.Thebean:BAAALgADCgQJBAAAAA==.Thebigtuna:BAAALgAECgYJEAAAAA==.Thegodpvp:BAAALgADCgEJAQAAAA==.Theladydruid:BAABLgAECn8lAAMGAAgJSBRADADJAQAGAAgJSBRADADJAQACAAcJWwjyYwAmAQAAAA==.Thestashman:BAAALgAECgcJCAAAAA==.Thexalia:BAAALgAECgQJBAAAAA==.Thordam:BAAALgADCgkJCQAAAA==.Threetee:BAAALgADCgQJCAAAAA==.Threnador:BAAALgAECgQJCQAAAA==.Thyrena:BAAALgADCgMJAwAAAA==.',
Ti='Tierrasbe:BAAALgAECgIJAgAAAA==.Tigerpa:BAAALgAECgkJCwAAAA==.Tinkernut:BAAALgADCgEJAQAAAA==.Tinysmites:BAAALgAECgUJBgAAAA==.Tinythia:BAABLgAECn8lAAIBAAgJeBQcJQDTAQABAAgJeBQcJQDTAQAAAA==.Tioklarus:BAAALgAECgYJEgAAAA==.',
To='Tofulady:BAABLgAECn8kAAIfAAgJ/CO8AQAYAwAfAAgJ/CO8AQAYAwAAAA==.Tornstorm:BAAALgADCgQJBAAAAA==.Torokun:BAAALgADCgUJBwAAAA==.',
Tr='Trashbunny:BAAALgAECgEJAQAAAA==.Traystiria:BAAALgAECgIJAwAAAA==.Trazin:BAAALgADCgEJAQAAAA==.Treesothorny:BAAALgAECgYJDgAAAA==.Triscüit:BAAALgAECgYJDgAAAA==.Truemoosiah:BAAALgAECgYJBgAAAA==.Trébol:BAAALgAECgEJAQAAAA==.Tròll:BAAALgADCgYJBwAAAA==.',
Tu='Turlok:BAAALgAECgYJEAABLgAECgYJDwAEAAAAAA==.',
Tw='Twotwotrain:BAAALgAECgUJCAAAAA==.',
Ty='Tyania:BAAALgADCggJCAABLgAECgEJAQAEAAAAAA==.',
Ul='Ulukki:BAAALgAECgEJAQAAAA==.',
Um='Umbralpickle:BAAALgAECgUJDgAAAA==.',
Un='Uncleiroh:BAAALgAECgYJCwAAAA==.Unhowly:BAACLgAFFH8FAAIZAAMJ7gqoOgDlAAAZAAMJ7gqoOgDlAAAuAAQKfyAAAhkACAklHhcuAIACABkACAklHhcuAIACAAAA.Unrealwushu:BAAALgADCgEJAQAAAA==.Unredeadzomb:BAAALgAECgEJAQAAAA==.Untaintedp:BAAALgADCgEJAQAAAA==.',
Ur='Urgelgru:BAAALgAECggJDgAAAA==.Ursaluna:BAAALgADCgcJBgAAAA==.',
Va='Valhalah:BAAALgADCgUJCgAAAA==.Vapidos:BAAALgAECgUJBgAAAA==.Varlug:BAAALgAECgQJBAAAAA==.Varynxiv:BAAALgAECgIJAgABLgAECgQJBQAEAAAAAA==.Vatica:BAAALgAECgQJBAAAAA==.Vauik:BAABLgAECn8hAAIZAAgJxBGVNABnAQAZAAgJxBGVNABnAQAAAA==.',
Ve='Vealeriadk:BAACLgAFFH8UAAMZAAYJlx/vBQCvAQAZAAUJgR/vBQCvAQALAAQJ7iBrBABmAQAuAAQKfx4ABBkACAm5JY0UAAADABkACAmCJY0UAAADAAsAAwkFJlcgAEIBACAAAQk9IjwTAF4AAAAA.Venatorr:BAAALgADCgcJBwAAAA==.Venvalzhar:BAAALgAECgYJBgAAAA==.Venyym:BAAALgADCgcJCAAAAA==.Veras:BAAALgAECgEJAQAAAA==.Vestammeni:BAAALgAECgEJAgAAAA==.Vexz:BAAALgAECgYJCQABLgAECgcJHgAiANEjAA==.Veyghar:BAAALgAECgIJAgABLgAECgUJBgAEAAAAAA==.',
Vl='Vladmiir:BAAALgAECgcJBwAAAA==.',
Vo='Voidtool:BAAALgADCgIJAgAAAA==.Vosagus:BAAALgAECgEJAgABLgAECggJGAATAAAXAA==.',
['Vê']='Vêzz:BAABLgAECn8oAAIDAAgJERlDHgAdAgADAAgJERlDHgAdAgAAAA==.',
Wc='Wckd:BAABLgAECn8cAAIFAAcJ7ReQEAC9AQAFAAcJ7ReQEAC9AQAAAA==.Wckdwar:BAAALgAECggJDgAAAA==.',
We='Weedvegeta:BAABLgAECn8UAAIBAAgJAhAsLQCvAQABAAgJAhAsLQCvAQAAAA==.Weinerslam:BAAALgAECgEJAgAAAA==.Wells:BAAALgADCgEJAQAAAA==.Wendego:BAAALgADCgMJAwAAAA==.Wernbirn:BAAALgAECggJBQAAAA==.Wetremin:BAAALgAECgYJDQAAAA==.',
Wh='Whiplashh:BAAALgAECgMJBAAAAA==.Whir:BAAALgADCgYJBgAAAA==.Whiry:BAAALgAECgcJEAAAAA==.Whirzy:BAAALgADCgUJBQAAAA==.Whitebeard:BAAALgAECgEJAQAAAA==.Whizkee:BAABLgAECn8ZAAIaAAgJ4RULCgDgAQAaAAgJ4RULCgDgAQAAAA==.',
Wi='Willowpuff:BAAALgAFFAEJAQAAAA==.Wingedlady:BAAALgAECgUJBwAAAA==.Wiskerbiskit:BAAALgAECgYJCgAAAA==.Wiskitbisker:BAACLgAFFH8IAAIZAAMJ0BGqOADsAAAZAAMJ0BGqOADsAAAuAAQKfxYAAhkABwkJGhNKABUCABkABwkJGhNKABUCAAAA.',
Wo='Worldgods:BAAALgADCgkJDQAAAA==.',
Wp='Wpnocturne:BAAALgAECgYJDwAAAA==.',
Wt='Wtfomgbbqftw:BAAALgAECgEJAQAAAA==.',
Wu='Wushu:BAAALgAECgYJEQAAAA==.',
Wy='Wyl:BAAALgAECgUJDgAAAA==.Wyrdfell:BAAALgADCgEJAQAAAA==.',
Xa='Xanthian:BAAALgADCgUJCwAAAA==.Xarrath:BAAALgADCgUJBQAAAA==.',
Xe='Xemro:BAAALgAECgQJBAAAAA==.Xendai:BAAALgAECgQJCwAAAA==.',
Xh='Xhyro:BAAALgAECgUJBQAAAA==.',
Xi='Xiing:BAAALgAECggJEwAAAA==.',
Xn='Xneutron:BAAALgAECgYJEAAAAA==.',
Xt='Xtravagent:BAABLgAECn8WAAMUAAYJXBY7EQArAQAUAAUJthk7EQArAQAHAAUJvwzmjwABAQAAAA==.',
Xy='Xynthris:BAABLgAECn8hAAIVAAgJUhUjBQCtAQAVAAgJUhUjBQCtAQAAAA==.',
Yo='Yonna:BAAALgAECgMJBwAAAA==.Yopps:BAABLgAECn8YAAMQAAgJKhmuKgBlAgAQAAgJKhmuKgBlAgARAAEJjxG9cAA1AAAAAA==.',
Yu='Yunggrazydh:BAAALgADCgcJCAAAAA==.Yurio:BAAALgADCgEJAQAAAA==.Yuunggrazy:BAAALgAECgUJBgAAAA==.',
['Yé']='Yéager:BAABLgAECn8aAAICAAgJQyFzBADjAgACAAgJQyFzBADjAgAAAA==.',
Za='Zabuto:BAABLgAECn8gAAIGAAgJhBvTFQBhAgAGAAgJhBvTFQBhAgAAAA==.Zaevryn:BAAALgAECgEJAwABLgAECgQJCwAEAAAAAA==.Zahäära:BAAALgAECgMJAwAAAA==.Zakaka:BAAALgAECgUJBgAAAA==.Zandrozarath:BAAALgAECgUJBQAAAA==.Zarrtan:BAAALgADCgQJBAAAAA==.Zazprie:BAAALgAECgEJAQAAAA==.',
Ze='Zenpickle:BAAALgADCgYJBgABLgAECgUJDgAEAAAAAA==.Zenrelia:BAAALgADCgEJAgAAAA==.',
Zi='Zicatriz:BAAALgADCggJDgAAAA==.',
Zo='Zongretaboom:BAAALgAECgUJCAAAAA==.Zooss:BAAALgAECgYJEwAAAA==.Zoralias:BAAALgADCgUJBQAAAA==.Zoth:BAAALgADCgcJCAAAAA==.',
Zs='Zshot:BAACLgAFFH8RAAIWAAUJrSSIAACqAQAWAAUJrSSIAACqAQAuAAQKfyIAAxYACQkOJVAAALoDABYACQkNJVAAALoDABUAAQlcIG5+AEwAAAAA.',
Zu='Zuggýzug:BAAALgAECgIJAwAAAA==.Zularam:BAAALgADCgYJBgAAAA==.Zuliks:BAAALgAECgQJCAAAAA==.',
Zx='Zxeý:BAAALgAECgYJDgAAAA==.',
Zy='Zyy:BAAALgADCgcJDQAAAA==.',
['Äb']='Äbracadabruh:BAAALgAECgUJCgAAAA==.',
['Êl']='Êlsa:BAAALgADCgIJAgAAAA==.',
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

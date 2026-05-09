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

local lookup = {'Mage-Frost','Druid-Restoration','Warrior-Fury','Shaman-Elemental','Unknown-Unknown','Paladin-Protection','Druid-Balance','DemonHunter-Devourer','Evoker-Augmentation','Priest-Holy','Rogue-Subtlety','DeathKnight-Blood','Warlock-Demonology','Paladin-Retribution','Hunter-BeastMastery','Monk-Windwalker','Priest-Shadow','Warlock-Destruction','Warlock-Affliction','Mage-Arcane','Monk-Brewmaster','DemonHunter-Havoc','DemonHunter-Vengeance','Hunter-Marksmanship','Hunter-Survival','DeathKnight-Unholy','Shaman-Restoration','Warrior-Protection','Priest-Discipline','Paladin-Holy','Monk-Mistweaver','DeathKnight-Frost','Druid-Guardian','Druid-Feral','Evoker-Devastation','Warrior-Arms','Shaman-Enhancement','Rogue-Assassination','Mage-Fire','Evoker-Preservation',}
local provider = {region='US',realm='Azshara',name='US',type='weekly',zone=46,date='2026-05-08',data={Ac='Acethyr:BAAALgADCgkJCgAAAA==.Activase:BAAALgAECgEJAwAAAA==.Activasee:BAABLgAECn8hAAIBAAkJmBJ8HwAuAgABAAkJmBJ8HwAuAgAAAA==.',
Ad='Adarnyk:BAAALgAECgQJBAAAAA==.Adgavis:BAAALgADCgcJEQAAAA==.Adiena:BAAALgADCggJCAAAAA==.Adroxi:BAAALgAECgEJAQAAAA==.',
Ae='Aelelelos:BAAALgAECgQJBwAAAA==.Aevenyhm:BAABLgAECn8aAAICAAcJYBtxFAAmAgACAAcJYBtxFAAmAgAAAA==.',
Ah='Ahsoul:BAAALgAECgYJCwAAAA==.',
Ak='Akadein:BAABLgAECn8ZAAIDAAcJ3hCLHACEAQADAAcJ3hCLHACEAQAAAA==.Akimato:BAAALgAECgUJBwAAAA==.Akismite:BAAALgAECgQJBAAAAA==.Akzulf:BAAALgADCgEJAQAAAA==.',
Al='Alaeul:BAAALgADCgEJAQAAAA==.Alarael:BAAALgADCgcJDAAAAA==.Alaredria:BAAALgADCgYJCAAAAA==.Alenath:BAAALgAECgEJAQAAAA==.Alicelin:BAABLgAECn8rAAIEAAcJaiL9DgC3AgAEAAcJaiL9DgC3AgAAAA==.Alicemist:BAAALgAECgUJBQAAAA==.Alicia:BAAALgADCgIJAgAAAA==.Alicê:BAAALgADCgIJAgAAAA==.Allhallows:BAAALgAECgUJBgAAAA==.Aloko:BAAALgAECgYJCQABLgAECgQJEAAFAAAAAA==.Alqueria:BAAALgAFFAEJAQAAAA==.Altarboizyum:BAAALgAECgQJBAABLgAFFAMJCgAGACQTAA==.',
Am='Amanuit:BAAALgADCgUJBQAAAA==.Amoreing:BAAALgADCgEJAQAAAA==.',
An='Andress:BAAALgAECgMJAwAAAA==.Angrylabubu:BAAALgAECgIJAgAAAA==.Anitadrink:BAABLgAECn8YAAMCAAcJ0wdoRwD1AAACAAcJ0wdoRwD1AAAHAAEJVQvwVwAzAAAAAA==.Anitapiss:BAAALgAECgQJBwAAAA==.Annarri:BAAALgADCgcJDAAAAA==.Anneweaver:BAABLgAECn8vAAIBAAkJhRebEwB8AgABAAkJhRebEwB8AgAAAA==.Annihilus:BAABLgAECn8jAAIIAAgJAR7XFwDGAgAIAAgJAR7XFwDGAgAAAA==.Anthorian:BAAALgADCgMJBgAAAA==.',
Ap='Aperture:BAAALgADCgkJCQABLgAFFAMJCAAJADUYAA==.Apicots:BAABLgAECn8XAAIKAAgJbySKAgBAAwAKAAgJbySKAgBAAwAAAA==.Apipa:BAAALgADCgYJCAABLgAECgQJBQAFAAAAAA==.Apocalypse:BAAALgAECgYJEQAAAA==.Aprilstorms:BAAALgAECgYJEgAAAA==.',
Aq='Aquana:BAAALgAECgEJAQAAAA==.',
Ar='Arcaneklout:BAAALgADCgEJAQAAAA==.Archalice:BAAALgAECgUJBgAAAA==.Arctik:BAAALgADCgMJAwAAAA==.Ardelas:BAAALgADCgUJAwAAAA==.Ariella:BAAALgADCgEJAQAAAA==.Aris:BAAALgADCgUJBQAAAA==.Artica:BAAALgAECgIJAgAAAA==.Aryn:BAAALgADCgMJAwAAAA==.',
As='Asherabinx:BAAALgADCgEJAQAAAA==.Ashtark:BAAALgADCgkJDAAAAA==.Asztaroth:BAAALgADCggJDgAAAA==.',
At='Athrepos:BAAALgAECgQJBwAAAA==.Atomoonk:BAAALgAECggJEwAAAA==.Atoy:BAAALgAECgMJAwAAAA==.Atreian:BAAALgAECgEJAQAAAA==.Atrejha:BAAALgAECgcJEgAAAA==.Atursix:BAAALgAECggJCQAAAA==.',
Au='Aurethas:BAAALgADCgcJBgAAAA==.Aurithos:BAABLgAECn8QAAIIAAgJTCDBFgDOAgAIAAgJTCDBFgDOAgAAAA==.Aurousdiamo:BAAALgADCgYJBgAAAA==.Aurä:BAABLgAECn8cAAIBAAkJPhKWIwAYAgABAAkJPhKWIwAYAgABLgAECgkJHAAIADAaAA==.Aussilio:BAAALgADCgYJBgAAAA==.',
Av='Avanddraeda:BAAALgAECgQJCQAAAA==.Avariel:BAAALgADCgUJBQABLgAECgUJBQAFAAAAAA==.',
Aw='Awesome:BAAALgAECgIJBAAAAA==.Awesometail:BAAALgADCgYJBgAAAA==.',
Ax='Axul:BAAALgADCgEJAQAAAA==.',
Az='Azazelundead:BAAALgAECgIJAgAAAA==.Azrina:BAABLgAECn8eAAILAAcJbxHxEgB/AQALAAcJbxHxEgB/AQAAAA==.',
Ba='Baam:BAAALgAECgEJAQAAAA==.Badboi:BAAALgAECgQJBwAAAA==.Bahnzuul:BAAALgADCgYJBgAAAA==.Baidden:BAAALgADCgcJDgAAAA==.Baldbandit:BAAALgADCgcJBwAAAA==.Balddh:BAAALgAFFAMJAwAAAA==.Ballseye:BAAALgAECgIJAgAAAA==.Balsagnatung:BAAALgAECgkJDwABLgAFFAMJCAAMAOUKAA==.Bananaheals:BAAALgAECgYJCgAAAA==.Bandidos:BAAALgADCggJHAAAAA==.Bapaful:BAAALgADCgYJCAAAAA==.Barkformommy:BAAALgADCgEJAQAAAA==.',
Be='Behealzabub:BAAALgAECgcJEQAAAA==.Behrman:BAAALgADCgYJBgABLgAECgUJBQAFAAAAAA==.Belfposer:BAABLgAECn8VAAINAAgJpxRKIwDfAQANAAgJpxRKIwDfAQAAAA==.Belpepper:BAABLgAFFH8GAAIOAAQJAAJnNADmAAAOAAQJAAJnNADmAAAAAA==.Belwas:BAAALgADCgMJAwAAAA==.Bendelmonte:BAAALgADCgkJIQAAAA==.Bengi:BAAALgADCgYJBwAAAA==.Bentone:BAAALgAECgIJAgAAAA==.Bergerkìng:BAABLgAECn8XAAIPAAgJdhYiIABEAgAPAAgJdhYiIABEAgAAAA==.',
Bi='Bibiimbap:BAAALgAECgYJEAABLgAFFAMJCAADAIMgAA==.Bigbigboi:BAAALgADCgMJAwAAAA==.Bigchungus:BAAALgAECgYJBgAAAA==.Bilipmonk:BAABLgAECn8jAAIQAAgJXBxgBwBTAgAQAAgJXBxgBwBTAgAAAA==.Bindinglight:BAACLgAFFH8IAAICAAMJiAcUKACxAAACAAMJiAcUKACxAAAuAAQKfxoAAgIACQkcF04OAGwCAAIACQkcF04OAGwCAAEuAAUUAwkLAA4ABwsA.Birdofhermes:BAAALgAECggJCgAAAA==.Biñx:BAAALgAECgMJAwAAAA==.',
Bl='Blackamus:BAAALgAECgEJAQAAAA==.Blarr:BAAALgAECgQJBAAAAA==.Blastss:BAAALgADCgUJCgAAAA==.Blindvoid:BAAALgAECgYJCwABLgADCgkJFwAFAAAAAA==.Blipilopian:BAAALgADCgMJAwAAAA==.Blockhead:BAAALgAECgUJDAAAAA==.Blueprint:BAAALgADCgUJBQABLgAECgEJAQAFAAAAAA==.',
Bo='Boenur:BAAALgADCgQJBAAAAA==.Bokumbap:BAACLgAFFH8IAAIDAAMJgyDkEwATAQADAAMJgyDkEwATAQAuAAQKfyMAAgMACQmXIjAEAGgDAAMACQmXIjAEAGgDAAAA.Bondisius:BAAALgAECgIJAgAAAA==.Bonesteel:BAABLgAECn8WAAINAAYJcAlUYwAIAQANAAYJcAlUYwAIAQAAAA==.Boomacita:BAAALgAECgMJBwAAAA==.Boonkay:BAAALgAECgMJAwAAAA==.Boonkie:BAAALgAECgIJAwAAAA==.Boonksdeath:BAAALgAECgEJAQAAAA==.Boonksdragon:BAAALgADCgcJCwAAAA==.Borednow:BAAALgADCgUJBQAAAA==.Boreowlis:BAAALgAECgMJBQAAAA==.Boribap:BAAALgAECgcJEwABLgAFFAMJCAADAIMgAA==.Borozon:BAAALgADCggJCAAAAA==.Botoliilii:BAAALgADCgEJAQAAAA==.Boyfriend:BAAALgAECgQJBQAAAA==.',
Br='Bremspal:BAAALgADCgYJBgAAAA==.Brewtangclan:BAAALgAECgYJEgAAAA==.Briarr:BAAALgAECgYJBwAAAA==.Brisanna:BAAALgAECgMJAwAAAA==.Brucethemage:BAAALgAECgEJBAAAAA==.Bruleecreme:BAAALgAECgYJEAAAAA==.',
Bu='Bubbasquez:BAACLgAFFH8GAAIOAAMJwBRBFQAAAQAOAAMJwBRBFQAAAQAuAAQKfxoAAg4ACAmFG+glAI8CAA4ACAmFG+glAI8CAAAA.Bububear:BAABLgAECn8XAAIRAAYJVwjqKQD5AAARAAYJVwjqKQD5AAAAAA==.Bugsjugs:BAAALgAECgYJEwAAAA==.Bugszugs:BAAALgADCgMJAwAAAA==.Buonasera:BAAALgADCgMJAwAAAA==.',
['Bà']='Bàng:BAAALgADCgMJAwAAAA==.Bàwlz:BAABLgAECn8VAAIMAAYJgR7sDgCDAQAMAAYJgR7sDgCDAQAAAA==.',
['Bè']='Bèérsërk:BAAALgADCgMJBAAAAA==.',
Ca='Caelix:BAAALgADCgYJBgAAAA==.Caledor:BAAALgADCgQJBAAAAA==.Camitriel:BAABLgAECn+eAAQNAAkJpyYsAACWAwANAAgJpyYsAACWAwASAAYJJiYzBQCtAQATAAEJuiaZEABvAAAAAA==.Castence:BAAALgADCgIJAgAAAA==.',
Cb='Cbdpen:BAAALgAECgEJAgAAAA==.',
Ce='Ceaserianoma:BAAALgAECgEJAQAAAA==.Celerunas:BAAALgAECgIJAgABLgAECgcJEgANAPIUAA==.',
Ch='Chadder:BAAALgADCgcJBwAAAA==.Chaunakoala:BAAALgADCgkJCQAAAA==.Cheesydemon:BAAALgADCgYJBgAAAA==.Chubbss:BAAALgAECgcJAgAAAA==.Chudkahlif:BAAALgAECgEJAQAAAA==.Chunkymonk:BAAALgADCgQJBAAAAA==.',
Cl='Classyshammy:BAAALgADCgYJBgAAAA==.Clenzo:BAAALgAECgEJAQAAAA==.Clopendeath:BAAALgADCgMJAQAAAA==.Cloüdyy:BAAALgAECggJCAAAAA==.Clyemne:BAAALgADCgcJDQABLgADCgkJCQAFAAAAAA==.Clïve:BAAALgADCgYJFAAAAA==.',
Co='Coachjim:BAABLgAECn8WAAIBAAgJhxijRgBkAgABAAgJhxijRgBkAgAAAA==.Cocinegr:BAABLgAECn8gAAQNAAgJ2BXnPAAZAgANAAgJ2BXnPAAZAgATAAMJVw1tHACPAAASAAIJcQV9WgBfAAAAAA==.Cocinegrö:BAAALgAECgMJAwABLgAECggJIAANANgVAA==.Coneja:BAABLgAECn8WAAMBAAgJpg+EQwCdAQABAAgJpg+EQwCdAQAUAAIJcQU2GABXAAAAAA==.Coochia:BAAALgADCgEJAQABLgAECgUJCAAFAAAAAA==.Corazon:BAAALgAECgIJBQAAAA==.',
Cr='Craabman:BAAALgAECgQJBAAAAA==.Craiso:BAABLgAECn8iAAIVAAgJzyH8BQB9AgAVAAgJzyH8BQB9AgAAAA==.Crasher:BAAALgAECgYJDQAAAA==.Creamyholes:BAAALgADCgYJBgAAAA==.Crimsondawn:BAAALgADCgUJBQAAAA==.Crisnerion:BAAALgADCgcJCwAAAA==.Cryonix:BAAALgADCgQJBAAAAA==.',
Ct='Cthuvian:BAAALgADCgcJCQAAAA==.',
Cu='Cuddlesama:BAAALgADCgkJDwAAAA==.Cudleyknight:BAAALgAECgYJEAAAAA==.Current:BAABLgAECn8eAAMWAAkJfAu8EAB5AQAWAAkJDAu8EAB5AQAXAAEJehLCHQA4AAAAAA==.',
Cy='Cynesd:BAAALgADCgQJBAAAAA==.Cynesh:BAACLgAFFH8kAAQPAAgJeCCOAAAdAgAPAAYJDSOOAAAdAgAYAAcJ3xlfAwAXAgAZAAQJfRwYDQAOAQAuAAQKfzIAAxgACQkPJZ0BAKoDABgACQklIp0BAKoDAA8ACQk5IfgIAAQDAAAA.Cyrn:BAAALgADCgcJDgAAAA==.',
Cz='Czerilaa:BAAALgADCgMJAwAAAA==.',
['Cô']='Cômbustiôn:BAAALgAECgMJBAAAAA==.',
Da='Daddyweaver:BAABLgAECn8sAAIKAAkJhREGEADrAQAKAAkJhREGEADrAQAAAA==.Daegor:BAAALgAECgMJBAAAAA==.Dagun:BAAALgADCgIJAgAAAA==.Daiken:BAAALgADCgEJAQAAAA==.Daisylight:BAAALgADCgMJAwAAAA==.Dakyu:BAAALgAECgEJAQAAAA==.Damitbobbi:BAAALgADCgEJAQAAAA==.Danazath:BAAALgAECgYJEgAAAA==.Danjaianka:BAAALgAECgIJAgAAAA==.Dansbouche:BAAALgAECgMJAwAAAA==.Darkerwarior:BAAALgAECgQJBgAAAA==.Darkkarma:BAABLgAECn8cAAIPAAYJyhWgRACdAQAPAAYJyhWgRACdAQAAAA==.Darkzeus:BAAALgAECgQJBwAAAA==.',
Dd='Ddeezn:BAAALgAECgkJDQAAAA==.',
De='Deadorcalive:BAAALgAECgMJAwAAAA==.Deathran:BAABLgAECn8mAAINAAgJxhxbFQA3AgANAAgJxhxbFQA3AgAAAA==.Declined:BAAALgADCgYJBgAAAA==.Decun:BAEALgAECgIJAgABLgAECgQJBwAFAAAAAA==.Delfine:BAAALgADCgYJBgAAAA==.Delitia:BAABLgAECn8UAAIQAAkJwAbhGQBVAQAQAAkJwAbhGQBVAQAAAA==.Demonikillz:BAAALgADCgUJBwAAAA==.Despott:BAABLgAECn8jAAMBAAgJXB7jFwBcAgABAAgJXB7jFwBcAgAUAAQJXQnKEAC1AAAAAA==.Dethfox:BAABLgAECn8YAAIaAAYJZg8kXAAtAQAaAAYJZg8kXAAtAQAAAA==.',
Di='Diampiece:BAAALgAFFAEJAQAAAA==.Diiviiniity:BAAALgAECgUJBQAAAA==.Dinellihun:BAAALgAECgQJBQAAAA==.Dioni:BAACLgAFFH8KAAMbAAQJkBVPEgAwAQAbAAQJkBVPEgAwAQAEAAMJBwgkHADPAAAuAAQKfxcAAwQACAk/F7spAMcBAAQABwlrFrspAMcBABsAAQmDDTSFACkAAAAA.',
Dk='Dkurther:BAAALgADCgYJBgAAAA==.',
Do='Dominants:BAAALgAECgQJCgAAAA==.Doomsdays:BAAALgAECgUJBgAAAA==.Doomsparkle:BAAALgAECgIJAgAAAA==.Dotterup:BAAALgADCgUJBgAAAA==.Dotty:BAAALgADCgMJAwAAAA==.Doublehelix:BAABLgAECn8aAAIOAAgJDxKlNwCgAQAOAAgJDxKlNwCgAQAAAA==.',
Dr='Dracoboch:BAAALgAECgIJAgAAAA==.Draethyra:BAAALgAECgEJAQAAAA==.Draglox:BAAALgADCgMJAwAAAA==.Dragonballs:BAAALgAECgEJAQABLgAECgIJBQAFAAAAAA==.Dragonmaipen:BAAALgAECgYJDgAAAA==.Dragonnwar:BAAALgADCgEJAQAAAA==.Drakaryss:BAAALgAECgUJBQABLgAECgkJHQACANcfAA==.Drakkarth:BAAALgAECgYJEgAAAA==.Drakoga:BAAALgADCgYJBgAAAA==.Dravenm:BAABLgAECn8bAAIBAAcJuAfXcAAvAQABAAcJuAfXcAAvAQAAAA==.Dreamyblinks:BAAALgADCgIJAgAAAA==.Dremonhunter:BAAALgAECgEJAQAAAA==.Dreyden:BAAALgADCgMJAwAAAA==.Drift:BAAALgADCgMJAwAAAA==.Drunkendrago:BAAALgAECgQJBAAAAA==.',
Du='Duckboss:BAAALgADCgUJBwAAAA==.Dulfrim:BAAALgADCggJDAAAAA==.Dumbest:BAACLgAFFH8HAAIaAAMJMxL/LQDjAAAaAAMJMxL/LQDjAAAuAAQKfxQAAhoABwl/GVVYAOkBABoABwl/GVVYAOkBAAAA.Dups:BAAALgAECggJCAAAAA==.Durgen:BAAALgADCgMJAwAAAA==.',
['Dè']='Dèmonic:BAACLgAFFH8IAAINAAIJpwYWPACaAAANAAIJpwYWPACaAAAuAAQKfy8AAg0ACQkQGIMnAHMCAA0ACQkQGIMnAHMCAAAA.',
['Dô']='Dôminants:BAAALgAECgEJAQAAAA==.',
['Dü']='Dürinn:BAAALgADCgQJDQAAAA==.',
Ea='Eastsideeyes:BAAALgAECgEJAgAAAA==.',
Eb='Ebonn:BAAALgADCgcJBwAAAA==.',
Ec='Echobloom:BAAALgAECgYJEwAAAA==.Echolaylee:BAAALgADCgQJBAABLgAECgYJEwAFAAAAAA==.Ectoplasm:BAAALgAECggJEwAAAA==.',
Ed='Eddiedagreat:BAAALgADCgEJAgAAAA==.Edgedemon:BAAALgAECgIJAgAAAA==.',
Ee='Eeny:BAAALgAECgYJCgAAAA==.',
Eh='Ehud:BAAALgAFFAIJAwAAAA==.',
Ei='Eiemonk:BAACLgAFFH8TAAIVAAUJ+xYqEAA3AQAVAAUJ+xYqEAA3AQAuAAQKfyYAAhUACAmcIcAGAGkCABUACAmcIcAGAGkCAAAA.',
El='Elaratorment:BAAALgADCgYJEgAAAA==.Elastica:BAAALgADCgEJAQAAAA==.Elbori:BAAALgAECgIJAwAAAA==.Eldaral:BAAALgAECgcJBQAAAA==.Elderathion:BAAALgADCgIJAgAAAA==.Elfmas:BAAALgAECgUJCAAAAA==.Elianie:BAAALgADCgQJBAAAAA==.Ellinarilia:BAAALgADCgQJAgAAAA==.Elrithien:BAAALgAECgQJBAAAAA==.',
Em='Emwhun:BAABLgAECn8WAAIcAAcJrQ/9EQBEAQAcAAcJrQ/9EQBEAQABLgAECgcJEgANAPIUAA==.',
En='Entropy:BAABLgAECn8YAAIIAAgJHA61NwBXAQAIAAgJHA61NwBXAQAAAA==.',
Er='Erenore:BAAALgADCgcJCwAAAA==.Eriele:BAAALgADCgQJBAABLgAECgUJBQAFAAAAAA==.',
Es='Eshaia:BAAALgAECgEJAQAAAA==.',
Et='Etalea:BAAALgAECgkJBwAAAA==.',
Ev='Eviaris:BAAALgADCgEJAQAAAA==.Evolintent:BAAALgAECgkJBAAAAA==.',
Fa='Faehuntress:BAAALgAECgMJAwAAAA==.Faenyx:BAAALgAECgQJCAAAAA==.Faesmite:BAACLgAFFH8KAAIKAAQJzBPUCAA3AQAKAAQJzBPUCAA3AQAuAAQKfysAAwoACAlDHugMABcCAAoACAlDHugMABcCABEABAkhEoQmABABAAAA.Fairra:BAAALgAECgcJCAAAAA==.Faithh:BAAALgADCgQJBAAAAA==.Fanggs:BAAALgADCgQJBgAAAA==.Fanobattle:BAAALgAECgMJAwABLgAECgUJDAAFAAAAAA==.Fanorage:BAAALgAECgUJDAAAAA==.Farvajr:BAAALgADCgcJBwAAAA==.Father:BAAALgADCgEJAgAAAA==.',
Fe='Fedusdeletus:BAAALgAECgUJBwAAAA==.Felic:BAAALgADCgUJBQAAAA==.Felixox:BAABLgAECn8VAAIcAAYJWAncKAD5AAAcAAYJWAncKAD5AAAAAA==.Felixxo:BAAALgADCgUJBQAAAA==.Felokali:BAABLgAECn8uAAIdAAkJrBGMEAA4AgAdAAkJrBGMEAA4AgAAAA==.Felrager:BAAALgADCgYJBgAAAA==.Ferocias:BAAALgAECgYJBgAAAA==.Fetty:BAAALgADCgUJCQAAAA==.',
Fi='Fiametta:BAAALgADCgcJEAAAAA==.Filianore:BAAALgAECgEJAgAAAA==.Filthyhobo:BAAALgADCggJEAAAAA==.Finessier:BAABLgAECn8ZAAQYAAcJHx42KwDTAQAYAAYJPR02KwDTAQAZAAQJwBGtIADYAAAPAAEJjCIJrwBmAAAAAA==.Fipples:BAABLgAECn8kAAIIAAgJgB0GFwAEAgAIAAgJgB0GFwAEAgAAAA==.Fistasoup:BAAALgAECgEJAQAAAA==.',
Fl='Flaffergan:BAAALgAECgQJBgAAAA==.Florafae:BAAALgAECgQJBAAAAA==.Flugel:BAAALgADCgYJBgAAAA==.',
Fo='Focinnet:BAAALgAECgYJEgAAAA==.Foilwrapped:BAAALgADCgkJDgAAAA==.Four:BAAALgAFFAIJBAAAAA==.Fourform:BAAALgAECgYJDgAAAA==.',
Fr='Fraydknot:BAAALgAECgQJBAAAAA==.Frianna:BAAALgAECgIJAgAAAA==.Frieren:BAAALgAECgYJEwAAAA==.Frostedfake:BAAALgADCgEJAQAAAA==.Frostybuns:BAAALgADCgYJBgAAAA==.',
Fu='Fustervin:BAAALgAECgMJBgAAAA==.',
Ga='Gaalit:BAAALgAECgQJDwAAAA==.Galaxybone:BAABLgAECn8hAAIaAAcJWSGxJADwAQAaAAcJWSGxJADwAQAAAA==.Galer:BAAALgAECgMJBAAAAA==.Galithiri:BAAALgAECgUJBQABLgAECgEJAQAFAAAAAA==.Gankorade:BAAALgAECgcJEwAAAA==.Ganthani:BAABLgAECn8mAAIKAAgJkBkICwA2AgAKAAgJkBkICwA2AgAAAA==.Ganthanor:BAAALgADCgcJDQAAAA==.Garzett:BAACLgAFFH8FAAIHAAIJ4BADHwCbAAAHAAIJ4BADHwCbAAAuAAQKfy8AAgcACAlAIHwFAJACAAcACAlAIHwFAJACAAAA.',
Gb='Gbonk:BAAALgADCgUJBQAAAA==.',
Ge='Geisterjäger:BAABLgAECn8tAAQXAAkJYRPxBQCmAQAXAAkJYRPxBQCmAQAWAAQJhApGKQCWAAAIAAIJMAXBqABIAAAAAA==.Gethalis:BAAALgADCgUJBgAAAA==.',
Gh='Ghouliana:BAAALgAECgkJEQABLgAECggJFgAeABojAA==.',
Gi='Giina:BAACLgAFFH8HAAIfAAMJBhX9FQDWAAAfAAMJBhX9FQDWAAAuAAQKfygAAh8ACAkbGzcPAPkBAB8ACAkbGzcPAPkBAAAA.Girlypopxoxo:BAAALgADCgQJBAAAAA==.',
Gl='Glizyglober:BAAALgAECgQJAgABLgAFFAMJCwAOAAcLAA==.',
Go='Gooddik:BAAALgAECgcJCAAAAA==.Gooseburglar:BAAALgAECgkJDQAAAA==.Goosesnacks:BAAALgAECgcJCwAAAA==.Goots:BAAALgADCgkJCQAAAA==.Gordo:BAAALgAECggJEQAAAA==.Gore:BAAALgADCgUJBQAAAA==.',
Gr='Greath:BAAALgAECgEJAQABLgAECgcJGAADANgeAA==.Greengobblin:BAAALgADCgEJAQABLgADCgEJAQAFAAAAAA==.Grhm:BAABLgAECn8oAAMPAAkJ+yPHAgAZAwAPAAkJ+yPHAgAZAwAYAAEJXwHimAAdAAAAAA==.Griffin:BAAALgADCgYJCAAAAA==.Griffinlance:BAABLgAECn8ZAAIZAAYJzQ/CFwBNAQAZAAYJzQ/CFwBNAQAAAA==.Grim:BAACLgAFFH8WAAIaAAgJ/xdwAQAeAgAaAAgJ/xdwAQAeAgAuAAQKfyAAAxoACQlII3sHAGUDABoACQlII3sHAGUDACAAAgmRISAPAK4AAAAA.Grimskull:BAAALgADCgEJAQAAAA==.Grimvalde:BAAALgAECgQJCAAAAA==.Grinberryall:BAAALgAECgIJBAAAAA==.Grinshankz:BAAALgAECgEJAQAAAA==.Gromtor:BAAALgAECgcJEwABLgAFFAYJEgAZAK0jAA==.Groos:BAAALgADCgEJAQAAAA==.Groöt:BAAALgADCgUJBQAAAA==.',
Gu='Gulthor:BAAALgAECgUJCgAAAA==.',
Gw='Gwory:BAABLgAECn8YAAIDAAcJ2B7IDQAQAgADAAcJ2B7IDQAQAgAAAA==.',
['Gá']='Gárp:BAABLgAECn8YAAIDAAcJwRBwOQDBAQADAAcJwRBwOQDBAQAAAA==.',
['Gø']='Gøsa:BAAALgADCgcJDgAAAA==.',
Ha='Hachipatxi:BAAALgAECgYJBgABLgADCgYJDQAFAAAAAA==.Haeretik:BAAALgADCgEJAQAAAA==.Hagpag:BAAALgAECgUJEAAAAA==.Hallowmourne:BAABLgAECn8fAAMeAAgJOR5yEgADAgAeAAgJOR5yEgADAgAOAAUJ9xRPcgAIAQAAAA==.Hanabii:BAAALgADCgQJBAAAAA==.Haramzadi:BAAALgAECgMJBAAAAA==.Harukà:BAABLgAECn8bAAMbAAcJ5QtJSwDSAAAbAAYJYAdJSwDSAAAEAAQJRQY3cgB5AAAAAA==.Hatxo:BAAALgADCgIJAgABLgADCgYJDQAFAAAAAA==.Haven:BAAALgADCgkJCQAAAA==.Hawbinobs:BAABLgAECn8aAAIaAAkJ7xFOSgBcAQAaAAkJ7xFOSgBcAQAAAA==.',
He='Hecâte:BAAALgADCgUJCQAAAA==.Helfon:BAABLgAECn8WAAIWAAgJKCGEEgBGAgAWAAgJKCGEEgBGAgAAAA==.Helganelf:BAAALgAECgQJBgAAAA==.Hellenria:BAAALgADCggJFQAAAA==.',
Hi='Hibouu:BAAALgADCgYJCQAAAA==.Highlordtron:BAABLgAECn8VAAQTAAYJ1BVTFADrAAANAAYJlRVVjQA+AQATAAQJTBBTFADrAAASAAEJzRRZaABAAAAAAA==.Hiira:BAAALgADCgYJBwAAAA==.Hinazuki:BAAALgADCgYJCAAAAA==.Hirro:BAABLgAECn8kAAIQAAkJcgheGABiAQAQAAkJcgheGABiAQAAAA==.',
Ho='Holycharlie:BAABLgAECn8fAAIGAAgJDiNdAwBsAgAGAAgJDiNdAwBsAgAAAA==.Holydudy:BAAALgAECgQJBAAAAA==.Holyely:BAABLgAECn8YAAIGAAgJgh/vAgB+AgAGAAgJgh/vAgB+AgAAAA==.Holynutzz:BAAALgAECgUJBgAAAA==.Holytrolli:BAAALgAECgUJCAAAAA==.Holyvez:BAAALgAECgEJAgAAAA==.Holyvoids:BAAALgADCgkJFwAAAA==.Holywhit:BAAALgAECgkJBgAAAA==.Hondodk:BAECLgAFFH8FAAIMAAMJFBveDQAAAQAMAAMJFBveDQAAAQAuAAQKfxYAAwwACAnvI+sIAJICAAwABwk6JesIAJICABoAAQksHKfNAFIAAAEuAAUUBgkYABoAtCEA.Honeycake:BAAALgADCgcJBwAAAA==.Hoodlum:BAAALgADCgUJBgAAAA==.Hoodlumxdk:BAAALgADCgcJCQAAAA==.Hoodyxlock:BAAALgADCgIJAgAAAA==.Horegan:BAAALgAECgUJCgAAAA==.Hornflames:BAAALgADCgEJAQAAAA==.Hotguymilker:BAAALgAECggJEAAAAA==.Hotnhard:BAAALgAFFAEJAwAAAA==.Howiedewit:BAAALgADCgQJBwAAAA==.Howlupine:BAAALgAECgYJDAAAAA==.',
Hu='Huneybee:BAAALgADCgQJAQAAAA==.',
Hy='Hysterium:BAAALgAECgIJAgAAAA==.',
Ic='Icomeyourun:BAAALgADCgIJAQAAAA==.',
Ik='Ikki:BAABLgAECn8TAAIIAAkJ6R/nDwD/AgAIAAkJ6R/nDwD/AgAAAA==.',
Il='Iliraelis:BAAALgAECgEJAgAAAA==.Ilirranna:BAAALgAECgcJEwAAAA==.Ilith:BAABLgAECn8jAAIIAAYJVBC6TQAPAQAIAAYJVBC6TQAPAQAAAA==.Illegal:BAAALgAECgEJAwAAAA==.',
In='Inallan:BAAALgADCgYJBgAAAA==.Infi:BAACLgAFFH8SAAQYAAYJuBwiBAD7AQAYAAYJrRwiBAD7AQAZAAEJoSEoGQBjAAAPAAEJnA/dTABSAAAuAAQKfyUAAxgACQnTJBgGADsDABgACAm5IxgGADsDABkAAgmxIzUlAM8AAAAA.Initapoop:BAAALgAECgYJCQAAAA==.',
Io='Ioannis:BAAALgAECgUJDgAAAA==.',
Ip='Ipse:BAAALgAECgIJAgAAAA==.',
Ir='Ironstrike:BAAALgAECgMJAwAAAA==.',
Is='Isos:BAABLgAECn8mAAMdAAgJCSXzAgBEAwAdAAgJCSXzAgBEAwAKAAEJPxAhfAA4AAAAAA==.Isus:BAAALgADCggJCwAAAA==.',
Iv='Ivander:BAAALgADCgMJAwAAAA==.',
Iw='Iweorn:BAAALgADCgEJAQAAAA==.',
Iy='Iykyk:BAAALgAECgUJBwABLgAECgcJFwAeAAoXAA==.',
Iz='Izuchi:BAAALgADCgcJEQAAAA==.Izzwizz:BAAALgAECgMJBAAAAA==.',
Ja='Jablowmi:BAAALgADCgYJBgAAAA==.Jaded:BAABLgAECn8oAAIQAAgJPyFNCAD1AgAQAAgJPyFNCAD1AgAAAA==.Jakersai:BAAALgADCgEJAQAAAA==.Jaksi:BAAALgAECgcJEAAAAA==.Jangutu:BAAALgAECgYJBgAAAA==.Jarlaxl:BAAALgAECgQJBwAAAA==.Jarthh:BAAALgADCgMJAwAAAA==.Javyr:BAAALgAECgYJCQAAAA==.Jaysdruid:BAAALgADCgUJBgAAAA==.Jayskrt:BAAALgADCgEJAgAAAA==.',
Je='Jearik:BAAALgADCgcJCAAAAA==.Jef:BAAALgADCgUJCAAAAA==.Jery:BAAALgADCgYJCQAAAA==.',
Ji='Jijí:BAAALgADCgUJBQAAAA==.Jimmyegs:BAAALgADCgMJAwAAAA==.Jinurzah:BAAALgADCgcJDAAAAA==.',
Jl='Jlnxy:BAABLgAECn8cAAIOAAgJSAQCawAXAQAOAAgJSAQCawAXAQAAAA==.',
Jo='Jokerld:BAAALgAECgEJAQAAAA==.Josiae:BAAALgADCgMJAwAAAA==.',
Jw='Jward:BAAALgAECgYJDwAAAA==.',
Ka='Kaagu:BAAALgADCgQJBAAAAA==.Kadzilak:BAAALgADCgYJEAAAAA==.Kagemika:BAAALgAECgEJAQABLgAECgcJEgAFAAAAAA==.Kaizumie:BAABLgAECn8WAAIeAAgJGiP6CADgAgAeAAgJGiP6CADgAgAAAA==.Kalmojor:BAAALgAECgQJCAAAAA==.Kamina:BAACLgAFFH8FAAIEAAMJKRiTFgD5AAAEAAMJKRiTFgD5AAAuAAQKfzgAAgQACQn7HkgHAB8DAAQACQn7HkgHAB8DAAAA.Karlhungus:BAAALgADCgMJAwAAAA==.Karmaniac:BAAALgAECgIJAgAAAA==.Karonet:BAAALgADCgIJAgAAAA==.Karu:BAAALgADCgcJGAAAAA==.Kawaiikutie:BAAALgAECgEJAQAAAA==.Kayarra:BAAALgAECgcJBwABLgAECggJJgARAH4XAA==.Kayonna:BAAALgADCgcJCAABLgAECggJJgARAH4XAA==.Kaypop:BAAALgADCgYJEwAAAA==.',
Ke='Keastral:BAAALgAECgUJBgAAAA==.Keeshawn:BAAALgAECgIJAgAAAA==.Keldanis:BAABLgAECn8cAAQPAAgJgB4rHgBQAgAPAAgJgB4rHgBQAgAZAAMJ9QkVJQCgAAAYAAMJBAWCcgB0AAAAAA==.Kelestrah:BAAALgAECgYJBgAAAA==.Kenbone:BAAALgADCgUJBQAAAA==.Keony:BAABLgAECn8XAAIeAAcJChelIgByAQAeAAcJChelIgByAQAAAA==.Kerthur:BAABLgAECn8VAAIhAAYJkwkxGwCBAAAhAAYJkwkxGwCBAAAAAA==.Ketuajawa:BAAALgAECgYJCQAAAA==.',
Kh='Khaalandrun:BAAALgAECgUJBgAAAA==.Khengis:BAAALgADCgcJCAAAAA==.',
Ki='Kiaarly:BAAALgADCgUJBQABLgAECggJHAAiAPMeAA==.Kieloesh:BAAALgAECgQJCgABLgAECgcJEgANAPIUAA==.Killamanjara:BAAALgADCgEJAQAAAA==.Killercj:BAAALgADCgMJAwAAAA==.Kirokote:BAAALgADCgIJAgAAAA==.Kitch:BAAALgADCgcJCgAAAA==.Kittyarly:BAABLgAECn8cAAIiAAgJ8x6SAgCAAgAiAAgJ8x6SAgCAAgAAAA==.Kiwee:BAAALgAECgIJAQAAAA==.Kiwi:BAAALgADCgcJBwABLgAECgYJEwAFAAAAAA==.',
Kj='Kjetil:BAAALgADCgMJAwAAAA==.',
Kl='Kleptoria:BAAALgAECgEJAQAAAA==.Klockwork:BAAALgADCgEJAQAAAA==.',
Kn='Kneeler:BAAALgADCgcJBgAAAA==.',
Ko='Kodaa:BAAALgADCgIJAgAAAA==.Kodeck:BAAALgADCgcJCAAAAA==.Kodokan:BAAALgAECgEJAQAAAA==.Koffey:BAAALgADCgUJBwAAAA==.Kopigyatt:BAAALgADCggJDAABLgAECgcJEAAFAAAAAA==.Koshima:BAABLgAECn8jAAIEAAkJahKmEADcAQAEAAkJahKmEADcAQAAAA==.Kozan:BAABLgAECn8YAAMJAAgJbA1dHQBUAQAJAAgJOAtdHQBUAQAjAAUJlg7XDgCbAAAAAA==.',
Kr='Krialin:BAABLgAECn8qAAIOAAkJCB9oBgDoAgAOAAkJCB9oBgDoAgAAAA==.Krimhit:BAAALgAECgUJDwAAAA==.Kronkley:BAABLgAECn8YAAIVAAgJABcWHQAaAgAVAAgJABcWHQAaAgABLgAFFAIJAgAFAAAAAA==.',
Ku='Kuddel:BAAALgADCgcJCAAAAA==.Kudranne:BAAALgAECgIJBAABLgAECgEJAQAFAAAAAA==.Kugia:BAABLgAECn8fAAICAAgJmRnIHgDOAQACAAgJmRnIHgDOAQABLgAFFAQJCgAbAJAVAA==.Kunthax:BAAALgADCgQJBAAAAA==.Kuori:BAAALgAECgEJAQAAAA==.Kuorii:BAAALgADCgMJAwABLgAECgEJAQAFAAAAAA==.Kuraba:BAAALgADCgIJAgAAAA==.Kushtusk:BAAALgAECgUJBgAAAA==.',
Ky='Kynndell:BAAALgADCgcJFgAAAA==.Kyo:BAAALgAECgQJCgAAAA==.',
['Ká']='Kárurosu:BAAALgAECgEJAQAAAA==.',
['Kø']='Køkushibø:BAAALgADCgYJCgAAAA==.',
La='Lanasrin:BAABLgAECn8UAAIOAAcJtCbCDgAYAwAOAAcJtCbCDgAYAwAAAA==.Lanastaul:BAAALgADCgQJBAABLgAFFAMJCAAJADUYAA==.Lantheiel:BAAALgAECgEJAgAAAA==.Laralana:BAABLgAECn8iAAIPAAgJKQeWPwBQAQAPAAgJKQeWPwBQAQAAAA==.Lazrin:BAAALgADCgIJAgAAAA==.',
Le='Leadzeplin:BAAALgADCgMJBAAAAA==.Leetheal:BAACLgAFFH8JAAIKAAMJ8hTJBwDuAAAKAAMJ8hTJBwDuAAAuAAQKfx0AAwoACQl6IOwDABgDAAoACQl6IOwDABgDABEAAQkoFv9bAEUAAAAA.Lekromancer:BAAALgAECgEJAQAAAA==.Lelethxx:BAAALgAECgUJCAAAAA==.Leraxx:BAAALgAECgEJAQAAAA==.Lerrax:BAAALgAECgIJAQAAAA==.Lesanna:BAABLgAECn8dAAIWAAgJ1QsdFQBCAQAWAAgJ1QsdFQBCAQAAAA==.Lesslie:BAAALgADCggJCAAAAA==.Leåwer:BAAALgAECgQJBAAAAA==.',
Li='Lilbitzz:BAAALgADCgkJCQAAAA==.Lilheal:BAAALgAECgYJCwAAAA==.Lilhussy:BAAALgAECgYJBgAAAA==.Lionël:BAABLgAECn8YAAIeAAgJlx6lBgCyAgAeAAgJlx6lBgCyAgAAAA==.Lirielle:BAAALgAECgEJAQAAAA==.Lisax:BAAALgADCgMJAwAAAA==.Lisset:BAAALgAECgYJBgAAAA==.Literocola:BAAALgADCgQJBAAAAA==.Lizbethe:BAABLgAECn8mAAMRAAgJfhfmCgAWAgARAAgJfhfmCgAWAgAdAAYJpxwyFwDmAQAAAA==.Lizzii:BAAALgADCgMJAwAAAA==.',
Lo='Loltank:BAAALgADCgcJDgAAAA==.Lomrgreenol:BAAALgADCggJCAAAAA==.Lopi:BAABLgAECn8aAAINAAcJoAbgoAAWAQANAAcJoAbgoAAWAQAAAA==.Lorshadow:BAAALgADCgcJDQAAAA==.Lorwater:BAAALgADCgcJCQAAAA==.Lorynden:BAAALgAECgQJBQAAAA==.Loubrock:BAAALgAECgcJBwAAAA==.Lovach:BAABLgAECn8YAAQZAAYJiRp9EgCLAQAZAAYJiRp9EgCLAQAYAAMJMRNvZACuAAAPAAEJxBd6wQBDAAAAAA==.Loveinfinity:BAAALgAECgYJEwAAAA==.Lovenox:BAAALgADCgcJBwAAAA==.Lovington:BAAALgAECgMJBgABLgAFFAIJCAANAKcGAA==.',
Lu='Lu:BAAALgADCgYJBgABLgAECgYJCgAFAAAAAA==.Luandria:BAAALgAECggJEwAAAA==.Lucifall:BAAALgAECgQJCAAAAA==.Lugostiglitz:BAAALgAECgEJAQAAAA==.Luminas:BAAALgADCgIJAgAAAA==.Lumí:BAAALgAECgEJAQAAAA==.Lunchboss:BAAALgADCgEJAQAAAA==.Lurelune:BAAALgAECgIJAgABLgAFFAMJCAAJADUYAA==.Luxaria:BAAALgAECgUJBQAAAA==.Luxx:BAAALgADCgQJBAABLgAECgcJJQATAFEfAA==.',
Ly='Lylek:BAAALgAECgYJBgAAAA==.',
Ma='Mackie:BAAALgADCgUJBQABLgAECgQJBAAFAAAAAA==.Madstreak:BAAALgADCgMJAwAAAA==.Maelbeq:BAABLgAECn8iAAIkAAgJYSCbAwBkAgAkAAgJYSCbAwBkAgAAAA==.Maevelles:BAAALgADCgUJBwAAAA==.Mag:BAAALgADCgUJBQAAAA==.Mageulook:BAAALgAECgEJAQAAAA==.Magewain:BAAALgADCgUJBQAAAA==.Mageypoo:BAABLgAECn8nAAIBAAgJWySfCgDPAgABAAgJWySfCgDPAgAAAA==.Magicpickle:BAAALgADCgkJEQABLgAECgcJFQAKACkcAA==.Maine:BAAALgAECgQJBAAAAA==.Malakarth:BAAALgADCgEJAgAAAA==.Malathar:BAAALgAECgYJDQAAAA==.Mallowe:BAAALgADCgMJAwAAAA==.Malson:BAAALgADCgMJBAAAAA==.Marcelxd:BAAALgAECgcJBgAAAA==.Marcunta:BAAALgADCgEJAQAAAA==.Martinjc:BAAALgAECgYJBgAAAA==.Martinlw:BAAALgADCgUJBQAAAA==.Martinte:BAAALgADCgcJAgAAAA==.Marukka:BAAALgAECgEJAQAAAA==.Masambula:BAAALgADCgEJAQAAAA==.Mavering:BAAALgADCgEJAQAAAA==.Mayaa:BAAALgADCgMJAwAAAA==.Mayaesp:BAAALgADCgMJAwAAAA==.',
Me='Meene:BAAALgAECgYJDQAAAA==.Meepderp:BAAALgAECgcJDgABLgAFFAQJCgAPAFEdAA==.Mehaz:BAAALgADCgYJBgAAAA==.Memeep:BAACLgAFFH8KAAIPAAQJUR07CAAhAQAPAAQJUR07CAAhAQAuAAQKfykAAw8ACQmDJHkAANEDAA8ACQmDJHkAANEDABgAAgnYBZ18AFIAAAAA.Meowely:BAAALgADCgYJCgAAAA==.Merry:BAAALgAECgEJAQAAAA==.Meshshift:BAAALgADCgIJAQAAAA==.',
Mi='Miggs:BAAALgADCgEJAQAAAA==.Milfshotz:BAAALgAECggJDgAAAA==.Mimidésy:BAAALgADCgEJAQAAAA==.Minimiyagi:BAAALgAECgEJAQAAAA==.Minority:BAAALgAECggJCAAAAA==.Mirajanna:BAAALgAECgUJBQAAAA==.Missbehavior:BAAALgAECgUJCgAAAA==.Misscariina:BAAALgAECgcJDQAAAA==.Missmouthoff:BAABLgAECn8YAAIKAAYJahiUHQBcAQAKAAYJahiUHQBcAQAAAA==.Mistralwind:BAAALgADCgEJAQABLgAECgEJAQAFAAAAAA==.Miztärjake:BAAALgADCggJCQAAAA==.Mizzxgummy:BAAALgAECgcJBwAAAA==.',
Mo='Modush:BAAALgADCgUJBQAAAA==.Moldytoast:BAAALgAECgQJAwAAAA==.Monkstaar:BAAALgADCgEJAQAAAA==.Moogan:BAAALgAECgUJCAAAAA==.Mooneyes:BAAALgADCgcJHAAAAA==.Moonfishing:BAACLgAFFH8IAAIBAAMJCgeaTwDlAAABAAMJCgeaTwDlAAAuAAQKfyQAAgEACAlMEm5RAHYBAAEACAlMEm5RAHYBAAAA.Moonfly:BAABLgAECn8cAAIHAAgJlhnRCgAdAgAHAAgJlhnRCgAdAgAAAA==.Moonmoonpand:BAAALgADCgEJBAAAAA==.Moorea:BAAALgAECgYJCQAAAA==.Morax:BAAALgAECgMJBAAAAA==.Morbidlord:BAAALgADCgcJBwAAAA==.Moubu:BAAALgAECgEJAgAAAA==.Mouton:BAAALgAECgUJCgAAAA==.Mozumi:BAABLgAECn8WAAINAAYJxx+iLQCtAQANAAYJxx+iLQCtAQAAAA==.',
Mt='Mtnoflight:BAAALgADCgUJBQAAAA==.',
Mu='Munn:BAABLgAECn8iAAMBAAgJLhsiHQA7AgABAAgJLhsiHQA7AgAUAAUJHw8rDAAPAQAAAA==.Murag:BAABLgAECn8WAAICAAcJ7BezNwDIAQACAAcJ7BezNwDIAQAAAA==.Mureum:BAAALgADCgEJAQAAAA==.',
['Mä']='Mächtig:BAAALgADCgEJAQAAAA==.',
Na='Nalä:BAAALgADCgUJBAAAAA==.Nammi:BAAALgADCgUJBQAAAA==.Nardorne:BAAALgADCgcJCQAAAA==.Natsumy:BAABLgAECn8YAAINAAgJtAoBeQBqAQANAAgJtAoBeQBqAQAAAA==.',
Ne='Nearhammer:BAAALgAECgQJBAAAAA==.Nearsear:BAAALgADCgcJCQAAAA==.Necho:BAAALgAECgIJAgABLgAECggJEQAFAAAAAA==.Nefariouz:BAAALgAECgkJCgAAAA==.Nervouz:BAAALgAECggJEAABLgAECggJHgAJAOYGAA==.Nezarly:BAAALgADCgkJDQAAAA==.',
Ni='Niaalä:BAAALgAECgEJAQAAAA==.Nicky:BAAALgADCgYJBgAAAA==.Nitrøus:BAAALgAECgIJAwAAAA==.',
No='Nobbs:BAAALgAECgQJBAAAAA==.Noctis:BAAALgADCgUJBQAAAA==.Nohhozwa:BAABLgAECn8SAAINAAcJ8hQvPgBwAQANAAcJ8hQvPgBwAQAAAA==.Nool:BAAALgADCgcJCgAAAA==.Nosaj:BAABLgAECn8WAAMHAAYJeQ9oOgBMAQAHAAYJeQ9oOgBMAQACAAEJsgNv4gAiAAAAAA==.Notacow:BAAALgADCgUJAQAAAA==.Notzombie:BAAALgADCgIJAgAAAA==.Noxx:BAAALgAECgUJCAAAAA==.',
Nu='Nualaperafin:BAACLgAFFH8JAAIlAAQJeBhQAgBgAQAlAAQJeBhQAgBgAQAuAAQKfyQAAiUACQlgHPQCAAwDACUACQlgHPQCAAwDAAAA.',
Ny='Nysellia:BAAALgADCgcJCgAAAA==.Nyvara:BAAALgAECgMJAwAAAA==.',
Oc='Ocularagon:BAAALgADCgEJAgAAAA==.',
Ol='Olawdie:BAAALgAECgEJAgABLgAECgEJAgAFAAAAAA==.Olayro:BAABLgAECn8kAAINAAgJRAiwRwBRAQANAAgJRAiwRwBRAQAAAA==.',
Om='Omez:BAAALgAECggJCgAAAA==.Omut:BAAALgAECgcJCQAAAA==.',
On='Onlymilkers:BAAALgADCgEJAQAAAA==.Onsight:BAAALgAECgQJBAAAAA==.',
Oo='Ookabooka:BAAALgAECgEJAQAAAA==.Oopsiedaisy:BAAALgAECgUJCwAAAA==.',
Or='Orangeburn:BAAALgAECgEJAQAAAA==.Orestes:BAAALgAECggJEgAAAA==.',
Ow='Owillo:BAAALgAECgEJAQAAAA==.',
Pa='Pacadin:BAAALgAECgQJBAAAAA==.Palaguy:BAAALgADCgEJAQAAAA==.Paleie:BAAALgADCgcJDAABLgAFFAUJEwAVAPsWAA==.Palokarhu:BAAALgADCgIJAgAAAA==.Panterra:BAAALgADCgIJAgABLgADCgQJBAAFAAAAAA==.Papacy:BAAALgAECgEJAQAAAA==.Pathran:BAAALgADCgcJDAABLgAECggJJgANAMYcAA==.',
Pe='Peaky:BAAALgADCgMJAwAAAA==.Peeonsnow:BAAALgAECgYJBgAAAA==.Pellias:BAAALgADCgQJBAAAAA==.Pendrix:BAAALgAECgEJAQAAAA==.Pennerixi:BAAALgAECgkJBAAAAA==.Percevil:BAAALgADCgEJAQABLgAECgIJBQAFAAAAAA==.Percival:BAAALgAECgUJBgAAAA==.Perzeval:BAAALgAECgYJEQAAAA==.Perzevel:BAAALgAECgIJBQAAAA==.',
Ph='Pharmacology:BAABLgAECn8eAAMdAAcJCSJtBQCsAgAdAAcJTCFtBQCsAgAKAAQJNSTCKgCeAQAAAA==.Phénicie:BAAALgAECgEJAQAAAA==.',
Pi='Pieceofchit:BAAALgADCgUJCQAAAA==.',
Pj='Pjb:BAAALgADCgMJAwAAAA==.',
Pl='Plankton:BAAALgAECgQJCgAAAA==.',
Po='Pocholate:BAAALgADCgIJAgAAAA==.Popa:BAAALgAECgEJAQAAAA==.Potatofat:BAAALgADCgUJCgAAAA==.',
Pr='Prathe:BAABLgAECn8ZAAIeAAgJuR3bCgBkAgAeAAgJuR3bCgBkAgAAAA==.Prayformee:BAAALgADCgYJDAAAAA==.Priestpriest:BAAALgADCgEJAQAAAA==.',
Ps='Psiloci:BAAALgADCgEJAQABLgAECggJIQAHADEbAA==.Psilocy:BAABLgAECn8hAAIHAAgJMRsaDAAJAgAHAAgJMRsaDAAJAgAAAA==.Pspspspspsps:BAAALgAECggJEAAAAA==.',
Pu='Puddiintoo:BAAALgAECgYJDQAAAA==.Pulsate:BAAALgAECgcJCgAAAA==.Purplechem:BAAALgAECgMJAwAAAA==.',
Qa='Qaucker:BAABLgAECn8iAAMKAAgJzhkCCgBIAgAKAAgJzhkCCgBIAgAdAAYJowZ7MAAcAQAAAA==.',
Qi='Qiz:BAABLgAECn8fAAIBAAYJmiHWMgDVAQABAAYJmiHWMgDVAQAAAA==.Qizard:BAAALgADCgMJAwAAAA==.',
Qj='Qjq:BAAALgAECgMJAwAAAA==.',
Qu='Quintarite:BAAALgADCgMJAwAAAA==.Quistas:BAAALgAECgUJCAAAAA==.',
Ra='Radlock:BAAALgAECgIJBAAAAA==.Radwaran:BAAALgADCgYJCAAAAA==.Rahma:BAAALgADCgEJAgAAAA==.Raincal:BAABLgAECn8rAAIHAAgJzhY/IAD8AQAHAAgJzhY/IAD8AQAAAA==.Rainsford:BAAALgADCgEJAQAAAA==.Rakchu:BAAALgAECgQJCAAAAA==.Randios:BAAALgADCgMJAwAAAA==.Ranfalem:BAAALgADCgYJCAAAAA==.Rarib:BAAALgAECgIJAgAAAA==.Rasto:BAABLgAECn8gAAIbAAkJ0wypJACUAQAbAAkJ0wypJACUAQAAAA==.Rausrunebane:BAAALgADCgIJAwAAAA==.Ravokh:BAAALgADCgYJCgAAAA==.',
Re='Redhand:BAAALgADCgYJBgAAAA==.Redmark:BAAALgADCgYJBgAAAA==.Regolas:BAAALgADCgcJDQAAAA==.Relentlezz:BAAALgADCgIJAgAAAA==.Relica:BAABLgAECn8dAAIBAAgJaxDwPACxAQABAAgJaxDwPACxAQAAAA==.Restalan:BAAALgADCgEJAQAAAA==.Revki:BAAALgAECgEJAQAAAA==.Revolvr:BAABLgAECn8sAAImAAgJth6RAQAKAwAmAAgJth6RAQAKAwAAAA==.Reïgn:BAAALgADCgUJBQAAAA==.',
Ri='Ridire:BAAALgAECgcJEQAAAA==.Rippedbutt:BAAALgADCgcJBwAAAA==.Riptidus:BAACLgAFFH8SAAIbAAUJBxsJBADcAQAbAAUJBxsJBADcAQAuAAQKfyEAAxsACAmGGsAiAA4CABsACAmGGsAiAA4CAAQABQmvD8MxAOsAAAAA.Ripzly:BAAALgAECgUJBQAAAA==.Ritalin:BAAALgADCgcJEAAAAA==.Rizzakk:BAAALgADCgcJBAAAAA==.',
Ro='Rogawr:BAAALgADCgEJAQAAAA==.Roguemas:BAAALgADCggJDQAAAA==.Ropeshooter:BAAALgADCgMJAwAAAA==.Roshi:BAAALgADCgIJAgAAAA==.Roxus:BAAALgAECgQJBwAAAA==.',
Ru='Rubberduck:BAAALgADCgYJBgAAAA==.Rudabaga:BAAALgADCgEJAQAAAA==.Rumî:BAABLgAECn8aAAIIAAgJUR0sDABtAgAIAAgJUR0sDABtAgAAAA==.Runaf:BAAALgADCgkJCgAAAA==.Runhauf:BAAALgAECgcJCAAAAA==.Runts:BAAALgAECgQJBQAAAA==.',
Ry='Ryuni:BAAALgAECgEJAQAAAA==.',
Sa='Sabellal:BAAALgADCgQJBAAAAA==.Sacredaura:BAAALgAECgMJBAAAAA==.Saegusa:BAAALgAECgQJBQAAAA==.Safedruid:BAAALgADCgUJCAABLgADCgEJAQAFAAAAAA==.Samhain:BAAALgADCgEJAQAAAA==.Samshamwow:BAAALgADCgMJAwABLgAFFAQJDQAiAKYOAA==.Saneseth:BAAALgAECgYJEQAAAA==.Sangodi:BAAALgAECgEJAQAAAA==.Sangomia:BAABLgAFFH8UAAMaAAUJ2iV3CQC8AQAaAAQJ2iV3CQC8AQAMAAEJAACxKgAAAAAAAA==.Saniblaze:BAAALgADCgQJBwAAAA==.Sanlanesh:BAAALgAECgEJAQAAAA==.Sarrazine:BAAALgAECgQJBgAAAA==.Sasive:BAAALgAECgYJCAAAAA==.Sassbringer:BAAALgAECgIJAgAAAA==.Sayani:BAAALgAECgQJBAAAAA==.',
Sc='Schmall:BAABLgAECn8WAAIEAAcJCxKtIwA3AQAEAAcJCxKtIwA3AQAAAA==.Scpypy:BAAALgAECgEJAQAAAA==.Scärlët:BAABLgAECn8sAAIKAAgJSxx1BwB8AgAKAAgJSxx1BwB8AgAAAA==.',
Se='Secrient:BAACLgAFFH8MAAIaAAQJyRHbKgBKAQAaAAQJyRHbKgBKAQAuAAQKfygAAhoACAlZIEgdABkCABoACAlZIEgdABkCAAAA.Selume:BAAALgADCgcJCAAAAA==.Selvalin:BAAALgADCgIJAgAAAA==.Sevyn:BAAALgAECgEJAwAAAQ==.Sevynari:BAAALgAECgQJBQABLgAECgEJAwAFAAAAAQ==.',
Sh='Shadowmeres:BAAALgAECgEJAQAAAA==.Shamtaar:BAAALgADCgMJAwAAAA==.Shestalker:BAAALgAECgQJBAAAAA==.Shieldheart:BAAALgADCgkJFAAAAA==.Shielpruuf:BAAALgAECgEJAQAAAA==.Shiift:BAABLgAECn8bAAICAAgJDBKtJgCYAQACAAgJDBKtJgCYAQAAAA==.Sholl:BAABLgAECn8bAAMRAAcJkRtEDwDZAQARAAcJkRtEDwDZAQAKAAEJVA8/TwAvAAAAAA==.Sholls:BAACLgAFFH8HAAIhAAMJ7Q5QBwCoAAAhAAMJ7Q5QBwCoAAAuAAQKfx8AAyEACAn8HMsJAAECACEACAkCG8sJAAECACIABgmgHEMIAKwBAAAA.Shurpi:BAAALgADCgEJAQAAAA==.Shweener:BAAALgAECgEJAQAAAA==.',
Si='Siandena:BAAALgADCgQJBgAAAA==.Sieguer:BAAALgAECgIJAgAAAA==.Sigismund:BAAALgAECgEJAQAAAA==.Sillygøøsey:BAAALgADCgIJAgAAAA==.Silvaine:BAABLgAECn8YAAIBAAgJowR1cAAwAQABAAgJowR1cAAwAQAAAA==.Silverdrack:BAAALgAFFAMJAwAAAA==.',
Sk='Skalitzath:BAAALgADCgQJAwAAAA==.Skarlax:BAAALgADCgEJAQABLgAECggJFgAeABojAA==.Skkits:BAAALgAECgMJAwAAAA==.Skrunkle:BAAALgAECgYJDAABLgAECggJIQAaAMQRAA==.Skulshooter:BAAALgADCgQJBAAAAA==.',
Sl='Slarhan:BAAALgADCgEJAQAAAA==.Slickshooter:BAAALgADCgMJBQAAAA==.',
Sm='Smibaco:BAAALgAECgEJAQAAAA==.Smushbush:BAACLgAFFH8HAAIOAAMJNSAlHAA9AQAOAAMJNSAlHAA9AQAuAAQKfxsAAg4ACAnYIykYADoCAA4ACAnYIykYADoCAAAA.Smushinbush:BAAALgAECgYJCQABLgAFFAMJBwAOADUgAA==.Smushyobush:BAAALgAECgcJDAABLgAFFAMJBwAOADUgAA==.',
Sn='Snicklefritz:BAAALgAECgQJBQABLgAECgcJEgAFAAAAAA==.Snipez:BAAALgAECgQJBAAAAA==.Snortymcdash:BAAALgAECgYJBgAAAA==.',
So='Solclipeus:BAACLgAFFH8KAAMGAAMJJBODBQC/AAAGAAMJJBODBQC/AAAOAAMJvAGROwC6AAAuAAQKfyYAAwYACAmDIuMCAPkCAAYACAmDIuMCAPkCAA4ACAmEEihVAOIBAAAA.Soldh:BAAALgADCgYJBwABLgAFFAMJCgAGACQTAA==.Soultaker:BAAALgAECgEJAQAAAA==.Soulton:BAAALgAECgUJCgAAAA==.Souperscott:BAAALgAECgIJAgAAAA==.Soupz:BAABLgAECn8iAAIOAAYJrCM4IQADAgAOAAYJrCM4IQADAgAAAA==.',
Sp='Spaghett:BAABLgAECn8hAAIEAAkJyhZoDAAUAgAEAAkJyhZoDAAUAgAAAA==.Sparkev:BAAALgADCgYJDAAAAA==.Spongebobytp:BAAALgADCgYJCAAAAA==.Springburn:BAAALgADCgUJBQAAAA==.',
Sq='Squady:BAAALgAECgEJAQABLgAECgEJAgAFAAAAAA==.Squiddy:BAAALgAECgEJAQAAAA==.',
Sr='Sririacha:BAACLgAFFH8IAAIJAAMJNRjbHQD6AAAJAAMJNRjbHQD6AAAuAAQKfyEAAwkACAl5GIISAFYCAAkACAl5GIISAFYCACMABAkUCtArAL4AAAAA.',
St='Stabbyabby:BAAALgADCggJDgAAAA==.Stabbypickle:BAAALgAECgUJBQABLgAECgcJFQAKACkcAA==.Statík:BAAALgADCgMJBgABLgAECgYJDQAFAAAAAA==.Steelbane:BAAALgADCgEJAQAAAA==.Stewy:BAAALgADCgYJCQAAAA==.Strånge:BAABLgAECn8WAAMBAAYJTyGohADIAQABAAYJTyGohADIAQAnAAEJdQU4EQAtAAAAAA==.Styxton:BAAALgAECggJCAAAAA==.Stìtch:BAABLgAECn9JAAMSAAgJzhywCAA2AgANAAgJOxyOEABgAgASAAgJABiwCAA2AgAAAA==.',
Su='Succubetch:BAAALgAECgYJEAAAAA==.Sukiafaunias:BAAALgAECgUJCwAAAA==.Sumirishade:BAAALgAECgIJAgAAAA==.Suoop:BAAALgAECgQJCgAAAA==.Surgeclaw:BAAALgAECgQJCgAAAA==.Suziedh:BAAALgAECgEJAQAAAA==.Suziesham:BAAALgAECgEJAQAAAA==.',
Sw='Switchbladez:BAAALgAECgEJAgAAAA==.',
Sy='Sylendris:BAAALgADCgYJBgAAAA==.',
['Sì']='Sìx:BAAALgAECgYJDQABLgAECggJCQAFAAAAAA==.',
['Sï']='Sïxx:BAAALgADCgcJCgABLgAECggJCQAFAAAAAA==.',
['Sø']='Søÿsåûçê:BAAALgAECgEJAQABLgAECgcJJAAVABMeAA==.',
Ta='Tadg:BAAALgAFFAIJAgAAAA==.Taeril:BAAALgAECgIJAgAAAA==.Taezanx:BAAALgADCgcJBwAAAA==.Tahm:BAABLgAECn8cAAIfAAgJLB8DBgCnAgAfAAgJLB8DBgCnAgAAAA==.Tambel:BAAALgADCgQJBAAAAA==.Tanburn:BAAALgAECgQJDgAAAA==.Tanduinex:BAAALgADCgcJFgAAAA==.Tanrobby:BAAALgADCgUJCQAAAA==.Tanthe:BAAALgADCgYJDAAAAA==.Tapae:BAAALgADCgYJBgAAAA==.Taterrot:BAAALgADCgMJAwAAAA==.Tatsumy:BAAALgAECgUJEAAAAA==.Taylorswïft:BAAALgAECgEJAQAAAA==.',
Tc='Tcdathirsty:BAAALgAECgMJAwAAAA==.Tcmon:BAABLgAECn8VAAQPAAYJvxIRWgBZAQAPAAUJwRYRWgBZAQAZAAIJAwJ4KwBMAAAYAAMJkgH0fgBKAAAAAA==.',
Te='Teaghan:BAABLgAECn8UAAIBAAgJihBwPQCvAQABAAgJihBwPQCvAQAAAA==.Teaglizzy:BAACLgAFFH8LAAIOAAMJBwuLMwDpAAAOAAMJBwuLMwDpAAAuAAQKfy0AAg4ACQmQGqcaAMkCAA4ACQmQGqcaAMkCAAAA.Teancm:BAAALgADCgUJBQAAAA==.Tedward:BAAALgADCgQJBAAAAA==.Teehole:BAABLgAECn8VAAIOAAgJpgwpdgCOAQAOAAgJpgwpdgCOAQAAAA==.Tempert:BAAALgADCgYJBgAAAA==.Termytree:BAAALgADCgcJBwAAAA==.Terorblade:BAAALgAECgIJAgAAAA==.',
Th='Thaetrois:BAAALgADCgMJBAAAAA==.Thanet:BAAALgADCgQJBAAAAA==.Thanussy:BAABLgAECn8aAAMJAAkJZQ2pEwCrAQAJAAkJZQ2pEwCrAQAoAAgJDAW3JgA/AQAAAA==.Thebean:BAAALgADCgQJBAAAAA==.Thebigtuna:BAAALgAECgYJEAAAAA==.Thegodpvp:BAAALgADCgEJAQAAAA==.Theladydruid:BAABLgAECn8uAAMHAAgJ6BkTCwAaAgAHAAgJ6BkTCwAaAgACAAcJWwjvYwAmAQAAAA==.Thestashman:BAAALgAECgcJCAAAAA==.Thexalia:BAAALgAECgUJCQAAAA==.Thighsoffel:BAAALgAECgkJBAAAAA==.Thordam:BAAALgADCgkJCQAAAA==.Threetee:BAAALgADCgQJCAAAAA==.Threnador:BAAALgAECgcJDQAAAA==.Thyrena:BAAALgADCgMJAwAAAA==.',
Ti='Tierrasbe:BAAALgAECgQJBgAAAA==.Tigerpa:BAAALgAECgkJCwAAAA==.Tinkernut:BAAALgADCgEJAQAAAA==.Tinysmites:BAAALgAECgUJBgAAAA==.Tinythia:BAABLgAECn8tAAIBAAgJgxahLgDmAQABAAgJgxahLgDmAQAAAA==.Tioklarus:BAABLgAECn8VAAIjAAYJ5AvODADEAAAjAAYJ5AvODADEAAAAAA==.',
To='Tofulady:BAABLgAECn8rAAIfAAgJTSRCAgA4AwAfAAgJTSRCAgA4AwAAAA==.Tornstorm:BAAALgAECgIJAgAAAA==.Torokun:BAAALgADCgUJBwAAAA==.',
Tr='Trashbunny:BAAALgAECgIJAgAAAA==.Travïskelce:BAAALgAECgEJAQAAAA==.Traystiria:BAAALgAECgIJAwABLgAECggJHgABABoXAA==.Trazin:BAAALgADCgEJAQAAAA==.Treesothorny:BAAALgAECgcJEgAAAA==.Triscüit:BAAALgAECgYJDgAAAA==.Truemoosiah:BAAALgAECgYJBgAAAA==.Trébol:BAAALgAECgEJAQAAAA==.Tròll:BAAALgADCgYJBwAAAA==.',
Tu='Turlok:BAAALgAECgYJEAABLgAECgcJEgANAPIUAA==.',
Tw='Twotwotrain:BAAALgAECgUJCAAAAA==.',
Ty='Tyania:BAAALgADCggJCAABLgAECgEJAQAFAAAAAA==.',
['Tå']='Tåter:BAAALgADCgUJBQAAAA==.',
Uk='Ukraineghost:BAAALgAECgMJAwAAAA==.',
Ul='Ulukki:BAAALgAECgcJDAAAAA==.',
Um='Umbralpickle:BAABLgAECn8VAAMKAAcJKRzIDAAaAgAKAAYJIB/IDAAaAgARAAYJpRdcJAAfAQAAAA==.',
Un='Uncleiroh:BAAALgAECgYJCwAAAA==.Uncleruckus:BAAALgAECgUJBQAAAA==.Unhowly:BAACLgAFFH8IAAIaAAMJxhKVSwD4AAAaAAMJxhKVSwD4AAAuAAQKfyMAAhoACQmfHYckAPEBABoACQmfHYckAPEBAAAA.Unrealwushu:BAAALgADCgEJAQAAAA==.Unredeadzomb:BAAALgAECgEJAgAAAA==.Untaintedp:BAAALgADCgEJAQAAAA==.',
Ur='Urgelgru:BAAALgAECggJDgAAAA==.Ursaluna:BAAALgADCgcJBgABLgAECggJFgANAFEaAA==.',
Va='Valhalah:BAAALgADCgUJCgAAAA==.Vapidos:BAAALgAECgYJBwAAAA==.Varlug:BAAALgAECgQJBAAAAA==.Varynxiv:BAAALgAECgIJAgABLgAECgQJBQAFAAAAAA==.Vatica:BAAALgAECgQJBAAAAA==.Vauik:BAABLgAECn8hAAIaAAgJxBGLOACXAQAaAAgJxBGLOACXAQAAAA==.',
Ve='Vealeriadk:BAACLgAFFH8WAAMaAAcJOiCBAwAWAgAaAAYJKCCBAwAWAgAMAAQJ7iBsBABmAQAuAAQKfx4ABBoACAm5JYoUAAADABoACAmCJYoUAAADAAwAAwkFJlYgAEIBACAAAQk9IjwTAF4AAAAA.Venatorr:BAAALgADCgcJBwAAAA==.Venvalzhar:BAAALgAECgYJBgAAAA==.Venyym:BAAALgADCgcJCAAAAA==.Veras:BAAALgAECgEJAgAAAA==.Vestammeni:BAAALgAECgEJAwAAAA==.Vexz:BAAALgAECgYJCQABLgAFFAQJBwAkAO8cAA==.Veyghar:BAAALgAECgIJAgABLgAECgUJCAAFAAAAAA==.',
Vi='Vintageghast:BAAALgADCgQJBAAAAA==.',
Vl='Vladmiir:BAAALgAECgcJBwAAAA==.',
Vo='Voidtool:BAAALgADCgIJAgAAAA==.Vosagus:BAAALgAECgEJAgABLgAFFAIJAgAFAAAAAA==.',
['Vê']='Vêzz:BAABLgAECn8oAAIEAAgJERlCHgAdAgAEAAgJERlCHgAdAgAAAA==.',
Wa='Waldwaffe:BAAALgADCgMJAwAAAA==.',
Wc='Wckd:BAABLgAECn8eAAIGAAcJPxiQEAC9AQAGAAcJPxiQEAC9AQAAAA==.Wckddh:BAAALgAECgEJAwAAAA==.Wckdwar:BAAALgAECggJEQAAAA==.',
We='Weedvegeta:BAABLgAECn8ZAAIBAAgJ1BVDLgDoAQABAAgJ1BVDLgDoAQAAAA==.Weinerslam:BAAALgAECgEJAgAAAA==.Wells:BAAALgADCgEJAQAAAA==.Wendego:BAAALgADCgMJAwAAAA==.Wernbirn:BAAALgAECggJBQAAAA==.Wetraman:BAAALgAECgEJAQABLgAECggJFQAHAPYRAA==.Wetremin:BAABLgAECn8VAAIHAAgJ9hFcEwCqAQAHAAgJ9hFcEwCqAQAAAA==.',
Wh='Whiplashh:BAAALgAECgMJBAAAAA==.Whir:BAAALgADCgYJBgAAAA==.Whiry:BAABLgAECn8UAAImAAgJRxbsAwDkAQAmAAgJRxbsAwDkAQAAAA==.Whirzy:BAAALgADCgUJBQAAAA==.Whitebeard:BAAALgAECgEJAQAAAA==.Whizkee:BAABLgAECn8aAAIRAAkJZxXZCQAnAgARAAkJZxXZCQAnAgAAAA==.',
Wi='Willowpuff:BAAALgAFFAEJAQAAAA==.Wingedlady:BAAALgAECgYJDQAAAA==.Wiskerbiskit:BAAALgAECgcJCwAAAA==.Wiskitbisker:BAACLgAFFH8KAAIaAAMJjRIbUQDtAAAaAAMJjRIbUQDtAAAuAAQKfxYAAhoABwkJGhFKABUCABoABwkJGhFKABUCAAAA.',
Wo='Woestalker:BAAALgAECgQJBAAAAA==.Wongway:BAAALgAECgEJAQAAAA==.Worldgods:BAAALgADCgkJDQAAAA==.',
Wp='Wpnocturne:BAABLgAECn8XAAINAAgJ/QcXYQAOAQANAAgJ/QcXYQAOAQAAAA==.',
Wt='Wtfomgbbqftw:BAAALgAECgEJAQAAAA==.',
Wu='Wushu:BAABLgAECn8UAAINAAcJUAzySABNAQANAAcJUAzySABNAQAAAA==.',
Wy='Wyl:BAABLgAECn8UAAIOAAcJdiGJFABVAgAOAAcJdiGJFABVAgABLgAECggJKAAIALIgAA==.Wyrdfell:BAAALgADCgEJAQAAAA==.',
['Wí']='Wíllõw:BAAALgADCgYJBgAAAA==.',
Xa='Xanthian:BAAALgADCgUJCwAAAA==.Xarrath:BAAALgADCgUJBQAAAA==.',
Xe='Xemro:BAAALgAECgQJBAAAAA==.Xendai:BAAALgAECgQJEAAAAA==.',
Xh='Xhyro:BAAALgAECgUJBQAAAA==.',
Xi='Xiing:BAABLgAECn8cAAIcAAkJAA1mDQCMAQAcAAkJAA1mDQCMAQAAAA==.',
Xn='Xneutron:BAABLgAECn8aAAMUAAgJHR1OAQA2AgAUAAcJHR1OAQA2AgABAAEJAACFYQE/AAAAAA==.',
Xt='Xtravagent:BAABLgAECn8WAAMWAAYJXBaPFwAmAQAWAAUJthmPFwAmAQAIAAUJvwztjwABAQAAAA==.',
Xy='Xynthris:BAABLgAECn8rAAIYAAkJLRv9AQB5AgAYAAkJLRv9AQB5AgAAAA==.',
Yo='Yodieceo:BAAALgAECgIJAgAAAA==.Yonna:BAAALgAECgMJBwAAAA==.Yopps:BAABLgAECn8YAAMNAAgJKhmtKgBlAgANAAgJKhmtKgBlAgASAAEJjxG9cAA1AAAAAA==.',
Yu='Yunggrazydh:BAAALgADCgcJCAAAAA==.Yurio:BAAALgADCgEJAQAAAA==.Yuunggrazy:BAAALgAECgUJBgAAAA==.',
['Yé']='Yéager:BAABLgAECn8dAAICAAkJ1x89BAAhAwACAAkJ1x89BAAhAwAAAA==.',
Za='Zabuto:BAABLgAECn8mAAIHAAkJSxp7CABJAgAHAAkJSxp7CABJAgAAAA==.Zaevryn:BAAALgAECgYJCAABLgAECgQJEAAFAAAAAA==.Zahäära:BAAALgAECgMJBgAAAA==.Zakaka:BAAALgAECgUJCAAAAA==.Zandrozarath:BAAALgAECgUJBQAAAA==.Zarrtan:BAAALgADCgcJCgAAAA==.Zazprie:BAAALgAECgUJBQAAAA==.',
Ze='Zeithergrim:BAAALgAECgYJBgAAAA==.Zenpickle:BAAALgADCgYJBgABLgAECgcJFQAKACkcAA==.Zenrelia:BAAALgADCgEJAgAAAA==.Zerazenasdan:BAAALgADCgcJBwAAAA==.',
Zi='Zicatriz:BAAALgADCggJDgAAAA==.',
Zo='Zongretaboom:BAAALgAECgUJCAAAAA==.Zooss:BAABLgAECn8WAAIOAAgJvhvkHQAUAgAOAAgJvhvkHQAUAgAAAA==.Zoralias:BAAALgADCgUJBQAAAA==.Zoth:BAAALgADCgcJCAAAAA==.',
Zs='Zshot:BAACLgAFFH8SAAIZAAYJrSOoAADqAQAZAAYJrSOoAADqAQAuAAQKfyIAAxkACQkOJU8AALoDABkACQkNJU8AALoDABgAAQlcIHd+AEwAAAAA.',
Zu='Zuggýzug:BAAALgAECgIJAwAAAA==.Zularam:BAAALgADCgYJBgAAAA==.Zuliks:BAAALgAECgcJDgAAAA==.',
Zx='Zxeý:BAAALgAECgYJDgAAAA==.',
Zy='Zyy:BAAALgADCgcJDQAAAA==.',
['Äb']='Äbracadabruh:BAAALgAECgUJDAAAAA==.',
['Êl']='Êlsa:BAAALgADCgIJAgAAAA==.',
['Ên']='Ênkidu:BAAALgAECgYJBwAAAA==.',
['Ðo']='Ðominants:BAAALgAECgUJBQAAAA==.',
['Ôd']='Ôdoyle:BAAALgAECgMJAwAAAA==.',
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

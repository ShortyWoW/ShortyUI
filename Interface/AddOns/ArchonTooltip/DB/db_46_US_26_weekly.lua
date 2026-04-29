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

local lookup = {'Mage-Frost','Shaman-Elemental','Unknown-Unknown','Paladin-Protection','DemonHunter-Devourer','Evoker-Augmentation','Priest-Holy','Warrior-Fury','Paladin-Retribution','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Druid-Balance','Monk-Brewmaster','DemonHunter-Havoc','Hunter-Marksmanship','Hunter-BeastMastery','Hunter-Survival','Mage-Arcane','DeathKnight-Unholy','Priest-Shadow','Warrior-Protection','Priest-Discipline','DemonHunter-Vengeance','Paladin-Holy','Monk-Mistweaver','DeathKnight-Frost','Monk-Windwalker','Druid-Restoration','Warrior-Arms','Shaman-Enhancement','Shaman-Restoration','Rogue-Assassination','Druid-Feral','Druid-Guardian','Evoker-Devastation','Mage-Fire','DeathKnight-Blood',}
local provider = {region='US',realm='Azshara',name='US',type='weekly',zone=46,date='2026-04-24',data={Ac='Acethyr:BAAALgADCggJCAAAAA==.Activase:BAAALgAECgEJAQAAAA==.Activasee:BAABLgAECn8ZAAIBAAcJjxLhGgBzAQABAAcJjxLhGgBzAQAAAA==.',
Ad='Adarnyk:BAAALgAECgQJBAAAAA==.Adgavis:BAAALgADCgUJCgAAAA==.Adiena:BAAALgADCggJCAAAAA==.',
Ae='Aelelelos:BAAALgAECgIJAgAAAA==.Aevenyhm:BAAALgAECgYJDgAAAA==.',
Ah='Ahsoul:BAAALgAECgUJCgAAAA==.',
Ak='Akadein:BAAALgAECgYJDAAAAA==.Akimato:BAAALgAECgIJAgAAAA==.Akzulf:BAAALgADCgEJAQAAAA==.',
Al='Alaeul:BAAALgADCgEJAQAAAA==.Alarael:BAAALgADCgcJDAAAAA==.Alenath:BAAALgAECgEJAQAAAA==.Alicelin:BAABLgAECn8oAAICAAcJaiKBAwADAgACAAcJaiKBAwADAgAAAA==.Alicê:BAAALgADCgIJAgAAAA==.Allhallows:BAAALgAECgUJBgAAAA==.Aloko:BAAALgAECgEJAgABLgAECgQJCgADAAAAAA==.Alqueria:BAAALgAECgEJBQAAAA==.Altarboizyum:BAAALgAECgQJBAABLgAFFAMJBwAEACQTAA==.',
Am='Amanuit:BAAALgADCgUJBQAAAA==.Amoreing:BAAALgADCgEJAQAAAA==.',
An='Andress:BAAALgAECgMJAwAAAA==.Angrylabubu:BAAALgADCgUJBQAAAA==.Anitadrink:BAAALgAECggJEAAAAA==.Anitapiss:BAAALgAECgIJAgAAAA==.Annarri:BAAALgADCgcJDAAAAA==.Anneweaver:BAABLgAECn8aAAIBAAgJ6g3NcQDwAQABAAgJ6g3NcQDwAQAAAA==.Annihilus:BAABLgAECn8iAAIFAAgJAR7aFwDGAgAFAAgJAR7aFwDGAgAAAA==.Anthorian:BAAALgADCgMJBgAAAA==.',
Ap='Aperture:BAAALgADCgkJCQABLgAECggJHQAGAHkYAA==.Apicots:BAABLgAECn8XAAIHAAgJbySKAgBAAwAHAAgJbySKAgBAAwAAAA==.Apipa:BAAALgADCgYJCAABLgAECgQJBQADAAAAAA==.Apocalypse:BAAALgAECgUJCwAAAA==.Aprilstorms:BAAALgAECgYJDwAAAA==.',
Ar='Arcaneklout:BAAALgADCgEJAQAAAA==.Archalice:BAAALgAECgUJBgAAAA==.Arctik:BAAALgADCgMJAwAAAA==.Ardelas:BAAALgADCgUJAwAAAA==.Ariella:BAAALgADCgEJAQAAAA==.Aris:BAAALgADCgUJBQAAAA==.Artica:BAAALgAECgIJAgAAAA==.Aryn:BAAALgADCgMJAwAAAA==.',
As='Asherabinx:BAAALgADCgEJAQAAAA==.Asztaroth:BAAALgADCggJDgAAAA==.',
At='Athrepos:BAAALgAECgQJBwAAAA==.Atomoonk:BAAALgAECggJEwAAAA==.Atoy:BAAALgAECgMJAwAAAA==.Atreian:BAAALgAECgEJAQAAAA==.Atrejha:BAAALgAECgUJCwAAAA==.',
Au='Aurethas:BAAALgADCgcJBgAAAA==.Aurithos:BAAALgAECggJEgAAAA==.Aurousdiamo:BAAALgADCgYJBgAAAA==.Aurä:BAAALgAECggJEAABLgAECggJDwADAAAAAA==.Aussilio:BAAALgADCgYJBgAAAA==.',
Av='Avanddraeda:BAAALgAECgQJBAAAAA==.Avariel:BAAALgADCgUJBQABLgAECgUJBQADAAAAAA==.',
Aw='Awesome:BAAALgAECgIJBAAAAA==.Awesometail:BAAALgADCgYJBgAAAA==.',
Ax='Axul:BAAALgADCgEJAQAAAA==.',
Az='Azazelundead:BAAALgADCggJFgAAAA==.Azrina:BAAALgAECgYJEQAAAA==.',
Ba='Baam:BAAALgADCgUJBwAAAA==.Badboi:BAAALgAECgQJBAAAAA==.Bahnzuul:BAAALgADCgYJBgAAAA==.Baidden:BAAALgADCgcJDgAAAA==.Baldbandit:BAAALgADCgcJBwAAAA==.Balddh:BAAALgADCgkJEQAAAA==.Ballseye:BAAALgAECgIJAgAAAA==.Balsagnatung:BAAALgAECgkJDwABLgAFFAIJAgADAAAAAA==.Bananaheals:BAAALgAECgIJAgAAAA==.Bandidos:BAAALgADCggJEwAAAA==.Bapaful:BAAALgADCgYJBgAAAA==.Barkformommy:BAAALgADCgEJAQAAAA==.',
Be='Behealzabub:BAAALgAECgYJCwAAAA==.Behrman:BAAALgADCgYJBgABLgAECgUJBQADAAAAAA==.Belfposer:BAAALgAECgYJDQAAAA==.Belpepper:BAAALgAFFAIJAgAAAA==.Belwas:BAAALgADCgMJAwAAAA==.Bendelmonte:BAAALgADCgkJFgAAAA==.Bengi:BAAALgADCgYJBwAAAA==.Bentone:BAAALgAECgIJAgAAAA==.Bergerkìng:BAAALgAECggJDgAAAA==.',
Bi='Bibiimbap:BAAALgADCgEJAQABLgAECgkJHwAIAO4gAA==.Bigbigboi:BAAALgADCgMJAwAAAA==.Bigchungus:BAAALgAECgYJBgAAAA==.Bilipmonk:BAAALgAECgYJEgAAAA==.Birdofhermes:BAAALgAECgEJAQAAAA==.Biñx:BAAALgADCgUJCAAAAA==.',
Bl='Blackamus:BAAALgAECgEJAQAAAA==.Blarr:BAAALgAECgQJBAAAAA==.Blastss:BAAALgADCgUJCgAAAA==.Blindvoid:BAAALgAECgUJCgABLgADCgcJDQADAAAAAA==.Blipilopian:BAAALgADCgMJAwAAAA==.Blockhead:BAAALgAECgUJBwAAAA==.',
Bo='Boenur:BAAALgADCgQJBAAAAA==.Bokumbap:BAABLgAECn8fAAIIAAkJ7iA3BABoAwAIAAkJ7iA3BABoAwAAAA==.Bonesteel:BAAALgAECgYJCgAAAA==.Boomacita:BAAALgAECgMJBQAAAA==.Boonkay:BAAALgADCgYJDgAAAA==.Boonkie:BAAALgADCgUJCwAAAA==.Boonksdeath:BAAALgADCgYJBgAAAA==.Boreowlis:BAAALgAECgEJAwAAAA==.Boribap:BAAALgAECgYJCgABLgAECgkJHwAIAO4gAA==.Botoliilii:BAAALgADCgEJAQAAAA==.',
Br='Bremspal:BAAALgADCgYJBgAAAA==.Brewtangclan:BAAALgAECgYJDgAAAA==.Briarr:BAAALgAECgUJBgAAAA==.Brisanna:BAAALgADCgcJDAAAAA==.Brucethemage:BAAALgAECgEJAwAAAA==.Bruleecreme:BAAALgAECgYJEAAAAA==.',
Bu='Bubbasquez:BAACLgAFFH8GAAIJAAMJwBQ/FQAAAQAJAAMJwBQ/FQAAAQAuAAQKfxoAAgkACAmFG+4lAI8CAAkACAmFG+4lAI8CAAAA.Bububear:BAAALgAECgYJBgAAAA==.Bugsjugs:BAAALgAECgYJEwAAAA==.Bugszugs:BAAALgADCgMJAwAAAA==.Buonasera:BAAALgADCgMJAwAAAA==.',
['Bà']='Bàng:BAAALgADCgMJAwAAAA==.Bàwlz:BAAALgAECgYJCQAAAA==.',
['Bè']='Bèérsërk:BAAALgADCgMJBAAAAA==.',
Ca='Caledor:BAAALgADCgQJBAAAAA==.Camitriel:BAABLgAECn9qAAQKAAkJUSYJAACMAwAKAAgJRyYJAACMAwALAAYJGCZgAQC3AQAMAAEJeibzBQBxAAAAAA==.Castence:BAAALgADCgIJAgAAAA==.',
Cb='Cbdpen:BAAALgAECgEJAgAAAA==.',
Ce='Ceaserianoma:BAAALgAECgEJAQAAAA==.Celerunas:BAAALgAECgEJAQABLgAECgYJCgADAAAAAA==.',
Ch='Chaunakoala:BAAALgADCgcJBgAAAA==.Cheesydemon:BAAALgADCgUJBQAAAA==.Chessguitar:BAABLgAECn8gAAINAAcJzRUTKQC2AQANAAcJzRUTKQC2AQAAAA==.Chubbss:BAAALgAECgcJAgAAAA==.Chudkahlif:BAAALgAECgEJAQAAAA==.Chunkymonk:BAAALgADCgQJBAAAAA==.',
Cl='Clopendeath:BAAALgADCgMJAQAAAA==.Cloüdyy:BAAALgADCgIJAgAAAA==.Clyemne:BAAALgADCgcJDQABLgADCgkJCQADAAAAAA==.Clïve:BAAALgADCgYJFAAAAA==.',
Co='Coachjim:BAABLgAECn8WAAIBAAgJhxiqRgBkAgABAAgJhxiqRgBkAgAAAA==.Cocinegr:BAABLgAECn8dAAQKAAgJ2BX0PAAZAgAKAAgJ2BX0PAAZAgAMAAMJVw1uHACPAAALAAIJcQV4WgBfAAAAAA==.Cocinegrö:BAAALgAECgMJAwABLgAECggJHQAKANgVAA==.Coneja:BAAALgAECgYJCgAAAA==.Corazon:BAAALgAECgEJAQAAAA==.',
Cr='Craabman:BAAALgAECgQJBAAAAA==.Craiso:BAABLgAECn8ZAAIOAAgJwCAhCAAEAwAOAAgJwCAhCAAEAwAAAA==.Crasher:BAAALgADCggJCAAAAA==.Creamyholes:BAAALgADCgYJBgAAAA==.Crimsondawn:BAAALgADCgUJBQAAAA==.Crisnerion:BAAALgADCgcJCQAAAA==.Cryonix:BAAALgADCgQJBAAAAA==.',
Ct='Cthuvian:BAAALgADCgcJCQAAAA==.',
Cu='Cuddlesama:BAAALgADCgYJBgAAAA==.Cudleyknight:BAAALgAECgIJAwAAAA==.Current:BAABLgAECn8ZAAIPAAcJ8wl2OAAiAQAPAAcJ8wl2OAAiAQAAAA==.',
Cy='Cynesd:BAAALgADCgQJBAAAAA==.Cynesh:BAACLgAFFH8XAAQQAAYJ9RtYAwAXAgAQAAYJvhdYAwAXAgARAAQJ2x1WCQAWAQASAAEJWRFdBwBWAAAuAAQKfycAAxAACQlkI54BAKgDABAACQklIp4BAKgDABEACAlmI/oIAAQDAAAA.Cyrn:BAAALgADCgEJAQAAAA==.',
['Cô']='Cômbustiôn:BAAALgAECgMJBAAAAA==.',
Da='Daddyweaver:BAABLgAECn8eAAIHAAgJvgwwCQBrAQAHAAgJvgwwCQBrAQAAAA==.Daegor:BAAALgAECgMJAwAAAA==.Dagun:BAAALgADCgIJAgAAAA==.Daisylight:BAAALgADCgMJAwAAAA==.Dakyu:BAAALgAECgEJAQAAAA==.Damitbobbi:BAAALgADCgEJAQAAAA==.Danazath:BAAALgAECgUJBgAAAA==.Danjaianka:BAAALgAECgIJAgAAAA==.Dansbouche:BAAALgAECgMJAwAAAA==.Darkerwarior:BAAALgAECgQJBgAAAA==.Darkkarma:BAAALgAECgYJDwAAAA==.Darkzeus:BAAALgAECgMJBgAAAA==.',
Dd='Ddeezn:BAAALgAECgkJDQAAAA==.',
De='Deadorcalive:BAAALgAECgMJAwAAAA==.Deathran:BAABLgAECn8cAAIKAAgJTBM5DgChAQAKAAgJTBM5DgChAQAAAA==.Declined:BAAALgADCgYJBgAAAA==.Decun:BAEALgAECgIJAgABLgAECggJHgAFAD8jAA==.Delfine:BAAALgADCgYJBgAAAA==.Delitia:BAAALgAECgcJEQAAAA==.Demonikillz:BAAALgADCgUJBwAAAA==.Despott:BAABLgAECn8aAAMBAAgJSRs4DQDhAQABAAgJSRs4DQDhAQATAAQJXgnLEAC1AAAAAA==.Dethfox:BAAALgAECgQJCwAAAA==.',
Di='Diampiece:BAAALgAECgMJAwAAAA==.Dinellihun:BAAALgAECgQJBQAAAA==.Dioni:BAABLgAECn8WAAICAAcJaxa4KQDHAQACAAcJaxa4KQDHAQAAAA==.',
Do='Dominants:BAAALgAECgQJCQAAAA==.Doomsdays:BAAALgAECgEJAQAAAA==.Doomsparkle:BAAALgAECgIJAgAAAA==.Dotterup:BAAALgADCgUJBgAAAA==.Doublehelix:BAAALgAECgUJCwAAAA==.',
Dr='Dracoboch:BAAALgAECgIJAgAAAA==.Draglox:BAAALgADCgMJAwAAAA==.Dragonmaipen:BAAALgAECgYJDgAAAA==.Drakkarth:BAAALgAECgYJEgAAAA==.Dravenm:BAABLgAECn8UAAIBAAYJKggPLwANAQABAAYJKggPLwANAQAAAA==.Dreamyblinks:BAAALgADCgIJAgAAAA==.Dremonhunter:BAAALgAECgEJAQAAAA==.Dreyden:BAAALgADCgMJAwAAAA==.Drift:BAAALgADCgMJAwAAAA==.Drunkendrago:BAAALgAECgQJBAAAAA==.',
Du='Duckboss:BAAALgADCgUJBwAAAA==.Dulfrim:BAAALgADCggJDAAAAA==.Dumbest:BAACLgAFFH8FAAIUAAMJfwjvLQDjAAAUAAMJfwjvLQDjAAAuAAQKfxQAAhQABwl/GWZYAOkBABQABwl/GWZYAOkBAAAA.',
['Dè']='Dèmonic:BAACLgAFFH8GAAIKAAIJpwb+OwCaAAAKAAIJpwb+OwCaAAAuAAQKfygAAgoACAlbGYUnAHMCAAoACAlbGYUnAHMCAAAA.',
['Dü']='Dürinn:BAAALgADCgQJCwAAAA==.',
Ea='Eastsideeyes:BAAALgAECgEJAQAAAA==.',
Eb='Ebonn:BAAALgADCgcJBwAAAA==.',
Ec='Echobloom:BAAALgAECgMJCAAAAA==.Echolaylee:BAAALgADCgQJBAABLgAECgMJCAADAAAAAA==.Ectoplasm:BAAALgAECgcJBwAAAA==.',
Ed='Eddiedagreat:BAAALgADCgEJAgAAAA==.',
Ee='Eeny:BAAALgAECgYJCgAAAA==.',
Eh='Ehud:BAAALgAFFAEJAQAAAA==.',
Ei='Eiemonk:BAACLgAFFH8KAAIOAAQJzQYXBgAVAQAOAAQJzQYXBgAVAQAuAAQKfx0AAg4ACAknHeYaAC0CAA4ACAknHeYaAC0CAAAA.',
El='Elaratorment:BAAALgADCgYJBgAAAA==.Elbori:BAAALgAECgEJAQAAAA==.Eldaral:BAAALgAECgcJBQAAAA==.Elderathion:BAAALgADCgIJAgAAAA==.Elfmas:BAAALgAECgIJAgAAAA==.Elianie:BAAALgADCgQJBAAAAA==.Ellinarilia:BAAALgADCgQJAgAAAA==.Elrithien:BAAALgAECgQJBAAAAA==.',
Em='Emwhun:BAAALgAECgMJBgABLgAECgYJCgADAAAAAA==.',
En='Entropy:BAAALgAECgYJCgAAAA==.',
Er='Erenore:BAAALgADCgcJCwAAAA==.Eriele:BAAALgADCgQJBAABLgAECgUJBQADAAAAAA==.',
Es='Eshaia:BAAALgAECgEJAQAAAA==.',
Et='Etalea:BAAALgAECgkJBwAAAA==.',
Ev='Eviaris:BAAALgADCgEJAQAAAA==.',
Fa='Faenyx:BAAALgAECgMJBQAAAA==.Faesmite:BAABLgAECn8dAAMHAAcJrBywFAA4AgAHAAcJrBywFAA4AgAVAAQJ1AjCEQDcAAAAAA==.Fairra:BAAALgAECgYJBwAAAA==.Faithh:BAAALgADCgQJBAAAAA==.Fanggs:BAAALgADCgQJBgAAAA==.Fanobattle:BAAALgADCgkJDgABLgAECgQJBQADAAAAAA==.Fanorage:BAAALgAECgQJBQAAAA==.Farvajr:BAAALgADCgcJBwAAAA==.Father:BAAALgADCgEJAgAAAA==.',
Fe='Fedusdeletus:BAAALgAECgUJBwAAAA==.Felic:BAAALgADCgUJBQAAAA==.Felixox:BAABLgAECn8VAAIWAAYJWAndKAD5AAAWAAYJWAndKAD5AAAAAA==.Felixxo:BAAALgADCgUJBQAAAA==.Felokali:BAABLgAECn8pAAIXAAkJuBCREAA4AgAXAAkJuBCREAA4AgAAAA==.Felrager:BAAALgADCgYJBgAAAA==.Ferocias:BAAALgADCgMJAwAAAA==.Fetty:BAAALgADCgUJCQAAAA==.',
Fi='Fiametta:BAAALgADCgcJEAAAAA==.Filianore:BAAALgAECgEJAgAAAA==.Filthyhobo:BAAALgADCgIJAgAAAA==.Finessier:BAABLgAECn8ZAAQQAAcJHx7KKgDTAQAQAAYJPR3KKgDTAQASAAQJwBGsIADYAAARAAEJjCL3rgBmAAAAAA==.Fipples:BAABLgAECn8UAAIFAAgJ1hvQPQD9AQAFAAgJ1hvQPQD9AQAAAA==.Fistasoup:BAAALgADCgQJBAAAAA==.',
Fl='Flaffergan:BAAALgAECgQJBgAAAA==.Florafae:BAAALgAECgIJAgAAAA==.Flugel:BAAALgADCgQJBAAAAA==.',
Fo='Focinnet:BAAALgAECgYJEAAAAA==.Foilwrapped:BAAALgADCgkJDgAAAA==.Fourform:BAAALgAECgYJDgAAAA==.',
Fr='Fraydknot:BAAALgADCgcJBwAAAA==.Frieren:BAAALgAECgYJDQAAAA==.Frostedfake:BAAALgADCgEJAQAAAA==.',
Fu='Fustervin:BAAALgAECgMJAwAAAA==.',
Ga='Gaalit:BAAALgAECgQJBwAAAA==.Galaxybone:BAABLgAECn8ZAAIUAAYJAB2fUgD6AQAUAAYJAB2fUgD6AQAAAA==.Galer:BAAALgAECgEJAQAAAA==.Galithiri:BAAALgAECgIJAgAAAA==.Gankorade:BAAALgAECgYJDAAAAA==.Ganthani:BAABLgAECn8YAAIHAAcJLhjKIwDIAQAHAAcJLhjKIwDIAQAAAA==.Ganthanor:BAAALgADCgQJBgAAAA==.Garzett:BAABLgAECn8fAAINAAgJUh1aAwAAAgANAAgJUh1aAwAAAgAAAA==.',
Gb='Gbonk:BAAALgADCgUJBQAAAA==.',
Ge='Geisterjäger:BAABLgAECn8fAAIYAAgJbRPGAgBwAQAYAAgJbRPGAgBwAQAAAA==.Gethalis:BAAALgADCgUJBgAAAA==.',
Gh='Ghouliana:BAAALgAECgYJBgABLgAECggJFgAZABojAA==.',
Gi='Giina:BAABLgAECn8dAAIaAAcJHxq3FwADAgAaAAcJHxq3FwADAgAAAA==.Girlypopxoxo:BAAALgADCgIJAgAAAA==.',
Go='Gooddik:BAAALgAECgYJBwAAAA==.Gooseburglar:BAAALgAECgMJBAAAAA==.Goosesnacks:BAAALgAECgEJAQAAAA==.Goots:BAAALgADCgYJBgAAAA==.Gordo:BAAALgAECgQJBwAAAA==.',
Gr='Grhm:BAABLgAECn8cAAMRAAgJKCLIBwATAwARAAgJKCLIBwATAwAQAAEJXwHTmAAdAAAAAA==.Griffin:BAAALgADCgYJCAAAAA==.Griffinlance:BAAALgAECgYJDAAAAA==.Grim:BAACLgAFFH8RAAIUAAYJLRttAQAeAgAUAAYJLRttAQAeAgAuAAQKfyAAAxQACQlII3gHAGUDABQACQlII3gHAGUDABsAAgmRIR4PAK4AAAAA.Grimskull:BAAALgADCgEJAQAAAA==.Grimvalde:BAAALgAECgQJBAAAAA==.Grinberryall:BAAALgAECgIJBAAAAA==.Grinshankz:BAAALgADCgcJDgAAAA==.Gromtor:BAAALgAECgcJEwABLgAFFAUJDgASAK0kAA==.Groos:BAAALgADCgEJAQAAAA==.',
Gu='Gulthor:BAAALgAECgMJAwAAAA==.',
Gw='Gwory:BAAALgAECgYJEAAAAA==.',
['Gá']='Gárp:BAABLgAECn8YAAIIAAcJwRBuOQDBAQAIAAcJwRBuOQDBAQAAAA==.',
['Gø']='Gøsa:BAAALgADCgcJDgAAAA==.',
Ha='Haeretik:BAAALgADCgEJAQAAAA==.Hagpag:BAAALgAECgUJDwAAAA==.Hallowmourne:BAABLgAECn8UAAMZAAcJmhu3IAAWAgAZAAcJmhu3IAAWAgAJAAMJZRdd3wDOAAAAAA==.Haramzadi:BAAALgAECgIJAwAAAA==.Harukà:BAAALgAECgUJDgAAAA==.Haven:BAAALgADCgMJAwAAAA==.Hawbinobs:BAABLgAECn8UAAIUAAgJpA8RYgDNAQAUAAgJpA8RYgDNAQAAAA==.',
He='Hecâte:BAAALgADCgUJCQAAAA==.Helfon:BAAALgAECgYJEQAAAA==.Helganelf:BAAALgADCgMJAwAAAA==.Hellenria:BAAALgADCggJFQAAAA==.',
Hi='Hibouu:BAAALgADCgYJCQAAAA==.Highlordtron:BAAALgAECgYJEwAAAA==.Hiira:BAAALgADCgUJBQAAAA==.Hinazuki:BAAALgADCgYJCAAAAA==.Hirro:BAAALgAECggJEgAAAA==.',
Ho='Holycharlie:BAABLgAECn8UAAIEAAcJHiEVBgCLAgAEAAcJHiEVBgCLAgAAAA==.Holydudy:BAAALgAECgQJBAAAAA==.Holyely:BAAALgAECgYJCgAAAA==.Holynutzz:BAAALgADCgEJAQAAAA==.Holyvez:BAAALgAECgEJAgAAAA==.Holyvoids:BAAALgADCgcJDQAAAA==.Hondodk:BAEALgAFFAEJAgABLgAFFAUJDgAUAKwhAA==.Hoodlum:BAAALgADCgUJBgAAAA==.Hoodlumxdk:BAAALgADCgcJCAAAAA==.Horegan:BAAALgAECgUJCgAAAA==.Hotguymilker:BAAALgAECggJCQAAAA==.Hotnhard:BAAALgAFFAEJAQAAAA==.Howiedewit:BAAALgADCgQJBwAAAA==.Howlupine:BAAALgAECgIJAgAAAA==.',
Hy='Hysterium:BAAALgAECgIJAgAAAA==.',
Ik='Ikki:BAAALgAECgkJEgAAAA==.',
Il='Iliraelis:BAAALgAECgEJAQAAAA==.Ilirranna:BAAALgAECgcJDwAAAA==.Ilith:BAAALgAECgYJEQAAAA==.Illegal:BAAALgAECgEJAgAAAA==.',
In='Infi:BAACLgAFFH8PAAMQAAUJwSMbBAD7AQAQAAUJwSMbBAD7AQARAAEJmA8WFQBYAAAuAAQKfyIAAhAACAm5IwwGADoDABAACAm5IwwGADoDAAAA.Initapoop:BAAALgAECgUJBQAAAA==.',
Io='Ioannis:BAAALgAECgMJBQAAAA==.',
Ir='Ironstrike:BAAALgAECgIJAgAAAA==.',
Is='Isos:BAABLgAECn8hAAMXAAgJ9STwAgBEAwAXAAgJ9STwAgBEAwAHAAEJPxAVfAA4AAAAAA==.Isus:BAAALgADCggJCwAAAA==.',
Iv='Ivander:BAAALgADCgMJAwAAAA==.',
Iw='Iweorn:BAAALgADCgEJAQAAAA==.',
Iy='Iykyk:BAAALgAECgEJAQABLgAECgYJEQADAAAAAA==.',
Iz='Izuchi:BAAALgADCgcJEQAAAA==.Izzwizz:BAAALgAECgMJBAAAAA==.',
Ja='Jaded:BAABLgAECn8dAAIcAAgJPyFOCAD1AgAcAAgJPyFOCAD1AgAAAA==.Jaksi:BAAALgAECgYJDgAAAA==.Jangutu:BAAALgADCggJCAAAAA==.Jarlaxl:BAAALgAECgQJBwAAAA==.Javyr:BAAALgAECgMJAwAAAA==.Jaysdruid:BAAALgADCgUJBgAAAA==.Jayskrt:BAAALgADCgEJAgAAAA==.',
Je='Jearik:BAAALgADCgcJCAAAAA==.Jef:BAAALgADCgUJCAAAAA==.',
Ji='Jijí:BAAALgADCgUJBQAAAA==.Jimmyegs:BAAALgADCgMJAwAAAA==.Jinurzah:BAAALgADCgcJDAAAAA==.',
Jl='Jlnxy:BAABLgAECn8UAAIJAAYJYwRKNADJAAAJAAYJYwRKNADJAAAAAA==.',
Jo='Jokerld:BAAALgAECgEJAQAAAA==.Josiae:BAAALgADCgMJAwAAAA==.',
Jw='Jward:BAAALgAECgQJBAAAAA==.',
Ka='Kaagu:BAAALgADCgQJBAAAAA==.Kadzilak:BAAALgADCgYJEAAAAA==.Kagemika:BAAALgADCgkJFQAAAA==.Kaizumie:BAABLgAECn8WAAIZAAgJGiP9CADgAgAZAAgJGiP9CADgAgAAAA==.Kalmojor:BAAALgADCgcJBwAAAA==.Karlhungus:BAAALgADCgMJAwAAAA==.Karmaniac:BAAALgAECgIJAgAAAA==.Karu:BAAALgADCgcJEQAAAA==.Kawaiikutie:BAAALgAECgEJAQAAAA==.Kayonna:BAAALgADCgcJCAABLgAECggJHQAVAIUUAA==.Kaypop:BAAALgADCgYJEwAAAA==.',
Ke='Keastral:BAAALgAECgQJBQAAAA==.Keeshawn:BAAALgAECgEJAQAAAA==.Keldanis:BAABLgAECn8UAAQRAAcJrBowHgBRAgARAAcJrBowHgBRAgASAAMJ9QkUJQCgAAAQAAMJBAVqcgB0AAAAAA==.Kenbone:BAAALgADCgUJBQAAAA==.Keony:BAAALgAECgYJEQAAAA==.Kerthur:BAAALgAECgYJDwAAAA==.',
Kh='Khaalandrun:BAAALgAECgIJAgAAAA==.',
Ki='Kiaarly:BAAALgADCgUJBQABLgAECgUJDwADAAAAAA==.Kieloesh:BAAALgAECgIJAgABLgAECgYJCgADAAAAAA==.Killamanjara:BAAALgADCgEJAQAAAA==.Killercj:BAAALgADCgMJAwAAAA==.Kirokote:BAAALgADCgIJAgAAAA==.Kitch:BAAALgADCgcJCAAAAA==.Kittyarly:BAAALgAECgUJDwAAAA==.Kiwee:BAAALgAECgIJAQAAAA==.',
Kj='Kjetil:BAAALgADCgMJAwAAAA==.',
Kl='Kleptoria:BAAALgADCgUJBgAAAA==.',
Kn='Kneeler:BAAALgADCgcJBgAAAA==.',
Ko='Kodeck:BAAALgADCgEJAQAAAA==.Kodokan:BAAALgADCgYJDwAAAA==.Koffey:BAAALgADCgUJBwAAAA==.Kopigyatt:BAAALgADCggJDAABLgAECgcJCwADAAAAAA==.Koshima:BAABLgAECn8eAAICAAgJnRGhBwCKAQACAAgJnRGhBwCKAQAAAA==.Kozan:BAAALgAECgYJCgAAAA==.',
Kr='Krialin:BAABLgAECn8ZAAIJAAgJEB/oFgDfAgAJAAgJEB/oFgDfAgAAAA==.Krimhit:BAAALgAECgQJCgAAAA==.Kronkley:BAABLgAECn8WAAIOAAgJABcVHQAaAgAOAAgJABcVHQAaAgAAAA==.',
Ku='Kudranne:BAAALgAECgEJAQABLgAECgIJAgADAAAAAA==.Kugia:BAABLgAECn8UAAIdAAcJOhhfKgAIAgAdAAcJOhhfKgAIAgABLgAECgcJFgACAGsWAA==.Kunthax:BAAALgADCgQJBAAAAA==.Kuore:BAAALgAECgIJAgAAAA==.Kuorii:BAAALgADCgMJAwABLgAECgIJAgADAAAAAA==.Kuraba:BAAALgADCgIJAgAAAA==.Kushtusk:BAAALgAECgUJBgAAAA==.',
Ky='Kynndell:BAAALgADCgcJEAAAAA==.Kyo:BAAALgAECgQJBAAAAA==.',
['Kø']='Køkushibø:BAAALgADCgYJCgAAAA==.',
La='Lanasrin:BAABLgAECn8UAAIJAAcJtCa/DgAYAwAJAAcJtCa/DgAYAwAAAA==.Lanastaul:BAAALgADCgQJBAABLgAECggJHQAGAHkYAA==.Lantheiel:BAAALgAECgEJAQAAAA==.Laralana:BAAALgAECgYJEQAAAA==.Lazrin:BAAALgADCgIJAgAAAA==.',
Le='Leadzeplin:BAAALgADCgEJAQAAAA==.Leetheal:BAACLgAFFH8JAAIHAAMJ8hTIBwDuAAAHAAMJ8hTIBwDuAAAuAAQKfx0AAwcACQl6IOsDABgDAAcACQl6IOsDABgDABUAAQkoFvdbAEUAAAAA.Lekromancer:BAAALgAECgEJAQAAAA==.Lelethxx:BAAALgAECgEJAQAAAA==.Leraxx:BAAALgAECgEJAQAAAA==.Lerrax:BAAALgAECgIJAQAAAA==.Lesanna:BAABLgAECn8UAAIPAAcJtQkvLgBbAQAPAAcJtQkvLgBbAQAAAA==.Lesslie:BAAALgADCggJCAAAAA==.Leåwer:BAAALgAECgQJBAAAAA==.',
Li='Lilbitzz:BAAALgADCgkJCQAAAA==.Lilheal:BAAALgAECgQJBQAAAA==.Lionël:BAAALgAECgYJCgAAAA==.Lirielle:BAAALgADCgcJDAAAAA==.Lisax:BAAALgADCgMJAwAAAA==.Literocola:BAAALgADCgQJBAAAAA==.Lizbethe:BAABLgAECn8dAAMVAAgJhRTjAwDsAQAVAAgJhRTjAwDsAQAXAAYJpxwzFwDmAQAAAA==.',
Lo='Loltank:BAAALgADCgcJDgAAAA==.Lopi:BAABLgAECn8UAAIKAAcJ6APKoAAWAQAKAAcJ6APKoAAWAQAAAA==.Lorshadow:BAAALgADCgYJBwAAAA==.Lorwater:BAAALgADCgcJCQAAAA==.Lorynden:BAAALgAECgQJBAAAAA==.Lovach:BAAALgAECgQJDAAAAA==.Loveinfinity:BAAALgAECgUJDgAAAA==.Lovington:BAAALgAECgMJAwABLgAFFAIJBgAKAKcGAA==.',
Lu='Lu:BAAALgADCgYJBgABLgAECgUJCQADAAAAAA==.Luandria:BAAALgAECggJDQAAAA==.Lugostiglitz:BAAALgAECgEJAQAAAA==.Luminas:BAAALgADCgIJAgAAAA==.Lumí:BAAALgAECgEJAQAAAA==.Lunchboss:BAAALgADCgEJAQAAAA==.Lurelune:BAAALgAECgEJAQABLgAECggJHQAGAHkYAA==.Luxaria:BAAALgAECgUJBQAAAA==.Luxx:BAAALgADCgQJBAABLgAECgcJHwAMAKQeAA==.',
Ly='Lylek:BAAALgAECgYJBgAAAA==.',
Ma='Mackie:BAAALgADCgUJBQABLgAECgQJBAADAAAAAA==.Maelbeq:BAABLgAECn8XAAIeAAgJohSPBwBEAgAeAAgJohSPBwBEAgAAAA==.Maevelles:BAAALgADCgUJBwAAAA==.Mag:BAAALgADCgUJBQAAAA==.Magewain:BAAALgADCgUJBQAAAA==.Mageypoo:BAABLgAECn8UAAIBAAgJ/iGyGwAIAwABAAgJ/iGyGwAIAwAAAA==.Magicpickle:BAAALgADCgkJEQABLgAECgQJCQADAAAAAA==.Maine:BAAALgAECgQJBAAAAA==.Malakarth:BAAALgADCgEJAgAAAA==.Malathar:BAAALgAECgUJCAAAAA==.Mallowe:BAAALgADCgMJAwAAAA==.Malson:BAAALgADCgMJBAAAAA==.Marcelxd:BAAALgAECgMJAwAAAA==.Martinjc:BAAALgAECgYJBgAAAA==.Martinlw:BAAALgADCgUJBQAAAA==.Martinte:BAAALgADCgcJAgAAAA==.Masambula:BAAALgADCgEJAQAAAA==.Mavering:BAAALgADCgEJAQAAAA==.Mayaa:BAAALgADCgMJAwAAAA==.Mayaesp:BAAALgADCgMJAwAAAA==.',
Me='Meene:BAAALgAECgYJDAAAAA==.Meepderp:BAAALgAECgcJBwABLgAFFAMJBQARABIdAA==.Mehaz:BAAALgADCgYJBgAAAA==.Memeep:BAACLgAFFH8FAAIRAAMJEh03CAAhAQARAAMJEh03CAAhAQAuAAQKfycAAxEACQmDJHgAANEDABEACQmDJHgAANEDABAAAgnYBYt8AFIAAAAA.Meowely:BAAALgADCgYJCgAAAA==.Merry:BAAALgAECgEJAQAAAA==.Meshshift:BAAALgADCgIJAQAAAA==.',
Mi='Miggs:BAAALgADCgEJAQAAAA==.Milfshotz:BAAALgAECggJDgAAAA==.Mimidésy:BAAALgADCgEJAQAAAA==.Minimiyagi:BAAALgAECgEJAQAAAA==.Missbehavior:BAAALgADCgYJBgAAAA==.Misscariina:BAAALgADCgEJAQAAAA==.Missmouthoff:BAAALgAECgcJDwAAAA==.Mistralwind:BAAALgADCgEJAQABLgAECgIJAgADAAAAAA==.Miztärjake:BAAALgADCgcJCAAAAA==.Mizzxgummy:BAAALgAECgcJBwAAAA==.',
Mo='Modush:BAAALgADCgUJBQAAAA==.Moldytoast:BAAALgADCgcJCAAAAA==.Monkstaar:BAAALgADCgEJAQAAAA==.Moogan:BAAALgAECgIJAgAAAA==.Mooneyes:BAAALgADCgcJHAAAAA==.Moonfishing:BAABLgAECn8aAAIBAAgJ3w0idgDmAQABAAgJ3w0idgDmAQAAAA==.Moonfly:BAAALgAECgYJDQAAAA==.Moonmoonpand:BAAALgADCgEJBAAAAA==.Moorea:BAAALgAECgYJCQAAAA==.Morax:BAAALgADCgkJEQAAAA==.Moubu:BAAALgAECgEJAgAAAA==.Mouton:BAAALgAECgMJBAAAAA==.Mozumi:BAABLgAECn8TAAIKAAYJEB5MDgCgAQAKAAYJEB5MDgCgAQAAAA==.',
Mu='Munn:BAABLgAECn8aAAMBAAgJxxYbTgBNAgABAAgJxxYbTgBNAgATAAUJHw8qDAAPAQAAAA==.Murag:BAAALgAECgYJEwAAAA==.Mureum:BAAALgADCgEJAQAAAA==.',
['Mä']='Mächtig:BAAALgADCgEJAQAAAA==.',
Na='Nalä:BAAALgADCgUJBAAAAA==.Nammi:BAAALgADCgUJBQAAAA==.Nardorne:BAAALgADCgcJBwAAAA==.Natsumy:BAABLgAECn8UAAIKAAcJRQr5eABqAQAKAAcJRQr5eABqAQAAAA==.',
Ne='Nearhammer:BAAALgAECgQJBAAAAA==.Nearsear:BAAALgADCgcJCQAAAA==.Nefariouz:BAAALgAECgkJCAAAAA==.Nervouz:BAAALgAECggJDwABLgAECgYJFwAGAH4FAA==.Nezarly:BAAALgADCgkJDQAAAA==.Nezukochan:BAAALgAECgEJAQAAAA==.',
Ni='Nicky:BAAALgADCgYJBgAAAA==.Nitrøus:BAAALgAECgEJAQAAAA==.',
No='Nobbs:BAAALgADCgkJEgAAAA==.Noctis:BAAALgADCgUJBQAAAA==.Nohhozwa:BAAALgAECgYJCgAAAA==.Nool:BAAALgADCgcJCgAAAA==.Nosaj:BAAALgAECgYJEAAAAA==.Notacow:BAAALgADCgUJAQAAAA==.Notzombie:BAAALgADCgIJAgAAAA==.Noxx:BAAALgAECgUJBgAAAA==.',
Nu='Nualaperafin:BAABLgAECn8kAAIfAAkJYBz1AgANAwAfAAkJYBz1AgANAwAAAA==.',
Ny='Nysellia:BAAALgADCgcJCgAAAA==.Nyvara:BAAALgAECgMJAwAAAA==.',
Oc='Ocularagon:BAAALgADCgEJAgAAAA==.',
Ol='Olayro:BAABLgAECn8UAAIKAAYJ8AZonQAeAQAKAAYJ8AZonQAeAQAAAA==.',
Om='Omez:BAAALgAECgIJAgAAAA==.Omut:BAAALgAECgcJCQAAAA==.',
On='Onlymilkers:BAAALgADCgEJAQAAAA==.Onsight:BAAALgAECgQJBAAAAA==.',
Oo='Ookabooka:BAAALgAECgEJAQAAAA==.Oopsiedaisy:BAAALgAECgUJCwAAAA==.',
Or='Orangeburn:BAAALgADCgUJBgAAAA==.Orestes:BAAALgAECgYJCwAAAA==.',
Ow='Owillo:BAAALgAECgEJAQAAAA==.',
Pa='Pacadin:BAAALgAECgQJBAAAAA==.Palaguy:BAAALgADCgEJAQAAAA==.Paleie:BAAALgADCgcJDAABLgAFFAQJCgAOAM0GAA==.Palokarhu:BAAALgADCgIJAgAAAA==.Panterra:BAAALgADCgIJAgABLgADCgQJBAADAAAAAA==.Papacy:BAAALgADCgIJAgAAAA==.Pathran:BAAALgADCgcJDAAAAA==.',
Pe='Peeonsnow:BAAALgAECgYJBgAAAA==.Pellias:BAAALgADCgQJBAAAAA==.Pendrix:BAAALgADCgkJFAAAAA==.Pennerixi:BAAALgAECgkJBAAAAA==.Perzeval:BAAALgAECgYJDAAAAA==.Perzevel:BAAALgAECgEJAgAAAA==.',
Ph='Pharmacology:BAAALgAECgQJDgAAAA==.Phénicie:BAAALgADCgUJBQAAAA==.',
Pi='Pieceofchit:BAAALgADCgUJBQAAAA==.',
Pj='Pjb:BAAALgADCgMJAwAAAA==.',
Pl='Plankton:BAAALgAECgQJCQAAAA==.',
Po='Pocholate:BAAALgADCgEJAQAAAA==.Popa:BAAALgAECgEJAQAAAA==.Potatofat:BAAALgADCgUJCgAAAA==.',
Pr='Prathe:BAAALgAECgcJEgAAAA==.Prayformee:BAAALgADCgYJDAAAAA==.Priestpriest:BAAALgADCgEJAQAAAA==.',
Ps='Psiloci:BAAALgADCgEJAQABLgAECggJGwANAFMZAA==.Psilocy:BAABLgAECn8bAAINAAgJUxnwAwDsAQANAAgJUxnwAwDsAQAAAA==.',
Pu='Puddiintoo:BAAALgAECgYJDQAAAA==.Pulsate:BAAALgAECgUJBQAAAA==.Purplechem:BAAALgAECgMJAwAAAA==.',
Qa='Qaucker:BAABLgAECn8aAAMHAAgJGhkzAgBXAgAHAAgJGhkzAgBXAgAXAAYJowZ7MAAcAQAAAA==.',
Qi='Qiz:BAAALgAECgYJEgAAAA==.Qizard:BAAALgADCgMJAwAAAA==.',
Qj='Qjq:BAAALgAECgMJAwAAAA==.',
Qu='Quintarite:BAAALgADCgMJAwAAAA==.Quistas:BAAALgAECgMJBAAAAA==.',
Ra='Radlock:BAAALgAECgIJAwAAAA==.Radwaran:BAAALgADCgYJCAAAAA==.Rahma:BAAALgADCgEJAgAAAA==.Raincal:BAABLgAECn8bAAINAAgJqRY7IAD8AQANAAgJqRY7IAD8AQAAAA==.Rainsford:BAAALgADCgEJAQAAAA==.Rakchu:BAAALgAECgQJBQAAAA==.Randios:BAAALgADCgMJAwAAAA==.Ranfalem:BAAALgADCgYJCAAAAA==.Rasto:BAABLgAECn8ZAAIgAAgJWguYPQCLAQAgAAgJWguYPQCLAQAAAA==.Rausrunebane:BAAALgADCgIJAwAAAA==.Ravokh:BAAALgADCgYJCgAAAA==.',
Re='Redhand:BAAALgADCgYJBgAAAA==.Regolas:BAAALgADCgcJBwAAAA==.Relentlezz:BAAALgADCgIJAgAAAA==.Relica:BAAALgAECgcJEQAAAA==.Restalan:BAAALgADCgEJAQAAAA==.Revki:BAAALgAECgEJAQAAAA==.Revolvr:BAABLgAECn8cAAIhAAgJbR6SAQAKAwAhAAgJbR6SAQAKAwAAAA==.Reïgn:BAAALgADCgUJBQAAAA==.',
Ri='Ridire:BAAALgAECgYJCgAAAA==.Riptidus:BAACLgAFFH8JAAIgAAMJRBN1BwDdAAAgAAMJRBN1BwDdAAAuAAQKfxoAAyAACAkYFsgiAA4CACAACAkYFsgiAA4CAAIAAQksBTqPACgAAAAA.Ripzly:BAAALgAECgQJBAAAAA==.Ritalin:BAAALgADCgcJCwAAAA==.Rizzakk:BAAALgADCgcJBAAAAA==.',
Ro='Rogawr:BAAALgADCgEJAQAAAA==.Roguemas:BAAALgADCggJDQAAAA==.Ropeshooter:BAAALgADCgMJAwAAAA==.Roxus:BAAALgAECgMJAwAAAA==.',
Ru='Rubberduck:BAAALgADCgYJBgAAAA==.Rudabaga:BAAALgADCgEJAQAAAA==.Rumî:BAAALgAFFAEJAQAAAA==.Runaf:BAAALgADCgkJCgAAAA==.Runhauf:BAAALgAECgYJBwAAAA==.Runts:BAAALgAECgQJBAAAAA==.',
Ry='Ryuni:BAAALgAECgEJAQAAAA==.',
Sa='Sabellal:BAAALgADCgQJBAAAAA==.Sacredaura:BAAALgAECgMJBAAAAA==.Saegusa:BAAALgADCgYJCQAAAA==.Safedruid:BAAALgADCgUJCAABLgADCgEJAQADAAAAAA==.Samhain:BAAALgADCgEJAQAAAA==.Samshamwow:BAAALgADCgMJAwABLgAFFAMJBQAiAPsEAA==.Saneseth:BAAALgAECgYJEQAAAA==.Sangomia:BAABLgAFFH8KAAIUAAQJriIQBAByAQAUAAQJriIQBAByAQAAAA==.Saniblaze:BAAALgADCgQJBwAAAA==.Sanlanesh:BAAALgADCgIJAgAAAA==.Sarrazine:BAAALgAECgQJBQAAAA==.Sasive:BAAALgAECgUJBwAAAA==.Sassbringer:BAAALgAECgIJAgAAAA==.Sayani:BAAALgAECgQJBAAAAA==.',
Sc='Schmall:BAAALgAECgYJEwAAAA==.Scärlët:BAABLgAECn8eAAIHAAgJQBtzAwAaAgAHAAgJQBtzAwAaAgAAAA==.',
Se='Secrient:BAABLgAECn8hAAIUAAgJeh9JCQDqAQAUAAgJeh9JCQDqAQAAAA==.Selume:BAAALgADCgcJCAAAAA==.Selvalin:BAAALgADCgIJAgAAAA==.Sevyn:BAAALgAECgEJAwAAAQ==.Sevynari:BAAALgAECgQJBQABLgAECgEJAwADAAAAAQ==.',
Sh='Shadowmeres:BAAALgAECgEJAQAAAA==.Shamtaar:BAAALgADCgMJAwAAAA==.Shestalker:BAAALgAECgMJAwAAAA==.Shieldheart:BAAALgADCgYJCwAAAA==.Shielpruuf:BAAALgAECgEJAQAAAA==.Shiift:BAAALgAECgYJDAAAAA==.Sholl:BAAALgAECgYJDgAAAA==.Sholls:BAABLgAECn8UAAMjAAcJthrHCQABAgAjAAcJthrHCQABAgAiAAIJ8gvoKwBmAAAAAA==.Shurpi:BAAALgADCgEJAQAAAA==.',
Si='Siandena:BAAALgADCgQJBgAAAA==.Sieguer:BAAALgADCgEJAQAAAA==.Sigismund:BAAALgAECgEJAQAAAA==.Sillygøøsey:BAAALgADCgIJAgAAAA==.Silvaine:BAAALgAECgYJCgAAAA==.',
Sk='Skalitzath:BAAALgADCgQJAwAAAA==.Skarlax:BAAALgADCgEJAQABLgAECggJFgAZABojAA==.Skkits:BAAALgAECgMJAwAAAA==.Skrunkle:BAAALgAECgIJBAABLgAECggJHgAUAEwRAA==.Skulshooter:BAAALgADCgQJBAAAAA==.',
Sl='Slarhan:BAAALgADCgEJAQAAAA==.',
Sm='Smibaco:BAAALgAECgEJAQAAAA==.Smushbush:BAABLgAECn8YAAIJAAYJdyM/NABRAgAJAAYJdyM/NABRAgAAAA==.Smushinbush:BAAALgADCgEJAQABLgAECgYJGAAJAHcjAA==.Smushyobush:BAAALgAECgcJBwABLgAECgYJGAAJAHcjAA==.',
Sn='Snicklefritz:BAAALgAECgQJBAABLgAECgYJCwADAAAAAA==.Snipez:BAAALgADCgMJAwAAAA==.Snortymcdash:BAAALgAECgYJBgAAAA==.',
So='Solclipeus:BAACLgAFFH8HAAIEAAMJJBN3AQDAAAAEAAMJJBN3AQDAAAAuAAQKfyYAAwQACAmDIuQCAPkCAAQACAmDIuQCAPkCAAkACAmEEjBVAOIBAAAA.Soldh:BAAALgADCgYJBwABLgAFFAMJBwAEACQTAA==.Soulton:BAAALgAECgQJBQAAAA==.Souperscott:BAAALgAECgIJAgAAAA==.Soupz:BAABLgAECn8WAAIJAAYJ9x//OQA7AgAJAAYJ9x//OQA7AgAAAA==.',
Sp='Spaghett:BAAALgAECgcJEwAAAA==.Sparkev:BAAALgADCgYJDAAAAA==.Spongebobytp:BAAALgADCgEJAQAAAA==.Springburn:BAAALgADCgUJBQAAAA==.',
Sq='Squiddy:BAAALgAECgEJAQAAAA==.',
Sr='Sririacha:BAABLgAECn8dAAMGAAgJeRiBEgBWAgAGAAgJeRiBEgBWAgAkAAQJFArPKwC+AAAAAA==.',
St='Stabbyabby:BAAALgADCggJCAAAAA==.Statík:BAAALgADCgMJBgAAAA==.Steelbane:BAAALgADCgEJAQAAAA==.Stewy:BAAALgADCgYJCQAAAA==.Strånge:BAABLgAECn8WAAMBAAYJTyHChADIAQABAAYJTyHChADIAQAlAAEJdQU1EQAtAAAAAA==.Stìtch:BAABLgAECn8qAAMLAAgJ6RetCAA2AgALAAgJ6RetCAA2AgAKAAMJ1w0w2wCjAAAAAA==.',
Su='Succubetch:BAAALgAECgYJCgAAAA==.Sukiafaunias:BAAALgAECgUJBQAAAA==.Sumirishade:BAAALgAECgIJAgAAAA==.Suoop:BAAALgAECgMJAwAAAA==.Surgeclaw:BAAALgAECgQJCgAAAA==.Suziedh:BAAALgAECgEJAQAAAA==.',
Sw='Switchbladez:BAAALgADCggJDAAAAA==.',
['Sì']='Sìx:BAAALgAECgYJDQAAAA==.',
['Sï']='Sïxx:BAAALgADCgcJCgABLgAECgYJDQADAAAAAA==.',
['Sø']='Søÿsåûçê:BAAALgAECgEJAQABLgAECgcJJAAOAA8eAA==.',
Ta='Taeril:BAAALgAECgIJAgAAAA==.Taezanx:BAAALgADCgcJBwAAAA==.Tahm:BAABLgAECn8YAAIaAAgJ+xx8AwAVAgAaAAgJ+xx8AwAVAgAAAA==.Tambel:BAAALgADCgQJBAAAAA==.Tanburn:BAAALgAECgQJDgAAAA==.Tanduinex:BAAALgADCgcJFgAAAA==.Tanrobby:BAAALgADCgUJCQAAAA==.Tanthe:BAAALgADCgYJBgAAAA==.Tapae:BAAALgADCgYJBgAAAA==.Taterrot:BAAALgADCgMJAwAAAA==.Tatsumy:BAAALgAECgUJCwAAAA==.',
Tc='Tcdathirsty:BAAALgADCgYJCQAAAA==.Tcmon:BAABLgAECn8VAAQRAAYJvxITWgBZAQARAAUJwRYTWgBZAQASAAIJAwJzKwBMAAAQAAMJkgHkfgBKAAAAAA==.',
Te='Teaghan:BAAALgAECgYJCwAAAA==.Teaglizzy:BAACLgAFFH8FAAIJAAMJPAqeDwCoAAAJAAMJPAqeDwCoAAAuAAQKfywAAgkACQlzGqoaAMkCAAkACQlzGqoaAMkCAAAA.Teancm:BAAALgADCgUJBQAAAA==.Tedward:BAAALgADCgQJBAAAAA==.Teehole:BAABLgAECn8VAAIJAAgJpgwmdgCOAQAJAAgJpgwmdgCOAQAAAA==.Tempert:BAAALgADCgYJBgAAAA==.Termytree:BAAALgADCgcJBwAAAA==.Terorblade:BAAALgADCgUJBQAAAA==.',
Th='Thaetrois:BAAALgADCgMJBAAAAA==.Thanussy:BAAALgAECggJDwAAAA==.Thebean:BAAALgADCgQJBAAAAA==.Thebigtuna:BAAALgAECgYJCgAAAA==.Thegodpvp:BAAALgADCgEJAQAAAA==.Theladydruid:BAABLgAECn8fAAMNAAgJSBTsBADIAQANAAgJSBTsBADIAQAdAAcJWwjyYwAmAQAAAA==.Thestashman:BAAALgAECgcJCAAAAA==.Thexalia:BAAALgADCgkJCQAAAA==.Thighsoffel:BAAALgADCgcJCwAAAA==.Thordam:BAAALgADCgkJCQAAAA==.Threetee:BAAALgADCgQJCAAAAA==.Threnador:BAAALgAECgQJBgAAAA==.Thyrena:BAAALgADCgMJAwAAAA==.',
Ti='Tierrasbe:BAAALgADCggJEQAAAA==.Tigerpa:BAAALgAECgkJBgAAAA==.Tinkernut:BAAALgADCgEJAQAAAA==.Tinysmites:BAAALgAECgUJBgAAAA==.Tinythia:BAABLgAECn8fAAIBAAgJCBRQDgDVAQABAAgJCBRQDgDVAQAAAA==.Tioklarus:BAAALgAECgYJDQAAAA==.',
To='Tofulady:BAABLgAECn8dAAIaAAcJoSUSAgBsAgAaAAcJoSUSAgBsAgAAAA==.Torokun:BAAALgADCgUJBwAAAA==.',
Tr='Trashbunny:BAAALgADCgEJAQAAAA==.Traystiria:BAAALgAECgIJAwAAAA==.Trazin:BAAALgADCgEJAQAAAA==.Treesothorny:BAAALgAECgYJCwAAAA==.Triscüit:BAAALgAECgUJCAAAAA==.Truemoosiah:BAAALgADCgYJCwAAAA==.Trébol:BAAALgAECgEJAQAAAA==.Tròll:BAAALgADCgYJBwAAAA==.',
Tu='Turlok:BAAALgAECgYJCwABLgAECgYJCgADAAAAAA==.',
Tw='Twotwotrain:BAAALgAECgUJCAAAAA==.',
Ty='Tyania:BAAALgADCggJCAABLgAECgEJAQADAAAAAA==.',
Ul='Ulukki:BAAALgADCgIJAwAAAA==.',
Um='Umbralpickle:BAAALgAECgQJCQAAAA==.',
Un='Uncleiroh:BAAALgAECgYJCwAAAA==.Unhowly:BAABLgAECn8bAAIUAAgJ9BsULgCAAgAUAAgJ9BsULgCAAgAAAA==.Unrealwushu:BAAALgADCgEJAQAAAA==.Unredeadzomb:BAAALgADCgQJBAAAAA==.Untaintedp:BAAALgADCgEJAQAAAA==.',
Ur='Urgelgru:BAAALgAECggJDgAAAA==.Ursaluna:BAAALgADCgcJBgABLgAECggJEgADAAAAAA==.',
Va='Valhalah:BAAALgADCgUJCAAAAA==.Vapidos:BAAALgAECgIJAgAAAA==.Varlug:BAAALgAECgQJBAAAAA==.Varynxiv:BAAALgAECgIJAgABLgAECgQJBQADAAAAAA==.Vatica:BAAALgAECgQJBAAAAA==.Vauik:BAABLgAECn8eAAIUAAgJTBFhEQCJAQAUAAgJTBFhEQCJAQAAAA==.',
Ve='Vealeriadk:BAACLgAFFH8TAAMUAAYJlx9lAAACAgAUAAUJgR9lAAACAgAmAAQJ7iBnBABmAQAuAAQKfx4ABBQACAm5JYYUAAADABQACAmCJYYUAAADACYAAwkFJlggAEIBABsAAQk9IjoTAF4AAAAA.Venatorr:BAAALgADCgcJBwAAAA==.Venvalzhar:BAAALgAECgYJBgAAAA==.Venyym:BAAALgADCgcJCAAAAA==.Veras:BAAALgAECgEJAQAAAA==.Vestammeni:BAAALgAECgEJAQAAAA==.Vexz:BAAALgAECgQJBAABLgAECgYJFAAIAL8gAA==.',
Vl='Vladmiir:BAAALgAECgcJBwAAAA==.',
Vo='Voidtool:BAAALgADCgIJAgAAAA==.Vosagus:BAAALgAECgEJAgABLgAECggJFgAOAAAXAA==.',
['Vê']='Vêzz:BAABLgAECn8hAAICAAgJERlCHgAdAgACAAgJERlCHgAdAgAAAA==.',
Wc='Wckd:BAABLgAECn8cAAIEAAcJ7ReNEAC9AQAEAAcJ7ReNEAC9AQAAAA==.Wckdwar:BAAALgAECgcJBwAAAA==.',
We='Weedvegeta:BAAALgAECgYJDAAAAA==.Weinerslam:BAAALgADCgYJEAAAAA==.Wells:BAAALgADCgEJAQAAAA==.Wendego:BAAALgADCgMJAwAAAA==.Wernbirn:BAAALgAECggJBQAAAA==.Wetremin:BAAALgAECgYJCwAAAA==.',
Wh='Whiplashh:BAAALgAECgMJAwAAAA==.Whiry:BAAALgAECgYJCgAAAA==.Whirzy:BAAALgADCgUJBQAAAA==.Whitebeard:BAAALgAECgEJAQAAAA==.Whizkee:BAABLgAECn8XAAIVAAcJ9xX9BgCOAQAVAAcJ9xX9BgCOAQAAAA==.',
Wi='Willowpuff:BAAALgAFFAEJAQAAAA==.Wingedlady:BAAALgAECgUJBQAAAA==.Wiskerbiskit:BAAALgAECgQJBAAAAA==.Wiskitbisker:BAACLgAFFH8GAAIUAAMJewrKEADvAAAUAAMJewrKEADvAAAuAAQKfxYAAhQABwkJGhVKABUCABQABwkJGhVKABUCAAAA.',
Wo='Worldgods:BAAALgADCgcJCwAAAA==.',
Wp='Wpnocturne:BAAALgAECgUJCQAAAA==.',
Wt='Wtfomgbbqftw:BAAALgAECgEJAQAAAA==.',
Wu='Wushu:BAAALgAECgUJDAAAAA==.',
Wy='Wyl:BAAALgAECgUJCQAAAA==.Wyrdfell:BAAALgADCgEJAQAAAA==.',
Xa='Xanthian:BAAALgADCgUJCwAAAA==.Xarrath:BAAALgADCgUJBQAAAA==.',
Xe='Xemro:BAAALgAECgQJBAAAAA==.Xendai:BAAALgAECgQJCgAAAA==.',
Xh='Xhyro:BAAALgAECgUJBQAAAA==.',
Xi='Xiing:BAAALgAECgYJDwAAAA==.',
Xn='Xneutron:BAAALgAECgUJCwAAAA==.',
Xt='Xtravagent:BAAALgAECgYJEQAAAA==.',
Xy='Xynthris:BAABLgAECn8hAAIQAAgJUhVLAgC2AQAQAAgJUhVLAgC2AQAAAA==.',
Yo='Yonna:BAAALgAECgMJBwAAAA==.Yopps:BAABLgAECn8YAAMKAAgJKhmtKgBlAgAKAAgJKhmtKgBlAgALAAEJjxG4cAA1AAAAAA==.',
Yu='Yunggrazydh:BAAALgADCgcJCAAAAA==.Yurio:BAAALgADCgEJAQAAAA==.Yuunggrazy:BAAALgAECgIJAwAAAA==.',
['Yé']='Yéager:BAAALgAECgcJEwAAAA==.',
Za='Zabuto:BAABLgAECn8cAAINAAgJhBtPBQC9AQANAAgJhBtPBQC9AQAAAA==.Zaevryn:BAAALgAECgEJAQABLgAECgQJCgADAAAAAA==.Zahäära:BAAALgADCgMJAwAAAA==.Zakaka:BAAALgAECgEJAQAAAA==.Zandrozarath:BAAALgAECgUJBQAAAA==.Zarrtan:BAAALgADCgMJAwAAAA==.Zazprie:BAAALgAECgEJAQAAAA==.',
Ze='Zenrelia:BAAALgADCgEJAgAAAA==.',
Zi='Zicatriz:BAAALgADCgYJBgAAAA==.',
Zo='Zongretaboom:BAAALgAECgUJCAAAAA==.Zooss:BAAALgAECgYJDQAAAA==.Zoralias:BAAALgADCgUJBQAAAA==.Zoth:BAAALgADCgcJCAAAAA==.',
Zs='Zshot:BAACLgAFFH8OAAISAAUJrSSIAACqAQASAAUJrSSIAACqAQAuAAQKfyIAAxIACQkOJVAAALoDABIACQkNJVAAALoDABAAAQlcIGl+AEwAAAAA.',
Zu='Zuggýzug:BAAALgAECgIJAwAAAA==.Zularam:BAAALgADCgYJBgAAAA==.Zuliks:BAAALgAECgQJBgAAAA==.',
Zx='Zxeý:BAAALgAECgYJDQAAAA==.',
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

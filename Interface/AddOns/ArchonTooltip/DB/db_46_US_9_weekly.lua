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

local lookup = {'Warlock-Destruction','Druid-Balance','Druid-Guardian','Mage-Frost','Mage-Arcane','Priest-Holy','DemonHunter-Vengeance','DemonHunter-Devourer','Priest-Discipline','Priest-Shadow','Shaman-Restoration','Warlock-Demonology','Warrior-Fury','Unknown-Unknown','Warrior-Protection','Paladin-Retribution','Shaman-Elemental','Monk-Mistweaver','Monk-Brewmaster','Druid-Restoration','Monk-Windwalker','Shaman-Enhancement','Paladin-Holy','Evoker-Preservation','Evoker-Augmentation','DemonHunter-Havoc','Paladin-Protection','Hunter-BeastMastery','DeathKnight-Unholy','Druid-Feral','Hunter-Marksmanship','DeathKnight-Blood','Rogue-Assassination','Evoker-Devastation','Warlock-Affliction','DeathKnight-Frost',}
local provider = {region='US',realm='AlteracMountains',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abyssia:BAAALgAFFAEJAQAAAA==.',
Ac='Acupuncher:BAAALgADCgEJAgAAAA==.',
Ad='Aderana:BAAALgADCgYJBgAAAA==.Adesireyn:BAAALgAECgcJEwAAAA==.',
Ae='Aedrenaline:BAAALgADCgMJAwAAAA==.',
Ai='Airius:BAAALgAECgcJCgAAAA==.Airmed:BAAALgAECgQJCQAAAA==.',
Al='Alcha:BAABLgAECn8ZAAIBAAcJmxomBADNAQABAAcJmxomBADNAQAAAA==.Alchalite:BAAALgADCgYJBgABLgAECgcJGQABAJsaAA==.Alenndar:BAAALgAECgYJDAAAAA==.Alexdaddario:BAABLgAECn8cAAMCAAYJIyHzHgAIAgACAAYJIyHzHgAIAgADAAIJ2ggaJQBEAAAAAA==.Alkuhh:BAAALgADCgcJDgABLgAECgcJGQABAJsaAA==.Altdps:BAAALgAECgYJDQAAAA==.',
Am='Amareyna:BAABLgAECn8cAAMEAAgJ0xHGPQCuAQAEAAgJ0xHGPQCuAQAFAAEJsgUPIAAvAAAAAA==.Amaridia:BAAALgAECggJDgAAAA==.Amos:BAAALgAECgcJCwABLgAECgcJGwAGABgUAA==.',
An='Anadeius:BAAALgADCgMJAwAAAA==.Animeniac:BAABLgAECn8aAAIHAAYJRCW0AwAKAgAHAAYJRCW0AwAKAgAAAA==.Annalease:BAAALgAECgIJAwAAAA==.Anticlimax:BAABLgAECn8bAAIIAAcJfRMKNABlAQAIAAcJfRMKNABlAQAAAA==.Antipathy:BAAALgADCgIJAgAAAA==.Antisocial:BAAALgADCggJGAAAAA==.',
Ao='Aoibhneas:BAAALgAECgMJBQAAAA==.',
Ap='Apparition:BAABLgAECn8aAAMJAAgJWRL/EgCuAQAJAAgJWRL/EgCuAQAKAAUJgQpFQQBuAAAAAA==.Apprentice:BAACLgAFFH8FAAIEAAMJiR3MPQAWAQAEAAMJiR3MPQAWAQAuAAQKfyQAAgQACAmgI1UVACgDAAQACAmgI1UVACgDAAAA.',
Ar='Argonar:BAABLgAECn8WAAIEAAgJ5w3KTQCAAQAEAAgJ5w3KTQCAAQAAAA==.Arthras:BAAALgAECgYJBgAAAA==.',
As='Ashelia:BAAALgAECgQJCQAAAA==.Ashian:BAAALgAECgMJAwAAAA==.Aslio:BAABLgAECn8aAAILAAgJ5RxsFgBiAgALAAgJ5RxsFgBiAgAAAA==.',
At='Atorim:BAAALgAECgEJAQAAAA==.Atreyou:BAAALgAECgcJCwAAAA==.',
Au='Aurum:BAABLgAECn8pAAILAAkJNA/sHgC7AQALAAkJNA/sHgC7AQAAAA==.',
Av='Avdol:BAAALgAECgcJDwABLgAFFAYJEAAMAGkcAA==.Avienndha:BAABLgAECn8UAAIHAAYJFRUnCgAxAQAHAAYJFRUnCgAxAQAAAA==.',
Aw='Awake:BAAALgAECgYJDAAAAA==.',
Az='Azgrunga:BAABLgAECn8uAAINAAgJqxxyDAAkAgANAAgJqxxyDAAkAgAAAA==.',
Ba='Banditbear:BAAALgAECgQJBAAAAA==.Barf:BAAALgAECgQJCgAAAA==.Battlecattle:BAAALgADCgYJCQAAAA==.',
Be='Beastmodedp:BAAALgAECgkJBwAAAA==.Bel:BAAALgAECgEJAQAAAA==.Benderbrod:BAAALgADCgkJCQAAAA==.Beornwildlaw:BAAALgADCgcJAgAAAA==.',
Bl='Blapdragon:BAAALgADCgEJAQABLgADCgEJAgAOAAAAAA==.',
Bo='Bobbytofva:BAABLgAECn8bAAINAAcJMRpyOQDBAQANAAcJMRpyOQDBAQAAAA==.Bobtheman:BAAALgADCgEJAQAAAA==.Boochaka:BAABLgAECn8cAAILAAgJKBmtEwAYAgALAAgJKBmtEwAYAgAAAA==.',
Br='Breesus:BAAALgAECgMJAwAAAA==.Brewdog:BAAALgAECgQJBgAAAA==.Brightmane:BAAALgADCgEJAQAAAA==.Brochefski:BAABLgAECn8eAAIPAAkJxh6RAwCNAgAPAAkJxh6RAwCNAgAAAA==.Brotherfuzz:BAAALgAECggJDwAAAA==.Bráscubas:BAAALgAECgEJAQAAAA==.',
Bu='Bubbernubs:BAAALgADCgUJAQAAAA==.Buff:BAAALgAECgkJCQABLgAECgkJHAAQACQSAA==.Busterposer:BAAALgAECgEJAQAAAA==.Buu:BAAALgAECgYJDQAAAA==.',
['Bö']='Böb:BAAALgAECgQJBQAAAA==.',
Ca='Calabooca:BAAALgAECgIJAgAAAA==.Candor:BAAALgADCggJCgAAAA==.Caramilk:BAAALgAECggJCwABLgAECgcJFAAMAAEZAA==.Cashthegreat:BAAALgAECgMJAwAAAA==.',
Ce='Celily:BAAALgADCgYJBgAAAA==.',
Ch='Chain:BAACLgAFFH8FAAILAAMJlhI5JADEAAALAAMJlhI5JADEAAAuAAQKfycAAwsACAkeGoUTABoCAAsACAkeGoUTABoCABEABQmLFQkoAB0BAAAA.Cheesefries:BAABLgAECn8YAAMSAAYJjBtaEgDRAQASAAYJjBtaEgDRAQATAAYJ/Ri6GABxAQAAAA==.Chereth:BAABLgAECn8WAAIUAAcJhBJnSACBAQAUAAcJhBJnSACBAQAAAA==.Chocola:BAAALgADCgEJAQAAAA==.Chouko:BAABLgAECn8dAAMVAAgJYg73HgAsAQAVAAcJaQv3HgAsAQATAAIJLxJ8SQBvAAAAAA==.Chronovan:BAAALgAECgUJBgAAAA==.Chrotch:BAAALgADCgQJBAAAAA==.',
Ci='Cirad:BAAALgADCgIJAgAAAA==.',
Cl='Claep:BAABLgAECn8VAAMSAAcJ0BKYIABBAQASAAcJ0BKYIABBAQAVAAYJ1QUdMADFAAAAAA==.',
Co='Cogglutch:BAAALgAECgMJAwABLgADCgYJBgAOAAAAAA==.Cokegirll:BAAALgAECgYJDAAAAA==.',
Cr='Creamcorn:BAAALgADCgUJBQABLgAECggJGgAWAI8VAA==.Creamie:BAABLgAECn8WAAITAAcJ1htKFQCRAQATAAcJ1htKFQCRAQABLgAECggJGgAWAI8VAA==.Creamish:BAABLgAECn8aAAIWAAgJjxWnBgDQAQAWAAgJjxWnBgDQAQAAAA==.Cricketts:BAAALgAECgEJAQAAAA==.Critties:BAAALgADCgcJDAAAAA==.Crueldin:BAABLgAECn8VAAIXAAcJMRf+FADoAQAXAAcJMRf+FADoAQAAAA==.Cryptos:BAAALgAECgQJCAAAAA==.',
Cy='Cybertruck:BAAALgADCgUJCgAAAA==.',
['Cé']='Célery:BAAALgAECgQJCAAAAA==.',
Da='Dacrus:BAAALgAECgEJBAAAAA==.Dalsen:BAABLgAECn8hAAIDAAgJ6w8vDABOAQADAAgJ6w8vDABOAQAAAA==.Dalvulpe:BAAALgADCgEJAQABLgAECggJIQADAOsPAA==.Damnadin:BAAALgAECgcJCwAAAA==.Dankchop:BAABLgAECn8VAAIPAAcJRQ4NFgAVAQAPAAcJRQ4NFgAVAQAAAA==.Daredevil:BAAALgAECgEJAQABLgADCgYJBgAOAAAAAA==.Darim:BAAALgAECgMJAwAAAA==.Darkgoomba:BAAALgADCggJCQAAAA==.',
De='Deathwinne:BAAALgADCgEJAQAAAA==.Demonfed:BAAALgAECgEJAQABLgAECgYJDAAOAAAAAA==.Denaian:BAAALgADCgcJCwAAAA==.Denoran:BAAALgADCgUJBwAAAA==.Deone:BAABLgAECn8YAAIVAAYJeBmuFQB9AQAVAAYJeBmuFQB9AQAAAA==.Deskpop:BAAALgADCgYJCgAAAA==.Dewberry:BAAALgAECgEJAQAAAA==.Deáth:BAAALgAECgMJBgAAAA==.',
Di='Diabolikal:BAAALgAECgQJCAAAAA==.Dill:BAABLgAECn85AAINAAkJYCNLAQAmAwANAAkJYCNLAQAmAwAAAA==.Diomedus:BAAALgADCggJDgAAAA==.Discord:BAAALgAECgYJBgAAAA==.',
Dk='Dkjosh:BAAALgAECgQJBQAAAA==.',
Do='Doctowatson:BAAALgAECgMJAwAAAA==.Donkeykông:BAAALgAECgQJBQAAAA==.',
Dr='Drassa:BAAALgADCgEJAQAAAA==.Drazzak:BAAALgADCgUJCQABLgAECgMJAwAOAAAAAA==.Drebatok:BAAALgAECgQJBAAAAA==.Drunkfuq:BAAALgAECgEJAQAAAA==.Druwulf:BAAALgAECgEJAQAAAA==.Drwarlacko:BAAALgADCgcJBwAAAA==.Drwatsonpal:BAAALgAECgcJCAAAAA==.Drùna:BAABLgAECn8YAAICAAcJLgyBLQDgAAACAAcJLgyBLQDgAAAAAA==.',
Du='Duifean:BAAALgADCgMJAwAAAA==.Dundecay:BAAALgADCgEJAQAAAA==.Durkidurk:BAAALgAECgEJAQAAAA==.',
Dw='Dwude:BAAALgADCgEJAwAAAA==.',
Dy='Dyabolykal:BAAALgAECgQJBQABLgAECgQJCAAOAAAAAA==.',
El='Eleramdar:BAAALgAECgQJBAAAAA==.Eligio:BAABLgAECn8cAAIQAAkJJBLdJwDhAQAQAAkJJBLdJwDhAQAAAA==.Elly:BAAALgADCgYJBgAAAA==.Elsharion:BAAALgAECgYJDQABLgAFFAYJGQASAGUfAA==.Elsharius:BAAALgAECgQJBAABLgAFFAYJGQASAGUfAA==.Elshary:BAAALgADCgkJCQAAAA==.Elsharyon:BAAALgAECgMJAwABLgAFFAYJGQASAGUfAA==.Elshie:BAACLgAFFH8ZAAISAAYJZR9dAwAYAgASAAYJZR9dAwAYAgAuAAQKfxUAAhIACQkJHl0NAH4CABIACQkJHl0NAH4CAAAA.',
Em='Emachine:BAAALgAFFAMJBAABLgAFFAYJEAAMAGkcAA==.',
Es='Eskyxy:BAAALgAECgYJCQAAAA==.Espressoul:BAAALgADCgQJAwAAAA==.',
Ev='Evergreen:BAABLgAECn8uAAIUAAgJABmqHwBEAgAUAAgJABmqHwBEAgAAAA==.',
Fa='Fastasheet:BAACLgAFFH8UAAIVAAUJUSM3AQDRAQAVAAUJUSM3AQDRAQAuAAQKfzoAAhUACQlWJj0AAIEDABUACQlWJj0AAIEDAAAA.Fatherfigur:BAAALgADCgEJAQAAAA==.',
Fd='Fdfrank:BAAALgAECgEJAwAAAA==.',
Fe='Felcollins:BAAALgAFFAEJAQAAAA==.Fenrirr:BAAALgAECgUJBgAAAA==.',
Fi='Fill:BAABLgAECn8ZAAIWAAYJFSQ2CABfAgAWAAYJFSQ2CABfAgAAAA==.Finnegan:BAAALgAECgEJAQAAAA==.Fistcleave:BAAALgAECgQJBQAAAA==.',
Fl='Flatwhite:BAAALgAECgUJBwAAAA==.Fleshtofill:BAAALgADCgkJCQAAAA==.Flexible:BAAALgADCgcJCgAAAA==.Flyinbanana:BAAALgAECgYJEAABLgAECgcJFgAYAMYWAA==.',
Fr='Frags:BAABLgAECn8lAAIXAAkJ0Rd3EQANAgAXAAkJ0Rd3EQANAgAAAA==.',
Fu='Furryfister:BAAALgAECgkJAQAAAA==.',
Fy='Fyrefest:BAAALgAECgYJBgABLgAECggJEgAOAAAAAA==.',
Ga='Galvek:BAAALgADCgQJBAAAAA==.Ganska:BAAALgAECgcJBwAAAA==.Garmonbozia:BAAALgADCgIJAwAAAA==.Garrytt:BAAALgAECgYJDQAAAA==.Gatsumoto:BAAALgADCgkJEAAAAA==.',
Ge='Genjyosanzo:BAAALgAECgYJEQAAAA==.Gertrex:BAAALgADCgEJAgAAAA==.',
Gi='Gilfu:BAABLgAECn8rAAITAAgJuyIbCAAEAwATAAgJuyIbCAAEAwAAAA==.Gilthol:BAAALgADCgEJAQAAAA==.Gimmixdh:BAAALgADCgMJAwAAAA==.Gingavitis:BAAALgADCgYJBAAAAA==.',
Go='Goey:BAAALgADCgYJAQAAAA==.Gothmommy:BAAALgADCgEJAQABLgAFFAUJDwAZALYRAA==.',
Gr='Gremussy:BAAALgADCgMJAwAAAA==.Grito:BAAALgAECgQJDAAAAA==.Grokdepaly:BAAALgAECgMJAwAAAA==.Grunkpatunga:BAAALgAECgUJBgAAAA==.',
Ha='Halsina:BAAALgAECgEJAQAAAA==.Hanittumn:BAAALgADCgQJBAAAAA==.Harrysax:BAAALgAECgkJBAAAAA==.',
He='Healadem:BAAALgADCgcJDAAAAA==.Healamage:BAAALgAECgMJBQAAAA==.',
Hi='Highfeather:BAABLgAECn8gAAINAAYJkBbAHwBuAQANAAYJkBbAHwBuAQAAAA==.Hilazy:BAAALgAECgYJEAAAAA==.Hiping:BAAALgAECgYJDgAAAA==.',
Ho='Holycanuk:BAAALgAECgEJBQAAAA==.Holyfed:BAAALgAECgYJDAAAAA==.Holyphok:BAABLgAECn8cAAMJAAcJeRbQDQD0AQAJAAcJeRbQDQD0AQAKAAEJLQo2TwA6AAAAAA==.Holysheet:BAAALgAFFAEJAQAAAA==.Hornedupwarr:BAAALgAECgEJAQAAAA==.Hort:BAAALgAECgYJEwAAAA==.Hotdog:BAAALgAECgYJBwAAAA==.',
Hu='Hukjor:BAAALgAECgIJAgAAAA==.Huneybutta:BAAALgADCgEJAQABLgADCgQJBAAOAAAAAA==.',
Hy='Hyla:BAAALgAECggJEgAAAA==.',
Ib='Ibackstab:BAAALgAECgEJAQAAAA==.',
Ic='Icestormy:BAABLgAECn8aAAIEAAYJoQUumwDcAAAEAAYJoQUumwDcAAAAAA==.',
Ih='Ihasaface:BAAALgAECgYJCwAAAA==.Ihavenofutur:BAAALgAECgYJCwAAAA==.',
Il='Illari:BAAALgAECgUJDAAAAA==.Illidantwo:BAACLgAFFH8UAAIaAAUJmhxkAQCYAQAaAAUJmhxkAQCYAQAuAAQKfyoAAhoACQllIxAEADoDABoACQllIxAEADoDAAAA.Illysanna:BAAALgADCgIJAgAAAA==.',
Im='Imprints:BAAALgAECgcJEgAAAA==.',
In='Inquisistrus:BAAALgADCgMJAwAAAA==.',
Ir='Irönside:BAAALgAECgUJDQAAAA==.',
Is='Isalia:BAAALgADCgQJBAAAAA==.Isdeepïnsidû:BAAALgAECgEJAQAAAA==.',
It='Italianapee:BAAALgAECgcJDwAAAA==.',
Ja='Jaboo:BAAALgAECgYJDAABLgAFFAMJBQAIANwVAA==.Jabu:BAAALgAECgEJAQABLgAFFAMJBQAIANwVAA==.Jacki:BAAALgADCgcJCwAAAA==.Jahz:BAABLgAECn8UAAIJAAYJLSU8BwB3AgAJAAYJLSU8BwB3AgAAAA==.Jakeem:BAAALgAECgEJAQAAAA==.',
Je='Jenasys:BAAALgAECgQJAwAAAA==.Jenstonedart:BAAALgAECggJEgAAAA==.Jeryeth:BAABLgAECn8YAAIPAAgJMByNCACXAgAPAAgJMByNCACXAgAAAA==.',
Ji='Jinwoo:BAAALgADCgQJBQAAAA==.',
Jm='Jmage:BAAALgAECgEJAQAAAA==.',
['Já']='Jácor:BAAALgADCgcJBwAAAA==.',
Ka='Kain:BAACLgAFFH8WAAIbAAQJgyOlAACkAQAbAAQJgyOlAACkAQAuAAQKfykAAhsACAk9JtwAAGgDABsACAk9JtwAAGgDAAAA.Karenuwu:BAAALgAECggJDQAAAA==.Kaïn:BAAALgADCgEJAQABLgAECgkJNAAQAIEhAA==.',
Ke='Kegtail:BAAALgADCgYJBgAAAA==.Kelsí:BAAALgADCggJCAAAAA==.Kenslee:BAAALgADCgEJAQAAAA==.',
Kh='Khanzu:BAABLgAECn8WAAMCAAYJxhQwOABYAQACAAYJxhQwOABYAQAUAAEJkAZIpQAlAAAAAA==.Khrouzh:BAAALgADCgIJAgAAAA==.',
Ki='Killnuall:BAAALgAECgMJAwABLgAECgYJDQAOAAAAAA==.Kiwí:BAABLgAECn8aAAMFAAcJSBtiAwCAAQAFAAUJAh1iAwCAAQAEAAUJxQ5hnADaAAAAAA==.',
Kr='Krasavice:BAABLgAECn8fAAIcAAcJGSRvGQBvAgAcAAcJGSRvGQBvAgAAAA==.',
Ku='Kungpowcow:BAAALgAECgQJCQAAAA==.',
Kv='Kvoth:BAAALgADCgcJCAAAAA==.',
La='Lauranthalas:BAABLgAECn8ZAAIcAAYJ7RDERgA5AQAcAAYJ7RDERgA5AQAAAA==.Lavish:BAACLgAFFH8NAAIIAAYJsAjNHQAzAQAIAAYJsAjNHQAzAQAuAAQKfxsAAggACAk3HOkqAFQCAAgACAk3HOkqAFQCAAAA.',
Le='Leathal:BAABLgAECn8WAAMXAAcJvRKdHACkAQAXAAcJvRKdHACkAQAQAAYJwhmZbgCgAQAAAA==.Lemurshoes:BAAALgAECgYJBgAAAA==.Lena:BAABLgAECn8kAAIcAAgJvyOLBwC4AgAcAAgJvyOLBwC4AgAAAA==.Lethario:BAAALgAECgEJAQAAAA==.Lewstelamon:BAAALgAECgQJBAAAAA==.Leøn:BAABLgAECn8YAAIdAAgJFx1kJACsAgAdAAgJFx1kJACsAgAAAA==.',
Li='Lightsmithin:BAAALgADCgQJBAABLgADCgcJCAAOAAAAAA==.Liightoneup:BAAALgADCgMJAwAAAA==.Lilaxe:BAAALgAECgUJBQAAAA==.',
Lo='Lokust:BAABLgAECn8dAAILAAgJLB4yCwB7AgALAAgJLB4yCwB7AgAAAA==.Londonfog:BAAALgADCgMJAwAAAA==.Lorax:BAAALgAECgMJBQABLgAECgYJEAAOAAAAAA==.',
Lu='Lucaeryn:BAAALgADCgMJAwABLgAECgkJKgAZAOwkAA==.Lungoblin:BAAALgADCgYJCgAAAA==.Luriøn:BAAALgAECgUJCwAAAA==.Lusat:BAAALgAECgMJAwAAAA==.',
Lw='Lwx:BAAALgADCgkJCQAAAA==.',
Ly='Lycanius:BAABLgAECn8vAAIeAAkJhxxTAgCOAgAeAAkJhxxTAgCOAgAAAA==.',
['Lü']='Lüna:BAABLgAECn8dAAIfAAcJvAWNEADlAAAfAAcJvAWNEADlAAAAAA==.',
Ma='Macewindu:BAAALgAECgEJAgAAAA==.Magicwalrus:BAAALgAECgMJAwABLgAFFAYJEAAMAGkcAA==.Malf:BAAALgAECgMJAwAAAA==.Malëk:BAABLgAECn80AAIQAAkJgSHbBgDhAgAQAAkJgSHbBgDhAgAAAA==.Marsmighty:BAAALgAECgQJCQAAAA==.Matchalatte:BAAALgAECgIJAgAAAA==.Mattato:BAAALgAECgYJDAAAAA==.Maximus:BAABLgAECn8aAAIQAAgJvAoOSQBqAQAQAAgJvAoOSQBqAQAAAA==.',
Me='Meditacoss:BAAALgAECgEJAQABLgAECgMJAwAOAAAAAA==.Mellowlizard:BAABLgAFFH8QAAIMAAYJaRyNBQDQAQAMAAYJaRyNBQDQAQAAAA==.Metamarie:BAAALgADCgEJAQAAAA==.Metuss:BAAALgAECgcJEAAAAA==.',
Mi='Mira:BAABLgAECn8bAAIcAAcJlBOURwCTAQAcAAcJlBOURwCTAQAAAA==.Mistutodeath:BAAALgADCgQJBAAAAA==.Mitçh:BAAALgAECgMJAwAAAA==.',
Mk='Mk:BAEALgAECgUJBgABLgAECggJKwAVAAIjAA==.Mkicon:BAABLgAECn8cAAIEAAgJyxCdPwCoAQAEAAgJyxCdPwCoAQAAAA==.Mkultra:BAABLgAECn8ZAAMgAAcJbB7MEwA6AQAdAAcJZRlmbgCtAQAgAAYJ6h3MEwA6AQAAAA==.',
Mo='Moanphine:BAAALgADCgcJBwAAAA==.Mogmoog:BAAALgAECgYJDQAAAA==.Mookilmer:BAAALgAECgIJAgAAAA==.Moonangel:BAABLgAECn8aAAIhAAYJHheCBwBnAQAhAAYJHheCBwBnAQAAAA==.Moozrael:BAAALgADCgQJBwAAAA==.Morbodan:BAAALgAECgYJDwAAAA==.Motone:BAABLgAECn8eAAMUAAgJbwhZQQANAQAUAAgJbwhZQQANAQACAAIJDwJkegA9AAAAAA==.Motrapz:BAAALgADCgQJBAAAAA==.Mozz:BAABLgAECn8aAAMMAAgJrxR8VADKAQAMAAcJzRV8VADKAQABAAIJ/w2zVABwAAAAAA==.',
Mt='Mtkdh:BAAALgAECgkJAQAAAA==.',
Mu='Mudget:BAACLgAFFH8gAAMBAAgJuRqPAAA9AgABAAYJDBiPAAA9AgAMAAcJPxkyBADcAQAuAAQKfzUAAwwACQkuJoUNAA0DAAwABwkTJoUNAA0DAAEABQl1JpgIADgCAAAA.Muffins:BAAALgADCgcJBwABLgAECggJJgALAOEVAA==.Multanni:BAABLgAECn8aAAIRAAcJXBYOHQBlAQARAAcJXBYOHQBlAQAAAA==.',
My='Myonecrosis:BAAALgAECgYJDgAAAA==.',
Na='Nacho:BAAALgAFFAEJAQABLgADCgYJBgAOAAAAAA==.Nakrog:BAAALgAECgEJAQAAAA==.Napster:BAABLgAECn8aAAIXAAcJoSAZGABRAgAXAAcJoSAZGABRAgAAAA==.Nasa:BAACLgAFFH8VAAIVAAYJXBxPAQDHAQAVAAYJXBxPAQDHAQAuAAQKfxsAAhUACQmZHu4LALwCABUACQmZHu4LALwCAAAA.Nazarov:BAAALgAECgEJAQAAAA==.',
Ne='Nellarixi:BAABLgAECn8nAAIKAAgJ7xiHCwALAgAKAAgJ7xiHCwALAgAAAA==.Nethus:BAAALgAECgEJAQAAAA==.',
Ni='Niivalyr:BAAALgADCgYJBgAAAA==.Nillheart:BAAALgADCgUJBQAAAA==.Nimbus:BAACLgAFFH8TAAMZAAcJIhTiBwCvAQAZAAcJIhTiBwCvAQAiAAIJpgnrBgCgAAAuAAQKf1AAAxkACQl0Ji8AAI4DABkACQlTJi8AAI4DACIACAklIL8DAN4CAAAA.',
No='Nomaa:BAABLgAECn8ZAAIjAAYJ1gE+DwCGAAAjAAYJ1gE+DwCGAAAAAA==.Nomäd:BAAALgAECgYJDQAAAA==.Nosneb:BAAALgAECgEJAgAAAA==.',
Nr='Nramar:BAAALgADCgYJBwAAAA==.',
Nu='Nurgle:BAAALgADCgYJDAAAAA==.',
Ny='Nyteshadow:BAAALgADCgYJCQAAAA==.Nyteshock:BAABLgAECn8UAAIRAAYJBhCLKwAKAQARAAYJBhCLKwAKAQAAAA==.',
['Nì']='Nìtsua:BAAALgAECgEJAwAAAA==.',
Ob='Obitz:BAAALgAECgUJBgAAAA==.',
Og='Ogmount:BAAALgAECgQJDQAAAA==.',
Oi='Oisin:BAABLgAECn8kAAQDAAgJ6gNPGgCKAAADAAgJyANPGgCKAAACAAEJ4gN6iQAmAAAeAAEJkQM3OQAkAAAAAA==.',
Ok='Okko:BAAALgAECgEJAQAAAA==.Oktoberfest:BAAALgAECggJEgAAAA==.',
Oo='Ookitsu:BAAALgADCgIJAgAAAA==.',
Pe='Perky:BAABLgAECn8YAAIbAAcJ2hQKEwCZAQAbAAcJ2hQKEwCZAQAAAA==.',
Ph='Phok:BAAALgADCgYJCQAAAA==.Phrash:BAAALgAECgIJBAABLgAECgYJGQAWABUkAA==.',
Pi='Pinkpwny:BAAALgAECgMJBAAAAA==.',
Pl='Plex:BAAALgAECgcJCAAAAA==.',
Po='Pocahontas:BAABLgAECn8bAAIGAAcJGBTCHQBbAQAGAAcJGBTCHQBbAQAAAA==.Poky:BAAALgADCgUJBgABLgADCgYJBgAOAAAAAA==.Poocatpokop:BAAALgADCgMJAwAAAA==.Pooldan:BAAALgAECgEJAQAAAA==.Portals:BAAALgAECgEJAQAAAA==.',
Pr='Praystatioñ:BAAALgAECgYJCwAAAA==.Premiumgank:BAAALgADCgEJAQAAAA==.Priestson:BAAALgADCgMJAwAAAA==.',
Qu='Quígonjinn:BAAALgAECgEJAQAAAA==.',
Ra='Raa:BAACLgAFFH8IAAIcAAMJaxnQJAADAQAcAAMJaxnQJAADAQAuAAQKfyIAAhwABwk8I1MRAK4CABwABwk8I1MRAK4CAAAA.Racker:BAAALgAECgYJBwAAAA==.Rainfallen:BAAALgAECgYJBgAAAA==.Raptors:BAAALgADCgEJAQAAAA==.Rawbert:BAAALgAECgMJBQAAAA==.',
Re='Rellein:BAAALgAECgYJEAAAAA==.Rengar:BAABLgAECn8UAAMNAAUJ7xnCSgB6AQANAAUJ7xnCSgB6AQAPAAQJUxA4MADCAAAAAA==.Rengots:BAAALgAECgYJDgAAAA==.Renne:BAABLgAECn8jAAIaAAcJxRWMEQBvAQAaAAcJxRWMEQBvAQAAAA==.Reph:BAAALgAECgEJAQAAAA==.',
Rh='Rheana:BAAALgAECgYJEAAAAA==.',
Ro='Rocktober:BAAALgADCgYJBgAAAA==.Rogmash:BAAALgAECgQJBgAAAA==.Rokkoz:BAABLgAECn8bAAMCAAcJsxR/IQArAQACAAcJsxR/IQArAQADAAQJhQhCKgBRAAAAAA==.Rookiestar:BAAALgAECgEJAgAAAA==.Rowaen:BAAALgAECgYJAgAAAA==.',
Ru='Rumí:BAABLgAECn8WAAQIAAcJ/R74KACWAQAIAAcJlx34KACWAQAHAAQJGiEQDgBzAQAaAAEJ+Q+BbQA4AAAAAA==.',
['Rí']='Ríta:BAAALgAECgYJEQAAAA==.',
Sa='Samosan:BAAALgAECgUJDAAAAA==.Sarnt:BAAALgAECggJBAAAAA==.Sass:BAABLgAECn8sAAMCAAkJjxxLBAC0AgACAAkJjxxLBAC0AgAUAAMJSgvuaACDAAAAAA==.Satella:BAAALgAECgcJBwABLgAFFAYJEAAMAGkcAA==.',
Sc='Schattën:BAAALgAECgcJEgAAAA==.',
Se='Senseideath:BAAALgAECgMJAwABLgADCgYJBgAOAAAAAA==.Serrana:BAAALgAECgQJDAAAAA==.',
Sf='Sfinktor:BAAALgAECgEJAQAAAA==.',
Sh='Shakz:BAAALgAECgYJBwAAAA==.Sharlug:BAAALgADCgcJEQAAAA==.Shingu:BAAALgAFFAEJAQABLgAFFAQJCgAEAJEdAA==.Shirokhan:BAABLgAECn8XAAIEAAcJcx58OwC2AQAEAAcJcx58OwC2AQAAAA==.Shïfthappens:BAAALgADCgIJAgAAAA==.',
Si='Sidewinderx:BAAALgADCgYJBgAAAA==.Siewarwolf:BAAALgAECgQJBgAAAA==.Silentant:BAAALgAECgMJBgAAAA==.Sinlock:BAABLgAECn8uAAMMAAgJNyOMCwCWAgAMAAgJNyOMCwCWAgABAAMJoRkbRwCaAAAAAA==.',
Sn='Snagglespark:BAABLgAECn8rAAIRAAkJZxqfCQA/AgARAAkJZxqfCQA/AgAAAA==.Sneviltok:BAAALgAECgIJAgAAAA==.Snowbunni:BAAALgADCgcJCQAAAA==.Snowster:BAAALgADCggJDAAAAA==.',
So='Soladrian:BAABLgAECn8YAAIIAAcJMxgJJwCgAQAIAAcJMxgJJwCgAQAAAA==.Somehunguy:BAAALgAECgEJAgABLgAECgMJAwAOAAAAAA==.Soulreeper:BAAALgAECgYJBgAAAA==.Soulsuck:BAAALgAECgYJCgAAAA==.',
Sp='Spankyee:BAAALgAECgMJAwAAAA==.',
St='Starlisia:BAAALgAECgYJEQAAAA==.Starz:BAAALgAECgUJAQAAAA==.Stelmaria:BAAALgAECgMJAwABLgAFFAMJBgAcALkMAA==.',
Su='Suhdrake:BAABLgAECn8iAAIYAAgJWhnEBQA1AgAYAAgJWhnEBQA1AgAAAA==.Sunwing:BAAALgAECgEJAQAAAA==.',
['Sé']='Séraph:BAAALgAECgMJBAAAAA==.',
['Só']='Sóozabimaru:BAAALgADCgEJAQAAAA==.',
['Sÿ']='Sÿdney:BAABLgAECn8aAAMJAAYJQBEKGgBhAQAJAAYJQBEKGgBhAQAKAAEJ+QIZaQAmAAAAAA==.',
Ta='Tanara:BAAALgAECgQJBQAAAA==.Tankarmor:BAABLgAECn8dAAIPAAgJDhd6CQDdAQAPAAgJDhd6CQDdAQAAAA==.Taric:BAAALgADCgYJBgABLgAECgcJFAAMAAEZAA==.',
Tc='Tcharta:BAABLgAECn8WAAIYAAcJxhbcCQC8AQAYAAcJxhbcCQC8AQAAAA==.',
Te='Teddyj:BAAALgAECgEJAQAAAA==.Tehkillerofu:BAAALgAECgEJAQAAAA==.Teos:BAAALgAECgcJDQAAAA==.',
Th='Thiccpickles:BAAALgAECgIJAgABLgAECgkJIgALABEcAA==.Thoror:BAAALgAECgUJCAAAAA==.Thunderblap:BAAALgADCgEJAQABLgADCgEJAgAOAAAAAA==.Thunderbolt:BAAALgADCgIJAgABLgADCgYJBgAOAAAAAA==.',
Ti='Tiamat:BAAALgADCgYJBgAAAA==.Tiffina:BAAALgAECgcJDgAAAA==.Tiffy:BAAALgAECgIJAgAAAA==.',
To='Tomvokhin:BAAALgADCgIJAgAAAA==.',
Tr='Tragikmuse:BAAALgAECgcJBwAAAA==.Treeberk:BAAALgADCgkJCQABLgAECgYJCgAOAAAAAA==.Trissara:BAAALgAECgcJCgAAAA==.Trolli:BAABLgAECn8dAAIQAAgJTSLXCwCkAgAQAAgJTSLXCwCkAgAAAA==.',
Tu='Tuckerherout:BAAALgADCgEJAQAAAA==.Tulia:BAAALgAECgYJDQAAAA==.',
Tw='Twixx:BAABLgAFFH8FAAIkAAMJPhCHBADpAAAkAAMJPhCHBADpAAAAAA==.',
Ty='Tyinar:BAAALgAECgEJAgAAAA==.',
Tz='Tzekelkan:BAAALgAECgQJBAAAAA==.',
['Tî']='Tînytotems:BAAALgAECgMJAQAAAA==.Tîtån:BAABLgAECn8UAAMBAAcJ9gb2EwCyAAAMAAYJ8we3cQDmAAABAAcJsAL2EwCyAAAAAA==.',
Ud='Uddercover:BAAALgAECgQJCQAAAA==.Udeloof:BAAALgADCgYJDAAAAA==.',
Uh='Uh:BAAALgAECgIJCQABLgAECgYJGQAWABUkAA==.',
Un='Unbound:BAAALgAECgYJDgAAAA==.Unbullevable:BAAALgAECgIJAgABLgAECgQJBQAOAAAAAA==.',
Ur='Urdurteno:BAAALgAECgEJAQAAAA==.',
Va='Vae:BAACLgAFFH8IAAIdAAMJjCGtTwDwAAAdAAMJjCGtTwDwAAAuAAQKfxYAAx0ABgkdJuE9AEACAB0ABgkdJuE9AEACACAAAQnNITk8AGQAAAAA.Valkussy:BAAALgADCgYJBgAAAA==.Vathen:BAABLgAECn8UAAIMAAcJARmGOQAlAgAMAAcJARmGOQAlAgAAAA==.',
Ve='Velmalthea:BAABLgAECn8XAAMJAAYJWBG3GwBQAQAJAAYJQg+3GwBQAQAGAAQJMA/4WADQAAAAAA==.Venk:BAAALgADCgYJBgAAAA==.',
Vg='Vgmking:BAABLgAECn8gAAIgAAcJChuVCwC7AQAgAAcJChuVCwC7AQAAAA==.',
Vi='Vindorei:BAAALgAECgMJAwAAAA==.Vinventure:BAAALgAECgQJDQAAAA==.Vivix:BAAALgAECggJDgABLgAECgkJHAAQACQSAA==.',
Vo='Voidfed:BAAALgAECgUJBQABLgAECgYJDAAOAAAAAA==.Vokzhen:BAABLgAECn8VAAIKAAcJ0BLwFwB+AQAKAAcJ0BLwFwB+AQAAAA==.Volescu:BAAALgAECgEJAgAAAA==.',
Wa='Walkerboah:BAABLgAECn8bAAMMAAcJGRGqSABOAQAMAAcJGRGqSABOAQABAAUJwAooMgDwAAAAAA==.Warhoff:BAAALgADCgUJBwAAAA==.Warnis:BAAALgAECgEJAQAAAA==.Wasp:BAAALgADCgcJCAAAAA==.Watergun:BAAALgAFFAEJAQAAAA==.',
Wo='Wolf:BAAALgAECgYJDwAAAA==.',
Wy='Wyland:BAAALgAECgYJEAABLgAECgcJDgAOAAAAAA==.',
Xa='Xarìca:BAAALgAECgcJCwABLgAFFAYJFwAVAB4mAA==.',
Xe='Xeri:BAAALgADCgcJBwABLgAFFAYJFwAVAB4mAA==.Xeromus:BAABLgAECn8aAAMCAAYJ6xfKHQBHAQACAAYJ6xfKHQBHAQAUAAIJ8wSmigBBAAAAAA==.Xetsus:BAAALgAECgUJBQAAAA==.',
Xo='Xoden:BAAALgAECgIJAgAAAA==.',
Ya='Yarok:BAAALgADCgMJBAAAAA==.',
Yu='Yuuna:BAAALgAECgIJAwAAAA==.',
Za='Zabawaba:BAABLgAECn8VAAMXAAgJhhhdEwD5AQAXAAgJhhhdEwD5AQAbAAEJAADlTAAaAAAAAA==.Zaboomaprune:BAAALgAECgcJCwAAAA==.Zantrax:BAAALgADCgIJAgAAAA==.Zaomega:BAAALgAECggJCAABLgAECgkJJwAVAAAkAA==.Zarika:BAAALgAECggJEgABLgAFFAYJFwAVAB4mAA==.Zarì:BAACLgAFFH8XAAIVAAYJHiZSAAA9AgAVAAYJHiZSAAA9AgAuAAQKfxwAAhUACQm8JQ0DAGUDABUACQm8JQ0DAGUDAAAA.Zaö:BAAALgADCgEJAQABLgAECgkJJwAVAAAkAA==.',
Ze='Zeblaw:BAABLgAECn8cAAIEAAgJkhPBSwCFAQAEAAgJkhPBSwCFAQAAAA==.Zenazure:BAAALgAECgUJCgAAAA==.Zenio:BAAALgADCggJCAAAAA==.Zennah:BAAALgADCgQJBgAAAA==.Zensetra:BAAALgADCgYJBgAAAA==.',
Zu='Zuraat:BAAALgAECgQJBAAAAA==.',
Zw='Zwebop:BAAALgADCgEJAgAAAA==.',
['Zà']='Zàomega:BAABLgAECn8nAAMVAAkJACTpAABKAwAVAAkJACTpAABKAwASAAEJuA/uawAqAAAAAA==.',
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

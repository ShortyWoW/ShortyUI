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

local lookup = {'Evoker-Preservation','Mage-Frost','DemonHunter-Devourer','Druid-Balance','Evoker-Augmentation','Priest-Shadow','Priest-Discipline','Hunter-Survival','DeathKnight-Blood','Paladin-Retribution','Paladin-Holy','Warlock-Affliction','Warlock-Demonology','DemonHunter-Havoc','Hunter-BeastMastery','Hunter-Marksmanship','Unknown-Unknown','Druid-Restoration','Rogue-Subtlety','Warrior-Protection','Monk-Mistweaver','Monk-Windwalker','Mage-Arcane','Priest-Holy','Monk-Brewmaster','Warrior-Fury','Warrior-Arms','Rogue-Assassination','Shaman-Elemental','Rogue-Outlaw','DeathKnight-Frost','DeathKnight-Unholy','Paladin-Protection','Druid-Feral','Druid-Guardian','Warlock-Destruction','Shaman-Restoration','Evoker-Devastation','Mage-Fire','Shaman-Enhancement',}
local provider = {region='US',realm='Llane',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abdervoke:BAABLgAECn8WAAIBAAYJySQkBAB4AgABAAYJySQkBAB4AgAAAA==.',
Ac='Account:BAAALgADCgIJAgAAAA==.',
Ae='Aethos:BAAALgAECgkJBQAAAA==.',
Al='Alessaah:BAAALgADCgcJCgAAAA==.Aliadra:BAABLgAECn8gAAICAAgJmR9NIgAfAgACAAgJmR9NIgAfAgAAAA==.Alistus:BAABLgAECn8pAAIDAAgJsyShBADpAgADAAgJsyShBADpAgAAAA==.Altholar:BAAALgADCgcJBwAAAA==.',
An='Anexxia:BAAALgAECgQJBwAAAA==.Angel:BAAALgAECgYJDwAAAA==.Angua:BAABLgAECn8bAAIEAAYJcgs0KgDzAAAEAAYJcgs0KgDzAAAAAA==.',
Ar='Arcanegarm:BAAALgAECgYJEwAAAA==.Archeyois:BAABLgAECn8hAAMFAAgJ8g5xFwCGAQAFAAgJ8g5xFwCGAQABAAUJhQIMNwCzAAAAAA==.Armitage:BAAALgAECggJDwAAAA==.Arthonos:BAABLgAECn8sAAMGAAkJvxI8CwAQAgAGAAkJvxI8CwAQAgAHAAgJ4wVhJwBaAQAAAA==.Arugall:BAAALgADCgYJBgAAAA==.',
As='Ashmall:BAAALgAECgQJBAAAAA==.',
Av='Averille:BAAALgADCgYJCwAAAA==.',
Ay='Ayraa:BAAALgADCgkJBQAAAA==.',
Az='Azerphage:BAAALgAECgUJCAAAAA==.Azeura:BAAALgADCgQJBAAAAA==.Azhorra:BAAALgAECgMJBwAAAA==.Azzog:BAAALgAECgEJAgAAAA==.',
Ba='Baindyn:BAAALgAECgQJCgAAAA==.Barator:BAAALgAECgIJBAAAAA==.Bas:BAAALgAECgUJCQAAAA==.',
Bi='Bickkbatwolf:BAAALgADCgYJDQAAAA==.Bigwhisky:BAAALgAECgcJCwAAAA==.',
Bl='Blackröse:BAABLgAECn8VAAIIAAYJSxzeDwCsAQAIAAYJSxzeDwCsAQAAAA==.Bladebane:BAABLgAECn8VAAIJAAgJkgB7LABqAAAJAAgJkgB7LABqAAAAAA==.Blksunshine:BAAALgAECgIJBAAAAA==.',
Bo='Bolash:BAAALgAECgQJCAAAAA==.Bort:BAAALgAECgEJAwAAAA==.',
Br='Bradthomas:BAAALgAECgQJBQAAAA==.Breni:BAAALgAFFAEJAQAAAA==.Bruscha:BAAALgAECgQJBwAAAA==.',
Bu='Bulvhine:BAABLgAECn8UAAIKAAYJLx2IMwCvAQAKAAYJMB2IMwCvAQAAAA==.',
Ca='Camford:BAAALgAECgcJDAAAAA==.Cantatrix:BAAALgAECgUJBQAAAA==.Capslok:BAAALgAECgQJBwAAAA==.Captinmeat:BAAALgAECgEJAQAAAA==.Cashkin:BAAALgADCgYJBgAAAA==.Cassiela:BAAALgAECgYJBgAAAA==.',
Ce='Cecilx:BAABLgAECn8ZAAILAAcJVyTEBQDHAgALAAcJVyTEBQDHAgAAAA==.Cellybelleri:BAAALgADCgUJCAAAAA==.',
Ch='Chaac:BAAALgADCgEJAQAAAA==.Charmander:BAAALgADCgcJCAAAAA==.Chayton:BAAALgADCgUJBQAAAA==.Chimerax:BAACLgAFFH8GAAMMAAMJOhevAwCcAAAMAAIJDBevAwCcAAANAAEJlxd0dgBLAAAuAAQKfyUAAwwACAlCIgACALACAAwACAlCIgACALACAA0ABwliFB50AOEAAAAA.Chloede:BAAALgADCgUJBQAAAA==.Chlorpyrifos:BAAALgADCgEJAQAAAA==.Chrismikea:BAABLgAECn8cAAIKAAgJMAZicQAKAQAKAAgJMAZicQAKAQAAAA==.Chronic:BAAALgAECgQJBwAAAA==.Chully:BAABLgAECn8oAAMDAAkJnRkgEQA3AgADAAkJnRkgEQA3AgAOAAMJiATKWQB9AAAAAA==.',
Cl='Clairíty:BAAALgAECgYJDwAAAA==.Clarky:BAAALgAECgUJCwAAAA==.Click:BAABLgAECn8hAAIPAAcJ7g4DOQBpAQAPAAcJ7g4DOQBpAQAAAA==.Cloutfarmer:BAABLgAECn8vAAMPAAkJGST6AQAzAwAPAAkJGST6AQAzAwAQAAYJShtUKQDgAQAAAA==.',
Co='Comadore:BAACLgAFFH8FAAIKAAMJZAa0NgDZAAAKAAMJZAa0NgDZAAAuAAQKfxsAAgoABwnAHNY4AEACAAoABwnAHNY4AEACAAAA.',
Cr='Crankshanker:BAAALgAECgEJAQAAAA==.Cratora:BAAALgAECgYJBgAAAA==.Credan:BAEALgAECgkJEgABLgADCgYJBgARAAAAAA==.',
Cy='Cylithina:BAAALgAECgQJBwAAAA==.Cytochrome:BAAALgADCgQJBAAAAA==.',
Da='Daphe:BAAALgAECgEJAgAAAA==.Dawggbiscuit:BAAALgAECgQJBQAAAA==.',
De='Deadiam:BAAALgAECgEJAQAAAA==.Deathslead:BAAALgAECgcJCwAAAA==.Decrepe:BAABLgAECn8wAAISAAkJmB2lCgCfAgASAAkJmB2lCgCfAgAAAA==.Delph:BAAALgAECgcJEQAAAA==.Desomas:BAAALgAECgIJAgAAAA==.',
Di='Discostar:BAABLgAECn8ZAAISAAcJIBXcLwBhAQASAAcJIBXcLwBhAQAAAA==.Distill:BAAALgAECgEJAQABLgAFFAgJFAATACQgAA==.',
Do='Dominicm:BAAALgAECgYJEQAAAA==.',
Dr='Dracanalian:BAAALgADCgkJCQAAAA==.Drajhar:BAAALgAECgkJBQAAAA==.Drakyore:BAAALgADCgIJAwAAAA==.Draq:BAAALgAECgIJBAAAAA==.Druth:BAABLgAECn8lAAIUAAgJ0x0HBgA4AgAUAAgJ0x0HBgA4AgAAAA==.',
Eb='Ebonhorn:BAAALgAECgQJBwAAAA==.',
Ee='Eevillean:BAAALgAECgEJAQAAAA==.',
Ei='Einark:BAABLgAECn8bAAMVAAYJbSFuCwA0AgAVAAYJbSFuCwA0AgAWAAEJNBbUeAA5AAAAAA==.',
El='Eldrond:BAAALgAECgQJCAAAAA==.Elinis:BAAALgAECgYJBgAAAA==.',
En='Ennauríon:BAAALgAECgQJBAAAAA==.Entropy:BAEALgADCgcJFQABLgAECggJHQAXAOAVAA==.',
Er='Eridor:BAAALgAECgYJDAAAAA==.',
Ex='Exek:BAABLgAECn8XAAMYAAYJVwuaUQDxAAAYAAYJVwuaUQDxAAAGAAMJhgJLRQBeAAAAAA==.',
Fa='Fabaztard:BAAALgAECgYJEAAAAA==.Faline:BAABLgAECn8mAAISAAgJ5wr9NABFAQASAAgJ5wr9NABFAQAAAA==.',
Fe='Felgetabouit:BAACLgAFFH8GAAIDAAMJYxQ5MADvAAADAAMJYxQ5MADvAAAuAAQKfyEAAgMACAnGHMQ0ACUCAAMACAnGHMQ0ACUCAAAA.Fenrakar:BAAALgAECgIJAwAAAA==.Feywynn:BAAALgAECggJBwAAAA==.',
Fi='Fights:BAABLgAECn8mAAILAAgJvR86BQDXAgALAAgJvR86BQDXAgAAAA==.',
Fl='Fleshworker:BAAALgADCgEJAQAAAA==.',
Fo='Fordalliance:BAAALgADCgcJBwAAAA==.Forky:BAAALgAECgQJBwAAAA==.Foxknight:BAAALgAECgQJCgAAAA==.',
Fr='Franciss:BAAALgAECgYJDQAAAA==.Francys:BAAALgADCgIJAwAAAA==.Franksnbeans:BAAALgAECgEJAgABLgAECgYJEgARAAAAAA==.',
Ft='Ftx:BAABLgAECn8gAAMZAAgJuh+pDQC4AgAZAAgJlR+pDQC4AgAWAAQJ2hm0RgD6AAAAAA==.',
Fu='Fubbleskag:BAABLgAECn8xAAIKAAkJARzZEAB0AgAKAAkJARzZEAB0AgAAAA==.Fullmoonn:BAAALgAECgIJAwAAAA==.',
Ga='Gaidan:BAACLgAFFH8HAAIEAAQJAQqpEwAXAQAEAAQJAQqpEwAXAQAuAAQKfx4AAgQACQk9FoIRAI8CAAQACQk9FoIRAI8CAAEuAAUUBQkFAAMAUQQA.Gameslayer:BAABLgAECn8VAAMaAAcJRRraVABXAQAaAAQJtBzaVABXAQAbAAQJHxa9JwCMAAAAAA==.Gankzilla:BAACLgAFFH8GAAMcAAMJuQm5CQBXAAATAAIJ6AbpHQCNAAAcAAEJWw+5CQBXAAAuAAQKfyEAAxwACAlPG2EJAKoBABMABgnhF9UlAMoBABwABQmUHGEJAKoBAAAA.Gatanikaz:BAAALgAECgIJBAAAAA==.',
Ge='Get:BAAALgADCgcJBwAAAA==.',
Gh='Ghalumvhar:BAAALgAECgUJCgAAAA==.Ghrìmm:BAABLgAECn8fAAQPAAgJ8A6vLQCXAQAPAAgJww6vLQCXAQAIAAgJ4ggWEwCDAQAQAAEJ+QbwKgArAAAAAA==.',
Gi='Gila:BAAALgAECgUJBwAAAA==.Gingasorrow:BAABLgAECn8YAAISAAYJCRkAJACoAQASAAYJCRkAJACoAQAAAA==.Gizzle:BAABLgAECn8fAAIKAAgJhBg8TgD4AQAKAAgJhBg8TgD4AQAAAA==.',
Gr='Greekfire:BAABLgAECn8YAAILAAgJ4CE4GwA7AgALAAgJ4CE4GwA7AgAAAA==.Grishna:BAAALgADCggJCAAAAA==.Grumrok:BAAALgAECgQJBgAAAA==.Grunbar:BAABLgAECn8eAAIPAAcJjSF5HwBIAgAPAAcJjSF5HwBIAgAAAA==.',
Ha='Hanjha:BAABLgAECn8fAAMIAAcJcRK5EgCIAQAIAAYJcRK5EgCIAQAPAAEJAAA6zwA3AAAAAA==.Hatz:BAAALgADCgcJBgAAAA==.',
He='Healshot:BAAALgADCgMJAwABLgAECgQJDQARAAAAAA==.Helldozer:BAABLgAECn8nAAIdAAcJBhP5HgBWAQAdAAcJBhP5HgBWAQAAAA==.',
Ho='Horde:BAAALgADCgEJAQAAAA==.',
Ht='Ht:BAAALgADCgMJCAAAAA==.',
Hu='Hugzy:BAAALgAECgEJAgAAAA==.',
Hw='Hwore:BAAALgADCggJCAAAAA==.',
Hy='Hydatos:BAAALgADCgMJAwABLgAECgYJCgARAAAAAA==.Hypnocide:BAEBLgAECn8aAAIDAAYJTw5IXADpAAADAAYJTw5IXADpAAAAAA==.',
['Hô']='Hôneynuts:BAAALgADCgIJAgAAAA==.',
['Hü']='Hüngry:BAABLgAECn8jAAITAAgJdRzoCAAVAgATAAgJdRzoCAAVAgAAAA==.',
Ib='Ibuki:BAAALgAECgQJBAABLgAFFAMJBgALAHgGAA==.',
Ic='Icepick:BAAALgADCgIJAgAAAA==.',
Id='Idleorc:BAAALgADCgcJDQAAAA==.',
Il='Illandren:BAABLgAECn8UAAMIAAkJiwjdDQDJAQAIAAgJiwjdDQDJAQAQAAgJNAP8EQDTAAAAAA==.',
Im='Impsane:BAAALgAECgYJBgAAAA==.',
In='Infernis:BAAALgADCgYJCQAAAA==.Innphyy:BAABLgAECn8cAAICAAYJOgmjgAAQAQACAAYJOgmjgAAQAQAAAA==.Innøminate:BAAALgAECgUJCAABLgAECgYJEgARAAAAAA==.Inti:BAAALgADCgEJAQAAAA==.',
Ir='Irv:BAABLgAECn8WAAQcAAgJlBrMAgAhAgAcAAgJ5RnMAgAhAgATAAUJoxxNMwBwAQAeAAQJjg9lCQDZAAAAAA==.',
Is='Isadorah:BAAALgADCgcJDAAAAA==.Isekai:BAAALgAECgEJAQAAAA==.Issadruiid:BAAALgADCgYJBgAAAA==.',
Ja='Jaxxa:BAABLgAECn8aAAIPAAgJNBPHNwBuAQAPAAgJNBPHNwBuAQAAAA==.',
Je='Jeddiah:BAAALgAECgYJEwAAAA==.',
Jh='Jhals:BAAALgADCgYJBgAAAA==.',
Ji='Jinkès:BAAALgAECgQJCwAAAA==.',
Jp='Jpank:BAAALgAECgEJAQAAAA==.',
Ju='Jubei:BAABLgAFFH8FAAIKAAQJQw9yNwDUAAAKAAQJQw9yNwDUAAAAAA==.Judis:BAABLgAECn86AAIcAAgJhxgcAwANAgAcAAgJhxgcAwANAgAAAA==.Juicy:BAAALgADCgIJAgAAAA==.',
Ka='Kainel:BAAALgAECgkJCQAAAA==.Kairì:BAAALgADCgcJDQAAAA==.Kalifist:BAABLgAECn8UAAIWAAkJ6xjDGgAJAgAWAAkJ6xjDGgAJAgAAAA==.Kalinear:BAAALgADCgQJBQAAAA==.Kaliscales:BAAALgAECgUJBQAAAA==.Kamiportal:BAAALgAECgYJCQAAAA==.Kanajotoma:BAAALgAECgQJCgAAAA==.Karlai:BAABLgAECn8gAAIfAAcJuBohBACzAQAfAAcJuBohBACzAQABLgAFFAUJBQADAFEEAA==.Kaslana:BAEALgADCgYJBgAAAA==.',
Ke='Keldrune:BAAALgAECgEJAQAAAA==.Keleena:BAEBLgAECn8bAAILAAYJYx/4EgD9AQALAAYJYx/4EgD9AQAAAA==.Kelume:BAAALgADCgMJAwAAAA==.Kely:BAAALgADCgUJBgAAAA==.',
Ki='Kinst:BAABLgAECn8bAAMQAAYJihPlEADgAAAPAAYJtwuoXAD6AAAQAAYJrxLlEADgAAAAAA==.Kisäi:BAABLgAECn8kAAIDAAkJ1Rz3EwAdAgADAAkJ1Rz3EwAdAgAAAA==.Kitanyia:BAAALgAECgYJDgAAAA==.Kittiy:BAABLgAECn8aAAMSAAYJbQVzVADGAAASAAYJbQVzVADGAAAEAAYJzAGVRQBoAAAAAA==.',
Ko='Kordelia:BAABLgAECn8dAAICAAgJQh68FAB0AgACAAgJQh68FAB0AgAAAA==.Korvus:BAAALgAECgcJEQAAAA==.',
Kv='Kv:BAAALgADCggJCAAAAA==.',
Ky='Kyakuna:BAAALgAECgIJAgAAAA==.Kylnara:BAAALgAECgIJAgABLgAECgQJCAARAAAAAA==.Kyloon:BAAALgAECgEJAQAAAA==.Kyrah:BAABLgAECn8VAAIMAAYJ3xvLBgDrAQAMAAYJ3xvLBgDrAQAAAA==.',
La='Lamanira:BAAALgAECgIJBAAAAA==.Lancier:BAAALgAECgIJBAAAAA==.',
Le='Lecleme:BAABLgAECn8UAAIgAAgJeBL5VAA/AQAgAAgJeBL5VAA/AQAAAA==.Lejend:BAABLgAECn8jAAMbAAcJQiNoAwBtAgAbAAcJQiNoAwBtAgAaAAMJfRWyfwC+AAAAAA==.Lenthalis:BAAALgAECgUJDAAAAA==.Lezriel:BAAALgAECgMJBgAAAA==.',
Li='Lichin:BAAALgADCgEJAQAAAA==.Lilithh:BAAALgADCgUJCAAAAA==.',
Ll='Llanedh:BAAALgAECgYJBgAAAA==.',
Lo='Loaganic:BAAALgAECgQJBAABLgAECggJFAAFAOcLAA==.Lockheéd:BAAALgAECgEJAQAAAA==.Lonelyhearts:BAABLgAECn8XAAIKAAcJYgWydQABAQAKAAcJYgWydQABAQAAAA==.Lonestar:BAAALgAECgYJCgAAAA==.Lonestarr:BAAALgAECgQJCQAAAA==.',
Lu='Lumiya:BAABLgAECn8yAAIYAAkJ8A4gFgCiAQAYAAkJ8A4gFgCiAQAAAA==.',
Ly='Lytol:BAAALgAECgYJEgAAAA==.',
Ma='Machu:BAAALgADCgIJAgABLgAECgkJLQAFAC4dAA==.Madderhorn:BAAALgAECgcJBQAAAA==.Maenad:BAAALgAECgIJAgABLgAECgYJBgARAAAAAA==.Maeple:BAABLgAECn8WAAIYAAgJ9Bz5BQCeAgAYAAgJ9Bz5BQCeAgAAAA==.Magikin:BAAALgAECgEJAgAAAA==.Mamichula:BAAALgAECgEJAQAAAA==.',
Mb='Mbdtf:BAACLgAFFH8QAAMIAAUJxR/bAADUAQAIAAQJlCbbAADUAQAQAAEJjASvJABVAAAuAAQKfxYAAwgABwlVJFoEANQCAAgABwn6I1oEANQCABAAAQksI/92AGMAAAEuAAUUCAkfAAIAuCMA.',
Me='Mechagnome:BAABLgAECn8rAAMWAAkJESAZAgD9AgAWAAkJESAZAgD9AgAVAAgJCQQFOgAAAQAAAA==.Meeps:BAAALgADCgcJBwAAAA==.Megamedes:BAABLgAECn8aAAMKAAYJkhbOegCEAQAKAAYJEhbOegCEAQAhAAQJTQkvIACTAAAAAA==.Meigna:BAABLgAECn8iAAIGAAgJwhlGCgAgAgAGAAgJwhlGCgAgAgAAAA==.Mekö:BAAALgAECgYJDQAAAA==.Meladyn:BAACLgAFFH8aAAIiAAUJPCLtAACaAQAiAAUJPCLtAACaAQAuAAQKfyMAAyIABwlnJlYDAAMDACIABwlnJlYDAAMDACMABAlNIfMJAH8BAAAA.Melritza:BAAALgAECgQJCAAAAA==.Mentock:BAAALgAECgQJCAAAAA==.Merelandra:BAAALgADCgcJCwAAAA==.Mermaid:BAAALgAECgUJCgAAAA==.',
Mi='Miliara:BAAALgADCgEJAQAAAA==.Missmaam:BAAALgAECgEJAgAAAA==.Mithrandir:BAAALgAECgkJBwAAAA==.Mixcoati:BAAALgADCgQJBQAAAA==.Mizu:BAAALgAECgkJEwAAAA==.',
Mo='Monkfox:BAAALgAECgcJBwAAAA==.Morgianna:BAAALgADCgEJAQAAAA==.',
Mu='Mudflap:BAAALgAECgUJCQAAAA==.Mushuwoonter:BAAALgAECgEJAQABLgAECgkJLQAFAC4dAA==.Muztang:BAABLgAECn8aAAMbAAcJRxWxCwCIAQAbAAcJeRSxCwCIAQAaAAYJihMYJQBJAQAAAA==.',
Mw='Mwmmwmm:BAAALgAECgMJAwAAAA==.',
My='Mythandwel:BAAALgAECgYJEwAAAA==.',
['Mä']='Mäddiey:BAAALgAECgQJBQAAAA==.',
['Mô']='Mônkii:BAACLgAFFH8GAAIZAAMJBR++FAAeAQAZAAMJBR++FAAeAQAuAAQKfzAAAhkACQnAJMAAAEwDABkACQnAJMAAAEwDAAAA.',
Na='Nace:BAABLgAECn8lAAITAAkJ7BOiCgD2AQATAAkJ7BOiCgD2AQAAAA==.Nadriede:BAAALgADCgYJBgAAAA==.Naenia:BAAALgADCgQJBAAAAA==.Naillimixam:BAAALgADCgMJAgAAAA==.Nateldin:BAABLgAECn8WAAMKAAgJ3wmIkABbAQAKAAgJDgiIkABbAQAhAAIJ9Q6EMgAuAAAAAA==.',
Ni='Nicksevokerc:BAAALgAECggJBwAAAA==.Niisha:BAAALgAECgcJCwABLgAECgkJHgAYAKMHAA==.Nikiso:BAAALgADCgQJBAAAAA==.',
No='Nocainus:BAABLgAECn8lAAIJAAcJLBv1CQDdAQAJAAcJLBv1CQDdAQAAAA==.Nosehole:BAAALgAECgYJEQAAAA==.Novari:BAAALgADCgkJCQAAAA==.',
Nv='Nv:BAAALgADCgEJAQAAAA==.',
['Nø']='Nøtsure:BAAALgAECgYJEgAAAA==.',
Ob='Obsidia:BAABLgAECn8UAAINAAcJ8QgnbgDuAAANAAcJ8QgnbgDuAAAAAA==.',
Oc='Octopusprime:BAAALgAECgkJDgAAAA==.',
Ol='Ollix:BAEALgAECgEJAQABLgAECgcJJAADAOQXAA==.',
Om='Omelette:BAAALgAECggJEwAAAA==.',
On='Onik:BAAALgADCgcJDQABLgAECgQJCAARAAAAAA==.',
Op='Ophj:BAABLgAECn8gAAICAAkJtiJgBwCRAwACAAkJtiJgBwCRAwAAAA==.',
Or='Orangejulius:BAAALgAECgIJBgAAAA==.Orangutan:BAAALgAECgMJBAAAAA==.Oriigami:BAAALgAECgMJBQAAAA==.Orinoheal:BAAALgADCgUJBQAAAA==.',
Os='Oshtudead:BAAALgADCgQJBAAAAA==.',
Pe='Perilous:BAAALgAECgQJCAAAAA==.Pewpëw:BAAALgADCgkJDwAAAA==.',
Ph='Phoelar:BAAALgAECgEJAQAAAA==.Phuumyn:BAABLgAECn8kAAIWAAcJ+B+yCAA1AgAWAAcJ+B+yCAA1AgAAAA==.',
Pi='Piccoblast:BAACLgAFFH8SAAICAAUJ1xYNDQCzAQACAAUJ1xYNDQCzAQAuAAQKfyIAAgIACAnPIt4cAAIDAAIACAnPIt4cAAIDAAAA.Piccopew:BAAALgAECgEJAQABLgAFFAUJEgACANcWAA==.Pichus:BAAALgAECgEJAQAAAA==.Picklesoup:BAAALgAECgcJCQAAAA==.Pierrecurzi:BAAALgAECgMJAwABLgAFFAMJCgAQAH0ZAA==.Piickles:BAACLgAFFH8XAAMYAAUJzRGxBQAoAQAHAAQJ7AzJEgAuAQAYAAQJSBKxBQAoAQAuAAQKfx8AAhgABwndItwLAJMCABgABwndItwLAJMCAAAA.Pinkcanibus:BAAALgAECgYJDAAAAA==.Pity:BAAALgAECgcJCAAAAA==.',
Pl='Plutø:BAABLgAECn8iAAMJAAgJ5BsKDABRAgAJAAcJaB4KDABRAgAgAAgJdRFANACoAQAAAA==.',
Po='Polylocks:BAAALgAECgUJBQAAAA==.Pompey:BAAALgAECgEJAQAAAA==.',
Pr='Praeastra:BAEBLgAECn8dAAIXAAgJ4BUoAgDbAQAXAAgJ4BUoAgDbAQAAAA==.Promethius:BAAALgAECgcJCQABLgAECgkJBwARAAAAAA==.Protein:BAABLgAECn8gAAIaAAcJ0BUeGQCeAQAaAAcJ0BUeGQCeAQAAAA==.Prplxd:BAAALgADCgUJBQABLgAECgYJCgARAAAAAA==.Prókill:BAAALgADCgcJBwAAAA==.',
Ps='Psychokitty:BAABLgAECn8jAAISAAgJaBxICwCVAgASAAgJaBxICwCVAgAAAA==.',
Py='Pyppi:BAAALgADCgEJAQABLgAECgUJBQARAAAAAA==.',
['Pô']='Pôwersm:BAAALgADCgMJAwAAAA==.',
Qu='Quilian:BAACLgAFFH8GAAIYAAMJPSOTCQAsAQAYAAMJPSOTCQAsAQAuAAQKfyQAAhgACAlIJCYEABIDABgACAlIJCYEABIDAAAA.',
Ra='Raelynn:BAABLgAECn8lAAIYAAcJBxVDGwBxAQAYAAcJBxVDGwBxAQAAAA==.Raevenhart:BAACLgAFFH8GAAIQAAMJlghFDgDVAAAQAAMJlghFDgDVAAAuAAQKfx0AAhAACAlYFVokAAUCABAACAlYFVokAAUCAAAA.Rainstorm:BAAALgADCgQJBAAAAA==.Rappa:BAAALgADCgEJAQAAAA==.Raptorx:BAAALgADCgcJBwAAAA==.Raymond:BAAALgADCgcJBwAAAA==.',
Re='Rebarbative:BAABLgAECn8VAAMNAAgJUQtfQABoAQANAAgJUQtfQABoAQAkAAMJfAXUUQB5AAAAAA==.Redvex:BAABLgAECn80AAQNAAkJ/yThAQBNAwANAAkJoCThAQBNAwAkAAUJMSCOEgC3AQAMAAIJcCPsHwBzAAAAAA==.Rei:BAAALgAECgEJAQAAAA==.Reinhard:BAABLgAECn8ZAAMKAAgJxQ/ESQBoAQAKAAgJAQvESQBoAQAhAAUJfBXoHQAbAQAAAA==.Resjamyn:BAAALgADCgEJAQAAAA==.Revengè:BAAALgADCgQJBAAAAA==.Rewrew:BAABLgAECn8mAAILAAgJAxyFCQB5AgALAAgJAxyFCQB5AgAAAA==.',
Rh='Rhedman:BAAALgAECgYJDQAAAA==.',
Ri='Ricasti:BAAALgAECgUJCgAAAA==.Rinahrune:BAAALgAECgMJBQAAAA==.Rinahvoid:BAAALgADCgcJBwAAAA==.',
Ro='Robat:BAAALgADCggJCAAAAA==.Rotyr:BAABLgAECn8VAAIHAAYJBhUQFwCBAQAHAAYJBhUQFwCBAQAAAA==.',
Ru='Ruana:BAEALgAECgQJBwAAAA==.Rubyrazor:BAAALgAECgQJBgAAAA==.Rumpunch:BAAALgAECgEJAQAAAA==.',
Sa='Safetydance:BAAALgAECgIJAgAAAA==.Salil:BAAALgADCgMJAwAAAA==.Salothos:BAAALgADCgYJBgAAAA==.Samesh:BAAALgAECgQJCAAAAA==.Sandrace:BAAALgADCgIJAgAAAA==.Sanginie:BAAALgADCgEJAQAAAA==.Satrana:BAAALgADCgMJAwAAAA==.Sauroman:BAAALgAECgUJDgAAAA==.',
Sc='Scoobey:BAABLgAECn8UAAIPAAYJyxoOXAD8AAAPAAYJyxoOXAD8AAAAAA==.Scubbs:BAACLgAFFH8GAAIlAAMJMguzJgC5AAAlAAMJMguzJgC5AAAuAAQKfyEAAiUACAkuFkoiABECACUACAkuFkoiABECAAAA.Scubbsboo:BAAALgAECgQJCAABLgAFFAMJBgAlADILAA==.',
Se='Servantes:BAABLgAECn8iAAISAAcJcAydQwAEAQASAAcJcAydQwAEAQAAAA==.',
Sh='Shackleford:BAABLgAECn8fAAMHAAcJKx/gEQAnAgAHAAcJKx/gEQAnAgAYAAEJMRiceQBCAAAAAA==.Shamwõwz:BAAALgAECgcJCwAAAA==.Sheck:BAAALgAECgEJAQAAAA==.Shessofine:BAAALgAECggJCQAAAA==.Shotya:BAABLgAECn8lAAIPAAcJfwoePwBRAQAPAAcJfwoePwBRAQAAAA==.',
Si='Siath:BAABLgAECn8UAAMFAAgJ5wtEHwBFAQAFAAgJ5wtEHwBFAQAmAAIJ6gg0PQA5AAAAAA==.Sixthknight:BAAALgADCgkJIgAAAA==.',
Sl='Slarr:BAAALgADCgEJAgAAAA==.',
Sm='Smight:BAABLgAECn8dAAILAAgJFyY3AQBmAwALAAgJFyY3AQBmAwAAAA==.',
Sn='Snarkypony:BAAALgAECgIJBAAAAA==.',
So='Solani:BAAALgADCgYJCQAAAA==.Solania:BAAALgAECgYJCgAAAA==.Soloqenjoyer:BAAALgAECgUJBQAAAA==.Sorsere:BAABLgAECn8aAAINAAYJKhlWOACEAQANAAYJKhlWOACEAQAAAA==.',
Sp='Spcecialk:BAAALgAECgcJEgAAAA==.Specialk:BAABLgAECn8zAAMdAAcJRxC+HwBQAQAdAAcJRxC+HwBQAQAlAAEJtQHYjAAgAAAAAA==.',
Sq='Squallie:BAAALgAECgYJCQAAAA==.',
St='Steamedhams:BAAALgAECgMJAwABLgAECgUJCAARAAAAAA==.Stromm:BAACLgAFFH8FAAIDAAUJUQS2LwDyAAADAAUJUQS2LwDyAAAuAAQKfxUAAgMACAkdFhonAKABAAMACAkdFhonAKABAAAA.',
Su='Sundorei:BAAALgADCgEJAQAAAA==.',
Ta='Tahoe:BAAALgADCgIJAgAAAA==.Talshekar:BAABLgAECn8XAAImAAcJdgfFCQAFAQAmAAcJdgfFCQAFAQAAAA==.',
Te='Teiana:BAABLgAECn8oAAIKAAkJxx8UCQDEAgAKAAkJxx8UCQDEAgAAAA==.Tezlyn:BAAALgAECgEJAgAAAA==.',
Th='Thaevin:BAAALgAECgYJEAAAAA==.Therony:BAAALgAECgkJBQAAAA==.Thingwan:BAABLgAECn8gAAISAAgJ/Rd4GwDoAQASAAgJ/Rd4GwDoAQAAAA==.Thordak:BAAALgADCggJDQABLgAECggJGAAKAGQPAA==.',
Ti='Timbuktoo:BAAALgAECgEJAQAAAA==.Tinypoop:BAABLgAECn8WAAICAAYJVBXJXgBVAQACAAYJVBXJXgBVAQAAAA==.Tinystain:BAAALgADCgcJDQAAAA==.Tinystink:BAAALgAECgQJBAAAAA==.Tiptugger:BAAALgAECgIJAgAAAA==.',
To='Toddstephens:BAAALgAECgQJDAAAAA==.Tors:BAABLgAECn80AAIEAAkJnRMUDQD6AQAEAAkJnRMUDQD6AQAAAA==.',
Tr='Trogdore:BAAALgAECgQJCAAAAA==.Trollololo:BAABLgAECn8lAAMCAAcJlg8NUQB3AQACAAcJlg8NUQB3AQAnAAMJ+wfsCgCPAAAAAA==.Troy:BAABLgAECn8jAAICAAgJwB3rFQBrAgACAAgJwB3rFQBrAgAAAA==.Truid:BAAALgADCgEJAQAAAA==.Trylly:BAAALgAECgIJAgABLgAECgUJBQARAAAAAA==.',
Tt='Ttaartt:BAACLgAFFH8aAAIBAAUJrhJOCgB0AQABAAUJrhJOCgB0AQAuAAQKfx0AAgEABwmqGeoSABICAAEABwmqGeoSABICAAAA.',
Tu='Tuckstaken:BAAALgAECgIJAgAAAA==.',
Ty='Typh:BAACLgAFFH8IAAIcAAMJ7BiIAwAZAQAcAAMJ7BiIAwAZAQAuAAQKfzAAAhwACQlXI00AAD0DABwACQlXI00AAD0DAAAA.Tyrone:BAABLgAECn8bAAMWAAgJlRtJBwBUAgAWAAgJlRtJBwBUAgAVAAIJaQcOYgBHAAAAAA==.',
Uf='Uffish:BAAALgADCgUJBgAAAQ==.',
Ug='Uglymagi:BAAALgAECgMJBAAAAA==.',
Un='Undeaddemon:BAABLgAECn8iAAQNAAkJIx2AFQA2AgANAAgJIx2AFQA2AgAMAAIJ/QgTHwB4AAAkAAEJkAa+eAAqAAAAAA==.Undeaddh:BAAALgADCgkJAgABLgAECgkJIgANACMdAA==.Undeadmaggot:BAAALgADCggJFAABLgAECgkJIgANACMdAA==.Undeadscaly:BAAALgAECgUJBQABLgAECgkJIgANACMdAA==.Undignified:BAABLgAECn8ZAAIcAAYJVA+QCQA0AQAcAAYJVA+QCQA0AQAAAA==.Unholysixth:BAAALgADCgcJEgAAAA==.Unicornquen:BAAALgAECgEJAQAAAA==.',
Ur='Uriyah:BAAALgAECgEJAQAAAA==.',
Uz='Uzzìel:BAAALgADCgEJAQAAAA==.',
Va='Vanidarr:BAAALgADCgEJAQAAAA==.',
Ve='Verasia:BAAALgAECgQJCgAAAA==.',
Vi='Vidikan:BAAALgAECgQJCgAAAA==.Vie:BAAALgAECgEJAQAAAA==.',
Vo='Voidwarranty:BAABLgAECn8nAAMlAAgJxxhXEgAlAgAlAAgJxxhXEgAlAgAdAAMJohULOgDEAAAAAA==.Vontoot:BAAALgADCgEJAQAAAA==.',
Vv='Vvumpscut:BAABLgAECn8bAAIlAAcJRRzSGwDSAQAlAAcJRRzSGwDSAQAAAA==.',
Vy='Vysena:BAAALgAECgEJAQAAAA==.',
Wa='Waldón:BAABLgAECn8lAAInAAgJpApDAwBhAQAnAAgJpApDAwBhAQAAAA==.',
We='Werrik:BAAALgAECgYJEgABLgAFFAIJAgARAAAAAA==.',
Wi='Wildsoul:BAABLgAECn8jAAIlAAcJPxIjKAB+AQAlAAcJPxIjKAB+AQAAAA==.Winchester:BAAALgADCgMJAwAAAA==.',
Wo='Wolfguardiån:BAAALgADCgMJAwAAAA==.',
Wr='Wrenz:BAAALgAECgQJCgAAAA==.',
Wu='Wuha:BAAALgADCgEJAQAAAA==.',
['Wä']='Wärhämmer:BAAALgADCgcJCgAAAA==.',
Xa='Xaneva:BAAALgADCgEJAgABLgAFFAUJGgAiADwiAA==.Xanxer:BAAALgADCgQJBQAAAA==.',
Xc='Xclaw:BAAALgAECgcJEQAAAA==.',
Xe='Xeroxgravîty:BAAALgAECgEJAQAAAA==.',
Xi='Xilphira:BAAALgAECgEJAQAAAA==.',
Xl='Xlithz:BAABLgAECn8qAAMbAAgJwBdLCQC2AQAaAAgJLReLDwD7AQAbAAgJPhJLCQC2AQAAAA==.',
['Xí']='Xílo:BAEBLgAECn8kAAMDAAcJ5BdXKgCPAQADAAcJ5BdXKgCPAQAOAAEJ+AcLQgAyAAAAAA==.',
Yl='Ylene:BAAALgAECgYJCQAAAA==.',
Yo='Yoink:BAACLgAFFH8GAAIgAAMJkQ8nUgDqAAAgAAMJkQ8nUgDqAAAuAAQKfycAAiAACQl7H9EGAO8CACAACQl7H9EGAO8CAAAA.',
Za='Zalasham:BAAALgADCgIJAgAAAA==.Zarinchaos:BAAALgADCgkJEgAAAA==.Zarinfur:BAABLgAECn8kAAIiAAgJehTbBwC1AQAiAAgJehTbBwC1AQAAAA==.Zazikalestra:BAABLgAECn8bAAQBAAgJEBdYFwDdAQABAAgJEBdYFwDdAQAFAAQJhQSaTwCPAAAmAAEJAAAcPwAzAAAAAA==.',
Ze='Zedrin:BAAALgAECgQJBAAAAA==.Zein:BAAALgAECgIJBAAAAA==.Zentacle:BAAALgAECgIJAgAAAA==.Zente:BAABLgAECn8bAAMPAAcJ0BOTRgCXAQAPAAcJ0BOTRgCXAQAQAAEJ9QCMmQAbAAAAAA==.Zequill:BAABLgAECn8mAAIUAAgJLiLdAgCrAgAUAAgJLiLdAgCrAgAAAA==.Zevsticles:BAABLgAECn8nAAIPAAkJUx+RCgCQAgAPAAkJUx+RCgCQAgAAAA==.',
Zh='Zhom:BAACLgAFFH8KAAIQAAMJfRmiDADxAAAQAAMJfRmiDADxAAAuAAQKfzQAAhAACQksIVwBALcCABAACQksIVwBALcCAAAA.',
Zo='Zohm:BAAALgADCgMJAwAAAA==.Zolec:BAAALgADCgcJDgAAAA==.Zooj:BAABLgAECn8kAAIoAAcJ9gyUCwBTAQAoAAcJ9gyUCwBTAQAAAA==.Zorlak:BAAALgAECgUJCQAAAA==.',
Zy='Zylofeather:BAAALgAECgQJBAAAAA==.',
['ße']='ßeast:BAAALgAECgYJDgAAAA==.',
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

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

local lookup = {'Unknown-Unknown','Druid-Balance','Druid-Guardian','Mage-Frost','Shaman-Restoration','Druid-Feral','Warlock-Demonology','Warrior-Fury','Mage-Arcane','Warrior-Protection','Shaman-Elemental','Paladin-Retribution','Monk-Mistweaver','Druid-Restoration','Monk-Windwalker','Shaman-Enhancement','Paladin-Holy','Monk-Brewmaster','Evoker-Augmentation','DemonHunter-Havoc','DemonHunter-Devourer','Paladin-Protection','Hunter-BeastMastery','DeathKnight-Unholy','Warlock-Destruction','Priest-Shadow','Evoker-Devastation','DeathKnight-Blood',}
local provider = {region='US',realm='AlteracMountains',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Abyssia:BAAALgAECgkJBQAAAA==.',
Ac='Acupuncher:BAAALgADCgEJAgAAAA==.',
Ad='Aderana:BAAALgADCgYJBgAAAA==.Adesireyn:BAAALgAECgQJBgAAAA==.',
Ai='Airmed:BAAALgAECgQJBAAAAA==.',
Al='Alcha:BAAALgAECgYJEgAAAA==.Alchalite:BAAALgADCgYJBgABLgAECgYJEgABAAAAAA==.Alenndar:BAAALgAECgQJBAAAAA==.Alexdaddario:BAABLgAECn8cAAMCAAYJIyHzHgAIAgACAAYJIyHzHgAIAgADAAIJ2gjaDABIAAAAAA==.Alkuhh:BAAALgADCgcJDgABLgAECgYJEgABAAAAAA==.Altdps:BAAALgAECgYJDQAAAA==.',
Am='Amareyna:BAAALgAECgYJEwAAAA==.Amos:BAAALgADCgkJGAABLgAECgYJEwABAAAAAA==.',
An='Anadeius:BAAALgADCgMJAwAAAA==.Animeniac:BAAALgAECgUJDQAAAA==.Annalease:BAAALgAECgIJAgAAAA==.Anticlimax:BAAALgAECgYJEwAAAA==.Antipathy:BAAALgADCgIJAgAAAA==.Antisocial:BAAALgADCggJGAAAAA==.',
Ap='Apparition:BAAALgAECgcJDQAAAA==.Apprentice:BAABLgAECn8fAAIEAAgJuCJPFQAoAwAEAAgJuCJPFQAoAwAAAA==.',
Ar='Argonar:BAAALgAECgcJDwAAAA==.Arthras:BAAALgADCgYJBgAAAA==.',
As='Ashelia:BAAALgAECgQJCQAAAA==.Ashian:BAAALgAECgMJAwAAAA==.Aslio:BAABLgAECn8WAAIFAAgJEBtxFgBiAgAFAAgJEBtxFgBiAgAAAA==.',
At='Atreyou:BAAALgADCgkJDwAAAA==.Atultak:BAABLgAECn8VAAQDAAYJ4AQXJQB0AAADAAUJIAUXJQB0AAACAAEJ4gNliQAmAAAGAAEJkQMvOQAkAAAAAA==.',
Au='Aurum:BAABLgAECn8bAAIFAAgJyg9ICgCZAQAFAAgJyg9ICgCZAQAAAA==.',
Av='Avdol:BAAALgAECgcJDgABLgAFFAQJBwAHAPEdAA==.Avienndha:BAAALgAECgUJDQAAAA==.',
Aw='Awake:BAAALgAECgYJDAAAAA==.',
Az='Azgrunga:BAABLgAECn8fAAIIAAgJMBgTHQBlAgAIAAgJMBgTHQBlAgAAAA==.',
Ba='Banditbear:BAAALgAECgQJBAAAAA==.Barf:BAAALgAECgQJCgAAAA==.Battlecattle:BAAALgADCgYJCQAAAA==.',
Be='Beastmodedp:BAAALgAECgkJBwAAAA==.Bel:BAAALgADCgcJEgAAAA==.',
Bl='Blapdragon:BAAALgADCgEJAQAAAA==.Bloodvalor:BAAALgADCgYJBgABLgAECgYJFAAJAJkTAA==.',
Bo='Bobbytofva:BAABLgAECn8XAAIIAAcJXxlyOQDBAQAIAAcJXxlyOQDBAQAAAA==.Bobtheman:BAAALgADCgEJAQAAAA==.Boochaka:BAABLgAECn8UAAIFAAcJUhTNMgC6AQAFAAcJUhTNMgC6AQAAAA==.',
Br='Breesus:BAAALgAECgMJAwAAAA==.Brochefski:BAABLgAECn8bAAIKAAgJNSBJAQBKAgAKAAgJNSBJAQBKAgAAAA==.Brotherfuzz:BAAALgAECggJDwAAAA==.Bráscubas:BAAALgAECgEJAQAAAA==.',
Bu='Bubbernubs:BAAALgADCgUJAQAAAA==.Busterposer:BAAALgAECgEJAQAAAA==.Buu:BAAALgAECgYJBgAAAA==.',
['Bö']='Böb:BAAALgAECgQJBQAAAA==.',
Ca='Calabooca:BAAALgADCgcJBwAAAA==.Candor:BAAALgADCgUJBgAAAA==.Caramilk:BAAALgAECggJCwABLgAECgcJFAAHAAEZAA==.Cashthegreat:BAAALgAECgMJAwAAAA==.',
Ce='Celily:BAAALgADCgYJBgAAAA==.',
Ch='Chain:BAABLgAECn8WAAMFAAYJ+xvRLQDSAQAFAAYJ+xvRLQDSAQALAAQJmQ5qZwClAAAAAA==.Cheesefries:BAAALgAECgUJCwAAAA==.Chereth:BAAALgAECgcJEAAAAA==.Chocola:BAAALgADCgEJAQAAAA==.Chouko:BAAALgAECgcJDgAAAA==.Chronovan:BAAALgAECgUJBgAAAA==.Chrotch:BAAALgADCgQJBAAAAA==.',
Ci='Cirad:BAAALgADCgIJAgAAAA==.',
Cl='Claep:BAAALgAECgYJCwAAAA==.',
Co='Cogglutch:BAAALgADCgMJAwABLgADCgYJBgABAAAAAA==.Cokegirll:BAAALgAECgQJBgAAAA==.',
Cr='Creamcorn:BAAALgADCgUJBQABLgAECggJEgABAAAAAA==.Creamie:BAAALgAECgYJDgABLgAECggJEgABAAAAAA==.Creamish:BAAALgAECggJEgAAAA==.Cricketts:BAAALgADCgcJDgAAAA==.Critties:BAAALgADCgcJDAAAAA==.Crueldin:BAAALgAECgYJCwAAAA==.Cryptos:BAAALgAECgQJBgAAAA==.',
Cy='Cybertruck:BAAALgADCgUJBgAAAA==.',
['Cé']='Célery:BAAALgAECgMJBQAAAA==.',
Da='Dacrus:BAAALgAECgEJAwAAAA==.Dalsen:BAABLgAECn8ZAAIDAAgJygs5GQDoAAADAAgJygs5GQDoAAAAAA==.Damnadin:BAAALgAECgUJBQAAAA==.Dankchop:BAAALgAECgYJCwAAAA==.Daredevil:BAAALgADCgEJAQABLgADCgYJBgABAAAAAA==.Darim:BAAALgAECgMJAwAAAA==.Darkgoomba:BAAALgADCggJCQAAAA==.',
De='Deathwinne:BAAALgADCgEJAQAAAA==.Demonfed:BAAALgAECgEJAQABLgAECgQJBwABAAAAAA==.Denaian:BAAALgADCgcJCwAAAA==.Denoran:BAAALgADCgUJBwAAAA==.Deone:BAAALgAECgUJDAAAAA==.Deskpop:BAAALgADCgYJBwAAAA==.Dewberry:BAAALgAECgEJAQAAAA==.Deáth:BAAALgAECgMJBgAAAA==.',
Di='Diabolikal:BAAALgAECgQJBQAAAA==.Dill:BAABLgAECn8nAAIIAAkJdB4bAQCMAgAIAAkJdB4bAQCMAgAAAA==.Diomedus:BAAALgADCggJDgAAAA==.',
Dk='Dkjosh:BAAALgAECgQJBQAAAA==.',
Do='Doctowatson:BAAALgADCgYJBgAAAA==.Donkeykông:BAAALgAECgQJBQAAAA==.',
Dr='Drassa:BAAALgADCgEJAQAAAA==.Drazzak:BAAALgADCgUJCQAAAA==.Drunkfuq:BAAALgAECgEJAQAAAA==.Druwulf:BAAALgAECgEJAQAAAA==.Drwarlacko:BAAALgADCgcJBwAAAA==.Drwatsonpal:BAAALgAECgEJAQAAAA==.Drùna:BAABLgAECn8YAAICAAcJLgxQEADwAAACAAcJLgxQEADwAAAAAA==.',
Du='Durkidurk:BAAALgAECgEJAQAAAA==.',
Dw='Dwude:BAAALgADCgEJAwAAAA==.',
Dy='Dyabolykal:BAAALgAECgQJBAABLgAECgQJBQABAAAAAA==.',
El='Eleramdar:BAAALgAECgQJBAAAAA==.Eligio:BAABLgAECn8XAAIMAAgJ9BIwEACkAQAMAAgJ9BIwEACkAQAAAA==.Elsharion:BAAALgAECgYJCgABLgAFFAUJDgANAP8bAA==.Elshary:BAAALgADCgkJCQAAAA==.Elsharyon:BAAALgAECgMJAwABLgAFFAUJDgANAP8bAA==.Elshie:BAACLgAFFH8OAAINAAUJ/xutAQCrAQANAAUJ/xutAQCrAQAuAAQKfxQAAg0ACQn8HVoNAH8CAA0ACQn8HVoNAH8CAAAA.',
Em='Emachine:BAAALgAFFAIJAgABLgAFFAQJBwAHAPEdAA==.',
Es='Eskyxy:BAAALgAECgEJAQAAAA==.Espressoul:BAAALgADCgQJAwAAAA==.',
Ev='Evergreen:BAABLgAECn8fAAIOAAgJORemHwBEAgAOAAgJORemHwBEAgAAAA==.',
Fa='Fastasheet:BAACLgAFFH8SAAIPAAUJIiE2AQDRAQAPAAUJIiE2AQDRAQAuAAQKfygAAg8ACQnKJCIAAEYDAA8ACQnKJCIAAEYDAAAA.',
Fe='Felcollins:BAAALgAECgYJDQAAAA==.Fenrirr:BAAALgAECgUJBgAAAA==.',
Fi='Fill:BAABLgAECn8VAAIQAAYJhCM2CABfAgAQAAYJhCM2CABfAgAAAA==.Fistcleave:BAAALgAECgQJBQAAAA==.',
Fl='Flatwhite:BAAALgAECgUJBwAAAA==.Fleshtofill:BAAALgADCgkJCQAAAA==.Flexible:BAAALgADCgcJCgAAAA==.Flyinbanana:BAAALgAECgIJAwABLgAECgYJCwABAAAAAA==.',
Fr='Frags:BAABLgAECn8aAAIRAAgJOhW0JgD0AQARAAgJOhW0JgD0AQAAAA==.',
Fy='Fyrefest:BAAALgAECgYJBgAAAA==.',
Ga='Galvek:BAAALgADCgQJBAAAAA==.Ganska:BAAALgAECgcJBwAAAA==.Garmonbozia:BAAALgADCgEJAgAAAA==.Garrytt:BAAALgAECgYJCAAAAA==.Gatsumoto:BAAALgADCgkJEAAAAA==.',
Ge='Genjyosanzo:BAAALgAECgUJCgAAAA==.Gertrex:BAAALgADCgEJAgAAAA==.',
Gi='Gilfu:BAABLgAECn8cAAISAAgJSSIbCAAEAwASAAgJSSIbCAAEAwAAAA==.Gimmixdh:BAAALgADCgMJAwAAAA==.Gingavitis:BAAALgADCgYJBAAAAA==.',
Go='Goey:BAAALgADCgYJAQAAAA==.Gothmommy:BAAALgADCgEJAQABLgAFFAQJBwATAEUMAA==.',
Gr='Gremussy:BAAALgADCgMJAwAAAA==.Grito:BAAALgAECgQJDAAAAA==.Grokdepaly:BAAALgAECgMJAwAAAA==.Grunkpatunga:BAAALgAECgUJBgAAAA==.',
Ha='Halsina:BAAALgAECgEJAQAAAA==.Hanittumn:BAAALgADCgQJBAAAAA==.Harrysax:BAAALgAECgkJAwAAAA==.',
He='Healadem:BAAALgADCgcJDAAAAA==.Healamage:BAAALgAECgMJBAAAAA==.',
Hi='Highfeather:BAAALgAECgUJEQAAAA==.Hilazy:BAAALgAECgUJCwAAAA==.Hiping:BAAALgAECgIJAgAAAA==.',
Ho='Holycanuk:BAAALgAECgEJBAAAAA==.Holyfed:BAAALgAECgQJBwAAAA==.Holyphok:BAAALgAECgYJDwAAAA==.Holysheet:BAAALgAFFAEJAQAAAA==.Hort:BAAALgAECgMJBgAAAA==.Hotdog:BAAALgAECgEJAQAAAA==.',
Hu='Huneybutta:BAAALgADCgEJAQAAAA==.',
Hy='Hyla:BAAALgAECgYJCwAAAA==.',
Ib='Ibackstab:BAAALgADCgcJCgAAAA==.',
Ic='Icestormy:BAAALgAECgYJDwAAAA==.',
Ih='Ihasaface:BAAALgADCgkJIAAAAA==.Ihavenofutur:BAAALgAECgQJBAAAAA==.',
Il='Illari:BAAALgAECgMJBQAAAA==.Illidantwo:BAACLgAFFH8MAAIUAAUJuxZeAQCYAQAUAAUJuxZeAQCYAQAuAAQKfyIAAhQACQmSIxAEADoDABQACQmSIxAEADoDAAAA.Illysanna:BAAALgADCgIJAgAAAA==.',
Im='Imprints:BAAALgAECgYJEAAAAA==.',
In='Inquisistrus:BAAALgADCgMJAwAAAA==.',
Ir='Irönside:BAAALgAECgUJDQAAAA==.',
Is='Isalia:BAAALgADCgQJBAAAAA==.',
It='Italianapee:BAAALgAECgYJDAAAAA==.',
Ja='Jaboo:BAAALgAECgUJBQABLgAECggJHQAVABMcAA==.Jabu:BAAALgADCgkJDQABLgAECggJHQAVABMcAA==.Jacki:BAAALgADCgcJBwAAAA==.Jahz:BAAALgAECgQJCAAAAA==.',
Je='Jenasys:BAAALgADCgkJCQAAAA==.Jenstonedart:BAAALgAECgYJCgAAAA==.Jeryeth:BAABLgAECn8YAAIKAAgJMByNCACXAgAKAAgJMByNCACXAgAAAA==.',
Ji='Jinwoo:BAAALgADCgQJBAAAAA==.',
Jm='Jmage:BAAALgADCgEJAgAAAA==.',
['Já']='Jácor:BAAALgADCgcJBwAAAA==.',
Ka='Kain:BAACLgAFFH8OAAIWAAQJwiEzAACQAQAWAAQJwiEzAACQAQAuAAQKfykAAhYACAk9Jt0AAGgDABYACAk9Jt0AAGgDAAAA.Karenuwu:BAAALgAECgQJBQAAAA==.Kaïn:BAAALgADCgEJAQABLgAECggJIgAMAHcfAA==.',
Ke='Kegtail:BAAALgADCgYJBgAAAA==.Kenslee:BAAALgADCgEJAQAAAA==.',
Kh='Khanzu:BAAALgAECgYJDgAAAA==.Khrouzh:BAAALgADCgIJAgAAAA==.',
Ki='Killnuall:BAAALgAECgMJAwABLgAECgYJBwABAAAAAA==.Kiwí:BAABLgAECn8UAAMJAAcJFhqUCABqAQAJAAUJkxuUCABqAQAEAAQJ9Q/mRACpAAAAAA==.',
Kr='Krasavice:BAABLgAECn8UAAIXAAYJdSRzGQBvAgAXAAYJdSRzGQBvAgAAAA==.',
Ku='Kungpowcow:BAAALgAECgQJCAAAAA==.',
Kv='Kvoth:BAAALgADCgcJCAAAAA==.',
La='Lauranthalas:BAAALgAECgUJDAAAAA==.Lavish:BAACLgAFFH8GAAIVAAQJPQWNFgCLAAAVAAQJPQWNFgCLAAAuAAQKfxsAAhUACQl0F+wqAFQCABUACQl0F+wqAFQCAAAA.',
Le='Leathal:BAAALgAECgYJCwAAAA==.Lena:BAABLgAECn8aAAIXAAYJuSUaBgAOAgAXAAYJuSUaBgAOAgAAAA==.Lewstelamon:BAAALgADCgcJBwAAAA==.Leøn:BAABLgAECn8YAAIYAAgJFx1lJACsAgAYAAgJFx1lJACsAgAAAA==.',
Li='Liightoneup:BAAALgADCgMJAwAAAA==.Lilaxe:BAAALgAECgUJBQAAAA==.',
Lo='Lokust:BAAALgAECgYJEAAAAA==.Londonfog:BAAALgADCgMJAwAAAA==.Lorax:BAAALgAECgMJBQABLgAECgYJCgABAAAAAA==.',
Lu='Lungoblin:BAAALgADCgYJCgAAAA==.Luriøn:BAAALgAECgUJCwAAAA==.Lusat:BAAALgAECgEJAQAAAA==.',
Lw='Lwx:BAAALgADCgkJCQAAAA==.',
Ly='Lycanius:BAABLgAECn8qAAIGAAgJSB0/AQAVAgAGAAgJSB0/AQAVAgAAAA==.',
['Lü']='Lüna:BAAALgAECgYJEAAAAA==.',
Ma='Macewindu:BAAALgAECgEJAQAAAA==.Magicwalrus:BAAALgAECgMJAwABLgAFFAQJBwAHAPEdAA==.Malëk:BAABLgAECn8iAAIMAAgJdx+6IACoAgAMAAgJdx+6IACoAgAAAA==.Marsmighty:BAAALgAECgQJCQAAAA==.Matchalatte:BAAALgAECgIJAgAAAA==.Mattato:BAAALgAECgQJBgAAAA==.Maximus:BAAALgAECgYJDAAAAA==.',
Me='Mellowlizard:BAABLgAFFH8HAAIHAAQJ8R2HCACfAQAHAAQJ8R2HCACfAQAAAA==.Metamarie:BAAALgADCgEJAQAAAA==.Metuss:BAAALgAECgUJBgAAAA==.',
Mi='Mira:BAAALgAECgYJEwAAAA==.Mistutodeath:BAAALgADCgQJBAAAAA==.Mitçh:BAAALgAECgMJAwAAAA==.',
Mk='Mk:BAEALgAECgUJBgABLgAECggJJAAPAAIjAA==.Mkicon:BAAALgAECgYJDwAAAA==.Mkultra:BAAALgAECgYJEgAAAA==.',
Mo='Moonangel:BAAALgAECgUJDQAAAA==.Moozrael:BAAALgADCgQJBwAAAA==.Morbodan:BAAALgAECgYJDwAAAA==.Motone:BAABLgAECn8bAAMOAAgJ8gdIWwBAAQAOAAgJ8gdIWwBAAQACAAIJDwJTegA9AAAAAA==.Motrapz:BAAALgADCgQJBAAAAA==.Mozz:BAABLgAECn8aAAMHAAgJrxSDVADKAQAHAAcJzRWDVADKAQAZAAIJ/w2rVABwAAAAAA==.',
Mu='Mudget:BAACLgAFFH8aAAMZAAcJOhyPAAA9AgAZAAYJDBiPAAA9AgAHAAYJKhsvBADcAQAuAAQKfzQAAwcACQkuJoMNAA4DAAcABwkTJoMNAA4DABkABQl1JpUIADgCAAAA.Muffins:BAAALgADCgcJBwABLgAECggJHQAFALQUAA==.Multanni:BAAALgAECgYJEgAAAA==.',
My='Myonecrosis:BAAALgAECgUJDQAAAA==.',
Na='Nakrog:BAAALgADCgIJAgAAAA==.Napster:BAAALgAECgYJEgAAAA==.Nasa:BAACLgAFFH8MAAIPAAUJWxPJAgAPAQAPAAUJWxPJAgAPAQAuAAQKfxsAAg8ACQkKH+4LALwCAA8ACQkKH+4LALwCAAAA.Nazarov:BAAALgADCgMJAwAAAA==.',
Ne='Nellarixi:BAABLgAECn8aAAIaAAgJYBQSGgAPAgAaAAgJYBQSGgAPAgAAAA==.Nethus:BAAALgAECgEJAQAAAA==.',
Ni='Niivalyr:BAAALgADCgYJBgAAAA==.Nimbus:BAACLgAFFH8QAAMTAAYJDBXrBQCgAQATAAYJDBXrBQCgAQAbAAIJpgnpBgCgAAAuAAQKfz4AAxsACAn5IL0DAN4CABsACAklIL0DAN4CABMACAllHkgKANICAAAA.',
No='Nomaa:BAAALgAECgUJDAAAAA==.Nomäd:BAAALgAECgUJCgAAAA==.Nosneb:BAAALgAECgEJAgAAAA==.',
Nr='Nramar:BAAALgADCgYJBwAAAA==.',
Nu='Nurgle:BAAALgADCgYJDAAAAA==.',
Ny='Nyteshadow:BAAALgADCgYJCQAAAA==.Nyteshock:BAAALgAECgYJCwAAAA==.',
['Nì']='Nìtsua:BAAALgADCgcJCQAAAA==.',
Oc='Ocnabar:BAAALgADCgQJBAAAAA==.',
Og='Ogmount:BAAALgAECgQJCwAAAA==.',
Ok='Oktoberfest:BAAALgAECgQJAwABLgAECgYJBgABAAAAAA==.',
Oo='Ookitsu:BAAALgADCgIJAgAAAA==.',
Pe='Perky:BAAALgAECgYJCwAAAA==.',
Ph='Phrash:BAAALgAECgIJBAABLgAECgYJFQAQAIQjAA==.',
Pi='Pinkpwny:BAAALgAECgMJBAAAAA==.',
Po='Pocahontas:BAAALgAECgYJEwAAAA==.Poky:BAAALgADCgUJBgABLgAECgcJFgAEAAkfAA==.Poocatpokop:BAAALgADCgMJAwAAAA==.Pooldan:BAAALgAECgEJAQAAAA==.Portals:BAAALgAECgEJAQAAAA==.',
Pr='Praystatioñ:BAAALgAECgUJBgAAAA==.Premiumgank:BAAALgADCgEJAQAAAA==.',
Ra='Raa:BAABLgAECn8eAAIXAAcJPCNVEQCuAgAXAAcJPCNVEQCuAgAAAA==.Racker:BAAALgAECgUJBQAAAA==.Raptors:BAAALgADCgEJAQAAAA==.Rawbert:BAAALgAECgMJBAAAAA==.',
Re='Rellein:BAAALgAECgYJCgAAAA==.Rengar:BAABLgAECn8UAAMIAAUJ7xm7SgB6AQAIAAUJ7xm7SgB6AQAKAAQJUxA3MADCAAAAAA==.Rengots:BAAALgAECgUJCQAAAA==.Renne:BAABLgAECn8cAAIUAAcJgBV2HgDLAQAUAAcJgBV2HgDLAQAAAA==.Reph:BAAALgAECgEJAQAAAA==.',
Rh='Rheana:BAAALgAECgUJCwAAAA==.',
Ro='Rocktober:BAAALgADCgYJBgAAAA==.Rogmash:BAAALgAECgIJAgAAAA==.Rokkoz:BAAALgAECgYJEwAAAA==.Rookiestar:BAAALgAECgEJAQAAAA==.Rowaen:BAAALgADCgIJAgAAAA==.',
Ru='Rumí:BAAALgAECgYJDQAAAA==.',
['Rí']='Ríta:BAAALgAECgYJCwAAAA==.',
Sa='Samosan:BAAALgAECgUJDAAAAA==.Sarnt:BAAALgADCgMJAwAAAA==.Sass:BAABLgAECn8YAAICAAgJFxuVFABtAgACAAgJFxuVFABtAgAAAA==.',
Sc='Schattën:BAAALgAECgUJCgAAAA==.',
Se='Senseideath:BAAALgAECgMJAwABLgADCgYJBgABAAAAAA==.Serrana:BAAALgAECgQJDAAAAA==.',
Sf='Sfinktor:BAAALgADCgEJAQAAAA==.',
Sh='Shakz:BAAALgAECgYJBwAAAA==.Sharlug:BAAALgADCgcJEQAAAA==.Shirokhan:BAAALgAECgkJEwAAAA==.Shïfthappens:BAAALgADCgIJAgAAAA==.',
Si='Sidewinderx:BAAALgADCgUJBQAAAA==.Siewarwolf:BAAALgAECgQJBgAAAA==.Silentant:BAAALgAECgMJBgAAAA==.Sinlock:BAABLgAECn8fAAMHAAgJSSA2NwAvAgAHAAYJ1iA2NwAvAgAZAAIJ+xwSRwCaAAAAAA==.',
Sn='Snagglespark:BAABLgAECn8YAAILAAgJahoiFgBpAgALAAgJahoiFgBpAgAAAA==.Snowbunni:BAAALgADCgcJCQAAAA==.Snowster:BAAALgADCgEJAgAAAA==.',
So='Soladrian:BAAALgAECgcJEwAAAA==.Somehunguy:BAAALgAECgEJAgABLgAECgMJAwABAAAAAA==.Soulreeper:BAAALgAECgYJBgAAAA==.Soulsuck:BAAALgAECgYJCgAAAA==.',
Sp='Spankyee:BAAALgADCgUJCQABLgADCgUJCQABAAAAAA==.',
St='Starlisia:BAAALgAECgQJBgAAAA==.Starz:BAAALgAECgEJAQAAAA==.Stelmaria:BAAALgAECgMJAwABLgAECggJFwAXABcZAA==.',
Su='Suhdrake:BAAALgAECgYJEAAAAA==.Sunwing:BAAALgAECgEJAQAAAA==.',
['Sé']='Séraph:BAAALgAECgIJAgAAAA==.',
['Sÿ']='Sÿdney:BAAALgAECgUJDQAAAA==.',
Ta='Tanara:BAAALgAECgQJBQAAAA==.Tankarmor:BAAALgAECgYJEAAAAA==.Taric:BAAALgADCgYJBgABLgAECgcJFAAHAAEZAA==.',
Tc='Tcharta:BAAALgAECgYJCwAAAA==.',
Te='Teddyj:BAAALgAECgEJAQAAAA==.Tehkillerofu:BAAALgADCgEJAQAAAA==.Teos:BAAALgAECgQJBgAAAA==.',
Th='Thiccpickles:BAAALgAECgIJAgABLgAECggJGwAFAJEaAA==.Thoror:BAAALgAECgUJBwAAAA==.Thunderblap:BAAALgADCgEJAQAAAA==.Thunderbolt:BAAALgADCgIJAgABLgADCgYJBgABAAAAAA==.',
Ti='Tiamat:BAAALgADCgYJBgAAAA==.Tiffina:BAAALgAECgQJBwAAAA==.Tiffy:BAAALgAECgIJAgAAAA==.',
To='Tomvokhin:BAAALgADCgIJAgAAAA==.',
Tr='Treeberk:BAAALgADCgkJCQABLgAECgQJBAABAAAAAA==.Trissara:BAAALgADCgIJAgAAAA==.Trolli:BAABLgAECn8XAAIMAAcJpR7tKwB0AgAMAAcJpR7tKwB0AgAAAA==.',
Tu='Tuckerherout:BAAALgADCgEJAQAAAA==.Tulia:BAAALgAECgUJBwAAAA==.',
Tw='Twixx:BAAALgAECgIJAgAAAA==.',
Ty='Tyinar:BAAALgAECgEJAgAAAA==.',
Tz='Tzekelkan:BAAALgAECgQJBAAAAA==.',
['Tî']='Tînytotems:BAAALgADCgUJBQAAAA==.Tîtån:BAAALgAECgYJCgAAAA==.',
Ud='Udeloof:BAAALgADCgYJDAAAAA==.',
Uh='Uh:BAAALgAECgIJBAABLgAECgYJFQAQAIQjAA==.',
Un='Unbound:BAAALgAECgYJDQAAAA==.Unbullevable:BAAALgAECgIJAgABLgAECgQJBQABAAAAAA==.',
Ur='Urdurteno:BAAALgAECgEJAQAAAA==.',
Va='Vae:BAACLgAFFH8FAAIYAAIJlyAjOgCoAAAYAAIJlyAjOgCoAAAuAAQKfxYAAxgABgkdJt89AEACABgABgkdJt89AEACABwAAQnNITg8AGQAAAAA.Valkussy:BAAALgADCgYJBgAAAA==.Vathen:BAABLgAECn8UAAIHAAcJARmROQAlAgAHAAcJARmROQAlAgAAAA==.',
Ve='Velmalthea:BAAALgAECgUJDQAAAA==.Venk:BAAALgADCgYJBgAAAA==.',
Vg='Vgmking:BAABLgAECn8WAAIcAAYJghljFgCuAQAcAAYJghljFgCuAQAAAA==.',
Vi='Vindorei:BAAALgAECgMJAwAAAA==.Vinventure:BAAALgAECgQJDQAAAA==.Vivix:BAAALgADCgQJBAABLgAECggJFwAMAPQSAA==.',
Vo='Voidfed:BAAALgAECgEJAQABLgAECgQJBwABAAAAAA==.Vokzhen:BAAALgAECgUJDQAAAA==.Volescu:BAAALgAECgEJAQAAAA==.',
Wa='Walkerboah:BAAALgAECgYJEwAAAA==.Warhoff:BAAALgADCgUJBwAAAA==.Wasp:BAAALgADCgcJCAAAAA==.Watergun:BAAALgAECgYJDAAAAA==.',
Wo='Wolf:BAAALgAECgYJBwAAAA==.',
Wy='Wyland:BAAALgAECgYJEAAAAA==.',
Xa='Xarìca:BAAALgAECgcJCwABLgAFFAUJDQAPALAlAA==.',
Xe='Xeri:BAAALgADCgcJBwABLgAFFAUJDQAPALAlAA==.Xeromus:BAAALgAECgUJDQAAAA==.Xetsus:BAAALgAECgUJBQAAAA==.',
Xo='Xoden:BAAALgAECgIJAgAAAA==.',
Ya='Yarok:BAAALgADCgMJBAAAAA==.',
Yu='Yuuna:BAAALgAECgIJAwAAAA==.',
Za='Zabawaba:BAAALgAECgYJDQAAAA==.Zaboomaprune:BAAALgAECgYJAwAAAA==.Zantrax:BAAALgADCgIJAgAAAA==.Zarika:BAAALgAECgMJAwABLgAFFAUJDQAPALAlAA==.Zarì:BAACLgAFFH8NAAIPAAUJsCWTAAASAgAPAAUJsCWTAAASAgAuAAQKfxwAAg8ACQm8JQwDAGUDAA8ACQm8JQwDAGUDAAAA.Zaö:BAAALgADCgEJAQABLgAECggJGQAPAN4bAA==.',
Ze='Zeblaw:BAABLgAECn8WAAIEAAYJ0haAqACJAQAEAAYJ0haAqACJAQAAAA==.Zenazure:BAAALgAECgUJCgAAAA==.Zenio:BAAALgADCggJCAAAAA==.Zennah:BAAALgADCgQJBgAAAA==.Zensetra:BAAALgADCgYJBgAAAA==.',
Zu='Zuraat:BAAALgAECgQJBAAAAA==.',
Zw='Zwebop:BAAALgADCgEJAgAAAA==.',
['Zà']='Zàomega:BAABLgAECn8ZAAMPAAgJ3htiEwBWAgAPAAgJ3htiEwBWAgANAAEJuA/lbAAqAAAAAA==.',
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

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

local lookup = {'Hunter-BeastMastery','Unknown-Unknown','Priest-Holy','Shaman-Restoration','Warrior-Arms','Warrior-Fury','Priest-Shadow','Warrior-Protection','DemonHunter-Devourer','Druid-Restoration','Mage-Frost','Warlock-Destruction','Evoker-Augmentation','Evoker-Devastation','Monk-Mistweaver','Hunter-Marksmanship','DeathKnight-Frost','Paladin-Holy','Paladin-Protection','DeathKnight-Unholy','Evoker-Preservation','Warlock-Demonology',}
local provider = {region='US',realm='Dragonblight',name='US',type='weekly',zone=46,date='2026-04-24',data={Aa='Aauron:BAAALgADCgUJCAAAAA==.Aazula:BAAALgAECgUJBgAAAA==.',
Ac='Acelionheart:BAAALgADCgQJCAAAAA==.Acheron:BAAALgADCgcJCQAAAA==.',
Aj='Ajrpg:BAAALgADCgEJAQAAAA==.',
Ak='Akirys:BAAALgAECgYJCgAAAA==.Akusenshi:BAAALgAECgQJBAAAAA==.',
Al='Albertwesker:BAAALgAECgEJAQAAAA==.Alethrix:BAAALgAECgMJBAAAAA==.Alexi:BAAALgADCgYJBAAAAA==.Alivis:BAEALgADCgYJCwABLgAECgcJFQABAN8fAA==.Alzith:BAAALgAECgQJBQAAAA==.',
Am='Amoone:BAAALgADCgUJCQAAAA==.',
An='Anarch:BAAALgADCgEJAQABLgADCgMJBgACAAAAAA==.Androcksus:BAAALgADCgMJBwAAAA==.Angelic:BAAALgAECgEJAQABLgAFFAcJGwADAPkiAA==.',
Ap='Apexalpha:BAAALgAECgIJAwAAAA==.',
Ar='Areto:BAAALgADCgYJBgAAAA==.Armster:BAAALgADCgcJDAAAAA==.Arold:BAAALgAECgYJDgAAAA==.',
As='Asylia:BAACLgAFFH8KAAIEAAQJNRF+CQA5AQAEAAQJNRF+CQA5AQAuAAQKfxcAAgQACAlLGzQhABcCAAQACAlLGzQhABcCAAAA.',
At='Atlantus:BAAALgAECgMJBAAAAA==.',
Au='Aurelliae:BAAALgAECgQJBwAAAA==.',
Av='Avesiren:BAAALgAECgYJDAAAAA==.',
Ay='Ayidá:BAAALgAECgIJAgAAAA==.',
Az='Azhág:BAAALgADCgUJBAAAAA==.',
Ba='Babalú:BAAALgAECgUJCAAAAA==.Babymamaa:BAAALgADCgYJDAAAAA==.Babymuffins:BAAALgAECgMJBAAAAA==.Balrocc:BAAALgADCgcJCQAAAA==.',
Be='Beecrafty:BAAALgAECgEJAQAAAA==.Belanda:BAAALgADCgkJDwAAAA==.Belin:BAAALgADCgkJFgAAAA==.Belmond:BAAALgAECgQJBwAAAA==.',
Bl='Blackmill:BAAALgAECgMJBAAAAA==.Blayrog:BAAALgAECgcJDAAAAA==.Bloodydemons:BAAALgADCgEJAQAAAA==.Bluerazz:BAAALgADCgMJAwAAAA==.',
Bo='Board:BAABLgAECn8VAAMFAAcJLhJuBQA2AQAGAAYJNhDJUQBiAQAFAAcJYBFuBQA2AQABLgAFFAQJCQAHAJYKAA==.Bolf:BAAALgADCgkJGQAAAA==.Boombaaby:BAAALgAECgQJBQAAAA==.Bootzee:BAAALgAECgUJCAAAAA==.',
Br='Brewsli:BAAALgAECgMJAwAAAA==.Brookenoel:BAAALgAECgQJCQAAAA==.Brunhilian:BAAALgADCggJGQAAAA==.',
Bu='Buckmaster:BAAALgADCgYJBQAAAA==.Bungulator:BAAALgAECgEJAgAAAA==.',
Ca='Cadun:BAAALgAECgMJBAAAAA==.Calada:BAAALgAECgIJAgAAAA==.',
Ch='Cheesdhunter:BAAALgAECgMJBQAAAA==.Chronoo:BAAALgAECgcJEAAAAA==.',
Ci='Citchelas:BAAALgAECgYJCwAAAA==.',
Co='Corrynn:BAAALgAECgYJDgAAAA==.',
Cr='Cribbage:BAABLgAECn8eAAIIAAgJECBGAQBLAgAIAAgJECBGAQBLAgAAAA==.Cryoclover:BAAALgAECgMJAwAAAA==.Crzykanaka:BAAALgADCgQJBAAAAA==.',
Cu='Cursedgurly:BAAALgADCgkJDwAAAA==.Curshuu:BAAALgAECgIJAgAAAA==.',
Cy='Cynosure:BAAALgAECgkJEQAAAA==.Cytronsneak:BAAALgADCgkJDAAAAA==.',
Da='Dabb:BAAALgADCgUJBgAAAA==.Daccard:BAAALgADCgkJGwAAAA==.Dangereuse:BAAALgADCgEJAQAAAA==.Danlor:BAAALgAECgYJEAAAAA==.Darkheaven:BAAALgADCgcJDgAAAA==.Darkkanaka:BAAALgADCgEJAQAAAA==.Darrling:BAAALgAECgQJBAAAAA==.Davethelock:BAAALgAECgIJAgAAAA==.Dazarek:BAAALgAECgUJCwAAAA==.',
De='Deadpoolx:BAAALgAECgMJBAAAAA==.Demium:BAACLgAFFH8FAAIJAAIJDg3fFACZAAAJAAIJDg3fFACZAAAuAAQKfyYAAgkACAkdIscCAIMCAAkACAkdIscCAIMCAAEuAAQKBAkFAAIAAAAA.Demonkanaka:BAAALgADCgEJAQAAAA==.Deowulf:BAAALgADCgkJCQAAAA==.Desiinnorre:BAAALgADCgEJAgAAAA==.Devinetoro:BAAALgAECgQJBQAAAA==.Devour:BAABLgAECn8cAAIKAAgJ8xYnLAD/AQAKAAgJ8xYnLAD/AQAAAA==.Deznormu:BAAALgADCgEJAQAAAA==.',
Di='Diag:BAAALgAECgYJDQAAAA==.',
Do='Dotitndropit:BAAALgAECgQJBAAAAA==.',
Dr='Drakenn:BAAALgAECgYJBwABLgAFFAMJBwABAKYNAA==.Dreadsofdeth:BAABLgAECn8VAAILAAYJixh5ngCZAQALAAYJixh5ngCZAQAAAA==.Drklhtkanaka:BAAALgADCgYJBgAAAA==.Drunkenbilly:BAAALgADCgYJBgAAAA==.',
['Dê']='Dêv:BAAALgAECgYJDwAAAA==.',
Ei='Einheri:BAAALgAECgUJDQAAAA==.',
Ek='Eksos:BAAALgADCgcJBwAAAA==.',
El='Elalian:BAAALgADCgMJBQAAAA==.Elracc:BAAALgADCgkJFAAAAA==.Elure:BAAALgADCgEJAQAAAA==.',
En='Endarius:BAAALgADCgMJAwAAAA==.Endeavour:BAAALgAFFAIJAgAAAA==.Enoira:BAAALgADCgYJCQAAAA==.Enver:BAAALgADCgYJBgAAAA==.',
Ep='Epistle:BAAALgADCgkJGwAAAA==.',
Er='Erfing:BAAALgADCgEJAQAAAA==.',
Ev='Evillizard:BAAALgAECgQJBQAAAA==.',
Ex='Exhumer:BAAALgAECgUJCgAAAA==.',
Fa='Faffard:BAAALgAECgIJAgABLgAECgYJFQAMAMcHAA==.Fame:BAAALgAFFAEJAQABLgAFFAMJCQANALQXAA==.Fara:BAAALgADCgMJAwAAAA==.Farsighted:BAAALgADCgcJCgAAAA==.',
Fe='Fearbilly:BAAALgADCgIJAgAAAA==.Fennerick:BAAALgAECgUJDQAAAA==.Feyndra:BAAALgADCgYJCQAAAA==.',
Fl='Flap:BAACLgAFFH8JAAINAAMJtBdUEAD/AAANAAMJtBdUEAD/AAAuAAQKfxkAAw0ACAlOGGccAOQBAA0ACAlOGGccAOQBAA4AAQkAAJBAAC8AAAAA.Fleureena:BAAALgADCgYJDQAAAA==.',
Fy='Fystie:BAAALgAECgIJAgABLgAECgYJFQAMAMcHAA==.',
Ga='Galpally:BAAALgAECgUJCAAAAA==.Ganzar:BAAALgADCgMJBAABLgAECgYJEgACAAAAAA==.Garin:BAAALgAECgUJBQAAAA==.',
Ge='Gennic:BAAALgADCgcJBwAAAA==.',
Gl='Glorak:BAAALgAECgMJAwAAAA==.',
Gr='Grashen:BAAALgAECgUJCQAAAA==.Gravorik:BAAALgAECgIJAwAAAA==.Grogu:BAAALgAECgMJAwAAAA==.',
Gs='Gsm:BAAALgAECgYJDQAAAA==.',
Ha='Hante:BAAALgADCgQJBAAAAA==.Hartmonster:BAAALgADCggJGAAAAA==.Hawaiianchi:BAAALgADCgQJBAAAAA==.Hawaiianvoid:BAAALgADCgYJBgAAAA==.',
He='Hellmouth:BAAALgADCgQJBAAAAA==.',
Hi='Hiawassee:BAAALgAECgcJEgAAAA==.',
Ho='Holydps:BAAALgAECgcJDgAAAA==.Holyloh:BAAALgADCgIJAgAAAA==.Hoompukka:BAAALgADCgkJDAAAAA==.',
Ii='Iit:BAAALgADCgcJBgAAAA==.',
Il='Ilokana:BAAALgADCgMJBgAAAA==.',
In='Inuyashi:BAAALgADCgMJAwAAAA==.',
Ir='Ironfist:BAAALgAECgQJBAAAAA==.',
Ja='Jacsace:BAAALgADCgQJBAAAAA==.Jacspally:BAAALgAECgUJCwAAAA==.Jailbayt:BAAALgAECgYJCgAAAA==.Janora:BAAALgAECgQJBAAAAA==.Jarlath:BAAALgADCgEJAQAAAA==.',
Je='Jebra:BAAALgAECgYJDAAAAA==.Jellexy:BAAALgAECgIJAgAAAA==.',
Jo='Jolah:BAAALgADCgMJAwAAAA==.Jolahbae:BAABLgAECn8gAAIPAAgJPRsaEABaAgAPAAgJPRsaEABaAgAAAA==.Jonnyfive:BAAALgAECgEJAQAAAA==.',
Ka='Kailis:BAAALgAECgYJDgAAAA==.Kaisa:BAAALgADCgcJBwAAAA==.Kanne:BAAALgADCgMJAwAAAA==.Karst:BAAALgADCgQJBAAAAA==.Kayzon:BAACLgAFFH8VAAMBAAYJwCEIAAAIAgABAAUJwCEIAAAIAgAQAAUJUAepCgBuAQAuAAQKfzMAAwEACQndJbQAAO0CABAACQkYIowCAIgDAAEACQnaJbQAAO0CAAAA.Kayzwei:BAAALgAECgYJEwAAAA==.',
Ke='Kegtap:BAAALgADCgEJAQAAAA==.',
Ki='Kij:BAAALgAECgEJAQAAAA==.Killaks:BAAALgAECgYJBgAAAA==.Killdo:BAAALgAECgEJAQAAAA==.Kirilla:BAAALgADCgEJAQAAAA==.',
Kl='Klavine:BAABLgAECn8jAAIRAAkJERY7AgCnAgARAAkJERY7AgCnAgAAAA==.',
Ko='Korben:BAABLgAECn8cAAISAAgJyRi8CAC5AQASAAgJyRi8CAC5AQAAAA==.Korenna:BAAALgADCgUJCgAAAA==.',
Kr='Kronn:BAAALgADCgkJDwAAAA==.Kruger:BAAALgAECgYJDgAAAA==.Kryptonicboy:BAAALgAECgMJBAAAAA==.',
Kt='Ktanna:BAAALgAECgUJBQAAAA==.',
Ku='Kublakhan:BAAALgAECgQJBQAAAA==.',
Ky='Kyfu:BAAALgADCgMJAwABLgAFFAQJCAATAMoYAA==.Kynleria:BAAALgADCgEJAQAAAA==.',
La='Lakhi:BAABLgAECn8WAAIEAAcJ5R70JAABAgAEAAcJ5R70JAABAgAAAA==.Lateralus:BAAALgAECgYJCwAAAA==.Laureli:BAAALgADCgkJHwAAAA==.',
Le='Leeta:BAAALgAECgMJBAAAAA==.Legendx:BAAALgADCgUJBwAAAA==.',
Li='Lightningg:BAAALgAECgQJBAAAAA==.Lightsaved:BAAALgADCgIJAgAAAA==.Lightsworn:BAAALgAECgIJAgAAAA==.Linara:BAAALgADCgIJAgAAAA==.',
Lo='Lockbite:BAAALgADCgEJAQAAAA==.Lollypopp:BAAALgAECgcJAQAAAA==.Lomme:BAAALgADCgcJBwAAAA==.Loraemar:BAAALgADCgkJDwAAAA==.Losoz:BAAALgADCgYJCQAAAA==.',
Lu='Lusilsandrus:BAAALgADCgQJBwAAAA==.Luxanna:BAAALgAECgIJAQAAAA==.',
Ma='Maegwin:BAAALgADCgQJBAAAAA==.Matti:BAAALgAECgMJBAAAAA==.',
Me='Meddler:BAAALgADCgEJAQAAAA==.',
Mi='Mildrik:BAAALgADCgcJDgAAAA==.Miracledh:BAAALgAECgUJDgAAAA==.Mirkdrak:BAAALgAECgMJAwAAAA==.Misheard:BAABLgAECn8lAAIJAAgJLh4wBgAYAgAJAAgJLh4wBgAYAgAAAA==.Misjudged:BAAALgAECgQJBgAAAA==.Missus:BAAALgADCgYJCAAAAA==.Mit:BAAALgADCgkJGAAAAA==.Miyu:BAAALgADCgcJBwAAAA==.Mizzen:BAAALgAECgYJEAABLgAFFAQJCQAHAJYKAA==.',
Mo='Mohtavius:BAAALgAECgYJCgAAAA==.Mohz:BAAALgADCgcJCwAAAA==.Mommydearest:BAABLgAECn8VAAIMAAYJxwd0BwC8AAAMAAYJxwd0BwC8AAAAAA==.Moonkissed:BAAALgAECgEJAQAAAA==.Morttimuss:BAAALgAECgQJBQAAAA==.Motz:BAAALgADCgUJBgAAAA==.',
Mu='Munkìe:BAAALgADCgYJDAABLgAECgYJDQACAAAAAA==.Muura:BAABLgAECn8UAAIUAAcJbQiVtQAXAQAUAAcJbQiVtQAXAQAAAA==.',
My='Myextralife:BAAALgADCgYJBgAAAA==.Myrik:BAAALgAECgMJBAAAAA==.',
Na='Naslunda:BAAALgADCgEJAQAAAA==.Nathyrra:BAAALgAECgYJDwAAAA==.',
Ne='Nebekenazar:BAAALgADCgkJDwAAAA==.Negate:BAAALgAECgYJEQABLgAFFAUJEAAVALQdAA==.',
Ni='Nitrö:BAAALgADCgcJDQABLgAECgQJBAACAAAAAA==.',
No='Noreset:BAAALgADCgYJBgAAAA==.Noriea:BAAALgADCgEJAQAAAA==.',
Nu='Nufonhudis:BAAALgAECgQJCAAAAA==.',
Om='Omnidacc:BAAALgAECgIJAgAAAA==.',
On='Onigirius:BAAALgAECgYJBgAAAA==.',
Ot='Otwin:BAAALgAECgQJBAAAAA==.',
Pa='Pahuum:BAAALgADCgkJDwAAAA==.Paimon:BAAALgAECgUJCAABLgAFFAMJCQANALQXAA==.Paintrainn:BAAALgAECgYJDAAAAA==.Palewhiteman:BAAALgAECgYJEwAAAA==.Palleigh:BAAALgAECgUJCwAAAA==.Pallyd:BAAALgADCgEJAQAAAA==.Patchës:BAAALgAECgQJBAAAAA==.',
Pe='Pepperjack:BAAALgAECgMJBAAAAA==.Persephonae:BAAALgADCgQJBAAAAA==.Persimmon:BAAALgAECgQJBAAAAA==.',
Pi='Pikklerikk:BAAALgAECgYJDAAAAA==.',
Po='Poondor:BAAALgAECgYJCgAAAA==.',
Pr='Predaturd:BAAALgAECgEJAQAAAA==.',
Pu='Purgatorri:BAAALgADCgMJAwAAAA==.',
Qi='Qindere:BAAALgAECgYJEAAAAA==.',
Ra='Raalaan:BAAALgADCgEJAQAAAA==.Raeinthe:BAABLgAECn8gAAIBAAkJcBGfBgACAgABAAkJcBGfBgACAgAAAA==.Ramantu:BAAALgADCgcJBwAAAA==.Rancor:BAAALgAECgEJAQABLgAECgYJEgACAAAAAA==.',
Re='Reihino:BAAALgADCgcJBwAAAA==.Resbak:BAAALgAECgMJAwAAAA==.Resiaus:BAABLgAECn8hAAIVAAgJehGkAgDjAQAVAAgJehGkAgDjAQAAAA==.',
Ri='Ripptyde:BAAALgADCgQJBAAAAA==.Rivalina:BAAALgADCgMJAwAAAA==.',
Ro='Robilargreen:BAAALgADCgUJBQAAAA==.Rocketabu:BAAALgADCgMJBQAAAA==.Roctheist:BAAALgAECgYJBgAAAA==.Rocthoeb:BAABLgAECn8oAAIIAAkJxhH7EQDoAQAIAAkJxhH7EQDoAQAAAA==.Rojito:BAAALgADCgkJGAAAAA==.',
Ry='Ry:BAAALgAECgcJEgAAAA==.',
Sa='Saintkhal:BAEALgAECgIJAgABLgAECgUJCQACAAAAAA==.Saintmedicus:BAEALgAECgUJCQAAAA==.Saintshunter:BAAALgAECgEJAQAAAA==.Sanctor:BAABLgAECn8dAAISAAcJeyJ2EgB/AgASAAcJeyJ2EgB/AgAAAA==.Sandusky:BAAALgADCgQJBAAAAA==.Saraya:BAAALgAECgUJCQAAAA==.',
Se='Sephafael:BAAALgADCgcJDQAAAA==.Setsena:BAAALgAECgQJBAAAAA==.',
Sh='Shamwow:BAAALgAECgQJBAAAAA==.Shangi:BAAALgADCgMJAwAAAA==.Shinstabber:BAAALgAECgQJBAAAAA==.Shlarya:BAAALgADCgYJBgABLgAECggJDwACAAAAAA==.Shruggie:BAAALgAECgUJBwAAAA==.',
Si='Silven:BAAALgADCgMJAwAAAA==.Singingsword:BAAALgAECgEJAQAAAA==.Siphond:BAAALgADCgIJAgAAAA==.Siphondark:BAAALgAECgQJBAAAAA==.Sisqi:BAAALgADCgQJBAAAAA==.',
Sl='Slapnutz:BAABLgAECn8bAAIBAAcJ3xVzLwD0AQABAAcJ3xVzLwD0AQAAAA==.',
Sm='Smoki:BAAALgAECgUJBQAAAA==.',
So='Solvaii:BAAALgAECgYJDAAAAA==.',
St='Starfail:BAAALgAECgYJDgABLgAFFAQJCgAEADURAA==.Starlie:BAAALgAECgUJBQAAAA==.Stratacaster:BAAALgAECgMJAwAAAA==.Strawberry:BAAALgAECgQJBAAAAA==.Stuckinwell:BAABLgAECn8bAAMWAAkJ+hq7MwA9AgAWAAgJ6Ra7MwA9AgAMAAUJDRxCGACIAQAAAA==.',
Su='Sunbound:BAABLgAFFH8FAAIKAAIJ4xp+FQC3AAAKAAIJ4xp+FQC3AAABLgAFFAUJEAAVALQdAA==.',
Sx='Sxths:BAAALgAECgEJAQAAAA==.',
Sy='Syela:BAAALgAECgQJBAAAAA==.Synsyn:BAAALgAECgQJBwAAAA==.',
Ta='Tach:BAAALgADCgYJBgAAAA==.Tanel:BAAALgAECgYJCAAAAA==.Targonne:BAAALgADCgEJAQAAAA==.Taterhots:BAAALgADCgcJBwAAAA==.Tatsü:BAAALgAECgIJAQAAAA==.Taílorswift:BAAALgAECggJEgAAAA==.',
Te='Teanfists:BAAALgAECgEJAgAAAA==.Temna:BAAALgAECgYJDQAAAA==.Tenari:BAAALgAECgcJDAAAAA==.',
Th='Theel:BAAALgAECgIJAgAAAA==.Thespaniard:BAABLgAECn8UAAIHAAcJphWgHwDbAQAHAAcJphWgHwDbAQAAAA==.Thlunk:BAAALgADCgkJCQAAAA==.',
Ti='Tidebreaker:BAAALgAECgQJCQAAAA==.Tinbasher:BAAALgAECgQJBAAAAA==.',
Tj='Tjay:BAAALgADCgEJAQAAAA==.',
To='Totemistic:BAAALgADCgcJCQAAAA==.',
Tr='Treebilly:BAAALgADCgcJDAAAAA==.Triviousox:BAAALgAECgUJBQAAAA==.',
Tu='Tungo:BAAALgADCgEJAQAAAA==.',
Tw='Twilightjade:BAAALgADCggJDwABLgAECgYJBwACAAAAAA==.Twotvmage:BAABLgAECn8YAAILAAYJfxfjHABmAQALAAYJfxfjHABmAQAAAA==.',
Ty='Tystin:BAAALgAECgEJAQAAAA==.',
Un='Unglued:BAAALgADCgcJBwAAAA==.Unholygrimg:BAAALgADCgUJBQAAAA==.Unholywar:BAAALgAECgEJAQABLgAECgcJGAAWALAZAA==.',
Ur='Ursolana:BAAALgADCgUJBQAAAA==.',
Va='Valkky:BAAALgAECgYJCwAAAA==.Valleya:BAAALgAECgIJAgAAAA==.Vallysong:BAAALgAECgQJBAAAAA==.Valnetrois:BAAALgADCgEJAQAAAA==.Vaswislor:BAAALgADCgIJAwAAAA==.',
Ve='Velayna:BAAALgAECgUJCQAAAA==.Velenn:BAAALgADCgUJBQAAAA==.Venatar:BAAALgAECgYJDQAAAA==.Vessna:BAAALgADCgkJIAABLgAECgMJAwACAAAAAA==.',
Vi='Vicarious:BAAALgAECgYJEwAAAA==.Visea:BAAALgADCgEJAQAAAA==.Vivîán:BAAALgAECgIJAgAAAA==.',
Vm='Vmro:BAAALgADCgYJEQAAAA==.',
Vo='Voras:BAAALgAECgQJCgAAAA==.Vorttex:BAAALgAECgEJAQAAAA==.',
Wa='Waitandbleed:BAAALgADCgcJBwAAAA==.Wanglock:BAAALgAECgYJDAABLgAFFAcJFgANALEXAA==.Wardstar:BAAALgADCgIJAgAAAA==.Wasure:BAAALgAECgMJBAAAAA==.',
Wh='Whiskeyrick:BAAALgADCgMJAwAAAA==.',
Wi='Wildkanaka:BAAALgADCgEJAQAAAA==.Winters:BAAALgADCggJCAAAAA==.',
Wo='Worthy:BAAALgADCgYJBgAAAA==.',
Xa='Xalatath:BAABLgAECn8YAAIHAAgJ4RsFEQB4AgAHAAgJ4RsFEQB4AgAAAA==.',
Xt='Xtra:BAAALgADCgEJAQAAAA==.',
Xy='Xylar:BAAALgAECgYJDAAAAA==.',
Ya='Yahiko:BAAALgAECgMJAwAAAA==.',
Yu='Yuzuriha:BAAALgAECgQJBwAAAA==.',
Za='Zarazard:BAAALgADCggJCwAAAA==.',
Ze='Zeynah:BAAALgADCgYJBgAAAA==.',
Zo='Zophier:BAAALgADCgMJAwAAAA==.',
Zu='Zube:BAAALgAECgUJBgAAAA==.',
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

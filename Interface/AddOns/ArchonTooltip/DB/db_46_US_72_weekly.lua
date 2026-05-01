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

local lookup = {'Hunter-BeastMastery','Unknown-Unknown','Priest-Holy','Shaman-Restoration','Mage-Frost','Warrior-Arms','Warrior-Fury','Warrior-Protection','Rogue-Subtlety','DemonHunter-Devourer','Druid-Restoration','Warlock-Demonology','Warlock-Destruction','Evoker-Augmentation','Evoker-Devastation','DeathKnight-Unholy','Hunter-Marksmanship','Monk-Mistweaver','DeathKnight-Frost','Paladin-Holy','Paladin-Protection','DemonHunter-Havoc','Monk-Windwalker','Evoker-Preservation','Druid-Feral','DeathKnight-Blood','Priest-Shadow',}
local provider = {region='US',realm='Dragonblight',name='US',type='weekly',zone=46,date='2026-05-01',data={Aa='Aauron:BAAALgADCgkJDAAAAA==.Aazula:BAAALgAECgUJBgAAAA==.',
Ac='Acelionheart:BAAALgADCgQJCAAAAA==.Acheron:BAAALgADCgcJCQAAAA==.',
Ai='Aix:BAAALgADCgcJBwAAAA==.',
Aj='Ajrpg:BAAALgADCgQJBAAAAA==.',
Ak='Akirys:BAAALgAECgcJDQAAAA==.Akusenshi:BAAALgAECgYJCgAAAA==.',
Al='Albertwesker:BAAALgAECgEJAQAAAA==.Alethrix:BAAALgAECgQJBwAAAA==.Alexi:BAAALgADCgYJBAAAAA==.Alivis:BAEALgADCgYJEQABLgAECgcJFwABAN8fAA==.Alzith:BAAALgAECgQJBQAAAA==.',
Am='Amoone:BAAALgADCgUJCQAAAA==.',
An='Anarch:BAAALgADCgEJAQABLgADCgMJBgACAAAAAA==.Androcksus:BAAALgADCgMJBwAAAA==.Angelic:BAAALgAECgEJAQABLgAFFAgJIgADAK8jAA==.',
Ap='Apexalpha:BAAALgAECgIJAwAAAA==.',
Ar='Areto:BAAALgADCgYJBgAAAA==.Armster:BAAALgADCgcJDAAAAA==.Arold:BAAALgAECgcJEwAAAA==.',
As='Asylia:BAACLgAFFH8KAAIEAAQJNRGACQA5AQAEAAQJNRGACQA5AQAuAAQKfxcAAgQACAlLGy0hABcCAAQACAlLGy0hABcCAAAA.',
At='Atlantus:BAAALgAECgQJCAAAAA==.',
Au='Aurelliae:BAAALgAECggJDgAAAA==.',
Av='Avesiren:BAAALgAECgYJEgAAAA==.',
Ay='Ayidá:BAAALgAECgQJBgAAAA==.',
Az='Azhág:BAAALgADCgUJBAAAAA==.',
Ba='Babalú:BAAALgAECgYJCQAAAA==.Babymamaa:BAAALgAECgEJAQAAAA==.Babymuffins:BAAALgAECgQJCAAAAA==.Balrocc:BAAALgADCgcJCQAAAA==.',
Be='Beecrafty:BAAALgAECgEJAQAAAA==.Belanda:BAAALgAECgEJAQAAAA==.Belgord:BAAALgAECgEJAQAAAA==.Belin:BAAALgADCgkJFgAAAA==.Belmond:BAAALgAECgQJBwAAAA==.',
Bl='Blackmill:BAAALgAECgQJCAAAAA==.Blayrog:BAABLgAECn8UAAIFAAcJsg4EUQA/AQAFAAcJsg4EUQA/AQAAAA==.Bloodydemons:BAAALgADCgEJAQAAAA==.Bluerazz:BAAALgADCgMJAwAAAA==.',
Bo='Board:BAABLgAECn8bAAMGAAcJJhasCwBHAQAHAAYJ/RDMUQBiAQAGAAcJshSsCwBHAQAAAA==.Bolf:BAAALgAECgQJBAAAAA==.Boombaaby:BAAALgAECgUJCwAAAA==.Bootzee:BAAALgAECgYJDgAAAA==.',
Br='Brewsli:BAAALgAECgMJAwAAAA==.Brookenoel:BAAALgAECgYJDwAAAA==.Brunhilian:BAAALgADCggJHQAAAA==.',
Bu='Buckmaster:BAAALgADCggJCwAAAA==.Bungulator:BAAALgAECgEJAgAAAA==.',
Ca='Cadun:BAAALgAECgQJCAAAAA==.Calada:BAAALgAECgQJBgAAAA==.',
Ch='Charot:BAAALgAECgEJAQABLgAECgcJCwACAAAAAA==.Cheesdhunter:BAAALgAECgMJBQAAAA==.Chronoo:BAABLgAECn8WAAIEAAcJ3RMrFwCtAQAEAAcJ3RMrFwCtAQAAAA==.',
Ci='Citchelas:BAAALgAECgYJCwAAAA==.',
Co='Corrynn:BAAALgAECgYJDgAAAA==.',
Cr='Cribbage:BAABLgAECn8mAAIIAAgJYCKsAQCyAgAIAAgJYCKsAQCyAgAAAA==.Cryoclover:BAAALgAECgMJAwAAAA==.Crzykanaka:BAAALgADCgUJBwAAAA==.',
Cu='Cursedgurly:BAAALgAECgEJAQAAAA==.Curshuu:BAAALgAECgQJBgAAAA==.',
Cy='Cynosure:BAABLgAECn8aAAIJAAkJghSaBABDAgAJAAkJghSaBABDAgAAAA==.Cytronsneak:BAAALgADCgkJDAAAAA==.',
Da='Dabb:BAAALgADCgcJCAAAAA==.Daccard:BAAALgADCgkJGwAAAA==.Daccfu:BAAALgAECgQJBAAAAA==.Dangereuse:BAAALgADCgEJAQAAAA==.Danlor:BAAALgAECgYJEAAAAA==.Darkheaven:BAAALgAECgYJBgAAAA==.Darkkanaka:BAAALgADCgEJAQAAAA==.Darrling:BAAALgAECgUJCQAAAA==.Davethelock:BAAALgAECgIJAgAAAA==.Dazarek:BAAALgAECgYJDAAAAA==.',
De='Deadpoolx:BAAALgAECgMJBAAAAA==.Demium:BAACLgAFFH8GAAIKAAMJHRQZHgDxAAAKAAMJHRQZHgDxAAAuAAQKfyEAAgoACAlOIrYZALoCAAoACAlOIrYZALoCAAEuAAQKBQkJAAIAAAAA.Demonkanaka:BAAALgADCgEJAQAAAA==.Deowulf:BAAALgADCgkJCQAAAA==.Desiinnorre:BAAALgADCggJCgAAAA==.Devinetoro:BAAALgAECgYJCwAAAA==.Devour:BAABLgAECn8gAAILAAgJshcoLAD/AQALAAgJshcoLAD/AQAAAA==.Deznormu:BAAALgADCgEJAQAAAA==.',
Di='Diag:BAAALgAECgYJEwAAAA==.',
Do='Dotitndropit:BAAALgAECgQJBAAAAA==.',
Dr='Drakenn:BAAALgAECgYJCQABLgAFFAMJCgABAAoOAA==.Dreadsofdeth:BAABLgAECn8VAAIFAAYJixhungCZAQAFAAYJixhungCZAQAAAA==.Drklhtkanaka:BAAALgADCgYJBgAAAA==.Drunkenbilly:BAAALgAECgEJAQAAAA==.',
['Dê']='Dêv:BAABLgAECn8XAAIMAAgJ4wl9LwBuAQAMAAgJ4wl9LwBuAQAAAA==.',
Ei='Einheri:BAABLgAECn8VAAIHAAYJVxgaGABvAQAHAAYJVxgaGABvAQAAAA==.',
Ek='Eksos:BAAALgADCgcJBwAAAA==.',
El='Elalian:BAAALgADCgYJCwAAAA==.Elracc:BAAALgADCgkJFAAAAA==.Elure:BAAALgADCgEJAQAAAA==.',
En='Endarius:BAAALgADCgMJAwAAAA==.Endeavour:BAACLgAFFH8FAAIJAAIJnwQWFwCZAAAJAAIJnwQWFwCZAAAuAAQKfx0AAgkACQm1DfoKALoBAAkACQm1DfoKALoBAAAA.Enoira:BAAALgAECgEJAQAAAA==.Enver:BAAALgADCgYJBgAAAA==.',
Ep='Epistle:BAAALgADCgkJGwAAAA==.',
Er='Erfing:BAAALgADCgcJCAAAAA==.',
Ev='Evillizard:BAAALgAECgQJCQAAAA==.',
Ex='Exhumer:BAAALgAECgUJDQAAAA==.',
Fa='Faffard:BAAALgAECgQJBgABLgAECggJHQANADsHAA==.Fame:BAAALgAFFAEJAQABLgAFFAQJDQAOAHIXAA==.Fara:BAAALgADCgMJAwAAAA==.Farsighted:BAAALgAECgEJAQAAAA==.',
Fe='Fearbilly:BAAALgAECgQJBAAAAA==.Fennerick:BAAALgAECgUJDQAAAA==.Feyndra:BAAALgADCgYJCQAAAA==.',
Fi='Fizzlenips:BAAALgADCgcJBwAAAA==.',
Fl='Flap:BAACLgAFFH8NAAIOAAQJchfDDQBBAQAOAAQJchfDDQBBAQAuAAQKfxkAAw4ACAlOGG8cAOQBAA4ACAlOGG8cAOQBAA8AAQkAAJlAAC8AAAAA.Fleureena:BAAALgADCgYJDQAAAA==.',
Fy='Fystie:BAAALgAECgQJBgABLgAECggJHQANADsHAA==.',
Ga='Galpally:BAAALgAECgYJDgAAAA==.Ganzar:BAAALgADCgMJBAABLgAECggJGAAQAFgbAA==.Garin:BAAALgAECgUJBQAAAA==.',
Ge='Gennic:BAAALgADCgcJBwAAAA==.',
Gi='Gishongar:BAAALgADCgkJCQAAAA==.',
Gl='Glorak:BAAALgAECgYJCQAAAA==.',
Gr='Grashen:BAAALgAECgUJDAAAAA==.Gravorik:BAAALgAECgQJBQAAAA==.Greefkarga:BAAALgADCgkJCQAAAA==.Grogu:BAAALgAECgQJBwAAAA==.',
Gs='Gsm:BAAALgAECgYJEwAAAA==.',
Ha='Hante:BAAALgADCgQJBAAAAA==.Hartmonster:BAAALgAECgQJBAAAAA==.Hawaiianchi:BAAALgADCgQJBAAAAA==.Hawaiianvoid:BAAALgADCgYJBgAAAA==.',
He='Hellmouth:BAAALgADCgQJBAAAAA==.',
Hi='Hiawassee:BAABLgAECn8UAAMBAAcJIwVrSgDxAAABAAYJ1AVrSgDxAAARAAEJrwEzJgAfAAAAAA==.',
Ho='Holydps:BAAALgAECgcJDgAAAA==.Holyloh:BAAALgADCgIJAgAAAA==.Hoompukka:BAAALgAECgEJAQAAAA==.',
Hy='Hypia:BAAALgADCgEJAQAAAA==.',
Ii='Iit:BAAALgADCgcJBgAAAA==.',
Il='Ilokana:BAAALgADCgMJCQAAAA==.',
In='Inuyashi:BAAALgADCgMJAwAAAA==.',
Ir='Ironfist:BAAALgAECgYJCgAAAA==.',
Ja='Jacsace:BAAALgADCgQJBAAAAA==.Jacspally:BAAALgAECgYJDAAAAA==.Jailbayt:BAAALgAECgYJCgAAAA==.Janora:BAAALgAECgYJCgAAAA==.Jarlath:BAAALgADCgEJAQAAAA==.',
Je='Jebra:BAAALgAECgYJEgAAAA==.Jellexy:BAAALgAECgQJBgAAAA==.',
Jo='Jolah:BAAALgADCgMJAwAAAA==.Jolahbae:BAABLgAECn8lAAISAAgJCBwcEABYAgASAAgJCBwcEABYAgAAAA==.Jonnyfive:BAAALgAECgIJAgAAAA==.',
Ka='Kailis:BAABLgAECn8VAAIBAAcJvhEzJQCFAQABAAcJvhEzJQCFAQAAAA==.Kaisa:BAAALgADCgcJBwAAAA==.Kanne:BAAALgADCgMJAwAAAA==.Karst:BAAALgAECgQJBAAAAA==.Katsudin:BAAALgAECgUJBQAAAA==.Kayzon:BAACLgAFFH8aAAMBAAYJCSJPAAD5AQABAAUJCSJPAAD5AQARAAUJUAezCgBuAQAuAAQKfzMAAxEACQndJYoCAIgDABEACQkYIooCAIgDAAEACQnaJeUGACADAAAA.Kayzwei:BAAALgAECgYJEwAAAA==.',
Ke='Kegtap:BAAALgADCgEJAQAAAA==.',
Ki='Kij:BAAALgAECgEJAQAAAA==.Killaks:BAAALgAECgYJBgAAAA==.Killdo:BAAALgAECgEJAQAAAA==.Kirilla:BAAALgADCgEJAQAAAA==.',
Kl='Klavine:BAABLgAECn8sAAITAAkJ1BY8AgCnAgATAAkJ1BY8AgCnAgAAAA==.',
Ko='Korben:BAABLgAECn8eAAIUAAgJaBllEwC8AQAUAAgJaBllEwC8AQAAAA==.Korenna:BAAALgADCgUJCgAAAA==.',
Kr='Kronn:BAAALgAECgEJAQAAAA==.Kruger:BAAALgAECgYJEQAAAA==.Kryptonicboy:BAAALgAECgMJBAAAAA==.',
Kt='Ktanna:BAAALgAECgYJCwAAAA==.',
Ku='Kublakhan:BAAALgAECgUJBgAAAA==.',
Ky='Kyfu:BAAALgADCgMJAwABLgAFFAQJDAAVAAMcAA==.Kynleria:BAAALgADCgEJAQAAAA==.',
La='Lakhi:BAABLgAECn8aAAIEAAgJ0Rw6EAD0AQAEAAgJ0Rw6EAD0AQAAAA==.Lateralus:BAAALgAECgYJEQAAAA==.Laureli:BAAALgAECgQJBAAAAA==.',
Le='Leeta:BAAALgAECgQJCAAAAA==.Legendx:BAAALgADCgUJBwAAAA==.',
Li='Lightningg:BAAALgAECgUJBgAAAA==.Lightsaved:BAAALgADCgIJAgAAAA==.Lightsworn:BAAALgAECgIJAgAAAA==.Linara:BAAALgADCgIJAgAAAA==.',
Lo='Lockbite:BAAALgADCgEJAQAAAA==.Lokralaila:BAAALgADCgQJBAAAAA==.Lollypopp:BAAALgAECgcJAQAAAA==.Lomme:BAAALgADCgcJBwAAAA==.Loraemar:BAAALgAECgEJAQAAAA==.Losoz:BAAALgAECgEJAQAAAA==.',
Lu='Lusilsandrus:BAAALgAECgQJCAAAAA==.Luxanna:BAAALgAECgIJAQAAAA==.',
Ma='Maegwin:BAAALgADCgUJBQAAAA==.Matti:BAAALgAECgQJCAAAAA==.',
Me='Mechaknight:BAAALgAECgMJAwAAAA==.Meddler:BAAALgADCgEJAgAAAA==.',
Mi='Mildrik:BAAALgAECgYJBgAAAA==.Miracledh:BAABLgAECn8RAAIWAAYJxSUkBQAfAgAWAAYJxSUkBQAfAgAAAA==.Mirkdrak:BAAALgAECgQJBwAAAA==.Misheard:BAABLgAECn8jAAIKAAkJex93FwCsAQAKAAkJex93FwCsAQAAAA==.Misjudged:BAAALgAECgUJCAAAAA==.Missus:BAAALgAECgQJBQAAAA==.Mit:BAAALgADCgkJGAAAAA==.Miyu:BAAALgADCgcJBwAAAA==.Mizzen:BAABLgAECn8WAAIXAAYJoxt1IQDKAQAXAAYJoxt1IQDKAQABLgAECgcJGwAGACYWAA==.',
Mo='Mohtavius:BAAALgAECgYJEAAAAA==.Mohz:BAAALgADCgcJCwAAAA==.Mommydearest:BAABLgAECn8dAAINAAgJOwesCQALAQANAAgJOwesCQALAQAAAA==.Moonbaboon:BAAALgAECgcJBgAAAA==.Moonkissed:BAAALgAECgEJAQAAAA==.Morttimuss:BAAALgAECgQJBQAAAA==.Motz:BAAALgADCgUJBgAAAA==.',
Mu='Munkìe:BAAALgAECgIJAwABLgAECgYJEwACAAAAAA==.Muura:BAABLgAECn8ZAAIQAAgJ2QuzXwDoAAAQAAgJ2QuzXwDoAAAAAA==.',
My='Myextralife:BAAALgADCgYJBgAAAA==.Myrik:BAAALgAECgQJCAAAAA==.',
Na='Naslunda:BAAALgADCgEJAQAAAA==.Nathyrra:BAABLgAECn8VAAIEAAYJUxpFFgC1AQAEAAYJUxpFFgC1AQAAAA==.',
Ne='Nebekenazar:BAAALgAECgYJBgAAAA==.Negate:BAAALgAECgYJEQABLgAFFAUJFQAYALQdAA==.',
Ni='Nitrö:BAAALgAECgEJAQABLgAECgQJCAACAAAAAA==.',
No='Noreset:BAAALgADCgYJBgAAAA==.Noriea:BAAALgADCgEJAQAAAA==.',
Nu='Nufonhudis:BAAALgAECgQJCAAAAA==.',
Om='Omnidacc:BAAALgAECgIJAgAAAA==.',
On='Onigirius:BAAALgAECgYJBgAAAA==.',
Ot='Otwin:BAAALgAECgQJBgAAAA==.',
Pa='Pahuum:BAAALgAECgEJAQAAAA==.Paimon:BAAALgAECgUJCAABLgAFFAQJDQAOAHIXAA==.Paintrainn:BAAALgAECgYJDQAAAA==.Palewhiteman:BAABLgAECn8YAAIUAAYJKhs+DwDtAQAUAAYJKhs+DwDtAQAAAA==.Palleigh:BAAALgAECgYJDAAAAA==.Pallyd:BAAALgADCgEJAQAAAA==.Patchës:BAAALgAECgQJCAAAAA==.',
Pe='Pepperjack:BAAALgAECgQJCAAAAA==.Persephonae:BAAALgADCgQJBAAAAA==.Persimmon:BAAALgAECgYJCgAAAA==.',
Pi='Pikklerikk:BAAALgAECgYJDAAAAA==.',
Po='Poondor:BAAALgAECgYJCgAAAA==.Poplocndrop:BAAALgADCgcJBwAAAA==.',
Pr='Predaturd:BAAALgAECgEJAQAAAA==.',
Pu='Purgatorri:BAAALgAECgQJBgAAAA==.',
Qi='Qindere:BAAALgAECgYJEAAAAA==.',
Ra='Raalaan:BAAALgADCgEJAQAAAA==.Raeinthe:BAABLgAECn8nAAIBAAkJkBOOEAARAgABAAkJkBOOEAARAgAAAA==.Ramantu:BAAALgADCgcJBwAAAA==.Rancor:BAAALgAECgEJAgABLgAECggJGAAQAFgbAA==.',
Re='Reihino:BAAALgADCgcJBwAAAA==.Resbak:BAAALgAECgcJBwAAAA==.Resiaus:BAABLgAECn8qAAIYAAkJNBVcAwBjAgAYAAkJNBVcAwBjAgAAAA==.',
Ri='Ripptyde:BAAALgADCgQJBAAAAA==.Rivalina:BAAALgADCgYJCQAAAA==.',
Ro='Robilargreen:BAAALgADCgUJBQAAAA==.Rocketabu:BAAALgAECgMJAwAAAA==.Roctheist:BAAALgAECgYJCgAAAA==.Rocthoeb:BAABLgAECn8sAAIIAAkJxhH8EQDoAQAIAAkJxhH8EQDoAQAAAA==.Rojito:BAAALgADCgkJGAAAAA==.',
Ry='Ry:BAABLgAECn8aAAIZAAcJxh37AwD5AQAZAAcJxh37AwD5AQAAAA==.',
Sa='Saintkhal:BAEALgAECgQJBwABLgAECgUJCgACAAAAAA==.Saintmedicus:BAEALgAECgUJCgAAAA==.Saintshammy:BAAALgAECgEJAQAAAA==.Saintshunter:BAAALgAECgEJAQAAAA==.Sanctor:BAABLgAECn8dAAIUAAcJeyJyEgB/AgAUAAcJeyJyEgB/AgAAAA==.Sandusky:BAAALgADCgQJBAAAAA==.Saraya:BAAALgAECgYJDgAAAA==.',
Se='Sephafael:BAAALgADCgcJDQAAAA==.Setsena:BAAALgAECgYJCgAAAA==.',
Sh='Shamwow:BAAALgAECgQJBAAAAA==.Shangi:BAAALgADCgMJAwAAAA==.Shinstabber:BAAALgAECgYJCgAAAA==.Shivantis:BAAALgADCgMJAwAAAA==.Shlarya:BAAALgAECgEJAQABLgAECggJDwACAAAAAA==.Shruggie:BAAALgAECgYJDQAAAA==.',
Si='Silven:BAAALgADCgMJAwAAAA==.Singingsword:BAAALgAECgEJAQAAAA==.Siphond:BAAALgADCgIJAgAAAA==.Siphondark:BAAALgAECgYJCgAAAA==.Sisqi:BAAALgADCgQJBAAAAA==.',
Sl='Slapnutz:BAABLgAECn8bAAIBAAcJ3xVvLwD0AQABAAcJ3xVvLwD0AQAAAA==.',
Sm='Smoki:BAAALgAECgUJBQAAAA==.',
So='Solvaii:BAAALgAECgYJEAAAAA==.',
St='Starfail:BAAALgAECgYJDgABLgAFFAQJCgAEADURAA==.Starlie:BAAALgAECgUJBQAAAA==.Stratacaster:BAAALgAECgMJBgAAAA==.Strawberry:BAAALgAECgUJCgAAAA==.Stuckinwell:BAACLgAFFH8FAAMMAAIJjxjaNQCnAAAMAAIJGBDaNQCnAAANAAEJkxYnDQBYAAAuAAQKfxsAAwwACQn6GrozAD0CAAwACAnpFrozAD0CAA0ABQkNHEEYAIgBAAAA.',
Su='Sunbound:BAABLgAFFH8HAAILAAIJ9xuFFQC3AAALAAIJ9xuFFQC3AAABLgAFFAUJFQAYALQdAA==.',
Sx='Sxths:BAAALgAECgEJAQAAAA==.',
Sy='Syela:BAAALgAECgQJDAABLgAECgcJGgAaAIMOAA==.Synsyn:BAAALgAECgQJBwAAAA==.',
Ta='Tach:BAAALgADCgYJBgAAAA==.Tanel:BAAALgAECgYJCAAAAA==.Targonne:BAAALgADCgEJAQAAAA==.Taterhots:BAAALgADCgcJBwAAAA==.Tatsü:BAAALgAECgIJAQAAAA==.Taílorswift:BAABLgAECn8UAAIFAAgJ5wxKiQC/AQAFAAgJ5wxKiQC/AQAAAA==.',
Te='Teanfists:BAAALgAECgEJAwAAAA==.Temna:BAAALgAECgYJEwAAAA==.Tenari:BAAALgAECggJDwAAAA==.',
Th='Theel:BAAALgAECgQJBgAAAA==.Thespaniard:BAABLgAECn8ZAAIbAAcJZhcIFABiAQAbAAcJZhcIFABiAQAAAA==.Thlunk:BAAALgADCgkJCQAAAA==.',
Ti='Tidebreaker:BAAALgAECgUJDgAAAA==.Tinbasher:BAAALgAECgQJBQAAAA==.',
Tj='Tjay:BAAALgADCgEJAQAAAA==.',
To='Totemistic:BAAALgADCggJCgAAAA==.',
Tr='Treebilly:BAAALgADCgkJDwAAAA==.Triviousox:BAAALgAECgYJCwAAAA==.',
Tu='Tungo:BAAALgADCgEJAQAAAA==.',
Tw='Twilightjade:BAAALgADCggJDwABLgAECgYJBwACAAAAAA==.Twotvmage:BAABLgAECn8cAAIFAAgJQhixIQDkAQAFAAgJQhixIQDkAQAAAA==.',
Un='Unglued:BAAALgADCgcJDgAAAA==.Unholygrimg:BAAALgADCgUJBQAAAA==.Unholywar:BAAALgAECgYJBwABLgAECggJIAAMAEgZAA==.',
Ur='Ursolana:BAAALgADCgUJBQAAAA==.',
Va='Valkky:BAAALgAECgYJEQAAAA==.Valleya:BAAALgAECgIJAgAAAA==.Vallysong:BAAALgAECgYJCQAAAA==.Valnetrois:BAAALgADCgEJAQAAAA==.Vaswislor:BAAALgADCgIJAwAAAA==.',
Ve='Velayna:BAAALgAECgYJCgAAAA==.Velenn:BAAALgADCgcJCAAAAA==.Venatar:BAAALgAECgYJEwAAAA==.Vessna:BAAALgAECgQJBAABLgAECgQJBwACAAAAAA==.',
Vi='Vicarious:BAAALgAECgYJEwAAAA==.Visea:BAAALgADCgEJAQAAAA==.Vivîán:BAAALgAECgIJAgAAAA==.',
Vm='Vmro:BAAALgADCgYJEQAAAA==.',
Vo='Voras:BAAALgAECgUJDwAAAA==.Vorttex:BAAALgAECgEJAQAAAA==.',
Wa='Waitandbleed:BAAALgADCgcJBwAAAA==.Wanglock:BAAALgAECgYJDAABLgAFFAgJHAAOAGYcAA==.Wardstar:BAAALgADCgIJAgAAAA==.Wasure:BAAALgAECgQJCAAAAA==.',
Wh='Whiskeyrick:BAAALgADCgMJAwAAAA==.',
Wi='Wildkanaka:BAAALgADCgEJAQAAAA==.Winters:BAAALgADCggJCAAAAA==.',
Wo='Worthy:BAAALgADCgYJBgAAAA==.',
Xa='Xalatath:BAABLgAECn8YAAIbAAgJ4RsEEQB4AgAbAAgJ4RsEEQB4AgAAAA==.',
Xt='Xtra:BAAALgADCgEJAQAAAA==.',
Xy='Xylar:BAAALgAECggJDwAAAA==.',
Ya='Yahiko:BAAALgAECgMJAwAAAA==.',
Yu='Yuzuriha:BAAALgAECgQJCQAAAA==.',
Za='Zarazard:BAAALgADCggJCwAAAA==.',
Ze='Zeynah:BAAALgADCgYJBgAAAA==.',
Zo='Zophier:BAAALgADCgMJAwAAAA==.',
Zu='Zube:BAAALgAECgUJBwAAAA==.',
['Âu']='Âuranna:BAAALgAECgYJBgAAAA==.',
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

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

local lookup = {'Paladin-Retribution','Druid-Balance','Shaman-Restoration','Priest-Discipline','Priest-Holy','Priest-Shadow','Unknown-Unknown','Warrior-Arms','Warrior-Fury','Hunter-BeastMastery','Hunter-Marksmanship','Hunter-Survival','DeathKnight-Unholy','Warrior-Protection','Monk-Brewmaster','Druid-Restoration','Druid-Feral','Shaman-Elemental','Monk-Mistweaver','Monk-Windwalker','Evoker-Preservation','Paladin-Protection','Warlock-Demonology','Warlock-Destruction','DemonHunter-Devourer','DemonHunter-Havoc','Rogue-Subtlety','Mage-Frost','Druid-Guardian','Paladin-Holy','Evoker-Devastation',}
local provider = {region='US',realm='Executus',name='US',type='weekly',zone=46,date='2026-05-08',data={Ad='Adventis:BAAALgADCgQJAwAAAA==.',
Al='Allavus:BAAALgADCgQJBQABLgAFFAMJCAABAKkUAA==.',
An='Andersen:BAAALgAECgQJEwAAAA==.Ando:BAAALgAECgEJAQABLgAECgkJIgACAD4XAA==.Andryu:BAABLgAECn8cAAICAAkJbxI5DgDqAQACAAkJbxI5DgDqAQAAAA==.Anebel:BAAALgADCgkJCQAAAA==.Angelmuerte:BAAALgADCgkJDgAAAA==.Angyal:BAAALgAECgYJBwAAAA==.',
Ap='Apolion:BAAALgADCgYJBgAAAA==.',
Ar='Archerius:BAAALgADCgcJCwAAAA==.Arkanis:BAABLgAECn8oAAIDAAgJ/B2CDQBdAgADAAgJ/B2CDQBdAgAAAA==.Arïel:BAABLgAECn8cAAQEAAcJLBqXHQCoAQAEAAcJYhmXHQCoAQAFAAEJfRuDRgBLAAAGAAEJKQUVVgAvAAAAAA==.',
Az='Azalya:BAAALgAECgQJBAAAAA==.',
Ba='Banidor:BAAALgAECgIJAgABLgAECgYJCAAHAAAAAA==.Banthistoó:BAAALgADCgcJCAAAAA==.',
Be='Becka:BAAALgADCgEJAQAAAA==.',
Bh='Bhrown:BAAALgADCgQJBAAAAA==.',
Bi='Bigdrill:BAAALgADCgYJBgAAAA==.',
Bl='Bloodlyn:BAAALgADCgUJBQAAAA==.Blueming:BAAALgAECgMJBQAAAA==.',
Bo='Bonsai:BAABLgAECn8UAAMIAAYJCwj1HQDJAAAJAAYJ/QUpNgDvAAAIAAYJmgb1HQDJAAAAAA==.',
Br='Broadfang:BAACLgAFFH8dAAMKAAYJziKJBQCQAQAKAAUJliKJBQCQAQALAAUJtRJODwA4AQAuAAQKfyQABAoACQlPJZ0cAFoCAAsABwliIokYAGgCAAoABgnHJJ0cAFoCAAwABAlWDjYiAMMAAAAA.Broconis:BAAALgAECgUJBgAAAA==.',
Bu='Bubbleoseven:BAAALgAECgUJDwAAAA==.Bullorly:BAACLgAFFH8SAAINAAUJbB00JgBTAQANAAUJbB00JgBTAQAuAAQKfxkAAg0ACQluJAAcANYCAA0ACQluJAAcANYCAAAA.Bungulators:BAEALgAECgEJAQABLgAECggJMQAOAGwZAA==.',
Ca='Capriestsunn:BAAALgAECgUJDQAAAA==.Casey:BAAALgAECgEJAQAAAA==.',
Ch='Chunt:BAAALgADCgkJDQAAAA==.',
Cl='Clickshot:BAABLgAECn8uAAMKAAkJyCTLAABlAwAKAAkJyCTLAABlAwALAAQJBBL1WQDcAAAAAA==.Clipee:BAAALgAECgYJBgAAAA==.Clipeskeg:BAABLgAECn8gAAIPAAkJ2xt/BgBwAgAPAAkJ2xt/BgBwAgAAAA==.Clipex:BAAALgAECgYJBgAAAA==.',
Co='Contagium:BAAALgAECgQJCgAAAA==.',
Cy='Cynîc:BAAALgAECgYJCAAAAA==.',
Da='Daddynature:BAAALgAECgUJDQAAAA==.Daddyÿ:BAAALgAECgEJAQAAAA==.Darenas:BAABLgAECn8oAAMGAAkJlBioEADIAQAGAAkJlBioEADIAQAEAAEJhQ1tRQA2AAAAAA==.Darkspyro:BAAALgADCgEJAQAAAA==.Dasu:BAABLgAECn8iAAQQAAkJ/AqZRQD9AAAQAAgJQAiZRQD9AAACAAYJ7gYMKwDuAAARAAMJUQKhLgBSAAAAAA==.David:BAAALgADCgcJDwABLgAECgkJIgAMAJ8cAA==.',
De='Deathbooze:BAACLgAFFH8GAAINAAMJ+SEwOQAnAQANAAMJ+SEwOQAnAQAuAAQKfyoAAg0ACAnaHkkTAGECAA0ACAnaHkkTAGECAAAA.Deathmikee:BAABLgAECn8oAAINAAkJOxs5DwCGAgANAAkJOxs5DwCGAgAAAA==.',
Di='Dimethaline:BAAALgADCgcJBwAAAA==.Dinlek:BAAALgAECgcJDQAAAA==.Dinosoars:BAAALgADCgEJAQAAAA==.',
Dk='Dkmountain:BAABLgAECn8fAAIGAAcJGyFJEwBaAgAGAAcJGyFJEwBaAgAAAA==.',
Dr='Draknol:BAAALgAECgIJAgAAAA==.Drakos:BAAALgAECgQJAwAAAA==.Drunknfist:BAAALgAECgEJAgAAAA==.',
Du='Durton:BAABLgAECn8iAAIJAAkJ7xk2GACKAgAJAAkJ7xk2GACKAgAAAA==.',
Ec='Echidna:BAABLgAFFH8FAAIKAAMJaxA8KwDsAAAKAAMJaxA8KwDsAAABLgAFFAQJCwASABYeAA==.Echø:BAAALgADCgUJBQAAAA==.',
Ed='Edison:BAABLgAECn8uAAMJAAkJOx6mBACzAgAJAAkJOx6mBACzAgAIAAIJNBg5MgBXAAAAAA==.',
Ef='Eferis:BAAALgAECgYJBgAAAA==.',
El='Elder:BAAALgAECgYJBgAAAA==.Elderdorje:BAABLgAECn8tAAMTAAkJnhwGBwCMAgATAAkJnhwGBwCMAgAUAAEJ7gH1iQAkAAAAAA==.Elesa:BAAALgADCgEJAQAAAA==.Elixe:BAAALgADCgEJAQAAAA==.Elondre:BAABLgAECn8oAAIDAAgJTCUzAwAeAwADAAgJTCUzAwAeAwAAAA==.',
Em='Emomorf:BAAALgAECgcJDwAAAA==.Employee:BAACLgAFFH8eAAIJAAcJrh1qAAAbAgAJAAcJrh1qAAAbAgAuAAQKfyIAAwkACQmvJVgBALwDAAkACQmvJVgBALwDAA4AAwmCGvYxALUAAAAA.',
Ev='Evangeliné:BAAALgAECgEJAQAAAA==.',
Ex='Exavier:BAAALgADCgQJBAAAAA==.',
Fi='Fistsofseno:BAAALgAECgEJAQAAAA==.Fizzenator:BAABLgAECn8hAAIMAAkJ8RvSAgC4AgAMAAkJ8RvSAgC4AgAAAA==.',
Fw='Fweeb:BAAALgAECgMJAwAAAA==.',
Ga='Galatea:BAACLgAFFH8IAAIBAAMJqRR1LAD/AAABAAMJqRR1LAD/AAAuAAQKfyQAAgEACQnWIdYGAOICAAEACQnWIdYGAOICAAAA.Galifen:BAABLgAECn8tAAICAAkJdyV2AAB0AwACAAkJdyV2AAB0AwAAAA==.Gank:BAAALgAECgYJCQAAAA==.Gargyll:BAAALgADCgUJBQAAAA==.Garysparks:BAAALgAECgEJAQAAAA==.',
Ge='Gelidon:BAABLgAECn8fAAIVAAkJlBhZBQBFAgAVAAkJlBhZBQBFAgAAAA==.',
Gh='Ghreen:BAAALgAECgMJBAAAAA==.',
Gi='Gilgahmesh:BAABLgAECn8UAAMWAAUJwwolHwCbAAAWAAUJwwolHwCbAAABAAEJaQNuWAEmAAABLgAECggJIAANALYEAA==.',
Gn='Gnomegrown:BAABLgAECn8WAAICAAYJyBMwJAAZAQACAAYJyBMwJAAZAQAAAA==.',
Gr='Gragehorn:BAAALgAECgEJAQAAAA==.Grapejuice:BAAALgAECgEJAQAAAA==.Gruvi:BAAALgAECgEJAQAAAA==.',
Gu='Gumbusta:BAAALgAECgcJDQAAAA==.Gummiie:BAAALgADCgEJAQAAAA==.Gunrunner:BAAALgADCgcJBwAAAA==.',
Ha='Halestorm:BAAALgADCgYJBgAAAA==.Halyer:BAAALgAECggJDwAAAA==.Hankthesnake:BAAALgADCgcJGwAAAA==.',
He='Helioboops:BAAALgAECgQJBAAAAA==.Hexdaman:BAAALgAECgMJBAAAAA==.',
Ho='Hobbz:BAACLgAFFH8UAAIBAAUJsSDEAwC2AQABAAUJsSDEAwC2AQAuAAQKfyYAAgEACQm2JBoHAF8DAAEACQm2JBoHAF8DAAAA.Hodge:BAAALgADCgMJAwAAAA==.Hoid:BAAALgADCgEJAQAAAA==.Holyshorts:BAAALgAECgYJCAAAAA==.',
Il='Illandros:BAAALgAECgYJDwAAAA==.Illidankmeme:BAAALgADCgIJAgAAAA==.',
In='Ingredient:BAABLgAECn8bAAIRAAgJ2hHyBwCzAQARAAgJ2hHyBwCzAQAAAA==.Inspire:BAAALgAECggJEQAAAA==.',
Is='Isinia:BAAALgAECgUJDgAAAA==.',
Ja='Janitor:BAAALgADCgMJAgAAAA==.Jayas:BAAALgAECgQJBwAAAA==.Jayim:BAAALgAECgkJEgAAAA==.Jaína:BAAALgAECgYJDAABLgAECggJEwAHAAAAAA==.',
Je='Jencks:BAAALgAECgQJCAABLgAECgkJIgACAD4XAA==.',
Ji='Jiren:BAABLgAECn8sAAMTAAkJqCAdAgA/AwATAAkJqCAdAgA/AwAUAAMJTgkkXwCTAAAAAA==.',
Jo='Johnson:BAAALgAECgUJCgAAAA==.Johnsunwell:BAAALgADCgQJAwAAAA==.Joran:BAAALgAECgYJEgAAAA==.',
Ju='Juckbolas:BAAALgAECgQJBAAAAA==.Juicyjj:BAABLgAECn8ZAAINAAgJCQ0CRQBtAQANAAgJCQ0CRQBtAQAAAA==.Jukesnaxx:BAAALgAECgMJBQAAAA==.',
Ka='Kaije:BAAALgADCgMJAwAAAA==.',
Ke='Kelekii:BAAALgADCgIJAgAAAA==.',
Ki='Kiritø:BAAALgADCgIJAgAAAA==.',
Kr='Kravoxx:BAAALgADCgUJCQABLgAECgYJCAAHAAAAAA==.Kro:BAAALgAECgYJDQAAAA==.Krysess:BAAALgADCgEJAQAAAA==.',
Le='Leanea:BAAALgAECgMJAwAAAA==.',
Li='Lich:BAAALgAFFAQJAgAAAA==.Liera:BAABLgAECn8bAAINAAcJvQ5PUABLAQANAAcJvQ5PUABLAQAAAA==.',
Ll='Lloydlei:BAABLgAECn8iAAMXAAkJ/xv+CwCRAgAXAAkJvRv+CwCRAgAYAAIJURxFRwCZAAAAAA==.',
Lo='Lodin:BAAALgAECgEJAQAAAA==.',
Lu='Luminå:BAABLgAECn8gAAIYAAkJZhg3BQCsAQAYAAkJZhg3BQCsAQAAAA==.',
Ly='Lylenn:BAAALgADCgkJGwAAAA==.',
Ma='Madora:BAAALgADCgQJBAAAAA==.Maibisan:BAABLgAECn8nAAMZAAgJ0yOhBQDTAgAZAAgJ0yOhBQDTAgAaAAUJyB4VEgBoAQAAAA==.Malificent:BAABLgAECn8YAAIXAAcJ5B0VHQACAgAXAAcJ5B0VHQACAgAAAA==.Malighn:BAABLgAECn8gAAINAAgJtgS6ZgAVAQANAAgJtgS6ZgAVAQAAAA==.Masseffex:BAAALgAECgQJCQAAAA==.',
Mc='Mcshooty:BAAALgADCgUJBQAAAA==.',
Mo='Modi:BAAALgAECgEJAQAAAA==.Mookong:BAAALgADCgEJAQAAAA==.Moonsliver:BAAALgAECgEJAgAAAA==.Mordecâi:BAAALgAECgEJAQAAAA==.Morf:BAAALgAECgMJAwABLgAECgkJHwAVAJQYAA==.Morganä:BAAALgAECgQJCQAAAA==.Morthrin:BAAALgAECgcJEQAAAA==.',
Mu='Muhrieyuh:BAAALgADCgQJBAAAAA==.',
My='Mystwolf:BAABLgAECn8pAAIDAAgJWhyVFABwAgADAAgJWhyVFABwAgAAAA==.',
Ne='Ned:BAAALgAECgIJAgABLgAECgQJBgAHAAAAAA==.',
Ni='Niccelndime:BAAALgAECgYJDgAAAA==.Nightember:BAAALgAECgEJAQABLgAECgkJLQATAJ4cAA==.Nightski:BAABLgAECn8hAAIQAAgJDRYZMADrAQAQAAgJDRYZMADrAQAAAA==.Nikolatesla:BAAALgAECgUJBQAAAA==.Nizzari:BAABLgAECn8kAAIbAAkJDhMtBwA5AgAbAAkJDhMtBwA5AgAAAA==.',
No='Nothalyer:BAABLgAECn8sAAIVAAkJag3WCwCOAQAVAAkJag3WCwCOAQAAAA==.',
Of='Offline:BAABLgAECn8WAAIQAAgJth1LCgCjAgAQAAgJth1LCgCjAgAAAA==.',
Oh='Ohms:BAACLgAFFH8GAAIcAAMJcAfoTwDjAAAcAAMJcAfoTwDjAAAuAAQKfy8AAhwACAmMHJweADICABwACAmMHJweADICAAAA.',
Ol='Olaria:BAAALgADCgYJDwAAAA==.',
Or='Orwasitshrek:BAAALgAECgYJDwAAAA==.Orwasitwrekt:BAAALgADCgkJCQABLgAECgYJDwAHAAAAAA==.',
Pa='Palabop:BAAALgAECgYJCwAAAA==.Paladinii:BAAALgAECgMJAwAAAA==.',
Pl='Planec:BAAALgAECgYJBgAAAA==.',
Po='Polytots:BAABLgAECn8qAAMSAAkJABM0LgCrAQASAAkJABM0LgCrAQADAAgJxg9QNAA6AQAAAA==.',
Pr='Proteus:BAAALgADCgMJAwAAAA==.',
Qi='Qiller:BAAALgAECgQJBgAAAA==.',
Qu='Quinne:BAAALgADCgEJAQABLgAECgEJAQAHAAAAAA==.',
Ra='Ranin:BAAALgAECgcJDAAAAA==.Razius:BAAALgAECgkJEgAAAA==.',
Ri='Riplordfire:BAAALgAECgEJAQAAAA==.',
Ro='Roadsign:BAAALgAECgYJDwAAAA==.Rottey:BAAALgAECgMJAwAAAA==.Roxette:BAAALgADCgcJBwAAAA==.',
Sa='Salvation:BAAALgAECgYJDwAAAA==.Sanctis:BAAALgAECgMJAwAAAA==.Santan:BAAALgADCgIJAgAAAA==.',
Sc='Scarecrow:BAAALgAECgEJAgAAAA==.',
Se='Sealgair:BAAALgAECgEJAgAAAA==.Senovourer:BAABLgAECn8fAAIZAAkJeyEJCwAqAwAZAAkJeyEJCwAqAwAAAA==.',
Sh='Shabamoo:BAABLgAECn8eAAMQAAgJ1B00CQC1AgAQAAgJ1B00CQC1AgARAAEJggcuKAAzAAAAAA==.Shakkes:BAAALgAECgEJAQAAAA==.Shasato:BAABLgAECn8hAAIdAAgJqxZUCQCOAQAdAAgJqxZUCQCOAQAAAA==.Shelian:BAAALgAECgEJAQAAAA==.Shiranai:BAAALgADCgEJAQAAAA==.Shoosty:BAAALgADCgcJDAAAAA==.',
Si='Sicarii:BAAALgADCgcJCAAAAA==.Sizouze:BAAALgAECgcJCwAAAA==.',
Sk='Skeeter:BAAALgAECgYJBgAAAA==.Skyepic:BAACLgAFFH8VAAIeAAcJVBTFAQDuAQAeAAcJVBTFAQDuAQAuAAQKfyIAAx4ACQlfIC4HAPkCAB4ACQlfIC4HAPkCAAEABAllEnrVAOAAAAAA.Skylight:BAAALgAECgEJAQAAAA==.',
Sn='Snugwalnut:BAACLgAFFH8OAAIDAAQJwyNcCACTAQADAAQJwyNcCACTAQAuAAQKfzEAAgMACAlJIzYEAAADAAMACAlJIzYEAAADAAAA.',
So='Soejoedi:BAABLgAECn8iAAICAAkJPhcACABTAgACAAkJPhcACABTAgAAAA==.',
St='Stitchzpls:BAAALgAECgUJCQAAAA==.',
Su='Sunhammer:BAAALgAECgEJAQAAAA==.Sunsworn:BAAALgAECgQJBwAAAA==.',
Sw='Sweetyboi:BAAALgAECgYJDgAAAA==.',
Ta='Tarhostamir:BAAALgAECgYJCwAAAA==.Taurup:BAAALgADCggJCAAAAA==.Tazz:BAABLgAECn8UAAIKAAYJPQcSWwD/AAAKAAYJPQcSWwD/AAAAAA==.',
Te='Tecnine:BAAALgADCgUJBQAAAA==.Teledar:BAAALgAECgQJCAAAAA==.',
Th='Thaysinga:BAAALgADCgQJBAAAAA==.Thelandlord:BAACLgAFFH8UAAIVAAYJTxXABQDLAQAVAAYJTxXABQDLAQAuAAQKfxwAAxUACAkOG9YMAGgCABUACAkOG9YMAGgCAB8AAwnJDpgvAJoAAAAA.Theshape:BAAALgADCgMJAwAAAA==.Thunderblast:BAAALgAECgYJEgAAAA==.Thuss:BAABLgAECn8XAAIZAAYJIxb3PwA5AQAZAAYJIxb3PwA5AQAAAA==.',
Ti='Titgunniz:BAAALgADCgYJCQAAAA==.',
Tu='Tugnutz:BAAALgAECgUJDQAAAA==.Tuk:BAAALgAECgMJAwAAAA==.',
Tw='Twirlywhirly:BAAALgAECgYJBgAAAA==.',
['Tè']='Tèmpos:BAAALgADCgcJCAAAAA==.',
Un='Unplug:BAAALgAECgQJDAAAAA==.',
Va='Vander:BAAALgAECgQJBAABLgAECgQJBwAHAAAAAA==.Vanidossa:BAAALgAECgcJEgAAAA==.Varygud:BAAALgADCgUJBgAAAA==.Vayper:BAABLgAECn8tAAIGAAkJliBPAgD1AgAGAAkJliBPAgD1AgAAAA==.',
Ve='Veins:BAAALgADCgQJDAAAAA==.Verdict:BAAALgAFFAEJAgAAAA==.',
Vo='Voklin:BAAALgAECgQJBAAAAA==.',
We='Weemsy:BAABLgAECn8kAAIJAAkJciKgAQAZAwAJAAkJciKgAQAZAwAAAA==.',
Wi='Wildfire:BAACLgAFFH8QAAIMAAUJlCNYAwCEAQAMAAUJlCNYAwCEAQAuAAQKfywAAgwACQmKJoMAAJADAAwACQmKJoMAAJADAAAA.Wildfirë:BAAALgAECgYJBgABLgAFFAUJEAAMAJQjAA==.Willthewise:BAAALgADCgIJAgAAAA==.',
Wo='Wolffei:BAAALgAECgEJAQAAAA==.Wolfhammer:BAABLgAECn8YAAIOAAgJPh0vBQBUAgAOAAgJPh0vBQBUAgAAAA==.Wolflee:BAAALgAECgYJDwAAAA==.Wolfmend:BAAALgAECgYJEAAAAA==.',
Xa='Xamid:BAAALgAECgYJEAAAAA==.Xaxfen:BAACLgAFFH8PAAIOAAUJyxTsBAAoAQAOAAUJyxTsBAAoAQAuAAQKfxoAAw4ACAkhIdMJAHoCAA4ACAkhIdMJAHoCAAkAAgk4CDJSAGwAAAAA.',
['Xê']='Xêndâr:BAAALgADCgQJBAAAAA==.',
Za='Zappieboy:BAAALgAECgIJBAAAAA==.',
Zu='Zulgrimm:BAAALgADCgMJAwAAAA==.',
Zy='Zyfèr:BAAALgAECgYJEgAAAA==.',
['Zî']='Zîmìk:BAAALgAECgIJAgAAAA==.',
['Às']='Àsh:BAABLgAECn8lAAIFAAkJxh7bAwDjAgAFAAkJxh7bAwDjAgAAAA==.',
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

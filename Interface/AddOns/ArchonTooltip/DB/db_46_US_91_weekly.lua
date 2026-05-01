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

local lookup = {'Paladin-Retribution','Druid-Balance','Shaman-Restoration','Priest-Discipline','Priest-Holy','Priest-Shadow','Unknown-Unknown','Warrior-Arms','Warrior-Fury','Hunter-BeastMastery','Hunter-Marksmanship','Hunter-Survival','DeathKnight-Unholy','Warrior-Protection','Monk-Brewmaster','Druid-Restoration','Druid-Feral','Shaman-Elemental','Monk-Mistweaver','Monk-Windwalker','Evoker-Preservation','Warlock-Demonology','Warlock-Destruction','DemonHunter-Devourer','Rogue-Subtlety','Mage-Frost','Druid-Guardian','Paladin-Holy','Evoker-Devastation',}
local provider = {region='US',realm='Executus',name='US',type='weekly',zone=46,date='2026-05-01',data={Ad='Adventis:BAAALgADCgQJAwAAAA==.',
Al='Allavus:BAAALgADCgQJBQABLgAECggJHAABAA8fAA==.',
An='Andersen:BAAALgAECgQJEgAAAA==.Ando:BAAALgADCgUJBwABLgAECgkJHwACAPAWAA==.Andryu:BAABLgAECn8VAAICAAgJxBHGDwCXAQACAAgJxBHGDwCXAQAAAA==.Anebel:BAAALgADCgkJCQAAAA==.Angelmuerte:BAAALgADCgkJDgAAAA==.Angyal:BAAALgAECgYJBwAAAA==.',
Ar='Archerius:BAAALgADCgcJCwAAAA==.Arkanis:BAABLgAECn8gAAIDAAcJNCC+DAAfAgADAAcJNCC+DAAfAgAAAA==.Arïel:BAABLgAECn8cAAQEAAcJLBqYHQCoAQAEAAcJYhmYHQCoAQAFAAEJfRulOABOAAAGAAEJKQVGRAAvAAAAAA==.',
Az='Azalya:BAAALgAECgQJBAAAAA==.',
Ba='Banidor:BAAALgAECgIJAgABLgAECgYJCAAHAAAAAA==.',
Be='Becka:BAAALgADCgEJAQAAAA==.',
Bh='Bhrown:BAAALgADCgQJBAAAAA==.',
Bi='Bigdrill:BAAALgADCgYJBgAAAA==.',
Bl='Bloodlyn:BAAALgADCgUJBQAAAA==.Blueming:BAAALgAECgMJBQAAAA==.',
Bo='Bonsai:BAABLgAECn8UAAMIAAYJCwj1FADTAAAJAAYJ/QV5KQD6AAAIAAYJmgb1FADTAAAAAA==.',
Br='Broadfang:BAACLgAFFH8XAAMKAAYJXxsGAwBtAQAKAAUJNh0GAwBtAQALAAUJyw5JDwA4AQAuAAQKfyQABAoACQlPJaAcAFoCAAsABwliItQYAGECAAoABgnHJKAcAFoCAAwABAlWDjciAMMAAAAA.Broconis:BAAALgAECgUJBgAAAA==.',
Bu='Bubbleoseven:BAAALgAECgUJCwAAAA==.Bullorly:BAACLgAFFH8OAAINAAQJbh0PFABfAQANAAQJbh0PFABfAQAuAAQKfxkAAg0ACQluJAEcANYCAA0ACQluJAEcANYCAAAA.Bungulators:BAEALgAECgEJAQABLgAECggJKQAOAI4TAA==.',
Ca='Capriestsunn:BAAALgAECgUJDQAAAA==.Casey:BAAALgAECgEJAQAAAA==.',
Ch='Chunt:BAAALgADCgkJDQAAAA==.',
Cl='Clickshot:BAABLgAECn8gAAMKAAgJCh9ICgBZAgAKAAgJCh9ICgBZAgALAAQJBBLcWQDcAAAAAA==.Clipee:BAAALgAECgYJBgAAAA==.Clipeskeg:BAABLgAECn8dAAIPAAgJvhqmCAAEAgAPAAgJvhqmCAAEAgAAAA==.',
Co='Contagium:BAAALgAECgMJBgAAAA==.',
Cy='Cynîc:BAAALgAECgYJCAAAAA==.',
Da='Daddynature:BAAALgAECgUJDQAAAA==.Daddyÿ:BAAALgAECgEJAQAAAA==.Darenas:BAABLgAECn8oAAMGAAkJlBi+CgDUAQAGAAkJlBi+CgDUAQAEAAEJhQ2xNgA2AAAAAA==.Darkspyro:BAAALgADCgEJAQAAAA==.Dasu:BAABLgAECn8aAAQQAAgJPgg/NQACAQAQAAgJPgg/NQACAQARAAMJUQKhLgBSAAACAAIJmgI2ewA7AAAAAA==.David:BAAALgADCgcJDwAAAA==.',
De='Deathbooze:BAABLgAECn8jAAINAAgJTBZIKACcAQANAAgJTBZIKACcAQAAAA==.Deathmikee:BAABLgAECn8gAAINAAgJlxunFAAUAgANAAgJlxunFAAUAgAAAA==.',
Di='Dimethaline:BAAALgADCgcJBwAAAA==.Dinlek:BAAALgAECgYJCwAAAA==.Dinosoars:BAAALgADCgEJAQAAAA==.',
Dk='Dkmountain:BAABLgAECn8fAAIGAAcJGyFLEwBaAgAGAAcJGyFLEwBaAgAAAA==.',
Dr='Draknol:BAAALgAECgIJAgAAAA==.Drakos:BAAALgAECgQJAwAAAA==.Drunknfist:BAAALgADCgMJAwAAAA==.',
Du='Durton:BAABLgAECn8hAAIJAAgJVhs5GACKAgAJAAgJVhs5GACKAgAAAA==.',
Ec='Echidna:BAAALgAFFAIJAgABLgAFFAQJCQASAMIaAA==.Echø:BAAALgADCgUJBQAAAA==.',
Ed='Edison:BAABLgAECn8pAAMJAAgJSB0zBgBRAgAJAAgJSB0zBgBRAgAIAAIJLhgkJQBYAAAAAA==.',
Ef='Eferis:BAAALgAECgQJBgAAAA==.',
El='Elder:BAAALgAECgYJBgAAAA==.Elderdorje:BAABLgAECn8kAAMTAAgJsh3RBwA8AgATAAgJsh3RBwA8AgAUAAEJ7gHxiQAkAAAAAA==.Elesa:BAAALgADCgEJAQAAAA==.Elixe:BAAALgADCgEJAQAAAA==.Elondre:BAABLgAECn8gAAIDAAgJfCGMBAC2AgADAAgJfCGMBAC2AgAAAA==.',
Em='Emomorf:BAAALgAECgYJCwAAAA==.Employee:BAACLgAFFH8cAAIJAAYJISBgAADqAQAJAAYJISBgAADqAQAuAAQKfyIAAwkACQmvJVgBALwDAAkACQmvJVgBALwDAA4AAwmCGvoxALUAAAAA.',
Ev='Evangeliné:BAAALgAECgEJAQAAAA==.',
Ex='Exavier:BAAALgADCgQJBAAAAA==.',
Fi='Fistsofseno:BAAALgAECgEJAQAAAA==.Fizzenator:BAABLgAECn8aAAIMAAkJnhgfAwBtAgAMAAkJnhgfAwBtAgAAAA==.',
Fw='Fweeb:BAAALgAECgMJAwAAAA==.',
Ga='Galatea:BAABLgAECn8cAAIBAAgJDx/zIQCiAgABAAgJDx/zIQCiAgAAAA==.Galifen:BAABLgAECn8kAAICAAgJwSVkAQAHAwACAAgJwSVkAQAHAwAAAA==.Gank:BAAALgAECgUJCAAAAA==.Gargyll:BAAALgADCgUJBQAAAA==.Garysparks:BAAALgADCgEJAQAAAA==.',
Ge='Gelidon:BAABLgAECn8XAAIVAAgJ5hVYFgDoAQAVAAgJ5hVYFgDoAQAAAA==.',
Gh='Ghreen:BAAALgAECgIJAgAAAA==.',
Gi='Gilgahmesh:BAAALgAECgUJDwABLgAECggJHwANAKcEAA==.',
Gn='Gnomegrown:BAABLgAECn8UAAICAAYJyBNNGwAhAQACAAYJyBNNGwAhAQAAAA==.',
Gr='Gragehorn:BAAALgAECgEJAQAAAA==.Grapejuice:BAAALgAECgEJAQAAAA==.Gruvi:BAAALgAECgEJAQAAAA==.',
Gu='Gumbusta:BAAALgAECgcJDQAAAA==.Gummiie:BAAALgADCgEJAQAAAA==.Gunrunner:BAAALgADCgcJBwAAAA==.',
Ha='Halestorm:BAAALgADCgYJBgAAAA==.Halyer:BAAALgAECgcJCgAAAA==.Hankthesnake:BAAALgADCgcJGwAAAA==.',
He='Helioboops:BAAALgAECgQJBAAAAA==.Hexdaman:BAAALgAECgMJBAAAAA==.',
Ho='Hobbz:BAACLgAFFH8TAAIBAAUJsSDDAwC2AQABAAUJsSDDAwC2AQAuAAQKfyYAAgEACQm2JBsHAF8DAAEACQm2JBsHAF8DAAAA.Hodge:BAAALgADCgMJAwAAAA==.Hoid:BAAALgADCgEJAQAAAA==.Holyshorts:BAAALgAECgYJCAAAAA==.',
Il='Illandros:BAAALgAECgUJCgAAAA==.Illidankmeme:BAAALgADCgIJAgAAAA==.',
In='Ingredient:BAABLgAECn8UAAIRAAcJjhAmFQBiAQARAAcJjhAmFQBiAQAAAA==.Inspire:BAAALgAECggJEQAAAA==.',
Is='Isinia:BAAALgAECgUJDgAAAA==.',
Ja='Janitor:BAAALgADCgMJAgAAAA==.Jayas:BAAALgAECgMJAwABLgAECgQJBAAHAAAAAA==.Jayim:BAAALgAECgkJEQAAAA==.',
Je='Jencks:BAAALgADCgYJDwABLgAECgkJHwACAPAWAA==.',
Ji='Jiren:BAABLgAECn8jAAMTAAgJVyFgAgDzAgATAAgJVyFgAgDzAgAUAAMJTgkjXwCTAAAAAA==.',
Jo='Johnson:BAAALgAECgUJBQAAAA==.Johnsunwell:BAAALgADCgQJAwAAAA==.Joran:BAAALgAECgYJDAAAAA==.',
Ju='Juckbolas:BAAALgAECgQJBAAAAA==.Juicyjj:BAABLgAECn8ZAAINAAgJCQ3pMAB2AQANAAgJCQ3pMAB2AQAAAA==.Jukesnaxx:BAAALgAECgMJBQAAAA==.',
Ka='Kaije:BAAALgADCgMJAwAAAA==.',
Ke='Kelekii:BAAALgADCgIJAgAAAA==.',
Ki='Kiritø:BAAALgADCgIJAgAAAA==.',
Kr='Kravoxx:BAAALgADCgUJCQABLgAECgYJCAAHAAAAAA==.Kro:BAAALgAECgUJCAAAAA==.Krysess:BAAALgADCgEJAQAAAA==.',
Le='Leanea:BAAALgAECgMJAwAAAA==.',
Li='Lich:BAAALgAFFAQJAQAAAA==.Liera:BAABLgAECn8YAAINAAYJ4Q/WSwAcAQANAAYJ4Q/WSwAcAQAAAA==.',
Ll='Lloydlei:BAABLgAECn8ZAAMWAAgJFRufLgBSAgAWAAgJyhqfLgBSAgAXAAIJURxBRwCZAAAAAA==.',
Lo='Lodin:BAAALgAECgEJAQAAAA==.',
Lu='Luminå:BAABLgAECn8XAAIXAAcJghfeGACEAQAXAAcJghfeGACEAQAAAA==.',
Ly='Lylenn:BAAALgADCgkJDgAAAA==.',
Ma='Madora:BAAALgADCgQJBAAAAA==.Maibisan:BAABLgAECn8fAAIYAAgJiyPdAgDUAgAYAAgJiyPdAgDUAgAAAA==.Malificent:BAABLgAECn8YAAIWAAcJ5B3kEgANAgAWAAcJ5B3kEgANAgAAAA==.Malighn:BAABLgAECn8fAAINAAgJpwQwTAAbAQANAAgJpwQwTAAbAQAAAA==.Masseffex:BAAALgAECgQJBwAAAA==.',
Mc='Mcshooty:BAAALgADCgUJBQAAAA==.',
Me='Metashaman:BAAALgAECgcJCQAAAA==.',
Mo='Modi:BAAALgAECgEJAQAAAA==.Mookong:BAAALgADCgEJAQAAAA==.Moonsliver:BAAALgAECgEJAgAAAA==.Mordecâi:BAAALgADCgQJBQAAAA==.Morf:BAAALgAECgMJAwABLgAECggJFwAVAOYVAA==.Morganä:BAAALgAECgQJCQAAAA==.Morthrin:BAAALgAECgYJDQAAAA==.',
Mu='Muhrieyuh:BAAALgADCgQJBAAAAA==.',
My='Mystwolf:BAABLgAECn8lAAIDAAgJWhyXFABwAgADAAgJWhyXFABwAgAAAA==.',
Ne='Ned:BAAALgADCgkJCAABLgAECgQJBAAHAAAAAA==.',
Ni='Niccelndime:BAAALgAECgYJDAAAAA==.Nightski:BAABLgAECn8fAAIQAAgJDRa3GQCzAQAQAAgJDRa3GQCzAQAAAA==.Nikolatesla:BAAALgAECgUJBQAAAA==.Nizzari:BAABLgAECn8aAAIZAAgJQwaBMACCAQAZAAgJQwaBMACCAQAAAA==.',
No='Nothalyer:BAABLgAECn8jAAIVAAgJWQ7fCQB8AQAVAAgJWQ7fCQB8AQAAAA==.',
Of='Offline:BAAALgAECgkJDwABLgAECgkJFQADAOMaAA==.',
Oh='Ohms:BAABLgAECn8oAAIaAAgJOhs+GAAbAgAaAAgJOhs+GAAbAgAAAA==.',
Ol='Olaria:BAAALgADCgYJCQAAAA==.',
Or='Orwasitshrek:BAAALgAECgUJDgAAAA==.',
Pa='Palabop:BAAALgAECgYJCgAAAA==.Paladinii:BAAALgADCgIJAgAAAA==.',
Pl='Planec:BAAALgAECgYJBgAAAA==.',
Po='Polytots:BAABLgAECn8qAAMSAAkJABM3LgCrAQASAAkJABM3LgCrAQADAAgJxg9/JABFAQAAAA==.',
Pr='Proteus:BAAALgADCgMJAwAAAA==.',
Qi='Qiller:BAAALgAECgQJBAAAAA==.',
Qu='Quinne:BAAALgADCgEJAQABLgAECgEJAQAHAAAAAA==.',
Ra='Ranin:BAAALgAECgEJAQAAAA==.Razius:BAAALgAECgkJEgAAAA==.',
Ri='Riplordfire:BAAALgAECgEJAQAAAA==.',
Ro='Roadsign:BAAALgAECgYJDQAAAA==.Rottey:BAAALgAECgMJAwAAAA==.Roxette:BAAALgADCgcJBwAAAA==.',
Sa='Salvation:BAAALgAECgYJDwAAAA==.Sanctis:BAAALgAECgMJAwAAAA==.Santan:BAAALgADCgIJAgAAAA==.',
Sc='Scarecrow:BAAALgADCgUJBQAAAA==.',
Se='Sealgair:BAAALgAECgEJAQAAAA==.Senovourer:BAABLgAECn8eAAIYAAgJFCMOCwAqAwAYAAgJFCMOCwAqAwAAAA==.',
Sh='Shabamoo:BAABLgAECn8WAAIQAAgJPB2LBgCuAgAQAAgJPB2LBgCuAgAAAA==.Shakkes:BAAALgAECgEJAQAAAA==.Shasato:BAABLgAECn8ZAAIbAAgJkRQ8DQCzAQAbAAgJkRQ8DQCzAQAAAA==.Shelian:BAAALgAECgEJAQAAAA==.Shiranai:BAAALgADCgEJAQAAAA==.Shoosty:BAAALgADCgcJDAAAAA==.',
Si='Sicarii:BAAALgADCgcJCAAAAA==.Sizouze:BAAALgAECgUJCAAAAA==.',
Sk='Skeeter:BAAALgAECgYJBgAAAA==.Skyepic:BAACLgAFFH8RAAIcAAcJOhPCAQDuAQAcAAcJOhPCAQDuAQAuAAQKfyIAAxwACQlfIC4HAPkCABwACQlfIC4HAPkCAAEABAllEnTVAOAAAAAA.Skylight:BAAALgAECgEJAQAAAA==.',
Sn='Snugwalnut:BAACLgAFFH8KAAIDAAQJ8SDWBgB5AQADAAQJ8SDWBgB5AQAuAAQKfy0AAgMACAkII+cDAMcCAAMACAkII+cDAMcCAAAA.',
So='Soejoedi:BAABLgAECn8fAAICAAkJ8Bb6BgArAgACAAkJ8Bb6BgArAgAAAA==.',
St='Stitchzpls:BAAALgAECgUJCQAAAA==.',
Su='Sunhammer:BAAALgAECgEJAQAAAA==.Sunsworn:BAAALgAECgQJBwAAAA==.',
Sw='Sweetyboi:BAAALgAECgYJDgAAAA==.',
Ta='Tarhostamir:BAAALgAECgYJCQAAAA==.Tazz:BAAALgAECgQJDgAAAA==.',
Te='Tecnine:BAAALgADCgUJBQAAAA==.Teledar:BAAALgAECgQJCAAAAA==.',
Th='Thaysinga:BAAALgADCgQJBAAAAA==.Thelandlord:BAACLgAFFH8UAAIVAAYJTxUbAwDVAQAVAAYJTxUbAwDVAQAuAAQKfxwAAxUACAkOG9cMAGgCABUACAkOG9cMAGgCAB0AAwnJDpsvAJoAAAAA.Theshape:BAAALgADCgMJAwAAAA==.Thunderblast:BAAALgAECgYJDAAAAA==.Thuss:BAABLgAECn8WAAIYAAYJIxblKQA+AQAYAAYJIxblKQA+AQAAAA==.',
Ti='Titgunniz:BAAALgADCgYJBgAAAA==.',
Tu='Tugnutz:BAAALgAECgUJBgAAAA==.Tuk:BAAALgAECgMJAwAAAA==.',
Tw='Twirlywhirly:BAAALgADCgQJBAAAAA==.',
['Tè']='Tèmpos:BAAALgADCgcJBwAAAA==.',
Un='Unplug:BAAALgAECgQJDAAAAA==.',
Va='Vander:BAAALgAECgQJBAAAAA==.Vanidossa:BAAALgAECgYJBwAAAA==.Varygud:BAAALgADCgUJBgAAAA==.Vayper:BAABLgAECn8kAAIGAAgJLCB2AwCDAgAGAAgJLCB2AwCDAgAAAA==.',
Ve='Veins:BAAALgADCgQJDAAAAA==.Verdict:BAAALgAFFAEJAQAAAA==.',
Vo='Voklin:BAAALgAECgQJBAAAAA==.',
We='Weemsy:BAABLgAECn8fAAIJAAgJLSAoAwCkAgAJAAgJLSAoAwCkAgAAAA==.',
Wi='Wildfire:BAACLgAFFH8NAAIMAAQJjyNoAQCXAQAMAAQJjyNoAQCXAQAuAAQKfywAAgwACQmKJoQAAJADAAwACQmKJoQAAJADAAAA.Wildfirë:BAAALgAECgYJBgABLgAFFAQJDQAMAI8jAA==.Willthewise:BAAALgADCgIJAgAAAA==.',
Wo='Wolffei:BAAALgAECgEJAQAAAA==.Wolfhammer:BAAALgAECggJEAAAAA==.Wolflee:BAAALgAECgYJDwAAAA==.Wolfmend:BAAALgAECgUJCgAAAA==.',
Xa='Xamid:BAAALgAECgYJEAAAAA==.Xaxfen:BAACLgAFFH8OAAIOAAUJyxTqBAAoAQAOAAUJyxTqBAAoAQAuAAQKfxcAAg4ACAkgIdMJAHoCAA4ACAkgIdMJAHoCAAAA.',
['Xê']='Xêndâr:BAAALgADCgQJBAAAAA==.',
Za='Zappieboy:BAAALgAECgIJAgAAAA==.',
Zu='Zulgrimm:BAAALgADCgMJAwAAAA==.',
Zy='Zyfèr:BAAALgAECgQJDAAAAA==.',
['Zî']='Zîmìk:BAAALgADCgkJIAAAAA==.',
['Às']='Àsh:BAABLgAECn8cAAIFAAgJyx9aAwCwAgAFAAgJyx9aAwCwAgAAAA==.',
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

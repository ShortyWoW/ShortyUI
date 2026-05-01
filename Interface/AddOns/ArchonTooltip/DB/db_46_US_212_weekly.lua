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

local lookup = {'Paladin-Retribution','Druid-Balance','Mage-Frost','Priest-Discipline','Priest-Holy','Priest-Shadow','Paladin-Holy','Druid-Restoration','Unknown-Unknown','Druid-Guardian','DeathKnight-Blood','Warrior-Protection','DeathKnight-Unholy','DemonHunter-Devourer','DemonHunter-Havoc','Evoker-Preservation','Hunter-Marksmanship','Warlock-Destruction','Hunter-BeastMastery','Monk-Windwalker','Monk-Brewmaster','Monk-Mistweaver','Rogue-Subtlety','DeathKnight-Frost','Warrior-Arms',}
local provider = {region='US',realm='Terokkar',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abuna:BAABLgAECn8bAAIBAAcJlhJFQABJAQABAAcJlhJFQABJAQAAAA==.',
Ad='Adreni:BAAALgADCgUJBQAAAA==.',
Ae='Aelzia:BAAALgAECgEJAQAAAA==.Aestia:BAAALgADCggJCwAAAA==.',
Al='Alfarin:BAAALgAECgEJAQAAAA==.Aljern:BAAALgADCgEJAgAAAA==.Alpha:BAAALgAECgYJBwAAAA==.Alysra:BAAALgADCgUJBQABLgAFFAYJEgACAA8gAA==.',
Am='Ammogal:BAAALgADCgcJBwAAAA==.',
An='Andyson:BAAALgAECgMJBAAAAA==.Antandra:BAAALgAECgUJEgAAAA==.Anwen:BAABLgAECn8YAAIDAAgJ6RRlIgDgAQADAAgJ6RRlIgDgAQAAAA==.',
Ar='Arawen:BAAALgAECgQJBgABLgAECggJGAADAOkUAA==.',
Av='Aválánche:BAAALgADCgEJAQAAAA==.',
Ay='Ayanea:BAABLgAECn8dAAQEAAgJbiG3BQBaAgAEAAgJMCC3BQBaAgAFAAIJvCRkWwDGAAAGAAQJSw97KAC8AAAAAA==.Aysá:BAAALgADCgMJBQAAAA==.',
Ba='Baberaham:BAAALgAECgYJDAAAAA==.Baiford:BAABLgAECn8WAAMHAAcJgw7xSgBMAQAHAAcJgw7xSgBMAQABAAMJ8wvEgACrAAAAAA==.Baldie:BAAALgADCgEJAQAAAA==.Batteries:BAAALgADCgkJLwAAAA==.',
Be='Bearitto:BAABLgAECn8mAAIIAAgJkSAkBgC2AgAIAAgJkSAkBgC2AgAAAA==.',
Bi='Bigpony:BAAALgADCgYJCAAAAA==.',
Bl='Bloodrain:BAAALgADCgYJBgAAAA==.',
Bo='Bobsan:BAAALgAECgQJBAAAAA==.',
Br='Breyvarian:BAAALgADCgUJBQAAAA==.Broland:BAAALgAECgYJEQAAAA==.',
Bu='Burningvoker:BAAALgADCgYJBgAAAA==.',
Ca='Caitycat:BAABLgAECn8VAAIIAAcJihc8FADlAQAIAAcJihc8FADlAQAAAA==.Calliopê:BAAALgAECgUJDAAAAA==.Candycane:BAAALgADCgQJBAAAAA==.Casseopea:BAAALgADCgMJAwABLgAECgMJAwAJAAAAAA==.Catherinn:BAAALgAECgUJBQAAAA==.Cattlock:BAAALgAECgQJBgAAAA==.',
Ch='Chaltin:BAAALgAECgMJAwAAAA==.Chillhunt:BAAALgADCgIJAgAAAA==.',
Co='Coldhand:BAAALgAECgkJBgAAAA==.Colë:BAABLgAECn8YAAIKAAcJWhR9CABWAQAKAAcJWhR9CABWAQAAAA==.',
['Cæ']='Cærus:BAAALgAECgYJBgABLgAFFAYJDgAGADAVAA==.',
Da='Daedrina:BAAALgADCgMJAwAAAA==.Dalkrim:BAABLgAECn8bAAILAAcJdR09BwCtAQALAAcJdR09BwCtAQAAAA==.',
De='Debboi:BAAALgADCgUJBQAAAA==.Derrick:BAAALgAECgUJEAAAAA==.Desol:BAAALgADCgEJAQAAAA==.Destrya:BAABLgAECn8dAAIMAAgJ7R6xAgB2AgAMAAgJ7R6xAgB2AgAAAA==.',
Di='Dibbsette:BAABLgAECn8cAAMEAAcJBR0DGADdAQAEAAcJBR0DGADdAQAGAAYJUw2nGAA5AQAAAA==.',
Do='Douber:BAAALgADCgYJCAAAAA==.',
Ds='Dshiznit:BAAALgAECgEJAQABLgAECgUJDAAJAAAAAA==.',
Dw='Dwamli:BAAALgAECgMJCAAAAA==.',
Dy='Dynamitedave:BAAALgAECgQJBQABLgAECgUJCgAJAAAAAA==.',
['Dø']='Dømino:BAAALgAECgQJCAAAAA==.',
Eb='Ebolabeef:BAABLgAECn8cAAINAAgJoCSKBgC2AgANAAgJoCSKBgC2AgAAAA==.',
Ei='Eirlys:BAAALgAECgYJBgAAAA==.',
El='Elky:BAAALgADCgkJHAABLgAECgEJAQAJAAAAAA==.Elìyon:BAABLgAECn8YAAMOAAgJEgjXYQB8AQAOAAgJEgjXYQB8AQAPAAEJoQErfQAiAAAAAA==.',
Es='Espyvon:BAAALgADCgQJBAAAAA==.',
Et='Eternalay:BAAALgADCgIJAgAAAA==.Eternshot:BAAALgADCgEJAQAAAA==.Eternsword:BAAALgADCgYJBgAAAA==.',
Ev='Evelanara:BAAALgADCgUJBQAAAA==.Evelinnia:BAAALgADCgMJAwAAAA==.Evilmurkii:BAAALgAECgEJBAABLgAECgYJEAAJAAAAAA==.Evilssoul:BAAALgAECgQJBAAAAA==.',
Fe='Feltsmer:BAAALgADCgYJCQAAAA==.Fenira:BAAALgADCgUJBQAAAA==.',
Fo='Foscora:BAAALgAECgEJAQAAAA==.',
Fr='Frushy:BAAALgADCgcJBwAAAA==.',
Fu='Fugu:BAAALgADCggJEQAAAA==.',
Ga='Gannicûs:BAAALgAECgEJAQAAAA==.Garlando:BAAALgAECgEJAQAAAA==.',
Go='Goatmommy:BAAALgAECgQJBgAAAA==.Goph:BAAALgADCgMJBQAAAA==.Goremnar:BAAALgADCgYJBgAAAA==.',
Gr='Grimmfury:BAAALgAECgMJAwAAAA==.Grolgor:BAAALgADCgQJBAAAAA==.Grïffïth:BAACLgAFFH8aAAMBAAYJgB5eAwC/AQABAAUJoBxeAwC/AQAHAAEJ1wC3HABGAAAuAAQKfyoAAwEACQmHIRgPABUDAAEACQmHIRgPABUDAAcABglLD2RHAFoBAAAA.',
Gu='Gunjir:BAAALgAECgMJBwAAAA==.',
Gw='Gwyneira:BAAALgAECgQJBAABLgAECgYJBgAJAAAAAA==.',
Ha='Haranbush:BAAALgADCgYJBgAAAA==.',
Hi='Hipidipi:BAAALgADCgUJBQAAAA==.',
Hu='Hucklebeary:BAAALgAECgIJAgAAAA==.Hugcubs:BAAALgADCgUJBQAAAA==.',
['Hí']='Hítgirl:BAAALgAECgQJCAAAAA==.',
Ic='Icylilith:BAAALgADCgYJCQAAAA==.',
Im='Imugi:BAABLgAECn8bAAIQAAcJPQgJDgAgAQAQAAcJPQgJDgAgAQAAAA==.',
Ir='Irithia:BAAALgADCgEJAQAAAA==.',
Is='Issavanos:BAAALgAECgYJEAAAAA==.',
Ja='Jazmane:BAAALgADCgYJBgAAAA==.',
Je='Jenhoney:BAAALgAECgMJAwAAAA==.Jes:BAAALgADCgEJAQAAAA==.',
Jo='Josh:BAAALgAECgYJCQABLgAFFAYJCwARAOcTAA==.',
Ka='Kaliya:BAAALgAECgQJCQAAAA==.Kashar:BAAALgADCgMJAwAAAA==.',
Ke='Kevdog:BAABLgAECn8bAAISAAcJVREWBgBeAQASAAcJVREWBgBeAQAAAA==.',
Kh='Khelemarth:BAAALgAECgEJAwAAAA==.',
Ki='Kire:BAAALgAECgYJDwAAAA==.Kirohan:BAAALgADCgcJCQAAAA==.',
Ko='Kobellr:BAAALgADCgUJBQAAAA==.Koldov:BAAALgAECgEJAQAAAA==.Kosmik:BAAALgADCgcJCwAAAA==.',
Kr='Krimzin:BAAALgADCgEJAQABLgAFFAMJBQATAKcbAA==.',
Ku='Kuiu:BAAALgADCgEJAQAAAA==.Kulnurayne:BAAALgADCgcJDAAAAA==.Kuna:BAAALgAECgIJBAAAAA==.Kushta:BAABLgAECn8YAAIBAAgJix0OGQDTAgABAAgJix0OGQDTAgAAAA==.',
La='Lackjaw:BAABLgAECn8aAAISAAgJTg72EQC8AQASAAgJTg72EQC8AQAAAA==.Landrick:BAABLgAECn8sAAILAAgJyxrABgC5AQALAAgJyxrABgC5AQAAAA==.Lanejack:BAAALgADCgQJBwAAAA==.Larissah:BAEALgADCgUJAgABLgAECgkJEwAJAAAAAA==.Lava:BAAALgAECgcJDgAAAA==.',
Lg='Lgang:BAABLgAECn8VAAIPAAYJ5QqBPAANAQAPAAYJ5QqBPAANAQAAAA==.',
Li='Lifeblõõm:BAAALgAECgYJEwAAAA==.Lilium:BAAALgAECgYJBgAAAA==.',
Ll='Llau:BAAALgAECgcJEgAAAA==.',
Lo='Losia:BAAALgAECgMJAwAAAA==.Loveinvain:BAAALgAECgMJAgAAAA==.',
Lu='Lunabun:BAAALgADCgcJEwAAAA==.Luniana:BAAALgADCgEJAQAAAA==.',
Ma='Malorn:BAABLgAECn8fAAQUAAgJkxU6CgDTAQAUAAgJkxU6CgDTAQAVAAYJ7Q7dQwAzAQAWAAEJJg5YQwA4AAAAAA==.Manaaddict:BAAALgAECgYJBgAAAA==.',
Mi='Midníght:BAAALgAECgEJAQAAAA==.',
Mo='Moltencarl:BAAALgAECgEJAgAAAA==.',
My='Myrna:BAAALgAECgMJAwAAAA==.',
Ni='Niege:BAAALgAECgQJBAAAAA==.Niiso:BAAALgADCgkJEQAAAA==.Nivina:BAAALgADCgcJBwAAAA==.',
Nk='Nkagnyto:BAAALgAECgUJDgAAAA==.Nkanue:BAAALgADCgIJAgABLgAECgUJDgAJAAAAAA==.',
No='Noonstalker:BAAALgAECgUJCQAAAA==.',
Or='Oric:BAAALgADCgMJAwABLgAECgUJDAAJAAAAAA==.Orintaar:BAAALgADCgMJAwAAAA==.Ormac:BAAALgAECgYJDwAAAA==.Ororoe:BAABLgAECn8iAAMVAAgJ9xprFABrAgAVAAgJJhprFABrAgAUAAcJ9RAFEwBZAQAAAA==.',
Pa='Palapo:BAAALgAECgMJAwAAAA==.Panrocktar:BAAALgADCgEJAQAAAA==.Paudrig:BAAALgAECgQJBQAAAA==.',
Pe='Perfect:BAAALgAECgQJBgAAAA==.',
Ph='Phagetouched:BAAALgAECgUJAwAAAA==.Phaydre:BAAALgAECgYJEQABLgAFFAQJCQAQAF4TAA==.',
Pi='Picklenick:BAABLgAECn8aAAIXAAcJ/Q9gDwB3AQAXAAcJ/Q9gDwB3AQAAAA==.',
Po='Ponytree:BAAALgAECgcJDwAAAA==.Porani:BAAALgADCggJFAAAAA==.',
Pr='Prismo:BAAALgAECgcJDAAAAA==.',
Pw='Pwnbuggy:BAABLgAECn8cAAINAAgJohc6FgAIAgANAAgJohc6FgAIAgAAAA==.',
Qa='Qartoga:BAAALgADCgEJAQABLgAECgIJBAAJAAAAAA==.',
Ql='Qlue:BAAALgADCgcJBwAAAA==.',
Ra='Rabin:BAAALgADCgIJAgAAAA==.Racistgreen:BAAALgAECgIJAgAAAA==.Rafikibull:BAAALgAECgIJBQAAAA==.Raindrop:BAABLgAECn8dAAIIAAgJHBfDFgDMAQAIAAgJHBfDFgDMAQAAAA==.Ramah:BAAALgAECgMJAwAAAA==.Ramen:BAAALgADCgEJAQAAAA==.',
Re='Reignstorm:BAABLgAECn8bAAIYAAcJigsJBwAJAQAYAAcJigsJBwAJAQAAAA==.Reivax:BAABLgAECn8ZAAITAAgJ1A4eLgD6AQATAAgJ1A4eLgD6AQAAAA==.Rethelm:BAAALgAECgUJEgAAAA==.Retreats:BAAALgADCgUJBQAAAA==.Retsella:BAAALgADCgkJHAAAAA==.Reveum:BAABLgAECn8vAAMZAAgJLwo8EAAJAQAMAAgJYQnpDwAhAQAZAAYJWws8EAAJAQAAAA==.Revân:BAAALgADCgMJAwAAAA==.',
Rh='Rhaegár:BAAALgAECgQJCAAAAA==.',
Ro='Rogl:BAACLgAFFH8KAAIIAAQJ4CPuBQCjAQAIAAQJ4CPuBQCjAQAuAAQKfx0AAggABwkbIFAcAFoCAAgABwkbIFAcAFoCAAAA.Rosgard:BAAALgADCggJCAAAAA==.',
Ru='Ruhll:BAAALgADCgcJCQAAAA==.Ruminate:BAAALgADCgQJBAABLgAECgEJAQAJAAAAAA==.Rustychi:BAAALgAECgMJAwAAAA==.',
['Rá']='Rámpapi:BAAALgAECgQJBgAAAA==.',
Sa='Sammaile:BAAALgAECgYJDgAAAA==.Sarahsmith:BAAALgAECgUJDAAAAA==.Saucypeach:BAAALgAECgYJDQAAAA==.',
Sc='Scamander:BAAALgAECggJEwAAAA==.Scarmouse:BAAALgAECgEJAQAAAA==.',
Se='Seifer:BAAALgADCgkJJQAAAA==.Semnickmonk:BAAALgAECgMJBAAAAA==.Senjosaku:BAAALgAECgYJCQABLgAFFAIJBQADAGcaAA==.Serigo:BAAALgAECgMJCAAAAA==.Serral:BAAALgAFFAEJAQAAAA==.',
Sk='Skayley:BAAALgADCgUJBQAAAA==.',
Sm='Smoochy:BAAALgAECgEJAQAAAA==.',
So='Solysz:BAAALgAECgYJEwAAAA==.Sophietheone:BAAALgADCgIJAgAAAA==.Soß:BAACLgAFFH8JAAIDAAQJfhnRJAAhAQADAAQJfhnRJAAhAQAuAAQKfx8AAgMABwnNIZ9SAEACAAMABwnNIZ9SAEACAAAA.',
Sp='Spongébob:BAAALgAECgIJAgAAAA==.Spork:BAAALgADCgYJEQABLgAECgEJAQAJAAAAAA==.',
St='Stimcheck:BAAALgADCgcJBwABLgADCggJCAAJAAAAAA==.Stmary:BAAALgADCgQJBAAAAA==.',
Su='Subzéro:BAAALgAECgUJDwAAAA==.',
Sw='Sweetwhisper:BAAALgAECgYJEQAAAA==.',
Sy='Sylitae:BAAALgADCgYJDwAAAA==.',
['Så']='Såbëtha:BAAALgADCgMJBQAAAA==.',
Ta='Tazzen:BAAALgAECgQJBQAAAA==.',
Te='Teletern:BAAALgADCgMJBQAAAA==.Tempeststørm:BAAALgAECgQJBAAAAA==.',
Th='Thaunelian:BAAALgADCggJCAABLgAECggJHwAUAJMVAA==.Thoristain:BAAALgAECgUJDAAAAA==.Thrain:BAABLgAECn8cAAIBAAgJoQvNMAB/AQABAAgJoQvNMAB/AQAAAA==.Threefive:BAAALgAECgQJBQAAAA==.',
To='Tokhan:BAABLgAECn8YAAITAAcJ1RttFgDfAQATAAcJ1RttFgDfAQAAAA==.Torvar:BAAALgADCgEJAgAAAA==.Totemíc:BAAALgAECgEJAQAAAA==.',
Ve='Velarion:BAAALgAECgEJAQAAAA==.Veryundead:BAABLgAECn8kAAISAAgJbA/ABgBLAQASAAgJbA/ABgBLAQAAAA==.',
Vo='Void:BAAALgAECgQJDgAAAA==.Voidmara:BAAALgAECgEJAgAAAA==.Voíd:BAAALgAECgEJAQAAAA==.',
Vr='Vrylykos:BAAALgAECgQJBAAAAA==.',
Wa='Waddlez:BAAALgAECgEJAQAAAA==.Wardawg:BAAALgADCgEJAQABLgAECggJHQAEAG4hAA==.Wargrylls:BAAALgADCgcJBwAAAA==.',
We='Wendrin:BAAALgADCggJCAAAAA==.',
Wh='White:BAAALgADCgkJEQAAAA==.',
Xa='Xanarine:BAABLgAECn8VAAMHAAYJhBQrRABnAQAHAAYJhBQrRABnAQABAAIJtQdCIQFbAAAAAA==.',
Xe='Xeeva:BAAALgAECgUJDgAAAA==.',
Xu='Xuralxia:BAAALgAECgEJBQAAAA==.',
Zi='Zink:BAAALgADCgEJAgAAAA==.Ziyad:BAABLgAECn8WAAQCAAcJeBNnEwBsAQACAAcJARFnEwBsAQAKAAMJwxMMIQCVAAAIAAEJiAEf6gAaAAAAAA==.',
Zy='Zyn:BAAALgADCggJFQAAAA==.',
['Zè']='Zèró:BAAALgAECgUJDAAAAA==.',
['Ðü']='Ðüß:BAAALgADCgIJAgABLgADCgkJEQAJAAAAAA==.',
['Ön']='Öna:BAABLgAECn8jAAITAAgJ6BIzJACKAQATAAgJ6BIzJACKAQAAAA==.',
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

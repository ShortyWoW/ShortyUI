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

local lookup = {'Paladin-Retribution','Unknown-Unknown','Druid-Balance','Mage-Frost','Priest-Discipline','Priest-Holy','Priest-Shadow','DeathKnight-Unholy','DeathKnight-Frost','DeathKnight-Blood','Paladin-Holy','Druid-Restoration','Druid-Guardian','Warrior-Protection','DemonHunter-Devourer','DemonHunter-Havoc','Hunter-BeastMastery','Evoker-Preservation','Hunter-Marksmanship','Warlock-Destruction','Warrior-Arms','Monk-Mistweaver','Monk-Windwalker','Monk-Brewmaster','Rogue-Subtlety',}
local provider = {region='US',realm='Terokkar',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abuna:BAABLgAECn8dAAIBAAgJAhNEPgCLAQABAAgJAhNEPgCLAQAAAA==.',
Ad='Adreni:BAAALgADCgUJBQAAAA==.',
Ae='Aelzia:BAAALgAECgEJAgAAAA==.Aennivan:BAAALgADCgcJBwABLgAECgMJBAACAAAAAA==.Aestia:BAAALgADCggJCwAAAA==.',
Al='Alfarin:BAAALgAECgEJAQAAAA==.Aljern:BAAALgADCgEJAgAAAA==.Alpha:BAAALgAECgYJBwAAAA==.Alysra:BAAALgADCgUJBQABLgAFFAYJFwADAF0hAA==.',
Am='Ammogal:BAAALgAECgEJAQAAAA==.',
An='Andyson:BAAALgAECgMJBQAAAA==.Antandra:BAAALgAECgYJEwAAAA==.Anwen:BAABLgAECn8ZAAIEAAgJMRUsMADgAQAEAAgJMRUsMADgAQAAAA==.',
Ar='Arawen:BAAALgAECgQJBgABLgAECggJGQAEADEVAA==.',
Av='Avadrea:BAAALgADCgEJAQAAAA==.Aválánche:BAAALgADCgEJAQAAAA==.',
Ay='Ayanea:BAABLgAECn8hAAQFAAgJJCMfBgCWAgAFAAgJ5yEfBgCWAgAGAAIJvCRrWwDGAAAHAAQJTw86NQC3AAAAAA==.Aysá:BAAALgADCgMJBQAAAA==.',
Ba='Baberaham:BAABLgAECn8VAAQIAAcJ7QKyhADXAAAIAAcJ7QKyhADXAAAJAAMJcQFTFgA4AAAKAAEJhAQLOwAoAAAAAA==.Baiford:BAABLgAECn8ZAAMLAAgJXg/zSgBMAQALAAgJXg/zSgBMAQABAAMJ8gvepwCjAAAAAA==.Baldie:BAAALgADCgEJAQAAAA==.Batteries:BAAALgAECgEJAQAAAA==.',
Be='Bearitto:BAABLgAECn8uAAIMAAgJsiBUCQC0AgAMAAgJsiBUCQC0AgAAAA==.',
Bi='Bigpony:BAAALgADCgYJCAAAAA==.',
Bl='Bloodrain:BAAALgADCgYJBgAAAA==.',
Bo='Bobsan:BAAALgAECgQJBAAAAA==.',
Br='Breyvarian:BAAALgADCgUJBQAAAA==.Broland:BAAALgAECgYJEQAAAA==.',
Bu='Burningvoker:BAAALgADCgYJBgAAAA==.',
Ca='Caitycat:BAABLgAECn8XAAIMAAgJdxUeGgDzAQAMAAgJdxUeGgDzAQAAAA==.Calliopê:BAAALgAECgYJDQAAAA==.Candycane:BAAALgADCgQJBAAAAA==.Casseopea:BAAALgADCgYJCQABLgAECgMJBgACAAAAAA==.Catherinn:BAAALgAECgUJBQAAAA==.Cattlock:BAAALgAECgQJCgAAAA==.',
Ch='Chaltin:BAAALgAECgMJAwAAAA==.Chillhunt:BAAALgADCgIJAgAAAA==.',
Co='Coldhand:BAAALgAECgkJBgAAAA==.Colë:BAABLgAECn8aAAINAAgJFxRcCQCOAQANAAgJFxRcCQCOAQAAAA==.',
['Cæ']='Cærus:BAAALgAECgYJBgABLgAFFAYJDwAHAD4VAA==.',
Da='Daedrina:BAAALgADCgMJAwAAAA==.Dalkrim:BAABLgAECn8dAAIKAAgJJhw8CQDsAQAKAAgJJhw8CQDsAQAAAA==.',
De='Deadblanchy:BAAALgADCgIJAgAAAA==.Debboi:BAAALgADCgUJBQAAAA==.Denzel:BAAALgAECgYJBQAAAA==.Derrick:BAAALgAECgYJEQAAAA==.Desol:BAAALgADCgEJAQAAAA==.Destrya:BAABLgAECn8hAAIOAAgJMSDcAwCBAgAOAAgJMSDcAwCBAgAAAA==.',
Di='Dibbsette:BAABLgAECn8eAAMFAAgJvxwDGADdAQAFAAgJvxwDGADdAQAHAAYJQQ3cIQAxAQAAAA==.',
Do='Douber:BAAALgADCgYJCAAAAA==.',
Ds='Dshiznit:BAAALgAECgEJAQABLgAECgYJDQACAAAAAA==.',
Dw='Dwamli:BAAALgAECgMJCgAAAA==.',
Dy='Dynamitedave:BAAALgAECgQJCAABLgAECgYJCwACAAAAAA==.',
['Dø']='Dømino:BAAALgAECgQJDAAAAA==.',
Eb='Ebolabeef:BAABLgAECn8gAAIIAAgJPCU0CADZAgAIAAgJPCU0CADZAgAAAA==.',
Ei='Eirlys:BAAALgAECgYJEAAAAA==.',
El='Elky:BAAALgADCgkJHAABLgAECgMJAwACAAAAAA==.Elìyon:BAABLgAECn8gAAMPAAgJJgwDPABHAQAPAAgJJgwDPABHAQAQAAEJoQEsfQAiAAAAAA==.',
Es='Espyvon:BAAALgADCgQJBAAAAA==.',
Et='Eternalay:BAAALgAECgEJAgAAAA==.Eternshot:BAAALgADCgEJAQAAAA==.Eternsword:BAAALgADCgYJBgAAAA==.',
Ev='Evelanara:BAAALgADCgUJBQAAAA==.Evelinnia:BAAALgADCgMJAwAAAA==.Evilmurkii:BAAALgAECgEJBgABLgAECgYJEAACAAAAAA==.Evilssoul:BAAALgAECgQJBAAAAA==.',
Fe='Feltsmer:BAAALgADCgYJCQAAAA==.Fenira:BAAALgADCgUJBQAAAA==.Ferguz:BAABLgAECn8YAAIRAAcJ2htHIwDKAQARAAcJ2htHIwDKAQAAAA==.',
Fo='Foscora:BAAALgAECgEJAQAAAA==.',
Fr='Frushy:BAAALgADCgcJBwAAAA==.',
Fu='Fugu:BAAALgADCggJEQAAAA==.',
Ga='Gannicûs:BAAALgAECgEJAQAAAA==.Garlando:BAAALgAECgEJAQAAAA==.',
Go='Goatmommy:BAAALgAECgQJCgAAAA==.Goph:BAAALgADCgMJBQAAAA==.Goremnar:BAAALgADCgYJBgAAAA==.',
Gr='Grimmfury:BAAALgAECgMJBgAAAA==.Grimmtide:BAAALgADCgYJBgAAAA==.Grolgor:BAAALgADCgQJBAAAAA==.Grïffïth:BAACLgAFFH8cAAMBAAcJPxpfAwC/AQABAAYJ9xdfAwC/AQALAAEJ2AC7HABGAAAuAAQKfysAAwEACQmNIRcPABUDAAEACQmNIRcPABUDAAsABglLD2ZHAFoBAAAA.',
Gu='Gunjir:BAAALgAECgMJCQAAAA==.',
Gw='Gwyneira:BAAALgAECgYJCgABLgAECgYJEAACAAAAAA==.',
Ha='Haranbush:BAAALgADCgYJBgAAAA==.',
Hi='Hipidipi:BAAALgADCgUJBQAAAA==.',
Ho='Honeysuckles:BAAALgADCggJCAAAAA==.',
Hu='Hucklebeary:BAAALgAECgQJBgAAAA==.Hugcubs:BAAALgADCgUJBQAAAA==.',
['Hí']='Hítgirl:BAAALgAECgQJCAAAAA==.',
Ic='Icylilith:BAAALgADCgYJCQAAAA==.',
Im='Imugi:BAABLgAECn8dAAISAAgJcgfIEAAwAQASAAgJcgfIEAAwAQAAAA==.',
Ir='Irithia:BAAALgADCgEJAQAAAA==.',
Is='Ishamael:BAAALgADCgcJBwABLgAECgYJEQACAAAAAA==.Issavanos:BAAALgAECgYJEAAAAA==.',
Ja='Jazmane:BAAALgADCgYJBgAAAA==.',
Je='Jenhoney:BAAALgAECgMJBgAAAA==.Jes:BAAALgADCgEJAQAAAA==.Jessdarklord:BAAALgAECgQJAgAAAA==.',
Jo='Josh:BAAALgAECgYJCQABLgAFFAYJDAATAOcTAA==.',
Ka='Kaliya:BAAALgAECgQJCQAAAA==.Kashar:BAAALgADCgMJAwAAAA==.',
Ke='Kevdog:BAABLgAECn8dAAIUAAgJMRBpBgCJAQAUAAgJMRBpBgCJAQAAAA==.',
Kh='Khelemarth:BAAALgAECgEJBAAAAA==.',
Ki='Kire:BAABLgAECn8ZAAMOAAgJ1R/nAwCAAgAOAAgJ1R/nAwCAAgAVAAEJ0Q7KQAA3AAAAAA==.Kirohan:BAAALgADCgcJCQAAAA==.',
Ko='Kobellr:BAAALgADCgUJBQAAAA==.Koldov:BAAALgAECgEJAQAAAA==.Kosmik:BAAALgADCgcJCwAAAA==.',
Kr='Krimzin:BAAALgAECgEJAQABLgAFFAQJCQARAD8bAA==.',
Ku='Kuiu:BAAALgADCgEJAQAAAA==.Kulnurayne:BAAALgADCgcJDAAAAA==.Kuna:BAAALgAECgIJBAAAAA==.Kushta:BAABLgAECn8YAAIBAAgJix0LGQDTAgABAAgJix0LGQDTAgAAAA==.',
La='Lackjaw:BAABLgAECn8aAAIUAAgJUA72EQC8AQAUAAgJUA72EQC8AQAAAA==.Landrick:BAACLgAFFH8FAAIKAAIJng1UGACAAAAKAAIJnQ1UGACAAAAuAAQKfzEAAgoACQlIGoYFAE8CAAoACQlIGoYFAE8CAAAA.Lanejack:BAAALgADCgQJBwAAAA==.Larissah:BAEALgADCgUJAgABLgAECgkJEwACAAAAAA==.Lava:BAAALgAECggJDwAAAA==.',
Lg='Lgang:BAABLgAECn8VAAIQAAYJ5gqEPAANAQAQAAYJ5gqEPAANAQAAAA==.',
Li='Lifeblõõm:BAABLgAECn8UAAMMAAcJUSH0DAB+AgAMAAcJUSH0DAB+AgADAAIJjA5WVgA2AAAAAA==.Lilium:BAAALgAECgYJBgAAAA==.',
Ll='Llau:BAABLgAECn8aAAIWAAgJVhdGDAAlAgAWAAgJVhdGDAAlAgAAAA==.',
Lo='Losia:BAAALgAECgMJBgAAAA==.Loveinvain:BAAALgAECgMJAgAAAA==.',
Lu='Lunabun:BAAALgADCgcJEwAAAA==.',
['Lû']='Lûffy:BAAALgAECgkJCQAAAA==.',
Ma='Malorn:BAABLgAECn8gAAQXAAgJlBW9DgDOAQAXAAgJlBW9DgDOAQAYAAYJ7Q7YQwAzAQAWAAIJaAx/RwBgAAAAAA==.Manaaddict:BAAALgAECgYJBgAAAA==.',
Mi='Midníght:BAAALgAECgEJAQABLgAECgMJAwACAAAAAA==.',
Mo='Moltencarl:BAAALgAECgEJAgAAAA==.',
My='Myrna:BAAALgAECgMJAwAAAA==.',
Ni='Niege:BAAALgAECgYJCgAAAA==.Niiso:BAAALgAECgMJAwAAAA==.Nivina:BAAALgADCgcJBwAAAA==.',
Nk='Nkagnyto:BAAALgAECgUJEQAAAA==.Nkanue:BAAALgADCgIJAgABLgAECgUJEQACAAAAAA==.',
No='Noonstalker:BAAALgAECgUJCgAAAA==.',
Or='Oric:BAAALgADCgMJAwABLgAECgYJDQACAAAAAA==.Orintaar:BAAALgADCgMJAwAAAA==.Ormac:BAAALgAECgYJEgAAAA==.Ororoe:BAABLgAECn8kAAMYAAgJ9xprFABrAgAYAAgJzRprFABrAgAXAAcJ9RARGgBTAQAAAA==.Orphancalf:BAAALgAECgIJAgAAAA==.',
Pa='Palapo:BAAALgAECgMJBAAAAA==.Panrocktar:BAAALgADCgEJAQAAAA==.Paudrig:BAAALgAECgYJCwAAAA==.',
Pe='Perfect:BAAALgAECgQJBgAAAA==.',
Ph='Phagetouched:BAAALgAECgUJAwAAAA==.Phaydre:BAAALgAECgYJEgABLgAFFAUJCgASANgPAA==.',
Pi='Picklenick:BAABLgAECn8cAAIZAAgJbBBwDwCuAQAZAAgJbBBwDwCuAQAAAA==.',
Po='Ponytree:BAAALgAECgcJEAAAAA==.Porani:BAAALgAECgEJAQAAAA==.',
Pr='Prismo:BAAALgAECgcJDgAAAA==.',
Pw='Pwnbuggy:BAABLgAECn8dAAIIAAgJpBeuIwD1AQAIAAgJpBeuIwD1AQAAAA==.',
Qa='Qartoga:BAAALgADCgEJAQABLgAECgIJBAACAAAAAA==.',
Ql='Qlue:BAAALgADCgcJBwAAAA==.',
Ra='Rabellious:BAAALgADCggJCAAAAA==.Rabin:BAAALgADCgIJAgAAAA==.Racistgreen:BAAALgAECgIJAgAAAA==.Rafikibull:BAAALgAECgIJBQAAAA==.Raindrop:BAABLgAECn8dAAIMAAgJHRdaIQC7AQAMAAgJHRdaIQC7AQAAAA==.Ramah:BAAALgAECgMJBgAAAA==.Ramen:BAAALgADCgEJAQAAAA==.',
Re='Reignstorm:BAABLgAECn8dAAIJAAgJzAuwBwAvAQAJAAgJzAuwBwAvAQAAAA==.Reivax:BAABLgAECn8hAAIRAAgJ3xASKgCoAQARAAgJ3xASKgCoAQAAAA==.Rethelm:BAAALgAECgYJEwAAAA==.Retreats:BAAALgADCgUJBQAAAA==.Retsella:BAAALgADCgkJHQAAAA==.Reveum:BAABLgAECn8vAAMVAAgJPgpwFwD8AAAOAAgJbQlSFQAcAQAVAAYJXwtwFwD8AAAAAA==.Revân:BAAALgADCgMJAwAAAA==.',
Rh='Rhaegár:BAAALgAECgQJCQAAAA==.',
Ro='Robyerto:BAAALgADCgMJAwAAAA==.Rogl:BAACLgAFFH8MAAIMAAUJRCEWBQDwAQAMAAUJRCEWBQDwAQAuAAQKfx0AAgwABwkbIE8cAFoCAAwABwkbIE8cAFoCAAAA.Rosgard:BAAALgADCggJCAAAAA==.',
Ru='Ruhll:BAAALgADCgcJCQAAAA==.Ruminate:BAAALgADCgYJCgABLgAECgMJAwACAAAAAA==.Rustychi:BAAALgAECgYJCQAAAA==.',
['Rá']='Rámpapi:BAAALgAECgQJCgAAAA==.',
Sa='Sammaile:BAAALgAECgYJEQAAAA==.Sarahsmith:BAAALgAECgYJDQAAAA==.Saucypeach:BAAALgAECgYJDQAAAA==.',
Sc='Scamander:BAAALgAECggJEwAAAA==.Scarmouse:BAAALgAECgEJAQAAAA==.',
Se='Seifer:BAAALgADCgkJJQAAAA==.Semnickmonk:BAAALgAECgMJBAAAAA==.Senjosaku:BAAALgAECgcJDwABLgAFFAMJCQAEAEEbAA==.Serigo:BAAALgAECgUJDgAAAA==.Serral:BAAALgAFFAEJAQAAAA==.',
Sk='Skayley:BAAALgADCgUJBQAAAA==.',
Sm='Smoochy:BAAALgAECgEJAQAAAA==.',
So='Solysz:BAAALgAECgYJEwAAAA==.Sophietheone:BAAALgADCgIJAgAAAA==.Soten:BAAALgADCgcJBwABLgAECgMJBgACAAAAAA==.Soß:BAACLgAFFH8KAAIEAAQJBBrXJAAhAQAEAAQJBBrXJAAhAQAuAAQKfx8AAgQABwnPIZVSAEACAAQABwnPIZVSAEACAAAA.',
Sp='Spongébob:BAAALgAECgIJAgAAAA==.Spork:BAAALgAECgMJAwAAAA==.',
St='Stimcheck:BAAALgADCgcJBwABLgADCggJCAACAAAAAA==.Stmary:BAAALgADCgQJBAAAAA==.Størmzmisery:BAAALgADCgUJBQAAAA==.',
Su='Subzéro:BAABLgAECn8UAAIEAAYJRAkmgAARAQAEAAYJRAkmgAARAQAAAA==.',
Sw='Sweetwhisper:BAAALgAECgYJEQAAAA==.',
Sy='Sylitae:BAAALgADCgcJFgAAAA==.',
['Så']='Såbëtha:BAAALgADCgMJBQAAAA==.',
Ta='Tazzen:BAAALgAECgQJBQAAAA==.',
Te='Teletern:BAAALgADCgMJBQAAAA==.Tempeststørm:BAAALgAECgUJBwAAAA==.',
Th='Thaunelian:BAAALgADCggJCAABLgAECggJIAAXAJQVAA==.Thoristain:BAAALgAECgYJDQAAAA==.Thorshman:BAAALgADCgcJBwABLgAECgYJDQACAAAAAA==.Thrain:BAABLgAECn8dAAIBAAgJvwveRQB0AQABAAgJvwveRQB0AQAAAA==.Threefive:BAAALgAECgQJBQAAAA==.',
To='Torvar:BAAALgADCgEJAgAAAA==.Totemíc:BAAALgAECgQJBQAAAA==.',
Tp='Tpops:BAAALgADCgMJAwAAAA==.',
Ve='Velarion:BAAALgAECgEJAQAAAA==.Veryundead:BAABLgAECn8kAAIUAAgJaQ+xCABPAQAUAAgJaQ+xCABPAQAAAA==.',
Vo='Void:BAAALgAECgUJEwAAAA==.Voidmara:BAAALgAECgEJAgAAAA==.Voíd:BAAALgAECgEJAQAAAA==.',
Vr='Vrylykos:BAAALgAECgYJCgAAAA==.',
Wa='Waddlez:BAAALgAECgEJAQAAAA==.Wardawg:BAAALgADCgEJAQABLgAECggJIQAFACQjAA==.Wargrylls:BAAALgADCgcJBwAAAA==.',
We='Wendrin:BAAALgAECgYJBgAAAA==.',
Wh='White:BAAALgAECgQJBQAAAA==.',
Xa='Xanarine:BAABLgAECn8VAAMLAAYJhRQtRABnAQALAAYJhRQtRABnAQABAAIJtQdFIQFbAAAAAA==.',
Xe='Xeeva:BAAALgAECgUJEQAAAA==.',
Xu='Xuralxia:BAAALgAECgEJBgAAAA==.',
Zi='Zink:BAAALgAECgEJAQAAAA==.Ziyad:BAABLgAECn8WAAQDAAcJexPgGgBfAQADAAcJBBHgGgBfAQANAAMJwxMKIQCVAAAMAAEJiAEm6gAaAAAAAA==.',
Zy='Zyn:BAAALgADCggJFQAAAA==.',
['Zè']='Zèró:BAAALgAECgYJDwAAAA==.',
['Ðü']='Ðüß:BAAALgADCgIJAgABLgAECgMJAwACAAAAAA==.',
['Ön']='Öna:BAABLgAECn8jAAIRAAgJ6hLnNwDOAQARAAgJ6hLnNwDOAQAAAA==.',
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

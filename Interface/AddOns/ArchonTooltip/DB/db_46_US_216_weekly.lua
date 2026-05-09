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

local lookup = {'Warrior-Arms','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Paladin-Protection','Paladin-Retribution','Monk-Mistweaver','Warlock-Affliction','Warlock-Demonology','Mage-Frost','Hunter-Survival','Unknown-Unknown','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Unholy','Paladin-Holy','Druid-Restoration','Shaman-Restoration','DemonHunter-Devourer','Priest-Holy','Priest-Discipline','Priest-Shadow','Warlock-Destruction','Warrior-Fury','Warrior-Protection','Monk-Brewmaster','DeathKnight-Blood','Shaman-Enhancement','DeathKnight-Frost','DemonHunter-Vengeance','Rogue-Subtlety',}
local provider = {region='US',realm='TheUnderbog',name='US',type='weekly',zone=46,date='2026-05-08',data={Ac='Acinovanth:BAAALgAECgEJAQAAAA==.Acousticjeff:BAAALgAECgYJBgAAAA==.',
Ad='Adwill:BAABLgAECn8ZAAIBAAcJcB93BgD8AQABAAcJcB93BgD8AQAAAA==.',
Ae='Aelvoker:BAACLgAFFH8SAAQCAAUJ9BkLBAAJAQACAAQJPhULBAAJAQADAAQJERKoIQDkAAAEAAQJ7gZ5EwCQAAAuAAQKfxcABAIACQlFH08HAHcCAAIABgkkI08HAHcCAAQABwmdEYQaALcBAAMAAgndGslKAKkAAAAA.',
Ai='Aindra:BAAALgAECggJEAAAAA==.Airen:BAAALgAECgQJBQAAAA==.',
An='Antidead:BAABLgAECn8gAAMFAAgJOR5zBQCfAgAFAAgJOR5zBQCfAgAGAAgJ1xPLLwC9AQAAAA==.',
Ap='Apachaler:BAABLgAECn8aAAIHAAYJTB8lEgDTAQAHAAYJTB8lEgDTAQAAAA==.',
Ar='Arathael:BAAALgADCgIJAgAAAA==.Ardyce:BAAALgADCgIJAgAAAA==.Arrae:BAAALgAECgUJAwAAAA==.Arreuws:BAAALgAECgQJBAAAAA==.',
As='Asiansmoliv:BAACLgAFFH8LAAMIAAMJ4BrWAgC3AAAIAAIJ9BnWAgC3AAAJAAIJ9htdMgCuAAAuAAQKfycAAwgACQmJI7oBAMYCAAgACAmiI7oBAMYCAAkABQm6H4clANQBAAAA.',
Ba='Babymager:BAABLgAECn8dAAIKAAYJSQ2pfAAYAQAKAAYJSQ2pfAAYAQAAAA==.Babyshamz:BAAALgADCggJCAAAAA==.',
Be='Beartwige:BAAALgADCgYJBgAAAA==.Belladonnà:BAAALgADCgQJBAAAAA==.Betsy:BAAALgAECgQJBAAAAA==.',
Bi='Bigpopapump:BAACLgAFFH8MAAILAAMJnhodAwDLAAALAAMJnhodAwDLAAAuAAQKfzMAAgsACAlEJn4BAP4CAAsACAlEJn4BAP4CAAAA.Bishop:BAAALgADCgMJAwAAAA==.',
Bl='Blackgarden:BAAALgAECgUJBwAAAA==.Bloodydak:BAEALgAECgcJBwABLgAECgYJDwAMAAAAAA==.',
Bo='Bombasharna:BAAALgADCgMJBQAAAA==.Bonkzx:BAAALgADCgMJAwAAAA==.Booze:BAAALgAECggJDgAAAA==.',
Br='Brigne:BAAALgADCgYJCwAAAA==.',
Bu='Buddeez:BAACLgAFFH8TAAIKAAUJ8B3VFQCJAQAKAAUJ8B3VFQCJAQAuAAQKfysAAgoACQk/JVAKAHEDAAoACQk/JVAKAHEDAAAA.Built:BAABLgAECn8dAAQLAAgJ8CA/DAAJAgALAAcJ/yA/DAAJAgANAAMJTBi7fwDoAAAOAAEJ2hhkgQBBAAAAAA==.',
Ca='Cabbage:BAAALgADCgEJAQAAAA==.',
Ce='Cenwen:BAACLgAFFH8HAAIKAAMJjQvnSwDxAAAKAAMJjQvnSwDxAAAuAAQKfx8AAgoABwlzHMdfABwCAAoABwlzHMdfABwCAAAA.',
Ch='Chaos:BAABLgAECn8nAAILAAkJAiD1AQDiAgALAAkJAiD1AQDiAgAAAA==.Chonk:BAAALgADCgYJCQAAAA==.Chugginjizz:BAAALgAECgEJAQABLgAFFAYJGAAPALAVAA==.',
Cl='Clawreece:BAAALgAECgMJBAAAAA==.',
Co='Conta:BAAALgADCgUJBQAAAA==.',
Cr='Cryingtears:BAABLgAECn8iAAMQAAgJgw0MLwAcAQAQAAgJgw0MLwAcAQAGAAcJqQa6dgD/AAAAAA==.',
Cu='Cuchicu:BAABLgAECn8vAAIRAAkJPBrwCwCLAgARAAkJPBrwCwCLAgAAAA==.',
Da='Dakkonix:BAEALgAECgYJDwAAAA==.Dakkonixx:BAEALgAECgUJBQABLgAECgYJDwAMAAAAAA==.Damagexx:BAAALgAECgEJAQAAAA==.Darkaged:BAAALgADCgYJBgAAAA==.',
De='Demonasa:BAAALgADCgIJAgAAAA==.Desim:BAABLgAECn8WAAIPAAcJsx5+MwBpAgAPAAcJsx5+MwBpAgAAAA==.Dextt:BAABLgAECn8dAAISAAcJLCIrDgCpAgASAAcJLCIrDgCpAgAAAA==.Dez:BAABLgAECn8XAAIQAAgJfRBgHQCcAQAQAAgJfRBgHQCcAQAAAA==.',
Dk='Dkamp:BAAALgADCgQJDAAAAA==.',
Dm='Dmoney:BAAALgAECgYJBgAAAA==.',
Do='Dondiablo:BAAALgAECgYJDQAAAA==.Doylock:BAAALgADCgkJCQAAAA==.',
Dr='Dragnaballs:BAAALgAECgcJEgABLgAFFAgJIQAKAGMWAA==.Drehd:BAACLgAFFH8KAAISAAMJvCQREQA6AQASAAMJvCQREQA6AQAuAAQKfy0AAhIACAnWJGECAD0DABIACAnWJGECAD0DAAAA.Drewcifer:BAABLgAECn8iAAITAAkJhR5+FgDPAgATAAkJhR5+FgDPAgABLgAECgkJIgATAIUeAA==.Drewwar:BAAALgAECgEJAQABLgAECgkJIgATAIUeAA==.Dripps:BAAALgAECgYJBgAAAA==.',
Du='Dumper:BAAALgADCgEJAQAAAA==.Dumps:BAAALgAECgMJAwAAAA==.',
['Dó']='Dóom:BAAALgAECgUJCQAAAA==.',
['Dü']='Düsk:BAAALgADCgUJBQABLgAECgEJAgAMAAAAAA==.',
Eg='Egoon:BAAALgAECgMJAwAAAA==.',
El='Elmerfud:BAAALgAECgYJBwAAAA==.',
En='Enrèk:BAAALgADCgYJBgAAAA==.',
Fa='Falafel:BAACLgAFFH8NAAIPAAUJBR8wGgBvAQAPAAUJBR8wGgBvAQAuAAQKfyUAAg8ACQmcIekSAAoDAA8ACQmcIekSAAoDAAAA.',
Fi='Fidely:BAAALgADCgEJAQAAAA==.',
Fo='Fomo:BAAALgADCgYJBgAAAA==.Fornax:BAAALgAECgQJBwABLgAECgYJFgAKADMOAA==.Fotmtrash:BAACLgAFFH8IAAMUAAQJbRIDEADTAAAUAAMJvBQDEADTAAAVAAEJfwtYJgBPAAAuAAQKfyYABBQACAlUIvAHAMwCABQACAkaIvAHAMwCABUABQmIHk4RAMIBABYAAgknCVxaAE4AAAAA.Foxxydots:BAABLgAECn8mAAIJAAgJSRYpLQCvAQAJAAgJSRYpLQCvAQAAAA==.',
Fr='Frostitoot:BAABLgAECn8WAAIKAAYJMw7pbwAxAQAKAAYJMw7pbwAxAQAAAA==.',
Ga='Galbsadi:BAABLgAECn8WAAMJAAgJ9Q5aYAAQAQAJAAYJDRBaYAAQAQAXAAMJOAwTHQBjAAAAAA==.Garrius:BAAALgADCgQJBAAAAA==.',
Ge='Gelfdar:BAAALgAECgEJAQAAAA==.Gethendriel:BAAALgAECgQJCQAAAA==.',
Gl='Glaia:BAAALgADCgYJDQAAAA==.',
Go='Goel:BAAALgAECgEJAgAAAA==.',
Gr='Graf:BAABLgAECn8dAAQYAAgJ6h7cHABnAgAYAAcJkR/cHABnAgABAAYJPRgFGwAZAQAZAAQJQRM4LwDJAAAAAA==.Grimzorath:BAAALgAECgYJBgAAAA==.Grox:BAABLgAECn8UAAIYAAYJmg+mTgBsAQAYAAYJmg+mTgBsAQAAAA==.Grudge:BAAALgADCgMJBQAAAA==.',
Ha='Hackensack:BAAALgAECgcJDwAAAA==.Hamtaro:BAAALgAECgEJAQAAAA==.Hawthorne:BAABLgAECn8aAAIHAAcJ7x3WFAAgAgAHAAcJ7x3WFAAgAgAAAA==.',
Hi='Hiyabusa:BAAALgAECgYJEgAAAA==.',
Ho='Hollowboi:BAABLgAECn8pAAIaAAgJ2x6ZBgBtAgAaAAgJ2x6ZBgBtAgAAAA==.Holygraf:BAAALgAECgcJDgAAAA==.',
Ia='Iamyama:BAAALgAECgUJCQAAAA==.',
Io='Ionna:BAAALgADCgcJBwAAAA==.',
Jd='Jdvance:BAAALgAECgYJBgAAAA==.',
Jh='Jhouska:BAAALgAECgcJEAAAAA==.',
Jo='Jormunngandr:BAACLgAFFH8YAAMPAAYJsBW7DQCgAQAPAAUJsBW7DQCgAQAbAAEJAAAwFQBGAAAuAAQKfx8AAg8ACQm9IKgRABIDAA8ACQm9IKgRABIDAAAA.',
Ju='Judgynomnom:BAACLgAFFH8GAAIQAAQJ8xZsDwA7AQAQAAQJ8xZsDwA7AQAuAAQKfxwAAhAACAloJtwJANQCABAACAloJtwJANQCAAAA.',
Jy='Jyggles:BAAALgAECgYJCgAAAA==.',
Ki='Kirax:BAAALgADCgEJAQAAAA==.',
Ko='Konataizumi:BAAALgADCgcJCwAAAA==.',
Kr='Kruhks:BAAALgAECgYJCAABLgAFFAMJCgASALwkAA==.',
Ks='Kshot:BAABLgAECn8vAAILAAkJ8x72AgCzAgALAAkJ8x72AgCzAgAAAA==.',
La='Lagdalen:BAABLgAECn8VAAIUAAYJQRtbEQDaAQAUAAYJQRtbEQDaAQAAAA==.Lanachan:BAABLgAECn8gAAIYAAcJ2w2YLQAZAQAYAAcJ2w2YLQAZAQAAAA==.',
Ld='Ldn:BAABLgAECn8nAAIKAAgJMRAgQACnAQAKAAgJMRAgQACnAQAAAA==.',
Le='Lep:BAAALgADCgcJDQAAAA==.',
Li='Likai:BAAALgADCgUJBQAAAA==.Lisa:BAAALgADCgcJAQAAAA==.Liz:BAABLgAECn8fAAINAAgJUwaxQwBCAQANAAgJUwaxQwBCAQAAAA==.',
Ly='Lylieth:BAABLgAECn8rAAIJAAkJ0BGpHAAEAgAJAAkJ0BGpHAAEAgAAAA==.Lyndyn:BAAALgADCgIJAgAAAA==.',
Ma='Mather:BAAALgAECgEJAgAAAA==.Mayzel:BAAALgAECgMJBAAAAA==.',
Mi='Microsqueeze:BAAALgADCgkJCQAAAA==.',
Mo='Mogera:BAAALgADCgMJBQAAAA==.',
Ni='Ninluv:BAAALgAECgQJDgAAAA==.',
Ny='Nyancat:BAAALgADCgkJCgAAAA==.',
Ol='Olaho:BAAALgADCgYJBgAAAA==.',
Om='Omenz:BAAALgADCgIJAgAAAA==.',
Oo='Oojni:BAAALgADCgYJBgAAAA==.',
Pa='Pazzman:BAAALgADCgYJBwAAAA==.',
Pe='Perc:BAAALgAECgQJBAAAAA==.',
Ph='Pharhar:BAABLgAECn8iAAMQAAgJdhuRHAAxAgAQAAgJdhuRHAAxAgAGAAMJfRFylQDEAAAAAA==.',
Po='Poppachàdson:BAABLgAECn8dAAIcAAcJ+CDSCABPAgAcAAcJ+CDSCABPAgABLgAFFAMJBgAcABoVAA==.Poppadadson:BAACLgAFFH8GAAIcAAMJGhXeBAD+AAAcAAMJGhXeBAD+AAAuAAQKfxwAAhwABwmBH4kGAI0CABwABwmBH4kGAI0CAAAA.Poppadotson:BAAALgAECgMJAwABLgAFFAMJBgAcABoVAA==.',
Pu='Puscifer:BAAALgAECgkJBAAAAA==.',
Qu='Quarrior:BAAALgADCgEJAQABLgAECgEJAgAMAAAAAA==.Quellazaire:BAAALgADCgcJDAAAAA==.',
Ra='Ravister:BAAALgAECgUJBQABLgAFFAUJFAAWAGgjAA==.',
Re='Relic:BAACLgAFFH8SAAMdAAUJyRUBAgBIAQAdAAQJyRUBAgBIAQAbAAIJxQvuHwA4AAAuAAQKfx0AAh0ACQnjHJMCAIwCAB0ACQnjHJMCAIwCAAAA.Renk:BAABLgAECn8iAAIPAAcJ1SV5DgCOAgAPAAcJ1SV5DgCOAgAAAA==.Renka:BAAALgADCggJCAAAAA==.',
Ro='Ronald:BAABLgAECn8UAAIGAAYJZRrelgBPAQAGAAYJZRrelgBPAQAAAA==.Roykevious:BAAALgAECgEJAwAAAA==.',
Sa='Saeyl:BAAALgAECgYJDAABLgAECgkJFwAVAJsJAA==.Sammie:BAEALgAECgUJBgABLgAECgYJDwAMAAAAAA==.Savant:BAAALgADCgEJAQAAAA==.Sayl:BAABLgAECn8XAAMVAAkJmwlALgAsAQAVAAYJNQpALgAsAQAWAAUJMwjJMADPAAAAAA==.',
Sc='Scallywinkle:BAAALgAECgcJEAAAAA==.Scrap:BAABLgAECn8aAAMJAAkJ4hqEPgATAgAJAAgJcBqEPgATAgAXAAQJeRTgKwAQAQAAAA==.',
Se='Senova:BAAALgAECgIJAgAAAA==.',
Sh='Shadowghoul:BAAALgAECgcJCAAAAA==.Shadowydern:BAABLgAECn8jAAMWAAgJySEkBACsAgAWAAgJySEkBACsAgAUAAEJ/RBkfwAzAAAAAA==.Shamewow:BAACLgAFFH8RAAISAAUJghh6CwBwAQASAAUJghh6CwBwAQAuAAQKfysAAhIACQlhGksZAEwCABIACQlhGksZAEwCAAAA.',
Si='Sicknnasty:BAACLgAFFH8PAAIbAAUJjRLNBwARAQAbAAUJjRLNBwARAQAuAAQKfy8AAxsABwmDIr0KAGwCABsABwmDIr0KAGwCAA8ABwkRFO8+AIABAAAA.',
Sl='Slayerz:BAAALgAECgYJBgAAAA==.',
Sn='Snattch:BAAALgADCgEJAQAAAA==.Snookismalls:BAAALgAECgcJEAAAAA==.',
So='Solarian:BAAALgADCgMJAwAAAA==.Solitary:BAAALgAECgcJEgAAAA==.',
Sp='Speed:BAAALgAECgYJCwAAAA==.Spinach:BAAALgAECgMJAQAAAA==.',
St='Starshopping:BAABLgAECn8UAAITAAgJmiFjFQDWAgATAAgJmiFjFQDWAgABLgAECgkJJwALAAIgAA==.',
Su='Sunari:BAAALgADCgQJBAAAAA==.',
Ta='Taewryn:BAAALgADCgYJBgABLgAFFAcJIAAaAOchAA==.Talrip:BAABLgAECn8dAAIeAAgJcx7YBgAgAgAeAAgJcx7YBgAgAgAAAA==.',
Th='Thicctrix:BAAALgADCgcJDAAAAA==.Thundon:BAAALgADCgcJCQAAAA==.',
To='Toatem:BAAALgAECgUJBQAAAA==.Toro:BAACLgAFFH8VAAIYAAUJByJnAwCWAQAYAAUJByJnAwCWAQAuAAQKfysAAhgACQl3JGcFAFADABgACQl3JGcFAFADAAAA.',
Tr='Traitor:BAAALgADCgEJAQAAAA==.Trappynomnom:BAAALgADCggJDQAAAA==.Tree:BAABLgAFFH8MAAIRAAQJAiTfCACsAQARAAQJAiTfCACsAQAAAA==.Treegrundler:BAAALgAECgYJEwAAAA==.Treeus:BAAALgAECgYJCQAAAA==.Trixulous:BAAALgADCgkJJQAAAA==.',
Tw='Twiigee:BAABLgAECn8XAAIaAAYJWSAMIAABAgAaAAYJWSAMIAABAgAAAA==.',
Tz='Tzungxie:BAABLgAECn8nAAIfAAkJWB3PAgC9AgAfAAkJWB3PAgC9AgAAAA==.',
Un='Unholylord:BAACLgAFFH8UAAIWAAUJaCMvBQCMAQAWAAUJaCMvBQCMAQAuAAQKfyAAAhYACQk2I8oEAEcDABYACQk2I8oEAEcDAAAA.',
Va='Vae:BAAALgAECgMJAwAAAA==.Vagbadge:BAAALgADCgkJCQABLgAFFAUJFAAWAGgjAA==.Varroww:BAAALgAECgYJEQAAAA==.',
Vo='Vosxo:BAAALgAECgEJAQAAAA==.',
['Ví']='Vígo:BAABLgAECn8ZAAIBAAYJ7QjuGwDWAAABAAYJ7QjuGwDWAAAAAA==.',
Wa='Wado:BAAALgAECgEJAQAAAA==.',
We='Wellíngton:BAAALgAECgEJAQAAAA==.',
Wh='Whack:BAAALgADCgYJBgAAAA==.',
Wi='Wicke:BAAALgADCgQJBAABLgAECgEJAQAMAAAAAA==.',
Wo='Wolfthetree:BAAALgAECgUJCAAAAA==.',
Wy='Wystarr:BAAALgADCgIJAgAAAA==.',
Xa='Xamael:BAAALgADCgMJAwAAAA==.',
Xe='Xerkz:BAAALgAECgEJAQAAAA==.',
Ys='Ystarian:BAABLgAECn88AAQCAAkJrRuIAQBwAgACAAkJrRuIAQBwAgADAAgJBhQUHQDeAQAEAAEJGwHsTgAgAAAAAA==.',
Za='Zaptik:BAAALgAECgEJAQAAAA==.',
['Ël']='Ëlëmëntary:BAAALgAECgcJBgAAAA==.',
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

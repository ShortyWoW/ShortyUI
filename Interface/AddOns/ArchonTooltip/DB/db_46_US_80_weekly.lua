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

local lookup = {'Mage-Frost','Mage-Arcane','Evoker-Augmentation','Evoker-Devastation','Warlock-Demonology','Warlock-Destruction','Shaman-Enhancement','Shaman-Elemental','Shaman-Restoration','Mage-Fire','Unknown-Unknown','Druid-Restoration','Druid-Balance','Hunter-BeastMastery','DemonHunter-Devourer','Evoker-Preservation','DemonHunter-Vengeance','Priest-Discipline','DemonHunter-Havoc','DeathKnight-Unholy','Hunter-Marksmanship','Paladin-Retribution','Priest-Shadow','Monk-Mistweaver','Paladin-Holy','DeathKnight-Blood','Warlock-Affliction','Monk-Windwalker',}
local provider = {region='US',realm='Dunemaul',name='US',type='weekly',zone=46,date='2026-04-24',data={Aa='Aaletaa:BAAALgADCgUJBQABLgAFFAMJCgABAHsWAA==.',
Al='Alalange:BAAALgADCgQJBAAAAA==.Allice:BAABLgAECn8WAAMCAAcJ3xtiAwA8AgACAAcJixtiAwA8AgABAAQJmQyLQAC+AAAAAA==.Alterion:BAAALgAECgEJAgAAAA==.Altimusprime:BAAALgAECgYJBwAAAA==.',
An='Antitww:BAAALgADCgkJCQAAAA==.Anxious:BAAALgADCgUJBQAAAA==.',
Au='Augnyxia:BAABLgAECn8bAAMDAAcJRxCiJACYAQADAAcJRxCiJACYAQAEAAIJ8w/1NABsAAAAAA==.Augtism:BAABLgAECn8UAAMFAAYJNSToJwByAgAFAAYJNSToJwByAgAGAAEJAADFXQBVAAAAAA==.',
Av='Avengedfoldz:BAAALgAECgMJBAAAAA==.Avengedmunk:BAAALgADCgUJBQAAAA==.Avengedx:BAAALgAECgMJBAAAAA==.Avengeseven:BAAALgADCgYJBgAAAA==.',
Ay='Aylaa:BAAALgADCgMJAwAAAA==.',
Ba='Balsamicvinn:BAAALgAECgMJAwAAAA==.Bamfp:BAAALgADCgQJBAAAAA==.Bandobras:BAAALgAECgQJBwAAAA==.Bangtwinkdh:BAAALgAECgQJBwABLgAFFAYJEwADABIjAA==.',
Be='Belfdelphine:BAAALgAECgYJCwAAAA==.Bersh:BAABLgAECn8WAAQHAAgJ7xhNBwB4AgAHAAgJ7xhNBwB4AgAIAAYJJBEjSAAnAQAJAAEJAQiOngAyAAAAAA==.',
Bi='Bigstankyy:BAAALgADCgQJCAAAAA==.',
Bl='Blarn:BAAALgAECgQJBAAAAA==.Bloodjury:BAAALgAECgYJEAAAAA==.Bloom:BAAALgADCgYJBgAAAA==.Blossom:BAAALgAECgcJCwAAAA==.Bluespirit:BAAALgADCgEJAQAAAA==.',
Bo='Boonktown:BAABLgAECn8UAAIKAAcJtwn6BAB9AQAKAAcJtwn6BAB9AQAAAA==.Booschlock:BAAALgADCgMJAwAAAA==.',
Br='Brambles:BAAALgAECgIJAgAAAA==.Bruceleela:BAAALgADCggJCAABLgAECgcJCwALAAAAAA==.Brunarr:BAAALgAECgQJDwAAAA==.',
Bu='Bushetti:BAABLgAECn8YAAMMAAcJkRUKEwAzAQAMAAcJkRUKEwAzAQANAAIJghdGcQBbAAAAAA==.',
Ca='Candlemass:BAAALgAECgQJBQAAAA==.Canelor:BAAALgADCgEJAQAAAA==.Casperface:BAABLgAECn8ZAAMIAAgJsBEhJQDoAQAIAAgJsBEhJQDoAQAJAAMJPBnXHACtAAAAAA==.Catawampus:BAAALgADCgQJBAAAAA==.Cazisham:BAAALgAECgYJCgAAAA==.',
Ce='Cevianne:BAABLgAECn8ZAAIOAAcJURQrOADNAQAOAAcJURQrOADNAQAAAA==.',
Ch='Chama:BAAALgADCgEJAQAAAA==.Chaoticsaint:BAAALgAECggJDwAAAA==.Chronoblade:BAAALgAECgMJBAAAAA==.',
Co='Coal:BAABLgAECn8WAAIPAAYJ/yP1JQBvAgAPAAYJ/yP1JQBvAgAAAA==.Coalesce:BAAALgADCgQJBAABLgAECgYJFgAPAP8jAA==.Coltonater:BAABLgAECn8eAAIBAAgJ4BaWSgBXAgABAAgJ4BaWSgBXAgAAAA==.Corlieb:BAAALgAECgQJBAAAAA==.',
Cu='Cuh:BAAALgAECgcJBwAAAA==.Curlyfrys:BAAALgADCgQJBAAAAA==.',
['Cá']='Cáséy:BAABLgAECn8XAAIBAAgJKhlePACGAgABAAgJKhlePACGAgAAAA==.',
Da='Dampening:BAAALgAECgMJAwAAAA==.Danbi:BAABLgAECn8cAAIQAAgJkRbKAQAeAgAQAAgJkRbKAQAeAgAAAA==.',
De='Deathdylan:BAAALgAFFAEJAQAAAA==.Deathra:BAAALgADCgYJBgAAAA==.Deathseer:BAAALgAECgcJCwAAAA==.Deathshaq:BAAALgADCggJFwAAAA==.Demi:BAAALgADCgYJBgAAAA==.Demítríus:BAAALgADCgYJDQAAAA==.',
Do='Dourwolf:BAAALgADCgQJBAAAAA==.',
Dr='Dragman:BAAALgADCgYJBgAAAA==.Draugr:BAAALgADCgUJBQAAAA==.Dravyn:BAAALgAECgUJCwAAAA==.Drfiredumper:BAABLgAECn8cAAIBAAgJmhxFNQCeAgABAAgJmhxFNQCeAgAAAA==.Druqz:BAABLgAECn8VAAIBAAgJUQZ9IABTAQABAAgJUQZ9IABTAQAAAA==.Drævn:BAAALgAECgYJEQAAAA==.',
Du='Ducky:BAAALgADCgEJAQAAAA==.Dum:BAACLgAFFH8JAAMPAAQJfhfaFwARAQAPAAMJqRnaFwARAQARAAIJOgtxAQCOAAAuAAQKfx0AAg8ABwn9IhshAIoCAA8ABwn9IhshAIoCAAAA.',
Dw='Dwimbear:BAAALgADCgEJAQAAAA==.Dwimhoof:BAAALgADCgcJCAAAAA==.',
El='Eldin:BAABLgAECn8XAAISAAgJ6x74DwA/AgASAAgJ6x74DwA/AgAAAA==.Elunadorei:BAAALgAECgMJBAAAAA==.',
Em='Emancipation:BAAALgAECgIJAgAAAA==.',
En='Enchantress:BAABLgAECn8XAAMBAAgJJQpHFwCKAQABAAgJJQpHFwCKAQACAAIJOgZSGQBNAAAAAA==.Enro:BAABLgAECn8aAAMTAAgJnxUDEgBMAgATAAgJnxUDEgBMAgAPAAQJqgdotQCdAAAAAA==.',
Er='Erovia:BAAALgAECgcJDgAAAA==.',
Es='Esclipse:BAAALgAECgEJAQAAAA==.',
Et='Etc:BAAALgADCgIJAgAAAA==.',
Fa='Farruq:BAAALgADCgIJAgAAAA==.',
Fe='Felony:BAAALgAECgcJEwAAAA==.',
Fl='Flavah:BAABLgAECn8UAAINAAcJ2x2OHAAdAgANAAcJ2x2OHAAdAgAAAA==.Flavahflav:BAAALgAECgYJCgAAAA==.Floormatt:BAABLgAECn8fAAIUAAkJIhO9VwDqAQAUAAkJIxO9VwDqAQAAAA==.Flower:BAAALgAECgcJEQAAAA==.',
Fo='Foodex:BAAALgAECgYJDgAAAA==.Fourleaf:BAABLgAECn8bAAIVAAgJ6xWlHwAlAgAVAAgJ6xWlHwAlAgAAAA==.',
Fr='Frydayx:BAAALgADCgQJBAAAAA==.',
Fu='Furral:BAAALgAECgUJBwAAAA==.',
Ga='Gaeth:BAABLgAECn8eAAIMAAgJaBEAQgCZAQAMAAgJaBEAQgCZAQAAAA==.',
Gh='Gheal:BAAALgAECgUJBQAAAA==.',
Go='Goopdawg:BAAALgAECgQJCQAAAA==.Goregon:BAAALgAECgYJBwAAAA==.',
Gr='Grimthebrave:BAAALgAECgEJAQAAAA==.Grimthecruel:BAAALgAECgYJCwAAAA==.Grungle:BAAALgADCgIJAgAAAA==.',
Ha='Handlebar:BAAALgAECgEJAQABLgAECgcJCwALAAAAAA==.Hannsollo:BAAALgADCgEJAQAAAA==.',
He='Heavenfall:BAAALgADCgMJAwAAAA==.Hellspawn:BAAALgADCgUJBQAAAA==.',
Ho='Holycowherd:BAAALgAECgUJCwAAAA==.',
Hy='Hyournmaru:BAAALgADCgkJCwAAAA==.',
['Hâ']='Hâmburger:BAAALgADCgQJAwAAAA==.',
Ia='Iamapally:BAAALgAECgEJAQAAAA==.',
In='Incarcerated:BAAALgADCgQJBAAAAA==.Infêstus:BAAALgAECgQJBAAAAA==.',
Ir='Iridessa:BAAALgAECgYJCwAAAA==.',
Is='Ishpoo:BAABLgAECn8YAAIWAAcJKwuOJAAWAQAWAAcJKwuOJAAWAQAAAA==.',
Ja='Jaellen:BAAALgAECgQJBgABLgAECggJHAABAJocAA==.Janasong:BAAALgAECgMJBAAAAA==.',
Je='Jelqer:BAABLgAECn8VAAMEAAYJsCCQEgC4AQAEAAYJsCCQEgC4AQADAAUJZBQLMABFAQAAAA==.Jennybunbun:BAAALgADCgcJBwAAAA==.',
Ji='Jimmycooks:BAAALgADCgMJAwAAAA==.',
Jl='Jlaworz:BAABLgAECn8bAAIMAAgJEB9sAgCZAgAMAAgJEB9sAgCZAgAAAA==.',
Jo='Job:BAACLgAFFH8KAAIPAAMJZiPuCAAnAQAPAAMJZiPuCAAnAQAuAAQKfyQAAw8ABwlvJLIGAAwCAA8ABwlvJLIGAAwCABMABgnFIM0jAJ4BAAAA.',
Ju='Juanweasley:BAAALgAECgEJAQAAAA==.Judoriel:BAAALgAECgMJAwAAAA==.Junkyard:BAAALgAECgQJBgAAAA==.',
Ka='Kahsindre:BAAALgAECgcJDgAAAA==.Kaimin:BAABLgAECn8VAAIUAAcJMRreRQAjAgAUAAcJMRreRQAjAgAAAA==.Karthas:BAAALgAECgEJAQAAAA==.',
Ke='Kellenved:BAAALgADCgEJAQABLgAECgcJAQALAAAAAA==.Kennypowers:BAAALgADCgcJCgAAAA==.Kezeshi:BAABLgAECn8YAAMSAAYJwxd8BQCzAQASAAYJwxd8BQCzAQAXAAMJFAO6VQBqAAAAAA==.',
Kh='Khaidralulz:BAABLgAECn8bAAIJAAcJkQ23RQBrAQAJAAcJkQ23RQBrAQAAAA==.Khonsu:BAAALgAECgEJAQAAAA==.',
Ki='Kiba:BAAALgAECgUJCwAAAA==.Kiliko:BAAALgADCgEJAQAAAA==.Killershammy:BAAALgAECgMJAwAAAA==.',
Kn='Knubboi:BAAALgADCgcJBwAAAA==.',
Ko='Koy:BAAALgADCgIJAwAAAA==.',
Kr='Kraegen:BAAALgAECgUJDAAAAA==.',
Ku='Kushiea:BAAALgADCgIJAgAAAA==.',
Ky='Kyofu:BAABLgAECn8dAAIYAAgJzh4OAgBuAgAYAAgJzh4OAgBuAgAAAA==.',
La='Larethiana:BAABLgAECn8UAAMMAAgJ6RSeTABxAQAMAAcJjBWeTABxAQANAAYJ9Rb6NABqAQAAAA==.',
Le='Leafmochi:BAAALgAECgYJBwAAAA==.Lennytwotoes:BAAALgAECgYJBQAAAA==.Leorick:BAAALgADCgMJAwAAAA==.Lexibelle:BAABLgAECn8UAAMZAAYJXQMSagDSAAAZAAYJXQMSagDSAAAWAAQJRQFyIQFbAAAAAA==.',
Li='Lightbright:BAABLgAECn8VAAIWAAgJjCSUBwBaAwAWAAgJjCSUBwBaAwAAAA==.Lilbeefcake:BAAALgAECgMJAwAAAA==.Lildab:BAAALgADCgcJFQAAAA==.Linnasha:BAABLgAECn8bAAIMAAgJCRWbNQDSAQAMAAgJCRWbNQDSAQAAAA==.',
Lo='Lornzap:BAAALgAECggJEAAAAA==.Lostwanderer:BAAALgAECgEJAgAAAA==.',
Ma='Magoo:BAAALgAECgEJAQAAAA==.Magtharas:BAAALgAECgYJDAAAAA==.Magzul:BAAALgADCggJCAAAAA==.Maki:BAAALgAECgUJCgAAAA==.Malacoda:BAABLgAECn8eAAITAAcJjhYhGwDoAQATAAcJjhYhGwDoAQAAAA==.Marble:BAAALgAECgMJAwAAAA==.Marshboa:BAAALgAECgUJBQAAAA==.Marymo:BAAALgADCgUJBQAAAA==.',
Me='Meddicare:BAAALgADCgUJBQAAAA==.',
Mi='Mindra:BAABLgAECn8YAAIOAAYJViNZBwD0AQAOAAYJViNZBwD0AQAAAA==.Minymoney:BAAALgADCgcJBwAAAA==.Miridian:BAAALgADCgYJBgAAAA==.Mitsuri:BAAALgAECggJDQAAAA==.',
Mo='Moatie:BAAALgADCgUJBQAAAA==.Moogician:BAAALgAECgEJAQABLgAECgUJCQALAAAAAA==.Moolasses:BAAALgAECgEJAgAAAA==.Moonsïnd:BAABLgAECn8ZAAIMAAgJigVTaAAaAQAMAAgJigVTaAAaAQAAAA==.Mooradin:BAAALgADCgQJAwAAAA==.Morgrin:BAAALgAECgMJAwAAAA==.Morguen:BAAALgAECgYJCwAAAA==.',
Mu='Mustachiopaw:BAAALgAECgcJEwAAAA==.',
My='Mydira:BAAALgAECgMJAwAAAA==.',
['Mò']='Mòomòo:BAAALgAECgEJAQAAAA==.',
Na='Nalthexon:BAAALgAECgYJBgABLgAECgcJHwAYAIUMAA==.Navysis:BAAALgADCggJCAAAAA==.Nazra:BAAALgAECgEJAQAAAA==.',
Ne='Negativeone:BAAALgADCgYJAgAAAA==.Neverender:BAAALgAECgEJAQAAAA==.Nexxus:BAAALgADCgcJDAAAAA==.Nezan:BAAALgADCgQJBAAAAA==.Nezin:BAAALgADCgUJBQABLgAECggJFQAZAKUeAA==.',
Ni='Niavanith:BAAALgADCgkJCgAAAA==.Nike:BAAALgAECgEJAQAAAA==.Nitwp:BAABLgAECn8aAAIEAAgJZRtQBgCQAgAEAAgJZRtQBgCQAgAAAA==.Nizo:BAAALgAECgYJDgAAAA==.',
No='Novastrike:BAABLgAECn8bAAMJAAcJ7BcNDQBtAQAJAAcJ7BcNDQBtAQAIAAYJBw1XSQAiAQAAAA==.',
Ny='Nyrif:BAABLgAECn8XAAIaAAgJ2RUxFQC/AQAaAAgJ2RUxFQC/AQAAAA==.',
Oj='Ojoon:BAAALgADCgEJAQAAAA==.',
Om='Omnisllash:BAAALgAECgMJAwAAAA==.',
Or='Orisana:BAABLgAECn8oAAMVAAkJwBrPDADfAgAVAAkJwBrPDADfAgAOAAIJrQ3xMQB/AAAAAA==.',
Pa='Pallamb:BAAALgADCgYJBwAAAA==.Palleberry:BAAALgADCgEJAQAAAA==.Panzerfaust:BAAALgADCgQJBAAAAA==.',
Pe='Penjamin:BAAALgADCgEJAQAAAA==.Petal:BAAALgAFFAQJBAAAAA==.',
Ph='Phyter:BAAALgADCgQJBgAAAA==.',
Pi='Pillin:BAAALgAECgEJAQAAAA==.Pillroller:BAAALgADCgYJBgAAAA==.',
Po='Pock:BAAALgADCgIJAgAAAA==.Poochew:BAAALgAECgcJDgAAAA==.Powerwordmoo:BAAALgADCgYJBwABLgAECgUJCQALAAAAAA==.',
Pr='Prilo:BAAALgADCgcJBwAAAA==.Provi:BAAALgAECgYJCgAAAA==.',
Ps='Psyffe:BAAALgAECgIJAgAAAA==.Psyrge:BAAALgAECgEJAQAAAA==.',
Qu='Queue:BAAALgAECgYJEwAAAA==.',
Re='Rebeccayaros:BAAALgAECgIJAgAAAA==.Redle:BAAALgAECgMJAwAAAA==.Rendarc:BAAALgADCgIJAgAAAA==.',
Rh='Rhordric:BAEALgAFFAEJAQAAAA==.',
Ro='Rokkitok:BAAALgAECgYJCgAAAA==.Ronindots:BAAALgADCgMJAwAAAA==.',
['Rå']='Råwrshåk:BAAALgAECgYJDAAAAA==.',
['Rú']='Rúmi:BAAALgAECgUJCgAAAA==.',
Se='Sea:BAACLgAFFH8LAAIJAAUJphIqAQCtAQAJAAUJphIqAQCtAQAuAAQKfx8AAgkACQkmIOYBAG4DAAkACQkmIOYBAG4DAAAA.Seniri:BAAALgAECgMJCAAAAA==.',
Sh='Shadowrose:BAAALgAECgYJEAAAAA==.Shaide:BAAALgADCgIJAgAAAA==.Shaihulud:BAAALgAECgQJCAAAAA==.Shamanic:BAAALgADCgQJBAAAAA==.Shamanistix:BAAALgAECgEJAgAAAA==.Shane:BAAALgADCgcJBwABLgAECgQJBAALAAAAAA==.Shunsui:BAAALgAECggJEgAAAA==.',
Si='Silchas:BAAALgAECgcJAQAAAA==.Siley:BAABLgAECn8VAAIZAAgJpR7GFABrAgAZAAgJpR7GFABrAgAAAA==.Sixsixsicks:BAAALgAECgcJCwAAAA==.Sizurp:BAAALgADCgIJAgAAAA==.',
Sl='Sleepytree:BAAALgAECgUJBwAAAA==.Slugo:BAAALgADCgEJAQAAAA==.',
Sn='Snail:BAAALgADCgIJAgAAAA==.Sneakytrix:BAAALgAECgEJAgAAAA==.',
So='Sooner:BAAALgAFFAEJAgABLgAFFAMJCQAMAAMbAA==.Sorcerix:BAAALgADCgQJBAAAAA==.',
Sq='Squeaky:BAAALgADCgcJEAAAAA==.',
St='Starar:BAAALgADCgcJDQAAAA==.Stickylicky:BAAALgADCgIJAgAAAA==.',
Su='Suina:BAAALgAECgYJDgAAAA==.Sungodess:BAAALgADCgcJDwAAAA==.',
Ta='Tanya:BAAALgAECgYJCgAAAA==.',
Te='Temporary:BAAALgADCgcJFgAAAA==.Tenka:BAAALgADCgMJAwAAAA==.',
Th='Theblackdk:BAAALgADCgQJAwAAAA==.',
Ti='Tisiphone:BAAALgADCgYJBgAAAA==.',
Tr='Triplenine:BAEALgAECgIJAgABLgAFFAUJDgABAMUaAA==.',
Ts='Tsavò:BAAALgADCgQJBgAAAA==.',
Tu='Tucktoo:BAAALgADCgIJAgAAAA==.',
Ty='Tyundric:BAAALgADCgUJCgAAAA==.',
Un='Unholysage:BAAALgAECgcJEQAAAA==.',
Uw='Uwurailme:BAABLgAECn8UAAQGAAcJNg8MMgDwAAAFAAYJcQxSiwBCAQAGAAUJHAoMMgDwAAAbAAIJrRN5HQCGAAAAAA==.',
Va='Valenix:BAABLgAECn8aAAMcAAgJEBHZCwATAQAcAAcJQBDZCwATAQAYAAUJjg5UQADjAAAAAA==.Valkryi:BAAALgADCgMJAwAAAA==.Vaxis:BAAALgADCgcJDgAAAA==.',
Ve='Velagosa:BAAALgADCgMJAwAAAA==.',
Vo='Vo:BAAALgAECgUJBwAAAA==.',
Wa='Warder:BAAALgAECgYJCwAAAA==.Warp:BAAALgAECgYJDgAAAA==.',
Wh='Whiteshaq:BAAALgADCgYJCAAAAA==.Whiteypingus:BAAALgADCgYJBgAAAA==.',
Wi='Wincks:BAAALgAECgUJCgAAAA==.',
Xe='Xenosaga:BAAALgAECgIJAgAAAA==.',
Ya='Yaltar:BAAALgAECgUJCgAAAA==.',
Za='Zachthemage:BAAALgAECgUJBQAAAA==.Zackman:BAABLgAECn8bAAIZAAgJsgIcTgBAAQAZAAgJsgIcTgBAAQAAAA==.',
Zi='Zinagos:BAAALgAECgMJAwABLgAECggJGgAcABARAA==.',
Zo='Zolttor:BAAALgAECgYJCQAAAA==.',
Zu='Zulrea:BAAALgAECgIJAgAAAA==.Zuri:BAAALgAECgUJCgAAAA==.Zushi:BAAALgADCgYJBgAAAA==.',
['Ùn']='Ùncleíroh:BAAALgADCgcJBwABLgAECgUJCgALAAAAAA==.',
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

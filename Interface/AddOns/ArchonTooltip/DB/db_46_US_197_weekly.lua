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

local lookup = {'Monk-Windwalker','Monk-Mistweaver','Paladin-Retribution','Hunter-Survival','Mage-Frost','Paladin-Holy','Warlock-Destruction','Evoker-Preservation','Evoker-Augmentation','DeathKnight-Blood','Warrior-Protection','Unknown-Unknown','Hunter-BeastMastery','Druid-Balance','DemonHunter-Havoc','Hunter-Marksmanship','Druid-Feral','Shaman-Elemental','Shaman-Restoration','Warlock-Demonology','Druid-Restoration','Evoker-Devastation','Priest-Holy','Priest-Discipline','Warrior-Fury','Shaman-Enhancement','Mage-Arcane',}
local provider = {region='US',realm='SistersofElune',name='US',type='weekly',zone=46,date='2026-05-01',data={Al='Althenara:BAAALgADCgIJAgAAAA==.',
An='Anoramang:BAAALgADCgYJBgAAAA==.',
Aq='Aquarius:BAAALgAECgQJBwAAAA==.Aquessaria:BAAALgADCgEJAQAAAA==.Aquå:BAAALgAECgMJCgAAAA==.',
Ar='Aratfu:BAABLgAECn8cAAMBAAcJQRbrIgC/AQABAAcJQRbrIgC/AQACAAUJFAqJOABfAAAAAA==.Araycadia:BAAALgADCgYJCQAAAA==.Arcanita:BAAALgADCgEJAgAAAA==.Arcee:BAAALgAECgcJDQAAAA==.Archivus:BAAALgADCgEJAQAAAA==.Argelmach:BAAALgAECgEJAQAAAA==.Arui:BAAALgAECgUJDAAAAA==.',
At='Athania:BAAALgAECgYJDwAAAA==.Athornia:BAAALgADCgMJAwAAAA==.',
Az='Azai:BAAALgADCgcJBwAAAA==.Azrannoth:BAAALgAECgYJDgAAAA==.Azurite:BAAALgAECgUJDQAAAA==.',
Ba='Baelthos:BAAALgAECgUJDQAAAA==.Balthamøs:BAABLgAECn8gAAIDAAgJxRAlLwCFAQADAAgJxRAlLwCFAQAAAA==.Baz:BAABLgAECn8WAAIEAAcJvx6wCABbAgAEAAcJvx6wCABbAgAAAA==.',
Be='Beautiful:BAAALgAECgQJBAAAAA==.Belathel:BAAALgAECgEJAQAAAA==.Bermon:BAAALgAECggJDwAAAA==.',
Bl='Bloodmojo:BAAALgADCgYJCAAAAA==.Bloodtotems:BAAALgAECgcJEQAAAA==.Bloomumz:BAAALgAECgUJCgAAAA==.Bluebyyou:BAAALgAECgYJCwAAAA==.Blur:BAAALgAECgEJAQAAAA==.',
Bo='Borgor:BAAALgADCggJCAAAAA==.Bowlicious:BAAALgADCgYJCgAAAA==.',
Br='Bryman:BAAALgADCgQJBwAAAA==.Brystle:BAABLgAECn8XAAIFAAYJigOahADKAAAFAAYJigOahADKAAAAAA==.',
Ca='Caelion:BAABLgAECn8nAAIGAAkJjSIyAQB8AwAGAAkJjSIyAQB8AwAAAA==.Callaf:BAABLgAECn8VAAIHAAcJFA9gCAAoAQAHAAcJFA9gCAAoAQAAAA==.Cannex:BAAALgAECgUJDQAAAA==.',
Ce='Celas:BAAALgAECgIJAgAAAA==.',
Ch='Chromex:BAAALgADCgEJAQAAAA==.',
Ci='Cindro:BAABLgAECn8jAAMIAAgJMw3oCACVAQAIAAgJMw3oCACVAQAJAAQJOgOMOgBmAAAAAA==.',
Cl='Clam:BAAALgAECgIJAgAAAA==.',
Co='Coheed:BAAALgADCgUJBQAAAA==.Command:BAAALgADCgEJAQAAAA==.Cottonwood:BAAALgADCgYJCwAAAA==.',
De='Deekon:BAAALgAECgYJDwAAAA==.Deni:BAAALgAECgEJAgAAAA==.Devourer:BAAALgADCgEJAQAAAA==.Deyvian:BAAALgAECgIJAgAAAA==.',
Do='Dovathresh:BAAALgAECgcJBwABLgAFFAYJFQAKAPoWAA==.',
Ec='Ectorius:BAAALgAECgEJAQAAAA==.',
Eg='Egud:BAABLgAECn8UAAILAAcJwxT/CwBkAQALAAcJwxT/CwBkAQAAAA==.',
El='Elegean:BAAALgADCgIJAgAAAA==.Eliri:BAACLgAFFH8KAAICAAMJJhyHDgDxAAACAAMJJhyHDgDxAAAuAAQKfxQAAgIACAlfG5YgAK4BAAIACAlfG5YgAK4BAAAA.Ellenad:BAAALgAECgUJBQAAAA==.Elsadormu:BAAALgAECgIJAgABLgAECgQJCwAMAAAAAA==.Elsà:BAAALgAECgYJBgABLgAECgYJLAANAMsfAA==.',
Ev='Evayn:BAAALgAECgYJDAAAAA==.Everhunt:BAAALgAECgIJAgAAAA==.Evo:BAAALgAECgYJDwAAAA==.Evolves:BAAALgADCgEJAQAAAA==.',
Fa='Fanguloo:BAAALgADCgYJBgAAAA==.Fantasmo:BAAALgAECgEJAQAAAA==.Fantoria:BAAALgADCgcJBAAAAA==.Farisu:BAAALgAECgcJEgAAAA==.',
Fe='Feasting:BAAALgADCgEJAQABLgAECggJIwAOAC4ZAA==.Feval:BAAALgADCgMJAwAAAA==.',
Fl='Flavortown:BAAALgAECgYJEAAAAA==.Fletch:BAAALgADCgMJAwAAAA==.Flick:BAAALgAECgQJCwAAAA==.Fluffyfury:BAAALgAECgQJCQAAAA==.',
Fo='Foggy:BAAALgADCgEJAQAAAA==.',
Fr='Frontallover:BAAALgADCgUJBQABLgAFFAMJCgACACYcAA==.',
Ga='Gaba:BAABLgAFFH8FAAICAAMJ2hWJDwDfAAACAAMJ2hWJDwDfAAAAAA==.Galndrel:BAAALgADCgEJAQAAAA==.',
Ge='Georish:BAABLgAECn8cAAIPAAgJeA+XHwDBAQAPAAgJeA+XHwDBAQAAAA==.',
Gi='Ginseng:BAAALgAECgYJDwAAAA==.',
Go='Gorg:BAAALgAECgYJDwAAAA==.',
Gr='Grease:BAAALgAECgEJAQAAAA==.',
Gu='Gunkshot:BAABLgAECn8VAAIQAAcJ7yUZCQANAwAQAAcJ7yUZCQANAwAAAA==.',
['Gé']='Gémini:BAAALgAECgEJAQAAAA==.',
Ha='Haavoc:BAABLgAECn8aAAIRAAcJGQa0DgDuAAARAAcJGQa0DgDuAAAAAA==.Handsomeman:BAAALgAECgEJAQAAAA==.Haniki:BAAALgADCgMJAwAAAA==.',
He='Hexadecimal:BAAALgAECgIJAwAAAA==.',
Hi='Hiasinth:BAABLgAECn8WAAMCAAgJaBACIgCjAQACAAgJaBACIgCjAQABAAMJxRZiUwDEAAAAAA==.',
Ho='Holytroller:BAAALgADCgUJBQAAAA==.Hornhub:BAAALgAECgYJCgAAAA==.',
Ik='Ikhdea:BAAALgADCgUJBQAAAA==.Ikhdin:BAAALgAECgMJAwAAAA==.Ikhlock:BAAALgADCgMJAwAAAA==.Ikthalon:BAAALgADCggJCAAAAA==.',
Im='Imnotafurry:BAAALgAECgUJBQABLgAFFAMJCgACACYcAA==.',
Ir='Irine:BAAALgADCgIJAgAAAA==.Irore:BAAALgAECgIJAgAAAA==.',
Is='Isoldé:BAAALgADCgcJBwAAAA==.',
Ja='Jagen:BAAALgADCgYJBgAAAA==.Jamarie:BAAALgADCgYJBgAAAA==.Jarrah:BAAALgAECgUJCgAAAA==.Jaxr:BAABLgAECn8hAAINAAkJshGcEgD9AQANAAkJshGcEgD9AQAAAA==.',
Je='Jetahnna:BAAALgAECgUJCQAAAA==.',
Jh='Jhata:BAAALgAECgYJEQAAAA==.',
Jo='Johnnysins:BAAALgAECgUJBwABLgAFFAUJBgAFAB8QAA==.Jontarr:BAAALgAECgEJAQAAAA==.',
Ju='Juicyphod:BAAALgAECgEJAQAAAA==.',
Ka='Kaelanna:BAAALgAECgcJEAAAAA==.Kajadin:BAAALgAECgUJDQAAAA==.Karatedonkey:BAAALgAECgUJCwAAAA==.Kardai:BAEALgAECgUJDQAAAA==.Katamai:BAAALgAECgYJDwAAAA==.Kazimas:BAAALgAECgUJCgAAAA==.',
Ke='Kelisande:BAAALgADCgEJAQAAAA==.',
Kh='Khalcite:BAAALgAECgUJDQAAAA==.',
Ki='Kik:BAAALgADCgEJAQAAAA==.Kittyshaman:BAABLgAECn8jAAMSAAgJ3wsVGABSAQASAAgJ3wsVGABSAQATAAEJtwNKowAtAAAAAA==.',
Ku='Kuross:BAAALgAECgQJBQAAAA==.',
Ky='Kyraltas:BAAALgAECgUJCgAAAA==.',
La='Laermeluion:BAAALgAECgYJBwABLgAFFAYJFQAKAPoWAA==.Larra:BAABLgAECn8sAAINAAYJyx87GADRAQANAAYJyx87GADRAQAAAA==.',
Le='Lefthian:BAAALgAECgQJDQAAAA==.Lemixa:BAAALgADCgEJAQAAAA==.',
Li='Listwhorior:BAABLgAECn8kAAILAAgJix90AgCAAgALAAgJix90AgCAAgAAAA==.',
Lo='Logen:BAAALgADCgcJCAAAAA==.Lokita:BAAALgADCgUJBQAAAA==.Loshing:BAAALgAECgIJAgAAAA==.',
Lu='Lunakae:BAAALgAECgMJAwAAAA==.',
Ly='Lysandrra:BAAALgAECgMJBAAAAA==.',
Ma='Madeline:BAAALgADCgQJBAAAAA==.Malafar:BAAALgAFFAEJAgAAAA==.Malfuriion:BAAALgAECgMJBQAAAA==.Maranwae:BAABLgAECn8WAAITAAcJHSB9CQBSAgATAAcJHSB9CQBSAgAAAA==.Maybemo:BAAALgADCgkJCQAAAA==.',
Me='Mebumsir:BAAALgADCgUJBgAAAA==.Melokoi:BAAALgAECgYJEQAAAA==.Merlose:BAAALgAECgYJEgAAAA==.',
Mi='Minidrake:BAAALgAECgQJCwAAAA==.',
Mo='Mogrun:BAABLgAECn8WAAMHAAcJShlrFwCOAQAUAAYJJRqPWAC+AQAHAAYJlRVrFwCOAQAAAA==.Monahci:BAAALgADCgcJEwAAAA==.Monocho:BAAALgADCgMJAwAAAA==.Monrroe:BAAALgAECgYJDAAAAA==.Mooasaurus:BAAALgAFFAIJAgAAAA==.Moonfaith:BAAALgADCgYJBgABLgAECggJIwAVAFYfAA==.Moonveil:BAAALgAECggJDQABLgAECggJIwAVAFYfAA==.Moshamie:BAAALgAECgQJBwAAAA==.',
Na='Naeryns:BAAALgAECgUJCQAAAA==.Narzwaz:BAAALgAECgUJEAAAAA==.Natallia:BAAALgADCgUJBQABLgAECgYJLAANAMsfAA==.',
Ne='Nehemiia:BAAALgADCgMJAwAAAA==.Neytri:BAAALgAECgcJEQAAAA==.',
Ni='Nivale:BAAALgAECgYJEAAAAA==.',
No='Noel:BAABLgAECn8gAAIFAAgJsRlxJADWAQAFAAgJsRlxJADWAQAAAA==.Nosotras:BAAALgAECgUJDQAAAA==.Noxicous:BAAALgAECgYJEQAAAA==.',
Ol='Olitas:BAAALgAECgQJBQAAAA==.',
Pa='Patches:BAAALgAECgYJDgAAAA==.',
Pe='Perse:BAAALgAECgEJAQAAAA==.',
Ph='Phau:BAAALgAECgUJDQAAAA==.',
Pi='Pinklemonade:BAAALgADCgIJAgAAAA==.',
Pl='Playmate:BAABLgAECn8jAAIVAAgJVh/4CAB8AgAVAAgJVh/4CAB8AgAAAA==.',
Po='Potatoe:BAAALgADCgQJBAAAAA==.',
Pr='Prozac:BAAALgADCgMJAwAAAA==.Prïnçess:BAAALgAECgUJDAAAAA==.',
Py='Pymilocs:BAAALgAECgUJDQAAAA==.',
Qu='Qualison:BAAALgAECgYJEgAAAA==.',
Ra='Rabare:BAAALgAECgcJDgAAAA==.Rabore:BAAALgAECgQJBAAAAA==.Rahumn:BAAALgAECgYJDgAAAA==.Ralee:BAAALgAECgMJAwABLgAECgQJCwAMAAAAAA==.Ranebowz:BAAALgAFFAEJAQAAAA==.Ravenmohr:BAAALgADCgUJBQAAAA==.',
Rh='Rhebeqa:BAAALgADCgYJBgABLgAECgQJBwAMAAAAAA==.',
Ri='Richter:BAAALgADCgkJIAAAAA==.Rin:BAEBLgAECn8cAAICAAgJVR03BQB/AgACAAgJVR03BQB/AgAAAA==.Rist:BAABLgAECn8gAAILAAkJ+A/1BwC6AQALAAkJ+A/1BwC6AQAAAA==.',
Ro='Rogelink:BAAALgAECgQJBgAAAA==.Rosan:BAAALgAECgQJBAAAAA==.Royakan:BAAALgAECgEJBAAAAA==.',
Sa='Samoset:BAAALgAECgUJDQAAAA==.',
Se='Setsuna:BAABLgAECn8cAAMWAAkJ2iD3BwBoAgAWAAYJBCX3BwBoAgAJAAUJ3hp7EACLAQABLgADCgQJBAAMAAAAAA==.',
Sh='Shava:BAAALgADCgkJCQAAAA==.Sheepstealer:BAABLgAECn8UAAIWAAYJxxWsBQBOAQAWAAYJxxWsBQBOAQAAAA==.Shippo:BAAALgAECgIJAgAAAA==.Shockisha:BAAALgADCgYJBgAAAA==.Showgirl:BAAALgADCgcJBwABLgAECgQJBAAMAAAAAA==.',
Si='Silvanthos:BAAALgAECgEJAQAAAA==.Silvers:BAAALgAECgUJCwAAAA==.',
Sl='Sliccie:BAABLgAECn8eAAIUAAgJMQ+ZMwBdAQAUAAgJMQ+ZMwBdAQAAAA==.',
Sm='Smitegoat:BAABLgAECn8lAAMXAAkJ8hqeFAA5AgAXAAgJ8xmeFAA5AgAYAAIJqh+vIgC9AAAAAA==.',
Sn='Sney:BAAALgAECgQJCwAAAA==.',
So='Sorlzul:BAAALgAECgMJBwAAAA==.',
Sp='Specialbarz:BAAALgADCgEJAQAAAA==.',
St='Stellaluna:BAAALgAECgQJBAAAAA==.',
Sv='Svanalock:BAAALgADCgcJDwAAAA==.',
Ta='Tad:BAABLgAECn8UAAINAAYJPQh+QQAQAQANAAYJPQh+QQAQAQAAAA==.Taini:BAAALgADCgYJBgABLgAFFAYJFQAKAPoWAA==.Taiurag:BAAALgAECgUJDgAAAA==.Taken:BAAALgAECgUJDQAAAA==.Tazra:BAABLgAECn8eAAIDAAgJ/h3pLQBrAgADAAgJ/h3pLQBrAgAAAA==.Tazzy:BAAALgADCgkJDwAAAA==.',
Te='Terrylabonte:BAAALgAECgcJEgAAAA==.',
Th='Thomaz:BAABLgAECn8UAAIZAAgJZg33EwCVAQAZAAgJZg33EwCVAQAAAA==.Thorninii:BAAALgADCgQJBAAAAA==.Thundergoose:BAAALgAECgMJAwAAAA==.',
Ti='Tirel:BAAALgADCgUJBQAAAA==.',
To='Tonkatruck:BAAALgAECgUJDQAAAA==.',
Tt='Ttvnazboo:BAAALgADCgMJBAAAAA==.',
Tu='Tulany:BAABLgAECn8VAAMXAAgJYQgOGQBAAQAXAAgJFQcOGQBAAQAYAAYJYwcJMQAYAQAAAA==.Tuyenlotus:BAABLgAECn8cAAIaAAkJqhhUCQBDAgAaAAkJqhhUCQBDAgAAAA==.',
Un='Unholypriest:BAAALgAECgMJBgAAAA==.',
Ut='Utloc:BAAALgAECgUJDQAAAA==.',
Va='Vahnya:BAAALgAECgQJCQAAAA==.Vardren:BAAALgADCgQJBAAAAA==.',
Ve='Venekor:BAAALgAECgYJEgAAAA==.Vesia:BAAALgAECgYJEwAAAA==.',
Vi='Viainfinita:BAAALgADCgYJBgAAAA==.Viannaironcl:BAAALgADCgIJAgAAAA==.',
Vo='Voidrat:BAAALgAECgEJAgABLgAECgcJHAABAEEWAA==.Voidweaver:BAAALgADCgYJBgAAAA==.',
['Ví']='Ví:BAAALgAECgUJDQAAAA==.',
Wh='Whistler:BAAALgADCgEJAQAAAA==.',
Wi='Wildpally:BAAALgAECgUJEAAAAA==.',
['Wí']='Wíldhide:BAAALgADCgMJAwAAAA==.',
Xo='Xonon:BAAALgAECgYJEAAAAA==.',
Xw='Xweithel:BAAALgAECgQJBwAAAA==.',
Yo='Yourmageisty:BAABLgAECn8fAAMFAAgJphPMMwCWAQAFAAgJAQ/MMwCWAQAbAAQJaxeSCwAcAQAAAA==.',
Yu='Yulíana:BAAALgAECgUJCQAAAA==.',
Za='Zanot:BAAALgADCgYJBgAAAA==.Zariara:BAAALgADCgUJBQAAAA==.',
Zc='Zcart:BAAALgAECgYJDwAAAA==.',
Ze='Zelara:BAAALgAECgUJCAAAAA==.Zertloc:BAABLgAECn8YAAISAAYJTxRVGwA5AQASAAYJTxRVGwA5AQAAAA==.',
Zh='Zhaan:BAAALgADCgkJDwAAAA==.',
Zi='Zieda:BAAALgAECgcJEwAAAA==.Ziti:BAAALgADCgIJAgAAAA==.',
Zu='Zubiria:BAAALgADCgQJBAAAAA==.Zulaaj:BAAALgAECgMJAwAAAA==.',
['Év']='Évania:BAAALgADCgYJBgAAAA==.Éver:BAAALgADCgUJBQAAAA==.',
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

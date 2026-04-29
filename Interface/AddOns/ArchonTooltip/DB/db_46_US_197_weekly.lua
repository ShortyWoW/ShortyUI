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

local lookup = {'Monk-Windwalker','Monk-Mistweaver','Paladin-Retribution','Hunter-Survival','Priest-Holy','Paladin-Holy','Evoker-Preservation','DeathKnight-Blood','Unknown-Unknown','Hunter-BeastMastery','Druid-Balance','DemonHunter-Havoc','Hunter-Marksmanship','Mage-Frost','Shaman-Elemental','Shaman-Restoration','Warrior-Protection','Warlock-Destruction','Warlock-Demonology','Druid-Restoration','Evoker-Devastation','Evoker-Augmentation','Priest-Discipline','Shaman-Enhancement','Mage-Arcane',}
local provider = {region='US',realm='SistersofElune',name='US',type='weekly',zone=46,date='2026-04-24',data={Al='Althenara:BAAALgADCgIJAgAAAA==.',
An='Anoramang:BAAALgADCgYJBgAAAA==.',
Aq='Aquarius:BAAALgAECgQJBAAAAA==.Aquessaria:BAAALgADCgEJAQAAAA==.Aquå:BAAALgAECgMJCgAAAA==.',
Ar='Aratfu:BAABLgAECn8WAAMBAAcJQRbqIgC/AQABAAcJQRbqIgC/AQACAAMJ3QfWWABsAAAAAA==.Araycadia:BAAALgADCgYJCQAAAA==.Arcanita:BAAALgADCgEJAQAAAA==.Arcee:BAAALgAECgYJBgAAAA==.Archivus:BAAALgADCgEJAQAAAA==.Argelmach:BAAALgAECgEJAQAAAA==.Arui:BAAALgAECgQJCAAAAA==.',
At='Athania:BAAALgAECgQJCgAAAA==.Athornia:BAAALgADCgEJAQAAAA==.',
Az='Azrannoth:BAAALgAECgQJCAAAAA==.Azurite:BAAALgAECgUJCAAAAA==.',
Ba='Baelthos:BAAALgAECgUJCQAAAA==.Balthamøs:BAABLgAECn8ZAAIDAAgJDA4hHABGAQADAAgJDA4hHABGAQAAAA==.Baz:BAABLgAECn8VAAIEAAYJ7CGtCABbAgAEAAYJ7CGtCABbAgAAAA==.',
Be='Beautiful:BAAALgAECgQJBAAAAA==.Belathel:BAAALgAECgEJAQAAAA==.Bermon:BAAALgAECgcJBwABLgAECggJFQAFAGEIAA==.',
Bl='Bloodmojo:BAAALgADCgIJAgAAAA==.Bloodtotems:BAAALgAECgcJEQAAAA==.Bloomumz:BAAALgAECgUJBQAAAA==.Bluebyyou:BAAALgAECgUJCgAAAA==.Blur:BAAALgAECgEJAQAAAA==.',
Bo='Borgor:BAAALgADCggJCAAAAA==.Bowlicious:BAAALgADCgYJCQAAAA==.',
Br='Bryman:BAAALgADCgQJBAAAAA==.Brystle:BAAALgAECgYJEgAAAA==.',
Ca='Caelion:BAABLgAECn8iAAIGAAkJ4yEyAQB8AwAGAAkJ4yEyAQB8AwAAAA==.Callaf:BAAALgAECgYJDgAAAA==.Cannex:BAAALgAECgUJCQAAAA==.',
Ce='Celas:BAAALgAECgIJAgAAAA==.',
Ch='Chromex:BAAALgADCgEJAQAAAA==.',
Ci='Cindro:BAABLgAECn8cAAIHAAgJTgzJAwCgAQAHAAgJTgzJAwCgAQAAAA==.',
Cl='Clam:BAAALgAECgIJAgAAAA==.',
Co='Coheed:BAAALgADCgUJBQAAAA==.Command:BAAALgADCgEJAQAAAA==.Cottonwood:BAAALgADCgYJCwAAAA==.',
De='Deekon:BAAALgAECgQJCgAAAA==.Deni:BAAALgAECgEJAQAAAA==.Devourer:BAAALgADCgEJAQAAAA==.',
Do='Dovathresh:BAAALgAECgcJBwABLgAFFAYJFAAIAPoWAA==.',
Eg='Egud:BAAALgAECgYJDQAAAA==.',
El='Elegean:BAAALgADCgIJAgAAAA==.Eliri:BAABLgAFFH8HAAICAAMJfRZxBgDXAAACAAMJfRZxBgDXAAAAAA==.Elsadormu:BAAALgAECgIJAgABLgAECgQJCQAJAAAAAA==.Elsà:BAAALgAECgYJBgABLgAECgYJJgAKAE0eAA==.',
Ev='Evayn:BAAALgAECgQJCAAAAA==.Everhunt:BAAALgADCgkJHQAAAA==.Evo:BAAALgAECgQJCgAAAA==.Evolves:BAAALgADCgEJAQAAAA==.',
Fa='Fantasmo:BAAALgAECgEJAQAAAA==.Fantoria:BAAALgADCgcJBAAAAA==.Farisu:BAAALgAECgcJDAAAAA==.',
Fe='Feasting:BAAALgADCgEJAQABLgAECgcJHgALAKoYAA==.Feval:BAAALgADCgMJAwAAAA==.',
Fl='Flavortown:BAAALgAECgYJCgAAAA==.Fletch:BAAALgADCgMJAwAAAA==.Flick:BAAALgAECgQJCwAAAA==.Fluffyfury:BAAALgAECgQJCQAAAA==.',
Fr='Frontallover:BAAALgADCgUJBQABLgAFFAMJBwACAH0WAA==.',
Ga='Gaba:BAAALgAFFAMJBAAAAA==.',
Ge='Georish:BAABLgAECn8cAAIMAAgJdw+XHwDBAQAMAAgJdw+XHwDBAQAAAA==.',
Gi='Ginseng:BAAALgAECgQJCgAAAA==.',
Go='Gorg:BAAALgAECgQJCgAAAA==.',
Gr='Grease:BAAALgAECgEJAQAAAA==.',
Gu='Gunkshot:BAABLgAECn8VAAINAAcJ7yUUCQANAwANAAcJ7yUUCQANAwAAAA==.',
Ha='Haavoc:BAAALgAECgYJEwAAAA==.Handsomeman:BAAALgAECgEJAQAAAA==.Haniki:BAAALgADCgMJAwAAAA==.',
Hi='Hiasinth:BAABLgAECn8WAAMCAAgJaBAZIgCkAQACAAgJaBAZIgCkAQABAAMJxRZjUwDEAAAAAA==.',
Ho='Holytroller:BAAALgADCgUJBQAAAA==.Hornhub:BAAALgAECgYJCgAAAA==.',
Ik='Ikhdea:BAAALgADCgUJBQAAAA==.Ikhdin:BAAALgAECgMJAwAAAA==.Ikhlock:BAAALgADCgMJAwAAAA==.Ikthalon:BAAALgADCggJCAAAAA==.',
Ir='Irine:BAAALgADCgIJAgAAAA==.Irore:BAAALgADCgkJHQAAAA==.',
Is='Isoldé:BAAALgADCgcJBwAAAA==.',
Ja='Jaems:BAAALgAECgQJBAAAAA==.Jagen:BAAALgADCgYJBgAAAA==.Jamarie:BAAALgADCgYJBgAAAA==.Jarrah:BAAALgAECgMJAwAAAA==.Jaxr:BAABLgAECn8XAAIKAAkJaA6KJgAgAgAKAAkJaA6KJgAgAgAAAA==.',
Je='Jetahnna:BAAALgAECgUJBQAAAA==.',
Jh='Jhata:BAAALgAECgYJCgAAAA==.',
Jo='Johnnysins:BAAALgAECgUJBgABLgAECgkJHgAOAPUiAA==.',
Ka='Kaelanna:BAAALgAECgYJCwAAAA==.Kajadin:BAAALgAECgUJCQAAAA==.Karatedonkey:BAAALgAECgQJBwAAAA==.Kardai:BAEALgAECgUJCQAAAA==.Katamai:BAAALgAECgQJCgAAAA==.Kazimas:BAAALgAECgUJCgAAAA==.',
Ke='Kelisande:BAAALgADCgEJAQAAAA==.',
Kh='Khalcite:BAAALgAECgUJCQAAAA==.',
Ki='Kittyshaman:BAABLgAECn8cAAMPAAgJcgpRCwBHAQAPAAgJcgpRCwBHAQAQAAEJtwNGowAtAAAAAA==.',
Ku='Kuross:BAAALgAECgQJBQAAAA==.',
Ky='Kyraltas:BAAALgAECgUJBgAAAA==.',
La='Laermeluion:BAAALgAECgUJBQABLgAFFAYJFAAIAPoWAA==.Larra:BAABLgAECn8mAAIKAAYJTR4yLgD5AQAKAAYJTR4yLgD5AQAAAA==.',
Le='Lefthian:BAAALgAECgQJDQAAAA==.Lemixa:BAAALgADCgEJAQAAAA==.',
Li='Listwhorior:BAABLgAECn8cAAIRAAgJLx9cAQBEAgARAAgJLx9cAQBEAgAAAA==.',
Lo='Logen:BAAALgADCgcJCAAAAA==.Loshing:BAAALgADCgcJEAAAAA==.',
Lu='Lunakae:BAAALgAECgIJAgAAAA==.',
Ly='Lysandrra:BAAALgAECgMJBAAAAA==.',
Ma='Madeline:BAAALgADCgQJBAAAAA==.Malafar:BAAALgAECgMJBAAAAA==.Malfuriion:BAAALgAECgMJBQAAAA==.Maranwae:BAAALgAECgYJDwAAAA==.',
Me='Mebumsir:BAAALgADCgUJBgAAAA==.Melokoi:BAAALgAECgYJCgAAAA==.Merlose:BAAALgAECgYJDAAAAA==.',
Mi='Minidrake:BAAALgAECgQJCwAAAA==.',
Mo='Mogrun:BAABLgAECn8WAAMSAAcJShlwFwCOAQATAAYJJRqPWAC+AQASAAYJlRVwFwCOAQAAAA==.Monahci:BAAALgADCgcJEwAAAA==.Monocho:BAAALgADCgMJAwAAAA==.Monrroe:BAAALgAECgUJBgAAAA==.Mooasaurus:BAAALgAFFAIJAgAAAA==.Moonfaith:BAAALgADCgUJBQABLgAECggJDQAJAAAAAA==.Moonveil:BAAALgAECggJDQAAAA==.Moshamie:BAAALgAECgMJAwAAAA==.',
Na='Naeryns:BAAALgAECgUJCQAAAA==.Narzwaz:BAAALgAECgUJDAAAAA==.Natallia:BAAALgADCgUJBQABLgAECgYJJgAKAE0eAA==.',
Ne='Nehemiia:BAAALgADCgMJAwAAAA==.Neytri:BAAALgAECgYJCgAAAA==.',
Ni='Nivale:BAAALgAECgYJCgAAAA==.',
No='Noel:BAABLgAECn8YAAIOAAcJjRygWAAvAgAOAAcJjRygWAAvAgAAAA==.Nosotras:BAAALgAECgUJCQAAAA==.Noxicous:BAAALgAECgYJDAAAAA==.',
Ol='Olitas:BAAALgAECgMJAwAAAA==.',
Pa='Patches:BAAALgAECgYJDgAAAA==.',
Pe='Perse:BAAALgAECgEJAQAAAA==.',
Ph='Phau:BAAALgAECgUJCQAAAA==.',
Pi='Pinklemonade:BAAALgADCgIJAgAAAA==.',
Pl='Playmate:BAABLgAECn8XAAIUAAcJkB8yGgBoAgAUAAcJkB8yGgBoAgABLgAECggJDQAJAAAAAA==.',
Po='Potatoe:BAAALgADCgQJBAAAAA==.',
Pr='Prozac:BAAALgADCgMJAwAAAA==.Prïnçess:BAAALgAECgQJBwAAAA==.',
Py='Pymilocs:BAAALgAECgQJCQAAAA==.',
Qu='Qualison:BAAALgAECgYJDwAAAA==.',
Ra='Rabare:BAAALgAECgcJDgAAAA==.Rahumn:BAAALgAECgYJDQAAAA==.Ralee:BAAALgAECgMJAwABLgAECgQJBwAJAAAAAA==.Ranebowz:BAAALgAECgYJCwAAAA==.Ravenmohr:BAAALgADCgUJBQAAAA==.',
Ri='Richter:BAAALgADCgkJIAAAAA==.Rin:BAEBLgAECn8UAAICAAYJAiAQBgC0AQACAAYJAiAQBgC0AQAAAA==.Rist:BAABLgAECn8eAAIRAAgJWBGxBAB9AQARAAgJWBGxBAB9AQAAAA==.',
Ro='Rogelink:BAAALgAECgQJBQAAAA==.Rosan:BAAALgAECgQJBAAAAA==.Royakan:BAAALgAECgEJAwAAAA==.',
Sa='Samoset:BAAALgAECgUJCQAAAA==.',
Se='Setsuna:BAABLgAECn8YAAMVAAgJWiP3BwBoAgAVAAYJBCX3BwBoAgAWAAIJMR/lGgBkAAABLgADCgQJBAAJAAAAAA==.',
Sh='Shava:BAAALgADCgkJCQAAAA==.Sheepstealer:BAAALgAECgYJDgAAAA==.Shippo:BAAALgAECgIJAgAAAA==.Shockisha:BAAALgADCgYJBgAAAA==.Showgirl:BAAALgADCgcJBwABLgAECgQJBAAJAAAAAA==.',
Si='Silvers:BAAALgAECgUJCwAAAA==.',
Sl='Sliccie:BAABLgAECn8cAAITAAgJrA6bFQBjAQATAAgJrA6bFQBjAQAAAA==.',
Sm='Smitegoat:BAABLgAECn8iAAIFAAgJ8xmZFAA5AgAFAAgJ8xmZFAA5AgAAAA==.',
Sn='Sney:BAAALgAECgQJBwAAAA==.',
So='Sorlzul:BAAALgAECgMJBAAAAA==.',
Sp='Specialbarz:BAAALgADCgEJAQAAAA==.',
St='Stellaluna:BAAALgAECgQJBAAAAA==.',
Sv='Svanalock:BAAALgADCgcJDwAAAA==.',
Ta='Tad:BAAALgAECgYJDgAAAA==.Taini:BAAALgADCgYJBgABLgAFFAYJFAAIAPoWAA==.Taiurag:BAAALgAECgUJCwAAAA==.Taken:BAAALgAECgUJCQAAAA==.Tazra:BAABLgAECn8bAAIDAAcJxx/zLQBrAgADAAcJxx/zLQBrAgAAAA==.Tazzy:BAAALgADCgkJDwAAAA==.',
Te='Telnei:BAABLgAECn8VAAMFAAgJYQjWCgBKAQAFAAgJFQfWCgBKAQAXAAYJYwcHMQAYAQAAAA==.Terrylabonte:BAAALgAECgcJDgAAAA==.',
Th='Thomaz:BAAALgAECgcJDAAAAA==.Thorninii:BAAALgADCgQJBAAAAA==.Thundergoose:BAAALgAECgMJAwAAAA==.',
Ti='Tirel:BAAALgADCgUJBQAAAA==.',
To='Tonkatruck:BAAALgAECgUJCQAAAA==.',
Tt='Ttvnazboo:BAAALgADCgMJBAAAAA==.',
Tu='Tuyenlotus:BAABLgAECn8YAAIYAAgJqBtTCQBDAgAYAAgJqBtTCQBDAgAAAA==.',
Un='Unholypriest:BAAALgAECgMJBQAAAA==.',
Ut='Utloc:BAAALgAECgUJCQAAAA==.',
Va='Vahnya:BAAALgAECgQJBgAAAA==.Vardren:BAAALgADCgQJBAAAAA==.',
Ve='Venekor:BAAALgAECgYJEAAAAA==.Vesia:BAAALgAECgYJDAAAAA==.',
Vi='Viainfinita:BAAALgADCgYJBgAAAA==.Viannaironcl:BAAALgADCgIJAgAAAA==.',
Vo='Voidrat:BAAALgAECgEJAQABLgAECgcJFgABAEEWAA==.Voidweaver:BAAALgADCgYJBgAAAA==.',
['Ví']='Ví:BAAALgAECgUJCAAAAA==.',
Wh='Whistler:BAAALgADCgEJAQAAAA==.',
Wi='Wildpally:BAAALgAECgUJDQAAAA==.',
['Wí']='Wíldhide:BAAALgADCgMJAwAAAA==.',
Xo='Xonon:BAAALgAECgYJEAAAAA==.',
Xw='Xweithel:BAAALgAECgQJBwAAAA==.',
Yo='Yourmageisty:BAABLgAECn8aAAMOAAcJnBP8HABmAQAOAAcJMQ78HABmAQAZAAQJaxeQCwAdAQAAAA==.',
Yu='Yulíana:BAAALgAECgQJBAAAAA==.',
Za='Zanot:BAAALgADCgYJBgAAAA==.Zariara:BAAALgADCgUJBQAAAA==.',
Zc='Zcart:BAAALgAECgQJCgAAAA==.',
Ze='Zelara:BAAALgAECgUJBwAAAA==.Zertloc:BAABLgAECn8UAAIPAAYJGhMyDgAgAQAPAAYJGhMyDgAgAQAAAA==.',
Zh='Zhaan:BAAALgADCggJDQAAAA==.',
Zi='Zieda:BAAALgAECgYJEAAAAA==.',
Zu='Zulaaj:BAAALgAECgMJAwAAAA==.',
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

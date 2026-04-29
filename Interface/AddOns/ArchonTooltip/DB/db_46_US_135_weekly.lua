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

local lookup = {'Rogue-Assassination','Shaman-Elemental','Mage-Frost','Mage-Fire','Unknown-Unknown','Priest-Shadow','Priest-Discipline','Warlock-Destruction','Warlock-Demonology','Paladin-Retribution','DeathKnight-Unholy','DeathKnight-Blood','Monk-Brewmaster','Rogue-Subtlety','Shaman-Restoration','Hunter-BeastMastery','Priest-Holy','Warrior-Fury','Druid-Restoration','DemonHunter-Devourer','Paladin-Protection','Paladin-Holy','Hunter-Survival','Hunter-Marksmanship','Shaman-Enhancement','Warrior-Protection','Evoker-Devastation',}
local provider = {region='US',realm='KirinTor',name='US',type='weekly',zone=46,date='2026-04-24',data={Ac='Acallia:BAAALgADCgYJBgAAAA==.Achkmed:BAAALgAECgkJDAAAAA==.',
Ae='Aelynis:BAABLgAECn8cAAIBAAkJfA6ZCADFAQABAAkJfA6ZCADFAQAAAA==.',
Ak='Akalon:BAABLgAECn8fAAICAAgJkgiiTgAMAQACAAgJkgiiTgAMAQAAAA==.',
Al='Alara:BAAALgADCgEJAQABLgAECggJJAADADQfAA==.Aldrus:BAAALgADCgYJBgAAAA==.Allfrost:BAAALgADCgEJAQAAAA==.',
Am='Amanthelia:BAAALgADCgUJBQAAAA==.',
An='Annerose:BAAALgAECgQJBgAAAA==.Anthir:BAAALgADCgEJAgAAAA==.',
Ao='Aoeina:BAABLgAECn8gAAMDAAgJuxKhGQB7AQADAAcJSRWhGQB7AQAEAAEJZQOUBAApAAAAAA==.',
Ap='Apollo:BAAALgAECgQJBAAAAA==.',
Aq='Aquinas:BAAALgAECgQJBAABLgAECgYJDwAFAAAAAA==.',
Ar='Arcanelotus:BAAALgADCgUJBQAAAA==.Arcás:BAAALgADCgYJBgAAAA==.Ariaves:BAABLgAECn8aAAMGAAkJlhbUGwD+AQAGAAkJlhbUGwD+AQAHAAQJugjPPgC3AAAAAA==.Arilea:BAAALgADCgkJEgAAAA==.Arioriaa:BAAALgAECgYJCAAAAA==.Arlind:BAAALgADCgYJCAAAAA==.',
As='Asenath:BAAALgADCgEJAQAAAA==.Asoeclya:BAAALgADCgIJAgAAAA==.',
At='Atanatari:BAAALgADCgYJDwABLgADCgcJGgAFAAAAAA==.Attonix:BAAALgAECgEJAQAAAA==.',
Az='Azem:BAAALgADCggJEwAAAA==.Azixarid:BAAALgADCgkJEgAAAA==.',
Ba='Baldur:BAAALgADCgcJDAAAAA==.Baratheøn:BAAALgAECgYJDwAAAA==.Bassotan:BAAALgAECgYJBgAAAA==.',
Be='Beasttoken:BAAALgADCgUJBQAAAA==.Beleva:BAAALgAECgUJEQAAAA==.',
Bi='Bigstan:BAAALgAECgQJBAAAAA==.Bilbobagging:BAAALgADCgcJCwAAAA==.Bilx:BAAALgAECgYJCwAAAA==.Biromong:BAAALgAECgIJAgAAAA==.',
Bl='Blackendmoon:BAAALgAECgMJBAAAAA==.Bloodknight:BAAALgADCgEJAQAAAA==.Bluebeary:BAAALgADCgEJAQAAAA==.Bluelocks:BAABLgAECn8YAAMIAAgJUgd4HgBcAQAIAAgJUgd4HgBcAQAJAAEJSwKOWwAqAAAAAA==.Bluéyes:BAAALgADCgUJBQAAAA==.Blvckscvl:BAAALgAECgcJEgAAAA==.Blynna:BAAALgADCgcJCQAAAA==.',
Bo='Bohemond:BAAALgADCgcJBwAAAA==.',
Br='Broadleaf:BAAALgAECgQJCQAAAA==.',
Ca='Calinai:BAAALgADCgkJDgAAAA==.Catastrophi:BAAALgADCgEJAQAAAA==.Catastrophie:BAAALgAECgUJCwAAAA==.',
Ch='Chiarakai:BAAALgADCgQJBAAAAA==.',
Cl='Claudeena:BAAALgADCgkJEgAAAA==.',
Co='Coswell:BAAALgADCgkJCQAAAA==.',
Cr='Creeder:BAABLgAECn8cAAIKAAkJ4Q0DdACTAQAKAAkJ4Q0DdACTAQAAAA==.Crm:BAAALgADCgUJBQAAAA==.',
Cy='Cynise:BAAALgADCgcJDQAAAA==.',
Da='Dagoland:BAAALgAECgMJAwAAAA==.',
De='Deaanor:BAAALgAECgUJEQAAAA==.Deathcòw:BAABLgAECn8iAAMLAAcJ1SH0LQCAAgALAAcJ1SH0LQCAAgAMAAIJmgkKPgBZAAAAAA==.Detective:BAABLgAECn8XAAINAAkJCgvfOgBdAQANAAkJCgvfOgBdAQAAAA==.Deween:BAAALgADCgYJBgAAAA==.',
Di='Discord:BAAALgADCgYJBgAAAA==.',
Do='Dojoro:BAAALgAECgYJEgAAAA==.',
Dr='Draegare:BAABLgAECn8iAAIKAAgJpyU5AQDUAgAKAAgJpyU5AQDUAgAAAA==.Drdeer:BAAALgAECgQJBgAAAA==.Dread:BAAALgADCgUJBwAAAA==.Drittsz:BAAALgADCgIJBAAAAA==.Drumheller:BAAALgADCgkJDwAAAA==.',
Ed='Edwar:BAAALgADCgYJBgAAAA==.',
Ee='Eelecurb:BAAALgAECgQJCQAAAA==.',
El='Eligorra:BAAALgADCgEJAQAAAA==.',
Ep='Epicfury:BAAALgADCgEJAQAAAA==.',
Es='Eshmun:BAAALgAECgQJCAAAAA==.',
Et='Eternalx:BAAALgADCgEJAQAAAA==.Ethidris:BAAALgADCgQJBAABLgAECgkJDAAFAAAAAA==.',
Ev='Evang:BAAALgAECgYJCAAAAA==.Eve:BAAALgAECgYJCgABLgAECggJGgAKAJ0iAA==.Everd:BAAALgAECgYJCQAAAA==.',
Fa='Faelilia:BAAALgADCgUJBQAAAA==.',
Fe='Felzup:BAAALgADCgkJEgAAAA==.',
Fi='Fiametta:BAABLgAECn8UAAIIAAYJQxgDBAAhAQAIAAYJQxgDBAAhAQAAAA==.Finruil:BAAALgADCgYJCQAAAA==.',
Fl='Flent:BAAALgAECgYJCwAAAA==.Florisá:BAAALgADCgQJBAABLgAECgMJAwAFAAAAAA==.',
Fo='Forkingidiot:BAAALgADCgEJAQAAAA==.',
Fu='Funsize:BAAALgADCgcJBwAAAA==.',
Ga='Galindlianid:BAAALgAECgYJDAAAAA==.',
Ge='Geryn:BAAALgADCgMJAwAAAA==.Gesen:BAAALgADCgMJAwAAAA==.',
Gi='Gigaweenie:BAAALgADCgUJBQAAAA==.',
Gl='Glavien:BAAALgAECgYJEgAAAA==.',
Gr='Grienke:BAAALgADCgQJBAABLgAECgUJBwAFAAAAAA==.Grizzle:BAAALgADCgUJBQAAAA==.Grumpolbolt:BAABLgAECn8ZAAIOAAYJLRooJwC/AQAOAAYJLRooJwC/AQAAAA==.',
Ha='Haplo:BAAALgADCgEJAQAAAA==.Harnessme:BAAALgADCggJCwAAAA==.Harps:BAAALgADCgYJBgAAAA==.',
He='Hey:BAABLgAECn8lAAIPAAgJICEvCADyAgAPAAgJICEvCADyAgAAAA==.',
Ho='Horadin:BAAALgADCgkJEgAAAA==.',
Hu='Huntmeister:BAABLgAECn8dAAIQAAgJLSEIDQDWAgAQAAgJLSEIDQDWAgAAAA==.',
Ic='Iceehawt:BAAALgAECgYJEgAAAA==.',
Il='Ilharra:BAAALgADCgkJHAAAAA==.Ilililili:BAAALgADCgEJAQAAAA==.Illee:BAAALgAECgQJBQAAAA==.Illuminara:BAAALgADCgYJEQAAAA==.',
Im='Imdrood:BAAALgADCgMJAwAAAA==.Imturtle:BAABLgAECn8bAAMMAAgJwyDqBQDdAgAMAAgJwyDqBQDdAgALAAIJ6BAW/gB+AAAAAA==.',
In='Insømniadk:BAAALgAFFAEJAQABLgAFFAUJDQALADkbAA==.',
Is='Isshiny:BAAALgAECgYJDgAAAA==.',
Iu='Iupiter:BAAALgAECgMJCAAAAA==.',
Iy='Iyahlieairia:BAAALgADCgEJAQAAAA==.',
Iz='Izabeth:BAAALgAECgYJDwAAAA==.',
Ja='Jacaar:BAAALgADCgUJBQAAAA==.Jamella:BAAALgAECgYJCAAAAA==.',
Ka='Kaelynia:BAAALgADCgYJCgAAAA==.Kagosi:BAAALgAECgQJBwAAAA==.Kairn:BAAALgADCgcJBwAAAA==.Kalivath:BAAALgADCgQJBAAAAA==.Kardaa:BAAALgADCgEJAQAAAA==.Kat:BAAALgAECgYJEwAAAA==.Kawi:BAAALgADCgEJAQAAAA==.Kazakusan:BAAALgADCgUJAwAAAA==.',
Ki='Kiraneem:BAAALgAECgYJEgAAAA==.Kittie:BAABLgAECn8UAAIPAAcJswYgUwA5AQAPAAcJswYgUwA5AQAAAA==.',
Ko='Kotenok:BAAALgADCgYJDAAAAA==.',
Kr='Kreyaa:BAAALgAECgYJEQAAAA==.Krinj:BAABLgAECn8cAAILAAkJPxgvSAAbAgALAAkJPxgvSAAbAgAAAA==.Kristov:BAAALgAECgIJAgAAAA==.',
Ky='Kyarla:BAAALgAECgQJDwAAAA==.Kydo:BAAALgAECgQJDgAAAA==.',
La='Lamp:BAAALgAECgQJBAAAAA==.',
Le='Ledani:BAAALgAECgYJEQAAAA==.Leøna:BAAALgADCgEJAQAAAA==.',
Li='Liberi:BAAALgADCgEJAQAAAA==.Light:BAAALgAECgkJDAAAAA==.Lightwràth:BAAALgADCgMJAwAAAA==.Lincecum:BAAALgAECgYJDgABLgAECgUJBwAFAAAAAA==.Listen:BAABLgAECn8wAAIOAAgJhRdmBQCiAQAOAAgJhRdmBQCiAQAAAA==.',
Lo='Loachapoka:BAAALgADCgYJDQAAAA==.Lonedawg:BAAALgADCgEJAQAAAA==.Loweform:BAAALgADCgEJAQAAAA==.',
Lu='Lunâ:BAAALgAECgYJEgAAAA==.Luwud:BAAALgADCgcJEAAAAA==.',
Ly='Lyrei:BAAALgAECgYJEgAAAA==.',
Ma='Macfrost:BAAALgADCgUJBgAAAA==.Machiavelli:BAAALgADCgUJBQAAAA==.Maddox:BAAALgAECgQJBAAAAA==.Magichandz:BAAALgAECgYJCQAAAA==.Maikakx:BAAALgADCgUJAgAAAA==.Marsyx:BAAALgAECgkJEAAAAA==.Masfonos:BAAALgADCgEJAQAAAA==.Mayael:BAAALgAECgQJBQAAAA==.Maíkeru:BAAALgADCgEJAQAAAA==.',
Mc='Mcguffinss:BAABLgAECn8aAAMJAAgJViWJOAAqAgAJAAYJqiWJOAAqAgAIAAMJuiJ0JwAmAQAAAA==.',
Me='Medreaux:BAABLgAECn8iAAIRAAcJkhvkAwAHAgARAAcJkhvkAwAHAgAAAA==.Metalknyte:BAAALgAECgYJEgAAAA==.',
Mi='Miniknyte:BAAALgAECgYJDgAAAA==.Minotauren:BAAALgADCgYJBQAAAA==.Misskitty:BAAALgAECgYJDwAAAA==.',
Mo='Modnoc:BAAALgAECgYJCwAAAA==.Mollog:BAAALgADCgcJEAAAAA==.Mommii:BAAALgADCgEJAQABLgAECgEJAQAFAAAAAA==.Moonshine:BAAALgADCgUJCAAAAA==.Moonsz:BAAALgADCgkJKAAAAA==.',
Mu='Mugmug:BAAALgADCgUJBgAAAA==.',
My='Mychelle:BAAALgAECgYJEgAAAA==.',
Na='Nakryn:BAABLgAECn8bAAIDAAcJrQN3PwDDAAADAAcJrQN3PwDDAAAAAA==.Naluai:BAAALgADCgEJAQAAAA==.Nandami:BAAALgADCgIJAgAAAA==.Nary:BAAALgAECgMJAwAAAA==.Narysham:BAAALgADCgIJAgAAAA==.',
Ne='Neazth:BAAALgADCgEJAQAAAA==.Nezaeth:BAAALgADCgYJDAAAAA==.',
Ni='Nickoli:BAAALgAECgIJAgAAAA==.',
No='Nohnehn:BAAALgAECgEJAgAAAA==.Nojomoto:BAAALgADCgMJAwAAAA==.Norabel:BAAALgAECgMJAwAAAA==.',
Ny='Nyra:BAABLgAECn8UAAIQAAYJXBYuSQCOAQAQAAYJXBYuSQCOAQAAAA==.',
['Nø']='Nøxxi:BAABLgAECn8dAAIIAAgJwRG7DwDSAQAIAAgJwRG7DwDSAQAAAA==.',
Oc='Ocon:BAAALgADCgUJBQAAAA==.',
Ok='Okbloomer:BAAALgAECgcJEgAAAA==.',
Op='Optometrist:BAAALgADCgcJBwAAAA==.',
Or='Orckeferal:BAAALgADCgYJCQABLgAFFAUJEgASAMYiAA==.Oriel:BAAALgAECgYJEgAAAA==.Orthein:BAAALgADCgUJBQABLgADCgYJCgAFAAAAAA==.',
Pa='Pawarwar:BAAALgADCgMJAwAAAA==.',
Ph='Phindin:BAAALgAECgYJEgAAAA==.',
Po='Poc:BAAALgAECgUJBQAAAA==.Pokoko:BAAALgADCgUJBgAAAA==.',
Pr='Priblet:BAAALgADCgcJBwAAAA==.Primo:BAAALgAECgEJAgAAAA==.Prinsana:BAAALgAECgYJEgAAAA==.',
Pu='Purged:BAAALgAECgYJDwAAAA==.Purquis:BAAALgAECgEJAQAAAA==.',
Ra='Ragnus:BAAALgADCgEJAQAAAA==.Ralphie:BAAALgADCgcJAQAAAA==.Rasen:BAAALgAECgIJAgAAAA==.Rawfalafel:BAAALgAECgcJCQAAAA==.',
Re='Reaperlord:BAAALgAECgYJCAAAAA==.',
Rl='Rllybuffnerd:BAAALgADCgEJAQAAAA==.',
Ro='Rodikus:BAABLgAECn8bAAMRAAYJFCE7FAA8AgARAAYJFCE7FAA8AgAGAAYJKAjTDgAJAQAAAA==.Rootbeer:BAAALgADCgYJBgAAAA==.Rorax:BAAALgAECgYJBgAAAA==.Rosanna:BAAALgAECgQJBQAAAA==.',
Rp='Rprunner:BAAALgAECgUJBQABLgAECgcJEwAFAAAAAA==.',
Sa='Saiaa:BAAALgAECgYJCAAAAA==.Sakeena:BAAALgADCgEJAQAAAA==.Samará:BAAALgAECgIJBgAAAA==.Sarleigh:BAAALgAECgQJBAAAAA==.Sattia:BAABLgAECn8ZAAITAAcJ/ATMeADuAAATAAcJ/ATMeADuAAAAAA==.',
Sc='Scampington:BAAALgADCgYJCwAAAA==.',
Se='Sertzert:BAAALgAECgYJEAAAAA==.',
Sh='Sharrow:BAAALgADCggJEQAAAA==.Shiggy:BAAALgAECgIJAgAAAA==.Shinokami:BAAALgAECgYJCAAAAA==.Shoto:BAAALgADCgEJAQAAAA==.',
Si='Silentninjaa:BAABLgAECn8WAAISAAgJ3hEGKAAdAgASAAgJ3hEGKAAdAgAAAA==.Silque:BAAALgAECgMJAwAAAA==.Simphunter:BAEBLgAECn8YAAIUAAYJwxb7IQD+AAAUAAYJwxb7IQD+AAAAAA==.Sinchan:BAAALgADCgEJAQAAAA==.Sindaea:BAAALgADCgYJBgAAAA==.Sinfel:BAAALgAECgYJEgAAAA==.Sit:BAAALgAECgMJBgAAAA==.',
Sk='Skall:BAAALgADCgYJBQAAAA==.Skoree:BAABLgAECn8ZAAIUAAkJWx+8GQC6AgAUAAkJWx+8GQC6AgAAAA==.',
So='Soluna:BAAALgADCgYJBgAAAA==.Sonett:BAAALgADCgEJAQAAAA==.',
Sp='Splunk:BAAALgAECgUJBQABLgAECgkJFwANAAoLAA==.Spânky:BAAALgAECgYJEQAAAA==.',
Sq='Squiggles:BAAALgAECgYJBgAAAA==.',
St='Staggerdaddy:BAAALgADCgYJBgAAAA==.Stariya:BAAALgADCgEJAQAAAA==.Stormkraa:BAAALgAECgYJBgAAAA==.Strawyà:BAAALgADCgQJBwABLgAECggJFgAVABQaAA==.Strawyæ:BAABLgAECn8WAAIVAAgJFBrKBwBgAgAVAAgJFBrKBwBgAgAAAA==.Strike:BAAALgAECgYJCAABLgAECgcJHQAWAPsOAA==.',
Su='Sugerfree:BAAALgAECgQJBgAAAA==.',
Ta='Taleranor:BAAALgADCgkJGAAAAA==.Tallaeya:BAAALgAECgIJAgAAAA==.Tamerizer:BAABLgAECn8WAAMXAAcJIg/OBwA4AQAYAAYJ8xDuQwBFAQAXAAcJAwXOBwA4AQAAAA==.',
Te='Tealera:BAAALgAECgMJAwAAAA==.Teejrath:BAAALgAECgEJAQAAAA==.Teekeez:BAAALgAECgYJDgAAAA==.Terup:BAAALgADCgUJBQAAAA==.',
Th='Theodorel:BAAALgADCgcJDQAAAA==.Thillarys:BAAALgADCgYJBgAAAA==.Thirge:BAAALgAECgYJEwAAAA==.Thrushbeard:BAAALgADCgcJBwAAAA==.',
To='Tokas:BAAALgAECgIJAgAAAA==.Tolak:BAAALgAECgQJBgAAAA==.Torturousôwl:BAAALgAECgYJCwAAAA==.',
Tr='Traaze:BAAALgAECgIJAgAAAA==.Tralle:BAAALgAECgMJAwAAAA==.Trisky:BAAALgAECgYJEAAAAA==.Trissa:BAAALgADCgcJEQAAAA==.Trolldax:BAAALgADCgUJBwABLgAECgMJAwAFAAAAAA==.Trydént:BAAALgADCgEJAQAAAA==.',
Tu='Tunip:BAAALgAECgIJAgAAAA==.Turtle:BAAALgAECgMJAwAAAA==.',
Ul='Ulric:BAAALgADCgkJEgAAAA==.',
Va='Vaceriss:BAAALgADCgYJBgAAAA==.Valatar:BAAALgADCgcJCgAAAA==.Valdrakkquin:BAABLgAECn8cAAIZAAkJfxxpBgCRAgAZAAkJfxxpBgCRAgAAAA==.Valtreya:BAAALgADCgYJBgAAAA==.',
Ve='Vegito:BAAALgAECgUJEQAAAA==.Veramoon:BAAALgADCgYJBgAAAA==.',
Vi='Victoriia:BAAALgADCggJCAAAAA==.Vistus:BAAALgAECgQJBAAAAA==.',
Vo='Void:BAAALgADCgQJBAABLgAECgYJEgAFAAAAAA==.Voidmeister:BAAALgAECgYJDgABLgAECggJHQAQAC0hAA==.Voin:BAABLgAECn8tAAMaAAkJqB80AwAqAwAaAAkJqB80AwAqAwASAAQJkg/icQDxAAAAAA==.Vorpine:BAABLgAECn8YAAMGAAgJmBNFHgDnAQAGAAcJkhVFHgDnAQAHAAEJEwqFWgAtAAAAAA==.',
Vs='Vs:BAACLgAFFH8GAAILAAMJ2xIpJQABAQALAAMJ2xIpJQABAQAuAAQKfxQAAgsACAnXIKZSAPoBAAsACAnXIKZSAPoBAAEuAAUUBgkZABQAYyYA.',
Wa='Warcockeh:BAAALgADCgUJBQAAAA==.Watermelon:BAAALgAECgcJEgAAAA==.',
Wi='Wirhl:BAAALgAECgQJBQAAAA==.',
Wo='Wolfrik:BAAALgADCggJEAAAAA==.Worthatry:BAAALgAECgYJDAAAAA==.',
Wy='Wyn:BAABLgAECn8VAAIKAAYJFSGaDADLAQAKAAYJFSGaDADLAQAAAA==.',
Xa='Xalbit:BAAALgAECgYJEgAAAA==.Xanthrash:BAAALgADCgYJCgAAAA==.Xantia:BAABLgAECn8gAAITAAgJIhfpBAA2AgATAAgJIhfpBAA2AgAAAA==.Xaraena:BAABLgAECn8cAAIQAAkJXxr4KAATAgAQAAkJXxr4KAATAgAAAA==.Xaraimarra:BAAALgADCgQJBAAAAA==.Xariz:BAAALgAECgcJEgAAAA==.',
Xe='Xedd:BAAALgAECgQJBQAAAA==.',
Xy='Xyndrä:BAAALgADCgYJBgAAAA==.',
Za='Zaizel:BAAALgADCgUJBQABLgAFFAQJCAAbAFkaAA==.Zathennyx:BAAALgADCgYJBgABLgAECgMJAwAFAAAAAA==.',
Ze='Zercus:BAAALgAFFAIJAgAAAA==.',
Zh='Zhryla:BAAALgADCgUJCQAAAA==.',
Zl='Zleakara:BAAALgADCgQJBAAAAA==.Zleako:BAAALgADCgMJAwAAAA==.',
['Ðr']='Ðread:BAAALgAECgYJCAAAAA==.',
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

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

local lookup = {'Rogue-Assassination','Shaman-Elemental','Unknown-Unknown','Mage-Frost','Mage-Fire','Druid-Feral','Priest-Shadow','Priest-Discipline','Druid-Restoration','Warlock-Destruction','Warlock-Demonology','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Retribution','DeathKnight-Unholy','DeathKnight-Blood','Monk-Brewmaster','Rogue-Subtlety','Shaman-Restoration','Priest-Holy','DemonHunter-Devourer','Warrior-Fury','Paladin-Protection','Monk-Windwalker','DemonHunter-Havoc','Hunter-Survival','Paladin-Holy','Shaman-Enhancement','Warrior-Protection','Monk-Mistweaver','Evoker-Devastation',}
local provider = {region='US',realm='KirinTor',name='US',type='weekly',zone=46,date='2026-05-01',data={Ac='Acallia:BAAALgAECgEJAQAAAA==.Achkmed:BAAALgAECgkJEgAAAA==.',
Ae='Aelynis:BAABLgAECn8fAAIBAAkJPQ+WCADFAQABAAkJPQ+WCADFAQAAAA==.',
Ak='Akalon:BAABLgAECn8uAAICAAgJ+AhMHQAsAQACAAgJ+AhMHQAsAQAAAA==.',
Al='Alara:BAAALgADCgEJAQABLgAECgQJBwADAAAAAA==.Aldrus:BAAALgADCgYJBgAAAA==.Allfrost:BAAALgAECgMJBAAAAA==.',
Am='Amanthelia:BAAALgADCgUJBQAAAA==.',
An='Annerose:BAAALgAECgYJDAAAAA==.Anthir:BAAALgADCgEJAgAAAA==.',
Ao='Aoeina:BAABLgAECn8oAAMEAAgJtRO9KQC9AQAEAAgJtRO9KQC9AQAFAAEJZQNmCQApAAAAAA==.',
Ap='Apollo:BAAALgAECgQJBAAAAA==.',
Aq='Aquinas:BAAALgAECgQJBAABLgAECgYJFAAGAFQjAA==.',
Ar='Arcanelotus:BAAALgADCgUJBQAAAA==.Arcás:BAAALgADCgYJBgAAAA==.Ariaves:BAABLgAECn8gAAMHAAkJExcsEQCAAQAHAAkJExcsEQCAAQAIAAQJugjQPgC3AAAAAA==.Arilea:BAAALgADCgkJEgAAAA==.Arioriaa:BAAALgAECgYJDgAAAA==.Arlind:BAAALgADCggJFgAAAA==.',
As='Asenath:BAAALgADCgEJAQAAAA==.Asoeclya:BAAALgADCgIJAgAAAA==.',
At='Atanatari:BAAALgADCgcJFQABLgADCggJIgADAAAAAA==.Attonix:BAAALgAECgEJAQAAAA==.',
Az='Azem:BAAALgADCggJEwAAAA==.Azixarid:BAAALgADCgkJEgAAAA==.Azurdrache:BAAALgAECgEJAQAAAA==.',
Ba='Baldur:BAAALgADCgcJDAAAAA==.Baratheøn:BAABLgAECn8VAAIJAAYJbhnrHwCBAQAJAAYJbhnrHwCBAQAAAA==.Bassotan:BAAALgAECgYJBgAAAA==.Battleares:BAAALgAECgUJBQAAAA==.',
Be='Beasttoken:BAAALgADCgUJBQAAAA==.Beleva:BAABLgAECn8XAAIKAAYJBwcQDQDUAAAKAAYJBwcQDQDUAAAAAA==.',
Bi='Bigstan:BAAALgAECgQJCAAAAA==.Bilbobagging:BAAALgADCgcJEQAAAA==.Bilx:BAAALgAECgYJCwAAAA==.Biromong:BAAALgAECgMJBQAAAA==.',
Bl='Blackendmoon:BAAALgAECgMJBAAAAA==.Blackløtus:BAAALgADCgkJBwAAAA==.Bloodknight:BAAALgADCgEJAQAAAA==.Bluebeary:BAAALgAECgMJAwAAAA==.Bluelocks:BAABLgAECn8bAAMKAAgJmAh7HgBcAQAKAAgJmAh7HgBcAQALAAEJSwJbwAAnAAAAAA==.Bluéyes:BAAALgADCgUJBQAAAA==.Blvckscvl:BAABLgAECn8aAAMMAAgJ5hvuFgCBAgAMAAgJ5hvuFgCBAgANAAEJNARlkQApAAAAAA==.Blynna:BAAALgADCgcJCQAAAA==.',
Bo='Bohemond:BAAALgADCgcJBwAAAA==.',
Br='Broadleaf:BAAALgAECgQJCQAAAA==.',
Bu='Burnttoast:BAAALgADCgMJAwABLgAECgkJEgADAAAAAA==.',
Ca='Calinai:BAAALgADCgkJDgAAAA==.Catastrophi:BAAALgADCgEJAQAAAA==.Catastrophie:BAAALgAECgYJEQAAAA==.',
Ch='Chiarakai:BAAALgADCgYJCgAAAA==.',
Cl='Claudeena:BAAALgADCgkJEgAAAA==.',
Co='Coswell:BAAALgADCgkJCQAAAA==.',
Cr='Creeder:BAABLgAECn8fAAIOAAkJPQ8DdACTAQAOAAkJPQ8DdACTAQAAAA==.Crm:BAAALgADCgUJBQAAAA==.',
Cy='Cynise:BAAALgADCgcJDQAAAA==.',
Da='Dagoland:BAAALgAECgMJAwAAAA==.',
De='Deaanor:BAAALgAECgUJEQAAAA==.Deathcòw:BAABLgAECn8sAAMPAAgJByQwBQDTAgAPAAgJByQwBQDTAgAQAAIJmgkEPgBZAAAAAA==.Detective:BAABLgAECn8XAAIRAAkJCgvXOgBdAQARAAkJCgvXOgBdAQAAAA==.Deween:BAAALgADCgYJBgAAAA==.',
Di='Discord:BAAALgADCgYJBgAAAA==.',
Do='Dojoro:BAABLgAECn8YAAIRAAYJ5xnoEQB9AQARAAYJ5xnoEQB9AQAAAA==.Dora:BAAALgAECgEJAQAAAA==.',
Dr='Draegare:BAABLgAECn8qAAIOAAgJpyXjBQBuAwAOAAgJpyXjBQBuAwAAAA==.Drdeer:BAAALgAECgQJBgAAAA==.Dread:BAAALgADCgUJBwAAAA==.Drittsz:BAAALgADCgIJBAAAAA==.Drumheller:BAAALgADCgkJFAAAAA==.',
Ed='Edwar:BAAALgADCgYJBgAAAA==.',
Ee='Eekumbokum:BAAALgAECgEJAQAAAA==.Eelecurb:BAAALgAECgYJDgAAAA==.',
El='Eligorra:BAAALgADCgEJAQAAAA==.',
Ep='Epicfury:BAAALgADCgEJAQAAAA==.',
Es='Eshmun:BAAALgAECgUJDQAAAA==.',
Et='Eternalx:BAAALgAECgMJBAAAAA==.Ethidris:BAAALgADCgQJBAABLgAECgkJEgADAAAAAA==.',
Ev='Evang:BAAALgAECgYJDAAAAA==.Eve:BAAALgAECgYJDAABLgAECggJGgAOAJ0iAA==.Everd:BAAALgAECgYJCwAAAA==.',
Fa='Faelilia:BAAALgADCgUJBQAAAA==.',
Fe='Felorana:BAAALgADCgYJBgAAAA==.Felzup:BAAALgADCgkJEgAAAA==.',
Fi='Fiametta:BAABLgAECn8aAAIKAAYJTBz/AwCjAQAKAAYJTBz/AwCjAQAAAA==.Finruil:BAAALgADCgYJCQAAAA==.',
Fl='Flent:BAABLgAECn8aAAINAAgJKwswBwBzAQANAAgJKwswBwBzAQAAAA==.Florisá:BAAALgADCgQJBAABLgAECgMJAwADAAAAAA==.',
Fo='Forkingidiot:BAAALgADCgEJAQAAAA==.',
Fu='Funsize:BAAALgADCgkJEAAAAA==.',
Ga='Galindlianid:BAAALgAECgYJEgAAAA==.',
Ge='Geryn:BAAALgADCgMJAwAAAA==.Gesen:BAAALgADCgYJBgAAAA==.',
Gi='Gigaweenie:BAAALgADCgUJBQAAAA==.',
Gl='Glavien:BAABLgAECn8YAAIOAAYJXg6fTwAeAQAOAAYJXg6fTwAeAQAAAA==.',
Gr='Grandstorm:BAAALgADCgIJAgAAAA==.Grienke:BAAALgADCgQJBAABLgAECgYJDgADAAAAAA==.Grizzle:BAAALgADCgUJBQAAAA==.Grumpolbolt:BAABLgAECn8eAAISAAgJ9RloDgCFAQASAAgJ9RloDgCFAQAAAA==.',
Ha='Haenin:BAAALgAECgEJAQAAAA==.Haplo:BAAALgAECgMJBAAAAA==.Harnessme:BAAALgADCggJCwAAAA==.Harps:BAAALgADCgYJBgAAAA==.',
He='Hey:BAABLgAECn8sAAITAAgJICExCADyAgATAAgJICExCADyAgAAAA==.',
Ho='Homble:BAAALgADCgIJAgAAAA==.Horadin:BAAALgADCgkJEgAAAA==.',
Hu='Huntmeister:BAABLgAECn8dAAIMAAgJLSEHDQDWAgAMAAgJLSEHDQDWAgAAAA==.',
Ic='Iceehawt:BAABLgAECn8XAAIPAAYJUyI0HADfAQAPAAYJUyI0HADfAQAAAA==.',
Il='Ilharra:BAAALgAECgMJAwAAAA==.Ilililili:BAAALgAECgMJBAAAAA==.Illee:BAAALgAECgQJBgAAAA==.Illuminara:BAAALgADCgYJEQAAAA==.',
Im='Imdrood:BAAALgADCgMJAwAAAA==.Imturtle:BAABLgAECn8bAAMQAAgJwyDpBQDdAgAQAAgJwyDpBQDdAgAPAAIJ6BAu/gB+AAAAAA==.',
In='Insømniadk:BAAALgAFFAIJAgABLgAFFAUJDQAPADkbAA==.',
Is='Isshiny:BAABLgAECn8UAAIOAAYJZxoeMgB6AQAOAAYJZxoeMgB6AQAAAA==.',
Iu='Iupiter:BAAALgAECgUJDQAAAA==.',
Iy='Iyahlieairia:BAAALgADCgEJAQAAAA==.',
Iz='Izabeth:BAABLgAECn8VAAIEAAYJhgtGawADAQAEAAYJhgtGawADAQAAAA==.',
Ja='Jacaar:BAAALgADCgUJBQAAAA==.Jamella:BAAALgAECgYJDgAAAA==.',
Je='Jessabella:BAAALgADCgIJAgAAAA==.',
Ji='Jigles:BAAALgADCgEJAQAAAA==.',
Ka='Kaelynia:BAAALgADCgYJCgAAAA==.Kagosi:BAAALgAECgQJBwAAAA==.Kairn:BAAALgADCgcJBwAAAA==.Kalivath:BAAALgADCgQJBAAAAA==.Kardaa:BAAALgADCgEJAQAAAA==.Kat:BAAALgAECgYJEwAAAA==.Kawi:BAAALgADCgEJAQAAAA==.Kazakusan:BAAALgADCgUJAwAAAA==.',
Ki='Kiraneem:BAABLgAECn8YAAMMAAYJ1BpdNgDVAQAMAAYJ1BpdNgDVAQANAAEJ2wGVlwAgAAAAAA==.Kittie:BAABLgAECn8bAAITAAcJ5Ag7LQAPAQATAAcJ5Ag7LQAPAQAAAA==.',
Ko='Kotenok:BAAALgAECgYJBgAAAA==.',
Kr='Kreyaa:BAAALgAECgYJEwAAAA==.Krinj:BAABLgAECn8jAAIPAAkJJBsRFQASAgAPAAkJJBsRFQASAgAAAA==.Kristov:BAAALgAECgIJAgAAAA==.',
Ky='Kyarla:BAABLgAECn8UAAIUAAQJORXhIwDfAAAUAAQJORXhIwDfAAAAAA==.Kydo:BAABLgAECn8YAAIEAAcJThJPOQCDAQAEAAcJThJPOQCDAQAAAA==.',
['Kø']='Køe:BAAALgADCgQJBAABLgAECgEJAQADAAAAAA==.',
La='Lamp:BAAALgAECgQJBQAAAA==.',
Le='Ledani:BAABLgAECn8XAAIHAAYJLhCXGAA5AQAHAAYJLhCXGAA5AQAAAA==.Leøna:BAAALgADCgEJAQAAAA==.',
Li='Liberi:BAAALgADCgEJAQAAAA==.Light:BAAALgAECgkJDAAAAA==.Lightwràth:BAAALgADCgMJAwAAAA==.Lincecum:BAAALgAECggJEAABLgAECgYJDgADAAAAAA==.Lioni:BAAALgADCgkJCQAAAA==.Listen:BAABLgAECn8/AAISAAgJAhtCBQAxAgASAAgJAhtCBQAxAgAAAA==.',
Lo='Loachapoka:BAAALgADCgYJDQAAAA==.Lohith:BAAALgAECgQJBAAAAA==.Lonedawg:BAAALgAECgMJBAAAAA==.Loweform:BAAALgADCgEJAQAAAA==.',
Lu='Lunâ:BAABLgAECn8YAAIIAAYJXhsqCwDaAQAIAAYJXhsqCwDaAQAAAA==.Luwud:BAAALgADCgcJEAAAAA==.',
Ly='Lyrei:BAABLgAECn8TAAIVAAYJlhXZKgA6AQAVAAYJlhXZKgA6AQAAAA==.',
Ma='Macfrost:BAAALgADCgUJBgAAAA==.Machiavelli:BAAALgADCgUJBQAAAA==.Maddox:BAAALgAECgYJCgAAAA==.Magichandz:BAAALgAECgYJCQAAAA==.Maikakx:BAAALgAECgEJAQAAAA==.Marsyx:BAABLgAECn8XAAIUAAkJ8BvABACBAgAUAAkJ8BvABACBAgAAAA==.Masfonos:BAAALgADCgEJAQAAAA==.Mayael:BAAALgAECgQJBQAAAA==.Maíkeru:BAAALgADCgEJAQAAAA==.',
Mc='Mcguffinss:BAABLgAECn8dAAMLAAkJdiVyHwC4AQALAAcJwiVyHwC4AQAKAAMJuiJzJwAmAQAAAA==.',
Me='Medreaux:BAABLgAECn8xAAIUAAgJyBvOBQBjAgAUAAgJyBvOBQBjAgAAAA==.Metalknyte:BAABLgAECn8YAAIQAAYJ4wzFFgDIAAAQAAYJ4wzFFgDIAAAAAA==.',
Mi='Miniknyte:BAAALgAECgYJDgAAAA==.Minotauren:BAAALgADCgYJBQAAAA==.Misskitty:BAABLgAECn8UAAIGAAYJVCP+AwD4AQAGAAYJVCP+AwD4AQAAAA==.',
Mo='Modnoc:BAAALgAECgYJDAAAAA==.Mollog:BAAALgADCgcJEAAAAA==.Mommii:BAAALgADCgEJAQABLgAECgEJAQADAAAAAA==.Moondanas:BAAALgADCgMJAwAAAA==.Moonshine:BAAALgADCgUJCAAAAA==.Moonsz:BAAALgADCgkJMQAAAA==.',
Mu='Mugmug:BAAALgADCgUJBgAAAA==.',
My='Mychelle:BAABLgAECn8YAAINAAYJtBS5CABNAQANAAYJtBS5CABNAQAAAA==.',
Na='Nakryn:BAABLgAECn8iAAIEAAcJ/gOwegDgAAAEAAcJ/gOwegDgAAAAAA==.Naluai:BAAALgADCgEJAQAAAA==.Nandami:BAAALgADCgIJAgAAAA==.Nary:BAAALgAECgkJCgAAAA==.Narysham:BAAALgADCgIJAgAAAA==.',
Ne='Neazth:BAAALgADCgEJAQAAAA==.Nezaeth:BAAALgADCggJFAAAAA==.Nezum:BAAALgADCgYJBgAAAA==.',
Ni='Nickoli:BAAALgAECgIJAgAAAA==.Nightshade:BAAALgADCgkJCQAAAA==.',
No='Nohnehn:BAAALgAECgEJAwAAAA==.Nojomoto:BAAALgADCgMJAwAAAA==.Norabel:BAAALgAECgQJBwAAAA==.',
Ny='Nyra:BAABLgAECn8cAAIMAAgJxRdqEAATAgAMAAgJxRdqEAATAgAAAA==.',
['Nø']='Nøxxi:BAABLgAECn8fAAIKAAgJgxORBQBtAQAKAAgJgxORBQBtAQAAAA==.',
Oc='Ocon:BAAALgADCgUJBQAAAA==.',
Ok='Okbloomer:BAAALgAECgcJEwAAAA==.',
Op='Optometrist:BAAALgADCgcJBwAAAA==.',
Or='Orckeferal:BAAALgADCgYJCQABLgAFFAYJGAAWAPkdAA==.Oriel:BAABLgAECn8YAAIIAAYJ6grKFwAuAQAIAAYJ6grKFwAuAQAAAA==.Orthein:BAAALgADCgYJCAABLgAECgEJAQADAAAAAA==.',
Pa='Pawarwar:BAAALgADCgMJAwAAAA==.',
Ph='Phindin:BAABLgAECn8aAAMCAAgJiw+6HQApAQACAAcJogy6HQApAQATAAEJ4QHLaQAlAAAAAA==.',
Po='Poc:BAAALgAECgYJCQAAAA==.Pokoko:BAAALgADCgUJBgAAAA==.',
Pr='Priblet:BAAALgADCgcJBwAAAA==.Primo:BAAALgAECgYJCAAAAA==.Prinsana:BAABLgAECn8YAAIXAAYJ1BFNEQDvAAAXAAYJ1BFNEQDvAAAAAA==.',
Pu='Purged:BAABLgAECn8WAAITAAcJXgYALwAGAQATAAcJXgYALwAGAQAAAA==.Purquis:BAAALgAECgEJAQAAAA==.',
Ra='Ragnus:BAAALgADCgEJAQAAAA==.Ralphie:BAAALgADCgcJAQAAAA==.Rasen:BAAALgAECgIJAgAAAA==.Ratheer:BAAALgAECgQJBAABLgAECgkJHQALAHYlAA==.Rawfalafel:BAAALgAECggJEQAAAA==.',
Re='Reaperlord:BAAALgAECgYJDgAAAA==.',
Rl='Rllybuffnerd:BAAALgADCgEJAQAAAA==.',
Ro='Rodikus:BAABLgAECn8cAAMUAAcJVh5AFAA8AgAUAAcJVh5AFAA8AgAHAAYJKAhaHQASAQAAAA==.Rootbeer:BAAALgADCgYJBgAAAA==.Rorax:BAAALgAECgYJDAAAAA==.Rosanna:BAAALgAECgQJBQAAAA==.',
Rp='Rprunner:BAAALgAECgUJBQABLgAECgcJFgAYAJwPAA==.',
Sa='Saiaa:BAAALgAECgYJCAAAAA==.Sakeena:BAAALgAECgMJBAAAAA==.Samará:BAAALgAECgIJBgAAAA==.Sarleigh:BAAALgAECgUJCQAAAA==.Sattia:BAABLgAECn8hAAIJAAgJvgWmNQAAAQAJAAgJvgWmNQAAAQAAAA==.',
Sc='Scampington:BAAALgADCgYJCwAAAA==.',
Se='Sertzert:BAABLgAECn8WAAIGAAYJYRh/CQBRAQAGAAYJYRh/CQBRAQAAAA==.',
Sh='Sharrow:BAAALgADCggJEQAAAA==.Shiggy:BAAALgAECgIJAgAAAA==.Shinokami:BAAALgAECgYJDgAAAA==.Shoto:BAAALgADCgEJAQAAAA==.',
Si='Silentninjaa:BAABLgAECn8WAAIWAAgJ3hEJKAAdAgAWAAgJ3hEJKAAdAgAAAA==.Silque:BAAALgAECgMJAwAAAA==.Simphunter:BAEBLgAECn8aAAIVAAYJchspHACLAQAVAAYJchspHACLAQAAAA==.Sinchan:BAAALgADCgEJAQAAAA==.Sindaea:BAAALgADCgYJBgAAAA==.Sinfel:BAABLgAECn8YAAIZAAYJVwhrFgDvAAAZAAYJVwhrFgDvAAAAAA==.Sit:BAAALgAECgUJCwAAAA==.',
Sk='Skall:BAAALgAECgEJAQAAAA==.Skoree:BAABLgAECn8cAAIVAAkJcCDAGQC5AgAVAAkJcCDAGQC5AgAAAA==.',
So='Soluna:BAAALgADCgYJBgAAAA==.Someonelse:BAAALgAECgMJAwAAAA==.Sonett:BAAALgAECgMJBAAAAA==.',
Sp='Splunk:BAAALgAECggJDAABLgAECgkJFwARAAoLAA==.Spânky:BAAALgAECgYJEQAAAA==.Spíké:BAAALgADCgkJCQAAAA==.',
Sq='Squiggles:BAAALgAECgYJDQAAAA==.',
St='Staggerdaddy:BAAALgADCgYJBgAAAA==.Stariya:BAAALgAECgMJBAAAAA==.Stormkraa:BAAALgAECgYJBgAAAA==.Strawyà:BAAALgADCgQJBwABLgAECggJFgAXABQaAA==.Strawyæ:BAABLgAECn8WAAIXAAgJFBrKBwBgAgAXAAgJFBrKBwBgAgAAAA==.Strike:BAAALgAECgYJCAAAAA==.',
Su='Sugerfree:BAAALgAECgYJDAAAAA==.',
Ta='Taleranor:BAAALgADCgkJIQAAAA==.Tallaeya:BAAALgAECgIJAgAAAA==.Tamerizer:BAABLgAECn8eAAMaAAgJyg7nDACRAQAaAAgJyAnnDACRAQANAAYJ8xDtQwBFAQAAAA==.',
Te='Tealera:BAAALgAECgMJAwAAAA==.Teejrath:BAAALgAECgEJAQAAAA==.Teekeez:BAABLgAECn8UAAIEAAYJ4QrweQDiAAAEAAYJ4QrweQDiAAAAAA==.Terup:BAAALgADCgUJBQAAAA==.',
Th='Theodorel:BAAALgADCgcJDQAAAA==.Thillarys:BAAALgAECgEJAQAAAA==.Thirge:BAABLgAECn8ZAAIWAAYJ8g5JIwAfAQAWAAYJ8g5JIwAfAQAAAA==.Thrushbeard:BAAALgADCgcJDgAAAA==.',
To='Tokas:BAAALgAECgIJAgAAAA==.Tolak:BAAALgAECgUJCwAAAA==.Torturousôwl:BAAALgAECgcJDAAAAA==.',
Tr='Traaze:BAAALgAECgYJCwAAAA==.Tralle:BAAALgAECgMJAwAAAA==.Trisky:BAABLgAECn8WAAIbAAYJtxfKFQCkAQAbAAYJtxfKFQCkAQAAAA==.Trissa:BAAALgADCgcJEQAAAA==.Trolldax:BAAALgADCgUJBwABLgAECgMJAwADAAAAAA==.Trydént:BAAALgAECgMJBAAAAA==.',
Tu='Tunip:BAAALgAECgIJAgAAAA==.Turtle:BAAALgAECgQJCQAAAA==.',
Ul='Ulric:BAAALgADCgkJEgAAAA==.',
Va='Vaceriss:BAAALgADCgYJBgAAAA==.Valatar:BAAALgADCgcJCgAAAA==.Valdrakkquin:BAABLgAECn8jAAIcAAkJjh7tAgAqAgAcAAkJjh7tAgAqAgAAAA==.Valtreya:BAAALgADCgYJBgAAAA==.',
Ve='Vegito:BAABLgAECn8XAAIWAAYJMQO+NwCoAAAWAAYJMQO+NwCoAAAAAA==.Veramoon:BAAALgADCgYJBgAAAA==.',
Vi='Victoriia:BAAALgADCggJCAAAAA==.Vistus:BAAALgAECgQJBAAAAA==.',
Vo='Void:BAAALgADCgQJBAABLgAECgYJGAANALQUAA==.Voidmeister:BAABLgAECn8WAAIVAAYJvhL4OAD/AAAVAAYJvhL4OAD/AAABLgAECggJHQAMAC0hAA==.Voin:BAABLgAECn81AAMdAAkJnCA2AwAqAwAdAAkJnCA2AwAqAwAWAAQJhRmdHQBEAQAAAA==.Vorpine:BAABLgAECn8YAAMHAAgJmBNNHgDnAQAHAAcJkhVNHgDnAQAIAAEJEwqHWgAtAAAAAA==.',
Vs='Vs:BAACLgAFFH8GAAIPAAMJ2xI6JQABAQAPAAMJ2xI6JQABAQAuAAQKfxUAAg8ACAnXIKdSAPoBAA8ACAnXIKdSAPoBAAEuAAUUBwkaABUA7iQA.',
Wa='Warcockeh:BAAALgADCgUJBQAAAA==.Watermelon:BAABLgAECn8YAAIeAAcJIhhfDgDBAQAeAAcJIhhfDgDBAQAAAA==.',
Wi='Wirhl:BAAALgAECgUJCgAAAA==.',
Wo='Wolfrik:BAAALgAECgUJAwAAAA==.Worthatry:BAAALgAECgYJDAAAAA==.',
Wy='Wyn:BAABLgAECn8bAAIOAAYJFSGhHwDMAQAOAAYJFSGhHwDMAQAAAA==.',
Xa='Xalbit:BAABLgAECn8YAAITAAYJaRP9IABdAQATAAYJaRP9IABdAQAAAA==.Xanthrash:BAAALgAECgEJAQAAAA==.Xantia:BAABLgAECn8oAAIJAAgJNReWDgAkAgAJAAgJNReWDgAkAgAAAA==.Xaraena:BAABLgAECn8fAAIMAAkJeBr1KAATAgAMAAkJeBr1KAATAgAAAA==.Xaraimarra:BAAALgADCgQJBAAAAA==.Xariz:BAAALgAECgcJEgAAAA==.',
Xe='Xedd:BAAALgAECgQJBQAAAA==.Xenlo:BAAALgAECgMJAwABLgAFFAMJBQAbANQcAA==.',
Xy='Xyndrä:BAAALgADCgYJBgAAAA==.',
Za='Zaizel:BAAALgADCgUJBQABLgAFFAUJDAAfAEAXAA==.Zathennyx:BAAALgADCgYJBgABLgAECgMJAwADAAAAAA==.',
Ze='Zercus:BAAALgAFFAIJBAAAAA==.',
Zh='Zhryla:BAAALgADCgUJCQAAAA==.',
Zl='Zleakara:BAAALgADCgQJBAAAAA==.Zleako:BAAALgADCgMJAwAAAA==.',
['Ðr']='Ðread:BAAALgAECgYJDQAAAA==.',
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

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

local lookup = {'Rogue-Assassination','Shaman-Elemental','Unknown-Unknown','Mage-Frost','Mage-Fire','Druid-Feral','Priest-Shadow','Priest-Discipline','Shaman-Restoration','Druid-Restoration','Warlock-Destruction','Warlock-Demonology','Hunter-BeastMastery','Hunter-Marksmanship','DeathKnight-Unholy','Paladin-Retribution','DeathKnight-Blood','Monk-Brewmaster','Rogue-Subtlety','Paladin-Protection','Priest-Holy','DemonHunter-Devourer','Druid-Balance','Warrior-Arms','Paladin-Holy','Monk-Windwalker','Warrior-Fury','DemonHunter-Havoc','Hunter-Survival','Shaman-Enhancement','Warrior-Protection','Monk-Mistweaver','Evoker-Devastation',}
local provider = {region='US',realm='KirinTor',name='US',type='weekly',zone=46,date='2026-05-08',data={Ac='Acallia:BAAALgAECgEJAQAAAA==.Achkmed:BAAALgAECgkJEwAAAA==.',
Ae='Aelynis:BAABLgAECn8hAAIBAAkJOg+VCADFAQABAAkJOg+VCADFAQAAAA==.',
Ak='Akalon:BAABLgAECn8uAAICAAgJ+QiOJwAgAQACAAgJ+QiOJwAgAQAAAA==.',
Al='Alara:BAAALgADCgEJAQABLgAECgQJBwADAAAAAA==.Aldrus:BAAALgADCgYJBgAAAA==.Allfrost:BAAALgAECgMJBAAAAA==.',
Am='Amanthelia:BAAALgADCgUJBQAAAA==.',
An='Annerose:BAAALgAECgcJEQAAAA==.Anthir:BAAALgADCgEJAgAAAA==.',
Ao='Aoeina:BAABLgAECn8xAAMEAAkJXBNMIwAZAgAEAAkJXBNMIwAZAgAFAAEJiAPxCwApAAAAAA==.',
Ap='Apollo:BAAALgAECgQJBAAAAA==.',
Aq='Aquinas:BAAALgAECgQJBAABLgAECgYJFAAGAFMjAA==.',
Ar='Arcanelotus:BAAALgADCgUJBQAAAA==.Arcás:BAAALgADCgYJBgAAAA==.Ariaves:BAABLgAECn8jAAMHAAkJGReMEwCoAQAHAAkJGReMEwCoAQAIAAQJugjSPgC3AAAAAA==.Arilea:BAAALgADCgkJEgAAAA==.Arioriaa:BAABLgAECn8VAAIJAAcJ8wm5NwAqAQAJAAcJ8wm5NwAqAQAAAA==.Arlind:BAAALgAECgIJAgAAAA==.',
As='Asenath:BAAALgADCgEJAQAAAA==.Asoeclya:BAAALgADCgIJAgAAAA==.',
At='Atanatari:BAAALgADCgcJFQABLgAECgIJAgADAAAAAA==.Attonix:BAAALgAECgEJAQAAAA==.',
Az='Azem:BAAALgADCggJEwAAAA==.Azixarid:BAAALgADCgkJEgAAAA==.Azurdrache:BAAALgAECgEJAQAAAA==.',
Ba='Baldur:BAAALgADCgcJDAAAAA==.Baratheøn:BAABLgAECn8cAAIKAAcJ9ReCJAClAQAKAAcJ9ReCJAClAQAAAA==.Bassotan:BAAALgAECgcJBgAAAA==.Battleares:BAAALgAECgUJCgAAAA==.',
Be='Beasttoken:BAAALgADCgUJBQAAAA==.Beleva:BAABLgAECn8eAAILAAYJpwkBDwDjAAALAAYJpwkBDwDjAAAAAA==.',
Bi='Bigstan:BAAALgAECgcJDwAAAA==.Bilbobagging:BAAALgADCgcJEQAAAA==.Bilx:BAAALgAECgYJCwAAAA==.Biromong:BAAALgAECgMJBgAAAA==.',
Bl='Blackendmoon:BAAALgAECgMJBgAAAA==.Blackløtus:BAAALgAECgYJAgAAAA==.Bloodknight:BAAALgADCgEJAQAAAA==.Bloodnight:BAAALgAECgIJAgAAAA==.Bluebeary:BAAALgAECgMJAwAAAA==.Bluelocks:BAABLgAECn8fAAMLAAgJjAt4HgBcAQALAAgJjAt4HgBcAQAMAAEJTgKu7AAnAAAAAA==.Bluéyes:BAAALgAECgQJBAAAAA==.Blvckscvl:BAABLgAECn8hAAMNAAgJvBy8FAAqAgANAAgJvBy8FAAqAgAOAAEJNQR4kQApAAAAAA==.Blynna:BAAALgADCgcJCQAAAA==.',
Bo='Bohemond:BAAALgADCgcJBwAAAA==.',
Br='Broadleaf:BAAALgAECgQJCQAAAA==.',
Bu='Burnttoast:BAAALgADCgMJAwABLgAECgkJEwADAAAAAA==.',
Ca='Caledra:BAAALgADCgkJCQAAAA==.Calinai:BAAALgADCgkJDgAAAA==.Catastrophi:BAAALgADCgEJAQAAAA==.Catastrophie:BAABLgAECn8XAAIPAAYJERGLWAA2AQAPAAYJERGLWAA2AQAAAA==.',
Ce='Cellturin:BAAALgAECgcJBwAAAA==.',
Ch='Chiarakai:BAAALgADCgYJCgAAAA==.',
Cl='Claudeena:BAAALgADCgkJEgAAAA==.',
Co='Coswell:BAAALgADCgkJCQAAAA==.',
Cr='Creeder:BAABLgAECn8jAAIQAAkJuBAGdACTAQAQAAkJuBAGdACTAQAAAA==.Crm:BAAALgADCgUJBQAAAA==.',
Cy='Cynise:BAAALgADCgcJDQAAAA==.',
Da='Dagoland:BAAALgAECgMJAwAAAA==.',
De='Deaanor:BAAALgAECgUJEQAAAA==.Deathcòw:BAABLgAECn80AAMPAAgJ3CQBBwDsAgAPAAgJ3CQBBwDsAgARAAIJmgkFPgBZAAAAAA==.Detective:BAABLgAECn8XAAISAAkJFQvSOgBdAQASAAkJFQvSOgBdAQAAAA==.Deween:BAAALgADCgYJBgAAAA==.',
Di='Discord:BAAALgADCgYJBgAAAA==.',
Do='Dojoro:BAABLgAECn8cAAISAAgJzBfsDAD1AQASAAgJzBfsDAD1AQAAAA==.Dora:BAAALgAECgEJAQAAAA==.',
Dr='Draegare:BAABLgAECn8qAAIQAAgJqCXiBQBuAwAQAAgJqCXiBQBuAwAAAA==.Drdeer:BAAALgAECgYJCgAAAA==.Dread:BAAALgADCgUJBwAAAA==.Drittsz:BAAALgADCgIJBAAAAA==.Drumheller:BAAALgADCgkJFAAAAA==.',
Ed='Edwar:BAAALgADCgYJBgAAAA==.',
Ee='Eekumbokum:BAAALgAECgEJAQAAAA==.Eelecurb:BAAALgAECgYJDgAAAA==.',
El='Eligorra:BAAALgADCgEJAQAAAA==.',
Ep='Epicfury:BAAALgADCgEJAQAAAA==.',
Es='Eshmun:BAAALgAECgUJDQAAAA==.',
Et='Eternalx:BAAALgAECgMJBAAAAA==.Ethidris:BAAALgADCgQJBAABLgAECgkJEwADAAAAAA==.',
Ev='Evang:BAAALgAECgcJEwAAAA==.Eve:BAAALgAECgYJDAABLgAECgkJHQAQAEYjAA==.Everd:BAABLgAECn8YAAIQAAgJIgimUwBMAQAQAAgJIgimUwBMAQAAAA==.',
Fa='Faelilia:BAAALgADCgUJBQAAAA==.',
Fe='Felorana:BAAALgADCgYJBgAAAA==.Felzup:BAAALgADCgkJEgAAAA==.',
Fi='Fiametta:BAABLgAECn8gAAILAAYJgh6rBAC+AQALAAYJgh6rBAC+AQAAAA==.Finruil:BAAALgADCgYJCQAAAA==.Fireburst:BAAALgAECgIJAgAAAA==.',
Fl='Flent:BAABLgAECn8bAAMOAAgJKQvkCQBZAQAOAAgJKQvkCQBZAQANAAEJqQaHwgAzAAAAAA==.Florisá:BAAALgADCgQJBAABLgAECgMJAwADAAAAAA==.',
Fo='Forkingidiot:BAAALgADCgEJAQAAAA==.',
Fu='Funsize:BAAALgAECgUJBQAAAA==.',
Ga='Galindlianid:BAAALgAECgcJEwAAAA==.',
Ge='Geryn:BAAALgADCgMJAwAAAA==.Gesen:BAAALgADCggJCAAAAA==.',
Gi='Gigaweenie:BAAALgADCgUJBQAAAA==.',
Gl='Glavien:BAABLgAECn8cAAIQAAgJdQ2URQB1AQAQAAgJdQ2URQB1AQAAAA==.',
Gr='Grandstorm:BAAALgADCgIJAgAAAA==.Greg:BAAALgADCgYJBgAAAA==.Grienke:BAAALgADCgQJBAABLgAECggJFgAPAOMaAA==.Grizzle:BAAALgADCgUJBQAAAA==.Grumpolbolt:BAABLgAECn8eAAITAAgJ9BnXEwB0AQATAAgJ9BnXEwB0AQAAAA==.',
Ha='Haenin:BAAALgAECgEJAQAAAA==.Haplo:BAAALgAECgMJBAAAAA==.Harnessme:BAAALgADCggJCwABLgAECggJHQALAFQOAA==.Harps:BAAALgADCgYJBgAAAA==.',
He='Hey:BAACLgAFFH8GAAIJAAIJphqOFQCsAAAJAAIJphqOFQCsAAAuAAQKfzQAAgkACQlbHzMIAPICAAkACQlbHzMIAPICAAAA.',
Ho='Homble:BAAALgADCgIJAgAAAA==.Horadin:BAAALgADCgkJEgAAAA==.',
Hu='Huntmeister:BAABLgAECn8dAAINAAgJLyEFDQDWAgANAAgJLyEFDQDWAgAAAA==.',
Ic='Iceehawt:BAABLgAECn8bAAIPAAgJHCJKDQCaAgAPAAgJHCJKDQCaAgAAAA==.',
Il='Ilharra:BAAALgAECgQJBwAAAA==.Ilililili:BAAALgAECgMJBAAAAA==.Illee:BAAALgAECgUJDQAAAA==.Illuminara:BAAALgADCgYJEQAAAA==.',
Im='Imdrood:BAAALgADCgMJAwABLgAECggJIwARAFoiAA==.Imturtle:BAABLgAECn8jAAMRAAgJWiJqBAB0AgARAAgJWiJqBAB0AgAPAAIJ6BA3/gB+AAAAAA==.',
In='Insømniadk:BAABLgAFFH8FAAIPAAMJgBzaQAAOAQAPAAMJgBzaQAAOAQABLgAFFAYJDwAPAEIYAA==.',
Is='Isshiny:BAABLgAECn8VAAIQAAcJchl4MgCzAQAQAAcJchl4MgCzAQAAAA==.',
Iu='Iupiter:BAAALgAECgcJDwAAAA==.',
Iy='Iyahlieairia:BAAALgADCgEJAQAAAA==.',
Iz='Izabeth:BAABLgAECn8VAAIEAAYJhgvRiAABAQAEAAYJhgvRiAABAQAAAA==.',
Ja='Jacaar:BAAALgADCgUJBQAAAA==.Jamella:BAABLgAECn8VAAIUAAcJhAx4FgDpAAAUAAcJhAx4FgDpAAAAAA==.',
Je='Jessabella:BAAALgADCgIJAgAAAA==.',
Ji='Jigles:BAAALgADCgEJAQAAAA==.',
Ka='Kaelynia:BAAALgADCgYJCgAAAA==.Kagosi:BAAALgAECgQJBwAAAA==.Kairn:BAAALgADCgcJBwAAAA==.Kalivath:BAAALgADCgUJCAAAAA==.Kardaa:BAAALgADCgEJAQAAAA==.Kat:BAABLgAECn8XAAIJAAgJHgZzXwAOAQAJAAgJHgZzXwAOAQAAAA==.Kawi:BAAALgADCgEJAQAAAA==.Kazakusan:BAAALgADCgUJAwAAAA==.',
Ki='Kiraneem:BAABLgAECn8dAAMNAAgJMxe4IgDNAQANAAgJMxe4IgDNAQAOAAEJ2wGflwAgAAAAAA==.Kittie:BAABLgAECn8jAAMJAAgJSQxvLABlAQAJAAgJSQxvLABlAQACAAQJjQjZRQCRAAAAAA==.',
Ko='Kotenok:BAAALgAECgYJBgAAAA==.',
Kr='Kreyaa:BAABLgAECn8UAAIEAAcJ2xFUVABvAQAEAAcJ2xFUVABvAQAAAA==.Krinj:BAABLgAECn8nAAIPAAkJZR3bGQAwAgAPAAkJZR3bGQAwAgAAAA==.Kristov:BAAALgAECgIJAgAAAA==.',
Ky='Kyarla:BAABLgAECn8cAAIVAAUJABNjJwAOAQAVAAUJABNjJwAOAQAAAA==.Kydo:BAABLgAECn8hAAIEAAcJZxeINwDEAQAEAAcJZxeINwDEAQABLgAFFAMJAwADAAAAAA==.',
['Kø']='Køe:BAAALgADCgQJBAABLgAECgEJAQADAAAAAA==.',
La='Lamp:BAAALgAECgQJBQAAAA==.',
Le='Ledani:BAABLgAECn8bAAIHAAgJhhFeEgC1AQAHAAgJhhFeEgC1AQAAAA==.Leøna:BAAALgADCgEJAQAAAA==.',
Li='Liberi:BAAALgADCgEJAQAAAA==.Light:BAAALgAECgkJDAAAAA==.Lightwràth:BAAALgADCgMJAwAAAA==.Lincecum:BAAALgAECggJEAABLgAECggJFgAPAOMaAA==.Lioni:BAAALgADCgkJCQAAAA==.Listen:BAABLgAECn9AAAITAAgJBBv4CAATAgATAAgJBBv4CAATAgAAAA==.',
Lo='Loachapoka:BAAALgADCgYJDQAAAA==.Lohith:BAAALgAECgQJBAAAAA==.Lonedawg:BAAALgAECgMJBAAAAA==.Loweform:BAAALgADCgEJAQAAAA==.',
Lu='Lunâ:BAABLgAECn8cAAIIAAgJrBieCABSAgAIAAgJrBieCABSAgAAAA==.Luwud:BAAALgADCgcJEAAAAA==.',
Ly='Lyrei:BAABLgAECn8XAAIWAAgJTBYuIADIAQAWAAgJTBYuIADIAQAAAA==.',
Ma='Macfrost:BAAALgADCgUJBgAAAA==.Machiavelli:BAAALgADCgUJBQAAAA==.Maddox:BAAALgAECgYJEAAAAA==.Magichandz:BAAALgAECgYJCQAAAA==.Maikakx:BAAALgAECgEJAQAAAA==.Marsyx:BAABLgAECn8bAAIVAAkJBR/fBAC/AgAVAAkJBR/fBAC/AgAAAA==.Masfonos:BAAALgADCgEJAQAAAA==.Mayael:BAAALgAECgQJBQAAAA==.Maíkeru:BAAALgADCgEJAQAAAA==.',
Mc='Mcguffinss:BAABLgAECn8dAAMMAAkJdSU7LACzAQAMAAcJwiU7LACzAQALAAMJuiJvJwAmAQABLgAFFAIJAgADAAAAAA==.',
Me='Medreaux:BAABLgAECn8yAAIVAAgJvhu+CQBNAgAVAAgJvhu+CQBNAgAAAA==.Metalknyte:BAABLgAECn8dAAIRAAgJmgq9GAAFAQARAAgJmgq9GAAFAQAAAA==.',
Mi='Miniknyte:BAAALgAECggJEAAAAA==.Minotauren:BAAALgADCgYJBQAAAA==.Misskitty:BAABLgAECn8UAAIGAAYJUyPMBQD0AQAGAAYJUyPMBQD0AQAAAA==.',
Mo='Modnoc:BAAALgAECgYJDAAAAA==.Mollog:BAAALgADCgcJEAAAAA==.Mommii:BAAALgADCgEJAQABLgAECgEJAQADAAAAAA==.Moondanas:BAAALgADCgMJAwAAAA==.Moonshine:BAAALgADCgUJCAAAAA==.Moonsz:BAAALgADCgkJOgAAAA==.',
Mu='Mugmug:BAAALgADCgUJBgAAAA==.',
My='Mychelle:BAABLgAECn8cAAIOAAgJjhQCBgC9AQAOAAgJjhQCBgC9AQAAAA==.',
['Mø']='Møgwai:BAAALgAECgEJAQAAAA==.',
Na='Nakryn:BAABLgAECn8oAAIEAAgJLAQQfgAVAQAEAAgJLAQQfgAVAQAAAA==.Naluai:BAAALgADCgEJAQAAAA==.Nandami:BAAALgADCgIJAgAAAA==.Nary:BAAALgAECgkJCgAAAA==.Naryeth:BAAALgAECggJCAAAAA==.Narysham:BAAALgADCgIJAgAAAA==.',
Ne='Neazth:BAAALgADCgEJAQABLgAECgIJAgADAAAAAA==.Nezaeth:BAAALgAECgIJAgAAAA==.Nezum:BAAALgADCgYJBgABLgAECgIJAgADAAAAAA==.',
Ni='Nickoli:BAAALgAECgIJAgAAAA==.Nightshade:BAAALgADCgkJEgAAAA==.',
No='Nohnehn:BAAALgAECgEJBAAAAA==.Nojomo:BAAALgAECgEJAQAAAA==.Nojomoto:BAAALgAECgEJAQAAAA==.Norabel:BAAALgAECgUJCwAAAA==.',
Ny='Nyra:BAABLgAECn8jAAINAAkJ8BobDAB+AgANAAkJ8BobDAB+AgAAAA==.',
['Nø']='Nøxxi:BAABLgAECn8nAAILAAgJNxenAwDlAQALAAgJNxenAwDlAQAAAA==.',
Oc='Ocon:BAAALgADCgUJBQAAAA==.',
Ok='Okbloomer:BAABLgAECn8aAAMXAAcJdSL6EADFAQAXAAcJdSL6EADFAQAKAAcJLQ4mXwA0AQAAAA==.',
Op='Optometrist:BAAALgADCgcJBwAAAA==.',
Or='Orckeferal:BAAALgADCgYJCQABLgAFFAcJGgAYACEdAA==.Oriel:BAABLgAECn8dAAIIAAgJxAlcFgCJAQAIAAgJxAlcFgCJAQAAAA==.Orthein:BAAALgADCgcJDAABLgAECgMJBAADAAAAAA==.',
Pa='Pawarwar:BAAALgADCgMJAwAAAA==.',
Pe='Pedrita:BAAALgADCgEJAQAAAA==.',
Ph='Phindin:BAABLgAECn8iAAMCAAgJ/gx3HwBTAQACAAgJ/gx3HwBTAQAJAAEJ4QEBiQAlAAAAAA==.',
Po='Poc:BAAALgAECgcJDgAAAA==.Pokoko:BAAALgADCgUJBgAAAA==.',
Pr='Priblet:BAAALgADCgcJBwAAAA==.Primo:BAAALgAECgYJCAAAAA==.Prinsana:BAABLgAECn8dAAIUAAgJAxDbDgBKAQAUAAgJAxDbDgBKAQAAAA==.',
Pu='Purged:BAABLgAECn8YAAIJAAcJYQaaPwAFAQAJAAcJYQaaPwAFAQAAAA==.Purquis:BAAALgAECgEJAQAAAA==.',
Ra='Ragnus:BAAALgADCgEJAQAAAA==.Ralphie:BAAALgADCgcJAQAAAA==.Rasen:BAAALgAECgIJAgAAAA==.Ratheer:BAAALgAFFAIJAgAAAA==.Rawfalafel:BAAALgAECggJEwAAAA==.',
Re='Reaperlord:BAABLgAECn8VAAIZAAcJkRK/GgCzAQAZAAcJkRK/GgCzAQAAAA==.',
Rl='Rllybuffnerd:BAAALgADCgEJAQAAAA==.',
Ro='Rodikus:BAABLgAECn8nAAMVAAgJ4R0/FAA8AgAVAAgJ4R0/FAA8AgAHAAYJ7AjEJwAJAQAAAA==.Rootbeer:BAAALgADCgYJBgAAAA==.Rorax:BAAALgAECgcJEwAAAA==.Rosanna:BAAALgAECgQJBQAAAA==.',
Rp='Rprunner:BAAALgAECgUJBQABLgAECgcJFgAaAJwPAA==.',
Sa='Saiaa:BAAALgAECgYJCAAAAA==.Sakeena:BAAALgAECgMJBAAAAA==.Samará:BAAALgAECgIJBgAAAA==.Sarleigh:BAAALgAECgUJDQAAAA==.Sattia:BAABLgAECn8pAAIKAAgJ+gXPQwADAQAKAAgJ+gXPQwADAQAAAA==.',
Sc='Scampington:BAAALgADCgcJDAAAAA==.',
Se='Sertzert:BAABLgAECn8WAAIGAAYJXhjYDABKAQAGAAYJXhjYDABKAQAAAA==.',
Sh='Sharrow:BAAALgADCggJEQAAAA==.Shiggy:BAAALgAECgIJAgAAAA==.Shinokami:BAABLgAECn8VAAISAAcJaA8cHQBLAQASAAcJaA8cHQBLAQAAAA==.Shoto:BAAALgADCgEJAQAAAA==.',
Si='Silentninjaa:BAABLgAECn8eAAIbAAgJuxTzFQC5AQAbAAgJuxTzFQC5AQAAAA==.Silque:BAAALgAECgMJAwAAAA==.Simphunter:BAEBLgAECn8kAAIWAAgJRx7YDABnAgAWAAgJRx7YDABnAgAAAA==.Sinchan:BAAALgADCgEJAQAAAA==.Sindaea:BAAALgADCgYJBgAAAA==.Sinfel:BAABLgAECn8cAAIcAAgJkAdHFgA1AQAcAAgJkAdHFgA1AQAAAA==.Sit:BAAALgAECgYJDAAAAA==.',
Sk='Skall:BAAALgAECgEJAQAAAA==.Skoree:BAABLgAECn8gAAIWAAkJgSC8GQC6AgAWAAkJgSC8GQC6AgAAAA==.',
Sn='Snapdragon:BAAALgAECgIJAgAAAA==.',
So='Soluna:BAAALgADCgYJBgAAAA==.Someonelse:BAAALgAECgMJAwAAAA==.Sonett:BAAALgAECgMJBAAAAA==.',
Sp='Splunk:BAAALgAECgkJEAABLgAECgkJFwASABULAA==.Spânky:BAAALgAECgYJEQAAAA==.Spíké:BAAALgADCgkJCQAAAA==.',
Sq='Squiggles:BAAALgAECggJEgAAAA==.',
St='Staggerdaddy:BAAALgADCgYJBgAAAA==.Stariya:BAAALgAECgMJBAAAAA==.Stormkraa:BAAALgAECgYJBgAAAA==.Strawyà:BAAALgADCgQJBwABLgAECggJHgAUABQaAA==.Strawyæ:BAABLgAECn8eAAIUAAgJFBrIBwBgAgAUAAgJFBrIBwBgAgAAAA==.Strike:BAAALgAECgYJCAABLgAECggJMQAZAHIXAA==.',
Su='Sugerfree:BAAALgAECgYJDAAAAA==.',
Ta='Taleranor:BAAALgADCgkJKAAAAA==.Tallaeya:BAAALgAECgIJAgAAAA==.Tamerizer:BAABLgAECn8gAAMdAAgJ0RGBEACkAQAdAAgJ0QyBEACkAQAOAAYJ8xAZRABFAQAAAA==.',
Te='Tealera:BAAALgAECgMJAwAAAA==.Teejrath:BAAALgAECgEJAQAAAA==.Teekeez:BAABLgAECn8UAAIEAAYJ4Qq0mQDfAAAEAAYJ4Qq0mQDfAAAAAA==.Terup:BAAALgADCgUJBQAAAA==.',
Th='Theodorel:BAAALgADCgcJDQAAAA==.Thillarys:BAAALgAECgEJAQAAAA==.Thirge:BAABLgAECn8dAAIbAAgJVg3YHwBtAQAbAAgJVg3YHwBtAQAAAA==.Thrushbeard:BAAALgADCgkJFwAAAA==.',
To='Tokas:BAAALgAECgIJAgAAAA==.Tolak:BAAALgAECgUJCwAAAA==.Torturousôwl:BAAALgAECgcJDQAAAA==.',
Tr='Traaze:BAAALgAECgYJDAAAAA==.Tralle:BAAALgAECgMJAwAAAA==.Trisky:BAABLgAECn8cAAIZAAYJLBmoGwCrAQAZAAYJLBmoGwCrAQAAAA==.Trissa:BAAALgADCgcJEQAAAA==.Trolldax:BAAALgADCgUJBwABLgAECgMJAwADAAAAAA==.Trydént:BAAALgAECgMJBAAAAA==.',
Tu='Tunip:BAAALgAECgIJAgAAAA==.Turtle:BAAALgAECgYJDwABLgAECggJIwARAFoiAA==.',
Ul='Ulric:BAAALgADCgkJEgAAAA==.',
Va='Vaceriss:BAAALgADCgYJBgAAAA==.Valatar:BAAALgADCgcJCgAAAA==.Valdrakkquin:BAABLgAECn8nAAIeAAkJZSB1AgCEAgAeAAkJZSB1AgCEAgAAAA==.Valtreya:BAAALgADCgYJBgAAAA==.',
Ve='Vegito:BAABLgAECn8eAAIbAAYJ4QTCOgDYAAAbAAYJ4QTCOgDYAAAAAA==.Veramoon:BAAALgADCgYJBgAAAA==.',
Vi='Victoriia:BAAALgADCggJCAAAAA==.Vincente:BAAALgADCgMJAwAAAA==.Vistus:BAAALgAECgQJBAAAAA==.',
Vo='Void:BAAALgADCgQJBAABLgAECggJHAAOAI4UAA==.Voidmeister:BAABLgAECn8WAAIWAAYJ+RIIVAD+AAAWAAYJ+RIIVAD+AAABLgAECggJHQANAC8hAA==.Voin:BAABLgAECn88AAMfAAkJpiLwAQDZAgAfAAkJpiLwAQDZAgAbAAQJfRstJwA9AQAAAA==.Vorpine:BAABLgAECn8gAAMHAAgJBBdtEwCpAQAHAAcJkBltEwCpAQAIAAMJ7grrMwCRAAAAAA==.',
Vs='Vs:BAACLgAFFH8GAAIPAAMJ3RJAJQABAQAPAAMJ3RJAJQABAQAuAAQKfxUAAg8ACAnYIJ9SAPoBAA8ACAnYIJ9SAPoBAAEuAAUUBwkgABYA8CQA.',
Wa='Warcockeh:BAAALgADCgUJBQAAAA==.Watermelon:BAABLgAECn8ZAAIgAAgJZxZaEQDdAQAgAAgJZxZaEQDdAQAAAA==.',
Wi='Wirhl:BAAALgAECgYJEAAAAA==.',
Wo='Wolfrik:BAAALgAECgUJAwAAAA==.Worthatry:BAAALgAFFAMJAwAAAA==.',
Wy='Wyn:BAABLgAECn8gAAIQAAgJRB9eEQBwAgAQAAgJRB9eEQBwAgAAAA==.',
Xa='Xalbit:BAABLgAECn8dAAIJAAgJ7BVPFwD4AQAJAAgJ7BVPFwD4AQAAAA==.Xanthrash:BAAALgAECgMJBAAAAA==.Xantia:BAABLgAECn8xAAIKAAkJdBVcEQBGAgAKAAkJdBVcEQBGAgAAAA==.Xaraena:BAABLgAECn8fAAINAAkJfRr1KAATAgANAAkJfRr1KAATAgAAAA==.Xaraimarra:BAAALgADCgQJBAAAAA==.Xariz:BAAALgAECgcJEgAAAA==.',
Xe='Xedd:BAAALgAECgQJBgAAAA==.Xenlo:BAAALgAECgMJAwABLgAFFAMJBwAZAI8eAA==.',
Xy='Xyndrä:BAAALgADCgYJBgAAAA==.',
Za='Zaizel:BAAALgADCgUJBQABLgAFFAYJEgAhAHYUAA==.Zathennyx:BAAALgADCgYJBgABLgAECgMJAwADAAAAAA==.',
Ze='Zercus:BAABLgAFFH8HAAIQAAMJywlzNQDgAAAQAAMJywlzNQDgAAAAAA==.',
Zh='Zhryla:BAAALgADCgUJCQAAAA==.',
Zl='Zleakara:BAAALgADCgQJBAAAAA==.Zleako:BAAALgADCgMJAwAAAA==.',
['Ðr']='Ðread:BAAALgAECgYJEQAAAA==.',
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

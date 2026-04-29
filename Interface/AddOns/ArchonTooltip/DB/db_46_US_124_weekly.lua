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

local lookup = {'Hunter-Marksmanship','Hunter-Survival','DemonHunter-Devourer','Unknown-Unknown','Warlock-Affliction','Warlock-Demonology','Shaman-Elemental','DeathKnight-Unholy','Mage-Frost','Hunter-BeastMastery','DemonHunter-Havoc','Evoker-Augmentation','Evoker-Preservation','Shaman-Restoration','Warrior-Protection','Druid-Guardian','Druid-Restoration','Shaman-Enhancement','Paladin-Retribution','Paladin-Holy','Monk-Windwalker','Rogue-Outlaw','Rogue-Subtlety','DemonHunter-Vengeance','Monk-Mistweaver','Monk-Brewmaster','Druid-Feral','Warrior-Fury','Warrior-Arms','Mage-Fire',}
local provider = {region='US',realm='Jaedenar',name='US',type='weekly',zone=46,date='2026-04-24',data={Ag='Agonie:BAAALgADCgEJAQAAAA==.',
Al='Alaina:BAAALgADCgIJAgAAAA==.Aleive:BAAALgADCgcJEwAAAA==.Alion:BAAALgAECgYJBwAAAA==.Alphachik:BAAALgADCggJEwAAAA==.Alruna:BAAALgADCgIJAgAAAA==.',
Am='Amarafar:BAACLgAFFH8HAAIBAAMJuSGZEQAfAQABAAMJuSGZEQAfAQAuAAQKfxUAAwEACAl+H0AQALgCAAEACAl+H0AQALgCAAIAAgnUGeAkAKIAAAAA.',
An='Anoiche:BAAALgAECgcJEAAAAA==.',
As='Asmodeus:BAACLgAFFH8IAAIDAAQJwg2tDQDuAAADAAQJwg2tDQDuAAAuAAQKfx8AAgMABwnaGxQvAEACAAMABwnaGxQvAEACAAAA.',
At='Atlastrasz:BAAALgADCggJGAABLgADCgkJGAAEAAAAAA==.',
Ax='Axeldaur:BAAALgADCgMJAwAAAA==.Axelrod:BAAALgAECgQJBQAAAA==.',
Az='Azucena:BAAALgAECgMJAwAAAA==.',
Ba='Bananos:BAABLgAECn8cAAMFAAgJOBzyAQC1AgAFAAgJOBzyAQC1AgAGAAIJNwIyJgErAAAAAA==.',
Bd='Bdog:BAAALgADCgMJAwAAAA==.Bdogg:BAAALgADCgQJBAAAAA==.',
Be='Bearback:BAAALgAECgQJBwAAAA==.Bertram:BAAALgAECgYJDwAAAA==.',
Bi='Billie:BAAALgADCgkJHAAAAA==.',
Bl='Blender:BAAALgADCgMJAwAAAA==.Blightforged:BAAALgADCgUJCQAAAA==.',
Bo='Boojum:BAAALgAECgMJBQAAAA==.Booze:BAAALgAECgcJDgAAAA==.Borgar:BAAALgAECgQJBwABLgAFFAEJAQAEAAAAAA==.',
Ch='Chillsunwell:BAAALgADCgkJCQAAAA==.Chivasaurus:BAAALgAECgUJCQABLgAFFAQJBQAHAC0FAA==.',
Cl='Cluëless:BAAALgAECgMJBgAAAA==.',
Co='Cokenoice:BAAALgAECgEJAQAAAA==.Covenant:BAAALgAECgMJBAAAAA==.',
Cr='Craig:BAAALgADCgYJBgAAAA==.',
Cy='Cynide:BAAALgAECgYJCgAAAA==.',
Da='Darktarus:BAAALgADCgIJAgAAAA==.',
De='Demonz:BAAALgADCgMJAwAAAA==.Dengeng:BAAALgADCgUJBQAAAA==.Depally:BAAALgAECgMJBAAAAA==.Devastata:BAAALgADCgcJBwAAAA==.Devilblight:BAAALgADCgMJAwAAAA==.Devilsburn:BAAALgADCggJBwAAAA==.',
Di='Disruptive:BAAALgAECgQJBAAAAA==.',
Dl='Dleifroom:BAAALgADCgMJAwAAAA==.',
Do='Domry:BAAALgADCgQJBAAAAA==.Dorim:BAAALgAECgcJDAAAAA==.',
Ec='Eclipse:BAACLgAFFH8LAAIIAAQJlRAhHAAzAQAIAAQJlRAhHAAzAQAuAAQKfyEAAggACAnoIPsbANYCAAgACAnoIPsbANYCAAAA.Eco:BAABLgAECn8ZAAIJAAgJXh5FEADAAQAJAAgJXh5FEADAAQAAAA==.',
Ed='Edeith:BAAALgAECgYJEQAAAA==.',
El='Elmono:BAACLgAFFH8MAAIJAAQJvBV0CABdAQAJAAQJvBV0CABdAQAuAAQKfywAAgkACQmlHNcUACsDAAkACQmlHNcUACsDAAAA.Elusivepanda:BAAALgAECgYJDgAAAA==.',
En='Enii:BAAALgAECgYJCwAAAA==.',
Er='Eravia:BAAALgAECgUJCAAAAA==.Erodria:BAAALgAECgQJCwAAAA==.Erther:BAABLgAECn8lAAMKAAgJTCRKBABLAwAKAAgJTCRKBABLAwABAAYJkw4cTQAcAQAAAA==.',
Es='Espresso:BAAALgADCgcJBwAAAA==.',
Eu='Eucharistica:BAACLgAFFH8GAAIDAAQJtBbXAwBrAQADAAQJtBbXAwBrAQAuAAQKfycAAgMACQnWIaoOAAkDAAMACQnWIaoOAAkDAAAA.',
Ex='Exeter:BAAALgAECgQJCgAAAA==.',
Ey='Eyegor:BAAALgAECgMJAwAAAA==.',
Fa='Faelyssa:BAABLgAECn8UAAILAAYJ2iB/FwAMAgALAAYJ2iB/FwAMAgABLgAFFAEJAQAEAAAAAA==.Far:BAABLgAECn8gAAQKAAgJ+B4ZEQCxAgAKAAgJzR4ZEQCxAgABAAQJow7XWQDcAAACAAMJRhW/DAC2AAAAAA==.Fathergoose:BAABLgAECn8ZAAMMAAgJGBn+DgCHAgAMAAgJGBn+DgCHAgANAAIJjAivQQBeAAAAAA==.',
Fi='Fistweavin:BAAALgAECgEJAQAAAA==.',
Fo='Foxpaw:BAAALgAECgMJAwAAAA==.',
Fr='Freakinout:BAAALgADCgUJBgAAAA==.Freekin:BAABLgAECn8lAAILAAgJxCN5AAC5AgALAAgJxCN5AAC5AgAAAA==.',
Fu='Fuddytotem:BAABLgAECn8VAAMOAAYJdx++IgAPAgAOAAYJdx++IgAPAgAHAAYJgRFGTQASAQABLgAECggJFAAPAPsNAA==.Furmoo:BAAALgAECgEJAQAAAA==.',
Fz='Fzy:BAABLgAECn8UAAIPAAgJ+w1VFADHAQAPAAgJ+w1VFADHAQAAAA==.Fzymage:BAAALgADCgEJAQABLgAECggJFAAPAPsNAA==.Fzyy:BAAALgADCgMJAwABLgAECggJFAAPAPsNAA==.',
Ga='Galvatron:BAAALgAECgEJAQAAAA==.',
Ge='Gearshot:BAAALgADCgcJDQAAAA==.Gergnome:BAAALgADCgYJBgAAAA==.',
Gh='Ghroxx:BAAALgAECgQJBQABLgAFFAEJAQAEAAAAAA==.',
Go='Goodra:BAAALgAFFAIJAgAAAA==.Goosetopher:BAAALgAECgYJDwAAAA==.Goril:BAAALgAFFAEJAQAAAA==.Goryious:BAACLgAFFH8HAAIIAAMJowo/LQDmAAAIAAMJowo/LQDmAAAuAAQKfx0AAggACAmRFg1AADgCAAgACAmRFg1AADgCAAAA.',
Gw='Gweg:BAABLgAECn8bAAMKAAgJUhsIIgA5AgAKAAgJMxsIIgA5AgACAAcJXBmzEAC4AQAAAA==.',
Ha='Halarda:BAAALgAFFAIJAgAAAA==.Harantor:BAAALgADCgkJGAAAAA==.',
Hi='Him:BAAALgADCgcJBwAAAA==.Hitthefloor:BAABLgAECn8cAAIOAAcJExdvKgDkAQAOAAcJExdvKgDkAQAAAA==.',
Ho='Hooves:BAACLgAFFH8NAAIQAAQJ5xMMAQAjAQAQAAQJ5xMMAQAjAQAuAAQKfysAAhAACQnNIvUAAGQDABAACQnNIvUAAGQDAAAA.',
Ic='Icphunter:BAAALgADCgcJDgAAAA==.',
Im='Imàdrood:BAABLgAECn8eAAIRAAgJWRt8BQAkAgARAAgJWRt8BQAkAgAAAA==.',
In='Invincible:BAAALgADCgQJBAAAAA==.',
Is='Iscorpiusi:BAAALgAECgMJBAAAAA==.',
Ja='Jaelana:BAABLgAECn8eAAMOAAYJcxKlDwBHAQAOAAYJcxKlDwBHAQASAAYJgAYBGwAaAQAAAA==.Jaenerys:BAAALgADCgcJBwABLgAECgEJAQAEAAAAAA==.Jaguarinsito:BAAALgAECgkJAwAAAA==.Janoski:BAAALgADCgEJAQAAAA==.',
Je='Jerrwolf:BAAALgADCggJGQAAAA==.',
Jo='Jorkinit:BAAALgAECgUJCQABLgAFFAEJAQAEAAAAAA==.',
Ka='Kafka:BAAALgADCgMJAwABLgAECgYJDAAEAAAAAA==.Kamideath:BAAALgAECgEJAQABLgAECgcJJQAJAPcjAA==.Kamidh:BAAALgADCgkJFQABLgAECgcJJQAJAPcjAA==.Kamihunt:BAAALgADCgQJBAABLgAECgcJJQAJAPcjAA==.Kamikozy:BAABLgAECn8lAAIJAAcJ9yMWJgDaAgAJAAcJ9yMWJgDaAgAAAA==.Kasharas:BAAALgAECgcJEgAAAA==.Katalena:BAABLgAECn8YAAMTAAcJgCPaHAC9AgATAAcJgCPaHAC9AgAUAAIJEgXfhQBhAAAAAA==.',
Ke='Keybinds:BAAALgAFFAEJAQAAAA==.',
Kh='Khain:BAAALgADCgcJFQAAAA==.Khealer:BAAALgAECgYJDQAAAA==.',
Ki='Kindi:BAAALgAECgYJDwAAAA==.Kitymeowmeow:BAACLgAFFH8IAAIVAAQJnSByAgCQAQAVAAQJnSByAgCQAQAuAAQKfygAAhUACQnkJUoCAHwDABUACQnkJUoCAHwDAAAA.',
Kl='Klausnomi:BAACLgAFFH8FAAIHAAQJLQXbBAAXAQAHAAQJLQXbBAAXAQAuAAQKfyoAAgcACQkuFigaAEICAAcACQkuFigaAEICAAAA.',
Ko='Kowalzky:BAAALgAECgQJCAAAAA==.',
Kr='Krow:BAAALgAFFAEJAQAAAA==.',
Ku='Kuup:BAAALgAECgUJBQAAAA==.',
Ky='Kyrieherbing:BAAALgADCgIJAwAAAA==.Kyruptôs:BAAALgADCgEJAQAAAA==.',
La='Lasina:BAAALgADCgIJAgAAAA==.Lastdance:BAAALgAECgYJBQAAAA==.',
Li='Lillyvera:BAAALgADCgcJFwAAAA==.Lilpsycho:BAAALgADCgYJBgAAAA==.',
Lo='Lokie:BAAALgAECgIJAgAAAA==.',
Lu='Lucia:BAAALgAECgYJDwAAAA==.',
Ly='Lynth:BAAALgADCgMJAwAAAA==.',
Ma='Magnusbane:BAAALgADCgYJBgABLgAECgYJFAAEAAAAAQ==.Maidokasa:BAAALgADCgUJBwAAAA==.Maja:BAABLgAECn8VAAMWAAUJXBa6BgBLAQAWAAUJXBa6BgBLAQAXAAUJUQyXPwAhAQAAAA==.Malaqor:BAABLgAECn8fAAIYAAgJ9CKlAQAEAwAYAAgJ9CKlAQAEAwAAAA==.Malla:BAAALgAECgQJBwAAAA==.Mamagoose:BAAALgADCgcJBwABLgAECggJGQAMABgZAA==.',
Mc='Mcflÿ:BAAALgADCgEJAQAAAA==.',
Me='Megryn:BAAALgAECgMJAwAAAA==.',
Mo='Mojojuice:BAABLgAECn8VAAIHAAgJ2SIOFwBfAgAHAAgJ2SIOFwBfAgAAAA==.Montar:BAAALgAECgYJEAAAAA==.Moonjuice:BAABLgAECn8YAAIRAAgJXhBrEwAvAQARAAgJXhBrEwAvAQAAAA==.',
Na='Nahaii:BAABLgAECn8aAAIIAAgJYhXWFABrAQAIAAgJYhXWFABrAQABLgAECggJIAAKAPgeAA==.Nanalli:BAAALgADCgIJAgAAAA==.',
Ne='Nelos:BAABLgAECn8VAAIZAAYJYBjvIACtAQAZAAYJYBjvIACtAQAAAA==.Neovisus:BAAALgAECgYJDwAAAA==.',
Ni='Nia:BAAALgAECggJCAAAAA==.Nineline:BAAALgADCgEJAQABLgAECgUJEQAEAAAAAA==.',
No='Nozarashi:BAAALgAECgYJEQAAAA==.',
Ob='Obzen:BAABLgAECn8mAAIaAAkJNhtfEwB2AgAaAAkJNhtfEwB2AgAAAA==.',
Om='Omegalul:BAAALgAECgMJAwABLgAFFAQJDAAJALwVAA==.',
Oo='Oopsikeelu:BAAALgADCgYJBgAAAA==.',
Pe='Pepperdogs:BAAALgAECgQJBAAAAA==.',
Po='Poisontips:BAAALgADCgkJHAAAAA==.',
Pr='Preast:BAAALgAECgEJAQAAAA==.',
Qk='Qkslvr:BAABLgAECn8XAAIKAAYJQSJdCgDDAQAKAAYJQSJdCgDDAQAAAA==.',
Ra='Randlidan:BAABLgAECn8YAAILAAgJ+x9yCQDLAgALAAgJ+x9yCQDLAgAAAA==.Randomcow:BAABLgAECn8VAAIIAAYJkA6ZoAA/AQAIAAYJkA6ZoAA/AQAAAA==.',
Re='Reidai:BAAALgAECgIJBAAAAA==.Remixedk:BAAALgAECgcJCAAAAA==.',
Ro='Roargorr:BAAALgAECgUJCAAAAA==.',
Ru='Rutabaga:BAAALgAECgIJAwAAAA==.',
Sa='Sadeas:BAAALgADCgQJBAAAAA==.Sadler:BAAALgADCgYJBgAAAA==.Sanctu:BAAALgAECgUJCgABLgAFFAQJCAADAMINAA==.',
Sc='Scarletnight:BAAALgADCgUJBQAAAA==.',
Se='Servusnape:BAAALgADCgQJAwAAAA==.',
Si='Silicos:BAAALgADCgIJAgABLgADCgYJBgAEAAAAAA==.',
Sk='Skywarp:BAAALgAECgYJBgAAAA==.',
Sl='Slapnchop:BAAALgADCgYJBgAAAA==.Slimjaedy:BAAALgAECgEJAQAAAA==.',
Sm='Smightful:BAAALgAECgUJBQAAAA==.Smol:BAAALgAECgUJCwAAAA==.',
St='Stan:BAAALgADCgYJCAABLgAECgYJDAAEAAAAAA==.Strexxi:BAAALgADCgMJBAAAAA==.',
Su='Summerdawn:BAAALgADCgcJBwAAAA==.Superspike:BAACLgAFFH8JAAIJAAQJMBASHABbAQAJAAQJMBASHABbAQAuAAQKfygAAgkACQklISAYABoDAAkACQklISAYABoDAAAA.Surshock:BAABLgAECn8bAAIHAAgJhRM4KQDLAQAHAAgJhRM4KQDLAQAAAA==.',
Sy='Sylaz:BAAALgAECgIJAgAAAA==.',
Ta='Taekay:BAAALgAECgcJDQABLgAFFAYJGAAaACkkAA==.Takamine:BAABLgAECn8UAAIbAAgJawgWBABkAQAbAAgJawgWBABkAQAAAA==.Talath:BAABLgAECn8VAAIMAAYJKBV7LQBWAQAMAAYJKBV7LQBWAQAAAA==.Talos:BAABLgAECn8VAAIDAAgJJAmmKwDHAAADAAgJJAmmKwDHAAAAAA==.',
Te='Terraluna:BAAALgADCgYJBgAAAA==.',
Th='Thundathighs:BAAALgADCgEJAQAAAA==.',
To='Totembutter:BAAALgADCgMJAwAAAA==.',
Tw='Twotswat:BAABLgAECn8ZAAQcAAcJ+hq5LQD8AQAcAAcJqxq5LQD8AQAPAAMJ6w1JDQCiAAAdAAIJ0xb6LACNAAAAAA==.Twysted:BAAALgAECgcJDAAAAA==.',
Ug='Ugin:BAAALgADCgQJBAAAAA==.',
Um='Umdrah:BAAALgADCgEJAQAAAA==.',
Va='Valsong:BAAALgADCgcJCwAAAA==.Vanillalatte:BAABLgAECn8YAAIeAAYJOiIRAgBMAgAeAAYJOiIRAgBMAgAAAA==.Vanillarista:BAAALgAECgMJAwAAAA==.Varwyn:BAAALgADCgMJAwAAAA==.',
Vo='Vonhance:BAAALgAECgEJAQAAAA==.',
Vy='Vynne:BAAALgADCgcJAQAAAA==.',
Wa='Wakingdeath:BAAALgAFFAEJAQAAAA==.',
We='Wesdarian:BAAALgAECgUJBQAAAA==.',
Wh='Whatdoisay:BAAALgADCgYJBgAAAA==.Whoami:BAAALgAECgYJDgAAAA==.',
Xe='Xer:BAABLgAECn8UAAIJAAUJsg1lNQDxAAAJAAUJsg1lNQDxAAAAAA==.',
Xi='Xirious:BAAALgAECgYJBwAAAA==.',
Xo='Xor:BAAALgADCgQJBAAAAA==.',
Xu='Xur:BAABLgAECn8YAAIDAAcJtBXVFgBHAQADAAcJtBXVFgBHAQAAAA==.',
Yo='Yonko:BAABLgAECn8XAAMVAAgJ4Bl9FABJAgAVAAgJ4Bl9FABJAgAaAAQJcAq3ZQCrAAAAAA==.',
Ys='Ys:BAAALgADCgcJCwABLgAECgQJDAAEAAAAAA==.',
Ze='Zev:BAAALgADCggJCAAAAA==.',
['Ís']='Ísolde:BAABLgAECn8WAAIJAAcJZhtoEAC/AQAJAAcJZhtoEAC/AQAAAA==.',
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

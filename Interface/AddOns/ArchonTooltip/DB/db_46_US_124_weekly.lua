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

local lookup = {'Rogue-Subtlety','Hunter-Marksmanship','Hunter-Survival','DemonHunter-Devourer','Unknown-Unknown','Warlock-Affliction','Warlock-Demonology','Shaman-Elemental','Rogue-Assassination','DemonHunter-Havoc','Monk-Brewmaster','Shaman-Restoration','DeathKnight-Unholy','Mage-Frost','Warlock-Destruction','Paladin-Retribution','Hunter-BeastMastery','Evoker-Augmentation','Evoker-Preservation','Warrior-Protection','Priest-Shadow','Druid-Guardian','Druid-Restoration','Druid-Balance','Shaman-Enhancement','Paladin-Holy','Priest-Holy','Monk-Windwalker','Rogue-Outlaw','DemonHunter-Vengeance','Monk-Mistweaver','DeathKnight-Blood','Druid-Feral','Warrior-Fury','Warrior-Arms','Mage-Fire','Mage-Arcane',}
local provider = {region='US',realm='Jaedenar',name='US',type='weekly',zone=46,date='2026-05-08',data={Ag='Agonie:BAAALgAECgEJAQAAAA==.',
Al='Aladia:BAAALgAECgEJAQABLgAECggJGgABAJkgAA==.Alaina:BAAALgADCgIJAgAAAA==.Aleive:BAAALgAECgEJAQAAAA==.Alion:BAAALgAECgYJBwAAAA==.Alphachik:BAAALgADCggJEwAAAA==.Alruna:BAAALgADCgIJAgAAAA==.',
Am='Amarafar:BAACLgAFFH8HAAICAAMJuSGqEQAfAQACAAMJuSGqEQAfAQAuAAQKfxUAAwIACAl+H/IPAL8CAAIACAl+H/IPAL8CAAMAAgnjGeIkAKIAAAAA.Amoteph:BAAALgADCgQJBAAAAA==.',
An='Anoiche:BAABLgAECn8QAAIEAAgJ0xogOgAMAgAEAAgJ0xogOgAMAgAAAA==.',
As='Asmodeus:BAACLgAFFH8MAAIEAAUJ9RTyHQAzAQAEAAUJ9RTyHQAzAQAuAAQKfygAAgQABwklHv0cANsBAAQABwklHv0cANsBAAAA.',
At='Atlastrasz:BAAALgADCggJGAABLgADCgkJGAAFAAAAAA==.',
Av='Avanzo:BAAALgAECgMJAwAAAA==.',
Ax='Axeldaur:BAAALgADCgMJAwAAAA==.Axelrod:BAAALgAECgkJDgAAAA==.',
Az='Azucena:BAAALgAECgMJAwAAAA==.',
Ba='Bananos:BAACLgAFFH8IAAMGAAQJKQxGAgDdAAAGAAMJqg5GAgDdAAAHAAEJpgRegAA7AAAuAAQKfx0AAwYACAk4HPMBALUCAAYACAk4HPMBALUCAAcAAwk3CPPKAD4AAAAA.',
Bd='Bdog:BAAALgADCgMJAwAAAA==.Bdogg:BAAALgADCgQJBAAAAA==.',
Be='Bearback:BAAALgAFFAIJAgAAAA==.Bertram:BAABLgAECn8bAAIIAAYJ5wThOgDBAAAIAAYJ5wThOgDBAAAAAA==.',
Bi='Bialalilia:BAAALgADCgMJAwAAAA==.Billie:BAAALgAECgQJBAAAAA==.',
Bl='Blender:BAAALgADCgMJAwAAAA==.Blightforged:BAAALgADCgUJCQAAAA==.',
Bo='Boojum:BAAALgAECgUJCgAAAA==.Booze:BAABLgAECn8aAAMBAAgJmSDGBwArAgABAAcJTyDGBwArAgAJAAIJzRwJEACxAAAAAA==.Borgar:BAAALgAECgQJBwABLgAECgcJHQAKAHIfAA==.',
Ch='Chillsunwell:BAAALgADCgkJCQAAAA==.Chivasaurus:BAABLgAECn8WAAILAAcJTwS0LgDhAAALAAcJTwS0LgDhAAABLgAFFAQJDAAIAPAMAA==.',
Ci='Cirrce:BAAALgAECgYJBwAAAA==.',
Cl='Cluëless:BAAALgAECgMJBgAAAA==.',
Co='Cokenoice:BAAALgAECgEJAQAAAA==.Covenant:BAAALgAECgYJDgAAAA==.',
Cr='Craig:BAAALgADCgYJBgAAAA==.',
Cy='Cynide:BAAALgAECgYJCgAAAA==.',
Da='Darktarus:BAAALgADCgIJAgAAAA==.',
De='Demonz:BAAALgADCgMJAwAAAA==.Dengeng:BAAALgAECgIJAwAAAA==.Depally:BAAALgAECgMJBAAAAA==.Devastata:BAAALgADCgcJBwAAAA==.Devilsburn:BAAALgAECgYJBgAAAA==.',
Di='Disruptive:BAAALgAECgUJBQAAAA==.',
Dl='Dleifroom:BAAALgADCgMJAwAAAA==.',
Do='Domry:BAAALgADCgQJBAAAAA==.Dorim:BAABLgAECn8WAAMIAAgJ3RITIQBHAQAIAAcJwhATIQBHAQAMAAMJ9Qa5YAB4AAAAAA==.',
Du='Duuhwat:BAAALgADCgYJBgAAAA==.',
Ec='Eclipse:BAACLgAFFH8LAAINAAQJkhAzHAAzAQANAAQJkhAzHAAzAQAuAAQKfyIAAg0ACAnoIAEcANYCAA0ACAnoIAEcANYCAAAA.Eco:BAACLgAFFH8LAAIOAAQJyxz8HABwAQAOAAQJyxz8HABwAQAuAAQKfx0AAg4ACQn0H1AfAC8CAA4ACQn0H1AfAC8CAAAA.',
Ed='Edeith:BAAALgAECgYJEwAAAA==.',
Eh='Ehanoko:BAAALgADCgYJBgABLgAECgYJFwABAPccAA==.',
El='Elmono:BAACLgAFFH8XAAIOAAYJQBgoDQC+AQAOAAYJQBgoDQC+AQAuAAQKfzUAAg4ACQnyIdwUACsDAA4ACQnyIdwUACsDAAAA.Elusivepanda:BAABLgAECn8VAAIPAAgJ3yIoBwBXAgAPAAgJ3yIoBwBXAgAAAA==.',
En='Enii:BAAALgAECgYJEAAAAA==.',
Er='Eravia:BAABLgAECn8YAAIQAAkJPBMkGgAsAgAQAAkJPBMkGgAsAgAAAA==.Erodria:BAAALgAECgQJCwAAAA==.Erther:BAACLgAFFH8MAAIRAAUJGxPCDAD8AAARAAUJGxPCDAD8AAAuAAQKfygABBEACAlMJEgEAEsDABEACAlMJEgEAEsDAAIABgmTDjVNABwBAAMAAQmGEk84AEgAAAAA.',
Es='Espresso:BAAALgADCgcJBwAAAA==.',
Eu='Eucharistica:BAACLgAFFH8OAAIEAAYJWhgHCQCuAQAEAAYJWhgHCQCuAQAuAAQKfz4AAgQACQlJI0QCAC8DAAQACQlJI0QCAC8DAAAA.',
Ex='Exeter:BAAALgAECgQJCgAAAA==.',
Ey='Eyegor:BAAALgAECgMJAwAAAA==.',
Fa='Faelyssa:BAABLgAECn8dAAIKAAcJch+CCwDKAQAKAAcJch+CCwDKAQAAAA==.Fake:BAAALgAECgMJAQAAAA==.Far:BAACLgAFFH8LAAMRAAUJnRJhGwAvAQARAAQJ0w1hGwAvAQADAAQJ4Q2QDwD6AAAuAAQKfygABBEACAmAIBgRALECABEACAlVIBgRALECAAMABwmVHGkKAP0BAAIABAmjDudZANwAAAAA.Fathergoose:BAABLgAECn8nAAMSAAgJ7Rn7DgCHAgASAAgJ7Rn7DgCHAgATAAcJAxQvCwCcAQAAAA==.',
Fi='Fistweavin:BAAALgAECgEJAQAAAA==.',
Fo='Foxpaw:BAAALgAECgMJAwAAAA==.',
Fr='Freakinout:BAAALgADCgUJBgAAAA==.Freekin:BAABLgAECn8oAAIKAAkJPSQWAQAeAwAKAAkJPSQWAQAeAwAAAA==.',
Fu='Fuddytotem:BAABLgAECn8cAAMMAAYJGCG1IgAPAgAMAAYJGCG1IgAPAgAIAAYJgRFSTQASAQABLgAECggJFQAUAPwNAA==.Funnelcake:BAAALgADCgcJBwAAAA==.Furmoo:BAAALgAECgEJAQAAAA==.',
Fz='Fzy:BAABLgAECn8VAAIUAAgJ/A1YFADGAQAUAAgJ/A1YFADGAQAAAA==.Fzymage:BAAALgADCgEJAQABLgAECggJFQAUAPwNAA==.Fzyy:BAAALgADCgMJAwABLgAECggJFQAUAPwNAA==.',
Ga='Galvatron:BAAALgAECgIJAwAAAA==.',
Ge='Gearshot:BAAALgADCgcJDQAAAA==.Gergnome:BAAALgADCgYJBgAAAA==.',
Gh='Ghroxx:BAAALgAECgQJBQABLgAECgcJHQAKAHIfAA==.',
Go='Goodra:BAAALgAFFAIJAgAAAA==.Goosetopher:BAABLgAECn8dAAIVAAgJbxaRDgDjAQAVAAgJbxaRDgDjAQAAAA==.Goril:BAABLgAECn8TAAIEAAcJThq+HADdAQAEAAcJThq+HADdAQABLgAECgcJHQAKAHIfAA==.Goryious:BAACLgAFFH8HAAINAAMJowpNLQDmAAANAAMJowpNLQDmAAAuAAQKfx4AAg0ACQmeFhFAADgCAA0ACQmeFhFAADgCAAEuAAUUBQkNAAIAHRwA.',
Gw='Gweg:BAABLgAECn8iAAMRAAgJTx4HIgA5AgARAAgJwBwHIgA5AgADAAcJOxyyCgD4AQAAAA==.',
Ha='Halarda:BAABLgAECn8dAAMRAAcJuBu5KACuAQARAAcJuBu5KACuAQACAAUJAhCsUAALAQAAAA==.Harantor:BAAALgADCgkJGAAAAA==.',
Hi='Him:BAAALgADCgcJBwAAAA==.Hitthefloor:BAABLgAECn8wAAIMAAgJdR7XBgDEAgAMAAgJdR7XBgDEAgAAAA==.',
Ho='Hooves:BAACLgAFFH8ZAAIWAAYJxBXfAQB7AQAWAAYJxBXfAQB7AQAuAAQKfzQAAhYACQkVI/UAAGQDABYACQkVI/UAAGQDAAAA.',
Ic='Icphunter:BAAALgAECgkJAQAAAA==.',
Im='Imàdrood:BAABLgAECn8tAAMXAAkJJRzKFgAOAgAXAAgJZRvKFgAOAgAYAAcJEBJWGQBuAQAAAA==.',
In='Inukari:BAAALgADCgcJBwAAAA==.Invincible:BAAALgADCgQJBAAAAA==.',
Is='Iscorpiusi:BAAALgAECgMJBAAAAA==.',
Ja='Jaelana:BAABLgAECn81AAMMAAgJsxJAHgDAAQAMAAgJsxJAHgDAAQAZAAgJJAdiCwBXAQAAAA==.Jaenerys:BAAALgADCgcJBwABLgAECgEJAQAFAAAAAA==.Jaguarinsito:BAAALgAECgkJBwAAAA==.Janoski:BAAALgADCgEJAQAAAA==.',
Je='Jerrwolf:BAAALgADCggJGQAAAA==.',
Jo='Jorkinit:BAAALgAECgUJCQABLgAFFAEJAQAFAAAAAA==.',
Jp='Jpl:BAAALgAECgkJCwAAAA==.',
Ka='Kafka:BAAALgADCgMJAwABLgAECgcJEQAFAAAAAA==.Kamideath:BAAALgAECgQJCAABLgAECgcJNAAOAPAkAA==.Kamidh:BAAALgADCgkJFQABLgAECgcJNAAOAPAkAA==.Kamihunt:BAAALgADCgQJBAABLgAECgcJNAAOAPAkAA==.Kamikozy:BAABLgAECn80AAIOAAcJ8CQdFwBiAgAOAAcJ8CQdFwBiAgAAAA==.Kasharas:BAABLgAECn8ZAAMMAAgJ1gxzLQBfAQAMAAgJ1gxzLQBfAQAIAAEJ6QWzkwAjAAAAAA==.Katalena:BAABLgAECn8aAAMQAAcJvyPWHAC9AgAQAAcJvyPWHAC9AgAaAAIJEgXshQBhAAAAAA==.',
Ke='Keybinds:BAAALgAFFAEJAQAAAA==.',
Kh='Khain:BAAALgAECgEJAQAAAA==.Khealer:BAABLgAECn8VAAIbAAcJPA17IwAtAQAbAAcJPA17IwAtAQAAAA==.',
Ki='Kindi:BAABLgAECn8YAAIaAAYJiSIeDQBDAgAaAAYJiSIeDQBDAgAAAA==.Kitymeowmeow:BAACLgAFFH8PAAIcAAUJ4iIwAwCLAQAcAAUJ4iIwAwCLAQAuAAQKfysAAhwACQkhJkoCAHwDABwACQkhJkoCAHwDAAAA.',
Kl='Klausnomi:BAACLgAFFH8MAAIIAAQJ8AyGEgAfAQAIAAQJ8AyGEgAfAQAuAAQKfzMAAggACQm/FygaAEICAAgACQm/FygaAEICAAAA.',
Ko='Kowalzky:BAAALgAECgQJCAAAAA==.',
Kr='Krow:BAABLgAECn8VAAILAAYJHR/ZFQCLAQALAAYJHR/ZFQCLAQAAAA==.',
Ku='Kuup:BAAALgAECgUJBQAAAA==.',
Ky='Kyrieherbing:BAAALgADCgIJAwAAAA==.Kyruptôs:BAAALgADCgEJAQAAAA==.',
La='Lalisaa:BAAALgAECgcJBwABLgAECggJHgAOAJ8bAA==.Lasina:BAAALgADCgMJBQAAAA==.Lastdance:BAAALgAECgYJCgAAAA==.',
Li='Lilithe:BAAALgADCgkJCQAAAA==.Lillyvera:BAAALgAECgEJAQAAAA==.Lilpsycho:BAAALgADCgYJDwAAAA==.',
Lo='Lokie:BAAALgAECgUJDAAAAA==.',
Lu='Lucia:BAABLgAECn8bAAIQAAgJtBEKNQCpAQAQAAgJtBEKNQCpAQAAAA==.',
Ly='Lynth:BAAALgADCgMJAwAAAA==.',
Ma='Magnusbane:BAAALgADCgYJBgABLgAECgcJHAAFAAAAAQ==.Maidokasa:BAAALgADCgUJBwAAAA==.Maja:BAABLgAECn8jAAMBAAcJ/BjEEACcAQABAAcJaxTEEACcAQAdAAUJXBa5BgBLAQAAAA==.Malaqor:BAABLgAECn8vAAIeAAgJdiSlAQAEAwAeAAgJdiSlAQAEAwAAAA==.Malla:BAAALgAECgQJBwAAAA==.Mamagoose:BAAALgADCgcJBwABLgAECggJJwASAO0ZAA==.Maylida:BAAALgAECgQJBAABLgAFFAUJBwACALkhAA==.',
Mc='Mcflÿ:BAAALgADCgEJAQAAAA==.',
Me='Megryn:BAAALgAECgMJAwAAAA==.',
Mi='Mistynyxy:BAAALgAECgUJBQAAAA==.',
Mo='Mojojuice:BAABLgAECn8dAAIIAAgJHiStAwDLAgAIAAgJHiStAwDLAgAAAA==.Montar:BAABLgAECn8cAAIRAAYJLCSRGAAMAgARAAYJLCSRGAAMAgAAAA==.Moonjuice:BAABLgAECn8kAAMXAAkJ9xE0NgA/AQAXAAgJaBA0NgA/AQAYAAcJqAicKAD9AAAAAA==.Moonlightt:BAAALgADCgEJAQAAAA==.',
Na='Nahaii:BAABLgAECn8gAAINAAgJbBplJADxAQANAAgJbBplJADxAQABLgAFFAUJCwARAJ0SAA==.Nanalli:BAAALgADCgIJAgAAAA==.',
Ne='Nelos:BAABLgAECn8kAAIfAAgJ6hp0CQBXAgAfAAgJ6hp0CQBXAgAAAA==.Neovisus:BAAALgAECgYJDwAAAA==.',
Ni='Nia:BAAALgAECggJEgAAAA==.Nineline:BAAALgADCgEJAQABLgAECgYJHQALAOUcAA==.',
No='Nozarashi:BAABLgAECn8bAAINAAYJpR4bMAC5AQANAAYJpR4bMAC5AQAAAA==.',
Ob='Obzen:BAACLgAFFH8FAAILAAMJbBFzIADcAAALAAMJbBFzIADcAAAuAAQKfy0AAgsACQnvHV0TAHYCAAsACQnvHV0TAHYCAAAA.',
Om='Omegalul:BAAALgAECgMJAwABLgAFFAYJFwAOAEAYAA==.',
Oo='Oopsikeelu:BAAALgADCgYJBgAAAA==.',
Pe='Pepperdogs:BAAALgAECgQJBAAAAA==.',
Po='Poisontips:BAAALgAECgMJBAAAAA==.',
Pr='Preast:BAAALgAECgEJAQAAAA==.',
Qk='Qkslvr:BAABLgAECn8kAAIRAAgJ5B2oDgBiAgARAAgJ5B2oDgBiAgAAAA==.',
Qu='Quackster:BAAALgAFFAIJAgABLgAFFAUJBwACALkhAA==.',
Ra='Randlidan:BAABLgAECn8YAAIKAAgJ+x90CQDLAgAKAAgJ+x90CQDLAgAAAA==.Randomcow:BAABLgAECn8gAAINAAYJkA6bfQDmAAANAAYJkA6bfQDmAAAAAA==.',
Re='Reidai:BAAALgAECgIJBAAAAA==.Remixedk:BAAALgAECgcJCgAAAA==.',
Ro='Roargorr:BAAALgAECgUJDgAAAA==.',
Ru='Rutabaga:BAAALgAECgIJAwAAAA==.',
Sa='Sadeas:BAAALgADCgQJBAAAAA==.Sadler:BAAALgADCgcJEwAAAA==.Sanctu:BAAALgAECgUJDgABLgAFFAUJDAAEAPUUAA==.',
Sc='Scarletnight:BAAALgADCgUJBQAAAA==.',
Se='Servusnape:BAAALgAECgEJAQAAAA==.',
Si='Silicos:BAAALgADCgIJAgABLgADCgYJBgAFAAAAAA==.',
Sk='Skywarp:BAAALgAECgcJBwAAAA==.',
Sl='Slapnchop:BAAALgAECgMJAwAAAA==.Slimjaedy:BAAALgAECgEJAQAAAA==.',
Sm='Smightful:BAABLgAECn8UAAIbAAgJRA3SHQBbAQAbAAgJRA3SHQBbAQAAAA==.Smol:BAABLgAECn8XAAIOAAYJuwtxfQAWAQAOAAYJuwtxfQAWAQAAAA==.',
St='Stan:BAAALgADCgYJCAABLgAECgcJEQAFAAAAAA==.Strexxi:BAAALgADCgMJBAAAAA==.',
Su='Summerdawn:BAAALgADCgcJFAAAAA==.Supersayan:BAAALgAECgMJAwABLgAECgYJDwAFAAAAAA==.Superspike:BAACLgAFFH8PAAIOAAUJGx5gHQBvAQAOAAUJGx5gHQBvAQAuAAQKfysAAg4ACQmLIyEYABoDAA4ACQmLIyEYABoDAAAA.Surshock:BAABLgAECn8dAAIIAAgJ4RQ/KQDLAQAIAAgJ4RQ/KQDLAQAAAA==.',
Sy='Sylaz:BAAALgAECgYJCAAAAA==.',
Ta='Taekay:BAABLgAFFH8GAAMgAAMJ4iC/CgAlAQAgAAMJ4iC/CgAlAQANAAIJsgoBfwCTAAABLgAFFAcJIAALAOchAA==.Takamine:BAABLgAECn8kAAIhAAgJRg3hCQCGAQAhAAgJRg3hCQCGAQAAAA==.Talath:BAABLgAECn8VAAISAAYJMBWBLQBWAQASAAYJMBWBLQBWAQAAAA==.Talos:BAABLgAECn8SAAIEAAgJAAl9gQAmAQAEAAgJAAl9gQAmAQAAAA==.',
Te='Terraluna:BAAALgADCgYJBgAAAA==.',
To='Totembutter:BAAALgADCgMJAwAAAA==.',
Tw='Twotswat:BAABLgAECn8kAAQiAAgJpB1ICwA1AgAiAAgJVR1ICwA1AgAUAAMJ/A31IwCfAAAjAAIJrRf+LACNAAAAAA==.Twysted:BAAALgAECggJDgAAAA==.',
Ug='Ugin:BAAALgADCgYJCAAAAA==.',
Um='Umdrah:BAAALgADCgEJAQAAAA==.',
Va='Valsong:BAAALgADCgcJCwAAAA==.Vanillalatte:BAABLgAECn8aAAIkAAgJNR8RAgBMAgAkAAgJNR8RAgBMAgAAAA==.Vanillarista:BAAALgAECggJEQAAAA==.Varwyn:BAAALgADCgMJAwAAAA==.',
Vo='Vonhance:BAAALgAECgEJAQAAAA==.Vonwrath:BAAALgAECgEJAQAAAA==.',
Vy='Vynne:BAAALgADCgcJAQAAAA==.',
Wa='Wakingdeath:BAABLgAECn8UAAINAAYJxBrHVAA/AQANAAYJxBrHVAA/AQAAAA==.',
We='Wesdarian:BAAALgAECgUJBQAAAA==.',
Wh='Whatdoisay:BAAALgADCgYJBgAAAA==.Whoami:BAABLgAECn8UAAIXAAgJYhGhVABVAQAXAAgJYhGhVABVAQAAAA==.',
Xe='Xer:BAABLgAECn8UAAIOAAUJuA1mlwDkAAAOAAUJuA1mlwDkAAAAAA==.',
Xi='Xirious:BAAALgAFFAIJAwAAAA==.',
Xo='Xor:BAAALgADCgQJBAAAAA==.',
Xu='Xur:BAABLgAECn8oAAIEAAgJ9BzJDgBRAgAEAAgJ9BzJDgBRAgAAAA==.',
Yo='Yonko:BAABLgAECn8hAAMcAAgJBRt6FABJAgAcAAgJBRt6FABJAgALAAQJiAuXPAClAAAAAA==.',
Ys='Ys:BAAALgADCgcJCwABLgAECgYJFwABAPccAA==.',
Ze='Zev:BAAALgADCggJCAAAAA==.',
Zu='Zulgathar:BAAALgADCgYJBgAAAA==.',
['Ís']='Ísolde:BAABLgAECn8eAAQOAAgJnxtkJgAKAgAOAAgJnxtkJgAKAgAlAAEJnBm4CwBNAAAkAAEJPAmGCwAwAAAAAA==.',
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

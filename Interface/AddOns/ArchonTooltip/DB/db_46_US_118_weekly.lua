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

local lookup = {'Warrior-Fury','DemonHunter-Devourer','DeathKnight-Unholy','Druid-Feral','Warrior-Protection','Unknown-Unknown','Paladin-Retribution','Mage-Frost','Druid-Restoration','Monk-Windwalker','Priest-Discipline','Priest-Holy','Priest-Shadow','DeathKnight-Blood','Hunter-BeastMastery','Evoker-Augmentation','Evoker-Devastation','Paladin-Holy','Hunter-Survival','DemonHunter-Havoc','Warrior-Arms','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','DemonHunter-Vengeance','Shaman-Elemental','Rogue-Assassination',}
local provider = {region='US',realm='Haomarush',name='US',type='weekly',zone=46,date='2026-05-01',data={Ad='Adderall:BAAALgAECggJDgAAAA==.',
Al='Alexya:BAAALgADCgIJAgAAAA==.All:BAAALgADCgEJAQAAAA==.Alphahawk:BAABLgAECn8nAAIBAAkJfRaGBQBhAgABAAkJfRaGBQBhAgAAAA==.',
Ap='Apocalipsis:BAAALgAECgMJAwAAAA==.',
Aq='Aquilis:BAABLgAECn8QAAICAAgJcReZVgCeAQACAAgJcReZVgCeAQAAAA==.',
Ar='Aramis:BAAALgAECgEJAQABLgAECgcJGQADAGshAA==.Arathrok:BAABLgAECn8ZAAIDAAcJayHLPwA5AgADAAcJayHLPwA5AgAAAA==.',
As='Asha:BAAALgAFFAQJBAAAAA==.Asmoday:BAABLgAECn8aAAIDAAgJkx4MDQBeAgADAAgJkx4MDQBeAgAAAA==.Asunawa:BAAALgADCgUJBQAAAA==.',
Au='Aundarr:BAAALgADCgEJAQABLgAECggJGgADAJMeAA==.Autoshift:BAABLgAECn8UAAIEAAcJSQuVCgA5AQAEAAcJSQuVCgA5AQAAAA==.',
Ba='Bat:BAAALgAECgcJEAAAAA==.',
Be='Benedictine:BAAALgAECgEJAwAAAA==.',
Bi='Bigcleavage:BAABLgAECn8ZAAIFAAgJRRo9CACzAQAFAAgJRRo9CACzAQAAAA==.',
Bl='Blueberrypie:BAAALgAECgQJBwABLgAECgYJEwAGAAAAAA==.',
Bo='Boomster:BAAALgAFFAcJAwAAAA==.',
Br='Bridgetpower:BAAALgADCgIJAgAAAA==.',
Ca='Calixta:BAABLgAECn8YAAIHAAcJGCQBKACFAgAHAAcJGCQBKACFAgAAAA==.Carbshock:BAAALgADCgYJCgAAAA==.',
Ce='Ceroah:BAAALgAECgYJCQAAAA==.',
Ch='Cherrypie:BAAALgAECgIJBAABLgAECgYJEwAGAAAAAA==.',
Cy='Cylla:BAACLgAFFH8FAAIIAAIJlQljUQCeAAAIAAIJlQljUQCeAAAuAAQKfysAAggACAlBHXAbAAcCAAgACAlBHXAbAAcCAAAA.',
Di='Dilfdormu:BAAALgAECgYJDwAAAA==.',
Do='Donkey:BAAALgADCgIJAgAAAA==.Doson:BAABLgAECn8mAAIJAAgJNx9NEAC1AgAJAAgJNx9NEAC1AgAAAA==.',
Dr='Dratak:BAACLgAFFH8aAAIFAAYJ4COSAAAQAgAFAAYJ4COSAAAQAgAuAAQKf0QAAgUACQleJS0AAG0DAAUACQleJS0AAG0DAAAA.Dread:BAABLgAECn8bAAIKAAgJixq5EAB2AgAKAAgJixq5EAB2AgAAAA==.Dred:BAAALgAECgIJBgAAAA==.Drizbul:BAAALgADCgEJAQABLgAFFAYJGgAFAOAjAA==.',
Ea='Earthswrath:BAAALgAECgUJDQAAAA==.',
El='Elitzai:BAAALgAECgIJAgAAAA==.',
Em='Emeralda:BAAALgADCgcJDQAAAA==.',
Ev='Evalueate:BAAALgAECgMJAwAAAA==.',
Fl='Fluf:BAAALgADCgcJDAAAAA==.',
Fr='Frocknor:BAAALgAECgUJCQAAAA==.',
Fu='Fuki:BAAALgAECgQJCgAAAA==.Furrymythh:BAAALgAECgQJBAAAAA==.',
Fy='Fyrstureinn:BAAALgADCgIJAgAAAA==.',
Ga='Galumian:BAACLgAFFH8cAAILAAYJ1CTPAAByAgALAAYJ1CTPAAByAgAuAAQKfzMABAsACQlsJaUDAC4DAAsACAlDJaUDAC4DAAwABwkSETUvAIYBAA0AAgncIbJGAMkAAAAA.',
Go='Goo:BAAALgAECgcJDAABLgAFFAUJDQAOALsYAA==.',
Gu='Guy:BAAALgADCgcJBwAAAA==.',
Ha='Hamhock:BAAALgAECgQJCQAAAA==.Haradali:BAAALgADCgEJAQAAAA==.',
Ho='Holydiah:BAAALgAECgQJBwAAAA==.Holypriest:BAAALgAECgYJBgAAAA==.Hordehound:BAAALgADCgIJAgAAAA==.',
Ja='Jakimozo:BAAALgAECgYJBgAAAA==.Jasminetea:BAABLgAECn8ZAAILAAcJdSCtEgAdAgALAAcJdSCtEgAdAgAAAA==.',
Ju='Judgecutie:BAAALgAECgkJCQAAAA==.',
Ka='Kadesh:BAAALgADCgYJBgABLgAECggJGgADAJMeAA==.Kayla:BAAALgAECgEJAgAAAA==.',
Ki='Kiran:BAAALgAECgEJAgAAAA==.',
Kr='Kroth:BAABLgAECn8vAAIJAAkJBxBvHACdAQAJAAkJBxBvHACdAQAAAA==.',
Ku='Kubfury:BAAALgAECgIJAgAAAA==.Kudi:BAAALgAECgYJDAAAAA==.',
['Kí']='Kíllian:BAABLgAECn8YAAIPAAgJqR7ZCQBfAgAPAAgJqR7ZCQBfAgAAAA==.',
La='Labatblue:BAAALgADCgEJAQAAAA==.Lacey:BAAALgAECgYJBgAAAA==.Lavitz:BAAALgAECgYJCgAAAA==.',
Lo='Loris:BAAALgAECgcJBgAAAA==.',
Lu='Lunaci:BAABLgAECn8UAAMQAAgJtxCCFQBTAQAQAAcJtg+CFQBTAQARAAYJlQ44BwAeAQAAAA==.Lunylu:BAAALgADCgUJBQAAAA==.',
Ma='Magicmagicin:BAAALgAECgMJAgAAAA==.Magnusson:BAABLgAECn8bAAIFAAgJyBVzBgDnAQAFAAgJyBVzBgDnAQAAAA==.Mandrah:BAAALgAECgYJCQAAAA==.Masutado:BAABLgAECn8bAAIIAAgJZBYvHwDxAQAIAAgJZBYvHwDxAQAAAA==.Maven:BAAALgAECgQJBAAAAA==.Mayelle:BAAALgADCgkJEAAAAA==.Mayvoker:BAAALgADCgEJAQAAAA==.',
Me='Metier:BAAALgAECgMJAwABLgAFFAIJBQAFAFwiAA==.',
Mi='Miao:BAAALgAECgYJBgAAAA==.Mirror:BAAALgAECgcJBQAAAA==.Misfortune:BAAALgAECgIJAwABLgAECgcJGAAHABgkAA==.Mitsy:BAAALgAECgcJDQAAAA==.',
Mo='Money:BAABLgAECn8jAAMHAAgJGCGgIACpAgAHAAcJFiGgIACpAgASAAIJbgeQPgBuAAAAAA==.Montipython:BAAALgADCgMJAwAAAA==.Moons:BAACLgAFFH8PAAITAAUJahVEAQBmAQATAAUJahVEAQBmAQAuAAQKfz8AAhMACQmwIZsBALkCABMACQmwIZsBALkCAAAA.Mothman:BAAALgADCgUJBAAAAA==.Moussebreath:BAABLgAECn8VAAILAAcJWx9UDgBVAgALAAcJWx9UDgBVAgAAAA==.',
Mu='Mudpie:BAAALgAECgYJEwAAAA==.Munco:BAABLgAECn8pAAIUAAgJiyEqAgCdAgAUAAgJiyEqAgCdAgAAAA==.Muncola:BAAALgADCgYJBwABLgAECggJKQAUAIshAA==.Muncoli:BAAALgAECgEJAQABLgAECggJKQAUAIshAA==.Muncolito:BAAALgADCgEJAQABLgAECggJKQAUAIshAA==.Mungus:BAAALgAECgQJCQAAAA==.',
My='Mythhleremix:BAAALgADCgUJBgABLgAFFAIJBQAFAFwiAA==.',
Ne='Nellie:BAAALgAECgYJEwAAAA==.Newtree:BAAALgAECgcJBgAAAA==.',
No='Notker:BAABLgAECn8bAAIMAAgJHCNuAQAfAwAMAAgJHCNuAQAfAwAAAA==.',
Ny='Nynaa:BAAALgADCgIJAgABLgAECggJGgADAJMeAA==.',
Or='Orcwarr:BAABLgAECn8YAAQFAAcJ2xIfCwB1AQAFAAcJ2xIfCwB1AQABAAMJlAlujwCAAAAVAAEJPQsHQwAzAAAAAA==.',
Pa='Panders:BAAALgAFFAMJAwAAAA==.Patadita:BAAALgAECgYJCwAAAA==.',
Pe='Pecanpie:BAAALgAECgEJAQABLgAECgYJEwAGAAAAAA==.Penne:BAAALgADCgcJDAAAAA==.',
Pi='Pinkpony:BAAALgAECgcJBgAAAA==.Pipsi:BAAALgAECgEJAQABLgAECggJKQAUAIshAA==.',
Pk='Pk:BAAALgADCgQJBAABLgAECgcJCwAGAAAAAA==.',
Pr='Pryor:BAAALgADCgIJAgABLgAECggJGgADAJMeAA==.',
Qu='Quiverinpalm:BAAALgAECgcJDQAAAA==.',
Ra='Rageoverrun:BAAALgADCgYJCgAAAA==.',
Re='Remiwog:BAAALgADCggJCgAAAA==.Rennik:BAACLgAFFH8FAAMWAAIJVxnkBAC7AAAWAAIJVxnkBAC7AAAXAAEJVwnlXABNAAAuAAQKfykABBYACAmAI1YOAOMBABYABQn3IVYOAOMBABcABgk+HXMgALIBABgAAwlVJAoIANcAAAAA.Rentiak:BAAALgAECgYJEwAAAA==.',
Ru='Rue:BAAALgAECgYJCwAAAA==.',
Sa='Saffy:BAAALgADCgYJBwAAAA==.',
Sc='Scorevival:BAAALgAECgEJAQAAAA==.Scorewin:BAEBLgAECn8gAAIZAAgJFyTeAQD1AgAZAAgJFyTeAQD1AgAAAA==.',
Se='Serenity:BAAALgAECgEJAwABLgAECgcJFwACAL0jAA==.Serraku:BAAALgAECgEJAQAAAA==.',
Sh='Shadowfern:BAEALgAECgMJBgAAAA==.Shalniar:BAAALgADCgYJBgABLgAFFAUJDwAaAAIlAA==.Shioh:BAAALgADCgUJBQAAAA==.Shocky:BAAALgAECgEJAQAAAA==.',
Si='Sienda:BAAALgADCgQJBAAAAA==.Siñ:BAABLgAECn8VAAIbAAgJKAWdBgBGAQAbAAgJKAWdBgBGAQAAAA==.',
Sk='Skeetshootah:BAABLgAECn8aAAIPAAgJ0xXdEwDzAQAPAAgJ0xXdEwDzAQAAAA==.',
Sl='Slowbadon:BAABLgAECn8VAAISAAgJmRP4GQB9AQASAAgJmRP4GQB9AQAAAA==.',
St='Stabpokestab:BAAALgADCgcJDQAAAA==.Stay:BAAALgAECgcJBgAAAA==.Streetlight:BAAALgAECgIJAgABLgABCgEJAQAGAAAAAA==.Streetlights:BAAALgAECgUJDQABLgABCgEJAQAGAAAAAA==.Streets:BAAALgAECggJEQABLgABCgEJAQAGAAAAAA==.',
Ta='Tank:BAACLgAFFH8FAAIFAAIJXCLMCgDPAAAFAAIJXCLMCgDPAAAuAAQKfyYAAgUACAlbJa0CADwDAAUACAlbJa0CADwDAAAA.',
Te='Teafayd:BAAALgADCgcJDgAAAA==.',
Th='Thunderdot:BAABLgAECn8iAAINAAgJ/hxQDgCeAgANAAgJ/hxQDgCeAgAAAA==.Thunderlok:BAAALgADCgEJAgAAAA==.',
Ti='Tilvayne:BAABLgAECn87AAIDAAkJvB7iBQDCAgADAAkJvB7iBQDCAgAAAA==.',
To='Tomayter:BAABLgAECn8bAAIMAAgJvB1WBACOAgAMAAgJvB1WBACOAgAAAA==.',
Tr='Trap:BAAALgAECgEJAgABLgAECgcJFwACAL0jAA==.Trinitee:BAAALgADCgQJBAAAAA==.Trisriane:BAAALgAECgMJBgABLgAECggJHAAHADQaAA==.Trist:BAABLgAECn8cAAIHAAgJNBp0PgArAgAHAAgJNBp0PgArAgAAAA==.',
Tu='Turbogoat:BAABLgAECn8hAAIDAAgJuh4HLQCFAgADAAgJuh4HLQCFAgAAAA==.Turok:BAAALgAECgEJAgABLgAFFAMJBQATAEsYAA==.',
Tw='Twaave:BAABLgAECn8gAAIIAAgJUyHxGwAHAwAIAAgJUyHxGwAHAwAAAA==.',
['Tÿ']='Tÿ:BAAALgAECgEJAgAAAA==.',
Va='Vaz:BAAALgAECgYJCwAAAA==.Vazp:BAAALgAECgUJBQABLgAECgYJCwAGAAAAAA==.',
Wa='Waltz:BAAALgADCgEJAQAAAA==.',
Yi='Yikezvelobtw:BAAALgAECgIJAgAAAA==.',
Ze='Zennah:BAAALgADCgQJBAAAAA==.Zerene:BAABLgAECn8bAAMWAAgJaRR2BQBwAQAWAAgJaRR2BQBwAQAXAAQJpAYAbgCwAAAAAA==.',
['Æs']='Æsc:BAABLgAECn8bAAIOAAgJchbfCQB3AQAOAAgJchbfCQB3AQAAAA==.',
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

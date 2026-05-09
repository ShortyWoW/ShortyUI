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

local lookup = {'Warrior-Fury','DemonHunter-Devourer','DeathKnight-Unholy','Monk-Windwalker','Druid-Feral','Warrior-Protection','Druid-Guardian','Paladin-Retribution','Mage-Frost','Druid-Restoration','Priest-Discipline','Priest-Holy','Priest-Shadow','DeathKnight-Blood','Unknown-Unknown','Hunter-BeastMastery','Evoker-Augmentation','Evoker-Devastation','Paladin-Holy','Hunter-Survival','DemonHunter-Havoc','Druid-Balance','Warrior-Arms','Warlock-Destruction','Warlock-Demonology','Warlock-Affliction','DemonHunter-Vengeance','Shaman-Elemental','Rogue-Assassination',}
local provider = {region='US',realm='Haomarush',name='US',type='weekly',zone=46,date='2026-05-08',data={Ad='Adderall:BAAALgAECggJDgAAAA==.',
Al='Alexya:BAAALgADCgIJAgAAAA==.All:BAAALgADCgEJAQAAAA==.Alphahawk:BAABLgAECn8wAAIBAAkJoRmSBwBzAgABAAkJoRmSBwBzAgAAAA==.',
Ap='Apocalipsis:BAAALgAECgMJAwAAAA==.',
Aq='Aquilis:BAABLgAECn8SAAICAAgJYBmbVgCeAQACAAgJYBmbVgCeAQAAAA==.',
Ar='Aramis:BAAALgAECgUJCQABLgAECggJGgADAGkgAA==.Arathrok:BAABLgAECn8aAAIDAAgJaSDLPwA5AgADAAgJaSDLPwA5AgAAAA==.',
As='Asha:BAABLgAFFH8IAAIEAAQJAhWsBwBKAQAEAAQJAhWsBwBKAQAAAA==.Asmoday:BAABLgAECn8eAAIDAAgJTB/VFABUAgADAAgJTB/VFABUAgAAAA==.Asunawa:BAAALgADCgUJBQAAAA==.',
Au='Aundarr:BAAALgADCgEJAQABLgAECggJHgADAEwfAA==.Autoshift:BAABLgAECn8WAAIFAAgJ7gqECwBhAQAFAAgJ7gqECwBhAQAAAA==.',
Ba='Bat:BAAALgAECgcJEgAAAA==.',
Be='Benedictine:BAAALgAECgEJBAAAAA==.',
Bi='Bigcleavage:BAABLgAECn8aAAIGAAgJRRr4CwCnAQAGAAgJRRr4CwCnAQAAAA==.',
Bl='Blueberrypie:BAAALgAECgQJBwABLgAECggJFQAHAKkeAA==.',
Bo='Boomster:BAAALgAFFAgJAwAAAA==.',
Br='Bridgetpower:BAAALgADCgIJAgAAAA==.',
Ca='Calixta:BAABLgAECn8ZAAIIAAgJaSIAKACFAgAIAAgJaSIAKACFAgAAAA==.Carbshock:BAAALgADCgYJCgAAAA==.',
Ce='Ceroah:BAAALgAECgYJCgAAAA==.',
Ch='Cherrypie:BAAALgAECgIJBAABLgAECggJFQAHAKkeAA==.',
Co='Coodown:BAAALgAECgYJCAAAAA==.',
Cy='Cylla:BAACLgAFFH8IAAIJAAMJfwnGTgDoAAAJAAMJfwnGTgDoAAAuAAQKfy0AAgkACAlCHWgfAC4CAAkACAlCHWgfAC4CAAAA.',
Di='Dilfdormu:BAAALgAECgcJDwAAAA==.',
Do='Donkey:BAAALgADCgIJAgAAAA==.Doson:BAABLgAECn8sAAIKAAkJ/BxJEAC1AgAKAAkJ/BxJEAC1AgAAAA==.',
Dr='Dratak:BAACLgAFFH8gAAIGAAYJSCXfAAAjAgAGAAYJSCXfAAAjAgAuAAQKf00AAgYACQmVJUkAAHEDAAYACQmVJUkAAHEDAAAA.Dread:BAABLgAECn8bAAIEAAgJixq5EAB2AgAEAAgJixq5EAB2AgAAAA==.Dreadfang:BAAALgADCgQJBAAAAA==.Dred:BAAALgAECgMJBwAAAA==.Drizbul:BAAALgADCgEJAQABLgAFFAYJIAAGAEglAA==.',
Ea='Earthswrath:BAAALgAECgUJDgAAAA==.',
El='Elitzai:BAAALgAECgIJAgAAAA==.',
Em='Emeralda:BAAALgADCgcJDQAAAA==.',
Ev='Evalueate:BAAALgAECgQJBAAAAA==.',
Fl='Fluf:BAAALgADCgcJDAAAAA==.',
Fr='Frocknor:BAAALgAECgUJDAAAAA==.',
Fu='Fuki:BAAALgAECgQJDAAAAA==.Furrymythh:BAAALgAECgQJBAABLgAFFAMJCQAGAB8kAA==.',
Fy='Fyrstureinn:BAAALgADCgIJAgAAAA==.',
Ga='Galumian:BAACLgAFFH8jAAILAAcJZCLiAAC9AgALAAcJZCLiAAC9AgAuAAQKfzMABAsACQlsJaQDAC4DAAsACAlDJaQDAC4DAAwABwkSETwvAIYBAA0AAgncIbVGAMkAAAAA.',
Go='Goo:BAAALgAECgcJDAABLgAFFAUJEQAOALsYAA==.',
Gu='Guy:BAAALgADCgcJBwAAAA==.',
Ha='Hamhock:BAAALgAECgQJCgAAAA==.Haradali:BAAALgAECgIJAgAAAA==.',
Ho='Holydiah:BAAALgAECgYJDQAAAA==.Holypriest:BAAALgAECgYJBgAAAA==.Hordehound:BAAALgADCgIJAgAAAA==.',
Ja='Jakimozo:BAAALgAECgcJDAAAAA==.Jasminetea:BAABLgAECn8eAAMLAAgJjx2rEgAdAgALAAcJdSCrEgAdAgAMAAQJjQkENgClAAAAAA==.',
Ju='Judgecutie:BAAALgAECgkJCQAAAA==.',
Ka='Kadesh:BAAALgADCgYJBgABLgAECggJHgADAEwfAA==.Kayla:BAAALgAECgEJAgAAAA==.',
Ki='Kiran:BAAALgAECgEJAgAAAA==.',
Kr='Krizara:BAAALgAECgEJAQABLgAECgUJDAAPAAAAAA==.Kroth:BAABLgAECn84AAIKAAkJ7xB0HQDYAQAKAAkJ7xB0HQDYAQAAAA==.',
Ku='Kubfury:BAAALgAECgIJAgAAAA==.Kudi:BAAALgAECgYJDAAAAA==.',
['Kí']='Kíllian:BAABLgAECn8cAAIQAAgJ9R+lDgBjAgAQAAgJ9R+lDgBjAgAAAA==.',
La='Labatblue:BAAALgADCgEJAQAAAA==.Lacey:BAAALgAECgYJBgAAAA==.Lavitz:BAAALgAECgYJCgAAAA==.',
Lo='Loris:BAAALgAECgcJBgAAAA==.',
Lu='Lunaci:BAABLgAECn8bAAMRAAgJQxQrEwCwAQARAAgJThMrEwCwAQASAAYJmQ7JCQAFAQAAAA==.Lunylu:BAAALgADCgUJBQAAAA==.',
Ma='Magicmagicin:BAAALgAECgMJAgAAAA==.Magnusson:BAABLgAECn8fAAIGAAgJnRkABwAYAgAGAAgJnRkABwAYAgAAAA==.Mandrah:BAAALgAECgYJCQAAAA==.Masutado:BAABLgAECn8fAAIJAAgJphgGKAACAgAJAAgJphgGKAACAgAAAA==.Maven:BAAALgAECgQJBAAAAA==.Mayelle:BAAALgADCgkJEAAAAA==.Mayernnaise:BAAALgAECgQJBAAAAA==.Mayvoker:BAAALgADCgEJAQAAAA==.',
Me='Metier:BAAALgAECgUJCQABLgAFFAMJCQAGAB8kAA==.',
Mi='Miao:BAAALgAECgYJBgAAAA==.Mirror:BAAALgAECgcJBQAAAA==.Misfortune:BAAALgAECgMJBAABLgAECggJGQAIAGkiAA==.Mitsy:BAABLgAECn8UAAINAAcJFg9BGwBhAQANAAcJFg9BGwBhAQAAAA==.',
Mo='Money:BAABLgAECn8jAAMIAAgJGCGdIACpAgAIAAcJFiGdIACpAgATAAIJbgfzTgBnAAAAAA==.Montipython:BAAALgADCgMJAwAAAA==.Moons:BAACLgAFFH8QAAIUAAUJahVEAQBmAQAUAAUJahVEAQBmAQAuAAQKfz8AAhQACQmwIT8BAA8DABQACQmwIT8BAA8DAAAA.Mothman:BAAALgADCgUJBAAAAA==.Moussebreath:BAABLgAECn8VAAILAAcJWx9RDgBVAgALAAcJWx9RDgBVAgAAAA==.',
Mu='Mudpie:BAABLgAECn8VAAIHAAgJqR59CQAJAgAHAAgJqR59CQAJAgAAAA==.Munco:BAABLgAECn8tAAIVAAgJFyK0AwCfAgAVAAgJFyK0AwCfAgAAAA==.Muncola:BAAALgAECgEJAQABLgAECggJLQAVABciAA==.Muncoli:BAAALgAECgMJBAABLgAECggJLQAVABciAA==.Muncolito:BAAALgADCgEJAQABLgAECggJLQAVABciAA==.Mungus:BAAALgAECgQJCQAAAA==.',
My='Mythhleremix:BAAALgADCgUJBgABLgAFFAMJCQAGAB8kAA==.',
Ne='Nellie:BAABLgAECn8XAAMWAAgJdQrJHgBAAQAWAAgJdQrJHgBAAQAKAAQJlQHHsABkAAAAAA==.Newtree:BAAALgAFFAQJAgAAAA==.',
No='Notker:BAABLgAECn8fAAIMAAgJQyT9AQAxAwAMAAgJQyT9AQAxAwAAAA==.',
Ny='Nynaa:BAAALgADCgIJAgABLgAECggJHgADAEwfAA==.',
Or='Orcwarr:BAABLgAECn8gAAQGAAgJ3hcuCAD6AQAGAAgJ3hcuCAD6AQABAAMJlAlyjwCAAAAXAAEJPQsHQwAzAAAAAA==.',
Pa='Panders:BAABLgAFFH8KAAIIAAQJ+AVKJAAbAQAIAAQJ+AVKJAAbAQAAAA==.Patadita:BAAALgAECgYJDgAAAA==.',
Pe='Pecanpie:BAAALgAECgEJAQABLgAECggJFQAHAKkeAA==.Penne:BAAALgADCgcJDAAAAA==.',
Pi='Pipsi:BAAALgAECgEJAQABLgAECggJLQAVABciAA==.',
Pk='Pk:BAAALgAECgUJBQABLgAFFAQJBQADACMWAA==.',
Pr='Pryor:BAAALgADCgIJAgABLgAECggJHgADAEwfAA==.',
Qu='Quiverinpalm:BAAALgAECgcJDgAAAA==.',
Ra='Rageoverrun:BAAALgADCgYJCgAAAA==.',
Re='Remiwog:BAAALgADCggJCgAAAA==.Rennik:BAACLgAFFH8JAAQYAAMJ4RtOBwCwAAAYAAIJWhlOBwCwAAAZAAIJIhP3WQCXAAAaAAEJ8CNLBQBjAAAuAAQKfy0ABBgACAmAI1kOAOMBABgABQn3IVkOAOMBABkABgk+HQ8pAMIBABoAAwlVJB8MAMYAAAAA.Rentiak:BAAALgAECgYJEwAAAA==.',
Ru='Rue:BAAALgAECgYJCwAAAA==.',
Sa='Saffy:BAAALgADCgYJBwAAAA==.',
Sc='Scorevival:BAAALgAECgEJAQAAAA==.Scorewin:BAEBLgAECn8hAAIbAAkJCiTeAQD1AgAbAAkJCiTeAQD1AgAAAA==.',
Se='Serenity:BAAALgAECgEJAwABLgAFFAEJAgAPAAAAAA==.Serraku:BAAALgAECgEJAQAAAA==.',
Sh='Shadowfern:BAEALgAECgMJBgAAAA==.Shalniar:BAAALgADCgYJBgABLgAFFAUJEwAcAAIlAA==.Shioh:BAAALgADCgUJBQAAAA==.Shocky:BAAALgAECgEJAQAAAA==.',
Si='Sienda:BAAALgADCgUJBAAAAA==.Sinappi:BAAALgAECgEJAQAAAA==.Siñ:BAABLgAECn8VAAIdAAgJKAXsCABCAQAdAAgJKAXsCABCAQAAAA==.',
Sk='Skeetshootah:BAABLgAECn8eAAIQAAgJjBZcHgDmAQAQAAgJjBZcHgDmAQAAAA==.',
Sl='Slowbadon:BAABLgAECn8XAAITAAgJLxWVIgBzAQATAAgJLxWVIgBzAQAAAA==.',
St='Stabpokestab:BAAALgADCgcJDQAAAA==.Stay:BAAALgAECgcJBgAAAA==.Streetlight:BAAALgAECgUJBwABLgABCgEJAQAPAAAAAA==.Streetlights:BAAALgAECgUJDQABLgABCgEJAQAPAAAAAA==.Streets:BAAALgAECggJEQABLgABCgEJAQAPAAAAAA==.',
Ta='Tank:BAACLgAFFH8JAAIGAAMJHyRGBwA3AQAGAAMJHyRGBwA3AQAuAAQKfygAAgYACAl/Ja4CADwDAAYACAl/Ja4CADwDAAAA.',
Te='Teafayd:BAAALgAECgMJBgAAAA==.',
Th='Thunderdot:BAABLgAECn8jAAINAAkJ+xxQDgCeAgANAAkJ+xxQDgCeAgAAAA==.Thunderlok:BAAALgADCgEJAgAAAA==.',
Ti='Tilvayne:BAABLgAECn9EAAIDAAkJ2x9wBwDmAgADAAkJ2x9wBwDmAgAAAA==.',
To='Tomayter:BAABLgAECn8fAAIMAAgJQyAYBQC3AgAMAAgJQyAYBQC3AgAAAA==.',
Tr='Trap:BAAALgAFFAEJAgAAAA==.Trinitee:BAAALgADCgYJCgAAAA==.Trisriane:BAAALgAECgMJBgABLgAECgkJHQAIAGwaAA==.Trist:BAABLgAECn8dAAIIAAkJbBpyPgArAgAIAAkJbBpyPgArAgAAAA==.',
Tu='Turbogoat:BAABLgAECn8kAAIDAAgJuh4ALQCFAgADAAgJuh4ALQCFAgAAAA==.Turok:BAAALgAECgEJAgABLgAFFAMJBQAUAEsYAA==.',
Tw='Twaave:BAABLgAECn8hAAIJAAkJlCHxGwAHAwAJAAkJlCHxGwAHAwAAAA==.',
['Tÿ']='Tÿ:BAAALgAECgQJBQAAAA==.',
Va='Vaz:BAAALgAECgYJCwAAAA==.Vazp:BAAALgAECgUJBQABLgAECgYJCwAPAAAAAA==.',
Wa='Waltz:BAAALgADCgEJAQAAAA==.',
Yi='Yikezvelobtw:BAAALgAECgIJAwAAAA==.',
Ze='Zennah:BAAALgADCgQJBAAAAA==.Zerene:BAABLgAECn8fAAMYAAgJbBSdBwBpAQAYAAgJbBSdBwBpAQAZAAcJ/wVfVwAmAQAAAA==.',
['Æs']='Æsc:BAABLgAECn8fAAIOAAgJmBedDACqAQAOAAgJmBedDACqAQAAAA==.',
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

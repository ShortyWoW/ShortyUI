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

local lookup = {'Mage-Fire','Monk-Windwalker','Priest-Holy','Warrior-Fury','Paladin-Retribution','Priest-Discipline','Shaman-Elemental','Shaman-Restoration','Warrior-Protection','Shaman-Enhancement','DeathKnight-Frost','Evoker-Preservation','Evoker-Devastation','Hunter-Survival','Druid-Guardian','DeathKnight-Unholy','Mage-Frost','DemonHunter-Devourer','Priest-Shadow','Hunter-BeastMastery','DemonHunter-Vengeance','Warlock-Demonology','Unknown-Unknown','Druid-Balance','Paladin-Holy','DemonHunter-Havoc','Paladin-Protection','Warlock-Destruction','DeathKnight-Blood','Druid-Restoration','Warlock-Affliction','Monk-Mistweaver','Monk-Brewmaster','Rogue-Subtlety',}
local provider = {region='US',realm='TheVentureCo',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abanados:BAABLgAECn8VAAIBAAcJKg5+AwBSAQABAAcJKg5+AwBSAQAAAA==.',
Ak='Akatsuki:BAABLgAECn8vAAICAAkJiCMcAQA5AwACAAkJiCMcAQA5AwAAAA==.',
Al='Althea:BAABLgAECn8kAAIDAAgJMxG0GACJAQADAAgJMxG0GACJAQAAAA==.',
Am='Ambition:BAAALgAECgEJAQABLgAFFAMJBwAEALMVAA==.Amoredis:BAAALgADCggJDgAAAA==.',
An='Animorpha:BAAALgAECgMJAwAAAA==.',
Ar='Ariane:BAAALgAECgIJAgAAAA==.Arkaen:BAABLgAECn8mAAIFAAgJMyBIHADAAgAFAAgJMyBIHADAAgAAAA==.Arkhyn:BAAALgAECgUJCAAAAA==.',
As='Ashengor:BAAALgAECgMJBAAAAA==.Asonda:BAEBLgAECn8aAAMDAAgJVxQaFwCZAQADAAcJLxUaFwCZAQAGAAUJfgjNJgDyAAAAAA==.Assi:BAAALgADCgEJAQAAAA==.',
Az='Azshauyssa:BAAALgAECgcJCgAAAA==.',
Ba='Baelsk:BAAALgADCgYJBgAAAA==.Bajamama:BAABLgAECn8hAAMHAAgJghRnEwC9AQAHAAgJghRnEwC9AQAIAAYJ/g7vTABPAQAAAA==.Batou:BAAALgADCgEJAQAAAA==.',
Be='Beans:BAAALgADCgUJBQAAAA==.Bel:BAAALgAECgMJAwABLgAECggJLQAJAJYiAA==.Betarius:BAAALgAECgQJBAABLgAECggJFwAIAFQeAA==.Betiff:BAABLgAECn8XAAMIAAgJVB7pEAA1AgAIAAcJSx3pEAA1AgAHAAcJ7BDcSQAgAQAAAA==.',
Bi='Birddog:BAAALgAECgkJCQAAAA==.',
Bl='Blazeschill:BAAALgADCgEJAQABLgAECgkJMgAKACMXAA==.Blooded:BAABLgAECn8XAAILAAkJgQ1nBACnAQALAAkJgQ1nBACnAQAAAA==.Bloodydraco:BAABLgAECn8sAAMMAAkJ8xUGBgArAgAMAAkJ8xUGBgArAgANAAEJpwWrGAAxAAAAAA==.Bloodymagus:BAAALgADCgkJCQAAAA==.',
Bo='Bolden:BAAALgADCgkJHQAAAA==.',
Br='Brelm:BAAALgADCgQJBwAAAA==.Brewzin:BAAALgADCgQJBAAAAA==.Bruwu:BAAALgAECgYJCAAAAA==.',
Bu='Bubblez:BAAALgADCgQJBAAAAA==.',
Ca='Cakebro:BAABLgAECn8xAAIOAAkJnx+9AgC7AgAOAAkJnx+9AgC7AgAAAA==.Camembert:BAABLgAECn8hAAIPAAgJfiP2AQAhAwAPAAgJfiP2AQAhAwAAAA==.Casii:BAAALgAECgcJDgAAAA==.',
Ce='Cele:BAAALgAECgMJBAAAAA==.Celyne:BAAALgAECgEJAQAAAA==.',
Ch='Chiizo:BAABLgAECn8UAAIGAAYJsRLSJwBXAQAGAAYJsRLSJwBXAQAAAA==.Chiror:BAAALgADCgYJCQAAAA==.Chubingus:BAABLgAECn8cAAIQAAgJgh48GAA7AgAQAAgJgh48GAA7AgAAAA==.Chuckmcstabb:BAAALgAECgEJAQAAAA==.Chufeng:BAAALgAECgYJCAABLgAECgkJKQAEAIskAA==.',
Co='Coggette:BAABLgAECn8UAAIRAAYJxgQeqADDAAARAAYJxgQeqADDAAAAAA==.Corvica:BAAALgADCgEJAQAAAA==.',
Cr='Crocubot:BAAALgAECgIJBQAAAA==.',
Cu='Cucuyknight:BAAALgADCgEJAgAAAA==.',
Da='Danaki:BAAALgAECgUJCQAAAA==.Dancookerton:BAAALgADCgUJBQAAAA==.Danorace:BAAALgAECgQJBQAAAA==.Darkcurve:BAAALgAECgYJCgAAAA==.Darkhope:BAAALgAECgYJCgAAAA==.',
De='Deija:BAABLgAECn8aAAISAAgJfh7HEgAnAgASAAgJfh7HEgAnAgAAAA==.Dekoo:BAABLgAECn8eAAIJAAYJ4yH7DAA7AgAJAAYJ4yH7DAA7AgAAAA==.Demon:BAAALgAECgcJEwAAAA==.Demoneyez:BAAALgAECgYJCQAAAA==.Deusene:BAABLgAECn8YAAITAAYJHhCdJwAKAQATAAYJHhCdJwAKAQAAAA==.',
Dr='Drakula:BAAALgAECgIJAgAAAA==.Dreadfang:BAABLgAECn8zAAIQAAkJMCNABQALAwAQAAkJMCNABQALAwAAAA==.Droka:BAABLgAECn8fAAIIAAcJKB64EgAiAgAIAAcJKB64EgAiAgAAAA==.',
El='Elavil:BAAALgADCgYJEAAAAA==.',
En='Endel:BAAALgADCgcJCwAAAA==.',
Eu='Eurotophobia:BAABLgAECn8WAAIFAAcJExSiRAB4AQAFAAcJExSiRAB4AQAAAA==.',
Ex='Exodia:BAABLgAECn8XAAMUAAcJkxX9QwBBAQAUAAYJLRb9QwBBAQAOAAMJJw4cJACrAAAAAA==.',
Fa='Faldrithor:BAAALgAECgMJAwAAAA==.',
Fe='Fellaria:BAABLgAECn8nAAMVAAkJnyOxAADtAgAVAAkJnyOxAADtAgASAAEJmA1XuwAwAAAAAA==.',
Fh='Fhyllo:BAAALgAECgYJDAAAAA==.',
Fl='Fluffybella:BAAALgAFFAIJAgAAAA==.',
Fo='Follaglas:BAABLgAECn8ZAAIUAAgJ1h/dCwCAAgAUAAgJ1h/dCwCAAgAAAA==.',
Ga='Gairen:BAAALgAECgQJBwAAAA==.Galadisis:BAABLgAECn8zAAMEAAkJfR+kAgDvAgAEAAkJTR+kAgDvAgAJAAIJ/BiMJACaAAAAAA==.Galtidor:BAAALgAECgIJAgAAAA==.',
Gh='Ghuldana:BAABLgAECn8bAAIWAAgJXx5qEgBPAgAWAAgJXx5qEgBPAgABLgAECgUJCQAXAAAAAA==.',
Gl='Glowgasm:BAAALgADCgMJAgAAAA==.',
Go='Goji:BAAALgADCgMJAwAAAA==.Goon:BAAALgAECgMJBAAAAA==.Goonann:BAAALgAECgkJEwAAAA==.',
Gr='Grimfoul:BAAALgADCgEJAQAAAA==.Gryari:BAAALgAECgQJBQAAAA==.',
Gu='Guiche:BAAALgAECgYJCAAAAA==.',
Gw='Gwiynevere:BAAALgAECgYJEQAAAA==.',
He='Heathclif:BAAALgADCgUJCgABLgAECgkJKQAEAIskAA==.Hellao:BAABLgAECn8rAAIYAAgJ/BUADwDgAQAYAAgJ/BUADwDgAQAAAA==.Hellmage:BAAALgADCgcJEQAAAA==.Hermano:BAAALgADCgUJBQAAAA==.',
Ho='Hoxpox:BAAALgADCgcJEQAAAA==.',
Hr='Hrimceald:BAAALgAECgYJCgAAAA==.',
Hy='Hylts:BAABLgAECn8eAAIKAAYJKRREDQAzAQAKAAYJKRREDQAzAQAAAA==.',
Id='Idpswhileafk:BAAALgADCgEJAQAAAA==.',
Il='Illithian:BAAALgAECgMJAwAAAA==.',
Im='Imalockyo:BAAALgAECgMJBAAAAA==.',
Ja='Javi:BAAALgADCgkJCQABLgAECgkJJwAVAJ8jAA==.',
Je='Jedus:BAAALgAECgEJAQABLgAECgYJHgAJAOMhAA==.',
Ji='Jizzmon:BAAALgAECgEJAQAAAA==.',
Ka='Kaidirra:BAAALgADCgYJBgAAAA==.Kassiandra:BAABLgAECn8fAAMFAAcJrBfUPACPAQAFAAcJrBfUPACPAQAZAAYJ5gcbWQAXAQAAAA==.Katja:BAAALgAECgYJBwABLgAECggJGgASAH4eAA==.',
Ke='Keeyla:BAAALgADCgUJBgAAAA==.Kejiabaobei:BAABLgAECn8qAAIUAAkJkiW4AQA8AwAUAAkJkiW4AQA8AwAAAA==.Kesta:BAAALgAECgQJBAAAAA==.Kevsterr:BAAALgAECgUJBQAAAA==.',
Kh='Khaantu:BAAALgADCgEJAQAAAA==.',
Ki='Kirin:BAAALgADCgYJCQAAAA==.',
Ko='Koi:BAAALgAECgIJAgABLgADCgEJAQAXAAAAAA==.Korah:BAAALgADCgcJCwAAAA==.',
Kp='Kpöp:BAABLgAECn8eAAMSAAgJoyKIJQBxAgASAAgJoyKIJQBxAgAaAAIJ2wrjaABBAAAAAA==.',
Kr='Krakens:BAEALgAECgUJBwABLgAECggJGgADAFcUAA==.Krayel:BAAALgAECgIJAgAAAA==.Krîtz:BAAALgADCgcJBAAAAA==.Krünk:BAABLgAECn8yAAIMAAkJIyAHAQBNAwAMAAkJIyAHAQBNAwAAAA==.',
Kt='Kt:BAAALgAFFAEJAQABLgADCgUJBQAXAAAAAA==.',
Ku='Kumquat:BAAALgADCgEJAQAAAA==.Kuubai:BAAALgADCggJCAAAAA==.',
La='Lachdanan:BAABLgAECn8YAAIbAAgJUguTEgAYAQAbAAgJUguTEgAYAQAAAA==.Lament:BAABLgAECn8hAAISAAgJSyJwBwCwAgASAAgJSyJwBwCwAgAAAA==.Lans:BAAALgADCgEJAQAAAA==.',
Le='Leafbeard:BAAALgAECgYJBgAAAA==.',
Li='Lilean:BAABLgAECn8UAAIUAAgJwh4nEwCeAgAUAAgJwh4nEwCeAgAAAA==.',
Lo='Lokka:BAABLgAECn8fAAMKAAgJTBmiBQDzAQAKAAgJSxmiBQDzAQAIAAYJgRUUPAAVAQAAAA==.Lolly:BAAALgAECgQJBAAAAA==.Loralin:BAAALgADCgcJCAAAAA==.',
Ly='Lyreshade:BAABLgAECn8nAAIHAAkJDxI3JQDnAQAHAAkJDxI3JQDnAQAAAA==.Lyreshaded:BAAALgAECgcJBwABLgAECgkJJwAHAA8SAA==.',
Ma='Maatdemon:BAAALgADCgcJCgABLgAECgkJLwACAIgjAA==.Madbunny:BAAALgADCgUJBwAAAA==.Madriina:BAAALgADCgYJBgAAAA==.Mahrah:BAABLgAECn8fAAIPAAgJoRMsCQCRAQAPAAgJoRMsCQCRAQAAAA==.Manashifter:BAAALgAECgYJDgAAAA==.Mar:BAAALgADCgcJBwAAAA==.Marija:BAAALgAECgQJBAABLgAECggJGgASAH4eAA==.',
Me='Melevolence:BAABLgAECn8zAAMWAAkJvxy1CQCtAgAWAAkJvxy1CQCtAgAcAAMJ9wZhQQCvAAAAAA==.Mep:BAAALgAECgEJAQABLgAECgUJBwAXAAAAAA==.Meplastered:BAAALgAECgYJEgAAAA==.',
Mi='Mirithari:BAAALgADCgkJCQAAAA==.',
Mo='Molby:BAAALgAFFAEJAQAAAA==.Monkehh:BAAALgAECgIJAgABLgAECgQJBQAXAAAAAA==.Moolinda:BAABLgAECn8eAAIIAAgJNhehGQDlAQAIAAgJNhehGQDlAQAAAA==.Morticia:BAABLgAECn8UAAMdAAgJixxDCwDCAQAdAAgJixxDCwDCAQAQAAIJjASQCQFiAAAAAA==.Motgul:BAAALgAECgUJBwAAAA==.',
My='Mythbras:BAAALgAECgUJBwAAAA==.Mythfurry:BAAALgAECgMJAwABLgAFFAUJFAAeAEwKAA==.',
Na='Naxria:BAAALgAECgQJBwAAAA==.',
Ne='Nezanu:BAAALgAECgcJDgAAAA==.',
Ni='Nic:BAAALgADCgUJBQAAAA==.Niiko:BAAALgADCgEJAQAAAA==.Nimithriel:BAABLgAECn8kAAITAAgJlRWNFACeAQATAAgJlRWNFACeAQAAAA==.',
No='Notwesa:BAAALgADCgkJCQAAAA==.Notweso:BAABLgAECn8sAAISAAgJ2SMbCQCTAgASAAgJ2SMbCQCTAgAAAA==.',
Oc='Oconostota:BAAALgAECgEJAQAAAA==.',
Ol='Oliverclutch:BAAALgADCgIJAgAAAA==.',
Pa='Pallywack:BAAALgADCgcJBwAAAA==.Parizade:BAAALgAECgMJAwAAAA==.Pat:BAAALgAECgMJAwAAAA==.',
Pe='Pergi:BAAALgADCgkJDwABLgAECggJGQAUANYfAA==.',
Pi='Pithikos:BAAALgAECgUJCQABLgAECgkJKQAEAIskAA==.',
Po='Poovey:BAACLgAFFH8HAAIEAAMJsxVnGADuAAAEAAMJsxVnGADuAAAuAAQKfx8AAgQACQmXF3IfAFUCAAQACQmXF3IfAFUCAAAA.',
Pu='Purpletoe:BAAALgAECgYJDgAAAA==.',
Py='Pyronae:BAABLgAECn8fAAIWAAcJwBSnMgCZAQAWAAcJwBSnMgCZAQAAAA==.',
Qi='Qit:BAAALgAECgEJAQAAAA==.',
Ra='Radrek:BAAALgADCgIJAgAAAA==.Rargh:BAABLgAECn8ZAAIUAAgJJhBwKwCiAQAUAAgJJhBwKwCiAQAAAA==.',
Re='Redonkeylous:BAAALgAECgMJAwAAAA==.Rengen:BAAALgAECgcJBwAAAA==.Reya:BAABLgAECn8eAAMQAAgJPh20GwAjAgAQAAgJGxy0GwAjAgAdAAYJPhgcEQBgAQAAAA==.',
Ri='Rixadin:BAAALgADCgEJAQAAAA==.',
Ru='Runelord:BAAALgAECgQJBgAAAA==.',
Sa='Saeli:BAABLgAECn8qAAIYAAkJthUjDQD5AQAYAAkJthUjDQD5AQAAAA==.Sakagawea:BAAALgADCgMJAwAAAA==.Sanamongolos:BAAALgAECgIJAgAAAA==.Sasinko:BAABLgAECn8fAAIfAAcJLxtdAwDLAQAfAAcJLxtdAwDLAQAAAA==.Sasqüatch:BAAALgADCgQJBAAAAA==.Satjin:BAAALgAECgYJEgAAAA==.Sawlrenuk:BAAALgADCgEJAQAAAA==.',
Sc='Scamander:BAAALgAECgcJEAAAAA==.',
Se='Sentien:BAAALgAECgcJAQAAAA==.',
Sh='Shadowstripe:BAABLgAECn8YAAQCAAgJzg+6GABfAQACAAcJOxG6GABfAQAgAAMJ8QPvZQA6AAAhAAEJGAaHjAAsAAAAAA==.Shambamtymam:BAAALgADCgMJAwAAAA==.Shaylathia:BAAALgAECgEJAQAAAA==.Shigglez:BAACLgAFFH8GAAIRAAMJrRC+RwD6AAARAAMJrRC+RwD6AAAuAAQKfzAAAhEACAk+IvoLAMACABEACAk+IvoLAMACAAAA.Shiitake:BAAALgAECgMJAwAAAA==.',
So='Sonatina:BAACLgAFFH8XAAMGAAgJNR68AADKAgAGAAgJNR68AADKAgADAAEJvRRyHABQAAAuAAQKfx8AAwYACAmxJc4BAE4DAAYACAmxJc4BAE4DABMAAwkuHW00ALwAAAAA.Soulfly:BAABLgAECn8xAAMCAAgJ4RlqDQDiAQACAAgJ4RlqDQDiAQAhAAMJgge7eQBcAAAAAA==.',
St='Steamedhams:BAAALgAECgYJBgAAAA==.Streat:BAAALgADCgMJAwAAAA==.Streatlight:BAAALgADCgcJDQAAAA==.',
Su='Sugarpants:BAABLgAECn8sAAIgAAYJLhasHABkAQAgAAYJLhasHABkAQAAAA==.Sulfuric:BAAALgADCggJFQAAAA==.Sumtongue:BAAALgAECgUJCAAAAA==.',
Sy='Sylphrenä:BAABLgAECn8ZAAIgAAcJQB2MGQDvAQAgAAcJQB2MGQDvAQAAAA==.',
Te='Tembtree:BAAALgAECgYJEwABLgAECggJJAAcAPYQAA==.Temlock:BAABLgAECn8kAAMcAAgJ9hBDBgCOAQAcAAgJ9hBDBgCOAQAWAAMJ8AEQ+wBkAAAAAA==.',
Th='Thrawnn:BAABLgAECn8pAAIEAAkJiyTWAABCAwAEAAkJiyTWAABCAwAAAA==.',
Tr='Tryamarula:BAAALgADCgEJAQAAAA==.Trysomecider:BAAALgADCgIJAwAAAA==.',
Tu='Tuonetar:BAAALgAECgMJAwAAAA==.',
Ty='Tyrenari:BAAALgAECgQJCAAAAA==.',
Ul='Ultear:BAABLgAECn8YAAQVAAYJHRjfCgAgAQASAAYJDg/KZQBwAQAVAAYJqBffCgAgAQAaAAIJ/xBrXABuAAAAAA==.',
Ve='Velkyn:BAABLgAECn8pAAIiAAgJYhQgDgDAAQAiAAgJYhQgDgDAAQAAAA==.Vetenarae:BAAALgADCgMJAwABLgAECgYJHgAKACkUAA==.',
Vo='Volkren:BAABLgAECn8xAAIdAAgJ+h/QBQBGAgAdAAgJ+h/QBQBGAgAAAA==.',
Wa='Warhunter:BAAALgAECgQJBAAAAA==.',
Xa='Xandor:BAAALgADCgYJBgABLgAECgYJCgAXAAAAAA==.Xaos:BAAALgAECgYJCwAAAA==.',
Xi='Xiaowugui:BAAALgADCgUJBQAAAA==.',
Xz='Xzaroth:BAAALgADCgcJBwAAAA==.',
Ya='Yarrick:BAABLgAECn8zAAIIAAkJGR1LBgDQAgAIAAkJGR1LBgDQAgAAAA==.',
Yo='Yonst:BAABLgAFFH8GAAIDAAMJxwxdEQDGAAADAAMJxwxdEQDGAAAAAA==.',
Yu='Yumemi:BAAALgADCgcJAgAAAA==.',
Ze='Zelkiri:BAAALgAECgYJDQAAAA==.Zeref:BAAALgAECgQJBAABLgAECgkJLwACAIgjAA==.Zethlahr:BAABLgAECn8tAAMTAAkJ1xxtBACjAgATAAkJ1xxtBACjAgADAAQJpA2nUgDtAAAAAA==.',
Zo='Zoros:BAAALgAECgIJBAAAAA==.',
Zy='Zytheri:BAAALgADCgEJAQAAAA==.',
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

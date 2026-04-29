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

local lookup = {'Priest-Discipline','Priest-Holy','Monk-Brewmaster','Druid-Restoration','DeathKnight-Unholy','DemonHunter-Havoc','Mage-Frost','Unknown-Unknown','Hunter-Marksmanship','Warlock-Destruction','Warlock-Demonology','Druid-Balance','Rogue-Subtlety','Rogue-Assassination','Warrior-Protection','Priest-Shadow','DemonHunter-Devourer','Shaman-Restoration','Evoker-Augmentation','Evoker-Preservation','Evoker-Devastation','Monk-Mistweaver','Paladin-Retribution','Warlock-Affliction','Shaman-Elemental','Shaman-Enhancement','Hunter-BeastMastery','Druid-Guardian','Warrior-Fury','Paladin-Holy','Druid-Feral','Rogue-Outlaw','Monk-Windwalker','DeathKnight-Blood','DeathKnight-Frost','Paladin-Protection',}
local provider = {region='US',realm='Dreadmaul',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Abbathdoom:BAAALgAECgYJBwAAAA==.',
Ae='Aedaris:BAABLgAECn9AAAMBAAgJrxqUIgB/AQABAAYJ+BOUIgB/AQACAAMJmiFzEADnAAAAAA==.Ael:BAAALgAECgEJAQAAAA==.Aethalides:BAAALgAECgUJDgAAAA==.',
Al='Altaria:BAABLgAFFH8FAAIDAAMJURLSEwDaAAADAAMJURLSEwDaAAAAAA==.Alvv:BAAALgADCgMJBQAAAA==.Alvz:BAAALgADCgMJAwAAAA==.',
An='Anouke:BAAALgADCgIJAgAAAA==.Anserion:BAAALgADCgMJAwAAAA==.Anvious:BAAALgAECgcJDAAAAA==.',
Aq='Aquilea:BAAALgAECgYJDwAAAA==.',
Ar='Arcfuldodger:BAAALgADCgQJBAAAAA==.Artais:BAABLgAECn8gAAIEAAgJ1RyBFgCCAgAEAAgJ1RyBFgCCAgAAAA==.Artzlayer:BAABLgAECn8hAAIFAAkJOyB5BgAdAgAFAAkJOyB5BgAdAgAAAA==.Aríes:BAABLgAECn9AAAIGAAgJ7xkqAgADAgAGAAgJ7xkqAgADAgAAAA==.',
As='Ashbourne:BAAALgADCgQJBAAAAA==.',
Aw='Aw:BAAALgAECgYJEQABLgAFFAUJBQAHAJ4FAA==.Awry:BAABLgAECn8VAAIFAAgJqBRlSAAaAgAFAAgJqBRlSAAaAgAAAA==.Awuuga:BAAALgAECgEJAQABLgAECgYJCwAIAAAAAA==.Aww:BAACLgAFFH8FAAIHAAUJngVRDAAyAQAHAAUJngVRDAAyAQAuAAQKfxwAAgcACAkkFw5/ANMBAAcACAkkFw5/ANMBAAAA.',
Az='Azamalaza:BAABLgAECn8XAAIJAAcJHCAVAgDBAQAJAAcJHCAVAgDBAQAAAA==.Azmo:BAABLgAECn8lAAMKAAgJMCHDAgDWAgAKAAgJiR3DAgDWAgALAAUJPhyzYACnAQAAAA==.Azulon:BAAALgADCgUJBQAAAA==.Azyrt:BAAALgAECgQJBAABLgAECggJIAAEANUcAA==.',
Be='Beefrod:BAAALgADCgEJAQAAAA==.Beenis:BAAALgADCgUJBQAAAA==.Belerick:BAABLgAFFH8JAAIMAAMJnQqMDwDoAAAMAAMJnQqMDwDoAAAAAA==.Belphine:BAAALgAECgYJCAAAAA==.',
Bi='Bicksmage:BAAALgAFFAEJAQAAAA==.Bigdaddylock:BAACLgAFFH8GAAILAAQJJxlwBABtAQALAAQJJxlwBABtAQAuAAQKfyMAAwsACQnKJMMFABkCAAoABgm1IkoIAD4CAAsACAkUI8MFABkCAAAA.Biluman:BAAALgAECgQJBAAAAA==.Biodeath:BAAALgADCgUJBQAAAA==.Biopally:BAAALgADCgYJDQAAAA==.Biorogue:BAAALgADCgYJDAAAAA==.Bishope:BAAALgAECgYJEgAAAA==.',
Bl='Bluecar:BAAALgADCgcJBwAAAA==.',
Bo='Bohica:BAAALgAECgEJAgAAAA==.Bombdiggity:BAAALgAECgYJEAAAAA==.Bonnierot:BAAALgAECgUJCgAAAA==.',
Br='Brecciana:BAAALgADCgUJBQAAAA==.Brewjitsu:BAABLgAECn8kAAIDAAYJhxNNOABpAQADAAYJhxNNOABpAQAAAA==.Brick:BAABLgAECn8ZAAIDAAcJOBrfGgAtAgADAAcJOBrfGgAtAgABLgAFFAQJDAALANkdAA==.Brongakill:BAAALgADCgYJBgAAAA==.',
Bu='Bumble:BAAALgADCgYJBgABLgAFFAUJEwACALMfAA==.Bundalock:BAAALgADCgYJEQAAAA==.',
Ca='Cakebringer:BAAALgAECgcJEQAAAA==.Caroshi:BAAALgAECgYJEAAAAA==.',
Ce='Cell:BAAALgAECgUJCAABLgAECgYJBgAIAAAAAA==.Ceridwen:BAAALgADCgEJAQAAAA==.',
Ci='Cig:BAAALgAECgUJCgAAAA==.',
Cl='Clankychan:BAAALgAFFAIJAgAAAA==.Cloneofhunt:BAAALgAFFAQJAgAAAA==.Cloneofmagic:BAAALgADCgcJBwABLgAFFAQJAgAIAAAAAA==.',
Co='Combustanut:BAAALgAECgEJAwAAAA==.Comillmouth:BAABLgAECn8ZAAIBAAgJahG+BADNAQABAAgJahG+BADNAQAAAA==.Cos:BAABLgAECn8cAAMNAAgJfAqJBQCeAQANAAgJfAqJBQCeAQAOAAMJOAXBFgCKAAAAAA==.',
Cr='Cryptum:BAAALgAECggJBAAAAA==.Cryten:BAAALgAECgIJAgAAAA==.',
['Cä']='Cäin:BAAALgAECgQJCAAAAA==.',
Da='Daerus:BAAALgAECgYJBQAAAA==.Damge:BAAALgAECgQJCAAAAA==.Danky:BAAALgAECgIJAgAAAA==.Darahug:BAAALgADCgYJBgAAAA==.Daraina:BAAALgADCgEJAQABLgADCgEJAQAIAAAAAA==.Darrkton:BAAALgADCgEJAQAAAA==.Dathil:BAAALgAECgYJCAAAAA==.Davmonhunter:BAAALgADCgQJBAAAAA==.',
De='Deadiemurphy:BAAALgADCgYJCQAAAA==.Deathshunter:BAAALgAECgYJEQABLgAFFAEJAgAIAAAAAA==.Deaththorn:BAAALgADCgEJAQAAAA==.Debsi:BAABLgAECn8XAAIPAAcJgQqUBwAbAQAPAAcJgQqUBwAbAQAAAA==.Deepest:BAAALgAECgIJAgAAAA==.Deloraine:BAACLgAFFH8QAAIQAAUJUhqxAgDMAQAQAAUJUhqxAgDMAQAuAAQKfxUAAhAABwk5ImcSAGUCABAABwk5ImcSAGUCAAAA.Demonicfaith:BAABLgAECn80AAMGAAcJbxp8FwAMAgAGAAYJTx58FwAMAgARAAcJwAvOgAAoAQAAAA==.Denman:BAAALgAECgcJEAAAAA==.',
Di='Dirtyfux:BAAALgAECgYJEQAAAA==.Dirtysham:BAABLgAECn8eAAISAAgJ8R4ADQC1AgASAAgJ8R4ADQC1AgAAAA==.Discipline:BAAALgADCgcJBwAAAA==.Disckin:BAAALgADCgEJAQAAAA==.',
Dn='Dnb:BAAALgADCgEJAQABLgAFFAUJBQAHAJ4FAA==.Dnk:BAAALgADCgMJAwAAAA==.',
Do='Dom:BAAALgADCgcJCQAAAA==.Donki:BAAALgAECgQJBAAAAA==.Doomvedas:BAAALgAECgYJCgAAAA==.',
Dr='Dracaena:BAABLgAECn8YAAQTAAgJkBT2GwDoAQATAAgJkBT2GwDoAQAUAAUJQwixMQDiAAAVAAIJHA1+QQAtAAAAAA==.Draco:BAAALgAECgEJAQAAAA==.Drekavach:BAAALgADCgcJEwAAAA==.',
['Dâ']='Dâftmonk:BAAALgAECgEJAQABLgAECgIJAgAIAAAAAA==.',
Ee='Eevo:BAAALgADCgUJBQABLgAECggJEwAIAAAAAA==.',
El='Elaha:BAAALgAECgEJAgAAAA==.Elexann:BAAALgADCgEJAQAAAA==.Elibaba:BAAALgAECggJDAAAAA==.Elindyl:BAAALgADCgEJAQAAAA==.Elleth:BAAALgADCgIJAgAAAA==.Elvishcheese:BAAALgAECgMJBgAAAA==.',
Em='Emojis:BAAALgADCggJFgAAAA==.',
En='Endlessdh:BAABLgAECn8YAAIGAAcJGySSCQDIAgAGAAcJGySSCQDIAgAAAA==.',
Er='Eraserhead:BAAALgAECgYJEQABLgAFFAEJAQAIAAAAAA==.',
Es='Estreuth:BAAALgADCgIJAgAAAA==.',
Ev='Evening:BAAALgAECgMJBAAAAA==.Everbuddha:BAAALgAECgQJBgAAAA==.',
Ew='Ewa:BAAALgAECgMJBAAAAA==.Eww:BAAALgAECgEJAQAAAA==.',
Ez='Ezelia:BAAALgAECgcJEgABLgAFFAYJHAACAEkYAA==.',
Fa='Faelune:BAAALgAECgYJDwAAAA==.Faldir:BAAALgADCgYJBAABLgAECgcJEwAIAAAAAA==.',
Fe='Ferndru:BAAALgAECgMJAwAAAA==.',
Fi='Fish:BAAALgAECgEJAgABLgAECggJGAATADQhAA==.Fisticuffs:BAACLgAFFH8GAAIWAAMJTwvcDADYAAAWAAMJTwvcDADYAAAuAAQKfxoAAhYABwmGE7gkAI8BABYABwmGE7gkAI8BAAAA.',
Fl='Flameshock:BAAALgAECgQJBAAAAA==.Flowki:BAAALgADCgYJBQAAAA==.',
Fo='Forcespark:BAAALgAECgEJAQAAAA==.',
Fr='Frostradamus:BAAALgADCgkJCgAAAA==.',
Fu='Fullmoonride:BAAALgAECgEJAQAAAA==.Fumbll:BAAALgAECgkJCQAAAA==.Funkymajik:BAAALgAECgYJDwAAAA==.Furiosa:BAAALgADCgkJDgAAAA==.',
Ga='Gallywox:BAAALgADCgMJAwAAAA==.Ganin:BAAALgAECgYJEAAAAA==.Gankinyou:BAAALgADCgEJAQAAAA==.Garielyn:BAAALgADCgEJAQAAAA==.Garugala:BAABLgAECn8bAAIXAAgJChcUDADSAQAXAAgJChcUDADSAQAAAA==.',
Gd='Gdaycøb:BAAALgADCgYJBwAAAA==.',
Ge='Gengár:BAAALgAECgMJBgABLgAECgcJBgAIAAAAAA==.',
Gh='Ghalorin:BAAALgAECgMJBQAAAA==.Ghiroza:BAABLgAECn9AAAQKAAgJORzbCAAzAgAKAAgJjBbbCAAzAgALAAcJOR1WCQDcAQAYAAIJcBdpHQCGAAAAAA==.',
Gi='Gigaevoker:BAABLgAECn8cAAIUAAgJjxEbAgAHAgAUAAgJjxEbAgAHAgAAAA==.Gigapaladin:BAAALgADCgQJBAAAAA==.Gingarthas:BAABLgAECn8bAAIFAAgJoB30BAA/AgAFAAgJoB30BAA/AgAAAA==.',
Gl='Glowingtoe:BAAALgAECgIJAgAAAA==.',
Go='Gogmazios:BAAALgADCgcJBwAAAA==.',
Gr='Gravytate:BAABLgAECn8+AAIZAAgJUQwaMwCNAQAZAAgJUQwaMwCNAQAAAA==.Griinn:BAAALgAECgcJEQAAAA==.Grimescene:BAAALgAECgIJAgAAAA==.',
Gu='Guldannyboy:BAABLgAECn8VAAIKAAgJRQdIHgBeAQAKAAgJRQdIHgBeAQAAAA==.',
Ha='Hammer:BAAALgAECgIJAgAAAA==.Hantore:BAAALgADCgMJAwAAAA==.Harry:BAABLgAECn8gAAMaAAgJIyPlAQA/AwAaAAgJIyPlAQA/AwASAAcJxBrrIAAaAgAAAA==.',
He='Heartdh:BAAALgAECgUJCgAAAA==.Hellza:BAAALgAECgMJAwAAAA==.Herpyprotect:BAAALgAECgQJBgAAAA==.Herrion:BAACLgAFFH8MAAILAAQJ2R2CBQBfAQALAAQJ2R2CBQBfAQAuAAQKfycAAwsACAluJPwcAKgCAAsABwluJPwcAKgCAAoABAmcJNUUAKQBAAAA.',
Hh='Hh:BAAALgAECgEJAQAAAA==.',
Ho='Hotspur:BAABLgAECn8wAAIEAAgJPRDNOADDAQAEAAgJPRDNOADDAQAAAA==.',
Hu='Huskar:BAAALgAECgYJBgAAAA==.',
Hy='Hypoxi:BAAALgADCgYJCQAAAA==.',
Ig='Ignis:BAAALgAECgYJEgAAAA==.Ignitor:BAAALgADCgEJAQAAAA==.',
Ik='Ikari:BAABLgAECn9AAAIKAAgJQhrzAADeAQAKAAgJQhrzAADeAQAAAA==.',
Il='Illadoss:BAAALgADCgIJAgAAAA==.',
Im='Imntprepared:BAAALgAECgYJCQAAAA==.',
In='Infectîon:BAAALgADCgYJBgAAAA==.Inferlock:BAAALgADCgMJAwAAAA==.',
Ir='Irithel:BAAALgAECgcJBQAAAA==.',
Iv='Ivygambina:BAAALgADCgYJBgAAAA==.',
Ja='Jasha:BAAALgADCgYJBQAAAA==.Jayy:BAABLgAECn8bAAIFAAkJBRCKTAAOAgAFAAkJBRCKTAAOAgAAAA==.',
Je='Jennatalia:BAAALgAECgcJBgAAAA==.',
Jo='Joelsdruid:BAAALgAECggJCAAAAA==.Jongwang:BAAALgAECgQJBwAAAA==.',
Ju='Jubjub:BAAALgAECgEJAgAAAA==.',
Ka='Kaaru:BAAALgAECgYJEwAAAA==.Kairon:BAABLgAECn8fAAIXAAgJjRRIDgC3AQAXAAgJjRRIDgC3AQAAAA==.Kalysae:BAAALgADCgEJAQAAAA==.Kazakhthundr:BAAALgADCgYJBgAAAA==.',
Ke='Keeanuleaves:BAAALgADCgYJBwAAAA==.Keeanuweaves:BAAALgADCgEJAQAAAA==.Keeze:BAAALgAECgcJDgAAAA==.',
Ki='Kickstarter:BAAALgAECgYJCwAAAA==.Kiel:BAAALgAECgEJAQAAAA==.Killania:BAAALgADCgMJAwAAAA==.Kiwichaos:BAACLgAFFH8HAAIGAAMJeAllAgDZAAAGAAMJeAllAgDZAAAuAAQKfxwAAgYACAmtGqIMAJcCAAYACAmtGqIMAJcCAAAA.',
Kl='Klckyourass:BAAALgADCgUJBQAAAA==.',
Ko='Korner:BAAALgAECgIJAgAAAA==.',
Kr='Krazzul:BAAALgADCgYJBgAAAA==.Krellis:BAAALgAECgcJEwAAAA==.Kritikall:BAAALgADCgUJBQAAAA==.',
Ku='Kurö:BAAALgAECgEJAQAAAA==.',
Kv='Kvôthe:BAAALgAECgUJDQAAAA==.',
Ky='Kynnareth:BAAALgAECgIJBAABLgAFFAUJCAABAN4IAA==.Kynralol:BAABLgAECn8TAAIHAAYJrh+UXgAfAgAHAAYJrh+UXgAfAgAAAA==.',
['Ká']='Káiser:BAAALgAECgYJDQAAAA==.',
La='Laenosh:BAAALgAECgIJBQAAAA==.Laomoo:BAAALgAECgcJDAAAAA==.',
Le='Learning:BAABLgAECn8UAAIZAAYJaSBGGwA4AgAZAAYJaSBGGwA4AgAAAA==.Legham:BAAALgADCgkJDgAAAA==.Legolazz:BAABLgAECn8aAAMbAAgJ0xt/AwBVAgAbAAgJ0xt/AwBVAgAJAAEJyAj7jQAtAAAAAA==.Lemins:BAAALgAECgMJAwAAAA==.Lemondruid:BAAALgAECgIJAgAAAA==.Lemonmelon:BAAALgAECgYJEwAAAA==.Lenatheplug:BAACLgAFFH8KAAMNAAUJhhwJAwDMAQANAAUJhhwJAwDMAQAOAAEJQRHFBQBgAAAuAAQKfyIAAw0ACAmUJD4KAO4CAA0ACAnbIz4KAO4CAA4ABwk/ItsDAIACAAAA.Lerust:BAAALgADCgcJBwAAAA==.',
Li='Liadrine:BAABLgAECn8cAAIXAAgJ7hXpQgAcAgAXAAgJ7hXpQgAcAgAAAA==.Littleriver:BAAALgAECgcJEQAAAA==.',
Ll='Llewser:BAAALgAECgUJDQAAAA==.',
Lo='Loistiah:BAAALgAECgQJCgAAAA==.Lothaof:BAABLgAECn8eAAIXAAkJQww/FwBnAQAXAAkJQww/FwBnAQAAAA==.Louisvuitton:BAAALgAECgUJCgAAAA==.',
Lp='Lpayn:BAAALgADCgEJAQAAAA==.',
Lu='Lugroth:BAAALgAECgEJAQABLgAFFAQJDAALANkdAA==.Lunana:BAAALgAECgYJCgAAAA==.',
Ly='Lychiee:BAAALgAECgYJDAAAAA==.',
Ma='Magesorry:BAAALgADCgUJBQAAAA==.Maize:BAABLgAECn8dAAMBAAcJox6CAgA5AgABAAcJox6CAgA5AgACAAMJhgvBZwCOAAAAAA==.Makima:BAAALgAECgMJAwABLgAFFAQJCgAMAIoVAA==.Malikai:BAAALgADCgcJDAAAAA==.Marcyon:BAAALgAECgYJDgAAAA==.',
Mc='Mchèalz:BAAALgAECgYJEgAAAA==.',
Me='Melonlemonza:BAAALgADCgQJBAAAAA==.Mentok:BAAALgAECgYJCwAAAA==.Merchei:BAAALgAECgEJAQAAAA==.Meruen:BAAALgAECgUJBwAAAA==.',
Mi='Mitymorphin:BAAALgADCgEJAQAAAA==.',
Mo='Mobility:BAAALgADCgYJBgAAAA==.Moistpole:BAAALgADCgQJBAAAAA==.Momock:BAAALgAECgQJBAAAAA==.Mongk:BAAALgAECggJEwAAAA==.Monscustodes:BAAALgAECgUJEgAAAA==.Mookin:BAAALgAECgcJCAAAAA==.Moospoon:BAAALgAECgQJBgAAAA==.Moounka:BAABLgAECn8VAAIDAAYJYgmTTAAQAQADAAYJYgmTTAAQAQAAAA==.Morphio:BAABLgAECn8iAAMbAAgJkCCnAQCoAgAbAAgJkCCnAQCoAgAJAAUJCxN4TAAfAQAAAA==.Mostakrakish:BAAALgADCgEJAQAAAA==.',
Mu='Muddles:BAABLgAECn8gAAIDAAYJixXDMwCBAQADAAYJixXDMwCBAQAAAA==.Murius:BAABLgAECn8cAAIFAAgJbRVvRgAhAgAFAAgJbRVvRgAhAgAAAA==.',
My='Mysterio:BAAALgAECgEJAQAAAA==.',
Na='Naendria:BAAALgAECgMJBAAAAA==.Nahaza:BAAALgAECgEJAQAAAA==.',
Ne='Nelena:BAAALgADCgEJAQAAAA==.',
Ni='Nickdoom:BAAALgAECgQJBwAAAA==.Nigella:BAAALgAECgYJBgAAAA==.Nikola:BAABLgAECn8dAAQEAAgJCxVfNwDKAQAEAAgJCxVfNwDKAQAcAAUJNxbkFQAUAQAMAAQJxw5uVADUAAAAAA==.Nimro:BAACLgAFFH8LAAIPAAQJNxZ8BAA1AQAPAAQJNxZ8BAA1AQAuAAQKfyYAAg8ACQmkHpkDABsDAA8ACQmkHpkDABsDAAAA.Niub:BAABLgAECn8WAAIdAAcJFAqKVwBOAQAdAAcJFAqKVwBOAQAAAA==.',
No='Nofate:BAAALgADCgEJAQAAAA==.Noirebringer:BAAALgAECgYJBgAAAA==.',
Nt='Ntrldrake:BAAALgADCgEJAQABLgAECgUJEgAIAAAAAA==.',
Nu='Nuferax:BAAALgAECgYJDwAAAA==.Numbrethree:BAACLgAFFH8GAAIWAAIJmg15GAA9AAAWAAIJmg15GAA9AAAuAAQKfy8AAhYACAlKF3oWABACABYACAlKF3oWABACAAAA.',
Ob='Obbi:BAAALgAECgMJAwABLgAECgcJDQAIAAAAAA==.',
Oh='Ohaither:BAAALgAECgQJBAAAAA==.',
Oi='Oirth:BAAALgADCgIJAgAAAA==.',
Or='Orinocco:BAAALgAECgEJAQAAAA==.Orobas:BAAALgADCgYJBwAAAA==.',
Pa='Palimathrus:BAAALgAECgUJCAAAAA==.Palliative:BAABLgAECn8VAAIeAAYJHSTnEwBzAgAeAAYJHSTnEwBzAgAAAA==.Pallidnim:BAAALgAECggJCwAAAA==.',
Pe='Pea:BAAALgAECgcJDAAAAA==.',
Ph='Phatmonk:BAAALgAFFAIJAgAAAA==.',
Pi='Piewpiew:BAAALgADCgcJCgAAAA==.Pix:BAACLgAFFH8OAAMQAAUJYh3PAgDHAQAQAAUJYh3PAgDHAQABAAQJmQkMBQAlAQAuAAQKfyYAAhAACQmwIUAEAFIDABAACQmwIUAEAFIDAAAA.',
Pl='Pleasuremax:BAAALgAECgMJBwAAAA==.Plex:BAABLgAECn8uAAIfAAcJUxdjAgC2AQAfAAcJUxdjAgC2AQAAAA==.',
Po='Poogie:BAAALgADCgYJBgABLgAECgMJBQAIAAAAAA==.Popshot:BAABLgAECn8eAAIJAAYJ5xL6RABBAQAJAAYJ5xL6RABBAQAAAA==.Portalhouse:BAAALgAECgEJAQAAAA==.',
Pr='Praxis:BAABLgAECn8VAAIPAAgJ5ghwHQBaAQAPAAgJ5ghwHQBaAQAAAA==.Preast:BAAALgADCgMJAwABLgAECggJEwAIAAAAAA==.Procist:BAAALgADCggJCAABLgAECggJIAASAKUeAA==.',
Py='Pyrusdk:BAAALgAECggJEQAAAA==.',
Qo='Qop:BAAALgAECgYJBgAAAA==.',
Qu='Quesarah:BAAALgADCgEJAQABLgAECgQJBAAIAAAAAA==.',
Qw='Qweffor:BAAALgADCgUJBQABLgAECgYJDwAIAAAAAA==.',
Ra='Rainbowkelly:BAAALgAECgQJBAAAAA==.Raìn:BAAALgAECgIJAgAAAA==.',
Re='Reapy:BAAALgAECgYJDgAAAA==.Recruitqt:BAAALgAECgUJDAAAAA==.Reiayanami:BAABLgAECn8WAAIHAAYJ/wzvNADzAAAHAAYJ/wzvNADzAAAAAA==.',
Ri='Ripandtear:BAAALgAECgcJEwAAAA==.',
Ro='Roguewan:BAAALgAECgYJCgAAAA==.Roninn:BAAALgAECgYJBgAAAA==.Ronlock:BAABLgAECn8VAAMLAAYJ1hDjnQAdAQALAAUJ1hDjnQAdAQAKAAEJAADwaQA+AAABLgAECgcJNAAGAG8aAA==.',
Rs='Rsi:BAAALgADCgEJAgAAAA==.',
['Rï']='Rïmuru:BAAALgADCgcJCwAAAA==.',
['Rô']='Rôlayne:BAAALgAECgYJBgAAAA==.',
Sa='Salvare:BAABLgAECn8eAAMOAAkJ5xdwAwCUAgAOAAkJ3RdwAwCUAgAgAAIJWBD5AwCEAAAAAA==.Sappy:BAAALgADCgMJBAAAAA==.Sauron:BAAALgADCgEJAQABLgAECgQJBgAIAAAAAA==.',
Sb='Sbf:BAABLgAFFH8HAAITAAQJpQ7LEgDpAAATAAQJpQ7LEgDpAAABLgAFFAcJJgAHAHIbAA==.',
Sc='Scalamander:BAAALgAECgcJAgAAAA==.Sciohunter:BAAALgADCgEJAQAAAA==.Scioscioz:BAABLgAECn8ZAAMEAAcJnxPZOwC1AQAEAAcJnxPZOwC1AQAMAAIJZBDuawBwAAAAAA==.Scwisgar:BAAALgAECgcJCwAAAA==.',
Se='Sedge:BAAALgAFFAEJAQAAAA==.Sephire:BAAALgAECgYJEAAAAA==.Sermazule:BAAALgADCgcJEQAAAA==.Sewerface:BAAALgAECgYJDwAAAA==.',
Sh='Shadonir:BAAALgAECgQJBAAAAA==.Shadowind:BAABLgAECn8lAAIJAAgJLRmBAQDxAQAJAAgJLRmBAQDxAQAAAA==.Shaft:BAAALgAECgEJAQAAAA==.Shallotte:BAABLgAECn8YAAMYAAgJcRDmCwB7AQAYAAcJABLmCwB7AQALAAcJmwgMGgBEAQAAAA==.Shammalxs:BAAALgAFFAQJBAAAAA==.Shamoc:BAABLgAECn8gAAMSAAgJpR5QAwBOAgASAAgJpR5QAwBOAgAZAAYJoRH/SAAjAQAAAA==.Shampooing:BAAALgAECgYJEAAAAA==.Sharpknife:BAAALgAECgYJCwAAAA==.Shaz:BAAALgADCgQJBAAAAA==.Shorpus:BAABLgAECn8WAAQaAAcJGyAgCgAwAgAaAAYJNx8gCgAwAgASAAcJCwjyXQATAQAZAAUJkxIVEQD+AAAAAA==.',
Si='Sicckbrew:BAABLgAECn8eAAIhAAkJMyEKAgAvAgAhAAkJMyEKAgAvAgAAAA==.',
Sk='Skizzyy:BAAALgAECgIJAgABLgAECgcJEAAIAAAAAA==.',
Sl='Slowpoke:BAABLgAFFH8KAAIMAAQJihW7CABXAQAMAAQJihW7CABXAQAAAA==.',
Sm='Smacedh:BAAALgAECgcJEgAAAA==.',
Sn='Sneakyfella:BAAALgAECggJCgAAAA==.',
So='Solidus:BAAALgAFFAEJAQAAAA==.',
Sp='Spaklehooves:BAAALgADCgYJBgAAAA==.Spiral:BAAALgAECgQJBwAAAA==.Spoonfed:BAAALgAECgQJCwAAAA==.',
Sq='Squiish:BAACLgAFFH8LAAIMAAUJrxjAAgBSAQAMAAUJrxjAAgBSAQAuAAQKfxoAAgwABwmoJesLANkCAAwABwmoJesLANkCAAAA.',
Ss='Ss:BAAALgAECgEJAQAAAA==.',
St='Stickyholes:BAAALgAECgEJAgABLgAECggJPgAQAP4fAA==.Stickypriest:BAABLgAECn8+AAMQAAgJ/h8bAgBEAgAQAAgJ/h8bAgBEAgACAAEJExh/eQBCAAAAAA==.Stipe:BAAALgADCgUJCAAAAA==.Stove:BAAALgADCgcJCwAAAA==.Strawhats:BAACLgAFFH8mAAIHAAcJchvmAADxAQAHAAcJchvmAADxAQAuAAQKfzwAAgcACQkyJWQCANgDAAcACQkyJWQCANgDAAAA.Streamliner:BAABLgAECn8YAAMNAAgJ7RMjGQA8AgANAAgJ7RMjGQA8AgAgAAMJ1gdLCwCNAAAAAA==.Stuunks:BAAALgAECgYJCwAAAA==.',
Su='Sustangelia:BAAALgAECggJEwAAAA==.',
Sw='Swisadecay:BAABLgAECn8YAAIiAAgJISJcBQDrAgAiAAgJISJcBQDrAgAAAA==.Swordkiller:BAAALgAECgcJAQAAAA==.',
Sx='Sxy:BAAALgADCgcJBwAAAA==.',
Sy='Synthesis:BAAALgAECgcJEwAAAA==.',
Ta='Tae:BAAALgADCgUJBQAAAA==.Talas:BAAALgADCgIJAgAAAA==.Talletalanot:BAABLgAECn8pAAIUAAgJWiAjAQBsAgAUAAgJWiAjAQBsAgAAAA==.Tandryan:BAAALgAECgQJBAAAAA==.Tanukiji:BAABLgAECn8aAAICAAgJpxg4AwAiAgACAAgJpxg4AwAiAgAAAA==.',
Td='Tdh:BAAALgADCgMJAwAAAA==.Tdk:BAABLgAECn8UAAIFAAcJMBNkIwAMAQAFAAcJMBNkIwAMAQAAAA==.',
Te='Tee:BAAALgADCgUJBQAAAA==.Tesarion:BAAALgAECgYJDwAAAA==.Testalatesta:BAABLgAECn8aAAIeAAcJqh2eAwBFAgAeAAcJqh2eAwBFAgAAAA==.',
Th='Tharien:BAAALgADCgIJAgAAAA==.Thovir:BAAALgADCgEJAQAAAA==.',
Ti='Tiberian:BAAALgADCgIJAgAAAA==.Tinyvolt:BAAALgADCgEJAQAAAA==.',
To='Toinahun:BAAALgAECgQJBAAAAA==.Totemea:BAAALgADCgcJDAAAAA==.Totems:BAAALgAFFAQJBAAAAA==.Totemîxx:BAABLgAECn8WAAMZAAYJdhdjLgCqAQAZAAYJdhdjLgCqAQASAAMJjg61fgCYAAAAAA==.Touchhy:BAAALgAECgEJAQAAAA==.',
Tr='Trainz:BAAALgADCgcJBwAAAA==.Trass:BAABLgAECn8oAAMLAAgJeB2XBwD4AQALAAgJeB2XBwD4AQAKAAIJlhkURAClAAAAAA==.Trisse:BAAALgAECgQJBAAAAA==.',
Tu='Tuzz:BAABLgAECn8iAAIjAAgJgiBiAQDuAgAjAAgJgiBiAQDuAgAAAA==.',
Ty='Tyden:BAAALgAECgYJDQAAAA==.',
Va='Vael:BAAALgAECgYJCgAAAA==.Valerie:BAAALgAECgMJAwAAAA==.Valkyrra:BAAALgAECgQJBAAAAA==.Varg:BAAALgADCgEJAQABLgADCgEJAQAIAAAAAA==.Vargmk:BAAALgADCgEJAQAAAA==.Vargps:BAAALgADCgEJAQAAAA==.',
Ve='Verdict:BAACLgAFFH8FAAIXAAMJOxJJCgD3AAAXAAMJOxJJCgD3AAAuAAQKfxgAAhcACAloHmMgAKoCABcACAloHmMgAKoCAAAA.Vermillion:BAACLgAFFH8GAAIXAAIJYxSQJACjAAAXAAIJYxSQJACjAAAuAAQKfxcAAhcABwlaHftEABUCABcABwlaHftEABUCAAAA.',
Vi='Viegas:BAABLgAECn8YAAIbAAcJERytIABBAgAbAAcJERytIABBAgAAAA==.Vincent:BAABLgAECn8eAAIHAAYJsB6jfgDUAQAHAAYJsB6jfgDUAQAAAA==.Vinijr:BAAALgAECgEJAgAAAA==.',
Vo='Volthic:BAAALgAECgQJBAAAAA==.Voltormu:BAAALgAECgMJBgAAAA==.Vore:BAAALgAECgcJCwAAAA==.',
Vr='Vrag:BAABLgAECn8UAAIFAAYJLwfAtgAVAQAFAAYJLwfAtgAVAQAAAA==.',
['Vè']='Vè:BAAALgAECgUJBQABLgAECggJDgAIAAAAAA==.',
Wa='Warth:BAAALgADCgEJAQAAAA==.Waterwater:BAAALgAECgYJBgAAAA==.Waterwaterz:BAABLgAECn8uAAIHAAgJ1RzdNACfAgAHAAgJ1RzdNACfAgAAAA==.',
Wc='Wchin:BAAALgAECgcJBwAAAA==.Wchinz:BAAALgAECggJEAAAAA==.',
We='Wedlock:BAAALgADCgIJAgAAAA==.Welcumshot:BAAALgAECgcJEgAAAA==.',
Wi='Windsabre:BAAALgADCgIJAgAAAA==.',
Wo='Woregeonnick:BAABLgAECn8aAAILAAcJmRAVZwCWAQALAAcJmRAVZwCWAQAAAA==.Woshiren:BAAALgAECgUJBQAAAA==.',
Wy='Wyvern:BAAALgAECgIJAgAAAA==.',
['Wä']='Wärrior:BAAALgADCgMJAwAAAA==.',
Xa='Xanadu:BAAALgADCgIJAgAAAA==.',
Xe='Xerxexy:BAAALgAECgQJBwAAAA==.',
Xi='Xiaodingdang:BAAALgAECgQJBAAAAA==.Xiera:BAAALgAECgYJDwAAAA==.',
Ya='Yaminosaishi:BAAALgAECgYJBwAAAA==.Yaoyôrozu:BAAALgADCgcJCwAAAA==.Yasuô:BAAALgADCgMJAwAAAA==.Yatelega:BAAALgADCgIJAgABLgAECgcJGgALAJkQAA==.Yazdorzarn:BAAALgAECgUJBQAAAA==.',
Za='Zaaniz:BAABLgAECn8UAAMXAAgJ1R11HwCvAgAXAAgJ1R11HwCvAgAkAAIJ5A1TDwBhAAAAAA==.',
Ze='Zenestra:BAAALgAECgYJAQAAAA==.Zenshui:BAAALgAECgYJCQAAAA==.Zephyruss:BAAALgADCgEJAQAAAA==.Zervis:BAAALgADCgQJBAAAAA==.Zeyra:BAAALgAECgYJDAAAAA==.',
Zi='Zinako:BAAALgADCgYJBgAAAA==.',
Zo='Zocalo:BAAALgAECgUJBQAAAA==.',
['Èa']='Èasymode:BAAALgADCgEJAQAAAA==.',
['Ód']='Ódyssey:BAAALgADCgMJAwAAAA==.',
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

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

local lookup = {'Evoker-Augmentation','Warrior-Arms','Warrior-Fury','Priest-Holy','Priest-Shadow','DeathKnight-Blood','Unknown-Unknown','Warlock-Demonology','Mage-Frost','Hunter-Marksmanship','Paladin-Retribution','Monk-Brewmaster','Hunter-BeastMastery','Evoker-Preservation','Evoker-Devastation','Warrior-Protection','Paladin-Holy','Warlock-Destruction','DeathKnight-Unholy','Shaman-Elemental','Shaman-Restoration','Monk-Windwalker','DemonHunter-Devourer','Warlock-Affliction','DemonHunter-Vengeance','Priest-Discipline','Druid-Guardian','Druid-Restoration','Hunter-Survival','Shaman-Enhancement','DemonHunter-Havoc','Paladin-Protection','Druid-Feral','DeathKnight-Frost','Druid-Balance','Monk-Mistweaver','Mage-Arcane',}
local provider = {region='US',realm='ShatteredHand',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abchi:BAAALgAECgMJAwAAAA==.Abelladanger:BAAALgADCgYJBgAAAA==.Absorption:BAAALgAECggJDAABLgAECggJIQABAFYXAA==.',
Ac='Ackerw:BAABLgAFFH8JAAMCAAQJkws1BAD3AAACAAQJkws1BAD3AAADAAEJaQQoJABMAAAAAA==.',
Ad='Addilyn:BAABLgAECn8aAAMEAAgJPxQkHQBhAQAEAAgJPxQkHQBhAQAFAAcJcguIHgBIAQAAAA==.',
Ah='Ahminous:BAABLgAECn8aAAIGAAgJ2BO1DQCWAQAGAAgJ2BO1DQCWAQAAAA==.Ahroo:BAAALgAECgcJGQABLgAECgkJDQAHAAAAAQ==.Ahrue:BAAALgAECgkJDQAAAQ==.',
Ai='Airc:BAAALgAECgYJDwAAAA==.Aiurman:BAAALgADCgkJCQAAAA==.',
Al='Alfster:BAABLgAECn8dAAIIAAgJcgfFRwBRAQAIAAgJcgfFRwBRAQAAAA==.Allessiae:BAAALgAECgYJBgAAAA==.Alvar:BAABLgAECn8XAAIIAAgJsRJpLwClAQAIAAgJsRJpLwClAQAAAA==.',
Ar='Arcadium:BAABLgAECn8VAAIJAAUJWCKRbwD1AQAJAAUJWCKRbwD1AQAAAA==.Arêos:BAABLgAECn8ZAAIEAAkJuxyJCQBRAgAEAAkJuxyJCQBRAgAAAA==.',
As='Asunaish:BAAALgAECgcJEwAAAA==.',
At='Atiko:BAAALgADCgQJBAAAAA==.Atomicrednax:BAABLgAFFH8UAAIKAAcJQh71AgAlAgAKAAcJQh71AgAlAgAAAA==.Atropos:BAAALgADCgcJBwAAAA==.',
Ay='Ayisen:BAAALgAECgQJBQAAAA==.',
Az='Azarite:BAABLgAECn8kAAILAAgJ1RJlPgCLAQALAAgJ1RJlPgCLAQAAAA==.',
Ba='Babybilly:BAAALgAECgQJBAAAAA==.Badassbum:BAAALgAECgYJEgAAAA==.Bahoodies:BAAALgAECgYJBQAAAA==.Balgorath:BAAALgAECgQJBwAAAA==.Balthazar:BAAALgADCgUJBgAAAA==.Bananastand:BAAALgADCgMJAwAAAA==.Banree:BAAALgAECgEJAgAAAA==.Bassa:BAAALgADCgYJBgAAAA==.Battman:BAAALgADCgcJDAAAAA==.Battousaiha:BAABLgAECn8cAAILAAgJABoOHgATAgALAAgJABoOHgATAgAAAA==.',
Be='Bera:BAAALgAECgIJAwAAAA==.',
Bi='Bigmustard:BAACLgAFFH8hAAIMAAYJSyAaAwDHAQAMAAYJSyAaAwDHAQAuAAQKfywAAgwACQkvJfUDAE8DAAwACQkvJfUDAE8DAAAA.Bignut:BAAALgAECgYJBQAAAA==.',
Bo='Boojum:BAAALgAECgYJDgAAAA==.Borticuss:BAAALgAECgMJAwABLgAECgcJHQAMABcZAA==.Bortikus:BAAALgAECgQJBwABLgAECgcJHQAMABcZAA==.Boskos:BAAALgADCgQJBAABLgAECgQJBgAHAAAAAA==.Bossnugg:BAAALgADCgYJCAABLgAECgQJBgAHAAAAAA==.',
Br='Brasputin:BAAALgADCgQJBAAAAA==.Breez:BAAALgADCgIJAgAAAA==.',
Bu='Bul:BAAALgADCgcJBwABLgAECggJFAANABAUAA==.Bullshifting:BAAALgAECgcJEwAAAA==.Bumbaloo:BAAALgAECgQJBQAAAA==.Burgi:BAAALgAECgQJBQAAAA==.Burney:BAABLgAECn8gAAMOAAgJFx71AgCxAgAOAAgJFx71AgCxAgAPAAIJcAsGEgBmAAAAAA==.',
['Bò']='Bònesaw:BAABLgAECn8lAAIQAAkJ0SF1AgC+AgAQAAkJ0SF1AgC+AgAAAA==.',
Ca='Calibrium:BAAALgAECgYJDwAAAA==.Cannaboss:BAAALgAECgQJBgAAAA==.Carll:BAACLgAFFH8IAAIRAAMJgA9HGgDSAAARAAMJgA9HGgDSAAAuAAQKfx8AAhEACAlsFLwmAPQBABEACAlsFLwmAPQBAAAA.Catleesei:BAAALgAFFAEJAQAAAA==.',
Ch='Chables:BAAALgADCgcJBwAAAA==.Chai:BAAALgAECgYJCwAAAA==.Chaosmage:BAAALgAECgQJBAAAAA==.Chickyn:BAAALgAECgMJBQAAAA==.Choppa:BAAALgAECgQJCAAAAA==.',
Cl='Clyde:BAAALgAECgIJAgAAAA==.',
Co='Coldxlxsoul:BAABLgAECn8WAAMPAAcJqhQEFAClAQAPAAcJDRIEFAClAQABAAYJWBE6LgBQAQAAAA==.Condrius:BAAALgADCgUJBgAAAA==.Convict:BAAALgAECgMJBQAAAA==.',
Cr='Crappylock:BAAALgAECgQJBAAAAA==.Criotor:BAAALgAECgIJAgAAAA==.Critster:BAAALgAECgQJBgAAAA==.',
Da='Daddy:BAACLgAFFH8LAAIIAAUJgQreHAARAQAIAAUJgQreHAARAQAuAAQKfyAAAwgACAk4GfIoAG0CAAgACAmkGPIoAG0CABIABwlaFJoYAIYBAAAA.Darkportal:BAAALgAECgQJCQABLgAECgcJEwAHAAAAAA==.Datnagablu:BAAALgAECgQJBQAAAA==.',
De='Deathsrain:BAABLgAECn8kAAITAAgJ2x+6NABkAgATAAgJ2x+6NABkAgAAAA==.Decimez:BAABLgAECn8aAAIUAAgJMiDsBgB0AgAUAAgJMiDsBgB0AgAAAA==.Decimock:BAAALgAECgcJCQAAAA==.Dellinsane:BAAALgADCgcJAwAAAA==.Devour:BAAALgAECggJCwAAAA==.',
Di='Dingiswayo:BAAALgAECgcJEgAAAA==.Dipz:BAAALgAECgYJCQAAAA==.',
Do='Donyolerberz:BAAALgAECgYJBQAAAA==.',
Dr='Draeno:BAABLgAECn8UAAINAAgJEBTyNgBxAQANAAgJEBTyNgBxAQAAAA==.Dragonflyy:BAAALgAECgEJAQAAAA==.Dragonips:BAAALgADCgYJBgAAAA==.Drbonedaddy:BAAALgAECgYJBgABLgAECgcJBQAHAAAAAA==.Drinkyds:BAABLgAFFH8HAAIVAAUJ5RZ0BgCuAQAVAAUJ5RZ0BgCuAQAAAA==.',
Du='Duggnut:BAAALgAECgMJAwAAAA==.Durgi:BAABLgAECn8UAAIRAAcJ1xk8JQD8AQARAAcJ1xk8JQD8AQAAAA==.Durtrim:BAAALgADCgIJAgAAAA==.',
Ed='Ederen:BAAALgAECgEJAQAAAA==.',
Ee='Eepic:BAABLgAECn8pAAILAAgJjRHrPQCMAQALAAgJjRHrPQCMAQAAAA==.',
Ei='Eightmile:BAAALgAECgcJBwAAAA==.Eisenhorn:BAAALgADCgcJDAABLgAECgcJFgAPAKoUAA==.',
El='Elementfrost:BAAALgAECgEJAQAAAA==.Ellio:BAAALgADCgcJBwABLgAFFAUJEgANAGAcAA==.',
Em='Embar:BAAALgADCgIJAwAAAA==.Emrys:BAACLgAFFH8FAAIMAAIJQSJwJADGAAAMAAIJQSJwJADGAAAuAAQKfxQAAwwABwkvJDYYAEMCAAwABwkvJDYYAEMCABYABAm8DA5SAMoAAAAA.',
Ep='Epinephrine:BAAALgAECggJDgAAAA==.',
Er='Eriebus:BAABLgAECn8aAAIXAAgJ5gtgQQA1AQAXAAgJ5gtgQQA1AQAAAA==.Erona:BAAALgAECgQJBAAAAA==.',
Es='Escorpiøn:BAACLgAFFH8KAAITAAQJJxtkIgBbAQATAAQJJxtkIgBbAQAuAAQKfyIAAhMACAlmIPwsAIUCABMACAlmIPwsAIUCAAAA.',
Ev='Evenstar:BAAALgAECgEJAQAAAA==.',
Fa='Faling:BAAALgADCgYJEQAAAA==.Falkor:BAAALgAECgcJEAABLgAECgcJEwAHAAAAAA==.Fartcloud:BAAALgAECgQJBAAAAA==.Fatigued:BAAALgAECggJDQAAAA==.',
Fe='Feech:BAAALgAECgUJCwABLgAFFAMJCAAYAFobAA==.Felagain:BAABLgAECn8cAAIZAAgJ6AqsCgAkAQAZAAgJ6AqsCgAkAQAAAA==.Felslizer:BAAALgAECgMJAwAAAA==.',
Fl='Flankshot:BAABLgAECn8cAAIJAAkJFQ3FTwB7AQAJAAkJFQ3FTwB7AQAAAA==.Flo:BAAALgADCgUJBgABLgAECgYJBQAHAAAAAA==.Flõ:BAAALgAECgQJBAAAAA==.',
Fo='Foops:BAACLgAFFH8bAAIJAAcJDBcmBAAvAgAJAAcJDBcmBAAvAgAuAAQKfxcAAgkACAlhHR1GAGUCAAkACAlhHR1GAGUCAAAA.Foopsadin:BAAALgAECgYJDQABLgAFFAcJGwAJAAwXAA==.',
Fu='Fumin:BAAALgAECgQJBwAAAA==.',
Ga='Galibuk:BAAALgADCgYJBgAAAA==.',
Ge='Geezuss:BAAALgAECgEJBAABLgAECgYJGQAaAJUfAA==.Genohbreaker:BAAALgADCgUJBAAAAA==.Getrkt:BAAALgAECgQJBAAAAA==.',
Gh='Ghouliver:BAABLgAECn8mAAITAAgJPhiqKQDWAQATAAgJPhiqKQDWAQAAAA==.',
Gi='Gigasushi:BAAALgAECgQJBAAAAA==.Gimblie:BAABLgAECn8aAAIEAAcJ2hb9FwCQAQAEAAcJ2hb9FwCQAQAAAA==.Gimermonty:BAABLgAECn8jAAINAAkJnxvgDQBrAgANAAkJnxvgDQBrAgAAAA==.Ging:BAAALgADCgcJCAAAAA==.',
Gl='Glorfindel:BAAALgAECgYJBwAAAA==.',
Go='Goblinkicker:BAAALgAECgMJBAAAAA==.Gothegg:BAAALgAECgEJAgAAAA==.Gothmommy:BAABLgAECn8eAAIIAAgJTQooQgBiAQAIAAgJTQooQgBiAQAAAA==.',
Gr='Gronk:BAAALgAECgIJAgAAAA==.',
Gu='Guldanshower:BAABLgAECn8hAAMSAAgJlRpCDgDjAQASAAYJJxxCDgDjAQAIAAcJqBYDJQDWAQAAAA==.',
Ha='Habusaki:BAAALgAECgQJBgAAAA==.Hakal:BAABLgAECn8cAAIbAAgJshUVCgB8AQAbAAgJshUVCgB8AQAAAA==.Halvor:BAAALgAECgQJCAAAAA==.Hangbladz:BAAALgAECgcJEwAAAA==.Hardwarë:BAAALgADCgcJCAAAAA==.Harrygazm:BAAALgADCgQJBAAAAA==.',
Hu='Hukdemon:BAABLgAECn8aAAIZAAgJNSQBAQDMAgAZAAgJNSQBAQDMAgAAAA==.',
Ic='Iceandfire:BAAALgAECgEJAQAAAA==.',
Il='Illiyana:BAAALgAECgUJBQAAAA==.',
In='Inviteme:BAAALgADCgMJAwABLgAECggJIQATACcaAA==.',
Ja='Jakesterwars:BAAALgADCgEJAQAAAA==.Jaldore:BAAALgADCgcJBwAAAA==.',
Je='Jeaine:BAAALgADCgEJAgAAAA==.',
Jh='Jhamin:BAACLgAFFH8HAAIVAAMJfgmHJwC1AAAVAAMJfgmHJwC1AAAuAAQKfx4AAxUACAmjFXMiABACABUACAmjFXMiABACABQABAmNGG8xAO0AAAAA.',
Ji='Jiveturkey:BAAALgAECgQJAwAAAA==.',
Ju='Jubeiskyfang:BAAALgAECgcJBgABLgAFFAQJBQALAEMPAA==.Julkaal:BAAALgAECgEJAQAAAA==.',
Ka='Kaedrelyn:BAAALgADCgkJBAAAAA==.Kai:BAAALgAECgYJBwAAAA==.Karnage:BAAALgAECgUJBgAAAA==.Karney:BAAALgAECgEJAgAAAA==.Kazam:BAAALgAECgYJBgAAAA==.Kazik:BAABLgAECn8ZAAIXAAcJaBuwIQC+AQAXAAcJaBuwIQC+AQAAAA==.',
Ke='Kelrath:BAABLgAECn8lAAIcAAgJvw7GJwCRAQAcAAgJvw7GJwCRAQAAAA==.Kelthugan:BAAALgADCgIJAgAAAA==.Kendeez:BAAALgADCgcJCwAAAA==.Kenparrchi:BAAALgAECgIJAwAAAA==.Kensei:BAAALgADCgIJAgABLgAECgkJFQALAA4UAA==.Ketheric:BAAALgADCgYJCAAAAA==.',
Ki='Kindinos:BAAALgAECgYJDwAAAA==.',
Kl='Kllcky:BAABLgAECn8WAAILAAgJZyL9BgDgAgALAAgJZyL9BgDgAgABLgAFFAMJCAAYAFobAA==.Klorox:BAAALgAECgIJAgAAAA==.',
Kr='Kraoptix:BAAALgADCgYJCAAAAA==.Kratøs:BAAALgADCgMJAwAAAA==.Kraun:BAABLgAECn8fAAMdAAcJnSHUCwATAgAdAAYJVCLUCwATAgANAAMJbR5yWAAGAQAAAA==.Kreig:BAAALgADCgIJAgAAAA==.Kroo:BAAALgAECgYJDQABLgAECggJIQABAFYXAA==.Krythas:BAAALgADCgIJAgAAAA==.',
Ku='Kuwabara:BAAALgADCgUJBQAAAA==.',
Kv='Kvothè:BAAALgAECgYJDAAAAA==.',
Ky='Kyi:BAABLgAECn8eAAIWAAkJhBHqFACGAQAWAAkJhBHqFACGAQAAAA==.',
['Kî']='Kîrîto:BAAALgAECgIJBQABLgAECggJFAAJAGMeAA==.',
La='Lactosetwo:BAAALgAECgEJAQAAAA==.Landar:BAABLgAECn8zAAIcAAkJbxP2GAD9AQAcAAkJbxP2GAD9AQAAAA==.Lathindra:BAAALgAECgEJAgAAAA==.Lazerpony:BAAALgAECgEJAwABLgAECgQJBgAHAAAAAA==.',
Le='Leggomyâggro:BAAALgAECgcJDwABLgAFFAQJDAANALkSAA==.Lexicon:BAAALgAECgMJAwAAAA==.',
Li='Liara:BAABLgAECn8fAAIdAAgJHw3SDgC7AQAdAAgJHw3SDgC7AQAAAA==.Lireesa:BAABLgAECn8jAAISAAgJmRB2BgCHAQASAAgJmRB2BgCHAQAAAA==.Lithiandriel:BAAALgAECgYJEgAAAA==.Liçk:BAAALgAECgMJAwABLgAECggJHAAcADkcAA==.',
Lo='Lockonyou:BAAALgAECgYJEQAAAA==.Logeofford:BAAALgADCgYJBQAAAA==.Lolola:BAAALgAECgQJBAAAAA==.',
Lu='Lunn:BAABLgAECn8YAAIKAAcJug8JDQAbAQAKAAcJug8JDQAbAQAAAA==.Lurac:BAAALgAECgEJAQABLgAFFAEJAQAHAAAAAA==.',
Ma='Madhi:BAAALgADCgcJDQAAAA==.Mahk:BAABLgAECn8UAAILAAcJlBWuUgBOAQALAAcJlBWuUgBOAQAAAA==.Majin:BAAALgAECgMJAwABLgAECgkJFQALAA4UAA==.Mangreese:BAABLgAECn8cAAIeAAkJ7g6DBgDVAQAeAAkJ7g6DBgDVAQAAAA==.Matelk:BAAALgAECgEJAQAAAA==.',
Me='Meekseek:BAAALgAECgQJDgAAAA==.Meltdown:BAAALgADCgQJBAAAAA==.Memoo:BAAALgADCgUJBQAAAA==.',
Mi='Miahealifa:BAABLgAECn8YAAMaAAcJOQt3JQD9AAAEAAYJgAlXRwAcAQAaAAYJLAl3JQD9AAAAAA==.Milim:BAAALgAECgUJBQAAAA==.Miloh:BAAALgAECgEJAQAAAA==.Mistabubbles:BAAALgAECgYJBgAAAA==.Mistmia:BAAALgADCgUJBQAAAA==.Mixmasterg:BAABLgAECn8eAAIXAAgJFgxmOwBJAQAXAAgJFgxmOwBJAQAAAA==.',
Mo='Mograinez:BAACLgAFFH8ZAAITAAcJdCVyAACEAgATAAcJdCVyAACEAgAuAAQKfxUAAhMACAl9Jp4cANMCABMACAl9Jp4cANMCAAAA.Monkeyman:BAAALgADCgIJAgAAAA==.Moosebreath:BAAALgAECgQJBAABLgAECgcJFQAaAFwfAA==.',
Mu='Murderer:BAAALgAECgMJBgAAAA==.',
My='Mythunrus:BAABLgAECn8YAAIfAAYJIhI6MgBDAQAfAAYJIhI6MgBDAQAAAA==.',
['Mó']='Móñk:BAAALgAECgcJEgAAAA==.',
['Mö']='Mörgana:BAAALgADCgQJBAAAAA==.',
Na='Narofu:BAAALgADCgQJBAAAAA==.Nazurasar:BAAALgAECgMJAwAAAA==.',
Ne='Nejìre:BAAALgADCgYJCQAAAA==.Neutron:BAAALgAECgIJAgAAAA==.',
No='Norolock:BAABLgAECn8aAAIIAAgJlRbqIgDhAQAIAAgJlRbqIgDhAQAAAA==.Notbreeze:BAAALgADCgYJBgAAAA==.Notsure:BAAALgAECgYJBgAAAA==.',
Nu='Nuero:BAAALgAFFAIJAgAAAA==.Nukashine:BAAALgADCgYJCAAAAA==.Nuuro:BAAALgAECgcJEgAAAA==.',
Ny='Ny:BAAALgADCgUJBQAAAA==.Nyverra:BAAALgADCgQJBAAAAA==.',
['Nã']='Nãrcissus:BAACLgAFFH8IAAMYAAMJWhtYAwBfAAAIAAIJrxnOUwClAAAYAAEJrx5YAwBfAAAuAAQKfyYABAgACAnNH/UnAMcBAAgABglgH/UnAMcBABIABAkoF3EuAAIBABgAAwnQIDAWANEAAAAA.',
Ol='Oldshotz:BAAALgAECgYJDAAAAA==.',
Om='Omgsteak:BAAALgAECgUJCQAAAA==.',
On='Onapalehorse:BAAALgADCgUJCgAAAA==.Onger:BAAALgADCgEJAQAAAA==.Onlybusa:BAAALgAECgEJAwAAAA==.Ons:BAAALgAECgQJBAAAAA==.',
Ow='Owl:BAAALgAECgEJAQABLgAECgcJGQALAJMTAA==.',
Pa='Panpots:BAAALgADCgYJBgAAAA==.Panzerdox:BAAALgAECgUJBQAAAA==.Panzerwolf:BAECLgAFFH8VAAIQAAQJdSR3AgCvAQAQAAQJdSR3AgCvAQAuAAQKf00AAxAACQkSJmQAANADABAACQkSJmQAANADAAMABQmGB2FvAPoAAAAA.Patchnotes:BAAALgAECgYJCwAAAA==.',
Pe='Peepaw:BAAALgAFFAIJAgAAAA==.',
Po='Poorclass:BAAALgADCgcJCAAAAA==.',
Pr='Prayforme:BAABLgAECn8bAAIaAAgJAhwGBgCZAgAaAAgJAhwGBgCZAgAAAA==.Prettynails:BAAALgAECggJDwAAAA==.Prise:BAABLgAECn8WAAMSAAcJOREDGwB1AQASAAcJvhADGwB1AQAIAAYJRw4siAC1AAAAAA==.',
Ps='Psilocybic:BAABLgAECn8aAAMVAAkJdQmlSQBbAQAVAAkJdQmlSQBbAQAUAAYJ4wflTwAHAQAAAA==.',
Qw='Qweh:BAAALgAECgYJDwAAAA==.',
Ra='Rahnko:BAAALgAECgQJAgAAAA==.Rakkasei:BAACLgAFFH8FAAIBAAIJWwcoMACJAAABAAIJWwcoMACJAAAuAAQKfxwAAwEACQnQFMEZAP8BAAEACQnQFMEZAP8BAA8AAwn+BOsyAH4AAAAA.Ralthas:BAAALgADCggJEgAAAA==.Randark:BAABLgAECn8nAAQCAAgJhRr3CgD0AQACAAYJCx33CgD0AQADAAcJ0g8yTwBqAQAQAAYJOxQ8FgASAQAAAA==.Razkal:BAAALgAECgYJDQAAAA==.Razzlock:BAAALgADCgcJBwAAAA==.',
Re='Reshiiram:BAAALgAECgEJAQAAAA==.Retneprac:BAAALgADCgQJBAAAAA==.Revirginator:BAABLgAECn8bAAMgAAcJ3Ab3JADgAAAgAAcJPgb3JADgAAALAAEJ5AYtUgErAAAAAA==.Revna:BAAALgAECgEJAwAAAA==.',
Rh='Rhagnar:BAAALgAECgQJBAAAAA==.',
Ri='Richandfamus:BAAALgAECgUJCwAAAA==.Riftstalker:BAAALgAECgcJEwAAAA==.',
Rn='Rngesus:BAACLgAFFH8FAAIIAAMJbAr1SQDEAAAIAAMJbAr1SQDEAAAuAAQKfyQAAwgACQkFHusUADoCAAgACQkFHusUADoCABIAAgliBrtWAGoAAAAA.',
Ro='Rocmaul:BAAALgADCgkJCQAAAA==.',
Ru='Rushem:BAAALgAECggJEwAAAA==.Ruwa:BAAALgADCgUJBQAAAA==.',
Ry='Ryft:BAABLgAECn8XAAITAAgJzBZYXwAmAQATAAgJzBZYXwAmAQAAAA==.Ryhaz:BAAALgADCgcJBwAAAA==.',
Sa='Saenen:BAABLgAECn8WAAIhAAcJuQv6EAALAQAhAAcJuQv6EAALAQAAAA==.Sandrozarke:BAABLgAECn8hAAQBAAgJVhc0EQBmAgABAAgJPxc0EQBmAgAPAAEJ+RJQPAA8AAAOAAEJygJoRwA4AAAAAA==.Sarah:BAAALgAECgIJAgABLgAECgkJLgAaAMsbAA==.',
Sc='Scrublet:BAAALgAECgYJCgAAAA==.',
Se='Seldara:BAABLgAECn8bAAMTAAgJzwXGhgDTAAATAAgJaQPGhgDTAAAiAAQJwwilDgC5AAAAAA==.Seraphic:BAAALgAECgkJAwAAAA==.Serenity:BAABLgAECn8WAAIaAAQJZyGBFwB8AQAaAAQJZyGBFwB8AQAAAA==.Sergeyred:BAAALgADCgUJBQAAAA==.Serlyn:BAAALgAECgYJEAAAAA==.Seseria:BAABLgAECn8kAAMgAAkJ0RO3EgCfAQAgAAgJ6xG3EgCfAQARAAUJYhU8KABKAQAAAA==.Sevinofnine:BAAALgADCgYJCAAAAA==.',
Sh='Shalamar:BAAALgAECgEJBAAAAA==.Shanic:BAABLgAECn8YAAIjAAgJ0xekDQDxAQAjAAgJ0xekDQDxAQAAAA==.Shiddybill:BAAALgAECgQJBAAAAA==.Shiftor:BAAALgADCgYJBgABLgAECgEJAQAHAAAAAA==.Shiftyslice:BAAALgAECgEJAgAAAA==.Shihiro:BAAALgADCgIJAQAAAA==.',
Si='Siberianbull:BAAALgADCgEJAQAAAA==.Siena:BAAALgAECgEJAQAAAA==.',
Sl='Slaveman:BAAALgADCgYJBgAAAA==.Slitherina:BAAALgADCgYJBgAAAA==.Slåkritisk:BAABLgAECn8XAAIdAAgJaA1PEgCdAQAdAAgJaA1PEgCdAQAAAA==.',
Sm='Smitervane:BAAALgADCgcJDQAAAA==.Smogy:BAAALgAECgIJAgAAAA==.',
Sn='Snipyterror:BAAALgADCgEJAQAAAA==.Snoodly:BAABLgAECn8VAAIkAAgJhxBlFgCkAQAkAAgJhxBlFgCkAQAAAA==.',
So='Solarice:BAABLgAECn8YAAMJAAgJxxy0GQBRAgAJAAgJjRy0GQBRAgAlAAEJ5iBkGQBMAAAAAA==.Soletaken:BAAALgADCgQJBwAAAA==.Solunais:BAABLgAECn8iAAIIAAkJuwuIKwC3AQAIAAkJuwuIKwC3AQAAAA==.Soramor:BAAALgADCgcJCAAAAA==.Sorynn:BAAALgAECgEJAQAAAA==.',
Sp='Spirallidan:BAABLgAECn8WAAIXAAkJDRMiSwDIAQAXAAkJDRMiSwDIAQAAAA==.Spy:BAAALgADCgQJBAAAAA==.',
St='Stardor:BAAALgAECgkJBwAAAA==.Staticprot:BAABLgAFFH8FAAIQAAQJzgv3DgDIAAAQAAQJzgv3DgDIAAAAAA==.Staticsrexar:BAAALgADCgcJBwABLgAFFAQJBQAQAM4LAA==.Stature:BAAALgAECgUJBQAAAA==.Stepbro:BAABLgAECn8hAAITAAgJJxpuHAAeAgATAAgJJxpuHAAeAgAAAA==.Stinksauce:BAACLgAFFH8OAAIOAAQJTR7+CgBnAQAOAAQJTR7+CgBnAQAuAAQKfxoABA4ACQkHGmoNAGACAA4ACQkHGmoNAGACAAEAAQl0BshhADUAAA8AAQmvB3k/ADIAAAAA.Stormvetra:BAAALgAECgQJBQAAAA==.',
Su='Supabox:BAAALgAECgcJEgABLgAFFAUJEwAMAKkjAA==.Superchunk:BAAALgAECgEJAQAAAA==.Suryoudie:BAAALgADCgQJBAAAAA==.Sutra:BAABLgAECn8YAAIEAAcJYwuwJAAkAQAEAAcJYwuwJAAkAQAAAA==.',
Sw='Swiftmend:BAAALgAECgYJBgABLgAECggJDQAHAAAAAA==.',
Sy='Sylmarillion:BAABLgAECn8bAAIRAAgJlhbVEQAKAgARAAgJlhbVEQAKAgAAAA==.',
['Sø']='Sørry:BAABLgAECn8XAAIMAAcJkRk1EADJAQAMAAcJkRk1EADJAQAAAA==.',
Ta='Talgulen:BAABLgAECn8sAAIPAAkJXh3UAADEAgAPAAkJXh3UAADEAgAAAA==.Tankytauren:BAABLgAECn8cAAMTAAgJ/hEpNQCkAQATAAgJ+hApNQCkAQAiAAYJRQ+vCABaAQAAAA==.Tarquinius:BAABLgAECn8mAAIfAAkJUQ8iDQCvAQAfAAkJUQ8iDQCvAQAAAA==.Tatianasoles:BAAALgAECgEJAQAAAA==.Taxii:BAAALgAECgUJCQABLgAECgkJLQADADYlAA==.',
Te='Telanastre:BAAALgAECgMJAwAAAA==.',
Th='Tharos:BAAALgADCgEJAQAAAA==.Theat:BAAALgAECgQJDAAAAA==.Theoeicke:BAAALgAECgYJBgABLgAECgkJHgAWAIQRAA==.Thibbledor:BAAALgADCgkJFAABLgAECgYJFAAUAOUSAA==.',
Ti='Tifferny:BAAALgAECgIJAwAAAA==.Tiffèrny:BAAALgADCgUJBQAAAA==.Tinydrunk:BAAALgADCggJCAAAAA==.',
To='Tondra:BAAALgAECgYJCQAAAA==.Tone:BAABLgAECn8XAAMjAAgJ+xNULQCZAQAjAAcJaRNULQCZAQAcAAgJHw27YQAsAQAAAA==.Tonkatruck:BAAALgAECgUJBAAAAA==.Totemlycool:BAABLgAECn8gAAQUAAgJGxWtIAAKAgAUAAgJCRStIAAKAgAeAAYJlRcEEgCWAQAVAAIJhAGRkwBNAAABLgAECggJIQABAFYXAA==.',
Tr='Trappress:BAAALgAECgcJBwAAAA==.Treehuggër:BAAALgAECgIJAgAAAA==.Trowa:BAAALgAECgIJAgABLgAFFAEJAQAHAAAAAA==.Trowaz:BAAALgAFFAEJAQAAAA==.Truffles:BAAALgADCgQJBAABLgAECggJIQASAJUaAA==.Tryrah:BAABLgAFFH8TAAIjAAYJ3RPBBACfAQAjAAYJ3RPBBACfAQAAAA==.',
Tw='Twinsons:BAAALgADCgEJAQAAAA==.Twisty:BAAALgAECgQJBQABLgAFFAEJAQAHAAAAAA==.Twîsty:BAAALgAECgUJBgABLgAFFAEJAQAHAAAAAA==.',
Ty='Tygron:BAAALgADCgQJBAAAAA==.Tyleroth:BAABLgAECn8gAAIXAAkJYhKUJgCjAQAXAAkJYhKUJgCjAQAAAA==.Tyrasia:BAAALgAECgEJAgAAAA==.Tyrith:BAABLgAECn8WAAMDAAgJsxhCPgCrAQADAAcJ4hhCPgCrAQACAAMJrReuHgDEAAAAAA==.',
['Tö']='Töömis:BAABLgAECn8ZAAILAAcJkxOFfACBAQALAAcJkxOFfACBAQAAAA==.',
Ug='Ugotgotpal:BAAALgAECgcJCAAAAA==.',
Ul='Ulazain:BAABLgAECn8sAAIDAAkJDx9mAwDXAgADAAkJDx9mAwDXAgAAAA==.',
Ur='Urza:BAAALgADCgYJDQAAAA==.',
Us='Usdaprime:BAABLgAECn8dAAIhAAgJqA2XCQCNAQAhAAgJqA2XCQCNAQAAAA==.',
Va='Valarjar:BAAALgADCgIJAgABLgADCgQJBAAHAAAAAA==.Vandene:BAAALgADCgEJAgAAAA==.',
Ve='Velderen:BAAALgAECgQJBAAAAA==.Vengance:BAAALgADCgMJAwAAAA==.Verstappen:BAAALgADCgEJAQAAAA==.',
Vi='Viì:BAABLgAECn8YAAILAAcJXggVigDZAAALAAcJXggVigDZAAAAAA==.',
Vo='Volsunga:BAAALgAECgQJBwAAAA==.',
Wi='Wildling:BAAALgADCgMJAwAAAA==.Winda:BAAALgADCggJCQAAAA==.',
Wr='Wrease:BAAALgADCgQJBQAAAA==.',
Xa='Xam:BAAALgAECgYJEgAAAA==.Xaphyre:BAAALgADCgEJAQAAAA==.Xarthas:BAAALgAECgMJBAAAAA==.Xavia:BAABLgAECn8YAAIIAAgJixPbJQDSAQAIAAgJixPbJQDSAQAAAA==.',
Xy='Xylazel:BAABLgAECn8fAAITAAkJqxUtFwBCAgATAAkJqxUtFwBCAgAAAA==.',
Ya='Yasmina:BAAALgAECgYJDgAAAA==.',
Yv='Yvana:BAAALgAECgQJEwAAAA==.',
Za='Zaradrela:BAAALgAECgEJAQAAAA==.',
Zu='Zugmaster:BAAALgADCgEJAQAAAA==.',
Zz='Zzephyrdruid:BAACLgAFFH8ZAAIjAAcJdiC3AABeAgAjAAcJdiC3AABeAgAuAAQKfxwAAiMACAnEJZMNAMECACMACAnEJZMNAMECAAAA.Zzephyrev:BAAALgAECgYJDwABLgAFFAcJGQAjAHYgAA==.',
['Âs']='Âsunâ:BAABLgAECn8cAAIcAAgJORyfDgBoAgAcAAgJORyfDgBoAgAAAA==.',
['Ôä']='Ôäk:BAAALgADCgYJCwABLgAECgcJGgAcANcOAA==.',
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

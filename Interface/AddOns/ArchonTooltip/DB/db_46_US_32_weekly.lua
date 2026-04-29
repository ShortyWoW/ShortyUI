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

local lookup = {'Druid-Restoration','DemonHunter-Devourer','Evoker-Augmentation','Evoker-Devastation','Druid-Guardian','Priest-Holy','Monk-Mistweaver','Monk-Windwalker','Monk-Brewmaster','Paladin-Retribution','Paladin-Protection','Unknown-Unknown','Hunter-BeastMastery','Shaman-Enhancement','DeathKnight-Unholy','Mage-Frost','Hunter-Marksmanship','Priest-Discipline','Warlock-Destruction','Warlock-Demonology','Paladin-Holy','Druid-Balance','Mage-Arcane','DemonHunter-Vengeance','DeathKnight-Blood','Shaman-Elemental','DemonHunter-Havoc','Warrior-Arms','Warrior-Fury','Rogue-Subtlety','Rogue-Assassination','Warrior-Protection','Priest-Shadow','Shaman-Restoration','Warlock-Affliction','Hunter-Survival','Druid-Feral',}
local provider = {region='US',realm='Blackhand',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Abadacalama:BAAALgAECgcJDQAAAA==.',
Ad='Adera:BAAALgADCgEJAQAAAA==.',
Ae='Aellee:BAAALgAECgQJCAAAAA==.Aeninas:BAAALgAECgYJDwAAAA==.Aeris:BAAALgADCgEJAQAAAA==.Aerynn:BAAALgADCgIJAgAAAA==.Aethwyn:BAAALgAECgYJBgAAAA==.',
Af='Afflictions:BAAALgADCgUJBQAAAA==.',
Ag='Agandaur:BAAALgAECgEJAQAAAA==.',
Ah='Ahnkala:BAAALgAECgMJBQAAAA==.Ahzi:BAABLgAECn8YAAIBAAcJCx0FBABUAgABAAcJCx0FBABUAgAAAA==.Ahzii:BAAALgADCgYJBwAAAA==.',
Ai='Aigirlfriend:BAABLgAECn8WAAICAAcJ6wgNdwBBAQACAAcJ6wgNdwBBAQAAAA==.',
Al='Allupcreepy:BAAALgAECgYJDgAAAA==.Alphaandy:BAAALgAECgMJAwAAAA==.Alphaboy:BAAALgADCgcJBwAAAA==.Alphaxdruid:BAAALgAECgMJAwAAAA==.Alysara:BAAALgAECgMJAwAAAA==.',
Am='Ambewlance:BAAALgAECgcJEwAAAA==.Ambrosious:BAAALgAECgEJAQAAAA==.Amethystra:BAABLgAECn8YAAMDAAgJ3woSLgBRAQADAAgJ3woSLgBRAQAEAAMJwwaLMgCBAAAAAA==.Amâlynd:BAABLgAECn8VAAIBAAYJ9AbxHwC2AAABAAYJ9AbxHwC2AAAAAA==.',
An='Anastasiaro:BAAALgADCgEJAQAAAA==.Annimosity:BAAALgAECgEJAQAAAA==.Ansem:BAAALgADCgUJBgAAAA==.Anthesis:BAABLgAECn8aAAIBAAgJuBSWNgDNAQABAAgJuBSWNgDNAQAAAA==.Anthonor:BAAALgAECgYJCAAAAA==.Anubrian:BAAALgAECgYJCwAAAA==.Anúbis:BAAALgAECgMJBQAAAA==.',
Ap='Apawllo:BAABLgAECn8eAAIFAAgJxRXyDAC5AQAFAAgJxRXyDAC5AQAAAA==.Apep:BAAALgAECgQJBwAAAA==.Apostle:BAACLgAFFH8NAAIGAAUJmxlSAQC6AQAGAAUJmxlSAQC6AQAuAAQKfyMAAgYACAkJI9kGAOACAAYACAkJI9kGAOACAAAA.',
Ar='Aryto:BAAALgAECgYJEAAAAA==.',
As='Asketill:BAAALgAFFAEJAQAAAA==.',
At='Ativan:BAEBLgAECn8VAAQHAAYJ8hTwKwBZAQAHAAYJ8hTwKwBZAQAIAAMJuAcVFACZAAAJAAEJcwDUKwAbAAAAAA==.',
Au='Auluras:BAAALgADCgUJBQAAAA==.',
Av='Avitus:BAAALgADCgEJAgAAAA==.',
Ay='Aylari:BAABLgAECn8gAAMKAAgJkyLRDgAYAwAKAAgJICLRDgAYAwALAAYJ+ReVEgCgAQAAAA==.',
Az='Azonya:BAAALgADCgEJAgAAAA==.Azuth:BAAALgADCgMJAwAAAA==.',
Ba='Bachren:BAAALgAECgQJBAAAAA==.Badil:BAAALgADCgIJAgAAAA==.Baitken:BAAALgAECgUJCQABLgAECgYJDwAMAAAAAA==.Batharel:BAABLgAECn8VAAINAAcJYBUoMgDnAQANAAcJYBUoMgDnAQAAAA==.',
Bd='Bdrone:BAAALgADCgYJCAAAAA==.',
Be='Bearen:BAABLgAECn8cAAIOAAcJwQiuBgAaAQAOAAcJwQiuBgAaAQAAAA==.Bedazzle:BAAALgADCgcJBwABLgAFFAUJDQAGAJsZAQ==.Beefo:BAAALgADCgUJBAAAAA==.Beemz:BAAALgAECgYJDgAAAA==.Beertrain:BAABLgAECn8bAAIPAAgJMhZVBwALAgAPAAgJMhZVBwALAgAAAA==.Beesechurger:BAABLgAECn8YAAIQAAcJXhpZFQCYAQAQAAcJXhpZFQCYAQAAAA==.Bekindrewind:BAABLgAECn8YAAIDAAgJrBa5BgCKAQADAAgJrBa5BgCKAQAAAA==.Belladonia:BAAALgADCgcJBwABLgAECggJIQABAIAVAA==.Belladue:BAAALgADCgMJBgAAAA==.Bellezza:BAABLgAECn8hAAIBAAgJgBUzKAAUAgABAAgJgBUzKAAUAgAAAA==.Bex:BAAALgADCgEJAQAAAA==.',
Bh='Bheef:BAAALgADCgMJAwAAAA==.',
Bi='Bigdisc:BAAALgADCgIJAgABLgAECgEJAQAMAAAAAA==.Bigdumbcatqt:BAABLgAECn8aAAILAAgJ8CZbAACfAwALAAgJ8CZbAACfAwAAAA==.',
Bl='Blinkk:BAAALgADCgEJAgABLgADCgMJAwAMAAAAAA==.Bloodshhot:BAABLgAECn8fAAMNAAgJJA8jPgC2AQANAAcJHBEjPgC2AQARAAEJVANOjgAsAAAAAA==.Bludgen:BAAALgAECgEJAQABLgAECgcJGAASAF4bAA==.',
Bo='Bobitt:BAAALgAECgMJBQAAAA==.Boddyknocker:BAAALgAECgYJBgAAAA==.Boinkusan:BAABLgAECn8ZAAIHAAgJ3B/bAwAFAgAHAAgJ3B/bAwAFAgAAAA==.Bolthar:BAAALgAECgYJEgAAAA==.Bonkler:BAABLgAECn8YAAMTAAcJqBpUEgC5AQATAAYJyhlUEgC5AQAUAAcJ+hPKEgB6AQAAAA==.Boombox:BAAALgAECgYJDQAAAA==.Boomwand:BAAALgAECgMJBAABLgAECgcJEwAMAAAAAA==.Boonerichard:BAAALgAECgMJAwAAAA==.Bootysweatz:BAAALgADCgcJCQAAAA==.Bouchewager:BAAALgADCgEJAQAAAA==.',
Br='Braina:BAAALgAECgQJBwAAAA==.Braver:BAACLgAFFH8HAAIRAAQJvgp7EQAgAQARAAQJvgp7EQAgAQAuAAQKfyIAAhEACQkBHx4JAAwDABEACQkBHx4JAAwDAAAA.Braverwar:BAAALgAECgYJCQABLgAFFAQJBwARAL4KAA==.Brayedine:BAAALgAECgQJBgAAAA==.Breekachu:BAAALgADCgYJBgAAAA==.Brodin:BAAALgADCgEJAQAAAA==.Brohymn:BAAALgADCgEJAQAAAA==.Brooké:BAAALgADCgEJAQAAAA==.',
Bu='Bubblebutt:BAAALgADCgEJAQAAAA==.Bubbledis:BAAALgAECgQJDAABLgAECgcJEwAMAAAAAA==.Bullfury:BAAALgADCgEJAQAAAA==.',
['Bù']='Bùbbles:BAAALgADCgkJEgAAAA==.',
Ca='Cadelsaya:BAABLgAECn8hAAMVAAgJfw4nNACtAQAVAAgJfw4nNACtAQAKAAIJHAIKKwFLAAAAAA==.Caletha:BAABLgAECn8WAAMGAAYJSRsTKQCpAQAGAAYJ5RgTKQCpAQASAAUJRBejIgB/AQAAAA==.Calimaria:BAAALgADCgMJAwAAAA==.Calixte:BAAALgAECgYJCgAAAA==.Cammandzar:BAAALgAECgYJCQABLgABCgMJAwAMAAAAAA==.Canman:BAAALgAECgEJAQAAAA==.Cardeller:BAAALgADCgUJCAAAAA==.Cassei:BAABLgAECn8uAAMVAAgJah0eDQCwAgAVAAgJah0eDQCwAgAKAAMJfwRgEwFwAAAAAA==.',
Ce='Celenia:BAAALgAECgQJBgAAAA==.Celorious:BAAALgAECgYJDgAAAA==.',
Ch='Chainari:BAAALgAECgQJCQAAAA==.Chassis:BAAALgADCgIJAgABLgAECgMJBQAMAAAAAA==.Chawìzawd:BAAALgADCgYJBgAAAA==.Chee:BAAALgAECgEJAgAAAA==.Cheechychong:BAAALgAECgEJAQAAAA==.Cheeksdakota:BAAALgADCgYJBgAAAA==.Cheetopaly:BAAALgAECgYJEwAAAA==.Cherrycrush:BAAALgAECgMJAwAAAA==.Chummy:BAABLgAECn8YAAIWAAgJRw9FBgCgAQAWAAgJRw9FBgCgAQAAAA==.Chìgusa:BAABLgAECn8eAAIGAAgJ0RTCHgDpAQAGAAgJ0RTCHgDpAQAAAA==.',
Ci='Cigarette:BAAALgAECgQJCQAAAA==.Cilenzer:BAAALgADCgEJAQAAAA==.Circa:BAAALgADCgUJBwAAAA==.',
Cl='Clumonk:BAAALgAECgYJEgAAAA==.',
Co='Convoke:BAAALgAECgcJCgABLgAFFAUJDQAGAJsZAA==.Coosedaplug:BAAALgADCgEJAQAAAA==.Coosey:BAAALgAECgMJBAABLgAECgQJCQAMAAAAAA==.Coosicle:BAAALgAECgIJAgAAAA==.Coredron:BAAALgAECgMJAwAAAA==.Corellon:BAAALgAECgYJEwAAAA==.Corinth:BAABLgAECn8eAAIXAAgJwRxcAAAvAgAXAAgJwRxcAAAvAgAAAA==.',
Cr='Cratoz:BAAALgAECgYJCAAAAA==.Craylic:BAAALgADCgkJDgAAAA==.Creepi:BAAALgAECgIJAgAAAA==.Criah:BAAALgADCggJCQAAAA==.Crixhs:BAAALgADCgUJBQAAAA==.Crossgideon:BAAALgAECgYJEwAAAA==.Crossword:BAAALgADCgcJBwAAAA==.Croswind:BAAALgADCgUJBQABLgAECgYJEwAMAAAAAA==.',
Cu='Curandero:BAAALgADCgYJCQABLgAECgEJAQAMAAAAAA==.',
Cy='Cyndrine:BAABLgAECn8eAAIYAAgJjCNFAAC2AgAYAAgJjCNFAAC2AgAAAA==.Cynex:BAAALgADCgMJAwAAAA==.Cyrani:BAAALgADCgcJBwAAAA==.Cyrcyn:BAAALgAECggJCAAAAA==.',
Da='Dadipps:BAAALgAECgYJDgAAAA==.Daggumit:BAAALgADCgYJBwAAAA==.Dagnei:BAAALgAECgIJAgAAAA==.Daltina:BAAALgAECgYJDAAAAA==.Dannyboone:BAAALgADCgEJAQAAAA==.Darg:BAAALgAECgYJEAAAAA==.Daurgoth:BAAALgADCgEJAQAAAA==.',
Dd='Ddream:BAAALgADCgMJAwAAAA==.',
De='Deathpuma:BAAALgAECgUJDwAAAA==.Deathrowe:BAABLgAECn8VAAIPAAYJUBhVGQBKAQAPAAYJUBhVGQBKAQAAAA==.Deezenuts:BAAALgADCgMJAwAAAA==.Delorayne:BAAALgADCgEJAQAAAA==.Demonponii:BAAALgAECgMJAwAAAA==.Demonvann:BAAALgADCgkJCgAAAA==.Denouncer:BAAALgAECgcJEwAAAA==.Deralth:BAAALgAECgMJAwAAAA==.Derca:BAAALgAECgQJBwAAAA==.Dethman:BAAALgAECgQJBwAAAA==.Devoider:BAAALgAECgIJAgAAAA==.',
Di='Diddyknight:BAABLgAECn8fAAIZAAgJJBCQFgCsAQAZAAgJJBCQFgCsAQAAAA==.Diddyrox:BAAALgADCgkJCAABLgAECggJGQAZAAgdAA==.Dienne:BAEALgAECggJEgABLgAECgkJFQAHAPIUAA==.Diminish:BAAALgAECgQJBwABLgAECgQJCQAMAAAAAA==.Diminutive:BAAALgADCgEJAQAAAA==.Dinarra:BAAALgADCgMJAwAAAA==.Diosdelaluna:BAAALgADCggJDgAAAA==.Dipity:BAAALgADCgYJBgAAAA==.Discobirb:BAABLgAECn8cAAMUAAgJZBfkEgB5AQAUAAYJdhbkEgB5AQATAAMJEBT4CQB+AAAAAA==.',
Do='Docdrood:BAAALgADCgMJAwAAAA==.Dohdag:BAAALgADCgEJAQAAAA==.Dokkyun:BAAALgADCgEJAwAAAA==.Donlazul:BAAALgAECggJEwAAAA==.Dorff:BAABLgAECn8UAAITAAYJjBUTFQCiAQATAAYJjBUTFQCiAQAAAA==.Dotlotto:BAAALgAECgYJDAAAAA==.',
Dr='Draconoth:BAAALgAECgYJDwAAAA==.Dragonare:BAAALgAECgYJBgABLgAECggJGQAZAAgdAA==.Dragonir:BAAALgAECgQJCgABLgAECgYJFAAKAIUZAA==.Dranddrand:BAABLgAECn8WAAIJAAgJCBx4EwB1AgAJAAgJCBx4EwB1AgAAAA==.Dreadborn:BAAALgADCgYJCAAAAA==.Dreadform:BAAALgADCgYJBgAAAA==.Drizit:BAAALgAECgQJBAAAAA==.',
Du='Dumbbear:BAAALgADCgcJCgAAAA==.Dungard:BAAALgADCgcJBwABLgAECggJIQAVAH8OAA==.',
Dy='Dyami:BAAALgADCgkJCQAAAA==.',
['Dè']='Dèadèyè:BAAALgADCgEJAQAAAA==.',
Ea='Eatmorechkn:BAAALgAECggJEgAAAA==.',
Ed='Edgli:BAAALgAECgQJBAAAAA==.Edlania:BAAALgAECgEJAQAAAA==.',
Ee='Eellonwy:BAAALgAECgMJBAAAAA==.Eemerald:BAAALgAECgMJAwAAAA==.',
Eg='Egna:BAABLgAECn8ZAAIaAAgJPxADDAA7AQAaAAgJPxADDAA7AQAAAA==.',
El='Eldiablo:BAABLgAECn8eAAIPAAgJ7Bo2BQA3AgAPAAgJ7Bo2BQA3AgAAAA==.Elfshots:BAAALgADCgQJBAABLgAECgcJEwAMAAAAAA==.Elizaa:BAAALgAECgYJEwAAAA==.Ellemeno:BAAALgADCgUJBQAAAA==.Eloria:BAAALgADCgIJAgAAAA==.',
Em='Emmadar:BAAALgADCgkJCQABLgAECggJHgATANoTAA==.',
En='Ennoa:BAAALgAECgIJAgAAAA==.',
Er='Eric:BAAALgAECgYJCQAAAA==.',
Et='Etoya:BAAALgAECgMJAwAAAA==.',
Ex='Execute:BAAALgADCgYJBwAAAA==.',
Ez='Ezykeil:BAAALgADCgYJBgAAAA==.',
Fe='Feelinbetter:BAAALgAECgEJAQAAAA==.Fenrigaar:BAABLgAECn8VAAIWAAYJSRecLACeAQAWAAYJSRecLACeAQAAAA==.',
Fi='Fillin:BAAALgAECgEJAQAAAA==.Filô:BAAALgAFFAIJAgAAAA==.',
Fj='Fjörd:BAAALgAECgEJAgAAAA==.',
Fl='Flanker:BAAALgADCgUJBQABLgAECgcJGAAQAF4aAA==.Flasherdemon:BAAALgAECgYJBgAAAA==.Flashoblight:BAAALgADCgYJDAABLgADCgkJDgAMAAAAAA==.',
Fo='Forsakenly:BAABLgAECn8YAAINAAcJ0hZ4DQCbAQANAAcJ0hZ4DQCbAQAAAA==.',
Fr='Frasti:BAAALgAECgEJAQAAAA==.Freshstart:BAAALgAECgYJCQAAAA==.Frostmage:BAABLgAECn8eAAIQAAgJ9xd3DQDfAQAQAAgJ9xd3DQDfAQAAAA==.',
Fu='Fuegoblazeit:BAAALgAECgIJAwAAAA==.Fuhsrodah:BAAALgADCgEJAgAAAA==.Fulgure:BAABLgAECn8eAAIaAAgJXhmfBADbAQAaAAgJXhmfBADbAQAAAA==.Furbucket:BAABLgAECn8WAAMWAAcJAwnCEQDbAAAWAAYJYQfCEQDbAAABAAQJLwjXkQCsAAAAAA==.Futon:BAAALgAECgQJBAAAAA==.Futonhunts:BAABLgAECn8dAAINAAgJrCALCQADAwANAAgJrCALCQADAwAAAA==.',
Fy='Fylerw:BAAALgAECgQJCQAAAA==.',
['Få']='Fåe:BAAALgAECgMJBAAAAA==.',
Ga='Gagoogamesh:BAAALgAECggJEwAAAA==.Gailyn:BAAALgADCgIJAgAAAA==.Galaxyshot:BAAALgADCgcJDAAAAA==.',
Ge='Gendershift:BAAALgADCgQJBAAAAA==.Getpsalm:BAAALgAECgIJAgAAAA==.',
Gh='Ghimpy:BAAALgAECgMJBQAAAA==.Ghostrideher:BAABLgAECn8WAAINAAgJjh2SCwCzAQANAAgJjh2SCwCzAQAAAA==.',
Gi='Gigafather:BAAALgAECgMJBAAAAA==.',
Go='Goochkiss:BAAALgAECgMJAwAAAA==.',
Gr='Griannee:BAABLgAECn8YAAIbAAcJYxqZAwC0AQAbAAcJYxqZAwC0AQAAAA==.Grimborn:BAAALgAECgIJAgAAAA==.Gripmedaddy:BAAALgADCgEJAQABLgAECgYJGAAHAO0VAA==.Grisdrips:BAAALgAECgQJBQAAAA==.Grislix:BAABLgAECn8VAAIUAAgJABPCQgAEAgAUAAgJABPCQgAEAgABLgAECgQJBQAMAAAAAA==.Gryffin:BAABLgAECn8YAAIQAAYJDw6oNgDqAAAQAAYJDw6oNgDqAAAAAA==.',
Gu='Gurrth:BAAALgADCgMJAwAAAA==.',
['Gâ']='Gânk:BAABLgAECn8eAAMcAAgJfAiUEwBsAQAcAAgJfAiUEwBsAQAdAAIJmQI6nQBKAAAAAA==.',
['Gå']='Gåladriel:BAAALgAECgEJAQAAAA==.',
Ha='Hael:BAAALgADCgEJAQAAAA==.Halar:BAAALgAECgYJDQAAAA==.Hammaford:BAAALgADCgMJAwAAAA==.Hardknockers:BAABLgAECn8VAAIdAAYJBwvkDwAtAQAdAAYJBwvkDwAtAQAAAA==.Hargyll:BAAALgAECgcJDAAAAA==.',
He='Heavychevy:BAAALgAECgYJEgAAAA==.Hellbentx:BAAALgAECgcJBwAAAA==.Heriel:BAAALgAECgQJBAABLgAECgYJFAAKAIUZAA==.',
Ho='Hokes:BAAALgAECgcJCwABLgAECggJGAABAHIXAA==.Hole:BAAALgADCgMJAwAAAA==.Homgar:BAAALgADCgYJBwAAAA==.',
Hu='Hughhoofner:BAAALgAECgIJAgAAAA==.Humphrees:BAABLgAECn8eAAMeAAgJzgrXBAC0AQAeAAgJzgrXBAC0AQAfAAEJFwaSIQAqAAAAAA==.Huraji:BAAALgAFFAIJAgABLgAFFAMJBgASAK4PAA==.',
['Hà']='Hàtos:BAABLgAECn8cAAIQAAYJrhjqmgCfAQAQAAYJrhjqmgCfAQAAAA==.Hàtoz:BAAALgAECgMJAwAAAA==.',
Ii='Iironrod:BAAALgADCgYJCQAAAA==.',
Im='Impawsum:BAAALgADCgUJBwAAAA==.',
In='Invissibill:BAAALgAECgYJDgAAAA==.',
Ir='Ironbark:BAAALgADCgYJCQAAAA==.',
Iv='Ivanã:BAAALgAECgYJEwAAAA==.',
Iz='Izax:BAAALgAECggJEgAAAA==.',
Ja='Jamestown:BAAALgADCgcJBwAAAA==.Janebquick:BAAALgAECgUJBgAAAA==.',
Je='Jelkal:BAAALgAECgcJBwAAAA==.',
Jj='Jjl:BAAALgAECgcJCwAAAA==.',
Jo='Johnnylingo:BAAALgAECgEJAQAAAA==.Johnwarcratf:BAAALgAECgYJDAAAAA==.',
Ju='Jupitus:BAABLgAECn8WAAIKAAcJQRJAIQAoAQAKAAcJQRJAIQAoAQAAAA==.Juícewrld:BAAALgAECgQJBQAAAA==.',
['Jå']='Jåhkøtå:BAAALgADCgYJBgAAAA==.',
Ka='Kaboomkablow:BAAALgAECgQJBAABLgAECgcJEwAMAAAAAA==.Kaosz:BAAALgADCgYJBgAAAA==.Karma:BAAALgAECgUJEAAAAA==.Katalanii:BAAALgAECgYJEQAAAA==.Kathtaer:BAAALgADCggJDQAAAA==.Katja:BAABLgAECn8YAAIUAAgJbRmeKQBqAgAUAAgJbRmeKQBqAgAAAA==.',
Ke='Keiwhenua:BAAALgAECgYJEQAAAA==.Keled:BAAALgADCgcJBwAAAA==.Kelinn:BAAALgAECgMJAwAAAA==.Kelzier:BAAALgAECgIJAwABLgAECgYJFAAKAIUZAA==.Kenthel:BAAALgAECgQJEAABLgAECgUJCwAMAAAAAA==.Kenthels:BAAALgAECgUJCwAAAA==.Kezt:BAAALgADCgEJAQAAAA==.',
Kh='Khalena:BAAALgADCgUJBwAAAA==.',
Ki='Kiiya:BAAALgAECgIJAgAAAA==.Kik:BAAALgAECgEJAQAAAA==.Killerchop:BAABLgAECn8aAAMXAAgJChngBADvAQAXAAcJ8BjgBADvAQAQAAcJIRMtfADZAQAAAA==.Kiplander:BAAALgAECgUJDAAAAA==.Kithforge:BAAALgADCgEJAQAAAA==.Kittytree:BAAALgADCgQJBAAAAA==.',
Ko='Kohii:BAAALgADCgQJBAAAAA==.Korry:BAAALgAECgQJBgAAAA==.Kortanis:BAAALgADCggJIAAAAA==.Korzaz:BAAALgAECgYJCwAAAA==.Kosiicek:BAAALgAECgEJAQAAAA==.Kotala:BAAALgADCgEJAQAAAA==.',
Kr='Krakìn:BAAALgAECgQJBgAAAA==.Krelanllan:BAAALgADCgkJCwAAAA==.Krilliz:BAAALgAECgcJEAAAAA==.Krocodile:BAAALgAECgEJAQAAAA==.',
Ku='Kushage:BAAALgADCgEJAQAAAA==.',
Ky='Kynlea:BAAALgADCgMJAwAAAA==.Kyumii:BAAALgADCgcJBwAAAA==.',
['Kì']='Kìla:BAAALgAECgEJAQABLgAECggJIAAKAJMiAA==.',
La='Landissa:BAABLgAECn8XAAIeAAYJOxu3KAC0AQAeAAYJOxu3KAC0AQAAAA==.Lanigosa:BAAALgADCggJBwAAAA==.Lanno:BAAALgADCgUJBgAAAA==.Laquandrae:BAAALgAECgUJEQAAAA==.Larryholmes:BAAALgAECgcJEwAAAA==.Lasting:BAAALgADCgYJCAAAAA==.Lathmaria:BAAALgADCgEJAQAAAA==.',
Le='Leche:BAAALgAECgUJBwAAAA==.Leenaa:BAABLgAECn8YAAIBAAYJ0BJMFAAlAQABAAYJ0BJMFAAlAQAAAA==.Lerash:BAAALgADCgIJAgAAAA==.',
Li='Liankaima:BAAALgADCgUJBQAAAA==.Lightninfury:BAAALgAECgEJAQAAAA==.Lihan:BAAALgAECgUJCgAAAA==.Lilieth:BAAALgADCgIJAgAAAA==.Lily:BAABLgAECn8dAAIPAAcJphtbDAC/AQAPAAcJphtbDAC/AQAAAA==.Livelyfist:BAAALgAECgUJDQAAAA==.Livelywilds:BAAALgADCgYJBgAAAA==.',
Lo='Locki:BAAALgADCgcJBwAAAA==.Loosenut:BAAALgAECgEJAQAAAA==.Losic:BAAALgADCgcJCwAAAA==.Lotzofblood:BAAALgADCgkJEgAAAA==.Loverocket:BAABLgAECn8UAAILAAcJhR65CQA1AgALAAcJhR65CQA1AgAAAA==.',
Lu='Lugosi:BAAALgADCgcJDQABLgAECggJIAACAN4ZAA==.Lullers:BAAALgAECgMJAwAAAA==.Luna:BAAALgAECgYJCwAAAA==.Luroe:BAAALgADCgkJCQAAAA==.',
Ly='Lyralina:BAEALgADCgQJBAABLgAECgkJFQAHAPIUAA==.Lysergicon:BAAALgADCgEJAQAAAA==.Lyshia:BAABLgAECn8ZAAIQAAgJqB9ALgC5AgAQAAgJqB9ALgC5AgAAAA==.Lyshion:BAAALgADCgYJBgAAAA==.',
['Lí']='Líghthand:BAABLgAECn8cAAILAAkJ5x2mAQA2AwALAAkJ5x2mAQA2AwAAAA==.',
['Lý']='Lýght:BAAALgADCggJDAAAAA==.',
Ma='Magdaanii:BAAALgAECgMJAwAAAA==.Magedown:BAABLgAECn8XAAIQAAgJPBGMEwClAQAQAAgJPBGMEwClAQAAAA==.Magician:BAAALgAECgQJBwABLgAECgcJEwAMAAAAAA==.Magicmallet:BAABLgAECn8ZAAIVAAgJYSSLAwA5AwAVAAgJYSSLAwA5AwAAAA==.Martinell:BAAALgADCgYJCQAAAA==.Matap:BAAALgADCgkJCQAAAA==.Mataw:BAABLgAECn8VAAMdAAgJwxc8AwAbAgAdAAgJQxc8AwAbAgAcAAYJ3BCzFgBHAQAAAA==.Mattdemon:BAABLgAECn8gAAICAAgJ3hllKABiAgACAAgJ3hllKABiAgAAAA==.',
Me='Mehruna:BAAALgADCgEJAgAAAA==.Meliany:BAAALgADCgMJAwAAAA==.Meliowar:BAAALgADCgQJBAAAAA==.Melkdudd:BAAALgAECgcJBwAAAA==.Mephmonster:BAAALgADCgEJAQAAAA==.Metroboomkin:BAAALgAECgIJAgAAAA==.',
Mi='Miksi:BAAALgADCgYJCQABLgAECgEJAQAMAAAAAA==.Miradele:BAAALgAECgYJDAAAAA==.Miraxx:BAAALgAECgEJAQAAAA==.Misscleö:BAAALgAECgYJEgAAAA==.Mistybrew:BAAALgADCgMJAwAAAA==.Miyoshi:BAAALgAECgYJDAAAAA==.Mizrhi:BAAALgADCgcJCgAAAA==.',
Mo='Monthy:BAAALgADCgUJCAAAAA==.Moonkey:BAAALgAECgIJAgAAAA==.Moosakka:BAABLgAECn8XAAMIAAgJyhdWDQD7AAAIAAYJMBJWDQD7AAAHAAYJHwwiFwB2AAAAAA==.Moosedluffy:BAAALgAECgQJBwAAAA==.Moosesiah:BAAALgAECgcJEQAAAA==.Moovinthru:BAAALgAECgMJBQAAAA==.Moraxes:BAABLgAECn8aAAIgAAgJVxhrAgD2AQAgAAgJVxhrAgD2AQAAAA==.Mordenkainen:BAAALgAECgQJCgAAAA==.Morenor:BAABLgAECn8YAAIhAAYJbwZ3PQAIAQAhAAYJbwZ3PQAIAQAAAA==.Morphidmage:BAABLgAECn8dAAIQAAgJ1guGGwBvAQAQAAgJ1guGGwBvAQAAAA==.Mortetdabo:BAAALgADCgYJBgAAAA==.Motoko:BAAALgADCgcJDAAAAA==.',
Mu='Muaadib:BAAALgADCgcJFAABLgAECgYJEwAMAAAAAA==.',
My='Mydin:BAABLgAECn8cAAIKAAgJkhglDgC5AQAKAAgJkhglDgC5AQAAAA==.Myordarsh:BAABLgAECn8XAAMZAAcJJRDoCgDRAAAPAAcJTQ9zmwBJAQAZAAYJtQnoCgDRAAAAAA==.',
['Mì']='Mìsawa:BAAALgAECgQJCAAAAA==.',
Na='Nael:BAAALgAECgEJAQAAAA==.Naeleen:BAAALgADCgQJBwAAAA==.Nakai:BAAALgADCgkJEgAAAA==.Nasmage:BAAALgADCgkJCgAAAA==.',
Ne='Nelfgonewild:BAAALgAECgIJAgAAAA==.Nexs:BAAALgAECgcJBwAAAA==.Nexxa:BAABLgAECn8WAAINAAcJ7RNSDQCdAQANAAcJ7RNSDQCdAQAAAA==.Neyrina:BAAALgADCgUJCAAAAA==.',
Ni='Nickk:BAAALgADCgMJAwAAAA==.Nightshadow:BAAALgAECgcJDAAAAA==.Niqkle:BAABLgAECn8ZAAMaAAgJmhShLgCoAQAaAAcJ3BKhLgCoAQAiAAIJHgNIlABLAAAAAA==.Nirat:BAAALgADCgEJAQAAAA==.Nishandriel:BAAALgADCgkJDwAAAA==.Nivia:BAAALgAECgMJBQABLgAFFAUJDQAGAJsZAA==.',
No='Nohurtscooby:BAAALgADCgcJCgAAAA==.Normond:BAAALgADCgUJCgAAAA==.Nosiaria:BAAALgAECgEJAQAAAA==.Notadh:BAAALgAECgYJBgAAAA==.Notmeanzy:BAABLgAECn8dAAMhAAgJaB6/AQBcAgAhAAgJaB6/AQBcAgASAAMJQhZXOwDOAAAAAA==.',
Ns='Nstagatr:BAAALgADCgEJAQAAAA==.',
Nu='Numeroun:BAAALgAECgQJBgAAAA==.',
['Né']='Nécrömancer:BAAALgADCgEJAQAAAA==.',
['Nï']='Nïghtknïght:BAAALgAECgIJAgAAAA==.',
Ol='Oleanna:BAABLgAECn8UAAIIAAYJcAzrDgDiAAAIAAYJcAzrDgDiAAABLgAECggJIQAKAHsXAA==.Olehanna:BAABLgAECn8hAAIKAAgJexfbCgDiAQAKAAgJexfbCgDiAQAAAA==.Olestrid:BAAALgADCgkJCQABLgAECggJIQAKAHsXAA==.',
On='Onyxtear:BAAALgADCgYJDAAAAA==.',
Op='Opioid:BAAALgAECgYJDwAAAA==.Opsèc:BAABLgAECn8ZAAICAAYJfxEyLADEAAACAAYJfxEyLADEAAAAAA==.',
Or='Orsa:BAABLgAECn8VAAIaAAcJcxQjMACfAQAaAAcJcxQjMACfAQAAAA==.',
Pe='Pebbles:BAAALgADCgIJAgABLgADCgkJEgAMAAAAAA==.Pedren:BAAALgAECgQJCAAAAA==.Perfectpal:BAABLgAECn8aAAIVAAgJPRWsCgCVAQAVAAgJPRWsCgCVAQAAAA==.Peri:BAAALgADCgUJBQAAAA==.',
Ph='Phaeseus:BAAALgADCggJDwAAAA==.Phexaryl:BAAALgAECgUJBgAAAA==.',
Pl='Planette:BAAALgAECgYJCwAAAA==.',
Po='Poinda:BAAALgADCgIJAgAAAA==.Popcorners:BAABLgAECn8hAAISAAgJ0R1iCAC4AgASAAgJ0R1iCAC4AgAAAA==.Popopanda:BAAALgAECgQJBgAAAA==.Poppnlok:BAAALgADCgEJAQAAAA==.Pordgio:BAABLgAECn8WAAIeAAYJSg+XDAAKAQAeAAYJSg+XDAAKAQAAAA==.Pozzi:BAAALgAECgIJAwAAAA==.',
Pr='Praypal:BAAALgAECgIJAwAAAA==.Problematiç:BAAALgADCgEJAQAAAA==.Proxxy:BAAALgADCgMJAwAAAA==.',
Ps='Psuedolus:BAABLgAECn8XAAIPAAYJ2iJFCwDNAQAPAAYJ2iJFCwDNAQAAAA==.Psålm:BAAALgAECgIJAgAAAA==.',
Pu='Pulshadow:BAACLgAFFH8KAAIhAAQJ7hunAQBgAQAhAAQJ7hunAQBgAQAuAAQKfx8AAiEACAkYJDMFAD4DACEACAkYJDMFAD4DAAAA.Pumah:BAAALgAECgEJAQAAAA==.',
Pw='Pweenqween:BAAALgADCgEJAQAAAA==.',
Py='Pyreska:BAAALgAECgkJBAAAAA==.Pyroklasm:BAABLgAECn8bAAIQAAcJ6RyTUwA9AgAQAAcJ6RyTUwA9AgAAAA==.',
Qt='Qthunter:BAAALgADCgkJCQABLgAECgYJDAAMAAAAAA==.Qtmonk:BAAALgAECgYJDAAAAA==.',
Qu='Quartzecoatl:BAAALgADCgMJAwAAAA==.Quela:BAAALgAECgMJBgAAAA==.Quintcaster:BAAALgADCgkJFAAAAA==.Quirt:BAAALgAECgQJCgAAAA==.',
Ra='Raamen:BAAALgAECgEJAQAAAA==.Rabiéz:BAAALgAECgEJAQAAAA==.Raellia:BAABLgAECn8eAAQTAAgJ2hNpCQCPAAAUAAQJMBHjNQCmAAAjAAIJvRNHBQCVAAATAAMJ2BdpCQCPAAAAAA==.Raimmey:BAAALgAECgIJAgAAAA==.Rajann:BAAALgADCgMJAwAAAA==.Rajia:BAAALgAECgYJDQAAAA==.Rakaw:BAAALgADCgMJAwAAAA==.Ralune:BAAALgAECgcJEQAAAA==.Randomone:BAAALgAECgQJBgAAAA==.Ranes:BAABLgAECn8eAAMeAAgJ1xnjAQAxAgAeAAgJ1xnjAQAxAgAfAAQJuA/IEgDWAAAAAA==.Rathmore:BAAALgAECgQJBQAAAA==.Raylavoidles:BAAALgADCgcJDgAAAA==.Rayllee:BAAALgAECgQJBQAAAA==.',
Re='Redi:BAAALgADCgYJBgAAAA==.Redxelementz:BAABLgAECn8jAAIiAAgJ1yOxAAD0AgAiAAgJ1yOxAAD0AgAAAA==.Relyana:BAAALgADCgEJAQAAAA==.Remena:BAABLgAECn8WAAIIAAcJERzbFwAlAgAIAAcJERzbFwAlAgAAAA==.Renasen:BAAALgAECgcJCQAAAA==.Reno:BAABLgAECn8YAAIVAAcJmBrSAwA9AgAVAAcJmBrSAwA9AgAAAA==.René:BAAALgADCgUJBwAAAA==.Resiretha:BAAALgAECgcJEgAAAA==.Revelynn:BAABLgAECn8eAAICAAgJzR1JBwD/AQACAAgJzR1JBwD/AQAAAA==.',
Rh='Rhico:BAAALgADCgEJAQAAAA==.Rhyin:BAAALgADCgYJBgAAAA==.',
Ri='Riolu:BAAALgAECgQJBAAAAA==.',
Rn='Rngesus:BAAALgADCgUJBQABLgAECggJJQAPAIccAA==.',
Ro='Robotmonk:BAAALgAECgQJBAABLgAECgkJHAALAOcdAA==.Rooxxy:BAAALgAECgYJDAAAAA==.Rotawna:BAAALgADCgkJJQAAAA==.Roxxye:BAAALgADCgEJAQABLgAECgYJDAAMAAAAAA==.',
Ru='Rumms:BAAALgAECgcJCgAAAA==.Rustybottom:BAAALgADCgEJAQAAAA==.Ruumis:BAAALgAECgQJBAAAAA==.',
Ry='Rydric:BAABLgAECn8WAAIQAAgJFCPBEwAxAwAQAAgJFCPBEwAxAwAAAA==.Ryezn:BAAALgADCgEJAQAAAA==.Ryxhal:BAAALgADCgYJBgAAAA==.',
['Rï']='Rïnzlër:BAAALgAECgcJEwAAAA==.',
Sa='Sarac:BAAALgAECgcJDwAAAA==.Saratosh:BAAALgADCgEJAQAAAA==.Savira:BAAALgAECgMJBgAAAA==.',
Sc='Scaleorva:BAAALgAECgYJDwAAAA==.',
Se='Seraphìm:BAABLgAECn8VAAIKAAcJngY4LQDpAAAKAAcJngY4LQDpAAAAAA==.',
Sh='Shadyballs:BAAALgAECgcJEAAAAA==.Shakypete:BAAALgAECgIJAwAAAA==.Shalaena:BAAALgAECgEJAQAAAA==.Shamysosa:BAAALgAECgUJEAABLgAECgYJBgAMAAAAAA==.Shanebentea:BAABLgAECn8UAAIdAAYJfgtrEQAcAQAdAAYJfgtrEQAcAQAAAA==.Sharpy:BAAALgADCgcJBwABLgAECggJGwAQABwZAA==.Sharpyboi:BAAALgADCgMJAwABLgAECggJGwAQABwZAA==.Sharpyy:BAAALgADCgYJBgABLgAECggJGwAQABwZAA==.Shiven:BAAALgADCgkJJAAAAA==.Shmob:BAAALgAECgQJEQAAAA==.Shnappz:BAAALgAECgYJEAAAAA==.Shockittome:BAAALgADCgUJBQAAAA==.Shwillarou:BAABLgAECn8eAAIPAAgJWQcBGABTAQAPAAgJWQcBGABTAQAAAA==.Shwillmoon:BAAALgADCgkJCQAAAA==.Shärpy:BAABLgAECn8bAAIQAAgJHBnlFwCGAQAQAAgJHBnlFwCGAQAAAA==.',
Si='Silverstring:BAAALgAECgMJAwAAAA==.Simmi:BAAALgAECgIJAgAAAA==.Sinergee:BAAALgAECgYJEgAAAA==.Sinnj:BAAALgAECgYJCwAAAA==.',
Sk='Skinney:BAAALgAECgEJAQAAAA==.Skycrush:BAAALgAECgQJBwAAAA==.',
Sl='Slanie:BAAALgAECgYJDwAAAA==.Slingerz:BAABLgAECn8hAAIgAAgJTRcMDwAYAgAgAAgJTRcMDwAYAgAAAA==.Slowmeaux:BAAALgADCgYJCgAAAA==.',
Sm='Smoky:BAABLgAECn8ZAAQUAAgJKyFCOwAfAgAUAAYJEiFCOwAfAgATAAMJPB/ALAALAQAjAAEJAACRIgBnAAAAAA==.',
Sn='Snacky:BAAALgADCgIJAgAAAA==.Sneakpastya:BAABLgAECn8YAAIeAAcJ/AIPDAATAQAeAAcJ/AIPDAATAQAAAA==.Snooksdk:BAAALgADCgEJAQABLgAFFAUJDwAQAE0fAA==.',
So='Solkar:BAAALgAECgYJCgAAAA==.Sollis:BAAALgAECgIJAgAAAA==.Sonastii:BAAALgAECgYJEgAAAA==.Soulbztrd:BAABLgAECn8bAAMTAAgJMRh0GgB5AQATAAUJIRp0GgB5AQAUAAYJ9hTYJQD+AAAAAA==.',
Sp='Spazzchel:BAAALgAECgMJAwAAAA==.Spruce:BAAALgADCgkJCQAAAA==.',
St='Stahlman:BAABLgAECn8eAAIiAAgJEhzaGABQAgAiAAgJEhzaGABQAgAAAA==.Stalpho:BAABLgAECn8ZAAIdAAgJAg81CACdAQAdAAgJAg81CACdAQAAAA==.Starflare:BAAALgADCgcJGAABLgAECgYJEwAMAAAAAA==.Starkind:BAAALgAECgYJEwAAAA==.Stefussy:BAAALgADCgIJAgAAAA==.Stonefist:BAAALgAECgYJBgAAAA==.Stoutmist:BAAALgAECgEJAQAAAA==.Sturr:BAAALgADCgEJAQAAAA==.',
Su='Subza:BAAALgADCgMJAwAAAA==.Sundalo:BAAALgAECgQJBAAAAA==.Superjoyful:BAAALgADCgEJAQAAAA==.Supersweet:BAAALgADCgYJEQAAAA==.Sutterkain:BAAALgAECgIJAgAAAA==.',
Sw='Swagadin:BAABLgAECn8eAAIKAAgJwSRSBwBdAwAKAAgJwSRSBwBdAwAAAA==.Swagika:BAAALgADCgYJBgABLgAECggJHgAKAMEkAA==.',
Sy='Syine:BAAALgADCgUJBQAAAA==.Sylee:BAAALgAFFAEJAQAAAA==.',
Ta='Tabitia:BAABLgAECn8eAAMNAAgJHxP8CQDJAQANAAgJrg/8CQDJAQAkAAYJnhL4FAB4AQAAAA==.Taladari:BAAALgADCgEJAQAAAA==.Taliss:BAAALgAECgQJCwAAAA==.Talonpepper:BAAALgADCgMJAwAAAA==.Tankmedaddy:BAABLgAECn8YAAMHAAYJ7RV5KQBrAQAHAAYJ7RV5KQBrAQAIAAEJawPwhwAoAAAAAA==.Tankopotamus:BAAALgADCgEJAQAAAA==.Tapenga:BAAALgAECgQJBAAAAA==.Tappuccino:BAAALgAECgMJAwAAAA==.Taras:BAACLgAFFH8FAAIdAAMJQhUgEQD+AAAdAAMJQhUgEQD+AAAuAAQKfxwAAh0ACQkGIPUHACsDAB0ACQkGIPUHACsDAAAA.Taraxist:BAABLgAECn8YAAITAAYJ1RY8BAAYAQATAAYJ1RY8BAAYAQAAAA==.Tarcanisdk:BAAALgAECgYJEAAAAA==.Tasuma:BAAALgAECgYJCAAAAA==.Tautology:BAABLgAECn8aAAIhAAgJIBh9GwABAgAhAAgJIBh9GwABAgAAAA==.',
Tc='Tchala:BAABLgAECn8UAAIKAAYJhRmCfACBAQAKAAYJhRmCfACBAQAAAA==.Tchaumb:BAAALgADCgYJBgAAAA==.',
Te='Tedeschi:BAAALgAECgEJAgAAAA==.Teks:BAABLgAECn8YAAIVAAYJcRt1CwCIAQAVAAYJcRt1CwCIAQAAAA==.Tekszen:BAAALgADCgEJAQABLgAECgYJGAAVAHEbAA==.Tencup:BAAALgAECgYJCwAAAA==.Teth:BAAALgAECgYJDwAAAA==.Tetsuyo:BAAALgAECgQJBgAAAA==.',
Th='Thaine:BAABLgAECn8hAAIKAAgJ+iNTCQBHAwAKAAgJ+iNTCQBHAwAAAA==.Theelvira:BAAALgADCgYJBgAAAA==.Theoalthor:BAAALgADCgYJDgAAAA==.Theresis:BAAALgAECgMJBAAAAA==.Therkadin:BAAALgAECgUJDQAAAA==.Theundeadone:BAAALgAECgIJAwAAAA==.Thndrwzrd:BAAALgAECgQJBgAAAA==.Thrust:BAAALgADCgIJAgAAAA==.',
Ti='Ticho:BAABLgAECn8eAAIPAAcJ0AVoJwD1AAAPAAcJ0AVoJwD1AAAAAA==.Tinderella:BAAALgADCgMJAwAAAA==.Tindmina:BAABLgAECn8VAAIVAAYJ7xYXMgC3AQAVAAYJ7xYXMgC3AQAAAA==.Tinglekin:BAAALgAECgEJAQAAAA==.',
Tl='Tlo:BAAALgAECgcJDgAAAA==.Tlol:BAAALgAECgEJAgABLgAECgcJDgAMAAAAAA==.',
To='Toenails:BAAALgADCgUJBQAAAA==.Torkkit:BAAALgADCgYJBgABLgAECgEJAQAMAAAAAA==.Torodisilis:BAAALgAECgIJAgABLgAECgYJFAAKAIUZAA==.Torqit:BAAALgAECgEJAQAAAA==.Totemzrus:BAAALgAECgcJDQAAAA==.',
Tr='Trath:BAAALgADCgMJAwAAAA==.Trent:BAAALgADCgQJCAAAAA==.Trickette:BAAALgAECggJAwAAAA==.Trickeye:BAAALgADCgIJAgAAAA==.',
Tw='Twicks:BAABLgAFFH8FAAIIAAUJkwjlAgB8AQAIAAUJkwjlAgB8AQAAAA==.',
Ud='Udderlyquiff:BAAALgAECgIJAgAAAA==.Udderlyslow:BAABLgAECn8eAAIiAAcJByGhGwA7AgAiAAcJByGhGwA7AgAAAA==.',
Ug='Uglyloser:BAAALgAECgEJAQAAAA==.',
Un='Undeez:BAAALgAECgMJAwAAAA==.Unluckyfrien:BAAALgAECgIJAgAAAA==.',
Va='Vaeshta:BAAALgAECgcJEQAAAA==.Vaku:BAAALgADCgkJDQAAAA==.Valhallarama:BAAALgAECgUJDwAAAA==.Vampy:BAAALgAECgYJCQAAAA==.Varya:BAAALgAECgYJBwAAAA==.Vasuvious:BAABLgAECn8gAAIJAAcJDRyZHgANAgAJAAcJDRyZHgANAgAAAA==.',
Ve='Vesstara:BAAALgADCgUJCwABLgAECgEJAQAMAAAAAA==.',
Vi='Vinago:BAAALgAECgMJAwAAAA==.',
Vo='Voidabyss:BAAALgADCgUJBQAAAA==.Voidixx:BAAALgADCgUJCgAAAA==.Voodoo:BAAALgAECgIJAgAAAA==.',
Vy='Vyleta:BAAALgADCgYJBgAAAA==.Vyllian:BAABLgAECn8lAAMPAAgJhxw6RAAoAgAPAAgJfBc6RAAoAgAZAAcJhw3DBwAaAQAAAA==.',
['Vá']='Váz:BAAALgADCgYJBgABLgAECggJGAABAHIXAA==.',
Wa='Wangwang:BAAALgAECgMJBQAAAA==.Warlakaflaka:BAAALgADCggJFwABLgAECgcJEAAMAAAAAA==.Warlboro:BAACLgAFFH8NAAIUAAUJIg9GFQBDAQAUAAUJIg9GFQBDAQAuAAQKfyMABBQACAlwHBEfAJ0CABQACAlwHBEfAJ0CABMABAnvClo1AOEAACMAAQnBIB4oAFEAAAAA.',
Wh='Whale:BAABLgAECn8ZAAIgAAgJwxY6EQD0AQAgAAgJwxY6EQD0AQAAAA==.Whine:BAAALgAECgIJAgAAAA==.',
Wi='Wicked:BAAALgAECgQJCQAAAA==.Willôw:BAAALgADCgkJDgABLgAECgYJFAAGAAgiAA==.Windwalker:BAAALgAECgcJDwAAAA==.Winkey:BAAALgADCgYJBgAAAA==.Winston:BAAALgADCgEJAgAAAA==.',
Wo='Wolfsong:BAAALgADCgMJBAABLgAECgIJAgAMAAAAAA==.Woosaah:BAAALgAECgYJBgAAAA==.',
Wr='Wreckyou:BAAALgAECgYJEAAAAA==.',
Wt='Wtfimkorgak:BAABLgAECn8VAAIGAAYJgyOXAgBDAgAGAAYJgyOXAgBDAgAAAA==.',
Wy='Wylestrean:BAABLgAECn8YAAMkAAYJohz1DwDDAQAkAAYJVRz1DwDDAQANAAEJeBuyuwBMAAAAAA==.',
Xa='Xandoriel:BAAALgADCgQJBAAAAA==.',
Ye='Yeahigotmilk:BAAALgADCgUJBQAAAA==.Yellowgoblin:BAAALgAECgIJAgAAAA==.',
Yo='Yopali:BAAALgAECgIJAwAAAA==.',
Yu='Yugiohrox:BAABLgAECn8ZAAIZAAgJCB2BCwBbAgAZAAgJCB2BCwBbAgAAAA==.Yujology:BAAALgAECgYJEQAAAA==.',
Ze='Zel:BAAALgAECgQJBgAAAA==.Zentradei:BAAALgAECgMJBQAAAA==.Zephirothh:BAAALgADCgYJDQAAAA==.',
Zi='Zieganfuss:BAABLgAECn8VAAIQAAcJ5R8IVQA5AgAQAAcJ5R8IVQA5AgAAAA==.Zilly:BAAALgAECgEJAQAAAA==.',
Zo='Zoho:BAAALgAECgMJBQAAAA==.Zoomies:BAAALgADCgMJAwAAAA==.',
Zu='Zulkai:BAABLgAECn8YAAIBAAgJaxFLDwBjAQABAAgJaxFLDwBjAQAAAA==.',
['Zá']='Záv:BAABLgAECn8YAAMBAAgJchcvJwAZAgABAAgJchcvJwAZAgAlAAIJMQpYCgB5AAAAAA==.',
['Zä']='Zäne:BAABLgAECn8ZAAIQAAYJHxpSjQC4AQAQAAYJHxpSjQC4AQAAAA==.',
['Çl']='Çlù:BAAALgAECgYJBwAAAA==.',
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

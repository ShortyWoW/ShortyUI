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

local lookup = {'Evoker-Augmentation','Evoker-Devastation','Unknown-Unknown','DeathKnight-Blood','DeathKnight-Unholy','Shaman-Restoration','Hunter-BeastMastery','Hunter-Marksmanship','Warrior-Fury','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','DemonHunter-Vengeance','DemonHunter-Havoc','DemonHunter-Devourer','Priest-Holy','Mage-Frost','Paladin-Retribution','Rogue-Subtlety','Evoker-Preservation','Druid-Guardian','Monk-Brewmaster','Warrior-Arms','Druid-Balance','Shaman-Enhancement','Shaman-Elemental','Warrior-Protection','Druid-Restoration','DeathKnight-Frost','Hunter-Survival','Priest-Shadow','Priest-Discipline','Monk-Windwalker','Paladin-Protection','Monk-Mistweaver','Druid-Feral','Rogue-Outlaw','Rogue-Assassination',}
local provider = {region='US',realm='Dragonmaw',name='US',type='weekly',zone=46,date='2026-05-08',data={Ab='Abbraxys:BAAALgADCgkJDgAAAA==.',
Ad='Adios:BAACLgAFFH8SAAIBAAYJEBwqBwC7AQABAAYJEBwqBwC7AQAuAAQKfxgAAwEACAkPJFIQAHMCAAEACAkPJFIQAHMCAAIABgnDDa4fADABAAAA.',
Ae='Ae:BAAALgAECgUJBgAAAA==.',
Af='Afflict:BAAALgADCgcJEwAAAA==.',
Ag='Agaar:BAAALgAECgUJEAAAAA==.',
Ai='Aidasul:BAAALgAECgUJCQAAAA==.Aimer:BAAALgADCgQJBAABLgAECgYJDgADAAAAAA==.Aireese:BAACLgAFFH8FAAMEAAIJVxbVFwCGAAAFAAIJTAkigQCQAAAEAAIJVxbVFwCGAAAuAAQKfzAAAgQACQmuH/kCALMCAAQACQmuH/kCALMCAAAA.',
Ak='Akaizhar:BAAALgADCgEJAQAAAA==.',
Al='Alareth:BAAALgAECgYJCQAAAA==.Alarin:BAAALgADCgMJAwAAAA==.Alinity:BAAALgAECgUJBwAAAA==.Alnysh:BAAALgADCgUJCQAAAA==.',
Am='Amorilladron:BAABLgAECn8fAAIFAAgJcwXzeADwAAAFAAgJcwXzeADwAAAAAA==.',
An='Anakira:BAAALgADCggJEgAAAA==.Anséis:BAAALgAECgIJAQAAAA==.Anti:BAAALgAECgMJBAAAAA==.Antury:BAABLgAECn8UAAIGAAkJNBMRJgCLAQAGAAkJNBMRJgCLAQAAAA==.',
Aq='Aquamatty:BAAALgADCgEJAQAAAA==.',
Ar='Arcayne:BAAALgAECgMJAwAAAA==.Areeya:BAABLgAECn8bAAMHAAcJcht/HwDfAQAHAAcJcht/HwDfAQAIAAUJPRRASAAzAQAAAA==.Ariamis:BAAALgADCgYJBgAAAA==.Arkatt:BAABLgAECn8uAAIFAAkJqhugDgCNAgAFAAkJqhugDgCNAgAAAA==.Arrowgance:BAAALgAECgUJBgABLgAFFAYJEgABABAcAA==.Artorious:BAAALgADCgUJBQAAAA==.Arulas:BAACLgAFFH8GAAIEAAMJDwhfFQCpAAAEAAMJDwhfFQCpAAAuAAQKfyQAAgQACQnbEAsMALMBAAQACQnbEAsMALMBAAAA.Arx:BAABLgAECn8XAAIJAAcJPyCcHQBhAgAJAAcJPyCcHQBhAgAAAA==.',
As='Ascrod:BAACLgAFFH8LAAMKAAUJsg1xHgAKAQAKAAUJsgtxHgAKAQALAAEJbgu4EwBPAAAuAAQKfxUABAsABwn8GWMVAJ8BAAsABgkAG2MVAJ8BAAoABAlaEyq0APAAAAwAAQnpFYAwAD0AAAEuAAMKBQkFAAMAAAAA.Ashami:BAAALgADCgEJAQABLgAECgcJFQAEAPkQAA==.Ashaxxi:BAAALgAECgMJAwABLgAFFAUJDAANADQGAA==.Ashildr:BAACLgAFFH8MAAINAAUJNAa2AwDGAAANAAUJNAa2AwDGAAAuAAQKfyMABA0ACQnVEhMKAMcBAA0ACQnVEhMKAMcBAA4AAgm8A7JlAE0AAA8AAgkOBSvTAE0AAAAA.Asuwish:BAABLgAECn8kAAIQAAkJHxGYFACzAQAQAAkJHxGYFACzAQAAAA==.',
At='Atcjedi:BAAALgAECgcJEwAAAA==.Atmospherelo:BAAALgAECgYJBgABLgAFFAYJHwARADomAA==.Atmospherew:BAABLgAFFH8HAAIKAAIJ2SEuSgDEAAAKAAIJ2SEuSgDEAAABLgAFFAYJHwARADomAA==.Atmospherez:BAACLgAFFH8fAAIRAAYJOiYWBAAtAgARAAYJOiYWBAAtAgAuAAQKfyUAAhEACQnZJkQAAAkEABEACQnZJkQAAAkEAAAA.',
Au='Audiamer:BAAALgAECgIJAgAAAA==.Auradawn:BAAALgADCgEJAQAAAA==.',
Ax='Axiom:BAAALgAECgEJAQAAAA==.',
Az='Azad:BAAALgADCgQJBAAAAA==.Azardel:BAAALgADCgQJBAAAAA==.Azmodan:BAAALgAECgMJAwAAAA==.',
['Añ']='Añdrew:BAAALgADCgIJAQAAAA==.',
Ba='Baalsdruid:BAAALgAECgcJCQAAAA==.Badgerdar:BAAALgAECggJDwAAAA==.Baep:BAACLgAFFH8MAAISAAQJZx1FCQCNAQASAAQJZx1FCQCNAQAuAAQKfxgAAhIACAl0JUIJAEgDABIACAl0JUIJAEgDAAAA.Baess:BAAALgAECgUJBQABLgAECggJGwATALcVAA==.Bagels:BAAALgAECgcJEQAAAA==.Balance:BAABLgAECn89AAQCAAcJKBryBQB2AQACAAcJKBryBQB2AQABAAYJ4xElIwAsAQAUAAMJwwTDPQB9AAAAAA==.Balooa:BAAALgAECgYJEQAAAA==.Bandrago:BAAALgAECgYJEAAAAA==.Banzan:BAAALgAECgQJBAAAAA==.Barktwain:BAABLgAECn8aAAIVAAgJggviEQDqAAAVAAgJggviEQDqAAABLgAECgUJDAADAAAAAA==.Barracuda:BAAALgAECgQJBAAAAA==.Barrybrown:BAAALgAECgQJBwAAAA==.',
Bd='Bdikd:BAAALgADCgQJBwAAAA==.',
Be='Bearamedic:BAAALgAECgMJAwAAAA==.Beeaarr:BAABLgAECn8XAAISAAcJAhVUiABqAQASAAcJAhVUiABqAQAAAA==.Beercules:BAABLgAECn8sAAIWAAkJvBg+DAD+AQAWAAkJvBg+DAD+AQAAAA==.Belagore:BAABLgAECn8kAAMJAAkJ7Bw/CgBDAgAJAAgJTB4/CgBDAgAXAAMJShhCGQDrAAAAAA==.Belegmor:BAAALgADCgEJAgAAAA==.Bellasnow:BAAALgAECgUJBgAAAA==.Benfrank:BAABLgAECn8hAAMYAAkJzhTdHwAAAgAYAAgJXxbdHwAAAgAVAAMJkA0JGQCWAAAAAA==.Benkkei:BAABLgAECn8tAAMJAAgJzyAWBQCoAgAJAAgJzyAWBQCoAgAXAAYJ4hXfEQCDAQAAAA==.Bethan:BAABLgAECn8VAAIRAAYJzQQSnADaAAARAAYJzQQSnADaAAAAAA==.',
Bf='Bfillz:BAABLgAECn8XAAIPAAcJmRQ8aQBnAQAPAAcJmRQ8aQBnAQAAAA==.',
Bi='Bibi:BAAALgAECgYJDgAAAA==.Bigantall:BAAALgAECgQJBQAAAA==.Bigmedic:BAAALgAECgcJDwABLgAFFAQJCQAZAAQcAA==.Bigtea:BAAALgAECgQJCQAAAA==.Biishess:BAAALgAECgkJBAAAAA==.Bitta:BAAALgAECgcJCAAAAA==.',
Bl='Blaart:BAABLgAECn8VAAMKAAgJpRKAVAAuAQAKAAYJqBCAVAAuAQALAAMJnBdyFwCPAAAAAA==.Blacksheep:BAAALgAECgEJAgAAAA==.Blanka:BAACLgAFFH8JAAIZAAQJBBylAQB3AQAZAAQJBBylAQB3AQAuAAQKfx0AAxkACQkZGYQCAIACABkACQkZGYQCAIACAAYAAQmWASKqACMAAAAA.Blastphemous:BAAALgADCgYJBgAAAA==.Blax:BAAALgAECgcJBgAAAA==.Blindhugs:BAAALgADCgEJAQABLgAECgEJAQADAAAAAA==.Bluexecute:BAAALgAECggJEwAAAA==.Blumez:BAAALgAECgcJDgAAAA==.Blùey:BAAALgADCgMJAwAAAA==.',
Bo='Bob:BAAALgADCgcJBwABLgAECggJHAAKANYZAA==.Bodytypebig:BAABLgAECn8oAAIVAAgJ3hpJBQAMAgAVAAgJ3hpJBQAMAgAAAA==.Boeuf:BAAALgAECgkJDwABLgAFFAIJBAADAAAAAA==.Boicrystian:BAABLgAECn8UAAIYAAcJjwuTIgAkAQAYAAcJjwuTIgAkAQAAAA==.Bolillo:BAAALgAECgEJAQAAAA==.Bookitty:BAAALgAECgQJBQAAAA==.Bord:BAAALgADCgYJBgAAAA==.Bossed:BAAALgAFFAIJAgAAAA==.Bossladìe:BAAALgAECggJDAAAAA==.Boston:BAAALgAECgEJAgAAAA==.',
Br='Breezy:BAAALgAECgEJAQAAAA==.Brennly:BAAALgAECgYJBgAAAA==.Brewbies:BAAALgADCggJCgABLgAECgYJDgADAAAAAA==.Brewness:BAAALgAECgcJEQABLgAECggJEwADAAAAAA==.Brommix:BAAALgAECgUJCwAAAA==.Brown:BAABLgAECn8WAAIRAAcJ6hFIbgA0AQARAAcJ6hFIbgA0AQAAAA==.Broxy:BAAALgAECgEJAgAAAA==.',
Bu='Bucci:BAAALgADCgIJAwAAAA==.Buhbles:BAACLgAFFH8GAAIYAAYJchfiAwCxAQAYAAYJchfiAwCxAQAuAAQKfyEAAhgABwnXI5cLABACABgABwnXI5cLABACAAAA.Buhflobill:BAAALgADCgcJCgAAAA==.Bullshiitake:BAAALgAECgUJCgAAAA==.Burberry:BAAALgAECgEJAQAAAA==.',
Ca='Cae:BAABLgAECn8WAAIPAAgJiBlRNABkAQAPAAgJiBlRNABkAQAAAA==.Calaglin:BAABLgAECn8XAAMKAAgJQRrjSwDlAQAKAAcJIx3jSwDlAQALAAIJ9AiJSwCLAAAAAA==.Calastiria:BAAALgADCgcJDAAAAA==.Caleb:BAAALgADCgYJBgABLgAECgYJCAADAAAAAA==.Camdragon:BAAALgADCgEJAQABLgAECgQJCAADAAAAAA==.Cassylan:BAAALgADCgEJAQAAAA==.Catdancingif:BAAALgAFFAMJAwABLgAFFAYJFQAPABUgAA==.Cavaloris:BAABLgAECn8UAAIaAAcJvwUzSwAbAQAaAAcJvwUzSwAbAQAAAA==.',
Ce='Cealena:BAAALgAECgQJBAAAAA==.Celesti:BAABLgAECn8fAAISAAcJ+hUURQB2AQASAAcJ+hUURQB2AQAAAA==.Cellia:BAABLgAECn8cAAISAAgJpx1KEwBgAgASAAgJpx1KEwBgAgAAAA==.Cevy:BAACLgAFFH8LAAIWAAQJhyKoBgCPAQAWAAQJhyKoBgCPAQAuAAQKfxcAAhYACQlAJC0FADYDABYACQlAJC0FADYDAAAA.',
Ch='Chekz:BAAALgADCgUJBQAAAA==.Chickenjoy:BAAALgADCgcJBwAAAA==.Chickensalad:BAAALgAECgIJAgABLgAECgYJCgADAAAAAA==.Chilæ:BAAALgAECgcJDAABLgAECggJHwARAFIXAA==.Chirhoxp:BAACLgAFFH8IAAIbAAMJtQXMEQCgAAAbAAMJtQXMEQCgAAAuAAQKfyoAAxsACQkqENcKAL4BABsACQkqENcKAL4BAAkAAgmfCi6XAGQAAAAA.Chocomousse:BAAALgADCgkJFAAAAA==.Chop:BAAALgAECgQJBAAAAA==.Christi:BAAALgAECgMJBAABLgAFFAQJDgAcABgTAA==.Chubbstone:BAAALgADCgIJAgAAAA==.Chuckkyd:BAABLgAECn8jAAISAAgJAh9uEQBvAgASAAgJAh9uEQBvAgAAAA==.Chîll:BAAALgAECgcJAwAAAA==.',
Ci='Cileo:BAAALgADCgYJCQAAAA==.',
Cl='Clanka:BAAALgAECgQJBQAAAA==.Cleb:BAAALgAECgYJCAAAAA==.Clocker:BAABLgAECn8dAAIGAAgJVBpMHQAwAgAGAAgJVBpMHQAwAgAAAA==.Clumbsykoala:BAAALgAECgUJBwAAAA==.Clâyface:BAABLgAECn8eAAIYAAcJeQ1eIwAeAQAYAAcJeQ1eIwAeAQAAAA==.',
Co='Coasta:BAAALgAECgMJCAAAAA==.Coldlunch:BAAALgAECgIJAwAAAA==.Colton:BAABLgAFFH8FAAIUAAEJKgbQFgBKAAAUAAEJKgbQFgBKAAAAAA==.Combatcow:BAACLgAFFH8LAAIJAAQJxBmyBwBkAQAJAAQJxBmyBwBkAQAuAAQKfyQAAgkACAmqIUALAAEDAAkACAmqIUALAAEDAAAA.Cozmic:BAABLgAECn8rAAIRAAgJjyMjCgDVAgARAAgJjyMjCgDVAgAAAA==.',
Cq='Cq:BAAALgADCggJCAAAAA==.',
Cr='Crackseed:BAABLgAECn8WAAIcAAcJIB+PEABPAgAcAAcJIB+PEABPAgAAAA==.Craftymidget:BAABLgAECn8pAAIIAAkJqA/dBADlAQAIAAkJqA/dBADlAQAAAA==.Crit:BAAALgAECgUJCwABLgAFFAQJDwAFAEwhAA==.',
Ct='Ctn:BAAALgAECgMJBgAAAA==.',
Cu='Curandero:BAAALgAECgQJCgAAAA==.Curie:BAABLgAECn8fAAIRAAgJUheIVABuAQARAAgJUheIVABuAQAAAA==.',
Cy='Cyclohexyll:BAAALgAECgEJAgAAAA==.',
Da='Dalynar:BAAALgADCgEJAQAAAA==.Dameck:BAABLgAECn8wAAMXAAkJ1B3nAQC+AgAXAAkJNRznAQC+AgAJAAcJ5heaQgCaAQAAAA==.Dampo:BAAALgADCgYJDAAAAA==.Danakira:BAAALgADCgMJBgAAAA==.Dancemonkey:BAAALgAECgUJCQAAAA==.Daralock:BAABLgAECn8fAAMKAAgJVBswTwDaAQAKAAYJghswTwDaAQALAAQJGRGHMwDpAAAAAA==.Darigaaz:BAAALgADCgUJBQAAAA==.Darkburley:BAAALgAECgUJBwAAAA==.Darkcastle:BAAALgADCgYJCQAAAA==.Darkholy:BAAALgADCgYJDwAAAA==.Darosh:BAAALgAECgIJAgABLgAECggJHgAdAG8aAA==.Das:BAABLgAECn8hAAIPAAkJqiD+BQDLAgAPAAkJqiD+BQDLAgAAAA==.Dawnbringer:BAAALgADCgEJAQAAAA==.Dayxxday:BAAALgAECgQJBgAAAA==.Dazzeler:BAABLgAECn8eAAMdAAgJbxr+AwC9AQAdAAcJexj+AwC9AQAFAAcJiBgMOACZAQAAAA==.',
De='Deathdisiple:BAAALgAECgcJCgAAAA==.Deathlysue:BAAALgAECgIJAgAAAA==.Deathpetals:BAACLgAFFH8XAAIFAAcJ3CHgBQDqAQAFAAcJ3CHgBQDqAQAuAAQKfyYAAgUACQkqJo4AAOoDAAUACQkqJo4AAOoDAAAA.Decepciona:BAABLgAECn8iAAQKAAcJ5iGCIwDeAQAKAAUJeiGCIwDeAQALAAMJaiAGLAAPAQAMAAEJAAAiIwBlAAAAAA==.Deecaye:BAAALgAECgEJAQAAAA==.Deejaypaulyd:BAABLgAECn8XAAIeAAYJxhQ4EwCPAQAeAAYJxhQ4EwCPAQAAAA==.Delver:BAAALgADCgIJAgAAAA==.Demongirly:BAAALgADCgcJBwAAAA==.Derailed:BAAALgAECgUJBQAAAA==.Desp:BAAALgAECgMJAgABLgAFFAcJFgAfALoVAA==.Despir:BAACLgAFFH8WAAMfAAcJuhXcBwBKAQAfAAYJTBTcBwBKAQAQAAMJUgnHBwDuAAAuAAQKfx0ABBAACAm9Ha4KAKICABAACAm9Ha4KAKICAB8ABglbJEEfAN4BACAAAgnVAhFQAE4AAAAA.Destantokill:BAAALgAECgMJAwAAAA==.Destro:BAAALgADCgUJBQAAAA==.Devilpoing:BAAALgAECgcJDQAAAA==.Devounor:BAAALgAECgYJCgAAAA==.',
Di='Ding:BAAALgADCgIJAgAAAA==.',
Do='Donnamatrix:BAAALgAECgIJAgAAAA==.Dorado:BAAALgADCgIJBAAAAA==.Doucheknight:BAAALgADCgMJBgAAAA==.',
Dr='Dracarizz:BAAALgADCgQJBAAAAA==.Draconius:BAAALgAECgEJAQAAAA==.Draenor:BAAALgADCgcJDQAAAA==.Dragnspittle:BAABLgAECn8rAAQBAAkJoRylBACuAgABAAkJoRylBACuAgAUAAkJOBkEAwCtAgACAAMJdBM0DQC9AAAAAA==.Dragonforce:BAABLgAECn8iAAICAAcJvxb9BACZAQACAAcJvxb9BACZAQAAAA==.Dragonskull:BAAALgAECgYJEAAAAA==.Dragonturd:BAABLgAECn8dAAISAAkJFBRiGQAxAgASAAkJFBRiGQAxAgAAAA==.Drazentar:BAAALgAECgYJEwAAAA==.Dreadnoughty:BAAALgADCgQJBAAAAA==.Dream:BAAALgADCgUJBQABLgAECgEJAQADAAAAAA==.Dregore:BAABLgAECn8YAAIBAAcJDxKlGgBpAQABAAcJDxKlGgBpAQABLgAECgkJJAAJAOwcAA==.Drethor:BAAALgADCgIJAgABLgAECggJJAAFAOkfAA==.Drevox:BAABLgAECn8kAAIFAAgJ6R+MGAA5AgAFAAgJ6R+MGAA5AgAAAA==.Druidheals:BAAALgAECgMJBAAAAA==.',
Du='Dulgar:BAACLgAFFH8FAAIGAAIJ9xPyLACXAAAGAAIJ9xPyLACXAAAuAAQKfzAAAgYACQl9HZcFAN8CAAYACQl9HZcFAN8CAAAA.Dummythick:BAAALgAECgEJAQAAAA==.Dunsmuir:BAABLgAECn8vAAIHAAcJqx6xGgD+AQAHAAcJqx6xGgD+AQAAAA==.Dux:BAABLgAECn8OAAIPAAkJVB7wQwDkAQAPAAkJVB7wQwDkAQAAAA==.',
['Dé']='Dévé:BAAALgADCgkJEAAAAA==.',
Ea='Eamonn:BAAALgADCgYJBgABLgAECgEJAwADAAAAAA==.',
El='Elephant:BAAALgAECgEJAQAAAA==.Elhokar:BAAALgAECgcJCAAAAA==.Elleduff:BAABLgAECn8XAAIhAAcJHw99HAA/AQAhAAcJHw99HAA/AQAAAA==.Eloragon:BAAALgADCgcJDAAAAA==.Elspeth:BAAALgAECgUJCAAAAA==.Elviusel:BAAALgADCgMJAwAAAA==.Elydra:BAAALgAECgQJBQAAAA==.Elyssabeta:BAAALgAECgEJAgAAAA==.Elysstaa:BAABLgAECn8qAAMQAAkJNBwBBADeAgAQAAkJNBwBBADeAgAfAAQJzgtNSQC5AAAAAA==.',
En='Energizér:BAAALgAECgIJBAAAAA==.',
Eq='Equilibria:BAAALgAECgUJCgAAAA==.',
Es='Esris:BAAALgAECggJKgAAAQ==.',
Et='Etík:BAAALgAECgQJBgAAAA==.',
Ev='Evomengol:BAAALgADCgUJBwABLgAFFAMJCgAYAH4RAA==.',
Ex='Exaltso:BAAALgADCgkJCQAAAA==.Exorcist:BAAALgAECgEJAQAAAA==.',
Ey='Eyebright:BAAALgAECgMJAwAAAA==.Eyye:BAAALgADCgYJBgABLgAECgcJAQADAAAAAA==.',
Fa='Falcyn:BAABLgAECn8lAAISAAcJzw5OVQBIAQASAAcJzw5OVQBIAQAAAA==.Faminex:BAACLgAFFH8UAAMaAAgJOSBEAADFAgAaAAgJOSBEAADFAgAZAAEJAAAhCgAAAAAuAAQKfxsAAxoACAn/H0EJAP4CABoACAn/H0EJAP4CABkABAmWHhIcAAoBAAAA.Famr:BAAALgADCgEJAQABLgAFFAgJFAAaADkgAA==.Farns:BAACLgAFFH8UAAIRAAYJ/yJ+BQAOAgARAAYJ/yJ+BQAOAgAuAAQKfxgAAhEACAnnJTksAMICABEACAnnJTksAMICAAAA.',
Fe='Feiyue:BAABLgAECn8YAAMKAAcJwhErWAC/AQAKAAcJwhErWAC/AQAMAAEJ6g0cMAA+AAAAAA==.Felinepriest:BAAALgAECgYJCAAAAA==.Felsdh:BAAALgAECgUJCgAAAA==.Felsoaked:BAAALgAECgQJCAAAAA==.Feltotes:BAAALgADCgcJDgAAAA==.Felucia:BAAALgAECgYJCgAAAA==.Fenryr:BAAALgAECggJEwAAAA==.Feyvorian:BAAALgADCgMJAwAAAA==.',
Fi='Fingerbone:BAAALgADCgkJEgAAAA==.Firebäne:BAABLgAECn8dAAILAAkJfCA7AQCCAgALAAkJfCA7AQCCAgAAAA==.Firecreep:BAAALgAECgcJDAAAAA==.Fistweave:BAAALgAECgMJAwAAAA==.Fiññ:BAAALgAECgEJAQAAAA==.',
Fl='Flaminghawk:BAACLgAFFH8PAAIRAAYJ8hR5GAB+AQARAAYJ8hR5GAB+AQAuAAQKfygAAhEACAmYIY0oANACABEACAmYIY0oANACAAAA.Flokkii:BAAALgAECgQJBwAAAA==.Floofie:BAAALgAECgEJAQAAAA==.Floofyfire:BAAALgAECgEJAQAAAA==.',
Fm='Fmnx:BAAALgADCgMJAwABLgAFFAgJFAAaADkgAA==.',
Fo='Foxmonk:BAAALgADCgYJBgAAAA==.',
Fr='Frankazoid:BAABLgAECn8WAAIFAAcJ2RboUgBEAQAFAAcJ2RboUgBEAQAAAA==.Frankdatank:BAAALgADCgcJBwABLgAECggJFgAFANkWAA==.Freightfrayn:BAACLgAFFH8GAAIGAAMJgQ/iJADBAAAGAAMJgQ/iJADBAAAuAAQKfywAAgYACQkvHPQGAAQDAAYACQkvHPQGAAQDAAAA.Freyin:BAABLgAECn8VAAIHAAcJGgymUQAZAQAHAAcJGgymUQAZAQAAAA==.Frolgar:BAAALgAECgIJAgAAAA==.Frostytotems:BAAALgADCgcJBgAAAA==.',
Fu='Fulldracarys:BAACLgAFFH8VAAIUAAYJvxtbAgD+AQAUAAYJvxtbAgD+AQAuAAQKfx8AAhQACAlyJZgCAEUDABQACAlyJZgCAEUDAAEuAAUUCAkVABwAVxMA.Fullgabagool:BAACLgAFFH8IAAIgAAQJrRdrEABFAQAgAAQJrRdrEABFAQAuAAQKfxYAAiAABwnrH/MGAH4CACAABwnrH/MGAH4CAAEuAAUUCAkVABwAVxMA.Fullmist:BAAALgAECgcJBgABLgAFFAgJFQAcAFcTAA==.Fulltranq:BAACLgAFFH8VAAIcAAgJVxMCAQCWAgAcAAgJVxMCAQCWAgAuAAQKfxgAAhwABwnmIvshADYCABwABwnmIvshADYCAAAA.',
Fw='Fwaffy:BAAALgAFFAMJBAAAAA==.',
['Fë']='Fëanor:BAAALgAECgQJBAAAAA==.',
['Fø']='Føxz:BAABLgAECn8UAAIWAAgJHBwSFgBZAgAWAAgJHBwSFgBZAgAAAA==.Føxzxv:BAAALgAECggJDAAAAA==.',
Ga='Gamesucks:BAAALgAECgEJAgAAAA==.Ganster:BAAALgAECgEJAgAAAA==.Gaya:BAAALgADCgcJFwAAAA==.',
Ge='Gee:BAAALgADCgEJAgAAAA==.Geltheros:BAAALgADCggJCAAAAA==.Getzapped:BAAALgAECgQJBQAAAA==.',
Gf='Gfoo:BAACLgAFFH8HAAIhAAQJCA+ZCQA1AQAhAAQJCA+ZCQA1AQAuAAQKfxQAAiEABgnQGOEnAJoBACEABgnQGOEnAJoBAAAA.',
Gh='Ghidorah:BAAALgAECgMJBAAAAA==.',
Gi='Gigabloke:BAAALgADCgUJBQAAAA==.Gigastar:BAAALgAECgYJBgAAAA==.',
Gl='Glacia:BAAALgADCgUJBQAAAA==.Glaticus:BAAALgAECgEJAQAAAA==.Glimpse:BAAALgAECggJEQAAAA==.Glizzgobbler:BAAALgAECgQJAwAAAA==.',
Go='Gokêe:BAAALgAECgcJDgABLgAECgcJFQAEAEMcAA==.Golddigger:BAAALgAECgYJEgAAAA==.Golok:BAAALgAECgEJAwABLgAECgYJBgADAAAAAA==.Goof:BAABLgAECn8UAAIFAAYJkh9+LwC7AQAFAAYJkh9+LwC7AQAAAA==.Gout:BAAALgADCgEJAQAAAA==.Goyuri:BAAALgAECgYJCwAAAA==.',
Gr='Greenmonsta:BAAALgAECgcJDwAAAA==.Grimknight:BAAALgAECggJEwAAAA==.Groovi:BAAALgAECgIJAgAAAA==.Grubergeiger:BAAALgAECgUJCAABLgAFFAIJBAADAAAAAA==.Gruunele:BAABLgAECn8jAAIZAAgJEh1wAwBPAgAZAAgJEh1wAwBPAgAAAA==.Grü:BAAALgADCgkJCQABLgAFFAIJBAADAAAAAA==.',
Gu='Gutrigor:BAAALgAECgYJDQAAAA==.',
Gw='Gwår:BAAALgAECgYJCAAAAA==.',
['Gó']='Gókee:BAABLgAECn8VAAMEAAcJQxwBDQCiAQAEAAcJQxwBDQCiAQAFAAEJKgX7MAEnAAAAAA==.',
Ha='Habebe:BAAALgAFFAEJAQAAAA==.Hair:BAAALgADCgYJBgAAAA==.Hardknockz:BAAALgAECgYJCgABLgAECggJHwAPAHIcAA==.Hashbrowns:BAABLgAECn8oAAISAAkJuSG8BAAFAwASAAkJuSG8BAAFAwAAAA==.Hav:BAEBLgAECn8qAAIRAAkJaSJrCQDeAgARAAkJaSJrCQDeAgAAAA==.Havaker:BAEALgAECgYJCgABLgAECgkJKgARAGkiAA==.Haxxorwyn:BAAALgAECgYJCQAAAA==.',
He='Healzyew:BAAALgADCggJCAAAAA==.Heartlust:BAABLgAECn8YAAIRAAcJ0RgocgDvAQARAAcJ0RgocgDvAQAAAA==.Hefemusprime:BAAALgADCgcJBwAAAA==.Hellscolon:BAABLgAECn8hAAIKAAkJmwp9OACEAQAKAAkJmwp9OACEAQAAAA==.Hema:BAAALgAECgMJBAABLgAFFAMJBQAFAMwRAA==.Herakless:BAAALgAECggJDgAAAA==.',
Hi='Highrider:BAAALgADCggJDQAAAA==.Hillybaba:BAAALgADCgcJBwAAAA==.Hitagi:BAAALgAECgYJDQAAAA==.',
Ho='Hoa:BAAALgAECgQJBgAAAA==.Holi:BAAALgAECgEJAgAAAA==.Holicow:BAABLgAFFH8HAAISAAQJnh/XJAAZAQASAAQJnh/XJAAZAQAAAA==.Holii:BAAALgAECgIJAwAAAA==.Holybagels:BAAALgAECgYJBgAAAA==.Holyblasts:BAAALgAECgYJDAAAAA==.Holyblowèr:BAABLgAECn8fAAISAAgJrCLhDQCQAgASAAgJrCLhDQCQAgAAAA==.Holydicsadin:BAAALgAECgQJBAAAAA==.Holydisciple:BAAALgADCgEJAQAAAA==.Holynikki:BAABLgAECn8aAAIiAAYJjwU5HwCbAAAiAAYJjwU5HwCbAAAAAA==.Holytalon:BAAALgADCgQJBQAAAA==.',
Hu='Hummingbird:BAABLgAECn8UAAIjAAgJRB8rDQAXAgAjAAgJRB8rDQAXAgABLgAECgcJIgAKAOYhAA==.Hungus:BAABLgAECn8bAAIOAAgJjRp/CQD1AQAOAAgJjRp/CQD1AQAAAA==.Huraacan:BAAALgAECgYJBwABLgAECggJFAAKAPISAA==.Hurtszick:BAAALgADCgEJAgAAAA==.',
Hy='Hybryddin:BAAALgADCgcJBwAAAA==.Hydrotiger:BAAALgAECgQJCQAAAA==.',
['Hà']='Hàra:BAAALgADCgUJCQAAAA==.',
Ia='Iamazombie:BAAALgADCgIJAgAAAA==.Iamholyman:BAAALgADCgYJBgAAAA==.',
Ig='Iggle:BAAALgADCgYJDAAAAA==.Igotchubruh:BAAALgAECgIJAgAAAA==.',
Ik='Ikitty:BAAALgAECgIJAgAAAA==.',
Il='Ilovemymommy:BAAALgAECggJDgAAAA==.',
Im='Imaru:BAAALgADCgYJBgAAAA==.Imnotthtgood:BAAALgADCgkJIwAAAA==.Impact:BAAALgAECgIJAgABLgAECgcJPQACACgaAA==.Implosion:BAABLgAECn8wAAIKAAkJWxbEFAA7AgAKAAkJWxbEFAA7AgAAAA==.',
In='Indigolemon:BAABLgAECn8aAAQVAAgJQBreBQB2AgAVAAgJQBreBQB2AgAkAAUJyBYkFgBXAQAYAAEJDhwmdQBOAAAAAA==.Inkconjurer:BAABLgAECn8eAAIRAAgJKh41JgALAgARAAgJKh41JgALAgAAAA==.Inkdrinker:BAAALgAECgEJAQABLgAECggJHgARACoeAA==.Inouskee:BAAALgADCgUJBQAAAA==.',
Io='Iowned:BAABLgAECn8cAAIiAAgJbRHBDQBdAQAiAAgJbRHBDQBdAQAAAA==.',
Ir='Irraelina:BAAALgADCgIJAgABLgAFFAQJDQAJAA0WAA==.',
Is='Ishundo:BAABLgAECn8fAAIhAAcJVhgvEAC6AQAhAAcJVhgvEAC6AQAAAA==.Isplash:BAAALgAECgEJAQAAAA==.',
Iz='Izalithx:BAACLgAFFH8MAAMKAAYJFxzOAQAgAgAKAAYJ6xrOAQAgAgALAAIJKhpuCwCvAAAuAAQKfxgAAwoACAkUIQsqAGgCAAoABwkUIQsqAGgCAAsAAwmHFoMvAP0AAAEuAAUUCAkUABoAOSAA.',
Ja='Jakku:BAABLgAECn8WAAIRAAcJBgy6swB3AQARAAcJBgy6swB3AQAAAA==.Jamie:BAABLgAECn8ZAAMiAAgJBwyOHwALAQAiAAcJ/AqOHwALAQASAAIJjQ9IvwB2AAAAAA==.Jastiri:BAAALgADCgIJAgAAAA==.',
Je='Jelly:BAABLgAECn8UAAIRAAcJPh2iVgA1AgARAAcJPh2iVgA1AgAAAA==.Jezz:BAAALgADCgEJAQAAAA==.',
Ji='Jiinrop:BAEBLgAECn8WAAMLAAcJIxQaIABSAQAKAAYJuRIebwCCAQALAAYJXxAaIABSAQAAAA==.Jinah:BAAALgADCgQJBAAAAA==.',
Jo='Johnassassin:BAAALgAECgYJCgABLgAECggJLwAkAAMcAA==.Jollyollie:BAAALgAECgYJCQAAAA==.Jonahkin:BAABLgAECn8YAAIYAAgJWBv2GwAiAgAYAAgJWBv2GwAiAgAAAA==.',
Ju='Judgewapner:BAAALgAECgEJAQAAAA==.Juicelord:BAAALgAECgMJBQAAAA==.Juiya:BAAALgADCgQJBAAAAA==.Juuice:BAAALgAECgEJAQAAAA==.',
Ka='Kaedes:BAACLgAFFH8KAAMYAAMJfhEYGADmAAAYAAMJfhEYGADmAAAkAAEJ6Q2oCQBYAAAuAAQKfy4ABRgACAl2IrsFAIoCABgACAkGIrsFAIoCACQABgmkGewSAIABABwAAgknGSliAJgAABUAAQkIFW0tAEEAAAAA.Kailyn:BAAALgAECgEJAgAAAA==.Kaiwai:BAAALgADCgYJBgAAAA==.Kaizoku:BAAALgADCgQJBAAAAA==.Kaladin:BAAALgAECgQJBQAAAA==.Kaldanarys:BAAALgAECgEJAQAAAA==.Kalenlock:BAAALgAECgYJCgAAAA==.Kaleo:BAAALgAECgIJAgABLgAECgcJEAADAAAAAA==.Kaorii:BAAALgAECgEJAQAAAA==.Karsus:BAAALgAECgIJAgAAAA==.Katherrian:BAAALgADCgcJBwABLgAECgkJLgAHAG8fAA==.Kathorall:BAABLgAECn8jAAIHAAkJ3xMjGQAIAgAHAAkJ3xMjGQAIAgAAAA==.Kavawings:BAAALgAFFAEJAQAAAA==.Kawaiihealer:BAABLgAECn8hAAIQAAgJZB4XEADqAQAQAAgJZB4XEADqAQAAAA==.',
Ke='Keddy:BAAALgADCgMJCQAAAA==.Kemper:BAABLgAECn8YAAMeAAcJ1xJLEACmAQAeAAcJ1xJLEACmAQAHAAEJFxDUrQBBAAAAAA==.Keoua:BAAALgADCgIJAgAAAA==.Kerrs:BAAALgAECgEJAQAAAA==.Kerrz:BAAALgAECgEJAgAAAA==.',
Kh='Khaza:BAAALgADCgMJBgAAAA==.',
Ki='Kidil:BAAALgAECgEJAQAAAA==.Kidneypopper:BAAALgAECgYJEAABLgAECggJKwARAI8jAA==.Kievit:BAABLgAECn8ZAAIMAAkJ/wthBACbAQAMAAkJ/wthBACbAQAAAA==.Killá:BAAALgADCgMJAwAAAA==.Kir:BAABLgAECn8eAAMPAAYJRRzpOgBLAQAOAAUJyR2SJQCSAQAPAAYJkRXpOgBLAQAAAA==.',
Kk='Kkonetica:BAAALgADCgUJBQABLgAECgkJJgAlANcXAA==.Kkrantuq:BAABLgAECn8mAAIlAAkJ1xdzAwDKAQAlAAkJ1xdzAwDKAQAAAA==.',
Kl='Klarityqt:BAAALgAECgQJBgAAAA==.Klarityx:BAABLgAECn8hAAIRAAkJ9RRwPQCCAgARAAkJ9RRwPQCCAgAAAA==.',
Ko='Kogadeath:BAAALgAECgEJAQAAAA==.Kogadraco:BAAALgAECggJDgAAAA==.Komatos:BAACLgAFFH8LAAIaAAQJfiTLBACqAQAaAAQJfiTLBACqAQAuAAQKfzAAAhoACAnOJToCAAcDABoACAnOJToCAAcDAAAA.Korona:BAABLgAECn8wAAIRAAkJ9hfCGABXAgARAAkJ9hfCGABXAgAAAA==.Korra:BAAALgADCgYJCgAAAA==.',
Kr='Kraptastic:BAAALgADCgEJAQAAAA==.',
Ky='Kylar:BAAALgAECgYJCwABLgAECgkJJgAlANcXAA==.',
['Kê']='Kênsêi:BAAALgAECgYJDAABLgAECgkJIAAaACcSAA==.',
['Kô']='Kôan:BAAALgADCgkJEQAAAA==.',
La='Laserbeams:BAAALgAECgYJDQAAAA==.',
Le='Leafyjoe:BAAALgAECgcJCAAAAA==.Lechencaja:BAAALgAECgQJBQAAAA==.Legendarybob:BAAALgAECgMJAwAAAA==.Legomyeggö:BAABLgAECn8cAAIFAAcJsRsGVAD1AQAFAAcJsRsGVAD1AQAAAA==.',
Lh='Lhera:BAABLgAECn8rAAQeAAkJCRwcBACIAgAeAAkJlxkcBACIAgAHAAcJzRrTMwDgAQAIAAcJDRcwCACAAQAAAA==.',
Li='Lilglittery:BAAALgADCgYJBgAAAA==.Lilnikki:BAAALgADCgUJCgAAAA==.Lilypotter:BAAALgAECgIJAwAAAA==.Lisp:BAAALgADCgYJBgAAAA==.Livathian:BAABLgAECn8dAAISAAgJTxQsMQC4AQASAAgJTxQsMQC4AQAAAA==.',
Lo='Lockingdown:BAAALgADCgYJCAAAAA==.Longshotx:BAAALgADCgYJBgAAAA==.Lothuial:BAAALgADCgEJAgAAAA==.',
Lu='Lucellis:BAAALgAECgcJBwAAAA==.Lumira:BAABLgAECn8tAAIHAAkJJR2ECQCdAgAHAAkJJR2ECQCdAgAAAA==.Lunavel:BAAALgADCgEJAgAAAA==.Lurex:BAAALgADCgEJAgAAAA==.Luzwarlockok:BAAALgAECgcJCAAAAA==.',
Lz='Lzybys:BAAALgADCgYJBgAAAA==.',
Ma='Madris:BAABLgAECn8cAAMgAAcJnhknDQD/AQAgAAcJnhknDQD/AQAfAAcJQQ35HQBMAQAAAA==.Maelstroke:BAAALgADCgcJBwAAAA==.Magimagi:BAAALgAECgYJCQAAAA==.Magtharn:BAAALgAECgUJBwABLgAECgcJBwADAAAAAA==.Magusdark:BAAALgAECgYJBwAAAA==.Makkascholar:BAAALgAECgIJAgAAAA==.Makotoh:BAAALgADCgEJAQAAAA==.Malnorr:BAABLgAECn8WAAMKAAgJaxnBWgAeAQAKAAcJaxnBWgAeAQALAAEJAACJaQA/AAAAAA==.Manbeerpig:BAAALgAECgYJCgABLgAFFAIJBAADAAAAAA==.Mandykiinz:BAAALgAECgYJEgAAAA==.Mannimarco:BAAALgADCgEJAQAAAA==.Marcodison:BAAALgADCgcJCAAAAA==.Maryillo:BAACLgAFFH8fAAMVAAgJhhdEAABGAgAVAAgJrhVEAABGAgAYAAUJVSHTBACeAQAuAAQKfyQAAxUACAlAJJ8CAPwCABUACAkUIZ8CAPwCABgABwmAJKcNAMECAAAA.',
Mc='Mcflurry:BAAALgAECgQJBAAAAA==.',
Me='Medd:BAAALgAECgUJCQAAAA==.Mengol:BAAALgADCgMJAwABLgAFFAMJCgAYAH4RAA==.Mennil:BAAALgAECgUJCQAAAA==.Meolater:BAABLgAECn8hAAIUAAgJYB/EAgC9AgAUAAgJYB/EAgC9AgAAAA==.Meowz:BAAALgADCgUJBQAAAA==.Mesmerise:BAABLgAECn8XAAIEAAcJLCAKCQDvAQAEAAcJLCAKCQDvAQAAAA==.',
Mh='Mhyrora:BAAALgAECgEJAQAAAA==.',
Mi='Mick:BAAALgADCgcJBwAAAA==.Midorii:BAAALgADCggJCwAAAA==.Mikeygee:BAAALgAECgEJAQABLgAECgcJBwADAAAAAA==.Mio:BAAALgADCgcJBwAAAA==.Miraya:BAACLgAFFH8IAAIKAAMJmAzaSQDEAAAKAAMJmAzaSQDEAAAuAAQKfycAAwoACAl1GE4wAEsCAAoACAnFF04wAEsCAAsABAmtCY46AMoAAAAA.Misbehaved:BAAALgADCgcJDAAAAA==.Mishrakthul:BAAALgAECgQJBwAAAA==.Missfear:BAAALgADCggJFwAAAA==.',
Mm='Mmrsdelaneys:BAAALgADCgEJAgAAAA==.',
Mo='Mokari:BAEBLgAECn8vAAMeAAkJ9yEXAQAaAwAeAAkJdSEXAQAaAwAHAAcJxhzrIgA0AgAAAA==.Mon:BAAALgADCgQJBwAAAA==.Moonfrost:BAAALgAECggJEwAAAA==.Morbidchaos:BAACLgAFFH8OAAIPAAYJhhr5EgBjAQAPAAYJhhr5EgBjAQAuAAQKfxsAAg8ACQljIccFAGkDAA8ACQljIccFAGkDAAAA.Morbius:BAAALgAECgcJEQAAAA==.Morglum:BAABLgAECn8pAAMKAAgJ8xu5OQAlAgAKAAgJ8xu5OQAlAgALAAEJAACXbAA7AAAAAA==.Morlog:BAAALgADCgUJBgAAAA==.Mosnar:BAAALgADCgEJAQAAAA==.Movak:BAEALgADCgUJBQABLgAECgkJKgARAGkiAA==.',
Mu='Muddywalrus:BAAALgAECgIJCAAAAA==.Mukatsuku:BAAALgAECgcJDQAAAA==.Muscida:BAAALgADCgEJAQAAAA==.',
My='Mykg:BAAALgAECgcJBwAAAA==.Myzas:BAAALgADCgcJBwAAAA==.',
['Mâ']='Mâyüri:BAABLgAECn8gAAMaAAkJJxLMEwC4AQAaAAkJJxLMEwC4AQAGAAMJswZolABLAAAAAA==.',
Na='Naaldlooshii:BAAALgAECgEJAQABLgAECgIJAwADAAAAAA==.Naeth:BAABLgAECn8rAAISAAkJ8x1aCQDAAgASAAkJ8x1aCQDAAgAAAA==.Nalrot:BAAALgADCgYJCAABLgAECgcJFwAEACwgAA==.Narcine:BAABLgAECn8uAAMHAAkJbx9EBQDeAgAHAAkJbx9EBQDeAgAeAAYJshu2EQCnAQAAAA==.Narina:BAAALgAECggJCAAAAA==.Naví:BAAALgAECggJDQAAAA==.',
Ne='Necie:BAABLgAECn8wAAIVAAkJBxe6BAAjAgAVAAkJBxe6BAAjAgABLgABCgEJAQADAAAAAA==.Neckred:BAAALgADCgEJAQAAAA==.Nedri:BAABLgAECn8WAAMKAAgJSw+TNgCKAQAKAAgJkQyTNgCKAQAMAAQJMgw6FwDEAAAAAA==.Nee:BAABLgAFFH8UAAIGAAYJ8hk/AwCmAQAGAAYJ8hk/AwCmAQAAAA==.Nelor:BAAALgAECggJEwAAAA==.Nerftitty:BAAALgAECgEJAQAAAA==.Nethya:BAAALgADCgMJAwAAAA==.',
Ni='Nibblet:BAAALgADCgEJAQAAAA==.Nightnight:BAAALgAECgYJCQAAAA==.Nikii:BAAALgADCgUJBQAAAA==.Nikkibear:BAAALgAECgMJBAAAAA==.Ninjason:BAAALgAECgEJAQAAAA==.Nio:BAAALgADCgUJBQAAAA==.Nissa:BAAALgAECgEJAQAAAA==.Nitashal:BAABLgAECn8oAAMUAAkJliK8AAB5AwAUAAkJliK8AAB5AwACAAEJwAYDQAAwAAAAAA==.',
No='Nobudagero:BAAALgAECgYJDgAAAA==.Noremac:BAAALgADCgkJGgAAAA==.Norgalis:BAAALgADCgMJBQAAAA==.Nosman:BAAALgAECgMJAwAAAA==.',
Nr='Nrowtuo:BAAALgAECgYJDwAAAA==.',
Nu='Nummnomms:BAAALgAECgcJCAAAAA==.',
Ny='Ny:BAAALgADCgEJAwAAAA==.',
['Në']='Nëzükõ:BAAALgADCgkJFgABLgAECgkJIAAaACcSAA==.',
Oa='Oathbreaker:BAAALgADCgcJBQAAAA==.',
Ol='Olivabiscuit:BAABLgAECn8VAAMFAAYJ9RSXkgBbAQAFAAYJ9RSXkgBbAQAEAAQJEg5QMQC2AAAAAA==.Oliviawildè:BAAALgAECgQJBgAAAA==.Olivya:BAAALgAECgIJAgAAAA==.',
On='Onepump:BAAALgADCgMJAwAAAA==.',
Oo='Oogiessxd:BAABLgAECn8WAAMgAAUJuRG5JgDyAAAgAAUJ2Qy5JgDyAAAQAAIJtBNkbQBzAAAAAA==.Oops:BAAALgADCgQJBAAAAA==.',
Or='Orwata:BAAALgADCgcJBwAAAA==.',
Ou='Ouskun:BAAALgADCgQJBgAAAA==.',
Ow='Owynn:BAAALgAECgMJAwAAAA==.',
Oz='Ozurot:BAABLgAECn8iAAIhAAgJFRD9FACFAQAhAAgJFRD9FACFAQAAAA==.',
Pa='Pakoh:BAACLgAFFH8FAAIcAAIJ8BfsGACaAAAcAAIJ8BfsGACaAAAuAAQKfygABBwACAnuI4cbAF8CABwABgkYJIcbAF8CABgACAlFIWsLABQCABUAAwmyIq8NAC8BAAAA.Palabok:BAAALgAECggJDwAAAA==.Paladang:BAAALgAECgcJAQAAAA==.Paladont:BAAALgAECgMJBwAAAA==.Palmarez:BAAALgADCgUJBAAAAA==.Panchita:BAAALgAECgcJEQAAAA==.Pandemoniúm:BAABLgAECn8aAAIhAAYJhhyxEwCVAQAhAAYJhhyxEwCVAQAAAA==.Panfriedrice:BAAALgAECgUJBAAAAA==.Pantyblossom:BAABLgAECn8UAAIQAAYJpxiGFgCeAQAQAAYJpxiGFgCeAQAAAA==.Pasdovqr:BAAALgAECgUJEAAAAA==.',
Pe='Peaches:BAAALgAECgcJDAABLgAECgcJFgAmAAcTAA==.Peewees:BAAALgADCgcJBwAAAA==.Pegasus:BAABLgAECn8rAAILAAgJyRkKBACnAgALAAgJyRkKBACnAgAAAA==.Perlman:BAAALgAECgcJCAAAAA==.Persivul:BAAALgAECgUJBgAAAA==.Pewpewz:BAAALgAECgQJCAABLgAECggJMQAJADsTAA==.',
Ph='Phaeddrus:BAAALgAECgYJCwAAAA==.Phaedross:BAAALgAECgEJAQAAAA==.Pheret:BAAALgAFFAIJAwAAAA==.Phobos:BAABLgAECn8vAAIBAAkJowf8GgBmAQABAAkJowf8GgBmAQAAAA==.Phogood:BAAALgAECgUJCQAAAA==.Phrix:BAAALgAECgQJBgABLgAFFAQJDQACABgSAA==.',
Pi='Pineapple:BAAALgAECgUJCQABLgAFFAIJAgADAAAAAA==.Pineapplelol:BAAALgAFFAIJAgAAAA==.Pineapplë:BAABLgAECn8TAAMPAAgJEhmILgBCAgAPAAgJEhmILgBCAgAOAAEJBR8yawA7AAABLgAFFAIJAgADAAAAAA==.Pinecone:BAAALgADCgUJBQABLgAFFAIJAgADAAAAAA==.Pinëapple:BAAALgAECgYJCgABLgAFFAIJAgADAAAAAA==.Pissdanger:BAAALgAECgEJAQAAAA==.Piñeapple:BAAALgAECgYJDAABLgAFFAIJAgADAAAAAA==.',
Pl='Plot:BAAALgAECgcJDgAAAA==.',
Po='Poekimaw:BAAALgAECgQJAwAAAA==.Polpo:BAACLgAFFH8XAAISAAUJkyRaBQC0AQASAAUJkyRaBQC0AQAuAAQKfxYAAhIACAkWJRkoAIQCABIACAkWJRkoAIQCAAAA.Poppinin:BAABLgAECn8iAAISAAgJnBQPLQDJAQASAAgJnBQPLQDJAQAAAA==.Powerwordhug:BAAALgAECgEJAQAAAA==.',
Pr='Prancer:BAAALgADCgMJAwAAAA==.Prevaleon:BAAALgADCgMJAwAAAA==.Procasual:BAABLgAECn8aAAIZAAgJOAf4CwBKAQAZAAgJOAf4CwBKAQAAAA==.',
Ps='Psychritic:BAABLgAECn8iAAIRAAgJFiJ2DgCpAgARAAgJFiJ2DgCpAgAAAA==.Psyence:BAAALgAECgMJBgABLgAECggJGAANAIcRAA==.',
Pt='Pterodactyl:BAAALgAECgYJCgAAAA==.',
Pu='Purpletotem:BAAALgAECgQJBAAAAA==.Purrsnikitty:BAABLgAECn8gAAIHAAgJzxW0IQDSAQAHAAgJzxW0IQDSAQAAAA==.',
['Pà']='Pànzer:BAAALgAECgQJBAAAAA==.',
['Pî']='Pîneapple:BAAALgADCgcJCwABLgAFFAIJAgADAAAAAA==.',
['Pô']='Pô:BAAALgAECgEJAQABLgAECggJHAASAKcdAA==.',
Qq='Qqmoarnoob:BAAALgADCgYJBgAAAA==.',
Qu='Quillmane:BAAALgAECgYJEQABLgAFFAQJDQACABgSAA==.Quiza:BAAALgADCgIJAgAAAA==.',
Ra='Raevyn:BAAALgAECgYJDgAAAA==.Ragebate:BAABLgAECn8fAAIPAAgJchzVLwA8AgAPAAgJchzVLwA8AgAAAA==.Ragingbohner:BAAALgADCgcJBwAAAA==.Ragingdeath:BAAALgAECgQJAwAAAA==.Ragingson:BAAALgAECgQJAgAAAA==.Rainakamugi:BAAALgAFFAEJAQAAAA==.Rakko:BAAALgAECgMJAwAAAA==.Ralphanir:BAABLgAECn8dAAIGAAcJLRfTIACsAQAGAAcJLRfTIACsAQAAAA==.Rangi:BAAALgADCgcJCwAAAA==.Raskreia:BAAALgAECgQJBgABLgAECgQJCAADAAAAAA==.Ravenclaw:BAAALgADCgEJAQAAAA==.Rawdogging:BAAALgADCgYJCgAAAA==.Rawrxd:BAAALgAECgYJDQAAAA==.Raygyu:BAAALgAECgQJBgABLgAECggJKQAHAJciAA==.Rayshoots:BAABLgAECn8pAAQHAAgJlyL3FwB5AgAHAAgJlyL3FwB5AgAeAAYJOBVgFQBpAQAIAAEJhgAonAAMAAAAAA==.Rayvoker:BAAALgADCgYJCgABLgAECggJKQAHAJciAA==.',
Re='Realkaleo:BAAALgAECgcJEAAAAA==.Rebekil:BAABLgAECn8WAAMYAAcJzQgzSAAMAQAYAAcJzQgzSAAMAQAcAAYJPQRQhQDMAAAAAA==.Rediline:BAAALgAECgUJCwAAAA==.Rekkfest:BAAALgADCgMJAwAAAA==.Rexari:BAAALgADCgkJFQAAAA==.Rezmae:BAAALgAECgQJBgAAAA==.Reznàp:BAAALgADCgUJBQAAAA==.',
Rh='Rhamah:BAAALgADCgEJAQAAAA==.Rheba:BAAALgADCgEJAQAAAA==.',
Ri='Rinrin:BAAALgADCgYJBgAAAA==.Riot:BAAALgAECgIJBAABLgAFFAQJDwAFAEwhAA==.Risotto:BAAALgADCgcJBwAAAA==.',
Ro='Roron:BAAALgAECgIJCAAAAA==.Rothgar:BAAALgADCgEJAQAAAA==.Roxy:BAAALgAECgUJBQAAAA==.',
Rr='Rrainmann:BAAALgADCgEJAQAAAA==.',
Ru='Rubmaps:BAAALgADCgUJBQAAAA==.',
Ry='Ryujin:BAAALgADCggJDwAAAA==.',
Sa='Sabi:BAAALgAECgYJEgAAAA==.Sadboy:BAAALgAECgYJCgAAAA==.Sadface:BAAALgAECgQJBAAAAA==.Safetyspork:BAAALgAECgEJAwABLgAECgcJAQADAAAAAA==.Sagë:BAAALgAECgYJEQAAAA==.Salamasina:BAAALgADCgEJAQAAAA==.Salsa:BAAALgAECgEJAQAAAA==.Samunzo:BAAALgADCgQJBQAAAA==.',
Sc='Schobe:BAAALgADCgEJAgABLgAECgIJAwADAAAAAA==.Schönen:BAAALgAFFAIJAgAAAA==.Scojo:BAAALgAECgEJAQAAAA==.Scârecrow:BAABLgAECn8PAAMPAAUJiReJTgANAQAPAAUJiReJTgANAQAOAAEJzRHZawA6AAAAAA==.',
Se='Sehtherria:BAAALgAECgEJAgAAAA==.Seishouu:BAAALgADCgUJBQAAAA==.Sejien:BAABLgAECn8cAAMKAAYJEh0BLgCrAQAKAAYJEh0BLgCrAQALAAEJAAD8dQAvAAAAAA==.Senjou:BAAALgAECgUJCwAAAA==.Sermet:BAAALgADCgcJCgABLgAECggJHgAPAN4fAA==.Serous:BAABLgAECn8hAAIJAAgJkBx5DgAHAgAJAAgJkBx5DgAHAgAAAA==.Setal:BAACLgAFFH8NAAMCAAQJGBLqAQBNAQACAAQJGBLqAQBNAQABAAIJwAazHACLAAAuAAQKfykAAwIACAmOHWkDAOUBAAEACAnlGlQPAIECAAIACAkRG2kDAOUBAAAA.Sevrik:BAABLgAECn8lAAIKAAgJ/BswGgAUAgAKAAgJ/BswGgAUAgAAAA==.',
Sh='Shadowbruin:BAAALgAECgMJAwAAAA==.Shammycammy:BAAALgAECgQJCAAAAA==.Shaoling:BAAALgADCgEJAQAAAA==.Sharadra:BAAALgAECgYJDgAAAA==.Shecklethief:BAABLgAECn8VAAMgAAgJigtQEgC3AQAgAAgJigtQEgC3AQAQAAMJigLmRABSAAAAAA==.Shimmyx:BAAALgADCgYJDgAAAA==.Shinizokonai:BAAALgADCgQJBAAAAA==.Shinydude:BAAALgAECgUJCwAAAA==.Shockwavee:BAAALgADCgQJBAABLgAECggJKwARAI8jAA==.Shogunz:BAAALgAECgMJAwAAAA==.Shroudedmoon:BAACLgAFFH8OAAImAAUJYCGVAQB9AQAmAAUJYCGVAQB9AQAuAAQKfxgAAyYACAlBJJwBAAYDACYACAlBJJwBAAYDACUABAlzGQcJAOkAAAAA.Shàmshii:BAAALgADCgIJAgAAAA==.',
Si='Silk:BAABLgAECn8WAAMmAAcJBxNRBgCJAQAmAAcJBxNRBgCJAQATAAEJ+QdxXwA3AAAAAA==.Sinapaladin:BAAALgAECgYJEQAAAA==.Sinavyr:BAAALgADCgMJAwAAAA==.',
Sk='Skarrtusk:BAAALgADCgYJBgAAAA==.Skroh:BAAALgADCgEJAQAAAA==.Skwsham:BAABLgAECn8fAAIaAAkJ6hwVBQChAgAaAAkJ6hwVBQChAgAAAA==.',
Sl='Slabbcrakle:BAAALgADCgcJCgAAAA==.Slabbhammer:BAABLgAECn8fAAISAAgJnRh9IQABAgASAAgJnRh9IQABAgAAAA==.Slappers:BAAALgADCgIJAgAAAA==.Slaykanit:BAAALgAECgQJBQAAAA==.',
Sm='Smooshednewt:BAAALgAECgQJDwAAAA==.',
Sn='Sneakyknight:BAABLgAECn8VAAITAAgJSgrYEQCNAQATAAgJSgrYEQCNAQAAAA==.',
So='Sobaley:BAAALgADCgQJBAAAAA==.Soggysausage:BAAALgAECgYJBwAAAA==.Sohvar:BAAALgAECgYJCwAAAA==.Sophira:BAABLgAECn8jAAIYAAkJ2Bk8BgB8AgAYAAkJ2Bk8BgB8AgAAAA==.Sosneaky:BAAALgAECgQJBAAAAA==.',
Sp='Sparkels:BAAALgADCgYJBgAAAA==.Spectre:BAAALgAECgEJAQABLgAFFAQJDwAFAEwhAA==.Speknawz:BAABLgAECn8bAAITAAgJtxUhEACkAQATAAgJtxUhEACkAQAAAA==.Spishak:BAAALgAECgYJBgAAAA==.Splatzill:BAAALgAECgUJDAABLgAFFAMJBgAGAEALAA==.Spoiledangel:BAABLgAECn8gAAIQAAgJ0RveCwApAgAQAAgJ0RveCwApAgAAAA==.Spookyhallow:BAABLgAECn8YAAIQAAgJ2wsHMgB4AQAQAAgJ2wsHMgB4AQAAAA==.Springz:BAABLgAFFH8cAAIgAAcJph01AQBAAgAgAAcJph01AQBAAgAAAA==.',
St='Starryniight:BAABLgAECn8nAAIKAAgJewiASABPAQAKAAgJewiASABPAQAAAA==.Stereodh:BAABLgAECn8jAAIPAAcJ/BYvLACHAQAPAAcJ/BYvLACHAQAAAA==.',
Su='Suetang:BAAALgAECgQJBAAAAA==.Sullengard:BAAALgADCgkJCQAAAA==.Supanova:BAAALgAFFAEJAgAAAA==.Surwick:BAABLgAECn8vAAIiAAkJMRJ6CADFAQAiAAkJMRJ6CADFAQAAAA==.Sussybaka:BAAALgADCgUJBQAAAA==.',
Sv='Svelus:BAACLgAFFH8FAAISAAUJxhq6EwBYAQASAAUJxhq6EwBYAQAuAAQKfxQAAhIABgkzI3Y7ADYCABIABgkzI3Y7ADYCAAEuAAUUBQkOACYAYCEA.',
Sw='Swangin:BAAALgAECgEJAQAAAA==.Swingin:BAABLgAECn8aAAIiAAcJLgxmGADTAAAiAAcJLgxmGADTAAAAAA==.Swishers:BAAALgAECgUJBgAAAA==.',
Sy='Synapticvoid:BAABLgAECn8WAAIPAAgJMAZjWADzAAAPAAgJMAZjWADzAAAAAA==.',
['Sï']='Sïxx:BAAALgADCgMJAwAAAA==.',
Ta='Tanurhide:BAAALgAECgQJBQAAAA==.Tapdat:BAACLgAFFH8KAAMKAAMJ6QsZSwDBAAAKAAMJ6QsZSwDBAAALAAEJwg7tFQBTAAAuAAQKfyQAAwsACAlTHVkLAAsCAAsABwl8GVkLAAsCAAoABwl2H9FIAPABAAAA.Tarram:BAAALgAECgYJCAAAAA==.Tartin:BAACLgAFFH8GAAIYAAQJrAuLGQDaAAAYAAQJrAuLGQDaAAAuAAQKfxsAAhgACAnTH1UOALgCABgACAnTH1UOALgCAAAA.Tasveira:BAAALgADCgEJAQAAAA==.Taurenmill:BAABLgAFFH8FAAIGAAMJYxTuIQDRAAAGAAMJYxTuIQDRAAAAAA==.',
Te='Teapsy:BAAALgAECgcJEQAAAA==.Techi:BAAALgAECgQJBAAAAA==.Tedward:BAAALgADCgQJBAAAAA==.Teener:BAAALgADCgQJBAAAAA==.Temres:BAABLgAECn8eAAQPAAgJ3h81CgCGAgAPAAgJ3h81CgCGAgANAAUJKxRaFQABAQAOAAEJfgbUdQAvAAAAAA==.Tendermulva:BAABLgAECn8hAAIMAAgJhQpWCADFAQAMAAgJhQpWCADFAQAAAA==.Tentoestwo:BAAALgAECgYJCgAAAA==.Tenzzo:BAAALgAECgUJBQAAAA==.Terekk:BAAALgADCgcJEwAAAA==.Terna:BAAALgADCgYJBwAAAA==.Tevashi:BAAALgAECgYJCwAAAA==.',
Th='Thannin:BAAALgAECgMJBgAAAA==.Tharekon:BAAALgAFFAIJBAAAAA==.Thedrink:BAAALgAECgIJBAAAAA==.Thermox:BAAALgAECgYJBwAAAA==.Thesauce:BAACLgAFFH8RAAIhAAUJ5CNEAgChAQAhAAUJ5CNEAgChAQAuAAQKfyMAAiEACQm+JF8CAHgDACEACQm+JF8CAHgDAAAA.Thesmallman:BAAALgADCgcJDgAAAA==.Thexcurse:BAAALgADCgcJBwAAAA==.Thimo:BAAALgAECgQJCAAAAA==.Thrikal:BAABLgAECn8nAAIOAAgJ5xU2DgCeAQAOAAgJ5xU2DgCeAQAAAA==.Throh:BAAALgADCgEJAQAAAA==.Thugd:BAAALgAECgYJDwAAAA==.',
Ti='Tiadalma:BAAALgAECgMJBAAAAA==.Tiek:BAABLgAECn8uAAIJAAkJJhkZBgCQAgAJAAkJJhkZBgCQAgAAAA==.Tindissa:BAAALgAECgMJAwAAAA==.Tivis:BAABLgAECn8iAAILAAgJFgpFCQBDAQALAAgJFgpFCQBDAQAAAA==.',
To='Toastydemon:BAABLgAECn8hAAIPAAgJMxOoJgCiAQAPAAgJMxOoJgCiAQAAAA==.Tokedope:BAAALgAECgUJCwAAAA==.Tomoe:BAAALgADCgkJCQAAAA==.Tomsmg:BAABLgAFFH8GAAIRAAMJyAn2TwDjAAARAAMJyAn2TwDjAAAAAA==.Tonen:BAABLgAECn8eAAIJAAcJ2ReUFQC9AQAJAAcJ2ReUFQC9AQAAAA==.Toofs:BAAALgAECgYJEAAAAA==.Torno:BAAALgAECgQJBQAAAA==.Totemtonya:BAAALgAECgEJAQAAAA==.Toxifay:BAAALgAECgYJCQAAAA==.Toywar:BAAALgADCgcJBgAAAA==.',
Ts='Tsilatra:BAAALgAECgQJBAAAAA==.',
Tu='Tufluk:BAABLgAECn8aAAIOAAgJyhULEQB1AQAOAAgJyhULEQB1AQAAAA==.Tuktirey:BAAALgAECgEJAQAAAA==.',
Tw='Twelevepeers:BAAALgAECgQJBAAAAA==.Twigs:BAAALgAECgkJCgAAAA==.',
['Tì']='Tìõ:BAABLgAECn8lAAIBAAgJcxTCGAAJAgABAAgJcxTCGAAJAgABLgAECgkJIAAaACcSAA==.',
['Tô']='Tôms:BAAALgAECggJEwAAAA==.',
['Tö']='Töms:BAAALgADCgYJCAAAAA==.',
Ud='Udderlegend:BAAALgADCgcJEAAAAA==.',
Ug='Ughtismo:BAAALgADCgYJBgAAAA==.',
Ul='Ulrikan:BAAALgAECgEJAQAAAA==.Ultarok:BAAALgAECgYJCAAAAA==.',
Un='Undeadban:BAAALgAECgEJAQAAAA==.Unfiltered:BAAALgAECgQJCgAAAA==.Unwanted:BAAALgAECgYJEQAAAA==.',
Up='Upstream:BAAALgADCgYJCwAAAA==.',
Us='Usagiknight:BAAALgADCgEJAQAAAA==.Ushii:BAAALgAECgUJCwAAAA==.',
Va='Vaelindar:BAAALgADCgUJBgAAAA==.Vakarians:BAAALgAECgMJAwAAAA==.Vakkd:BAAALgADCgIJAgAAAA==.Valei:BAAALgAECgQJBAAAAA==.Valenai:BAAALgAECgEJAQAAAA==.Valor:BAACLgAFFH8PAAIFAAQJTCFRGQByAQAFAAQJTCFRGQByAQAuAAQKfx0AAwUACQnbHp8gAL8CAAUACAlIIp8gAL8CAB0AAQneBmIUAEMAAAAA.Vampirevic:BAAALgAECgYJBgAAAA==.Vansanssra:BAAALgADCgEJAQAAAA==.Varcoh:BAABLgAECn8mAAMQAAgJsA70GQB9AQAQAAgJsA70GQB9AQAfAAIJUgQQWgBQAAAAAA==.',
Ve='Velixar:BAAALgAECgEJAQAAAA==.Veloxen:BAAALgAFFAEJAQAAAA==.Venthyr:BAAALgADCgEJAQABLgAFFAQJDwAFAEwhAA==.Verikost:BAAALgADCgEJAQAAAA==.',
Vi='Victanney:BAAALgAECgkJBwABLgAECgkJJgAKAPEbAA==.Vinda:BAACLgAFFH8FAAIfAAIJzwZYGgCUAAAfAAIJzwZYGgCUAAAuAAQKfzAAAh8ACQlyF0sHAFoCAB8ACQlyF0sHAFoCAAAA.',
Vl='Vladious:BAABLgAECn8mAAQKAAkJ8RuqCgCgAgAKAAgJ8RuqCgCgAgALAAIJvB1USACWAAAMAAEJAABwKABQAAAAAA==.',
Vy='Vynd:BAAALgAECgYJEwAAAA==.Vynllandis:BAAALgADCgMJAwAAAA==.',
Wa='Wallo:BAABLgAECn8xAAIJAAgJOxNkFQC+AQAJAAgJOxNkFQC+AQAAAA==.Warglaivez:BAAALgAECgQJDwAAAA==.Washedbolt:BAAALgAFFAEJAQAAAA==.Washedpyro:BAAALgAECgcJCQAAAA==.Wata:BAAALgAECgMJAwAAAA==.Watchscotch:BAAALgADCgkJFQABLgAECggJGgAHADoYAA==.Wayfairkid:BAAALgAECgYJCwAAAA==.',
We='Werken:BAAALgAECgMJBQAAAA==.',
Wh='Whyetee:BAACLgAFFH8FAAITAAIJOw8mGwChAAATAAIJOw8mGwChAAAuAAQKfy0AAxMACAlMI7wLANoCABMACAkLIrwLANoCACYAAglKIm0UALYAAAAA.',
Wi='Willywonkas:BAAALgADCgkJGQAAAA==.Windowlicker:BAAALgADCgEJAQAAAA==.Wineo:BAABLgAECn8kAAIYAAgJeiCoDQDAAgAYAAgJeiCoDQDAAgAAAA==.Wizzwee:BAAALgAECgIJAgABLgAECgkJHgAOAIEcAA==.',
Wo='Woa:BAAALgAECgEJAQAAAA==.Wonder:BAAALgAECgIJAwAAAA==.Woofwoofwoof:BAABLgAECn8fAAIRAAgJjAwYUgB1AQARAAgJjAwYUgB1AQAAAA==.Worn:BAAALgADCgQJBAAAAA==.Worthlesshoe:BAAALgADCgIJBAABLgADCgUJBQADAAAAAA==.',
Wr='Wraithwok:BAAALgADCgYJBgAAAA==.Wrld:BAAALgAECgYJCQAAAA==.',
['Wà']='Wàll:BAAALgADCgMJAwAAAA==.',
['Wå']='Wåffle:BAAALgADCgMJAwAAAA==.',
Xa='Xasther:BAABLgAECn8jAAISAAgJlCRdCQDAAgASAAgJlCRdCQDAAgAAAA==.Xav:BAAALgADCgkJDAAAAA==.',
Xe='Xenophilius:BAAALgAECgcJDgAAAA==.Xeruk:BAAALgAECgYJDAAAAA==.',
Ya='Yasha:BAAALgADCgEJAQABLgAECgUJCQADAAAAAA==.',
Ye='Yearsfade:BAAALgADCgMJAwAAAA==.',
Yu='Yuka:BAAALgADCgUJBAAAAA==.Yulok:BAAALgAECgQJBQABLgAFFAgJFAAaADkgAA==.Yumí:BAABLgAECn8dAAMeAAgJ4BzMCQBAAgAeAAgJ4BzMCQBAAgAIAAEJywn0iQAxAAAAAA==.Yurgling:BAAALgAECgMJBAAAAA==.',
Za='Zaberra:BAAALgAECgEJAgABLgAECgkJIwAYANgZAA==.Zanarkand:BAAALgAECggJDwAAAA==.Zarivara:BAAALgAECgEJAgAAAA==.',
Ze='Zepha:BAAALgADCgIJAQAAAA==.',
Zi='Zib:BAAALgAECgkJBgAAAA==.Zibrina:BAAALgADCgUJCAAAAA==.Zieg:BAAALgADCgIJAgABLgAFFAIJBAADAAAAAA==.Zina:BAAALgAECgEJAQAAAA==.Zitish:BAAALgADCgEJAQAAAA==.',
Zo='Zomby:BAAALgAECgcJCgAAAA==.',
Zu='Zuko:BAAALgADCgEJAQAAAA==.',
['Ço']='Çookiemonstr:BAAALgADCgkJDwAAAA==.',
['Ëy']='Ëyë:BAAALgAFFAEJAQAAAA==.',
['Ñi']='Ñina:BAAALgAECgYJCgAAAA==.',
['ßu']='ßutterworth:BAAALgADCgEJAQAAAA==.',
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

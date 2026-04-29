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

local lookup = {'Shaman-Restoration','Warlock-Destruction','Warlock-Demonology','Unknown-Unknown','Mage-Frost','Shaman-Elemental','Paladin-Retribution','Paladin-Holy','Hunter-Survival','Hunter-Marksmanship','Hunter-BeastMastery','Priest-Discipline','Priest-Holy','Warrior-Fury','Shaman-Enhancement','Monk-Brewmaster','Druid-Restoration','Priest-Shadow','Paladin-Protection','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Warrior-Protection','Druid-Guardian','DemonHunter-Devourer','Monk-Mistweaver','Druid-Balance','Warlock-Affliction','DemonHunter-Havoc','DeathKnight-Frost','Rogue-Subtlety','Druid-Feral','DeathKnight-Unholy','DeathKnight-Blood','DemonHunter-Vengeance','Monk-Windwalker','Warrior-Arms','Rogue-Outlaw',}
local provider = {region='US',realm='Garona',name='US',type='weekly',zone=46,date='2026-04-24',data={Aa='Aartoo:BAAALgADCgUJBwAAAA==.',
Ac='Ackreshanot:BAAALgADCgYJCQABLgAFFAQJCQABAE4dAA==.Acuna:BAABLgAECn8VAAICAAYJTg7EIQBHAQACAAYJTg7EIQBHAQAAAA==.',
Ae='Aerotika:BAAALgADCgcJBwAAAA==.',
Ai='Airz:BAAALgAECgYJEQAAAA==.',
Ak='Akennethpaly:BAAALgADCgQJBwAAAA==.Aknou:BAAALgADCgQJBAAAAA==.Akrichie:BAAALgAECgEJAQABLgAFFAUJDAADACMPAA==.Akudama:BAAALgAECgMJBAAAAA==.Akâkiôs:BAAALgAECgYJDwAAAA==.',
Al='Aladorman:BAAALgAECgQJCAAAAA==.Albertlin:BAAALgAECgQJBAAAAA==.Aldin:BAAALgAECgUJBgAAAA==.Alexpaladin:BAAALgADCgEJAQAAAA==.Altarya:BAAALgAECgYJBgABLgAECgcJDgAEAAAAAA==.Altex:BAABLgAECn8eAAIFAAgJ1RrXDADlAQAFAAgJ1RrXDADlAQAAAA==.Altexa:BAAALgADCgMJAwABLgAECggJFAAGALkcAA==.Altriimus:BAAALgAECgIJAgAAAA==.',
Am='Amakuagsak:BAAALgAECgYJEAAAAA==.Amicus:BAAALgAECgYJDwAAAA==.',
An='Anadarmas:BAAALgADCgEJAgAAAA==.Ancestor:BAAALgADCgUJBQAAAA==.Angelcastiel:BAAALgADCgEJAQAAAA==.Anothertalas:BAAALgAECgIJAQAAAA==.Anthren:BAAALgADCgYJBgABLgAECgIJAwAEAAAAAA==.',
Ao='Aoifè:BAAALgAECgMJAwAAAA==.',
Ap='Apollo:BAABLgAECn8cAAMHAAgJ/xsXDwCuAQAHAAcJ2xwXDwCuAQAIAAMJdgfLdQCjAAAAAA==.Apolynnae:BAAALgADCgMJAwABLgAECggJEwAEAAAAAA==.Apolynnæ:BAAALgAECgQJBAABLgAECggJEwAEAAAAAA==.',
Aq='Aquanoria:BAAALgADCggJEwAAAA==.',
Ar='Arasthel:BAAALgAECgcJCAAAAA==.Arthalion:BAAALgAECgEJAQAAAA==.Arvellonwen:BAAALgADCgEJAQAAAA==.',
As='Ascalapha:BAAALgAECgcJBwAAAA==.Ashe:BAACLgAFFH8NAAMJAAQJyB65AAB9AQAKAAQJ2Ru0CQB9AQAJAAQJ7he5AAB9AQAuAAQKfyIAAgoACQmdJkEAAO8DAAoACQmdJkEAAO8DAAAA.',
At='Attabubble:BAAALgADCgEJAQABLgAFFAQJCAALAD8dAA==.Attaraxia:BAACLgAFFH8IAAILAAQJPx1lCQAWAQALAAQJPx1lCQAWAQAuAAQKfycAAwsACQkSI/4JAPgCAAsACQkSI/4JAPgCAAoAAQm4AXWZABsAAAAA.',
Au='Aure:BAAALgADCgMJAwAAAA==.Aurelith:BAAALgADCgMJBAAAAA==.Auvona:BAAALgAECgYJCAAAAA==.',
Az='Azavin:BAABLgAECn8VAAIIAAgJNAwINgCkAQAIAAgJNAwINgCkAQAAAA==.Azezal:BAAALgAECgYJBwAAAA==.',
Ba='Babba:BAAALgADCgQJBAAAAA==.Baegar:BAAALgAECgYJBgAAAA==.Bakugo:BAACLgAFFH8JAAIMAAMJthBWBgDyAAAMAAMJthBWBgDyAAAuAAQKfxwAAwwACAk0Ib4JAJ4CAAwACAn+Hr4JAJ4CAA0ABgmNH+wgANsBAAAA.Bamfbutcher:BAABLgAECn8ZAAIOAAgJ3BcjBgDEAQAOAAgJ3BcjBgDEAQAAAA==.Banang:BAAALgADCgUJBQAAAA==.Barrimen:BAAALgAECgYJEAAAAA==.Bartolomew:BAAALgAECggJEwAAAQ==.Batboy:BAAALgAECgYJEgAAAA==.',
Be='Beepers:BAABLgAECn8YAAILAAgJ/A7HDQCYAQALAAgJ/A7HDQCYAQAAAA==.Behodahlia:BAAALgAECgYJEgAAAA==.Bellattrix:BAAALgAECgUJBQAAAA==.Benezra:BAAALgAECgEJAQAAAA==.Bexurk:BAABLgAECn8UAAMPAAgJSQThBgASAQAPAAgJ7gPhBgASAQAGAAEJwgOnKwAoAAAAAA==.',
Bi='Biaku:BAAALgADCgIJAgAAAA==.Bibleman:BAAALgADCgIJAgABLgAECgYJDAAEAAAAAA==.Bigcalcium:BAABLgAECn8hAAIHAAgJnyWIBgBmAwAHAAgJnyWIBgBmAwAAAA==.Bigdemon:BAAALgADCgcJCQAAAA==.Bighimbo:BAAALgAECgYJDwAAAA==.Biltix:BAACLgAFFH8GAAIQAAIJNiDUCQC/AAAQAAIJNiDUCQC/AAAuAAQKfxsAAhAABwmQH8oSAHwCABAABwmQH8oSAHwCAAAA.Bimzelx:BAAALgAECgMJBQAAAA==.Bipolar:BAAALgAECgIJAgAAAA==.Bitterblood:BAAALgAECgQJBwAAAA==.',
Bl='Blanche:BAAALgADCgYJBgAAAA==.Blastgamer:BAAALgAECgIJAgAAAA==.Blindbob:BAAALgADCgUJBwAAAA==.Blueb:BAAALgADCgkJEgABLgAECggJIAANAGQaAA==.',
Bo='Boltbourne:BAAALgADCgUJBQAAAA==.Bolyn:BAAALgADCgYJCwAAAA==.Bonami:BAAALgADCgYJBgAAAA==.Bongwizard:BAAALgADCgUJBQAAAA==.Booshi:BAABLgAECn8cAAIRAAgJbhUYNwDLAQARAAgJbhUYNwDLAQAAAA==.Bowiiesenpai:BAABLgAECn8aAAISAAgJIB66AwDyAQASAAgJIB66AwDyAQAAAA==.Bowmarc:BAAALgAECggJEgAAAA==.Boykisser:BAAALgAECgUJBQAAAA==.',
Br='Bravehearth:BAAALgAECgIJAgABLgAECgQJBAAEAAAAAA==.Brewcifer:BAAALgADCgYJBgAAAA==.Brightxan:BAABLgAECn8dAAITAAgJNhhcCgApAgATAAgJNhhcCgApAgAAAA==.Broamdar:BAAALgAECgkJBgAAAA==.Brotha:BAAALgADCgUJCgAAAA==.Brownbeard:BAAALgAECgYJDAAAAA==.',
Bu='Bubbapriest:BAAALgADCgMJAwAAAA==.Bubbashaman:BAAALgAECgYJDQAAAA==.Budgetsushi:BAAALgADCgcJCwAAAA==.Burninator:BAABLgAECn8WAAQUAAgJdBaCEwCrAQAUAAYJrhmCEwCrAQAVAAgJThGsIgCpAQAWAAIJJw1PQABoAAAAAA==.Bus:BAABLgAFFH8FAAIXAAUJXyIYAQD5AQAXAAUJXyIYAQD5AQABLgAFFAcJCAAYAEEfAA==.Butterrs:BAAALgAECgUJBwAAAQ==.Butterz:BAABLgAECn8fAAIGAAkJuB4/CwDkAgAGAAkJuB4/CwDkAgABLgAECgUJBwAEAAAAAA==.',
Ca='Caelan:BAAALgAECgEJAQAAAA==.Caloren:BAABLgAECn8gAAIZAAgJGiDLAwBcAgAZAAgJGiDLAwBcAgAAAA==.Calqlated:BAAALgADCgYJBgABLgAECgcJCQAEAAAAAA==.',
Ce='Cedrid:BAAALgADCgIJAgAAAA==.Cenauria:BAAALgADCgYJBgAAAA==.',
Ch='Chanit:BAAALgAECgcJDwAAAA==.Chaosbeast:BAAALgADCgEJAQAAAA==.Charuzu:BAAALgAECgYJCwAAAA==.Chaurana:BAAALgAECgcJEwAAAA==.Chenzio:BAAALgADCgUJBQAAAA==.Chikorita:BAAALgAECgcJDgAAAA==.Chilidan:BAAALgAECgIJAgAAAA==.Chimichurri:BAAALgAECgMJAwAAAA==.Chipo:BAAALgAECgEJAgAAAA==.Chrilynn:BAABLgAECn8UAAMHAAYJohWXHQA9AQAHAAYJKhSXHQA9AQATAAQJhRJEKADHAAAAAA==.Chuwee:BAAALgADCgIJAgAAAA==.',
Ci='Cind:BAAALgADCgcJCAAAAA==.Cinderatrath:BAACLgAFFH8MAAIUAAUJZxHcAAAIAQAUAAUJZxHcAAAIAQAuAAQKfyoAAhQACAkRInQAAFACABQACAkRInQAAFACAAAA.',
Cn='Cnydemon:BAAALgADCgEJAQAAAA==.',
Co='Corsaro:BAAALgAECgMJAwAAAA==.Corvixius:BAABLgAECn8UAAIOAAYJDAvNFAD2AAAOAAYJDAvNFAD2AAAAAA==.',
Cr='Crunchwrap:BAAALgAECgYJEAAAAA==.',
Cu='Cuigy:BAAALgAECgYJEgAAAA==.',
Cy='Cyriene:BAAALgAECgUJDQAAAA==.Cyrik:BAAALgAECgYJDgAAAA==.',
Da='Daevas:BAAALgADCgEJAQABLgAECgYJDAAEAAAAAA==.Danksinatra:BAAALgAECgUJDgAAAA==.Danté:BAABLgAECn8bAAIFAAcJ+BvMUgA/AgAFAAcJ+BvMUgA/AgAAAA==.Dardorian:BAAALgAECgEJAgAAAA==.Darko:BAAALgAECgQJCgAAAA==.Darou:BAAALgAECgcJEgAAAA==.Daylen:BAAALgAECgYJDAAAAA==.',
De='Deactrim:BAAALgAECgMJAwAAAA==.Deadploo:BAAALgADCgMJAwAAAA==.Deadpòól:BAAALgADCgUJBQABLgAECgIJAgAEAAAAAA==.Deafknights:BAAALgADCgQJBAABLgAECggJFAAGALkcAA==.Deathgoat:BAAALgADCgIJAgAAAA==.Deku:BAAALgAECgMJBAABLgAECgYJDAAEAAAAAA==.Demiglace:BAABLgAECn8ZAAMQAAcJ5SXiBwAHAwAQAAcJ5SXiBwAHAwAaAAEJxxTTaAAwAAABLgAFFAUJFAAZAB0mAA==.Demonfloozie:BAAALgADCgkJCQAAAA==.Demongal:BAAALgADCgQJBAAAAA==.Dendrada:BAAALgAECgYJDAAAAA==.Dewbie:BAABLgAECn8ZAAIJAAgJ8hOQCQBGAgAJAAgJ8hOQCQBGAgAAAA==.',
Di='Dirtyshim:BAAALgAECgMJAwAAAA==.Dizimo:BAAALgAECgUJBgAAAA==.',
Dm='Dminn:BAAALgAECgQJBQAAAA==.',
Do='Dogmeat:BAACLgAFFH8HAAILAAQJeRxVAgB6AQALAAQJeRxVAgB6AQAuAAQKfxgAAgsABwl9IKcWAIMCAAsABwl9IKcWAIMCAAEuAAUUBQkKABsAFBEA.Doomslayer:BAAALgADCgcJDgAAAA==.Doreniel:BAAALgAECgEJAQAAAA==.Dotisa:BAAALgAECgUJBwAAAA==.',
Dr='Draxker:BAAALgAECgYJEgAAAA==.Dreadmourne:BAAALgAECgMJAwAAAA==.Druddigon:BAAALgAECgQJBQABLgAECgcJCQAEAAAAAA==.',
Du='Duna:BAAALgAECgYJDwAAAA==.Duvidressra:BAABLgAECn8XAAMcAAcJhgyKAgAzAQAcAAcJhgyKAgAzAQADAAMJUAVf/QBgAAAAAA==.',
Dx='Dxmvn:BAAALgADCgEJAQAAAA==.',
Dy='Dyingmight:BAAALgAECgQJBAAAAA==.',
['Dä']='Dävïs:BAAALgAECggJEwAAAA==.',
Ed='Edea:BAAALgAECgQJBwAAAA==.Edisonn:BAABLgAECn8fAAMDAAgJjhq2CwC9AQADAAgJXhq2CwC9AQACAAMJfxw3OwDHAAAAAA==.',
El='Eldermoon:BAAALgAECgYJCAAAAA==.Elghinn:BAABLgAECn8bAAIdAAgJsBLABACHAQAdAAgJsBLABACHAQAAAA==.Ellie:BAAALgAECgYJEgAAAA==.Elponch:BAAALgAECgYJBQAAAA==.Elroy:BAABLgAECn8ZAAIHAAgJghDcVgDdAQAHAAgJghDcVgDdAQAAAA==.',
Em='Embold:BAACLgAFFH8WAAIKAAYJaSIKAgBRAgAKAAYJaSIKAgBRAgAuAAQKfy0AAgoACQnqJWYAAOYDAAoACQnqJWYAAOYDAAAA.Emernantus:BAABLgAECn8WAAITAAYJPg8CHgAZAQATAAYJPg8CHgAZAQAAAA==.Emozi:BAABLgAECn8eAAMcAAcJwhDNCwB9AQAcAAYJoBHNCwB9AQADAAcJBQ+0HQAuAQAAAA==.',
Eu='Eunbyeol:BAABLgAECn8WAAIOAAcJPBiPKgAOAgAOAAcJPBiPKgAOAgAAAA==.',
Ex='Excidium:BAAALgAECgYJDQAAAA==.',
Fa='Faeria:BAAALgAECgYJEwAAAA==.Fangwalker:BAAALgAECgQJCwAAAA==.Farmerdotcom:BAAALgADCgEJAQAAAA==.Fatnchunkydk:BAAALgAECgYJDQAAAA==.',
Fe='Feeblemind:BAAALgAECgcJEwAAAA==.Feesherman:BAAALgAECgcJEwAAAA==.Feli:BAAALgAECgYJDwAAAA==.Felldor:BAAALgADCgUJAgAAAA==.Felmommy:BAAALgADCgYJBgAAAA==.Felrindan:BAAALgAECgYJDAAAAA==.Felscream:BAAALgADCgUJBQAAAA==.Fender:BAAALgAECgcJEwAAAA==.Ferchrian:BAAALgADCgEJAQAAAA==.',
Fi='Finfangfoom:BAAALgAECgQJBAAAAA==.Fingertoes:BAABLgAECn8cAAIFAAgJ2xqHQQB0AgAFAAgJ2xqHQQB0AgAAAA==.Fistamista:BAAALgADCgYJBgAAAA==.Fizban:BAAALgADCggJFAAAAA==.',
Fl='Flaygar:BAAALgAECgYJDAAAAA==.Flory:BAABLgAECn8bAAIHAAgJHBkjKACEAgAHAAgJHBkjKACEAgAAAA==.Flowpro:BAAALgADCgMJAwAAAA==.Flyinweasle:BAAALgAECgUJBQAAAA==.',
Fo='Foundation:BAAALgAECgMJBAAAAA==.Foxxycontin:BAABLgAECn8aAAMNAAcJEBDgMAB9AQANAAcJEBDgMAB9AQASAAEJFQZrZgAsAAAAAA==.',
Fr='Frostyrican:BAAALgAECgEJAQAAAA==.',
Fu='Fuglybaby:BAAALgADCgUJBQAAAA==.',
Fw='Fwakos:BAAALgADCgUJCQAAAA==.',
['Fé']='Fénnie:BAAALgADCgMJAwAAAA==.',
Ga='Gaivahros:BAAALgAECgcJDQAAAA==.Gakpaladin:BAABLgAECn8bAAITAAgJqBVPAwCeAQATAAgJqBVPAwCeAQAAAA==.Galileo:BAAALgAECgQJBAAAAA==.',
Ge='Gerasstrois:BAAALgAECgcJEAABLgAECgcJFwAcAIYMAA==.Gerionier:BAAALgADCgEJAQABLgAECgYJBgAEAAAAAA==.Gethael:BAAALgAECgEJAQAAAA==.',
Gh='Ghalathor:BAAALgADCgMJAwAAAA==.',
Gl='Glimsy:BAAALgADCgYJCQAAAA==.Glittermilk:BAAALgADCgUJBQAAAA==.',
Go='Golosan:BAABLgAECn8aAAIQAAgJ6xz5AgAWAgAQAAgJ6xz5AgAWAgAAAA==.Goododie:BAAALgAECgYJDwAAAA==.Gordil:BAAALgAECgMJAwAAAA==.Gorokan:BAAALgAECgIJAwAAAA==.',
Gr='Grayback:BAAALgAECgcJBgABLgAECggJIQADAC4YAA==.Grimsdeath:BAAALgADCgUJBQAAAA==.',
Gu='Guila:BAAALgAECgYJEAAAAA==.Gulaken:BAAALgAECgUJBwAAAA==.',
Ha='Hafnia:BAAALgAECgQJCAAAAA==.Hai:BAAALgADCgEJAQAAAA==.Halphion:BAAALgADCgYJBwABLgAECgYJEAAEAAAAAA==.Hanoe:BAAALgADCgYJBgAAAA==.Haoasakura:BAABLgAECn8lAAIHAAgJhCLKAwBqAgAHAAgJhCLKAwBqAgAAAA==.Haybuse:BAABLgAECn8fAAIJAAgJdB89AQBOAgAJAAgJdB89AQBOAgAAAA==.',
He='Healmd:BAAALgADCgMJAwAAAA==.Healzforfood:BAAALgAECgUJCAAAAA==.Healzyou:BAAALgADCgMJAwAAAA==.Heap:BAABLgAECn8ZAAIYAAgJgA2nEQBbAQAYAAgJgA2nEQBbAQAAAA==.Hectavius:BAAALgADCgIJAgAAAA==.Hewnoshaqa:BAABLgAECn8UAAILAAcJOA7BEgBlAQALAAcJOA7BEgBlAQAAAA==.Hexeñ:BAAALgAECgYJBwAAAA==.Hexorcist:BAACLgAFFH8FAAIBAAIJmCH8EgDJAAABAAIJmCH8EgDJAAAuAAQKfxcAAwEACAnPGY0bADwCAAEACAnPGY0bADwCAAYAAwnVGa5aANkAAAAA.',
Hi='Hickerbilly:BAAALgAECgkJCAAAAA==.Higgintoot:BAAALgAECgIJAgAAAA==.Hitormist:BAAALgAECgYJDAAAAA==.',
Ho='Holyshoot:BAAALgAECgIJBAAAAA==.Horous:BAAALgADCgkJAgAAAA==.',
Hr='Hruuli:BAAALgAECgIJAgAAAA==.',
Hu='Hungweilow:BAAALgADCgUJBgABLgAECgQJBAAEAAAAAA==.Huugar:BAAALgAECgcJEgAAAA==.',
['Hæ']='Hædés:BAAALgAECgYJEwAAAA==.',
Ib='Ibeamwork:BAAALgAECgcJEAAAAA==.',
Ic='Icoulddowork:BAAALgADCgQJBAABLgAECgcJEAAEAAAAAA==.Icyconjurer:BAAALgADCgMJAwAAAA==.',
Id='Idoworkz:BAAALgADCgcJBwABLgAECgcJEAAEAAAAAA==.',
Ii='Iiquorice:BAAALgAECgMJAwAAAA==.',
Ik='Ikazuchi:BAABLgAECn8UAAIeAAgJ5hKVAQCdAQAeAAgJ5hKVAQCdAQAAAA==.',
Il='Illcutabish:BAABLgAECn8hAAIfAAgJAxmqBAC6AQAfAAgJAxmqBAC6AQAAAA==.',
Im='Imk:BAAALgAECgcJEwAAAA==.',
In='Ineedatarget:BAAALgADCgEJAQAAAA==.Intbuff:BAAALgADCggJDQABLgAECgQJBAAEAAAAAA==.Invadiah:BAAALgAECgcJDQAAAA==.Invited:BAAALgAECgIJAgAAAA==.',
Io='Iock:BAEALgAECgUJCAAAAA==.',
Ir='Ironarms:BAAALgADCgUJBQAAAA==.',
Iw='Iwdominate:BAAALgADCgMJAwAAAA==.',
Iy='Iyana:BAAALgAECgMJAwAAAA==.',
Iz='Izümi:BAABLgAECn8UAAIJAAYJJxhfBgBeAQAJAAYJJxhfBgBeAQAAAA==.',
Ja='Jazz:BAAALgADCgcJBwAAAA==.',
Je='Jennypoo:BAABLgAECn8dAAIRAAYJbR0VMQDmAQARAAYJbR0VMQDmAQAAAA==.',
Ji='Jild:BAAALgAECgQJBgAAAA==.Jinwoosung:BAAALgAECgYJDQAAAA==.',
Jo='Johnwarrior:BAAALgAECggJEAAAAA==.Jorrix:BAABLgAECn8YAAIHAAYJUQ90IAAsAQAHAAYJUQ90IAAsAQAAAA==.',
Ju='Juduspriestt:BAABLgAECn8WAAIHAAYJ3BhGdwCMAQAHAAYJ3BhGdwCMAQAAAA==.Jurt:BAAALgADCgcJDQAAAA==.',
Ka='Kaalysto:BAAALgADCgMJAwAAAA==.Kaekko:BAAALgADCgYJBgABLgAECggJGAASACQbAA==.Kaeko:BAABLgAECn8YAAISAAgJJBtrEACAAgASAAgJJBtrEACAAgAAAA==.Kaelathaniel:BAABLgAECn8cAAMDAAgJugrEXwCqAQADAAgJuArEXwCqAQACAAEJeA69dQAvAAAAAA==.Kalerito:BAABLgAECn8UAAIRAAgJAh0NIgA2AgARAAgJAh0NIgA2AgAAAA==.Kalistae:BAAALgAECgYJEgAAAA==.Kallivath:BAAALgADCgYJCAAAAA==.Kamdrixa:BAAALgADCgYJDAAAAA==.Karinus:BAAALgADCgUJBQAAAA==.Karl:BAAALgAECgUJEwAAAA==.Karlack:BAAALgADCgUJBQAAAA==.Kaserr:BAACLgAFFH8IAAIfAAMJVw89DgAKAQAfAAMJVw89DgAKAQAuAAQKfyAAAh8ACQksIOcCAHcDAB8ACQksIOcCAHcDAAAA.Kayserdh:BAAALgAECgYJDgAAAA==.Kazaf:BAAALgAECgQJDgAAAA==.',
Ke='Keeirian:BAAALgADCgEJAQAAAA==.Keikoh:BAAALgAECgcJEgABLgAECggJGAASACQbAA==.Keitrek:BAABLgAECn8bAAIIAAgJfQd3DAB4AQAIAAgJfQd3DAB4AQAAAA==.Kelthias:BAAALgADCgYJCgAAAA==.Kelypsoc:BAAALgAECgQJBgAAAA==.Kenichï:BAAALgAECgUJCQABLgAECgYJBwAEAAAAAA==.Keomag:BAAALgAECgQJBwAAAA==.Kerwîck:BAAALgAECgcJBwAAAA==.Keyen:BAAALgAECgcJEwAAAA==.',
Kh='Khallan:BAAALgAECgYJEgAAAA==.Khazsz:BAABLgAECn8ZAAMYAAYJMiK2BwA6AgAYAAYJMiK2BwA6AgAgAAMJ/RSmJACuAAAAAA==.',
Ki='Kibalion:BAAALgAECgYJCwAAAA==.Kiljaezyn:BAAALgAECgEJAgAAAA==.Killbent:BAAALgAECgMJAwAAAA==.Kilowatts:BAAALgADCgYJBgAAAA==.Kimjongwork:BAAALgAECgEJAQABLgAECgcJEAAEAAAAAA==.Kinnky:BAAALgAECgYJEQAAAA==.Kino:BAAALgAECgUJCQAAAA==.Kiratsuna:BAAALgAECgYJBgAAAA==.Kiriya:BAAALgAECgYJCwAAAA==.Kismiasu:BAAALgAECgEJAQAAAA==.Kitticakes:BAAALgADCgUJBQAAAA==.Kivdruid:BAABLgAECn8XAAMRAAgJ9xgEBABUAgARAAgJ9xgEBABUAgAbAAIJGw/tbwBfAAAAAA==.Kivpriest:BAAALgADCgUJBQABLgAECggJFwARAPcYAA==.',
Kk='Kkty:BAAALgADCgQJBwAAAA==.',
Ko='Koore:BAAALgAECgYJEgAAAA==.Korraavatar:BAAALgAECgIJAgAAAA==.',
Kp='Kpop:BAAALgAECgYJDwAAAA==.Kpopkhan:BAABLgAECn8VAAIZAAgJJQzXHQAYAQAZAAgJJQzXHQAYAQAAAA==.',
Kr='Kreettip:BAABLgAECn8ZAAINAAgJ9A8aLACXAQANAAgJ9A8aLACXAQAAAA==.',
Ku='Kugamoo:BAABLgAECn8dAAIbAAgJrxbSCABkAQAbAAgJrxbSCABkAQAAAA==.Kulgen:BAAALgADCgIJAgAAAA==.Kurgen:BAAALgAECgYJDwAAAA==.',
Ky='Kylex:BAAALgAECgEJAQAAAA==.',
['Kà']='Kàkárót:BAAALgADCgcJCgAAAA==.',
La='Lamasacre:BAAALgAECgEJAQAAAA==.Lannybarby:BAAALgAECgYJEQAAAA==.Laotzu:BAABLgAECn8ZAAMVAAgJ0gi2LgBNAQAVAAcJNQm2LgBNAQAWAAgJ7AN5JwA4AQAAAA==.',
Lc='Lckdown:BAAALgAECgcJCQAAAA==.',
Le='Legomyegolas:BAAALgAECgcJCwAAAA==.Leviticus:BAAALgADCgEJAQAAAA==.',
Li='Liara:BAAALgADCgEJAQAAAA==.Licentious:BAAALgADCgIJAgAAAA==.Lightsauce:BAAALgAECgYJCQAAAA==.Lilianis:BAAALgAECgIJAgAAAA==.Lilybloom:BAAALgAECgQJBAAAAA==.',
Lo='Loden:BAACLgAFFH8KAAIhAAQJDxl8EQBbAQAhAAQJDxl8EQBbAQAuAAQKfxoAAiEACAnUIAQZAOYCACEACAnUIAQZAOYCAAAA.Lodex:BAAALgAECgEJAQAAAA==.Lokthal:BAAALgADCgYJBgAAAA==.Lovi:BAAALgAECggJEwAAAA==.',
Lu='Lucifero:BAAALgAECgYJCgAAAA==.Luckyboi:BAAALgAECgYJEAAAAA==.Luckymonk:BAAALgAECggJDwABLgAECgYJEAAEAAAAAA==.Lumina:BAAALgAECgYJCQAAAA==.Lusciifi:BAACLgAFFH8NAAIHAAUJ6SIHAQCcAQAHAAUJ6SIHAQCcAQAuAAQKfyUAAgcACAnUJRUGAGwDAAcACAnUJRUGAGwDAAAA.Luvva:BAAALgAECgIJAgAAAA==.',
Ly='Lykie:BAABLgAECn8fAAITAAgJIxz8BwBbAgATAAgJIxz8BwBbAgAAAA==.Lyllith:BAAALgADCgYJBgAAAA==.Lyone:BAAALgAECgYJCQAAAA==.',
['Lú']='Lúvaa:BAABLgAECn8dAAMhAAcJeCKfLgB+AgAhAAcJmyCfLgB+AgAiAAMJPSOfJAAbAQAAAA==.',
Ma='Maahun:BAAALgAECgEJAQAAAA==.Maficwar:BAABLgAECn8jAAIXAAgJ4BYwDABJAgAXAAgJ4BYwDABJAgAAAA==.Mageyuwu:BAAALgADCgcJCAAAAA==.Magikkisback:BAAALgAECgcJDAAAAA==.Manarez:BAAALgAECgYJCgAAAA==.Mandorius:BAAALgAECgYJDAAAAA==.Manywagons:BAAALgAECgcJDQABLgAFFAgJIQAFADMiAA==.Mariora:BAAALgAECgEJAQAAAA==.Masacre:BAAALgAECgQJCAAAAA==.Mavalynal:BAAALgADCgcJEgAAAA==.Mavidari:BAABLgAECn8gAAIZAAgJDB4CCQDjAQAZAAgJDB4CCQDjAQAAAA==.',
Mc='Mchammered:BAAALgADCgMJBgAAAA==.',
Me='Meeshie:BAABLgAECn8gAAMNAAgJZBo4EABkAgANAAgJZBo4EABkAgAMAAUJLhDjEACaAAAAAA==.Meleys:BAAALgADCgcJCAAAAA==.',
Mi='Midoriya:BAACLgAFFH8IAAMDAAMJtCZeBgBVAQADAAMJtCZeBgBVAQACAAEJNhdYEwBYAAAuAAQKfxoABAMACAl+Jvc6ACACAAMABQmWJvc6ACACAAIAAwn5JZghAEgBABwAAQktJhwgAHIAAAAA.Mightyhunts:BAAALgAECgMJBAAAAA==.Mikuzume:BAAALgAECgMJAwAAAA==.Milkmage:BAABLgAECn8WAAIFAAgJ5he3CwD0AQAFAAgJ5he3CwD0AQAAAA==.Mintt:BAAALgAECgEJAQAAAA==.Mishima:BAAALgADCgMJAwAAAA==.Miznewbooty:BAABLgAECn8hAAMMAAgJQg4FBQDCAQAMAAgJQg4FBQDCAQASAAQJog5LRADaAAAAAA==.',
Mo='Monknack:BAAALgAECgEJAQAAAA==.Moondofrond:BAAALgADCgkJCQAAAA==.Moonq:BAAALgAECgYJDAAAAA==.Moorti:BAAALgAECgYJDwAAAA==.Moosaurus:BAABLgAECn8UAAIjAAcJ9BPfDQB3AQAjAAcJ9BPfDQB3AQAAAA==.Mosrael:BAAALgADCgEJAgAAAA==.',
Mu='Muffy:BAAALgAECgYJCQAAAA==.Multishoted:BAAALgADCgEJAQAAAA==.Murlouh:BAAALgADCgUJCAAAAA==.Mushudoobey:BAAALgAECgIJAgABLgAECggJGwAFAC8fAA==.',
My='Mylthrad:BAAALgADCgMJAwAAAA==.Mythnarra:BAACLgAFFH8GAAIjAAIJeST3AADaAAAjAAIJeST3AADaAAAuAAQKfyIAAiMACAk5JCkAAOQCACMACAk5JCkAAOQCAAAA.',
['Mí']='Mísanthrope:BAAALgAECgIJAgAAAA==.',
['Mô']='Mônster:BAAALgAECgUJCQAAAA==.',
['Mö']='Mönk:BAACLgAFFH8FAAIaAAMJthfaCgD8AAAaAAMJthfaCgD8AAAuAAQKfxoAAhoACAkqHsUMAIcCABoACAkqHsUMAIcCAAAA.',
['Mø']='Mønstèr:BAAALgAECgMJAwAAAA==.',
Na='Nachtimbess:BAAALgADCgYJBgABLgAECggJEwAEAAAAAA==.Nadaline:BAAALgADCgcJBwAAAA==.Nadíne:BAABLgAECn8ZAAIFAAgJYB86QwBuAgAFAAgJYB86QwBuAgAAAA==.Naha:BAAALgAECgcJBgAAAA==.Naimi:BAAALgAECgQJBQAAAA==.Nanukimon:BAAALgAECgYJDAAAAA==.Nastymcdirty:BAAALgADCgcJBwAAAA==.',
Ne='Nelivath:BAAALgAECgEJAQAAAA==.Nene:BAAALgAECgUJCgAAAA==.Nevaera:BAAALgAECgcJDAAAAA==.',
Ni='Nichan:BAAALgAECgEJAwAAAA==.Nick:BAACLgAFFH8ZAAMhAAUJLBygBABrAQAhAAQJLBygBABrAQAiAAEJAAAxFwA+AAAuAAQKfy0AAiEACQmSI/4EAIQDACEACQmSI/4EAIQDAAAA.Nightcraft:BAAALgAECgEJAQAAAA==.Nightshine:BAAALgAECgYJEAAAAA==.Nikor:BAAALgAECgMJBQAAAA==.Nisan:BAAALgADCgcJBwAAAA==.',
No='Nocabevoli:BAAALgADCgUJBQABLgAECgIJAwAEAAAAAA==.Nokorii:BAAALgAECgYJDwAAAA==.Nomecoma:BAAALgAECgQJAQAAAA==.Norgatha:BAAALgAECgQJBQAAAA==.Notches:BAAALgADCgUJCwAAAA==.Nowheres:BAAALgAECgIJAgABLgAECgUJBQAEAAAAAA==.Noxturn:BAAALgAECgYJEQAAAA==.',
Ny='Nyxx:BAAALgAECgYJBwABLgAECgUJCQAEAAAAAA==.',
['Nè']='Nèlo:BAAALgAECgYJEgAAAA==.',
Oc='Oceansoul:BAAALgAECgYJDQAAAA==.',
Oh='Ohh:BAAALgADCgMJAQAAAA==.',
Ok='Ok:BAAALgADCgYJCgAAAA==.',
On='Ondestra:BAAALgAECgIJAgAAAA==.',
Op='Oppenheimerx:BAAALgADCgMJBQAAAA==.',
Or='Orave:BAAALgAECgMJBQAAAA==.Origin:BAAALgADCgYJDAAAAA==.Orionah:BAAALgAECgQJBAAAAA==.',
Os='Osywar:BAAALgAECgYJEwABLgAECggJEwAEAAAAAA==.',
Ou='Oulawdpriest:BAACLgAFFH8HAAISAAMJfgnIDADdAAASAAMJfgnIDADdAAAuAAQKfygABBIACAl6HkcMAL4CABIACAl6HkcMAL4CAAwAAgk4HE9DAJoAAA0AAQkfIWBzAFoAAAAA.',
Ov='Overture:BAAALgAECgUJDgAAAA==.',
Pa='Panacea:BAAALgAECgYJCQAAAA==.Parkour:BAAALgAECgYJEAAAAA==.Pastorale:BAAALgADCgYJBgABLgAECggJGQAVANIIAA==.Paullymorph:BAABLgAECn8aAAIFAAgJxyEbBQBlAgAFAAgJxyEbBQBlAgAAAA==.Pawpawbear:BAAALgADCgEJAQAAAA==.Payal:BAAALgADCgQJBAABLgAECggJHwADAI4aAA==.',
Ph='Phenyl:BAABLgAECn8UAAIaAAgJOwY6DQAPAQAaAAgJOwY6DQAPAQAAAA==.',
Pi='Pithers:BAAALgAECgQJBgAAAA==.',
Po='Ponchohunter:BAAALgADCgEJAQAAAA==.Poohpocket:BAAALgADCgQJAwAAAA==.Popkorn:BAACLgAFFH8UAAMZAAUJHSbxAQCaAQAZAAQJHSbxAQCaAQAjAAEJAAAPBABqAAAuAAQKfyEABBkACQmcJbAQAPkCABkACQlxJbAQAPkCAB0ABQmUIbsqAHABACMAAQlnJW8iAG8AAAAA.Popkornvoke:BAAALgAECgEJAQABLgAFFAUJFAAZAB0mAA==.Poplocks:BAAALgADCgEJAwAAAA==.Porrana:BAAALgAECgYJDgAAAA==.Powaqa:BAAALgAECgcJEwAAAA==.',
Ps='Psydeath:BAAALgAECggJDQAAAA==.',
Pu='Pumpkinspice:BAAALgAECgUJBQAAAA==.Punchkin:BAABLgAECn8YAAMaAAgJeBmBAwAUAgAaAAgJeBmBAwAUAgAkAAEJWwJBiQAmAAAAAA==.Puzzledmonk:BAAALgADCgcJDQAAAA==.',
Qu='Quasient:BAAALgAECgQJBAAAAA==.Quickspell:BAABLgAECn8bAAIFAAYJtyCrEQC1AQAFAAYJtyCrEQC1AQAAAA==.Quickstep:BAAALgAECgkJBwAAAA==.',
Ra='Rabidpopcorn:BAAALgADCgcJBwAAAA==.Radaghast:BAAALgAECgYJDAAAAA==.Raedyyn:BAAALgAECgYJEQAAAA==.Ragarth:BAAALgAECgUJBQAAAA==.Ragendecay:BAAALgAECgYJEgAAAA==.Ragequits:BAACLgAFFH8SAAMOAAcJ2R82AABdAgAOAAYJRCM2AABdAgAlAAIJvRAJCgBbAAAuAAQKfx8AAw4ACQlBJpYAAN4DAA4ACQlBJpYAAN4DACUAAQm/JiAxAG8AAAAA.Ragæ:BAAALgAECgUJBgAAAA==.Rakshassa:BAAALgAECgYJEgAAAA==.Ralcar:BAAALgAECgUJCwAAAA==.Razrscale:BAAALgADCgcJCwAAAA==.',
Re='Regrow:BAAALgAECgQJBAAAAA==.',
Rh='Rheas:BAAALgAECgIJAQAAAA==.Rholdentodor:BAAALgADCgUJBQABLgAECgYJBwAEAAAAAA==.',
Ro='Rockabye:BAAALgAECgUJBQABLgAFFAMJBAAEAAAAAA==.Rohra:BAABLgAECn8WAAIRAAYJcxDgYQAsAQARAAYJcxDgYQAsAQAAAA==.Rombaz:BAAALgAECgcJCAAAAA==.Ronspoomage:BAAALgADCgkJEQAAAA==.Rosemary:BAAALgADCgQJBAAAAA==.Roóz:BAAALgAECgQJDgAAAA==.',
Ru='Ruah:BAAALgADCgMJAwAAAA==.Runecast:BAAALgADCgcJFQAAAA==.',
Ry='Rynk:BAABLgAECn8hAAIQAAgJZCTrAACnAgAQAAgJZCTrAACnAgAAAA==.Ryuoxel:BAAALgADCgEJAQAAAA==.',
['Rá']='Rágnarok:BAAALgADCgMJAwAAAA==.Ráwkfist:BAABLgAFFH8HAAIVAAUJBxIKCQDzAAAVAAUJBxIKCQDzAAAAAA==.',
Sa='Sabbybunnee:BAAALgADCgcJDAAAAA==.Sabertrek:BAAALgADCgMJAwAAAA==.Saelyrinth:BAAALgADCgUJCAAAAA==.Saltybonez:BAAALgADCgUJBQAAAA==.Sambor:BAAALgAECgkJCQAAAA==.Sarapheena:BAABLgAECn8fAAIBAAgJnxMDCwCNAQABAAgJnxMDCwCNAQAAAA==.Saravian:BAAALgADCgUJBQAAAA==.Sardeench:BAAALgAECgEJAQAAAA==.Satanbomb:BAAALgAECgEJAQAAAA==.Satansbride:BAAALgAECgEJAQABLgAECgQJBAAEAAAAAA==.Saterli:BAABLgAECn8lAAMNAAgJjQ0SKgCiAQANAAgJjQ0SKgCiAQASAAYJaAM7FQCtAAAAAA==.Saturno:BAAALgAECgUJBgAAAA==.Saucypirate:BAAALgAECgQJCgAAAA==.Saulgoodman:BAAALgADCgMJAwAAAA==.Sauronknight:BAAALgAFFAMJBAAAAA==.',
Sc='Scalvert:BAAALgAECgYJBwAAAA==.Scalypanda:BAABLgAECn8fAAMVAAgJGhNmBQCtAQAVAAgJGhNmBQCtAQAUAAIJ0gzLNABuAAAAAA==.Scamander:BAAALgAECgcJBgABLgAECggJIQADAC4YAA==.Scarléth:BAAALgADCggJCgAAAA==.Scoobs:BAAALgAECgIJAgAAAA==.Scorpinom:BAAALgADCgQJBAAAAA==.Sculi:BAAALgADCgcJBwAAAA==.Scurge:BAAALgAECgIJAgAAAA==.Scuttle:BAAALgADCgIJBAABLgAECgYJDAAEAAAAAA==.',
Se='Seiishiro:BAAALgAECgYJEwAAAA==.Seldon:BAAALgAECgYJEQAAAA==.Sennistian:BAAALgADCgMJBAABLgAECgcJFwAcAIYMAA==.Seraphiel:BAAALgAECgQJBAABLgAECgYJBgAEAAAAAA==.Seraphymm:BAAALgAECgIJBAAAAA==.',
Sh='Shacklebolt:BAABLgAECn8hAAMDAAgJLhjtJAB/AgADAAgJLhjtJAB/AgACAAQJWg/AMwDoAAAAAA==.Shadowsneak:BAAALgAECgUJDgAAAA==.Shaelistra:BAAALgAECgYJEAAAAA==.Shalai:BAAALgADCggJDgAAAA==.Shalilama:BAACLgAFFH8JAAIBAAQJTh2fBAAnAQABAAQJTh2fBAAnAQAuAAQKfywAAgEACQkgJOEAAJ4DAAEACQkgJOEAAJ4DAAAA.Shanazure:BAABLgAECn8YAAMUAAcJHBc4EwCvAQAUAAcJyhM4EwCvAQAVAAUJYhdQMQA9AQAAAA==.Sheikai:BAAALgADCgcJEgAAAA==.Shenderp:BAAALgAECgUJDwAAAA==.Shinerbock:BAAALgAECgYJCgAAAA==.Shivä:BAAALgADCgcJCgABLgAECgYJDwAEAAAAAA==.Shriven:BAAALgAECgIJAgAAAA==.',
Si='Sianvar:BAAALgAECgUJCAAAAA==.Silvanus:BAAALgADCgQJBwAAAA==.Silverjustis:BAAALgAECgcJEwAAAA==.Siwe:BAABLgAECn8XAAQBAAgJYBuwAwBBAgABAAcJlxywAwBBAgAPAAYJjhmHEgCOAQAGAAEJpBJMgwA8AAAAAA==.',
Sk='Skadoosh:BAAALgAECgYJDAAAAA==.Skribblez:BAAALgAECgYJEwAAAA==.Skrilled:BAABLgAECn8cAAILAAYJLQ4TGgAsAQALAAYJLQ4TGgAsAQAAAA==.',
Sl='Slackback:BAAALgAECgkJBAABLgAFFAIJBQAGAFkTAA==.Sloot:BAAALgAECgYJCQAAAA==.Slughorn:BAAALgAECgcJBQABLgAECggJIQADAC4YAA==.Slyv:BAAALgADCgcJBwAAAA==.',
Sm='Smellidan:BAAALgADCgEJAwAAAA==.Smïte:BAAALgAECgUJBQAAAA==.',
Sn='Snape:BAAALgADCgYJBgAAAA==.Snowcones:BAAALgAECgcJDAAAAA==.Snowman:BAAALgAECgMJBQAAAA==.Snw:BAAALgADCgUJAwAAAA==.',
So='Soul:BAABLgAECn8ZAAIgAAgJzCHPBADKAgAgAAgJzCHPBADKAgAAAA==.Soulls:BAAALgAECgIJAgAAAA==.Soulsy:BAAALgAECgEJAgAAAA==.Sourgrip:BAABLgAECn8aAAIeAAgJmhYSAQDWAQAeAAgJmhYSAQDWAQAAAA==.',
Sp='Splendorae:BAABLgAECn8fAAIIAAgJSROdIwAFAgAIAAgJSROdIwAFAgAAAA==.Sprints:BAABLgAECn8YAAIBAAcJShacKADuAQABAAcJShacKADuAQAAAA==.Spritz:BAAALgAECgEJAQAAAA==.Sprylf:BAAALgADCgMJBAAAAA==.Spwany:BAABLgAECn8VAAQOAAgJ3ArwDABTAQAOAAcJeQXwDABTAQAXAAUJoA0UKgDwAAAlAAEJAACHFwAAAAAAAA==.Spyderelite:BAABLgAECn8gAAICAAgJ7xGpAQCiAQACAAgJ7xGpAQCiAQAAAA==.',
Sq='Squeekems:BAAALgAECgIJAwAAAA==.Squirrel:BAAALgAECgkJDQAAAA==.',
St='Stainedhero:BAAALgADCgEJAQAAAA==.Stankstarstu:BAAALgADCgYJCAABLgAECgQJBAAEAAAAAA==.Starspeaker:BAAALgAECgYJDAAAAA==.Steveaustin:BAAALgAECgMJBAABLgAECgYJDAAEAAAAAA==.Stinkypeen:BAAALgAECgIJAgAAAA==.Stonecypher:BAAALgAECgYJCgAAAA==.Stoogotz:BAAALgADCgYJCAAAAA==.Stormlesbian:BAAALgADCgUJBQAAAA==.',
Su='Sunwing:BAABLgAECn8fAAINAAgJbRyQDwBqAgANAAgJbRyQDwBqAgAAAA==.Sutileza:BAAALgADCgMJAwABLgAECgUJDgAEAAAAAA==.Suvien:BAAALgAECgIJAQAAAA==.',
Sw='Swagette:BAAALgADCgcJBwAAAA==.Swingkitti:BAAALgAECgQJBgAAAA==.',
Sx='Sxtitan:BAAALgAECggJEAAAAA==.',
Sy='Sylvarian:BAAALgAECgYJEwAAAA==.Syrodeus:BAAALgADCgEJAQAAAA==.',
Sz='Szz:BAABLgAECn8cAAIUAAgJnCUdAADiAgAUAAgJnCUdAADiAgAAAA==.',
['Sÿ']='Sÿn:BAAALgADCgcJFwAAAA==.',
Ta='Taelgar:BAAALgAECgcJDAAAAA==.Targaryenelf:BAAALgADCgMJAwAAAA==.Taterdotz:BAAALgAECgcJEgAAAA==.Tatyrra:BAAALgADCgUJBQAAAA==.Tayswift:BAAALgADCgQJBAABLgAECgUJBwAEAAAAAA==.',
Te='Tenast:BAAALgADCgIJAgAAAA==.Tepicoyotl:BAAALgAECgYJEwAAAA==.',
Th='Thaymor:BAAALgADCggJEQAAAA==.Thelonecone:BAACLgAFFH8IAAMhAAMJXxIBJQABAQAhAAMJXxIBJQABAQAeAAEJwwoOBABVAAAuAAQKfzoAAyEACAkLJIMVAPsCACEACAkfIoMVAPsCAB4ACAlfIhsBAM8BAAAA.Theoganth:BAAALgAECgEJAQAAAA==.Theraphee:BAAALgADCgcJDQAAAA==.Therimor:BAAALgAECgcJEgAAAA==.Theronshan:BAAALgADCgQJBAAAAA==.Thomwizard:BAAALgAECgMJAwAAAA==.Thongrin:BAAALgADCgcJBwAAAA==.Thormorn:BAAALgADCgEJAgAAAA==.Thornarlenan:BAAALgADCgkJDgAAAA==.Thunnha:BAAALgAFFAEJAQAAAA==.Thurlando:BAAALgADCgIJBAAAAA==.',
To='Toastedsushi:BAAALgAECgMJAwAAAA==.Toetagg:BAAALgADCgUJCAAAAA==.Toobooku:BAAALgADCgEJAQAAAA==.Toofwess:BAAALgADCgkJCQABLgAECgYJDAAEAAAAAA==.Torí:BAAALgADCgUJBgAAAA==.Tosala:BAAALgAECgQJBwAAAA==.Totemkiller:BAAALgAECgcJEwAAAA==.Totemtwiddlr:BAABLgAECn8UAAIGAAgJuRzHFAB3AgAGAAgJuRzHFAB3AgAAAA==.',
Tr='Traael:BAAALgAECgYJEAAAAA==.Trashbeard:BAAALgADCgIJAgAAAA==.Treesap:BAABLgAECn8fAAImAAgJAxt6AQDHAgAmAAgJAxt6AQDHAgAAAA==.Trinityeve:BAAALgAECgEJAQAAAA==.Trnz:BAAALgAECggJEAABLgAECggJFAAGALkcAA==.Trnzlock:BAAALgAECgIJAwAAAA==.',
Tu='Tularana:BAAALgAECggJEwAAAA==.Tumble:BAAALgAECgcJEwAAAA==.Tummyissues:BAAALgAECgIJAgAAAA==.Tums:BAAALgAECgMJBQAAAA==.',
Tw='Twignberryz:BAAALgADCgQJBwABLgAECgQJBAAEAAAAAA==.Twinkie:BAAALgAECgYJEgAAAA==.Twodogz:BAAALgAECgYJEwAAAA==.',
Ty='Tyious:BAABLgAECn8gAAMhAAgJ7xu5BgAXAgAhAAgJ7xu5BgAXAgAiAAUJBQyPLADaAAAAAA==.Tyndara:BAAALgAECgYJEAAAAA==.',
['Tü']='Tüesdaÿ:BAAALgAECgcJCwAAAA==.',
Un='Unbeat:BAAALgAECgYJDAAAAA==.Unhoe:BAAALgADCggJEgAAAA==.Unholussie:BAABLgAECn8iAAIhAAgJeBk2CAD8AQAhAAgJeBk2CAD8AQAAAA==.Unholybowner:BAAALgADCgcJDAAAAA==.Unstablè:BAAALgADCgkJDgAAAA==.',
Ur='Ursane:BAABLgAECn8eAAIOAAcJFBnnBgC1AQAOAAcJFBnnBgC1AQAAAA==.Ursully:BAAALgAECgYJEAAAAA==.',
Uz='Uzi:BAAALgAECgQJBAAAAA==.',
Va='Vaardux:BAAALgAECgYJEAAAAA==.Vaelithra:BAAALgADCgEJAQAAAA==.Valamarl:BAAALgADCgcJCAAAAA==.Valkeria:BAAALgAECgEJAQAAAA==.Vampulla:BAABLgAECn8ZAAIZAAgJSgZiIQACAQAZAAgJSgZiIQACAQAAAA==.Vanncint:BAAALgAECgQJBAAAAA==.Vanndrygos:BAAALgAECgQJBAAAAA==.Varea:BAAALgAECgIJAgAAAA==.Vashie:BAAALgAECggJDAAAAA==.',
Ve='Veigar:BAAALgAECgcJBwAAAA==.Velanis:BAAALgADCgUJBwAAAA==.Velmir:BAAALgAECgkJBwAAAA==.Velorius:BAAALgAECgEJAgAAAA==.Vexus:BAACLgAFFH8FAAIGAAIJWRP7CQCeAAAGAAIJWRP7CQCeAAAuAAQKfyEAAgYACAmKI7sJAPcCAAYACAmKI7sJAPcCAAAA.Vexuss:BAAALgAECgkJAgABLgAFFAIJBQAGAFkTAA==.',
Vi='Vidya:BAAALgADCgMJAwAAAA==.',
Vl='Vladios:BAAALgAECgQJBAAAAA==.',
Vo='Voidwraith:BAAALgADCgEJAQAAAA==.Vordarian:BAAALgAECggJEwAAAA==.',
Vy='Vynciaagn:BAAALgADCgcJEgAAAA==.',
Wa='Wafflehouse:BAAALgAECgYJDAAAAA==.Walolas:BAAALgADCgcJEAAAAA==.Watchmeburst:BAAALgADCgUJBQAAAA==.',
We='Weeb:BAAALgADCgEJAQAAAA==.',
Wh='Whaler:BAAALgAECgcJEwAAAA==.Whìndy:BAAALgAECgMJAwABLgAECgQJBAAEAAAAAA==.',
Wi='Wildspanks:BAAALgADCgYJCQAAAA==.',
Xe='Xenyodk:BAABLgAECn8WAAIhAAgJ8RtfBwAKAgAhAAgJ8RtfBwAKAgAAAA==.',
Xi='Xideris:BAABLgAECn8hAAIWAAgJjh/AAAClAgAWAAgJjh/AAAClAgAAAA==.',
Xt='Xtraxtra:BAABLgAECn8aAAIRAAgJZhm8HABWAgARAAgJZhm8HABWAgAAAA==.',
Ya='Yaku:BAAALgAECgUJCAAAAA==.',
Ye='Yetzi:BAAALgADCgIJAgAAAA==.Yetzibel:BAAALgADCgQJBAAAAA==.',
Yo='Yoan:BAAALgAECggJHgAAAQ==.Yoga:BAAALgADCgkJCwAAAA==.Yonicbonnet:BAAALgAECgYJDAAAAA==.Yoondo:BAAALgAECgUJBwAAAA==.Yorde:BAAALgADCgcJBwAAAA==.',
Ys='Yshtola:BAAALgAECgYJCwAAAA==.',
Yu='Yuffie:BAAALgAECgQJBAAAAA==.Yunara:BAABLgAECn8aAAIZAAcJKR53CgDMAQAZAAcJKR53CgDMAQAAAA==.',
Za='Zabra:BAAALgAECgQJBwAAAA==.Zachpally:BAAALgADCgUJBQAAAA==.Zahvoker:BAAALgAECgMJBQAAAA==.Zapkitti:BAAALgADCgQJBAAAAA==.Zareline:BAAALgAECgQJBAAAAA==.Zathaeus:BAABLgAECn8VAAIZAAkJHBNfGQA1AQAZAAkJHBNfGQA1AQAAAA==.Zaylian:BAABLgAECn8WAAIdAAcJkxbuFwAIAgAdAAcJkxbuFwAIAgAAAA==.Zayragossa:BAAALgAFFAIJAwAAAA==.',
Ze='Zeerkk:BAABLgAECn8cAAIDAAgJhRUwCgDQAQADAAgJhRUwCgDQAQAAAA==.Zelanta:BAAALgADCgQJBAAAAA==.Zergmark:BAAALgADCgMJAwAAAA==.Zero:BAAALgADCgIJAgAAAA==.',
Zo='Zouris:BAAALgAECgIJAgAAAA==.',
Zt='Ztaziki:BAAALgADCgQJBAAAAA==.',
Zu='Zulkraa:BAAALgADCggJDgAAAA==.Zulmex:BAAALgAECgUJBQAAAA==.Zunda:BAAALgAECgcJBgAAAA==.Zurtogg:BAAALgAECgYJEgAAAA==.',
['Ön']='Öndi:BAAALgADCgYJBgAAAA==.',
['ßr']='ßrûh:BAAALgADCgEJAQAAAA==.',
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

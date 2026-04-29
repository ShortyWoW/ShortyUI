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

local lookup = {'Evoker-Augmentation','Evoker-Devastation','Unknown-Unknown','Mage-Arcane','Monk-Mistweaver','Paladin-Retribution','Priest-Holy','Priest-Shadow','DeathKnight-Unholy','DeathKnight-Blood','Monk-Brewmaster','Hunter-BeastMastery','Hunter-Marksmanship','Warrior-Fury','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Mage-Frost','Shaman-Restoration','Monk-Windwalker','DemonHunter-Devourer','DemonHunter-Vengeance','Warrior-Protection','Paladin-Holy','Druid-Guardian','Shaman-Elemental','Druid-Restoration','Druid-Balance','Rogue-Subtlety','Evoker-Preservation','Hunter-Survival','Shaman-Enhancement','Rogue-Assassination',}
local provider = {region='US',realm='BloodFurnace',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Aborc:BAAALgAECgQJCAAAAA==.Abraxøs:BAACLgAFFH8FAAIBAAQJKQ/vBABDAQABAAQJKQ/vBABDAQAuAAQKfxUAAwIACAnpHRQKAD0CAAIABwl5HhQKAD0CAAEAAQmHGsFaAFEAAAAA.',
Ad='Adiris:BAAALgADCgYJBgAAAA==.Aduranu:BAAALgAECgcJBwAAAA==.',
Ae='Aegeax:BAAALgAECgMJBwAAAA==.Aethers:BAAALgADCgYJBwAAAA==.Aethrion:BAAALgADCgQJBAAAAA==.',
Ai='Aiou:BAAALgAECgQJBwABLgAFFAEJAQADAAAAAA==.Airtrun:BAAALgADCgEJAQAAAA==.',
Al='Alaalla:BAAALgAECgUJCgAAAA==.Alasttra:BAAALgAECgUJCAAAAA==.Alesallie:BAAALgAECgQJBgAAAA==.Alexie:BAAALgAECgQJCQAAAA==.Alleriand:BAAALgADCgcJBwAAAA==.Alleryn:BAAALgADCgYJCQAAAA==.Alpine:BAAALgAECggJCwAAAA==.Alunaarn:BAAALgADCgMJCQAAAA==.',
Am='Amandagarcia:BAAALgAECgQJBAABLgAFFAEJAQADAAAAAA==.Ambermage:BAAALgADCgUJDQAAAA==.Amerese:BAAALgADCgEJAQAAAA==.Amourantha:BAAALgADCgUJCAAAAA==.',
An='Andersdame:BAAALgAECgYJEwAAAA==.Anrot:BAAALgADCgUJBgAAAA==.Anthonyisme:BAAALgAECgYJDgAAAA==.',
Ao='Aon:BAAALgAECgIJAgAAAA==.',
Ar='Araels:BAAALgAECgYJEQAAAA==.Arindoril:BAAALgADCgYJDAAAAA==.Arktyh:BAABLgAECn8cAAIEAAcJaRuSAwAwAgAEAAcJaRuSAwAwAgAAAA==.Aryndinnin:BAACLgAFFH8JAAIFAAQJ3gpVCQAhAQAFAAQJ3gpVCQAhAQAuAAQKfx8AAgUACAkWHagLAJkCAAUACAkWHagLAJkCAAAA.',
As='Asdar:BAAALgAECgYJCAAAAA==.Asherah:BAABLgAECn8WAAMCAAkJ+woGGgBkAQACAAcJHgwGGgBkAQABAAYJUgnLFwCJAAAAAA==.Ashketchums:BAAALgADCgcJBwAAAA==.Astralrepaul:BAAALgAECgYJDwAAAA==.',
At='Attincy:BAAALgADCggJDQAAAA==.',
Au='Augtistic:BAACLgAFFH8GAAIBAAMJBxmoEAD8AAABAAMJBxmoEAD8AAAuAAQKfxYAAgEACAlJIjQKANMCAAEACAlJIjQKANMCAAAA.',
Ax='Axelofóðinn:BAABLgAECn8dAAIGAAgJdw35awCmAQAGAAgJdw35awCmAQAAAA==.',
Ay='Ayah:BAABLgAECn8WAAMHAAcJyRZ0KQCmAQAHAAcJyRZ0KQCmAQAIAAMJ6AryFACwAAAAAA==.Ayayrahn:BAAALgAECgMJAgAAAA==.',
Az='Azerfrost:BAAALgAECgEJAQABLgAECgEJAgADAAAAAA==.Azogothar:BAAALgADCggJFAAAAA==.Aztinuz:BAAALgADCgUJBQAAAA==.',
Ba='Babygerl:BAAALgADCgIJAgAAAA==.Badbuny:BAAALgAECgYJCwAAAA==.Badger:BAAALgAECgMJAwAAAA==.Bahlz:BAAALgADCggJDQAAAA==.Bareca:BAAALgAECgUJBAAAAA==.',
Be='Bearenstein:BAAALgAECgQJBAAAAA==.Beccaw:BAAALgADCgUJCAAAAA==.Beccky:BAAALgADCgEJAQAAAA==.Beginners:BAAALgADCgEJAQAAAA==.Benthelius:BAAALgADCgkJEAAAAA==.Bestial:BAAALgADCgkJDwAAAA==.Bevicia:BAAALgAECgYJDAAAAA==.',
Bi='Biggrim:BAAALgAECgIJAgAAAA==.Biiwaabik:BAAALgADCgcJDAAAAA==.Binkey:BAAALgADCgQJBAAAAA==.Bitsotig:BAAALgAECgEJAQAAAA==.',
Bl='Blap:BAAALgADCgEJAQAAAA==.Blemish:BAAALgAECgMJBgAAAA==.Bloodfm:BAAALgAECgMJAwAAAA==.Bloodlordz:BAAALgADCgYJDQAAAA==.Bloodology:BAAALgAECgEJAgABLgAECgQJBQADAAAAAA==.Bloodscum:BAAALgADCgcJCAAAAA==.Bloodsham:BAAALgAECgQJBQAAAA==.Blordz:BAAALgADCgYJCwAAAA==.Bluelicht:BAABLgAECn8bAAIJAAcJEhueTgAHAgAJAAcJEhueTgAHAgAAAA==.Bluphantom:BAAALgAECgIJBAAAAA==.',
Bo='Boodiica:BAABLgAECn8VAAIKAAYJvRb6GgB3AQAKAAYJvRb6GgB3AQAAAA==.Bootyism:BAAALgAECgUJBgAAAA==.',
Br='Brauman:BAAALgAECgIJAgAAAA==.Braynia:BAAALgAECggJCwAAAA==.Brazo:BAABLgAECn8cAAILAAcJOCK3AwD1AQALAAcJOCK3AwD1AQAAAA==.Brazzinoth:BAAALgADCgEJAQABLgAECgcJHAALADgiAA==.Broxxigarr:BAAALgAECgEJAQAAAA==.',
Bu='Bucky:BAAALgADCgcJBwAAAA==.Buhlz:BAAALgAECgQJBwAAAA==.Bullybane:BAAALgAECgYJEwAAAA==.Buri:BAAALgAECgYJDwAAAA==.Buzzslc:BAAALgAECgQJBAAAAA==.',
By='Bytebait:BAAALgADCgUJBQAAAA==.',
Ca='Caelista:BAAALgADCgUJBQAAAA==.Calahunts:BAACLgAFFH8IAAIMAAMJFhA/DAAAAQAMAAMJFhA/DAAAAQAuAAQKfygAAwwACAlNJEwMAN8CAAwACAkfJEwMAN8CAA0AAglwIrFmAKQAAAAA.Calatath:BAAALgAECgMJBgABLgAFFAMJCAAMABYQAA==.Castiana:BAAALgADCgQJBAAAAA==.',
Ce='Celandria:BAAALgADCgkJFQAAAA==.Celical:BAAALgADCgMJAwAAAA==.Celize:BAAALgAECgYJDwAAAA==.Cerollan:BAAALgADCgUJBQAAAA==.',
Ch='Cheeto:BAAALgADCgYJCAAAAA==.Chenna:BAAALgAECgEJAwAAAA==.Chewwybot:BAAALgADCgMJAwAAAA==.Chifoxx:BAAALgAECgYJCwAAAA==.Chorgin:BAAALgADCgEJAQAAAA==.Chromaxion:BAAALgAFFAIJAgAAAA==.Chronic:BAABLgAECn8cAAIOAAkJFR+YDQDpAgAOAAkJFR+YDQDpAgAAAA==.Chrysostom:BAAALgAECggJEwAAAA==.Chwamz:BAABLgAECn8cAAMPAAgJZhsPKABxAgAPAAgJZhsPKABxAgAQAAEJAADRfAAiAAAAAA==.',
Ci='Ciphirion:BAAALgADCgYJBwAAAA==.',
Cl='Clivennik:BAAALgADCgEJAQAAAA==.Cloggy:BAACLgAFFH8OAAMPAAUJXSBwAgCNAQAPAAUJXSBwAgCNAQAQAAEJWx0YEgBbAAAuAAQKfyUABA8ACAnDJdQFAGADAA8ACAmCJdQFAGADABEABwn+IvMBALUCABAABQmdHlYQAMwBAAAA.Cloudshield:BAAALgAECgQJAgAAAA==.Clydell:BAAALgADCgIJAgAAAA==.',
Co='Coeus:BAAALgADCgMJAwAAAA==.Cokolo:BAAALgADCggJCAAAAA==.Coldflame:BAABLgAECn8jAAISAAgJqh9zIwDlAgASAAgJqh9zIwDlAgAAAA==.Corruption:BAAALgAECgYJCAAAAA==.Corruptmonk:BAAALgAECgEJAQAAAA==.Cowchucker:BAAALgAECgQJBAAAAA==.',
Cp='Cptboomerang:BAAALgAECgcJDwAAAA==.',
Cr='Crath:BAAALgAECgQJBAABLgAECggJEgADAAAAAA==.Crathdk:BAAALgAECggJEgAAAA==.Crathmonk:BAAALgAECgQJCgABLgAECggJEgADAAAAAA==.Creamfilling:BAAALgADCgYJBgAAAA==.Crispynugget:BAAALgADCgUJBQAAAA==.Crixo:BAAALgADCgUJBQAAAA==.Crownroyale:BAABLgAECn8fAAILAAgJWhnqAwDtAQALAAgJWhnqAwDtAQAAAA==.',
Cy='Cyrissa:BAABLgAECn8WAAISAAcJ9xGUowCRAQASAAcJ9xGUowCRAQAAAA==.',
Da='Dadlover:BAAALgAECgYJBgAAAA==.Daegu:BAABLgAECn8XAAITAAgJqA2pMADEAQATAAgJqA2pMADEAQAAAA==.Daenlan:BAAALgADCgQJBwAAAA==.Daeynora:BAAALgADCgEJAQAAAA==.Daityasfist:BAABLgAFFH8FAAIUAAMJJyE+BQA2AQAUAAMJJyE+BQA2AQAAAA==.Dalien:BAAALgADCgcJBwAAAA==.Dalinius:BAAALgAECgYJDgAAAA==.Dalonar:BAAALgADCgMJAwAAAA==.Dance:BAAALgADCgYJCwAAAA==.Darcine:BAAALgAECgQJCAAAAA==.Darkbojangle:BAAALgAECgEJAQAAAA==.Darkless:BAAALgAECgEJAQAAAA==.Dashmodius:BAABLgAECn8aAAMVAAcJmB5qCgDNAQAVAAcJUx5qCgDNAQAWAAEJkhwQJgBUAAAAAA==.Datfourloko:BAAALgAECgEJAgAAAA==.Dazing:BAAALgAECgIJAgAAAA==.',
De='Deamontsuki:BAAALgAECgYJCgAAAA==.Deceasedpi:BAAALgAECgUJCgAAAA==.Delaci:BAAALgAECgYJCAAAAA==.Delsid:BAAALgADCgUJBQAAAA==.Demonicbeilf:BAAALgADCgEJAQAAAA==.Demonster:BAAALgAECggJEAAAAA==.Denaian:BAAALgADCgEJAgAAAA==.Deohgee:BAAALgAECgQJBwAAAA==.Deranker:BAAALgAECgYJCwAAAA==.Desmus:BAAALgADCgUJBgAAAA==.Devourdeez:BAAALgAECgMJAwABLgAFFAYJFgAPAGsfAA==.Dezarath:BAAALgAECgUJBgAAAA==.',
Dh='Dhuumstar:BAAALgADCgcJBwAAAA==.',
Dk='Dkbuhlz:BAAALgAECgIJAgAAAA==.',
Do='Dotdude:BAAALgAECgYJBgAAAA==.',
Dr='Draganhammer:BAAALgAECggJEgAAAA==.Drakeath:BAAALgADCgcJBwAAAA==.Drakkarn:BAABLgAECn8UAAIXAAYJqw8zCQDzAAAXAAYJqw8zCQDzAAAAAA==.Draxina:BAAALgADCgYJBgAAAA==.Draxxton:BAAALgADCgcJBwAAAA==.Drdurty:BAABLgAECn8dAAIIAAgJshdXFABNAgAIAAgJshdXFABNAgAAAA==.Dreadhoof:BAAALgADCgkJDQAAAA==.Drewcifur:BAAALgAECgUJDQAAAA==.Droodar:BAAALgADCgUJBQAAAA==.Droopey:BAAALgADCgIJBAAAAA==.Dropxlife:BAAALgAECgQJBAAAAA==.Druttut:BAAALgADCgEJAQAAAA==.',
Du='Duckywg:BAAALgAECgYJCQAAAA==.Duskvoke:BAAALgAECgMJAwABLgAECgUJCwADAAAAAA==.Duskzen:BAAALgAECgUJCwAAAA==.Dusq:BAAALgAECgEJAQAAAA==.',
Ed='Edswell:BAAALgADCgYJBgAAAA==.',
Ei='Eilistraaee:BAABLgAECn8jAAIYAAgJDyK5CADjAgAYAAgJDyK5CADjAgAAAA==.',
Ek='Eki:BAAALgAECgIJAgAAAA==.Ekicarys:BAAALgADCgQJBAAAAA==.',
El='Elfayomega:BAAALgADCgEJAQABLgADCgQJBQADAAAAAA==.Elmencho:BAABLgAECn8WAAIJAAYJgRAenABIAQAJAAYJgRAenABIAQAAAA==.Eltiera:BAAALgAECgQJBQAAAA==.Elvenshot:BAAALgADCgMJAwAAAA==.Elyssa:BAAALgAECgYJCwAAAA==.',
Em='Emberfist:BAAALgADCgYJCQAAAA==.',
En='Endswell:BAAALgAECgEJAQAAAA==.Endszene:BAAALgADCgMJAwAAAA==.',
Er='Errorin:BAAALgAECgMJAwAAAA==.',
Es='Eskimo:BAAALgAECgQJBgAAAA==.Esquimaux:BAABLgAECn8WAAIGAAcJLxMwHQA/AQAGAAcJLxMwHQA/AQAAAA==.Essex:BAAALgAECgEJAQAAAA==.',
Et='Etchlock:BAAALgADCgkJDwAAAA==.Etheriademon:BAAALgADCgQJBAAAAA==.',
Ev='Eviannis:BAAALgAECgYJBwAAAA==.Evîe:BAAALgADCgQJBAAAAA==.',
Ew='Ewanae:BAAALgAECgQJBAABLgAECgkJFgACAPsKAA==.',
Ex='Extacee:BAAALgAECgEJAQAAAA==.',
Fa='Faerina:BAAALgADCgIJAgAAAA==.Faesonia:BAAALgAECgQJCgAAAA==.Fangthir:BAAALgADCgYJCAABLgAECgQJBAADAAAAAA==.Faoop:BAAALgADCgIJAgAAAA==.Fasylan:BAAALgADCgEJAQAAAA==.',
Fe='Feastling:BAAALgAECgYJCwAAAA==.Feefree:BAAALgAECgEJAQAAAA==.Felthirra:BAAALgADCgEJAQAAAA==.Femboyswag:BAAALgAECgUJBgAAAA==.Ferrak:BAAALgADCgcJBwAAAA==.',
Fi='Finnabust:BAAALgAECgEJAQAAAA==.Fizzlefarts:BAAALgADCgYJDwAAAA==.Fizzylemon:BAAALgADCgcJCQAAAA==.',
Fl='Flipnslam:BAAALgAFFAEJAQAAAA==.Floofball:BAAALgAFFAEJAgABLgAFFAMJCAAMABYQAA==.Floralia:BAAALgAECgEJAQAAAA==.',
Fo='Forget:BAAALgADCgMJBAAAAA==.Foxyshadow:BAAALgADCgkJCgAAAA==.',
Fr='Fragwork:BAAALgADCggJBwAAAA==.Freadyfire:BAAALgAECgYJCgAAAA==.Frostfiretip:BAAALgAECgYJCwAAAA==.Frozanath:BAAALgAECgcJBwAAAA==.Frózen:BAAALgAECgQJBgAAAA==.',
Fu='Fucctaard:BAAALgADCgIJAgAAAA==.Furious:BAAALgADCgYJBgAAAA==.',
Ga='Gaerestord:BAAALgADCgEJAQAAAA==.Gakusei:BAAALgADCgUJBQAAAA==.Gatortail:BAAALgADCgUJBQAAAA==.Gatzart:BAAALgADCgUJCQAAAA==.',
Gi='Gimchick:BAAALgAECgYJCgAAAA==.',
Gn='Gnomebody:BAAALgADCgcJBwABLgAECggJEgADAAAAAA==.',
Go='Goofydude:BAAALgAECgYJCQAAAA==.Goofysensei:BAAALgAECgUJCAABLgAECgYJCQADAAAAAA==.',
Gr='Grandejugoso:BAAALgAECgEJAQAAAA==.Grapejuicy:BAAALgADCgIJAgAAAA==.Grea:BAAALgAECgYJDAAAAA==.Grumpyguts:BAAALgADCgQJBAAAAA==.',
Gu='Guatemoc:BAAALgADCgUJBQAAAA==.Guldandan:BAAALgAECgIJBAAAAA==.Gurthang:BAAALgAECgMJBgAAAA==.',
Ha='Hadrianus:BAAALgADCgcJBwAAAA==.Haginger:BAAALgAECgQJBAABLgAECggJHQAZACEUAA==.Harlyq:BAABLgAECn8kAAQLAAcJDx7OOgBdAQALAAUJ/RrOOgBdAQAFAAcJEBEsCgBLAQAUAAIJFAs4aABsAAAAAA==.Havocpeener:BAAALgADCgIJAgABLgADCgcJFQADAAAAAA==.Hazy:BAAALgADCgEJAQAAAA==.',
He='Hearah:BAABLgAECn8YAAMTAAkJewrJPACOAQATAAkJewrJPACOAQAaAAEJ6wEilAAiAAAAAA==.Hellyes:BAAALgADCgYJBgAAAA==.Hexdabear:BAAALgADCgcJDgABLgAECgUJCAADAAAAAA==.Hexkwondo:BAAALgAECgUJCAAAAA==.',
Ho='Hondô:BAECLgAFFH8OAAIJAAUJrCEZCQCIAQAJAAUJrCEZCQCIAQAuAAQKfx8AAgkACQlBJNAGAGwDAAkACQlBJNAGAGwDAAAA.Hosinator:BAABLgAECn8ZAAISAAcJBgPC6wAgAQASAAcJBgPC6wAgAQAAAA==.',
Hu='Huckleberry:BAAALgADCgcJBwAAAA==.Hukmo:BAAALgAECgIJAgAAAA==.Huntermanjoe:BAAALgAECgUJBgAAAA==.Hunterzalt:BAABLgAECn8gAAMKAAgJLhSwBAB/AQAKAAgJLhSwBAB/AQAJAAEJxgGDMQEmAAAAAA==.Huunah:BAAALgADCgIJAgAAAA==.',
Hy='Hydroplex:BAAALgADCgQJBQAAAA==.',
['Hò']='Hòndo:BAEALgAECgMJAwABLgAFFAUJDgAJAKwhAA==.',
['Hô']='Hôndo:BAEALgAECgMJBgABLgAFFAUJDgAJAKwhAA==.',
Ic='Icepanda:BAAALgADCgMJAwAAAA==.Ichantspell:BAAALgADCggJCgAAAA==.',
Id='Idra:BAABLgAECn8hAAINAAgJ/iSIBgAxAwANAAgJ/iSIBgAxAwAAAA==.Idrea:BAAALgADCgYJBgAAAA==.',
Il='Ildjarnn:BAAALgAECgUJCAAAAA==.Illaoii:BAAALgAECgEJAQAAAA==.Illussions:BAABLgAECn8VAAMbAAYJ4BOEUgBcAQAbAAYJ4BOEUgBcAQAcAAEJjxmJdgBJAAAAAA==.',
Im='Imdyland:BAAALgADCgIJAgAAAA==.',
In='Inashen:BAAALgADCgEJAQABLgAECgMJBwADAAAAAA==.Informal:BAAALgADCgIJAgAAAA==.Invelmoon:BAAALgAECgQJDAAAAA==.',
Ir='Iriane:BAAALgAECgkJEgAAAA==.',
It='Ithrail:BAABLgAECn8YAAIVAAkJMhgvNAAoAgAVAAkJMhgvNAAoAgAAAA==.',
Ja='Jakilk:BAAALgADCgYJBgAAAA==.Janistrapin:BAAALgADCgcJDQAAAA==.Jatza:BAAALgAECgQJBgAAAA==.Javontavius:BAAALgAECgMJAwAAAA==.Jazzmisa:BAABLgAECn8fAAIGAAgJQAv4bgCfAQAGAAgJQAv4bgCfAQAAAA==.',
Jd='Jdoobie:BAAALgADCgYJBgAAAA==.',
Je='Jehon:BAAALgAECgEJAgAAAA==.Jellydead:BAABLgAECn8WAAIJAAYJFQ3OHAA0AQAJAAYJFQ3OHAA0AQAAAA==.Jerico:BAAALgADCgIJAgAAAA==.Jesselroes:BAAALgADCgMJAwAAAA==.',
Ji='Jinja:BAAALgADCgcJDwAAAA==.',
Jo='Jockster:BAAALgAECgYJEQAAAA==.Jonawayne:BAAALgAECgQJBAAAAA==.Joseycoyote:BAAALgADCgcJBwAAAA==.',
Ju='Judgeandrson:BAAALgAECgUJBQABLgAECgYJCwADAAAAAA==.Judinous:BAABLgAECn8eAAISAAgJkiJSJwDVAgASAAgJkiJSJwDVAgAAAA==.Juggernåut:BAAALgADCgkJCwAAAA==.',
Ka='Kabooms:BAABLgAECn8WAAISAAYJxgXKOADgAAASAAYJxgXKOADgAAAAAA==.Kaelditeta:BAAALgAECgYJCQAAAA==.Kaelsdruid:BAAALgAECgQJBAAAAA==.Kaelsevoker:BAAALgAECggJEQAAAA==.Kaelthuss:BAAALgADCgMJAwABLgAECgIJBAADAAAAAA==.Kaiarbarcy:BAAALgAECgQJBAAAAA==.Kaisen:BAAALgADCgUJBQAAAA==.Kalamord:BAAALgADCgYJBgAAAA==.Kalross:BAAALgADCgIJAgAAAA==.Kanao:BAABLgAECn8VAAIVAAgJSA+4TQC+AQAVAAgJSA+4TQC+AQAAAA==.Karethi:BAAALgADCgEJAQAAAA==.Katimeen:BAAALgAECgYJDgAAAA==.Kawaiiuwu:BAAALgADCgYJCwAAAA==.',
Ke='Keesah:BAAALgAECgEJAQAAAA==.Keinddora:BAAALgADCgEJAQAAAA==.Kelann:BAABLgAECn8WAAIVAAcJ0AOqNQCQAAAVAAcJ0AOqNQCQAAAAAA==.Kensei:BAAALgAFFAEJAQAAAA==.Kentohya:BAAALgADCgYJDwAAAA==.Kenöbi:BAAALgADCgEJAQAAAA==.',
Kh='Khaoticbrews:BAAALgAECgEJAQABLgAECgYJCgADAAAAAA==.Kharnoth:BAAALgAECgQJBAAAAA==.Khayla:BAAALgADCgEJAQAAAA==.Khody:BAAALgAECgQJBAAAAA==.',
Ki='Kicknbird:BAAALgADCgEJAQAAAA==.Kimbo:BAAALgAECgEJAQAAAA==.Kippo:BAEALgAECgEJAQAAAA==.',
Kn='Knewbee:BAAALgADCgEJAQABLgADCgQJBQADAAAAAA==.',
Ko='Kokushîbo:BAAALgAECgEJAgAAAA==.Konkon:BAAALgAECgYJBwAAAA==.Konoa:BAAALgAECgEJAQABLgAECgQJBwADAAAAAA==.Konton:BAAALgAECgQJBAABLgAECgYJHAAdAJoZAA==.',
Kr='Kradoro:BAAALgADCgYJDAAAAA==.Kratorick:BAAALgADCgEJAQAAAA==.Krelash:BAAALgAECgYJDAAAAA==.',
Ku='Kukipoo:BAAALgADCgMJAwAAAA==.Kurdzy:BAAALgADCgQJBAAAAA==.',
Kv='Kvarda:BAAALgADCgMJBAAAAA==.',
Ky='Kynetic:BAAALgAECgQJBwAAAA==.',
La='Labatblue:BAAALgADCgkJEAAAAA==.',
Le='Leenie:BAAALgAECggJDQAAAA==.Leftleg:BAAALgAECgEJAwAAAA==.Legendrìser:BAABLgAECn8UAAIGAAkJXhimTQD5AQAGAAkJXhimTQD5AQAAAA==.Leggomyeggos:BAAALgADCgMJAwAAAA==.Leginge:BAABLgAECn8dAAMZAAgJIRR/DwCCAQAZAAgJIRR/DwCCAQAbAAEJdgHm6AAcAAAAAA==.Leigong:BAAALgAECgYJBgAAAA==.Leiyang:BAABLgAECn8UAAIWAAcJVwgBFAAUAQAWAAcJVwgBFAAUAQAAAA==.Lemmykillmr:BAAALgADCgYJBgAAAA==.',
Li='Liaree:BAAALgADCgIJAgAAAA==.Lie:BAABLgAECn8cAAIdAAYJmhmrIQDsAQAdAAYJmhmrIQDsAQAAAA==.Lifey:BAABLgAECn8WAAIJAAcJtRtLRwAeAgAJAAcJtRtLRwAeAgABLgAECgIJAgADAAAAAA==.Lightfemboy:BAAALgAECgYJDwABLgAFFAUJEgALADolAA==.Limonespe:BAABLgAECn8YAAMPAAgJvSSMCwAeAwAPAAgJvSSMCwAeAwAQAAEJAAAJXABaAAAAAA==.Lisal:BAAALgAECgkJAgAAAA==.Lizerd:BAAALgAECgUJCAABLgAFFAQJCQAHAOgXAA==.',
Lo='Locktendo:BAAALgADCgUJCAAAAA==.Looksmaxxing:BAAALgADCgIJAgAAAA==.Lothon:BAAALgADCgMJAwAAAA==.',
Lu='Luciferal:BAAALgADCgYJBgAAAA==.Lunaluv:BAAALgAECgYJCQAAAA==.Lussions:BAAALgAECgUJCAAAAA==.',
Ly='Lytefoot:BAAALgADCgQJBAAAAA==.Lytheris:BAAALgADCgQJBAAAAA==.',
['Lë']='Lëägolas:BAAALgADCgcJBgAAAA==.',
['Lí']='Líllíth:BAAALgADCgkJGQAAAA==.',
Ma='Machoshaman:BAABLgAECn8aAAMTAAgJuBTsKQDmAQATAAgJuBTsKQDmAQAaAAIJrRHsdABuAAAAAA==.Maeveran:BAAALgAECgYJEgAAAA==.Mafuyu:BAAALgAECgMJBAAAAA==.Maghalfastir:BAABLgAECn8XAAIJAAYJ4BOIjwBhAQAJAAYJ4BOIjwBhAQAAAA==.Magnusvll:BAAALgAECgcJDQAAAA==.Magraah:BAAALgAECgkJCgAAAA==.Mahesvara:BAAALgAECgQJBgAAAA==.Malomea:BAAALgADCgcJBwAAAA==.Malvoryx:BAAALgAECgIJAgAAAA==.Mandrei:BAAALgAECgEJAQAAAA==.Mantisa:BAAALgAECgMJAwAAAA==.Manøn:BAAALgAECgQJBQAAAA==.Maraul:BAAALgAECgEJAQAAAA==.Marlynn:BAAALgAECgcJDAAAAA==.Masinverter:BAAALgAECgQJBQAAAA==.Mastalys:BAEALgAECgMJBAAAAQ==.Mattamuss:BAAALgADCgYJBgAAAA==.Mattdamon:BAAALgADCgEJAQAAAA==.Mattzappara:BAAALgADCgMJAwAAAA==.Mavet:BAABLgAECn8iAAMIAAgJbxSTBADTAQAIAAgJbxSTBADTAQAHAAQJNANsYwChAAAAAA==.Mavina:BAAALgAECgUJBQABLgAECggJIAABAMQYAA==.Mavinaqt:BAABLgAECn8gAAMBAAgJxBggFgAnAgABAAgJxBggFgAnAgAeAAIJ7QJVRABMAAAAAA==.Mazez:BAAALgADCgkJCQAAAA==.',
Mc='Mcpeek:BAAALgAECgMJAgAAAA==.',
Me='Meatshieldz:BAAALgAECgUJBQAAAA==.Mechachi:BAAALgAECgYJCwAAAA==.Megabonk:BAAALgADCgcJBwABLgAECgIJAgADAAAAAA==.Meglatwo:BAAALgADCgYJBgABLgAECggJHwAQAJ8YAA==.Meketek:BAAALgAECgYJEwAAAA==.Mellivia:BAAALgAECgQJBAAAAA==.Melodica:BAAALgAECgQJBAAAAA==.Menaly:BAAALgAECgMJBQAAAA==.Mendel:BAAALgADCgQJBAAAAA==.Metaphysical:BAABLgAECn8wAAMFAAgJbBWRFwAEAgAFAAgJbBWRFwAEAgALAAQJkRl3VwDmAAAAAA==.Methenistul:BAAALgAECgEJAQAAAA==.',
Mi='Miennie:BAAALgAECgYJCAAAAA==.Mildo:BAABLgAECn8VAAMQAAcJzQ6kBAAKAQAQAAcJzQ6kBAAKAQAPAAEJAADsNAEOAAAAAA==.Millerlight:BAAALgAECgQJBAAAAA==.Mingemeister:BAAALgAECgIJAgAAAA==.Minotàurus:BAABLgAECn8ZAAMMAAgJuwkKEwBjAQAMAAgJuwkKEwBjAQAfAAMJNANwJwB9AAAAAA==.Mintonka:BAAALgAECgYJEAAAAA==.Mirakodus:BAAALgADCgcJDQAAAA==.Misfired:BAAALgAECgUJCAAAAA==.Mistbehave:BAAALgAECgYJEgAAAA==.Miztaqe:BAAALgADCgMJAwAAAA==.',
Mo='Mogthalen:BAAALgADCgMJAwAAAA==.Moneyheavy:BAAALgADCgcJBwAAAA==.Mongkorn:BAAALgAECgEJAQAAAA==.Monstershi:BAAALgAECgEJAQAAAA==.Moonologist:BAAALgADCgUJBQAAAA==.Moonpig:BAAALgADCgcJFwAAAA==.Moopiehead:BAAALgAECgIJAgAAAA==.Mordayna:BAAALgADCggJEQAAAA==.Morganà:BAAALgAECgMJBAAAAA==.Morgy:BAABLgAECn8ZAAISAAcJPgcdNQDyAAASAAcJPgcdNQDyAAAAAA==.Mortimr:BAAALgAECgUJBAAAAA==.Mortinir:BAAALgAECgEJAQAAAA==.',
My='Myor:BAAALgADCgUJBQAAAA==.Mystsouls:BAABLgAECn8fAAIJAAgJlA8dXgDYAQAJAAgJlA8dXgDYAQAAAA==.',
['Må']='Måâgic:BAAALgAECgEJAgAAAA==.',
Na='Nagasaywhat:BAAALgAECgYJDwAAAA==.Nahari:BAAALgADCgIJAgAAAA==.Narcissist:BAAALgAECgMJAgABLgAECggJMAAFAGwVAA==.Natalietes:BAAALgADCgcJCgAAAA==.Nattylight:BAAALgADCggJCAAAAA==.',
Ne='Necronomicon:BAABLgAECn8XAAMQAAYJ2hP0LwD7AAAPAAUJGBXOmwAhAQAQAAUJcAv0LwD7AAAAAA==.Neetneetneet:BAAALgADCgMJAgAAAA==.Nemoglobine:BAAALgADCgIJAgAAAA==.',
Ni='Nightshroud:BAAALgAFFAMJAgAAAA==.Niipz:BAAALgAECgcJDgAAAA==.Nilie:BAAALgAECgEJAQAAAA==.Ninelinez:BAAALgAECgUJEQAAAA==.Ninjakiwiz:BAAALgADCgEJAQAAAA==.Ninjaknife:BAAALgADCgEJAQAAAA==.',
No='Noctaholic:BAAALgADCgMJBQAAAA==.Noctria:BAAALgAECgMJAwAAAA==.Nocturnalis:BAAALgADCgYJBgAAAA==.Nords:BAAALgAECgMJAwAAAA==.Novavanna:BAAALgADCgcJDAAAAA==.Noxistra:BAABLgAECn8TAAQRAAcJQQ9bAgBCAQARAAYJ6Q5bAgBCAQAQAAMJBgRdXQBWAAAPAAIJ8AwGVwA2AAAAAA==.Noyan:BAAALgAECgMJAwAAAQ==.',
Nu='Nukedawg:BAAALgAECgMJAwAAAA==.Nunchaku:BAAALgAECggJBQAAAA==.',
['Nä']='Nägasäh:BAABLgAECn8VAAIJAAYJihVYkABfAQAJAAYJihVYkABfAQAAAA==.',
['Nî']='Nîneline:BAAALgADCgcJCwABLgAECgUJEQADAAAAAA==.',
['Nø']='Nørb:BAAALgAECgYJDAAAAA==.',
Ob='Obsessions:BAAALgADCgEJAQAAAA==.',
Og='Ogdirtymac:BAAALgADCgMJAwAAAA==.',
Oi='Oilless:BAAALgAECgIJAgAAAA==.',
Ol='Olayro:BAAALgADCgcJBwABLgAECgIJAgADAAAAAA==.Olgalina:BAAALgADCgYJBgAAAA==.Ollietrollie:BAAALgAECgYJBgAAAA==.',
Om='Ommateal:BAAALgAECgEJAgAAAA==.',
Op='Opirix:BAACLgAFFH8JAAIHAAQJ6BfzAQBCAQAHAAQJ6BfzAQBCAQAuAAQKfygAAwcACAmXIp0BAHwCAAcACAmXIp0BAHwCAAgAAwlxGB1CAOkAAAAA.',
Or='Orcgirl:BAAALgADCgcJCAAAAA==.',
Ou='Ouidufromage:BAAALgAECgEJAQAAAA==.',
Ov='Overlandx:BAAALgAECgEJAgAAAA==.Overloaded:BAAALgAECgQJBQAAAA==.',
Ow='Owlzkaban:BAAALgAECgcJCgAAAA==.',
Ox='Oxelox:BAAALgADCgUJBgAAAA==.',
Oz='Ozzytbone:BAAALgAECgQJBAAAAA==.',
Pa='Paddfoot:BAAALgADCgQJBQAAAA==.Painkillerx:BAAALgADCgcJFAAAAA==.Palisa:BAAALgADCgkJEQAAAA==.Panini:BAAALgADCgkJEAABLgAECgcJFgASAPcRAA==.Panzurdin:BAAALgADCgUJBQAAAA==.Panzurlock:BAABLgAECn8aAAIPAAgJFh3GLgBSAgAPAAgJFh3GLgBSAgAAAA==.Panzurrkin:BAAALgADCgEJAQAAAA==.Papabelliswa:BAAALgADCgIJAgAAAA==.Papasquat:BAAALgAECgIJAwAAAA==.Patreszas:BAABLgAECn8ZAAMBAAcJogyUDAAhAQABAAcJQgyUDAAhAQACAAYJ7gvdIwAIAQAAAA==.',
Pe='Peener:BAAALgADCgcJFQAAAA==.Pellere:BAAALgADCgMJAwAAAA==.Pemberton:BAAALgAECgYJDAAAAA==.Pepperboy:BAAALgADCgQJBAAAAA==.',
Ph='Pheauxbe:BAAALgADCgYJCAAAAA==.Pheauxly:BAAALgADCgYJDAAAAA==.Phlehm:BAAALgAFFAEJAQAAAA==.',
Pl='Plaguesire:BAAALgADCgYJDgAAAA==.Plutonyx:BAAALgAECgYJCgAAAA==.',
Po='Popedk:BAAALgAECggJCAAAAA==.',
Pr='Prannanm:BAAALgADCgcJEwAAAA==.Priestduude:BAAALgAECgcJDAAAAA==.Priestpheus:BAAALgAECgEJAQAAAA==.Prismaticp:BAAALgADCgYJDAAAAA==.',
Ps='Psyger:BAAALgAECgUJCQAAAA==.',
Pu='Pullacrapton:BAAALgAECgUJCgAAAA==.Purecorrupt:BAAALgAECgIJAgAAAA==.Putridmeat:BAAALgAECgYJCQAAAA==.',
Pw='Pwrsmoke:BAAALgADCgcJCQAAAA==.',
Qu='Quackery:BAAALgADCgIJAgAAAA==.Quiggins:BAAALgAECgUJDAAAAA==.Quikbrownfox:BAAALgADCgQJBAAAAA==.Quirkster:BAAALgADCgIJAgAAAA==.',
Ra='Rakoon:BAAALgADCgMJAwAAAA==.Rathindor:BAAALgADCgEJAQAAAA==.',
Rc='Rchris:BAAALgADCgEJAQAAAA==.',
Re='Rectivius:BAAALgADCgMJAwAAAA==.Reddknight:BAAALgAECgcJEwAAAA==.Reiker:BAAALgAECgIJAgAAAA==.Retzu:BAAALgAECgEJAQAAAA==.Rezme:BAAALgADCgMJAwAAAA==.',
Ri='Riccardo:BAAALgAECgEJAwAAAA==.Rickiebear:BAAALgADCgQJBwABLgADCgcJEgADAAAAAA==.Rimeborn:BAAALgADCgEJAQAAAA==.Rivenn:BAAALgAECgEJAQABLgAECgYJEgADAAAAAA==.Rizzlesschud:BAAALgADCgMJAwAAAA==.Rizzlér:BAAALgADCgUJAwAAAA==.',
Ru='Rubonyx:BAAALgAECgEJAQAAAA==.Ruikai:BAAALgAECgEJAQAAAA==.Rune:BAAALgADCgcJBgAAAA==.',
Ry='Ryoko:BAABLgAECn8XAAMPAAYJKx2tEACLAQAPAAUJlhutEACLAQAQAAMJzBghMwDrAAAAAA==.',
['Rä']='Rävaged:BAAALgADCgcJDQABLgAECgYJCwADAAAAAA==.',
Sa='Sagerin:BAAALgAECgQJDAAAAA==.Sageslife:BAAALgAECgQJCQAAAA==.Sailwe:BAAALgAECgIJAwAAAA==.Saintofthetp:BAAALgADCgUJCAAAAA==.Saison:BAAALgADCgYJBgAAAA==.Salém:BAAALgADCgUJBQAAAA==.Sambooka:BAAALgADCgQJBAAAAA==.Saraaj:BAAALgAECgYJCQAAAA==.Sarallina:BAAALgADCgUJCQAAAA==.Sarifa:BAAALgADCgcJBwAAAA==.',
Sc='Scallion:BAAALgADCgIJAwAAAQ==.Scalythott:BAAALgAECgQJBAAAAA==.Scarr:BAAALgADCgEJAgAAAA==.Scruffmcgruf:BAAALgAECgYJEgAAAA==.Scubany:BAAALgADCgQJBAAAAA==.',
Se='Selem:BAAALgADCgUJBQABLgAECgcJFwAFAFoXAA==.Sezeth:BAAALgAECgQJBAAAAA==.',
Sh='Shaboomboom:BAABLgAECn8bAAIgAAgJwh/YBQChAgAgAAgJwh/YBQChAgABLgADCgYJBgADAAAAAA==.Shadowglaive:BAABLgAECn8bAAIVAAYJnBT/YAB+AQAVAAYJnBT/YAB+AQAAAA==.Shalthorn:BAAALgADCgMJAwAAAA==.Sharsu:BAACLgAFFH8FAAIPAAMJ5hqTDAAOAQAPAAMJ5hqTDAAOAQAuAAQKfysAAg8ACAlGJYoGAFYDAA8ACAlGJYoGAFYDAAAA.Shew:BAAALgADCgkJCQAAAA==.Shewadin:BAAALgADCgYJBgAAAA==.Shewcifer:BAAALgAECgMJBwAAAA==.Shortcake:BAAALgADCgEJAQAAAA==.',
Si='Silhouete:BAAALgADCgIJAgAAAA==.',
Sk='Skaborn:BAAALgAECgQJCAAAAA==.Skillitor:BAAALgADCgcJBwAAAA==.Skillman:BAAALgADCgUJCAAAAA==.Skrizik:BAAALgAECgIJAgAAAA==.Skullshine:BAACLgAFFH8MAAIJAAQJ0BusEwBTAQAJAAQJ0BusEwBTAQAuAAQKfxgAAgkACQlhI08WAPYCAAkACQlhI08WAPYCAAAA.Skunkie:BAAALgAECgYJCwAAAA==.Skybreaker:BAAALgAFFAEJAQAAAA==.Skåbørn:BAAALgADCgcJDQABLgAECgQJCAADAAAAAA==.',
Sl='Sluewt:BAABLgAECn8XAAIGAAgJqA/hWQDVAQAGAAgJqA/hWQDVAQAAAA==.Slushpuppy:BAAALgADCgEJAQAAAA==.Slìquid:BAAALgADCgUJBQAAAA==.',
Sm='Smileysabear:BAAALgAECgYJBgABLgAECgYJCwADAAAAAA==.Smileysalock:BAAALgADCgcJBwABLgAECgYJCwADAAAAAA==.Smolderr:BAAALgAECgYJCAAAAA==.',
Sn='Sneasel:BAAALgADCgEJAQABLgAECgYJEgADAAAAAA==.',
So='Soapydish:BAAALgADCgIJAgAAAA==.Soulshart:BAAALgAECgcJBQAAAA==.',
Sp='Spacerift:BAABLgAFFH8QAAIXAAYJEiBNAADhAQAXAAYJEiBNAADhAQAAAA==.Spaciousyeti:BAAALgAECgYJCgAAAA==.Sparhawke:BAAALgADCgkJEAAAAA==.Spawne:BAAALgAECgcJBwAAAA==.Spearowmage:BAAALgADCgYJBgAAAA==.Spearowpally:BAAALgAECgQJBwAAAA==.Spellomode:BAAALgAECgYJBwAAAA==.Splits:BAAALgAECgEJAgAAAA==.',
St='Stanhorn:BAAALgADCgIJAQAAAA==.Starrscream:BAAALgAECgkJBAAAAA==.Stazxd:BAAALgAECgEJAQAAAA==.Steezyah:BAAALgAECgQJBQAAAA==.Stevebrule:BAAALgAECgEJAQAAAA==.Stiffbacon:BAABLgAECn8UAAIOAAYJ8A1qUQBjAQAOAAYJ8A1qUQBjAQAAAA==.Stinkler:BAAALgAECgUJBQAAAA==.Stornhas:BAAALgADCgQJBwAAAA==.Strikerj:BAAALgAECgQJBAAAAA==.Strànge:BAAALgADCgUJBQAAAA==.Stun:BAAALgAECgIJAgAAAA==.Stunllub:BAAALgAECgYJCwAAAA==.',
Su='Suggs:BAACLgAFFH8GAAIPAAQJuRnaBQBcAQAPAAQJuRnaBQBcAQAuAAQKfx8ABA8ACQkuJNgOAAMDAA8ACAmYJNgOAAMDABAAAgl4GgRMAIkAABEAAQkAAKAoAE8AAAAA.Sunwelldone:BAAALgADCgYJDAAAAA==.Superali:BAAALgADCgMJAwAAAA==.Surnaturelle:BAAALgADCgcJBwAAAA==.',
Sy='Syphyr:BAAALgADCgQJBwAAAA==.Syradael:BAAALgADCgUJBQAAAA==.Sythyn:BAAALgADCgUJBQAAAA==.',
['Sæ']='Sæd:BAAALgADCgYJBgAAAA==.',
Ta='Taelinn:BAAALgADCgcJBwABLgAECgcJGQABAKIMAA==.Talet:BAAALgAECgMJAwAAAA==.Tallyjaber:BAAALgAECgEJAQAAAA==.Tastymelo:BAAALgAECgEJAQAAAA==.Taterthott:BAAALgAECgYJEQAAAA==.Tauriko:BAAALgAECgUJCQAAAA==.',
Te='Teradin:BAAALgAECgEJAQAAAA==.Teratori:BAAALgADCgIJAwAAAA==.Terrorknight:BAABLgAECn8WAAIJAAcJDBfwFgBaAQAJAAcJDBfwFgBaAQAAAA==.',
Th='Thebestlorax:BAAALgADCgMJAwAAAA==.Theldrus:BAAALgAECgQJBAAAAA==.Theradestria:BAAALgADCgcJEQAAAA==.Thereeree:BAAALgADCgcJCQAAAA==.Thestigg:BAAALgADCgUJBQAAAA==.Threaten:BAAALgADCgUJCQAAAA==.Thunderfall:BAAALgAECgYJEgAAAA==.Thyrä:BAAALgADCggJDAAAAA==.Thëspiän:BAAALgAECgEJAQAAAA==.',
Ti='Tihro:BAAALgAECgQJBwAAAA==.Timmyjam:BAABLgAECn8ZAAMQAAYJCw/9AwAhAQAQAAYJCw/9AwAhAQAPAAEJAADfNQEHAAAAAA==.Tiradia:BAABLgAECn8hAAINAAcJECYFCgAAAwANAAcJECYFCgAAAwAAAA==.',
To='Toffersox:BAAALgAECgYJDAABLgAECgIJAgADAAAAAA==.',
Tr='Traianus:BAAALgADCgMJAwAAAA==.Traynnissa:BAAALgADCgUJBwAAAA==.Treexa:BAAALgADCgQJBAAAAA==.',
Tu='Tutankhamun:BAAALgAECgMJBAAAAA==.',
Tv='Tvenom:BAAALgAECgYJEwAAAA==.',
Tw='Twistybanana:BAAALgAECgYJDAAAAA==.Twofourfive:BAAALgADCgEJAQAAAA==.',
Ty='Tyinastor:BAAALgADCggJBgAAAA==.',
['Tö']='Töme:BAAALgADCgUJBwAAAA==.',
['Tø']='Tømb:BAAALgAECgQJBQABLgAFFAQJBQABACkPAA==.',
Ud='Udderless:BAAALgAECgUJCgAAAA==.',
Uh='Uhhtari:BAAALgAECgEJAQAAAA==.',
Un='Unbëärable:BAAALgADCggJEAAAAA==.',
Ut='Uthers:BAAALgADCgYJBgAAAA==.',
Va='Vaalhazak:BAAALgAECgIJBAAAAA==.Valdril:BAAALgADCgcJBwAAAA==.Valky:BAAALgAECgYJCgAAAA==.Vanhealín:BAAALgAECgYJBgAAAA==.',
Ve='Vecx:BAAALgAECgMJAwABLgAECgYJDQADAAAAAA==.Veldispel:BAAALgADCgYJBgAAAA==.Velro:BAAALgAECggJEQAAAA==.Versë:BAAALgAECgEJAQAAAA==.Vextrex:BAAALgAECgEJAQAAAA==.',
Vh='Vhalaan:BAAALgADCgMJAwAAAA==.',
Vi='Vianir:BAAALgAECgYJDwAAAA==.Viann:BAAALgADCgYJCgAAAA==.Vitamin:BAAALgAECggJBgAAAA==.',
Vo='Voidness:BAAALgAECgQJBAAAAA==.Voldanis:BAAALgAECgcJAQAAAA==.Volpris:BAAALgADCgYJBgAAAA==.Volzuka:BAAALgAECgEJAQAAAA==.',
Vu='Vulsutyr:BAAALgADCgMJAwAAAA==.',
Vy='Vyndeyice:BAAALgADCgIJAgAAAA==.',
['Vé']='Véxør:BAABLgAECn8dAAQZAAYJUhJxFAApAQAZAAYJUhJxFAApAQAbAAUJ/QIenQCRAAAcAAIJugK6eQA/AAAAAA==.',
['Vê']='Vêxor:BAAALgADCgcJBwAAAA==.',
['Vë']='Vësper:BAAALgADCgkJCwAAAA==.',
Wa='Waffel:BAAALgAECgEJAQAAAA==.Wafulol:BAABLgAECn8sAAIGAAgJ0hUlOgA7AgAGAAgJ0hUlOgA7AgAAAA==.Warhawkyo:BAAALgAECgYJBwAAAA==.Warlockios:BAAALgADCgcJBwAAAA==.Warmsoup:BAAALgADCgMJAwAAAA==.Warscared:BAAALgAECgUJCQAAAA==.Waxxpoet:BAAALgADCgYJDQAAAA==.',
We='Wels:BAAALgAECgYJCQAAAA==.',
Wh='Whichwitch:BAAALgADCgUJBQAAAA==.Whiteagle:BAAALgADCgEJAQAAAA==.',
Wi='Wigglypuffsr:BAAALgAECgQJBQABLgAECgcJGwAJABIbAA==.Wiikkid:BAAALgAECgQJBAAAAA==.Winddrake:BAAALgAECgQJAgAAAA==.',
Wr='Wrathborne:BAAALgADCgMJAwAAAA==.',
Xa='Xaanu:BAAALgADCgUJBQAAAA==.Xaclov:BAAALgAECgYJDQAAAA==.Xalcor:BAEALgAECgQJBAAAAA==.Xanelivan:BAAALgADCgUJCgAAAA==.Xanneste:BAAALgADCgMJAwAAAA==.Xano:BAAALgAECgYJDwAAAA==.Xarius:BAAALgAECgEJAQAAAA==.',
Xi='Xiz:BAAALgAECgEJAQAAAA==.',
Xo='Xorlandu:BAAALgAECggJCQAAAA==.',
Xx='Xxchan:BAAALgADCgIJAgAAAA==.',
Xy='Xylotus:BAAALgAECgUJEAAAAA==.',
Ya='Yahtzeé:BAABLgAECn8dAAIYAAgJOA2+LwDDAQAYAAgJOA2+LwDDAQAAAA==.',
Yo='Yokaihp:BAAALgADCgMJAwAAAA==.Yoshii:BAAALgAECgUJBQAAAA==.',
Yu='Yujirø:BAAALgAECgQJDAAAAA==.Yuubel:BAAALgADCgUJCwAAAA==.',
Za='Zale:BAAALgAECgIJAgAAAA==.Zanpakuto:BAAALgAECgkJCAAAAA==.Zayday:BAAALgADCgEJAQAAAA==.',
Ze='Zedawg:BAAALgADCgcJJAAAAA==.Zenfemboy:BAACLgAFFH8SAAILAAUJOiVqAQAHAgALAAUJOiVqAQAHAgAuAAQKfyUAAgsACQkQJuIBAIYDAAsACQkQJuIBAIYDAAAA.Zerofoxx:BAAALgADCgMJAwAAAA==.',
Zi='Ziweix:BAAALgADCgYJCAAAAA==.',
Zo='Zolmijin:BAAALgAECgYJDwAAAA==.Zombiekush:BAAALgADCgMJBAAAAA==.',
Zu='Zugomik:BAAALgAECggJEgAAAA==.Zurydh:BAAALgADCgYJBgAAAA==.Zuulax:BAAALgAECgMJAwAAAA==.',
['Zæ']='Zæn:BAAALgAECgQJBAAAAA==.',
['Zé']='Zéddicus:BAAALgADCgEJAQAAAA==.',
['Ça']='Çasey:BAAALgAECgYJDQAAAA==.',
['Çé']='Çélädor:BAACLgAFFH8HAAIGAAMJuRq8CQD+AAAGAAMJuRq8CQD+AAAuAAQKfyAAAgYACAm1JG8NACIDAAYACAm1JG8NACIDAAAA.',
['Çü']='Çürzê:BAAALgADCgMJAwAAAA==.',
['Èm']='Èmrys:BAAALgAECgcJBQAAAA==.',
['Öb']='Öbi:BAAALgAECgYJDAAAAA==.',
['Ör']='Örin:BAABLgAECn8WAAIhAAgJihm5BABWAgAhAAgJihm5BABWAgAAAA==.',
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

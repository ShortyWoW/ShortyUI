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

local lookup = {'Hunter-BeastMastery','Unknown-Unknown','Priest-Discipline','Warlock-Demonology','Shaman-Restoration','Paladin-Protection','Mage-Frost','Warrior-Arms','Warrior-Fury','Priest-Shadow','Warrior-Protection','Rogue-Subtlety','DemonHunter-Devourer','Druid-Restoration','Evoker-Devastation','Evoker-Augmentation','Evoker-Preservation','Hunter-Marksmanship','Warlock-Destruction','DeathKnight-Unholy','Shaman-Elemental','Druid-Guardian','Druid-Balance','Monk-Mistweaver','DeathKnight-Frost','Paladin-Holy','DemonHunter-Havoc','Monk-Windwalker','Druid-Feral','DeathKnight-Blood','Paladin-Retribution','Mage-Arcane','DemonHunter-Vengeance',}
local provider = {region='US',realm='Dragonblight',name='US',type='daily',zone=46,date='2026-05-10',data={Aa='Aauron:BAAALgAECgMJAwAAAA==.Aazula:BAAALgAECgUJBgAAAA==.',
Ac='Acelionheart:BAAALgADCgQJCAAAAA==.Acheron:BAAALgADCgcJCQAAAA==.',
Ai='Aix:BAAALgADCgcJBwAAAA==.',
Aj='Ajrpg:BAAALgADCgQJBAAAAA==.',
Ak='Akirys:BAAALgAECgcJEwAAAA==.Akusenshi:BAAALgAECgYJDwAAAA==.',
Al='Alarr:BAAALgAECgIJAgAAAA==.Albertwesker:BAAALgAECgEJAQAAAA==.Alethrix:BAAALgAECgQJBwAAAA==.Alexi:BAAALgADCgYJBAAAAA==.Alivis:BAEALgAECgQJBAABLgAECgcJHQABAFciAA==.Alzith:BAAALgAECgQJBQAAAA==.',
Am='Amoone:BAAALgADCgUJCQAAAA==.',
An='Anarch:BAAALgADCgEJAQABLgADCgMJBgACAAAAAA==.Androcksus:BAAALgADCgMJBwAAAA==.Angelic:BAAALgAECgEJAQABLgAFFAgJKQADAC4lAA==.',
Ap='Apexalpha:BAAALgAECgIJAwAAAA==.',
Ar='Areto:BAAALgADCgYJBgAAAA==.Armster:BAAALgADCgcJDAAAAA==.Arold:BAABLgAECn8eAAIEAAgJwBJzLAC5AQhoDAAABQA4AGkMAAAFACgAawwAAAUALQBqDAAABAA1AGwMAAAEAE0AbQwAAAIAKADqDAAAAwAoAG4MAAACACMABAAICcAScywAuQEIaAwAAAUAOABpDAAABQAoAGsMAAAFAC0AagwAAAQANQBsDAAABABNAG0MAAACACgA6gwAAAMAKABuDAAAAgAjAAAA.',
As='Asylia:BAACLgAFFH8KAAIFAAQJNhGCCQA5AQRoDAAABABJAGkMAAADABkAawwAAAEAFADqDAAAAgA5AAUABAk2EYIJADkBBGgMAAAEAEkAaQwAAAMAGQBrDAAAAQAUAOoMAAACADkALgAECn8XAAIFAAgJSxsuIQAXAgAFAAgJSxsuIQAXAgAAAA==.',
At='Atlantus:BAAALgAECgYJDgAAAA==.',
Au='Aurelliae:BAABLgAECn8WAAIBAAgJtBXaIQDVAQhoDAAAAwBWAGkMAAAFAC0AawwAAAUAMgBqDAAAAwA/AGwMAAACAEEAbQwAAAEAEwDqDAAAAgA/AG4MAAABADkAAQAICbQV2iEA1QEIaAwAAAMAVgBpDAAABQAtAGsMAAAFADIAagwAAAMAPwBsDAAAAgBBAG0MAAABABMA6gwAAAIAPwBuDAAAAQA5AAAA.',
Av='Avesiren:BAABLgAECn8VAAIGAAYJexTcEgAgAQZoDAAABQBAAGkMAAAEADEAawwAAAUAQwBqDAAAAgAUAGwMAAACADYA6gwAAAMAGwAGAAYJexTcEgAgAQZoDAAABQBAAGkMAAAEADEAawwAAAUAQwBqDAAAAgAUAGwMAAACADYA6gwAAAMAGwAAAA==.',
Ay='Ayidá:BAAALgAECgQJBwAAAA==.',
Az='Azhág:BAAALgADCgUJBAAAAA==.',
Ba='Babalú:BAAALgAECgYJDAAAAA==.Babymamaa:BAAALgAECgIJAgAAAA==.Babymuffins:BAAALgAECgYJDgAAAA==.Balrocc:BAAALgADCgcJCQAAAA==.',
Be='Beecrafty:BAAALgAECgEJAQAAAA==.Belanda:BAAALgAECgIJAgAAAA==.Belgord:BAAALgAECgQJBgAAAA==.Belin:BAAALgADCgkJFgAAAA==.Belmond:BAAALgAECgQJBwAAAA==.',
Bl='Blackmill:BAAALgAECgYJDAAAAA==.Blayrog:BAABLgAECn8cAAIHAAcJ1A5ybgA7AQdoDAAABAA2AGkMAAAEADAAawwAAAQAIgBqDAAABgA5AGwMAAAFAC0AbQwAAAEABQDqDAAABAAmAAcABwnUDnJuADsBB2gMAAAEADYAaQwAAAQAMABrDAAABAAiAGoMAAAGADkAbAwAAAUALQBtDAAAAQAFAOoMAAAEACYAAAA=.Bloodydemons:BAAALgADCgEJAQAAAA==.Bluerazz:BAAALgADCgMJAwAAAA==.',
Bo='Board:BAABLgAECn8hAAMIAAcJOBjsDgBlAQdoDAAABwBCAGkMAAAHAEMAawwAAAUATgBqDAAABQBGAGwMAAAEAD4A6gwAAAIAKABuDAAAAwA4AAgABwnUF+wOAGUBB2gMAAAEAEIAaQwAAAQAQwBrDAAAAwBOAGoMAAADAEYAbAwAAAMAPgDqDAAAAQAiAG4MAAADADgACQAGCf0Q0lEAYgEGaAwAAAMAFwBpDAAAAwA0AGsMAAACAEQAagwAAAIALABsDAAAAQAgAOoMAAABACgAAS4ABRQFCREACgDeFAA=.Bolf:BAAALgAECgQJCAAAAA==.Boombaaby:BAAALgAECgUJEAAAAA==.Bootzee:BAAALgAECgYJEgAAAA==.',
Br='Brewsli:BAAALgAECgMJAwAAAA==.Brookenoel:BAAALgAECgYJDwAAAA==.Brunhilian:BAAALgAECgQJBAAAAA==.',
Bu='Buckmaster:BAAALgADCggJDAAAAA==.Bungulator:BAAALgAECgEJAgAAAA==.',
Ca='Cadun:BAAALgAECgYJDgAAAA==.Calada:BAAALgAECgQJBgAAAA==.Carbion:BAAALgADCgkJCQAAAA==.',
Ce='Cedarnia:BAAALgADCgMJAgAAAA==.',
Ch='Charot:BAAALgAECgEJAQABLgAFFAEJAQACAAAAAA==.Cheesdhunter:BAAALgAECgMJBQAAAA==.Chronoo:BAABLgAECn8WAAIFAAcJ3BMYJQCgAQdoDAAABQA8AGkMAAAFADsAawwAAAMAQQBqDAAAAwA0AGwMAAACAD4AbQwAAAEADwDqDAAAAwAoAAUABwncExglAKABB2gMAAAFADwAaQwAAAUAOwBrDAAAAwBBAGoMAAADADQAbAwAAAIAPgBtDAAAAQAPAOoMAAADACgAAAA=.',
Ci='Citchelas:BAAALgAECgYJCwAAAA==.',
Co='Corrynn:BAAALgAECgYJDgAAAA==.',
Cr='Cribbage:BAABLgAECn8mAAILAAgJYCJAAwCdAghoDAAABgBVAGkMAAAFAF0AawwAAAUAWABqDAAABQBbAGwMAAAFAFwAbQwAAAMAWwDqDAAABQBYAG4MAAAEAE0ACwAICWAiQAMAnQIIaAwAAAYAVQBpDAAABQBdAGsMAAAFAFgAagwAAAUAWwBsDAAABQBcAG0MAAADAFsA6gwAAAUAWABuDAAABABNAAAA.Cryoclover:BAAALgAECgQJBAAAAA==.Crzykanaka:BAAALgADCgUJBwAAAA==.',
Cu='Cursedgurly:BAAALgAECgIJAgAAAA==.Curshuu:BAAALgAECgQJDgAAAA==.',
Cy='Cynosure:BAABLgAECn8iAAIMAAkJxxhsBQBuAgloDAAABABNAGkMAAAEAFMAawwAAAQAUQBqDAAABABQAGwMAAAEAD8AbQwAAAMAKwDqDAAABAA/AG4MAAAEADwAbwwAAAMAIQAMAAkJxxhsBQBuAgloDAAABABNAGkMAAAEAFMAawwAAAQAUQBqDAAABABQAGwMAAAEAD8AbQwAAAMAKwDqDAAABAA/AG4MAAAEADwAbwwAAAMAIQAAAA==.Cytronsneak:BAAALgAECgEJAQAAAA==.',
Da='Dabb:BAAALgADCgcJCAAAAA==.Daccard:BAAALgADCgkJGwAAAA==.Daccfu:BAAALgAECgQJCAAAAA==.Dangereuse:BAAALgADCgEJAQAAAA==.Danlor:BAABLgAECn8WAAIEAAYJcQgGcQDuAAZoDAAABAAPAGkMAAAEAB4AawwAAAQAEABqDAAAAwAnAGwMAAADABwA6gwAAAQAEQAEAAYJcQgGcQDuAAZoDAAABAAPAGkMAAAEAB4AawwAAAQAEABqDAAAAwAnAGwMAAADABwA6gwAAAQAEQAAAA==.Darkheaven:BAAALgAECgYJEgAAAA==.Darkkanaka:BAAALgADCgEJAQAAAA==.Darrling:BAAALgAECgYJDgAAAA==.Davethelock:BAAALgAECgIJAgAAAA==.Dazarek:BAAALgAECgYJEAAAAA==.',
De='Deadpoolx:BAAALgAECgMJBAAAAA==.Demium:BAACLgAFFH8JAAINAAMJOBfJMQD1AANoDAAABABPAGkMAAADACIA6gwAAAIAQAANAAMJOBfJMQD1AANoDAAABABPAGkMAAADACIA6gwAAAIAQAAuAAQKfyIAAg0ACAlPIrYZALoCAA0ACAlPIrYZALoCAAEuAAQKBQkKAAIAAAAA.Demonkanaka:BAAALgADCgEJAQAAAA==.Deowulf:BAAALgADCgkJCQAAAA==.Desiinnorre:BAAALgADCggJCgAAAA==.Devinetoro:BAAALgAECgYJEQAAAA==.Devnull:BAAALgADCgIJAgAAAA==.Devour:BAABLgAECn8hAAIOAAkJGRclLAD/AQloDAAABQA6AGkMAAAEADsAawwAAAQAPABqDAAABABUAGwMAAAEAFAAbQwAAAIAEADqDAAABwBYAG4MAAACACQAbwwAAAEALgAOAAkJGRclLAD/AQloDAAABQA6AGkMAAAEADsAawwAAAQAPABqDAAABABUAGwMAAAEAFAAbQwAAAIAEADqDAAABwBYAG4MAAACACQAbwwAAAEALgAAAA==.Deznormu:BAAALgADCgEJAQAAAA==.',
Di='Diag:BAABLgAECn8WAAQPAAYJBxRtCAAyAQZoDAAABABJAGkMAAAEADwAawwAAAUAMQBqDAAAAwBSAGwMAAADAB0A6gwAAAMAKgAPAAYJBxRtCAAyAQZoDAAAAwBJAGkMAAACADwAawwAAAIAMQBqDAAAAwBSAGwMAAACAB0A6gwAAAEAKgAQAAMJLQYISACEAANpDAAAAQAUAGsMAAABAAsAbAwAAAEAEAARAAQJTRLFHgCEAARoDAAAAQA6AGkMAAABAB4AawwAAAIAIwDqDAAAAgA+AAAA.',
Do='Doree:BAAALgADCgYJBgAAAA==.Dotitndropit:BAAALgAECgQJBAAAAA==.',
Dr='Drakenn:BAAALgAECgYJDgABLgAFFAQJDAASALkKAA==.Dreadsofdeth:BAABLgAECn8VAAIHAAYJixh0ngCZAQZoDAAABAA+AGkMAAAEAEMAawwAAAQAQgBqDAAAAwAaAGwMAAADAEoA6gwAAAMAKwAHAAYJixh0ngCZAQZoDAAABAA+AGkMAAAEAEMAawwAAAQAQgBqDAAAAwAaAGwMAAADAEoA6gwAAAMAKwAAAA==.Drklhtkanaka:BAAALgADCgYJBgAAAA==.Drunkenbilly:BAAALgAECgEJAQAAAA==.',
['Dê']='Dêv:BAABLgAECn8gAAIEAAgJMg8XNACZAQhoDAAABQAwAGkMAAAFADoAawwAAAQAKwBqDAAABAApAGwMAAAFACEAbQwAAAIAGQDqDAAABgAqAG4MAAABABIABAAICTIPFzQAmQEIaAwAAAUAMABpDAAABQA6AGsMAAAEACsAagwAAAQAKQBsDAAABQAhAG0MAAACABkA6gwAAAYAKgBuDAAAAQASAAAA.',
Ei='Einheri:BAABLgAECn8bAAIJAAYJxBqVHgB7AQZoDAAABQBSAGkMAAAFAEMAawwAAAUAVQBqDAAABAAuAGwMAAADADwA6gwAAAUALgAJAAYJxBqVHgB7AQZoDAAABQBSAGkMAAAFAEMAawwAAAUAVQBqDAAABAAuAGwMAAADADwA6gwAAAUALgAAAA==.',
Ek='Eksos:BAAALgADCgcJBwAAAA==.',
El='Elalian:BAAALgADCggJEAAAAA==.Elracc:BAAALgAECggJDgAAAA==.Eltoronegro:BAAALgADCgEJAQAAAA==.Elure:BAAALgADCgEJAQAAAA==.',
En='Endarius:BAAALgADCgMJAwAAAA==.Endeavour:BAACLgAFFH8HAAIMAAIJGhLYGwCmAAJoDAAAAwAwAOoMAAAEACwADAACCRoS2BsApgACaAwAAAMAMADqDAAABAAsAC4ABAp/IwACDAAJCVATxAcANAIADAAJCVATxAcANAIAAAA=.Enoira:BAAALgAECgEJAQAAAA==.Enver:BAAALgADCgYJBgAAAA==.',
Ep='Epistle:BAAALgAECgQJBAAAAA==.',
Er='Erfing:BAAALgADCgcJCAAAAA==.Erinoa:BAAALgADCgEJAQAAAA==.',
Ev='Evillizard:BAAALgAECgYJDwAAAA==.',
Ex='Exhumer:BAAALgAECgYJEwAAAA==.',
Fa='Faffard:BAAALgAECgYJEAABLgAECggJJQATALIHAA==.Fame:BAAALgAFFAEJAQABLgAFFAQJDwAQAFEZAA==.Fara:BAAALgADCgMJAwAAAA==.Farsighted:BAAALgAECgEJAQAAAA==.',
Fe='Fearbilly:BAAALgAECgQJBAAAAA==.Fennerick:BAAALgAECgUJDQAAAA==.Feyndra:BAAALgAECgYJBgAAAA==.',
Fi='Fizzlenips:BAAALgAECgMJAwAAAA==.',
Fl='Flap:BAACLgAFFH8PAAIQAAQJURk5FABAAQRoDAAABQA+AGkMAAAEAFAAawwAAAIAKADqDAAABABKABAABAlRGTkUAEABBGgMAAAFAD4AaQwAAAQAUABrDAAAAgAoAOoMAAAEAEoALgAECn8ZAAMQAAgJThhsHADkAQAQAAgJThhsHADkAQAPAAEJAACfQAAvAAAAAA==.Fleureena:BAAALgADCgYJDQAAAA==.',
Fy='Fystie:BAAALgAECgYJEAABLgAECggJJQATALIHAA==.',
Ga='Galpally:BAAALgAECgYJEgAAAA==.Ganzar:BAAALgADCgMJBAABLgAECgkJGwAUAPQcAA==.Garin:BAAALgAECgUJBQAAAA==.',
Ge='Gennic:BAAALgADCgcJBwAAAA==.',
Gi='Gishongar:BAAALgADCgkJCQAAAA==.',
Gl='Glorak:BAABLgAECn8VAAIBAAYJvgX1ZgDgAAZoDAAABAAWAGkMAAAEAA8AawwAAAQACQBqDAAAAwAYAGwMAAADAAsA6gwAAAMADgABAAYJvgX1ZgDgAAZoDAAABAAWAGkMAAAEAA8AawwAAAQACQBqDAAAAwAYAGwMAAADAAsA6gwAAAMADgAAAA==.',
Gr='Grashen:BAAALgAECgYJEgAAAA==.Gravorik:BAAALgAECgUJCgAAAA==.Greefkarga:BAAALgADCgkJCgAAAA==.Grogu:BAAALgAECgYJDgAAAA==.',
Gs='Gsm:BAABLgAECn8ZAAIVAAYJQQ0ZMAD+AAZoDAAABQAlAGkMAAAFACgAawwAAAUALgBqDAAAAwAkAGwMAAADABEA6gwAAAQAGwAVAAYJQQ0ZMAD+AAZoDAAABQAlAGkMAAAFACgAawwAAAUALgBqDAAAAwAkAGwMAAADABEA6gwAAAQAGwAAAA==.',
Gu='Gulritz:BAAALgAECgEJAQAAAA==.',
Ha='Hante:BAAALgADCgQJBAAAAA==.Hartmonster:BAAALgAECgQJBAAAAA==.Hawaiianchi:BAAALgADCgQJBAAAAA==.Hawaiianvoid:BAAALgADCgYJBgAAAA==.',
He='Hellmouth:BAAALgADCgQJBAAAAA==.',
Hi='Hiawassee:BAABLgAECn8UAAMBAAcJIQWOagDWAAdoDAAAAwAHAGkMAAADABIAawwAAAMAEQBqDAAAAwAXAGwMAAADABEAbQwAAAEABADqDAAABAANAAEABgnSBY5qANYABmgMAAADAAcAaQwAAAMAEgBrDAAAAwARAGoMAAADABcAbAwAAAMAEQDqDAAABAANABIAAQmuAQwvAB8AAW0MAAABAAQAAAA=.',
Ho='Holydps:BAAALgAECgcJDgAAAA==.Holyloh:BAAALgADCgIJAgAAAA==.Hoompukka:BAAALgAECgEJAQAAAA==.',
Hy='Hypia:BAAALgADCgEJAQAAAA==.',
Ii='Iit:BAAALgADCgcJBgAAAA==.',
Il='Ilokana:BAAALgAECgEJAgAAAA==.',
In='Inuyashi:BAAALgADCgMJAwAAAA==.',
Ir='Ironfist:BAAALgAECgYJCwAAAA==.',
It='Itzbarney:BAAALgAECgUJBQAAAA==.',
Ja='Jacsace:BAAALgADCgQJBAAAAA==.Jacspally:BAAALgAECgYJEQAAAA==.Jailbayt:BAAALgAECgYJCgAAAA==.Janora:BAABLgAECn8WAAIWAAYJpiCjBwDNAQZoDAAABABZAGkMAAAEAFQAawwAAAQAUABqDAAAAwBVAGwMAAADAE8A6gwAAAQAUgAWAAYJpiCjBwDNAQZoDAAABABZAGkMAAAEAFQAawwAAAQAUABqDAAAAwBVAGwMAAADAE8A6gwAAAQAUgAAAA==.Jarlath:BAAALgADCgEJAQAAAA==.',
Je='Jebra:BAABLgAECn8YAAIXAAYJVg9MJwARAQZoDAAABAA3AGkMAAAFADAAawwAAAUAJABqDAAAAwAnAGwMAAADABsA6gwAAAQAHAAXAAYJVg9MJwARAQZoDAAABAA3AGkMAAAFADAAawwAAAUAJABqDAAAAwAnAGwMAAADABsA6gwAAAQAHAAAAA==.Jellexy:BAAALgAECgYJEAAAAA==.',
Jo='Jolah:BAAALgADCgMJAwAAAA==.Jolahbae:BAACLgAFFH8HAAIYAAMJcw6pGQC/AANoDAAABAA9AGkMAAACACAA6gwAAAEAEQAYAAMJcw6pGQC/AANoDAAABAA9AGkMAAACACAA6gwAAAEAEQAuAAQKfysAAhgACAk2HcMKAEoCABgACAk2HcMKAEoCAAAA.Jonnyfive:BAAALgAECgMJAwAAAA==.',
Ka='Kaehlen:BAAALgADCgkJCQAAAA==.Kaigon:BAAALgADCgEJAQAAAA==.Kailis:BAABLgAECn8dAAIBAAgJThYUIQDaAQhoDAAABQAqAGkMAAAEAEgAawwAAAQARQBqDAAABABCAGwMAAAEACoAbQwAAAIANgDqDAAABQAxAG4MAAABAEUAAQAICU4WFCEA2gEIaAwAAAUAKgBpDAAABABIAGsMAAAEAEUAagwAAAQAQgBsDAAABAAqAG0MAAACADYA6gwAAAUAMQBuDAAAAQBFAAAA.Kaisa:BAAALgADCgcJBwAAAA==.Kanne:BAAALgADCgMJAwAAAA==.Karst:BAAALgAECgYJCgAAAA==.Katsudin:BAAALgAECgUJBQAAAA==.Kayzon:BAACLgAFFH8iAAMBAAcJkCE9AAB4AgdoDAAABQBgAGkMAAAGAGMAawwAAAYAYwBqDAAABQBJAGwMAAAEAFsAbQwAAAIANgDqDAAABgBJAAEABwmQIT0AAHgCB2gMAAADAGAAaQwAAAYAYwBrDAAABQBjAGoMAAABAEkAbAwAAAIAWwBtDAAAAgA2AOoMAAAFAEkAEgAFCVkHvQoAbgEFaAwAAAIAMwBrDAAAAQAKAGoMAAAEADAAbAwAAAIAAwDqDAAAAQAJAC4ABAp/OAADAQAJCRkmLQEAVgMAEgAJCRgijgIAiQMAAQAJCRYmLQEAVgMAAAA=.Kayzwei:BAAALgAECgYJEwAAAA==.',
Ke='Kegtap:BAAALgADCgEJAQAAAA==.',
Ki='Kij:BAAALgAECgEJAQAAAA==.Kill:BAAALgAECgYJBgAAAA==.Killaks:BAAALgAECgYJBgAAAA==.Killdo:BAAALgAECgEJAQAAAA==.Kirilla:BAAALgADCgEJAQAAAA==.',
Kl='Klavine:BAABLgAECn80AAIZAAkJMRrlAQBTAgloDAAABwBaAGkMAAAGAE8AawwAAAYASABqDAAABQAvAGwMAAAGAFAAbQwAAAUAQADqDAAABwBIAG4MAAAGADgAbwwAAAQAEwAZAAkJMRrlAQBTAgloDAAABwBaAGkMAAAGAE8AawwAAAYASABqDAAABQAvAGwMAAAGAFAAbQwAAAUAQADqDAAABwBIAG4MAAAGADgAbwwAAAQAEwAAAA==.Klavinester:BAAALgAECgcJBwAAAA==.',
Ko='Korben:BAABLgAECn8fAAIaAAkJbRcDGADXAQloDAAABQA+AGkMAAAEAEkAawwAAAQAQABqDAAABABSAGwMAAAEAEEAbQwAAAIAIADqDAAABQBQAG4MAAACADsAbwwAAAEAEwAaAAkJbRcDGADXAQloDAAABQA+AGkMAAAEAEkAawwAAAQAQABqDAAABABSAGwMAAAEAEEAbQwAAAIAIADqDAAABQBQAG4MAAACADsAbwwAAAEAEwAAAA==.Korenna:BAAALgADCgUJCgAAAA==.',
Kr='Kronn:BAAALgAECgIJAgAAAA==.Kruger:BAABLgAECn8ZAAIEAAYJqga7dADmAAZoDAAABgARAGkMAAAFABcAawwAAAQACQBqDAAAAgATAGwMAAAEABIA6gwAAAQAEAAEAAYJqga7dADmAAZoDAAABgARAGkMAAAFABcAawwAAAQACQBqDAAAAgATAGwMAAAEABIA6gwAAAQAEAAAAA==.Kryptonicboy:BAAALgAECgMJBAAAAA==.',
Kt='Ktanna:BAAALgAECgYJDwAAAA==.',
Ku='Kublakhan:BAAALgAECgYJCwAAAA==.',
Ky='Kyfu:BAAALgADCgMJAwABLgAFFAUJFAAGAFUdAA==.Kynleria:BAAALgADCgEJAQAAAA==.',
La='Lakhi:BAABLgAECn8eAAIFAAgJQx7YGAD5AQhoDAAABQBdAGkMAAAEAFUAawwAAAQAWQBqDAAAAgBXAGwMAAADAFAAbQwAAAIAJADqDAAABwBRAG4MAAADAEEABQAICUMe2BgA+QEIaAwAAAUAXQBpDAAABABVAGsMAAAEAFkAagwAAAIAVwBsDAAAAwBQAG0MAAACACQA6gwAAAcAUQBuDAAAAwBBAAAA.Lateralus:BAAALgAECgYJEwAAAA==.Laureli:BAAALgAECgYJCgAAAA==.',
Le='Leeta:BAAALgAECgYJDgAAAA==.Legendx:BAAALgADCgUJBwAAAA==.',
Li='Lightningg:BAAALgAECgYJEgAAAA==.Lightsaved:BAAALgADCgIJAgAAAA==.Lightsworn:BAAALgAECgIJAgAAAA==.Linara:BAAALgADCgIJAgAAAA==.',
Lo='Lockbite:BAAALgADCgEJAQAAAA==.Lokralaila:BAAALgADCgQJBAAAAA==.Lollypopp:BAAALgAECgcJAQAAAA==.Lomme:BAAALgADCgcJBwAAAA==.Loraemar:BAAALgAECgIJAgAAAA==.Losoz:BAAALgAECgEJAQAAAA==.',
Lu='Lusilsandrus:BAAALgAECgUJDAAAAA==.Luxanna:BAAALgAECgIJAQAAAA==.',
Ma='Maegwin:BAAALgAECgYJBgAAAA==.Mahoutsukai:BAAALgAECgcJCwAAAA==.Malefiscent:BAAALgADCgIJAgAAAA==.Matti:BAAALgAECgYJDgAAAA==.',
Me='Mechaknight:BAAALgAECgUJCAAAAA==.Meddler:BAAALgADCgQJBQAAAA==.',
Mi='Mildrik:BAAALgAECgYJEgAAAA==.Miracledh:BAABLgAECn8WAAIbAAYJKiZvBwAxAgZoDAAABQBiAGkMAAAFAGMAawwAAAMAXgBqDAAAAwBdAGwMAAABAGEA6gwAAAUAYQAbAAYJKiZvBwAxAgZoDAAABQBiAGkMAAAFAGMAawwAAAMAXgBqDAAAAwBdAGwMAAABAGEA6gwAAAUAYQAAAA==.Mirkdrak:BAAALgAECgYJEQAAAA==.Misheard:BAABLgAECn8lAAINAAkJeR+pJwCnAQloDAAABQBgAGkMAAAFAFoAawwAAAUAWQBqDAAABQBUAGwMAAAFAFEAbQwAAAMANgDqDAAABQBhAG4MAAACAE8AbwwAAAIANgANAAkJeR+pJwCnAQloDAAABQBgAGkMAAAFAFoAawwAAAUAWQBqDAAABQBUAGwMAAAFAFEAbQwAAAMANgDqDAAABQBhAG4MAAACAE8AbwwAAAIANgAAAA==.Misjudged:BAAALgAECgYJEwAAAA==.Missus:BAAALgAECgYJCgAAAA==.Mit:BAAALgADCgkJGAAAAA==.Miyu:BAAALgAECgEJAQAAAA==.Mizzen:BAABLgAECn8dAAIcAAcJpRiiFQCKAQdoDAAABwBMAGkMAAAFAD0AawwAAAYARQBqDAAAAwAzAGwMAAADAEYA6gwAAAQATABuDAAAAQAYABwABwmlGKIVAIoBB2gMAAAHAEwAaQwAAAUAPQBrDAAABgBFAGoMAAADADMAbAwAAAMARgDqDAAABABMAG4MAAABABgAAS4ABRQFCREACgDeFAA=.',
Mo='Mohtavius:BAABLgAECn8WAAILAAYJTBFEGAACAQZoDAAABQAuAGkMAAAEACcAawwAAAMAIQBqDAAAAwAqAGwMAAADADoA6gwAAAQAKwALAAYJTBFEGAACAQZoDAAABQAuAGkMAAAEACcAawwAAAMAIQBqDAAAAwAqAGwMAAADADoA6gwAAAQAKwAAAA==.Mohz:BAAALgADCgcJCwAAAA==.Mommydearest:BAABLgAECn8lAAITAAgJsgfbDAAOAQhoDAAABwAkAGkMAAAGABYAawwAAAYAJQBqDAAABQAfAGwMAAAEAAoAbQwAAAIABgDqDAAABQASAG4MAAACAAQAEwAICbIH2wwADgEIaAwAAAcAJABpDAAABgAWAGsMAAAGACUAagwAAAUAHwBsDAAABAAKAG0MAAACAAYA6gwAAAUAEgBuDAAAAgAEAAAA.Moonbaboon:BAAALgAECgcJDAAAAA==.Moonkissed:BAAALgAECgEJAgAAAA==.Moonrizer:BAAALgAECgIJAgAAAA==.Morttimuss:BAAALgAECgQJBQAAAA==.Motz:BAAALgADCgUJBgAAAA==.',
Mu='Munkìe:BAAALgAECgIJAwABLgAECgYJGQAVAEENAA==.Muura:BAABLgAECn8eAAIUAAgJ2QvMiADcAAhoDAAAAwAVAGkMAAADABoAawwAAAMADgBqDAAABQAtAGwMAAAFADYAbQwAAAMAFwDqDAAABgA0AG4MAAACABIAFAAICdkLzIgA3AAIaAwAAAMAFQBpDAAAAwAaAGsMAAADAA4AagwAAAUALQBsDAAABQA2AG0MAAADABcA6gwAAAYANABuDAAAAgASAAAA.',
My='Myextralife:BAAALgADCgYJBgAAAA==.Myrik:BAAALgAECgQJDAAAAA==.',
Na='Naslunda:BAAALgADCgIJAgAAAA==.Nathyrra:BAABLgAECn8fAAIFAAgJyxdTFAAhAghoDAAABQBTAGkMAAAFAEMAawwAAAUAQQBqDAAABABQAGwMAAAEAEgAbQwAAAEAGADqDAAABgAzAG4MAAABACoABQAICcsXUxQAIQIIaAwAAAUAUwBpDAAABQBDAGsMAAAFAEEAagwAAAQAUABsDAAABABIAG0MAAABABgA6gwAAAYAMwBuDAAAAQAqAAAA.',
Ne='Nebekenazar:BAAALgAECgYJCgAAAA==.Negate:BAAALgAFFAEJAQABLgAFFAYJGwARAEEeAA==.',
Ni='Nitrö:BAAALgAECgEJAQABLgAECgQJCAACAAAAAA==.',
No='Noreset:BAAALgADCgYJBgAAAA==.Noriea:BAAALgADCgEJAQAAAA==.',
Nu='Nufonhudis:BAAALgAECgQJCAAAAA==.',
Om='Omnidacc:BAAALgAECgIJAgAAAA==.',
On='Onigirius:BAAALgAECgYJBgAAAA==.',
Op='Optional:BAAALgAECgEJAgAAAA==.',
Ot='Otwin:BAAALgAECgQJBwAAAA==.',
Pa='Pahuum:BAAALgAECgIJAgAAAA==.Paimon:BAAALgAECgUJCAABLgAFFAQJDwAQAFEZAA==.Paintrainn:BAAALgAECgYJDgAAAA==.Palewhiteman:BAABLgAECn8aAAIaAAgJ5hlLDABZAghoDAAABQBeAGkMAAAEABkAawwAAAUAMwBqDAAABABOAGwMAAAEAEwAbQwAAAEAPQDqDAAAAgBaAG4MAAABADMAGgAICeYZSwwAWQIIaAwAAAUAXgBpDAAABAAZAGsMAAAFADMAagwAAAQATgBsDAAABABMAG0MAAABAD0A6gwAAAIAWgBuDAAAAQAzAAAA.Palleigh:BAAALgAECgYJEQAAAA==.Pallyd:BAAALgADCgEJAQAAAA==.Patchës:BAAALgAECgQJCAAAAA==.',
Pe='Pepperjack:BAAALgAECgYJDgAAAA==.Persephonae:BAAALgADCgQJBAAAAA==.Persimmon:BAABLgAECn8WAAIBAAYJNxZaRgA8AQZoDAAABABEAGkMAAAEAD4AawwAAAQANABqDAAAAwBJAGwMAAADAC8A6gwAAAQANQABAAYJNxZaRgA8AQZoDAAABABEAGkMAAAEAD4AawwAAAQANABqDAAAAwBJAGwMAAADAC8A6gwAAAQANQAAAA==.',
Pi='Pikklerikk:BAAALgAECgYJDAAAAA==.',
Po='Poondor:BAAALgAECgYJDwAAAA==.Poplocndrop:BAAALgAECgMJAwAAAA==.',
Pr='Predaturd:BAAALgAECgQJAwAAAA==.',
Pu='Purgatorri:BAAALgAECgQJBwAAAA==.',
Qi='Qindere:BAAALgAECgYJEQAAAA==.',
Ra='Raalaan:BAAALgADCgEJAQAAAA==.Raeinthe:BAABLgAECn8wAAIBAAkJnRN4HAD2AQloDAAABwBFAGkMAAAHADwAawwAAAcAOwBqDAAABgAkAGwMAAAEACgAbQwAAAQAHgDqDAAABgA+AG4MAAAEAC8AbwwAAAMAHwABAAkJnRN4HAD2AQloDAAABwBFAGkMAAAHADwAawwAAAcAOwBqDAAABgAkAGwMAAAEACgAbQwAAAQAHgDqDAAABgA+AG4MAAAEAC8AbwwAAAMAHwAAAA==.Ramantu:BAAALgADCgcJBwAAAA==.Rancor:BAAALgAECgMJBAABLgAECgkJGwAUAPQcAA==.',
Re='Reihino:BAAALgADCgcJBwAAAA==.Resbak:BAAALgAECgcJCwAAAA==.Resiaus:BAABLgAECn8zAAIRAAkJ7RtkAgDfAgloDAAABwBbAGkMAAAHAFQAawwAAAcAUgBqDAAABgA5AGwMAAAGAEMAbQwAAAUAPQDqDAAABwA1AG4MAAAEAFgAbwwAAAIAOAARAAkJ7RtkAgDfAgloDAAABwBbAGkMAAAHAFQAawwAAAcAUgBqDAAABgA5AGwMAAAGAEMAbQwAAAUAPQDqDAAABwA1AG4MAAAEAFgAbwwAAAIAOAAAAA==.',
Ri='Ripptyde:BAAALgADCgQJBAAAAA==.Rivalina:BAAALgAECgYJBgAAAA==.',
Ro='Robilargreen:BAAALgADCgUJBQAAAA==.Rocketabu:BAAALgAECgMJAwAAAA==.Roctheist:BAAALgAECgYJDwAAAA==.Rocthoeb:BAABLgAECn80AAILAAkJxRH/EQDoAQloDAAACABCAGkMAAAIAEYAawwAAAgANgBqDAAACAAvAGwMAAAHAEQAbQwAAAIAEwDqDAAABgAyAG4MAAAEACEAbwwAAAEAAAALAAkJxRH/EQDoAQloDAAACABCAGkMAAAIAEYAawwAAAgANgBqDAAACAAvAGwMAAAHAEQAbQwAAAIAEwDqDAAABgAyAG4MAAAEACEAbwwAAAEAAAAAAA==.Rojito:BAAALgADCgkJGAAAAA==.',
Ry='Ry:BAABLgAECn8dAAIdAAgJmB8DAwBxAghoDAAABQBYAGkMAAAFAF4AawwAAAQAVQBqDAAAAwBEAGwMAAACADEAbQwAAAEAXQDqDAAABABLAG4MAAAFAE8AHQAICZgfAwMAcQIIaAwAAAUAWABpDAAABQBeAGsMAAAEAFUAagwAAAMARABsDAAAAgAxAG0MAAABAF0A6gwAAAQASwBuDAAABQBPAAAA.',
Sa='Saeris:BAAALgAECgMJAwAAAA==.Saintfrosty:BAEALgADCgEJAQABLgAECggJFAADAJkTAA==.Saintkhal:BAEALgAECgQJCAABLgAECggJFAADAJkTAA==.Saintmedicus:BAEBLgAECn8UAAMDAAgJmRPGHQBMAQhoDAAABQBCAGkMAAADADYAawwAAAMAOABqDAAAAgBGAGwMAAABACoAbQwAAAEAJQDqDAAABAAyAG4MAAABABYAAwAFCWQXxh0ATAEFaAwAAAUAQgBpDAAAAwA2AGsMAAADADgAagwAAAIARgDqDAAABAAyAAoAAwnVDW06AKkAA2wMAAABAC8AbQwAAAEAGwBuDAAAAQAfAAAA.Saintshammy:BAAALgAFFAEJAgAAAA==.Saintshunter:BAAALgAECgEJAQAAAA==.Sanctor:BAABLgAECn8dAAIaAAcJeyJ0EgB/AgdoDAAABQBWAGkMAAAEAGEAawwAAAUAWwBqDAAABABDAGwMAAAEAFkAbQwAAAIAVgDqDAAABQBiABoABwl7InQSAH8CB2gMAAAFAFYAaQwAAAQAYQBrDAAABQBbAGoMAAAEAEMAbAwAAAQAWQBtDAAAAgBWAOoMAAAFAGIAAAA=.Sandusky:BAAALgADCgQJBAAAAA==.Saraya:BAAALgAECgYJEAAAAA==.',
Se='Sephafael:BAAALgAECgIJAgAAAA==.Setsena:BAABLgAECn8WAAIDAAYJKRtTEADdAQZoDAAABABJAGkMAAAEADQAawwAAAQARwBqDAAAAwBLAGwMAAADAE0A6gwAAAQAQgADAAYJKRtTEADdAQZoDAAABABJAGkMAAAEADQAawwAAAQARwBqDAAAAwBLAGwMAAADAE0A6gwAAAQAQgAAAA==.',
Sh='Shamwow:BAAALgAECgQJBAAAAA==.Shangi:BAAALgADCgMJAwAAAA==.Shinstabber:BAABLgAECn8WAAIeAAYJrwcxIwC3AAZoDAAABAAOAGkMAAAEAB0AawwAAAQAFgBqDAAAAwAIAGwMAAADABYA6gwAAAQACgAeAAYJrwcxIwC3AAZoDAAABAAOAGkMAAAEAB0AawwAAAQAFgBqDAAAAwAIAGwMAAADABYA6gwAAAQACgAAAA==.Shivantis:BAAALgADCgUJBQAAAA==.Shlarya:BAAALgAECgEJAQABLgAECggJDwACAAAAAA==.Shruggie:BAAALgAECgYJEwAAAA==.',
Si='Silven:BAAALgAECgYJBgAAAA==.Singingsword:BAAALgAECgEJAQAAAA==.Siphond:BAAALgAECgQJBAAAAA==.Siphondark:BAABLgAECn8WAAIYAAYJmBvyEgDVAQZoDAAABAA9AGkMAAAEAEQAawwAAAQAQwBqDAAAAwBGAGwMAAADAFEA6gwAAAQASgAYAAYJmBvyEgDVAQZoDAAABAA9AGkMAAAEAEQAawwAAAQAQwBqDAAAAwBGAGwMAAADAFEA6gwAAAQASgAAAA==.Sisqi:BAAALgADCgQJBAAAAA==.',
Sl='Slapnutz:BAABLgAECn8bAAIBAAcJ3xVwLwD0AQdoDAAABQAoAGkMAAAEAEIAawwAAAUAPgBqDAAABAAuAGwMAAAEAD4AbQwAAAEAEgDqDAAABABVAAEABwnfFXAvAPQBB2gMAAAFACgAaQwAAAQAQgBrDAAABQA+AGoMAAAEAC4AbAwAAAQAPgBtDAAAAQASAOoMAAAEAFUAAAA=.',
Sm='Smidgen:BAAALgADCgcJCAAAAA==.Smoki:BAAALgAECgUJBQAAAA==.',
So='Solvaii:BAABLgAECn8YAAISAAgJYAaUDQAaAQhoDAAABAAYAGkMAAAEABEAawwAAAQAEgBqDAAAAwAUAGwMAAADAA4AbQwAAAEAEQDqDAAABAARAG4MAAABAAQAEgAICWAGlA0AGgEIaAwAAAQAGABpDAAABAARAGsMAAAEABIAagwAAAMAFABsDAAAAwAOAG0MAAABABEA6gwAAAQAEQBuDAAAAQAEAAAA.',
St='Starfail:BAAALgAECgYJDgABLgAFFAQJCgAFADYRAA==.Starlie:BAAALgAECgUJBQAAAA==.Stratacaster:BAAALgAECgMJBgAAAA==.Strawberry:BAAALgAECgUJCwAAAA==.Stuckinwell:BAACLgAFFH8FAAMEAAIJkBjpNQCnAAJoDAAAAwBDAOoMAAACADkABAACCRgQ6TUApwACaAwAAAMAQwDqDAAAAQAOABMAAQmUFuARAFUAAeoMAAABADkALgAECn8bAAMEAAkJ+hq9MwA9AgAEAAgJ6Ra9MwA9AgATAAUJDRxAGACIAQAAAA==.',
Su='Sunbound:BAABLgAFFH8KAAIOAAIJhh6OFQC3AAJoDAAABAA5AOoMAAAGAGIADgACCYYejhUAtwACaAwAAAQAOQDqDAAABgBiAAEuAAUUBgkbABEAQR4A.',
Sx='Sxths:BAAALgAECgEJAQAAAA==.',
Sy='Syela:BAAALgAECgQJDAABLgAECgcJJAAeAFQRAA==.Synsyn:BAAALgAECgQJCQAAAA==.',
Ta='Tach:BAAALgADCgYJBgAAAA==.Tanel:BAAALgAECgYJCAAAAA==.Targonne:BAAALgADCgEJAQAAAA==.Taterhots:BAAALgADCgcJBwAAAA==.Tatsü:BAAALgAECgIJAQAAAA==.Taílorswift:BAABLgAECn8dAAIHAAkJaw1mTQCIAQloDAAABAAjAGkMAAAEACMAawwAAAQAJQBqDAAAAwAuAGwMAAADADQAbQwAAAEACQDqDAAABgAtAG4MAAADACkAbwwAAAEAEgAHAAkJaw1mTQCIAQloDAAABAAjAGkMAAAEACMAawwAAAQAJQBqDAAAAwAuAGwMAAADADQAbQwAAAEACQDqDAAABgAtAG4MAAADACkAbwwAAAEAEgAAAA==.',
Te='Teanfists:BAAALgAECgEJBAAAAA==.Temna:BAABLgAECn8ZAAIfAAYJLh4JNQCzAQZoDAAABQBRAGkMAAAFAFMAawwAAAUAQwBqDAAAAwBYAGwMAAADAEoA6gwAAAQATwAfAAYJLh4JNQCzAQZoDAAABQBRAGkMAAAFAFMAawwAAAUAQwBqDAAAAwBYAGwMAAADAEoA6gwAAAQATwAAAA==.Tenari:BAAALgAECggJDwAAAA==.',
Th='Theel:BAAALgAECgQJCgAAAA==.Thespaniard:BAABLgAECn8cAAIKAAcJPhnSEgC8AQdoDAAABABEAGkMAAAFAE8AawwAAAUAMQBqDAAABABBAGwMAAADADkAbQwAAAIAOgDqDAAABQBLAAoABwk+GdISALwBB2gMAAAEAEQAaQwAAAUATwBrDAAABQAxAGoMAAAEAEEAbAwAAAMAOQBtDAAAAgA6AOoMAAAFAEsAAAA=.Thlunk:BAAALgADCgkJCQAAAA==.',
Ti='Tidebreaker:BAAALgAECgYJDwAAAA==.Tidepods:BAAALgAECgYJBgAAAA==.Tinbasher:BAAALgAECgQJBgAAAA==.',
Tj='Tjay:BAAALgADCgEJAQAAAA==.',
To='Totemistic:BAAALgADCggJCgAAAA==.',
Tr='Treebilly:BAAALgAECgYJBwAAAA==.Tricky:BAAALgAECgEJAQAAAA==.Triviousox:BAAALgAECgYJDwAAAA==.',
Tu='Tungo:BAAALgADCgEJAQAAAA==.',
Tw='Twilightjade:BAAALgADCggJDwABLgAFFAMJCAAHAP8TAA==.Twotvmage:BAABLgAECn8jAAMHAAgJyRjCKwD6AQhoDAAABQA+AGkMAAAFAEIAawwAAAUAQABqDAAABQBOAGwMAAAGAEMAbQwAAAEAOwDqDAAABQBFAG4MAAADADUABwAICckYwisA+gEIaAwAAAUAPgBpDAAABQBCAGsMAAAEAEAAagwAAAUATgBsDAAABgBDAG0MAAABADsA6gwAAAUARQBuDAAAAwA1ACAAAQkgDUkOADgAAWsMAAABACEAAAA=.',
Ug='Uglyboyryan:BAAALgAECgQJBAAAAA==.',
Un='Unglued:BAAALgADCgcJFQAAAA==.Unholygrimg:BAAALgADCgUJBQAAAA==.Unholywar:BAAALgAECgYJCQAAAA==.',
Up='Uplift:BAAALgAECgcJBwABLgAFFAYJEAAHAPgeAA==.',
Ur='Ursolana:BAAALgADCgUJBQAAAA==.',
Va='Valkky:BAABLgAECn8XAAMhAAYJvw1lDwDUAAZoDAAABAAhAGkMAAAFACMAawwAAAUAHgBqDAAAAwAmAGwMAAADABkA6gwAAAMAMwAhAAYJ0wtlDwDUAAZoDAAAAgAhAGkMAAADABoAawwAAAMAHgBqDAAAAwAmAGwMAAADABkA6gwAAAIAIwANAAQJOA0RowDOAARoDAAAAgAZAGkMAAACACMAawwAAAIAFwDqDAAAAQAzAAAA.Valky:BAAALgADCgQJBAABLgAECgYJFwAhAL8NAA==.Valleya:BAAALgAECgIJAgAAAA==.Vallysong:BAAALgAECgcJEgAAAA==.Valnetrois:BAAALgADCgEJAQAAAA==.Vaswislor:BAAALgAECgEJAgAAAA==.',
Ve='Velayna:BAAALgAECgYJCgAAAA==.Velenn:BAAALgAECgEJAQABLgAECgcJEgACAAAAAA==.Vellani:BAAALgAECgEJAQAAAA==.Venatar:BAABLgAECn8ZAAIBAAYJjRjCOQBpAQZoDAAABQBUAGkMAAAFAFAAawwAAAUAJQBqDAAAAwAxAGwMAAADAD8A6gwAAAQAMQABAAYJjRjCOQBpAQZoDAAABQBUAGkMAAAFAFAAawwAAAUAJQBqDAAAAwAxAGwMAAADAD8A6gwAAAQAMQAAAA==.Vessna:BAAALgAECgQJDAABLgAECgYJEQACAAAAAA==.',
Vi='Vicarious:BAAALgAECgYJEwAAAA==.Visea:BAAALgADCgEJAQAAAA==.Vivîán:BAAALgAECgYJDAAAAA==.',
Vm='Vmro:BAAALgADCgYJEQAAAA==.',
Vo='Voras:BAAALgAECgUJEAAAAA==.Vorttex:BAAALgAECgEJAQAAAA==.',
Wa='Waitandbleed:BAAALgADCgcJBwAAAA==.Wanglock:BAAALgAECgYJDAABLgAFFAgJHAAQAGYcAA==.Wardstar:BAAALgADCgIJAgAAAA==.Wasure:BAAALgAECgYJDgAAAA==.',
Wh='Whiskeyrick:BAAALgADCgMJAwAAAA==.',
Wi='Wildkanaka:BAAALgADCgEJAQAAAA==.Winters:BAAALgADCggJCAAAAA==.',
Wo='Worthy:BAAALgADCgYJBgAAAA==.',
Xa='Xalatath:BAABLgAECn8YAAIKAAgJ4RsFEQB4AghoDAAAAwBVAGkMAAAEAFsAawwAAAIARgBqDAAABAAhAGwMAAAEAEEAbQwAAAIAJADqDAAAAwBWAG4MAAACAD8ACgAICeEbBREAeAIIaAwAAAMAVQBpDAAABABbAGsMAAACAEYAagwAAAQAIQBsDAAABABBAG0MAAACACQA6gwAAAMAVgBuDAAAAgA/AAAA.',
Xt='Xtra:BAAALgADCgEJAQAAAA==.',
Xy='Xylar:BAAALgAFFAIJAgAAAA==.',
Ya='Yahiko:BAAALgAECgMJAwAAAA==.',
Yu='Yuzuriha:BAAALgAECgQJCQAAAA==.',
Za='Zarazard:BAAALgAECgQJBAAAAA==.',
Ze='Zeynah:BAAALgADCgYJBgAAAA==.',
Zo='Zophier:BAAALgADCgMJAwAAAA==.',
Zu='Zube:BAAALgAECgUJBwAAAA==.',
['Âu']='Âuranna:BAAALgAECgYJCgAAAA==.',
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

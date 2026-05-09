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

local lookup = {'Shaman-Restoration','Hunter-Marksmanship','Unknown-Unknown','Shaman-Enhancement','Shaman-Elemental','Mage-Frost','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Warrior-Fury','Priest-Discipline','Druid-Restoration','Evoker-Augmentation','Evoker-Devastation','Hunter-BeastMastery','Mage-Arcane','Paladin-Protection','DemonHunter-Havoc','DemonHunter-Devourer','DeathKnight-Unholy','Druid-Guardian','Priest-Holy','Monk-Mistweaver','Monk-Windwalker','Druid-Balance','Rogue-Subtlety','Monk-Brewmaster','Paladin-Retribution','Priest-Shadow','Paladin-Holy','Hunter-Survival','DeathKnight-Frost','Druid-Feral','DemonHunter-Vengeance','Warrior-Protection','DeathKnight-Blood','Evoker-Preservation',}
local provider = {region='US',realm='Gurubashi',name='US',type='weekly',zone=46,date='2026-05-08',data={Aa='Aadrisedh:BAAALgAECgYJBgAAAA==.Aaeryñ:BAAALgAECgcJBwAAAA==.Aaliyshaa:BAAALgAECgYJCwAAAA==.Aaramis:BAABLgAECn8eAAIBAAgJchCQOQCbAQABAAgJchCQOQCbAQAAAA==.',
Ab='Abandyn:BAAALgADCgcJCwAAAA==.',
Ad='Adrisehunt:BAAALgADCgQJBAAAAA==.',
Ae='Aegira:BAAALgADCgUJBgAAAA==.Aelira:BAAALgADCgkJCwAAAA==.Aendoril:BAAALgAECgQJDAAAAA==.',
Ag='Aggrodk:BAAALgAECgIJAgAAAA==.',
Ai='Aidoffhealer:BAAALgAECgQJBgAAAA==.',
Al='Alariah:BAAALgAECgYJDgAAAQ==.Alaín:BAABLgAECn8jAAICAAgJqxhuBAD1AQACAAgJqxhuBAD1AQAAAA==.Aldoladre:BAAALgADCgYJBgABLgAECgYJCgADAAAAAA==.Aldoraline:BAAALgADCgIJAwAAAA==.Alegedly:BAAALgADCgcJBwAAAA==.Alicê:BAAALgADCgYJCQABLgAECgEJAQADAAAAAA==.Alystair:BAAALgADCgQJCAABLgAECgcJEQADAAAAAA==.',
Am='Ambellina:BAAALgAECgQJBQAAAA==.Ampse:BAAALgAECgUJCAAAAA==.Amzy:BAAALgADCgYJCQAAAA==.',
An='Anaria:BAAALgAECgQJCAAAAA==.Angbu:BAABLgAECn8aAAMEAAcJew/SCgBmAQAEAAcJew/SCgBmAQAFAAEJoARakQAmAAAAAA==.Angelpika:BAAALgADCgEJAQAAAA==.',
Ap='Aphadiri:BAAALgAECgMJBAAAAA==.Apinkninja:BAABLgAECn8iAAIGAAcJthn3QQChAQAGAAcJthn3QQChAQAAAA==.',
Ar='Aranyssa:BAABLgAECn8UAAQHAAkJ3RL8HACKAAAIAAYJeBDVoQAVAQAJAAMJ2hWHRQCgAAAHAAIJsBj8HACKAAAAAA==.Arch:BAAALgAECgIJAgABLgAFFAQJDAAIAGAcAA==.Arclock:BAAALgADCgcJBwAAAA==.Arconnai:BAABLgAFFH8IAAIKAAMJagqgGwDZAAAKAAMJagqgGwDZAAAAAA==.Ardur:BAAALgAECgMJAwAAAA==.Arnøld:BAAALgAECgEJAQAAAA==.Arruna:BAAALgAECgYJEQAAAA==.Artorìas:BAAALgADCgkJCwABLgAECgcJEQADAAAAAA==.',
As='Asham:BAABLgAECn8eAAILAAgJXgzJFwB4AQALAAgJXgzJFwB4AQAAAA==.Ashenbloom:BAABLgAECn8UAAIMAAcJQwiESgDpAAAMAAcJQwiESgDpAAAAAA==.Asiago:BAABLgAECn8WAAMNAAkJKhIZLQBYAQANAAkJKhIZLQBYAQAOAAEJRgetPwAxAAAAAA==.Aspect:BAAALgAECgcJEQAAAA==.',
Au='Augmenter:BAAALgAECgIJAgAAAA==.Aureliah:BAAALgADCgcJBwAAAA==.Autable:BAAALgAECgQJBQAAAA==.',
Av='Avacúma:BAAALgAECgEJAgAAAA==.Avvalethra:BAABLgAECn8sAAMPAAgJxRcyGQAIAgAPAAgJxRcyGQAIAgACAAgJqQ3POwBwAQAAAA==.',
Ax='Axane:BAAALgADCggJCgAAAA==.',
Ay='Ayekea:BAAALgAECgcJCwAAAA==.',
Az='Azenet:BAAALgAECgEJAQABLgAFFAcJFAANALkdAA==.',
['Aé']='Aélyrá:BAAALgAECgEJAQAAAA==.',
Ba='Bachshots:BAAALgAFFAQJBAAAAA==.Badassbich:BAAALgADCgEJAQAAAA==.Baggett:BAAALgAECgYJCAAAAA==.Bainey:BAAALgADCgIJAgABLgADCgYJCgADAAAAAA==.Bananataffy:BAAALgAECgMJBQAAAA==.Barackoshama:BAABLgAECn8aAAIFAAkJWhi9IwDyAQAFAAkJWhi9IwDyAQAAAA==.Barfdrinker:BAAALgAECgYJBwAAAA==.Barlaina:BAAALgADCgEJAQAAAA==.Basedween:BAAALgADCgYJDgAAAA==.Battlescars:BAAALgAFFAIJAgAAAA==.Baw:BAABLgAECn8oAAMGAAgJIxskIgAgAgAGAAgJIxskIgAgAgAQAAMJFwmSFQBvAAAAAA==.',
Be='Bearelf:BAAALgADCgIJAgAAAA==.Bearlinwall:BAAALgAECgYJDQAAAA==.Befoul:BAAALgAECgQJBAAAAA==.Bellyz:BAAALgAECgYJBwAAAA==.Bernham:BAAALgADCgMJAwAAAA==.',
Bi='Bigcheifpoop:BAAALgAECgEJAQAAAA==.Bigdumbo:BAAALgAECgEJAQABLgAFFAIJAwADAAAAAA==.Bigskydh:BAAALgAECgYJDwAAAA==.Bigskymage:BAAALgAECgQJCwAAAA==.Billybones:BAAALgAECgIJAgAAAA==.Bip:BAAALgADCgEJAQAAAA==.',
Bl='Blackrazor:BAAALgADCgIJAgAAAA==.Blacksburden:BAAALgAECgMJAwABLgAFFAEJAQADAAAAAA==.Blackvalor:BAAALgADCgMJAwAAAA==.Blackwÿn:BAAALgAECgEJAQABLgAECgcJGQARACYNAA==.Bladedozzer:BAAALgAECgUJBwAAAA==.Blindinglite:BAABLgAECn8dAAISAAcJSiIlDgCCAgASAAcJSiIlDgCCAgAAAA==.Blindtoast:BAAALgAECgIJAgAAAA==.Blkpriest:BAAALgAECgIJAwAAAA==.Bloodhaze:BAACLgAFFH8GAAISAAMJuRzlCAAIAQASAAMJuRzlCAAIAQAuAAQKfxsAAhIACQl8HxcLAK8CABIACQl8HxcLAK8CAAAA.Blorp:BAACLgAFFH8KAAITAAMJIBaEMADuAAATAAMJIBaEMADuAAAuAAQKfxsAAhMACAnfHMYlAHACABMACAnfHMYlAHACAAAA.',
Bo='Bodizzle:BAAALgADCgkJIAAAAA==.Bonez:BAAALgADCgMJAwAAAA==.Boondoggle:BAAALgAECgQJCAAAAA==.Borestus:BAAALgAECgYJCAAAAA==.Bouldur:BAAALgAECgUJDgAAAA==.Bownystark:BAABLgAECn8eAAICAAcJCCI9FQCIAgACAAcJCCI9FQCIAgAAAA==.Bozz:BAAALgAECgQJBQAAAA==.',
Br='Brieter:BAAALgAECgcJDAABLgAECgkJFgANACoSAA==.Brinar:BAAALgAECgQJCQAAAA==.Brokikobo:BAAALgADCggJCwAAAA==.Broughston:BAAALgAECgEJAQAAAA==.Brutusx:BAAALgAECgYJDgAAAA==.',
Bu='Bullhockey:BAAALgAECgEJAQAAAA==.Bullshiftsal:BAAALgAECgYJEgAAAA==.Burntcring:BAAALgAECgEJAgAAAA==.',
Bw='Bwabwagon:BAAALgADCgcJDgAAAA==.',
Bx='Bxxberry:BAAALgAECgMJAwAAAA==.',
Ca='Camipriest:BAAALgAECgEJAQAAAA==.Casstyelle:BAAALgAECgQJBAABLgAFFAEJAQADAAAAAA==.Catpizz:BAAALgADCgEJAQAAAA==.',
Ce='Celedael:BAAALgAECgUJCgABLgAECgkJFAAHAN0SAA==.',
Ch='Chairon:BAAALgAECgMJAwABLgAECgUJEAADAAAAAA==.Changed:BAAALgAECgIJAgAAAA==.Chauvinpack:BAAALgAECgcJBwAAAA==.Cheesus:BAAALgAECgYJCQABLgAECgkJFgANACoSAA==.Chicharon:BAAALgAECgQJCwAAAA==.Chickentacos:BAAALgADCgkJCAABLgAECgcJDwADAAAAAA==.Chipsnsalsa:BAAALgAECgEJAQABLgAECgcJDwADAAAAAA==.Chocoriffic:BAAALgAECgcJDwAAAA==.Chokoballs:BAAALgAECgEJAQABLgAECggJKgAUAAgWAA==.Chokoballz:BAAALgADCgkJCQABLgAECggJKgAUAAgWAA==.',
Cl='Clawmommy:BAAALgAECgMJAwAAAA==.',
Co='Cojobo:BAAALgADCgYJCQAAAA==.Coko:BAABLgAECn8mAAIVAAkJSB7CAQC6AgAVAAkJSB7CAQC6AgABLgAECggJGwAPAJUgAA==.Coldbrewz:BAAALgAECgYJDwAAAA==.Condensation:BAAALgADCgEJAQAAAA==.Corgibutts:BAAALgAECgEJAQAAAA==.',
Cr='Crackjones:BAAALgAECgUJAgAAAA==.Crazydave:BAABLgAECn8aAAIWAAkJ6xEnIwDMAQAWAAkJ6xEnIwDMAQAAAA==.Creemywitchu:BAAALgADCgEJAQABLgADCgcJBwADAAAAAA==.Crisgmt:BAAALgAECgcJCAAAAA==.Crism:BAAALgAECgQJAwAAAA==.Crismggt:BAAALgAFFAEJAQAAAA==.Crismtg:BAAALgAECgQJBwAAAA==.Crispytank:BAAALgADCgcJCgAAAA==.Cryptìc:BAAALgAFFAIJAgABLgAFFAUJEQAGABMbAA==.Cryptîc:BAACLgAFFH8RAAIGAAUJExtqGgB4AQAGAAUJExtqGgB4AQAuAAQKfyoAAgYACAmUJXoIAOoCAAYACAmUJXoIAOoCAAAA.',
Cu='Cursadilla:BAAALgAECgQJCgAAAA==.',
Cy='Cylissari:BAAALgAECgYJBgAAAA==.',
Da='Daasstion:BAABLgAECn8YAAIGAAcJjxlJXwAdAgAGAAcJjxlJXwAdAgAAAA==.Dabbia:BAABLgAECn8dAAQJAAgJphwIEwCzAQAIAAYJeBuGVwDBAQAJAAYJ5RoIEwCzAQAHAAEJWiLSEQBkAAAAAA==.Daedleus:BAAALgADCgQJBAAAAA==.Damented:BAAALgAFFAEJAQAAAA==.Darkaitsu:BAAALgAECgEJAQAAAA==.Dawnpaw:BAABLgAECn8iAAMXAAkJqhNTIgCgAQAXAAgJcxFTIgCgAQAYAAUJpBWkIwALAQAAAA==.Daymonesus:BAAALgADCgkJCAAAAA==.',
De='Deathballz:BAABLgAECn8qAAIUAAgJCBb4KgDQAQAUAAgJCBb4KgDQAQAAAA==.Deathsbreach:BAABLgAECn8VAAITAAYJ4Q97TgANAQATAAYJ4Q97TgANAQAAAA==.Deathsmite:BAAALgAECgIJAwAAAA==.Deathtee:BAABLgAECn8YAAIUAAgJqRxHRgAiAgAUAAgJqRxHRgAiAgAAAA==.Deepwaters:BAAALgADCgcJDgAAAA==.Dekuslice:BAABLgAECn8VAAIZAAYJ8BDPLgDZAAAZAAYJ8BDPLgDZAAAAAA==.Delafant:BAAALgAECgYJCwAAAA==.Demencia:BAAALgADCgQJBAAAAA==.Demonclawx:BAAALgADCgcJCAAAAA==.Dephlorate:BAAALgADCgcJCAAAAA==.Derpyderp:BAAALgAECgEJAQABLgAECgkJFAAGALkMAA==.Destroyah:BAAALgADCgUJBwABLgAECgcJEgADAAAAAA==.Devile:BAAALgADCgIJAgAAAA==.Devocate:BAAALgADCgcJCAAAAA==.',
Di='Dinkys:BAAALgADCgYJCwABLgAECgYJDwADAAAAAA==.Dinsum:BAAALgADCgcJDQAAAA==.Diogenist:BAAALgAECgIJAwAAAA==.Dirtypeasant:BAAALgADCgUJBQAAAA==.',
Dk='Dkballz:BAAALgAECgQJBAABLgAECggJGAAaAO0iAA==.',
Do='Dogdad:BAAALgADCgcJCwAAAA==.Doktardoodad:BAAALgAECgMJAwAAAA==.Doktartides:BAAALgAECgEJAQAAAA==.Doktarzen:BAAALgAECgQJBgAAAA==.Doktershokk:BAAALgADCgEJAgAAAA==.Donkel:BAAALgAECgEJAQAAAA==.Doomslayer:BAABLgAECn8aAAITAAkJfAnxYgB4AQATAAkJfAnxYgB4AQAAAA==.Doresearch:BAABLgAECn8iAAIFAAgJgBV5EwC8AQAFAAgJgBV5EwC8AQAAAA==.',
Dr='Drackani:BAAALgADCgYJBgAAAA==.Draenutt:BAABLgAECn8XAAIIAAgJSh8AGgAVAgAIAAgJSh8AGgAVAgAAAA==.Dragontee:BAAALgADCgQJBAABLgAECggJGAAUAKkcAA==.Drakarys:BAAALgAECgYJCwAAAA==.Drakex:BAAALgAECgUJBgAAAA==.Drengist:BAABLgAECn8qAAIbAAkJwBgaCABMAgAbAAkJwBgaCABMAgAAAA==.Drexybear:BAABLgAECn8XAAMPAAcJ9iHZEQBDAgAPAAcJ9iHZEQBDAgACAAUJBBf2QgBLAQAAAA==.Drezbi:BAAALgAECgUJCQAAAA==.Drpally:BAAALgADCgEJAQAAAA==.Drpebbles:BAAALgAECgQJCwAAAA==.Druidskillz:BAAALgADCgEJAQAAAA==.',
Du='Dulcineru:BAAALgADCgYJCgAAAA==.Dunbarth:BAABLgAECn8cAAIcAAkJUwzkbQChAQAcAAkJUwzkbQChAQAAAA==.Durzaman:BAAALgAECgYJDQAAAA==.Durzuk:BAAALgAECgMJAwAAAA==.Duskhoof:BAAALgADCgIJAwAAAA==.',
Dy='Dynastyy:BAAALgAECgkJBwAAAA==.',
['Dé']='Dévílyñ:BAAALgAECgYJDwAAAA==.',
['Dü']='Dük:BAABLgAECn8YAAMIAAcJexGsUQA1AQAIAAYJIRKsUQA1AQAJAAIJOw5LTACIAAAAAA==.',
Eg='Eggy:BAAALgAECgkJDgAAAA==.',
Ek='Eks:BAAALgADCgkJEQAAAA==.',
El='Eldraaqeyn:BAAALgAECgMJAwAAAA==.Elephant:BAAALgAECgQJCQAAAA==.Elkanàh:BAAALgAECgIJAwABLgAECggJKQAWAKEgAA==.Elleynle:BAAALgAECgQJDAAAAA==.Elunara:BAACLgAFFH8IAAIVAAIJMxVYCACPAAAVAAIJMxVYCACPAAAuAAQKfykAAhUACQkiH2kBANQCABUACQkiH2kBANQCAAEuAAQKCQkUAAcA3RIA.',
Em='Emhotep:BAAALgADCgMJAwAAAA==.',
En='Enazar:BAAALgADCgIJAgAAAA==.Enigmä:BAAALgADCgYJCgAAAA==.Enio:BAAALgAECgMJAwAAAA==.',
Er='Ericuh:BAABLgAECn8XAAIBAAYJsxJqNwArAQABAAYJsxJqNwArAQAAAA==.',
Es='Escanör:BAAALgAECgYJDAABLgAECgcJEQADAAAAAA==.Essekk:BAACLgAFFH8JAAIGAAMJHg17LgD9AAAGAAMJHg17LgD9AAAuAAQKfy8AAgYACQklH10WACMDAAYACQklH10WACMDAAAA.',
Eu='Euliana:BAAALgADCgUJBQAAAA==.',
Ev='Evokeeznutz:BAAALgAECgcJCQABLgAECgcJDAADAAAAAA==.',
Ex='Exesolo:BAAALgADCgYJBwAAAA==.Exploreswag:BAAALgAECgcJDwAAAA==.',
Ey='Eyeshmesch:BAAALgADCgUJBQABLgAECgMJAwADAAAAAA==.',
['Eí']='Eír:BAAALgADCgYJDQABLgAECggJLgAWAJwcAA==.',
Fa='Fairyholy:BAAALgADCgIJAgAAAA==.Fallenchaos:BAAALgAECgYJBgAAAA==.Famjam:BAAALgAECgYJDgAAAA==.Fao:BAAALgADCgMJAwAAAA==.Fastrialimas:BAAALgAECgEJBAAAAA==.Fatpo:BAABLgAECn8gAAMWAAgJzSC8BgDiAgAWAAgJzSC8BgDiAgAdAAQJVh+oJQAXAQAAAA==.Fayjhu:BAABLgAECn8eAAIGAAgJBAoKUwByAQAGAAgJBAoKUwByAQAAAA==.',
Fe='Ferbos:BAAALgAECgIJAwAAAA==.Feylock:BAABLgAECn8UAAIIAAcJ6xABUQA3AQAIAAcJ6xABUQA3AQAAAA==.',
Fi='Fiastrei:BAAALgADCgcJCQAAAA==.',
Fl='Flexo:BAAALgADCgQJBAAAAA==.',
Fo='Forheretogo:BAAALgADCgEJAQAAAA==.Foô:BAACLgAFFH8FAAIaAAIJGBSOGQCpAAAaAAIJGBSOGQCpAAAuAAQKfysAAhoACAnjH8wGAEICABoACAnjH8wGAEICAAAA.',
Fr='Frigate:BAABLgAECn8YAAIGAAcJWAX9mwDaAAAGAAcJWAX9mwDaAAAAAA==.Frihgate:BAABLgAECn8YAAIPAAcJWBd1MgDmAQAPAAcJWBd1MgDmAQAAAA==.Frostbitten:BAAALgADCgYJBgAAAA==.Frostea:BAAALgADCgUJBgAAAA==.Frostmyface:BAAALgAFFAIJAwAAAA==.Frozenbeard:BAAALgAECgcJEwAAAA==.',
Fu='Fugarra:BAAALgAECgEJAQABLgAECgkJDAADAAAAAA==.Fugbug:BAAALgADCgYJBwAAAA==.Furcrazy:BAACLgAFFH8FAAIbAAMJjhvVFgAUAQAbAAMJjhvVFgAUAQAuAAQKfxYAAhsACAl9IUsHAF0CABsACAl9IUsHAF0CAAAA.Furdreich:BAAALgADCgIJAgAAAA==.Furryoffury:BAAALgADCgYJBgAAAA==.Furynagger:BAAALgADCgEJAQAAAA==.Furyosia:BAAALgADCgEJAQAAAA==.Furyrosa:BAAALgAECgEJAQAAAA==.Fuzi:BAAALgADCgUJBQABLgAECgMJAwADAAAAAA==.',
Fy='Fyafya:BAAALgADCgEJAQAAAA==.Fyah:BAABLgAECn8UAAIcAAkJQxnUOQCZAQAcAAkJQxnUOQCZAQABLgAFFAUJEAAPAOIaAA==.Fyaza:BAAALgAECgMJAwAAAA==.',
Ga='Gargamels:BAAALgAECgEJAQABLgAECgkJDAADAAAAAA==.Gariantel:BAAALgAECgIJAgAAAA==.Garou:BAAALgAECgYJDwAAAA==.Gaygar:BAAALgADCgYJBgAAAA==.',
Ge='Geekylock:BAAALgAECgQJCAAAAA==.Geekymage:BAAALgADCgEJAQAAAA==.Genesis:BAAALgAECgkJAgAAAA==.Geobloom:BAAALgADCgUJBgAAAA==.Gerbic:BAAALgAECgEJAQAAAA==.Germ:BAAALgAECgQJCwAAAA==.Gerttie:BAAALgAECgQJBAAAAA==.',
Gh='Ghosted:BAAALgAECgMJBQAAAA==.',
Gi='Gilgalador:BAAALgADCgMJAwAAAA==.Gingdrac:BAAALgADCgcJDgABLgAFFAcJIQALALAgAA==.Givepenance:BAAALgADCgcJFAAAAA==.',
Go='Gomdagarm:BAAALgADCgUJBQAAAA==.Gopwal:BAAALgAECgcJDQAAAA==.Gorehammer:BAABLgAECn8qAAIUAAgJmhlaMwCsAQAUAAgJmhlaMwCsAQAAAA==.Gorto:BAAALgAECgEJAQAAAA==.',
Gr='Grassmoker:BAAALgADCgYJBgAAAA==.Gravediger:BAAALgAECgYJCgAAAA==.Gravepaws:BAAALgADCgIJAgAAAA==.Greatfatherx:BAAALgADCgEJAQAAAA==.Grek:BAAALgAECgQJBgABLgAFFAEJAQADAAAAAA==.Gridxx:BAAALgAECgcJCAAAAA==.Grievex:BAABLgAECn8vAAIcAAkJoQgUPACSAQAcAAkJoQgUPACSAQAAAA==.Grimbeorn:BAAALgADCgEJAQAAAA==.',
['Gî']='Gîgâbussy:BAAALgADCgIJAgAAAA==.',
Ha='Hairybear:BAAALgADCgYJBgAAAA==.Hanazawa:BAAALgADCgMJBAAAAA==.Hanyu:BAAALgADCgMJAwAAAA==.Harkelem:BAAALgAECgkJAQAAAA==.Haydayy:BAAALgADCgYJBgAAAA==.Hazykeety:BAAALgADCgEJAQAAAA==.',
He='Healsonwheel:BAAALgAECgcJCgAAAA==.Healthiss:BAAALgAECgcJDAAAAA==.Helaziri:BAAALgAECgYJEQAAAA==.Hemolock:BAABLgAECn8ZAAMIAAYJgBZ4QQBlAQAIAAYJgBZ4QQBlAQAJAAEJAACoNwAAAAABLgAFFAQJEQAcAAsUAA==.Hemostasis:BAACLgAFFH8RAAIcAAQJCxSVGABIAQAcAAQJCxSVGABIAQAuAAQKfyAABBwACAkhIpMwAGACABwACAkhIpMwAGACABEAAQn4DW8yAC4AAB4AAQnCAAKiACUAAAAA.Herjä:BAABLgAECn8uAAMWAAgJnByEBwB7AgAWAAgJnByEBwB7AgALAAYJrRNdJQBpAQAAAA==.Hexmora:BAAALgAECgEJAQAAAA==.',
Hi='Hinkles:BAAALgAECgYJDwAAAA==.',
Ho='Hoocha:BAAALgADCgYJBgABLgAECgcJDAADAAAAAA==.Hoollymollyy:BAAALgAECgEJAQAAAA==.Hornsly:BAAALgADCgMJAwAAAA==.Hotandcold:BAAALgAECgEJAQAAAA==.',
Hu='Hunterskillz:BAAALgADCgYJBgAAAA==.Huntingpoo:BAAALgAECgYJEgAAAA==.Huntweak:BAAALgAECgIJAgAAAA==.Huun:BAABLgAECn8mAAIfAAgJwxjUCQAGAgAfAAgJwxjUCQAGAgAAAA==.',
Hy='Hyasynthia:BAAALgAECgYJBQAAAA==.',
Ia='Iamnsfw:BAAALgAECgcJEgAAAA==.',
Ic='Icelcelance:BAAALgAFFAEJAQAAAA==.',
Il='Illuminee:BAAALgAECgIJAgABLgAECgIJAgADAAAAAA==.Illydan:BAAALgAECgcJEwAAAA==.Ilvisarxiln:BAAALgADCgUJBQAAAA==.',
Im='Imataquito:BAABLgAECn8tAAIGAAkJRh8RDADAAgAGAAkJRh8RDADAAgAAAA==.',
In='Indigø:BAAALgAECgQJCQAAAA==.Inepsy:BAAALgAECgEJAQAAAA==.Infelicity:BAAALgADCgYJCQAAAA==.Infortunii:BAAALgADCgYJBgABLgAFFAEJAQADAAAAAA==.',
Ir='Irezufortips:BAAALgADCgcJBwABLgAECgkJDAADAAAAAA==.Ironhide:BAAALgAECgIJAgAAAA==.Ironshadow:BAAALgADCgEJAQAAAA==.Irrenadro:BAABLgAECn8VAAIcAAgJJQ6/fQB+AQAcAAgJJQ6/fQB+AQAAAA==.Irvainee:BAAALgAECgYJDAAAAA==.',
It='Itsp:BAAALgAECgUJBQAAAA==.',
Ja='Jadechaos:BAAALgAECgEJAQAAAA==.Jadireux:BAAALgAECgMJAwAAAA==.Jahkazul:BAAALgADCgYJDAAAAA==.Jarnabas:BAAALgAECgIJAgAAAA==.Jayec:BAAALgAECgEJAQAAAA==.',
Ji='Jimboslice:BAAALgADCgcJBwAAAA==.Jingleparts:BAAALgADCggJCQABLgAECgcJDwADAAAAAA==.',
Jo='Joes:BAABLgAECn8cAAMPAAYJChgPNAB9AQAPAAYJChgPNAB9AQACAAYJ3AWUFgCfAAAAAA==.Jonesy:BAAALgAECgUJCwAAAA==.Jorath:BAAALgAECgUJBQABLgAECgkJDAADAAAAAA==.',
Ju='Juicygossip:BAAALgAECgEJAQAAAA==.Jujupowa:BAAALgAECgcJDwAAAA==.Junebug:BAAALgAECgQJBQAAAA==.Justicus:BAAALgADCgMJAwAAAA==.',
['Jë']='Jëssë:BAAALgADCgEJAQAAAA==.',
['Jö']='Jöe:BAAALgAECgEJAQAAAA==.',
Ka='Kagal:BAABLgAECn8WAAIfAAgJ3hFtDwDNAQAfAAgJ3hFtDwDNAQAAAA==.Kaidan:BAABLgAECn8cAAIPAAkJIhCwMwDgAQAPAAkJIhCwMwDgAQAAAA==.Kaipriest:BAAALgAECgQJBAAAAA==.Kaladinn:BAAALgADCgEJAQAAAA==.Kaledra:BAAALgADCgYJBgAAAA==.Kalyke:BAAALgADCggJDQAAAA==.Kamikazejoe:BAAALgADCgEJAQAAAA==.Kargian:BAAALgAECgQJBQAAAA==.Kasumirenn:BAAALgAECgMJAwABLgAFFAMJBQASAOAXAA==.Katanya:BAAALgAECgYJBgABLgAECgkJFAAHAN0SAA==.Katarinabluu:BAAALgADCgYJBgAAAA==.',
Ke='Keetra:BAABLgAFFH8MAAIPAAQJTREWFQBJAQAPAAQJTREWFQBJAQAAAA==.Keftheals:BAAALgAECgEJAQAAAA==.Keiriline:BAABLgAECn8cAAMgAAcJIxVNBQB+AQAgAAcJIxVNBQB+AQAUAAEJYwBrBQEaAAAAAA==.Keledorimash:BAAALgADCgYJCAAAAA==.Keva:BAABLgAECn8YAAIfAAYJIB3wEgCFAQAfAAYJIB3wEgCFAQAAAA==.Keyboard:BAAALgADCgIJAQAAAA==.Kez:BAAALgAECgYJCgAAAA==.',
Kh='Khaalian:BAAALgAECgIJAwAAAA==.Khalysea:BAAALgADCgIJAgABLgAECgkJFAAHAN0SAA==.',
Ki='Killbreed:BAABLgAECn8gAAIhAAgJ7SALAgCgAgAhAAgJ7SALAgCgAgAAAA==.Kinkster:BAAALgAECgMJAwAAAA==.Kirinani:BAAALgAECgEJAQAAAA==.Kirzan:BAAALgADCgMJAwAAAA==.Kizaruu:BAAALgADCgEJAQAAAA==.',
Kn='Knifeprty:BAAALgADCgUJBgAAAA==.Knight:BAAALgAECgMJBAABLgAECggJIgAYAKQfAA==.Knuggz:BAABLgAECn8XAAIKAAYJdReyJABMAQAKAAYJdReyJABMAQAAAA==.',
Ko='Kolduna:BAAALgADCgUJBQAAAA==.Koshmare:BAAALgADCgUJBQAAAA==.Kozanazure:BAAALgADCgkJEQAAAA==.',
Kr='Krestaul:BAAALgAECgcJCQAAAA==.',
Ku='Kurthalan:BAAALgAECgQJDAAAAA==.Kuumaneko:BAABLgAECn8lAAMIAAgJahypGgAQAgAIAAgJahypGgAQAgAJAAYJrwcLMQD1AAAAAA==.',
Ky='Kyarita:BAAALgAECgIJAgAAAA==.Kyballion:BAAALgAECgYJEgAAAA==.Kyledh:BAACLgAFFH8LAAITAAQJfRgyGQAGAQATAAQJfRgyGQAGAQAuAAQKfy4AAxMACQmSJEEPAAUDABMACQmSJEEPAAUDACIAAQluIf4jAGIAAAAA.Kyletotems:BAAALgADCggJCAAAAA==.Kyllgorre:BAAALgAECgEJAQAAAA==.Kynyine:BAAALgADCgcJCAAAAA==.',
La='Landridan:BAAALgADCgkJFQAAAA==.Lanstoll:BAAALgADCgQJBAAAAA==.Lanthin:BAAALgADCgYJCgAAAA==.Larzoh:BAABLgAECn8bAAMSAAkJ6iOjAwBGAwASAAkJ6iOjAwBGAwATAAMJSw4YkwBpAAAAAA==.Laylaria:BAAALgADCgEJAQAAAA==.',
Le='Lee:BAAALgADCgYJBQABLgAECggJLAAUAHIgAA==.Legadiaus:BAAALgAECgEJAQAAAA==.Lemonheads:BAABLgAECn8oAAMLAAcJoxSiFACbAQALAAcJoxSiFACbAQAdAAEJ4QEpagAjAAAAAA==.Lethargy:BAAALgAECgQJBAAAAA==.',
Li='Liaenara:BAAALgADCgQJCQAAAA==.Lidorila:BAAALgADCgYJDAAAAA==.Lightpallyzz:BAAALgADCgEJAQAAAA==.Lilin:BAAALgADCgcJCgABLgAECgYJDwADAAAAAA==.Lilwiz:BAAALgADCgkJHgAAAA==.Lindre:BAAALgADCgQJBAAAAA==.Linnxvx:BAAALgAECgIJAgAAAA==.Lishp:BAAALgADCgMJAwAAAA==.Littleiceice:BAAALgADCgEJAQAAAA==.',
Ll='Llemonz:BAAALgAECgMJBAAAAA==.',
Lo='Lockaf:BAAALgADCgUJBQABLgAECgUJBgADAAAAAA==.Lohki:BAAALgADCgEJAQAAAA==.Lonelyroad:BAAALgADCgMJAwAAAA==.Lostsausage:BAAALgAECgQJBgABLgAECgYJEwADAAAAAA==.Lothaire:BAAALgADCgEJAQAAAA==.Lothiet:BAAALgAECgYJCwABLgAECgcJEgADAAAAAA==.',
Ls='Lshaman:BAAALgAECgYJBgABLgAFFAIJAwADAAAAAA==.',
Lu='Luayhanui:BAAALgADCgEJAQAAAA==.Lugeya:BAAALgADCgYJBgAAAA==.Lunarcricket:BAAALgAECgMJAwABLgAECggJJAARAPIiAA==.Lustpls:BAAALgAECgQJBAABLgAECgYJBwADAAAAAA==.',
Ly='Lyncha:BAAALgADCgcJDgABLgAECggJJAARAPIiAA==.Lynchà:BAABLgAECn8kAAIRAAgJ8iJ+AgCRAgARAAgJ8iJ+AgCRAgAAAA==.Lynchä:BAAALgADCgEJAQABLgAECggJJAARAPIiAA==.',
Ma='Maakun:BAABLgAECn8dAAQWAAcJ3gxkOwBNAQAWAAcJ2gdkOwBNAQAdAAUJ8wcSQAD2AAALAAQJHg2nOgDTAAAAAA==.Maddiebaby:BAAALgAECgQJCAABLgAECgUJBQADAAAAAA==.Mageapoug:BAAALgADCgcJBwABLgAECggJFAATAFcdAA==.Magmalance:BAAALgAECgIJAgABLgAECgYJFQATAOEPAA==.Mahzad:BAABLgAECn8fAAIBAAYJPCM7GABUAgABAAYJPCM7GABUAgAAAA==.Maladi:BAAALgADCgkJGwAAAA==.Malfrun:BAABLgAECn8cAAIjAAgJdhajCgDDAQAjAAgJdhajCgDDAQAAAA==.Marinnite:BAAALgADCgYJDQAAAA==.Markzugrberg:BAAALgADCgkJCQAAAA==.Marox:BAACLgAFFH8HAAIGAAQJwQpmNQA7AQAGAAQJwQpmNQA7AQAuAAQKfxcAAgYACQmjHG5DAG4CAAYACQmjHG5DAG4CAAAA.Marshmellows:BAAALgAECgYJBgAAAA==.Mastolus:BAAALgADCgEJAQAAAA==.Mathesi:BAAALgADCgYJCQAAAA==.Mathrim:BAACLgAFFH8MAAIIAAQJYBwWEgBxAQAIAAQJYBwWEgBxAQAuAAQKfyAAAwgACAk3I00VANUCAAgABwk3I00VANUCAAkAAQkAANRVAG0AAAAA.Matooka:BAABLgAECn8ZAAIPAAcJNA3eOQBmAQAPAAcJNA3eOQBmAQAAAA==.Maynji:BAAALgAECgMJAwAAAA==.Mayushi:BAAALgAECgYJCQAAAA==.',
Me='Meencurry:BAABLgAECn8iAAIGAAcJDRSSTQCBAQAGAAcJDRSSTQCBAQAAAA==.Megozugzug:BAAALgAECgIJAgABLgAFFAEJAQADAAAAAA==.Meyneth:BAAALgAECgEJAQAAAA==.',
Mi='Mikaì:BAAALgAECgkJEgAAAA==.Mikehawkener:BAAALgAECgUJBwAAAA==.Misleading:BAAALgAECgUJCQAAAA==.Misotofu:BAAALgADCgcJCgAAAA==.Mistfisting:BAABLgAFFH8FAAIXAAMJURRuFgDQAAAXAAMJURRuFgDQAAAAAA==.',
Mo='Moderato:BAAALgAECgcJDAAAAA==.Moelleri:BAABLgAECn8bAAIUAAgJXRi1JgDlAQAUAAgJXRi1JgDlAQAAAA==.Mojowarlock:BAAALgADCgYJBgABLgAECgUJBQADAAAAAA==.Moneymage:BAAALgAECgcJCwAAAA==.Monkgroom:BAACLgAFFH8LAAIXAAQJBQrJEwD2AAAXAAQJBQrJEwD2AAAuAAQKfx0AAxcACQmcFAoXAAkCABcACQmcFAoXAAkCABgABgnxCtE5ADYBAAAA.Monsignor:BAAALgAECgEJBAAAAA==.Montra:BAABLgAECn8uAAMVAAkJNRwgBQCOAgAVAAkJNRwgBQCOAgAhAAUJAgn8HgDrAAAAAA==.Moreilira:BAAALgAECgQJBwAAAA==.Mornshield:BAABLgAECn8bAAMcAAYJWxSlkQBZAQAcAAYJIxClkQBZAQARAAUJUxMDJgDZAAABLgAECgkJDAADAAAAAA==.Morphien:BAAALgADCgcJCQAAAA==.Mortaveus:BAAALgAECgEJAQAAAA==.Motorinkashi:BAAALgAECggJDwAAAA==.Motto:BAAALgAECgEJAQAAAA==.Mouse:BAAALgADCgMJAwAAAA==.',
Mu='Muddgore:BAABLgAECn8ZAAIjAAgJnBQ5DQCQAQAjAAgJnBQ5DQCQAQAAAA==.Muddthir:BAAALgAECgQJBAABLgAECggJGQAjAJwUAA==.Murkyblaizin:BAAALgAECgYJDQAAAA==.Mustardheals:BAAALgAECgUJCwAAAA==.',
My='Myharanir:BAAALgADCgUJBQAAAA==.Mythaera:BAAALgAECgQJCAABLgAECggJFwAcANocAA==.',
Na='Nazrra:BAABLgAECn8bAAIjAAkJIxRhEAACAgAjAAkJIxRhEAACAgAAAA==.Nazugrax:BAAALgAECgQJBAAAAA==.',
Ne='Neebsz:BAAALgAECgEJAQAAAA==.Nemene:BAAALgADCgUJBQAAAA==.Nenad:BAAALgADCgEJAQAAAA==.Neolithic:BAAALgAECgcJBAAAAA==.Nerdeficent:BAAALgADCgQJBAAAAA==.Nerodic:BAAALgADCgYJBgABLgAFFAQJCwAUAK0TAA==.Nestaah:BAAALgAFFAIJBAAAAA==.Nettra:BAAALgAECgIJCAAAAA==.Newtnewt:BAAALgAECgEJAQAAAA==.',
Ni='Nickparker:BAAALgADCggJCAAAAA==.Nicneven:BAAALgADCgkJCQAAAA==.Nininbrew:BAAALgADCgMJAwAAAA==.Nirath:BAABLgAECn8nAAIGAAgJow4xRACaAQAGAAgJow4xRACaAQAAAA==.',
No='Nobainer:BAAALgADCgYJCgAAAA==.Noed:BAAALgAECgMJAwAAAA==.Nohkana:BAAALgAECgEJAQAAAA==.Nohkano:BAABLgAECn8mAAIbAAkJYyMFAQA5AwAbAAkJYyMFAQA5AwAAAA==.Nokinkshame:BAAALgADCggJCQABLgAECgcJDwADAAAAAA==.Noobymonk:BAAALgAECggJEQAAAA==.Noralise:BAAALgAECgYJEwAAAA==.Northerndk:BAABLgAECn8VAAIUAAcJKgWJeQDuAAAUAAcJKgWJeQDuAAAAAA==.Notsxldier:BAAALgADCgQJBAAAAA==.Novàstar:BAAALgADCgQJCAAAAA==.',
Nu='Numbuh:BAAALgAECgEJAgAAAA==.Nutthunter:BAAALgAECgEJAQAAAA==.',
Ny='Nyxariaw:BAAALgADCggJDAAAAA==.Nyxmaris:BAAALgADCgYJBAAAAA==.',
['Nø']='Nøvâ:BAABLgAECn8fAAIGAAgJVhS+bAD8AQAGAAgJVhS+bAD8AQAAAA==.',
Oc='Octavarium:BAABLgAECn8aAAIXAAYJdB4wDwD5AQAXAAYJdB4wDwD5AQAAAA==.',
Od='Odinsmage:BAAALgADCgUJBgAAAA==.Odinspriest:BAAALgADCgIJAgAAAA==.Odinsvulpera:BAAALgADCgYJBgAAAA==.',
Oe='Oennomaus:BAAALgAECgUJBQAAAA==.',
Of='Offspec:BAAALgAECgEJAgAAAA==.',
Oh='Ohyshii:BAAALgAECgMJAwAAAA==.',
On='Oneshothel:BAAALgAECgYJCgAAAA==.Onran:BAAALgADCgUJBQABLgAECggJFwAcANocAA==.',
Or='Orcpeon:BAAALgAECgUJCAABLgAECggJLQAcACgdAA==.Oryndern:BAAALgAECgMJBwAAAA==.',
Ot='Otokunu:BAAALgADCgIJAgAAAA==.',
Ov='Ovenmitts:BAAALgAECgYJEgABLgAECgcJDwADAAAAAA==.',
Oz='Ozwalds:BAAALgADCgQJBAAAAA==.',
Pa='Paeonagos:BAAALgADCgMJAwAAAA==.Palimpsest:BAAALgADCgEJAQAAAA==.Pallymans:BAAALgADCgUJBQAAAA==.Pancaked:BAAALgAECgcJCgABLgAECgcJDwADAAAAAA==.Pantheons:BAAALgADCgEJAQAAAA==.Parsi:BAAALgAFFAEJAQAAAA==.Pawtism:BAAALgADCgcJBgAAAA==.',
Pe='Penut:BAAALgAECgEJAQAAAA==.Perritax:BAABLgAECn8bAAIGAAcJ+g+qUQB2AQAGAAcJ+g+qUQB2AQAAAA==.',
Ph='Phialkit:BAAALgADCgcJBwAAAA==.Phoebelyria:BAAALgAECgUJDgAAAA==.Phêo:BAAALgAECgMJAwABLgAECgYJCgADAAAAAA==.',
Pi='Pickelz:BAAALgADCgMJAwAAAA==.Piffiny:BAAALgAECgYJBwAAAA==.Pine:BAAALgAECgMJAwAAAA==.Pingdoo:BAAALgAECgIJAgAAAA==.',
Po='Pofat:BAAALgAFFAIJAwAAAA==.Polis:BAABLgAECn8tAAIcAAgJKB2XFwA+AgAcAAgJKB2XFwA+AgAAAA==.Pomol:BAAALgAECgcJDQAAAA==.Pomoly:BAAALgAECgEJAQAAAA==.Poppafury:BAAALgAECgYJDQAAAA==.Potent:BAABLgAECn8gAAMUAAgJ4REGOQCVAQAUAAgJ4REGOQCVAQAkAAQJbQaMOgBvAAAAAA==.Pougadina:BAAALgAECgIJAgABLgAECggJIAAWAM0gAA==.',
Pr='Prislo:BAAALgADCgMJAwAAAA==.Prodie:BAAALgADCgMJBAAAAA==.Protect:BAAALgADCgMJAwAAAA==.Présage:BAACLgAFFH8FAAIUAAMJMAd9VgDeAAAUAAMJMAd9VgDeAAAuAAQKfxYAAxQACAkSFkQpANcBABQACAkSFkQpANcBACQAAQlLBHpPABcAAAAA.',
Ps='Pswar:BAAALgAECgEJAQAAAA==.',
Pu='Puriel:BAAALgADCgMJAwAAAA==.',
Pw='Pwnstar:BAAALgAECgMJAwAAAA==.',
Py='Pyrojoe:BAAALgAECgcJEQABLgAECgkJDAADAAAAAA==.',
['Pò']='Pò:BAAALgAECgIJBAAAAA==.',
Qi='Qizzle:BAAALgADCgMJAwAAAA==.',
Ra='Ramsha:BAABLgAECn8VAAIcAAYJWxbzYgAoAQAcAAYJWxbzYgAoAQAAAA==.Ramshunter:BAABLgAECn8fAAMPAAkJFCFeBwAaAwAPAAkJFCFeBwAaAwACAAIJ2xGKIgBIAAAAAA==.Randyvivaldi:BAAALgADCgEJAQAAAA==.Rashanda:BAAALgADCgMJAwAAAA==.Rathasas:BAAALgAECgMJAwAAAA==.Ratnob:BAABLgAECn8kAAIUAAkJJBWAJgDlAQAUAAkJJBWAJgDlAQAAAA==.Ravnaar:BAAALgAECgkJDwAAAA==.Razamatazz:BAAALgADCgEJAQAAAA==.',
Re='Reddemon:BAAALgAECgEJAQABLgAFFAEJAQADAAAAAA==.Redstraw:BAAALgADCgYJBwAAAA==.Relda:BAAALgAECgYJCQABLgAFFAEJAQADAAAAAA==.Renae:BAAALgAECgkJCAAAAA==.Renaud:BAAALgAECgQJBAAAAA==.Rennshi:BAACLgAFFH8FAAISAAMJ4Bc4CAAWAQASAAMJ4Bc4CAAWAQAuAAQKfx8AAhIACAmaJAcEADsDABIACAmaJAcEADsDAAAA.Retpally:BAABLgAFFH8OAAIjAAUJLBGQBABsAQAjAAUJLBGQBABsAQAAAA==.Reyikrat:BAAALgAECgQJCAAAAA==.Rezmee:BAACLgAFFH8FAAIUAAMJJSUIMABAAQAUAAMJJSUIMABAAQAuAAQKfxgAAhQACQmFI/cDACcDABQACQmFI/cDACcDAAAA.',
Rh='Rheaf:BAAALgAECgYJCQAAAA==.',
Ri='Riastrad:BAAALgADCgUJBwAAAA==.Richie:BAABLgAECn8VAAIGAAcJPxHBdgAjAQAGAAcJPxHBdgAjAQAAAA==.Ringsofsatrn:BAAALgADCgEJAQAAAA==.Ripgoose:BAAALgADCggJEwAAAA==.',
Ro='Rolanthas:BAAALgADCgcJCQAAAA==.Rolexiós:BAAALgADCgcJBwAAAA==.Rosario:BAACLgAFFH8JAAMfAAQJIRkEBgBkAQAfAAQJIRkEBgBkAQACAAIJMg0/HwCZAAAuAAQKfyYAAwIACAmfIaANANgCAAIACAmfIaANANgCAB8ABQmeFnITAH4BAAAA.',
Ry='Ryotwar:BAAALgAECgEJAQAAAA==.Rythmatic:BAABLgAECn8YAAIaAAgJ7SJCBwA3AgAaAAgJ7SJCBwA3AgAAAA==.Ryvenox:BAAALgADCgcJBwAAAA==.',
['Ré']='Rénae:BAAALgAECgkJAgABLgAECgkJCAADAAAAAA==.',
Sa='Sabil:BAAALgADCgYJBgAAAA==.Saccharine:BAABLgAECn8hAAMLAAkJBBenBgCHAgALAAkJBBenBgCHAgAdAAEJdAATbQAHAAAAAA==.Sakieri:BAABLgAECn8vAAIdAAkJHx7hAgDbAgAdAAkJHx7hAgDbAgAAAA==.Salinomycin:BAAALgAECgUJBwAAAA==.Samedi:BAAALgAECgQJBAAAAA==.Sandordel:BAAALgADCgYJCgAAAA==.Sangan:BAAALgAECgYJEgAAAA==.Sanguini:BAABLgAECn8hAAIGAAgJXhaNMADeAQAGAAgJXhaNMADeAQAAAA==.Sathari:BAAALgAECgQJBgAAAA==.',
Sc='Scrappycoco:BAAALgADCgQJBAAAAA==.Scye:BAAALgAECgIJAgAAAA==.',
Se='Seamanhunter:BAAALgADCgEJAQAAAA==.Seanoevil:BAAALgAFFAEJAQAAAA==.Selaris:BAAALgAECgYJDAAAAA==.Selathviala:BAAALgADCgMJBQAAAA==.Sephares:BAAALgADCgUJBQAAAA==.Serazal:BAACLgAFFH8UAAMNAAcJuR12BQDgAQANAAYJMht2BQDgAQAOAAQJmhvHAQCDAQAuAAQKfyoAAw4ACQmzIsABAC8DAA4ACAlJI8ABAC8DAA0ACAk3I2oDAN4CAAAA.',
Sh='Shadowblitzx:BAAALgAECgUJEAAAAA==.Shadowfall:BAAALgADCgkJEQAAAA==.Shaggin:BAAALgADCgMJAwAAAA==.Shamfoo:BAAALgADCggJCAABLgAFFAIJBQAaABgUAA==.Shangan:BAAALgADCgEJAgAAAA==.Sharana:BAAALgADCggJCAAAAA==.Shhrekk:BAAALgAECgIJAgAAAA==.Shikendagoon:BAAALgADCgcJCwAAAA==.Shinøbu:BAAALgADCgYJDAAAAA==.Shirrazaha:BAAALgADCgMJAwAAAA==.Shortbejo:BAAALgADCgQJBgAAAA==.Shâzzam:BAAALgAECgYJBgABLgAECgcJFAAGAEgdAA==.',
Si='Silaris:BAAALgADCgMJBgAAAA==.Sinath:BAAALgAECgYJCgAAAA==.Singren:BAAALgADCgEJAQAAAA==.Sinnur:BAAALgAECgQJCQAAAA==.Sinsear:BAAALgADCgYJBgAAAA==.',
Sk='Skeezer:BAAALgAECgcJDAAAAA==.',
Sl='Sleeveless:BAAALgAECgcJDQAAAA==.Slizzie:BAAALgAECgYJDAAAAA==.Slizzle:BAAALgAECgEJAQAAAA==.Slowteeth:BAAALgADCgMJAwAAAA==.',
Sm='Smackdiver:BAAALgADCgYJAwAAAA==.Smarfus:BAAALgAECgYJCQABLgAFFAEJAQADAAAAAA==.Smilingdemon:BAAALgADCgIJAgAAAA==.Smilingp:BAAALgADCgkJDwAAAA==.Smiteznhealz:BAAALgADCgEJAQAAAA==.Smursh:BAAALgAECgQJBAAAAA==.',
Sn='Snakesabbath:BAAALgAECgUJDAAAAA==.Snarge:BAACLgAFFH8LAAIEAAUJIRW5AgBUAQAEAAUJIRW5AgBUAQAuAAQKfxQAAwQACQnnGB8KADACAAQACQnnGB8KADACAAUAAQkjEsCDADsAAAAA.Sneaktee:BAAALgAECgMJBAABLgAECggJGAAUAKkcAA==.',
So='Soone:BAAALgADCgUJBQAAAA==.',
Sp='Sparkmantle:BAAALgAECgYJBgAAAA==.Sparkydrac:BAAALgADCggJCQABLgAECgYJFQATAOEPAA==.Spectroce:BAAALgADCgMJAwAAAA==.Spunky:BAAALgAECgQJBgAAAA==.',
Sq='Squeaksune:BAAALgADCgcJCAAAAA==.Squiish:BAAALgAECgUJCQAAAA==.',
Sr='Srorcalot:BAAALgAECgQJCAABLgAECgkJDAADAAAAAA==.',
St='Steppedon:BAAALgAECgYJDgAAAA==.Stingerai:BAABLgAECn8bAAIPAAgJlSA8EABTAgAPAAgJlSA8EABTAgAAAA==.Stingeret:BAAALgADCgMJAwABLgAECggJGwAPAJUgAA==.Stingerge:BAAALgAECgMJBAABLgAECggJGwAPAJUgAA==.Stormweaverr:BAAALgAFFAEJAQAAAA==.',
Su='Sunbeamer:BAAALgAECgQJBAAAAA==.Sureman:BAAALgAECgMJBAAAAA==.',
Sw='Sweezy:BAAALgADCgcJBwAAAA==.',
Sx='Sxldíer:BAAALgAECgQJBwAAAA==.',
Sy='Sylvesters:BAAALgADCgcJBwABLgAECgUJBgADAAAAAA==.Syzmic:BAAALgADCgQJBgAAAA==.',
Ta='Taellas:BAAALgADCgMJAwAAAA==.Taeyeuh:BAAALgADCgcJCwAAAA==.Taley:BAAALgADCgMJAwAAAA==.Tamb:BAABLgAECn8bAAIMAAYJUxS+OgAqAQAMAAYJUxS+OgAqAQAAAA==.Tankboy:BAAALgAECgcJCwAAAA==.Tankndspank:BAAALgADCgYJBgAAAA==.Tarickjk:BAAALgAECgQJCAAAAA==.Taryn:BAAALgAECgUJBQABLgAECgYJBwADAAAAAA==.',
Te='Tedious:BAAALgAECgYJBgAAAA==.Teehuntee:BAAALgAECgMJAwABLgAECggJGAAUAKkcAA==.Teepal:BAAALgAECgMJBAABLgAECggJGAAUAKkcAA==.Tekraa:BAAALgAECgcJDQAAAA==.Tempist:BAABLgAECn8UAAIEAAYJ2R3DBwCyAQAEAAYJ2R3DBwCyAQAAAA==.Teribullduce:BAACLgAFFH8GAAIfAAIJLxgfEwC6AAAfAAIJLxgfEwC6AAAuAAQKf0EAAh8ACQksHtYDAJICAB8ACQksHtYDAJICAAAA.Terscheckii:BAAALgAFFAEJAQAAAA==.',
Th='Theslimer:BAAALgAECgcJEQAAAA==.Thesukuna:BAAALgAECgUJBwAAAA==.Thormor:BAACLgAFFH8hAAILAAcJsCD8AACxAgALAAcJsCD8AACxAgAuAAQKfy4ABAsACQk8JPsAAJoDAAsACQk8JPsAAJoDABYABwnoHiIWACwCAB0ABQmVHpo0AEUBAAAA.Thrä:BAAALgADCgEJAQAAAA==.Thuggerjr:BAABLgAECn8lAAIcAAgJ1Bg3IwD4AQAcAAgJ1Bg3IwD4AQAAAA==.Thunderlordx:BAAALgAECgEJAgAAAA==.Thænes:BAABLgAECn8ZAAMRAAcJJg0SFQD5AAARAAcJJg0SFQD5AAAcAAMJHgr9/QCYAAAAAA==.Thémis:BAAALgADCgIJAQAAAA==.',
Ti='Tiimmyy:BAAALgAECgEJAQAAAA==.Tikaanivorn:BAAALgADCgcJBAAAAA==.Tikitiki:BAAALgAECgYJDgAAAA==.Tildin:BAAALgAECgYJDgAAAA==.Tinyandcute:BAAALgADCgkJCQABLgAECgcJDwADAAAAAA==.Tiravana:BAAALgAECgIJAgAAAA==.',
To='Toohottohndl:BAAALgADCgMJAwAAAA==.Topson:BAAALgAFFAMJAwAAAA==.Tornok:BAAALgADCgEJAQAAAA==.Tots:BAAALgAECgEJAQAAAA==.Tottemdrop:BAAALgADCgYJBwABLgAFFAEJAQADAAAAAA==.',
Tr='Trebuchet:BAAALgAECgcJCAAAAA==.Treefrog:BAAALgADCgkJDAAAAA==.Treeshine:BAAALgAECgcJAQABLgAECggJDQADAAAAAA==.',
Tu='Tuggins:BAAALgADCgkJEQAAAA==.Tusi:BAAALgADCgEJAQAAAA==.',
Ty='Tychondriuss:BAABLgAECn8WAAIGAAYJ0B89OgC6AQAGAAYJ0B89OgC6AQAAAA==.Tylar:BAAALgAECgEJAQAAAA==.Tyrgor:BAAALgAECgMJBgAAAA==.',
Ub='Ubeenbained:BAABLgAECn8aAAISAAYJZw1wGgAKAQASAAYJZw1wGgAKAQAAAA==.',
Un='Unlock:BAAALgAECgcJDwAAAA==.',
Ur='Urgmathron:BAAALgAECgYJDwAAAA==.Ursão:BAAALgADCgcJBwAAAA==.',
Va='Valkorión:BAAALgADCgkJCQAAAA==.Valorisa:BAACLgAFFH8VAAMFAAUJnRL3EAAoAQAFAAQJnRL3EAAoAQABAAUJJQL9FgASAQAuAAQKfyQAAwUACAnRIn0EALQCAAUACAnRIn0EALQCAAEAAQlsGQV0AEgAAAAA.Vargko:BAAALgADCgkJEwAAAA==.Vassik:BAAALgADCgUJBQAAAA==.Vaughan:BAAALgADCgcJCQAAAA==.Vaush:BAAALgADCgkJCQAAAA==.',
Vd='Vdr:BAAALgADCgEJAQAAAA==.',
Ve='Velantheron:BAAALgAECgEJAQAAAA==.Vezrx:BAAALgAFFAIJAwAAAA==.',
Vi='Vinsmoke:BAAALgAECgQJBgAAAA==.Vitanimm:BAAALgADCgIJAwAAAA==.Vitiate:BAAALgAECgYJBgAAAA==.',
Vo='Volcanoez:BAAALgAECgQJBwAAAA==.',
Vr='Vrezor:BAAALgAECgQJDAAAAA==.',
Vy='Vyolnc:BAAALgAECgQJCAAAAA==.Vyrexiona:BAABLgAECn8YAAMNAAcJ1Rl7GAANAgANAAcJ1Rl7GAANAgAOAAEJtwIORgAdAAAAAA==.',
['Vë']='Vëssël:BAAALgAECgcJDAAAAA==.',
Wa='Warthelian:BAAALgADCgcJBwABLgAECgYJCgADAAAAAA==.',
Wi='Wigglethorn:BAABLgAECn8XAAIcAAgJ2hwkJQCSAgAcAAgJ2hwkJQCSAgAAAA==.Winchells:BAAALgAECgcJAQAAAA==.Winddy:BAAALgAECgYJEwAAAA==.Winrodan:BAAALgAECggJDAAAAA==.',
Wo='Wokthisway:BAAALgAECgQJCAAAAA==.Wolpertinger:BAAALgADCgYJBgAAAA==.',
Wr='Wreck:BAAALgADCgYJBgABLgAECgEJEgADAAAAAA==.',
Wy='Wych:BAAALgAECgYJDgABLgAECgcJFwAJALwdAA==.Wynain:BAAALgADCgUJBQAAAA==.',
Xi='Xinjun:BAAALgAECgQJCAAAAA==.',
Xl='Xlh:BAAALgAECgcJAwAAAA==.',
Xp='Xpaínzkilla:BAAALgADCgQJBAAAAA==.',
Xs='Xsslopgob:BAAALgAECgYJDwAAAA==.',
Xu='Xufoxpikmin:BAAALgADCgUJBAAAAA==.',
Ya='Yappor:BAAALgAECgYJBgAAAA==.',
Ye='Yekteniya:BAAALgAECgYJCAAAAA==.',
Yi='Yibbers:BAAALgADCgIJAgAAAA==.Yiimmyy:BAAALgADCgEJAQAAAA==.',
Yo='Yoohoomoo:BAAALgADCgcJEgAAAA==.',
Yu='Yuna:BAAALgAECgUJDAAAAA==.Yur:BAAALgADCgcJDAABLgAECgcJEQADAAAAAA==.Yutch:BAAALgAECgYJCgAAAA==.',
Za='Zabuccy:BAAALgAECgYJCAAAAA==.Zacalkan:BAAALgAECgYJCgAAAA==.Zakkydrakky:BAABLgAECn8VAAMlAAcJLA66IwBbAQAlAAcJLA66IwBbAQANAAUJtggMOQC7AAAAAA==.Zani:BAAALgAECgIJAgAAAA==.Zarashara:BAABLgAECn8dAAMbAAcJEhZRFwB9AQAbAAcJEhZRFwB9AQAYAAYJzgMGTADiAAAAAA==.',
Ze='Zelta:BAAALgADCgkJEwAAAA==.Zerise:BAAALgAECgUJCwAAAA==.',
Zo='Zolidus:BAAALgADCgcJBwAAAA==.Zonckpog:BAAALgAECgcJCgAAAA==.',
Zu='Zugforlife:BAAALgAECgUJBQABLgAFFAEJAQADAAAAAA==.Zulkren:BAAALgAECgUJDQAAAA==.Zulugangrene:BAABLgAECn8eAAIcAAgJNBHYQwB6AQAcAAgJNBHYQwB6AQAAAA==.Zun:BAAALgAECgcJCwAAAA==.',
['Zá']='Záyá:BAAALgADCgIJAgAAAA==.',
['Èz']='Èzili:BAAALgAECgYJCwAAAA==.',
['Ód']='Ódinnhunt:BAAALgADCgEJAQAAAA==.',
['Üd']='Üdderchaos:BAABLgAECn8ZAAMUAAgJQxROVgDuAQAUAAgJ/BJOVgDuAQAgAAUJrQyVCwDTAAAAAA==.',
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

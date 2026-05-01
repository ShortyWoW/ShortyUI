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

local lookup = {'Shaman-Restoration','Hunter-Marksmanship','Unknown-Unknown','Mage-Frost','Warlock-Affliction','Warlock-Demonology','Warlock-Destruction','Warrior-Fury','Priest-Discipline','Evoker-Augmentation','Evoker-Devastation','Hunter-BeastMastery','Shaman-Elemental','Mage-Arcane','DemonHunter-Havoc','DemonHunter-Devourer','DeathKnight-Unholy','Druid-Guardian','Priest-Holy','Monk-Mistweaver','Monk-Windwalker','Rogue-Subtlety','Monk-Brewmaster','Paladin-Retribution','Priest-Shadow','Paladin-Protection','Paladin-Holy','Hunter-Survival','DeathKnight-Frost','Druid-Feral','DemonHunter-Vengeance','Warrior-Protection','DeathKnight-Blood','Shaman-Enhancement',}
local provider = {region='US',realm='Gurubashi',name='US',type='weekly',zone=46,date='2026-05-01',data={Aa='Aadrisedh:BAAALgAECgYJBgAAAA==.Aaeryñ:BAAALgAECgcJBwAAAA==.Aaliyshaa:BAAALgAECgYJCgAAAA==.Aaramis:BAABLgAECn8dAAIBAAgJchCQOQCbAQABAAgJchCQOQCbAQAAAA==.',
Ab='Abandyn:BAAALgADCgcJCwAAAA==.',
Ad='Adrisehunt:BAAALgADCgQJBAAAAA==.',
Ae='Aegira:BAAALgADCgUJBgAAAA==.Aelira:BAAALgADCgkJCwAAAA==.Aendoril:BAAALgAECgQJCAAAAA==.',
Ag='Aggrodk:BAAALgAECgIJAgAAAA==.',
Ai='Aidoffhealer:BAAALgAECgMJBQAAAA==.',
Al='Alariah:BAAALgAECgQJBwAAAA==.Alaín:BAABLgAECn8eAAICAAgJrBZnBQCmAQACAAgJrBZnBQCmAQAAAA==.Aldoladre:BAAALgADCgYJBgABLgAECgYJCgADAAAAAA==.Aldoraline:BAAALgADCgIJAwAAAA==.Alegedly:BAAALgADCgcJBwAAAA==.Alicê:BAAALgADCgYJCQABLgAECgEJAQADAAAAAA==.Alystair:BAAALgADCgQJCAABLgAECgYJEAADAAAAAA==.',
Am='Ambellina:BAAALgAECgQJBQAAAA==.Ampse:BAAALgAECgUJBwAAAA==.Amzy:BAAALgADCgYJCQAAAA==.',
An='Anaria:BAAALgAECgQJCAAAAA==.Angbu:BAAALgAECgcJEgAAAA==.Angelpika:BAAALgADCgEJAQAAAA==.',
Ap='Apinkninja:BAABLgAECn8aAAIEAAcJsxlNMACiAQAEAAcJsxlNMACiAQAAAA==.',
Ar='Aranyssa:BAABLgAECn8UAAQFAAkJ3RL6HACKAAAGAAYJeBDPoQAVAQAHAAMJ2hWGRQCgAAAFAAIJsBj6HACKAAAAAA==.Arch:BAAALgAECgIJAgABLgAFFAMJCAAGAMAeAA==.Arclock:BAAALgADCgcJBwAAAA==.Arconnai:BAABLgAFFH8HAAIIAAMJMgoKEwDvAAAIAAMJMgoKEwDvAAAAAA==.Ardur:BAAALgAECgMJAwAAAA==.Arnøld:BAAALgAECgEJAQAAAA==.Arruna:BAAALgAECgYJDAAAAA==.Artorìas:BAAALgADCgkJCwABLgAECgYJEAADAAAAAA==.',
As='Asham:BAABLgAECn8UAAIJAAgJgQpEEwBiAQAJAAgJgQpEEwBiAQAAAA==.Ashenbloom:BAAALgAECgYJDQAAAA==.Asiago:BAABLgAECn8VAAMKAAgJ1xMaLQBYAQAKAAgJ1xMaLQBYAQALAAEJRgeuPwAxAAAAAA==.Aspect:BAAALgAECgYJEAAAAA==.',
Au='Augmenter:BAAALgAECgIJAgAAAA==.Aureliah:BAAALgADCgcJBwAAAA==.Autable:BAAALgAECgEJAQAAAA==.',
Av='Avacúma:BAAALgAECgEJAgAAAA==.Avvalethra:BAABLgAECn8lAAMMAAgJDRROFgDgAQAMAAgJDRROFgDgAQACAAgJpw01DwDXAAAAAA==.',
Ax='Axane:BAAALgADCggJCgAAAA==.',
Ay='Ayekea:BAAALgAECgYJCgAAAA==.',
Az='Azenet:BAAALgAECgEJAQABLgAFFAYJEAALAF0hAA==.',
['Aé']='Aélyrá:BAAALgAECgEJAQAAAA==.',
Ba='Bachshots:BAAALgAECggJDwAAAA==.Badassbich:BAAALgADCgEJAQAAAA==.Baggett:BAAALgAECgYJBgAAAA==.Bainey:BAAALgADCgIJAgABLgADCgYJCgADAAAAAA==.Bananataffy:BAAALgAECgMJAwAAAA==.Barackoshama:BAABLgAECn8ZAAINAAkJWhi9IwDyAQANAAkJWhi9IwDyAQAAAA==.Barfdrinker:BAAALgAECgYJBwAAAA==.Barlaina:BAAALgADCgEJAQAAAA==.Basedween:BAAALgADCgYJCAAAAA==.Battlescars:BAAALgAECgcJEAAAAA==.Baw:BAABLgAECn8kAAMEAAgJUhqpGAAYAgAEAAgJUhqpGAAYAgAOAAMJFwmUFQBvAAAAAA==.',
Be='Bearlinwall:BAAALgAECgYJDQAAAA==.Befoul:BAAALgAECgQJBAAAAA==.Bellyz:BAAALgAECgYJBwAAAA==.Bernham:BAAALgADCgMJAwAAAA==.',
Bi='Bigcheifpoop:BAAALgAECgEJAQAAAA==.Bigdumbo:BAAALgAECgEJAQABLgAECgcJEwADAAAAAA==.Bigskydh:BAAALgAECgYJCwAAAA==.Bigskymage:BAAALgAECgQJCgAAAA==.Billybones:BAAALgAECgEJAQAAAA==.Bip:BAAALgADCgEJAQAAAA==.',
Bl='Blackrazor:BAAALgADCgIJAgAAAA==.Blacksburden:BAAALgAECgMJAwABLgAECgcJDwADAAAAAA==.Blackvalor:BAAALgADCgMJAwAAAA==.Blackwÿn:BAAALgAECgEJAQABLgAECgYJEwADAAAAAA==.Bladedozzer:BAAALgAECgUJBwAAAA==.Blindinglite:BAABLgAECn8bAAIPAAcJSiIlDgCCAgAPAAcJSiIlDgCCAgAAAA==.Blindtoast:BAAALgAECgEJAQAAAA==.Blkpriest:BAAALgAECgIJAgAAAA==.Bloodhaze:BAABLgAECn8aAAIPAAgJFB8YCwCvAgAPAAgJFB8YCwCvAgAAAA==.Blorp:BAACLgAFFH8HAAIQAAMJlhSAHgDvAAAQAAMJlhSAHgDvAAAuAAQKfxsAAhAACAnfHM4lAHACABAACAnfHM4lAHACAAAA.',
Bo='Bodizzle:BAAALgADCgkJFwAAAA==.Bonez:BAAALgADCgMJAwAAAA==.Boondoggle:BAAALgAECgQJBwAAAA==.Borestus:BAAALgAECgYJCAAAAA==.Bouldur:BAAALgAECgUJDAAAAA==.Bownystark:BAABLgAECn8eAAICAAcJCCISFQCHAgACAAcJCCISFQCHAgAAAA==.Bozz:BAAALgAECgEJAQAAAA==.',
Br='Brieter:BAAALgAECgcJDAABLgAECggJFQAKANcTAA==.Brinar:BAAALgAECgQJCQAAAA==.Brokikobo:BAAALgADCggJCwAAAA==.Broughston:BAAALgAECgEJAQAAAA==.Brutusx:BAAALgAECgYJDgAAAA==.',
Bu='Bullhockey:BAAALgAECgEJAQAAAA==.Bullshiftsal:BAAALgAECgUJEQAAAA==.',
Bw='Bwabwagon:BAAALgADCgcJDgAAAA==.',
Bx='Bxxberry:BAAALgADCgkJFgAAAA==.',
Ca='Camipriest:BAAALgAECgEJAQAAAA==.Casstyelle:BAAALgAECgQJBAABLgAECgYJCQADAAAAAA==.Catpizz:BAAALgADCgEJAQAAAA==.',
Ce='Celedael:BAAALgAECgQJCAABLgAECgkJFAAFAN0SAA==.',
Ch='Chairon:BAAALgAECgMJAwABLgAECgUJEAADAAAAAA==.Changed:BAAALgAECgIJAgAAAA==.Chauvinpack:BAAALgAECgcJBwAAAA==.Cheesus:BAAALgAECgYJCQABLgAECggJFQAKANcTAA==.Chicharon:BAAALgAECgQJCwAAAA==.Chickentacos:BAAALgADCgkJCAABLgAECgcJDgADAAAAAA==.Chipsnsalsa:BAAALgAECgEJAQABLgAECgcJDgADAAAAAA==.Chocoriffic:BAAALgAECgcJDgAAAA==.Chokoballs:BAAALgAECgEJAQABLgAECggJIgARAAsVAA==.',
Cl='Clawmommy:BAAALgAECgMJAwAAAA==.',
Co='Cojobo:BAAALgADCgYJCQAAAA==.Coko:BAABLgAECn8jAAISAAgJgB71AQBfAgASAAgJgB71AQBfAgAAAA==.Coldbrewz:BAAALgAECgYJDwAAAA==.Condensation:BAAALgADCgEJAQAAAA==.Corgibutts:BAAALgAECgEJAQAAAA==.',
Cr='Crackjones:BAAALgAECgIJAgAAAA==.Crazydave:BAABLgAECn8aAAITAAkJ6xEiIwDMAQATAAkJ6xEiIwDMAQAAAA==.Creemywitchu:BAAALgADCgEJAQABLgADCgcJBwADAAAAAA==.Crism:BAAALgAECgQJAwAAAA==.Crismggt:BAAALgAFFAEJAQAAAA==.Crismtg:BAAALgAECgQJBwAAAA==.Crispytank:BAAALgADCgcJCgAAAA==.Cryptìc:BAAALgAECgYJBwABLgAFFAUJDgAEAHYYAA==.Cryptîc:BAACLgAFFH8OAAIEAAUJdhjOEwBxAQAEAAUJdhjOEwBxAQAuAAQKfycAAgQACAmUJbMEAPMCAAQACAmUJbMEAPMCAAAA.',
Cu='Cursadilla:BAAALgAECgQJCgAAAA==.',
Cy='Cylissari:BAAALgAECgYJBgAAAA==.',
Da='Daasstion:BAABLgAECn8YAAIEAAcJjxlQXwAdAgAEAAcJjxlQXwAdAgAAAA==.Dabbia:BAABLgAECn8bAAMHAAgJpRwGEwCzAQAGAAYJeBuLVwDBAQAHAAYJ5RoGEwCzAQAAAA==.Daedleus:BAAALgADCgQJBAAAAA==.Damented:BAAALgAECgYJCQAAAA==.Darkaitsu:BAAALgAECgEJAQAAAA==.Dawnpaw:BAABLgAECn8cAAMUAAkJFRNRIgCgAQAUAAgJyhBRIgCgAQAVAAUJDhVnGwAKAQAAAA==.',
De='Deathballz:BAABLgAECn8iAAIRAAgJCxW0HwDJAQARAAgJCxW0HwDJAQAAAA==.Deathsbreach:BAAALgAECgYJEQAAAA==.Deathsmite:BAAALgAECgEJAQAAAA==.Deathtee:BAABLgAECn8XAAIRAAgJqBxGRgAiAgARAAgJqBxGRgAiAgAAAA==.Deepwaters:BAAALgADCgcJDgAAAA==.Dekuslice:BAAALgAECgYJEAAAAA==.Delafant:BAAALgAECgUJCgAAAA==.Demencia:BAAALgADCgQJBAAAAA==.Demonclawx:BAAALgADCgcJCAAAAA==.Dephlorate:BAAALgADCgcJCAAAAA==.Derpyderp:BAAALgADCgcJCAABLgAECggJEwADAAAAAA==.Destroyah:BAAALgADCgUJBwABLgAECgcJEgADAAAAAA==.Devile:BAAALgADCgIJAgAAAA==.Devocate:BAAALgADCgcJCAAAAA==.',
Di='Dinkys:BAAALgADCgYJCwABLgAECgYJDwADAAAAAA==.Diogenist:BAAALgAECgIJAwAAAA==.Dirtypeasant:BAAALgADCgUJBQAAAA==.',
Dk='Dkballz:BAAALgAECgEJAQABLgAECgcJFQAWAOMiAA==.',
Do='Dogdad:BAAALgADCgcJCwAAAA==.Doktardoodad:BAAALgAECgMJAwAAAA==.Doktartides:BAAALgADCgEJAQAAAA==.Doktarzen:BAAALgAECgMJBQAAAA==.Doktershokk:BAAALgADCgEJAgAAAA==.Donkel:BAAALgAECgEJAQAAAA==.Doomslayer:BAABLgAECn8XAAIQAAgJdQnvYgB4AQAQAAgJdQnvYgB4AQAAAA==.Doresearch:BAABLgAECn8iAAINAAgJgBVWDQDIAQANAAgJgBVWDQDIAQAAAA==.',
Dr='Drackani:BAAALgADCgYJBgAAAA==.Draenutt:BAABLgAECn8VAAIGAAgJzh7PEQAWAgAGAAgJzh7PEQAWAgAAAA==.Dragontee:BAAALgADCgQJBAABLgAECggJFwARAKgcAA==.Drakarys:BAAALgAECgYJCwAAAA==.Drakex:BAAALgAECgUJBgAAAA==.Drengist:BAABLgAECn8hAAIXAAgJkRQUEgB7AQAXAAgJkRQUEgB7AQAAAA==.Drexybear:BAABLgAECn8XAAMMAAcJ9iErCgBaAgAMAAcJ9iErCgBaAgACAAUJBBfDQgBLAQAAAA==.Drezbi:BAAALgAECgMJBAAAAA==.Drpebbles:BAAALgAECgQJCwAAAA==.Druidskillz:BAAALgADCgEJAQAAAA==.',
Du='Dulcineru:BAAALgADCgYJBwAAAA==.Dunbarth:BAABLgAECn8ZAAIYAAgJvQzebQChAQAYAAgJvQzebQChAQAAAA==.Durzaman:BAAALgAECgYJDQAAAA==.Durzuk:BAAALgAECgMJAwAAAA==.Duskhoof:BAAALgADCgIJAwAAAA==.',
['Dé']='Dévílyñ:BAAALgAECgYJDwAAAA==.',
['Dü']='Dük:BAABLgAECn8YAAMGAAcJexFfPQA6AQAGAAYJIRJfPQA6AQAHAAIJOw5KTACIAAAAAA==.',
Eg='Eggy:BAAALgAECgkJDgAAAA==.',
El='Eldraaqeyn:BAAALgADCgcJDAAAAA==.Elephant:BAAALgAECgQJCQAAAA==.Elkanàh:BAAALgAECgIJAgABLgAECggJKQATAKEgAA==.Elleynle:BAAALgAECgQJCgAAAA==.Elunara:BAABLgAECn8bAAISAAkJLh6mAQB3AgASAAkJLh6mAQB3AgABLgAECgkJFAAFAN0SAA==.',
Em='Emhotep:BAAALgADCgMJAwAAAA==.',
En='Enazar:BAAALgADCgIJAgAAAA==.Enigmä:BAAALgADCgYJCgAAAA==.Enio:BAAALgAECgMJAwAAAA==.',
Er='Ericuh:BAAALgAECgYJEwAAAA==.',
Es='Escanör:BAAALgAECgYJBgABLgAECgYJEAADAAAAAA==.Essekk:BAACLgAFFH8IAAIEAAMJHg13LgD9AAAEAAMJHg13LgD9AAAuAAQKfywAAgQACQklH1sWACMDAAQACQklH1sWACMDAAAA.',
Eu='Euliana:BAAALgADCgUJBQAAAA==.',
Ev='Evokeeznutz:BAAALgAECgcJCQABLgAECgcJDAADAAAAAA==.',
Ex='Exesolo:BAAALgADCgYJBwAAAA==.Exploreswag:BAAALgAECgcJDgAAAA==.',
Ey='Eyeshmesch:BAAALgADCgUJBQABLgAECgMJAwADAAAAAA==.',
['Eí']='Eír:BAAALgADCgYJDQABLgAECggJJgATADQaAA==.',
Fa='Fairyholy:BAAALgADCgEJAQAAAA==.Fallenchaos:BAAALgAECgYJBgAAAA==.Famjam:BAAALgAECgYJCAAAAA==.Fao:BAAALgADCgMJAwAAAA==.Fastrialimas:BAAALgAECgEJBAAAAA==.Fatpo:BAABLgAECn8bAAMTAAgJzSC8BgDiAgATAAgJzSC8BgDiAgAZAAEJwRvINwBVAAAAAA==.Fayjhu:BAABLgAECn8YAAIEAAcJPAnvWAAsAQAEAAcJPAnvWAAsAQAAAA==.',
Fe='Ferbos:BAAALgAECgIJAwAAAA==.Feylock:BAABLgAECn8UAAIGAAcJ6xD2PAA8AQAGAAcJ6xD2PAA8AQAAAA==.',
Fi='Fiastrei:BAAALgADCgcJCQAAAA==.',
Fl='Flexo:BAAALgADCgQJBAAAAA==.',
Fo='Forheretogo:BAAALgADCgEJAQAAAA==.Foô:BAABLgAECn8rAAIWAAgJ4x+wAwBhAgAWAAgJ4x+wAwBhAgAAAA==.',
Fr='Frigate:BAABLgAECn8XAAIEAAcJRAXXgwDMAAAEAAcJRAXXgwDMAAAAAA==.Frihgate:BAABLgAECn8XAAIMAAcJWBdxMgDmAQAMAAcJWBdxMgDmAQAAAA==.Frostbitten:BAAALgADCgYJBgAAAA==.Frostea:BAAALgADCgUJBgAAAA==.Frostmyface:BAAALgAFFAEJAQAAAA==.Frozenbeard:BAAALgAECgcJEgAAAA==.',
Fu='Fugbug:BAAALgADCgYJBwAAAA==.Furcrazy:BAABLgAECn8WAAIXAAgJfSG4BABmAgAXAAgJfSG4BABmAgAAAA==.Furdreich:BAAALgADCgIJAgAAAA==.Furryoffury:BAAALgADCgYJBgAAAA==.Furynagger:BAAALgADCgEJAQAAAA==.Furyosia:BAAALgADCgEJAQAAAA==.Furyrosa:BAAALgAECgEJAQAAAA==.Fuzi:BAAALgADCgUJBQABLgAECgMJAwADAAAAAA==.',
Fy='Fyafya:BAAALgADCgEJAQAAAA==.Fyah:BAAALgAECggJEAABLgAFFAUJDQAMAEQVAA==.Fyaza:BAAALgAECgIJAgAAAA==.',
Ga='Gargamels:BAAALgADCggJEwABLgAECgkJBQADAAAAAA==.Gariantel:BAAALgADCgkJFwAAAA==.Garou:BAAALgAECgQJCQAAAA==.',
Ge='Geekylock:BAAALgAECgQJCAAAAA==.Genesis:BAAALgAECgkJAgAAAA==.Geobloom:BAAALgADCgUJBgAAAA==.Gerbic:BAAALgAECgEJAQAAAA==.Germ:BAAALgAECgQJCAAAAA==.Gerttie:BAAALgAECgQJBAAAAA==.',
Gh='Ghosted:BAAALgAECgMJBQAAAA==.',
Gi='Gilgalador:BAAALgADCgMJAwAAAA==.Gingdrac:BAAALgADCgcJDgABLgAFFAcJGgAJAKogAA==.Givepenance:BAAALgADCgcJFAAAAA==.',
Go='Gomdagarm:BAAALgADCgUJBQAAAA==.Gopwal:BAAALgAECgcJDQAAAA==.Gorehammer:BAABLgAECn8qAAIRAAgJmhmlIQC9AQARAAgJmhmlIQC9AQAAAA==.Gorto:BAAALgADCgYJCwAAAA==.',
Gr='Gravediger:BAAALgAECgQJBAAAAA==.Gravepaws:BAAALgADCgIJAgAAAA==.Greatfatherx:BAAALgADCgEJAQAAAA==.Gridxx:BAAALgADCgUJBQAAAA==.Grievex:BAABLgAECn8mAAIYAAkJ6waBLgCIAQAYAAkJ6waBLgCIAQAAAA==.Grimbeorn:BAAALgADCgEJAQAAAA==.',
['Gî']='Gîgâbussy:BAAALgADCgIJAgAAAA==.',
Ha='Hairybear:BAAALgADCgYJBgAAAA==.Hanazawa:BAAALgADCgMJBAAAAA==.Hanyu:BAAALgADCgMJAwAAAA==.Haydayy:BAAALgADCgYJBgAAAA==.Hazykeety:BAAALgADCgEJAQAAAA==.',
He='Healsonwheel:BAAALgAECgcJCgAAAA==.Healthiss:BAAALgAECgQJBgAAAA==.Helaziri:BAAALgAECgYJEQAAAA==.Hemolock:BAAALgAECgYJEwABLgAFFAMJCgAYAJcYAA==.Hemostasis:BAACLgAFFH8KAAIYAAMJlxgJFQABAQAYAAMJlxgJFQABAQAuAAQKfx8ABBgABwkqI5UwAGACABgABwkqI5UwAGACABoAAQn4DU8oAC8AABsAAQnCAPmhACUAAAAA.Herjä:BAABLgAECn8mAAMTAAgJNBo9BgBWAgATAAgJMxo9BgBWAgAJAAYJrRNdJQBpAQAAAA==.',
Hi='Hinkles:BAAALgAECgYJDwAAAA==.',
Ho='Hoocha:BAAALgADCgYJBgABLgAECgcJDAADAAAAAA==.Hoollymollyy:BAAALgADCgYJCQAAAA==.Hornsly:BAAALgADCgMJAwAAAA==.Hotandcold:BAAALgAECgEJAQAAAA==.',
Hu='Huntingpoo:BAAALgAECgYJEgAAAA==.Huntweak:BAAALgAECgIJAgAAAA==.Huun:BAABLgAECn8eAAIcAAgJehhQBgAKAgAcAAgJehhQBgAKAgAAAA==.',
Hy='Hyasynthia:BAAALgAECgQJAwAAAA==.',
Ia='Iamnsfw:BAAALgAECgcJEgAAAA==.',
Il='Illydan:BAAALgAECgcJEQAAAA==.Ilvisarxiln:BAAALgADCgUJBQAAAA==.',
Im='Imataquito:BAABLgAECn8oAAIEAAgJGiF7DwBhAgAEAAgJGiF7DwBhAgAAAA==.',
In='Indigø:BAAALgAECgMJBAAAAA==.Inepsy:BAAALgAECgEJAQAAAA==.Infelicity:BAAALgADCgYJCQAAAA==.Infortunii:BAAALgADCgYJBgABLgAFFAEJAQADAAAAAA==.',
Ir='Irezufortips:BAAALgADCgcJBwABLgAECgkJBQADAAAAAA==.Ironhide:BAAALgAECgIJAgAAAA==.Ironshadow:BAAALgADCgEJAQAAAA==.Irrenadro:BAABLgAECn8VAAIYAAgJJQ69fQB+AQAYAAgJJQ69fQB+AQAAAA==.Irvainee:BAAALgAECgYJDAAAAA==.',
It='Itsp:BAAALgAECgUJBQAAAA==.',
Ja='Jadechaos:BAAALgAECgEJAQAAAA==.Jahkazul:BAAALgADCgYJDAAAAA==.Jarnabas:BAAALgAECgIJAgAAAA==.Jayec:BAAALgAECgEJAQAAAA==.',
Ji='Jimboslice:BAAALgADCgcJBwAAAA==.Jingleparts:BAAALgADCggJCQABLgAECgcJDgADAAAAAA==.',
Jo='Joes:BAABLgAECn8XAAMMAAYJ3hfWLQBaAQAMAAUJUhzWLQBaAQACAAYJ2wXuEQCyAAAAAA==.Jonesy:BAAALgAECgUJCwAAAA==.Jorath:BAAALgADCgQJBAABLgAECgkJBQADAAAAAA==.',
Ju='Juicygossip:BAAALgADCgkJEwAAAA==.Jujupowa:BAAALgAECgcJDwAAAA==.Junebug:BAAALgAECgQJBQAAAA==.Justicus:BAAALgADCgIJAgAAAA==.',
['Jö']='Jöe:BAAALgAECgEJAQAAAA==.',
Ka='Kagal:BAABLgAECn8WAAIcAAgJ3hFsDwDNAQAcAAgJ3hFsDwDNAQAAAA==.Kaidan:BAABLgAECn8ZAAIMAAgJ9RCuMwDgAQAMAAgJ9RCuMwDgAQAAAA==.Kaipriest:BAAALgAECgQJBAAAAA==.Kaladinn:BAAALgADCgEJAQAAAA==.Kaledra:BAAALgADCgYJBgAAAA==.Kalyke:BAAALgADCggJDQAAAA==.Kamikazejoe:BAAALgADCgEJAQAAAA==.Kargian:BAAALgAECgQJBAAAAA==.Kasumirenn:BAAALgAECgMJAwABLgAECggJHgAPAJokAA==.Katanya:BAAALgAECgYJBgABLgAECgkJFAAFAN0SAA==.Katarinabluu:BAAALgADCgYJBgAAAA==.',
Ke='Keetra:BAABLgAFFH8IAAIMAAMJ5wsEHAD0AAAMAAMJ5wsEHAD0AAAAAA==.Keftheals:BAAALgADCgEJAQAAAA==.Keiriline:BAABLgAECn8VAAMdAAcJCRSTAwCNAQAdAAcJCRSTAwCNAQARAAEJYwAD0wAaAAAAAA==.Keledorimash:BAAALgADCgYJCAAAAA==.Keva:BAAALgAECgYJEgAAAA==.Keyboard:BAAALgADCgIJAQAAAA==.Kez:BAAALgAECgYJCgAAAA==.',
Kh='Khaalian:BAAALgAECgIJAwAAAA==.',
Ki='Killbreed:BAABLgAECn8ZAAIeAAgJ+B9ABADdAgAeAAgJ+B9ABADdAgAAAA==.Kinkster:BAAALgAECgMJAwAAAA==.Kirinani:BAAALgAECgEJAQAAAA==.Kirzan:BAAALgADCgMJAwAAAA==.Kizaruu:BAAALgADCgEJAQAAAA==.',
Kn='Knifeprty:BAAALgADCgUJBgAAAA==.Knuggz:BAAALgAECgYJEwAAAA==.',
Ko='Kolduna:BAAALgADCgUJBQAAAA==.Koshmare:BAAALgADCgUJBQAAAA==.Kozanazure:BAAALgADCggJDAAAAA==.',
Kr='Krestaul:BAAALgAECgcJBAAAAA==.',
Ku='Kurthalan:BAAALgAECgQJCAAAAA==.Kuumaneko:BAABLgAECn8XAAMGAAgJThSkJgCVAQAGAAgJThSkJgCVAQAHAAYJrwcMMQD1AAAAAA==.',
Ky='Kyarita:BAAALgAECgIJAgAAAA==.Kyballion:BAAALgAECgYJEQAAAA==.Kyledh:BAACLgAFFH8LAAIQAAQJfRgsGQAGAQAQAAQJfRgsGQAGAQAuAAQKfy4AAxAACQmSJEYPAAUDABAACQmSJEYPAAUDAB8AAQluIf4jAGIAAAAA.Kyletotems:BAAALgADCggJCAAAAA==.Kyllgorre:BAAALgAECgEJAQAAAA==.Kynyine:BAAALgADCgcJCAAAAA==.',
La='Laerosia:BAAALgADCgUJBQAAAA==.Landridan:BAAALgADCgYJCQAAAA==.Lanthin:BAAALgADCgYJCgAAAA==.Larzoh:BAABLgAECn8YAAMPAAgJ9COjAwBGAwAPAAgJ9COjAwBGAwAQAAEJgxgy5QAtAAAAAA==.',
Le='Lee:BAAALgADCgYJBQABLgAECgcJKAARAAciAA==.Legadiaus:BAAALgAECgEJAQAAAA==.Lemonheads:BAABLgAECn8mAAMJAAcJpBTeEQBzAQAJAAcJpBTeEQBzAQAZAAEJ4QEoagAjAAAAAA==.Lethargy:BAAALgAECgQJBAAAAA==.',
Li='Liaenara:BAAALgADCgQJCQAAAA==.Lidorila:BAAALgADCgYJDAAAAA==.Lightpallyzz:BAAALgADCgEJAQAAAA==.Lilin:BAAALgADCgcJCgABLgAECgYJDgADAAAAAA==.Lilwiz:BAAALgADCgcJHAAAAA==.Lindre:BAAALgADCgQJBAAAAA==.Linnxvx:BAAALgAECgEJAQAAAA==.Lishp:BAAALgADCgMJAwAAAA==.Littleiceice:BAAALgADCgEJAQAAAA==.',
Ll='Llemonz:BAAALgAECgMJBAAAAA==.',
Lo='Lockaf:BAAALgADCgUJBQABLgAECgUJBgADAAAAAA==.Lohki:BAAALgADCgEJAQAAAA==.Lonelyroad:BAAALgADCgMJAwAAAA==.Lostsausage:BAAALgAECgQJBgABLgAECgYJEwADAAAAAA==.Lothaire:BAAALgADCgEJAQAAAA==.Lothiet:BAAALgAECgYJCwABLgAECgcJEgADAAAAAA==.',
Lu='Luayhanui:BAAALgADCgEJAQAAAA==.Lugeya:BAAALgADCgYJBgAAAA==.Lunarcricket:BAAALgAECgMJAwAAAA==.Lustpls:BAAALgAECgQJBAABLgAECgYJBwADAAAAAA==.',
Ly='Lyncha:BAAALgADCgcJDgABLgAECggJIAAaAHMiAA==.Lynchà:BAABLgAECn8gAAIaAAgJcyLoAQCFAgAaAAgJcyLoAQCFAgAAAA==.Lynchä:BAAALgADCgEJAQABLgAECggJIAAaAHMiAA==.',
Ma='Maakun:BAABLgAECn8dAAQTAAcJ3gxbOwBNAQATAAcJ2gdbOwBNAQAZAAUJ8wcUQAD2AAAJAAQJHg2nOgDTAAAAAA==.Maddiebaby:BAAALgAECgQJCAABLgAECgUJBQADAAAAAA==.Mageapoug:BAAALgADCgcJBwAAAA==.Magmalance:BAAALgAECgIJAgABLgAECgYJEQADAAAAAA==.Mahzad:BAABLgAECn8fAAIBAAYJPCM9GABUAgABAAYJPCM9GABUAgAAAA==.Maladi:BAAALgADCgkJEgAAAA==.Malfrun:BAABLgAECn8UAAIgAAgJ5xJqCgCDAQAgAAgJ5xJqCgCDAQAAAA==.Marinnite:BAAALgADCgYJDQAAAA==.Marox:BAAALgAECggJEQAAAA==.Marshmellows:BAAALgAECgYJBgAAAA==.Mastolus:BAAALgADCgEJAQAAAA==.Mathesi:BAAALgADCgYJCQAAAA==.Mathrim:BAACLgAFFH8IAAIGAAMJwB6LHQAsAQAGAAMJwB6LHQAsAQAuAAQKfyAAAwYACAk3I00VANUCAAYABwk3I00VANUCAAcAAQkAANZVAG0AAAAA.Matooka:BAAALgAECgcJEgAAAA==.Maynji:BAAALgAECgMJAwAAAA==.Mayushi:BAAALgAECgYJCQAAAA==.',
Me='Meencurry:BAABLgAECn8bAAIEAAYJHhXSmgCgAQAEAAYJHhXSmgCgAQAAAA==.Megozugzug:BAAALgAECgIJAgABLgAFFAEJAQADAAAAAA==.Meyneth:BAAALgAECgEJAQAAAA==.',
Mi='Mikaì:BAAALgAECggJEQAAAA==.Mikehawkener:BAAALgAECgUJBwAAAA==.Misleading:BAAALgAECgQJBwAAAA==.Misotofu:BAAALgADCgcJCgAAAA==.Mistfisting:BAAALgAFFAMJAwAAAA==.',
Mo='Moderato:BAAALgAECgYJCwAAAA==.Moelleri:BAABLgAECn8XAAIRAAYJPxkeNgBhAQARAAYJPxkeNgBhAQAAAA==.Mojowarlock:BAAALgADCgYJBgABLgAECgUJBQADAAAAAA==.Moneymage:BAAALgAECgUJBQAAAA==.Monkgroom:BAACLgAFFH8HAAIUAAMJKgmpEQCNAAAUAAMJKgmpEQCNAAAuAAQKfx0AAxQACQmcFAkXAAkCABQACQmcFAkXAAkCABUABgnxCtU5ADYBAAAA.Monsignor:BAAALgAECgEJAwAAAA==.Montra:BAABLgAECn8oAAMSAAkJMBwfBQCOAgASAAkJMBwfBQCOAgAeAAUJAgn9HgDrAAAAAA==.Moreilira:BAAALgAECgQJBwAAAA==.Mornshield:BAABLgAECn8bAAMYAAYJWxSokQBZAQAYAAYJIxCokQBZAQAaAAUJUxMEJgDZAAABLgAECgkJBQADAAAAAA==.Morphien:BAAALgADCgcJCQAAAA==.Mortaveus:BAAALgAECgEJAQAAAA==.Motorinkashi:BAAALgAECggJCgAAAA==.Motto:BAAALgAECgEJAQAAAA==.Mouse:BAAALgADCgMJAwAAAA==.',
Mu='Muddgore:BAABLgAECn8YAAIgAAgJHhMoCgCIAQAgAAgJHhMoCgCIAQAAAA==.Muddthir:BAAALgAECgQJBAABLgAECggJGAAgAB4TAA==.Murkyblaizin:BAAALgAECgYJDQAAAA==.Mustardheals:BAAALgAECgUJCwAAAA==.',
My='Myharanir:BAAALgADCgUJBQAAAA==.Mypanda:BAAALgAECgIJAgAAAA==.Mythaera:BAAALgAECgQJCAABLgAECggJFwAYANocAA==.',
Na='Nazrra:BAABLgAECn8YAAIgAAgJfRVhEAADAgAgAAgJfRVhEAADAgAAAA==.Nazugrax:BAAALgAECgQJBAAAAA==.',
Ne='Neebsz:BAAALgADCgYJEgAAAA==.Nemene:BAAALgADCgUJBQAAAA==.Neolithic:BAAALgAECgcJBAAAAA==.Nerdeficent:BAAALgADCgQJBAAAAA==.Nestaah:BAAALgAFFAIJAwAAAA==.Nettra:BAAALgAECgIJBQAAAA==.Newtnewt:BAAALgAECgEJAQAAAA==.',
Ni='Nickparker:BAAALgADCggJCAAAAA==.Nicneven:BAAALgADCgkJCQAAAA==.Nininbrew:BAAALgADCgMJAwAAAA==.Nirath:BAABLgAECn8gAAIEAAgJdAvGPAB4AQAEAAgJdAvGPAB4AQAAAA==.',
No='Nobainer:BAAALgADCgYJCgAAAA==.Noed:BAAALgAECgMJAwAAAA==.Nohkano:BAABLgAECn8dAAIXAAgJayJ/BgAfAwAXAAgJayJ/BgAfAwAAAA==.Nokinkshame:BAAALgADCggJCQABLgAECgcJDgADAAAAAA==.Noobymonk:BAAALgAECgcJDQAAAA==.Noralise:BAAALgAECgYJDwAAAA==.Northerndk:BAAALgAECgcJEAAAAA==.Notsxldier:BAAALgADCgQJBAAAAA==.Novàstar:BAAALgADCgQJCAAAAA==.',
Nu='Numbuh:BAAALgAECgEJAgAAAA==.',
Ny='Nyxariaw:BAAALgADCggJDAAAAA==.Nyxmaris:BAAALgADCgYJBAAAAA==.',
['Nø']='Nøvâ:BAABLgAECn8fAAIEAAgJVhTBbAD8AQAEAAgJVhTBbAD8AQAAAA==.',
Oc='Octavarium:BAAALgAECgYJEwAAAA==.',
Od='Odinsmage:BAAALgADCgUJBgAAAA==.',
Oe='Oennomaus:BAAALgAECgUJBQAAAA==.',
Oh='Ohyshii:BAAALgAECgMJAwAAAA==.',
On='Oneshothel:BAAALgAECgUJCQAAAA==.Onran:BAAALgADCgUJBQABLgAECggJFwAYANocAA==.',
Or='Orcpeon:BAAALgAECgEJAgABLgAECggJJQAYADYcAA==.Oryndern:BAAALgAECgMJBwAAAA==.',
Ot='Otokunu:BAAALgADCgIJAgAAAA==.',
Ov='Ovenmitts:BAAALgAECgYJEgABLgAECgcJDgADAAAAAA==.',
Oz='Ozwalds:BAAALgADCgQJBAAAAA==.',
Pa='Paeonagos:BAAALgADCgMJAwAAAA==.Palimpsest:BAAALgADCgEJAQAAAA==.Pallymans:BAAALgADCgUJBQAAAA==.Pantheons:BAAALgADCgEJAQAAAA==.Parsi:BAAALgAECgcJCAAAAA==.Pawtism:BAAALgADCgcJBgAAAA==.',
Pe='Penut:BAAALgAECgEJAQAAAA==.Perritax:BAABLgAECn8ZAAIEAAcJ/A7ZPgBxAQAEAAcJ/A7ZPgBxAQAAAA==.',
Ph='Phialkit:BAAALgADCgcJBwAAAA==.Phoebelyria:BAAALgAECgQJBwAAAA==.Phêo:BAAALgAECgMJAwABLgAECgYJCgADAAAAAA==.',
Pi='Pickelz:BAAALgADCgMJAwAAAA==.Piffiny:BAAALgAECgYJBwAAAA==.Pine:BAAALgAECgMJAwAAAA==.Pingdoo:BAAALgAECgIJAgAAAA==.',
Po='Pofat:BAAALgAFFAEJAQAAAA==.Polis:BAABLgAECn8lAAIYAAgJNhzBEQAtAgAYAAgJNhzBEQAtAgAAAA==.Pomol:BAAALgAECgcJDQAAAA==.Pomoly:BAAALgADCgEJAQAAAA==.Poppafury:BAAALgAECgYJBwAAAA==.Potent:BAABLgAECn8aAAMRAAYJpw7qWgD0AAARAAYJpw7qWgD0AAAhAAQJbQaKOgBvAAAAAA==.Pougadina:BAAALgAECgIJAgABLgAECggJGwATAM0gAA==.',
Pr='Prislo:BAAALgADCgMJAwAAAA==.Prodie:BAAALgADCgMJBAAAAA==.Protect:BAAALgADCgMJAwAAAA==.Présage:BAABLgAECn8VAAMRAAgJEhZ0HwDKAQARAAgJEhZ0HwDKAQAhAAEJSwR5TwAXAAAAAA==.',
Ps='Pswar:BAAALgAECgEJAQAAAA==.',
Pu='Puriel:BAAALgADCgMJAwAAAA==.',
Pw='Pwnstar:BAAALgAECgMJAwAAAA==.',
Py='Pyrojoe:BAAALgAECgcJEAABLgAECgkJBQADAAAAAA==.',
['Pò']='Pò:BAAALgAECgIJBAAAAA==.',
Qi='Qizzle:BAAALgADCgMJAwAAAA==.',
Ra='Ramsha:BAABLgAECn8VAAIYAAYJWxaxRwAyAQAYAAYJWxaxRwAyAQAAAA==.Ramshunter:BAABLgAECn8fAAMMAAkJFCFgBwAaAwAMAAkJFCFgBwAaAwACAAIJ2xEUHQBLAAAAAA==.Randyvivaldi:BAAALgADCgEJAQAAAA==.Rashanda:BAAALgADCgMJAwAAAA==.Rathasas:BAAALgAECgIJAgAAAA==.Ratnob:BAABLgAECn8gAAIRAAkJJBU7GQDxAQARAAkJJBU7GQDxAQAAAA==.Ravnaar:BAAALgAECggJDQAAAA==.Razamatazz:BAAALgADCgEJAQAAAA==.',
Re='Reddemon:BAAALgAECgEJAQABLgAFFAEJAQADAAAAAA==.Redstraw:BAAALgADCgQJBAAAAA==.Relda:BAAALgAECgYJCQABLgAFFAEJAQADAAAAAA==.Renae:BAAALgAECgkJCAAAAA==.Renaud:BAAALgAECgQJBAAAAA==.Rennshi:BAABLgAECn8eAAIPAAgJmiQHBAA7AwAPAAgJmiQHBAA7AwAAAA==.Retpally:BAABLgAFFH8NAAIgAAQJrxHyBAA9AQAgAAQJrxHyBAA9AQAAAA==.Reyikrat:BAAALgAECgMJBwAAAA==.Rezmee:BAABLgAECn8VAAIRAAgJKSPPBQDEAgARAAgJKSPPBQDEAgAAAA==.',
Rh='Rheaf:BAAALgAECgYJCQAAAA==.',
Ri='Riastrad:BAAALgADCgUJBwAAAA==.Richie:BAABLgAECn8UAAIEAAYJoxB+vgBmAQAEAAYJoxB+vgBmAQAAAA==.Ringsofsatrn:BAAALgADCgEJAQAAAA==.Ripgoose:BAAALgADCggJEwAAAA==.',
Ro='Rolanthas:BAAALgADCgcJCQAAAA==.Rosario:BAACLgAFFH8FAAMcAAMJhREACgABAQAcAAMJgA8ACgABAQACAAIJMg01HwCZAAAuAAQKfyYAAwIACAmfIZINANYCAAIACAmfIZINANYCABwABQmeFh0NAI0BAAAA.',
Ry='Ryotwar:BAAALgAECgEJAQAAAA==.Rythmatic:BAABLgAECn8VAAIWAAcJ4yJNCADqAQAWAAcJ4yJNCADqAQAAAA==.Ryvenox:BAAALgADCgcJBwAAAA==.',
['Ré']='Rénae:BAAALgAECgkJAgABLgAECgkJCAADAAAAAA==.',
Sa='Sabil:BAAALgADCgYJBgAAAA==.Saccharine:BAABLgAECn8gAAMJAAgJCBnaBQBVAgAJAAgJCBnaBQBVAgAZAAEJdAASbQAHAAAAAA==.Sakieri:BAABLgAECn8mAAIZAAkJeBnuAgCYAgAZAAkJeBnuAgCYAgAAAA==.Salinomycin:BAAALgADCgcJBwAAAA==.Samedi:BAAALgAECgQJBAAAAA==.Sandordel:BAAALgADCgMJBAAAAA==.Sangan:BAAALgAECgQJCwAAAA==.Sanguini:BAABLgAECn8ZAAIEAAgJeRJyOwB8AQAEAAgJeRJyOwB8AQAAAA==.Sathari:BAAALgAECgQJBgAAAA==.',
Sc='Scrappycoco:BAAALgADCgQJBAAAAA==.Scye:BAAALgAECgIJAgAAAA==.',
Se='Seamanhunter:BAAALgADCgEJAQAAAA==.Seanoevil:BAAALgAFFAEJAQAAAA==.Selaris:BAAALgAECgMJBgAAAA==.Selathviala:BAAALgADCgMJBQAAAA==.Sephares:BAAALgADCgUJBQAAAA==.Serazal:BAACLgAFFH8QAAMLAAYJXSHGAQCDAQALAAQJJxvGAQCDAQAKAAQJCxxjGgDVAAAuAAQKfyoAAwsACQmzIsIBAC8DAAsACAlJI8IBAC8DAAoACAk3Ix8CAOACAAAA.',
Sh='Shadowblitzx:BAAALgAECgUJDwAAAA==.Shadowfall:BAAALgADCgkJEQAAAA==.Shaggin:BAAALgADCgMJAwAAAA==.Shamfoo:BAAALgADCggJCAABLgAECggJKwAWAOMfAA==.Shangan:BAAALgADCgEJAQAAAA==.Sharana:BAAALgADCggJCAAAAA==.Shhrekk:BAAALgAECgIJAgAAAA==.Shikendagoon:BAAALgADCgcJCwAAAA==.Shinøbu:BAAALgADCgYJDAAAAA==.Shirrazaha:BAAALgADCgMJAwAAAA==.Shortbejo:BAAALgADCgQJBgAAAA==.Shâzzam:BAAALgAECgYJBgAAAA==.',
Si='Silaris:BAAALgADCgMJBgAAAA==.Sinath:BAAALgAECgYJCgAAAA==.Singren:BAAALgADCgEJAQAAAA==.Sinnur:BAAALgAECgQJBAAAAA==.Sinsear:BAAALgADCgYJBgAAAA==.',
Sk='Skeezer:BAAALgAECgcJDAAAAA==.',
Sl='Sleeveless:BAAALgAECgcJDQAAAA==.Slizzie:BAAALgAECgYJBgAAAA==.Slowteeth:BAAALgADCgMJAwAAAA==.',
Sm='Smackdiver:BAAALgADCgYJAwAAAA==.Smarfus:BAAALgAECgYJCQABLgAFFAEJAQADAAAAAA==.Smilingdemon:BAAALgADCgIJAgAAAA==.Smilingp:BAAALgADCgcJBwAAAA==.Smiteznhealz:BAAALgADCgEJAQAAAA==.Smursh:BAAALgAECgQJBAAAAA==.',
Sn='Snakesabbath:BAAALgAECgUJCAAAAA==.Snarge:BAACLgAFFH8GAAIiAAMJvhSTAwC3AAAiAAMJvhSTAwC3AAAuAAQKfxQAAyIACQnnGB8KADACACIACQnnGB8KADACAA0AAQkjEsODADsAAAAA.Sneaktee:BAAALgAECgMJBAABLgAECggJFwARAKgcAA==.',
Sp='Sparkmantle:BAAALgAECgYJBgAAAA==.Sparkydrac:BAAALgADCggJCQABLgAECgYJEQADAAAAAA==.Spectroce:BAAALgADCgMJAwAAAA==.Spunky:BAAALgAECgQJBgAAAA==.',
Sq='Squeaksune:BAAALgADCgcJCAAAAA==.Squiish:BAAALgAECgQJBAAAAA==.',
Sr='Srorcalot:BAAALgAECgQJBAABLgAECgkJBQADAAAAAA==.',
St='Steppedon:BAAALgAECgYJDgAAAA==.Stingerai:BAABLgAECn8ZAAIMAAcJoiA2EQAKAgAMAAcJoiA2EQAKAgABLgAECggJIwASAIAeAA==.Stingeret:BAAALgADCgMJAwABLgAECggJIwASAIAeAA==.Stingerge:BAAALgAECgMJBAABLgAECggJIwASAIAeAA==.Stormweaverr:BAAALgAFFAEJAQAAAA==.',
Su='Sunbeamer:BAAALgADCgcJEQAAAA==.Sureman:BAAALgADCgIJAgAAAA==.',
Sw='Sweezy:BAAALgADCgcJBwAAAA==.',
Sx='Sxldíer:BAAALgAECgQJBwAAAA==.',
Sy='Sylvesters:BAAALgADCgcJBwABLgAECgUJBgADAAAAAA==.Syzmic:BAAALgADCgQJBgAAAA==.',
Ta='Taellas:BAAALgADCgMJAwAAAA==.Taeyeuh:BAAALgADCgcJCwAAAA==.Taley:BAAALgADCgMJAwAAAA==.Tamb:BAAALgAECgYJEgAAAA==.Tankboy:BAAALgAECgcJCwAAAA==.Tarickjk:BAAALgAECgQJCAAAAA==.Taryn:BAAALgAECgUJBQABLgAECgYJBwADAAAAAA==.',
Te='Tedious:BAAALgAECgUJBQAAAA==.Teehuntee:BAAALgAECgMJAwABLgAECggJFwARAKgcAA==.Teepal:BAAALgAECgMJBAABLgAECggJFwARAKgcAA==.Tekraa:BAAALgAECgcJDQAAAA==.Tempist:BAAALgAECgYJDgAAAA==.Teribullduce:BAACLgAFFH8FAAIcAAIJLRioDADDAAAcAAIJLRioDADDAAAuAAQKfzsAAhwACQmkHSkDAGwCABwACQmkHSkDAGwCAAAA.Terscheckii:BAAALgAECgMJBAAAAA==.',
Th='Theslimer:BAAALgAECgYJCwAAAA==.Thesukuna:BAAALgAECgIJAgAAAA==.Thormor:BAACLgAFFH8aAAIJAAcJqiDeAABwAgAJAAcJqiDeAABwAgAuAAQKfy4ABAkACQk8JPkAAJoDAAkACQk8JPkAAJoDABMABwnoHiQWACwCABkABQmVHpo0AEUBAAAA.Thrä:BAAALgADCgEJAQAAAA==.Thuggerjr:BAABLgAECn8eAAIYAAgJFhS+JwCkAQAYAAgJFhS+JwCkAQAAAA==.Thunderlordx:BAAALgAECgEJAgAAAA==.Thænes:BAAALgAECgYJEwAAAA==.Thémis:BAAALgADCgIJAQAAAA==.',
Ti='Tiimmyy:BAAALgAECgEJAQAAAA==.Tikaanivorn:BAAALgADCgcJBAAAAA==.Tikitiki:BAAALgAECgYJDgAAAA==.Tildin:BAAALgAECgYJDgAAAA==.Tinyandcute:BAAALgADCgkJCQABLgAECgcJDgADAAAAAA==.Tiravana:BAAALgADCgEJAgAAAA==.',
To='Toohottohndl:BAAALgADCgMJAwAAAA==.Topson:BAAALgAFFAMJAwAAAA==.Tornok:BAAALgADCgEJAQAAAA==.Tots:BAAALgAECgEJAQAAAA==.Tottemdrop:BAAALgADCgQJBQABLgAECgYJCQADAAAAAA==.',
Tr='Trebuchet:BAAALgAECgYJBgAAAA==.Treefrog:BAAALgADCgkJDAAAAA==.Treeshine:BAAALgAECgcJAQAAAA==.',
Tu='Tuggins:BAAALgADCgkJEQAAAA==.Tusi:BAAALgADCgEJAQAAAA==.',
Ty='Tychondriuss:BAABLgAECn8WAAIEAAYJ0B8bKADFAQAEAAYJ0B8bKADFAQAAAA==.Tylar:BAAALgAECgEJAQAAAA==.Tyrgor:BAAALgAECgMJBgAAAA==.',
Ub='Ubeenbained:BAABLgAECn8aAAIPAAYJZw2+EwAPAQAPAAYJZw2+EwAPAQAAAA==.',
Un='Unlock:BAAALgAECgUJCAAAAA==.',
Ur='Urgmathron:BAAALgAECgUJCQAAAA==.Ursão:BAAALgADCgcJBwAAAA==.',
Va='Valkorión:BAAALgADCgkJCQAAAA==.Valorisa:BAACLgAFFH8QAAINAAQJoBJICwA0AQANAAQJoBJICwA0AQAuAAQKfyIAAg0ACAnSIpkCAL0CAA0ACAnSIpkCAL0CAAAA.Vargko:BAAALgADCgkJEwAAAA==.Vassik:BAAALgADCgUJBQAAAA==.Vaughan:BAAALgADCgcJCQAAAA==.Vaush:BAAALgADCgcJBwAAAA==.',
Vd='Vdr:BAAALgADCgEJAQAAAA==.',
Ve='Velantheron:BAAALgAECgEJAQAAAA==.Vezrx:BAAALgAECggJEQAAAA==.',
Vi='Vinsmoke:BAAALgAECgIJAgAAAA==.Vitanimm:BAAALgADCgIJAwAAAA==.Vitiate:BAAALgAECgYJBgAAAA==.',
Vo='Volcanoez:BAAALgAECgQJBAAAAA==.',
Vr='Vrezor:BAAALgAECgQJDAAAAA==.',
Vy='Vyolnc:BAAALgAECgQJCAAAAA==.Vyrexiona:BAABLgAECn8YAAMKAAcJ1RmBGAAMAgAKAAcJ1RmBGAAMAgALAAEJtwIPRgAdAAAAAA==.',
['Vë']='Vëssël:BAAALgAECgYJCwAAAA==.',
Wa='Warthelian:BAAALgADCgcJBwABLgAECgUJCQADAAAAAA==.',
Wi='Wigglethorn:BAABLgAECn8XAAIYAAgJ2hwmJQCSAgAYAAgJ2hwmJQCSAgAAAA==.Winchells:BAAALgAECgcJAQAAAA==.Winddy:BAAALgAECgYJEwAAAA==.Winrodan:BAAALgAECgYJBgAAAA==.',
Wo='Wokthisway:BAAALgAECgQJCAAAAA==.Wolpertinger:BAAALgADCgYJBgAAAA==.',
Wr='Wreck:BAAALgADCgYJBgABLgAECgEJEgADAAAAAA==.',
Wy='Wych:BAAALgAECgYJDgABLgAECgcJFgAHALcdAA==.',
Xi='Xinjun:BAAALgAECgQJCAAAAA==.',
Xl='Xlh:BAAALgAECgcJAwAAAA==.',
Xp='Xpaínzkilla:BAAALgADCgQJBAAAAA==.',
Xs='Xsslopgob:BAAALgAECgYJDgAAAA==.',
Xu='Xufoxpikmin:BAAALgADCgUJBAAAAA==.',
Ya='Yappor:BAAALgAECgYJBgAAAA==.',
Ye='Yekteniya:BAAALgAECgYJCAAAAA==.',
Yi='Yibbers:BAAALgADCgIJAgAAAA==.',
Yo='Yoohoomoo:BAAALgADCgcJEgAAAA==.',
Yu='Yuna:BAAALgAECgUJDAAAAA==.Yur:BAAALgADCgcJDAABLgAECgYJEAADAAAAAA==.Yutch:BAAALgAECgYJCgAAAA==.',
Za='Zabuccy:BAAALgAECgYJCAAAAA==.Zacalkan:BAAALgAECgIJBAAAAA==.Zakkydrakky:BAAALgAECgYJDwAAAA==.Zani:BAAALgADCgEJAQAAAA==.Zarashara:BAABLgAECn8bAAMXAAYJ9hZ7FgBMAQAXAAYJ9hZ7FgBMAQAVAAYJzgMGTADiAAAAAA==.',
Ze='Zelta:BAAALgADCgkJDwAAAA==.Zerise:BAAALgAECgUJCgAAAA==.',
Zo='Zolidus:BAAALgADCgcJBwAAAA==.Zonckpog:BAAALgAECgcJCgAAAA==.',
Zu='Zugforlife:BAAALgAECgUJBQABLgAFFAEJAQADAAAAAA==.Zulkren:BAAALgAECgUJDQAAAA==.Zulugangrene:BAABLgAECn8bAAIYAAcJNhHJQABHAQAYAAcJNhHJQABHAQAAAA==.Zun:BAAALgAECgcJCQAAAA==.',
['Zá']='Záyá:BAAALgADCgIJAgAAAA==.',
['Èz']='Èzili:BAAALgAECgYJCwAAAA==.',
['Ód']='Ódinnhunt:BAAALgADCgEJAQAAAA==.',
['Üd']='Üdderchaos:BAABLgAECn8ZAAMRAAgJQxRYVgDuAQARAAgJ/BJYVgDuAQAdAAUJrQz8BwDqAAAAAA==.',
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

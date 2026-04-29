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

local lookup = {'Shaman-Restoration','Hunter-Marksmanship','Unknown-Unknown','Mage-Frost','Warlock-Demonology','Evoker-Devastation','Shaman-Elemental','Mage-Arcane','DemonHunter-Havoc','DemonHunter-Devourer','DeathKnight-Unholy','Druid-Guardian','Priest-Holy','Warlock-Destruction','Monk-Mistweaver','Monk-Windwalker','Rogue-Subtlety','Monk-Brewmaster','Paladin-Retribution','Priest-Shadow','Hunter-BeastMastery','Priest-Discipline','Paladin-Protection','Paladin-Holy','Hunter-Survival','Druid-Feral','DemonHunter-Vengeance','Warrior-Protection','DeathKnight-Blood','Evoker-Augmentation','Shaman-Enhancement','DeathKnight-Frost',}
local provider = {region='US',realm='Gurubashi',name='US',type='weekly',zone=46,date='2026-04-24',data={Aa='Aadrisedh:BAAALgAECgYJBgAAAA==.Aaeryñ:BAAALgAECgcJBwAAAA==.Aaliyshaa:BAAALgAECgMJBAAAAA==.Aaramis:BAABLgAECn8VAAIBAAcJ8xCSOQCbAQABAAcJ8xCSOQCbAQAAAA==.',
Ab='Abandyn:BAAALgADCgcJCwAAAA==.',
Ad='Adrisehunt:BAAALgADCgQJBAAAAA==.',
Ae='Aegira:BAAALgADCgUJBgAAAA==.Aelira:BAAALgADCgkJCwAAAA==.Aendoril:BAAALgADCgkJCAAAAA==.',
Ag='Aggrodk:BAAALgADCgMJAwAAAA==.',
Ai='Aidoffhealer:BAAALgADCgYJEQAAAA==.',
Al='Alariah:BAAALgAECgQJBwAAAA==.Alaín:BAABLgAECn8eAAICAAgJrBZMAgC2AQACAAgJrBZMAgC2AQAAAA==.Aldoladre:BAAALgADCgYJBgABLgAECgYJCgADAAAAAA==.Aldoraline:BAAALgADCgIJAwAAAA==.Alegedly:BAAALgADCgcJBwAAAA==.Alicê:BAAALgADCgYJCQAAAA==.Alystair:BAAALgADCgQJCAABLgAECgYJDgADAAAAAA==.',
Am='Ambellina:BAAALgAECgQJBAAAAA==.Ampse:BAAALgAECgQJBAAAAA==.Amzy:BAAALgADCgYJCQAAAA==.',
An='Anaria:BAAALgAECgQJBAAAAA==.Angbu:BAAALgAECgQJCwAAAA==.Angelpika:BAAALgADCgEJAQAAAA==.',
Ap='Apinkninja:BAABLgAECn8UAAIEAAcJ/xgLdQDoAQAEAAcJ/xgLdQDoAQAAAA==.',
Ar='Aranyssa:BAAALgAECggJEwAAAA==.Arch:BAAALgAECgIJAgABLgAECggJIAAFADcjAA==.Arclock:BAAALgADCgcJBwAAAA==.Arconnai:BAAALgAFFAIJAwAAAA==.Ardur:BAAALgAECgEJAQAAAA==.Arruna:BAAALgAECgYJDAAAAA==.Artorìas:BAAALgADCgkJCwABLgAECgYJDgADAAAAAA==.',
As='Asham:BAAALgAECgUJCQAAAA==.Ashenbloom:BAAALgAECgUJBwAAAA==.Asiago:BAAALgAECggJEwAAAA==.Aspect:BAAALgAECgYJDgAAAA==.',
Au='Augmenter:BAAALgAECgIJAgAAAA==.Aureliah:BAAALgADCgcJBwAAAA==.Autable:BAAALgADCgcJDgAAAA==.',
Av='Avacúma:BAAALgAECgEJAQAAAA==.Avvalethra:BAABLgAECn8dAAICAAgJpw1YCADeAAACAAgJpw1YCADeAAAAAA==.',
Ax='Axane:BAAALgADCggJCgAAAA==.',
Ay='Ayekea:BAAALgAECgYJCgAAAA==.',
Az='Azenet:BAAALgAECgEJAQABLgAFFAUJDgAGAB4iAA==.',
['Aé']='Aélyrá:BAAALgAECgEJAQAAAA==.',
Ba='Bachshots:BAAALgAECggJCAAAAA==.Badassbich:BAAALgADCgEJAQAAAA==.Baggett:BAAALgAECgUJBgAAAA==.Bainey:BAAALgADCgIJAgABLgADCgYJCgADAAAAAA==.Bananataffy:BAAALgADCgQJBAAAAA==.Barackoshama:BAABLgAECn8WAAIHAAgJWhe8IwDyAQAHAAgJWhe8IwDyAQAAAA==.Barfdrinker:BAAALgAECgYJBwAAAA==.Barlaina:BAAALgADCgEJAQAAAA==.Basedween:BAAALgADCgYJCAAAAA==.Battlescars:BAAALgAECgYJDwAAAA==.Baw:BAABLgAECn8cAAMEAAgJaBihEwCkAQAEAAgJaBihEwCkAQAIAAMJFwmUFQBvAAAAAA==.',
Bd='Bdelp:BAABLgAECn8jAAIEAAkJBRIuCQAWAgAEAAkJBRIuCQAWAgAAAA==.',
Be='Bearlinwall:BAAALgAECgYJBwAAAA==.Befoul:BAAALgAECgQJBAAAAA==.Bellyz:BAAALgAECgYJBwAAAA==.Bernham:BAAALgADCgMJAwAAAA==.',
Bi='Bigcheifpoop:BAAALgAECgEJAQAAAA==.Bigskydh:BAAALgAECgYJCwAAAA==.Bigskymage:BAAALgAECgQJCQAAAA==.Bip:BAAALgADCgEJAQAAAA==.',
Bl='Blackrazor:BAAALgADCgIJAgAAAA==.Blacksburden:BAAALgAECgMJAwABLgAECgcJDwADAAAAAA==.Blackvalor:BAAALgADCgMJAwAAAA==.Blackwÿn:BAAALgAECgEJAQABLgAECgUJDAADAAAAAA==.Bladedozzer:BAAALgAECgIJAwAAAA==.Blindinglite:BAABLgAECn8bAAIJAAcJSiLMAgDbAQAJAAcJSiLMAgDbAQAAAA==.Blindtoast:BAAALgAECgEJAQAAAA==.Blkpriest:BAAALgAECgIJAgAAAA==.Bloodhaze:BAABLgAECn8ZAAIJAAgJfx4WCwCvAgAJAAgJfx4WCwCvAgAAAA==.Blorp:BAABLgAECn8jAAIKAAgJPx5QBgAWAgAKAAgJPx5QBgAWAgAAAA==.',
Bo='Bodizzle:BAAALgADCgkJFwAAAA==.Bonez:BAAALgADCgMJAwAAAA==.Boondoggle:BAAALgAECgMJAwAAAA==.Borestus:BAAALgAECgMJAwAAAA==.Bouldur:BAAALgAECgUJCQAAAA==.Bownystark:BAABLgAECn8eAAICAAcJCCIQFQCHAgACAAcJCCIQFQCHAgAAAA==.',
Br='Brieter:BAAALgAECgcJDAABLgAECggJEwADAAAAAA==.Brinar:BAAALgAECgQJCQAAAA==.Brokikobo:BAAALgADCgUJCQAAAA==.Broughston:BAAALgADCgMJAwAAAA==.Brutusx:BAAALgAECgUJCAAAAA==.',
Bu='Bullhockey:BAAALgAECgEJAQAAAA==.Bullshiftsal:BAAALgAECgQJEAAAAA==.',
Bw='Bwabwagon:BAAALgADCgcJBwAAAA==.',
Bx='Bxxberry:BAAALgADCggJDQAAAA==.',
Ca='Camipriest:BAAALgAECgEJAQAAAA==.Casstyelle:BAAALgAECgQJBAAAAA==.Catpizz:BAAALgADCgEJAQAAAA==.',
Ce='Celedael:BAAALgAECgQJCAABLgAECggJEwADAAAAAA==.',
Ch='Changed:BAAALgAECgIJAgAAAA==.Chauvinpack:BAAALgAECgcJBwAAAA==.Cheesus:BAAALgAECgQJBAABLgAECggJEwADAAAAAA==.Chicharon:BAAALgAECgQJBwAAAA==.Chickentacos:BAAALgADCgkJCAABLgAECgcJBwADAAAAAA==.Chipsnsalsa:BAAALgADCgEJAQABLgAECgcJBwADAAAAAA==.Chocoriffic:BAAALgAECgcJBwAAAA==.Chokoballs:BAAALgADCgcJBwABLgAECgcJGQALAPgSAA==.',
Cl='Clawmommy:BAAALgAECgMJAwAAAA==.',
Co='Cojobo:BAAALgADCgYJCQAAAA==.Coko:BAABLgAECn8iAAIMAAgJgB7EAABkAgAMAAgJgB7EAABkAgAAAA==.Coldbrewz:BAAALgAECgYJDwAAAA==.Condensation:BAAALgADCgEJAQAAAA==.',
Cr='Crackjones:BAAALgAECgIJAgAAAA==.Crazydave:BAABLgAECn8WAAINAAgJRhIlIwDMAQANAAgJRhIlIwDMAQAAAA==.Creemywitchu:BAAALgADCgEJAQABLgADCgcJBwADAAAAAA==.Crism:BAAALgAECgQJAwAAAA==.Crismggt:BAAALgAFFAEJAQAAAA==.Crismtg:BAAALgAECgQJBwAAAA==.Crispytank:BAAALgADCgcJCgAAAA==.Cryptìc:BAAALgADCgUJBQABLgAFFAUJCgAEACUYAA==.Cryptîc:BAACLgAFFH8KAAIEAAUJJRiRBAB+AQAEAAUJJRiRBAB+AQAuAAQKfycAAgQACAmUJSIBAAUDAAQACAmUJSIBAAUDAAAA.',
Cu='Cursadilla:BAAALgAECgQJCgAAAA==.',
Cy='Cylissari:BAAALgAECgYJBgAAAA==.',
Da='Daasstion:BAABLgAECn8UAAIEAAcJOhhbXwAdAgAEAAcJOhhbXwAdAgAAAA==.Dabbia:BAABLgAECn8bAAMOAAgJpRwJEwCzAQAFAAYJeBuKVwDBAQAOAAYJ5RoJEwCzAQAAAA==.Daedleus:BAAALgADCgQJBAAAAA==.Damented:BAAALgAECgQJBAABLgAECgQJBAADAAAAAA==.Darkaitsu:BAAALgAECgEJAQAAAA==.Dawnpaw:BAABLgAECn8YAAMPAAgJyhBpIgCiAQAPAAgJyhBpIgCiAQAQAAEJyBsMcABSAAAAAA==.',
De='Deathballz:BAABLgAECn8ZAAILAAcJ+BKWFABuAQALAAcJ+BKWFABuAQAAAA==.Deathsbreach:BAAALgAECgUJCwAAAA==.Deathtee:BAABLgAECn8UAAILAAcJsx5HRgAiAgALAAcJsx5HRgAiAgAAAA==.Deepwaters:BAAALgADCgcJDAAAAA==.Dekuslice:BAAALgAECgYJDwAAAA==.Delafant:BAAALgAECgUJCgAAAA==.Demencia:BAAALgADCgQJBAAAAA==.Demonclawx:BAAALgADCgcJCAAAAA==.Dephlorate:BAAALgADCgcJCAAAAA==.Derpyderp:BAAALgADCgcJCAABLgAECggJEgADAAAAAA==.Destroyah:BAAALgADCgUJBwABLgAECgcJEgADAAAAAA==.Devile:BAAALgADCgIJAgAAAA==.Devocate:BAAALgADCgYJBwAAAA==.',
Di='Dinkys:BAAALgADCgYJCwABLgAECgYJDwADAAAAAA==.Diogenist:BAAALgAECgIJAwAAAA==.Dirtypeasant:BAAALgADCgUJBQAAAA==.',
Dk='Dkballz:BAAALgAECgEJAQABLgAECgcJFQARAOMiAA==.',
Do='Doktardoodad:BAAALgADCgcJCwAAAA==.Doktarzen:BAAALgAECgMJBQAAAA==.Doktershokk:BAAALgADCgEJAgAAAA==.Donkel:BAAALgAECgEJAQAAAA==.Doomslayer:BAABLgAECn8WAAIKAAgJdQnsYgB4AQAKAAgJdQnsYgB4AQAAAA==.Doresearch:BAABLgAECn8aAAIHAAcJihYdBwCWAQAHAAcJihYdBwCWAQAAAA==.',
Dr='Drackani:BAAALgADCgYJBgAAAA==.Draenutt:BAAALgAECggJDQAAAA==.Dragontee:BAAALgADCgQJBAABLgAECgcJFAALALMeAA==.Drakarys:BAAALgAECgQJBQAAAA==.Drakex:BAAALgAECgUJBQAAAA==.Drengist:BAABLgAECn8ZAAISAAgJTBTXIgDrAQASAAgJTBTXIgDrAQAAAA==.Drexybear:BAAALgAECgYJEAAAAA==.Drezbi:BAAALgAECgMJBAAAAA==.Drpebbles:BAAALgAECgQJCAAAAA==.',
Du='Dulcineru:BAAALgADCgYJBwAAAA==.Dunbarth:BAABLgAECn8YAAITAAgJvQzgbQChAQATAAgJvQzgbQChAQAAAA==.Durzaman:BAAALgAECgYJDAAAAA==.',
['Dé']='Dévílyñ:BAAALgAECgYJDgAAAA==.',
['Dü']='Dük:BAABLgAECn8YAAMFAAcJexHEGABMAQAFAAYJIRLEGABMAQAOAAIJOw5DTACIAAAAAA==.',
Eg='Eggy:BAAALgAECgkJCQAAAA==.',
El='Eldraaqeyn:BAAALgADCgcJBwAAAA==.Elephant:BAAALgAECgQJCQAAAA==.Elkanàh:BAAALgAECgIJAgABLgAECggJJgANAAsfAA==.Elleynle:BAAALgAECgMJBwAAAA==.Elunara:BAAALgAFFAEJAgABLgAECggJEwADAAAAAA==.',
Em='Emhotep:BAAALgADCgMJAwAAAA==.',
En='Enazar:BAAALgADCgIJAgAAAA==.',
Er='Ericuh:BAAALgAECgYJDQAAAA==.',
Es='Essekk:BAACLgAFFH8IAAIEAAMJHg16LgD9AAAEAAMJHg16LgD9AAAuAAQKfysAAgQACQklH1cWACMDAAQACQklH1cWACMDAAAA.',
Eu='Euliana:BAAALgADCgUJBQAAAA==.',
Ev='Evokeeznutz:BAAALgAECgcJCQABLgAECgcJDAADAAAAAA==.',
Ex='Exesolo:BAAALgADCgYJBwAAAA==.',
Ey='Eyeshmesch:BAAALgADCgUJBQABLgADCgUJCAADAAAAAA==.',
['Eí']='Eír:BAAALgADCgYJBgABLgAECggJFwANAMwUAA==.',
Fa='Fairyholy:BAAALgADCgEJAQAAAA==.Famjam:BAAALgAECgUJBgAAAA==.Fao:BAAALgADCgMJAwAAAA==.Fastrialimas:BAAALgAECgEJBAAAAA==.Fatpo:BAABLgAECn8bAAMNAAgJzSC7BgDiAgANAAgJzSC7BgDiAgAUAAEJwRs5HABTAAAAAA==.Fayjhu:BAAALgAECgYJEQAAAA==.',
Fe='Ferbos:BAAALgAECgEJAQAAAA==.Feylock:BAABLgAECn8UAAIFAAcJ6xBOGQBJAQAFAAcJ6xBOGQBJAQAAAA==.',
Fi='Fiastrei:BAAALgADCgcJCQAAAA==.',
Fl='Flexo:BAAALgADCgQJBAAAAA==.',
Fo='Forheretogo:BAAALgADCgEJAQAAAA==.Foô:BAABLgAECn8jAAIRAAgJ2RxBEwB/AgARAAgJ2RxBEwB/AgAAAA==.',
Fr='Frigate:BAAALgAECgcJEQAAAA==.Frihgate:BAAALgAECgcJEQAAAA==.Frostbitten:BAAALgADCgYJBgAAAA==.Frostea:BAAALgADCgUJBgAAAA==.Frostmyface:BAAALgAECgUJDAAAAA==.Frozenbeard:BAAALgAECgcJBgAAAA==.',
Fu='Fugbug:BAAALgADCgYJBwAAAA==.Furcrazy:BAAALgAECgcJEAAAAA==.Furdreich:BAAALgADCgIJAgAAAA==.Furryoffury:BAAALgADCgYJBgAAAA==.Furynagger:BAAALgADCgEJAQAAAA==.Furyosia:BAAALgADCgEJAQAAAA==.Furyrosa:BAAALgADCgQJBAAAAA==.Fuzi:BAAALgADCgUJBQABLgADCgUJCAADAAAAAA==.',
Fy='Fyafya:BAAALgADCgEJAQAAAA==.Fyah:BAAALgAECggJDgABLgAFFAQJDAAVAEQVAA==.Fyaza:BAAALgAECgEJAQAAAA==.',
Ga='Gargamels:BAAALgADCggJDgABLgAECgkJBAADAAAAAA==.Gariantel:BAAALgADCggJDgAAAA==.Garou:BAAALgAECgMJBQAAAA==.',
Ge='Geekylock:BAAALgAECgMJAwAAAA==.Genesis:BAAALgAECgkJAgAAAA==.Geobloom:BAAALgADCgUJBgAAAA==.Gerbic:BAAALgAECgEJAQAAAA==.Germ:BAAALgAECgMJAwAAAA==.Gerttie:BAAALgAECgMJAwAAAA==.',
Gh='Ghosted:BAAALgAECgMJBQAAAA==.',
Gi='Gilgalador:BAAALgADCgMJAwAAAA==.Gingdrac:BAAALgADCgcJDgABLgAFFAYJFQAWAH8dAA==.Givepenance:BAAALgADCgcJFAAAAA==.',
Go='Gomdagarm:BAAALgADCgUJBQAAAA==.Gopwal:BAAALgAECgYJBgAAAA==.Gorehammer:BAABLgAECn8aAAILAAgJ1BOIUAAAAgALAAgJ1BOIUAAAAgAAAA==.',
Gr='Gravediger:BAAALgAECgQJBAAAAA==.Gravepaws:BAAALgADCgIJAgAAAA==.Greatfatherx:BAAALgADCgEJAQAAAA==.Gridxx:BAAALgADCgUJBQAAAA==.Grievex:BAABLgAECn8dAAITAAgJpAVNHABEAQATAAgJpAVNHABEAQAAAA==.Grimbeorn:BAAALgADCgEJAQAAAA==.',
['Gî']='Gîgâbussy:BAAALgADCgIJAgAAAA==.',
Ha='Hairybear:BAAALgADCgYJBgAAAA==.Hanazawa:BAAALgADCgEJAQAAAA==.Hanyu:BAAALgADCgMJAwAAAA==.Hazykeety:BAAALgADCgEJAQAAAA==.',
He='Healsonwheel:BAAALgAECgcJCgAAAA==.Healthiss:BAAALgAECgEJAQAAAA==.Helaziri:BAAALgAECgYJEQAAAA==.Hemolock:BAAALgAECgYJEwABLgAFFAMJCQATAJcYAA==.Hemostasis:BAACLgAFFH8JAAITAAMJlxibCQD/AAATAAMJlxibCQD/AAAuAAQKfx8ABBMABwkqI5kwAGACABMABwkqI5kwAGACABcAAQn4DecSADQAABgAAQnCAOShACUAAAAA.Herjä:BAABLgAECn8XAAMNAAgJzBTGJQC8AQANAAgJixHGJQC8AQAWAAYJrRNfJQBpAQAAAA==.',
Hi='Hinkles:BAAALgAECgYJDwAAAA==.',
Ho='Hoocha:BAAALgADCgYJBgABLgAECgcJDAADAAAAAA==.Hoollymollyy:BAAALgADCgMJBAAAAA==.Hornsly:BAAALgADCgMJAwAAAA==.',
Hu='Huntingpoo:BAAALgAECgYJEgAAAA==.Huntweak:BAAALgAECgIJAgAAAA==.Huun:BAABLgAECn8WAAIZAAcJqBmmDAABAgAZAAcJqBmmDAABAgAAAA==.',
Hy='Hyasynthia:BAAALgAECgIJAQAAAA==.',
Ia='Iamnsfw:BAAALgAECgcJEgAAAA==.',
Il='Illydan:BAAALgAECgUJBwAAAA==.Ilvisarxiln:BAAALgADCgUJBQAAAA==.',
Im='Imataquito:BAABLgAECn8mAAIEAAgJGiE9BAB5AgAEAAgJGiE9BAB5AgAAAA==.',
In='Indigø:BAAALgAECgMJBAAAAA==.Inepsy:BAAALgAECgEJAQAAAA==.Infelicity:BAAALgADCgYJCQAAAA==.Infortunii:BAAALgADCgYJBgABLgAECgUJBQADAAAAAA==.',
Ir='Irezufortips:BAAALgADCgcJBwABLgAECgkJBAADAAAAAA==.Ironhide:BAAALgAECgIJAgAAAA==.Irrenadro:BAABLgAECn8VAAITAAgJJQ69fQB+AQATAAgJJQ69fQB+AQAAAA==.Irvainee:BAAALgAECgYJCwAAAA==.',
It='Itsp:BAAALgAECgUJBQAAAA==.',
Ja='Jadechaos:BAAALgAECgEJAQAAAA==.Jahkazul:BAAALgADCgYJDAAAAA==.Jarnabas:BAAALgAECgIJAgAAAA==.Jayec:BAAALgAECgEJAQAAAA==.',
Ji='Jingleparts:BAAALgADCggJCQABLgAECgcJBwADAAAAAA==.',
Jo='Joes:BAAALgAECgUJDQAAAA==.Jonesy:BAAALgAECgUJCwAAAA==.Jorath:BAAALgADCgQJBAABLgAECgkJBAADAAAAAA==.',
Ju='Juicygossip:BAAALgADCgkJEwAAAA==.Jujupowa:BAAALgAECgYJCAAAAA==.Junebug:BAAALgAECgQJBQAAAA==.',
['Jö']='Jöe:BAAALgAECgEJAQAAAA==.',
Ka='Kagal:BAABLgAECn8VAAIZAAcJfhJrDwDNAQAZAAcJfhJrDwDNAQAAAA==.Kaidan:BAABLgAECn8YAAIVAAgJ9RC1MwDgAQAVAAgJ9RC1MwDgAQAAAA==.Kaipriest:BAAALgADCgIJAgAAAA==.Kaladinn:BAAALgADCgEJAQAAAA==.Kaledra:BAAALgADCgYJBgAAAA==.Kalyke:BAAALgADCggJDQAAAA==.Kamikazejoe:BAAALgADCgEJAQAAAA==.Kargian:BAAALgAECgEJAQAAAA==.Kasumirenn:BAAALgAECgMJAwABLgAECggJGwAJAFUkAA==.Katanya:BAAALgAECgYJBgABLgAECggJEwADAAAAAA==.Katarinabluu:BAAALgADCgYJBgAAAA==.',
Ke='Keetra:BAABLgAFFH8FAAIVAAMJEwrOCAD7AAAVAAMJEwrOCAD7AAAAAA==.Keiriline:BAAALgAECgYJDgAAAA==.Keledorimash:BAAALgADCgYJCAAAAA==.Keva:BAAALgAECgUJDAAAAA==.Keyboard:BAAALgADCgIJAQAAAA==.Kez:BAAALgAECgUJBQAAAA==.',
Kh='Khaalian:BAAALgAECgIJAwAAAA==.',
Ki='Killbreed:BAABLgAECn8XAAIaAAgJGR4/BADdAgAaAAgJGR4/BADdAgAAAA==.Kinkster:BAAALgAECgMJAwAAAA==.Kirinani:BAAALgADCgcJCQAAAA==.Kirzan:BAAALgADCgMJAwAAAA==.Kizaruu:BAAALgADCgEJAQAAAA==.',
Kn='Knifeprty:BAAALgADCgUJBgAAAA==.Knuggz:BAAALgAECgYJDQAAAA==.',
Ko='Kolduna:BAAALgADCgUJBQAAAA==.Koshmare:BAAALgADCgUJBQAAAA==.Kozanazure:BAAALgADCggJDAAAAA==.',
Ku='Kurthalan:BAAALgAECgQJCAAAAA==.Kuumaneko:BAABLgAECn8XAAMFAAgJThQDDgCjAQAFAAgJThQDDgCjAQAOAAYJrwcNMQD1AAAAAA==.',
Ky='Kyarita:BAAALgAECgIJAgAAAA==.Kyballion:BAAALgAECgYJDwAAAA==.Kyledh:BAACLgAFFH8KAAIKAAMJKhoqGQAGAQAKAAMJKhoqGQAGAQAuAAQKfzUAAwoACQndI/QAAOkCAAoACQndI/QAAOkCABsAAQluIf8jAGIAAAAA.Kynyine:BAAALgADCgcJCAAAAA==.',
La='Laerosia:BAAALgADCgUJBQAAAA==.Landridan:BAAALgADCgUJBQAAAA==.Lanthin:BAAALgADCgYJCgAAAA==.Larzoh:BAABLgAECn8YAAMJAAgJ9COjAwBGAwAJAAgJ9COjAwBGAwAKAAEJgxgs5QAtAAAAAA==.',
Le='Lee:BAAALgADCgUJBQABLgAECgcJIgALAAciAA==.Legadiaus:BAAALgAECgEJAQAAAA==.Lemonheads:BAABLgAECn8bAAMWAAYJ7xM1IgCCAQAWAAYJ7xM1IgCCAQAUAAEJ4QEdagAjAAAAAA==.Lethargy:BAAALgAECgQJBAAAAA==.',
Li='Liaenara:BAAALgADCgQJCQAAAA==.Lidorila:BAAALgADCgUJBgAAAA==.Lightpallyzz:BAAALgADCgEJAQAAAA==.Lilin:BAAALgADCgUJCAAAAA==.Lilwiz:BAAALgADCgcJEwAAAA==.Lindre:BAAALgADCgQJBAAAAA==.Lishp:BAAALgADCgMJAwAAAA==.Littleiceice:BAAALgADCgEJAQAAAA==.',
Ll='Llemonz:BAAALgAECgEJAQAAAA==.',
Lo='Lockaf:BAAALgADCgUJBQABLgAECgUJBgADAAAAAA==.Lohki:BAAALgADCgEJAQAAAA==.Lonelyroad:BAAALgADCgMJAwAAAA==.Lostsausage:BAAALgAECgQJBgABLgAECgYJEwADAAAAAA==.Lothaire:BAAALgADCgEJAQAAAA==.Lothiet:BAAALgAECgYJCwABLgAECgcJEgADAAAAAA==.',
Lu='Luayhanui:BAAALgADCgEJAQAAAA==.Lugeya:BAAALgADCgYJBgAAAA==.Lustpls:BAAALgAECgQJBAABLgAECgYJBwADAAAAAA==.Luyoun:BAAALgADCgEJAQABLgAECgYJBwADAAAAAA==.',
Ly='Lyncha:BAAALgADCgcJDgABLgAECggJHAAXACshAA==.Lynchà:BAABLgAECn8cAAIXAAgJKyEaAQBEAgAXAAgJKyEaAQBEAgAAAA==.',
Ma='Maakun:BAABLgAECn8dAAQNAAcJ3gxaOwBNAQANAAcJ2gdaOwBNAQAUAAUJ8wcJQAD2AAAWAAQJHg2fOgDTAAAAAA==.Maddiebaby:BAAALgAECgQJCAAAAA==.Mageapoug:BAAALgADCgcJBwABLgAECggJEQADAAAAAA==.Magmalance:BAAALgAECgIJAgABLgAECgUJCwADAAAAAA==.Mahzad:BAABLgAECn8eAAIBAAYJqyJCGABUAgABAAYJqyJCGABUAgAAAA==.Maladi:BAAALgADCgkJCQAAAA==.Malfrun:BAAALgAECgYJDAAAAA==.Marinnite:BAAALgADCgYJDQAAAA==.Marox:BAAALgAECggJEAAAAA==.Marshmellows:BAAALgAECgYJBgAAAA==.Mastolus:BAAALgADCgEJAQAAAA==.Mathesi:BAAALgADCgYJCQAAAA==.Mathrim:BAABLgAECn8gAAMFAAgJNyNTFQDWAgAFAAcJNyNTFQDWAgAOAAEJAADNVQBtAAAAAA==.Matooka:BAAALgAECgYJDgAAAA==.Maynji:BAAALgADCgUJCAAAAA==.Mayushi:BAAALgAECgYJBwAAAA==.',
Me='Meencurry:BAABLgAECn8XAAIEAAYJHhXjmgCfAQAEAAYJHhXjmgCfAQAAAA==.Megozugzug:BAAALgAECgIJAgABLgAECgUJBQADAAAAAA==.Meyneth:BAAALgAECgEJAQAAAA==.',
Mi='Mikaì:BAAALgAECggJEQAAAA==.Mikehawkener:BAAALgAECgEJAQAAAA==.Misleading:BAAALgADCgMJBAAAAA==.Misotofu:BAAALgADCgcJCgAAAA==.Mistfisting:BAAALgAFFAIJAgAAAA==.',
Mo='Moderato:BAAALgAECgYJCwAAAA==.Moelleri:BAAALgAECgYJEQAAAA==.Mojowarlock:BAAALgADCgYJBgABLgAECgQJCAADAAAAAA==.Monkgroom:BAABLgAECn8dAAMPAAkJnBT1FgALAgAPAAkJnBT1FgALAgAQAAYJ8QrQOQA2AQAAAA==.Monsignor:BAAALgAECgEJAgAAAA==.Montra:BAABLgAECn8hAAMMAAkJfRogBQCOAgAMAAkJfRogBQCOAgAaAAUJAgn6HgDrAAAAAA==.Moreilira:BAAALgAECgQJBQAAAA==.Mornshield:BAABLgAECn8UAAMTAAYJWxSmkQBZAQATAAYJIxCmkQBZAQAXAAUJUxMCJgDZAAABLgAECgkJBAADAAAAAA==.Morphien:BAAALgADCgcJCQAAAA==.Mortaveus:BAAALgAECgEJAQAAAA==.Motto:BAAALgAECgEJAQAAAA==.Mouse:BAAALgADCgMJAwAAAA==.',
Mu='Muddgore:BAAALgAECgcJEgAAAA==.Muddthir:BAAALgADCgQJBAABLgAECgcJEgADAAAAAA==.Murkyblaizin:BAAALgAECgYJDQAAAA==.Mustardheals:BAAALgAECgUJCgAAAA==.',
My='Myharanir:BAAALgADCgUJBQAAAA==.Mypanda:BAAALgADCgkJDQAAAA==.Mythaera:BAAALgAECgQJCAABLgAECggJFwATANocAA==.',
Na='Nazrra:BAABLgAECn8YAAIcAAgJfRViEAADAgAcAAgJfRViEAADAgAAAA==.Nazugrax:BAAALgAECgQJBAAAAA==.',
Ne='Neebsz:BAAALgADCgYJEgAAAA==.Nemene:BAAALgADCgUJBQAAAA==.Neolithic:BAAALgAECgcJBAAAAA==.Nerdeficent:BAAALgADCgQJBAAAAA==.Nestaah:BAAALgAFFAEJAQAAAA==.Nettra:BAAALgAECgIJBAAAAA==.Newtdru:BAAALgADCgUJBQAAAA==.',
Ni='Nickparker:BAAALgADCggJCAAAAA==.Nininbrew:BAAALgADCgMJAwAAAA==.Nirath:BAABLgAECn8YAAIEAAYJigz9LgAOAQAEAAYJigz9LgAOAQAAAA==.',
No='Nobainer:BAAALgADCgYJCgAAAA==.Noed:BAAALgAECgMJAwAAAA==.Nohkano:BAABLgAECn8YAAISAAgJGiJ+BgAfAwASAAgJGiJ+BgAfAwAAAA==.Nokinkshame:BAAALgADCggJCQABLgAECgcJBwADAAAAAA==.Noobymonk:BAAALgAECgUJBgAAAA==.Noralise:BAAALgAECgQJBAAAAA==.Northerndk:BAAALgAECgUJCgAAAA==.Notsxldier:BAAALgADCgQJBAAAAA==.Novàstar:BAAALgADCgMJBgAAAA==.',
Nu='Numbuh:BAAALgAECgEJAgAAAA==.',
Ny='Nyxariaw:BAAALgADCggJDAAAAA==.Nyxmaris:BAAALgADCgYJBAAAAA==.',
['Nø']='Nøvâ:BAABLgAECn8fAAIEAAgJVhTJbAD8AQAEAAgJVhTJbAD8AQAAAA==.',
Oc='Octavarium:BAAALgAECgYJEwAAAA==.',
Od='Odinsmage:BAAALgADCgUJBgAAAA==.',
Oe='Oennomaus:BAAALgADCgEJAQABLgAECgQJCAADAAAAAA==.',
On='Oneshothel:BAAALgAECgQJBAAAAA==.Onran:BAAALgADCgUJBQABLgAECggJFwATANocAA==.',
Or='Orcpeon:BAAALgADCgYJBgABLgAECggJFgATAMMbAA==.Oryndern:BAAALgAECgMJBwAAAA==.',
Ot='Otokunu:BAAALgADCgIJAgAAAA==.',
Ov='Ovenmitts:BAAALgAECgYJEgABLgAECgcJBwADAAAAAA==.',
Oz='Ozwalds:BAAALgADCgQJBAAAAA==.',
Pa='Paeonagos:BAAALgADCgMJAwAAAA==.Palimpsest:BAAALgADCgEJAQAAAA==.Pallymans:BAAALgADCgUJBQAAAA==.Pantheons:BAAALgADCgEJAQAAAA==.Parsi:BAAALgAECgQJBAAAAA==.Pawtism:BAAALgADCgcJBgAAAA==.',
Pe='Penut:BAAALgAECgEJAQAAAA==.Perritax:BAAALgAECgcJDwAAAA==.',
Ph='Phialkit:BAAALgADCgcJBwAAAA==.Phoebelyria:BAAALgAECgQJBgAAAA==.Phêo:BAAALgAECgMJAwABLgAECgYJCgADAAAAAA==.',
Pi='Piffiny:BAAALgAECgYJBwAAAA==.Pine:BAAALgAECgIJAgAAAA==.Pingdoo:BAAALgAECgEJAQAAAA==.',
Po='Polis:BAABLgAECn8WAAITAAcJwxtcQgAdAgATAAcJwxtcQgAdAgAAAA==.Pomol:BAAALgAECgYJDAAAAA==.Potent:BAABLgAECn8VAAMLAAYJXQ4VJgD9AAALAAYJXQ4VJgD9AAAdAAQJbQaLOgBvAAAAAA==.Pougadina:BAAALgAECgIJAgABLgAECggJGwANAM0gAA==.',
Pr='Prislo:BAAALgADCgMJAwAAAA==.Prodie:BAAALgADCgMJBAAAAA==.Protect:BAAALgADCgMJAwAAAA==.Présage:BAAALgAECgQJCgAAAA==.',
Ps='Pswar:BAAALgAECgEJAQAAAA==.',
Pu='Puriel:BAAALgADCgMJAwAAAA==.',
Pw='Pwnstar:BAAALgAECgMJAwAAAA==.',
Py='Pyrojoe:BAAALgAECgYJCgABLgAECgkJBAADAAAAAA==.',
['Pò']='Pò:BAAALgAECgIJBAAAAA==.',
Ra='Ramsha:BAABLgAECn8VAAITAAYJWxZ8HQA9AQATAAYJWxZ8HQA9AQAAAA==.Ramshunter:BAABLgAECn8VAAMVAAkJJB1eBwAaAwAVAAkJJB1eBwAaAwACAAEJCgrziwAvAAAAAA==.Randyvivaldi:BAAALgADCgEJAQAAAA==.Rashanda:BAAALgADCgMJAwAAAA==.Rathasas:BAAALgADCggJCAAAAA==.Ratnob:BAABLgAECn8dAAILAAgJoRT7DAC3AQALAAgJoRT7DAC3AQAAAA==.Ravnaar:BAAALgAECggJDAAAAA==.Razamatazz:BAAALgADCgEJAQAAAA==.',
Re='Reddemon:BAAALgAECgEJAQABLgAECgcJDwADAAAAAA==.Relda:BAAALgAECgYJCQAAAA==.Renae:BAAALgAECgkJCAAAAA==.Renaud:BAAALgAECgQJBAAAAA==.Rennshi:BAABLgAECn8bAAIJAAgJVSQHBAA7AwAJAAgJVSQHBAA7AwAAAA==.Retpally:BAABLgAFFH8NAAIcAAQJrxHxAQA6AQAcAAQJrxHxAQA6AQAAAA==.Rezmee:BAAALgAECgUJCwAAAA==.',
Rh='Rheaf:BAAALgAECgYJBwAAAA==.',
Ri='Riastrad:BAAALgADCgUJBwAAAA==.Richie:BAABLgAECn8UAAIEAAYJoxD2NQDuAAAEAAYJoxD2NQDuAAAAAA==.Ringsofsatrn:BAAALgADCgEJAQAAAA==.Ripgoose:BAAALgADCggJEwAAAA==.',
Ro='Rolanthas:BAAALgADCgcJCQAAAA==.Rosario:BAABLgAECn8kAAMCAAgJnyGPDQDXAgACAAgJnyGPDQDXAgAZAAMJ1RmdCQAIAQAAAA==.',
Ry='Ryotwar:BAAALgAECgEJAQAAAA==.Rythmatic:BAABLgAECn8VAAIRAAcJ4yIQAwD3AQARAAcJ4yIQAwD3AQAAAA==.Ryvenox:BAAALgADCgcJBwAAAA==.',
Sa='Sabil:BAAALgADCgYJBgAAAA==.Saccharine:BAABLgAECn8fAAMWAAgJ3xfLAgAqAgAWAAgJ3xfLAgAqAgAUAAEJdAAEbQAHAAAAAA==.Sakieri:BAABLgAECn8dAAIUAAgJfxmTAgAoAgAUAAgJfxmTAgAoAgAAAA==.Samedi:BAAALgAECgQJBAAAAA==.Sangan:BAAALgAECgQJBwAAAA==.Sanguini:BAABLgAECn8VAAIEAAgJOBEgHwBaAQAEAAgJOBEgHwBaAQAAAA==.Sathari:BAAALgAECgIJAgAAAA==.',
Sc='Scrappycoco:BAAALgADCgQJBAAAAA==.Scye:BAAALgAECgIJAgAAAA==.',
Se='Seamanhunter:BAAALgADCgEJAQAAAA==.Seanoevil:BAAALgAECgUJBQAAAA==.Selaris:BAAALgAECgMJBgAAAA==.Selathviala:BAAALgADCgEJAgAAAA==.Sephares:BAAALgADCgUJBQAAAA==.Serazal:BAACLgAFFH8OAAMGAAUJHiLEAQCDAQAGAAQJJxvEAQCDAQAeAAMJ4xq4GACgAAAuAAQKfycAAx4ACQmzIokAAOcCAAYACAlJI8IBAC8DAB4ACAk3I4kAAOcCAAAA.',
Sh='Shadowblitzx:BAAALgAECgUJDwAAAA==.Shadowfall:BAAALgADCgkJEQAAAA==.Shaggin:BAAALgADCgMJAwAAAA==.Shamfoo:BAAALgADCggJCAABLgAECggJIwARANkcAA==.Sharana:BAAALgADCggJCAAAAA==.Shhrekk:BAAALgAECgIJAgAAAA==.Shikendagoon:BAAALgADCgcJCwAAAA==.Shinøbu:BAAALgADCgYJDAAAAA==.Shirrazaha:BAAALgADCgMJAwAAAA==.Shortbejo:BAAALgADCgQJBgAAAA==.Shâzzam:BAAALgAECgYJBgABLgAECgcJEgADAAAAAA==.',
Si='Silaris:BAAALgADCgMJBQAAAA==.Sinath:BAAALgAECgYJCgAAAA==.Singren:BAAALgADCgEJAQAAAA==.Sinnur:BAAALgAECgQJBAAAAA==.',
Sk='Skeezer:BAAALgAECgcJDAAAAA==.',
Sl='Sleeveless:BAAALgAECgcJDQAAAA==.Slizzie:BAAALgADCgkJFAAAAA==.Slowteeth:BAAALgADCgMJAwAAAA==.',
Sm='Smarfus:BAAALgAECgYJCAABLgAECgcJDwADAAAAAA==.Smilingp:BAAALgADCgcJBwAAAA==.Smiteznhealz:BAAALgADCgEJAQAAAA==.Smursh:BAAALgAECgQJBAAAAA==.',
Sn='Snakesabbath:BAAALgAECgUJCAAAAA==.Snarge:BAABLgAECn8UAAMfAAkJARkfCgAwAgAfAAkJARkfCgAwAgAHAAEJIxKugwA7AAAAAA==.Sneaktee:BAAALgAECgMJBAABLgAECgcJFAALALMeAA==.',
Sp='Sparkmantle:BAAALgAECgYJBgAAAA==.Spectroce:BAAALgADCgMJAwAAAA==.Spunky:BAAALgAECgQJBgAAAA==.',
Sq='Squeaksune:BAAALgADCgcJBwAAAA==.Squiish:BAAALgADCggJCAAAAA==.',
Sr='Srorcalot:BAAALgADCgYJBgABLgAECgkJBAADAAAAAA==.',
St='Steppedon:BAAALgAECgYJCgAAAA==.Stingerai:BAABLgAECn8XAAIVAAYJmCBcCwC1AQAVAAYJmCBcCwC1AQABLgAECggJIgAMAIAeAA==.Stingeret:BAAALgADCgMJAwABLgAECggJIgAMAIAeAA==.Stingerge:BAAALgAECgMJBAABLgAECggJIgAMAIAeAA==.Stormweaverr:BAAALgAECgcJDwAAAA==.',
Su='Sunbeamer:BAAALgADCgcJEQAAAA==.',
Sw='Sweezy:BAAALgADCgcJBwAAAA==.',
Sx='Sxldíer:BAAALgAECgQJBwAAAA==.',
Sy='Sylvesters:BAAALgADCgcJBwABLgAECgUJBgADAAAAAA==.Syzmic:BAAALgADCgQJBgAAAA==.',
Ta='Taellas:BAAALgADCgMJAwAAAA==.Taeyeuh:BAAALgADCgcJCwAAAA==.Taley:BAAALgADCgMJAwAAAA==.Tamb:BAAALgAECgYJEAAAAA==.Tankboy:BAAALgAECgcJCwAAAA==.Tarickjk:BAAALgAECgQJCAAAAA==.Taryn:BAAALgAECgUJBQABLgAECgYJBwADAAAAAA==.',
Te='Teehuntee:BAAALgADCgUJBQABLgAECgcJFAALALMeAA==.Teepal:BAAALgADCgUJBQABLgAECgcJFAALALMeAA==.Tekraa:BAAALgAECgcJDQAAAA==.Tempist:BAAALgAECgQJCAAAAA==.Teribullduce:BAABLgAECn84AAIZAAkJpB3WAwDkAgAZAAkJpB3WAwDkAgAAAA==.Terscheckii:BAAALgAECgMJBAAAAA==.',
Th='Theslimer:BAAALgAECgUJCQAAAA==.Thesukuna:BAAALgAECgEJAQAAAA==.Thormor:BAACLgAFFH8VAAIWAAYJfx2kAQAhAgAWAAYJfx2kAQAhAgAuAAQKfy4ABBYACQk8JPcAAJoDABYACQk8JPcAAJoDAA0ABwnoHh0WACwCABQABQmVHo80AEUBAAAA.Thrä:BAAALgADCgEJAQAAAA==.Thuggerjr:BAAALgAFFAEJAQAAAA==.Thunderlordx:BAAALgAECgEJAgAAAA==.Thænes:BAAALgAECgUJDAAAAA==.Thémis:BAAALgADCgIJAQAAAA==.',
Ti='Tiimmyy:BAAALgADCgMJAwAAAA==.Tikaanivorn:BAAALgADCgcJBAAAAA==.Tikitiki:BAAALgAECgYJDgAAAA==.Tildin:BAAALgAECgYJDgAAAA==.Tinyandcute:BAAALgADCgkJCQABLgAECgcJBwADAAAAAA==.',
To='Toohottohndl:BAAALgADCgMJAwAAAA==.Topson:BAAALgAFFAMJAwAAAA==.Tornok:BAAALgADCgEJAQAAAA==.Tots:BAAALgAECgEJAQAAAA==.Tottemdrop:BAAALgADCgQJBQABLgAECgQJBAADAAAAAA==.',
Tr='Trebuchet:BAAALgAECgYJBgAAAA==.Treefrog:BAAALgADCgQJBAAAAA==.Treeshine:BAAALgAECgcJAQAAAA==.',
Tu='Tuggins:BAAALgADCgkJEQAAAA==.Tusi:BAAALgADCgEJAQAAAA==.',
Ty='Tychondriuss:BAAALgAECgYJEAAAAA==.Tylar:BAAALgAECgEJAQAAAA==.Tyrgor:BAAALgAECgMJBQAAAA==.',
Ub='Ubeenbained:BAAALgAECgYJDwAAAA==.',
Un='Unlock:BAAALgADCgcJDAAAAA==.',
Ur='Urgmathron:BAAALgAECgQJBAAAAA==.Ursão:BAAALgADCgcJBwAAAA==.',
Va='Valkorión:BAAALgADCgkJCQAAAA==.Valorisa:BAACLgAFFH8IAAIHAAQJrwyFDAAlAQAHAAQJrwyFDAAlAQAuAAQKfyEAAgcACAnHIsYAALYCAAcACAnHIsYAALYCAAAA.Vargko:BAAALgADCgkJEwAAAA==.Vassik:BAAALgADCgUJBQAAAA==.Vaughan:BAAALgADCgcJCQAAAA==.Vaush:BAAALgADCgcJBgAAAA==.',
Ve='Velantheron:BAAALgAECgEJAQAAAA==.Vezrx:BAAALgAECgYJBgAAAA==.',
Vi='Vinsmoke:BAAALgAECgEJAQAAAA==.Vitanimm:BAAALgADCgEJAgAAAA==.Vitiate:BAAALgADCgYJBgAAAA==.',
Vo='Volcanoez:BAAALgADCgQJBQAAAA==.',
Vr='Vrezor:BAAALgAECgQJCAAAAA==.',
Vy='Vyolnc:BAAALgAECgQJBAAAAA==.Vyrexiona:BAABLgAECn8YAAMeAAcJ1Rl+GAANAgAeAAcJ1Rl+GAANAgAGAAEJtwIGRgAdAAAAAA==.',
['Vë']='Vëssël:BAAALgAECgYJCwAAAA==.',
Wa='Warthelian:BAAALgADCgcJBwABLgAECgQJBAADAAAAAA==.',
Wi='Wigglethorn:BAABLgAECn8XAAITAAgJ2hwsJQCSAgATAAgJ2hwsJQCSAgAAAA==.Winchells:BAAALgAECgcJAQAAAA==.Winddy:BAAALgAECgYJEwAAAA==.Winrodan:BAAALgAECgQJBAAAAA==.',
Wo='Wokthisway:BAAALgADCgQJBAAAAA==.Wolpertinger:BAAALgADCgYJBgAAAA==.',
Wr='Wreck:BAAALgADCgYJBgABLgAECgEJDAADAAAAAA==.',
Wy='Wych:BAAALgAECgQJBwABLgAECgYJFQAOAEggAA==.',
Xi='Xinjun:BAAALgAECgQJCAAAAA==.',
Xl='Xlh:BAAALgAECgcJAwAAAA==.',
Xp='Xpaínzkilla:BAAALgADCgQJBAAAAA==.',
Xs='Xsslopgob:BAAALgAECgQJBwAAAA==.',
Xu='Xufoxpikmin:BAAALgADCgUJBAAAAA==.',
Ya='Yappor:BAAALgADCgkJCgAAAA==.',
Ye='Yekteniya:BAAALgAECgYJBwAAAA==.',
Yo='Yoohoomoo:BAAALgADCgcJEgAAAA==.',
Yu='Yuna:BAAALgAECgUJDAAAAA==.Yur:BAAALgADCgcJDAABLgAECgYJDgADAAAAAA==.Yutch:BAAALgAECgYJCgAAAA==.',
Za='Zabuccy:BAAALgAECgYJCAAAAA==.Zacalkan:BAAALgAECgEJAgAAAA==.Zakkydrakky:BAAALgAECgYJDwAAAA==.Zarashara:BAABLgAECn8UAAMSAAYJ9hYGDwABAQASAAYJ9hYGDwABAQAQAAYJzgMKTADiAAAAAA==.',
Ze='Zelta:BAAALgADCgkJDwAAAA==.Zerise:BAAALgAECgUJCgAAAA==.',
Zo='Zonckpog:BAAALgAECgcJCgAAAA==.',
Zu='Zugforlife:BAAALgAECgUJBQABLgAECgUJBQADAAAAAA==.Zulkren:BAAALgAECgUJDQAAAA==.Zulugangrene:BAABLgAECn8YAAITAAYJcBB5lgBQAQATAAYJcBB5lgBQAQAAAA==.Zun:BAAALgAECgcJCQAAAA==.',
['Zá']='Záyá:BAAALgADCgIJAgAAAA==.',
['Èz']='Èzili:BAAALgAECgYJBgAAAA==.',
['Ód']='Ódinnhunt:BAAALgADCgEJAQAAAA==.',
['Üd']='Üdderchaos:BAABLgAECn8ZAAMLAAgJQxRdVgDuAQALAAgJ/BJdVgDuAQAgAAUJrQwGBAD1AAAAAA==.',
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

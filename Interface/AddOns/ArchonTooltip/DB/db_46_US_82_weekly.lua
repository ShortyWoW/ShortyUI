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

local lookup = {'Warlock-Demonology','Warlock-Destruction','Unknown-Unknown','Rogue-Subtlety','Hunter-Marksmanship','Shaman-Enhancement','Druid-Balance','Mage-Frost','DeathKnight-Unholy','DeathKnight-Frost','Hunter-BeastMastery','Shaman-Restoration','Rogue-Assassination','DemonHunter-Devourer','Paladin-Retribution','Hunter-Survival','Warrior-Fury','Druid-Feral','Priest-Holy','Monk-Windwalker','Monk-Brewmaster','Monk-Mistweaver','Priest-Discipline','Evoker-Augmentation','Shaman-Elemental','DeathKnight-Blood','DemonHunter-Vengeance','Mage-Arcane','Paladin-Protection','Paladin-Holy','DemonHunter-Havoc','Druid-Restoration','Druid-Guardian',}
local provider = {region='US',realm='Duskwood',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Abominasven:BAAALgADCgkJFQAAAA==.',
Ad='Adhira:BAAALgADCgUJBwAAAA==.',
Ae='Aedrias:BAAALgAECgYJCwAAAA==.Aegennai:BAAALgAECgQJBwAAAA==.Aegon:BAECLgAFFH8LAAIBAAQJpRr+DAALAQABAAQJpRr+DAALAQAuAAQKfx0AAwEACQn9HzwGABACAAEABgkfITwGABACAAIAAwmUHL8pABsBAAAA.Aeli:BAAALgADCgQJBAABLgAECgYJCwADAAAAAA==.Aethelios:BAAALgAECgEJAQAAAA==.Aevaela:BAABLgAECn8cAAIEAAgJBhaHAwDhAQAEAAgJBhaHAwDhAQAAAA==.',
Ag='Agilaz:BAABLgAECn8UAAIFAAYJuROeBQAoAQAFAAYJuROeBQAoAQAAAA==.Aguas:BAAALgAECgMJBQAAAA==.',
Ak='Akey:BAAALgAECgEJAQAAAQ==.Akhae:BAAALgAECggJEQAAAA==.',
Al='Albinism:BAABLgAECn8UAAIGAAYJwQ1UBgAmAQAGAAYJwQ1UBgAmAQAAAA==.Alcadeias:BAAALgAECgYJEQAAAA==.Alexandros:BAAALgADCgIJAgAAAA==.Allastor:BAAALgADCggJFgAAAA==.Alupindat:BAABLgAECn8dAAIHAAgJkRdNHgANAgAHAAgJkRdNHgANAgAAAA==.',
Am='Amehnet:BAAALgAECgEJAQAAAA==.Amuria:BAAALgADCgQJBAAAAA==.',
An='Anaeda:BAAALgAECgcJEgAAAA==.Angryjim:BAAALgADCgMJAgAAAA==.Angusmcduck:BAAALgADCgUJBQAAAA==.Anubisre:BAAALgAECgEJAgAAAA==.',
Ap='Apparèntly:BAAALgAECgIJAgABLgAECgYJCwADAAAAAA==.',
Aq='Aquindra:BAAALgADCggJDQAAAA==.',
Ar='Arccane:BAAALgAECgMJBQAAAA==.',
As='Ashvyth:BAAALgAECgYJDgAAAA==.Asmodeus:BAAALgADCgUJBQAAAA==.',
Aw='Awwyeah:BAAALgADCggJEAABLgAFFAMJCgAIAE4NAA==.',
Ba='Baeyik:BAAALgADCggJDgAAAA==.Baldrr:BAAALgADCgcJEgAAAA==.Barnabus:BAAALgAECgEJAgAAAA==.',
Be='Beachbecrazy:BAAALgAECgEJAgABLgAECgYJDgADAAAAAA==.Bearforce:BAAALgAECgYJCwAAAA==.Beastlypläyä:BAAALgADCgUJCgAAAA==.Beiral:BAAALgADCgkJEAAAAA==.Berey:BAAALgADCgEJAgABLgAECggJDwADAAAAAA==.',
Bi='Bigblingaxe:BAAALgADCgkJHgAAAA==.Billymayss:BAAALgADCgUJBQAAAA==.Bimbosuzi:BAAALgADCgYJCQAAAA==.',
Bl='Blacksabbth:BAAALgADCgMJBQAAAA==.Blindhealz:BAAALgAECgcJEAAAAA==.Blinkzy:BAAALgAECgIJAgAAAA==.',
Bo='Bonerblast:BAAALgAECgIJAgAAAA==.Boston:BAABLgAECn8cAAMJAAcJIiTzBgASAgAJAAcJIiTzBgASAgAKAAEJAACbCgAAAAAAAA==.',
Br='Brewtholomew:BAABLgAECn8YAAILAAcJbRBJEQB0AQALAAcJbRBJEQB0AQAAAA==.Briggsey:BAAALgAECgYJDAAAAA==.Briznot:BAAALgAECgQJBwAAAA==.Brounies:BAAALgAECgcJEgAAAA==.Bryce:BAAALgAECgUJDAAAAA==.Brèanna:BAAALgADCggJDwAAAA==.',
Bu='Bubbachi:BAAALgAECgYJCwAAAA==.Bubbadubya:BAAALgADCgcJBQAAAA==.Bucciarati:BAAALgADCgYJBgAAAA==.Buray:BAAALgADCgEJAQAAAA==.Burningwolf:BAABLgAECn8dAAIMAAgJ7x59CgDUAgAMAAgJ7x59CgDUAgAAAA==.Burr:BAAALgAECgcJBwAAAA==.Bushmomma:BAAALgAECgQJDwAAAA==.',
['Bâ']='Bâbygirl:BAAALgAECgYJDgAAAA==.',
Ca='Caitlyn:BAAALgAECgQJBgAAAA==.Caleesia:BAAALgADCgcJCQAAAA==.Camdingo:BAAALgAECgcJCwAAAA==.Carnìfex:BAAALgAECgYJDwAAAA==.Caskaerta:BAAALgADCgcJBwAAAA==.Catbrin:BAAALgAECgUJDAAAAA==.',
Ce='Celáena:BAABLgAECn8YAAINAAcJ5QutCgCGAQANAAcJ5QutCgCGAQAAAA==.Cerà:BAAALgADCgEJAQAAAA==.',
Ch='Champkind:BAAALgAECgMJAwAAAA==.Chapslop:BAAALgADCgQJBAAAAA==.Charcoal:BAAALgAECgEJAQAAAA==.Cheetah:BAAALgADCgcJCAAAAA==.',
Cl='Cleos:BAAALgAECgIJAwAAAA==.Clobberben:BAAALgAECgQJBQAAAA==.Cloudbreaker:BAAALgADCgcJCAAAAA==.Cloudkeg:BAAALgADCggJDQAAAA==.',
Cr='Crunchyjim:BAAALgADCgMJAgAAAA==.',
Cu='Cuppicake:BAAALgADCgEJAQAAAA==.Cute:BAAALgADCgYJDgAAAA==.',
Cz='Cztalone:BAAALgAECgUJCQAAAA==.',
['Cè']='Cèlane:BAAALgAECgcJEwAAAA==.',
Da='Dadeeps:BAAALgAECgUJBQAAAA==.Damitsu:BAEBLgAECn8UAAMNAAYJtg8lDQBMAQAEAAYJwAx8MgB1AQANAAYJ0gwlDQBMAQAAAA==.Damnitsu:BAEALgADCgkJJQABLgAECgYJFAANALYPAA==.Darkcat:BAAALgAECgQJCwAAAA==.Darktrial:BAAALgADCgUJBQAAAA==.Darnaya:BAAALgADCgkJEQAAAA==.Datemike:BAAALgADCgEJAQAAAA==.Dazen:BAAALgADCggJGAAAAA==.',
De='Deadflexy:BAAALgAECgUJDAAAAA==.Deathberry:BAABLgAECn8bAAIBAAYJcB9AQQAJAgABAAYJcB9AQQAJAgAAAA==.Deathdoodles:BAAALgAECgYJDAAAAA==.Deathvoker:BAAALgAECgMJAwAAAA==.Deekan:BAAALgAECgYJCwAAAA==.Degrade:BAAALgADCgMJBgABLgADCgYJCwADAAAAAA==.Dejai:BAAALgADCgUJBQAAAA==.Dejavù:BAAALgAECgUJBgAAAA==.Demise:BAAALgADCgYJCQAAAA==.Demonb:BAAALgADCgUJBgAAAA==.Demonicmac:BAAALgADCgMJAwAAAA==.Derick:BAAALgAECgMJBgAAAA==.Deräth:BAAALgAECgUJBQAAAA==.Deviltrigger:BAAALgADCgcJCQABLgADCgkJEQADAAAAAA==.Devlik:BAAALgAECgEJAQAAAA==.',
Df='Dfresh:BAAALgAECgQJCwAAAA==.',
Di='Dinkalopogis:BAAALgADCgYJCAAAAA==.Ditsie:BAAALgADCgkJHAAAAA==.',
Do='Dobby:BAAALgAECgEJAQAAAA==.',
Dr='Dragondude:BAAALgAECgYJDQAAAA==.Druidhealer:BAAALgAECgEJAQAAAA==.Druidia:BAAALgAECgUJBQAAAA==.',
Du='Durango:BAAALgAECgYJDAAAAA==.',
Dy='Dyelin:BAAALgAECgYJDgAAAA==.',
Ee='Eephus:BAAALgAECgcJDwAAAA==.',
El='Elylle:BAAALgAECgEJAQAAAA==.Elyron:BAAALgAECgYJDgAAAA==.',
Em='Emovision:BAAALgAECgEJAQAAAA==.',
En='Ennoaleh:BAAALgADCggJFAAAAA==.',
Et='Ethelwulf:BAAALgADCgYJCwAAAA==.Etheri:BAAALgADCgYJBgAAAA==.',
Ev='Evilorc:BAAALgADCgUJBQAAAA==.Eviltoo:BAAALgADCgEJAQAAAA==.Evozker:BAAALgADCgEJAQAAAA==.Evêlyn:BAAALgADCgQJBAAAAA==.',
Ex='Exerphus:BAAALgAECgUJCAAAAA==.',
Ez='Ezren:BAAALgADCgMJAwAAAA==.',
Fa='Faedove:BAAALgADCgEJAQAAAA==.Fakename:BAAALgAECgYJDgAAAA==.Fakesaint:BAABLgAECn8aAAIMAAcJQR0gBQAVAgAMAAcJQR0gBQAVAgAAAA==.Fangstorm:BAAALgAECgYJDAAAAA==.Farorê:BAAALgAECgMJAwAAAA==.',
Fe='Felbane:BAABLgAECn8YAAIOAAcJExXNFgBIAQAOAAcJExXNFgBIAQAAAA==.Felpally:BAAALgAECgIJAgAAAA==.',
Fl='Fleekjuice:BAAALgADCgcJCgAAAA==.Flexecute:BAAALgAECgcJEAAAAA==.Fluffyangel:BAAALgAECgQJBAAAAA==.',
Fu='Fujimoto:BAAALgADCgMJAwAAAA==.Furpunch:BAAALgADCgcJBwAAAA==.',
Ga='Galaxzia:BAAALgAECgEJAQAAAA==.Gallivia:BAAALgAECgMJBAAAAA==.',
Ge='Gehn:BAAALgAECgEJAQAAAA==.',
Gh='Ghostprodigy:BAAALgADCgcJBwAAAA==.',
Gi='Gideòn:BAAALgAECgUJCAAAAA==.Ginzi:BAAALgAECgYJEgAAAA==.',
Gl='Glard:BAAALgADCgcJBwAAAA==.',
Go='Gonto:BAAALgADCgYJBgAAAA==.Gopao:BAAALgADCgYJBgABLgAECgUJDAADAAAAAA==.',
Gr='Graxus:BAAALgADCgkJIAAAAA==.Greatchez:BAAALgAECgUJBwAAAA==.Greth:BAAALgADCgYJBwAAAA==.Gronky:BAAALgAECgIJAgAAAA==.',
Gu='Gudge:BAAALgAECgYJEQAAAA==.Gummypenguin:BAABLgAECn8VAAMLAAgJGhqeTACDAQALAAcJiBmeTACDAQAFAAYJTQy1VQDyAAAAAA==.',
Ha='Hadhox:BAAALgAECgYJDQAAAA==.Hakano:BAAALgAECgUJCAAAAA==.Hathdox:BAAALgAECgMJAwABLgAECgYJDQADAAAAAA==.Hawkulees:BAAALgADCgcJBQAAAA==.Hazelnoot:BAABLgAECn8XAAIPAAYJ1BrSHgA2AQAPAAYJ1BrSHgA2AQAAAA==.Haûnt:BAAALgADCgMJAwAAAA==.',
He='Hexcist:BAAALgAECgYJDQAAAA==.',
Hi='Hitsuryu:BAAALgAECgUJDAAAAA==.',
Ho='Hollyanne:BAAALgAECgYJCwAAAA==.Holyfawn:BAAALgADCgEJAQABLgADCgYJBgADAAAAAA==.Holystrike:BAAALgAECgMJBAAAAA==.Hoonicorn:BAAALgAECgIJAwABLgADCgUJCgADAAAAAA==.Hornsnap:BAAALgAECgYJEQAAAA==.',
Hu='Hunalli:BAAALgAECgUJBQABLgAECgYJEQADAAAAAA==.Hunterb:BAAALgADCgkJCQAAAA==.',
Hy='Hydropump:BAAALgADCgYJBgAAAA==.Hyst:BAABLgAECn8rAAQQAAgJEyZtAAC6AgAFAAgJwyWgAwBpAwAQAAgJSCFtAAC6AgALAAIJhCVPkwCyAAAAAA==.',
Ic='Iconius:BAAALgADCggJGAAAAA==.',
Ie='Ieatsomeshoe:BAAALgAECgYJBgAAAA==.Ieatsomesock:BAAALgADCgYJBwAAAA==.Ieatwetsocks:BAAALgAECgYJDwAAAA==.',
Il='Illuminatie:BAAALgAECgEJAgAAAA==.',
In='Insaint:BAABLgAECn8gAAIPAAcJexZBXADOAQAPAAcJexZBXADOAQAAAA==.',
Is='Isabellë:BAAALgAECgUJCgAAAA==.Isadorra:BAAALgADCgYJBgAAAA==.Iskandar:BAAALgADCgMJAwAAAA==.',
Ja='Jaker:BAAALgADCgEJAQAAAA==.Jalu:BAAALgAECgQJCQAAAA==.Jatia:BAAALgADCgEJAQABLgAECggJIAARAO4fAA==.',
Je='Jessamine:BAABLgAECn8YAAIIAAcJFxVbGACDAQAIAAcJFxVbGACDAQAAAA==.Jessicafelba:BAAALgAECgUJDAAAAA==.Jetta:BAABLgAECn8UAAISAAYJTRB/BQAsAQASAAYJTRB/BQAsAQAAAA==.Jezzak:BAAALgAECgYJEgABLgAECggJFgALADUWAA==.',
Jo='Jorien:BAABLgAECn8eAAILAAgJoxUQEACAAQALAAgJoxUQEACAAQAAAA==.',
Jp='Jp:BAAALgAECgEJAQAAAA==.Jps:BAAALgADCgUJBQABLgAECgEJAQADAAAAAA==.',
Ka='Kaboonski:BAAALgADCgUJBQAAAA==.Kaboonsky:BAABLgAECn8WAAITAAgJdRZAGAAaAgATAAgJdRZAGAAaAgAAAA==.Kabvoker:BAAALgADCgUJBQAAAA==.Kamikori:BAAALgAECgUJCwAAAA==.Kardels:BAAALgAECgQJBgAAAA==.Karnn:BAACLgAFFH8GAAMUAAMJQRYvBwAEAQAUAAMJQRYvBwAEAQAVAAEJHQFIKgArAAAuAAQKfx0AAxQABwmNIY8KAM8CABQABwmNIY8KAM8CABYAAQnIAcV0AB0AAAAA.',
Ke='Keho:BAAALgAECgEJAQAAAA==.',
Ki='Kiplet:BAAALgAECgYJEQAAAA==.',
Ko='Korxon:BAABLgAECn8UAAMXAAcJPBQsGQDQAQAXAAcJPBQsGQDQAQATAAQJDg4AWgDMAAAAAA==.Kotus:BAAALgAECgEJAQAAAA==.',
Kr='Krazz:BAAALgADCgYJBgABLgAECgUJDAADAAAAAA==.',
Ks='Ksyusha:BAAALgAECgEJAQAAAA==.',
['Kä']='Kämi:BAAALgADCgYJCwABLgAECgYJEwADAAAAAA==.',
La='Lahabrea:BAABLgAECn8XAAMCAAYJ9Q/vKwAPAQACAAYJ2w3vKwAPAQABAAYJYwxKJAAHAQAAAA==.Lanuadra:BAAALgADCgYJBgABLgAECggJFAAYAPkaAA==.Lasagne:BAAALgAECgMJBQAAAA==.Lawry:BAAALgAECgUJBQAAAA==.',
Le='Leeara:BAAALgAECggJDwAAAA==.Legitpoopoo:BAAALgAECgUJBQABLgAECgcJGgAIAA8aAA==.Lethalbimbo:BAAALgADCggJDwAAAA==.',
Li='Liammairi:BAAALgAECgEJAQAAAA==.Lillié:BAAALgAECgMJAwAAAA==.Lilpeep:BAAALgADCgMJAwAAAA==.Lilysham:BAACLgAFFH8MAAIMAAUJthFgAQCfAQAMAAUJthFgAQCfAQAuAAQKfxwAAwwACAlSIVUQAJUCAAwABwmSIFUQAJUCABkAAQnnERSFADcAAAAA.Linddrel:BAAALgAECgYJCQAAAA==.',
Lo='Lomea:BAAALgAECgQJBQAAAA==.Lonristyn:BAAALgADCgYJCgAAAA==.',
['Lø']='Løllîe:BAAALgAECgEJAQAAAA==.Løllïe:BAAALgADCgYJDAABLgAECgEJAQADAAAAAA==.',
Ma='Magatai:BAAALgAECgMJAwAAAA==.Malenrhen:BAAALgADCgkJFgAAAA==.Mandhos:BAAALgADCgIJAgAAAA==.Martlok:BAABLgAECn8UAAMJAAYJaRkkGgBEAQAJAAYJXRckGgBEAQAKAAIJEBbWFABGAAAAAA==.Matalue:BAAALgAECgYJDAAAAA==.',
Mc='Mcbrynhammer:BAAALgADCgYJEQAAAA==.',
Mi='Micflinigan:BAAALgAECgYJEQAAAA==.Minmo:BAAALgADCgUJBQABLgAECgYJEQADAAAAAA==.Misahaviran:BAAALgADCgQJBAAAAA==.Mishelö:BAAALgADCgEJAQAAAA==.',
Mo='Moduur:BAAALgAECgYJCgAAAA==.Moonshae:BAABLgAECn8YAAIWAAcJJBM1BwCSAQAWAAcJJBM1BwCSAQAAAA==.Mooshata:BAAALgAECgQJBAAAAA==.Morninghunt:BAAALgADCgEJAQABLgAECggJHQAHAJEXAA==.Mornings:BAAALgAECgYJDQABLgAECggJHQAHAJEXAA==.Mouse:BAAALgAECgQJCAAAAA==.Moze:BAAALgADCgMJAwAAAA==.',
Mu='Murf:BAAALgADCgMJAwAAAA==.',
My='Mystiquè:BAAALgADCgYJCAAAAA==.',
Na='Naboo:BAAALgADCgIJAgABLgAECgYJDAADAAAAAA==.Nails:BAAALgAECgUJDAAAAA==.Naithin:BAAALgAECgIJAgAAAA==.Nalarah:BAAALgAECgEJAQAAAA==.Naviriel:BAAALgADCgYJBgABLgAECgUJDAADAAAAAA==.',
Ni='Nightdragon:BAAALgADCgQJBAAAAA==.',
No='Noknik:BAAALgADCgMJAwAAAA==.Nootloops:BAAALgADCgcJCgABLgAECgYJFwAPANQaAA==.Noriisa:BAABLgAECn8WAAILAAgJNRaXIABBAgALAAgJNRaXIABBAgAAAA==.Noudders:BAAALgAECgcJDwAAAA==.',
Od='Odinhand:BAABLgAECn8YAAIHAAcJ2wnfDQATAQAHAAcJ2wnfDQATAQAAAA==.',
Ol='Oliissa:BAAALgADCgcJCAAAAA==.',
Or='Oregar:BAAALgADCgYJBgAAAA==.',
Ou='Ouch:BAAALgADCgEJAQAAAA==.',
Oz='Ozwäld:BAAALgAECggJDwAAAA==.',
Pa='Paladinb:BAAALgADCgYJBgAAAA==.Pandapí:BAAALgADCgcJDQAAAA==.Panduh:BAACLgAFFH8PAAIIAAUJjw9/DQCvAQAIAAUJjw9/DQCvAQAuAAQKfyUAAggACAkaIroaAAwDAAgACAkaIroaAAwDAAAA.Pandóra:BAAALgAECgMJBQAAAA==.Pariousa:BAABLgAECn8rAAMNAAgJAyYjAADrAgAEAAgJlSVIAwBrAwANAAgJ9CMjAADrAgAAAA==.',
Pe='Perceval:BAAALgAECgYJCgAAAA==.Pewpewboo:BAACLgAFFH8KAAIIAAMJTg3/LgD6AAAIAAMJTg3/LgD6AAAuAAQKfyYAAggACAkvHbszAKQCAAgACAkvHbszAKQCAAAA.',
Pi='Pigeonhole:BAAALgADCgYJBgABLgAECgQJBAADAAAAAA==.Pinkeepink:BAAALgAECgMJAwAAAA==.',
Pl='Plates:BAAALgAECgIJAgAAAA==.',
Pr='Pray:BAAALgADCgYJBgAAAA==.',
Qu='Quarantina:BAAALgAECgIJAQAAAA==.',
Ra='Ragnor:BAAALgADCgQJBAAAAA==.Ralganor:BAABLgAECn8YAAIaAAcJOR5UAwC/AQAaAAcJOR5UAwC/AQAAAA==.Ramanash:BAAALgADCgUJDAAAAA==.Ravenstrider:BAAALgAECgYJCwAAAA==.Raylerya:BAAALgADCgYJCQAAAA==.Raylish:BAAALgAECgYJBgAAAA==.',
Re='Ren:BAAALgADCgIJAgAAAA==.',
Rh='Rhm:BAAALgAECgEJAQAAAA==.Rhylen:BAAALgADCgYJCQABLgAECgUJDAADAAAAAA==.',
Ri='Rina:BAACLgAFFH8LAAIbAAQJsxrgAAA7AQAbAAQJsxrgAAA7AQAuAAQKfx0AAhsACAlPIBUCAOoCABsACAlPIBUCAOoCAAAA.Rineli:BAAALgAECgYJCwAAAA==.Ringadingg:BAABLgAECn8VAAIJAAgJAh3gGADnAgAJAAgJAh3gGADnAgAAAA==.Riniching:BAAALgAECgEJAQABLgAECggJFQAJAAIdAA==.',
Ro='Roastduck:BAAALgAECgYJDAAAAA==.Rosequartz:BAAALgADCgUJBQAAAA==.Rosetas:BAAALgADCggJCAAAAA==.',
Ru='Runeytoon:BAAALgAECgUJBgAAAA==.',
Sa='Sacamano:BAAALgADCggJEAAAAA==.Sarazah:BAABLgAECn8oAAIPAAgJkSUfAQDaAgAPAAgJkSUfAQDaAgAAAA==.',
Sc='Scony:BAAALgAECgMJAwAAAA==.Scribs:BAAALgADCgkJCQAAAA==.',
Sd='Sdiybt:BAABLgAECn8aAAMIAAcJDxpGFgCRAQAIAAYJ4hxGFgCRAQAcAAQJ8hcPDAARAQAAAA==.',
Se='Selysse:BAAALgAECgUJCQAAAA==.Sephi:BAAALgAECgEJAQAAAA==.Seramis:BAAALgADCgkJHAAAAA==.Servis:BAAALgADCgYJBgAAAA==.Setharoth:BAAALgAECgEJAgAAAA==.Severalforms:BAAALgADCgIJAgABLgAECggJHQAPAP8bAA==.Severànce:BAAALgADCgQJBAABLgAECggJHQAPAP8bAA==.Sevotion:BAABLgAECn8dAAQPAAgJ/xsvNgBKAgAPAAgJABovNgBKAgAdAAUJgRElLQClAAAeAAIJGg9SgQBzAAAAAA==.',
Sh='Shablammy:BAAALgAECgUJDAAAAA==.Shadownome:BAAALgADCggJFQAAAA==.Shadowolves:BAAALgADCgQJBAAAAA==.Shanker:BAAALgAECgEJAQAAAA==.Shaolinchii:BAAALgADCgkJEAAAAA==.Shayden:BAAALgAECgIJAgAAAA==.Shinkickerr:BAAALgADCgYJBgAAAA==.Shirø:BAAALgADCgIJAgAAAA==.Shizamthebam:BAAALgAECgQJBAAAAA==.Shäzu:BAAALgADCgEJAQAAAA==.',
Si='Sihtric:BAAALgADCggJDQAAAA==.Silvanosh:BAAALgAECggJCQAAAA==.Silverflame:BAAALgADCgkJEwAAAA==.Sinveil:BAABLgAECn8hAAMFAAgJCRfyKADfAQAFAAcJfRfyKADfAQALAAQJZBGjJgDQAAAAAA==.',
Sk='Skendr:BAAALgADCgYJCAAAAA==.Skullshadow:BAAALgADCgMJAwAAAA==.Skydragon:BAAALgADCgYJDgAAAA==.',
Sl='Slash:BAAALgADCgMJAwAAAA==.Sleepydwarf:BAAALgAECgEJAgAAAA==.',
Sm='Smerknd:BAAALgADCgUJCAAAAA==.',
Sp='Spiritly:BAAALgADCgcJDQAAAA==.Sprynt:BAAALgAECgMJAwAAAA==.',
St='Starmist:BAAALgADCgcJBgAAAA==.Stendo:BAAALgAECgMJAwABLgAFFAMJBgAfANEcAA==.Steviewonder:BAAALgAECgUJBgAAAA==.Stonemother:BAAALgAECgEJAQAAAA==.Stormbane:BAAALgAECgIJAgAAAA==.Stormcrest:BAAALgADCgkJFAAAAA==.Stormseer:BAAALgAECgIJAgABLgAECgIJAgADAAAAAA==.',
Su='Sunae:BAAALgADCgkJCQAAAA==.Sunn:BAAALgADCgYJBgABLgAECgUJDAADAAAAAA==.',
Sw='Sweèt:BAAALgAECgMJAwAAAA==.Swockwickdus:BAACLgAFFH8FAAIOAAIJmR9zIgC7AAAOAAIJmR9zIgC7AAAuAAQKfyYAAw4ACAn6Iy0BANcCAA4ACAlDIy0BANcCAB8AAwk/JUs/AP8AAAAA.Swooze:BAAALgADCgUJBQAAAA==.',
Ta='Tarouhorn:BAAALgAECgIJAwAAAA==.Taurasthunt:BAAALgAECgQJCAABLgAECgYJEQADAAAAAA==.Taurastrage:BAAALgAECgYJEQAAAA==.Taurenator:BAAALgADCgEJAwAAAA==.Taursroot:BAAALgADCgIJAgAAAA==.Taylorshift:BAAALgAECgYJDAAAAA==.Tazbeard:BAAALgADCgYJCQABLgAECgUJDAADAAAAAA==.',
Te='Teetau:BAAALgAECgYJDgAAAA==.',
Th='Thaddaios:BAAALgAECgEJAQABLgAECgcJDwADAAAAAA==.Thadregosa:BAAALgAECgcJDwAAAA==.Thander:BAAALgADCgMJAwABLgADCggJDQADAAAAAA==.Thannicus:BAAALgAECgUJBQAAAA==.Thedarkskull:BAAALgAECgEJAQAAAA==.',
Ti='Tibbotanical:BAABLgAECn8WAAIgAAcJOxgiQQCdAQAgAAcJOxgiQQCdAQAAAA==.Tiblessed:BAAALgADCgEJAQABLgAECgcJFgAgADsYAA==.Tiffy:BAAALgADCgYJEAAAAA==.Tintreach:BAAALgAECgQJBQAAAA==.Tirnotham:BAAALgAECgEJAQAAAA==.',
To='Tokalu:BAAALgAECgUJDAAAAA==.Tonjudsonson:BAACLgAFFH8IAAIhAAMJPRtPAgAEAQAhAAMJPRtPAgAEAQAuAAQKfyQAAiEACAnkJfYAAGQDACEACAnkJfYAAGQDAAAA.Tonopah:BAAALgAECgUJDAAAAA==.Toxix:BAAALgAECgYJDwAAAA==.',
Tr='Travesura:BAAALgADCgIJAgAAAA==.',
Ts='Tsu:BAAALgAECgQJBAAAAA==.',
Tw='Twiki:BAAALgAECgUJCQAAAA==.',
Ty='Tyrssana:BAAALgAECgEJAQABLgAECgcJGQAYACAVAA==.',
Ug='Uglykitten:BAAALgAECgYJEgAAAA==.',
Ur='Urdeadtoo:BAAALgAECgUJCgAAAA==.',
Va='Vaererelor:BAAALgAECgEJAgAAAA==.Vassiliki:BAAALgADCgYJCQAAAA==.Vaterunser:BAAALgAECgEJAQAAAA==.Vayleen:BAAALgADCgYJBgAAAA==.',
Ve='Verlynna:BAAALgADCgIJAwAAAA==.',
Vi='Vicky:BAAALgADCgYJCQABLgAECgQJBwADAAAAAA==.Vincenzo:BAACLgAFFH8FAAIUAAIJ5CRxBADPAAAUAAIJ5CRxBADPAAAuAAQKfxoAAhQACAk9I0QEAEgDABQACAk9I0QEAEgDAAAA.Vinhar:BAAALgADCgkJCQAAAA==.Vinlight:BAAALgAECgUJBQAAAA==.Vinsteam:BAAALgAECgYJDgAAAA==.Visea:BAAALgADCgUJBgAAAA==.',
Vl='Vlarett:BAAALgAECgMJBQAAAA==.',
Vo='Voidsavage:BAAALgADCggJDQAAAA==.Volic:BAAALgAECgYJDgAAAA==.',
Vu='Vulpixa:BAAALgADCgkJGgAAAA==.',
Wa='Waps:BAAALgAECgEJAQAAAA==.Warsyeaa:BAAALgADCgMJAwAAAA==.Watevr:BAEALgAECgYJBgABLgAECgYJFAANALYPAA==.',
We='Weeniehutjr:BAAALgADCgEJAQABLgAECgEJAQADAAAAAA==.Wesleypriest:BAABLgAECn8cAAMXAAgJrAmsBwByAQAXAAgJWQmsBwByAQATAAMJCwhhaQCHAAAAAA==.Wesleyswipes:BAAALgADCgEJAQAAAA==.',
Xa='Xalabro:BAAALgAECgUJDAAAAA==.Xarcus:BAAALgAECgEJAQABLgAECgYJFAAIAFUYAA==.',
Xe='Xeros:BAAALgADCgcJDAAAAA==.',
Xo='Xousa:BAAALgADCgYJCAABLgAECggJKwANAAMmAA==.',
Xy='Xylas:BAABLgAECn8UAAIIAAYJVRipjQC3AQAIAAYJVRipjQC3AQAAAA==.',
Ya='Yashe:BAAALgAECgYJDgAAAA==.',
Yi='Yinoa:BAAALgADCgUJBQABLgAECgcJFgARAJ0XAA==.',
Yo='Yokuni:BAAALgADCggJDgAAAA==.',
Yu='Yuefei:BAAALgADCgUJBQAAAA==.',
Za='Zakoor:BAAALgADCggJDwAAAA==.Zareena:BAAALgADCgMJAwAAAA==.Zarnia:BAAALgADCggJCwAAAA==.Zarrock:BAAALgADCggJCgAAAA==.Zaurra:BAAALgAECgYJCQAAAA==.',
Ze='Zebbyzebzeb:BAAALgADCgcJBwAAAA==.Zebrow:BAAALgADCgQJBgAAAA==.Zebzap:BAAALgADCgEJAQAAAA==.Zed:BAAALgADCgkJEgAAAA==.Zehorn:BAAALgAECgYJBgABLgAFFAUJDAAMALYRAA==.Zekia:BAAALgAECgEJAQAAAA==.Zerm:BAABLgAECn8gAAIPAAgJOhOWDgCzAQAPAAgJOhOWDgCzAQAAAA==.',
Zi='Zinnkura:BAAALgAECgEJAQAAAA==.Zizzix:BAAALgADCgYJCgAAAA==.',
Zo='Zorsa:BAAALgAECgMJAwAAAA==.',
Zu='Zulfrito:BAAALgAECgYJDgAAAA==.',
['Ñô']='Ñôg:BAAALgADCgcJCAAAAA==.',
['Ød']='Ødis:BAAALgADCgcJEQAAAA==.',
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

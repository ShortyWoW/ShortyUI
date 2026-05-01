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

local lookup = {'Warlock-Demonology','Warlock-Destruction','Unknown-Unknown','Rogue-Subtlety','Hunter-Marksmanship','Shaman-Restoration','Shaman-Enhancement','Paladin-Retribution','Druid-Balance','Monk-Brewmaster','Mage-Frost','DeathKnight-Unholy','DeathKnight-Frost','Hunter-BeastMastery','Evoker-Augmentation','Druid-Guardian','Warrior-Arms','Warrior-Fury','Rogue-Assassination','Shaman-Elemental','Evoker-Preservation','Mage-Arcane','DemonHunter-Devourer','Warrior-Protection','Hunter-Survival','Druid-Feral','Priest-Holy','Monk-Windwalker','Monk-Mistweaver','Priest-Discipline','DeathKnight-Blood','DemonHunter-Vengeance','Paladin-Protection','Paladin-Holy','DemonHunter-Havoc','Evoker-Devastation','Druid-Restoration',}
local provider = {region='US',realm='Duskwood',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abominasven:BAAALgADCgkJFQAAAA==.',
Ad='Adhira:BAAALgAECgMJAwAAAA==.',
Ae='Aedrias:BAAALgAECgYJEQAAAA==.Aegennai:BAAALgAECgYJDwAAAA==.Aegon:BAECLgAFFH8QAAIBAAUJRRu6FQBHAQABAAUJRRu6FQBHAQAuAAQKfx0AAwEACQn9H2sTAAkCAAEABgkfIWsTAAkCAAIAAwmUHMEpABsBAAAA.Aeli:BAAALgADCgQJBAABLgAECgYJEQADAAAAAA==.Aethelios:BAAALgAECgEJAQAAAA==.Aevaela:BAABLgAECn8kAAIEAAgJzxdVBwD9AQAEAAgJzxdVBwD9AQAAAA==.',
Ag='Agilaz:BAABLgAECn8bAAIFAAcJ9xf/BACyAQAFAAcJ9xf/BACyAQAAAA==.Aguas:BAAALgAECgMJBgAAAA==.',
Ak='Akey:BAAALgAECgMJBAAAAQ==.Akhae:BAABLgAECn8aAAIGAAgJKRgXFQDBAQAGAAgJKRgXFQDBAQAAAA==.',
Al='Albinism:BAABLgAECn8aAAIHAAYJ0g9FCgBBAQAHAAYJ0g9FCgBBAQAAAA==.Alcadeias:BAABLgAECn8XAAIIAAYJnxgwRAA9AQAIAAYJnxgwRAA9AQAAAA==.Alexandros:BAAALgADCgIJAgAAAA==.Allastor:BAAALgADCggJFgAAAA==.Alupindat:BAABLgAECn8hAAIJAAkJfhdLHgANAgAJAAkJfhdLHgANAgAAAA==.',
Am='Amehnet:BAAALgAECgYJBgAAAA==.Amuria:BAAALgADCgQJBAAAAA==.',
An='Anaeda:BAABLgAECn8UAAIIAAgJMAtorgAmAQAIAAgJMAtorgAmAQAAAA==.Angryjim:BAAALgADCgQJAwAAAA==.Angusmcduck:BAAALgADCgUJBQAAAA==.Anubisre:BAAALgAECgEJAwAAAA==.',
Ap='Apparèntly:BAAALgAECgIJAgABLgAECgYJEQADAAAAAA==.',
Aq='Aquindra:BAAALgADCggJDQAAAA==.',
Ar='Arccane:BAAALgAECgQJBgAAAA==.Arthar:BAAALgADCgYJBgAAAA==.',
As='Ashvyth:BAABLgAECn8VAAIKAAcJRRmnEACLAQAKAAcJRRmnEACLAQAAAA==.Asmodeus:BAAALgADCgUJBQAAAA==.',
Aw='Awwyeah:BAAALgADCggJEAABLgAFFAQJEgALAC8MAA==.',
Ba='Baeyik:BAAALgAFFAEJAQAAAA==.Baldrr:BAAALgADCgcJEgAAAA==.Balomdruid:BAAALgADCgYJBgAAAA==.Barnabus:BAAALgAECgEJAgAAAA==.',
Be='Beachbecrazy:BAAALgAECgMJBQABLgAECgcJFQAGANEbAA==.Bearforce:BAAALgAECgYJCwAAAA==.Beastcat:BAAALgADCgYJBgAAAA==.Beastlypläyä:BAAALgAECgEJAQAAAA==.Beiral:BAAALgADCgkJEAAAAA==.Berey:BAAALgADCgEJAgABLgAECggJFwALAHUgAA==.',
Bi='Bigblingaxe:BAAALgADCgkJJwAAAA==.Billymayss:BAAALgADCgUJBQAAAA==.Bimbosuzi:BAAALgADCgYJCQAAAA==.',
Bl='Blacksabbth:BAAALgADCgcJDAAAAA==.Blindhealz:BAAALgAECgcJEQAAAA==.Blinkzy:BAAALgAECgIJAgAAAA==.',
Bo='Bonerblast:BAAALgAECgIJAgAAAA==.Boston:BAABLgAECn8kAAMMAAgJriQgBgC+AgAMAAgJriQgBgC+AgANAAEJAACREwAAAAAAAA==.',
Br='Brewtholomew:BAABLgAECn8eAAIOAAgJGhEuHgCrAQAOAAgJGhEuHgCrAQAAAA==.Briggsey:BAABLgAECn8UAAIBAAYJAgmSVgDtAAABAAYJAgmSVgDtAAAAAA==.Briznot:BAAALgAECgUJDAAAAA==.Brounies:BAAALgAECgcJEgAAAA==.Bryce:BAAALgAECgUJEQAAAA==.Brèanna:BAAALgADCggJDwAAAA==.',
Bu='Bubbachi:BAAALgAECgYJCwAAAA==.Bubbadubya:BAAALgADCggJBQAAAA==.Bucciarati:BAAALgADCgYJBgAAAA==.Bunnyfu:BAAALgAECgUJBQABLgAECgcJGAAPAHURAA==.Buray:BAAALgADCgEJAQAAAA==.Burningwolf:BAABLgAECn8dAAIGAAgJ7x58CgDUAgAGAAgJ7x58CgDUAgAAAA==.Burr:BAAALgAECgcJBwAAAA==.Bushmomma:BAABLgAECn8UAAIQAAUJpRN1DgDRAAAQAAUJpRN1DgDRAAAAAA==.',
['Bâ']='Bâbygirl:BAABLgAECn8WAAIOAAYJEQVkVgDHAAAOAAYJEQVkVgDHAAAAAA==.',
Ca='Caitlyn:BAAALgAECgQJBgAAAA==.Caleesia:BAAALgADCggJCQAAAA==.Camdingo:BAAALgAECgcJCwAAAA==.Capthunder:BAAALgADCgYJDAAAAA==.Carnìfex:BAABLgAECn8VAAMRAAYJnBcPCQB0AQARAAYJnBcPCQB0AQASAAYJJA97VwBOAQAAAA==.Caskaerta:BAAALgAECgMJAwAAAA==.Catbrin:BAAALgAECgUJDAAAAA==.',
Ce='Celáena:BAABLgAECn8gAAITAAgJGwySBACMAQATAAgJGwySBACMAQAAAA==.Cerà:BAAALgADCgEJAQAAAA==.',
Ch='Champkind:BAAALgAECgMJAwAAAA==.Chapslop:BAAALgADCgQJBAAAAA==.Charcoal:BAAALgAECgEJAQAAAA==.Cheetah:BAAALgAECgIJAgAAAA==.',
Cl='Cleos:BAAALgAECgIJAwAAAA==.Clobberben:BAAALgAECgYJCwAAAA==.Cloudbreaker:BAAALgADCgcJCAAAAA==.Cloudkeg:BAAALgAECgMJAwAAAA==.',
Cr='Crunchyjim:BAAALgADCgMJAgAAAA==.',
Cu='Cuppicake:BAAALgADCgEJAQAAAA==.Cute:BAAALgADCgYJDgAAAA==.',
Cz='Cztalone:BAAALgAECgUJDgAAAA==.',
['Cè']='Cèlane:BAABLgAECn8WAAMUAAgJ0RlzKQDJAQAUAAcJfRpzKQDJAQAGAAIJDQr+UABeAAAAAA==.',
Da='Dadeeps:BAAALgAECgUJBQAAAA==.Damitsu:BAEBLgAECn8aAAMTAAYJtg8mDQBMAQATAAYJ0gwmDQBMAQAEAAYJBg3vFQAqAQAAAA==.Damnitsu:BAEALgAECgMJAwABLgAECgYJGgATALYPAA==.Darkcat:BAAALgAECgYJEwAAAA==.Darktrial:BAAALgADCgUJBQAAAA==.Darnaya:BAAALgADCgkJEQAAAA==.Datemike:BAAALgADCgEJAQAAAA==.Dazen:BAAALgAECgIJAgAAAA==.',
De='Deadflexy:BAAALgAECgUJEQAAAA==.Deathberry:BAABLgAECn8iAAIBAAcJCB49IACzAQABAAcJCB49IACzAQAAAA==.Deathdoodles:BAABLgAECn8UAAIMAAcJARQ4NQBkAQAMAAcJARQ4NQBkAQAAAA==.Deathvoker:BAAALgAECgMJAwAAAA==.Deekan:BAAALgAECgYJEAAAAA==.Degrade:BAAALgAECgMJAwAAAA==.Dejai:BAAALgADCgUJBQAAAA==.Dejavù:BAAALgAECgUJBgAAAA==.Demise:BAAALgADCgYJCQAAAA==.Demonb:BAAALgADCgUJBgAAAA==.Demonicmac:BAAALgADCgMJAwAAAA==.Derick:BAAALgAECgMJBgAAAA==.Deräth:BAAALgAECgYJCQAAAA==.Deviltrigger:BAAALgADCgcJCQABLgADCgkJEQADAAAAAA==.Devlik:BAAALgAECgEJAQAAAA==.',
Df='Dfresh:BAAALgAECgYJEwAAAA==.',
Di='Dinkalopogis:BAAALgADCggJCAAAAA==.Ditsie:BAAALgAECgEJAQAAAA==.Dizzyizzy:BAAALgAECgcJBwAAAA==.',
Do='Dobby:BAAALgAECgMJBAAAAA==.',
Dr='Dragondude:BAABLgAECn8UAAIVAAcJ0xrYBwCxAQAVAAcJ0xrYBwCxAQAAAA==.Druidhealer:BAAALgAECgEJAQAAAA==.Druidia:BAAALgAECgUJBwAAAA==.',
Du='Durango:BAAALgAECgcJEwAAAA==.',
Dy='Dyelin:BAABLgAECn8VAAMBAAcJshlcHwC5AQABAAcJshlcHwC5AQACAAIJyhN7SQCSAAAAAA==.',
Ea='Eagleballz:BAAALgADCgMJAwAAAA==.',
Ee='Eephus:BAABLgAECn8WAAMTAAcJahL8BAB+AQATAAcJahL8BAB+AQAEAAYJPAosOQBMAQAAAA==.',
El='Elylle:BAAALgAECgIJAwAAAA==.Elyron:BAABLgAECn8VAAMLAAcJiRYpNACUAQALAAcJiRYpNACUAQAWAAEJog+XHQA3AAAAAA==.',
Em='Emovision:BAAALgAECgEJAQAAAA==.',
En='Ennoaleh:BAAALgAECgIJAgAAAA==.',
Er='Erlandis:BAAALgADCgIJAgAAAA==.',
Et='Ethelwulf:BAAALgADCgYJCwABLgAECgMJAwADAAAAAA==.Etheri:BAAALgADCgYJBgAAAA==.',
Ev='Evilorc:BAAALgADCgUJAwAAAA==.Eviltoo:BAAALgADCgEJAQAAAA==.Evozker:BAAALgADCgEJAQAAAA==.Evêlyn:BAAALgADCgQJBAAAAA==.',
Ex='Exerphus:BAAALgAECgUJCAAAAA==.',
Ez='Ezren:BAAALgADCgMJAwAAAA==.',
Fa='Faedove:BAAALgADCgEJAQAAAA==.Fakename:BAAALgAECgcJEAAAAA==.Fakesaint:BAABLgAECn8iAAIGAAgJBh+MBgCEAgAGAAgJBh+MBgCEAgAAAA==.Fangstorm:BAAALgAECgcJEwAAAA==.Farorê:BAAALgAECgYJCQAAAA==.',
Fe='Felbane:BAABLgAECn8ZAAIXAAgJIxbHGQCbAQAXAAgJIxbHGQCbAQAAAA==.Felpally:BAAALgAECgIJAgAAAA==.',
Fl='Fleekjuice:BAAALgADCgcJCgAAAA==.Flexecute:BAABLgAECn8VAAIYAAcJHgTIGgCtAAAYAAcJHgTIGgCtAAAAAA==.',
Fu='Fujimoto:BAAALgAECgUJCgAAAA==.Fujitora:BAAALgAECgEJAQAAAA==.Furpunch:BAAALgADCggJCwAAAA==.',
Ga='Galaxzia:BAAALgAECgYJCQAAAA==.Gallivia:BAAALgAECgMJBAAAAA==.',
Ge='Gehn:BAAALgAECgEJAQAAAA==.',
Gh='Ghostprodigy:BAAALgADCgcJBwAAAA==.',
Gi='Gideòn:BAAALgAECgYJDAAAAA==.Ginzi:BAABLgAECn8ZAAMNAAcJsglcCgAoAQANAAYJYQpcCgAoAQAMAAcJ2AQgUgALAQAAAA==.',
Gl='Glard:BAAALgADCgcJBwAAAA==.',
Go='Gonto:BAAALgADCgYJBgAAAA==.Gopao:BAAALgADCgYJCQABLgAECgUJEQADAAAAAA==.',
Gr='Graxus:BAAALgADCgkJIAAAAA==.Greatchez:BAAALgAECgUJCQAAAA==.Greth:BAAALgADCgYJBwAAAA==.Gronky:BAAALgAECgIJAgAAAA==.',
Gu='Gudge:BAABLgAECn8YAAIPAAcJdRHYEwBkAQAPAAcJdRHYEwBkAQAAAA==.Gummypenguin:BAABLgAECn8VAAMOAAgJGhqZTACDAQAOAAcJiBmZTACDAQAFAAYJTQyuVQDyAAAAAA==.',
Ha='Hadhox:BAABLgAECn8UAAISAAcJBQ0TGgBfAQASAAcJBQ0TGgBfAQAAAA==.Hakano:BAAALgAECgUJDQAAAA==.Hathdox:BAAALgAECgYJCQABLgAECgcJFAASAAUNAA==.Hawkulees:BAAALgADCgcJBQAAAA==.Hazelnoot:BAABLgAECn8aAAIIAAgJDhsXHQDbAQAIAAgJDhsXHQDbAQAAAA==.Haûnt:BAAALgADCgMJAwAAAA==.',
He='Hexcist:BAAALgAECgcJEwAAAA==.',
Hi='Hitsuryu:BAAALgAECgUJEQAAAA==.',
Ho='Hollyanne:BAAALgAECgcJEgAAAA==.Holyfawn:BAAALgADCgEJAQABLgADCgYJBgADAAAAAA==.Holystrike:BAAALgAECgMJBAAAAA==.Hoonicorn:BAAALgAECgMJBwABLgAECgEJAQADAAAAAA==.Hornsnap:BAABLgAECn8WAAMGAAYJnxokHQB6AQAGAAYJnxokHQB6AQAUAAEJ+QwkhQA3AAAAAA==.',
Hu='Huanying:BAAALgADCgQJBAAAAA==.Hunalli:BAAALgAECgUJBQABLgAECgcJGAAPAHURAA==.Hunterb:BAAALgADCgkJCQAAAA==.',
Hy='Hydropump:BAAALgADCgYJBgAAAA==.Hyst:BAACLgAFFH8HAAQFAAMJsBtDGADQAAAFAAIJ0CNDGADQAAAZAAIJohWwDQC1AAAOAAEJ7CEoMwBkAAAuAAQKfzEABAUACQlRJaADAGkDAAUACAnDJaADAGkDABkACAnXIkwBAM0CAA4AAwlzI1CTALIAAAAA.',
Ic='Iconius:BAAALgAECgIJAgAAAA==.',
Ie='Ieatsomeshoe:BAAALgAECgYJBgAAAA==.Ieatsomesock:BAAALgADCgYJBwAAAA==.Ieatwetsocks:BAABLgAECn8VAAMGAAYJIBnoNACwAQAGAAYJIBnoNACwAQAUAAYJpw4LIQATAQAAAA==.',
Il='Illuminatie:BAAALgAECgEJAgAAAA==.',
In='Innexdruid:BAAALgADCgUJBQABLgAECgUJBQADAAAAAA==.Insaint:BAABLgAECn8pAAIIAAgJqhbRHgDRAQAIAAgJqhbRHgDRAQAAAA==.',
Is='Isabellë:BAAALgAECgYJEAAAAA==.Isadorra:BAAALgADCgYJBgAAAA==.Iskandar:BAAALgADCgMJAwAAAA==.',
Ja='Jackboy:BAAALgAECgMJAwAAAA==.Jaker:BAAALgADCgEJAQAAAA==.Jalu:BAAALgAECgUJEQAAAA==.Jatia:BAAALgADCgEJAQABLgAECggJKAASAJ8iAA==.',
Je='Jessamine:BAABLgAECn8bAAILAAgJtxVJKADEAQALAAgJtxVJKADEAQAAAA==.Jessicafelba:BAAALgAECgUJEQAAAA==.Jetta:BAABLgAECn8aAAIaAAYJAhKQCgA5AQAaAAYJAhKQCgA5AQAAAA==.Jezzak:BAAALgAECgcJEwABLgAECggJHgAOAEMaAA==.',
Jo='John:BAAALgAECgcJAQAAAA==.Jorien:BAABLgAECn8mAAIOAAgJYhd1GADPAQAOAAgJYhd1GADPAQAAAA==.',
Jp='Jp:BAAALgAECgEJAQABLgAECgYJBgADAAAAAA==.Jps:BAAALgAECgYJBgAAAA==.',
Ka='Kaboonski:BAAALgADCgUJBQAAAA==.Kaboonsky:BAABLgAECn8dAAIbAAgJHxlEGAAaAgAbAAgJHxlEGAAaAgAAAA==.Kabvoker:BAAALgADCgUJBQAAAA==.Kamikori:BAAALgAECgUJEAAAAA==.Kardels:BAAALgAECgQJCgAAAA==.Karnn:BAACLgAFFH8JAAMcAAQJJhosBABXAQAcAAQJJhosBABXAQAKAAEJHQFLKgArAAAuAAQKfx8AAxwACAn7IJAKAM8CABwACAn7IJAKAM8CAB0AAQnIAWh1ABsAAAAA.',
Ke='Keho:BAAALgAECgQJBgAAAA==.',
Ki='Kiascendance:BAAALgAECgEJAQABLgAECgMJAwADAAAAAA==.Kiplet:BAABLgAECn8YAAIbAAcJ8xicKwCZAQAbAAcJ8xicKwCZAQAAAA==.',
Ko='Korxon:BAABLgAECn8WAAMeAAcJZhYpGQDQAQAeAAcJZhYpGQDQAQAbAAQJDg4CWgDMAAAAAA==.Kotus:BAAALgAECgEJAQAAAA==.',
Kr='Krazilec:BAAALgADCgYJBgABLgADCgYJBgADAAAAAA==.Krazz:BAAALgADCgYJCQABLgAECgUJEQADAAAAAA==.',
Ks='Ksyusha:BAAALgAECgMJBAAAAA==.',
['Kä']='Kämi:BAAALgADCgYJCwABLgAECgEJAgADAAAAAA==.',
La='Lahabrea:BAABLgAECn8fAAMBAAgJBA2+NABYAQABAAgJwAq+NABYAQACAAYJ2w3wKwAPAQAAAA==.Lanuadra:BAAALgADCgYJBgABLgAECggJFgAPAIwdAA==.Lasagne:BAAALgAECgMJBQAAAA==.Lawry:BAAALgAECgUJBQAAAA==.',
Le='Leeara:BAABLgAECn8VAAIXAAgJVBajNQAhAgAXAAgJVBajNQAhAgAAAA==.Legitpoopoo:BAAALgAECgUJBQABLgAECgcJGgALAA8aAA==.Lethalbimbo:BAAALgAECgIJAgAAAA==.',
Li='Liammairi:BAAALgAECgIJAwAAAA==.Lillié:BAAALgAECgQJBAAAAA==.Lilpeep:BAAALgADCgMJAwAAAA==.Lilysham:BAACLgAFFH8OAAIGAAYJIhJRAgDfAQAGAAYJIhJRAgDfAQAuAAQKfxwAAwYACAlSIVAQAJUCAAYABwmSIFAQAJUCABQAAQnnESiFADcAAAAA.Linddrel:BAAALgAECgYJCwAAAA==.',
Lo='Lomea:BAAALgAECgQJBQAAAA==.Lonristyn:BAAALgADCgYJCgAAAA==.',
['Lø']='Løllîe:BAAALgAECgMJBAAAAA==.Løllïe:BAAALgADCgYJDAABLgAECgMJBAADAAAAAA==.',
Ma='Magatai:BAAALgAECgUJCAAAAA==.Mageless:BAAALgADCgIJAgAAAA==.Magifizzle:BAAALgADCgEJAQAAAA==.Malenrhen:BAAALgADCgkJFgAAAA==.Malotan:BAAALgADCgUJBQAAAA==.Mandhos:BAAALgADCgIJAgAAAA==.Martlok:BAABLgAECn8YAAMMAAYJoBqjNgBfAQAMAAYJlBijNgBfAQANAAIJEBbZFABGAAAAAA==.Matalue:BAAALgAECgYJDQAAAA==.Maynis:BAAALgADCgMJAwAAAA==.',
Mc='Mcbrynhammer:BAAALgAECgEJAQAAAA==.',
Me='Methallica:BAAALgADCgMJAwAAAA==.',
Mi='Micflinigan:BAABLgAECn8XAAMSAAYJIBIDJQAUAQASAAUJ3xIDJQAUAQAYAAEJKA/gKgA1AAAAAA==.Minmo:BAAALgADCgUJBQABLgAECgcJGAAbAPMYAA==.Misahaviran:BAAALgADCgQJBAAAAA==.Mishelö:BAAALgADCgMJAwAAAA==.Mistynite:BAAALgADCgQJBAAAAA==.',
Mo='Mochimochi:BAAALgADCgYJBgAAAA==.Moduur:BAAALgAECgYJCgAAAA==.Moonshae:BAABLgAECn8bAAIdAAgJzROlDgC9AQAdAAgJzROlDgC9AQAAAA==.Mooshata:BAAALgAECgQJBAAAAA==.Morninghunt:BAAALgADCgEJAQABLgAECgkJIQAJAH4XAA==.Mornings:BAAALgAECgYJDQABLgAECgkJIQAJAH4XAA==.Mouse:BAAALgAECgQJDAAAAA==.Moze:BAAALgADCgMJAwAAAA==.',
Mu='Murf:BAAALgADCgMJAwAAAA==.',
My='Mystiquè:BAAALgADCgYJCAAAAA==.',
Na='Naboo:BAAALgADCgIJAgABLgAECgcJFAAMAAEUAA==.Nails:BAAALgAECgUJEQAAAA==.Naithin:BAAALgAECgIJAgAAAA==.Nalarah:BAAALgAECgEJAQAAAA==.Naviriel:BAAALgADCgYJCQABLgAECgUJEQADAAAAAA==.',
Ni='Nightdragon:BAAALgADCgQJBAAAAA==.Nivvix:BAAALgADCgYJBgAAAA==.',
No='Noknik:BAAALgADCgMJAwAAAA==.Nootloops:BAAALgADCgcJCgABLgAECggJGgAIAA4bAA==.Noriisa:BAABLgAECn8eAAIOAAgJQxo+EwD4AQAOAAgJQxo+EwD4AQAAAA==.Noudders:BAAALgAECgcJDwAAAA==.',
Nu='Nutsandberri:BAAALgADCggJCQAAAA==.',
Od='Odinhand:BAABLgAECn8bAAIJAAgJsAi8GQAvAQAJAAgJsAi8GQAvAQAAAA==.',
Ol='Oliissa:BAAALgADCggJCAAAAA==.',
On='Onibeef:BAAALgAECgIJAgAAAA==.',
Or='Oregar:BAAALgADCgYJBgAAAA==.',
Ou='Ouch:BAAALgADCgEJAQAAAA==.',
Oz='Ozwäld:BAABLgAECn8XAAILAAgJdSCsCgCVAgALAAgJdSCsCgCVAgAAAA==.',
Pa='Paladinb:BAAALgADCgYJBgAAAA==.Pandapí:BAAALgADCgcJDwAAAA==.Panduh:BAACLgAFFH8PAAILAAUJjw+NDQCvAQALAAUJjw+NDQCvAQAuAAQKfyUAAgsACAkaIr0aAAwDAAsACAkaIr0aAAwDAAAA.Pandóra:BAAALgAECgMJCAAAAA==.Pariousa:BAACLgAFFH8HAAMTAAMJTh1BAgAlAQATAAMJYRxBAgAlAQAEAAIJcB72EADBAAAuAAQKfzEAAxMACQmzJRoAAGkDAAQACAmVJUgDAGsDABMACQkCJRoAAGkDAAAA.Patty:BAAALgADCgEJAgAAAA==.',
Pe='Perceval:BAAALgAECgYJCgAAAA==.Pewpewboo:BAACLgAFFH8SAAILAAQJLwx4JwAzAQALAAQJLwx4JwAzAQAuAAQKfygAAgsACQm5HL8zAKQCAAsACQm5HL8zAKQCAAAA.',
Pi='Pigeonhole:BAAALgADCgYJBgABLgAECgQJBAADAAAAAA==.Pinkeepink:BAAALgAECgYJCQAAAA==.',
Pl='Plates:BAAALgAECgIJAwAAAA==.',
Pr='Pray:BAAALgADCgYJBgAAAA==.',
Qu='Quarantina:BAAALgAECgIJAQAAAA==.',
Ra='Ragnor:BAAALgADCgQJBAAAAA==.Ralganor:BAABLgAECn8bAAIfAAgJJSHdBADuAQAfAAgJJSHdBADuAQAAAA==.Ramanash:BAAALgADCgYJEgAAAA==.Ravenstrider:BAAALgAECgYJDwAAAA==.Raylerya:BAAALgADCgYJCQAAAA==.Raylish:BAAALgAECgcJDQAAAA==.',
Re='Ren:BAAALgADCgQJBgAAAA==.',
Rh='Rhm:BAAALgAECgMJBAAAAA==.Rhylen:BAAALgADCgYJCQABLgAECgUJEQADAAAAAA==.',
Ri='Rina:BAACLgAFFH8QAAIgAAUJsxrgAAA7AQAgAAUJsxrgAAA7AQAuAAQKfx0AAiAACAlPIBUCAOoCACAACAlPIBUCAOoCAAAA.Rineli:BAAALgAFFAEJAQAAAA==.Ringadingg:BAABLgAECn8cAAIMAAgJByDkGADnAgAMAAgJByDkGADnAgAAAA==.Riniching:BAAALgAECgEJAQABLgAECggJHAAMAAcgAA==.Rivets:BAAALgADCgMJAwABLgAECgUJEQADAAAAAA==.',
Ro='Roastduck:BAAALgAECgcJEwAAAA==.Rosequartz:BAAALgAECgEJAQAAAA==.Rosetas:BAAALgADCggJCAAAAA==.',
Ru='Runeytoon:BAAALgAECgUJBgAAAA==.',
Sa='Sacamano:BAAALgAECgMJAwAAAA==.Sarazah:BAABLgAECn8rAAIIAAkJBSW6AABgAwAIAAkJBSW6AABgAwAAAA==.',
Sc='Scony:BAAALgAECgMJAwAAAA==.Scribs:BAAALgADCgkJCQAAAA==.',
Sd='Sdiybt:BAABLgAECn8aAAMLAAcJDxpaOgCAAQALAAYJ4hxaOgCAAQAWAAQJ8hcSDAARAQAAAA==.',
Se='Seegon:BAAALgAECgEJAQAAAA==.Selysse:BAAALgAECgUJCQAAAA==.Sephi:BAAALgAECgEJAQAAAA==.Seramis:BAAALgAECgEJAQAAAA==.Servis:BAAALgADCgYJBgAAAA==.Setharoth:BAAALgAECgEJAgAAAA==.Sethena:BAAALgAECgcJAgAAAA==.Severalforms:BAAALgADCgIJAgABLgAECggJJQAIAPodAA==.Severànce:BAAALgADCgQJBAABLgAECggJJQAIAPodAA==.Sevotion:BAABLgAECn8lAAQIAAgJ+h0GHgDVAQAIAAgJIh0GHgDVAQAhAAUJgREpLQClAAAiAAQJEA6vPAB4AAAAAA==.',
Sh='Shablammy:BAAALgAECgUJEQAAAA==.Shadownome:BAAALgAECgIJAwAAAA==.Shadowolves:BAAALgAECgEJAQAAAA==.Shanker:BAAALgAECgEJAQAAAA==.Shaolinchii:BAAALgADCgkJEAAAAA==.Shayden:BAAALgAECgIJAgAAAA==.Shinkickerr:BAAALgADCgYJBgAAAA==.Shirø:BAAALgADCgIJAgAAAA==.Shizamthebam:BAAALgAECgQJBAAAAA==.Shäzu:BAAALgADCgEJAQAAAA==.',
Si='Sihtric:BAAALgADCggJDQAAAA==.Silvanosh:BAAALgAECggJEQAAAA==.Silverflame:BAAALgAECgEJAQAAAA==.Sinveil:BAABLgAECn8pAAQZAAgJ9hgSBgAQAgAZAAgJnxYSBgAQAgAFAAcJfRf1KADfAQAOAAQJZBGTVQDJAAAAAA==.',
Sk='Skendr:BAAALgAECgMJAwAAAA==.Skullshadow:BAAALgADCgMJAwAAAA==.Skydragon:BAAALgADCgYJDgAAAA==.',
Sl='Slash:BAAALgADCgMJAwAAAA==.Sleepydwarf:BAAALgAECgEJAgAAAA==.',
Sm='Smerknd:BAAALgADCgUJCAAAAA==.',
Sp='Spiritly:BAAALgADCggJDgAAAA==.Sprynt:BAAALgAECgYJCQAAAA==.',
St='Starmist:BAAALgADCggJBgAAAA==.Stendo:BAAALgAECgMJBAABLgAFFAQJCgAjANogAA==.Steviewonder:BAAALgAECgYJCQAAAA==.Stonemother:BAAALgAECgMJBAAAAA==.Stormbane:BAAALgAECggJCgAAAA==.Stormcrest:BAAALgADCgkJFAAAAA==.Stormseer:BAAALgAECgIJAgABLgAECggJCgADAAAAAA==.',
Su='Sunae:BAAALgADCgkJCQAAAA==.Sunfyrie:BAAALgAECgcJCwAAAA==.Sunn:BAAALgADCgYJBgABLgAECgUJEQADAAAAAA==.',
Sw='Swampmonster:BAAALgAECgIJAwABLgAECgYJBwADAAAAAA==.Sweèt:BAAALgAECgMJAwAAAA==.Swockwickdus:BAACLgAFFH8DAAIXAAIJmR9+IgC7AAAXAAIJmR9+IgC7AAAuAAQKfx4AAxcACAmEIwURAPYCABcACAnHIQURAPYCACMAAwk/JUs/AP8AAAAA.Swooze:BAAALgADCgUJBQAAAA==.',
Ta='Tarouhorn:BAAALgAECgIJAwAAAA==.Taurasthunt:BAAALgAECgQJCAABLgAECgcJFAAYAKQZAA==.Taurastrage:BAABLgAECn8UAAIYAAcJpBmnCQCTAQAYAAcJpBmnCQCTAQAAAA==.Taurenator:BAAALgADCgEJAwAAAA==.Taursroot:BAAALgADCgIJAgAAAA==.Taylorshift:BAABLgAECn8YAAIJAAcJLB6cCgDlAQAJAAcJLB6cCgDlAQAAAA==.Tazarakk:BAAALgADCgMJAwABLgAECgUJEQADAAAAAA==.Tazbeard:BAAALgADCgYJCQABLgAECgUJEQADAAAAAA==.',
Te='Teedos:BAAALgAECgcJBwAAAA==.Teetau:BAABLgAECn8VAAIQAAcJYAMTFACAAAAQAAcJYAMTFACAAAAAAA==.',
Th='Thaddaios:BAAALgAECgEJAQABLgAECggJGAAkAMEOAA==.Thadregosa:BAABLgAECn8YAAMkAAgJwQ4UBQBlAQAkAAgJwQ4UBQBlAQAPAAUJFQlXSQCxAAAAAA==.Thander:BAAALgADCgMJAwABLgAECgMJAwADAAAAAA==.Thannicus:BAAALgAECgYJBgAAAA==.Thedarkskull:BAAALgAECgEJAQAAAA==.Thugnugget:BAAALgADCgEJAQAAAA==.',
Ti='Tibbotanical:BAABLgAECn8bAAIlAAgJ3Ri6GQCyAQAlAAgJ3Ri6GQCyAQAAAA==.Tiblessed:BAAALgADCgEJAQABLgAECggJGwAlAN0YAA==.Tiffy:BAAALgADCgcJFwAAAA==.Tintreach:BAAALgAECgQJBQAAAA==.Tirnotham:BAAALgAECgMJBAAAAA==.',
To='Tokalu:BAAALgAECgUJEQAAAA==.Tonjudsonson:BAACLgAFFH8OAAIQAAQJ8yEWAQCQAQAQAAQJ8yEWAQCQAQAuAAQKfyYAAhAACAnkJfYAAGQDABAACAnkJfYAAGQDAAAA.Tonopah:BAAALgAECgUJEQAAAA==.Toxix:BAAALgAECgYJDwAAAA==.',
Tr='Travesura:BAAALgADCgIJAgAAAA==.',
Ts='Tsu:BAAALgAECgUJBQAAAA==.',
Tw='Twiki:BAAALgAECgYJDwAAAA==.',
Ty='Tyrssana:BAAALgAECgMJBAABLgAECggJGwAPAEYUAA==.',
Ug='Uglykitten:BAAALgAECgYJEgAAAA==.',
Un='Uncas:BAAALgAECgEJAQAAAA==.',
Ur='Urdeadtoo:BAAALgAECgcJEAAAAA==.',
Va='Vaererelor:BAAALgAECgEJAgAAAA==.Varnzdort:BAAALgAECgkJCQABLgAFFAYJDgAGACISAA==.Vassiliki:BAAALgADCgYJCQAAAA==.Vaterunser:BAAALgAECgMJBAAAAA==.Vayleen:BAAALgADCgYJBgAAAA==.',
Ve='Verlynna:BAAALgADCgIJAwAAAA==.',
Vi='Vicky:BAAALgADCgYJCQABLgAECgUJDAADAAAAAA==.Vierth:BAAALgADCgQJBAAAAA==.Vincenzo:BAACLgAFFH8IAAIcAAMJciTtBQA5AQAcAAMJciTtBQA5AQAuAAQKfxoAAhwACAk9I0QEAEgDABwACAk9I0QEAEgDAAAA.Vinhar:BAAALgADCgkJCQAAAA==.Vinlight:BAAALgAECgUJBQAAAA==.Vinsteam:BAAALgAECgYJDgAAAA==.Visea:BAAALgADCgUJBgAAAA==.',
Vl='Vlarett:BAAALgAECgMJBQAAAA==.',
Vo='Voidsavage:BAAALgAECgMJAwAAAA==.Volic:BAAALgAECgcJFQAAAQ==.',
Vu='Vulpixa:BAAALgADCgkJGgAAAA==.',
Wa='Waps:BAAALgAECgEJAQAAAA==.Warsyeaa:BAAALgADCgQJAwAAAA==.Watevr:BAEALgAECgYJBgABLgAECgYJGgATALYPAA==.',
We='Weeniehutjr:BAAALgADCgEJAQABLgAECgEJAQADAAAAAA==.Wesleypriest:BAABLgAECn8cAAMeAAgJrAkDEwBlAQAeAAgJWQkDEwBlAQAbAAMJCwhfaQCHAAAAAA==.Wesleyswipes:BAAALgADCgEJAQAAAA==.',
Xa='Xalabro:BAAALgAECgUJEQAAAA==.Xarcus:BAAALgAECgEJAQABLgAECgcJGgALAEkXAA==.',
Xe='Xehorn:BAAALgAECgYJBgABLgAFFAYJDgAGACISAA==.Xeros:BAAALgADCgcJDwAAAA==.',
Xo='Xousa:BAAALgADCgYJCAABLgAFFAMJBwATAE4dAA==.',
Xy='Xyknight:BAAALgADCgUJBwAAAA==.Xylas:BAABLgAECn8aAAILAAcJSRdERgBcAQALAAcJSRdERgBcAQAAAA==.',
Ya='Yashe:BAABLgAECn8VAAMGAAcJ0RvpEQDiAQAGAAcJ0RvpEQDiAQAUAAEJWAjakQAlAAAAAA==.',
Yi='Yinoa:BAAALgADCgUJBQABLgAECgcJFgASAJ0XAA==.',
Yo='Yokuni:BAAALgAECgQJBAAAAA==.',
Yu='Yuefei:BAAALgADCgUJBQAAAA==.',
Za='Zakoor:BAAALgAECgMJAwAAAA==.Zareena:BAAALgADCgMJAwAAAA==.Zarnia:BAAALgAECgMJAwAAAA==.Zarrock:BAAALgAECgMJAwAAAA==.Zaurra:BAAALgAECgYJCgAAAA==.',
Ze='Zebbyzebzeb:BAAALgAECgMJAwAAAA==.Zebrow:BAAALgADCgQJBgAAAA==.Zebzap:BAAALgADCgEJAQAAAA==.Zed:BAAALgADCgkJEgAAAA==.Zehorn:BAAALgAECgYJBgABLgAFFAYJDgAGACISAA==.Zekia:BAAALgAECgMJAwAAAA==.Zenwaldo:BAAALgAECgEJAQAAAA==.Zerm:BAABLgAECn8oAAIIAAgJOhYEIADKAQAIAAgJOhYEIADKAQAAAA==.',
Zi='Zinnkura:BAAALgAECgMJBAAAAA==.Zizzix:BAAALgAECgUJBQAAAA==.',
Zo='Zorsa:BAAALgAECgYJCAAAAA==.',
Zu='Zulfrito:BAABLgAECn8VAAMFAAcJWxvNBQCZAQAZAAUJ9x6zEAC4AQAFAAcJOxfNBQCZAQAAAA==.',
['Ñô']='Ñôg:BAAALgADCggJCAAAAA==.',
['Ød']='Ødis:BAAALgADCgcJFwAAAA==.',
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

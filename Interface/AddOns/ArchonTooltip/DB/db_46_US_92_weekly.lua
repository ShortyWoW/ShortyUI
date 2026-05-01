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

local lookup = {'Warlock-Demonology','Shaman-Elemental','Paladin-Retribution','Druid-Balance','Evoker-Preservation','DemonHunter-Havoc','Monk-Windwalker','Warrior-Fury','Paladin-Protection','Monk-Mistweaver','DemonHunter-Devourer','Warrior-Arms','Rogue-Subtlety','Rogue-Assassination','Unknown-Unknown','Shaman-Restoration','Evoker-Devastation','Evoker-Augmentation','Hunter-BeastMastery','Warlock-Destruction','Priest-Shadow','DemonHunter-Vengeance','Mage-Frost','Hunter-Marksmanship','Priest-Discipline','Mage-Arcane','Priest-Holy','Paladin-Holy','Druid-Feral','DeathKnight-Unholy','Rogue-Outlaw','Warrior-Protection','DeathKnight-Blood','Druid-Restoration','Warlock-Affliction','DeathKnight-Frost','Monk-Brewmaster','Druid-Guardian','Hunter-Survival','Shaman-Enhancement',}
local provider = {region='US',realm='Exodar',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abelladanger:BAAALgAECgUJCgAAAA==.Ablivion:BAABLgAECn8YAAIBAAkJuxE+OgAjAgABAAkJuxE+OgAjAgAAAA==.Abzero:BAAALgAECgIJAwAAAA==.',
Ac='Achillesdk:BAAALgAECgMJAwAAAA==.',
Ad='Adeshae:BAAALgADCgEJAQAAAA==.Adeynalon:BAAALgAECgQJBQAAAA==.Adinne:BAAALgAECgMJAwABLgAECgkJKgACAAATAA==.',
Ae='Aestris:BAAALgADCgkJLQAAAA==.Aethira:BAAALgAECgEJAQAAAA==.',
Ah='Ahnaka:BAAALgADCgcJDgAAAA==.Ahron:BAABLgAECn8mAAIDAAgJ+B7BCwBrAgADAAgJ+B7BCwBrAgAAAA==.',
Ai='Aica:BAAALgAECgIJAgAAAA==.',
Al='Aleuseche:BAAALgADCgYJCwAAAA==.Alexr:BAAALgADCgMJAwAAAA==.Allarielle:BAAALgADCgEJAQAAAA==.',
Am='Amarantus:BAAALgADCgEJAQABLgAECgkJLAAEAKEdAA==.Amarndeus:BAAALgADCgMJAwAAAA==.',
An='Anmodru:BAAALgAECgYJBgAAAA==.Annihilation:BAAALgAECgEJAQAAAA==.Anorillian:BAAALgADCgkJCgAAAA==.Antàrès:BAAALgAECgYJCQAAAA==.',
Ao='Aotc:BAAALgAECgkJEgAAAA==.',
Aq='Aquaism:BAAALgADCgIJAgAAAA==.Aqulath:BAAALgAECgIJBAAAAA==.Aquílés:BAAALgADCgEJAQAAAA==.',
Ar='Arazensetal:BAABLgAECn8gAAIFAAgJwBuGAgCOAgAFAAgJwBuGAgCOAgAAAA==.Arctica:BAAALgAECgIJAgAAAA==.Arker:BAAALgADCgIJAgAAAA==.',
As='Astralrisk:BAAALgADCgUJCAAAAA==.',
At='Athenä:BAABLgAECn8fAAIGAAYJTB0fCgCdAQAGAAYJTB0fCgCdAQAAAA==.',
Au='Aubrii:BAAALgADCgYJCAAAAA==.Aukatsang:BAACLgAFFH8GAAIHAAMJqRnHCgCvAAAHAAMJqRnHCgCvAAAuAAQKfyMAAgcACQnBIl4BAKMDAAcACQnBIl4BAKMDAAAA.Aureuzeth:BAAALgAECgcJDgAAAA==.',
Az='Azymor:BAAALgADCggJCQAAAA==.',
Ba='Baddy:BAABLgAECn8dAAIIAAgJpBwEFQClAgAIAAgJpBwEFQClAgAAAA==.Bagabo:BAACLgAFFH8JAAIHAAQJrBoOBABaAQAHAAQJrBoOBABaAQAuAAQKfyQAAgcACAndHo0JAN8CAAcACAndHo0JAN8CAAAA.Baladeva:BAABLgAECn8hAAIJAAgJrxq2BQDWAQAJAAgJrxq2BQDWAQAAAA==.Bamberram:BAAALgAECgQJBgAAAA==.Bamboozle:BAAALgADCgUJAgAAAA==.Barrak:BAAALgADCgEJAQABLgAECggJJgADAPgeAA==.Bartz:BAAALgAECgkJBAAAAA==.Bau:BAAALgADCgMJAwAAAA==.',
Be='Bearhold:BAAALgAECgQJBAAAAA==.Beersnob:BAABLgAECn8UAAIKAAcJzRIULwBBAQAKAAcJzRIULwBBAQAAAA==.Benjam:BAABLgAECn8iAAILAAcJNiNKGQC9AgALAAcJNiNKGQC9AgAAAA==.Benyo:BAAALgADCgIJAgAAAA==.',
Bi='Bigmikeyg:BAABLgAECn8hAAIDAAgJbQrtOABhAQADAAgJbQrtOABhAQAAAA==.Bigsteve:BAABLgAECn8gAAMMAAgJOBh4BQDRAQAIAAYJERvkMwDaAQAMAAgJ0hJ4BQDRAQAAAA==.',
Bl='Blanket:BAABLgAFFH8IAAMNAAMJNwiPDwD0AAANAAMJqQWPDwD0AAAOAAEJ0QmdBwBUAAAAAA==.Blitzo:BAAALgAECgYJBgAAAA==.',
Bo='Bottomdps:BAAALgAECgIJAgABLgAFFAIJAgAPAAAAAA==.',
Bu='Bunty:BAAALgADCgQJBAAAAA==.Buttonmashèr:BAAALgADCgUJBQAAAA==.',
['Bè']='Bèyork:BAABLgAECn8eAAIQAAgJgRvhBwBtAgAQAAgJgRvhBwBtAgAAAA==.',
['Bõ']='Bõnd:BAAALgADCgIJAgAAAA==.',
Ca='Caedan:BAAALgADCgcJCgAAAA==.Caedreth:BAABLgAECn8bAAQFAAkJTgb1IgBhAQAFAAgJawX1IgBhAQARAAMJGgjBMgCAAAASAAEJEwbqRwA0AAAAAA==.Calizon:BAAALgAECggJDgAAAA==.Camc:BAAALgAECgQJCQAAAA==.Canowhoopass:BAABLgAECn8VAAICAAYJtAmEJgDyAAACAAYJtAmEJgDyAAAAAA==.Cardano:BAAALgADCggJDQAAAA==.Carine:BAAALgAECgMJBAAAAA==.',
Ce='Cerassin:BAACLgAFFH8KAAILAAQJrQ/iEgAtAQALAAQJrQ/iEgAtAQAuAAQKfywAAgsACQk+H/YPAP8CAAsACQk+H/YPAP8CAAAA.Cereas:BAABLgAECn8kAAIGAAcJ0RjQCgCQAQAGAAcJ0RjQCgCQAQAAAA==.',
Ch='Challincia:BAAALgADCgUJBgAAAA==.Cherrish:BAAALgADCgMJBQAAAA==.Chuckrutis:BAABLgAECn8VAAIRAAYJUh5sDAAUAgARAAYJUh5sDAAUAgAAAA==.',
Cl='Cliché:BAAALgADCgkJGQAAAA==.Cloudzz:BAAALgAECgEJAQAAAA==.Clukdogg:BAACLgAFFH8KAAITAAQJ1hVPDABSAQATAAQJ1hVPDABSAQAuAAQKfyIAAhMACQnhIHQCAHEDABMACQnhIHQCAHEDAAAA.',
Co='Coldandwet:BAAALgAECgEJAQAAAA==.Combination:BAABLgAECn8hAAIUAAgJPxteAQA9AgAUAAgJPxteAQA9AgABLgAFFAUJEAADAEAcAA==.Constrace:BAAALgAECgMJAwAAAA==.Corvenall:BAABLgAECn8rAAIRAAgJGAtqBQBYAQARAAgJGAtqBQBYAQAAAA==.Cowboytroy:BAAALgAECgEJAQAAAA==.',
Cr='Crashpad:BAAALgAECgQJBAAAAA==.Crossbow:BAABLgAECn8rAAITAAkJCB9pCAByAgATAAkJCB9pCAByAgAAAA==.',
Ct='Cthulha:BAAALgADCgEJAQAAAA==.',
Da='Dabbernath:BAAALgADCgMJAwAAAA==.Dandaraber:BAAALgADCgMJAwAAAA==.Dante:BAAALgAECgIJAwABLgAECggJEwAPAAAAAA==.Darkluster:BAAALgADCgEJAQAAAA==.Darknesmonk:BAAALgAECgQJBAAAAA==.Darkrune:BAAALgADCgkJCQAAAA==.Darÿ:BAAALgADCggJEwAAAA==.Davand:BAAALgADCgcJBwAAAA==.Dawncloud:BAAALgADCgkJFgAAAA==.',
De='Deathbcmesyu:BAAALgAECgYJEAAAAA==.Deathbreathh:BAAALgAECgQJBAAAAA==.Deathweilder:BAAALgAECgUJEAAAAA==.Deloaofnova:BAAALgAECgMJAwAAAA==.Demorian:BAAALgAECgEJAQABLgAECgcJFwAVAHYKAA==.Deondre:BAAALgAECgMJBAAAAA==.Deucali:BAAALgADCgEJAQAAAA==.Devilsmight:BAAALgAECgQJBwAAAA==.',
Di='Diehappy:BAAALgAECgMJAwAAAA==.Dillie:BAAALgADCgMJAwAAAA==.Disguize:BAAALgAECgQJBQAAAA==.',
Do='Dompal:BAAALgAECgMJBgABLgAFFAQJCgAWAFUeAA==.Dozy:BAAALgADCgkJDQAAAA==.',
Dr='Draatoo:BAAALgAECgMJAwAAAA==.Dreamm:BAAALgAECgkJCQABLgAFFAMJCwAXAPEhAA==.Drovinos:BAAALgADCgkJEQAAAA==.Drybonez:BAABLgAECn8UAAIXAAYJzwiafwDVAAAXAAYJzwiafwDVAAAAAA==.Drylie:BAACLgAFFH8KAAMTAAQJ1iF7EgAnAQATAAQJ1iF7EgAnAQAYAAEJwBmLJQBSAAAuAAQKfyMAAxgACQmGJL8JAAUDABgACAmdIr8JAAUDABMAAwnsIno1ADsBAAAA.Dràgonkíng:BAAALgAECgUJCwAAAA==.',
Dt='Dtinnel:BAAALgAECgYJEAABLgAECgcJGgAZAOYaAA==.',
Du='Dumbledussy:BAABLgAECn8XAAIVAAcJdgo9GwAjAQAVAAcJdgo9GwAjAQAAAA==.Durryfruid:BAAALgAECgIJAgAAAA==.',
Ed='Edanor:BAAALgADCgEJAQABLgAECgcJDgAPAAAAAA==.',
Eg='Ego:BAABLgAECn8lAAIIAAgJXiPPAQDcAgAIAAgJXiPPAQDcAgAAAA==.',
El='Elandra:BAAALgAECgcJEQAAAA==.Elrondo:BAAALgADCgQJBAAAAA==.',
Em='Emela:BAAALgAECgQJBAAAAA==.Emmarree:BAAALgADCgUJBQABLgAECgYJFQAXAHciAA==.Emmone:BAAALgAECgMJAwAAAA==.Emmylyn:BAAALgAECgEJAQAAAA==.',
Ev='Evelapix:BAAALgAECgEJAQAAAA==.Evilrook:BAAALgADCgEJAQAAAA==.Evocamc:BAAALgADCgEJAQAAAA==.',
Ex='Exacerbator:BAAALgAECgEJAgAAAA==.',
Fa='Faker:BAAALgAECgYJCwAAAA==.Farglight:BAAALgAECgQJBAAAAA==.Faunna:BAABLgAECn8sAAIEAAkJoR37AgCrAgAEAAkJoR37AgCrAgAAAA==.',
Fe='Feebeeboofae:BAAALgADCgYJBgAAAA==.Felaz:BAABLgAECn8iAAIaAAgJHR+gAABtAgAaAAgJHR+gAABtAgAAAA==.Fericus:BAAALgAECgIJAwAAAA==.',
Fi='Fingerguns:BAABLgAECn8VAAQZAAYJchRaEQB6AQAZAAYJchRaEQB6AQAbAAMJdwjbZgCRAAAVAAMJ+AcDMwBtAAAAAA==.Fionaa:BAABLgAECn8dAAMBAAkJMAVlLwBuAQABAAkJBQVlLwBuAQAUAAEJsAfmeAAqAAAAAA==.Fiyona:BAAALgAECgIJAgAAAA==.',
Fl='Flip:BAAALgAECgUJBQAAAA==.Flogger:BAAALgADCgcJBwAAAA==.Flooraan:BAAALgADCgMJAwAAAA==.Floortank:BAAALgAECgYJDwAAAA==.',
Fo='Forladyranni:BAAALgADCgEJAQAAAA==.Fosforin:BAAALgAECgEJAQAAAA==.',
Fr='Freeteddyp:BAABLgAFFH8IAAIcAAMJsBYnEwDZAAAcAAMJsBYnEwDZAAAAAA==.Frikilatar:BAAALgAECgEJAQAAAA==.Frostyhatesu:BAEALgADCgMJAwABLgAECgIJAwAPAAAAAA==.Frrank:BAACLgAFFH8KAAIMAAQJGSRgBQAuAQAMAAQJGSRgBQAuAQAuAAQKfyQAAgwACQlrJGEAALQDAAwACQlrJGEAALQDAAAA.',
Fu='Fullerene:BAAALgADCgUJCwAAAA==.',
Ga='Galcain:BAABLgAECn8cAAMTAAgJAiL6BwARAwATAAgJvSH6BwARAwAYAAMJVBqrYAC+AAAAAA==.',
Gh='Ghostmain:BAAALgAECgIJAgAAAA==.',
Gi='Girandzimm:BAAALgAECgEJAQAAAA==.',
Gl='Glacia:BAABLgAECn8hAAIXAAgJYhJGLACzAQAXAAgJYhJGLACzAQAAAA==.Glaivizzon:BAAALgAECgIJAwAAAA==.',
Go='Gorizarev:BAAALgAECgQJCAAAAA==.',
Gr='Grogtar:BAAALgADCgMJAwAAAA==.Grumandel:BAABLgAECn8hAAIdAAgJ6w0eBwCNAQAdAAgJ6w0eBwCNAQAAAA==.',
Gu='Gudetama:BAAALgAECgcJEQAAAA==.Guhlinda:BAAALgADCgcJBwAAAA==.Gunthor:BAAALgAECgEJAQAAAA==.',
Ha='Hadgavelm:BAAALgADCgQJBAAAAA==.Haidie:BAAALgADCgEJAQAAAA==.Hakur:BAABLgAECn8iAAIDAAgJoh0WEgAqAgADAAgJoh0WEgAqAgAAAA==.Hamahara:BAAALgADCgMJAwAAAA==.Hanma:BAACLgAFFH8LAAIeAAYJBA1sHwA9AQAeAAYJBA1sHwA9AQAuAAQKfygAAh4ACQn7HhIsAIgCAB4ACQn7HhIsAIgCAAAA.Harribel:BAABLgAECn8bAAIXAAgJRQ5ORgBcAQAXAAgJRQ5ORgBcAQAAAA==.',
He='Heliodorus:BAAALgADCgIJAgAAAA==.Hellcroh:BAAALgAECgMJAwAAAA==.Hercey:BAAALgADCgYJBgAAAA==.',
Hi='Higheleazar:BAAALgADCgYJBgAAAA==.Hiroki:BAAALgAECgcJEQAAAA==.Hitachitotem:BAACLgAFFH8KAAICAAMJaAiWEQDeAAACAAMJaAiWEQDeAAAuAAQKfxkAAgIACAmZGloaAEECAAIACAmZGloaAEECAAAA.Hizzon:BAAALgADCgcJCAAAAA==.',
Ho='Holous:BAAALgAECgQJBAAAAA==.Holybjoly:BAAALgAECggJCAAAAA==.Holyphatso:BAAALgADCgMJAwABLgAECggJGAAbAHEgAA==.',
Hy='Hyperíon:BAAALgAECgQJBQAAAA==.Hyun:BAAALgAECgIJAgAAAA==.',
Ic='Icies:BAAALgAECgYJDwAAAA==.',
In='Inflikted:BAABLgAECn8UAAIeAAgJtAUwPgBEAQAeAAgJtAUwPgBEAQAAAA==.Interwebz:BAAALgAECgcJDQAAAA==.Intra:BAAALgAECgMJBAAAAA==.',
Ir='Iristia:BAAALgADCgcJAgAAAA==.',
Ja='Jadeshark:BAAALgADCgcJBwAAAA==.Jaidic:BAAALgADCgYJBgABLgADCgcJBwAPAAAAAA==.',
Je='Jehannum:BAABLgAECn8aAAICAAgJ9AwnGQBJAQACAAgJ9AwnGQBJAQAAAA==.Jessira:BAAALgAECgYJDgAAAA==.Jezabel:BAAALgAECgUJDgAAAA==.',
Jo='Jomjiggado:BAAALgADCgUJBQAAAA==.Jonahheal:BAAALgAECgUJBwABLgAFFAMJCwAQAOcbAA==.',
Ju='Juliana:BAAALgADCgMJAwAAAA==.',
['Jú']='Júdâs:BAABLgAECn8ZAAIVAAcJIRfdDgCaAQAVAAcJIRfdDgCaAQAAAA==.',
Ka='Kaeläni:BAAALgAECgQJBwAAAA==.Kalek:BAAALgAECgEJAQAAAA==.Kaljrak:BAAALgAECgYJEAAAAA==.Katarena:BAABLgAECn8fAAIcAAcJvA9TGgB6AQAcAAcJvA9TGgB6AQAAAA==.Kathyra:BAAALgAECgcJEgAAAA==.Kavax:BAABLgAECn8WAAIcAAcJFhO/EgDEAQAcAAcJFhO/EgDEAQAAAA==.',
Ke='Keeller:BAACLgAFFH8MAAIDAAUJMAwtEwA3AQADAAUJMAwtEwA3AQAuAAQKfzIAAgMACAnsHPcXAPwBAAMACAnsHPcXAPwBAAAA.Keggor:BAAALgAECgEJAQAAAA==.Kentyr:BAABLgAECn8cAAMNAAgJVAxtEQBbAQANAAgJVAxtEQBbAQAfAAIJZwGDDgA0AAAAAA==.',
Kh='Khasket:BAAALgAECgYJDQAAAA==.',
Ki='Kigahen:BAAALgADCgYJBgAAAA==.Kiingsbanne:BAAALgADCgIJAgABLgAECgcJIQAIAEMhAA==.Kinký:BAABLgAECn8aAAIIAAgJ8g6hNQDSAQAIAAgJ8g6hNQDSAQABLgAECgMJBgAPAAAAAA==.Kiraelis:BAABLgAECn8VAAIYAAcJOA3XCQA1AQAYAAcJOA3XCQA1AQAAAA==.Kiss:BAAALgADCgEJAQABLgAECgEJAQAPAAAAAA==.Kivea:BAAALgAECgcJEAAAAA==.',
Kl='Klah:BAAALgADCgQJBAAAAA==.',
Ko='Konagda:BAAALgADCgcJDQAAAA==.Korvoh:BAABLgAECn8hAAMZAAgJfRsDBQBxAgAZAAgJBxoDBQBxAgAbAAMJUxd/XQC8AAAAAA==.',
Kr='Kringe:BAABLgAECn8ZAAICAAYJNyTUFAB3AgACAAYJNyTUFAB3AgAAAA==.',
Ku='Kumonk:BAAALgAECgYJDgAAAA==.',
Ky='Kyloris:BAAALgAECgMJBQAAAA==.',
['Kä']='Kämik:BAABLgAECn8hAAITAAgJMiAZBgCWAgATAAgJMiAZBgCWAgAAAA==.',
['Kì']='Kìn:BAAALgAECgUJCwAAAA==.',
La='Lampion:BAABLgAECn8VAAIGAAgJSQggOgAZAQAGAAgJSQggOgAZAQAAAA==.Lasstchance:BAAALgAECgMJAwAAAA==.Latina:BAAALgADCgUJBgAAAA==.Latinamaddog:BAABLgAECn8VAAIBAAYJCB7UKwB9AQABAAYJCB7UKwB9AQAAAA==.',
Le='Leijona:BAAALgAECgEJAQAAAA==.Lenard:BAAALgAECgMJBAAAAA==.Lenardo:BAAALgADCgMJAwAAAA==.Leröth:BAAALgAECgQJBAAAAA==.',
Li='Liandia:BAAALgADCgQJBAAAAA==.Likeatrain:BAABLgAECn8VAAIgAAYJ7AvlFADkAAAgAAYJ7AvlFADkAAAAAA==.Likhano:BAAALgAECgIJAgAAAA==.Lilstyx:BAABLgAECn8cAAMcAAgJJROBKADqAQAcAAgJJROBKADqAQADAAUJDwiPcADNAAAAAA==.Linds:BAABLgAECn8hAAMcAAgJTB2QHgAjAgAcAAgJTB2QHgAjAgADAAQJag3cdADEAAAAAA==.Lionhart:BAAALgADCgUJBQAAAA==.Lissari:BAAALgAECgYJDQAAAA==.Littlehoof:BAAALgADCgMJAwAAAA==.',
Lo='Lobowolf:BAAALgAECgYJDwAAAA==.Lorralen:BAAALgAECgcJBwAAAA==.',
Lt='Ltdanslegs:BAABLgAECn8fAAIHAAYJ/R4ODgCZAQAHAAYJ/R4ODgCZAQAAAA==.',
Lu='Luber:BAAALgAECgYJDAAAAA==.Lurtras:BAAALgAECgMJAwAAAA==.Luxu:BAABLgAECn8lAAIhAAgJwSRHBAAJAwAhAAgJwSRHBAAJAwAAAA==.',
Ly='Lysta:BAAALgADCgEJAQAAAA==.',
Ma='Malachron:BAAALgADCgQJBQAAAA==.Manbearcat:BAABLgAECn8WAAIiAAcJmSN0BwCZAgAiAAcJmSN0BwCZAgAAAA==.Marbleous:BAAALgAFFAIJAgAAAA==.Marina:BAAALgADCgcJCgAAAA==.',
Me='Meatcurtains:BAAALgAECgYJCQABLgAECgcJCwAPAAAAAA==.Mebeatwife:BAABLgAECn8WAAIQAAcJ6hmVEADxAQAQAAcJ6hmVEADxAQAAAA==.Melhina:BAAALgAECgUJBQABLgAECgcJHQAjAFAXAA==.Merle:BAABLgAECn8hAAMIAAcJQyF9CwD0AQAIAAcJgR99CwD0AQAMAAMJzxudEAAEAQAAAA==.Merredith:BAAALgADCgYJBgAAAA==.Metagriff:BAAALgADCgQJBAAAAA==.Metz:BAAALgAECgUJBgAAAA==.Mezu:BAAALgAECgQJBQAAAA==.',
Mi='Miakhalifa:BAAALgAECgEJAQAAAA==.Miquella:BAAALgAECgEJAgAAAA==.Miranza:BAAALgAECgIJBQAAAA==.Mistborn:BAABLgAECn8gAAQbAAcJNiQmCQC5AgAbAAcJNiQmCQC5AgAZAAQJ1RyFKQBMAQAVAAIJsBXEUQCEAAAAAA==.Mixy:BAAALgADCgQJBAAAAA==.',
Mo='Momoku:BAABLgAECn8ZAAIdAAYJJhVYCQBUAQAdAAYJJhVYCQBUAQAAAA==.Monkjamin:BAAALgAECgUJBwAAAA==.Moolimbo:BAABLgAECn8YAAICAAcJdhJMFgBiAQACAAcJdhJMFgBiAQAAAA==.Mooseboy:BAABLgAECn8YAAIdAAcJLR32AwD5AQAdAAcJLR32AwD5AQAAAA==.Mooserton:BAABLgAECn8hAAMDAAYJrA80UwAUAQADAAYJrA80UwAUAQAcAAUJcgt5KwDwAAAAAA==.Mootalstrike:BAABLgAECn8bAAIIAAcJ2g1uGQBlAQAIAAcJ2g1uGQBlAQAAAA==.Moshworm:BAABLgAECn8ZAAIEAAYJUQvURQAXAQAEAAYJUQvURQAXAQAAAA==.',
Mu='Murl:BAAALgAECgYJDQAAAA==.',
Mv='Mvp:BAAALgAECgEJAgAAAA==.',
My='Myfattotem:BAAALgAECgYJBgABLgAFFAQJCgATANYVAA==.',
Na='Nalaxx:BAAALgADCgkJDAAAAA==.',
Ne='Neeners:BAABLgAECn8UAAISAAYJVQPIQwDRAAASAAYJVQPIQwDRAAAAAA==.Neiran:BAAALgADCgEJAQAAAA==.Nelaphim:BAABLgAECn8nAAIXAAgJ1xkQHgD3AQAXAAgJ1xkQHgD3AQAAAA==.Neuroticaine:BAABLgAECn8hAAMVAAgJKBUJFQBYAQAVAAYJnxgJFQBYAQAZAAQJbwQaLgBfAAAAAA==.Nev:BAACLgAFFH8IAAMTAAMJsxROEgC5AAAYAAMJ6AUtGQDAAAATAAIJWB5OEgC5AAAuAAQKfyEAAxMACAnbIsgjAC8CABMABwkjIsgjAC8CABgABwmhHCUlAPwBAAAA.Nexassin:BAAALgAECgUJBgAAAA==.',
Ni='Nico:BAAALgAECggJEwAAAA==.Nimz:BAAALgAECgcJCwAAAA==.',
No='Noctrine:BAAALgADCgMJAwAAAA==.Nooblets:BAABLgAECn8YAAINAAcJwhwAJQDRAQANAAcJwhwAJQDRAQAAAA==.Noradia:BAAALgAECgMJBAAAAA==.Noxxidari:BAABLgAECn8YAAMLAAgJHg14QwDbAAALAAgJmAx4QwDbAAAWAAIJuRSvFgA/AAAAAA==.Noxxus:BAABLgAECn8aAAIJAAgJWReeDAD9AQAJAAgJWReeDAD9AQAAAA==.',
Nt='Ntajneeb:BAAALgAECgEJAQAAAA==.',
Ny='Nymphis:BAAALgADCgYJBgAAAA==.Nymz:BAAALgAECgMJAwABLgAECgcJCwAPAAAAAA==.Nyrunde:BAAALgAECgEJAQAAAA==.',
['Nô']='Nôwôrries:BAEALgAECgIJAwAAAA==.',
Ob='Oblivia:BAAALgAECgUJBQAAAA==.',
Of='Offended:BAAALgADCgYJBgAAAA==.',
Og='Oghmeister:BAAALgADCgUJBQAAAA==.',
Or='Orangeteddyd:BAAALgAECgcJBwABLgAFFAMJCAAcALAWAA==.Oratherah:BAABLgAFFH8GAAIhAAMJYhp3DwCpAAAhAAMJYhp3DwCpAAAAAA==.Orbs:BAAALgADCgYJBgAAAA==.Orchist:BAABLgAECn8WAAIIAAcJWB4lCAApAgAIAAcJWB4lCAApAgAAAA==.',
Oz='Ozôls:BAAALgAECgEJAQAAAA==.',
Pa='Pandromonk:BAAALgAECgMJAwAAAA==.Pawd:BAAALgAECgIJAgAAAA==.',
Pe='Periden:BAAALgAECgEJAgAAAA==.Pestilancé:BAABLgAECn8hAAIkAAgJ7AZuBgAdAQAkAAgJ7AZuBgAdAQAAAA==.Petco:BAAALgAECgEJAQAAAA==.Pewlimbo:BAAALgADCgcJFQABLgAECgcJGAACAHYSAA==.',
Pi='Piketricfoot:BAAALgADCgEJAQAAAA==.Pingpaung:BAAALgAECgUJCQABLgAECgcJDQAPAAAAAA==.Pitchblende:BAABLgAECn8bAAIcAAcJmhR5FgCdAQAcAAcJmhR5FgCdAQAAAA==.',
Po='Poeppsul:BAAALgADCgIJAgAAAA==.Polymorph:BAAALgADCgEJAwAAAA==.Pooqi:BAAALgAECgMJAwABLgAECggJFgAeAFYiAA==.Porthub:BAABLgAECn8WAAIXAAcJrAaHcAD4AAAXAAcJrAaHcAD4AAAAAA==.',
Pr='Protagoras:BAAALgAECgcJBQAAAA==.',
Pu='Purejoy:BAAALgAECgYJCwAAAA==.',
['Pü']='Püff:BAAALgADCgcJDAAAAA==.',
Qu='Quillz:BAAALgAECgIJAwAAAA==.Quison:BAAALgADCggJCAAAAA==.',
Ra='Ragnarr:BAAALgADCgIJAgAAAA==.Raiffee:BAAALgADCgkJHAAAAA==.Rajak:BAAALgAECgEJAQAAAA==.Rathibrew:BAACLgAFFH8KAAIlAAQJRSMLBACUAQAlAAQJRSMLBACUAQAuAAQKfykAAiUACQklI7sBAIwDACUACQklI7sBAIwDAAAA.',
Re='Reen:BAAALgADCgQJBAAAAA==.Reisil:BAAALgAECgYJCAAAAA==.Rellt:BAAALgADCgIJAgAAAA==.Remnants:BAABLgAECn8UAAIlAAYJihvDJwDIAQAlAAYJihvDJwDIAQAAAA==.Rendis:BAAALgADCgMJBAAAAA==.',
Rh='Rhydon:BAAALgAECgIJAgAAAA==.Rhypocalypse:BAAALgAECgMJBAAAAA==.',
Ri='Rika:BAAALgADCgYJBgAAAA==.Rikondolo:BAAALgADCgYJBwAAAA==.',
Ro='Rockyx:BAAALgAECgQJBAAAAA==.Roll:BAAALgADCgcJBwABLgAFFAEJAQAPAAAAAA==.',
Ru='Ruikha:BAAALgADCgYJCQAAAA==.Ruukia:BAABLgAECn8eAAIeAAgJ4BiGawC0AQAeAAgJ4BiGawC0AQABLgAECgcJGgAZAOYaAA==.',
['Rê']='Rêzìcå:BAAALgADCgkJCQAAAA==.',
Sa='Sacredtee:BAAALgAECggJDAAAAA==.Saelylria:BAAALgAECgQJBgAAAA==.Salezar:BAAALgAECgcJDgAAAA==.Sandoud:BAAALgAECggJEQAAAA==.Sapientia:BAABLgAECn8bAAIDAAcJKgUHWwABAQADAAcJKgUHWwABAQAAAA==.Satheion:BAAALgADCgMJAwAAAA==.Savagex:BAAALgADCgEJAQAAAA==.',
Sc='Scottkill:BAABLgAECn8hAAMcAAgJWhjHGQBFAgAcAAgJWhjHGQBFAgADAAEJ8g8nMgE/AAAAAA==.',
Se='Sebaux:BAAALgAECgMJAwAAAA==.Segur:BAAALgAECgYJDgAAAA==.Selenesul:BAABLgAECn8WAAMDAAcJvhExMwB1AQADAAcJvhExMwB1AQAJAAMJTAymNAB0AAAAAA==.Selyda:BAAALgADCgUJBgAAAA==.Senzie:BAABLgAECn8iAAIHAAgJHx6HBABiAgAHAAgJHx6HBABiAgABLgAFFAMJBQAHAMIJAA==.',
Sh='Shadowdrake:BAAALgAECgUJBQAAAA==.Shadowheàrt:BAAALgAECgQJBgAAAA==.Shadowshifty:BAAALgAECgQJCQAAAA==.Shadowtotem:BAAALgADCgkJDQAAAA==.Shaeen:BAAALgAECgUJBQAAAA==.Shagi:BAAALgAECgUJDAAAAA==.Shamdoodoo:BAAALgADCgcJDQAAAA==.Sharroz:BAABLgAECn8dAAMkAAcJiB1nAwBWAgAkAAcJiB1nAwBWAgAhAAQJRw7SGgCkAAAAAA==.Shftyuddrs:BAAALgAECgQJBAAAAA==.Shizuuku:BAABLgAECn8aAAMZAAcJ5hr3CQDvAQAZAAcJ5hr3CQDvAQAVAAEJJQKVaQAlAAAAAA==.Shoot:BAAALgAECgEJAQAAAA==.',
Si='Sineth:BAAALgADCgUJBgAAAA==.',
Sk='Skooda:BAABLgAECn8qAAICAAgJzxBaEQCWAQACAAgJzxBaEQCWAQAAAA==.Skyded:BAABLgAECn8bAAIeAAcJxhg+JwChAQAeAAcJxhg+JwChAQAAAA==.Skyknight:BAABLgAECn8eAAIIAAgJrRTXDQDVAQAIAAgJrRTXDQDVAQAAAA==.',
Sl='Slacker:BAAALgADCgMJAwAAAA==.Slapadwarf:BAABLgAECn8pAAIYAAgJyx7+AQBFAgAYAAgJyx7+AQBFAgAAAA==.',
Sn='Snapahead:BAAALgADCgIJAgAAAA==.',
So='Solastraza:BAAALgAECgkJCQAAAA==.Solcon:BAABLgAECn8bAAILAAgJChpXDgADAgALAAgJChpXDgADAgAAAA==.Solozolo:BAAALgAECgQJCAAAAA==.Somebodie:BAAALgAECgEJAQAAAA==.Soralas:BAAALgAECgIJAgAAAA==.',
Sp='Spaazz:BAAALgAECgcJEAAAAA==.Sparkwire:BAAALgADCgcJDQAAAA==.Spazzikins:BAAALgADCgUJBQAAAA==.',
St='Starweaver:BAAALgAECgUJEAAAAA==.Stellmarine:BAABLgAECn8dAAIEAAkJyxq+BgAwAgAEAAkJyxq+BgAwAgAAAA==.Stormjin:BAAALgADCgEJAQAAAA==.Strangecandy:BAAALgAECgQJBgAAAA==.Stratosphere:BAAALgADCgcJBwAAAA==.Störmrender:BAABLgAECn8bAAMmAAcJ0Ro8CABeAQAEAAYJBBrgKgCqAQAmAAYJLhU8CABeAQAAAA==.',
Sw='Swaazil:BAABLgAECn8cAAIXAAcJcg4sXwAeAQAXAAcJcg4sXwAeAQAAAA==.Swan:BAAALgAFFAEJAQAAAA==.Swishswish:BAAALgADCgYJBgAAAA==.',
Sy='Sybelybrook:BAAALgAECgYJDgAAAA==.',
Ta='Tahune:BAAALgADCgEJAgAAAA==.Taloriesh:BAAALgAECgYJEAAAAA==.Tanazir:BAEALgAECgUJDAAAAA==.Tarondria:BAAALgADCgcJCgAAAA==.Tashien:BAAALgAECgQJBAAAAA==.',
Te='Techytechy:BAAALgAECgYJDwAAAA==.Tennmage:BAAALgAECgEJAQAAAA==.',
Th='Thedhbrady:BAAALgADCgMJAwAAAA==.Thejonko:BAAALgADCgMJAwAAAA==.Thrúl:BAAALgADCggJCgAAAA==.Thundrtheigs:BAABLgAECn8ZAAIDAAgJqxlWRQATAgADAAgJqxlWRQATAgAAAA==.',
Ti='Tigermaster:BAAALgAECgQJBwAAAA==.Tilamano:BAABLgAECn8mAAQUAAgJHCXCAACIAgAUAAcJXSXCAACIAgAjAAcJqSKNAABnAgABAAYJJSSXPgATAgAAAA==.',
Tm='Tmntmikey:BAABLgAFFH8GAAMKAAMJvwrlEQDBAAAKAAMJvwrlEQDBAAAlAAMJbAGLHgCmAAAAAA==.',
To='Tohrnamental:BAAALgAECgQJBgAAAA==.Tohrniquet:BAAALgAECgYJBgAAAA==.Tomori:BAABLgAECn8XAAMTAAcJOCMaHwBLAgATAAcJciIaHwBLAgAYAAYJMSOwIQAVAgABLgAECggJCAAPAAAAAA==.Tonycheeks:BAAALgAECgIJAgAAAA==.Toogie:BAAALgAECgIJAwABLgAFFAEJAgAPAAAAAA==.Tookie:BAAALgADCgYJBgABLgAFFAEJAgAPAAAAAA==.Toophie:BAAALgADCgIJAgABLgAFFAEJAgAPAAAAAA==.Toopie:BAAALgAFFAEJAgAAAA==.',
Tr='Trellie:BAAALgAECgIJAgAAAA==.Trenve:BAABLgAECn8WAAIiAAYJWRz4GQCwAQAiAAYJWRz4GQCwAQAAAA==.Tryath:BAAALgAECgcJCwAAAA==.Tryggr:BAAALgADCgcJAgAAAA==.',
Tu='Turrtle:BAAALgADCgYJCwAAAA==.',
['Té']='Téchymoon:BAACLgAFFH8HAAIUAAMJxxORBgClAAAUAAMJxxORBgClAAAuAAQKfyQAAhQACQl+G2oCAOUCABQACQl+G2oCAOUCAAAA.',
Ug='Ugo:BAABLgAECn8XAAInAAgJFSA1AwD6AgAnAAgJFSA1AwD6AgAAAA==.',
Ul='Ultimapriest:BAAALgAECgMJBQAAAA==.',
Um='Umbrute:BAABLgAECn8gAAILAAkJsh1jEwDlAgALAAkJsh1jEwDlAgAAAA==.',
Ur='Urn:BAAALgADCgYJBgABLgAECgYJDgAPAAAAAA==.',
Va='Valcristo:BAABLgAECn8nAAIJAAgJJiT2AADLAgAJAAgJJiT2AADLAgAAAA==.Valros:BAAALgADCgEJAQAAAA==.Vanka:BAAALgADCgYJCwAAAA==.',
Ve='Vegean:BAAALgAECgIJAgABLgAECgYJEAAPAAAAAA==.Veloncis:BAAALgADCgUJBgAAAA==.Velrathion:BAAALgAECgcJCAAAAA==.Venelia:BAAALgADCgMJAwAAAA==.Venous:BAABLgAECn8bAAMNAAgJjRN0DwB3AQANAAcJbBF0DwB3AQAOAAUJ0xF/EwDJAAAAAA==.Vermasity:BAAALgADCgkJDAAAAA==.Vessar:BAAALgADCgkJCQAAAA==.Vestt:BAABLgAECn8hAAITAAgJ5xn9FADqAQATAAgJ5xn9FADqAQAAAA==.',
Vi='Vicariana:BAACLgAFFH8KAAIZAAQJrCUIBgCzAQAZAAQJrCUIBgCzAQAuAAQKfyMAAhkACQneJhEAAPkDABkACQneJhEAAPkDAAAA.Vichoot:BAAALgAECgYJCwAAAA==.Vidette:BAAALgADCgYJCwAAAA==.Viv:BAABLgAECn8jAAMJAAgJ5SIkAgBzAgAJAAcJLiQkAgBzAgADAAYJEiNVOQA+AgAAAA==.',
Vo='Vodmor:BAAALgAECgYJDQAAAA==.Vorog:BAAALgAECgYJBgAAAA==.',
Wa='Wackusbonk:BAAALgADCgIJAgAAAA==.Wallzi:BAAALgAECgYJEQABLgAECggJEAAPAAAAAA==.Warrendemon:BAACLgAFFH8IAAILAAQJbyQCEwAtAQALAAQJbyQCEwAtAQAuAAQKfyYAAwsACQmmJboBAMADAAsACQmmJboBAMADAAYAAwn9InNDAOkAAAAA.',
We='Weleieledis:BAAALgAECgcJCQAAAA==.',
Wi='Widerichard:BAABLgAECn8gAAIXAAkJUBOzUgA/AgAXAAkJUBOzUgA/AgAAAA==.Wildheart:BAAALgAECgYJCgAAAA==.Wilker:BAAALgADCgEJAQAAAA==.',
Wo='Wowbelly:BAABLgAECn8VAAIKAAcJghs8FgARAgAKAAcJghs8FgARAgAAAA==.Wowbellyjr:BAAALgAECgYJCwABLgAECgcJFQAKAIIbAA==.',
Xa='Xaanii:BAAALgADCgEJAQAAAA==.Xandon:BAAALgAECgQJBQAAAA==.',
Xo='Xonk:BAACLgAFFH8GAAIjAAQJUQrbAAD9AAAjAAQJUQrbAAD9AAAuAAQKfxoAAiMACAnPICwBAPECACMACAnPICwBAPECAAAA.',
Xs='Xsavage:BAAALgADCgEJAQAAAA==.',
Ye='Yerdaddy:BAAALgADCgcJDAABLgAECgYJEAAPAAAAAA==.',
Yo='Yoruwolf:BAAALgADCgMJAwAAAA==.Yoven:BAAALgAECgQJBwAAAA==.',
Yu='Yuuna:BAAALgADCggJDAAAAA==.',
Za='Zachsmack:BAAALgAECgYJCQAAAA==.Zanatos:BAAALgAECgQJBwAAAA==.Zaps:BAABLgAECn8WAAIoAAcJzR/aAgAuAgAoAAcJzR/aAgAuAgAAAA==.Zarayliel:BAAALgAECgIJAgAAAA==.Zarnic:BAAALgADCggJCQAAAA==.Zay:BAAALgAECgEJAQAAAA==.Zaíra:BAAALgAECgYJDgAAAA==.',
Ze='Zeahcur:BAAALgAECgIJAgAAAA==.Zeenab:BAAALgADCgUJBQAAAA==.Zelie:BAABLgAECn8jAAMQAAgJjQdMLQAPAQAQAAgJjQdMLQAPAQACAAUJsgQ3LQDLAAAAAA==.Zenreto:BAABLgAECn8hAAIOAAgJoxyVAQA6AgAOAAgJoxyVAQA6AgAAAA==.Zerce:BAAALgAECgEJAQAAAA==.',
Zk='Zkull:BAAALgAECgEJAQAAAA==.',
Zu='Zuggernaut:BAAALgADCgkJDwAAAA==.Zuggzugg:BAAALgADCgcJDAAAAA==.',
Zy='Zyria:BAACLgAFFH8KAAIXAAQJ/yAiDQCMAQAXAAQJ/yAiDQCMAQAuAAQKfyoAAhcACAnAJO8JAJ8CABcACAnAJO8JAJ8CAAAA.',
['Än']='Ängerberg:BAAALgAECgEJAQAAAA==.Änmoa:BAACLgAFFH8JAAIoAAQJ4BL0AQAFAQAoAAQJ4BL0AQAFAQAuAAQKfxwAAigACQl3IcMAAI8DACgACQl3IcMAAI8DAAAA.',
['Îl']='Îllîdan:BAAALgAECgQJBAAAAA==.',
['Ïn']='Ïnsane:BAABLgAECn8gAAMBAAgJGBmnEAAhAgABAAgJGBmnEAAhAgAUAAQJGwi/QQCuAAAAAA==.',
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

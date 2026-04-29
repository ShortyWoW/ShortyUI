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

local lookup = {'Warlock-Demonology','Shaman-Elemental','Paladin-Retribution','Druid-Balance','Evoker-Preservation','Rogue-Subtlety','DemonHunter-Havoc','Monk-Windwalker','Warrior-Fury','Paladin-Protection','DemonHunter-Devourer','Warrior-Arms','Rogue-Assassination','Unknown-Unknown','Shaman-Restoration','Evoker-Devastation','Hunter-BeastMastery','Warlock-Destruction','Priest-Shadow','DemonHunter-Vengeance','Mage-Frost','Hunter-Marksmanship','Mage-Arcane','Druid-Feral','DeathKnight-Unholy','Priest-Holy','Paladin-Holy','Rogue-Outlaw','Priest-Discipline','DeathKnight-Blood','Evoker-Augmentation','DeathKnight-Frost','Monk-Brewmaster','Druid-Guardian','Warlock-Affliction','Hunter-Survival','Monk-Mistweaver','Shaman-Enhancement',}
local provider = {region='US',realm='Exodar',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Abelladanger:BAAALgAECgUJCgAAAA==.Ablivion:BAABLgAECn8YAAIBAAkJuxFCOgAjAgABAAkJuxFCOgAjAgAAAA==.',
Ac='Achillesdk:BAAALgAECgMJAwAAAA==.',
Ad='Adeshae:BAAALgADCgEJAQAAAA==.Adeynalon:BAAALgAECgQJBQAAAA==.Adinne:BAAALgADCgkJHgABLgAECggJKAACAOoSAA==.',
Ae='Aestris:BAAALgADCgkJJQAAAA==.Aethira:BAAALgADCgEJAQAAAA==.',
Ah='Ahnaka:BAAALgADCgcJDgAAAA==.Ahron:BAABLgAECn8fAAIDAAgJTxuCCgDmAQADAAgJTxuCCgDmAQAAAA==.',
Ai='Aica:BAAALgAECgIJAgAAAA==.',
Al='Aleuseche:BAAALgADCgYJCwAAAA==.Alexr:BAAALgADCgMJAwAAAA==.Allarielle:BAAALgADCgEJAQAAAA==.',
Am='Amarantus:BAAALgADCgEJAQABLgAECggJIgAEACMcAA==.Amarndeus:BAAALgADCgMJAwAAAA==.',
An='Annihilation:BAAALgAECgEJAQAAAA==.Anorillian:BAAALgADCgkJCgAAAA==.Antàrès:BAAALgAECgYJCQAAAA==.',
Ao='Aotc:BAAALgAECgkJDgAAAA==.',
Aq='Aquaism:BAAALgADCgIJAgAAAA==.Aqulath:BAAALgAECgIJAgAAAA==.',
Ar='Arazensetal:BAABLgAECn8YAAIFAAYJHByBAgDqAQAFAAYJHByBAgDqAQAAAA==.Arctica:BAAALgAECgIJAgABLgAECgkJGAAGAHURAA==.Arker:BAAALgADCgIJAgAAAA==.',
As='Astralrisk:BAAALgADCgUJCAAAAA==.',
At='Athenä:BAABLgAECn8ZAAIHAAYJMB2dBQBqAQAHAAYJMB2dBQBqAQAAAA==.',
Au='Aubrii:BAAALgADCgYJCAAAAA==.Aukatsang:BAACLgAFFH8GAAIIAAMJqRkoAwADAQAIAAMJqRkoAwADAQAuAAQKfyMAAggACQnBImABAKMDAAgACQnBImABAKMDAAAA.Aureuzeth:BAAALgAECgcJDgAAAA==.',
Az='Azymor:BAAALgADCgMJAwAAAA==.',
Ba='Baddy:BAABLgAECn8dAAIJAAgJpBwIFQClAgAJAAgJpBwIFQClAgAAAA==.Bagabo:BAACLgAFFH8FAAIIAAMJ3xQkBwAFAQAIAAMJ3xQkBwAFAQAuAAQKfxwAAggACAndHowJAN8CAAgACAndHowJAN8CAAAA.Baladeva:BAABLgAECn8ZAAIKAAYJJRoQEgCoAQAKAAYJJRoQEgCoAQAAAA==.Bamberram:BAAALgAECgQJBgAAAA==.Bamboozle:BAAALgADCgUJAgAAAA==.Barrak:BAAALgADCgEJAQABLgAECggJHwADAE8bAA==.Bartz:BAAALgAECgkJBAAAAA==.Bau:BAAALgADCgEJAQAAAA==.',
Be='Beersnob:BAAALgAECgYJDwAAAA==.Benjam:BAABLgAECn8lAAILAAcJkSTYCADlAQALAAcJkSTYCADlAQAAAA==.Benyo:BAAALgADCgIJAgAAAA==.',
Bi='Bigmikeyg:BAABLgAECn8ZAAIDAAYJKQyCIgAhAQADAAYJKQyCIgAhAQAAAA==.Bigsteve:BAABLgAECn8ZAAMMAAYJERs7BQA8AQAJAAYJERvlMwDaAQAMAAYJBxE7BQA8AQAAAA==.',
Bl='Blanket:BAABLgAFFH8GAAMGAAMJNwiRDwD0AAAGAAMJqQWRDwD0AAANAAEJ0QkoAwBXAAAAAA==.Blitzo:BAAALgADCgMJAwAAAA==.',
Bo='Bottomdps:BAAALgAECgIJAgABLgAECgQJDgAOAAAAAA==.',
Bu='Buttonmashèr:BAAALgADCgUJBQAAAA==.',
['Bè']='Bèyork:BAABLgAECn8WAAIPAAcJ5hx6BwDXAQAPAAcJ5hx6BwDXAQAAAA==.',
['Bõ']='Bõnd:BAAALgADCgEJAQAAAA==.',
Ca='Caedan:BAAALgADCgcJCgAAAA==.Caedreth:BAABLgAECn8WAAMFAAgJawX3IgBhAQAFAAgJawX3IgBhAQAQAAMJGgi7MgCAAAAAAA==.Calizon:BAAALgAECgYJCwAAAA==.Camc:BAAALgAECgQJBgAAAA==.Canowhoopass:BAAALgAECgYJDwAAAA==.Cardano:BAAALgADCggJDQAAAA==.Carine:BAAALgAECgMJBAAAAA==.',
Ce='Cerassin:BAACLgAFFH8HAAILAAMJMA+RLACUAAALAAMJMA+RLACUAAAuAAQKfysAAgsACQkfH+4PAP8CAAsACQkfH+4PAP8CAAAA.Cereas:BAABLgAECn8WAAIHAAYJUxxLGwDnAQAHAAYJUxxLGwDnAQAAAA==.',
Ch='Challincia:BAAALgADCgUJBgAAAA==.Cherrish:BAAALgADCgMJBAAAAA==.Chuckrutis:BAABLgAECn8UAAIQAAYJUh5rDAAUAgAQAAYJUh5rDAAUAgAAAA==.',
Cl='Cliché:BAAALgADCgkJGQAAAA==.Cloudzz:BAAALgAECgEJAQAAAA==.Clukdogg:BAACLgAFFH8GAAIRAAMJUw0zCQD0AAARAAMJUw0zCQD0AAAuAAQKfyIAAhEACQnlIHYCAHEDABEACQnlIHYCAHEDAAAA.',
Co='Combination:BAABLgAECn8ZAAISAAYJ1RvsAQCOAQASAAYJ1RvsAQCOAQABLgAFFAUJDAADAEEbAA==.Constrace:BAAALgADCgkJFgAAAA==.Corvenall:BAABLgAECn8jAAIQAAcJugrtGgBaAQAQAAcJugrtGgBaAQAAAA==.Cowboytroy:BAAALgAECgEJAQAAAA==.',
Cr='Crashpad:BAAALgAECgIJAgAAAA==.Crossbow:BAABLgAECn8iAAIRAAgJ1CEeDwDCAgARAAgJ1CEeDwDCAgAAAA==.',
Ct='Cthulha:BAAALgADCgEJAQAAAA==.',
Da='Dabbernath:BAAALgADCgMJAwAAAA==.Dandaraber:BAAALgADCgMJAwAAAA==.Dante:BAAALgAECgIJAwABLgAECgYJDQAOAAAAAA==.Darkluster:BAAALgADCgEJAQAAAA==.Darknesmonk:BAAALgAECgQJBAAAAA==.Darkrune:BAAALgADCgkJCQAAAA==.Darÿ:BAAALgADCggJEwAAAA==.Davand:BAAALgADCgcJBwAAAA==.Dawncloud:BAAALgADCgkJFgAAAA==.',
De='Deathbcmesyu:BAAALgAECgYJEAAAAA==.Deathbreathh:BAAALgAECgQJBAAAAA==.Deathweilder:BAAALgAECgQJCAAAAA==.Deloaofnova:BAAALgAECgMJAwAAAA==.Demorian:BAAALgAECgEJAQABLgAECgYJFAATAO0LAA==.Deondre:BAAALgAECgIJAgAAAA==.Deucali:BAAALgADCgEJAQAAAA==.Devilsmight:BAAALgAECgQJBwAAAA==.',
Di='Diehappy:BAAALgADCgcJFAAAAA==.Dillie:BAAALgADCgMJAwAAAA==.Disguize:BAAALgAECgQJBQAAAA==.',
Do='Dompal:BAAALgAECgIJBgABLgAFFAMJBgAUAOgYAA==.Dozy:BAAALgADCgkJDQAAAA==.',
Dr='Draatoo:BAAALgAECgMJAwAAAA==.Dreamm:BAAALgAECggJCAABLgAFFAgJGQAVAEolAA==.Drovinos:BAAALgADCgkJEQAAAA==.Drybonez:BAAALgAECgYJDwAAAA==.Drylie:BAACLgAFFH8GAAMRAAMJvR4mBgAaAQARAAMJBxwmBgAaAQAWAAEJwBmHJQBSAAAuAAQKfyMAAxYACQkFJbkJAAUDABYACAmdIrkJAAUDABEAAwk+JLwWAEYBAAAA.Dràgonkíng:BAAALgAECgUJCAAAAA==.',
Dt='Dtinnel:BAAALgAECgYJCwABLgAFFAEJAQAOAAAAAA==.',
Du='Dumbledussy:BAABLgAECn8UAAITAAYJ7QvbMgBPAQATAAYJ7QvbMgBPAQAAAA==.',
Ed='Edanor:BAAALgADCgEJAQABLgAECgcJDgAOAAAAAA==.',
Eg='Ego:BAABLgAECn8dAAIJAAgJkyKrAAC7AgAJAAgJkyKrAAC7AgAAAA==.',
El='Elandra:BAAALgAECgcJCwAAAA==.Elrondo:BAAALgADCgQJBAAAAA==.',
Em='Emela:BAAALgAECgQJBAAAAA==.Emmarree:BAAALgADCgUJBQABLgAECgYJFQAVAHciAA==.Emmone:BAAALgAECgMJAwAAAA==.',
Ev='Evelapix:BAAALgAECgEJAQAAAA==.Evilrook:BAAALgADCgEJAQAAAA==.Evocamc:BAAALgADCgEJAQAAAA==.',
Ex='Exacerbator:BAAALgAECgEJAQAAAA==.',
Fa='Faker:BAAALgAECgYJCwAAAA==.Farglight:BAAALgAECgQJBAAAAA==.Faunna:BAABLgAECn8iAAIEAAgJIxzoAwDtAQAEAAgJIxzoAwDtAQAAAA==.',
Fe='Felaz:BAABLgAECn8aAAIXAAcJfB/2AgBTAgAXAAcJfB/2AgBTAgAAAA==.Fericus:BAAALgAECgIJAgAAAA==.',
Fi='Fingerguns:BAAALgAECgYJEQAAAA==.Fionaa:BAABLgAECn8dAAMBAAkJMAXwEgB5AQABAAkJBQXwEgB5AQASAAEJsAfgeAAqAAAAAA==.Fiyona:BAAALgADCgkJCgAAAA==.',
Fl='Flogger:BAAALgADCgcJBwAAAA==.Flooraan:BAAALgADCgMJAwAAAA==.Floortank:BAAALgAECgUJCQAAAA==.',
Fo='Forladyranni:BAAALgADCgEJAQAAAA==.Fosforin:BAAALgAECgEJAQAAAA==.',
Fr='Freeteddyp:BAAALgAFFAIJBAAAAA==.Frikilatar:BAAALgAECgEJAQAAAA==.Frostyhatesu:BAEALgADCgMJAwABLgAECgIJAwAOAAAAAA==.Frrank:BAACLgAFFH8GAAIMAAMJqCRiAQA6AQAMAAMJqCRiAQA6AQAuAAQKfyQAAgwACQlvJF4AALQDAAwACQlvJF4AALQDAAAA.',
Fu='Fullerene:BAAALgADCgMJBgAAAA==.',
Ga='Galcain:BAABLgAECn8cAAMRAAgJAiL3BwARAwARAAgJvSH3BwARAwAWAAMJVBq0YAC+AAAAAA==.',
Gh='Ghostmain:BAAALgADCgMJBAABLgAECgUJCgAOAAAAAA==.',
Gi='Girandzimm:BAAALgAECgEJAQAAAA==.',
Gl='Glacia:BAABLgAECn8YAAIVAAcJPxIDhgDFAQAVAAcJPxIDhgDFAQAAAA==.Glaivizzon:BAAALgAECgIJAwAAAA==.',
Go='Gorizarev:BAAALgAECgQJCAAAAA==.',
Gr='Grogtar:BAAALgADCgMJAwAAAA==.Grumandel:BAABLgAECn8ZAAIYAAYJMhBzBQAuAQAYAAYJMhBzBQAuAQAAAA==.',
Gu='Gudetama:BAAALgAECgYJDwAAAA==.Guhlinda:BAAALgADCgcJBwAAAA==.Gunthor:BAAALgAECgEJAQAAAA==.',
Ha='Haidie:BAAALgADCgEJAQAAAA==.Hakur:BAABLgAECn8aAAIDAAgJoh16CQDzAQADAAgJoh16CQDzAQAAAA==.Hamahara:BAAALgADCgMJAwAAAA==.Hanma:BAACLgAFFH8IAAIZAAQJOwjNEADvAAAZAAQJOwjNEADvAAAuAAQKfycAAhkACQkVHgwsAIgCABkACQkVHgwsAIgCAAAA.Harribel:BAAALgAECgYJEwAAAA==.',
He='Heliodorus:BAAALgADCgIJAgAAAA==.Hercey:BAAALgADCgYJBgAAAA==.',
Hi='Higheleazar:BAAALgADCgYJBgAAAA==.Hiroki:BAAALgAECgcJCwAAAA==.Hitachitotem:BAACLgAFFH8JAAICAAMJaAjsBwDYAAACAAMJaAjsBwDYAAAuAAQKfxYAAgIACAmPGlkaAEACAAIACAmPGlkaAEACAAAA.Hizzon:BAAALgADCgcJCAAAAA==.',
Ho='Holyphatso:BAAALgADCgMJAwABLgAECgcJFwAaAPwgAA==.',
Hy='Hyperíon:BAAALgAECgEJAQAAAA==.Hyun:BAAALgAECgIJAgAAAA==.',
Ic='Icies:BAAALgAECgYJDwAAAA==.',
In='Inflikted:BAAALgAECgYJDAAAAA==.Interwebz:BAAALgAECgYJBgAAAA==.Intra:BAAALgAECgMJBAAAAA==.',
Ir='Iristia:BAAALgADCgcJAgAAAA==.',
Je='Jehannum:BAABLgAECn8YAAICAAYJbQ2CEgDsAAACAAYJbQ2CEgDsAAAAAA==.Jessira:BAAALgAECgYJDgAAAA==.Jezabel:BAAALgAECgUJBgAAAA==.',
Jo='Jomjiggado:BAAALgADCgUJBQAAAA==.Jonahheal:BAAALgAECgUJBwABLgAFFAMJCAAPAB8bAA==.',
Ju='Juliana:BAAALgADCgMJAwAAAA==.',
['Jú']='Júdâs:BAABLgAECn8aAAITAAgJNRbsBADHAQATAAgJNRbsBADHAQAAAA==.',
Ka='Kaeläni:BAAALgAECgQJBwAAAA==.Kalek:BAAALgAECgEJAQAAAA==.Kaljrak:BAAALgAECgUJCgAAAA==.Katarena:BAABLgAECn8XAAIbAAcJ6AcGTgBAAQAbAAcJ6AcGTgBAAQAAAA==.Kathyra:BAAALgAECgYJCwAAAA==.Kavax:BAAALgAECgYJDwAAAA==.',
Ke='Keeller:BAACLgAFFH8HAAIDAAQJ2gaiBQA2AQADAAQJ2gaiBQA2AQAuAAQKfysAAgMACAnsHFYoAIQCAAMACAnsHFYoAIQCAAAA.Kentyr:BAABLgAECn8XAAMGAAcJgwvCLQCTAQAGAAcJgwvCLQCTAQAcAAIJZwGCDgA0AAAAAA==.',
Kh='Khasket:BAAALgAECgYJDQAAAA==.',
Ki='Kigahen:BAAALgADCgYJBgAAAA==.Kinký:BAABLgAECn8XAAIJAAgJ6w6iNQDSAQAJAAgJ6w6iNQDSAQABLgAECgIJAwAOAAAAAA==.Kiraelis:BAAALgAECgYJEQAAAA==.Kivea:BAAALgAECgYJCwAAAA==.',
Kl='Klah:BAAALgADCgQJBAAAAA==.',
Ko='Konagda:BAAALgADCgcJDQAAAA==.Korvoh:BAABLgAECn8ZAAMdAAYJhhrhBgCHAQAdAAYJkxjhBgCHAQAaAAMJUxd4XQC8AAAAAA==.',
Kr='Kringe:BAABLgAECn8ZAAICAAYJNyQBBQDOAQACAAYJNyQBBQDOAQAAAA==.',
Ku='Kumonk:BAAALgAECgQJBwAAAA==.',
Ky='Kyloris:BAAALgAECgMJBQAAAA==.',
['Kä']='Kämik:BAABLgAECn8ZAAIRAAYJIh8xKwAIAgARAAYJIh8xKwAIAgAAAA==.',
['Kì']='Kìn:BAAALgAECgMJBQAAAA==.',
La='Lampion:BAAALgAECgcJEwAAAA==.Lasstchance:BAAALgADCgkJHgAAAA==.Latina:BAAALgADCgUJBgAAAA==.Latinamaddog:BAAALgAECgYJEAAAAA==.',
Le='Leijona:BAAALgAECgEJAQAAAA==.Lenard:BAAALgAECgIJAwAAAA==.Lenardo:BAAALgADCgMJAwAAAA==.Leröth:BAAALgAECgQJBAAAAA==.',
Li='Liandia:BAAALgADCgQJBAAAAA==.Likeatrain:BAAALgAECgUJDwAAAA==.Likhano:BAAALgAECgIJAgAAAA==.Lilstyx:BAABLgAECn8XAAIbAAgJJRN9KADqAQAbAAgJJRN9KADqAQAAAA==.Linds:BAABLgAECn8dAAMbAAcJKRySHgAjAgAbAAcJKRySHgAjAgADAAQJag1UMwDNAAAAAA==.Lionhart:BAAALgADCgUJBQAAAA==.Lissari:BAAALgAECgQJBwAAAA==.Littlehoof:BAAALgADCgMJAwAAAA==.',
Lo='Lobowolf:BAAALgAECgYJCwAAAA==.Lorralen:BAAALgAECgcJBwAAAA==.',
Lt='Ltdanslegs:BAABLgAECn8ZAAIIAAYJ/R6rBQCUAQAIAAYJ/R6rBQCUAQAAAA==.',
Lu='Luber:BAAALgAECgUJBwAAAA==.Lurtras:BAAALgAECgMJAwAAAA==.Luxu:BAABLgAECn8cAAIeAAgJdSJDBAAJAwAeAAgJdSJDBAAJAwAAAA==.',
Ly='Lysta:BAAALgADCgEJAQAAAA==.',
Ma='Malachron:BAAALgADCgQJBQAAAA==.Manbearcat:BAAALgAECgYJDwAAAA==.Marbleous:BAAALgAECgQJDgAAAA==.Marina:BAAALgADCgcJBwAAAA==.',
Me='Meatcurtains:BAAALgAECgYJCQAAAA==.Mebeatwife:BAAALgAECgYJEgAAAA==.Merle:BAABLgAECn8VAAIJAAYJMBxUNwDKAQAJAAYJMBxUNwDKAQAAAA==.Merredith:BAAALgADCgYJBgAAAA==.Metagriff:BAAALgADCgQJBAAAAA==.Metz:BAAALgADCgkJCgAAAA==.Mezu:BAAALgAECgQJBQAAAA==.',
Mi='Miquella:BAAALgAECgEJAQAAAA==.Miranza:BAAALgAECgIJAwAAAA==.Mistborn:BAABLgAECn8gAAQaAAcJNiQlCQC5AgAaAAcJNiQlCQC5AgAdAAQJ1RyFKQBMAQATAAIJsBW9UQCEAAAAAA==.Mixy:BAAALgADCgQJBAAAAA==.',
Mo='Momoku:BAAALgAECgYJEwAAAA==.Monkjamin:BAAALgAECgUJBwAAAA==.Moolimbo:BAAALgAECgYJEwAAAA==.Mooseboy:BAAALgAECgYJEwAAAA==.Mooserton:BAABLgAECn8XAAMDAAYJrQzzpgAzAQADAAYJrQzzpgAzAQAbAAEJDQEAAAAAAAAAAA==.Mootalstrike:BAABLgAECn8UAAIJAAYJvw5SVABZAQAJAAYJvw5SVABZAQAAAA==.Moshworm:BAAALgAECgYJEwAAAA==.',
Mu='Murl:BAAALgAECgYJDQAAAA==.',
Mv='Mvp:BAAALgADCgcJDgAAAA==.',
Na='Nalaxx:BAAALgADCgkJDAAAAA==.Natsumi:BAAALgADCgkJEQAAAA==.',
Ne='Neeners:BAABLgAECn8UAAIfAAYJVQPDQwDRAAAfAAYJVQPDQwDRAAAAAA==.Neiran:BAAALgADCgEJAQAAAA==.Nelaphim:BAABLgAECn8fAAIVAAcJNBkYFACgAQAVAAcJNBkYFACgAQAAAA==.Neuroticaine:BAABLgAECn8ZAAMTAAYJVBgsDAAwAQATAAYJVBgsDAAwAQAdAAIJcwELVgA1AAAAAA==.Nev:BAACLgAFFH8IAAMRAAMJsxRKEgC5AAAWAAMJ6AUfGQDAAAARAAIJWB5KEgC5AAAuAAQKfx8AAxEACAl3IcojAC8CABEABwmDIMojAC8CABYABwmhHCQlAPwBAAAA.Nexassin:BAAALgAECgQJBAAAAA==.',
Ni='Nico:BAAALgAECgYJDQAAAA==.Nimz:BAAALgAECgUJBgABLgAECgYJCQAOAAAAAA==.',
No='Noctrine:BAAALgADCgMJAwAAAA==.Nooblets:BAABLgAECn8VAAIGAAYJXRwAJQDRAQAGAAYJXRwAJQDRAQAAAA==.Noradia:BAAALgAECgMJBAAAAA==.Noxxidari:BAAALgAECgYJEQAAAA==.Noxxus:BAABLgAECn8YAAIKAAgJYxacDAD9AQAKAAgJYxacDAD9AQAAAA==.',
Nt='Ntajneeb:BAAALgAECgEJAQAAAA==.',
Ny='Nymz:BAAALgAECgMJAwABLgAECgYJCQAOAAAAAA==.',
['Nô']='Nôwôrries:BAEALgAECgIJAwAAAA==.',
Ob='Oblivia:BAAALgAECgUJBQAAAA==.',
Og='Oghmeister:BAAALgADCgUJBQAAAA==.',
Or='Oratherah:BAAALgAFFAMJAwAAAA==.Orbs:BAAALgADCgYJBgAAAA==.Orchist:BAAALgAECgYJDwAAAA==.',
Oz='Ozôls:BAAALgAECgEJAQAAAA==.',
Pa='Pandromonk:BAAALgAECgMJAwAAAA==.Pawd:BAAALgAECgIJAgAAAA==.',
Pe='Periden:BAAALgAECgEJAgAAAA==.Pestilancé:BAABLgAECn8ZAAIgAAYJugeRCwADAQAgAAYJugeRCwADAQAAAA==.Petco:BAAALgAECgEJAQAAAA==.Pewlimbo:BAAALgADCgcJFQABLgAECgYJEwAOAAAAAA==.',
Pi='Piketricfoot:BAAALgADCgEJAQAAAA==.Pingpaung:BAAALgAECgUJCQABLgAECgYJBgAOAAAAAA==.Pitchblende:BAABLgAECn8WAAIbAAYJ3hQREwAQAQAbAAYJ3hQREwAQAQAAAA==.',
Po='Poeppsul:BAAALgADCgIJAgAAAA==.Polymorph:BAAALgADCgEJAwAAAA==.Pooqi:BAAALgAECgMJAwABLgAECggJFQAZAKEhAA==.Porthub:BAAALgAECgYJEgAAAA==.',
Pr='Protagoras:BAAALgAECgcJAwAAAA==.',
Pu='Purejoy:BAAALgAECgQJCAAAAA==.',
['Pü']='Püff:BAAALgADCgcJDAAAAA==.',
Qu='Quison:BAAALgADCggJCAAAAA==.',
Ra='Raiffee:BAAALgADCgkJHAAAAA==.Rajak:BAAALgAECgEJAQAAAA==.Rathibrew:BAACLgAFFH8GAAIhAAMJrCHgBQAZAQAhAAMJrCHgBQAZAQAuAAQKfyQAAiEACQklI70BAIwDACEACQklI70BAIwDAAAA.',
Re='Reen:BAAALgADCgQJBAAAAA==.Reisil:BAAALgAECgYJCAAAAA==.Rellt:BAAALgADCgIJAgAAAA==.Remnants:BAAALgAECgYJEgAAAA==.Rendis:BAAALgADCgMJBAAAAA==.',
Rh='Rhydon:BAAALgADCgYJBgAAAA==.Rhypocalypse:BAAALgAECgEJAQAAAA==.',
Ri='Rika:BAAALgADCgYJBgAAAA==.Rikondolo:BAAALgADCgYJBwAAAA==.',
Ro='Rockyx:BAAALgAECgMJAwAAAA==.Roll:BAAALgADCgcJBwABLgAECgcJHAAeALkkAA==.',
Ru='Ruikha:BAAALgADCgYJCQAAAA==.Ruukia:BAABLgAECn8bAAIZAAcJaReJawC0AQAZAAcJaReJawC0AQABLgAFFAEJAQAOAAAAAA==.',
['Rê']='Rêzìcå:BAAALgADCgkJCQAAAA==.',
Sa='Sacredtee:BAAALgAECggJCAAAAA==.Saelylria:BAAALgAECgMJAwAAAA==.Salezar:BAAALgAECgcJDgAAAA==.Sandoud:BAAALgAECgcJBwAAAA==.Sapientia:BAAALgAECgYJEQAAAA==.Savagex:BAAALgADCgEJAQAAAA==.',
Sc='Scottkill:BAABLgAECn8hAAMbAAgJWhjHGQBFAgAbAAgJWhjHGQBFAgADAAEJ8g8NMgE/AAAAAA==.',
Se='Sebaux:BAAALgAECgEJAQAAAA==.Segur:BAAALgAECgYJDQAAAA==.Selenesul:BAAALgAECgYJDwAAAA==.Senzie:BAABLgAECn8cAAIIAAgJEhoqAwDwAQAIAAgJEhoqAwDwAQABLgAECggJIAAIAFwdAA==.',
Sh='Shadowheàrt:BAAALgAECgIJAgAAAA==.Shadowshifty:BAAALgAECgQJBQAAAA==.Shadowtotem:BAAALgADCgkJDQAAAA==.Shaeen:BAAALgAECgUJBQAAAA==.Shagi:BAAALgAECgUJCQAAAA==.Shamdoodoo:BAAALgADCgcJDQAAAA==.Sharroz:BAABLgAECn8ZAAMgAAcJiB1lAwBWAgAgAAcJiB1lAwBWAgAeAAEJAhjwQABJAAAAAA==.Shftyuddrs:BAAALgAECgQJBAAAAA==.Shizuuku:BAAALgAFFAEJAQAAAA==.Shoot:BAAALgAECgEJAQAAAA==.',
Si='Sineth:BAAALgADCgUJBgAAAA==.',
Sk='Skooda:BAABLgAECn8iAAICAAgJOwoXCwBKAQACAAgJOwoXCwBKAQAAAA==.Skyded:BAABLgAECn8WAAIZAAYJhBnmcACmAQAZAAYJhBnmcACmAQAAAA==.Skyknight:BAABLgAECn8WAAIJAAcJBxfxCwBhAQAJAAcJBxfxCwBhAQAAAA==.',
Sl='Slacker:BAAALgADCgMJAwAAAA==.Slapadwarf:BAABLgAECn8hAAIWAAgJwh7tAAAxAgAWAAgJwh7tAAAxAgAAAA==.',
Sn='Snapahead:BAAALgADCgIJAgAAAA==.',
So='Solastraza:BAAALgAECgkJAgAAAA==.Solcon:BAABLgAECn8ZAAILAAYJMRzYEQB0AQALAAYJMRzYEQB0AQAAAA==.Solozolo:BAAALgAECgQJCAAAAA==.Somebodie:BAAALgAECgEJAQAAAA==.Soralas:BAAALgADCgQJAQAAAA==.',
Sp='Spaazz:BAAALgAECgYJCwAAAA==.Sparkwire:BAAALgADCgYJBgAAAA==.Spazzikins:BAAALgADCgUJBQAAAA==.',
St='Starweaver:BAAALgAECgQJCwAAAA==.Stellmarine:BAABLgAECn8bAAIEAAgJqho3FwBSAgAEAAgJqho3FwBSAgAAAA==.Stormjin:BAAALgADCgEJAQAAAA==.Strangecandy:BAAALgAECgQJBAAAAA==.Stratosphere:BAAALgADCgcJBwAAAA==.Störmrender:BAABLgAECn8WAAMEAAYJJxrjKgCqAQAEAAYJ4RnjKgCqAQAiAAUJOBElBwDIAAAAAA==.',
Sw='Swaazil:BAABLgAECn8cAAIVAAcJcg5WKQAoAQAVAAcJcg5WKQAoAQAAAA==.Swan:BAAALgAFFAEJAQAAAA==.Swishswish:BAAALgADCgYJBgAAAA==.',
Sy='Sybelybrook:BAAALgAECgQJBwAAAA==.',
Ta='Tahune:BAAALgADCgEJAgAAAA==.Taloriesh:BAAALgAECgYJDAAAAA==.Tanazir:BAEALgAECgUJCQAAAA==.Tarondria:BAAALgADCgcJCgAAAA==.Tashien:BAAALgAECgIJAgAAAA==.',
Te='Techytechy:BAAALgAECgYJCQAAAA==.Tennmage:BAAALgAECgEJAQAAAA==.',
Th='Thedhbrady:BAAALgADCgMJAwAAAA==.Thejonko:BAAALgADCgMJAwAAAA==.Thrúl:BAAALgADCgYJCAAAAA==.Thundrtheigs:BAABLgAECn8XAAIDAAcJ0BhaRQATAgADAAcJ0BhaRQATAgAAAA==.',
Ti='Tigermaster:BAAALgAECgQJBwAAAA==.Tilamano:BAABLgAECn8eAAQSAAcJtyU4AACSAgASAAcJXSU4AACSAgABAAUJ0SSYPgATAgAjAAUJziRIBgD4AQAAAA==.',
Tm='Tmntmikey:BAAALgAFFAMJAwAAAA==.',
To='Tohrnamental:BAAALgAECgQJBgAAAA==.Tohrniquet:BAAALgAECgYJBgAAAA==.Tomori:BAABLgAECn8XAAMRAAcJOCNICQDUAQAWAAYJMSOwIQAVAgARAAcJciJICQDUAQAAAA==.Tonycheeks:BAAALgAECgIJAgAAAA==.Toogie:BAAALgAECgEJAQABLgAECggJDwAOAAAAAA==.Tookie:BAAALgADCgYJBgABLgAECggJDwAOAAAAAA==.Toophie:BAAALgADCgIJAgABLgAECggJDwAOAAAAAA==.Toopie:BAAALgAECggJDwAAAA==.',
Tr='Trellie:BAAALgAECgIJAgAAAA==.Trenve:BAAALgAECgYJEAAAAA==.Tryath:BAAALgAECgcJCgAAAA==.Tryggr:BAAALgADCgcJAgAAAA==.',
Tu='Turrtle:BAAALgADCgYJCwAAAA==.',
['Té']='Téchymoon:BAACLgAFFH8GAAISAAMJxxPWAAD6AAASAAMJxxPWAAD6AAAuAAQKfyQAAhIACQl+G2sCAOUCABIACQl+G2sCAOUCAAAA.',
Ug='Ugo:BAABLgAECn8VAAIkAAgJ9x40AwD6AgAkAAgJ9x40AwD6AgAAAA==.',
Ul='Ultimapriest:BAAALgAECgEJAgAAAA==.',
Um='Umbrute:BAABLgAECn8bAAILAAgJHSBbEwDlAgALAAgJHSBbEwDlAgAAAA==.',
Ur='Urn:BAAALgADCgYJBgABLgAECgQJBwAOAAAAAA==.',
Va='Valcristo:BAABLgAECn8fAAIKAAcJySI2AQA3AgAKAAcJySI2AQA3AgAAAA==.Valros:BAAALgADCgEJAQAAAA==.Vanka:BAAALgADCgYJCwAAAA==.',
Ve='Vegean:BAAALgADCgcJCAABLgAECgYJEAAOAAAAAA==.Veloncis:BAAALgADCgUJBgAAAA==.Velrathion:BAAALgAECgYJBgAAAA==.Venelia:BAAALgADCgMJAwAAAA==.Venous:BAABLgAECn8XAAMGAAcJZxVNCQBDAQAGAAYJOBNNCQBDAQANAAMJXRaAEwDJAAAAAA==.Vermasity:BAAALgADCgkJCQAAAA==.Vessar:BAAALgADCgkJCQAAAA==.Vestt:BAABLgAECn8ZAAIRAAYJ5hmNPgC1AQARAAYJ5hmNPgC1AQAAAA==.',
Vi='Vicariana:BAACLgAFFH8GAAIdAAMJviSHBAA5AQAdAAMJviSHBAA5AQAuAAQKfyMAAh0ACQneJhEAAPoDAB0ACQneJhEAAPoDAAAA.Vichoot:BAAALgAECgUJBQAAAA==.Vidette:BAAALgADCgUJBQAAAA==.Viv:BAABLgAECn8jAAMKAAgJ5SK1AAB5AgAKAAcJLiS1AAB5AgADAAYJEiNcOQA+AgAAAA==.',
Vo='Vodmor:BAAALgAECgQJBwAAAA==.Vorog:BAAALgAECgEJAQAAAA==.',
Wa='Wallzi:BAAALgAECgYJDgABLgAECggJEAAOAAAAAA==.Warrendemon:BAACLgAFFH8GAAILAAMJLSNiCAAtAQALAAMJLSNiCAAtAQAuAAQKfyQAAwsACQmmJbsBAMADAAsACQmmJbsBAMADAAcAAwn9Im5DAOkAAAAA.',
We='Weleieledis:BAAALgAECgEJAQAAAA==.',
Wi='Widerichard:BAABLgAECn8bAAIVAAgJxBS8UgA/AgAVAAgJxBS8UgA/AgAAAA==.Wildheart:BAAALgAECgYJCgAAAA==.Wilker:BAAALgADCgEJAQAAAA==.',
Wo='Wowbelly:BAABLgAECn8VAAIlAAcJexs3FgATAgAlAAcJexs3FgATAgAAAA==.Wowbellyjr:BAAALgAECgYJCwABLgAECgcJFQAlAHsbAA==.',
Xa='Xaanii:BAAALgADCgEJAQAAAA==.Xandon:BAAALgADCggJFgAAAA==.',
Xo='Xonk:BAABLgAECn8aAAIjAAgJzyAsAQDxAgAjAAgJzyAsAQDxAgAAAA==.',
Ye='Yerdaddy:BAAALgADCgcJDAABLgAECgYJEAAOAAAAAA==.',
Yo='Yoruwolf:BAAALgADCgMJAwAAAA==.Yoven:BAAALgAECgQJBAAAAA==.',
Yu='Yuuna:BAAALgADCggJDAAAAA==.',
Za='Zachsmack:BAAALgAECgYJBQAAAA==.Zanatos:BAAALgAECgQJBwAAAA==.Zaps:BAAALgAECgYJEQAAAA==.Zarayliel:BAAALgAECgIJAgAAAA==.Zarnic:BAAALgADCggJCQAAAA==.Zay:BAAALgAECgEJAQAAAA==.Zaíra:BAAALgAECgQJBwAAAA==.',
Ze='Zeahcur:BAAALgAECgIJAgAAAA==.Zeenab:BAAALgADCgEJAQAAAA==.Zelie:BAABLgAECn8bAAMPAAcJFAguFQAEAQAPAAcJFAguFQAEAQACAAMJpgEGfABVAAAAAA==.Zenreto:BAABLgAECn8ZAAINAAYJqhzgAQChAQANAAYJqhzgAQChAQAAAA==.Zerce:BAAALgADCgcJBwAAAA==.',
Zk='Zkull:BAAALgAECgEJAQAAAA==.',
Zu='Zuggernaut:BAAALgADCgkJDwAAAA==.Zuggzugg:BAAALgADCgcJDAAAAA==.',
Zy='Zyria:BAACLgAFFH8GAAIVAAIJSSKnFgDFAAAVAAIJSSKnFgDFAAAuAAQKfycAAhUACAnAJIYCALICABUACAnAJIYCALICAAAA.',
['Än']='Ängerberg:BAAALgAECgEJAQAAAA==.Änmoa:BAACLgAFFH8FAAImAAIJEBYkAgCzAAAmAAIJEBYkAgCzAAAuAAQKfxwAAiYACQl3IcMAAI8DACYACQl3IcMAAI8DAAAA.',
['Îl']='Îllîdan:BAAALgADCgEJAQAAAA==.',
['Ïn']='Ïnsane:BAABLgAECn8ZAAMBAAcJdRgzDQCsAQABAAcJdRgzDQCsAQASAAQJGwjAQQCuAAAAAA==.',
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

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

local lookup = {'Hunter-BeastMastery','Priest-Discipline','Priest-Holy','Priest-Shadow','DeathKnight-Unholy','DemonHunter-Havoc','Druid-Restoration','Unknown-Unknown','Warrior-Arms','Rogue-Subtlety','Hunter-Survival','Hunter-Marksmanship','Warrior-Fury','Mage-Frost','Druid-Balance','DemonHunter-Devourer','Rogue-Assassination','Mage-Arcane','Monk-Mistweaver','Monk-Brewmaster','Paladin-Holy','Shaman-Restoration','Warlock-Demonology','DeathKnight-Frost','Paladin-Retribution','Evoker-Preservation','Warrior-Protection','Shaman-Elemental','Druid-Feral','Druid-Guardian','Mage-Fire','Warlock-Destruction','Warlock-Affliction','DeathKnight-Blood','Paladin-Protection','Shaman-Enhancement','Evoker-Augmentation','Evoker-Devastation','DemonHunter-Vengeance','Monk-Windwalker',}
local provider = {region='US',realm='Zuluhed',name='US',type='weekly',zone=46,date='2026-05-08',data={Aa='Aaronfreeze:BAABLgAECn8tAAIBAAkJ6xwgCQCjAgABAAkJ6xwgCQCjAgAAAA==.',
Ab='Abrakazaam:BAAALgADCgEJAQAAAA==.',
Ad='Adrios:BAABLgAECn8jAAQCAAgJEhV5EQDAAQACAAgJABV5EQDAAQADAAMJyggdaQCIAAAEAAUJeQYhQABzAAAAAA==.',
Ae='Aetherion:BAAALgAECgMJAwAAAA==.',
Aj='Ajaxz:BAABLgAECn8VAAIFAAkJ+RLLYADRAQAFAAkJ+RLLYADRAQAAAA==.',
Al='Albedô:BAAALgAFFAIJAwABLgAFFAIJBQAGAAohAA==.Aliren:BAAALgAECgYJCgAAAA==.Allmaick:BAAALgADCggJCAAAAA==.Alucard:BAAALgAECgYJDAAAAA==.Alystrasza:BAABLgAECn8cAAIHAAYJvhasKgB/AQAHAAYJvhasKgB/AQAAAA==.',
Am='Amorlandian:BAAALgAECgMJAwAAAA==.',
An='Antimovsky:BAAALgAECgYJCgAAAA==.',
Ap='Aphroditê:BAAALgADCgYJBgABLgAECgcJBwAIAAAAAA==.',
Aq='Aqours:BAAALgADCgcJBwABLgAECgEJAgAIAAAAAA==.',
Ar='Arcan:BAAALgAECgIJAgAAAA==.',
Au='Augustine:BAAALgAECgEJAQAAAA==.Auroras:BAABLgAECn8XAAIDAAcJghPdHQBaAQADAAcJghPdHQBaAQAAAA==.',
Av='Aviaria:BAAALgAECgQJBAAAAA==.Avìendha:BAAALgADCgEJAQAAAA==.',
['Aì']='Aìnzooalgown:BAAALgAFFAIJBAABLgAFFAIJBQAGAAohAA==.',
Ba='Babakubwa:BAAALgAECgMJAwAAAA==.Babylonfive:BAAALgAECgcJCQAAAA==.Balhair:BAAALgADCgYJBgAAAA==.Banish:BAAALgAECgMJAgABLgAECgcJCgAIAAAAAA==.Barragdan:BAAALgADCgEJAQAAAA==.Basandra:BAAALgADCgQJBAAAAA==.Basicc:BAAALgADCgMJAwAAAA==.',
Be='Belleta:BAAALgAECgQJBAABLgAECgUJBQAIAAAAAA==.Berserk:BAEBLgAECn8XAAIJAAYJJyLxBwDTAQAJAAYJJyLxBwDTAQABLgAFFAMJBQAKALwMAA==.Bertringer:BAAALgAECgEJAgAAAA==.',
Bi='Bigmack:BAAALgAECgYJCwAAAA==.Bigwilli:BAAALgAECgUJDAAAAA==.Bingßong:BAAALgADCgUJCAAAAA==.Biscuit:BAACLgAFFH8JAAMBAAMJaBwcIwAJAQABAAMJaBwcIwAJAQALAAIJ/BGZFwCZAAAuAAQKfyIABAwACAmPIx4PAMgCAAwACAl9HR4PAMgCAAsAAwnaH/odABIBAAEABAk+HqlYAAUBAAAA.Bisha:BAABLgAECn83AAINAAkJ8yB8AgD1AgANAAkJ8yB8AgD1AgAAAA==.Bizcocho:BAAALgAECgYJCwAAAA==.',
Bl='Black:BAAALgADCgEJAQAAAA==.Blastthemuff:BAAALgADCgQJBAAAAA==.Bloodsimple:BAAALgADCgUJBQAAAA==.Blákers:BAAALgAECgcJCgABLgAECggJIgAOADIQAA==.',
Bo='Boic:BAAALgADCgQJBAAAAA==.Bonesofdoom:BAAALgAFFAEJAQAAAA==.Boogsta:BAAALgADCgcJEgAAAA==.Boomkingobrr:BAACLgAFFH8HAAIPAAMJ9wgiGgDTAAAPAAMJ9wgiGgDTAAAuAAQKfxsAAg8ACQkOHD8LAOECAA8ACQkOHD8LAOECAAAA.Boops:BAAALgAECgEJAQAAAA==.Bootysweatt:BAABLgAECn8aAAIGAAYJNhtmJACaAQAGAAYJNhtmJACaAQAAAA==.Boss:BAAALgADCgEJAQAAAA==.',
Br='Brewnz:BAAALgAECgUJBgAAAA==.',
Bu='Buckits:BAAALgAECgcJDgAAAA==.Bunsey:BAAALgADCgIJAgAAAA==.Burnsx:BAAALgAECgUJCgABLgAFFAcJEQAQAE8dAA==.Bussyman:BAAALgAECgMJBAAAAA==.',
Bw='Bwoar:BAAALgAECgQJBgAAAA==.',
['Bø']='Bøw:BAAALgAECgMJAwAAAA==.',
['Bü']='Bübble:BAAALgADCgEJAQAAAA==.',
Ca='Captnmurloc:BAAALgAECggJCwAAAA==.Carl:BAAALgAECgEJAgABLgAFFAUJCwARAM0cAA==.Caveyodeler:BAAALgAECgQJCgAAAA==.',
Ce='Cedar:BAAALgAECgQJBQAAAA==.',
Ch='Cherga:BAAALgADCgYJBgAAAA==.Chinegga:BAAALgADCgYJBgAAAA==.Chitose:BAAALgADCgUJBQABLgAECgEJAgAIAAAAAA==.Chrapsasspee:BAAALgADCgcJGQAAAA==.Chrinn:BAAALgADCgIJAgAAAA==.',
Ci='Cindele:BAAALgADCgMJAwAAAA==.Cirvix:BAAALgAECgYJDAAAAA==.Cirxe:BAABLgAECn8VAAISAAgJaAeGBABEAQASAAgJaAeGBABEAQAAAA==.',
Cl='Clampire:BAAALgAECgQJBAAAAA==.Cliint:BAAALgAECgUJBgAAAA==.Cluumn:BAAALgAECgkJCgAAAA==.',
Co='Coms:BAAALgADCgIJAgAAAA==.Cooz:BAAALgAECgUJCAAAAA==.Corybooker:BAAALgAECgcJBAAAAA==.Cowdux:BAAALgAECgYJCQAAAA==.',
Cr='Creamdragon:BAAALgADCgYJCgABLgAECgYJGAATAIsdAA==.',
Cu='Curuni:BAAALgADCgYJBgAAAA==.',
Cz='Czechhunter:BAAALgADCgUJBQAAAA==.',
['Cå']='Cåleb:BAAALgAECgEJAQAAAA==.',
['Cø']='Cønstance:BAAALgAECgcJCAAAAA==.',
Da='Daddyphat:BAABLgAECn8hAAIUAAgJSyR+AgDlAgAUAAgJSyR+AgDlAgAAAA==.Dalight:BAABLgAECn8XAAIVAAYJKiYODwCdAgAVAAYJKiYODwCdAgAAAA==.Dankins:BAACLgAFFH8YAAIWAAYJ5iEhAQA8AgAWAAYJ5iEhAQA8AgAuAAQKfxYAAhYACAkGHfcZAEcCABYACAkGHfcZAEcCAAAA.',
De='Deathmager:BAABLgAECn8cAAIOAAYJuQjVggAMAQAOAAYJuQjVggAMAQAAAA==.Deathtraper:BAAALgAECgcJDQAAAA==.Debur:BAAALgADCgEJAQAAAA==.Deltaka:BAAALgAECgEJAQAAAA==.Demonfella:BAAALgADCgMJAwAAAA==.Demonicpeach:BAABLgAECn8XAAIXAAcJHwuPYgAKAQAXAAcJHwuPYgAKAQAAAA==.Dethsent:BAAALgAECgUJCwAAAA==.Dette:BAAALgAECgYJDAAAAA==.Devilchaser:BAAALgAECgUJBgAAAA==.Devourer:BAAALgAECgcJEQAAAA==.',
Di='Diaval:BAAALgADCgIJAgABLgAECggJGwAXACARAA==.',
Do='Donzilly:BAAALgAECgQJBgAAAA==.Doreme:BAAALgADCgIJAgAAAA==.',
Dr='Drafted:BAAALgAECgcJEAAAAA==.Drax:BAAALgAECgMJAwAAAA==.Drewmcmoo:BAAALgADCgcJBgAAAA==.Drsath:BAAALgADCgcJBwAAAA==.Drunkorca:BAAALgADCgUJBQABLgAECggJKQAYAB0aAA==.',
Ea='Earnar:BAAALgADCgYJDAAAAA==.',
Ed='Edarix:BAAALgADCgcJBgABLgAECgYJIQAZANEWAA==.',
Ei='Eiliyah:BAABLgAECn8yAAMVAAgJehz0FgBaAgAVAAgJehz0FgBaAgAZAAIJHwIRWgElAAAAAA==.',
Ek='Ekmek:BAAALgAECgEJAQAAAA==.',
El='Elabernathy:BAABLgAECn8bAAIBAAcJXxXeMACKAQABAAcJXxXeMACKAQAAAA==.Elenay:BAAALgAECgYJDwAAAA==.Elesia:BAAALgAECgkJCQAAAA==.Elfussy:BAAALgAECgEJAQAAAA==.Elgoku:BAAALgAECgQJCQABLgAECgUJCwAIAAAAAA==.Eliarssande:BAAALgADCgQJBAAAAA==.Elinay:BAAALgADCgcJCQABLgAECgYJDwAIAAAAAA==.Elixia:BAAALgAECgYJCgAAAA==.Elpatron:BAAALgADCgQJBAABLgAECgkJKQAaAGgXAA==.Elylanea:BAAALgAECgUJDgAAAA==.',
Em='Emulsdeath:BAAALgAECgcJEAABLgAECggJIgAZAA8mAA==.Emulsifier:BAABLgAECn8iAAIZAAgJDyb3BAABAwAZAAgJDyb3BAABAwAAAA==.',
En='Ennoa:BAAALgAECgEJAQAAAA==.',
Er='Ergen:BAACLgAFFH8JAAILAAMJ0Q9wDwD7AAALAAMJ0Q9wDwD7AAAuAAQKfyUAAgsACAk6IY4GAJUCAAsACAk6IY4GAJUCAAAA.',
Eu='Eusexua:BAAALgAECgQJBQABLgAECgcJCgAIAAAAAA==.',
Fa='Fairbear:BAABLgAECn8cAAQNAAYJ+ByvFwCpAQANAAYJ+ByvFwCpAQAJAAEJZA5rPgA7AAAbAAEJ6QeZOwAjAAAAAA==.Faustt:BAAALgAECgEJAQAAAA==.',
Fi='Filthyfabio:BAAALgADCgcJEQAAAA==.Fireburr:BAAALgAECgMJAwAAAA==.',
Fl='Fløw:BAAALgAECgMJCgAAAA==.',
Fr='Fragglerott:BAABLgAECn8VAAMcAAgJXAiLUQAAAQAcAAgJXAiLUQAAAQAWAAIJJAi3kQBTAAAAAA==.Frati:BAAALgAECgEJAQAAAA==.Friedchickn:BAAALgAECgMJBwAAAA==.Frosttrinity:BAAALgADCgUJBAAAAA==.',
Fu='Funslinger:BAAALgAECgMJBgAAAA==.',
Ga='Gaffz:BAAALgAECgEJAQAAAA==.Galannar:BAAALgAECggJDQAAAA==.Galvrax:BAAALgAECgUJCgAAAA==.Gast:BAACLgAFFH8GAAINAAQJNxFdDwA0AQANAAQJNxFdDwA0AQAuAAQKfyQAAw0ACAkLGpIpABQCAA0ACAkLGpIpABQCABsAAQm0G3BAAE8AAAAA.',
Ge='Gearwick:BAAALgADCgYJBwABLgAECgYJIAAVAMkgAA==.',
Gh='Ghstfacekila:BAAALgADCgEJAQAAAA==.',
Gl='Glizzybreath:BAAALgAECgMJAwABLgAECgQJBAAIAAAAAA==.',
Go='Gorska:BAABLgAECn8iAAIcAAgJFR1cCQBEAgAcAAgJFR1cCQBEAgAAAA==.',
Gr='Grawm:BAABLgAECn8iAAMBAAkJqiKRGwD4AQAMAAgJSRWrHgAxAgABAAkJPyCRGwD4AQAAAA==.Greedory:BAAALgADCgIJAgAAAA==.Groot:BAAALgADCgUJBgAAAA==.Gruetss:BAAALgAECgQJBAAAAA==.',
Ha='Hailbringer:BAAALgAECgcJCAAAAA==.Hakoona:BAABLgAECn8jAAIUAAgJBxipDgDdAQAUAAgJBxipDgDdAQAAAA==.Hanginaround:BAAALgAECgEJAQAAAA==.Hangman:BAABLgAFFH8JAAIVAAMJORyREgAfAQAVAAMJORyREgAfAQABLgAECggJNgAHAG0jAA==.Hanni:BAABLgAECn8dAAIMAAgJUhwHBAAGAgAMAAgJUhwHBAAGAgAAAA==.Haveaburitto:BAACLgAFFH8NAAIOAAQJWBxIIgBkAQAOAAQJWBxIIgBkAQAuAAQKfygAAg4ACAk0JXsMAGEDAA4ACAk0JXsMAGEDAAAA.Hawktoetem:BAAALgAECgQJBAABLgAECgYJHAANAPgcAA==.',
He='Healmemaybe:BAABLgAECn8VAAIHAAYJnCGxJQAiAgAHAAYJnCGxJQAiAgAAAA==.Healthyadult:BAAALgAECgMJBQAAAA==.Hellshand:BAAALgADCggJEAAAAA==.Heracles:BAAALgAECgQJBAAAAA==.Heretic:BAAALgADCgEJAQAAAA==.',
Hi='Hickscale:BAAALgADCgMJAwAAAA==.',
Ho='Holycøw:BAAALgADCgMJAwAAAA==.Holydefender:BAAALgADCgUJBQAAAA==.Holyhands:BAAALgADCgYJBgAAAA==.Holyholyholy:BAAALgAECgEJAgAAAA==.Honest:BAAALgADCgMJAwAAAA==.',
Hu='Hunniee:BAAALgAECgEJAQAAAA==.Huntrix:BAAALgADCgcJEgAAAA==.',
Ic='Icedatt:BAAALgAECgUJCwAAAA==.Icefire:BAAALgADCgUJBAAAAA==.',
Ik='Ikur:BAABLgAECn8sAAIVAAgJAhy/DABJAgAVAAgJAhy/DABJAgAAAA==.',
Il='Ilinia:BAAALgAECgYJCAABLgAECgQJCgAIAAAAAA==.',
In='Infoxicated:BAAALgADCgcJBwABLgAECgkJJAACALIeAA==.',
Ip='Ipopkidneys:BAACLgAFFH8MAAMRAAQJ0x95AwAbAQAKAAMJTiKnEAAdAQARAAMJ/Bl5AwAbAQAuAAQKfyIAAwoACAn6JYEMANACAAoACAn6JYEMANACABEAAQn1I1UUAGUAAAAA.',
Ir='Iroi:BAAALgAECgIJBQAAAA==.',
Is='Iskur:BAABLgAECn8ZAAIWAAcJ8xbaHQDCAQAWAAcJ8xbaHQDCAQABLgAECggJLAAVAAIcAA==.Isuck:BAAALgAFFAIJAgAAAA==.Isurr:BAAALgAECgYJCwABLgAECggJLAAVAAIcAA==.',
It='Itakecandle:BAAALgADCgkJCgABLgAECgUJCwAIAAAAAA==.',
Iv='Ivanapump:BAAALgAECgIJAgABLgAECgQJBAAIAAAAAA==.',
Ja='Jackkal:BAAALgAECgMJAwAAAA==.Jadethecat:BAAALgADCgMJAwAAAA==.Jakbis:BAAALgADCgEJAQAAAA==.Jaldiar:BAAALgADCgcJBwABLgAECgYJBgAIAAAAAA==.Jametrok:BAAALgAECgEJAQAAAA==.Jazbek:BAAALgAECgMJBAAAAA==.Jazzonus:BAAALgAECgEJAQAAAA==.',
Je='Jefferey:BAAALgADCgMJAwAAAA==.Jeriçho:BAAALgADCgYJBgAAAA==.',
Jh='Jhonwick:BAAALgAECgIJAgAAAA==.',
Ji='Jippedo:BAAALgAECgYJAgABLgAECgcJBAAIAAAAAA==.Jiraîya:BAAALgAECgQJBQAAAA==.',
Jo='Jordak:BAABLgAECn8cAAIHAAgJvByzCQCuAgAHAAgJvByzCQCuAgAAAA==.Jorolee:BAAALgADCgEJAQAAAA==.',
Ka='Kallistos:BAAALgAECgcJEAAAAA==.Kariza:BAAALgAECgMJAgAAAA==.Karunik:BAAALgADCgYJBgABLgAECgcJCgAIAAAAAA==.',
Kh='Khione:BAAALgADCgYJBgAAAA==.',
Ki='Kibblerina:BAAALgADCgcJBwAAAA==.Kiranam:BAABLgAECn8cAAQdAAgJrQ6aEQCTAQAdAAgJqQqaEQCTAQAeAAcJNQz0EgDaAAAPAAIJWwfWcQBZAAAAAA==.',
Kn='Knarth:BAABLgAECn8hAAIfAAcJGxgEAgDAAQAfAAcJGxgEAgDAAQAAAA==.',
Ko='Koisy:BAAALgAECgIJAwABLgAECgYJDwAIAAAAAA==.Kole:BAAALgAECgEJAQAAAA==.Koopa:BAABLgAECn8eAAINAAgJsSELCQBYAgANAAgJsSELCQBYAgAAAA==.',
Kr='Krasul:BAACLgAFFH8NAAMWAAQJ4Rx6DwBIAQAWAAQJ4Rx6DwBIAQAcAAEJwg3gKwBKAAAuAAQKfx8AAxYACAkXIecIAOgCABYACAkXIecIAOgCABwABgm/HPAxAJQBAAAA.Krenthok:BAABLgAECn8WAAIXAAgJfgZPTgA/AQAXAAgJfgZPTgA/AQAAAA==.',
Ku='Kuraha:BAAALgAECgQJBAAAAA==.Kushar:BAAALgAECgQJBQABLgAECgYJBwAIAAAAAA==.',
La='Large:BAAALgADCgYJBgAAAA==.Largemann:BAAALgAECgUJBgABLgAFFAQJCQAFAKYYAA==.Lathspell:BAABLgAECn8pAAIOAAgJEiEaHABCAgAOAAgJEiEaHABCAgAAAA==.Lazyevoker:BAAALgADCgQJBAABLgAECgEJAQAIAAAAAA==.',
Le='Leahan:BAAALgAECgMJBgAAAA==.Leloo:BAAALgADCgYJCgABLgAECgEJAQAIAAAAAA==.',
Lh='Lhureciv:BAABLgAECn87AAMEAAkJPCNxAQAjAwAEAAkJPCNxAQAjAwACAAYJ+x4tIwB6AQAAAA==.',
Li='Lightchaser:BAAALgADCgMJAgAAAA==.Lightfkyou:BAAALgADCgcJCgAAAA==.Lihvurce:BAAALgAECgUJDAABLgAECgkJOwAEADwjAA==.Lillianna:BAABLgAECn8kAAIKAAgJxBcLCAAnAgAKAAgJxBcLCAAnAgAAAA==.Lingchi:BAAALgAECgMJAwAAAA==.',
Ll='Llew:BAAALgAECgEJAQAAAA==.',
Lo='Loenhart:BAAALgAECgEJAQAAAA==.Lolkurtone:BAAALgAECgIJAgAAAA==.',
Lu='Luciaan:BAAALgADCgcJEgAAAA==.Lucrative:BAAALgADCgcJDQAAAA==.Lug:BAAALgAECgEJAQAAAA==.Lulue:BAAALgADCgQJBAAAAA==.Luminari:BAAALgADCgUJBQAAAA==.Lunastorm:BAABLgAECn8xAAIaAAkJYSE2AQA5AwAaAAkJYSE2AQA5AwAAAA==.Luponero:BAACLgAFFH8IAAMBAAQJ5iKYAwCkAQABAAQJ5iKYAwCkAQAMAAEJ5QacKgBGAAAuAAQKfx8AAwwACAnnHtwQALUCAAwACAl6HdwQALUCAAEAAwm/H39QAB0BAAAA.',
Ly='Lynney:BAAALgADCgYJBwAAAA==.',
Ma='Macmn:BAACLgAFFH8QAAIcAAQJrheQDABFAQAcAAQJrheQDABFAQAuAAQKfx4AAhwABwnAJGILAOICABwABwnAJGILAOICAAAA.Magicard:BAAALgAECgcJDgAAAA==.Makesfood:BAABLgAECn8qAAIOAAcJZBctTACEAQAOAAcJZBctTACEAQAAAA==.Mamaheals:BAABLgAECn8dAAIDAAYJdBogJwC1AQADAAYJdBogJwC1AQAAAA==.Mandos:BAAALgAECgYJBgAAAA==.Mantistabogn:BAAALgAECgYJDwAAAA==.Maor:BAABLgAECn8WAAIZAAgJlxfnLwC9AQAZAAgJlxfnLwC9AQAAAA==.March:BAAALgADCgEJAQAAAA==.Markeisha:BAAALgAECgQJCAAAAA==.',
Me='Mechzician:BAABLgAECn8yAAIOAAgJBBkLLQDtAQAOAAgJBBkLLQDtAQAAAA==.Melinoe:BAAALgAECgEJAQAAAA==.Merlerk:BAAALgADCgYJBgAAAA==.Merlini:BAAALgAECgcJEAAAAA==.',
Mi='Micspanky:BAAALgAECggJEgAAAA==.Mithrandi:BAAALgAECgMJBAAAAA==.',
Mo='Mornhathor:BAAALgAECggJDgABLgAECgYJBgAIAAAAAA==.',
Mu='Mufinblaster:BAAALgADCgEJAQAAAA==.Mushuu:BAAALgADCgIJBgAAAA==.Musnicker:BAAALgAECgQJBwAAAA==.',
['Mè']='Mètis:BAAALgAECgcJBwAAAA==.',
Ne='Neel:BAAALgADCgQJBQAAAA==.Nervhoost:BAAALgADCgMJAwAAAA==.Neuropolis:BAAALgADCgcJFQAAAA==.Neuroscience:BAAALgADCgMJAwAAAA==.Neurotics:BAABLgAECn8WAAQgAAYJxiRhAwDxAQAgAAYJJCNhAwDxAQAhAAMJ+iSvBwArAQAXAAQJGRz0ugDjAAAAAA==.Neò:BAAALgAECgYJDQAAAA==.',
Ni='Niesh:BAAALgAECgEJBwAAAA==.Nineoneone:BAABLgAECn8WAAMDAAYJRhTeIABBAQADAAYJRhTeIABBAQACAAQJjgPoRQCLAAAAAA==.',
No='Nobledecay:BAAALgAECgQJBQAAAA==.Nocturne:BAAALgAECgEJAwAAAA==.',
Nu='Nubbletcake:BAAALgADCgEJAQABLgAECgkJJAACALIeAA==.',
Ny='Nylveth:BAACLgAFFH8HAAIEAAQJxgyXDQAyAQAEAAQJxgyXDQAyAQAuAAQKfyoAAgQACQkAHW4EAKMCAAQACQkAHW4EAKMCAAAA.',
Oc='Ocra:BAAALgAECgUJDAABLgAECgkJPAABADwfAA==.',
Of='Offspeck:BAAALgAECgIJAgABLgAECgkJIAAhAFYcAA==.',
Or='Orcaman:BAAALgAECgMJAwABLgAECggJKQAYAB0aAA==.',
Ou='Ouutkast:BAAALgAECgEJAQAAAA==.',
Oz='Ozwald:BAABLgAECn8nAAILAAkJ9xpyAwCgAgALAAkJ9xpyAwCgAgAAAA==.',
Pa='Pallyangel:BAAALgADCgcJDwAAAA==.Patrio:BAABLgAECn8pAAIaAAkJaBfcBABaAgAaAAkJaBfcBABaAgAAAA==.',
Pe='Peaceonea:BAAALgAECgUJBwAAAA==.Peachaid:BAECLgAFFH8RAAICAAYJlB1IAwA7AgACAAYJlB1IAwA7AgAuAAQKfzAAAwIACQlWIosBAGADAAIACQlWIosBAGADAAMABgkYHSUlAMABAAAA.Peatri:BAAALgAECgkJBAAAAA==.Peetree:BAAALgAECgkJDgAAAA==.',
Ph='Phosphorus:BAABLgAECn9FAAMJAAkJEB6dAQDUAgAJAAkJEB6dAQDUAgAbAAQJTR5RFwAHAQAAAA==.',
Pl='Plagüë:BAACLgAFFH8FAAMFAAIJ7BxHYwCxAAAFAAIJ7BxHYwCxAAAiAAEJWwlOIQAyAAAuAAQKfz0AAwUACQmkI4UDADIDAAUACQmkI4UDADIDACIABQmZDwkeANEAAAAA.Pleistarchus:BAAALgAECgYJCQAAAA==.',
Po='Poic:BAAALgADCgEJAQAAAA==.Poofighter:BAAALgAECgMJAwABLgAFFAIJBQAGAAohAA==.Poonan:BAAALgAECgQJBAAAAA==.',
Pp='Ppgangandlaw:BAAALgADCgEJAQAAAA==.',
Pr='Precious:BAAALgAECgMJBgAAAA==.Primalistic:BAAALgADCgUJBQABLgAECggJMgAOAAQZAA==.Primàl:BAABLgAECn8lAAIHAAYJBRvyNADUAQAHAAYJBRvyNADUAQAAAA==.',
Pu='Purifieds:BAAALgADCgEJAQAAAA==.',
Qs='Qsrqasda:BAAALgAECgYJDgAAAA==.',
Qt='Qtmenopaws:BAAALgAECgQJAwAAAA==.Qtptt:BAACLgAFFH8NAAIXAAMJQxxEHQAPAQAXAAMJQxxEHQAPAQAuAAQKfzgAAhcACAkpI7kIALoCABcACAkpI7kIALoCAAAA.',
Ra='Ragedeath:BAABLgAFFH8GAAIiAAMJsw+KEwDAAAAiAAMJsw+KEwDAAAAAAA==.Ragedh:BAAALgAECgIJAgABLgAFFAMJBgAiALMPAA==.Ragemonk:BAAALgADCgQJBAABLgAFFAMJBgAiALMPAA==.Rasmong:BAAALgAECgYJBwAAAA==.Ravinsinda:BAAALgADCggJDQAAAA==.Ravinursula:BAAALgAECgYJDAAAAA==.Rawrsaur:BAAALgAECgcJDQAAAA==.',
Re='Really:BAAALgADCgYJBgABLgAECgEJAQAIAAAAAA==.Redder:BAAALgAECgEJAQAAAA==.Retaliator:BAABLgAECn8hAAMZAAYJ0Rb2iQBnAQAZAAYJ0Rb2iQBnAQAjAAEJ1QZBOAAbAAAAAA==.Revan:BAAALgADCggJDgAAAA==.',
Rh='Rhýs:BAAALgAECgYJBgAAAA==.',
Ri='Rih:BAAALgADCgEJAQAAAA==.Ripits:BAAALgADCgcJCAABLgAECgEJAQAIAAAAAA==.Risky:BAAALgAECgkJAwAAAA==.Riskyfist:BAAALgAECgcJAgAAAA==.Risquae:BAAALgAECgEJAQAAAA==.',
Ro='Rocc:BAAALgAECgcJBAAAAA==.Rocketeer:BAABLgAECn8iAAIOAAgJ1gsXWQBjAQAOAAgJ1gsXWQBjAQAAAA==.Romulis:BAAALgAECgEJAQAAAA==.Ronburgundii:BAAALgAECgEJAQAAAA==.',
Ru='Rudrya:BAABLgAECn8UAAIkAAgJcAfiEwB8AQAkAAgJcAfiEwB8AQAAAA==.Runalish:BAAALgAECgEJAQAAAA==.Runarinis:BAAALgADCgIJAgAAAA==.',
Ry='Rynopinn:BAABLgAECn82AAIHAAgJbSMZCwDoAgAHAAgJbSMZCwDoAgAAAA==.Ryxn:BAAALgADCgYJBgAAAA==.',
['Rí']='Ríco:BAAALgADCgUJCgAAAA==.',
Sa='Saeed:BAAALgAECgEJAQAAAA==.Saelylasia:BAAALgAECgQJBQAAAA==.Sajaboy:BAAALgADCgUJCgAAAA==.Samusaran:BAAALgADCgEJAQAAAA==.Sartha:BAABLgAECn8WAAIZAAcJxRE4RQB2AQAZAAcJxRE4RQB2AQAAAA==.Sasuka:BAAALgADCgUJCQAAAA==.Satsu:BAAALgAECgEJAQAAAA==.',
Sc='Scatherlia:BAAALgADCgYJBQABLgAECgQJBQAIAAAAAA==.Sco:BAAALgADCgEJAQAAAA==.Screwthebull:BAAALgAECgQJBAAAAA==.Scrumpvincet:BAAALgADCgQJBQAAAA==.',
Se='Sectiondk:BAAALgAECgYJEwAAAA==.Sedda:BAACLgAFFH8QAAIZAAUJhR8EDAB7AQAZAAUJhR8EDAB7AQAuAAQKfygAAhkACAmjJcwGAGMDABkACAmjJcwGAGMDAAAA.Seigfreid:BAAALgAECgYJCAAAAA==.Sensual:BAABLgAECn86AAIjAAkJiBIGCADQAQAjAAkJiBIGCADQAQAAAA==.Seraphina:BAAALgAECgQJCgAAAA==.Sessano:BAAALgAECgMJBAAAAA==.Sesshomaru:BAACLgAFFH8FAAMGAAIJCiFIEQBpAAAGAAEJ0CNIEQBpAAAQAAEJRB6HVQBbAAAuAAQKfz0AAxAACQnoIt8KAH0CABAACAmwId8KAH0CAAYABwldJIAOAHsCAAAA.',
Sh='Shadoly:BAAALgAECgYJDAAAAA==.Shadowboss:BAABLgAECn8WAAIEAAUJIhOuLADoAAAEAAUJIhOuLADoAAAAAA==.Shamnslam:BAAALgAECgEJAQAAAA==.Shang:BAABLgAECn8hAAMPAAgJBCIHBAC9AgAPAAgJBCIHBAC9AgAHAAEJCxNVywA0AAAAAA==.Shirona:BAAALgAECgQJBAAAAA==.Showstop:BAAALgAECgEJAQAAAA==.Shyvanna:BAABLgAECn8fAAMlAAgJsREGFQCeAQAlAAgJsREGFQCeAQAmAAQJ+gl+KwDBAAAAAA==.Shïnïgämï:BAABLgAECn8WAAInAAYJiCAvCQDeAQAnAAYJiCAvCQDeAQABLgAECgkJIgAWAEkeAA==.',
Si='Siare:BAAALgAECgYJEAAAAA==.Silica:BAAALgAECgMJAwAAAA==.Siner:BAAALgAECgUJCAAAAA==.',
Sk='Skeeter:BAABLgAECn8pAAQhAAgJdRzGAgDvAQAhAAcJ0hzGAgDvAQAXAAgJXRilNQCOAQAgAAEJEBqqIgBLAAAAAA==.Skiadrum:BAABLgAECn8wAAMTAAgJlArJHgBQAQATAAgJlArJHgBQAQAoAAEJpweiYwAvAAAAAA==.Skoliro:BAAALgAECgEJAQAAAA==.Skorch:BAAALgADCgkJEAABLgAECggJMgAOAAQZAA==.',
Sm='Smotts:BAAALgAECgYJCwAAAA==.Smòtts:BAAALgAECgQJBQAAAA==.',
Sn='Snizard:BAAALgAECgUJDAAAAA==.Snuggiepoo:BAABLgAECn8kAAMCAAkJsh7fAwDkAgACAAgJ5CDfAwDkAgAEAAYJgRXbMQDJAAAAAA==.',
So='Songbirds:BAAALgADCgcJDQAAAA==.Sonichoos:BAAALgAECgUJCwAAAA==.Sophiel:BAAALgAECgYJDwAAAA==.Soulbark:BAAALgAECgMJAwABLgAECgQJBAAIAAAAAQ==.Souleater:BAAALgADCgMJAwAAAA==.Soulforged:BAAALgADCgcJCwABLgAECgQJBAAIAAAAAA==.Soulweaver:BAAALgAECgQJBAAAAQ==.',
Sp='Sparrowhåwk:BAAALgADCgUJBgAAAA==.Spongebill:BAAALgADCgEJAQAAAA==.Spàdes:BAABLgAECn8UAAMNAAYJmhlBLgAVAQANAAUJOB1BLgAVAQAJAAMJTA6FJACiAAAAAA==.',
St='Starel:BAAALgADCgYJBwAAAA==.Stellanoova:BAAALgAECgMJAwABLgAECgYJDgAIAAAAAA==.Stevebushami:BAAALgAECgYJEAAAAA==.',
Su='Suou:BAAALgADCgcJCQABLgAECgEJAgAIAAAAAA==.Surj:BAAALgAECgQJDQAAAA==.',
Sv='Svmii:BAAALgADCgcJCgAAAA==.',
Ta='Taikuri:BAAALgAECgUJCAABLgAECgYJEAAIAAAAAA==.Tanklilbaby:BAAALgAECgEJAQAAAA==.Taxgirl:BAACLgAFFH8JAAMFAAQJphj/IABeAQAFAAQJphj/IABeAQAYAAEJsQO2CgBCAAAuAAQKfxsAAgUACAndI14SAA0DAAUACAndI14SAA0DAAAA.',
Te='Teralion:BAAALgAECgMJBAAAAA==.',
Th='Thaldreaux:BAAALgAECgMJBAAAAA==.Thefirst:BAAALgAECgEJAQAAAA==.Theleon:BAABLgAECn8YAAIPAAgJNw4QGAB6AQAPAAgJNw4QGAB6AQAAAA==.Thordrin:BAABLgAECn8lAAIVAAcJVx86GABQAgAVAAcJVx86GABQAgAAAA==.Thorlan:BAAALgADCgYJCAAAAA==.Thrasherzs:BAAALgAECgUJCQAAAA==.Thunder:BAAALgADCgQJBAABLgAECgcJCgAIAAAAAA==.Thundergrasp:BAAALgAECgcJDwAAAA==.',
Ti='Tianhe:BAAALgAECgMJAwAAAA==.Tiarisaril:BAAALgAECgYJBgAAAA==.Tippah:BAAALgAECgEJAgAAAA==.Tippers:BAAALgAECgEJAQAAAA==.',
To='Toe:BAAALgAECgQJBAAAAA==.Tonkah:BAAALgAECgUJBQAAAA==.Topenga:BAABLgAECn88AAIBAAkJPB8XBgDRAgABAAkJPB8XBgDRAgAAAA==.Touchypope:BAAALgADCgUJBQAAAA==.',
Tr='Treeage:BAAALgADCgMJAwAAAA==.Triggerd:BAAALgADCgEJAQAAAA==.Trunks:BAAALgADCgQJBAAAAA==.Trüst:BAAALgAECggJDgAAAA==.',
Tw='Twicelife:BAAALgAECgUJBwABLgAECgkJRQAJABAeAA==.',
Ty='Tyrygosa:BAAALgAECgUJBQABLgAFFAMJBgAXAPsVAA==.',
['Tå']='Tånk:BAAALgAECggJEwAAAA==.',
Un='Uneedsummilk:BAAALgADCgcJBwAAAA==.Unholyapollo:BAAALgADCgYJCwAAAA==.',
Ur='Urthstripe:BAABLgAECn8WAAIHAAcJvBb6JAChAQAHAAcJvBb6JAChAQAAAA==.',
Va='Vae:BAAALgAECgIJAgABLgAFFAMJCAAFAIkhAA==.Valle:BAAALgAECgIJAwABLgAFFAcJFQAEAAAZAA==.Valoria:BAAALgAECgEJAQABLgAFFAcJFQAEAAAZAA==.',
Ve='Velarenea:BAAALgADCgEJAQAAAA==.Velgabrine:BAAALgADCggJEgABLgAECggJIgAZAA8mAA==.Veraani:BAAALgAECgYJBgAAAA==.Verra:BAAALgADCgYJBgAAAA==.',
Vi='Vil:BAAALgADCgcJBgAAAA==.Virlan:BAAALgADCgQJBAAAAA==.Viserion:BAAALgAECgYJDgAAAA==.',
Vo='Voidchaosfan:BAAALgAECgQJBQABLgAECgQJCAAIAAAAAA==.',
Vu='Vue:BAABLgAECn83AAIVAAkJHBokCwBfAgAVAAkJHBokCwBfAgAAAA==.Vuldin:BAAALgAECgEJAgAAAA==.',
['Vö']='Völdemört:BAAALgADCgIJAgAAAA==.',
Wa='Wakasham:BAACLgAFFH8PAAIkAAUJ1B92AQCAAQAkAAUJ1B92AQCAAQAuAAQKfyUAAiQACAnjJZ4BAFMDACQACAnjJZ4BAFMDAAAA.',
We='Wehonoryou:BAABLgAECn8WAAIGAAYJ9CFDDAC9AQAGAAYJ9CFDDAC9AQAAAA==.Wetard:BAAALgADCgIJAgAAAA==.',
Wi='Willbyers:BAAALgAECgEJAQAAAA==.',
Wo='Wolfpacked:BAABLgAECn8iAAIWAAkJSR62BADzAgAWAAkJSR62BADzAgAAAA==.Wolfzbåin:BAAALgAECgQJBAAAAA==.',
Wr='Wroot:BAAALgADCgYJCQAAAA==.Wrotten:BAAALgAECggJEgAAAA==.',
Wu='Wunderlust:BAABLgAECn82AAIOAAkJtB5lCQDeAgAOAAkJtB5lCQDeAgAAAA==.',
Xe='Xemon:BAAALgAECgIJAgAAAA==.',
Xi='Xilyana:BAAALgAECgQJBAAAAA==.',
Xm='Xmatick:BAAALgAECgcJCQAAAA==.',
Xs='Xscrats:BAAALgAECgkJBwAAAA==.',
Ye='Yellowshaman:BAACLgAFFH8QAAIcAAUJkQ/nCwAuAQAcAAUJkQ/nCwAuAQAuAAQKfyoAAhwACAkkIT8MANcCABwACAkkIT8MANcCAAAA.Yerac:BAAALgAECgEJAQAAAA==.',
Yu='Yukikage:BAAALgAECgMJAwAAAA==.Yutdaeng:BAAALgAECgMJBAAAAA==.',
Yv='Yvent:BAAALgADCgIJAgAAAA==.Yvraine:BAAALgAECgEJAQAAAA==.',
Za='Zakcarii:BAAALgADCgMJCAAAAA==.Zalicy:BAAALgAECgYJEwAAAA==.Zalogar:BAAALgAECgcJCgAAAA==.Zapper:BAAALgAECgQJBQAAAA==.',
Ze='Zealot:BAAALgAECgEJAQAAAA==.Zeeasyez:BAAALgAECgYJEQAAAA==.Zestul:BAAALgADCgEJAQAAAA==.',
Zh='Zhane:BAAALgADCgYJBwAAAA==.',
Zo='Zordon:BAAALgAECgYJDwAAAA==.',
Zu='Zugg:BAAALgAECgIJAgABLgAFFAcJFQAEAAAZAA==.Zuriznikov:BAAALgADCgUJBQABLgAECgYJDgAIAAAAAA==.',
['Øf']='Øffspeck:BAABLgAECn8gAAQhAAkJVhw3AgAQAgAXAAgJwxgXLgBVAgAhAAcJICE3AgAQAgAgAAMJzh7LMAD3AAAAAA==.',
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

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

local lookup = {'Hunter-BeastMastery','Priest-Discipline','Priest-Holy','Priest-Shadow','DemonHunter-Devourer','Unknown-Unknown','Rogue-Subtlety','Hunter-Marksmanship','Warrior-Fury','Druid-Balance','DemonHunter-Havoc','Rogue-Assassination','Paladin-Holy','Shaman-Restoration','Paladin-Retribution','Hunter-Survival','Warrior-Protection','Shaman-Elemental','Monk-Brewmaster','Druid-Restoration','Mage-Frost','Druid-Feral','Druid-Guardian','DeathKnight-Unholy','Evoker-Preservation','Warlock-Affliction','Warrior-Arms','DeathKnight-Blood','Warlock-Demonology','Shaman-Enhancement','Paladin-Protection','Evoker-Augmentation','Evoker-Devastation','DemonHunter-Vengeance','Monk-Mistweaver','Warlock-Destruction',}
local provider = {region='US',realm='Zuluhed',name='US',type='weekly',zone=46,date='2026-04-24',data={Aa='Aaronfreeze:BAABLgAECn8kAAIBAAgJDhy0AwBOAgABAAgJDhy0AwBOAgAAAA==.',
Ab='Abrakazaam:BAAALgADCgEJAQAAAA==.',
Ad='Adrios:BAABLgAECn8fAAQCAAgJvAvwHgCdAQACAAgJWAvwHgCdAQADAAMJyggSaQCIAAAEAAUJgAZSGAB3AAAAAA==.',
Aj='Ajaxz:BAAALgAECggJEQAAAA==.',
Al='Albedô:BAAALgAECgUJBgABLgAECggJMAAFAHIjAA==.Aliren:BAAALgAECgYJCgAAAA==.Allmaick:BAAALgADCggJCAAAAA==.Alucard:BAAALgAECgIJAgAAAA==.Alystrasza:BAAALgAECgYJEAAAAA==.',
An='Antimovsky:BAAALgAECgUJCAAAAA==.',
Aq='Aqours:BAAALgADCgcJBwABLgAECgEJAgAGAAAAAA==.',
Ar='Arcan:BAAALgAECgIJAgAAAA==.',
Au='Augustine:BAAALgADCgYJBgAAAA==.Auroras:BAABLgAECn8XAAIDAAcJhRPPCABzAQADAAcJhRPPCABzAQAAAA==.',
Av='Aviaria:BAAALgAECgQJBAAAAA==.Avìendha:BAAALgADCgEJAQAAAA==.',
['Aì']='Aìnzooalgown:BAAALgAECgQJDAABLgAECggJMAAFAHIjAA==.',
Ba='Babakubwa:BAAALgAECgMJAwAAAA==.Babylonfive:BAAALgAECgcJCAAAAA==.Balhair:BAAALgADCgYJBgAAAA==.Banish:BAAALgAECgEJAQABLgAECgUJBgAGAAAAAA==.Barragdan:BAAALgADCgEJAQAAAA==.Basandra:BAAALgADCgQJBAAAAA==.',
Be='Berserk:BAEALgAECgYJDwABLgAFFAMJBQAHAMUMAA==.Bertringer:BAAALgAECgEJAQAAAA==.',
Bi='Bigmack:BAAALgAECgYJCwAAAA==.Bigwilli:BAAALgAECgQJBwAAAA==.Bingßong:BAAALgADCgUJBQAAAA==.Biscuit:BAABLgAECn8aAAMIAAgJ0h11DwDBAgAIAAgJeh11DwDBAgABAAQJOhV7KADEAAAAAA==.Bisha:BAABLgAECn8pAAIJAAgJbB/qDQDmAgAJAAgJbB/qDQDmAgAAAA==.Bizcocho:BAAALgAECgYJCwAAAA==.',
Bl='Black:BAAALgADCgEJAQAAAA==.Blákers:BAAALgAECgUJBwAAAA==.',
Bo='Boic:BAAALgADCgQJBAAAAA==.Bonesofdoom:BAAALgAECgUJCAAAAA==.Boogsta:BAAALgADCgcJCwAAAA==.Boomkingobrr:BAACLgAFFH8HAAIKAAMJ5giPBgDpAAAKAAMJ5giPBgDpAAAuAAQKfxsAAgoACQkOHD8LAOECAAoACQkOHD8LAOECAAAA.Bootysweatt:BAABLgAECn8aAAILAAYJNhtgJACaAQALAAYJNhtgJACaAQAAAA==.Boss:BAAALgADCgEJAQAAAA==.',
Br='Brewnz:BAAALgAECgUJBgAAAA==.',
Bu='Buckits:BAAALgAECgcJBwAAAA==.Bunsey:BAAALgADCgIJAgAAAA==.Burnsx:BAAALgAECgUJBQABLgAFFAYJEQAFAOUfAA==.',
Bw='Bwoar:BAAALgAECgQJBgAAAA==.',
['Bø']='Bøw:BAAALgAECgMJAwAAAA==.',
['Bü']='Bübble:BAAALgADCgEJAQAAAA==.',
Ca='Captnmurloc:BAAALgAECgIJAgAAAA==.Carl:BAAALgADCgUJBQABLgAFFAQJBgAMAIwXAA==.Caveyodeler:BAAALgAECgQJCgAAAA==.',
Ce='Cedar:BAAALgAECgIJAgAAAA==.',
Ch='Cherga:BAAALgADCgYJBgAAAA==.Chinegga:BAAALgADCgYJBgAAAA==.Chitose:BAAALgADCgUJBQABLgAECgEJAgAGAAAAAA==.Chrapsasspee:BAAALgADCgcJEwAAAA==.Chrinn:BAAALgADCgIJAgAAAA==.',
Ci='Cindele:BAAALgADCgMJAwAAAA==.Cirvix:BAAALgAECgYJDAAAAA==.Cirxe:BAAALgAECgYJBgAAAA==.',
Cl='Cliint:BAAALgADCgMJAwAAAA==.',
Co='Coms:BAAALgADCgIJAgAAAA==.Cooz:BAAALgAECgMJAwAAAA==.',
Cr='Creamdragon:BAAALgADCgYJCgABLgAECgUJDAAGAAAAAA==.',
Cz='Czechhunter:BAAALgADCgUJBQAAAA==.',
['Cå']='Cåleb:BAAALgAECgEJAQAAAA==.',
['Cø']='Cønstance:BAAALgAECgcJBwAAAA==.',
Da='Daddyphat:BAAALgAECgcJEwAAAA==.Dalight:BAABLgAECn8XAAINAAYJKiYODwCdAgANAAYJKiYODwCdAgAAAA==.Dankins:BAACLgAFFH8SAAIOAAUJDSGXAQDkAQAOAAUJDSGXAQDkAQAuAAQKfxYAAg4ACAkGHfsZAEgCAA4ACAkGHfsZAEgCAAAA.',
De='Deathmager:BAAALgAECgQJDwAAAA==.Deathtraper:BAAALgAECgYJCgAAAA==.Deltaka:BAAALgAECgEJAQAAAA==.Demonfella:BAAALgADCgMJAwAAAA==.Demonicpeach:BAAALgAFFAIJAgAAAA==.Dethsent:BAAALgAECgQJBAAAAA==.Dette:BAAALgAECgQJBQAAAA==.Devilchaser:BAAALgAECgUJBgAAAA==.Devourer:BAAALgAECgcJEAAAAA==.',
Di='Diaval:BAAALgADCgIJAgABLgAECggJEgAGAAAAAA==.',
Do='Donzilly:BAAALgAECgQJAgAAAA==.Doreme:BAAALgADCgIJAgAAAA==.',
Dr='Drafted:BAAALgAECgcJEAAAAA==.Drax:BAAALgAECgMJAwAAAA==.Drewmcmoo:BAAALgADCgcJBgAAAA==.Drunkorca:BAAALgADCgUJBQAAAA==.',
Ea='Earnar:BAAALgADCgYJDAAAAA==.',
Ed='Edarix:BAAALgADCgcJBgABLgAECgYJGgAPAGIWAA==.',
Ei='Eiliyah:BAABLgAECn8lAAMNAAgJ3Bj1FgBaAgANAAgJ3Bj1FgBaAgAPAAIJHQL3WQElAAAAAA==.',
Ek='Ekmek:BAAALgADCgMJAwAAAA==.',
El='Elabernathy:BAAALgAECgYJEwAAAA==.Elenay:BAAALgAECgUJDAAAAA==.Elfussy:BAAALgAECgEJAQAAAA==.Elgoku:BAAALgAECgQJBgABLgAECgUJCwAGAAAAAA==.Eliarssande:BAAALgADCgQJBAAAAA==.Elinay:BAAALgADCgcJBwABLgAECgUJDAAGAAAAAA==.Elpatron:BAAALgADCgQJBAAAAA==.Elylanea:BAAALgAECgUJCQAAAA==.',
Em='Emulsdeath:BAAALgAECgcJDQABLgAECgcJGgAPABIlAA==.Emulsifier:BAABLgAECn8aAAIPAAcJEiWzEgD9AgAPAAcJEiWzEgD9AgAAAA==.',
En='Ennoa:BAAALgAECgEJAQAAAA==.',
Er='Ergen:BAABLgAECn8gAAIQAAgJax+NBgCVAgAQAAgJax+NBgCVAgAAAA==.',
Eu='Eusexua:BAAALgAECgQJBQABLgAECgUJBgAGAAAAAA==.',
Fa='Fairbear:BAAALgAECgYJEAAAAA==.',
Fi='Filthyfabio:BAAALgADCgcJEQAAAA==.Fireburr:BAAALgAECgMJAwAAAA==.',
Fl='Fløw:BAAALgAECgMJBgAAAA==.',
Fr='Fragglerott:BAAALgAECggJEQAAAA==.Frati:BAAALgAECgEJAQAAAA==.Friedchickn:BAAALgAECgMJBAAAAA==.Frosttrinity:BAAALgADCgUJBAAAAA==.',
Fu='Funslinger:BAAALgAECgIJAwAAAA==.',
Ga='Galannar:BAAALgAECggJDQAAAA==.Galvrax:BAAALgAECgUJCgAAAA==.Gast:BAABLgAECn8bAAMJAAgJjRaSKQAUAgAJAAgJjRaSKQAUAgARAAEJtRtsQABPAAAAAA==.',
Ge='Gearwick:BAAALgADCgMJBAABLgAECgYJFQANACIeAA==.',
Gh='Ghstfacekila:BAAALgADCgEJAQAAAA==.',
Gl='Glizzybreath:BAAALgAECgMJAwAAAA==.',
Go='Gorska:BAABLgAECn8YAAISAAYJHh2WBwCLAQASAAYJHh2WBwCLAQAAAA==.',
Gr='Grawm:BAABLgAECn8aAAMIAAkJdRzhHgAsAgAIAAgJSRXhHgAsAgABAAgJ5hx4PwCxAQAAAA==.Greedory:BAAALgADCgIJAgAAAA==.Groot:BAAALgADCgUJBgAAAA==.Gruetss:BAAALgADCgEJAQAAAA==.',
Ha='Hakoona:BAABLgAECn8ZAAITAAcJ8RkFCAB4AQATAAcJ8RkFCAB4AQAAAA==.Hanginaround:BAAALgADCgYJBgABLgADCgYJBgAGAAAAAA==.Hangman:BAAALgAECgcJDAABLgAECggJMgAUAP8fAA==.Hanni:BAAALgAECgcJDgAAAA==.Haveaburitto:BAACLgAFFH8FAAIVAAMJxBnrDgAXAQAVAAMJxBnrDgAXAQAuAAQKfygAAhUACAk0JXYMAGEDABUACAk0JXYMAGEDAAAA.',
He='Healmemaybe:BAAALgAECgYJDQAAAA==.Healthyadult:BAAALgAECgMJBQAAAA==.Hellshand:BAAALgADCggJCAAAAA==.Heracles:BAAALgAECgQJBAAAAA==.Heretic:BAAALgADCgEJAQAAAA==.',
Hi='Hickscale:BAAALgADCgMJAwAAAA==.',
Ho='Holycøw:BAAALgADCgMJAwAAAA==.Holyhands:BAAALgADCgYJBgAAAA==.Holyholyholy:BAAALgAECgEJAgAAAA==.Honest:BAAALgADCgMJAwAAAA==.',
Hu='Huntrix:BAAALgADCgUJCgAAAA==.',
Ic='Icedatt:BAAALgAECgMJBgAAAA==.Icefire:BAAALgADCgUJBAAAAA==.',
Ik='Ikur:BAABLgAECn8iAAINAAgJwxv0AwA4AgANAAgJwxv0AwA4AgAAAA==.',
Il='Ilinia:BAAALgAECgYJCAAAAA==.',
In='Infoxicated:BAAALgADCgcJBwABLgAECgcJGwACAHYhAA==.',
Ip='Ipopkidneys:BAABLgAECn8gAAMHAAcJ8yWBDADQAgAHAAcJ8yWBDADQAgAMAAEJ8CPsBwBqAAAAAA==.',
Ir='Iroi:BAAALgAECgIJBAAAAA==.',
Is='Iskur:BAAALgAECgYJDgABLgAECggJIgANAMMbAA==.Isuck:BAAALgAECgYJDAAAAA==.Isurr:BAAALgAECgEJAQABLgAECggJIgANAMMbAA==.',
It='Itakecandle:BAAALgADCgkJCQABLgAECgUJCwAGAAAAAA==.',
Iv='Ivanapump:BAAALgAECgIJAgABLgAECgMJAwAGAAAAAA==.',
Ja='Jakbis:BAAALgADCgEJAQAAAA==.Jaldiar:BAAALgADCgcJBwABLgAECgYJBgAGAAAAAA==.Jametrok:BAAALgAECgEJAQAAAA==.Jazbek:BAAALgADCggJEwAAAA==.Jazzonus:BAAALgAECgEJAQAAAA==.',
Je='Jefferey:BAAALgADCgMJAwAAAA==.Jeriçho:BAAALgADCgYJBgAAAA==.',
Jh='Jhonwick:BAAALgAECgIJAgAAAA==.',
Ji='Jippedo:BAAALgAECgYJAgAAAA==.Jiraîya:BAAALgAECgQJBQAAAA==.',
Jo='Jordak:BAABLgAECn8ZAAIUAAcJpB8xAgCjAgAUAAcJpB8xAgCjAgAAAA==.Jorolee:BAAALgADCgEJAQAAAA==.',
Ka='Kallistos:BAAALgAECgQJBAAAAA==.',
Kh='Khione:BAAALgADCgYJBgAAAA==.',
Ki='Kiranam:BAABLgAECn8WAAQWAAgJwwuZEQCTAQAWAAgJqQqZEQCTAQAXAAYJ2wmYCQCEAAAKAAIJWQfHcQBZAAAAAA==.',
Kn='Knarth:BAAALgAECgYJEwAAAA==.',
Ko='Koisy:BAAALgADCgUJBgABLgAECgUJDAAGAAAAAA==.Kole:BAAALgAECgEJAQAAAA==.Koopa:BAABLgAECn8WAAIJAAgJFCCCJAAzAgAJAAgJFCCCJAAzAgAAAA==.',
Kr='Krasul:BAACLgAFFH8FAAIOAAMJjR2mBQALAQAOAAMJjR2mBQALAQAuAAQKfx8AAw4ACAkXIecIAOgCAA4ACAkXIecIAOgCABIABgm/HO8xAJQBAAAA.Krenthok:BAAALgAECgcJBwAAAA==.',
Ku='Kuraha:BAAALgAECgQJBAAAAA==.Kushar:BAAALgAECgQJBQAAAA==.',
La='Large:BAAALgADCgYJBgAAAA==.Largemann:BAAALgAECgIJAgABLgAECggJFwAYAJUjAA==.Lathspell:BAABLgAECn8dAAIVAAgJ+h+gLQC7AgAVAAgJ+h+gLQC7AgAAAA==.Lazyevoker:BAAALgADCgQJBAABLgAECgEJAQAGAAAAAA==.',
Le='Leahan:BAAALgADCgYJCAAAAA==.Leloo:BAAALgADCgYJCgAAAA==.',
Lh='Lhureciv:BAABLgAECn8uAAMEAAgJqyHKBgAeAwAEAAgJqyHKBgAeAwACAAUJuSEvIwB6AQAAAA==.',
Li='Lightchaser:BAAALgADCgMJAgAAAA==.Lightfkyou:BAAALgADCgcJCgAAAA==.Lihvurce:BAAALgAECgQJBQABLgAECggJLgAEAKshAA==.Lillianna:BAABLgAECn8UAAIHAAcJgw7ZCABLAQAHAAcJgw7ZCABLAQAAAA==.',
Lo='Loenhart:BAAALgAECgEJAQAAAA==.Lolkurtone:BAAALgAECgIJAgAAAA==.',
Lu='Luciaan:BAAALgADCgcJEgAAAA==.Lucrative:BAAALgADCgcJDQAAAA==.Lulue:BAAALgADCgQJBAAAAA==.Luminari:BAAALgADCgUJBQAAAA==.Lunastorm:BAABLgAECn8jAAIZAAgJdyInBAAUAwAZAAgJdyInBAAUAwAAAA==.Luponero:BAABLgAECn8dAAMIAAgJ7R3UEACyAgAIAAgJeh3UEACyAgABAAMJjRvZIAD8AAAAAA==.',
Ly='Lynney:BAAALgADCgEJAQAAAA==.',
Ma='Macmn:BAACLgAFFH8IAAISAAQJoRWdAwA4AQASAAQJoRWdAwA4AQAuAAQKfx4AAhIABwnAJF0LAOICABIABwnAJF0LAOICAAAA.Magicard:BAAALgAECgcJCwAAAA==.Makesfood:BAABLgAECn8lAAIVAAcJxhaddADpAQAVAAcJxhaddADpAQAAAA==.Mamaheals:BAAALgAECgYJEQAAAA==.Mandos:BAAALgAECgYJBgAAAA==.Mantistabogn:BAAALgAECgYJDwAAAA==.Maor:BAAALgAECgcJDgAAAA==.Markeisha:BAAALgAECgQJCAAAAA==.',
Me='Mechzician:BAABLgAECn8pAAIVAAgJ/xjiCgD/AQAVAAgJ/xjiCgD/AQAAAA==.Melinoe:BAAALgAECgEJAQAAAA==.Merlerk:BAAALgADCgYJBgAAAA==.Merlini:BAAALgAECgcJCwAAAA==.',
Mi='Micspanky:BAAALgAECgcJEAAAAA==.Mithrandi:BAAALgAECgMJBAAAAA==.',
Mo='Mornhathor:BAAALgAECggJDgABLgAECgYJBgAGAAAAAA==.',
Mu='Mushuu:BAAALgADCgIJBAAAAA==.Musnicker:BAAALgAECgQJBwAAAA==.',
Ne='Neel:BAAALgADCgEJAQAAAA==.Nervhoost:BAAALgADCgMJAwAAAA==.Neuropolis:BAAALgADCgcJBwAAAA==.Neurotics:BAAALgAECgYJEAAAAA==.',
Ni='Niesh:BAAALgAECgEJBAAAAA==.Nineoneone:BAAALgAECgYJEAAAAA==.',
No='Nobledecay:BAAALgAECgQJBAAAAA==.Nocturne:BAAALgAECgEJAgAAAA==.',
Nu='Nubbletcake:BAAALgADCgEJAQABLgAECgcJGwACAHYhAA==.',
Ny='Nylveth:BAABLgAECn8cAAIEAAgJVxqAEgBkAgAEAAgJVxqAEgBkAgAAAA==.',
['Në']='Nëö:BAAALgADCgkJCQAAAA==.',
Oc='Ocra:BAAALgAECgQJBQABLgAECggJLgABAFAeAA==.',
Of='Offspeck:BAAALgAECgEJAQABLgAECggJHgAaACEfAA==.',
Ou='Ouutkast:BAAALgADCgMJAwAAAA==.',
Oz='Ozwald:BAABLgAECn8ZAAIQAAgJoxaFEgCaAQAQAAgJoxaFEgCaAQAAAA==.',
Pa='Pallyangel:BAAALgADCgcJDwAAAA==.Patrio:BAABLgAECn8fAAIZAAgJwxY1AwC/AQAZAAgJwxY1AwC/AQAAAA==.',
Pe='Peaceonea:BAAALgADCggJEwAAAA==.Peachaid:BAECLgAFFH8HAAICAAUJ6BHeBACdAQACAAUJ6BHeBACdAQAuAAQKfycAAwIACAn8ItkEAAgDAAIACAn8ItkEAAgDAAMABgkYHSElAMABAAAA.Peatri:BAAALgAECgkJBAAAAA==.Peetree:BAAALgAECgkJBwAAAA==.',
Ph='Phosphorus:BAABLgAECn80AAMbAAgJZxqRBQCAAgAbAAgJsRmRBQCAAgARAAQJ/hkuJAAdAQAAAA==.',
Pl='Plagüë:BAABLgAECn8uAAMYAAgJwyGAEQATAwAYAAgJwyGAEQATAwAcAAUJhw+mCgDVAAAAAA==.Pleistarchus:BAAALgAECgYJCQAAAA==.',
Po='Poic:BAAALgADCgEJAQAAAA==.',
Pp='Ppgangandlaw:BAAALgADCgEJAQAAAA==.',
Pr='Precious:BAAALgAECgMJAwAAAA==.Primalistic:BAAALgADCgUJBQABLgAECggJKQAVAP8YAA==.Primàl:BAABLgAECn8kAAIUAAYJAhvwNADUAQAUAAYJAhvwNADUAQAAAA==.',
Pu='Purifieds:BAAALgADCgEJAQAAAA==.',
Qs='Qsrqasda:BAAALgAECgQJBQAAAA==.',
Qt='Qtmenopaws:BAAALgAECgEJAQAAAA==.Qtptt:BAACLgAFFH8KAAIdAAMJQxxBHQAPAQAdAAMJQxxBHQAPAQAuAAQKfyoAAh0ACAkgIhoZAL4CAB0ACAkgIhoZAL4CAAAA.',
Ra='Ragedeath:BAAALgAFFAEJAQAAAA==.Ragedh:BAAALgAECgIJAgABLgAFFAEJAQAGAAAAAA==.Ragemonk:BAAALgADCgQJBAABLgAFFAEJAQAGAAAAAA==.Ravinsinda:BAAALgADCggJDQAAAA==.Ravinursula:BAAALgAECgIJAgAAAA==.Rawrsaur:BAAALgAECgUJCwAAAA==.',
Re='Really:BAAALgADCgYJBgAAAA==.Retaliator:BAABLgAECn8aAAIPAAYJYhb3iQBnAQAPAAYJYhb3iQBnAQAAAA==.Revan:BAAALgADCggJDgAAAA==.',
Ri='Rih:BAAALgADCgEJAQAAAA==.Ripits:BAAALgADCgcJCAABLgAECgEJAQAGAAAAAA==.Riskyfist:BAAALgAECgcJAgAAAA==.',
Ro='Rocc:BAAALgAECgQJAwABLgAECgYJAgAGAAAAAA==.Rocketeer:BAABLgAECn8VAAIVAAcJOwmRKQAnAQAVAAcJOwmRKQAnAQAAAA==.Romulis:BAAALgAECgEJAQAAAA==.Ronburgundii:BAAALgADCgIJAgAAAA==.',
Ru='Rudrya:BAABLgAECn8UAAIeAAgJcAfhEwB8AQAeAAgJcAfhEwB8AQAAAA==.Runalish:BAAALgAECgEJAQAAAA==.',
Ry='Rynopinn:BAABLgAECn8yAAIUAAgJ/x8eCwDoAgAUAAgJ/x8eCwDoAgAAAA==.',
['Rí']='Ríco:BAAALgADCgMJCAAAAA==.',
Sa='Saeed:BAAALgADCgQJBAAAAA==.Saelylasia:BAAALgAECgQJBQAAAA==.Sajaboy:BAAALgADCgUJCgAAAA==.Samusaran:BAAALgADCgEJAQAAAA==.Sartha:BAAALgAECgUJCQAAAA==.Sasuka:BAAALgADCgUJBwAAAA==.Satsu:BAAALgAECgEJAQAAAA==.',
Sc='Scatherlia:BAAALgADCgYJBQABLgAECgQJBQAGAAAAAA==.Screwthebull:BAAALgAECgQJBAAAAA==.Scrumpvincet:BAAALgADCgMJBAAAAA==.',
Se='Sectiondk:BAAALgAECgUJCQAAAA==.Sedda:BAABLgAECn8oAAIPAAgJnCXwAADoAgAPAAgJnCXwAADoAgAAAA==.Seigfreid:BAAALgAECgYJCAAAAA==.Sensual:BAABLgAECn8sAAIfAAgJQg6+FACCAQAfAAgJQg6+FACCAQAAAA==.Seraphina:BAAALgAECgQJBQAAAA==.Sessano:BAAALgAECgMJBAAAAA==.Sesshomaru:BAABLgAECn8wAAMFAAgJciMTEwDnAgAFAAgJVSETEwDnAgALAAYJ6CWADgB7AgAAAA==.',
Sh='Shadoly:BAAALgAECgQJBQAAAA==.Shadowboss:BAAALgAECgQJCgAAAA==.Shamnslam:BAAALgAECgEJAQAAAA==.Shang:BAAALgAECgYJEQAAAA==.Shirona:BAAALgAECgQJBAAAAA==.Showstop:BAAALgAECgEJAQAAAA==.Shyvanna:BAABLgAECn8ZAAMgAAgJMQ2bBgCNAQAgAAgJKQ2bBgCNAQAhAAQJ+gl9KwDBAAAAAA==.Shïnïgämï:BAABLgAECn8UAAIiAAYJOCAvCQDeAQAiAAYJOCAvCQDeAQABLgAECggJGAAOAP0WAA==.',
Si='Siare:BAAALgAECgYJDgAAAA==.Silica:BAAALgAECgMJAwAAAA==.Siner:BAAALgAECgMJAwAAAA==.Sixseconds:BAAALgAECgYJDAAAAA==.',
Sk='Skeeter:BAABLgAECn8ZAAMdAAcJBhjuFwBSAQAdAAcJBhjuFwBSAQAaAAQJmxKbFgDMAAAAAA==.Skiadrum:BAABLgAECn8gAAIjAAgJUAbSCgA+AQAjAAgJUAbSCgA+AQAAAA==.Skoliro:BAAALgAECgEJAQAAAA==.Skorch:BAAALgADCgkJEAABLgAECggJKQAVAP8YAA==.',
Sm='Smotts:BAAALgAECgYJCgAAAA==.Smòtts:BAAALgAECgQJBQAAAA==.',
Sn='Snizard:BAAALgAECgMJAwAAAA==.Snuggiepoo:BAABLgAECn8bAAMCAAcJdiFAAQCYAgACAAcJdiFAAQCYAgAEAAMJtBlbQgDnAAAAAA==.',
So='Songbirds:BAAALgADCgcJDQAAAA==.Sonichoos:BAAALgAECgUJCwAAAA==.Sophiel:BAAALgAECgQJBAAAAA==.Soulbark:BAAALgAECgMJAwABLgAECgQJBAAGAAAAAQ==.Soulforged:BAAALgADCgcJCwABLgAECgQJBAAGAAAAAA==.Soulweaver:BAAALgAECgQJBAAAAQ==.',
Sp='Sparrowhåwk:BAAALgADCgUJBgAAAA==.Spàdes:BAAALgAECgYJCwAAAA==.',
St='Starel:BAAALgADCgUJBgAAAA==.Stevebushami:BAAALgAECgYJEAAAAA==.',
Su='Suou:BAAALgADCgcJCQABLgAECgEJAgAGAAAAAA==.Surj:BAAALgAECgQJCAAAAA==.',
Sv='Svmii:BAAALgADCgcJCgAAAA==.',
Ta='Taikuri:BAAALgAECgEJAQABLgAECgYJDgAGAAAAAA==.Taxgirl:BAABLgAECn8XAAIYAAgJlSNeEgANAwAYAAgJlSNeEgANAwAAAA==.',
Th='Thaldreaux:BAAALgAECgMJBAAAAA==.Theleon:BAAALgAECggJEAAAAA==.Thordrin:BAABLgAECn8eAAINAAcJIR8+GABQAgANAAcJIB8+GABQAgAAAA==.Thrasherzs:BAAALgAECgIJAwAAAA==.Thunder:BAAALgADCgQJBAABLgAECgUJBgAGAAAAAA==.Thundergrasp:BAAALgAECgcJDgAAAA==.',
Ti='Tianhe:BAAALgAECgMJAwAAAA==.Tiarisaril:BAAALgAECgYJBgAAAA==.',
To='Tonkah:BAAALgAECgUJBQAAAA==.Topenga:BAABLgAECn8uAAIBAAgJUB5iAwBaAgABAAgJUB5iAwBaAgAAAA==.Touchypope:BAAALgADCgUJBQAAAA==.',
Tr='Treeage:BAAALgADCgMJAwAAAA==.Triggerd:BAAALgADCgEJAQAAAA==.Trunks:BAAALgADCgQJBAAAAA==.Trüst:BAAALgAECggJDQAAAA==.',
Tw='Twicelife:BAAALgADCgYJCgABLgAECggJNAAbAGcaAA==.',
['Tå']='Tånk:BAAALgAECggJCwAAAA==.',
Un='Uneedsummilk:BAAALgADCgcJBwAAAA==.Unholyapollo:BAAALgADCgYJCwAAAA==.',
Ur='Urthstripe:BAAALgAECgQJCAAAAA==.',
Va='Vae:BAAALgAECgIJAgABLgAFFAIJBQAYAJcgAA==.Valle:BAAALgADCgEJAQABLgAFFAYJEwAEAMUcAA==.',
Ve='Velarenea:BAAALgADCgEJAQAAAA==.Velgabrine:BAAALgADCggJEgABLgAECgcJGgAPABIlAA==.Veraani:BAAALgAECgYJBgAAAA==.Verra:BAAALgADCgYJBgAAAA==.',
Vi='Vil:BAAALgADCgcJBgAAAA==.Virlan:BAAALgADCgQJBAAAAA==.Viserion:BAAALgAECgYJDQAAAA==.',
Vo='Voidchaosfan:BAAALgAECgQJBQABLgAECgQJCAAGAAAAAA==.',
Vu='Vue:BAABLgAECn8pAAINAAgJlRo4HwAfAgANAAgJlRo4HwAfAgAAAA==.Vuldin:BAAALgAECgEJAgAAAA==.',
['Vö']='Völdemört:BAAALgADCgIJAgAAAA==.',
Wa='Wakasham:BAACLgAFFH8JAAIeAAQJDx50AQCAAQAeAAQJDx50AQCAAQAuAAQKfyUAAh4ACAnjJZ4BAFMDAB4ACAnjJZ4BAFMDAAAA.',
We='Wehonoryou:BAAALgAECgUJEAAAAA==.Wetard:BAAALgADCgIJAgAAAA==.',
Wi='Willbyers:BAAALgADCgEJAQAAAA==.',
Wo='Wolfpacked:BAABLgAECn8YAAIOAAgJ/RajIgAPAgAOAAgJ/RajIgAPAgAAAA==.Wolfzbåin:BAAALgAECgQJBAAAAA==.',
Wr='Wroot:BAAALgADCgYJCQAAAA==.',
Wu='Wunderlust:BAABLgAECn8pAAIVAAgJPiAhHAAGAwAVAAgJPiAhHAAGAwAAAA==.',
Xe='Xemon:BAAALgAECgIJAgAAAA==.',
Xm='Xmatick:BAAALgAECgcJBgAAAA==.',
Ye='Yellowshaman:BAACLgAFFH8IAAISAAQJTAvdCwAuAQASAAQJTAvdCwAuAQAuAAQKfyMAAhIACAkZHz8MANcCABIACAkZHz8MANcCAAAA.Yerac:BAAALgAECgEJAQAAAA==.',
Yu='Yukikage:BAAALgAECgMJAwAAAA==.Yutdaeng:BAAALgAECgMJBAAAAA==.',
Yv='Yvent:BAAALgADCgIJAgAAAA==.',
Za='Zakcarii:BAAALgADCgMJCAAAAA==.Zalicy:BAAALgAECgYJDQAAAA==.Zalogar:BAAALgAECgUJBgAAAA==.Zapper:BAAALgAECgIJAgAAAA==.',
Ze='Zealot:BAAALgAECgEJAQAAAA==.Zeeasyez:BAAALgAECgYJDQAAAA==.Zestul:BAAALgADCgEJAQAAAA==.',
Zh='Zhane:BAAALgADCgEJAQAAAA==.',
Zo='Zordon:BAAALgAECgYJCwAAAA==.',
Zu='Zuriznikov:BAAALgADCgUJBQABLgAECgYJDQAGAAAAAA==.',
['Øf']='Øffspeck:BAABLgAECn8eAAQaAAgJIR9DAABTAgAdAAcJDhsVLgBVAgAaAAcJFyFDAABTAgAkAAMJzh7MMAD3AAAAAA==.',
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

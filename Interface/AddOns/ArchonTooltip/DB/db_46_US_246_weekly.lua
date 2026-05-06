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

local lookup = {'Hunter-BeastMastery','Priest-Discipline','Priest-Holy','Priest-Shadow','DemonHunter-Devourer','Druid-Restoration','Unknown-Unknown','Warrior-Arms','Rogue-Subtlety','Hunter-Survival','Hunter-Marksmanship','Warrior-Fury','Druid-Balance','DemonHunter-Havoc','Rogue-Assassination','Monk-Brewmaster','Paladin-Holy','Shaman-Restoration','Warlock-Demonology','DeathKnight-Frost','Paladin-Retribution','Evoker-Preservation','Warrior-Protection','Shaman-Elemental','Mage-Frost','Druid-Feral','Druid-Guardian','Mage-Fire','DeathKnight-Unholy','Warlock-Destruction','Warlock-Affliction','DeathKnight-Blood','Shaman-Enhancement','Paladin-Protection','Evoker-Augmentation','Evoker-Devastation','DemonHunter-Vengeance','Monk-Mistweaver',}
local provider = {region='US',realm='Zuluhed',name='US',type='weekly',zone=46,date='2026-05-01',data={Aa='Aaronfreeze:BAABLgAECn8tAAIBAAkJ6hy+AwDKAgABAAkJ6hy+AwDKAgAAAA==.',
Ab='Abrakazaam:BAAALgADCgEJAQAAAA==.',
Ad='Adrios:BAABLgAECn8iAAQCAAgJEBVvEACHAQACAAgJ/hRvEACHAQADAAMJyggSaQCIAAAEAAUJgAZHMQB3AAAAAA==.',
Aj='Ajaxz:BAAALgAECggJEwAAAA==.',
Al='Albedô:BAAALgAECgUJBgABLgAECgkJOAAFACMiAA==.Aliren:BAAALgAECgYJCgAAAA==.Allmaick:BAAALgADCggJCAAAAA==.Alucard:BAAALgAECgQJBgAAAA==.Alystrasza:BAABLgAECn8WAAIGAAYJvRb0HgCJAQAGAAYJvRb0HgCJAQAAAA==.',
An='Antimovsky:BAAALgAECgYJCgAAAA==.',
Aq='Aqours:BAAALgADCgcJBwABLgAECgEJAgAHAAAAAA==.',
Ar='Arcan:BAAALgAECgIJAgAAAA==.',
Au='Augustine:BAAALgAECgEJAQAAAA==.Auroras:BAABLgAECn8XAAIDAAcJhROEFQBjAQADAAcJhROEFQBjAQAAAA==.',
Av='Aviaria:BAAALgAECgQJBAAAAA==.Avìendha:BAAALgADCgEJAQAAAA==.',
['Aì']='Aìnzooalgown:BAAALgAECgQJDAABLgAECgkJOAAFACMiAA==.',
Ba='Babakubwa:BAAALgAECgMJAwAAAA==.Babylonfive:BAAALgAECgcJCQAAAA==.Balhair:BAAALgADCgYJBgAAAA==.Banish:BAAALgAECgMJAgABLgAECgcJCgAHAAAAAA==.Barragdan:BAAALgADCgEJAQAAAA==.Basandra:BAAALgADCgQJBAAAAA==.Basicc:BAAALgADCgMJAwAAAA==.',
Be='Berserk:BAEBLgAECn8XAAIIAAYJISI3BQDcAQAIAAYJISI3BQDcAQABLgAFFAMJBQAJAMUMAA==.Bertringer:BAAALgAECgEJAgAAAA==.',
Bi='Bigmack:BAAALgAECgYJCwAAAA==.Bigwilli:BAAALgAECgQJCwAAAA==.Bingßong:BAAALgADCgUJBQAAAA==.Biscuit:BAACLgAFFH8FAAMBAAIJfhdmHABzAAAKAAIJ+REAEAChAAABAAIJfhdmHABzAAAuAAQKfx4ABAsACAmoIXYPAMECAAsACAl6HXYPAMECAAoAAwmnHfcWAAkBAAEABAk6FZJYAMAAAAAA.Bisha:BAABLgAECn8xAAIMAAkJIh0UAgDNAgAMAAkJIh0UAgDNAgAAAA==.Bizcocho:BAAALgAECgYJCwAAAA==.',
Bl='Black:BAAALgADCgEJAQAAAA==.Blastthemuff:BAAALgADCgQJBAAAAA==.Bloodsimple:BAAALgADCgUJBQAAAA==.Blákers:BAAALgAECgYJCAAAAA==.',
Bo='Boic:BAAALgADCgQJBAAAAA==.Bonesofdoom:BAAALgAECgUJCAAAAA==.Boogsta:BAAALgADCgcJEgAAAA==.Boomkingobrr:BAACLgAFFH8HAAINAAMJ5gjQEgDeAAANAAMJ5gjQEgDeAAAuAAQKfxsAAg0ACQkOHEALAOECAA0ACQkOHEALAOECAAAA.Boops:BAAALgAECgEJAQAAAA==.Bootysweatt:BAABLgAECn8aAAIOAAYJNhtiJACaAQAOAAYJNhtiJACaAQAAAA==.Boss:BAAALgADCgEJAQAAAA==.',
Br='Brewnz:BAAALgAECgUJBgAAAA==.',
Bu='Buckits:BAAALgAECgcJDgAAAA==.Bunsey:BAAALgADCgIJAgAAAA==.Burnsx:BAAALgAECgUJCgABLgAFFAYJDwAFAOUfAA==.',
Bw='Bwoar:BAAALgAECgQJBgAAAA==.',
['Bø']='Bøw:BAAALgAECgMJAwAAAA==.',
['Bü']='Bübble:BAAALgADCgEJAQAAAA==.',
Ca='Captnmurloc:BAAALgAECgYJCAAAAA==.Carl:BAAALgAECgEJAQABLgAFFAUJCgAPAMkcAA==.Caveyodeler:BAAALgAECgQJCgAAAA==.',
Ce='Cedar:BAAALgAECgIJAgAAAA==.',
Ch='Cherga:BAAALgADCgYJBgAAAA==.Chinegga:BAAALgADCgYJBgAAAA==.Chitose:BAAALgADCgUJBQABLgAECgEJAgAHAAAAAA==.Chrapsasspee:BAAALgADCgcJEwAAAA==.Chrinn:BAAALgADCgIJAgAAAA==.',
Ci='Cindele:BAAALgADCgMJAwAAAA==.Cirvix:BAAALgAECgYJDAAAAA==.Cirxe:BAAALgAECgcJDQAAAA==.',
Cl='Clampire:BAAALgAECgQJBAAAAA==.Cliint:BAAALgAECgUJBgAAAA==.Cluumn:BAAALgAECgkJCgAAAA==.',
Co='Coms:BAAALgADCgIJAgAAAA==.Cooz:BAAALgAECgUJBgAAAA==.Corybooker:BAAALgAECgcJBAAAAA==.Cowdux:BAAALgADCgEJAQAAAA==.',
Cr='Creamdragon:BAAALgADCgYJCgABLgAECgYJEgAHAAAAAA==.',
Cu='Curuni:BAAALgADCgYJBgAAAA==.',
Cz='Czechhunter:BAAALgADCgUJBQAAAA==.',
['Cå']='Cåleb:BAAALgAECgEJAQAAAA==.',
['Cø']='Cønstance:BAAALgAECgcJCAAAAA==.',
Da='Daddyphat:BAABLgAECn8ZAAIQAAcJjCKFBABrAgAQAAcJjCKFBABrAgAAAA==.Dalight:BAABLgAECn8XAAIRAAYJKiYLDwCdAgARAAYJKiYLDwCdAgAAAA==.Dankins:BAACLgAFFH8WAAISAAUJHSGYAQDkAQASAAUJHSGYAQDkAQAuAAQKfxYAAhIACAkGHfYZAEcCABIACAkGHfYZAEcCAAAA.',
De='Deathmager:BAAALgAECgUJEwAAAA==.Deathtraper:BAAALgAECgcJDAAAAA==.Debur:BAAALgADCgEJAQAAAA==.Deltaka:BAAALgAECgEJAQAAAA==.Demonfella:BAAALgADCgMJAwAAAA==.Demonicpeach:BAABLgAECn8VAAITAAYJ9Ax8VADzAAATAAYJ9Ax8VADzAAAAAA==.Dethsent:BAAALgAECgQJBgAAAA==.Dette:BAAALgAECgQJBgAAAA==.Devilchaser:BAAALgAECgUJBgAAAA==.Devourer:BAAALgAECgcJEQAAAA==.',
Di='Diaval:BAAALgADCgIJAgABLgAECggJGQATALMQAA==.',
Do='Donzilly:BAAALgAECgQJAgAAAA==.Doreme:BAAALgADCgIJAgAAAA==.',
Dr='Drafted:BAAALgAECgcJEAAAAA==.Drax:BAAALgAECgMJAwAAAA==.Drewmcmoo:BAAALgADCgcJBgAAAA==.Drunkorca:BAAALgADCgUJBQABLgAECggJJAAUAKoXAA==.',
Ea='Earnar:BAAALgADCgYJDAAAAA==.',
Ed='Edarix:BAAALgADCgcJBgABLgAECgYJHAAVAGIWAA==.',
Ei='Eiliyah:BAABLgAECn8vAAMRAAgJehz1FgBaAgARAAgJehz1FgBaAgAVAAIJHQIYWgElAAAAAA==.',
Ek='Ekmek:BAAALgAECgEJAQAAAA==.',
El='Elabernathy:BAABLgAECn8aAAIBAAcJjhNcIQCaAQABAAcJjhNcIQCaAQAAAA==.Elenay:BAAALgAECgUJDQAAAA==.Elfussy:BAAALgAECgEJAQAAAA==.Elgoku:BAAALgAECgQJCQABLgAECgUJCwAHAAAAAA==.Eliarssande:BAAALgADCgQJBAAAAA==.Elinay:BAAALgADCgcJCQABLgAECgUJDQAHAAAAAA==.Elixia:BAAALgAECgQJBAAAAA==.Elpatron:BAAALgADCgQJBAABLgAECggJJQAWAOAWAA==.Elylanea:BAAALgAECgUJDgAAAA==.',
Em='Emulsdeath:BAAALgAECgcJDQABLgAECggJIgAVAA4mAA==.Emulsifier:BAABLgAECn8iAAIVAAgJDiZzAgAKAwAVAAgJDiZzAgAKAwAAAA==.',
En='Ennoa:BAAALgAECgEJAQAAAA==.',
Er='Ergen:BAACLgAFFH8FAAIKAAMJ0gbKCwDdAAAKAAMJ0gbKCwDdAAAuAAQKfyIAAgoACAlrH48GAJUCAAoACAlrH48GAJUCAAAA.',
Eu='Eusexua:BAAALgAECgQJBQABLgAECgcJCgAHAAAAAA==.',
Fa='Fairbear:BAABLgAECn8WAAQMAAYJORYQGABwAQAMAAYJORYQGABwAQAIAAEJZA5pPgA7AAAXAAEJ6QcqLwAkAAAAAA==.',
Fi='Filthyfabio:BAAALgADCgcJEQAAAA==.Fireburr:BAAALgAECgMJAwAAAA==.',
Fl='Fløw:BAAALgAECgMJBwAAAA==.',
Fr='Fragglerott:BAABLgAECn8VAAMYAAgJWQjFMQCzAAAYAAgJWQjFMQCzAAASAAIJJAi/kQBTAAAAAA==.Frati:BAAALgAECgEJAQAAAA==.Friedchickn:BAAALgAECgMJBwAAAA==.Frosttrinity:BAAALgADCgUJBAAAAA==.',
Fu='Funslinger:BAAALgAECgMJBgAAAA==.',
Ga='Galannar:BAAALgAECggJDQAAAA==.Galvrax:BAAALgAECgUJCgAAAA==.Gast:BAABLgAECn8cAAMMAAgJsxaVKQAUAgAMAAgJsxaVKQAUAgAXAAEJtRtyQABPAAAAAA==.',
Ge='Gearwick:BAAALgADCgMJBAABLgAECgYJHgARAMogAA==.',
Gh='Ghstfacekila:BAAALgADCgEJAQAAAA==.',
Gl='Glizzybreath:BAAALgAECgMJAwAAAA==.',
Go='Gorska:BAABLgAECn8gAAIYAAgJFB3sBQBRAgAYAAgJFB3sBQBRAgAAAA==.',
Gr='Grawm:BAABLgAECn8dAAMLAAkJ9BziHgArAgALAAgJSRXiHgArAgABAAgJeB1yPwCxAQAAAA==.Greedory:BAAALgADCgIJAgAAAA==.Groot:BAAALgADCgUJBgAAAA==.Gruetss:BAAALgAECgQJBAAAAA==.Gréy:BAAALgADCgQJBAABLgAECggJNgAGAGwjAA==.',
Ha='Hailbringer:BAAALgAECgcJBwAAAA==.Hakoona:BAABLgAECn8hAAIQAAgJ+BdACgDnAQAQAAgJ+BdACgDnAQAAAA==.Hanginaround:BAAALgAECgEJAQAAAA==.Hangman:BAAALgAFFAIJBAABLgAECggJNgAGAGwjAA==.Hanni:BAABLgAECn8VAAILAAcJTxm6BQCcAQALAAcJTxm6BQCcAQAAAA==.Haveaburitto:BAACLgAFFH8JAAIZAAQJVhwyEwBzAQAZAAQJVhwyEwBzAQAuAAQKfygAAhkACAk0JXwMAGEDABkACAk0JXwMAGEDAAAA.',
He='Healmemaybe:BAAALgAECgYJEQAAAA==.Healthyadult:BAAALgAECgMJBQAAAA==.Hellshand:BAAALgADCggJCAAAAA==.Heracles:BAAALgAECgQJBAAAAA==.Heretic:BAAALgADCgEJAQAAAA==.',
Hi='Hickscale:BAAALgADCgMJAwAAAA==.',
Ho='Holycøw:BAAALgADCgMJAwAAAA==.Holyhands:BAAALgADCgYJBgAAAA==.Holyholyholy:BAAALgAECgEJAgAAAA==.Honest:BAAALgADCgMJAwAAAA==.',
Hu='Hunniee:BAAALgAECgEJAQAAAA==.Huntrix:BAAALgADCgUJCgAAAA==.',
Ic='Icedatt:BAAALgAECgMJBgAAAA==.Icefire:BAAALgADCgUJBAAAAA==.',
Ik='Ikur:BAABLgAECn8kAAIRAAgJwxubCgAtAgARAAgJwxubCgAtAgAAAA==.',
Il='Ilinia:BAAALgAECgYJCAABLgAECgQJBgAHAAAAAA==.',
In='Infoxicated:BAAALgADCgcJBwABLgAECggJHwACAL4gAA==.',
Ip='Ipopkidneys:BAACLgAFFH8IAAMPAAQJCB1FAgAkAQAPAAMJ/xlFAgAkAQAJAAMJ9RQRDgAFAQAuAAQKfyEAAwkACAn6JYIMANACAAkACAn6JYIMANACAA8AAQnwI8wPAGcAAAAA.',
Ir='Iroi:BAAALgAECgIJBAAAAA==.',
Is='Iskur:BAAALgAECgYJEwABLgAECggJJAARAMMbAA==.Isuck:BAAALgAECgYJDAAAAA==.Isurr:BAAALgAECgYJCgABLgAECggJJAARAMMbAA==.',
It='Itakecandle:BAAALgADCgkJCgABLgAECgUJCwAHAAAAAA==.',
Iv='Ivanapump:BAAALgAECgIJAgABLgAECgMJAwAHAAAAAA==.',
Ja='Jadethecat:BAAALgADCgMJAwAAAA==.Jakbis:BAAALgADCgEJAQAAAA==.Jaldiar:BAAALgADCgcJBwABLgAECgYJBgAHAAAAAA==.Jametrok:BAAALgAECgEJAQAAAA==.Jazbek:BAAALgAECgEJAQAAAA==.Jazzonus:BAAALgAECgEJAQAAAA==.',
Je='Jefferey:BAAALgADCgMJAwAAAA==.Jeriçho:BAAALgADCgYJBgAAAA==.',
Jh='Jhonwick:BAAALgAECgIJAgAAAA==.',
Ji='Jippedo:BAAALgAECgYJAgABLgAECgcJAwAHAAAAAA==.Jiraîya:BAAALgAECgQJBQAAAA==.',
Jo='Jordak:BAABLgAECn8aAAIGAAgJcBwxBgC1AgAGAAgJcBwxBgC1AgAAAA==.Jorolee:BAAALgADCgEJAQAAAA==.',
Ka='Kallistos:BAAALgAECgcJDwAAAA==.Karunik:BAAALgADCgYJBgABLgAECgcJCgAHAAAAAA==.',
Kh='Khione:BAAALgADCgYJBgAAAA==.',
Ki='Kibblerina:BAAALgADCgcJBwAAAA==.Kiranam:BAABLgAECn8cAAQaAAgJqQ6bEQCTAQAaAAgJqQqbEQCTAQAbAAcJJgynDQDdAAANAAIJWQfPcQBZAAAAAA==.',
Kn='Knarth:BAABLgAECn8aAAIcAAcJ0hWsAQCuAQAcAAcJ0hWsAQCuAQAAAA==.',
Ko='Koisy:BAAALgAECgIJAwABLgAECgUJDQAHAAAAAA==.Kole:BAAALgAECgEJAQAAAA==.Koopa:BAABLgAECn8eAAIMAAgJqyHpBABxAgAMAAgJqyHpBABxAgAAAA==.',
Kr='Krasul:BAACLgAFFH8JAAISAAQJ4RwcCQBVAQASAAQJ4RwcCQBVAQAuAAQKfx8AAxIACAkXIecIAOgCABIACAkXIecIAOgCABgABgm/HPExAJQBAAAA.Krenthok:BAAALgAECggJDwAAAA==.',
Ku='Kuraha:BAAALgAECgQJBAAAAA==.Kushar:BAAALgAECgQJBQAAAA==.',
La='Large:BAAALgADCgYJBgAAAA==.Largemann:BAAALgAECgUJBgABLgAFFAMJBQAdAH0bAA==.Lathspell:BAABLgAECn8hAAIZAAgJDyCiLQC7AgAZAAgJDyCiLQC7AgAAAA==.Lazyevoker:BAAALgADCgQJBAABLgAECgEJAQAHAAAAAA==.',
Le='Leahan:BAAALgAECgMJBgAAAA==.Leloo:BAAALgADCgYJCgABLgAECgEJAQAHAAAAAA==.',
Lh='Lhureciv:BAABLgAECn8yAAMEAAkJRR76AgCWAgAEAAgJViH6AgCWAgACAAYJ+R4uIwB6AQAAAA==.',
Li='Lightchaser:BAAALgADCgMJAgAAAA==.Lightfkyou:BAAALgADCgcJCgAAAA==.Lihvurce:BAAALgAECgQJBwABLgAECgkJMgAEAEUeAA==.Lillianna:BAABLgAECn8bAAIJAAcJBxGcDQCSAQAJAAcJBxGcDQCSAQAAAA==.',
Ll='Llew:BAAALgAECgEJAQAAAA==.',
Lo='Loenhart:BAAALgAECgEJAQAAAA==.Lolkurtone:BAAALgAECgIJAgAAAA==.',
Lu='Luciaan:BAAALgADCgcJEgAAAA==.Lucrative:BAAALgADCgcJDQAAAA==.Lulue:BAAALgADCgQJBAAAAA==.Luminari:BAAALgADCgUJBQAAAA==.Lunastorm:BAABLgAECn8rAAIWAAkJESDKAAA8AwAWAAkJESDKAAA8AwAAAA==.Luponero:BAABLgAECn8dAAMLAAgJ7R3UEACyAgALAAgJeh3UEACyAgABAAMJjRvdSAD3AAAAAA==.',
Ly='Lynney:BAAALgADCgEJAQAAAA==.',
Ma='Macmn:BAACLgAFFH8MAAIYAAQJyBbRCQA/AQAYAAQJyBbRCQA/AQAuAAQKfx4AAhgABwnAJGELAOICABgABwnAJGELAOICAAAA.Magicard:BAAALgAECgcJCwAAAA==.Makesfood:BAABLgAECn8oAAIZAAcJZBe4OwB7AQAZAAcJZBe4OwB7AQAAAA==.Mamaheals:BAABLgAECn8dAAIDAAYJdRoeJwC1AQADAAYJdRoeJwC1AQAAAA==.Mandos:BAAALgAECgYJBgAAAA==.Mantistabogn:BAAALgAECgYJDwAAAA==.Maor:BAAALgAECgcJEAAAAA==.March:BAAALgADCgEJAQAAAA==.Markeisha:BAAALgAECgQJCAAAAA==.',
Me='Mechzician:BAABLgAECn8pAAIZAAgJ/xiNIADqAQAZAAgJ/xiNIADqAQAAAA==.Melinoe:BAAALgAECgEJAQAAAA==.Merlerk:BAAALgADCgYJBgAAAA==.Merlini:BAAALgAECgcJDQAAAA==.',
Mi='Micspanky:BAAALgAECggJEgAAAA==.Mithrandi:BAAALgAECgMJBAAAAA==.',
Mo='Mornhathor:BAAALgAECggJDgABLgAECgYJBgAHAAAAAA==.',
Mu='Mufinblaster:BAAALgADCgEJAQAAAA==.Mushuu:BAAALgADCgIJBAAAAA==.Musnicker:BAAALgAECgQJBwAAAA==.',
['Mè']='Mètis:BAAALgAECgYJBgAAAA==.',
Ne='Neel:BAAALgADCgEJAQAAAA==.Nervhoost:BAAALgADCgMJAwAAAA==.Neuropolis:BAAALgADCgcJBwAAAA==.Neurotics:BAABLgAECn8WAAQeAAYJxiQ5AgD5AQAeAAYJHiM5AgD5AQAfAAMJ+yTJBABHAQATAAQJGRz0ugDjAAAAAA==.',
Ni='Niesh:BAAALgAECgEJBwAAAA==.Nineoneone:BAABLgAECn8WAAMDAAYJSBTuFwBLAQADAAYJSBTuFwBLAQACAAQJjgPnRQCLAAAAAA==.',
No='Nobledecay:BAAALgAECgQJBQAAAA==.Nocturne:BAAALgAECgEJAwAAAA==.',
Nu='Nubbletcake:BAAALgADCgEJAQABLgAECggJHwACAL4gAA==.',
Ny='Nylveth:BAABLgAECn8hAAIEAAkJrxkOCwDOAQAEAAkJrxkOCwDOAQAAAA==.',
['Në']='Nëö:BAAALgAECgYJDQAAAA==.',
Oc='Ocra:BAAALgAECgQJBwABLgAECgkJNgABACYcAA==.',
Of='Offspeck:BAAALgAECgEJAQABLgAECggJHwAfACEfAA==.',
Ou='Ouutkast:BAAALgADCgMJAwAAAA==.',
Oz='Ozwald:BAABLgAECn8hAAIKAAkJ5BeEAgCGAgAKAAkJ5BeEAgCGAgAAAA==.',
Pa='Pallyangel:BAAALgADCgcJDwAAAA==.Patrio:BAABLgAECn8lAAIWAAgJ4BbcBAAaAgAWAAgJ4BbcBAAaAgAAAA==.',
Pe='Peaceonea:BAAALgAECgIJAgAAAA==.Peachaid:BAECLgAFFH8LAAICAAYJjxfgBACdAQACAAYJjxfgBACdAQAuAAQKfzAAAwIACQlUItAAAG0DAAIACQlUItAAAG0DAAMABgkYHSIlAMABAAAA.Peatri:BAAALgAECgkJBAAAAA==.Peetree:BAAALgAECgkJBwAAAA==.',
Ph='Phosphorus:BAABLgAECn88AAMIAAkJ4hi0AQCKAgAIAAkJQhi0AQCKAgAXAAQJ/hksJAAdAQAAAA==.',
Pl='Plagüë:BAABLgAECn83AAMdAAkJ4iKuBQDIAgAdAAkJ4iKuBQDIAgAgAAUJhw+RGQCwAAAAAA==.Pleistarchus:BAAALgAECgYJCQAAAA==.',
Po='Poic:BAAALgADCgEJAQAAAA==.Poofighter:BAAALgAECgMJAwABLgAECgkJOAAFACMiAA==.',
Pp='Ppgangandlaw:BAAALgADCgEJAQAAAA==.',
Pr='Precious:BAAALgAECgMJBgAAAA==.Primalistic:BAAALgADCgUJBQABLgAECggJKQAZAP8YAA==.Primàl:BAABLgAECn8lAAIGAAYJAhv4NADUAQAGAAYJAhv4NADUAQAAAA==.',
Pu='Purifieds:BAAALgADCgEJAQAAAA==.',
Qs='Qsrqasda:BAAALgAECgUJCAAAAA==.',
Qt='Qtmenopaws:BAAALgAECgMJAQAAAA==.Qtptt:BAACLgAFFH8NAAITAAMJQxw+HQAPAQATAAMJQxw+HQAPAQAuAAQKfzIAAhMACAkRIxEHAJwCABMACAkRIxEHAJwCAAAA.',
Ra='Ragedeath:BAAALgAFFAIJAwAAAA==.Ragedh:BAAALgAECgIJAgABLgAFFAIJAwAHAAAAAA==.Ragemonk:BAAALgADCgQJBAABLgAFFAIJAwAHAAAAAA==.Rasmong:BAAALgAECgEJAQABLgAECgQJBQAHAAAAAA==.Ravinsinda:BAAALgADCggJDQAAAA==.Ravinursula:BAAALgAECgUJBwAAAA==.Rawrsaur:BAAALgAECgUJCwAAAA==.',
Re='Really:BAAALgADCgYJBgABLgAECgEJAQAHAAAAAA==.Redder:BAAALgAECgEJAQAAAA==.Retaliator:BAABLgAECn8cAAIVAAYJYhb0iQBnAQAVAAYJYhb0iQBnAQAAAA==.Revan:BAAALgADCggJDgAAAA==.',
Ri='Rih:BAAALgADCgEJAQAAAA==.Ripits:BAAALgADCgcJCAABLgAECgEJAQAHAAAAAA==.Risky:BAAALgAECgkJAwAAAA==.Riskyfist:BAAALgAECgcJAgAAAA==.Risquae:BAAALgAECgEJAQAAAA==.',
Ro='Rocc:BAAALgAECgcJAwAAAA==.Rocketeer:BAABLgAECn8bAAIZAAgJbApLSQBTAQAZAAgJbApLSQBTAQAAAA==.Romulis:BAAALgAECgEJAQAAAA==.Ronburgundii:BAAALgADCgIJAgAAAA==.',
Ru='Rudrya:BAABLgAECn8UAAIhAAgJcAfiEwB8AQAhAAgJcAfiEwB8AQAAAA==.Runalish:BAAALgAECgEJAQAAAA==.Runarinis:BAAALgADCgIJAgAAAA==.',
Ry='Rynopinn:BAABLgAECn82AAIGAAgJbCMdCwDoAgAGAAgJbCMdCwDoAgAAAA==.',
['Rí']='Ríco:BAAALgADCgUJCgAAAA==.',
Sa='Saeed:BAAALgADCgQJBAAAAA==.Saelylasia:BAAALgAECgQJBQAAAA==.Sajaboy:BAAALgADCgUJCgAAAA==.Samusaran:BAAALgADCgEJAQAAAA==.Sartha:BAABLgAECn8UAAIVAAYJTxLPQQBEAQAVAAYJTxLPQQBEAQAAAA==.Sasuka:BAAALgADCgUJBwAAAA==.Satsu:BAAALgAECgEJAQAAAA==.',
Sc='Scatherlia:BAAALgADCgYJBQABLgAECgQJBQAHAAAAAA==.Sco:BAAALgADCgEJAQAAAA==.Screwthebull:BAAALgAECgQJBAAAAA==.Scrumpvincet:BAAALgADCgMJBAAAAA==.',
Se='Sectiondk:BAAALgAECgYJDwAAAA==.Sedda:BAACLgAFFH8KAAIVAAQJ2xiiDwBIAQAVAAQJ2xiiDwBIAQAuAAQKfygAAhUACAmcJewDAOICABUACAmcJewDAOICAAAA.Seigfreid:BAAALgAECgYJCAAAAA==.Sensual:BAABLgAECn80AAIiAAkJAA9WBwCmAQAiAAkJAA9WBwCmAQAAAA==.Seraphina:BAAALgAECgQJCQAAAA==.Sessano:BAAALgAECgMJBAAAAA==.Sesshomaru:BAABLgAECn84AAMFAAkJIyL3BQB+AgAFAAgJYyH3BQB+AgAOAAcJsSOADgB7AgAAAA==.',
Sh='Shadoly:BAAALgAECgYJDAAAAA==.Shadowboss:BAAALgAECgQJEAAAAA==.Shamnslam:BAAALgAECgEJAQAAAA==.Shang:BAABLgAECn8aAAMNAAgJax9pBABzAgANAAgJax9pBABzAgAGAAEJCxNRywA0AAAAAA==.Shirona:BAAALgAECgQJBAAAAA==.Showstop:BAAALgAECgEJAQAAAA==.Shyvanna:BAABLgAECn8fAAMjAAgJsBHkDgCfAQAjAAgJsBHkDgCfAQAkAAQJ+gmBKwDBAAAAAA==.Shïnïgämï:BAABLgAECn8UAAIlAAYJOCAwCQDeAQAlAAYJOCAwCQDeAQABLgAECgkJHwASAMMbAA==.',
Si='Siare:BAAALgAECgYJDwAAAA==.Silica:BAAALgAECgMJAwAAAA==.Siner:BAAALgAECgQJBQAAAA==.',
Sk='Skeeter:BAABLgAECn8hAAQTAAgJ/BiYJgCVAQATAAgJWRiYJgCVAQAfAAYJvxYGBQA9AQAeAAEJDxpdHABMAAAAAA==.Skiadrum:BAABLgAECn8rAAImAAgJYwiaGQA4AQAmAAgJYwiaGQA4AQAAAA==.Skoliro:BAAALgAECgEJAQAAAA==.Skorch:BAAALgADCgkJEAABLgAECggJKQAZAP8YAA==.',
Sm='Smotts:BAAALgAECgYJCwAAAA==.Smòtts:BAAALgAECgQJBQAAAA==.',
Sn='Snizard:BAAALgAECgUJCAAAAA==.Snuggiepoo:BAABLgAECn8fAAMCAAgJviCLAgDfAgACAAgJviCLAgDfAgAEAAUJBxZmQgDnAAAAAA==.',
So='Songbirds:BAAALgADCgcJDQAAAA==.Sonichoos:BAAALgAECgUJCwAAAA==.Sophiel:BAAALgAECgYJDQAAAA==.Soulbark:BAAALgAECgMJAwABLgAECgQJBAAHAAAAAQ==.Souleater:BAAALgADCgMJAwAAAA==.Soulforged:BAAALgADCgcJCwABLgAECgQJBAAHAAAAAA==.Soulweaver:BAAALgAECgQJBAAAAQ==.',
Sp='Sparrowhåwk:BAAALgADCgUJBgAAAA==.Spongebill:BAAALgADCgEJAQAAAA==.Spàdes:BAAALgAECgYJDgAAAA==.',
St='Starel:BAAALgADCgUJBgAAAA==.Stevebushami:BAAALgAECgYJEAAAAA==.',
Su='Suou:BAAALgADCgcJCQABLgAECgEJAgAHAAAAAA==.Surj:BAAALgAECgQJDQAAAA==.',
Sv='Svmii:BAAALgADCgcJCgAAAA==.',
Ta='Taikuri:BAAALgAECgIJAwABLgAECgYJDwAHAAAAAA==.Taxgirl:BAACLgAFFH8FAAMdAAMJfRuAMAABAQAdAAMJfRuAMAABAQAUAAEJewOOBwBIAAAuAAQKfxkAAh0ACAncI2ESAA0DAB0ACAncI2ESAA0DAAAA.',
Th='Thaldreaux:BAAALgAECgMJBAAAAA==.Theleon:BAABLgAECn8XAAINAAgJMQ5cEQCEAQANAAgJMQ5cEQCEAQAAAA==.Thordrin:BAABLgAECn8lAAIRAAcJVh+jDAANAgARAAcJVh+jDAANAgAAAA==.Thorlan:BAAALgADCgYJCAAAAA==.Thrasherzs:BAAALgAECgIJBAAAAA==.Thunder:BAAALgADCgQJBAABLgAECgcJCgAHAAAAAA==.Thundergrasp:BAAALgAECgcJDgAAAA==.',
Ti='Tianhe:BAAALgAECgMJAwAAAA==.Tiarisaril:BAAALgAECgYJBgAAAA==.Tippah:BAAALgAECgEJAQAAAA==.',
To='Toe:BAAALgAECgIJAgAAAA==.Tonkah:BAAALgAECgUJBQAAAA==.Topenga:BAABLgAECn82AAIBAAkJJhwKBADCAgABAAkJJhwKBADCAgAAAA==.Touchypope:BAAALgADCgUJBQAAAA==.',
Tr='Treeage:BAAALgADCgMJAwAAAA==.Triggerd:BAAALgADCgEJAQAAAA==.Trunks:BAAALgADCgQJBAAAAA==.Trüst:BAAALgAECggJDQAAAA==.',
Tw='Twicelife:BAAALgAECgIJAgABLgAECgkJPAAIAOIYAA==.',
Ty='Tyrygosa:BAAALgAECgUJBQABLgAECgcJFQATAAYhAA==.',
['Tå']='Tånk:BAAALgAECggJEgAAAA==.',
Un='Uneedsummilk:BAAALgADCgcJBwAAAA==.Unholyapollo:BAAALgADCgYJCwAAAA==.',
Ur='Urthstripe:BAABLgAECn8UAAIGAAcJvRa6GgCqAQAGAAcJvRa6GgCqAQAAAA==.',
Va='Vae:BAAALgAECgIJAgABLgAFFAMJCAAdAIwhAA==.Valle:BAAALgAECgEJAQABLgAFFAYJFAAEAMUcAA==.Valoria:BAAALgAECgEJAQABLgAFFAYJFAAEAMUcAA==.',
Ve='Velarenea:BAAALgADCgEJAQAAAA==.Velgabrine:BAAALgADCggJEgABLgAECggJIgAVAA4mAA==.Veraani:BAAALgAECgYJBgAAAA==.Verra:BAAALgADCgYJBgAAAA==.',
Vi='Vil:BAAALgADCgcJBgAAAA==.Virlan:BAAALgADCgQJBAAAAA==.Viserion:BAAALgAECgYJDgAAAA==.',
Vo='Voidchaosfan:BAAALgAECgQJBQABLgAECgQJCAAHAAAAAA==.',
Vu='Vue:BAABLgAECn8xAAIRAAkJGxpGBgB+AgARAAkJGxpGBgB+AgAAAA==.Vuldin:BAAALgAECgEJAgAAAA==.',
['Vö']='Völdemört:BAAALgADCgIJAgAAAA==.',
Wa='Wakasham:BAACLgAFFH8OAAIhAAUJDx7wAAAjAQAhAAUJDx7wAAAjAQAuAAQKfyUAAiEACAnjJZ4BAFMDACEACAnjJZ4BAFMDAAAA.',
We='Wehonoryou:BAAALgAECgUJEQAAAA==.Wetard:BAAALgADCgIJAgAAAA==.',
Wi='Willbyers:BAAALgAECgEJAQAAAA==.',
Wo='Wolfpacked:BAABLgAECn8fAAISAAkJwxsWBADCAgASAAkJwxsWBADCAgAAAA==.Wolfzbåin:BAAALgAECgQJBAAAAA==.',
Wr='Wroot:BAAALgADCgYJCQAAAA==.Wrotten:BAAALgAECgcJDAAAAA==.',
Wu='Wunderlust:BAABLgAECn8xAAIZAAkJ8R0LCQCsAgAZAAkJ8R0LCQCsAgAAAA==.',
Xe='Xemon:BAAALgAECgIJAgAAAA==.',
Xi='Xilyana:BAAALgAECgQJBAAAAA==.',
Xm='Xmatick:BAAALgAECgcJBwAAAA==.',
Xs='Xscrats:BAAALgAECgkJBwAAAA==.',
Ye='Yellowshaman:BAACLgAFFH8LAAIYAAQJBg7jCwAuAQAYAAQJBg7jCwAuAQAuAAQKfygAAhgACAmmID0MANcCABgACAmmID0MANcCAAAA.Yerac:BAAALgAECgEJAQAAAA==.',
Yu='Yukikage:BAAALgAECgMJAwAAAA==.Yutdaeng:BAAALgAECgMJBAAAAA==.',
Yv='Yvent:BAAALgADCgIJAgAAAA==.Yvraine:BAAALgADCgEJAQAAAA==.',
Za='Zakcarii:BAAALgADCgMJCAAAAA==.Zalicy:BAAALgAECgYJEwAAAA==.Zalogar:BAAALgAECgcJCgAAAA==.Zapper:BAAALgAECgIJAgAAAA==.',
Ze='Zealot:BAAALgAECgEJAQAAAA==.Zeeasyez:BAAALgAECgYJEQAAAA==.Zestul:BAAALgADCgEJAQAAAA==.',
Zh='Zhane:BAAALgADCgEJAQAAAA==.',
Zo='Zordon:BAAALgAECgYJDwAAAA==.',
Zu='Zugg:BAAALgAECgIJAgABLgAFFAYJFAAEAMUcAA==.Zuriznikov:BAAALgADCgUJBQABLgAECgYJDgAHAAAAAA==.',
['Øf']='Øffspeck:BAABLgAECn8fAAQfAAgJIR+xAABNAgATAAcJDhsYLgBVAgAfAAcJFyGxAABNAgAeAAMJzh7MMAD3AAAAAA==.',
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

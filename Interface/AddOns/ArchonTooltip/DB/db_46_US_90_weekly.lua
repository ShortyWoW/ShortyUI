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

local lookup = {'Rogue-Subtlety','Warlock-Destruction','Warlock-Demonology','Druid-Balance','Druid-Restoration','Evoker-Augmentation','Shaman-Elemental','Warrior-Arms','Warrior-Fury','Warrior-Protection','Monk-Windwalker','Paladin-Holy','DemonHunter-Devourer','DemonHunter-Vengeance','Priest-Shadow','DeathKnight-Unholy','Unknown-Unknown','Priest-Holy','Mage-Frost','DemonHunter-Havoc','Shaman-Restoration','Rogue-Outlaw','Hunter-BeastMastery','Hunter-Survival','Hunter-Marksmanship','Monk-Mistweaver','DeathKnight-Blood','Druid-Guardian','Shaman-Enhancement','Priest-Discipline','Mage-Fire','Paladin-Retribution','Mage-Arcane','Druid-Feral','DeathKnight-Frost','Evoker-Preservation','Rogue-Assassination','Evoker-Devastation','Warlock-Affliction','Monk-Brewmaster',}
local provider = {region='US',realm='Eredar',name='US',type='weekly',zone=46,date='2026-05-08',data={Aa='Aamon:BAAALgAECgQJCgAAAA==.',
Ab='Abacus:BAABLgAECn8hAAIBAAgJGSOZAwCfAgABAAgJGSOZAwCfAgAAAA==.',
Ad='Adam:BAACLgAFFH8LAAMCAAYJFRRUDQCiAAADAAQJBRZTRADSAAACAAMJlBFUDQCiAAAuAAQKfycAAwMACQmwIl0WAM4CAAMACQnFIV0WAM4CAAIABQlkJKcNAOsBAAAA.Adedruid:BAABLgAECn8eAAMEAAYJVB5XKwCnAQAEAAYJVB5XKwCnAQAFAAYJ3hr9SQB6AQAAAA==.Adevoker:BAAALgAECgQJBAAAAA==.Adragon:BAABLgAECn8bAAIGAAgJWBm7CgAfAgAGAAgJWBm7CgAfAgAAAA==.',
Ae='Aengyl:BAAALgAECgQJBAAAAA==.Aeonne:BAAALgAECggJEAAAAA==.',
Ak='Akshul:BAABLgAECn8UAAIHAAYJ3g1DRgAvAQAHAAYJ3g1DRgAvAQAAAA==.Akurama:BAAALgAECgcJCQAAAA==.',
Al='Aldrea:BAAALgAECgUJBwAAAA==.Allsmiles:BAABLgAECn8UAAQIAAkJuh3rCAAhAgAIAAgJexrrCAAhAgAJAAUJChmxTQBwAQAKAAMJ7R0iKgDvAAAAAA==.Allura:BAAALgAECgIJAwAAAA==.Alorian:BAAALgAECgIJAgAAAA==.Alttharius:BAAALgADCgQJBAABLgAECgkJFwALALMgAA==.Alyysha:BAABLgAECn8bAAIMAAcJlwkARgBgAQAMAAcJlwkARgBgAQAAAA==.',
Am='Amoon:BAABLgAECn8fAAMNAAgJdxhrHQDYAQANAAgJlxZrHQDYAQAOAAYJ8BSrCQA8AQAAAA==.',
An='Andoriel:BAAALgADCgcJBwAAAA==.Angelrain:BAABLgAECn8lAAIPAAgJWByNDgCaAgAPAAgJWByNDgCaAgAAAA==.',
Ar='Archymedes:BAABLgAECn8bAAIJAAUJyxDfMgD/AAAJAAUJyxDfMgD/AAAAAA==.Arckady:BAAALgAECgIJAwAAAA==.Artharius:BAABLgAECn8XAAILAAkJsyDwCAAvAgALAAkJsyDwCAAvAgAAAA==.',
Au='Auburnbeard:BAAALgADCgYJBgAAAA==.Aumed:BAAALgADCgEJAQAAAA==.',
Av='Averle:BAABLgAECn88AAICAAYJdQUMEwC8AAACAAYJdQUMEwC8AAAAAA==.',
Az='Azrran:BAAALgADCgEJAQAAAA==.Aztharot:BAAALgAECgIJAgAAAA==.',
Ba='Badchoices:BAAALgAECgMJAwAAAA==.Badkittie:BAAALgAECgIJAgAAAA==.',
Be='Belinda:BAAALgAECgEJAQABLgAFFAUJFgAQAA8jAA==.Bewater:BAAALgADCgcJBwAAAA==.',
Bl='Bladesmcgee:BAAALgADCgMJAwABLgAECgQJCAARAAAAAA==.',
Bo='Bobadelphia:BAAALgADCgYJBgABLgAECgYJEQARAAAAAA==.Bofahdeez:BAABLgAECn8aAAMPAAgJtQzcHQBNAQAPAAcJHAzcHQBNAQASAAcJWQ66PABHAQAAAA==.Bogs:BAACLgAFFH8JAAITAAMJNhudQAALAQATAAMJNhudQAALAQAuAAQKfxwAAhMACAkiIbojAOQCABMACAkiIbojAOQCAAAA.Bonedaddy:BAAALgAECgYJBgAAAA==.',
Br='Brewswayne:BAAALgADCgQJBAABLgAFFAIJAgARAAAAAA==.Brolic:BAABLgAECn8jAAMUAAgJaBx6CQD1AQAUAAgJaBx6CQD1AQANAAEJ5weTwwAqAAAAAA==.',
Ca='Cail:BAEBLgAECn8UAAIVAAgJsRdLEgAmAgAVAAgJsRdLEgAmAgAAAA==.Calamìty:BAAALgADCgcJDgABLgAECggJHwAFAAMPAA==.Calisa:BAABLgAECn8kAAIWAAgJ0xl2AwDJAQAWAAgJ0xl2AwDJAQAAAA==.Cardio:BAAALgADCgYJCAAAAA==.Carnifexx:BAAALgAECgUJBQABLgAFFAQJDAANANAWAA==.Cassey:BAAALgAECgEJAQAAAA==.',
Ce='Celesteus:BAAALgADCgkJFAAAAA==.',
Ch='Charis:BAAALgAECgYJCwAAAA==.Chigutotems:BAAALgAECgYJCgABLgAECgkJFQANAFcVAA==.Choi:BAAALgAECgUJDwAAAA==.Chooq:BAAALgADCgIJAgAAAA==.Chozen:BAAALgAECgUJEAAAAA==.Chumlee:BAAALgADCgQJBAAAAA==.',
Ci='Cienna:BAAALgAECgYJDgAAAA==.Cigz:BAAALgADCgEJAQAAAA==.Cinch:BAAALgAECgIJAgAAAA==.',
Co='Colinferral:BAAALgAECgYJCAAAAA==.Coulee:BAAALgAECgEJAgABLgAECggJHAAUABceAA==.Cowladin:BAAALgADCgUJBQAAAA==.',
Cr='Crakzkull:BAAALgAECgUJCwAAAA==.Croar:BAAALgAECgMJBAAAAA==.Cronicpain:BAAALgADCgkJCQAAAA==.',
['Cä']='Cäntstandya:BAACLgAFFH8JAAMXAAMJmRhzIwAIAQAXAAMJmRhzIwAIAQAYAAIJrQpfGACNAAAuAAQKfxwAAxcACAliGVcSAKUCABcACAliGVcSAKUCABgAAgm0DR8pAGkAAAAA.',
Da='Daiko:BAAALgAECgYJBgAAAA==.Daks:BAAALgAFFAIJAgAAAA==.Dargo:BAAALgAECgYJEwAAAA==.Darklucrezia:BAACLgAFFH8JAAMXAAMJ4huzHwAYAQAXAAMJ4huzHwAYAQAZAAIJNgL4FwBZAAAuAAQKfyIAAhkACAkOEd0lAPoBABkACAkOEd0lAPoBAAAA.Dazzlefraz:BAAALgAECgQJBAAAAA==.',
De='Demonklunter:BAAALgADCgYJEAAAAA==.Destructoid:BAAALgAECgEJAQAAAA==.',
Di='Dicey:BAAALgADCgMJAwABLgAECgQJBgARAAAAAA==.',
Do='Dochunter:BAAALgAECgUJBQAAAA==.',
Dr='Dracarius:BAAALgAECgIJAwAAAA==.Drega:BAAALgAECgYJBwAAAA==.Droods:BAAALgAECgQJBQAAAA==.Drtypinkcake:BAABLgAECn8VAAIUAAYJ5AXYIQDMAAAUAAYJ5AXYIQDMAAAAAA==.Druskgar:BAABLgAECn8fAAIQAAgJwyG1FwA+AgAQAAgJwyG1FwA+AgAAAA==.Dryad:BAAALgAECgIJAwAAAA==.',
Du='Duckster:BAAALgADCgYJBwAAAA==.Dunce:BAABLgAECn8YAAIaAAgJDh4VDACRAgAaAAgJDh4VDACRAgAAAA==.Durkk:BAABLgAECn8kAAIbAAgJACAMBQBeAgAbAAgJACAMBQBeAgAAAA==.Durza:BAAALgAECgYJDwAAAA==.',
['Dä']='Dännydevito:BAAALgADCgQJBAAAAA==.',
Ed='Eduard:BAAALgAECgYJCQAAAA==.',
El='Elanthae:BAAALgAECgMJBwAAAA==.Elysia:BAAALgAECgEJAgAAAA==.',
Er='Erzulie:BAAALgAECgUJBAAAAA==.',
Es='Estara:BAABLgAECn8eAAIcAAgJTQt5EgDhAAAcAAgJTQt5EgDhAAAAAA==.',
Et='Etali:BAABLgAECn8bAAIJAAgJOBRDFgC2AQAJAAgJOBRDFgC2AQAAAA==.',
Ez='Ezazel:BAAALgADCgUJBwAAAA==.',
Fa='Faite:BAAALgADCgUJBQAAAA==.Falorin:BAABLgAECn8WAAITAAYJEhZqVwBnAQATAAYJEhZqVwBnAQAAAA==.Fanis:BAABLgAECn8cAAIZAAgJHhB6CQBhAQAZAAgJHhB6CQBhAQAAAA==.Fatherwhig:BAAALgAECgIJAwAAAA==.',
Fi='Fidis:BAAALgADCgkJCwAAAA==.Fistsofdeath:BAAALgADCggJCgAAAA==.Fistychub:BAAALgADCgEJAQAAAA==.',
Fl='Flashbang:BAAALgADCgEJAQAAAA==.Flashis:BAAALgAECggJEwAAAA==.Florago:BAAALgAECgIJAwAAAA==.',
Fr='Frakir:BAABLgAECn8kAAQVAAgJJhf2FgD6AQAVAAgJJhf2FgD6AQAdAAIJfASnLAAzAAAHAAEJkAYdkwAjAAAAAA==.Fritzz:BAAALgAECgcJEgAAAA==.Frog:BAAALgAECgEJAgAAAA==.',
Fu='Furrypaw:BAABLgAECn8XAAIaAAgJOyOWAgAnAwAaAAgJOyOWAgAnAwAAAA==.',
Fw='Fwapp:BAACLgAFFH8WAAIMAAUJUCC/BwCgAQAMAAUJUCC/BwCgAQAuAAQKfxcAAgwACAlrIcgLAL8CAAwACAlrIcgLAL8CAAAA.',
Ga='Galvanize:BAAALgAECgEJAgAAAA==.Galynisse:BAABLgAECn8jAAMeAAUJ0Bu8FACaAQAeAAUJ0Bu8FACaAQASAAMJ7A4XZQCZAAAAAA==.',
Ge='Gedorah:BAABLgAECn8UAAIfAAYJ/xc+AwBiAQAfAAYJ/xc+AwBiAQABLgAFFAMJBwAHAIMYAA==.',
Gh='Ghaspy:BAAALgAECgUJBwAAAA==.Ghoste:BAAALgADCgMJAwAAAA==.Ghrex:BAAALgAECgEJAQAAAA==.',
Gi='Gijaick:BAABLgAECn8kAAMDAAgJMRfGMgCZAQADAAgJMRfGMgCZAQACAAEJHg71cwAxAAAAAA==.',
Gl='Glaivethrow:BAABLgAECn8VAAINAAkJVxUGQAD0AQANAAkJVxUGQAD0AQAAAA==.Glizzo:BAAALgAECgYJDAAAAA==.',
Go='Gochujjang:BAAALgAECgYJDQAAAA==.Goldhawk:BAAALgAECgMJAwAAAA==.Gotchá:BAAALgAECgEJBAAAAA==.Gotwiped:BAAALgAECgcJDAAAAA==.',
Gr='Grimgor:BAAALgAECgcJAQAAAA==.',
Ha='Hahaheals:BAAALgAECgMJBAAAAA==.Hakhar:BAAALgADCgMJAwAAAA==.Hatter:BAABLgAECn8XAAQNAAgJzhKeYAB/AQANAAgJzhKeYAB/AQAUAAMJXwcNWACGAAAOAAEJNRMlKwA0AAAAAA==.',
He='Healsus:BAAALgAECgMJAwAAAA==.Heimlish:BAAALgAECgEJAQAAAA==.Hellraiser:BAABLgAECn8WAAIQAAYJFRhrRQBsAQAQAAYJFRhrRQBsAQAAAA==.Hermione:BAAALgAECgYJDQAAAA==.Hexecution:BAAALgADCgIJAgAAAA==.',
Hi='Hiddendragon:BAAALgAECgEJAQAAAA==.',
Ho='Holydarkness:BAAALgADCgcJCQAAAA==.Holykilla:BAAALgAECgEJAQAAAA==.Holykiller:BAAALgAECgEJAQAAAA==.Hoofjob:BAAALgADCggJDgABLgAECgkJMQAeAEEdAA==.Hoplite:BAAALgADCgYJCAABLgAECggJEQARAAAAAA==.Hotot:BAAALgADCgMJAwAAAA==.',
Hu='Huffpuffle:BAAALgAECgUJBwAAAA==.',
['Hô']='Hôwl:BAAALgAECgYJEQAAAA==.',
Ic='Icdeathg:BAACLgAFFH8FAAINAAMJ/QuRNwDUAAANAAMJ/QuRNwDUAAAuAAQKfyEAAg0ACAmvFYhTAKkBAA0ACAmvFYhTAKkBAAAA.',
Ik='Iktaar:BAAALgAECgQJBAAAAA==.',
Il='Illidami:BAAALgADCgkJCwAAAA==.Illidamngirl:BAAALgADCgYJBgABLgAECggJFgAKABIWAA==.',
Im='Imperius:BAACLgAFFH8VAAIgAAUJHBYGFgBQAQAgAAUJHBYGFgBQAQAuAAQKfyQAAiAACQmMJBkOAB0DACAACQmMJBkOAB0DAAAA.',
In='Ines:BAABLgAECn8xAAIQAAgJ+CTECQDEAgAQAAgJ+CTECQDEAgAAAA==.Insomiax:BAAALgAECggJDwAAAA==.Insta:BAABLgAECn8nAAIJAAcJzx3ZIwA3AgAJAAcJzx3ZIwA3AgAAAA==.Inter:BAABLgAECn8vAAIbAAkJ+iFUAwCiAgAbAAkJ+iFUAwCiAgAAAA==.',
Ir='Iridi:BAAALgADCgEJAQAAAA==.Iritall:BAAALgADCgcJCwAAAA==.',
It='Ithamburglar:BAAALgAECgQJBQAAAA==.',
Iz='Izureka:BAAALgADCgYJBgAAAA==.',
Ja='Jackidaytona:BAAALgAECgcJBwAAAA==.Jakaru:BAAALgAECgYJEgAAAA==.Jankadish:BAAALgAECgcJEwAAAA==.Jarre:BAACLgAFFH8GAAIFAAQJrggoDgAFAQAFAAQJrggoDgAFAQAuAAQKfygAAgUACAmzICEKAPICAAUACAmzICEKAPICAAAA.Jaspirian:BAAALgADCggJFAAAAA==.Jazzil:BAAALgADCgcJCgAAAA==.',
Jb='Jbaconcheese:BAAALgAECgEJAQAAAA==.',
Je='Jehmothy:BAAALgADCgEJAQAAAA==.Jerome:BAAALgAECgEJAQAAAA==.',
Jo='Jotabop:BAAALgAECgQJBgAAAA==.',
Ju='Juicy:BAABLgAECn8YAAIYAAcJ+RbDDgC8AQAYAAcJ+RbDDgC8AQAAAA==.',
Ka='Kabu:BAAALgAECgcJBwAAAA==.Kalia:BAABLgAECn8vAAMTAAkJ+hirFwBeAgATAAkJ+hirFwBeAgAhAAMJUg8VCAC0AAABLgADCgEJAQARAAAAAA==.Kalitra:BAAALgADCgMJAwABLgADCgEJAQARAAAAAA==.Katoumae:BAACLgAFFH8NAAIiAAQJvBYYAgBsAQAiAAQJvBYYAgBsAQAuAAQKfxsAAiIACAm0GvQFAKMCACIACAm0GvQFAKMCAAAA.Katoumey:BAAALgAECgYJCQABLgAFFAQJDQAiALwWAA==.',
Ke='Keratin:BAABLgAECn8gAAIjAAgJTiIEAgC2AgAjAAgJTiIEAgC2AgAAAA==.',
Kh='Khumi:BAABLgAECn8XAAIZAAgJYSCdEgCiAgAZAAgJYSCdEgCiAgABLgAFFAgJGAAgALQiAA==.',
Ki='Kinan:BAABLgAECn8fAAMXAAgJtCNCBgDOAgAXAAgJeCNCBgDOAgAZAAcJOx6dFwBxAgAAAA==.Kita:BAAALgAECggJEgABLgAECgkJAgARAAAAAA==.',
Kk='Kkaarrkk:BAAALgAECgUJBQAAAA==.',
Kr='Krindon:BAAALgAECgYJEQAAAA==.',
Ku='Kureiji:BAAALgADCgEJAQAAAA==.',
Ky='Kythin:BAAALgADCgEJAQAAAA==.',
Kz='Kzuon:BAAALgADCggJCAAAAA==.',
La='Lacutis:BAAALgAECgEJAQAAAA==.Laww:BAAALgADCgcJCgAAAA==.',
Le='Lecroix:BAAALgADCgUJBQAAAA==.Leonus:BAAALgAECgMJAwABLgAECgIJAgARAAAAAA==.Lessana:BAAALgAECgIJAgAAAA==.Lethalforce:BAAALgADCgMJAwAAAA==.',
Li='Liandri:BAAALgADCgEJAgAAAA==.Lightchild:BAAALgADCggJCAAAAA==.Lillith:BAAALgAECgMJAwAAAA==.Livewire:BAAALgAECgIJAwAAAA==.',
Lo='Lokohmojo:BAAALgAECgMJBAAAAA==.Lomponic:BAEBLgAECn8iAAIPAAgJVRq/CQAoAgAPAAgJVRq/CQAoAgAAAA==.Loomadin:BAAALgADCgYJCQAAAA==.',
Lu='Lunethra:BAABLgAECn8rAAIXAAkJwBGeJgC5AQAXAAkJwBGeJgC5AQAAAA==.',
Ma='Mageaux:BAAALgAECgEJAQAAAA==.Magerag:BAACLgAFFH8FAAITAAMJQBgBQgAHAQATAAMJQBgBQgAHAQAuAAQKfyEAAxMACAlRHq4vALMCABMACAlRHq4vALMCACEAAglAGkMVAHMAAAAA.Manamontana:BAACLgAFFH8WAAMQAAUJuxGzNgAvAQAQAAQJuxGzNgAvAQAbAAEJAADaJgAAAAAuAAQKfxkAAhAACAn4H3coAJgCABAACAn4H3coAJgCAAAA.Marumo:BAAALgAECgMJBgAAAA==.',
Mc='Mcribz:BAACLgAFFH8WAAIQAAUJDyP8DgCaAQAQAAUJDyP8DgCaAQAuAAQKfx0AAhAACAl5IysZAOUCABAACAl5IysZAOUCAAAA.',
Me='Meelonusk:BAAALgAECgQJCAAAAA==.Mess:BAAALgAECgEJAQAAAA==.Messah:BAAALgAECgMJBQAAAA==.Messic:BAAALgADCgEJAQAAAA==.',
Mi='Michaelcoyle:BAABLgAECn8mAAIXAAgJqxxbEwA2AgAXAAgJqxxbEwA2AgAAAA==.Midnightcrow:BAAALgADCgkJDwAAAA==.Milo:BAABLgAECn8sAAMJAAkJLCLlAQAMAwAJAAkJLCLlAQAMAwAIAAgJbhwTBAC0AgAAAA==.Mishra:BAAALgAECgUJBQAAAA==.Mitra:BAABLgAECn8eAAIWAAgJzx1wAQBoAgAWAAgJzx1wAQBoAgAAAA==.',
Mo='Moesko:BAAALgAECggJEQAAAA==.Mof:BAAALgADCgEJAQAAAA==.Mohawkk:BAAALgAECgEJAQAAAA==.Monktup:BAAALgAECgYJCwAAAA==.Monnehbaggs:BAABLgAECn8gAAMSAAkJDxz+DQB7AgASAAgJpR3+DQB7AgAeAAMJPRETNACQAAAAAA==.Mortalidad:BAAALgADCgQJBAAAAA==.',
Mu='Muin:BAAALgAECgEJAQAAAA==.Murdersamich:BAAALgAECgQJCwAAAA==.',
My='Mybigcrits:BAAALgAECgYJDAAAAA==.',
['Mà']='Màevë:BAAALgAECgEJAgAAAA==.',
Na='Nairdax:BAAALgADCgEJAQAAAA==.Nalmec:BAABLgAECn8bAAIJAAYJ4QfeMgD/AAAJAAYJ4QfeMgD/AAAAAA==.Nama:BAAALgADCgYJBgAAAA==.Naysayre:BAABLgAECn8YAAINAAYJXAfvdgCqAAANAAYJXAfvdgCqAAAAAA==.',
Ne='Nebody:BAAALgAECgEJAQAAAA==.Necriss:BAABLgAECn8aAAIgAAgJkw17SgBmAQAgAAgJkw17SgBmAQAAAA==.',
Ni='Nightkilla:BAAALgAECgEJAQAAAA==.Nike:BAAALgAECgcJBwAAAA==.Nilowin:BAABLgAECn8gAAIBAAgJGgwSEQCXAQABAAgJGgwSEQCXAQAAAA==.',
No='Nokaj:BAAALgAECgEJAgAAAA==.Noshards:BAAALgAECgcJDQAAAA==.Notericdh:BAAALgAECgYJEwAAAA==.',
Og='Oghom:BAAALgADCgcJCgAAAA==.',
Oh='Ohnoitzgumby:BAAALgAECgcJEQAAAA==.',
Om='Omiko:BAAALgAECgIJAgAAAA==.',
Op='Opeep:BAAALgADCgcJGQAAAA==.',
Or='Orah:BAAALgADCgEJAQAAAA==.',
Os='Osos:BAAALgAECgYJEAAAAA==.',
Pa='Paladimdab:BAAALgAECgMJAwAAAA==.Papachance:BAAALgAECgMJAwAAAA==.Papafrank:BAAALgADCgkJEAAAAA==.Paradis:BAAALgADCgcJBwAAAA==.Pazuzu:BAAALgADCgYJBgAAAA==.',
Pe='Peepo:BAAALgAECgEJAQAAAA==.',
Pi='Pinga:BAAALgAECgUJCwABLgAECggJLgAkAMIjAA==.Pinkberry:BAAALgAECgQJBAAAAA==.Pintcube:BAAALgADCgYJCAAAAA==.',
Pl='Pljeskavica:BAAALgAECgUJBgAAAA==.Plox:BAAALgAECgMJAwAAAA==.',
Po='Port:BAABLgAECn8kAAIFAAgJpx4LDwBiAgAFAAgJpx4LDwBiAgAAAA==.Potroastjr:BAAALgADCgEJAgABLgAECgEJAQARAAAAAA==.',
Pr='Primordus:BAAALgADCgUJBQAAAA==.Profiler:BAAALgAECgcJCAAAAA==.Protocol:BAAALgAECgMJAwAAAA==.Prïestess:BAAALgAECgYJBQAAAA==.',
Ps='Pseriph:BAABLgAECn8ZAAICAAcJ3BZqCwAKAgACAAcJ3BZqCwAKAgAAAA==.',
Ra='Radamantis:BAAALgAECgMJAwAAAA==.Raenon:BAAALgADCgkJEAAAAA==.Raggnar:BAACLgAFFH8HAAIHAAMJgxiaFQADAQAHAAMJgxiaFQADAQAuAAQKfykAAgcACAmFIfMFAIoCAAcACAmFIfMFAIoCAAAA.Ragingwaters:BAAALgADCgYJCAAAAA==.Ranvir:BAAALgAECgEJAQAAAA==.Raun:BAABLgAECn8kAAMgAAgJiB9yEAB4AgAgAAgJiB9yEAB4AgAMAAMJIxEscgCzAAAAAA==.',
Re='Regnarr:BAAALgADCgEJAQAAAA==.Relaire:BAABLgAECn8ZAAIXAAcJrQ2wOwBeAQAXAAcJrQ2wOwBeAQAAAA==.Resonate:BAAALgAFFAIJAgAAAA==.',
Ri='Rikane:BAAALgADCgcJDAABLgADCgcJEgARAAAAAA==.Riku:BAABLgAECn8fAAIiAAgJQBzuAwA5AgAiAAgJQBzuAwA5AgAAAA==.',
Ro='Rock:BAAALgAECgcJCQAAAA==.Roguey:BAABLgAECn8XAAIlAAcJ5AlQCQA5AQAlAAcJ5AlQCQA5AQAAAA==.Roots:BAAALgAECgEJBAAAAA==.',
Ru='Rulethrefour:BAAALgAECgMJAwAAAA==.',
Ry='Ryveri:BAABLgAECn8lAAIJAAkJDxnqBwBtAgAJAAkJDxnqBwBtAgAAAA==.',
Sa='Sablehide:BAABLgAECn8dAAIGAAcJ/BLFGwBgAQAGAAcJ/BLFGwBgAQAAAA==.Sanaron:BAAALgADCgIJAgAAAA==.Sanaty:BAAALgAECgQJCQAAAA==.Saryn:BAAALgAECgYJDwAAAA==.Satanz:BAAALgADCgIJAgAAAA==.Sathanus:BAAALgAECgIJAwAAAA==.',
Se='Searate:BAAALgADCgcJEgAAAA==.Seaside:BAACLgAFFH8MAAIQAAMJIyXtHAAvAQAQAAMJIyXtHAAvAQAuAAQKfxYAAxAABwk9JdcbACICABAABwk9JdcbACICABsAAgmEC+w/AE4AAAAA.Secrett:BAABLgAECn8WAAMBAAcJ3RPxFABnAQABAAcJ3RPxFABnAQAlAAEJew7pGQA6AAAAAA==.Sephyxia:BAABLgAECn8mAAIbAAgJNhSxDgCGAQAbAAgJNhSxDgCGAQAAAA==.Serryon:BAAALgADCgIJAgAAAA==.',
Sf='Sfora:BAAALgADCggJCAAAAA==.',
Sh='Shadowwzz:BAAALgADCgEJAQAAAA==.Shoçknezz:BAAALgAECgMJBQAAAA==.',
Si='Silverwolf:BAABLgAECn8xAAIdAAkJjh9CAQDVAgAdAAkJjh9CAQDVAgAAAA==.Simplyunlock:BAABLgAECn8hAAMDAAgJWxR3IgDkAQADAAgJWxR3IgDkAQACAAIJ5wWMZgBDAAAAAA==.Simplyvoided:BAAALgAECgQJBAAAAA==.Sinverguenza:BAAALgAECgMJBQAAAA==.Sizzlechop:BAABLgAECn8ZAAIQAAcJCgdiZQAYAQAQAAcJCgdiZQAYAQAAAA==.',
Sk='Skizzak:BAAALgADCgQJBAABLgAFFAUJFgAQAA8jAA==.Skweeks:BAAALgAECgMJBAAAAA==.',
Sm='Smelvin:BAABLgAECn8WAAIHAAkJtRloFgBmAgAHAAkJtRloFgBmAgABLgAECgQJCAARAAAAAA==.Smoko:BAAALgAECgIJAgABLgAECgUJBQARAAAAAA==.',
Sn='Snailslolol:BAAALgAECgEJAgAAAA==.Snakey:BAECLgAFFH8MAAMGAAMJngfWJQDIAAAGAAMJngfWJQDIAAAmAAEJ1wLmCABDAAAuAAQKfyYAAwYACAmLGDYaAPkBAAYACAmLGDYaAPkBACYABgl5BHEmAO8AAAAA.',
So='Solara:BAABLgAECn8bAAQPAAgJwBcADgDqAQAPAAgJwBcADgDqAQASAAEJQAINhwApAAAeAAEJXgKWXgAkAAAAAA==.Soleill:BAAALgAECgcJBwAAAA==.Sondan:BAAALgADCgMJAwAAAA==.Songs:BAAALgAECgEJAQABLgAECgYJGAALAP0gAA==.',
Sp='Spellpowa:BAAALgAECgYJDgAAAA==.',
Ss='Ssminion:BAAALgAECgEJAgAAAA==.',
St='Stormwing:BAABLgAECn8bAAIHAAcJshm8FQClAQAHAAcJshm8FQClAQAAAA==.Strecagosa:BAAALgAECgYJDQAAAA==.',
Sv='Svenn:BAAALgAECgYJBgAAAA==.',
Sy='Sybelissa:BAAALgAECgMJAwABLgAECgcJCgARAAAAAA==.Synni:BAAALgADCgEJAQAAAA==.',
['Sÿ']='Sÿnÿster:BAAALgADCgMJAwABLgAFFAMJCQAXAOIbAA==.',
Ta='Talron:BAAALgAECgQJBAAAAA==.Tastytay:BAAALgADCgMJAwAAAA==.Tatertots:BAABLgAECn8gAAMjAAcJWiDYAgD+AQAjAAcJWiDYAgD+AQAQAAMJ8hOF7ACmAAAAAA==.',
Te='Tea:BAABLgAECn8lAAIXAAgJMiAaCwCJAgAXAAgJMiAaCwCJAgAAAA==.Teal:BAAALgAECgMJAwAAAA==.Templyn:BAAALgAECgcJCQAAAA==.Templÿn:BAAALgADCgEJAQABLgAECgcJCQARAAAAAA==.Tenebrarum:BAABLgAECn8bAAIXAAgJGA1RQABNAQAXAAgJGA1RQABNAQAAAA==.Testorooni:BAABLgAECn8ZAAIXAAcJkBgnMwDjAQAXAAcJkBgnMwDjAQAAAA==.',
Th='Thakodi:BAAALgAECgQJBAAAAA==.Thannos:BAAALgADCgEJAQAAAA==.Tharvan:BAAALgADCgcJDAAAAA==.Thedeadman:BAABLgAECn8kAAIQAAkJEiLbCADPAgAQAAkJEiLbCADPAgAAAA==.Thepriestg:BAAALgAECgEJAQAAAA==.Thiccksilver:BAAALgADCgcJBwABLgAECgkJJQADAN0cAA==.Thompson:BAAALgAECgYJEwAAAA==.Thunderflaps:BAAALgAECgUJCQAAAA==.Thyrus:BAABLgAECn8uAAMkAAgJwiN2AwCXAgAkAAgJwiN2AwCXAgAmAAEJqgL1RAAjAAAAAA==.',
Ti='Tirna:BAABLgAECn8hAAIfAAgJzgwiAwBsAQAfAAgJzgwiAwBsAQAAAA==.',
To='Toebot:BAAALgAECgEJAQAAAA==.Tomsellock:BAABLgAECn8WAAMnAAcJjhBuBwDcAQAnAAcJjhBuBwDcAQADAAEJugM5LAEmAAAAAA==.Tonari:BAAALgADCgYJBgABLgAECgYJEAARAAAAAA==.Torvi:BAAALgADCgMJAwAAAA==.',
Tr='Transmørtuus:BAAALgAECgQJCQAAAA==.Treehug:BAAALgAECggJEwAAAA==.Triple:BAAALgAECgQJBwABLgAECgYJEAARAAAAAA==.Trolleonne:BAAALgAECgEJAQAAAA==.',
Tu='Tullen:BAEBLgAECn8eAAISAAgJgRIEFwCZAQASAAgJgRIEFwCZAQAAAA==.Turanos:BAAALgAECgIJAwAAAA==.',
Tw='Tweyen:BAAALgAECgEJAQAAAA==.',
Ty='Tyindaris:BAAALgAECgQJCQAAAA==.Tyloregeth:BAABLgAECn8lAAIPAAgJbxM+EwCsAQAPAAgJbxM+EwCsAQAAAA==.',
['Tè']='Tèmplyn:BAAALgADCgEJAQABLgAECgcJCQARAAAAAA==.',
['Té']='Témplýn:BAAALgADCgEJAQABLgAECgcJCQARAAAAAA==.',
['Të']='Tëmplýn:BAAALgAECgEJAQABLgAECgcJCQARAAAAAA==.',
Ul='Ulfrunn:BAAALgADCgYJBgAAAA==.Ultrachad:BAACLgAFFH8PAAIQAAUJvBrRJABWAQAQAAUJvBrRJABWAQAuAAQKfx4AAhAACAlFIwAUAAMDABAACAlFIwAUAAMDAAAA.',
Um='Umami:BAABLgAECn8gAAIJAAYJ4hg8JQBIAQAJAAYJ4hg8JQBIAQAAAA==.',
Un='Unggoy:BAACLgAFFH8VAAMZAAcJ9h/2AgAkAgAZAAcJnB72AgAkAgAXAAIJsRmfMADEAAAuAAQKfyEAAhkACQmAJbkBAKYDABkACQmAJbkBAKYDAAAA.Unholywaters:BAAALgAECgIJBQAAAA==.',
Ur='Urianna:BAAALgAECgIJBgAAAA==.',
Va='Vaelthirion:BAABLgAECn8aAAITAAgJ8hJEhADJAQATAAgJ8hJEhADJAQAAAA==.Vahidamus:BAAALgAECgUJBgAAAA==.Valkaryon:BAAALgAECgcJCgABLgAFFAIJAgARAAAAAA==.Valmirax:BAAALgADCggJEgAAAA==.Valton:BAABLgAECn8tAAIgAAYJhwsmbgARAQAgAAYJhwsmbgARAQAAAA==.',
Ve='Vegetation:BAAALgAECgQJBgAAAA==.Velenestus:BAAALgAECgMJBgAAAA==.Verses:BAAALgADCgEJAQAAAA==.',
Vi='Vizsla:BAAALgAECgEJAQAAAA==.',
Wa='Wackaman:BAABLgAECn8WAAIKAAgJEhbzDACVAQAKAAgJEhbzDACVAQAAAA==.Warpig:BAAALgAECgYJEQAAAA==.Wasps:BAAALgAECgYJEQAAAA==.',
We='Wegmaniac:BAAALgADCgYJCAAAAA==.Welastrexa:BAAALgADCgUJBQABLgADCgYJCAARAAAAAA==.',
Wi='Wickedclöwn:BAAALgADCgMJAwAAAA==.Winchester:BAAALgADCgIJAgAAAA==.Windhorn:BAAALgADCggJCQAAAA==.Winds:BAABLgAECn8YAAILAAYJ/SBfFwAqAgALAAYJ/SBfFwAqAgAAAA==.',
Wn='Wntrizcoming:BAAALgADCgMJBQAAAA==.',
Wo='Wolfquota:BAACLgAFFH8KAAIHAAMJZx2lFQACAQAHAAMJZx2lFQACAQAuAAQKfx4AAwcACAkoIkcJAP4CAAcACAkoIkcJAP4CAB0ABAntE1AeAOkAAAAA.Wolftime:BAAALgADCgUJBQAAAA==.Wombaa:BAACLgAFFH8KAAIQAAMJQiPnLgBCAQAQAAMJQiPnLgBCAQAuAAQKfxwAAhAACAleJF8KAEgDABAACAleJF8KAEgDAAAA.',
Wr='Wrathbolt:BAAALgAECgEJAQABLgAECgYJHQALAF4dAA==.Wrathmo:BAABLgAECn8dAAMLAAYJXh2iGQBWAQALAAYJXh2iGQBWAQAoAAYJ3AhHLgDjAAAAAA==.Wrolie:BAAALgADCgMJAwAAAA==.',
['Wê']='Wêêdyys:BAAALgADCgMJBAAAAA==.',
Xy='Xyr:BAAALgAECgEJAQABLgAECggJHgAPAJkOAA==.',
Za='Zandalia:BAAALgAECgMJAwAAAA==.Zark:BAEALgADCgcJBwABLgAECggJFAAVALEXAA==.',
Ze='Zemphoths:BAAALgAECgUJCAAAAA==.',
Zo='Zoa:BAAALgADCgYJBgAAAA==.Zolton:BAAALgADCgMJAwAAAA==.Zornak:BAAALgAECgUJBQAAAA==.',
['Åe']='Åequitas:BAAALgAECgYJCQAAAA==.',
['ßa']='ßahamut:BAAALgAECgQJBQAAAA==.',
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

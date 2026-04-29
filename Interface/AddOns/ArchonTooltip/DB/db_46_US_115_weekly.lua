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

local lookup = {'Unknown-Unknown','Priest-Holy','Mage-Frost','Warrior-Fury','Paladin-Holy','Monk-Mistweaver','Monk-Windwalker','Priest-Shadow','DeathKnight-Unholy','DeathKnight-Frost','Mage-Arcane','Paladin-Retribution','Monk-Brewmaster','Druid-Feral','Evoker-Augmentation','Evoker-Devastation','DeathKnight-Blood','Warrior-Arms','Shaman-Restoration','Shaman-Elemental','Druid-Restoration','Evoker-Preservation','DemonHunter-Devourer','Hunter-BeastMastery','Hunter-Survival','Hunter-Marksmanship','Mage-Fire','Priest-Discipline','Warlock-Demonology','Warrior-Protection','DemonHunter-Vengeance','Shaman-Enhancement',}
local provider = {region='US',realm='Gundrak',name='US',type='weekly',zone=46,date='2026-04-24',data={Ad='Adelyne:BAAALgAECgQJCAAAAA==.Adera:BAAALgAECgYJBwAAAA==.',
Af='Aff:BAAALgADCgYJBgAAAA==.',
Ah='Ahkanon:BAAALgADCgEJAQAAAA==.',
Ai='Aiden:BAAALgAECgEJAgABLgAECgIJAgABAAAAAA==.Aidendk:BAAALgADCgIJAgABLgAECgIJAgABAAAAAA==.Aidenp:BAAALgADCgIJAgABLgAECgIJAgABAAAAAA==.Air:BAAALgADCgcJBwABLgAFFAUJEwACALMfAA==.',
Ak='Aku:BAAALgADCgIJBAAAAA==.',
Al='Aleniastra:BAAALgAECgQJBQAAAA==.Alexyss:BAAALgAECgQJCAAAAA==.Alykard:BAABLgAECn8bAAIDAAgJVwytiADAAQADAAgJVwytiADAAQAAAA==.',
Am='Amyara:BAAALgADCgEJAQAAAA==.',
An='Andronicas:BAAALgAECgQJBwAAAA==.Aneira:BAAALgAECgIJAwAAAA==.',
Ap='Apexis:BAAALgADCgYJCQAAAA==.',
Ar='Arieyri:BAAALgADCgcJBwAAAA==.',
As='Ash:BAAALgADCgcJCwAAAA==.Aspect:BAAALgADCgcJDgABLgAECgEJAQABAAAAAA==.Astarael:BAAALgAECgcJEwAAAA==.',
Av='Avi:BAAALgAECgYJCwABLgAECgkJTQAEAIoYAA==.',
Ba='Babygurl:BAABLgAECn9SAAIFAAkJdySkAAADAwAFAAkJdySkAAADAwAAAA==.Baragas:BAAALgAECgUJBgAAAA==.Barney:BAAALgADCgEJAQAAAA==.Battosaî:BAAALgAECgQJBAAAAA==.',
Be='Beeny:BAACLgAFFH8eAAIGAAUJnCLIAAD6AQAGAAUJnCLIAAD6AQAuAAQKfz4AAwYACAmUI4IIAM4CAAYABwmlJIIIAM4CAAcAAQldD0weAD4AAAAA.Berzerker:BAAALgADCgcJEwAAAA==.',
Bg='Bgc:BAAALgADCgUJBQAAAA==.',
Bi='Binari:BAAALgAECgMJAwABLgAECggJGQAEAJ4eAA==.Binlock:BAAALgAECgQJBAABLgAECggJGQAEAJ4eAA==.',
Bl='Bl:BAAALgAECgMJAwAAAA==.Bladebear:BAABLgAECn8jAAIDAAgJiRT2EAC6AQADAAgJiRT2EAC6AQAAAA==.',
Bo='Bootybreaker:BAAALgADCgcJBwAAAA==.',
Bu='Bubbleez:BAAALgADCgUJBQAAAA==.Bucklord:BAABLgAECn8iAAMIAAgJjRn6FgAuAgAIAAgJjRn6FgAuAgACAAEJ7xgBHABJAAAAAA==.Budin:BAAALgAECgYJCQAAAA==.Bullmann:BAAALgADCgQJBAAAAA==.',
Ca='Cannibal:BAAALgAECgYJDwAAAA==.Caplock:BAAALgAECgYJEQAAAA==.Capri:BAAALgAECgQJCwAAAA==.',
Ce='Cellun:BAAALgAECgUJCwAAAA==.Ceredis:BAAALgAECgUJCwAAAA==.',
Ch='Choomoo:BAAALgADCgcJCwAAAA==.',
Cl='Cleankarma:BAAALgADCgEJAwAAAA==.',
Co='Comet:BAAALgAECgEJAQAAAA==.Corwiggs:BAAALgAECgYJCwAAAA==.',
Cr='Crikey:BAAALgAECgMJAwAAAA==.Crimínal:BAAALgADCgcJCwAAAA==.',
Cu='Curbie:BAAALgAECgIJAwAAAA==.',
['Cô']='Cônvict:BAAALgADCgYJBgAAAA==.',
De='Deacknight:BAABLgAECn8cAAMJAAgJwRuOLgB+AgAJAAgJwRuOLgB+AgAKAAEJig15FwAyAAABLgADCgYJBwABAAAAAA==.Deacmonk:BAAALgADCgYJBgABLgADCgYJBwABAAAAAA==.Definitely:BAABLgAECn8fAAMDAAcJOSLYMACvAgADAAcJOSLYMACvAgALAAEJDyAqGwA/AAAAAA==.Deki:BAEALgAECgYJBgAAAA==.Desariana:BAABLgAECn8WAAIMAAcJdBCdeACJAQAMAAcJdBCdeACJAQAAAA==.',
Di='Diggitie:BAAALgAECgEJAQAAAA==.',
Do='Dormas:BAAALgAECgQJBwAAAA==.Doug:BAAALgADCgEJAQAAAA==.',
Dr='Drakeon:BAAALgADCgYJBgABLgAECgkJTQAEAIoYAA==.',
Ee='Eeryxx:BAAALgAECgEJAQAAAA==.',
El='Eldh:BAABLgAECn8XAAINAAcJgguLCwA3AQANAAcJgguLCwA3AQAAAA==.Eleison:BAAALgADCgMJAwAAAA==.Elendril:BAAALgADCgcJFQAAAA==.Elisoly:BAAALgAECgYJCwAAAA==.',
Em='Emrald:BAAALgAECgYJEwAAAA==.',
En='Endlessly:BAABLgAECn8fAAIOAAgJbCLoAwDrAgAOAAgJbCLoAwDrAgAAAA==.Enerchi:BAAALgADCgMJAwAAAA==.',
Er='Erivoker:BAAALgAECgYJBgAAAA==.Errimage:BAAALgAECgYJEgAAAA==.Errishoot:BAAALgAECgUJBQABLgAECgYJBgABAAAAAA==.Ervinia:BAAALgADCgYJCgABLgAECgQJBQABAAAAAA==.',
Ev='Evelinar:BAAALgAECgMJAwAAAA==.Evoslex:BAABLgAECn8dAAMPAAgJ9SAcAgA5AgAPAAgJ9SAcAgA5AgAQAAYJzx1kEwCsAQAAAA==.',
Ex='Exo:BAECLgAFFH8LAAIRAAQJqBN3AwAUAQARAAQJqBN3AwAUAQAuAAQKfyEAAhEACQnnHDAGANYCABEACQnnHDAGANYCAAAA.',
Fa='Facerolleh:BAACLgAFFH8cAAMEAAUJ/iJ/BgCGAQAEAAQJZiF/BgCGAQASAAMJfCAUBAD7AAAuAAQKfz4AAwQACAkAJtAEAFwDAAQACAn2JdAEAFwDABIABwnRIIsIACwCAAAA.',
Fe='Feelgoodinc:BAAALgADCgkJEgAAAA==.',
Fi='Fidah:BAAALgADCgEJAQAAAA==.Firemagemain:BAAALgADCgUJBQABLgAECggJGQAEAJ4eAA==.',
Fl='Flop:BAAALgAECgQJBAABLgAECgcJEgABAAAAAA==.',
Fr='Frostmere:BAAALgADCggJGAAAAA==.',
Fu='Fuknazum:BAAALgADCgYJBgAAAA==.Furcht:BAAALgAECgYJCwAAAA==.',
Ga='Galadar:BAAALgADCgUJBQAAAA==.',
Gi='Gitèff:BAAALgAFFAIJAwAAAA==.',
Go='Gourdin:BAAALgAECgQJBAABLgAECgUJBQABAAAAAA==.',
Gr='Gramnpa:BAAALgADCgUJBQAAAA==.Gravepriest:BAAALgADCgQJBAAAAA==.Grimtysha:BAAALgAECgIJAQAAAA==.Gromit:BAAALgAECgQJCQAAAA==.',
He='Hellbourne:BAAALgAECgQJDQAAAA==.',
Hi='Himmel:BAAALgADCgMJBAAAAA==.',
Ho='Hopnhorsé:BAAALgADCgEJAQAAAA==.Hotchoq:BAAALgAECgEJAQAAAA==.',
Hu='Huntchoq:BAAALgAFFAMJAwAAAA==.Huxley:BAAALgADCgMJAwAAAA==.',
Ik='Ikan:BAAALgADCgMJBAAAAA==.',
In='Infest:BAAALgAECgQJCAAAAA==.Inzolethys:BAAALgADCgcJBwAAAA==.',
It='Itchy:BAAALgADCgEJAQAAAA==.Itskiohte:BAAALgAECgcJDgAAAA==.',
Ja='Jaggernut:BAAALgADCgUJBQAAAA==.',
Jo='Johnny:BAAALgAECgIJAgABLgAECggJHQAPAPUgAA==.',
Ju='Judeau:BAAALgADCgEJAQAAAA==.',
Ka='Kaelthuzzad:BAAALgADCgEJAQAAAA==.Kaitza:BAAALgAECgYJCwAAAA==.Kalzaketh:BAABLgAECn8YAAMPAAYJpgc5PAD+AAAPAAYJpgc5PAD+AAAQAAMJ5QR7MwB5AAAAAA==.Kashari:BAAALgADCgkJCQABLgAECgkJTQAIAGsZAA==.Katali:BAAALgADCgYJBgAAAA==.Kazuggar:BAACLgAFFH8HAAITAAMJmR97BQAPAQATAAMJmR97BQAPAQAuAAQKfyIAAxMACAlRJW4CAFwDABMACAlRJW4CAFwDABQAAwleGkFdAM4AAAAA.',
Ke='Kebau:BAAALgADCgEJAQAAAA==.Kedar:BAAALgAECgYJCwAAAA==.Keg:BAAALgAECgIJAgAAAA==.Kelabar:BAAALgADCgQJBAAAAA==.',
Ki='Kiffs:BAAALgAECgYJCQAAAA==.Kirâ:BAAALgAECgYJBgAAAA==.',
Kr='Kregnar:BAAALgAECgQJCgAAAA==.Kresh:BAAALgAECgcJCwAAAA==.',
Ku='Kucabara:BAAALgADCgYJCQAAAA==.Kuraiwiggs:BAAALgADCgYJDAAAAA==.',
Kw='Kwichang:BAAALgAECgUJCAAAAA==.',
['Ké']='Kélpo:BAAALgADCgMJBAAAAA==.',
La='Lasagne:BAAALgADCgMJAwAAAA==.',
Li='Lickynose:BAAALgAECgcJEgAAAA==.Lips:BAAALgAECgEJAQAAAA==.',
Ls='Ls:BAAALgAECgcJEgAAAA==.',
Ma='Madarabia:BAAALgAECgYJDQAAAA==.Magellann:BAAALgAECgMJAwAAAA==.Mallidan:BAAALgADCgkJCQAAAA==.Mamut:BAAALgAECgEJAQAAAA==.Mantisar:BAAALgAECgUJEgAAAA==.Maxsm:BAABLgAECn8XAAIUAAgJrhmOIQACAgAUAAgJrhmOIQACAgAAAA==.',
Me='Melanippe:BAAALgAECgYJEwAAAA==.Meleefox:BAAALgADCgUJBQAAAA==.Melethron:BAABLgAECn8iAAIMAAgJxBGsEQCWAQAMAAgJxBGsEQCWAQAAAA==.Melioknky:BAAALgAECgYJBgAAAA==.',
Mi='Mid:BAAALgADCgYJBgAAAA==.Mightymage:BAABLgAECn8XAAIDAAcJpw1gGgB2AQADAAcJpw1gGgB2AQAAAA==.Milliondruid:BAAALgAECgMJBAAAAA==.Millionsm:BAAALgADCgQJBQAAAA==.Mirrorimage:BAAALgAECgMJBQABLgAFFAQJCQAIAH4PAA==.Mirrorx:BAACLgAFFH8JAAIIAAQJfg/jAgA6AQAIAAQJfg/jAgA6AQAuAAQKfyEAAggACAlUHBsEAOEBAAgACAlUHBsEAOEBAAAA.Miy:BAAALgAECgEJAQAAAA==.',
Mo='Moogle:BAAALgAECgIJBAAAAA==.Moomie:BAABLgAECn8bAAIVAAcJxBTLOwC1AQAVAAcJxBTLOwC1AQAAAA==.Moosfel:BAAALgAECgYJEAAAAA==.',
Mt='Mtzz:BAAALgAECgUJBQAAAA==.',
My='Mygravebroke:BAAALgADCggJCQAAAA==.Mystdragon:BAACLgAFFH8GAAIWAAIJeh4IEADLAAAWAAIJeh4IEADLAAAuAAQKfyUAAhYACAkOIP0FAOYCABYACAkOIP0FAOYCAAEuAAUUBgkXAAYAlRwA.Mystweaverr:BAACLgAFFH8XAAIGAAYJlRxsAgDwAQAGAAYJlRxsAgDwAQAuAAQKfykAAgYACAnnIHkJALsCAAYACAnnIHkJALsCAAAA.',
['Mö']='Mörae:BAAALgADCgEJAQABLgAECgYJEwABAAAAAA==.',
Na='Naddar:BAAALgAFFAQJBAAAAA==.Namadgi:BAAALgAECgcJCwAAAA==.Nathria:BAAALgAECgEJAQAAAA==.',
Ne='Netalis:BAAALgAECgcJEgAAAA==.',
Ni='Nikonii:BAAALgADCgQJBAAAAA==.',
Oa='Oakinelf:BAAALgADCgcJAQAAAA==.',
Om='Omnishifts:BAAALgADCgQJBAAAAA==.',
Or='Oramo:BAABLgAECn8aAAMRAAgJCSMjBQDxAgARAAgJwyIjBQDxAgAJAAYJ4R3vkgBaAQAAAA==.',
Pa='Paradisya:BAAALgADCggJDgAAAA==.',
Pe='Pets:BAAALgAECgEJAQAAAA==.',
Pl='Placebo:BAAALgADCgcJDAABLgAECggJHwAOAGwiAA==.',
Pr='Prothero:BAABLgAFFH8FAAIDAAMJABfrDwAQAQADAAMJABfrDwAQAQAAAA==.Proyo:BAAALgADCgUJBQAAAA==.',
['På']='Påthor:BAAALgAFFAEJAgAAAA==.',
Ra='Raikonnen:BAAALgAECgEJAQAAAA==.Rawtoor:BAACLgAFFH8PAAIXAAUJORyoBQBNAQAXAAUJORyoBQBNAQAuAAQKfxkAAhcACAn8IMonAGUCABcACAn8IMonAGUCAAAA.',
Re='Rebelsister:BAAALgADCgcJCQAAAA==.Refridgerate:BAAALgADCgUJBwAAAA==.',
Ri='Riddagain:BAAALgAECgYJDQAAAA==.Ridgemonk:BAABLgAECn8WAAMNAAcJpR5iGQA4AgANAAcJpR5iGQA4AgAGAAQJQAFmYABNAAAAAA==.Riggsdk:BAAALgADCgcJBwABLgAFFAUJFQAYAGolAA==.Riggshunt:BAACLgAFFH8VAAQYAAUJaiXTAACrAQAZAAUJliQvAAD7AQAYAAQJtCLTAACrAQAaAAEJAAChKABKAAAuAAQKfxoABBgACAmrJsEIAAcDABgABwmYJsEIAAcDABkACAlsJI8DAOwCABoAAQmCHFF9AE8AAAAA.',
Ro='Roadkill:BAABLgAECn8gAAIRAAgJnSOmAACkAgARAAgJnSOmAACkAgAAAA==.Rolltoor:BAAALgADCgYJCgAAAA==.Rosemary:BAAALgAECgQJBAAAAA==.',
Ry='Ryujin:BAAALgAECgQJCQAAAA==.',
Sa='Sansa:BAACLgAFFH8JAAIZAAQJIB21AAB+AQAZAAQJIB21AAB+AQAuAAQKfyEAAhkACAlmJF0CABwDABkACAlmJF0CABwDAAAA.Saso:BAACLgAFFH8IAAIDAAQJKxHyGgBfAQADAAQJKxHyGgBfAQAuAAQKfygABAMACAnVI5ACALACAAMACAnVI5ACALACAAsAAwkDH0UMAA0BABsAAgnECK4LAHcAAAAA.Sastroll:BAAALgAECgUJBQAAAA==.',
Sc='Scorn:BAAALgADCgcJCAAAAA==.Scroll:BAAALgAECgQJBAAAAA==.',
Se='Seluvis:BAAALgAECgYJCwAAAA==.Sentai:BAAALgADCgcJBwAAAA==.',
Sh='Shadow:BAACLgAFFH8IAAIXAAQJKwYbDAD/AAAXAAQJKwYbDAD/AAAuAAQKfyQAAhcACAmPHGccAKgCABcACAmPHGccAKgCAAAA.Shandrilah:BAAALgADCgQJBAAAAA==.Shapeshift:BAAALgADCgUJBQABLgAECgIJAgABAAAAAA==.Shialebuff:BAABLgAECn8YAAMCAAcJkCCWFwAfAgACAAcJkCCWFwAfAgAIAAQJvhLGPgD/AAAAAA==.Shijin:BAAALgAECgIJAgAAAA==.Shortfuze:BAAALgAECgUJCQAAAA==.',
Si='Sindar:BAAALgADCgUJBQAAAA==.Sinfall:BAAALgAECgEJAQAAAA==.Siscomp:BAABLgAECn9NAAIEAAkJihjCAgAuAgAEAAkJihjCAgAuAgAAAA==.Sixth:BAAALgAECgYJCwAAAA==.Sizzle:BAAALgADCgMJAwAAAA==.',
Sk='Sky:BAACLgAFFH8RAAIcAAYJCAw1AwDQAQAcAAYJCAw1AwDQAQAuAAQKfxQAAxwACAlxE40cALABABwABwlZEo0cALABAAIABQnyD3ZMAAYBAAAA.',
Sl='Sleck:BAAALgAECgYJCAAAAA==.',
Sn='Snappa:BAAALgADCgYJCwAAAA==.Sniped:BAAALgAFFAEJAQAAAA==.Snugglepuff:BAAALgAECgcJCwAAAA==.',
So='Soapfidas:BAAALgADCgcJBQAAAA==.Sonarius:BAAALgAECgcJEgAAAA==.',
Su='Su:BAABLgAECn8oAAIGAAcJqiVgBwDjAgAGAAcJqiVgBwDjAgAAAA==.Sudno:BAAALgAECgQJCAABLgAFFAMJCgAdAEYfAA==.Sundae:BAABLgAECn8dAAMCAAcJCSOMDQCAAgACAAcJCSOMDQCAAgAcAAQJFBnBLQAwAQAAAA==.Supersinpe:BAAALgAECgIJAgAAAA==.',
Sv='Svendlefyre:BAAALgADCgcJDgABLgAECgYJHgAOANgWAA==.Svholydrag:BAAALgADCgEJAQAAAA==.Svmishima:BAAALgADCgEJAQAAAA==.',
Sy='Sylvie:BAAALgAECgcJCAAAAA==.',
['Sý']='Sýlvanas:BAAALgAECgMJBgAAAA==.',
Te='Tealç:BAABLgAECn8ZAAIeAAcJpReLGACQAQAeAAcJpReLGACQAQABLgAFFAIJBQAeAIoSAA==.Tertle:BAAALgADCgUJBQAAAA==.',
Ti='Tiafinia:BAAALgAECgEJAQAAAA==.Timur:BAAALgAECgEJAQAAAA==.Tinara:BAAALgADCgUJBQAAAA==.',
Tr='Trigger:BAAALgAECgIJAgAAAA==.',
Tu='Turlesblows:BAABLgAECn8VAAMEAAYJXCFbJAA0AgAEAAYJXCFbJAA0AgAeAAEJOxWVRAA7AAAAAA==.',
Tw='Twityy:BAAALgADCgEJAgAAAA==.',
Ty='Tyladrhas:BAABLgAECn8UAAIfAAYJ0BkzAgCYAQAfAAYJ0BkzAgCYAQAAAA==.Tyrismaximus:BAAALgADCgQJBgAAAA==.',
Ul='Ulkina:BAAALgADCgYJCAAAAA==.',
Va='Vaelith:BAAALgAECgIJAgAAAA==.Valerine:BAAALgAECgcJEgAAAA==.Vanoran:BAAALgAECgMJAwAAAA==.Varang:BAAALgAECgIJAgAAAA==.Varina:BAAALgAECgYJEAAAAA==.',
Ve='Venki:BAAALgADCgMJAwAAAA==.',
Vo='Voidnova:BAAALgAFFAIJBAAAAA==.Voidphayze:BAAALgAECgUJDAABLgAECgcJEAABAAAAAA==.',
Vu='Vulken:BAABLgAECn9IAAIYAAkJSiEIAgCUAgAYAAkJSiEIAgCUAgAAAA==.',
['Vê']='Vê:BAAALgAECggJDgAAAA==.',
Wa='Wallace:BAAALgAECgcJDAAAAA==.Walterlight:BAAALgAECgYJDgAAAA==.Watto:BAAALgAECggJDQAAAA==.',
We='Wemongin:BAAALgADCgUJBQAAAA==.',
Wh='Whimsical:BAAALgAECgYJCwAAAA==.',
Wi='Winnìng:BAAALgAECgYJDgAAAA==.',
Wu='Wugong:BAAALgADCgEJAQAAAA==.',
['Wó']='Wórkwórk:BAABLgAECn8ZAAMEAAgJnh4VNwDLAQAEAAUJZCEVNwDLAQASAAMJ7Bq8HwDvAAAAAA==.',
Zi='Zich:BAAALgADCgMJAwAAAA==.Zihon:BAAALgAECgQJDwAAAA==.',
Zo='Zodiiak:BAABLgAECn8gAAIgAAYJ3B8ECwAcAgAgAAYJ3B8ECwAcAgAAAA==.',
Zu='Zupp:BAAALgADCgcJBwAAAA==.',
Zx='Zx:BAAALgADCgYJBgAAAA==.',
['Ér']='Ér:BAAALgAECgkJBAAAAA==.',
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

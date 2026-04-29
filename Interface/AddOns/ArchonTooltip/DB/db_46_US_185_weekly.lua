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

local lookup = {'Paladin-Holy','Paladin-Retribution','Warlock-Destruction','Unknown-Unknown','Hunter-Survival','Monk-Brewmaster','Warlock-Demonology','Warrior-Fury','Warrior-Arms','Evoker-Augmentation','Evoker-Devastation','Rogue-Outlaw','DeathKnight-Unholy','Shaman-Elemental','Mage-Frost','Druid-Guardian','DemonHunter-Devourer','Shaman-Restoration','Mage-Arcane','DeathKnight-Frost','Druid-Feral','Druid-Restoration','Mage-Fire','DemonHunter-Vengeance','Monk-Windwalker','Rogue-Assassination','Rogue-Subtlety','Druid-Balance','Hunter-BeastMastery',}
local provider = {region='US',realm='Scilla',name='US',type='weekly',zone=46,date='2026-04-24',data={Ab='Abeblinkin:BAAALgADCgkJDgAAAA==.',
Ae='Aedrius:BAABLgAECn8ZAAMBAAcJLRjINQClAQABAAYJrBnINQClAQACAAQJlRH+wAAFAQAAAA==.',
Ag='Agnekie:BAAALgADCgYJBgAAAA==.',
Ai='Aiwass:BAABLgAECn8XAAIDAAgJUwUbBAAdAQADAAgJUwUbBAAdAQAAAA==.',
Al='Alexander:BAAALgAECgMJAwAAAA==.',
Am='Amathricus:BAAALgAECgYJEAAAAA==.Amerika:BAAALgADCgIJAgAAAA==.',
Ar='Arawak:BAAALgADCgEJAQAAAA==.',
At='Athena:BAAALgAECgMJAwAAAA==.',
Au='Augtism:BAEALgAECgMJBwABLgAECgIJBwAEAAAAAA==.Auralei:BAAALgAECgMJAwAAAA==.',
Az='Azelia:BAAALgAECgUJCQABLgAECgYJEQAEAAAAAA==.Azzy:BAAALgAECgYJEQAAAA==.',
Ba='Bacta:BAAALgADCgQJBAAAAA==.',
Be='Beasti:BAAALgAECgIJAgAAAA==.Beelzebul:BAAALgAECgIJBAABLgAECgUJBwAEAAAAAA==.',
Bi='Bigb:BAABLgAECn8dAAIFAAcJGyHgBADEAgAFAAcJGyHgBADEAgAAAA==.Bigpaladin:BAAALgADCgEJAQAAAA==.',
Bo='Boor:BAAALgAECgMJAwAAAA==.',
Br='Broka:BAAALgAECgMJAwAAAA==.',
Bu='Bubblewrap:BAAALgAECgMJBgABLgAFFAMJBQAGAN0HAA==.',
Ch='Chonk:BAAALgADCgkJCwAAAA==.',
Cl='Claybigsby:BAACLgAFFH8FAAIHAAMJOw/uDgD8AAAHAAMJOw/uDgD8AAAuAAQKfxwAAwMACAm5HRIDAMoCAAMACAm5HRIDAMoCAAcABQmUGqJxAHwBAAAA.Clif:BAABLgAECn8ZAAMIAAgJqhziFgCWAgAIAAgJqhziFgCWAgAJAAEJTh1OEABWAAAAAA==.',
Co='Cosmiccosmo:BAAALgAECgQJBAAAAA==.',
Cu='Cucurbita:BAAALgADCgYJBgAAAA==.',
Da='Dargon:BAABLgAECn8WAAMKAAgJ3yNkBgAaAwAKAAgJ3yNkBgAaAwALAAYJ7hzIGwBSAQAAAA==.',
De='Deadlyorc:BAAALgADCgMJAwAAAA==.Deaf:BAAALgAECgYJDgABLgAECgcJHQAMAIIlAA==.Delphine:BAAALgADCgYJBgAAAA==.Demonblade:BAAALgADCgEJAQAAAA==.Demoniosushi:BAAALgAECgMJBAABLgAECgUJBwAEAAAAAA==.Demonmane:BAAALgADCgMJAwAAAA==.Derpy:BAAALgAECgQJBQAAAA==.',
Di='Dippindotz:BAAALgAECgEJAQABLgAFFAUJEAANAIAfAA==.',
Dj='Djheals:BAAALgAECgQJBQAAAA==.',
Do='Dorenis:BAAALgADCgUJBQAAAA==.',
Dr='Droopox:BAAALgAECgcJCQAAAA==.Druchese:BAAALgADCgcJEAABLgADCgkJFwAEAAAAAA==.',
Ea='Eagleeye:BAAALgAECgMJBgAAAA==.',
Em='Emsley:BAABLgAECn8pAAIOAAgJdxJNJwDYAQAOAAgJdxJNJwDYAQAAAA==.',
Er='Erised:BAAALgADCgMJAwAAAA==.',
Ex='Exo:BAACLgAFFH8FAAIPAAMJ4gzbEgD+AAAPAAMJ4gzbEgD+AAAuAAQKfx4AAg8ACAkzIS8gAPMCAA8ACAkzIS8gAPMCAAAA.',
Fe='Felrid:BAAALgAECgYJBgABLgAECggJFgAKAN8jAA==.',
Fl='Floudruid:BAAALgADCgMJAwAAAA==.',
Fo='Focalors:BAAALgAECgUJBwAAAA==.Foobear:BAACLgAFFH8FAAIQAAMJuQcVAgCmAAAQAAMJuQcVAgCmAAAuAAQKfyIAAhAACAm5HpwEAKQCABAACAm5HpwEAKQCAAAA.Fozzy:BAAALgAECgYJEAAAAA==.Fozél:BAAALgAECgEJAQAAAA==.',
Fr='Franchescold:BAABLgAECn8aAAINAAcJ/BcXDwCgAQANAAcJ/BcXDwCgAQAAAA==.Franfran:BAABLgAECn8XAAIPAAgJJQxhFgCQAQAPAAgJJQxhFgCQAQAAAA==.Freasey:BAAALgAECgMJBgAAAA==.Frostbeard:BAAALgADCgQJBwAAAA==.',
Fu='Furiousfoo:BAAALgAECgMJBgABLgAFFAMJBQAQALkHAA==.Furlock:BAAALgAECgMJBgAAAA==.',
Ga='Gabriel:BAAALgAECgcJBwAAAA==.Galicia:BAAALgAECgYJBgAAAA==.Gantaris:BAAALgAECgIJAgAAAA==.',
Gi='Gir:BAAALgAECgIJAgAAAA==.Gixian:BAAALgAECgYJEAAAAA==.',
Go='Gochese:BAAALgADCgkJFwAAAA==.',
Gr='Gramid:BAAALgAECgYJDQABLgAECggJFgAKAN8jAA==.Greenseer:BAABLgAECn8VAAIHAAYJWhGukQA1AQAHAAYJWhGukQA1AQAAAA==.Grognag:BAAALgAECgYJDgAAAA==.',
Gt='Gtoffmydh:BAAALgADCgIJAgAAAA==.',
Gw='Gwaralmighty:BAABLgAECn8fAAIIAAgJSiBUAQB5AgAIAAgJSiBUAQB5AgAAAA==.',
Ha='Haagen:BAAALgADCgEJAgAAAA==.Haagoon:BAAALgADCgUJBQAAAA==.Halfwolf:BAAALgADCgQJBAAAAA==.Hatch:BAABLgAECn8dAAIMAAcJgiUcAQDzAgAMAAcJgiUcAQDzAgAAAA==.',
Hh='Hholdem:BAAALgADCgcJBwABLgAECgYJEAAEAAAAAA==.',
Hi='Hightones:BAABLgAECn8hAAIRAAgJNiBIFgDRAgARAAgJNiBIFgDRAgAAAA==.',
Ho='Holdêm:BAAALgAECgYJEAAAAA==.Hollee:BAAALgADCgQJBAABLgAFFAIJBgASAGMRAA==.Horsdoeuvres:BAAALgAECgcJDgAAAA==.',
Hu='Humberto:BAAALgADCgEJAQAAAA==.',
Ic='Icylady:BAAALgADCgMJBQAAAA==.',
If='Ifrita:BAABLgAECn8cAAMTAAgJMxGlBwCGAQATAAYJIxOlBwCGAQAPAAcJ6Ay1JAA9AQAAAA==.Ifrite:BAABLgAECn8bAAMNAAgJAg3EfgCGAQANAAcJtAzEfgCGAQAUAAYJAAkBDwCwAAAAAA==.',
Ik='Ikur:BAAALgAECgMJAwABLgAECggJIgABAMMbAA==.',
It='Itita:BAAALgADCgIJAgAAAA==.',
Ja='Jackoneill:BAABLgAECn8gAAICAAgJUQ5rFQB1AQACAAgJUQ5rFQB1AQAAAA==.',
Je='Jezlana:BAAALgADCgcJDwAAAA==.',
Ji='Jillidan:BAAALgADCgUJBQAAAA==.',
Jo='Johnnynapalm:BAAALgAECgIJAwABLgAECgQJBAAEAAAAAA==.Jonnycraig:BAAALgAECgEJAgAAAA==.Jormi:BAABLgAECn8WAAIJAAcJyhyfAQDzAQAJAAcJyhyfAQDzAQAAAA==.',
Ka='Kabaayi:BAAALgADCgEJAQAAAA==.Kaihu:BAAALgADCgUJCAAAAA==.Kalthael:BAAALgADCgkJGAAAAA==.Kasura:BAABLgAECn8bAAMVAAgJCRszAQAZAgAVAAgJCRszAQAZAgAWAAQJmw+xgwDQAAAAAA==.',
Kh='Kharahealer:BAAALgAECgcJCwAAAA==.',
Kl='Kllausy:BAAALgAECgIJAwAAAA==.',
Ko='Kochese:BAAALgADCgcJBwABLgADCgkJFwAEAAAAAA==.',
Kw='Kwrr:BAAALgADCgYJBgABLgAFFAYJDAAHAJ0iAA==.',
La='Lambo:BAAALgAECgYJCwAAAA==.',
Le='Leafhoof:BAAALgAECgEJAQAAAA==.Lenona:BAAALgAECgIJAgAAAA==.Lexidia:BAAALgADCgUJBQAAAA==.Leynnar:BAAALgAECgQJCQAAAA==.',
Lo='Lockme:BAAALgADCgcJDQAAAA==.',
Lu='Lunk:BAAALgADCgEJAQAAAA==.',
['Ló']='Lóvecandy:BAAALgAECgEJAQABLgAECgIJAwAEAAAAAA==.',
Ma='Maruzensky:BAACLgAFFH8TAAIPAAUJ7R7ZCADaAQAPAAUJ7R7ZCADaAQAuAAQKfyoAAw8ACQlbI6MPAEoDAA8ACQlbI6MPAEoDABcABAmtD6MHAP8AAAAA.Mary:BAAALgAFFAIJAwAAAA==.',
Me='Mero:BAABLgAECn8dAAMYAAgJmRhbCQDZAQAYAAYJjR9bCQDZAQARAAcJbhDvZgBtAQAAAA==.Metal:BAAALgAECgQJCgAAAA==.Meyrey:BAAALgADCgYJCwAAAA==.',
Mi='Miorine:BAAALgAECgEJAQABLgAECgUJBwAEAAAAAA==.Mistbehavin:BAACLgAFFH8FAAIGAAMJ3QcbCQDSAAAGAAMJ3QcbCQDSAAAuAAQKfyIAAgYACAm5FvYcABsCAAYACAm5FvYcABsCAAAA.',
Mo='Mog:BAABLgAECn8iAAIBAAcJMyWrBgDoAQABAAcJMyWrBgDoAQAAAA==.Moochese:BAAALgADCgIJAgABLgADCgkJFwAEAAAAAA==.Moostache:BAAALgAECgEJAQAAAA==.',
Ne='Nemisai:BAAALgAECgMJAwAAAA==.',
No='Nobody:BAAALgADCgcJBwAAAA==.',
Oc='Ochra:BAAALgADCgEJAQAAAA==.',
Og='Ogparadox:BAAALgAECgQJBgAAAA==.',
Or='Orionbtch:BAAALgAECgUJDgAAAA==.',
Ov='Overheat:BAABLgAECn8UAAIPAAgJdBXCDgDQAQAPAAgJdBXCDgDQAQAAAA==.',
Po='Poppy:BAAALgAECgQJBQAAAA==.',
Qw='Qwiix:BAAALgADCgMJAwAAAA==.Qwixx:BAAALgADCgEJAQAAAA==.',
Ra='Rafikki:BAAALgAECgEJAQAAAA==.Ratidari:BAABLgAECn8WAAIRAAcJ/REzFQBTAQARAAcJ/REzFQBTAQAAAA==.',
Re='Remmîngton:BAABLgAECn8WAAMBAAcJtiBGAwBTAgABAAcJtiBGAwBTAgACAAEJdwc0QgEzAAAAAA==.Reverie:BAAALgADCgMJAwAAAA==.',
Rh='Rhynehardt:BAAALgAECgQJBAAAAA==.',
Ri='Riptidedro:BAABLgAECn8hAAISAAgJnx6mEwB4AgASAAgJnx6mEwB4AgAAAA==.',
Ru='Rukaz:BAAALgADCgYJBgAAAA==.Runslikedeer:BAAALgAECgUJCgAAAA==.Rustyarrow:BAAALgAECgEJAQAAAA==.',
Ry='Ryukk:BAABLgAECn8gAAINAAgJbBTTCwDGAQANAAgJbBTTCwDGAQAAAA==.',
Sa='Sanoth:BAAALgADCgEJAgAAAA==.Sarana:BAAALgADCgMJAwAAAA==.Sarkhael:BAAALgAECgUJCAAAAA==.',
Se='Sean:BAACLgAFFH8FAAIPAAMJFRYEEQAKAQAPAAMJFRYEEQAKAQAuAAQKfyIAAg8ACAmGI0QXAB4DAA8ACAmGI0QXAB4DAAAA.Secksecute:BAAALgAECgEJAgAAAA==.Seinsleer:BAAALgAECgQJBAAAAA==.Serah:BAAALgAECgcJBwAAAA==.Seris:BAAALgAECgYJBgABLgAECggJFgAKAN8jAA==.',
Sh='Shel:BAABLgAECn8XAAIRAAcJvwieJADuAAARAAcJvwieJADuAAAAAA==.Shimakaze:BAACLgAFFH8LAAINAAQJLR42DgBpAQANAAQJLR42DgBpAQAuAAQKfx0AAg0ABwmXIdErAIkCAA0ABwmXIdErAIkCAAAA.Shizaam:BAACLgAFFH8FAAIOAAMJIxNvBgD0AAAOAAMJIxNvBgD0AAAuAAQKfyIAAw4ACAkHJYYFAD4DAA4ACAkHJYYFAD4DABIAAQkrCXadADQAAAAA.Shlommy:BAAALgAECgcJEQAAAA==.',
Si='Siinns:BAABLgAECn8ZAAMZAAgJEh1aBAC+AQAZAAgJEh1aBAC+AQAGAAIJzhNCegBbAAAAAA==.Sinfxl:BAAALgAECgYJCgAAAA==.Sippinsizurp:BAAALgAECggJDwAAAA==.',
Sk='Skadooget:BAAALgADCgYJBgAAAA==.Skastep:BAAALgADCgYJBgAAAA==.Skullmages:BAACLgAFFH8IAAICAAQJyhf2CABnAQACAAQJyhf2CABnAQAuAAQKfxkAAgIABwk3I6ogAKkCAAIABwk3I6ogAKkCAAAA.',
Sl='Slayur:BAAALgAECgYJEgAAAA==.Slinkeril:BAAALgAECgQJBQAAAA==.Sloppydro:BAAALgAECgEJAQAAAA==.',
Sm='Smackthat:BAAALgAECgIJAwABLgAECgUJBwAEAAAAAA==.Smokey:BAAALgAECgEJAQABLgAECgUJBwAEAAAAAA==.Smokinpurrp:BAAALgAECgQJBAAAAA==.Smoky:BAAALgAECgUJBwAAAA==.',
So='Soju:BAAALgAECgEJAgAAAA==.Sotari:BAAALgADCggJCQAAAA==.',
Sp='Sploosh:BAAALgADCgEJAQAAAA==.',
St='Stabberz:BAABLgAECn8pAAMaAAgJxxvVAgC5AgAaAAgJqBvVAgC5AgAbAAQJNxKiSwDNAAAAAA==.Stõrmy:BAAALgAECgIJAgAAAA==.',
Su='Sushiroll:BAAALgAECgQJBgABLgAFFAUJEAANAIAfAA==.',
Sw='Sweetsourrex:BAAALgAECgEJAwAAAA==.',
Sy='Synkro:BAAALgAECgYJBgABLgAECgYJCgAEAAAAAA==.',
Te='Tempprance:BAAALgADCgcJBwAAAA==.',
Th='Thewordalive:BAAALgADCgIJAgAAAA==.Tholdraz:BAAALgAECgEJAQAAAA==.Thooran:BAAALgAECgIJBQAAAA==.Thrass:BAABLgAECn8aAAIPAAcJKhAZFwCLAQAPAAcJKhAZFwCLAQAAAA==.Throngler:BAAALgAECgYJEQAAAA==.',
To='Toobrunner:BAACLgAFFH8LAAIRAAUJBiC4BQBNAQARAAUJBiC4BQBNAQAuAAQKfyAAAhEACAldImMbAK4CABEACAldImMbAK4CAAAA.Tool:BAACLgAFFH8JAAIRAAQJaR45CwB9AQARAAQJaR45CwB9AQAuAAQKfxQAAhEACQkKIQcMACEDABEACQkKIQcMACEDAAEuAAUUCAkZAA8AHBsA.',
Up='Upside:BAAALgAECgEJAgAAAA==.',
Uz='Uzi:BAAALgAECgYJCQAAAA==.',
Va='Varvera:BAAALgADCgMJAwAAAA==.',
Ve='Velannis:BAABLgAECn8gAAMMAAgJrSAwAACGAgAMAAgJrSAwAACGAgAaAAMJvx0uEgDiAAAAAA==.',
Vi='Virikas:BAABLgAECn8WAAISAAcJEh2rAwBCAgASAAcJEh2rAwBCAgAAAA==.',
Vo='Voidhunter:BAABLgAECn8XAAIRAAcJGBbEEAB/AQARAAcJGBbEEAB/AQAAAA==.Voodooki:BAABLgAECn8WAAIcAAcJCA0qCgBKAQAcAAcJCA0qCgBKAQAAAA==.',
Vu='Vuo:BAABLgAECn8VAAIdAAYJWxCcUgBxAQAdAAYJWxCcUgBxAQAAAA==.',
Wa='Wayside:BAAALgAECgEJBAAAAA==.',
Wh='White:BAAALgAECgMJAwABLgABCgIJAgAEAAAAAA==.',
Wi='Wilburoni:BAAALgADCgIJAgAAAA==.Wiping:BAAALgAECgIJAQABLgAECgcJIgABADMlAA==.',
Xf='Xfreshh:BAAALgAECgYJDQAAAA==.',
Ya='Yamalock:BAAALgAECgUJBQAAAA==.Yamå:BAABLgAECn8XAAIPAAYJayJVXwAdAgAPAAYJayJVXwAdAgAAAA==.',
Ye='Yeaffa:BAAALgADCgYJBgAAAA==.',
Yi='Yingzhi:BAAALgADCgIJAgAAAA==.',
Za='Zavalu:BAAALgAECgYJEwAAAA==.',
Ze='Zerosh:BAAALgAECgcJEAAAAA==.',
Zi='Zinaida:BAAALgADCggJCAAAAA==.',
Zo='Zortok:BAABLgAECn8bAAIOAAcJ6hIfCQBsAQAOAAcJ6hIfCQBsAQAAAA==.',
['Âc']='Âce:BAAALgAECgEJAQAAAA==.',
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

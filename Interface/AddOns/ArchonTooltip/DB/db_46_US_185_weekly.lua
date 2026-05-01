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

local lookup = {'Paladin-Holy','Paladin-Retribution','Warlock-Destruction','Unknown-Unknown','Hunter-Survival','Monk-Brewmaster','DeathKnight-Unholy','Warlock-Demonology','Warrior-Arms','Warrior-Fury','Evoker-Augmentation','Evoker-Devastation','Rogue-Outlaw','Shaman-Elemental','Mage-Frost','Druid-Guardian','Monk-Windwalker','DemonHunter-Devourer','Shaman-Restoration','Mage-Arcane','Mage-Fire','DeathKnight-Frost','Druid-Feral','Druid-Restoration','Rogue-Assassination','DemonHunter-Vengeance','Rogue-Subtlety','DeathKnight-Blood','Druid-Balance','Hunter-BeastMastery',}
local provider = {region='US',realm='Scilla',name='US',type='weekly',zone=46,date='2026-05-01',data={Ab='Abeblinkin:BAAALgAECgEJAQAAAA==.Aborlight:BAAALgADCgUJBQAAAA==.',
Ad='Adit:BAAALgADCgMJAwAAAA==.',
Ae='Aedrius:BAABLgAECn8ZAAMBAAcJLRjENQClAQABAAYJrBnENQClAQACAAQJlREDwQAFAQAAAA==.',
Ag='Agnekie:BAAALgAECgEJAQAAAA==.',
Ai='Aiwass:BAABLgAECn8fAAIDAAgJCgrIBgBKAQADAAgJCgrIBgBKAQAAAA==.Aiyo:BAAALgAECgEJAQABLgAECgYJCAAEAAAAAA==.',
Al='Alexander:BAAALgAECgMJAwAAAA==.',
Am='Amathricus:BAABLgAECn8YAAICAAgJGwtyOQBfAQACAAgJGwtyOQBfAQAAAA==.Amerika:BAAALgADCgIJAgAAAA==.',
Ar='Arawak:BAAALgADCgEJAQAAAA==.',
As='Ashuk:BAAALgAECgIJAQAAAA==.',
At='Athena:BAAALgAECgMJAwAAAA==.',
Au='Augtism:BAEALgAFFAEJAQABLgAECgIJEQAEAAAAAA==.Auitou:BAAALgAECgIJAgAAAA==.Auralei:BAAALgAECgUJCAAAAA==.',
Az='Azelia:BAAALgAECgUJCQABLgAECgYJGAABAIwZAA==.Azzy:BAABLgAECn8YAAIBAAYJjBlvGQCBAQABAAYJjBlvGQCBAQAAAA==.',
Ba='Bacta:BAAALgADCgUJBQAAAA==.',
Be='Beasti:BAAALgAECgIJAgAAAA==.Beelzebul:BAAALgAECgIJBAABLgAECgUJBwAEAAAAAA==.',
Bi='Bigb:BAABLgAECn8gAAIFAAcJKSbiBADEAgAFAAcJKSbiBADEAgAAAA==.Bigpaladin:BAAALgADCgEJAQAAAA==.',
Bl='Black:BAAALgAECgQJBAAAAA==.',
Bo='Boor:BAAALgAECgYJCAAAAA==.',
Br='Brilline:BAAALgADCgYJCgAAAA==.Brochese:BAAALgAECgEJAQABLgAECgEJAQAEAAAAAA==.Broka:BAAALgAECgMJAwAAAA==.',
Bu='Bubblewrap:BAAALgAECgQJCAABLgAFFAQJCQAGAJcPAA==.',
Ca='Canadianguy:BAAALgADCgIJAgABLgAECgEJAQAEAAAAAA==.',
Ch='Chonk:BAAALgADCgkJCwAAAA==.',
Cl='Classcarry:BAAALgADCgYJBgABLgAFFAYJFgAHAFghAA==.Claybigsby:BAACLgAFFH8JAAIIAAQJghXHEwBNAQAIAAQJghXHEwBNAQAuAAQKfxwAAwMACAm5HREDAMoCAAMACAm5HREDAMoCAAgABQmUGqZxAHwBAAAA.Clif:BAACLgAFFH8HAAMJAAQJhwt0BQArAQAJAAQJhwt0BQArAQAKAAEJhgNAJQBJAAAuAAQKfxkAAwoACAmqHN4WAJYCAAoACAmqHN4WAJYCAAkAAQlOHTolAFgAAAAA.',
Co='Cosmiccosmo:BAAALgAECgQJBAAAAA==.',
Cu='Cucurbita:BAAALgADCgYJBgAAAA==.',
Da='Dargon:BAABLgAECn8XAAMLAAgJ3yNlBgAaAwALAAgJ3yNlBgAaAwAMAAYJ7hzQGwBSAQABLgAFFAEJAQAEAAAAAA==.',
De='Deadlyorc:BAAALgADCgMJAwAAAA==.Deaf:BAAALgAFFAEJAQABLgAFFAMJBQANAL4hAA==.Delphine:BAAALgADCgYJBgAAAA==.Demonblade:BAAALgADCgEJAQAAAA==.Demoniosushi:BAAALgAECgMJBwABLgAECgUJCgAEAAAAAA==.Demonmane:BAAALgADCgMJAwAAAA==.Derpy:BAAALgAECgYJCwAAAA==.',
Di='Dippindotz:BAAALgAECgEJAQABLgAFFAYJFgAHAFghAA==.',
Dj='Djheals:BAAALgAECgQJBQAAAA==.',
Do='Dorenis:BAAALgADCgUJBQAAAA==.',
Dr='Drachese:BAAALgAECgEJAQABLgAECgEJAQAEAAAAAA==.Droopox:BAAALgAECggJEQAAAA==.Druchese:BAAALgAECgEJAQABLgAECgEJAQAEAAAAAA==.',
Ea='Eagleeye:BAAALgAECgQJCgAAAA==.',
Em='Emsley:BAABLgAECn8xAAIOAAkJKhFvCgD0AQAOAAkJKhFvCgD0AQAAAA==.',
Er='Erised:BAAALgADCgMJAwAAAA==.',
Ex='Exo:BAACLgAFFH8JAAIPAAQJqhcXGABlAQAPAAQJqhcXGABlAQAuAAQKfx4AAg8ACAkzITEgAPMCAA8ACAkzITEgAPMCAAAA.',
Fe='Felrid:BAAALgAECgYJBgABLgAFFAEJAQAEAAAAAA==.',
Fl='Floudruid:BAAALgADCgMJAwAAAA==.',
Fo='Focalors:BAAALgAECgUJBwAAAA==.Foobear:BAACLgAFFH8JAAIQAAQJdQuxAwDpAAAQAAQJdQuxAwDpAAAuAAQKfyIAAhAACAm5HpsEAKQCABAACAm5HpsEAKQCAAAA.Fozzy:BAABLgAECn8WAAILAAYJHgm1JgDVAAALAAYJHgm1JgDVAAAAAA==.Fozél:BAAALgAECgEJAQAAAA==.',
Fr='Franchescold:BAABLgAECn8cAAIHAAgJ5hl3GgDpAQAHAAgJ5hl3GgDpAQAAAA==.Franfran:BAABLgAECn8ZAAIPAAgJ3w6DNACTAQAPAAgJ3w6DNACTAQAAAA==.Freasey:BAAALgAECgQJCgAAAA==.Frostbeard:BAAALgADCgQJBwAAAA==.',
Fu='Furiousfoo:BAAALgAECgQJCgABLgAFFAQJCQAQAHULAA==.Furlock:BAAALgAECgQJCgAAAA==.',
Ga='Gabriel:BAAALgAECgcJBwAAAA==.Galicia:BAAALgAECgYJBgAAAA==.Gantaris:BAAALgAECgIJAgAAAA==.',
Ge='Gengiskaan:BAAALgADCgMJAwAAAA==.',
Gi='Gir:BAAALgAECgQJBQAAAA==.Gixian:BAAALgAECgYJEAAAAA==.',
Go='Gochese:BAAALgAECgEJAQAAAA==.',
Gr='Gramid:BAAALgAFFAEJAQAAAA==.Greenseer:BAABLgAECn8ZAAIIAAYJWhG6VADzAAAIAAYJWhG6VADzAAAAAA==.Grognag:BAAALgAECgYJDgAAAA==.',
Gt='Gtoffmydh:BAAALgADCgIJAgAAAA==.',
Gw='Gwaralmighty:BAABLgAECn8oAAIKAAkJjR+vAQDiAgAKAAkJjR+vAQDiAgAAAA==.',
Ha='Haagen:BAAALgADCgEJAgAAAA==.Haagoon:BAAALgADCgYJCwAAAA==.Halfwolf:BAAALgADCgQJBAAAAA==.Hatch:BAACLgAFFH8FAAINAAMJviGjAQAsAQANAAMJviGjAQAsAQAuAAQKfx0AAg0ABwmCJRwBAPMCAA0ABwmCJRwBAPMCAAAA.',
Hh='Hholdem:BAAALgADCgcJBwABLgAECgYJFgARAFQQAA==.',
Hi='Hightones:BAACLgAFFH8FAAISAAQJHQQDIgDeAAASAAQJHQQDIgDeAAAuAAQKfyAAAhIACAk2IE0WANECABIACAk2IE0WANECAAAA.',
Ho='Holdêm:BAABLgAECn8WAAIRAAYJVBCuGAAiAQARAAYJVBCuGAAiAQAAAA==.Holeytoast:BAAALgAECgQJBAABLgAFFAQJCQAOAAQeAA==.Hollee:BAAALgADCgQJBAABLgAFFAMJCQATABIQAA==.Horsdoeuvres:BAAALgAECgcJDgAAAA==.',
Hu='Humberto:BAAALgADCgEJAQAAAA==.Hung:BAAALgAECgEJAgAAAA==.',
Ic='Icylady:BAAALgADCgUJCgAAAA==.',
If='Ifrita:BAABLgAECn8lAAQUAAgJYROoBwCGAQAUAAYJIxOoBwCGAQAPAAgJFg/BPwBvAQAVAAEJwQnxCAAzAAAAAA==.Ifrite:BAABLgAECn8bAAMHAAgJAg3AfgCGAQAHAAcJtAzAfgCGAQAWAAYJAAkCDwCwAAAAAA==.',
Ik='Ikur:BAAALgAECgMJAwABLgAECggJJAABAMMbAA==.',
It='Itita:BAAALgADCgIJAgAAAA==.',
Ja='Jackoneill:BAABLgAECn8hAAICAAgJdRANbgChAQACAAgJdRANbgChAQAAAA==.',
Je='Jezlana:BAAALgAECgQJBAAAAA==.',
Ji='Jillidan:BAAALgAECgEJAQAAAA==.',
Jo='Johnnynapalm:BAAALgAECgIJAwABLgAECgQJBAAEAAAAAA==.Jonnycraig:BAAALgAECgEJAgAAAA==.Jormi:BAABLgAECn8eAAIJAAgJJB6+AQCIAgAJAAgJJB6+AQCIAgAAAA==.',
Ka='Kabaayi:BAAALgADCgEJAQAAAA==.Kaihu:BAAALgADCgUJCAAAAA==.Kalthael:BAAALgADCgkJGAAAAA==.Kasura:BAABLgAECn8dAAMXAAgJCRsyAwAeAgAXAAgJCRsyAwAeAgAYAAQJmw+1gwDQAAAAAA==.',
Kh='Kharahealer:BAAALgAECgcJDwAAAA==.',
Kl='Kllausy:BAAALgAECgIJAwAAAA==.',
Ko='Kochese:BAAALgAECgEJAQABLgAECgEJAQAEAAAAAA==.',
Kw='Kwrr:BAAALgADCgYJBgABLgAFFAYJEQAIADMlAA==.',
La='Lambo:BAAALgAECgYJEQAAAA==.',
Le='Leafhoof:BAAALgAECgEJAQAAAA==.Lenona:BAAALgAECgIJAgAAAA==.Lexidia:BAAALgADCgUJBQAAAA==.Leynnar:BAAALgAECgUJDAAAAA==.',
Li='Licha:BAAALgAECgcJBQAAAA==.',
Lo='Lockme:BAAALgAECgEJAQAAAA==.Loveyuling:BAAALgAECgEJAQABLgAECgQJBQAEAAAAAA==.',
Lu='Lunk:BAAALgADCgEJAQAAAA==.',
['Ló']='Lóvecandy:BAAALgAECgQJBQAAAA==.',
Ma='Maruzensky:BAACLgAFFH8aAAIPAAYJ0yCGBQDXAQAPAAYJ0yCGBQDXAQAuAAQKfyoAAw8ACQlbI6kPAEoDAA8ACQlbI6kPAEoDABUABAmtD6MHAP8AAAAA.Mary:BAACLgAFFH8HAAIZAAMJeR9AAgAlAQAZAAMJeR9AAgAlAQAuAAQKfxYAAhkACAnrH7ICAMECABkACAnrH7ICAMECAAAA.',
Me='Mero:BAABLgAECn8eAAMaAAgJmRhcCQDZAQAaAAYJjR9cCQDZAQASAAcJNRH1ZgBtAQAAAA==.Metal:BAAALgAECgYJEAAAAA==.Meyrey:BAAALgADCgYJCwAAAA==.',
Mi='Miorine:BAAALgAECgEJAQABLgAECgUJBwAEAAAAAA==.Mistbehavin:BAACLgAFFH8JAAIGAAQJlw/EDQAlAQAGAAQJlw/EDQAlAQAuAAQKfyIAAgYACAm5FvYcABsCAAYACAm5FvYcABsCAAAA.',
Mo='Mog:BAABLgAECn8iAAIBAAcJMyXSCQA5AgABAAcJMyXSCQA5AgAAAA==.Moochese:BAAALgAECgEJAQABLgAECgEJAQAEAAAAAA==.Moostache:BAAALgAECgMJBAAAAA==.',
My='Mytz:BAAALgADCgEJAQAAAA==.',
Ne='Nemisai:BAAALgAECgMJBgAAAA==.',
No='Nobody:BAAALgADCgcJBwAAAA==.',
Oc='Ochra:BAAALgAECgEJAQAAAA==.',
Og='Ogparadox:BAAALgAECgQJBwAAAA==.',
Or='Orionbtch:BAABLgAECn8VAAIbAAcJLgeREgBNAQAbAAcJLgeREgBNAQAAAA==.',
Ov='Overheat:BAABLgAECn8UAAIPAAgJdBXyOwB6AQAPAAgJdBXyOwB6AQAAAA==.',
Po='Poppy:BAAALgAECgQJBwAAAA==.',
Ps='Psycilocibin:BAAALgADCgEJAQAAAA==.',
Qw='Qwiix:BAAALgADCgMJAwAAAA==.Qwixx:BAAALgADCgEJAQAAAA==.',
Ra='Rafikki:BAAALgAECgUJBgAAAA==.Ratidari:BAABLgAECn8YAAISAAgJARQGGgCaAQASAAgJARQGGgCaAQAAAA==.Ravenstorm:BAAALgAECgIJAQAAAA==.',
Re='Remmîngton:BAABLgAECn8eAAMBAAgJEB/8AwC+AgABAAgJEB/8AwC+AgACAAEJdwdcQgEzAAAAAA==.Reverie:BAAALgADCgMJAwAAAA==.',
Rh='Rhynehardt:BAAALgAECgQJBAAAAA==.',
Ri='Riptidedro:BAABLgAECn8iAAITAAgJnx6jEwB4AgATAAgJnx6jEwB4AgAAAA==.',
Ru='Rukaz:BAAALgADCgYJBgAAAA==.Runslikedeer:BAAALgAECgYJDQAAAA==.Rustyarrow:BAAALgAECgEJAQAAAA==.',
Ry='Ryukk:BAABLgAECn8iAAIHAAgJJheLIwC0AQAHAAgJJheLIwC0AQAAAA==.',
Sa='Sanoth:BAAALgADCgEJAgAAAA==.Sarana:BAAALgADCgMJAwAAAA==.Sarkhael:BAAALgAECgUJCAAAAA==.',
Se='Sean:BAACLgAFFH8JAAIPAAQJORvdEwBxAQAPAAQJORvdEwBxAQAuAAQKfyIAAg8ACAmGI0YXAB4DAA8ACAmGI0YXAB4DAAAA.Secksecute:BAAALgAECgIJBQAAAA==.Seinsleer:BAAALgAECgQJBAAAAA==.Serah:BAAALgAECgkJBwAAAA==.Seris:BAAALgAECgYJBgABLgAFFAEJAQAEAAAAAA==.',
Sh='Shel:BAABLgAECn8fAAISAAgJAArNLQAtAQASAAgJAArNLQAtAQAAAA==.Shimakaze:BAACLgAFFH8QAAMHAAUJxSI8DgBpAQAHAAQJxSI8DgBpAQAcAAEJAADmHwAAAAAuAAQKfx8AAgcABwljJNgrAIkCAAcABwljJNgrAIkCAAAA.Shizaam:BAACLgAFFH8JAAIOAAQJBB5uBQBvAQAOAAQJBB5uBQBvAQAuAAQKfyIAAw4ACAkHJYoFAD4DAA4ACAkHJYoFAD4DABMAAQkrCXadADQAAAAA.Shlommy:BAAALgAECgcJEQAAAA==.',
Si='Siinns:BAABLgAECn8cAAMRAAkJjR2OBQA/AgARAAkJjR2OBQA/AgAGAAIJzhM2egBbAAAAAA==.Simp:BAAALgAECgIJAgAAAA==.Sinfxl:BAAALgAECgYJCgAAAA==.Sippinsizurp:BAAALgAECggJDwAAAA==.',
Sk='Skadooget:BAAALgADCgYJBgAAAA==.Skullmages:BAACLgAFFH8MAAICAAQJ/hf9CABnAQACAAQJ/hf9CABnAQAuAAQKfxkAAgIABwk3I6QgAKkCAAIABwk3I6QgAKkCAAAA.',
Sl='Slayur:BAABLgAECn8VAAIKAAYJRwwELADrAAAKAAYJRwwELADrAAAAAA==.Slinkeril:BAAALgAECgUJCgAAAA==.Sloppydro:BAAALgAECgEJAgAAAA==.',
Sm='Smackthat:BAAALgAECgQJBgABLgAECgUJCgAEAAAAAA==.Smokey:BAAALgAECgQJBAABLgAECgUJCgAEAAAAAA==.Smokinpurrp:BAAALgAECgQJBAAAAA==.Smoky:BAAALgAECgUJCgAAAA==.',
So='Soju:BAAALgAECgEJBAAAAA==.Sotari:BAAALgADCggJCQAAAA==.',
Sp='Sploosh:BAAALgADCgEJAQAAAA==.',
St='Stabberz:BAABLgAECn8xAAMZAAkJ2x2YAAC5AgAZAAkJvx2YAAC5AgAbAAQJNxKlSwDNAAAAAA==.Stõrmy:BAAALgAECgIJAgAAAA==.',
Su='Sushiroll:BAAALgAECgQJBgABLgAFFAYJFgAHAFghAA==.',
Sw='Sweetsourrex:BAAALgAECgYJCAAAAA==.',
Sy='Synkro:BAAALgAECgYJBgABLgAECgYJCgAEAAAAAA==.',
Ta='Tatisjr:BAAALgAECgIJAgAAAA==.',
Te='Tempprance:BAAALgADCgcJDQAAAA==.',
Th='Thewordalive:BAAALgADCgIJAgAAAA==.Tholdraz:BAAALgAECgEJAQAAAA==.Thooran:BAAALgAECgIJBgAAAA==.Thrass:BAABLgAECn8cAAIPAAgJKBFnKgC7AQAPAAgJKBFnKgC7AQAAAA==.Throngler:BAAALgAECgYJEQAAAA==.',
To='Toobrunner:BAACLgAFFH8OAAISAAYJRx8eAgDpAQASAAYJRx8eAgDpAQAuAAQKfx0AAhIACAlSImQbAK4CABIACAlSImQbAK4CAAAA.Tool:BAACLgAFFH8JAAISAAQJpyA6CwB9AQASAAQJpyA6CwB9AQAuAAQKfxYAAhIACQmRIQkMACEDABIACQmRIQkMACEDAAAA.',
Up='Upside:BAAALgAECgEJAgAAAA==.',
Uz='Uzi:BAAALgAECgYJCQAAAA==.',
Va='Varvera:BAAALgADCgMJAwAAAA==.',
Ve='Velannis:BAABLgAECn8lAAMNAAkJoCEjAAAcAwANAAkJoCEjAAAcAwAZAAQJ+BwtEgDiAAAAAA==.',
Vi='Virikas:BAABLgAECn8cAAMTAAcJXx0OCwA6AgATAAcJXx0OCwA6AgAOAAQJJwzsNACiAAAAAA==.',
Vo='Voidhunter:BAABLgAECn8RAAISAAcJGBa/WwCOAQASAAcJGBa/WwCOAQAAAA==.Voodooki:BAABLgAECn8eAAIdAAgJfQ12EgB3AQAdAAgJfQ12EgB3AQAAAA==.',
Vu='Vuo:BAABLgAECn8dAAIeAAgJqQ+/HwCiAQAeAAgJqQ+/HwCiAQAAAA==.',
Wa='Wayside:BAAALgAECgEJBQAAAA==.',
We='Weedonice:BAAALgAECgcJBQAAAA==.',
Wh='White:BAAALgAECgQJBwABLgABCgIJAgAEAAAAAA==.',
Wi='Wilburoni:BAAALgADCgIJAgAAAA==.Wiping:BAAALgAECgIJAQABLgAECgcJIgABADMlAA==.',
Xf='Xfreshh:BAAALgAECgYJDQAAAA==.',
Ya='Yamalock:BAAALgAECgUJBQAAAA==.Yamamist:BAAALgAECgQJBAABLgAFFAMJBgAPAKsWAA==.Yamå:BAACLgAFFH8GAAIPAAMJqxbTLgAOAQAPAAMJqxbTLgAOAQAuAAQKfxkAAg8ABglrIk1fAB0CAA8ABglrIk1fAB0CAAAA.',
Ye='Yeaffa:BAAALgADCgYJBgAAAA==.',
Yi='Yingzhi:BAAALgADCgIJAgAAAA==.',
Za='Zavalu:BAABLgAECn8aAAITAAcJ7SDgBwBtAgATAAcJ7SDgBwBtAgAAAA==.',
Ze='Zerosh:BAAALgAECgcJEAAAAA==.',
Zi='Zinaida:BAAALgADCggJCAAAAA==.',
Zo='Zortok:BAABLgAECn8dAAIOAAgJ0RKwEACfAQAOAAgJ0RKwEACfAQAAAA==.',
['Âc']='Âce:BAAALgAECgEJAgAAAA==.',
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

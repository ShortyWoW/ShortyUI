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

local lookup = {'Evoker-Preservation','Evoker-Augmentation','DeathKnight-Blood','DemonHunter-Havoc','Unknown-Unknown','Hunter-BeastMastery','Hunter-Survival','DeathKnight-Unholy','Druid-Restoration','Priest-Discipline','Warrior-Protection','Rogue-Assassination','Rogue-Subtlety','Rogue-Outlaw','Paladin-Retribution','DeathKnight-Frost','Priest-Holy','DemonHunter-Devourer','Druid-Feral','Hunter-Marksmanship','Shaman-Elemental','Monk-Mistweaver','Monk-Windwalker','Monk-Brewmaster','Priest-Shadow','Paladin-Protection','Paladin-Holy','Warrior-Fury','Warrior-Arms','Evoker-Devastation','Mage-Frost','Druid-Guardian',}
local provider = {region='US',realm='ScarletCrusade',name='US',type='weekly',zone=46,date='2026-04-24',data={Ac='Acefu:BAAALgAECgYJBgAAAA==.Acornita:BAACLgAFFH8GAAMBAAMJ5w9MEQCsAAABAAMJ5w9MEQCsAAACAAEJZAAJFAA6AAAuAAQKfyYAAwEACQnlD0ARACgCAAEACQnlD0ARACgCAAIABwk9EvsjAJ0BAAAA.',
Ai='Ailanthus:BAAALgAECgYJEQAAAA==.',
Ak='Akinira:BAEBLgAECn8kAAIDAAkJNR4PAQBtAgADAAkJNR4PAQBtAgAAAA==.',
Al='Aleinadris:BAAALgADCgQJBAAAAA==.Alikchi:BAAALgADCgEJAgAAAA==.Alloisaber:BAAALgAECgYJCAAAAA==.Alternis:BAAALgAECgMJAwAAAA==.',
An='Andrelsia:BAAALgAECgEJAQAAAA==.',
Ap='Apôllyon:BAABLgAECn8fAAIEAAkJqCTuAAC+AwAEAAkJqCTuAAC+AwAAAA==.',
Ar='Aracelis:BAAALgAECgEJAQAAAA==.Archertower:BAAALgADCgUJBQAAAA==.Artemiswynd:BAAALgADCgYJBgAAAA==.Arén:BAAALgAECgYJDwAAAA==.',
As='Ashenshugär:BAAALgAECgEJAQAAAA==.',
Av='Avadda:BAAALgAECgYJEQAAAA==.',
Az='Azmar:BAAALgAECgYJEgAAAA==.',
Ba='Balain:BAAALgADCgcJBwABLgAECgUJEQAFAAAAAA==.',
Be='Bearmont:BAAALgADCgkJIwAAAA==.Bearzerk:BAAALgAECgYJEQAAAA==.Beastmonk:BAAALgADCgEJAQAAAA==.Benathar:BAAALgAECgYJEQAAAA==.',
Bi='Bionico:BAAALgAECgEJAgAAAA==.Birgir:BAAALgADCgYJBgAAAA==.',
Bl='Blackmagék:BAAALgADCgcJBwAAAA==.Bloodrager:BAAALgADCgIJAgAAAA==.Bloodthorn:BAAALgAECgYJEAAAAA==.Blortimor:BAAALgADCgcJBwAAAA==.',
Bo='Bombad:BAAALgAECgYJBwAAAA==.Boomnescient:BAAALgAECgEJAQAAAA==.Bozscaggs:BAABLgAECn8dAAMGAAgJtAwVRgCYAQAGAAgJtAwVRgCYAQAHAAUJBQNbCwDZAAAAAA==.',
Br='Bramis:BAAALgADCgcJFQAAAA==.Brantu:BAAALgADCgQJCAABLgADCgYJCgAFAAAAAA==.Braultus:BAABLgAECn8VAAIDAAcJ9xoZBACaAQADAAcJ9xoZBACaAQAAAA==.',
Bu='Burstangel:BAAALgAECgMJAwAAAA==.',
By='Byrddh:BAAALgADCgQJBAAAAA==.',
Ca='Caliopedk:BAABLgAECn8ZAAMIAAgJCyFdIQC7AgAIAAgJCyFdIQC7AgADAAUJSQ41KgDtAAAAAA==.Capra:BAAALgADCgkJGAAAAA==.Carillanklip:BAAALgADCgUJBQAAAA==.',
Cd='Cdmickey:BAAALgADCgUJBQAAAA==.',
Ce='Celestè:BAAALgAECgYJCQAAAA==.Celéste:BAAALgAECgQJBAAAAA==.Cerdwin:BAAALgAECgYJCQABLgAECggJHgAJAOgVAA==.',
Ch='Chibeard:BAAALgAECgYJEQAAAA==.Chonglin:BAAALgADCgIJAgAAAA==.',
Cl='Clubsdh:BAAALgADCgEJAQAAAA==.',
Co='Coolbro:BAAALgADCgIJAgAAAA==.Corialis:BAAALgAECgcJDgAAAA==.',
Cr='Crom:BAAALgAECgYJEgAAAA==.Crosis:BAAALgADCgYJBgAAAA==.Cruelladvoid:BAAALgAECgEJAQAAAA==.Cruush:BAAALgAECgYJBQAAAA==.',
Cu='Culerro:BAAALgAECgYJAwABLgAECgYJBQAFAAAAAA==.Cursive:BAAALgADCgUJDQAAAA==.',
Cy='Cygnes:BAAALgAECgYJDAAAAA==.',
Da='Daddywarrior:BAAALgADCgUJBgAAAA==.Daeva:BAAALgADCgEJAQAAAA==.Dantey:BAAALgADCgYJBgAAAA==.Dazanna:BAAALgAECgUJDQAAAA==.Dazre:BAAALgAECgQJBAAAAA==.',
De='Deeminor:BAAALgADCgYJDgAAAA==.Desktop:BAABLgAECn8VAAIKAAYJGBcSBgChAQAKAAYJGBcSBgChAQAAAA==.',
Di='Diod:BAABLgAECn8VAAILAAYJuxapCAAAAQALAAYJuxapCAAAAQAAAA==.Divineßovine:BAAALgADCgcJBwAAAA==.',
Dr='Dracovoid:BAAALgADCgMJAwAAAA==.Draehton:BAAALgAECgQJBAAAAA==.Dragyns:BAABLgAECn8jAAQMAAkJRBuBAgDKAgAMAAkJtxiBAgDKAgANAAUJkBo5LACcAQAOAAMJqxRSCQDcAAAAAA==.Dragynseye:BAAALgADCgIJAgABLgAECgkJIwAMAEQbAA==.Drayper:BAAALgAECgYJCwAAAA==.Druugal:BAABLgAECn8kAAMNAAgJcCBDDADUAgANAAgJcCBDDADUAgAMAAEJegvjHwAzAAAAAA==.',
Du='Dubs:BAAALgAECgUJCgAAAA==.Dunbarke:BAAALgAECgQJBgAAAA==.',
Ef='Efishient:BAABLgAECn8UAAIJAAYJJyLdHgBIAgAJAAYJJyLdHgBIAgABLgAFFAUJEAAJAM0UAA==.',
El='Elliwynd:BAAALgAECgUJDQAAAA==.',
Eo='Eoshot:BAAALgAECgMJAwAAAA==.',
Er='Erinnys:BAAALgAECgYJDAAAAA==.Ermoril:BAAALgAECgMJAwAAAA==.Ernesta:BAAALgADCgcJCAAAAA==.',
Eu='Eufemia:BAAALgAECgEJAQAAAA==.',
['Eø']='Eøs:BAAALgAECgEJAQAAAA==.',
Fa='Famine:BAAALgAECgcJDAAAAA==.',
Fe='Felern:BAAALgAECgEJAQABLgAECgYJEgAFAAAAAA==.Feyrun:BAAALgADCgkJEwAAAA==.Feyrè:BAAALgADCgEJAgAAAA==.',
Fi='Finalomega:BAAALgAECgQJAwAAAA==.',
Fl='Flaminfalcon:BAAALgADCgYJCAABLgADCgcJCwAFAAAAAA==.Flody:BAAALgAECgYJDAAAAA==.',
Fo='Foxflame:BAABLgAECn8eAAIJAAgJ6BXYBgD/AQAJAAgJ6BXYBgD/AQAAAA==.',
Fr='Franzen:BAAALgADCgYJCQAAAA==.Freakbob:BAAALgADCgYJCQAAAA==.Froglocky:BAAALgAECgYJEQAAAA==.Fronsac:BAAALgADCgQJBAAAAA==.',
Fu='Fulanita:BAAALgAECgQJCQAAAA==.',
Ga='Garzok:BAAALgAECgYJEAAAAA==.',
Ge='Genkithered:BAAALgAECgYJEQAAAA==.',
Gi='Gilernil:BAAALgAECgEJAQAAAA==.',
Gl='Gladtohelp:BAAALgAECgIJAgAAAA==.',
Gn='Gnoquarter:BAAALgADCgIJAgAAAA==.',
Gr='Gravemarks:BAABLgAECn8YAAMOAAgJjRO1AADpAQAOAAgJjRO1AADpAQAMAAQJzAnaEQDoAAAAAA==.Grimhorn:BAAALgAECgIJAwAAAA==.Grimlie:BAAALgADCgYJCgAAAA==.Grumblen:BAAALgADCgMJAwAAAA==.',
Gu='Guaritrice:BAAALgADCgkJHwAAAA==.Gubb:BAAALgAECgMJAwAAAA==.',
Gw='Gwenylane:BAABLgAECn8UAAIPAAgJ0wUYHABGAQAPAAgJ0wUYHABGAQAAAA==.Gwindor:BAAALgAECgEJAQAAAA==.Gwyndelyn:BAAALgAECgYJEQAAAA==.',
Ha='Hatterus:BAAALgAECgYJDwAAAA==.',
He='Herculeze:BAAALgAECgMJAwAAAA==.Hessian:BAAALgADCgEJAQAAAA==.',
Hi='Hillbroken:BAABLgAECn8eAAIQAAgJ1BueAAAoAgAQAAgJ1BueAAAoAgAAAA==.',
Ho='Holycross:BAAALgAECgIJAgAAAA==.',
Hu='Huntertidus:BAAALgADCgcJBwABLgAECgkJHwAPAB8VAA==.',
['Hà']='Hànks:BAAALgAECgQJBAAAAA==.',
Im='Imo:BAAALgAECgUJDQAAAA==.',
In='Intrepidz:BAAALgADCgcJCwAAAA==.Inèvitable:BAABLgAECn8XAAIIAAgJyhGgDwCaAQAIAAgJyhGgDwCaAQAAAA==.',
Ja='Javeech:BAAALgAECgYJCwAAAA==.',
Je='Jebib:BAAALgAECgYJBgAAAA==.Jeod:BAAALgAECgEJAQAAAA==.',
Jo='Johnflamos:BAAALgAECgEJAQAAAA==.Jolty:BAACLgAFFH8FAAIIAAIJjh6CEwC/AAAIAAIJjh6CEwC/AAAuAAQKfyYAAwgACQlWIq4MADUDAAgACQlWIq4MADUDAAMAAwm2GO8KANAAAAAA.',
Ka='Kaiou:BAAALgADCgMJAwAAAA==.Kantor:BAABLgAECn8eAAIRAAgJyBU8BQDUAQARAAgJyRU8BQDUAQAAAA==.Karnstein:BAAALgAECgcJEgAAAA==.Kasryna:BAAALgAECgEJAQAAAA==.Kathinja:BAAALgAECgUJCgAAAA==.',
Ke='Kelumbria:BAAALgAECgYJCAAAAA==.Keta:BAAALgADCgYJBgAAAA==.Ketameanie:BAABLgAECn8aAAISAAYJFBxeSADSAQASAAYJFBxeSADSAQAAAA==.',
Ki='Kieran:BAAALgAECgIJAgAAAA==.Kitsunè:BAAALgAECgEJAQAAAA==.',
Km='Kmazing:BAAALgAECgMJAwAAAA==.',
Kn='Knifèparty:BAAALgAECgMJAwAAAA==.',
Ko='Konoha:BAAALgAECgUJDQAAAA==.',
Ku='Kultag:BAAALgAECgUJCgAAAA==.',
Ky='Kyaw:BAAALgAECgYJCwAAAA==.Kynzo:BAABLgAECn8eAAITAAgJlhHBAwByAQATAAgJlhHBAwByAQAAAA==.',
La='Laykeezenith:BAACLgAFFH8QAAQUAAUJfh0cBwCrAQAUAAUJzBocBwCrAQAGAAMJ2xr9DACyAAAHAAEJrwdPBwBXAAAuAAQKfxgABBQACAmyIycVAIYCABQABwk/JCcVAIYCAAYAAwnqIveMAMMAAAcAAgl3EgMoAHUAAAAA.Lazuli:BAABLgAECn8hAAIVAAgJnRM8BgCrAQAVAAgJnRM8BgCrAQAAAA==.',
Le='Lehann:BAABLgAECn8UAAIGAAgJ2w8oCgDGAQAGAAgJ2w8oCgDGAQAAAA==.',
Li='Lichtech:BAAALgAECgQJBAABLgAFFAQJCAACAMQSAA==.',
Lu='Luciselda:BAAALgADCgUJBgAAAA==.Lunariah:BAAALgADCgYJDgAAAA==.Luvtarhugar:BAAALgADCgMJAwAAAA==.',
Ma='Marenus:BAABLgAECn8cAAIGAAgJPhBhDgCRAQAGAAgJPhBhDgCRAQAAAA==.Masume:BAAALgADCgcJEwAAAA==.Maély:BAAALgAECgEJAgAAAA==.',
Me='Mechadead:BAAALgADCgIJAgAAAA==.Meowmix:BAAALgADCgMJAwAAAA==.',
Mi='Miantha:BAAALgAECgMJAwAAAA==.Michi:BAABLgAECn8bAAIJAAgJJSH4CAAAAwAJAAgJJSH4CAAAAwAAAA==.Midnights:BAAALgAECgYJCAAAAA==.Mightymopo:BAAALgADCgMJAwAAAA==.Mikuki:BAABLgAECn8XAAIGAAgJmyGmDQDRAgAGAAgJmyGmDQDRAgAAAA==.Milkinghands:BAABLgAECn8XAAMWAAgJSw+aJQCIAQAWAAgJSw+aJQCIAQAXAAEJlAJBJQApAAAAAA==.Mizmonk:BAACLgAFFH8IAAIYAAQJbBOLAwBJAQAYAAQJbBOLAwBJAQAuAAQKfyIAAhgACQnoHqQJAO4CABgACQnoHqQJAO4CAAAA.',
Mj='Mjölnir:BAAALgAECgEJAQAAAA==.',
Mo='Montfort:BAAALgADCggJDwAAAA==.Moovover:BAAALgAECgcJCQAAAA==.',
My='Mykian:BAAALgAECgYJEQAAAA==.Myrwynn:BAAALgADCgcJDQABLgAECgcJGQAZAOYRAA==.Mythundon:BAAALgADCgUJBQAAAA==.',
Na='Nahion:BAAALgAECgEJAQAAAA==.Nashira:BAAALgAECgYJCwAAAA==.Nature:BAAALgAECgUJCwAAAA==.',
Ne='Necrana:BAAALgADCgEJAQAAAA==.Necrobyarg:BAAALgAECgYJDQAAAA==.Nemasus:BAAALgAECgYJEQAAAA==.Nembie:BAAALgADCgMJAwAAAA==.',
Ni='Ninjahh:BAAALgAECgcJCQAAAA==.Nioshei:BAAALgAECgYJEQAAAA==.Nisara:BAABLgAECn8ZAAMWAAgJsx6FCgCqAgAWAAgJsx6FCgCqAgAXAAYJCBjEIgDAAQAAAA==.',
No='Nochmuerta:BAAALgAECggJDwAAAA==.Nogrid:BAABLgAECn8eAAIaAAgJIxPiBABZAQAaAAgJIxPiBABZAQAAAA==.Notmyface:BAAALgAECgcJDAABLgAECggJIwAPADElAA==.',
Nu='Nuthar:BAAALgAECgYJEAAAAA==.',
Om='Ominousowl:BAAALgADCgQJBAABLgADCgcJCwAFAAAAAA==.',
Or='Oregizm:BAAALgAECgQJBAAAAA==.',
Pa='Pamburu:BAABLgAECn8bAAQUAAgJQQsECADlAAAGAAYJOA25bwAZAQAUAAYJtQUECADlAAAHAAIJrQUJKgBgAAAAAA==.Papagrape:BAAALgAECgYJEwAAAA==.Parzivàl:BAABLgAECn8iAAIbAAgJuRabEwB1AgAbAAgJuRabEwB1AgAAAA==.Paxa:BAAALgAECgUJCwAAAA==.',
Pe='Peacebox:BAAALgADCgcJCwABLgAECgMJAwAFAAAAAA==.',
Ph='Phoebel:BAAALgADCgYJDQAAAA==.Phoenixbodhi:BAAALgAECgQJBAAAAA==.',
Po='Podnov:BAACLgAFFH8FAAMGAAMJZR0KDAC5AAAGAAIJjh0KDAC5AAAUAAMJkhVhHACkAAAuAAQKfyAAAhQACQk6GwMOANECABQACQk6GwMOANECAAAA.',
Pr='Preyon:BAAALgAECgEJAgABLgAECgUJEQAFAAAAAA==.',
Py='Pyne:BAAALgADCgEJAQAAAA==.',
Qo='Qotho:BAABLgAECn8eAAIGAAgJ2hkjBwD5AQAGAAgJ2hkjBwD5AQAAAA==.',
Ra='Raistliin:BAAALgAECgYJDgAAAA==.Raithis:BAACLgAFFH8JAAIGAAQJaBLPAwBMAQAGAAQJaBLPAwBMAQAuAAQKfyYAAgYACQmmIMIEAEEDAAYACQmmIMIEAEEDAAAA.Ramhadin:BAEALgADCgkJFAABLgAECgQJBQAFAAAAAA==.',
Re='Rednaxel:BAAALgAECgYJEQAAAA==.Redvelvet:BAAALgAECgYJEAAAAA==.Rekoner:BAAALgAECgUJDQAAAA==.Retarganator:BAAALgAECgYJEAAAAA==.',
Ri='Rixaa:BAAALgADCgIJAgABLgAECgUJCAAFAAAAAA==.',
Ro='Rocks:BAAALgAECgYJCAAAAA==.Romam:BAAALgAECgEJAQAAAA==.',
Ru='Rubyknight:BAAALgADCgYJCAAAAA==.',
Ry='Rykria:BAAALgADCgcJCgAAAA==.',
Sa='Samsonknight:BAAALgADCgYJBgAAAA==.Sanguinarian:BAAALgAECgYJDwAAAA==.',
Se='Secksiecutie:BAAALgAECgUJDQAAAA==.Selanda:BAAALgADCgcJCgAAAA==.Serinar:BAAALgAECgMJAwAAAA==.',
Sh='Shoshin:BAAALgAECgUJEQAAAA==.Shïvana:BAAALgAECgMJAwAAAA==.',
Si='Silversaiyan:BAABLgAECn8cAAMcAAcJVCCnHABoAgAcAAcJVCCnHABoAgAdAAEJXRiAOgBGAAAAAA==.',
Sl='Slade:BAABLgAECn8cAAMNAAgJAiHLAQA3AgANAAgJAiHLAQA3AgAMAAIJBxkRGgBZAAAAAA==.Sliyce:BAAALgAECgIJBQAAAA==.',
Sm='Smóke:BAABLgAECn8eAAISAAgJYBH4FABVAQASAAgJYBH4FABVAQAAAA==.',
Sn='Snowfawn:BAAALgAECgQJBAABLgAECgUJCQAFAAAAAA==.',
So='Sofedan:BAABLgAECn8eAAIUAAgJ4wWNBABKAQAUAAgJ4wWNBABKAQAAAA==.Sorgath:BAAALgADCggJCwAAAA==.Soriel:BAAALgADCgIJAgABLgAECgYJEQAFAAAAAA==.',
Sq='Squids:BAAALgADCgQJBAAAAA==.',
Su='Sunsword:BAAALgAECgUJCwAAAA==.',
Sw='Swagidan:BAABLgAECn8ZAAIEAAgJbhb+EQBMAgAEAAgJbhb+EQBMAgAAAA==.Sweatermonk:BAAALgADCgIJAgABLgAECgYJBgAFAAAAAA==.Sweaterpally:BAAALgADCggJFQABLgAECgYJBgAFAAAAAA==.Swiftera:BAABLgAECn8cAAIbAAgJURaTCQCpAQAbAAgJURaTCQCpAQAAAA==.Swiftlier:BAABLgAECn8fAAIYAAgJUxmEBQC1AQAYAAgJUxmEBQC1AQAAAA==.Swipegirl:BAAALgAECgYJCQAAAA==.',
Sy='Sylphrène:BAABLgAECn8XAAIEAAcJCAahCQABAQAEAAcJCAahCQABAQAAAA==.',
Ta='Taladan:BAAALgAECgEJAQAAAA==.Tandrana:BAAALgADCgcJDwAAAA==.Tanwen:BAAALgAECgYJBgAAAA==.Targypunch:BAAALgADCgcJBwABLgAECgYJEAAFAAAAAA==.',
Te='Techniqe:BAACLgAFFH8IAAICAAQJxBJ0BgAfAQACAAQJxBJ0BgAfAQAuAAQKfykAAwIACAk9IhYHAAoDAAIACAk9IhYHAAoDAB4ABgkgIeUSALMBAAAA.Techtides:BAAALgADCgUJBQABLgAFFAQJCAACAMQSAA==.Temperance:BAAALgADCgEJAQAAAA==.Temptations:BAAALgAECgEJAQAAAA==.Terminus:BAAALgAECgEJAQAAAA==.Terrylin:BAAALgAECgMJAwAAAA==.',
Th='Thaliá:BAAALgADCgkJFQAAAA==.Thomag:BAAALgADCgIJAgAAAA==.',
Ti='Ticebane:BAABLgAECn8jAAIDAAkJNBmvCwBYAgADAAkJNBmvCwBYAgAAAA==.Tiduspullo:BAABLgAECn8fAAMPAAkJHxWXRAAWAgAPAAkJHxWXRAAWAgAaAAEJRw6lRgAnAAAAAA==.Tiduswar:BAAALgAECgYJEAABLgAECgkJHwAPAB8VAA==.Tinafay:BAAALgAECgcJDAAAAA==.Titanbeard:BAAALgADCgkJEAAAAA==.Titor:BAAALgAECgUJCgAAAA==.Tituspullo:BAAALgADCgEJAQABLgAECgkJHwAPAB8VAA==.',
To='Tolduan:BAAALgAECgUJDQAAAA==.Totemik:BAAALgADCgYJBgAAAA==.Toughturkey:BAAALgAECgIJBAAAAA==.',
Tr='Tremorhoof:BAAALgADCgIJAwAAAA==.Tresera:BAAALgADCgEJAQAAAA==.Tricarnetry:BAAALgAECgcJDwAAAA==.Trufleshufle:BAAALgAECggJEAAAAA==.',
Uh='Uhtread:BAAALgADCgUJBQAAAA==.',
Un='Unholyfury:BAAALgADCgYJBgAAAA==.',
Va='Vapor:BAAALgAECgMJAwAAAA==.Vaquinha:BAAALgADCgUJBQAAAA==.Varyel:BAAALgAECgIJAgAAAA==.',
Ve='Velianne:BAAALgADCgUJBQAAAA==.Vellinada:BAAALgADCgMJAwABLgAFFAMJCgARAP8jAA==.Verakis:BAAALgAECgYJEQAAAA==.Verndarí:BAAALgAECgYJCgABLgAECggJHwAYAFMZAA==.',
Vo='Vortheus:BAAALgAECgQJCgAAAA==.Votollis:BAAALgAECgQJBQAAAA==.',
Wa='Warlanen:BAAALgAECgEJAQAAAA==.Warning:BAAALgADCgUJBQAAAA==.Warpiggies:BAAALgADCgkJCAAAAA==.',
Wi='Widdy:BAAALgAECgYJDgAAAA==.Willbur:BAABLgAECn8eAAIfAAgJVBWVEQC1AQAfAAgJVBWVEQC1AQAAAA==.',
Wu='Wurthwhile:BAAALgADCggJGgAAAA==.',
Wy='Wylaniris:BAAALgADCgQJBAAAAA==.Wyndywalker:BAAALgAECgYJEQAAAA==.',
Xa='Xaveil:BAAALgADCgEJAQAAAA==.',
Xe='Xenosian:BAAALgAECgkJCQAAAA==.',
Xi='Xinnuo:BAAALgADCgEJBAAAAA==.',
Xy='Xydias:BAAALgAECggJCgAAAA==.Xyra:BAAALgADCgcJBwAAAA==.',
Yo='Yoku:BAAALgAECggJEwAAAA==.',
Za='Zamønk:BAABLgAECn8VAAMYAAcJFg8jOABqAQAYAAcJFg8jOABqAQAXAAIJTAZnbgBXAAAAAA==.Zaphoidvtwo:BAAALgADCgcJBwAAAA==.Zason:BAAALgADCgMJAwAAAA==.Zatari:BAAALgADCgMJAwAAAA==.',
Ze='Zelectie:BAABLgAECn8XAAIgAAgJbhctCgD3AQAgAAgJbhctCgD3AQABLgAFFAUJDQAYACgbAA==.Zelzaikin:BAAALgADCgUJBQAAAA==.',
Zi='Zinazarinara:BAAALgADCgQJDQAAAA==.Zirril:BAAALgADCgcJDwAAAA==.',
Zo='Zombiechick:BAAALgAECgMJBAAAAA==.',
['ßr']='ßrigitte:BAAALgADCgYJCgABLgADCgcJBwAFAAAAAA==.',
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

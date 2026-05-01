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

local lookup = {'Rogue-Subtlety','DemonHunter-Devourer','Hunter-BeastMastery','Warrior-Protection','Mage-Frost','Monk-Windwalker','DeathKnight-Unholy','Druid-Restoration','Druid-Balance','Shaman-Elemental','Shaman-Restoration','Paladin-Retribution','Priest-Discipline','Priest-Holy','Evoker-Augmentation','Unknown-Unknown','Paladin-Holy','Priest-Shadow','Warrior-Arms','Warrior-Fury','Hunter-Marksmanship','Monk-Brewmaster','Shaman-Enhancement','Rogue-Assassination','Paladin-Protection','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Monk-Mistweaver',}
local provider = {region='US',realm='Auchindoun',name='US',type='weekly',zone=46,date='2026-05-01',data={Ad='Adnerb:BAAALgAECgUJDgABLgAFFAUJBQABAEcPAA==.',
Ah='Ahriman:BAABLgAECn8XAAICAAYJHQ6RPgDsAAACAAYJHQ6RPgDsAAAAAA==.',
Al='Alystra:BAAALgAECgYJEgAAAA==.',
An='Anjedin:BAAALgAECgYJCgAAAA==.',
Ao='Aoki:BAABLgAECn8VAAIDAAcJYxx1IQA8AgADAAcJYxx1IQA8AgAAAA==.',
Ar='Archdemon:BAABLgAECn8aAAIEAAcJFBa2CQCSAQAEAAcJFBa2CQCSAQAAAA==.Argonos:BAAALgAECgcJDQAAAA==.Arielias:BAAALgAECgQJBAABLgAFFAUJBQABAEcPAA==.Arkanoas:BAACLgAFFH8FAAIFAAQJQgqQJgA4AQAFAAQJQgqQJgA4AQAuAAQKfykAAgUACQmwFg44AJQCAAUACQmwFg44AJQCAAAA.',
As='Ashatal:BAAALgADCgEJAQAAAA==.Ashphantom:BAAALgAECgIJAgAAAA==.',
Ba='Bagelbite:BAAALgADCgUJBQAAAA==.Banshee:BAAALgAECgYJDAABLgAFFAUJBQABAEcPAA==.Battahelin:BAAALgAECgQJBgAAAA==.',
Be='Bearmanowl:BAAALgAECgYJBQAAAA==.Bellator:BAAALgAECgMJBAAAAA==.',
Bi='Bigchungus:BAABLgAECn8dAAIGAAYJ/AgFIwDTAAAGAAYJ/AgFIwDTAAAAAA==.',
Bl='Blart:BAAALgAECgUJBwAAAA==.',
Br='Breathplay:BAABLgAECn8XAAIHAAgJgRuUPQBBAgAHAAgJgRuUPQBBAgAAAA==.',
['Bà']='Bàyne:BAABLgAECn8qAAIIAAkJqxHnLAD7AQAIAAkJqxHnLAD7AQAAAA==.',
Ca='Caroquintero:BAABLgAECn8YAAIFAAYJZwPqiQC/AAAFAAYJZwPqiQC/AAAAAA==.',
Ch='Charliemen:BAAALgADCgcJBgAAAA==.Chilli:BAAALgADCgEJAQAAAA==.Chubtart:BAABLgAECn8tAAIJAAkJ0CI+CAASAwAJAAkJ0CI+CAASAwAAAA==.Churrasco:BAAALgAECgMJAwAAAA==.',
Cl='Clayton:BAAALgADCgcJBAAAAA==.',
Cu='Cunumi:BAAALgAECgMJBAAAAA==.',
Da='Daddy:BAABLgAECn8rAAMKAAgJlBNKFAB1AQAKAAgJlBNKFAB1AQALAAYJsApOWQAjAQAAAA==.Danehar:BAAALgAECgEJAQAAAA==.',
Dc='Dcone:BAAALgADCgYJBgAAAA==.',
De='Deadkey:BAAALgADCgEJAQAAAA==.Deathborne:BAAALgAECgUJCAAAAA==.Deathshreik:BAAALgADCgMJAwAAAA==.Deathslam:BAABLgAECn8YAAIHAAgJMhjJFQAMAgAHAAgJMhjJFQAMAgAAAA==.',
Dr='Droston:BAAALgADCgQJBAAAAA==.',
Du='Dutchess:BAABLgAECn8UAAIMAAYJORrgOgBaAQAMAAYJORrgOgBaAQAAAA==.',
Dy='Dylan:BAACLgAFFH8JAAIFAAQJLBOUHwBSAQAFAAQJLBOUHwBSAQAuAAQKfx4AAgUACAn9JHcFAOMCAAUACAn9JHcFAOMCAAAA.Dylanj:BAAALgAECgQJBAAAAQ==.',
Ec='Echevalier:BAAALgAECgQJBQAAAA==.',
Eg='Egonspengler:BAAALgADCgMJAwAAAA==.',
El='Elowen:BAAALgAECgcJHQAAAQ==.',
En='Enhae:BAAALgAECgEJAQAAAA==.',
Er='Eresiine:BAAALgAECgYJBgAAAA==.Eríngo:BAAALgAECgcJCwAAAA==.',
Es='Esna:BAAALgADCgUJBgAAAA==.',
Fi='Filomena:BAAALgADCgUJBgAAAA==.Firnin:BAAALgAECgYJCgAAAA==.',
Fl='Floise:BAACLgAFFH8HAAMNAAQJXhOUEQDyAAANAAMJZQ+UEQDyAAAOAAIJVBNVDQCTAAAuAAQKfx0AAw4ACQn7GXwMAIwCAA4ACQlBGXwMAIwCAA0ABwkPFdYZABgBAAAA.Flounder:BAAALgAECgEJAwAAAA==.',
Fo='Forumsoldier:BAABLgAECn8jAAIFAAgJkxcrVAA8AgAFAAgJkxcrVAA8AgAAAA==.',
Fr='Frozenscorch:BAAALgAECgYJDAAAAA==.',
['Fä']='Fälkor:BAABLgAECn8cAAIPAAgJXwZxHgAMAQAPAAgJXwZxHgAMAQAAAA==.',
['Fö']='Föx:BAAALgADCgEJAQABLgAECgYJDQAQAAAAAA==.',
Gi='Gigamoo:BAAALgAECgQJBgAAAA==.',
Gl='Glys:BAAALgAECgQJBgAAAA==.',
Go='Gooba:BAAALgAECgEJAQAAAA==.Goommar:BAAALgAECgIJAgAAAA==.Gorim:BAAALgAECgIJAgAAAA==.',
Gr='Grandgoose:BAAALgADCgIJAgAAAA==.Granuju:BAAALgADCgUJBgAAAA==.',
Gu='Gunnhildr:BAAALgADCgkJCQAAAA==.',
Ha='Hanasanai:BAAALgADCgMJBAAAAA==.Handil:BAABLgAECn8VAAIRAAYJNyCODwDpAQARAAYJNyCODwDpAQAAAA==.',
He='Helpingyou:BAAALgAECgcJBwAAAA==.',
Ho='Holybell:BAAALgAECgIJAgAAAA==.Hoptyj:BAAALgADCgIJAgAAAA==.',
['Hë']='Hënnessy:BAAALgADCgMJAwAAAA==.Hënnëssy:BAAALgAECgYJDwAAAA==.',
Io='Iolanthe:BAAALgADCgQJBAAAAA==.',
Iz='Izeroeasily:BAAALgAECgMJAwAAAA==.Izerohealz:BAAALgADCgQJBAAAAA==.Izzi:BAAALgAECgYJBgAAAA==.Izzia:BAAALgAECgUJDwAAAA==.',
Ja='Jabbathabutt:BAAALgADCgYJEwAAAA==.Jasia:BAAALgADCgIJAgAAAA==.',
Jo='Joyboy:BAAALgAECgEJAQAAAA==.',
Ju='Justfn:BAAALgADCgUJBwAAAA==.',
Ka='Kamitos:BAABLgAECn8jAAMNAAcJIRGuFABQAQANAAcJIRGuFABQAQASAAUJyAhgRADZAAAAAA==.Kayewyn:BAAALgAECgYJEwAAAA==.',
Kb='Kbdh:BAAALgAECgYJBwABLgAFFAIJAwAQAAAAAA==.Kbdruid:BAAALgAFFAEJAQABLgAFFAIJAwAQAAAAAA==.Kbhunter:BAAALgAECgUJCAABLgAFFAIJAwAQAAAAAA==.Kbmage:BAAALgADCgQJBAABLgAFFAIJAwAQAAAAAA==.Kbmonk:BAAALgAFFAIJAwAAAA==.',
Ke='Keiji:BAAALgAECgUJBQAAAA==.',
Kl='Klipnor:BAAALgAECgQJCAAAAA==.',
Kr='Krocketeer:BAAALgAECgYJCQAAAA==.',
Ky='Kyndel:BAAALgAECgQJBAABLgAFFAMJBgAIAIEQAA==.Kynn:BAACLgAFFH8GAAIIAAMJgRByGgDIAAAIAAMJgRByGgDIAAAuAAQKfy0AAggACQmWIvQBAIEDAAgACQmWIvQBAIEDAAAA.',
['Kè']='Kèlemvore:BAABLgAECn8dAAIMAAcJMxLJNABwAQAMAAcJMxLJNABwAQAAAA==.',
Le='Leafittome:BAAALgADCgEJAQAAAA==.',
Ly='Lykos:BAAALgAECgIJAgAAAA==.',
Ma='Mammal:BAAALgAECgQJBAAAAA==.',
Me='Medxchaos:BAAALgAECgQJBwABLgAFFAQJBwANAF4TAA==.Meowy:BAAALgAECgEJAQAAAA==.Mepha:BAABLgAECn8cAAMTAAgJbB84BQDcAQAUAAcJ+B/0GACDAgATAAgJJxM4BQDcAQAAAA==.',
Mu='Muddless:BAABLgAECn8UAAMTAAcJsBtlBQDUAQATAAcJsBtlBQDUAQAUAAEJ6gvGpQA5AAAAAA==.Mudds:BAABLgAECn8bAAIGAAgJnyB1EAB5AgAGAAgJnyB1EAB5AgAAAA==.',
Na='Naelia:BAAALgAECgMJAwAAAA==.Nakira:BAAALgAECgMJAwAAAA==.Nami:BAAALgAECgUJBQAAAA==.',
Ni='Nicodemus:BAAALgADCgEJAQAAAA==.Nightrush:BAABLgAECn8oAAMDAAgJICVzBQCiAgADAAYJBCZzBQCiAgAVAAYJqSEKBADXAQAAAA==.',
No='Noodles:BAAALgAECgYJEgAAAA==.Norbit:BAAALgAECgEJAQAAAA==.',
Oe='Oesteroth:BAAALgAECgUJDgAAAA==.',
Pa='Palaben:BAABLgAECn8bAAMRAAgJdRF8GwBwAQARAAcJrBJ8GwBwAQAMAAQJUAxBhwCdAAAAAA==.Pantsu:BAABLgAECn8pAAIHAAgJpCRTBQDQAgAHAAgJpCRTBQDQAgAAAA==.Pateaviejas:BAAALgADCgEJAQAAAA==.Pawnchy:BAAALgAECgUJCQAAAA==.',
Pe='Peepaw:BAAALgAECgQJCwAAAA==.',
Pi='Pitchwhite:BAABLgAECn8XAAIOAAYJKhELHQAcAQAOAAYJKhELHQAcAQAAAA==.Pixel:BAAALgADCgkJDQAAAA==.',
Pr='Proselyte:BAABLgAECn8hAAIGAAgJlx1oBQBEAgAGAAgJlx1oBQBEAgAAAA==.',
Pu='Punchize:BAABLgAECn8UAAIWAAYJSR9yDgCnAQAWAAYJSR9yDgCnAQAAAA==.Punchlocks:BAAALgADCgYJBgAAAA==.',
Ra='Rakrak:BAAALgADCgEJAQAAAA==.Rani:BAAALgADCgUJBQAAAA==.Rathon:BAAALgAECgMJAwABLgAECgQJBwAQAAAAAA==.',
Re='Remote:BAAALgADCggJHQAAAA==.',
Ri='Rianis:BAAALgADCgcJEAAAAA==.Rilea:BAAALgAECgYJCwAAAA==.',
['Rä']='Räiyu:BAAALgADCgMJAwAAAA==.',
Sa='Sadgasm:BAABLgAECn8aAAIXAAcJjR3XAwABAgAXAAcJjR3XAwABAgAAAA==.Safeword:BAAALgAECgkJCwAAAA==.Sauron:BAAALgAECgMJBQAAAA==.',
Se='Sebrine:BAAALgAECgUJCwAAAA==.Seishan:BAACLgAFFH8FAAMBAAUJRw/gEQC6AAABAAQJHRHgEQC6AAAYAAEJwgmUBwBVAAAuAAQKfxwAAxgABwmTGyoHAPQBABgABgnVHioHAPQBAAEABQlRFkk9ADIBAAAA.Seneca:BAAALgAECgEJBAAAAA==.',
Sh='Shadowtalon:BAAALgADCgEJAQAAAA==.Shamandrea:BAAALgAECgYJBgAAAA==.Shzam:BAAALgADCgMJAwAAAA==.',
Sl='Slam:BAAALgADCgMJBQAAAA==.Sleipner:BAABLgAECn8cAAIZAAgJSQ+4DAA0AQAZAAgJSQ+4DAA0AQAAAA==.',
Sm='Smiley:BAAALgADCgYJBgAAAA==.',
Sn='Snugglehex:BAAALgADCgEJAQAAAA==.',
So='Socktrout:BAABLgAECn8jAAQaAAkJ6BQvIwClAQAaAAgJ6BQvIwClAQAbAAMJ3QoQQwCpAAAcAAEJAAA+OAAZAAAAAA==.Softgrizzly:BAAALgADCgMJAwAAAA==.Solidgold:BAACLgAFFH8PAAMUAAYJ+BfLBACoAQAUAAYJ+BfLBACoAQATAAEJnwazCwBTAAAuAAQKfyQAAxQACAlYJEYJABgDABQACAkxI0YJABgDABMABQmnIKUMANYBAAAA.Solvane:BAAALgAECgMJAwABLgAFFAUJBQABAEcPAA==.',
Sp='Spongeybob:BAAALgADCgEJAQAAAA==.',
Ss='Sscrubbucket:BAAALgAECgYJBgAAAA==.',
Su='Sunrise:BAAALgADCgkJEAAAAA==.',
Sy='Syllassa:BAAALgAECgkJAQAAAA==.Sylv:BAAALgADCgQJBgAAAA==.',
Ta='Taelia:BAACLgAFFH8FAAIHAAMJmQqPPQDYAAAHAAMJmQqPPQDYAAAuAAQKfy0AAgcACQl0HfMGAK8CAAcACQl0HfMGAK8CAAAA.Tahine:BAAALgAECgYJCQAAAA==.Tans:BAAALgADCgkJCwAAAA==.',
Ti='Tiktoks:BAAALgADCgkJEQABLgAECggJKAAOAO8ZAA==.Timetwoflame:BAAALgAECgUJDwAAAA==.',
Tn='Tnarg:BAAALgADCgIJAgAAAA==.',
To='Tokki:BAAALgAECgYJBwAAAA==.',
Tr='Trekvis:BAAALgADCgcJDgAAAA==.',
['Tû']='Tûâny:BAAALgADCgkJDgAAAA==.',
Up='Upphoria:BAAALgAECgUJDwAAAA==.',
Ur='Urkel:BAAALgADCgIJAgAAAA==.',
Vi='Viccan:BAABLgAECn8aAAIbAAcJoAaRDgDDAAAbAAcJoAaRDgDDAAAAAA==.',
Wa='Walkingtanko:BAAALgADCgIJAgAAAA==.Wavés:BAAALgADCgIJAgAAAA==.',
We='Wef:BAAALgADCgUJBQAAAA==.',
Wi='Willowleaf:BAAALgAECgEJAQABLgAECgYJBgAQAAAAAA==.',
Wo='Wolffie:BAAALgAECgcJCwAAAA==.',
Wu='Wushuu:BAAALgAECgQJBAABLgAFFAQJBQAFAEIKAA==.',
Xe='Xernaeus:BAAALgADCgQJBAAAAA==.',
Ya='Yahwëh:BAAALgAECgMJBAAAAA==.',
Yo='Yodason:BAAALgADCgQJBQAAAA==.',
Yu='Yuukï:BAABLgAECn8aAAMGAAcJOxmjIADRAQAGAAYJoB2jIADRAQAdAAMJ5QT5OgBWAAAAAA==.',
Za='Zaelyse:BAAALgADCgMJAwAAAA==.Zaton:BAABLgAECn8WAAIFAAcJMxK3OwB7AQAFAAcJMxK3OwB7AQAAAA==.',
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

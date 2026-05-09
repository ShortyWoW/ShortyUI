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

local lookup = {'Unknown-Unknown','Warlock-Demonology','Warlock-Affliction','DemonHunter-Devourer','Evoker-Preservation','Paladin-Retribution','Monk-Windwalker','Mage-Frost','Shaman-Elemental','Shaman-Restoration','Priest-Shadow','Monk-Mistweaver','Priest-Discipline','Hunter-Marksmanship','DemonHunter-Vengeance','Evoker-Augmentation','Warrior-Fury','Hunter-BeastMastery','Evoker-Devastation','Shaman-Enhancement','Paladin-Holy','Rogue-Subtlety','Druid-Feral','Rogue-Outlaw','Priest-Holy','Mage-Arcane','Warlock-Destruction','DeathKnight-Unholy','Rogue-Assassination','Paladin-Protection','Monk-Brewmaster',}
local provider = {region='US',realm='Andorhal',name='US',type='weekly',zone=46,date='2026-05-08',data={Ad='Adelyne:BAAALgAECgMJAwABLgAECgQJCAABAAAAAA==.Adorablepine:BAABLgAECn8ZAAMCAAcJuAMAdQDfAAACAAcJrAMAdQDfAAADAAEJqgP4GQAmAAAAAA==.',
Ag='Agaze:BAACLgAFFH8QAAIEAAYJGCB1CgCGAQAEAAYJGCB1CgCGAQAuAAQKfxYAAgQACAkTIv0YAL8CAAQACAkTIv0YAL8CAAAA.',
Ai='Aiedel:BAAALgAECgQJCAAAAA==.',
Al='Allesa:BAAALgAECgEJAQAAAA==.',
Ao='Aoise:BAAALgAECgkJBwAAAA==.',
Ap='Applejuuice:BAAALgAFFAMJAwABLgAECggJFwAFAMUSAA==.',
Ar='Archblade:BAAALgADCgMJBAAAAA==.Arelith:BAAALgAECgMJBwAAAA==.Arlen:BAABLgAECn8XAAIGAAcJXBO2RAB3AQAGAAcJXBO2RAB3AQAAAA==.Arma:BAABLgAECn8cAAIHAAgJjiNFBQAwAwAHAAgJjiNFBQAwAwAAAA==.Armadro:BAABLgAFFH8IAAIIAAQJ6BZYGwB1AQAIAAQJ6BZYGwB1AQAAAA==.',
Au='Aurky:BAAALgAECgEJAwAAAA==.',
Ba='Bald:BAAALgADCgYJBgAAAA==.Balob:BAACLgAFFH8WAAMJAAYJfR4vBgB4AQAJAAUJBiAvBgB4AQAKAAEJvwJRPwBCAAAuAAQKfyIAAgkACAlqJXoEAFQDAAkACAlqJXoEAFQDAAAA.Bandar:BAAALgADCgcJBwAAAA==.',
Be='Bellafists:BAAALgAECgYJBgAAAA==.',
Bl='Blacksteve:BAAALgAECgIJAgAAAA==.Bloodngore:BAAALgAECggJEAAAAA==.',
Bm='Bmxdh:BAAALgAECgYJDwAAAA==.',
Br='Broku:BAAALgAECgEJAQABLgAECggJKQAGAHoVAA==.Brudah:BAAALgAECgEJAQAAAA==.',
Bu='Bubblelove:BAABLgAECn8VAAILAAgJHQzeGQBtAQALAAgJHQzeGQBtAQAAAA==.Bubbly:BAABLgAECn8pAAIGAAgJehWCOACdAQAGAAgJehWCOACdAQAAAA==.',
Ca='Caelum:BAAALgAECgMJAwAAAA==.Callmepappy:BAAALgADCgUJBQAAAA==.Canníbal:BAAALgAECggJDwAAAA==.',
Ce='Censored:BAAALgADCgIJAgAAAA==.',
Ch='Chopsy:BAABLgAECn9GAAMHAAkJGCTIAABVAwAHAAkJGCTIAABVAwAMAAIJxAvbXgBSAAAAAA==.Chris:BAAALgAECgUJCQAAAA==.Chucklez:BAAALgADCgMJAwAAAA==.Chulobulo:BAAALgAFFAIJAgAAAA==.Chulosdck:BAAALgAECgQJBAABLgAFFAIJAgABAAAAAA==.',
Ci='Cinnabons:BAAALgAECgYJDQABLgAECggJFwAFAMUSAA==.',
Cl='Cleopatrick:BAAALgADCgkJEAAAAA==.',
Co='Codingsocks:BAAALgADCgEJAgAAAA==.',
Cr='Crekton:BAAALgAECgMJAwAAAA==.Cronnos:BAAALgAECgYJBwAAAA==.',
Cu='Cudlemonster:BAABLgAECn8iAAINAAgJOA21FACaAQANAAgJOA21FACaAQAAAA==.Cursed:BAABLgAECn8kAAMDAAkJtB0SAgCtAgADAAkJtB0SAgCtAgACAAIJlAt7qABtAAAAAA==.',
Da='Dabz:BAAALgAECgcJEQAAAA==.Danyel:BAAALgADCgYJBwAAAA==.Darmok:BAABLgAECn81AAMKAAkJ3yMJAQCFAwAKAAkJ3yMJAQCFAwAJAAEJbBoUWQBMAAAAAA==.Darzamat:BAAALgADCgEJAQAAAA==.',
De='Demonbubble:BAACLgAFFH8LAAIEAAUJ5QkFKgAKAQAEAAUJ5QkFKgAKAQAuAAQKfyYAAgQACAn2FZMfAMsBAAQACAn2FZMfAMsBAAAA.Dezric:BAAALgADCgYJDAABLgAECgYJDQABAAAAAA==.',
Do='Dotomic:BAAALgAECgQJBQABLgAFFAcJFAAOAEkeAA==.',
Dr='Drejan:BAAALgAECgcJBwAAAA==.Drfe:BAAALgADCgYJBgAAAA==.Drowarchon:BAAALgADCgIJAgABLgAECgQJBAABAAAAAA==.Drownix:BAAALgAECgQJBAAAAA==.Drowzy:BAAALgADCgQJBAABLgAECgQJBAABAAAAAA==.',
Eb='Ebon:BAAALgADCgMJAwAAAA==.',
Ec='Ecaed:BAABLgAECn8XAAIPAAgJGAe8DAD5AAAPAAgJGAe8DAD5AAAAAA==.',
El='Elektriss:BAAALgAECgQJBAAAAA==.Elnaris:BAABLgAECn8UAAIGAAcJZgWscwAFAQAGAAcJZgWscwAFAQAAAA==.Elohime:BAAALgADCgYJCAAAAA==.',
Eo='Eon:BAAALgAECgIJBwAAAA==.',
Er='Erikkak:BAAALgADCgQJBAAAAA==.',
Fi='Fire:BAAALgAECgUJBQABLgAFFAUJFAAQAGsfAA==.',
Fr='Fragga:BAABLgAECn8VAAIRAAYJDxK4KQAuAQARAAYJDxK4KQAuAQAAAA==.',
Fu='Fullflavor:BAAALgADCgIJAgAAAA==.',
['Fü']='Füran:BAAALgADCgIJAgAAAA==.',
Ga='Ganryu:BAAALgADCgYJCgAAAA==.',
Gb='Gboybalili:BAAALgADCgcJDAAAAA==.',
Gi='Gitzi:BAABLgAECn86AAISAAkJGRosEABUAgASAAkJGRosEABUAgAAAA==.',
Gl='Glaciea:BAAALgADCgMJAwABLgAECggJHAATAKEiAA==.',
Gr='Greenrage:BAAALgADCgQJBAAAAA==.Griever:BAAALgAECgMJBAAAAA==.Grizzly:BAAALgADCgUJBQABLgAECgQJCgABAAAAAA==.Groovexgroov:BAAALgAECgcJBwAAAA==.',
He='Healrog:BAAALgADCgkJCgAAAA==.Hellraiser:BAAALgAECgMJAwAAAA==.',
Hi='Highfive:BAAALgADCgIJAgAAAA==.',
Ho='Hordend:BAAALgAECgUJEAAAAA==.Hozru:BAAALgADCgEJAQAAAA==.',
Hu='Hulkfists:BAABLgAECn8UAAMJAAYJownHSgAcAQAJAAYJownHSgAcAQAUAAYJ3gLWHgDiAAAAAA==.',
Hy='Hydration:BAAALgADCgMJAwAAAA==.',
Im='Imcepsy:BAABLgAECn8pAAINAAgJKhnvBwBjAgANAAgJKhnvBwBjAgAAAA==.',
Io='Iownzuu:BAAALgADCgMJAwAAAA==.',
Is='Istark:BAAALgAECgMJAwAAAA==.',
Ja='Jayjay:BAABLgAECn8UAAIIAAgJER7jHAA9AgAIAAgJER7jHAA9AgAAAA==.',
Je='Jethroy:BAABLgAECn8VAAIVAAgJcBFXHQCcAQAVAAgJcBFXHQCcAQAAAA==.',
Jf='Jfkwspvpfldg:BAAALgAECgYJBgAAAA==.',
Ji='Jimmie:BAABLgAECn8aAAIWAAgJuiAiEQCYAgAWAAgJuiAiEQCYAgAAAA==.',
Jo='Johnparstina:BAAALgAECgYJCgAAAA==.Jolty:BAACLgAFFH8GAAIUAAIJDSWkBQDfAAAUAAIJDSWkBQDfAAAuAAQKfxgAAhQACQkRHcEDAO4CABQACQkRHcEDAO4CAAAA.',
Jr='Jrbacnchee:BAAALgAECgEJAQAAAA==.Jrbcncheze:BAAALgAECggJEgAAAA==.',
Ka='Kainicus:BAABLgAECn82AAIPAAkJqxXBAwAHAgAPAAkJqxXBAwAHAgAAAA==.Kainigal:BAAALgADCgYJCwAAAA==.Kainisham:BAAALgADCgcJBwAAAA==.',
Ke='Kelador:BAABLgAECn8WAAIXAAYJeAUXFgDIAAAXAAYJeAUXFgDIAAAAAA==.Keoni:BAAALgAECgEJAQAAAA==.',
Kh='Khappucino:BAAALgAECgYJCAAAAA==.Kharibou:BAAALgAECgIJAgAAAA==.Khellendros:BAAALgADCgYJCgAAAA==.Khrism:BAAALgADCgQJBAAAAA==.',
Ki='Kibbi:BAAALgADCgcJBwAAAA==.Kitsyune:BAABLgAECn8fAAIYAAkJ6hfJAQBBAgAYAAkJ6hfJAQBBAgAAAA==.',
Kl='Kløey:BAAALgAECgYJEAAAAA==.',
La='Laethys:BAAALgADCggJCAABLgAECgkJIQAIADkeAA==.',
Li='Lithini:BAAALgAECgEJAQAAAA==.',
Lo='Lowtech:BAAALgAECgMJAwAAAA==.',
Lu='Luminusrayne:BAABLgAECn83AAMNAAkJWQ0AIgCEAQANAAgJ/AoAIgCEAQAZAAUJCwx4KwDxAAAAAA==.Lussypipz:BAAALgAECgUJCwAAAA==.',
Ma='Mahwe:BAAALgAECggJDAAAAA==.Manafest:BAAALgAECgMJCgAAAA==.Maros:BAABLgAECn8VAAMIAAgJ4xDlPwCoAQAIAAgJ4xDlPwCoAQAaAAEJJA/uDAA/AAAAAA==.',
Me='Meheret:BAABLgAECn8yAAIIAAkJ1gTAVwBmAQAIAAkJ1gTAVwBmAQAAAA==.Melissenia:BAAALgAECgQJBAAAAA==.Mepha:BAAALgAECgYJCQAAAA==.',
Mi='Mint:BAABLgAECn8hAAIIAAkJOR48DQC1AgAIAAkJOR48DQC1AgAAAA==.',
Mo='Mokth:BAAALgADCgMJAwAAAA==.Mom:BAAALgAECgIJAgAAAA==.Mooby:BAABLgAECn8XAAIWAAgJhBoGCQASAgAWAAgJhBoGCQASAgAAAA==.Moonfury:BAAALgAECgEJAQAAAA==.Moonleigh:BAAALgADCgMJBAAAAA==.Morganthe:BAAALgAECgIJAwAAAA==.',
Mu='Munt:BAAALgAECgQJBAABLgAECgkJIQAIADkeAA==.',
My='Mypriiest:BAAALgAECgQJBAAAAA==.Myroguëë:BAAALgADCgUJBQAAAA==.Mystx:BAAALgAECgEJAQABLgAFFAMJBQARAOMYAA==.Mythx:BAACLgAFFH8FAAIRAAMJ4xiOFAANAQARAAMJ4xiOFAANAQAuAAQKfygAAhEACAkCId4EAK0CABEACAkCId4EAK0CAAAA.Mywarr:BAAALgADCgMJAwAAAA==.',
Na='Naturemage:BAAALgAECgUJBwAAAA==.Natâsi:BAABLgAECn8qAAIVAAgJeRaUFADsAQAVAAgJeRaUFADsAQAAAA==.',
Ne='Nerazul:BAABLgAECn8VAAQDAAYJph/HBQAKAgADAAYJph/HBQAKAgACAAMJ3wp74wCTAAAbAAEJ/AgGeAAsAAAAAA==.Netharec:BAAALgADCgEJAQAAAA==.Nevai:BAABLgAECn8UAAIVAAgJxxC/FgDYAQAVAAgJxxC/FgDYAQAAAA==.',
Ni='Nielas:BAAALgAECgcJEQAAAA==.Nihilus:BAACLgAFFH8OAAIcAAUJVheOCACMAQAcAAUJVheOCACMAQAuAAQKfxUAAhwABwkWJLIvAHkCABwABwkWJLIvAHkCAAAA.Nilari:BAAALgAECgUJCAAAAA==.Nine:BAAALgADCgYJBgABLgAECgkJRgAHABgkAA==.',
No='Noctazari:BAAALgADCgUJBQAAAA==.Noctium:BAABLgAECn8cAAITAAgJoSLkAAC7AgATAAgJoSLkAAC7AgAAAA==.Nostrildamus:BAAALgAECgYJEQABLgAECgkJFQAGAKcXAA==.',
Nz='Nzoth:BAAALgADCgYJBgAAAA==.',
Ow='Owlaf:BAAALgAECgIJAgABLgAFFAQJDQANADIaAA==.Owls:BAACLgAFFH8NAAINAAQJMhp+EABFAQANAAQJMhp+EABFAQAuAAQKfy4AAxkACQkVI/kKAJ8CABkABwkbJPkKAJ8CAA0ACQmxH60KAI0CAAEuAAUUBAkNAA0AMhoA.',
Pa='Pallywhacker:BAAALgADCgMJAwAAAA==.Panconcaca:BAAALgAFFAMJAwAAAA==.Pantsokay:BAAALgADCgEJAQAAAA==.',
Pe='Peach:BAABLgAECn8cAAMdAAgJ3Q25BQCbAQAdAAgJ3Q25BQCbAQAWAAYJUAGWSwDNAAAAAA==.Peaches:BAAALgADCgkJCQAAAA==.Petsmart:BAAALgAECgQJBQAAAA==.',
Po='Potatoeshot:BAAALgAECgQJBQAAAA==.',
Pr='Praisethesun:BAAALgAECgQJCQAAAA==.Prayxx:BAAALgAECgYJCQAAAA==.Pretzel:BAACLgAFFH8FAAIcAAMJ4xo9QwAIAQAcAAMJ4xo9QwAIAQAuAAQKfysAAhwACQlAJZ4EAIoDABwACQlAJZ4EAIoDAAAA.Proved:BAABLgAECn87AAIZAAgJlh94BQCtAgAZAAgJlh94BQCtAgAAAA==.',
Ps='Psillycybin:BAAALgAECgcJCQAAAA==.',
Pu='Puddingface:BAAALgADCgkJCQAAAA==.Puggar:BAAALgADCgQJBgAAAA==.Pumpspotter:BAAALgAECgkJEgAAAA==.',
Qu='Quiescence:BAAALgADCgYJBgAAAA==.',
Ra='Ranas:BAAALgADCgIJAgAAAA==.Ratlemebonez:BAAALgAECgEJAQAAAA==.Ravèn:BAAALgAECgYJDAAAAA==.Rayana:BAAALgADCgYJBgAAAA==.Razeal:BAAALgAECgYJDwAAAA==.',
Re='Rene:BAEALgAECgYJCAAAAA==.Rev:BAAALgADCgEJAQAAAA==.',
Rh='Rhysan:BAABLgAECn8sAAIKAAkJBxP8GwDRAQAKAAkJBxP8GwDRAQAAAA==.Rhyuk:BAAALgADCgQJBAAAAA==.',
Ri='Ristria:BAAALgADCgYJDAABLgAECgQJDwABAAAAAA==.Rizy:BAABLgAECn8WAAIcAAgJ8g11PACJAQAcAAgJ8g11PACJAQAAAA==.',
Ro='Robonord:BAAALgAECgIJAgAAAA==.Rokki:BAAALgADCgIJAgAAAA==.',
Ru='Rude:BAAALgADCgcJCwAAAA==.',
Ry='Rynhart:BAAALgADCgUJBQAAAA==.Ryushi:BAABLgAECn85AAIEAAkJbiCzAwD/AgAEAAkJbiCzAwD/AgAAAA==.',
Sa='Sacerdote:BAABLgAECn8UAAICAAYJPiF1IQDpAQACAAYJPiF1IQDpAQAAAA==.Sakari:BAAALgADCgcJEAAAAA==.Sandara:BAAALgADCgYJBgAAAA==.Sangre:BAAALgADCgIJAgAAAA==.Sarasara:BAAALgADCgUJBQAAAA==.',
Sc='Scoots:BAAALgAECgUJBwABLgAECgkJRgAHABgkAA==.Scratster:BAAALgAECgcJCAAAAA==.',
Se='Sebnoth:BAABLgAECn8kAAIcAAgJzxtGFgBJAgAcAAgJzxtGFgBJAgAAAA==.',
Sh='Shalashaska:BAAALgADCgEJAQAAAA==.Shamantastik:BAAALgAECgMJAwAAAA==.Shiden:BAAALgAECgIJAwAAAA==.Shiift:BAAALgADCgYJBwAAAA==.Shockblocked:BAAALgADCgQJBAAAAA==.',
Si='Sideburn:BAAALgADCgUJBQAAAA==.Sidepiece:BAAALgADCgcJCAAAAA==.Sillyderek:BAABLgAECn8UAAIeAAcJvQzzFAD6AAAeAAcJvQzzFAD6AAAAAA==.',
Sl='Slashology:BAAALgAECgYJBgAAAA==.',
Sm='Smallpally:BAAALgAECgQJCAAAAA==.',
So='Soarsha:BAAALgAECgEJAQAAAA==.Solarida:BAABLgAECn8YAAIGAAcJpBYtOQCbAQAGAAcJpBYtOQCbAQAAAA==.',
Sr='Srsawyer:BAABLgAECn8bAAICAAgJRg9XPgBwAQACAAgJRg9XPgBwAQAAAA==.',
St='Staralfur:BAAALgADCgcJBwAAAA==.Stevokerjobs:BAAALgAFFAEJAQAAAA==.Stratos:BAAALgADCgcJBwAAAA==.',
Su='Sunwa:BAAALgAECgYJDwABLgAFFAMJBQARAOMYAA==.',
['Sï']='Sïmba:BAAALgAECgMJCQAAAA==.',
Te='Terzhull:BAAALgADCgIJAgAAAA==.',
Th='Thepride:BAAALgAECggJDwAAAA==.',
Ti='Timmytim:BAAALgAECgQJCAAAAA==.Tired:BAAALgAECgUJBgAAAA==.',
To='Tool:BAACLgAFFH8ZAAIIAAgJHBu/AADdAgAIAAgJHBu/AADdAgAuAAQKfyYAAggACQnrJGUCANgDAAgACQnrJGUCANgDAAAA.Touchi:BAAALgAECgEJAgABLgAECggJHAAXAHIaAA==.',
Tr='Troljin:BAAALgADCgEJAQAAAA==.',
Tu='Tuo:BAABLgAECn8cAAIXAAgJchrRBAAWAgAXAAgJchrRBAAWAgAAAA==.Turbid:BAABLgAECn8fAAIEAAgJjxPGKACXAQAEAAgJjxPGKACXAQAAAA==.',
Ty='Ty:BAAALgAECgUJDAAAAA==.Tytank:BAAALgADCgMJAwAAAA==.',
Uh='Uhavemyrice:BAAALgADCgIJAgAAAA==.',
Ve='Velkin:BAAALgAECgEJAQAAAA==.',
Vi='Vivia:BAAALgADCgQJBAAAAA==.Viviann:BAAALgADCgMJAwAAAA==.Vivians:BAAALgADCggJCgAAAA==.',
Vo='Voutecomer:BAAALgADCgYJCAAAAA==.',
Wa='Walls:BAABLgAECn8VAAIGAAkJpxc5FABYAgAGAAkJpxc5FABYAgAAAA==.Warrach:BAAALgADCgQJBAAAAA==.',
We='Wennoe:BAAALgADCgIJAgAAAA==.Westirras:BAAALgAECgUJCQAAAA==.',
Yo='Yogurt:BAAALgAECgYJCAABLgAECggJKQAGAHoVAA==.',
Yu='Yusuke:BAABLgAECn8WAAMfAAcJWxFOFgCGAQAfAAcJWxFOFgCGAQAMAAYJPQlvQADgAAABLgAECggJEAABAAAAAA==.',
Za='Zazabandit:BAAALgADCgUJBQAAAA==.',
Zo='Zolleta:BAAALgAECgQJBAAAAA==.',
Zu='Zunden:BAAALgAECgYJCwAAAA==.',
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

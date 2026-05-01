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

local lookup = {'DemonHunter-Devourer','Paladin-Retribution','DeathKnight-Unholy','Mage-Frost','Shaman-Restoration','Druid-Feral','Shaman-Elemental','Warlock-Demonology','Warlock-Destruction','Warlock-Affliction','Evoker-Preservation','Druid-Restoration','Unknown-Unknown','Mage-Arcane','Hunter-Marksmanship','Priest-Holy','Priest-Shadow','Druid-Balance','Shaman-Enhancement','Priest-Discipline','Hunter-Survival','Hunter-BeastMastery','Monk-Windwalker','Monk-Brewmaster','Evoker-Augmentation','Evoker-Devastation','Warrior-Protection','Rogue-Subtlety','Monk-Mistweaver','Paladin-Holy',}
local provider = {region='US',realm="Anub'arak",name='US',type='weekly',zone=46,date='2026-05-01',data={Ad='Adrestia:BAEALgAECgcJBwAAAA==.',
Ae='Aerglo:BAAALgAECgYJCgAAAA==.',
Al='Alidruid:BAAALgAECgQJBQAAAA==.',
An='Analog:BAAALgAECgYJEQAAAA==.Andromaelis:BAAALgAECgYJCwAAAA==.Angelo:BAAALgADCgUJBQAAAA==.',
Ar='Aremís:BAAALgAECgUJBQAAAA==.Arttes:BAAALgADCggJEAAAAA==.',
As='Asheda:BAAALgAECgEJBAAAAA==.Astraldoge:BAAALgAECgYJEQAAAA==.Astraldogeh:BAAALgAECgQJBAAAAA==.',
At='Atom:BAAALgAECgMJAwAAAA==.',
Az='Azshanal:BAABLgAECn8bAAIBAAgJDCAEBwBrAgABAAgJDCAEBwBrAgAAAA==.',
Ba='Banana:BAAALgADCgUJBQAAAA==.',
Bi='Biggsthebold:BAABLgAECn8dAAICAAcJiCQ8IQCmAgACAAcJiCQ8IQCmAgAAAA==.Biggsthevast:BAAALgAECgEJAQABLgAECgcJHQACAIgkAA==.Bix:BAAALgADCgUJBQAAAA==.',
Bl='Bloodmight:BAAALgAECgYJCgAAAA==.',
Br='Brewhousee:BAAALgAECgEJAgAAAA==.Bronwyn:BAAALgAECgQJBQAAAA==.Brruno:BAAALgAECgQJCwAAAA==.',
Bu='Bungus:BAABLgAECn8bAAIDAAgJcCC+CACTAgADAAgJcCC+CACTAgAAAA==.Bupropion:BAAALgADCgMJAwAAAA==.Buttermane:BAAALgADCgUJBgAAAA==.',
Ca='Caps:BAAALgAECgYJCAAAAA==.Cassa:BAAALgAECgIJBAAAAA==.Castor:BAABLgAECn8VAAIEAAYJLBsRwQBiAQAEAAYJLBsRwQBiAQAAAA==.Castroff:BAAALgAFFAIJAgAAAA==.',
Ch='Chamuskin:BAABLgAECn8lAAIFAAgJXR4PBQCnAgAFAAgJXR4PBQCnAgAAAA==.Cherovski:BAAALgADCgIJAgAAAA==.Chimuelo:BAAALgADCgcJDwAAAA==.Chravis:BAABLgAECn8YAAIGAAgJ8RTjCwD/AQAGAAgJ8RTjCwD/AQAAAA==.',
Ck='Ckonquer:BAABLgAFFH8HAAIHAAMJfhLrEAD3AAAHAAMJfhLrEAD3AAAAAA==.',
Cr='Crazytaco:BAAALgADCgYJCAAAAA==.',
Cu='Cursewords:BAABLgAFFH8GAAMIAAUJyQbrMQDfAAAIAAQJ/gjrMQDfAAAJAAEJKwDwEQAPAAAAAA==.',
Cz='Czaedyn:BAABLgAECn8jAAIJAAgJUxAwBQB5AQAJAAgJUxAwBQB5AQAAAA==.',
['Cá']='Cátáclïsmíc:BAAALgAECgEJAQABLgAECgcJFQAFAMYEAA==.',
Da='Damari:BAAALgAECgIJAgAAAA==.Daslock:BAAALgADCgEJAQAAAA==.Dastickle:BAAALgADCgIJAgAAAA==.Davrazpp:BAAALgADCgYJDQAAAA==.',
De='Deathful:BAABLgAECn8XAAMIAAcJ4Rh2RAD+AQAIAAcJ4Rh2RAD+AQAKAAEJAAALLQBEAAAAAA==.Deathkano:BAAALgADCgMJBgAAAA==.Dellea:BAAALgADCgkJFgAAAA==.Depemonkimab:BAAALgADCgQJBAAAAA==.Derpcat:BAAALgAECgcJDAAAAA==.Dervish:BAABLgAECn8bAAILAAgJlgqJCgBuAQALAAgJlgqJCgBuAQAAAA==.Deuceretro:BAAALgADCgMJAwAAAA==.',
Di='Dingoatemybb:BAAALgADCgcJEgAAAA==.Dizana:BAAALgAECgMJBAAAAA==.',
Dk='Dkxd:BAABLgAECn8cAAIMAAgJPCGjDADYAgAMAAgJPCGjDADYAgAAAA==.',
Do='Dogwater:BAAALgADCgEJAQAAAA==.Doomcow:BAAALgAECgUJEwAAAA==.',
Dr='Dreadful:BAAALgADCgMJAwAAAA==.',
Dy='Dysis:BAAALgAECgYJBwAAAA==.',
Eb='Eblocked:BAAALgADCgkJDgAAAA==.',
El='Elyoen:BAAALgADCgEJAQAAAA==.',
Em='Emeline:BAAALgAECgEJAQABLgAECgYJGAAEAFgQAA==.',
Ev='Evi:BAAALgADCgcJBwAAAA==.Evokemynuts:BAAALgAECgYJBwAAAA==.',
Ew='Ewok:BAAALgADCgkJEQAAAA==.',
Fa='Faelar:BAAALgAECgQJBAAAAA==.',
Fe='Fellek:BAAALgAECgIJAQAAAA==.',
Fi='Fizzybubblah:BAAALgADCgUJCQAAAA==.',
Fr='Frostpimp:BAACLgAFFH8FAAIEAAMJOg39NQD6AAAEAAMJOg39NQD6AAAuAAQKfyMAAgQABwlsH/QgAOgBAAQABwlsH/QgAOgBAAAA.',
Ge='Gertrude:BAAALgADCgYJBwAAAA==.',
Go='Goldencalves:BAAALgADCgQJBAAAAA==.Goldrinn:BAAALgADCgYJCAAAAA==.',
Gr='Greasemonkèy:BAABLgAECn8VAAIFAAcJxgSDZgD1AAAFAAcJxgSDZgD1AAAAAA==.Greasemonkéy:BAAALgADCgYJBwAAAA==.Griselda:BAAALgAECgEJAQAAAA==.Grow:BAAALgADCgYJBgAAAA==.',
He='Healistraza:BAAALgAECggJEgAAAA==.Heavyroller:BAAALgAECgEJAQAAAA==.Help:BAAALgAECgYJBgABLgAECggJEgANAAAAAA==.Hesha:BAAALgADCgMJAQAAAA==.',
Ho='Hockey:BAABLgAECn8YAAIOAAcJZiQfAQDgAgAOAAcJZiQfAQDgAgAAAA==.Hotten:BAAALgAECgYJDAAAAA==.',
Hr='Hruid:BAAALgADCgYJBgAAAA==.',
Hu='Hu:BAAALgADCgUJBQAAAA==.Humâ:BAAALgADCgcJFwAAAA==.',
['Hú']='Húe:BAAALgADCgUJBgAAAA==.',
Ic='Ickrest:BAAALgAECgIJAgAAAA==.',
Il='Illil:BAAALgAECggJEAAAAA==.',
Ja='Jackherer:BAAALgAECgUJCgAAAA==.',
Je='Jehuty:BAAALgADCgQJBwAAAA==.',
Jo='Jordok:BAAALgAECgYJEgAAAA==.',
Ka='Kalmea:BAAALgAECgQJBgAAAA==.Kaoru:BAABLgAECn8aAAIPAAgJtw+0BQCcAQAPAAgJtw+0BQCcAQAAAA==.',
Kh='Khayserxd:BAAALgAECgQJBwAAAA==.',
Ki='Kittenhealer:BAAALgAECggJAwAAAA==.',
Ko='Korwynn:BAAALgADCggJDQAAAA==.',
Kr='Krodork:BAAALgAECgEJAQAAAA==.Krucal:BAABLgAECn8dAAMJAAcJORHgIQBHAQAIAAYJVxPROABKAQAJAAYJfgzgIQBHAQAAAA==.',
La='Lamar:BAAALgAECgYJDgAAAA==.Lark:BAABLgAECn8dAAMQAAcJuBQZNABuAQAQAAYJkxQZNABuAQARAAcJqh2IGQAyAQAAAA==.',
Le='Legendabloka:BAAALgAECgIJAgAAAA==.',
Li='Life:BAAALgADCgQJBAAAAA==.Lifedeclined:BAAALgAECgcJBwAAAA==.Lifegiver:BAABLgAECn8WAAMMAAgJWRjEEQD+AQAMAAgJWRjEEQD+AQASAAMJZSFGRQAZAQAAAA==.Listyn:BAACLgAFFH8GAAIMAAMJwgKsGgCSAAAMAAMJwgKsGgCSAAAuAAQKfxkAAgwABwm0D1AlAFoBAAwABwm0D1AlAFoBAAAA.Litvyak:BAAALgADCgYJCgAAAA==.',
Lo='Lolly:BAAALgAECggJEQAAAA==.',
Lu='Luordkhan:BAAALgADCgEJAQAAAA==.',
Ma='Magegodkaren:BAAALgAECgEJAQAAAA==.Maluban:BAAALgAECgYJDAAAAA==.Mandan:BAABLgAECn8UAAITAAgJohTKDAD2AQATAAgJohTKDAD2AQAAAA==.Mart:BAACLgAFFH8IAAILAAQJMh5uCABRAQALAAQJMh5uCABRAQAuAAQKfycAAgsACAkIH+oMAGcCAAsACAkIH+oMAGcCAAAA.Marwynne:BAAALgAECgYJEgAAAA==.Mayday:BAAALgADCgEJAQAAAA==.',
Mi='Miyafuji:BAABLgAECn8bAAMQAAgJsyI9BACRAgAQAAgJjSI9BACRAgAUAAYJ1R7YEwAOAgAAAA==.',
Mo='Moonwell:BAACLgAFFH8FAAIMAAMJmSLfDQAyAQAMAAMJmSLfDQAyAQAuAAQKfyEAAgwACAnXJA4CAD4DAAwACAnXJA4CAD4DAAAA.',
Mu='Mug:BAAALgADCggJEAAAAA==.',
Mv='Mvp:BAACLgAFFH8MAAIVAAQJhiAMAgCEAQAVAAQJhiAMAgCEAQAuAAQKfyUABBUACAlWIqIEAMsCABUACAlWIqIEAMsCAA8ABAmdDzhiALcAABYAAQk/FbjRADQAAAAA.',
['Mí']='Míriel:BAAALgAECgEJAQAAAA==.',
Na='Naguurafan:BAAALgAFFAEJAgABLgAECgkJEAANAAAAAA==.',
No='Nologic:BAAALgAECgMJAwAAAA==.',
Nu='Nutprepared:BAAALgAECgkJEAAAAA==.',
Ny='Nyxie:BAAALgAECgUJCQAAAA==.',
Oa='Oaknock:BAAALgAECgQJBgABLgAECgcJGAAOAGYkAA==.',
Ob='Obwand:BAAALgADCgMJAgAAAA==.',
Ou='Outfirenyou:BAAALgADCgEJAQAAAA==.',
Pa='Painter:BAAALgAECgYJDgAAAA==.Palanthir:BAABLgAECn8hAAICAAgJZB7hDgBJAgACAAgJZB7hDgBJAgAAAA==.Pandapve:BAACLgAFFH8IAAMXAAMJUBLRCwDlAAAXAAMJUBLRCwDlAAAYAAEJ4wZzMAA9AAAuAAQKfyUAAxcACAkLIakDAIECABcACAkLIakDAIECABgABQkCEFxQAAIBAAAA.',
Pe='Peja:BAAALgAECgUJDQAAAA==.Pelan:BAAALgADCgIJAgABLgAECggJEgANAAAAAA==.',
Ph='Phu:BAACLgAFFH8LAAISAAQJdBd2DQAJAQASAAQJdBd2DQAJAQAuAAQKfyUAAhIACAlMJF8FAEgDABIACAlMJF8FAEgDAAAA.',
Po='Pockthelock:BAAALgAECgUJDQAAAA==.',
Pu='Puds:BAAALgADCgYJCwABLgAECgUJCgANAAAAAA==.',
Qu='Quanche:BAAALgADCgcJCgAAAA==.Quanchii:BAAALgAECgEJAQAAAA==.',
Ra='Raanth:BAABLgAECn8jAAIIAAgJKBbYHgC7AQAIAAgJKBbYHgC7AQAAAA==.Rampant:BAAALgAECgQJBAAAAA==.Randune:BAAALgAECgYJDQAAAA==.Ravioli:BAABLgAECn8bAAIYAAgJrSPpAQDSAgAYAAgJrSPpAQDSAgABLgAECgcJGAAOAGYkAA==.Ravyn:BAAALgADCgUJAwAAAA==.Ray:BAABLgAECn8cAAMEAAgJoA08NgCNAQAEAAgJoA08NgCNAQAOAAIJOQT9GABQAAAAAA==.Rayliee:BAAALgADCgMJAwABLgAECggJHAAEAKANAA==.',
Rh='Rhyssa:BAABLgAECn8WAAIXAAYJkiBFGgAOAgAXAAYJkiBFGgAOAgAAAA==.',
Ro='Roided:BAAALgADCgkJEAAAAA==.Rokkstedy:BAAALgAECgIJAgAAAA==.',
Ry='Ryukan:BAABLgAECn8UAAICAAgJtBZERQAUAgACAAgJtBZERQAUAgAAAA==.',
Sa='Sadiegrace:BAAALgADCgIJAgAAAA==.Saint:BAAALgAECgcJEwAAAA==.Saintfrancis:BAABLgAECn8bAAQQAAcJxAuhPgA/AQAQAAcJxAuhPgA/AQARAAQJMgExWgBQAAAUAAIJ6wFkUQBGAAAAAA==.Sairae:BAAALgADCgIJAgAAAA==.Saucey:BAAALgAECgMJAwAAAA==.',
Sc='Scales:BAABLgAECn8jAAMZAAgJVgx2EwBoAQAZAAgJVgx2EwBoAQAaAAUJwwETMACWAAAAAA==.',
Se='Sempii:BAAALgAECgUJCAAAAA==.Serarlan:BAAALgAECgEJAwAAAA==.',
Sh='Sheve:BAAALgADCgIJAgABLgAECgUJCgANAAAAAA==.Shiine:BAAALgADCgUJBQAAAA==.Shädöw:BAAALgAECgcJBgAAAA==.',
Si='Sinist:BAAALgAECgYJBwAAAA==.Sinisteros:BAAALgAECgQJAwAAAA==.',
Sk='Skeletron:BAAALgADCgEJAQAAAA==.Skull:BAAALgAECgMJBAAAAA==.',
Sl='Slager:BAAALgAECgMJAwAAAA==.Slagr:BAABLgAECn8bAAIbAAcJ2CB+CQCDAgAbAAcJ2CB+CQCDAgAAAA==.Slightcoyote:BAAALgAECgYJCQAAAA==.',
Sm='Smokeyh:BAACLgAFFH8IAAIYAAIJTR1kGwDBAAAYAAIJTR1kGwDBAAAuAAQKfzgAAhgACAm7IiACAMgCABgACAm7IiACAMgCAAAA.',
Sn='Snow:BAABLgAECn8XAAIcAAcJFhtZFwBQAgAcAAcJFhtZFwBQAgAAAA==.',
So='Sonnytyphoon:BAAALgAECgYJEQAAAA==.',
St='Strongtoast:BAAALgAECgQJBQAAAA==.Strónghamer:BAAALgAECgIJAwAAAA==.',
Ta='Ta:BAAALgADCgEJAQAAAA==.Taepo:BAAALgADCgIJAgAAAA==.',
Te='Terranda:BAAALgAECgIJAwAAAA==.',
Th='Thonor:BAABLgAECn8XAAIIAAYJVRT2OwA/AQAIAAYJVRT2OwA/AQAAAA==.Thuglar:BAAALgAECgYJDgAAAA==.',
Ti='Tikitickler:BAAALgADCggJCwAAAA==.',
Tl='Tlab:BAAALgAECgcJEQAAAA==.',
To='Torí:BAABLgAECn8WAAICAAcJKwqwowA5AQACAAcJKwqwowA5AQAAAA==.Totemmygotem:BAAALgADCgUJBQAAAA==.',
Tr='Tryla:BAAALgADCgkJCwAAAA==.',
Va='Vaelandir:BAAALgAECgMJAwAAAA==.Vallkyr:BAABLgAECn8gAAIEAAkJhh4QCQCsAgAEAAkJhh4QCQCsAgAAAA==.',
Ve='Vexahlia:BAABLgAECn8UAAIWAAgJ7w70OQDHAQAWAAgJ7w70OQDHAQAAAA==.',
Vi='Vivix:BAAALgADCgMJAwAAAA==.',
Vp='Vpj:BAAALgAECgEJAQAAAA==.',
Vy='Vyndord:BAAALgAECgEJAQAAAA==.Vyz:BAAALgADCgEJAQAAAA==.',
Wa='Wastemgmnt:BAAALgAECgYJDAAAAA==.',
Wi='Wildshifter:BAAALgADCgYJBwAAAA==.',
Xe='Xeriaah:BAAALgAECgEJAQAAAA==.',
Za='Zarivia:BAAALgADCgcJCwAAAA==.',
Ze='Zerfatar:BAAALgADCgcJDQAAAA==.',
Zi='Zinjari:BAAALgAECgYJEAAAAA==.Zitta:BAABLgAECn8eAAIdAAgJYhV3FwAEAgAdAAgJYhV3FwAEAgAAAA==.Zittav:BAABLgAECn8VAAMeAAkJaBlmGwA5AgAeAAkJaBlmGwA5AgACAAYJhB6cIADHAQAAAA==.',
Zo='Zombie:BAAALgADCgEJAQAAAA==.Zooknock:BAAALgADCgUJCAABLgAECgcJGAAOAGYkAA==.Zov:BAAALgAECgYJDQAAAA==.',
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

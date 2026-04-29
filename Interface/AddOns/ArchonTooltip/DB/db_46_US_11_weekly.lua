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

local lookup = {'DemonHunter-Devourer','Unknown-Unknown','Monk-Windwalker','Shaman-Elemental','Paladin-Retribution','Monk-Mistweaver','Warlock-Affliction','Shaman-Restoration','Hunter-Marksmanship','Hunter-BeastMastery','Evoker-Devastation','Shaman-Enhancement','Priest-Discipline','Rogue-Subtlety','DemonHunter-Vengeance','Rogue-Outlaw','Mage-Frost','Priest-Holy','Warrior-Fury','Paladin-Holy','Warlock-Demonology','Warlock-Destruction','DeathKnight-Unholy','Rogue-Assassination','Monk-Brewmaster',}
local provider = {region='US',realm='Andorhal',name='US',type='weekly',zone=46,date='2026-04-24',data={Ad='Adelyne:BAAALgAECgMJAwAAAA==.Adorablepine:BAAALgAECgYJCwAAAA==.',
Ag='Agaze:BAACLgAFFH8KAAIBAAUJRR9xCgCGAQABAAUJRR9xCgCGAQAuAAQKfxkAAgEACAkTIv0YAL8CAAEACAkTIv0YAL8CAAAA.',
Ai='Aiedel:BAAALgAECgQJBQAAAA==.',
Al='Allesa:BAAALgAECgEJAQAAAA==.',
Ao='Aoise:BAAALgAECgkJBAAAAA==.',
Ap='Applejuuice:BAAALgADCgUJBQABLgAFFAEJAQACAAAAAA==.',
Ar='Archblade:BAAALgADCgEJAQAAAA==.Arelith:BAAALgAECgMJBQAAAA==.Arlen:BAAALgAECgkJDAAAAA==.Arma:BAABLgAECn8cAAIDAAgJjiNGBQAwAwADAAgJjiNGBQAwAwAAAA==.Armadro:BAAALgAFFAMJAwAAAA==.',
Au='Aurky:BAAALgAECgEJAQAAAA==.',
Ba='Bald:BAAALgADCgYJBgAAAA==.Balob:BAACLgAFFH8PAAIEAAQJBiD1AgBGAQAEAAQJBiD1AgBGAQAuAAQKfyAAAgQACAlqJXsEAFQDAAQACAlqJXsEAFQDAAAA.Bandar:BAAALgADCgcJBwAAAA==.',
Bl='Blacksteve:BAAALgAECgIJAgAAAA==.',
Bm='Bmxdh:BAAALgAECgYJDwAAAA==.',
Br='Broku:BAAALgADCgEJAQABLgAECgYJGQAFAPIYAA==.Brudah:BAAALgAECgEJAQAAAA==.',
Bu='Bubblelove:BAAALgAECgcJEgAAAA==.Bubbly:BAABLgAECn8ZAAIFAAYJ8hj3HgA1AQAFAAYJ8hj3HgA1AQAAAA==.',
Ca='Caelum:BAAALgAECgMJAwAAAA==.Callmepappy:BAAALgADCgUJBQAAAA==.Canníbal:BAAALgAECgcJDQAAAA==.',
Ce='Censored:BAAALgADCgIJAgAAAA==.',
Ch='Chopsy:BAABLgAECn80AAMDAAgJXCDDAQBFAgADAAgJXCDDAQBFAgAGAAIJxAvGXgBUAAAAAA==.Chris:BAAALgAECgUJCAAAAA==.Chucklez:BAAALgADCgMJAwAAAA==.Chulobulo:BAAALgAECgIJAgAAAA==.Chulosdck:BAAALgADCgUJBQAAAA==.',
Ci='Cinnabons:BAAALgAECgMJAwABLgAFFAEJAQACAAAAAA==.',
Cl='Cleopatrick:BAAALgADCgkJEAAAAA==.',
Co='Codingsocks:BAAALgADCgEJAgAAAA==.',
Cr='Crekton:BAAALgAECgMJAwAAAA==.Cronnos:BAAALgAECgYJBwAAAA==.',
Cu='Cudlemonster:BAAALgAECgUJEAAAAA==.Cursed:BAABLgAECn8YAAIHAAgJLRgSAgCtAgAHAAgJLRgSAgCtAgAAAA==.',
Da='Dabz:BAAALgAECgUJCQAAAA==.Danyel:BAAALgADCgYJBwAAAA==.Darmok:BAABLgAECn8fAAIIAAgJaiL3BwD1AgAIAAgJaiL3BwD1AgAAAA==.Darzamat:BAAALgADCgEJAQAAAA==.',
De='Demonbubble:BAACLgAFFH8FAAIBAAIJQwl8FQCVAAABAAIJQwl8FQCVAAAuAAQKfxkAAgEACAkfEgVJANABAAEACAkfEgVJANABAAAA.Dezric:BAAALgADCgYJDAABLgAECgEJAgACAAAAAA==.',
Do='Dotomic:BAAALgAECgQJBQABLgAFFAYJEQAJAOUgAA==.',
Dr='Drfe:BAAALgADCgYJBgAAAA==.Drownix:BAAALgAECgEJAQAAAA==.',
Eb='Ebon:BAAALgADCgMJAwAAAA==.',
Ec='Ecaed:BAAALgAECgYJDgAAAA==.',
El='Elektriss:BAAALgAECgMJAwAAAA==.Elnaris:BAAALgAECgYJDQAAAA==.Elohime:BAAALgADCgYJCAAAAA==.',
Eo='Eon:BAAALgAECgIJBAAAAA==.',
Er='Erikkak:BAAALgADCgQJBAAAAA==.',
Fr='Fragga:BAAALgAECgYJDgAAAA==.',
Fu='Fullflavor:BAAALgADCgIJAgAAAA==.',
['Fü']='Füran:BAAALgADCgIJAgAAAA==.',
Ga='Ganryu:BAAALgADCgYJCgAAAA==.',
Gb='Gboybalili:BAAALgADCgcJDAAAAA==.',
Gi='Gitzi:BAABLgAECn8pAAIKAAgJ7xo3HABdAgAKAAgJ7xo3HABdAgAAAA==.',
Gl='Glaciea:BAAALgADCgMJAwABLgAECgcJFAALAEQhAA==.',
Gr='Greenrage:BAAALgADCgQJBAAAAA==.Griever:BAAALgAECgEJAQAAAA==.',
['Gë']='Gënshï:BAAALgAECgEJAQAAAA==.',
Hi='Highfive:BAAALgADCgIJAgAAAA==.',
Ho='Hordend:BAAALgAECgQJCwAAAA==.Hozru:BAAALgADCgEJAQAAAA==.',
Hu='Hulkfists:BAABLgAECn8UAAMEAAYJowm5SgAcAQAEAAYJowm5SgAcAQAMAAYJ3gLXHgDiAAAAAA==.',
Hy='Hydration:BAAALgADCgMJAwAAAA==.',
Im='Imcepsy:BAABLgAECn8YAAINAAcJphU5FwDmAQANAAcJphU5FwDmAQAAAA==.',
Io='Iownzuu:BAAALgADCgMJAwAAAA==.',
Ja='Jayjay:BAAALgAFFAEJAQAAAA==.',
Je='Jethroy:BAAALgAECgQJCgAAAA==.',
Jf='Jfkwspvpfldg:BAAALgAECgYJBgAAAA==.',
Ji='Jimmie:BAABLgAECn8aAAIOAAgJuiApEQCYAgAOAAgJuiApEQCYAgAAAA==.',
Jo='Johnparstina:BAAALgAECgQJBAAAAA==.Jolty:BAABLgAECn8YAAIMAAkJER3BAwDuAgAMAAkJER3BAwDuAgAAAA==.',
Jr='Jrbacnchee:BAAALgAECgEJAQAAAA==.Jrbcncheze:BAAALgAECgYJDgAAAA==.',
Ka='Kainicus:BAABLgAECn8hAAIPAAgJyxLKCQDPAQAPAAgJyxLKCQDPAQAAAA==.Kainigal:BAAALgADCgYJCwAAAA==.Kainisham:BAAALgADCgcJBwAAAA==.',
Ke='Kelador:BAAALgAECgUJCgAAAA==.',
Kh='Khappucino:BAAALgAECgIJAgAAAA==.Kharibou:BAAALgAECgIJAgAAAA==.Khellendros:BAAALgADCgYJCgAAAA==.Khrism:BAAALgADCgQJBAAAAA==.',
Ki='Kibbi:BAAALgADCgcJBwAAAA==.Kitsyune:BAABLgAECn8YAAIQAAgJBhOKAQBmAQAQAAgJBhOKAQBmAQAAAA==.',
Kl='Kløey:BAAALgAECgYJDAAAAA==.',
La='Laethys:BAAALgADCggJBwABLgAECggJHwARAIkfAA==.',
Li='Lithini:BAAALgADCgEJAQAAAA==.',
Lo='Lowtech:BAAALgAECgMJAwAAAA==.',
Lu='Lukass:BAAALgADCgEJAQAAAA==.Luminusrayne:BAABLgAECn8pAAMNAAgJDgsEIgCEAQANAAgJYwoEIgCEAQASAAIJegQOGwBSAAAAAA==.Lussypipz:BAAALgAECgQJBwAAAA==.',
Ma='Mahwe:BAAALgAECgYJCAAAAA==.Manafest:BAAALgAECgMJBwAAAA==.Maros:BAAALgAECgYJCwAAAA==.',
Me='Meheret:BAABLgAECn8kAAIRAAgJ4gPSzgBOAQARAAgJ4gPSzgBOAQAAAA==.Melissenia:BAAALgAECgQJBAAAAA==.Mepha:BAAALgAECgYJCQAAAA==.',
Mi='Mint:BAABLgAECn8fAAIRAAgJiR+cBgBDAgARAAgJiR+cBgBDAgAAAA==.',
Mo='Mom:BAAALgAECgIJAgAAAA==.Mooby:BAAALgAECggJDwAAAA==.Moonfury:BAAALgAECgEJAQAAAA==.Moonleigh:BAAALgADCgMJBAAAAA==.Morganthe:BAAALgAECgIJAwAAAA==.',
Mu='Munt:BAAALgAECgQJBAABLgAECggJHwARAIkfAA==.',
My='Mypriiest:BAAALgAECgQJBAAAAA==.Myroguëë:BAAALgADCgUJBQAAAA==.Mythx:BAABLgAECn8WAAITAAcJhRoRJQAvAgATAAcJhRoRJQAvAgAAAA==.Mywarr:BAAALgADCgMJAwAAAA==.',
Na='Natâsi:BAABLgAECn8hAAIUAAgJSRTLCAC4AQAUAAgJSRTLCAC4AQAAAA==.',
Ne='Nerazul:BAABLgAECn8VAAQHAAYJph/IBQAJAgAHAAYJph/IBQAJAgAVAAMJ3wpi4wCTAAAWAAEJ/AgBeAAsAAAAAA==.Netharec:BAAALgADCgEJAQAAAA==.Nevai:BAAALgAECgYJCwAAAA==.',
Ni='Nielas:BAAALgAECgUJCQAAAA==.Nihilus:BAACLgAFFH8MAAIXAAUJTRaKCACMAQAXAAUJTRaKCACMAQAuAAQKfxUAAhcABwkWJLgvAHkCABcABwkWJLgvAHkCAAAA.Nilari:BAAALgAECgEJAQAAAA==.Nine:BAAALgADCgYJBgABLgAECggJNAADAFwgAA==.',
No='Noctazari:BAAALgADCgUJBQAAAA==.Noctium:BAABLgAECn8UAAILAAcJRCF2AABPAgALAAcJRCF2AABPAgAAAA==.Nostrildamus:BAAALgAECgYJEAABLgAECggJEwACAAAAAA==.',
Ow='Owlaf:BAAALgAECgIJAgABLgAFFAMJBwANAF4XAA==.Owls:BAACLgAFFH8HAAINAAMJXhdYBgDyAAANAAMJXhdYBgDyAAAuAAQKfyUAAxIACAmEIfsKAJ8CABIABwkbJPsKAJ8CAA0ACAmiHK4KAI0CAAEuAAUUAwkHAA0AXhcA.',
Pa='Pallywhacker:BAAALgADCgMJAwAAAA==.Pantsokay:BAAALgADCgEJAQAAAA==.',
Pe='Peach:BAABLgAECn8UAAMYAAgJwgfGCgCEAQAYAAcJ8AjGCgCEAQAOAAYJUAGYSwDNAAAAAA==.',
Po='Potatoeshot:BAAALgAECgQJBQAAAA==.',
Pr='Praisethesun:BAAALgADCgUJCAAAAA==.Prayxx:BAAALgADCgcJDAAAAA==.Pretzel:BAABLgAECn8bAAIXAAkJ/iLIBACHAwAXAAkJ/iLIBACHAwAAAA==.Proved:BAABLgAECn8pAAISAAcJzxwaAwAnAgASAAcJzxwaAwAnAgAAAA==.',
Ps='Psillycybin:BAAALgAECgMJBQAAAA==.',
Pu='Puggar:BAAALgADCgQJBgAAAA==.Pumpspotter:BAAALgAECgcJCAAAAA==.',
Qu='Quiescence:BAAALgADCgYJBgAAAA==.',
Ra='Ranas:BAAALgADCgIJAgAAAA==.Ravèn:BAAALgAECgUJBgAAAA==.Rayana:BAAALgADCgYJBgAAAA==.Razeal:BAAALgAECgYJCgAAAA==.',
Re='Rene:BAEALgAECgUJBgAAAA==.Rev:BAAALgADCgEJAQAAAA==.',
Rh='Rhysan:BAABLgAECn8mAAIIAAgJ7hNsCwCHAQAIAAgJ7hNsCwCHAQAAAA==.Rhyuk:BAAALgADCgQJBAAAAA==.',
Ri='Ristria:BAAALgADCgMJAwABLgAECgQJBwACAAAAAA==.Rizy:BAAALgAECgYJDgAAAA==.',
Ro='Robonord:BAAALgAECgIJAgAAAA==.Rokki:BAAALgADCgIJAgAAAA==.',
Ru='Rude:BAAALgADCgcJCwAAAA==.',
Ry='Rynhart:BAAALgADCgUJBQAAAA==.Ryushi:BAABLgAECn8uAAIBAAgJgh6fAwBjAgABAAgJgh6fAwBjAgAAAA==.',
Sa='Sacerdote:BAAALgAECgQJCAAAAA==.Sakari:BAAALgADCgcJDwAAAA==.Sandara:BAAALgADCgYJBgAAAA==.Sangre:BAAALgADCgIJAgAAAA==.Sarasara:BAAALgADCgUJBQAAAA==.',
Sc='Scoots:BAAALgADCgYJBgABLgAECggJNAADAFwgAA==.Scratster:BAAALgAECgcJCAAAAA==.',
Se='Sebnoth:BAABLgAECn8VAAIXAAYJPBfDFgBcAQAXAAYJPBfDFgBcAQAAAA==.',
Sh='Shalashaska:BAAALgADCgEJAQAAAA==.Shamantastik:BAAALgAECgMJAwAAAA==.Shiift:BAAALgADCgYJBwAAAA==.Shockblocked:BAAALgADCgQJBAAAAA==.',
Si='Sideburn:BAAALgADCgUJBQAAAA==.Sidepiece:BAAALgADCgcJCAAAAA==.Sillyderek:BAAALgAECgUJCAAAAA==.',
Sm='Smallpally:BAAALgAECgQJBAAAAA==.',
So='Soarsha:BAAALgAECgEJAQAAAA==.Solarida:BAAALgAECgYJCwAAAA==.',
Sr='Srsawyer:BAABLgAECn8bAAIVAAgJRg/DEQCCAQAVAAgJRg/DEQCCAQAAAA==.',
St='Staralfur:BAAALgADCgcJBwAAAA==.Stevokerjobs:BAAALgAECgYJDgAAAA==.Stratos:BAAALgADCgcJBwAAAA==.',
Su='Sunwa:BAAALgAECgYJCAABLgAECgcJFgATAIUaAA==.',
['Sï']='Sïmba:BAAALgAECgMJCQAAAA==.',
Te='Terzhull:BAAALgADCgIJAgAAAA==.',
Th='Thepride:BAAALgAECgcJDAAAAA==.',
Ti='Timmytim:BAAALgAECgQJCAAAAA==.Tired:BAAALgAECgUJBgAAAA==.',
To='Tool:BAACLgAFFH8ZAAIRAAgJHBu4AADdAgARAAgJHBu4AADdAgAuAAQKfyUAAhEACQnrJGYCANgDABEACQnrJGYCANgDAAAA.Touchi:BAAALgAECgEJAQABLgAECgcJEQACAAAAAA==.',
Tr='Troljin:BAAALgADCgEJAQAAAA==.',
Tu='Tuo:BAAALgAECgcJEQAAAA==.Turbid:BAAALgAECgYJEAAAAA==.',
Ty='Ty:BAAALgAECgQJBgAAAA==.',
Uh='Uhavemyrice:BAAALgADCgIJAgAAAA==.',
Vi='Vivia:BAAALgADCgQJBAAAAA==.Vivians:BAAALgADCggJCgAAAA==.',
Vo='Voutecomer:BAAALgADCgIJAgAAAA==.',
Wa='Walls:BAAALgAECggJEwAAAA==.Warrach:BAAALgADCgQJBAAAAA==.',
We='Wennoe:BAAALgADCgIJAgAAAA==.Westirras:BAAALgAECgMJAwAAAA==.',
Yo='Yogurt:BAAALgAECgYJBwABLgAECgYJGQAFAPIYAA==.',
Yu='Yusuke:BAABLgAECn8WAAMZAAcJWxElBwCKAQAZAAcJWxElBwCKAQAGAAYJPQn5PwDlAAAAAA==.',
Za='Zazabandit:BAAALgADCgUJBQAAAA==.',
Ze='Zenders:BAAALgADCgMJAwAAAA==.',
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

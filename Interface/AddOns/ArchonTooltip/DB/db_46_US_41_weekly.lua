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

local lookup = {'Priest-Discipline','Monk-Brewmaster','Druid-Guardian','Warlock-Demonology','Unknown-Unknown','DeathKnight-Blood','Paladin-Retribution','Paladin-Holy','Paladin-Protection','DemonHunter-Devourer','Mage-Fire','Rogue-Subtlety','Hunter-Survival','Hunter-Marksmanship','Mage-Frost','Shaman-Enhancement','Druid-Balance','Druid-Restoration','DeathKnight-Unholy','Warlock-Destruction','Warlock-Affliction','Priest-Holy','Warrior-Protection','Hunter-BeastMastery','Mage-Arcane','Shaman-Elemental','Monk-Windwalker','Priest-Shadow','Warrior-Arms','Warrior-Fury','DemonHunter-Havoc','Evoker-Preservation','Rogue-Assassination','Evoker-Augmentation','Evoker-Devastation',}
local provider = {region='US',realm='Bloodscalp',name='US',type='weekly',zone=46,date='2026-04-24',data={Aa='Aahzbear:BAAALgAECgMJBgAAAA==.',
Ab='Abreale:BAAALgADCgMJAwAAAA==.',
Ae='Aeero:BAABLgAECn8UAAIBAAYJNhfAHwCWAQABAAYJNhfAHwCWAQAAAA==.',
Ai='Aiden:BAABLgAECn8UAAICAAYJHxxoKgC3AQACAAYJHxxoKgC3AQAAAA==.',
Am='Amathal:BAAALgAECgcJEAAAAA==.Amilea:BAAALgAECgQJBAABLgAECggJIgADAJ4ZAA==.',
An='Angermoonria:BAAALgADCgcJBwAAAA==.Ankheloios:BAAALgADCggJDgAAAA==.Antihiiro:BAAALgAECgMJAwAAAA==.Antipro:BAAALgAECgYJCgAAAA==.Anzulok:BAAALgADCgYJAQAAAA==.',
Ar='Aredhela:BAAALgAECgYJCwAAAA==.Arinth:BAAALgADCggJEQAAAA==.Armpit:BAAALgAECgMJAwAAAA==.',
As='Ashiiro:BAAALgAECgcJEAAAAA==.Asia:BAABLgAECn8kAAIEAAkJMSAaAQDTAgAEAAkJMSAaAQDTAgAAAA==.Asmodeius:BAAALgADCgkJFwAAAA==.Astroprof:BAAALgAECgEJAQABLgAECgYJEAAFAAAAAA==.',
At='Athrea:BAAALgAECgcJDQAAAA==.',
Au='Auntjemima:BAAALgAECgEJAQAAAA==.Aureleus:BAAALgADCgEJAQAAAA==.',
Aw='Away:BAAALgADCgIJAgAAAA==.',
Az='Azaii:BAAALgADCggJCgAAAA==.Azlear:BAAALgAECgkJBgAAAA==.',
Ba='Babilouchoux:BAAALgADCgUJBQAAAA==.Ballz:BAAALgADCgYJBgAAAA==.Bano:BAAALgAECgMJAwAAAA==.Baythos:BAAALgAECgUJCwAAAA==.',
Bd='Bdssm:BAAALgAECgYJCwAAAA==.',
Be='Beefstick:BAAALgADCgcJBwAAAA==.Berzercarl:BAAALgAECgEJAQAAAA==.Beserkfury:BAAALgAECgUJDAAAAA==.',
Bh='Bhemtu:BAAALgADCgMJBAAAAA==.',
Bi='Biercan:BAAALgAECgcJCwAAAA==.Bigcarl:BAAALgADCgMJAwAAAA==.Binke:BAAALgAECgIJAgAAAA==.Bittywhite:BAAALgADCgkJEAAAAA==.Bittywyvern:BAAALgADCgUJBQABLgADCgkJEAAFAAAAAA==.',
Bl='Blayze:BAAALgAECgYJDAAAAA==.Blessidbee:BAAALgAECgEJAQAAAA==.Blightmarx:BAAALgADCgUJBwAAAA==.Blitzwow:BAAALgADCgYJBQAAAA==.Bluemoonflay:BAAALgAECgYJCwAAAA==.Blúnt:BAAALgADCgQJBAAAAA==.',
Bo='Bobheals:BAAALgAECgQJEAAAAA==.Boibye:BAAALgAECgUJCQAAAA==.Bolblock:BAAALgAECgUJBQAAAA==.Boostedww:BAAALgAECgMJBwAAAA==.',
Br='Brambleclaw:BAABLgAECn8kAAIGAAkJFxzrAAB7AgAGAAkJFxzrAAB7AgAAAA==.Brayker:BAABLgAECn8kAAIHAAkJsiRnAQDJAgAHAAkJsiRnAQDJAgAAAA==.Breadoneal:BAABLgAECn8VAAIIAAcJwhnNBAAaAgAIAAcJwhnNBAAaAgAAAA==.Brewed:BAAALgAECgYJEAAAAA==.Brisketbane:BAAALgAECgUJCQAAAA==.Brokenmask:BAAALgAECgcJCQAAAA==.Broxxar:BAAALgAECgIJAgAAAA==.Bruxxe:BAAALgAECgcJAQAAAA==.',
Bu='Burntroot:BAAALgAECgYJDQAAAA==.',
Ca='Caedwyn:BAABLgAECn8WAAIDAAcJAR1MAgC1AQADAAcJAR1MAgC1AQAAAA==.Caitrakk:BAAALgAECgYJEAAAAA==.Calignus:BAABLgAECn8aAAMHAAcJIhJ6HwAyAQAHAAcJIhJ6HwAyAQAJAAUJVQ8bJwDQAAAAAA==.Captjack:BAABLgAECn8YAAIKAAcJqQw4IAAJAQAKAAcJqQw4IAAJAQAAAA==.Cartilage:BAAALgAECgYJCAAAAA==.Catalei:BAAALgAECgYJDwAAAA==.Caution:BAAALgADCgYJCwAAAA==.',
Ce='Celira:BAAALgAECgEJAQAAAA==.',
Ch='Chickenman:BAAALgAECgEJAQAAAA==.Chiselia:BAAALgADCgUJBQABLgAECgcJCgAFAAAAAA==.Choconilla:BAAALgADCgQJBAAAAA==.Chonkmonk:BAAALgADCgQJBAAAAA==.Choppa:BAAALgADCggJCgAAAA==.Chorizo:BAAALgAECgEJAQABLgAECgQJBAAFAAAAAA==.Chupacabrass:BAAALgADCgYJBgAAAA==.',
Co='Consuming:BAAALgAECgUJEQAAAA==.Coorsbanquet:BAAALgAECgYJCAAAAA==.Corgh:BAABLgAECn8YAAILAAYJSQ0XBgBIAQALAAYJSQ0XBgBIAQAAAA==.Cowardice:BAAALgADCgYJCwAAAA==.',
Cr='Crash:BAEBLgAECn8fAAIKAAcJWyPSFQDTAgAKAAcJWyPSFQDTAgAAAA==.Croarik:BAAALgAECgEJAQAAAA==.Crushix:BAABLgAECn8jAAIIAAkJMRfaBAAYAgAIAAkJMRfaBAAYAgAAAA==.',
Cy='Cybear:BAAALgADCgcJBwAAAA==.Cykun:BAABLgAECn8hAAIMAAYJQB+rBAC6AQAMAAYJQB+rBAC6AQAAAA==.',
['Cã']='Cãs:BAAALgADCgkJCgABLgAECggJEwAFAAAAAA==.',
Da='Darch:BAABLgAECn8kAAMNAAkJAiM0AAD5AgANAAkJAiM0AAD5AgAOAAEJPwmYkAAqAAAAAA==.',
De='Deadgripz:BAAALgADCgMJBgAAAA==.Deadjaden:BAAALgADCgEJAQAAAA==.Deathscreams:BAAALgAECgQJBAAAAA==.Deathxreaper:BAAALgAECgIJAgAAAA==.Decessus:BAAALgAECgUJBgAAAA==.Dekig:BAAALgAECgcJDwAAAA==.Demine:BAABLgAECn8UAAIPAAYJVR7vYAAZAgAPAAYJVR7vYAAZAgAAAA==.Demonvibe:BAAALgAECgQJBgAAAA==.',
Di='Dico:BAAALgAECgIJAgAAAA==.Dinobots:BAAALgAECgYJDAAAAA==.Dipper:BAAALgAECggJEAAAAA==.',
Do='Donbarriga:BAAALgAECgMJAwAAAA==.Dosmojitos:BAAALgADCgcJBwAAAA==.Doublejumps:BAAALgAECgYJCQAAAA==.Doublelung:BAAALgAECgYJEgAAAA==.',
Dr='Drdiddles:BAAALgAECgMJAwAAAA==.',
Du='Duney:BAAALgAECggJEwAAAA==.Dußad:BAAALgAECgMJBgAAAA==.',
['Dé']='Déäth:BAAALgADCgQJBAAAAA==.',
Ec='Eckoe:BAAALgAECgUJDgAAAA==.',
Ee='Eekeros:BAAALgADCgUJBQAAAA==.Eeveeko:BAABLgAECn8hAAIQAAgJyBa4AQD7AQAQAAgJyBa4AQD7AQAAAA==.',
Ej='Ejavuday:BAABLgAECn8YAAIPAAgJ/x/wCwDxAQAPAAgJ/x/wCwDxAQAAAA==.',
El='Elvudu:BAAALgAECgIJBAAAAA==.',
Em='Emberstrife:BAAALgAECgEJAgAAAA==.',
Er='Erazath:BAAALgAECgQJCAAAAA==.Erianar:BAAALgADCgYJDAAAAA==.Ericdruid:BAABLgAECn8YAAMRAAcJSiDzEgB+AgARAAcJSiDzEgB+AgASAAEJ6QqO1gAqAAAAAA==.Ericlock:BAAALgADCgMJAwAAAA==.',
Ev='Eveko:BAAALgADCgIJAQAAAA==.Evera:BAABLgAECn8YAAITAAYJ8wNWJwD1AAATAAYJ8wNWJwD1AAAAAA==.Evokinpants:BAAALgAECgYJDQAAAA==.Evos:BAAALgAECgQJBgAAAA==.',
Ex='Explicatory:BAAALgAECgYJBgAAAA==.',
Ey='Eyllion:BAAALgAECgQJBQAAAA==.',
Fa='Falorin:BAAALgADCgMJAwAAAA==.Fastoris:BAAALgADCgEJAQAAAA==.Fauci:BAAALgAECgcJCAAAAA==.',
Fb='Fblthelost:BAAALgAECgMJAwAAAA==.',
Fe='Feihao:BAAALgADCggJEgAAAA==.Feile:BAABLgAECn8kAAQEAAkJrBLoBgAEAgAEAAkJTRLoBgAEAgAUAAIJfguvVwBnAAAVAAEJAADzLwA+AAAAAA==.Feshh:BAAALgADCgEJAQAAAA==.',
Fi='Fifezilla:BAAALgADCgYJBgAAAA==.Firble:BAAALgADCgYJBgAAAA==.Fireg:BAEALgADCgEJAQAAAA==.Fistbeaver:BAAALgADCgUJBQAAAA==.',
Fo='Foolezz:BAAALgADCgMJAwAAAA==.',
Fr='Fredthedh:BAABLgAECn8aAAIKAAgJFCNMFADeAgAKAAgJFCNMFADeAgAAAA==.',
Fu='Furble:BAAALgADCgYJBgAAAA==.',
Ga='Gaashw:BAAALgAECgEJAwAAAA==.Gadziila:BAAALgADCgEJAQAAAA==.Galcyon:BAAALgADCgEJAQAAAA==.Galiant:BAABLgAECn8WAAITAAYJnCJVEACUAQATAAYJnCJVEACUAQAAAA==.Gator:BAAALgAECgEJAQAAAA==.Gaulish:BAAALgADCgkJCQAAAA==.',
Ge='Gethalyn:BAAALgAECgYJCQAAAA==.Gexz:BAAALgADCgYJDAAAAA==.',
Gl='Glaivedaddy:BAAALgAECgEJAQAAAA==.Glenlives:BAAALgADCgkJCQABLgAECgQJBAAFAAAAAA==.',
Go='Gore:BAAALgAECgUJBQAAAA==.Gottverdammt:BAAALgAECgEJAQABLgAECgYJBwAFAAAAAA==.',
Gr='Graveknight:BAAALgAECgMJAwAAAA==.Graveshot:BAAALgADCgQJBAAAAA==.Greyskin:BAAALgADCgEJAQAAAA==.Grizzabella:BAABLgAECn8XAAISAAgJHBoDBQAyAgASAAgJHBoDBQAyAgAAAA==.Grreenry:BAAALgAECgEJAQAAAA==.Grriz:BAAALgADCgEJAQAAAA==.Grtmustachio:BAAALgAECgYJBwAAAA==.Grundle:BAAALgAECgMJAwAAAA==.',
Gu='Gularak:BAAALgAECgQJBgAAAA==.Gunghø:BAAALgADCgcJBwAAAA==.',
Gy='Gyutaro:BAAALgADCgEJAQAAAA==.',
Ha='Haelellionys:BAAALgADCgQJBAAAAA==.Hanamae:BAAALgADCgEJAQAAAA==.Hanswoloqued:BAAALgAECgYJEQAAAA==.Harmfuljoker:BAAALgADCgQJBAAAAA==.Haxzen:BAAALgADCgMJBAAAAA==.',
He='Healufast:BAABLgAECn8XAAIWAAgJMBiPBADsAQAWAAgJMBiPBADsAQAAAA==.Hellsong:BAAALgAECgMJAwABLgAECgYJBgAFAAAAAA==.Heysisters:BAAALgADCgEJAQAAAA==.',
Hi='Hispeas:BAAALgADCgQJBwAAAA==.Hitchkawk:BAAALgAECgEJAQAAAA==.Hitchlock:BAAALgAECgEJAgAAAA==.',
Ho='Holysabeline:BAABLgAECn8kAAIIAAkJbBPGBgDmAQAIAAkJbBPGBgDmAQAAAA==.Honestleon:BAAALgADCgMJAwABLgAECgcJEgAFAAAAAA==.',
Hu='Huchar:BAABLgAECn8dAAIXAAgJUhtAAwDCAQAXAAgJUhtAAwDCAQAAAA==.Huevos:BAAALgAECgEJAQAAAA==.Huntersteve:BAABLgAECn8hAAMYAAgJPyMtAQDHAgAYAAgJPyMtAQDHAgAOAAYJ7CCuIgAOAgAAAA==.',
Hy='Hydraxix:BAAALgADCgUJBQAAAA==.',
Ia='Iamanopcow:BAAALgADCgQJBAAAAA==.Iamspeed:BAAALgADCgQJBAAAAA==.',
Ic='Iceblade:BAABLgAECn8ZAAIIAAkJKBP4HwAaAgAIAAkJKBP4HwAaAgAAAA==.',
If='If:BAAALgAECgMJAwAAAA==.',
Ii='Iityouup:BAAALgADCgYJCAAAAA==.',
Il='Illidaniella:BAAALgAECgQJCAAAAA==.Illsmurfuup:BAABLgAECn8UAAINAAgJ9CZoAAClAwANAAgJ9CZoAAClAwAAAA==.',
In='Infection:BAAALgADCgYJCAAAAA==.Inverse:BAAALgADCgYJBgAAAA==.',
Ir='Irôh:BAAALgAECgEJAQABLgAECgMJBQAFAAAAAA==.',
Is='Ishmael:BAAALgADCgEJAQAAAA==.',
Iv='Ivannas:BAAALgADCgQJBAAAAA==.',
Ja='Jaabroni:BAAALgADCgIJAgAAAA==.Jackymoon:BAAALgAECgQJCQAAAA==.Jaxxion:BAAALgADCgMJAwAAAA==.',
Jd='Jdawg:BAABLgAECn8gAAIQAAkJvCA5AADYAgAQAAkJvCA5AADYAgAAAA==.',
Je='Jessaiyan:BAABLgAECn8XAAIKAAgJzBwpGgC3AgAKAAgJzBwpGgC3AgAAAA==.',
Ji='Jindo:BAAALgADCgcJBwAAAA==.Jiuni:BAAALgADCgUJBQAAAA==.',
Ju='Julaudette:BAAALgADCggJCwAAAA==.Julzaria:BAAALgAECgQJCAAAAA==.Jurny:BAAALgAECgQJBgAAAA==.',
Ka='Kadookieii:BAAALgAECgMJBAAAAA==.Kahlandra:BAABLgAECn8cAAMZAAkJgBQCBAAXAgAZAAkJgBQCBAAXAgAPAAIJggFthAEjAAAAAA==.Kaizer:BAABLgAECn8hAAIaAAgJpRrbGABNAgAaAAgJpRrbGABNAgAAAA==.Kalo:BAAALgAECgMJAwAAAA==.Kanrethad:BAAALgADCgQJBwABLgAECgYJEwAFAAAAAA==.Karina:BAABLgAECn8kAAIKAAkJIx6BBABHAgAKAAkJIx6BBABHAgAAAA==.Kastravia:BAAALgADCgYJBgABLgAFFAMJBQAbAPELAA==.Kawolski:BAAALgAECgIJAwABLgAFFAMJBQAbAPELAA==.',
Ke='Kelitarra:BAAALgADCgQJCAAAAA==.Kevin:BAAALgAECgYJCAAAAA==.',
Kh='Khanjuror:BAABLgAECn8ZAAIUAAcJkAtUBQDzAAAUAAcJkAtUBQDzAAAAAA==.Kholonoe:BAABLgAECn8bAAIcAAgJcBW5BQCwAQAcAAgJcBW5BQCwAQAAAA==.Khornedog:BAAALgAECgYJEQAAAA==.Khrama:BAAALgAECgYJBwABLgAECgcJFgACAOMjAA==.',
Ki='Kiimachamara:BAAALgADCgIJAgAAAA==.Killik:BAAALgADCgQJBAAAAA==.Kiritokun:BAAALgADCgYJBAAAAA==.',
Kl='Klapz:BAAALgADCgcJDQABLgAECgcJCwAFAAAAAA==.Kleenonean:BAABLgAECn8tAAMcAAgJeCV+AADoAgAcAAgJeCV+AADoAgAWAAIJxgZDdABXAAAAAA==.',
Kr='Kreuzritter:BAABLgAECn8fAAINAAkJLBDOCABXAgANAAkJLBDOCABXAgAAAA==.',
Ku='Kungcarefu:BAAALgAECgYJDwAAAA==.Kungfushnaz:BAAALgADCgYJCwAAAA==.Kurzaan:BAAALgAECgIJAgAAAA==.Kurzak:BAAALgAECgMJAwAAAA==.',
La='Laciel:BAAALgAECgMJAwABLgAECgcJDQAFAAAAAA==.Lacio:BAABLgAECn8jAAIcAAgJzAZWCwA8AQAcAAgJzAZWCwA8AQAAAA==.Larune:BAAALgADCgQJBwAAAA==.Lavendàh:BAAALgAECggJEQAAAA==.',
Le='Lemonite:BAABLgAECn8UAAISAAgJyhznFACOAgASAAgJyhznFACOAgAAAA==.Lennykoggins:BAAALgAECgQJDQAAAA==.Leyru:BAAALgAECgcJDQAAAA==.',
Li='Liberos:BAAALgAECgQJBwAAAA==.Lifenight:BAAALgAECggJEgAAAA==.Lithvia:BAAALgAECgYJCgAAAA==.',
Ln='Lninedkhack:BAABLgAECn8UAAMTAAcJ/BF7igBsAQATAAcJ/BF7igBsAQAGAAQJVATbDwBwAAAAAA==.',
Lo='Lockdor:BAAALgAECgQJBAAAAA==.Logaar:BAAALgAECggJDwAAAA==.Louvuitton:BAAALgADCgcJDgAAAA==.',
Lu='Lunartsy:BAAALgADCggJDgAAAA==.Lustiel:BAAALgAECgYJCwAAAA==.Luticris:BAAALgADCggJEAAAAA==.',
Ly='Lyoric:BAAALgAECgEJAQAAAA==.',
Ma='Madmax:BAAALgADCggJCAAAAA==.Maegot:BAAALgADCgYJBgAAAA==.Maiden:BAAALgADCgUJCAABLgAECgYJEwAFAAAAAA==.Malexannius:BAAALgADCgUJCQAAAA==.Mannirot:BAAALgAECgEJAQAAAA==.Maxdeath:BAABLgAECn8eAAITAAgJ9iO7DQAtAwATAAgJ9iO7DQAtAwAAAA==.Mazre:BAAALgAECgQJBwAAAA==.',
Me='Megtallica:BAAALgAECgEJAQAAAA==.Mensrea:BAAALgAECgQJBwAAAA==.Merlinn:BAAALgADCgMJBgAAAA==.Merrycold:BAABLgAECn8aAAMTAAcJJiI8PABGAgATAAYJ3yM8PABGAgAGAAMJtRLqPgBUAAAAAA==.Merrygold:BAAALgADCgMJAwABLgAECgcJGgATACYiAA==.Merrygored:BAAALgAECgIJAgABLgAECgcJGgATACYiAA==.Mess:BAAALgAECgYJEQABLgAECgYJEwAFAAAAAA==.Methodical:BAAALgADCgUJBQAAAA==.Metophis:BAAALgAECgYJCgAAAA==.',
Mf='Mfboomstick:BAABLgAECn8dAAINAAYJ/yXABgCQAgANAAYJ/yXABgCQAgAAAA==.',
Mi='Mikklelee:BAAALgADCgIJAgAAAA==.Missdebby:BAAALgADCgYJCwAAAA==.Missoxx:BAAALgAECgMJAwAAAA==.Mistweaver:BAAALgAECgQJBAAAAA==.Miztakswrmde:BAAALgADCgUJBgAAAA==.',
Mo='Moghorva:BAAALgAECggJEwAAAA==.Mojoe:BAAALgAECgQJCQAAAA==.Mommyswaggin:BAAALgAECgUJCQAAAA==.Moonra:BAAALgAECgEJAQAAAA==.Moopocalypse:BAAALgADCgUJBQABLgAECggJHgAWAOwkAA==.Moopsta:BAAALgADCggJDgABLgAECggJHgAWAOwkAA==.Moopster:BAABLgAECn8eAAIWAAgJ7CTpAgAzAwAWAAgJ7CTpAgAzAwAAAA==.Mordekaiserz:BAAALgAECgUJCAAAAA==.',
Mu='Mucouslurp:BAAALgADCgEJAQAAAA==.',
Na='Nalahni:BAAALgAFFAEJAgAAAA==.Nanashi:BAAALgAECgMJAwAAAA==.Nastage:BAAALgADCgMJAQAAAA==.Nastus:BAAALgAECgMJAwAAAA==.Nayela:BAAALgAECgYJEAAAAA==.Nazgru:BAAALgADCgcJBgAAAA==.',
Ne='Neptuneakis:BAAALgAECgMJAwAAAA==.Nerfblaster:BAAALgADCgEJAQAAAA==.Newcarsmell:BAAALgAECgEJAQAAAA==.',
Ni='Nicktee:BAAALgAECgEJAgAAAA==.Nightmares:BAAALgAECgcJCgAAAA==.Nimrose:BAAALgAECgMJAwAAAA==.Niquid:BAAALgAECgYJEwAAAA==.',
No='Nolmac:BAAALgAECgQJBAAAAA==.Notahealer:BAAALgAECgYJBgAAAA==.Noxloxes:BAAALgADCgcJDAAAAA==.',
Np='Npv:BAAALgAECgEJAQAAAA==.',
Ny='Nyssavia:BAAALgADCgcJDgAAAA==.',
Oa='Oakshre:BAAALgAECgYJEQAAAA==.',
Ol='Olivertwist:BAAALgAECgMJAwAAAA==.',
On='Ontwou:BAAALgAECgYJBgAAAA==.',
Op='Ophi:BAAALgAECgYJEQAAAA==.',
Os='Oshaku:BAAALgAECgcJBwAAAQ==.',
Ou='Ouchpotato:BAAALgAECgIJAgABLgAECggJGAAMAG0eAA==.',
Pa='Pallynim:BAAALgADCgQJBwAAAA==.Palms:BAAALgAECggJEwAAAA==.Pancakezebra:BAABLgAECn8lAAINAAkJ4xS0AQApAgANAAkJ4xS0AQApAgAAAA==.Pantsftw:BAAALgAECgYJEgAAAA==.Papabear:BAAALgADCgUJBQAAAA==.Parkbreezy:BAAALgAECgUJDQAAAA==.Pawg:BAAALgADCgcJBgAAAA==.',
Pe='Peltier:BAABLgAECn8fAAIPAAgJIB3ACAAcAgAPAAgJIB3ACAAcAgAAAA==.Pendle:BAAALgAECgYJCwAAAA==.',
Ph='Phoenix:BAABLgAECn8VAAIHAAYJeyHFPgAqAgAHAAYJeyHFPgAqAgAAAA==.',
Pl='Plox:BAAALgAECgYJDwAAAA==.Plurnizz:BAAALgAECggJEwAAAA==.',
Po='Pocketchange:BAAALgAECggJEgAAAA==.',
Pu='Puppymoke:BAAALgAECgMJAwAAAA==.Puptart:BAAALgAECgUJBQAAAA==.',
Ra='Raest:BAABLgAECn8WAAICAAcJ4yOXEACVAgACAAcJ4yOXEACVAgAAAA==.Raiker:BAAALgAECgMJAwAAAA==.Razzlock:BAAALgAECgEJAQAAAA==.',
Re='Regret:BAAALgAECgYJCgAAAA==.Relovan:BAABLgAECn8UAAMdAAcJ0ggxBQA9AQAdAAcJ0ggxBQA9AQAeAAUJSwN/hgClAAAAAA==.Renothidan:BAABLgAECn8XAAIHAAgJHxn+TQD4AQAHAAgJHxn+TQD4AQAAAA==.Reuben:BAAALgADCgIJBAAAAA==.Revin:BAAALgADCgYJBgAAAA==.',
Ri='Rickyboby:BAAALgADCgEJAQAAAA==.Righteøus:BAAALgAECgQJBwAAAA==.Rillan:BAAALgAECgQJDQAAAA==.Ripper:BAAALgAECgUJCQAAAA==.Rithcice:BAABLgAECn8eAAIeAAkJyCQTAABWAwAeAAkJyCQTAABWAwAAAA==.Rizzdolphler:BAAALgAECgcJCAAAAA==.',
Ro='Roadnurse:BAAALgADCgIJAgAAAA==.Rockntroll:BAAALgADCgIJAgAAAA==.Rodah:BAAALgADCgkJEAAAAA==.Roscoee:BAAALgADCgEJAQAAAA==.',
Rs='Rsk:BAAALgADCgYJCQABLgAECgYJEwAFAAAAAA==.',
['Rà']='Ràrity:BAAALgADCggJCAAAAA==.',
['Rö']='Rönburgundy:BAABLgAECn8hAAIEAAgJTx15BAA6AgAEAAgJTx15BAA6AgAAAA==.',
Sa='Sanako:BAABLgAECn8eAAIRAAkJCQsxBwCKAQARAAkJCQsxBwCKAQAAAA==.Sanastusa:BAAALgADCgYJCAAAAA==.Saneros:BAAALgAECgEJAQABLgAECggJIAAKALsSAA==.Santoniche:BAAALgAECgMJAwAAAA==.Sap:BAAALgAECgYJDQABLgAECgYJEwAFAAAAAA==.Sausiege:BAAALgAECgMJAwAAAA==.Saveserenade:BAAALgAECgUJBQAAAA==.',
Sc='Scarylarry:BAABLgAECn8gAAIKAAgJuxJmFgBLAQAKAAgJuxJmFgBLAQAAAA==.Scyther:BAABLgAECn8XAAMKAAgJfgzDcQBPAQAKAAgJkgvDcQBPAQAfAAUJDQ2WSgDGAAAAAA==.',
Sd='Sdh:BAAALgADCgQJBgAAAA==.',
Se='Seishinokami:BAAALgAECgQJBAAAAA==.Serenade:BAABLgAECn8eAAIPAAgJiB8RMwCmAgAPAAgJiB8RMwCmAgAAAA==.Setheron:BAAALgAECgQJBAAAAA==.Sethron:BAAALgAECgEJAQAAAA==.Señsei:BAAALgAECggJCwAAAA==.',
Sh='Shamtul:BAAALgAECgEJAQAAAA==.Shamwow:BAAALgADCgcJDgAAAA==.Shlea:BAAALgAECgcJEgAAAA==.Shyva:BAABLgAECn8cAAIXAAcJPyMsBwC4AgAXAAcJPyMsBwC4AgAAAA==.',
Si='Siinestro:BAAALgADCgYJDAAAAA==.Sinlee:BAAALgAECgcJCwABLgAECggJJQAEACEgAA==.',
Sl='Slayla:BAAALgAECgMJAwAAAA==.Slimboyjoe:BAAALgADCgcJDgAAAA==.Slimmjim:BAAALgADCgEJAQAAAA==.Slinkstir:BAAALgADCgQJAwAAAA==.',
Sn='Sneak:BAAALgADCgMJAwABLgAECgYJCQAFAAAAAA==.',
So='Solendros:BAAALgAECgYJDwAAAA==.Sonthar:BAAALgAECgYJBgAAAA==.Soulborn:BAAALgADCgEJAQAAAA==.',
Sp='Spacehog:BAAALgAECgYJBwAAAA==.Sparticus:BAAALgAECgEJAQAAAA==.Spiro:BAAALgADCgUJBQAAAA==.',
St='Standarshh:BAABLgAECn8bAAIYAAgJnRpUBwD0AQAYAAgJnRpUBwD0AQAAAA==.Stemmz:BAAALgADCgEJAQAAAA==.Stronghand:BAAALgADCgYJBwAAAA==.',
Su='Subtle:BAABLgAECn8YAAIMAAgJbR4nDQDHAgAMAAgJbR4nDQDHAgAAAA==.Sugarbabi:BAABLgAECn8ZAAMSAAcJ3x4sIQA7AgASAAcJ3x4sIQA7AgARAAQJNBZ2DQAZAQAAAA==.Sugarrush:BAAALgADCgUJBQAAAA==.Sulcer:BAAALgADCgMJBAAAAA==.',
Sy='Sylria:BAAALgAECgIJAgAAAA==.Sylrianah:BAABLgAECn8kAAMWAAkJfhyLCwCXAgAWAAkJfhyLCwCXAgABAAQJrgiLDgDKAAAAAA==.Sylveste:BAABLgAECn8XAAIIAAcJ0hNuOQCUAQAIAAcJ0hNuOQCUAQAAAA==.Sylvfelster:BAAALgAECgUJBQAAAA==.Sylánnia:BAAALgADCgcJBwAAAA==.',
Ta='Ta:BAAALgAECgMJAwAAAA==.Tankhiskhan:BAAALgAECgcJDgAAAA==.Tarlis:BAAALgAECgcJDgAAAA==.',
Te='Tedrickeyjr:BAAALgAECgEJBAAAAA==.Terithresh:BAAALgADCgMJBAAAAA==.',
Th='Thanil:BAAALgAECgYJCgAAAA==.',
Ti='Tilvalhalla:BAABLgAECn8XAAIgAAYJJwogKgAhAQAgAAYJJwogKgAhAQAAAA==.',
To='Tom:BAAALgAECgEJAQAAAA==.Torrin:BAAALgADCgYJBwAAAA==.Tortricid:BAAALgAECgIJAwAAAA==.Totinospizza:BAAALgADCgYJBgAAAA==.',
Tr='Trashkan:BAAALgADCgIJAgAAAA==.Traumzi:BAAALgAECgEJAQAAAA==.Travvy:BAACLgAFFH8VAAMMAAYJPyRKAQD/AQAMAAUJpCNKAQD/AQAhAAIJoR7tAQB4AAAuAAQKfx4AAgwACQkvIwABAMMDAAwACQkvIwABAMMDAAAA.Treezus:BAAALgADCgYJCAAAAA==.Trevmo:BAABLgAECn8kAAIXAAkJ2RYqAgAGAgAXAAkJ2RYqAgAGAgAAAA==.',
Tu='Turaylon:BAAALgAFFAEJAQAAAA==.Turtlebox:BAAALgAECgEJAQAAAA==.',
Ty='Tym:BAAALgAECggJCAAAAA==.',
Ug='Ugargro:BAAALgADCgcJDgAAAA==.',
Un='Unapologetic:BAAALgAECgQJBAAAAA==.Unbreakabull:BAAALgADCgYJBgAAAA==.Unceejin:BAAALgADCggJEQAAAA==.Unholydk:BAAALgAECgYJEwAAAA==.',
Va='Valcuna:BAAALgAECgEJAQAAAA==.Valka:BAAALgAECgQJBwAAAA==.Vamptouch:BAAALgAECgIJAwABLgAECgYJCQAFAAAAAA==.Vanaan:BAAALgADCgYJBgAAAA==.Varidrus:BAAALgADCgIJAgAAAA==.Vaste:BAAALgADCgcJCQAAAA==.',
Ve='Ventrue:BAABLgAECn8aAAIPAAcJhRhOdADqAQAPAAcJhRhOdADqAQAAAA==.Veyle:BAABLgAECn8kAAMMAAkJriFQAAAAAwAMAAkJriFQAAAAAwAhAAEJKh65GwBJAAAAAA==.',
Vi='Vivian:BAAALgAECgYJEAAAAA==.',
Vo='Voidsurge:BAAALgAECgUJDAABLgAECgYJEwAFAAAAAA==.',
Vy='Vyndria:BAAALgADCgcJBgAAAA==.',
We='Weaspore:BAABLgAECn8ZAAITAAgJVhjBBgAWAgATAAgJVhjBBgAWAgAAAA==.Weasy:BAAALgADCgkJCQAAAA==.',
Wo='Woogidaboogi:BAAALgADCgUJBgAAAA==.Woogieboogie:BAAALgADCgEJAQABLgADCgUJBgAFAAAAAA==.',
Xi='Xiamiel:BAAALgADCgYJCQAAAA==.',
Xl='Xl:BAABLgAECn9EAAMfAAgJhxxVCwCrAgAfAAgJhxxVCwCrAgAKAAYJIghaLgC5AAAAAA==.',
Yh='Yharnem:BAAALgAECgUJCAAAAA==.',
Yo='Yogurtpants:BAAALgAECgYJEgAAAA==.Yonny:BAAALgADCgEJAQAAAA==.',
Yu='Yukionna:BAAALgADCgcJCwAAAA==.',
Za='Zabara:BAAALgAECgYJCwAAAA==.Zakaraki:BAABLgAECn8kAAQiAAkJoiTHAQBRAgAjAAcJ7iXZBgCDAgAiAAcJOBDHAQBRAgAgAAcJTQd3JgBBAQAAAA==.Zaki:BAAALgAECgYJEAAAAA==.Zanked:BAAALgADCgQJBAAAAA==.Zarkingu:BAAALgADCgMJAwAAAA==.',
Ze='Zeleria:BAAALgAECgUJBgAAAA==.Zeno:BAAALgAECgEJAgAAAA==.Zerathis:BAABLgAECn8lAAIEAAgJISAvEwDjAgAEAAgJISAvEwDjAgAAAA==.Zerathül:BAAALgAECgIJAwAAAA==.Zerötwo:BAAALgADCgkJCgAAAA==.Zestul:BAAALgADCgkJFQAAAA==.',
Zi='Zimbobayaga:BAAALgAECgMJAwAAAA==.',
Zo='Zodivine:BAAALgADCgMJAwAAAA==.Zohar:BAAALgADCgEJAgAAAA==.Zooty:BAAALgADCgUJAwAAAA==.Zoshow:BAAALgAECgEJAQAAAA==.',
Zu='Zuggo:BAAALgADCgYJBgAAAA==.',
['Zõ']='Zõshow:BAAALgAECgYJCgAAAA==.',
['Ða']='Ðaredevil:BAAALgAECgYJCQAAAA==.',
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

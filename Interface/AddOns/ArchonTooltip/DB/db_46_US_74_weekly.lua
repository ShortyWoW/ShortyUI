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

local lookup = {'Paladin-Retribution','Unknown-Unknown','DeathKnight-Unholy','Druid-Restoration','Evoker-Augmentation','Paladin-Holy','Priest-Holy','Priest-Discipline','Rogue-Subtlety','Hunter-BeastMastery','DemonHunter-Devourer','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','Rogue-Assassination','Evoker-Preservation','Shaman-Enhancement','Priest-Shadow','Hunter-Marksmanship','Warrior-Protection','Warrior-Fury','DeathKnight-Blood','DeathKnight-Frost','DemonHunter-Havoc','Shaman-Restoration','Monk-Mistweaver','Mage-Fire','DemonHunter-Vengeance','Rogue-Outlaw','Warrior-Arms','Paladin-Protection','Shaman-Elemental','Druid-Guardian','Hunter-Survival',}
local provider = {region='US',realm="Drak'Tharon",name='US',type='weekly',zone=46,date='2026-05-01',data={Ad='Adorah:BAABLgAECn8UAAIBAAcJpQkdRwA0AQABAAcJpQkdRwA0AQAAAA==.',
Ak='Akazamello:BAAALgAECgEJAQAAAA==.',
Al='Allyia:BAAALgADCgEJAgABLgADCgEJAgACAAAAAA==.Alucarde:BAAALgAECgYJEwAAAA==.',
Ar='Arator:BAAALgADCgYJBQAAAA==.Artelios:BAAALgADCgMJAwAAAA==.Arvad:BAAALgADCgUJBQABLgAECggJHgABADMgAA==.',
As='Ashknight:BAABLgAECn8VAAIDAAcJugawYQDjAAADAAcJugawYQDjAAAAAA==.',
Au='Auroralights:BAAALgAECgEJAQAAAA==.',
Az='Azriel:BAAALgADCgkJCQAAAA==.',
Ba='Babyjeebus:BAAALgAECgQJBAAAAA==.Bagged:BAAALgAECgcJEgAAAA==.Balzak:BAAALgADCgMJAwAAAA==.Bastas:BAABLgAECn8fAAIEAAkJLBcqJwAaAgAEAAkJLBcqJwAaAgAAAA==.',
Be='Beastley:BAAALgADCgcJBwAAAA==.Beekro:BAACLgAFFH8KAAIFAAQJ9RxMCQBlAQAFAAQJ9RxMCQBlAQAuAAQKfykAAgUACAlaI2MIAPICAAUACAlaI2MIAPICAAAA.Belaen:BAABLgAECn8cAAIGAAcJwh/bDgDxAQAGAAcJwh/bDgDxAQAAAA==.Belarina:BAAALgAECgYJBgABLgAFFAQJCgAHAHwVAA==.Belatink:BAACLgAFFH8KAAMHAAQJfBVJCgDpAAAHAAMJGBxJCgDpAAAIAAMJTAEBGgCBAAAuAAQKfykAAwcACAlsIE0JALcCAAcACAlsIE0JALcCAAgABwnvClgyAA4BAAAA.',
Bi='Bilando:BAAALgAECgYJDwAAAA==.',
Bl='Blueberry:BAAALgAECgEJAQAAAA==.Blàckbeard:BAABLgAECn8gAAIJAAgJBxPHCQDNAQAJAAgJBxPHCQDNAQAAAA==.',
Bo='Borden:BAAALgAECggJDwAAAA==.',
Br='Brutalize:BAAALgADCgcJCAAAAA==.',
Bu='Bustyvoidelf:BAAALgAECgQJBAAAAA==.Buttercup:BAACLgAFFH8KAAIEAAQJyh9VCQBqAQAEAAQJyh9VCQBqAQAuAAQKfyIAAgQACAkyIbESAKACAAQACAkyIbESAKACAAAA.',
Ch='Chainer:BAABLgAECn8UAAIKAAYJ9xJsMABPAQAKAAYJ9xJsMABPAQAAAA==.Chirios:BAAALgAECgYJDgAAAA==.',
Ck='Ckdeath:BAABLgAECn8UAAIDAAcJsxigKgCRAQADAAcJsxigKgCRAQAAAA==.Ckwarlock:BAAALgAECgIJAgAAAA==.',
Cl='Clam:BAAALgAECgEJAQABLgAFFAEJAgACAAAAAA==.',
Cr='Crash:BAEALgAECgEJAgABLgAFFAMJBQALAPMWAA==.',
Cu='Cursén:BAABLgAECn8qAAQMAAgJcBrtFwDoAQAMAAgJcBrtFwDoAQANAAIJXQ+pIABvAAAOAAEJigcedwAtAAAAAA==.',
Cy='Cyristrasza:BAAALgADCgkJBgAAAA==.',
Da='Dacker:BAAALgADCgUJBQAAAA==.Daelen:BAAALgADCgkJCQABLgAFFAEJAgACAAAAAQ==.Darlocke:BAABLgAECn8UAAIPAAYJPBaUBQBlAQAPAAYJPBaUBQBlAQAAAA==.Darwin:BAAALgADCgIJAgAAAA==.Daysforsand:BAAALgAECgEJAQAAAA==.',
De='Deathmurk:BAABLgAECn8fAAIDAAgJKhWKSAAaAgADAAgJKhWKSAAaAgAAAA==.Deathstyck:BAAALgADCgcJBwABLgADCgcJBwACAAAAAA==.',
Di='Dimblederf:BAAALgADCgMJAwAAAA==.Divinesteez:BAAALgAECgMJBQABLgAECgYJDwACAAAAAA==.',
Do='Doomentia:BAABLgAECn8WAAMQAAcJbw3zJQBHAQAQAAcJbw3zJQBHAQAFAAYJtgnlJQDaAAAAAA==.',
Dr='Drezzarnbez:BAAALgAECgcJEAAAAA==.Drimdor:BAAALgAECgIJAgAAAA==.Druìdfluid:BAAALgADCgYJBgAAAA==.',
Du='Durgrim:BAACLgAFFH8GAAIRAAMJIhsJBADBAAARAAMJIhsJBADBAAAuAAQKfx4AAhEACAm1IeQDAOoCABEACAm1IeQDAOoCAAAA.',
Dw='Dwuiduwu:BAAALgADCgMJAwAAAA==.',
Ed='Edine:BAAALgAECgMJBgAAAA==.',
Ee='Eeèva:BAAALgAECgYJCAAAAA==.',
Ef='Efah:BAAALgAECgUJCAAAAA==.',
Ep='Epoxxy:BAAALgADCgkJCQAAAA==.',
Es='Espresso:BAACLgAFFH8KAAISAAQJJhwMBABzAQASAAQJJhwMBABzAQAuAAQKfyMAAhIACQlCIqQAADIDABIACQlCIqQAADIDAAAA.',
Ex='Exvo:BAAALgADCgQJBAAAAA==.',
Fe='Fellbent:BAAALgAECgEJAQABLgAECgYJDwACAAAAAA==.',
Fh='Fhtagnglui:BAAALgADCgYJBwABLgAFFAEJAgACAAAAAQ==.',
Fr='Freddiemerc:BAAALgADCgYJBgAAAA==.Frogspawn:BAAALgADCgEJAQAAAA==.',
Fu='Furrywar:BAAALgAECgEJAQABLgAECggJGAAKANQkAA==.',
Ga='Gaartak:BAACLgAFFH8IAAIDAAMJziQAJAAtAQADAAMJziQAJAAtAQAuAAQKfx8AAgMACAmwIyYPACMDAAMACAmwIyYPACMDAAAA.',
Ge='Gengar:BAAALgAECggJEgAAAA==.Geto:BAAALgADCgYJBwAAAA==.',
Gi='Girlypop:BAAALgADCgQJBAAAAA==.Gith:BAAALgAECgEJAQAAAA==.Githlock:BAABLgAECn8YAAQNAAgJIhKqBwDXAQANAAcJ7ROqBwDXAQAOAAUJJwdrNwDYAAAMAAIJTgjItQAyAAAAAA==.Githpriest:BAAALgADCgcJBwAAAA==.',
Gl='Gluegun:BAABLgAECn8UAAMTAAkJRRm/HgAtAgATAAgJCRi/HgAtAgAKAAEJ7yGldQBnAAAAAA==.',
Go='Gondo:BAAALgAECgUJBQABLgAFFAMJCAAKAKUXAA==.Goodberry:BAAALgADCgYJBgAAAA==.',
Gr='Griselbrand:BAAALgAECgMJAwAAAA==.Grogrin:BAACLgAFFH8GAAMUAAMJVRKDCgDUAAAUAAMJVRKDCgDUAAAVAAIJpAhxGgCjAAAuAAQKfycAAxUACAkyG+4MAOEBABUACAkyG+4MAOEBABQAAwlqDlo9AGIAAAAA.',
Gu='Gunnlaugr:BAAALgADCgYJBgAAAA==.',
Ha='Haleb:BAAALgADCgYJBgAAAA==.Harlíequinn:BAAALgAECgYJEQAAAA==.Harmacist:BAAALgAECgYJEwAAAA==.',
He='Hex:BAAALgAECgYJDQABLgAFFAMJBQAHAFYXAA==.',
Hi='Hitmonlee:BAAALgAECgIJAgABLgAFFAYJGgAFAGAgAA==.',
Ho='Hobstwo:BAAALgADCgEJAQAAAA==.Hoofhearted:BAAALgAECgIJAgAAAA==.Houtoku:BAAALgAFFAEJAgAAAQ==.Hozi:BAABLgAECn8uAAQDAAgJhh76DQBTAgADAAgJhh76DQBTAgAWAAMJQA39PABfAAAXAAEJHwcuGQAqAAAAAA==.',
Hp='Hpnosis:BAABLgAECn8WAAIBAAcJ+xBVSgArAQABAAcJ+xBVSgArAQAAAA==.',
Hu='Hunterin:BAABLgAECn8YAAMKAAgJ1CSJDADcAgAKAAcJxCSJDADcAgATAAMJryLISgAmAQAAAA==.Huntington:BAAALgAECgEJAQAAAA==.',
Il='Illidanmello:BAACLgAFFH8HAAILAAQJ8A+mGQAMAQALAAQJ8A+mGQAMAQAuAAQKfyQAAwsACAm6H64fAJMCAAsACAm6H64fAJMCABgAAwnqD/xSAJ0AAAAA.',
Im='Imtrying:BAACLgAFFH8KAAIZAAQJRQrREQACAQAZAAQJRQrREQACAQAuAAQKfykAAhkACAnNEwgrAOEBABkACAnNEwgrAOEBAAAA.',
Is='Isolet:BAAALgAECgUJBgAAAA==.',
Ja='Jayaegis:BAAALgADCgUJBgAAAA==.Jayaesir:BAAALgADCgEJAQAAAA==.Jayal:BAABLgAECn8eAAIBAAgJUBKWJACyAQABAAgJUBKWJACyAQAAAA==.',
Je='Jessïe:BAAALgAECgUJCAAAAA==.',
Jo='Joja:BAABLgAECn8WAAIaAAgJZReLCgACAgAaAAgJZReLCgACAgAAAA==.',
Ka='Kaizen:BAAALgAECgUJBQAAAA==.Katbelle:BAACLgAFFH8JAAIbAAQJzQaOAAARAQAbAAQJzQaOAAARAQAuAAQKfyYAAhsACAmbGTwBAOgBABsACAmbGTwBAOgBAAAA.',
Ke='Keyi:BAAALgADCgcJBwABLgADCgcJBwACAAAAAA==.Keynallan:BAAALgAECgQJBAAAAA==.',
Ki='Kinkykelly:BAACLgAFFH8LAAILAAUJEBJKCgCIAQALAAUJEBJKCgCIAQAuAAQKfxcAAgsACAmrINolAG8CAAsACAmrINolAG8CAAAA.',
Kl='Kloo:BAAALgAECgEJAQAAAA==.',
Kr='Krugidan:BAAALgAECgQJCwAAAA==.',
['Kú']='Kúsh:BAAALgAECgQJBwAAAA==.',
['Kü']='Küsh:BAAALgAECggJEwAAAA==.',
Le='Leof:BAAALgAECgEJAQABLgAFFAMJBgARACIbAA==.Leshwi:BAAALgAECgUJCQABLgAECgYJDwACAAAAAA==.',
Li='Liltimmyp:BAAALgADCgEJAQAAAA==.Littlelam:BAACLgAFFH8KAAIDAAMJkx9cKAAbAQADAAMJkx9cKAAbAQAuAAQKfywAAgMACAlUI7YTAAUDAAMACAlUI7YTAAUDAAAA.',
Lo='Locknar:BAAALgADCgYJBgABLgAECgUJCAACAAAAAA==.Lockybowboa:BAAALgAECgMJAwAAAA==.Locrock:BAAALgAECgEJAQAAAA==.Loken:BAAALgAECgkJCAAAAA==.Lorkhan:BAAALgAECggJEwAAAA==.',
Lt='Ltcclover:BAAALgAECgQJCAAAAA==.',
Ma='Maledict:BAABLgAECn8VAAILAAcJkwYVgwAiAQALAAcJkwYVgwAiAQAAAA==.Malgan:BAAALgADCgEJAQABLgAFFAEJAgACAAAAAQ==.Manhattan:BAAALgAECgcJDwABLgAFFAQJCgASACYcAA==.Martini:BAAALgAECgQJBgABLgAFFAQJCgASACYcAA==.',
Me='Meko:BAAALgAECgUJBgAAAA==.Merikaya:BAAALgAECgQJBAAAAA==.Meèko:BAAALgAECgcJCgAAAA==.Meéko:BAAALgADCgQJBAAAAA==.',
Mi='Miau:BAAALgADCgcJBwAAAA==.Mistafridge:BAAALgADCgcJCAABLgAECgYJDwACAAAAAA==.',
Mo='Monkedor:BAAALgADCgIJAgAAAA==.Moocelee:BAAALgAECgQJCAAAAA==.',
Mu='Murk:BAAALgADCgkJDQABLgAECggJHwADACoVAA==.Murloc:BAAALgADCgEJAQAAAA==.',
Na='Nah:BAAALgADCgcJBwAAAA==.Nahshadah:BAAALgADCggJCAAAAA==.Nanome:BAAALgAECgYJDwAAAA==.Nazure:BAAALgAECgEJAQAAAA==.',
Ne='Nedra:BAAALgADCgEJAQABLgADCgEJAgACAAAAAA==.Nesral:BAABLgAECn8WAAIKAAcJ+RbCJwAaAgAKAAcJ+RbCJwAaAgAAAA==.Nevoir:BAAALgAECggJCQAAAA==.',
Nh='Nhasir:BAACLgAFFH8KAAIWAAQJkRAWCQAKAQAWAAQJkRAWCQAKAQAuAAQKfx8AAhYACAloISIHAL4CABYACAloISIHAL4CAAAA.Nhastea:BAAALgAECgcJEgABLgAFFAQJCgAWAJEQAA==.',
Ni='Niceneasy:BAAALgAECgMJAwAAAA==.',
No='Normal:BAAALgAECgMJAwAAAA==.Nowaifu:BAAALgAECgEJAQAAAA==.',
Od='Odrade:BAAALgADCgIJAgABLgADCgIJAgACAAAAAA==.',
Ow='Owlbread:BAAALgAECggJEwAAAA==.',
Oz='Ozwin:BAAALgAECgYJDwAAAA==.',
Pe='Peccator:BAACLgAFFH8FAAIHAAMJVhctCgDtAAAHAAMJVhctCgDtAAAuAAQKfxoAAgcACAk8JFYBACYDAAcACAk8JFYBACYDAAAA.Pein:BAAALgADCgIJAgAAAA==.Percdirty:BAAALgADCgUJCAAAAA==.',
Ph='Phatality:BAEALgAECgMJCQABLgAECgQJBQACAAAAAA==.',
Pi='Pillowpants:BAAALgADCgcJBwAAAA==.',
Pl='Plat:BAAALgAECgEJAQAAAA==.Platsearthen:BAAALgAECgYJDgAAAA==.Ploo:BAAALgADCgcJAQAAAA==.',
Pn='Pneumma:BAAALgAECgcJBwAAAA==.',
Pr='Priya:BAAALgAECgYJCgAAAA==.Protect:BAAALgAECgMJBAABLgAFFAMJCAAKAKUXAA==.Prya:BAAALgAECgEJAgABLgAECggJFgAaAGUXAA==.Pròm:BAAALgAECgIJAQAAAA==.',
Ra='Ramordis:BAAALgADCgEJAQAAAA==.Ravia:BAABLgAECn8XAAIcAAcJDhyiBwALAgAcAAcJDhyiBwALAgAAAA==.',
Re='Rebyen:BAAALgADCgYJBQAAAA==.Regularhorns:BAABLgAECn8WAAILAAcJiw/UMQAcAQALAAcJiw/UMQAcAQAAAA==.Rendhoof:BAAALgAECgEJAgAAAA==.Reptarr:BAAALgADCgYJBQABLgAECgYJDwACAAAAAA==.Restodruid:BAAALgAECgQJBAAAAA==.Rev:BAAALgADCgQJCAAAAA==.',
Ri='Richter:BAAALgADCgkJCQAAAA==.Rins:BAAALgAECgYJCwABLgAECggJGAAKANQkAA==.Rinslet:BAAALgAECgYJCgABLgAECggJGAAKANQkAA==.Riskante:BAABLgAECn8jAAMBAAgJ6Rt3EQAvAgABAAgJ6Rt3EQAvAgAGAAUJ2w/qWwANAQAAAA==.',
Ro='Roonrana:BAAALgAECgMJBQAAAA==.Rosey:BAACLgAFFH8HAAIdAAMJOA+kAgDsAAAdAAMJOA+kAgDsAAAuAAQKfycAAh0ACAnhHokBAMMCAB0ACAnhHokBAMMCAAAA.',
Ru='Rulutieh:BAAALgAECgMJBgAAAA==.Runebraker:BAAALgAECgYJCwAAAA==.',
Sa='Sandfordays:BAAALgAECgMJBgAAAA==.Sardor:BAAALgAECgQJCAAAAA==.',
Sc='Scorn:BAAALgAECggJDwAAAA==.Scottyno:BAABLgAECn8eAAIBAAkJZx6mEQAtAgABAAkJZx6mEQAtAgAAAA==.',
Se='Sempast:BAABLgAECn8jAAMMAAcJSiMwFgD0AQAMAAYJzSIwFgD0AQAOAAQJ3yJnGQCAAQAAAA==.',
Sh='Shadyfear:BAAALgAECgEJAQAAAA==.Shaldin:BAAALgAECgcJDwAAAA==.Shaluesta:BAAALgAECgMJBAAAAA==.Shaluestaa:BAAALgAECgcJBwAAAA==.Shanithell:BAAALgADCgIJAgAAAA==.Shanksz:BAAALgAECgIJAwAAAA==.Shellyd:BAABLgAECn8YAAIVAAgJaxLWEACzAQAVAAgJaxLWEACzAQAAAA==.Shiryû:BAAALgADCgEJAQAAAA==.',
Si='Siennaa:BAAALgAECgIJAgAAAA==.Sinfulsmite:BAAALgADCgEJAQABLgAECgQJCgACAAAAAA==.Sins:BAACLgAFFH8NAAQDAAUJiBYXFgBLAQADAAQJMxUXFgBLAQAXAAMJ5xDhAgD8AAAWAAEJAABOJgAAAAAuAAQKfxYAAgMACAmFHxEpAJYCAAMACAmFHxEpAJYCAAAA.',
Sl='Slide:BAAALgAECgYJBgAAAA==.',
Sn='Sneakyhand:BAACLgAFFH8KAAMeAAQJ3R4IAgCEAQAeAAQJ4RwIAgCEAQAVAAIJFSFfFQDKAAAuAAQKfygAAxUACAloJhwEAGoDABUACAn7JRwEAGoDAB4ABAlMIyQHAKMBAAAA.',
So='Soupson:BAAALgADCgIJAgABLgAECgYJEAACAAAAAA==.',
St='Steelt:BAAALgAECgYJCQAAAA==.Steris:BAAALgAECgYJDwAAAA==.Stinkindwarf:BAAALgAECgQJBAAAAA==.Stizzy:BAAALgAECgIJAgAAAA==.',
Su='Sunadora:BAAALgAECgEJAwAAAA==.',
Sw='Swagula:BAABLgAECn8WAAIfAAcJRyPhAgBJAgAfAAcJRyPhAgBJAgAAAA==.',
Sy='Sylvain:BAAALgAECgEJAQABLgAECggJIQAgADofAA==.Sylvi:BAAALgAECggJEwAAAA==.Syrup:BAAALgADCgkJCQAAAA==.Syurni:BAAALgADCgEJAgAAAA==.',
Ta='Takitsu:BAACLgAFFH8IAAIhAAMJggbhBQCPAAAhAAMJggbhBQCPAAAuAAQKfx4AAiEACAkWDrkRAFkBACEACAkWDrkRAFkBAAAA.',
Th='Tharion:BAAALgADCgcJBwAAAA==.',
Ti='Tinyfist:BAAALgADCgYJBgAAAA==.Tired:BAAALgADCgEJAgAAAA==.',
To='Tombz:BAABLgAECn80AAMDAAgJICG8HgDIAgADAAgJICG8HgDIAgAWAAIJNQIHRgAwAAAAAA==.Towa:BAAALgAECgMJBAAAAA==.',
Tr='Trilira:BAAALgADCgUJBwAAAA==.',
Tu='Turf:BAAALgADCgMJAgAAAA==.',
Ul='Ulangi:BAAALgADCgMJAgAAAA==.',
Un='Unbelavable:BAAALgAECgYJBwAAAA==.',
Ur='Uranis:BAAALgADCgEJAgAAAA==.Uroboros:BAAALgADCgEJAQAAAA==.Ursa:BAAALgAECgYJCgAAAA==.',
Ve='Veil:BAAALgAECgYJBwABLgAECgcJIwAMAEojAA==.',
Vl='Vlorax:BAAALgADCgMJBgAAAA==.',
Vo='Volodinson:BAAALgAECgQJCAAAAA==.',
Vy='Vynesh:BAAALgADCgEJAwAAAA==.',
Wa='Wallê:BAAALgAECgEJAQAAAA==.Wandwanker:BAAALgAECgcJEgAAAA==.Warsawz:BAAALgAECgEJAQAAAA==.',
We='Wetasscat:BAAALgAFFAEJAgAAAA==.Weyae:BAAALgAECgMJBAAAAA==.',
Wh='Whorg:BAACLgAFFH8IAAIKAAMJpRcjGAAFAQAKAAMJpRcjGAAFAQAuAAQKfysAAwoACAljH8EMADkCAAoACAndHMEMADkCACIABglHHOoSAJQBAAAA.',
Wi='Willyboi:BAAALgAECgYJDwAAAA==.Wisemanorc:BAAALgAECgMJBQAAAA==.',
Xa='Xavierr:BAAALgAECgYJEQAAAA==.',
Ya='Yarkaz:BAAALgADCgcJBwAAAA==.',
Yi='Yinli:BAAALgAECgEJAQAAAA==.',
Za='Zaai:BAAALgADCgcJCgAAAA==.Zargus:BAABLgAECn8hAAIgAAgJOh9bEQCWAQAgAAgJOh9bEQCWAQAAAA==.Zarlunce:BAABLgAECn8ZAAIVAAcJmhzxHgBZAgAVAAcJmhzxHgBZAgAAAA==.',
Ze='Zetsuon:BAABLgAECn8pAAIEAAkJXB77AgASAwAEAAkJXB77AgASAwAAAA==.',
Zu='Zuk:BAAALgAECgcJDQAAAA==.',
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

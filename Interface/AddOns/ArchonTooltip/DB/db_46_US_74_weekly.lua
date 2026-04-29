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

local lookup = {'Unknown-Unknown','Paladin-Retribution','Druid-Restoration','Evoker-Augmentation','Paladin-Holy','Priest-Holy','Priest-Discipline','Rogue-Subtlety','DemonHunter-Devourer','Warlock-Demonology','Warlock-Affliction','Warlock-Destruction','DeathKnight-Unholy','Shaman-Enhancement','Priest-Shadow','Hunter-BeastMastery','Warrior-Fury','Warrior-Protection','DeathKnight-Blood','DeathKnight-Frost','Hunter-Marksmanship','DemonHunter-Havoc','Shaman-Restoration','Mage-Fire','DemonHunter-Vengeance','Rogue-Outlaw','Warrior-Arms','Shaman-Elemental','Druid-Guardian','Hunter-Survival',}
local provider = {region='US',realm="Drak'Tharon",name='US',type='weekly',zone=46,date='2026-04-24',data={Ad='Adorah:BAAALgAECgcJDQAAAA==.',
Al='Allyia:BAAALgADCgEJAgABLgADCgEJAgABAAAAAA==.Alucarde:BAAALgAECgYJDQAAAA==.',
Ar='Arator:BAAALgADCgYJBQAAAA==.Artelios:BAAALgADCgMJAwAAAA==.Arvad:BAAALgADCgUJBQABLgAECggJFgACABoaAA==.',
As='Ashknight:BAAALgAECgYJDwAAAA==.',
Au='Auroralights:BAAALgAECgEJAQAAAA==.',
Az='Azriel:BAAALgADCgkJCQAAAA==.',
Ba='Bagged:BAAALgAECgcJEgAAAA==.Balzak:BAAALgADCgMJAwAAAA==.Bastas:BAABLgAECn8cAAIDAAgJ/RcmJwAaAgADAAgJ/RcmJwAaAgAAAA==.',
Be='Beastley:BAAALgADCgcJBwAAAA==.Beekro:BAACLgAFFH8GAAIEAAMJ9xndBwADAQAEAAMJ9xndBwADAQAuAAQKfyUAAgQACAmbIWAIAPMCAAQACAmbIWAIAPMCAAAA.Belaen:BAABLgAECn8VAAIFAAYJnh+PHwAdAgAFAAYJnh+PHwAdAgAAAA==.Belarina:BAAALgADCgYJBgABLgAFFAMJBgAGANkZAA==.Belatink:BAACLgAFFH8GAAMGAAMJ2RnOAwDfAAAGAAMJ2RnOAwDfAAAHAAEJbgC1HAAzAAAuAAQKfyUAAwYACAlsIEwJALcCAAYACAlsIEwJALcCAAcABwkGA1QyAA4BAAAA.',
Bi='Bilando:BAAALgAECgYJDwAAAA==.',
Bl='Blueberry:BAAALgAECgEJAQAAAA==.Blàckbeard:BAABLgAECn8fAAIIAAgJCxLtAwDSAQAIAAgJCxLtAwDSAQAAAA==.',
Bo='Borden:BAAALgAECgcJDAAAAA==.',
Br='Brutalize:BAAALgADCgcJBwAAAA==.',
Bu='Bustyvoidelf:BAAALgAECgQJBAAAAA==.Buttercup:BAACLgAFFH8GAAIDAAMJjhvBBwDpAAADAAMJjhvBBwDpAAAuAAQKfx4AAgMACAn5ILQSAKACAAMACAn5ILQSAKACAAAA.',
Ch='Chainer:BAAALgAECgUJDgAAAA==.Chirios:BAAALgAECgYJDgAAAA==.',
Ck='Ckdeath:BAAALgAFFAEJAQAAAA==.Ckwarlock:BAAALgAECgIJAgAAAA==.',
Cr='Crash:BAEALgAECgEJAgABLgAECggJHwAJAFsjAA==.',
Cu='Cursén:BAABLgAECn8pAAQKAAgJ5xk7CADuAQAKAAgJ5xk7CADuAQALAAIJXQ+qIABvAAAMAAEJigcZdwAtAAAAAA==.',
Cy='Cyristrasza:BAAALgADCgkJBgAAAA==.',
Da='Dacker:BAAALgADCgUJBQAAAA==.Daelen:BAAALgADCgkJCQABLgAECgcJFgABAAAAAQ==.Darlocke:BAAALgAECgUJDgAAAA==.Darwin:BAAALgADCgIJAgAAAA==.Daysforsand:BAAALgAECgEJAQAAAA==.',
De='Deathmurk:BAABLgAECn8dAAINAAgJARSKSAAaAgANAAgJARSKSAAaAgAAAA==.Deathstyck:BAAALgADCgcJBwABLgADCgcJBwABAAAAAA==.',
Di='Dimblederf:BAAALgADCgMJAwAAAA==.Divinesteez:BAAALgAECgMJBQABLgAECgUJCQABAAAAAA==.',
Do='Doomentia:BAAALgAECgcJDwAAAA==.',
Dr='Drezzarnbez:BAAALgAECgIJCAAAAA==.Drimdor:BAAALgAECgIJAgAAAA==.Druìdfluid:BAAALgADCgYJBgAAAA==.',
Du='Durgrim:BAABLgAECn8dAAIOAAgJuSDkAwDqAgAOAAgJuSDkAwDqAgAAAA==.',
Dw='Dwuiduwu:BAAALgADCgMJAwAAAA==.',
Ed='Edine:BAAALgAECgMJBgAAAA==.',
Ee='Eeèva:BAAALgADCggJDwAAAA==.',
Ef='Efah:BAAALgAECgUJCAAAAA==.',
Ep='Epoxxy:BAAALgADCgkJCQAAAA==.',
Es='Espresso:BAACLgAFFH8FAAIPAAMJBxkVBQD2AAAPAAMJBxkVBQD2AAAuAAQKfxsAAg8ACAmTIvwAAJsCAA8ACAmTIvwAAJsCAAAA.',
Fe='Fellbent:BAAALgAECgEJAQABLgAECgUJCQABAAAAAA==.',
Fr='Freddiemerc:BAAALgADCgYJBgAAAA==.Frogspawn:BAAALgADCgEJAQAAAA==.',
Fu='Furrywar:BAAALgAECgEJAQABLgAECggJFwAQANQkAA==.',
Ga='Gaartak:BAACLgAFFH8FAAINAAIJtSPbEgDHAAANAAIJtSPbEgDHAAAuAAQKfx4AAg0ACAmwIyIPACMDAA0ACAmwIyIPACMDAAAA.',
Ge='Gengar:BAAALgAECgcJCgAAAA==.Geto:BAAALgADCgYJBwAAAA==.',
Gi='Girlypop:BAAALgADCgQJBAAAAA==.Gith:BAAALgAECgEJAQAAAA==.Githlock:BAABLgAECn8XAAQLAAgJIhKtBwDXAQALAAcJ7ROtBwDXAQAMAAUJJwdpNwDYAAAKAAEJsQcIJwEqAAAAAA==.Githpriest:BAAALgADCgcJBwAAAA==.',
Gl='Gluegun:BAAALgAFFAEJAQAAAA==.',
Go='Gondo:BAAALgADCgEJAgABLgAFFAMJBQAQAJwMAA==.Goodberry:BAAALgADCgYJBgAAAA==.',
Gr='Griselbrand:BAAALgAECgMJAwAAAA==.Grogrin:BAABLgAECn8gAAMRAAgJ4Re7GwBvAgARAAgJ4Re7GwBvAgASAAIJCgtVPQBiAAAAAA==.',
Gu='Gunnlaugr:BAAALgADCgYJBgAAAA==.',
Ha='Haleb:BAAALgADCgYJBgAAAA==.Harlíequinn:BAAALgAECgUJCwAAAA==.Harmacist:BAAALgAECgUJBwAAAA==.',
He='Hex:BAAALgAECgYJDQABLgAECggJFQAGADwkAA==.',
Ho='Hobstwo:BAAALgADCgEJAQAAAA==.Hoofhearted:BAAALgAECgIJAgAAAA==.Houtoku:BAAALgAECgcJFgAAAQ==.Hozi:BAABLgAECn8oAAQNAAgJ3xdZCAD5AQANAAgJ3xdZCAD5AQATAAIJixgBPQBfAAAUAAEJHwcpGQAqAAAAAA==.',
Hp='Hpnosis:BAAALgAECgcJDwAAAA==.',
Hu='Hunterin:BAABLgAECn8XAAMQAAgJ1CSLDADcAgAQAAcJxCSLDADcAgAVAAMJryLNSgAmAQAAAA==.Huntington:BAAALgAECgEJAQAAAA==.',
Il='Illidanmello:BAACLgAFFH8FAAIJAAMJ2hMHDAD/AAAJAAMJ2hMHDAD/AAAuAAQKfyQAAwkACAlTH6ofAJMCAAkACAlTH6ofAJMCABYAAwnqD/5SAJ0AAAAA.',
Im='Imtrying:BAACLgAFFH8GAAIXAAMJoAo1CADRAAAXAAMJoAo1CADRAAAuAAQKfyUAAhcACAl5EwcrAOEBABcACAl5EwcrAOEBAAAA.',
Is='Isolet:BAAALgAECgEJAQAAAA==.',
Ja='Jayaegis:BAAALgADCgUJBgAAAA==.Jayaesir:BAAALgADCgEJAQAAAA==.Jayal:BAABLgAECn8XAAICAAgJihHTEQCUAQACAAgJihHTEQCUAQAAAA==.',
Je='Jessïe:BAAALgAECgUJCAAAAA==.',
Jo='Joja:BAAALgAECgYJEwAAAA==.',
Ka='Kaizen:BAAALgAECgUJBQAAAA==.Katbelle:BAACLgAFFH8FAAIYAAMJDAhWAAC7AAAYAAMJDAhWAAC7AAAuAAQKfx0AAhgACAmpE/sCAP0BABgACAmpE/sCAP0BAAAA.',
Ke='Keynallan:BAAALgAECgQJBAAAAA==.',
Ki='Kinkykelly:BAACLgAFFH8LAAIJAAUJEBJKCgCIAQAJAAUJEBJKCgCIAQAuAAQKfxkAAgkACAmsINIlAG8CAAkACAmsINIlAG8CAAAA.',
Kl='Kloo:BAAALgAECgEJAQAAAA==.',
Kr='Krugidan:BAAALgAECgQJCgAAAA==.',
['Kú']='Kúsh:BAAALgAECgQJBwAAAA==.',
['Kü']='Küsh:BAAALgAECggJEwAAAA==.',
Le='Leof:BAAALgAECgEJAQABLgAECggJHQAOALkgAA==.Leshwi:BAAALgAECgQJBgABLgAECgYJDgABAAAAAA==.',
Li='Liltimmyp:BAAALgADCgEJAQAAAA==.Littlelam:BAACLgAFFH8HAAINAAMJlReTDQAIAQANAAMJlReTDQAIAQAuAAQKfygAAg0ACAkzI7ETAAUDAA0ACAkzI7ETAAUDAAAA.',
Lo='Locknar:BAAALgADCgYJBgABLgAECgUJCAABAAAAAA==.Lockybowboa:BAAALgAECgMJAwAAAA==.Locrock:BAAALgAECgEJAQAAAA==.Lorkhan:BAAALgAECgcJEAAAAA==.',
Lt='Ltcclover:BAAALgAECgQJBAAAAA==.',
Ma='Maledict:BAABLgAECn8VAAIJAAcJkwYSgwAiAQAJAAcJkwYSgwAiAQAAAA==.Malgan:BAAALgADCgEJAQABLgAECgcJFgABAAAAAQ==.Manhattan:BAAALgAECgcJDwABLgAFFAMJBQAPAAcZAA==.Martini:BAAALgAECgQJBQABLgAFFAMJBQAPAAcZAA==.',
Me='Meèko:BAAALgAECgcJCgAAAA==.Meéko:BAAALgADCgQJBAAAAA==.',
Mi='Miau:BAAALgADCgcJBwAAAA==.Mistafridge:BAAALgADCgcJCAABLgAECgUJCQABAAAAAA==.',
Mo='Monkedor:BAAALgADCgIJAgAAAA==.Moocelee:BAAALgAECgQJBgAAAA==.',
Mu='Murk:BAAALgADCgkJDQABLgAECggJHQANAAEUAA==.Murloc:BAAALgADCgEJAQAAAA==.',
Na='Nahshadah:BAAALgADCggJCAAAAA==.Nanome:BAAALgAECgUJCQAAAA==.Nazure:BAAALgADCgcJCAAAAA==.',
Ne='Nedra:BAAALgADCgEJAQABLgADCgEJAgABAAAAAA==.Nesral:BAAALgAECgcJDwAAAA==.Nevoir:BAAALgAECggJCAAAAA==.',
Nh='Nhasir:BAACLgAFFH8GAAITAAMJHBSKBQC/AAATAAMJHBSKBQC/AAAuAAQKfxsAAhMACAknICAHAL4CABMACAknICAHAL4CAAAA.Nhastea:BAAALgAECgYJCwABLgAFFAMJBgATABwUAA==.',
Ni='Niceneasy:BAAALgAECgMJAwAAAA==.',
No='Normal:BAAALgAECgMJAwAAAA==.Nowaifu:BAAALgAECgEJAQAAAA==.',
Od='Odrade:BAAALgADCgIJAgABLgADCgIJAgABAAAAAA==.',
Ow='Owlbread:BAAALgAECgcJEAAAAA==.',
Oz='Ozwin:BAAALgAECgMJAwAAAA==.',
Pe='Peccator:BAABLgAECn8VAAIGAAgJPCRVAAArAwAGAAgJPCRVAAArAwAAAA==.Pein:BAAALgADCgIJAgAAAA==.Percdirty:BAAALgADCgUJCAAAAA==.',
Ph='Phatality:BAEALgAECgMJBgABLgAECgQJBQABAAAAAA==.',
Pi='Pillowpants:BAAALgADCgcJBwAAAA==.',
Pl='Plat:BAAALgAECgEJAQAAAA==.Platsearthen:BAAALgAECgUJCAAAAA==.Ploo:BAAALgADCgcJAQAAAA==.',
Pn='Pneumma:BAAALgAECgcJBwAAAA==.',
Pr='Priya:BAAALgAECgQJBAAAAA==.Protect:BAAALgAECgMJBAABLgAFFAMJBQAQAJwMAA==.Prya:BAAALgAECgEJAQABLgAECgYJEwABAAAAAA==.Pròm:BAAALgAECgIJAQAAAA==.',
Ra='Ramordis:BAAALgADCgEJAQAAAA==.Ravia:BAABLgAECn8XAAIZAAcJDhyjBwALAgAZAAcJDhyjBwALAgAAAA==.',
Re='Rebyen:BAAALgADCgYJBQAAAA==.Regularhorns:BAAALgAECgcJDwAAAA==.Rendhoof:BAAALgAECgEJAgAAAA==.Reptarr:BAAALgADCgYJBQABLgAECgUJCQABAAAAAA==.Restodruid:BAAALgAECgQJBAAAAA==.Rev:BAAALgADCgQJBAAAAA==.',
Ri='Richter:BAAALgADCgkJCQAAAA==.Rins:BAAALgAECgYJCgABLgAECggJFwAQANQkAA==.Rinslet:BAAALgAECgMJAwABLgAECggJFwAQANQkAA==.Riskante:BAABLgAECn8bAAMCAAcJshyvDwCoAQACAAcJshyvDwCoAQAFAAUJ2w/wWwANAQAAAA==.',
Ro='Roonrana:BAAALgAECgMJBAAAAA==.Rosey:BAABLgAECn8jAAIaAAgJcx2JAQDDAgAaAAgJcx2JAQDDAgAAAA==.',
Ru='Rulutieh:BAAALgAECgMJBgAAAA==.Runebraker:BAAALgAECgUJBQAAAA==.',
Sa='Sandfordays:BAAALgAECgMJBgAAAA==.Sardor:BAAALgAECgQJCAAAAA==.',
Sc='Scorn:BAAALgAECgcJDAAAAA==.Scottyno:BAABLgAECn8YAAICAAgJtR7lJwCGAgACAAgJtR7lJwCGAgAAAA==.',
Se='Sempast:BAABLgAECn8eAAMMAAcJSiNsGQCAAQAMAAQJ3yJsGQCAAQAKAAUJ6yISGABRAQAAAA==.',
Sh='Shadyfear:BAAALgAECgEJAQAAAA==.Shaldin:BAAALgAECgYJCAAAAA==.Shaluesta:BAAALgAECgMJBAAAAA==.Shaluestaa:BAAALgAECgYJBgAAAA==.Shanithell:BAAALgADCgIJAgAAAA==.Shanksz:BAAALgAECgIJAwAAAA==.Shellyd:BAAALgAECgcJEQAAAA==.Shiryû:BAAALgADCgEJAQAAAA==.',
Si='Siennaa:BAAALgAECgIJAgAAAA==.Sinfulsmite:BAAALgADCgEJAQABLgAECgQJCgABAAAAAA==.Sins:BAACLgAFFH8NAAQNAAUJiBYRFgBLAQANAAQJMxURFgBLAQAUAAMJ5xCTAQAFAQATAAEJAAC7DwAAAAAuAAQKfxYAAg0ACAmFHwspAJYCAA0ACAmFHwspAJYCAAAA.',
Sl='Slide:BAAALgAECgEJAQAAAA==.',
Sn='Sneakyhand:BAACLgAFFH8GAAMRAAMJKyLKBwDMAAARAAIJFSHKBwDMAAAbAAEJVSRiBABuAAAuAAQKfyQAAhEACAn7JR0EAGoDABEACAn7JR0EAGoDAAAA.',
So='Soupson:BAAALgADCgIJAgABLgAECgYJEAABAAAAAA==.',
St='Steelt:BAAALgAECgMJAwAAAA==.Steris:BAAALgAECgYJDgAAAA==.Stinkindwarf:BAAALgAECgQJBAAAAA==.Stizzy:BAAALgAECgIJAgAAAA==.',
Su='Sunadora:BAAALgAECgEJAgAAAA==.',
Sw='Swagula:BAAALgAECgcJDwAAAA==.',
Sy='Sylvain:BAAALgAECgEJAQABLgAECggJGwAcAPgdAA==.Sylvi:BAAALgAECgcJEAAAAA==.Syrup:BAAALgADCgkJCQAAAA==.Syurni:BAAALgADCgEJAgAAAA==.',
Ta='Takitsu:BAACLgAFFH8FAAIdAAIJQQMGAwBaAAAdAAIJQQMGAwBaAAAuAAQKfx0AAh0ACAkWDrcRAFkBAB0ACAkWDrcRAFkBAAAA.',
Ti='Tinyfist:BAAALgADCgYJBgAAAA==.Tired:BAAALgADCgEJAgAAAA==.',
To='Tombz:BAABLgAECn8pAAMNAAgJQiA2BwANAgANAAgJQiA2BwANAgATAAIJNQIKRgAwAAAAAA==.Towa:BAAALgAECgMJBAAAAA==.',
Tr='Trilira:BAAALgADCgUJBwAAAA==.',
Tu='Turf:BAAALgADCgMJAgAAAA==.',
Un='Unbelavable:BAAALgAECgEJAQAAAA==.',
Ur='Uranis:BAAALgADCgEJAgAAAA==.Uroboros:BAAALgADCgEJAQAAAA==.Ursa:BAAALgAECgYJCgAAAA==.',
Ve='Veil:BAAALgAECgYJBwABLgAECgcJHgAMAEojAA==.',
Vo='Volodinson:BAAALgAECgQJBAAAAA==.',
Vy='Vynesh:BAAALgADCgEJAwAAAA==.',
Wa='Wallê:BAAALgADCggJEAAAAA==.Wandwanker:BAAALgAECgYJCwAAAA==.Warsawz:BAAALgAECgEJAQAAAA==.',
We='Wetasscat:BAAALgAECgcJEAAAAA==.Weyae:BAAALgAECgMJBAAAAA==.',
Wh='Whorg:BAACLgAFFH8FAAIQAAMJnAz9DwCbAAAQAAMJnAz9DwCbAAAuAAQKfx8AAxAACAl1G8ZAAKwBABAACAnRF8ZAAKwBAB4ABglHHOkSAJQBAAAA.',
Wi='Willyboi:BAAALgAECgQJBwAAAA==.Wisemanorc:BAAALgAECgMJBQAAAA==.',
Xa='Xavierr:BAAALgAECgYJDQAAAA==.',
Yi='Yinli:BAAALgADCgQJBAAAAA==.',
Za='Zaai:BAAALgADCgcJCgAAAA==.Zargus:BAABLgAECn8bAAIcAAgJ+B0xCAB9AQAcAAgJ+B0xCAB9AQAAAA==.Zarlunce:BAABLgAECn8ZAAIRAAcJmhzzHgBZAgARAAcJmhzzHgBZAgAAAA==.',
Ze='Zetsuon:BAABLgAECn8jAAIDAAgJPh6IAgCTAgADAAgJPh6IAgCTAgAAAA==.',
Zu='Zuk:BAAALgAECgcJBwAAAA==.',
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

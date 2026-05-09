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

local lookup = {'Warlock-Demonology','Warlock-Destruction','DemonHunter-Devourer','Mage-Frost','Hunter-BeastMastery','Unknown-Unknown','DeathKnight-Unholy','DeathKnight-Blood','Shaman-Restoration','Shaman-Elemental','Evoker-Augmentation','Paladin-Retribution','Monk-Brewmaster','Hunter-Survival','Rogue-Assassination','Warrior-Fury','Warlock-Affliction','Paladin-Holy','Monk-Mistweaver','Mage-Fire','Paladin-Protection','Druid-Restoration','Evoker-Devastation','Rogue-Outlaw','Rogue-Subtlety','DemonHunter-Vengeance','Warrior-Protection','Warrior-Arms','Priest-Shadow','Priest-Discipline','Monk-Windwalker','Evoker-Preservation','Priest-Holy','DemonHunter-Havoc','Druid-Feral','Druid-Guardian','Hunter-Marksmanship','Shaman-Enhancement','Druid-Balance','Mage-Arcane',}
local provider = {region='US',realm='Stonemaul',name='US',type='weekly',zone=46,date='2026-05-08',data={Aa='Aannte:BAACLgAFFH8WAAMBAAcJyhf9BQDAAQABAAUJIhX9BQDAAQACAAQJ6Be2AgAsAQAuAAQKfyIAAwEACQlKIocmAHgCAAEACQk6IocmAHgCAAIABAnwHvUdAGABAAAA.Aardbark:BAAALgADCgEJAQAAAA==.',
Ac='Achtland:BAAALgAECgUJBgABLgAECgcJIAADAM8eAA==.',
Ad='Adekai:BAAALgAECgEJAwAAAA==.Adv:BAAALgAECgEJAQAAAA==.',
Ae='Aerestrix:BAAALgAECgUJBgAAAA==.',
Ai='Airvis:BAABLgAECn8XAAIEAAYJ/ARRmQDgAAAEAAYJ/ARRmQDgAAAAAA==.',
Al='Alacia:BAAALgAECgcJBwABLgAECggJLAAFAK8cAA==.Alatarr:BAAALgAECgYJCgAAAA==.Albinomonk:BAAALgADCgcJBwAAAA==.',
An='Anankei:BAAALgAECgMJAwAAAA==.Annastrophic:BAAALgADCgMJAwAAAA==.Anrí:BAAALgAECgEJAQAAAA==.Antaria:BAAALgADCgcJFgAAAA==.Ante:BAAALgADCgUJAQAAAA==.Antiform:BAAALgAECgIJBgAAAA==.Antpony:BAAALgAECgIJAgABLgAECgYJCgAGAAAAAA==.',
Ar='Arcish:BAAALgAECgEJAgAAAA==.Arjun:BAAALgAECgcJEAAAAA==.Arkirla:BAAALgAECgEJAgAAAA==.Arkiyra:BAAALgAECggJDAAAAA==.Arkosh:BAAALgAECgEJAQAAAA==.Arkyra:BAAALgAECgUJBwAAAA==.Arovix:BAAALgAECgcJDgAAAA==.',
As='Ashwey:BAAALgADCgkJCAAAAA==.',
At='Atom:BAAALgAECgYJBgAAAA==.',
Au='Aubreey:BAAALgADCgcJCQAAAA==.Aureille:BAAALgAECgYJCgAAAA==.',
Aw='Awoozehl:BAACLgAFFH8aAAMHAAYJFiAKFgB7AQAHAAUJFiAKFgB7AQAIAAEJAACVJQAAAAAuAAQKfzQAAgcACQmgJh8CALsDAAcACQmgJh8CALsDAAAA.',
Az='Azanoth:BAAALgAECgEJAQAAAA==.Azgrodon:BAABLgAECn8rAAMJAAkJTBYSDgBWAgAJAAkJTBYSDgBWAgAKAAMJjww2bACSAAAAAA==.Azor:BAABLgAECn8YAAIDAAgJch04HQCiAgADAAgJch04HQCiAgAAAA==.',
Ba='Baja:BAAALgAECgQJBAAAAA==.Baldomar:BAAALgADCgUJCAAAAA==.Bangungot:BAAALgADCgMJAwABLgAFFAgJGQALABAfAA==.Barzalie:BAAALgAECgYJDAABLgAFFAMJAwAGAAAAAA==.Bathrezz:BAABLgAECn8WAAIMAAgJAxUYOgCYAQAMAAgJAxUYOgCYAQAAAA==.',
Be='Beerbelly:BAAALgAFFAMJAwAAAA==.Beleaves:BAACLgAFFH8bAAINAAcJdQePBgBqAQANAAcJdQePBgBqAQAuAAQKfzYAAg0ACQmGFzgbACoCAA0ACQmGFzgbACoCAAAA.Belsnickel:BAAALgADCgYJCQAAAA==.Beorl:BAAALgADCgYJCAAAAA==.',
Bh='Bhackshots:BAABLgAECn8XAAIOAAUJjSEaFQBrAQAOAAUJjSEaFQBrAQABLgAECggJLAAPAG0iAA==.',
Bi='Bifurious:BAABLgAECn8WAAIQAAgJthlTJwAhAgAQAAgJthlTJwAhAgAAAA==.Bigrob:BAAALgAECgEJAQAAAA==.',
Bl='Blowmybubble:BAAALgADCgEJAQAAAA==.Bluereindeer:BAABLgAECn8VAAIHAAkJAguoLADIAQAHAAkJAguoLADIAQAAAA==.',
Bo='Bobsstones:BAACLgAFFH8TAAQBAAcJ/R7MAwDkAQABAAYJex3MAwDkAQACAAQJ6x0lBgANAQARAAEJoCW/BABrAAAuAAQKfyUABAIACQlCJT0GAGwCAAEABwkmI/4bAK0CAAIABgmDJD0GAGwCABEAAglDJOoVANUAAAAA.Bonekitty:BAAALgAECgYJBgAAAA==.Bonkulo:BAAALgAECgYJDAAAAA==.Boofassist:BAABLgAECn8VAAISAAgJ9yR/BAAmAwASAAgJ9yR/BAAmAwABLgAFFAYJFQATAIMWAA==.Boogey:BAABLgAECn8UAAMEAAYJzQxldQAmAQAEAAYJzQxldQAmAQAUAAEJpQiOEAAyAAAAAA==.Boompowwow:BAABLgAECn8VAAIKAAYJIxniNACDAQAKAAYJIxniNACDAQAAAA==.Boomsonic:BAAALgADCgUJBQABLgAECggJFgAQALYZAA==.Bophadeez:BAABLgAECn8lAAQSAAgJeB4vFQDmAQASAAcJGiEvFQDmAQAVAAgJghYOCADPAQAMAAYJvQ/NjABhAQAAAA==.',
Br='Broccoliz:BAECLgAFFH8bAAIWAAcJfxDxAgC9AQAWAAcJfxDxAgC9AQAuAAQKfzcAAhYACQkUH9IYAHECABYACQkUH9IYAHECAAAA.Brokgar:BAAALgAECggJEAAAAA==.Brotu:BAAALgADCgIJAQAAAA==.Bruceleroy:BAAALgADCgEJAQAAAA==.Brutalsmasch:BAAALgADCgUJBQAAAA==.',
Bu='Bubu:BAAALgAECgEJAQAAAA==.Bulis:BAAALgAECgEJAQAAAA==.Bullblaster:BAAALgAECgEJAQAAAA==.',
Bw='Bwonshamdi:BAAALgAECgcJBwABLgAECgcJBwAGAAAAAA==.',
['Bõ']='Bõb:BAAALgAECgMJBQAAAA==.',
Ca='Cafca:BAABLgAECn8nAAICAAgJYRckAwD+AQACAAgJYRckAwD+AQAAAA==.Caitlin:BAAALgAECgEJAQABLgAFFAQJBwAFALcRAA==.Callyour:BAAALgADCgIJAgAAAA==.Cask:BAAALgADCgYJAQAAAA==.',
Ch='Chainsawloli:BAAALgADCgUJBQAAAA==.Changying:BAAALgAECgYJCQAAAA==.Cheekung:BAAALgAECgcJEgAAAA==.Choedankal:BAAALgADCgcJBwAAAA==.Chophouse:BAAALgAECgkJBgAAAA==.',
Cl='Clearlyumad:BAACLgAFFH8LAAMHAAUJhxAHQwAJAQAHAAQJhxAHQwAJAQAIAAEJAAArLwAAAAAuAAQKfxsAAgcACAmNHk08AEYCAAcACAmNHk08AEYCAAAA.Clèrick:BAABLgAECn8fAAISAAgJayIDDABTAgASAAgJayIDDABTAgAAAA==.',
Co='Coldcrow:BAAALgAECgEJAQAAAA==.Combination:BAAALgAFFAMJAwAAAA==.Confessor:BAAALgADCgEJAQAAAA==.Corruptions:BAAALgADCgEJAQAAAA==.',
Cr='Crux:BAAALgADCgQJBAAAAA==.',
Cy='Cyfrin:BAAALgADCgEJAQAAAA==.Cyânide:BAAALgADCgYJDQAAAA==.',
['Cõ']='Cõurage:BAAALgAECgYJCAAAAA==.',
Da='Dabbhammer:BAAALgAECgIJAwABLgAECggJGgALABMGAA==.Dabbzyvoker:BAABLgAECn8aAAMLAAgJEwYFLgDvAAAXAAYJowZ4IgAWAQALAAgJVQUFLgDvAAAAAA==.Danathoor:BAAALgADCggJCAAAAA==.Danathor:BAAALgADCgcJBwAAAA==.Dangbro:BAAALgAECgUJBwAAAA==.Dankspank:BAAALgAECgEJAQABLgAECgQJCQAGAAAAAA==.Danteus:BAAALgADCgMJAwABLgAECgUJDwAGAAAAAA==.Darkrigh:BAAALgADCggJDgAAAA==.Darkwave:BAABLgAECn8eAAIBAAgJ8g+OMgCaAQABAAgJ8g+OMgCaAQAAAA==.Darthdiddyus:BAACLgAFFH8ZAAMYAAUJdh6IAABoAQAYAAUJph2IAABoAQAZAAMJtxSiDQAQAQAuAAQKfywABBgACQlPJEEBAHoCABgACQn2I0EBAHoCABkABwlRIToUAHICAA8ABAnJIdoKAIIBAAAA.Datdruidguy:BAAALgADCgUJBQABLgAECgYJBgAGAAAAAA==.Datlock:BAAALgADCgEJAQABLgAECgYJBgAGAAAAAA==.Datshammy:BAAALgAECgYJBgAAAA==.Daviculas:BAAALgADCggJDgAAAA==.Dawghawg:BAAALgAECgEJAQAAAA==.Dawnnie:BAABLgAECn8qAAIVAAgJuxbLDAD7AQAVAAgJuxbLDAD7AQAAAA==.Dawnte:BAABLgAECn8dAAIMAAcJHBx9JADxAQAMAAcJHBx9JADxAQABLgAECgUJDwAGAAAAAA==.Dawsonrogers:BAAALgAECgEJAQAAAA==.Dayvastate:BAABLgAECn8nAAIHAAgJuRcCIwD5AQAHAAgJuRcCIwD5AQAAAA==.Dazshir:BAAALgADCgMJAwAAAA==.',
De='Deathbanana:BAABLgAFFH8HAAIHAAMJ2R5gPwATAQAHAAMJ2R5gPwATAQABLgAFFAcJFQAEAD0cAA==.Deaththreat:BAAALgAECgQJBAABLgAFFAEJAQAGAAAAAA==.Delema:BAACLgAFFH8QAAIMAAUJPB6WDAB3AQAMAAUJPB6WDAB3AQAuAAQKfyAAAgwACAlaIUIiAKACAAwACAlaIUIiAKACAAAA.Democrit:BAAALgAECgIJAgAAAA==.Demonjuice:BAAALgAECgIJAwAAAA==.Derpyblinker:BAABLgAECn8VAAIEAAYJQRDk0wBHAQAEAAYJQRDk0wBHAQAAAA==.Destructer:BAAALgAECgYJEQAAAA==.Devoured:BAAALgADCgMJAwAAAA==.',
Di='Dinger:BAAALgAECgEJAQAAAA==.Dirtydinker:BAAALgAECgYJDQAAAA==.Disconneted:BAAALgADCgYJBgAAAA==.Dishwasher:BAAALgADCgIJAgAAAA==.Dixsard:BAABLgAECn8sAAMPAAgJbSImAQCkAgAPAAgJJiImAQCkAgAZAAcJTB1mIwDeAQAAAA==.',
Do='Doezenn:BAAALgADCgUJBQAAAA==.Dottprepared:BAACLgAFFH8YAAIaAAYJyBCyAABRAQAaAAYJyBCyAABRAQAuAAQKfzYAAhoACQmbIZcBAAcDABoACQmbIZcBAAcDAAAA.Dottyfu:BAABLgAFFH8FAAINAAMJKwnvJADDAAANAAMJKwnvJADDAAAAAA==.Doubted:BAAALgAECgQJBAAAAA==.',
Dr='Dragonboffa:BAAALgAECgcJAQAAAA==.Draul:BAAALgAECgEJAQABLgAECgkJKwAJAEwWAA==.Drexl:BAACLgAFFH8MAAIbAAQJ9xG2BQARAQAbAAQJ9xG2BQARAQAuAAQKfy0ABBwACQlLEl8JABgCABwACQnFEF8JABgCABAABwkSBtFlABwBABsAAgmHDHY7AHAAAAAA.Dril:BAABLgAECn8WAAMDAAYJChlzMQBwAQADAAYJ7hhzMQBwAQAaAAIJAhZuIACBAAAAAA==.Drognin:BAAALgADCgEJAQAAAA==.Drunkfu:BAAALgADCgQJBAAAAA==.',
Du='Dubstep:BAAALgAECgkJAgAAAA==.Dudette:BAAALgAECgYJCgAAAA==.Dunlop:BAAALgAECggJCgAAAA==.',
Dv='Dvmcquéén:BAABLgAECn8WAAMCAAcJ5xkyCwANAgACAAcJ5xkyCwANAgABAAIJBwRCBwFOAAAAAA==.',
Dw='Dweams:BAACLgAFFH8YAAIdAAcJ9xc8AQAnAgAdAAcJ9xc8AQAnAgAuAAQKfzIAAx0ACQlWJgQCAJkDAB0ACQlWJgQCAJkDAB4ABAmrDM05ANkAAAAA.',
['Dâ']='Dântæ:BAAALgAECgUJDwAAAA==.',
['Dö']='Döts:BAAALgADCgMJAgAAAA==.',
['Dø']='Døctøred:BAAALgAECgYJEwAAAA==.',
Ec='Ectonight:BAAALgAECgQJBwAAAA==.',
Ed='Edgybob:BAAALgAECgMJAwAAAA==.',
Eg='Eggfooyung:BAACLgAFFH8VAAITAAYJgxZ5BgDDAQATAAYJgxZ5BgDDAQAuAAQKfzIAAxMACQmPIRYEAC8DABMACQmPIRYEAC8DAB8ABwlPCCA7ADABAAAA.Egwene:BAAALgAECgYJBwAAAA==.',
El='Eldar:BAAALgAECgUJBQAAAA==.Elfchick:BAAALgADCgEJAQAAAA==.Elhonna:BAAALgAECgQJBAAAAA==.Elsâ:BAAALgAECgQJCAAAAA==.',
Em='Emwen:BAAALgADCgMJAwAAAA==.',
En='Endcredits:BAABLgAECn8YAAIIAAcJtQ2eFwARAQAIAAcJtQ2eFwARAQAAAA==.',
Et='Ether:BAABLgAECn8eAAIKAAgJzhPUKADNAQAKAAgJzhPUKADNAQAAAA==.',
Ev='Evieroot:BAAALgADCgMJAwAAAA==.Evoulker:BAACLgAFFH8bAAIgAAcJ1x3wAABWAgAgAAcJ1x3wAABWAgAuAAQKfzYAAiAACQkTH6YFAO4CACAACQkTH6YFAO4CAAAA.',
Ex='Exodyce:BAAALgAECgQJBAAAAA==.',
Ey='Eyecantsee:BAAALgADCgIJAgABLgADCgcJBwAGAAAAAA==.',
Fa='Faene:BAAALgAECgQJCgABLgAECgUJBQAGAAAAAA==.Faire:BAAALgADCgUJBQABLgAFFAQJBwAFALcRAA==.Fairytale:BAACLgAFFH8YAAMeAAYJCxRIAwDPAQAeAAYJCxRIAwDPAQAhAAEJMwjHEwBGAAAuAAQKfzYAAx4ACQlSIP0GANUCAB4ACQlTHf0GANUCACEABwn5HkYSAE4CAAAA.Faitza:BAAALgAECgYJCgAAAA==.Fantastico:BAAALgAECgUJCQAAAA==.',
Fe='Felheim:BAACLgAFFH8LAAIDAAQJkAtyKgAIAQADAAQJkAtyKgAIAQAuAAQKfxgAAgMACAmnGcQjALIBAAMACAmnGcQjALIBAAAA.Fellitha:BAAALgAECgcJEgAAAA==.Fellithà:BAAALgAECgUJBgAAAA==.Felrend:BAAALgADCgMJAgAAAA==.Fentertained:BAAALgADCgcJCAAAAA==.',
Fi='Fiercevalkyr:BAAALgAECgkJBgAAAA==.Firsttower:BAAALgADCgEJAQAAAA==.Fists:BAACLgAFFH8GAAITAAIJJyOpFgDNAAATAAIJJyOpFgDNAAAuAAQKfywAAxMACAnBHssFAK4CABMACAnBHssFAK4CAA0ABAlOFq9dAMwAAAAA.Fizle:BAABLgAECn8YAAIgAAcJngtlEAA3AQAgAAcJngtlEAA3AQAAAA==.',
Fl='Flink:BAAALgAECgYJEwAAAA==.',
Fr='Friend:BAAALgAECgYJEAAAAA==.Frostmoan:BAAALgAFFAEJAQAAAA==.Frostyninja:BAABLgAECn8iAAIFAAgJlgZwSQAxAQAFAAgJlgZwSQAxAQAAAA==.',
Ga='Gabryal:BAABLgAECn8WAAIdAAgJWxoRCgAjAgAdAAgJWxoRCgAjAgAAAA==.Galthur:BAAALgADCgkJCgAAAA==.Garchomp:BAAALgAECgUJEgAAAA==.',
Ge='Gellina:BAAALgAECgEJAQAAAA==.Georg:BAACLgAFFH8WAAIMAAUJCh4MAwDIAQAMAAUJCh4MAwDIAQAuAAQKfzAAAgwACQmBJi8DAKMDAAwACQmBJi8DAKMDAAAA.Gerbankis:BAAALgAECgMJAwAAAA==.',
Gh='Ghoul:BAABLgAECn8aAAIHAAgJkiMyFABZAgAHAAgJkiMyFABZAgAAAA==.Ghouligan:BAAALgAECgQJBAAAAA==.',
Gl='Glaiver:BAABLgAECn8WAAIiAAcJFg0tFgA2AQAiAAcJFg0tFgA2AQAAAA==.Glassjaw:BAAALgADCgUJBQAAAA==.',
Go='Goewin:BAAALgAECgUJBgABLgAECgcJIAADAM8eAA==.Gojo:BAAALgADCgYJDwAAAA==.Goodbye:BAAALgADCgUJBQAAAA==.Gorgrom:BAAALgADCgIJAgAAAA==.',
Gr='Greg:BAAALgAECgIJAgAAAA==.Gregorz:BAAALgAECgEJAQAAAA==.',
Gu='Gulgodeth:BAAALgAECgQJBAAAAA==.Gulgrimmar:BAACLgAFFH8XAAMKAAcJQx/5AQATAgAKAAYJGSD5AQATAgAJAAEJPQxGIABRAAAuAAQKfy8AAgoACQnTJq0AANkDAAoACQnTJq0AANkDAAAA.Guwudanielle:BAAALgAECgcJDwABLgAFFAQJBwAFALcRAA==.',
Ha='Hailsstorm:BAAALgADCgcJEgAAAA==.Hardfeelings:BAAALgAFFAEJAQAAAA==.Harkness:BAAALgAECgQJBwAAAA==.Hassif:BAAALgAECgEJAQAAAA==.',
He='Heimerdoodle:BAAALgAECgYJDwAAAA==.Hemus:BAAALgAECgMJAwAAAA==.Hexed:BAABLgAECn8ZAAINAAgJZgjJHwA4AQANAAgJZgjJHwA4AQAAAA==.',
Hu='Hughue:BAAALgADCgUJBQAAAA==.Hugs:BAAALgAECgYJCAAAAA==.',
Hy='Hyuna:BAAALgADCgIJAgABLgAECgcJDgAGAAAAAA==.',
Ia='Iaso:BAAALgAECgYJEQAAAA==.',
Ic='Iconstar:BAAALgADCgMJAwAAAA==.',
Ig='Igneel:BAAALgADCgQJAQAAAA==.',
Ij='Ijustankedu:BAAALgAECgMJAwAAAA==.',
Ik='Ikiea:BAAALgAECgcJCAAAAA==.',
Il='Ilgrim:BAAALgAFFAIJAgABLgAFFAQJBwAZAD4NAA==.Ilravenll:BAABLgAFFH8HAAIZAAQJPg0UDgA+AQAZAAQJPg0UDgA+AQAAAA==.Ilyana:BAACLgAFFH8UAAIEAAYJNhlnDADDAQAEAAYJNhlnDADDAQAuAAQKfzYAAgQACQn1JZ4HAI4DAAQACQn1JZ4HAI4DAAAA.',
Im='Impavido:BAAALgAECgYJBgAAAA==.',
In='Inholy:BAAALgAECgQJBgAAAA==.Insights:BAAALgADCgMJAwAAAA==.',
Is='Isabella:BAAALgAECgEJAQABLgAFFAQJBwAFALcRAA==.',
It='Ithopel:BAABLgAECn8jAAIWAAYJASF4KAASAgAWAAYJASF4KAASAgAAAA==.',
Ja='Jalista:BAAALgADCgMJAwAAAA==.Jayc:BAACLgAFFH8JAAIEAAQJNRp9HgBsAQAEAAQJNRp9HgBsAQAuAAQKfx0AAgQACAlgHiB0AOoBAAQACAlgHiB0AOoBAAAA.',
Je='Jereico:BAACLgAFFH8cAAILAAcJ0SPqAACQAgALAAcJ0SPqAACQAgAuAAQKfzAAAgsACQmHJgMBAMoDAAsACQmHJgMBAMoDAAAA.Jeryhn:BAACLgAFFH8YAAISAAcJVBRDAgDZAQASAAcJVBRDAgDZAQAuAAQKfzYAAhIACQk8GhUTAHoCABIACQk8GhUTAHoCAAAA.',
Jo='Joeynodz:BAAALgADCgYJEgAAAA==.Jortshorts:BAABLgAECn8kAAIjAAgJTwghDgA1AQAjAAgJTwghDgA1AQAAAA==.',
Jr='Jray:BAABLgAECn8VAAIMAAYJGRnSZAC3AQAMAAYJGRnSZAC3AQAAAA==.',
Ju='Juggalo:BAABLgAECn8pAAMXAAkJQiB/AAABAwAXAAkJCSB/AAABAwALAAIJiRJCVABJAAAAAA==.June:BAACLgAFFH8aAAITAAcJlBmvAQAaAgATAAcJlBmvAQAaAgAuAAQKfzYAAxMACQlsIbIEAB0DABMACQlsIbIEAB0DAB8ABgl3GVcVAIEBAAAA.Juuju:BAAALgAECgQJBwAAAA==.',
Ka='Kaldriss:BAAALgAECgEJAQAAAA==.Kalen:BAAALgADCgEJAgAAAA==.Katashimus:BAAALgAECgYJCwAAAA==.Kawasuoo:BAABLgAECn8UAAMWAAYJ+h64FgAPAgAWAAYJ+h64FgAPAgAkAAUJEw2ZGACbAAAAAA==.Kaze:BAAALgAECgYJCgAAAA==.',
Kh='Khaotichic:BAAALgAECgQJCAAAAA==.Khrenak:BAAALgAECgQJCgAAAA==.',
Ki='Kickpunch:BAAALgAECgYJCQAAAA==.Kirah:BAACLgAFFH8HAAILAAIJmBx6JwC3AAALAAIJmBx6JwC3AAAuAAQKfyAAAgsACQmwIWoEAEoDAAsACQmwIWoEAEoDAAEuAAUUBAkHAAUAtxEA.',
Ko='Koddin:BAABLgAECn8sAAIMAAkJ6h4SDACiAgAMAAkJ6h4SDACiAgAAAA==.Korenchkin:BAAALgAECgEJAQAAAA==.Koreth:BAACLgAFFH8VAAMZAAUJNyBSBgB4AQAZAAQJNyBSBgB4AQAPAAEJAACvBwA5AAAuAAQKfzwAAxkACQl7JVwHABoDABkACQl7JVwHABoDAA8ACAmWGg4EAHcCAAAA.Kornholyo:BAAALgAECgEJAQAAAA==.',
Ku='Kutuzov:BAAALgAECgUJDAAAAA==.',
Kw='Kwaiza:BAAALgAECgYJDwAAAA==.',
['Ká']='Káel:BAAALgAECgMJAwAAAA==.',
La='Lailaysia:BAAALgAECgcJCAAAAA==.Lamemoosaur:BAAALgADCgIJAgABLgAECgYJCgAGAAAAAA==.Laríca:BAACLgAFFH8JAAISAAQJmSaWBQDIAQASAAQJmSaWBQDIAQAuAAQKfygAAhIACAnhJYICAFIDABIACAnhJYICAFIDAAAA.Laustin:BAABLgAECn8YAAQOAAcJNxmNDADcAQAOAAcJDhiNDADcAQAlAAYJEhBADwD4AAAFAAIJbwWGmABgAAAAAA==.Laydout:BAAALgADCgkJCgABLgAECggJGAAFAHshAA==.Laydoutyota:BAABLgAECn8YAAIFAAgJeyEYGQByAgAFAAgJeyEYGQByAgAAAA==.',
Le='Leag:BAABLgAECn8YAAMQAAcJFw8oKAA3AQAQAAcJFw8oKAA3AQAcAAEJJAmtPwA5AAAAAA==.Lemonruss:BAAALgADCgQJBAAAAA==.',
Li='Lilea:BAABLgAECn8sAAMFAAgJrxyPIwDIAQAFAAUJKx+PIwDIAQAlAAcJ4RHtNACWAQAAAA==.Lithium:BAAALgADCgUJBQAAAA==.Littledeb:BAAALgAFFAEJAQAAAA==.',
Lo='Lolchaosbolt:BAAALgADCgYJBgAAAA==.Lortherian:BAAALgAECgYJCgAAAA==.Lowbo:BAAALgADCgUJBQAAAA==.Lowelfesteem:BAAALgADCgUJBQAAAA==.',
Lu='Lucille:BAAALgAECgQJDgAAAA==.',
Ly='Lyndira:BAAALgAECgUJBQAAAA==.',
['Lä']='Läwlbringer:BAAALgAECgYJBwAAAA==.',
['Lî']='Lîghtt:BAAALgADCgQJBAAAAA==.',
Ma='Mabritos:BAAALgAECgQJBQABLgAFFAYJGgAlAJ8eAA==.Maccabee:BAAALgAECgEJAQAAAA==.Mania:BAAALgADCgYJBgABLgAECggJFgAQALYZAA==.Mathath:BAABLgAECn8VAAMHAAcJShq/MQCyAQAHAAcJEhq/MQCyAQAIAAQJVBWkKAD5AAAAAA==.Mathoras:BAABLgAECn8WAAIBAAcJaRXsNgCJAQABAAcJaRXsNgCJAQAAAA==.',
Me='Meandean:BAAALgAECgIJBgAAAA==.Meatier:BAAALgAECgEJAQABLgAECggJFgAQALYZAA==.Meatless:BAAALgADCgcJDQAAAA==.',
Mi='Micmac:BAAALgAECgQJCQAAAA==.Miltonroe:BAABLgAECn8cAAImAAcJwQ9kCwBXAQAmAAcJwQ9kCwBXAQAAAA==.Mirithul:BAAALgADCgYJBwAAAA==.Mischiëf:BAAALgAECgQJBQAAAA==.Mitsuri:BAABLgAECn8iAAIEAAgJoQrWkgCtAQAEAAgJoQrWkgCtAQAAAA==.',
Mo='Modr:BAAALgAECgkJDAAAAA==.Monkynate:BAAALgAECgYJCgAAAA==.Monsterskill:BAABLgAECn8fAAQRAAgJzhgfEAAsAQARAAUJ4RMfEAAsAQABAAUJdBllWwAcAQACAAUJhhNTLQAIAQAAAA==.Moonerva:BAABLgAECn8YAAInAAcJIgwQIQAuAQAnAAcJIgwQIQAuAQAAAA==.Morpheos:BAAALgADCgQJBAAAAA==.Mortgage:BAAALgADCgUJBQAAAA==.',
Mu='Mutsu:BAAALgADCgcJBwAAAA==.',
Mv='Mvqchx:BAAALgAECgMJBQAAAA==.',
Na='Naturelass:BAAALgADCgUJBQAAAA==.',
Ne='Neotama:BAAALgAECggJEgAAAA==.Nethis:BAABLgAECn8gAAIdAAYJORxIFQCXAQAdAAYJORxIFQCXAQAAAA==.',
Ni='Niatpacgrom:BAAALgAFFAEJAQAAAA==.Nivla:BAAALgADCgMJAwAAAA==.',
No='Nobacon:BAAALgAECgMJAwAAAA==.Norvis:BAAALgAECgQJBQAAAA==.Notdragon:BAAALgAECgQJDQAAAA==.',
Nu='Nukeddukem:BAAALgAECgYJDwAAAA==.',
Nv='Nv:BAAALgAECgcJDgAAAA==.',
Ny='Nymrod:BAABLgAECn8iAAMBAAgJIRT7JwDGAQABAAgJIRT7JwDGAQACAAIJpgdlZQBEAAAAAA==.',
['Ní']='Nír:BAAALgAECgQJBAAAAA==.',
Oj='Ojou:BAAALgADCgMJAwABLgAFFAMJAwAGAAAAAA==.',
Om='Omizzig:BAAALgAECgQJCgAAAA==.',
On='Onepunch:BAAALgAECgQJBgAAAA==.',
Or='Orcman:BAAALgADCgIJAgABLgADCgcJBwAGAAAAAA==.Orloran:BAAALgADCgIJAgAAAA==.',
Pa='Palthur:BAAALgAECgUJCAAAAA==.Parria:BAAALgAECgYJDgABLgAECgcJCAAGAAAAAA==.Pasqualino:BAAALgAECgYJCgAAAA==.Passionate:BAACLgAFFH8IAAIgAAMJZQ3uEwDOAAAgAAMJZQ3uEwDOAAAuAAQKfyUAAiAACAmfFFEVAPUBACAACAmfFFEVAPUBAAAA.',
Pe='Peepis:BAAALgADCgEJAQABLgAECggJFgAQALYZAA==.Pennance:BAABLgAECn8iAAISAAkJ/huYBgC0AgASAAkJ/huYBgC0AgAAAA==.',
Ph='Phatmidas:BAABLgAECn8hAAIMAAgJRxdoNgCkAQAMAAgJRxdoNgCkAQAAAA==.',
Pl='Plagueground:BAACLgAFFH8KAAIHAAQJHx9VGwBsAQAHAAQJHx9VGwBsAQAuAAQKfzkAAgcACQmnJrYCAK8DAAcACQmnJrYCAK8DAAAA.Plutonyus:BAAALgAECgEJAQAAAA==.',
Po='Poc:BAABLgAECn8YAAIEAAYJPB3rdADoAQAEAAYJPB3rdADoAQAAAA==.Pockets:BAAALgAECgMJBwAAAA==.Potatopotato:BAABLgAECn8gAAIZAAgJTBchHAAeAgAZAAgJTBchHAAeAgAAAA==.Pounces:BAAALgAECgYJEgABLgAECgcJGAALAKgXAA==.Powerfistin:BAAALgADCgcJBwAAAA==.',
Pr='Prosecutor:BAAALgAECgUJDAAAAA==.Prynts:BAABLgAECn8VAAIMAAcJZh3pRAAVAgAMAAcJZh3pRAAVAgAAAA==.Prøzak:BAAALgAECgYJBQAAAA==.',
Pu='Puetrid:BAAALgADCgYJBgABLgAECgQJBAAGAAAAAA==.',
Ra='Raanky:BAAALgAECgEJAQAAAA==.Radiantlight:BAAALgAECgEJAQAAAA==.Randomly:BAAALgADCgkJJQAAAA==.Raspberries:BAAALgAECgcJBwAAAA==.Rautha:BAAALgAECgkJEgAAAA==.Rayl:BAAALgAECgYJDwAAAA==.Razsputin:BAAALgAECgMJBwAAAA==.',
Re='Rekless:BAAALgADCgUJBQAAAA==.Rethgar:BAAALgAECgUJEgAAAA==.',
Rh='Rhaegosa:BAABLgAECn8mAAQLAAkJ7xcOHgDVAQALAAcJVBgOHgDVAQAXAAQJrg31DQCtAAAgAAIJfhEFHQCMAAAAAA==.Rhavik:BAAALgADCgQJBAAAAA==.Rhekt:BAAALgAECgEJAQAAAA==.Rhokladar:BAAALgAECgQJCQAAAA==.',
Ri='Ridcully:BAABLgAECn8VAAIWAAcJRhZtOADFAQAWAAcJRhZtOADFAQAAAA==.Rimath:BAAALgAECgcJBAAAAA==.Rinswind:BAAALgADCgMJAwAAAA==.',
Ro='Robopacman:BAACLgAFFH8NAAIHAAQJvyD1EwCDAQAHAAQJvyD1EwCDAQAuAAQKfy8AAgcACQnyJBUPACMDAAcACQnyJBUPACMDAAAA.Rodstewart:BAACLgAFFH8UAAMFAAcJrBlwAQDZAQAFAAUJhxtwAQDZAQAlAAQJXwzjFAD2AAAuAAQKfyIAAwUACQn+Ik0WAIYCAAUACAmeIk0WAIYCACUABwnNHxEmAPgBAAAA.Roofeo:BAAALgAECgcJCwAAAA==.Rotdaddy:BAAALgAECgcJEwAAAA==.',
Ry='Ryoshin:BAAALgADCgEJAQABLgAECgYJDQAGAAAAAA==.Ryzze:BAAALgADCgYJBgAAAA==.',
['Rï']='Rïn:BAAALgADCgEJAQAAAA==.',
Sa='Salas:BAABLgAECn8UAAIBAAcJzgxFSwBHAQABAAcJzgxFSwBHAQAAAA==.Salino:BAAALgAECgUJBQAAAA==.Salinoster:BAAALgADCgEJAQAAAA==.Salordell:BAAALgADCgIJAwAAAA==.Sam:BAAALgADCgEJAQAAAA==.Sarate:BAABLgAECn8aAAIdAAcJ3g56HABYAQAdAAcJ3g56HABYAQAAAA==.Savannah:BAABLgAFFH8HAAIFAAQJtxHxEgBQAQAFAAQJtxHxEgBQAQAAAA==.Savvtwo:BAAALgADCgcJBwABLgAFFAYJFQADAGAlAQ==.',
Sc='Scathach:BAABLgAECn8gAAMDAAcJzx7cGQDuAQADAAcJzx7cGQDuAQAiAAQJURgsRADmAAAAAA==.Scorandom:BAAALgAECgEJAQAAAA==.',
Se='Sezra:BAAALgADCgkJAQAAAA==.',
Sh='Shamalam:BAAALgADCgEJAQAAAA==.Shei:BAAALgAECgIJAgAAAA==.Sheidon:BAAALgAECgQJBAAAAA==.Shinanigans:BAAALgAECgYJDAAAAA==.Shruikan:BAAALgADCggJDAAAAA==.',
Si='Silverslam:BAAALgAECgEJAQABLgAECgcJEAAGAAAAAA==.Sinatra:BAAALgAECgIJBAABLgAECgYJCgAGAAAAAA==.Siqodel:BAAALgADCgYJCAAAAA==.',
Sk='Skurge:BAAALgAECgYJDwAAAA==.',
Sl='Slamb:BAAALgAECgYJBwAAAA==.Slimetongue:BAAALgADCgMJAwAAAA==.',
Sm='Smaaug:BAAALgADCgMJAwAAAA==.',
Sn='Snuggle:BAAALgAECgEJAQAAAA==.',
So='Solstis:BAAALgAECggJDgAAAA==.Sorzsnipe:BAAALgADCgQJBAAAAA==.',
Sp='Spellchücker:BAAALgAECgcJDQAAAA==.Spfzero:BAAALgAECgEJAQAAAA==.',
St='Staggered:BAACLgAFFH8PAAINAAQJoh6aCQBtAQANAAQJoh6aCQBtAQAuAAQKfyUAAw0ACAkOIusLAM8CAA0ACAkOIusLAM8CAB8AAQk1A8uMABwAAAAA.Stoneojinray:BAAALgADCgEJAQAAAA==.Stoneorcman:BAAALgADCgcJBwAAAA==.Stormriderr:BAAALgAECgYJCAAAAA==.',
Su='Subdofu:BAAALgADCgQJBAABLgAECgcJFwAZAN0cAA==.Subtox:BAABLgAECn8XAAMZAAcJ3RxIIQDvAQAZAAcJ3RxIIQDvAQAPAAEJkgu2HwA0AAAAAA==.',
Sw='Sweetcool:BAAALgAECgUJCQABLgAECggJKAAFAN4hAA==.',
Sy='Syphilistjt:BAABLgAECn8WAAIeAAgJ0xLHFwDgAQAeAAgJ0xLHFwDgAQAAAA==.Syphillis:BAAALgAECgYJCgAAAA==.',
['Sá']='Sálud:BAACLgAFFH8JAAInAAQJWRmpFQD/AAAnAAQJWRmpFQD/AAAuAAQKfyIAAycACAmSH3sPAKkCACcABwlcIXsPAKkCACQABwmhGfkHALABAAAA.',
['Sê']='Sêp:BAAALgAECgYJCgAAAA==.',
Ta='Tanissaria:BAAALgADCgEJAQAAAA==.Taranith:BAAALgAECgUJBQABLgAECggJFgAEAPYTAA==.Tarhealeon:BAABLgAECn8zAAMSAAkJ4BmVIQARAgASAAkJ4BmVIQARAgAMAAcJThGwQgB9AQAAAA==.Tarmander:BAAALgAECgYJDgAAAA==.Taylörshift:BAAALgAECgQJBwAAAA==.',
Te='Telahnicus:BAAALgADCgEJAQAAAA==.Terranox:BAAALgADCgMJAwAAAA==.Testostauren:BAAALgAECgMJBgAAAA==.',
Th='Thabigone:BAAALgAECgYJCwAAAA==.Thalnaria:BAAALgAECgYJCwAAAA==.Threebuttons:BAAALgAECgUJCAABLgAFFAMJCAAgAO4GAA==.Thunderkis:BAAALgAECgYJDwAAAA==.',
Ti='Tiewiz:BAABLgAECn8cAAMEAAgJWg9HSwCGAQAEAAgJEQxHSwCGAQAoAAUJlw3WBwC9AAAAAA==.',
To='Tointjoker:BAAALgAECgMJBAAAAA==.Tolun:BAABLgAECn80AAIEAAkJARcYUQBEAgAEAAkJARcYUQBEAgAAAA==.Tosan:BAAALgADCggJDgAAAA==.',
Tr='Treeplague:BAABLgAECn8oAAMdAAkJDAyLEQC/AQAdAAkJDAyLEQC/AQAeAAUJDQtmKADmAAAAAA==.Trypleg:BAAALgAECgMJAwAAAA==.',
Tu='Tungie:BAABLgAECn8bAAIHAAgJ0iA8FwBBAgAHAAgJ0iA8FwBBAgAAAA==.Turn:BAACLgAFFH8bAAQBAAcJaRhwCAChAQABAAUJCyBwCAChAQACAAUJvg25AwBcAQARAAIJlwBaCwAmAAAuAAQKfzEABAEACQmqI8AUANkCAAEACAmqI8AUANkCAAIAAwk6HyorABMBABEAAQkAAKkbAAAAAAAA.Turtleduck:BAABLgAECn8UAAIXAAYJVxkUBgBxAQAXAAYJVxkUBgBxAQAAAA==.Tuskbreaker:BAAALgAECgIJAgAAAA==.',
Tw='Twostrokes:BAAALgAECgEJAQAAAA==.',
Ty='Tyrese:BAAALgADCggJEAAAAA==.',
Uf='Uffin:BAAALgAECgQJBQAAAA==.',
Um='Umbryx:BAAALgAECgYJCQAAAA==.',
Un='Unagi:BAAALgAECggJDAAAAA==.Unholy:BAAALgADCgIJAgAAAA==.',
Va='Valdi:BAAALgAECgYJEQAAAA==.',
Ve='Velthera:BAABLgAECn8XAAIgAAgJCyJFBAAQAwAgAAgJCyJFBAAQAwABLgAFFAMJAwAGAAAAAA==.Venomlight:BAAALgADCgIJAgAAAA==.Venomstrikes:BAAALgAECgQJCQAAAA==.Venratzi:BAAALgAECgQJBAAAAA==.',
Vo='Voridor:BAAALgADCgEJAQAAAA==.Voulk:BAAALgAFFAMJAwABLgAFFAcJGwAgANcdAA==.',
Vy='Vyllan:BAABLgAECn8UAAQRAAgJ8AQDEwD8AAABAAgJGgSnYAAPAQARAAYJKwQDEwD8AAACAAMJmgFIKQAxAAAAAA==.',
Wa='Waldgeist:BAAALgAECgUJBQABLgAECggJFgAQALYZAA==.Walthur:BAAALgADCgkJDQAAAA==.Waobby:BAAALgADCgIJAgAAAA==.Warrpigg:BAAALgAECgEJAQAAAA==.Waterdrinker:BAAALgAECgIJAgAAAA==.Wavybone:BAAALgAECgEJAgAAAA==.',
Wh='Whoarlock:BAAALgADCgUJCAAAAA==.',
Wo='Wo:BAAALgADCgMJAwAAAA==.',
Wu='Wutangstyle:BAAALgAECgIJAgABLgAECggJFgAQALYZAA==.',
Wy='Wyatta:BAAALgADCgIJAgAAAA==.',
Xe='Xelinia:BAACLgAFFH8QAAIdAAUJoxI3DQA3AQAdAAUJoxI3DQA3AQAuAAQKfyEAAh0ACQk1H2oMAL0CAB0ACQk1H2oMAL0CAAAA.Xen:BAAALgAECgYJCAAAAA==.',
Xf='Xfortune:BAAALgADCgcJCQAAAA==.',
Xh='Xholycritz:BAAALgAECgMJAwAAAA==.',
Xu='Xuefeng:BAACLgAFFH8MAAIfAAQJkA5DCgArAQAfAAQJkA5DCgArAQAuAAQKfy4AAh8ACQkkHb0EAJkCAB8ACQkkHb0EAJkCAAAA.',
Ye='Yenchmeister:BAACLgAFFH8YAAMQAAcJLhtBAwDDAQAQAAUJuRxBAwDDAQAcAAUJMBUAAgBiAQAuAAQKfygAAxAACQkgJd8JABEDABAACQkgJd8JABEDABwAAgl3IBwoAK4AAAAA.',
Yo='Youngbusta:BAABLgAECn8qAAIEAAgJqSNJEACYAgAEAAgJqSNJEACYAgAAAA==.',
Yu='Yuta:BAAALgAECgYJDQAAAA==.',
Za='Zad:BAAALgADCgIJAgAAAA==.',
Ze='Zenrac:BAAALgADCgUJBQAAAA==.Zeromus:BAAALgAECgIJAgAAAA==.',
Zi='Zilvanic:BAACLgAFFH8FAAIVAAMJYwdXBwCRAAAVAAMJYwdXBwCRAAAuAAQKfyQABBUACAlgEiULAI0BABUACAn0ESULAI0BAAwABQlZELuAAOsAABIAAwl8AQODAGwAAAAA.Zilvanion:BAAALgAECgQJBAAAAA==.',
Zo='Zourknight:BAAALgADCgcJEAAAAA==.Zourlock:BAAALgAECgYJDQAAAA==.',
Zu='Zulvaz:BAAALgAECgIJAwAAAA==.Zurey:BAABLgAECn80AAIDAAkJOA0PKgCQAQADAAkJOA0PKgCQAQAAAA==.',
Zy='Zynjamin:BAACLgAFFH8VAAIXAAYJeSM9AAADAgAXAAYJeSM9AAADAgAuAAQKfy4AAhcACQkLJC8AANsDABcACQkLJC8AANsDAAAA.',
['Ðr']='Ðrèamless:BAAALgAECgIJAgAAAA==.',
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

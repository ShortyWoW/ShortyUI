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

local lookup = {'Warlock-Demonology','Warlock-Destruction','DemonHunter-Devourer','Hunter-BeastMastery','Unknown-Unknown','DeathKnight-Unholy','DeathKnight-Blood','Shaman-Restoration','Shaman-Elemental','Evoker-Augmentation','Paladin-Retribution','Monk-Brewmaster','Rogue-Assassination','Warrior-Fury','Warlock-Affliction','Paladin-Holy','Monk-Mistweaver','Paladin-Protection','Druid-Restoration','Evoker-Preservation','Evoker-Devastation','Rogue-Outlaw','Rogue-Subtlety','Mage-Frost','DemonHunter-Vengeance','Warrior-Protection','Warrior-Arms','Priest-Shadow','Priest-Discipline','Monk-Windwalker','Priest-Holy','Druid-Feral','Hunter-Marksmanship','Shaman-Enhancement','DemonHunter-Havoc','Druid-Balance','Druid-Guardian','Mage-Arcane',}
local provider = {region='US',realm='Stonemaul',name='US',type='weekly',zone=46,date='2026-05-01',data={Aa='Aannte:BAACLgAFFH8WAAMBAAcJ7Rf6BQDAAQABAAUJIhX6BQDAAQACAAQJHRi9AQA4AQAuAAQKfyIAAwEACQklIocmAHgCAAEACQkVIocmAHgCAAIABAnwHvgdAGABAAAA.Aardbark:BAAALgADCgEJAQAAAA==.',
Ac='Achtland:BAAALgAECgUJBgABLgAECgcJIAADAKgdAA==.',
Ad='Adekai:BAAALgADCgEJAQAAAA==.Adv:BAAALgAECgEJAQAAAA==.',
Ae='Aerestrix:BAAALgAECgUJBgAAAA==.',
Ai='Airvis:BAAALgAECgYJEQAAAA==.',
Al='Alacia:BAAALgAECgcJBwABLgAECggJJwAEAIcZAA==.Alatarr:BAAALgAECgQJBAAAAA==.Albinomonk:BAAALgADCgcJBwAAAA==.',
An='Anankei:BAAALgAECgMJAwAAAA==.Annastrophic:BAAALgADCgMJAwAAAA==.Anrí:BAAALgAECgEJAQAAAA==.Antaria:BAAALgADCgcJFgAAAA==.Ante:BAAALgADCgUJAQAAAA==.Antiform:BAAALgAECgIJBgAAAA==.Antpony:BAAALgAECgIJAgABLgAECgYJCgAFAAAAAA==.',
Ar='Arcish:BAAALgAECgEJAgAAAA==.Arjun:BAAALgAECgYJDgAAAA==.Arkirla:BAAALgAECgEJAgAAAA==.Arkiyra:BAAALgAECggJCQAAAA==.Arkyra:BAAALgAECgUJBgAAAA==.Arovix:BAAALgAECgYJDgAAAA==.',
As='Ashwey:BAAALgADCgkJCAAAAA==.',
At='Atom:BAAALgADCgkJHQAAAA==.',
Au='Aubreey:BAAALgADCgcJBwAAAA==.Aureille:BAAALgAECgYJCgAAAA==.',
Aw='Awoozehl:BAACLgAFFH8WAAMGAAYJyB7DDAB8AQAGAAUJyB7DDAB8AQAHAAEJAAAMFQBIAAAuAAQKfy8AAgYACQmXJh8CALsDAAYACQmXJh8CALsDAAAA.',
Az='Azgrodon:BAABLgAECn8mAAMIAAgJ8xRRDgALAgAIAAgJ8xRRDgALAgAJAAMJjww4bACSAAAAAA==.Azor:BAABLgAECn8YAAIDAAgJcR08HQCiAgADAAgJcR08HQCiAgAAAA==.',
Ba='Baja:BAAALgAECgMJAwAAAA==.Baldomar:BAAALgADCgUJCAAAAA==.Bangungot:BAAALgADCgMJAwABLgAFFAcJFAAKAEwfAA==.Barzalie:BAAALgAECgYJDAABLgAFFAMJAwAFAAAAAA==.Bathrezz:BAABLgAECn8UAAILAAgJqhQ4KQCdAQALAAgJqhQ4KQCdAQAAAA==.',
Be='Beerbelly:BAAALgAFFAMJAwAAAA==.Beleaves:BAACLgAFFH8XAAIMAAcJzQaNBgBqAQAMAAcJzQaNBgBqAQAuAAQKfzAAAgwACQkxFzkbACoCAAwACQkxFzkbACoCAAAA.Belsnickel:BAAALgADCgYJCAAAAA==.Beorl:BAAALgADCgYJCAAAAA==.',
Bh='Bhackshots:BAAALgAECgUJDwABLgAECggJKwANAG8iAA==.',
Bi='Bifurious:BAABLgAECn8UAAIOAAgJthlVJwAhAgAOAAgJthlVJwAhAgAAAA==.',
Bl='Blowmybubble:BAAALgADCgEJAQAAAA==.Bluereindeer:BAAALgAECgkJEQAAAA==.',
Bo='Bobsstones:BAACLgAFFH8OAAMBAAcJnR7LAwDkAQABAAYJdh3LAwDkAQACAAQJ6x0hBgANAQAuAAQKfyUABAIACQlCJT0GAGwCAAEABwkmI/sbAK0CAAIABgmDJD0GAGwCAA8AAglDJOkVANUAAAAA.Bonekitty:BAAALgAECgYJBgAAAA==.Bonkulo:BAAALgAECgYJBwAAAA==.Boofassist:BAABLgAECn8VAAIQAAgJ9yR/BAAmAwAQAAgJ9yR/BAAmAwABLgAFFAUJEwARAD8VAA==.Boogey:BAAALgAECgUJDgAAAA==.Boompowwow:BAABLgAECn8VAAIJAAYJIxnjNACDAQAJAAYJIxnjNACDAQAAAA==.Boomsonic:BAAALgADCgUJBQABLgAECggJFAAOALYZAA==.Bophadeez:BAABLgAECn8dAAQQAAcJGSGGDQACAgAQAAcJGSGGDQACAgALAAYJtQ/KjABhAQASAAEJPCP/OABcAAAAAA==.',
Br='Broccoliz:BAECLgAFFH8XAAITAAcJghDyAgC9AQATAAcJghDyAgC9AQAuAAQKfzEAAhMACQkUH9UYAHECABMACQkUH9UYAHECAAAA.Brokgar:BAAALgAECggJEAAAAA==.Brotu:BAAALgADCgIJAQAAAA==.Bruceleroy:BAAALgADCgEJAQAAAA==.Brutalsmasch:BAAALgADCgUJBQAAAA==.',
Bu='Bubu:BAAALgAECgEJAQAAAA==.',
Bw='Bwonshamdi:BAAALgAECgcJBwABLgAECgcJBwAFAAAAAA==.',
['Bõ']='Bõb:BAAALgAECgMJBQAAAA==.',
Ca='Cafca:BAABLgAECn8fAAICAAcJmBhrAwC6AQACAAcJmBhrAwC6AQAAAA==.Caitlin:BAAALgAECgEJAQABLgAFFAQJBgAEAHkLAA==.Callyour:BAAALgADCgIJAgAAAA==.Cask:BAAALgADCgYJAQAAAA==.',
Ch='Chainsawloli:BAAALgADCgUJBQAAAA==.Changying:BAAALgAECgUJCAAAAA==.Cheekung:BAAALgAECgYJDwAAAA==.Choedankal:BAAALgADCgcJBwAAAA==.Chophouse:BAAALgAECgkJBgAAAA==.',
Cl='Clearlyumad:BAACLgAFFH8KAAMGAAUJlxAqKwARAQAGAAQJlxAqKwARAQAHAAEJAABLIwAAAAAuAAQKfxsAAgYACAmFHk08AEYCAAYACAmFHk08AEYCAAAA.Clèrick:BAABLgAECn8bAAIQAAgJGyLwFQBhAgAQAAgJGyLwFQBhAgAAAA==.',
Co='Coldcrow:BAAALgADCgEJAQAAAA==.Combination:BAAALgADCgIJAgABLgAECggJFwAUAAsiAA==.Corruptions:BAAALgADCgEJAQAAAA==.',
Cr='Crux:BAAALgADCgQJBAAAAA==.',
Cy='Cyfrin:BAAALgADCgEJAQAAAA==.Cyânide:BAAALgADCgYJDQAAAA==.',
['Cõ']='Cõurage:BAAALgAECgYJCAAAAA==.',
Da='Dabbhammer:BAAALgAECgIJAgABLgAECggJGgAKABIGAA==.Dabbzyvoker:BAABLgAECn8aAAMKAAgJEgatIgDvAAAVAAYJowZ+IgAWAQAKAAgJTwWtIgDvAAAAAA==.Danathoor:BAAALgADCggJCAAAAA==.Danathor:BAAALgADCgcJBwAAAA==.Dangbro:BAAALgAECgUJBwAAAA==.Danteus:BAAALgADCgMJAwABLgAECgQJDAAFAAAAAA==.Darkrigh:BAAALgADCggJDgAAAA==.Darkwave:BAABLgAECn8WAAIBAAcJTg3GNgBQAQABAAcJTg3GNgBQAQAAAA==.Darthdiddyus:BAACLgAFFH8UAAMWAAUJdR6IAABoAQAWAAUJpR2IAABoAQAXAAMJtxSfDQAQAQAuAAQKfykABBYACAkaJIABAA4CABcABwlRIT0UAHICABYACAm0I4ABAA4CAA0ABAnJIdkKAIIBAAAA.Datdruidguy:BAAALgADCgUJBQABLgAECgYJBgAFAAAAAA==.Datlock:BAAALgADCgEJAQABLgAECgYJBgAFAAAAAA==.Datshammy:BAAALgAECgYJBgAAAA==.Daviculas:BAAALgADCggJDgAAAA==.Dawghawg:BAAALgAECgEJAQAAAA==.Dawnnie:BAABLgAECn8iAAISAAgJiBXNDAD7AQASAAgJiBXNDAD7AQAAAA==.Dawnte:BAABLgAECn8XAAILAAcJGxqPHQDYAQALAAcJGxqPHQDYAQAAAA==.Dawsonrogers:BAAALgADCgMJBAAAAA==.Dayvastate:BAABLgAECn8fAAIGAAgJ4BPCIwCzAQAGAAgJ4BPCIwCzAQAAAA==.Dazshir:BAAALgADCgMJAwAAAA==.',
De='Deathbanana:BAABLgAFFH8GAAIGAAMJABxwKgAUAQAGAAMJABxwKgAUAQABLgAFFAcJEQAYAD0cAA==.Deaththreat:BAAALgAECgQJBAABLgAECgYJCgAFAAAAAA==.Delema:BAACLgAFFH8QAAILAAUJMB5ABgCDAQALAAUJMB5ABgCDAQAuAAQKfyAAAgsACAlaIUgiAKACAAsACAlaIUgiAKACAAAA.Democrit:BAAALgAECgIJAgAAAA==.Demonjuice:BAAALgADCgIJAgAAAA==.Derpyblinker:BAABLgAECn8VAAIYAAYJQRDZ0wBHAQAYAAYJQRDZ0wBHAQAAAA==.Destructer:BAAALgAECgQJCQAAAA==.Devoured:BAAALgADCgMJAwAAAA==.',
Di='Dinger:BAAALgADCgQJAwAAAA==.Dirtydinker:BAAALgAECgYJDQAAAA==.Disconneted:BAAALgADCgYJBgAAAA==.Dishwasher:BAAALgADCgIJAgAAAA==.Dixsard:BAABLgAECn8rAAMNAAgJbyKmAACxAgANAAgJISKmAACxAgAXAAcJSB1lIwDeAQAAAA==.',
Do='Doezenn:BAAALgADCgUJBQAAAA==.Dottprepared:BAACLgAFFH8UAAIZAAYJ8w2yAABRAQAZAAYJ8w2yAABRAQAuAAQKfzAAAhkACQn9IJcBAAcDABkACQn9IJcBAAcDAAAA.Dottyfu:BAAALgAFFAMJAwAAAA==.Doubted:BAAALgAECgQJBAAAAA==.',
Dr='Dragonboffa:BAAALgAECgcJAQAAAA==.Drexl:BAACLgAFFH8KAAIaAAQJ9hG0BQARAQAaAAQJ9hG0BQARAQAuAAQKfy0ABBsACQlIEmAJABgCABsACQnDEGAJABgCAA4ABwkSBtJlABwBABoAAgmHDHk7AHAAAAAA.Dril:BAABLgAECn8VAAMDAAUJjhdAMQAeAQADAAUJahdAMQAeAQAZAAIJ/hVvIACBAAAAAA==.Drognin:BAAALgADCgEJAQAAAA==.',
Du='Dubstep:BAAALgAECgkJAgAAAA==.Dudette:BAAALgAECgYJCgAAAA==.Dunlop:BAAALgAECgYJBgAAAA==.',
Dv='Dvmcquéén:BAABLgAECn8WAAMCAAcJ5xkxCwANAgACAAcJ5xkxCwANAgABAAIJBwQ4BwFOAAAAAA==.',
Dw='Dweams:BAACLgAFFH8UAAIcAAcJ/xY8AQAnAgAcAAcJ/xY8AQAnAgAuAAQKfywAAxwACQmBJQMCAJkDABwACQmBJQMCAJkDAB0ABAmrDM45ANkAAAAA.',
['Dâ']='Dântæ:BAAALgAECgQJDAAAAA==.',
['Dö']='Döts:BAAALgADCgMJAgAAAA==.',
['Dø']='Døctøred:BAAALgAECgYJEwAAAA==.',
Ec='Ectonight:BAAALgAECgQJBwAAAA==.',
Ed='Edgybob:BAAALgAECgMJAwAAAA==.',
Eg='Eggfooyung:BAACLgAFFH8TAAIRAAUJPxVZBwBzAQARAAUJPxVZBwBzAQAuAAQKfy0AAxEACQmbIRcEAC8DABEACQmbIRcEAC8DAB4ABwlPCCQ7ADABAAAA.Egwene:BAAALgAECgYJBwAAAA==.',
El='Eldar:BAAALgAECgQJBAAAAA==.Elfchick:BAAALgADCgEJAQAAAA==.Elhonna:BAAALgAECgQJBAAAAA==.Elsâ:BAAALgAECgQJCAAAAA==.',
Em='Emwen:BAAALgADCgMJAwAAAA==.',
En='Endcredits:BAAALgAECgYJEQAAAA==.',
Et='Ether:BAABLgAECn8eAAIJAAgJzhPUKADNAQAJAAgJzhPUKADNAQAAAA==.',
Ev='Evieroot:BAAALgADCgMJAwAAAA==.Evoulker:BAACLgAFFH8XAAIUAAcJ/x3wAABWAgAUAAcJ/x3wAABWAgAuAAQKfzAAAhQACQkNH6cFAO4CABQACQkNH6cFAO4CAAAA.',
Ex='Exodyce:BAAALgAECgQJBAAAAA==.',
Ey='Eyecantsee:BAAALgADCgIJAgABLgADCgcJBwAFAAAAAA==.',
Fa='Faene:BAAALgAECgMJCQAAAA==.Faire:BAAALgADCgUJBQABLgAFFAQJBgAEAHkLAA==.Fairytale:BAACLgAFFH8UAAMdAAYJHxFGAwDPAQAdAAYJHxFGAwDPAQAfAAEJMwjEEwBGAAAuAAQKfzAAAx0ACQlSIP8GANUCAB0ACQlTHf8GANUCAB8ABwn5HkgSAE4CAAAA.Faitza:BAAALgAECgYJCgAAAA==.Fantastico:BAAALgAECgIJAwAAAA==.',
Fe='Felheim:BAACLgAFFH8IAAIDAAQJcQutGQAMAQADAAQJcQutGQAMAQAuAAQKfxcAAgMABwmaGD0kAFsBAAMABwmaGD0kAFsBAAAA.Fellitha:BAAALgAECgYJEAAAAA==.Fellithà:BAAALgAECgEJAQAAAA==.Felrend:BAAALgADCgMJAgAAAA==.Fentertained:BAAALgADCgcJCAAAAA==.',
Fi='Fiercevalkyr:BAAALgAECgkJBgAAAA==.Fists:BAABLgAECn8sAAMRAAgJyR6JAwC4AgARAAgJyR6JAwC4AgAMAAQJTharXQDMAAAAAA==.Fizle:BAAALgAECgYJEQAAAA==.',
Fl='Flink:BAAALgAECgYJEwAAAA==.',
Fr='Friend:BAAALgAECgYJEAAAAA==.Frostmoan:BAAALgAFFAEJAQAAAA==.Frostyninja:BAABLgAECn8gAAIEAAgJeAZkPQAfAQAEAAgJeAZkPQAfAQAAAA==.',
Ga='Gabryal:BAAALgAECggJDwAAAA==.Galthur:BAAALgADCgkJCgAAAA==.Garchomp:BAAALgAECgUJEQAAAA==.',
Ge='Gellina:BAAALgADCgkJEgAAAA==.Georg:BAACLgAFFH8SAAILAAUJBx4LAwDIAQALAAUJBx4LAwDIAQAuAAQKfyoAAgsACQn7JDADAKMDAAsACQn7JDADAKMDAAAA.Gerbankis:BAAALgAECgMJAwAAAA==.',
Gh='Ghoul:BAABLgAECn8aAAIGAAgJjCM6CwByAgAGAAgJjCM6CwByAgAAAA==.Ghouligan:BAAALgAECgQJBAAAAA==.',
Gl='Glaiver:BAAALgAECgYJDwAAAA==.Glassjaw:BAAALgADCgUJBQAAAA==.',
Go='Goewin:BAAALgAECgUJBgABLgAECgcJIAADAKgdAA==.Gojo:BAAALgADCgYJDwAAAA==.Goodbye:BAAALgADCgUJBQAAAA==.Gorgrom:BAAALgADCgIJAgAAAA==.',
Gr='Greg:BAAALgAECgIJAgAAAA==.Gregorz:BAAALgAECgEJAQAAAA==.',
Gu='Gulgrimmar:BAACLgAFFH8TAAMJAAcJRx/xAQDxAQAJAAYJHiDxAQDxAQAIAAEJPQxEIABRAAAuAAQKfy8AAgkACQnTJq0AANkDAAkACQnTJq0AANkDAAAA.Guwudanielle:BAAALgAECgcJDwABLgAFFAQJBgAEAHkLAA==.',
Ha='Hailsstorm:BAAALgADCgcJEgAAAA==.Hardfeelings:BAAALgAECgYJCgAAAA==.Harkness:BAAALgAECgMJAwAAAA==.Hassif:BAAALgAECgEJAQAAAA==.',
He='Heimerdoodle:BAAALgAECgYJDwAAAA==.Hemus:BAAALgAECgMJAwAAAA==.Hexed:BAAALgAECgcJEQAAAA==.',
Hu='Hughue:BAAALgADCgUJBQAAAA==.Hugs:BAAALgADCgUJCgAAAA==.',
Hy='Hyuna:BAAALgADCgIJAgABLgAECgYJCwAFAAAAAA==.',
Ia='Iaso:BAAALgAECgYJEQAAAA==.',
Ic='Iconstar:BAAALgADCgMJAwAAAA==.',
Ig='Igneel:BAAALgADCgQJAQAAAA==.',
Ij='Ijustankedu:BAAALgAECgMJAwAAAA==.',
Ik='Ikiea:BAAALgAECgcJCAAAAA==.',
Il='Ilgrim:BAAALgAFFAIJAgABLgAFFAQJBAAFAAAAAA==.Ilravenll:BAAALgAFFAQJBAAAAA==.Ilyana:BAACLgAFFH8QAAIYAAYJdxn3DAC0AQAYAAYJdxn3DAC0AQAuAAQKfzAAAhgACQnsJaAHAI4DABgACQnsJaAHAI4DAAAA.',
Im='Impavido:BAAALgAECgYJBgAAAA==.',
In='Inholy:BAAALgADCgcJEAAAAA==.Insights:BAAALgADCgMJAwAAAA==.',
Is='Isabella:BAAALgAECgEJAQABLgAFFAQJBgAEAHkLAA==.',
It='Ithopel:BAABLgAECn8jAAITAAYJACF9KAASAgATAAYJACF9KAASAgAAAA==.',
Ja='Jalista:BAAALgADCgMJAwAAAA==.Jayc:BAACLgAFFH8FAAIYAAMJwhtPLgAQAQAYAAMJwhtPLgAQAQAuAAQKfx0AAhgACAlgHiF0AOoBABgACAlgHiF0AOoBAAAA.',
Je='Jereico:BAACLgAFFH8YAAIKAAcJwCPkAACQAgAKAAcJwCPkAACQAgAuAAQKfzAAAgoACQmJJgMBAMoDAAoACQmJJgMBAMoDAAAA.Jeryhn:BAACLgAFFH8UAAIQAAcJZxJAAgDZAQAQAAcJZxJAAgDZAQAuAAQKfzAAAhAACQkzGhUTAHoCABAACQkzGhUTAHoCAAAA.',
Jo='Joeynodz:BAAALgADCgYJEgAAAA==.Jortshorts:BAABLgAECn8hAAIgAAcJDQnnCgAzAQAgAAcJDQnnCgAzAQAAAA==.',
Jr='Jray:BAABLgAECn8VAAILAAYJGBnPZAC3AQALAAYJGBnPZAC3AQAAAA==.',
Ju='Juggalo:BAABLgAECn8nAAMVAAkJOx/AAACbAgAVAAgJQCHAAACbAgAKAAIJhhKTQQBMAAAAAA==.June:BAACLgAFFH8WAAIRAAcJoBiuAQAaAgARAAcJoBiuAQAaAgAuAAQKfzAAAhEACQmNIbIEAB0DABEACQmNIbIEAB0DAAAA.Juuju:BAAALgAECgEJAQAAAA==.',
Ka='Kaldriss:BAAALgAECgEJAQAAAA==.Kalen:BAAALgADCgEJAgAAAA==.Katashimus:BAAALgAECgQJBQAAAA==.Kawasuoo:BAAALgAECgUJDgAAAA==.Kaze:BAAALgAECgUJBgABLgAECgYJFAAOAG4dAA==.',
Kh='Khaotichic:BAAALgAECgQJBwAAAA==.Khrenak:BAAALgAECgQJCgAAAA==.',
Ki='Kickpunch:BAAALgAECgUJBQAAAA==.Kirah:BAACLgAFFH8FAAIKAAIJFRM1HwCkAAAKAAIJFRM1HwCkAAAuAAQKfyAAAgoACQmtIWgEAEoDAAoACQmtIWgEAEoDAAEuAAUUBAkGAAQAeQsA.',
Ko='Koddin:BAABLgAECn8oAAILAAkJ4h3vBwCbAgALAAkJ4h3vBwCbAgAAAA==.Koreth:BAACLgAFFH8RAAMXAAUJVR0qAwCHAQAXAAQJVR0qAwCHAQANAAEJAACuBwA5AAAuAAQKfzYAAxcACQk2JVwHABoDABcACQk2JVwHABoDAA0ACAmWGg4EAHcCAAAA.Kornholyo:BAAALgAECgEJAQAAAA==.',
Ku='Kutuzov:BAAALgAECgQJBwAAAA==.',
Kw='Kwaiza:BAAALgAECgYJDwAAAA==.',
['Ká']='Káel:BAAALgAECgMJAwAAAA==.',
La='Lailaysia:BAAALgAECgYJBwAAAA==.Lamemoosaur:BAAALgADCgIJAgABLgAECgYJCgAFAAAAAA==.Laríca:BAACLgAFFH8FAAIQAAMJrSYPCQBbAQAQAAMJrSYPCQBbAQAuAAQKfycAAhAACAnhJe0AAE0DABAACAnhJe0AAE0DAAAA.Laustin:BAAALgAECgYJDwAAAA==.Laydout:BAAALgADCgYJAQABLgAECggJFwAEAD8hAA==.Laydoutyota:BAABLgAECn8XAAIEAAgJPyEaGQByAgAEAAgJPyEaGQByAgAAAA==.',
Le='Leag:BAABLgAECn8YAAMOAAcJEw8XHQBIAQAOAAcJEw8XHQBIAQAbAAEJJAmsPwA5AAAAAA==.Lemonruss:BAAALgADCgQJBAAAAA==.',
Li='Lilea:BAABLgAECn8nAAMEAAgJhxmjHwCjAQAEAAUJwBqjHwCjAQAhAAcJ4xFwNQCRAQAAAA==.Lithium:BAAALgADCgUJBQAAAA==.Littledeb:BAAALgAFFAEJAQAAAA==.',
Lo='Lolchaosbolt:BAAALgADCgYJBgAAAA==.Lortherian:BAAALgAECgYJCgAAAA==.Lowbo:BAAALgADCgUJBQAAAA==.Lowelfesteem:BAAALgADCgUJBQAAAA==.',
Lu='Lucille:BAAALgAECgIJAwAAAA==.',
['Lä']='Läwlbringer:BAAALgAECgIJAgAAAA==.',
['Lî']='Lîghtt:BAAALgADCgQJBAAAAA==.',
Ma='Mabritos:BAAALgAECgQJBQABLgAFFAYJGQAhAJ8eAA==.Maccabee:BAAALgAECgEJAQAAAA==.Mania:BAAALgADCgYJBgABLgAECggJFAAOALYZAA==.Mathath:BAAALgAECgUJDwAAAA==.Mathoras:BAAALgAECgYJDwAAAA==.',
Me='Meandean:BAAALgAECgIJBQAAAA==.Meatier:BAAALgAECgEJAQABLgAECggJFAAOALYZAA==.Meatless:BAAALgADCgcJDQAAAA==.',
Mi='Micmac:BAAALgAECgQJCQAAAA==.Miltonroe:BAABLgAECn8bAAIiAAYJbw4kCwAuAQAiAAYJbw4kCwAuAQAAAA==.Mirithul:BAAALgADCgYJBwAAAA==.Mischiëf:BAAALgAECgQJBAAAAA==.Mitsuri:BAABLgAECn8iAAIYAAgJnArYkgCtAQAYAAgJnArYkgCtAQAAAA==.',
Mo='Modr:BAAALgAECgkJCAAAAA==.Monkynate:BAAALgAECgYJCgAAAA==.Monsterskill:BAABLgAECn8fAAQPAAgJyhgeEAAsAQAPAAUJ4RMeEAAsAQABAAUJchk/RQAhAQACAAUJghNTLQAIAQAAAA==.Moonerva:BAAALgAECgYJEQAAAA==.Morpheos:BAAALgADCgQJBAAAAA==.Mortgage:BAAALgADCgUJBQAAAA==.',
Mu='Mutsu:BAAALgADCgcJBwAAAA==.',
Mv='Mvqchx:BAAALgAECgIJAwAAAA==.',
Na='Naturelass:BAAALgADCgUJBQAAAA==.',
Ne='Neotama:BAAALgAECggJEgAAAA==.Nethis:BAABLgAECn8ZAAIcAAYJ1hkeJgCmAQAcAAYJ1hkeJgCmAQAAAA==.',
Ni='Niatpacgrom:BAAALgAECggJDwAAAA==.Nivla:BAAALgADCgMJAwAAAA==.',
No='Norvis:BAAALgAECgQJBQAAAA==.Notdragon:BAAALgAECgQJDQAAAA==.',
Nu='Nukeddukem:BAAALgAECgYJDwAAAA==.',
Nv='Nv:BAAALgAECgcJDgAAAA==.',
Ny='Nymrod:BAABLgAECn8iAAMBAAgJHhTtGwDNAQABAAgJHhTtGwDNAQACAAIJpgdmZQBEAAAAAA==.',
['Ní']='Nír:BAAALgAECgQJBAAAAA==.',
Oj='Ojou:BAAALgADCgMJAwABLgAFFAMJAwAFAAAAAA==.',
Om='Omizzig:BAAALgAECgMJBgAAAA==.',
On='Onepunch:BAAALgAECgEJAQAAAA==.',
Or='Orcman:BAAALgADCgIJAgABLgADCgcJBwAFAAAAAA==.Orloran:BAAALgADCgIJAgAAAA==.',
Pa='Palthur:BAAALgAECgMJAwAAAA==.Parria:BAAALgAECgUJDQABLgAECgYJBwAFAAAAAA==.Pasqualino:BAAALgAECgYJCgAAAA==.Passionate:BAACLgAFFH8FAAIUAAMJWwn3DwDAAAAUAAMJWwn3DwDAAAAuAAQKfyUAAhQACAmfFLQJAIEBABQACAmfFLQJAIEBAAAA.',
Pe='Peepis:BAAALgADCgEJAQABLgAECggJFAAOALYZAA==.Pennance:BAABLgAECn8iAAIQAAkJ+xtZAwDSAgAQAAkJ+xtZAwDSAgAAAA==.',
Ph='Phatmidas:BAABLgAECn8ZAAILAAcJtBjtVgDdAQALAAcJtBjtVgDdAQAAAA==.',
Pl='Plagueground:BAACLgAFFH8IAAIGAAQJEB/xDAB7AQAGAAQJEB/xDAB7AQAuAAQKfzMAAgYACQmnJrUCAK8DAAYACQmnJrUCAK8DAAAA.Plutonyus:BAAALgAECgEJAQAAAA==.',
Po='Poc:BAABLgAECn8YAAIYAAYJOh3tdADoAQAYAAYJOh3tdADoAQAAAA==.Pockets:BAAALgAECgMJBwAAAA==.Potatopotato:BAABLgAECn8eAAIXAAgJShciHAAeAgAXAAgJShciHAAeAgAAAA==.Pounces:BAAALgAECgYJEQAAAA==.Powerfistin:BAAALgADCgcJBwAAAA==.',
Pr='Prosecutor:BAAALgAECgUJDAAAAA==.Prynts:BAABLgAECn8UAAILAAcJZB3oRAAVAgALAAcJZB3oRAAVAgAAAA==.Prøzak:BAAALgAECgUJBQAAAA==.',
Pu='Puetrid:BAAALgADCgYJBgABLgAECgQJBAAFAAAAAA==.',
Ra='Raanky:BAAALgAECgEJAQAAAA==.Radiantlight:BAAALgAECgEJAQAAAA==.Randomly:BAAALgADCgkJJQAAAA==.Raspberries:BAAALgAECgcJBwAAAA==.Rautha:BAAALgAECgYJCgAAAA==.Rayl:BAAALgAECgYJDwAAAA==.Razsputin:BAAALgAECgMJBwAAAA==.',
Re='Rekless:BAAALgADCgUJBQAAAA==.Rethgar:BAAALgAECgUJEAAAAA==.',
Rh='Rhaegosa:BAABLgAECn8dAAQKAAgJXRUTHgDVAQAKAAcJZxUTHgDVAQAVAAIJcA2nNQBoAAAUAAEJhQyyRQBDAAAAAA==.Rhavik:BAAALgADCgQJBAAAAA==.Rhekt:BAAALgADCgEJAQAAAA==.Rhokladar:BAAALgAECgIJBAAAAA==.',
Ri='Ridcully:BAABLgAECn8UAAITAAcJRRZuOADFAQATAAcJRRZuOADFAQAAAA==.Rimath:BAAALgAECgcJBAAAAA==.Rinswind:BAAALgADCgMJAwAAAA==.',
Ro='Robopacman:BAACLgAFFH8JAAIGAAQJIB5ZDgB1AQAGAAQJIB5ZDgB1AQAuAAQKfyoAAgYACAlnJBkPACMDAAYACAlnJBkPACMDAAAA.Rodstewart:BAACLgAFFH8PAAMEAAcJihZbCgAPAQAEAAUJxBdbCgAPAQAhAAQJXwzeFAD2AAAuAAQKfyIAAwQACQn+Ik8WAIYCAAQACAmcIk8WAIYCACEABwnOH4gmAPIBAAAA.Roofeo:BAAALgAECgYJCgAAAA==.Rotdaddy:BAAALgAECgcJEwAAAA==.',
Ry='Ryoshin:BAAALgADCgEJAQABLgAECgYJDQAFAAAAAA==.Ryzze:BAAALgADCgYJBgAAAA==.',
Sa='Salas:BAAALgAECgcJEAAAAA==.Salino:BAAALgAECgEJAQAAAA==.Salinoster:BAAALgADCgEJAQAAAA==.Salordell:BAAALgADCgIJAwAAAA==.Sam:BAAALgADCgEJAQAAAA==.Sarate:BAAALgAECgYJEwAAAA==.Savannah:BAABLgAFFH8GAAIEAAQJeQvHDgBDAQAEAAQJeQvHDgBDAQAAAA==.Savvtwo:BAAALgADCgcJBwABLgAFFAYJEgADADMlAQ==.',
Sc='Scathach:BAABLgAECn8gAAMDAAcJqB0eEADwAQADAAcJqB0eEADwAQAjAAQJURgpRADmAAAAAA==.Scorandom:BAAALgAECgEJAQAAAA==.',
Se='Sezra:BAAALgADCgkJAQAAAA==.',
Sh='Shamalam:BAAALgADCgEJAQAAAA==.Shei:BAAALgAECgIJAgAAAA==.Sheidon:BAAALgAECgQJBAAAAA==.Shinanigans:BAAALgAECgUJCgAAAA==.Shruikan:BAAALgADCggJDAAAAA==.',
Si='Silverslam:BAAALgAECgEJAQABLgAECgYJDgAFAAAAAA==.Sinatra:BAAALgAECgIJBAABLgAECgYJFAAOAG4dAA==.Siqodel:BAAALgADCgYJCAAAAA==.',
Sk='Skurge:BAAALgAECgYJCgAAAA==.',
Sl='Slamb:BAAALgAECgYJBwAAAA==.Slimetongue:BAAALgADCgMJAwAAAA==.',
Sm='Smaaug:BAAALgADCgMJAwAAAA==.',
So='Solstis:BAAALgAECggJDgAAAA==.Sorzsnipe:BAAALgADCgQJBAAAAA==.',
Sp='Spellchücker:BAAALgAECgcJDQAAAA==.Spfzero:BAAALgAECgEJAQAAAA==.',
St='Staggered:BAACLgAFFH8LAAIMAAQJoB7GBQB1AQAMAAQJoB7GBQB1AQAuAAQKfyUAAwwACAkKIuwLAM8CAAwACAkKIuwLAM8CAB4AAQk1A8WMABwAAAAA.Stoneorcman:BAAALgADCgcJBwAAAA==.Stormriderr:BAAALgAECgUJBwAAAA==.',
Su='Subdofu:BAAALgADCgQJBAABLgAECgcJFwAXAN0cAA==.Subtox:BAABLgAECn8XAAMXAAcJ3RxIIQDvAQAXAAcJ3RxIIQDvAQANAAEJkgu2HwA0AAAAAA==.',
Sw='Sweetcool:BAAALgAECgUJCQABLgAECggJKAAEAN4hAA==.',
Sy='Syphilistjt:BAABLgAECn8WAAIdAAgJ0xLFFwDgAQAdAAgJ0xLFFwDgAQAAAA==.Syphillis:BAAALgAECgQJBQAAAA==.',
['Sá']='Sálud:BAACLgAFFH8HAAIkAAMJUxjnDgAMAQAkAAMJUxjnDgAMAQAuAAQKfx4AAyQACAlMH30PAKkCACQABwkNIX0PAKkCACUABwmYGZEFAK4BAAAA.',
['Sê']='Sêp:BAAALgAECgUJCQAAAA==.',
Ta='Tanissaria:BAAALgADCgEJAQAAAA==.Tarhealeon:BAABLgAECn8kAAMQAAgJiBqZIQARAgAQAAgJiBqZIQARAgALAAYJRxJ3PwBLAQAAAA==.Tarmander:BAAALgAECgYJDgAAAA==.Taylörshift:BAAALgAECgQJBwAAAA==.',
Te='Telahnicus:BAAALgADCgEJAQAAAA==.Terranox:BAAALgADCgMJAwAAAA==.Testostauren:BAAALgAECgMJBgAAAA==.',
Th='Thabigone:BAAALgAECgYJCwAAAA==.Thalnaria:BAAALgAECgYJCwAAAA==.Threebuttons:BAAALgAECgUJCAABLgAFFAMJBQAUALkEAA==.Thunderkis:BAAALgAECgQJCAAAAA==.',
Ti='Tiewiz:BAABLgAECn8aAAMYAAgJYQxRPwBwAQAYAAgJMAlRPwBwAQAmAAUJbg0wBgDJAAAAAA==.',
To='Tointjoker:BAAALgAECgMJBAAAAA==.Tolun:BAABLgAECn8uAAIYAAkJnxYiUQBEAgAYAAkJnxYiUQBEAgAAAA==.Tosan:BAAALgADCggJDgAAAA==.',
Tr='Treeplague:BAABLgAECn8fAAMcAAgJvgmFFABeAQAcAAgJvgmFFABeAQAdAAUJ8wq7HQDuAAAAAA==.Trypleg:BAAALgAECgMJAwAAAA==.',
Tu='Tungie:BAABLgAECn8aAAIGAAgJziBZDQBaAgAGAAgJziBZDQBaAgAAAA==.Turn:BAACLgAFFH8XAAMBAAcJYhZuCAChAQABAAUJrxxuCAChAQACAAUJ2w22AwBcAQAuAAQKfzEABAEACQmrI8MUANkCAAEACAmrI8MUANkCAAIAAwk6HysrABMBAA8AAQkAAEMTAAAAAAAA.Turtleduck:BAAALgAECgUJDgAAAA==.Tuskbreaker:BAAALgAECgIJAgAAAA==.',
Tw='Twostrokes:BAAALgAECgEJAQAAAA==.',
Ty='Tyrese:BAAALgADCggJEAAAAA==.',
Uf='Uffin:BAAALgAECgQJBQAAAA==.',
Um='Umbryx:BAAALgAECgMJBAAAAA==.',
Un='Unagi:BAAALgAECgQJBAAAAA==.Unholy:BAAALgADCgIJAgAAAA==.',
Va='Valdi:BAAALgAECgYJEAAAAA==.',
Ve='Velthera:BAABLgAECn8XAAIUAAgJCyJHBAAQAwAUAAgJCyJHBAAQAwAAAA==.Venomette:BAAALgAECgMJBQAAAA==.Venomlight:BAAALgADCgIJAgAAAA==.Venratzi:BAAALgAECgQJBAAAAA==.',
Vo='Voridor:BAAALgADCgEJAQAAAA==.Voulk:BAAALgAFFAMJAwABLgAFFAcJFwAUAP8dAA==.',
Vy='Vyllan:BAAALgAECggJDgAAAA==.',
Wa='Waldgeist:BAAALgAECgUJBQABLgAECggJFAAOALYZAA==.Walthur:BAAALgADCgkJDQAAAA==.Waobby:BAAALgADCgIJAgAAAA==.Warrpigg:BAAALgAECgEJAQAAAA==.Waterdrinker:BAAALgAECgIJAgAAAA==.Wavybone:BAAALgAECgEJAgAAAA==.',
Wh='Whoarlock:BAAALgADCgMJAwAAAA==.',
Wo='Wo:BAAALgADCgMJAwAAAA==.',
Wu='Wutangstyle:BAAALgAECgIJAgABLgAECggJFAAOALYZAA==.',
Wy='Wyatta:BAAALgADCgIJAgAAAA==.',
Xe='Xelinia:BAACLgAFFH8PAAIcAAUJnBJgCAA7AQAcAAUJnBJgCAA7AQAuAAQKfyEAAhwACQkCH2kMAL0CABwACQkCH2kMAL0CAAAA.Xen:BAAALgAECgYJBgAAAA==.',
Xf='Xfortune:BAAALgADCgcJCQAAAA==.',
Xh='Xholycritz:BAAALgAECgMJAwAAAA==.',
Xu='Xuefeng:BAACLgAFFH8GAAIeAAMJ0AcbDQDQAAAeAAMJ0AcbDQDQAAAuAAQKfyoAAh4ACAk6HGUIAPkBAB4ACAk6HGUIAPkBAAAA.',
Ye='Yenchmeister:BAACLgAFFH8WAAMOAAcJSBtBAwDDAQAOAAUJuBxBAwDDAQAbAAUJVxUAAgBiAQAuAAQKfygAAw4ACQkaJeQJABEDAA4ACQkaJeQJABEDABsAAgl3IB4oAK4AAAAA.',
Yo='Youngbusta:BAABLgAECn8pAAIYAAgJqSOFCQClAgAYAAgJqSOFCQClAgAAAA==.',
Yu='Yuta:BAAALgAECgYJDQAAAA==.',
Za='Zad:BAAALgADCgIJAgAAAA==.',
Ze='Zenrac:BAAALgADCgUJBQAAAA==.Zeromus:BAAALgAECgIJAgAAAA==.',
Zi='Zilvanic:BAABLgAECn8eAAQSAAgJ5Q/cDAAyAQASAAgJoA3cDAAyAQALAAUJWBDnYQDwAAAQAAMJfAH6ggBsAAAAAA==.Zilvanion:BAAALgAECgQJBAAAAA==.',
Zo='Zourknight:BAAALgADCgcJDwAAAA==.Zourlock:BAAALgAECgYJCgAAAA==.',
Zu='Zulvaz:BAAALgAECgIJAgAAAA==.Zurey:BAABLgAECn8rAAIDAAkJPwvnGwCNAQADAAkJPwvnGwCNAQAAAA==.',
Zy='Zynjamin:BAACLgAFFH8UAAIVAAYJeSM9AAADAgAVAAYJeSM9AAADAgAuAAQKfy4AAhUACQkLJC8AANsDABUACQkLJC8AANsDAAAA.',
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

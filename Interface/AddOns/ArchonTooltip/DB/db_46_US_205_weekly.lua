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

local lookup = {'Warlock-Demonology','Warlock-Destruction','DemonHunter-Devourer','Hunter-Marksmanship','Unknown-Unknown','DeathKnight-Unholy','DeathKnight-Blood','Shaman-Restoration','Shaman-Elemental','Evoker-Augmentation','Monk-Brewmaster','Rogue-Assassination','Warlock-Affliction','Paladin-Holy','Monk-Mistweaver','Paladin-Retribution','Paladin-Protection','Druid-Restoration','Evoker-Preservation','Evoker-Devastation','Rogue-Outlaw','Rogue-Subtlety','Mage-Frost','DemonHunter-Vengeance','Warrior-Protection','Warrior-Arms','Warrior-Fury','Priest-Shadow','Priest-Discipline','Monk-Windwalker','Priest-Holy','Hunter-BeastMastery','Druid-Feral','Hunter-Survival','Shaman-Enhancement','DemonHunter-Havoc','Druid-Balance','Mage-Arcane',}
local provider = {region='US',realm='Stonemaul',name='US',type='weekly',zone=46,date='2026-04-24',data={Aa='Aannte:BAACLgAFFH8RAAMBAAYJThj2BQDAAQABAAUJIhX2BQDAAQACAAMJvBiaBQAXAQAuAAQKfyIAAwEACQklIkgLAMIBAAEACQkVIkgLAMIBAAIABAnwHvcdAGABAAAA.Aardbark:BAAALgADCgEJAQAAAA==.',
Ac='Achtland:BAAALgAECgEJAQABLgAECgcJHgADAAEcAA==.',
Ad='Adekai:BAAALgADCgEJAQAAAA==.Adv:BAAALgAECgEJAQAAAA==.',
Ae='Aerestrix:BAAALgAECgUJBgAAAA==.',
Ai='Airvis:BAAALgAECgYJCwAAAA==.',
Al='Alacia:BAAALgAECgcJBwABLgAECgcJHAAEAOMRAA==.Albinomonk:BAAALgADCgcJBwAAAA==.',
An='Anankei:BAAALgAECgMJAwAAAA==.Annastrophic:BAAALgADCgMJAwAAAA==.Anrí:BAAALgAECgEJAQAAAA==.Antaria:BAAALgADCgcJFgAAAA==.Ante:BAAALgADCgUJAQAAAA==.Antiform:BAAALgAECgIJBQAAAA==.Antpony:BAAALgAECgIJAgABLgAECgYJCgAFAAAAAA==.',
Ar='Arcish:BAAALgAECgEJAgAAAA==.Arjun:BAAALgAECgQJCAAAAA==.Arkirla:BAAALgAECgEJAgAAAA==.Arkiyra:BAAALgAECgcJCAAAAA==.Arkyra:BAAALgAECgUJBQAAAA==.Arovix:BAAALgAECgUJCAAAAA==.',
As='Ashwey:BAAALgADCgkJCAAAAA==.',
At='Atom:BAAALgADCgkJFQAAAA==.',
Au='Aureille:BAAALgAECgYJCgAAAA==.',
Aw='Awoozehl:BAACLgAFFH8RAAMGAAUJlRrlEQBaAQAGAAQJlRrlEQBaAQAHAAEJAAAIFQBIAAAuAAQKfykAAgYACQm9JR0CALsDAAYACQm9JR0CALsDAAAA.',
Az='Azgrodon:BAABLgAECn8eAAMIAAgJpA0oDQBsAQAIAAgJpA0oDQBsAQAJAAMJjwwsbACSAAAAAA==.Azor:BAABLgAECn8XAAIDAAgJcR07HQCiAgADAAgJcR07HQCiAgAAAA==.',
Ba='Baja:BAAALgAECgMJAwAAAA==.Baldomar:BAAALgADCgUJCAAAAA==.Bangungot:BAAALgADCgMJAwABLgAFFAYJEwAKABIjAA==.Barzalie:BAAALgAECgYJDAABLgAFFAEJAQAFAAAAAA==.Bathrezz:BAAALgAECgcJEgAAAA==.',
Be='Beerbelly:BAAALgAFFAEJAQAAAA==.Beleaves:BAACLgAFFH8SAAILAAYJ/gSMBgBqAQALAAYJ/gSMBgBqAQAuAAQKfyoAAgsACQmmFjcbACoCAAsACQmmFjcbACoCAAAA.Belsnickel:BAAALgADCgYJCAAAAA==.Beorl:BAAALgADCgYJCAAAAA==.',
Bh='Bhackshots:BAAALgAECgQJDAABLgAECgcJIwAMABYhAA==.',
Bi='Bifurious:BAAALgAECgcJEQAAAA==.',
Bl='Bluereindeer:BAAALgAECggJCAAAAA==.',
Bo='Bobsstones:BAACLgAFFH8MAAMBAAYJ0BrHAwDkAQABAAYJGRrHAwDkAQACAAMJ9BsYBgANAQAuAAQKfyMABAIACQlCJT0GAGwCAAEABwkmIwIcAK0CAAIABgmDJD0GAGwCAA0AAglDJOkVANUAAAAA.Bonekitty:BAAALgAECgYJBgAAAA==.Bonkulo:BAAALgAECgYJBwAAAA==.Boofassist:BAABLgAECn8VAAIOAAgJ9ySDBAAmAwAOAAgJ9ySDBAAmAwABLgAFFAUJDgAPAD4VAA==.Boogey:BAAALgAECgMJBwAAAA==.Boompowwow:BAABLgAECn8VAAIJAAYJIxniNACDAQAJAAYJIxniNACDAQAAAA==.Boomsonic:BAAALgADCgUJBQABLgAECgcJEQAFAAAAAA==.Bophadeez:BAABLgAECn8WAAQOAAYJlR8eHwAgAgAOAAYJlR8eHwAgAgAQAAYJtQ/MjABhAQARAAEJPCMAOQBcAAAAAA==.',
Br='Broccoliz:BAECLgAFFH8SAAISAAYJxgvtAgC9AQASAAYJxgvtAgC9AQAuAAQKfysAAhIACQk5HtUYAHECABIACQk5HtUYAHECAAAA.Brokgar:BAAALgAECgYJCQAAAA==.Bruceleroy:BAAALgADCgEJAQAAAA==.Brutalsmasch:BAAALgADCgUJBQAAAA==.',
Bu='Bubu:BAAALgAECgEJAQAAAA==.',
Bw='Bwonshamdi:BAAALgAECgcJBwABLgAECgcJBwAFAAAAAA==.',
['Bõ']='Bõb:BAAALgAECgMJBQAAAA==.',
Ca='Cafca:BAABLgAECn8YAAICAAcJ+RO0AgBaAQACAAcJ+RO0AgBaAQAAAA==.Caitlin:BAAALgAECgEJAQABLgAECgkJHwAKAK0hAA==.Callyour:BAAALgADCgIJAgAAAA==.Cask:BAAALgADCgYJAQAAAA==.',
Ch='Chainsawloli:BAAALgADCgUJBQAAAA==.Changying:BAAALgAECgMJAwAAAA==.Cheekung:BAAALgAECgYJCgAAAA==.Choedankal:BAAALgADCgcJBwAAAA==.',
Cl='Clearlyumad:BAACLgAFFH8IAAMGAAUJdw9ZCQAwAQAGAAQJdw9ZCQAwAQAHAAEJAACeDgAAAAAuAAQKfxoAAgYACAmFHko8AEYCAAYACAmFHko8AEYCAAAA.Clèrick:BAABLgAECn8VAAIOAAYJFiTuFQBhAgAOAAYJFiTuFQBhAgAAAA==.',
Co='Coldcrow:BAAALgADCgEJAQAAAA==.Combination:BAAALgADCgIJAgABLgAECggJFgATAAsiAA==.Corruptions:BAAALgADCgEJAQAAAA==.',
Cr='Crux:BAAALgADCgQJBAAAAA==.',
Cy='Cyfrin:BAAALgADCgEJAQAAAA==.Cyânide:BAAALgADCgYJDQAAAA==.',
['Cõ']='Cõurage:BAAALgAECgYJCAAAAA==.',
Da='Dabbzyvoker:BAABLgAECn8ZAAMKAAgJEgZtDwD2AAAUAAYJowZ4IgAWAQAKAAgJTwVtDwD2AAAAAA==.Danathoor:BAAALgADCggJCAAAAA==.Danathor:BAAALgADCgcJBwAAAA==.Dangbro:BAAALgAECgIJAgAAAA==.Danteus:BAAALgADCgMJAwABLgAECgQJCwAFAAAAAA==.Darkrigh:BAAALgADCggJCAAAAA==.Darkwave:BAAALgAECgUJDgAAAA==.Darthdiddyus:BAACLgAFFH8PAAMVAAQJ3BqHAABoAQAVAAQJDBqHAABoAQAWAAMJtxSgDQAQAQAuAAQKfycABBUACAkAJHQAABgCABYABwlRIT8UAHICABUACAmaI3QAABgCAAwABAnJIdkKAIIBAAAA.Datdruidguy:BAAALgADCgUJBQABLgAECgYJBgAFAAAAAA==.Datlock:BAAALgADCgEJAQABLgAECgYJBgAFAAAAAA==.Datshammy:BAAALgAECgYJBgAAAA==.Daviculas:BAAALgADCggJCAAAAA==.Dawghawg:BAAALgAECgEJAQAAAA==.Dawnnie:BAABLgAECn8bAAIRAAgJiBXMDAD7AQARAAgJiBXMDAD7AQAAAA==.Dawsonrogers:BAAALgADCgMJBAAAAA==.Dayvastate:BAABLgAECn8XAAIGAAcJrRPcFgBbAQAGAAcJrRPcFgBbAQAAAA==.Dazshir:BAAALgADCgMJAwAAAA==.',
De='Deathbanana:BAAALgAFFAIJAwABLgAFFAYJEAAXAF8cAA==.Deaththreat:BAAALgAECgQJBAAAAA==.Delema:BAACLgAFFH8LAAIQAAQJMB6+AQCCAQAQAAQJMB6+AQCCAQAuAAQKfx8AAhAACAlaIUkiAKACABAACAlaIUkiAKACAAAA.Democrit:BAAALgAECgIJAgAAAA==.Demonjuice:BAAALgADCgIJAgAAAA==.Derpyblinker:BAABLgAECn8VAAIXAAYJQRDR0wBHAQAXAAYJQRDR0wBHAQAAAA==.Destructer:BAAALgAECgQJBAAAAA==.Devoured:BAAALgADCgMJAwAAAA==.',
Di='Dirtydinker:BAAALgAECgYJDQAAAA==.Disconneted:BAAALgADCgYJBgAAAA==.Dishwasher:BAAALgADCgIJAgAAAA==.Dixsard:BAABLgAECn8jAAMMAAcJFiHJBQApAgAMAAcJBiDJBQApAgAWAAcJSB1mIwDeAQAAAA==.',
Do='Doezenn:BAAALgADCgUJBQAAAA==.Dottprepared:BAACLgAFFH8PAAIYAAUJbg6yAABRAQAYAAUJbg6yAABRAQAuAAQKfyoAAhgACQm/IJcBAAcDABgACQm/IJcBAAcDAAAA.Dottyfu:BAAALgAECgYJBgAAAA==.Doubted:BAAALgAECgQJBAAAAA==.',
Dr='Drexl:BAACLgAFFH8HAAIZAAQJkwq0BQARAQAZAAQJkwq0BQARAQAuAAQKfycABBoACQnXEGAJABgCABoACQlSD2AJABgCABsABwkSBsllABwBABkAAgmHDHY7AHAAAAAA.Dril:BAAALgAECgUJEAAAAA==.Drognin:BAAALgADCgEJAQAAAA==.',
Du='Dudette:BAAALgAECgYJBwAAAA==.Dunlop:BAAALgAECgEJAQAAAA==.',
Dv='Dvmcquéén:BAABLgAECn8WAAMCAAcJ5xktCwANAgACAAcJ5xktCwANAgABAAIJBwQuBwFOAAAAAA==.',
Dw='Dweams:BAACLgAFFH8RAAIcAAYJBRs5AQAoAgAcAAYJBRs5AQAoAgAuAAQKfyYAAxwACQllI/8BAJkDABwACQllI/8BAJkDAB0ABAmrDMQ5ANkAAAAA.',
['Dâ']='Dântæ:BAAALgAECgQJCwAAAA==.',
['Dö']='Döts:BAAALgADCgMJAgAAAA==.',
['Dø']='Døctøred:BAAALgAECgYJEwAAAA==.',
Ec='Ectonight:BAAALgAECgMJAwAAAA==.',
Ed='Edgybob:BAAALgAECgMJAwAAAA==.',
Eg='Eggfooyung:BAACLgAFFH8OAAIPAAUJPhVrAgCCAQAPAAUJPhVrAgCCAQAuAAQKfy0AAw8ACQmbIRUEADADAA8ACQmbIRUEADADAB4ABwlPCCA7ADABAAAA.Egwene:BAAALgAECgYJBwAAAA==.',
El='Eldar:BAAALgAECgQJBAAAAA==.Elfchick:BAAALgADCgEJAQAAAA==.Elsâ:BAAALgAECgQJCAAAAA==.',
Em='Emwen:BAAALgADCgMJAwAAAA==.',
En='Endcredits:BAAALgAECgUJCwAAAA==.',
Et='Ether:BAABLgAECn8eAAIJAAgJzhPRKADNAQAJAAgJzhPRKADNAQAAAA==.',
Ev='Evieroot:BAAALgADCgMJAwAAAA==.Evoulker:BAACLgAFFH8SAAITAAYJMyDuAABWAgATAAYJMyDuAABWAgAuAAQKfyoAAhMACQkNH6YFAO4CABMACQkNH6YFAO4CAAAA.',
Ex='Exodyce:BAAALgAECgQJBAAAAA==.',
Ey='Eyecantsee:BAAALgADCgIJAgABLgADCgIJAgAFAAAAAA==.',
Fa='Faene:BAAALgAECgMJBgAAAA==.Faire:BAAALgADCgUJBQABLgAECgkJHwAKAK0hAA==.Fairytale:BAACLgAFFH8NAAMdAAYJFQpGAwDPAQAdAAYJFQpGAwDPAQAfAAEJMwjEEwBGAAAuAAQKfyoAAx0ACQlSIPsGANUCAB0ACQnxHPsGANUCAB8ABwn5HkISAE4CAAAA.Faitza:BAAALgAECgYJCgAAAA==.Fantastico:BAAALgAECgEJAQAAAA==.',
Fe='Felheim:BAAALgAFFAMJBAAAAA==.Fellitha:BAAALgAECgUJCgAAAA==.Fellithà:BAAALgAECgEJAQAAAA==.Felrend:BAAALgADCgMJAgAAAA==.Fentertained:BAAALgADCgcJCAAAAA==.',
Fi='Fiercevalkyr:BAAALgAECgkJBgAAAA==.Fists:BAABLgAECn8kAAMPAAgJ5xrfAgA0AgAPAAgJ5xrfAgA0AgALAAQJThaxXQDMAAAAAA==.Fizle:BAAALgAECgUJCwAAAA==.',
Fl='Flink:BAAALgAECgUJCgAAAA==.',
Fr='Friend:BAAALgAECgYJEAAAAA==.Frostmoan:BAAALgAFFAEJAQAAAA==.Frostyninja:BAABLgAECn8aAAIgAAYJzQePbAAiAQAgAAYJzQePbAAiAQAAAA==.',
Ga='Gabryal:BAAALgAECgYJDAAAAA==.Galthur:BAAALgADCgkJCgAAAA==.Garchomp:BAAALgAECgUJDQAAAA==.',
Ge='Gellina:BAAALgADCgkJCQAAAA==.Georg:BAACLgAFFH8LAAIQAAUJWxkLAwDIAQAQAAUJWxkLAwDIAQAuAAQKfyQAAhAACQmYJC4DAKMDABAACQmYJC4DAKMDAAAA.Gerbankis:BAAALgAECgMJAwAAAA==.',
Gh='Ghoul:BAABLgAECn8aAAIGAAgJjCNNAQDNAgAGAAgJjCNNAQDNAgAAAA==.Ghouligan:BAAALgAECgQJBAAAAA==.',
Gl='Glaiver:BAAALgAECgUJCQAAAA==.Glassjaw:BAAALgADCgUJBQAAAA==.',
Go='Goewin:BAAALgAECgQJBAABLgAECgcJHgADAAEcAA==.Gojo:BAAALgADCgYJDwAAAA==.Goodbye:BAAALgADCgUJBQAAAA==.Gorgrom:BAAALgADCgIJAgAAAA==.',
Gr='Greg:BAAALgAECgIJAgAAAA==.Gregorz:BAAALgAECgEJAQAAAA==.',
Gu='Gulgrimmar:BAACLgAFFH8PAAMJAAYJNiLwAQDxAQAJAAUJ/iPwAQDxAQAIAAEJPQxEIABRAAAuAAQKfykAAgkACQneJawAANkDAAkACQneJawAANkDAAAA.Guwudanielle:BAAALgAECgcJDwABLgAECgkJHwAKAK0hAA==.',
Ha='Hailsstorm:BAAALgADCgcJEgAAAA==.Hardfeelings:BAAALgAECgQJAwABLgAECgQJBAAFAAAAAA==.Harkness:BAAALgADCggJCQAAAA==.Hassif:BAAALgAECgEJAQAAAA==.',
He='Heimerdoodle:BAAALgAECgYJDwAAAA==.Hemus:BAAALgAECgMJAwAAAA==.Hexed:BAAALgAECgYJDAAAAA==.',
Hu='Hughue:BAAALgADCgUJBQAAAA==.Hugs:BAAALgADCgUJBQAAAA==.',
Hy='Hyuna:BAAALgADCgIJAgABLgAECgQJCAAFAAAAAA==.',
Ia='Iaso:BAAALgAECgYJCwAAAA==.',
Ic='Iconstar:BAAALgADCgMJAwAAAA==.',
Ig='Igneel:BAAALgADCgQJAQAAAA==.',
Ij='Ijustankedu:BAAALgAECgMJAwAAAA==.',
Ik='Ikiea:BAAALgAECgcJBwAAAA==.',
Il='Ilgrim:BAAALgAFFAIJAgAAAA==.Ilravenll:BAAALgAECgYJBwABLgAFFAIJAgAFAAAAAA==.Ilyana:BAACLgAFFH8LAAIXAAUJFRnrDAC0AQAXAAUJFRnrDAC0AQAuAAQKfyoAAhcACQkWJJYHAI4DABcACQkWJJYHAI4DAAAA.',
Im='Impavido:BAAALgADCgYJCQAAAA==.',
In='Inholy:BAAALgADCgEJAgAAAA==.Insights:BAAALgADCgMJAwAAAA==.',
Is='Isabella:BAAALgAECgEJAQABLgAECgkJHwAKAK0hAA==.',
It='Ithopel:BAABLgAECn8eAAISAAYJXSB2KAASAgASAAYJXSB2KAASAgAAAA==.',
Ja='Jalista:BAAALgADCgMJAwAAAA==.Jayc:BAABLgAECn8cAAIXAAgJYB4rdADqAQAXAAgJYB4rdADqAQAAAA==.',
Je='Jereico:BAACLgAFFH8TAAIKAAYJjCTkAACQAgAKAAYJjCTkAACQAgAuAAQKfyoAAgoACQkhJgMBAMoDAAoACQkhJgMBAMoDAAAA.Jeryhn:BAACLgAFFH8PAAIOAAYJYxE+AgDZAQAOAAYJYxE+AgDZAQAuAAQKfyoAAg4ACQkWGhcTAHoCAA4ACQkWGhcTAHoCAAAA.',
Jo='Joeynodz:BAAALgADCgYJEgAAAA==.Jortshorts:BAABLgAECn8aAAIhAAYJ4whAGwAZAQAhAAYJ4whAGwAZAQAAAA==.',
Jr='Jray:BAAALgAECgYJDwAAAA==.',
Ju='Juggalo:BAABLgAECn8kAAMUAAgJOiFxAABSAgAUAAgJOiFxAABSAgAKAAEJ8xOzYwAvAAAAAA==.June:BAACLgAFFH8RAAIPAAYJ5xqvAQAaAgAPAAYJ5xqvAQAaAgAuAAQKfyoAAg8ACQkbIbMEAB8DAA8ACQkbIbMEAB8DAAAA.Juuju:BAAALgADCgYJCAAAAA==.',
Ka='Kaldriss:BAAALgAECgEJAQAAAA==.Kalen:BAAALgADCgEJAgAAAA==.Katashimus:BAAALgAECgQJBQAAAA==.Kawasuoo:BAAALgAECgMJBwAAAA==.',
Kh='Khaotichic:BAAALgAECgQJBwAAAA==.Khrenak:BAAALgAECgQJCgAAAA==.',
Ki='Kickpunch:BAAALgAECgUJBQAAAA==.Kirah:BAABLgAECn8fAAIKAAkJrSFmBABKAwAKAAkJrSFmBABKAwAAAA==.',
Ko='Koddin:BAABLgAECn8fAAIQAAgJnxtMCQD1AQAQAAgJnxtMCQD1AQAAAA==.Koreth:BAACLgAFFH8KAAMWAAUJoRQtCABmAQAWAAQJoRQtCABmAQAMAAEJAACtBwA5AAAuAAQKfzAAAxYACQl7JFwHABoDABYACQlOJFwHABoDAAwACAmWGg0EAHcCAAAA.Kornholyo:BAAALgADCgMJAwAAAA==.',
Ku='Kutuzov:BAAALgAECgMJBAAAAA==.',
Kw='Kwaiza:BAAALgAECgYJDgAAAA==.',
['Ká']='Káel:BAAALgAECgMJAwAAAA==.',
La='Lamemoosaur:BAAALgADCgIJAgABLgAECgYJCgAFAAAAAA==.Laríca:BAABLgAECn8jAAIOAAgJMiViAAAiAwAOAAgJMiViAAAiAwAAAA==.Laustin:BAAALgAECgYJDAAAAA==.Laydout:BAAALgADCgYJAQABLgAECggJDwAFAAAAAA==.Laydoutyota:BAAALgAECggJDwAAAA==.',
Le='Leag:BAABLgAECn8YAAMbAAcJEw98DQBLAQAbAAcJEw98DQBLAQAaAAEJJAmmPwA5AAAAAA==.Lemonruss:BAAALgADCgQJBAAAAA==.',
Li='Lilea:BAABLgAECn8cAAIEAAcJ4xFwNQCRAQAEAAcJ4xFwNQCRAQAAAA==.Littledeb:BAAALgAECgcJDwAAAA==.',
Lo='Lolchaosbolt:BAAALgADCgYJBgAAAA==.Lortherian:BAAALgAECgQJBAAAAA==.Lowbo:BAAALgADCgUJBQAAAA==.',
Lu='Lucille:BAAALgAECgIJAgAAAA==.',
['Lä']='Läwlbringer:BAAALgAECgIJAgAAAA==.',
Ma='Mabritos:BAAALgAECgQJBQABLgAFFAYJFwAiAJ8eAA==.Maccabee:BAAALgAECgEJAQAAAA==.Mania:BAAALgADCgYJBgABLgAECgcJEQAFAAAAAA==.Mathath:BAAALgAECgQJCgAAAA==.Mathoras:BAAALgAECgQJCQAAAA==.',
Me='Meandean:BAAALgAECgIJAwAAAA==.Meatier:BAAALgAECgEJAQABLgAECgcJEQAFAAAAAA==.Meatless:BAAALgADCgcJDQAAAA==.',
Mi='Micmac:BAAALgAECgQJBgAAAA==.Miltonroe:BAABLgAECn8WAAIjAAYJtA1ZBgAmAQAjAAYJtA1ZBgAmAQAAAA==.Mirithul:BAAALgADCgYJBwAAAA==.Mischiëf:BAAALgADCgMJAwAAAA==.Mitsuri:BAABLgAECn8hAAIXAAgJnArokgCtAQAXAAgJnArokgCtAQAAAA==.',
Mo='Modr:BAAALgAECgkJBwAAAA==.Monkynate:BAAALgAECgQJCAAAAA==.Monsterskill:BAABLgAECn8eAAQNAAgJyhgeEAAsAQANAAUJ4RMeEAAsAQABAAUJchk2IgAUAQACAAUJghNULQAIAQAAAA==.Moonerva:BAAALgAECgUJCwAAAA==.Morpheos:BAAALgADCgQJBAAAAA==.Mortgage:BAAALgADCgUJBQAAAA==.',
Mv='Mvqchx:BAAALgAECgIJAgAAAA==.',
Na='Naturelass:BAAALgADCgUJBQAAAA==.',
Ne='Neotama:BAAALgAECggJEgAAAA==.Nethis:BAABLgAECn8XAAIcAAYJvhgXJgCmAQAcAAYJvhgXJgCmAQAAAA==.',
Ni='Niatpacgrom:BAAALgAECgcJDAAAAA==.Nivla:BAAALgADCgMJAwAAAA==.',
No='Norvis:BAAALgAECgQJBQAAAA==.Notdragon:BAAALgAECgMJDAAAAA==.',
Nu='Nukeddukem:BAAALgAECgYJCQAAAA==.',
Nv='Nv:BAAALgAECgcJDgAAAA==.',
Ny='Nymrod:BAABLgAECn8ZAAMBAAcJexFJFQBmAQABAAcJexFJFQBmAQACAAIJpgdfZQBEAAAAAA==.',
['Ní']='Nír:BAAALgAECgQJBAAAAA==.',
Oj='Ojou:BAAALgADCgMJAwABLgAFFAEJAQAFAAAAAA==.',
Om='Omizzig:BAAALgAECgMJAwAAAA==.',
Or='Orcman:BAAALgADCgIJAgAAAA==.Orloran:BAAALgADCgIJAgAAAA==.',
Pa='Palthur:BAAALgADCgIJAwAAAA==.Parria:BAAALgAECgMJBgAAAA==.Pasqualino:BAAALgAECgYJCgAAAA==.Passionate:BAABLgAECn8iAAITAAgJ+RNPFQD1AQATAAgJ+RNPFQD1AQAAAA==.',
Pe='Pennance:BAABLgAECn8fAAIOAAgJNB6uAQCfAgAOAAgJNB6uAQCfAgAAAA==.',
Ph='Phatmidas:BAABLgAECn8UAAIQAAYJFBv2VgDdAQAQAAYJFBv2VgDdAQAAAA==.',
Pl='Plagueground:BAACLgAFFH8FAAIGAAMJ+B+mHgAjAQAGAAMJ+B+mHgAjAQAuAAQKfysAAgYACQkjJbcCAK8DAAYACQkjJbcCAK8DAAAA.Plutonyus:BAAALgAECgEJAQAAAA==.',
Po='Poc:BAABLgAECn8YAAIXAAYJOh35dADoAQAXAAYJOh35dADoAQAAAA==.Pockets:BAAALgAECgMJBwAAAA==.Potatopotato:BAABLgAECn8cAAIWAAgJShckHAAeAgAWAAgJShckHAAeAgAAAA==.Pounces:BAAALgAECgYJEQAAAA==.Powerfistin:BAAALgADCgcJBwAAAA==.',
Pr='Prosecutor:BAAALgAECgUJDAAAAA==.Prynts:BAABLgAECn8UAAIQAAcJZB3vRAAVAgAQAAcJZB3vRAAVAgAAAA==.',
Pu='Puetrid:BAAALgADCgYJBgABLgAECgQJBAAFAAAAAA==.',
Ra='Raanky:BAAALgAECgEJAQAAAA==.Radiantlight:BAAALgAECgEJAQAAAA==.Randomly:BAAALgADCggJHAAAAA==.Raspberries:BAAALgAECgcJBwAAAA==.Rautha:BAAALgAECgQJBAAAAA==.Rayl:BAAALgAECgYJCQAAAA==.Razsputin:BAAALgAECgMJBwAAAA==.',
Re='Rekless:BAAALgADCgUJBQAAAA==.Rethgar:BAAALgAECgUJCwAAAA==.',
Rh='Rhaegosa:BAABLgAECn8dAAQKAAgJXRUNHgDVAQAKAAcJZxUNHgDVAQAUAAIJcA2VCABKAAATAAEJhQyxRQBDAAAAAA==.Rhavik:BAAALgADCgQJBAAAAA==.Rhokladar:BAAALgAECgIJAgAAAA==.',
Ri='Ridcully:BAAALgAECgcJEwAAAA==.Rimath:BAAALgADCgkJAQAAAA==.Rinswind:BAAALgADCgMJAwAAAA==.',
Ro='Robopacman:BAACLgAFFH8FAAIGAAIJfiQIFAC6AAAGAAIJfiQIFAC6AAAuAAQKfyoAAgYACAlnJBYPACMDAAYACAlnJBYPACMDAAAA.Rodstewart:BAACLgAFFH8KAAMgAAYJyRlVCgAPAQAgAAQJIRxVCgAPAQAEAAMJrwvNFAD2AAAuAAQKfyIAAyAACQn+Ik8WAIYCACAACAmcIk8WAIYCAAQABwnOH4UmAPIBAAAA.Roofeo:BAAALgAECgQJBAAAAA==.Rotdaddy:BAAALgAECgYJDgAAAA==.',
Ry='Ryoshin:BAAALgADCgEJAQABLgAECgYJDQAFAAAAAA==.',
Sa='Salas:BAAALgAECgYJDAAAAA==.Salino:BAAALgADCgYJBgAAAA==.Salinoster:BAAALgADCgEJAQAAAA==.Salordell:BAAALgADCgIJAwAAAA==.Sam:BAAALgADCgEJAQAAAA==.Sarate:BAAALgAECgYJDAAAAA==.Savannah:BAAALgAECgYJDQABLgAECgkJHwAKAK0hAA==.Savvtwo:BAAALgADCgcJBwABLgAFFAUJEgADAI4jAQ==.',
Sc='Scathach:BAABLgAECn8eAAMDAAcJARw3EQB7AQADAAcJARw3EQB7AQAkAAQJURglRADmAAAAAA==.Scorandom:BAAALgAECgEJAQAAAA==.',
Se='Sezra:BAAALgADCgkJAQAAAA==.',
Sh='Shamalam:BAAALgADCgEJAQAAAA==.Shei:BAAALgAECgIJAgAAAA==.Sheidon:BAAALgAECgQJBAAAAA==.Shinanigans:BAAALgAECgUJCgAAAA==.Shruikan:BAAALgADCggJDAAAAA==.',
Si='Silverslam:BAAALgAECgEJAQAAAA==.Sinatra:BAAALgAECgIJBAABLgAECgYJFAAbAG4dAA==.Siqodel:BAAALgADCgYJCAAAAA==.',
Sk='Skurge:BAAALgAECgQJBAAAAA==.',
Sl='Slamb:BAAALgAECgYJBwAAAA==.Slimetongue:BAAALgADCgMJAwAAAA==.',
So='Solstis:BAAALgAECggJDgAAAA==.Sorzsnipe:BAAALgADCgQJBAAAAA==.',
Sp='Spellchücker:BAAALgAECgcJDQAAAA==.Spfzero:BAAALgAECgEJAQAAAA==.',
St='Staggered:BAACLgAFFH8GAAILAAIJSRlDFwC3AAALAAIJSRlDFwC3AAAuAAQKfyUAAwsACAkKIuwLAM8CAAsACAkKIuwLAM8CAB4AAQk1A76MABwAAAAA.Stormriderr:BAAALgAECgUJBQAAAA==.',
Su='Subdofu:BAAALgADCgQJBAABLgAFFAIJBAAFAAAAAA==.Subtox:BAAALgAFFAIJBAAAAA==.',
Sw='Sweetcool:BAAALgAECgQJBQABLgAECggJHQAgANEhAA==.',
Sy='Syphilistjt:BAABLgAECn8WAAIdAAgJ0xLIFwDgAQAdAAgJ0xLIFwDgAQAAAA==.Syphillis:BAAALgAECgMJAwAAAA==.',
['Sá']='Sálud:BAABLgAECn8XAAIlAAcJDSF9DwCpAgAlAAcJDSF9DwCpAgAAAA==.',
['Sê']='Sêp:BAAALgAECgMJAwAAAA==.',
Ta='Tanissaria:BAAALgADCgEJAQAAAA==.Tarhealeon:BAABLgAECn8VAAMOAAgJiBqYIQARAgAOAAgJiBqYIQARAgAQAAYJoApHLADuAAAAAA==.Tarmander:BAAALgAECgYJDgAAAA==.Taylörshift:BAAALgAECgQJBwAAAA==.',
Te='Telahnicus:BAAALgADCgEJAQAAAA==.Terranox:BAAALgADCgMJAwAAAA==.Testostauren:BAAALgAECgMJBQAAAA==.',
Th='Thabigone:BAAALgAECgEJAQAAAA==.Thalnaria:BAAALgAECgYJCgAAAA==.Threebuttons:BAAALgAECgMJAwABLgAECggJKQATAI4aAA==.Thunderkis:BAAALgADCggJCAAAAA==.',
Ti='Tiewiz:BAABLgAECn8UAAMmAAcJeAxQAwDNAAAXAAcJAQj62wA6AQAmAAUJbg1QAwDNAAAAAA==.',
To='Tointjoker:BAAALgAECgMJBAAAAA==.Tolun:BAABLgAECn8oAAIXAAkJkRQqUQBEAgAXAAkJkRQqUQBEAgAAAA==.Tosan:BAAALgADCggJDgAAAA==.',
Tr='Treeplague:BAABLgAECn8XAAMcAAgJqQmBNgA4AQAcAAcJDwmBNgA4AQAdAAUJ8wqWDAD3AAAAAA==.Trypleg:BAAALgAECgMJAwAAAA==.',
Tu='Tungie:BAAALgAECggJEwAAAA==.Turn:BAACLgAFFH8SAAMBAAYJ2RBpCAChAQABAAUJXhJpCAChAQACAAQJiQ6xAwBcAQAuAAQKfysABAEACQn4IsYUANkCAAEACAmkIsYUANkCAAIAAwk6HysrABMBAA0AAQkAAHw4ABUAAAAA.Turtleduck:BAAALgAECgMJBwAAAA==.Tuskbreaker:BAAALgAECgIJAgAAAA==.',
Tw='Twostrokes:BAAALgAECgEJAQAAAA==.',
Ty='Tyrese:BAAALgADCggJEAAAAA==.',
Uf='Uffin:BAAALgAECgQJBQAAAA==.',
Um='Umbryx:BAAALgAECgMJAwAAAA==.',
Un='Unagi:BAAALgADCgkJDQAAAA==.Unholy:BAAALgADCgIJAgAAAA==.',
Va='Valdi:BAAALgAECgYJCQAAAA==.',
Ve='Velthera:BAABLgAECn8WAAITAAgJCyJEBAAQAwATAAgJCyJEBAAQAwAAAA==.Venomette:BAAALgAECgMJBAAAAA==.Venomlight:BAAALgADCgIJAgAAAA==.Venratzi:BAAALgAECgQJBAAAAA==.',
Vo='Voridor:BAAALgADCgEJAQAAAA==.Voulk:BAAALgAECgMJAwABLgAFFAYJEgATADMgAA==.',
Vy='Vyllan:BAAALgAECgYJCwAAAA==.',
Wa='Walthur:BAAALgADCgkJDQAAAA==.Waobby:BAAALgADCgIJAgAAAA==.Warrpigg:BAAALgAECgEJAQAAAA==.Waterdrinker:BAAALgAECgIJAgAAAA==.',
Wh='Whoarlock:BAAALgADCgMJAwAAAA==.',
Wo='Wo:BAAALgADCgMJAwAAAA==.',
Wu='Wutangstyle:BAAALgAECgIJAgABLgAECgcJEQAFAAAAAA==.',
Wy='Wyatta:BAAALgADCgIJAgAAAA==.',
Xe='Xelinia:BAACLgAFFH8KAAIcAAUJQBKmCgAJAQAcAAUJQBKmCgAJAQAuAAQKfyAAAhwACQlgHmkMAL0CABwACQlgHmkMAL0CAAAA.Xen:BAAALgAECgUJBQAAAA==.',
Xf='Xfortune:BAAALgADCgcJCQAAAA==.',
Xh='Xholycritz:BAAALgAECgMJAwAAAA==.',
Xu='Xuefeng:BAABLgAECn8jAAIeAAgJiRkwEQBwAgAeAAgJiRkwEQBwAgAAAA==.',
Ye='Yenchmeister:BAACLgAFFH8SAAMbAAYJahs+AwDDAQAbAAUJuRo+AwDDAQAaAAQJPxb9AQBiAQAuAAQKfyIAAxsACQniIeUJABEDABsACQniIeUJABEDABoAAgl3ICAoAK4AAAAA.',
Yo='Youngbusta:BAABLgAECn8hAAIXAAgJqyH1MACuAgAXAAgJqyH1MACuAgAAAA==.',
Yu='Yuta:BAAALgAECgYJDQAAAA==.',
Za='Zad:BAAALgADCgIJAgAAAA==.',
Ze='Zenrac:BAAALgADCgUJBQAAAA==.Zeromus:BAAALgAECgIJAgAAAA==.',
Zi='Zilvanic:BAABLgAECn8XAAQRAAcJXA8PJADnAAARAAYJxg0PJADnAAAQAAQJLg07/gCYAAAOAAMJfAH5ggBsAAAAAA==.Zilvanion:BAAALgAECgQJBAAAAA==.',
Zo='Zourknight:BAAALgADCgYJCgAAAA==.Zourlock:BAAALgAECgQJBAAAAA==.',
Zu='Zulvaz:BAAALgAECgIJAgAAAA==.Zurey:BAABLgAECn8kAAIDAAgJ3AsXFABdAQADAAgJ3AsXFABdAQAAAA==.',
Zy='Zynjamin:BAACLgAFFH8PAAIUAAUJyiI9AAADAgAUAAUJyiI9AAADAgAuAAQKfyQAAhQACQn0Iy8AANsDABQACQn0Iy8AANsDAAAA.',
['Ðr']='Ðrèamless:BAAALgADCgIJAgAAAA==.',
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

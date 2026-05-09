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

local lookup = {'Warrior-Fury','Unknown-Unknown','Mage-Frost','Hunter-Survival','Warrior-Protection','Priest-Discipline','Druid-Restoration','Monk-Mistweaver','DeathKnight-Blood','DeathKnight-Unholy','Druid-Balance','Paladin-Retribution','Hunter-BeastMastery','Warlock-Affliction','Warlock-Demonology','Paladin-Holy','Priest-Shadow','Monk-Brewmaster','Shaman-Restoration','Monk-Windwalker','Rogue-Subtlety','Warlock-Destruction','Druid-Guardian','Shaman-Elemental','DeathKnight-Frost','DemonHunter-Vengeance','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Paladin-Protection','Rogue-Assassination','Rogue-Outlaw','Hunter-Marksmanship','Priest-Holy','DemonHunter-Devourer','Shaman-Enhancement','Druid-Feral','Warrior-Arms','DemonHunter-Havoc','Mage-Fire',}
local provider = {region='US',realm="Eldre'Thalas",name='US',type='weekly',zone=46,date='2026-05-08',data={Ac='Acharon:BAABLgAECn8jAAIBAAgJuhaeDgAFAgABAAgJuhaeDgAFAgAAAA==.',
Ad='Adrastus:BAAALgAECgYJDQAAAA==.',
Ae='Aeslin:BAAALgAECgYJDAABLgAECgYJDwACAAAAAA==.',
Ah='Ahsoka:BAAALgAECgYJDgAAAA==.',
Ai='Ain:BAAALgAFFAEJAQAAAA==.Ainslie:BAAALgAECgYJCAAAAA==.',
Al='Alarashinu:BAABLgAECn8eAAIDAAcJ6gRgjgD2AAADAAcJ6gRgjgD2AAAAAA==.Alataris:BAAALgADCgUJBwAAAA==.Alawae:BAABLgAECn8dAAIEAAgJCCCwBgBEAgAEAAgJCCCwBgBEAgAAAA==.Altria:BAAALgADCgcJEAAAAA==.',
Am='Amarco:BAABLgAECn8VAAIFAAgJgBWhEwDRAQAFAAgJgBWhEwDRAQAAAA==.',
An='Anahit:BAAALgAECgEJAQAAAA==.Angela:BAAALgADCgcJEAABLgAECggJJgAGALkTAA==.',
Ap='Apaka:BAAALgADCgEJAQAAAA==.',
Ar='Araedia:BAAALgAECgYJCAABLgAECgkJIAAHACkUAA==.Arahant:BAACLgAFFH8NAAIIAAQJihj9DgAvAQAIAAQJihj9DgAvAQAuAAQKfykAAggACQmbHP0MAIMCAAgACQmbHP0MAIMCAAAA.Aretas:BAABLgAECn8hAAMJAAgJaCB1BAByAgAJAAgJaCB1BAByAgAKAAEJsxZS3gA9AAAAAA==.Arriånna:BAAALgADCgkJFAAAAA==.Arrowpeen:BAAALgAECgQJBwAAAA==.',
As='Ashuffle:BAAALgAECgQJCAAAAA==.Asifa:BAAALgAECgYJDwAAAA==.Astinds:BAAALgADCgMJBQABLgAECgQJBQACAAAAAA==.',
At='Atherion:BAABLgAECn8hAAIDAAgJ0RJpNgDIAQADAAgJ0RJpNgDIAQAAAA==.',
Au='Aurod:BAAALgADCgMJBAAAAA==.',
Av='Avareh:BAAALgADCgIJAQAAAA==.Averix:BAAALgAECgEJAgAAAA==.Avranarada:BAABLgAECn8gAAMHAAkJKRRDFAAnAgAHAAkJKRRDFAAnAgALAAQJtBBwOQCjAAAAAA==.',
Az='Azung:BAABLgAECn8jAAIMAAgJeB8lIwCcAgAMAAgJeB8lIwCcAgAAAA==.',
Ba='Babaisyaga:BAACLgAFFH8RAAINAAQJqhmZCgANAQANAAQJqhmZCgANAQAuAAQKfysAAg0ACQlFI9IIAAUDAA0ACQlFI9IIAAUDAAAA.Baelia:BAAALgAECgEJAQAAAA==.Baimes:BAABLgAECn8cAAMOAAkJFBG2AgDyAQAOAAkJFBG2AgDyAQAPAAEJXwFnNAEUAAAAAA==.Baka:BAABLgAECn8tAAMQAAgJTCVaAQBdAwAQAAgJTCVaAQBdAwAMAAYJNBCikQBZAQAAAA==.Balance:BAAALgADCgIJAgAAAA==.Balinse:BAABLgAECn8VAAIFAAcJAxz1CADoAQAFAAcJAxz1CADoAQAAAA==.Bandruì:BAAALgAECgMJAwAAAA==.Bankpoo:BAACLgAFFH8OAAIKAAQJmhWcKABPAQAKAAQJmhWcKABPAQAuAAQKfyAAAwoACAkeHwAuAIACAAoABwntIgAuAIACAAkAAQlICBg6ACwAAAAA.Baragohn:BAAALgADCggJCAAAAA==.Barb:BAAALgAECgEJAQAAAA==.Barrelrollin:BAAALgAECgUJCAAAAA==.Batrito:BAABLgAECn8mAAMGAAgJuRMWHAC1AQAGAAgJuRMWHAC1AQARAAcJ5xJxFgCMAQAAAA==.Bawchu:BAAALgADCgcJBwAAAA==.',
Be='Bealzebubbà:BAAALgAECgYJEAAAAA==.Beastfodays:BAAALgAECgcJEgAAAA==.Beaviss:BAAALgADCgUJBQAAAA==.Benn:BAABLgAECn8VAAMQAAYJ1hXCMgCzAQAQAAYJ1hXCMgCzAQAMAAYJFwhfeQD5AAAAAA==.Bethlahammer:BAAALgAECgQJBAABLgAECgUJBgACAAAAAA==.',
Bi='Bigboom:BAAALgAECgEJAQAAAA==.Billcosbrew:BAACLgAFFH8FAAISAAMJnR8/FAAgAQASAAMJnR8/FAAgAQAuAAQKfyMAAhIACAkHJhcEAEsDABIACAkHJhcEAEsDAAAA.Biomechan:BAAALgAECgQJDQAAAA==.',
Bj='Bjorinn:BAAALgAECgIJAgAAAA==.',
Bl='Blackleaf:BAAALgAECgQJBwAAAA==.Blankshot:BAAALgADCgMJAwAAAA==.Blightsides:BAAALgAECgMJAwABLgAECggJGQATAFwPAA==.Blizzcon:BAABLgAECn8vAAMGAAcJMhbtEgCvAQAGAAcJMhbtEgCvAQARAAMJWAcOOwCUAAAAAA==.',
Bo='Borrgar:BAABLgAECn8XAAIMAAYJlSD4MwCtAQAMAAYJlSD4MwCtAQAAAA==.',
Br='Brackle:BAABLgAECn8iAAINAAgJNSDaDQBrAgANAAgJNSDaDQBrAgAAAA==.Bracori:BAACLgAFFH8LAAIIAAQJvhbVDwAjAQAIAAQJvhbVDwAjAQAuAAQKfyMAAwgACAkKEAooAHQBAAgACAkKEAooAHQBABQABgn0DPo3AD4BAAAA.Brandywynne:BAABLgAECn8mAAINAAgJ+g4ENAB9AQANAAgJ+g4ENAB9AQAAAA==.Brick:BAABLgAECn8pAAIVAAkJsSLbAAA4AwAVAAkJsSLbAAA4AwAAAA==.Briggsie:BAAALgADCgQJBgAAAA==.Briggsy:BAAALgAECgEJAQAAAA==.Brightfame:BAABLgAECn8vAAMWAAgJWRzKAgARAgAWAAgJ0RnKAgARAgAOAAcJ3xuYCAC/AQAAAA==.Bronny:BAAALgADCgMJAwAAAA==.Brownpepperz:BAAALgADCgEJAQAAAA==.Bruticus:BAAALgADCggJCAAAAA==.',
Bu='Bubblebull:BAAALgAECgEJAQAAAA==.Buffalox:BAAALgADCgUJBQAAAA==.Buffshagwell:BAAALgAECgUJCQAAAA==.Butterbllz:BAABLgAECn8YAAIMAAkJ5xkEaACvAQAMAAkJ5xkEaACvAQAAAA==.',
Ca='Caius:BAAALgADCgUJDAAAAA==.Calaine:BAAALgADCgcJBwAAAA==.Calypsio:BAABLgAECn8aAAIMAAYJbxFQYwAnAQAMAAYJbxFQYwAnAQAAAA==.Camany:BAAALgAECgcJEQAAAA==.Cantread:BAAALgAECgcJBwABLgAFFAMJCAARAKUMAA==.Caretakerz:BAABLgAECn8VAAIXAAYJ9xpKCgB3AQAXAAYJ9xpKCgB3AQAAAA==.Cartus:BAABLgAECn8fAAMYAAcJJgzhKQATAQAYAAcJJgzhKQATAQATAAQJgwVKYgBxAAAAAA==.',
Ce='Cedre:BAAALgADCgQJEAAAAA==.Celidoria:BAABLgAECn8aAAIMAAgJzx8+KwB3AgAMAAgJzx8+KwB3AgAAAA==.',
Ch='Chainfrost:BAAALgADCgEJAQAAAA==.Cheesepuff:BAABLgAECn8ZAAIPAAYJign7bADxAAAPAAYJign7bADxAAAAAA==.Chikara:BAAALgAECgQJBgAAAA==.Chittypalli:BAAALgADCgcJBwAAAA==.',
Ci='Cindera:BAAALgAECgMJAwABLgAFFAQJDwADAPQXAA==.Cinnibar:BAAALgADCgYJBgAAAA==.Cirï:BAAALgAECgYJDAAAAA==.Cisbick:BAAALgAECgYJEwAAAA==.',
Cl='Clamshell:BAABLgAECn8oAAMKAAkJpSJ8BQAGAwAKAAkJpSJ8BQAGAwAZAAEJAACbGgAAAAAAAA==.Clayier:BAAALgAECgQJCAAAAA==.',
Cn='Cntendr:BAAALgAECgMJBQAAAA==.Cntendrthree:BAAALgADCgMJAwAAAA==.',
Co='Codenike:BAABLgAECn8VAAMUAAYJlhpBFgB2AQAUAAYJlhpBFgB2AQAIAAQJCg/LNgCxAAAAAA==.Companionbea:BAAALgAECgQJBwAAAA==.Consume:BAAALgADCgQJBAABLgAECggJGwAMAOAiAA==.Corbanite:BAAALgAECgQJBQAAAA==.Corelheals:BAAALgADCgMJAwAAAA==.Corpsè:BAAALgAECgYJDgAAAA==.Covertyqt:BAABLgAECn8oAAIDAAkJQiH+BgD/AgADAAkJQiH+BgD/AgAAAA==.Coyote:BAAALgAECgkJAgAAAA==.',
Cp='Cptnhuman:BAABLgAECn8oAAIKAAkJeBftGgApAgAKAAkJeBftGgApAgAAAA==.',
Cr='Crunk:BAAALgAECgQJCAAAAA==.Cryptis:BAAALgADCgEJAQAAAA==.',
Da='Daboof:BAAALgAECgEJAQAAAA==.Daddydragon:BAAALgADCgYJCgAAAA==.Daemandred:BAAALgADCggJCQAAAA==.Daggere:BAAALgAECgEJAwAAAA==.Damaged:BAAALgAECgQJBAAAAA==.Damian:BAAALgAECgUJBwABLgAECgYJCgACAAAAAA==.Danfu:BAAALgADCgEJAQAAAA==.Danke:BAAALgAECgYJEQAAAA==.Dankrazor:BAAALgADCggJDAAAAA==.Dankz:BAAALgADCgEJAQAAAA==.Darckinz:BAAALgAECgYJCwAAAA==.Darkenmicky:BAABLgAECn8YAAISAAcJRA2dHwA4AQASAAcJRA2dHwA4AQAAAA==.Darkmickyz:BAAALgAECgQJBgAAAA==.Darkqueenx:BAAALgADCgIJAgAAAA==.Darksev:BAAALgADCgIJAgAAAA==.Darthbobula:BAACLgAFFH8OAAIMAAQJWwlSIQApAQAMAAQJWwlSIQApAQAuAAQKfyMAAgwACAnfIGgYANYCAAwACAnfIGgYANYCAAAA.Darthceril:BAAALgAECgUJBgAAAA==.Daswar:BAAALgAECgYJBwABLgAECgkJBwACAAAAAA==.Dayloc:BAABLgAECn8oAAIPAAkJHQ+mJQDTAQAPAAkJHQ+mJQDTAQAAAA==.',
De='Deataria:BAAALgAECgQJBAAAAA==.Deathrho:BAAALgADCgkJFQAAAA==.Delryth:BAAALgAECgQJBgAAAA==.Delyne:BAAALgADCgYJCAAAAA==.Demontyk:BAAALgADCgkJEAAAAA==.Denareas:BAAALgAECgYJCgAAAA==.Detox:BAAALgADCgQJBAAAAA==.',
Di='Diablõ:BAEBLgAECn8mAAIaAAkJXxzOAQCCAgAaAAkJXxzOAQCCAgABLgAECgIJAgACAAAAAA==.Dirtyd:BAAALgAECgQJBwAAAA==.Dirtydeeds:BAABLgAECn8nAAIKAAkJfRCXIAAGAgAKAAkJfRCXIAAGAgAAAA==.Divinetism:BAAALgAECgcJDQAAAA==.',
Dl='Dl:BAABLgAECn8yAAIRAAkJgh9jAgDxAgARAAkJgh9jAgDxAgAAAA==.',
Dr='Draccarys:BAAALgAECgcJCAAAAA==.Draekbee:BAABLgAECn8kAAQbAAgJFxUSGgBuAQAcAAYJZBiSFACfAQAbAAgJkBESGgBuAQAdAAEJwwdkSgAtAAAAAA==.Dragkohn:BAAALgAECgQJBAABLgAECgkJHQAQAI8kAA==.Dragonaged:BAAALgADCgMJAwAAAA==.Drakkarr:BAAALgADCgUJCQAAAA==.Drannek:BAAALgAECgEJAgAAAA==.Drimbirt:BAAALgAECgQJBAAAAA==.Drinkmormilk:BAAALgAECgYJCwAAAA==.Drogman:BAAALgAECgEJAQAAAA==.Droowin:BAAALgAECgEJAQABLgAECgUJCAACAAAAAA==.Drshockaloo:BAAALgADCgYJCgAAAA==.',
Du='Duvori:BAAALgAECgEJAQAAAA==.',
Dy='Dyspepsia:BAAALgADCgMJCAAAAA==.',
Eb='Ebullition:BAAALgAECgcJEgAAAA==.',
Ed='Edensfury:BAAALgAECgUJBgAAAA==.',
Ei='Eightyhd:BAAALgADCgkJCQAAAA==.Eigi:BAAALgAECgcJDwAAAA==.',
Ek='Ekthelion:BAABLgAECn8fAAIeAAcJORgdCgChAQAeAAcJORgdCgChAQAAAA==.',
El='Elavelin:BAAALgADCgUJCgAAAA==.Eldanon:BAABLgAECn8YAAIWAAYJayA0CgAbAgAWAAYJayA0CgAbAgAAAA==.Eleyert:BAABLgAECn8lAAIYAAkJBiQpAQBEAwAYAAkJBiQpAQBEAwAAAA==.Elwe:BAAALgAECgcJEwAAAA==.',
Em='Emmaga:BAAALgAECgYJEwAAAA==.Emrhakul:BAAALgADCgEJAQAAAA==.',
En='Enkidu:BAABLgAECn8ZAAINAAYJoBtJLgD5AQANAAYJoBtJLgD5AQAAAA==.Enseth:BAABLgAECn8aAAQbAAgJHRCvFgCMAQAbAAgJHRCvFgCMAQAcAAQJNQfZLQCsAAAdAAIJpAYMQwBVAAAAAA==.',
Er='Erotikzombie:BAABLgAECn8VAAIKAAYJcB6/LwC6AQAKAAYJcB6/LwC6AQAAAA==.',
Es='Esme:BAAALgAECgYJDQAAAA==.',
Eu='Eulogy:BAAALgAECgYJDQABLgAECgcJLwAGADIWAA==.',
Ex='Exene:BAAALgAECggJEwAAAA==.',
Fa='Faelwen:BAAALgAECgIJAgAAAA==.Fairious:BAABLgAECn8iAAMfAAgJSxU1BwBxAQAVAAgJpRPBEgCCAQAfAAcJaRA1BwBxAQAAAA==.Fangrell:BAAALgADCgEJAgABLgAECgkJCQACAAAAAA==.Faror:BAAALgAECgEJAQAAAA==.',
Fe='Feethunter:BAAALgAECgEJAQABLgAFFAYJGwAVABgaAA==.Felcon:BAAALgADCgMJBAAAAA==.Fellivath:BAAALgAECgYJBwAAAA==.Fenrirr:BAAALgADCgYJBgABLgAECgYJFwAMAJUgAA==.Fet:BAACLgAFFH8bAAMVAAYJGBoNAgDlAQAVAAYJxxgNAgDlAQAgAAQJag5nAgA3AQAuAAQKfykAAxUACAmLItkIAAQDABUACAmLItkIAAQDACAABgmpISIDAN4BAAAA.Feyu:BAEALgAECgYJCQABLgAECggJGAATAD4ZAA==.',
Fh='Fhatbashtud:BAAALgAECgIJAgAAAA==.',
Fi='Fireflies:BAAALgAFFAMJAwAAAA==.Firelore:BAAALgAECgcJAwABLgAECgkJBwACAAAAAA==.Fistsoiaaryn:BAAALgAECgUJBQAAAA==.',
Fl='Flatline:BAAALgAECgcJEQAAAA==.Flattymatty:BAAALgADCgYJBgAAAA==.Flöti:BAEBLgAECn8YAAITAAgJPhkiHQAxAgATAAgJPhkiHQAxAgAAAA==.',
Fo='Four:BAABLgAECn8cAAIMAAgJchAZQgB/AQAMAAgJchAZQgB/AQAAAA==.',
Fr='Frayla:BAAALgADCgMJAwAAAA==.Frostnips:BAAALgAECgYJCwAAAA==.Frysky:BAABLgAECn8UAAIXAAYJ+Q2BGQDkAAAXAAYJ+Q2BGQDkAAAAAA==.',
Fu='Furytotem:BAAALgADCgMJAwABLgAECgUJBwACAAAAAA==.Futz:BAABLgAECn8cAAIQAAcJfCQUBQDcAgAQAAcJfCQUBQDcAgAAAA==.Fuzzymage:BAAALgAECgEJAQAAAA==.',
Ga='Gadrolicus:BAAALgADCgEJAQAAAA==.Galadriell:BAABLgAECn8aAAMNAAgJMhqpIwDIAQANAAgJMhqpIwDIAQAhAAYJmQ9KQwBKAQAAAA==.Gargahmell:BAAALgADCgUJBQAAAA==.',
Ge='Gengarr:BAAALgAECgIJAQAAAA==.',
Gn='Gnomes:BAAALgADCgcJBwAAAA==.',
Go='Gooberz:BAAALgADCgYJBgAAAA==.Goobs:BAAALgADCgcJDwAAAA==.Goonxoxo:BAAALgADCgUJCAAAAA==.Gordoe:BAAALgADCgUJBQAAAA==.Gothberry:BAAALgADCgUJBgAAAA==.',
Gr='Graveborne:BAAALgADCgkJGwAAAA==.Gravess:BAABLgAECn8tAAMgAAkJXxtZAQByAgAgAAkJXxtZAQByAgAfAAIJThSGEQCSAAAAAA==.Gravewin:BAAALgADCgIJAgABLgAECgUJCAACAAAAAA==.Grendelheim:BAAALgAECgEJAQAAAA==.Grogar:BAAALgADCgMJAwAAAA==.',
Gu='Gurg:BAAALgAECgYJCwAAAA==.',
Gw='Gwynath:BAABLgAECn8YAAMiAAcJBSMFBQC6AgAiAAcJBSMFBQC6AgAGAAYJtxqgFwB6AQAAAA==.',
Ha='Hagrok:BAAALgADCgEJAQAAAA==.Haldael:BAAALgAECgMJAwAAAA==.Hammerfists:BAAALgAECgQJBQAAAA==.Hanbil:BAAALgAECgYJDQAAAA==.Handace:BAAALgAECgUJBQAAAA==.Hangezoe:BAAALgAECgIJAwABLgAECggJFQAFAIAVAA==.Hantak:BAAALgAECgQJBgAAAA==.Hathaendron:BAAALgADCgEJAQAAAA==.Hatsunemiku:BAAALgADCgcJDQAAAA==.Hawginmaw:BAAALgADCgMJAwAAAA==.',
He='Hemorrhagic:BAAALgADCgIJAgAAAA==.Heretic:BAAALgAECgQJBAAAAA==.',
Hi='Hiromi:BAABLgAECn8mAAIFAAgJjRM3EABeAQAFAAgJjRM3EABeAQAAAA==.',
Ho='Hoisin:BAABLgAECn8bAAISAAgJ2hVZFQCQAQASAAgJ2hVZFQCQAQAAAA==.Holyyballs:BAABLgAECn8WAAIQAAcJNx2PDABLAgAQAAcJNx2PDABLAgAAAA==.Hotrodbob:BAAALgAECgEJAgAAAA==.Hotshot:BAAALgADCgQJAwAAAA==.Howlymandel:BAAALgAECgMJAwABLgAECgkJCQACAAAAAA==.Hoytx:BAAALgAECgQJBAAAAA==.',
Hu='Huntstokill:BAAALgAECgMJBAAAAA==.Huskerfister:BAABLgAECn8lAAIUAAgJhiG6BQB+AgAUAAgJhiG6BQB+AgAAAA==.Hussion:BAAALgADCgMJBQAAAA==.',
['Hì']='Hìroko:BAAALgAECgYJEQAAAA==.',
Ia='Iaaryn:BAAALgAECgQJBAAAAA==.',
Ic='Icedemon:BAAALgAECgEJAgAAAA==.Icey:BAAALgADCgEJAgAAAA==.',
Il='Illiderp:BAAALgAECgQJCAABLgAECgQJDQACAAAAAA==.',
Im='Imananji:BAAALgAECgMJBAABLgAFFAQJDQAXALgPAA==.Imasurvivor:BAAALgADCgYJBgAAAA==.Imblind:BAABLgAECn8cAAIjAAgJSB/yEwAdAgAjAAgJSB/yEwAdAgAAAA==.Imperius:BAAALgADCgMJAwABLgAECgYJDwACAAAAAA==.',
In='Infernodruid:BAAALgAECgMJBAABLgAECgUJBwACAAAAAA==.Infinitie:BAAALgAECgEJAQAAAA==.Insillico:BAAALgAECgYJEgAAAA==.',
Io='Iog:BAAALgAECgYJCQAAAA==.',
Ip='Iplaydead:BAABLgAECn8eAAINAAcJHRiAKQCrAQANAAcJHRiAKQCrAQAAAA==.',
Ir='Iroh:BAAALgAECgcJEgAAAA==.Irondali:BAAALgADCgYJBgAAAA==.',
Is='Ismokeprot:BAAALgAECgQJBQAAAA==.',
Ja='Jakub:BAAALgAECgYJCQAAAA==.Jarinduva:BAAALgADCgcJFAAAAA==.Jawnson:BAABLgAECn8oAAMVAAkJDBcHBgBVAgAVAAkJDBcHBgBVAgAfAAIJ8RK5GABqAAAAAA==.',
Je='Jeffo:BAAALgAECgMJBQAAAA==.Jenefer:BAACLgAFFH8PAAMJAAQJyhgDCgAwAQAJAAQJyhgDCgAwAQAKAAEJRgdFVgBNAAAuAAQKfygAAgkACQk3IJ0GAMwCAAkACQk3IJ0GAMwCAAAA.Jerzak:BAAALgADCgYJCwAAAA==.',
Jo='Joemomo:BAABLgAECn8VAAIBAAYJHRITJQBKAQABAAYJHRITJQBKAQAAAA==.Joethebull:BAAALgADCgQJBAAAAA==.Johnbasilone:BAAALgAECgEJAgABLgAECgMJBAACAAAAAA==.Johnmoo:BAAALgADCgIJAgAAAA==.Johnthick:BAAALgADCgcJFAAAAA==.Jokerninja:BAAALgAECgYJCgAAAA==.Jondooss:BAAALgADCgkJEwAAAA==.Jonsholo:BAAALgAECgIJAwAAAA==.Josefina:BAAALgAECgYJCwAAAA==.',
Ju='Jubelum:BAAALgADCgQJBAAAAA==.',
Ka='Kailback:BAAALgAECggJEQAAAA==.Kait:BAABLgAECn8rAAMTAAkJvBqKEQAuAgATAAkJvBqKEQAuAgAkAAMJ3gdCJACVAAAAAA==.Kakarotto:BAAALgAECgMJAwABLgAECgYJBwACAAAAAA==.Kaladin:BAAALgAECgUJCgAAAA==.Kalathriel:BAAALgADCgcJBwAAAA==.Kalcifur:BAACLgAFFH8OAAIQAAQJHA1UEwAYAQAQAAQJHA1UEwAYAQAuAAQKfyQAAhAACAm0FEAqAOABABAACAm0FEAqAOABAAAA.Kaseofbeer:BAAALgAECgEJAgAAAA==.Kashisht:BAAALgADCgIJAgAAAA==.Kassanovva:BAAALgADCgIJAgABLgAFFAQJDwAJAMoYAA==.Kasstigate:BAAALgAECgYJEAABLgAFFAQJDwAJAMoYAA==.Kastiel:BAAALgAECgQJCQABLgAECgcJFQAFAAMcAA==.Kathtel:BAABLgAECn8WAAIDAAcJWgwWZQBHAQADAAcJWgwWZQBHAQAAAA==.Katstrider:BAABLgAECn8dAAINAAgJuhTfIwDHAQANAAgJuhTfIwDHAQAAAA==.Kattarea:BAAALgAECgMJAwABLgAECggJHQANALoUAA==.Kavica:BAAALgAECgYJDAABLgAECggJMQAHAGYkAA==.Kayotic:BAAALgADCgUJBQAAAA==.',
Ke='Kekw:BAAALgAECgUJDAAAAA==.Keldean:BAABLgAECn8dAAIFAAYJ6BtNDgB+AQAFAAYJ6BtNDgB+AQAAAA==.Kenji:BAAALgAECgEJAgAAAA==.Keryka:BAACLgAFFH8KAAIKAAQJcRjNKABOAQAKAAQJcRjNKABOAQAuAAQKfyEAAgoACQltIWAWAPYCAAoACQltIWAWAPYCAAAA.Keybomb:BAAALgAECgYJBgAAAA==.',
Kh='Khall:BAAALgAFFAEJAQAAAA==.Khere:BAAALgAECgEJAQAAAA==.',
Ki='Kirigiri:BAABLgAECn8aAAMHAAcJ5A2oRgD4AAAHAAcJ5A2oRgD4AAAXAAEJAABANAAlAAABLgAFFAQJDgAQABwNAA==.Kirøs:BAAALgAECgUJBQAAAA==.Kitanâ:BAAALgADCgMJBAAAAA==.Kiwi:BAAALgAECgEJAQAAAA==.',
Kn='Knom:BAAALgAECgcJCgAAAA==.',
Ko='Kohn:BAABLgAECn8dAAIQAAkJjyQXBgDAAgAQAAkJjyQXBgDAAgAAAA==.Kona:BAEALgAECgIJAgAAAA==.Kovalo:BAAALgAECgMJBAAAAA==.',
Kp='Kpegz:BAAALgADCgcJBwABLgAECgkJIwAMAOkeAA==.',
Kr='Krisjian:BAAALgADCgUJBQAAAA==.Kroh:BAACLgAFFH8MAAIlAAUJKhGQAgBcAQAlAAUJKhGQAgBcAQAuAAQKfyAAAiUACQlUIusEAMYCACUACQlUIusEAMYCAAAA.',
Ku='Kungfugriff:BAAALgAECgMJBAAAAA==.',
Ky='Kytana:BAAALgADCgQJBAAAAA==.',
La='Laisidhiel:BAAALgAECgYJCgAAAA==.Lateo:BAABLgAECn8uAAIVAAgJYhH3DQDCAQAVAAgJYhH3DQDCAQAAAA==.Lawz:BAABLgAECn8cAAQWAAcJlwepEgDAAAAWAAcJIwapEgDAAAAPAAYJ5QPalwCRAAAOAAMJQQtnEABxAAAAAA==.',
Le='Leafz:BAABLgAECn8eAAMHAAgJ+xTlHADcAQAHAAgJ+xTlHADcAQALAAEJnw01VQA5AAAAAA==.Leaonissa:BAAALgAECgEJAQAAAA==.Learn:BAAALgADCgYJBgAAAA==.Leleb:BAAALgAECgUJDAAAAA==.Lelianna:BAAALgAECgEJAQAAAA==.Lemonruss:BAACLgAFFH8HAAIMAAQJrAkbIAAtAQAMAAQJrAkbIAAtAQAuAAQKfyEAAgwACQkTGGcsAHICAAwACQkTGGcsAHICAAAA.Leshafrierne:BAAALgAECgUJCQAAAA==.Leshen:BAAALgAECgYJCQAAAA==.Lexia:BAABLgAECn8dAAMWAAcJdgV4EQDLAAAWAAcJdgV4EQDLAAAPAAUJXgLjmgCJAAAAAA==.',
Li='Lilturtz:BAAALgAECgEJAQABLgAECgcJGQAUAOYhAA==.Linnea:BAAALgAECgMJAwAAAA==.',
Lo='Loabones:BAAALgADCgcJDwAAAA==.Longhorn:BAABLgAECn8VAAIMAAYJARB4YwAnAQAMAAYJARB4YwAnAQAAAA==.Loni:BAAALgAECgYJDQAAAA==.Lookitsopz:BAAALgADCgQJBAAAAA==.Lorrenna:BAAALgAECgIJBQAAAA==.Lorrien:BAAALgAECgQJBAAAAA==.Lorré:BAAALgAECgYJBgABLgAECgQJBAACAAAAAA==.Lortpegsalot:BAABLgAECn8jAAIMAAkJ6R69EwBcAgAMAAkJ6R69EwBcAgAAAA==.Lostcause:BAAALgAECgEJAQAAAA==.Lowy:BAAALgADCgMJAwAAAA==.',
Lu='Lucena:BAABLgAECn8ZAAIiAAYJbiHiDQAJAgAiAAYJbiHiDQAJAgAAAA==.Lunas:BAAALgAECgMJBAABLgAECgYJDQACAAAAAA==.',
['Lö']='Lörö:BAAALgADCgQJBAAAAA==.',
Ma='Madamkluck:BAABLgAECn8fAAIHAAcJrR28EwAsAgAHAAcJrR28EwAsAgAAAA==.Maglubiyet:BAABLgAECn8VAAIkAAYJhBSpDAA+AQAkAAYJhBSpDAA+AQAAAA==.Magoz:BAAALgADCgcJCwAAAA==.Manhole:BAAALgAECgUJCQAAAA==.Markyb:BAABLgAECn8kAAIMAAkJXBBJLgDDAQAMAAkJXBBJLgDDAQAAAA==.Masamura:BAACLgAFFH8SAAIDAAUJOB0+JABgAQADAAUJOB0+JABgAQAuAAQKfywAAgMACQk/H9wdADcCAAMACQk/H9wdADcCAAAA.Mattor:BAAALgADCgYJBgABLgAECggJFQAFAIAVAA==.Maureanna:BAABLgAECn84AAIHAAgJgxuUDgBpAgAHAAgJgxuUDgBpAgAAAA==.Mavralle:BAAALgAECgUJBQAAAA==.',
Me='Medari:BAEBLgAECn8WAAIdAAgJGxe5BQA2AgAdAAgJGxe5BQA2AgAAAA==.Medwyna:BAAALgAECgcJBQAAAA==.Melorm:BAAALgAECgIJAgAAAA==.',
Mi='Minipig:BAAALgAECgIJAgAAAA==.Mirasharu:BAAALgAECgEJAQAAAA==.Mireille:BAAALgADCgkJFwAAAA==.Miseria:BAAALgADCgIJAgAAAA==.Mitsuri:BAAALgAECggJDwAAAA==.',
Mn='Mnkyman:BAAALgAECgQJBAAAAA==.',
Mo='Mommamoon:BAAALgAECgYJCgABLgAECgcJEgACAAAAAA==.Monachier:BAAALgAECgUJBgABLgAECgUJCQACAAAAAA==.Moonkin:BAAALgAECgYJDgAAAA==.Moonlïght:BAAALgAECgcJEgAAAA==.Moonrage:BAAALgADCgcJCwABLgAECgcJEgACAAAAAA==.Moose:BAAALgAECgYJEQAAAA==.Morganlefay:BAABLgAECn8hAAIPAAYJ5gGInwB9AAAPAAYJ5gGInwB9AAAAAA==.Morgona:BAAALgADCgEJAQAAAA==.Morlyn:BAABLgAECn8WAAIDAAcJqw0jZgBFAQADAAcJqw0jZgBFAQAAAA==.Mosho:BAAALgAECgEJAQABLgAFFAYJGwAVABgaAA==.Mousemist:BAABLgAECn8hAAMUAAgJRRtkEwCYAQAUAAcJLRpkEwCYAQAIAAcJhAVqTACkAAAAAA==.',
Mu='Mulangar:BAAALgADCgEJAQAAAA==.',
My='Mynameiskase:BAAALgAECgYJEQAAAA==.Mystìc:BAAALgAECgQJCwAAAA==.',
['Má']='Májorrobot:BAAALgAECgYJCQAAAA==.',
['Mä']='Mänjo:BAAALgAECgcJDwAAAA==.',
['Mó']='Móldy:BAAALgAECgEJAgAAAA==.',
['Mö']='Mönkey:BAAALgADCgQJBAAAAA==.',
Na='Nale:BAAALgADCgcJFwAAAA==.Namesgambit:BAAALgAECgEJAQABLgAFFAMJBQASAJ0fAA==.Namor:BAAALgADCgYJBgAAAA==.Nasforatu:BAAALgADCgUJBgAAAA==.Nattisca:BAAALgAECgIJAgAAAA==.Navani:BAAALgAECgUJCgAAAA==.',
Ne='Nedtusk:BAEALgADCgYJCQABLgAECggJIgARAKYSAA==.Nedvox:BAEBLgAECn8iAAIRAAgJphLmFgCIAQARAAgJphLmFgCIAQAAAA==.Nervous:BAAALgAECgQJCwABLgAECgkJBwACAAAAAA==.Nessà:BAAALgAECgQJBQAAAA==.Neveenn:BAABLgAECn8eAAMHAAgJcBahJwAXAgAHAAgJcBahJwAXAgALAAEJfAWAXgApAAAAAA==.Neverbakdown:BAAALgAECgQJBwAAAA==.Neverclaws:BAAALgADCgEJAQAAAA==.Nevernoctis:BAAALgADCggJEwAAAA==.',
Ni='Nightpigas:BAAALgADCgIJAgABLgAECgUJDAACAAAAAA==.',
No='Nohatcat:BAABLgAECn8ZAAMUAAcJ5iE5BwBWAgAUAAcJ5iE5BwBWAgAIAAMJUQzhTgBJAAAAAA==.Notoom:BAAALgAECgYJCgAAAA==.Noxle:BAAALgADCgIJAgAAAA==.',
Ny='Nyxara:BAABLgAECn8ZAAIPAAcJug9SRABcAQAPAAcJug9SRABcAQAAAA==.',
['Nè']='Nèzukõ:BAABLgAECn8UAAINAAcJzBvGJgC4AQANAAcJzBvGJgC4AQAAAA==.',
['Nø']='Nøtfuriøus:BAAALgADCgYJBQABLgAECgYJCgACAAAAAA==.',
['Nÿ']='Nÿte:BAAALgADCgYJDwAAAA==.',
Oc='Octavius:BAAALgAECgQJBwABLgAECgUJBgACAAAAAA==.',
Od='Oddbrew:BAAALgADCgEJAQAAAA==.Oddsaga:BAAALgADCgYJBgAAAA==.',
Oj='Ojore:BAEBLgAECn8UAAIZAAYJIBJqCAAcAQAZAAYJIBJqCAAcAQAAAA==.Ojoverde:BAACLgAFFH8JAAIPAAQJmAODPQDhAAAPAAQJmAODPQDhAAAuAAQKfykAAg8ACQnZGnMkAIECAA8ACQnZGnMkAIECAAAA.',
On='Ontahli:BAAALgADCgUJBQABLgAECggJJgAGALkTAA==.',
Or='Orian:BAAALgAECgEJAQAAAA==.Orleron:BAAALgADCgEJAQAAAA==.',
Ov='Overflare:BAAALgADCgMJBAAAAA==.',
Ow='Ow:BAAALgADCgUJCQAAAA==.',
Oz='Ozmà:BAAALgAECgUJDAAAAA==.Ozzdraugur:BAAALgAECgMJAwAAAA==.Ozzfu:BAAALgAECgQJBwAAAA==.Ozzsamdi:BAAALgAECgEJAQAAAA==.Ozzskelmir:BAAALgADCgYJDAAAAA==.',
Pa='Pajamas:BAABLgAECn8WAAIJAAYJgBwQEQBgAQAJAAYJgBwQEQBgAQAAAA==.Pallanquin:BAAALgAECgMJBQAAAA==.Pallywacker:BAAALgAECgYJEQAAAA==.Papichili:BAAALgADCgMJAwAAAA==.Pashnir:BAAALgADCggJCQAAAA==.',
Pe='Peachey:BAABLgAECn8cAAITAAcJFxdpHQDGAQATAAcJFxdpHQDGAQAAAA==.',
Ph='Phrantic:BAAALgAECgMJBAAAAA==.Phö:BAAALgADCgcJBwAAAA==.',
Pi='Pigas:BAAALgAECgUJDAAAAA==.Pikkel:BAAALgADCgIJAgAAAA==.Pillory:BAAALgADCgYJBgAAAA==.',
Pl='Platinïum:BAAALgAECgYJBgAAAA==.Playdoh:BAAALgADCgEJAQAAAA==.',
Pr='Priestling:BAAALgADCgkJDAAAAA==.Prncess:BAAALgAECgQJCAAAAA==.Prncsspuddlz:BAAALgAECgcJEgABLgAECgQJCAACAAAAAA==.',
Ps='Psychosix:BAABLgAECn8vAAIDAAkJZCSOAwBEAwADAAkJZCSOAwBEAwAAAA==.Psychros:BAAALgAECgUJBQAAAA==.',
Pu='Puzzledmind:BAAALgAECgMJAwAAAA==.',
['Pø']='Pøintblank:BAAALgADCgEJAQAAAA==.',
Qi='Qimiao:BAAALgADCgYJDQAAAA==.',
Qu='Quinberos:BAAALgADCgQJBAABLgAECgcJDQACAAAAAA==.',
Ra='Radchad:BAAALgAECgQJBQAAAA==.Raiistlin:BAAALgADCgQJBAABLgAECgYJFwAMAJUgAA==.Raiola:BAAALgAECgQJBQAAAA==.Rakuumn:BAAALgAECgEJAQABLgAECgEJAgACAAAAAA==.Ramdel:BAAALgADCgkJHgABLgAECggJHwAEAKgcAA==.Ramstryder:BAABLgAECn8fAAIEAAgJqBwuCAAlAgAEAAgJqBwuCAAlAgAAAA==.Rancidgravy:BAAALgADCgUJBgAAAA==.Rancor:BAAALgADCgEJAQAAAA==.Rapture:BAAALgADCgQJBAAAAA==.Rastabastion:BAACLgAFFH8SAAIFAAQJHSVvAgCwAQAFAAQJHSVvAgCwAQAuAAQKfxwAAgUACAk6JdkCADYDAAUACAk6JdkCADYDAAAA.',
Re='Rejuvanator:BAAALgADCgIJAgAAAA==.Rekmortal:BAABLgAFFH8LAAMmAAUJCBkCCAAnAQAmAAUJCRMCCAAnAQABAAQJ0hSlFwDzAAAAAA==.Rekoj:BAAALgADCgQJBAAAAA==.Rengell:BAABLgAECn8oAAINAAgJ9xcBGQAJAgANAAgJ9xcBGQAJAgABLgAECgkJCQACAAAAAA==.Resinya:BAAALgAECgcJCAAAAA==.Retnuh:BAAALgAECgEJAQAAAA==.',
Rh='Rhaazst:BAAALgADCgUJBQAAAA==.Rheagall:BAAALgAECgcJEgAAAA==.Rheagnar:BAAALgADCgIJAgAAAA==.',
Rm='Rmeech:BAAALgAECgYJDAAAAA==.',
Ro='Rowena:BAABLgAECn8rAAILAAkJfRo2FQBnAgALAAkJfRo2FQBnAgAAAA==.Rowynna:BAAALgAECgcJDQAAAA==.Roxydk:BAAALgAECgcJDAAAAA==.Roxymonk:BAAALgAECggJDwAAAA==.',
Ru='Ruxspin:BAAALgAECgYJDwAAAA==.',
Ry='Ryzedvoid:BAABLgAECn8RAAIjAAYJhwm6YQDbAAAjAAYJhwm6YQDbAAAAAA==.Ryzinneko:BAABLgAECn8kAAIHAAkJ6x9TDgBsAgAHAAkJ6x9TDgBsAgAAAA==.',
Sa='Sabend:BAACLgAFFH8UAAMPAAcJKw7KCACdAQAPAAYJ7hDKCACdAQAWAAEJYABqFABNAAAuAAQKfx8AAw8ACAmfHVspAGsCAA8ACAmfHVspAGsCABYAAQkAAFtmAEMAAAAA.Sablewolfe:BAAALgAECgIJAwAAAA==.Safaria:BAABLgAECn8VAAILAAUJ4x1QHABSAQALAAUJ4x1QHABSAQAAAA==.Sarlyssa:BAAALgADCgkJEQAAAA==.Saucymac:BAACLgAFFH8IAAIRAAMJpQyqEwDmAAARAAMJpQyqEwDmAAAuAAQKfyoAAxEACQkVIe8KANQCABEACAn8Iu8KANQCACIABQltHKwUALIBAAAA.',
Sc='Scofflaw:BAAALgADCgYJBgAAAA==.',
Se='Senath:BAABLgAECn8fAAMVAAcJtRxAEgCIAQAVAAYJpRxAEgCIAQAfAAIJbB1LEACsAAAAAA==.Sephrenia:BAAALgADCgUJCQAAAA==.Serandipity:BAAALgAECgYJDQABLgAFFAQJDwAJAMoYAA==.Seraphina:BAAALgAECgEJAQAAAA==.',
Sh='Shalorath:BAABLgAECn8ZAAIDAAcJpAyuXABaAQADAAcJpAyuXABaAQAAAA==.Shamanagans:BAAALgAECgUJBgAAAA==.Shamanigans:BAABLgAECn8ZAAITAAgJXA/EIgCfAQATAAgJXA/EIgCfAQAAAA==.Shammygoat:BAAALgAECgcJEwAAAA==.Shamncheese:BAAALgAECgQJAwAAAA==.Shania:BAAALgADCgUJBQAAAA==.Shaosun:BAAALgAECgYJDwAAAA==.Shaqattack:BAACLgAFFH8HAAIUAAQJORmVBgBYAQAUAAQJORmVBgBYAQAuAAQKfxoAAhQACAkYI0sGABwDABQACAkYI0sGABwDAAAA.Shaqattaq:BAAALgAECgYJEAABLgAFFAQJBwAUADkZAA==.Sharkmeat:BAABLgAECn8hAAIRAAgJlxoYCwASAgARAAgJlxoYCwASAgAAAA==.Sharktide:BAAALgADCgkJCQAAAA==.Shauriena:BAAALgADCgUJBwAAAA==.Shawnellie:BAAALgAECgcJDAAAAA==.Shawntelle:BAABLgAECn8cAAIEAAkJEiCoBQCvAgAEAAkJEiCoBQCvAgAAAA==.Shenlune:BAAALgAECgQJCAAAAA==.Sheutka:BAAALgAECgYJDwAAAA==.Shinaie:BAABLgAECn8cAAIRAAcJTgxKHgBKAQARAAcJTgxKHgBKAQAAAA==.Shockanduwu:BAAALgAECgYJEwAAAA==.Shruikan:BAAALgADCgYJDAABLgAECggJFQAFAIAVAA==.Shtylez:BAAALgAECgIJAgAAAA==.Shurshott:BAAALgADCgUJBAAAAA==.',
Si='Sigzil:BAAALgADCgUJCQAAAA==.Silth:BAAALgADCgkJHQAAAA==.Silvermisst:BAAALgAECgQJBAAAAA==.Silvermist:BAAALgADCgUJBQAAAA==.Silvertouch:BAAALgAECgEJAQABLgAECgUJBwACAAAAAA==.Sinariel:BAABLgAECn8aAAMIAAgJnRnxEQDWAQAIAAYJhBzxEQDWAQAUAAgJsxLMKgCHAQAAAA==.Sirdank:BAAALgADCgMJAwAAAA==.Sithus:BAAALgADCgQJBAAAAA==.',
Sl='Sliko:BAABLgAECn8UAAIMAAgJHglvYAAtAQAMAAgJHglvYAAtAQAAAA==.',
Sm='Smmoke:BAABLgAECn8oAAINAAkJEx1TEQBIAgANAAkJEx1TEQBIAgAAAA==.Smorko:BAAALgADCgYJBgAAAA==.',
Sn='Sneekypally:BAAALgAECgMJBgAAAA==.Sniperart:BAABLgAECn8YAAINAAcJzB5rFgAcAgANAAcJzB5rFgAcAgABLgAECggJIQAJAGggAA==.',
So='Sothh:BAAALgADCgYJBgABLgAECgYJFwAMAJUgAA==.Soull:BAABLgAECn8fAAIHAAgJDhxoDACFAgAHAAgJDhxoDACFAgAAAA==.',
Sp='Spacemoo:BAABLgAECn8ZAAMKAAcJhx26JADwAQAKAAcJhx26JADwAQAJAAEJhAHnPQAeAAAAAA==.',
Sq='Squall:BAAALgADCgcJCAAAAA==.',
St='Starface:BAACLgAFFH8NAAIXAAQJuA8wBQDjAAAXAAQJuA8wBQDjAAAuAAQKfykAAxcACQmaHrIEAKACABcACQmaHrIEAKACAAcAAQk9AfHpABsAAAAA.Starrlyte:BAAALgADCgUJBQAAAA==.Steelytree:BAAALgAECgEJAQAAAA==.Stefane:BAAALgAECgcJCgAAAA==.Steverogers:BAAALgAECgEJBgABLgAFFAMJBQASAJ0fAA==.Stocktonrush:BAAALgAECgEJAwABLgAFFAMJBQASAJ0fAA==.Stonewillow:BAAALgADCgUJBQAAAA==.Stormoond:BAAALgADCgEJAQAAAA==.Strongbad:BAAALgAECgYJEgAAAA==.Sturmx:BAABLgAECn8oAAInAAkJfRiNBQBcAgAnAAkJfRiNBQBcAgAAAA==.',
Su='Subaaâ:BAABLgAECn8hAAMaAAgJlSMGAQAzAwAaAAgJlSMGAQAzAwAjAAUJIhQ1hgAaAQABLgAECgYJJQABADggAA==.Subby:BAAALgADCgUJDQAAAA==.Subedei:BAABLgAECn8sAAMJAAkJHCLuAwCIAgAJAAgJOiLuAwCIAgAKAAUJ5Bo01ADYAAAAAA==.Sukati:BAAALgADCgMJAwAAAA==.Sunderhorn:BAAALgAECgYJDwAAAA==.Sutherman:BAAALgAECgEJAQAAAA==.',
Sv='Svictis:BAABLgAECn8hAAIKAAgJLBP1QgB0AQAKAAgJLBP1QgB0AQAAAA==.Sviictis:BAAALgADCggJEgAAAA==.',
Sw='Swab:BAAALgADCgEJAQABLgADCgcJFwACAAAAAA==.Swami:BAAALgADCgQJBAAAAA==.',
Sy='Syluxs:BAABLgAECn8YAAInAAcJqxUnDwCOAQAnAAcJqxUnDwCOAQAAAA==.Syrony:BAAALgADCgMJAwAAAA==.',
['Sû']='Sûshealä:BAAALgAECgYJEgAAAA==.',
Ta='Tadryth:BAAALgADCgQJBQAAAA==.Talila:BAABLgAECn8hAAIXAAYJFx8lCACrAQAXAAYJFx8lCACrAQAAAA==.Tamashi:BAAALgADCgIJAgAAAA==.Taxter:BAAALgADCgEJAQAAAA==.',
Te='Tealzitaz:BAAALgAECgEJAgAAAA==.Terrya:BAAALgADCgkJDgAAAA==.Teryail:BAAALgADCgEJAQAAAA==.',
Th='Thallion:BAAALgAECgMJBAAAAA==.Thalorian:BAAALgADCgIJAgAAAA==.Tharaa:BAAALgAECgUJBwAAAA==.Theycomeforu:BAAALgAECgIJAgAAAA==.Thiccklock:BAAALgAECgMJAwAAAA==.Thorwallen:BAAALgADCgYJBgABLgAECgYJFwAMAJUgAA==.',
Ti='Tickle:BAABLgAECn8YAAIlAAcJySC3AwBCAgAlAAcJySC3AwBCAgAAAA==.Tiermorthius:BAAALgADCgYJBgABLgAECgUJCQACAAAAAA==.Tirithor:BAABLgAECn8qAAIMAAgJ/xaiKwDPAQAMAAgJ/xaiKwDPAQAAAA==.',
To='Tockell:BAAALgADCgkJFgAAAA==.Tonakai:BAAALgAFFAIJAwAAAA==.Tony:BAAALgAECgYJCgABLgAECgcJDAACAAAAAA==.Torbin:BAAALgAECgYJDgAAAA==.Touchmywave:BAAALgADCgUJCAABLgAECgcJEgACAAAAAA==.',
Tr='Tricks:BAAALgAECgcJEAAAAA==.Trilleon:BAAALgAECgYJBwAAAA==.Trillis:BAAALgAECgIJAgABLgAECgYJBwACAAAAAA==.Tryjincks:BAAALgAECgYJDAAAAA==.Tryjinks:BAAALgAECgYJCgABLgAECgYJDAACAAAAAA==.',
Ts='Tserendolgor:BAAALgADCgEJAQAAAA==.',
Tu='Turgà:BAAALgAECgEJAQABLgAECgQJBQACAAAAAA==.',
Ty='Tykahndrius:BAAALgAECgEJAQAAAA==.Tys:BAAALgADCgQJBAAAAA==.',
['Tö']='Töph:BAAALgADCgEJAQABLgAECgQJBQACAAAAAA==.',
['Tú']='Túsk:BAAALgAECgYJBwAAAA==.',
['Tý']='Týlïus:BAABLgAECn8WAAIeAAYJqBvwEgCbAQAeAAYJqBvwEgCbAQAAAA==.',
Ud='Uddergrace:BAAALgADCgEJAQAAAA==.',
Un='Unspokenword:BAAALgADCgcJFwAAAA==.',
Ut='Uthilon:BAABLgAECn8nAAIeAAkJvR9LAQDTAgAeAAkJvR9LAQDTAgAAAA==.',
Va='Vaeredor:BAAALgADCgIJAgAAAA==.Valdare:BAABLgAECn8aAAInAAYJRxGMFwAmAQAnAAYJRxGMFwAmAQAAAA==.',
Ve='Vedillian:BAABLgAECn8dAAIgAAgJOgzhBAB/AQAgAAgJOgzhBAB/AQAAAA==.Velyndrenis:BAAALgADCgEJAgAAAA==.Vennaya:BAABLgAECn8bAAIiAAkJkwdyJQAeAQAiAAkJkwdyJQAeAQAAAA==.Vethinrel:BAAALgADCgYJBgAAAA==.',
Vi='Victorr:BAAALgAECgEJAQAAAA==.Viktorius:BAAALgADCgkJCQAAAA==.Violentpanda:BAAALgAECgUJCwABLgAECggJJQADACskAA==.Vite:BAAALgADCgcJGAAAAA==.Vixious:BAAALgADCgcJEgAAAA==.Vizigoth:BAABLgAECn8jAAMPAAgJzAxeOACEAQAPAAcJNwxeOACEAQAWAAIJCxHtVwBnAAAAAA==.',
Vo='Voladon:BAABLgAECn8aAAIHAAcJXBiUHADfAQAHAAcJXBiUHADfAQAAAA==.Voyana:BAABLgAECn8VAAIiAAUJjRddIABFAQAiAAUJjRddIABFAQABLgAECgUJFQALAOMdAA==.',
Vy='Vydragon:BAAALgAFFAIJAgABLgAFFAQJDwADAPQXAA==.Vymage:BAACLgAFFH8PAAIDAAQJ9BcwJgBcAQADAAQJ9BcwJgBcAQAuAAQKfycAAwMACQk4IUMSADoDAAMACQk4IUMSADoDACgABAn8EO0EAP0AAAAA.',
['Vá']='Válidüs:BAACLgAFFH8TAAIiAAUJwhLKBACCAQAiAAUJwhLKBACCAQAuAAQKfxwAAiIACQkJGMgLAJQCACIACQkJGMgLAJQCAAAA.',
['Vã']='Vãsh:BAAALgAECgYJDwAAAA==.',
Wa='Wanitou:BAAALgADCgMJAwAAAA==.Warninja:BAAALgAECgYJDgAAAA==.Waterlogged:BAAALgADCgMJAwAAAA==.Waterloo:BAAALgAECgEJAQAAAA==.',
We='Weejas:BAAALgADCgMJAwAAAA==.Werwick:BAAALgAECgIJBQAAAA==.',
Wh='Whatsnail:BAABLgAECn8cAAIDAAgJpAkCVwBoAQADAAgJpAkCVwBoAQAAAA==.',
Wi='Wizdom:BAAALgADCgQJBAAAAA==.',
Wr='Wrathidan:BAAALgAECgcJEAAAAA==.',
['Wì']='Wìccka:BAABLgAECn8UAAIHAAYJGxlpIgCzAQAHAAYJGxlpIgCzAQAAAA==.',
Xi='Xifan:BAAALgAECgEJAgAAAA==.',
Ya='Yalper:BAAALgADCgcJCwAAAA==.',
Yd='Yd:BAAALgAECgIJAgABLgAFFAIJAgACAAAAAA==.',
Yo='Youngwokongs:BAAALgADCgIJAgAAAA==.',
Yu='Yudie:BAABLgAECn8UAAIIAAYJoA6rNQAYAQAIAAYJoA6rNQAYAQAAAA==.',
Yz='Yz:BAAALgAFFAIJAgAAAA==.',
Za='Zalysi:BAABLgAECn8WAAMQAAgJHBLfJwDtAQAQAAgJHBLfJwDtAQAMAAIJkQdJHwFeAAAAAA==.Zam:BAABLgAECn8dAAMBAAcJ5B3VHwBSAgABAAcJsRrVHwBSAgAmAAMJwBgAJACkAAAAAA==.Zamantha:BAAALgADCgIJAgAAAA==.Zanny:BAAALgADCgMJAwAAAA==.Zashawa:BAAALgADCgUJBgAAAA==.Zashen:BAAALgAECgcJDQAAAA==.',
Ze='Zebb:BAAALgADCgcJDQAAAA==.Zelix:BAAALgADCgEJAQAAAA==.Zenmist:BAAALgAECgUJBwAAAA==.Zeylanica:BAAALgAECgEJAQABLgAFFAQJDQAXALgPAA==.',
Zh='Zhastr:BAAALgAECgYJEAAAAA==.',
Zl='Zllusion:BAAALgADCgMJAwAAAA==.Zlucu:BAAALgAECgQJBwABLgAFFAQJCwAPAPgTAA==.Zlufernal:BAACLgAFFH8LAAIPAAQJ+BPZKQAcAQAPAAQJ+BPZKQAcAQAuAAQKfyUAAg8ACAmyJVQNAA8DAA8ACAmyJVQNAA8DAAAA.',
Zy='Zyn:BAABLgAECn8eAAIBAAcJnQ4XIQBjAQABAAcJnQ4XIQBjAQAAAA==.',
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

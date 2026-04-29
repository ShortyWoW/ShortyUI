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

local lookup = {'Mage-Frost','Mage-Arcane','Hunter-BeastMastery','DemonHunter-Havoc','Unknown-Unknown','Druid-Balance','Druid-Feral','Hunter-Marksmanship','Rogue-Subtlety','Monk-Windwalker','DemonHunter-Devourer','Shaman-Enhancement','Paladin-Retribution','Monk-Mistweaver','Warlock-Destruction','Warlock-Demonology','Shaman-Restoration','Evoker-Preservation','Druid-Restoration','Evoker-Augmentation','Evoker-Devastation','DeathKnight-Unholy','Warlock-Affliction','DeathKnight-Blood','Warrior-Fury','Paladin-Holy','Priest-Shadow','Priest-Holy','Druid-Guardian','Warrior-Protection','Shaman-Elemental','Paladin-Protection','Monk-Brewmaster','Hunter-Survival','DeathKnight-Frost','Rogue-Assassination','Rogue-Outlaw','Mage-Fire',}
local provider = {region='US',realm='Drenden',name='US',type='weekly',zone=46,date='2026-04-24',data={Aa='Aaronius:BAAALgAECgQJCAAAAA==.',
Ab='Abundance:BAABLgAECn8YAAMBAAcJMBh7HABpAQABAAcJFBh7HABpAQACAAQJ2BeFCwAeAQAAAA==.',
Ad='Addictive:BAAALgADCggJCAAAAA==.Adoe:BAABLgAECn8YAAIDAAcJ4hybHABbAgADAAcJ4hybHABbAgAAAA==.Adora:BAAALgAECgUJCAAAAA==.Adër:BAAALgAECgQJBAAAAA==.',
Ae='Aeðn:BAAALgAECgEJAwAAAA==.',
Ag='Agaliarept:BAAALgAECgcJEAAAAA==.Agathena:BAAALgADCgEJAQAAAA==.Agathos:BAAALgAECgEJAQAAAA==.',
Ai='Aidan:BAAALgADCgEJAQAAAA==.Aidenator:BAABLgAECn8YAAIEAAcJuhJhIwCiAQAEAAcJuhJhIwCiAQAAAA==.',
Al='Alger:BAAALgAECgMJAwAAAA==.Aloria:BAAALgAECgEJAQAAAA==.Alrook:BAAALgAECgYJCwAAAA==.',
Am='Amoral:BAAALgAECgIJAgAAAA==.',
An='Angelneko:BAAALgAECgQJCAAAAA==.',
Ap='Apylonn:BAAALgADCgEJAQAAAA==.',
Ar='Arakhet:BAAALgADCgYJCQABLgADCgcJBwAFAAAAAA==.Arcaynemoon:BAABLgAECn8XAAIGAAYJWAMuVgDLAAAGAAYJWAMuVgDLAAAAAA==.',
As='Asterior:BAACLgAFFH8JAAIHAAQJdRpjAQBxAQAHAAQJdRpjAQBxAQAuAAQKfxkAAgcACAmuHIsEANICAAcACAmuHIsEANICAAAA.',
Au='Auley:BAAALgADCgQJBAAAAA==.Auroraa:BAAALgAECgYJEAAAAA==.Auyniko:BAAALgADCgQJAwABLgAECgIJAgAFAAAAAA==.',
Az='Azmodeaz:BAAALgAECgYJEgAAAA==.',
Ba='Bajapanti:BAABLgAECn8YAAIIAAYJAhReBQAwAQAIAAYJAhReBQAwAQAAAA==.Ballyhøø:BAAALgAECgYJDQAAAA==.Baxstab:BAABLgAECn8aAAIJAAYJ1xYUCABbAQAJAAYJ1xYUCABbAQAAAA==.',
Be='Beahon:BAAALgAECgQJCQAAAA==.',
Bg='Bgeefiddy:BAAALgADCgEJAQAAAA==.',
Bi='Bigmuff:BAAALgADCgEJAQAAAA==.Bigsocket:BAAALgAECgYJDAAAAA==.Binglepong:BAAALgAECgMJAwAAAA==.Bingobongo:BAAALgAECgQJBAAAAA==.Bio:BAAALgADCgMJAwAAAA==.',
Bl='Blackpatch:BAABLgAECn8WAAIKAAYJAhvHHAD1AQAKAAYJAhvHHAD1AQAAAA==.Blaqdraco:BAAALgAECgUJBQAAAA==.Blazingballs:BAAALgAECgMJAwAAAA==.Blink:BAEALgAECgQJBgAAAA==.Blitzaga:BAAALgAECgYJCAAAAA==.Bloomsbeam:BAABLgAECn8XAAILAAgJCBVdVQCjAQALAAgJCBVdVQCjAQAAAA==.',
Bo='Booneboy:BAAALgAECgQJBAAAAA==.Boptyboopity:BAAALgAECgQJBAAAAA==.Botemedel:BAAALgAECgYJDAABLgAECggJFgAMAOwYAA==.',
Br='Brennor:BAABLgAECn8bAAINAAcJDA3hGwBHAQANAAcJDA3hGwBHAQAAAA==.Brewslunt:BAACLgAFFH8JAAIOAAQJNxTJBwBAAQAOAAQJNxTJBwBAAQAuAAQKfxwAAg4ACAlaG5wNAHwCAA4ACAlaG5wNAHwCAAAA.Briarwyn:BAAALgADCgYJBgAAAA==.Brother:BAAALgAECgQJBAAAAA==.',
Bu='Buttcoin:BAAALgADCgcJCgAAAA==.',
Ca='Caeden:BAAALgAECgUJCQAAAA==.Cairyan:BAAALgAECgcJEAAAAA==.Capn:BAAALgADCgcJCAAAAA==.Carvil:BAABLgAECn8bAAMPAAcJ3g/BJwAlAQAPAAYJXBHBJwAlAQAQAAMJfwdYOACXAAAAAA==.Castalia:BAAALgAECgQJBAAAAA==.Cathel:BAAALgADCgEJAQAAAA==.',
Ce='Celenara:BAABLgAECn8eAAIBAAgJjiElHAAGAwABAAgJjiElHAAGAwAAAA==.Celithe:BAAALgAECgQJBgAAAA==.Cendriel:BAAALgAECgQJBwAAAA==.',
Ch='Charmcaster:BAABLgAECn8bAAIBAAcJnRx0DwDJAQABAAcJnRx0DwDJAQAAAA==.Chiafix:BAAALgAECgYJDQABLgAECgYJFwARAIEiAA==.Chipp:BAAALgAFFAEJAQAAAA==.Chleo:BAAALgAECgIJAwAAAA==.Choco:BAACLgAFFH8RAAISAAUJyhsYAQDMAQASAAUJyhsYAQDMAQAuAAQKfyMAAhIACAklIOQFAOkCABIACAklIOQFAOkCAAAA.Chocolat:BAAALgAECgYJDgABLgAFFAUJEQASAMobAA==.Chudster:BAAALgAECgcJEwAAAA==.',
Ci='Cindesh:BAAALgADCgMJAwAAAA==.',
Co='Coggler:BAAALgAECgQJBAAAAA==.Conqueror:BAAALgADCggJCAABLgAECggJGgATALsYAA==.',
Cr='Crawdaddy:BAAALgAECgQJBAAAAA==.Crawgirl:BAAALgADCgYJBQAAAA==.Crualti:BAAALgAECgQJBgAAAA==.',
Cu='Cupper:BAAALgADCgIJAwABLgAECgQJBAAFAAAAAA==.Curmudge:BAABLgAECn8eAAITAAgJ9Q4oEwAyAQATAAgJ9Q4oEwAyAQAAAA==.',
Cy='Cybele:BAAALgAECgQJBAAAAA==.',
Da='Dakunaito:BAAALgAECgYJEQAAAA==.Darachane:BAAALgAECgEJAQAAAA==.',
De='Deafgnome:BAAALgADCggJDAAAAA==.Deathstars:BAAALgADCgEJAQAAAA==.Deathßite:BAAALgADCgQJBAAAAA==.Deboss:BAAALgAECgQJBAAAAA==.Delianna:BAAALgADCgMJBQAAAA==.Delritha:BAAALgAECgQJDwAAAA==.Demonagent:BAAALgAECgQJBQAAAA==.Dermortimer:BAAALgAECgUJCgAAAA==.Desvoker:BAACLgAFFH8IAAMUAAMJfhmQEAD9AAAUAAMJfhmQEAD9AAAVAAEJ2BYPCQBYAAAuAAQKfyMAAxUACAnDG9MJAEICABUABwk/G9MJAEICABQACAlhFL4bAOoBAAAA.Devessa:BAAALgADCgEJAQAAAA==.Devious:BAAALgAECgYJDQAAAA==.',
Di='Dimebagg:BAAALgADCgMJBQAAAA==.Diorholocene:BAAALgAECgYJCwAAAA==.',
Do='Docspades:BAAALgAECgYJDwAAAA==.Dornoch:BAAALgAECgEJAQAAAA==.Dotzilla:BAAALgAECgEJAQAAAA==.',
Dr='Drakeigneel:BAAALgADCgYJCAAAAA==.Dramine:BAAALgAECgIJAwAAAA==.Dremire:BAAALgAECgYJEgAAAA==.Drhkillinger:BAAALgADCgkJEQABLgAECgQJBQAFAAAAAA==.Drspades:BAAALgADCgIJAgAAAA==.',
Dx='Dx:BAAALgAECgEJAgAAAA==.',
['Dé']='Démetal:BAABLgAECn8dAAIWAAgJrRpICQDqAQAWAAgJrRpICQDqAQAAAA==.Démi:BAAALgAECgYJDQAAAA==.',
El='Elessaria:BAAALgAECgQJBAAAAA==.Elfatheàrt:BAAALgAECgEJAQAAAA==.Elira:BAAALgAECgEJAQAAAA==.',
Em='Emofurry:BAAALgADCgIJAwAAAA==.',
Er='Eristira:BAAALgADCgcJDAABLgAECgUJCAAFAAAAAA==.',
Es='Esika:BAAALgAFFAEJAgAAAA==.Estherras:BAABLgAECn8YAAIDAAcJ+BZWKgAMAgADAAcJ+BZWKgAMAgAAAA==.',
Et='Ethari:BAAALgADCgUJBQAAAA==.',
Ey='Eyvira:BAAALgAECgUJBQAAAA==.',
Fe='Feardotrun:BAAALgAECgQJBQAAAA==.Felicious:BAAALgAECgEJAQAAAA==.',
Fi='Fiach:BAAALgADCgUJBQAAAA==.Finahlia:BAAALgAECgUJCgAAAA==.Finally:BAAALgAECgEJAQAAAA==.Firemage:BAABLgAECn8XAAIQAAYJriRcJgB5AgAQAAYJriRcJgB5AgAAAA==.Fizzanelf:BAAALgAECgEJAQAAAA==.',
Fo='Forn:BAAALgADCggJCwAAAA==.',
Fr='Freyá:BAABLgAECn8aAAINAAgJKhQHUQDuAQANAAgJKhQHUQDuAQAAAA==.Friendo:BAABLgAECn8YAAMHAAYJIhMYBQA7AQAHAAYJIhMYBQA7AQAGAAQJcwYGZQCNAAAAAA==.Frierenn:BAAALgADCgQJBAAAAA==.Frostyflakes:BAAALgAECgYJBgAAAA==.',
Fu='Furnost:BAAALgAECgYJDAAAAA==.Futnuraz:BAAALgAECgEJAQAAAA==.',
Fy='Fyriat:BAABLgAECn8YAAIBAAcJUgjrLAAXAQABAAcJUgjrLAAXAQAAAA==.',
Gi='Girthquakes:BAAALgAECgQJCQAAAA==.',
Gl='Glenji:BAABLgAECn8YAAIKAAYJkBHXOgAxAQAKAAYJkBHXOgAxAQAAAA==.Glenjin:BAAALgADCgEJAQAAAA==.',
Go='Goodgirl:BAAALgADCgEJAQAAAA==.Gorgmash:BAAALgAECgEJAQAAAA==.',
Gr='Grenswood:BAAALgAECgYJDAAAAA==.Griffindor:BAABLgAECn8YAAINAAYJaRmVHABDAQANAAYJaRmVHABDAQAAAA==.Grimfelborn:BAABLgAECn8kAAMQAAgJ/hm7MQBFAgAQAAgJ/hm7MQBFAgAXAAIJFAofGgCnAAAAAA==.Grimlinnan:BAAALgAECgMJAwAAAA==.Grondosh:BAAALgAECgQJBQAAAA==.',
Gu='Gummyscales:BAAALgADCgIJAgAAAA==.',
['Gì']='Gìorgìa:BAAALgADCgcJBwAAAA==.',
Ha='Hanicus:BAAALgADCgQJBwAAAA==.Hanoverfiste:BAAALgAECgQJBAAAAA==.Hapsburg:BAABLgAECn8ZAAIOAAcJTBLvBgCaAQAOAAcJTBLvBgCaAQAAAA==.Havince:BAABLgAECn8bAAIYAAcJeyAzAgD/AQAYAAcJeyAzAgD/AQAAAA==.',
Hi='Higgs:BAAALgAECgMJAwAAAA==.',
Ho='Holyball:BAABLgAECn8YAAINAAYJsR3rDgCwAQANAAYJsR3rDgCwAQAAAA==.',
Hu='Hughjahsol:BAAALgADCgYJCQAAAA==.Hustlîn:BAAALgADCgEJAQAAAA==.',
['Hê']='Hêra:BAAALgADCgEJAQAAAA==.',
Il='Illidai:BAAALgAECgQJBQAAAA==.Ilyndra:BAAALgAECgQJCAAAAA==.',
In='Infernella:BAAALgAECgMJAwAAAA==.',
Ir='Iristail:BAAALgAECgQJBQAAAA==.Ironskin:BAAALgADCgIJAgAAAA==.',
Is='Iselilja:BAABLgAECn8YAAIZAAcJ4BHzCwBhAQAZAAcJ4BHzCwBhAQAAAA==.',
It='Ithea:BAAALgAECgcJDQAAAA==.',
Ja='Jaeson:BAAALgAECgcJDQAAAA==.Jaiya:BAAALgADCggJCAAAAA==.Javoren:BAAALgAECgcJCwABLgAFFAUJDwAaAEITAA==.',
Je='Jeef:BAAALgADCgEJAQABLgAECgcJHQALABkhAA==.Jeffha:BAAALgAECgYJEQAAAA==.',
Ji='Jimothy:BAAALgAECgQJBwAAAA==.',
Jo='Joap:BAAALgAECgQJBwAAAA==.Joejr:BAAALgAECgYJEAAAAA==.Jonald:BAAALgADCgUJBQAAAA==.',
Jt='Jtizlfrizl:BAAALgAECgQJBAAAAA==.',
Jw='Jwise:BAAALgADCgcJCgAAAA==.',
Ka='Kajowsmage:BAAALgADCgcJBwAAAA==.Kalierix:BAAALgAECgQJBAAAAA==.Kaloesh:BAAALgAECgcJEwAAAA==.Kanabat:BAAALgAECgMJAwAAAA==.Karawyn:BAABLgAECn8WAAIDAAcJVQ5APQC5AQADAAcJVQ5APQC5AQABLgADCgUJBQAFAAAAAA==.Katrishy:BAABLgAECn8hAAMbAAgJGxx+FgAzAgAbAAgJGxx+FgAzAgAcAAEJcAUviAAnAAAAAA==.Kazeral:BAAALgADCgQJBwAAAA==.',
Ke='Keedrid:BAAALgAECgYJCgAAAA==.Keindis:BAAALgADCgYJBgAAAA==.Kelemenohpea:BAAALgAECgYJDwAAAA==.',
Kn='Knoll:BAAALgAECgQJBQAAAA==.',
Ko='Kode:BAAALgAECgQJCQAAAA==.',
Kr='Kreeona:BAABLgAECn8XAAIRAAYJgSKXBQAIAgARAAYJgSKXBQAIAgAAAA==.Kruàlty:BAAALgAECgQJCgAAAA==.',
Le='Legreecast:BAAALgAECgEJAQAAAA==.',
Li='Liasong:BAAALgADCgUJBQAAAA==.Litespeed:BAAALgADCgEJAQAAAA==.Litheliice:BAABLgAECn8bAAIcAAcJPQ3sCQBcAQAcAAcJPQ3sCQBcAQAAAA==.',
Lo='Lodur:BAABLgAECn8YAAIRAAcJFhvWIAAaAgARAAcJFhvWIAAaAgAAAA==.Lofurious:BAAALgADCgIJAgAAAA==.Lonen:BAEBLgAECn8XAAIdAAYJqxY/EABzAQAdAAYJqxY/EABzAQAAAA==.Losat:BAABLgAECn8YAAIeAAYJaQteCgDZAAAeAAYJaQteCgDZAAAAAA==.',
Lu='Lugrat:BAAALgADCgEJAQAAAA==.Luguna:BAAALgAECgYJCAAAAA==.Lunári:BAAALgAECgEJAQAAAA==.Luthian:BAAALgADCgMJAwAAAA==.',
Ly='Lycinder:BAAALgADCgEJAQAAAA==.',
['Lî']='Lîîght:BAAALgADCgEJAQAAAA==.',
Ma='Mackavelian:BAAALgAECgEJAQABLgAECgQJBAAFAAAAAA==.Mackkie:BAAALgAECgQJBAAAAA==.Madonkadonk:BAABLgAECn8bAAIVAAcJlg1yAgBpAQAVAAcJlg1yAgBpAQAAAA==.Maedai:BAABLgAECn8aAAIOAAcJFQz/CgA5AQAOAAcJFQz/CgA5AQAAAA==.Maeli:BAAALgADCgkJDQAAAA==.Magladroth:BAAALgAECgEJAQAAAA==.Magnaball:BAABLgAECn8gAAMaAAgJfhnzFwBSAgAaAAgJfhnzFwBSAgANAAEJOxDNSgEvAAAAAA==.Magús:BAAALgADCgEJAgAAAA==.Maldive:BAABLgAECn8XAAIQAAYJLxFMHgArAQAQAAYJLxFMHgArAQAAAA==.Maligasia:BAAALgADCgIJAgAAAA==.Mallicia:BAABLgAECn8dAAIcAAgJryOXAwAgAwAcAAgJryOXAwAgAwAAAA==.Mallika:BAAALgAECgcJCAABLgAECggJHQAcAK8jAA==.Mallwizard:BAABLgAECn8dAAIQAAgJJRaROAApAgAQAAgJJRaROAApAgAAAA==.Mangopewpew:BAAALgAECgQJBwAAAA==.Martris:BAAALgADCgQJBAAAAA==.Massoflice:BAABLgAECn8aAAIWAAgJcBTtagC2AQAWAAgJcBTtagC2AQAAAA==.Maxblaide:BAAALgADCggJCwAAAA==.Maxilla:BAAALgADCgcJBwABLgAECggJIAAaAH4ZAA==.',
Me='Meridians:BAAALgAECgYJEQAAAA==.',
Mh='Mhataharii:BAAALgADCgIJAgAAAA==.',
Mi='Mindhorn:BAABLgAECn8cAAMfAAgJmB+8BQC4AQAfAAcJyR+8BQC4AQARAAQJAhUBIwBsAAAAAA==.Misstangy:BAAALgAECgQJBQAAAA==.',
Mo='Moct:BAABLgAECn8YAAIgAAYJtxqmEAC8AQAgAAYJtxqmEAC8AQAAAA==.Moomooduck:BAAALgAECgEJAQAAAA==.',
Mu='Mudskipper:BAAALgAECgcJEAAAAA==.Muradox:BAAALgADCgQJBAABLgAECggJFAAUALINAA==.Mustardhunt:BAAALgADCgQJBAAAAA==.',
My='Myriad:BAABLgAECn8YAAIeAAcJrx4fDABJAgAeAAcJrx4fDABJAgAAAA==.',
Na='Nakze:BAABLgAECn8YAAIJAAcJRApRCgAvAQAJAAcJRApRCgAvAQAAAA==.Nastyfigs:BAAALgAECgYJDQAAAA==.Nazca:BAAALgADCgcJCgAAAA==.',
Ne='Necrochade:BAAALgAECgEJAQAAAA==.',
Nh='Nhilas:BAAALgAECgEJAQAAAA==.',
Ni='Nishal:BAAALgADCgkJEgAAAA==.',
Ny='Nyxaries:BAAALgAECgMJAwAAAA==.',
Ob='Oblivioso:BAAALgADCgYJBgAAAA==.',
Ol='Olåf:BAAALgADCgkJCQAAAA==.',
Pa='Pablo:BAAALgAECgQJBAAAAA==.Panzerblitz:BAAALgAECgYJDQAAAA==.Papers:BAAALgADCgEJAQAAAA==.Pargath:BAAALgAECgcJEgAAAA==.Pasìthea:BAAALgADCgcJBQAAAA==.',
Pe='Pengu:BAAALgAECgQJBgAAAA==.',
Pi='Pillow:BAAALgAECgcJEgAAAA==.Pillowdin:BAAALgAECgEJAQAAAA==.Pilson:BAAALgAECgYJDQAAAA==.Pinkytails:BAAALgADCgcJBwAAAA==.Piseyi:BAAALgADCgIJAgAAAA==.',
Po='Poonwagoon:BAAALgADCgYJCAAAAA==.',
Pr='Predacon:BAAALgAECgQJCAAAAA==.Pretzelz:BAAALgADCgYJCgAAAA==.',
Pu='Puffer:BAABLgAECn8YAAIBAAYJuRA6LQAWAQABAAYJuRA6LQAWAQAAAA==.',
Ra='Raito:BAAALgAECgYJDgAAAA==.Rakshasa:BAABLgAECn8ZAAMQAAgJ8iCvNAA5AgAQAAgJ8iCvNAA5AgAXAAEJAACuIQBrAAAAAA==.Rasetsungo:BAAALgAECgYJDAAAAA==.Raura:BAAALgAECgEJAQAAAA==.',
Re='Recalcitrent:BAAALgADCgYJCAAAAA==.Redblueblurr:BAAALgAECgMJAwAAAA==.Remi:BAAALgAECggJAgAAAA==.Reveillark:BAAALgAECgQJCQAAAA==.',
Ro='Rolan:BAABLgAECn8YAAIWAAgJvSN6BQAwAgAWAAgJvSN6BQAwAgAAAA==.Rosalian:BAABLgAECn8YAAITAAcJRhppCQDFAQATAAcJRhppCQDFAQAAAA==.Rotiko:BAAALgAECgYJEQAAAA==.Roweene:BAAALgAECgQJBwAAAA==.',
Sa='Saintseven:BAAALgAECgUJDAAAAA==.Salamander:BAAALgADCgYJBgAAAA==.Savior:BAAALgADCggJGQAAAA==.',
Se='Seiko:BAAALgADCgEJAQAAAA==.Selaphiel:BAAALgAECgEJAQAAAA==.Selvey:BAAALgADCgUJBwAAAA==.Sensei:BAABLgAECn8YAAMKAAcJQh5NBADAAQAKAAYJFSJNBADAAQAhAAEJJAsyhQA8AAAAAA==.Serenatee:BAABLgAECn8ZAAIbAAcJBAtCCwA8AQAbAAcJBAtCCwA8AQAAAA==.',
Sh='Shamill:BAAALgADCgMJAwAAAA==.Shammyball:BAAALgADCgcJBwAAAA==.Shamwow:BAAALgADCggJDgAAAA==.Shobe:BAAALgAECgQJBQAAAA==.Shouhuzhee:BAAALgAECggJEwAAAA==.Shåde:BAAALgADCgYJDQAAAA==.Shócker:BAAALgADCgMJAwAAAA==.',
Si='Simbà:BAAALgAECgQJBwAAAA==.',
Sl='Sleep:BAAALgADCgYJBgAAAA==.Sluicewrld:BAABLgAECn8dAAMLAAcJGSE6CgDPAQALAAcJGSE6CgDPAQAEAAEJ9hZUawA7AAAAAA==.',
Sn='Snorlacks:BAAALgAECgQJBAAAAA==.Snortedgfuel:BAAALgAECgYJDAAAAA==.',
So='Sokroar:BAAALgAECgQJBAABLgAECgkJAwAFAAAAAA==.Sonknight:BAAALgAECgQJCAAAAA==.',
Sp='Sparkticus:BAABLgAECn8UAAIfAAcJUxkkCAB+AQAfAAcJUxkkCAB+AQAAAA==.Spiky:BAAALgADCggJDQAAAA==.Spitefulcrow:BAAALgAECgYJEwAAAA==.Sporak:BAAALgADCgIJAgAAAA==.',
St='Stardstr:BAAALgAECgIJBAAAAA==.Sto:BAAALgAECgcJDAAAAA==.Stubz:BAAALgAECgYJBwAAAA==.',
Su='Supad:BAAALgADCgUJBQAAAA==.Superball:BAAALgAECgQJCgABLgAECggJIAAaAH4ZAA==.Suria:BAABLgAECn8YAAITAAYJVx9GBwDzAQATAAYJVx9GBwDzAQAAAA==.',
Sw='Swiskimohunr:BAAALgADCgMJAwAAAA==.Swàt:BAAALgADCgUJBQAAAA==.',
Sy='Syker:BAAALgAECgUJBQAAAA==.Syloc:BAAALgAECgEJAQAAAA==.',
Ta='Tahrovin:BAAALgADCggJEwAAAA==.Talaera:BAAALgAECgUJBQAAAA==.Tannastia:BAAALgAECgQJBwAAAA==.Tatem:BAAALgADCgYJDwAAAA==.Taurunter:BAAALgAECgMJAwAAAA==.Tavistreea:BAAALgAECgQJBwAAAA==.Taystee:BAAALgADCgYJBgAAAA==.Taytorchips:BAABLgAECn8aAAMaAAYJ2gNSFwDQAAAaAAYJ2gNSFwDQAAANAAUJ6QRw+ACiAAAAAA==.',
Th='Thelm:BAAALgADCgMJAwAAAA==.Thiccsmoke:BAAALgADCgIJAgAAAA==.Thoneous:BAAALgAECgYJBgAAAA==.Thornten:BAAALgAECgYJEAAAAA==.Thundercups:BAABLgAECn8bAAIMAAcJWxluAgDMAQAMAAcJWxluAgDMAQAAAA==.',
Ti='Tigerstarr:BAAALgAFFAEJAQAAAA==.Timboslicé:BAAALgAECgcJCwAAAA==.Tinyshieva:BAAALgAECgYJDwAAAA==.Tizuki:BAAALgAECgIJAgAAAA==.',
To='Tokey:BAAALgAECgUJCgAAAA==.',
Tr='Trashlock:BAAALgADCgYJBgAAAA==.Treasure:BAAALgAECgYJDgAAAA==.Treborlock:BAAALgAECgYJEgAAAA==.Treenn:BAAALgADCgEJAQAAAA==.Triplock:BAAALgADCgMJBQAAAA==.Trolcain:BAAALgAECgYJEgAAAA==.Trolmed:BAAALgAECgYJBgABLgAECgYJEgAFAAAAAA==.',
Ty='Tyrix:BAAALgAECgQJBAAAAA==.Tyránt:BAABLgAECn8bAAMDAAcJ1CADLgD6AQADAAcJ1CADLgD6AQAIAAEJAADKmwAQAAAAAA==.',
Ul='Ulfal:BAAALgAFFAEJAgAAAA==.',
Va='Vagglord:BAABLgAECn8WAAIBAAUJoyXcEwCjAQABAAUJoyXcEwCjAQAAAA==.Valadir:BAAALgAECgQJCAAAAA==.Valerossi:BAABLgAECn8XAAIiAAYJOR7pBACRAQAiAAYJOR7pBACRAQAAAA==.Valha:BAABLgAECn8WAAIEAAYJexEhBwA/AQAEAAYJexEhBwA/AQAAAA==.Vanorick:BAAALgAECgEJAgAAAA==.Vardisk:BAAALgADCgYJBgAAAA==.Varleyna:BAAALgAECgMJAwABLgAECggJHQAcAK8jAA==.Varteras:BAABLgAECn8bAAMQAAcJrhhsFQBlAQAQAAYJWRVsFQBlAQAXAAUJjBMxDgBPAQAAAA==.',
Ve='Veleiri:BAAALgAECgQJCAAAAA==.Velenal:BAAALgAECgEJAQAAAA==.Vellron:BAAALgAECgYJDgAAAA==.',
Vu='Vurkaal:BAAALgADCgYJBgAAAA==.',
['Và']='Vàsh:BAAALgAECgIJAgAAAA==.',
Wa='Wafflelegend:BAAALgAECgUJBwABLgAECgYJBwAFAAAAAA==.Wardkbriggle:BAAALgAFFAIJBAAAAA==.Warlover:BAAALgADCgYJCgAAAA==.Wartiger:BAACLgAFFH8QAAIhAAQJVhyPCABKAQAhAAQJVhyPCABKAQAuAAQKfxYAAiEACAmBICAVAGMCACEACAmBICAVAGMCAAAA.',
Wo='Wolfdude:BAABLgAECn8UAAMYAAYJXQWCNwCGAAAYAAQJGQaCNwCGAAAjAAUJ0gH7EgBiAAAAAA==.',
Wy='Wydge:BAAALgAECgUJDgAAAA==.Wymonath:BAAALgAECgMJAwAAAA==.',
Xa='Xanddoria:BAABLgAECn8YAAQkAAYJUSQTBAB1AgAkAAYJUSQTBAB1AgAlAAYJvR3fAADLAQAJAAQJex8+OgBFAQAAAA==.Xannydevito:BAAALgAECgQJDQAAAA==.',
Xe='Xellioth:BAAALgAECgUJCwAAAA==.Xenti:BAAALgADCgcJBwABLgAECgYJGAAkAFEkAA==.',
Xh='Xhared:BAAALgAECgYJEgAAAA==.',
Ya='Yahtzee:BAAALgADCgIJAgAAAA==.Yaosi:BAAALgAECgEJAQAAAA==.Yatorishino:BAAALgAECgYJDgAAAA==.',
Ze='Zephy:BAAALgADCgkJCQAAAA==.',
Zo='Zom:BAAALgADCgkJEQAAAA==.',
['Ël']='Ëlle:BAAALgADCgEJAQAAAA==.',
['Öz']='Öz:BAABLgAECn8oAAMmAAgJLSEuAABYAgAmAAgJLSEuAABYAgABAAQJsheF+QAHAQAAAA==.',
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

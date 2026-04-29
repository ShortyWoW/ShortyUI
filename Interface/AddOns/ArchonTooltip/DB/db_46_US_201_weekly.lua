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

local lookup = {'Paladin-Retribution','DeathKnight-Blood','Hunter-BeastMastery','Hunter-Marksmanship','Priest-Discipline','Paladin-Protection','Unknown-Unknown','Druid-Restoration','Monk-Mistweaver','Paladin-Holy','DemonHunter-Devourer','Warlock-Demonology','Mage-Frost','Mage-Arcane','DeathKnight-Unholy','Rogue-Subtlety','Rogue-Assassination','Shaman-Restoration','Shaman-Elemental','Evoker-Augmentation','Evoker-Devastation','Evoker-Preservation','Monk-Windwalker','Priest-Holy','Warlock-Destruction','Druid-Balance','Priest-Shadow',}
local provider = {region='US',realm='Spinebreaker',name='US',type='weekly',zone=46,date='2026-04-24',data={Aa='Aandidar:BAAALgAECgQJBAAAAA==.',
Ac='Aceroth:BAABLgAECn8UAAIBAAYJexlpYgC+AQABAAYJexlpYgC+AQAAAA==.',
Ad='Adarus:BAAALgAECgYJCAAAAA==.Addia:BAAALgAECgEJAgAAAA==.',
Ae='Aedran:BAAALgADCgIJAgAAAA==.Aelin:BAABLgAECn8fAAICAAgJwhOXFQC6AQACAAgJwhOXFQC6AQAAAA==.',
Ag='Agu:BAAALgADCgQJBAAAAA==.',
Al='Alaran:BAAALgADCgMJAwAAAA==.Alaysia:BAAALgADCgEJAQAAAA==.Alestair:BAABLgAECn8UAAMDAAcJBwojUQB1AQADAAcJBwojUQB1AQAEAAEJqQHNmQAaAAAAAA==.',
Am='Ampluslues:BAAALgADCgYJBgAAAA==.',
An='Andro:BAAALgAECgcJBwAAAA==.Angrä:BAAALgAECgUJBgAAAA==.',
Ao='Aowynn:BAAALgADCgEJAQAAAA==.',
Ar='Arakfalas:BAAALgAECgUJCQAAAA==.Artshell:BAABLgAECn8aAAIFAAgJjQh6LgArAQAFAAgJjQh6LgArAQAAAA==.',
As='Astalos:BAAALgAECgkJCgAAAA==.',
At='Atal:BAAALgADCgcJBwAAAA==.Atlask:BAAALgAECgEJAgAAAA==.Atsidi:BAAALgAECgYJDAAAAA==.',
Az='Azaelara:BAABLgAECn8UAAIGAAYJbQTfKwCuAAAGAAYJbQTfKwCuAAAAAA==.Azanie:BAAALgADCgkJEAAAAA==.Azuula:BAAALgAECgcJCwAAAA==.',
Ba='Badmidget:BAAALgADCgYJCQAAAA==.Bakasura:BAAALgADCgkJCQAAAA==.Bankhand:BAAALgAECgQJBAAAAA==.Bannon:BAAALgAECgMJAgAAAA==.Bartab:BAAALgAECgcJEgAAAA==.',
Be='Beauadin:BAAALgADCgQJCAAAAA==.Beaudacious:BAAALgAECgQJBwAAAA==.',
Bh='Bhoomi:BAAALgAECgEJAQAAAA==.',
Bi='Bignugs:BAAALgAECgEJAQAAAA==.Bisbird:BAAALgADCgEJAQAAAA==.',
Bl='Blacktips:BAAALgAECgIJAgABLgAECgYJBwAHAAAAAA==.Blenny:BAABLgAECn8UAAIIAAYJJgSxhADOAAAIAAYJJgSxhADOAAAAAA==.Blindpickle:BAAALgAECgQJBgAAAA==.Blitzkriegen:BAAALgADCgEJAQAAAA==.Blitzkrîeg:BAAALgAECgQJBAAAAA==.',
Bo='Boyscourge:BAAALgAECgEJAQAAAA==.',
Br='Breezylock:BAAALgAECgYJCQAAAA==.Brewgar:BAABLgAECn8aAAIJAAgJmw9VJwB7AQAJAAgJmw9VJwB7AQAAAA==.Brightblade:BAABLgAECn8VAAMKAAgJtBB4MAC/AQAKAAgJtBB4MAC/AQABAAUJ/CJShgBuAQABLgAFFAQJBQALABYLAA==.Brucetea:BAAALgAECgYJCgAAAA==.Brux:BAABLgAECn8YAAIMAAgJHRN5RwD0AQAMAAgJHRN5RwD0AQAAAA==.',
Bu='Bubonic:BAAALgAECgYJBgAAAA==.Burntt:BAAALgAECgEJAQAAAA==.Buttjeans:BAAALgAECggJEQAAAA==.',
Ca='Calduryn:BAAALgADCgYJBgAAAA==.Calibër:BAAALgAECgMJAwAAAA==.Captchair:BAAALgADCgIJAgAAAA==.Cashis:BAAALgADCgUJBQAAAA==.',
Ce='Celibate:BAAALgADCgYJBQAAAA==.',
Ch='Chainhealman:BAAALgADCgEJAQAAAA==.Chickynuggy:BAAALgAECgcJEgAAAA==.Chillypickle:BAAALgAECgcJEwAAAA==.Chonkdoggie:BAAALgADCgYJDAAAAA==.Chronicbuds:BAAALgAECgQJBAAAAA==.',
Cl='Cloudcaller:BAAALgAECgQJCQAAAA==.',
Co='Cobrakai:BAAALgAECgYJEwAAAA==.Cochuata:BAAALgADCgcJBwAAAA==.Cowculated:BAAALgAECgMJAwAAAA==.',
Cr='Crabbypatty:BAAALgAECgQJDwAAAA==.Cripstaet:BAAALgADCgkJEAAAAA==.Crisp:BAABLgAECn8WAAMNAAYJ1xh6jwC0AQANAAYJ1xh6jwC0AQAOAAEJZgvpHwAwAAAAAA==.Crow:BAAALgADCgcJEQAAAA==.',
Cu='Curse:BAAALgAECgUJCgABLgAFFAQJCgAPAAcbAA==.',
Da='Daace:BAAALgAECgYJBgAAAA==.Daboomdh:BAAALgAECgcJAwAAAA==.Daboommg:BAAALgAECgcJBwAAAA==.Dace:BAACLgAFFH8FAAIQAAMJhgqIBgD8AAAQAAMJhgqIBgD8AAAuAAQKfyUAAxAACAn2HRICACcCABAACAn2HRICACcCABEABAnaDM4TAMMAAAAA.Daelandor:BAAALgADCgYJBgAAAA==.Daelthyr:BAAALgAECgQJBQAAAA==.Dairydefendr:BAAALgAECgMJBQAAAA==.Damyn:BAAALgAECgYJEgAAAA==.Dart:BAAALgAECgcJDQAAAA==.Daspanktank:BAAALgAECgYJDwAAAA==.',
De='Deathsgrace:BAABLgAECn8UAAINAAYJlB72aQACAgANAAYJlB72aQACAgAAAA==.Demark:BAAALgAECgUJDQAAAA==.Demoniccake:BAAALgADCgMJAwAAAA==.Demonicneon:BAAALgAECgMJAwAAAA==.Dergara:BAAALgADCgYJCgAAAA==.Devman:BAABLgAECn8VAAIBAAcJaxSVdACSAQABAAcJaxSVdACSAQAAAA==.Dezzolation:BAAALgADCggJCQAAAA==.',
Di='Diekath:BAAALgADCgYJDgAAAA==.Dingus:BAAALgAECgQJBAAAAA==.Dixinmayaz:BAAALgADCgMJBAAAAA==.',
Dk='Dk:BAABLgAFFH8KAAIPAAQJBxvvBABoAQAPAAQJBxvvBABoAQAAAA==.',
Do='Dodgeroach:BAAALgAECgMJAwAAAA==.Doody:BAABLgAECn8dAAIIAAkJXwwmRwCFAQAIAAkJXwwmRwCFAQAAAA==.Dotyew:BAAALgAECgEJAQAAAA==.',
Dr='Dratalis:BAAALgAECgEJAQAAAA==.Dreastotems:BAAALgAECgIJAgAAAA==.Drennifer:BAAALgAECgYJCgAAAA==.Drgndeeznuts:BAAALgAECgEJAgABLgAECgcJFQABAGsUAA==.',
Du='Duskcandin:BAAALgADCgIJAgAAAA==.',
Eb='Ebtyrone:BAAALgAECggJEQAAAA==.',
El='Ellyham:BAAALgADCgMJBQAAAA==.',
Em='Emrys:BAAALgADCgcJDQAAAA==.',
Ez='Ezath:BAAALgAECgYJBgAAAA==.',
Fa='Falcorn:BAAALgADCgQJBAAAAA==.',
Fe='Felwolf:BAAALgAECgMJBAAAAA==.',
Fi='Fibderp:BAAALgADCgcJDgAAAA==.',
Fo='Foxx:BAAALgAECgEJAQAAAA==.',
Fr='Freshdots:BAAALgAECgEJAQABLgAECgIJAgAHAAAAAA==.Froolock:BAAALgADCgYJBgAAAA==.Fruvi:BAAALgADCgQJBAAAAA==.',
Fu='Fullometal:BAAALgAECgYJEwAAAA==.Furojin:BAAALgAECggJEgAAAA==.',
Ga='Galstad:BAABLgAECn8cAAMEAAYJkCUjAQAXAgAEAAYJkCUjAQAXAgADAAIJXhdp1AAxAAAAAA==.',
Ge='Geff:BAAALgAECgIJBAAAAA==.',
Gi='Gigariven:BAAALgAECgYJEgAAAA==.Girthhquake:BAAALgAECgYJDgAAAA==.Girumm:BAAALgAECgcJBwAAAA==.Gisokaashi:BAAALgAECgQJCAAAAA==.',
Go='Gooserage:BAAALgADCgQJBAAAAA==.Gothick:BAAALgAECgIJAgAAAA==.',
Gr='Grumz:BAABLgAECn8WAAMSAAcJHxTgPwCBAQASAAcJHxTgPwCBAQATAAQJUwy/awCUAAAAAA==.',
Gu='Guacamolle:BAAALgADCgIJAgAAAA==.Gurrand:BAAALgAECgYJBgABLgAFFAQJBwANADoSAA==.',
Ha='Habib:BAAALgAECgIJAgAAAA==.Happyflappy:BAEBLgAECn8gAAMUAAgJwhu2AgAVAgAUAAgJ6xq2AgAVAgAVAAMJSxpwKADcAAAAAA==.Happyshocks:BAEALgAECgEJAQABLgAECggJIAAUAMIbAA==.Harambe:BAAALgADCgUJBQABLgAECgkJHQAIAF8MAA==.',
He='Healforfun:BAABLgAECn8fAAIIAAkJwRPzDACEAQAIAAkJwRPzDACEAQAAAA==.Heilung:BAABLgAECn8mAAIWAAkJdwcbBQBhAQAWAAkJdwcbBQBhAQAAAA==.Hellstar:BAAALgADCgcJBwAAAA==.',
Hi='Hirradee:BAACLgAFFH8FAAILAAMJWxMFCwALAQALAAMJWxMFCwALAQAuAAQKfyUAAgsACAn7G1ssAE0CAAsACAn7G1ssAE0CAAAA.',
Ho='Holyroach:BAAALgAECgQJBQAAAA==.',
Hu='Hugebubbles:BAAALgADCgcJCQAAAA==.',
Ic='Icecweam:BAAALgADCgkJEAAAAA==.Ichigo:BAAALgAECgQJBAAAAA==.',
Il='Illuminus:BAAALgAECgQJCAAAAA==.Ilovenikki:BAAALgADCgcJDQAAAA==.',
Im='Image:BAAALgADCgcJBwAAAA==.Impending:BAAALgADCgQJBAAAAA==.',
In='Inktown:BAAALgAECgIJAgAAAA==.',
Ir='Iruden:BAABLgAECn8WAAIPAAcJWBYCcgCjAQAPAAcJWBYCcgCjAQAAAA==.',
Ji='Jipper:BAAALgADCgMJAwAAAA==.',
Jr='Jrwriter:BAAALgAECgYJEAABLgAFFAQJCgAPAAcbAA==.',
Jy='Jym:BAEALgAECggJEAAAAA==.',
Ka='Kaijin:BAABLgAECn8fAAIXAAgJSRiyEgBeAgAXAAgJSRiyEgBeAgAAAA==.Kalypsö:BAAALgADCgEJAQAAAA==.Kandrianna:BAAALgAECgQJBAAAAA==.Kateriny:BAAALgADCgEJAQAAAA==.',
Ke='Kelaya:BAAALgAECgIJAwAAAA==.Kenpachi:BAAALgADCgcJCQAAAA==.Kernuckle:BAAALgAECgQJBwAAAA==.',
Kh='Khristine:BAAALgADCgEJAQAAAA==.',
Ki='Kilrav:BAAALgAECgEJAQAAAA==.Kimberlee:BAAALgAECgkJEgAAAA==.Kiryanna:BAAALgAECgYJCwAAAA==.',
Kl='Klayana:BAAALgAECgYJDAAAAA==.',
Kr='Krombopulös:BAAALgAECgYJBgAAAA==.',
La='Lawloo:BAACLgAFFH8JAAIYAAQJtxXeAwBPAQAYAAQJtxXeAwBPAQAuAAQKfx0AAhgACAn0ITcIAMgCABgACAn0ITcIAMgCAAAA.Lawltwo:BAAALgAECgMJAwAAAA==.',
Le='Legothas:BAABLgAECn8aAAIEAAcJDxyAAgCqAQAEAAcJDxyAAgCqAQAAAA==.',
Li='Lifestyle:BAAALgAECgEJAQAAAA==.Lintlickerr:BAAALgAECgcJCAAAAA==.Littledirk:BAABLgAECn8VAAIQAAgJ8AbAMACBAQAQAAgJ8AbAMACBAQAAAA==.',
Ll='Llillies:BAAALgAECgMJAwAAAA==.',
Lo='Longstalker:BAAALgADCgcJCQAAAA==.',
Lu='Luxiss:BAAALgADCgIJAgAAAA==.',
Ma='Maak:BAAALgAFFAEJAQAAAA==.Madcuzbad:BAAALgAECgMJAwAAAA==.Magebuff:BAAALgAECgUJBwAAAA==.Malzgatoth:BAAALgADCgEJAQAAAA==.Maplesyrup:BAAALgADCgQJBwAAAA==.',
Mc='Mcheals:BAAALgAECggJEQAAAA==.',
Me='Meanìe:BAAALgADCgEJAQAAAA==.Medellia:BAAALgAECgkJAgAAAA==.Media:BAAALgADCgkJGQAAAA==.Mezcal:BAAALgAECgEJAQAAAA==.',
Mi='Miasma:BAAALgADCgEJAQABLgAECgUJCAAHAAAAAA==.Midgetitis:BAAALgADCgUJBgAAAA==.',
Mo='Monsunami:BAAALgAECggJDgAAAA==.Moonmonk:BAAALgADCgMJAwAAAA==.Moonwings:BAAALgADCgMJAwAAAA==.Morkra:BAAALgAECgYJDQAAAA==.Morte:BAAALgAECgYJBwAAAA==.Moònflower:BAAALgAECgYJDwAAAA==.',
Mu='Mundungus:BAAALgADCgYJBgAAAA==.Mushroom:BAAALgAECgUJBQAAAA==.',
['Më']='Mëlfina:BAAALgADCgEJAQAAAA==.',
['Mø']='Møøn:BAAALgAECgEJAQAAAA==.Møøse:BAABLgAECn8fAAISAAgJeBU8CQCvAQASAAgJeBU8CQCvAQAAAA==.',
Na='Narcyon:BAABLgAECn8aAAIYAAYJ9xm6BwCMAQAYAAYJ9xm6BwCMAQAAAA==.',
No='Noahdh:BAACLgAFFH8SAAILAAUJYCNhAQCwAQALAAUJYCNhAQCwAQAuAAQKfyIAAgsACAk/IjAOAA0DAAsACAk/IjAOAA0DAAAA.Nokkoh:BAAALgADCgcJCQAAAA==.Notmaxxie:BAAALgAECgIJAgAAAA==.',
['Nì']='Nìck:BAAALgAECgIJAgAAAA==.',
Ob='Obz:BAAALgAECgEJAQAAAA==.',
Oe='Oexx:BAAALgAECgYJEAAAAA==.',
Oz='Ozmodius:BAAALgADCgMJAwAAAA==.',
Pa='Padhi:BAAALgAECgYJEgAAAA==.Palaadin:BAAALgAECgYJCgAAAA==.Pandicated:BAEALgAECgYJDQABLgAECggJEwAHAAAAAA==.',
Pe='Pennlad:BAAALgAECgEJAQAAAA==.Peppermint:BAACLgAFFH8FAAIIAAIJUhuwFgCrAAAIAAIJUhuwFgCrAAAuAAQKfyAAAggACAlMIvoMANUCAAgACAlMIvoMANUCAAAA.',
Ph='Pheelix:BAAALgADCgEJAQAAAA==.Phlufy:BAABLgAECn8XAAIIAAcJKxfDMQDjAQAIAAcJKxfDMQDjAQAAAA==.',
Pi='Piemur:BAAALgADCgcJBwAAAA==.',
Po='Pollix:BAAALgAECgYJDQAAAA==.Ponsi:BAAALgAECgYJEQAAAA==.',
Pr='Prettypatty:BAAALgADCgcJEwAAAA==.Preying:BAAALgADCgEJAQABLgAECgMJAwAHAAAAAA==.Prídè:BAAALgAECgYJCgAAAA==.',
Qu='Quj:BAAALgADCgkJEAAAAA==.',
Ra='Raejiisa:BAAALgADCgcJBwAAAA==.Rakoth:BAAALgAECgMJCQAAAA==.Rantharot:BAAALgADCgEJAQAAAA==.Rathmá:BAAALgAECgcJAQAAAA==.Ravenwolf:BAAALgAECgQJCAAAAA==.Raveñna:BAAALgAECgUJBQAAAA==.Rawrina:BAAALgAECggJEQAAAA==.',
Re='Redlitesaber:BAAALgAECgEJAQAAAA==.Rejoice:BAAALgADCgIJAgAAAA==.',
Ri='Riptide:BAABLgAECn8ZAAINAAgJGRW/EAC8AQANAAgJGRW/EAC8AQABLgAECgMJAwAHAAAAAA==.Risto:BAABLgAECn8UAAIMAAYJryNBKgBnAgAMAAYJryNBKgBnAgAAAA==.',
Ro='Rodandwen:BAAALgADCgMJAwAAAA==.Ronzertnin:BAABLgAECn8UAAIZAAYJAxJFGgB7AQAZAAYJAxJFGgB7AQAAAA==.Roody:BAAALgADCgkJCwABLgAECgkJHQAIAF8MAA==.',
Ry='Ryöshun:BAAALgADCgIJAgAAAA==.',
Sa='Sabreus:BAAALgADCgEJAQAAAA==.Sagong:BAAALgADCgEJAQAAAA==.Samel:BAAALgAECgEJAQAAAA==.Samelly:BAAALgADCgYJBgAAAA==.Samellyfox:BAAALgADCgYJBgAAAA==.Sanctify:BAAALgADCgYJBgAAAA==.Sandrea:BAAALgADCgkJDwAAAA==.Sandroin:BAAALgAECgYJDQAAAA==.',
Sc='Scarf:BAAALgAECgEJAQAAAA==.Schnee:BAAALgADCgEJAQAAAA==.Schrimp:BAAALgADCgMJBAABLgAECgYJBwAHAAAAAA==.',
Se='Serrasin:BAAALgADCgIJAgAAAA==.',
Sh='Shinerbock:BAAALgAECgYJDwAAAA==.Shock:BAAALgAECgYJCwAAAA==.',
Si='Sighty:BAAALgADCgcJDQAAAA==.Sixxam:BAAALgADCgEJAQAAAA==.',
Sk='Skipuscales:BAAALgAECgcJCAAAAA==.',
Sn='Snowgo:BAAALgAECgEJAQABLgAECgIJAgAHAAAAAA==.',
So='Soul:BAABLgAECn8fAAIaAAgJYx2KBADVAQAaAAgJYx2KBADVAQAAAA==.Sovietpanda:BAAALgAECgUJCQAAAA==.',
Sp='Spanky:BAAALgAECggJDwAAAA==.Spawnite:BAAALgAECgEJAgAAAA==.Spiritgun:BAAALgAECgIJAgABLgAFFAQJCgAPAAcbAA==.Spumungus:BAAALgADCgMJAwAAAA==.',
St='Staahcked:BAAALgAECgQJBAAAAA==.',
Su='Summon:BAABLgAECn8dAAIMAAgJmRn5MgBAAgAMAAgJmRn5MgBAAgAAAA==.Sumtingwong:BAAALgAECgEJAQAAAA==.Sutures:BAAALgADCgEJAgAAAA==.',
Sw='Swig:BAAALgADCgIJAgAAAA==.',
['Sö']='Sönja:BAABLgAECn8bAAIGAAgJlQz2HAAjAQAGAAgJlQz2HAAjAQAAAA==.',
Ta='Taek:BAAALgAFFAQJBAAAAA==.Taterbiscuts:BAAALgADCgMJAwAAAA==.Tazmo:BAAALgAECgQJBQAAAA==.',
Te='Tehblink:BAAALgAECgQJBAAAAA==.Terah:BAAALgADCgEJAgAAAA==.Terofyin:BAAALgAECgEJAQAAAA==.Terralithia:BAAALgADCgEJAQAAAA==.',
Th='Thamúz:BAAALgAECgMJBgAAAA==.Thathnda:BAAALgADCgEJAQAAAA==.Thorgan:BAAALgAECgEJAQAAAA==.',
To='Toomez:BAAALgADCgEJAQAAAA==.Tormxnted:BAAALgADCgcJDAAAAA==.',
Tr='Tranquiill:BAAALgAECgQJBgAAAA==.Trea:BAAALgADCgQJBAAAAA==.Tripsalot:BAAALgADCgcJDQAAAA==.Tro:BAAALgADCgEJAQAAAA==.',
Tu='Tupkiss:BAABLgAECn8cAAIbAAYJOSEwBQDAAQAbAAYJOSEwBQDAAQAAAA==.',
Tw='Twilight:BAAALgADCgUJBQAAAA==.',
Ty='Tygrand:BAAALgADCgUJBQAAAA==.Tylernol:BAAALgAECgcJDQAAAA==.',
Un='Unknwndemon:BAAALgAECggJCQAAAA==.',
Wa='Wafflepop:BAABLgAECn8fAAMVAAgJAxx8AABLAgAVAAgJAxx8AABLAgAUAAYJ+hIEMABFAQAAAA==.Warpfiend:BAAALgAECgUJEgAAAA==.',
Wh='Whammy:BAAALgAECgQJDQAAAA==.Wheresmypet:BAAALgADCgYJBgAAAA==.',
Wo='Woodymcwood:BAAALgAECgQJBAAAAA==.',
Wu='Wurmz:BAAALgADCgMJAwAAAA==.',
Xe='Xenovia:BAAALgADCgkJEAAAAA==.',
Za='Zandragon:BAAALgADCgYJBwAAAA==.',
Ze='Zeldris:BAAALgADCgYJBgAAAA==.Zenbo:BAAALgAECgEJAQAAAA==.Zensu:BAAALgAECgMJAwAAAA==.',
Zo='Zoêy:BAAALgAECgQJBgAAAA==.',
Zz='Zzturtlezz:BAAALgAECgYJEAAAAA==.',
['Än']='Änorack:BAAALgADCgMJAgAAAA==.',
['Ço']='Çountèr:BAACLgAFFH8MAAILAAQJ1hO5EABJAQALAAQJ1hO5EABJAQAuAAQKfyMAAgsACAmJHewkAHUCAAsACAmJHewkAHUCAAAA.',
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

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

local lookup = {'Shaman-Restoration','Monk-Brewmaster','DeathKnight-Frost','DeathKnight-Blood','Paladin-Retribution','Unknown-Unknown','Mage-Frost','Warrior-Protection','Mage-Fire','Druid-Balance','Druid-Restoration','Paladin-Protection','Monk-Mistweaver','Evoker-Devastation','Evoker-Augmentation','Priest-Discipline','Paladin-Holy','DeathKnight-Unholy','Druid-Feral','Priest-Shadow','Priest-Holy','Hunter-BeastMastery','Rogue-Assassination','Warlock-Demonology','Rogue-Outlaw','Shaman-Elemental','DemonHunter-Havoc','Shaman-Enhancement','Hunter-Marksmanship','Warlock-Destruction','Warlock-Affliction','DemonHunter-Devourer','DemonHunter-Vengeance','Mage-Arcane','Monk-Windwalker','Druid-Guardian','Warrior-Arms','Warrior-Fury',}
local provider = {region='US',realm='Draenor',name='US',type='weekly',zone=46,date='2026-04-24',data={Ac='Achiella:BAAALgADCgIJAgAAAA==.',
Ad='Advisor:BAABLgAECn8ZAAIBAAcJHyVtCQDhAgABAAcJHyVtCQDhAgAAAA==.',
Ae='Aería:BAAALgAECgQJBgAAAA==.',
Ah='Ahnkho:BAAALgADCgcJDwAAAA==.',
Ai='Ailea:BAAALgADCgcJFQAAAA==.',
Ak='Akarm:BAAALgADCgcJBwAAAA==.',
Al='Alcomancer:BAAALgADCgIJAgAAAA==.Aleks:BAAALgAECgQJBAAAAA==.Aluna:BAAALgAECgcJCQAAAA==.Alvarr:BAAALgADCgUJAwAAAA==.',
Am='Amalia:BAAALgADCgEJAQAAAA==.Amandakk:BAAALgADCggJEwAAAA==.Aminas:BAAALgAECgEJAQAAAA==.',
An='Annya:BAAALgAECgYJBgAAAA==.Antheria:BAAALgADCgMJAwAAAA==.',
Ap='Aphrodite:BAAALgAECgYJEAAAAA==.',
Ar='Archie:BAAALgAECgQJBgAAAA==.Arendt:BAAALgADCgQJBwAAAA==.Arkahera:BAAALgAECgMJAwABLgAFFAMJBwACAM8iAA==.Arolder:BAABLgAECn8SAAMDAAgJHBzaAwA7AgADAAcJIR3aAwA7AgAEAAEJARZvQgBBAAAAAA==.Arturium:BAAALgADCgYJCQAAAA==.',
At='Atabey:BAABLgAECn8hAAIFAAgJdB1sCAADAgAFAAgJdB1sCAADAgABLgABCgMJAwAGAAAAAA==.Atimusk:BAAALgADCggJDwAAAA==.Atoadaso:BAAALgADCgMJAwAAAA==.Attretes:BAAALgADCgUJBQAAAA==.',
Az='Azcowboy:BAAALgAECgIJBAAAAA==.Aznå:BAAALgADCgQJBAAAAA==.',
Ba='Balacheck:BAAALgAECgUJBwAAAA==.Bang:BAAALgADCgEJAQAAAA==.Barecub:BAAALgADCgQJCgAAAA==.Barton:BAAALgADCgcJCQAAAA==.Baultenaz:BAAALgADCgQJBAAAAA==.',
Bb='Bbite:BAAALgAECgcJEgAAAA==.',
Be='Beanwater:BAAALgAECgMJAwAAAA==.Belmax:BAAALgADCgQJCgAAAA==.Bemon:BAAALgADCgcJBwABLgAECgcJFAAHAKAcAA==.',
Bi='Bigbadwoof:BAAALgADCgYJGQAAAA==.Bighog:BAABLgAFFH8FAAIIAAMJqBvFAgARAQAIAAMJqBvFAgARAQAAAA==.',
Bl='Blaazzin:BAAALgADCgYJBwAAAA==.Blessa:BAAALgADCgkJCQAAAA==.Bloomzy:BAABLgAECn8YAAMHAAgJCBXjFQCUAQAHAAgJMRDjFQCUAQAJAAIJehtYCgCfAAAAAA==.Blytzbrigade:BAAALgADCgkJDQAAAA==.',
Bo='Boneycheese:BAAALgADCgYJCgAAAA==.Boombástic:BAABLgAECn8VAAMKAAcJ4A9VEADwAAAKAAUJ+hNVEADwAAALAAIJjA9SKgBlAAAAAA==.Boomco:BAAALgADCgkJGwAAAA==.Bors:BAAALgADCgQJBwAAAA==.Boulderholdr:BAAALgADCgcJDQAAAA==.Boxing:BAAALgADCgIJAgAAAA==.',
Br='Breaddy:BAAALgAECgYJCwAAAA==.Breeti:BAAALgAECgUJBwAAAA==.Bronte:BAABLgAECn8ZAAIMAAgJhhqcCgAkAgAMAAgJhhqcCgAkAgAAAA==.Bryda:BAAALgADCgcJEAAAAA==.',
Bu='Bubblez:BAAALgADCgYJCQAAAA==.Burblingbee:BAAALgADCgcJBwAAAA==.',
Bw='Bwucewee:BAAALgADCgcJBwAAAA==.',
Ca='Cajbo:BAAALgAECgYJEwAAAA==.Calyssa:BAABLgAECn8WAAIFAAYJFQ2cKAABAQAFAAYJFQ2cKAABAQAAAA==.Candyflöss:BAAALgAECgYJBgAAAA==.Carpe:BAAALgAECgYJBgAAAA==.Cartan:BAABLgAECn8VAAINAAcJRBppGAD8AQANAAcJRBppGAD8AQAAAA==.Cathelina:BAAALgADCgcJCQAAAA==.Cathom:BAAALgAECgQJBwAAAA==.',
Ch='Charizaard:BAAALgADCggJDAAAAA==.Charizaardx:BAABLgAECn8oAAMOAAgJpRZGAQDIAQAOAAgJdhJGAQDIAQAPAAYJvhbuJQCNAQAAAA==.Chevytron:BAAALgAECgUJCwAAAA==.Chune:BAAALgADCgcJDAAAAA==.',
Ci='Cinder:BAAALgADCgIJAgAAAA==.',
Cl='Cletus:BAAALgAECgYJEgAAAA==.Clément:BAAALgADCgUJBQAAAA==.',
Co='Coffeebeans:BAABLgAECn8WAAMLAAcJfxThPgCnAQALAAcJfxThPgCnAQAKAAQJDwI/bgBmAAAAAA==.Cowabunga:BAAALgADCgIJAgAAAA==.',
Cr='Crazyasian:BAAALgAECgUJCQAAAA==.Crogan:BAAALgAECgEJAQAAAA==.',
Ct='Ctrlaltdk:BAAALgAECgEJAQAAAA==.',
Cy='Cybrocookie:BAAALgADCgEJAQAAAA==.Cyrberus:BAAALgAECgUJBwAAAA==.',
['Cá']='Cáposhady:BAAALgAECgEJAQAAAA==.',
Da='Dagda:BAAALgADCgMJAwAAAA==.Dalna:BAAALgAECgYJEAAAAA==.Danilex:BAABLgAECn8XAAIHAAcJHh9uSABeAgAHAAcJHh9uSABeAgABLgAFFAYJEwAQAOoOAA==.Danksoul:BAAALgADCgUJBQABLgAECggJFwARAMAYAA==.Darcorin:BAABLgAECn8XAAISAAYJTBafFwBVAQASAAYJTBafFwBVAQAAAA==.Darkblitz:BAAALgADCgQJBQAAAA==.Darklürker:BAAALgAECgQJBQAAAA==.Darksaber:BAAALgADCgcJDQAAAA==.Dasthodan:BAAALgADCgcJDQAAAA==.Dayne:BAAALgAECgUJBgAAAA==.',
Dc='Dctrpepper:BAAALgADCggJHwAAAA==.',
De='Deathcore:BAAALgADCgUJBQAAAA==.Deathminions:BAAALgADCgUJBQAAAA==.Deathwish:BAAALgADCgIJAgAAAA==.Decklan:BAAALgADCgEJAQAAAA==.Decorum:BAAALgADCgEJAQAAAA==.Defiant:BAAALgADCgEJAQAAAA==.Deilliann:BAABLgAECn8XAAQLAAYJmgZ3HwC6AAALAAYJmgZ3HwC6AAAKAAYJkgFPZQCMAAATAAIJhQB9OgAdAAAAAA==.Deldawalth:BAAALgADCgcJEgAAAA==.Demonica:BAAALgAECgUJCAAAAA==.Demonky:BAAALgAECgEJAQAAAA==.Demonology:BAAALgADCgYJBwAAAA==.Denastus:BAAALgADCgEJAQAAAA==.Devick:BAAALgADCgkJCQAAAA==.',
Di='Dinta:BAABLgAECn8kAAIFAAgJ0hpfDgC2AQAFAAgJ0hpfDgC2AQAAAA==.Dip:BAAALgADCgcJBwAAAA==.',
Dj='Djabuty:BAAALgAECgEJAgAAAA==.',
Do='Dominoes:BAAALgADCgkJHAAAAA==.Domìnion:BAAALgADCgkJEAAAAA==.Dorcater:BAAALgADCgEJAQAAAA==.',
Dr='Dradmaster:BAAALgADCgYJBgAAAA==.Drakth:BAAALgADCgIJAQAAAA==.Drekker:BAAALgAECgcJEwAAAA==.Drhofmann:BAAALgAECgMJCQAAAA==.',
Du='Duffar:BAAALgAECgcJDgAAAA==.Dummblond:BAAALgAECgYJDQAAAA==.Dumptruck:BAAALgAECgYJCQAAAA==.Durgledore:BAAALgAECgUJDAAAAA==.',
Dy='Dysfunction:BAAALgADCgkJCQAAAA==.',
Ea='Earthshield:BAAALgAECgUJBwABLgAECgkJLQARAK4iAA==.',
Eg='Ego:BAAALgAECgYJDQAAAA==.',
El='Elipto:BAAALgADCgcJEwAAAA==.Ellaana:BAAALgAECgIJAgAAAA==.Elotarra:BAAALgADCgQJCgAAAA==.Elowentinsel:BAAALgADCgkJGgAAAA==.Elsiais:BAAALgADCgUJCwAAAA==.Elvarang:BAAALgADCgYJCQAAAA==.',
Er='Erasi:BAABLgAECn8VAAMUAAcJCgi6NQA9AQAUAAcJCgi6NQA9AQAVAAEJWgfhhgApAAAAAA==.',
Es='Es:BAABLgAECn8UAAISAAcJ8gS/pgA0AQASAAcJ8gS/pgA0AQAAAA==.Esttsumi:BAAALgADCgkJCQAAAA==.',
Eu='Euphia:BAAALgAECgQJBAAAAA==.',
Ex='Exiled:BAAALgADCgYJCQAAAA==.Exine:BAABLgAECn8UAAIWAAcJDhNqOQDJAQAWAAcJDhNqOQDJAQAAAA==.Exodiá:BAAALgADCgMJAwAAAA==.',
Fa='Faeonia:BAAALgAECgYJDwAAAA==.Faethe:BAAALgADCgMJAwABLgAECggJGQAHAKsjAA==.Farawaystare:BAAALgAECgQJBAAAAA==.Farwolf:BAAALgAECgYJCwAAAA==.Fayore:BAAALgADCgcJBwAAAA==.',
Fe='Fee:BAABLgAECn8nAAIFAAgJEx5zIQCkAgAFAAgJEx5zIQCkAgAAAA==.Fellyn:BAAALgADCgYJBgAAAA==.Feloniusmunk:BAAALgADCgQJCgAAAA==.Fenrith:BAAALgADCgIJAgAAAA==.Feyt:BAAALgADCgMJAwAAAA==.',
Fi='Fidelis:BAAALgADCgYJBgAAAA==.Figaro:BAAALgAECgcJEwAAAA==.Filthy:BAAALgAECgMJBAAAAA==.',
Fl='Flameheart:BAAALgADCgkJFwAAAA==.Fleathulhu:BAABLgAECn8fAAIVAAgJpBCICAB4AQAVAAgJpBCICAB4AQAAAA==.Flungpu:BAAALgADCgkJCQABLgAECgYJFAAWAFoKAA==.',
Fo='Foleigh:BAAALgADCggJCwAAAA==.Fostock:BAAALgAECgUJBwAAAA==.Foxieshoxie:BAAALgAECgEJAQAAAA==.',
Fr='Frontierland:BAAALgADCgcJDQAAAA==.Frostmoon:BAAALgADCgIJAgAAAA==.Frozty:BAAALgADCggJCAAAAA==.',
Fu='Fuzzie:BAAALgADCgYJBAAAAA==.',
Ga='Gankuskhan:BAAALgAECgQJBAAAAA==.Ganlolf:BAAALgAECgQJBAABLgAECgQJBQAGAAAAAA==.Ganook:BAAALgADCgkJCgAAAA==.Garwynn:BAABLgAECn8cAAIXAAgJERGwAQCwAQAXAAgJERGwAQCwAQAAAA==.',
Gh='Ghoulmaxing:BAAALgAECgEJAQAAAA==.',
Gi='Gimper:BAAALgADCgcJFAAAAA==.',
Gl='Glen:BAAALgAECgIJAgAAAA==.',
Go='Goldengraham:BAAALgADCgcJCQAAAA==.Gorgutz:BAAALgADCgEJAQAAAA==.',
Gr='Graeman:BAAALgADCgMJAwAAAA==.',
Gw='Gwyn:BAAALgADCgQJBAAAAA==.',
['Gæ']='Gætherr:BAAALgAECgQJBQAAAA==.',
Ha='Habbyb:BAAALgADCgUJBAAAAA==.Habbypallie:BAAALgADCgUJCQAAAA==.Haimanist:BAAALgAECggJEgABLgAFFAMJBwACAM8iAA==.Halixan:BAAALgAECgYJEgAAAA==.Handlebardoc:BAABLgAECn8iAAISAAcJ7B22NQBgAgASAAcJ7B22NQBgAgAAAA==.Harmoni:BAAALgADCgEJAQABLgAECggJGQAHAKsjAA==.',
He='Healmemommy:BAAALgAECgYJCgAAAA==.Healze:BAAALgADCgUJBgAAAA==.Hemorrvoid:BAAALgAECgMJBQAAAA==.Heyei:BAAALgAECgUJBgAAAA==.',
Hi='Highroller:BAAALgADCgQJBgAAAA==.',
Ho='Holyname:BAAALgADCgIJAgAAAA==.',
Hu='Huttboles:BAAALgAECgYJDAAAAA==.',
Hy='Hydrozortek:BAAALgAECgEJAQAAAA==.',
Ia='Iamlegend:BAAALgADCgcJBwAAAA==.',
Ib='Iblis:BAAALgADCgcJEgAAAA==.',
Ig='Ignivoid:BAAALgADCggJCAAAAA==.',
Ij='Ijillien:BAAALgADCgkJGAAAAA==.',
Im='Imahaa:BAAALgADCgMJAwAAAA==.Imonster:BAABLgAECn8XAAIYAAcJJwmOIwAMAQAYAAcJJwmOIwAMAQAAAA==.',
Ir='Ironfizt:BAAALgAECgYJBgABLgAECgYJEQAGAAAAAA==.',
It='Itsgotime:BAAALgAECgMJBQAAAA==.',
Iu='Iudex:BAAALgAECgYJBwAAAA==.',
Ja='Jaaru:BAAALgADCggJEwAAAA==.Jaayycee:BAAALgAECgMJAwAAAA==.Jamus:BAABLgAECn8tAAMRAAkJriJGAgBYAwARAAkJriJGAgBYAwAFAAMJcwyfQACMAAAAAA==.',
Je='Jedavon:BAAALgADCgkJGwAAAA==.Jerriden:BAAALgADCgUJCAAAAA==.',
Ji='Jilibean:BAAALgADCgIJAgAAAA==.',
Jo='Jons:BAAALgADCgYJEQAAAA==.Joé:BAAALgADCgEJAQAAAA==.',
Ka='Kaazel:BAABLgAECn8UAAIWAAYJWgr6HAAXAQAWAAYJWgr6HAAXAQAAAA==.Kacee:BAAALgAECgQJBgAAAA==.Kaldor:BAAALgAECgQJBgAAAA==.Kalispo:BAAALgAECgEJAgAAAA==.Kallias:BAAALgADCggJFQAAAA==.Karite:BAABLgAECn8YAAIZAAcJaR/ZAADOAQAZAAcJaR/ZAADOAQAAAA==.Karom:BAAALgADCgMJAwAAAA==.Karsh:BAABLgAECn8eAAINAAgJEBbZBADhAQANAAgJEBbZBADhAQAAAA==.Katyla:BAAALgADCgQJBAABLgAECgcJGQAWAMAKAA==.Kazar:BAAALgADCgQJCAAAAA==.Kazenoth:BAABLgAECn8cAAIPAAgJHRjTAwDhAQAPAAgJHRjTAwDhAQAAAA==.',
Ke='Kellement:BAAALgAECgMJAwAAAA==.Ken:BAAALgADCggJJgAAAA==.Kennychaoss:BAAALgADCggJGwAAAA==.',
Ki='Kille:BAAALgAECgEJAQAAAA==.',
Kn='Knucks:BAAALgADCgYJBgAAAA==.',
Ko='Koomgak:BAAALgAECgEJAQAAAA==.Kosseluna:BAAALgAECgYJDwAAAA==.Kostazu:BAABLgAECn8cAAIaAAgJig9FDAA4AQAaAAgJig9FDAA4AQAAAA==.Kozanat:BAAALgADCgEJAQAAAA==.Kozzy:BAAALgADCgUJBQAAAA==.',
Ku='Kulthulhu:BAAALgADCgcJBwABLgAECggJHwAVAKQQAA==.Kushcoma:BAAALgAECgYJCQAAAA==.',
Kv='Kvn:BAAALgADCgYJCQAAAA==.',
Ky='Kynvana:BAAALgADCgcJDQAAAA==.',
['Kí']='Kíns:BAAALgAECgEJAQAAAA==.',
La='Laity:BAABLgAECn8WAAIFAAgJZhvGBwAOAgAFAAgJZhvGBwAOAgAAAA==.Lanfer:BAAALgADCgcJGgAAAA==.Larethar:BAAALgADCggJBwAAAA==.Laurentos:BAAALgADCgkJFAAAAA==.Lazylaz:BAABLgAECn8YAAITAAcJjiQbBADjAgATAAcJjiQbBADjAgABLgAFFAUJDQASALcVAA==.Lazyriver:BAAALgAECgcJEwAAAA==.',
Le='Lebigmu:BAAALgAECgUJDAAAAA==.Lebleb:BAAALgADCgYJBwAAAA==.Leeanna:BAAALgAECgUJBwAAAA==.Lexý:BAAALgAECgEJAQAAAA==.',
Li='Lieff:BAAALgAECgUJBwAAAA==.Lilctown:BAAALgADCgcJDQAAAA==.Liliyn:BAAALgAECgcJEAABLgAECggJHAALAC8dAA==.Lilsoulz:BAAALgADCgUJCQAAAA==.Lindwych:BAAALgADCgYJBgAAAA==.Lisettar:BAABLgAECn8ZAAIWAAcJwAo8HQAWAQAWAAcJwAo8HQAWAQAAAA==.Livedcargox:BAAALgADCgMJAwAAAA==.',
Lo='Lockvegas:BAAALgAECgIJAgAAAA==.Lorindis:BAAALgAECgIJAwAAAA==.',
Lu='Luciferser:BAAALgAECgEJAQAAAA==.Luminara:BAAALgADCgMJAwAAAA==.Luthbruk:BAAALgADCgYJBgAAAA==.Luxsaria:BAAALgADCgcJBwAAAA==.',
Ly='Lycanbyte:BAAALgADCggJFwAAAA==.Lylith:BAABLgAECn8XAAIbAAcJVRNtBQBwAQAbAAcJVRNtBQBwAQAAAA==.Lysanndra:BAAALgADCgUJBQAAAA==.',
['Lû']='Lûså:BAAALgAECgEJAgAAAA==.',
Ma='Madamcarnage:BAAALgADCgEJAgAAAA==.Magdalena:BAAALgAECgUJDwAAAA==.Magicboi:BAAALgAECgYJEQAAAA==.Magikos:BAAALgAECgEJAQAAAA==.Magnólia:BAAALgAECgYJEwAAAA==.Makima:BAAALgADCgcJCQABLgAECgcJFgAHAA8iAA==.Manbearcat:BAAALgADCgEJAQAAAA==.Manbearpigg:BAAALgADCgEJAQAAAA==.Maribelle:BAAALgADCgYJCgABLgAECggJGQAHAKsjAA==.Marrent:BAAALgADCgcJGAAAAA==.Matlen:BAAALgADCgUJBgAAAA==.Mavelana:BAAALgAECgcJBQAAAA==.Mazeltov:BAABLgAECn8WAAIIAAgJPRrMDgAcAgAIAAgJPRrMDgAcAgAAAA==.',
Me='Melomel:BAAALgAECgUJBwAAAA==.Melonsquezer:BAABLgAECn8YAAMMAAcJAx2TAwCRAQAMAAYJ2B6TAwCRAQAFAAEJ2RPEMwE9AAAAAA==.Menmei:BAAALgAECgUJBwAAAA==.Meygen:BAAALgAECgUJBQAAAA==.',
Mi='Minbyunggyu:BAAALgADCgUJBQAAAA==.Minien:BAABLgAECn8WAAMcAAYJGhe1AwCHAQAcAAYJPxa1AwCHAQAaAAYJEBNVPABbAQAAAA==.Minko:BAABLgAECn8VAAIWAAcJtRTiMADtAQAWAAcJtRTiMADtAQAAAA==.Minore:BAAALgAECgcJCwAAAA==.Mishifu:BAAALgAECgQJBAAAAA==.',
Mo='Modelo:BAAALgAECgYJBgAAAA==.Monkaholic:BAAALgAECgQJBAAAAA==.Moonshot:BAABLgAECn8cAAIdAAgJQRT3AgCRAQAdAAgJQRT3AgCRAQAAAA==.Morillic:BAAALgAECgYJEQAAAA==.Mouchii:BAAALgAECgEJAQAAAA==.Mousepad:BAAALgADCgEJAQAAAA==.',
Ms='Mstrcrowly:BAAALgAECgUJCgAAAA==.',
Mu='Mustachjones:BAABLgAECn8VAAIYAAcJeRzFMwA9AgAYAAcJeRzFMwA9AgAAAA==.',
My='Myros:BAABLgAECn8YAAMHAAcJPRhWJgA2AQAHAAcJPRhWJgA2AQAJAAEJ/AVRBAA5AAAAAA==.',
['Mí']='Mísfire:BAAALgAECgEJAQAAAA==.',
Na='Naakos:BAAALgADCgUJCgAAAA==.Naih:BAAALgADCgMJAwAAAA==.Nantari:BAAALgADCggJBwAAAA==.Narestor:BAAALgAECggJDgABLgAECgcJFwAQAI4PAA==.Navras:BAAALgADCgIJAgAAAA==.Nazurend:BAAALgAECgQJBQAAAA==.',
Nb='Nblock:BAAALgAECgQJBwAAAA==.',
Ne='Nekopunch:BAAALgAECgYJBgAAAA==.Nero:BAABLgAECn8hAAIbAAgJ2SHQAACEAgAbAAgJ2SHQAACEAgAAAA==.Nest:BAAALgADCgYJDQAAAA==.',
Ni='Nicholas:BAAALgADCgIJAgAAAA==.Nicorobin:BAABLgAECn8fAAMYAAgJNAUVfQBhAQAYAAgJNAUVfQBhAQAeAAIJywFTZgBDAAAAAA==.Nimuerose:BAAALgADCgMJAwAAAA==.',
No='Nortree:BAAALgAECgQJBgAAAA==.Nost:BAABLgAECn8YAAIFAAcJcRkWDQDFAQAFAAcJcRkWDQDFAQAAAA==.Notthatbish:BAAALgADCgYJBgAAAA==.',
Nu='Nulwyrm:BAAALgAECgYJEwAAAA==.',
Ny='Nyyrivik:BAAALgADCgYJBgAAAA==.',
['Nø']='Nøtrab:BAAALgADCgQJBAAAAA==.',
Oc='Octapie:BAABLgAECn8XAAIBAAYJCCFyBAApAgABAAYJCCFyBAApAgAAAA==.',
Oh='Ohitsadragon:BAAALgAECgYJCgAAAA==.',
Or='Oranur:BAAALgADCgIJAgAAAA==.Orclock:BAAALgAECgQJAQABLgAECgYJBgAGAAAAAA==.',
Ow='Owl:BAABLgAECn8WAAIfAAcJBgdSDQBgAQAfAAcJBgdSDQBgAQAAAA==.Owlcatraz:BAAALgAECgUJCAAAAA==.',
Pa='Paendrag:BAAALgADCgUJBQAAAA==.Panadarama:BAACLgAFFH8HAAICAAMJzyKlBAAzAQACAAMJzyKlBAAzAQAuAAQKfyAAAgIACAkQJWgEAEUDAAIACAkQJWgEAEUDAAAA.Panteragon:BAAALgAECgUJBwAAAA==.Pasara:BAAALgADCgQJBAAAAA==.',
Pe='Periwinkle:BAABLgAECn8WAAIVAAYJkwv0DgAAAQAVAAYJkwv0DgAAAQAAAA==.Persaud:BAAALgAECgcJEwAAAA==.Pettacular:BAAALgADCgMJAwAAAA==.',
Ph='Phidra:BAABLgAECn8YAAMBAAcJFw2ADQBmAQABAAcJFw2ADQBmAQAaAAQJTgasagCYAAAAAA==.Philiia:BAAALgADCgQJBAAAAA==.Phranky:BAAALgADCgQJBAABLgAECgEJAQAGAAAAAA==.',
Pi='Pixiebrew:BAAALgAECgQJBgAAAA==.',
Pl='Plutrax:BAAALgADCgcJEAAAAA==.',
Po='Pokecheck:BAAALgADCgUJBgAAAA==.',
Pr='Predatorc:BAAALgAECggJEwAAAA==.Primevl:BAAALgADCgQJBAAAAA==.Primévil:BAABLgAECn8cAAIgAAgJCAo1HAAhAQAgAAgJCAo1HAAhAQAAAA==.',
Pu='Puma:BAAALgAECgUJDAAAAA==.',
['Pí']='Píp:BAAALgADCgcJBwAAAA==.',
Qu='Quarz:BAAALgADCgkJFAAAAA==.Quimmi:BAAALgADCgMJAwAAAA==.',
Ra='Raediant:BAAALgAECgQJBQABLgAECgcJEwAGAAAAAA==.Raelek:BAAALgADCggJCAAAAA==.Ragethecage:BAAALgADCgMJAwAAAA==.Raggaemon:BAAALgAECgMJBgAAAA==.Ragingbanana:BAAALgAECgEJAQAAAA==.Rahmonk:BAAALgADCgEJAQAAAA==.Rahvinwulf:BAAALgAECgYJDwAAAA==.Raquel:BAABLgAECn8ZAAIBAAgJUQtrRwBkAQABAAgJUQtrRwBkAQAAAA==.Raszageth:BAAALgADCgEJAQAAAA==.Raínbowdash:BAAALgADCgEJAQAAAA==.',
Re='Rede:BAAALgADCgkJGwAAAA==.Rein:BAAALgAECgIJAgABLgAECgQJBAAGAAAAAA==.Relieff:BAAALgADCgcJCQAAAA==.Relmin:BAAALgADCgYJCwAAAA==.Rennistus:BAAALgADCgYJBgAAAA==.',
Ri='Rio:BAABLgAECn8WAAIbAAgJbhLpKQB1AQAbAAgJbhLpKQB1AQAAAA==.Ris:BAABLgAECn8fAAIHAAcJjyA2CgAHAgAHAAcJjyA2CgAHAgAAAA==.Riseyyn:BAAALgADCgIJAgAAAA==.',
Ro='Roknathar:BAABLgAECn8bAAIdAAcJoSVsAAB+AgAdAAcJoSVsAAB+AgAAAA==.Ronilf:BAAALgAECgYJEQAAAA==.Rou:BAAALgADCgUJBQAAAA==.Rough:BAAALgADCgEJAQAAAA==.Royda:BAABLgAECn8gAAMUAAgJhRsqAwAKAgAUAAgJhRsqAwAKAgAVAAIJyhNoiAAnAAAAAA==.',
Ru='Ruitiny:BAAALgADCgkJEAAAAA==.Rukaza:BAAALgAECgEJAQABLgAECggJLAAhAB0kAA==.',
Ry='Rygard:BAAALgADCgQJBAAAAA==.',
Sa='Saerenity:BAAALgADCgYJCgAAAA==.Saintlucky:BAAALgADCgYJBgAAAA==.Saintvonzeal:BAAALgADCggJFQAAAA==.Sana:BAABLgAECn8VAAIaAAcJDBzoHQAgAgAaAAcJDBzoHQAgAgAAAA==.Saphihr:BAAALgADCgYJBgAAAA==.Sazerac:BAAALgAECgUJEAAAAA==.',
Sc='Scaly:BAAALgAECgEJAQABLgAECgMJBAAGAAAAAA==.',
Se='Selenis:BAAALgAECgEJAQABLgAECgcJFQASAPMiAA==.',
Sg='Sgtshamrock:BAAALgADCgIJAgAAAA==.',
Sh='Shadowlady:BAAALgAECgEJAQAAAA==.Shadowrealms:BAAALgADCgYJCAAAAA==.Shamainiac:BAABLgAECn8cAAIaAAgJhBNBCQBqAQAaAAgJhBNBCQBqAQAAAA==.Shaomai:BAABLgAECn8VAAMaAAcJFx9CFAB9AgAaAAcJFx9CFAB9AgABAAQJLw0UcwDDAAAAAA==.Sharper:BAAALgAECgcJEQABLgAECgcJIgASAOwdAA==.Shep:BAAALgADCgUJBwAAAA==.Sherra:BAAALgADCgIJAgAAAA==.Shiok:BAAALgADCggJFwAAAA==.Shâde:BAAALgAECgQJBgAAAA==.',
Si='Siirius:BAAALgAECgQJCAAAAA==.Silverwin:BAAALgAECgUJBwAAAA==.',
Sk='Skribbles:BAAALgADCgQJBAAAAA==.',
Sl='Slimage:BAABLgAECn8UAAIiAAgJdRhmAAAhAgAiAAgJdRhmAAAhAgAAAA==.Slushius:BAAALgAECgEJAQAAAA==.',
Sm='Smite:BAAALgAECgQJBgAAAA==.Smitted:BAAALgAECgYJEQAAAA==.Smitty:BAAALgAECgYJBgAAAA==.',
So='Socharis:BAAALgADCgMJAwAAAA==.Sodapops:BAAALgADCgcJBwAAAA==.Sophiaa:BAAALgADCgYJBQAAAA==.Sorn:BAAALgAECgUJCAAAAA==.',
Sp='Spaarkle:BAAALgAECgYJBwAAAA==.Specialheist:BAAALgAECgkJCAAAAA==.Spectrehawk:BAAALgAECgMJAwAAAA==.Speçtre:BAABLgAECn8bAAIEAAgJ4hTLEgDgAQAEAAgJ4hTLEgDgAQAAAA==.',
Sr='Srankhunter:BAAALgADCgcJDwAAAA==.',
St='Stallord:BAAALgADCgYJBgAAAA==.Steppin:BAAALgAECgYJBgABLgAECgYJEQAGAAAAAA==.Stormglaive:BAABLgAECn8aAAMbAAcJPhU3HQDWAQAbAAcJPhU3HQDWAQAgAAEJTwPT6QAoAAAAAA==.Stupidity:BAABLgAECn8aAAIUAAYJdB8OBwCMAQAUAAYJdB8OBwCMAQAAAA==.',
Su='Suldrick:BAAALgADCgkJEAAAAA==.Suppabad:BAABLgAECn8YAAMNAAcJmxneHADRAQANAAcJmxneHADRAQAjAAQJTRFjDwDcAAAAAA==.',
['Sá']='Sákura:BAAALgAECgIJBAAAAA==.',
Ta='Taara:BAAALgADCgUJBQABLgAECggJGQAHAKsjAA==.Tarysha:BAAALgAECgUJBQAAAA==.Tatertotz:BAAALgAECgUJCQAAAA==.Taynav:BAABLgAECn8VAAIkAAcJbBSZDgCWAQAkAAcJbBSZDgCWAQAAAA==.Tayoma:BAAALgADCgIJAgAAAA==.Tazara:BAAALgAECgEJAQAAAA==.',
Te='Tealth:BAAALgAECgMJAwAAAA==.Ted:BAAALgAECgYJCwAAAA==.Tehgrimza:BAABLgAECn8WAAMYAAcJsRT6EQCBAQAYAAcJsRT6EQCBAQAeAAEJrxBzdAAwAAAAAA==.Teias:BAAALgADCgIJAgABLgAECggJIAAVAFwaAA==.Temu:BAAALgAECgUJBQABLgAECgcJFgAHAA8iAA==.Tevia:BAABLgAECn8cAAIlAAgJwBGIAgCzAQAlAAgJwBGIAgCzAQAAAA==.',
Th='Thalip:BAAALgAECgQJBQAAAA==.Thokmay:BAABLgAECn8cAAIjAAgJqw77BwBZAQAjAAgJqw77BwBZAQAAAA==.Thorel:BAAALgADCggJFgAAAA==.Thornar:BAAALgADCgQJBAAAAA==.Thunden:BAAALgADCgUJBQAAAA==.',
Ti='Tiandrinna:BAAALgAECgYJEgAAAA==.Tightywhitey:BAAALgAECgYJBwAAAA==.Timkaoss:BAAALgAECgYJEwAAAA==.Timmyjudge:BAAALgADCgQJBAAAAA==.Tinyspoon:BAAALgADCgMJAwAAAA==.',
Tm='Tmagnet:BAAALgAECgUJBwAAAA==.',
To='Tooshie:BAAALgADCgcJBwAAAA==.Tormin:BAAALgADCgcJDQAAAA==.Torrente:BAAALgADCgEJAQAAAA==.Tourmaline:BAAALgADCgEJAgABLgAECgYJEwAGAAAAAA==.',
Tr='Treebud:BAAALgADCgkJDAAAAA==.Tritherelyn:BAAALgADCgcJBwAAAA==.Trixterwolf:BAAALgADCgUJBwAAAA==.',
Ts='Tserendolgor:BAAALgADCggJCAAAAA==.',
Tw='Tweedildee:BAABLgAECn8gAAIHAAgJYBR1EgCuAQAHAAgJYBR1EgCuAQAAAA==.',
Ty='Tygrassar:BAAALgADCgUJBgAAAA==.',
['Tà']='Tàttersail:BAABLgAECn8VAAIVAAcJFxqJGQAQAgAVAAcJFxqJGQAQAgAAAA==.',
Va='Vaelena:BAAALgADCgMJAwAAAA==.Vahldr:BAAALgAECgQJBQAAAA==.Valdor:BAAALgADCgcJBwAAAA==.Valeeras:BAAALgADCgUJBQAAAA==.Valeron:BAAALgAECgYJCQAAAA==.Valicous:BAAALgADCggJFAAAAA==.Valyerian:BAABLgAECn8uAAImAAgJ5hsXFgCcAgAmAAgJ5hsXFgCcAgAAAA==.Vandalie:BAAALgAECgEJAQABLgAECggJFQASAKMfAA==.Vandevoker:BAAALgAECgQJCAABLgAECggJFQASAKMfAA==.Vanserra:BAAALgADCgcJCgAAAA==.Varregory:BAAALgADCgQJBAAAAA==.Vaxas:BAAALgAECgcJEgAAAA==.Vaült:BAABLgAECn8YAAMRAAcJzxapBQACAgARAAcJzxapBQACAgAFAAMJPwYGEgFzAAAAAA==.',
Ve='Verianna:BAABLgAECn8VAAMSAAcJ8yIBFQBpAQASAAUJcyEBFQBpAQAEAAIJ8iVeCgDbAAAAAA==.Vexmorphis:BAAALgADCgUJBQABLgAECgEJAQAGAAAAAA==.Vexxis:BAAALgADCgMJAwAAAA==.',
Vo='Vodkâshots:BAAALgAECgIJAgAAAA==.Votary:BAAALgADCgcJDgAAAA==.',
Vt='Vtown:BAAALgADCgYJDQAAAA==.',
Wa='Wadumu:BAAALgAECgYJCwAAAA==.Wagwanmist:BAABLgAECn8XAAINAAYJ0xvnBADfAQANAAYJ0xvnBADfAQAAAA==.Wardrago:BAAALgADCgYJBgAAAA==.Warwulf:BAAALgAECgQJBAABLgAECgYJDwAGAAAAAA==.',
Wi='Willowy:BAABLgAECn8ZAAIHAAgJqyNjDQDfAQAHAAgJqyNjDQDfAQAAAA==.',
['Wâ']='Wâlmi:BAABLgAECn8WAAMBAAUJdQ7hGwC3AAABAAUJdQ7hGwC3AAAaAAQJvAZHaACiAAAAAA==.',
Xa='Xaerius:BAABLgAECn8YAAImAAcJ7hCuCwBlAQAmAAcJ7hCuCwBlAQAAAA==.Xalatath:BAAALgADCgcJDQAAAA==.Xan:BAABLgAECn8XAAIHAAgJPxliDADsAQAHAAgJPxliDADsAQAAAA==.Xann:BAAALgADCgUJBQAAAA==.Xantharr:BAAALgADCgMJAwAAAA==.Xantyr:BAAALgADCgYJBgAAAA==.Xashae:BAAALgADCgcJDwAAAA==.',
Xe='Xenocidal:BAAALgAECgcJEwAAAA==.',
Xo='Xog:BAAALgAECgEJAQAAAA==.',
Ya='Yaren:BAAALgADCgMJAwAAAA==.Yarman:BAAALgAECgUJBwAAAA==.',
Ye='Yeaforpie:BAAALgAECgYJDQAAAA==.Yervant:BAAALgAECgQJBAAAAA==.Yesthatbish:BAAALgAECgYJDQAAAA==.',
Yo='Yoshial:BAAALgADCgcJGQAAAA==.',
Za='Zadoc:BAAALgADCgcJGwAAAA==.Zano:BAABLgAECn8cAAMUAAgJqxEqHgDoAQAUAAgJqxEqHgDoAQAQAAYJjgzICwAIAQAAAA==.',
Ze='Zealins:BAAALgADCgUJCAAAAA==.Zenrek:BAAALgADCgEJAQAAAA==.Zenrekt:BAAALgADCgMJBAAAAA==.Zeuhl:BAAALgAECgcJCgAAAA==.',
Zi='Zilver:BAAALgADCgEJAQABLgAECggJJAAFAO8kAA==.Ziv:BAABLgAECn8cAAILAAgJLx18EQCrAgALAAgJLx18EQCrAgAAAA==.',
['Ôa']='Ôath:BAAALgAECgEJAQAAAA==.',
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

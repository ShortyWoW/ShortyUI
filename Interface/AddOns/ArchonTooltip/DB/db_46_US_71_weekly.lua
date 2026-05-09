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

local lookup = {'Shaman-Restoration','Monk-Brewmaster','DeathKnight-Blood','DeathKnight-Frost','Paladin-Retribution','Unknown-Unknown','Druid-Balance','Mage-Frost','Warrior-Protection','Mage-Fire','Druid-Restoration','Paladin-Protection','Rogue-Assassination','Monk-Mistweaver','Evoker-Devastation','Evoker-Augmentation','Warrior-Fury','Priest-Discipline','Paladin-Holy','DeathKnight-Unholy','Druid-Feral','DemonHunter-Vengeance','DemonHunter-Havoc','DemonHunter-Devourer','Hunter-Survival','Warlock-Demonology','Priest-Shadow','Priest-Holy','Hunter-BeastMastery','Shaman-Enhancement','Rogue-Subtlety','Rogue-Outlaw','Evoker-Preservation','Warlock-Destruction','Shaman-Elemental','Hunter-Marksmanship','Warlock-Affliction','Mage-Arcane','Monk-Windwalker','Druid-Guardian','Warrior-Arms',}
local provider = {region='US',realm='Draenor',name='US',type='weekly',zone=46,date='2026-05-08',data={Ac='Achiella:BAAALgADCgIJAgAAAA==.',
Ad='Advisor:BAACLgAFFH8HAAIBAAQJkBAiGAANAQABAAQJkBAiGAANAQAuAAQKfyUAAgEACAmfJG0JAOECAAEACAmfJG0JAOECAAAA.',
Ae='Aería:BAAALgAECgYJDgAAAA==.',
Ah='Ahnkho:BAAALgAECgEJAQAAAA==.',
Ai='Ailea:BAAALgAECgEJAQAAAA==.Aindie:BAAALgADCgEJAQAAAA==.',
Ak='Akarm:BAAALgADCgcJBwAAAA==.',
Al='Alcomancer:BAAALgADCgIJAgAAAA==.Aleks:BAAALgAECgQJBAAAAA==.Aluna:BAAALgAECgcJEAAAAA==.Alvarr:BAAALgADCgcJEAAAAA==.',
Am='Amalia:BAAALgADCgEJAQAAAA==.Amandakk:BAAALgADCgkJHAAAAA==.Aminas:BAAALgAECgEJAQAAAA==.',
An='Annya:BAAALgAECgYJBgAAAA==.Antheria:BAAALgADCgMJAwAAAA==.',
Ap='Aphrodite:BAAALgAECgYJEAAAAA==.',
Ar='Archie:BAAALgAECgQJBgAAAA==.Arendt:BAAALgADCgQJCwAAAA==.Arkahera:BAAALgAECgQJBQABLgAFFAMJCgACAM8iAA==.Arolder:BAABLgAECn8fAAMDAAgJeCBsBAB0AgADAAgJsh9sBAB0AgAEAAcJZB3cAwA7AgAAAA==.Arturium:BAAALgADCgYJCQAAAA==.',
At='Atabey:BAABLgAECn8yAAIFAAkJSB75BwDSAgAFAAkJSB75BwDSAgABLgABCgMJAwAGAAAAAA==.Atimusk:BAAALgADCggJDwAAAA==.Atoadaso:BAAALgAECgQJBAAAAA==.Attretes:BAAALgADCgcJDwAAAA==.',
Az='Azcowboy:BAAALgAECgMJCAAAAA==.Azezel:BAAALgADCgYJBgAAAA==.Aznå:BAAALgAECgIJAgAAAA==.',
Ba='Balacheck:BAAALgAECgYJEwAAAA==.Bang:BAAALgADCgEJAQAAAA==.Barecub:BAAALgADCgQJCgAAAA==.Barton:BAAALgADCgcJCQAAAA==.Baultenaz:BAAALgADCgQJBAAAAA==.',
Bb='Bbite:BAABLgAECn8hAAIHAAgJoBqqCwAPAgAHAAgJoBqqCwAPAgAAAA==.',
Be='Beanwater:BAAALgAECgMJAwAAAA==.Belmax:BAAALgADCgQJCgAAAA==.Bemon:BAAALgADCgcJBwABLgAECgcJFAAIAKAcAA==.',
Bi='Bigbadwoof:BAAALgADCgYJGQAAAA==.Bighog:BAABLgAFFH8MAAIJAAQJFh3qBQBQAQAJAAQJFh3qBQBQAQAAAA==.Bipbipbup:BAAALgADCgQJBAAAAA==.',
Bl='Blaazzin:BAAALgADCgYJCAAAAA==.Blessa:BAAALgADCgkJCQAAAA==.Bloomzy:BAABLgAECn8jAAMIAAkJNRTSIgAcAgAIAAkJdBPSIgAcAgAKAAIJehtaCgCfAAAAAA==.Blytzbrigade:BAAALgADCgkJDQAAAA==.',
Bo='Boneycheese:BAAALgADCgYJCgAAAA==.Boombástic:BAABLgAECn8eAAMHAAgJ/g9WIAA0AQAHAAYJVRJWIAA0AQALAAIJzg8rcwBnAAAAAA==.Boomco:BAAALgAECgUJBwAAAA==.Bors:BAAALgADCgQJBwAAAA==.Boulderholdr:BAAALgADCgkJFwAAAA==.Boxing:BAAALgADCgIJAgAAAA==.',
Br='Breaddy:BAAALgAECgYJCwAAAA==.Breeti:BAAALgAECgUJEAAAAA==.Broin:BAAALgAECgEJAQAAAA==.Bronte:BAABLgAECn8cAAIMAAkJxRmcCgAkAgAMAAkJxRmcCgAkAgAAAA==.Bryda:BAAALgADCgkJGQAAAA==.',
Bu='Bubblez:BAAALgADCgYJCQAAAA==.Burblingbee:BAAALgADCgcJBwAAAA==.',
Bw='Bwucewee:BAAALgADCgcJCAAAAA==.',
Ca='Cajbo:BAABLgAECn8gAAINAAcJCx30AgAYAgANAAcJCx30AgAYAgAAAA==.Calyssa:BAABLgAECn8dAAIFAAcJ7Q24VwBCAQAFAAcJ7Q24VwBCAQAAAA==.Candyflöss:BAAALgAFFAIJAwAAAA==.Carpe:BAAALgAECgYJBgAAAA==.Cartan:BAABLgAECn80AAIOAAkJ2xsZBADmAgAOAAkJ2xsZBADmAgAAAA==.Cathelina:BAAALgADCggJDwAAAA==.Cathom:BAAALgAECgQJBwAAAA==.',
Ch='Charizaard:BAAALgADCggJDAAAAA==.Charizaardx:BAACLgAFFH8HAAMPAAQJzATyAwDWAAAQAAQJ7AN2HQD9AAAPAAMJWwXyAwDWAAAuAAQKfy0AAw8ACAlVGLQEAKYBAA8ACAnoErQEAKYBABAABwkFFe4lAI0BAAAA.Chevytron:BAAALgAECgYJEQAAAA==.Chune:BAAALgADCgcJDAAAAA==.',
Ci='Cinder:BAAALgADCgIJAgAAAA==.',
Cl='Clement:BAAALgAECgQJBAAAAA==.Cletus:BAABLgAECn8XAAMRAAYJgxCWMAAKAQARAAYJYA+WMAAKAQAJAAIJmwt9NwAuAAAAAA==.Clément:BAAALgADCgUJBQAAAA==.',
Co='Coffeebeans:BAABLgAECn8iAAMLAAgJExbgPgCnAQALAAcJfxTgPgCnAQAHAAgJwAuxGgBhAQAAAA==.Cowabunga:BAAALgADCgIJAgAAAA==.Cowkiller:BAAALgADCgIJAgAAAA==.',
Cr='Crazyasian:BAAALgAECgYJCgAAAA==.Crogan:BAAALgAECgcJDQAAAA==.Crysiscane:BAAALgADCgYJBQAAAA==.',
Ct='Ctrlaltdk:BAAALgAECgEJAQABLgAECgIJAwAGAAAAAA==.',
Cy='Cybrocookie:BAAALgADCgEJAQAAAA==.Cyrberus:BAAALgAECgUJBwAAAA==.',
['Cá']='Cáposhady:BAAALgAECgEJAQAAAA==.',
Da='Dagda:BAAALgADCgMJAwAAAA==.Dalna:BAABLgAECn8dAAIOAAcJ3w9kHgBUAQAOAAcJ3w9kHgBUAQAAAA==.Danilex:BAABLgAECn8cAAIIAAgJCx9lSABeAgAIAAgJCx9lSABeAgABLgAFFAYJGgASALgSAA==.Danksoul:BAAALgADCgUJBQABLgAECggJGAATAK4ZAA==.Darcorin:BAABLgAECn8fAAIUAAgJIBaWLwC7AQAUAAgJIBaWLwC7AQAAAA==.Darkblitz:BAAALgADCgQJBQAAAA==.Darklürker:BAAALgAECgQJDQAAAA==.Darksaber:BAAALgADCgkJGgAAAA==.Dasthodan:BAAALgADCgkJFgAAAA==.Dayne:BAAALgAECgUJBgAAAA==.',
Dc='Dctrpepper:BAAALgADCggJJAAAAA==.',
De='Deathcore:BAAALgADCgUJBQAAAA==.Deathminions:BAAALgADCgUJBQAAAA==.Deathwish:BAAALgADCgIJAgAAAA==.Decklan:BAAALgADCgEJAQAAAA==.Decorum:BAAALgADCgEJAQAAAA==.Defiant:BAAALgADCgEJAQAAAA==.Deilliann:BAABLgAECn8kAAQLAAgJxQWaTADhAAALAAgJxQWaTADhAAAHAAgJgAKoMwDAAAAVAAIJhQCGOgAdAAAAAA==.Deldawalth:BAAALgADCgcJEgAAAA==.Delvisprezly:BAAALgAECgIJAwAAAA==.Demonica:BAABLgAECn8VAAQWAAcJdgd/DgDYAAAXAAUJ4QYoRADmAAAWAAcJyAZ/DgDYAAAYAAEJnwjvvAAvAAAAAA==.Demonky:BAAALgAECgIJAgAAAA==.Demonology:BAAALgADCgYJBwAAAA==.Demonspecial:BAAALgAECgkJBwAAAA==.Denastus:BAAALgADCgEJAQAAAA==.Dethknyght:BAAALgAECggJCAABLgAFFAMJCgACAM8iAA==.Devick:BAAALgAECgEJAQAAAA==.',
Di='Dinta:BAABLgAECn8tAAIFAAkJBxl1IgD8AQAFAAkJBxl1IgD8AQAAAA==.Dip:BAAALgADCgcJBwAAAA==.',
Dj='Djabuty:BAAALgAECgEJAgAAAA==.',
Do='Dominoes:BAAALgAECgUJBwAAAA==.Domìnion:BAAALgADCgkJEAAAAA==.Dorcater:BAAALgADCgEJAQAAAA==.',
Dr='Dradmaster:BAAALgADCgYJBgAAAA==.Drakth:BAAALgADCgIJAQAAAA==.Drekker:BAABLgAECn8WAAICAAgJ+AsoTQAOAQACAAgJ+AsoTQAOAQAAAA==.Drhofmann:BAAALgAECgMJCQAAAA==.',
Du='Duffar:BAABLgAECn8dAAIZAAgJ+wp1EQCYAQAZAAgJ+wp1EQCYAQAAAA==.Dummblond:BAAALgAFFAIJAgAAAA==.Dumptruck:BAAALgAECgYJCQAAAA==.Durgledore:BAABLgAECn8WAAIaAAcJohosLwCmAQAaAAcJohosLwCmAQAAAA==.',
Dy='Dysfunction:BAAALgAECgUJBQAAAA==.',
Ea='Earthshield:BAAALgAECgYJDQABLgAECgkJOQATADgkAA==.',
Eg='Ego:BAABLgAECn8VAAITAAcJ8yBoCQB7AgATAAcJ8yBoCQB7AgAAAA==.',
El='Elipto:BAAALgADCgcJGQAAAA==.Ellaana:BAAALgAECgQJBwAAAA==.Elotarra:BAAALgAECgEJAQAAAA==.Elowentinsel:BAAALgADCgkJLAAAAA==.Elsiais:BAAALgADCgUJCwAAAA==.Elvarang:BAAALgADCgYJCQAAAA==.',
En='Enduran:BAAALgAECgYJBwAAAA==.',
Er='Erasi:BAABLgAECn8kAAMbAAgJ2gjWHQBNAQAbAAgJ2gjWHQBNAQAcAAMJ4QMNSQBBAAAAAA==.',
Es='Es:BAABLgAECn8UAAIUAAcJ8gS9pgA0AQAUAAcJ8gS9pgA0AQAAAA==.Escanorlion:BAAALgADCgcJBwAAAA==.Esttsumi:BAAALgAECgkJDwAAAA==.',
Eu='Euphia:BAAALgAECgUJDAAAAA==.',
Ex='Exiled:BAAALgADCgYJCQAAAA==.Exine:BAABLgAECn8iAAIdAAgJrRFqOQDJAQAdAAgJrRFqOQDJAQAAAA==.Exodiá:BAAALgADCgMJAwAAAA==.',
Ey='Eyebee:BAAALgADCgEJAQAAAA==.',
Fa='Faeonia:BAABLgAECn8dAAIFAAgJJRsZIgD+AQAFAAgJJRsZIgD+AQAAAA==.Faethe:BAAALgADCgMJAwABLgAECggJJwAIACQkAA==.Farawaystare:BAAALgAECgQJBAAAAA==.Farwolf:BAABLgAECn8VAAIdAAcJEwvdRgA5AQAdAAcJEwvdRgA5AQAAAA==.Fayore:BAAALgADCgcJBwAAAA==.',
Fe='Fearmaxxing:BAAALgAECgcJBwAAAA==.Fee:BAABLgAECn8xAAIFAAkJFyPxAgAvAwAFAAkJFyPxAgAvAwAAAA==.Fellyn:BAAALgADCgYJBwAAAA==.Feloniusmunk:BAAALgADCgQJCgAAAA==.Fenrith:BAAALgADCggJCAAAAA==.Feyt:BAAALgADCgMJAwAAAA==.',
Fi='Fidelis:BAAALgADCgYJBgAAAA==.Figaro:BAAALgAECgcJEwAAAA==.Filthy:BAAALgAECgQJBQAAAA==.',
Fl='Flameheart:BAAALgAECgYJCwAAAA==.Fleathulhu:BAABLgAECn8nAAIcAAgJYRWzEQDWAQAcAAgJYRWzEQDWAQAAAA==.Flungpu:BAAALgADCgkJFwABLgAECggJHwAdAJsLAA==.',
Fo='Foleigh:BAAALgADCggJCwAAAA==.Fostock:BAAALgAECgYJEgAAAA==.Foxieshoxie:BAAALgAECgEJAgAAAA==.',
Fr='Frontierland:BAAALgADCgcJDQAAAA==.Frostmoon:BAAALgADCgIJAgAAAA==.Frozty:BAAALgADCggJCAAAAA==.',
Fu='Furrfoxsake:BAAALgADCggJCAAAAA==.Fuzzie:BAAALgADCgYJBAAAAA==.',
Ga='Gankuskhan:BAAALgAECgQJBAAAAA==.Ganlolf:BAAALgAECgQJBAABLgAECgQJBQAGAAAAAA==.Ganook:BAAALgADCgkJCgAAAA==.Garwynn:BAABLgAECn8tAAINAAkJjRPkAgAbAgANAAkJjRPkAgAbAgAAAA==.',
Gh='Ghoulmaxing:BAAALgAECgEJAwAAAA==.Ghøulish:BAAALgADCgMJAwABLgAECgcJHQALAIQMAA==.',
Gi='Gimper:BAAALgADCgcJFwAAAA==.',
Gl='Glaistia:BAAALgADCgIJAgAAAA==.Glen:BAAALgAECgQJBwAAAA==.',
Go='Goldengraham:BAAALgADCgcJCQAAAA==.Gorgutz:BAAALgADCgEJAQAAAA==.Gormlaîth:BAAALgADCgkJCQAAAA==.',
Gr='Graeman:BAAALgADCgMJAwAAAA==.Greatpàw:BAAALgADCgUJBAAAAA==.Grisly:BAAALgADCgUJBQAAAA==.',
Gu='Gurrney:BAAALgADCgYJBgAAAA==.',
Gw='Gwyn:BAAALgADCgQJBAAAAA==.',
['Gæ']='Gætherr:BAAALgAECgQJBQAAAA==.',
Ha='Habbyb:BAAALgAECgIJAgAAAA==.Habbypallie:BAAALgADCgUJDgAAAA==.Haimanist:BAABLgAECn8ZAAIMAAgJjSAkAwDwAgAMAAgJjSAkAwDwAgABLgAFFAMJCgACAM8iAA==.Halixan:BAABLgAECn8aAAIeAAgJFSNVAQDNAgAeAAgJFSNVAQDNAgAAAA==.Handlebardoc:BAACLgAFFH8HAAIUAAMJKRxqRgABAQAUAAMJKRxqRgABAQAuAAQKfzAAAhQACAmnIY8MAKECABQACAmnIY8MAKECAAAA.Harmoni:BAAALgAECgIJAgABLgAECggJJwAIACQkAA==.Hatorade:BAAALgAECgQJBAAAAA==.',
He='Healmemommy:BAAALgAECgYJCgAAAA==.Healsrus:BAAALgAECgMJAgAAAA==.Healze:BAAALgADCgUJBgAAAA==.Hemorrvoid:BAAALgAECgMJBQAAAA==.Heyei:BAAALgAECgUJBgAAAA==.',
Hi='Highroller:BAAALgADCgQJBgAAAA==.',
Ho='Holyname:BAAALgADCgIJAgAAAA==.',
Hy='Hydrozortek:BAAALgAECgEJAQAAAA==.',
Ia='Iamlegend:BAAALgADCgcJBwAAAA==.',
Ib='Iblis:BAAALgADCgcJEgAAAA==.',
Ig='Ignivoid:BAAALgADCggJCAAAAA==.',
Ij='Ijillien:BAAALgAECgIJAgAAAA==.',
Im='Imahaa:BAAALgADCgMJAwAAAA==.Imonster:BAABLgAECn8iAAIaAAgJywhzRwBSAQAaAAgJywhzRwBSAQAAAA==.',
Ir='Ironfizt:BAAALgAECggJDwABLgAECgcJFgAfAAMZAA==.',
It='Itsgotime:BAAALgAECgMJBgAAAA==.',
Iu='Iudex:BAAALgAECgYJBwAAAA==.',
Ja='Jaaru:BAAALgADCggJEwAAAA==.Jaayycee:BAAALgAECgMJAwAAAA==.Jamus:BAABLgAECn85AAMTAAkJOCRDAgBYAwATAAkJOCRDAgBYAwAFAAUJwg5aiQDaAAAAAA==.Jarvy:BAAALgAECggJCAAAAA==.',
Je='Jedavon:BAAALgADCgkJLQAAAA==.Jerreden:BAAALgADCgYJBgAAAA==.Jerriden:BAAALgADCgUJCAAAAA==.',
Ji='Jiangshi:BAAALgADCgkJCQAAAA==.Jilibean:BAAALgADCgIJAgAAAA==.',
Jo='Jons:BAAALgADCgYJEQAAAA==.Joé:BAAALgADCgEJAQAAAA==.',
Ka='Kaazel:BAABLgAECn8fAAIdAAgJmwstMgCFAQAdAAgJmwstMgCFAQAAAA==.Kacee:BAAALgAECgQJBgAAAA==.Kaldor:BAAALgAECgYJEgAAAA==.Kalispo:BAAALgAECgEJAgAAAA==.Kallias:BAAALgAECgMJAwAAAA==.Karite:BAABLgAECn8lAAIgAAgJFyE+AQB8AgAgAAgJFyE+AQB8AgAAAA==.Karom:BAAALgADCgMJAwAAAA==.Karsh:BAABLgAECn8mAAIOAAgJRxkkCwA4AgAOAAgJRxkkCwA4AgAAAA==.Katyla:BAAALgADCgQJBAABLgAECggJKQAdAD0MAA==.Kazar:BAAALgADCgQJCAAAAA==.Kazenoth:BAABLgAECn8pAAMQAAgJexonDQD6AQAQAAgJexonDQD6AQAhAAEJbxHVKAAyAAAAAA==.',
Ke='Kellement:BAAALgAECgMJAwAAAA==.Ken:BAAALgAECgQJBAABLgAECggJKAAiADcYAA==.Kennychaoss:BAAALgAECggJEAAAAA==.',
Ki='Kille:BAAALgAECgUJCAAAAA==.',
Kn='Knucks:BAAALgADCgYJBgAAAA==.',
Ko='Kobeqt:BAAALgAECgEJAQAAAA==.Koomgak:BAAALgAECgIJAwAAAA==.Kosseluna:BAABLgAECn8bAAIHAAcJuAnSJQAPAQAHAAcJuAnSJQAPAQAAAA==.Kostazu:BAABLgAECn8sAAIjAAgJThAJHgBeAQAjAAgJThAJHgBeAQAAAA==.Kozanat:BAAALgADCgEJAQAAAA==.Kozzy:BAAALgADCgUJBQABLgAECgkJMQAFABcjAA==.',
Ku='Kulthulhu:BAAALgADCgcJBwABLgAECggJJwAcAGEVAA==.Kushcoma:BAAALgAECgYJCQAAAA==.',
Kv='Kvn:BAAALgADCgYJCQAAAA==.',
Ky='Kynvana:BAAALgADCgcJDQAAAA==.',
['Kí']='Kíns:BAAALgAECgEJAQAAAA==.',
La='Laity:BAABLgAECn8mAAIFAAgJvh4TEQByAgAFAAgJvh4TEQByAgAAAA==.Lanfer:BAAALgADCgcJGgAAAA==.Laraithe:BAAALgADCgEJAQAAAA==.Larethar:BAAALgADCggJBwAAAA==.Laurentos:BAAALgAECgEJAQAAAA==.Lazylaz:BAABLgAECn8oAAIVAAgJySLwAQCoAgAVAAgJySLwAQCoAgABLgAFFAYJFwAUANIaAA==.Lazyriver:BAAALgAECgcJEwAAAA==.',
Le='Lebigmu:BAABLgAECn8XAAIeAAcJHB0DBQAHAgAeAAcJHB0DBQAHAgAAAA==.Lebleb:BAAALgADCggJCQAAAA==.Leeanna:BAAALgAECgUJBwAAAA==.Lexý:BAAALgAECgEJAQAAAA==.',
Li='Lieff:BAAALgAECgUJEgAAAA==.Lifebloom:BAAALgADCgYJBgABLgAECgkJOQATADgkAA==.Lilctown:BAAALgADCgcJDQAAAA==.Liliyn:BAAALgAECgcJEAABLgAECgcJEAAGAAAAAA==.Lilsoulz:BAAALgADCgUJCQAAAA==.Lindwych:BAAALgADCgYJBgAAAA==.Lisettar:BAABLgAECn8pAAIdAAgJPQwvNgB0AQAdAAgJPQwvNgB0AQAAAA==.Livedcargox:BAAALgAECgYJBgAAAA==.',
Lo='Lockvegas:BAAALgAECgIJBAAAAA==.Lorindis:BAAALgAECgIJAwAAAA==.',
Lu='Luciferser:BAAALgAECgEJAQAAAA==.Luminara:BAAALgADCgMJAwAAAA==.Luthbruk:BAAALgADCgYJBgAAAA==.Luxsaria:BAAALgADCgcJBwAAAA==.',
Ly='Lycanbyte:BAAALgADCgkJKQAAAA==.Lylith:BAABLgAECn8kAAIXAAgJmxTBCwDFAQAXAAgJmxTBCwDFAQAAAA==.Lysanndra:BAAALgADCgUJBQAAAA==.',
['Lû']='Lûså:BAAALgAECgEJAgAAAA==.',
Ma='Madamcarnage:BAAALgADCgEJAgAAAA==.Magdalena:BAAALgAECgYJEwAAAA==.Magehawk:BAAALgADCgEJAQAAAA==.Magicboi:BAAALgAECgYJEQAAAA==.Magikos:BAAALgAECgEJAQAAAA==.Magnólia:BAABLgAECn8bAAIBAAcJniOyEwB3AgABAAcJniOyEwB3AgAAAA==.Mahito:BAAALgADCgUJBQAAAA==.Makima:BAAALgADCgcJCQABLgAECggJHQAIAMoiAA==.Manbearcat:BAAALgADCgEJAQAAAA==.Manbearpigg:BAAALgADCgEJAQAAAA==.Maribelle:BAAALgAECgEJAQABLgAECggJJwAIACQkAA==.Marrent:BAAALgADCgcJGAAAAA==.Matlen:BAAALgADCgUJBgAAAA==.Mavelana:BAAALgAECgkJBQAAAA==.Mazeltov:BAABLgAECn8WAAIJAAgJPRrJDgAcAgAJAAgJPRrJDgAcAgAAAA==.',
Me='Melomel:BAAALgAECgYJEwAAAA==.Melonsquezer:BAABLgAECn8lAAMMAAgJtBwHBwDqAQAMAAcJLh4HBwDqAQAFAAEJ2ROL/QA4AAAAAA==.Menmei:BAAALgAECgYJEwAAAA==.Mexicanrage:BAAALgADCgQJBAAAAA==.Meygen:BAAALgAECgUJBQAAAA==.',
Mi='Minbyunggyu:BAAALgAECgIJAgAAAA==.Minien:BAABLgAECn8kAAMjAAgJaxyoEwC6AQAeAAcJgRqbBgDSAQAjAAgJtReoEwC6AQAAAA==.Minko:BAABLgAECn8cAAIdAAcJ5xfeMADtAQAdAAcJ5xfeMADtAQAAAA==.Minore:BAAALgAECgcJCwAAAA==.Mishifu:BAAALgAECgQJBAABLgAECggJGAAIANQMAA==.',
Mo='Modelo:BAAALgAECgYJBgAAAA==.Monkaholic:BAAALgAECgQJBAAAAA==.Moonshot:BAABLgAECn8sAAIkAAgJuBxVAgBeAgAkAAgJuBxVAgBeAgAAAA==.Morillic:BAAALgAECgYJEQABLgAECggJEgAbADkUAA==.Mouchii:BAAALgAECgEJAQAAAA==.Mousepad:BAAALgADCgEJAQAAAA==.',
Ms='Mstrcrowly:BAABLgAECn8WAAMaAAYJkh9mKQDAAQAaAAYJ4h1mKQDAAQAlAAIJvhxiEwBWAAAAAA==.',
Mu='Mustachjones:BAABLgAECn8kAAIaAAgJZBwWIADwAQAaAAgJZBwWIADwAQAAAA==.',
My='Myros:BAABLgAECn8lAAMIAAgJdRfIMgDVAQAIAAgJdRfIMgDVAQAKAAEJ/AU7CwAzAAAAAA==.',
['Mí']='Mísfire:BAAALgAECgEJAQAAAA==.',
Na='Naakos:BAAALgADCgUJCgAAAA==.Naih:BAAALgADCgMJAwAAAA==.Nantari:BAAALgADCggJBwAAAA==.Narestor:BAABLgAECn8WAAIRAAgJBxO/MQDlAQARAAgJBxO/MQDlAQAAAA==.Navras:BAAALgADCgIJAgAAAA==.Nazurend:BAABLgAECn8WAAIIAAcJlxLvSQCKAQAIAAcJlxLvSQCKAQAAAA==.',
Nb='Nblock:BAAALgAECgQJBwAAAA==.',
Ne='Nekopunch:BAAALgAECgcJCwAAAA==.Nero:BAABLgAECn8nAAIXAAkJTyHGAQDzAgAXAAkJTyHGAQDzAgAAAA==.Nest:BAAALgADCgYJDQAAAA==.',
Ni='Nicholas:BAAALgADCgIJAgAAAA==.Nicorobin:BAABLgAECn8fAAMaAAgJNAUbfQBhAQAaAAgJNAUbfQBhAQAiAAIJywFaZgBDAAAAAA==.Nimuerose:BAAALgADCgMJAwAAAA==.',
No='Nortree:BAAALgAECgYJEgAAAA==.Nost:BAABLgAECn8lAAIFAAgJDBxpFQBOAgAFAAgJDBxpFQBOAgAAAA==.Notthatbish:BAAALgADCgYJBgAAAA==.',
Nu='Nulwyrm:BAABLgAECn8bAAIQAAcJ0xnNEgC0AQAQAAcJ0xnNEgC0AQAAAA==.',
Ny='Nyyrivik:BAAALgADCgkJDwAAAA==.',
['Nø']='Nøtrab:BAAALgADCgQJBAAAAA==.',
Oc='Octapie:BAABLgAECn8lAAIBAAgJUh4LCQCcAgABAAgJUh4LCQCcAgAAAA==.',
Oh='Ohitsadragon:BAABLgAECn8WAAIPAAYJ9RN2BwBBAQAPAAYJ9RN2BwBBAQAAAA==.',
Or='Oranur:BAAALgADCgIJAgAAAA==.Orclock:BAAALgAECgQJAQABLgAECgYJBgAGAAAAAA==.',
Ow='Owl:BAABLgAECn8fAAIlAAkJBAzzBACFAQAlAAkJBAzzBACFAQAAAA==.Owlcatraz:BAAALgAFFAEJAQAAAA==.',
Pa='Paendrag:BAAALgADCgUJBQAAAA==.Panadarama:BAACLgAFFH8KAAICAAMJzyKSEgAoAQACAAMJzyKSEgAoAQAuAAQKfyIAAgIACAkQJWkEAEUDAAIACAkQJWkEAEUDAAAA.Panteragon:BAAALgAECgYJEgAAAA==.Pasara:BAAALgADCgQJBAAAAA==.Pashene:BAAALgAECgYJCwAAAA==.',
Pe='Periwinkle:BAABLgAECn8dAAIcAAcJIxGNFwCUAQAcAAcJIxGNFwCUAQAAAA==.Persaud:BAABLgAECn8aAAMiAAkJbxjbDwDSAQAiAAcJnhLbDwDSAQAaAAUJORwsKgC8AQAAAA==.',
Ph='Phidra:BAABLgAECn8lAAMBAAgJyQ37KAB5AQABAAgJyQ37KAB5AQAjAAQJTga3agCYAAAAAA==.Philiia:BAAALgADCgQJBAAAAA==.Philionel:BAAALgADCgYJBgABLgADCgkJKQAGAAAAAA==.Phranky:BAAALgAECgEJAwABLgAECgIJAwAGAAAAAA==.',
Pi='Pixiebrew:BAAALgAECgUJCwAAAA==.',
Pl='Plutrax:BAAALgAECgIJAgAAAA==.',
Po='Pokecheck:BAAALgADCgUJBgAAAA==.',
Pr='Predatorc:BAABLgAECn8dAAIdAAkJaAoZOABtAQAdAAkJaAoZOABtAQAAAA==.Primevl:BAAALgADCgQJBAAAAA==.Primévil:BAABLgAECn8mAAIYAAgJbAoSRwAjAQAYAAgJbAoSRwAjAQAAAA==.',
Pu='Puma:BAAALgAECgYJEwAAAA==.',
['Pí']='Píp:BAAALgADCggJDQAAAA==.',
Qu='Quarz:BAAALgAECgIJAwAAAA==.Quimmi:BAAALgADCgMJAwAAAA==.',
Ra='Raediant:BAAALgAECgUJBgABLgAECggJFgACAPgLAA==.Raelek:BAAALgAECgMJAwAAAA==.Ragethecage:BAAALgADCgMJAwAAAA==.Raggaemon:BAAALgAFFAEJAQAAAA==.Ragingbanana:BAAALgAECgEJAQAAAA==.Rahmonk:BAAALgADCgEJAQAAAA==.Rahvinwulf:BAABLgAECn8dAAMRAAgJ1BufCQBOAgARAAgJ1BufCQBOAgAJAAcJrBTODQCFAQAAAA==.Raquel:BAABLgAECn8jAAIBAAkJJAtqRwBkAQABAAkJJAtqRwBkAQAAAA==.Raszageth:BAAALgADCgEJAQAAAA==.Raínbowdash:BAAALgAECgMJAwAAAA==.',
Re='Rede:BAAALgAECgIJAgAAAA==.Rein:BAABLgAECn8YAAIIAAgJ1Ax0RgCUAQAIAAgJ1Ax0RgCUAQAAAA==.Relieff:BAAALgAECgUJBQAAAA==.Relmin:BAAALgADCgcJDQAAAA==.Rennistus:BAAALgADCgYJBgAAAA==.',
Ri='Rio:BAABLgAECn8mAAIXAAgJABcaCgDnAQAXAAgJABcaCgDnAQAAAA==.Ris:BAABLgAECn8oAAIIAAkJJB9hDQCzAgAIAAkJJB9hDQCzAgAAAA==.Riseyyn:BAAALgADCgIJAgAAAA==.',
Ro='Roadzombie:BAAALgADCgMJAwAAAA==.Rockheart:BAAALgADCgQJBAAAAA==.Roknathar:BAABLgAECn8iAAIkAAgJbyUaAQDVAgAkAAgJbyUaAQDVAgAAAA==.Ronburrgandy:BAAALgAECgEJAQAAAA==.Ronilf:BAABLgAECn8WAAIfAAcJAxkIEAClAQAfAAcJAxkIEAClAQAAAA==.Rono:BAAALgADCgYJDAAAAA==.Rou:BAAALgADCgUJBQAAAA==.Rough:BAAALgADCgEJAQAAAA==.Royda:BAABLgAECn8oAAMbAAkJUBxtBgBwAgAbAAkJUBxtBgBwAgAcAAIJyhN3iAAnAAAAAA==.',
Ru='Ruitiny:BAAALgADCgkJEAAAAA==.Rukaza:BAAALgAECgEJAQABLgAFFAIJBQAYALMeAA==.',
Ry='Rygard:BAAALgADCgQJBAAAAA==.',
Sa='Saerenity:BAAALgAECgMJAwAAAA==.Saintlucky:BAAALgADCgYJBgAAAA==.Saintvonzeal:BAAALgADCggJFQAAAA==.Sana:BAABLgAECn8kAAIjAAgJyR0oCQBIAgAjAAgJyR0oCQBIAgAAAA==.Saphihr:BAAALgADCgYJBgAAAA==.Saxmaster:BAAALgAECgMJAwAAAA==.Sazerac:BAAALgAECgUJEwAAAA==.',
Sc='Scaly:BAAALgAECgEJAQABLgAECgQJBQAGAAAAAA==.',
Se='Sedo:BAAALgAECgEJAQAAAA==.Selenis:BAAALgAECgEJAwABLgAECggJIgAUABojAA==.',
Sg='Sgtshamrock:BAAALgADCgIJAgAAAA==.',
Sh='Shadowlady:BAAALgAECgEJAQAAAA==.Shadowrealms:BAAALgADCgYJCAAAAA==.Shamainiac:BAABLgAECn8sAAIjAAgJ0RRiGACNAQAjAAgJ0RRiGACNAQAAAA==.Shaomai:BAABLgAECn8kAAMjAAgJESFvBQCYAgAjAAgJESFvBQCYAgABAAQJLw0RcwDDAAAAAA==.Sharper:BAABLgAECn8XAAIYAAcJhhuYIADFAQAYAAcJhhuYIADFAQABLgAFFAMJBwAUACkcAA==.Shep:BAAALgAECgMJAwAAAA==.Sherra:BAAALgADCgIJAgAAAA==.Shiok:BAAALgADCggJFwAAAA==.Shoknorris:BAAALgADCgkJCQAAAA==.Shâde:BAAALgAECgQJBgAAAA==.',
Si='Siirius:BAAALgAECgQJCAAAAA==.Silverwin:BAAALgAECgYJEwAAAA==.',
Sk='Skribbles:BAAALgADCgQJBAAAAA==.',
Sl='Slimage:BAABLgAECn8cAAImAAkJAxj3AABkAgAmAAkJAxj3AABkAgAAAA==.Slushius:BAAALgAECgEJAQAAAA==.',
Sm='Smite:BAAALgAECgQJCgAAAA==.Smitted:BAAALgAECgYJEQAAAA==.Smitty:BAAALgAECggJDQAAAA==.',
So='Socharis:BAAALgADCgMJAwAAAA==.Sodapops:BAAALgAECgQJBQAAAA==.Sophiaa:BAAALgADCgcJBgAAAA==.Sorn:BAABLgAECn8VAAIMAAcJjRL2DQBZAQAMAAcJjRL2DQBZAQAAAA==.',
Sp='Spaarkle:BAAALgAECgYJBwAAAA==.Specialheist:BAAALgAECgkJCgAAAA==.Spectrehawk:BAAALgAECgYJBgABLgAFFAQJCAADADIKAA==.Speçtre:BAACLgAFFH8IAAIDAAQJMgqaEADlAAADAAQJMgqaEADlAAAuAAQKfx8AAwMACQk9FcoSAOABAAMACAlFF8oSAOABABQAAQkDBz/aAEEAAAAA.Spins:BAAALgAECgEJAQAAAA==.',
Sr='Srankhunter:BAAALgAECgEJAQAAAA==.',
St='Stallord:BAAALgADCgYJDAAAAA==.Steppin:BAABLgAECn8SAAIbAAgJORTHDgDgAQAbAAgJORTHDgDgAQAAAA==.Stormglaive:BAABLgAECn8aAAMXAAcJPhU5HQDWAQAXAAcJPhU5HQDWAQAYAAEJTwPh6QAoAAAAAA==.Stupidity:BAABLgAECn8kAAMbAAgJWBrPEADGAQAbAAYJiCDPEADGAQAcAAIJhBdAOgCIAAAAAA==.',
Su='Suldrick:BAAALgADCgkJEAAAAA==.Suppabad:BAABLgAECn8lAAMOAAgJeyBFBADgAgAOAAgJeyBFBADgAgAnAAQJTRGnLQDRAAAAAA==.Suzäku:BAAALgADCgkJCQAAAA==.',
['Sá']='Sákura:BAAALgAECgIJBAAAAA==.',
Ta='Taara:BAAALgADCgUJBQABLgAECggJJwAIACQkAA==.Tarysha:BAAALgAECgcJDQAAAA==.Tatertotz:BAAALgAECgUJCQAAAA==.Taynav:BAABLgAECn8kAAIoAAgJzhKgDABFAQAoAAgJzhKgDABFAQAAAA==.Tayoma:BAAALgAECgEJAQAAAA==.Tazara:BAAALgAECgEJAQAAAA==.',
Te='Tealth:BAAALgAECgYJBgAAAA==.Ted:BAABLgAECn8XAAIjAAYJdhS8IwA2AQAjAAYJdhS8IwA2AQAAAA==.Tehgrimza:BAABLgAECn8dAAMaAAgJOhMmMQCfAQAaAAgJOhMmMQCfAQAiAAEJrxB4dAAwAAAAAA==.Teias:BAAALgAECgIJAgABLgAFFAIJBQAcAOEdAA==.Teka:BAAALgADCgMJAwAAAA==.Temu:BAAALgAECgYJCAABLgAECggJHQAIAMoiAA==.Tet:BAAALgADCgMJAwAAAA==.Tevia:BAABLgAECn8tAAIpAAkJ4hhwAwBsAgApAAkJ4hhwAwBsAgAAAA==.',
Th='Thalip:BAAALgAECgQJBgAAAA==.Thokmay:BAABLgAECn8hAAInAAgJIg8hGgBSAQAnAAgJIg8hGgBSAQAAAA==.Thorel:BAAALgAECgQJBAAAAA==.Thornar:BAAALgADCgQJBAAAAA==.Thunden:BAAALgAECgEJAQAAAA==.',
Ti='Tiandrinna:BAABLgAECn8eAAIKAAgJjBxKAQAOAgAKAAgJjBxKAQAOAgAAAA==.Tightywhitey:BAAALgAECgYJBwAAAA==.Timkaoss:BAABLgAECn8WAAMLAAYJtxRvUABkAQALAAYJtxRvUABkAQAHAAMJOQcDSgBZAAAAAA==.Timmyjudge:BAAALgAECgEJAgAAAA==.Tinyspoon:BAAALgADCgMJAwAAAA==.',
Tm='Tmagnet:BAAALgAECgYJEwAAAA==.',
To='Tooshie:BAAALgADCgcJBwAAAA==.Tormin:BAAALgADCgkJFgAAAA==.Torrente:BAAALgADCgEJAQAAAA==.Tourmaline:BAAALgAECgEJAgABLgAECgcJGwABAJ4jAA==.',
Tr='Treebud:BAAALgADCgkJDAAAAA==.Tritherelyn:BAAALgADCgcJBwAAAA==.Trixterwolf:BAAALgADCgUJBwAAAA==.',
Ts='Tserendolgor:BAAALgADCggJDwAAAA==.',
Tw='Tweedildee:BAABLgAECn8oAAIIAAkJ+hYdHgA1AgAIAAkJ+hYdHgA1AgAAAA==.',
Ty='Tygrassar:BAAALgAECgIJAgAAAA==.',
['Tà']='Tàttersail:BAABLgAECn8gAAIcAAgJvhr/CABdAgAcAAgJvhr/CABdAgAAAA==.',
['Tä']='Täd:BAAALgAECgQJBAAAAA==.',
Va='Vaelena:BAAALgADCgMJAwAAAA==.Vahldr:BAAALgAECgQJBQAAAA==.Valdor:BAAALgAECgYJCwAAAA==.Valeeras:BAAALgADCgUJBQAAAA==.Valeron:BAAALgAECgcJEgAAAA==.Valicous:BAAALgADCgkJJgAAAA==.Valyerian:BAABLgAECn8uAAIRAAgJ5hsMFgCcAgARAAgJ5hsMFgCcAgAAAA==.Vandalie:BAAALgAECgEJAQABLgAECgkJHgAUAGMiAA==.Vandevoker:BAAALgAECgQJCAABLgAECgkJHgAUAGMiAA==.Vanserra:BAAALgADCgcJEAAAAA==.Varregory:BAAALgADCgQJBAAAAA==.Vaxas:BAABLgAECn8eAAIFAAgJnBwcFgBKAgAFAAgJnBwcFgBKAgAAAA==.Vaxasus:BAAALgADCgEJAQAAAA==.Vaylorian:BAAALgAECgYJDAAAAA==.Vaült:BAABLgAECn8dAAMTAAgJ+ha8DwAiAgATAAgJ+ha8DwAiAgAFAAMJPwYYEgFzAAAAAA==.',
Ve='Verianna:BAABLgAECn8iAAMUAAgJGiOiGgArAgAUAAcJpCGiGgArAgADAAIJcCaFHADfAAAAAA==.Vexmorphis:BAAALgADCgUJBQABLgAECgEJAQAGAAAAAA==.Vexxis:BAAALgADCgMJAwAAAA==.',
Vi='Vitani:BAAALgAECgEJAQAAAA==.',
Vo='Vodkâshots:BAAALgAECgkJBgAAAA==.Votary:BAAALgAECgQJBAAAAA==.',
Vt='Vtown:BAAALgADCgYJFQAAAA==.',
Wa='Wadumu:BAABLgAECn8dAAMLAAcJhAwJaQAYAQALAAYJVg4JaQAYAQAoAAcJIQybEgDfAAAAAA==.Wagwanmist:BAABLgAECn8lAAIOAAgJtBlRCgBHAgAOAAgJtBlRCgBHAgAAAA==.Wardrago:BAAALgADCgcJCAAAAA==.Warvegas:BAAALgAECgMJAwAAAA==.Warwulf:BAAALgAECgQJBAABLgAECggJHQARANQbAA==.Water:BAAALgADCgEJAQAAAA==.',
Wi='Willowy:BAABLgAECn8nAAIIAAgJJCQ0CwDJAgAIAAgJJCQ0CwDJAgAAAA==.',
['Wâ']='Wâlmi:BAABLgAECn8ZAAQBAAUJdQ6QVQCoAAABAAUJdQ6QVQCoAAAjAAQJzAdTaACiAAAeAAEJngodHwA4AAAAAA==.',
Xa='Xaerius:BAABLgAECn8lAAMRAAgJWxOQFgCzAQARAAgJyRKQFgCzAQApAAEJ6wXKQQArAAAAAA==.Xalatath:BAAALgADCgcJDQAAAA==.Xan:BAABLgAECn8gAAIIAAkJyReBIQAjAgAIAAkJyReBIQAjAgAAAA==.Xann:BAAALgADCgYJBgAAAA==.Xannen:BAAALgADCgkJCQAAAA==.Xantharr:BAAALgADCgMJAwAAAA==.Xantyr:BAAALgADCgYJBgAAAA==.Xashae:BAAALgADCgcJDwAAAA==.',
Xe='Xenocidal:BAABLgAECn8YAAIIAAcJJiNCPQCDAgAIAAcJJiNCPQCDAgAAAA==.',
Xo='Xog:BAAALgAECgIJAgAAAA==.',
Ya='Yarman:BAAALgAECgYJEwAAAA==.',
Ye='Yeaforpie:BAAALgAECgYJEgAAAA==.Yervant:BAAALgAECgQJBAAAAA==.Yesthatbish:BAAALgAECgcJDwAAAA==.',
Yo='Yoshial:BAAALgADCgkJKQAAAA==.',
Za='Zadoc:BAAALgADCgcJGwAAAA==.Zano:BAABLgAECn8iAAMbAAgJlBItHgDoAQAbAAgJlBItHgDoAQASAAYJjgzRJQD6AAAAAA==.',
Ze='Zealins:BAAALgADCgUJCAAAAA==.Zenrek:BAAALgADCgEJAQAAAA==.Zenrekt:BAAALgADCgMJBAAAAA==.Zeuhl:BAAALgAECgcJCwAAAA==.',
Zi='Zilver:BAAALgADCgEJAQABLgAFFAMJBgAFAJEXAA==.Ziv:BAABLgAECn8tAAILAAkJKiAxBAAjAwALAAkJKiAxBAAjAwABLgAECgcJEAAGAAAAAA==.Ziyn:BAAALgAECgcJEAAAAA==.',
['Ôa']='Ôath:BAAALgAECgEJAQAAAA==.',
['Ÿe']='Ÿeñnefer:BAAALgADCgEJAQAAAA==.',
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

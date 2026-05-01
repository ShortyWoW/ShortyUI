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

local lookup = {'Shaman-Restoration','Monk-Brewmaster','DeathKnight-Blood','DeathKnight-Frost','Paladin-Retribution','Unknown-Unknown','Druid-Balance','Mage-Frost','Warrior-Protection','Mage-Fire','Druid-Restoration','Paladin-Protection','Rogue-Assassination','Monk-Mistweaver','Evoker-Devastation','Evoker-Augmentation','Warrior-Fury','Priest-Discipline','DeathKnight-Unholy','Druid-Feral','Hunter-Survival','Paladin-Holy','Priest-Shadow','Priest-Holy','Hunter-BeastMastery','Warlock-Demonology','Rogue-Outlaw','Evoker-Preservation','Shaman-Elemental','DemonHunter-Havoc','Shaman-Enhancement','Hunter-Marksmanship','Warlock-Destruction','Warlock-Affliction','DemonHunter-Devourer','DemonHunter-Vengeance','Mage-Arcane','Monk-Windwalker','Druid-Guardian','Warrior-Arms',}
local provider = {region='US',realm='Draenor',name='US',type='weekly',zone=46,date='2026-05-01',data={Ac='Achiella:BAAALgADCgIJAgAAAA==.',
Ad='Advisor:BAACLgAFFH8GAAIBAAQJjhBmDgAdAQABAAQJjhBmDgAdAQAuAAQKfyEAAgEACAl2Im0JAOECAAEACAl2Im0JAOECAAAA.',
Ae='Aería:BAAALgAECgUJCwAAAA==.',
Ah='Ahnkho:BAAALgAECgEJAQAAAA==.',
Ai='Ailea:BAAALgADCgcJFQAAAA==.Aindie:BAAALgADCgEJAQAAAA==.',
Ak='Akarm:BAAALgADCgcJBwAAAA==.',
Al='Alcomancer:BAAALgADCgIJAgAAAA==.Aleks:BAAALgAECgQJBAAAAA==.Aluna:BAAALgAECgcJEAAAAA==.Alvarr:BAAALgADCgYJCQAAAA==.',
Am='Amalia:BAAALgADCgEJAQAAAA==.Amandakk:BAAALgADCgkJHAAAAA==.Aminas:BAAALgAECgEJAQAAAA==.',
An='Annya:BAAALgAECgYJBgAAAA==.Antheria:BAAALgADCgMJAwAAAA==.',
Ap='Aphrodite:BAAALgAECgYJEAAAAA==.',
Ar='Archie:BAAALgAECgQJBgAAAA==.Arendt:BAAALgADCgQJCgAAAA==.Arkahera:BAAALgAECgQJBAABLgAFFAMJCgACAM8iAA==.Arolder:BAABLgAECn8cAAMDAAgJPCCXAwAXAgAEAAcJIR3cAwA7AgADAAgJdh+XAwAXAgAAAA==.Arturium:BAAALgADCgYJCQAAAA==.',
At='Atabey:BAABLgAECn8pAAIFAAgJeB1SDQBZAgAFAAgJeB1SDQBZAgABLgABCgMJAwAGAAAAAA==.Atimusk:BAAALgADCggJDwAAAA==.Atoadaso:BAAALgAECgQJBAAAAA==.Attretes:BAAALgADCgcJCQAAAA==.',
Az='Azcowboy:BAAALgAECgIJBQAAAA==.Azezel:BAAALgADCgYJBgAAAA==.Aznå:BAAALgADCgQJBAAAAA==.',
Ba='Balacheck:BAAALgAECgUJDQAAAA==.Bang:BAAALgADCgEJAQAAAA==.Barecub:BAAALgADCgQJCgAAAA==.Barton:BAAALgADCgcJCQAAAA==.Baultenaz:BAAALgADCgQJBAAAAA==.',
Bb='Bbite:BAABLgAECn8ZAAIHAAcJihmiDgClAQAHAAcJihmiDgClAQAAAA==.',
Be='Beanwater:BAAALgAECgMJAwAAAA==.Belmax:BAAALgADCgQJCgAAAA==.Bemon:BAAALgADCgcJBwABLgAECgcJFAAIAKAcAA==.',
Bi='Bigbadwoof:BAAALgADCgYJGQAAAA==.Bighog:BAABLgAFFH8JAAIJAAQJChx5AwBlAQAJAAQJChx5AwBlAQAAAA==.',
Bl='Blaazzin:BAAALgADCgYJCAAAAA==.Blessa:BAAALgADCgkJCQAAAA==.Bloomzy:BAABLgAECn8aAAMIAAgJCBWLOACFAQAIAAgJMRCLOACFAQAKAAIJehtaCgCfAAAAAA==.Blytzbrigade:BAAALgADCgkJDQAAAA==.',
Bo='Boneycheese:BAAALgADCgYJCgAAAA==.Boombástic:BAABLgAECn8dAAMHAAgJ/g9hGAA7AQAHAAYJVhJhGAA7AQALAAIJzg/MWQBsAAAAAA==.Boomco:BAAALgAECgIJAgAAAA==.Bors:BAAALgADCgQJBwAAAA==.Boulderholdr:BAAALgADCgcJDgAAAA==.Boxing:BAAALgADCgIJAgAAAA==.',
Br='Breaddy:BAAALgAECgYJCwAAAA==.Breeti:BAAALgAECgUJCwAAAA==.Broin:BAAALgAECgEJAQAAAA==.Bronte:BAABLgAECn8cAAIMAAkJxRmcCgAkAgAMAAkJxRmcCgAkAgAAAA==.Bryda:BAAALgADCgcJEAAAAA==.',
Bu='Bubblez:BAAALgADCgYJCQAAAA==.Burblingbee:BAAALgADCgcJBwAAAA==.',
Bw='Bwucewee:BAAALgADCgcJCAAAAA==.',
Ca='Cajbo:BAABLgAECn8ZAAINAAYJKR2QBACNAQANAAYJKR2QBACNAQAAAA==.Calyssa:BAABLgAECn8XAAIFAAcJvwuYUQAZAQAFAAcJvwuYUQAZAQAAAA==.Candyflöss:BAAALgAFFAEJAQAAAA==.Carpe:BAAALgAECgYJBgAAAA==.Cartan:BAABLgAECn8lAAIOAAkJvRpLAwDDAgAOAAkJvRpLAwDDAgAAAA==.Cathelina:BAAALgADCggJDwAAAA==.Cathom:BAAALgAECgQJBwAAAA==.',
Ch='Charizaard:BAAALgADCggJDAAAAA==.Charizaardx:BAABLgAECn8qAAMPAAgJpRZqAwCzAQAPAAgJchJqAwCzAQAQAAYJvhbwJQCNAQAAAA==.Chevytron:BAAALgAECgYJEQAAAA==.Chune:BAAALgADCgcJDAAAAA==.',
Ci='Cinder:BAAALgADCgIJAgAAAA==.',
Cl='Clement:BAAALgAECgQJBAAAAA==.Cletus:BAABLgAECn8UAAMRAAYJYA/lJAAVAQARAAYJYA/lJAAVAQAJAAEJLgcISQAsAAAAAA==.Clément:BAAALgADCgUJBQAAAA==.',
Co='Coffeebeans:BAABLgAECn8eAAMLAAgJExblPgCnAQALAAcJfxTlPgCnAQAHAAgJSwq6FABdAQAAAA==.Cowabunga:BAAALgADCgIJAgAAAA==.Cowkiller:BAAALgADCgEJAQAAAA==.',
Cr='Crazyasian:BAAALgAECgYJCgAAAA==.Crogan:BAAALgAECgYJBwAAAA==.',
Ct='Ctrlaltdk:BAAALgAECgEJAQABLgAECgEJAgAGAAAAAA==.',
Cy='Cybrocookie:BAAALgADCgEJAQAAAA==.Cyrberus:BAAALgAECgUJBwAAAA==.',
['Cá']='Cáposhady:BAAALgAECgEJAQAAAA==.',
Da='Dagda:BAAALgADCgMJAwAAAA==.Dalna:BAABLgAECn8WAAIOAAYJ1RCVGQA5AQAOAAYJ1RCVGQA5AQAAAA==.Danilex:BAABLgAECn8XAAIIAAcJHh9uSABeAgAIAAcJHh9uSABeAgABLgAFFAYJGQASALgSAA==.Danksoul:BAAALgADCgUJBQABLgAECgUJBQAGAAAAAA==.Darcorin:BAABLgAECn8eAAITAAcJcBaVLACJAQATAAcJcBaVLACJAQAAAA==.Darkblitz:BAAALgADCgQJBQAAAA==.Darklürker:BAAALgAECgQJCQAAAA==.Darksaber:BAAALgADCgcJEQAAAA==.Dasthodan:BAAALgADCgcJDQAAAA==.Dayne:BAAALgAECgUJBgAAAA==.',
Dc='Dctrpepper:BAAALgADCggJHwAAAA==.',
De='Deathcore:BAAALgADCgUJBQAAAA==.Deathminions:BAAALgADCgUJBQAAAA==.Deathwish:BAAALgADCgIJAgAAAA==.Decklan:BAAALgADCgEJAQAAAA==.Decorum:BAAALgADCgEJAQAAAA==.Defiant:BAAALgADCgEJAQAAAA==.Deilliann:BAABLgAECn8fAAQLAAgJxQV0OgDpAAALAAgJxQV0OgDpAAAHAAYJkwJLLwCaAAAUAAIJhQCFOgAdAAAAAA==.Deldawalth:BAAALgADCgcJEgAAAA==.Demonica:BAAALgAECgYJDgAAAA==.Demonky:BAAALgAECgIJAgAAAA==.Demonology:BAAALgADCgYJBwAAAA==.Demonspecial:BAAALgAECgkJBwAAAA==.Denastus:BAAALgADCgEJAQAAAA==.Devick:BAAALgADCgkJCQAAAA==.',
Di='Dinta:BAABLgAECn8tAAIFAAkJBxlTMgBZAgAFAAkJBxlTMgBZAgAAAA==.Dip:BAAALgADCgcJBwAAAA==.',
Dj='Djabuty:BAAALgAECgEJAgAAAA==.',
Do='Dominoes:BAAALgAECgIJAgAAAA==.Domìnion:BAAALgADCgkJEAAAAA==.Dorcater:BAAALgADCgEJAQAAAA==.',
Dr='Dradmaster:BAAALgADCgYJBgAAAA==.Drakth:BAAALgADCgIJAQAAAA==.Drekker:BAABLgAECn8VAAICAAgJ8wsoTQAOAQACAAgJ8wsoTQAOAQAAAA==.Drhofmann:BAAALgAECgMJCQAAAA==.',
Du='Duffar:BAABLgAECn8VAAIVAAcJEQmwEABVAQAVAAcJEQmwEABVAQAAAA==.Dummblond:BAAALgAECgcJDwAAAA==.Dumptruck:BAAALgAECgYJCQAAAA==.Durgledore:BAAALgAECgcJEQAAAA==.',
Dy='Dysfunction:BAAALgADCgkJCQAAAA==.',
Ea='Earthshield:BAAALgAECgYJDQABLgAECgkJNwAWANojAA==.',
Eg='Ego:BAAALgAECgYJDgAAAA==.',
El='Elipto:BAAALgADCgcJGQAAAA==.Ellaana:BAAALgAECgMJBQAAAA==.Elotarra:BAAALgADCgQJCgAAAA==.Elowentinsel:BAAALgADCgkJIwAAAA==.Elsiais:BAAALgADCgUJCwAAAA==.Elvarang:BAAALgADCgYJCQAAAA==.',
En='Enduran:BAAALgAECgMJAwAAAA==.',
Er='Erasi:BAABLgAECn8cAAMXAAcJhggEGwAlAQAXAAcJhggEGwAlAQAYAAEJWgfuhgApAAAAAA==.',
Es='Es:BAABLgAECn8UAAITAAcJ8gTApgA0AQATAAcJ8gTApgA0AQAAAA==.Escanorlion:BAAALgADCgQJBAAAAA==.Esttsumi:BAAALgAECggJCAAAAA==.',
Eu='Euphia:BAAALgAECgQJCgAAAA==.',
Ex='Exiled:BAAALgADCgYJCQAAAA==.Exine:BAABLgAECn8bAAIZAAgJphEZJwB8AQAZAAgJphEZJwB8AQAAAA==.Exodiá:BAAALgADCgMJAwAAAA==.',
Ey='Eyebee:BAAALgADCgEJAQAAAA==.',
Fa='Faeonia:BAABLgAECn8VAAIFAAYJZxw3OABjAQAFAAYJZxw3OABjAQAAAA==.Faethe:BAAALgADCgMJAwABLgAECggJIAAIAB0kAA==.Farawaystare:BAAALgAECgQJBAAAAA==.Farwolf:BAAALgAECgYJEQAAAA==.Fayore:BAAALgADCgcJBwAAAA==.',
Fe='Fearmaxxing:BAAALgAECgUJBQAAAA==.Fee:BAABLgAECn8nAAIFAAgJEx5xIQCkAgAFAAgJEx5xIQCkAgAAAA==.Fellyn:BAAALgADCgYJBwAAAA==.Feloniusmunk:BAAALgADCgQJCgAAAA==.Fenrith:BAAALgADCgIJAgAAAA==.Feyt:BAAALgADCgMJAwAAAA==.',
Fi='Fidelis:BAAALgADCgYJBgAAAA==.Figaro:BAAALgAECgcJEwAAAA==.Filthy:BAAALgAECgQJBQAAAA==.',
Fl='Flameheart:BAAALgAECgYJBgAAAA==.Fleathulhu:BAABLgAECn8nAAIYAAgJYRX/CwDkAQAYAAgJYRX/CwDkAQAAAA==.Flungpu:BAAALgADCgkJDgABLgAECgcJGwAZAG8MAA==.',
Fo='Foleigh:BAAALgADCggJCwAAAA==.Fostock:BAAALgAECgUJDQAAAA==.Foxieshoxie:BAAALgAECgEJAQAAAA==.',
Fr='Frontierland:BAAALgADCgcJDQAAAA==.Frostmoon:BAAALgADCgIJAgAAAA==.Frozty:BAAALgADCggJCAAAAA==.',
Fu='Fuzzie:BAAALgADCgYJBAAAAA==.',
Ga='Gankuskhan:BAAALgAECgQJBAAAAA==.Ganlolf:BAAALgAECgQJBAABLgAECgQJBQAGAAAAAA==.Ganook:BAAALgADCgkJCgAAAA==.Garwynn:BAABLgAECn8kAAINAAgJ5xM/AwDHAQANAAgJ5xM/AwDHAQAAAA==.',
Gh='Ghoulmaxing:BAAALgAECgEJAgAAAA==.',
Gi='Gimper:BAAALgADCgcJFAAAAA==.',
Gl='Glaistia:BAAALgADCgEJAQAAAA==.Glen:BAAALgAECgMJBQAAAA==.',
Go='Goldengraham:BAAALgADCgcJCQAAAA==.Gorgutz:BAAALgADCgEJAQAAAA==.',
Gr='Graeman:BAAALgADCgMJAwAAAA==.Greatpàw:BAAALgADCgUJBAAAAA==.',
Gw='Gwyn:BAAALgADCgQJBAAAAA==.',
['Gæ']='Gætherr:BAAALgAECgQJBQAAAA==.',
Ha='Habbyb:BAAALgAECgEJAQAAAA==.Habbypallie:BAAALgADCgUJCQAAAA==.Haimanist:BAABLgAECn8ZAAIMAAgJjSAlAwDwAgAMAAgJjSAlAwDwAgABLgAFFAMJCgACAM8iAA==.Halixan:BAAALgAECgYJEgAAAA==.Handlebardoc:BAACLgAFFH8FAAITAAIJvhtuTgCpAAATAAIJvhtuTgCpAAAuAAQKfygAAhMABwmzHzkjALYBABMABwmzHzkjALYBAAAA.Harmoni:BAAALgADCgEJAQABLgAECggJIAAIAB0kAA==.',
He='Healmemommy:BAAALgAECgYJCgAAAA==.Healsrus:BAAALgADCgQJBAAAAA==.Healze:BAAALgADCgUJBgAAAA==.Hemorrvoid:BAAALgAECgMJBQAAAA==.Heyei:BAAALgAECgUJBgAAAA==.',
Hi='Highroller:BAAALgADCgQJBgAAAA==.',
Ho='Holyname:BAAALgADCgIJAgAAAA==.',
Hy='Hydrozortek:BAAALgAECgEJAQAAAA==.',
Ia='Iamlegend:BAAALgADCgcJBwAAAA==.',
Ib='Iblis:BAAALgADCgcJEgAAAA==.',
Ig='Ignivoid:BAAALgADCggJCAAAAA==.',
Ij='Ijillien:BAAALgAECgEJAQAAAA==.',
Im='Imahaa:BAAALgADCgMJAwAAAA==.Imonster:BAABLgAECn8fAAIaAAgJhghrNQBVAQAaAAgJhghrNQBVAQAAAA==.',
Ir='Ironfizt:BAAALgAECgcJDgABLgAECgYJEQAGAAAAAA==.',
It='Itsgotime:BAAALgAECgMJBgAAAA==.',
Iu='Iudex:BAAALgAECgYJBwAAAA==.',
Ja='Jaaru:BAAALgADCggJEwAAAA==.Jaayycee:BAAALgAECgMJAwAAAA==.Jamus:BAABLgAECn83AAMWAAkJ2iNEAgBYAwAWAAkJ2iNEAgBYAwAFAAQJ3Q16hACjAAAAAA==.Jarvy:BAAALgAECgYJBgAAAA==.',
Je='Jedavon:BAAALgADCgkJJAAAAA==.Jerriden:BAAALgADCgUJCAAAAA==.',
Ji='Jilibean:BAAALgADCgIJAgAAAA==.',
Jo='Jons:BAAALgADCgYJEQAAAA==.Joé:BAAALgADCgEJAQAAAA==.',
Ka='Kaazel:BAABLgAECn8bAAIZAAcJbwz3LABeAQAZAAcJbwz3LABeAQAAAA==.Kacee:BAAALgAECgQJBgAAAA==.Kaldor:BAAALgAECgUJDAAAAA==.Kalispo:BAAALgAECgEJAgAAAA==.Kallias:BAAALgADCggJFQAAAA==.Karite:BAABLgAECn8gAAIbAAgJ5R0aAQBJAgAbAAgJ5R0aAQBJAgAAAA==.Karom:BAAALgADCgMJAwAAAA==.Karsh:BAABLgAECn8mAAIOAAgJRxl5BwBDAgAOAAgJRxl5BwBDAgAAAA==.Katyla:BAAALgADCgQJBAABLgAECggJIQAZAJoKAA==.Kazar:BAAALgADCgQJCAAAAA==.Kazenoth:BAABLgAECn8kAAMQAAgJphmNCQDyAQAQAAgJphmNCQDyAQAcAAEJcRGBIQAzAAAAAA==.',
Ke='Kellement:BAAALgAECgMJAwAAAA==.Ken:BAAALgADCgkJLwAAAA==.Kennychaoss:BAAALgAECggJCAAAAA==.',
Ki='Kille:BAAALgAECgMJAwAAAA==.',
Kn='Knucks:BAAALgADCgYJBgAAAA==.',
Ko='Koomgak:BAAALgAECgIJAwAAAA==.Kosseluna:BAABLgAECn8UAAIHAAYJ4wh5IwDlAAAHAAYJ4wh5IwDlAAAAAA==.Kostazu:BAABLgAECn8kAAIdAAgJ5A/yFwBTAQAdAAgJ5A/yFwBTAQAAAA==.Kozanat:BAAALgADCgEJAQAAAA==.Kozzy:BAAALgADCgUJBQABLgAECggJJwAFABMeAA==.',
Ku='Kulthulhu:BAAALgADCgcJBwABLgAECggJJwAYAGEVAA==.Kushcoma:BAAALgAECgYJCQAAAA==.',
Kv='Kvn:BAAALgADCgYJCQAAAA==.',
Ky='Kynvana:BAAALgADCgcJDQAAAA==.',
['Kí']='Kíns:BAAALgAECgEJAQAAAA==.',
La='Laity:BAABLgAECn8eAAIFAAgJSR0SDQBbAgAFAAgJSR0SDQBbAgAAAA==.Lanfer:BAAALgADCgcJGgAAAA==.Larethar:BAAALgADCggJBwAAAA==.Laurentos:BAAALgADCgkJFAAAAA==.Lazylaz:BAABLgAECn8gAAIUAAgJkiJqAQCRAgAUAAgJkiJqAQCRAgABLgAFFAYJEgATAMEZAA==.Lazyriver:BAAALgAECgcJEwAAAA==.',
Le='Lebigmu:BAAALgAECgUJEQAAAA==.Lebleb:BAAALgADCggJCQAAAA==.Leeanna:BAAALgAECgUJBwAAAA==.Lexý:BAAALgAECgEJAQAAAA==.',
Li='Lieff:BAAALgAECgUJDQAAAA==.Lilctown:BAAALgADCgcJDQAAAA==.Liliyn:BAAALgAECgcJEAABLgAECgcJCAAGAAAAAA==.Lilsoulz:BAAALgADCgUJCQAAAA==.Lindwych:BAAALgADCgYJBgAAAA==.Lisettar:BAABLgAECn8hAAIZAAgJmgq2LABfAQAZAAgJmgq2LABfAQAAAA==.Livedcargox:BAAALgADCgMJAwAAAA==.',
Lo='Lockvegas:BAAALgAECgIJBAAAAA==.Lorindis:BAAALgAECgIJAwAAAA==.',
Lu='Luciferser:BAAALgAECgEJAQAAAA==.Luminara:BAAALgADCgMJAwAAAA==.Luthbruk:BAAALgADCgYJBgAAAA==.Luxsaria:BAAALgADCgcJBwAAAA==.',
Ly='Lycanbyte:BAAALgADCgkJIAAAAA==.Lylith:BAABLgAECn8fAAIeAAgJsxF7CgCXAQAeAAgJsxF7CgCXAQAAAA==.Lysanndra:BAAALgADCgUJBQAAAA==.',
['Lû']='Lûså:BAAALgAECgEJAgAAAA==.',
Ma='Madamcarnage:BAAALgADCgEJAgAAAA==.Magdalena:BAAALgAECgYJEwAAAA==.Magicboi:BAAALgAECgYJEQAAAA==.Magikos:BAAALgAECgEJAQAAAA==.Magnólia:BAABLgAECn8UAAIBAAYJlSW2EwB3AgABAAYJlSW2EwB3AgAAAA==.Mahito:BAAALgADCgUJBQAAAA==.Makima:BAAALgADCgcJCQABLgAECgUJBgAGAAAAAA==.Manbearcat:BAAALgADCgEJAQAAAA==.Manbearpigg:BAAALgADCgEJAQAAAA==.Maribelle:BAAALgAECgEJAQABLgAECggJIAAIAB0kAA==.Marrent:BAAALgADCgcJGAAAAA==.Matlen:BAAALgADCgUJBgAAAA==.Mavelana:BAAALgAECgkJBQAAAA==.Mazeltov:BAABLgAECn8WAAIJAAgJPRrKDgAcAgAJAAgJPRrKDgAcAgAAAA==.',
Me='Melomel:BAAALgAECgUJDQAAAA==.Melonsquezer:BAABLgAECn8gAAMMAAgJJRwnBQDoAQAMAAcJhx0nBQDoAQAFAAEJ2RPfMwE9AAAAAA==.Menmei:BAAALgAECgUJDQAAAA==.Meygen:BAAALgAECgUJBQAAAA==.',
Mi='Minbyunggyu:BAAALgADCggJCAAAAA==.Minien:BAABLgAECn8eAAMfAAcJgBpiBADpAQAfAAcJgBpiBADpAQAdAAYJEBNYPABbAQAAAA==.Minko:BAABLgAECn8cAAIZAAcJ5xcgHgCrAQAZAAcJ5xcgHgCrAQAAAA==.Minore:BAAALgAECgcJCwAAAA==.Mishifu:BAAALgAECgQJBAABLgAECgYJDgAGAAAAAA==.',
Mo='Modelo:BAAALgAECgYJBgAAAA==.Monkaholic:BAAALgAECgQJBAAAAA==.Moonshot:BAABLgAECn8kAAIgAAgJDxXcBAC3AQAgAAgJDxXcBAC3AQAAAA==.Morillic:BAAALgAECgYJEQABLgAECgcJDgAGAAAAAA==.Mouchii:BAAALgAECgEJAQAAAA==.Mousepad:BAAALgADCgEJAQAAAA==.',
Ms='Mstrcrowly:BAAALgAECgYJEAAAAA==.',
Mu='Mustachjones:BAABLgAECn8cAAIaAAcJJx3EMwA9AgAaAAcJJx3EMwA9AgAAAA==.',
My='Myros:BAABLgAECn8gAAMIAAgJ3RaKJwDHAQAIAAgJ3RaKJwDHAQAKAAEJ/AW/CAA1AAAAAA==.',
['Mí']='Mísfire:BAAALgAECgEJAQAAAA==.',
Na='Naakos:BAAALgADCgUJCgAAAA==.Naih:BAAALgADCgMJAwAAAA==.Nantari:BAAALgADCggJBwAAAA==.Narestor:BAAALgAFFAEJAQAAAA==.Navras:BAAALgADCgIJAgAAAA==.Nazurend:BAAALgAECgYJDAAAAA==.',
Nb='Nblock:BAAALgAECgQJBwAAAA==.',
Ne='Nekopunch:BAAALgAECgYJCQAAAA==.Nero:BAABLgAECn8lAAIeAAgJ/CEEAgCmAgAeAAgJ/CEEAgCmAgAAAA==.Nest:BAAALgADCgYJDQAAAA==.',
Ni='Nicholas:BAAALgADCgIJAgAAAA==.Nicorobin:BAABLgAECn8fAAMaAAgJNAUdfQBhAQAaAAgJNAUdfQBhAQAhAAIJywFaZgBDAAAAAA==.Nimuerose:BAAALgADCgMJAwAAAA==.',
No='Nortree:BAAALgAECgUJDAAAAA==.Nost:BAABLgAECn8gAAIFAAgJwRpgDwBEAgAFAAgJwRpgDwBEAgAAAA==.Notthatbish:BAAALgADCgYJBgAAAA==.',
Nu='Nulwyrm:BAABLgAECn8UAAIQAAYJixuPEwBnAQAQAAYJixuPEwBnAQAAAA==.',
Ny='Nyyrivik:BAAALgADCgYJBgAAAA==.',
['Nø']='Nøtrab:BAAALgADCgQJBAAAAA==.',
Oc='Octapie:BAABLgAECn8fAAIBAAcJ9h+JCABhAgABAAcJ9h+JCABhAgAAAA==.',
Oh='Ohitsadragon:BAAALgAECgYJEAAAAA==.',
Or='Oranur:BAAALgADCgIJAgAAAA==.Orclock:BAAALgAECgQJAQABLgAECgYJBgAGAAAAAA==.',
Ow='Owl:BAABLgAECn8dAAIiAAgJEgwPBABlAQAiAAgJEgwPBABlAQAAAA==.Owlcatraz:BAAALgAECgUJCAAAAA==.',
Pa='Paendrag:BAAALgADCgUJBQAAAA==.Panadarama:BAACLgAFFH8KAAICAAMJzyIjDAAxAQACAAMJzyIjDAAxAQAuAAQKfyIAAgIACAkQJWwEAEUDAAIACAkQJWwEAEUDAAAA.Panteragon:BAAALgAECgUJDAAAAA==.Pasara:BAAALgADCgQJBAAAAA==.Pashene:BAAALgAECgUJBQAAAA==.',
Pe='Periwinkle:BAABLgAECn8XAAIYAAcJJgqbHQAWAQAYAAcJJgqbHQAWAQAAAA==.Persaud:BAABLgAECn8XAAMhAAgJKxraDwDSAQAhAAcJnhLaDwDSAQAaAAQJNCCdLAB6AQAAAA==.Pettacular:BAAALgADCgMJAwAAAA==.',
Ph='Phidra:BAABLgAECn8gAAMBAAgJIQ0fHQB6AQABAAgJIQ0fHQB6AQAdAAQJTga3agCYAAAAAA==.Philiia:BAAALgADCgQJBAAAAA==.Philionel:BAAALgADCgYJBgABLgADCgcJIAAGAAAAAA==.Phranky:BAAALgAECgEJAgAAAA==.',
Pi='Pixiebrew:BAAALgAECgQJBgAAAA==.',
Pl='Plutrax:BAAALgAECgEJAQAAAA==.',
Po='Pokecheck:BAAALgADCgUJBgAAAA==.',
Pr='Predatorc:BAABLgAECn8UAAIZAAgJEgvETgB9AQAZAAgJEgvETgB9AQAAAA==.Primevl:BAAALgADCgQJBAAAAA==.Primévil:BAABLgAECn8eAAIjAAgJUwofNAASAQAjAAgJUwofNAASAQAAAA==.',
Pu='Puma:BAAALgAECgYJEwAAAA==.',
['Pí']='Píp:BAAALgADCgcJBwAAAA==.',
Qu='Quarz:BAAALgAECgEJAQAAAA==.Quimmi:BAAALgADCgMJAwAAAA==.',
Ra='Raediant:BAAALgAECgUJBgABLgAECggJFQACAPMLAA==.Raelek:BAAALgAECgMJAwAAAA==.Ragethecage:BAAALgADCgMJAwAAAA==.Raggaemon:BAAALgAFFAEJAQAAAA==.Ragingbanana:BAAALgAECgEJAQAAAA==.Rahmonk:BAAALgADCgEJAQAAAA==.Rahvinwulf:BAABLgAECn8XAAMJAAcJkBrmCQCNAQARAAcJwBSfQgCaAQAJAAcJqBTmCQCNAQAAAA==.Raquel:BAABLgAECn8aAAIBAAgJUQttRwBkAQABAAgJUQttRwBkAQAAAA==.Raszageth:BAAALgADCgEJAQAAAA==.Raínbowdash:BAAALgADCgEJAQAAAA==.',
Re='Rede:BAAALgAECgEJAQAAAA==.Rein:BAAALgAECgYJDgAAAA==.Relieff:BAAALgADCgkJEgAAAA==.Relmin:BAAALgADCgcJDQAAAA==.Rennistus:BAAALgADCgYJBgAAAA==.',
Ri='Rio:BAABLgAECn8eAAIeAAgJvRXyBwDRAQAeAAgJvRXyBwDRAQAAAA==.Ris:BAABLgAECn8nAAIIAAgJFSDKDgBoAgAIAAgJFSDKDgBoAgAAAA==.Riseyyn:BAAALgADCgIJAgAAAA==.',
Ro='Roadzombie:BAAALgADCgMJAwAAAA==.Rockheart:BAAALgADCgEJAQAAAA==.Roknathar:BAABLgAECn8cAAIgAAcJoSVwAQByAgAgAAcJoSVwAQByAgAAAA==.Ronilf:BAAALgAECgYJEQAAAA==.Rou:BAAALgADCgUJBQAAAA==.Rough:BAAALgADCgEJAQAAAA==.Royda:BAABLgAECn8mAAMXAAgJGRzsBgAdAgAXAAgJGRzsBgAdAgAYAAIJyhN0iAAnAAAAAA==.',
Ru='Ruitiny:BAAALgADCgkJEAAAAA==.Rukaza:BAAALgAECgEJAQABLgAECggJLgAkADskAA==.',
Ry='Rygard:BAAALgADCgQJBAAAAA==.',
Sa='Saerenity:BAAALgAECgMJAwAAAA==.Saintlucky:BAAALgADCgYJBgAAAA==.Saintvonzeal:BAAALgADCggJFQAAAA==.Sana:BAABLgAECn8cAAIdAAcJ9BzXCwDdAQAdAAcJ9BzXCwDdAQAAAA==.Saphihr:BAAALgADCgYJBgAAAA==.Saxmaster:BAAALgAECgMJAwAAAA==.Sazerac:BAAALgAECgUJEwAAAA==.',
Sc='Scaly:BAAALgAECgEJAQABLgAECgQJBQAGAAAAAA==.',
Se='Sedo:BAAALgAECgEJAQAAAA==.Selenis:BAAALgAECgEJAgABLgAECggJHQATAKkiAA==.',
Sg='Sgtshamrock:BAAALgADCgIJAgAAAA==.',
Sh='Shadowlady:BAAALgAECgEJAQAAAA==.Shadowrealms:BAAALgADCgYJCAAAAA==.Shamainiac:BAABLgAECn8kAAIdAAgJZhQ/EwCBAQAdAAgJZhQ/EwCBAQAAAA==.Shaomai:BAABLgAECn8cAAMdAAcJJiITBgBNAgAdAAcJJiITBgBNAgABAAQJLw0XcwDDAAAAAA==.Sharper:BAABLgAECn8XAAIjAAcJhhv1EwDKAQAjAAcJhhv1EwDKAQABLgAFFAIJBQATAL4bAA==.Shep:BAAALgAECgMJAwAAAA==.Sherra:BAAALgADCgIJAgAAAA==.Shiok:BAAALgADCggJFwAAAA==.Shâde:BAAALgAECgQJBgAAAA==.',
Si='Siirius:BAAALgAECgQJCAAAAA==.Silverwin:BAAALgAECgUJDQAAAA==.',
Sk='Skribbles:BAAALgADCgQJBAAAAA==.',
Sl='Slimage:BAABLgAECn8bAAIlAAgJ1Rn+AAAnAgAlAAgJ1Rn+AAAnAgAAAA==.Slushius:BAAALgAECgEJAQAAAA==.',
Sm='Smite:BAAALgAECgQJCgAAAA==.Smitted:BAAALgAECgYJEQAAAA==.Smitty:BAAALgAECgcJBwAAAA==.',
So='Socharis:BAAALgADCgMJAwAAAA==.Sodapops:BAAALgADCgkJEAAAAA==.Sophiaa:BAAALgADCgcJBgAAAA==.Sorn:BAAALgAECgYJDgAAAA==.',
Sp='Spaarkle:BAAALgAECgYJBwAAAA==.Specialheist:BAAALgAECgkJCgAAAA==.Spectrehawk:BAAALgAECgYJBgAAAA==.Speçtre:BAACLgAFFH8FAAIDAAQJiQVZFABgAAADAAQJiQVZFABgAAAuAAQKfxwAAgMACAlmFcoSAN8BAAMACAlmFcoSAN8BAAAA.Spins:BAAALgAECgEJAQAAAA==.',
Sr='Srankhunter:BAAALgAECgEJAQAAAA==.',
St='Stallord:BAAALgADCgYJDAAAAA==.Steppin:BAAALgAECgcJDgAAAA==.Stormglaive:BAABLgAECn8aAAMeAAcJPhU3HQDWAQAeAAcJPhU3HQDWAQAjAAEJTwPY6QAoAAAAAA==.Stupidity:BAABLgAECn8cAAIXAAYJdB+4DgCcAQAXAAYJdB+4DgCcAQAAAA==.',
Su='Suldrick:BAAALgADCgkJEAAAAA==.Suppabad:BAABLgAECn8gAAMOAAgJNR8kAwDMAgAOAAgJNR8kAwDMAgAmAAQJTREAIwDTAAAAAA==.Suzäku:BAAALgADCgkJCQAAAA==.',
['Sá']='Sákura:BAAALgAECgIJBAAAAA==.',
Ta='Taara:BAAALgADCgUJBQABLgAECggJIAAIAB0kAA==.Tarysha:BAAALgAECgUJCgAAAA==.Tatertotz:BAAALgAECgUJCQAAAA==.Taynav:BAABLgAECn8cAAInAAcJbBSZDgCWAQAnAAcJbBSZDgCWAQAAAA==.Tayoma:BAAALgAECgEJAQAAAA==.Tazara:BAAALgAECgEJAQAAAA==.',
Te='Tealth:BAAALgAECgMJAwAAAA==.Ted:BAAALgAECgYJEQAAAA==.Tehgrimza:BAABLgAECn8bAAMaAAgJvRJTIwCkAQAaAAgJvRJTIwCkAQAhAAEJrxB4dAAwAAAAAA==.Teias:BAAALgAECgIJAgABLgAECgkJJgAYAM4YAA==.Temu:BAAALgAECgUJBgAAAA==.Tevia:BAABLgAECn8kAAIoAAgJ4BR8BQDQAQAoAAgJ4BR8BQDQAQAAAA==.',
Th='Thalip:BAAALgAECgQJBQAAAA==.Thokmay:BAABLgAECn8fAAImAAgJIA/yEgBaAQAmAAgJIA/yEgBaAQAAAA==.Thorel:BAAALgADCggJFgAAAA==.Thornar:BAAALgADCgQJBAAAAA==.Thunden:BAAALgADCgUJBQAAAA==.',
Ti='Tiandrinna:BAABLgAECn8aAAIKAAgJjBzbAAAcAgAKAAgJjBzbAAAcAgAAAA==.Tightywhitey:BAAALgAECgYJBwAAAA==.Timkaoss:BAAALgAECgYJEwAAAA==.Timmyjudge:BAAALgADCgQJBAAAAA==.Tinyspoon:BAAALgADCgMJAwAAAA==.',
Tm='Tmagnet:BAAALgAECgUJDQAAAA==.',
To='Tooshie:BAAALgADCgcJBwAAAA==.Tormin:BAAALgADCgcJDQAAAA==.Torrente:BAAALgADCgEJAQAAAA==.Tourmaline:BAAALgAECgEJAQABLgAECgYJFAABAJUlAA==.',
Tr='Treebud:BAAALgADCgkJDAAAAA==.Tritherelyn:BAAALgADCgcJBwAAAA==.Trixterwolf:BAAALgADCgUJBwAAAA==.',
Ts='Tserendolgor:BAAALgADCggJDwAAAA==.',
Tw='Tweedildee:BAABLgAECn8kAAIIAAgJdxU1LQCvAQAIAAgJdxU1LQCvAQAAAA==.',
Ty='Tygrassar:BAAALgADCgcJDQAAAA==.',
['Tà']='Tàttersail:BAABLgAECn8YAAIYAAcJFxqQGQAQAgAYAAcJFxqQGQAQAgAAAA==.',
['Tä']='Täd:BAAALgAECgMJAwAAAA==.',
Va='Vaelena:BAAALgADCgMJAwAAAA==.Vahldr:BAAALgAECgQJBQAAAA==.Valdor:BAAALgAECgUJBQAAAA==.Valeeras:BAAALgADCgUJBQAAAA==.Valeron:BAAALgAECgcJDgAAAA==.Valicous:BAAALgADCgkJHQAAAA==.Valyerian:BAABLgAECn8uAAIRAAgJ5hsRFgCcAgARAAgJ5hsRFgCcAgAAAA==.Vandalie:BAAALgAECgEJAQABLgAECgYJDwAGAAAAAA==.Vandevoker:BAAALgAECgQJCAABLgAECgYJDwAGAAAAAA==.Vanserra:BAAALgADCgcJDwAAAA==.Varregory:BAAALgADCgQJBAAAAA==.Vaxas:BAABLgAECn8aAAIFAAgJHByWDgBMAgAFAAgJHByWDgBMAgAAAA==.Vaylorian:BAAALgAECgQJBAAAAA==.Vaült:BAABLgAECn8YAAMWAAcJzxaEDgD1AQAWAAcJzxaEDgD1AQAFAAMJPwYTEgFzAAAAAA==.',
Ve='Verianna:BAABLgAECn8dAAMTAAgJqSLWEwAbAgATAAcJSiHWEwAbAgADAAIJ8iXAFADbAAAAAA==.Vexmorphis:BAAALgADCgUJBQABLgAECgEJAQAGAAAAAA==.Vexxis:BAAALgADCgMJAwAAAA==.',
Vi='Vitani:BAAALgAECgEJAQAAAA==.',
Vo='Vodkâshots:BAAALgAECgkJBgAAAA==.Votary:BAAALgADCgcJDgAAAA==.',
Vt='Vtown:BAAALgADCgYJFQAAAA==.',
Wa='Wadumu:BAABLgAECn8WAAMLAAcJggwLaQAYAQALAAYJVA4LaQAYAQAnAAcJCQc8EwCMAAAAAA==.Wagwanmist:BAABLgAECn8fAAIOAAcJVxtXCQAaAgAOAAcJVxtXCQAaAgAAAA==.Wardrago:BAAALgADCgcJCAAAAA==.Warvegas:BAAALgAECgEJAQAAAA==.Warwulf:BAAALgAECgQJBAABLgAECgcJFwAJAJAaAA==.',
Wi='Willowy:BAABLgAECn8gAAIIAAgJHSRMFAA4AgAIAAgJHSRMFAA4AgAAAA==.',
['Wâ']='Wâlmi:BAABLgAECn8WAAMBAAUJdQ6vPwCuAAABAAUJdQ6vPwCuAAAdAAQJvAZTaACiAAAAAA==.',
Xa='Xaerius:BAABLgAECn8gAAMRAAgJ3BAPFQCMAQARAAcJrxIPFQCMAQAoAAEJ6gVFLwAwAAAAAA==.Xalatath:BAAALgADCgcJDQAAAA==.Xan:BAABLgAECn8eAAIIAAgJshrJHAD/AQAIAAgJshrJHAD/AQAAAA==.Xann:BAAALgADCgYJBgAAAA==.Xantharr:BAAALgADCgMJAwAAAA==.Xantyr:BAAALgADCgYJBgAAAA==.Xashae:BAAALgADCgcJDwAAAA==.',
Xe='Xenocidal:BAABLgAECn8YAAIIAAcJJiNJPQCDAgAIAAcJJiNJPQCDAgAAAA==.',
Xo='Xog:BAAALgAECgEJAQAAAA==.',
Ya='Yarman:BAAALgAECgUJDQAAAA==.',
Ye='Yeaforpie:BAAALgAECgYJEgAAAA==.Yervant:BAAALgAECgQJBAAAAA==.Yesthatbish:BAAALgAECgcJDwAAAA==.',
Yo='Yoshial:BAAALgADCgcJIAAAAA==.',
Za='Zadoc:BAAALgADCgcJGwAAAA==.Zano:BAABLgAECn8fAAMXAAgJPxIzHgDoAQAXAAgJPxIzHgDoAQASAAYJjgwgHAD/AAAAAA==.',
Ze='Zealins:BAAALgADCgUJCAAAAA==.Zenrek:BAAALgADCgEJAQAAAA==.Zenrekt:BAAALgADCgMJBAAAAA==.Zeuhl:BAAALgAECgcJCwAAAA==.',
Zi='Zilver:BAAALgADCgEJAQABLgAECggJJQAFAO8kAA==.Ziv:BAABLgAECn8lAAILAAkJ2h8lAwAMAwALAAkJ2h8lAwAMAwABLgAECgcJCAAGAAAAAA==.Ziyn:BAAALgAECgcJCAAAAA==.',
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

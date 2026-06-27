local _, ns = ...
ns.continents = {}
ns.map = {}

-- Name Spaced data file for anything mapping related and which is common across my AddOns

if ( ns.version < 50000) then
	ns.continents[ 1414 ] = true -- Kalimdor
	ns.continents[ 1415 ] = true -- Eastern Kingdoms
else
	ns.continents[ 12 ] = true -- Kalimdor
	ns.continents[ 13 ] = true -- Eastern Kingdoms
end
if ( ns.version < 50000) then
	ns.continents[ 1945 ] = ( ns.version >= 20000) and true or nil -- Outland
elseif ( ns.version >= 60000) then
	ns.continents[ 101 ] = true -- Outland
else
	ns.continents[ 1467 ] = true -- Outland
end
ns.continents[ 113 ] = ( ns.version >= 30000) and true or nil -- Northrend
ns.continents[ 203 ] = ( ns.version >= 40000) and true or nil -- Vashj'ir
ns.continents[ 948 ] = ( ns.version >= 40000) and true or nil -- The Maelstrom
ns.continents[ 424 ] = ( ns.version >= 50000) and true or nil -- Pandaria
ns.continents[ 572 ] = ( ns.version >= 60000) and true or nil -- Draenor
ns.continents[ 619 ] = ( ns.version >= 70000) and true or nil -- Broken Isles
ns.continents[ 875 ] = ( ns.version >= 80000) and true or nil -- Zandalar
ns.continents[ 876 ] = ( ns.version >= 80000) and true or nil -- Kul Tiras
ns.continents[ 1550 ] = ( ns.version >= 90000) and true or nil -- Shadowlands
ns.continents[ 1978 ] = ( ns.version >= 100000) and true or nil -- Dragon Isles
ns.continents[ 2274 ] = ( ns.version >= 110000) and true or nil -- Khaz Algar
ns.continents[ 947 ] = true -- Azeroth

--==================================================================================================================================
--
-- KALIMDOR
--
--==================================================================================================================================

ns.map.ammenVale = 468
ns.map.ahnQiraj = 327
ns.map.ashenvale = ( ns.version < 50000 ) and 1440 or 63
ns.map.azshara = ( ns.version < 50000 ) and 1447 or 76
ns.map.azuremyst = ( ns.version < 50000 ) and 1943 or 97
ns.map.banethilBarrowDenL = 61
ns.map.banethilBarrowDenU = 60
ns.map.barrens = ( ns.version < 50000 ) and 1413 or 10 -- In Classic Cata it's called "The Barrens". Retail it's "Northern Barrens"
ns.map.bloodmyst = ( ns.version < 50000 ) and 1950 or 106
ns.map.brawlgarArena = 503
ns.map.campNarache = 462
ns.map.cleftOfShadow = 86
ns.map.darkshore = ( ns.version < 50000 ) and 1439 or 62
ns.map.darnassus = ( ns.version < 50000 ) and 1457 or 89
ns.map.desolace = ( ns.version < 50000 ) and 1443 or 66
ns.map.durotar = ( ns.version < 50000 ) and 1411 or 1
ns.map.dustwallow = ( ns.version < 50000 ) and 1445 or 70
ns.map.echoIsles = 463
ns.map.felRock = 59
ns.map.felwood = ( ns.version < 50000 ) and 1448 or 77
ns.map.feralas = ( ns.version < 50000 ) and 1444 or 69
ns.map.moonglade = ( ns.version < 50000 ) and 1450 or 80
ns.map.mountHyjal = 198
ns.map.mulgore = ( ns.version < 50000 ) and 1412 or 7
ns.map.orgrimmar = ( ns.version < 50000 ) and 1454 or 85
ns.map.shadowglen = 460
ns.map.shadowthreadCave = 58
ns.map.silithus = ( ns.version < 50000 ) and 1451 or 81
ns.map.southernBarrens = 199
ns.map.spitescaleCavern = 464
ns.map.stonetalon = ( ns.version < 50000 ) and 1442 or 65
ns.map.tanaris = ( ns.version < 50000 ) and 1446 or 71
ns.map.teldrassil = ( ns.version < 50000 ) and 1438 or 57
ns.map.theExodar = ( ns.version < 50000 ) and 1947 or 103
ns.map.thousand = ( ns.version < 50000 ) and 1441 or 64
ns.map.thunder = ( ns.version < 50000 ) and 1456 or 88
ns.map.uldumOld = 249
ns.map.uldumNew= 1527
ns.map.ungoro = ( ns.version < 50000 ) and 1449 or 78
ns.map.valleyOfTrials = 461
ns.map.wailingCaverns = 11
ns.map.winterspring = ( ns.version < 50000 ) and 1452 or 83
ns.map.kalimdor = ( ns.version < 50000 ) and 1414 or 12

--==================================================================================================================================
--
-- EASTERN KINGDOMS
--
--==================================================================================================================================

ns.map.alterac = ( ns.version < 50000 ) and 1416
ns.map.arathi = ( ns.version < 50000 ) and 1417 or 14
ns.map.atalAman = 2536
ns.map.badlands = ( ns.version < 50000 ) and 1418 or 15
ns.map.bizmosBrawlPub = 500
ns.map.blastedLands = ( ns.version < 50000 ) and 1419 or 17
ns.map.burningSteppes = ( ns.version < 50000 ) and 1428 or 36
ns.map.coldridgePass = 28
ns.map.coldridgeValley = 427
ns.map.deadwind = ( ns.version < 50000 ) and 1430 or 42
ns.map.deathknell = 465
ns.map.deeprunTram = 499
ns.map.dunMorogh = ( ns.version < 50000 ) and 1426 or 27
ns.map.duskwood = ( ns.version < 50000 ) and 1431 or 47
ns.map.easternP = ( ns.version < 50000 ) and 1423 or 23
ns.map.elwynn = ( ns.version < 50000 ) and 1429 or 37
ns.map.eversong = ( ns.version < 50000 ) and 1941 or 94
ns.map.eversongEK = 2395
ns.map.frostmaneHold = 470
ns.map.frostmaneHovel = 428
ns.map.ghostlands = ( ns.version < 50000 ) and 1942 or 95
ns.map.gilneas = 179 		-- As a non-worgen not accessible via World Map
ns.map.gilneasCity = 202	-- As a non Worgen I noted 1577. Both via the World Map. 1577 has Cathedral 1/4 and Light's Dawn missing
ns.map.harandar = 2413
ns.map.hillsbrad = ( ns.version < 50000 ) and 1424 or 25
ns.map.ironforge = ( ns.version < 50000 ) and 1455 or 87
ns.map.isleOfQuelDanas = 122
ns.map.lochModan = ( ns.version < 50000 ) and 1432 or 48
ns.map.newTinkertown = 30
ns.map.nightWebsHollow = 466
ns.map.northshire = 425
ns.map.northStrangle = ( ns.version < 50000 ) and 1434 or 50 -- 1434 is listed as "stranglethorne"
ns.map.oldIronforge = 1361
ns.map.quelDanas = 2432
ns.map.quelThalas = 2537
ns.map.redridge = ( ns.version < 50000 ) and 1433 or 49
ns.map.ruinsGilneas = 217
ns.map.ruinsGilneasCity = 218
ns.map.sanctumOfLight = 24		-- Paladin class Order Hall. Eastern Plaguelands
ns.map.searingGorge = ( ns.version < 50000 ) and 1427 or 32
ns.map.silvermoon = ( ns.version < 50000 ) and 1954 or 110
ns.map.silvermoonCity = 2393
ns.map.silverpine = ( ns.version < 50000 ) and 1421 or 21
ns.map.stormwind = ( ns.version < 50000 ) and 1453 or 84
ns.map.stranglethorn = 224
ns.map.sunstriderIsle = 467
ns.map.sunwell = 2566 -- Maybe
ns.map.swampOS = ( ns.version < 50000 ) and 1435 or 51
ns.map.theCapeStrangle = 210
ns.map.theGrizzledDen = 29
ns.map.TheHinter = ( ns.version < 50000 ) and 1425 or 26
ns.map.tirisfal = ( ns.version < 50000 ) and 1420 or 18
ns.map.tirisfalBlight = 2070
ns.map.tolBarad = 244
ns.map.tolBaradPeninsular = 245
ns.map.twilight = 241
ns.map.undercity = ( ns.version < 50000 ) and 1458 or ( ( ns.version < 60000 ) and 998 or 90 )
ns.map.voidstorm = 2405
ns.map.westernP = ( ns.version < 50000 ) and 1422 or 22
ns.map.westfall = ( ns.version < 50000 ) and 1436 or 52
ns.map.wetlands = ( ns.version < 50000 ) and 1437 or 56
ns.map.zulAman = 2437
ns.map.easternK = ( ns.version < 50000 ) and 1415 or 13

--==================================================================================================================================
--
-- OUTLAND
--
--==================================================================================================================================

ns.map.bladesEdge = ( ns.version < 50000 ) and 1949 or 105
ns.map.hellfire = ( ns.version < 50000 ) and 1944 or 100
ns.map.nagrand = ( ns.version < 50000 ) and 1951 or 107
ns.map.netherstorm = ( ns.version < 50000 ) and 1953 or 109
ns.map.shadowmoon = ( ns.version < 50000 ) and 1948 or 104
ns.map.shattrath = ( ns.version < 50000 ) and 1955 or 111
ns.map.terokkar = ( ns.version < 50000 ) and 1952 or 108
ns.map.zangarmarsh = ( ns.version < 50000 ) and 1946 or 102
ns.map.outland = ( ns.version < 50000 ) and 1945 or  ( ( ns.version < 60000 ) and 1467 or 101 )

--==================================================================================================================================
--
-- WRATH OF THE LICH KING / NORTHREND
--
--==================================================================================================================================

ns.map.boreanTundra = 114
ns.map.crystalsongForest = 127
ns.map.dalaran = 125		-- By design The Underbelly doesn't overlay on Dalaran. It goes straight to Crystalsong etc.
ns.map.dragonblight = 115
ns.map.grizzlyHills = 116
ns.map.howlingFjord = 117
ns.map.hrothgarsLanding = 170
ns.map.icecrown = 118
ns.map.sholazarBasin = 119
ns.map.theLostGlacier = 871	-- Deathknight Order Hall campaign in Legion. Far to the northwest of Hrothgar's Landing
ns.map.theStormPeaks = 120
ns.map.theUnderbelly = 126 	-- By design Dalaran doesn't overlay on The Underbelly. It goes straight to Crystalsong etc.
ns.map.wintergrasp = 123
ns.map.zulDrak = 121

--==================================================================================================================================
--
-- CATACLYSM (INC. THE MAELSTROM / VASHJ'IR )
--
--==================================================================================================================================

-- Mount Hyjal, The Maelstrom (Continent), Tol Barad (2), Twilight Highlands, Uldum (both), Vashj'ir see Kal / EK above

ns.map.abyssalDepths = 204
ns.map.deepholm = 207
ns.map.kelptharForest = 201
ns.map.kezan = 194
ns.map.shimmeringExpanse = 205
ns.map.theLostIsles = 174
ns.map.theMaelstromZone = 276 -- Eg: Accessable from The Maelstrom continent map (click under the text)
ns.map.vashjir = 203

--==================================================================================================================================
--
-- MISTS OF PANDARIA
--
--==================================================================================================================================

-- Brawl'gar Arena & Bizmo's Brawl Pub see Kal / EK above

ns.map.cavernOfEndlessEchoes = 377
ns.map.cryptOfKorune = 387
ns.map.dreadWastes = 422
ns.map.greenstoneQuarryL = 373
ns.map.greenstoneQuarryU = 372
ns.map.howlingwindCavern = 380
ns.map.isleOfGiants = 507
ns.map.isleOfThunder = 504
ns.map.knucklethumpHole = 382
ns.map.krasarangWilds = 418
ns.map.kunLaiSummit = 379
ns.map.niuzaoCatacombs = 389
ns.map.oonaKagu = 375
ns.map.ruinsOfKorune = 386
ns.map.soSSEmperors = 393		-- Shrine of Seven Stars - The Emeror's Step
ns.map.soSSExchange = 394		-- Shrine of Seven Stars - The Imperial Exchange
ns.map.soTMCrescent = 391		-- Shrine of Two Moons - Hall of the Crescent
ns.map.soTMMercantile = 392		-- Shrine of Two Moons - The Imperial Mercantile
ns.map.theAncientPassage = 434
ns.map.theJadeForest = 371
ns.map.theVeiledStair = 433
ns.map.theWanderingIsle = 378	-- Monk starting area. See also Legion
ns.map.theWidowsWail = 374
ns.map.timelessIsle = 554
ns.map.tombOfConquerors = 385
ns.map.townlongSteppes = 388
ns.map.valeOfEternalBlossoms = 390
ns.map.valleyOfTheFourWinds = 376

--==================================================================================================================================
--
-- WARLORDS OF DRAENOR / GARRISON
--
--==================================================================================================================================

ns.map.ashran = 588
ns.map.ashranExcavation = 589
ns.map.frostwall = 590
ns.map.frostfireRidge = 525
ns.map.gorgrond = 543
ns.map.lunarfall = 582
ns.map.moirasReachArmory = 545	-- Moira's Reach - The Armory
ns.map.moirasReachBastion = 544	-- Moira's Reach - Moira's Bastion
ns.map.nagrandDraenor = 550
ns.map.shadowmoonDraenor = 539
ns.map.shattrathDraenor = 594
ns.map.spiresOfArak = 542
ns.map.stormshield = 622
ns.map.talador = 535
ns.map.tanaanJungle = 534
ns.map.theBreachedOssuary = 538
ns.map.warspear = 624

--==================================================================================================================================
--
-- LEGION / BROKEN ISLES
--
--==================================================================================================================================

-- Paladin Order Hall Sanctum of Light is in the Eastern Plaguelands. See above.
-- Demon Hunter's Fel Hammer in Mardum to do. Drakthyr there is no Order Hall.
-- The Lost Glacier see Northrend.

ns.map.acherusCommand = 648	-- Acherus: The Ebon Hold - The Hall of Command (34.69,36.93) is portal to other level. Centre(50.25,51.04)
ns.map.acherusHeart = 647	-- Acherus: The Ebon Hold - The Heart of Acherus (33.29,35.60) is portal to other level. Centre(50.29,50.85)
ns.map.aegwynnsGallery = 629	-- aka Chamber of the Guardian
								-- Arrive (63.39,23.87) = Dal (55.16,36.74). (30.36,85.11) = Dal (44.43,56.64)
								-- (64.73,80.69) = Dal (55.60,55.20), (25.93,33.98) = Dal (42.99,40.03)
								-- Portal to Telogrus Rift is at (33.78,78.67), Dal (45.55,54.55)
								-- Portal to Wyrmrest Temple is at (30.79,84.35), Dal (44.57,56.39). One way
								-- Portal to Karazhan is at (32.02,71.52), Dal (44.97,52.23). One way. Arrive at (47.24,75.40)
ns.map.antoranWastes = 885
ns.map.argus = 905
ns.map.argusBeacons = 830			-- Like a Flight Master map. 830 and 905 cannot map onto each other.
ns.map.azsuna = 630
ns.map.dalaranLegion = 627
ns.map.dreadscarRift717 = 717		-- Warlock Order Hall. Somewhere in the Twisting Nether.
ns.map.dreadscarRift718 = 718		-- Warlock Order Hall. Somewhere in the Twisting Nether.
									-- One is the Order Hall, the other is for the artifact acquisition. Which is which?
ns.map.eredath = 882
ns.map.eyeOfAzshara = 790
ns.map.felHammerL = 721				-- Demon Hunter Order Hall. Cannot map onto Mardum. Coordinates can map between top/bottom.
ns.map.felHammerU = 720				-- Demon Hunter Order Hall. There's also a top deck - accessible during the Order Hall campaign.
ns.map.guardiansLibrary = 735		-- Mage Order Hall. Cannot map onto Dalaran.
ns.map.hallOfTheGuardian = 734		-- Mage Order Hall
ns.map.hellheim = 649
ns.map.highmountain = 650
ns.map.krokuun = 830
ns.map.mardum = 672					-- Demon Hunter starting zone. Somewhere in the Twisting Nether.
ns.map.mardumOrder = 718			-- Demon Hunter Order Hall. Can't actually explore it
ns.map.netherlightTemple = 702		-- Priest Order Hall. Somewhere in the Twisting Nether
ns.map.oceanusCove = 632
ns.map.skyhold = 695				-- Warrior Order Hall. Somewhere above Hellheim
ns.map.stormheim = 634
ns.map.suramar = 680
ns.map.telogrusRift = 971			-- Arrive at (25.34,27.89). Rift back to Dal is (24.95,27.91)
ns.map.theBrokenShore = 646
ns.map.theDreamgrove = 747			-- Druid Order Hall. Val'sharah. Needs coord mapping
ns.map.theHallOfShadows = 626		-- Rogue Order Hall. Under Legion Dalaran. The old WotLK Cantrip & Crows. Needs coord mapping
ns.map.theMaelstromShaman = 726 	-- Shaman Order Hall. Cannot map onto Cataclysm Maelstrom zone. Roughly onto continent possible.
ns.map.theUnderbellyLegion = 628
ns.map.theVindicaarLowerA = 887
ns.map.theVindicaarUpperA = 886
ns.map.theVindicaarLowerE = 884
ns.map.theVindicaarUpperE = 883
ns.map.theVindicaarLowerH = 941		-- Special Heritage Instance. Cannot map onto anything as it's high above a rotating Azeroth!
ns.map.theVindicaarUpperH = 940
ns.map.theVindicaarLowerK = 832
ns.map.theVindicaarUpperK = 831
ns.map.theWanderingIsleZen = 709 	-- Monk Order Hall. The Pandaria monk starter zone shares identical coordinate mapping
ns.map.thunderTotemExt = 750
ns.map.thunderTotemInt = 652		-- aka Hall of Chieftains
ns.map.trueshotLodge = 739			-- Hunter Order Hall. In Highmountain but needs coord mapping
ns.map.valsharah = 641

--==================================================================================================================================
--
-- BATTLE FOR AZEROTH / KUL TIRAS & ZANDALAR
--
--==================================================================================================================================

ns.map.boralus = 1161
ns.map.dazaralor = 1165
ns.map.dazaralorGreatSeal = 1163
ns.map.dazaralorHallChroniclers = 1164
ns.map.drustvar = 896
ns.map.mechagon = 1462
ns.map.nazjatar = 1355
ns.map.nazmir = 863
ns.map.stormsongValley = 942
ns.map.tiragardeSound = 895
ns.map.voldun = 864
ns.map.zuldazar = 862

--==================================================================================================================================
--
-- THE SHADOWLANDS
--
--==================================================================================================================================

ns.map.ardenweald = 1565
ns.map.bastion = 1533
ns.map.crapopolis = 1532			-- Part of Kezan. A rough mapping is possible
ns.map.korthia = 1961				-- City of Secrets
ns.map.maldraxxus = 1536
ns.map.oribosBrokersDen = 1672		-- The Broker's Den
ns.map.oribosCrucible = 1673		-- The Crucible
ns.map.oribosRingOfFates = 1670
ns.map.oribosTransference = 1671
ns.map.revendreth = 1525
ns.map.tazaveshKA = 2472			-- Maps easily onto K'aresh
ns.map.tazaveshSL = 2016			-- Non-instanced foyer area. Maps easily onto the Shadowlands
ns.map.tazaveshVeiled = 1989		-- The Veiled Market. Main Tazavesh instance map
ns.map.theMaw = 1543
ns.map.zerethMortis = 1970

--==================================================================================================================================
--
-- DRAGONFLIGHT / DRAGON ISLES
--
--==================================================================================================================================

ns.map.ohnahranPlains = 2023
ns.map.thaldraszus = 2025
ns.map.theAzureSpan = 2024
ns.map.theForbiddenReach = 2151
ns.map.theWakingShores = 2022
ns.map.valdrakken = 2112
ns.map.zaralekCavern = 2133

--==================================================================================================================================
--
-- KHAZ ALGAR / THE WAR WITHIN
--
--==================================================================================================================================

ns.map.azjKahet = 2255
ns.map.cityOfThreads = 2213		-- City of Threads / Azj-Kahet
ns.map.cityOfThreadsL = 2216	-- City of Threads / Azj-Kahet - Lower
ns.map.dornogal = 2339
ns.map.hallowfall = 2215
ns.map.isleOfDorn = 2248
ns.map.karesh = 2371			-- Does appear top left of Khaz Algar map. Very arbitrary mapping is possible
ns.map.theRingingDeeps = 2214

--==================================================================================================================================
--
-- AZEROTH
--
--==================================================================================================================================

ns.map.exilesReach = 1409

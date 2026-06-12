-- Khaz Algar

local L = BigWigs:NewBossLocale("Aggregation of Horrors", "deDE")
if L then
	L.void_rocks = "Leerenfelsen" -- Plural of Void Rock (452379)
end

L = BigWigs:NewBossLocale("Reshanor, The Untethered", "deDE")
if L then
	L.run = "Zum Portal laufen und Extra Aktionsbutton drücken"
end

-- Liberation of Undermine

L = BigWigs:NewBossLocale("Cauldron of Carnage", "deDE")
if L then
	L.custom_on_fade_out_bars = "Leisten abblenden"
	L.custom_on_fade_out_bars_desc = "Blendet die Leisten ab, welche zum aus der Reichweite befindlichen Boss gehören."

	L.bomb_explosion = "Bombenexplosion"
	L.bomb_explosion_desc = "Zeigt einen Timer für die Explosion der Bomben."

	L.eruption_stomp = "Stampfen" -- Short for Eruption Stomp
	L.thunderdrum_salvo = "Salve" -- Short for Thunderdrum Salvo

	L.static_charge_high = "%d - Du bewegst Dich zuviel"
end

L = BigWigs:NewBossLocale("Rik Reverb", "deDE")
if L then
	L.amplification = "Verstärker"
	L.echoing_chant = "Echos"
	L.faulty_zap = "Schocker"
	L.sparkblast_ignition = "Fässer"
end

L = BigWigs:NewBossLocale("Stix Bunkjunker", "deDE")
if L then
	L.rolled_on_you = "%s ist über DICH gerollt" -- PlayerX rolled over you
	L.rolled_from_you = "Ist über %s gerollt" -- (you) Rolled over PlayerX
	L.garbage_dump_message = "DU hast den BOSS getroffen für %s"

	L.electromagnetic_sorting = "Sortierung" -- Short for Electromagnetic Sorting
	L.muffled_doomsplosion = "Bombe absorbiert"
	L.short_fuse = "Bombenhülse Explosion"
	L.incinerator = "Feuerkreise"
end

L = BigWigs:NewBossLocale("Sprocketmonger Lockenstock", "deDE")
if L then
	L.foot_blasters = "Minen"
	L.unstable_shrapnel = "Mine absorbiert"
	L.screw_up = "Bohrer"
	L.screw_up_single = "Bohrer" -- Singular of Drills
	L.sonic_ba_boom = "Raid Schaden"
	L.polarization_generator = "Farben"

	L.polarization_soon = "Baldige Farbe: %s"
	L.polarization_soon_change = "Baldiger FARBWECHSEL: %s"

	L.activate_inventions = "Aktiviert: %s"
	L.blazing_beam = "Strahlen"
	L.rocket_barrage = "Raketen"
	L.mega_magnetize = "Magneten"
	L.jumbo_void_beam = "Große Strahlen"
	L.void_barrage = "Bälle"
	L.everything = "Alles"

	L.under_you_comment = "Unter Dir" -- Implies this setting is for the damage from the ground effect under you
end

L = BigWigs:NewBossLocale("The One-Armed Bandit", "deDE")
if L then
	L.rewards = "Preise" -- Fabulous Prizes
	L.rewards_desc = "Wenn zwei Walzen eingerastet sind, wird die \"fabelhafte Belohnung\" ausgegeben.\nNachrichten weisen darauf hin, welche ausgegeben wird.\nDie Infobox zeigt an, welche Preise noch verfügbar sind."
	L.deposit_time = "Einwurfzeit:" -- Timer that indicates how long you have left to deposit the tokens.

	L.pay_line = "Münzen"
	L.shock = "Schock"
	L.flame = "Flamme"
	L.coin = "Münze"

	L.withering_flames = "Flammen" -- Short for Withering Flames

	L.cheat = "Aktiviert: %s" -- Cheat: Coils, Cheat: Debuffs, Cheat: Raid Damage, Cheat: Final Cast
	L.linked_machines = "Spulen"
	L.linked_machine = "Spule" -- Singular of Coils
	L.hot_hot_heat = "Heiße Debuffs"
	L.explosive_jackpot = "Letzter Zauber"
end

L = BigWigs:NewBossLocale("Mug'Zee, Heads of Security", "deDE")
if L then
	L.earthshaker_gaol = "Gefängnisse"
	L.frostshatter_boots = "Froststiefel" -- Short for Frostshatter Boots
	L.frostshatter_spear = "Frostspeere" -- Short for Frostshatter Spears
	L.stormfury_finger_gun = "Fingerpistole" -- Short for Stormfury Finger Gun
	L.molten_gold_knuckles = "Tank Frontal"
	L.unstable_crawler_mines = "Minen"
	L.goblin_guided_rocket = "Rakete"
	L.double_whammy_shot = "Tank Soak"
	L.electro_shocker = "Schocker"
end

L = BigWigs:NewBossLocale("Chrome King Gallywix", "deDE")
if L then
	L.story_phase_trigger = "Was? Ihr glaubt, Ihr hättet gewonnen?" -- What, you think you won? Nah, I got somethin' else for ya.

	L.scatterblast_canisters = "Kegel Soak"
	L.fused_canisters = "Gruppen Soaks"
	L.tick_tock_canisters = "Soaks"
	L.total_destruction = "ZERSTÖRUNG!"

	L.duds = "Blindgänger" -- Short for 1500-Pound "Dud"
	L.all_duds_detontated = "Alle Blindgänger detoniert!"
	L.duds_remaining = "%d Blindgänger übrig" -- 1 Dud Remains | 2 Duds Remaining
	L.duds_soak = "Soak Blindgänger (%d übrig)"
end

-- Manaforge Omega

L = BigWigs:NewBossLocale("Plexus Sentinel", "deDE")
if L then
	L.cleanse_the_chamber = "Wand"
end

L = BigWigs:NewBossLocale("Loom'ithar", "deDE")
if L then
	L.lair_weaving = "Netze" -- Webs that spawn on the edge of the room
	L.infusion_pylons = "Pylonen" -- Short for Infusion Pylons
end

L = BigWigs:NewBossLocale("Soulbinder Naazindhri", "deDE")
if L then
	L.voidblade_ambush = "Hinterhalt" -- Short for Voidblade Ambush
	L.soulfray_annihilation = "Linien" -- Lines that shoot out an orb along that path
	L.soulfray_annihilation_single = "Linie" -- Single from Lines
	L.remaining_adds = "Verbleibende Adds" -- All remaining adds from Soul Calling spawn
end

L = BigWigs:NewBossLocale("Forgeweaver Araz", "deDE")
if L then
	L.invoke_collector = "Sammler" -- Short for Arcane Collector
end

L = BigWigs:NewBossLocale("Fractillus", "deDE")
if L then
	L.crystalline_shockwave = "Wände"
	L.shattershell = "Brechen"
	L.shockwave_slam = "Tank Wand"
	L.nexus_shrapnel = "Schrapnell landet"
	L.crystal_lacerations = "Blutung"
end

L = BigWigs:NewBossLocale("Nexus-King Salhadaar", "deDE")
if L then
	L.fractal_images = "Drachen"
	L.oath_bound_removed_dose = "1x Eidgebunden entfernt"
	L.behead = "Klauen" -- Claws of a dragon
	L.netherbreaker = "Zirkel"
	L.galaxy_smash = "Schmettern" -- Short for Galactic Smash, and multiple of them.
	L.starkiller_swing = "Sternentöter" -- Short for Starkiller Swing, and multiple of them.
	L.vengeful_oath = "Geister"
end

L = BigWigs:NewBossLocale("Dimensius, the All-Devouring", "deDE")
if L then
	L.gravity = "Gravitation" -- Short for Reverse Gravity
	L.extinction = "Fragment" -- Dimensius hurls a fragment of a broken world
	L.slows = "Verlangsamungen"
	L.slow = "Verlangsamung" -- Singular of Slows
	L.mass_destruction = "Linien"
	L.mass_destruction_single = "Linie"
	L.stardust_nova = "Nova" -- Short for Stardust Nova
	L.extinguish_the_stars = "Sterne" -- Short for Extinguish the Stars
	L.darkened_sky = "Ringe"
	L.cosmic_collapse = "Tank Anziehung"
	L.cosmic_collapse_easy = "Tank Schmettern"
	L.soaring_reshii = "Fliegen verfügbar" -- On the timer for when flying is available

	L.left_living_mass = "Lebendige Masse (Links)"
	L.right_living_mass = "Lebendige Masse (Rechts)"

	L.soaring_reshii_monster_yell = "Gut gekämpft bisher." -- [CHAT_MSG_MONSTER_YELL] You've done well so far. Surprising. But we're not done yet.#Xal'atath###Meeresflask##0#0##0#256#nil#0#false#false#false#false",
	L.weakened_soon_monster_yell = "Wir müssen zuschlagen!" -- [CHAT_MSG_MONSTER_YELL] We must strike--now!#Xal'atath###Xal'atath##0#0##0#4873#nil#0#false#false#false#false",
end

-- Nerub-ar Palace

L = BigWigs:NewBossLocale("Ulgrax the Devourer", "deDE")
if L then
	L.carnivorous_contest_pull = "Heranziehen"
	L.chunky_viscera_message = "Boss füttern! (Spezialaktionsbutton)"
end

L = BigWigs:NewBossLocale("The Bloodbound Horror", "deDE")
if L then
	L.gruesome_disgorge_debuff = "Phasenverschiebung"
	L.grasp_from_beyond = "Tentakel"
	L.grasp_from_beyond_say = "Tentakel"
	L.bloodcurdle = "Verteilen"
	L.bloodcurdle_on_you = "Verteilen" -- Singular of Spread
	L.goresplatter = "Weglaufen"
end

L = BigWigs:NewBossLocale("Rasha'nan", "deDE")
if L then
	L.spinnerets_strands = "Stränge"
	L.enveloping_webs = "Gespinste"
	L.enveloping_web_say = "Gespinst" -- Singular of Webs
	L.erosive_spray = "Spucke"
	L.caustic_hail = "Nächste Position"
end

L = BigWigs:NewBossLocale("Broodtwister Ovi'nax", "deDE")
if L then
	L.sticky_web = "Netze"
	L.sticky_web_say = "Netz" -- Singular of Webs
	L.infest_message = "Wirkt Infizieren auf DICH!"
	L.infest_say = "Parasiten"
	L.experimental_dosage = "Ei schlüpft"
	L.experimental_dosage_say = "Ei schlüpft"
	L.ingest_black_blood = "Nächster Kanister"
	L.unstable_infusion = "Wirbel"

	L.custom_on_experimental_dosage_marks = "Experimentelle Dosierung Zuweisungen"
	L.custom_on_experimental_dosage_marks_desc = "Weist den von 'Experimentelle Dosierung' betroffenen Spielern {rt6}{rt4}{rt3}{rt7} mit der Priorität Nahkampf > Fernkampf > Heiler zu. Betrifft Sagen- und Ziel-Nachrichten."

	L.volatile_concoction_explosion_desc = "Zeigt eine Zielleiste für den Debuff von Instabiles Gebräu."
end

L = BigWigs:NewBossLocale("Nexus-Princess Ky'veza", "deDE")
if L then
	L.assasination = "Phantome"
	L.twiligt_massacre = "Rennen"
	L.nexus_daggers = "Dolche"
end

L = BigWigs:NewBossLocale("The Silken Court", "deDE")
if L then
	L.skipped_cast = "%s (%d) übersprungen"
	L.intermission_trigger = "Gipfel der Macht!" -- Skeinspinner Takazj 100 energy yell

	L.venomous_rain = "Regen"
	L.burrowed_eruption = "Eingraben"
	L.stinging_swarm = "Debuffs entfernen"
	L.strands_of_reality = "Frontal [S]" -- S for Skeinspinner Takazj
	L.strands_of_reality_message = "Frontal [Strangspinnerin Takazj]"
	L.impaling_eruption = "Frontal [A]" -- A for Anub'arash
	L.impaling_eruption_message = "Frontal [Anub'arash]"
	L.entropic_desolation = "Rausrennen"
	L.cataclysmic_entropy = "Großer Knall" -- Interrupt before it casts
	L.spike_eruption = "Stacheln"
	L.unleashed_swarm = "Schwarm"
	L.void_degeneration = "Blaue Kugel"
	L.burning_rage = "Rote Kugel"
end

L = BigWigs:NewBossLocale("Queen Ansurek", "deDE")
if L then
	L.stacks_onboss = "%dx %s auf dem BOSS"

	L.reactive_toxin = "Toxine"
	L.reactive_toxin_say = "Toxin"
	L.venom_nova = "Nova"
	L.web_blades = "Klingen"
	L.silken_tomb = "Wurzeln" -- Raid being rooted in place
	L.wrest = "Heranziehen"
	L.royal_condemnation = "Fesseln"
	L.frothing_gluttony = "Ring"

	L.stage_two_end_message_storymode = "Lauft in das Portal"
end

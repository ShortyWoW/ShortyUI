-- Khaz Algar

local L = BigWigs:NewBossLocale("Aggregation of Horrors", "frFR")
if L then
	L.void_rocks = "Rochers du Vide" -- Plural of Void Rock (452379)
end

L = BigWigs:NewBossLocale("Reshanor, The Untethered", "frFR")
if L then
	L.run = "Courrez dans le portail et cliquez sur l'extra bouton"
end

-- Liberation of Undermine

L = BigWigs:NewBossLocale("Cauldron of Carnage", "frFR")
if L then
	L.custom_on_fade_out_bars = "Masquage des barres"
	L.custom_on_fade_out_bars_desc = "Masque les barres qui appartiennent au boss qui est hors de portée."

	L.bomb_explosion = "Explosion de bombe"
	L.bomb_explosion_desc = "Affiche un timer pour l'explosion des bombes."

	L.eruption_stomp = "Piétinement" -- Short for Eruption Stomp
	L.thunderdrum_salvo = "Salve" -- Short for Thunderdrum Salvo

	L.static_charge_high = "%d - Vous vous déplacez trop"
end

L = BigWigs:NewBossLocale("Rik Reverb", "frFR")
if L then
	L.amplification = "Amplificateur"
	L.echoing_chant = "Échos"
	L.faulty_zap = "Décharges"
	L.sparkblast_ignition = "Ignition"
end

L = BigWigs:NewBossLocale("Stix Bunkjunker", "frFR")
if L then
	L.rolled_on_you = "%s vous a roulé dessus" -- PlayerX rolled over you
	L.rolled_from_you = "Vous avez roulé sur %s" -- (you) Rolled over PlayerX
	L.garbage_dump_message = "Vous avez frappé le boss pour %s"

	L.electromagnetic_sorting = "Tri" -- Short for Electromagnetic Sorting
	L.muffled_doomsplosion = "Explosion fatale étouffée"
	L.short_fuse = "Explosion de crabombe"
	L.incinerator = "Cercles de feu"
end

L = BigWigs:NewBossLocale("Sprocketmonger Lockenstock", "frFR")
if L then
	L.foot_blasters = "Mines"
	L.unstable_shrapnel = "Mine absorbée"
	L.screw_up = "Foreuses"
	L.screw_up_single = "Foreuse" -- Singular of Drills
	L.sonic_ba_boom = "Dégâts sur le raid"
	L.polarization_generator = "Couleurs"

	L.polarization_soon = "Couleurs imminentes : %s"
	L.polarization_soon_change = "CHANGEMENT de couleurs imminent : %s"

	L.activate_inventions = "Activation : %s"
	L.blazing_beam = "Rayons"
	L.rocket_barrage = "Fusées"
	L.mega_magnetize = "Aimants"
	L.jumbo_void_beam = "Gros rayons"
	L.void_barrage = "Boules"
	L.everything = "Tout"

	L.under_you_comment = "E" -- Implies this setting is for the damage from the ground effect under you
end

L = BigWigs:NewBossLocale("The One-Armed Bandit", "frFR")
if L then
	L.rewards = "Prix" -- Fabulous Prizes
	L.rewards_desc = "Lorsque deux jetons sont verrouillés, un  \"prix fabuleux\" est distribué.\nLes messages vous laisseront savoir lequel a été obtenu.\nLa boîte d'info affichera quels prix sont encore disponibles."
	L.deposit_time = "Temps de dépôt:" -- Timer that indicates how long you have left to deposit the tokens.

	L.pay_line = "Ligne pièces"
	L.shock = "Champ"
	L.flame = "Flamme"
	L.coin = "Pièce"

	L.withering_flames = "Flammes" -- Short for Withering Flames

	L.cheat = "Activation : %s" -- Cheat: Coils, Cheat: Debuffs, Cheat: Raid Damage, Cheat: Final Cast
	L.linked_machines = "Bobines"
	L.linked_machine = "Bobine" -- Singular of Coils
	L.hot_hot_heat = "Débuff châleur"
	L.explosive_jackpot = "Incantation finale"
end

L = BigWigs:NewBossLocale("Mug'Zee, Heads of Security", "frFR")
if L then
	L.earthshaker_gaol = "Prisons"
	L.frostshatter_boots = "Bottes de givre" -- Short for Frostshatter Boots
	L.frostshatter_spear = "Lances de givre" -- Short for Frostshatter Spears
	L.stormfury_finger_gun = "Doigt-pistolet" -- Short for Stormfury Finger Gun
	L.molten_gold_knuckles = "Frontal Tank"
	L.unstable_crawler_mines = "Mines"
	L.goblin_guided_rocket = "Fusée"
	L.double_whammy_shot = "Tank Soak"
	L.electro_shocker = "Électrochoqueur mod. II"
end

L = BigWigs:NewBossLocale("Chrome King Gallywix", "frFR")
if L then
	L.story_phase_trigger = "Vous pensez avoir gagné ?" -- What, you think you won? Nah, I got somethin' else for ya.

	L.scatterblast_canisters = "Cone Soak"
	L.fused_canisters = "Groupe Soaks"
	L.tick_tock_canisters = "Soaks"
	L.total_destruction = "DESTRUCTION !"

	L.duds = "Obus" -- Short for 1500-Pound "Dud"
	L.all_duds_detontated = "Tous les obus ont détonné !"
	L.duds_remaining = "%d |4Obus restant:Obus restants;" -- 1 Dud Remains | 2 Duds Remaining
	L.duds_soak = "Soak Obus (%d |4restant:restants;)"
end

-- Manaforge Omega

L = BigWigs:NewBossLocale("Plexus Sentinel", "frFR")
if L then
	--L.cleanse_the_chamber = "Wall"
end

L = BigWigs:NewBossLocale("Loom'ithar", "frFR")
if L then
	L.lair_weaving = "Toiles" -- Webs that spawn on the edge of the room
	L.infusion_pylons = "Pylônes" -- Short for Infusion Pylons
end

L = BigWigs:NewBossLocale("Soulbinder Naazindhri", "frFR")
if L then
	L.voidblade_ambush = "Embuscade" -- Short for Voidblade Ambush
	L.soulfray_annihilation = "Lignes" -- Lines that shoot out an orb along that path
	L.soulfray_annihilation_single = "Ligne" -- Single from Lines
	L.remaining_adds = "Adds restants" -- All remaining adds from Soul Calling spawn
end

L = BigWigs:NewBossLocale("Forgeweaver Araz", "frFR")
if L then
	L.invoke_collector = "Collecteur" -- Short for Arcane Collector
end

L = BigWigs:NewBossLocale("Fractillus", "frFR")
if L then
	L.crystalline_shockwave = "Murs"
	L.shattershell = "Casser"
	L.shockwave_slam = "Mur Tank"
	L.nexus_shrapnel = "Éclats atterrissent"
	L.crystal_lacerations = "Saignement"
end

L = BigWigs:NewBossLocale("Nexus-King Salhadaar", "frFR")
if L then
	L.fractal_images = "Dragons"
	L.oath_bound_removed_dose = "1x Lien par serment enlevé"
	L.behead = "Griffes" -- Claws of a dragon
	L.netherbreaker = "Cercles"
	L.galaxy_smash = "Chocs" -- Short for Galactic Smash, and multiple of them.
	L.starkiller_swing = "Fléaux stellaires" -- Short for Starkiller Swing, and multiple of them.
	L.vengeful_oath = "Esprits"
end

L = BigWigs:NewBossLocale("Dimensius, the All-Devouring", "frFR")
if L then
	L.gravity = "Gravité" -- Short for Reverse Gravity
	L.extinction = "Fragment" -- Dimensius hurls a fragment of a broken world
	L.slows = "Ralentissements"
	L.slow = "Ralentissement" -- Singular of Slows
	L.mass_destruction = "Lignes"
	L.mass_destruction_single = "Ligne"
	L.stardust_nova = "Nova" -- Short for Stardust Nova
	L.extinguish_the_stars = "Étoiles" -- Short for Extinguish the Stars
	L.darkened_sky = "Anneaux"
	L.cosmic_collapse = "Attiré sur le Tank"
	L.cosmic_collapse_easy = "Fracasse Tank"
	L.soaring_reshii = "Monture disponible" -- On the timer for when flying is available

	L.left_living_mass = "Masse vivante (Gauche)"
	L.right_living_mass = "Masse vivante (Droite)"

	L.soaring_reshii_monster_yell = "Vous vous en sortez bien." -- [CHAT_MSG_MONSTER_YELL] You've done well so far. Surprising. But we're not done yet.#Xal'atath###Meeresflask##0#0##0#256#nil#0#false#false#false#false",

	L.weakened_soon_monster_yell = "Nous devons frapper maintenant !" -- [CHAT_MSG_MONSTER_YELL] We must strike--now!#Xal'atath###Xal'atath##0#0##0#4873#nil#0#false#false#false#false",
end

-- Nerub-ar Palace

L = BigWigs:NewBossLocale("Ulgrax the Devourer", "frFR")
if L then
	L.carnivorous_contest_pull = "Attraction"
	L.chunky_viscera_message = "Nourrissez le boss ! (Bouton d'action spécial)"
end

L = BigWigs:NewBossLocale("The Bloodbound Horror", "frFR")
if L then
	L.gruesome_disgorge_debuff = "Déphasage"
	L.grasp_from_beyond = "Tentacule"
	L.grasp_from_beyond_say = "Tentacules"
	L.bloodcurdle = "Écartez-vous"
	L.bloodcurdle_on_you = "Écartez-vous" -- Singular of Spread
	L.goresplatter = "Courez"
end

L = BigWigs:NewBossLocale("Rasha'nan", "frFR")
if L then
	L.spinnerets_strands = "Brins"
	L.enveloping_webs = "Toiles"
	L.enveloping_web_say = "Toile" -- Singular of Webs
	L.erosive_spray = "Écartez-vous"
	L.caustic_hail = "Prochaine position"
end

L = BigWigs:NewBossLocale("Broodtwister Ovi'nax", "frFR")
if L then
	L.sticky_web = "Toile"
	L.sticky_web_say = "Toiles" -- Singular of Webs
	L.infest_message = "Lance Infester sur vous !"
	L.infest_say = "Parasites"
	L.experimental_dosage = "Éclosion d'œufs"
	L.experimental_dosage_say = "Casseur d'œufs"
	L.ingest_black_blood = "Prochain conteneur"
	L.unstable_infusion = "Tourbillons"

	L.custom_on_experimental_dosage_marks = "Assignements Dosage expérimental"
	L.custom_on_experimental_dosage_marks_desc = "Assigne des joueurs affectés par 'Dosage expérimental' à {rt6}{rt4}{rt3}{rt7} avec un priorité mélée > distant > soigneur. Affecte les messages dire et cible."

	L.volatile_concoction_explosion_desc = "Affiche une barre pour l'affaiblissement Décoction volatile."
end

L = BigWigs:NewBossLocale("Nexus-Princess Ky'veza", "frFR")
if L then
	L.assasination = "Fantômes"
	L.twiligt_massacre = "Dashes"
	L.nexus_daggers = "Dagues"
end

L = BigWigs:NewBossLocale("The Silken Court", "frFR")
if L then
	L.skipped_cast = "Incantation passée %s (%d)"
	L.intermission_trigger = "Le pic de la puissance !" -- Skeinspinner Takazj 100 energy yell

	L.venomous_rain = "Pluie"
	L.burrowed_eruption = "Enfouissement"
	L.stinging_swarm = "Dispel debuffs"
	L.strands_of_reality = "Frontal Takazj" -- S for Skeinspinner Takazj
	L.strands_of_reality_message = "Frontal Takazj"
	L.impaling_eruption = "Frontal Anub'arash" -- A for Anub'arash
	L.impaling_eruption_message = "Frontal Anub'arash"
	L.entropic_desolation = "S'enfuir"
	L.cataclysmic_entropy = "Grosse explosion" -- Interrupt before it casts
	L.spike_eruption = "Pointes"
	L.unleashed_swarm = "Essaim"
	L.void_degeneration = "Orbe bleu"
	L.burning_rage = "Orbe rouge"
end

L = BigWigs:NewBossLocale("Queen Ansurek", "frFR")
if L then
	L.stacks_onboss = "%dx %s sur le Boss"

	L.reactive_toxin = "Toxines"
	L.reactive_toxin_say = "Toxine"
	L.venom_nova = "Nova"
	L.web_blades = "Lames"
	L.silken_tomb = "Immobilisation" -- Raid being rooted in place
	L.wrest = "Attraction"
	L.royal_condemnation = "Entraves"
	L.frothing_gluttony = "Anneau"

	L.stage_two_end_message_storymode = "Courez vers le portail"
end

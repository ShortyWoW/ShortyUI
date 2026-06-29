-- Khaz Algar

local L = BigWigs:NewBossLocale("Aggregation of Horrors", "esMX")
if L then
	L.void_rocks = "Piedras del Vacío" -- Plural of Void Rock (452379)
end

L = BigWigs:NewBossLocale("Reshanor, The Untethered", "esMX")
if L then
	L.run = "Corre al portal y presiona el botón de acción extra"
end

-- Liberation of Undermine

L = BigWigs:NewBossLocale("Cauldron of Carnage", "esMX")
if L then
	L.custom_on_fade_out_bars = "Barras que desaparecen"
	L.custom_on_fade_out_bars_desc = "Barras que desaparecen del jefe que esta fuera de rango."

	L.bomb_explosion = "Explosión de la bomba"
	L.bomb_explosion_desc = "Muestra el tiempo de explosión de la bomba."

	L.eruption_stomp = "Pisotón" -- Short for Eruption Stomp
	L.thunderdrum_salvo = "Salva" -- Short for Thunderdrum Salvo

	L.static_charge_high = "%d - Te estás moviendo mucho"
end

L = BigWigs:NewBossLocale("Rik Reverb", "esMX")
if L then
	L.amplification = "Amplificadores"
	L.echoing_chant = "Ecos Resonantes"
	L.faulty_zap = "Voltajes Persistentes"
	L.sparkblast_ignition = "Barriles"
end

L = BigWigs:NewBossLocale("Stix Bunkjunker", "esMX")
if L then
	L.rolled_on_you = "%s Te atropello A TI" -- PlayerX rolled over you
	L.rolled_from_you = "Atropellaste a %s" -- (you) Rolled over PlayerX
	L.garbage_dump_message = "Le pegaste al jefe por %s"

	L.electromagnetic_sorting = "Clasificación" -- Short for Electromagnetic Sorting
	L.muffled_doomsplosion = "Bomba explotada"
	L.short_fuse = "Explosión de Caparabomba"
	L.incinerator = "Circulos de fuego"
end

L = BigWigs:NewBossLocale("Sprocketmonger Lockenstock", "esMX")
if L then
	L.foot_blasters = "Minas"
	L.unstable_shrapnel = "Mina Pisada"
	L.screw_up = "Taladros"
	L.screw_up_single = "Taladro" -- Singular of Drills
	L.sonic_ba_boom = "Daño de banda"
	L.polarization_generator = "Colors"

	L.polarization_soon = "Cambio de color: %s"
	L.polarization_soon_change = "Cambio de color PRONTO: %s"

	L.activate_inventions = "Activando: %s"
	L.blazing_beam = "Rayos"
	L.rocket_barrage = "Misiles"
	L.mega_magnetize = "Imanes"
	L.jumbo_void_beam = "Rayos GRANDES"
	L.void_barrage = "Pelotas"
	L.everything = "TODO"

	L.under_you_comment = "Bajo tuyo" -- Implies this setting is for the damage from the ground effect under you
end

L = BigWigs:NewBossLocale("The One-Armed Bandit", "esMX")
if L then
	L.rewards = "Premios" -- Fabulous Prizes
	L.rewards_desc = "Cuando dos fichas se entregan, el \"Premio Fabuloso\" es repartido.\nMensajes te harán saber que premio ha sido entregado.\nEl cuadro de información te mostrará que premios aún están disponibles."
	L.deposit_time = "Tiempo para depositar:" -- Timer that indicates how long you have left to deposit the tokens.

	L.pay_line = "Monedas"
	L.shock = "Rayo"
	L.flame = "Llama"
	L.coin = "Moneda"

	L.withering_flames = "Llamas" -- Short for Withering Flames

	L.cheat = "Activando: %s" -- Cheat: Coils, Cheat: Debuffs, Cheat: Raid Damage, Cheat: Final Cast
	L.linked_machines = "Bobinas"
	L.linked_machine = "Bobina" -- Singular of Coils
	L.hot_hot_heat = "Calor Hipercaliente"
	L.explosive_jackpot = "Gran explosión"
end

L = BigWigs:NewBossLocale("Mug'Zee, Heads of Security", "esMX")
if L then
	L.earthshaker_gaol = "Prisiones"
	L.frostshatter_boots = "Botas de hielo" -- Short for Frostshatter Boots
	L.frostshatter_spear = "Lanzas de hielo" -- Short for Frostshatter Spears
	L.stormfury_finger_gun = "Dedos de rayo" -- Short for Stormfury Finger Gun
	L.molten_gold_knuckles = "Frontal de tanque"
	L.unstable_crawler_mines = "Minas"
	L.goblin_guided_rocket = "Misil grande"
	L.double_whammy_shot = "Detrás del tanque"
	L.electro_shocker = "Electrificador"
end

L = BigWigs:NewBossLocale("Chrome King Gallywix", "esMX")
if L then
	--L.story_phase_trigger = "What, you think you won?" -- What, you think you won? Nah, I got somethin' else for ya.

	L.scatterblast_canisters = "Cono frontal"
	L.fused_canisters = "Soak de grupo"
	L.tick_tock_canisters = "Soaks"
	L.total_destruction = "DESTRUCCIÓN!"

	L.duds = "DÑD" -- Short for 1500-Pound "Dud"
	L.all_duds_detontated = "TODAS las DÑD han sido explotadas!"
	L.duds_remaining = "%d |4DÑD faltante:DÑD faltantes;" -- 1 Dud Remains | 2 Duds Remaining
	L.duds_soak = "Pisa DÑD (%d vivas aún)"
end

-- Manaforge Omega

L = BigWigs:NewBossLocale("Plexus Sentinel", "esMX")
if L then
	--L.cleanse_the_chamber = "Wall"
end

L = BigWigs:NewBossLocale("Loom'ithar", "esMX")
if L then
	L.lair_weaving = "Telarañas" -- Webs that spawn on the edge of the room
	L.infusion_pylons = "Pilones" -- Short for Infusion Pylons
end

L = BigWigs:NewBossLocale("Soulbinder Naazindhri", "esMX")
if L then
	L.voidblade_ambush = "Emboscada" -- Short for Voidblade Ambush
	L.soulfray_annihilation = "Líneas" -- Lines that shoot out an orb along that path
	L.soulfray_annihilation_single = "Línea" -- Single from Lines
	L.remaining_adds = "Almas Faltantes" -- All remaining adds from Soul Calling spawn
end

L = BigWigs:NewBossLocale("Forgeweaver Araz", "esMX")
if L then
	L.invoke_collector = "Recolector" -- Short for Arcane Collector
end

L = BigWigs:NewBossLocale("Fractillus", "esMX")
if L then
	L.crystalline_shockwave = "Muro"
	L.shattershell = "Destruir"
	L.shockwave_slam = "Muro de Tanque"
	L.nexus_shrapnel = "Lluvia de Metralla"
	L.crystal_lacerations = "Sangrado"
end

L = BigWigs:NewBossLocale("Nexus-King Salhadaar", "esMX")
if L then
	L.fractal_images = "Imágenes"
	L.oath_bound_removed_dose = "1x Atado al juramento removido"
	L.behead = "Garras" -- Claws of a dragon
	L.netherbreaker = "Círculos"
	L.galaxy_smash = "Machaque" -- Short for Galactic Smash, and multiple of them.
	L.starkiller_swing = "Mataestrellas" -- Short for Starkiller Swing, and multiple of them.
	L.vengeful_oath = "Espíritus"
end

L = BigWigs:NewBossLocale("Dimensius, the All-Devouring", "esMX")
if L then
	L.gravity = "Gravedad" -- Short for Reverse Gravity
	L.extinction = "Fragmento" -- Dimensius hurls a fragment of a broken world
	L.slows = "Ralentizaciones"
	L.slow = "Ralentización" -- Singular of Slows
	L.mass_destruction = "Líneas"
	L.mass_destruction_single = "Línea"
	L.stardust_nova = "Nova" -- Short for Stardust Nova
	L.extinguish_the_stars = "Estrellas" -- Short for Extinguish the Stars
	L.darkened_sky = "Anillos"
	L.cosmic_collapse = "Agarre de Tanque"
	L.cosmic_collapse_easy = "Golpe de Tanque"
	L.soaring_reshii = "Montura Disponible" -- On the timer for when flying is available

	L.left_living_mass = "Masa Viviente (Izquierda)"
	L.right_living_mass = "Masa Viviente (Derecha)"

	--L.soaring_reshii_monster_yell = "You've done well so far." -- [CHAT_MSG_MONSTER_YELL] You've done well so far. Surprising. But we're not done yet.#Xal'atath###Meeresflask##0#0##0#256#nil#0#false#false#false#false",

	--L.weakened_soon_monster_yell = "We must strike--now!" -- [CHAT_MSG_MONSTER_YELL] We must strike--now!#Xal'atath###Xal'atath##0#0##0#4873#nil#0#false#false#false#false",
end

-- Nerub-ar Palace

L = BigWigs:NewBossLocale("Ulgrax the Devourer", "esMX")
if L then
	--L.carnivorous_contest_pull = "Pull In"
	--L.chunky_viscera_message = "Feed Boss! (Special Action Button)"
end

L = BigWigs:NewBossLocale("The Bloodbound Horror", "esMX")
if L then
	--L.gruesome_disgorge_debuff = "Phase Shift"
	--L.grasp_from_beyond = "Tentacles"
	--L.grasp_from_beyond_say = "Tentacles"
	--L.bloodcurdle = "Spreads"
	--L.bloodcurdle_on_you = "Spread" -- Singular of Spread
	--L.goresplatter = "Run Away"
end

L = BigWigs:NewBossLocale("Rasha'nan", "esMX")
if L then
	--L.spinnerets_strands = "Strands"
	--L.enveloping_webs = "Webs"
	--L.enveloping_web_say = "Web" -- Singular of Webs
	--L.erosive_spray = "Spray"
	--L.caustic_hail = "Next Position"
end

L = BigWigs:NewBossLocale("Broodtwister Ovi'nax", "esMX")
if L then
	--L.sticky_web = "Webs"
	--L.sticky_web_say = "Web" -- Singular of Webs
	--L.infest_message = "Casting Infest on YOU!"
	--L.infest_say = "Parasites"
	--L.experimental_dosage = "Egg Breaks"
	--L.experimental_dosage_say = "Egg Break"
	--L.ingest_black_blood = "Next Container"
	--L.unstable_infusion = "Swirls"

	--L.custom_on_experimental_dosage_marks = "Experimental Dosage assignments"
	--L.custom_on_experimental_dosage_marks_desc = "Assign players affected by 'Experimental Dosage' to {rt6}{rt4}{rt3}{rt7} with a melee > ranged > healer priority. Affects Say and Target messages."

	--L.volatile_concoction_explosion_desc = "Show a target bar for the Volatile Concoction debuff."
end

L = BigWigs:NewBossLocale("Nexus-Princess Ky'veza", "esMX")
if L then
	--L.assasination = "Phantoms"
	--L.twiligt_massacre = "Dashes"
	--L.nexus_daggers = "Daggers"
end

L = BigWigs:NewBossLocale("The Silken Court", "esMX")
if L then
	--L.skipped_cast = "Skipped %s (%d)"
	--L.intermission_trigger = "Apex of power!" -- Skeinspinner Takazj 100 energy yell

	--L.venomous_rain = "Rain"
	--L.burrowed_eruption = "Burrow"
	--L.stinging_swarm = "Dispel Debuffs"
	--L.strands_of_reality = "Frontal [S]" -- S for Skeinspinner Takazj
	--L.strands_of_reality_message = "Frontal [Skeinspinner Takazj]"
	--L.impaling_eruption = "Frontal [A]" -- A for Anub'arash
	--L.impaling_eruption_message = "Frontal [Anub'arash]"
	--L.entropic_desolation = "Run Out"
	--L.cataclysmic_entropy = "Big Boom" -- Interrupt before it casts
	--L.spike_eruption = "Spikes"
	--L.unleashed_swarm = "Swarm"
	--L.void_degeneration = "Blue Orb"
	--L.burning_rage = "Red Orb"
end

L = BigWigs:NewBossLocale("Queen Ansurek", "esMX")
if L then
	--L.stacks_onboss = "%dx %s on BOSS"

	--L.reactive_toxin = "Toxins"
	--L.reactive_toxin_say = "Toxin"
	--L.venom_nova = "Nova"
	--L.web_blades = "Blades"
	--L.silken_tomb = "Roots" -- Raid being rooted in place
	--L.wrest = "Pull In"
	--L.royal_condemnation = "Shackles"
	--L.frothing_gluttony = "Ring"

	--L.stage_two_end_message_storymode = "Run into the portal"
end

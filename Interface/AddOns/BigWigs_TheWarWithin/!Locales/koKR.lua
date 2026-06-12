-- Khaz Algar

local L = BigWigs:NewBossLocale("Aggregation of Horrors", "koKR")
if L then
	L.void_rocks = "공허 바위" -- Plural of Void Rock (452379)
end

L = BigWigs:NewBossLocale("Reshanor, The Untethered", "koKR")
if L then
	L.run = "포털로 이동해 엑스트라 버튼을 누르세요."
end

-- Liberation of Undermine

L = BigWigs:NewBossLocale("Cauldron of Carnage", "koKR")
if L then
	L.custom_on_fade_out_bars = "바 투명도 감소"
	L.custom_on_fade_out_bars_desc = "범위를 벗어난 보스 관련 바의 투명도를 낮춥니다."

	L.bomb_explosion = "폭탄 폭발"
	L.bomb_explosion_desc = "폭탄이 폭파되기까지의 타이머 표시."

	L.eruption_stomp = "분출" -- Short for Eruption Stomp
	L.thunderdrum_salvo = "바닥" -- Short for Thunderdrum Salvo

	L.static_charge_high = "%d - 너무 많이 움직입니다."
end

L = BigWigs:NewBossLocale("Rik Reverb", "koKR")
if L then
	L.amplification = "증폭기"
	L.echoing_chant = "메아리"
	L.faulty_zap = "감전"
	L.sparkblast_ignition = "배럴"
end

L = BigWigs:NewBossLocale("Stix Bunkjunker", "koKR")
if L then
	L.rolled_on_you = "%s 에게 치임" -- PlayerX rolled over you
	L.rolled_from_you = "%s 를 치고감" -- (you) Rolled over PlayerX
	L.garbage_dump_message = "보스에게 %s 피해를 입힘"

	L.electromagnetic_sorting = "분류" -- Short for Electromagnetic Sorting
	L.muffled_doomsplosion = "폭탄 처리됨"
	L.short_fuse = "폭탄 폭발"
	L.incinerator = "소각"
end

L = BigWigs:NewBossLocale("Sprocketmonger Lockenstock", "koKR")
if L then
	L.foot_blasters = "지뢰"
	L.unstable_shrapnel = "지뢰 밟음"
	L.screw_up = "드릴"
	L.screw_up_single = "드릴" -- Singular of Drills
	L.sonic_ba_boom = "공대 피해"
	L.polarization_generator = "극성"

	L.polarization_soon = "곧 극성: %s"
	L.polarization_soon_change = "곧 극성 변환: %s"

	L.activate_inventions = "활성화: %s"
	L.blazing_beam = "광선"
	L.rocket_barrage = "로켓"
	L.mega_magnetize = "자석"
	L.jumbo_void_beam = "강력 광선"
	L.void_barrage = "공허 구슬"
	L.everything = "발명품 활성화" -- ??

	L.under_you_comment = "바닥" -- Implies this setting is for the damage from the ground effect under you
end

L = BigWigs:NewBossLocale("The One-Armed Bandit", "koKR")
if L then
	L.rewards = "경품" -- Fabulous Prizes
	L.rewards_desc = "두개의 토큰이 정해지면, \"환상적인 경품\" 이 나옵니다. \n어떤 경품이 나왔는지 메시지로 알려줍니다.\n정보박스로 어떤 경품이 아직 남았는지 보여줍니다."
	L.deposit_time = "토큰 주입 마무리:" -- Timer that indicates how long you have left to deposit the tokens.

	L.pay_line = "당첨선"
	L.shock = "전격"
	L.flame = "불꽃"
	L.coin = "동전"

	L.withering_flames = "회오리" -- Short for Withering Flames

	L.cheat = "활성화: %s" -- Cheat: Coils, Cheat: Debuffs, Cheat: Raid Damage, Cheat: Final Cast
	L.linked_machines = "감줄"
	L.linked_machine = "감줄" -- Singular of Coils
	L.hot_hot_heat = "불길"
	L.explosive_jackpot = "광폭화"
end

L = BigWigs:NewBossLocale("Mug'Zee, Heads of Security", "koKR")
if L then
	L.earthshaker_gaol = "감옥"
	L.frostshatter_boots = "냉기 장화" -- Short for Frostshatter Boots
	L.frostshatter_spear = "냉기 창" -- Short for Frostshatter Spears
	L.stormfury_finger_gun = "손가락총" -- Short for Stormfury Finger Gun
	L.molten_gold_knuckles = "탱커 전방기"
	L.unstable_crawler_mines = "지뢰"
	L.goblin_guided_rocket = "로켓"
	L.double_whammy_shot = "광선"
	L.electro_shocker = "충격기"
end

L = BigWigs:NewBossLocale("Chrome King Gallywix", "koKR")
if L then
	L.story_phase_trigger = "뭐, 이겼다고 생각해?" -- What, you think you won? Nah, I got somethin' else for ya.

	L.scatterblast_canisters = "브레스 같이맞기"
	L.fused_canisters = "용기 같이맞기"
	L.tick_tock_canisters = "바닥밟기"
	L.total_destruction = "파괴!"

	L.duds = "불발탄" -- Short for 1500-Pound "Dud"
	L.all_duds_detontated = "모든 불발탄 해체완료!"
	L.duds_remaining = "불발탄 %d 개 남음" -- 1 Dud Remains | 2 Duds Remaining
	L.duds_soak = "불발탄 바닥밟기 (%d 개 남음)"
end

-- Manaforge Omega


L = BigWigs:NewBossLocale("Plexus Sentinel", "koKR")
if L then
	L.cleanse_the_chamber = "벽"
end
L = BigWigs:NewBossLocale("Loom'ithar", "koKR")
if L then
	L.lair_weaving = "거미줄" -- Webs that spawn on the edge of the room
	L.infusion_pylons = "수정탑" -- Short for Infusion Pylons
end

L = BigWigs:NewBossLocale("Soulbinder Naazindhri", "koKR")
if L then
	L.voidblade_ambush = "매복" -- Short for Voidblade Ambush
	L.soulfray_annihilation = "보주" -- Lines that shoot out an orb along that path
	L.soulfray_annihilation_single = "레이저" -- Single from Lines
	L.remaining_adds = "남은 추가 몹" -- All remaining adds from Soul Calling spawn
end

L = BigWigs:NewBossLocale("Forgeweaver Araz", "koKR")
if L then
	L.invoke_collector = "수집기" -- Short for Arcane Collector
end

L = BigWigs:NewBossLocale("Fractillus", "koKR")
if L then
	L.crystalline_shockwave = "벽"
	L.shattershell = "제거"
	L.shockwave_slam = "탱커 벽"
	L.nexus_shrapnel = "파편"
	L.crystal_lacerations = "출혈"
end

L = BigWigs:NewBossLocale("Nexus-King Salhadaar", "koKR")
if L then
	L.fractal_images = "환영"
	L.oath_bound_removed_dose = "1x 서약결속 제거됨"
	L.behead = "발톱" -- Claws of a dragon
	L.netherbreaker = "차원문"
	L.galaxy_smash = "강타" -- Short for Galactic Smash, and multiple of them.
	L.starkiller_swing = "별 부수기" -- Short for Starkiller Swing, and multiple of them.
	L.vengeful_oath = "영혼"
end

L = BigWigs:NewBossLocale("Dimensius, the All-Devouring", "koKR")
if L then
	L.gravity = "역중력" -- Short for Reverse Gravity
	L.extinction = "파편" -- Dimensius hurls a fragment of a broken world
	L.slows = "이감"
	L.slow = "이감" -- Singular of Slows
	L.mass_destruction = "라인"
	L.mass_destruction_single = "라인"
	L.stardust_nova = "바닥" -- Short for Stardust Nova
	L.extinguish_the_stars = "별" -- Short for Extinguish the Stars
	L.darkened_sky = "고리"
	L.cosmic_collapse = "탱커 당기기"
	L.cosmic_collapse_easy = "탱커 강타"
	L.soaring_reshii = "비행 가능" -- On the timer for when flying is available

	L.left_living_mass = "살아있는 질량체 (왼쪽)"
	L.right_living_mass = "살아있는 질량체 (오른쪽)"

	L.soaring_reshii_monster_yell = "지금까진 잘했어요." -- [CHAT_MSG_MONSTER_YELL] You've done well so far. Surprising. But we're not done yet.#Xal'atath###Meeresflask##0#0##0#256#nil#0#false#false#false#false",

	L.weakened_soon_monster_yell = "지금 공격해야 해요!" -- [CHAT_MSG_MONSTER_YELL] We must strike--now!#Xal'atath###Xal'atath##0#0##0#4873#nil#0#false#false#false#false",
end

-- Nerub-ar Palace

L = BigWigs:NewBossLocale("Ulgrax the Devourer", "koKR")
if L then
	L.carnivorous_contest_pull = "끌어당김"
	L.chunky_viscera_message = "보스 먹이기! (엑스트라 버튼)"
end

L = BigWigs:NewBossLocale("The Bloodbound Horror", "koKR")
if L then
	L.gruesome_disgorge_debuff = "위상 전환"
	L.grasp_from_beyond = "촉수"
	L.grasp_from_beyond_say = "촉수"
	L.bloodcurdle = "산개"
	L.bloodcurdle_on_you = "산개" -- Singular of Spread
	L.goresplatter = "바닥"
end

L = BigWigs:NewBossLocale("Rasha'nan", "koKR")
if L then
	L.spinnerets_strands = "가닥"
	L.enveloping_webs = "거미줄"
	L.enveloping_web_say = "거미줄" -- Singular of Webs
	L.erosive_spray = "분무"
	L.caustic_hail = "다음 위치"
end

L = BigWigs:NewBossLocale("Broodtwister Ovi'nax", "koKR")
if L then
	L.sticky_web = "거미줄"
	L.sticky_web_say = "거미줄" -- Singular of Webs
	L.infest_message = "당신에게 감염 시전 중!"
	L.infest_say = "기생충"
	L.experimental_dosage = "알 깨기"
	L.experimental_dosage_say = "알 깨기"
	L.ingest_black_blood = "다음 용기"
	L.unstable_infusion = "이감 바닥"

	L.custom_on_experimental_dosage_marks = "실험용 투여제 할당"
	L.custom_on_experimental_dosage_marks_desc = "'실험용 투여제'에 영향을 받는 플레이어를 근접 > 원거리 > 힐러 우선 순위로 {rt6}{rt4}{rt3}{rt7}에 할당합니다. 채팅 및 대상 메시지에 영향을 미칩니다."

	L.volatile_concoction_explosion_desc = "휘발성 혼합물 디버프의 대상 바를 표시합니다."
end

L = BigWigs:NewBossLocale("Nexus-Princess Ky'veza", "koKR")
if L then
	L.assasination = "암살"
	L.twiligt_massacre = "돌진"
	L.nexus_daggers = "단검"
end

L = BigWigs:NewBossLocale("The Silken Court", "koKR")
if L then
	L.skipped_cast = "건너뛴 %s (%d)"
	L.intermission_trigger = "힘의 정점!" -- Skeinspinner Takazj 100 energy yell

	L.venomous_rain = "맹독의 비"
	L.burrowed_eruption = "잠복"
	L.stinging_swarm = "디버프 해제"
	L.strands_of_reality = "전방 [S]" -- S for Skeinspinner Takazj
	L.strands_of_reality_message = "전방 [타래직공 타카즈]"
	L.impaling_eruption = "전방 [A]" -- A for Anub'arash
	L.impaling_eruption_message = "전방 [아눕아라쉬]"
	L.entropic_desolation = "밖으로 도망"
	L.cataclysmic_entropy = "큰 폭발" -- Interrupt before it casts
	L.spike_eruption = "가시"
	L.unleashed_swarm = "무리"
	L.void_degeneration = "파란 구슬"
	L.burning_rage = "빨간 구슬"
end

L = BigWigs:NewBossLocale("Queen Ansurek", "koKR")
if L then
	L.stacks_onboss = "넴드 %dx %s"

	L.reactive_toxin = "독소"
	L.reactive_toxin_say = "독소"
	L.venom_nova = "회오리"
	L.web_blades = "칼날"
	L.silken_tomb = "이동 불가" -- Raid being rooted in place
	L.wrest = "끌어당김"
	L.royal_condemnation = "족쇄"
	L.frothing_gluttony = "고리"

	L.stage_two_end_message_storymode = "포털로 이동"
end

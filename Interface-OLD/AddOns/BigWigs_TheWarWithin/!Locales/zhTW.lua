-- Khaz Algar

local L = BigWigs:NewBossLocale("Aggregation of Horrors", "zhTW")
if L then
	L.void_rocks = "彈幕" -- Plural of Void Rock (452379)
end

L = BigWigs:NewBossLocale("Reshanor, The Untethered", "zhTW")
if L then
	L.run = "去傳送門點擊額外技能"
end

-- Liberation of Undermine

L = BigWigs:NewBossLocale("Cauldron of Carnage", "zhTW")
if L then
	L.custom_on_fade_out_bars = "淡出計時器"
	L.custom_on_fade_out_bars_desc = "淡出顯示超出距離的首領計時條。"

	L.bomb_explosion = "炸彈爆炸"
	L.bomb_explosion_desc = "替炸彈爆炸顯示倒數計時。"

	L.eruption_stomp = "踐踏" -- Short for Eruption Stomp
	L.thunderdrum_salvo = "電圈" -- Short for Thunderdrum Salvo

	L.static_charge_high = "%d - 移動過於頻繁"
end

L = BigWigs:NewBossLocale("Rik Reverb", "zhTW")
if L then
	L.amplification = "增幅器"
	L.echoing_chant = "回音" -- 回音之頌
	L.faulty_zap = "電擊"
	L.sparkblast_ignition = "火花" -- 火花衝擊
end

L = BigWigs:NewBossLocale("Stix Bunkjunker", "zhTW")
if L then
	L.rolled_on_you = "%s 碾了你" -- PlayerX rolled over you
	L.rolled_from_you = "你碾了 %s" -- (you) Rolled over PlayerX
	L.garbage_dump_message = "你對首領造成了 %s 點傷害" -- 視百分比或數值再調整

	L.electromagnetic_sorting = "電磁" -- Short for Electromagnetic Sorting
	L.muffled_doomsplosion = "悶響爆炸" -- 悶響末日爆炸 暫定
	L.short_fuse = "螃蟹爆炸" -- 表意
	L.incinerator = "火圈" -- 火圈/焚化/燒垃圾
end

L = BigWigs:NewBossLocale("Sprocketmonger Lockenstock", "zhTW")
if L then
	L.foot_blasters = "地雷"
	L.unstable_shrapnel = "地雷爆炸" -- 或者 踩雷
	L.screw_up = "鑽頭"
	L.screw_up_single = "鑽頭" -- Singular of Drills
	L.sonic_ba_boom = "音波" --音速轟爆
	L.polarization_generator = "極化"

	L.polarization_soon = "極化：%s"
	L.polarization_soon_change = "即將極化：%s"

	L.activate_inventions = "啟動：%s"
	L.blazing_beam = "光束" --熾炎光束
	L.rocket_barrage = "火箭" --火箭彈幕
	L.mega_magnetize = "磁鐵" --超能磁化
	L.jumbo_void_beam = "虛無光束" --就不改了
	L.void_barrage = "黑球" --虛無彈幕
	L.everything = "組合技" -- 所有發明物/合擊

	L.under_you_comment = "在你腳下" -- Implies this setting is for the damage from the ground effect under you
end

L = BigWigs:NewBossLocale("The One-Armed Bandit", "zhTW")
if L then
	L.rewards = "酷炫獎勵" -- Fabulous Prizes
	L.rewards_desc = "投入二枚代幣後會立即發放「酷炫獎勵」，訊息將會顯示你獲得的獎勵，訊息盒則顯示你尚未領取過的獎勵。"
	L.deposit_time = "投幣時限：" -- Timer that indicates how long you have left to deposit the tokens.

	L.pay_line = "錢幣" -- 籌碼？滾錢幣
	L.shock = "電擊"
	L.flame = "烈焰"
	L.coin = "硬幣" -- 應該是獎勵的硬幣

	L.withering_flames = "烈焰" -- Short for Withering Flames

	L.cheat = "啟動：%s" -- Cheat: Coils, Cheat: Debuffs, Cheat: Raid Damage, Cheat: Final Cast
	L.linked_machines = "線圈"
	L.linked_machine = "線圈" -- Singular of Coils
	L.hot_hot_heat = "燒燙燙"
	L.explosive_jackpot = "火爆大獎"
end

L = BigWigs:NewBossLocale("Mug'Zee, Heads of Security", "zhTW")
if L then
	L.earthshaker_gaol = "土牢"
	L.frostshatter_boots = "冰靴" -- Short for Frostshatter Boots 或者乾脆叫「腳滑」吧
	L.frostshatter_spear = "冰矛" -- Short for Frostshatter Spears
	L.stormfury_finger_gun = "手指槍" -- Short for Stormfury Finger Gun 指槍/閃電/射線
	L.molten_gold_knuckles = "坦克擊飛"
	L.unstable_crawler_mines = "地雷"
	L.goblin_guided_rocket = "火箭" --或分攤
	L.double_whammy_shot = "坦克擋線" --雙惡射擊
	L.electro_shocker = "震擊者"
end

L = BigWigs:NewBossLocale("Chrome King Gallywix", "zhTW")
if L then
	--L.story_phase_trigger = "What, you think you won?" -- What, you think you won? Nah, I got somethin' else for ya.

	L.scatterblast_canisters = "碎爆分攤" --碎爆罐
	L.fused_canisters = "融合罐分攤"
	L.tick_tock_canisters = "嘀答罐分攤"
	L.total_destruction = "毀滅！"

	L.duds = "爆彈" -- Short for 1500-Pound "Dud" dud是啞彈但手冊是爆彈
	L.all_duds_detontated = "爆彈已全部引爆！"
	L.duds_remaining = "剩餘 %d 個爆彈"
	--L.duds_soak = "Soak Duds (%d left)"
end

-- Manaforge Omega

L = BigWigs:NewBossLocale("Plexus Sentinel", "zhTW")
if L then
	--L.cleanse_the_chamber = "Wall"
end

L = BigWigs:NewBossLocale("Loom'ithar", "zhTW")
if L then
	L.lair_weaving = "織網" -- Webs that spawn on the edge of the room
	L.infusion_pylons = "注能" -- Short for Infusion Pylons 注能塔
end

L = BigWigs:NewBossLocale("Soulbinder Naazindhri", "zhTW")
if L then
	L.voidblade_ambush = "伏擊" -- Short for Voidblade Ambush
	L.soulfray_annihilation = "射線" -- 傷魂滅殺/出球/射線
	L.soulfray_annihilation_single = "射線" -- 傷魂滅殺/出球/射線
	L.remaining_adds = "剩餘增援" -- 剩餘增援來襲
end

L = BigWigs:NewBossLocale("Forgeweaver Araz", "zhTW")
if L then
	L.invoke_collector = "收集器" -- Short for Arcane Collector
end

L = BigWigs:NewBossLocale("Fractillus", "zhTW")
if L then
	L.crystalline_shockwave = "水晶牆" -- 出牆
	L.shattershell = "破牆"
	L.shockwave_slam = "坦克牆"
	L.nexus_shrapnel = "碎片落地" -- 粉碎反擊小圈
	L.crystal_lacerations = "流血"
end

L = BigWigs:NewBossLocale("Nexus-King Salhadaar", "zhTW")
if L then
	L.fractal_images = "飛龍"
	L.oath_bound_removed_dose = "移除一層誓言"
	L.behead = "利爪" -- Claws of a dragon 斬首
	L.netherbreaker = "大圈"
	L.galaxy_smash = "撞擊" -- 星河撞擊
	L.starkiller_swing = "弒星" -- 弒星揮擊，或者射線
	L.vengeful_oath = "靈魂"
end

L = BigWigs:NewBossLocale("Dimensius, the All-Devouring", "zhTW")
if L then
	L.gravity = "重力"
	L.extinction = "滅絕" -- Dimensius hurls a fragment of a broken world
	L.slows = "緩速"
	L.slow = "緩速" -- Singular of Slows
	L.mass_destruction = "射線"
	L.mass_destruction_single = "射線"
	L.stardust_nova = "新星" -- Short for Stardust Nova
	L.extinguish_the_stars = "星晨" -- Short for Extinguish the Stars
	L.darkened_sky = "星環"
	L.cosmic_collapse = "坦克拉人"
	L.cosmic_collapse_easy = "坦克大圈"
	L.soaring_reshii = "可飛行" -- On the timer for when flying is available

	L.left_living_mass = "左側過剩物質"
	L.right_living_mass = "右側過剩物質"

	L.soaring_reshii_monster_yell = "你的表現很不錯。" -- [CHAT_MSG_MONSTER_YELL] You've done well so far. Surprising. But we're not done yet.#Xal'atath###Meeresflask##0#0##0#256#nil#0#false#false#false#false",

	L.weakened_soon_monster_yell = "必需現在就出擊！" -- [CHAT_MSG_MONSTER_YELL] We must strike--now!#Xal'atath###Xal'atath##0#0##0#4873#nil#0#false#false#false#false",
end

-- Nerub-ar Palace

L = BigWigs:NewBossLocale("Ulgrax the Devourer", "zhTW")
if L then
	L.carnivorous_contest_pull = "拉扯" -- 要不...吃人?
	L.chunky_viscera_message = "使用額外快捷鍵餵食首領！"
end

L = BigWigs:NewBossLocale("The Bloodbound Horror", "zhTW")
if L then
	L.gruesome_disgorge_debuff = "內場" -- 非表象之境 名字太長了
	L.grasp_from_beyond = "地刺" -- 觸手
	L.grasp_from_beyond_say = "地刺"
	L.bloodcurdle = "分散"
	L.bloodcurdle_on_you = "分散" -- Singular of Spread
	L.goresplatter = "遠離"
end

L = BigWigs:NewBossLocale("Rasha'nan", "zhTW")
if L then
	L.spinnerets_strands = "絲線" -- 絲囊?
	L.enveloping_webs = "蛛網"
	L.enveloping_web_say = "蛛網" -- Singular of Webs
	L.erosive_spray = "酸液"
	L.caustic_hail = "下個位置"
end

L = BigWigs:NewBossLocale("Broodtwister Ovi'nax", "zhTW")
if L then
	L.sticky_web = "蛛網"
	L.sticky_web_say = "蛛網" -- Singular of Webs
	L.infest_message = "正在對你施放寄生！"
	L.infest_say = "寄生"
	L.experimental_dosage = "破蛋"
	L.experimental_dosage_say = "破蛋"
	L.ingest_black_blood = "換場" -- 或 下個容器
	L.unstable_infusion = "黑圈"  -- 或 旋渦

	L.custom_on_experimental_dosage_marks = "實驗療法分配"
	L.custom_on_experimental_dosage_marks_desc = "將受到「實驗療法」影響的玩家，按照近戰 > 遠程 > 治療的優先級，標記為 {rt6}{rt4}{rt3}{rt7}，包含喊話與目標訊息。"

	L.volatile_concoction_explosion_desc = "當有玩家受到「爆炸性混合物」的減益效果影響時，顯示計時條。"
end

L = BigWigs:NewBossLocale("Nexus-Princess Ky'veza", "zhTW")
if L then
	L.assasination = "幻影"
	L.twiligt_massacre = "衝鋒"
	L.nexus_daggers = "匕首"
end

L = BigWigs:NewBossLocale("The Silken Court", "zhTW")
if L then
	L.skipped_cast = "跳過%s（%d）"
	L.intermission_trigger = "要使出全力了！" -- Skeinspinner Takazj 100 energy yell

	L.venomous_rain = "毒雨" -- 毒圈 綠圈
	L.burrowed_eruption = "鑽地"
	L.stinging_swarm = "驅散魔法"
	L.strands_of_reality = "塔卡正面" -- S for Skeinspinner Takazj 塔卡震懾波
	L.strands_of_reality_message = "塔卡茲：正面衝擊波"
	L.impaling_eruption = "阿努正面" -- A for Anub'arash 阿努震懾波
	L.impaling_eruption_message = "阿努巴拉許：正面衝擊波"
	L.entropic_desolation = "跑開"
	L.cataclysmic_entropy = "大爆炸" -- 災變無序/災變
	L.spike_eruption = "尖刺"
	L.unleashed_swarm = "蟲群"
	L.void_degeneration = "藍球"
	L.burning_rage = "紅球"
end

L = BigWigs:NewBossLocale("Queen Ansurek", "zhTW")
if L then
	L.stacks_onboss = "首領：%d 層%s"

	L.reactive_toxin = "毒素" -- 技能描述用了「毒素」
	L.reactive_toxin_say = "毒素"
	L.venom_nova = "新星"
	L.web_blades = "刀刃" -- 技能描述「刀刃絲網」
	L.silken_tomb = "絲網" -- Raid being rooted in place
	L.wrest = "拉扯" -- 好像也不用轉？搶奪只有兩個字
	L.royal_condemnation = "鐐銬"
	L.frothing_gluttony = "暴食" -- 起沫暴食/黑環

	L.stage_two_end_message_storymode = "快進傳送門"
end

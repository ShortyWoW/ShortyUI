-- Khaz Algar

local L = BigWigs:NewBossLocale("Aggregation of Horrors", "zhCN")
if L then
	L.void_rocks = "虚空岩石" -- Plural of Void Rock (452379)
end

L = BigWigs:NewBossLocale("Reshanor, The Untethered", "zhCN")
if L then
	L.run = "靠近紫光并使用额外快捷键"
end

-- Liberation of Undermine

L = BigWigs:NewBossLocale("Cauldron of Carnage", "zhCN")
if L then
	L.custom_on_fade_out_bars = "淡出计时器"
	L.custom_on_fade_out_bars_desc = "当首领超出范围时，淡出其相关技能的计时器。"

	L.bomb_explosion = "炸弹爆炸"
	L.bomb_explosion_desc = "显示炸弹爆炸的倒计时。"

	L.eruption_stomp = "重踏" -- 喷发重踏
	L.thunderdrum_salvo = "齐射" -- 雷鼓齐射

	L.static_charge_high = "%d - 你移动得太频繁"
end

L = BigWigs:NewBossLocale("Rik Reverb", "zhCN")
if L then
	L.amplification = "增幅器"
	L.echoing_chant = "音波"
	L.faulty_zap = "电击"
	L.sparkblast_ignition = "烟火桶"
end

L = BigWigs:NewBossLocale("Stix Bunkjunker", "zhCN")
if L then
	L.rolled_on_you = "%s 碾过你" -- PlayerX rolled over you
	L.rolled_from_you = "你碾过 %s" -- (you) Rolled over PlayerX
	L.garbage_dump_message = "你对首领造成了 %s 伤害"

	L.electromagnetic_sorting = "电磁分拣" -- 中文技能名称短，就不简写了
	L.muffled_doomsplosion = "炸弹爆炸" -- 闷声毁灭爆炸
	L.short_fuse = "爆壳蟹爆炸" -- 超短引线
	L.incinerator = "火圈"
end

L = BigWigs:NewBossLocale("Sprocketmonger Lockenstock", "zhCN")
if L then
	L.foot_blasters = "地雷"
	L.unstable_shrapnel = "地雷爆炸"
	L.screw_up = "钻头"
	L.screw_up_single = "钻头" -- Singular of Drills
	L.sonic_ba_boom = "声波爆轰"
	L.polarization_generator = "极性转化"

	L.polarization_soon = "极性改变：%s"
	L.polarization_soon_change = "极性即将改变：%s"

	L.activate_inventions = "激活：%s"  --激活发明！
	L.blazing_beam = "光束" -- 炙热光束
	L.rocket_barrage = "火箭" -- 火箭弹幕
	L.mega_magnetize = "磁吸" -- 超级磁吸
	L.jumbo_void_beam = "虚空光束" -- 大号虚空光束
	L.void_barrage = "黑球" -- 虚空弹幕
	L.everything = "组合技" -- 光束+火箭+磁吸等组合技能

	L.under_you_comment = "在你脚下" -- Implies this setting is for the damage from the ground effect under you
end

L = BigWigs:NewBossLocale("The One-Armed Bandit", "zhCN")
if L then
	L.rewards = "豪华大奖" -- Fabulous Prizes
	L.rewards_desc = "当2种礼卷被组合后，将发放\"豪华大奖\"。\n信息会提醒你获得了哪种奖励。\n信息框也会显示哪些奖励任然可用。"
	L.deposit_time = "投卷计时：" -- Timer that indicates how long you have left to deposit the tokens.

	L.pay_line = "凭证"
	L.shock = "震击"
	L.flame = "烈焰"
	L.coin = "硬币"

	L.withering_flames = "烈焰" -- Short for Withering Flames

	L.cheat = "激活：%s" -- Cheat: Coils, Cheat: Debuffs, Cheat: Raid Damage, Cheat: Final Cast
	L.linked_machines = "线圈"
	L.linked_machine = "线圈" -- Singular of Coils
	L.hot_hot_heat = "烈焰减益"
	L.explosive_jackpot = "爆破大奖"
end

L = BigWigs:NewBossLocale("Mug'Zee, Heads of Security", "zhCN")
if L then
	L.earthshaker_gaol = "牢狱"
	L.frostshatter_boots = "冰靴" -- “霜裂冰靴”简写
	L.frostshatter_spear = "长矛" -- “霜裂长矛”简写
	L.stormfury_finger_gun = "手指枪" -- “风暴手指枪”简写
	L.molten_gold_knuckles = "真金指虎" -- “熔火真金指虎”
	L.unstable_crawler_mines = "地雷"
	L.goblin_guided_rocket = "火箭"
	L.double_whammy_shot = "双厄射击"
	L.electro_shocker = "振荡器" -- Mk II型电击振荡器
end

L = BigWigs:NewBossLocale("Chrome King Gallywix", "zhCN")
if L then
	L.story_phase_trigger = "怎么，自以为胜利了？" -- 怎么，自以为胜利了？呵，我给你准备了惊喜。

	L.scatterblast_canisters = "弹药筒分摊" -- 因为“裂破弹药筒”和“散射弹药筒”使用相同本地化，改成“弹药筒”
	L.fused_canisters = "引线分摊" -- 使用技能名“引线弹药筒”前2字做提醒
	L.tick_tock_canisters = "分摊"
	L.total_destruction = "毁灭！" -- 毁灭一切！！！

	L.duds = "哑弹" -- Short for 1500-Pound "Dud"
	L.all_duds_detontated = "所有哑弹已引爆！"
	L.duds_remaining = "剩余：%d 个哑弹" -- 1 Dud Remains | 2 Duds Remaining
	L.duds_soak = "哑弹爆炸 （剩余：%d 个）"
end

-- Manaforge Omega

L = BigWigs:NewBossLocale("Plexus Sentinel", "zhCN")
if L then
	L.cleanse_the_chamber = "光墙" --技能“净化内室”
end

L = BigWigs:NewBossLocale("Loom'ithar", "zhCN")
if L then
	L.lair_weaving = "蛛网" -- Webs that spawn on the edge of the room
	L.infusion_pylons = "晶塔" -- 技能“注能晶塔”的简称
end

L = BigWigs:NewBossLocale("Soulbinder Naazindhri", "zhCN")
if L then
	L.voidblade_ambush = "奇袭" -- 技能“虚空剑士奇袭”的简称
	L.soulfray_annihilation = "射线" -- Lines that shoot out an orb along that path
	L.soulfray_annihilation_single = "射线" -- Single from Lines
	L.remaining_adds = "剩余增援" -- All remaining adds from Soul Calling spawn
end

L = BigWigs:NewBossLocale("Forgeweaver Araz", "zhCN")
if L then
	L.invoke_collector = "收集者" -- NPC“唤动收集者”的简称
end

L = BigWigs:NewBossLocale("Fractillus", "zhCN")
if L then
	L.crystalline_shockwave = "水晶墙"
	L.shattershell = "破墙"
	L.shockwave_slam = "坦克墙"
	L.nexus_shrapnel = "碎片落地"
	L.crystal_lacerations = "流血"
end

L = BigWigs:NewBossLocale("Nexus-King Salhadaar", "zhCN")
if L then
	L.fractal_images = "虚空龙" -- 技能“分形镜像”描述
	L.oath_bound_removed_dose = "移除1层誓言约束"
	L.behead = "处斩" -- Claws of a dragon
	L.netherbreaker = "虚空圈"
	L.galaxy_smash = "重碾" -- 技能“星河重碾”的简称
	L.starkiller_swing = "歼星斩" -- 歼星斩
	L.vengeful_oath = "幻影"
end

L = BigWigs:NewBossLocale("Dimensius, the All-Devouring", "zhCN")
if L then
	L.gravity = "引力" -- 技能“引力倒逆”和“引力扭曲”的简称。
	L.extinction = "碎片" -- 迪门修斯投掷出“破碎空间”的空间碎片
	L.slows = "减速"
	L.slow = "减速"
	L.mass_destruction = "射线"
	L.mass_destruction_single = "射线"
	L.stardust_nova = "新星" -- 技能“星尘新星”的简称
	L.extinguish_the_stars = "众星" -- 技能“熄灭众星”的简称
	L.darkened_sky = "光波"
	L.cosmic_collapse = "坦克拉人"
	L.cosmic_collapse_easy = "坦克大圈"
	L.soaring_reshii = "坐骑可用" -- On the timer for when flying is available

	L.left_living_mass = "活体物质（左）"  -- NPCID：242587 活体物质
	L.right_living_mass = "活体物质（右）"

	L.soaring_reshii_monster_yell = "你目前的表现好得出奇，" -- [CHAT_MSG_MONSTER_YELL] 你目前的表现好得出奇，可我们还没结束呢。#Xal'atath###Meeresflask##0#0##0#256#nil#0#false#false#false#false",

	L.weakened_soon_monster_yell = "必须出击，就是现在！" -- [CHAT_MSG_MONSTER_YELL] 必须出击，就是现在！#Xal'atath###Xal'atath##0#0##0#4873#nil#0#false#false#false#false",
end

-- Nerub-ar Palace

L = BigWigs:NewBossLocale("Ulgrax the Devourer", "zhCN")
if L then
	L.carnivorous_contest_pull = "拉扯"
	L.chunky_viscera_message = "喂食首领！（额外快捷键）"
end

L = BigWigs:NewBossLocale("The Bloodbound Horror", "zhCN")
if L then
	L.gruesome_disgorge_debuff = "内场"
	L.grasp_from_beyond = "触手"
	L.grasp_from_beyond_say = "触手"
	L.bloodcurdle = "分散"
	L.bloodcurdle_on_you = "分散" -- Singular of Spread
	L.goresplatter = "远离"
end

L = BigWigs:NewBossLocale("Rasha'nan", "zhCN")
if L then
	L.spinnerets_strands = "丝线"
	L.enveloping_webs = "蛛网"
	L.enveloping_web_say = "蛛网" -- Singular of Webs
	L.erosive_spray = "喷涌"
	L.caustic_hail = "下个位置"
end

L = BigWigs:NewBossLocale("Broodtwister Ovi'nax", "zhCN")
if L then
	L.sticky_web = "蛛网"
	L.sticky_web_say = "蛛网" -- Singular of Webs
	L.infest_message = "对你施放感染！"
	L.infest_say = "寄生"
	L.experimental_dosage = "破蛋"
	L.experimental_dosage_say = "破蛋"
	L.ingest_black_blood = "下个容器"
	L.unstable_infusion = "紫圈"

	L.custom_on_experimental_dosage_marks = "试验性剂量分配"
	L.custom_on_experimental_dosage_marks_desc = "将受到“试验性剂量” 的玩家，按照 近战 > 远程 > 治疗 的优先顺序分配 {rt6}{rt4}{rt3}{rt7} 标记。 包含喊话和目标信息。"

	L.volatile_concoction_explosion_desc = "当玩家受到“不稳定的混合物”的减益效果影响时，显示计时条。"
end

L = BigWigs:NewBossLocale("Nexus-Princess Ky'veza", "zhCN")
if L then
	L.assasination = "幻影"
	L.twiligt_massacre = "冲锋"
	L.nexus_daggers = "匕首"
end

L = BigWigs:NewBossLocale("The Silken Court", "zhCN")
if L then
	L.skipped_cast = "跳过 %s (%d)"
	L.intermission_trigger = "巅峰之力！" -- Skeinspinner Takazj 100 energy yell

	L.venomous_rain = "毒雨"
	L.burrowed_eruption = "钻地"
	L.stinging_swarm = "驱散减益"
	L.strands_of_reality = "正面 [塔卡]" -- S for Skeinspinner Takazj 使用了首领名字前二个字“塔卡兹基”
	L.strands_of_reality_message = "正面 [纺束者塔卡兹基]"
	L.impaling_eruption = "正面 [阿努]" -- A for Anub'arash 使用了首领名字前二个字“阿努巴拉什”
	L.impaling_eruption_message = "正面 [阿努巴拉什]"
	L.entropic_desolation = "熵能"  --使用技能名称。
	L.cataclysmic_entropy = "大爆炸" -- Interrupt before it casts
	L.spike_eruption = "尖刺"
	L.unleashed_swarm = "虫群"
	L.void_degeneration = "蓝球"
	L.burning_rage = "红球"
end

L = BigWigs:NewBossLocale("Queen Ansurek", "zhCN")
if L then
	L.stacks_onboss = "首领：%d层 %s"

	L.reactive_toxin = "毒素"
	L.reactive_toxin_say = "毒素"
	L.venom_nova = "新星"  -- 剧毒新星，暂时用新星，也可以用毒环
	L.web_blades = "网刃"  -- 中文技能名称短直接使用技能名称
	L.silken_tomb = "缠绕" -- Raid being rooted in place
	L.wrest = "拉扯"
	L.royal_condemnation = "镣铐"
	L.frothing_gluttony = "能量环"

	L.stage_two_end_message_storymode = "快进传送门"
end

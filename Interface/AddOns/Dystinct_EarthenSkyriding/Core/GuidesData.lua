local addonName, addon = ...

addon.guides = {
    {
        title = "Skyriding Leveling Basics",
        description = "How discovery leveling works and why it's built for the Earthen allied race.",
        content = {
            { type = "header", value = "Introduction" },
            { type = "text", value = "The routes in this addon are designed to optimize the discovery of areas as efficiently as possible, chaining area discoveries together in an optimal path to minimize travel time and maximize experience per hour." },
            { type = "header", value = "Why Earthen?" },
            { type = "image", texture = "Interface\\AddOns\\Dystinct_EarthenSkyriding\\Textures\\Guides\\basics_passive", width = 512, height = 85 },
            { type = "text", value = "This method of leveling is built around the Earthen allied race due to their racial trait |cFF87e6e8Wide-Eyed Wonder|r, which provides them with 3x the experience other characters would receive from discovery experience. This multiplier is what makes discovery leveling so effective — without it, the experience gains would not be competitive with other leveling methods." },
            { type = "header", value = "Triggering Discoveries" },
            { type = "text", value = "An important detail to understand is that discovering an area does not trigger automatically simply from entering it. If you fly through a zone without any input, the discovery may be inconsistent or missed entirely." },
            { type = "text", value = "To reliably trigger a discovery, you need to press a movement key such as |cFF87e6e8W|r or click |cFF87e6e8both mouse buttons together|r after entering the area. This forces the game to register your presence in the zone and award the discovery experience." },
        }
    },
    {
        title = "Advanced Skyriding",
        description = "Techniques for maximizing speed and efficiency while skyriding between discoveries.",
        content = {
            { type = "header", value = "Introduction" },
            { type = "text", value = "Skyriding is the fastest way to travel between area discoveries. Mastering a few key techniques will dramatically improve your leveling speed with proper use of Skyward Ascent being the most difficult to master but the most effective tool in your arsenal." },
            { type = "header", value = "Spend Charges Aggressively" },
            { type = "text", value = "Your charges for |cFF87e6e8Skyward Ascent|r and |cFF87e6e8Surge Forward|r reset every time you level up. Since you will be leveling frequently during a route, you should be spending charges at a very aggressive pace to maintain the highest speed possible — there is no reason to hold onto them when they are about to reset." },
            { type = "text", value = "Similarly, if you are using |cFF87e6e8Whirling Surge|r, keep it on cooldown as much as possible. Every second it sits unused is wasted potential speed." },
            { type = "header", value = "Recovering From Turns" },
            { type = "text", value = "Sharp turns bleed momentum significantly. To mitigate this, use a |cFF87e6e8Skyward Ascent|r or |cFF87e6e8Whirling Surge|r immediately after making a sharp turn. This recovers the speed lost from turning at the moment you need it most, rather than wasting a charge while you are already at top speed." },
            { type = "header", value = "Skyward Ascent Technique" },
            { type = "text", value = "Skyward Ascent is the most powerful speed tool when used correctly, and is more valuable than Surge Forward when mastered." },
            { type = "text", value = "When you activate |cFF87e6e8Skyward Ascent|r, quickly flick your camera upward at the moment of activation. The ability applies its thrust in the direction you are facing, so by angling upward you ensure the full acceleration burst is applied. Then immediately angle your camera back down into a steep dive." },
            { type = "text", value = "This works because the upward flick maximizes the acceleration the ability provides, and by redirecting into a dive you allow gravity to compound with your existing momentum rather than fighting against it. The result is continuously building speed for as long as you are descending." },
            { type = "text", value = "By contrast, |cFF87e6e8Surge Forward|r gives a fixed horizontal speed boost that decays quickly. The flick-and-dive technique with Skyward Ascent produces higher peak speeds and sustains them for longer, making it the superior option when used properly." },
            { type = "text", value = "Mastering this technique is the single biggest improvement you can make to your route times." },
        }
    },
    {
        title = "Lorewalking",
        description = "How to use Lorewalking mode to scale old zones for level-appropriate discovery experience.",
        content = {
            { type = "header", value = "Introduction" },
            { type = "text", value = "Lorewalking is a mode that allows you to engage with quest storylines from previous expansions. For our purposes, the key benefit is that it enables level scaling in old zones, which means area discoveries grant level-appropriate experience rather than diminishing amounts as you outgrow the zone." },
            { type = "header", value = "Finding Lorewalker Cho" },
            { type = "text", value = "Lorewalker Cho can be found in Orgrimmar, Stormwind, and Silvermoon City though for the route we will rely on his presence in your faction's capital. He is located near the Cataclysm portals to the north. Speak with him to begin." },
            { type = "header", value = "Enabling Lorewalking" },
            { type = "image", texture = "Interface\\AddOns\\Dystinct_EarthenSkyriding\\Textures\\Guides\\lorewalking_activate", width = 512, height = 85 },
            { type = "text", value = "When you speak with Lorewalker Cho, select the dialogue option to activate Lorewalking. Once enabled, the zones associated with the storyline you choose will scale to your current level, making all area discoveries in those zones grant full experience." },
            { type = "header", value = "Leaving the Bench" },
            { type = "image", texture = "Interface\\AddOns\\Dystinct_EarthenSkyriding\\Textures\\Guides\\lorewalking_bench", width = 512, height = 85 },
            { type = "text", value = "After activating Lorewalking, you will be seated on a bench. To leave without teleporting away, click the exit vehicle button that appears. This keeps Lorewalking active while allowing you to continue your route." },
            { type = "header", value = "Exiting Lorewalking" },
            { type = "image", texture = "Interface\\AddOns\\Dystinct_EarthenSkyriding\\Textures\\Guides\\lorewalking_exiting", width = 512, height = 85 },
            { type = "text", value = "When you are ready to stop Lorewalking, you can exit the mode which will return you to Lorewalker Cho. You can return to him at any point later to reactivate Lorewalking for another session." },
            { type = "text", value = "|cFF87e6e8Note:|r Be sure to reactivate Lorewalking after you return to Lorewalker Cho before continuing on your journey. If you forget to reactivate it, the zones will not be scaled and your discoveries will no longer provide scaled experience." },
        }
    },
}

local _, ns = ...

ns.colour.completeR		= "\124cFFFF0000" -- Red
ns.colour.completeG		= "\124cFF00FF00" -- Green

-- Define the colours in the Colours_xxx file
ns.questTypes = { "One Time", "Seasonal", "Weekly", "Daily", "Repeatable" }
	-- Code the qType field exactly as this for each quest set within the pin's quests set in the data file
ns.questTypesDB = { "One Time Quests", "Seasonal Quests", "Weekly Quests", "Daily Quests", "Repeatable Quests", }
	-- Doubles as the db key as well as the on screen (translated) options title
ns.questColours = { ( ns.colour.oneTime or ns.colour.quests or ns.colour.plaintext ),
					( ns.colour.seasonal or ns.colour.quests or ns.colour.plaintext ),
					( ns.colour.weekly or ns.colour.quests or ns.colour.plaintext ),
					( ns.colour.daily or ns.colour.quests or ns.colour.plaintext ),
					( ns.colour.repeatable or ns.colour.quests or ns.colour.plaintext ), }
					
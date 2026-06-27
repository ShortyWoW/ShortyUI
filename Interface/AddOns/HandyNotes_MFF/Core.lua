--[[
                                ----o----(||)----oo----(||)----o----

                                       Midsummer Fire Festival

                                       v4.07 - 27th June 2026
                                Copyright (C) Taraezor / Chris Birch
                                         All Rights Reserved

                                ----o----(||)----oo----(||)----o----
]]

local addonName, ns = ...

-- ---------------------------------------------------------------------------------------------------------------------------------

-- This AddOn has been wholly modularised and runs on a standardised core of files.
-- It's data/customisations are found in the _XXXX files.
-- Executable customisations / overrides are to be inserted here.
-- To configure use a chat command as defined in the Data_XXXX file.

-- ---------------------------------------------------------------------------------------------------------------------------------

-- Data checks. Must return true or false. Decision as to whether or not to show, regardless of any other checks

--function ns.PassAddOnSpecificPetChecks( pet )
--function ns.PassAddOnSpecificAchievementChecks( event )
--function ns.PassAddOnSpecificQuestChecks( quest )

-- ---------------------------------------------------------------------------------------------------------------------------------

-- Preceeds the showing of Tooltips. After the title/name fields and after Event/Pet/Quest modules. Right before theg guides/tips.

--function ns.AddOnSpecificTooltipLines( pin )

-- ---------------------------------------------------------------------------------------------------------------------------------

--	Return manually allocated and sized texture index into the Functions_Commons "hash" for then "return" to the HandyNotes
--  driver for displaying the pin from the HN pin iterator

-- function ns.GetAddOnSpecificTextureIndex( pin )

-- ---------------------------------------------------------------------------------------------------------------------------------

-- Custom "do end" blocks, especially timed checks/setups

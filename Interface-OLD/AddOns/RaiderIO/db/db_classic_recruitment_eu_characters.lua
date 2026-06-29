--
-- Copyright (c) 2025 by RaiderIO, Inc.
-- All rights reserved.
--
local provider={name=...,data=3,region="eu",date="2026-06-28T08:04:04Z",numCharacters=5,db={}}
local F

F = function() provider.db["Norushen"]={0,"Jebasznikov","Jebasznikow","Xentare"} end F()
F = function() provider.db["Everlook"]={6,"Captntobi"} end F()
F = function() provider.db["PyrewoodVillage"]={8,"Shaymary"} end F()

F = nil
RaiderIO.AddProvider(provider)

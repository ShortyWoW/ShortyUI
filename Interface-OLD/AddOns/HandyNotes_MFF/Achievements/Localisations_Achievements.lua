local _, ns = ...

-- Translations specific to the Achievements module.
-- Note that per character and per account differentiated labels have been retained.

if ns.locale == "deDE" then
	ns.L["Achievement"] = "Erfolg"
	ns.L["Achievements"] = "Erfolge"
	ns.L["Achievements Acct"] = "Erfolge: Konto"
	ns.L["Achievements AcctDesc"] = "Die Kartenmarkierung wird nicht angezeigt, wenn ein Charakter den Erfolg abgeschlossen hat"
	ns.L["Achievements Char"] = "Erfolge: %up"
	ns.L["Achievements CharDesc"] = "Die Kartenmarkierung wird nicht angezeigt, wenn %up den Erfolg abgeschlossen hat"
	ns.L["AchievementsDesc"] = "Die Kartenmarkierung wird nicht angezeigt, wenn ein Charakter den Erfolg abgeschlossen hat"

elseif ns.locale == "esES" or ns.locale == "esMX" then
	ns.L["Achievement"] = "Logro"
	ns.L["Achievements"] = "Logros"
	ns.L["Achievements Acct"] = "Logros: Cuenta"
	ns.L["Achievements AcctDesc"] = "El marcador del mapa no aparecerá cuando algún personaje haya completado el logro"
	ns.L["Achievements Char"] = "Logros: %up"
	ns.L["Achievements CharDesc"] = "El marcador del mapa no aparecerá cuando %up haya completado el logro"
	ns.L["AchievementsDesc"] = "El marcador del mapa no aparecerá cuando algún personaje haya completado el logro"

elseif ns.locale == "frFR" then
	ns.L["Achievement"] = "Réalisation"
	ns.L["Achievements"] = "Réalisations"
	ns.L["Achievements Acct"] = "Réalisations: Compte"
	ns.L["Achievements AcctDesc"] = "L'épingle de la carte n'apparaîtra pas lorsqu'un personnage aura terminé le succès"
	ns.L["Achievements Char"] = "Réalisations: %up"
	ns.L["Achievements CharDesc"] = "L'épingle de la carte n'apparaîtra pas lorsque %up aura terminé le succès"
	ns.L["AchievementsDesc"] = "L'épingle de la carte n'apparaîtra pas lorsqu'un personnage aura terminé le succès"

elseif ns.locale == "itIT" then
	ns.L["Achievement"] = "Risultato"
	ns.L["Achievements"] = "Risultati"
	ns.L["Achievements Acct"] = "Risultati: Account"
	ns.L["Achievements AcctDesc"] = "Il segnaposto sulla mappa non apparirà quando un personaggio avrà completato l'obiettivo"
	ns.L["Achievements Char"] = "Risultati: %up"
	ns.L["Achievements CharDesc"] = "Il segnaposto sulla mappa non apparirà quando %up avrà completato l'obiettivo"
	ns.L["AchievementsDesc"] = "Il segnaposto sulla mappa non apparirà quando un personaggio avrà completato l'obiettivo"
	
elseif ns.locale == "koKR" then
	ns.L["Achievement"] = "성취"
	ns.L["Achievements"] = "업적"
	ns.L["Achievements Acct"] = "업적: 계정가"
	ns.L["Achievements AcctDesc"] = "캐릭터가 업적을 완료하면 지도 핀이 표시되지 않습니다."
	ns.L["Achievements Char"] = "업적: %up가"
	ns.L["Achievements CharDesc"] = "%up가 업적을 완료하면 지도 핀이 표시되지 않습니다."
	ns.L["AchievementsDesc"] = "캐릭터가 업적을 완료하면 지도 핀이 표시되지 않습니다."

elseif ns.locale == "ptBR" or ns.locale == "ptPT" then
	ns.L["Achievement"] = "Conquista"
	ns.L["Achievements"] = "Conquistas"
	ns.L["Achievements Acct"] = "Conquistas: Conta"
	ns.L["Achievements AcctDesc"] = "O pin do mapa não aparecerá quando algum personagem tiver concluído a conquista"
	ns.L["Achievements Char"] = "Conquistas: %up"
	ns.L["Achievements CharDesc"] = "O pin do mapa não aparecerá quando %up tiver concluído a conquista"
	ns.L["AchievementsDesc"] = "O pin do mapa não aparecerá quando algum personagem tiver concluído a conquista"

elseif ns.locale == "ruRU" then
	ns.L["Achievement"] = "Достижение"
	ns.L["Achievements"] = "Достижения"
	ns.L["Achievements Acct"] = "Достижения: Счет"
	ns.L["Achievements AcctDesc"] = "Значок на карте не появится, если какой-либо персонаж выполнит достижение"
	ns.L["Achievements Char"] = "Достижения: %up"
	ns.L["Achievements CharDesc"] = "Значок на карте не появится, когда %up выполнит достижение"
	ns.L["AchievementsDesc"] = "Значок на карте не появится, если какой-либо персонаж выполнит достижение"

elseif ns.locale == "zhCN" then
	ns.L["Achievement"] = "成就"
	ns.L["Achievements"] = "成就"
	ns.L["Achievements Acct"] = "成就：帐户"
	ns.L["Achievements AcctDesc"] = "当任何角色完成成就时，地图图标将不会出现"
	ns.L["Achievements Char"] = "成就：%up"
	ns.L["Achievements CharDesc"] = "当 %up 完成成就时，地图图标将不会出现"
	ns.L["AchievementsDesc"] = "当任何角色完成成就时，地图图标将不会出现"

elseif ns.locale == "zhTW" then
	ns.L["Achievement"] = "成就"
	ns.L["Achievements"] = "成就"
	ns.L["Achievements Acct"] = "成就：帳戶"
	ns.L["Achievements AcctDesc"] = "當任何角色完成成就時，地圖圖示將不會出現"
	ns.L["Achievements Char"] = "成就：%up"
	ns.L["Achievements CharDesc"] = "當 %up 完成成就時，地圖圖示將不會出現"
	ns.L["AchievementsDesc"] = "當任何角色完成成就時，地圖圖示將不會出現"

else
	ns.L["Achievements Acct"] = "Achievements: Account"
	ns.L["Achievements AcctDesc"] = "The map pin will not appear when any character has completed the achievement"
	ns.L["Achievements Char"] = "Achievements: %up"
	ns.L["Achievements CharDesc"] = "The map pin will not appear when %up has completed the achievement"
	ns.L["AchievementsDesc"] = "The map pin will not appear when any character has completed the achievement"
end
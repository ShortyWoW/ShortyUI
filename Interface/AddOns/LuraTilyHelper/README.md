# LuraOrder - WoW Addon

Addon de suivi de pattern pour boss (WoW: The War Within / Midnight).

## Installation

1. Copie le dossier `LuraOrder/` dans :
   ```
   World of Warcraft/_retail_/Interface/AddOns/LuraOrder/
   ```
2. Lance WoW et active l'addon dans "Addons" sur l'écran de sélection de personnage.

## Utilisation

| Commande | Action |
|---|---|
| `/lura` | Ouvre/ferme la fenêtre principale |
| `/lura raid` | Affiche/cache la vue raid (toutes les icônes de chaque joueur) |
| `/lura clear` | Efface ton pattern |

## Comment ça marche

- **Clique** sur les lettres en bas (T, O, D, C, X) pour ajouter des symboles à ton arc.
- Les symboles apparaissent en arc de cercle de droite à gauche.
- Chaque clic est **synchronisé en temps réel** à tout le groupe/raid qui a l'addon.
- La **vue raid** `/lura raid` montre une mini-fenêtre par joueur.
- Bouton **Clear** (ou `/lura clear`) pour remettre à zéro.

## Symboles

| Lettre | Couleur | Usage suggéré |
|---|---|---|
| T | Blanc | Tank |
| O | Orange | Objet / Orbe |
| D | Violet | DPS |
| C | Vert | Soin (Heal) |
| X | Rouge | Danger / Mort |

## Notes techniques

- Fonctionne en **raid, groupe et hors groupe** (test solo).
- Utilise les **addon messages** de WoW (C_ChatInfo) pour la synchro.
- Tous les joueurs doivent avoir l'addon installé pour voir les patterns des autres.
- Interface: 110100 (The War Within / compatible Midnight)

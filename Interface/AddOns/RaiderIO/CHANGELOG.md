# Raider.IO Mythic Plus, Raiding, and Recruitment

## [v202606040600](https://github.com/RaiderIO/raiderio-addon/tree/v202606040600) (2026-06-04)
[Full Changelog](https://github.com/RaiderIO/raiderio-addon/compare/v202606030600...v202606040600) [Previous Releases](https://github.com/RaiderIO/raiderio-addon/releases)

- [Raider.IO] Database Refresh  
- [Raider.IO] Classic Database Refresh  
- Added more checks to the "selected" unit behavior for dropdowns which previously missed a case #374. (#375)  
    Added a new tempoary option to disable the dropdown menu integration. This should fix community frame during combat, or unit focus or raid target icon selection as they are all affected by any addon tainting the dropdown menu.  
    Not everyone will experience the dropdown menu issue at the same frequency, so for those that do have it frequently error, this option should help those disable the dropdown integration.  
    In the future we can simply remove this option from the addon, once Blizzard makes the dropdown system more robust from taint.  
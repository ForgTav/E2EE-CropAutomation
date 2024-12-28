local shell = require('shell')
local scripts = {
    'autoStat.lua',
    'autoTier.lua',
    'robotActions.lua',
    'robotConfig.lua',
    'robotGPS.lua',
    'robotSetup.lua',
    'start.lua',
    'sysConfig.lua',
    'sysDB.lua',
    'sysGPS.lua',
    'sysSetup.lua',
    'main.lua',
    'sysFunction.lua',
    'sysEvents.lua',
    'uninstall.lua'
}

-- UNINSTALL
for i = 1, #scripts do
    shell.execute(string.format('rm %s', scripts[i]))
    print(string.format('Uninstalled %s', scripts[i]))
end

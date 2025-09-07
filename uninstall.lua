local shell = require('shell')
local scripts = {
    'robotActions.lua',
    'robotConfig.lua',
    'robotGPS.lua',
    'start.lua',
    'main.lua',
    'sysConfig.lua',
    'sysDB.lua',
    'sysFunction.lua',
    'sysGPS.lua',
    'sysLogic.lua',
    'sysUI.lua',
    'uninstall.lua'
}

for i = 1, #scripts do
    shell.execute(string.format('rm %s', scripts[i]))
    print(string.format('Uninstalled %s', scripts[i]))
end

fx_version 'cerulean'
game 'gta5'

lua54 'yes'

author 'Visionary Shield contributors'
description 'Open-source FiveM/QBCore security and admin tooling resource'
version '1.7.3-open-source-deployment-polish'

ui_page 'ui/index.html'

dependency 'screenshot-basic'

files {
    'ui/index.html',
    'ui/style.css',
    'ui/app.js',
    'ui/translations.js',
    'data/*.json'
}

shared_scripts {
    'shared/config.lua'
}

client_scripts {
    'shared/utils.lua',
    'client/main.lua',
    'client/modules/*.lua'
}

server_scripts {
    'server/bootstrap.lua',
    'shared/utils.lua',
    'server/utils/logger.lua',
    'server/modules/*.lua',
    'server/main.lua'
}

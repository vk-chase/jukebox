fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Chase'
description 'VK Music Players - optimized deployable music stations for QBCore'
version '2.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config/*.lua',
    'locales/*.lua'
}

client_scripts {
    'client/*.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/*.lua'
}

dependencies {
    'ox_lib',
    'qb-core',
    'qb-target',
    'oxmysql',
    'xsound'
}

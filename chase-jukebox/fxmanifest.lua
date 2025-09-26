fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'jim-djbooth'
author 'jim edits by vk-chase'
version '1.0.0'

-- REQUIRE ox_lib
shared_script '@ox_lib/init.lua'

client_scripts {
    'client.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua',
}


shared = require("shared")
util = require("script/script_util")

local handler = require("event_handler")

handler.add_lib(require("script/road_network"))
handler.add_lib(require("script/migrations"))
handler.add_lib(require("script/depot_common"))
handler.add_lib(require("script/transport_drone"))
handler.add_lib(require("script/proxy_tile"))
handler.add_lib(require("script/transport_technologies"))
handler.add_lib(require("script/gui"))
handler.add_lib(require("script/depot_panel"))
handler.add_lib(require("script/writer_gui"))
handler.add_lib(require("script/reader_gui"))
handler.add_lib(require("script/fork_migration"))
handler.add_lib(require("script/factorissimo"))

require("script/remote_interface")

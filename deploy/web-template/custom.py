# SCons options for the trimmed web export template; build.sh passes this
# file as `profile=`. Everything the game doesn't use is off. A class the
# game needs but this build leaves out fails when the page runs, not at
# export, so when the game starts using a new engine feature, turn its
# option or module back on here and rebuild.

# What the official templates are built with. It also picks LTO (thin, on
# the web), and overrides any lto set here.
production = "yes"

disable_3d = "yes"
disable_physics_2d = "yes"
disable_physics_3d = "yes"
disable_navigation_2d = "yes"
disable_navigation_3d = "yes"
disable_xr = "yes"
# RichTextLabel, Tree, menus and the like. The UI uses Label and StyleBoxFlat.
disable_advanced_gui = "yes"
deprecated = "no"
# The web build loads a .pck, never a ZIP.
minizip = "no"

modules_enabled_by_default = "no"
module_gdscript_enabled = "yes"
module_multiplayer_enabled = "yes"
# The default font.
module_freetype_enabled = "yes"
# PLACEHOLDER (design): the fallback text server has no complex shaping or
# right-to-left text; fine for English-only UI. text_server_adv supports
# every script and is larger.
module_text_server_fb_enabled = "yes"
# Crypto, for the client's session ID (client/client.gd).
module_mbedtls_enabled = "yes"

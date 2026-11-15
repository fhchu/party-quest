# SCons options for the trimmed web export template; build.sh passes this
# file as `profile=`, and the .gdbuild next to it as `build_profile=`. The
# .gdbuild removes the classes the game doesn't use; this file picks the
# modules and build settings. The .gdbuild is applied after this file and
# wins where both set an option.

# What the official templates are built with. It also picks LTO (thin, on
# the web), and overrides any lto set here.
production = "yes"
deprecated = "no"
# The web build loads a .pck, never a ZIP.
minizip = "no"

modules_enabled_by_default = "no"
module_gdscript_enabled = "yes"
module_multiplayer_enabled = "yes"
# The default font.
module_freetype_enabled = "yes"
# No complex shaping or right-to-left text, unlike text_server_adv, which
# is larger.
module_text_server_fb_enabled = "yes"
# Crypto, for the client's session ID (client/client.gd).
module_mbedtls_enabled = "yes"

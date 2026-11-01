# Layout of the DMG window, read by dmgbuild (https://dmgbuild.readthedocs.io). scripts/release.sh runs it as:
#   dmgbuild -s scripts/dmg-settings.py -D app=<Gander.app> -D background=<background.tiff> "Gander <version>" <dmg>
# The icon positions match the arrow drawn by scripts/make-dmg-background.swift: change both together.
import os.path

app = defines["app"]  # noqa: F821 (dmgbuild provides `defines`)
background = defines["background"]  # noqa: F821

format = "UDZO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = os.path.join(app, "Contents", "Resources", "AppIcon.icns")

# The background is 660 × 420 points. The window size includes Finder's title bar, about 32 points tall.
window_rect = ((200, 120), (660, 452))
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
default_view = "icon-view"
icon_size = 128
text_size = 13
arrange_by = None
icon_locations = {
    os.path.basename(app): (170, 200),
    "Applications": (490, 200),
}

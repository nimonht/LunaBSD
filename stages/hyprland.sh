# Stage: hyprland - Hyprland, the tools its desktop relies on, and a session
# launcher that sets up the environment FreeBSD needs.

[ "$WANT_HYPR" = yes ] || { say "Hyprland not selected - skipped"; return 0; }

say "Hyprland and companions"
pkg_install seatd hyprland hyprlock hypridle hyprpaper hyprpicker hyprpolkitagent \
	xdg-desktop-portal-hyprland xdg-desktop-portal-gtk \
	qt6-wayland qt5-wayland qt6ct \
	foot fuzzel wl-clipboard cliphist grim slurp swappy wf-recorder libnotify \
	thunar gvfs polkit-gnome gnome-keyring gammastep wlr-randr ydotool \
	unix-selfauth-helper
svc seatd

say "fonts, icons and cursors used by the Hyprland setup"
pkg_install nerd-fonts-jetbrainsmono nerd-fonts-caskaydiacove material-icons-ttf \
	papirus-icon-theme bibata-cursor-theme nwg-look
pkg_try rubik

say "shell tools"
pkg_install fish starship eza zoxide direnv btop micro bat ripgrep lazygit
# trash-cli is a Python package, named after Python's version (py311-...):
# take the version the python3 package uses now.
_py=$(pkg_flavor python3 'python3[0-9]+')
[ -n "$_py" ] && pkg_try "py${_py#python}-trash-cli"

# With SDDM and no KDE, unlock gnome-keyring with the login password.
if [ "$DISPLAY_MANAGER" = sddm ] && [ "$WANT_KDE" != yes ]; then sddm_pam_enable pam_gnome_keyring; fi

install_file "$REPO_DIR/files/bin/hypr-session" /usr/local/bin/hypr-session 755
# Our session entry, named differently from the package's own "Hyprland"
# entry: that one starts Hyprland without the environment FreeBSD needs,
# and a package upgrade (or the ly login screen, which ignores NoDisplay)
# can show it again next to ours.
_hn="Hyprland (FreeBSD)"
is_yes INSTALL_CAELESTIA && _hn="Hyprland (Caelestia)"
mkdir -p /usr/local/share/wayland-sessions
cat > /usr/local/share/wayland-sessions/hypr-session.desktop <<DESK
# Written by FreeBSD-setup
[Desktop Entry]
Name=$_hn
Comment=Hyprland with the environment FreeBSD needs - choose this one
Exec=/usr/local/bin/hypr-session
Type=Application
DesktopNames=Hyprland
DESK
# Hide the package's entry where the login screen honours that (SDDM).
_hd=/usr/local/share/wayland-sessions/hyprland.desktop
[ -f "$_hd" ] && ! grep -q '^NoDisplay=true' "$_hd" && echo 'NoDisplay=true' >> "$_hd"
true

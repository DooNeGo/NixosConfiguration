{
  home.file.".config/uwsm/env".text = ''
    export GDK_BACKEND=wayland,x11,*
    export QT_QPA_PLATFORM=wayland;xcb

    export QT_AUTO_SCREEN_SCALE_FACTOR=1
    export QT_QPA_PLATFORM=wayland;xcb
    export QT_WAYLAND_DISABLE_WINDOWDECORATION=1

    export GBM_BACKEND=nvidia-drm
    export __GLX_VENDOR_LIBRARY_NAME=nvidia
    export LIBVA_DRIVER_NAME=nvidia
    export __GL_GSYNC_ALLOWED=1
    export __GL_VRR_ALLOWED=1
    export NVD_BACKEND=direct
  '';
}

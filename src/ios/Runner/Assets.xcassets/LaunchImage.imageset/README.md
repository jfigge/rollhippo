# Launch Screen Assets

These three rasters are drawn by `make icon`, out of `tool/app_icon.dart`, from
the same mark as the app icon — don't replace them by hand or through Xcode, or
the next `make icon` will draw over whatever was dropped in. Their size comes
from `_kLaunchPoints` in that file, and `LaunchScreen.storyboard` centres them
at that size on the picker's own background.

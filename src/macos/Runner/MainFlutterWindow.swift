import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// The desktop build exists to judge how the dice feel, so its tray is sized
  /// to a phone rather than to a desktop window. 393 × 852 points is an iPhone
  /// 15 Pro, which at the app's 6100 px/m makes the tray 64 × 140 mm — the same
  /// tray, at the same scale, as the device build.
  private static let phoneSize = NSSize(width: 393, height: 852)

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Sizing has to happen *after* super, which restores the frame the nib was
    // saved with and would otherwise undo this.
    super.awakeFromNib()

    self.setContentSize(MainFlutterWindow.phoneSize)
    self.contentAspectRatio = MainFlutterWindow.phoneSize
    self.center()
  }
}

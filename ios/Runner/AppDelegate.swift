import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate {

  private let headingService = TrueHeadingService()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    let controller = window?.rootViewController as! FlutterViewController

    let channel = FlutterEventChannel(
      name: "with_light_star/true_heading",
      binaryMessenger: controller.binaryMessenger
    )
    channel.setStreamHandler(headingService)

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

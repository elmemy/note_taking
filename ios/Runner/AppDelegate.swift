import UIKit
import Flutter
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
      
      let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
      let microphoneChannel = FlutterMethodChannel(name: "com.example.microphone/permissions",
                                                   binaryMessenger: controller.binaryMessenger)
      
      microphoneChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
        if call.method == "checkMicrophonePermission" {
          self?.checkMicrophonePermission(result: result)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
      
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Custom function to check microphone permission
  @objc func checkMicrophonePermission(result: @escaping FlutterResult) {
    switch AVAudioSession.sharedInstance().recordPermission {
    case .granted:
      result(true)
    case .denied:
      result(false)
    case .undetermined:
      AVAudioSession.sharedInstance().requestRecordPermission { granted in
        result(granted)
      }
    @unknown default:
      result(false)
    }
  }
}

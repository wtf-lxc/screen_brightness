import Flutter
import UIKit

public class ScreenBrightnessIosPlugin: NSObject, FlutterPlugin {
    var registrar: FlutterPluginRegistrar
    var methodChannel: FlutterMethodChannel?

    var systemScreenBrightnessChangedEventChannel: FlutterEventChannel?
    let systemScreenBrightnessChangedStreamHandler: ScreenBrightnessChangedStreamHandler = ScreenBrightnessChangedStreamHandler()

    var applicationScreenBrightnessChangedEventChannel: FlutterEventChannel?
    let applicationScreenBrightnessChangedStreamHandler: ScreenBrightnessChangedStreamHandler = ScreenBrightnessChangedStreamHandler()
    
    var systemScreenBrightness: CGFloat?
    var applicationScreenBrightness: CGFloat?
    
    var isAutoReset: Bool = true
    var isAnimate: Bool = true
    
    let taskQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    init(registration: FlutterPluginRegistrar) {
        self.registrar = registration
        super.init()
        systemScreenBrightness = UIScreen.main.brightness
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = ScreenBrightnessIosPlugin(registration: registrar)
        instance.methodChannel = FlutterMethodChannel(name: "github.com/aaassseee/screen_brightness", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: instance.methodChannel!)

        instance.systemScreenBrightnessChangedEventChannel = FlutterEventChannel(name: "github.com/aaassseee/screen_brightness/system_brightness_changed", binaryMessenger: registrar.messenger())
        instance.systemScreenBrightnessChangedEventChannel!.setStreamHandler(instance.systemScreenBrightnessChangedStreamHandler)

        instance.applicationScreenBrightnessChangedEventChannel = FlutterEventChannel(name: "github.com/aaassseee/screen_brightness/application_brightness_changed", binaryMessenger: registrar.messenger())
        instance.applicationScreenBrightnessChangedEventChannel!.setStreamHandler(instance.applicationScreenBrightnessChangedStreamHandler)
        
        // Use NotificationCenter with renamed methods to avoid Flutter delegate conflicts
        NotificationCenter.default.addObserver(instance, selector: #selector(instance.onAppDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(instance, selector: #selector(instance.onAppWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(instance, selector: #selector(instance.onAppWillTerminate), name: UIApplication.willTerminateNotification, object: nil)
    }

    private var currentScreen: UIScreen? {
        if #available(iOS 13.0, *) {
            for scene in UIApplication.shared.connectedScenes {
                if let windowScene = scene as? UIWindowScene {
                    return windowScene.screen
                }
            }
        }
        return UIScreen.main
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getSystemScreenBrightness":
            guard let sb = systemScreenBrightness else {
                result(FlutterError(code: "-11", message: "Could not found system screen brightness value", details: nil))
                return
            }
            result(sb)

        case "setSystemScreenBrightness":
            guard let params = call.arguments as? Dictionary<String, Any>, let brightness = params["brightness"] as? NSNumber else {
                result(FlutterError(code: "-2", message: "Unexpected error on null brightness", details: nil))
                return
            }
            let b = CGFloat(brightness.doubleValue)
            systemScreenBrightness = b
            handleSystemScreenBrightnessChanged(b)
            if applicationScreenBrightness == nil {
                setScreenBrightness(targetBrightness: b, animated: isAnimate)
                handleApplicationScreenBrightnessChanged(b)
            }
            result(nil)

        case "getApplicationScreenBrightness":
            result(currentScreen?.brightness ?? UIScreen.main.brightness)

        case "setApplicationScreenBrightness":
            guard let params = call.arguments as? Dictionary<String, Any>, let brightness = params["brightness"] as? NSNumber else {
                result(FlutterError(code: "-2", message: "Unexpected error on null brightness", details: nil))
                return
            }
            let b = CGFloat(brightness.doubleValue)
            setScreenBrightness(targetBrightness: b, animated: isAnimate)
            applicationScreenBrightness = b
            handleApplicationScreenBrightnessChanged(b)
            result(nil)

        case "resetApplicationScreenBrightness":
            guard let b = systemScreenBrightness else {
                result(FlutterError(code: "-2", message: "Unexpected error on null brightness", details: nil))
                return
            }
            setScreenBrightness(targetBrightness: b, animated: isAnimate)
            applicationScreenBrightness = nil
            handleApplicationScreenBrightnessChanged(b)
            result(nil)

        case "hasApplicationScreenBrightnessChanged":
            result(applicationScreenBrightness != nil)

        case "isAutoReset":
            result(isAutoReset)

        case "setAutoReset":
            guard let params = call.arguments as? Dictionary<String, Any>, let val = params["isAutoReset"] as? Bool else {
                result(FlutterError(code: "-2", message: "Unexpected error on null isAutoReset", details: nil))
                return
            }
            isAutoReset = val
            result(nil)

        case "isAnimate":
            result(isAnimate)

        case "setAnimate":
            guard let params = call.arguments as? Dictionary<String, Any>, let val = params["isAnimate"] as? Bool else {
                result(FlutterError(code: "-2", message: "Unexpected error on null isAnimate", details: nil))
                return
            }
            isAnimate = val
            result(nil)

        case "canChangeSystemBrightness":
            result(true)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func handleSystemScreenBrightnessChanged(_ brightness: CGFloat) {
        systemScreenBrightnessChangedStreamHandler.addScreenBrightnessToEventSink(brightness)
    }
    
    private func handleApplicationScreenBrightnessChanged(_ brightness: CGFloat) {
        applicationScreenBrightnessChangedStreamHandler.addScreenBrightnessToEventSink(brightness)
    }

    // MARK: - Renamed lifecycle handlers (no conflict with Flutter delegate)

    @objc private func onAppWillResignActive(_ notification: Notification) {
        guard isAutoReset else { return }
        pauseScreenBrightness()
        NotificationCenter.default.addObserver(self, selector: #selector(onScreenBrightnessChanged), name: UIScreen.brightnessDidChangeNotification, object: nil)
    }
    
    @objc private func onAppDidBecomeActive(_ notification: Notification) {
        guard isAutoReset else { return }
        NotificationCenter.default.removeObserver(self, name: UIScreen.brightnessDidChangeNotification, object: nil)
        systemScreenBrightness = currentScreen?.brightness ?? UIScreen.main.brightness
        handleSystemScreenBrightnessChanged(systemScreenBrightness!)
        if applicationScreenBrightness == nil {
            handleApplicationScreenBrightnessChanged(systemScreenBrightness!)
        }
        resumeScreenBrightness()
    }
    
    @objc private func onAppWillTerminate(_ notification: Notification) {
        terminateScreenBrightness()
    }
    
    @objc private func onScreenBrightnessChanged(_ notification: Notification) {
        guard let screenObject = notification.object, let brightness = (screenObject as AnyObject).brightness else { return }
        systemScreenBrightness = brightness
        handleSystemScreenBrightnessChanged(brightness)
        if applicationScreenBrightness == nil {
            handleApplicationScreenBrightnessChanged(brightness)
        }
    }
    
    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        NotificationCenter.default.removeObserver(self)
        methodChannel?.setMethodCallHandler(nil)
        applicationScreenBrightnessChangedEventChannel?.setStreamHandler(nil)
        systemScreenBrightnessChangedEventChannel?.setStreamHandler(nil)
    }

    public func setScreenBrightness(targetBrightness: CGFloat, animated: Bool, duration: TimeInterval = 1.0) {
        taskQueue.cancelAllOperations()
        let screen = currentScreen ?? UIScreen.main
        if !animated {
            screen.brightness = targetBrightness
            return
        }

        let currentBrightness = screen.brightness
        var framePerSecond = 60.0
        if #available(iOS 10.3, *) {
            framePerSecond = Double(screen.maximumFramesPerSecond)
        }
        let changes = 0.01 / (framePerSecond / 60.0)
        let step = changes * ((targetBrightness > currentBrightness) ? 1 : -1)

        taskQueue.addOperations(stride(from: currentBrightness, through: targetBrightness, by: step).map({ _brightness -> Operation in
            let blockOperation = BlockOperation()
            unowned let _unownedOperation = blockOperation
            blockOperation.addExecutionBlock({
                guard !_unownedOperation.isCancelled else { return }
                Thread.sleep(forTimeInterval: duration * changes)
                OperationQueue.main.addOperation({
                    (self.currentScreen ?? UIScreen.main).brightness = _brightness
                })
            })
            return blockOperation
        }), waitUntilFinished: false)
    }
    
    func pauseScreenBrightness() {
        guard let b = systemScreenBrightness else { return }
        setScreenBrightness(targetBrightness: b, animated: isAnimate, duration: 0.5)
    }
    
    func resumeScreenBrightness() {
        guard let b = applicationScreenBrightness else { return }
        setScreenBrightness(targetBrightness: b, animated: isAnimate, duration: 0.5)
    }
    
    func terminateScreenBrightness() {
        guard let b = systemScreenBrightness else { return }
        UIScreen.main.brightness = b
    }
}

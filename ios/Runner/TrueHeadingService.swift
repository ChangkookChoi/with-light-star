import Foundation
import CoreLocation
import Flutter

final class TrueHeadingService: NSObject, FlutterStreamHandler, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private var eventSink: FlutterEventSink?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.headingFilter = 1.0
    }

    // Flutter가 listen 시작할 때 호출됨
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events

        // 권한 요청 (이미 권한 있으면 조용히 지나갑니다)
        locationManager.requestWhenInUseAuthorization()

        // trueHeading 안정성을 위해 location도 함께 업데이트하는 편이 낫습니다.
        locationManager.startUpdatingLocation()

        if CLLocationManager.headingAvailable() {
            locationManager.startUpdatingHeading()
        } else {
            // heading 불가 디바이스면 null 보내지 말고 에러 형태로라도 알려줌
            events(["error": "heading_not_available"])
        }

        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        locationManager.stopUpdatingHeading()
        locationManager.stopUpdatingLocation()
        eventSink = nil
        return nil
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // iOS는 초기에는 trueHeading이 -1로 올 수 있음
        let isTrue = newHeading.trueHeading >= 0
        let heading = isTrue ? newHeading.trueHeading : newHeading.magneticHeading

        // headingAccuracy: 음수일 수 있음(유효하지 않음)
        let acc = newHeading.headingAccuracy

        eventSink?([
            "heading": heading,
            "isTrue": isTrue,
            "accuracy": acc
        ])
    }

    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        return true
    }
}

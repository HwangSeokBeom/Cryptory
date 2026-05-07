import Foundation

enum AppTestEnvironment {
    static var isRunningUnitTests: Bool {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if environment["XCTestConfigurationFilePath"] != nil {
            return true
        }
        return NSClassFromString("XCTestCase") != nil
        #else
        return false
        #endif
    }

    static var isRunningUITests: Bool {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        let arguments = ProcessInfo.processInfo.arguments
        return environment["CRYPTORY_UI_TEST_SCENARIO"] != nil
            || arguments.contains("-UITestMode")
        #else
        return false
        #endif
    }
}

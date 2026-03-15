import XCTest
@testable import CricCoachAI

final class CricCoachAITests: XCTestCase {
    
    // MARK: - AngleCalculator Tests
    
    func testAngleCalculation_RightAngle() {
        let a = CGPoint(x: 0, y: 1)
        let b = CGPoint(x: 0, y: 0) // vertex
        let c = CGPoint(x: 1, y: 0)
        let angle = AngleCalculator.angleBetween(a: a, b: b, c: c)
        XCTAssertEqual(angle, 90.0, accuracy: 0.1)
    }
    
    func testAngleCalculation_StraightLine() {
        let a = CGPoint(x: 0, y: 0)
        let b = CGPoint(x: 0.5, y: 0)
        let c = CGPoint(x: 1, y: 0)
        let angle = AngleCalculator.angleBetween(a: a, b: b, c: c)
        XCTAssertEqual(angle, 180.0, accuracy: 0.1)
    }
    
    func testAngleCalculation_AcuteAngle() {
        let a = CGPoint(x: 0, y: 0)
        let b = CGPoint(x: 0.5, y: 0)
        let c = CGPoint(x: 1, y: 1)
        let angle = AngleCalculator.angleBetween(a: a, b: b, c: c)
        XCTAssertLessThan(angle, 180.0)
        XCTAssertGreaterThan(angle, 0)
    }
    
    func testAngleCalculation_ZeroLength() {
        let a = CGPoint(x: 0, y: 0)
        let b = CGPoint(x: 0, y: 0) // same as a
        let c = CGPoint(x: 1, y: 0)
        let angle = AngleCalculator.angleBetween(a: a, b: b, c: c)
        XCTAssertEqual(angle, 0.0) // guard returns 0 for zero-length vectors
    }
    
    // MARK: - Severity Tests
    
    func testSeverityFromScore() {
        XCTAssertEqual(Severity(score: 30), .critical)
        XCTAssertEqual(Severity(score: 60), .moderate)
        XCTAssertEqual(Severity(score: 80), .minor)
        XCTAssertEqual(Severity(score: 95), .good)
    }
    
    // MARK: - PoseFrame Tests
    
    func testPoseFrameDistance() {
        let landmarks: [String: NormalizedPoint] = [
            BodyLandmark.leftShoulder.rawValue: NormalizedPoint(x: 0.3, y: 0.3),
            BodyLandmark.rightShoulder.rawValue: NormalizedPoint(x: 0.7, y: 0.3),
            BodyLandmark.leftAnkle.rawValue: NormalizedPoint(x: 0.25, y: 0.9),
            BodyLandmark.rightAnkle.rawValue: NormalizedPoint(x: 0.75, y: 0.9),
        ]
        let frame = PoseFrame(timestamp: 0, frameIndex: 0, landmarks: landmarks, confidence: [:])
        let shoulderWidth = frame.shoulderWidth
        XCTAssertNotNil(shoulderWidth)
        XCTAssertEqual(Double(shoulderWidth!), 0.4, accuracy: 0.01)
    }
    
    // MARK: - PosePhase Tests
    
    func testBattingPhasesOrder() {
        let phases = PosePhase.battingPhases
        XCTAssertEqual(phases.count, 6)
        XCTAssertEqual(phases.first, .stance)
        XCTAssertEqual(phases.last, .battingFollowThrough)
    }
    
    func testBowlingPhasesOrder() {
        let phases = PosePhase.bowlingPhases
        XCTAssertEqual(phases.count, 6)
        XCTAssertEqual(phases.first, .runUp)
        XCTAssertEqual(phases.last, .bowlingFollowThrough)
    }
}

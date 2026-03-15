import XCTest
@testable import CricCoachAI

/// Golden test suite for PhaseDetectionService.
/// Loads annotated videos from TestVideos/annotations/ and verifies
/// that detected phases match ground-truth annotations.
///
/// Run these as integration tests — they're slow (process real video).
/// Mark with `.timeLimit(.minutes(5))` or run separately.
final class PhaseDetectionGoldenTests: XCTestCase {
    
    // MARK: - Annotation Model
    
    struct VideoAnnotation: Codable {
        let videoFile: String
        let analysisType: String
        let sourceFps: Double
        let resolution: String
        let annotations: [String: PhaseAnnotation]
        let notes: String?
        
        enum CodingKeys: String, CodingKey {
            case videoFile = "video_file"
            case analysisType = "analysis_type"
            case sourceFps = "source_fps"
            case resolution
            case annotations
            case notes
        }
    }
    
    struct PhaseAnnotation: Codable {
        let startFrame: Int
        let endFrame: Int
        let keyFrame: Int
        
        enum CodingKeys: String, CodingKey {
            case startFrame = "start_frame"
            case endFrame = "end_frame"
            case keyFrame = "key_frame"
        }
    }
    
    // MARK: - Tolerances
    
    /// Maximum allowed deviation for key frame detection (in frames)
    let keyFrameTolerance = 5
    /// Minimum required recall (percentage of annotated phases that were detected)
    let minimumRecall: Double = 0.90
    /// Minimum required precision (percentage of detected phases that were correct)
    let minimumPrecision: Double = 0.85
    
    // MARK: - Test Runner
    
    /// Run golden tests against all annotated videos
    func testPhaseDetectionAgainstGoldenDataset() async throws {
        let annotationURLs = loadAnnotationFiles()
        
        guard !annotationURLs.isEmpty else {
            XCTFail("No annotation files found in TestVideos/annotations/. Add annotated videos first.")
            return
        }
        
        var totalAnnotatedPhases = 0
        var totalDetectedCorrectly = 0
        var totalDetectedPhases = 0
        var totalFalsePositives = 0
        
        for annotationURL in annotationURLs {
            let data = try Data(contentsOf: annotationURL)
            let annotation = try JSONDecoder().decode(VideoAnnotation.self, from: data)
            
            // Find the corresponding video file
            let videoURL = annotationURL
                .deletingLastPathComponent()  // annotations/
                .deletingLastPathComponent()  // TestVideos/
                .appendingPathComponent(annotation.videoFile)
            
            guard FileManager.default.fileExists(atPath: videoURL.path) else {
                print("⚠️ Skipping \(annotation.videoFile) — video file not found")
                continue
            }
            
            print("🎥 Testing: \(annotation.videoFile)")
            
            // Run the pipeline
            let poseService = PoseEstimationService()
            let poseSequence = try await poseService.processVideo(url: videoURL)
            
            let analysisType = AnalysisType(rawValue: annotation.analysisType) ?? .batting
            let phaseService = PhaseDetectionService()
            let detectedPhases = phaseService.detectPhases(
                in: poseSequence,
                analysisType: analysisType
            )
            
            // Compare against annotations
            let annotatedPhaseNames = Set(annotation.annotations.keys)
            let detectedPhaseNames = Set(detectedPhases.map { $0.phase.rawValue })
            
            // Calculate recall: how many annotated phases were detected?
            for (phaseName, expected) in annotation.annotations {
                totalAnnotatedPhases += 1
                
                if let detected = detectedPhases.first(where: { $0.phase.rawValue == phaseName }) {
                    // Check key frame is within tolerance
                    let keyFrameDiff = abs(detected.keyFrame - expected.keyFrame)
                    if keyFrameDiff <= keyFrameTolerance {
                        totalDetectedCorrectly += 1
                        print("  ✅ \(phaseName): keyFrame \(detected.keyFrame) (expected \(expected.keyFrame), diff=\(keyFrameDiff))")
                    } else {
                        print("  ⚠️ \(phaseName): keyFrame \(detected.keyFrame) (expected \(expected.keyFrame), diff=\(keyFrameDiff) > tolerance \(keyFrameTolerance))")
                    }
                } else {
                    print("  ❌ \(phaseName): NOT DETECTED (expected keyFrame \(expected.keyFrame))")
                }
            }
            
            // Calculate precision: were any false phases detected?
            totalDetectedPhases += detectedPhases.count
            let falsePositives = detectedPhaseNames.subtracting(annotatedPhaseNames)
            totalFalsePositives += falsePositives.count
            for fp in falsePositives {
                print("  🔴 FALSE POSITIVE: \(fp)")
            }
        }
        
        // Summary
        let recall = totalAnnotatedPhases > 0
            ? Double(totalDetectedCorrectly) / Double(totalAnnotatedPhases)
            : 0
        let precision = totalDetectedPhases > 0
            ? Double(totalDetectedPhases - totalFalsePositives) / Double(totalDetectedPhases)
            : 0
        
        print("\n📊 Golden Test Results:")
        print("  Annotated phases: \(totalAnnotatedPhases)")
        print("  Correctly detected: \(totalDetectedCorrectly)")
        print("  False positives: \(totalFalsePositives)")
        print("  Recall: \(String(format: "%.1f%%", recall * 100)) (minimum: \(String(format: "%.0f%%", minimumRecall * 100)))")
        print("  Precision: \(String(format: "%.1f%%", precision * 100)) (minimum: \(String(format: "%.0f%%", minimumPrecision * 100)))")
        
        XCTAssertGreaterThanOrEqual(recall, minimumRecall,
            "Recall \(String(format: "%.1f%%", recall * 100)) is below minimum \(String(format: "%.0f%%", minimumRecall * 100))")
        XCTAssertGreaterThanOrEqual(precision, minimumPrecision,
            "Precision \(String(format: "%.1f%%", precision * 100)) is below minimum \(String(format: "%.0f%%", minimumPrecision * 100))")
    }
    
    // MARK: - Helpers
    
    /// Find all annotation JSON files
    private func loadAnnotationFiles() -> [URL] {
        // Look in the TestVideos/annotations/ directory relative to the project root
        let bundle = Bundle(for: type(of: self))
        
        // Try bundle resource path first
        if let resourcePath = bundle.resourcePath {
            let annotationsDir = URL(fileURLWithPath: resourcePath)
                .appendingPathComponent("TestVideos")
                .appendingPathComponent("annotations")
            
            if let files = try? FileManager.default.contentsOfDirectory(
                at: annotationsDir,
                includingPropertiesForKeys: nil
            ) {
                return files.filter { $0.pathExtension == "json" }
            }
        }
        
        // Fallback: try project directory
        let projectDir = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()  // CricCoachAITests/
            .deletingLastPathComponent()  // Project root
        let annotationsDir = projectDir
            .appendingPathComponent("TestVideos")
            .appendingPathComponent("annotations")
        
        if let files = try? FileManager.default.contentsOfDirectory(
            at: annotationsDir,
            includingPropertiesForKeys: nil
        ) {
            return files.filter { $0.pathExtension == "json" }
        }
        
        return []
    }
}

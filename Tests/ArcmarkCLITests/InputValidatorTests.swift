import XCTest
@testable import ArcmarkCLI
@testable import ArcmarkData

final class InputValidatorTests: XCTestCase {

    // MARK: - validateNoControlChars

    func testAcceptsNormalText() {
        XCTAssertNoThrow(try InputValidator.validateNoControlChars("Hello World", field: "name"))
    }

    func testAcceptsUnicode() {
        XCTAssertNoThrow(try InputValidator.validateNoControlChars("Café ☕ 日本語", field: "name"))
    }

    func testAcceptsTab() {
        XCTAssertNoThrow(try InputValidator.validateNoControlChars("Hello\tWorld", field: "name"))
    }

    func testRejectsNullByte() {
        XCTAssertThrowsError(try InputValidator.validateNoControlChars("Hello\0World", field: "name")) { error in
            guard case CLIError.invalidInput(_, _, let reason) = error else {
                XCTFail("Expected invalidInput"); return
            }
            XCTAssertTrue(reason.contains("U+0000"))
        }
    }

    func testRejectsBellCharacter() {
        XCTAssertThrowsError(try InputValidator.validateNoControlChars("Hello\u{07}World", field: "name"))
    }

    func testRejectsNewline() {
        XCTAssertThrowsError(try InputValidator.validateNoControlChars("Hello\nWorld", field: "name"))
    }

    func testRejectsCarriageReturn() {
        XCTAssertThrowsError(try InputValidator.validateNoControlChars("Hello\rWorld", field: "name"))
    }

    func testRejectsDEL() {
        XCTAssertThrowsError(try InputValidator.validateNoControlChars("Hello\u{7F}World", field: "name"))
    }

    func testRejectsC1ControlCSI() {
        // U+009B (CSI) can introduce ANSI escape sequences in terminals
        XCTAssertThrowsError(try InputValidator.validateNoControlChars("Hello\u{9B}World", field: "name"))
    }

    // MARK: - validateNotEmpty

    func testAcceptsNonEmptyString() {
        XCTAssertNoThrow(try InputValidator.validateNotEmpty("Hello", field: "name"))
    }

    func testRejectsEmptyString() {
        XCTAssertThrowsError(try InputValidator.validateNotEmpty("", field: "name")) { error in
            guard case CLIError.invalidInput(_, let value, _) = error else {
                XCTFail("Expected invalidInput"); return
            }
            XCTAssertEqual(value, "(empty)")
        }
    }

    func testRejectsWhitespaceOnlyString() {
        XCTAssertThrowsError(try InputValidator.validateNotEmpty("   ", field: "name")) { error in
            guard case CLIError.invalidInput(_, let value, _) = error else {
                XCTFail("Expected invalidInput"); return
            }
            XCTAssertEqual(value, "(whitespace only)")
        }
    }

    // MARK: - validateNoPathTraversal

    func testAcceptsNormalPath() {
        XCTAssertNoThrow(try InputValidator.validateNoPathTraversal("Work/APIs/Internal", field: "folder"))
    }

    func testRejectsDoubleDot() {
        XCTAssertThrowsError(try InputValidator.validateNoPathTraversal("../etc/passwd", field: "folder"))
    }

    func testRejectsTilde() {
        XCTAssertThrowsError(try InputValidator.validateNoPathTraversal("~/Documents", field: "folder"))
    }

    // MARK: - validateColor

    func testAcceptsValidColor() throws {
        let color = try InputValidator.validateColor("ocean")
        XCTAssertEqual(color, .ocean)
    }

    func testAcceptsColorCaseInsensitive() throws {
        let color = try InputValidator.validateColor("OCEAN")
        XCTAssertEqual(color, .ocean)
    }

    func testRejectsInvalidColor() {
        XCTAssertThrowsError(try InputValidator.validateColor("purple")) { error in
            guard case CLIError.invalidInput(let field, _, let reason) = error else {
                XCTFail("Expected invalidInput"); return
            }
            XCTAssertEqual(field, "color")
            XCTAssertTrue(reason.contains("ember"))
            XCTAssertTrue(reason.contains("Blush"))
        }
    }

    // MARK: - validateURLScheme

    func testAcceptsHTTPS() {
        XCTAssertNoThrow(try InputValidator.validateURLScheme("https://example.com"))
    }

    func testAcceptsHTTP() {
        XCTAssertNoThrow(try InputValidator.validateURLScheme("http://example.com"))
    }

    func testRejectsJavascript() {
        XCTAssertThrowsError(try InputValidator.validateURLScheme("javascript:alert(1)")) { error in
            guard case CLIError.invalidInput(_, _, let reason) = error else {
                XCTFail("Expected invalidInput"); return
            }
            XCTAssertTrue(reason.contains("javascript"))
        }
    }

    func testRejectsFileScheme() {
        XCTAssertThrowsError(try InputValidator.validateURLScheme("file:///etc/passwd"))
    }

    func testRejectsDataScheme() {
        XCTAssertThrowsError(try InputValidator.validateURLScheme("data:text/html,<h1>hi</h1>"))
    }

    func testRejectsInvalidURL() {
        XCTAssertThrowsError(try InputValidator.validateURLScheme("not a url at all"))
    }

    // MARK: - CLIError.toJSON

    func testNotFoundErrorJSON() {
        let error = CLIError.notFound(entity: "workspace", reference: "foo", suggestions: ["Foo"])
        let json = error.toJSON()
        XCTAssertEqual(json["error"] as? String, "not_found")
        XCTAssertEqual(json["entity"] as? String, "workspace")
        XCTAssertEqual(json["reference"] as? String, "foo")
        XCTAssertNotNil(json["message"])
        XCTAssertNotNil(json["hint"])
        XCTAssertEqual((json["suggestions"] as? [String])?.first, "Foo")
    }

    func testAmbiguousReferenceErrorJSON() {
        let error = CLIError.ambiguousReference(entity: "workspace", reference: "Work", candidates: ["Work (abc...)", "Work (def...)"])
        let json = error.toJSON()
        XCTAssertEqual(json["error"] as? String, "ambiguous_reference")
        XCTAssertEqual((json["candidates"] as? [String])?.count, 2)
        XCTAssertNotNil(json["message"])
    }

    func testInvalidInputErrorJSON() {
        let error = CLIError.invalidInput(field: "color", value: "purple", reason: "not a valid color")
        let json = error.toJSON()
        XCTAssertEqual(json["error"] as? String, "invalid_input")
        XCTAssertEqual(json["field"] as? String, "color")
        XCTAssertNotNil(json["message"])
    }

    func testValidationFailedErrorJSON() {
        let error = CLIError.validationFailed(message: "Cannot delete last workspace")
        let json = error.toJSON()
        XCTAssertEqual(json["error"] as? String, "validation_failed")
        XCTAssertNotNil(json["message"])
    }

    func testDataErrorJSON() {
        let error = CLIError.dataError(message: "Corrupt file")
        let json = error.toJSON()
        XCTAssertEqual(json["error"] as? String, "data_error")
        XCTAssertNotNil(json["message"])
    }
}

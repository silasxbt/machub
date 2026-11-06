import AppKit
import Foundation

@MainActor
enum DiagnosticReportExporter {
    static func exportPDF(markdownAt markdownURL: URL, to destination: URL) throws {
        let markdown = try String(contentsOf: markdownURL, encoding: .utf8)
        let attributed = try NSAttributedString(
            markdown: Data(markdown.utf8),
            options: .init(interpretedSyntax: .full),
            baseURL: markdownURL.deletingLastPathComponent()
        )

        let pageSize = NSSize(width: 595, height: 842)
        let margins = NSEdgeInsets(top: 42, left: 46, bottom: 42, right: 46)
        let printableSize = NSSize(width: pageSize.width - margins.left - margins.right, height: pageSize.height - margins.top - margins.bottom)
        let textView = NSTextView(frame: NSRect(origin: .zero, size: printableSize))
        textView.isEditable = false
        textView.isSelectable = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainer?.containerSize = NSSize(width: printableSize.width, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textStorage?.setAttributedString(attributed)
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        let contentHeight = (textView.layoutManager?.usedRect(for: textView.textContainer!).height ?? printableSize.height) + 20
        textView.frame.size.height = max(printableSize.height, contentHeight)

        let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
        printInfo.paperSize = pageSize
        printInfo.topMargin = margins.top
        printInfo.leftMargin = margins.left
        printInfo.bottomMargin = margins.bottom
        printInfo.rightMargin = margins.right
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        let data = NSMutableData()
        let operation = NSPrintOperation.pdfOperation(with: textView, inside: textView.bounds, to: data, printInfo: printInfo)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        guard operation.run() else {
            throw DiagnosticExportError.pdfCreationFailed
        }
        try data.write(to: destination, options: .atomic)
    }

    static func openInBrowser(_ pdfURL: URL) {
        let workspace = NSWorkspace.shared
        if let safari = workspace.urlForApplication(withBundleIdentifier: "com.apple.Safari") {
            workspace.open([pdfURL], withApplicationAt: safari, configuration: NSWorkspace.OpenConfiguration())
        } else {
            workspace.open(pdfURL)
        }
    }
}

enum DiagnosticExportError: LocalizedError {
    case pdfCreationFailed

    var errorDescription: String? {
        switch self {
        case .pdfCreationFailed: "无法生成诊断 PDF"
        }
    }
}

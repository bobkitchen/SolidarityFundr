//
//  PaymentEditWindow.swift
//  SolidarityFundr
//
//  Created on 7/21/25.
//

import SwiftUI

struct PaymentEditWindow: View {
    let payment: Payment
    @StateObject private var viewModel = PaymentViewModel()
    @Environment(\.dismiss) private var dismiss
    let onSave: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Edit Payment")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("Modify payment details for \(payment.member?.name ?? "Unknown")")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Payment Form with custom save handling
            PaymentFormViewWrapper(
                viewModel: viewModel,
                editingPayment: payment,
                onSave: {
                    onSave?()
                    NSApp.keyWindow?.close()
                }
            )
        }
        .frame(width: 600, height: 700)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// Wrapper to intercept save completion
struct PaymentFormViewWrapper: View {
    @ObservedObject var viewModel: PaymentViewModel
    let editingPayment: Payment
    let onSave: () -> Void
    
    var body: some View {
        PaymentFormView(
            viewModel: viewModel,
            editingPayment: editingPayment
        )
        .onReceive(NotificationCenter.default.publisher(for: .paymentSaved)) { _ in
            onSave()
        }
    }
}

// Notification for payment saved
extension Notification.Name {
    static let paymentSaved = Notification.Name("paymentSaved")
    static let loanBalanceUpdated = Notification.Name("loanBalanceUpdated")
}

// Window management helper
struct PaymentEditWindowController {
    static func openEditWindow(for payment: Payment, onSave: @escaping () -> Void) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 700),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Edit Payment"
        window.center()
        window.setFrameAutosaveName("PaymentEditWindow")
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.minSize = NSSize(width: 500, height: 600)
        window.maxSize = NSSize(width: 800, height: 900)
        
        let editView = PaymentEditWindow(payment: payment, onSave: {
            onSave()
            window.close()
        })
        window.contentView = NSHostingView(rootView: editView)
        
        window.makeKeyAndOrderFront(nil)
        
        // Store window reference to prevent deallocation
        WindowManager.shared.addWindow(window)
    }
}

// Window manager to keep references
class WindowManager {
    static let shared = WindowManager()
    private var windows: Set<NSWindow> = []
    
    func addWindow(_ window: NSWindow) {
        windows.insert(window)
        
        // Remove from set when window closes
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            self.windows.remove(window)
        }
    }
}
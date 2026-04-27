//
//  CloudKitStatusView.swift
//  SolidarityFundr
//
//  Created on 7/20/25.
//

import SwiftUI
import CloudKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct CloudKitStatusView: View {
    @StateObject private var syncManager = CloudKitSyncManager.shared
    @State private var cloudKitStatus = "Checking..."
    @State private var showingDetails = false
    
    var body: some View {
        HStack(spacing: 8) {
            syncStatusIcon
            
            VStack(alignment: .leading, spacing: 2) {
                Text(syncManager.syncStatus.displayText)
                    .font(.caption)
                    .foregroundStyle(syncStatusColor)
                
                if let lastSync = syncManager.lastSyncDate {
                    Text("Last sync: \(formatSyncTime(lastSync))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            
            if case .error = syncManager.syncStatus {
                Button("Details") {
                    showingDetails = true
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(syncStatusColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture {
            showingDetails = true
        }
        .popover(isPresented: $showingDetails) {
            CloudKitDetailsView()
        }
        .task {
            cloudKitStatus = await syncManager.getCloudKitStatusMessage()
        }
    }
    
    private var syncStatusIcon: some View {
        Group {
            switch syncManager.syncStatus {
            case .idle:
                if syncManager.isOnline {
                    Image(systemName: "icloud")
                } else {
                    Image(systemName: "icloud.slash")
                }
            case .syncing:
                ProgressView()
                    .scaleEffect(0.7)
            case .success:
                Image(systemName: "icloud.and.arrow.up")
            case .error:
                Image(systemName: "icloud.slash")
            }
        }
        .foregroundStyle(syncStatusColor)
        .font(.caption)
    }
    
    private var syncStatusColor: Color {
        switch syncManager.syncStatus {
        case .idle:
            return syncManager.isOnline ? .blue : .gray
        case .syncing:
            return .blue
        case .success:
            return .green
        case .error:
            return .red
        }
    }
    
    private func formatSyncTime(_ date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)
        
        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
    }
}

struct CloudKitDetailsView: View {
    @StateObject private var syncManager = CloudKitSyncManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var cloudKitStatus = "Checking..."
    @State private var accountStatus: CKAccountStatus = .couldNotDetermine
    @State private var copiedDiagnostic = false
    @State private var probeResult: CloudKitSyncManager.ProbeResult?
    @State private var probing = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                // CloudKit Account Status
                GroupBox("iCloud Account") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "person.icloud")
                                .foregroundStyle(.blue)
                            Text(cloudKitStatus)
                            Spacer()
                        }
                        Text("Container: \(syncManager.containerIdentifier)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }

                // Sync Status
                GroupBox("Sync Status") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: syncManager.isOnline ? "wifi" : "wifi.slash")
                                .foregroundStyle(syncManager.isOnline ? .green : .red)
                            Text(syncManager.isOnline ? "Online" : "Offline")
                        }

                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundStyle(.blue)
                            Text("Status: \(syncManager.syncStatus.displayText)")
                        }

                        if let lastSync = syncManager.lastSyncDate {
                            HStack {
                                Image(systemName: "clock")
                                    .foregroundStyle(.secondary)
                                Text("Last sync: \(DateFormatter.fullDateTime.string(from: lastSync))")
                            }
                        }
                    }
                }

                // Active Probe — answers "is data actually reaching iCloud?"
                // independently of whether sync events have fired.
                GroupBox("Live Probe") {
                    VStack(alignment: .leading, spacing: 8) {
                        if let result = probeResult {
                            probeRow(label: "Account",
                                     value: accountStatusName(result.accountStatus),
                                     ok: result.accountStatus == .available)
                            if let userID = result.userRecordID {
                                probeRow(label: "User Record",
                                         value: String(userID.prefix(12)) + "…",
                                         ok: true)
                            }
                            if let zoneCount = result.zoneCount {
                                probeRow(label: "Private Zones",
                                         value: "\(zoneCount)",
                                         ok: zoneCount > 0)
                            }
                            if let probeError = result.error {
                                Text(probeError)
                                    .foregroundStyle(.red)
                                    .font(.caption)
                                    .textSelection(.enabled)
                            }
                        } else {
                            Text("Press Run Probe to test the iCloud connection directly.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Button {
                            runProbe()
                        } label: {
                            if probing {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small)
                                    Text("Probing…")
                                }
                            } else {
                                Text("Run Probe")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.bordered)
                        .disabled(probing)
                    }
                }

                // Setup Error (separate from per-event errors — surfaces store-load failure)
                if let setupError = syncManager.setupErrorDescription {
                    GroupBox("Setup Error") {
                        Text(setupError)
                            .foregroundStyle(.red)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                }

                // Last Event Error
                if let error = syncManager.syncError {
                    GroupBox("Last Sync Error") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(error)
                                .foregroundStyle(.red)
                                .font(.caption)
                                .textSelection(.enabled)

                            Button("Clear Error") {
                                syncManager.clearSyncError()
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                // Manual Actions
                GroupBox("Actions") {
                    VStack(spacing: 8) {
                        Button("Save Local Changes") {
                            syncManager.saveAndSurfaceState()
                        }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.borderedProminent)

                        Button(copiedDiagnostic ? "Copied!" : "Copy Diagnostic Info") {
                            copyDiagnostic()
                        }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.bordered)

                        Text("CloudKit propagates remote changes automatically via silent push — there's no public API to force a fetch.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }

                Spacer()
            }
            .padding()
            .frame(width: 360, height: 680)
            .navigationTitle("CloudKit Sync")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            cloudKitStatus = await syncManager.getCloudKitStatusMessage()
            accountStatus = await syncManager.checkCloudKitStatus()
        }
    }

    private func runProbe() {
        probing = true
        Task {
            let result = await syncManager.probeCloudKit()
            await MainActor.run {
                probeResult = result
                accountStatus = result.accountStatus
                probing = false
            }
        }
    }

    private func probeRow(label: String, value: String, ok: Bool) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ok ? .green : .orange)
            Text(label)
                .font(.caption)
            Spacer()
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private func accountStatusName(_ status: CKAccountStatus) -> String {
        switch status {
        case .available: return "available"
        case .noAccount: return "no account"
        case .restricted: return "restricted"
        case .couldNotDetermine: return "unknown"
        case .temporarilyUnavailable: return "temporarily unavailable"
        @unknown default: return "unknown"
        }
    }

    private func copyDiagnostic() {
        let text = syncManager.diagnosticSummary(accountStatus: accountStatus)
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
        copiedDiagnostic = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run { copiedDiagnostic = false }
        }
    }
}

// Helper extension for date formatting
extension DateFormatter {
    static let fullDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
}

#Preview {
    CloudKitStatusView()
}

#Preview("Details") {
    CloudKitDetailsView()
}
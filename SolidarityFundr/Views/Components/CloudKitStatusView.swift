//
//  CloudKitStatusView.swift
//  SolidarityFundr
//
//  Created on 7/20/25.
//

import SwiftUI

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
                    .foregroundColor(syncStatusColor)
                
                if let lastSync = syncManager.lastSyncDate {
                    Text("Last sync: \(formatSyncTime(lastSync))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            if case .error = syncManager.syncStatus {
                Button("Retry") {
                    syncManager.forceSyncNow()
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(syncStatusColor.opacity(0.1))
        .cornerRadius(6)
        .onTapGesture {
            if case .idle = syncManager.syncStatus {
                syncManager.forceSyncNow()
            } else {
                showingDetails = true
            }
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
        .foregroundColor(syncStatusColor)
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
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                // CloudKit Account Status
                GroupBox("iCloud Account") {
                    HStack {
                        Image(systemName: "person.icloud")
                            .foregroundColor(.blue)
                        Text(cloudKitStatus)
                        Spacer()
                    }
                }
                
                // Sync Status
                GroupBox("Sync Status") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: syncManager.isOnline ? "wifi" : "wifi.slash")
                                .foregroundColor(syncManager.isOnline ? .green : .red)
                            Text(syncManager.isOnline ? "Online" : "Offline")
                        }
                        
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundColor(.blue)
                            Text("Status: \(syncManager.syncStatus.displayText)")
                        }
                        
                        if let lastSync = syncManager.lastSyncDate {
                            HStack {
                                Image(systemName: "clock")
                                    .foregroundColor(.secondary)
                                Text("Last sync: \(DateFormatter.fullDateTime.string(from: lastSync))")
                            }
                        }
                    }
                }
                
                // Error Details
                if let error = syncManager.syncError {
                    GroupBox("Error Details") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(error)
                                .foregroundColor(.red)
                                .font(.caption)
                            
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
                        Button("Sync Now") {
                            syncManager.forceSyncNow()
                            dismiss()
                        }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.borderedProminent)
                        
                        Text("The app automatically syncs every 3 minutes when online.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                
                Spacer()
            }
            .padding()
            .frame(width: 300, height: 400)
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
//
//  FloatingSidebar.swift
//  SolidarityFundr
//
//  Created on 7/20/25.
//  Floating overlay sidebar matching Transcriptly implementation
//

import SwiftUI

enum SidebarSection: String, CaseIterable {
    case overview = "Overview"
    case members = "Members"
    case loans = "Loans"
    case payments = "Payments"
    case reports = "Reports"
    case settings = "Settings"
    
    var icon: String {
        switch self {
        case .overview: return "chart.line.uptrend.xyaxis"
        case .members: return "person.3.fill"
        case .loans: return "creditcard.fill"
        case .payments: return "dollarsign.circle.fill"
        case .reports: return "doc.text.fill"
        case .settings: return "gear"
        }
    }
    
    var color: Color {
        switch self {
        case .overview: return .blue
        case .members: return .green
        case .loans: return .orange
        case .payments: return .purple
        case .reports: return .pink
        case .settings: return .gray
        }
    }
}

struct FloatingSidebar: View {
    @Binding var selectedSection: Int
    @State private var hoveredSection: SidebarSection?
    @EnvironmentObject var dataManager: DataManager
    
    // Convert Int to SidebarSection
    private var currentSection: SidebarSection {
        let sections = SidebarSection.allCases
        guard selectedSection < sections.count else { return .overview }
        return sections[selectedSection]
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 28px drag region for traffic lights as per macOS 26 guide
            Color.clear
                .frame(height: 28)
                .contentShape(Rectangle())
            
            // Header with 12px inset from drag region
            sidebarHeader
                .padding(.top, 12)
            
            // Navigation items
            VStack(spacing: 2) {
                ForEach(SidebarSection.allCases, id: \.self) { section in
                    sidebarItem(for: section)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 4) // Small gap after header
            
            Spacer()
            
            // Fund Status
            fundStatusCard
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial) // Use ultraThinMaterial as per macOS 26 guide
    }
    
    @ViewBuilder
    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "building.columns.fill")
                .font(.system(size: 32, weight: .medium))
                .foregroundColor(.blue)
            
            Text("Solidarity Fund")
                .font(DesignSystem.Typography.cardTitle)
                .foregroundColor(.primaryText)
                
            Text("Parachichi House")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
    
    @ViewBuilder
    private func sidebarItem(for section: SidebarSection) -> some View {
        Button(action: {
            selectedSection = SidebarSection.allCases.firstIndex(of: section) ?? 0
        }) {
            HStack(spacing: 12) {
                Image(systemName: section.icon)
                    .font(.system(size: 16))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(itemIconColor(for: section))
                    .frame(width: 20)
                
                Text(section.rawValue)
                    .font(currentSection == section ? DesignSystem.Typography.navItemSelected : DesignSystem.Typography.navItem)
                    .foregroundColor(itemTextColor(for: section))
                
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(itemBackground(for: section))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredSection = hovering ? section : nil
        }
        .hoverOverlay(
            isHovered: hoveredSection == section,
            cornerRadius: DesignSystem.cornerRadiusXSmall,
            intensity: 0.05
        )
        .cornerRadius(DesignSystem.cornerRadiusXSmall)
    }
    
    @ViewBuilder
    private func itemBackground(for section: SidebarSection) -> some View {
        if currentSection == section {
            RoundedRectangle(cornerRadius: DesignSystem.cornerRadiusXSmall)
                .fill(Color.accentColor.opacity(0.15))
        } else if hoveredSection == section {
            RoundedRectangle(cornerRadius: DesignSystem.cornerRadiusXSmall)
                .fill(.quaternary)
        } else {
            Color.clear
        }
    }
    
    private func itemIconColor(for section: SidebarSection) -> Color {
        return currentSection == section ? .accentColor : .secondaryText
    }
    
    private func itemTextColor(for section: SidebarSection) -> Color {
        return currentSection == section ? .primaryText : .secondaryText
    }
    
    @ViewBuilder
    private var fundStatusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fund Status")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(.tertiaryText)
                .textCase(.uppercase)
                .tracking(0.5)
            
            VStack(spacing: 6) {
                FundStatusRow(
                    label: "Balance",
                    value: formatCurrency(dataManager.fundSettings?.calculateFundBalance() ?? 0),
                    color: .green
                )
                
                FundStatusRow(
                    label: "Utilization",
                    value: String(format: "%.1f%%", (dataManager.fundSettings?.calculateUtilizationPercentage() ?? 0) * 100),
                    color: utilizationColor(dataManager.fundSettings?.calculateUtilizationPercentage() ?? 0)
                )
                
                FundStatusRow(
                    label: "Active Loans",
                    value: "\(dataManager.activeLoans.count)",
                    color: .orange
                )
            }
        }
        .padding(12)
        .performantGlass(
            material: .thinMaterial,
            cornerRadius: DesignSystem.cornerRadiusSmall,
            strokeOpacity: 0.1
        )
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        CurrencyFormatter.shared.format(amount)
    }
    
    private func utilizationColor(_ utilization: Double) -> Color {
        if utilization >= 0.6 {
            return .red
        } else if utilization >= 0.4 {
            return .orange
        } else {
            return .green
        }
    }
}

// MARK: - Status Row
private struct FundStatusRow: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack {
            Text(label)
                .font(DesignSystem.Typography.small)
                .foregroundColor(.secondaryText)
            Spacer()
            Text(value)
                .font(DesignSystem.Typography.caption)
                .fontWeight(.medium)
                .foregroundColor(color)
        }
    }
}

#Preview {
    HStack {
        FloatingSidebar(selectedSection: .constant(0))
            .frame(width: DesignSystem.sidebarExpandedWidth)
            .environmentObject(DataManager.shared)
        Spacer()
    }
    .padding(DesignSystem.sidebarPadding)
    .frame(width: 800, height: 600)
    .background(Color.primaryBackground)
}
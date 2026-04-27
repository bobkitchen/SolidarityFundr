//
//  FloatingSidebar.swift
//  SolidarityFundr
//
//  Created on 7/20/25.
//  Floating Liquid Glass Sidebar - macOS 26 Tahoe HIG Compliant
//

import SwiftUI

enum SidebarSection: String, CaseIterable {
    case overview = "Overview"
    case members = "Members"
    case loans = "Loans"
    case payments = "Payments"
    case reports = "Reports"

    var icon: String {
        switch self {
        case .overview: return "chart.line.uptrend.xyaxis"
        case .members: return "person.3.fill"
        case .loans: return "creditcard.fill"
        case .payments: return "dollarsign.circle.fill"
        case .reports: return "doc.text.fill"
        }
    }

    var color: Color {
        switch self {
        case .overview: return .blue
        case .members: return .green
        case .loans: return .orange
        case .payments: return .purple
        case .reports: return .pink
        }
    }
}

struct FloatingSidebar: View {
    @Binding var selectedSection: Int
    @Binding var isCollapsed: Bool
    @State private var hoveredSection: SidebarSection?
    @State private var refreshID = UUID()
    @EnvironmentObject var dataManager: DataManager

    // Convert Int to SidebarSection
    private var currentSection: SidebarSection {
        let sections = SidebarSection.allCases
        guard selectedSection < sections.count else { return .overview }
        return sections[selectedSection]
    }

    var body: some View {
        sidebarContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .liquidGlassSidebar()
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Navigation sidebar")
            .onReceive(NotificationCenter.default.publisher(for: .transactionsUpdated)) { _ in
                refreshID = UUID()
            }
            .onReceive(NotificationCenter.default.publisher(for: .paymentSaved)) { _ in
                refreshID = UUID()
            }
            .onReceive(NotificationCenter.default.publisher(for: .memberDataUpdated)) { _ in
                refreshID = UUID()
            }
            .onReceive(NotificationCenter.default.publisher(for: .loanBalanceUpdated)) { _ in
                refreshID = UUID()
            }
            .id(refreshID)
    }

    @ViewBuilder
    private var sidebarContent: some View {
        VStack(spacing: 0) {
            // Add space at the top for traffic lights
            Color.clear
                .frame(height: 28)
                .frame(maxHeight: 28)

            // Rest of sidebar content wrapped in glass container for proper sampling
            GlassContainerCompat {
                VStack(spacing: 0) {
                    if !isCollapsed {
                        sidebarHeader
                            .padding(.horizontal, 16)
                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }

                    // Toggle button
                    HStack {
                        Spacer()
                        Button(action: toggleSidebar) {
                            Image(systemName: isCollapsed ? "sidebar.left" : "sidebar.leading")
                                .font(.system(size: 12))
                                .foregroundColor(.tertiaryText)
                        }
                        .buttonStyle(.plain)
                        .accessibleControl(label: isCollapsed ? "Expand sidebar" : "Collapse sidebar")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    // Navigation items
                    VStack(spacing: 2) {
                        ForEach(SidebarSection.allCases, id: \.self) { section in
                            sidebarItem(for: section)
                        }
                    }
                    .padding(.horizontal, 8)

                    Spacer()

                    // Fund status
                    if !isCollapsed {
                        fundStatusCard
                            .padding(.horizontal, 8)
                            .padding(.bottom, 12)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image("AvocadoLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)

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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Solidarity Fund, Parachichi House")
    }

    @ViewBuilder
    private func sidebarItem(for section: SidebarSection) -> some View {
        Button(action: {
            selectedSection = SidebarSection.allCases.firstIndex(of: section) ?? 0
        }) {
            HStack(spacing: isCollapsed ? 0 : 12) {
                Image(systemName: section.icon)
                    .font(.system(size: 16))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(itemIconColor(for: section))
                    .frame(width: 20)
                    .frame(maxWidth: isCollapsed ? .infinity : nil)

                if !isCollapsed {
                    Text(section.rawValue)
                        .font(currentSection == section ? DesignSystem.Typography.navItemSelected : DesignSystem.Typography.navItem)
                        .foregroundColor(itemTextColor(for: section))
                        .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .leading)))

                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .padding(.horizontal, isCollapsed ? 8 : 12)
            .background(
                Group {
                    if currentSection == section {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.thinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.12))
                            )
                    } else if hoveredSection == section {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredSection = hovering ? section : nil
        }
        .accessibilityLabel(section.rawValue)
        .accessibilityAddTraits(currentSection == section ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint("Navigate to \(section.rawValue)")
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
        .tertiaryGlass(cornerRadius: DesignSystem.cornerRadiusSmall)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Fund status: Balance \(formatCurrency(dataManager.fundSettings?.calculateFundBalance() ?? 0)), \(dataManager.activeLoans.count) active loans")
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

    private func toggleSidebar() {
        withAnimation(DesignSystem.gentleSpring) {
            isCollapsed.toggle()
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
        FloatingSidebar(
            selectedSection: .constant(0),
            isCollapsed: .constant(false)
        )
        .frame(width: DesignSystem.sidebarExpandedWidth)
        .environmentObject(DataManager.shared)
        Spacer()
    }
    .padding(DesignSystem.sidebarPadding)
    .frame(width: 800, height: 600)
    .background(Color.primaryBackground)
}

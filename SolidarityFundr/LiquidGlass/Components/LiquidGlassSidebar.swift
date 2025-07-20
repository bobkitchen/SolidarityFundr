//
//  LiquidGlassSidebar.swift
//  SolidarityFundr
//
//  Created on 7/20/25.
//  Liquid Glass Sidebar Implementation
//

import SwiftUI

// MARK: - Liquid Glass Sidebar
struct LiquidGlassSidebar: View {
    @Binding var selectedTab: Int
    @State private var hoveredItem: Int? = nil
    @Environment(\.colorScheme) var colorScheme
    
    let items: [SidebarItem] = [
        SidebarItem(id: 0, title: "Overview", icon: "chart.line.uptrend.xyaxis", color: .blue),
        SidebarItem(id: 1, title: "Members", icon: "person.3.fill", color: .green),
        SidebarItem(id: 2, title: "Loans", icon: "creditcard.fill", color: .orange),
        SidebarItem(id: 3, title: "Payments", icon: "dollarsign.circle.fill", color: .purple),
        SidebarItem(id: 4, title: "Reports", icon: "doc.text.fill", color: .pink),
        SidebarItem(id: 5, title: "Settings", icon: "gear", color: .gray)
    ]
    
    var body: some View {
        VStack(spacing: 12) {
            // App Title - Left aligned as per requirements
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "building.columns.fill")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(.blue)
                
                Text("Solidarity Fund")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                    
                Text("Parachichi House")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 8)
            
            Divider()
                .padding(.horizontal, 24)
            
            // Navigation Items
            VStack(spacing: 8) {
                ForEach(items) { item in
                    SidebarNavigationItem(
                        item: item,
                        isSelected: selectedTab == item.id,
                        isHovered: hoveredItem == item.id,
                        action: { selectedTab = item.id }
                    )
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            hoveredItem = hovering ? item.id : nil
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            
            Spacer()
            
            // Fund Status Card
            FundStatusCard()
                .padding(.horizontal, 12)
                .padding(.bottom, 20)
        }
        .padding(16)
        .frame(width: 280)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Sidebar Item Model
struct SidebarItem: Identifiable {
    let id: Int
    let title: String
    let icon: String
    let color: Color
}

// MARK: - Sidebar Navigation Item
struct SidebarNavigationItem: View {
    let item: SidebarItem
    let isSelected: Bool
    let isHovered: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: item.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isSelected ? item.color : .secondary)
                
                Text(item.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isSelected ? .primary : .secondary)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(height: 32)
            .background(
                Capsule()
                    .fill(isSelected ? item.color.opacity(0.2) : Color.clear)
                    .overlay(
                        Capsule()
                            .stroke(item.color.opacity(isSelected ? 0.3 : 0), lineWidth: 1)
                    )
            )
            .background(.ultraThinMaterial, in: Capsule())
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isHovered)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Fund Status Card
struct FundStatusCard: View {
    @EnvironmentObject var dataManager: DataManager
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Fund Status")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
            }
            
            VStack(spacing: 8) {
                StatusRow(
                    label: "Balance",
                    value: formatCurrency(dataManager.fundSettings?.calculateFundBalance() ?? 0),
                    color: .green
                )
                
                StatusRow(
                    label: "Utilization",
                    value: String(format: "%.1f%%", (dataManager.fundSettings?.calculateUtilizationPercentage() ?? 0) * 100),
                    color: utilizationColor(dataManager.fundSettings?.calculateUtilizationPercentage() ?? 0)
                )
                
                StatusRow(
                    label: "Active Loans",
                    value: "\(dataManager.activeLoans.count)",
                    color: .orange
                )
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
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
struct StatusRow: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(color)
        }
    }
}


// MARK: - Preview
#Preview {
    HStack(spacing: 0) {
        LiquidGlassSidebar(selectedTab: .constant(0))
            .environmentObject(DataManager.shared)
        
        Spacer()
    }
    .frame(height: 800)
}
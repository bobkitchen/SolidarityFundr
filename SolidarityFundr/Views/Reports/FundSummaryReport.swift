//
//  FundSummaryReport.swift
//  SolidarityFundr
//
//  Created on 8/01/25.
//

import SwiftUI
import Charts

struct FundSummaryReport: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var isGeneratingPDF = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var hasRecalculated = false
    
    private var fundSummary: FundSummary {
        FundCalculator.shared.generateFundSummary()
    }
    
    private var activeMembersCount: Int {
        dataManager.members.filter { $0.memberStatus == .active }.count
    }
    
    private var activeLoansData: [(member: String, amount: Double, balance: Double)] {
        dataManager.activeLoans.compactMap { loan in
            guard let memberName = loan.member?.name else { return nil }
            return (member: memberName, amount: loan.amount, balance: loan.balance)
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            reportHeader
            
            // Fund Overview Cards
            fundOverviewSection
            
            // Loan Summary
            loanSummarySection
            
            // Member Summary Table
            memberSummarySection
            
            // Export Options
            exportSection
        }
        .padding()
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            // Recalculate all member contributions on view load to fix any discrepancies
            if !hasRecalculated {
                dataManager.recalculateAllMemberContributions()
                hasRecalculated = true
            }
        }
    }
    
    // MARK: - Report Header
    private var reportHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fund Summary Report")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Comprehensive overview of the Solidarity Fund for all members")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text("Report Date: \(Date().formatted(date: .complete, time: .omitted))")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(10)
    }
    
    // MARK: - Fund Overview Section
    private var fundOverviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fund Overview")
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                MetricCard(
                    title: "Total Fund Balance",
                    value: CurrencyFormatter.shared.format(fundSummary.fundBalance),
                    icon: "banknote.fill",
                    color: .green
                )
                
                MetricCard(
                    title: "Active Loans",
                    value: CurrencyFormatter.shared.format(fundSummary.totalActiveLoans),
                    icon: "creditcard.fill",
                    color: .orange
                )
                
                MetricCard(
                    title: "Utilization Rate",
                    value: String(format: "%.1f%%", fundSummary.utilizationPercentage * 100),
                    icon: "percent",
                    color: fundSummary.utilizationPercentage * 100 > 60 ? .red : .blue
                )
                
                MetricCard(
                    title: "Total Contributions",
                    value: CurrencyFormatter.shared.format(fundSummary.totalContributions),
                    icon: "arrow.down.circle.fill",
                    color: .blue
                )
                
                MetricCard(
                    title: "Active Members",
                    value: "\(activeMembersCount)",
                    icon: "person.3.fill",
                    color: .purple
                )
                
                MetricCard(
                    title: "Interest Earned",
                    value: CurrencyFormatter.shared.format(dataManager.fundSettings?.totalInterestApplied ?? 0),
                    icon: "chart.line.uptrend.xyaxis",
                    color: .mint
                )
            }
        }
    }
    
    // MARK: - Loan Summary Section
    private var loanSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Active Loans Summary")
                .font(.headline)
            
            if activeLoansData.isEmpty {
                Text("No active loans")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    // Summary stats
                    HStack {
                        Label("\(activeLoansData.count) active loans", systemImage: "number.circle.fill")
                        Spacer()
                        Text("Total: \(CurrencyFormatter.shared.format(fundSummary.totalActiveLoans))")
                            .fontWeight(.medium)
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
                    
                    // Active loans list
                    ForEach(activeLoansData, id: \.member) { loan in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(loan.member)
                                    .fontWeight(.medium)
                                Text("Original: \(CurrencyFormatter.shared.format(loan.amount))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(CurrencyFormatter.shared.format(loan.balance))
                                    .fontWeight(.medium)
                                    .foregroundColor(.orange)
                                Text("Outstanding")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                }
            }
        }
    }
    
    // MARK: - Member Summary Section
    private var memberSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("🏆 Savings Leaderboard")
                .font(.headline)
            
            // Table header
            HStack {
                Text("Rank")
                    .fontWeight(.medium)
                    .frame(width: 50, alignment: .center)
                
                Text("Member")
                    .fontWeight(.medium)
                    .frame(width: 250, alignment: .leading)
                
                Text("Total Saved")
                    .fontWeight(.medium)
                    .frame(width: 150, alignment: .trailing)
                
                Text("Active Loan")
                    .fontWeight(.medium)
                    .frame(width: 150, alignment: .trailing)
                
                Text("Status")
                    .fontWeight(.medium)
                    .frame(width: 100, alignment: .center)
                
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.1))
            
            // Member rows sorted by total contributions
            ScrollView {
                VStack(spacing: 0) {
                    let sortedMembers = dataManager.members
                        .filter { $0.memberStatus == .active }
                        .sorted { member1, member2 in
                            // First sort by total contributions
                            if member1.totalContributions != member2.totalContributions {
                                return member1.totalContributions > member2.totalContributions
                            }
                            // If contributions are equal, those without loans rank higher
                            return member1.totalActiveLoanBalance < member2.totalActiveLoanBalance
                        }
                    
                    ForEach(Array(sortedMembers.enumerated()), id: \.element.id) { index, member in
                        HStack {
                            // Rank with special styling for top 3
                            Group {
                                if index == 0 {
                                    Text("🥇")
                                        .font(.title3)
                                } else if index == 1 {
                                    Text("🥈")
                                        .font(.title3)
                                } else if index == 2 {
                                    Text("🥉")
                                        .font(.title3)
                                } else {
                                    Text("\(index + 1)")
                                        .fontWeight(.medium)
                                }
                            }
                            .frame(width: 50, alignment: .center)
                            
                            // Member name with crown for top saver
                            HStack(spacing: 4) {
                                if index == 0 {
                                    Text("👑")
                                }
                                Text(member.name ?? "Unknown")
                                    .fontWeight(index == 0 ? .bold : .regular)
                            }
                            .frame(width: 250, alignment: .leading)
                            
                            Text(CurrencyFormatter.shared.format(member.totalContributions))
                                .frame(width: 150, alignment: .trailing)
                                .fontWeight(index < 3 ? .semibold : .regular)
                                .foregroundColor(index == 0 ? .green : .primary)
                            
                            Text(CurrencyFormatter.shared.format(member.totalActiveLoanBalance))
                                .frame(width: 150, alignment: .trailing)
                                .foregroundColor(member.hasActiveLoans ? .orange : .primary)
                            
                            StatusBadge(status: member.memberStatus)
                                .frame(width: 100)
                            
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(index == 0 ? Color.yellow.opacity(0.1) : 
                                   index < 3 ? Color.secondary.opacity(0.05) : Color.clear)
                        
                        Divider()
                    }
                }
            }
            .frame(maxHeight: 300)
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(10)
    }
    
    // MARK: - Export Section
    private var exportSection: some View {
        VStack(spacing: 12) {
            Text("Export Report")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Button {
                Task {
                    await generateAndCopyPDF()
                }
            } label: {
                Label("Copy PDF to Clipboard", systemImage: "doc.on.clipboard.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isGeneratingPDF)
            
            if isGeneratingPDF {
                ProgressView("Generating report...")
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(10)
    }
    
    // MARK: - Helper Methods
    
    private func generateAndCopyPDF() async {
        isGeneratingPDF = true
        
        do {
            let generator = PDFGenerator()
            let pdfURL = try await generator.generateReport(
                type: .fundSummary,
                dataManager: dataManager,
                startDate: Calendar.current.date(byAdding: .month, value: -1, to: Date())!,
                endDate: Date()
            )
            
            // Read the PDF data
            let pdfData = try Data(contentsOf: pdfURL)
            
            // Copy to clipboard
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setData(pdfData, forType: .pdf)
            
            isGeneratingPDF = false
            
            // Show success message
            let alert = NSAlert()
            alert.messageText = "PDF Copied to Clipboard"
            alert.informativeText = "The Fund Summary Report has been copied to your clipboard. You can now paste it into any application that accepts PDF files."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.runModal()
            
        } catch {
            isGeneratingPDF = false
            errorMessage = "Failed to generate PDF: \(error.localizedDescription)"
            showingError = true
        }
    }
}

// MARK: - Metric Card Component
private struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title3)
                Spacer()
            }
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(10)
    }
}

#Preview {
    FundSummaryReport()
        .environmentObject(DataManager.shared)
}
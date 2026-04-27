//
//  PDFGenerator.swift
//  SolidarityFundr
//
//  Created on 7/19/25.
//

import Foundation
import PDFKit
import SwiftUI
import CoreGraphics
import AppKit

// MARK: - Thread-Safe Data Snapshots
// These plain structs capture Core Data values on the main thread
// so PDF drawing can safely happen on a background thread.

struct MemberSnapshot {
    let name: String
    let role: String
    let status: String
    let joinDate: Date?
    let totalContributions: Double
    let totalActiveLoanBalance: Double
    let availableContributions: Double
    let maximumLoanAmount: Double
    let memberID: UUID?

    init(member: Member) {
        self.name = member.name ?? "Unknown"
        self.role = member.memberRole.displayName
        self.status = member.memberStatus.rawValue.capitalized
        self.joinDate = member.joinDate
        self.totalContributions = member.totalContributions
        self.totalActiveLoanBalance = member.totalActiveLoanBalance
        self.availableContributions = member.availableContributions
        self.maximumLoanAmount = member.maximumLoanAmount
        self.memberID = member.memberID
    }
}

struct LoanSnapshot {
    let memberName: String
    let memberID: UUID?
    let amount: Double
    let balance: Double
    let issueDate: Date?
    let dueDate: Date?
    let isOverdue: Bool
    let wasOverridden: Bool

    init(loan: Loan) {
        self.memberName = loan.member?.name ?? "Unknown"
        self.memberID = loan.member?.memberID
        self.amount = loan.amount
        self.balance = loan.balance
        self.issueDate = loan.issueDate
        self.dueDate = loan.dueDate
        self.isOverdue = loan.isOverdue
        self.wasOverridden = loan.wasOverridden
    }
}

struct MonthlyReportData {
    let newMembersCount: Int
    let totalContributions: Double
    let loansIssuedCount: Int
    let totalLoansIssued: Double
}

struct AnalyticsData {
    let averageLoanAmount: Double
    let repaymentRate: Double
    let fundSummary: FundSummary
    let membersByRole: [(role: String, count: Int)]
    let activeLoansCount: Int
}

/// All the data needed to draw a PDF, captured on the main thread.
struct PDFReportData {
    let type: ReportsView.ReportType
    let startDate: Date
    let endDate: Date
    let fundSummary: FundSummary
    let activeMembers: [MemberSnapshot]
    let allMembers: [MemberSnapshot]
    let activeLoans: [LoanSnapshot]
    let memberSnapshot: MemberSnapshot?  // For member statement
    let monthlyReportData: MonthlyReportData?
    let analyticsData: AnalyticsData?
}

class PDFGenerator {

    // MARK: - Public Methods

    func generateReport(type: ReportsView.ReportType,
                       dataManager: DataManager,
                       member: Member? = nil,
                       startDate: Date,
                       endDate: Date) async throws -> URL {

        // Run everything on the main thread:
        // 1. Core Data access (viewContext is main-thread only)
        // 2. FundCalculator queries (uses viewContext)
        // 3. AppKit drawing operations (NSFont, NSBezierPath, NSImage.draw, etc.)
        //
        // A single-page PDF generates in <100ms so main-thread execution is fine.
        // The previous DispatchQueue.global() approach caused crashes/hangs because
        // AppKit drawing primitives (especially NSImage.draw) are not thread-safe.
        return try await MainActor.run {
            let reportData = self.snapshotData(
                type: type,
                dataManager: dataManager,
                member: member,
                startDate: startDate,
                endDate: endDate
            )
            return try self.createPDF(reportData: reportData)
        }
    }

    // MARK: - Data Snapshotting (Main Thread)

    /// Captures all Core Data values into plain Swift structs.
    /// Must be called on the main thread before dispatching to background.
    private func snapshotData(type: ReportsView.ReportType,
                             dataManager: DataManager,
                             member: Member?,
                             startDate: Date,
                             endDate: Date) -> PDFReportData {

        let fundSummary = FundCalculator.shared.generateFundSummary()

        let allMembers = dataManager.members.map { MemberSnapshot(member: $0) }
        let activeMembers = dataManager.members
            .filter { $0.memberStatus == .active }
            .map { MemberSnapshot(member: $0) }
        let activeLoans = dataManager.activeLoans.map { LoanSnapshot(loan: $0) }

        let memberSnapshot = member.map { MemberSnapshot(member: $0) }

        // Pre-calculate monthly report data if needed
        var monthlyReportData: MonthlyReportData?
        if type == .monthlyReport {
            let loansIssuedInPeriod = dataManager.activeLoans.filter { loan in
                guard let issueDate = loan.issueDate else { return false }
                return issueDate >= startDate && issueDate <= endDate
            }
            let totalLoansIssued = loansIssuedInPeriod.reduce(0) { $0 + $1.amount }

            var totalContributions: Double = 0
            for m in dataManager.members {
                if let payments = m.payments?.allObjects as? [Payment] {
                    for payment in payments {
                        if let date = payment.paymentDate,
                           date >= startDate && date <= endDate &&
                           payment.contributionAmount > 0 {
                            totalContributions += payment.contributionAmount
                        }
                    }
                }
            }

            let newMembers = dataManager.members.filter { m in
                guard let joinDate = m.joinDate else { return false }
                return joinDate >= startDate && joinDate <= endDate
            }

            monthlyReportData = MonthlyReportData(
                newMembersCount: newMembers.count,
                totalContributions: totalContributions,
                loansIssuedCount: loansIssuedInPeriod.count,
                totalLoansIssued: totalLoansIssued
            )
        }

        // Pre-calculate analytics data if needed
        var analyticsData: AnalyticsData?
        if type == .analytics {
            let loans = dataManager.activeLoans
            let averageLoanAmount = loans.isEmpty ? 0 : loans.reduce(0) { $0 + $1.amount } / Double(loans.count)

            let completedLoans = dataManager.members.flatMap { m in
                (m.loans?.allObjects as? [Loan] ?? []).filter { $0.loanStatus == .completed }
            }
            let totalLoans = dataManager.members.flatMap { m in
                (m.loans?.allObjects as? [Loan] ?? [])
            }
            let repaymentRate = totalLoans.isEmpty ? 0 : Double(completedLoans.count) / Double(totalLoans.count)

            let membersByRole = Dictionary(grouping: dataManager.members) { $0.memberRole }
            let roleData = membersByRole.map { (role: $0.key.displayName, count: $0.value.count) }
                .sorted { $0.count > $1.count }

            analyticsData = AnalyticsData(
                averageLoanAmount: averageLoanAmount,
                repaymentRate: repaymentRate,
                fundSummary: fundSummary,
                membersByRole: roleData,
                activeLoansCount: loans.count
            )
        }

        return PDFReportData(
            type: type,
            startDate: startDate,
            endDate: endDate,
            fundSummary: fundSummary,
            activeMembers: activeMembers,
            allMembers: allMembers,
            activeLoans: activeLoans,
            memberSnapshot: memberSnapshot,
            monthlyReportData: monthlyReportData,
            analyticsData: analyticsData
        )
    }

    // MARK: - PDF Creation (Background Thread - No Core Data Access)

    private func createPDF(reportData: PDFReportData) throws -> URL {

        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter

        // Create graphics context
        let data = NSMutableData()
        var mediaBox = pageRect
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let pdfContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw PDFError.contextCreationFailed
        }

        // Begin PDF page
        let pageInfo: [String: Any] = [:]
        pdfContext.beginPDFPage(pageInfo as CFDictionary)

        // Save graphics state
        NSGraphicsContext.saveGraphicsState()
        let nsContext = NSGraphicsContext(cgContext: pdfContext, flipped: false)
        NSGraphicsContext.current = nsContext

        // Draw content based on report type
        var currentY: CGFloat = pageRect.height - 50

        // Draw header
        currentY = drawHeader(type: reportData.type, in: pageRect, at: currentY)

        // Draw content based on report type
        switch reportData.type {
        case .fundOverview:
            currentY = drawFundOverview(fundSummary: reportData.fundSummary, in: pageRect, at: currentY)
        case .memberStatement:
            if let memberSnapshot = reportData.memberSnapshot {
                currentY = drawMemberStatement(member: memberSnapshot, in: pageRect, at: currentY)
            }
        case .loanSummary:
            currentY = drawLoanSummary(activeLoans: reportData.activeLoans, startDate: reportData.startDate, endDate: reportData.endDate, in: pageRect, at: currentY)
        case .monthlyReport:
            if let data = reportData.monthlyReportData {
                currentY = drawMonthlyReport(data: data, startDate: reportData.startDate, endDate: reportData.endDate, in: pageRect, at: currentY)
            }
        case .analytics:
            if let data = reportData.analyticsData {
                currentY = drawAnalyticsReport(data: data, in: pageRect, at: currentY)
            }
        case .fundSummary:
            currentY = drawFundSummary(fundSummary: reportData.fundSummary, activeMembers: reportData.activeMembers, activeLoans: reportData.activeLoans, in: pageRect, at: currentY)
        }

        // Draw footer
        drawFooter(in: pageRect)

        // Restore graphics state
        NSGraphicsContext.restoreGraphicsState()

        // End PDF page
        pdfContext.endPDFPage()
        pdfContext.closePDF()

        // Save to file
        let fileName = "\(reportData.type.rawValue.replacingOccurrences(of: " ", with: "_"))_\(Date().timeIntervalSince1970).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: url)

        return url
    }

    // MARK: - Drawing Methods (Use only snapshot data, never Core Data objects)

    private func drawHeader(type: ReportsView.ReportType, in pageRect: CGRect, at yPosition: CGFloat) -> CGFloat {
        // For Fund Summary, use compact header drawn in drawFundSummary
        if type == .fundSummary {
            return yPosition
        }

        var currentY = yPosition

        // Title
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 24),
            .foregroundColor: NSColor.black
        ]

        let title = "Parachichi House Solidarity Fund"
        let titleSize = title.size(withAttributes: titleAttributes)
        let titleRect = CGRect(x: (pageRect.width - titleSize.width) / 2, y: currentY - titleSize.height, width: titleSize.width, height: titleSize.height)
        title.draw(in: titleRect, withAttributes: titleAttributes)

        currentY -= titleSize.height + 10

        // Report type
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18),
            .foregroundColor: NSColor.darkGray
        ]

        let subtitle = type.rawValue
        let subtitleSize = subtitle.size(withAttributes: subtitleAttributes)
        let subtitleRect = CGRect(x: (pageRect.width - subtitleSize.width) / 2, y: currentY - subtitleSize.height, width: subtitleSize.width, height: subtitleSize.height)
        subtitle.draw(in: subtitleRect, withAttributes: subtitleAttributes)

        currentY -= subtitleSize.height + 5

        // Date
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        let dateString = "Generated on \(dateFormatter.string(from: Date()))"

        let dateAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.gray
        ]

        let dateSize = dateString.size(withAttributes: dateAttributes)
        let dateRect = CGRect(x: (pageRect.width - dateSize.width) / 2, y: currentY - dateSize.height, width: dateSize.width, height: dateSize.height)
        dateString.draw(in: dateRect, withAttributes: dateAttributes)

        currentY -= dateSize.height + 20

        // Draw separator line
        let context = NSGraphicsContext.current?.cgContext
        context?.setStrokeColor(NSColor.gray.cgColor)
        context?.setLineWidth(1)
        context?.move(to: CGPoint(x: 50, y: currentY))
        context?.addLine(to: CGPoint(x: pageRect.width - 50, y: currentY))
        context?.strokePath()

        return currentY - 20
    }

    private func drawFooter(in pageRect: CGRect) {
        let context = NSGraphicsContext.current?.cgContext

        // Draw footer separator line
        context?.saveGState()
        context?.setStrokeColor(NSColor.systemGray.withAlphaComponent(0.2).cgColor)
        context?.setLineWidth(0.5)
        context?.move(to: CGPoint(x: 40, y: 35))
        context?.addLine(to: CGPoint(x: pageRect.width - 40, y: 35))
        context?.strokePath()
        context?.restoreGState()

        let footerAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.darkGray
        ]

        let leftText = "Page 1 of 1"
        let centerText = "Parachichi House Solidarity Fund"
        let rightText = "Generated on \(DateFormatter.mediumDate.string(from: Date()))"

        // Left text
        leftText.draw(at: CGPoint(x: 40, y: 20), withAttributes: footerAttributes)

        // Center text
        let centerSize = centerText.size(withAttributes: footerAttributes)
        centerText.draw(at: CGPoint(x: (pageRect.width - centerSize.width) / 2, y: 20), withAttributes: footerAttributes)

        // Right text
        let rightSize = rightText.size(withAttributes: footerAttributes)
        rightText.draw(at: CGPoint(x: pageRect.width - rightSize.width - 40, y: 20), withAttributes: footerAttributes)
    }

    private func drawFundOverview(fundSummary: FundSummary, in pageRect: CGRect, at yPosition: CGFloat) -> CGFloat {
        var currentY = yPosition

        // Fund Balance Section
        currentY = drawSectionTitle("Fund Balance", at: currentY, in: pageRect)
        currentY -= 20

        let balanceText = CurrencyFormatter.shared.format(fundSummary.fundBalance)
        currentY = drawKeyValue("Current Balance:", value: balanceText, at: currentY, in: pageRect)
        currentY = drawKeyValue("Total Contributions:", value: CurrencyFormatter.shared.format(fundSummary.totalContributions), at: currentY, in: pageRect)
        currentY = drawKeyValue("Active Loans:", value: CurrencyFormatter.shared.format(fundSummary.totalActiveLoans), at: currentY, in: pageRect)
        currentY = drawKeyValue("Bob's Investment:", value: CurrencyFormatter.shared.format(fundSummary.bobRemainingInvestment), at: currentY, in: pageRect)

        currentY -= 30

        // Utilization Section
        currentY = drawSectionTitle("Fund Utilization", at: currentY, in: pageRect)
        currentY -= 20

        let utilizationPercent = String(format: "%.1f%%", fundSummary.utilizationPercentage * 100)
        currentY = drawKeyValue("Utilization:", value: utilizationPercent, at: currentY, in: pageRect)
        currentY = drawKeyValue("Active Members:", value: "\(fundSummary.activeMembers)", at: currentY, in: pageRect)
        currentY = drawKeyValue("Active Loans:", value: "\(fundSummary.activeLoansCount)", at: currentY, in: pageRect)

        return currentY
    }

    private func drawMemberStatement(member: MemberSnapshot, in pageRect: CGRect, at yPosition: CGFloat) -> CGFloat {
        var currentY = yPosition

        // Member Information
        currentY = drawSectionTitle("Member Information", at: currentY, in: pageRect)
        currentY -= 20

        currentY = drawKeyValue("Name:", value: member.name, at: currentY, in: pageRect)
        currentY = drawKeyValue("Role:", value: member.role, at: currentY, in: pageRect)
        currentY = drawKeyValue("Status:", value: member.status, at: currentY, in: pageRect)
        currentY = drawKeyValue("Join Date:", value: DateFormatter.mediumDate.string(from: member.joinDate ?? Date()), at: currentY, in: pageRect)

        currentY -= 30

        // Financial Summary
        currentY = drawSectionTitle("Financial Summary", at: currentY, in: pageRect)
        currentY -= 20

        currentY = drawKeyValue("Total Contributions:", value: CurrencyFormatter.shared.format(member.totalContributions), at: currentY, in: pageRect)
        currentY = drawKeyValue("Current Loan Balance:", value: CurrencyFormatter.shared.format(member.totalActiveLoanBalance), at: currentY, in: pageRect)
        currentY = drawKeyValue("Available for Loan:", value: CurrencyFormatter.shared.format(member.maximumLoanAmount), at: currentY, in: pageRect)

        return currentY
    }

    private func drawLoanSummary(activeLoans: [LoanSnapshot], startDate: Date, endDate: Date, in pageRect: CGRect, at yPosition: CGFloat) -> CGFloat {
        var currentY = yPosition

        currentY = drawSectionTitle("Loan Summary Report", at: currentY, in: pageRect)
        currentY -= 20

        currentY = drawKeyValue("Period:", value: "\(DateFormatter.mediumDate.string(from: startDate)) - \(DateFormatter.mediumDate.string(from: endDate))", at: currentY, in: pageRect)

        let totalLoanAmount = activeLoans.reduce(0) { $0 + $1.amount }
        let totalOutstanding = activeLoans.reduce(0) { $0 + $1.balance }
        let overdueLoans = activeLoans.filter { $0.isOverdue }

        currentY = drawKeyValue("Total Loans Issued:", value: CurrencyFormatter.shared.format(totalLoanAmount), at: currentY, in: pageRect)
        currentY = drawKeyValue("Outstanding Balance:", value: CurrencyFormatter.shared.format(totalOutstanding), at: currentY, in: pageRect)
        currentY = drawKeyValue("Number of Loans:", value: "\(activeLoans.count)", at: currentY, in: pageRect)
        currentY = drawKeyValue("Overdue Loans:", value: "\(overdueLoans.count)", at: currentY, in: pageRect)

        currentY -= 20

        // Draw loan details
        if !activeLoans.isEmpty {
            currentY = drawSectionTitle("Loan Details", at: currentY, in: pageRect)
            currentY -= 15

            for loan in activeLoans {
                let loanInfo = "\(loan.memberName) - \(CurrencyFormatter.shared.format(loan.amount))"
                let balanceInfo = "Balance: \(CurrencyFormatter.shared.format(loan.balance))"
                let statusInfo = loan.isOverdue ? " (OVERDUE)" : ""

                currentY = drawKeyValue("  Loan:", value: "\(loanInfo)\(statusInfo)", at: currentY, in: pageRect)
                currentY = drawKeyValue("  ", value: balanceInfo, at: currentY, in: pageRect)
                currentY -= 5
            }
        }

        return currentY
    }

    private func drawMonthlyReport(data: MonthlyReportData, startDate: Date, endDate: Date, in pageRect: CGRect, at yPosition: CGFloat) -> CGFloat {
        var currentY = yPosition

        currentY = drawSectionTitle("Monthly Report", at: currentY, in: pageRect)
        currentY -= 20

        currentY = drawKeyValue("Period:", value: "\(DateFormatter.mediumDate.string(from: startDate)) - \(DateFormatter.mediumDate.string(from: endDate))", at: currentY, in: pageRect)

        currentY = drawKeyValue("New Members:", value: "\(data.newMembersCount)", at: currentY, in: pageRect)
        currentY = drawKeyValue("Total Contributions:", value: CurrencyFormatter.shared.format(data.totalContributions), at: currentY, in: pageRect)
        currentY = drawKeyValue("Loans Issued:", value: "\(data.loansIssuedCount)", at: currentY, in: pageRect)
        currentY = drawKeyValue("Loan Amount Issued:", value: CurrencyFormatter.shared.format(data.totalLoansIssued), at: currentY, in: pageRect)

        return currentY
    }

    private func drawAnalyticsReport(data: AnalyticsData, in pageRect: CGRect, at yPosition: CGFloat) -> CGFloat {
        var currentY = yPosition

        currentY = drawSectionTitle("Analytics Report", at: currentY, in: pageRect)
        currentY -= 20

        let utilizationPercent = String(format: "%.1f%%", data.fundSummary.utilizationPercentage * 100)

        currentY = drawKeyValue("Average Loan Amount:", value: CurrencyFormatter.shared.format(data.averageLoanAmount), at: currentY, in: pageRect)
        currentY = drawKeyValue("Repayment Success Rate:", value: String(format: "%.1f%%", data.repaymentRate * 100), at: currentY, in: pageRect)
        currentY = drawKeyValue("Fund Utilization:", value: utilizationPercent, at: currentY, in: pageRect)
        currentY = drawKeyValue("Active Members:", value: "\(data.fundSummary.activeMembers)", at: currentY, in: pageRect)
        currentY = drawKeyValue("Active Loans:", value: "\(data.activeLoansCount)", at: currentY, in: pageRect)

        currentY -= 20

        // Member distribution
        currentY = drawSectionTitle("Member Distribution", at: currentY, in: pageRect)
        currentY -= 15

        for (role, count) in data.membersByRole {
            currentY = drawKeyValue("  \(role):", value: "\(count)", at: currentY, in: pageRect)
        }

        return currentY
    }

    private func drawFundSummary(fundSummary: FundSummary, activeMembers: [MemberSnapshot], activeLoans: [LoanSnapshot], in pageRect: CGRect, at yPosition: CGFloat) -> CGFloat {
        var currentY = yPosition

        // Compact Header
        currentY = drawCompactHeader(in: pageRect, at: currentY)
        currentY -= 20

        // Fund Overview Metrics Cards
        currentY = drawMetricCards(fundSummary: fundSummary, activeMembers: activeMembers.count, in: pageRect, at: currentY)
        currentY -= 30

        // Active Loans Section
        if !activeLoans.isEmpty {
            currentY = drawActiveLoansSection(loans: activeLoans, in: pageRect, at: currentY)
            currentY -= 30
        }

        // Member Summary Table - Main focus of the report
        currentY = drawMemberSummaryTable(activeMembers: activeMembers, in: pageRect, at: currentY)

        return currentY
    }

    private func drawCompactHeader(in pageRect: CGRect, at yPosition: CGFloat) -> CGFloat {
        var currentY = yPosition
        let leftMargin: CGFloat = 40
        let headerHeight: CGFloat = 70

        // Draw header background
        let context = NSGraphicsContext.current?.cgContext
        context?.saveGState()
        context?.setFillColor(NSColor.systemGray.withAlphaComponent(0.1).cgColor)
        let headerRect = CGRect(x: 0, y: currentY - headerHeight, width: pageRect.width, height: headerHeight)
        context?.fill(headerRect)
        context?.restoreGState()

        // Draw logo
        let logoSize: CGFloat = 50
        if let logoImage = NSImage(named: "AvocadoLogo") {
            let logoRect = CGRect(x: leftMargin, y: currentY - headerHeight + 10, width: logoSize, height: logoSize)
            logoImage.draw(in: logoRect)
        }

        // Title - Line 1
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
            .foregroundColor: NSColor.black
        ]
        let title1 = "Parachichi House - Solidarity Fund"
        title1.draw(at: CGPoint(x: leftMargin + logoSize + 15, y: currentY - 30), withAttributes: titleAttributes)

        // Title - Line 2 with current month and year
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.darkGray
        ]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMMM yyyy"
        let monthYear = dateFormatter.string(from: Date())
        let title2 = "Monthly Report - \(monthYear)"
        title2.draw(at: CGPoint(x: leftMargin + logoSize + 15, y: currentY - 50), withAttributes: subtitleAttributes)

        return currentY - headerHeight
    }

    private func drawMetricCards(fundSummary: FundSummary, activeMembers: Int, in pageRect: CGRect, at yPosition: CGFloat) -> CGFloat {
        let currentY = yPosition
        let leftMargin: CGFloat = 40
        let cardWidth: CGFloat = (pageRect.width - (leftMargin * 2) - 30) / 4 // 4 cards with spacing
        let cardHeight: CGFloat = 70  // Increased height for better label visibility
        let spacing: CGFloat = 10

        // Fix utilization calculation - multiply by 100 for percentage
        let utilizationPercentage = fundSummary.utilizationPercentage * 100

        // Define metrics
        let metrics = [
            ("Fund Balance", CurrencyFormatter.shared.format(fundSummary.fundBalance), NSColor.systemGreen),
            ("Active Loans", CurrencyFormatter.shared.format(fundSummary.totalActiveLoans), NSColor.systemOrange),
            ("Utilization", String(format: "%.1f%%", utilizationPercentage),
             utilizationPercentage > 60 ? NSColor.systemRed : NSColor.systemBlue),
            ("Members", "\(activeMembers)", NSColor.systemPurple)
        ]

        var xPosition = leftMargin

        for (title, value, color) in metrics {
            drawMetricCard(title: title, value: value, color: color,
                          at: CGRect(x: xPosition, y: currentY - cardHeight, width: cardWidth, height: cardHeight))
            xPosition += cardWidth + spacing
        }

        return currentY - cardHeight
    }

    private func drawMetricCard(title: String, value: String, color: NSColor, at rect: CGRect) {
        let context = NSGraphicsContext.current?.cgContext

        // Card background with subtle shadow
        context?.saveGState()

        // Shadow
        context?.setShadow(offset: CGSize(width: 0, height: 2), blur: 4, color: NSColor.black.withAlphaComponent(0.1).cgColor)

        // Background
        context?.setFillColor(NSColor.white.cgColor)
        let cardPath = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        cardPath.fill()

        context?.restoreGState()

        // Colored accent bar at bottom of card
        context?.saveGState()
        let accentHeight: CGFloat = 4
        let accentRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: accentHeight)
        context?.setFillColor(color.cgColor)
        context?.fill(accentRect)
        context?.restoreGState()

        // Title - positioned below the top edge
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.darkGray  // Explicit color for PDF
        ]
        title.draw(at: CGPoint(x: rect.minX + 10, y: rect.maxY - 20), withAttributes: titleAttributes)

        // Value - centered in the card
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
            .foregroundColor: NSColor.black  // Explicit color for PDF
        ]
        value.draw(at: CGPoint(x: rect.minX + 10, y: rect.minY + 20), withAttributes: valueAttributes)
    }

    private func drawActiveLoansSection(loans: [LoanSnapshot], in pageRect: CGRect, at yPosition: CGFloat) -> CGFloat {
        var currentY = yPosition
        let leftMargin: CGFloat = 40
        let rightMargin: CGFloat = 40
        let contentWidth = pageRect.width - leftMargin - rightMargin

        // Section title
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.black
        ]
        let title = "Active Loans (\(loans.count))"
        title.draw(at: CGPoint(x: leftMargin, y: currentY - 15), withAttributes: titleAttributes)
        currentY -= 25

        // Group loans by member
        let loansByMember = Dictionary(grouping: loans) { loan -> String in
            loan.memberID?.uuidString ?? "unknown"
        }

        // Sort members by name for consistent ordering
        let sortedMemberIDs = loansByMember.keys.sorted { id1, id2 in
            let name1 = loansByMember[id1]?.first?.memberName ?? ""
            let name2 = loansByMember[id2]?.first?.memberName ?? ""
            return name1 < name2
        }

        // Draw each member's loans
        var membersDrawn = 0
        for memberID in sortedMemberIDs {
            guard let memberLoans = loansByMember[memberID],
                  let firstLoan = memberLoans.first else { continue }

            // Limit to avoid overly long reports
            if membersDrawn >= 10 { break }

            currentY = drawMemberLoansGroup(memberName: firstLoan.memberName, loans: memberLoans, width: contentWidth, at: CGPoint(x: leftMargin, y: currentY))
            currentY -= 10
            membersDrawn += 1
        }

        // Show "more" message if truncated
        let totalMembers = sortedMemberIDs.count
        if totalMembers > 10 {
            let moreText = "... and \(totalMembers - 10) more members with active loans"
            let moreAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9),
                .foregroundColor: NSColor.darkGray
            ]
            moreText.draw(at: CGPoint(x: leftMargin + 10, y: currentY - 12), withAttributes: moreAttributes)
            currentY -= 20
        }

        return currentY
    }

    private func drawMemberLoansGroup(memberName: String, loans: [LoanSnapshot], width: CGFloat, at point: CGPoint) -> CGFloat {
        var currentY = point.y

        // Member name header
        let memberNameAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.black
        ]

        // Calculate total balance for this member
        let totalBalance = loans.reduce(0) { $0 + $1.balance }
        let memberText = "\(memberName) (\(loans.count) loan\(loans.count == 1 ? "" : "s") - Total: \(CurrencyFormatter.shared.format(totalBalance)))"
        memberText.draw(at: CGPoint(x: point.x, y: currentY - 12), withAttributes: memberNameAttributes)
        currentY -= 28  // Increased spacing after member header

        // Draw each loan for this member (indented)
        for loan in loans {
            currentY = drawLoanItem(loan: loan, width: width, at: CGPoint(x: point.x + 15, y: currentY), showMemberName: false)
            currentY -= 6  // Increased spacing between loans
        }

        return currentY
    }

    private func drawLoanItem(loan: LoanSnapshot, width: CGFloat, at point: CGPoint, showMemberName: Bool = true) -> CGFloat {
        let percentage = loan.amount > 0 ? ((loan.amount - loan.balance) / loan.amount) * 100 : 0

        // Loan details line
        let detailAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: NSColor.darkGray
        ]

        var loanText = ""
        if showMemberName {
            loanText = "\(loan.memberName): "
        }

        // Add issue date and due date for context
        let dueDateStr = loan.dueDate != nil ? DateFormatter.shortDate.string(from: loan.dueDate!) : "N/A"

        loanText += "\(CurrencyFormatter.shared.format(loan.amount)) → Balance: \(CurrencyFormatter.shared.format(loan.balance)) (Due: \(dueDateStr))"

        // Check if loan was overridden
        if loan.wasOverridden {
            loanText += " ⚠️"
        }

        loanText.draw(at: point, withAttributes: detailAttributes)

        // Progress bar - positioned to the right
        let progressX = point.x + 300
        let progressWidth: CGFloat = 80
        let progressHeight: CGFloat = 8
        let progressY = point.y - 2

        let context = NSGraphicsContext.current?.cgContext

        // Save the outermost state for the entire progress bar drawing
        context?.saveGState()

        // Progress background
        let bgPath = NSBezierPath(roundedRect: CGRect(x: progressX, y: progressY, width: progressWidth, height: progressHeight),
                                 xRadius: 5, yRadius: 5)
        context?.setFillColor(NSColor.systemGray.withAlphaComponent(0.2).cgColor)
        bgPath.fill()

        // Progress fill with gradient
        let progressFillWidth = progressWidth * CGFloat(percentage / 100)
        if progressFillWidth > 0 {
            let progressRect = CGRect(x: progressX, y: progressY,
                                     width: progressFillWidth,
                                     height: progressHeight)
            let progressPath = NSBezierPath(roundedRect: progressRect, xRadius: 5, yRadius: 5)

            // Create gradient using Core Graphics — use nested save/restore to isolate the clip
            context?.saveGState()
            progressPath.addClip()

            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let colors = [NSColor.systemGreen.withAlphaComponent(0.6).cgColor,
                          NSColor.systemGreen.cgColor] as CFArray
            let locations: [CGFloat] = [0.0, 1.0]

            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) {
                let startPoint = CGPoint(x: progressX, y: progressY + progressHeight/2)
                let endPoint = CGPoint(x: progressX + progressFillWidth, y: progressY + progressHeight/2)
                context?.drawLinearGradient(gradient, start: startPoint, end: endPoint, options: [])
            }
            context?.restoreGState()  // Restores clip from addClip()
        }

        // Border — drawn after restoring clip so it renders on the full background
        context?.setStrokeColor(NSColor.systemGray.withAlphaComponent(0.3).cgColor)
        context?.setLineWidth(0.5)
        bgPath.stroke()

        // Restore outermost state
        context?.restoreGState()

        // Percentage text
        let percentAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8, weight: .medium),
            .foregroundColor: NSColor.black
        ]
        let percentText = String(format: "%.0f%%", percentage)
        percentText.draw(at: CGPoint(x: progressX + progressWidth + 5, y: point.y - 2), withAttributes: percentAttributes)

        return point.y - 14  // Single line layout
    }

    private func drawMemberSummaryTable(activeMembers: [MemberSnapshot], in pageRect: CGRect, at yPosition: CGFloat) -> CGFloat {
        var currentY = yPosition
        let leftMargin: CGFloat = 40
        let rightMargin: CGFloat = 40
        let tableWidth = pageRect.width - leftMargin - rightMargin

        // Section background
        let context = NSGraphicsContext.current?.cgContext
        context?.saveGState()
        let sectionHeight: CGFloat = 300 // Approximate height
        let sectionRect = CGRect(x: leftMargin - 10, y: currentY - sectionHeight, width: tableWidth + 20, height: sectionHeight)
        context?.setFillColor(NSColor.systemGray.withAlphaComponent(0.03).cgColor)
        let sectionPath = NSBezierPath(roundedRect: sectionRect, xRadius: 8, yRadius: 8)
        sectionPath.fill()
        context?.restoreGState()

        // Section title with trophy emoji
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.black
        ]
        "🏆 Savings Leaderboard".draw(at: CGPoint(x: leftMargin, y: currentY - 15), withAttributes: titleAttributes)
        currentY -= 30

        // Table setup with rank column
        let columnWidths: [CGFloat] = [40, 200, 120, 120]
        let headers = ["Rank", "Name", "Total Saved", "Active Loan"]

        // Draw table header with background
        currentY = drawEnhancedTableHeader(headers, widths: columnWidths, at: currentY, leftMargin: leftMargin)
        currentY -= 2

        // Sort members by total contributions (highest first), then by loan status (no loans ranked higher)
        let sortedMembers = activeMembers.sorted { member1, member2 in
            if member1.totalContributions != member2.totalContributions {
                return member1.totalContributions > member2.totalContributions
            }
            return member1.totalActiveLoanBalance < member2.totalActiveLoanBalance
        }
        var totalContributions: Double = 0
        var totalLoans: Double = 0
        var rowIndex = 0

        for (index, member) in sortedMembers.enumerated() {
            // Determine rank display
            let rankDisplay: String
            if index == 0 {
                rankDisplay = "🥇"
            } else if index == 1 {
                rankDisplay = "🥈"
            } else if index == 2 {
                rankDisplay = "🥉"
            } else {
                rankDisplay = "\(index + 1)"
            }

            // Add crown emoji for top saver
            let nameDisplay = index == 0 ? "👑 \(member.name)" : member.name

            let values = [
                rankDisplay,
                nameDisplay,
                CurrencyFormatter.shared.format(member.totalContributions),
                CurrencyFormatter.shared.format(member.totalActiveLoanBalance)
            ]

            // Special highlighting for top 3 savers
            if index == 0 {
                // Gold background for top saver
                context?.saveGState()
                context?.setFillColor(NSColor.systemYellow.withAlphaComponent(0.15).cgColor)
                context?.fill(CGRect(x: leftMargin - 5, y: currentY - 20, width: columnWidths.reduce(0, +) + 10, height: 20))
                context?.restoreGState()
            } else if index < 3 {
                // Light background for 2nd and 3rd place
                context?.saveGState()
                context?.setFillColor(NSColor.systemGray.withAlphaComponent(0.1).cgColor)
                context?.fill(CGRect(x: leftMargin - 5, y: currentY - 20, width: columnWidths.reduce(0, +) + 10, height: 20))
                context?.restoreGState()
            } else if rowIndex % 2 == 1 {
                // Regular alternating rows
                context?.saveGState()
                context?.setFillColor(NSColor.systemGray.withAlphaComponent(0.05).cgColor)
                context?.fill(CGRect(x: leftMargin - 5, y: currentY - 20, width: columnWidths.reduce(0, +) + 10, height: 20))
                context?.restoreGState()
            }

            // Draw subtle row separator (horizontal line)
            context?.saveGState()
            context?.setStrokeColor(NSColor.systemGray.withAlphaComponent(0.15).cgColor)
            context?.setLineWidth(0.5)
            context?.move(to: CGPoint(x: leftMargin, y: currentY - 20))
            context?.addLine(to: CGPoint(x: leftMargin + columnWidths.reduce(0, +), y: currentY - 20))
            context?.strokePath()
            context?.restoreGState()

            // Draw vertical column separators
            context?.saveGState()
            context?.setStrokeColor(NSColor.systemGray.withAlphaComponent(0.1).cgColor)
            context?.setLineWidth(0.5)
            var xPos = leftMargin
            for (colIndex, width) in columnWidths.enumerated() {
                if colIndex < columnWidths.count - 1 {  // Don't draw after last column
                    xPos += width
                    context?.move(to: CGPoint(x: xPos, y: currentY))
                    context?.addLine(to: CGPoint(x: xPos, y: currentY - 20))
                }
            }
            context?.strokePath()
            context?.restoreGState()

            drawEnhancedTableRow(values, widths: columnWidths, at: currentY, leftMargin: leftMargin,
                               isNegative: member.availableContributions < 0)

            totalContributions += member.totalContributions
            totalLoans += member.totalActiveLoanBalance

            currentY -= 20
            rowIndex += 1
        }

        // Draw totals row with emphasis
        currentY -= 5

        // Totals background
        context?.saveGState()
        context?.setFillColor(NSColor.systemGray.withAlphaComponent(0.1).cgColor)
        context?.fill(CGRect(x: leftMargin - 5, y: currentY - 22, width: columnWidths.reduce(0, +) + 10, height: 24))
        context?.restoreGState()

        // Top border for totals
        context?.saveGState()
        context?.setStrokeColor(NSColor.systemGray.cgColor)
        context?.setLineWidth(1.5)
        context?.move(to: CGPoint(x: leftMargin, y: currentY + 2))
        context?.addLine(to: CGPoint(x: leftMargin + columnWidths.reduce(0, +), y: currentY + 2))
        context?.strokePath()
        context?.restoreGState()

        currentY -= 3
        let totalValues = [
            "",  // Empty rank column
            "TOTALS",
            CurrencyFormatter.shared.format(totalContributions),
            CurrencyFormatter.shared.format(totalLoans)
        ]
        drawEnhancedTableRow(totalValues, widths: columnWidths, at: currentY, leftMargin: leftMargin,
                           isBold: true, isNegative: false)

        return currentY - 25
    }

    private func drawEnhancedTableHeader(_ headers: [String], widths: [CGFloat], at yPosition: CGFloat, leftMargin: CGFloat) -> CGFloat {
        let context = NSGraphicsContext.current?.cgContext

        // Header background
        context?.saveGState()
        context?.setFillColor(NSColor.systemGray.withAlphaComponent(0.1).cgColor)
        let headerRect = CGRect(x: leftMargin - 5, y: yPosition - 20, width: widths.reduce(0, +) + 10, height: 20)
        context?.fill(headerRect)
        context?.restoreGState()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.black
        ]

        var xPosition = leftMargin
        for (index, header) in headers.enumerated() {
            let rect = CGRect(x: xPosition, y: yPosition - 16, width: widths[index], height: 15)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = index == 0 ? .left : .right

            var attrs = attributes
            attrs[.paragraphStyle] = paragraph

            header.draw(in: rect, withAttributes: attrs)
            xPosition += widths[index]
        }

        // Draw bottom border
        context?.saveGState()
        context?.setStrokeColor(NSColor.systemGray.withAlphaComponent(0.3).cgColor)
        context?.setLineWidth(1)
        context?.move(to: CGPoint(x: leftMargin, y: yPosition - 20))
        context?.addLine(to: CGPoint(x: leftMargin + widths.reduce(0, +), y: yPosition - 20))
        context?.strokePath()
        context?.restoreGState()

        return yPosition - 22
    }

    private func drawEnhancedTableRow(_ values: [String], widths: [CGFloat], at yPosition: CGFloat,
                                     leftMargin: CGFloat, isBold: Bool = false, isNegative: Bool = false) {
        let weight: NSFont.Weight = isBold ? .medium : .regular
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: weight),
            .foregroundColor: NSColor.black
        ]

        var xPosition = leftMargin
        for (index, value) in values.enumerated() {
            let rect = CGRect(x: xPosition, y: yPosition - 12, width: widths[index], height: 12)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = index == 0 ? .left : .right

            var attrs = attributes
            attrs[.paragraphStyle] = paragraph

            // Color negative available balances
            if index == 3 && isNegative && value.contains("-") {
                attrs[.foregroundColor] = NSColor.systemRed
            }

            value.draw(in: rect, withAttributes: attrs)
            xPosition += widths[index]
        }
    }

    private func drawTableHeader(_ headers: [String], widths: [CGFloat], at yPosition: CGFloat, in pageRect: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 11),
            .foregroundColor: NSColor.black
        ]

        var xPosition: CGFloat = 70
        for (index, header) in headers.enumerated() {
            let rect = CGRect(x: xPosition, y: yPosition - 15, width: widths[index], height: 15)
            header.draw(in: rect, withAttributes: attributes)
            xPosition += widths[index]
        }

        // Draw underline
        let context = NSGraphicsContext.current?.cgContext
        context?.setStrokeColor(NSColor.black.cgColor)
        context?.setLineWidth(0.5)
        context?.move(to: CGPoint(x: 70, y: yPosition - 17))
        context?.addLine(to: CGPoint(x: 70 + widths.reduce(0, +), y: yPosition - 17))
        context?.strokePath()
    }

    private func drawTableRow(_ values: [String], widths: [CGFloat], at yPosition: CGFloat, in pageRect: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.darkGray
        ]

        var xPosition: CGFloat = 70
        for (index, value) in values.enumerated() {
            let rect = CGRect(x: xPosition, y: yPosition - 12, width: widths[index], height: 12)
            value.draw(in: rect, withAttributes: attributes)
            xPosition += widths[index]
        }
    }

    // MARK: - Helper Methods

    private func drawSectionTitle(_ title: String, at yPosition: CGFloat, in pageRect: CGRect) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 16),
            .foregroundColor: NSColor.black
        ]

        let size = title.size(withAttributes: attributes)
        let rect = CGRect(x: 50, y: yPosition - size.height, width: size.width, height: size.height)
        title.draw(in: rect, withAttributes: attributes)

        return yPosition - size.height - 10
    }

    private func drawKeyValue(_ key: String, value: String, at yPosition: CGFloat, in pageRect: CGRect) -> CGFloat {
        let keyAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.darkGray
        ]

        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.black
        ]

        let keySize = key.size(withAttributes: keyAttributes)
        let keyRect = CGRect(x: 70, y: yPosition - keySize.height, width: 150, height: keySize.height)
        key.draw(in: keyRect, withAttributes: keyAttributes)

        let valueRect = CGRect(x: 230, y: yPosition - keySize.height, width: pageRect.width - 280, height: keySize.height)
        value.draw(in: valueRect, withAttributes: valueAttributes)

        return yPosition - keySize.height - 8
    }
}

// MARK: - PDF Error

enum PDFError: LocalizedError {
    case contextCreationFailed
    case documentCreationFailed

    var errorDescription: String? {
        switch self {
        case .contextCreationFailed:
            return "Failed to create PDF graphics context"
        case .documentCreationFailed:
            return "Failed to create PDF document"
        }
    }
}

// MARK: - Helper Extensions

extension DateFormatter {
    static let mediumDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()

    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yy"
        return formatter
    }()
}

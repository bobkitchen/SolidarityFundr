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

class PDFGenerator {
    
    // MARK: - Public Methods
    
    func generateReport(type: ReportsView.ReportType,
                       dataManager: DataManager,
                       member: Member? = nil,
                       startDate: Date,
                       endDate: Date) async throws -> URL {
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let url = try self.createPDF(
                        type: type,
                        dataManager: dataManager,
                        member: member,
                        startDate: startDate,
                        endDate: endDate
                    )
                    continuation.resume(returning: url)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - PDF Creation
    
    private func createPDF(type: ReportsView.ReportType,
                          dataManager: DataManager,
                          member: Member?,
                          startDate: Date,
                          endDate: Date) throws -> URL {
        
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
        
        // Create PDF document
        let pdfDocument = PDFDocument()
        
        // Create first page
        let pdfPage = PDFPage()
        
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
        currentY = drawHeader(type: type, in: pageRect, at: currentY)
        
        // Draw content based on report type
        switch type {
        case .fundOverview:
            currentY = drawFundOverview(dataManager: dataManager, in: pageRect, at: currentY)
        case .memberStatement:
            if let member = member {
                currentY = drawMemberStatement(member: member, dataManager: dataManager, in: pageRect, at: currentY)
            }
        case .loanSummary:
            currentY = drawLoanSummary(dataManager: dataManager, startDate: startDate, endDate: endDate, in: pageRect, at: currentY)
        case .monthlyReport:
            currentY = drawMonthlyReport(dataManager: dataManager, startDate: startDate, endDate: endDate, in: pageRect, at: currentY)
        case .analytics:
            currentY = drawAnalyticsReport(dataManager: dataManager, in: pageRect, at: currentY)
        }
        
        // Draw footer
        drawFooter(in: pageRect)
        
        // Restore graphics state
        NSGraphicsContext.restoreGraphicsState()
        
        // End PDF page
        pdfContext.endPDFPage()
        pdfContext.closePDF()
        
        // Save to file
        let fileName = "\(type.rawValue.replacingOccurrences(of: " ", with: "_"))_\(Date().timeIntervalSince1970).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try data.write(to: url)
        
        return url
    }
    
    // MARK: - Drawing Methods
    
    private func drawHeader(type: ReportsView.ReportType, in pageRect: CGRect, at yPosition: CGFloat) -> CGFloat {
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
        let footerAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.gray
        ]
        
        let footer = "Solidarity Fund Management System"
        let footerSize = footer.size(withAttributes: footerAttributes)
        let footerRect = CGRect(x: (pageRect.width - footerSize.width) / 2, y: 30, width: footerSize.width, height: footerSize.height)
        footer.draw(in: footerRect, withAttributes: footerAttributes)
    }
    
    private func drawFundOverview(dataManager: DataManager, in pageRect: CGRect, at yPosition: CGFloat) -> CGFloat {
        var currentY = yPosition
        let margin: CGFloat = 50
        let contentWidth = pageRect.width - (margin * 2)
        
        let fundSummary = FundCalculator.shared.generateFundSummary()
        
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
    
    private func drawMemberStatement(member: Member, dataManager: DataManager, in pageRect: CGRect, at yPosition: CGFloat) -> CGFloat {
        var currentY = yPosition
        
        // Member Information
        currentY = drawSectionTitle("Member Information", at: currentY, in: pageRect)
        currentY -= 20
        
        currentY = drawKeyValue("Name:", value: member.name ?? "Unknown", at: currentY, in: pageRect)
        currentY = drawKeyValue("Role:", value: member.memberRole.displayName, at: currentY, in: pageRect)
        currentY = drawKeyValue("Status:", value: member.memberStatus.rawValue.capitalized, at: currentY, in: pageRect)
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
    
    private func drawLoanSummary(dataManager: DataManager, startDate: Date, endDate: Date, in pageRect: CGRect, at yPosition: CGFloat) -> CGFloat {
        var currentY = yPosition
        
        currentY = drawSectionTitle("Loan Summary Report", at: currentY, in: pageRect)
        currentY -= 20
        
        currentY = drawKeyValue("Period:", value: "\(DateFormatter.mediumDate.string(from: startDate)) - \(DateFormatter.mediumDate.string(from: endDate))", at: currentY, in: pageRect)
        
        // Calculate actual loan summary data
        let allActiveLoans = dataManager.activeLoans
        let totalLoanAmount = allActiveLoans.reduce(0) { $0 + $1.amount }
        let totalOutstanding = allActiveLoans.reduce(0) { $0 + $1.balance }
        let overdueLoans = allActiveLoans.filter { $0.isOverdue }
        
        currentY = drawKeyValue("Total Loans Issued:", value: CurrencyFormatter.shared.format(totalLoanAmount), at: currentY, in: pageRect)
        currentY = drawKeyValue("Outstanding Balance:", value: CurrencyFormatter.shared.format(totalOutstanding), at: currentY, in: pageRect)
        currentY = drawKeyValue("Number of Loans:", value: "\(allActiveLoans.count)", at: currentY, in: pageRect)
        currentY = drawKeyValue("Overdue Loans:", value: "\(overdueLoans.count)", at: currentY, in: pageRect)
        
        currentY -= 20
        
        // Draw loan details
        if !allActiveLoans.isEmpty {
            currentY = drawSectionTitle("Loan Details", at: currentY, in: pageRect)
            currentY -= 15
            
            for loan in allActiveLoans {
                let memberName = loan.member?.name ?? "Unknown"
                let loanInfo = "\(memberName) - \(CurrencyFormatter.shared.format(loan.amount))"
                let balanceInfo = "Balance: \(CurrencyFormatter.shared.format(loan.balance))"
                let statusInfo = loan.isOverdue ? " (OVERDUE)" : ""
                
                currentY = drawKeyValue("  Loan:", value: "\(loanInfo)\(statusInfo)", at: currentY, in: pageRect)
                currentY = drawKeyValue("  ", value: balanceInfo, at: currentY, in: pageRect)
                currentY -= 5
            }
        }
        
        return currentY
    }
    
    private func drawMonthlyReport(dataManager: DataManager, startDate: Date, endDate: Date, in pageRect: CGRect, at yPosition: CGFloat) -> CGFloat {
        var currentY = yPosition
        
        currentY = drawSectionTitle("Monthly Report", at: currentY, in: pageRect)
        currentY -= 20
        
        currentY = drawKeyValue("Period:", value: "\(DateFormatter.mediumDate.string(from: startDate)) - \(DateFormatter.mediumDate.string(from: endDate))", at: currentY, in: pageRect)
        
        // Calculate actual monthly report data
        let loansIssuedInPeriod = dataManager.activeLoans.filter { loan in
            guard let issueDate = loan.issueDate else { return false }
            return issueDate >= startDate && issueDate <= endDate
        }
        
        let totalLoansIssued = loansIssuedInPeriod.reduce(0) { $0 + $1.amount }
        
        // Calculate contributions in period
        var totalContributions: Double = 0
        for member in dataManager.members {
            if let payments = member.payments?.allObjects as? [Payment] {
                for payment in payments {
                    if let date = payment.paymentDate, 
                       date >= startDate && date <= endDate && 
                       payment.contributionAmount > 0 {
                        totalContributions += payment.contributionAmount
                    }
                }
            }
        }
        
        // Calculate new members in period
        let newMembers = dataManager.members.filter { member in
            guard let joinDate = member.joinDate else { return false }
            return joinDate >= startDate && joinDate <= endDate
        }
        
        currentY = drawKeyValue("New Members:", value: "\(newMembers.count)", at: currentY, in: pageRect)
        currentY = drawKeyValue("Total Contributions:", value: CurrencyFormatter.shared.format(totalContributions), at: currentY, in: pageRect)
        currentY = drawKeyValue("Loans Issued:", value: "\(loansIssuedInPeriod.count)", at: currentY, in: pageRect)
        currentY = drawKeyValue("Loan Amount Issued:", value: CurrencyFormatter.shared.format(totalLoansIssued), at: currentY, in: pageRect)
        
        return currentY
    }
    
    private func drawAnalyticsReport(dataManager: DataManager, in pageRect: CGRect, at yPosition: CGFloat) -> CGFloat {
        var currentY = yPosition
        
        currentY = drawSectionTitle("Analytics Report", at: currentY, in: pageRect)
        currentY -= 20
        
        // Calculate actual analytics data
        let activeLoans = dataManager.activeLoans
        let averageLoanAmount = activeLoans.isEmpty ? 0 : activeLoans.reduce(0) { $0 + $1.amount } / Double(activeLoans.count)
        
        let completedLoans = dataManager.members.flatMap { member in
            (member.loans?.allObjects as? [Loan] ?? []).filter { $0.loanStatus == .completed }
        }
        let totalLoans = dataManager.members.flatMap { member in
            (member.loans?.allObjects as? [Loan] ?? [])
        }
        let repaymentRate = totalLoans.isEmpty ? 0 : Double(completedLoans.count) / Double(totalLoans.count)
        
        let fundSummary = FundCalculator.shared.generateFundSummary()
        let utilizationPercent = String(format: "%.1f%%", fundSummary.utilizationPercentage * 100)
        
        currentY = drawKeyValue("Average Loan Amount:", value: CurrencyFormatter.shared.format(averageLoanAmount), at: currentY, in: pageRect)
        currentY = drawKeyValue("Repayment Success Rate:", value: String(format: "%.1f%%", repaymentRate * 100), at: currentY, in: pageRect)
        currentY = drawKeyValue("Fund Utilization:", value: utilizationPercent, at: currentY, in: pageRect)
        currentY = drawKeyValue("Active Members:", value: "\(fundSummary.activeMembers)", at: currentY, in: pageRect)
        currentY = drawKeyValue("Active Loans:", value: "\(activeLoans.count)", at: currentY, in: pageRect)
        
        currentY -= 20
        
        // Member distribution
        currentY = drawSectionTitle("Member Distribution", at: currentY, in: pageRect)
        currentY -= 15
        
        let membersByRole = Dictionary(grouping: dataManager.members) { $0.memberRole }
        for (role, members) in membersByRole.sorted(by: { $0.value.count > $1.value.count }) {
            currentY = drawKeyValue("  \(role.displayName):", value: "\(members.count)", at: currentY, in: pageRect)
        }
        
        return currentY
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
}
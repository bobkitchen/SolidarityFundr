//
//  DataImportExport.swift
//  SolidarityFundr
//
//  Created on 7/19/25.
//

import Foundation
import CoreData

class DataImportExport {
    static let shared = DataImportExport()
    
    private let context = PersistenceController.shared.container.viewContext
    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        return formatter
    }()
    
    private init() {}
    
    // MARK: - Export
    
    func exportData() throws -> Data {
        let exportData = ExportData(
            exportDate: Date(),
            version: "1.0",
            fundSettings: try exportFundSettings(),
            members: try exportMembers(),
            loans: try exportLoans(),
            payments: try exportPayments(),
            transactions: try exportTransactions()
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        return try encoder.encode(exportData)
    }
    
    private func exportFundSettings() throws -> ExportFundSettings? {
        let request = FundSettings.fetchRequest()
        guard let settings = try context.fetch(request).first else { return nil }
        
        return ExportFundSettings(
            monthlyContribution: settings.monthlyContribution,
            annualInterestRate: settings.annualInterestRate,
            utilizationWarningThreshold: settings.utilizationWarningThreshold,
            minimumFundBalance: settings.minimumFundBalance,
            bobInitialInvestment: settings.bobInitialInvestment,
            bobRemainingInvestment: settings.bobRemainingInvestment,
            totalInterestApplied: settings.totalInterestApplied,
            lastInterestAppliedDate: settings.lastInterestAppliedDate,
            createdAt: settings.createdAt,
            updatedAt: settings.updatedAt
        )
    }
    
    private func exportMembers() throws -> [ExportMember] {
        let request = Member.fetchRequest()
        let members = try context.fetch(request)
        
        return members.map { member in
            ExportMember(
                memberID: member.memberID,
                name: member.name ?? "",
                role: member.role ?? "",
                status: member.status ?? "active",
                email: member.email,
                phoneNumber: member.phoneNumber,
                joinDate: member.joinDate,
                totalContributions: member.totalContributions,
                suspendedDate: member.suspendedDate,
                cashOutDate: member.cashOutDate,
                cashOutAmount: member.cashOutAmount,
                createdAt: member.createdAt,
                updatedAt: member.updatedAt
            )
        }
    }
    
    private func exportLoans() throws -> [ExportLoan] {
        let request = Loan.fetchRequest()
        let loans = try context.fetch(request)
        
        return loans.map { loan in
            ExportLoan(
                loanID: loan.loanID,
                memberID: loan.member?.memberID,
                amount: loan.amount,
                balance: loan.balance,
                monthlyPayment: loan.monthlyPayment,
                repaymentMonths: Int(loan.repaymentMonths),
                status: loan.status ?? "active",
                issueDate: loan.issueDate,
                dueDate: loan.dueDate,
                completedDate: loan.completedDate,
                notes: loan.notes,
                createdAt: loan.createdAt,
                updatedAt: loan.updatedAt
            )
        }
    }
    
    private func exportPayments() throws -> [ExportPayment] {
        let request = Payment.fetchRequest()
        let payments = try context.fetch(request)
        
        return payments.map { payment in
            ExportPayment(
                paymentID: payment.paymentID,
                memberID: payment.member?.memberID,
                loanID: payment.loan?.loanID,
                amount: payment.amount,
                contributionAmount: payment.contributionAmount,
                loanRepaymentAmount: payment.loanRepaymentAmount,
                type: payment.type ?? "contribution",
                paymentMethod: payment.paymentMethod ?? "cash",
                paymentDate: payment.paymentDate,
                notes: payment.notes,
                createdAt: payment.createdAt,
                updatedAt: payment.updatedAt
            )
        }
    }
    
    private func exportTransactions() throws -> [ExportTransaction] {
        let request = Transaction.fetchRequest()
        let transactions = try context.fetch(request)
        
        return transactions.map { transaction in
            ExportTransaction(
                transactionID: transaction.transactionID,
                memberID: transaction.member?.memberID,
                amount: transaction.amount,
                balance: transaction.balance,
                type: transaction.type ?? "",
                description: transaction.description,
                transactionDate: transaction.transactionDate,
                createdAt: transaction.createdAt,
                updatedAt: transaction.updatedAt
            )
        }
    }
    
    // MARK: - Import
    
    func importData(from data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let importData = try decoder.decode(ExportData.self, from: data)
        
        // Validate version compatibility
        guard importData.version == "1.0" else {
            throw ImportError.incompatibleVersion
        }
        
        // Clear existing data (optional - could merge instead)
        try clearAllData()
        
        // Import in order to maintain relationships
        try importFundSettings(importData.fundSettings)
        let memberMapping = try importMembers(importData.members)
        try importLoans(importData.loans, memberMapping: memberMapping)
        try importPayments(importData.payments, memberMapping: memberMapping)
        try importTransactions(importData.transactions, memberMapping: memberMapping)
        
        try context.save()
    }
    
    private func clearAllData() throws {
        // Delete all entities
        let entities = ["Transaction", "Payment", "Loan", "Member", "FundSettings"]
        
        for entity in entities {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entity)
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            try context.execute(deleteRequest)
        }
    }
    
    private func importFundSettings(_ settings: ExportFundSettings?) throws {
        guard let settings = settings else { return }
        
        let fundSettings = FundSettings(context: context)
        fundSettings.monthlyContribution = settings.monthlyContribution
        fundSettings.annualInterestRate = settings.annualInterestRate
        fundSettings.utilizationWarningThreshold = settings.utilizationWarningThreshold
        fundSettings.minimumFundBalance = settings.minimumFundBalance
        fundSettings.bobInitialInvestment = settings.bobInitialInvestment
        fundSettings.bobRemainingInvestment = settings.bobRemainingInvestment
        fundSettings.totalInterestApplied = settings.totalInterestApplied
        fundSettings.lastInterestAppliedDate = settings.lastInterestAppliedDate
        fundSettings.createdAt = settings.createdAt
        fundSettings.updatedAt = settings.updatedAt
    }
    
    private func importMembers(_ members: [ExportMember]) throws -> [UUID: Member] {
        var memberMapping: [UUID: Member] = [:]
        
        for exportMember in members {
            let member = Member(context: context)
            member.memberID = exportMember.memberID
            member.name = exportMember.name
            member.role = exportMember.role
            member.status = exportMember.status
            member.email = exportMember.email
            member.phoneNumber = exportMember.phoneNumber
            member.joinDate = exportMember.joinDate
            member.totalContributions = exportMember.totalContributions
            member.suspendedDate = exportMember.suspendedDate
            member.cashOutDate = exportMember.cashOutDate
            member.cashOutAmount = exportMember.cashOutAmount
            member.createdAt = exportMember.createdAt
            member.updatedAt = exportMember.updatedAt
            
            if let memberID = exportMember.memberID {
                memberMapping[memberID] = member
            }
        }
        
        return memberMapping
    }
    
    private func importLoans(_ loans: [ExportLoan], memberMapping: [UUID: Member]) throws {
        for exportLoan in loans {
            let loan = Loan(context: context)
            loan.loanID = exportLoan.loanID
            loan.amount = exportLoan.amount
            loan.balance = exportLoan.balance
            loan.monthlyPayment = exportLoan.monthlyPayment
            loan.repaymentMonths = Int16(exportLoan.repaymentMonths)
            loan.status = exportLoan.status
            loan.issueDate = exportLoan.issueDate
            loan.dueDate = exportLoan.dueDate
            loan.completedDate = exportLoan.completedDate
            loan.notes = exportLoan.notes
            loan.createdAt = exportLoan.createdAt
            loan.updatedAt = exportLoan.updatedAt
            
            // Link to member
            if let memberID = exportLoan.memberID,
               let member = memberMapping[memberID] {
                loan.member = member
            }
        }
    }
    
    private func importPayments(_ payments: [ExportPayment], memberMapping: [UUID: Member]) throws {
        // First pass: create all loans to build loan mapping
        let loanRequest = Loan.fetchRequest()
        let allLoans = try context.fetch(loanRequest)
        let loanMapping: [UUID: Loan] = Dictionary(uniqueKeysWithValues: allLoans.compactMap { loan in
            guard let loanID = loan.loanID else { return nil }
            return (loanID, loan)
        })
        
        for exportPayment in payments {
            let payment = Payment(context: context)
            payment.paymentID = exportPayment.paymentID
            payment.amount = exportPayment.amount
            payment.contributionAmount = exportPayment.contributionAmount
            payment.loanRepaymentAmount = exportPayment.loanRepaymentAmount
            payment.type = exportPayment.type
            payment.paymentMethod = exportPayment.paymentMethod
            payment.paymentDate = exportPayment.paymentDate
            payment.notes = exportPayment.notes
            payment.createdAt = exportPayment.createdAt
            payment.updatedAt = exportPayment.updatedAt
            
            // Link to member
            if let memberID = exportPayment.memberID,
               let member = memberMapping[memberID] {
                payment.member = member
            }
            
            // Link to loan
            if let loanID = exportPayment.loanID,
               let loan = loanMapping[loanID] {
                payment.loan = loan
            }
        }
    }
    
    private func importTransactions(_ transactions: [ExportTransaction], memberMapping: [UUID: Member]) throws {
        for exportTransaction in transactions {
            let transaction = Transaction(context: context)
            transaction.transactionID = exportTransaction.transactionID
            transaction.amount = exportTransaction.amount
            transaction.balance = exportTransaction.balance
            transaction.type = exportTransaction.type
            transaction.transactionDescription = exportTransaction.description
            transaction.transactionDate = exportTransaction.transactionDate
            transaction.createdAt = exportTransaction.createdAt
            transaction.updatedAt = exportTransaction.updatedAt
            
            // Link to member
            if let memberID = exportTransaction.memberID,
               let member = memberMapping[memberID] {
                transaction.member = member
            }
        }
    }
}

// MARK: - Export Data Models

struct ExportData: Codable {
    let exportDate: Date
    let version: String
    let fundSettings: ExportFundSettings?
    let members: [ExportMember]
    let loans: [ExportLoan]
    let payments: [ExportPayment]
    let transactions: [ExportTransaction]
}

struct ExportFundSettings: Codable {
    let monthlyContribution: Double
    let annualInterestRate: Double
    let utilizationWarningThreshold: Double
    let minimumFundBalance: Double
    let bobInitialInvestment: Double
    let bobRemainingInvestment: Double
    let totalInterestApplied: Double
    let lastInterestAppliedDate: Date?
    let createdAt: Date?
    let updatedAt: Date?
}

struct ExportMember: Codable {
    let memberID: UUID?
    let name: String
    let role: String
    let status: String
    let email: String?
    let phoneNumber: String?
    let joinDate: Date?
    let totalContributions: Double
    let suspendedDate: Date?
    let cashOutDate: Date?
    let cashOutAmount: Double
    let createdAt: Date?
    let updatedAt: Date?
}

struct ExportLoan: Codable {
    let loanID: UUID?
    let memberID: UUID?
    let amount: Double
    let balance: Double
    let monthlyPayment: Double
    let repaymentMonths: Int
    let status: String
    let issueDate: Date?
    let dueDate: Date?
    let completedDate: Date?
    let notes: String?
    let createdAt: Date?
    let updatedAt: Date?
}

struct ExportPayment: Codable {
    let paymentID: UUID?
    let memberID: UUID?
    let loanID: UUID?
    let amount: Double
    let contributionAmount: Double
    let loanRepaymentAmount: Double
    let type: String
    let paymentMethod: String
    let paymentDate: Date?
    let notes: String?
    let createdAt: Date?
    let updatedAt: Date?
}

struct ExportTransaction: Codable {
    let transactionID: UUID?
    let memberID: UUID?
    let amount: Double
    let balance: Double
    let type: String
    let description: String?
    let transactionDate: Date?
    let createdAt: Date?
    let updatedAt: Date?
}

// MARK: - Errors

enum ImportError: LocalizedError {
    case incompatibleVersion
    case corruptedData
    case missingRequiredData
    
    var errorDescription: String? {
        switch self {
        case .incompatibleVersion:
            return "The import file version is not compatible with this app version"
        case .corruptedData:
            return "The import file appears to be corrupted"
        case .missingRequiredData:
            return "The import file is missing required data"
        }
    }
}
//
//  LoanWindowView.swift
//  SolidarityFundr
//
//  Window wrapper for LoanDetailView that fetches loan by UUID
//

import SwiftUI
import CoreData

struct LoanWindowView: View {
    let loanID: UUID?
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var dataManager: DataManager
    @StateObject private var viewModel = LoanViewModel()

    @State private var loan: Loan?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading loan...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loan = loan {
                LoanDetailView(loan: loan)
                    .environmentObject(viewModel)
                    .environment(\.openMemberWindow, openMemberWindow)
                    .environment(\.openLoanWindow, openLoanWindow)
            } else {
                ContentUnavailableView(
                    "Loan Not Found",
                    systemImage: "creditcard.trianglebadge.exclamationmark",
                    description: Text(errorMessage ?? "The requested loan could not be loaded.")
                )
            }
        }
        .onAppear {
            loadLoan()
        }
        .onChange(of: loanID) { _, newID in
            loadLoan()
        }
    }

    private func loadLoan() {
        guard let loanID = loanID else {
            isLoading = false
            errorMessage = "No loan ID provided"
            return
        }

        isLoading = true

        let request: NSFetchRequest<Loan> = Loan.fetchRequest()
        request.predicate = NSPredicate(format: "loanID == %@", loanID as CVarArg)
        request.fetchLimit = 1

        do {
            let results = try viewContext.fetch(request)
            loan = results.first
            if loan == nil {
                errorMessage = "Loan with ID \(loanID) not found"
            }
        } catch {
            errorMessage = "Failed to load loan: \(error.localizedDescription)"
        }

        isLoading = false
    }

    private func openMemberWindow(memberID: UUID) {
        openWindow(id: "member-detail", value: memberID)
    }

    private func openLoanWindow(loanID: UUID) {
        openWindow(id: "loan-detail", value: loanID)
    }
}

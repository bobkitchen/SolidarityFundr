//
//  MemberWindowView.swift
//  SolidarityFundr
//
//  Window wrapper for MemberDetailView that fetches member by UUID
//

import SwiftUI
import CoreData

struct MemberWindowView: View {
    let memberID: UUID?
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var dataManager: DataManager
    @StateObject private var viewModel = MemberViewModel()

    @State private var member: Member?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading member...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let member = member {
                MemberDetailView(member: member)
                    .environmentObject(viewModel)
                    .environment(\.openMemberWindow, openMemberWindow)
                    .environment(\.openLoanWindow, openLoanWindow)
            } else {
                ContentUnavailableView(
                    "Member Not Found",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text(errorMessage ?? "The requested member could not be loaded.")
                )
            }
        }
        .onAppear {
            loadMember()
        }
        .onChange(of: memberID) { _, newID in
            loadMember()
        }
    }

    private func loadMember() {
        guard let memberID = memberID else {
            isLoading = false
            errorMessage = "No member ID provided"
            return
        }

        isLoading = true

        let request: NSFetchRequest<Member> = Member.fetchRequest()
        request.predicate = NSPredicate(format: "memberID == %@", memberID as CVarArg)
        request.fetchLimit = 1

        do {
            let results = try viewContext.fetch(request)
            member = results.first
            if member == nil {
                errorMessage = "Member with ID \(memberID) not found"
            }
        } catch {
            errorMessage = "Failed to load member: \(error.localizedDescription)"
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

// MARK: - Environment Keys for Window Opening

private struct OpenMemberWindowKey: EnvironmentKey {
    static let defaultValue: (UUID) -> Void = { _ in }
}

private struct OpenLoanWindowKey: EnvironmentKey {
    static let defaultValue: (UUID) -> Void = { _ in }
}

extension EnvironmentValues {
    var openMemberWindow: (UUID) -> Void {
        get { self[OpenMemberWindowKey.self] }
        set { self[OpenMemberWindowKey.self] = newValue }
    }

    var openLoanWindow: (UUID) -> Void {
        get { self[OpenLoanWindowKey.self] }
        set { self[OpenLoanWindowKey.self] = newValue }
    }
}

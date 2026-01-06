import Foundation
import CoreData

// This script would check for mismatches between Loan entities and Transaction ledger
// Run in app context to debug the data integrity issue

print("Data Integrity Check")
print("===================")

// Check 1: All active loans and their balances
// Check 2: All loan disbursement transactions
// Check 3: All loan repayment transactions  
// Compare totals


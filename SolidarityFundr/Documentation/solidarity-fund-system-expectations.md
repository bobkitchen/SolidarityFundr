# Parachichi House Solidarity Fund - System Expectations Document

## 1. System Overview

The Parachichi House Solidarity Fund Management System is a native macOS application designed to manage a staff solidarity fund with complete financial tracking, loan management, and reporting capabilities. The system leverages iCloud for multi-user access and synchronization while maintaining full offline functionality.

## 2. Functional Expectations

### 2.1 Member Management

**Expected Behaviors:**
- System shall maintain a complete record of all fund members
- Each member record shall track: name, role, join date, status, total contributions, and payment history
- System shall calculate total contributions automatically based on payment history
- System shall allow manual suspension/reactivation of members
- Cash-out calculations shall include contributions plus any accrued interest
- System shall prevent deletion of members with active loans

**Data Integrity:**
- Member IDs shall be unique and immutable
- Role changes shall not affect historical loan limits
- Contribution history shall be append-only (no deletion, only corrections via new entries)

### 2.2 Loan Management

**Expected Behaviors:**
- System shall enforce role-based loan limits:
  - Driver/Assistant: KSH 40,000
  - Housekeeper: KSH 19,000
  - Grounds Keeper: KSH 19,000
  - Guards/Part-time: Contributions to date, max KSH 12,000
- Guards must have 3 months of contributions before loan eligibility
- System shall track loan lifecycle: active → completed
- Monthly payments shall include both loan repayment and KSH 2,000 contribution
- System shall calculate next payment due dates automatically

**Warning System:**
- Display warning when fund utilization exceeds 60% (overrideable)
- Display warning when loan would reduce fund below KSH 50,000 (overrideable)
- Warnings shall clearly indicate they can be overridden

### 2.3 Financial Tracking

**Expected Behaviors:**
- Fund balance shall update in real-time with all transactions
- System shall track Bob Kitchen's KSH 100,000 investment separately
- Bob Kitchen can withdraw his investment incrementally
- Interest (13%) shall be applied manually via button click
- Interest shall be calculated on total fund value (held + loaned)
- System shall maintain complete transaction history

**Calculations:**
- Fund Balance = Total Contributions + Bob's Remaining Investment + Applied Interest - Active Loans - Withdrawn Amounts
- Loan Utilization = (Total Active Loans / Fund Balance) × 100
- Member Balance = Contributions + Accrued Interest - Outstanding Loans

### 2.4 Payment Processing

**Expected Behaviors:**
- Two payment types: contribution only, or loan repayment (includes contribution)
- Loan payments automatically allocate KSH 2,000 to contribution
- System shall update loan balances immediately upon payment
- Completed loans shall change status automatically when balance reaches zero
- Payment history shall be editable with automatic recalculation

**Validations:**
- Prevent loan payments less than KSH 2,000
- Prevent overpayment of loans
- Validate payment dates are not in the future

## 3. Non-Functional Expectations

### 3.1 Performance

**Response Times:**
- View loading: < 1 second
- Search operations: < 500ms
- Report generation: < 5 seconds
- Sync operations: Background, non-blocking

**Capacity:**
- Support up to 100 members
- Handle 10,000+ transactions
- Generate reports with 1 year of data
- Sync across 5 devices simultaneously

### 3.2 Reliability

**Availability:**
- 100% availability in offline mode
- Automatic sync recovery on connection
- No data loss during crashes
- Graceful handling of sync conflicts

**Data Integrity:**
- ACID compliance for all transactions
- Automatic validation of financial calculations
- Referential integrity across all relationships
- Audit trail for all modifications

### 3.3 Usability

**User Interface:**
- Native macOS look and feel
- Keyboard shortcuts for common operations
- Contextual help for complex features
- Clear error messages with recovery actions

**Workflows:**
- Record payment in < 30 seconds
- Issue new loan in < 1 minute
- Generate member report in < 10 seconds
- Complete monthly reconciliation in < 10 minutes

### 3.4 Security

**Access Control:**
- Require iCloud authentication
- All users have full access (no roles currently)
- Secure data storage using Core Data encryption
- No sensitive data in logs or debug output

**Data Protection:**
- Encrypted data at rest
- Secure iCloud transmission
- No local caching of sensitive data
- Automatic logout on system sleep

## 4. Integration Expectations

### 4.1 iCloud Sync

**Sync Behavior:**
- Automatic sync when online
- Queue changes when offline
- Merge conflicts using last-write-wins
- Visual indicators for sync status

**Conflict Resolution:**
- Financial transactions: Latest timestamp wins
- Member data: Manual merge option
- Loan status: Require manual review
- Settings: Device-specific

### 4.2 Data Import/Export

**Import Capabilities:**
- JSON import from React prototype
- Validate all imported data
- Map old structure to new schema
- Preserve historical transactions

**Export Capabilities:**
- Full backup to JSON
- Member reports to PDF
- Transaction history to CSV
- Financial summaries to PDF

## 5. Reporting Expectations

### 5.1 Individual Member Reports

**Content:**
- Member details and status
- Contribution history with dates
- Current contribution balance
- Active loan details with payment schedule
- Net position (contributions - loans)
- Accrued but unpaid interest

**Format:**
- Professional PDF layout
- Parachichi House branding
- Clear tabular data
- Summary section at top
- Generated date/time stamp

### 5.2 Fund Overview Reports

**Content:**
- Total fund balance
- Bob Kitchen's investment status
- Active loans summary
- Member contribution totals
- Utilization metrics
- Monthly transaction summary

## 6. Error Handling Expectations

### 6.1 User Errors
- Clear validation messages before submission
- Opportunity to correct without data loss
- Confirmation dialogs for destructive actions
- Undo capability where appropriate

### 6.2 System Errors
- Graceful degradation for sync failures
- Automatic recovery attempts
- Error logging for debugging
- User-friendly error messages

### 6.3 Data Errors
- Validation on all inputs
- Range checking for financial amounts
- Date validation for logical consistency
- Referential integrity enforcement

## 7. Future Compatibility

### 7.1 iOS App Preparation
- Data model compatible with iOS Core Data
- Business logic in reusable modules
- CloudKit schema supports iOS access
- Report formats mobile-friendly

### 7.2 Feature Expansion
- Database schema supports new fields
- Settings system extensible
- Report engine configurable
- UI components modular

## 8. Acceptance Criteria

The system shall be considered complete when:
1. All member CRUD operations function correctly
2. Loan issuance and repayment tracking is accurate
3. Financial calculations match manual verification
4. iCloud sync works across multiple devices
5. PDF reports generate correctly
6. Data import from React prototype succeeds
7. All business rules are enforced (with overrides)
8. System handles offline mode gracefully
9. No critical bugs in 5 days of testing
10. User documentation is complete
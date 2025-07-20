# Parachichi House Solidarity Fund - Project Brief

## Executive Summary
The Parachichi House Solidarity Fund macOS application is a comprehensive financial management system designed to manage a staff solidarity fund. The fund provides interest-free emergency loans to household staff while encouraging regular savings through monthly contributions. The application will replace the existing React prototype with a native macOS experience that leverages iCloud for multi-user access and data synchronization.

## Project Overview

### Purpose
Create a native macOS application to manage all aspects of the Staff Solidarity Fund, including:
- Member management and contributions tracking
- Loan issuance and repayment monitoring
- Fund balance management
- Financial reporting and analytics
- Interest calculations and distributions
- Bob Kitchen's initial investment tracking

### Key Business Rules
- Monthly contribution: KSH 2,000 per member
- Loan limits based on staff categories (KSH 12,000 - 40,000)
- 60% fund utilization warning threshold
- Minimum fund balance warning at KSH 50,000
- 13% annual interest on total fund value (applied manually)
- Loan repayment periods: 3 or 4 months

### Target Users
- Primary: Bob Kitchen (Fund Custodian)
- Secondary: Other authorized administrators with full access via iCloud

## Technical Requirements

### Platform
- **Primary**: macOS 15.5+ (native SwiftUI application)
- **Future**: iOS 18.5+ companion app (not in current scope)

### Data Management
- **Storage**: Core Data with iCloud sync (CloudKit)
- **Multi-user**: Shared iCloud container for authorized users
- **Offline**: Full functionality with automatic sync when connected
- **Export**: JSON backup/restore functionality
- **Reports**: PDF generation for monthly statements

### Core Features
1. **Member Management**
   - Add/edit/remove members
   - Track contributions and payment history
   - Suspend/reactivate members manually
   - Cash-out calculations

2. **Loan Management**
   - Issue loans with override capabilities for warnings
   - Track repayments and remaining balances
   - Payment history with editing capabilities
   - Automatic next payment date calculations

3. **Financial Tracking**
   - Real-time fund balance
   - Bob Kitchen's investment tracking with withdrawal capability
   - Manual interest application (13% annually)
   - Contribution and loan analytics

4. **Reporting**
   - Individual member financial summaries (PDF)
   - Fund overview reports
   - Payment history reports
   - Monthly statements for distribution

### User Experience
- Clean, intuitive macOS-native interface
- Dashboard with key metrics
- Warning dialogs for policy violations (overrideable)
- Efficient data entry workflows
- Comprehensive search and filtering

## Project Constraints

### Business Constraints
- Must enforce fund charter rules (with override options)
- Must maintain accurate financial records
- Must support the existing five staff categories
- Must track Bob Kitchen's KSH 100,000 investment separately

### Technical Constraints
- macOS 15.5 minimum deployment target
- iCloud account required for sync
- Must handle offline scenarios gracefully
- Must support data migration from React prototype

## Success Criteria
1. Accurate tracking of all financial transactions
2. Reliable iCloud sync across multiple devices
3. Generation of clear, professional PDF reports
4. Improved efficiency over React prototype
5. Data integrity and security
6. Intuitive user interface requiring minimal training

## Risks and Mitigation
- **Data Loss**: Implement robust backup/restore functionality
- **Sync Conflicts**: Design clear conflict resolution UI
- **Calculation Errors**: Comprehensive unit testing for financial logic
- **User Errors**: Implement edit/undo capabilities where appropriate

## Future Enhancements (Out of Scope)
- iOS companion app
- Member self-service portal
- Automated payment reminders
- Authentication and role-based access
- Integration with banking systems
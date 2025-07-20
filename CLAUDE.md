# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

SolidarityFundr is a native Apple platform application for managing the Parachichi House Solidarity Fund. It's a financial management system that provides interest-free emergency loans to household staff while encouraging regular savings through monthly contributions. The application is built with SwiftUI and Core Data, targeting macOS, iOS, and visionOS platforms.

## Development Commands

### Building and Running
```bash
# Build for macOS
xcodebuild -project SolidarityFundr.xcodeproj -scheme SolidarityFundr -configuration Debug -derivedDataPath build

# Build for iOS Simulator
xcodebuild -project SolidarityFundr.xcodeproj -scheme SolidarityFundr -destination 'platform=iOS Simulator,name=iPhone 15' -configuration Debug

# Clean build folder
xcodebuild -project SolidarityFundr.xcodeproj -scheme SolidarityFundr clean

# Run the app (must use Xcode IDE)
# Open project in Xcode: open SolidarityFundr.xcodeproj
```

### Testing
```bash
# No test targets currently exist. When added, use:
# xcodebuild test -project SolidarityFundr.xcodeproj -scheme SolidarityFundr -destination 'platform=macOS'
```

## Architecture Overview

### Project Structure
- **SolidarityFundr.xcodeproj/**: Xcode project configuration
- **SolidarityFundr/**: Main application source
  - **ContentView.swift**: Main view (currently template code)
  - **SolidarityFundrApp.swift**: App entry point
  - **Persistence.swift**: Core Data stack with CloudKit integration
  - **SolidarityFundr.xcdatamodeld/**: Core Data model definitions
  - **Documentation/**: Comprehensive project documentation

### Technology Stack
- **Language**: Swift 5.0
- **UI Framework**: SwiftUI
- **Data Persistence**: Core Data with CloudKit (NSPersistentCloudKitContainer)
- **Platforms**: macOS 15.5+, iOS 18.5+, visionOS 2.5+
- **iCloud**: Enabled for cross-device synchronization

### Key Architectural Decisions
1. **Core Data + CloudKit**: Provides offline functionality with automatic cloud sync
2. **Multi-platform**: Single codebase targets macOS (primary), iOS, and visionOS
3. **SwiftUI**: Modern declarative UI framework for all platforms
4. **MVVM Pattern**: Recommended for SwiftUI applications (to be implemented)

## Core Business Logic

### Member Management
- Monthly contribution: KSH 2,000 per member
- Role-based loan limits:
  - Driver/Assistant: KSH 40,000
  - Housekeeper: KSH 19,000
  - Grounds Keeper: KSH 19,000
  - Guards/Part-time: Contributions to date, max KSH 12,000
- Guards require 3 months of contributions before loan eligibility

### Loan System
- Interest-free loans with 3 or 4 month repayment periods
- Monthly payments include loan repayment + KSH 2,000 contribution
- Automatic completion when balance reaches zero
- Cannot delete members with active loans

### Fund Calculations
```
Fund Balance = Total Contributions + Bob's Remaining Investment + Applied Interest - Active Loans - Withdrawn Amounts
Loan Utilization = (Total Active Loans / Fund Balance) × 100
```

### Business Rules
- 60% fund utilization warning (overrideable)
- Minimum fund balance warning at KSH 50,000 (overrideable)
- 13% annual interest on total fund value (applied manually)
- Bob Kitchen's KSH 100,000 initial investment tracked separately

## Implementation Roadmap

The project follows a 7-week development plan detailed in `Documentation/solidarity-fund-task-list.md`:

1. **Week 1**: Project setup, Core Data schema, iCloud configuration
2. **Week 2**: Data models, business logic, calculation engine
3. **Week 3**: Core UI views (Dashboard, Members, Loans)
4. **Week 4**: Advanced features (Payments, Reports, Settings)
5. **Week 5**: Data management, import/export, sync implementation
6. **Week 6**: Testing, performance optimization, UI polish
7. **Week 7**: Deployment preparation and documentation

## Important Implementation Notes

### Core Data Schema
When implementing Core Data entities, ensure:
- All entities are marked for CloudKit sync
- Proper relationships between Member, Loan, Payment, and Transaction entities
- Indexes on frequently queried fields (memberID, loanStatus, etc.)

### iCloud Integration
- Use NSPersistentCloudKitContainer (already configured in Persistence.swift)
- Handle sync conflicts appropriately
- Implement proper error handling for network issues
- Test multi-device scenarios thoroughly

### Performance Requirements
- View loading: < 1 second
- Search operations: < 500ms
- Report generation: < 5 seconds
- Support up to 100 members and 10,000+ transactions

### Data Import
Must support importing from existing React prototype:
- JSON format for member and transaction data
- Validate data integrity during import
- Provide rollback capability if import fails

### Report Generation
- PDF generation for member statements and fund reports
- Use native macOS/iOS PDF APIs
- Include proper formatting and branding

## Development Best Practices

1. **SwiftUI Best Practices**:
   - Use @StateObject for view models
   - Leverage @EnvironmentObject for shared state
   - Keep views small and focused
   - Use computed properties for derived values

2. **Core Data Best Practices**:
   - Use background contexts for heavy operations
   - Batch operations when possible
   - Implement proper error handling
   - Test migrations thoroughly

3. **Code Organization**:
   - Group related files in folders (Models, Views, ViewModels, Services)
   - Use Swift's access control appropriately
   - Follow Swift naming conventions
   - Keep business logic separate from UI code

4. **Testing Strategy**:
   - Unit tests for business logic and calculations
   - Integration tests for Core Data operations
   - UI tests for critical user flows
   - Test iCloud sync scenarios

## Current Project Status

### Implemented Features ✅
1. **Core Data Schema & Models**: All entities created (Member, Loan, Payment, Transaction, FundSettings, InterestApplication)
2. **Business Logic**: Complete implementation of fund calculations, loan management, member management
3. **iCloud Integration**: CloudKit sync fully configured and working
4. **Authentication**: Biometric authentication and app locking implemented
5. **All Core Views**: Dashboard, Members, Loans, Payments, Reports, Settings
6. **Data Import/Export**: JSON and CSV support
7. **PDF Report Generation**: Member statements and fund reports

### Liquid Glass UI Implementation (macOS Tahoe 26)

#### Completed Work ✅
1. **Initial Liquid Glass Components**:
   - Created `LiquidGlassEffects.swift` with performantGlass modifiers
   - Created `DesignSystem.swift` with centralized spacing, materials, and typography
   - Created `FloatingSidebar.swift` matching Transcriptly implementation
   - Created `LiquidGlassDashboard.swift` with metric cards and charts
   - Implemented proper glass materials (ultraThinMaterial, regularMaterial)
   - Added hover overlays and adaptive shadows

2. **Window Configuration**:
   - Updated `SolidarityFundrApp.swift`:
     - Changed from `.windowStyle(.titleBar)` to `.windowStyle(.hiddenTitleBar)`
     - Added `.windowResizability(.contentSize)`
     - Added `@NSApplicationDelegateAdaptor(WindowConfigurator.self)`
     - Added `.ignoresSafeArea(.all, edges: .top)`

3. **NavigationStack Removal**:
   - Removed NavigationStack from all detail views to prevent double title bars
   - Added integrated toolbar controls within each view's header

4. **Window Configurator**:
   - Created `WindowConfigurator.swift` to set up edge-to-edge content:
     ```swift
     window.titlebarAppearsTransparent = true
     window.titleVisibility = .hidden
     window.styleMask.insert(.fullSizeContentView)
     ```

#### Current Issues 🚨

**Traffic Light Button Positioning**
- **Problem**: Traffic light buttons (close, minimize, maximize) are not positioned correctly
- **Current**: Buttons appear pushed down as if there's still a title bar
- **Expected**: Buttons should be at the very top edge of the window, overlaying content
- **Reference**: Notes.app and Reminders.app show proper positioning

**Visual Symptoms**:
- Extra space above traffic lights
- Inconsistent title bar heights between views
- Window chrome not fully integrated

#### Technical Details

**Key Modified Files**:
1. `/SolidarityFundr/SolidarityFundrApp.swift` - Main app configuration
2. `/SolidarityFundr/WindowConfigurator.swift` - NSWindow customization
3. `/SolidarityFundr/LiquidGlass/Components/FloatingSidebar.swift` - Sidebar implementation
4. `/SolidarityFundr/LiquidGlass/Components/LiquidGlassDashboard.swift` - Dashboard view
5. `/SolidarityFundr/LiquidGlass/Effects/LiquidGlassEffects.swift` - Glass effect modifiers
6. `/SolidarityFundr/LiquidGlass/DesignSystem.swift` - Design constants
7. All view files in `/SolidarityFundr/Views/` - Removed NavigationStack, added headers

**Design System Constants**:
- Sidebar width: 220px
- Sidebar padding: 12px
- Corner radius: Nav items 6px, Cards 12px, Panels 20px
- Top padding for views: 16px (reduced from 28px)

### Next Steps to Fix Traffic Light Positioning

The main issue is that the traffic lights are not properly positioned at the window edge. Research indicates this may require:

1. **Different NSWindow configuration approach**
2. **Custom NSWindowDelegate implementation**
3. **Possible NSToolbar integration**
4. **Study of modern macOS app implementations (Notes.app, Reminders.app)**

### Build & Test Instructions
```bash
# Clean build
xcodebuild -scheme SolidarityFundr -configuration Debug clean build

# Run the app
open /Users/bobkitchen/Library/Developer/Xcode/DerivedData/SolidarityFundr-*/Build/Products/Debug/SolidarityFundr.app
```

**Testing Focus**:
- Compare window chrome with Notes.app
- Check traffic light positioning
- Verify edge-to-edge content layout
- Test all views for consistency
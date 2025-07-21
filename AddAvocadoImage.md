# Adding the Avocado Logo to SolidarityFundr

## Steps to Add Your Avocado Image

1. **Save your avocado image** with one of these filenames:
   - `avocado.png` (for 1x resolution)
   - `avocado@2x.png` (for 2x resolution - recommended for Retina displays)
   - `avocado@3x.png` (for 3x resolution - optional)

2. **Add the image(s) to the project**:
   - Open the project in Xcode
   - Navigate to: `SolidarityFundr/Assets.xcassets/AvocadoLogo.imageset/`
   - Drag and drop your avocado image file(s) into this folder
   - Alternatively, you can drag them directly into Xcode's Asset Catalog

3. **Build and run** the project

## What Was Changed

The blue building icon has been replaced with your avocado logo in these locations:

1. **Sidebar Header** - The main navigation sidebar
2. **Authentication Screen** - The login screen that appears when the app starts
3. **All Other Sidebars** - Any other sidebar components in the app

## Image Specifications

- **Recommended size**: 120x120 pixels for the @2x version (will display at 60x60 points)
- **Format**: PNG with transparent background
- **The image will automatically scale** to fit the designated spaces (40x40 for sidebar, 80x80 for authentication)

## Note

The Asset Catalog structure has already been created. You just need to add your avocado image file(s) to complete the setup.
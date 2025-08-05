# Cloudflare R2 Setup Guide

This guide will walk you through setting up Cloudflare R2 for hosting PDF statements.

## Prerequisites

- A Cloudflare account
- Access to Cloudflare R2 (may require enabling R2 in your account)

## Step 1: Create an R2 Bucket

1. Log in to the [Cloudflare Dashboard](https://dash.cloudflare.com)
2. Navigate to **R2** in the sidebar
3. Click **Create bucket**
4. Enter bucket name: `solidarity-fund-statements`
5. Select your preferred location (or leave as automatic)
6. Click **Create bucket**

## Step 2: Configure Public Access (Optional but Recommended)

To allow public access to PDFs without authentication:

1. Go to your bucket settings
2. Navigate to **Settings** → **Public Access**
3. Enable public access
4. Configure a custom domain (optional):
   - Add a custom domain like `statements.solidarityfund.com`
   - This will be your public URL for accessing PDFs

## Step 3: Create API Credentials

1. In the R2 dashboard, go to **Manage R2 API tokens**
2. Click **Create API token**
3. Configure the token:
   - **Name**: SolidarityFundr
   - **Permissions**: Object Read & Write
   - **Bucket**: Select `solidarity-fund-statements`
   - **TTL**: Leave as default (forever)
4. Click **Create API Token**
5. Save the following credentials:
   - **Access Key ID**: (shown once)
   - **Secret Access Key**: (shown once)
   - **Account ID**: (visible in your Cloudflare dashboard URL)

## Step 4: Configure in SolidarityFundr

1. Open SolidarityFundr app
2. Go to **Settings** → **SMS & Notifications** tab
3. Scroll to **PDF Hosting Configuration**
4. Enter your credentials:
   - **Account ID**: Your Cloudflare account ID
   - **Access Key ID**: From Step 3
   - **Secret Access Key**: From Step 3
   - **Bucket Name**: `solidarity-fund-statements`
   - **Custom Domain**: Your public URL (e.g., `https://statements.solidarityfund.com`)
5. Click **Save** for each field

## Step 5: Test the Configuration

1. Send a test SMS to verify PDF upload works
2. Check the Cloudflare R2 dashboard to confirm PDFs are being uploaded
3. Try accessing a PDF URL to ensure public access works

## Bucket Structure

PDFs will be organized in the following structure:
```
statements/
├── 2025/
│   ├── 01/
│   │   ├── John-Doe-statement-2025-01-25.pdf
│   │   └── Jane-Smith-statement-2025-01-25.pdf
│   └── 02/
│       └── ...
└── 2024/
    └── ...
```

## Security Considerations

- API credentials are stored securely in the macOS Keychain
- PDFs contain sensitive financial information
- Consider your privacy requirements when enabling public access
- URLs are shortened to obscure the full path

## Troubleshooting

### "Missing credentials" error
- Ensure all R2 fields are filled in Settings
- Try re-entering and saving credentials

### "Upload failed" error
- Verify bucket name matches exactly
- Check API token permissions include write access
- Ensure bucket exists and is accessible

### PDFs not accessible
- Verify public access is enabled on the bucket
- Check custom domain configuration
- Test with the direct R2 URL first

## Cost Estimation

Cloudflare R2 pricing (as of 2025):
- **Storage**: $0.015 per GB per month
- **Operations**: $0.36 per million requests
- **Bandwidth**: Free (no egress fees)

For 50 members with monthly statements:
- Storage: ~50MB/month = ~$0.001/month
- Operations: ~600 requests/month = ~$0.0002/month
- Total: Less than $0.01/month
#!/bin/bash

# Script to seed badge definitions to Firestore
# This script reads BadgeDefinitions.json and uploads them to Firestore

echo "🏅 Badge Seeding Script"
echo "======================="
echo ""
echo "This script will upload badge definitions to Firestore."
echo "Make sure you have:"
echo "  1. Firebase CLI installed (npm install -g firebase-tools)"
echo "  2. Logged in to Firebase (firebase login)"
echo "  3. Selected the correct project (firebase use <project-id>)"
echo ""
read -p "Press Enter to continue or Ctrl+C to cancel..."

# Check if firebase CLI is installed
if ! command -v firebase &> /dev/null; then
    echo "❌ Firebase CLI not found. Please install it first:"
    echo "   npm install -g firebase-tools"
    exit 1
fi

# Get the project root directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
BADGE_FILE="$PROJECT_ROOT/TTB/Configuration/BadgeDefinitions.json"

# Check if badge definitions file exists
if [ ! -f "$BADGE_FILE" ]; then
    echo "❌ Badge definitions file not found at: $BADGE_FILE"
    exit 1
fi

echo "📄 Reading badge definitions from: $BADGE_FILE"
echo ""

# Create a temporary JavaScript file to upload badges
TEMP_SCRIPT=$(mktemp)
cat > "$TEMP_SCRIPT" << 'EOF'
const admin = require('firebase-admin');
const fs = require('fs');

// Initialize Firebase Admin
admin.initializeApp();
const db = admin.firestore();

// Read badge definitions
const badgeFile = process.argv[2];
const badges = JSON.parse(fs.readFileSync(badgeFile, 'utf8'));

async function seedBadges() {
  console.log(`📤 Uploading ${badges.length} badge definitions...`);
  
  const batch = db.batch();
  let count = 0;
  
  for (const badge of badges) {
    const { id, ...badgeData } = badge;
    const docRef = db.collection('badges').doc(id);
    batch.set(docRef, badgeData, { merge: true });
    count++;
    console.log(`   ✓ ${badge.title} (${badge.type})`);
  }
  
  await batch.commit();
  console.log('');
  console.log(`✅ Successfully uploaded ${count} badges!`);
  process.exit(0);
}

seedBadges().catch(error => {
  console.error('❌ Error seeding badges:', error);
  process.exit(1);
});
EOF

# Run the script
echo "🚀 Starting upload..."
echo ""
firebase functions:shell < "$TEMP_SCRIPT" -- "$BADGE_FILE"

# Clean up
rm "$TEMP_SCRIPT"

echo ""
echo "✨ Badge seeding complete!"


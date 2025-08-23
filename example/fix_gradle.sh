#!/bin/bash

echo "🔧 Fixing Gradle wrapper issue..."

# Remove corrupted Gradle caches
rm -rf ~/.gradle/caches/
rm -rf ~/.gradle/wrapper/

# Clean local project
rm -rf android/.gradle/
rm -rf android/build/
rm -rf android/app/build/

# Download correct Gradle wrapper jar
echo "📥 Downloading fresh Gradle wrapper..."
curl -L -o android/gradle/wrapper/gradle-wrapper.jar \
  https://github.com/gradle/gradle/raw/v8.6.0/gradle/wrapper/gradle-wrapper.jar

# Make gradlew executable
chmod +x android/gradlew

echo "✅ Gradle wrapper fixed! Try running 'flutter run' now."
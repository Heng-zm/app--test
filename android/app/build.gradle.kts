plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    // 1. Corrected the spelling typo here and in applicationId
    namespace = "com.example.bluetoothchat"
    
    // Use the latest SDK to support Android 14 (API 34) features
    compileSdk = 34 
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // 2. Upgraded to Java 17 for better plugin compatibility
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.example.bluetoothchat"
        
        // 3. Bluetooth hardware access requires at least API 21
        minSdk = 21 
        targetSdk = 34
        
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // 4. Recommended: Enable shrinking and obfuscation for security
            // If Bluetooth fails in release mode, you will need to add 
            // rules to 'proguard-rules.pro'
            minifyEnabled = false 
            shrinkResources = false
            
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
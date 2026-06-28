plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.redcloud.vpn.redcloud_android"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.redcloud.vpn.redcloud_android"
        
        // تنظیم حداقل نسخه اندروید روی نسخه 21 (اندروید 5)
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // بهینه‌سازی و تفکیک فایل‌های خروجی (APK Splits) برای معماری‌های مختلف پردازنده
    splits {
        abi {
            isEnable = true
            reset()
            include("x86_64", "armeabi-v7a", "arm64-v8a")
            isUniversalApk = true
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            
            // اعمال فیلترهای معماری پردازنده‌ها
            ndk {
                abiFilters.addAll(setOf("x86_64", "armeabi-v7a", "arm64-v8a"))
            }
        }
    }

    // تنظیم نحوه بسته‌بندی کتابخانه‌های بومی هسته Go متناسب با نسخه‌های جدید اندروید و گریدل
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}


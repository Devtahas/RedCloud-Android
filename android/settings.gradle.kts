pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
        flutterSdkPath
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        // ۱. ابتدا مخازن رسمی جهت اتصال مستقیم و سریع سرور گیت‌هاب اکشنز
        google()
        mavenCentral()
        gradlePluginPortal()

        // ۲. مخازن آیینه علی‌بابا به عنوان پشتیبان (Fallback) برای دور زدن تحریم‌ها در ویندوز شما
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.9.1" apply false
    id("org.jetbrains.kotlin.android") version "1.9.24" apply false
}

// هدایت تمام دانلودهای کتابخانه‌ای اندروید به آیینه‌های بدون فیلتر علی‌بابا با حفظ دسترسی به کتابخانه‌های بومی پروژه
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_PROJECT) // تغییر به PREFER_PROJECT جهت شناسایی فایل بومی libv2ray
    repositories {
        // ۱. ابتدا مخازن رسمی جهت اتصال مستقیم و سریع سرور گیت‌هاب اکشنز
        google()
        mavenCentral()

        // ۲. مخازن آیینه علی‌بابا به عنوان پشتیبان (Fallback) برای دور زدن تحریم‌ها در ویندوز شما
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        maven { url = uri("https://maven.aliyun.com/repository/jcenter") }
    }
}

include(":app")
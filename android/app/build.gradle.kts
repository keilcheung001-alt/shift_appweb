import com.android.build.gradle.internal.dsl.BaseAppModuleExtension
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    // 強制讀取 google-services.json，確保 Firebase 能識別你的 App
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.shift_app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.example.shift_app"
        // 🔥 改：由 flutter.minSdkVersion 改為固定 23
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // 🔥 加：啟用 MultiDex（Firebase 方法數超過 65K 必須）
        multiDexEnabled = true
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    add("coreLibraryDesugaring", "com.android.tools:desugar_jdk_libs:2.1.4")
    // 🔥 改：Firebase BoM 由 32.7.0 改為 33.7.0
    implementation(platform("com.google.firebase:firebase-bom:33.7.0"))
    // 🔥 加：Firestore 依賴（你之前漏咗）
    implementation("com.google.firebase:firebase-firestore")
    // 🔥 加：Analytics（你原本有）
    implementation("com.google.firebase:firebase-analytics")
    // 🔥 加：MultiDex 依賴
    implementation("androidx.multidex:multidex:2.0.1")
}

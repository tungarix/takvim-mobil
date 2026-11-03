plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.aktenak.takvim"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    // Uygulamanın kendi yerel kodu yok; .so dosyaları Flutter motorunundur ve zaten hazır gelir.
    // CI'da (ve NDK'lı her makinede) semboller NDK'nın llvm-strip'iyle soyulur: APK ~20-60 MB olur.
    // Soyma NDK ister; NDK'sı olmayan yerel geliştirme makinesi TAKVIM_YEREL_NDKSIZ=1 ile soymayı
    // atlar (APK ~170 MB olur, yalnız yerel deneme için; yayın APK'sı hep CI'dan çıkar).
    if (System.getenv("TAKVIM_YEREL_NDKSIZ") == "1") {
        packaging {
            jniLibs {
                keepDebugSymbols += setOf("**/*.so")
            }
        }
    }

    compileOptions {
        // flutter_local_notifications zamanlı bildirimler için java.time desugaring ister.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.aktenak.takvim"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Sürüm imzası CI'da (release.yml) ortam değişkenlerinden gelir; anahtar depoda yok.
    // Değişkenler yoksa (yerel geliştirme) debug anahtarı kullanılır: o APK yalnız yerel
    // deneme içindir, yayımlanan APK'lar hep aynı sürüm anahtarıyla imzalanır ve birbirinin
    // üstüne kurulur.
    val surumAnahtari = System.getenv("TAKVIM_KEYSTORE")
    signingConfigs {
        if (surumAnahtari != null) {
            create("surum") {
                storeFile = file(surumAnahtari)
                storePassword = System.getenv("TAKVIM_KEYSTORE_PASSWORD")
                keyAlias = "takvim"
                keyPassword = System.getenv("TAKVIM_KEYSTORE_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(
                if (surumAnahtari != null) "surum" else "debug"
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}

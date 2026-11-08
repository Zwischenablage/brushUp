plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "de.toni.zahnputz"
    compileSdk = 34

    defaultConfig {
        applicationId = "de.toni.zahnputz"
        // Echo Show / Fire OS devices run older Android versions -> keep minSdk low.
        minSdk = 22
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            // Signed with the debug key so the APK can be sideloaded right away.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    androidResources {
        noCompress += "mp3"
    }
}

android.testOptions.unitTests.isIncludeAndroidResources = true

dependencies {
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.14.1")
}
dependencies {
    testImplementation("androidx.test:core:1.6.1")
}
// Robolectric's own downloader gets rate-limited on some networks, so let Gradle fetch
// the Android framework jar and run Robolectric offline.
val robolectricRuntime: Configuration by configurations.creating
dependencies {
    robolectricRuntime("org.robolectric:android-all-instrumented:14-robolectric-10818077-i7")
    robolectricRuntime("org.robolectric:android-all-instrumented:15-robolectric-12650502-i7")
}
val robolectricJars = tasks.register<Copy>("robolectricJars") {
    from(robolectricRuntime)
    into(layout.buildDirectory.dir("robolectric-jars"))
}
tasks.withType<Test>().configureEach {
    dependsOn(robolectricJars)
    systemProperty("robolectric.offline", "true")
    systemProperty("robolectric.dependency.dir", layout.buildDirectory.dir("robolectric-jars").get().asFile.absolutePath)
}

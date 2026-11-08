pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        // Google's mirror of Maven Central, only for Robolectric's large framework jar
        // (the main host often rate-limits it).
        exclusiveContent {
            forRepository { maven("https://maven-central.storage-download.googleapis.com/maven2") }
            filter { includeModule("org.robolectric", "android-all-instrumented") }
        }
        google()
        mavenCentral()
    }
}
rootProject.name = "ToniZahnputz"
include(":app")

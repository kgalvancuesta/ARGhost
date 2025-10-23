pluginManagement {
    repositories {
        gradlePluginPortal()
        google()
        mavenCentral()
    }
    plugins {
        id("org.jetbrains.kotlin.multiplatform") version "2.2.20"
    }
}

dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "ARGhost"
include("androiddemo", "iosdemo")
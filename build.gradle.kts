buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:2.2.20")
    }
}

plugins {
    alias(libs.plugins.androidLibrary).apply(false)
    alias(libs.plugins.kotlinMultiplatform).apply(false)
    alias(libs.plugins.androidApplication).apply(false)
    alias(libs.plugins.kotlinAndroid).apply(false)
    alias(libs.plugins.compose.compiler).apply(false)
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}
package com.example.androiddemo

import android.app.Application

class App : Application() {
    override fun onCreate() {
        super.onCreate()
        com.example.tonguedetector.App.context = this
    }
}

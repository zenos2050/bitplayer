package com.solus.bitplayer

import com.ryanheise.audioservice.AudioServiceActivity

// AudioServiceActivity keeps the Flutter engine alive for background playback
// and lock-screen / notification controls.
class MainActivity : AudioServiceActivity()

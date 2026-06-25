package com.ytmusic.yt_music

import com.ryanheise.audioservice.AudioServiceActivity

// Extends AudioServiceActivity (not FlutterActivity) so audio_service can host
// background playback and the media notification correctly.
class MainActivity : AudioServiceActivity()

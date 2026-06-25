import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/playlist.dart';
import '../models/track.dart';

/// Owns the user's local library — liked songs, user playlists, and a small
/// recently-played history (used to seed Home recommendations). Everything is
/// persisted to [SharedPreferences] as JSON and survives restarts.
///
/// Mirrors the lazy-init shape of PlayerController: state starts empty and is
/// hydrated by [_load]; every mutation re-persists and notifies listeners.
class LibraryController extends ChangeNotifier {
  LibraryController() {
    _load();
  }

  static const _kLiked = 'lib.liked';
  static const _kPlaylists = 'lib.playlists';
  static const _kRecent = 'lib.recent';
  static const _kUserId = 'lib.userId';
  static const _kRecKey = 'lib.recKey';
  static const _kRecData = 'lib.recData';
  static const _recentCap = 25;
  static const exportVersion = 1;

  SharedPreferences? _prefs;
  bool _loaded = false;

  List<Track> _liked = [];
  List<Playlist> _playlists = [];
  List<Track> _recent = [];
  String _userId = '';
  String? _recKey;
  String? _recData;

  bool get isLoaded => _loaded;
  List<Track> get likedSongs => List.unmodifiable(_liked);
  List<Playlist> get playlists => List.unmodifiable(_playlists);
  List<Track> get recentlyPlayed => List.unmodifiable(_recent);

  /// A stable per-install user token, generated once and persisted. Used to
  /// namespace cached data so it survives restarts.
  String get userId => _userId;

  Future<void> _load() async {
    _prefs = await SharedPreferences.getInstance();
    _liked = _decodeTracks(_prefs!.getString(_kLiked));
    _recent = _decodeTracks(_prefs!.getString(_kRecent));
    _playlists = _decodePlaylists(_prefs!.getString(_kPlaylists));
    _userId = _prefs!.getString(_kUserId) ?? '';
    if (_userId.isEmpty) {
      _userId = _generateUserId();
      await _prefs!.setString(_kUserId, _userId);
    }
    _recKey = _prefs!.getString(_kRecKey);
    _recData = _prefs!.getString(_kRecData);
    _loaded = true;
    notifyListeners();
  }

  // --- Recommendation cache (keeps Home stable across restarts) --------
  /// Returns the cached recommendation JSON for [key], or null if the cache is
  /// for a different key (i.e. the user's seeds changed).
  String? recCacheFor(String key) => _recKey == key ? _recData : null;

  void saveRecCache(String key, String data) {
    _recKey = key;
    _recData = data;
    _prefs?.setString(_kRecKey, key);
    _prefs?.setString(_kRecData, data);
  }

  void clearRecCache() {
    _recKey = null;
    _recData = null;
    _prefs?.remove(_kRecKey);
    _prefs?.remove(_kRecData);
  }

  static String _generateUserId() {
    final r = Random();
    const hex = '0123456789abcdef';
    return List.generate(32, (_) => hex[r.nextInt(16)]).join();
  }

  // --- Liked songs -----------------------------------------------------
  bool isLiked(Track t) => _liked.any((x) => _sameTrack(x, t));

  void toggleLike(Track t) {
    if (isLiked(t)) {
      _liked.removeWhere((x) => _sameTrack(x, t));
    } else {
      _liked.insert(0, t);
    }
    _persistLiked();
    notifyListeners();
  }

  // --- Playlists -------------------------------------------------------
  Playlist createPlaylist(String name) {
    final pl = Playlist(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name.trim().isEmpty ? 'Untitled' : name.trim(),
      tracks: const [],
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    _playlists.insert(0, pl);
    _persistPlaylists();
    notifyListeners();
    return pl;
  }

  void deletePlaylist(String id) {
    _playlists.removeWhere((p) => p.id == id);
    _persistPlaylists();
    notifyListeners();
  }

  void renamePlaylist(String id, String name) {
    _updatePlaylist(id, (p) => p.copyWith(name: name.trim()));
  }

  /// Returns false if the track is already in the playlist (no duplicate add).
  bool addToPlaylist(String id, Track t) {
    var added = false;
    _updatePlaylist(id, (p) {
      if (p.tracks.any((x) => _sameTrack(x, t))) return p;
      added = true;
      return p.copyWith(tracks: [...p.tracks, t]);
    });
    return added;
  }

  void removeFromPlaylist(String id, Track t) {
    _updatePlaylist(
      id,
      (p) => p.copyWith(
        tracks: p.tracks.where((x) => !_sameTrack(x, t)).toList(),
      ),
    );
  }

  Playlist? playlistById(String id) {
    for (final p in _playlists) {
      if (p.id == id) return p;
    }
    return null;
  }

  void _updatePlaylist(String id, Playlist Function(Playlist) f) {
    final i = _playlists.indexWhere((p) => p.id == id);
    if (i < 0) return;
    _playlists[i] = f(_playlists[i]);
    _persistPlaylists();
    notifyListeners();
  }

  // --- Recently played (recommendation seeds) --------------------------
  void recordPlayed(Track t) {
    _recent.removeWhere((x) => _sameTrack(x, t));
    _recent.insert(0, t);
    if (_recent.length > _recentCap) {
      _recent = _recent.sublist(0, _recentCap);
    }
    _persistRecent();
    notifyListeners();
  }

  // --- Export / import (re-importable JSON) ----------------------------
  String exportJson() => const JsonEncoder.withIndent('  ').convert({
        'version': exportVersion,
        'liked': _liked.map((t) => t.toJson()).toList(),
        'playlists': _playlists.map((p) => p.toJson()).toList(),
      });

  /// Merge an exported library into the current one (dedupe liked by videoId,
  /// playlists by id). Throws [FormatException] on malformed input.
  void importJson(String raw) {
    final data = jsonDecode(raw);
    if (data is! Map) throw const FormatException('Not a library export.');

    final liked = _decodeTracks(jsonEncode(data['liked'] ?? []));
    for (final t in liked) {
      if (!isLiked(t)) _liked.add(t);
    }

    final imported = (data['playlists'] as List?)
            ?.map((e) => Playlist.fromJson((e as Map).cast<String, dynamic>()))
            .toList() ??
        const [];
    for (final p in imported) {
      if (_playlists.any((x) => x.id == p.id)) continue;
      _playlists.add(p);
    }

    _persistLiked();
    _persistPlaylists();
    notifyListeners();
  }

  // --- Persistence helpers ---------------------------------------------
  void _persistLiked() =>
      _prefs?.setString(_kLiked, jsonEncode(_liked.map((t) => t.toJson()).toList()));
  void _persistRecent() =>
      _prefs?.setString(_kRecent, jsonEncode(_recent.map((t) => t.toJson()).toList()));
  void _persistPlaylists() => _prefs?.setString(
      _kPlaylists, jsonEncode(_playlists.map((p) => p.toJson()).toList()));

  List<Track> _decodeTracks(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw);
    if (list is! List) return [];
    return list
        .map((e) => Track.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  List<Playlist> _decodePlaylists(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw);
    if (list is! List) return [];
    return list
        .map((e) => Playlist.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  // Tracks are identified by videoId when present, else by title+artist.
  bool _sameTrack(Track a, Track b) {
    if (a.videoId != null && b.videoId != null) return a.videoId == b.videoId;
    return a.title == b.title && a.artistText == b.artistText;
  }
}

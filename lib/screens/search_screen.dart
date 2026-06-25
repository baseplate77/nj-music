import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../providers.dart';
import '../theme.dart';
import '../widgets/track_actions.dart';
import '../widgets/track_tile.dart';
import 'now_playing_screen.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  String _input = ''; // live text in the field
  String _query = ''; // submitted query (drives results)
  String _suggestQuery = ''; // debounced input (drives suggestions)
  bool _showSuggestions = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    setState(() {
      _input = v;
      _showSuggestions = v.trim().isNotEmpty;
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _suggestQuery = v.trim());
    });
  }

  void _submit(String q) {
    q = q.trim();
    if (q.isEmpty) return;
    _controller.value = TextEditingValue(
      text: q,
      selection: TextSelection.collapsed(offset: q.length),
    );
    setState(() {
      _input = q;
      _query = q;
      _showSuggestions = false;
    });
    FocusScope.of(context).unfocus();
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    setState(() {
      _input = '';
      _query = '';
      _suggestQuery = '';
      _showSuggestions = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Search'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: SearchBar(
              controller: _controller,
              hintText: 'Search songs, artists…',
              leading: const Icon(Iconsax.search_normal_1),
              trailing: [
                if (_input.isNotEmpty)
                  IconButton(
                    icon: const Icon(Iconsax.close_circle),
                    onPressed: _clear,
                  ),
              ],
              onChanged: _onChanged,
              onSubmitted: _submit,
            ),
          ),
        ),
      ),
      body: _input.trim().isEmpty
          ? const _EmptyState()
          : _showSuggestions
              ? _SuggestionsList(query: _suggestQuery, onTap: _submit)
              : _resultsView(),
    );
  }

  Widget _resultsView() {
    final results = ref.watch(searchProvider(_query));
    final player = ref.read(playerProvider);
    return results.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _ErrorState(message: '$e'),
      data: (tracks) {
        if (tracks.isEmpty) {
          return const Center(child: Text('No results'));
        }
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: kNavReserve),
          itemCount: tracks.length,
          itemBuilder: (context, i) {
            final t = tracks[i];
            // No scroll-triggered prefetch: warming a URL per tile built bursts
            // manifest requests and trips YouTube's rate limit. The tapped track
            // resolves on demand.
            return TrackTile(
              track: t,
              onTap: () {
                player.playTrackWithRadio(t);
                openNowPlaying(context);
              },
              trailing: TrackActions(track: t),
            );
          },
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Iconsax.search_normal_1,
              size: 64, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          const Text('Search for a song to start listening'),
          const SizedBox(height: 8),
          Text('Tap a result — recommendations queue up automatically',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Autocomplete suggestions shown while typing; tap one to run the search.
class _SuggestionsList extends ConsumerWidget {
  const _SuggestionsList({required this.query, required this.onTap});
  final String query;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestions = ref.watch(searchSuggestionsProvider(query));
    return suggestions.maybeWhen(
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: kNavReserve),
          itemCount: items.length,
          itemBuilder: (context, i) => ListTile(
            leading: Icon(Iconsax.search_normal_1,
                size: 20, color: Colors.white.withValues(alpha: 0.55)),
            title: Text(items[i],
                maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Icon(Iconsax.arrow_up_3,
                size: 16, color: Colors.white.withValues(alpha: 0.4)),
            onTap: () => onTap(items[i]),
          ),
        );
      },
      // Keep the list area quiet while debouncing/loading or on error.
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Iconsax.cloud_cross, size: 48),
            const SizedBox(height: 12),
            const Text('Something went wrong'),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

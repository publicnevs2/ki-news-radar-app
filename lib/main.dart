import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:share_plus/share_plus.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:audio_service/audio_service.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart'; // KORREKTUR: Fehlender Import
import 'audio_handler.dart'; 

// --- Datenmodell ---
class NewsArticle {
  final String source;
  final String title;
  final String link;
  final String summaryAi;
  final String type;
  final List<String> topics;
  final String audioUrl;
  final DateTime published;

  NewsArticle({
    required this.source,
    required this.title,
    required this.link,
    required this.summaryAi,
    required this.type,
    required this.topics,
    required this.audioUrl,
    required this.published,
  });

  factory NewsArticle.fromJson(Map<String, dynamic> json) {
    return NewsArticle(
      source: json['source'] ?? 'Unbekannte Quelle',
      title: json['title'] ?? 'Ohne Titel',
      link: json['link'] ?? '',
      summaryAi: json['summary_ai'] ?? 'Keine Zusammenfassung.',
      type: json['type'] ?? 'article',
      topics: List<String>.from(json['topics'] ?? []),
      audioUrl: json['audio_url'] ?? '',
      published: DateTime.tryParse(json['published'] ?? '') ?? DateTime.now(),
    );
  }
}

// --- Provider ---
final newsProvider = FutureProvider<List<NewsArticle>>((ref) async {
  final url = Uri.parse('https://raw.githubusercontent.com/publicnevs2/ki-news-radar/main/data.json');
  final headers = {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'};
  final response = await http.get(url, headers: headers);

  if (response.statusCode == 200) {
    final List<dynamic> jsonData = json.decode(utf8.decode(response.bodyBytes));
    return jsonData.map((item) => NewsArticle.fromJson(item)).toList();
  } else {
    throw Exception('Fehler beim Laden der News: ${response.statusCode}');
  }
});

final filterQueryProvider = StateProvider<String>((ref) => '');
enum ContentType { all, article, podcast }
final contentTypeFilterProvider = StateProvider<ContentType>((ref) => ContentType.all);

final filteredNewsProvider = Provider<List<NewsArticle>>((ref) {
  final filterQuery = ref.watch(filterQueryProvider).toLowerCase();
  final contentType = ref.watch(contentTypeFilterProvider);
  final newsAsyncValue = ref.watch(newsProvider);

  return newsAsyncValue.when(
    data: (news) {
      final typeFilteredNews = switch (contentType) {
        ContentType.all => news,
        ContentType.article => news.where((a) => a.type == 'article').toList(),
        ContentType.podcast => news.where((a) => a.type == 'podcast').toList(),
      };

      if (filterQuery.isEmpty) return typeFilteredNews;
      return typeFilteredNews.where((article) =>
          article.title.toLowerCase().contains(filterQuery) ||
          article.summaryAi.toLowerCase().contains(filterQuery) ||
          article.source.toLowerCase().contains(filterQuery) ||
          article.topics.any((topic) => topic.toLowerCase().contains(filterQuery))).toList();
    },
    loading: () => [],
    error: (e, st) => [],
  );
});

final topicFrequencyProvider = Provider<Map<String, int>>((ref) {
  final news = ref.watch(filteredNewsProvider);
  final topicCounts = <String, int>{};
  for (var article in news) {
    for (var topic in article.topics) {
      if (topic.isNotEmpty) {
        topicCounts[topic] = (topicCounts[topic] ?? 0) + 1;
      }
    }
  }
  return topicCounts;
});

final playbackStateProvider = StreamProvider<PlaybackState>((ref) {
  return audioHandler.playbackState;
});

final currentMediaItemProvider = StreamProvider<MediaItem?>((ref) {
  return audioHandler.mediaItem;
});


// --- Haupt-App ---
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initAudioHandler();
  await initializeDateFormatting('de_DE', null);
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KI-News-Radar',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        primaryColor: Colors.blue.shade300,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF3B82F6),
          secondary: Color(0xFF60A5FA),
          surface: Color(0xFF1E1E1E),
          onSurface: Color(0xFFE0E0E0),
        ),
        textTheme: GoogleFonts.manropeTextTheme(
          Theme.of(context).textTheme.apply(bodyColor: const Color(0xFFE0E0E0)),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF121212),
          elevation: 0,
        ),
      ),
      home: const MainScreen(),
    );
  }
}

// --- Haupt-Container mit Bottom Navigation UND Mini-Player ---
class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});
  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  int _selectedIndex = 0;

  void _onItemTapped(int index) {
    if (_selectedIndex != index) ref.read(filterQueryProvider.notifier).state = '';
    setState(() => _selectedIndex = index);
  }
  
  void selectTopic(String topic) {
     ref.read(filterQueryProvider.notifier).state = topic;
     ref.read(contentTypeFilterProvider.notifier).state = ContentType.all;
     setState(() => _selectedIndex = 0);
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const NewsFeedPage(),
      RadarPage(onTopicSelected: selectTopic),
      const SearchPage(),
   ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('KI-News-Radar'),
        centerTitle: true,
      ),
      drawer: const AppDrawer(),
      body: Column(
        children: [
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: pages,
            ),
          ),
          const MiniPlayer(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.article_outlined), activeIcon: Icon(Icons.article), label: 'Heute'),
          BottomNavigationBarItem(icon: Icon(Icons.radar_outlined), activeIcon: Icon(Icons.radar), label: 'Radar'),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Suche'),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Colors.grey,
        backgroundColor: const Color(0xFF1E1E1E),
        showUnselectedLabels: false,
        showSelectedLabels: true,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}

// --- Seiten-Widgets ---

class NewsFeedPage extends ConsumerWidget {
  const NewsFeedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final articles = ref.watch(filteredNewsProvider);
    final isTopicFilterActive = ref.watch(filterQueryProvider).isNotEmpty;
    
    return RefreshIndicator(
      onRefresh: () async {
        HapticFeedback.mediumImpact();
        ref.read(filterQueryProvider.notifier).state = '';
        ref.read(contentTypeFilterProvider.notifier).state = ContentType.all;
        return ref.refresh(newsProvider.future);
      },
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: SegmentedButton<ContentType>(
              segments: const <ButtonSegment<ContentType>>[
                ButtonSegment<ContentType>(value: ContentType.all, label: Text('Alle')),
                ButtonSegment<ContentType>(value: ContentType.article, label: Text('News'), icon: Icon(Icons.article_outlined)),
                ButtonSegment<ContentType>(value: ContentType.podcast, label: Text('Pod'), icon: Icon(Icons.mic_outlined)),
              ],
              selected: {ref.watch(contentTypeFilterProvider)},
              onSelectionChanged: (Set<ContentType> newSelection) {
                ref.read(contentTypeFilterProvider.notifier).state = newSelection.first;
              },
              style: SegmentedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.surface,
                foregroundColor: Colors.white70,
                selectedForegroundColor: Theme.of(context).colorScheme.primary,
                // KORREKTUR: Veraltete Funktion ersetzt
                selectedBackgroundColor: Theme.of(context).colorScheme.primary.withAlpha(51),
              ),
            ),
          ),
          if (isTopicFilterActive)
            Container(
              color: Theme.of(context).colorScheme.surface,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(child: Text("Thema: '${ref.read(filterQueryProvider)}'", overflow: TextOverflow.ellipsis)),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => ref.read(filterQueryProvider.notifier).state = '',
                  )
                ],
              ),
            ),
          Expanded(
            child: ref.watch(newsProvider).when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (err, stack) => Center(child: Text('Fehler beim Laden: $err')),
                  data: (_) => articles.isEmpty
                      ? const Center(child: Text("Keine Beiträge für diesen Filter gefunden."))
                      : AnimationLimiter(
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 8.0),
                            itemCount: articles.length,
                            itemBuilder: (context, index) {
                              final article = articles[index];
                              return AnimationConfiguration.staggeredList(
                                position: index,
                                duration: const Duration(milliseconds: 375),
                                child: SlideAnimation(
                                  verticalOffset: 50.0,
                                  child: FadeInAnimation(child: NewsCard(article: article)),
                                ),
                              );
                            },
                          ),
                        ),
                ),
          ),
        ],
      ),
    );
  }
}

class RadarPage extends ConsumerWidget {
  final Function(String) onTopicSelected;
  const RadarPage({super.key, required this.onTopicSelected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final newsAsyncValue = ref.watch(newsProvider);

    return newsAsyncValue.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => const Center(child: Text('Fehler beim Laden der Themendaten')),
      data: (articles) {
        final topicCounts = ref.watch(topicFrequencyProvider);
        if (topicCounts.isEmpty) {
          return const Center(child: Text("Keine Themen zum Anzeigen gefunden."));
        }
        
        final sortedTopics = topicCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
        final topTopics = sortedTopics.take(7).toList();

        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Top-Themen", style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text("Tippe auf einen Balken, um die News zu filtern.", style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 32),
              Expanded(
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY: (topTopics.first.value.toDouble()) * 1.2,
                    barTouchData: BarTouchData(
                      touchTooltipData: BarTouchTooltipData(
                        // KORREKTUR: Veralteter Parameter ersetzt
                        getTooltipColor: (group) => Colors.grey[800] ?? Colors.grey,
                        getTooltipItem: (group, groupIndex, rod, rodIndex) {
                           return BarTooltipItem(
                             '${topTopics[group.x.toInt()].key}\n',
                             const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                             children: <TextSpan>[
                               TextSpan(
                                 text: rod.toY.toInt().toString(),
                                 style: TextStyle(
                                   color: Theme.of(context).colorScheme.secondary,
                                   fontWeight: FontWeight.w500,
                                 ),
                               ),
                               const TextSpan(text: ' Erwähnungen', style: TextStyle(color: Colors.white)),
                             ],
                           );
                        },
                      ),
                      touchCallback: (event, response) {
                        if (response != null && response.spot != null && event is FlTapUpEvent) {
                           final index = response.spot!.touchedBarGroupIndex;
                           onTopicSelected(topTopics[index].key);
                        }
                      }
                    ),
                    titlesData: FlTitlesData(
                      show: true,
                      bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (value, meta) {
                            final index = value.toInt();
                            if (index < topTopics.length) {
                              return Padding(padding: const EdgeInsets.only(top: 6.0), child: Text(topTopics[index].key, style: const TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis));
                            }
                            return const Text('');
                          }, reservedSize: 38)),
                      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    borderData: FlBorderData(show: false),
                    gridData: const FlGridData(show: false),
                    barGroups: topTopics.asMap().entries.map((entry) {
                       return BarChartGroupData(x: entry.key, barRods: [
                            BarChartRodData(
                              toY: entry.value.value.toDouble(), 
                              color: Theme.of(context).colorScheme.primary, 
                              width: 22, 
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(6),
                                topRight: Radius.circular(6),
                              ),
                            )
                          ]);
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        );
      }
    );
  }
}

class SearchPage extends ConsumerWidget {
  const SearchPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filteredArticles = ref.watch(filteredNewsProvider);
    final hasQuery = ref.watch(filterQueryProvider).isNotEmpty;
    final searchController = TextEditingController(text: ref.watch(filterQueryProvider));
    searchController.selection = TextSelection.fromPosition(TextPosition(offset: searchController.text.length));

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          TextField(
            controller: searchController,
            onChanged: (query) => ref.read(filterQueryProvider.notifier).state = query,
            decoration: InputDecoration(
              labelText: 'Suchen...',
              suffixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: hasQuery 
              ? ListView.builder(itemCount: filteredArticles.length, itemBuilder: (context, index) => NewsCard(article: filteredArticles[index]))
              : const Center(child: Text("Beginne zu tippen, um zu suchen.", style: TextStyle(color: Colors.grey))),
          ),
        ],
      ),
    );
  }
}

// --- Wiederverwendbare Widgets ---

class NewsCard extends ConsumerWidget {
  final NewsArticle article;
  const NewsCard({super.key, required this.article});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentItem = ref.watch(currentMediaItemProvider).asData?.value;
    final playbackState = ref.watch(playbackStateProvider).asData?.value;
    final isPlaying = playbackState?.playing == true && currentItem?.id == article.audioUrl;

    final icon = article.type == 'podcast' ? Icons.mic_rounded : Icons.article_rounded;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(article.source.toUpperCase(), style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary, letterSpacing: 0.5), overflow: TextOverflow.ellipsis)),
                IconButton(icon: const Icon(Icons.share, size: 20, color: Colors.grey), onPressed: () => Share.share('KI-News-Radar: ${article.title}\n${article.link}')),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
              child: Text(
                DateFormat('dd. MMMM yyyy', 'de_DE').format(article.published),
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
            Text(article.title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text(article.summaryAi, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70)),
            if (article.topics.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: Wrap(spacing: 6.0, runSpacing: 4.0, children: article.topics.map((topic) => Chip(label: Text(topic), backgroundColor: Theme.of(context).colorScheme.surface, side: BorderSide(color: Colors.grey.shade700), labelStyle: const TextStyle(fontSize: 10), padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0))).toList()),
              ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: article.type == 'podcast' && article.audioUrl.isNotEmpty
                ? IconButton(
                    icon: Icon(isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled, size: 40, color: Theme.of(context).colorScheme.primary),
                    onPressed: () {
                      if (isPlaying) {
                        audioHandler.pause();
                      } else {
                        final mediaItem = MediaItem(id: article.audioUrl, title: article.title, artist: article.source);
                        audioHandler.playMediaItem(mediaItem);
                      }
                    },
                  )
                : TextButton(
                    onPressed: () async {
                       final url = Uri.parse(article.link);
                       if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.inAppWebView);
                    },
                    child: const Text('ZUM ORIGINAL'),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mediaItem = ref.watch(currentMediaItemProvider).asData?.value;
    final playbackState = ref.watch(playbackStateProvider).asData?.value;

    if (mediaItem == null || playbackState == null || playbackState.processingState == AudioProcessingState.idle) {
      return const SizedBox.shrink();
    }

    final isPlaying = playbackState.playing;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Colors.grey.shade800, width: 1.0)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      height: 64,
      child: Row(
        children: [
          const Icon(Icons.music_note, color: Colors.grey),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(mediaItem.title, style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(mediaItem.artist ?? '', style: TextStyle(color: Colors.grey[400], fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          IconButton(
            icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow, size: 32, color: Theme.of(context).colorScheme.primary),
            onPressed: isPlaying ? audioHandler.pause : audioHandler.play,
          ),
          IconButton(
            icon: const Icon(Icons.stop, size: 32),
            onPressed: audioHandler.stop,
          ),
        ],
      ),
    );
  }
}

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          UserAccountsDrawerHeader(
            accountName: const Text("Sven", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            accountEmail: const Text("AI Strategist & Visionary"),
            currentAccountPicture: const CircleAvatar(backgroundImage: AssetImage("assets/sven_profile.jpg")),
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary),
          ),
          ListTile(leading: const Icon(Icons.info_outline), title: const Text('Über die App'), onTap: () => Navigator.pop(context)),
          ListTile(leading: const Icon(Icons.settings), title: const Text('Einstellungen'), onTap: () => Navigator.pop(context)),
        ],
      ),
    );
  }
}


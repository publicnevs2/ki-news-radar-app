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
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'audio_handler.dart';
import 'dart:math';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

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

// HIER DIE ADRESSE DEINES BACKENDS EINTRAGEN
// Wähle die richtige Adresse, je nachdem, wo du die App testest:
// - Für den Android Emulator: 'http://10.0.2.2:8000'
// - Für Windows/Web/iOS Simulator: 'http://127.0.0.1:8000'
//const String backendUrl = 'http://10.0.2.2:8000';
const String backendUrl = 'https://ki-news-radar-backend.onrender.com';


final newsProvider = FutureProvider<List<NewsArticle>>((ref) async {
  // ANGEPASST: Greift jetzt auf deine lokale API zu
  final url = Uri.parse('$backendUrl/api/articles');
  final headers = {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'};
  final response = await http.get(url, headers: headers);

  if (response.statusCode == 200) {
    final List<dynamic> jsonData = json.decode(utf8.decode(response.bodyBytes));
    final articles = jsonData.map((item) => NewsArticle.fromJson(item)).toList();
    // Sortierung ist nicht mehr nötig, da die API das bereits erledigt
    return articles;
  } else {
    throw Exception('Fehler beim Laden der News: ${response.statusCode}');
  }
});

final dailySummaryProvider = FutureProvider<String>((ref) async {
  // ANGEPASST: Greift jetzt auf deine lokale API zu
  final url = Uri.parse('$backendUrl/api/summary');
  final headers = {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'};
  final response = await http.get(url, headers: headers);

  if (response.statusCode == 200) {
    final Map<String, dynamic> jsonData = json.decode(utf8.decode(response.bodyBytes));
    return jsonData['summary_text'] ?? "Keine Zusammenfassung für heute verfügbar.";
  } else {
    return "Das Tages-Briefing konnte nicht geladen werden. Bitte später erneut versuchen.";
  }
});


final filterQueryProvider = StateProvider<String>((ref) => '');
enum ContentType { all, article, podcast }
final contentTypeFilterProvider = StateProvider<ContentType>((ref) => ContentType.all);

final favoritesProvider = StateNotifierProvider<FavoritesNotifier, Set<String>>((ref) {
  return FavoritesNotifier();
});

final availableSourcesProvider = Provider<List<String>>((ref) {
  return ref.watch(newsProvider).when(
    data: (articles) => articles.map((a) => a.source).toSet().toList()..sort(),
    loading: () => [],
    error: (_, __) => [],
  );
});

final selectedSourcesProvider = StateNotifierProvider<SelectedSourcesNotifier, Set<String>>((ref) {
  final availableSources = ref.watch(availableSourcesProvider);
  return SelectedSourcesNotifier(availableSources.toSet());
});

final mainScreenIndexProvider = StateProvider<int>((ref) => 0);

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier();
});
final isCompactViewProvider = StateProvider<bool>((ref) => false);


class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.dark) {
    _loadThemeMode();
  }
  static const _themeKey = 'theme_mode';

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt(_themeKey) ?? ThemeMode.dark.index;
    state = ThemeMode.values[themeIndex];
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeKey, mode.index);
  }
}

class SelectedSourcesNotifier extends StateNotifier<Set<String>> {
  SelectedSourcesNotifier(super.initialSources);

  void setSource(String source) {
    state = {source};
  }

  void toggleSource(String source) {
    if (state.contains(source)) {
      state = state.where((s) => s != source).toSet();
    } else {
      state = {...state, source};
    }
  }
  
  void selectAll(List<String> allSources) {
    state = allSources.toSet();
  }
}


class FavoritesNotifier extends StateNotifier<Set<String>> {
  FavoritesNotifier() : super({}) {
    _loadFavorites();
  }
  static const _favoritesKey = 'favorite_articles';

  Future<void> _loadFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final favorites = prefs.getStringList(_favoritesKey) ?? [];
      state = favorites.toSet();
    } catch (e) {
      state = {};
    }
  }

  Future<void> toggleFavorite(String link) async {
    final prefs = await SharedPreferences.getInstance();
    final currentFavorites = Set<String>.from(state);
    if (currentFavorites.contains(link)) {
      currentFavorites.remove(link);
    } else {
      currentFavorites.add(link);
    }
    await prefs.setStringList(_favoritesKey, currentFavorites.toList());
    state = currentFavorites;
  }
}

final filteredNewsProvider = Provider<List<NewsArticle>>((ref) {
  final filterQuery = ref.watch(filterQueryProvider).toLowerCase();
  final contentType = ref.watch(contentTypeFilterProvider);
  final selectedSources = ref.watch(selectedSourcesProvider);
  final newsAsyncValue = ref.watch(newsProvider);

  return newsAsyncValue.when(
    data: (news) {
      List<NewsArticle> filteredNews = news;

      if (selectedSources.isNotEmpty) {
        filteredNews = filteredNews.where((article) => selectedSources.contains(article.source)).toList();
      }
      
      filteredNews = switch (contentType) {
        ContentType.all => filteredNews,
        ContentType.article => filteredNews.where((a) => a.type == 'article').toList(),
        ContentType.podcast => filteredNews.where((a) => a.type == 'podcast').toList(),
      };

      if (filterQuery.isNotEmpty) {
        return filteredNews.where((article) =>
            article.title.toLowerCase().contains(filterQuery) ||
            article.summaryAi.toLowerCase().contains(filterQuery) ||
            article.source.toLowerCase().contains(filterQuery) ||
            article.topics.any((topic) => topic.toLowerCase().contains(filterQuery))).toList();
      }
      return filteredNews;
    },
    loading: () => [],
    error: (e, st) => [],
  );
});

final topicFrequencyProvider = Provider<Map<String, int>>((ref) {
  final newsAsyncValue = ref.watch(newsProvider);
  return newsAsyncValue.when(
    data: (news) {
        final topicCounts = <String, int>{};
        for (var article in news) {
          for (var topic in article.topics) {
            if (topic.isNotEmpty) {
              topicCounts[topic] = (topicCounts[topic] ?? 0) + 1;
            }
          }
        }
        return topicCounts;
    },
    loading: () => {},
    error: (_, __) => {},
  );
});

final sourceDistributionProvider = Provider<Map<String, int>>((ref) {
    final articles = ref.watch(newsProvider).asData?.value ?? [];
    final distribution = <String, int>{};
    for (var article in articles) {
        distribution[article.source] = (distribution[article.source] ?? 0) + 1;
    }
    return distribution;
});


final playbackStateProvider = StreamProvider<PlaybackState>((ref) => audioHandler.playbackState);
final currentMediaItemProvider = StreamProvider<MediaItem?>((ref) => audioHandler.mediaItem);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await initAudioHandler();
  await initializeDateFormatting('de_DE', null);
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    final darkTheme = ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        primaryColor: Colors.blue.shade300,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF3B82F6),
          secondary: Color(0xFF60A5FA),
          surface: Color(0xFF1E1E1E),
          onSurface: Color(0xFFE0E0E0),
        ),
        textTheme: GoogleFonts.manropeTextTheme(Theme.of(context).textTheme.apply(bodyColor: const Color(0xFFE0E0E0))),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF121212), elevation: 0),
      );

    final lightTheme = ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF0F2F5),
      primaryColor: Colors.blue.shade600,
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF2563EB),
        secondary: Color(0xFF3B82F6),
        surface: Colors.white,
        onSurface: Color(0xFF111827),
      ),
      textTheme: GoogleFonts.manropeTextTheme(Theme.of(context).textTheme.apply(bodyColor: const Color(0xFF111827))),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFF0F2F5), 
        elevation: 0,
        foregroundColor: Color(0xFF111827)
      ),
    );


    return MaterialApp(
      title: 'KI-News-Radar',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      home: const MainScreen(),
    );
  }
}

class MainScreen extends ConsumerWidget {
  const MainScreen({super.key});
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {

    final selectedIndex = ref.watch(mainScreenIndexProvider);

    void onItemTapped(int index) {
      if (selectedIndex != index) ref.read(filterQueryProvider.notifier).state = '';
      ref.read(mainScreenIndexProvider.notifier).state = index;
    }
    
    void selectTopic(String topic) {
       ref.read(filterQueryProvider.notifier).state = topic;
       ref.read(contentTypeFilterProvider.notifier).state = ContentType.all;
       ref.read(mainScreenIndexProvider.notifier).state = 0;
    }
    
    void showSourceFilter() {
      final allSources = ref.read(availableSourcesProvider);
      showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (context) {
              return DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.6,
                maxChildSize: 0.9,
                builder: (BuildContext context, ScrollController scrollController) {
                  return Consumer(
                    builder: (context, ref, child) {
                      final selectedSources = ref.watch(selectedSourcesProvider);
                      return Container(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                  Text("Quellen filtern", style: Theme.of(context).textTheme.headlineSmall),
                                  const SizedBox(height: 8),
                                  Expanded(
                                      child: ListView.builder(
                                          controller: scrollController,
                                          itemCount: allSources.length,
                                          itemBuilder: (context, index) {
                                              final source = allSources[index];
                                              return CheckboxListTile(
                                                  title: Text(source),
                                                  value: selectedSources.contains(source),
                                                  onChanged: (bool? value) {
                                                      ref.read(selectedSourcesProvider.notifier).toggleSource(source);
                                                  },
                                              );
                                          },
                                      ),
                                  ),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                       TextButton(onPressed: () {
                                         ref.read(selectedSourcesProvider.notifier).selectAll(allSources);
                                       }, child: const Text("Alle auswählen")),
                                       const SizedBox(width: 8),
                                       FilledButton(onPressed: () => Navigator.pop(context), child: const Text("Anwenden"))
                                    ],
                                  )
                              ],
                          ),
                      );
                    },
                  );
                },
              );
          },
      );
    }

    final pages = <Widget>[
      const NewsFeedPage(),
      RadarPage(onTopicSelected: selectTopic),
      const StatisticsPage(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('KI-News-Radar'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: showSourceFilter,
            tooltip: "Quellen filtern",
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const SearchPage())),
            tooltip: "Suchen",
          ),
        ],
      ),
      drawer: const AppDrawer(),
      body: Column(
        children: [
          Expanded(child: IndexedStack(index: selectedIndex, children: pages)),
          const MiniPlayer(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.article_outlined), activeIcon: Icon(Icons.article), label: 'Heute'),
          BottomNavigationBarItem(icon: Icon(Icons.radar_outlined), activeIcon: Icon(Icons.radar), label: 'Radar'),
          BottomNavigationBarItem(icon: Icon(Icons.analytics_outlined), activeIcon: Icon(Icons.analytics), label: 'Insights'),
        ],
        currentIndex: selectedIndex,
        onTap: onItemTapped,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}

// --- Page Widgets ---

class NewsFeedPage extends ConsumerStatefulWidget {
  const NewsFeedPage({super.key});

  @override
  ConsumerState<NewsFeedPage> createState() => _NewsFeedPageState();
}

class _NewsFeedPageState extends ConsumerState<NewsFeedPage> {

  Future<void> _getLiveKiNewsBriefing(BuildContext context) async {
    final apiKey = dotenv.env['GEMINI_API_KEY'];

    if (apiKey == null || apiKey.isEmpty) {
       showDialog(context: context, builder: (context) => AlertDialog(title: const Text("API Key fehlt"), content: const Text("Bitte füge deinen Gemini API Key in der .env-Datei hinzu, um dieses Feature zu nutzen."), actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("OK"))]));
       return;
    }
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Dialog(child: Padding(padding: EdgeInsets.all(20), child: Row(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(width: 20), Text("Live-Briefing wird erstellt...")]))),
    );

    try {
      final model = GenerativeModel(model: 'gemini-1.5-flash-latest', apiKey: apiKey);
      
      final today = DateFormat('d. MMMM yyyy', 'de_DE').format(DateTime.now());
      final prompt = "Gib mir ein professionelles Briefing der wichtigsten und aktuellsten Nachrichten zum Thema Künstliche Intelligenz von heute, dem $today. Nutze die Google-Suche, um die neuesten Quellen zu finden und fasse die Ergebnisse auf Deutsch zusammen. Antworte nur mit der Zusammenfassung.";
      
      final response = await model.generateContent([Content.text(prompt)]);
      
      if (!mounted) return;
      Navigator.of(context).pop();

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Brandaktuelles KI-Briefing"),
          content: SingleChildScrollView(child: Text(response.text ?? "Keine Antwort erhalten.")),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("Schließen"))],
        ),
      );

    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Fehler"),
          content: Text("Das Live-Briefing konnte nicht erstellt werden:\n\n$e"),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text("OK"))],
        ),
      );
    }
  }


  void _showDailySummaryDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("KI-Tages-Briefing"),
          content: Consumer(
            builder: (context, ref, child) {
              final summaryAsync = ref.watch(dailySummaryProvider);
              return summaryAsync.when(
                loading: () => const SizedBox(height: 100, child: Center(child: CircularProgressIndicator())),
                error: (err, stack) => Text("Fehler beim Laden des Briefings:\n$err"),
                data: (summary) => SingleChildScrollView(child: Text(summary)),
              );
            },
          ),
          actions: <Widget>[
            TextButton(
              child: const Text("Schließen"),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  List<dynamic> _groupAndFlattenArticles(List<NewsArticle> articles, String locale) {
    if (articles.isEmpty) return [];
    final grouped = <String, List<NewsArticle>>{};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateMap = <String, DateTime>{};

    for (final article in articles) {
      final articleDate = DateTime(article.published.year, article.published.month, article.published.day);
      String key;
      if (articleDate == today) {
        key = 'Heute';
      } else if (articleDate == yesterday) {
        key = 'Gestern';
      } else {
        key = DateFormat('EEEE, dd. MMMM', locale).format(article.published);
      }
      dateMap.putIfAbsent(key, () => articleDate);
      grouped.putIfAbsent(key, () => []).add(article);
    }

    final sortedKeys = grouped.keys.toList()..sort((a, b) => dateMap[b]!.compareTo(dateMap[a]!));
    final flatList = <dynamic>[];
    for (final key in sortedKeys) {
      flatList.add(key);
      flatList.addAll(grouped[key]!);
    }
    return flatList;
  }

  @override
  Widget build(BuildContext context) {
    final articles = ref.watch(filteredNewsProvider);
    final isTopicFilterActive = ref.watch(filterQueryProvider).isNotEmpty;
    final isCompactView = ref.watch(isCompactViewProvider);
    final groupedAndFlatArticles = _groupAndFlattenArticles(articles, 'de_DE');
    
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          HapticFeedback.mediumImpact();
          ref.read(filterQueryProvider.notifier).state = '';
          ref.read(contentTypeFilterProvider.notifier).state = ContentType.all;
          final allSources = ref.read(availableSourcesProvider);
          ref.read(selectedSourcesProvider.notifier).selectAll(allSources);
          // Refresh both providers
          await ref.refresh(dailySummaryProvider.future);
          await ref.refresh(newsProvider.future);
        },
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: ToggleButtons(
                      isSelected: [
                        ref.watch(contentTypeFilterProvider) == ContentType.all,
                        ref.watch(contentTypeFilterProvider) == ContentType.article,
                        ref.watch(contentTypeFilterProvider) == ContentType.podcast,
                      ],
                      onPressed: (int index) {
                        ref.read(contentTypeFilterProvider.notifier).state = ContentType.values[index];
                      },
                      borderRadius: BorderRadius.circular(8.0),
                      constraints: const BoxConstraints(minHeight: 40.0),
                      children: const [
                        Padding(padding: EdgeInsets.symmetric(horizontal: 16.0), child: Text('Alle')),
                        Padding(padding: EdgeInsets.symmetric(horizontal: 16.0), child: Text('News')),
                        Padding(padding: EdgeInsets.symmetric(horizontal: 16.0), child: Text('Podcasts')),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    icon: Icon(isCompactView ? Icons.view_agenda_outlined : Icons.view_list_outlined),
                    tooltip: isCompactView ? "Detailansicht" : "Kompaktansicht",
                    onPressed: () => ref.read(isCompactViewProvider.notifier).state = !isCompactView,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.article_outlined),
                  label: const Text("Tages-Briefing"),
                  onPressed: () => _showDailySummaryDialog(context, ref),
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
                    IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => ref.read(filterQueryProvider.notifier).state = ''),
                  ],
                ),
              ),
            Expanded(
              child: ref.watch(newsProvider).when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (err, stack) => Center(child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text('Verbindungsfehler.\n\nStelle sicher, dass dein Backend-Server läuft und die IP-Adresse in der App korrekt ist.\n\nFehler: $err', textAlign: TextAlign.center),
                    )),
                    data: (_) => articles.isEmpty
                        ? Center(child: Text("Keine Beiträge für diesen Filter gefunden.", style: TextStyle(color: Colors.grey.shade600)))
                        : AnimationLimiter(
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(8.0, 0, 8.0, 80.0),
                              itemCount: groupedAndFlatArticles.length,
                              itemBuilder: (context, index) {
                                final item = groupedAndFlatArticles[index];
                                if (item is String) {
                                  return Padding(
                                    padding: const EdgeInsets.only(left: 8.0, right: 8.0, top: 24.0, bottom: 8.0),
                                    child: Text(
                                      item.toUpperCase(),
                                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.8),
                                    ),
                                  );
                                } else if (item is NewsArticle) {
                                  int articleIndex = groupedAndFlatArticles.sublist(0, index).whereType<NewsArticle>().length;
                                  final card = isCompactView ? CompactNewsCard(article: item) : NewsCard(article: item);
                                  return AnimationConfiguration.staggeredList(
                                    position: articleIndex,
                                    duration: const Duration(milliseconds: 375),
                                    child: SlideAnimation(verticalOffset: 50.0, child: FadeInAnimation(child: card)),
                                  );
                                }
                                return const SizedBox.shrink();
                              },
                            ),
                          ),
                  ),
            ),
          ],
        ),
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
        final topTopics = sortedTopics.take(15).toList();
        final double maxValue = topTopics.isNotEmpty ? topTopics.first.value.toDouble() : 1.0;

        return AnimationLimiter(
          child: ListView.builder(
            padding: const EdgeInsets.all(16.0),
            itemCount: topTopics.length + 1, // +1 for the header
            itemBuilder: (context, index) {
              if (index == 0) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Top-Themen", style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text("Tippe auf ein Thema, um die News zu filtern.", style: TextStyle(color: Colors.grey)),
                    const SizedBox(height: 24),
                  ],
                );
              }
              final topic = topTopics[index - 1];
              return AnimationConfiguration.staggeredList(
                position: index -1,
                duration: const Duration(milliseconds: 375),
                child: SlideAnimation(
                  verticalOffset: 50.0,
                  child: FadeInAnimation(
                    child: InkWell(
                      onTap: () => onTopicSelected(topic.key),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(child: Text(topic.key, style: Theme.of(context).textTheme.titleMedium)),
                                Text(topic.value.toString(), style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.primary)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: LinearProgressIndicator(
                                value: topic.value / maxValue,
                                minHeight: 8,
                                backgroundColor: Theme.of(context).colorScheme.surface,
                                valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class SearchPage extends ConsumerWidget {
  const SearchPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text("Suche")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              autofocus: true,
              onChanged: (query) => ref.read(filterQueryProvider.notifier).state = query,
              decoration: InputDecoration(
                labelText: 'Suchen...',
                suffixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ref.watch(filterQueryProvider).isNotEmpty
                ? Consumer(builder: (context, ref, _) {
                    final articles = ref.watch(filteredNewsProvider);
                    return ListView.builder(itemCount: articles.length, itemBuilder: (context, index) => NewsCard(article: articles[index]));
                  })
                : const Center(child: Text("Beginne zu tippen, um zu suchen.", style: TextStyle(color: Colors.grey))),
            ),
          ],
        ),
      ),
    );
  }
}

class FavoritesPage extends ConsumerWidget {
  const FavoritesPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allArticles = ref.watch(newsProvider).asData?.value ?? [];
    final favoriteLinks = ref.watch(favoritesProvider);

    final favoriteArticles = allArticles.where((article) => favoriteLinks.contains(article.link)).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meine Leseliste'),
      ),
      body: favoriteArticles.isEmpty
          ? const Center(
              child: Text(
                'Du hast noch keine Artikel markiert.\nTippe auf das Lesezeichen-Symbol 🔖 bei einem Artikel.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(8.0),
              itemCount: favoriteArticles.length,
              itemBuilder: (context, index) {
                return NewsCard(article: favoriteArticles[index]);
              },
            ),
    );
  }
}

class StatisticsPage extends ConsumerStatefulWidget {
  const StatisticsPage({super.key});

  @override
  ConsumerState<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends ConsumerState<StatisticsPage> {
  int touchedIndex = -1;

  @override
  Widget build(BuildContext context) {
    final sourceDistribution = ref.watch(sourceDistributionProvider);
    final topicFrequency = ref.watch(topicFrequencyProvider);

    final sortedTopics = topicFrequency.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final List<Color> pieColors = [
      Colors.blue.shade300,
      Colors.red.shade300,
      Colors.green.shade300,
      Colors.orange.shade300,
      Colors.purple.shade300,
      Colors.yellow.shade700,
      Colors.teal.shade300,
      Colors.pink.shade300,
      Colors.indigo.shade300,
    ];

    if (sourceDistribution.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Insights",
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          Text("Beiträge pro Quelle",
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: PieChart(
              PieChartData(
                pieTouchData: PieTouchData(
                  touchCallback: (FlTouchEvent event, pieTouchResponse) {
                    if (event is FlTapUpEvent &&
                        pieTouchResponse != null &&
                        pieTouchResponse.touchedSection != null) {
                      final index = pieTouchResponse.touchedSection!.touchedSectionIndex;
                      final sourceName = sourceDistribution.keys.toList()[index];
                      
                      ref.read(filterQueryProvider.notifier).state = '';
                      ref.read(contentTypeFilterProvider.notifier).state = ContentType.all;
                      ref.read(selectedSourcesProvider.notifier).setSource(sourceName);
                      ref.read(mainScreenIndexProvider.notifier).state = 0;
                    }

                    setState(() {
                      if (!event.isInterestedForInteractions ||
                          pieTouchResponse == null ||
                          pieTouchResponse.touchedSection == null) {
                        touchedIndex = -1;
                        return;
                      }
                      touchedIndex =
                          pieTouchResponse.touchedSection!.touchedSectionIndex;
                    });
                  },
                ),
                sections: sourceDistribution.entries
                    .toList()
                    .asMap()
                    .entries
                    .map((entry) {
                  final index = entry.key;
                  final data = entry.value;
                  final isTouched = index == touchedIndex;
                  final fontSize = isTouched ? 20.0 : 16.0;
                  final radius = isTouched ? 90.0 : 80.0;
                  final titleStyle = TextStyle(
                      fontSize: fontSize,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      shadows: const [
                        Shadow(color: Colors.black, blurRadius: 2)
                      ]);

                  return PieChartSectionData(
                      color: pieColors[index % pieColors.length],
                      value: data.value.toDouble(),
                      title: '${data.value}',
                      radius: radius,
                      titleStyle: titleStyle);
                }).toList(),
                sectionsSpace: 2,
                centerSpaceRadius: 40,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8.0,
            runSpacing: 4.0,
            alignment: WrapAlignment.center,
            children: sourceDistribution.entries
                .toList()
                .asMap()
                .entries
                .map((entry) {
              final index = entry.key;
              final data = entry.value;
              return Chip(
                avatar: CircleAvatar(
                    backgroundColor: pieColors[index % pieColors.length],
                    radius: 6),
                label: Text(data.key),
                backgroundColor: Theme.of(context).colorScheme.surface,
              );
            }).toList(),
          ),
          const SizedBox(height: 32),
          Text("Top-Themen", style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8.0,
            runSpacing: 8.0,
            children: sortedTopics.take(15).map((topic) {
              return ActionChip(
                onPressed: () {
                  ref.read(contentTypeFilterProvider.notifier).state = ContentType.all;
                  final allSources = ref.read(availableSourcesProvider);
                  ref.read(selectedSourcesProvider.notifier).selectAll(allSources);
                  ref.read(filterQueryProvider.notifier).state = topic.key;
                  ref.read(mainScreenIndexProvider.notifier).state = 0;
                },
                label: Text(topic.key),
                labelStyle: TextStyle(fontSize: (12.0 + (log(topic.value) * 2.5)).clamp(12, 22)),
                backgroundColor: Theme.of(context).colorScheme.surface,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              );
            }).toList(),
          )
        ],
      ),
    );
  }
}

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentThemeMode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Einstellungen'),
      ),
      body: ListView(
        children: [
          ListTile(
            title: Text("Darstellung", style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
          ),
          RadioListTile<ThemeMode>(
            title: const Text('Heller Modus'),
            value: ThemeMode.light,
            groupValue: currentThemeMode,
            onChanged: (ThemeMode? value) {
              if (value != null) {
                ref.read(themeModeProvider.notifier).setThemeMode(value);
              }
            },
          ),
          RadioListTile<ThemeMode>(
            title: const Text('Dunkler Modus'),
            value: ThemeMode.dark,
            groupValue: currentThemeMode,
            onChanged: (ThemeMode? value) {
              if (value != null) {
                ref.read(themeModeProvider.notifier).setThemeMode(value);
              }
            },
          ),
          RadioListTile<ThemeMode>(
            title: const Text('Systemeinstellung verwenden'),
            value: ThemeMode.system,
            groupValue: currentThemeMode,
            onChanged: (ThemeMode? value) {
              if (value != null) {
                ref.read(themeModeProvider.notifier).setThemeMode(value);
              }
            },
          ),
        ],
      ),
    );
  }
}


// --- Reusable Widgets ---

class NewsCard extends ConsumerWidget {
  final NewsArticle article;
  const NewsCard({super.key, required this.article});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentItem = ref.watch(currentMediaItemProvider).asData?.value;
    final playbackState = ref.watch(playbackStateProvider).asData?.value;
    final isPlaying = playbackState?.playing == true && currentItem?.id == article.audioUrl;

    final favoriteLinks = ref.watch(favoritesProvider);
    final isFavorite = favoriteLinks.contains(article.link);

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
                IconButton(
                  icon: Icon(
                    isFavorite ? Icons.bookmark : Icons.bookmark_border,
                    color: isFavorite ? Theme.of(context).colorScheme.primary : Colors.grey,
                  ),
                  iconSize: 22,
                  onPressed: () => ref.read(favoritesProvider.notifier).toggleFavorite(article.link),
                ),
                IconButton(icon: const Icon(Icons.share, size: 20, color: Colors.grey), onPressed: () => Share.share('KI-News-Radar: ${article.title}\n${article.link}')),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
              child: Text(DateFormat('dd. MMMM yyyy', 'de_DE').format(article.published), style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ),
            Text(article.title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text(article.summaryAi, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).textTheme.bodyMedium?.color?.withAlpha(204))),
            if (article.topics.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12.0),
                child: Wrap(
                    spacing: 6.0,
                    runSpacing: 4.0,
                    children: article.topics.map((topic) => Chip(
                          label: Text(topic),
                          backgroundColor: Theme.of(context).colorScheme.surface,
                          side: BorderSide(color: Colors.grey.shade700),
                          labelStyle: const TextStyle(fontSize: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                        )).toList()),
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
                        final mediaItem = MediaItem(id: article.audioUrl, title: article.title, artist: article.source, artUri: Uri.parse("https://placehold.co/128x128/3B82F6/FFFFFF?text=KI"));
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

class CompactNewsCard extends ConsumerWidget {
  final NewsArticle article;
  const CompactNewsCard({super.key, required this.article});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favoriteLinks = ref.watch(favoritesProvider);
    final isFavorite = favoriteLinks.contains(article.link);
    final icon = article.type == 'podcast' ? Icons.mic_outlined : Icons.article_outlined;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(article.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(article.source),
        trailing: IconButton(
          icon: Icon(isFavorite ? Icons.bookmark : Icons.bookmark_border,
            color: isFavorite ? Theme.of(context).colorScheme.primary : Colors.grey,
          ),
          onPressed: () => ref.read(favoritesProvider.notifier).toggleFavorite(article.link),
        ),
        onTap: () async {
          if (article.type == 'podcast' && article.audioUrl.isNotEmpty) {
            final mediaItem = MediaItem(id: article.audioUrl, title: article.title, artist: article.source, artUri: Uri.parse("https://placehold.co/128x128/3B82F6/FFFFFF?text=KI"));
            audioHandler.playMediaItem(mediaItem);
          } else {
            final url = Uri.parse(article.link);
            if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.inAppWebView);
          }
        },
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
        border: Border(top: BorderSide(color: Colors.grey.shade800, width: 0.5)),
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
            currentAccountPicture: const CircleAvatar(
              backgroundColor: Colors.white,
              backgroundImage: NetworkImage("https://placehold.co/128x128/FFFFFF/3B82F6?text=S"),
            ),
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary),
          ),
          ListTile(
            leading: const Icon(Icons.bookmark_outline),
            title: const Text('Meine Leseliste'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (context) => const FavoritesPage()));
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.settings_outlined), 
            title: const Text('Einstellungen'), 
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsPage()));
            }
          ),
          ListTile(leading: const Icon(Icons.info_outline), title: const Text('Über die App'), onTap: () => Navigator.pop(context)),
        ],
      ),
    );
  }
}
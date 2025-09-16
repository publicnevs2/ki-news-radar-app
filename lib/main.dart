import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

// --- Datenmodell (unverändert) ---
class NewsArticle {
  final String source;
  final String title;
  final String link;
  final String summaryAi;

  NewsArticle({
    required this.source,
    required this.title,
    required this.link,
    required this.summaryAi,
  });

  factory NewsArticle.fromJson(Map<String, dynamic> json) {
    return NewsArticle(
      source: json['source'] ?? 'Unbekannte Quelle',
      title: json['title'] ?? 'Ohne Titel',
      link: json['link'] ?? '',
      summaryAi: json['summary_ai'] ?? 'Keine Zusammenfassung verfügbar.',
    );
  }
}

// --- Provider ---

// 1. Holt alle Nachrichten von GitHub
final newsProvider = FutureProvider<List<NewsArticle>>((ref) async {
  final url = Uri.parse('https://raw.githubusercontent.com/publicnevs2/ki-news-radar/main/data.json');
  final response = await http.get(url);

  if (response.statusCode == 200) {
    final List<dynamic> jsonData = json.decode(utf8.decode(response.bodyBytes));
    final articles = jsonData.map((item) => NewsArticle.fromJson(item)).toList();
    // Sortiere die Artikel, die neuesten zuerst (optional, falls data.json nicht sortiert ist)
    // articles.sort((a, b) => b.published.compareTo(a.published));
    return articles;
  } else {
    throw Exception('Fehler beim Laden der News: ${response.statusCode}');
  }
});

// 2. Speichert den aktuellen Suchbegriff
final searchQueryProvider = StateProvider<String>((ref) => '');

// 3. Filtert die Nachrichten basierend auf dem Suchbegriff
final filteredNewsProvider = Provider<List<NewsArticle>>((ref) {
  final searchQuery = ref.watch(searchQueryProvider).toLowerCase();
  final news = ref.watch(newsProvider).asData?.value ?? [];

  if (searchQuery.isEmpty) {
    return news;
  }

  return news.where((article) {
    return article.title.toLowerCase().contains(searchQuery) ||
        article.summaryAi.toLowerCase().contains(searchQuery) ||
        article.source.toLowerCase().contains(searchQuery);
  }).toList();
});


// --- Haupt-App (unverändert) ---
void main() {
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
          surface: Color(0xFF1E1E1E),
          onSurface: Color(0xFFE0E0E0),
        ),
        textTheme: GoogleFonts.manropeTextTheme(
          Theme.of(context).textTheme.apply(bodyColor: const Color(0xFFE0E0E0)),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E1E1E),
          elevation: 0,
        ),
      ),
      home: const MainScreen(),
    );
  }
}

// --- Haupt-Container mit Bottom Navigation ---
class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  int _selectedIndex = 0;

  static const List<Widget> _pages = <Widget>[
    NewsFeedPage(),
    RadarPage(),
    SearchPage(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('KI-News-Radar'),
        centerTitle: true,
      ),
      drawer: const AppDrawer(),
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.article_outlined),
            activeIcon: Icon(Icons.article),
            label: 'Heute',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.radar_outlined),
            activeIcon: Icon(Icons.radar),
            label: 'Radar',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.search),
            label: 'Suche',
          ),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Colors.grey,
        backgroundColor: const Color(0xFF1E1E1E),
      ),
    );
  }
}

// --- Seiten-Widgets ---

// Seite 1: Der "Heute"-Feed mit Pull-to-Refresh
class NewsFeedPage extends ConsumerWidget {
  const NewsFeedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final newsAsyncValue = ref.watch(newsProvider);
    return newsAsyncValue.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Fehler: $err')),
      data: (articles) {
        return RefreshIndicator(
          onRefresh: () async {
            HapticFeedback.mediumImpact();
            ref.invalidate(newsProvider);
            return await ref.read(newsProvider.future);
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(8.0),
            itemCount: articles.length,
            itemBuilder: (context, index) {
              final article = articles[index];
              return NewsCard(article: article);
            },
          ),
        );
      },
    );
  }
}

// Seite 2: Der "Radar" (aktuell ein Platzhalter)
class RadarPage extends StatelessWidget {
  const RadarPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Hier entsteht der interaktive Themen-Radar.',
        style: TextStyle(color: Colors.white70),
      ),
    );
  }
}

// Seite 3: Die Suche
class SearchPage extends ConsumerWidget {
  const SearchPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filteredArticles = ref.watch(filteredNewsProvider);

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          TextField(
            onChanged: (query) {
              ref.read(searchQueryProvider.notifier).state = query;
            },
            decoration: InputDecoration(
              labelText: 'Suchen...',
              suffixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.builder(
              itemCount: filteredArticles.length,
              itemBuilder: (context, index) {
                final article = filteredArticles[index];
                return NewsCard(article: article);
              },
            ),
          ),
        ],
      ),
    );
  }
}


// --- Wiederverwendbare Widgets (unverändert) ---

class NewsCard extends StatelessWidget {
  final NewsArticle article;
  const NewsCard({super.key, required this.article});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              article.source.toUpperCase(),
              style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary, letterSpacing: 0.5),
            ),
            const SizedBox(height: 8),
            Text(
              article.title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              article.summaryAi,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () async {
                   final url = Uri.parse(article.link);
                   if (await canLaunchUrl(url)) {
                     await launchUrl(url, mode: LaunchMode.inAppWebView);
                   }
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
              backgroundImage: AssetImage("assets/sven_profile.jpg"),
            ),
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Über die App'),
            onTap: () => Navigator.pop(context),
          ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Einstellungen'),
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }
}


import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF0EA5E9);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
        textTheme: GoogleFonts.manropeTextTheme(
          ThemeData(brightness: Brightness.dark).textTheme,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0x14FFFFFF),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: const WeatherPage(),
    );
  }
}

class WeatherPage extends StatefulWidget {
  const WeatherPage({super.key});

  @override
  State<WeatherPage> createState() => _WeatherPageState();
}

class _WeatherPageState extends State<WeatherPage> {
  late final String _apiKey = dotenv.env['OPEN_WEATHER_KEY'] ?? '';

  final TextEditingController cityController = TextEditingController();
  Map<String, dynamic>? _weatherData;
  bool _loading = false;
  String? _error;
  String? _lastQueryMode; // "city" or "location" to support refresh.

  @override
  void initState() {
    super.initState();
    if (_apiKey.isEmpty) {
      _error = 'Missing OPEN_WEATHER_KEY in .env';
    } else {
      _fetchByLocation();
    }
  }

  @override
  void dispose() {
    cityController.dispose();
    super.dispose();
  }

  Future<Position> getCurrentLocation() async {
    _requireApiKey();
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services are disabled. Please enable GPS.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw Exception('Location permission not granted');
    }

    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  Future<Map<String, dynamic>> getWeatherData(
      double lat, double lon) async {
    _requireApiKey();
    final url =
        'https://api.openweathermap.org/data/2.5/weather?lat=$lat&lon=$lon&appid=$_apiKey&units=metric';
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(
        'Failed to load weather data (${response.statusCode}): ${response.body}',
      );
    }
  }

  Future<Map<String, dynamic>> getWeatherByCity(String city) async {
    _requireApiKey();
    final url =
        'https://api.openweathermap.org/data/2.5/weather?q=$city&appid=$_apiKey&units=metric';
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    } else {
      throw Exception(
        'Failed to load weather data (${response.statusCode}): ${response.body}',
      );
    }
  }

  Future<void> _fetchByLocation() async {
    setState(() {
      _loading = true;
      _error = null;
      _lastQueryMode = 'location';
    });

    try {
      final position = await getCurrentLocation();
      final data = await getWeatherData(position.latitude, position.longitude);
      setState(() {
        _weatherData = data;
      });
      // Quick console check.
      // ignore: avoid_print
      print('Weather by location: $data');
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _fetchByCity() async {
    final city = cityController.text.trim();
    if (city.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
      _lastQueryMode = 'city';
    });

    try {
      final data = await getWeatherByCity(city);
      setState(() {
        _weatherData = data;
      });
      // ignore: avoid_print
      print('Weather for $city: $data');
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _refresh() async {
    if (_lastQueryMode == 'city') {
      await _fetchByCity();
    } else {
      await _fetchByLocation();
    }
  }

  void _requireApiKey() {
    if (_apiKey.isEmpty) {
      throw Exception('Missing OPEN_WEATHER_KEY in .env');
    }
  }

  String _buildWeatherMessage(
    dynamic tempCelsius,
    String weatherMain,
    String description,
  ) {
    final temp = tempCelsius is num ? tempCelsius.toDouble() : null;
    final main = weatherMain.toLowerCase();
    final desc = description.toLowerCase();
    final summary = '$main $desc';

    if (summary.contains('thunder')) {
      return 'Stormy skies today—best to stay indoors and stay safe.';
    }
    if (summary.contains('rain') || summary.contains('drizzle')) {
      return 'Rainy vibes—grab an umbrella and enjoy something cozy.';
    }
    if (summary.contains('snow')) {
      return 'Snow is falling—bundle up and take it slow out there.';
    }
    if (summary.contains('clear') || (temp != null && temp >= 22 && temp <= 32)) {
      return 'The weather is nice today! Let’s go for a walk or enjoy something while the sun is out.';
    }
    if (summary.contains('cloud')) {
      return 'Cloudy but calm—perfect for a coffee run or a relaxed stroll.';
    }
    if (temp != null && temp > 32) {
      return 'It’s pretty hot—stay hydrated and find some shade.';
    }
    if (temp != null && temp < 12) {
      return 'Chilly weather—layer up and keep warm if you head out.';
    }

    return 'Check the sky and enjoy your day—conditions look steady.';
  }

  @override
  Widget build(BuildContext context) {
    final tempCelsius = _weatherData?['main']?['temp'];
    final weather = _weatherData?['weather'];
    final description = weather is List && weather.isNotEmpty
        ? (weather.first['description'] as String?) ?? ''
        : '';
    final weatherMain = weather is List && weather.isNotEmpty
        ? (weather.first['main'] as String?) ?? ''
        : '';
    final iconCode = weather is List && weather.isNotEmpty
        ? (weather.first['icon'] as String?)
        : null;
    final feelsLike = _weatherData?['main']?['feels_like'];
    final humidity = _weatherData?['main']?['humidity'];
    final wind = _weatherData?['wind']?['speed'];

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF0B1224),
            Color(0xFF10243E),
            Color(0xFF0A4A68),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: const Text('Weather'),
          actions: [
            IconButton(
              onPressed: _loading ? null : _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Find today’s forecast',
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Search any city or use your current spot.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white70,
                      ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: cityController,
                  decoration: InputDecoration(
                    labelText: 'City',
                    hintText: 'e.g., Manila',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: _loading ? null : _fetchByCity,
                    ),
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _fetchByCity(),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _loading ? null : _fetchByCity,
                        icon: const Icon(Icons.location_city),
                        label: const Text('Search City'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _loading ? null : _fetchByLocation,
                        icon: const Icon(Icons.my_location),
                        label: const Text('Use Location'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Color(0x66FFFFFF)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _buildContent(
                    context,
                    tempCelsius,
                    description,
                    weatherMain,
                    iconCode,
                    feelsLike,
                    humidity,
                    wind,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    dynamic tempCelsius,
    String description,
    String weatherMain,
    String? iconCode,
    dynamic feelsLike,
    dynamic humidity,
    dynamic wind,
  ) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.only(top: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 24),
        child: _InfoCard(
          child: Text(
            _error!,
            style: const TextStyle(color: Colors.redAccent),
          ),
        ),
      );
    }

    if (_weatherData != null) {
      return _InfoCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _weatherData?['name']?.toString() ?? 'Unknown',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        description.isNotEmpty
                            ? description
                            : 'No description',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: Colors.white70),
                      ),
                      const SizedBox(height: 16),
                      if (tempCelsius != null)
                        Text(
                          '${tempCelsius.round()}°',
                          style: Theme.of(context)
                              .textTheme
                              .displayLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      if (feelsLike != null)
                        Text(
                          'Feels like ${feelsLike.round()}°C',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: Colors.white70),
                        ),
                    ],
                  ),
                ),
                if (iconCode != null)
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0x14FFFFFF),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Image.network(
                      'https://openweathermap.org/img/wn/$iconCode@2x.png',
                      width: 90,
                      height: 90,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.cloud,
                        size: 64,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _StatTile(
                  label: 'Humidity',
                  value: humidity != null ? '$humidity%' : '—',
                  icon: Icons.water_drop,
                ),
                _StatTile(
                  label: 'Wind',
                  value: wind != null ? '$wind m/s' : '—',
                  icon: Icons.air,
                ),
                _StatTile(
                  label: 'Mode',
                  value: _lastQueryMode == 'city' ? 'City' : 'Location',
                  icon: Icons.public,
                ),
              ],
            ),
            const SizedBox(height: 20),
            _MoodTile(
              message: _buildWeatherMessage(
                tempCelsius,
                weatherMain,
                description,
              ),
            ),
          ],
        ),
      );
    }

    return const _InfoCard(
      child: Text('Enter a city or use your location to get weather.'),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x14FFFFFF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x80000000),
            blurRadius: 16,
            offset: Offset(0, 8),
          )
        ],
      ),
      child: child,
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: Colors.white70),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.white70),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _MoodTile extends StatelessWidget {
  const _MoodTile({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [
            Color(0x3326C6DA),
            Color(0x331C8FE6),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: const Color(0x3326C6DA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.emoji_emotions, color: Colors.amber, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:audioplayers/audioplayers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const VinylVisionApp());
}

class VinylVisionApp extends StatelessWidget {
  const VinylVisionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vinyl Vision',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MainMapScreen(),
    );
  }
}

class MainMapScreen extends StatefulWidget {
  const MainMapScreen({super.key});

  @override
  State<MainMapScreen> createState() => _MainMapScreenState();
}

class _MainMapScreenState extends State<MainMapScreen> {
  late GoogleMapController mapController;
  final LatLng _initialPosition = const LatLng(36.0735, -79.7923);
  final Set<Marker> _markers = {};
  Position? _currentPosition;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  String? _currentSong;

  // List of vinyl record locations and their songs
  final List<VinylLocation> _vinylLocations = [
    VinylLocation(
      id: '1',
      position: const LatLng(36.0735, -79.7923),
      title: 'Billie Jean',
      artist: 'Michael Jackson',
      audioUrl: 'https://example.com/billie_jean.mp3', // Replace with actual URL
    ),
    VinylLocation(
      id: '2',
      position: const LatLng(36.0720, -79.7915),
      title: 'Jump',
      artist: 'Van Halen',
      audioUrl: 'https://example.com/jump.mp3', // Replace with actual URL
    ),
    VinylLocation(
      id: '3',
      position: const LatLng(36.0710, -79.7900),
      title: 'Africa',
      artist: 'Toto',
      audioUrl: 'https://example.com/africa.mp3', // Replace with actual URL
    ),
    VinylLocation(
      id: '4',
      position: const LatLng(36.0740, -79.7930),
      title: 'Like a Prayer',
      artist: 'Madonna',
      audioUrl: 'https://example.com/like_a_prayer.mp3', // Replace with actual URL
    ),
    VinylLocation(
      id: '5',
      position: const LatLng(36.0700, -79.7940),
      title: 'Don\'t You Forget About Me',
      artist: 'Simple Minds',
      audioUrl: 'https://example.com/dont_forget.mp3', // Replace with actual URL
    ),
  ];

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
    _loadVinylLocations();
    _initAudio();
    // Start checking location periodically
    _startLocationChecking();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _initAudio() async {
    await _audioPlayer.setReleaseMode(ReleaseMode.stop);
    _audioPlayer.onPlayerComplete.listen((event) {
      setState(() {
        _isPlaying = false;
        _currentSong = null;
      });
    });
  }

  Future<void> _getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    Position position = await Geolocator.getCurrentPosition();
    setState(() {
      _currentPosition = position;
      if (mapController != null) {
        mapController.animateCamera(CameraUpdate.newLatLng(
          LatLng(position.latitude, position.longitude),
        ));
      }
    });
  }

  Future<void> _loadVinylLocations() async {
    for (final location in _vinylLocations) {
      final marker = Marker(
        markerId: MarkerId(location.id),
        position: location.position,
        infoWindow: InfoWindow(title: '${location.title} - ${location.artist}'),
        icon: await _createCustomMarker(location.title),
      );
      _markers.add(marker);
    }
    setState(() {});
  }

  Future<BitmapDescriptor> _createCustomMarker(String title) async {
    return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet);
  }

  Future<void> _startLocationChecking() async {
    const checkInterval = Duration(seconds: 10); // Check every 10 seconds
    const proximityThreshold = 50.0; // 50 meters

    while (true) {
      await Future.delayed(checkInterval);
      
      if (_currentPosition == null) continue;
      
      for (final location in _vinylLocations) {
        final distance = Geolocator.distanceBetween(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          location.position.latitude,
          location.position.longitude,
        );
        
        if (distance <= proximityThreshold && _currentSong != location.title) {
          // We're near a vinyl location and it's not the current song
          await _playSong(location);
          break; // Only play one song at a time
        }
      }
    }
  }

  Future<void> _playSong(VinylLocation location) async {
    if (_isPlaying) {
      await _audioPlayer.stop();
    }
    
    try {
      await _audioPlayer.play(UrlSource(location.audioUrl));
      setState(() {
        _isPlaying = true;
        _currentSong = location.title;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Now playing: ${location.title} - ${location.artist}'),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to play song: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vinyl Vision'),
        actions: [
          if (_isPlaying)
            IconButton(
              icon: const Icon(Icons.stop),
              onPressed: () async {
                await _audioPlayer.stop();
                setState(() {
                  _isPlaying = false;
                  _currentSong = null;
                });
              },
            ),
        ],
      ),
      body: GoogleMap(
        onMapCreated: (controller) => mapController = controller,
        initialCameraPosition: CameraPosition(
          target: _initialPosition,
          zoom: 15,
        ),
        markers: _markers,
        myLocationEnabled: true,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _getCurrentLocation,
        child: const Icon(Icons.my_location),
      ),
    );
  }
}

class VinylLocation {
  final String id;
  final LatLng position;
  final String title;
  final String artist;
  final String audioUrl;

  VinylLocation({
    required this.id,
    required this.position,
    required this.title,
    required this.artist,
    required this.audioUrl,
  });
}
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:vector_math/vector_math_64.dart' as vector;
import 'package:just_audio/just_audio.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_web_auth/flutter_web_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:ar_flutter_plugin/ar_flutter_plugin.dart';
import 'package:ar_flutter_plugin/datatypes/anchor_types.dart';
import 'package:ar_flutter_plugin/datatypes/config_planedetection.dart';
import 'package:ar_flutter_plugin/datatypes/hittest_result_types.dart';
import 'package:ar_flutter_plugin/datatypes/node_types.dart';
import 'package:ar_flutter_plugin/managers/ar_anchor_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_location_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_object_manager.dart';
import 'package:ar_flutter_plugin/managers/ar_session_manager.dart';
import 'package:ar_flutter_plugin/models/ar_anchor.dart';
import 'package:ar_flutter_plugin/models/ar_hittest_result.dart';
import 'package:ar_flutter_plugin/models/ar_node.dart';
import 'package:ar_flutter_plugin/widgets/ar_view.dart';

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
  bool _arAvailable = false;
  String? _spotifyAccessToken;
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _checkARAvailability();
    _getCurrentLocation();
    _loadVirtualRecords();
    _initAudio();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _initAudio() async {
    await _audioPlayer.setReleaseMode(ReleaseMode.stop);
  }

  Future<void> _checkARAvailability() async {
    // AR Flutter Plugin doesn't have a direct availability check
    // You might want to implement platform-specific checks here
    setState(() => _arAvailable = true);
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
      mapController.animateCamera(CameraUpdate.newLatLng(
        LatLng(position.latitude, position.longitude),
      ));
    });
  }

  Future<void> _loadVirtualRecords() async {
    final records = [
      VirtualRecord(
        id: '1',
        position: const LatLng(36.0735, -79.7923),
        title: 'Blinding Lights',
        artist: 'The Weeknd',
        spotifyUri: 'spotify:track:0VjIjW4GlUZAMYd2vXMi3b',
        imageUrl: 'https://i.scdn.co/image/ab67616d00001e02a935e8e2a8d5a5b8a7c6a6e5',
      ),
      VirtualRecord(
        id: '2',
        position: const LatLng(36.0720, -79.7915),
        title: 'Levitating',
        artist: 'Dua Lipa',
        spotifyUri: 'spotify:track:39LLxExYz6ewLAcYrzQQyP',
        imageUrl: 'https://i.scdn.co/image/ab67616d00001e02a5d5a5b8a7c6a6e5a935e8e2',
      ),
    ];

    for (final record in records) {
      final marker = Marker(
        markerId: MarkerId(record.id),
        position: record.position,
        infoWindow: InfoWindow(title: '${record.title} - ${record.artist}'),
        icon: await _createCustomMarker(record.title, record.imageUrl),
      );
      _markers.add(marker);
    }
    setState(() {});
  }

  Future<BitmapDescriptor> _createCustomMarker(String title, String imageUrl) async {
    return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet);
  }

  Future<void> _authenticateSpotify() async {
    const clientId = 'YOUR_SPOTIFY_CLIENT_ID';
    const redirectUri = 'YOUR_REDIRECT_URI';
    const scope = 'user-read-playback-state user-modify-playback-state';

    final url = Uri.parse(
      'https://accounts.spotify.com/authorize?response_type=token'
      '&client_id=$clientId'
      '&redirect_uri=${Uri.encodeComponent(redirectUri)}'
      '&scope=${Uri.encodeComponent(scope)}'
    );

    try {
      final result = await FlutterWebAuth.authenticate(
        url: url.toString(),
        callbackUrlScheme: redirectUri.split(':')[0],
      );

      final token = Uri.parse(result).fragment
          .split('&')
          .firstWhere((e) => e.startsWith('access_token='))
          .split('=')[1];

      setState(() => _spotifyAccessToken = token);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Spotify auth failed: $e')),
      );
    }
  }

  Future<void> _playSpotifyTrack(String trackUri) async {
    if (_spotifyAccessToken == null) {
      await _authenticateSpotify();
      if (_spotifyAccessToken == null) return;
    }

    try {
      final response = await http.post(
        Uri.parse('https://api.spotify.com/v1/me/player/play'),
        headers: {
          'Authorization': 'Bearer $_spotifyAccessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'uris': [trackUri],
        }),
      );

      if (response.statusCode != 204) {
        throw Exception('Failed to play track');
      }
    } catch (e) {
      await _playLocalPreview(trackUri);
    }
  }

  Future<void> _playLocalPreview(String trackUri) async {
    final previewUrls = {
      'spotify:track:0VjIjW4GlUZAMYd2vXMi3b': 'https://p.scdn.co/mp3-preview/...',
      'spotify:track:39LLxExYz6ewLAcYrzQQyP': 'https://p.scdn.co/mp3-preview/...',
    };

    if (previewUrls.containsKey(trackUri)) {
      await _audioPlayer.play(UrlSource(previewUrls[trackUri]!));
    }
  }

  void _launchARView() {
    if (_spotifyAccessToken == null) {
      _authenticateSpotify();
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ARViewScreen(
          userLocation: _currentPosition != null
              ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
              : _initialPosition,
          records: _markers.map((m) => VirtualRecord(
            id: m.markerId.value,
            position: m.position,
            title: m.infoWindow.title?.split(' - ')[0] ?? 'Unknown',
            artist: m.infoWindow.title?.split(' - ')[1] ?? 'Artist',
            spotifyUri: _getSpotifyUriForMarker(m.markerId.value),
            imageUrl: '',
          )).toList(),
          onRecordCollected: _playSpotifyTrack,
        ),
      ),
    );
  }

  String _getSpotifyUriForMarker(String markerId) {
    return {
      '1': 'spotify:track:0VjIjW4GlUZAMYd2vXMi3b',
      '2': 'spotify:track:39LLxExYz6ewLAcYrzQQyP',
    }[markerId] ?? 'spotify:track:0VjIjW4GlUZAMYd2vXMi3b';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vinyl Vision'),
        actions: [
          IconButton(
            icon: Icon(_spotifyAccessToken != null 
                ? Icons.music_note 
                : Icons.music_off),
            onPressed: _authenticateSpotify,
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
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (_arAvailable)
            FloatingActionButton(
              heroTag: 'ar_button',
              onPressed: _launchARView,
              child: const Icon(Icons.view_in_ar),
            ),
          const SizedBox(height: 16),
          FloatingActionButton(
            heroTag: 'location_button',
            onPressed: _getCurrentLocation,
            child: const Icon(Icons.my_location),
          ),
        ],
      ),
    );
  }
}

class VirtualRecord {
  final String id;
  final LatLng position;
  final String title;
  final String artist;
  final String spotifyUri;
  final String imageUrl;

  VirtualRecord({
    required this.id,
    required this.position,
    required this.title,
    required this.artist,
    required this.spotifyUri,
    required this.imageUrl,
  });
}

class ARViewScreen extends StatefulWidget {
  final LatLng userLocation;
  final List<VirtualRecord> records;
  final Function(String) onRecordCollected;

  const ARViewScreen({
    super.key,
    required this.userLocation,
    required this.records,
    required this.onRecordCollected,
  });

  @override
  State<ARViewScreen> createState() => _ARViewScreenState();
}

class _ARViewScreenState extends State<ARViewScreen> {
  late ARSessionManager arSessionManager;
  late ARObjectManager arObjectManager;
  final Set<String> _collectedRecords = {};

  @override
  void dispose() {
    arSessionManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Collect Vinyl Records')),
      body: ARView(
        onARViewCreated: _onARViewCreated,
        planeDetectionConfig: PlaneDetectionConfig.horizontalAndVertical,
      ),
    );
  }

  void _onARViewCreated(ARSessionManager sessionManager, ARObjectManager objectManager) {
    arSessionManager = sessionManager;
    arObjectManager = objectManager;

    arSessionManager.onInitialize(
      showFeaturePoints: false,
      showPlanes: true,
      showWorldOrigin: true,
      customPlaneTexturePath: "assets/triangle.png",
    );

    _placeRecords();
  }

  Future<void> _placeRecords() async {
    for (final record in widget.records) {
      final dx = record.position.latitude - widget.userLocation.latitude;
      final dz = record.position.longitude - widget.userLocation.longitude;

      // First hit test to find a plane
      final hitTestResults = await arSessionManager.performHitTest(
        vector.Vector3(dx * 1000, 0, dz * 1000),
        HitTestResultType.horizontalPlane,
      );

      if (hitTestResults.isNotEmpty) {
        final hit = hitTestResults.first;
        
        // Create an anchor at the hit location
        final anchor = ARPlaneAnchor(
          transformation: hit.worldTransform,
        );
        await arSessionManager.addAnchor(anchor);

        // Create a node attached to the anchor
        final node = ARNode(
          type: NodeType.local,
          uri: "assets/models/vinyl_record.sfb",
          scale: vector.Vector3(0.5, 0.5, 0.5),
          position: vector.Vector3(0, 0, 0),
          rotation: vector.Vector4(0, 0, 0, 0),
        );
        
        await arObjectManager.addNode(node, planeAnchor: anchor);
        arObjectManager.onNodeTap = (nodes) => _onNodeTap(nodes);
      }
    }
  }

  void _onNodeTap(List<String> nodeNames) {
    for (final nodeName in nodeNames) {
      if (!_collectedRecords.contains(nodeName)) {
        _collectedRecords.add(nodeName);
        final record = widget.records.firstWhere((r) => r.id == nodeName);
        widget.onRecordCollected(record.spotifyUri);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Collected: ${record.title} by ${record.artist}')),
        );
        
        // Remove the node
        arObjectManager.removeNode(nodeName);
      }
    }
  }
}
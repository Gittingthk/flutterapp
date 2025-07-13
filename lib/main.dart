// ──────────────────────────────────────────────────────────────
// Flutter 앱: Pet Feeder PRO v0.2
//   • Firebase Realtime Database 연동 (commands / device_status / diagnosis_log)
//   • 수동 급여(그램 입력) & 진단 버튼
//   • 상태 · 진단 결과 · 이미지 실시간 표시
// ──────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '스마트 펫 피더',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  // ─ Stream 구독 관리 ─
  late StreamSubscription<DatabaseEvent> _diagSub;
  late StreamSubscription<DatabaseEvent> _statusSub;

  // ─ UI 상태 변수 ─
  String _diagResult = '진단 대기 중…';
  String? _imageUrl;
  bool _isOnline = false;
  String _lastSeen = '-';
  String _currentState = '-';

  // 급여량 입력용 컨트롤러
  final TextEditingController _amountCtrl = TextEditingController(text: '50');

  @override
  void initState() {
    super.initState();
    _activateListeners();
  }

  void _activateListeners() {
    // ─ diagnosis_log/last_result 스트림 ─
    _diagSub = _db.child('diagnosis_log/last_result').onValue.listen((e) {
      final m = e.snapshot.value as Map?;
      if (m == null) return;
      setState(() {
        final res = m['result'];
        _diagResult = res is List ? res.join(', ') : res?.toString() ?? '결과 없음';
        _imageUrl = m['image_url'];
      });
    });

    // ─ device_status 스트림 ─
    _statusSub = _db.child('device_status').onValue.listen((e) {
      final m = e.snapshot.value as Map?;
      if (m == null) return;
      setState(() {
        _isOnline = m['is_online'] == true;
        _lastSeen = m['last_seen'] ?? '-';
        _currentState = m['current_state'] ?? '-';
      });
    });
  }

  // ─ 사료 급여 명령 ─
  Future<void> _feedPet() async {
    final grams = int.tryParse(_amountCtrl.text) ?? 0;
    if (grams <= 0) {
      _snack('급여량을 올바르게 입력하세요.');
      return;
    }

    final reqId = DateTime.now().millisecondsSinceEpoch.toString();
    final payload = {
      'request_id': reqId,
      'amount_g': grams,
      'issued_at': DateTime.now().toUtc().toIso8601String(),
    };

    try {
      await _db.child('commands/feed').set(payload);
      _snack('사료 $grams g 배급 명령 전송!');
    } catch (e) {
      _snack('사료 명령 실패: $e');
    }
  }

  // ─ 진단 명령 ─
  Future<void> _diagnosePet() async {
    try {
      await _db.child('commands').update({'diagnose': 'REQUEST'});
      _snack('진단 명령 전송!');
    } catch (e) {
      _snack('진단 명령 실패: $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('스마트 펫 피더 (${_isOnline ? '온라인' : '오프라인'})'),
        backgroundColor: _isOnline ? Colors.teal : Colors.grey,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ─ 장치 상태 ─
            Card(
              child: ListTile(
                leading: Icon(_isOnline ? Icons.wifi : Icons.wifi_off,
                    color: _isOnline ? Colors.green : Colors.red),
                title: Text('상태: $_currentState'),
                subtitle: Text('최근 확인: $_lastSeen'),
              ),
            ),
            const SizedBox(height: 24),

            // ─ 급여 입력 + 버튼 ─
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _amountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '급여량 (g)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _feedPet,
                icon: const Icon(Icons.fastfood),
                label: const Text('급여'),
                style:
                ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
              ),
            ]),
            const SizedBox(height: 24),

            // ─ 진단 버튼 ─
            ElevatedButton.icon(
              onPressed: _diagnosePet,
              icon: const Icon(Icons.medical_information),
              label: const Text('진단 요청'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 32),

            // ─ 진단 결과 ─
            const Text('최근 진단 결과',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(_diagResult,
                style: const TextStyle(fontSize: 16), textAlign: TextAlign.center),
            const SizedBox(height: 16),

            // ─ 이미지 ─
            Container(
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: _imageUrl == null
                    ? const Text('촬영된 이미지 없음')
                    : Image.network(
                  _imageUrl!,
                  fit: BoxFit.cover,
                  loadingBuilder: (ctx, child, prog) =>
                  prog == null ? child : const CircularProgressIndicator(),
                  errorBuilder: (ctx, err, st) =>
                  const Text('이미지 로드 실패'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _diagSub.cancel();
    _statusSub.cancel();
    _amountCtrl.dispose();
    super.dispose();
  }
}

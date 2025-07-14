// Smart Pet Feeder v0.6
//
// Home · History · Settings 탭 + 자동급여(시간·g·요일) + CSV 내보내기 + 캘리브레이션
// ▸ Firebase Realtime Database 구조
//   - commands/feed, commands/diagnose
//   - device_status, diagnosis_log
//   - feeding_log
//   - auto_schedule/{enabled,breakfast,lunch,dinner,breakfast_g,lunch_g,dinner_g,days}
// ▸ FCM 토큰은 users/default/fcm_token 에 저장하여 푸시 알림용으로 사용
// ---------------------------------------------------------------------------
import 'dart:async';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'firebase_options.dart';

/* ───────────────  App Entry  ─────────────── */
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // FCM 토큰 저장
  final token = await FirebaseMessaging.instance.getToken();
  if (token != null) {
    FirebaseDatabase.instance
        .ref('users/default/fcm_token')
        .set(token)
        .catchError((_) {});
  }
  runApp(const MyApp());
}

/* ───────────────  Root with NavBar  ─────────────── */
class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  int _index = 0;
  final _pages = const [HomePage(), HistoryPage(), SettingsPage()];

  @override
  Widget build(BuildContext context) {
    final seed = Colors.teal;
    return MaterialApp(
      title: 'Smart Pet Feeder',
      themeMode: ThemeMode.system,
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true),
      darkTheme:
      ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark, useMaterial3: true),
      home: Scaffold(
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _pages[_index],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.list), label: 'History'),
            NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
          ],
          onDestinationSelected: (i) => setState(() => _index = i),
        ),
      ),
    );
  }
}

/* ─────────────────────────────── ① Home ─────────────────────────────── */
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomeState();
}

class _HomeState extends State<HomePage> {
  final db = FirebaseDatabase.instance.ref();
  late final StreamSubscription _diagSub, _statusSub;

  // 상태 변수
  String _diag = '진단 대기 중…';
  String? _imgUrl;
  bool _online = false;
  String _lastSeen = '-', _state = '-';

  final _gCtrl = TextEditingController(text: '50');

  @override
  void initState() {
    super.initState();
    _diagSub = db.child('diagnosis_log/last_result').onValue.listen((e) {
      final m = e.snapshot.value as Map?;
      if (m == null) return;
      setState(() {
        _diag =
        m['result'] is List ? (m['result'] as List).join(', ') : (m['result']?.toString() ?? '결과 없음');
        _imgUrl = m['image_url'];
      });
    });

    _statusSub = db.child('device_status').onValue.listen((e) {
      final m = e.snapshot.value as Map?;
      if (m == null) return;
      setState(() {
        _online = m['is_online'] == true;
        _lastSeen = m['last_seen'] ?? '-';
        _state = m['current_state'] ?? '-';
      });
    });
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _feed() async {
    final g = int.tryParse(_gCtrl.text) ?? 0;
    if (g <= 0) return _snack('급여량을 입력하세요');
    await db.child('commands/feed').set({
      'request_id': '${DateTime.now().millisecondsSinceEpoch}',
      'amount_g': g,
      'issued_at': DateTime.now().toUtc().toIso8601String()
    });
    _snack('$g g 급여 명령 전송');
  }

  Future<void> _diagnose() async {
    await db.child('commands').update({'diagnose': 'REQUEST'});
    _snack('진단 명령 전송');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Pet Feeder'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16, top: 8),
            child: Chip(
              label: Text(_online ? '온라인' : '오프라인',
                  style: const TextStyle(color: Colors.white)),
              backgroundColor: _online ? Colors.green : Colors.red,
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('사료 급여',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                TextField(
                  controller: _gCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: '급여량(g)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: _feed,
                  icon: const Icon(Icons.fastfood),
                  label: const Text('급여'),
                )
              ],
            ),
          ),
          const SizedBox(height: 24),
          _card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('눈 질환 진단',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _diagnose,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('사진 찍고 진단'),
                  style: FilledButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _card(
            Column(
              children: [
                const Text('최근 진단 결과',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(_diag, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _imgUrl == null
                      ? Container(
                    height: 160,
                    color: cs.surfaceVariant,
                    alignment: Alignment.center,
                    child: const Text('촬영된 이미지 없음'),
                  )
                      : Image.network(_imgUrl!, height: 160, fit: BoxFit.cover),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(Widget child) =>
      Card(child: Padding(padding: const EdgeInsets.all(16), child: child));

  @override
  void dispose() {
    _diagSub.cancel();
    _statusSub.cancel();
    _gCtrl.dispose();
    super.dispose();
  }
}

/* ─────────────────────────────── ② History ─────────────────────────────── */
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseDatabase.instance.ref('feeding_log');
    return Scaffold(
      appBar: AppBar(
        title: const Text('급여 기록'),
        actions: [
          PopupMenuButton(
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'csv', child: Text('CSV 내보내기')),
            ],
            onSelected: (v) {
              if (v == 'csv') _exportCsv(context);
            },
          )
        ],
      ),
      body: StreamBuilder(
        stream: ref.orderByChild('timestamp').onValue,
        builder: (ctx, AsyncSnapshot<DatabaseEvent> snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final map = snap.data?.snapshot.value as Map? ?? {};
          final list = map.entries.toList()
            ..sort((a, b) =>
                (b.value['timestamp'] ?? '').compareTo(a.value['timestamp']));
          if (list.isEmpty) {
            return const Center(child: Text('기록 없음'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (ctx, i) {
              final m = list[i].value as Map;
              return ListTile(
                leading: const Icon(Icons.fastfood),
                title: Text('${m['amount_g']} g'),
                subtitle: Text(m['timestamp'] ?? ''),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _exportCsv(BuildContext context) async {
    final snap = await FirebaseDatabase.instance.ref('feeding_log').get();
    final rows = <List<String>>[
      ['id', 'grams', 'timestamp']
    ];
    (snap.value as Map?)?.forEach((k, v) {
      final m = v as Map;
      rows.add([k, '${m['amount_g']}', m['timestamp'] ?? '']);
    });
    final csvData = const ListToCsvConverter().convert(rows);
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/feeding_log.csv');
    await file.writeAsString(csvData);
    if (context.mounted) {
      await Share.shareXFiles([XFile(file.path)], text: 'Feeding log');
    }
  }
}

/* ───────────────────────────── ③ Settings ───────────────────────────── */
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsState();
}

class _SettingsState extends State<SettingsPage> {
  final ref = FirebaseDatabase.instance.ref('auto_schedule');
  bool _enabled = false;
  TimeOfDay _bf = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _lunch = const TimeOfDay(hour: 12, minute: 0);
  TimeOfDay _dinner = const TimeOfDay(hour: 18, minute: 0);
  int _bfG = 40, _lG = 50, _dG = 45;
  final _days = <String, bool>{
    'Mon': true,
    'Tue': true,
    'Wed': true,
    'Thu': true,
    'Fri': true,
    'Sat': true,
    'Sun': true
  };
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _sub = ref.onValue.listen((e) {
      final m = e.snapshot.value as Map? ?? {};
      setState(() {
        _enabled = m['enabled'] == true;
        _bf = _parseTime(m['breakfast']) ?? _bf;
        _lunch = _parseTime(m['lunch']) ?? _lunch;
        _dinner = _parseTime(m['dinner']) ?? _dinner;
        _bfG = m['breakfast_g'] ?? _bfG;
        _lG = m['lunch_g'] ?? _lG;
        _dG = m['dinner_g'] ?? _dG;
        (m['days'] as Map?)?.forEach((k, v) => _days[k] = v == true);
      });
    });
  }

  static TimeOfDay? _parseTime(Object? s) {
    if (s is String && RegExp(r'^\d{2}:\d{2}$').hasMatch(s)) {
      final h = int.parse(s.substring(0, 2));
      final m = int.parse(s.substring(3, 5));
      return TimeOfDay(hour: h, minute: m);
    }
    return null;
  }

  static String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _save() => ref.set({
    'enabled': _enabled,
    'breakfast': _fmt(_bf),
    'lunch': _fmt(_lunch),
    'dinner': _fmt(_dinner),
    'breakfast_g': _bfG,
    'lunch_g': _lG,
    'dinner_g': _dG,
    'days': _days,
  });

  Future<void> _pickTime(TimeOfDay init, ValueChanged<TimeOfDay> set) async {
    final picked =
    await showTimePicker(context: context, initialTime: init);
    if (picked != null) {
      set(picked);
      _save();
    }
  }

  Future<void> _pickGram(int init, ValueChanged<int> set) async {
    final ctrl = TextEditingController(text: '$init');
    final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('급여량(g)'),
          content: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('취소')),
            TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('확인')),
          ],
        ));
    if (ok == true) {
      final g = int.tryParse(ctrl.text);
      if (g != null && g > 0) {
        set(g);
        _save();
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('설정'),
      actions: [
        IconButton(
            tooltip: '캘리브레이션', icon: const Icon(Icons.build),
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const CalibrationPage()))),
      ],
    ),
    body: ListView(
      children: [
        SwitchListTile(
          title: const Text('자동 급여 활성화'),
          value: _enabled,
          onChanged: (v) {
            setState(() => _enabled = v);
            _save();
          },
        ),
        const Divider(),
        _timeRow('아침', _bf, _bfG, (t) => setState(() => _bf = t),
                (g) => setState(() => _bfG = g)),
        _timeRow('점심', _lunch, _lG, (t) => setState(() => _lunch = t),
                (g) => setState(() => _lG = g)),
        _timeRow('저녁', _dinner, _dG, (t) => setState(() => _dinner = t),
                (g) => setState(() => _dG = g)),
        const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: const Text('요일별 자동 급여',
              style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        Wrap(
          alignment: WrapAlignment.center,
          children: _days.entries
              .map((e) => FilterChip(
            label: Text(e.key),
            selected: e.value,
            onSelected: (v) {
              setState(() => _days[e.key] = v);
              _save();
            },
          ))
              .toList(),
        ),
      ],
    ),
  );

  ListTile _timeRow(
      String name,
      TimeOfDay time,
      int grams,
      ValueChanged<TimeOfDay> setTime,
      ValueChanged<int> setGram) =>
      ListTile(
        leading: const Icon(Icons.schedule),
        title: Text(name),
        subtitle: Text('${_fmt(time)}  •  $grams g'),
        trailing: const Icon(Icons.edit),
        enabled: _enabled,
        onTap: () async {
          await _pickTime(time, setTime);
          await _pickGram(grams, setGram);
        },
      );

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

/* ─────────────── Calibration Page (스텝당 g 보정) ─────────────── */
class CalibrationPage extends StatefulWidget {
  const CalibrationPage({super.key});
  @override
  State<CalibrationPage> createState() => _CalState();
}

class _CalState extends State<CalibrationPage> {
  int _stage = 0; // 0 설명 → 1 실제 측정 입력 → 2 완료
  final _ctrl = TextEditingController();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('모터 캘리브레이션')),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: _stage == 0
          ? Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
              '1. 빈 상태에서 “10 g 배급” 버튼을 누르세요.\n'
                  '2. 실제 저울에 나온 g 값을 입력하면 자동 계산됩니다.',
              style: TextStyle(fontSize: 16)),
          const Spacer(),
          FilledButton(
              onPressed: () {
                FirebaseDatabase.instance
                    .ref('commands/calibrate')
                    .set('FEED10');
                setState(() => _stage = 1);
              },
              child: const Text('10 g 배급')),
        ],
      )
          : _stage == 1
          ? Column(
        children: [
          TextField(
            controller: _ctrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: '실제 측정된 g',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 24),
          FilledButton(
              onPressed: _submit, child: const Text('적용')),
        ],
      )
          : Center(
        child: Icon(Icons.check_circle,
            color: Colors.green, size: 96),
      ),
    ),
  );

  Future<void> _submit() async {
    final g = double.tryParse(_ctrl.text);
    if (g == null || g <= 0) return;
    await FirebaseDatabase.instance
        .ref('calibration/grams_per_rev')
        .set(g / 10.0);
    setState(() => _stage = 2);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) Navigator.pop(context);
  }
}

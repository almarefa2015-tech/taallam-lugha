import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:url_launcher/url_launcher.dart';

const String kAppName = 'تعلم لغة';
const String kPackageId = 'com.khaled.taallam_lugha';
const String kPlayUrl = 'https://play.google.com/store/apps/details?id=$kPackageId';

const Color kPrimary = Color(0xFF5B6CFF);
const Color kAccent = Color(0xFFFF9F43);
const Color kGood = Color(0xFF2ECC71);
const Color kBad = Color(0xFFE74C3C);
const Color kBg = Color(0xFFF5F7FF);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TaallamApp());
}

class TaallamApp extends StatelessWidget {
  const TaallamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kAppName,
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: kPrimary,
        scaffoldBackgroundColor: kBg,
      ),
      home: const HomeScreen(),
    );
  }
}

// ---------------------------------------------------------------- data

class CardItem {
  final String type; // word | sentence
  final String text;
  final String ar;
  final String image;
  CardItem({required this.type, required this.text, required this.ar, required this.image});
  factory CardItem.fromJson(Map<String, dynamic> j) =>
      CardItem(type: j['type'], text: j['text'], ar: j['ar'], image: j['image']);
  String get key => image;
  bool get isSentence => type == 'sentence';
}

class Unit {
  final String id;
  final String titleAr;
  final String titleEn;
  final List<CardItem> cards;
  Unit({required this.id, required this.titleAr, required this.titleEn, required this.cards});
  factory Unit.fromJson(Map<String, dynamic> j) => Unit(
        id: j['id'],
        titleAr: j['title_ar'],
        titleEn: j['title_en'],
        cards: (j['cards'] as List).map((e) => CardItem.fromJson(e)).toList(),
      );
}

class Level {
  final String code;
  final List<Unit> units;
  Level(this.code, this.units);
  static Future<Level> load(String asset) async {
    final raw = await rootBundle.loadString(asset);
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return Level(j['level'], (j['units'] as List).map((e) => Unit.fromJson(e)).toList());
  }
}

class Progress {
  static const _kDone = 'done_cards';
  static const _kUnits = 'done_units';
  static const _kRated = 'rate_asked';

  static Future<Set<String>> doneCards() async {
    final p = await SharedPreferences.getInstance();
    return (p.getStringList(_kDone) ?? []).toSet();
  }

  static Future<void> markCard(String key) async {
    final p = await SharedPreferences.getInstance();
    final s = (p.getStringList(_kDone) ?? []).toSet()..add(key);
    await p.setStringList(_kDone, s.toList());
  }

  static Future<Set<String>> doneUnits() async {
    final p = await SharedPreferences.getInstance();
    return (p.getStringList(_kUnits) ?? []).toSet();
  }

  static Future<void> markUnit(String id) async {
    final p = await SharedPreferences.getInstance();
    final s = (p.getStringList(_kUnits) ?? []).toSet()..add(id);
    await p.setStringList(_kUnits, s.toList());
  }

  static Future<bool> rateAsked() async =>
      (await SharedPreferences.getInstance()).getBool(_kRated) ?? false;
  static Future<void> setRateAsked() async =>
      (await SharedPreferences.getInstance()).setBool(_kRated, true);
}

// ---------------------------------------------------------------- speech

class Voice {
  Voice._();
  static final Voice I = Voice._();
  final FlutterTts _tts = FlutterTts();
  final SpeechToText _stt = SpeechToText();
  bool _ttsReady = false;
  bool? _sttReady;

  Future<void> speak(String text, {bool slow = false}) async {
    if (!_ttsReady) {
      await _tts.setLanguage('en-US');
      await _tts.setPitch(1.0);
      _ttsReady = true;
    }
    await _tts.setSpeechRate(slow ? 0.3 : 0.45);
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<bool> initStt() async {
    _sttReady ??= await _stt.initialize(onError: (_) {}, onStatus: (_) {});
    return _sttReady!;
  }

  Future<void> listen(void Function(String words, bool done) onResult) async {
    await _tts.stop();
    await _stt.listen(
      localeId: 'en_US',
      listenFor: const Duration(seconds: 8),
      pauseFor: const Duration(seconds: 2),
      listenOptions: SpeechListenOptions(partialResults: true, cancelOnError: true),
      onResult: (r) => onResult(r.recognizedWords, r.finalResult),
    );
  }

  Future<void> stop() => _stt.stop();
  bool get isListening => _stt.isListening;
}

/// Compares what the learner said with the target, word by word.
class SpeechCheck {
  final List<String> target;
  final List<bool> ok;
  final double score;
  SpeechCheck(this.target, this.ok, this.score);

  static List<String> _words(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r"[^a-z0-9' ]"), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();

  static SpeechCheck compare(String target, String heard) {
    final t = _words(target);
    final h = _words(heard);
    final ok = <bool>[];
    var j = 0;
    for (final w in t) {
      var found = false;
      for (var k = j; k < h.length && k < j + 3; k++) {
        if (h[k] == w || (w.length > 3 && _close(h[k], w))) {
          found = true;
          j = k + 1;
          break;
        }
      }
      ok.add(found);
    }
    final score = t.isEmpty ? 0.0 : ok.where((e) => e).length / t.length;
    return SpeechCheck(t, ok, score);
  }

  static bool _close(String a, String b) {
    // allow one letter difference for longer words
    if ((a.length - b.length).abs() > 1) return false;
    var diff = 0;
    final n = min(a.length, b.length);
    for (var i = 0; i < n; i++) {
      if (a[i] != b[i]) diff++;
    }
    diff += (a.length - b.length).abs();
    return diff <= 1;
  }

  bool get passed => score >= 0.8;
}

// ---------------------------------------------------------------- widgets

class CardImage extends StatelessWidget {
  final CardItem card;
  final double? height;
  const CardImage(this.card, {super.key, this.height});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Image.asset(
        card.image,
        height: height,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Container(
          height: height ?? 260,
          width: double.infinity,
          color: Colors.white,
          alignment: Alignment.center,
          padding: const EdgeInsets.all(16),
          child: Text(card.text,
              textAlign: TextAlign.center,
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold, color: kPrimary)),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- home

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Level? level;
  Set<String> done = {};
  Set<String> doneUnits = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await Level.load('assets/content/a1.json');
    final d = await Progress.doneCards();
    final u = await Progress.doneUnits();
    setState(() {
      level = l;
      done = d;
      doneUnits = u;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = level;
    return Scaffold(
      appBar: AppBar(
        title: const Text(kAppName, style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: l == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [kPrimary, Color(0xFF8E7CFF)]),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('المستوى ${l.code} — المبتدئ',
                          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      const Text('شوف الصورة، اسمع الكلمة، وقولها بصوتك. التطبيق بيصححلك النطق.',
                          style: TextStyle(color: Colors.white70, fontSize: 15)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                for (var i = 0; i < l.units.length; i++) _unitTile(l.units[i], i),
              ],
            ),
    );
  }

  Widget _unitTile(Unit u, int i) {
    final n = u.cards.where((c) => done.contains(c.key)).length;
    final finished = doneUnits.contains(u.id);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => LessonScreen(unit: u)));
          _load();
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              SizedBox(width: 70, height: 90, child: CardImage(u.cards.first, height: 90)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('الوحدة ${i + 1}: ${u.titleAr}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text(u.titleEn, style: const TextStyle(color: Colors.black54)),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: n / u.cards.length,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(8),
                      color: finished ? kGood : kAccent,
                    ),
                    const SizedBox(height: 4),
                    Text(finished ? 'مكتملة ✅' : '$n من ${u.cards.length}',
                        style: const TextStyle(fontSize: 13, color: Colors.black54)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- lesson

class LessonScreen extends StatefulWidget {
  final Unit unit;
  const LessonScreen({super.key, required this.unit});
  @override
  State<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends State<LessonScreen> {
  int index = 0;
  String heard = '';
  bool listening = false;
  SpeechCheck? result;
  String? micError;

  CardItem get card => widget.unit.cards[index];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => Voice.I.speak(card.text));
  }

  Future<void> _record() async {
    if (listening) {
      await Voice.I.stop();
      return;
    }
    final ok = await Voice.I.initStt();
    if (!ok) {
      setState(() => micError = 'محتاجين إذن الميكروفون وخدمة التعرف على الكلام من جوجل.');
      return;
    }
    setState(() {
      listening = true;
      heard = '';
      result = null;
      micError = null;
    });
    await Voice.I.listen((words, done) {
      if (!mounted) return;
      setState(() => heard = words);
      if (done) _finishListening();
    });
    // safety: stop UI state if recognizer ended without a final result
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted && listening && !Voice.I.isListening) _finishListening();
    });
  }

  void _finishListening() {
    final r = SpeechCheck.compare(card.text, heard);
    setState(() {
      listening = false;
      result = r;
    });
    if (r.passed) Progress.markCard(card.key);
  }

  void _next() {
    if (index < widget.unit.cards.length - 1) {
      setState(() {
        index++;
        heard = '';
        result = null;
        micError = null;
      });
      Voice.I.speak(card.text);
    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => QuizScreen(unit: widget.unit)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.unit.cards.length;
    return Scaffold(
      appBar: AppBar(title: Text(widget.unit.titleAr), centerTitle: true),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: LinearProgressIndicator(
                value: (index + 1) / total,
                minHeight: 8,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    CardImage(card, height: 330),
                    const SizedBox(height: 10),
                    Text(card.ar, style: const TextStyle(fontSize: 22, color: Colors.black87)),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _round(Icons.volume_up_rounded, 'اسمع', kPrimary, () => Voice.I.speak(card.text)),
                        const SizedBox(width: 18),
                        _round(Icons.slow_motion_video_rounded, 'ببطء', kPrimary,
                            () => Voice.I.speak(card.text, slow: true)),
                        const SizedBox(width: 18),
                        _round(listening ? Icons.stop_rounded : Icons.mic_rounded,
                            listening ? 'إيقاف' : 'قول بصوتك', listening ? kBad : kAccent, _record,
                            big: true),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (listening)
                      Text(heard.isEmpty ? 'بسمعك... اتكلم دلوقتي' : heard,
                          textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 18)),
                    if (micError != null) Text(micError!, style: const TextStyle(color: kBad)),
                    if (result != null) _feedback(result!),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: _next,
                  style: FilledButton.styleFrom(
                    backgroundColor: result?.passed == true ? kGood : kPrimary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                  child: Text(index < total - 1 ? 'التالي' : 'ابدأ الاختبار',
                      style: const TextStyle(fontSize: 20)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _round(IconData icon, String label, Color c, VoidCallback onTap, {bool big = false}) {
    final size = big ? 84.0 : 64.0;
    return Column(
      children: [
        Material(
          color: c,
          shape: const CircleBorder(),
          elevation: 3,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: size, height: size, child: Icon(icon, color: Colors.white, size: size * 0.5)),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(fontSize: 14)),
      ],
    );
  }

  Widget _feedback(SpeechCheck r) {
    final pass = r.passed;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: (pass ? kGood : kBad).withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: pass ? kGood : kBad),
      ),
      child: Column(
        children: [
          Text(pass ? 'ممتاز! نطقك صحيح 👏' : 'قربت! جرب تاني',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: pass ? kGood : kBad)),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            textDirection: TextDirection.ltr,
            spacing: 6,
            children: [
              for (var i = 0; i < r.target.length; i++)
                Text(r.target[i],
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: r.ok[i] ? kGood : kBad,
                        decoration: r.ok[i] ? null : TextDecoration.underline)),
            ],
          ),
          const SizedBox(height: 6),
          Text('سمعتك بتقول: ${heard.isEmpty ? '—' : heard}',
              style: const TextStyle(color: Colors.black54)),
          if (!pass) const Text('الكلمات الحمرا محتاجة تتنطق أوضح. اسمعها تاني وجرب.',
              style: TextStyle(color: Colors.black54)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- quiz

class QuizScreen extends StatefulWidget {
  final Unit unit;
  const QuizScreen({super.key, required this.unit});
  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  late final List<CardItem> questions;
  int q = 0;
  int correct = 0;
  String? picked;
  late List<String> options;
  final rnd = Random();

  @override
  void initState() {
    super.initState();
    questions = [...widget.unit.cards]..shuffle(rnd);
    _makeOptions();
  }

  void _makeOptions() {
    final c = questions[q];
    final pool = widget.unit.cards.where((x) => x.type == c.type && x.text != c.text).map((x) => x.text).toList()
      ..shuffle(rnd);
    options = [c.text, ...pool.take(3)]..shuffle(rnd);
    picked = null;
  }

  void _pick(String o) {
    if (picked != null) return;
    final ok = o == questions[q].text;
    setState(() {
      picked = o;
      if (ok) correct++;
    });
    Voice.I.speak(questions[q].text);
    Future.delayed(const Duration(milliseconds: 1300), () {
      if (!mounted) return;
      if (q < questions.length - 1) {
        setState(() {
          q++;
          _makeOptions();
        });
      } else {
        _finish();
      }
    });
  }

  Future<void> _finish() async {
    final total = questions.length;
    final passed = correct >= (total * 0.7).ceil();
    if (passed) await Progress.markUnit(widget.unit.id);
    final askRate = passed && !(await Progress.rateAsked());
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(passed ? 'برافو! خلصت الوحدة 🎉' : 'محتاج مراجعة شوية'),
        content: Text('جاوبت صح $correct من $total.'
            '${askRate ? '\n\nلو التطبيق عجبك، قيّمنا على جوجل بلاي ⭐ ده بيساعدنا جداً.' : ''}'),
        actions: [
          if (askRate)
            FilledButton(
              onPressed: () async {
                await Progress.setRateAsked();
                await launchUrl(Uri.parse(kPlayUrl), mode: LaunchMode.externalApplication);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('قيّم التطبيق ⭐'),
            ),
          TextButton(
            onPressed: () async {
              if (askRate) await Progress.setRateAsked();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(askRate ? 'بعدين' : 'تمام'),
          ),
        ],
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = questions[q];
    return Scaffold(
      appBar: AppBar(title: Text('اختبار: ${widget.unit.titleAr}'), centerTitle: true),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              LinearProgressIndicator(
                value: (q + 1) / questions.length,
                minHeight: 8,
                borderRadius: BorderRadius.circular(8),
              ),
              const SizedBox(height: 12),
              const Text('إيه معنى ده بالإنجليزي؟', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 8),
              Text(c.ar, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
              const Spacer(),
              for (final o in options)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SizedBox(
                    width: double.infinity,
                    height: 58,
                    child: OutlinedButton(
                      onPressed: () => _pick(o),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: picked == null
                            ? Colors.white
                            : o == c.text
                                ? kGood.withOpacity(0.2)
                                : o == picked
                                    ? kBad.withOpacity(0.2)
                                    : Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Text(o, textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 20)),
                    ),
                  ),
                ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

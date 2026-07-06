import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const PreguntasApp());
}

class PreguntasApp extends StatelessWidget {
  const PreguntasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Preguntas',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}

/// A selectable test (a "norma"), described in assets/tests/index.json.
class TestInfo {
  final String id;
  final String titulo;
  final String descripcion;
  final String dir;

  TestInfo({
    required this.id,
    required this.titulo,
    required this.descripcion,
    required this.dir,
  });

  factory TestInfo.fromJson(Map<String, dynamic> json) {
    return TestInfo(
      id: json['id'] as String,
      titulo: json['titulo'] as String,
      descripcion: json['descripcion'] as String,
      dir: json['dir'] as String,
    );
  }

  String get questionsPath => '$dir/questions.json';
  String get articulosDir => '$dir/articulos';

  String get answersPrefKey => 'answers_$id';
  String get currentIndexPrefKey => 'current_index_$id';
  String get totalPrefKey => 'total_$id';
}

class Question {
  final String question;
  final List<String> options;
  final String? article;

  Question({
    required this.question,
    required this.options,
    this.article,
  });

  /// The correct option is always the first one in [options].
  static const int correctIndex = 0;

  factory Question.fromJson(Map<String, dynamic> json) {
    return Question(
      question: json['question'] as String,
      options: List<String>.from(json['options'] as List),
      article: json['article'] as String?,
    );
  }
}

const _reportEmail = 'preguntas@ainz.eus';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<TestInfo> _tests = [];
  bool _loading = true;
  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    _loadTests();
  }

  Future<void> _loadTests() async {
    final raw = await rootBundle.loadString('assets/tests/index.json');
    final data = jsonDecode(raw) as List;
    final tests = data.map((t) => TestInfo.fromJson(t as Map<String, dynamic>)).toList();
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _tests = tests;
      _prefs = prefs;
      _loading = false;
    });
  }

  /// Returns "N / total respondidas" for a started test, or null if not started.
  String? _progressLabel(TestInfo test) {
    final prefs = _prefs;
    if (prefs == null) return null;
    final total = prefs.getInt(test.totalPrefKey);
    if (total == null) return null;
    final saved = prefs.getStringList(test.answersPrefKey) ?? [];
    final answered = saved.where((s) => s != '-1').length;
    return '$answered / $total respondidas';
  }

  Future<void> _openTest(TestInfo test) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => QuizScreen(test: test)),
    );
    // Refresh progress labels after returning from the quiz.
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Preguntas')),
      body: _tests.isEmpty
          ? const Center(child: Text('No hay teses disponibles.'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _tests.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final test = _tests[index];
                final progress = _progressLabel(test);
                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    title: Text(
                      test.titulo,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(test.descripcion),
                        if (progress != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            progress,
                            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ],
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openTest(test),
                  ),
                );
              },
            ),
    );
  }
}

class QuizScreen extends StatefulWidget {
  final TestInfo test;

  const QuizScreen({super.key, required this.test});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  List<Question> _questions = [];
  List<int?> _answers = [];
  // For each question, the order in which its options are displayed:
  // _displayOrders[q][d] is the original option index shown at display slot d.
  // Answers are always stored/compared as original indices, so persistence and
  // results stay correct regardless of how the options are shuffled.
  List<List<int>> _displayOrders = [];
  int _currentIndex = 0;
  bool _loading = true;
  SharedPreferences? _prefs;
  final _random = Random();
  final Map<String, String> _articuloTextCache = {};

  /// Builds a fresh random display order for the given question.
  void _shuffleOrder(int index) {
    final count = _questions[index].options.length;
    _displayOrders[index] = List<int>.generate(count, (i) => i)..shuffle(_random);
  }

  TestInfo get _test => widget.test;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  Future<void> _loadQuestions() async {
    final raw = await rootBundle.loadString(_test.questionsPath);
    final data = jsonDecode(raw) as List;
    final questions = data.map((q) => Question.fromJson(q as Map<String, dynamic>)).toList();
    final prefs = await SharedPreferences.getInstance();

    final savedAnswers = prefs.getStringList(_test.answersPrefKey);
    final answers = List<int?>.filled(questions.length, null);
    if (savedAnswers != null && savedAnswers.length == questions.length) {
      for (var i = 0; i < savedAnswers.length; i++) {
        final value = int.tryParse(savedAnswers[i]);
        answers[i] = (value == null || value < 0) ? null : value;
      }
    }
    final savedIndex = prefs.getInt(_test.currentIndexPrefKey) ?? 0;
    // Record the question count so the home screen can show progress without loading questions.
    await prefs.setInt(_test.totalPrefKey, questions.length);

    if (!mounted) return;
    setState(() {
      _questions = questions;
      _answers = answers;
      _displayOrders = List.generate(
        questions.length,
        (i) => List<int>.generate(questions[i].options.length, (j) => j)..shuffle(_random),
      );
      _currentIndex = savedIndex.clamp(0, questions.length - 1);
      _prefs = prefs;
      _loading = false;
    });
    _maybeLoadArticuloForCurrent();
  }

  Future<void> _maybeLoadArticuloForCurrent() async {
    if (_currentIndex >= _questions.length) return;
    if (_answers[_currentIndex] == null) return;
    final articulo = _questions[_currentIndex].article;
    if (articulo == null || _articuloTextCache.containsKey(articulo)) return;

    final padded = articulo.padLeft(3, '0');
    try {
      final text = await rootBundle.loadString('${_test.articulosDir}/articulo_$padded.txt');
      if (!mounted) return;
      setState(() => _articuloTextCache[articulo] = text);
    } catch (_) {
      // Article text not available for this reference; the label alone is still shown.
    }
  }

  void _persist() {
    final prefs = _prefs;
    if (prefs == null) return;
    prefs.setStringList(_test.answersPrefKey, _answers.map((a) => (a ?? -1).toString()).toList());
    prefs.setInt(_test.currentIndexPrefKey, _currentIndex);
  }

  void _selectOption(int optionIndex) {
    setState(() => _answers[_currentIndex] = optionIndex);
    _persist();
    _maybeLoadArticuloForCurrent();
  }

  void _goTo(int index) {
    if (index < 0 || index >= _questions.length) return;
    setState(() {
      // Re-randomize the options every time the question is shown.
      _shuffleOrder(index);
      _currentIndex = index;
    });
    _persist();
    _maybeLoadArticuloForCurrent();
  }

  void _resetAll() {
    setState(() {
      _answers = List<int?>.filled(_questions.length, null);
      _currentIndex = 0;
    });
    _persist();
  }

  void _showJumpDialog() {
    final controller = TextEditingController(text: '${_currentIndex + 1}');
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ir a pregunta'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: '1 - ${_questions.length}'),
          onSubmitted: (_) => _submitJump(controller.text),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: () => _submitJump(controller.text), child: const Text('Ir')),
        ],
      ),
    );
  }

  void _submitJump(String text) {
    final value = int.tryParse(text);
    if (value != null && value >= 1 && value <= _questions.length) {
      _goTo(value - 1);
    }
    Navigator.pop(context);
  }

  Future<void> _reportQuestion() async {
    final question = _questions[_currentIndex];
    final options = question.options.asMap().entries.map((e) => '- ${e.value}').join('\n');
    final articuloLine = question.article != null ? ' (Artículo ${question.article})' : '';
    final uri = Uri(
      scheme: 'mailto',
      path: _reportEmail,
      query: [
        'subject=${Uri.encodeComponent('Reporte ${_test.id} pregunta ${_currentIndex + 1}')}',
        'body=${Uri.encodeComponent(
          '${_test.titulo}\n\nPregunta ${_currentIndex + 1}$articuloLine:\n${question.question}\n\nOpciones:\n$options\n\nComentario: (escribe aquí tu comentario)',
        )}',
      ].join('&'),
    );
    await launchUrl(uri);
  }

  void _showResults() {
    final answered = _answers.where((a) => a != null).length;
    var correct = 0;
    for (var i = 0; i < _questions.length; i++) {
      if (_answers[i] != null && _answers[i] == Question.correctIndex) {
        correct++;
      }
    }
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Resultado'),
        content: Text(
          'Respondidas: $answered / ${_questions.length}\nAciertos: $correct / $answered',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _resetAll();
            },
            child: const Text('Reiniciar'),
          ),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
        ],
      ),
    );
  }

  Widget _buildArticuloText(BuildContext context, String articulo) {
    final text = _articuloTextCache[articulo];
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: text == null
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator(),
                ),
              )
            : Text(text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(_test.titulo)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final question = _questions[_currentIndex];
    final selected = _answers[_currentIndex];

    return Scaffold(
      appBar: AppBar(
        title: Text('Pregunta ${_currentIndex + 1} / ${_questions.length}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flag_outlined),
            tooltip: 'Reportar pregunta',
            onPressed: _reportQuestion,
          ),
          IconButton(
            icon: const Icon(Icons.numbers),
            tooltip: 'Ir a pregunta',
            onPressed: _showJumpDialog,
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'Ver resultado',
            onPressed: _showResults,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                children: [
                  if (question.article != null) ...[
                    Text(
                      'Artículo ${question.article}',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  Text(question.question, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 24),
                  ...List.generate(_displayOrders[_currentIndex].length, (slot) {
                    final optionIndex = _displayOrders[_currentIndex][slot];
                    final isCorrect = optionIndex == Question.correctIndex;
                    final isSelected = optionIndex == selected;
                    Color? color;
                    if (selected != null) {
                      if (isCorrect) {
                        color = Colors.green.shade200;
                      } else if (isSelected) {
                        color = Colors.red.shade200;
                      }
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: color),
                        onPressed: () => _selectOption(optionIndex),
                        child: Text(question.options[optionIndex]),
                      ),
                    );
                  }),
                  if (selected != null && question.article != null) ...[
                    const SizedBox(height: 8),
                    _buildArticuloText(context, question.article!),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _currentIndex > 0 ? () => _goTo(_currentIndex - 1) : null,
                    child: const Text('Anterior'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: _currentIndex < _questions.length - 1
                        ? () => _goTo(_currentIndex + 1)
                        : null,
                    child: const Text('Siguiente'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

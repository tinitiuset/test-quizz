import 'dart:convert';

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
      home: const QuizScreen(),
    );
  }
}

class Question {
  final String question;
  final List<String> options;
  final int answerIndex;

  Question({required this.question, required this.options, required this.answerIndex});

  factory Question.fromJson(Map<String, dynamic> json) {
    return Question(
      question: json['question'] as String,
      options: List<String>.from(json['options'] as List),
      answerIndex: json['answerIndex'] as int,
    );
  }
}

const _answersPrefKey = 'answers';
const _currentIndexPrefKey = 'current_index';
const _reportEmail = 'preguntas@ainz.eus';

class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  List<Question> _questions = [];
  List<int?> _answers = [];
  int _currentIndex = 0;
  bool _loading = true;
  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  Future<void> _loadQuestions() async {
    final raw = await rootBundle.loadString('assets/questions.json');
    final data = jsonDecode(raw) as List;
    final questions = data.map((q) => Question.fromJson(q as Map<String, dynamic>)).toList();
    final prefs = await SharedPreferences.getInstance();

    final savedAnswers = prefs.getStringList(_answersPrefKey);
    final answers = List<int?>.filled(questions.length, null);
    if (savedAnswers != null && savedAnswers.length == questions.length) {
      for (var i = 0; i < savedAnswers.length; i++) {
        final value = int.tryParse(savedAnswers[i]);
        answers[i] = (value == null || value < 0) ? null : value;
      }
    }
    final savedIndex = prefs.getInt(_currentIndexPrefKey) ?? 0;

    setState(() {
      _questions = questions;
      _answers = answers;
      _currentIndex = savedIndex.clamp(0, questions.length - 1);
      _prefs = prefs;
      _loading = false;
    });
  }

  void _persist() {
    final prefs = _prefs;
    if (prefs == null) return;
    prefs.setStringList(_answersPrefKey, _answers.map((a) => (a ?? -1).toString()).toList());
    prefs.setInt(_currentIndexPrefKey, _currentIndex);
  }

  void _selectOption(int optionIndex) {
    setState(() => _answers[_currentIndex] = optionIndex);
    _persist();
  }

  void _goTo(int index) {
    if (index < 0 || index >= _questions.length) return;
    setState(() => _currentIndex = index);
    _persist();
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
    final uri = Uri(
      scheme: 'mailto',
      path: _reportEmail,
      query: [
        'subject=${Uri.encodeComponent('Reporte pregunta ${_currentIndex + 1}')}',
        'body=${Uri.encodeComponent(
          'Pregunta ${_currentIndex + 1}:\n${question.question}\n\nOpciones:\n$options\n\nComentario: (escribe aquí tu comentario)',
        )}',
      ].join('&'),
    );
    await launchUrl(uri);
  }

  void _showResults() {
    final answered = _answers.where((a) => a != null).length;
    var correct = 0;
    for (var i = 0; i < _questions.length; i++) {
      if (_answers[i] != null && _answers[i] == _questions[i].answerIndex) {
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
                  Text(question.question, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 24),
                  ...List.generate(question.options.length, (index) {
                    final isCorrect = index == question.answerIndex;
                    final isSelected = index == selected;
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
                        onPressed: () => _selectOption(index),
                        child: Text(question.options[index]),
                      ),
                    );
                  }),
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

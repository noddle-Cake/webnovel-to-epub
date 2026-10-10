import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../data/local_novel_service.dart';

import '../data/novel_api.dart';
import '../theme.dart';
import '../widgets/book_art.dart';

class ConvertScreen extends StatefulWidget {
  const ConvertScreen({super.key, this.service});
  final NovelService? service;
  @override
  State<ConvertScreen> createState() => _ConvertScreenState();
}

class _ConvertScreenState extends State<ConvertScreen> {
  late NovelService _service;
  bool _ownsService = false;
  final _form = GlobalKey<FormState>();
  final _url = TextEditingController();
  final _title = TextEditingController();
  final _author = TextEditingController();
  final _chapter = TextEditingController();
  BookMetadata? _metadata;
  Uint8List? _cover;
  String? _coverName;
  ExtractionJob? _job;
  String? _jobId;
  String? _exportTitle;
  String? _error;
  bool _detecting = false;
  bool _starting = false;
  bool _saving = false;
  bool _polling = false;
  bool _cancelling = false;
  int _generation = 0;
  bool get _working => _starting || (_job?.active ?? false);
  bool get _busy => _working || _detecting || _saving;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? (kIsWeb ? NovelApi() : LocalNovelService());
    _ownsService = widget.service == null;
  }

  @override
  void dispose() {
    _generation++;
    if (_ownsService) _service.close();
    for (final controller in [_url, _title, _author, _chapter]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _validUrl(String? value) {
    final uri = Uri.tryParse(value?.trim() ?? '');
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty) {
      return 'Enter a complete website URL.';
    }
    return null;
  }

  void _showError(Object error) {
    if (mounted) {
      setState(
        () => _error = error is ApiException
            ? error.message
            : 'Something went wrong. Please try again.',
      );
    }
  }

  Future<void> _detect() async {
    if (_validUrl(_url.text) != null) {
      setState(() => _error = 'Paste the novel’s homepage URL to get started.');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _detecting = true;
      _error = null;
    });
    try {
      final metadata = await _service.detect(_url.text.trim());
      if (!mounted) return;
      setState(() {
        _metadata = metadata;
        _title.text = metadata.title;
        _author.text = metadata.author;
        _chapter.text = metadata.firstChapter;
        _cover = null;
        _coverName = null;
        _job = null;
        _jobId = null;
      });
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _detecting = false);
    }
  }

  Future<void> _pickCover() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png'],
      );
      if (file == null || !mounted) return;
      if ((await file.length() ?? 0) > 8 * 1024 * 1024) {
        throw const ApiException('Choose a cover smaller than 8 MB.');
      }
      final bytes = await file.readAsBytes();
      if (bytes.length > 8 * 1024 * 1024) {
        throw const ApiException('Choose a cover smaller than 8 MB.');
      }
      if (!mounted) return;
      setState(() {
        _cover = bytes;
        _coverName = file.name;
        _error = null;
      });
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _extract() async {
    if (!_form.currentState!.validate()) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _starting = true;
      _error = null;
      _job = null;
      _jobId = null;
      _cancelling = false;
    });
    try {
      final id = await _service.extract(
        url: _url.text.trim(),
        title: _title.text.trim(),
        author: _author.text.trim(),
        chapterUrl: _chapter.text.trim(),
        cover: _cover,
      );
      if (!mounted) return;
      setState(() {
        _jobId = id;
        _exportTitle = _title.text.trim();
        _job = ExtractionJob(id: id, status: 'queued');
      });
      unawaited(_poll());
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _poll() async {
    if (_polling || _jobId == null) return;
    final generation = ++_generation;
    setState(() {
      _polling = true;
      _error = null;
    });
    try {
      while (mounted && generation == _generation) {
        final job = await _service.job(_jobId!);
        if (!mounted || generation != _generation) return;
        setState(() {
          _job = job;
          if (!job.active) _cancelling = false;
        });
        if (!job.active) {
          if (job.status == 'failed') {
            setState(
              () =>
                  _error = job.error ?? 'Extraction failed. Please try again.',
            );
          }
          break;
        }
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    } catch (error) {
      if (mounted && error is ApiException && error.statusCode == 404) {
        setState(
          () => _job = ExtractionJob(
            id: _jobId!,
            status: 'failed',
            error: error.message,
          ),
        );
      }
      _showError(error);
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _polling = false);
      }
    }
  }

  Future<void> _cancel() async {
    if (_jobId == null) return;
    setState(() {
      _cancelling = true;
      _error = null;
    });
    try {
      await _service.cancel(_jobId!);
      if (mounted && !_polling) unawaited(_poll());
    } catch (error) {
      _showError(error);
      if (mounted) setState(() => _cancelling = false);
    }
  }

  void _startOver() {
    final id = _jobId;
    if (id != null) unawaited(_service.cancel(id).catchError((Object _) {}));
    setState(() {
      _generation++;
      _polling = false;
      _jobId = null;
      _job = null;
      _cancelling = false;
      _error = null;
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final bytes = await _service.download(_jobId!);
      if (!mounted) return;
      final name = (_exportTitle ?? 'novel').replaceAll(
        RegExp(r'[<>:"/\\|?*\x00-\x1f]'),
        '_',
      );
      final path = await FileSaver.instance.saveAs(
        name: name,
        bytes: bytes,
        fileExtension: 'epub',
        mimeType: MimeType.custom,
        customMimeType: 'application/epub+zip',
      );
      if (mounted && path != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Your EPUB is saved. Happy reading!')),
        );
      }
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _settings() async {
    final controller = TextEditingController(
      text: (_service as NovelApi).baseUrl,
    );
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Server connection'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Use your server’s address. On a physical phone, enter the computer’s local network address.',
              ),
              const SizedBox(height: 20),
              TextField(
                controller: controller,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Server URL',
                  hintText: 'https://your-server.com',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Connect'),
          ),
        ],
      ),
    );
    // Dialog controllers are disposed after the closing animation finishes.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    controller.dispose();
    if (result == null || !mounted) return;
    if (_validUrl(result) != null) {
      _showError(const ApiException('Enter a valid server URL.'));
      return;
    }
    if (_ownsService) _service.close();
    setState(() {
      _service = NovelApi(baseUrl: result);
      _ownsService = true;
      _error = null;
      _job = null;
      _jobId = null;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 920;
          return SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1240),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    wide ? 48 : 20,
                    24,
                    wide ? 48 : 20,
                    36,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _header(wide),
                      SizedBox(height: wide ? 56 : 36),
                      _hero(wide),
                      const SizedBox(height: 32),
                      if (_error != null) ...[
                        _errorBanner(),
                        const SizedBox(height: 20),
                      ],
                      Form(
                        key: _form,
                        child: wide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(flex: 7, child: _editor()),
                                  const SizedBox(width: 28),
                                  Expanded(flex: 4, child: _preview()),
                                ],
                              )
                            : Column(
                                children: [
                                  _editor(),
                                  const SizedBox(height: 24),
                                  _preview(),
                                ],
                              ),
                      ),
                      const SizedBox(height: 32),
                      Center(
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Icon(
                              Icons.menu_book_outlined,
                              size: 16,
                              color: muted,
                            ),
                            Text(
                              'A little less scrolling. A little more reading.',
                              style: TextStyle(color: muted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );

  Widget _header(bool wide) => Row(
    children: [
      Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: ink,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(
          Icons.auto_stories_rounded,
          color: Colors.white,
          size: 22,
        ),
      ),
      const SizedBox(width: 12),
      const Expanded(
        child: Text(
          'Chapter & Verse',
          style: TextStyle(fontFamily: 'Fraunces', fontSize: 22, color: ink),
        ),
      ),
      if (wide)
        const Padding(
          padding: EdgeInsets.only(right: 28),
          child: Text(
            'YOUR STORIES, OFFLINE',
            style: TextStyle(fontSize: 10, letterSpacing: 2, color: muted),
          ),
        ),
      if (_service is NovelApi)
        IconButton(
          onPressed: _busy ? null : _settings,
          tooltip: 'Server connection',
          icon: const Icon(Icons.tune_rounded, size: 22),
        ),
    ],
  );

  Widget _hero(bool wide) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'FROM THE WEB TO YOUR BOOKSHELF',
              style: TextStyle(
                color: muted,
                fontSize: 10,
                letterSpacing: 2.2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Good stories.\nYours to keep.',
              style: TextStyle(
                fontFamily: 'Fraunces',
                color: ink,
                fontSize: wide ? 58 : 42,
                height: 1.08,
                letterSpacing: -1.5,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Turn your favorite web novels into beautiful EPUBs.\nReady for your reader, wherever the story takes you.',
              style: TextStyle(color: muted, fontSize: 15, height: 1.7),
            ),
            const SizedBox(height: 22),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                _siteChip('Royal Road'),
                _siteChip('RoliaScan'),
                _siteChip('EPUB format', icon: Icons.check_rounded),
              ],
            ),
          ],
        ),
      ),
      if (wide)
        Padding(
          padding: const EdgeInsets.only(right: 40, left: 48),
          child: Transform.rotate(
            angle: .09,
            child: const SizedBox(
              width: 145,
              child: BookArt(
                title: 'One more\nchapter.',
                author: 'TAKE THE STORY WITH YOU',
              ),
            ),
          ),
        ),
    ],
  );

  Widget _siteChip(String label, {IconData icon = Icons.language_rounded}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFECEFE5),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: ink, size: 14),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 11, color: ink)),
          ],
        ),
      );

  Widget _errorBanner() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFFCF0E8),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, color: Color(0xFF9A4C2C), size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            _error!,
            style: const TextStyle(color: Color(0xFF9A4C2C), height: 1.5),
          ),
        ),
        IconButton(
          onPressed: () => setState(() => _error = null),
          tooltip: 'Dismiss message',
          icon: const Icon(Icons.close, size: 18),
        ),
      ],
    ),
  );

  Widget _card(Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFE1E6DC)),
    ),
    child: child,
  );

  Widget _sectionTitle(String number, String title, String subtitle) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFEDF1E7),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          number,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: ink,
          ),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 17,
                color: ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 12, color: muted, height: 1.5),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _editor() => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          '01',
          'Find your story',
          'Paste the homepage of a supported novel.',
        ),
        const SizedBox(height: 22),
        TextFormField(
          key: const Key('novel-url'),
          controller: _url,
          enabled: !_busy,
          keyboardType: TextInputType.url,
          autocorrect: false,
          validator: _validUrl,
          decoration: const InputDecoration(
            labelText: 'Novel URL',
            hintText: 'https://roliascan.com/manga/…',
            prefixIcon: Icon(Icons.link_rounded, size: 20),
          ),
          onChanged: (_) {
            if (_metadata != null || _job != null) {
              setState(() {
                _metadata = null;
                _cover = null;
                _coverName = null;
                _title.clear();
                _author.clear();
                _chapter.clear();
                _job = null;
                _jobId = null;
              });
            }
          },
          onFieldSubmitted: (_) {
            if (!_busy) _detect();
          },
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _busy ? null : _detect,
            icon: _detecting
                ? _spinner()
                : const Icon(Icons.search_rounded, size: 19),
            label: Text(
              _detecting ? 'Finding your story…' : 'Find book details',
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 26),
          child: Divider(height: 1, color: Color(0xFFE8EBE4)),
        ),
        _sectionTitle(
          '02',
          'Make it yours',
          'Review the details, or fill them in yourself.',
        ),
        const SizedBox(height: 22),
        TextFormField(
          key: const Key('book-title'),
          controller: _title,
          enabled: !_busy,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Book title',
            hintText: 'The title on your bookshelf',
          ),
          validator: (value) => value == null || value.trim().isEmpty
              ? 'Add a book title.'
              : null,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: const Key('book-author'),
          controller: _author,
          enabled: !_busy,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Author',
            hintText: 'Who wrote your story?',
          ),
          validator: (value) =>
              value == null || value.trim().isEmpty ? 'Add an author.' : null,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: const Key('first-chapter'),
          controller: _chapter,
          enabled: !_busy,
          keyboardType: TextInputType.url,
          autocorrect: false,
          validator: _validUrl,
          decoration: const InputDecoration(
            labelText: 'First chapter URL',
            hintText: 'Where should we start?',
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'We’ll follow the chapters from here, in reading order.',
          style: TextStyle(fontSize: 11, color: muted, height: 1.5),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 26),
          child: Divider(height: 1, color: Color(0xFFE8EBE4)),
        ),
        _sectionTitle(
          '03',
          'Take the story with you',
          'Create an EPUB for Apple Books, Kobo, and more.',
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: const Key('create-epub'),
            onPressed: _busy ? null : _extract,
            icon: _starting
                ? _spinner()
                : const Icon(Icons.auto_stories_outlined, size: 20),
            label: Text(_starting ? 'Starting your book…' : 'Create EPUB'),
          ),
        ),
        const SizedBox(height: 12),
        const Center(
          child: Text(
            'Your formatting stays. The distractions go.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: muted),
          ),
        ),
      ],
    ),
  );

  Widget _preview() => Column(
    children: [
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'ON YOUR BOOKSHELF',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.8,
                      color: muted,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECEFE5),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'EPUB',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: ink,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 24),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F1E9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: SizedBox(width: 175, child: _coverPreview()),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              _title.text.isEmpty ? 'Your story starts here' : _title.text,
              style: const TextStyle(
                fontFamily: 'Fraunces',
                fontSize: 22,
                height: 1.2,
                color: ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _author.text.isEmpty
                  ? 'A whole world, one book.'
                  : 'by ${_author.text}',
              style: const TextStyle(fontSize: 12, color: muted),
            ),
            if (_metadata?.description?.isNotEmpty ?? false) ...[
              const SizedBox(height: 14),
              Text(
                _metadata!.description!,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: muted, height: 1.6),
              ),
            ],
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _pickCover,
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                label: Text(_cover != null ? 'Change cover' : 'Upload a cover'),
              ),
            ),
            const SizedBox(height: 10),
            if (_cover != null)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _coverName ?? 'Custom cover',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: muted),
                    ),
                  ),
                  IconButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _cover = null;
                            _coverName = null;
                          }),
                    tooltip: 'Use original cover',
                    icon: const Icon(Icons.close, size: 16),
                  ),
                ],
              )
            else
              const Center(
                child: Text(
                  'Optional · JPG or PNG · Up to 8 MB',
                  style: TextStyle(fontSize: 10, color: muted),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      if (_job != null)
        _progressCard()
      else
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFFEAEFE4),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.offline_bolt_outlined, color: ink, size: 22),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'A book, wherever you are.',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: ink,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Save once. Read on the train, on a flight, or somewhere wonderfully quiet.',
                      style: TextStyle(fontSize: 12, color: muted, height: 1.6),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
    ],
  );

  Widget _coverPreview() {
    Widget fallback() => BookArt(title: _title.text, author: _author.text);
    if (_cover != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.memory(
          _cover!,
          fit: BoxFit.cover,
          errorBuilder: (_, error, stack) => fallback(),
        ),
      );
    }
    if (_metadata?.coverUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.network(
          _metadata!.coverUrl!,
          fit: BoxFit.cover,
          errorBuilder: (_, error, stack) => fallback(),
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : fallback(),
        ),
      );
    }
    return fallback();
  }

  Widget _progressCard() {
    final job = _job!;
    final complete = job.status == 'complete';
    final title = switch (job.status) {
      'complete' => 'Your next read is ready.',
      'failed' => 'We couldn’t finish this book.',
      'cancelled' => 'Extraction cancelled.',
      'queued' => 'Your story is in line.',
      _ => _cancelling ? 'Stopping extraction…' : 'Building your book…',
    };
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            complete
                ? Icons.check_circle_outline_rounded
                : Icons.auto_stories_outlined,
            color: ink,
            size: 28,
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Fraunces',
              fontSize: 22,
              color: ink,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '${job.chapters} ${job.chapters == 1 ? 'chapter' : 'chapters'} collected',
            style: const TextStyle(fontSize: 13, color: muted),
          ),
          if (job.chapterTitle.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              job.chapterTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: muted),
            ),
          ],
          if (job.active) ...[
            const SizedBox(height: 20),
            if (_polling) const LinearProgressIndicator(minHeight: 3),
            const SizedBox(height: 12),
            if (!_polling)
              OutlinedButton.icon(
                onPressed: _poll,
                icon: const Icon(Icons.refresh),
                label: const Text('Reconnect to progress'),
              ),
            if (!_polling)
              TextButton(
                onPressed: _startOver,
                child: const Text('Start over'),
              ),
            TextButton(
              onPressed: _cancelling ? null : _cancel,
              child: Text(_cancelling ? 'Cancelling…' : 'Cancel extraction'),
            ),
          ],
          if (complete) ...[
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('save-epub'),
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? _spinner()
                    : const Icon(Icons.download_rounded, size: 18),
                label: Text(_saving ? 'Saving…' : 'Save EPUB'),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _service is NovelApi
                  ? 'Your download is available for one hour.'
                  : 'Save your book before closing the app.',
              style: const TextStyle(fontSize: 10, color: muted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _spinner() => const SizedBox(
    width: 18,
    height: 18,
    child: CircularProgressIndicator(strokeWidth: 2),
  );
}

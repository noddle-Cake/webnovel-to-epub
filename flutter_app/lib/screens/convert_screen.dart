import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../data/local_novel_service.dart';

import '../data/novel_api.dart';

class ConvertScreen extends StatefulWidget {
  const ConvertScreen({
    super.key,
    this.service,
    this.initialUrl,
    this.initialBook,
  });
  final NovelService? service;
  final String? initialUrl;
  final BookMetadata? initialBook;
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
    _url.text = widget.initialUrl ?? '';
    _metadata = widget.initialBook;
    _title.text = _metadata?.title ?? '';
    _author.text = _metadata?.author ?? '';
    _chapter.text = _metadata?.firstChapter ?? '';
  }

  @override
  void dispose() {
    _generation++;
    if (_job?.active == true && _jobId != null) {
      unawaited(_service.cancel(_jobId!).catchError((Object _) {}));
    }
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
                'Enter the extraction API address for this web client.',
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
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create an EPUB'),
        actions: [
          if (_service is NovelApi)
            IconButton(
              tooltip: 'Server connection',
              onPressed: _busy ? null : _settings,
              icon: const Icon(Icons.dns_outlined),
            ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Take your story with you',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _service is NovelApi
                        ? 'Create an EPUB with your connected extraction server.'
                        : 'Chapters are fetched and packaged on this device. Keep the app open until your book is ready.',
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 28),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Text(
                        _error!,
                        style: TextStyle(color: colors.error),
                      ),
                    ),
                  TextFormField(
                    key: const Key('novel-url'),
                    controller: _url,
                    enabled: !_busy,
                    validator: _validUrl,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Novel URL',
                      hintText: 'Paste a Royal Road or RoliaScan novel page',
                    ),
                    onChanged: (_) => setState(() {
                      _metadata = null;
                      _title.clear();
                      _author.clear();
                      _chapter.clear();
                      _cover = null;
                      _coverName = null;
                      _job = null;
                      _jobId = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _detect,
                    icon: _detecting ? _spinner() : const Icon(Icons.search),
                    label: const Text('Find book details'),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'Book details',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    key: const Key('book-title'),
                    controller: _title,
                    enabled: !_busy,
                    validator: (v) =>
                        v?.trim().isEmpty != false ? 'Add a book title.' : null,
                    decoration: const InputDecoration(labelText: 'Title'),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('book-author'),
                    controller: _author,
                    enabled: !_busy,
                    decoration: const InputDecoration(labelText: 'Author'),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('first-chapter'),
                    controller: _chapter,
                    enabled: !_busy,
                    validator: _validUrl,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Starting chapter URL',
                    ),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _pickCover,
                        icon: const Icon(Icons.image_outlined),
                        label: const Text('Upload a cover'),
                      ),
                      if (_coverName != null) Text(_coverName!),
                      if (_cover != null)
                        IconButton(
                          tooltip: 'Remove cover',
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                  _cover = null;
                                  _coverName = null;
                                }),
                          icon: const Icon(Icons.close),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Optional JPEG or PNG, up to 8 MB',
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const Key('create-epub'),
                      onPressed: _busy ? null : _extract,
                      icon: _starting
                          ? _spinner()
                          : const Icon(Icons.file_download_outlined),
                      label: const Text('Create EPUB'),
                    ),
                  ),
                  if (_job != null) ...[
                    const SizedBox(height: 24),
                    _progressCard(),
                  ],
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _progressCard() {
    final job = _job!;
    final complete = job.status == 'complete';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(switch (job.status) {
              'complete' => 'Your next read is ready.',
              'failed' => 'We couldn’t finish this book.',
              'cancelled' => 'Extraction cancelled.',
              _ => 'Building your book…',
            }, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text(
              '${job.chapters} ${job.chapters == 1 ? 'chapter' : 'chapters'} collected',
            ),
            if (job.chapterTitle.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(job.chapterTitle),
              ),
            if (job.active) ...[
              const SizedBox(height: 20),
              if (_polling) const LinearProgressIndicator(),
              if (!_polling) ...[
                TextButton(
                  onPressed: _poll,
                  child: const Text('Reconnect to progress'),
                ),
                TextButton(
                  onPressed: _startOver,
                  child: const Text('Start over'),
                ),
              ],
              TextButton(
                onPressed: _cancelling ? null : _cancel,
                child: Text(_cancelling ? 'Cancelling…' : 'Cancel extraction'),
              ),
            ],
            if (complete) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                key: const Key('save-epub'),
                onPressed: _saving ? null : _save,
                icon: _saving ? _spinner() : const Icon(Icons.save_alt),
                label: const Text('Save EPUB'),
              ),
              const SizedBox(height: 12),
              Text(
                _service is NovelApi
                    ? 'Your download is available for one hour.'
                    : 'Save your book before leaving this page.',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _spinner() => const SizedBox(
    width: 18,
    height: 18,
    child: CircularProgressIndicator(strokeWidth: 2),
  );
}

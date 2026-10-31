#!/usr/bin/env python3
"""Create a local timestamped transcript with an already installed Whisper model."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def atomic_json(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix='.' + path.name + '.')
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as stream:
            json.dump(payload, stream, ensure_ascii=False, indent=2)
            stream.write('\n')
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True, type=Path)
    parser.add_argument('--source-id', required=True)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--model-dir', required=True, type=Path,
                        help='existing local faster-whisper or MLX Whisper model directory; no download')
    parser.add_argument('--language')
    parser.add_argument('--cpu-threads', type=int, default=max(1, (os.cpu_count() or 4) - 2))
    args = parser.parse_args()

    source = args.source.expanduser().resolve(strict=True)
    model_dir = args.model_dir.expanduser().resolve(strict=True)
    output = args.output.expanduser().resolve()
    if not source.is_file() or source.stat().st_size == 0:
        raise SystemExit('BLOCKED: source is not a nonempty regular file')
    if not model_dir.is_dir():
        raise SystemExit('BLOCKED: --model-dir must be an existing local directory')
    mlx_model = (model_dir / 'weights.safetensors').is_file() or (model_dir / 'weights.npz').is_file()
    if not ((model_dir / 'model.bin').is_file() or mlx_model) or not (model_dir / 'config.json').is_file():
        raise SystemExit('BLOCKED: local model directory must contain config.json and supported model weights')
    source_hash = digest(source)
    if output.exists():
        try:
            old = json.loads(output.read_text(encoding='utf-8'))
        except (OSError, json.JSONDecodeError):
            raise SystemExit('BLOCKED: transcript output exists but is unreadable; preserve and inspect it')
        if old.get('source_sha256') == source_hash and old.get('source_id') == args.source_id:
            print(json.dumps({'status': 'REUSED', 'output': str(output), 'source_sha256': source_hash}))
            return
        raise SystemExit('BLOCKED: transcript output exists for a different source; do not overwrite')

    if mlx_model:
        try:
            import mlx_whisper
        except ImportError:
            raise SystemExit('BLOCKED: mlx-whisper is not installed in this Python environment')
        # Use only the explicit existing local snapshot. Never resolve a repository or download weights.
        os.environ['HF_HUB_OFFLINE'] = '1'
        result = mlx_whisper.transcribe(str(source), path_or_hf_repo=str(model_dir),
                                       language=args.language, word_timestamps=True, verbose=False)
        serialized = [{
            'start_seconds': round(float(segment['start']), 3),
            'end_seconds': round(float(segment['end']), 3),
            'text': segment['text'].strip(),
            'words': [{'start_seconds': round(float(word['start']), 3),
                       'end_seconds': round(float(word['end']), 3), 'text': word['word']}
                      for word in segment.get('words', [])],
        } for segment in result['segments'] if segment['text'].strip()]
        model_engine, language, probability, vad = 'mlx-whisper', result.get('language'), None, False
    else:
        try:
            from faster_whisper import WhisperModel
        except ImportError:
            raise SystemExit('BLOCKED: faster-whisper is not installed in this Python environment')
        serialized, language, probability = faster_transcript(model_dir, source, args)
        model_engine, vad = 'faster-whisper', True
    if not serialized:
        raise SystemExit('BLOCKED: local transcription returned no speech segments')
    payload = {
        'source_id': args.source_id, 'source_file': source.name, 'source_sha256': source_hash,
        'model': model_engine, 'model_path': str(model_dir), 'language': language,
        'language_probability': probability, 'vad_filter': vad, 'word_timestamps': True,
        'transcription_status': 'completed; ASR accuracy not independently verified', 'segments': serialized,
    }
    atomic_json(output, payload)
    print(json.dumps({'status': 'TRANSCRIBED', 'segments': len(serialized),
                      'output': str(output), 'source_sha256': source_hash}))


def faster_transcript(model_dir, source, args):
    from faster_whisper import WhisperModel
    model = WhisperModel(str(model_dir), device='cpu', compute_type='int8',
                         cpu_threads=args.cpu_threads)
    segments, info = model.transcribe(str(source), language=args.language,
                                      vad_filter=True, word_timestamps=True,
                                      condition_on_previous_text=True)
    serialized = []
    for segment in segments:
        if not segment.text.strip():
            continue
        serialized.append({
            'start_seconds': round(float(segment.start), 3),
            'end_seconds': round(float(segment.end), 3),
            'text': segment.text.strip(),
            'words': [{'start_seconds': round(float(word.start), 3),
                       'end_seconds': round(float(word.end), 3),
                       'text': word.word}
                      for word in (segment.words or [])],
        })
    return serialized, info.language, info.language_probability


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        print('BLOCKED: transcription interrupted', file=sys.stderr)
        raise SystemExit(130)

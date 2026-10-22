"""Summarize timing-only companion logs without reading any credentials."""
import argparse
import json
import os
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--out', type=Path, required=True)
parser.add_argument('--logs', type=Path, default=Path(f'/tmp/whale-voice-{os.getuid()}'))
args = parser.parse_args()
args.out.mkdir(parents=True, exist_ok=True)
reports = []
for source in sorted(args.logs.glob('latency-*.jsonl')):
    events = [json.loads(line) for line in source.read_text().splitlines() if line]
    if not events:
        continue
    # Capture data as-is so incomplete/error runs cannot be mistaken for successful ones.
    (args.out / source.name).write_text(source.read_text())
    plays = [e for e in events if e['event'] == 'play_start']
    sentences = [e for e in events if e['event'] == 'sentence_ready']
    ready = {e['index']: e for e in events if e['event'] == 'tts_ready'}
    ends = {e['index']: e for e in events if e['event'] == 'play_end'}
    def gap_after(a, b):
        if 'duration_ms' in a:
            return max(0, b['elapsed_ms'] - a['elapsed_ms'] - a['duration_ms'])
        end = ends.get(a['index'])
        return max(0, b['elapsed_ms']-end['elapsed_ms']) if end else None
    reports.append({'file': source.name,
        'provider': next((e['provider'] for e in events if 'provider' in e), 'legacy_unknown'),
        'source': next((e['source'] for e in events if 'source' in e), 'legacy_unknown'),
        'transport': next((e['transport'] for e in events if 'transport' in e), 'legacy_unknown'),
        'complete': any(e['event'] == 'turn_complete' for e in events),
        'failed': any(e['event'] == 'failure' for e in events),
        'model_first_text_ms': sentences[0]['model_first_text_ms'] if sentences else None,
        'first_sentence_ms': sentences[0]['sentence_ms'] if sentences else None,
        'first_audio_ms': plays[0]['elapsed_ms'] if plays else None,
        'tts_ms': [ready.get(e['index'],{}).get('tts_ms',e.get('tts_ms')) for e in plays], 'gap_ms': [e['gap_ms'] for e in plays[1:]],
        'modes': ['pcm_stream' if e.get('streaming') else 'complete_audio' for e in plays],
        'first_packet_ms': [e['first_packet_ms'] for e in events if e['event']=='tts_first_audio'],
        'bridge_timings': [ready.get(e['index'],{}).get('bridge_timings',{}) for e in plays],
        'underruns': sum(e['event']=='stream_underrun' for e in events),
        'cached': [ready.get(e['index'],{}).get('cache_hit',e.get('cache_hit')) for e in plays],
        'overlap_count': sum(e['event'] == 'tts_start' and e.get('overlaps_playback',False) for e in events),
        'estimated_gap_ms': [gap_after(a,b) for a,b in zip(plays, plays[1:])],
        'played_sentences': len(plays),
        'audio_verified': len(plays) > 0 and any(e['event'] == 'turn_complete' for e in events)})
(args.out / 'summary.json').write_text(json.dumps(reports, ensure_ascii=False, indent=2) + '\n')
print(json.dumps(reports, ensure_ascii=False, indent=2))

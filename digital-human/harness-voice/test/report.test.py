"""Regression: streamed clips lack an upfront duration, unlike MP3 clips."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

class ReportTests(unittest.TestCase):
    def test_complete_and_streamed_gaps_use_their_own_clock(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            logs = root / 'logs'; logs.mkdir()
            common = [{'event':'sentence_ready','model_first_text_ms':100,'sentence_ms':200}]
            complete = common + [
                {'event':'play_start','index':0,'elapsed_ms':1000,'duration_ms':1500,'tts_ms':800,'cache_hit':False},
                {'event':'play_start','index':1,'elapsed_ms':2800,'duration_ms':1000,'tts_ms':100,'gap_ms':5,'cache_hit':True},
                {'event':'turn_complete'}]
            streaming = common + [
                {'event':'tts_first_audio','index':0,'first_packet_ms':300},
                {'event':'play_start','index':0,'elapsed_ms':600,'streaming':True,'tts_ms':300},
                {'event':'tts_ready','index':0,'tts_ms':900,'cache_hit':False,'bridge_timings':{'copy':120}},
                {'event':'stream_underrun','index':0},
                {'event':'play_end','index':0,'elapsed_ms':2100},
                {'event':'play_start','index':1,'elapsed_ms':2400,'streaming':True,'tts_ms':200,'gap_ms':300},
                {'event':'tts_ready','index':1,'tts_ms':600,'cache_hit':True,'bridge_timings':{}},
                {'event':'turn_complete'}]
            for name,events in [('complete',complete),('streaming',streaming)]:
                (logs / f'latency-{name}.jsonl').write_text(''.join(json.dumps(e)+'\n' for e in events))
            subprocess.run([sys.executable,str(Path(__file__).resolve().parents[1]/'report.py'),
                '--logs',str(logs),'--out',str(root/'report')],check=True,capture_output=True)
            a,b=json.loads((root/'report'/'summary.json').read_text())
            self.assertEqual(a['estimated_gap_ms'],[300])
            self.assertEqual(b['estimated_gap_ms'],[300])
            self.assertEqual(b['tts_ms'],[900,600])
            self.assertEqual(b['first_packet_ms'],[300])
            self.assertEqual(b['cached'],[False,True])
            self.assertEqual(b['modes'],['pcm_stream','pcm_stream'])
            self.assertEqual(b['underruns'],1)
            self.assertEqual(b['bridge_timings'][0],{'copy':120})

if __name__=='__main__':unittest.main()

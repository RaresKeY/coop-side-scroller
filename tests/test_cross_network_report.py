"""A failed startup must not advertise an old successful attempt as current."""
import json
from pathlib import Path
import tempfile
import types
import unittest
from unittest.mock import patch
import browser_cross_network as harness

class ReportTests(unittest.TestCase):
 def test_failed_startup_marks_new_attempt_without_erasing_historical_success(self):
  with tempfile.TemporaryDirectory() as folder:
   root=Path(folder)
   (root/'build').mkdir()
   historical=root/'build/cross-network.json'
   historical.write_text('{"result":"pass","historical":true}')
   (root/'build/cross-network-latest.json').write_text('{"result":"pass"}')
   def unavailable(): raise RuntimeError('controller unavailable')
   with patch.object(harness,'ROOT',root),patch('sys.argv',['test']),patch.dict('sys.modules',{'client':types.SimpleNamespace(Browser=unavailable)}):
    with self.assertRaises(RuntimeError): harness.run()
   latest=json.loads((root/'build/cross-network-latest.json').read_text())
   self.assertEqual(latest['result'],'running')
   self.assertGreater(latest['started_at_unix'],0)
   self.assertTrue(json.loads(historical.read_text())['historical'])

if __name__=='__main__':unittest.main()

"""Check the probe's HTTP boundary without launching a browser or services."""
import functools
import http.client
import http.server
from pathlib import Path
import tempfile
import threading
import unittest

from deterministic_browser import Handler


class BrowserProbeServerTests(unittest.TestCase):
    def test_get_and_head_share_the_resource_allowlist(self):
        with tempfile.TemporaryDirectory(prefix='deterministic-http-test-') as directory:
            root = Path(directory)
            (root / 'tests').mkdir()
            (root / 'tests/deterministic_browser.html').write_text('probe')
            (root / 'private.txt').write_text('private fixture')
            with http.server.ThreadingHTTPServer(('127.0.0.1', 0),
                    functools.partial(Handler, directory=directory)) as server:
                thread = threading.Thread(target=server.serve_forever, daemon=True)
                thread.start()
                try:
                    for method in ('GET', 'HEAD'):
                        for path, expected in (
                            ('/tests/deterministic_browser.html?test=1', 200),
                            ('/private.txt', 404), ('/', 404),
                            ('/tests/../private.txt', 404),
                        ):
                            with self.subTest(method=method, path=path):
                                connection = http.client.HTTPConnection('127.0.0.1', server.server_port, timeout=5)
                                try:
                                    connection.request(method, path)
                                    response = connection.getresponse()
                                    self.assertEqual(response.status, expected)
                                    response.read()
                                finally:
                                    connection.close()
                finally:
                    server.shutdown()
                    thread.join(timeout=5)


if __name__ == '__main__':
    unittest.main()

import pathlib, sys, unittest
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]))
from scanout import classify, scanout_value, extract_monitor
from directcast_lab import parse, build_gsr, build_ssh

class TestScanout(unittest.TestCase):
    def test_parse(self):
        self.assertIsNone(scanout_value(None))
        self.assertIsNone(scanout_value("nonsense"))
        self.assertIsNone(scanout_value("(nil)"))
        self.assertFalse(scanout_value("0"))
        self.assertFalse(scanout_value("0x0"))
        self.assertTrue(scanout_value("0x9a"))
    def test_consistent(self):
        self.assertEqual(classify({"directScanoutTo":"0x45","directScanoutBlockedBy":None})[0],True)
    def test_inconsistent(self):
        self.assertIsNone(classify({"directScanoutTo":"0x45","directScanoutBlockedBy":["RECORD"]})[0])
    def test_nonarray(self):
        with self.assertRaises(ValueError): extract_monitor('"bad"',"eDP-1")
    def test_missing_monitor(self):
        self.assertIsNone(extract_monitor('[]', 'eDP-1')["direct"])
    def test_target(self):
        args=parse(['--monitor','eDP-1','--ssh-host','neko7'])
        self.assertEqual(build_gsr(args)[build_gsr(args).index('-w')+1],'eDP-1')
        self.assertIn('127.0.0.1:11935:127.0.0.1:11935',build_ssh(args))
        self.assertNotIn('vulkan',' '.join(build_gsr(args)).lower())
        self.assertNotIn('portal',' '.join(build_gsr(args)).lower())
        self.assertIn('no',build_gsr(args))

if __name__ == '__main__': unittest.main()

from obs_stock_boundary import nft_guard_present

class TestStockObsGuard(unittest.TestCase):
    def test_expected_guard(self):
        raw = '''table inet splitcast-obs-websocket-guard {
          chain input {
            type filter hook input priority -150; policy accept;
            iifname != "lo" tcp dport 4455 counter packets 0 bytes 0 drop
          }
        }'''
        self.assertTrue(nft_guard_present(raw))
    def test_not_fooled_by_tailscale_accept(self):
        self.assertFalse(nft_guard_present('''table inet splitcast-obs-websocket-guard {
            chain input { type filter hook input priority -150; policy accept;
               iifname "tailscale0" accept
            }
        }'''))

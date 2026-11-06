import hashlib,subprocess,sys,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
TOOL=ROOT/'tools/invite_verifier.py'
class InviteVerifierTests(unittest.TestCase):
 def run_tool(self,args=(),value=''):
  return subprocess.run([sys.executable,str(TOOL),*args],input=value,text=True,capture_output=True)
 def test_protected_pipe_outputs_only_verifier(self):
  secret='K'*64
  result=self.run_tool(['--stdin'],secret+'\n')
  self.assertEqual(result.returncode,0)
  self.assertEqual(result.stdout,hashlib.sha256(secret.encode()).hexdigest()+'\n')
  self.assertNotIn(secret,result.stdout+result.stderr)
 def test_bad_inputs_and_argv_do_not_echo_private_values(self):
  for value,args in [('PRIVATE'*3,['--stdin']),('K'*64+'\tX',['--stdin']),('K'*64,[])]:
   result=self.run_tool(args,value)
   self.assertNotEqual(result.returncode,0)
   self.assertEqual(result.stdout,'')
   self.assertNotIn(value,result.stderr)
  secret='K'*64
  result=self.run_tool([secret])
  self.assertNotEqual(result.returncode,0)
  self.assertNotIn(secret,result.stdout+result.stderr)
if __name__=='__main__':unittest.main()

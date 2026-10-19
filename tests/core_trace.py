#!/usr/bin/env python3
import ctypes,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
lib=ctypes.CDLL(str(ROOT/'build/native/libember_core.so'))
lib.ec_v1_create.argtypes=[ctypes.c_uint32]*3;lib.ec_v1_create.restype=ctypes.c_void_p
lib.ec_v1_command.argtypes=[ctypes.c_void_p,ctypes.c_int32,ctypes.c_int32,ctypes.c_int32];lib.ec_v1_command.restype=ctypes.c_int32
lib.ec_v1_destroy.argtypes=[ctypes.c_void_p]
host=lib.ec_v1_create(0x10000,1,1);guest=lib.ec_v1_create(0x10000,2,2)
assert host and guest
hash_value=2166136261
trace=bytearray()
def cmd(h,op,a=0,b=0):return lib.ec_v1_command(h,op,a,b)
def transfer(source,target,sender):
 global hash_value
 while (size:=cmd(source,7))>0:
  assert cmd(target,4,sender,size)==0
  for i in range(size):
   value=cmd(source,8,i);trace.append(value);hash_value=((hash_value^value)*16777619)&0xffffffff
   assert cmd(target,5,i,value)==0
  assert cmd(target,6)==0
  assert cmd(source,9)==0
 while cmd(source,12)>0:cmd(source,13)
cmd(host,3,2,1)
for tick in range(600):
 cmd(guest,1,1000 if tick<144 else 0,2);cmd(guest,2);transfer(guest,host,2)
 cmd(host,1,0,0);cmd(host,2);transfer(host,guest,1)
result={'hash':hash_value,'tick':cmd(host,10,0),'hp':cmd(guest,10,1),'guest_x':cmd(guest,10,3,2)}
assert result['hp']==0
(ROOT/'build/core-trace.bin').write_bytes(trace)
(ROOT/'build/core-trace.json').write_text(json.dumps(result)+'\n')
print('native trace',result)
lib.ec_v1_destroy(guest);lib.ec_v1_destroy(host)

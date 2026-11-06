#!/usr/bin/env python3
"""Print only the server verifier for a random 256-bit playtest capability.

The input must have at least 32 cryptographically random bytes of entropy.
Human-chosen passwords require a password KDF and are not supported here.
"""
import argparse,getpass,hashlib,sys
def verifier(value):
    value=value.strip()
    if not 32<=len(value)<=128 or any(not 33<=ord(c)<=126 for c in value):
        raise ValueError("Expected a 32–128 character random invite key.")
    return hashlib.sha256(value.encode("ascii")).hexdigest()
class PrivateArguments(argparse.ArgumentParser):
    def error(self, _message):
        raise SystemExit("Use no arguments for masked input, or --stdin for a protected pipe. Never pass a key in argv.")
def main():
    p=PrivateArguments(description=__doc__)
    p.add_argument("--stdin",action="store_true",help="read a key from a protected pipe; never pass it in argv")
    args=p.parse_args()
    if args.stdin and sys.stdin.isatty():
        p.error("Use masked terminal input")
    if not args.stdin and not sys.stdin.isatty():
        p.error("No private terminal")
    value=sys.stdin.read(131) if args.stdin else getpass.getpass("Invite key: ")
    try: print(verifier(value))
    except ValueError:
        raise SystemExit("Expected a 32–128 character random invite key; no verifier written.")
if __name__=="__main__":main()

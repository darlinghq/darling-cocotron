import pathlib,shlex,subprocess,sys
build=pathlib.Path(sys.argv[1]).resolve();here=pathlib.Path(__file__).resolve().parent
lines=subprocess.check_output(['ninja','-C',str(build),'-t','commands','AppKit'],text=True).splitlines()
a=shlex.split(next(l for l in lines if ' -c ' in l and '/NSView.m' in l));flags=[a[0]];i=1
if '--baseline' not in sys.argv:flags.append('-I'+str(here.parents[1]/'AppKit/include'))
while i<len(a):
 if a[i] in ['-o','-c','-MT','-MF']:i+=2;continue
 if a[i] in ['-MD','-MMD']:i+=1;continue
 flags.append(a[i]);i+=1
subprocess.run(flags+['-fobjc-arc','-fsyntax-only',str(here/'client.m')],cwd=build,check=True)

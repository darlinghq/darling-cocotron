from pathlib import Path
import subprocess,json,sys
p=Path(sys.argv[1]);scale=int(sys.argv[2]);results=[];errors=[]
deep=len(sys.argv)>3 and sys.argv[3]=='deep'
expected={1:9600,2:9600,3:0,4:9600,5:0,6:9600,7:9600,8:7200,9:0,10:9600,11:168,12:0,13:168,14:0}
if deep:
 expected.update({1:7200,4:7200,6:7200,7:7200,15:0,16:0})
for stage,count in expected.items():
 image=p/f'{stage}.png';size=subprocess.check_output(['magick','identify','-format','%w %h',str(image)],text=True);width,height=map(int,size.split())
 data=subprocess.check_output(['magick',str(image),'-depth','8','RGB:-']);r={'stage':stage}
 checks=[('green',b'\x00\xff\x00',count),('blue',b'\x00\x00\xff',0 if stage in (5,12) else 6000)]
 if deep:checks += [('yellow',b'\xff\xff\x00',0 if stage in (5,12) else 2400),('magenta',b'\xff\x00\xff',0 if stage in (3,5,12) else (2500 if stage==8 else 4000))]
 for label,c,want in checks:
  points=[i//3 for i in range(0,len(data),3) if data[i:i+3]==c];xs=[i%width for i in points];ys=[i//width for i in points]
  r[label]={'pixels':len(points),'expected':want*scale*scale,'bbox':[min(xs),min(ys),max(xs),max(ys)] if points else None}
  if len(points)!=want*scale*scale:errors.append(f'{stage} {label}: {len(points)} != {want*scale*scale}')
 results.append(r)
(p/'pixels.json').write_text(json.dumps({'scale':scale,'results':results,'errors':errors},indent=2))
print(json.dumps({'pixel_assertions':sum(len(r)-1 for r in results),'failures':errors}));raise SystemExit(bool(errors))

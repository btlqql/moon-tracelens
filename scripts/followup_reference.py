"""Independent follow-up oracles over synthetic deterministic inputs."""
import collections,copy,hashlib,json,math,random,subprocess
from pathlib import Path
root=Path(__file__).resolve().parents[1]
random.seed(20261018)
def run(request, error=False):
    result=subprocess.run(['node',str(root/'_build/js/debug/build/cmd/main/main.js'),'-'],input=json.dumps(request),capture_output=True,text=True,encoding='utf-8',timeout=60)
    if error:
        assert result.returncode==1,(result.returncode,result.stdout); return
    assert result.returncode in (0,2),(result.returncode,result.stdout,result.stderr)
    return json.loads(result.stdout)

for _ in range(20):
    times=[random.randrange(-30,30)/2 for _ in range(40)]
    width=random.choice([0.5,1,2,4]); origin=0.5
    events=[{'timestamp':t,'message':'x','level':'info'} for t in times]
    report=run({'operation':'buckets','events':events,'width_seconds':width,'origin':origin})
    expected=collections.Counter(math.floor((t-origin)/width)*width+origin for t in times)
    assert {bucket['start']:bucket['metrics']['count'] for bucket in report['buckets']}==dict(expected)
    assert sum(b['metrics']['count'] for b in report['buckets'])==len(times)
print('Time buckets: 20 negative/fractional boundary histograms passed')

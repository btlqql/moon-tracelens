"""Independent Python standard library oracles; deterministic synthetic data."""
import csv, datetime, hashlib, heapq, io, json, math, random, subprocess
from pathlib import Path
root = Path(__file__).resolve().parents[1]
random.seed(20261005)
def run(request):
    result = subprocess.run(['node',str(root/'_build/js/debug/build/cmd/main/main.js'),'-'],
        input=json.dumps(request),capture_output=True,text=True,encoding='utf-8',timeout=30)
    if result.returncode: raise RuntimeError(result.stdout or result.stderr)
    return json.loads(result.stdout)

for i in range(50):
    zone = datetime.timezone(datetime.timedelta(minutes=random.randint(-720,840)))
    date = datetime.datetime(random.randint(1600,2300),random.randint(1,12),random.randint(1,28),random.randint(0,23),random.randint(0,59),random.randint(0,59),123000,tzinfo=zone)
    result = run({'events':[{'timestamp':date.isoformat(),'level':'info','message':'oracle'}]})
    assert abs(result['events'][0]['timestamp'] - date.timestamp()) < 0.00001
print('Python datetime oracle: 50 calendar/timezone/fraction cases passed')

# Revision oracle: compare service buckets using Python counts and nearest-rank percentiles.
random.seed(20261016)
def summary(events):
    durations=sorted(e['duration_ms'] for e in events)
    return {'count':len(events),'errors':sum(e['level']=='error' for e in events),
        'error_fraction':sum(e['level']=='error' for e in events)/len(events) if events else None,
        'duration_p95_ms':durations[math.ceil(len(durations)*0.95)-1] if durations else None}
for iteration in range(20):
    windows=[]
    for _ in range(2):
        windows.append([{'timestamp':i,'level':random.choice(['info','error']),'message':'sample',
            'service':random.choice(['a','b','c']),'duration_ms':random.randrange(100)} for i in range(random.randrange(20))])
    a,b=windows
    result=run({'operation':'compare','before':{'events':a,'group_by':'service'},'after':{'events':b,'group_by':'service'}})
    for side,events in [('before',a),('after',b)]:
        for key,expected in summary(events).items():
            actual=result['metrics'][side][key]
            assert actual==expected or (actual is not None and expected is not None and abs(actual-expected)<1e-12)
    for group in result['groups']:
        for side,events in [('before',a),('after',b)]:
            selected=[e for e in events if e['service']==group['key']]
            assert group['metrics'][side]['count']==len(selected)
            assert group['metrics'][side]['errors']==sum(e['level']=='error' for e in selected)
print('Independent comparison oracle: 20 window pairs, service alignment and p95 summaries passed')

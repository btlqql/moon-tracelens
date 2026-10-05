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

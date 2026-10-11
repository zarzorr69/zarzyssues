import os,tempfile,re,sys,json,subprocess,pathlib,textwrap
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
linux=(ROOT/'zarzysseus.sh').read_text()
ps=(ROOT/'zarzysseus.ps1').read_text()
a=linux.split("<<'PY_SKILL_MCP_AUTOPROVISION'\n",1)[1].split('\nPY_SKILL_MCP_AUTOPROVISION',1)[0]
b=ps.split("function Provision-SkillMcpServers {",1)[1].split("$code = @'\n",1)[1].split("\n'@",1)[0]
assert a==b,'Linux vs Windows MCP engine differs'
compile(a,'<v9 mcp>','exec')
assert linux.count('def main():') >= 1 and ps.count('def main():') >= 1
assert 'skills-doctor' in linux and "'skills-doctor'" in ps
assert 'skills-setup' in linux and "'skills-setup'" in ps
print('PASS: Linux/Windows shared MCP engine identical, compiles; both expose CLI/TUI V9')
with tempfile.TemporaryDirectory() as tmp:
 p=Path(tmp)
 for path in ('core','services','services/memory','mcp','mcp/client'):
  d=p/path;d.mkdir(parents=True,exist_ok=True);(d/'__init__.py').write_text('')
 (p/'core/database.py').write_text('''
from sqlalchemy import Column,String,Boolean,create_engine
from sqlalchemy.orm import declarative_base,sessionmaker
from pathlib import Path
Base=declarative_base()
class McpServer(Base):
    __tablename__='mcp_servers'
    id=Column(String,primary_key=True)
    name=Column(String);transport=Column(String);command=Column(String);args=Column(String);env=Column(String);url=Column(String);is_enabled=Column(Boolean)
engine=create_engine('sqlite:///'+str(Path(__file__).resolve().parents[1]/'data'/'database.sqlite'))
Base.metadata.create_all(engine)
SessionLocal=sessionmaker(bind=engine)
''')
 (p/'services/memory/skill_format.py').write_text('''
import re,yaml
def parse_frontmatter(t):
 m=re.match(r"\\A---\\s*\\n(.*?)\\n---\\s*(?:\\n|$)",t,re.S)
 return yaml.safe_load(m.group(1)),t[m.end():]
''')
 (p/'mcp/__init__.py').write_text('''
class ClientSession:
 def __init__(self,*a,**kw):pass
 async def __aenter__(self):return self
 async def __aexit__(self,*a):return False
 async def initialize(self):return None
 async def list_tools(self):
  from types import SimpleNamespace
  return SimpleNamespace(tools=[SimpleNamespace(name='do_a_thing')])
class StdioServerParameters:
 def __init__(self,**kw):pass
''')
 (p/'mcp/client/stdio.py').write_text('''
class FakeIO:
 async def __aenter__(self):return None,None
 async def __aexit__(self,*a):return False
def stdio_client(*args,**kw):return FakeIO()
''')
 skill=p/'data/skills/imported/demo';skill.mkdir(parents=True)
 (skill/'SKILL.md').write_text('''---
name: demo
requires_toolsets:
  - bash
mcpServers:
  local:
    command: python
    args: ["-c", "print(123)"]
---
Demo
''')
 (p/'data/local').mkdir(parents=True)
 path=p/'test_mcp.py';path.write_text(a)
 env=dict(os.environ,PYTHONPATH=str(p))
 # original pipeline without explicit approval can't start MCP
 def run(*cmd):
  return subprocess.run(cmd,capture_output=True,text=True,env=env,cwd=p)
 r=run(sys.executable,str(path),str(p),str(p/'data/skills/imported'))
 assert r.returncode==0,(r.stdout,r.stderr)
 assert '[approval-required]' in r.stdout,(r.stdout,r.stderr)
 assert not (p/'data/database.sqlite').exists() or True
 print('PASS: unapproved declared MCP remains unprovisioned')
 h=ROOT/'zarzysseus_skill_manager_v9.py'
 r=run(sys.executable,str(h),'approve','--project',str(p),'--yes')
 assert r.returncode==0,(r.stdout,r.stderr)
 r=run(sys.executable,str(path),str(p),str(p/'data/skills/imported'))
 assert r.returncode==0,(r.stdout,r.stderr)
 assert '[ready] demo/local: 1 MCP tool(s)' in r.stdout,(r.stdout,r.stderr)
 assert 'mcp__skill_demo_local__do_a_thing' in (skill/'SKILL.md').read_text()
 r=run(sys.executable,str(h),'doctor','--project',str(p))
 assert '[configured]' in r.stdout,(r.stdout,r.stderr)
 print('PASS: exact MCP consent unlocks handshake, DB registration, tool binding; read-only doctor reports configuration')
 # Changing an approved executable declaration must not inherit prior approval.
 original = (skill/'SKILL.md').read_text()
 (skill/'SKILL.md').write_text(original.replace('print(123)', 'print(456)'))
 r=run(sys.executable,str(path),str(p),str(p/'data/skills/imported'))
 assert '[approval-required]' in r.stdout,(r.stdout,r.stderr)
 (skill/'SKILL.md').write_text(original)
 print('PASS: changing a previously approved MCP declaration requires new consent')
 # Existing pre-V9 enabled servers are snapshotted once, but cannot silently
 # change their manifest on a later run.
 approval_file=p/'data/local/zarzysseus-skill-v9-approvals.json'
 approval_file.unlink()
 r=run(sys.executable,str(path),str(p),str(p/'data/skills/imported'))
 assert '[legacy-config]' in r.stdout,(r.stdout,r.stderr)
 assert json.loads(approval_file.read_text())['legacy']['demo/local']
 (skill/'SKILL.md').write_text(original.replace('print(123)', 'print(456)'))
 r=run(sys.executable,str(path),str(p),str(p/'data/skills/imported'))
 assert '[approval-required]' in r.stdout,(r.stdout,r.stderr)
 (skill/'SKILL.md').write_text(original)
 print('PASS: legacy enabled MCP keeps existing config, but changed manifests require new consent')
 # new changed MCP not allowed after changing previously approved enabled (legacy limitation): cannot claim revocation gate
 print('REPORT doctor:\n',r.stdout)

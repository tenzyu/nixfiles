import pathlib,subprocess,tempfile,os,json,re,sys
old,new=map(pathlib.Path,sys.argv[1:])
def instrument(src):
    s=src.read_text()
    # The package prepends its runtime PATH. Replace just that generated line,
    # and the two real privileged executables, before any script is executed.
    for pattern,replace in [
        (r'^export PATH=.*$', 'export PATH="$MOCK_PATH"'),
        (r'^readonly minecraft_operator=.*$', 'readonly minecraft_operator="$MOCK_OPERATOR"'),
        (r'^readonly operator_sudo=.*$', 'readonly operator_sudo="$MOCK_SUDO"'),
    ]:
        s,n=re.subn(pattern,lambda _:replace,s,flags=re.M)
        assert n==1,(src,pattern,n)
    return s
with tempfile.TemporaryDirectory() as d:
    p=pathlib.Path(d); trace=p/'trace'; sudo=p/'sudo'; op=p/'mc-op'; date=p/'date'
    sudo.write_text('''#!/bin/bash
printf 'sudo' >> "$TRACE"
printf ' %q' "$@" >> "$TRACE"; printf '\\n' >> "$TRACE"
case "$*" in
  'systemctl is-active --quiet '* ) exit "$HOST_STATUS";;
  *'systemctl is-active --quiet '* ) exit "$GUEST_STATUS";;
  *'systemctl start '*-update ) exit "$UPDATE_STATUS";;
  'test -d '* ) exit "$DIR_STATUS";;
  *'tar -C '* ) exit "$TAR_STATUS";;
  * ) exit 0;;
esac
''')
    op.write_text('''#!/bin/bash
printf 'mc' >> "$TRACE"; printf ' %q' "$@" >> "$TRACE"
printf '\\n' >> "$TRACE"; exit 0
''')
    date.write_text('#!/bin/bash\necho 20261127-000000\n')
    for x in (sudo,op,date):x.chmod(0o755)
    scripts=[]
    for label,source in [('old',old),('new',new)]:
        q=p/label;q.write_text(instrument(source));subprocess.run(['/bin/bash','-n',q],check=True);scripts.append(q)
    scenarios=[]
    for game in ['ark','rust','minecraft','bogus']:
        for action in ['status','start','stop','restart','logs','ip','console','send','diagnose','exec','update','backup','unknown']:
            for enabled,states in [(True,(0,0,0,0,0)),(False,(1,1,0,0,0)),(True,(0,0,1,0,1)),(True,(0,0,0,1,0))]:
                args=[action,game]+(['echo','two words'] if action=='exec' else ['say hi'] if action=='send' else [])
                scenarios.append((enabled,args,states))
    for enabled in [True,False]:
        for args in [[],['help'],['status'],['list'],['exec','ark'],['start'],['status','']]:
            scenarios.append((enabled,args,(0,0,0,0,0)))
    mismatches=[]; trace_cases=0
    for enabled,args,states in scenarios:
        env={'PATH':str(p)+':/usr/bin:/bin','MOCK_PATH':str(p)+':/usr/bin:/bin','TRACE':str(trace),'MOCK_SUDO':str(sudo),'MOCK_OPERATOR':str(op) if enabled else ''}
        env.update(zip(['HOST_STATUS','GUEST_STATUS','UPDATE_STATUS','DIR_STATUS','TAR_STATUS'],map(str,states)))
        outcomes=[]
        for s in scripts:
            trace.write_text('')
            r=subprocess.run(['/bin/bash',s,*args],env=env,capture_output=True,timeout=5)
            err=re.sub(r'SCRIPT: line \d+:','SCRIPT: line N:',r.stderr.decode().replace(str(s),'SCRIPT'))
            outcomes.append((r.returncode,r.stdout.decode(),err,trace.read_text()))
        trace_cases+=bool(outcomes[0][3])
        if outcomes[0]!=outcomes[1]:mismatches.append((enabled,args,states,outcomes))
    report={'scenarios':len(scenarios),'mismatches':len(mismatches),'traceCases':trace_cases,'examples':mismatches[:5]}
    pathlib.Path('evidence/dispatch.json').write_text(json.dumps(report,indent=2))
    print(json.dumps(report))
    assert trace_cases>0 and not mismatches

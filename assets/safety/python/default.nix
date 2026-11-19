{runCommand}:
runCommand "safety-python" {} ''
  mkdir -p "$out"
  cp ${./safety_operations.py} "$out/safety_operations.py"
''

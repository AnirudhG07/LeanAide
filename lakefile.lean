import Lake
open Lake DSL

package LeanCodePrompts{
  precompileModules := true
}

@[default_target]
lean_lib LeanCodePrompts {
}

lean_exe datagen{
  supportInterpreter := true
}

lean_exe elabdatagen{
  supportInterpreter := true
}

@[default_target]
lean_exe bulkelab {
  supportInterpreter := true
}

lean_exe thmextract {
  supportInterpreter := true
}


lean_exe bulkchk{
  supportInterpreter := true
}

lean_exe lib4chk{
  supportInterpreter := true
}

lean_exe annotatekwds{
  supportInterpreter := false
}


lean_exe batchcheck{
  supportInterpreter := true
}

lean_exe constnames{
  supportInterpreter := true
}

lean_exe depnames{
  supportInterpreter := true
}

@[default_target]
lean_exe chkthms{
  supportInterpreter := true
}

lean_lib examples

require mathlib from git
  "https://github.com/leanprover-community/mathlib4.git"@"415530d447d2fc6557f3ed00caf409dd391e0756"

require mathlib3port from git
  "https://github.com/leanprover-community/mathlib3port.git"@"120d183ebd8c91a7ebbcb754d49aa1d7f696ee48"

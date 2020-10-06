# Practical RPC - Rpc framework
# GNU Lesser General Public License, version 2.1
#
# Copyright © 2020 Trey Cutter <treycutter@protonmail.com>

import macros

macro expect*(cond: untyped): untyped =
  var
    infix = nnkInfix.new_tree(cond[0], cond[1], cond[2])
    v = cond[1]
    e = cond[2]

  result = quote do:
    if (`infix`) == false:
      echo "Expectation " & astToStr(`infix`) & " failed"
      quit astToStr(`v`) & " is " & $`v` & "\n" & astToStr(`e`) & " is " & $`e`

# Package

version = "0.1.0"
author = "Trey Cutter"
description = "Practical RPC"
license = "LGPL-2.1"

backend = "cpp"

requires "nim >= 1.0.4"

import strutils
from os import walkDirRec
from system import gorge_ex

task tests, "Run all tests":
  for path in walkDirRec("tests"):
    if path.contains(".nim"):
      if path.contains("utils.nim"):
        continue
      let (output, code) =
        gorge_ex "nim c -r --hints:off " & path

      var rpath = path
      rpath.remove_suffix(".nim")
      if code == 0:
        echo " \e[0;32m\u2713\e[0m " & rpath
      elif code == 1:
        echo " \e[0;31m\u2717\e[0m " & rpath
        echo "OUTPUT: \n" & output
        break



